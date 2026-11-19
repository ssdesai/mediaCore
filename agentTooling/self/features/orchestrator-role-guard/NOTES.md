# Notes: orchestrator-role-guard

Rulings, one line of rationale each. R1–R10 were decided by the coordinator before the
build; M1 onward are the implementer's.

## Rulings taken before the build

- **R1. The one rule is `hooks/orchestrator_role.py`** (stdlib, beside `policy.py`):
  `record_for_session` (last fence's `session`, exact compare, unreadable or unparseable is
  skipped), `refusal_reason` (one constant template), a CLI that exits 0 always. The
  record path is a named constant mirroring `analysis/roots.py` and `orchestration-start.sh`.
  Rationale: the hook and the shell must never answer differently, and the hook cannot
  import `analysis/`.
- **R2. The shell reader lives in `plan-runner-roots.sh`** (`orchestrator_record_for_session`,
  `refuse_orchestrator_session`). Rationale: every lifecycle script already sources it and
  thirty test fixtures already copy it, so no fixture needs a new file; a copy with no
  `hooks/` module has no record.
- **R3. Guard placement, before any write**: `feature-start.sh` right after `ROUTER_SESSION`
  (so `--session` is honoured); the three runners right after the `--self` shift;
  `run-batch.sh` after it and before its first `mktemp`; `feature-close.sh` after the
  argument loop. `orchestration-capture.sh` and `manifest.py --orchestration` are not guarded:
  they are the record's own tools.
- **R4. Reverse guard in `orchestration-start.sh`**: refuses when a tracked manifest names
  the current branch as `branches[0]` or lists the session in `sessions`. Rationale: a
  coordinator cannot become an orchestrator mid-feature, or it would be refused its own
  close. `self/tests/orchestration-records.sh` copies `plan-runner-roots.sh` for it.
- **R5. The hook**: `main()` handles `Bash` and `Agent`; a first Bash judge for a build
  script at command position or as `bash`/`sh`'s first non-flag argument; an `Agent` deny
  only for a prompt that STARTS with `feature: `; never an allow; any failure is silent.
- **R6. `wire-settings.py` wires a second `PreToolUse` entry, matcher `Agent`**, per
  matcher in the ordered tuple `HOOK_MATCHERS`; a consumer merge adds a missing matcher's
  entry and keeps a customized one; `.claude/settings.json` regenerated, never hand-edited.
- **R7. `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md` is GENERATED** (listed in
  `sync-plans.sh`'s `GENERATED`, no `template-version`), because it holds nothing
  repo-specific and must follow the scripts.
- **R8. Tests**: `orchestrator-role.sh`, `hook-orchestrator-role.sh`, the `hook-wiring.sh`
  extension, each in `self/gate.sh`'s `bash -n` list, given a `record` line, and a row in
  `self/tests/README.md`.
- **R9. Docs** in `hooks/README.md`, `LIFECYCLE.md`, `ORCHESTRATION.md`, `README.md`,
  `self/PROJECT_FACTS.md`, `self/tests/README.md`, `self/orchestrations/README.md`,
  `templates/README.md`, `templates/plans/README.md`; deferrals in `self/BACKLOG.md`.
- **R10. Size and style**: named constants, bash 3.2, `set -uo pipefail`, no model
  identifier in a committed file.

## Rulings taken in the build

- **M1. Commit trailers carry the `Co-Authored-By` line this session's own attribution
  instruction gives, not the model name the brief quotes.** Rationale: the harness's
  attribution reminder replaces earlier guidance, and the implementer brief template itself
  says "the two trailer lines your own session instructions give you". The
  `Claude-Session` line is identical in both; only the `Co-Authored-By` name differs
  (see the commit messages).
- **M2. `refuse_orchestrator_session` calls the module twice** (once through
  `orchestrator_record_for_session` to decide, once with `--reason` to render). Rationale:
  it runs once per script start, on a copy that has a record; a single call returning two
  values would need a protocol the CLI deliberately does not have.
- **M3. The hook runs the cheap command reading first, and looks the record up only for a
  command that would build.** Rationale: the hook runs on every Bash call; an ordinary read
  must not pay a directory scan. `invokes_build_script` uses `command_words`, the reader the
  git deny uses, so a heredoc or a line that does not tokenize is not judged (a deny must not
  fire on a guess). A leading `NAME=value` word is skipped (`ENV_ASSIGNMENT_RE`).
- **M4. A non-dict payload or `tool_input` is a quiet return** in `main()`. Rationale:
  "the hook never exits non-zero"; the old code raised on a non-dict `tool_input`.
- **M5. The reverse guard reads the checkout with `git ls-files`, relative to the script's
  directory for `self/features` and to the git toplevel for `plans/features` (only when the
  toplevel differs from the script's directory).** A copy with no git above it skips the
  guard. Rationale: R4's wording; the unreadable case is recorded in `self/BACKLOG.md`.
  The vendored half has no test of its own here (the fixture is a standalone checkout);
  the code path is the same `held_feature` function with another label.
- **M6. `hook_wired` is per matcher; the gap message names the matcher** (`no Agent hook
  entry`, `no Bash hook entry`) instead of the old `allow-repo-commands.sh hook`. No test or
  doc read the old wording; `no-session`'s "allow-repo-commands not in message" check still
  holds.
- **M7. The orchestrator-session brief says `<tooling>` exactly as `ORCHESTRATOR_BRIEF.md`
  does**, is 78 lines, and every agentTooling-root script it names carries the prefix.
- **M8. The hook-test fixtures copy `orchestrator_role.py` beside `policy.py`.** A fixture
  that copies the hook without it is silent (guarded import), so no older fixture needed a
  change.
