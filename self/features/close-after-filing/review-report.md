Verdict: clean

# close-after-filing — review round 6 (the `main` merge)

## What this round was supposed to do

This round's only change is merge commit `8c34190` (`close-after-filing: merge main
(consumer-record-guard)`). It brings `origin/main` (`2b27dac`, carrying
`consumer-record-guard`, PR #156) into this branch. The review judged whether the resolution
keeps both features intact: this branch's `<slug>: backlog` close allowance, and main's
vendored-copy `--self` record-write refusal.

## Does it

Yes, once the one fix below is in.

- **No hunk dropped.** I compared every file the two sides share against both parents:
  `LIFECYCLE.md`, `README.md`, `self/PROJECT_FACTS.md`, `self/gate.sh` and
  `self/tests/README.md`. For each one, the merge's change over `main` matches this branch's
  change over the merge base. No file main changed differs between `main` and the merge
  outside those five. No file this branch changed differs between `8c34190^1` and the merge.
- **`feature-close.sh`** is this branch's version. Main never touched it.
- **`self/gate.sh`** registers `self/tests/consumer-record-guard.sh` and
  `self/tests/close-backlog.sh` in `shell_scripts` and as `record` lines. Both ran green in
  `self/gate-report.txt`, and nothing in the gate report is SKIPPED or failing.
- **The docs agree.** `README.md` keeps main's `orchestration-start.sh` and
  `orchestration-capture.sh` rows unchanged, and the `feature-close.sh` row is this branch's.
  The two features describe separate scripts, and neither contradicts the other.
- **No check weakened or dropped.**

## Fixed in this pass

- **`README.md`: the `forge.sh` row appeared twice** (old lines 53 and 54, byte-identical).
  The conflict resolution kept the row as context on both sides of the adjacent
  `feature-close.sh` hunk. `main` has the row once. I deleted the second copy, and
  `git diff origin/main -- README.md` is now only the one-line `feature-close.sh` row
  change, as intended. No test caught it, because `check-readme-index.py` checks that each
  file is named, not that it is named once. This fix is in the working tree and still needs
  committing on the branch.

## Escalated to the next round

None.

## Non-blocking notes

- Missing check that would have caught the duplicate: `check-readme-index.py` (or a
  `self/tests/readme-index.sh` case) could flag a file that heads more than one row of the
  same README table. It belongs in the BACKLOG, not this feature.
