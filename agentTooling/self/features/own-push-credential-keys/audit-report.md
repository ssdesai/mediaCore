Verdict: clean

# Security audit — own-push-credential-keys

Hook files the diff changes against `origin/main`: `hooks/allow-repo-commands.sh` and
`hooks/README.md` (documentation of the same rule).

## Rules the diff adds or changes

1. **Credential keys in the effective config** — the cloud own-branch push
   (`git push [-u] origin <B>`) is no longer silently approved, but handed to the human, when the
   effective config (`git config --list -z`, every scope) holds `credential.helper` or
   `core.askpass` (added to `OWN_PUSH_PRESENT_KEYS`) or any `credential.<sub>.helper` (new regex
   `^credential\..*\.helper$`).
2. **Empty subsections** — `OWN_PUSH_PRESENT_KEY_RES` widened from `.+` to `.*`, so
   `branch..pushremote`, `includeif..path`, `hook..event|command` and `credential..helper`
   (a `[section ""]` block) also take the push to the human.
3. **Askpass in the hook's environment** — a non-empty `GIT_ASKPASS` or `SSH_ASKPASS` in the hook's
   own environment takes the push to the human; an empty one still approves.

Every change only adds a `return False` path to `own_push_config_allows` or widens a regex
that already returns False, so by construction the head can only be stricter than the base.
The table below confirms that empirically.

## Method

`git archive HEAD` and `git archive origin/main` were unpacked under the scratch directory
(`/tmp/plan-capture.ZgHfpD/scratch/{head,base}.tar`). For each copy, a fresh repository was
built with that copy's `hooks/` vendored at `agentTooling/hooks/`, a started feature
`feat-x` (manifest `branches: ["claude/feat-x"]` committed at `HEAD`), the current branch
`claude/feat-x`, and `origin` = `https://example.invalid/consumer.git`. Each payload went
to the hook on stdin (`tool_name: Bash`, `session_id`, `agent_id`, `cwd` = the root,
`tool_input.command`) with `CLAUDE_PROJECT_DIR` = that root, `AGENTTOOLING_PROFILE=cloud`,
`GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, and inherited askpass variables
removed unless the row sets them. Every config mutation was applied to both copies, run, then
undone. Driver: `/tmp/plan-capture.ZgHfpD/scratch/audit.py`, run as
`python3 /tmp/plan-capture.ZgHfpD/scratch/audit.py`. Results: `allow` = the hook's
allow decision, `ask` = no output (handed to the human), `deny` = denied with a rewrite.
The helper and askpass rows point at a script that touches a marker file. The marker was never
created, because the hook only probes the config and never runs the push.

## Inputs tried

`<B>` = `claude/feat-x`; `PUSH` = `git push origin <B>`.

| # | Input (mutation / env / command) | head | base |
|---|---|---|---|
| 1 | baseline `PUSH` | allow | allow |
| 2 | baseline `git push -u origin <B>` | allow | allow |
| 3 | repo `credential.helper = !f() { touch …; }; f` | ask | allow |
| 4 | repo `credential.helper =` (empty value) | ask | allow |
| 5 | repo `credential.https://example.invalid.helper` | ask | allow |
| 6 | repo `credential.HTTPS://Example.Invalid.Helper` (mixed case) | ask | allow |
| 7 | repo `credential.https://example.invalid/consumer.git.helper` (dots in subsection) | ask | allow |
| 8 | repo raw `[credential ""] helper = …` (`credential..helper`) | ask | allow |
| 9 | repo `core.askPass = <script>` | ask | allow |
| 10 | repo `core.askpass =` (empty value) | ask | allow |
| 11 | global (`GIT_CONFIG_GLOBAL`) `[credential] helper` | ask | allow |
| 12 | global `[credential ""] helper` | ask | allow |
| 13 | global `[core] askpass` | ask | allow |
| 14 | system (`GIT_CONFIG_SYSTEM`, NOSYSTEM unset) `[credential] helper` | ask | allow |
| 15 | hook env `GIT_CONFIG_PARAMETERS='credential.helper'=…` | ask | allow |
| 16 | hook env `GIT_CONFIG_COUNT/KEY_0/VALUE_0` credential.helper | ask | allow |
| 17 | hook env `GIT_CONFIG_COUNT/KEY_0/VALUE_0` core.askPass | ask | allow |
| 18 | repo `include.path` → file holding a helper | ask | ask |
| 19 | repo raw `[includeIf ""] path` (`includeif..path`) | ask | allow |
| 20 | repo raw `[hook ""] command` (`hook..command`) | ask | allow |
| 21 | repo raw `[branch ""] pushremote` (`branch..pushremote`) | ask | ask |
| 22 | `config.worktree` (`extensions.worktreeConfig`) `credential.helper` | ask | allow |
| 23 | hook env `GIT_ASKPASS=<script>` | ask | allow |
| 24 | hook env `SSH_ASKPASS=<script>` | ask | allow |
| 25 | hook env `GIT_ASKPASS=' '` (a space) | ask | allow |
| 26 | hook env `GIT_ASKPASS=` (empty) | allow | allow |
| 27 | hook env `SSH_ASKPASS=` (empty) | allow | allow |
| 28 | repo `credential.interactive=false` | allow | allow |
| 29 | repo `credential.<url>.username=x` | allow | allow |
| 30 | repo `credential.helperx` (near-miss key) | allow | allow |
| 31 | repo `credential.a.helperx` (near-miss key) | allow | allow |
| 32 | repo `credentialx.helper` (near-miss section) | allow | allow |
| 33 | `GIT_ASKPASS=<script> git push origin <B>` | ask | ask |
| 34 | `SSH_ASKPASS=<script> git push origin <B>` | ask | ask |
| 35 | `env GIT_ASKPASS=<script> git push origin <B>` | ask | ask |
| 36 | `env env GIT_ASKPASS=<script> git push origin <B>` | ask | ask |
| 37 | `/usr/bin/env GIT_ASKPASS=<script> git push origin <B>` | ask | ask |
| 38 | `GIT_CONFIG_PARAMETERS="'credential.helper'='!touch x'" git push origin <B>` | ask | ask |
| 39 | `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=x git push origin <B>` | ask | ask |
| 40 | `git -c credential.helper=x push origin <B>` | ask | ask |
| 41 | `git -c core.askPass=x push origin <B>` | ask | ask |
| 42 | `git --config-env=credential.helper=HOME push origin <B>` | ask | ask |
| 43 | `command git push origin <B>` | ask | ask |
| 44 | `exec -a git git push origin <B>` | ask | ask |
| 45 | `nohup git push origin <B>` | ask | ask |
| 46 | `sudo git push origin <B>` | ask | ask |
| 47 | `echo origin <B> \| xargs git push` | ask | ask |
| 48 | `bash -c 'git push origin <B>'` | deny | deny |
| 49 | `echo git push origin <B> \| sh` | deny | deny |
| 50 | `find . -maxdepth 0 -exec git push origin <B> ;` | ask | ask |
| 51 | `"git" "push" "origin" "<B>"` (same words after unquoting) | allow | allow |
| 52 | `g""it pu""sh origin <B>` (same words after unquoting) | allow | allow |
| 53 | `\git push origin <B>` (same words after unquoting) | allow | allow |
| 54 | `git push origin {<B>,}` | ask | ask |
| 55 | `git push origin $BR` | deny | deny |
| 56 | `git config credential.helper x && git push origin <B>` | deny | deny |
| 57 | `export GIT_ASKPASS=<script>; git push origin <B>` | deny | deny |
| 58 | malformed payload: `cwd` missing | ask | ask |
| 59 | malformed payload: `tool_input` a string | ask | ask |
| 60 | malformed payload: not JSON | ask | ask |
| 61 | hook env `GIT_EXEC_PATH=<scratch dir>` | allow | allow |

