Verdict: escalated

# Security audit — own-push-credential-keys (02-audit-opus)

Diff audited: `git diff origin/main...HEAD -- hooks/allow-repo-commands.sh hooks/README.md`.

Rules the diff adds or changes (all in `own_push_config_allows`, the cloud-only silent approval
of `git push [-u] origin <own branch>`):

1. **R1** `credential.helper` present in the effective config → no approval (prompt).
2. **R2** `core.askpass` present → prompt.
3. **R3** `credential.<any>.helper`, empty subsection included (`^credential\..*\.helper$`) → prompt.
4. **R4** the existing `branch.<sub>.pushremote`, `includeif.<sub>.path`, `hook.<sub>.(event|command)`
   regexes widened from `.+` to `.*`, so an empty subsection prompts.
5. **R5** `GIT_ASKPASS` or `SSH_ASKPASS` non-empty in the hook's environment → prompt; empty → approve.

`hooks/README.md` only documents these rules; nothing in it is enforced.

## Method

Two throwaway copies under the scratch directory: `git archive HEAD` (head) and
`git archive origin/main` (base). For each, a consumer repo was built with the copy's `hooks/`
vendored at `agentTooling/hooks/`, a started feature `feat-x` (manifest committed at HEAD,
`branches: ["claude/feat-x"]`), checked out on `claude/feat-x`, `remote.origin.url =
https://example.invalid/consumer.git`. The hook ran with `AGENTTOOLING_PROFILE=cloud`,
`CLAUDE_PROJECT_DIR=<consumer>`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=<empty file>`, no
inherited askpass, and a PreToolUse payload `{tool_name: Bash, cwd: <consumer>, session_id,
agent_id, tool_input: {command}}`. Every row starts from a fresh consumer. Scripts:
`attack.py` (all rows below) and `attack2.py` (the `GIT_CONFIG` rows), run as
`python3 /tmp/plan-capture.pEmOGC/scratch/attack.py` / `attack2.py`. `prompt` = no hook output
(the human is asked); `allow` = silent approval.

## Inputs tried

Command is `git push -u origin claude/feat-x` unless the row says otherwise.

| # | input (config mutation / hook env / command) | head | base | correct? |
|---|---|---|---|---|
| 1 | baseline, no mutation | allow | allow | yes (intended) |
| 2 | local `credential.helper=!f() { touch pwned; }; f` | prompt | allow | yes (R1) |
| 3 | raw `[Credential]\n Helper = …` (mixed case) | prompt | allow | yes |
| 4 | `credential.https://example.invalid.helper` | prompt | allow | yes (R3) |
| 5 | raw `[credential "HTTPS://Example.Invalid"] Helper` | prompt | allow | yes |
| 6 | raw `[credential ""] helper` | prompt | allow | yes (R3 empty sub) |
| 7 | raw `[credential] helper` (no `=`) | prompt | allow | yes |
| 8 | raw `[credential] helper =` (empty, resets list) | prompt | allow | yes (conservative) |
| 9 | raw `[credential "a\"b"] helper` (escaped subsection) | prompt | allow | yes |
| 10 | raw `[credential.example] helper` (old dotted subsection) | prompt | allow | yes |
| 11 | local `core.askpass=<script>` | prompt | allow | yes (R2) |
| 12 | raw `[Core] askPass = …` | prompt | allow | yes |
| 13 | `credential.helper` in global config only (`GIT_CONFIG_GLOBAL`) | prompt | allow | yes |
| 14 | `credential.helper` in system config only (`GIT_CONFIG_SYSTEM`) | prompt | allow | yes |
| 15 | hook env `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=…` | prompt | allow | yes |
| 16 | hook env `GIT_CONFIG_PARAMETERS='core.askpass'='…'` | prompt | allow | yes |
| 17 | `credential.helper` inside an `include.path` file | prompt | prompt | yes |
| 18 | hook env `GIT_CONFIG=<empty file>` + local `credential.helper` | prompt | prompt | yes (no url seen) |
| 19 | hook env `GIT_CONFIG=<empty file>` + local `core.askpass` | prompt | prompt | yes |
| 20 | hook env `GIT_CONFIG=<empty file>`, no mutation | prompt | prompt | yes |
| 21 | **hook env `GIT_CONFIG=<file holding only remote.origin.url>` + local `credential.helper=!…`** | **allow** | **allow** | **NO — bypass** |
| 22 | **hook env `GIT_CONFIG=<url-only file>` + local `core.askpass`** | **allow** | **allow** | **NO — bypass** |
| 23 | hook env `GIT_CONFIG=<url-only file>` + local `remote.origin.pushurl` | prompt | prompt | yes (get-url check) |
| 24 | `credential.x.helperx` (just outside regex) | allow | allow | yes (git ignores it) |
| 25 | `credential.helper.x` (subsection `helper`) | allow | allow | yes (git ignores it) |
| 26 | `credential.username`, `credential.interactive=false` | allow | allow | yes (intended) |
| 27 | `credential.useHttpPath=true` | allow | allow | yes (runs nothing) |
| 28 | raw `[core "x"] askpass` (git ignores subsectioned core) | allow | allow | yes |
| 29 | raw `[branch ""] pushremote = evil` | prompt | prompt | yes (base prompts via other check) |
| 30 | raw `[includeIf ""] path = …` | prompt | allow | yes (R4) |
| 31 | raw `[hook ""] command = touch …` | prompt | allow | yes (R4) |
| 32 | raw `[hook ""] event = pre-push` | prompt | allow | yes (R4) |
| 33 | hook env `GIT_ASKPASS=<script>` | prompt | allow | yes (R5) |
| 34 | hook env `SSH_ASKPASS=<script>` | prompt | allow | yes (R5) |
| 35 | hook env `GIT_ASKPASS=` (empty) | allow | allow | yes (intended; cloud default) |
| 36 | hook env `SSH_ASKPASS=` (empty) | allow | allow | yes |
| 37 | hook env `GIT_ASKPASS=" "` | prompt | allow | yes (conservative) |
| 38 | hook env `git_askpass=<script>` (lowercase; git ignores) | allow | allow | yes |
| 39 | hook env `GIT_TERMINAL_PROMPT=1` | allow | allow | yes (runs nothing) |
| 40 | cmd `GIT_ASKPASS=<script> git push -u origin B` | prompt | prompt | yes |
| 41 | cmd `SSH_ASKPASS=<script> git push …` | prompt | prompt | yes |
| 42 | cmd `GIT_ASKPASS= git push …` | prompt | prompt | yes |
| 43 | cmd `env GIT_ASKPASS=<script> git push …` | prompt | prompt | yes |
| 44 | cmd `env env GIT_ASKPASS=… git push …` | prompt | prompt | yes |
| 45 | cmd `/usr/bin/env GIT_ASKPASS=… git push …` | prompt | prompt | yes |
| 46 | cmd `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=x git push …` | prompt | prompt | yes |
| 47 | cmd `GIT_CONFIG_PARAMETERS="'credential.helper'='!x'" git push …` | prompt | prompt | yes |
| 48 | cmd `GIT_CONFIG=/dev/null git push …` | prompt | prompt | yes |
| 49 | cmd `git -c credential.helper=x push -u origin B` | prompt | prompt | yes |
| 50 | cmd `git -c core.askpass=x push …` | prompt | prompt | yes |
| 51 | cmd `git -c credential..helper=x push …` | prompt | prompt | yes |
| 52 | cmd `git --config-env=credential.helper=HOME push …` | prompt | prompt | yes |
| 53 | cmd `export GIT_ASKPASS=x; git push …` | deny | deny | yes |
| 54 | cmd `export GIT_ASKPASS=x && git push …` | prompt | prompt | yes |
| 55 | cmd `git config credential.helper x && git push …` | prompt | prompt | yes |
| 56 | cmd `git config credential.helper '!touch x'` | prompt | prompt | yes |
| 57 | cmd `git config core.askpass x` | prompt | prompt | yes |
| 58 | cmd `command git push …` | prompt | prompt | yes |
| 59 | cmd `nohup git push …` | prompt | prompt | yes |
| 60 | cmd `exec -a git git push …` | prompt | prompt | yes |
| 61 | cmd `sudo git push …` | prompt | prompt | yes |
| 62 | cmd `/usr/bin/git push …` | prompt | prompt | yes |
| 63 | cmd `bash -c 'git push …'` | deny | deny | yes |
| 64 | cmd `echo B \| xargs git push -u origin` | prompt | prompt | yes |
| 65 | cmd `echo git push … \| sh` | deny | deny | yes |
| 66 | cmd `"git" "push" -u origin B` | allow | allow | yes (same words as row 1) |
| 67 | cmd `g""it push -u origin B` | allow | allow | yes (same words as row 1) |
| 68 | cmd `git push origin {B,main}` | deny | deny | yes |
| 69 | payload without `agent_id` / `session_id` | allow | allow | yes (same as row 1) |
| 70 | payload without `cwd` | prompt | prompt | yes |
| 71 | payload `tool_input.command` a list, not a string | prompt | prompt | yes |

