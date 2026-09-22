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

- **A pipe into an interpreter followed by a redirect is not read as one.**
  `piped_into_interpreter` counts every non-flag word after the interpreter as a script,
  and `opaque_segments` keeps a redirect's operator and target as words, so
  `cat <<'EOF' | python3 > out` (and `ls | sh > out`) reads as `python3` running a script
  named `>` and prints nothing, where the same line without the redirect is the opaque
  deny. Found while building the shell-authored-file shape, whose own reader
  (`redirect_members`) already takes redirects out of a member's words; not fixed there
  because it is a different shape's defect. Assertion: `cat <<'EOF' | python3 > out\n…\nEOF`
  and `ls | sh > out` are denied with `OPAQUE_DENY_REASON`.
  Raised by `shell-write-rewrite`.

- **`capture_planning.py` keeps its own `parse_manifest`.** `report.py`'s copy now
  imports `routing.parse_manifest`, the one the pinned-session predicate reads through;
  `capture_planning.py` still defines an identical function of its own, and
  `self/tests/session-claims.sh` monkeypatches that name on the module, so folding it in
  is a small change with a test to adjust rather than a free one. Assertion:
  `capture_planning.parse_manifest is routing.parse_manifest`, with session-claims.sh's
  counter still counting.
  Raised by `shell-write-rewrite`.
