Verdict: clean

# Security audit (round 4): orchestration-start-branch-v2

- **Head:** this branch's `HEAD`, `63643dd` ("round 4 — --branch takes claude/<slug> only").
- **Base:** `origin/main`, `2108a44`.
- **How the trees were made:** `build.sh` extracted both trees with `git archive` into
  `/tmp/plan-capture.Fiyg7f/scratch/{head,base}`.
- **What was attacked:** nothing in this checkout. Every attack ran against those copies, or against git fixtures
  built from them.

What changed since round 3's audit:

- `--branch` now takes only `claude/<slug>`, where the slug matches `SLUG_PATTERN`. This replaces round 3's
  `BRANCH_NAME_PATTERN`.
- The branch merged `origin/main` (#168).
- The feature's diff against `origin/main` in `hooks/allow-repo-commands.sh`, `hooks/shared_rules.py` and
  `hooks/README.md` is the same as round 3's. The hook was attacked again anyway, so this round has its own evidence.

## Harnesses

**Hook (`hook.py`, `hook2.py`).** Each case gets a fresh consuming-repo fixture, once for head and once for base:

- `<root>/` is a `git init` repo, with the tree's whole `hooks/` vendored at `<root>/agentTooling/hooks/`.
- It holds two legacy records under `agentTooling/self/orchestrations/`: `mine`, whose fence names session S1, and
  `other`, which names S2.
- `plans/orchestrations/` exists unless a case removes it.
- The PreToolUse JSON goes on stdin, with `CLAUDE_PROJECT_DIR=<root>` and `AGENTTOOLING_PROFILE=cloud`.

**Script (`start.sh`, `start-all.sh`, `vendored.sh`, `push.sh`).** Each run, for head and for base:

1. Copies the tree, commits it (commit A) and clones a bare `origin.git` from it.
2. Clones `work` from origin.
3. Pushes commit B to origin's `main` from another clone, so `work` is stale.
4. Puts `work` in the row's state. The default is a detached HEAD at `origin/main`.
5. Runs `AGENTTOOLING_PROFILE=cloud ./orchestration-start.sh --self t --session s <args>`.
6. Records the exit code, whether the record was written, the current branch, and every ref that changed on origin.

`vendored.sh` uses the consuming-repo layout instead: `agentTooling/` is vendored, the manifest is at
`plans/features/<dir>/README.md`, and the command is `./agentTooling/orchestration-start.sh t …`.

`push.sh` sources each tree's `plan-runner-roots.sh` and calls `push_feature_branch` directly. Its fixture is a
local branch carrying a commit that does not fast-forward origin's `main`.

## Rules the diff adds or changes

1. **Hook: `orchestrator_moves_own_record` (outright `allow`).** For an orchestrator session only. It approves
   `git mv <tooling>/self/orchestrations/<slug> plans/orchestrations/<slug>` of the session's own record, under these
   conditions:
   - the line is the move alone, or the move after exactly `mkdir -p plans/orchestrations && `;
   - it runs from the consuming repo's root, in a vendored copy;
   - no symlink is on the record's path or on the destination's parents;
   - the destination does not exist yet.

   Any other `git mv` is the allowlist's deny.
2. **Hook: `orchestrator_git_allowed` → `mv`.** The same check, used as an allowlist entry inside a line that holds
   other commands. A line it admits is then judged by the rest of the hook.
3. **`shared_rules.LEGACY_RECORD_MOVE` / `LEGACY_RECORD_MKDIR`.** The remedy text, which now carries the
   `mkdir -p` lead.
4. **`orchestration-start.sh --branch`, a lifecycle refusal (cloud profile).**
   - It refuses any `--branch` that is not `claude/<slug>`.
   - It refuses a branch that already exists locally, or on origin (asked with `ls-remote`).
   - It refuses a branch that a feature manifest on `origin/main` names. This covers agentTooling's own corpus and,
     from a vendored copy, the consuming repo's.
   - It refuses when there are unpushed commits, uncommitted changes, a launch from another branch, the local
     profile, or a coordinator record.
   - It also refuses, with no `--branch`, a cloud launch on a detached HEAD or on `main`.
   - Otherwise it cuts the branch off `origin/main`, commits the record and pushes it.
   - On base, every `--branch` is a usage error (exit 2).
5. **`held_feature` / `branch_named_at`.** They now read with `ls-files -z` / `ls-tree -z`, so a manifest path that
   git would C-quote is no longer skipped.
6. **`plan-runner-roots.sh` `push_feature_branch`.** It now pushes `refs/heads/<b>:refs/heads/<b>`, not `<b>`.

## Inputs tried

### Hook (rules 1–3)

**How to read the result columns:**

- **allow** means `permissionDecision: allow`.
- **no output** means the hook says nothing, so the settings decide. No rule allows these lines, so they are a
  prompt.
- **deny** means the hook denies the line.

**Shorthands in the input column:**

- `OWN` is `agentTooling/self/orchestrations/mine`.
- `DST` is `plans/orchestrations/mine`.
- `LEAD` is `mkdir -p plans/orchestrations && `.
- The session is S1 and the cwd is the consumer root, unless the row says otherwise.

| id | input / setup | head | base | note |
|---|---|---|---|---|
| M1 | `git mv OWN DST` | allow | deny | the intended shape |
| K1 | `LEAD git mv OWN DST`, no `plans/` | allow | deny | intended. Run for real (`realmove.sh`), it moves the record. |
| K1b | the same, with `plans/orchestrations/` present | allow | deny | intended |
| M2 | `git mv …/other plans/orchestrations/other` (S2's record) | deny | deny | |
| M3 | `git mv OWN plans/orchestrations/other` | deny | deny | |
| M4 | `git mv OWN plans/mine` | deny | deny | |
| M5 | `git mv OWN/README.md DST` | deny | deny | |
| M6 / M7 / M8 | `git mv -f` / `-k` / `--` `OWN DST` | deny | deny | |
| M9 / M9b | an extra word / one operand | deny | deny | |
| M10 / M10b / M10c | `git -C .` / `-c core.fsmonitor=touch` / `--git-dir=.git` `mv OWN DST` | deny | deny | |
| M11 / M11b | `GIT_DIR=x` / `GIT_CONFIG_PARAMETERS=…` prefix | deny | deny | |
| M12 / M12b / M12c | `env` / `env env` / `/usr/bin/env` `git mv OWN DST` | deny | deny | |
| M13 | `/usr/bin/git mv OWN DST` | deny | deny | |
| M14 / M15 / M16 / M17 | `command` / `nohup` / `xargs` / `sudo` | deny | deny | |
| M18 | `bash -c 'git mv OWN DST'` | deny | deny | |
| M19 | `echo git mv OWN DST \| sh` | deny | deny | |
| M20 | `find . -maxdepth 0 -exec git mv OWN DST ;` | deny | deny | |
| M21 / M21b | `exec -a git git mv …` / `time git mv …` | deny | deny | |
| M22 | `"git" "mv" "OWN" 'DST'` | allow | deny | the same words as M1; not a finding |
| M23 | `git mv …/mi""ne plans/orchestrations/mi''ne` | allow | deny | the same words as M1; not a finding |
| M23b | `g""it m''v OWN DST` | allow | deny | the same words as M1; not a finding |
| M24 / M24b | `…/mi\ne` / `$'OWN'` | deny | deny | |
| M25 / M26 / M26b | a glob / a brace group on either operand | deny | deny | |
| M27 / M28 / M28b / M29 | `$SLUG` / `$(echo mine)` / backticks / `~/…` | deny | deny | |
| M30 | `git mv OWN DST && git status` | deny | deny | |
| M31 | `git mv OWN DST; git push -u origin main` | deny | deny | |
| M32 / M33 | `… > /dev/null` / `… 2>&1` | allow | deny | a harmless redirect; not a finding |
| M34 / M34b | `> out.txt` / `> /dev/null; touch pwned` | deny | deny | |
| M35 | `git mv OWN DST &` | deny | deny | |
| M36 / M37 | the move, then a newline and `git status` / `touch pwned` | deny | deny | |
| M38 | the move with a heredoc on stdin | deny | deny | |
| M39 | `git mv OWN DST \| cat` | no output | deny | the intended move, sent to a prompt; not a finding |
| M40 / M41 | `( … )` / `{ …; }` | deny | deny | |
| M42 | the move `# comment` | deny | deny | |
| M43 / M44 | a `..` in the source / in the destination | deny | deny | |
| M44b / M44c / M44d | `./` prefixes / trailing `/` / `plans//orchestrations` | deny | deny | |
| M45 | `git mv OWN DST` as S2 | deny | deny | |
| M46 / M46b / M46c | as S3 (no role) / no `session_id` / an empty one | no output | no output | not an orchestrator |
| M47 | `git mv self/orchestrations/mine ../plans/orchestrations/mine`, cwd `agentTooling/` | deny | deny | |
| M48 / M49 | cwd `plans/` / cwd `/` | deny | deny | |
| M50 / M51 | cwd `null` / cwd `7` | deny | deny | |
| M52 / M52b | cwd `<root>/agentTooling/..` / `<root>/.` | allow | deny | the same directory; not a finding |
| M53 / M53b / M53c | `DST` exists as a directory / as a dangling symlink / as a file | deny | deny | |
| M54 | `plans/orchestrations` is a regular file | allow | deny | git refuses (`realmove.sh`: `fatal: … Not a directory`, rc 128); nothing moves; not a finding |
| M54b | `plans` is a file, with `LEAD` | allow | deny | `mkdir` fails and `&&` stops (rc 1); not a finding |
| M55 | a `.git` file in `agentTooling/` (a standalone checkout) | deny | deny | |
| M58 | `OWN` is a symlink to a real directory | deny | deny | |
| M58b | `agentTooling/self` is a symlink | deny | deny | |
| M59 | `plans` → symlink to `<root>/.git` | deny | deny | |
| M65 / M65k | `plans` → symlink outside the repo (without / with `LEAD`) | deny | deny | |
| M66 | `plans/orchestrations` → symlink outside the repo | deny | deny | |
| M66b | `plans/orchestrations` → symlink to `agentTooling/self/orchestrations` | deny | deny | |
| M71 | `mine/README.md` → symlink to `../other/README.md`; `git mv …/other …/other` | no output | no output | S1 then holds no record |
| M72 | S1 named only by the ledger (`.git/agenttooling-orchestrators`: `S1 mine`) | allow | deny | its own slug according to the ledger; not a finding |
| M73 | S1 also holds a record in `plans/orchestrations/mine2` | allow | deny | its own legacy record; not a finding |
| M74 | S1's record in a non-slug directory `Mine_X` | deny | deny | |
| M75 / M75b | S1 holds two legacy records: move `mine2` / move `mine` | deny / allow | deny / deny | only the record the lookup returns is admitted; not a finding |
| L1 | the ledger says `S1 other`; `other`'s fence names S2; S1 moves `other` | allow | deny | see note 1; not a finding |
| L2 | the ledger says `S3 other`; S3 moves `other` | allow | deny | see note 1; not a finding |
| L3 | the ledger says `S3 other`; S3 moves `mine` | deny | deny | |
| K2 | `LEAD git mv OWN plans/orchestrations/other` | deny | deny | |
| K3 / K4 / K16 | `LEAD rm -rf plans` / `LEAD git status` / `LEAD touch x` | deny | deny | |
| K5 | `LEAD` the move `&& git status` | deny | deny | |
| K6 / K34 | two spaces before `&&` / no space after it | deny | deny | |
| K7 / K8 / K9 | `mkdir -p /tmp/x` / `mkdir -m 777 -p …` / `mkdir -p plans/orchestrations/evil`, then `&&` and the move | deny | deny | |
| K10 / K11 | the lead twice, then the move | deny | deny | |
| K12 / K13 / K14 | the lead joined with `;` / `\|\|` / `&` | deny | deny | |
| K15 | `mkdir -p plans/orchestrations` alone | deny | deny | |
| K17 | `LEAD` the move `> /dev/null` | allow | deny | a harmless redirect; not a finding |
| K18 / K19 / K36 | a redirect on the `mkdir` (`> /tmp/x`, `> /dev/null`, `2> /dev/null`) | deny | deny | |
| K20 / K21 / K22 / K23 | `LEAD` the move then `\| sh` / `; rm -rf x` / a newline and `rm -rf x` / `# x` | deny | deny | |
| K24 | leading blanks before `LEAD` | allow | deny | the same line; not a finding |
| K25 | `MKDIR=1 LEAD …` | deny | deny | |
| K26 / K27 | `mkdir -p 'plans/orchestrations'` / `mkdir -p plans/orch*` | deny | deny | |
| K28 | `LEAD` the move, `plans` → symlink outside | deny | deny | |
| K29 / K30 | `LEAD` the move as S2 / as S3 | deny / no output | deny / no output | |
| K31 / K32 / K33 / K35 | a trailing `&& mkdir …` / `( … )` / `\| tee` / `;` after the lead | deny | deny | |
| C1 | the move `&& git add README.md` (no such file) | deny | deny | |
| C2 | `git status &&` the move | deny | deny | |
| C3 | the move `&& git commit -m x` | no output | deny | see note 2; not a finding |
| C4 | the move `&&` the move | no output | deny | see note 2; not a finding |
| C5 / C6 | `…/other` move `&& git status` / `ls &&` the `other` move | deny | deny | |
| C7 | the move `2>/dev/null </dev/null` | deny | deny | |
| C8 | the move `>/dev/null 2>&1` | allow | deny | a harmless redirect; not a finding |
| C9 / C10 / C11 | `>\| /dev/null` / `> /dev/null > out` / `2>/dev/null>out` | deny | deny | |
| C12 / C13 | a trailing `;` | deny | deny | |
| C14 / C15 | tabs as separators / a trailing newline | allow | deny | the same words; not a finding |
| C16 / C17 | a `\` continuation (inside the move / after the lead) | deny | deny | |
| C18 | `LEAD` the move with `core.fsmonitor` set in the consumer's `.git/config` | allow | deny | the intended shape; a repo-config fsmonitor fires on any git read the base already admits (`git status`); not a finding |
| R1 / R2 | `git push -u origin +main` / `… refs/heads/x:refs/heads/main` | deny | deny | |
| R3 / R4 / R5 | `./agentTooling/orchestration-start.sh … --branch +main` (S3) / `--branch claude/mine` (S1) / `--branch origin/main` (S1) | no output | no output | the hook leaves the script to the settings: a prompt on both |
| R6 | `git checkout -b claude/mine` (S1) | deny | deny | |
| R7 / R8 | the payload is not JSON / `command` is a list | no output | no output | |
| R9 | the move with an `agent_id` (S1's delegate) | allow | deny | the same session's own record; not a finding |
| R10 | no `cwd` in the payload | deny | deny | |
| R11 / R12 | `session_id` is a list / `tool_name` is `bash` | no output | no output | |

**Note 1 (L1/L2): the ledger.** The role lookup returns the record the ledger ties to the session.
`self/tests/hook-orchestrator-role.sh` H13 treats the ledger as authoritative when the record has been rewritten.

So the "own record" the move admits is the role's own record: a legacy record, moved to the place
`LEGACY_RECORD_REFUSAL` says every legacy record belongs. Nothing else is moved.

Planting a ledger line takes a write to `.git/`, which:

- an orchestrator's allowlist never admits;
- any other session can make only through a prompt.

**Note 2 (C3/C4): the move inside a longer line.** Rule 2 makes the move an allowlist entry inside a longer line, as
the README row documents. Such a line goes on to the ordinary policy, and here that means a prompt (a git write).
The human sees exactly the move and the commit. Base denies because `mv` was not on its list. The head's prompt is
the designed result, not a bypass.

### `orchestration-start.sh` (rules 4–5) and `push_feature_branch` (rule 6)

**On base:**

- Every row with `--branch` exits 2 (usage), writes nothing and changes nothing on origin.
- Origin's `main` never moved on head in any row.

"Goes on" means the script exits 0, cuts the branch, commits the record and pushes that one branch.

| id | input (cloud; detached at `origin/main` unless stated) | head | base | note |
|---|---|---|---|---|
| p01 | `--branch claude/t` | goes on; origin gains `refs/heads/claude/t` only | usage | the intended path |
| p02 | `--branch origin/main` | refused (`claude/<slug>`) | usage | round 3's blocking finding: fixed |
| p03 | `--branch origin/HEAD` | refused | usage | round 3: fixed |
| p04 | `--branch origin/claude/someone` | refused | usage | round 3: fixed |
| p05 / p06 | `--branch +main` / `+claude/t` | refused | usage | |
| p07 | `--branch main` | refused | usage | |
| p08 / p09 | `refs/heads/claude/t` / `heads/claude/t` | refused | usage | |
| p10 / p11 | `claude/t:main` / `claude/t:refs/heads/main` | refused | usage | |
| p12 / p13 | `claude/../main` / `'claude/*'` | refused | usage | |
| p14 / p15 | `claude/` / `claude` | refused | usage | |
| p16 / p17 / p18 / p19 | `claude/T` / `claude/a_b` / `claude/a.b` / `claude/a.lock` | refused | usage | |
| p20 | `claude/a/b` | refused | usage | |
| p21 / p22 / p23 | `claude/-a` / `claude/a-` / `claude/a--b` | refused | usage | |
| p24 / p25 | `$'claude/t\n'` / `$'claude/t\nmain'` | refused | usage | |
| p26 / p27 | a trailing / leading blank | refused | usage | |
| p28 | `claude/main` | goes on: `refs/heads/claude/main` | usage | a distinct `claude/<slug>` name, inside the owner's rule; see p28r |
| p29 | `claude/head` | goes on: `refs/heads/claude/head` | usage | inside the rule; distinct from `HEAD`; not a finding |
| p30 / p31 / p32 | `Claude/t` / `claude//t` / `remotes/origin/main` | refused | usage | |
| p33 / p34 | `claude/t@{0}` / `claude/t^0` | refused | usage | |
| p35 / p36 | `-f` / `--force` | refused | usage | |
| p37 | `--branch claude/x --branch origin/main` | refused (the last one wins) | usage | |
| p38 | `--branch origin/main --branch claude/x` | goes on as `claude/x` | usage | the last one wins; harmless |
| p39 | `--coordinator --branch claude/t` | refused | usage | |
| p40 | `$'claude/t\x01'` | refused | usage | |
| p41 | `claude/ｔ` (a fullwidth t) | refused | usage | |
| p42 | `claude/t1-2-3` | goes on | usage | intended |
| s01 | `claude/t` from an up-to-date `main` | goes on | usage | intended |
| s02 / s03 | an unpushed commit on `main` / on a detached HEAD | refused (1 commit not on `origin/main`) | usage | |
| s04 / s05 | a modified tracked file / an untracked file | refused (uncommitted changes) | usage | |
| s06 / s08 / s19 | on `feature/x` / `claude/u` / `main2`, with `--branch claude/t` | refused (switches to no other branch) | usage | |
| s07 | already on `claude/t`, with `--branch claude/t` | goes on: commits the record and pushes `claude/t` | usage | the branch the session is on; the orchestrator's allowlist already admits `git push -u origin <its branch>`; not a finding |
| s09 | `claude/t` exists locally | refused | usage | |
| s10 | `claude/t` exists on origin only (the local cache is stale) | refused (`ls-remote`) | usage | |
| s11 | an `origin/main` manifest's `branches[0]` is `claude/t` | refused | usage | |
| s12 | origin unreachable (`ls-remote` exits 128) | refused ("cannot ask origin") | usage | |
| s13 | no `origin` remote | goes on, local only: no push | usage | nothing is pushed anywhere; not a finding |
| s14 | a second remote named `claude`, `--branch claude/t` | goes on | usage | no `refs/remotes/claude/t`, so nothing is shadowed |
| p28r | a remote named `claude`, `--branch claude/main` | goes on; `git rev-parse claude/main` warns "ambiguous" and resolves to the new local branch, not `refs/remotes/claude/main` | usage | see note 3; not a finding |
| s15 | a tag `claude/t` exists | goes on; the explicit refspec pushes the branch | usage | not a finding |
| s16 / s17 | no `--branch`, on a detached HEAD / on `main` | refused (names `--branch claude/t`) | record written (exit 0) | stricter on head |
| s18 | no `--branch`, on `feature/x` | record written | record written | same |
| s20 | `--branch claude/t`, `AGENTTOOLING_PROFILE=local` | refused | usage | |
| s21 | `--branch claude/t`, `AGENTTOOLING_PROFILE=bogus` | refused | usage | |
| s22 | no `--branch`, local profile | record written | record written | same |
| v01 | vendored copy, `--branch claude/t`, the consumer manifest names `claude/other` | goes on | usage | intended |
| v02 | vendored copy, the consumer manifest `plans/features/zz` names `claude/t` | refused | usage | |
| v03 / v04 / v05 | the same, with the manifest directory `zé` / `z⇥z` / `z"z` (C-quoted by git) | refused (`ls-tree -z`) | usage | |
| v06 | vendored copy, on `claude/held`, no `--branch`; manifest `zé` names that branch | refused (`held_feature`, `-z`) | record written | stricter on head (base skipped the C-quoted path) |
| v07 | the same; manifest `zé` lists session `s` | refused | record written | stricter on head |
| v08 | the same with manifest `zz` | refused | refused | same |
| u1 | `push_feature_branch … claude/x` | pushes `refs/heads/claude/x` | the same | |
| u2 | `push_feature_branch … +main` (a local branch named `+main`) | pushes a new `refs/heads/+main`; origin's `main` unchanged | **force-pushes origin `main`** (`01174d7` → `a5fca74`) | stricter on head |
| u3 | `push_feature_branch … +claude/x` | pushes a new `refs/heads/+claude/x` | fails (rc 1) | the head pushes the branch actually named; no other ref is touched; not a finding |
| u4 / u5 / u6 | `main` (not a fast-forward) / `claude/x:main` / `x:refs/heads/main` | fails, origin unchanged | fails, origin unchanged | same |

**Note 3 (p28r): a remote named `claude`.** In the same family as round 3's `origin/main`, a `claude/<slug>`
branch shadows a remote-tracking ref only in a checkout that has a remote named `claude`.

That remote does not exist in the cloud layout, and adding one is a human-approved `git remote add`.

Nothing the harness runs reads `claude/*` remote-tracking refs: the base is always `origin/main`. So the script's own
refusals, and every `origin/main...HEAD` diff, are unaffected.

The owner's round-4 ruling admits exactly `claude/<slug>`, and git warns about the ambiguity.

This is recorded so the owner can see it, not raised as a finding.

## Findings

None.

## Non-blocking findings

None.

## Blocking findings

None. Round 3's three blocking findings (`--branch origin/main`, `origin/HEAD` and `origin/claude/someone`) no longer
reproduce: p02–p04 are refused, and nothing is written.
