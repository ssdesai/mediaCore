Verdict: escalated

# Security audit — own-push-credential-keys (round 01)

Hook files the diff changes (`git diff origin/main...HEAD`): `hooks/allow-repo-commands.sh`,
`hooks/README.md`.

## Rules the diff adds or changes

All three sit in `own_push_config_allows`, which gates the cloud-only silent approval of
`git push [-u] origin <own branch>`. Each turns that approval into a prompt (no output), never a deny.

1. **R1 — `credential.helper` and `core.askpass` present.** These are added to
   `OWN_PUSH_PRESENT_KEYS`. If either key appears anywhere in `git config --list -z`, the push
   prompts.
2. **R2 — `^credential\..+\.helper$` present.** A URL-scoped helper in any scope makes the push
   prompt.
3. **R3 — `GIT_ASKPASS` or `SSH_ASKPASS` non-empty in the hook's environment.** The push prompts.
   An empty value still approves.

## Method

- **HEAD copy:** `git archive HEAD` into `/tmp/plan-capture.SdyQqi/scratch/head`.
- **Base copy:** `git archive origin/main` into `/tmp/plan-capture.SdyQqi/scratch/base`.
- **Fixture:** for each copy, `attack.py` builds a fixture consumer repo with the same shape as
  `self/tests/hook-cloud-profile.sh`'s `C`:
  - the copy's four hook files vendored under `agentTooling/hooks/`;
  - a started feature `feat-x` on `claude/feat-x`, with the manifest committed;
  - origin set to `https://example.invalid/consumer.git`.
- **Each input:**
  1. The config edit is applied to the fixture's `.git/config`, either with `git config` or by
     appending raw text.
  2. The hook runs with a Bash PreToolUse payload (`tool_name`, `session_id`, `agent_id`, `cwd` =
     root, `tool_input.command`) on stdin.
  3. The hook's environment is `AGENTTOOLING_PROFILE=cloud` and
     `CLAUDE_PROJECT_DIR=<fixture>`, with inherited `GIT_ASKPASS`/`SSH_ASKPASS` removed, plus the
     row's extra environment.
  4. The fixture's config is restored afterwards.
- **Commands:**
  - `python3 /tmp/plan-capture.SdyQqi/scratch/attack.py` (main table)
  - `python3 /tmp/plan-capture.SdyQqi/scratch/attack.py extra` (empty-subsection variants)
- **Git behaviour check:** `bash /tmp/plan-capture.SdyQqi/scratch/emptysub.sh` (git 2.43.0).
- **Push command:** unless the row says otherwise, the command is `git push origin claude/feat-x`.

Results: `allow` = `permissionDecision: allow`; `ask` = no output (prompt); `deny` = deny.

## Inputs tried

