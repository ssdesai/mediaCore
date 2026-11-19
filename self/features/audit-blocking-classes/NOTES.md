# audit-blocking-classes — notes

Decisions for the feature (`README.md`), which writes the repository owner's ruling of
2026-11-16 into the tooling: `templates/SECURITY_AUDIT.md` (steps 5 and "## Verdict"),
`run-review.sh`'s audit prompt (step 4), `plan-runner-roots.sh`'s `audit_report_unclassed`,
`feature-close.sh`, and `self/tests/security-audit.sh` (B1–B5).

## Rulings

1. **The classification check is ADDED to the close, after the existing checks.** The
   existing ones are unchanged and run first: `report_verdict`, the fingerprint / `stale`
   stamp, the audit at the judged head, the base checks and `audit_plan_matches_template`.
   The template's rule alone is a model instruction; the tests require a clean report with a
   `blocking` or unclassified row to be refused, so `feature-close.sh` runs
   `audit_report_unclassed` on the committed report at the judged head and refuses anything it
   prints. Fail closed: no `## Findings` section, any line in it that is not `None.`, a blank
   line or a table row, and any row whose first cell is not `non-blocking` are problems.
2. **`run-review.sh`'s `audit_end` stamp still reads only the first line** of the report. A
   `Verdict: clean` report holding a blocking row is therefore stamped clean and refused at
   the close, not restamped by the runner.
3. **This round's own audit is rendered from the branch's new template.** `run-review.sh`
   renders from `$SCRIPT_DIR/templates` and the close compares the completed plan against
   the same file, so the round that introduces the ruling is audited under it.
4. **"A deny that becomes an ask" is blocking (a); "prompt-only (deny to ask and the like)"
   is non-blocking.** Read as: an input the base denies that the head only asks about is a
   regression. A finding that asks on the head where it should deny, and does not deny on the
   base either, is prompt-only — same result both sides, nothing got more permissive.
5. **The class is the table's FIRST column.** `audit_report_unclassed` reads only the text
   between the first and second `|` of a row, so a `|` in a later cell (a probed command,
   even inside backticks) cannot move it. Separator rows are skipped; the header is skipped
   once per section, as the first row whose first cell is `class` (a second such row is
   unclassified), so a table with no header has its first finding read, not skipped (B5).
6. **`feature-start.sh`'s worktree refusal named the wrong path.** In the standalone layout
   `${SCRIPT_DIR#"$PRIMARY"/}` strips nothing when `SCRIPT_DIR` equals `PRIMARY`, so it
   printed `<common-root>/<worktree absolute path>`. It now prints the primary's own
   `feature-start.sh`: the directory above the absolute git common dir, plus
   `agentTooling/` when vendored (`self/tests/feature-lifecycle.sh` S2d2, S6j). Message text
   only; the refusal is unchanged.
