Verdict: escalated

# Security audit — pull-agenttooling-pr173 (round 02)

Head `d354d70d`, base `origin/main` `08fb89f5`. Two throwaway copies were built under the
pass's scratch directory: `git archive HEAD` → `head/` and `git archive origin/main` → `base/`.
Each was `git init`-ed and committed, with `origin` set to an https URL. The same payloads
ran against both. The scripts were run by name from the scratch directory (`attack_move.py`,
`attack2.py`, `attack_start.py`, `attack_hook_empty.py`). The hook ran as the PreToolUse
executable with `CLAUDE_PROJECT_DIR=<copy>`, `HOME`/`TMPDIR` in scratch and
`AGENTTOOLING_PROFILE=cloud` unless a row says `local`. Record-move payloads came from session
S (`5e5e…0001`), whose record is the vendored `agentTooling/self/orchestrations/zzmine/README.md`.

## Rules the diff adds or changes

1. **R1 — orchestrator record move (`allow-repo-commands.sh`, `orchestrator_stranded_own_record`).**
   For an orchestrator session, the hook approves `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`
   outright only when the folder's README is a regular file naming the session and
   `roots.py stranded <slug>` exits 0. Any other line is held to the allowlist. A `git mv` inside a larger line is now denied
   (`orchestrator_git_allowed` returns False).
2. **R2 — own-push transport keys (`own_push_config_allows`).** The cloud own-push approval
   is refused when the effective config holds `remote.<any>.proxy`, or any `http.<var>` /
   `http.<url>.<var>` whose variable is outside `OWN_PUSH_HTTP_SAFE_VARS`.
3. **R3 — `orchestration-start.sh` vendored-record refusal (with `roots.py start-refusal` /
   `legacy_record_claim`).** A start without `--self` of a slug that has a vendored record is refused when the
   record is stranded (consumer feature only) or ambiguous (consumer and agentTooling features).
   It now goes on only on exit 0 of `roots.py start-refusal`. Any other exit refuses (fail closed).

## Inputs tried and results

Legend: `allow[move]` means the hook approved the move outright (`ORCHESTRATOR_MOVE_REASON`).
`deny[role]` means the orchestrator role or allowlist denial. `deny` means another denial.
`ask(silent)` means no output, so the human judges.

### R1 — record move, by record shape (command: the plain move, then `mkdir -p plans/orchestrations && ` + move)

| record (last fence `features`) | plain: head | plain: base | lead: head | lead: base |
|---|---|---|---|---|
| stranded `[{repo: mediaCore}]` | allow[move] | allow[move] | allow[move] | allow[move] |
| own `[]` | deny[role] | allow[move] | deny[role] | allow[move] |
| ambiguous `[mediaCore, agentTooling]` | deny[role] | allow[move] | deny[role] | allow[move] |
| case-variant ambiguous `[MEDIACORE, AgentTooling]` | deny[role] | allow[move] | deny[role] | allow[move] |
| `[mediaCore, "agentTooling "]` (trailing space) | allow[move] | allow[move] | allow[move] | allow[move] |
| `features` a dict, not a list | deny[role] | allow[move] | deny[role] | allow[move] |
| `[mediaCore, "agentTooling"]` (string, not dict) | allow[move] | allow[move] | allow[move] | allow[move] |
| `[mediaCore, {repo: null}]` | allow[move] | allow[move] | allow[move] | allow[move] |
| two fences, first stranded, last own | deny[role] | allow[move] | deny[role] | allow[move] |
| two fences, first stranded, last ambiguous | deny[role] | allow[move] | deny[role] | allow[move] |
| README a symlink to a stranded README in another folder | deny[role] | deny[role] | deny[role] | deny[role] |
| classifier `analysis/roots.py` a symlink (stranded record) | deny[role] | allow[move] | deny[role] | allow[move] |
| classifier missing (stranded record) | deny[role] | allow[move] | deny[role] | allow[move] |
| `plans/orchestrations` a symlink | deny[role] | deny[role] | deny[role] | deny[role] |
| destination already exists | deny[role] | deny[role] | deny[role] | deny[role] |
| classifier empty file, own record | allow[move] | allow[move] | — | — |
| classifier `sys.exit(0)`, own record | allow[move] | allow[move] | — | — |
| classifier empty file, ambiguous record | allow[move] | allow[move] | — | — |
| classifier `sys.exit(0)`, ambiguous record | allow[move] | allow[move] | — | — |
| ledger names S for `zzmine`, README names session T (stranded) | deny[role] | allow[move] | — | — |
| ledger names S, folder empty (no README) | deny[role] | allow[move] | — | — |
| ledger names S, README is a directory | deny[role] | allow[move] | — | — |

### R1 — record move, by command shape (the same results for the stranded, own and ambiguous records unless noted)

