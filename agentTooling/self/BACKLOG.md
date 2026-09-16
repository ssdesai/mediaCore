# Backlog

Escalations and decisions left open by finished features — one entry per item, phrased as
the assertion that would catch it, with the feature that raised it. Remove an entry in the
feature that closes it. Same shape as a consuming repo's `plans/BACKLOG.md`; this one is
agentTooling's own, for the harness rather than for a product.

- **Two features started by one router, merged in turn, conflict on the routing record.**
  `feature-start.sh` writes `plans/routing/<session-id>.json` on each feature's branch.
  Two branches cut from the same `main` before either merged each *add* that one path with
  a different `features_started` — an add/add conflict on the second merge, which a human
  resolves by taking the side with the later `captured_at`: a router only grows, so that
  side names both features and the other one loses the newer feature's "routed by" line
  and its Routing-table row (design 2026-09-16 §3.4, accepted there). Once `main` carries the file, every later branch
  modifies rather than adds it and merges cleanly, and `feature-capture.sh` refreshing the
  record from a fully flushed transcript converges the content. Left as accepted: the
  alternatives are a path per (router, feature), which breaks the "one copy cannot
  disagree with itself" rule, or a merge driver. Assertion: two features started by one
  router and merged in turn reach `main` with one routing record naming both, with no
  hand resolution. Raised by `start-procedure-and-routing`.

- **A worktree's `hooks/` is outside the policy's own Edit deny.** The deny rule
  `--self` writes is `Edit(/hooks/**)`, anchored at the project root. For a session whose
  project root is the primary checkout that is the primary's `hooks/`, and the copy in
  `.worktrees/<slug>/hooks/` is editable with the Edit tool — which is how this feature's
  own hook change was made. A session launched *inside* the worktree is covered, since its
  project root is the worktree. Closing it means a `**/hooks/**` form under `--self`, at
  the cost of matching an unrelated `hooks/` directory anywhere in a consuming repo.
  Assertion: an Edit to `<primary>/.worktrees/<slug>/hooks/allow-repo-commands.sh` is
  denied in a session rooted at the primary. Raised by `start-procedure-and-routing`.

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

- **A bare entry-point name is approved against a file bash will not run.** The hook's
  entry-point approvals match `gate.sh` and `check-plans.sh` by basename and confine the
  PATH they see to the root, but a command written as `check-plans.sh` with no directory
  component is resolved by bash along `$PATH`, not from the cwd — so the hook approves a
  file it checked in the repo while bash runs whichever copy `$PATH` finds first, which
  may be outside it. `self/tests/allow-repo-commands.sh` currently expects the bare form
  to be approved. Assertion: `check-plans.sh` and `gate.sh` are approved only when the
  word carries a directory component (`./check-plans.sh`, `self/gate.sh`), and the bare
  form prompts.
  Raised by the `permissions-policy-inherit` review.

- **`git branch --list <pattern>` is denied as a branch creation.** `git_mutates` reads any
  positional argument to `git branch` as a name to create or rename, but after `--list` or
  `-l` the positional is a glob to filter by; the command reads and moves nothing.
  Assertion: `git branch --list 'feat*'` is not denied, and the test's list of
  read-only git commands includes it.
  Raised by the `permissions-policy-inherit` review.

- **The settings-drift check sees additions, not the whole file.** `wire-settings.py
  --self --check`, which `self/gate.sh` records, fails only when an entry the constants
  generate is missing from `.claude/settings.json`; an allow rule added by hand, or the
  hook command repointed at the consuming-repo path where it would never run, leaves the
  gate green — while `hooks/README.md` and `self/README.md` both say a hand edit fails it.
  Two smaller drifts sit beside it: the comment on `BASH_DENY_RULES` omits denies the hook
  applies (`git branch <name>`, `git worktree move`/`lock`), and the module docstring
  names a `GIT_MUTATING_*` constant that is spelled `GIT_ALWAYS_MUTATING` and its flag
  sets. Assertion: the gate fails when `.claude/settings.json` differs from a fresh
  `wire-settings.py --self --write` in any byte, and the docs describe exactly the check
  that runs.
  Raised by the `permissions-policy-inherit` review.

- **`report.py --self <slug>` on a feature not yet captured is a traceback.** Before the
  close writes `planning.json`, the single-feature report dies in `run_single_feature`
  with `FileNotFoundError` instead of saying the feature has not been captured and which
  command captures it. Assertion: the report on an uncaptured feature exits non-zero with
  one line naming `planning.json` and the capture step, and no traceback.
  Raised by the `permissions-policy-inherit` review, 2026-09-16.

