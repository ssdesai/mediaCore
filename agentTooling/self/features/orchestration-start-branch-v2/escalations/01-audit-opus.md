Verdict: escalated

# Security audit — orchestration-start-branch-v2

Head: this branch's `HEAD`; base: `origin/main`. Both were extracted with `git archive` under
the scratch directory (`/tmp/plan-capture.ykpPzB/scratch/{head,base}`). Each copy was laid out
as a consuming repo `consumer/` (its own `git init`) with the tooling vendored at
`consumer/agentTooling/`. Two legacy records sat in `agentTooling/self/orchestrations/`: `mine`,
whose fence names session `S1`, and `other`, whose fence names `S2`. A standalone checkout
(`standalone/`, with a `.git` of its own) was also built.

The hook was run as `hook.py` does it: the PreToolUse JSON (`tool_name: Bash`, `session_id`,
`agent_id: null`, `cwd`, `tool_input.command`) on stdin, with `CLAUDE_PROJECT_DIR` set to the
copy and `AGENTTOOLING_PROFILE=cloud`. Every input below ran against the head copy and the base
copy with the same payload and the same file edits (`setup` and `teardown` in
`cases{1,2,3}.json`). `orchestration-start.sh` was attacked in fresh clones of a local bare
`origin.git`, seeded from each copy (`start.sh`, `start-all.sh`, `start2.sh`).

## Rules the diff adds or changes

1. **Hook, `orchestrator_record_move` / `orchestrator_moves_own_record`.** For an orchestrator
   session only, the hook now accepts `git mv <tooling>/self/orchestrations/<slug>
   plans/orchestrations/<slug>`, and approves it outright (`allow`) when it is alone on the line.
   The source must be the directory that holds the session's own record, in a vendored copy, run
   from the consuming repo's root, and the destination must not exist yet. Every other `git mv`
   stays on the allowlist's deny.
2. **Hook, `orchestrator_git_allowed` → `mv`.** The same check, as an allowlist entry. A line
   that holds the move together with other allowlisted commands goes on to the ordinary judges.
3. **`orchestration-start.sh --branch`, cloud profile.** It refuses `--branch` for a
   coordinator, under the local profile, for `main`, an invalid name, a branch that exists
   locally or on origin, a branch a feature manifest on `origin/main` names, a checkout whose
   commits are not on `origin/main`, a dirty checkout, and a launch from another branch. It also
   refuses an orchestrator start on a detached HEAD or on `main` without `--branch`. On base,
   every `--branch` is a usage error (exit 2).
4. **`held_feature` reads `ls-files -z`.** This can only refuse more.

## Inputs tried

Results: **allow** = `permissionDecision: allow`; **no output** = the hook says nothing and the
settings decide (no settings rule allows `git mv`, so this is a prompt); **deny** = the hook
denies. Session `S1` and cwd = the consumer root unless stated. `own` stands for
`agentTooling/self/orchestrations/mine` and `dst` for `plans/orchestrations/mine`.

### Hook — `git mv` (rules 1–2)

