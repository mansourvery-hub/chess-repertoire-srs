# H4 — credential redaction in logs: specification

Status: **specified, not implemented.** Audit finding H4 in `audit.md` is open and
this document is the contract for closing it. It exists because an earlier partial
implementation was lost, and a specification that outlives an implementation is
cheaper to rebuild from than to reconstruct from a diff.

**Check for a recovered implementation before writing one.** If the work that was
in flight is recovered from an editor's local history or a filesystem snapshot,
compare it against this document rather than replacing it — it may already cover
sites listed here as open.

## What is exposed, precisely

Three secrets reach durable storage:

| Secret | Where it is placed | How long it lasts |
|---|---|---|
| One-time login code | `email`, `username` and `code` in the **query string** of `/auth/mobile-code/bearer` | Seconds to a minute |
| Email address and username | Query string of `/auth/mobile-code/email` and `/auth/mobile-code/bearer` | Durable identifier |
| FCM registration token | **URL path** of `/mobile/register/firebase/<token>`, and logged verbatim | Long-lived device credential |

## Where it lands

Verified against `main` at `384157a64`. Two SQLite tables, both with a 7-day TTL
(`httpLogTTL`, `appLogTTL` — `lib/src/db/database.dart:18-19`):

- **`http_log`** — one row per request, with the complete URL
  (`lib/src/network/http.dart:115`, `requestUrl: request.url`). Every query
  parameter and every path segment is therefore stored verbatim.
- **`app_log`** — fed from `Logger.root.onRecord`
  (`lib/src/model/log/app_log_service.dart:66`), so every log line, including the
  FCM token line, is persisted.

Both are readable in-app: Settings → HTTP log, and Settings → app logs.

**It does not leave the device.** `app_log_service.dart:85-86` forwards records to
Firebase Crashlytics only when the logger is in
`_loggersReportedToCrashlytics` **and** the level is `SEVERE` or above. Every site
listed below logs at `INFO`, `FINEST` or `WARNING`, so none of them qualifies.
This is worth stating precisely, because the natural assumption — that anything
logged is shipped to a third party — is wrong here, and overstating it would
misdirect the fix. The exposure is local persistence plus in-app visibility, not
remote disclosure.

## The sites

Nine, in three groups. Line numbers as of `384157a64`; all confirmed present.

### 1. The request logger (`lib/src/network/http.dart`)

| Line | What it records |
|---|---|
| 115 | `requestUrl: request.url` — the structured `http_log` row. **The most important one**: durable, queryable, and shown in a UI. |
| 457 | `LichessClient` request line: method, full URL, User-Agent |
| 478 | `LichessClient` failure line, full URL |
| 599 | `DefaultClient` request line: method, full URL, User-Agent |
| 609 | `DefaultClient` failure line, full URL |

### 2. Credentials deliberately placed in URLs

| Location | What |
|---|---|
| `lib/src/model/auth/auth_repository.dart:107` | `lichessUri('/auth/mobile-code/email', {'email': …, 'username': …})` |
| `lib/src/model/auth/auth_repository.dart:135-139` | `lichessUri('/auth/mobile-code/bearer', {'email': …, 'username': …, 'code': …})` — the OTP |
| `lib/src/model/notifications/notification_service.dart:471` | `post(Uri(path: '/mobile/register/firebase/$token'))` — the FCM token as a path segment |

These cannot be fixed by redacting at the logger: the secret is in the URL the
client must send. Redaction has to happen on the way *into* storage.

### 3. Secrets written straight to the log

| Location | What |
|---|---|
| `lib/src/model/notifications/notification_service.dart:465` | `_logger.info('will register fcmToken: $token')` |

## What to build

**One redaction helper, used everywhere.** There was a `redactUriForLogging`
helper in the lost work. Its shape was right; keep the idea.

1. **A `redactUriForLogging(Uri)` helper in `lib/src/network/http.dart`.** Given a
   URI, return a loggable one with sensitive parts replaced. Rules:
   - Query parameters whose name matches a denylist (`code`, `token`, `email`,
     `username`, `password`, `secret`, `otp`) → `***`. An allowlist is safer than a
     denylist here, since a new secret-bearing parameter would otherwise leak by
     default.
   - Path segments that look like credentials — in practice the FCM token at
     `/mobile/register/firebase/<token>` → `***`. Prefer matching the known route
     over guessing "long opaque segment", which would mangle ordinary paths.
   - Everything else preserved. Logs are for diagnosis; a redaction that destroys
     the path makes the log useless.
2. **Apply it at all five `http.dart` sites**, including the `http_log` row at
   line 115. The stored row is the one with the longest life.
3. **Delete or rewrite the FCM log line at `notification_service.dart:465`.** It is
   the one place a secret is logged rather than merely URL-borne. Logging
   "registering an FCM token" carries the same diagnostic value.
4. **Leave the two `auth_repository` URLs alone.** The client must send the real
   values. The fix is at step 2 — the request logger redacts them on the way to
   storage. Note this explicitly, because "fix the auth URLs" reads like the
   obvious move and would break login.

## Tests to write

Assert on the *absence of secrets*, not the presence of a redaction marker — the
marker is an implementation detail, and a test coupled to it will be rewritten
when the format changes.

- **The unit test for the helper**, over a table of cases: each sensitive
  parameter redacted, ordinary ones (`max`, `moves`, `lastFen`, `until`) left
  alone, FCM path redacted, nested/unknown parameters handled, and a URI with
  nothing sensitive returned **unchanged** so ordinary logging is unaffected.
- **An end-to-end assertion that no secret reaches storage.** Drive a login-code
  request and an FCM registration through the real client with a mock transport,
  then read `http_log` and `app_log` and assert the code, the email and the token
  appear in **no** row. This is the test that actually pins the finding, and the
  one the audit asked for.
- **A guard on the logger wiring**, so a future logging site added without
  redaction fails: assert that `http.dart` has no unredacted `${request.url}`
  interpolation outside the helper. This is the same source-scanning approach as
  `test/platform/verified_link_claims_test.dart` and
  `test/platform/oauth_callback_identity_test.dart` — the codebase already accepts
  this shape of test, and it is what stops the fix rotting one call site at a time.

## Decisions for the owner

- **Should `http_log` store redacted URLs at all?** It is a diagnostic log, and
  redacted URLs remain useful. But if the value of `http_log` is only
  troubleshooting, a shorter TTL or an opt-in toggle would cut exposure further.
  This is a product call, not a technical one.
- **Should the FCM token be redacted in the log row, or the registration request
  excluded from `http_log` entirely?** Excluding it is a smaller surface and loses
  the ability to debug registration failures; redacting keeps the request visible.
  Both are defensible.
- **Is a Crashlytics-side check warranted?** Not for these sites today, per the
  level gate above. Worth confirming that `_loggersReportedToCrashlytics` contains
  no logger that might later log at `SEVERE` with a URL in the message.

## What is not in scope

- **H2** (auth transitions not generation-fenced) and **H3** (credentials on
  cross-host requests) are separate findings. H3 is already fixed: the
  `Authorization` header is gated on `isMainHost` at `http.dart:442`.
- **`authorization` headers** are not currently logged, so there is nothing to
  redact. If header logging is ever added, it needs the same treatment.
- **The `message` field of a Crashlytics report** is a separate path with a
  separate 7-day-or-longer retention story. Out of scope here, and worth its own
  look.
