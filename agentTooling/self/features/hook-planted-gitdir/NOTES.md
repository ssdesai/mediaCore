# Notes: hook-planted-gitdir

Rulings, with a one-line reason each.

## Source

`self/BACKLOG.md`, "The read-only git approvals trust a git directory planted in the tree."
(humanNetworkMap `pull-agenttooling-pr141` round-3 audit; left out of
`own-push-real-gitdir` by its ruling 8). Reproduced here on git 2.43.0: a plain-file plant
under `plans/evil/` (`HEAD`, `objects/`, `refs/`, a `config` with `core.bare = false`,
`core.worktree = <plant>`, `core.fsmonitor` and `diff.external`) runs the fsmonitor command
on `git status` (as cwd and through `-C`) and on `git --git-dir=plans/evil diff`, and the
external diff on `git -C <plant> diff --no-index a b`. `git --git-dir=plans/evil log -1`
runs neither key in this plant, but is the same unvetted directory and prompts with the rest.

## Rulings

1. **The check is the filesystem half of `own_push_allowed`'s, and no git runs.** The read
   is approved only when the git directory it would use is the root checkout's own
   (`own_checkout`), its common directory, or a direct child of `<common>/worktrees/`
   (a real linked worktree's), all by realpath (`trusted_gitdirs`).
   Why: `own_push_allowed` also asks `git rev-parse --absolute-git-dir`, but on a read that
   probe would run in the very directory being judged, and `hooks/README.md` already
   promises no git probe on a read (`hook-cloud-profile.sh` X1–X3). The walk alone is sound
   because git's discovery stops only at a directory holding a `.git` entry or one that is
   itself a git directory, which must hold `HEAD`; the walk stops at either
   (`discovered_gitdir`), so it never looks past a directory git would stop at.
2. **A directory holding `HEAD` is read as a git directory, whatever else it holds.** Git
   also needs `objects/` and `refs/` (or a `commondir` naming them); requiring less only
   prompts more, and a file named `HEAD` in an ordinary directory of a repo is rare.
3. **`--git-dir` is judged directly**, resolved against where every `-C` leaves the
   location (git sets `GIT_DIR` while parsing and resolves it after every `chdir`), and
   the last one given wins, as in git. `--work-tree` does not move the git directory and is
   not read.
4. **No repository found at all (the walk reaches `/`) stays approved.** Git then reads no
   repository config, so there is nothing planted to run; and a location inside the root of
   a checkout always reaches the root's own `.git` first.
5. **The root's `commondir` is read from its own git directory**, which sits under the
   Edit-denied `.git` (or, for a worktree root, is named by an Edit-denied `.git` file): the
   same trust `own_push_allowed` already places there.
6. **`own_checkout` is split, not changed**: the `.git` entry reading moved into
   `dot_git_target`, which the discovery walk shares. Its answers are the same (the Q rows in
   `hook-cloud-profile.sh` hold them).
7. **Tests in `self/tests/allow-repo-commands.sh`**, which runs every row in both profiles:
   the answer does not depend on the profile. The rows run against a real repository with a
   real `git worktree add`, and a `PLANT_LIVE` check runs git in the plant first so a prompt
   row is about a plant that really executes.

## Out of scope (backlog)

Unchanged and each its own entry: a writable git config generally; git variables in the
hook's environment (`GIT_DIR` set there would move every read past this check); the `.git`
Edit-deny in consumers; basename matching of `gate.sh`/`check-plans.sh`; the `analysis/`
pins; `--config`/`--config-file`. The orchestrator allowlist's git reads
(`orchestrator_git_allowed`) are a separate path and are not touched here.
