# 01 — review: backlog-parked-items

Independent review of a docs-only change to `self/BACKLOG.md`. "No findings" is a
legitimate verdict; report only what you can show from the diff and the tree.

## What the feature was supposed to do

Add entries to `self/BACKLOG.md` (shape in its header: one bullet per item, phrased as the
assertion that would catch it, naming what raised it):

- Eight entries for the README/spec-structure items the owner parked on 2026-11-07, under a
  lead sentence saying they are parked until the owner says otherwise, `Raised by`
  `readme-structure`: (1) roll the structure out beyond vinylCatalogue, saying part shipped in
  humanNetworkMap and musicMap (PRs #273, #275, #277, #73, #74 in
  `self/orchestrations/readme-structure/README.md`) and phrased as what is left;
  (2) opt humanNetworkMap, musicMap, mediaCore into the README-index check (#119);
  (3) vinylCatalogue root `CLAUDE.md`: move the CLI reference and spec-amendment history out;
  (4) `.claude/rules/` path-scoped facts, musicMap first; (5) a mechanical README-accuracy
  check beyond #119's index; (6) humanNetworkMap root README: move Data Model, Delegated plan
  execution, Notes for Claude Code out; (7) optional: wire humanNetworkMap's
  `scripts/check_test_spec_split.py` into its gate; (8) the README traversal-rule A/B, "decide
  whether still worth running".
- Loose items 9 (a script bringing a feature branch up to date with main), 12 (`spec_commit`
  label on arm-spec rows), 13 (`plans/experiments/README.md` index entries missing), 14
  (`publish.sh` with several experiments on one branch: one PR, first scorecard only),
  15 (`feature-start.sh` for an experiment writes a full README and review stub), raised by
  `orchestrator notes 2026-11-07` unless the tree names a better source.
- Items 10 (program-cell `--reset`) and 11 (time budget) were already in the file and must not
  be duplicated.
- Each entry 3–6 lines with an `Assertion:`; consumer-repo claims phrased as the
  orchestrator's note "as of 2026-11-07" where the tree cannot verify them.

Excluded: changes to any file but `self/BACKLOG.md` and `self/features/backlog-parked-items/`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Only the two paths above change; existing backlog entries are untouched.
- No duplicate of the existing "Program cells cannot be reset" or "`run-plans.sh` has no time
  budget" entries.
- Every entry has an `Assertion:` and a `Raised by`; no entry states a consumer-repo fact the
  tree cannot show as verified.
- Claims about this tree are true: check `harness/README.md` (spec_commit on arm rows),
  `harness/publish.sh` (PR body, existing PR), `feature-start.sh` (manifest and review stub).
- `./self/gate.sh` is green.

## Verdict
