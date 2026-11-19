Verdict: clean

# Security audit: orchestration-records-in-repo

Base `origin/main`, attacked on a `git archive HEAD` copy vendored as `agentTooling/` inside
throwaway consumer git repos under the pass's scratch directory. The hook was run with crafted
PreToolUse payloads (`tool_name: Bash`, `session_id`, `agent_id`, `cwd`, `tool_input.command`),
with `CLAUDE_PROJECT_DIR` set to the consumer copy and `AGENTTOOLING_PROFILE=cloud`. The
orchestrator session `S-orch-1` is named by a committed record at
`plans/orchestrations/demo/README.md`. Unless a row says otherwise, there is **no ledger
line**: that simulates a fresh clone or a cloud container where only the committed history
can still name the role. Nothing in the checkout was edited apart from this report.

## Rules the diff adds or changes

| # | Rule | Applies to |
|---|---|---|
| R1 | `hooks/orchestrator_role.py` `record_roots`/`record_bases`: a record under the consuming repo's `plans/orchestrations/<slug>/README.md` gives a session the orchestrator role, in all three sources (working tree, history as first committed, ledger). The root is read only when the tooling directory has no `.git` of its own. | Every session, Bash and Agent |
| R2 | `hooks/allow-repo-commands.sh` `orchestrator_tool_allowed`: `--self` is admitted once, as the first argument only, before `--orchestration` for `analysis/manifest.py` and `analysis/report.py`. | Orchestrator sessions |
| R3 | `hooks/wire-settings.py` `POLICY_ASK_RULES`: `Edit(**/plans/orchestrations/**)` is an ask rule. | Edit/Write in a consuming repo |

## Inputs tried

Key: **deny (role)** means denied with the orchestrator-role allowlist reason. **deny
(unreadable)** means denied with the fail-closed ledger-unreadable reason. **asked** means
the hook printed nothing, so the call goes on to the later judges and then to the human.
**allow** means the hook approved it.

### R1: role detection over `plans/orchestrations`

| Input / state | Result | Expected |
|---|---|---|
| baseline: committed record, `./agentTooling/run-plans.sh demo` | deny (role) | deny |
| baseline, a different session runs the same | asked | not role-denied |
| record deleted from the working tree (history only) | deny (role) | deny |
| record never committed, then deleted; ledger line only | deny (role) | deny |
| working-tree record edited to `kind: coordinator` | deny (role) | deny |
| a shadow fence appended naming another session | deny (role) | deny |
| `agentTooling/.git` = dangling symlink, build / `rm -rf x` | deny (role) / deny (role) | deny |
| `agentTooling/.git` = empty file, build / `rm -rf x` | deny (unreadable) / asked | deny (fail-closed, documented: build-only) |
| `agentTooling/.git` = empty dir, build / `rm -rf x` | deny (unreadable) / asked | as above |
| `agentTooling/.git` = `gitdir: <repo>/.git` + ledger line, build / `rm -rf x` | deny (role) / deny (role) | deny |
| `agentTooling/.git` = `gitdir: <repo>/.git`, no ledger, build / `rm -rf x` | **asked / asked** | see Observation 1 |
| `agentTooling/.git` = `gitdir: ../.git`, no ledger | **asked / asked** | see Observation 1 |
| `agentTooling/.git` = dir holding only `HEAD`, no ledger | **asked / asked** | see Observation 1 |
| `agentTooling/.git` = symlink to `<repo>/.git`, no ledger | **asked / asked** | see Observation 1 |
| `agentTooling/.git` = a full `git init`, no ledger | **asked / asked** | see Observation 1 |
| payload with `session_id` missing, build | asked | no session means no role (unchanged) |

Can anyone plant `agentTooling/.git`? Each command was run as the orchestrator and as an
ordinary session:

