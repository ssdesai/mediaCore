Verdict: escalated

# Review: brief-conformance-checks, round 2

The round 2 rework (`96395b0`) is correct by reading on all four items, and the gate is green with nothing skipped (`brief conformance self-test`: all checks passed). One contract the brief names has no test, so it is escalated as a single assertion for the next round. No code change is needed.

## What the rework was supposed to do

Settle round 1's review escalations 1–3 and the security audit's blocking finding B1 (along with its non-blocking findings 1–2), without breaking anything round 1 found sound:

1. Numbered-list owner items.
2. No owner brief means no `## Acceptance` section is asked for (ruling R17).
3. No duplicate `plans[]` entry.
4. Unowed conformance plans are refused before anything runs.

## Does it do it

1. **Numbered-list owner items: done.**
   - `conformance.py` `parse_items` now collects top-level (column-0) `N.`/`N)` list items outside fences as `listed`. It titles each by its opening bold span, or else by the line with `**`/`__` removed. It returns `headings or listed or fallback`, so headings win.
   - The rule is stated in `LIFECYCLE.md`, `ORCHESTRATION.md` → "Rules" and `templates/plans/ORCHESTRATOR_BRIEF.md`.
   - Tests:
     - U1n: the round-1 brief shape, nested items excluded.
     - U1o: headings win.
     - U1p: fences, indented lines, marker stripping.
     - L1a/L1b: both prompts list all five items by their bold titles, end to end.
2. **No owner brief, no acceptance section: done.**
   - `report_sections_text` takes a has-brief flag. Without a brief, the review is asked only for `## Deviations from the brief`.
   - The tests for this:
     - N1c is flipped. It now also asserts that "owner's request listed above" is absent and the deviations heading is present.
     - `conformance.py deviations` reads a missing section as `non-empty` only with `--owner-brief-present` (U1h, both ways).
   - **The close and `pr.sh`:**
     - `feature-close.sh` sets `CONFORMANCE_REPORT_FILE` only inside its owner-brief branch, and exports `CONFORMANCE_REPORT` only when that is set (`feature-close.sh:422,440,615`).
     - `pr.sh` passes the flag exactly when `CONFORMANCE_REPORT` names an existing file, so the flag tracks "the close found an owner brief".
     - N2a checks that a no-brief report without the section gets the bare-slug title. N2b checks that one with a deviation is marked.
   - This matches R17.
3. **No duplicate `plans[]` entry: done.** The stem is appended only when it is missing. L1c/L1d assert it once after a second queueing for the same NN, reached by the refusal's own "move it back" path.
4. **Audit B1, unowed conformance plans refused: done.**
   - `refuse_unowed_conformance_plans` runs before `queue_security_audit` and `queue_conformance_check`. It refuses (exit 1, nothing run) when any of these holds:
     - the feature has no owner brief;
     - no review is queued beside the plan;
     - the plan's stem is not `<review NN>-conformance-<review model>`.
   - It uses the same "delete it" wording as the stray-audit refusal.
   - Tests:
     - B1a: no brief, with a review queued.
     - B1b: no brief, alone after a clean round (the audit's variant C).
     - B1c: wrong NN.
     - B1d: wrong model.
   - Variants A and B take the same path as B1a, which refuses before the audit pairing.
   - It computes the owed stem with the same expression `queue_conformance_check` uses, and finds the review with the same scan, so by reading it never refuses the plan that function renders.

**Template version.** `pr.sh` stays at template-version 8, and the template-versions and sync-check self-tests pass on the re-recorded hash.

Nothing that round 1 found sound is touched by the rework, apart from the lines above.

## Fixed in this pass

- `conformance.py:78,81`: `NAME ="…"` → `NAME = "…"` (spacing only, no behaviour change).

## Escalated to the next round

1. **Missing assertion: the refusal never fires for the plan `queue_conformance_check` renders when that plan is already queued.** The brief names this as a contract. No test exercises it:
   - Every refusal test (B1a–d) starts with no owed plan in the queue.
   - Every success path (L1a, L1d, C1) runs the refusal before the plan has been rendered.
   - `self/tests/brief-conformance.sh` has no `inprogress/` case at all.

   The owed stem is computed by hand in two places, `run-review.sh` `refuse_unowed_conformance_plans` (`owed=…`) and `queue_conformance_check` (`stem=…`). Today they match, but if one drifts, a resumed pass is refused with "delete it" and nothing in the gate catches it.

   **Assertion to add** (`self/tests/brief-conformance.sh`, under L1 or B1): in a feature with an owner brief, queue `01-review-<model>.md` and its owed `01-conformance-<model>.md` in `review/incomplete/` (as an interrupted pass leaves them), then run `run-review.sh`. It should exit 0, with no `refused` line, and run the conformance plan and then the review. Add the same check with the review in `review/inprogress/` and the owed plan beside it. Optionally, factor the stem into one shared helper so the two sites cannot drift.

## Deviations from the brief

None
