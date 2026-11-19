Verdict: clean

# Review: hook-planted-gitdir

## What the batch was supposed to do

Close the `self/BACKLOG.md` gap "the read-only git approvals trust a git directory planted
in the tree". Before this change, a bare git directory written as plain files under, say,
`plans/evil/` (with `core.fsmonitor` / `diff.external` in its `config`) made
`git -C <plant> status`, `git -C <plant> diff --no-index a b`, a `git status` run from inside
the plant, and `git --git-dir=plans/evil log -1` approved silently, and git then ran the
command the plant names. After the change, each of those must prompt. The root's own reads
and a real linked worktree's reads must stay approved. The check itself must not run git,
and the backlog entry must be removed.

## Does it do that — yes

- **`hooks/allow-repo-commands.sh`**: `subcommand_allowed` now approves a `git_allowed`
  read only when `read_uses_own_gitdir` agrees, and any exception approves nothing.
  - `read_location_options` follows every `-C` from the payload cwd and resolves the last
    `--git-dir` against where those `-C`s leave it, as git does.
  - It only has to handle the options `git_location_args` lets through (`-C`, `--git-dir`,
    `--work-tree`), so the two parsers cannot disagree about where the subcommand starts.
  - `discovered_gitdir` walks up from the realpath and stops at the first directory with a
    `.git` entry or a `HEAD`. Git never stops earlier than that, so the walk cannot look
    past a directory git would use.
  - `trusted_gitdirs` accepts the root's own git directory, its `commondir` target, or a
    direct child of `<common>/worktrees/`, all compared by realpath.
  - No subprocess runs on this path.
  - Every way it can fail leads to a prompt: a symlinked or unreadable `.git`, a missing
    `shared_rules` (empty constants), an attached `-C=`, or an empty `commondir`.
  - It adds no new deny and no new allow.
- **`own_checkout`** was split rather than changed: the `.git` reading moved into
  `dot_git_target` and gives the same answers. The gate's `hook-cloud-profile.sh` Q and X
  rows are green.
- **Named constants**: the new literals are `GIT_DIR_FLAG`, `GIT_COMMONDIR_FILE` (taken
  from `shared_rules.COMMONDIR_NAME`) and `GIT_WORKTREES_DIR`. The walk reuses
  `GIT_DOT_ENTRY` and `GIT_HEAD`.
- **Tests** (`self/tests/allow-repo-commands.sh`, run in both profiles):
  - They build a real repository with a real `git worktree add`, a nested `git init`, and
    a plant.
  - A `PLANT_LIVE` row first proves the plant really runs its commands under git, so the
    prompt rows test something live.
  - There is a prompt row for each of the four backlog spellings, plus variants: separate
    and relative `--git-dir`, a chained `-C`, a subdirectory of the plant, and the nested
    repository.
  - There are ALLOW rows for the root, its `.git`, `--work-tree`, and the linked worktree,
    both from the root and as the session's own root.
  - Every prompt row targets a path inside the root that `origin/main` approved, so each
    would have been red there.
- **Docs**:
  - `hooks/README.md`: "The git shape" paragraph and the approvals bullet now describe the
    check.
  - `self/tests/README.md`: the entry for `allow-repo-commands.sh` lists the new rows.
  - `NOTES.md` records seven rulings.
  - `self/BACKLOG.md`: only the targeted entry was removed.
- **Gate**: `./self/gate.sh` is green, and the report lists no check as SKIPPED.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.

## Behaviour changes for the approver (decided, not defects)

Each of these makes the hook prompt *more*. None of them can approve a read the hook
should not, and each follows from the rulings in `NOTES.md`:

- A read in a git **submodule** now prompts. The submodule's `.git` file points at
  `<root>/.git/modules/<name>`, which is not the root's git directory, its common
  directory, or a linked worktree. This is the "nested repository prompts" ruling applied
  to submodules.
- A **symlinked `.git`**, or a `--git-dir` that names a `.git` *file* rather than a
  directory, prompts.
- A directory inside the repo that holds a file named **`HEAD`** is treated as a git
  directory, so a read run from it prompts (ruling 2).

Optional test rows, not required for this feature: a symlinked `.git` and a `.git` file
whose `gitdir:` line names the plant would pin those fail-closed paths. Nothing depends on
them today beyond the code's own guards.
