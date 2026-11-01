# Checkpoint: hook-opaque-commands-and-audit

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-17T17:40:00Z
gate: all checks passed — 824 ok, 0 FAIL, 0 SKIP (shellcheck not installed, not counted),
      re-run after the rework; `check-plans --self hook-opaque-commands-and-audit`:
      14 checks, 0 failed

## Slices
- [x] acceptance tests — `self/tests/allow-repo-commands.sh`, new
      `self/tests/hook-escalation.sh`, `self/tests/stream-capture.sh` phase 10,
      registered in `self/gate.sh`. Committed alone, red (35 + 45 + 5).
- [x] 1. The opaque-command deny (spec §1) — `opaque_segments` and the six shape checks
- [x] 2. Escalation after 2 rewrites: state file under `$TMPDIR`, `ask` (spec §2)
- [x] 3. Headless fall-through + the `AGENTTOOLING_SCRATCH` entry point (spec §3)
- [x] 4. `plan-runner-lib.sh`: both exports through `env` at the `claude -p` site, the
      scratch directory inside `CAPTURE_TMPDIR`, one prompt line naming it (spec §3)
- [x] 5. The security audit (spec §4) — seven closures, each asserted beside its guard;
      everything considered is a row in `hooks/README.md`
- [x] 6. The git-deny reason names `feature-start.sh` alone (spec §5)
- [x] 7. Docs: `hooks/README.md`, `CONVENTIONS.md`, `RUNNER.md`, `self/tests/README.md`,
      root `README.md`, `NOTES.md` (15 rulings), three `self/BACKLOG.md` entries, the
      manifest's Slices table
- [x] gate green, then commit
- [x] rework (review E1–E4): `--add-dir` for the scratch directory + stream-capture
      10h–10i; `interpreter_takes_code` stops at the first non-flag word; a `cat` heredoc
      no longer excuses its own first line; the env-prefix audit row. `NOTES.md` →
      "Rework" R1–R5.

## Learned
- The hook payload distinguishes a subagent: `agent_id` is present only inside a
  subagent call, and `session_id` is the parent's (Claude Code hooks reference).
- `Edit(/hooks/**)` anchors at THE SESSION'S project root. For this build and for the
  rework — both delegated from a session rooted at the primary checkout — that is the
  primary, so Edit works on the worktree's `hooks/` copy. For a runner's executor, whose
  cwd *is* the worktree, it is the worktree, and the edit is refused: that is why the
  review pass escalated instead of fixing. Never brief a verify or review pass to change
  anything under `hooks/` (`NOTES.md` R5; start-procedure-and-routing ruling 6 holds only
  for the primary-rooted case).
- `self/tests/stream-capture.sh` `capture_dirs_left()` counts directories at depth 1
  under the redirected `$TMPDIR` and asserts exactly 1 in flight — so the executor
  scratch directory lives INSIDE `CAPTURE_TMPDIR`, not beside it.
- Taking the spec's "structural refusals" literally would deny commands the hook
  approves (`ls src # list it`) and writes whose fix is not a rewrite
  (`cat x > out.txt`). The opaque check therefore runs last and covers the six named
  shapes only — `NOTES.md` ruling 2, backlog entry filed.

## Resume
- Worktree `/Users/sahildesai/dev/agentTooling/.worktrees/hook-opaque-commands-and-audit`,
  branch `hook-opaque-commands-and-audit`, base `main`.
- Hook tests by hand: `bash self/tests/allow-repo-commands.sh`,
  `bash self/tests/hook-escalation.sh`, `bash self/tests/stream-capture.sh` — all green.
- Full gate: `./self/gate.sh` (a few minutes), then commit everything on the branch.
