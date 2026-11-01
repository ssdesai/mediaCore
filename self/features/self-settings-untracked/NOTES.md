# Notes: self-settings-untracked

Rulings made during the direct build, one line of rationale each. The design itself is
the backlog ruling of 2026-09-26: stop tracking agentTooling's own
`.claude/settings.json`, generate it in `self/worktree-setup.sh`, check it in
`self/gate.sh`.

## Rulings

- **No drift to settle.** `wire-settings.py --self --check` reported `in-sync` against the
  tracked file before anything changed, so the generator needed no hand addition taught
  to it; the untracked working copy is byte-identical to what it writes.
- **The vendored layout is decided in `wire-settings.py`, not in the shell callers.**
  Under `--self`, a `--repo` with no `.git` of its own and one in an ancestor is a
  vendored agentTooling: `--check` passes on the file's absence and fails (`UNWIRED`) on a
  nested copy, and `--write` writes nothing. Without it, untracking would have turned
  `self/gate.sh` red forever in that layout (a `--self` start from a consuming repo would
  refuse on its base gate), and the setup hook would have recreated the very nested file
  the backlog entry was about. One rule, read by the setup hook, the start and the gate
  alike. A directory with no git anywhere above it counts as standalone — the shape of
  `hook-wiring.sh`'s scratch repos, which therefore needed no change.
- **A nested copy in a vendored tree fails the setup hook** (`--write` reports `UNWIRED`,
  `set -e` exits 1, the start refuses). Deliberately loud: it is the defect this feature
  closes, and `wire-settings.py` never deletes a file it did not write.
- **The primary checkout's hook point is every `--self` start, not the fast-forward
  path.** The fast-forward path is by construction the OLD copy of `feature-start.sh` (that
  is why it exits 3 asking for a rerun), so code added there cannot run on the one
  fast-forward that deletes the file. The rerun it demands is the new copy; the block sits
  right after the stale-primary check and writes the primary's file when it is missing,
  printing `settings  … regenerated`. Every later start does the same, which also covers a
  primary updated with a plain `git pull`.
- **Only when missing.** A present-but-drifted primary file is left alone — a human may be
  experimenting in it; the gate reports drift. A failed regeneration is a `warn` line
  naming the command, never a refusal: the start's job is the worktree.
- **Failure messages name the exact command** with absolute paths —
  `python3 -B <abs>/hooks/wire-settings.py --self --repo <abs root> --write` — in place
  of the old `--repo <dir>` placeholder, so the gate's failure can be pasted as it stands.
  The `--write` success line no longer says "commit it".
- **The consumer-layout setup hook (`templates/plans/worktree-setup.sh`) is unchanged.**
  A consuming repo's `.claude/settings.json` is at its own root, written by
  `sync-plans.sh`, and committed in that repo, so its worktrees inherit it; nothing there
  was ever generated per checkout. No template version bump.
- **Existing consumers heal on their next pull.** `update.sh` pulls the subtree with
  `--squash` from agentTooling's tracked tree, so the first pull after this merges deletes
  the `agentTooling/.claude/settings.json` earlier pulls left; their root wiring is
  untouched. Recorded in `LIFECYCLE.md` → "Propagate".
- **The gate test drives the real `self/gate.sh`** in a staged sandbox and reads only its
  settings section; every other section fails there because no other suite is staged.
  This keeps the test black-box (through the gate, not through `wire-settings.py` alone)
  without recursing into the full suite.
- **A post-merge git hook to regenerate was considered and rejected**: `.git/hooks` is not
  versioned, is denied to agents, and would need installing per clone — the start already
  runs in every checkout that matters.

## The one-time regeneration after this merges

When the primary checkout fast-forwards over this merge, git deletes its
`.claude/settings.json` (tracked before, untracked after), and sessions launched there run
with no hook until it is back. The rerun `feature-start.sh --self` asks for restores it;
by hand, from the primary's root:

    python3 -B hooks/wire-settings.py --self --repo /Users/sahildesai/dev/agentTooling --write

The `~/dev` parent-folder session wires the primary's `hooks/allow-repo-commands.sh`
directly from `~/dev/.claude/settings.json` and is unaffected.

## Open questions

- None.
