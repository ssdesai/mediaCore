Verdict: escalated

# Security audit (round 2): orchestration-start-branch-v2

Head is this branch's `HEAD` and base is `origin/main`. Both trees were extracted with `git archive` into
`/tmp/plan-capture.arUdwf/scratch/{head,base}` by `build.sh`. Each copy was laid out as a consuming repo
(`consumer/`, its own `git init`, everything committed) with the tooling vendored at `consumer/agentTooling/`.
It holds two legacy records in `agentTooling/self/orchestrations/`: `mine`, whose fence names session `S1`, and
`other`, whose fence names `S2`.

The hook was run as Claude Code runs it. `hook.py` sends the PreToolUse JSON (`tool_name: Bash`, `session_id`,
`agent_id: null`, `cwd`, `tool_input.command`) on stdin, with `CLAUDE_PROJECT_DIR` set to a fresh copy of the
template and `AGENTTOOLING_PROFILE=cloud`. Every input ran against head and base with the same payload and the
same setup edits (`cases1.json`, `cases2.json`).

`orchestration-start.sh` was run by `start.sh` / `start-all.sh` in a clone of a local bare `origin.git` seeded
from each tree. After the clone, somebody else pushed commit `B` to origin's `main`, so the clone's local `main`
is stale. The clone then runs from a detached HEAD at `origin/main`, under `AGENTTOOLING_PROFILE=cloud`, with
`--self`.

## Rules the diff adds or changes

1. **Hook, `orchestrator_moves_own_record` (outright `allow`).** Applies to an orchestrator session only. It
   approves `git mv <tooling>/self/orchestrations/<slug> plans/orchestrations/<slug>`, alone or after exactly
   `mkdir -p plans/orchestrations && `. Every condition must hold:
   - the line runs from the consuming repo's root, in a vendored copy;
   - the source is the directory that holds the record the role lookup returned for this session;
   - that record path contains no symlink;
   - `plans` and `plans/orchestrations` contain no symlink;
   - the destination does not exist yet.
2. **Hook, `orchestrator_git_allowed` → `mv`.** The same check, used as an allowlist entry inside a mixed line.
   Such a line then goes on to the ordinary judges.
3. **`shared_rules.LEGACY_RECORD_MOVE`.** The remedy text now carries the `mkdir -p` lead. It is text only, and
   rule 1 matches it.
4. **`orchestration-start.sh --branch`, cloud profile.** This is a lifecycle-script refusal. The script refuses:
   - a coordinator record, the local profile, `main`, or an invalid ref name;
   - a branch that exists locally or on origin (asked with `ls-remote`);
   - a branch that a feature manifest on `origin/main` names;
   - commits not on `origin/main`, or a dirty checkout;
   - a launch from another branch;
   - no `--branch` at all on a detached HEAD or on `main`.

   When none of these refuses, it cuts the branch, commits the record and **pushes the branch with
   `git push -u origin <name>`**. On base, every `--branch` is a usage error (exit 2).
5. **`held_feature` reads `ls-files -z`.** This can only refuse more.

## Inputs tried

Results:

- **allow** means the hook returned `permissionDecision: allow`.
- **no output** means the settings decide. No rule allows `git mv`, so that is a prompt.
- **deny** means the hook denied the input.

Unless a row says otherwise, the session is `S1` and cwd is the consumer root. `OWN` is
`agentTooling/self/orchestrations/mine`, `DST` is `plans/orchestrations/mine` and `outside` is a directory
outside the repo.

### Hook: `git mv` (rules 1–3)

