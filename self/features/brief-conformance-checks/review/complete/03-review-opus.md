# 03 — review: brief-conformance-checks, round 3

A re-review, allowed by the owner's ruling of 2026-11-19 past the audit round cap. Round 1's
brief (`review/complete/01-review-opus.md`) still states what the feature must do and the
contracts to hold it to, and round 2's (`review/complete/02-review-opus.md`) the rework it
judged. Round 2's review escalated one missing assertion
(`escalations/02-review-opus.md`); its security audit came back clean and was stamped stale
only because the review then made a whitespace fix in `conformance.py`. "No findings" is a
legitimate verdict.

## What the rework was supposed to do

Add the missing assertion: an owed conformance plan that an interrupted pass left queued is
resumed, never refused by `refuse_unowed_conformance_plans`. Tests L1e (the check in
`review/inprogress/` beside its review in `review/incomplete/`) and L1f (both in
`review/inprogress/`) in `self/tests/brief-conformance.sh`, and the test's entry in
`self/tests/README.md`. Nothing else changed since round 2.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The rework alone is
`git diff <the 'brief-conformance-checks: review stamps' commit of round 2>..HEAD`.

## Contracts to hold it to

Round 1's and round 2's lists, unchanged.

## How to treat a finding on an audit path

Do NOT edit any audit path (`plan-runner-roots.sh` → `AUDIT_TOOLING_PATHS`: among others
`conformance.py`, `run-review.sh`, `feature-close.sh`, `feature-start.sh`,
`plan-runner-lib.sh`, `plan-runner-roots.sh`, `analysis/`, `hooks/`), not even for
whitespace or a comment: a change there after the security audit has run stamps the audit
stale. Report such a finding instead; a cosmetic one is not an escalation. Local fixes
elsewhere (docs, tests) are fine.

## Verdict

The report's first line is the verdict the runner's prompt specifies. Then what the rework
was supposed to do, whether it does it, what you fixed, and what you escalate — each
escalation phrased as the assertion or change that would settle it.
