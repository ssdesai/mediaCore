Verdict: escalated

# Security audit — pull-agenttooling-pr173

Head `HEAD` of `claude/pull-agenttooling-pr173` against base `origin/main` (the vendored
agentTooling this pull replaces). Both trees were extracted with `git archive` into
`/tmp/plan-capture.rXBQCL/scratch/{head,base}`, and every input below was run against each
copy's own hook or script. Nothing in this checkout was run or edited.

## Rules the diff adds or changes

1. **own-push transport keys** (`own_push_config_allows`, cloud profile, any session): the
   plain own-branch push is no longer approved silently when the effective config holds
   `remote.<any>.proxy`, or any `http.<var>` / `http.<url>.<var>` whose variable is outside
   `OWN_PUSH_HTTP_SAFE_VARS`. Prompts instead.
2. **Orchestrator record move guard** (`orchestrator_stranded_own_record`, orchestrator
   sessions): the `git mv` of a vendored record is approved outright only if the folder's
   README is a regular file naming this session and `roots.py stranded <slug>` (run with
   `-B -E -s`, a 15 s timeout, no symlinked classifier) exits 0. Any other move is the
   allowlist denial.
3. **Orchestrator move order / line cap** (`main`, `orchestrator_moves_own_record`,
   `orchestrator_git_allowed`): the move is judged first, with its own 20000-char cap. A
   `git mv` on any other line is the allowlist denial, where the base admitted it to the
   allowlist and let it fall through.
