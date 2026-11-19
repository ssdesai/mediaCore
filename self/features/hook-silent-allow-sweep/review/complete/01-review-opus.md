# 01 — review: hook-silent-allow-sweep

Review this feature's diff against the seven items below, written from the spec (the
owner's 2026-11-18 triage of `self/BACKLOG.md`), not from the builder's report. Each item
closes one backlog entry where `hooks/allow-repo-commands.sh` (or the role reader in
`plan-runner-roots.sh`) approves silently what it should prompt for or deny. "No findings"
is a legitimate verdict.

## What the feature was supposed to do

1. **Glob in a read-only git's `-C` / `--git-dir`.** A `-C` or `--git-dir` value holding a
   pattern character (`*`, `?`, `[`, or an extglob such as `@(`, `!(`, `+(`, `*(`, `?(`)
   is no silent approval: it prompts (or every glob match passes the planted-gitdir check).
   Covers `git -C plans/e?il status`, `e*l`, `evi[l]`, `git -C plans -C e?il log`, and the
   `diff --no-index a b` form.
2. **Git helper environment on the own-branch push.** A set `GIT_EXEC_PATH`, `GIT_SSH`,
   `GIT_SSH_COMMAND` or `GIT_PROXY_COMMAND` in the hook's environment stops the own-branch
   push approval (it prompts), beside `OWN_PUSH_ASKPASS_ENVS`.
3. **`GIT_CONFIG` and the own-push probe.** A `GIT_CONFIG` in the hook's environment can no
   longer hide the effective config from the own-push probe: either the probe runs with it
   removed, or any `GIT_CONFIG` is no approval. A url-only `GIT_CONFIG` file beside a
   local `credential.helper = !…` prompts. `hooks/README.md` gains one sentence that a
   `GIT_ASKPASS` exported only by a shell rc file reaches the push but not the hook.
4. **Own-branch push inside a chain.** The own-branch push is approved only when it is the
   whole command; `git push origin <B> && cat README.md` (and any other chain, pipe or
   list) is sent back with "run the push alone" or prompts.
5. **`--config` / `--config-file`.** These approve only the names the tool discovers itself
   (`pyproject.toml`, `ruff.toml`, `.ruff.toml`, `mypy.ini`, `.mypy.ini`, `setup.cfg`),
   or prompt on every use. `ruff check --config fix.toml …` and
   `mypy --config-file cfg.ini …` are no longer approved silently.
6. **Entry points matched too loosely.** The `analysis/` entry points (`report.py`,
   `manifest.py`, `capture_planning.py`) are approved only from the one directory that
   holds the running hook (`<root>/analysis/` for `<root>/hooks/…`,
   `<root>/agentTooling/analysis/` for `<root>/agentTooling/hooks/…`); the other prompts.
   `gate.sh` is approved only as `self/gate.sh` or `plans/gate.sh`, `check-plans.sh` only
   as `check-plans.sh` or `agentTooling/check-plans.sh`; the same basename elsewhere
   (`x/gate.sh`, `x/check-plans.sh`) prompts.
7. **Role reader fails closed.** `plan-runner-roots.sh`'s role reader no longer reads a
   missing or crashing `hooks/orchestrator_role.py` / `hooks/shared_rules.py` as "no
   record": a build script refuses, naming the module.

Excluded: the broader "writable git config" entry, the `.git` Edit-deny check, the deny-side
entries, and anything the sibling features `orchestration-start-branch-v2` and
`branch-sync-and-fanout-docs` own. A reviewer finding outside the seven items that is not a
regression this feature introduces is non-blocking and goes to `self/BACKLOG.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Each item has a test row in `self/tests/allow-repo-commands.sh` (or the existing test
  file for its area, e.g. `self/tests/` for the role reader) that fails on main and passes
  here; the gate (`./self/gate.sh`) is green.
- No previously approved legitimate form regresses: `git -C <literal in-root dir> status`,
  the plain own-branch push run alone from the root, `ruff check` / `mypy` with no
  `--config` or with a discovered name, `self/gate.sh`, `plans/gate.sh`,
  `check-plans.sh`, `agentTooling/check-plans.sh`, and the pinned `analysis/` entry points
  stay approved.
- `OWN_PUSH_ASKPASS_ENVS` (or the constant beside it) names the four new variables; the
  own-push probe's handling of `GIT_CONFIG` is explicit in `hooks/allow-repo-commands.sh`.
- The analysis pin is derived from the hook's own location, as `orchestrator_tooling_file`
  derives its pin.
- The role reader's refusal names the missing or failing module.
- `hooks/README.md` and `CONVENTIONS.md` describe the new behaviour where they described
  the old (the own-branch push "run alone", the narrowed entry points); each closed entry
  is removed from `self/BACKLOG.md`.
- Named constants for new literal sets (file names, env names), per `CONVENTIONS.md`.

## Verdict
