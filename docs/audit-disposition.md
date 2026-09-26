# Audit disposition

The 37 findings in `audit.md`, and what became of each. `audit.md` itself is
accurate as a *description* of the problems but its status is out of date — it was
written against a tree that has since changed substantially, and several of its
line references no longer point at the code it describes.

This file is the record of what was verified and what was decided. It exists so
the next person does not have to re-derive it from eleven pull requests, and so
the reasoning behind the judgement calls is available rather than implied.

**How to read the categories.** *Fixed* means the code changed. *Closed* means no
code change was warranted — the finding was already handled, was inherited
upstream unchanged, or was wrong. *Out of scope* means the underlying behaviour is
real but is upstream's and was deliberately left alone. *Open* means it still
needs a decision or work this session could not do.

## Summary

| | Count |
|---|---|
| Fixed | 22 |
| Closed without a change | 9 |
| Out of scope by the inherited-code rule | 4 |
| Open | 2 |
| **Total** | **37** |

Two findings are counted in *closed* but are softer than the rest: **M23**, where
only one of three sub-claims was in scope, and **H1**, where the audit's evidence
was stale and the finding was overruled rather than fixed.

## Fixed

| # | Finding | Change |
|---|---|---|
| H5 | Review answers mutate the session before persistence | Roll back the in-memory session when the write fails |
| H6 | Offline game work not fenced to its game | Generation counter on the game controller |
| H7 | Canonical review identity is lossy | Identity is the full answer set; v14 rekey migration |
| H8 | Study collaboration ignores incoming edits | Apply promote, delete, anaMove, anaDrop |
| H9 | Socket queue survives an account change | Drop both queues on auth change |
| M1 | Server-analysis stale-request race | Request generation |
| M2 | Socket version gaps retried without recovery | Reconnect from the last committed version |
| M3 | Engine callbacks outlive the request | Fence to the generation that started the work |
| M4 | Cloud eval uncorrelated | Generation, 5s deadline, and a test that a reply arriving before a listener is dropped |
| M7 | Chapter selection on the wrong chapter | Publish the chapter that was switched to |
| M8 | Review scope reloads commit out of order | Generation on both `ReviewService` and the controller |
| M9 | Retry loses quota credit | Retries count toward the daily quota |
| M11 | v10 migration has no backfill | v14 rekey with backfill |
| M12 | PGN orientation ignores starting side | Honour the side the line starts on |
| M13 | Malformed PGN reported as success | Refuse to store an untrainable study |
| M14 | Duplicate identity ignores side | Side-aware lookup in SQL, without a hash format change |
| M21 | Share extension uses the wrong UTI | Aligned identifiers across plist, manifest and Swift |
| M22 | Opening DB script can leave it empty | Build to temp, validate, atomically replace |
| M25 | `expectedLength` not enforced | Hold downloads to the expected length |
| L1 | Log paginators permit duplicate loads | In-flight guard |
| L2 | Engine offered on unsupported platforms | `isLocalEngineOffered` gates on platform |
| L3 | Truncated links throw silently | Guard the missing path segments; refuse non-web `open-web` targets |
| — | *Not in the audit:* "rate this app" opened the upstream app | Derive store links from this app's own identity |
| — | *Not in the audit:* accent selection was never persisted | Stored with the other general preferences |

## Closed without a change

**H1 — OAuth callback scheme.** The audit reported the Dart side building
`org.lichess.mobile://login-callback` while the native apps registered
`org.chesssrs.app`. Not so: `constants.dart` has carried `org.chesssrs.app` since
the first fork commit, and `kOAuthRedirectUri` is derived from it. What was missing
was a check, so one was added asserting all three agree — it fails if a future
rename reaches one and not the others.

**H3 — credentials on cross-host requests.** Already fixed by the fork: the
`Authorization` header is gated on `isMainHost` at `http.dart:442`, and the fork
went further, also gating the User-Agent identity and the server-status check.

**H2 — auth transitions not fenced.** Also already fixed by the fork, and the
fixing is thorough: `AuthController` carries a generation, `checkToken` captures it
before the network call and re-checks both it and the token's identity afterwards,
`signOut` re-checks around its 500ms delay, and concurrent validations for one
token are de-duplicated. The 401 handler passes the *captured* user, so a stale
response cannot act on a newer session — which was the finding's central claim.
None of it was tested, and the 401 path is unawaited by design, so a test now pins
it. The first version of that test passed for the wrong reason: the provider is
`autoDispose`, and a bare read with no listener collects it immediately, so
`checkToken` returned before doing anything at all.

**H4 — credentials in logs.** Was open; a partial implementation was lost before
this audit pass reached it. Specified in `h4-credential-redaction.md` and
implemented. Three secrets reached two SQLite tables: the one-time login code, the
email and username, and the FCM token. Note the severity is narrower than it first
appears — Crashlytics forwarding requires `SEVERE` or above and every affected
site logs below that, so this was local persistence plus in-app visibility, not
remote disclosure.

