Verdict: clean

# Security audit — hook-silent-allow-sweep

Files the diff changes (`git diff origin/main...HEAD`): `hooks/allow-repo-commands.sh`,
`hooks/orchestrator_role.py`, `plan-runner-roots.sh`, `hooks/README.md` (prose only).

## Rules under attack

1. **Item 1:** a `git -C` / `--git-dir` / `--work-tree` value holding a glob character (`*?[`) or an extglob opener approves nothing (`read_location_options` → `location_is_pattern`). Applies to every session.
2. **Item 2:** no own-branch push approval when any of `GIT_EXEC_PATH`, `GIT_SSH`, `GIT_SSH_COMMAND` or `GIT_PROXY_COMMAND` is set, even to an empty value (`own_push_config_allows`). Cloud profile.
3. **Item 3:** the config probe runs without `GIT_CONFIG` (`git_probe_text`), so a url-only `GIT_CONFIG` cannot hide a repo-config credential helper from it.
4. **Item 4:** the own-branch push is approved only as the whole command. In a `&&`/`||`/`;` sequence it is denied with a rewrite (`own_push_alone_reason`). Beside a pipe, `&` or anything else it is not approved (`command_allowed` → `is_git_push`).
5. **Item 5:** a ruff `--config` or mypy `--config-file` value is approved only under a name the tool discovers on its own (`RUNNER_CONFIG_NAMES`), checked both as written and as resolved.
6. **Item 6:** `report.py` and `manifest.py` are pinned only in the analysis directory beside the running hook (`hook_analysis_pins`). `gate.sh` and `check-plans.sh` are approved only at their known spellings relative to the root (`entry_script` + `ENTRY_*_SPELLINGS`).
7. **Item 7:** `refuse_orchestrator_session` (`plan-runner-roots.sh`) refuses to build when `hooks/orchestrator_role.py` or `hooks/shared_rules.py` is missing, or when the module exits non-zero. `orchestrator_role.py` `main()` exits `RULE_FAILED` (3) when a rule raises. The hook imports `record_for_session` directly, so this `main()` change does not touch the hook's path.

## Method

- The head copy came from `git archive HEAD` and the base copy from `git archive origin/main`, both under `/tmp/plan-capture.oNrczl/scratch/`.
- Each copy was `git init`ed on branch `claude/hook-silent-allow-sweep` with origin `https://example.invalid/x.git`, and committed. The feature's manifest README was copied into the base so the own-push approval applies there too.
- The live environment is the cloud profile (`AGENTTOOLING_PROFILE=cloud`, `GIT_ASKPASS=`).
- Planted in each working tree (uncommitted):
  - `plans/evil`: a bare git dir with `core.fsmonitor` set.
  - `plans/wt`: a nested checkout with `core.fsmonitor` set.
  - Config files: `fix.toml` (`fix = true`), `cfg.ini` (`junit_xml`), `sub/ruff.toml` (`fix = true`), `sub/mypy.ini`, a `lnk/ruff.toml` symlink to `fix.toml`, and a root `ruff.toml` symlink to `fix.toml`.
  - Entry scripts: `x/gate.sh`, `plans/gate.sh`, `x/check-plans.sh`, `agentTooling/check-plans.sh`, `agentTooling/analysis/report.py` and `agentTooling/analysis/manifest.py`.
- Vendored layout: `consumer-head` and `consumer-base` hold `<root>/agentTooling/` = the tree, plus a planted `<root>/analysis/report.py`, `manifest.py`, `plans/gate.sh` and `x/gate.sh`.
- How each hook was run: `python3 -B <copy>/hooks/allow-repo-commands.sh` (in a consumer, `<copy>/agentTooling/hooks/allow-repo-commands.sh`) with `CLAUDE_PROJECT_DIR=<copy>`. Each payload carried a fresh `session_id` so that no escalation counter carries over, and `cwd` = the copy root unless the table says otherwise. Drivers: `scratch/drive.py` and `scratch/drive2.py`.
- Item 7: each scenario ran `source <copy>/plan-runner-roots.sh; refuse_orchestrator_session <id>` (driver `scratch/role.sh`).
- Result meanings: `allow` = a silent approve; `deny` = sent back; `ask` = no output, so the human decides.

