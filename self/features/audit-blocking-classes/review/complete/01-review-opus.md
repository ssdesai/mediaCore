# 01 — review: audit-blocking-classes

## What the feature was supposed to do

Write the repository owner's ruling (2026-11-16) on security-audit findings into the
tooling. A security audit blocks the close only on BLOCKING findings:

- (a) a regression: the head's outcome for an input is more permissive than the base's —
  a deny or ask that becomes an allow, a deny that becomes an ask;
- (b) a silent ALLOW of a command that writes or runs something not read-only, even when
  the base allows it too.

Every other finding is NON-BLOCKING (pre-existing, identical on the base, prompt-only): it
is listed in the report and filed as a follow-up, and it does not escalate the round. The
ruling applies to feature audits and to propagations (a consuming repo's
`pull-agenttooling-*` feature, whose base is the vendored agentTooling version it
replaces).

Concretely:

1. `templates/SECURITY_AUDIT.md` carries the rule: every finding is classed `blocking` or
   `non-blocking` in a `## Findings` table whose FIRST column is the class; a non-blocking
   class is evidenced by the base's outcome for the same input, from the base's hook run
   in a second throwaway copy; anything the auditor cannot classify with evidence counts
   as blocking; `Verdict: clean` means no blocking finding, and non-blocking findings are
   still listed under `## Non-blocking findings`.
2. `run-review.sh` `build_audit_prompt` step 4 no longer says "clean (no bypass found) /
   escalated (at least one)"; it defers to the plan's classification. Verdict meaning only.
3. `feature-close.sh` adds ONE check after the existing ones: a clean audit report at the
   judged head whose `## Findings` section is missing, or holds a row classed `blocking`,
   or a row/line it cannot read as classed, is refused (fail closed). The reader is a
   function in `plan-runner-roots.sh`.
4. `feature-start.sh`'s worktree refusal names the primary checkout's own
   `feature-start.sh` — `<primary>/feature-start.sh` standalone,
   `<primary>/agentTooling/feature-start.sh` vendored — instead of
   `<common-root>/<worktree absolute path>`. Message text only; the refusal itself stays.
5. Docs: `LIFECYCLE.md` "The security audit" and a line in "Propagate"; one bullet in
   `ORCHESTRATION.md`; the audit paragraph in `hooks/README.md` (docs only); the folder
   READMEs the change touches.

Excluded: `hooks/allow-repo-commands.sh` (a parallel feature, PR #147, owns it) and every
hook rule; `.claude/` and settings.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- UNCHANGED, byte for byte in behaviour: `report_verdict` (first line only), the audit
  fingerprint and `stale` stamp in `run-review.sh`, the audit-at-judged-head check, the
  base checks (moved base, empty diff), `audit_plan_matches_template`, and every existing
  refusal message in `feature-close.sh`'s audit block. The new check comes after them.
- The template contains no `{{` other than the four existing placeholders (`{{NN}}`,
  `{{SLUG}}`, `{{DIFF_BASE}}`, `{{FILES}}`), so `audit_plan_matches_template` and the
  renderer still match it.
- The classification reader fails closed: no `## Findings` heading, a row whose first
  cell is neither `blocking` nor `non-blocking`, or a non-table line other than `None.`
  in that section, is a refusal; a pipe inside a later cell cannot move the class column.
- `self/tests/security-audit.sh` asserts: only non-blocking findings under
  `Verdict: clean` → the close passes the audit check; a blocking finding → refused; an
  unclassified finding → refused; the template carries the rule text and both headings.
  Existing assertions R1–R5, C1–C5, F1–F7, N8–N11 still pass with the stub's report in the
  new shape.
- `self/tests/feature-lifecycle.sh` asserts the worktree refusal names the primary's
  `feature-start.sh`.
- `hooks/allow-repo-commands.sh` and `.claude/` are not in the diff.
- READMEs current for every folder touched (`self/tests/README.md`, `templates/README.md`
  if it describes the template's contents).
- `self/features/audit-blocking-classes/NOTES.md` records that this round's own audit is
  rendered from the branch's new template (run-review.sh renders from `$SCRIPT_DIR/templates`
  and the close compares against the same file), and the reading of "prompt-only
  (deny→ask)" against (a).

## Verdict

"No findings" is a legitimate verdict — say it outright rather than manufacturing
concerns.
