# 08 — verify: harness-arm-base

**Feature `harness-arm-base`, plan 8 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics (files and bytes read before the first edit, README bytes read)
beside the cost figures.

Read `self/gate-report.txt` first; do not re-run the gate or any of its sections. If a
section failed, triage it, fix what is local (a wrong grep, an assertion on the wrong
field, a drifted README line), and re-run only that one script.

Read the tests before checking anything: `harness/tests/arm-base.sh`,
`harness/tests/reading-metrics.sh`, and `harness/tests/smoke.sh`'s section 8b plus the
`arm_kind` / reading-field checks added to sections 6 and 9c2. Check only what they leave
uncovered:

1. **Real transcript shape.** The reading tests run on transcripts the test author
   fabricated from a model of the format. Run `python3 harness/reading_metrics.py
   analysis <a worktree or checkout this machine has real Claude Code sessions for>
   --from <a start> --to <an end>` over a window you know contains `Read` and `Edit`
   calls (this session's own project directory under `~/.claude/projects/` will do), and
   confirm the figures are non-zero and plausible against what that session did — in
   particular that `tool_result` content and `tool_use_id` matching work on real lines.
   If they do not, fix `reading_metrics.py` and add the real shape to
   `reading-metrics.sh` as a case.
2. **Executable bits.** `harness/tests/arm-base.sh` and `harness/tests/reading-metrics.sh`
   carry the same mode as `harness/tests/scorecard-arms.sh`; set it if not.
3. **agentTooling arms intact.** `git diff` the base for `harness/tests/scorecard-arms.sh`,
   `scorecard-programs.sh` and `scorecard-programs.cells.md`: none may have changed. A
   change to any of them is a finding, not a fix.

"Passing" is: the gate report shows every experiment-harness section passed (five
records, none skipped), and items 1–3 hold. Anything needing a new function or a
signature change is escalated, not fixed here.
