# 01 — review: backlog-unclaimed-delegates

feature: agentTooling/backlog-unclaimed-delegates

## What the feature was supposed to do

Add two entries to `self/BACKLOG.md` and change nothing else. The entries come from the
unclaimed-delegate residue that `litellm-pricing`'s capture printed on 2026-09-23:

1. **Propagation has no cost record.** Subtree-pull sessions and their delegates belong to
   no feature, so the residue keeps listing them: 24 delegates, $16.55 across PRs
   #46–#60.
2. **Unclaimed delegates that belong elsewhere.** The `vinylCatalogue/audio-checked-mark`
   implementer `abdc44b0d582d0b92` ($8.74) is to be pinned in the vinylCatalogue repo,
   alongside the pending repair there. There are also two exploration delegates under
   parent `a60214fa`.

## The diff

Base is `main`. Run `git diff main...HEAD --stat`, then read the full diff.

## Contracts to hold it to

1. **Only the two entries and this feature's own records.** The diff may touch only
   `self/BACKLOG.md` and `self/features/backlog-unclaimed-delegates/`.
2. **Each entry fits the file's own format.** Read the file's header: each entry is phrased
   with the assertion that would catch the problem, and ends with `Raised by` naming the
   feature that raised it.
3. **Every fact in the entries is checkable.** Check the three agent ids, the dollar
   figures and the PR range against
   `python3 analysis/capture_planning.py --self --list-subagents --unclaimed --since 2026-09-16`.
   Also check that the commands and paths the entries name exist
   (`update.sh`, `LIFECYCLE.md` → "Propagate", `--list-subagents --unclaimed --everywhere`).
4. **Gate.** `./self/gate.sh` passes.

## Verdict

Open the report with exactly one line: `Verdict: clean` or `Verdict: escalated`. "No
findings" is a legitimate verdict. Fix local defects yourself and commit the fixes.