Proof for rows 21-22 (`attack2.py`): with `GIT_CONFIG=<url-only file>` in the environment,
`git -C <consumer> config --list -z` prints only `remote.origin.url` — `GIT_CONFIG` redirects the
`git config` command alone (git-config(1): "has no effect on other Git commands") — while
`git -C <consumer> credential fill` under the same environment ran the local `!` helper (the
`pwned` file was created). A push takes the credential path through the real config, so the
silently approved push runs the helper.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | hook env `GIT_CONFIG=<file holding only remote.origin.url=https://example.invalid/consumer.git>`, local `credential.helper=!f() { touch pwned; }; f`, cmd `git push -u origin claude/feat-x` | allow (silent) | allow (silent) | `python3 /tmp/plan-capture.pEmOGC/scratch/attack2.py` on the `git archive HEAD` and `git archive origin/main` copies; `git credential fill` under that env ran the helper |
| blocking | hook env `GIT_CONFIG=<url-only file>`, local `core.askpass=<script>`, cmd `git push -u origin claude/feat-x` | allow (silent) | allow (silent) | same script, both copies |

## Non-blocking findings

None.

## Blocking findings: reproduction and fix

Both rows are one defect, classed `blocking` under rule (b) — a silent allow of a push that runs
a program (the credential helper / askpass) — although the base allows them too (not a
regression; the base reads no credential key at all).