| Command | Orchestrator | Other session |
|---|---|---|
| `mkdir agentTooling/.git` | deny (role) | asked |
| `touch agentTooling/.git` | deny (role) | asked |
| `git init agentTooling` / `git init -q agentTooling` / `git -C agentTooling init` | deny (role) | asked |
| `git worktree add agentTooling/x` | deny (role) | deny |
| `git submodule add ./x agentTooling` | deny (role) | asked |
| `ln -s <repo>/.git agentTooling/.git` | deny (role) | asked |
| `cp -r .git agentTooling/.git` | deny (role) | asked |
| Write/Edit tool on `agentTooling/.git` or `agentTooling/.git/HEAD` | covered by `Edit(**/.git)` / `Edit(**/.git/**)` deny rules; `wire-settings.py --write` was run in the copy and both land in the consumer's `.claude/settings.json` | deny |
| `python3 …/manifest.py --self --orchestration demo set-feature … session=x` | asked | asked |
| `./agentTooling/orchestration-start.sh --self other` | asked | asked |
| `./agentTooling/orchestration-start.sh --self other --session x` | deny (role) | asked |
| `./agentTooling/orchestration-start.sh other --coordinator` | asked | asked |

### R2: `--self` in the orchestrator allowlist (all as the orchestrator, cwd = consumer root)

`M` = `agentTooling/analysis/manifest.py`, `R` = `agentTooling/analysis/report.py`, `C` = `agentTooling/analysis/capture_planning.py`.

| Command | Result | Expected |
|---|---|---|
| `python3 M --self --orchestration get demo` | asked | on the allowlist |
| `python3 -B M --self --orchestration list` | asked | on the allowlist |
| `python3 M --orchestration get demo` | asked | on the allowlist |
| `python3 M "--self" --orchestration get demo`, `python3 M --se""lf --orchestration get demo` | asked | the same word after quote removal |
| `python3 M --self` | deny (role) | deny |
| `python3 M --self --self --orchestration get demo` | deny (role) | deny |
| `python3 M --self get demo` (feature-manifest scope) | deny (role) | deny |
| `python3 M --self=1 --orchestration …` / `--SELF` / `--se\lf` | deny (role) | deny |
| `python3 --self M --orchestration get demo` | deny (role) | deny |
| `python3 R --self --orchestration demo` | allow | on the allowlist |
| `python3 R --self --orchestration demo --checkout /tmp/x` | asked | on the allowlist |
| `python3 R --self --orchestration ../demo` | deny (role) | deny |
| `python3 R --self --orchestration demo --self` | deny (role) | deny |
| `python3 R --self --self --orchestration demo` | deny (role) | deny |
| `python3 R --self --orchestration` / `python3 R --self demo` | deny (role) | deny |
| `python3 C --self --list-sessions` | allow | unchanged rule (`--self` not stripped there) |
| `python3 agentTooling/run-plans.sh --self demo` | deny (role) | deny |
| `python3 agentTooling/analysis/roots.py --self --orchestration x` | deny (role) | deny |
| `python3 agentTooling/analysis/coordinator_check.py --self --orchestration x` | deny (role) | deny |
| `python3 M --self --orchestration get demo; ./agentTooling/run-plans.sh demo` | deny (role) | deny |
| `… && bash -c x` / `… \| sh` | deny (role) | deny |
| `env python3 M …`, `/usr/bin/env python3 M …`, `command python3 M …`, `nohup …`, `sudo …`, `exec -a x python3 M …` | deny (role) | deny |
| `echo M \| xargs python3` | deny (role) | deny |
| `find . -name manifest.py -exec python3 {} --self --orchestration get demo \;` | deny (role) | deny |
| `bash -c 'python3 M --self --orchestration get demo'` | deny (role) | deny |
| `X=1 python3 M …`, `PYTHONPATH=/tmp python3 M …` | deny (role) | deny |
| `python3 $M --self --orchestration get demo` | deny (role) | deny |
| `python3 agentTooling/analysis/manif*.py --self …` | deny (role) | deny |
| `python3 agentTooling/analysis/{manifest,report}.py --self …` | deny (role) | deny |
| `python3 M --self --orchestration get demo > /tmp/out` | deny (role) | deny |
| `python3 M --self --orchestration get demo <<'EOF'` … heredoc | deny (role) | deny |
| `python3 ./agentTooling/../agentTooling/analysis/manifest.py --self …` | deny (`..` shape) | deny |
| `python3 M --self --orchestration get $(./agentTooling/run-plans.sh demo)` | deny (role) | deny |
| `` python3 M --self --orchestration get `./agentTooling/run-plans.sh demo` `` | deny (role) | deny |
| `python3 m.py --self …` where `m.py` is a symlink to `M` | deny (role) | deny |
| `python3 copy_manifest.py --self …` (a copy of `M`) | deny (role) | deny |
| payload `cwd` = null, `python3 M --self --orchestration get demo` | deny (role) | deny |
| payload `cwd` = `/`, same command | deny (role) | deny |

