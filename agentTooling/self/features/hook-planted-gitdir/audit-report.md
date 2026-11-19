Verdict: clean

# Security audit — hook-planted-gitdir

Files changed against `origin/main`: `hooks/allow-repo-commands.sh`, `hooks/README.md`.

## Rules the diff adds or changes

1. **`read_uses_own_gitdir`** (new; called from `subcommand_allowed` after `git_allowed`).
   For everyone running a git read that `git_allowed` approves, it stops silent approval
   unless the git directory the read would use is one of these: the root checkout's own,
   its common directory, a direct child of `<common>/worktrees/`, or no repository at all.
   On failure it falls through to `own_push_allowed`, which approves only pushes, so the
   read prompts.
2. **`own_checkout` refactor** (`dot_git_target` split out). The return value does not
   change: `(directory, entry)` for a `.git` directory and `(directory, gitfile target)`
   for a gitfile. The cloud-push rule that uses it behaves as before.
3. **README** (`hooks/README.md` § The git shape, § What it approves). Documentation only,
   with no rule of its own.

## Method

`git archive HEAD` → `/tmp/plan-capture.tQbAoJ/scratch/head`, `git archive origin/main` →
`…/scratch/base`. Each copy got `git init` with one commit and a real linked worktree
(`git worktree add .worktrees/wt`). Both copies got the same plants:

- `plans/evil`: a bare git dir (`HEAD`, `objects/`, `refs/`, a `config` with `core.fsmonitor`)
- `plans/nested/.git`: a copy of the bare plant
- `plans/gf/.git`: a gitfile, `gitdir: ../evil`
- `plans/gfreal/.git`: a gitfile, `gitdir: ../../.git`
- `plans/sl/.git`: a symlink to `../evil`
- `plans/evillink`: a symlink to `evil`
- `plans/headonly`: holds only a `HEAD` file

Each payload is the PreToolUse JSON (`tool_name: Bash`, `session_id`, `agent_id`, `cwd`,
`tool_input.command`), piped to `python3 <copy>/hooks/allow-repo-commands.sh` with
`CLAUDE_PROJECT_DIR=<copy>` (scripts `run.py` and `run2.py` in the scratch directory).
Results: **allow** means the hook printed `permissionDecision: allow`, **ask** means it
printed nothing (the human is asked), and **deny** means it printed a deny. `R` is the
copy's root, and cwd is `R` unless the row says otherwise.

## Inputs tried

