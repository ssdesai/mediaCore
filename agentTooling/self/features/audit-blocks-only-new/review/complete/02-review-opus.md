# 02 — review: audit-blocks-only-new

## Why this round exists

Round 1 was clean, and so was its security audit. The round-1 review then fixed one stale
cross-reference in `templates/SECURITY_AUDIT.md`: "(a) applies the same way" became "the
REGRESSION rule applies the same way", because the batch had removed the (a)/(b) labels.
That fixed the audit's one non-blocking finding. But the template is an audit path, so the
round-1 audit went stale. This round re-reviews the tree as it stands, and a fresh audit
runs beside it. Nothing else changed after round 1.

## What the feature was supposed to do

Change one rule: what a security audit finding may block. In `templates/SECURITY_AUDIT.md`
step 5, the old clause (b) is removed. It made blocking "a SILENT ALLOW of a command that
writes or runs anything that is not read-only, even when the base allows it too". The new
classification:

- **blocking**: only a REGRESSION. The head's result for an input is more permissive than
  the base's: a deny or an ask that becomes an allow, or a deny that becomes an ask. This
  includes a silent allow the head introduces.
- **non-blocking**: everything else, including a pre-existing silent allow, where the base
  allows the same input. Such a finding is still listed under `## Non-blocking findings`,
  flagged as a pre-existing silent allow, with what the rule should do. The feature that
  sees it files it in its BACKLOG before it closes.
- Kept: a finding that cannot be classed with base evidence is blocking.

The same wording change appears wherever the rule is restated. The tests that pin the text
are updated, not deleted. The `self/BACKLOG.md` convergence entry is shortened to its
remainder. Excluded: a `feature-close.sh` filing check, issue #149's reader gaps, and any
hook rule change. The rulings are in `self/features/audit-blocks-only-new/NOTES.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Nothing in tracked prose or prompts, outside the `self/features/*/` history, still says
  that a pre-existing silent allow is blocking.
- Every restatement agrees with the template, and no dangling (a)/(b) reference remains.
- The report shape is unchanged. `feature-close.sh` and `plan-runner-roots.sh` are untouched.
- `self/tests/security-audit.sh` B4 and its `self/tests/README.md` line pin the new text.
- Nothing outside this one change. Do not edit any audit path in this round (the template,
  `hooks/`, the lifecycle scripts). If one needs a change, escalate it instead, because an
  edit would make this round's audit stale.

## Verdict

"No findings" is a legitimate verdict.
