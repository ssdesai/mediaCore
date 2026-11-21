Verdict: escalated

# Security audit — pull-agenttooling-pr173 (round 1)

Scope: the hook rules the diff against `origin/main` adds or changes in
`agentTooling/hooks/allow-repo-commands.sh`, `agentTooling/analysis/roots.py` and
`agentTooling/orchestration-start.sh` (the two README changes are documentation only):

1. **Own-push transport keys.** In the cloud, the silent approval of `git push [-u] origin <own branch>`
   now asks the human when the effective config has any `http.*` / `http.<url>.*` variable outside
   `OWN_PUSH_HTTP_SAFE_VARS`, or any `remote.<name>.proxy`.
2. **Orchestrator record move.** The one write approved outright for an orchestrator session
   (`[mkdir -p plans/orchestrations &&] git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`)
   now also requires the folder's README to be a regular file naming this session, and
   `roots.py stranded <slug>` to exit 0. A `git mv` anywhere else on an orchestrator line is now the
   allowlist denial, and `main()` now judges the move line before (and apart from) `orchestrator_command_allowed`.
3. **Start refusal / classifier.** `legacy_record_claim` splits the old "stranded" result into stranded,
   ambiguous (lists both the consumer and agentTooling) and own. `orchestration-start.sh` (no `--self`)
   refuses unless `roots.py start-refusal <slug>` exits 0, so a crash now refuses.

## Method

- Head copy: `git archive HEAD` into `/tmp/plan-capture.BSus1H/scratch/head`. Base copy: `git archive origin/main`
  into `.../scratch/base`. Each was made a git repo (`git init`, origin `https://github.com/ssdesai/mediaCore.git`,
  one commit) with `HOME` pointing at an empty scratch `.gitconfig` and `GIT_CONFIG_NOSYSTEM=1`.
- Hook cases: `python3 <copy>/agentTooling/hooks/allow-repo-commands.sh` with the PreToolUse JSON
  (`tool_name: Bash`, `session_id`, `agent_id`, `cwd`, `tool_input.command`) on stdin and
  `CLAUDE_PROJECT_DIR=<copy>`. Move cases plant `agentTooling/self/orchestrations/audit-move/README.md` with a
  role fence `{"session": "audit-sess-1", "features": [{"repo": …, "session": …}]}` (session `audit-sess-1`).
- Push-config cases (`P*`): `own_push_config_allows(<fresh repo>)` from each copy's hook module, loaded by path;
  end-to-end cases (`E*`): the whole hook under `AGENTTOOLING_PROFILE=cloud` on the started feature's branch.
- Start cases: `roots.py start-refusal audit-move` (head) vs `roots.py stranded audit-move` (base) (`S*`), and the
  whole `orchestration-start.sh audit-move` under `AGENTTOOLING_PROFILE=local` (`T*`).
- Driver: `/tmp/plan-capture.BSus1H/scratch/attack.py` (setup: `setup.sh` beside it).

## Inputs tried

"allow" = hook printed `allow`; "ask" = no output (human decides) or, for `P*`, `own_push_config_allows` false
so the push is not approved silently; "deny" = hook printed `deny`. `MOVE` = `git mv agentTooling/self/orchestrations/audit-move plans/orchestrations/audit-move`.

