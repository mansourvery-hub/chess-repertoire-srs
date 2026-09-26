# Audit fixes shipped without a test that fails without them

Five of the fixes in this series are shipped on reasoning rather than on a
regression test. This records what each one does, what evidence exists, and what
would close the gap. It exists so the caveat is not something a future reader has
to rediscover from a commit message.

None of these is a suspected defect. They are unproven.

## M3 — engine subscription is cancelled on supersession

**The fix.** `position_evaluator.dart:583` cancels `_searchInfoSubscription`
when a search is superseded. A superseded search kept reporting until its own
bestmove, and nothing was listening for it.

**Evidence.** The generation tag and the `_isCurrentSearch` guard around it are
covered by a test that fails without them. The subscription cancel is not.

**What would close it.** A fake engine that lets a test hold a search open,
supersede it, then deliver a bestmove and assert no state change. The fake
engine infrastructure exists; what is missing is a lever to deliver a bestmove
on demand.

**Risk if wrong.** Low. The cancel is a resource-hygiene call, not a correctness
one, and a redundant live subscription cannot produce a wrong evaluation —
worst case it wastes work.

## M4 — cloud evaluation subscribes before it sends

**The fix.** The offline cloud evaluation subscribes to the socket before sending
the request, so a reply landing in the gap is not dropped; the HTTP variant gets
a 5-second deadline and a request generation.

**Evidence.** None discriminating. The original defect is a race whose window is
the gap between two adjacent statements, which a test has to win deliberately.

**What would close it.** A fake socket that delivers the reply synchronously from
`send`, so the reply provably arrives before the subscription existed in the old
ordering. That turns the race into a determinism problem.

**Risk if wrong.** Low to moderate. The timeout and generation are independently
defensive. The subscribe-first change is the one that matters and the one that is
unproven.

## M6 — threefold repetition compares full position identity

**The fix.** Repetition compares the 4-field FEN rather than piece placement, so
the same pieces with the other side to move, different castling rights or a
different en-passant square are not the same position.

**Evidence.** None. Two attempts failed and both were removed. The first used a
knight shuffle, which was vacuous: moving a knight and a bishop out and back
preserves castling rights, so the position genuinely *was* identical and neither
the old nor the new code triggered.

**What would close it.** A king shuffle, because moving the king and back
destroys castling rights permanently while leaving the board identical. That
produces three board-identical positions of which only one is the same position.
It needs the sequence played twice to reach three occurrences, and both sides
must return to their starting squares — which means scripting the engine, and
the existing fakes control the NNUE weights rather than the search.

**Risk if wrong.** Very low. QUALITY.md §2.3 requires identity to account for
side to move, castling and en-passant, so this is compliance with a written
invariant rather than a judgement call. It is in the offline move path, which is
why it is worth a test eventually.

## M10 — retry persists its side effects

**The fix.** `review_service.dart:256` persists `result.sideEffectStates` and
rolls the session back if the write fails, mirroring `submitMove`.

**Evidence.** None. Three attempts failed. In every scenario that could be built,
a correct retry produced no side-effect states at all, so the fix was never
exercised.

**What would close it.** An answer, not a test: either a reachable path where a
correct retry produces side effects, or a determination that none exists. The
honest way to settle it is to instrument `retryMove` once across the existing
review suite and count non-empty `sideEffectStates`, rather than to guess at
scenarios a fourth time.

**Risk if wrong.** Low. The call is guarded by `isNotEmpty`, so when the list is
empty nothing happens and it cannot corrupt anything. If the path is reachable
and was missed, the fix closes it; if it is unreachable, the fix is inert until
something makes it live.

## M15 — large imports hash off the UI isolate

**The fix.** `importPgnText` uses the existing `computePgnHashAsync` helper
instead of hashing synchronously before the large-import branch.

**Evidence.** Not obtainable in this harness. The helper short-circuits to the
synchronous path under `FLUTTER_TEST`, so the worker path cannot be reached from
a test suite. The test that exists pins that the helper agrees with the
synchronous one, which is what would break duplicate detection — it does not
show that work left the UI isolate.

**What would close it.** A test that observes the isolate boundary, which means
either removing the `FLUTTER_TEST` short-circuit for this path or asserting on
the helper's internals. Neither is worth it for a two-line change that reuses a
helper whose contract is already pinned elsewhere.

**Risk if wrong.** Very low. The helper is the one the codebase already provides
for exactly this, and it is covered where the behaviour is observable.

## Summary

| Item | Unproven part | Risk if wrong | Closable in this harness |
|---|---|---|---|
| M3 | subscription cancel | low — hygiene only | yes, needs a bestmove lever |
| M4 | subscribe-before-send | low–moderate | yes, needs a synchronous fake socket |
| M6 | repetition identity | very low — spec-mandated | awkward, needs a scripted engine |
| M10 | retry side effects | low — inert when empty | needs instrumentation, not a test |
| M15 | isolate offloading | very low | no — unreachable under test |

Two of the five (M6, M15) are better argued from the spec and from the helper's
existing contract than from a test, and I would not spend more on them. M3 and
M4 are genuinely closable and are worth doing when someone has an afternoon.
M10 needs one instrumentation run to settle whether it is live or dead code, and
that answer is worth more than another test attempt.
