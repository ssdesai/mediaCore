Verdict: clean

# harness-arm-base — review round 2 (the merge of `origin/main`)

## What this round reviewed

Round 1 judged the feature clean. Since then the branch merged `origin/main` (#120
`harness-direct-bare`, #119 `readme-index-check`) in merge commit `131def5`
(`harness-arm-base: merge origin/main`). This round reviewed only that merge: how the two
conflicted files were resolved (`harness/README.md`, `self/PROJECT_FACTS.md`) and how the
auto-merged files came out (`harness/EXPERIMENTS.md`, `harness/SPEC.md`, `harness/lib.sh`,
`self/gate.sh`).

## Does the merge keep both sides intact? Yes.

- **Conflicted files.** Every line in `git diff 131def5^1 131def5` traces back to main,
  and every line in `git diff 131def5^2 131def5` traces back to this branch. Neither diff
  has a line that neither side wrote.
  - From main, all present: the `direct-bare` row in the `methods/` entry, the
    hyphenated-method branch naming note, the `check-readme-index.py` facts entry,
    `check-readme-index.py` in the `py_compile` line, and the `readme index` gate bullet.
  - From this branch, all present: the `reading_metrics.py`, `tests/arm-base.sh` and
    `tests/reading-metrics.sh` Contents rows, the `--base-arms` text in `run.sh`,
    `new-experiment.sh` and "Arms", `base_arms` in `experiment.json`, `arm_kind` and the
    three reading fields in the ledger-row field list, the program-row exclusion, and
    `reading_metrics.py` in the `py_compile` line.
- **Auto-merged files.** Main's hunks landed apart from this branch's and change none of
  its lines.
  - `lib.sh` gains main's multi-part `harness_capitalise`. The base-arm helpers
    (`harness_experiment_arm_kind`, `harness_experiment_arms`) and their refusals are
    unchanged.
  - `self/gate.sh` gains main's `direct-bare pair` and `readme index` self-tests, the
    blocking `readme index` check and `py_compile readme index`. It still records
    `harness arm base` and `harness reading metrics` and still compiles
    `harness/reading_metrics.py`. No check was dropped and none appears twice.
- **Counts.** `self/gate.sh` runs five `harness/tests/` scripts, and `CLAUDE.md` says
  "five". `self/PROJECT_FACTS.md` lists all five. `harness/tests/README.md` gives no count.
- **README index.** The blocking `readme index` check passed on the merged tip
  (`self/gate-report.txt`). So the `harness/README.md` Contents names every tracked file
  in `harness/`, including the three this branch added.
- **Conflict markers.** None in the tree.
- **`git diff --check origin/main...HEAD`.** It reports one line: trailing whitespace on
  `cost per plan: $0.9610` in `self/features/harness-arm-base/report.md`. That file is the
  cost report `report.py` generates, and the same line ends the same way in the reports of
  #119 and #120 already on main. It comes from the generator, not from this merge, and is
  left alone.
- **Model names.** The merge added none to any committed file.
- **Gate.** All checks passed on the merged tip, none skipped. That includes
  `readme index`, `harness arm base`, `harness reading metrics` and `harness smoke test`.

## Fixed in this pass

- `self/README.md`, the `gate.sh` entry. It still said the gate runs "the harness's own
  three tests" and compiles only `scorecard.py`. That was the count before this feature;
  round 1 missed it, and the merge did not cause it. It now says five tests (adding
  `arm-base.sh` and `reading-metrics.sh`) and that `reading_metrics.py` is compiled too,
  which matches `self/gate.sh` and `CLAUDE.md`.

## Escalated to the next round

None.