| # | input | head | base |
|---|---|---|---|
| 1 | baseline plain push | allow | allow |
| 2 | baseline `git push -u origin claude/feat-x` | allow | allow |
| 3 | `credential.helper` = `!f() { touch …; }; f` | ask | allow |
| 4 | `credential.helper` = empty | ask | allow |
| 5 | `credential.https://example.invalid.helper` | ask | allow |
| 6 | `credential.https://Example.INVALID/X.Helper` (mixed case) | ask | allow |
| 7 | `Credential.HELPER` (section/key case) | ask | allow |
| 8 | raw `[credential ""]` `helper = !…` (**empty subsection**) | **allow** | allow |
| 9 | raw `[credential "*"]` helper | ask | allow |
| 10 | raw `[credential "https://*.invalid"]` helper | ask | allow |
| 11 | raw `[credential "a.b.c"]` helper (dots in subsection) | ask | allow |
| 12 | raw `[credential]` `helper   =…` (spacing) | ask | allow |
| 13 | `core.askPass` = script path | ask | allow |
| 14 | `core.askpass` = empty | ask | allow |
| 15 | raw `[core]` `AskPass = …` | ask | allow |
| 16 | raw `[CORE]` `askpass = …` | ask | allow |
| 17 | `credential.helper` in `GIT_CONFIG_GLOBAL` file (hook env) | ask | allow |
| 18 | `core.askpass` in `$XDG_CONFIG_HOME/git/config` (hook env) | ask | allow |
| 19 | `GIT_CONFIG_COUNT/KEY_0/VALUE_0` = `credential.helper` (hook env) | ask | allow |
| 20 | `GIT_CONFIG_PARAMETERS='credential.helper'=…` (hook env) | ask | allow |
| 21 | `GIT_CONFIG_KEY_0` = `credential.a<newline>b.helper` (hook env) | ask | ask |
| 22 | `GIT_ASKPASS=/path` (hook env) | ask | allow |
| 23 | `GIT_ASKPASS=" "` (hook env) | ask | allow |
| 24 | `SSH_ASKPASS=/path` (hook env) | ask | allow |
| 25 | `GIT_ASKPASS=` empty (hook env) | allow | allow |
| 26 | `SSH_ASKPASS=` empty (hook env) | allow | allow |
| 27 | `git_askpass=/path` lowercase (hook env; git ignores it) | allow | allow |
| 28 | `credential.interactive=false` | allow | allow |
| 29 | `credential.https://example.invalid.username=x` | allow | allow |
| 30 | `credential.helperx` (near-miss) | allow | allow |
| 31 | `credential.x.helpers` (near-miss) | allow | allow |
| 32 | `core.askpassx` (near-miss) | allow | allow |
| 33 | cmd `GIT_ASKPASS=/path git push origin claude/feat-x` | ask | ask |
| 34 | cmd `SSH_ASKPASS=/path git push …` | ask | ask |
| 35 | cmd `GIT_CONFIG_PARAMETERS="'credential.helper'='!touch …'" git push …` | ask | ask |
| 36 | cmd `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.askpass GIT_CONFIG_VALUE_0=… git push …` | ask | ask |
| 37 | cmd `env GIT_ASKPASS=… git push …` | ask | ask |
| 38 | cmd `env env GIT_ASKPASS=… git push …` | ask | ask |
| 39 | cmd `/usr/bin/env GIT_ASKPASS=… git push …` | ask | ask |
| 40 | cmd `export GIT_ASKPASS=…; git push …` | deny | deny |
| 41 | cmd `export GIT_ASKPASS=… && git push …` | deny | deny |
| 42 | cmd `git -c credential.helper='!touch …' push origin claude/feat-x` | ask | ask |
| 43 | cmd `git -c core.askpass=… push origin claude/feat-x` | ask | ask |
| 44 | cmd `git --config-env=core.askpass=HOME push origin claude/feat-x` | ask | ask |
| 45 | cmd `command git push …` | ask | ask |
| 46 | cmd `exec -a x git push …` | ask | ask |
| 47 | cmd `nohup git push …` | ask | ask |
| 48 | cmd `sudo git push …` | ask | ask |
| 49 | cmd `echo claude/feat-x \| xargs git push origin` | ask | ask |
| 50 | cmd `bash -c 'git push …'` | deny | deny |
| 51 | cmd `echo 'git push …' \| sh` | deny | deny |
| 52 | cmd `"git" push origin claude/feat-x` (the same argv as #1) | allow | allow |
| 53 | cmd `g""it push origin claude/feat-x` (the same argv as #1) | allow | allow |
| 54 | cmd `\git push origin claude/feat-x` (the same argv as #1) | allow | allow |
| 55 | cmd `git push origin {claude/feat-x,main}` | deny | deny |
| 56 | cmd `git push origin $B` | deny | deny |
| 57 | cmd `git push origin $(echo claude/feat-x)` | deny | deny |
| 58 | cmd `git push …; cat <<EOF …` | ask | ask |
| 59 | `[credential ""]` helper in a `GIT_CONFIG_GLOBAL` file (hook env) | **allow** | allow |
| 60 | `GIT_CONFIG_KEY_0=credential..helper` via `GIT_CONFIG_COUNT` (hook env) | **allow** | allow |
| 61 | `git config credential..helper '!…'` (set via CLI) | **allow** | allow |
| 62 | restored fixture, plain push | allow | allow |

How to read the table:

- **Rows 52–54** are the same argv as row 1 once the shell has parsed the line, so they are not
  bypasses.
- **Rows 33–39 and 42–49** carry the push's own environment or global options on the command line.
  They prompt on both copies, as the rule intends ("a prompt, never a deny").
- **No regression:** no input is more permissive on head than on base. The diff only adds early
  `return False` paths.

Git behaviour check (`emptysub.sh`, git 2.43.0):

- A repo with only `[credential ""] helper = "!f() { touch …/PWN_EMPTY; …}; f"` was given
  `printf 'protocol=https\nhost=example.invalid\n\n' | git credential fill`.
- The helper **ran**: `PWN_EMPTY` was created, and `username=x`/`password=y` came back.
- `git config --list -z` prints that key as `credential..helper`. An empty subsection matches every
  URL, so git runs this helper on any credential request for the https origin, the same as a plain
  `credential.helper`.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | `credential..helper` (`[credential ""]` `helper = !…`) in the repo config, global config or `GIT_CONFIG_COUNT`, then `git push origin claude/feat-x` | allow (silent) | allow | `python3 /tmp/plan-capture.SdyQqi/scratch/attack.py` row 8 and `… attack.py extra` rows 59–61 on the `head` and `base` copies; `bash /tmp/plan-capture.SdyQqi/scratch/emptysub.sh` shows git 2.43.0 runs the helper |

## Non-blocking findings

None.

## Blocking finding: reproduction and fix

**Reproduce:**

1. In the fixture (or any cloud checkout on its started feature's branch with an https origin),
   append this to `.git/config`, or to the global config, or set it with
   `git config credential..helper '!f() { touch /tmp/pwned; echo username=x; echo password=y; }; f'`:

   ```
   [credential ""]
   	helper = !f() { touch /tmp/pwned; echo username=x; echo password=y; }; f
   ```

2. Send the hook `git push origin <own branch>` with `AGENTTOOLING_PROFILE=cloud`.
3. It returns `permissionDecision: allow`. When the server asks for credentials, git runs the
   shell helper with no human approval.

The silently approved push therefore runs an arbitrary shell command. That is the exact case R1/R2
exist to turn into a prompt. Under the owner's ruling it is blocking class (b), a silent allow of a
command that runs something, even though the base also allows it.

**Cause:** `OWN_PUSH_PRESENT_KEY_RES`'s new `^credential\..+\.helper$` requires at least one
character of subsection. Git lists an empty subsection as `credential..helper`, which matches
neither that regex nor the exact `credential.helper` key.

**What the rule should do instead:** prompt for every helper key git honours, whatever the
subsection. Either:

- change the regex to `^credential\..*\.helper$`, or
- match `key.startswith("credential.") and key.endswith(".helper")`.

Then add a Q8 row for `[credential ""]` / `credential..helper` to
`self/tests/hook-cloud-profile.sh`, and name the empty subsection in the `hooks/README.md`
sentence. The same `.+` shape is in `includeif\..+\.path` and `hook\..+\.(event|command)`. Whether
git honours an empty subsection for those was not tested in this round; checking them belongs to
the same fix.
