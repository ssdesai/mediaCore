Verdict: clean

# Review: split-tests-method, round 3

## What the batch was supposed to do

Add the `split-tests` harness method (`harness/methods/split-tests/`). It runs two fresh
sessions in the same tree. An independent test author writes black-box acceptance tests and
commits them alone as `<slug>: acceptance tests`. Then `vanilla-conv`'s implementer is told
to make those tests pass. The spec is the manifest's opening paragraph and its "Deliberately
excluded" list.

Round 3 reworks one finding that round 2 escalated. The author could commit its tests, leave
source such as `src/feature.py` uncommitted, and then hit its usage limit. The re-entry
trusts any tests commit it finds and goes straight to the implementer, so that source would
reach the implementer.

## Does it do it

Yes. Checked against the whole `origin/main...HEAD` diff and against this round's own change
(`dcef7ae..HEAD`):

- **The escalated finding is fixed.** In `harness/methods/split-tests/run.sh`, the
  usage-limit branch (lines 126–139) now checks two things once a tests commit exists. The
  tip must be that commit. Nothing may be left uncommitted, which is checked by
  `refuse_author_leftovers " before its usage limit"`. Both happen before the exit 2. The
  clean-exit path (line 148) calls the same function, so there is only one copy of the check.
  Without a tests commit, the stop still exits 2 as before.
- **The test would fail without the fix.** The new pair-test case `limitdirty` commits the
  tests, leaves `src/feature.py` untracked, and then stops on the limit. Before the fix this
  path exited 2, so 4h (exit 1, one session) and 4i4 (the refusal names `src/feature.py`)
  would both fail. The cases `limit`, `limitafter` and the re-entry are unchanged (4i3, 4k,
  4l).
- **The gate is green.** `self/gate-report.txt` shows `split-tests-pair: all assertions
  passed`, including 4h for `limitdirty` and 4i4, and no check exits non-zero.
- **Out of bounds stays untouched.** `harness/run.sh`, `harness/lib.sh`, `hooks/` and
  `harness/check-fixture.sh` show no diff against `origin/main`.
- **The docs agree with the code.** These all now describe the new check on the
  usage-limit path:
  - the method README's exit-1 paragraph
  - `run.sh`'s header comment
  - the manifest paragraph and its plan table
  - the `self/tests/README.md` entry
  - the pair test's header comment
- **The other contracts still hold.** Round 3 did not touch `template.md`, the author
  brief, the test-diff write, or the "nothing lands in the tree" check (4g). Round 2's review
  cleared those, and they still hold. No `${x//pat/$var}` appears anywhere. There are no new
  magic literals: the only new literal is a message suffix.
- **NOTES.md ruling 12 holds** as written, including its account of what it leaves alone.

## Not a finding, for the approver's information

NOTES ruling 12 and the plan both keep one behaviour on purpose. Suppose the author stops on
its limit **before** making a tests commit and has left a partial source file. The re-run
author then records that file in its own `dirty_before`, so the leftover check does not
catch it, and the file can still reach the implementer. The manifest specifies this
behaviour ("Without a tests commit, the stop exits 2 as before"), and the ruling states the
trade-off openly. Closing the gap would mean saving the first author's `dirty_before` next
to `<branch>-author-start`, which is a design choice for a later feature, not a defect in
this one.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.
