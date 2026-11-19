# Checkpoint: vendored-edit-ask

status: committed
updated: 2026-11-13T19:15:00Z
gate: not run (the coordinator's); run: hook-wiring.sh, self-settings.sh, `--self --check`, readme index (with the gate's --ignore), py_compile — all green

## Slices
- [x] acceptance tests — self/tests/hook-wiring.sh (red before the build, green after)
- [x] 1. wire-settings.py: POLICY_ASK_RULES, RETIRED_EDIT_ASK_RULES, gaps_in/apply_gaps/describe_changes, docstring and comments
- [x] 2. read-only verification of update.sh and consumer-side Edit instructions (none found)
- [x] READMEs: hooks/README.md, README.md, self/README.md, self/BACKLOG.md, self/tests/README.md

## Learned
- `check-readme-index.py` needs `--root` and `--ignore self/readme-index-ignore` as the gate passes them; bare it lists hundreds of historical lines.
- security-audit.sh does not name the ask rules; only hook-wiring.sh asserts them.

## Resume
- `bash /home/user/agentTooling/self/tests/hook-wiring.sh`
- `python3 -B /home/user/agentTooling/hooks/wire-settings.py --self --check --repo /home/user/agentTooling`
- the whole gate is the coordinator's
