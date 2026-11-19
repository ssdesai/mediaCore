# 01 — review: hook-planted-gitdir

Review the feature against the spec below, not against the builder's report. "No findings"
is a legitimate verdict: say so plainly when the diff holds to every contract here.

## What the feature was supposed to do

Close one gap from `self/BACKLOG.md`: **the read-only git approvals trust a git directory
planted in the tree.** A plain-file bare gitdir under, say, `plans/evil/` (`HEAD`,
`objects/`, `refs/`, and a `config` holding `core.fsmonitor = <cmd>` or
`diff.external = <cmd>`) made each of these approved silently, and git ran the command:

- `git -C <root>/plans/evil status`
- `git -C <root>/plans/evil diff --no-index a b`
- `cd <root>/plans/evil` as its own call, then `git status` (the payload's `cwd` is the
  planted directory)
- `git --git-dir=plans/evil log -1`

After the feature, each of those prompts (no output from the hook — never a deny, never an
allow). The check is the real-gitdir check `own_push_allowed` already makes: the git
directory git would use for the read must be the root checkout's own, found by walking the
filesystem (`own_checkout`), or a linked worktree of it. A real linked worktree under the
root (a feature worktree under `.worktrees/`, whose `.git` file names
`<common dir>/worktrees/<name>`) stays approved, as do the ordinary read-only git approvals
in the root (`git status`, `git -C <root> log`, `git --git-dir=<root>/.git log`,
`git --work-tree=<root> status`, …).

The check itself must not run anything the planted config names: it may not run git
against an unvetted git directory (the hook README already promises no git probe on a read,
`self/tests/hook-cloud-profile.sh` X1–X3).

The BACKLOG entry for this gap is removed in this feature.

**Excluded** (each its own BACKLOG entry; a finding about one of them is non-blocking and
belongs in the backlog, not in this round): a writable git config generally (the real
`.git/config`, global or included configs); `GIT_CONFIG`, `GIT_DIR`, `GIT_EXEC_PATH` or any
other git variable in the hook's own environment; the `.git` Edit-deny check in consuming
repos; `gate.sh`/`check-plans.sh` basename matching; the `analysis/` pins;
`--config`/`--config-file`; the orchestrator allowlist's own git reads.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/allow-repo-commands.sh`: the read-only git approval (`subcommand_allowed` →
  `git_allowed`) is approved only when the git directory the command would use — given by
  `--git-dir` when present, else discovered from the payload `cwd` moved by every `-C` —
  is the root checkout's git directory, its common directory, or a direct child of
  `<common dir>/worktrees/`, all compared by realpath. Discovery must stop at least as
  early as git's: at the first directory, walking up from the resolved location, that holds
  a `.git` entry or is itself shaped like a git directory (holds `HEAD`). Any failure
  approves nothing. No new deny, no new allow.
- `own_push_allowed`'s behaviour is unchanged (`self/tests/hook-cloud-profile.sh` Q-rows
  all still pass); any refactor of `own_checkout` keeps its answers.
- No git subprocess on the read path (X1–X3 stay green).
- Named constants for every new literal (`CONVENTIONS.md` → "Named constants").
- Tests, in `self/tests/allow-repo-commands.sh` (both profiles) and/or
  `self/tests/hook-cloud-profile.sh` as `self/tests/README.md` places them: a row per
  spelling above with a planted bare gitdir, seen prompting; rows showing the root
  approvals and a real linked worktree's approvals unchanged. Each new prompt row should
  have been red on `origin/main`.
- Docs: `hooks/README.md` where it describes the read-only git approvals ("The git shape"
  and the global-options paragraph) says what is now checked; `self/tests/README.md`'s
  entry for each test file touched lists the new rows; the feature's `NOTES.md` records
  the rulings.
- `self/BACKLOG.md`: the "planted in the tree" entry is gone and no other entry changed.
- `./self/gate.sh` green.

## Verdict
