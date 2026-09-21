# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **A vendored `agentTooling/.claude/settings.json` is a hook path that does not exist in
  the consuming repo.** This checkout's own settings file ships with the subtree, so a
  repo that vendors agentTooling gets `agentTooling/.claude/settings.json` naming
  `${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh` — a path that resolves to nothing
  there. Claude Code reads project settings from the project root, so nothing reads that
  nested file today and the consuming repo's own wiring at its root is unaffected; if a
  future version reads settings from subdirectories, the consumer inherits a hook command
  that cannot run. Closing it means either excluding `.claude/` from the subtree split or
  making the `--self` hook command resolve in both layouts. Assertion: a repo that
  vendors agentTooling and opens a session loads exactly one `allow-repo-commands.sh`
  hook, and it is the one at its own root.
  Raised by `permissions-policy-inherit`.

- **Two design points from the 2026-09-16 audit are still undecided.** `self/DESIGN-2026-09-16-lifecycle-restructure.md`
  §4 leaves both open, and this feature built neither: a **per-feature budget** in the
  manifest fence (the runners cap per pass, so a feature that reworks three times has no
  figure that can refuse the fourth), and **relaxing the `git stash list` deny** (the hook
  denies the whole `git stash` verb, so the read-only listing that would let an agent see
  whose stash it is about to step on is denied with it — `CONVENTIONS.md` tells a worktree
  session to find its own entry by tag, which that denial makes impossible). Neither is a
  defect; both are decisions nobody has taken. Assertions, once taken: a fence carrying a
  budget refuses a pass that would exceed the feature's remaining total; and `git stash
  list` is approved while every mutating `git stash` form stays denied.
  Raised by `sweep-retirement-and-audit-fixes`.
