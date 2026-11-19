# 01 — review: audit-blocks-only-new

## What the feature was supposed to do

Change one rule: what a security audit finding may block. In `templates/SECURITY_AUDIT.md`
step 5, the old clause (b) — "a SILENT ALLOW of a command that writes or runs anything that
is not read-only, even when the base allows it too" is blocking — is removed. The new
classification:

- **blocking**: only a REGRESSION — the head's result for an input is more permissive than
  the base's (a deny or an ask that becomes an allow, a deny that becomes an ask), including
  a silent allow the head introduces.
- **non-blocking**: everything else, including a pre-existing silent allow (the base allows
  the same input). Such a finding is still listed under `## Non-blocking findings`, flagged as
  a pre-existing silent allow with what the rule should do, and the feature that sees it files
  it in its BACKLOG (`self/BACKLOG.md`, or `plans/BACKLOG.md` in a consuming repo) before it
  closes.
- Kept: a finding that cannot be classed with base evidence is blocking.

The same wording change wherever the rule is restated (LIFECYCLE.md → "The security audit",
ORCHESTRATION.md, hooks/README.md, templates/README.md, run-review.sh's audit prompt if it
restates it), the tests that pin the template's text updated (not deleted), and the
`self/BACKLOG.md` entry "The security audit has no convergence criterion" replaced by a
shorter remainder (the round cap / owner ruling).

Excluded: any `feature-close.sh` check that non-blocking findings were filed (NOTES ruling
2); the `audit_report_unclassed` gaps of issue #149; any hook rule change. The rulings are in
`self/features/audit-blocks-only-new/NOTES.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- No remaining statement anywhere in tracked prose or prompts (outside `self/features/*/`
  history) that a pre-existing silent allow is blocking — grep for "base allows it too" and
  "silent allow".
- Every restatement agrees with the template: regression-only blocking, pre-existing silent
  allow non-blocking but flagged and filed in BACKLOG before the close, unclassifiable is
  blocking.
- The report shape is unchanged: `## Findings` table with first cell the class,
  `## Non-blocking findings`, `Verdict: clean|escalated` first line — `feature-close.sh` and
  `plan-runner-roots.sh` are not changed.
- `self/tests/security-audit.sh` B4 (and its `self/tests/README.md` description) pins the new
  text and the absence of the old clause; no test row deleted.
- `self/BACKLOG.md`: the old convergence entry is gone or shortened to the remainder.
- READMEs current for every folder touched (`CONVENTIONS.md` → READMEs).
- Nothing outside this one change.

## Verdict

"No findings" is a legitimate verdict.