4. **Legacy record classifier** (`roots.legacy_record_claim`, every record tool, the start
   and the hook): a vendored record that lists both a consumer feature and an agentTooling
   one (or a consumer whose name is agentTooling's) is `ambiguous`. That means it is
   refused, but not counted as stranded.
5. **Start refusal through the go-ahead** (`orchestration-start.sh`, anyone running a
   no-`--self` start, and `--self` self-write): the start goes on past a vendored record
   only on `roots.py start-refusal <slug>` (or `self-write`) exiting 0 **and** printing
   exactly `ok` (`ROOTS_CLI_GO_AHEAD`). The base refused when `roots.py stranded` exited 0
   and went on otherwise.

## Inputs tried

Commands that produced the evidence (all in `/tmp/plan-capture.rXBQCL/scratch/`):

- `bash setup.sh`: the two `git archive` copies, plus `base-headtests/`, which is the base
  tree carrying the head's two hook test files.
- `python3 push_attack.py`: rule 1, calling `own_push_config_allows` from each copy's hook
  against one crafted repo config.
- `bash head/agentTooling/self/tests/hook-cloud-profile.sh` and
  `bash base-headtests/self/tests/hook-cloud-profile.sh`: rule 1 end to end. Each runs the
  full hook in its fixture with the cloud profile and the Q10 rows.
- `python3 move_attack.py`: rules 2–4 end to end. Each copy's hook runs in a consumer
  fixture with the head's/base's `analysis/`, using PreToolUse payloads, cloud profile.
- `bash head/agentTooling/self/tests/hook-orchestrator-role.sh` and
  `bash base-headtests/self/tests/hook-orchestrator-role.sh`: rules 2–3 end to end.
- `bash start_attack.sh`: rules 4–5. Each copy's `orchestration-start.sh <slug>
  --coordinator` runs in a consumer fixture with crafted legacy records and a tampered
  `roots.py`.

### Rule 1: own-push config (`push_attack.py`; allow = approved silently, ask = prompts)

| config / environment | head | base |
|---|---|---|
| pristine (cloud's own `credential.interactive`, two `url.*.insteadof`) | allow | allow |
| `http.sslVerify=false` | ask | allow |
| `[HTTP] SSLVERIFY=false` (case) | ask | allow |
| `http.https://a.postbuffer.example/.sslVerify` (safe word inside url) | ask | allow |
| `http.x.postbuffer.sslVerify` (subsection ending in a safe var) | ask | allow |
| `http..sslVerify` (empty subsection) | ask | allow |
| old-style `[http.github.com] sslVerify` | ask | allow |
| `[http "a\npostbuffer"]` (escaped newline in subsection) | ask | allow |
| `http.<url>.postBuffer` (kept var) | allow | allow |
| `http.proxyAuthMethod=basic` (kept var, cloud's own) | allow | allow |
| `http.version`, bare `http.postBuffer` (kept vars) | allow | allow |
| `http.sslVerify` with no value (bool true) | ask | allow |
| `http.proxy` | ask | allow |
| `http.<url>.proxy` | ask | allow |
| `remote.origin.proxy` | ask | allow |
| `remote..proxy` (empty subsection) | ask | allow |
| `remote.origin.proxyAuthMethod` (not a proxy) | allow | allow |
| `http.curloptResolve` | ask | allow |
| `http.extraHeader` | ask | allow |
| `http.followRedirects` | ask | allow |
| `http.sslVerify` reached through `include.path` | ask | ask (include.path already listed) |
| `core.gitProxy` (git:// only; origin is https) | allow | allow |
| `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.sslVerify` in the hook's env | ask | allow |
| `HTTPS_PROXY` set in the hook's env | allow | allow |
| `GIT_SSL_NO_VERIFY=1` set in the hook's env | allow | allow |
| hook-cloud-profile.sh Q10: 26 transport keys from the repo config, plus `http.<url>.sslVerify` from a global config only (full hook) | prompt on all 27 (suite: all checks passed) | ALLOW on all 27 (the suite's only failures) |
| hook-cloud-profile.sh Q10: the 7 kept vars, and the restored fixture | ALLOW | ALLOW |

### Rules 2–4: orchestrator move (`move_attack.py`, full hook, session S)

`deny(allowlist)` is the orchestrator allowlist denial. `allow(move)` is
`ORCHESTRATOR_MOVE_REASON`.

| input | head | base |
|---|---|---|
| S's stranded record, `git mv …/wave plans/orchestrations/wave` alone | allow(move) | allow(move) |
| the printed remedy `mkdir -p plans/orchestrations && git mv …` (no `plans/`) | allow(move) | allow(move) |
| record listing only an agentTooling feature (shipped shape) | deny(allowlist) | allow(move) |
| record with `features: []` | deny(allowlist) | allow(move) |
| ambiguous record (consumer + agentTooling) | deny(allowlist) | allow(move) |
| stranded first fence, ambiguous last fence | deny(allowlist) | allow(move) |
| agentTooling first fence, stranded last fence | allow(move) | allow(move) |
| the only record names another session; S sends the move | ask(silent) | ask(silent) |
| another session sends the move | ask(silent) | ask(silent) |
| no `session_id` / `""` / `7` | ask(silent) | ask(silent) |
| a delegate of S (`agent_id` set) | allow(move) | allow(move) |
| move `&& ls` / `ls &&` move / move `; ls` | deny(allowlist) | deny |
| move `\| cat` | deny(allowlist) | ask(silent) |
| move `&&` move | deny(allowlist) | ask(silent) |
| move `2>&1` / move `> /dev/null` | allow(move) | allow(move) |
| move `> out.txt` / move `# c` | deny(allowlist) | deny(allowlist) |
| quoted operands, `orch""estrations` split quote | allow(move) | allow(move) |
| backslash, glob `wav?`, brace group `{wave,x}`, `$S`, `$(echo wave)` in an operand | deny(allowlist) | deny(allowlist) |
| `env` / `command` / `/usr/bin/git` / `GIT_DIR=x` / `git -c core.hooksPath=…` / `git mv -k` / `nohup` / `sudo` / `xargs` / `bash -c` / heredoc into `bash` / a second line | deny(allowlist) | deny(allowlist) |
| move padded with spaces to 4097 chars (cap is 20000) | allow(move) | allow(move) |
| move plus 100000 spaces | deny(allowlist) | deny(allowlist) |
| cwd `consumer/agentTooling`; cwd null | deny(allowlist) | deny(allowlist) |
| `roots.py` emptied (exit 0), record not stranded | allow(move) | allow(move) |
| `roots.py` stub `sys.exit(1)`, record stranded | deny(allowlist) | allow(move) |
| `roots.py` sleeps 30 s (timeout) | deny(allowlist) | allow(move) |
| `roots.py` a symlink to an exit-0 stub, record not stranded | deny(allowlist) | allow(move) |
| planted `routing.py` at the consumer root (the classifier's cwd), record not stranded | deny(allowlist) | allow(move) |
| record README a symlink to S's stranded record outside the folder | deny(allowlist) | deny(allowlist) |
| ledger-only session moves another session's stranded record (O39) | deny(allowlist) | allow(move) |
| ledger-only session moves an empty folder (O40) | deny(allowlist) | allow(move) |
| fixture restored: S's stranded record, move alone | allow(move) | allow(move) |
| hook-orchestrator-role.sh (head's suite) | all checks passed | FAILED, only on 16 H28 rows (O18 shipped record ALLOW, ambiguous ALLOW, O39/O40 ledger-only ALLOW, move `\| cat` and move `&&` move silent, move `&& ls`/`ls &&` move a deny with another reason), each one where the base is more permissive or the same deny |

### Rules 4–5: `orchestration-start.sh <slug> --coordinator` (`start_attack.sh`)

`refused` = exit 1, nothing written. `went on` = exit 0, record written.

| vendored record / tamper | head | base |
|---|---|---|
| stranded (`repo: consumer`) | refused | refused |
| stranded, repo spelled `CONSUMER` | refused | refused |
| ambiguous (consumer + agentTooling) | refused | refused |
| ambiguous, `AGENTTOOLING` upper-case | refused | refused |
| agentTooling's own | went on | went on |
| `features: []` | went on | went on |
| `features` a dict | went on | went on |
| a non-string `repo` plus a consumer feature | refused | refused |
| empty folder | went on | went on |
| unparseable fence | went on | went on |
| stranded first fence, ambiguous last fence | refused | refused |
| README a symlink to a stranded record elsewhere | refused | refused |
| the slug folder a symlink to a stranded record folder | refused | refused |
| stranded record, `roots.py` = `raise SystemExit("boom")` | refused | **went on** |
| stranded record, `roots.py` = `sys.exit(1)` | refused | **went on** |
| stranded record, `roots.py` emptied (exit 0, prints nothing) | refused | refused |
| stranded record, `roots.py` = `print("ok")` | **went on** | refused |
| stranded record, `roots.py` = `print("ok"); sys.exit(1)` | refused | **went on** |
| stranded record, `roots.py` = `print("ok ")` | refused | refused |
| stranded record, `roots.py` missing | refused | **went on** |
| stranded record, `roots.py` a symlink to a `print("ok")` stub | **went on** | refused |
| stranded record, a `routing.py` planted at the consumer root (run from there) | refused | refused |
| stranded record, `PYTHONPATH` naming a planted `routing.py` | refused | refused |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | a stranded vendored record, with `agentTooling/analysis/roots.py` replaced by `print("ok")`; then `orchestration-start.sh <slug> --coordinator` | went on (exit 0; record written to `plans/orchestrations/<slug>`) | refused (exit 1; `python3 -B roots.py stranded` exits 0, so the base refuses with LEGACY_RECORD_REFUSAL) | `bash /tmp/plan-capture.rXBQCL/scratch/start_attack.sh`, row `stub:print-ok`. Each copy's own `orchestration-start.sh` and `roots.py` run in `start-work/{head,base}/consumer` |
| blocking | the same, with `roots.py` a symlink to a `print("ok")` stub outside the tree | went on | refused | `start_attack.sh`, row `stub:symlink-to-stub` (same command on each copy) |
| non-blocking | own-branch push with `HTTPS_PROXY` set in the hook's environment | allow | allow | `python3 /tmp/plan-capture.rXBQCL/scratch/push_attack.py`, row `env HTTPS_PROXY`, both copies' `own_push_config_allows` |
| non-blocking | own-branch push with `GIT_SSL_NO_VERIFY=1` set in the hook's environment | allow | allow | `push_attack.py`, row `env GIT_SSL_NO_VERIFY`, both copies |
| non-blocking | orchestrator move of a record that is not stranded, with `roots.py` emptied (exit 0) | allow(move) | allow(move) | `python3 /tmp/plan-capture.rXBQCL/scratch/move_attack.py`, row `roots.py stub exit 0, record not stranded`, both copies' hooks |

## Non-blocking findings

1. **Pre-existing silent allow: proxy/TLS environment variables.** Input: the cloud
   own-branch push while the hook's environment sets `HTTPS_PROXY`/`https_proxy`/`ALL_PROXY`,
   or `GIT_SSL_NO_VERIFY`/`GIT_SSL_CAINFO`/`GIT_SSL_CERT`. Head allows, and the base allows
   too. Rule 1 now treats `http.proxy` and `http.sslVerify` in config as moving or weakening
   the transport, but git reads the same settings from these variables, and
   `OWN_PUSH_HELPER_ENVS` does not list them. What the rule should do instead: prompt when
   any `GIT_SSL_*` or `GIT_CURL_*` variable is set, and when a proxy variable differs from
   the container's own (the cloud container sets a proxy legitimately, so a blanket prompt
   on `HTTPS_PROXY` would prompt on every push). These variables come from the hook's own
   environment, not from anything the agent writes, so the exposure is low.
2. **Pre-existing silent allow: the orchestrator move trusts an edited classifier.** Input:
   `agentTooling/analysis/roots.py` emptied (exits 0), with S's own record not stranded (it
   lists only an agentTooling feature); then the move alone. Head allows(move), and the base
   allows(move) too, since it ran no classifier. What the rule should do instead: run the
   classifier only when `analysis/roots.py`, `analysis/routing.py` and
   `hooks/shared_rules.py` are unmodified against `HEAD` (`git diff --quiet HEAD -- …`), so a
   working-tree edit is no approval. Alternatively, read the record's last fence in the hook
   itself (it already parses fences through `orchestrator_role`) instead of running a
   repo-resident script. Same root cause as the blocking finding below.

## Blocking findings

### B1: a `roots.py` stub printing `ok` lets the start go on past a stranded record

**Reproduce.** In a consuming repo with a stranded legacy record at
`agentTooling/self/orchestrations/<slug>/README.md` (last fence lists a feature whose `repo`
is the consumer's name), replace `agentTooling/analysis/roots.py` with the single line
`print("ok")`, or make it a symlink to such a file. Then run
`./agentTooling/orchestration-start.sh <slug> --coordinator --session <id>`:

- **Head:** exits 0 and writes `plans/orchestrations/<slug>/README.md`, so the new record
  shadows the stranded one, which the refusal exists to prevent.
- **Base:** refuses with `LEGACY_RECORD_REFUSAL`. Its polarity was "exit 0 from
  `roots.py stranded` means refuse", so this stub refuses there.

Reproduced by `bash /tmp/plan-capture.rXBQCL/scratch/start_attack.sh` (rows
`stub:print-ok`, `stub:symlink-to-stub`).

**Context.** This is a regression only by input-for-input comparison. The opposite stubs
(`sys.exit(1)`, a crash, a missing `roots.py`, `print("ok"); sys.exit(1)`) went on under the
base and are refused under the head. Overall tamper resistance improved, but the owner's
rule counts each input on its own. The head's own docs (`orchestration-start.sh`,
`roots.py`, `hooks/README.md`) say "an emptied or stubbed roots.py … refuses", which holds
only for a stub that does not print the token. The same gap applies to the `--self`
`self-write` go-ahead (stub `print("ok")` writes on both copies, so no regression there).

**What the rule should do instead.** Do not take a go-ahead from a classifier the session
can change without a commit. Before asking `roots.py start-refusal` (and `self-write`), the
start should check that the classifier's files are unmodified against `HEAD`:
`git -C "$REPO_DIR" diff --quiet HEAD -- <vendored analysis/roots.py, analysis/routing.py,
hooks/shared_rules.py>`, with an untracked or symlinked `roots.py` also refused. It should
refuse, naming the modified file, when they are not. A commit is a write the human approves
and an edit is not (`self/features/hook-audit-gaps/NOTES.md` ruling 1). With that check,
every stub row above refuses on the head, and the base's refusals are kept.
