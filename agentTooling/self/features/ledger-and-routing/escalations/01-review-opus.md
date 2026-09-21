Verdict: escalated

# Review — ledger-and-routing

Base: the branch's own commits, `b427ae6..HEAD` (`a096c80` start through `fe1ca90`). The
local `main` is behind `origin/main` by the #50 and #51 merges, so a literal
`git diff main...HEAD` also shows those two features' files. None of them belongs to
this batch, and they are not reviewed here.

## What the feature was supposed to do

It closes four ledger defects:

1. The routing record now lives inside the feature it links (`<slug>/routing.json`).
   Latest `captured_at` wins in `load_records`, `--refresh-for` touches only its own
   slug's copy, `--migrate` moves the legacy records and `sync-plans.sh` runs it, and the
   stray reader lists `routing.json` in `COST_FILES`.
2. An open co-claimant is bounded provisionally by its own `last_branch_instant`. The
   record carries `open` and `provisional_to` on `share_basis[]` and `open_claimants[]`
   at the top level, and `annotate_corpus` warns when the stamped bound drifts from it.
3. Every `subagents[]` entry reaches the ledger, at `cost_usd` 0 when unpriced.
4. `manifest.py set-window-from` is the head's remedy, with its three refusals, and the
   unclaimed-head warning names it.

## Does it do it

Yes. All four hold on reading, and the gate is green. Each contract in the brief is
covered by a test:

- **One location, one reader.** `routing.py` checks it: `routers_of` opens only
  `<slug>/routing.json`, and `load_records` globs `*/routing.json` and ranks each router's
  copies by `(captured_at, len(features_started))`. The legacy directory is read only by
  `--migrate`. The record's field set is unchanged. Tests: R1, R5d2, R8.
- **No path two features share.** `feature-lifecycle.sh` MR starts the second feature
  before the first merges, merges both with no conflict, and asserts one Routing row that
  names both slugs.
  - The test merges the branches directly rather than through `feature-close.sh`. This
    still tests the defect, because the conflict was about the two paths and not about
    the close.
- **Refresh touches only its own file.** R7a/R7b, and R7c shows the check is not vacuous.
- **Migration is idempotent.** Tests R9a–m, including skipping a target that holds a
  newer record and keeping a record whose slugs are all orphans. `self/routing/` is gone,
  and each record now sits under its slug's directory (NOTES ruling 1 covers the one
  skipped slug).
- **The stray reader.** `COST_FILES` includes `routing.json`, and no `ROUTING_*` label is
  left in code. Tests: `verdict-readers.sh` S7/S8.
- **The open co-claimant.** `build_claimant_index` calls `last_branch_instant` with the
  co-claimant's own `features_dir` and exempts the capturing feature. The warning for a
  claimant with no evidence is distinct from the malformed-window one. Tests:
  `session-share.sh` 18–20, which cover the share being the same before and after the
  close, and one WARN naming `--recapture` on drift.
- **The zero-cost pin.** `record_claims` iterates `subagents[]`. Tests:
  `subagent-capture.sh` 19a–f.
- **`set-window-from`.** Covers every refusal, the old → new echo and the `--recapture`
  note. `manifest.py` imports `routing`, not `capture_planning`, and ruling 13 records
  that choice. The head warning prints
  `manifest.py [--self] <slug> set-window-from <session start> --session <id>`. The
  instant it prints is the same `min(timestamps)` that `session_first_instant` checks
  against, and both serialize it losslessly, so the suggested command is never refused as
  too early. Tests: `manifest-window.sh` M1–M8, `session-share.sh` 15e/16e.
- **Backlog.** The four entries are gone and the six others remain.

## Fixed in this pass

Stale docs, where each file still described the old routing location:

- `README.md`, the `plan-runner-roots.sh` row: it still listed
  `ROUTING_DIR_NAME`/`ROUTING_RECORD_SUFFIX` and "the four path labels … `ROUTING_REL`",
  in two places. It now names `routing.json` inside `COST_FILES` and the three labels
  that remain.
- `self/PROJECT_FACTS.md` → Commands: it said a start writes
  `self/routing/<session-id>.json`. It now says `self/features/<slug>/routing.json`.
- `analysis/report.py`, the `render_routed_by` docstring: it said `routers_of` was "one
  scan" over `load_records`'s sorted records. It now says the function reads the
  feature's own copy, and that "alongside" may therefore name fewer slugs than the
  router's latest copy in the Routing table.

## Escalated to the next round

1. **Nothing tests `sync-plans.sh` running `--migrate`.** `sync-plans.sh:194` (the
   `migrate_routing` hook, called at `:284` on the write path) is the only way a
   consuming repo's `plans/routing/` ever moves.
   - `routing-record.sh` R9 tests `routing.py --migrate` directly.
     `self/tests/sync-check.sh` never creates a `plans/routing/` fixture.
   - So none of these would turn the gate red: dropping the call, running it on the
     `--check` path, or resolving a features root different from `sync-plans.sh`'s
     `PLANS_DIR`. The last matters because `roots.features_root(False)` and `PLANS_DIR`
     are derived separately.
   - Assertion to add to `sync-check.sh`, in a vendored scaffold:
     - Set up `plans/routing/<id>.json` naming `a` and `b`, with `plans/features/a/` and
       `plans/features/b/` present.
     - The write path should leave `plans/features/{a,b}/routing.json` equal to the
       legacy record, remove `plans/routing/`, and print a `routing  moved …` line for
       each move.
     - A second sync prints no `routing` line.
     - `sync-plans.sh --check` over the same fixture leaves `plans/routing/<id>.json` in
       place.
   - This is a test-only slice. No code change is expected.

## Files this pass touched

- `README.md`
- `self/PROJECT_FACTS.md`
- `analysis/report.py` (a docstring only)
- `self/review-report.md`
