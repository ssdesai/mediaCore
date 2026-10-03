# 110 — review: feature-close-and-review-rounds

Written before the build, from `self/DESIGN-2026-09-17-close-and-review-rounds.md`,
never from the implementers' reports. "No findings" is a legitimate verdict. Fix local
drift in this pass; anything structural is an escalation. **This pass is itself the first
run of the flow it reviews**: `run-review.sh` on this branch is the worktree's rewritten
copy, so it will record your verdict, commit `<slug>: review round 1`, and stop — the
close is run afterwards by the coordinator. Begin your report with the `Verdict:` line the
prompt asks for. `feature-close.sh`, `feature-capture.sh` and `hooks/` are
escalate-only here.

## What the feature was supposed to do

Give the lifecycle its exit. The base is `main`; the diff to read is
`git diff main...HEAD`.

1. **The verdict** (design §3). The review report begins with `Verdict: clean` or
   `Verdict: escalated`; `run-review.sh` reads it, treats a missing line as `unreadable`
   and unreadable as escalated (fail closed), copies an escalated report to
   `escalations/<review-stem>.md` (runner writes it, not the executor), commits its pass
   as `<slug>: review round N` on a non-base branch, stamps `plan_end` with `verdict=`
   and `head=` (HEAD after that commit) and `pass_end`, opens **no** PR, runs **no**
   capture, and prints the next step for each verdict.
2. **Rounds** (§4). `stamp_timing` adds `round` = completed review plans + 1, computed
   once per runner pass and held; `stamp-timing.sh` computes it fresh; the close's
   stamps carry the count itself; a line with no `round` reads as round 1.
3. **`feature-close.sh`** (§5) replaces the shim: refuses off the branch/worktree, with no
   completed review, with a latest verdict that is not clean, with a non-harness commit
   after the stamped `head`, or with a stray dirty path; then `pr.sh <slug> <body>` with
   the report plus the Rounds table → `pr_opened` stamp → `feature-capture.sh` → `pr.sh
   --merge-request <slug>` last. Re-runnable.
4. **`pr.sh` template-version 4** (§5.4) in both copies: the open step requests no merge;
   `--merge-request` is the second entry point; `self/pr.sh` keeps `AUTO_MERGE=0`; the
   close warns once and skips on an older seeded copy.
5. **`run-batch.sh`** (§6): clean → close; escalated/unreadable → brief path, exit 1; one
   verdict reader shared with the close.
6. **The report** (§4): `rounds[]` in `report.json` with the listed fields, the Rounds
   table in `report.md`, a renderer the close reuses for the PR body.
7. **Docs** (manifest slice A6) and the superseded note on the 2026-09-16 design's §3.2.
   `AGENT_DIRECT.md`'s "captured by hand after a rework that skipped a full review" is
   gone: the close refuses a tree no review judged.

Not in this feature: `hooks/`, `feature-start.sh`, the numbering, the capture's stray
rule internals, a script that writes re-review briefs, an escalation count.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect:
`feature-close.sh` (real), `run-review.sh`, `run-batch.sh`, `plan-runner-roots.sh`,
`stamp-timing.sh`, `templates/plans/pr.sh`, `self/pr.sh`, `analysis/report.py`,
`analysis/README.md`, the docs above, `self/tests/feature-lifecycle.sh`,
`self/tests/sync-check.sh`, `self/tests/template-versions.sh`, a new
`self/tests/report-rounds.sh`, `self/tests/README.md`, `self/BACKLOG.md` (one entry
removed), `self/features/README.md`, and this feature's `NOTES.md`/`CHECKPOINT.md`.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **Fail closed.** No path from a report without a `Verdict:` line reaches a PR or a
  capture, in the runner, the batch, or the close. The three read one verdict reader.
- **The runner opens nothing.** After `run-review.sh` returns, the stub `gh` log has no
  `pr create` and no capture ran, for every verdict (design §9 V1–V3).
- **The judged tree is the closed tree.** The close refuses when a commit with a subject
  other than `<slug>: cost records` / `<slug>: PR` follows the stamped `head`, and names
  the sha (X1). A re-run of the close after a refused capture is not refused by its own
  earlier commits (X3).
- **Merge request last.** With `PR_AUTO_MERGE=1` and the template `pr.sh`, the origin
  head at the `pr merge` call already contains `<slug>: cost records` (X2); under
  `self/pr.sh` no `pr merge` is ever issued.
- **Rounds are consistent.** The second review's stamps carry `round=2`, the `pass_end`
  of round 1's review still says `round=1`, and `report.json`'s `rounds[]` has one row per
  round with the verdict from `plan_end` and `escalations_file` only on the escalated
  row (RD). A pre-existing `timing.jsonl` with no `round` renders as one round.
- **The batch still ends in a PR unattended** (B1) and stops on escalation (B2).
- **`pr.sh` contract.** `template-version: 4` in both copies; `sync-check.sh` and
  `template-versions.sh` say so; the open step has no auto-merge call; the old positional
  contract (`pr.sh <slug> <report>`) is unchanged.
- **Named constants** for the verdict strings, the subjects, the escalation path, the
  round key; bash 3.2; `set -uo pipefail`, no `set -e`; no chained `cd`; every python
  `-B`; nothing under `hooks/` touched.
- **README Rule 1** on the `rounds[]` field list in `analysis/README.md`; **Rule 2** on
  `feature-close.sh`'s row (depends on the `plan_end` stamp's `verdict`/`head` keys and
  on `pr.sh` ≥ 4 for the merge request) and on `run-batch.sh`'s row (calls the close).
- **`LIFECYCLE.md`** has seven numbered steps ending in Merge, then Propagate, and no
  sentence still says the review pass opens the PR or captures.
- **Every item above** is present or named in `NOTES.md` as a deliberate exclusion with a
  `self/BACKLOG.md` entry.

## Verdict

Begin with `Verdict: clean` or `Verdict: escalated`. Then, as the PR body will read it:
what the diff does, each contract above as holds / fixed here / escalated, and the files
touched by this pass.
