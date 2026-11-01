Verdict: clean

# Review: harness-same-repo (round 2)

## What the batch was supposed to do

Enforce the owner's rule: *every experiment runs from, and lives on, the repository it
measures*.

- A fixture's or program's `repo` block is optional. When present it must be the consumer.
- The spec comes from the consumer by default.
- The five entry scripts refuse a harness that is not the consumer's own vendored copy.
  The only exception is the test seam `HARNESS_TEST_EXTERNAL_DRIVER=1`.
- The arm's agentTooling pin and an external `spec.url` stay read-only.
- The smoke test and the docs match.

Round 1 found all of that in place and escalated two items. Round 2 (commit `8b4bd23`) had
to close them.

## Does it do it

Yes. Both escalations are closed.

1. **The `repo.path` branch of `harness_measured_repo_problem` now has smoke assertions**
   (`harness/tests/smoke.sh`, section 5, each run through `check-fixture.sh`):
   - `smokePathOwn`: the consumer's own directory passes, and the output says "the
     fixture's repository is the consumer".
   - `smokePathOther`: a fresh checkout whose `origin` is `acme/other` is refused. The
     message names `acme/other` and "run it there".
   - `smokePathMissing`: a path that does not exist is refused, and the message names the
     path. `grep -F` is used here, so the path's characters are matched literally.

   Each case checks the exit code and the message content. These match the code:
   - a path that physically equals `CONSUMER_ROOT` returns 0;
   - otherwise, if the path is a checkout, the identity of its `origin` is compared with
     the consumer's;
   - otherwise the error names the path itself.
2. **Owner decision: option (b), keep the refusal.** `smokePathStale` puts the consumer's
   own `repo.url` beside a nonexistent `repo.path`. It asserts a refusal that names the
   path. That matches the code, which checks `repo.url` first and then checks `repo.path`
   independently, with no early return after the url matches. The same rule is stated once
   in each place it belongs:
   - `harness/README.md` (fixture shape): "`repo.url` and `repo.path` are each checked …
     drop the `repo.path`";
   - `harness/SPEC.md` §14, in the same words;
   - `harness/tests/README.md` describes all four new cases.

   No other doc still calls `repo.path` a hint for the measured repository. The
   one SPEC.md line that does call it a hint (the fixture example, line 56) is about the
   history of `spec.repo`.

The four new cases only add `derived_fixture`s and `check`s. No existing assertion was
changed or removed. Their constants follow the named-constant convention. `self/gate-report.txt`
was generated at 13:26:32Z, after the rework commit at 13:26:26Z. It is green, and it runs
`harness/tests/smoke.sh` through "all checks passed".

Everything round 1 checked still holds, because this round touched only `smoke.sh` and
three docs:
- no fixture path resolves another repository;
- the driver check is in all five scripts;
- no `set -e` or bash-4 constructs were added;
- the seam is documented only in `harness/tests/README.md`.

## Fixed in this pass

None.

## Escalated to the next round

None.
