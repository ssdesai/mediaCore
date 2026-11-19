Verdict: clean

# Review — audit-blocking-classes

## What the batch was supposed to do

Write the repository owner's ruling (2026-11-16) on security-audit findings into the
tooling. An audit escalates only on a **blocking** finding: (a) a regression against the
base (deny/ask → allow, deny → ask), or (b) a silent allow of a non-read-only command, even
when the base allows it too. Everything else is **non-blocking**. Non-blocking findings are
listed and filed as follow-ups, and they don't escalate the round. Concretely: the template
rule and report shape, `run-review.sh` audit-prompt step 4, one fail-closed check in
`feature-close.sh` backed by a reader in `plan-runner-roots.sh`, the `feature-start.sh`
worktree-refusal message, and the docs.

## Does it do it

Yes. Checked against each contract in the brief:

- **The template** (`templates/SECURITY_AUDIT.md`):
  - Step 5 carries both classes.
  - The evidence for a non-blocking class is the base's result, from a second throwaway copy built with `git archive {{DIFF_BASE}}`.
  - A finding that can't be classed with that evidence is blocking.
  - The rule covers propagations too.
  - `## Verdict` sets the report shape: a `## Findings` table with the class in its first column, or `None.`, then `## Non-blocking findings`.
  - The only placeholder added is the existing `{{DIFF_BASE}}`, so `audit_plan_matches_template` and the renderer still match the template.
- **`run-review.sh`:** step 4 defers to the plan's classification, and only the verdict text changed. `report_verdict`, the fingerprint and the stamps are untouched.
- **`feature-close.sh`:**
  - The new refusal comes after every existing check: the verdict stamp, the judged head, the pinned model, the report verdict and commit, and `audit_plan_matches_template`.
  - No existing message changed.
  - It runs only after `report_verdict` has already required `Verdict: clean`.
- **`audit_report_unclassed` fails closed** on each case below:
  - no `## Findings` section;
  - a row whose first cell is neither class, compared after trimming, lowercasing and removing backticks;
  - a non-table line other than `None.`;
  - an indented row or a deeper heading inside the section.
  - The class is read as the text between the first two `|`, so a pipe in a later cell can't move it.
  - The `class` header row is skipped once per section, so a table with no header has its first row read rather than skipped (B5).
- **`feature-start.sh`:**
  - The refusal now names `<primary>/feature-start.sh` when standalone and `<primary>/agentTooling/feature-start.sh` when vendored.
  - S2d2 asserts the old `<root>//<abs path>` shape is gone.
  - S6j covers the vendored case.
- **Tests:** B1–B5 cover each case the brief requires. The stub audit now writes the new report shape, and the old assertions still pass (the gate is green).
- **Excluded paths:** `hooks/allow-repo-commands.sh` and `.claude/` are not in the diff.
- **Docs:** the LIFECYCLE audit paragraph and the Propagate line, the ORCHESTRATION bullet, the `hooks/README.md` paragraph, `self/tests/README.md` and `templates/README.md` all match the code.
- **NOTES:** `NOTES.md` records that this round is audited under the branch's own template, and how "prompt-only" reads against (a).

## Fixed in this pass

- `self/features/audit-blocking-classes/NOTES.md`:
  - The test range said B1–B4, but B5 exists. Changed it to B1–B5.
  - Ruling 5 said "the header row … is skipped". The reader actually skips only the first row whose first cell is `class`, once per section. Corrected the wording so it doesn't suggest a header-less table loses its first row.

## Escalated to the next round

None.

## Notes, not findings

- If the report is missing at the judged head, `audit_report_unclassed` runs awk on a file that doesn't exist, so awk prints an error to stderr before the existing report-verdict refusal fires. The outcome is unaffected: the close is refused either way, by the earlier message. This is cosmetic only.
- The gate's "pricing rate history is current" check exited 1, but the gate's verdict reads "all checks passed", so it is advisory. It is unrelated to this feature.
