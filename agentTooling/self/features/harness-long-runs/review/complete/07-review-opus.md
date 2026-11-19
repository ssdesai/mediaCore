# 07 — re-review: harness-long-runs, round 2

Round 2's review is scoped. Read `self/features/harness-long-runs/escalations/06-review-opus.md`
(round 1's findings) and `self/features/harness-long-runs/review-report.md`, then the
rework: `git diff <round-1 review commit>..HEAD` (the commit titled
`harness-long-runs: review stamps` is round 1's last; find it with `git log --oneline`).
Read the whole feature diff (`git fetch origin main`, `git diff origin/main...HEAD`) only
where the rework touches code round 1 did not review. Do not re-run tests or the gate
(`self/gate-report.txt` has them). **"No findings" is a legitimate verdict** —
`Verdict: clean` when the escalated list is empty; do not invent speculative findings.
Phrase findings as missing assertions where you can; keep two lists, fixed here and
escalated.

## What the feature was supposed to do

`harness/run.sh` stops safely before the fixed 2-hour background kill (a time budget, exit
75, a `resume:` line naming the remaining cells), resets a killed fixture cell
non-destructively from inside the harness (`--reset <spec>`, behind a per-experiment lock),
takes several `--only` specs, and refuses a `--from` whose earlier outputs are missing.
The manifest's "Deliberately excluded" stands (program-cell reset, a budget in
`run-batch.sh`, any `hooks/` change, comma-separated `--only`).

Round 2's coordinator ruling on round 1's finding 1: **the first cell of every invocation
always starts**, with a warning when its estimate alone exceeds the budget; the budget
decides only whether a further cell starts. Judge the implementation against that ruling,
not the ruling itself.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- No invocation can print a `resume:` line equal to itself: at least one cell runs per
  invocation, and the resume line names exactly the cells not started.
- `harness/tests/long-runs.sh` asserts the first-cell rule (warning, then exit 75 naming
  only the remaining cell) and that `--from record` on a finished fixture cell with no
  worktree is not refused.
- Round 1's contracts still hold: exit 75 distinct and documented; reset moves only, never
  deletes or pushes, refuses before moving, uses and releases the lock; a `--from` refusal
  writes no row; bash 3.2, named constants; docs (`harness/README.md`, `SPEC.md` §17,
  `EXPERIMENTS.md` "Long cells") match the code; no committed file names a model; no
  change under `hooks/` or `.claude/`.

## Verdict