`manifest.py`'s own dispatch matches the hook. `main()` hands `argv[1:3] ==
["--self", "--orchestration"]` to `orchestration_main`, so an admitted `--self` can never
reach the feature-manifest subcommands. Those stay denied: `python3 M --self get demo` above.

### R3: the Edit ask rule

`hooks/wire-settings.py --repo <consumer copy> --write` writes both
`Edit(**/agentTooling/self/orchestrations/**)` and `Edit(**/plans/orchestrations/**)` into
`.claude/settings.json`, beside the `Edit(/.git/**)`, `Edit(**/.git/**)` and `Edit(**/.git)`
denies. Claude Code's own glob matching cannot be run in this container, so the rule's match
against a record's path was not exercised end to end.

## Bypasses

None. Every input that one of these rules exists to deny was denied, or was handed to the
human because it is a write.

## Observations (not bypasses)

1. **One file presence drops a whole root.** `record_bases` reads the consuming repo's
   `plans/orchestrations` only when `agentTooling/.git` does not exist. If a resolvable `.git`
   is planted there (a `gitdir:` file pointing at the repo's own git dir, a dir holding only
   `HEAD`, a symlink, or a nested `git init`), the role is gone from all three sources.
   That includes the committed-history source, which a working-tree edit cannot defeat. The
   session then gets no allowlist and no build-script deny, unless this machine's ledger
   still names it.
   - Why this is not a bypass: neither the orchestrator nor any other session can plant the
     file without the human. The orchestrator's Bash is denied by the allowlist. Every
     other session's write goes to the human, or is denied (`git worktree add`). The Write
     and Edit tools are denied by `Edit(**/.git)` and `Edit(**/.git/**)`.
   - A possible hardening: decide "standalone" the way `orchestration-start.sh` and
     `roots.py` must agree on it, but only when `.git` resolves to a checkout whose top level
     is the tooling directory itself. Or keep the consumer root whenever the parent directory
     is a git work tree. Either makes a planted marker a no-op.
   - Untested: a case-insensitive filesystem (macOS) where `.GIT` might satisfy
     `os.path.exists` while slipping past a case-sensitive `Edit(**/.git)` glob. This
     container could not check it.
2. **An empty planted `.git` (file or directory) downgrades the role.** It makes the record
   unreadable (`LEDGER_UNREADABLE`): only building is refused, and the allowlist is lost,
   so `rm -rf x` is asked rather than denied. This is the documented fail-closed behaviour
   for an unresolvable `.git`, and planting it needs the same human-approved write as in
   Observation 1.
3. **No root-anchored form of the new ask rule.** `Edit(**/plans/orchestrations/**)` has no
   `Edit(/plans/orchestrations/**)` beside it, unlike the `.git` and `.claude` denies.
   This is consistent with the other consumer ask rules, which also have none. If `**/`
   ever failed to match the project root, the record would be unprotected against a direct
   Edit, though the committed history would still hold the role.
