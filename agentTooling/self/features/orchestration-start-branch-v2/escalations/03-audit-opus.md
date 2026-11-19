Verdict: escalated

# Security audit (round 3): orchestration-start-branch-v2

Head is this branch's `HEAD` (`30873dd`). Base is `origin/main`. `build.sh` extracted both trees with
`git archive` into `/tmp/plan-capture.yW0Uiq/scratch/{head,base}`.

What changed since round 2's audit (`git diff 31c1c5e HEAD`):

- Among the audited files, only `orchestration-start.sh` and `plan-runner-roots.sh` changed.
- `hooks/allow-repo-commands.sh`, `hooks/shared_rules.py` and `hooks/README.md` are byte-identical to round 2.
- The hook was still re-run with a sample of round 2's attacks, to give this round its own evidence.

**Hook harness (`hook.py`).** Each case gets a fresh consuming-repo fixture for head and for base:

- `consumer/` has its own `git init`, with the tree's `hooks/` vendored at `consumer/agentTooling/hooks/`.
- It holds two legacy records under `agentTooling/self/orchestrations/`: `mine`, whose fence names session S1,
  and `other`, which names S2.
- `plans/orchestrations/` exists unless a case removes it.
- The PreToolUse JSON goes on stdin, with `CLAUDE_PROJECT_DIR` set to the fixture and
  `AGENTTOOLING_PROFILE=cloud`.

**Script harness (`start.sh` / `start-all.sh` / `start-more.sh`).** Each run, for head and for base:

- seeds a bare `origin.git` from the tree (commit A) and clones it;
- pushes commit B to origin's `main` from elsewhere, so the clone's local `main` is stale;
- puts the clone in the state the row names (default: a detached HEAD at `origin/main`);
- runs `AGENTTOOLING_PROFILE=cloud ./orchestration-start.sh --self t --session s <args>`.

## Rules the diff adds or changes

1. **Hook, `orchestrator_moves_own_record` (outright `allow`).** For an orchestrator session only. It approves
   `git mv <tooling>/self/orchestrations/<slug> plans/orchestrations/<slug>` of the session's own record, alone
   or after exactly `mkdir -p plans/orchestrations && `, under these conditions:
   - the line runs from the consuming repo's root, in a vendored copy;
   - no symlink is on the record's path or on the destination's parents;
   - the destination does not exist yet.

   Unchanged since round 2.
2. **Hook, `orchestrator_git_allowed` → `mv`.** The same check, used as an allowlist entry inside a mixed line.
   Unchanged.
3. **`shared_rules.LEGACY_RECORD_MOVE`.** Remedy text that now carries the `mkdir -p` lead. Unchanged.
4. **`orchestration-start.sh --branch`, cloud profile (lifecycle refusal).** Round 3 adds
   `BRANCH_NAME_PATTERN` `^[A-Za-z0-9][A-Za-z0-9._/-]*$`, which refuses:
   - a name starting `refs/` or `heads/`;
   - a name holding `..`;
   - `main`;
   - a name `git check-ref-format --branch` rejects.

   The other refusals are unchanged: an existing local or origin branch, a manifest's branch, unpushed commits,
   a dirty tree, a launch from another branch, the local profile, a coordinator record. When nothing refuses, it
   cuts the branch, commits the record and pushes. On base, every `--branch` is a usage error (exit 2) and
   nothing is written.
5. **`plan-runner-roots.sh` `push_feature_branch`.** It now pushes `refs/heads/<b>:refs/heads/<b>`, not
   `<b>`. Its callers are `orchestration-start.sh`, `feature-start.sh`, `feature-capture.sh` and
   `run-review.sh`. This can only narrow what a push names.

## Inputs tried

### Hook (rules 1–3)

**How to read the result columns:**

- **allow** means `permissionDecision: allow`.
- **no output** means the settings decide; no rule allows these lines, so they are a prompt.
- **deny** means the hook denies the line.

**Shorthands in the input column:**

- `OWN` is `agentTooling/self/orchestrations/mine`.
- `DST` is `plans/orchestrations/mine`.
- The session is S1 and the cwd is the consumer root, unless the row says otherwise.