| command | stranded: head / base | own: head / base | ambiguous: head / base |
|---|---|---|---|
| `git mv SRC DST` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `mkdir -p plans/orchestrations && git mv SRC DST` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `git mv SRC DST ; ls` | deny[role] / deny | deny[role] / deny | deny[role] / deny |
| `ls && git mv SRC DST` | deny[role] / deny | deny[role] / deny | deny[role] / deny |
| `git mv SRC DST \| cat` | deny[role] / ask(silent) | deny[role] / ask(silent) | deny[role] / ask(silent) |
| `git mv SRC DST && git mv SRC DST` | deny[role] / ask(silent) | deny[role] / ask(silent) | deny[role] / ask(silent) |
| `env git mv …` | deny[role] / deny[role] | same | same |
| `env env git mv …` | deny[role] / deny[role] | same | same |
| `/usr/bin/env git mv …` | deny[role] / deny[role] | same | same |
| `command git mv …` | deny[role] / deny[role] | same | same |
| `exec -a x git mv …` | deny[role] / deny[role] | same | same |
| `nohup git mv …` | deny[role] / deny[role] | same | same |
| `sudo git mv …` | deny[role] / deny[role] | same | same |
| `bash -c 'git mv …'` | deny[role] / deny[role] | same | same |
| `echo 'git mv …' \| sh` | deny[role] / deny[role] | same | same |
| `echo SRC DST \| xargs git mv` | deny[role] / deny[role] | same | same |
| `find … -name zzmine -exec git mv {} DST \;` | deny[role] / deny[role] | same | same |
| `/usr/bin/git mv …` | deny[role] / deny[role] | same | same |
| `"git" mv SRC DST` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `git mv agentTooling/self/orch""estrations/zzmine DST` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `git mv …/\zzmine DST` (backslash) | deny[role] / deny[role] | same | same |
| `git mv ./SRC DST` | deny[role] / deny[role] | same | same |
| `git mv SRC/ DST` | deny[role] / deny[role] | same | same |
| `git mv -- SRC DST` | deny[role] / deny[role] | same | same |
| `git mv -f SRC DST` | deny[role] / deny[role] | same | same |
| `git -C . mv SRC DST` | deny[role] / deny[role] | same | same |
| `git -c a.b=c mv SRC DST` | deny[role] / deny[role] | same | same |
| `GIT_DIR=x git mv SRC DST` | deny[role] / deny[role] | same | same |
| `git mv SRC DST > /dev/null` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `git mv SRC DST 2>&1` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `git mv SRC DST > out.txt` | deny[role] / deny[role] | same | same |
| `git mv …/zzmin? DST` (glob) | deny[role] / deny[role] | same | same |
| `git mv …/{zzmine,x} DST` (brace) | deny[role] / deny[role] | same | same |
| `git mv $SRC DST` | deny[role] / deny[role] | same | same |
| `git mv $(echo SRC) DST` | deny[role] / deny[role] | same | same |
| `git mv SRC DST⏎ls` | deny[role] / deny[role] | same | same |
| `mkdir -p plans/orchestrations \|\| git mv …` | deny[role] / deny[role] | same | same |
| `mkdir -p plans/orchestrations ; git mv …` | deny[role] / deny[role] | same | same |
| lead twice, then the move | deny[role] / deny[role] | same | same |
| two leading spaces, then the move | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| tabs instead of spaces | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |
| `cat <<'EOF'⏎x⏎EOF⏎git mv …` | deny[role] / deny[role] | same | same |
| `git mv SRC DST extra` | deny[role] / deny[role] | same | same |
| plain move, `AGENTTOOLING_PROFILE=local` | allow[move] / allow[move] | deny[role] / allow[move] | deny[role] / allow[move] |

The rows that differ only in quoting or blanks (`"git"`, `pa""th`, leading space, tabs,
`> /dev/null`, `2>&1`) are the same move once the shell has read them. Both trees approve them
only where they approve the plain move.

### R1 — payload fields (stranded record, plain move)

| payload | head | base |
|---|---|---|
| `session_id` = T (another session) | ask(silent) | ask(silent) |
| no `session_id` | ask(silent) | ask(silent) |
| `session_id` = `""` | ask(silent) | ask(silent) |
| `session_id` = `7` (int) | ask(silent) | ask(silent) |
| `cwd` = `<root>/agentTooling` | deny[role] | deny[role] |
| `cwd` = `<root>/plans` | deny[role] | deny[role] |

### R2 — own-push transport keys (`own_push_config_allows(root)`, imported from each tree's hook; `True` = approval possible)

The global config was an empty file (`GIT_CONFIG_GLOBAL`) and `GIT_CONFIG_NOSYSTEM=1` was set.
Each key was set with `git config --local` in the copy, then unset.