| # | input | cwd | head | base |
|---|---|---|---|---|
| 1 | `git status` | R | allow | allow |
| 2 | `git log -1` | R | allow | allow |
| 3 | `git -C R status` | R | allow | allow |
| 4 | `git -C R/plans status` | R | allow | allow |
| 5 | `git -C R/plans/evil status` | R | ask | allow |
| 6 | `git -C plans/evil status` | R | ask | allow |
| 7 | `git -C plans -C evil status` | R | ask | allow |
| 8 | `git -C R/plans/evil/sub status` | R | ask | allow |
| 9 | `git -C R/plans/evil diff --no-index a b` | R | ask | allow |
| 10 | `git status` | R/plans/evil | ask | allow |
| 11 | `git status` | R/plans/evil/sub | ask | allow |
| 12 | `git log` | R/plans/nested | ask | allow |
| 13 | `git --git-dir=plans/evil log` | R | ask | allow |
| 14 | `git --git-dir plans/evil log` | R | ask | allow |
| 15 | `git --git-dir=R/plans/evil log` | R | ask | allow |
| 16 | `git --git-dir=evil log` | R/plans | ask | allow |
| 17 | `git -C plans --git-dir=evil log` | R | ask | allow |
| 18 | `git --git-dir=evil -C plans log` | R | ask | allow |
| 19 | `git --git-dir=.git log` | R | allow | allow |
| 20 | `git --git-dir=.git -C plans log` (git resolves to `plans/.git`, which does not exist) | R | ask | allow |
| 21 | `git --git-dir=plans/../.git log` | R | deny | deny |
| 22 | `git --git-dir=plans/evillink log` | R | ask | allow |
| 23 | `git --git-dir=.git/worktrees/wt log` | R | allow | allow |
| 24 | `git --git-dir=.git/worktrees/../../plans/evil log` | R | deny | deny |
| 25 | `git --git-dir=plans/evil --git-dir=.git log` (last one wins, as in git) | R | allow | allow |
| 26 | `git --git-dir=.git --git-dir=plans/evil log` | R | ask | allow |
| 27 | `git --work-tree=plans/evil status` | R | allow | allow |
| 28 | `git -C R/plans/nested log` | R | ask | allow |
| 29 | `git -C R/plans/gf status` (gitfile to the plant) | R | ask | allow |
| 30 | `git -C R/plans/gfreal status` (gitfile to the real `.git`) | R | allow | allow |
| 31 | `git -C R/plans/sl status` (symlinked `.git`) | R | ask | allow |
| 32 | `git -C R/plans/evillink status` | R | ask | allow |
| 33 | `git -C R/plans/headonly/inner status` (stray `HEAD` file) | R | ask | allow |
| 34 | `git -C R/.worktrees/wt status` | R | allow | allow |
| 35 | `git status` | R/.worktrees/wt | allow | allow |
| 36 | `git -C R/.git status` | R | allow | allow |
| 37 | `git -C R/.git/worktrees/wt status` | R | allow | allow |
| 38 | `git -C pla""ns/evil status` | R | ask | allow |
| 39 | `git -C 'plans/evil' status` | R | ask | allow |
| 40 | `git -C plans/ev\il status` | R | ask | allow |
| 41 | `git -C plans/ev* status` (expands to two words, so git fails) | R | allow | allow |
| 42 | `git -C plans/{evil,x} status` | R | ask | ask |
| 43 | `git -C plans/{evil} status` | R | ask | ask |
| 44 | **`git -C plans/e?il status`** | R | **allow** | allow |
| 45 | `git -C=plans/evil status` | R | ask | allow |
| 46 | `git -C` | R | ask | ask |
| 47 | `git --git-dir` | R | ask | ask |
| 48 | `GIT_DIR=plans/evil git status` | R | ask | ask |
| 49 | `env GIT_DIR=plans/evil git status` | R | ask | ask |
| 50 | `env env git -C plans/evil status` | R | ask | ask |
| 51 | `/usr/bin/env git -C plans/evil status` | R | ask | ask |
| 52 | `command git -C plans/evil status` | R | ask | ask |
| 53 | `exec -a x git -C plans/evil status` | R | ask | ask |
| 54 | `nohup git -C plans/evil status` | R | ask | ask |
| 55 | `echo plans/evil \| xargs git -C` | R | ask | ask |
| 56 | `sudo git -C plans/evil status` | R | ask | ask |
| 57 | `find plans -name evil -exec git -C {} status ;` | R | ask | ask |
| 58 | `bash -c 'git -C plans/evil status'` | R | deny | deny |
| 59 | `echo 'git -C plans/evil status' \| sh` | R | deny | deny |
| 60 | `cat <<EOF \| sh` + `git -C plans/evil status` + `EOF` | R | ask | ask |
| 61 | `/usr/bin/git -C plans/evil status` | R | ask | ask |
| 62 | `git -C $(echo plans/evil) status` | R | ask | ask |
| 63 | ``git -C `echo plans/evil` status`` | R | ask | ask |
| 64 | `D=plans/evil; git -C $D status` | R | deny | deny |
| 65 | `git -C plans/evil status && ls` | R | deny (mixed sequence) | allow |
| 66 | `ls && git -C plans/evil status` | R | deny (mixed sequence) | allow |
| 67 | `git status \| git -C plans/evil log` | R | ask | allow |
| 68 | `git -c core.fsmonitor=x status` | R | ask | ask |
| 69 | `git --no-pager -C plans/evil status` | R | ask | ask |
| 70 | `git -C plans/evil branch --show-current` | R | ask | allow |
| 71 | `git -C plans/evil worktree list` | R | ask | allow |
| 72 | `git -C plans/evil stash list` | R | ask | allow |
| 73 | `git -C plans/evil show` | R | ask | allow |
| 74 | `git -C /tmp status` | R | ask | ask |
| 75 | `git status` | /tmp | ask | ask |
| 76 | `git status` | `relative/cwd` (relative string) | allow | allow |
| 77 | `git -C plans/evil push origin main` | R | deny | deny |
| 78 | `git -C plans/evil status` | cwd field missing | ask | ask |
| 79 | `git -C plans/evil status` | cwd = `5` (not a string) | ask | ask |
| 80 | `git status` | cwd field missing | ask | ask |
| 81 | `git status` | cwd = `5` | ask | ask |
| 82 | **`git -C plans/e?il log`** | R | **allow** | allow |
| 83 | **`git -C plans/e*l log`** | R | **allow** | allow |
| 84 | **`git -C plans/evi[l] log`** | R | **allow** | allow |
| 85 | `git -C 'plans/e?il' log` (quoted: a literal path, so git fails) | R | allow | allow |
| 86 | **`git -C plans/e?il diff --no-index a b`** | R | **allow** | allow |
| 87 | `git --git-dir=plans/evi? log` | R | ask | allow |
| 88 | `git --git-dir plans/evi[l] log` | R | ask | allow |
| 89 | **`git -C plans -C e?il log`** | R | **allow** | allow |
| 90 | **`git -C plans/nest?d log`** | R | **allow** | allow |
| 91 | **`git -C plans/g? status`** (expands to the gitfile plant) | R | **allow** | allow |
| 92 | `git -C plans/@(evil) log` | R | ask | ask |
| 93 | `git -C plans/evil/ log` | R | ask | allow |
| 94 | `git --git-dir=plans/evil/ log` | R | ask | allow |
| 95 | `git -C '' log` | R | ask | ask |
| 96 | `git -C '' -C plans/evil log` | R | ask | ask |
| 97 | `git --git-dir= log` | R | ask | ask |
| 98 | `git -C plans/evil/sub/.. log` | R | deny | deny |
| 99 | `git -C ./plans/./evil log` | R | ask | allow |
| 100 | `git -C plans//evil log` | R | ask | allow |
| 101 | `git --work-tree=. --git-dir=plans/evil status` | R | ask | allow |
| 102 | `git -C plans/evil -C R log` (absolute `-C` back to the root) | R | allow | allow |
| 103 | `git -C plans/evil --git-dir=R/.git log` | R | allow | allow |
| 104 | `git --git-dir=R/.git -C plans/evil log` | R | allow | allow |