| id | input / setup | head | base | note |
|---|---|---|---|---|
| M1 | `git mv OWN DST` | allow | deny | the intended shape |
| K1 | `mkdir -p plans/orchestrations && git mv OWN DST`, no `plans/` | allow | deny | the intended shape |
| M2 | `git mv …/other plans/orchestrations/other` (S2's record) | deny | deny | |
| M3 | `git mv OWN plans/orchestrations/other` | deny | deny | |
| M6 | `git mv -f OWN DST` | deny | deny | |
| M8 | `git mv -- OWN DST` | deny | deny | |
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
| M30 | `git mv OWN DST && git status` | deny | deny | |
| M31 | `git mv OWN DST; git push -u origin main` | deny | deny | |
| M32 | `git mv OWN DST > /dev/null` | allow | deny | harmless redirect; not a finding |
| M34 | `git mv OWN DST > out.txt` | deny | deny | |
| M35 | `git mv OWN DST &` | deny | deny | |
| M36 | `git mv OWN DST` + newline + `git status` | deny | deny | |
| M38 | `git mv OWN DST <<'EOF' … EOF` | deny | deny | |
| M39 | `git mv OWN DST \| cat` | no output | deny | the intended move, sent to a prompt instead of approved; not a finding |
| M40 | `(git mv OWN DST)` | deny | deny | |
| M43 | `git mv …/orchestrations/../orchestrations/mine DST` | deny | deny | |
| M44 | `git mv OWN plans/orchestrations/../orchestrations/mine` | deny | deny | |
| M45 | `git mv OWN DST` as S2 | deny | deny | |
| M46 | `git mv OWN DST` as S3 (no role) | no output | no output | not an orchestrator |
| M47 | `git mv self/orchestrations/mine ../plans/orchestrations/mine`, cwd `agentTooling/` | deny | deny | |
| M48 | `git mv OWN DST`, cwd `plans/` | deny | deny | |
| M50 | `git mv OWN DST`, cwd `null` | deny | deny | |
| M51 | `git mv OWN DST`, cwd `7` | deny | deny | |
| M52 | `git mv OWN DST`, cwd `<root>/agentTooling/..` | allow | deny | the same directory; not a finding |
| M53 | `DST` already exists | deny | deny | |
| M55 | a `.git` file in `agentTooling/` (a standalone checkout) | deny | deny | |
| M58 | `OWN` is a symlink to a real directory | deny | deny | |
| M59 | `plans` → symlink to `<root>/.git` | deny | deny | |
| M65 | `plans` → symlink outside the repo | deny | deny | |
| M65k | the same, with the `mkdir -p` lead | deny | deny | |
| M66 | `plans/orchestrations` → symlink outside the repo | deny | deny | |
| M71 | `mine/README.md` → symlink to `../other/README.md`; `git mv …/other …/other` | deny | deny | |
| K2 | the lead, then `git mv OWN plans/orchestrations/other` | deny | deny | |
| K3 | `mkdir -p plans/orchestrations && rm -rf plans` | deny | deny | |
| K9 | `mkdir -p plans/orchestrations/evil && git mv OWN DST` | deny | deny | |
| K12 | `mkdir -p plans/orchestrations ; git mv OWN DST` | deny | deny | |
| K13 | `mkdir -p plans/orchestrations \|\| git mv OWN DST` | deny | deny | |
| K15 | `mkdir -p plans/orchestrations` alone | deny | deny | |
| K20 | the lead plus the move `\| sh` | deny | deny | |
| K21 | the lead plus the move `; rm -rf x` | deny | deny | |
| K23 | the lead plus the move `# x` | deny | deny | |
| R1 | `git push -u origin +main` (S1) | deny | deny | |
| R2 | `git push -u origin refs/heads/x:refs/heads/main` (S1) | deny | deny | |
| R3 | `./agentTooling/orchestration-start.sh --self t --session s --branch +main` (S3) | no output | no output | the hook leaves the script to the settings: a prompt on both |
| R4 | `./agentTooling/orchestration-start.sh mine --branch origin/main` (S1) | no output | no output | the same |

### `orchestration-start.sh` (rules 4–5)

Each row records:

- the exit code;
- whether the record was written;
- origin's `main` before and after the run;
- the new refs on origin.

On base, every row exits 2 (usage) and writes nothing. Origin's `main` stays `B A` on both trees in every row.

| id | input (cloud; detached at `origin/main` unless stated) | head | base | note |
|---|---|---|---|---|
| b01 | `--branch claude/b01` | goes on: cut, commit, push `claude/b01`; upstream `refs/heads/claude/b01` | usage (2) | the intended path |
| p1 | `--branch +main` | refused (pattern) | usage | round 2's blocking finding: fixed |
| p2 | `--branch +refs/heads/main` | refused | usage | fixed |
| p3 | `--branch +main`, unreviewed commit on local `main` | refused | usage | fixed |
| p4 | `--branch +claude/p4` | refused | usage | |
| p5 | `--branch refs/heads/main` | refused | usage | |
| p6 | `--branch heads/main` | refused | usage | |
| p7 | `--branch refs/heads/claude/x` | refused | usage | |
| p8 | `--branch claude/../main` | refused | usage | |
| p9 | `--branch claude/p9:main` | refused | usage | |
| p10 | `--branch claude/p9:refs/heads/main` | refused | usage | |
| p11 | `--branch 'claude/*'` | refused | usage | |
| p12 | `--branch 'main^0'` | refused | usage | |
| p13 | `--branch ' main'` | refused | usage | |
| p14 | `--branch 'main '` | refused | usage | |
| p15 | `--branch $'claude/x\nmain'` | refused | usage | |
| p16 | `--branch -f` | refused | usage | |
| p17 | `--branch --force` | refused | usage | |
| **p18** | `--branch origin/main` | **goes on, exit 0: creates the local `refs/heads/origin/main` and pushes `refs/heads/origin/main` to origin** | usage | **blocking — see below** |
| p19 | `--branch remotes/origin/main` | goes on: `refs/heads/remotes/origin/main` | usage | `refs/remotes/origin/main` still wins the lookup, so nothing is shadowed; not a finding |
| p20 | `--branch tags/v1` | goes on: `refs/heads/tags/v1` | usage | odd but distinct; not a finding |
| p21 | `--branch MAIN` | goes on: `refs/heads/MAIN` | usage | distinct from `main` on a case-sensitive file system (the cloud profile is Linux); not a finding |
| p22 | `--branch main.lock` | refused | usage | |
| p23 | `--branch main/x` | refused (`checkout -b` fails: `main` exists); nothing written | usage | |
| p24 | `--branch main/` | refused | usage | |
| p25 | `--branch claude/x.` | refused | usage | |
| p26 | `--branch @` | refused | usage | |
| p27 | `--branch 'main@{0}'` | refused | usage | |
| p28 | `--branch HEAD` | refused | usage | |
| p29 | `--branch .main` | refused | usage | |
| p30 | `--branch claude//x` | refused | usage | |
| p31 | `--branch Refs/heads/main` | goes on: `refs/heads/Refs/heads/main` | usage | distinct on Linux; not a finding |
| p32 | `--branch claude/x:` | refused | usage | |
| p33 | `--branch claude/p33`, unreviewed commit on local `main` | goes on; only `claude/p33` pushed; the unreviewed commit stays local | usage | the explicit refspec pushes one ref; not a finding |
| p34 | `--branch claude/p34`, on an up-to-date `main` | goes on | usage | the intended path from `main` |
| p35 | `--branch claude/exist`, a local branch of that name | refused | usage | |
| p36 | `--branch claude/x --branch +main` | refused (the last `--branch` wins) | usage | |
| p37 | `--branch +main --branch claude/x` | goes on as `claude/x` | usage | the last one wins; harmless |
| p38 | `--coordinator --branch +main` | refused | usage | |
| p39 | `--branch +main`, `AGENTTOOLING_PROFILE=local` | refused | usage | |
| p40 | `--branch +main`, `AGENTTOOLING_PROFILE=bogus` | refused | usage | |
| **p41** | `--branch origin/HEAD` | **goes on: `refs/heads/origin/HEAD` shadows `refs/remotes/origin/HEAD`** | usage | **blocking (same family as p18)** |
| **p42** | `--branch origin/claude/someone` | **goes on: `refs/heads/origin/claude/someone` shadows that remote-tracking ref** | usage | **blocking (same family as p18)** |
| p43 | `--branch remotes/origin/HEAD` | goes on: `refs/heads/remotes/origin/HEAD` | usage | shadowed, not shadowing; not a finding |
| S1 | after p18, what `origin/main` names (`shadow.sh`) | `warning: refname 'origin/main' is ambiguous` → the local orchestrator branch. Every later read sees the orchestrator's branch: `git rev-list --count origin/main..HEAD` = 0, an empty `git diff origin/main...HEAD`, and `git fetch origin main` does not undo it. A second `--branch claude/t2` start in the same checkout fails at `checkout -b claude/t2 origin/main` | — | the consequence of p18 |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | `orchestration-start.sh --self t --session s --branch origin/main` (cloud, detached HEAD at `origin/main`) | goes on, exit 0: cuts local branch `refs/heads/origin/main`, commits the record and pushes it. In that checkout `origin/main` then resolves to the orchestrator's branch, not the remote-tracking ref. The script's own "commits not on origin/main" refusal, and every `origin/main...HEAD` diff, read the orchestrator's branch. | refused (usage, exit 2), nothing written | `bash /tmp/plan-capture.yW0Uiq/scratch/start.sh head p18 detached -- --branch origin/main` versus `… start.sh base p18 detached -- --branch origin/main`, then `bash /tmp/plan-capture.yW0Uiq/scratch/shadow.sh` |
| blocking | the same with `--branch origin/HEAD` | goes on, exit 0: `refs/heads/origin/HEAD` shadows `refs/remotes/origin/HEAD` | refused (usage, exit 2) | `start-more.sh` rows `[head p41]` / `[base p41]` |
| blocking | the same with `--branch origin/claude/someone` | goes on, exit 0: `refs/heads/origin/claude/someone` shadows another session's remote-tracking branch | refused (usage, exit 2) | `start-more.sh` rows `[head p42]` / `[base p42]` |

## Non-blocking findings

None.

Every other input whose result differs between head and base falls into one of three groups:

- **Stricter on head.**
- **The documented move of the session's own record.** This includes words that are the same after the shell's
  quote removal, a harmless redirect, and the same directory reached by another path.
- **Branch names that create a distinct, unshadowing ref** (p19, p20, p21, p31, p43). Each such row is marked
  "not a finding".

## Blocking findings: reproduction and fix

### 1. A `--branch` beginning with a remote's name shadows that remote's tracking refs (p18, p41, p42)

**Reproduce.**

1. Take a cloud container (`AGENTTOOLING_PROFILE=cloud`) on a detached HEAD at `origin/main`.
2. Run:

   ```
   ./orchestration-start.sh --self t --session s --branch origin/main
   ```

3. Every refusal passes. The name matches `BRANCH_NAME_PATTERN`, has no `..`, and does not start `refs/` or
   `heads/`. It is not `main`, and `check-ref-format --branch` accepts it. There is no local
   `refs/heads/origin/main`, and `ls-remote` finds no `refs/heads/origin/main`.
4. The script runs `git checkout -b origin/main origin/main`, commits the record and pushes
   `refs/heads/origin/main`.

**Why it shadows.** Git's ref lookup tries `refs/heads/<name>` before `refs/remotes/<name>`. In that checkout,
from then on, the bare `origin/main` names the orchestrator's branch and moves with each of its commits. `git`
prints only `warning: refname 'origin/main' is ambiguous`, and `git fetch origin main` does not undo it.

**Effects.** Every lifecycle step that reads `origin/main` now reads the orchestrator's branch:

- the script's own `rev-list --count origin/main..HEAD` refusal (it counts 0);
- any `git diff origin/main...HEAD` (it is empty);
- the start point of a later cut.

Origin also gets a branch named literally `origin/main`. Base has no `--branch`, so it refuses every one of
these with exit 2. This is a regression from refuse to go on.

**Severity.** The hook does not approve `orchestration-start.sh` silently: R3 and R4 show no output, so the
settings decide and the human is prompted. The damage stays in the container's own ref namespace. Origin's
`main` is never touched. By the plan's rule it is still blocking: it is a regression from refuse to a write,
and the rule's own stated purpose is defeated ("no branch name can be read as another ref").

**What the rule should do.** Refuse a `--branch` before any write when either of these holds:

- its first path component is the name of a configured remote (`git remote` lists it);
- the name already resolves to a ref: `git rev-parse --verify --quiet "<name>^{commit}"` succeeds.

The second check also covers `MAIN`-style collisions on a case-insensitive file system and an existing tag
name. A stricter alternative is to require the `claude/` prefix the refusal already offers
(`CLOUD_BRANCH_PREFIX`).

Add tests: `--branch origin/main`, `--branch origin/HEAD` and `--branch origin/claude/x` must each be refused,
with nothing written and no `refs/heads/origin/*` created.
