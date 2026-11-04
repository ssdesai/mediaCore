# 01 — review: harness-direct-bare

Review the diff for this feature against the spec below; "no findings" is a legitimate
verdict (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

Add `direct-bare`, the control arm for an experiment measuring what `direct`'s three
procedure steps cost (the rewritten `CHECKPOINT.md`, the `stamp-timing.sh` calls, the
acceptance-tests-first commit). It is `direct` with exactly those steps removed.

- `harness/methods/direct-bare/template.md`: `direct/template.md` with exactly two
  removals — the whole `## Procedure` section, and the parenthetical
  ``(`CHECKPOINT.md` at status `committed`)`` in Finish step 2. Every other byte, the
  placeholders included, identical.
- `harness/methods/direct-bare/run.sh`: `direct/run.sh` unless something in it is specific
  to the checkpoint or stamps (nothing is; only the method name in log lines may differ).
- `harness/methods/direct-bare/README.md`: what it is, what it removes, that it exists to
  measure the steps' cost.
- A gate-run test that derives the expected template from `direct`'s and fails on any other
  difference, and checks `direct-bare` passes the placeholder checks `direct` passes.
- Docs: a row in `harness/methods/README.md`'s table, and every README or
  `harness/EXPERIMENTS.md` place that lists the methods, kept current.
- Out of scope: any change to `direct` itself (a README pointer excepted), running an
  experiment.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `diff harness/methods/direct/template.md harness/methods/direct-bare/template.md` shows
  only the deleted Procedure section and the deleted parenthetical — verify by running it.
- `self/tests/direct-bare-pair.sh` is wired into `self/gate.sh` (the `bash -n` list and a
  `record` line), would actually fail if `direct/template.md` changed, and does not pass
  vacuously. Hold its derivation to the spec rather than trusting its comments.
- `direct-bare/run.sh` is executable and does not diverge from `direct/run.sh` beyond the
  name; the method contract in `harness/methods/README.md` (exit codes, no self-review the
  harness relies on) still holds.
- READMEs touched are accurate, the new tests-README row names what the test reads, and
  `direct`'s behaviour is unchanged.

## Verdict
