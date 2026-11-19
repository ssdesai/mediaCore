Verdict: escalated

# Review — hook-role-hardening (01-review-opus)

## What the batch was supposed to do

Four fixes from the security audit of PR #138, plus one lifecycle rule:

- **F1**: an orchestrator cannot drop its role with one Edit. This covers the consumer-layout `ask` rule on the records folder, coordinator-by-shape, reading every fence, and `manifest.py --orchestration` refusing `session=`/`branch=` on a coordinator record.
- **F2**: `orchestration-start.sh` validates the session id.
- **F4**: `invokes_build_script` is no longer fooled by wrappers.
- **Hook security audit**: a hook diff queues a security audit beside the review, and `feature-close.sh` refuses to close until that audit is clean on the judged head.

## Does it do it

Mostly, yes. Checked against the spec's contracts:

- **One role rule.** `hooks/orchestrator_role.py` is still the one place the role rule lives. The hook and `plan-runner-roots.sh` both call it, now with a `--` before the positional arguments. The design grew past the spec: there is now a ledger under the git common dir and a read of each record as first committed. Each of these additions is a decision recorded in NOTES.md and documented in `hooks/README.md` and `LIFECYCLE.md`.
- **Coordinator shape.** `orchestrator_shaped`/`is_role` and `manifest.py`'s `COORDINATOR_REFUSED_FEATURE_KEYS` mirror each other (`session`, `branch`). Both name each other in their comments.
- **Settings.** `wire-settings.py` adds `Edit(**/agentTooling/self/orchestrations/**)` for the consumer layout only. The `--self` spelling was dropped deliberately (NOTES.md F9). The gate's settings check passes.
- **F2.** `SESSION_PATTERN` and `SESSION_MAX_CHARS` are applied to both `--session` and the `$CLAUDE_CODE_SESSION_ID` fallback.
- **Audit plans are not review rounds.** `completed_review_count` and `latest_review_plan` skip audit stems. The audit's verdict uses `VERDICT_PREFIX`/`report_verdict`.
- **Tests.** `self/tests/security-audit.sh` covers both directions the plan asks for: C3/C4 refuse a hook diff with no clean audit, and C2 shows a non-hook diff closes as before. It also covers the hardening rounds.
- **Docs.** `LIFECYCLE.md`, `hooks/README.md` and `ORCHESTRATION.md` describe the new behaviour. LIFECYCLE's list of audit paths matches `AUDIT_TOOLING_PATHS`.
- **Gate.** `self/gate-report.txt` is green, with no SKIPPED checks.

The security audit that ran in this same pass (`self/features/hook-role-hardening/audit-report.md`) came back **escalated** with two bypasses. I confirmed both by reading the code. `feature-close.sh` refuses this round whatever this review says, so this review is escalated too and names both bypasses below as the next round's work.

## Fixed in this pass

Nothing. I tried to apply B1's one-word fix to `hooks/allow-repo-commands.sh`, but the `Edit(**/hooks/**)` ask rule correctly held it for a human, and no human approves edits in an unattended pass. So it is escalated below.

## Escalated to the next round

1. **B1: `uniq - OUT` writes a file past the orchestrator allowlist.** This is in `hooks/allow-repo-commands.sh`, in `orchestrator_operands` (about line 3688).
   - **What's wrong:** a word counts as an operand only if it does not start with `-`. That drops the bare `-` (stdin, an input operand), so `uniq - orchestration-start.sh` counts one operand and is admitted.
   - **What it reaches:** with stdin piped in, it overwrites a script the allowlist then runs, or `.git/agenttooling-orchestrators` (the ledger), or `.git/config`. Each is one human prompt rather than a deny, and under `bypassPermissions` there is no prompt at all.
   - **Fix:** treat `w == "-"` as an operand in both branches, e.g. a helper `is_orchestrator_operand(w)` returning `w == "-" or not w.startswith("-")`, with `"-"` as a named constant beside `ORCHESTRATOR_END_OF_OPTIONS`.
   - **Test:** add `'uniq - out'`, `'echo x | uniq - out'`, `'uniq -c - out'` and `'uniq --skip-fields=1 - out'` to `ROUND3_ROWS` in `self/tests/hook-orchestrator-role.sh`, next to the R7 rows (about line 974). Leave them out of `ROUND3_ADMITTED`, so the test asserts they are denied. `echo '#!/bin/sh' | uniq - -hook` stays admitted: with the fix it counts one operand.

2. **B2: the audit trigger misses entry points the orchestrator allowlist executes.** This is in `plan-runner-roots.sh`, `AUDIT_TOOLING_PATHS`.
   - **What's wrong:** the array leaves out files the allowlist runs: `orchestration-capture.sh`, `analysis/report.py`, `analysis/capture_planning.py`, `analysis/orchestration_capture.py`, and the modules they import (`analysis/roots.py`, `routing.py`, `pricing.py`, `transcript.py`). NOTES.md R2 says "the residual route is editing the real tooling files — and those are audit paths". That is false for these files.
   - **Same problem in this diff:** this diff changes `orchestration-capture.sh` (the symlink resolution), and neither the audit's file list nor the close's trigger names it.
   - **Decision needed:** either list every file the allowlist executes and imports, or take `analysis/` whole, which audits every analysis change. Either way, the same list goes into `LIFECYCLE.md` → "The security audit", and `security-audit.sh` F6 needs a case for `orchestration-capture.sh` and for an `analysis/` import.

The next round's audit re-runs automatically, because these fixes touch audit paths.