| config / environment | head | base |
|---|---|---|
| none | True | True |
| `http.proxyAuthMethod=anyauth` | True | True |
| `http.proxy` | False | True |
| `http.sslVerify=false` | False | True |
| `http.https://github.com/.proxy` | False | True |
| `http.https://x.version/.proxy` (URL holding a safe var's name) | False | True |
| `http.https://github.com.sslVerify` | False | True |
| `http.https://github.com/.version` | True | True |
| `http.extraHeader` | False | True |
| `http.curloptResolve` | False | True |
| `http.cookieFile` | False | True |
| `http.sslCAInfo` | False | True |
| `http.postBuffer` | True | True |
| `http.someNewVar` | False | True |
| `remote.origin.proxy` | False | True |
| `remote..proxy` (empty subsection) | False | True |
| `remote.x.proxy` | False | True |
| `remote.origin.proxyAuthMethod=basic` | True | True |
| `https.proxy` (not a git key) | True | True |
| `HTTP.Proxy` (case) | False | True |
| `core.sshCommand` | False | False |
| `include.path` → file with `[http] proxy` | False | False |
| env `GIT_CONFIG_PARAMETERS='http.proxy'=…` | False | True |
| env `GIT_CONFIG_COUNT=1`, `http.sslVerify=false` | False | True |
| env `HTTPS_PROXY=http://evil` | True | True |
| env `GIT_SSL_NO_VERIFY=1` | True | True |
| env `GIT_PROXY_SSL_CAINFO=/tmp/x` | True | True |

### R3 — `orchestration-start.sh zzmine` (local profile, `CLAUDE_CODE_SESSION_ID`=S, run from the copy's root)

"went on" means the script wrote `plans/orchestrations/zzmine/README.md`.

| vendored record / classifier | head | base |
|---|---|---|
| stranded | refused (git mv text) | refused (git mv text) |
| own `[]` | went on | went on |
| ambiguous | refused (ambiguous text) | refused (git mv text) |
| case-variant ambiguous | refused (ambiguous text) | refused (git mv text) |
| `[mediaCore, "agentTooling "]` | refused (git mv text) | refused (git mv text) |
| `features` a dict | went on | went on |
| `[mediaCore, "agentTooling"]` | refused (git mv text) | refused (git mv text) |
| `[mediaCore, {repo: null}]` | refused (git mv text) | refused (git mv text) |
| two fences, last own | went on | went on |
| two fences, last ambiguous | refused (ambiguous text) | refused (git mv text) |
| README a symlink to a stranded README | refused (git mv text) | refused (git mv text) |
| folder with no README | went on | went on |
| README is a directory | went on | went on |
| `<slug>` is a file, not a folder | went on | went on |
| folder a symlink to a stranded folder | refused (git mv text) | refused (git mv text) |
| README undecodable bytes | went on | went on |
| shipped `tooling-wave-2026-11-17` | went on | went on |
| shipped `program-ab` | went on | went on |
| shipped `hook-hardening-wave` | went on | went on |
| **classifier `roots.py` an empty file — stranded record** | **went on** | refused (git mv text) |
| **classifier empty — ambiguous record** | **went on** | refused (git mv text) |
| **classifier empty — own record** | **went on** | refused (git mv text) |
| **classifier `import sys; sys.exit(0)` — stranded record** | **went on** | refused (git mv text) |
| **classifier `sys.exit(0)` — ambiguous record** | **went on** | refused (git mv text) |
| **classifier `sys.exit(0)` — own record** | **went on** | refused (git mv text) |
| classifier `sys.exit(1)` — stranded / ambiguous / own | refused (classifier failed) ×3 | went on ×3 |
| classifier a syntax error — stranded / ambiguous / own | refused (classifier failed) ×3 | went on ×3 |
| classifier missing — stranded / ambiguous / own | refused (classifier failed) ×3 | went on ×3 |
| classifier a symlink to the real file — stranded / ambiguous / own | refused (git mv) / refused (ambiguous) / went on | refused (git mv) ×2 / went on |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | `orchestration-start.sh zzmine` with a stranded (or ambiguous) vendored record at `agentTooling/self/orchestrations/zzmine/` and `agentTooling/analysis/roots.py` truncated to an empty file | went on: wrote `plans/orchestrations/zzmine/README.md`, rc 0 | refused with the `git mv` text, rc 1 | `attack_start.py`: `./agentTooling/orchestration-start.sh zzmine` from `<scratch>/head` and `<scratch>/base`, `AGENTTOOLING_PROFILE=local`, `CLAUDE_CODE_SESSION_ID`=S, after `open(roots.py,"w").close()` |
| blocking | the same start with `roots.py` replaced by `import sys; sys.exit(0)` (any classifier that exits 0 without printing) | went on, rc 0 | refused with the `git mv` text, rc 1 | `attack_start.py`, same command on both copies |
| non-blocking | own-push approval with `HTTPS_PROXY` / `http_proxy` / `ALL_PROXY`, `GIT_SSL_NO_VERIFY`, `GIT_SSL_CAINFO` / `GIT_PROXY_SSL_CAINFO` in the hook's environment (pre-existing silent allow) | `own_push_config_allows` True | True | `attack2.py`: `own_push_config_allows(<copy>)` imported from each tree's hook, with the variable set |
| non-blocking | record move of a record whose last fence lists `{"repo": "agentTooling "}` (trailing space) or `"agentTooling"` as a bare string beside a consumer feature (pre-existing silent allow) | allow[move] | allow[move] | `attack_move.py`: kinds `space_amb` and `stranded_dict_junk`, plain move from S on both copies |
| non-blocking | record move with `analysis/roots.py` empty or `sys.exit(0)`, own or ambiguous record (pre-existing silent allow) | allow[move] | allow[move] | `attack_hook_empty.py`: the plain move from S on both copies |

## Non-blocking findings

1. **Pre-existing silent allow: transport set through the environment rather than through config (R2).**
   R2 refuses `http.proxy`, `http.sslVerify` and `http.sslCAInfo` set in config. On both head and base,
   `own_push_config_allows` still returns True when the hook's environment sets
   `HTTPS_PROXY`/`https_proxy`/`ALL_PROXY` (curl's proxy), `GIT_SSL_NO_VERIFY` or
   `GIT_SSL_CAINFO`/`GIT_PROXY_SSL_CAINFO`. These have the same effect as the keys R2 refuses.
   *Instead:* the own-push approval should prompt when any of these is non-empty, as it already
   does for `GIT_ASKPASS`/`GIT_SSH*`. If the cloud container sets a proxy variable itself, the
   check should allow only that exact value. File in `plans/BACKLOG.md`.
2. **Pre-existing silent allow: the claim classifier does not normalise `repo` (R1, R3).**
   A fence listing `{"repo": "agentTooling "}` (with whitespace) or the bare string `"agentTooling"`
   beside a consumer feature is classed stranded. The hook then approves the `git mv` of what
   may be an agentTooling wave, and the start names the `git mv`. Base and head behave the same.
   *Instead:* `legacy_record_claim` should strip whitespace from `repo`, and should class a
   record as ambiguous (or refuse it) when a feature entry is not a dict or names an
   unrecognised repo. File in `plans/BACKLOG.md`.
3. **Pre-existing silent allow: the hook's classifier call treats a bare exit 0 as "stranded" (R1).**
   With `analysis/roots.py` empty, or exiting 0 without output, the hook approves the move of
   S's own or ambiguous record. The base approved those moves with no classifier at all.
   *Instead:* `roots.py stranded` should print a fixed token on success, and the hook should
   require that token on stdout as well as exit 0. That way a truncated or stubbed classifier fails
   closed. File in `plans/BACKLOG.md`. Blocking finding B1 below has the same root cause.

## Blocking findings

### B1 — `orchestration-start.sh` goes on when the classifier exits 0 without classifying

**Reproduce** (in a consuming-repo copy, local profile, `CLAUDE_CODE_SESSION_ID` set to a valid id):

1. Create `agentTooling/self/orchestrations/zzmine/README.md` with a fence
   `{"slug":"zzmine","session":"<id>","features":[{"slug":"f","repo":"mediaCore"}]}`.
   This is a stranded record, which the start must refuse with the `git mv`.
2. Truncate `agentTooling/analysis/roots.py` to zero bytes. Replacing it with
   `import sys; sys.exit(0)` has the same effect.
3. Run `./agentTooling/orchestration-start.sh zzmine`.

The head writes `plans/orchestrations/zzmine/README.md` and exits 0. The base refuses with the
`git mv` text, because its test was "`roots.py stranded` exits 0 → refuse". The same is true for
an ambiguous record and for an own record. The head's fail-closed change covers a non-zero exit, but it
reads a bare exit 0, with nothing printed, as "may go on". A classifier that is empty, stubbed, or
lacks the `start-refusal` branch but exits 0 therefore turns the refusal into a go-on. The base
refused in that case.

**What the rule should do instead:** go on only on a positive answer the classifier cannot give
by accident. For example, `roots.py start-refusal <slug>` prints a fixed token such as `ok` on
stdout when the start may go on, and `orchestration-start.sh` checks
`start_rc == START_OK_RC && start_refusal == <token>`. Anything else refuses, including exit 0
with empty output: the refusal text when one was printed, the "could not be classified" text
otherwise. Add a test row to `self/tests/orchestration-records-in-repo.sh` with an empty and an
exit-0 `roots.py` in front of a stranded record.
