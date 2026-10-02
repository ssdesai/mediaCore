# Checkpoint: sandbox-consumer-reads

status: committed
updated: 2026-09-30T21:40:00Z
gate: === gate: done — all checks passed ===

## Slices
- [x] premise check — the doc and a live probe show repository `allowRead` is dropped under the read block; feature rescoped (f233b81)
- [x] acceptance tests — hook-wiring.sh, self-settings.sh assert `enabled` == the SANDBOX_ENABLED switch (false) and the set-back (9b17542; red before the build)
- [x] 1. `SANDBOX_ENABLED = False` in hooks/wire-settings.py feeding `SANDBOX_OWNED_SETTINGS`; worktree settings regenerated
- [x] 2. hooks/README.md → "The sandbox block" (off by default, why, how to turn on; the allowRead finding), RUNNER.md sandbox paragraph conditional, root README rows
- [x] 3. self/BACKLOG.md — consumer-verify entry rewritten (user settings → switch → propagation → vinyl verify), gate-outside-sandbox entry added
- [x] 4. NOTES.md — probe evidence, the switch, rulings
- [x] 5. manifest prose above the fence
- [x] READMEs for every folder touched (hooks/, root, self/tests/); gate green

## Learned
- The delegate's Bash cwd resets between calls, so a `claude -p` that must run from the worktree goes through a launcher script that sets the cwd itself.