Rows 3–17, 19, 20 and 22–25 are the intended tightening: an allow on the base becomes an ask on
the head. Rows 26–32 are the approvals the feature means to keep. Rows 51–53 allow the same
command after shell unquoting, so they are not bypasses. No input is more permissive on the
head than on the base.

## Findings

| class | input | head | base | evidence |
|---|---|---|---|---|
| non-blocking | hook env `GIT_EXEC_PATH=<dir>` with `git push origin claude/feat-x` (row 61) | allow | allow | `python3 /tmp/plan-capture.ZgHfpD/scratch/audit.py` row "hook env GIT_EXEC_PATH planted", the same payload and env run against the head copy (`scratch/head/repo`) and the base copy (`scratch/base/repo`) |

## Non-blocking findings

- **Pre-existing silent allow — `GIT_EXEC_PATH` in the hook's environment.** Input: the own-branch
  push `git push origin claude/feat-x` when the hook runs with `GIT_EXEC_PATH` set to a
  directory the tree controls. Head: allow. Base: allow. For an `https://` origin, git runs
  `git-remote-https` from `GIT_EXEC_PATH`. A planted directory therefore names a program the
  push runs, the same class as the `GIT_ASKPASS` and `SSH_ASKPASS` this feature now refuses
  to approve silently. The rule should treat a `GIT_EXEC_PATH` that differs from git's
  built-in exec path as no approval and hand the push to the human, as it does a non-empty
  askpass. The same applies to a `PATH` entry ahead of the system git, which the hook cannot
  tell apart from an ordinary setup. A command cannot plant this variable itself: rows 33–39
  show that a prefix assignment or an `env` wrapper already goes to the human. Only the
  session's own environment can set it, so the finding is low severity. To file in
  `self/BACKLOG.md` before the feature closes.

## Blocking findings

None.
