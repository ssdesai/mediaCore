# 01 — review: orchestrator-role-guard

Read-only review of one feature's diff against its spec. "No findings" is a legitimate
verdict. First line of your report: `Verdict: clean` or `Verdict: escalated`.

## What the feature was supposed to do

The owner's rule (2026-11-05): an orchestrator session spawns one implementer session per
feature and builds nothing itself. `LIFECYCLE.md` said so and `orchestration-start.sh`
recorded it, but nothing enforced it — a session holding an orchestration record could
still run `feature-start.sh` on its own branch, run a batch, or spawn a build delegate, and
one did. This feature makes the **orchestration record the role**: once a session's id is
the `session` of a record under `self/orchestrations/<slug>/README.md`, the lifecycle
scripts refuse to build in that session, and the PreToolUse hook names the remedy before a
script runs. Scripts first, hooks as early feedback, no GitHub CI. Five items:

1. **One role reader, shared.** A sourced helper beside `plan-runner-roots.sh`
   (`orchestrator-role.sh`) with one function, `orchestrator_record_for_session <id>`,
   printing the path of the record whose fence `session` equals the id (under
   `analysis/roots.py`'s `orchestrations_root`, tracked or not), or nothing. Pure, no side
   effects. The session id comes from `--session`, else `$CLAUDE_CODE_SESSION_ID`, the way
   `feature-start.sh` learns it. Unit-tested in `self/tests/` with a fixture record. The
   hook reuses the same rule in Python — if that is a tiny shared Python module both call,
   `NOTES.md` says so; the rule is not forked.
2. **The scripts refuse to build in an orchestrator session.** `feature-start.sh` (with and
   without `--self`), `run-plans.sh`, `run-verify.sh`, `run-review.sh`, `run-batch.sh`,
   `feature-close.sh`: before anything is written, when the reader finds a record naming
   the current session, one `  refused  …` line naming the record and the remedy ("this
   session is the orchestrator of `<slug>` (`<record path>`): a feature is built in a
   session of its own — create one with the implementer brief
   (`templates/plans/ORCHESTRATOR_BRIEF.md`) and never run this here"). `orchestration-capture.sh`
   and `manifest.py --orchestration …` stay allowed. The reverse guard: `orchestration-start.sh`
   refuses in a checkout holding a tracked feature manifest whose `branches[0]` is the
   current branch or whose `session` is the current session, naming the manifest. Tests in
   the `feature-lifecycle.sh` pattern: a fixture repo with a record naming session `S`;
   each script with `--session S` or `CLAUDE_CODE_SESSION_ID=S` refuses and writes nothing;
   another id proceeds as before; the reverse guard refuses beside a tracked manifest.
3. **The hook names the remedy early.** `hooks/allow-repo-commands.sh`: when the payload's
   `session_id` matches a record in the project root, a Bash command invoking any item-2
   script is denied with the same reason text. A second PreToolUse matcher for the `Agent`
   tool, wired by `hooks/wire-settings.py` (`.claude/settings.json` regenerated, byte for
   byte), denies an `Agent` call from an orchestrator session whose `prompt` begins with
   the cost-capture marker `feature: ` (`ORCHESTRATION.md`); any other `Agent` call is
   allowed. Both entries guarded like the existing one (a no-op where the script is absent).
   `hooks/README.md`: a section under "The three outcomes" and a row under "Cross-layer
   dependencies" (the record's path and the `feature: ` marker are the contracts). Tests:
   `self/tests/hook-*.sh` cases for the Bash denial, the Agent denial, the Agent allow, a
   session with no record untouched; `hook-wiring.sh` for the new matcher.
4. **The orchestrator session's own brief.** `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`
   (generated or seeded per `sync-plans.sh`'s two kinds — the ruling in `NOTES.md`): first
   command `orchestration-start.sh <slug>`; one feature per child session from a copy of
   `ORCHESTRATOR_BRIEF.md`; `manifest.py --orchestration <slug> add-feature` after each
   spawn; the forbidden commands and why; the end (`set-window-to now`, capture, report,
   records-only PR). `sync-plans.sh` ships it; `LIFECYCLE.md` → "Orchestrator and
   implementer sessions" and "Orchestration records" point at it and at the guard;
   `README.md`'s script table rows for the touched scripts; `self/PROJECT_FACTS.md` where a
   fact changed.
5. **Doctrine lines.** `LIFECYCLE.md` and `ORCHESTRATION.md`: one paragraph each — the role
   is the record, the scripts refuse on it, the hook names the remedy, the remedy is a child
   session. `self/features/orchestrator-role-guard/NOTES.md` carries the rulings;
   `self/BACKLOG.md` anything deferred.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **One reader.** The shell helper and the hook decide "is this session an orchestrator"
  by the same rule: a record under `orchestrations_root` whose fence `session` equals the
  id, exactly. No second spelling of the record path or the fence key; if the hook has a
  Python twin, it reads the same files the same way and `NOTES.md` says where the one rule
  lives. The reader is pure: it writes nothing, runs no git mutation, tolerates a missing
  `self/orchestrations/` and a record with no readable fence.
- **Before anything is written.** In every item-2 script the refusal precedes the first
  write, the first `mkdir`, the first stamp, the first `git` ref move. `feature-start.sh`'s
  refusal comes before its lock, its exclude-file edit and any fetch; the runners' before
  `run_all`'s `mkdir -p`; the close's before the PR. A session with no record, or with no
  session id at all, behaves exactly as before — every existing test still passes.
- **The refusal shape** is the scripts' own: `  refused  <text>` on stderr, exit 1, the
  text naming the slug, the record path and `templates/plans/ORCHESTRATOR_BRIEF.md`.
- **Allowed stays allowed.** `orchestration-start.sh`, `orchestration-capture.sh`,
  `manifest.py --orchestration …`, `report.py --orchestration`, and every read-only
  command are unchanged for an orchestrator session; the hook denies only a Bash line that
  invokes an item-2 script, and only when the payload's `session_id` matches a record.
- **The reverse guard** refuses `orchestration-start.sh` only beside a *tracked* feature
  manifest whose `branches[0]` is the current branch or whose fence `sessions` holds the
  current session; it writes nothing on refusal, and `self/tests/orchestration-records.sh`
  still passes.
- **The Agent matcher.** `wire-settings.py` writes a second `PreToolUse` entry with
  `matcher: "Agent"`, guarded exactly like the Bash one; `--self --check` is byte for byte
  and `self/gate.sh` passes it; a consuming repo's merge adds the entry when absent and
  never duplicates it (`hook-wiring.sh`). The hook denies an `Agent` call only when the
  session is an orchestrator AND `tool_input.prompt` begins with `feature: `; a prompt
  mentioning the marker mid-text, a non-orchestrator session, or a payload with no
  `session_id` is left alone (the hook prints nothing — never an `allow` that would widen
  the policy). The hook never exits non-zero on a malformed payload.
- **Confinement.** Only `hooks/env_profile.py` and `env-profile.sh` spell
  `AGENTTOOLING_PROFILE` or `CLAUDE_CODE_REMOTE` outside the tests and adapters
  (`self/profile-confinement.sh`); every new test pins `AGENTTOOLING_PROFILE` and clears
  `CLAUDE_CODE_REMOTE`; no test reads the real `~/.claude`.
- **Templates.** `ORCHESTRATOR_SESSION_BRIEF.md` is registered in the kind `NOTES.md`
  rules (the `GENERATED` list, or seeded), `templates/README.md` and
  `templates/plans/README.md` name it, `sync-check.sh`/`orchestrator-brief.sh` still pass,
  `TEMPLATE_VERSIONS` is unchanged unless the ruling was "seeded". Every agentTooling-root
  path in it carries the `<tooling>/` prefix convention the implementer brief uses.
- **READMEs and the index.** `check-readme-index.py` passes: every new file has its line
  (`README.md`'s script table for `orchestrator-role.sh`, `self/tests/README.md` for each
  new test, `hooks/README.md` for the new section and row, `templates/README.md`).
  `self/gate.sh` lists each new test in both its `bash -n` list and a `record` line.
- Nothing under `.claude/` was hand-edited (the settings file is regenerated); nothing
  under another feature's folder or `self/orchestrations/` changed; no model identifier in
  a committed file; bash 3.2 compatible (no associative arrays, no `${v,,}`), `set -uo
  pipefail` with no `set -e`, named constants for every literal in the new scripts.
- Report anything the docs now state wrongly — a `LIFECYCLE.md` or `ORCHESTRATION.md`
  sentence still saying the rule is unenforced, a README row that omits the guard.

## Verdict