| id | input / setup | head | base | note |
|---|---|---|---|---|
| M1 | `git mv OWN DST` (`plans/orchestrations` present), executed | allow; record lands at `plans/orchestrations/mine` | deny | the intended shape |
| M1b | `git mv OWN DST` | allow | deny | the intended shape |
| K1 | `mkdir -p plans/orchestrations && git mv OWN DST`, executed | allow; moved | deny | the intended shape |
| M2 | `git mv agentTooling/self/orchestrations/other plans/orchestrations/other` (S2's record) | deny | deny | |
| M3 | `git mv OWN plans/orchestrations/other` | deny | deny | |
| M4 | `git mv ./OWN DST` | deny | deny | |
| M5 | `git mv OWN/ DST` | deny | deny | |
| M6 | `git mv -f OWN DST` | deny | deny | |
| M7 | `git mv -k OWN DST` | deny | deny | |
| M8 | `git mv -- OWN DST` | deny | deny | |
| M9 | `git mv OWN DST extra` | deny | deny | |
| M10 | `git -C . mv OWN DST` | deny | deny | |
| M10b | `git -c core.fsmonitor=touch mv OWN DST` | deny | deny | |
| M11 | `GIT_DIR=x git mv OWN DST` | deny | deny | |
| M12 | `env git mv OWN DST` | deny | deny | |
| M12b | `env env git mv OWN DST` | deny | deny | |
| M13 | `/usr/bin/git mv OWN DST` | deny | deny | |
| M14 | `command git mv OWN DST` | deny | deny | |
| M15 | `nohup git mv OWN DST` | deny | deny | |
| M16 | `xargs git mv OWN DST` | deny | deny | |
| M17 | `sudo git mv OWN DST` | deny | deny | |
| M18 | `bash -c 'git mv OWN DST'` | deny | deny | |
| M19 | `echo git mv OWN DST \| sh` | deny | deny | |
| M20 | `find . -maxdepth 0 -exec git mv OWN DST ;` | deny | deny | |
| M21 | `exec -a git git mv OWN DST` | deny | deny | |
| M22 | `"git" "mv" "OWN" 'DST'` | allow | deny | the same words as M1; not a finding |
| M23 | `git mv …/mi""ne plans/orchestrations/mi''ne` | allow | deny | the same words as M1; not a finding |
| M24 | `git mv …/mi\ne DST` | deny | deny | |
| M25 | `git mv …/mi* DST` | deny | deny | |
| M26 | `git mv …/{mine,other} DST` | deny | deny | |
| M27 | `git mv …/$SLUG DST` | deny | deny | |
| M28 | `git mv OWN plans/orchestrations/$(echo mine)` | deny | deny | |
| M29 | `git mv OWN "$(git branch --show-current)"` | deny | deny | |
| M30 | `git mv OWN DST && git status` | deny (mixed line) | deny | |
| M31 | `git mv OWN DST; git push -u origin main` | deny | deny | |
| M32 | `git mv OWN DST > /dev/null` | allow | deny | harmless redirect; not a finding |
| M33 | `git mv OWN DST 2>&1` | allow | deny | harmless redirect; not a finding |
| M34 | `git mv OWN DST > out.txt` | deny | deny | |
| M35 | `git mv OWN DST &` | deny | deny | |
| M36 | `git mv OWN DST` + newline + `git status` | deny | deny | |
| M37 | `git mv OWN DST # c` | deny | deny | |
| M38 | `git mv OWN DST <<'EOF' … EOF` | deny | deny | |
| M39 | `git mv OWN DST \| cat` | no output (prompt) | deny | the intended move, handed to the human instead of approved; not a finding |
| M40 | `(git mv OWN DST)` | deny | deny | |
| M41 | `git mv OWN DST \|\| git status` | deny (mixed line) | deny | |
| M42 | `git<TAB>mv  OWN   DST` | allow | deny | the same words as M1; not a finding |
| M43 | `git mv …/../self/orchestrations/mine DST` | deny | deny | |
| M44 | `git mv OWN plans/orchestrations/../orchestrations/mine` | deny | deny | |
| M45 | `git mv OWN DST` as S2 | deny | deny | |
| M46 | `git mv OWN DST` as S3 (no role) | no output | no output | not an orchestrator |
| M47 | `git mv self/orchestrations/mine ../plans/orchestrations/mine`, cwd `agentTooling/` | deny | deny | |
| M48 | `git mv OWN DST`, cwd `plans/` | deny | deny | |
| M49 | `git mv OWN DST`, cwd `<root>/` | allow | deny | the same directory; not a finding |
| M50 | `git mv OWN DST`, cwd `null` | deny | deny | |
| M51 | `git mv OWN DST`, cwd `7` | deny | deny | |
| M52 | `git mv OWN DST`, cwd `<root>/agentTooling/..` | allow | deny | the same directory; not a finding |
| M53 | `DST` already exists | deny | deny | |
| M54 | `DST` a dangling symlink | deny | deny | |
| M55 | a `.git` file planted in `agentTooling/` (looks standalone) | deny | deny | |
| M58 | `OWN` a symlink to a real directory | deny | deny | |
| M59 | `plans` → symlink to `<root>/.git` | deny | deny | round 1's blocking finding, fixed |
| M65 | `plans` → symlink to `outside` (holding `orchestrations/`) | deny | deny | round 1's blocking finding, fixed |
| M65k | the same, with the `mkdir -p` lead | deny | deny | |
| M66 | `plans/orchestrations` → symlink to `outside/orchestrations` | deny | deny | round 1's blocking finding, fixed |
| M66k | the same, with the `mkdir -p` lead | deny | deny | |
| M66d | `plans` → a dangling symlink outside, with the `mkdir -p` lead (mkdir would create it outside) | deny | deny | |
| M70 | `mine/README.md` → symlink to `../other/R2` (holding S1's fence); `git mv OWN DST` | deny | deny | |
| M71 | the same symlink; `git mv …/other plans/orchestrations/other` | deny | deny | round 1's blocking finding, fixed |
| M71b | the working tree has only `other/`, whose README names S1; `git mv …/other plans/orchestrations/other` | allow | deny | both trees' role lookup names S1 the orchestrator of `other`, so this is its own record; not a finding |
| M72 | `plans` → symlink to `.git`, with `.git/orchestrations/` present | deny | deny | round 1's blocking finding, fixed |
| M74 | `agentTooling/self` → symlink to a directory outside | deny | deny | |
| M75 | `plans/orchestrations/x` → symlink to outside (a sibling of the destination) | allow | deny | the destination `mine` is a real path inside the repo; not a finding |
| K2 | `mkdir -p plans/orchestrations && git mv OWN plans/orchestrations/other` | deny | deny | |
| K3 | `mkdir -p plans/orchestrations && rm -rf plans` | deny | deny | |
| K4 | the lead plus the move, with `plans` a regular file | allow | deny | mkdir fails and `&&` stops; nothing is written; not a finding |
| K5 | the lead with two spaces before `&&` | deny | deny | |
| K6 | the lead twice, then the move | deny | deny | |
| K7 | the lead plus the move `> /dev/null` | allow | deny | harmless redirect; not a finding |
| K8 | `mkdir -p plans/orchestrations > /dev/null && git mv OWN DST` | deny | deny | |
| K9 | `mkdir -p plans/orchestrations/evil && git mv OWN DST` | deny | deny | |
| K9b | `mkdir -p plans/orchestrations/../../../x && git mv OWN DST` | deny | deny | |
| K10 | the lead plus the move, cwd `agentTooling/` | deny | deny | |
| K11 | the lead plus the move, `plans` → symlink to `.git/x` | deny | deny | |
| K12 | `mkdir -p plans/orchestrations ; git mv OWN DST` | deny | deny | |
| K13 | `mkdir -p plans/orchestrations \|\| git mv OWN DST` | deny | deny | |
| K14 | the lead plus the move plus a trailing `&&` | deny | deny | |
| K15 | `mkdir -p plans/orchestrations` alone | deny | deny | |
| K16 | `git mv OWN DST`, cwd `.` (hook process at the root) | allow | deny | the same directory; not a finding |
| K17 | the lead plus `"git" mv OWN DST` | allow | deny | the same words; not a finding |
| K18 | `mkdir<TAB>-p …` lead | deny | deny | |
| K19 | `git mv OWN DST\r` | allow | deny | `str.strip()` drops the `\r`. Bash moves to `plans/orchestrations/mine\r`, a path inside the repo; not a finding |
| K20 | the lead plus the move `\| sh` | deny | deny | |
| K21 | the lead plus the move `; rm -rf x` | deny | deny | |
| K22 | the lead plus the move `&` | deny | deny | |
| K23 | the lead plus the move `# x` | deny | deny | |
| K24 | a record dir `Mine` (fails the slug pattern) holding S1's record | deny | deny | |
| K25 | `plans` → symlink to `plans2` inside the repo | deny | deny | stricter than needed; harmless |
| K26 | cwd a symlink (outside the root) that points to the consumer root | allow | deny | git runs in the consumer root; not a finding |
| K27 | the working tree's `mine/README.md` rewritten (S1) and untracked | allow | deny | own record; not a finding |
| K28 | `mine/escape` → symlink to outside; lead plus the move, executed | allow; the link moves, the target is untouched | deny | not a finding |
| K29 | `DST` a symlink to an outside path | deny | deny | |
| K30 | `agentTooling/self/orchestrations` → symlink to outside | deny | deny | |
| K31 | `mine/README.md` deleted from the tree and index; the role comes from the committed record | allow | deny | own record by history; not a finding |
| K32 | S1 also written into `.git/agenttooling-orchestrators` | allow | deny | own record; not a finding |

### `orchestration-start.sh` (rule 4)

Every row runs from a detached HEAD at `origin/main` with a stale local `main` (origin has commit `B` that local
`main` lacks), unless a row says otherwise. On base, every `--branch` input exits 2 with usage and writes
nothing.

| id | input (cloud unless stated) | head | base | note |
|---|---|---|---|---|
| b01 | `--branch claude/b01` | goes on: cut, commit, push `claude/b01`; origin `main` untouched | usage (2) | the intended path |
| b02 | `--branch main` | refused | usage | |
| b07 | `--branch -foo` | refused | usage | |
| b09 | `--branch HEAD` | refused | usage | |
| b18 | `--branch ''` | refused | usage | |
| b19 | `--coordinator --branch claude/b19` | refused | usage | |
| b20 | no `--branch`, detached | refused | goes on (record written) | stricter than base |
| b21 | no `--branch`, on `main` | refused | goes on | stricter than base |
| b13 | on `main`, `--branch main` | refused | usage | |
| b14 | on `feature-x`, `--branch claude/b14` | refused | usage | |
| b16 | dirty checkout | refused | usage | |
| b10 | `claude/taken` exists on origin | refused | usage | |
| c03 | `AGENTTOOLING_PROFILE=local` | refused | usage | |
| c05 | origin unreachable (ls-remote exit 128) | refused | usage | |
| p5 | `--branch main.lock` | refused | usage | |
| p6 | `--branch claude/p6:main` | refused | usage | |
| p4 | `--branch +claude/p4` (no local `claude/p4`) | goes on: branch `+claude/p4` and its commit are created; the push fails (`src refspec claude/p4 does not match`) | usage | the push is read as a force refspec; it fails here only because no such local branch exists |
| **p1** | `--branch +main` | **goes on, exit 0: the push is `git push -u origin +main`, a FORCE push of the stale local `main` onto origin's `main`. Origin `main` goes from `B A` to `A`, and commit B is lost** | usage | **blocking** |
| **p2** | `--branch +refs/heads/main` | **goes on, exit 0: the same force push; origin `main` `B A` → `A`** | usage | **blocking** |
| **p3** | `--branch +main`, with an unreviewed commit on the local `main` | **goes on, exit 0: origin `main` `B A` → `local-unreviewed A`. The local commit lands on `main` with no PR, and B is lost** | usage | **blocking** |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | `orchestration-start.sh --self t --session s --branch +main` (cloud profile, detached HEAD at `origin/main`, stale local `main`) | goes on (exit 0): cuts `+main`, commits, then `git push -u origin +main` force-pushes local `main` over origin's `main`, deleting origin's newer commit | refused (usage, exit 2), nothing written | `bash /tmp/plan-capture.arUdwf/scratch/start.sh head p1 --branch +main` versus `… start.sh base p1 --branch +main` |
| blocking | the same with `--branch +refs/heads/main` | goes on (exit 0); origin `main` force-rewound | refused (usage, exit 2) | `start-all.sh` rows `[head p2]` / `[base p2]` |
| blocking | the same with `--branch +main` and an unreviewed commit on local `main` | goes on (exit 0); origin `main` force-set to the unreviewed local commit | refused (usage, exit 2) | `start-all.sh` rows `[head p3]` / `[base p3]` |

## Non-blocking findings

None. Every other input that differs between head and base is either stricter on head or is the documented move
of the session's own record into an in-repo destination. The rows above note each one as "not a finding".

## Blocking findings: reproduction and fix

### 1. A `--branch` name beginning with `+` becomes a force-push refspec (p1, p2, p3)

**Reproduce.** Set up a cloud container (`AGENTTOOLING_PROFILE=cloud`) whose local `main` differs from
`origin/main`. This is the normal state after anyone merges to `main` once the container has cloned. Start from a
detached HEAD at `origin/main`, then run:

```
./orchestration-start.sh --self t --session s --branch +main
```

Every refusal passes:

- `git check-ref-format --branch +main` accepts the name;
- `+main` is not `main`;
- `ls-remote refs/heads/+main` finds nothing;
- no manifest names it;
- HEAD carries nothing that `origin/main` lacks.

The script then runs `git checkout -b +main origin/main`, commits the record, and calls
`checkpoint_push "$TOPLEVEL" "+main"` → `git push -q -u origin +main`. Git reads `+main` as the refspec `+main`,
which force-updates origin's `main` from the local `main`. In the test, origin `main` was rewound from `B A` to
`A` (p1, p2). With an unreviewed local commit on `main`, that commit was published onto `main` with no PR (p3).

The hook's cloud push carve-out never sees this push, because it runs inside the script. The script's exit is 0
and it prints `push +main -> origin`, so nothing signals the rewrite. On base, `--branch` does not exist: usage,
exit 2, nothing written. This is a regression from refuse to a destructive write.

**What the rule should do.**

- Refuse a `--branch` that is not a plain branch name. At least refuse a leading `+`, and a name starting with
  `refs/` or `heads/`. Better, require the conventional shape, for example the `claude/<slug-like>` pattern or a
  `^[A-Za-z0-9][A-Za-z0-9._/-]*$` allowlist with no `+`.
- Make the push itself unambiguous, so that no branch name can become a refspec: in `push_feature_branch`,
  `git push -q -u origin "refs/heads/$branch:refs/heads/$branch"`. That helper also serves `feature-start.sh` and
  `run-review.sh`.
- Add tests: `--branch +main` and `--branch +refs/heads/main` must be refused before any write, and origin's
  `main` must be unchanged.
