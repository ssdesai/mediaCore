Verdict: clean

# Review: brief-conformance-checks, round 3

## What the rework was supposed to do

Settle round 2's single escalation (`escalations/02-review-opus.md`). The missing assertion: when an interrupted pass has already queued the owed conformance plan, `refuse_unowed_conformance_plans` never refuses it, and the pass resumes it. The brief asked for two tests in `self/tests/brief-conformance.sh` and the test's entry in `self/tests/README.md`:

- **L1e:** the check is in `review/inprogress/` and its review is in `review/incomplete/`.
- **L1f:** both are in `review/inprogress/`.

Nothing else was to change.

## Does it do it

Yes. The rework (`ce69673..a533b88`) adds exactly those two cases, the README entry and this round's queue entry and `plans[]` stem. It touches no audit path.

Both tests use the listy feature, which has an owner brief. Each one asserts three things:

- `run-review.sh` exits 0;
- no `refused` line appears;
- the order log is exactly `conformance review`.

Read against `run-review.sh:522–551` and `:461–514`, these assertions catch the drift round 2 named. If the owed stem computed in `refuse_unowed_conformance_plans` (`owed=…`) stopped matching the one in `queue_conformance_check` (`stem=…`), the refusal would exit 1 before anything ran, and both the exit-code and order-log checks would fail.

- **L1f** also covers the `queue_conformance_check` branch that refuses a review resumed from `inprogress/` with no check beside it: the check is present there, so the refusal must not fire.
- **L1e** covers the path where the existing check is rewritten in place in `inprogress/` (`target=…/${conf_state}/…`).

Both cases run last in their section, and no later test reads the listy feature's queue, so the leftover fixtures cannot affect other checks.

**The gate:** `self/gate-report.txt` shows `brief-conformance: all checks passed`, with nothing skipped. This round's security audit (`audit-report.md`) is `Verdict: clean`.

**One difference from round 2's escalation:** it asked for the review and the check both in `review/incomplete/`, which is the state an audit interrupted ahead of them leaves. The rework tests the inprogress/incomplete split instead. By reading, this does not leave the contract untested. `refuse_unowed_conformance_plans` keeps a plan's directory only to print it in the message, and computes the owed stem the same way whichever directory the plan is in. So L1e checks the same stem comparison the both-in-incomplete case would. This round's brief names L1e and L1f, and the work matches it.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.

## Deviations from the brief

None
