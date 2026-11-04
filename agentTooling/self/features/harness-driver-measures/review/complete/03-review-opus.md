# 03 — review: harness-driver-measures (round 3)

Round 2 (`escalations/02-review-opus.md`) escalated one gap: the resume test watched only a
log line, so deleting `recapture=(--recapture)` or the `${recapture[@]+…}` expansion in
`capture_one` left the suite green. Round 3 seeds a far-future frozen `planning.json`
(`captured_at` 2099, `cost.total` 5.0) on the cell's local branch before the resume, and
asserts the capture log has no `<slug>: already captured` line and the resume row's
`cost_method_usd` is not 5.0 (`harness/tests/smoke.sh` §9c2c). Judge it against the spec
below, not the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Principle: the arm's `agentTooling/` only builds; the driver measures and does the
bookkeeping. (1) literal template fill; (2) cost capture/report from the driver's
`analysis/` via `--arm-root`; (3) the driver's `forge.sh` at the arm's origin
(`FORGE_CHECKOUT`), harness-opened PR with `pr_opened_by_harness` + intervention;
(4) unresolved `base` fetched once by sha; (5) `run.sh <exp> --from review` on a
`no-pr`/`method_failed` cell runs only the PR step, never the method, and re-captures the
method's cost with the driver's rates, with a test.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`. The round-3 change is the last commit before this review: the seed
block and two assertions in `harness/tests/smoke.sh` §9c2c, nothing else in code.

## Contracts to hold it to

- The round-2 escalation is closed: both mutants (drop `recapture=(--recapture)`; drop the
  `${recapture[@]+…}` expansion at the `capture_planning.py` call in `capture_one`) must
  now fail the suite. Trace the seeded freeze through `capture_one` and
  `capture_planning.py` to confirm; do not assume.
- The seed must not break the other resume assertions (no model call, row not
  method_failed, worktree removed afterwards, branch kept) and must not leave a scratch
  worktree behind.
- Everything earlier rounds held to still holds (forge.sh backward compatible, `--arm-root`
  usage error with `--self`, bash 3.2, READMEs current, method templates untouched).

## Verdict

The first line of the report is `Verdict: clean` or `Verdict: escalated`, followed by
findings (file, line, gap, fix).