No input is more permissive on head than on base: no row goes from deny or ask to allow,
or from deny to ask. Every row that changed moved to a stricter result.

**Exploitation check for rows 44 and 82–91** (`scratch/prove.sh`, run in the head copy
only). I planted `plans/pwn` as a git dir with `core.bare=false`, a `core.worktree`, and
`core.fsmonitor = touch <scratch>/PWNED; false`. The head hook returned **ask** for
`git -C plans/pwn status` and **allow** for `git -C plans/pw? status`. Bash expands
`plans/pw?` to `plans/pwn`. Running the approved command created `<scratch>/PWNED`: the
planted config's command ran.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | `git -C plans/e?il status` / `log` / `diff --no-index a b` (a glob in a `-C` value that expands to one planted git dir) | allow; the planted `core.fsmonitor` runs (`prove.sh`) | allow | `run.py` row 44 and `run2.py` rows 82, 86 on `scratch/head` and `scratch/base` (`python3 <copy>/hooks/allow-repo-commands.sh`, `CLAUDE_PROJECT_DIR=<copy>`) |
| non-blocking | `git -C plans/e*l log`, `git -C plans/evi[l] log`, `git -C plans -C e?il log`, `git -C plans/nest?d log`, `git -C plans/g? status` (other glob shapes and plant kinds) | allow | allow | `run2.py` rows 83, 84, 89, 90, 91 on both copies |

## Non-blocking findings

- **Pre-existing silent allow: a glob in a `-C` value reaches a planted git directory.**
  Inputs: `git -C plans/e?il status` (and `log`, `diff --no-index`), `git -C plans/e*l log`,
  `git -C plans/evi[l] log`, `git -C plans -C e?il log`, `git -C plans/nest?d log`,
  `git -C plans/g? status`.
  - Head: allow. Base: allow.
  - Cause: `read_location_options` joins the literal word (`plans/e?il`).
    `discovered_gitdir` then finds no such directory, walks up to the root's real `.git`,
    and approves. Bash expands the glob to `plans/evil` before git runs, and git uses the
    plant. `prove.sh` showed the planted `core.fsmonitor` running.
  - The `--git-dir` form (`--git-dir=plans/evi?`) already prompts on head.
  - Fix: `read_uses_own_gitdir` should not approve a `-C` or `--git-dir` value holding a
    glob character (`*?[`, or an extglob). It could expand the value the way
    `path_is_confined` does (`glob.glob`) and require every match to pass. The simpler fix
    is to treat any pattern character in a location value as unjudgeable, which prompts.
  - Must go in `self/BACKLOG.md` as a `hook-planted-gitdir: backlog` commit before the
    close.
- **Over-strict, not a security finding:** row 33, `git -C plans/headonly/inner status`.
  A directory holding a stray file named `HEAD` stops the walk, so the command prompts,
  though git would keep walking up to the root. This is the conservative direction and
  needs no follow-up for safety.
- **Already backlogged:** `GIT_DIR` in the hook's own environment, and a writable real
  `.git/config`. The README names both as out of scope. In the command line, rows 48 and 49
  (`GIT_DIR=… git`, `env GIT_DIR=… git`) prompt on both copies.

## Blocking findings

None.
