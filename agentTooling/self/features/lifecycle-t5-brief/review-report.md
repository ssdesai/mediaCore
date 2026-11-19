Verdict: clean

# Review — lifecycle-t5-brief, round 2

## What the batch was supposed to do

Make `self/tests/feature-lifecycle.sh` phase T5 run with its review brief: create the
brief's directory before writing it, add a `T5-pre` assertion that fails if the brief is
missing or if writing it printed anything on stderr, keep T5a–T5d unchanged and passing,
remove the one BACKLOG entry recording the defect, and describe T5 in
`self/tests/README.md`. No runner code changes.

Round 1 was clean. The only commit since is `lifecycle-t5-brief: fill manifest prose`,
which fills the feature manifest's goal paragraph, plan table and exclusions.

## Does it do it

Yes.

- **Manifest prose (new this round).** The goal paragraph matches the diff: the directory
  is created, `T5-pre` asserts the brief exists and that the write was silent on stderr,
  the BACKLOG entry is removed, and T5a–T5d are untouched. The plan table has one row each
  for `01-review-opus` and `02-review-opus`. The fence's `plans` lists the same two stems:
  the harness added the second row and stem in the working tree when it queued this round.
  The `review/incomplete/` path form matches the other self manifests, such as
  `cloud-wave-sessions`. The exclusion is true: the diff touches no runner code.
- **Fence.** Apart from `plans` gaining `02-review-opus`, the fence is exactly what
  `feature-start.sh` wrote: `method: direct`, the branch, `base: main`, `profile: cloud`,
  `gate: green`, the orchestration, `from` and `to: null`, with the id lists empty.
- **Round-1 contracts.**
  - `T5-pre` exists.
  - Its redirect order is `2>>"$T5_ERR" > "$T5_BRIEF"`. Stderr is redirected before the
    write's redirect is opened, so a failed open is captured in `$T5_ERR`.
  - `mkdir -p` writes its stderr into the same file.
  - T5a–T5d are not in the diff.
  - The diff changes only `self/BACKLOG.md` (exactly the one entry removed),
    `self/tests/feature-lifecycle.sh`, `self/tests/README.md` and this feature's own folder.
    It touches no runner, no `.claude/` and no other feature's folder.

## Fixed in this pass

None.

## Escalated to the next round

None.
