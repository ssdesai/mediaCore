# 03 — review: shared-hook-rules (round 3, scoped)

Rounds 1 and 2 came back clean, with clean security audits; round 2's audit judged the tree
as it stands. After round 2 the coordinator committed one more change,
`shared-hook-rules: fill the feature README`, because `feature-close.sh` refused the feature
manifest's template placeholders. This round judges only that commit. "No findings" is a
legitimate verdict.

## What the feature was supposed to do

Unchanged: a pure refactor giving every rule the PreToolUse hook shares with `analysis/` and
the shell one definition in `hooks/shared_rules.py` (`NOTES.md` rulings 1–10;
`review/complete/01-review-opus.md`). The README fill is documentation: it replaces the
template's title, goal paragraph, plan table, level and contract sections and excluded list
in `self/features/shared-hook-rules/README.md` with this feature's own, and changes nothing
in the machine-readable fence.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

For this round, read `git show <the 'shared-hook-rules: fill the feature README' commit>`
(find it with `git log --oneline origin/main..HEAD`) and confirm it is the only commit after
round 2's `review stamps` commit apart from this round's own.

## Contracts to hold it to

1. The commit touches only `self/features/shared-hook-rules/README.md`. Inside its ```json
   fence the only change since round 2 is `plans` gaining `03-review-opus` (written by
   `manifest.py set-plans` when this round was queued, and committed with this round's
   output), and the prose below the fence is untouched.
2. What the prose says is true of the tree and of `NOTES.md`: the goal paragraph matches what
   was built; the plan table names exactly the review and audit plans in `review/complete/`
   with accurate one-line descriptions, and matches the fence's `plans`; each "Deliberately
   excluded" entry matches a ruling in `NOTES.md` and, where it says so, a `self/BACKLOG.md`
   entry.
3. The sections `templates/plans/features/TEMPLATE.md` says a single-level (direct) feature
   deletes are deleted, and no template placeholder text remains.

## Verdict
