# 10 — review (round 2): harness-arm-base

Round 1 judged the feature clean at the earlier tip. Since then `origin/main` gained two
merged PRs — #120 (`harness-direct-bare`, a new `direct-bare` method under
`harness/methods/`) and #119 (`readme-index-check`, a blocking `readme index` gate check and
`check-readme-index.py`) — and this branch merged it with a merge commit (subject
`harness-arm-base: merge origin/main`). Two files conflicted, `harness/README.md` and
`self/PROJECT_FACTS.md`, and were resolved by keeping both sides. This round reviews the
merge and its resolution **only**; do not re-review the feature's own diff, which round 1
read.

## What the feature does (for orientation only)

`--base-arms old=<sha>,new=<sha>` arms differ by a commit of the measured repository;
reading metrics (`read_files_before_edit`, `read_bytes_before_edit`, `readme_bytes_read`)
sit in the results row and the scorecard. Program rows are unaffected.

## The diff to read

Fetch first: `git fetch origin main`. Then read only the merge:

- `git show --stat <merge commit>` and the resolution of the two conflicted files:
  `git diff <merge commit>^1 <merge commit> -- harness/README.md self/PROJECT_FACTS.md`
  (changes relative to this branch's side) and
  `git diff <merge commit>^2 <merge commit> -- harness/README.md self/PROJECT_FACTS.md`
  (relative to main's side). Every line in either diff must be explained by one side's own
  intent; a line neither side wrote is a finding.
- The auto-merged files both sides touched: `harness/EXPERIMENTS.md`, `harness/SPEC.md`,
  `harness/lib.sh`, `self/gate.sh`. Read how each merged, not the files whole.
- Read `self/features/harness-arm-base/README.md` for the plan table.

## Contracts to hold it to

- **Neither side lost content.** Main's: the `direct-bare` row in the `methods/` entry, the
  readme-index and `direct-bare` text in `harness/README.md`, `check-readme-index.py` in
  `self/PROJECT_FACTS.md`'s `py_compile` line and the `readme index` gate check. This
  branch's: the `reading_metrics.py` Contents row, the `--base-arms` text, the
  `tests/arm-base.sh` and `tests/reading-metrics.sh` rows, `reading_metrics.py` in the
  `py_compile` line, `base_arms`, `arm_kind` and the three reading fields in the shapes and
  the ledger-row field list.
- **`harness/lib.sh` and `self/gate.sh` auto-merged correctly**: the base-arm override and
  its refusals still intact; the gate still records both new harness tests and compiles
  `reading_metrics.py`, alongside main's `readme index` check, `direct-bare` pair test and
  `readme index` self-test; no check dropped, none duplicated.
- **Counts and lists agree after the merge**: any "N tests" count in `harness/tests/README.md`,
  `self/PROJECT_FACTS.md` and `CLAUDE.md` matches what `self/gate.sh` runs; the
  `harness/README.md` Contents lists every file in `harness/` that main's readme-index check
  requires.
- **No conflict markers** anywhere in the tree; `git diff --check` clean.
- **Gate**: `./self/gate.sh` was run on the merged tip by the coordinator and passed all
  checks (including `readme index`, `harness arm base`, `harness reading metrics` and
  `harness smoke test`). You may read `self/gate-report.txt`; do not re-run the gate.
- **House rules** as in round 1 for anything the merge touched: no model named in any
  committed file other than plan filenames; folder READMEs current.

A missing assertion is the most valuable finding: phrase it as the test line that would
catch it. "No findings" is a legitimate verdict; do not manufacture speculative ones.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`; then whether the merge and its
resolution keep both sides intact, and two lists — fixed here, escalated.
