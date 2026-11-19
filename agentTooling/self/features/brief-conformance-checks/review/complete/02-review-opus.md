# 02 — review: brief-conformance-checks, round 2

A re-review. Round 1's brief (`review/complete/01-review-opus.md`) still states what the
feature must do and the contracts to hold it to; read it first and hold the whole diff to
it. Round 1 escalated on the review (`escalations/01-review-opus.md`, items 1–3) and on the
security audit (`escalations/01-audit-opus.md`, blocking B1, non-blocking 1–2). This round
judges whether each of those is settled, and whether the rework broke anything round 1 found
sound. "No findings" is a legitimate verdict.

## What the rework was supposed to do

1. **Numbered-list owner items.** `conformance.py items` treats top-level numbered list items
   as the owner's items when the brief has no numbered heading (headings win when both
   exist; neither → one item), with bold titles; the rule is stated in `LIFECYCLE.md`,
   `ORCHESTRATION.md` → "Rules" and `templates/plans/ORCHESTRATOR_BRIEF.md`; tests cover a
   list-shaped brief end to end (both prompts list every item).
2. **No owner brief → no acceptance section asked.** The review prompt asks for
   `## Acceptance` only with an owner brief; `## Deviations from the brief` always. The
   coordinator's ruling (NOTES.md R17): item 4's mark applies to every report, but a report
   with no deviations section is marked only when the feature has an owner brief — a
   no-brief report without the section opens its PR titled with the plain slug, as on `main`.
   This ruling settles round 1's "owner's call" question; do not re-raise it.
3. **No duplicate `plans[]` entry** when the conformance plan is queued again for the same NN.
4. **Audit B1.** `run-review.sh` refuses, before anything runs and before the audit pairing,
   any queued `NN-conformance-<model>` plan the feature does not owe: no `OWNER_BRIEF.md`, no
   review queued beside it, or a stem other than `<review NN>-conformance-<review model>`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The rework alone is
`git diff <the 'brief-conformance-checks: review stamps' commit of round 1>..HEAD`.

## Contracts to hold it to

Round 1's list, unchanged, plus:

- The stray-plan refusal fires for a stray conformance plan with no owner brief (with and
  without a review queued) and for a wrong NN or model with one, and never for the plan
  `queue_conformance_check` itself renders.
- `conformance.py deviations` without the owner-brief flag reads a missing section as empty;
  with it, as non-empty; `pr.sh` passes the flag exactly when the close says the feature has
  an owner brief.
- `pr.sh` stays at template-version 8 (not yet on `main`) with its `TEMPLATE_VERSIONS` hash
  re-recorded.

## Verdict

The report's first line is the verdict the runner's prompt specifies. Then what the rework
was supposed to do, whether it does it item by item, what you fixed, and what you escalate —
each escalation phrased as the assertion or change that would settle it.
