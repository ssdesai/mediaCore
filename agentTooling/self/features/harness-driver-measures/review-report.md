Verdict: clean

# Review — harness-driver-measures, round 3

## What the round was supposed to do

Round 2 escalated one gap: the `--from review` resume test on a `no-pr` cell checked only
a log line. Deleting `recapture=(--recapture)` or the `${recapture[@]+…}` expansion in
`capture_one` (`harness/run.sh`) left the suite green. To close it, round 3 commits a
far-future frozen `planning.json` (`captured_at` 2099) onto the cell's local branch before
the resume. It then asserts two things in `harness/tests/smoke.sh` §9c2c:

- the capture log has no `<slug>: already captured` line;
- the resume row's `cost_method_usd` is not the frozen 5.0.

## Does it do it

Yes. The first assertion closes the escalation on its own. I checked this by tracing the
code. I could not run the mutants: the permission policy here does not allow a scratch
worktree.

- The seed reaches the resume tree. `ensure_resume_trees` (`harness/run.sh:407`) adds the
  worktree from the **local** branch when one exists, and the seed commit is on that
  branch.
- The stale-freeze rule cannot rebuild a 2099 stamp, because `"2099…" < started` is false.
  So `--recapture` can only come from the `RECAPTURE_METHOD` branch.
- With either mutant, `capture_planning.py` runs without `--recapture`. Every step reads
  the seed through `.get()`: `prior_capture` returns the 2099 stamp,
  `register_frozen_claims` sees no sessions, and `annotate_frozen_record` reports no
  change. So `capture_feature` prints `<slug>: already captured 2099-… — skipping` into
  the capture log, and the assertion fails. Both mutants are killed.
- The seed does not disturb the other resume checks. The worktree is added and then
  removed with `--force`, so nothing is left behind. The branch is only advanced
  locally, and the resume's push fast-forwards it.

The second assertion could never fail, and its message ("the rebuilt figure") was false.
The smoke run's capture log shows why:

1. The seed wrote `"cost": {"total": 5.0}`, but the schema key is `cost_usd`. Both
   `prior_capture` and `report.py:1071` index `cost_usd`, so `report.py` crashed with
   `KeyError: 'cost_usd'`. `capture_one` swallows that crash (`|| true`) and reports 0.
   The row read 0 whether or not the freeze was honoured.
2. Correcting the key would not rescue the assertion. The fake sessions price nothing, so
   an honoured `--recapture` **refuses** to write a $0 record ("REFUSING to write
   planning.json — no session and no subagent matched"). The 5.0 freeze would stay on disk
   and the assertion would fail on correct code. In this offline suite, the row's cost
   cannot tell the mutant from the real code.

Earlier rounds' contracts are untouched. Round 3 changes only test code and the test
README; `run.sh`, `lib.sh`, `forge.sh`, `analysis/` and the method templates are the same
as in round 2. The seed block uses no syntax that bash 3.2 lacks.

### Gate coverage

`self/gate-report.txt` was written at 14:10. The round-3 edit to `smoke.sh` came at
14:20, so the gate never ran the new assertions. I ran `harness/tests/smoke.sh` myself:

- On the committed round-3 code, all checks passed (379 ok).
- After my fix, it reran with all checks passing (378 ok, one fewer because the vacuous
  check is gone). `report.py` now reads the seed without crashing, and the resume row
  shows `cost_method_usd` 5.0, the freeze that survived. That confirms the removed check
  would have failed on correct code if the seed key had been right.

## Fixed in this pass

- `harness/tests/smoke.sh` §9c2c, the seed: `"cost"` is now `"cost_usd"`, the real
  schema. The comment explains why the row's cost cannot tell the mutant apart.
- `harness/tests/smoke.sh` §9c2c: removed the vacuous
  `cost_method_usd != $RESUME_FROZEN_USD` check. I also corrected the comment above the
  capture checks, which said no frozen record exists.
- `harness/tests/README.md`, the resume-cell paragraph: it now describes the seeded freeze
  and the capture-log assertion, and says why the row's cost is not asserted.

## Escalated to the next round

None.