| id | input | head | base | note |
|---|---|---|---|---|
| M1 | `git mv own dst` | allow | deny | the intended shape |
| M2 | `git mv agentTooling/self/orchestrations/other plans/orchestrations/other` (S2's record) | deny | deny | |
| M3 | `git mv own plans/orchestrations/other` | deny | deny | |
| M4 | `git mv ./agentTooling/self/orchestrations/mine dst` | deny | deny | |
| M5 | `git mv own/ dst` | deny | deny | |
| M6 | `git mv -f own dst` | deny | deny | |
| M7 | `git mv -k own dst` | deny | deny | |
| M8 | `git mv -- own dst` | deny | deny | |
| M9 | `git mv own dst extra` | deny | deny | |
| M10 | `git -C . mv own dst` | deny | deny | |
| M11 | `GIT_DIR=x git mv own dst` | deny | deny | |
| M12 | `env git mv own dst` | deny | deny | |
| M13 | `/usr/bin/git mv own dst` | deny | deny | |
| M14 | `command git mv own dst` | deny | deny | |
| M15 | `nohup git mv own dst` | deny | deny | |
| M16 | `xargs git mv own dst` | deny | deny | |
| M17 | `sudo git mv own dst` | deny | deny | |
| M18 | `bash -c 'git mv own dst'` | deny | deny | |
| M19 | `echo git mv own dst \| sh` | deny | deny | |
| M20 | `find . -maxdepth 0 -exec git mv own dst ;` | deny | deny | |
| M21 | `exec -a git git mv own dst` | deny | deny | |
| M22 | `"git" "mv" "own" 'dst'` | allow | deny | same words as M1; not a finding |
| M23 | `git mv agentTooling/self/orchestrations/mi""ne plans/orchestrations/mi''ne` | allow | deny | same words as M1; not a finding |
| M24 | `git mv …/mi\ne dst` | deny | deny | |
| M25 | `git mv …/mi* dst` | deny | deny | |
| M26 | `git mv …/{mine,other} dst` | deny | deny | |
| M27 | `git mv …/$SLUG dst` | deny | deny | |
| M28 | `git mv own plans/orchestrations/$(echo mine)` | deny | deny | |
| M29 | `git mv own "$(git branch --show-current)"` | deny | deny | |
| M30 | `git mv own dst && git status` | deny (mixed line) | deny | |
| M31 | `git mv own dst; git push -u origin main` | deny (push rule) | deny | |
| M32 | `git mv own dst > /dev/null` | allow | deny | harmless redirect; not a finding |
| M33 | `git mv own dst 2>&1` | allow | deny | harmless redirect; not a finding |
| M34 | `git mv own dst > out.txt` | deny | deny | |
| M35 | `git mv own dst &` | deny | deny | |
| M36 | `git mv own dst` + newline + `git status` | deny | deny | |
| M37 | `git mv own dst # c` | deny | deny | |
| M38 | `git mv own dst <<'EOF' … EOF` | deny | deny | |
| M39 | `git mv own dst \| cat` | no output (prompt) | deny | the intended move, sent to the human rather than approved; not a finding |
| M40 | `(git mv own dst)` | deny | deny | |
| M41 | `git mv own dst \|\| git status` | deny (mixed line) | deny | |
| M42 | `git<TAB>mv  own   dst` | allow | deny | same words as M1; not a finding |
| M43 | `git mv agentTooling/self/orchestrations/../self/orchestrations/mine dst` | deny | deny | |
| M44 | `git mv own plans/orchestrations/../orchestrations/mine` | deny | deny | |
| M45 | `git mv own dst` as session S2 (orchestrator of `other`) | deny | deny | |
| M46 | `git mv own dst` as session S3 (no role) | no output | no output | not an orchestrator; the rule does not apply |
| M47 | `git mv self/orchestrations/mine ../plans/orchestrations/mine`, cwd `agentTooling/` | deny | deny | |
| M48 | `git mv own dst`, cwd `plans/` | deny | deny | |
| M49 | `git mv own dst`, cwd `<root>/` | allow | deny | same directory; not a finding |
| M50 | `git mv own dst`, cwd `null` | deny | deny | |
| M51 | `git mv own dst`, cwd `7` (not a string) | deny | deny | |
| M52 | `git mv own dst`, cwd `<root>/agentTooling/..` | allow | deny | same directory after realpath; not a finding |
| M53 | `git mv own dst`, `plans/orchestrations/mine/` already exists | deny | deny | |
| M54 | `git mv own dst`, `dst` a dangling symlink | deny | deny | |
| M55 | `git mv own dst`, a `.git` file planted in `agentTooling/` (now looks standalone) | deny | deny | |
| M56 | standalone checkout: `git mv self/orchestrations/mine plans/orchestrations/mine` | deny | deny | |
| M57 | standalone checkout: `git mv self/orchestrations/mine ../plans/orchestrations/mine` | deny | deny | |
| M58 | `git mv own dst`, `own` a symlink to a real directory | deny | deny | |
| M59 | `git mv own dst`, `plans` → symlink to `<root>/.git` (no `.git/orchestrations`) | allow | deny | **finding**, same root cause as M66 (git itself fails here: ENOENT) |
| M60 | as S9: a planted `aaa` record whose second fence names S9; `git mv own dst` | deny | deny | |
| M61 | S1 named by a second fence in a planted `aaa` record (first fence S2); `git mv …/aaa plans/orchestrations/aaa` | allow | deny | the hook's own role lookup resolves S1 to `aaa` on both heads ("orchestrator of `aaa`"), so `aaa` IS the session's record under the rule's contract; not a finding |
| M62 | same `aaa` planted; `git mv own dst` (`mine` is no longer the first record) | deny | deny | |
| M63 | `mine/README.md` deleted, S1 recorded in `plans/orchestrations/zzz`; `git mv own dst` | deny | deny | |
| M64 | `mine` record edited to `kind: coordinator` in the tree (the committed version still makes S1 the orchestrator) | allow | deny | the role still comes from the committed record; not a finding |
| M65 | `git mv own dst`, `plans` → symlink to a directory OUTSIDE the repo holding `orchestrations/` | allow | deny | **finding** |
| M66 | `git mv own dst`, `plans/orchestrations` → symlink to a directory OUTSIDE the repo | allow | deny | **finding** |
| M67 | `git add plans/keep \| cat` (control) | no output | no output | |
| M68 | as S7, recorded only in the ledger (`S7 mine` in `.git/agenttooling-orchestrators`, README removed) | allow | deny | own record by ledger; not a finding |
| M69 | `mine/README.md` a symlink to a file outside the records folder | deny | deny | |
| M70 | `mine/README.md` → symlink to `../other/R2` (holding S1's fence); `git mv own dst` | deny | deny | |
| M71 | same symlink as M70; `git mv agentTooling/self/orchestrations/other plans/orchestrations/other` | allow | deny | **finding**: moves S2's record directory |
| M72 | `git mv own dst`, `plans` → symlink to `.git`, `.git/orchestrations/` present | allow | deny | **finding**, same root cause as M66 |
| M73 | `git mv own dst`, a symlink to `/etc/passwd` inside `mine/sub/` | allow | deny | moving a symlink moves the link, not its target; not a finding |

Git's own behaviour for M65 and M66 (`m59b.sh`): with `plans` a symlink to an outside directory
that holds `orchestrations/`, `git mv agentTooling/self/orchestrations/mine
plans/orchestrations/mine` exits 0 and the record directory lands OUTSIDE the repository
(`/tmp/plan-capture.ykpPzB/scratch/outside/orchestrations/mine`). Git does not refuse a
destination behind a symlinked parent here, so the hook's `allow` is the only check.

### `orchestration-start.sh` (rules 3–4)

The result is the exit code plus what was written. On base, every `--branch` input exits 2 with
usage and writes nothing.

| id | input (cloud unless stated) | head | base | note |
|---|---|---|---|---|
| b01 | detached, `--branch claude/b01` | goes on: cut, commit, push claude/b01 | usage (2) | the intended path |
| b02 | detached, `--branch main` | refused | usage | |
| b03 | detached, no local main, `--branch refs/heads/main` | goes on: creates `refs/heads/refs/heads/main`, pushes it as that name; origin `main` untouched | usage | a distinct ref; nothing that exists is written; not a finding |
| b04 | local `main` ahead of origin, `--branch refs/heads/main` | goes on: local ref `refs/heads/refs/heads/main`; the push fails (ambiguous src); origin `main` untouched | usage | not a finding |
| b05 | `--branch heads/main` | goes on: ref `heads/main`; the push fails (ambiguous); origin `main` untouched | usage | not a finding |
| b06 | `--branch origin/main` | goes on: pushes a new `refs/heads/origin/main`; origin `main` untouched | usage | not a finding |
| b07 | `--branch -foo` | refused | usage | |
| b08 | `--branch @{-1}` | refused (`checkout -b` fails, nothing written) | usage | |
| b09 | `--branch HEAD` | refused | usage | |
| b10 | `claude/taken` exists on origin, `--branch claude/taken` | refused | usage | |
| b11 | same, `--branch refs/heads/claude/taken` | goes on: creates and pushes `refs/heads/refs/heads/claude/taken`; `claude/taken` untouched | usage | a distinct ref, not the existing branch; not a finding |
| b12 | same, `--branch heads/claude/taken` | goes on: `refs/heads/heads/claude/taken`; `claude/taken` untouched | usage | not a finding |
| b13 | on `main`, `--branch main` | refused | usage | |
| b14 | on `feature-x`, `--branch claude/b14` | refused | usage | |
| b15 | on `feature-x`, `--branch feature-x` | goes on: commits the record on feature-x and pushes it | usage | documented ("the branch this session is on"); not a finding |
| b16 | dirty checkout, `--branch claude/b16` | refused | usage | |
| b17 | local `main` ahead of origin, HEAD detached at `origin/main`, `--branch claude/b17` | goes on (HEAD carries nothing that origin/main lacks) | usage | correct; not a finding |
| b18 | `--branch ''` | refused | usage | |
| b19 | `--coordinator --branch claude/b19` | refused | usage | |
| b20 | detached, no `--branch` | refused | goes on (writes the record) | stricter than base |
| b21 | on `main`, no `--branch` | refused | goes on | stricter than base |
| b22 | `--branch refs/remotes/origin/main` | goes on: local ref only; push fails (ambiguous); origin untouched | usage | not a finding |
| b23 | no local main, `--branch Main` | goes on: pushes `Main` | usage | a different branch on a case-sensitive remote; not a finding |
| b24 | `--branch claude/b24 --branch main` | refused (the last one wins) | usage | |
| c01 | a feature manifest on origin/main names `claude/feat`; `--branch claude/feat` | refused | usage | |
| c02 | the same, from a manifest at `plans/features/fé tab/` (non-ASCII and space) | refused | usage | the `-z` reads hold |
| c03 | `AGENTTOOLING_PROFILE=local`, `--branch claude/c03` | refused | usage | |
| c04 | `AGENTTOOLING_PROFILE=bogus`, `--branch` | refused | usage | |
| c05 | origin unreachable (`ls-remote` exits 128), `--branch claude/c05` | refused | usage | |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | M66: `git mv agentTooling/self/orchestrations/mine plans/orchestrations/mine` as S1 from the consumer root, with `plans/orchestrations` a symlink to a directory outside the repo | allow (approved outright; git moves the record directory outside the repository) | deny (orchestrator allowlist) | `python3 /tmp/plan-capture.ykpPzB/scratch/hook.py /tmp/plan-capture.ykpPzB/scratch/cases2.json` (M66) on head/consumer and base/consumer; git's effect: `bash /tmp/plan-capture.ykpPzB/scratch/m59b.sh` |
| blocking | M65: the same command, with `plans` a symlink to an outside directory that holds `orchestrations/` | allow | deny | `hook.py cases3.json` (M65) on both copies |
| blocking | M72 / M59: the same command, with `plans` a symlink to `<root>/.git` | allow | deny | `hook.py cases3.json` (M72) and `hook.py cases1.json` (M59) on both copies |
| blocking | M71: `git mv agentTooling/self/orchestrations/other plans/orchestrations/other` as S1, with `self/orchestrations/mine/README.md` a symlink to `../other/R2` (a file holding S1's fence) — moves S2's record directory, though the hook names S1 the orchestrator of `mine` | allow | deny | `hook.py cases2.json` (M71) on both copies |

## Non-blocking findings

None.

## Blocking findings — reproduction and fix

All four are regressions: on base, the orchestrator allowlist denies every `git mv`. On head,
`orchestrator_record_move` approves these moves outright. The plan's rule makes each one
blocking.

### 1. Destination behind a symlinked parent (M65, M66, M72, M59)

**Reproduce.** In a vendored layout, make `plans` or `plans/orchestrations` a symlink, either to
a directory outside the repo or to `.git`. Then send, as the orchestrator of `mine` with cwd at
the consumer root:

```
git mv agentTooling/self/orchestrations/mine plans/orchestrations/mine
```

The hook answers `allow` (`ORCHESTRATOR_MOVE_REASON`). Git follows the symlink and moves the
record directory to `<target>/orchestrations/mine` (or `<target>/mine`). That is a write outside
the project root, approved with no prompt. `orchestrator_record_move` checks only
`os.path.lexists(consumer/destination)`, never the parents of the destination.

**What the rule should do.** Approve only when the destination's parent resolves to where it
claims to be, for example
`os.path.realpath(os.path.join(consumer, ORCHESTRATIONS_CONSUMER_REL)) == os.path.join(consumer,
*ORCHESTRATIONS_CONSUMER_REL.split("/"))`. That means no symlink at `plans` or
`plans/orchestrations` (and `plans/orchestrations` may be absent only if `plans` itself is a real
directory). Otherwise deny, or at most leave the line to the human.

### 2. A symlinked record file names another session's directory (M71)

**Reproduce.** Make S1's working-tree record `self/orchestrations/mine/README.md` a symlink to a
file under `self/orchestrations/other/` that holds S1's fence. `record_for_session` returns
`…/mine/README.md`, and the hook's role reason names `mine`. But `orchestrator_record_move`
takes `os.path.dirname(os.path.realpath(record))`, which is `…/other`. So it approves

```
git mv agentTooling/self/orchestrations/other plans/orchestrations/other
```

which moves S2's record directory, a record that is not the one the role lookup found.

**What the rule should do.** Derive the slug from the record path the role lookup returned
without resolving symlinks: `os.path.dirname(os.path.abspath(record))`. Refuse when the record
file or any of its parents is a symlink (`os.path.islink(record)`, or `realpath(record) !=
abspath(record)`). Then the directory that is moved is always the one that holds the record
that names the session.
