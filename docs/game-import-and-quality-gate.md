# Game Import and the Import Quality Gate

Status: **proposal.** Not in scope. Nothing here is implemented or decided.

## Goal

Two related ideas, from the owner:

1. **Import individual lichess games** as a way to grow opening repertoire. Ten French
   games should give a more complete French opening review than one does.
2. **Analyse on import by default** (disable-able). The opponent may make as many
   mistakes as they like; the repertoire side may not. Every imported PGN is meant
   for learning, and learning from poor moves is self-defeating. Not "play the
   engine's first choice every time" — the bar is "not terrible chess, loosely
   defined."

## What already exists

Verified, so none of this is rebuilt:

- **Importing a single game's PGN already produces one chapter**
  (`pgn_importer.dart:278,285`). One game in, one chapter out.
- **Only the repertoire side's moves become questions.** `_deriveDecisions` creates a
  decision where `nodeSideToMove == repertoireSide`; the opponent's moves are
  auto-traversed during review rather than drilled. The asymmetry is already the design.
- **Divergent imports merge into a wider answer set.** A position's canonical identity
  covers its *complete* accepted-move set, not one representative move. Import ten games
  and positions where they agree yield one question with one answer; positions where
  they diverge yield one question with every answer they played. "A more complete
  opening review" is what the model already does — it is not a feature to build.
- **Analysis on load already fires.** `study_controller.dart:301` calls `requestEval()`
  when the engine is available, gated by `alwaysRequestCloudEval`, which is currently
  hardcoded `false`. A past commit set it false deliberately, to avoid delaying local
  analysis.

## Open questions

These block the design. They are not implementation details.

### 1. Analysis results are not persisted — the load-bearing one

`repertoireNodeToJson` (`json_adapters.dart:22`) stores id, FEN, FEN key, incoming move,
comment and children. **No evaluation.** Evals live on the node in memory and are lost
when the app closes.

Consequence: analysing on import without persisting results means re-analysing every
imported game on every launch, which defeats the point of the feature. This question
comes first because it decides whether idea 2 is pleasant or unusable.

### 2. The engine is phone-only

Native engine support is Android and iOS only; other platforms resolve the engine to
null and it is no longer offered there. **The quality gate therefore cannot run on
desktop at all.** If the gate is wanted everywhere, a desktop evaluation backend is a
separate piece of work that does not exist.

### 3. "Terrible, defined very loosely" needs a number

A shared mainline from a real game is rarely catastrophic, but it happens. The tradeoff
is real: drop the position and repertoire coverage silently shrinks; keep it and bad
moves get trained.

Recommendation: **flag, never drop.** Losing coverage is the worse failure because it
is invisible — the user cannot tell that a line they expected is gone. A flagged
position still trains, with a visible marker.

This should be a written invariant in `QUALITY.md` rather than a constant chosen during
implementation.

### 4. Cost of analysing on import

Ten games is 200+ positions. On-device that is minutes of work and battery; via server
analysis it is a queued job with its own limits. "On by default" needs a size threshold
or the feature will be unpleasant in exactly the large-import case it is meant for.

### 5. Which side a game is imported as

Each game must state whether the owner played White or Black, or the importer cannot
tell the owner's moves from the opponent's. The field already exists
(`repertoireSide`). For a batch of mixed-colour games this needs a per-game answer or a
stated default.

### 6. How a game gets into the app at all

By game id from a link, in principle. That path is currently unreachable: **M20** —
`assetlinks.json` and `apple-app-site-association` still list the upstream
`org.lichess.mobileV2` identity, not `org.chesssrs.app`. Until those records are
published, a `lichess.org/<gameId>` link does not hand off to this app.

M20 is an operations task, not code.

## Effect on the audit

**M19 is dissolved by this proposal.** The offline game cache exists because played-game
*viewing* was meant to fetch a game on demand. If games are imported as chapters instead,
their moves are stored like any other repertoire and the cache question disappears.

The corollary: if the idea is *not* adopted, the honest alternative is to cut the
unreachable played-game path — retro screen, game share service, and game-link
resolution — rather than leave it dormant. `AGENTS.md` §6 prefers deleting
unnecessary things.

## What adopting this would require updating

Authoritative documents, in hierarchy order. Not edited here, because nothing is decided:

- `MVP.md` — brings game import into active scope.
- `QUALITY.md` — a candidate domain invariant: repertoire-side moves must not be
  indefensible, with the bar written down rather than implied.
- `IMPLEMENTATION_PLAN.md` — phasing, after the scope decision.