- **A plan's minutes come from the attempts that reported one, and nothing says which
  attempts did not.** `report.py`'s `duration_from_usage` sums the live sidecar's
  `attempts[].duration_ms` and stops there, so a resumed plan whose first attempt was
  killed and whose second completed reports only the second's minutes, is in neither
  `time.missing_duration_plans[]` nor `time.recovered_duration_plans[]`, and marks no
  row — the total reads as whole when it is short by however long the killed attempt
  ran. The dollars do not have this hole: `compute_cost_rollup` walks the attempts
  individually and reads prior sidecars too, taking each session's figure from the first
  copy that has one (`ATTEMPT_FIGURE_FIELDS`, live before prior). Closing it means giving
  the time roll-up the same per-attempt, prior-aware walk — a recovered span for the
  killed attempt beside the measured figure for the completed one, which then has to
  decide what a cell holding both a wall clock and a transcript span means and how it is
  marked. `recovered-duration-lower-bound` deliberately did not: it credits a recovered
  span only where the plan has no measured duration at all, on the ground that blending
  the two inside one cell produces a figure that is neither, and the mixed case is rarer
  than the wholly-unmeasured one it was built for. Assertion: a plan with one measured
  attempt and one attempt whose duration was recovered reports both, and its bucket says
  which part of the figure is a lower bound.
  Raised by `recovered-duration-lower-bound`.

- **A co-claimant still in flight is unbounded in this feature's split.** The share walk
  reads every other claimant's `session_window` as it stands, and a feature that has not
  closed yet carries `to: null` — so on a coordinator both features claim, the in-flight
  one takes an equal share of every response from its `from` to the end of the transcript,
  including the stretch after its own work stopped. `claim-window-precision` closed the
  same defect for the CAPTURING feature, by stamping its own `to` from the last instant of
  its branch-selected sessions, and deliberately did not close it for the others: bounding
  another feature's claim would mean walking that feature's transcripts from here, on
  every capture, to derive a bound its own close is about to derive anyway — and a figure
  derived here would then disagree with the one that feature freezes. Its own close bounds
  its own record, and re-capturing this feature afterwards picks the tightened bound up.
  Assertion: a feature captured while a co-claimant's `to` is still null, then re-captured
  after that co-claimant closes, reports a larger share the second time, and the first
  record says which of its claimants were still open.
  Raised by `claim-window-precision`.

- **A pinned delegate that cost nothing is listed as unclaimed forever.** The ledger's
  subagent side is written from the capture's priced entries (`add_session_claims` over
  `costs`), so a delegate whose transcript holds no billable response — a rework one-shot
  killed at spawn, two lines and 0.3 seconds — is captured into `planning.json`'s
  `subagents[]` as `selected_by: pinned`, and never reaches the ledger. `--list-subagents
  --unclaimed` reads the ledger, so every sweep prints the pin that is already there and
  tells the human to write it, which is the exact advice `manifest_pinned_subagents` was
  added to stop for `--for`. Seen on `humanNetworkMap/node-query-payload`'s
  `a3cb921a319b2c2ee` on 2026-09-10. Assertion: a manifest pinning a delegate whose
  transcript has no `assistant` line captures it, the ledger names the feature for that
  id with `cost_usd` 0, and `--list-subagents --unclaimed` does not list it.
  Raised by the 2026-09-10 delegate sweep.

- **The head's remedy has no tool.** The bounded opening stretch (`head_bound`) leaves the
  part of a session's head nobody planned in `unclaimed_usd`/`unclaimed_duration_s`, and
  the "unclaimed by any feature" warning names the two repairs that can reach it: pin the
  session into the feature the work belongs to, or move the earliest claimant's `from`
  back. The first has a tool (`sessions` in the manifest fence); the second does not —
  `analysis/manifest.py` has `set-window-to` and no `set-window-from`, so the warning ends
  by telling the reader to edit the fence by hand, which is the one thing every manifest
  and `LIFECYCLE.md` say not to do. `bounded-opening-stretch` deliberately did not build
  the twin: `set-window-to`'s value is that it refuses to WIDEN a bound already stamped
  from evidence, and the symmetric refusal for `from` is not the same rule — moving `from`
  back is a widening, which is exactly the operation being asked for, so the command would
  be a bare writer with no guard, and what stops a `from` from being moved to claim a head
  the feature did not plan is judgement, not arithmetic. Assertion: a `from` moved back to
  cover a disclosed head is applied by a command that shows the old and new bound and
  refuses to move it PAST the session's own first instant, and the unclaimed warning names
  that command instead of "by hand".
  Raised by `bounded-opening-stretch`.

- **A start with no slug reads the next line's first word as its slug.**
  `routing.slug_of_start_command` takes the argument after `feature-start.sh [--self]`
  from wherever the regex lands, and with `re.MULTILINE` a Bash call whose start line ends
  without a slug hands it the first word of the following line — `./feature-start.sh
  --self` then `ls` records a feature named `ls`. The inverse also holds: a start split
  over two lines with a trailing `\` yields no slug, so that session is never a router.
  Assertion: the slug is taken from the same line as the script token, a start with no
  slug on its line yields nothing, and a `\`-continued start yields its slug; all three in
  `self/tests/routing-record.sh`.
  Raised by the `start-procedure-and-routing` second review.

- **`open-session.sh` quotes the worktree path against spaces only.** Both copies wrap the
  path in single quotes inside the `osascript` string, which a path containing `'`, `"` or
  `\` still breaks. Closing it means escaping the path for AppleScript's string and the
  shell inside it, and moving both copies to `template-version: 3` with the hash
  re-recorded in `TEMPLATE_VERSIONS`. Assertion: a worktree path holding each of those
  three characters reaches `claude` intact.
  Raised by the `start-procedure-and-routing` second review.
