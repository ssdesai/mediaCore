# 02 — review: router-built-pin (round 2, the merges from main)

feature: agentTooling/router-built-pin

Round 1 (`01-review-opus`) reviewed the whole feature and returned `Verdict: clean`. After
that review, `origin/main` gained `litellm-pricing` (PR #62) and
`backlog-unclaimed-delegates` (PR #64), and both were merged into this branch as two merge
commits. Those merges are the only thing round 1 did not read. Review only the merges. Do
not re-review the feature.

## What the feature was supposed to do

See `self/features/router-built-pin/README.md`. `feature-close.sh` refuses a feature its
unpinned router built (`analysis/routing.py --unpinned-builder`) and names the remedy,
`analysis/manifest.py pin-session`. `WORKTREES_DIR_NAME` and `feature_worktree_path` moved
from `capture_planning.py` into `routing.py`. `self/BACKLOG.md` gained a re-render-drift
entry.

## The diff

The two merge commits are the latest two `Merge remote-tracking branch 'origin/main'`
commits on this branch; list them with `git log --merges -2 --oneline`. Read
`git show --cc <merge>` for each, which shows only the hunks that combine both sides. Then
read the files both sides touched, as they are at `HEAD`:
- `README.md` and `analysis/README.md`: the two hand-resolved conflicts;
- `analysis/capture_planning.py`, `LIFECYCLE.md`, `self/BACKLOG.md` and
  `self/tests/README.md`;
- `self/tests/feature-lifecycle.sh` and `self/tests/routing-record.sh`.

## Contracts to hold it to

1. **Both sides survive the two hand resolutions.**
   - In the root `README.md`: the `feature-capture.sh` row carries litellm-pricing's rates
     residue (`refresh_rates.py --check`), and the `feature-close.sh` row carries this
     feature's unpinned-router refusal. Each row appears exactly once.
   - In `analysis/README.md`: the `routing.py` entry ends with this feature's Exposes list
     (`feature_worktree_path`, `is_at_or_under`, `worked_in`, `unpinned_builder`) and the
     R12/RB assertions. It is followed by litellm-pricing's `pricing.py`,
     `rates_history.json` and `refresh_rates.py` entries, with no older `pricing.py` entry
     beside them.
2. **The moved helpers.** `capture_planning.py` imports `WORKTREES_DIR_NAME` and
   `feature_worktree_path` from `routing` and defines neither itself. Nothing litellm-pricing
   changed in that file reintroduced them.
3. **The tests.** `self/tests/routing-record.sh` copies `analysis/rates_history.json` into
   its sandbox (litellm-pricing's line) and keeps R12. `self/tests/feature-lifecycle.sh`
   keeps RB and whatever main changed. Both scripts pass.
4. **BACKLOG and the other READMEs.** Each side's entries are present exactly once, in a
   readable order, with no text interleaved.
5. **Gate.** Run `./self/gate.sh` yourself. It must be green.

## Verdict

Open the report with exactly one line: `Verdict: clean` or `Verdict: escalated`. "No
findings" is a legitimate verdict. Fix local defects yourself and commit the fixes.
Escalate only what is structural.