**M18 — history providers retain old pages.** Not reachable. `_list` is cleared in
`ref.onDispose`, and `onDispose` fires on rebuild as well as on disposal, so a
rebuild does not carry pages across. Confirmed by instrumenting a notifier: the
instance is reused across the rebuild, yet the accumulated list holds only the
newest build's entry. A test now pins the account-switch behaviour.

**M16 — opening explorer off by one.** Not a defect. `UciPath.penultimate` returns
empty for a single-pair path, so a "walk to root" loop stops one node short by
design.

**M5 (terminal-position half) and M6 (material accounting).** Both inherited from
upstream unchanged. M5's terminal half would also have required a product
decision — reject or normalise — which is not this session's to make.

**M17 — game-history pagination.** Every one of its six sub-claims is accurate as
a code fact, and every one is inherited unchanged: `page()` and `setFilter()` are
byte-identical to upstream. Four are additionally unreachable, because nothing in
this fork writes the game-storage table — upstream's `_storeGame` lived in
`game_controller.dart`, which the fork deleted. One sub-claim is simply wrong: it
says profile users "always take the network branch, even when offline", and the
code does the opposite.

## Out of scope by the inherited-code rule

These are real behaviours, upstream's, and left alone deliberately. Changing any of
them is a conscious divergence and should be recorded as one.

**M10 and M15** ship unproven. M10's retry path was settled by instrumentation —
the path is live and the fix is not dead code — but no test proves it, because
every attempt built a session where the retry had nowhere to advance to. M15's
hash-offloading is unproven and unreachable under test. Both are recorded in
`audit-unverified-fixes.md`.

**M23, two of three sub-claims.** The audit also reported that preference writes
are unserialized and that `SessionPreferencesStorage` does not fence a write to the
account that requested it. Both are inherited unchanged — the fork's diff to
`preferences_storage.dart` is import renames, enum syntax and two dropped upstream
categories, and the `save`/`fetch` bodies do not appear in it. The lost toggle is a
real bug; it is not a regression this fork introduced. Only the accent claim was in
scope, and it is fixed.

**M24 — no deadline on `DefaultClient`.** Accurate, and asymmetric:
`LichessClient.send` has a 15s `defaultRequestTimeout` and `DefaultClient.send` has
none. `DefaultClient.send` is inherited unchanged, and no project invariant
requires a deadline — `QUALITY.md` §3 covers PGN degradation and deterministic
clocks, §4 is performance.

**Worth the owner's judgement anyway**, because this fork amplifies the
consequence: it is local-first, and the opening database, NNUE weights and Maia
book all download through the client with no deadline, where upstream's traffic is
mostly short cloud calls. A stall there leaves the app waiting with no way out. The
change would be one line — give `DefaultClient` the timeout its sibling has.

## Open

**M19 — the local game cache has no writer.** Upstream's `_storeGame` was in a file
the fork deleted, so the cache is never populated. Three possible resolutions
(cache everything, cache above a size threshold, drop the offline promise) with
different consequences, so it is a product decision rather than a bug. Likely moot
if the game-import design is adopted.

**M20 — App Links identity.** The code half is done: the app no longer claims
verified `lichess.org` links it cannot be verified for, since the published
association files name the official Lichess identity. The records themselves are
the open half and need domain control plus App Store Connect.

**`firebase_options.dart` still declares `iosBundleId: 'org.lichess.mobileV2'`.**
Found while fixing H1 and not in the audit. It is a generated file, so the fix is a
Firebase-console decision about which project owns iOS telemetry; a code edit would
be overwritten on the next regeneration.

## One unresolved thread

`test/app_test.dart` — the startup token check — is **still skipped**, and the
cause is not fully established. What is now known, from CI logs rather than
inference:

- The original quarantine blamed a harness difference and concluded the mock was
  not intercepting. That was wrong: with a `quick_actions` channel mock added (a
  real harness gap, since fixed in `test/binding.dart`), the mock demonstrably
  intercepts on the runner.
- With that fixed, the failure becomes the original assertion: `Expected: <1>
  Actual: <0>`. The mock serves three requests on the runner — a connectivity
  probe, a logo, an FCM registration — and `/api/token/test` appears **zero times**
  in the whole run, while the assertion that the stored token was read back
  *passes*.
- On a developer machine the same mock serves the token check, plus `/api/account`.

So the request is genuinely never issued on the runner while the token is read.
That is an environmental difference in the startup path, not in the auth logic, and
it has not been isolated. The test now records every request the mock serves and
reports them on failure, so the next attempt starts from evidence rather than a
guess. Two earlier attempts reasoned about the request and were wrong.

## What the ratings were worth

Six findings marked "High confidence" turned out to be already fixed (H1, H3, H4),
inherited-and-unreachable (M17), or wrong as written (M18, and one M17 sub-claim).
None of the ones that turned out to be live defects was found by trusting the
rating.

What did correlate was **file-level evidence pointing at fork-introduced code**.
That is the heuristic worth applying to a future audit of this fork, and it is
recorded in `AGENTS.md` for the same reason.
