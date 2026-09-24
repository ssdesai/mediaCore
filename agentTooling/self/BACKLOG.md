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

- **A start interrupted between `git worktree add` and its `<slug>: start` commit blocks
  its own slug for good.** `feature-start.sh` creates the branch and the worktree first
  (`worktree add -b`), then runs the setup hook and the gate, and only then writes and
  commits the feature directory. A refusal in that stretch leaves the worktree "for
  inspection" by design, and an interrupt leaves it too. A re-run then refuses the
  existing branch and worktree. The prune never takes a branch whose tip is still its
  `Created from` commit, since that is also what a concurrent start looks like. Agents
  may not delete refs. So only a human's `!` clears it, although the half-made start holds
  no work. Seen 2026-09-23: an interrupted `feature-start.sh --self
  carry-stream-sections` left `.worktrees/carry-stream-sections` at its base with no
  feature directory. Closing it means the start taking over its own abandoned
  half-start: branch unmoved since creation, no `<slug>: start` commit, clean worktree,
  **and** evidence that the earlier start is dead, such as a lock file carrying its PID,
  so a live concurrent start of the same slug is never taken. The prune would use the
  same predicate. Assertion: a start killed during its gate, re-run with the same slug,
  succeeds, while a second start of a slug whose first start is still running is
  refused.
  Raised by `carry-stream-sections`.

- **An annotated frozen report still carries renderer drift into another feature's
  commit.** `feature-capture.sh`'s annotate step re-renders every frozen record whose
  `also_claimed_by` it changed, and `report.py` renders the frozen data with the current
  code. So the re-rendered report also takes on whatever the renderer has gained since the
  record was frozen, and all of it lands in the closing feature's `<slug>: cost records`
  commit. On 2026-09-23, re-rendering the 28 frozen self reports with no streams changed
  most of them: new keys (`rounds`, `unmeasured_attempts`), reworded warnings, and the
  "Rates last verified" footer. `carry-stream-sections` stopped the data loss in the
  stream sections. It did not stop this, which is the same frozen data in the renderer's
  newer format. No figure is wrong, but a reviewer of feature X sees edits to feature Y that
  X did not cause, and every renderer or rate-table change makes the next annotation
  noisier. Three ways to close it:
  (a) accept it, since a re-render uses the current renderer by design;
  (b) a one-time self feature that re-renders the whole corpus, so the drift lands once in
  its own commit, repeated whenever the renderer changes;
  (c) have the annotate step update only the shared-session lines of a frozen report.
  Option (c) is the only complete fix, but it is a second, partial writer of
  `report.md`/`report.json`. Assertion, once decided: a feature's close that annotates an
  older record changes nothing in that record's `report.*` but `cost.shared_sessions[]`
  and the footnote under the Cost table.
  Raised by `router-built-pin`, from `carry-stream-sections`' probe.

- **`capture_planning.py` keeps its own `parse_manifest`.** `report.py`'s copy now
  imports `routing.parse_manifest`, the one the pinned-session predicate reads through;
  `capture_planning.py` still defines an identical function of its own, and
  `self/tests/session-claims.sh` monkeypatches that name on the module, so folding it in
  is a small change with a test to adjust rather than a free one. Assertion:
  `capture_planning.parse_manifest is routing.parse_manifest`, with session-claims.sh's
  counter still counting.
  Raised by `shell-write-rewrite`.

- **Long-context (above 200k input tokens) and other tiered pricing is not priced.**
  `analysis/rates_history.json` holds one flat rate per field, and `refresh_rates.py`
  reads only LiteLLM's five flat per-token fields, ignoring its
  `*_above_200k_tokens` variants — as the hand table before it did. A request whose
  prompt crosses the threshold is billed at the higher tier and priced here at the lower,
  so every such session is under-counted. Adding it changes which figures are correct,
  not just where the rates come from, so it needs its own decision (a per-request tier
  is invisible in an aggregate; `transcript.py` would have to price per message).
  Assertion: a transcript message with more than 200k input tokens on a model whose
  LiteLLM entry carries `input_cost_per_token_above_200k_tokens` prices at that rate, and
  one below the threshold at the flat rate.
  Raised by `litellm-pricing`.

- **Propagation has no cost record.** After every agentTooling PR, a session pulls the
  subtree into each consuming repo (`LIFECYCLE.md` → "Propagate"). Those sessions and
  their delegates are launched in `~/dev`, on no feature branch, and name no feature. So
  every capture's residue lists them as unclaimed, and no report counts them. As of
  2026-09-23 there were 24 such delegates totalling $16.55, spent propagating every
  agentTooling merge from 2026-09-16 (PR #44 or earlier) through PR #60. This is a gap in
  the design, like routing before `routing.json`, not a set of pins nobody made. Closing
  it means giving propagation its own record: written by `update.sh`, or by the session
  that runs the pulls, and keyed to the agentTooling PR or sha it propagated, so the
  residue stops listing that spend. Assertion: after a propagation round,
  `feature-capture.sh`'s residue lists none of that round's delegates, and some report
  shows their total.
  Raised by `litellm-pricing`.

- **Unclaimed delegates that belong to a feature in another repo.**
  `abdc44b0d582d0b92` (2026-09-22, $8.74) is the direct implementer for
  `vinylCatalogue/audio-checked-mark`: its brief opens with that `feature:` line, but
  its parent session was on `main`, so no route claims it. Pin it in that feature's
  manifest `subagents` in the vinylCatalogue repo, and re-capture there. Do it together
  with the pending vinylCatalogue repair, which needs a clean `main` there anyway.
  Two "very thorough exploration" delegates, `a64bd100d13188cc7` ($0.73) and
  `aed24720a93f38a51` ($0.95), belong to parent session `a60214fa`, and their briefs name
  no feature. Pin them to whatever feature that session went on to build, or record them
  as that session's routing overhead. Assertion: `capture_planning.py --list-subagents
  --unclaimed --everywhere` lists none of these three ids.
  Raised by `litellm-pricing`.