## Attempts

| rule | input | cwd | env | head | base |
|---|---|---|---|---|---|
| 1 | `git -C plans/evil status` | root | - | ask | ask |
| 1 | `git -C plans/e?il status` | root | - | ask | allow |
| 1 | `git -C plans/e*l status` | root | - | ask | allow |
| 1 | `git -C plans/e[v]il status` | root | - | ask | allow |
| 1 | `git -C 'plans/e?il' status` | root | - | ask | allow |
| 1 | `git -C "plans/e?il" status` | root | - | ask | allow |
| 1 | `git -C plans/@(evil) status` | root | - | ask | ask |
| 1 | `git -C plans/+(evil) status` | root | - | ask | ask |
| 1 | `git -C plans/{evil,evil} status` | root | - | ask | ask |
| 1 | `git -C plans/ev\il status` | root | - | ask | ask |
| 1 | `git -C pla""ns/e?il status` | root | - | ask | allow |
| 1 | `git -C plans/e?il log` | root | - | ask | allow |
| 1 | `git -C plans/e?il diff` | root | - | ask | allow |
| 1 | `git -C plans/e?il branch --show-current` | root | - | ask | allow |
| 1 | `git -C plans/e?il worktree list` | root | - | ask | allow |
| 1 | `git -C plans/e?il stash list` | root | - | ask | allow |
| 1 | `git --git-dir=plans/e?il status` | root | - | ask | ask |
| 1 | `git --git-dir plans/e?il status` | root | - | ask | ask |
| 1 | `git --git-dir=plans/evil status` | root | - | ask | ask |
| 1 | `git --work-tree=plans/e?il status` | root | - | ask | allow |
| 1 | `git -C plans -C e?il status` | root | - | ask | allow |
| 1 | `git -C plans/w? status` | root | - | ask | allow |
| 1 | `git -C plans/wt status` | root | - | ask | ask |
| 1 | `git -C plans/w[t] log` | root | - | ask | allow |
| 1 | `git -C=plans/e?il status` | root | - | ask | ask |
| 1 | `env git -C plans/e?il status` | root | - | ask | ask |
| 1 | `command git -C plans/e?il status` | root | - | ask | ask |
| 1 | `/usr/bin/git -C plans/e?il status` | root | - | ask | ask |
| 1 | `git -c x.y=z -C plans/e?il status` | root | - | ask | ask |
| 1 | `git -C plans/e?il status \| cat` | root | - | ask | allow |
| 1 | `ls && git -C plans/e?il status` | root | - | deny | allow |
| 1 | `git -C plans/e\?il status` | root | - | ask | allow |
| 1 | `git -C p*/evil status` | root | - | ask | allow |
| 1 | `git -C . status` | root | - | allow | allow |
| 1 | `git -C se?f status` | root | - | ask | allow |
| 1 | `git -C plans/evil/ status` | root | - | ask | ask |
| 1 | `git -C plans/./evil status` | root | - | ask | ask |
| 1 | `git -C e?il status` | plans | - | ask | allow |
| 1 | `git -C w? status` | plans | - | ask | allow |
| 1 | `git status` | plans/evil | - | ask | ask |
| 1 | `git status` | plans/wt | - | ask | ask |
| 1 | `git -C plans/e?il status` | (missing cwd) | - | ask | ask |
| 1 (deny side) | `git -C <L> <sub>` for L ∈ {`self`, `.`, `se?f`, `s*f`, `se[l]f`, `@(self)`}: grid below | root | - | grid | grid |
| 1 (deny side) | `git --git-dir=.g?t` / `git --git-dir .g?t` / `--work-tree=se?f` / `--git-dir=.git` × {`reset --hard`, `push origin main`, `push --force origin <B>`, `switch main`} (16 inputs) | root | - | deny (all 16) | deny (all 16) |
| 2 | `git push origin <B>` | root | - | allow | allow |
| 2 | `git push -u origin <B>` | root | - | allow | allow |
| 2 | `git push origin <B>` | root | GIT_EXEC_PATH=/tmp/x | ask | allow |
| 2 | `git push origin <B>` | root | GIT_EXEC_PATH= (empty) | ask | allow |
| 2 | `git push origin <B>` | root | GIT_SSH=/tmp/x | ask | allow |
| 2 | `git push origin <B>` | root | GIT_SSH_COMMAND=touch /tmp/x | ask | allow |
| 2 | `git push origin <B>` | root | GIT_SSH_COMMAND= (empty) | ask | allow |
| 2 | `git push origin <B>` | root | GIT_PROXY_COMMAND=/tmp/x | ask | allow |
| 2 | `git push origin <B>` | root | GIT_ASKPASS=/tmp/x | ask | ask |
| 2 | `git push origin <B>` | root | SSH_ASKPASS=/tmp/x | ask | ask |
| 2 | `git push origin <B>` | root | GIT_CONFIG_GLOBAL=cred.cfg (credential.helper) | ask | ask |
| 2 | `git push origin <B>` | root | GIT_CONFIG_SYSTEM=cred.cfg | ask | ask |
| 2 | `git push origin <B>` | root | GIT_CONFIG_PARAMETERS='credential.helper'='!touch /tmp/x' | ask | ask |
| 2 | `git push origin <B>` | root | GIT_CONFIG_COUNT=4, KEY_3=core.sshCommand | ask | ask |
| 2 | `git push origin <B>` | root | GIT_CONFIG_COUNT=4, KEY_3=credential.helper | ask | ask |
| 2 | `git push origin <B>` | root | GIT_DIR=plans/evil | ask | ask |
| 2 | `git push origin <B>` | root | GIT_TRACE=<scratch>/trace.out | allow | allow |
| 2 | `git push origin <B>` | root | GIT_TRACE_PACKET=<scratch>/trace.out | allow | allow |
| 2 | `git push origin <B>` | root | GIT_TRACE2_EVENT=<scratch>/trace2.out | allow | allow |
| 2 | `git push origin <B>` | root | GIT_EXTERNAL_DIFF=/tmp/x | allow | allow |
| 2 | `git push origin <B>` | root | GIT_PAGER=touch /tmp/x | allow | allow |
| 2 | `git push origin <B>` | root | GIT_SSL_NO_VERIFY=1 | allow | allow |
| 2 | `git push origin <B>` | root | HTTPS_PROXY=http://evil.invalid:1 | allow | allow |
| 2 | `git push origin <B>` | root | GIT_TEMPLATE_DIR / GIT_CURL_VERBOSE / GIT_TERMINAL_PROMPT=1 / GIT_HTTP_PROXY_AUTHMETHOD / GIT_CONFIG_NOSYSTEM=1 (one each) | allow | allow |
| 2 | `GIT_EXEC_PATH=/tmp/x git push origin <B>` | root | - | ask | ask |
| 2 | `GIT_CONFIG=/dev/null git push origin <B>` | root | - | ask | ask |
| 2 | `env GIT_SSH_COMMAND=x git push origin <B>` | root | - | ask | ask |
| 2 | `env -i git push origin <B>` | root | - | ask | ask |
| 2 | `git -c core.sshCommand=x push origin <B>` | root | - | ask | ask |
| 2 | `git push origin HEAD` | root | - | ask | ask |
| 2 | `git push origin main` | root | - | deny | deny |
| 2 | `git push --force origin <B>` | root | - | deny | deny |
| 3 | `git push origin <B>`, repo `credential.helper` set, no GIT_CONFIG | root | - | ask | ask |
| 3 | same | root | GIT_CONFIG=url-only file | ask | allow |
| 3 | same | root | GIT_CONFIG=url-only, GIT_CONFIG_NOSYSTEM=1 | ask | allow |
| 3 | same | root | GIT_CONFIG=url-only, GIT_CONFIG_GLOBAL=/dev/null | ask | allow |
| 3 | same | root | GIT_CONFIG=/dev/null | ask | ask |
| 3 | same | root | GIT_CONFIG_GLOBAL=/dev/null | ask | ask |
| 3 | `git push origin <B>`, clean repo config | root | GIT_CONFIG=url-only file | allow | allow |
| 4 | `git push origin <B> && ls` | root | - | deny | allow |
| 4 | `ls && git push origin <B>` | root | - | deny | allow |
| 4 | `ls; git push origin <B>` | root | - | deny | allow |
| 4 | `git push origin <B>; ls` | root | - | deny | allow |
| 4 | `git push origin <B> \|\| ls` | root | - | deny | allow |
| 4 | `git push origin <B> ; ls ;` | root | - | deny | allow |
| 4 | `git status && git push origin <B>` | root | - | deny | allow |
| 4 | `git push origin <B> && git push origin <B>` | root | - | deny | allow |
| 4 | `git push origin <B> && touch x` | root | - | deny | deny |
| 4 | `git push origin <B> \| tail` | root | - | ask | allow |
| 4 | `git push origin <B> 2>&1 \| tail -5` | root | - | ask | allow |
| 4 | `ls \| git push origin <B>` | root | - | ask | allow |
| 4 | `git push origin <B> & ls` | root | - | ask | allow |
| 4 | `git push origin <B> &` | root | - | allow | allow |
| 4 | `git push origin <B> > <scratch>/out.log` | root | - | ask | ask |
| 4 | `(git push origin <B>)` | root | - | ask | ask |
| 4 | `{ git push origin <B>; }` | root | - | ask | ask |
| 4 | `{ git push origin <B>; } && ls` | root | - | deny | deny |
| 4 | `git push origin <B> && cd /tmp` | root | - | deny | deny |
| 4 | `/usr/bin/git push origin <B> && ls` | root | - | deny | deny |
| 4 | `env git push origin <B> && ls` | root | - | deny | deny |
| 4 | `command git push origin <B> && ls` | root | - | deny | deny |
| 4 | `git push origin {<B>,<B>} && ls` | root | - | deny | deny |
| 4 | `g{i,}t push origin <B> && ls` | root | - | deny | deny |
| 4 | `gi{t,} push origin <B> && ls` | root | - | deny | deny |
| 4 | `git pu{sh,} origin <B> && ls` | root | - | deny | deny |
| 4 | `'git' push origin <B> && ls` | root | - | ask | allow |
| 4 | `"git" push origin <B> && ls` | root | - | ask | allow |
| 4 | `g\it push origin <B> && ls` | root | - | ask | allow |
| 4 | `git 'push' origin <B> && ls` | root | - | ask | allow |
| 4 | `true && git push origin <B>` | root | - | deny | deny |
| 4 | `git push origin <B> && true` | root | - | deny | deny |
| 4 | `git push origin <B> \| sh` | root | - | deny | deny |
| 4 | `! git push origin <B>` | root | - | ask | ask |
| 4 | `nohup git push origin <B>` | root | - | ask | ask |
| 4 | `nohup git push origin <B> && ls` | root | - | deny | deny |
| 4 | `time git push origin <B> && ls` | root | - | deny | deny |
| 4 | `exec git push origin <B>` | root | - | ask | ask |
| 4 | `xargs git push origin <B> < /dev/null` | root | - | ask | ask |
| 4 | `git push origin <B> && git push origin main` | root | - | deny | deny |
| 5 | `ruff check .` | root | - | allow | allow |
| 5 | `ruff check --config fix.toml .` | root | - | ask | allow |
| 5 | `ruff check --config=fix.toml .` | root | - | ask | allow |
| 5 | `ruff check --config ruff.toml .` (symlink → fix.toml) | root | - | ask | allow |
| 5 | `ruff check --config lnk/ruff.toml .` (symlink → ../fix.toml) | root | - | ask | allow |
| 5 | `ruff check --config sub/ruff.toml .` (planted, `fix = true`) | root | - | allow | allow |
| 5 | `ruff check --config ./sub/ruff.toml .` | root | - | allow | allow |
| 5 | `ruff check --config 'fix = true' .` | root | - | ask | ask |
| 5 | `ruff check --config pyproject.toml .` (absent at root) | root | - | ask | ask |
| 5 | `ruff check --config sub/ruff.toml/ .` | root | - | ask | allow |
| 5 | `ruff check --config sub/Ruff.toml .` | root | - | ask | ask |
| 5 | `ruff check --config sub/r?ff.toml .` | root | - | ask | ask |
| 5 | `ruff check --config sub/ruff.to{ml,ml} .` | root | - | ask | ask |
| 5 | `ruff check --config sub/ruff.toml --config fix.toml .` | root | - | ask | allow |
| 5 | `ruff --config fix.toml check .` | root | - | ask | allow |
| 5 | `ruff check --fix .` | root | - | ask | ask |
| 5 | `ruff check --config <abs head>/fix.toml .` | root | - | ask | ask |
| 5 | `mypy --config-file cfg.ini .` | root | - | ask | allow |
| 5 | `mypy --config-file=cfg.ini .` | root | - | ask | allow |
| 5 | `mypy --config-file sub/mypy.ini .` (planted, `junit_xml`) | root | - | allow | allow |
| 5 | `mypy --config-file setup.cfg .` (absent) | root | - | ask | ask |
| 5 | `python3 -m mypy --config-file cfg.ini .` | root | - | ask | allow |
| 5 | `python3 -m ruff check --config fix.toml .` | root | - | ask | allow |
| 5 | `pytest -c cfg.ini` | root | - | ask | ask |
| 5 | `pytest --config-file cfg.ini` | root | - | ask | ask |
| 5 | `pytest -p evil` | root | - | ask | ask |
| 5 | `env ruff check --config fix.toml .` | root | - | ask | ask |
| 6 | `./self/gate.sh` | root | - | allow | allow |
| 6 | `self/gate.sh` | root | - | allow | allow |
| 6 | `./self//gate.sh` | root | - | allow | allow |
| 6 | `./self/./gate.sh` | root | - | allow | allow |
| 6 | `<abs copy>/self/gate.sh` | root | - | allow | allow |
| 6 | `./x/gate.sh` (planted) | root | - | ask | allow |
| 6 | `x/gate.sh` | root | - | ask | allow |
| 6 | `./plans/gate.sh` (planted in agentTooling's own checkout) | root | - | allow | allow |
| 6 | `./gate.sh` | self | - | allow | allow |
| 6 | `./gate.sh` | x | - | ask | allow |
| 6 | `bash x/gate.sh` | root | - | ask | ask |
| 6 | `bash self/gate.sh` | root | - | ask | ask |
| 6 | `./check-plans.sh` | root | - | allow | allow |
| 6 | `./x/check-plans.sh` (planted) | root | - | ask | allow |
| 6 | `./agentTooling/check-plans.sh` (planted in own checkout) | root | - | allow | allow |
| 6 | `./check-plans.sh` | x | - | ask | allow |
| 6 | `x/../self/gate.sh` | root | - | deny | deny |
| 6 | `./sel?/gate.sh` | root | - | ask | ask |
| 6 | `./s*/gate.sh` | root | - | ask | ask |
| 6 | `./x/g?te.sh` | root | - | ask | ask |
| 6 | `./{x,self}/gate.sh` | root | - | ask | ask |
| 6 | `python3 analysis/report.py --self x` | root | - | allow | allow |
| 6 | `python3 agentTooling/analysis/report.py --self x` (planted) | root | - | ask | allow |
| 6 | `python3 agentTooling/analysis/report.py x` (planted) | root | - | ask | allow |
| 6 | `python3 ./agentTooling/analysis/report.py --self x` | root | - | ask | allow |
| 6 | `python3 -B agentTooling/analysis/report.py --self x` | root | - | ask | allow |
| 6 | `python3 analysis/manifest.py get x y` | root | - | ask | ask |
| 6 | `python3 agentTooling/analysis/manifest.py get x y` (planted) | root | - | ask | ask |
| 6 consumer | `python3 analysis/report.py x` (planted at consumer root) | root | - | ask | ask |
| 6 consumer | `python3 agentTooling/analysis/report.py x` | root | - | allow | allow |
| 6 consumer | `python3 analysis/manifest.py get x y` (planted) | root | - | ask | ask |
| 6 consumer | `python3 agentTooling/analysis/manifest.py get x y` | root | - | ask | ask |
| 6 consumer | `./plans/gate.sh` | root | - | allow | allow |
| 6 consumer | `./gate.sh` | plans | - | allow | allow |
| 6 consumer | `./x/gate.sh` (planted) | root | - | ask | allow |
| 6 consumer | `./agentTooling/check-plans.sh` | root | - | allow | allow |
| 6 consumer | `./agentTooling/self/gate.sh` | root | - | ask | allow |
| 6 consumer | `python3 report.py x` | analysis | - | ask | ask |
| 6 consumer | `python3 ./report.py x` | analysis | - | ask | ask |

`<B>` = `claude/hook-silent-allow-sweep`, the copy's current branch and its manifest's `branches[0]`.

**Rule 1, deny side** (`git -C <L> <sub>`). Head and base gave the same result in every one of the 102 cells:

| sub \ L | `self` | `.` | `se?f` | `s*f` | `se[l]f` | `@(self)` |
|---|---|---|---|---|---|---|
| `reset --hard` | deny | deny | deny | deny | deny | ask |
| `push --force origin <B>` | deny | deny | deny | deny | deny | ask |
| `push origin main` | deny | deny | deny | deny | deny | ask |
| `push origin other` | deny | deny | ask | ask | ask | ask |
| `checkout main` | ask | ask | ask | ask | ask | ask |
| `switch main` | deny | deny | ask | ask | ask | ask |
| `branch -D x` | deny | deny | deny | deny | deny | ask |
| `rebase main` | deny | deny | deny | deny | deny | ask |
| `clean -fd` | deny | deny | deny | deny | deny | ask |
| `stash drop` | deny | deny | deny | deny | deny | ask |
| `worktree remove x` | deny | deny | deny | deny | deny | ask |
| `commit --amend -m x` / `update-ref -d refs/heads/x` / `filter-branch` / `restore .` / `checkout -- .` / `push origin <B>` | ask | ask | ask | ask | ask | ask |

**Rule 7** (`refuse_orchestrator_session <id>` after sourcing `plan-runner-roots.sh`). "refused" means it exited 1 with the `  refused  ` line; "goes on" means it returned 0.

| scenario | id `audit-orch-session` | id `''` | id `--reason` | id `other-session` |
|---|---|---|---|---|
| intact, no record | goes on / goes on | goes on / goes on | goes on / goes on | goes on / goes on |
| record naming `audit-orch-session` (working tree) | refused / refused | goes on / goes on | goes on / goes on | goes on / goes on |
| record + `hooks/shared_rules.py` removed | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| record + `hooks/orchestrator_role.py` removed | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| record + module replaced by `raise SystemExit(5)` | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| record + `shared_rules.py` a symlink to the real file | refused / refused | goes on / goes on | goes on / goes on | goes on / goes on |
| no record + `shared_rules.py` removed | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| no record + `orchestrator_role.py` removed | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| no record + module crashes | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| no record + `shared_rules.py` is a directory | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |
| no record + module prints `x` then exits 4 | refused / goes on | goes on / goes on | refused / goes on | refused / goes on |

(Each cell is head / base. The committed-record variant could not be built because the planted nested checkout `plans/wt` blocked `git add -A`. The record was therefore read from the working tree, which the rule honours per `orchestrator-role.sh` G11.)

No input anywhere is more permissive on the head than on the base. Every head/base difference is the head asking or denying where the base allowed, or refusing where the base went on.

## Findings

| class | input | head | base | evidence |
|---|---|---|---|---|
| non-blocking | `ruff check --config sub/ruff.toml .` with a planted `sub/ruff.toml` holding `fix = true` (pre-existing silent allow) | allow | allow | `scratch/drive.py`: payload to `head/hooks/allow-repo-commands.sh` and `base/hooks/allow-repo-commands.sh`, `CLAUDE_PROJECT_DIR=<copy>` |
| non-blocking | `mypy --config-file sub/mypy.ini .` with a planted `sub/mypy.ini` holding `junit_xml` (pre-existing silent allow) | allow | allow | `scratch/drive.py`, same as above |
| non-blocking | `./plans/gate.sh`, planted in agentTooling's own checkout (pre-existing silent allow) | allow | allow | `scratch/drive.py`, same as above |
| non-blocking | `./agentTooling/check-plans.sh`, planted in agentTooling's own checkout (pre-existing silent allow) | allow | allow | `scratch/drive.py`, same as above |
| non-blocking | `git push origin <B>` with `GIT_TRACE`/`GIT_TRACE_PACKET`/`GIT_TRACE2_EVENT=<path>` in the session environment (pre-existing silent allow) | allow | allow | `scratch/drive.py`, env set on the hook process |
| non-blocking | `git -C se?f switch main` (literal `git -C self switch main` denies; prompt-only) | ask | ask | `scratch/drive2.py deny` on both copies |
| non-blocking | `git -C se?f push origin other` (literal `-C self` denies; prompt-only) | ask | ask | `scratch/drive2.py deny` on both copies |
| non-blocking | `git -C @(self) reset --hard`, and every destructive subcommand behind an extglob `-C` (literal denies; prompt-only) | ask | ask | `scratch/drive2.py deny` on both copies |

## Non-blocking findings

1. **Pre-existing silent allow — runner config in a subdirectory.** `ruff check --config sub/ruff.toml .` (a planted `fix = true`) and `mypy --config-file sub/mypy.ini .` (a planted `junit_xml`) are allowed on both head and base.
   - Item 5 checks only the basename, so a planted file with a discovered name anywhere in the tree still rewrites files or writes output.
   - What the rule should do instead: approve only the config file the runner would itself discover for the target. At a minimum, that is a root-level `ruff.toml`/`.ruff.toml`/`pyproject.toml`, or `mypy.ini`/`.mypy.ini`/`setup.cfg`/`pyproject.toml`, and anything else should ask.
2. **Pre-existing silent allow — entry spellings not tied to the layout.** In agentTooling's own checkout, a planted `plans/gate.sh` or `agentTooling/check-plans.sh` is approved, on both head and base.
   - `ENTRY_GATE_SPELLINGS` and `ENTRY_CHECK_PLANS_SPELLINGS` hold the spellings for both layouts, whatever layout the hook runs in.
   - What the rule should do instead: pin these spellings beside the running hook, as `hook_analysis_pins` now does for `analysis/`. That means `self/gate.sh` + `check-plans.sh` for `<root>/hooks/`, and `plans/gate.sh` + `agentTooling/check-plans.sh` for `<root>/agentTooling/hooks/`.
3. **Pre-existing silent allow — trace variables on the own-branch push.** With `GIT_TRACE`, `GIT_TRACE_PACKET` or `GIT_TRACE2_EVENT` naming a path in the hook's environment, the own-branch push is still approved on both head and base, and git writes to that path.
   - This is environment-only: a per-call `VAR=… git push` prefix asks on both.
   - What the rule should do instead: add the `GIT_TRACE*` names to `OWN_PUSH_HELPER_ENVS`, or a sibling list, so that any of them being set refuses the approval.
4. **Prompt-only — git denies behind a pattern location.** These ask on both head and base where the literal spelling denies:
   - `git -C se?f switch main`
   - `git -C se?f push origin other`
   - every destructive subcommand behind an extglob `-C` (`git -C @(self) reset --hard`)

   What the rule should do instead: the deny side should not need the location. A `switch`/`push` to another branch, and the destructive set, should deny whatever `-C` value precedes them, or deny any pattern-valued location outright with a rewrite to the literal path.

## Blocking findings

None.

## Notes (head stricter than base; not findings)

- `git -C 'plans/e?il' status` and `git -C "plans/e?il" status` now ask, although bash does not glob a quoted word. This is harmless over-refusal.
- In a vendored consumer, `./agentTooling/self/gate.sh` (agentTooling's own gate) now asks where the base approved it. This narrows usability, not security.