| # | Input | Head | Base |
|---|---|---|---|
| M1 | stranded record (repo `mediaCore`), `MOVE` | allow | allow |
| M2 | stranded, `mkdir -p plans/orchestrations && MOVE` | allow | allow |
| M3 | ambiguous (`mediaCore` + `agentTooling`), `MOVE` | deny | allow |
| M4 | own (`agentTooling` only), `MOVE` | deny | allow |
| M5 | stranded, repo spelled `MEDIACORE` | allow | allow |
| M5b | ambiguous, `mediacore` + `AGENTTOOLING` | deny | allow |
| M5c | ambiguous first fence, stranded LAST fence | allow | allow |
| M5d | stranded first fence, ambiguous last fence | deny | allow |
| M5e | `features` an object, not a list | deny | allow |
| M5f | `repo` a list `["mediaCore"]` | deny | allow |
| M7 | stranded, `MOVE` + ` 2>&1` × 5000 (> 20000 chars) | **allow** | deny |
| M7b | stranded, `MOVE` + ` > /dev/null` × 2000 | **allow** | deny |
| M7c | ambiguous, `MOVE` + ` 2>&1` × 5000 | deny | deny |
| M8 | stranded, `git mv` + 25000 spaces + operands | **allow** | deny |
| M8b | stranded, mkdir lead + `MOVE` + 25000 trailing spaces | **allow** | deny |
| B19999 | stranded, `MOVE` padded with spaces to 19999 chars | allow | allow |
| B20000 | same, exactly 20000 chars | allow | allow |
| B20001 | same, 20001 chars | **allow** | deny |
| M9 | stranded, `MOVE && ls` | deny | deny |
| M9b | ambiguous, `MOVE ; ls` | deny | deny |
| M9c | ambiguous, `ls && MOVE` | deny | deny |
| M9d | stranded, `MOVE \| cat` | deny | ask |
| M9e | stranded, `git mv -f …` | deny | deny |
| M9f | stranded, `git mv -k …` | deny | deny |
| M9g | stranded, `./agentTooling/…` source spelling | deny | deny |
| M9h | stranded, operands in `'…'` / `"…"` | allow | allow |
| M9i | stranded, `env MOVE` | deny | deny |
| M9j | stranded, `command MOVE` | deny | deny |
| M9k | stranded, `GIT_DIR=x MOVE` | deny | deny |
| M9l | stranded, `git -C . mv …` | deny | deny |
| M9m | stranded, `bash -c 'MOVE'` | deny | deny |
| M9n | stranded, `MOVE` newline `ls` | deny | deny |
| M9o | stranded, `MOVE &` | deny | deny |
| M9p | ambiguous, `MOVE ; MOVE` | deny | ask |
| M10 | stranded, cwd = consumer root (control) | allow | allow |
| M10b | stranded, cwd = `plans/` | deny | deny |
| M10c | stranded, payload without `cwd` | deny | deny |
| M10d | `session_id` null | ask | ask |
| M10e | `session_id` a list | ask | ask |
| M10f | `session_id` empty | ask | ask |
| M11 | ambiguous, `analysis/roots.py` a symlink to the real file | deny | allow |
| M11b | stranded, `analysis/roots.py` a symlink | deny | allow |
| M12 | ambiguous, `analysis/roots.py` edited to `sys.exit(0)` | allow | allow |
| M12b | stranded, `analysis/roots.py` a syntax error (crash) | deny | allow |
| M13 | ambiguous, `PYTHONPATH` = dir with a fake `routing.py` + `sitecustomize.py` | deny | allow |
| M13b | ambiguous, `PYTHONSTARTUP` / `PYTHONSAFEPATH` set | deny | allow |
| M13c | ambiguous, `routing.py` / `shared_rules.py` planted in the consumer root (classifier's cwd) | deny | allow |
| M14 | stranded, folder README a symlink | deny | deny |
| M15 | role from the ledger only, folder README names ANOTHER session | deny | allow |
| M15b | role from the ledger only, folder has no README | deny | allow |
| M16 | shipped `tooling-wave-2026-11-17` + appended role fence for this session | deny | allow |
| P0 | clean config, origin only | allow | allow |
| P1 | `http.proxy` | ask | allow |
| P2 | `http.https://github.com/.proxy` | ask | allow |
| P3 | `http.sslVerify=false` | ask | allow |
| P3b | `http.<url>.sslverify=false` | ask | allow |
| P4 | `http.extraHeader` | ask | allow |
| P5 | `http.cookieFile` | ask | allow |
| P6 | `http.sslCAInfo` | ask | allow |
| P7 | `http.curloptResolve` | ask | allow |
| P8 | `http.followRedirects` | ask | allow |
| P9 | `http.postBuffer` (safe) | allow | allow |
| P9b | `http.<url>.postBuffer` (safe) | allow | allow |
| P9c | `http.proxyAuthMethod` (safe) | allow | allow |
| P10 | `[http "x.postbuffer"] proxy` (subsection shaped like a safe var) | ask | allow |
| P10b | `[http "proxy"] postbuffer` | allow | allow |
| P10c | `[HTTP] PROXY` (upper case in the file) | ask | allow |
| P10d | old-style `[http.https://github.com] proxy` | ask | ask |
| P11 | `remote.origin.proxy` | ask | allow |
| P11b | `remote.upstream.proxy` | ask | allow |
| P11c | `remote.origin.proxyAuthMethod` | allow | allow |
| P11d | `[remote "origin"] PROXY` | ask | allow |
| P12 | `http.proxy` in `~/.gitconfig` | ask | allow |
| P13 | `http.proxy` via `GIT_CONFIG_COUNT/KEY/VALUE` | ask | allow |
| P13b | `http.proxy` via `GIT_CONFIG_PARAMETERS` | ask | allow |
| P14 | `http.proxy` via `include.path` | ask | ask |
| P14b | `http.proxy` via `includeIf.gitdir:/.path` | ask | ask |
| P15 | `core.gitProxy` (git:// only; origin is https) | allow | allow |
| P16 | `https_proxy` / `HTTPS_PROXY` in the hook's environment (not settable from the command line's plain-push shape) | allow | allow |
| P16b | `GIT_SSL_NO_VERIFY` in the environment (same) | allow | allow |
| P17 | `http.sslBackend` | ask | allow |
| P17b | `http.emptyAuth` | ask | allow |
| P17c | `http.version` (safe) | allow | allow |
| P17d | `http.proxy.version` (url `proxy`, safe var) | allow | allow |
| P18 | `[http ""] proxy` (empty subsection) | ask | allow |
| P19 | `url.<x>.insteadOf` matching origin | ask | ask |
| P20 | `remote.origin.uploadpack` (fetch only) | allow | allow |
| P21 | `[http] sslverify` with no value | ask | allow |
| E0 | whole hook, `git push -u origin <own branch>`, clean config | allow | allow |
| E1 | same, `http.proxy` set | ask | allow |
| E2 | same, `http.<url>.sslVerify=false` | ask | allow |
| E3 | same, `remote.origin.proxy` | ask | allow |
| E4 | same, `http.postBuffer` (safe) | allow | allow |
| E5 | `git -c http.proxy=… push origin <b>` | ask | ask |
| S1 | start classifier, stranded | refuse | refuse |
| S2 | ambiguous | refuse | refuse |
| S3 | own | go on | go on |
| S4 | `MEDIACORE` | refuse | refuse |
| S5 | `mediaCore` + `AgentTooling` | refuse | refuse |
| S6 | last fence own, earlier stranded | go on | go on |
| S7 | last fence stranded, earlier own | refuse | refuse |
| S8 | `features` a string | go on | go on |
| S9 | `features` entries non-dict | go on | go on |
| S10 | `repo` a list | go on | go on |
| S11 | `repo` `" mediaCore"` | go on | go on |
| S12 | `repo` `ssdesai/mediaCore` | go on | go on |
| S13 | folder with no README | go on | go on |
| S14 | README with no fence | go on | go on |
| S15 | unclosed fence | go on | go on |
| S16 | `repo` null + `mediaCore` | refuse | refuse |
| S17 | `mediaCore` + `agentTooling` + `x` | refuse | refuse |
| T1 | `orchestration-start.sh`, stranded | refused (git mv text) | refused (git mv text) |
| T2 | ambiguous | refused (both readings) | refused (git mv text) |
| T3 | own | goes on, writes record | goes on, writes record |
| T4 | stranded, `roots.py` broken (crash) | refused (classifier failed) | goes on, writes record |
| T5 | own, `roots.py` broken (crash) | refused (classifier failed) | goes on, writes record |
| T6 | folder with no README | goes on, writes record | goes on, writes record |

Every changed rule is at least as strict as the base on every input above except M7, M7b, M8, M8b and B20001.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | orchestrator session (`audit-sess-1`, stranded record at `agentTooling/self/orchestrations/audit-move`), command `git mv agentTooling/self/orchestrations/audit-move plans/orchestrations/audit-move` padded with spaces or harmless redirects (` 2>&1`, ` > /dev/null`) past `ORCHESTRATOR_MAX_LINE_CHARS` (20000): M7, M7b, M8, M8b, B20001 | allow (`the orchestrator's move of its own record…`) | deny (allowlist denial: line refused unread, R1) | `python3 scratch/attack.py bound` → `python3 {head,base}/agentTooling/hooks/allow-repo-commands.sh` with the same payload on stdin, `CLAUDE_PROJECT_DIR={head,base}` |
| non-blocking | ambiguous record, `analysis/roots.py` edited in the working tree to `sys.exit(0)`, `MOVE` (M12) | allow | allow | same driver, `tamper_roots` prep on each copy |
| non-blocking | record whose earlier fence is ambiguous but whose LAST fence lists only the consumer (an appended fence), `MOVE` (M5c) | allow | allow | same driver, two fences written on each copy |

## Non-blocking findings

1. **Pre-existing silent allow — the classifier is a working-tree file (M12).** With the ambiguous record
   `{"features": [{"repo": "mediaCore"}, {"repo": "agentTooling"}]}` and `agentTooling/analysis/roots.py`
   replaced by `import sys; sys.exit(0)`, the move is allowed on head; base allows the same move with no classifier
   at all. The new rule checks that `roots.py` is a regular file and not a symlink, but trusts its content. It
   should run the classifier as committed (for example, `git show HEAD:agentTooling/analysis/roots.py`, or refuse
   when `git diff --quiet HEAD -- agentTooling/analysis/ agentTooling/hooks/shared_rules.py` fails), or classify
   in-process from `shared_rules` so that no editable file decides an outright approval. File in `plans/BACKLOG.md`.
2. **Pre-existing silent allow — only the last fence is classified (M5c).** A record whose original fence lists
   both `mediaCore` and `agentTooling` reads as stranded once a fence listing only `mediaCore` is appended, and
   the move is allowed on both head and base. Readers of the record's data take the last fence by design. For an
   outright write approval, though, the classifier should count a repo listed in ANY fence, or in the record as
   first committed, the way `names_role` reads every fence. File in `plans/BACKLOG.md`.

## Blocking finding: the line-length check is skipped for the record move

**Reproduce.** In a consuming-repo checkout, run as an orchestrator session whose own stranded record sits at
`agentTooling/self/orchestrations/<slug>/README.md` (a role fence naming the session, with `features` listing
only the consuming repo). Send the Bash command

```
git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>
```

followed by enough spaces (or ` 2>&1` / ` > /dev/null` repeats) to bring the line past 20000 characters, with
`cwd` set to the consuming repo's root. The head hook prints `allow` with `ORCHESTRATOR_MOVE_REASON`. The base
hook prints the allowlist `deny`. At exactly 20000 characters both allow; at 20001 they diverge.

**Cause.** On the base, `main()` reached the move only through `orchestrator_command_allowed`, whose first check
refuses any line longer than `ORCHESTRATOR_MAX_LINE_CHARS` before reading it (R1). The head's `main()` calls
`orchestrator_moves_own_record` first and allows when it returns true. Nothing on that path checks the length, so
`ORCHESTRATOR_HARMLESS_REDIRECT_RE.sub` and the tokenizer read a line of any size.

**What the rule should do instead.** Refuse an over-long line before any reading on the move path too. Put the
`len(command) > ORCHESTRATOR_MAX_LINE_CHARS` check at the top of `orchestrator_moves_own_record`, or in `main()`
before either judge runs, so that M7, M7b, M8, M8b and B20001 are denied as on the base. Add a test at 20000 and
20001 characters. The command that runs is still the same single move, so the practical impact is small.
It is classed blocking because the owner's ruling makes any deny-to-allow change for the same input a regression.
