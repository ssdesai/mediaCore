# 03 — review: cost-capture-collisions (round 3, scoped)

Written before the change it judges. Round 2's verdict was clean and the feature closed
(PR #80, `cost-capture-collisions: cost records`). The task requires the design record
to carry what that close found, which is a commit after the close, so it is reviewed
like any other. "No findings" is a legitimate verdict. Begin your report with the
`Verdict:` line the prompt asks for.

## What the change was supposed to do

Add one bullet, "Found at its own close", under `cost-capture-collisions`' findings in
`self/DESIGN-2026-10-05-cloud-execution.md` §10. Nothing else.

## The diff

`git diff <the cost-records commit>..HEAD`, where that commit is the one whose subject is
`cost-capture-collisions: cost records`. Expect the design doc, this brief, the
manifest's `plans` and plan table, and the runner's own records under
`self/features/cost-capture-collisions/`. Any code, test, or other feature's directory in
that range is a finding.

## Contracts to hold it to

- **Every figure in the bullet matches the record on disk**: the session and subagent
  dollars in `self/features/cost-capture-collisions/planning.json`, the total and the
  review figure in `report.md`, and "2 excluded" in `planning.json`'s
  `excluded_session_ids`. That the annotate step changed no other record is checked by
  `git diff <base> --stat -- self/features`, which must show only this feature.
- **It states nothing the code does not do** (`analysis/capture_planning.py`'s annotate
  path for the "not re-checked" notes).

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the change was supposed to do, whether it does it, what you fixed, what you
escalated, and the files this pass touched.
