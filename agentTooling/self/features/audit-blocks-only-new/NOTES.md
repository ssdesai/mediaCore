# audit-blocks-only-new — rulings

Coordinator's rulings, made before the build. Owner's request (2026-11-16), passed down by
the parent orchestrator as an urgent exception to the agentTooling freeze.

1. **The classification.** In `templates/SECURITY_AUDIT.md` step 5:
   - **blocking** is only a REGRESSION: the result on this head is more permissive than on
     the base for the same input — a deny or an ask that becomes an allow, or a deny that
     becomes an ask. That includes a silent allow the head introduces (the base denies or
     asks, the head allows).
   - **non-blocking** is every other finding: pre-existing (the base's result is the same),
     prompt-only, and a **pre-existing silent allow** (the base allows the same input too).
     A pre-existing silent allow is listed under `## Non-blocking findings` flagged as
     `pre-existing silent allow`, with what the rule should do instead; the coordinator of
     the feature that sees it files it in its BACKLOG (`self/BACKLOG.md`, or
     `plans/BACKLOG.md` in a consuming repo) before it closes.
   - Unchanged: a finding that cannot be classed with base evidence is blocking; the report
     shape (`## Findings` table, first cell the class; `## Non-blocking findings`).
   Rationale: clause (b) made each audit responsible for every pre-existing hole, so a
   feature could never converge; a regression is the only thing the feature itself caused.

2. **`feature-close.sh` does not check that non-blocking findings were filed.** Docs only.
   Matching free-text report rows against BACKLOG entries is fragile and would add a new
   way for the close to refuse — the opposite of this feature's purpose. The rule lives in
   the template, LIFECYCLE.md and ORCHESTRATION.md, where the coordinator reads it.

3. **Restatements updated with the same wording:** `LIFECYCLE.md` → "The security audit"
   ("What escalates a round"), `ORCHESTRATION.md`'s rule line (now names the BACKLOG, before
   the close), `hooks/README.md`'s one-sentence summary, `templates/README.md` if it
   restates the classes. `run-review.sh`'s audit prompt defers to "the plan's rule" and is
   left unchanged unless it restates clause (b).

4. **Tests.** `self/tests/security-audit.sh` B4 pins `SILENT ALLOW`; it now pins the new
   text (a pre-existing silent allow is non-blocking) and asserts the old clause ("even when
   the base allows it too") is gone. Rows are updated, never deleted; `self/tests/README.md`'s
   B4 description follows.

5. **BACKLOG.** The entry "The security audit has no convergence criterion" is replaced by a
   shorter remainder: this feature closes its main proposal (block only on a regression,
   file the rest); what is left is a round cap — after 2 audit rounds the owner rules what
   moves to BACKLOG.

6. **An audit is queued.** The parent's brief expected a review only, but
   `templates/SECURITY_AUDIT.md` and `hooks/` are audit paths (`plan-runner-roots.sh`
   `AUDIT_TOOLING_PATHS`), so `run-review.sh` renders an audit beside the review. It runs
   from this branch's template, i.e. under the new rule.