**Reproduce.** In a cloud-profile consumer on its started branch with an https origin:
`git config credential.helper '!f() { touch /tmp/pwned; }; f'`; write a file `u.cfg` holding
`[remote "origin"]\n\turl = <the origin url>`; run the hook with `GIT_CONFIG=<u.cfg>` in its
environment on `git push -u origin <branch>` → `allow`. Same with `core.askpass` in place of the
helper.

**Cause.** `own_push_config_allows` trusts `git config --list -z` to be the config the push will
read. `GIT_CONFIG` (set in the environment the hook and the Bash tool inherit) replaces the files
`git config` reads but no other command's, so every key the probe looks for — R1, R2, R3, and the
pre-existing present-keys — can be hidden from it, as long as the substitute file supplies the one
`remote.origin.url` the probe requires (`remote get-url --push --all` then agrees, since it reads
the real config and nothing there changes the url). The new R5 already treats the hook's
environment as an input; this is the same input class.

**What the rule should do instead.** Either run the config probe with `GIT_CONFIG` removed from
its environment (so `git config --list` reads exactly what `git push` reads), or treat a
`GIT_CONFIG` present in the hook's environment — any value — as no approval, the way R5 treats a
non-empty askpass. The second is the smaller change; add a Q8 row for it with a url-only
`GIT_CONFIG` file and a local `!` helper, expecting a prompt.

## Note (not a hook input, so no finding row)

R5 reads the hook process's environment. The Bash tool's shell is initialised from the user's
profile, so a `GIT_ASKPASS` exported only by a shell rc file reaches the push but not the hook.
Writing such a file is outside the root and prompts, and neither head nor base can see it; it is
a limit of an environment check made from the hook, worth one sentence in `hooks/README.md`
beside the Q8 description.
