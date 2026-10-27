# Orchestration

How to run the tier *above* the runners: a coordinator session automating the human
who would otherwise sit at a terminal running `run-batch.sh`. This tier appears when
work spans repos, or when several features interleave in one repo. It sits above
`AGENT_PLANS.md` (which governs the delegate authoring plans) and `RUNNER.md` (which
governs execution); nothing here changes either.

The one-line rule: **the architect plans; the coordinator runs.** For a feature under
roughly a thousand lines of diff there is no architect and no batch: **the implementer
builds** (`AGENT_DIRECT.md`), the coordinator runs the review pass, and the size rule
that picks between the two is in that file, from the measurements in `harness/EXPERIMENTS.md`.

## Roles

- **Coordinator** — the interactive session talking to the human. Keeps the smallest
  context in the system; owns every long-running pipeline as its *own* background
  shell; relays questions between delegates and the human. Does trivial mechanical
  steps itself with a few commands (`pr.sh`, manifest fixes, constraint checks)
  rather than delegating them.
- **Architect** — an opus delegate, one per feature. Takes the brief, makes the
  design decisions, bubbles design questions up through the coordinator, authors the
  plans per `AGENT_PLANS.md`, then writes `plans/features/<slug>/NOTES.md` and
  **terminates**. It never launches the batch and never watches one.
- **Implementer** — an opus delegate, one per feature, for the features
  `AGENT_DIRECT.md` routes away from the plan workflow. Takes the brief, slices the
  work into `CHECKPOINT.md`, writes and commits the acceptance tests, builds slice by
  slice keeping the checkpoint and `NOTES.md` current, runs the checks it touched,
  **commits and checkpoints, then stops** — its brief ends there. Its context is never
  resumed: if it dies, a fresh one is briefed to resume from the checkpoint
  (`AGENT_DIRECT.md` → "Checkpoint and resume"). The coordinator then runs the whole
  gate, `run-review.sh`, and `feature-close.sh` on the round it reports clean — an
  escalated round is a rework and a second review, routed like any other build.
- **Judgment one-shot** — spawned only for a failure the red-gate tier ladder could
  not settle. Briefed with `NOTES.md`, the failed plan's `.progress.md`, and the one
  relevant spec section — never "read the design doc". Dies on delivery.

## Coordinator shapes

Two, and the number of features decides which.

- **One feature → coordinate from inside its worktree.** `feature-start.sh --open`
  launches the session there (`LIFECYCLE.md` → step 2); it and every delegate it spawns
  carry the feature's branch and are claimed with no pin.
- **A wave of features → one coordinator, wherever it runs, spawning an implementer or
  architect per feature** and pinning each with `manifest.py <slug> pin-subagent <id>`
  as it spawns it. Never peer coordinators opened with `--open`, one per feature: twenty
  standing sessions each idling on a large context is the token leak below, twenty times
  over. The coordinator is the router that started them, so its own spend is routing
  overhead and it is never pinned. It writes each feature's review briefs and manifest
  prose itself, by the worktree path, without being refused — a write under the
  feature's `review/` or to its manifest `README.md` is not building (`LIFECYCLE.md` →
  steps 3, 5 and 6). It still runs each feature's review and close by the worktree
  copy's absolute path rather than `cd`-ing in, since a router whose transcript shows it
  building in a worktree — a `cwd` there, or any other write — is refused at that
  feature's close as its builder, and the refusal names the line that tripped it.
  A propagation round is this shape too: one `pull-agenttooling-pr<N>` hand feature per
  consuming repo, a delegate per pull, each pinned in its own repo (`LIFECYCLE.md` →
  "Propagate"). A pull run from a Claude Code cloud session needs `ssdesai/agentTooling`
  attached to that session (`add_repo`) before `update.sh` can fetch it (step 2 there).
  A pull that conflicts with no local edits is resolved by taking upstream's whole tree
  (`git rm -r` the prefix, `git read-tree --prefix=… -u MERGE_HEAD`) and committing the
  merge in progress, and a `broken` trailer chain is re-anchored by `update.sh` itself — a brief
  says both, and that the PR is merged with a merge commit (step 2 → "The trailer chain").
  The pull that first brings the chain check in still runs the older `update.sh`, so in an
  already-broken repo that one pull may conflict and is resolved the same way.
  When the coordinator runs in a Claude Code cloud container and the features are in
  other repos, the delegates are **cloud sessions**, not subagents — see "Cloud sessions"
  below.

### Cloud sessions

A coordinator in a Claude Code cloud container that runs a wave across repos — a
propagation round, or several self features at once — spawns one **child session** per
feature with the claude-code-remote MCP's `create_session`, not a local subagent: a
container holds one feature and pushes one branch
(`self/DESIGN-2026-10-05-cloud-execution.md` §2, §12), so a feature in another repo, or a
second feature in this one, needs a container of its own.

- **Assign each child its branch up front, with `outcome_branch`.** The convention is
  `claude/pull-agenttooling-pr<N>` for a propagation and `claude/<slug>` for a self feature
  — `claude/<slug>` either way, since a propagation's slug is `pull-agenttooling-pr<N>`.
  A child created without one has no branch to start on and improvises: on 2026-10-26,
  propagating agentTooling PR 90 into four repos with no `outcome_branch`, two children
  (one on a detached HEAD, one on `main`) cut `claude/pull-agenttooling-pr90` with
  `--branch`, one invented `pullAgenttoolingPr90`, and one sat on `main` until the
  coordinator sent it a name. `feature-start.sh`'s cloud refusal on the base or a detached
  HEAD now names `--branch claude/<slug>`, so a child that is missing one picks the
  conventional name, but the assignment is what makes it certain.
- **The brief is self-contained.** The child starts with nothing but its prompt, and it
  has no coordinator in its container to ask. The brief names the repo, the slug, the
  `--method` (`hand` for a propagation; a self feature's by step 1), the start command
  with `--branch <the outcome_branch>`, the review, and the standing close-on-clean rule:
  on `Verdict: clean`, run `feature-close.sh` straight away; on `escalated`, run the rework
  round. Name the assigned branch and say to create or push no other. Ask for the PR link
  or the exact blocker as the child's last line.
- **The child is its feature's coordinator, on that branch.** It runs the start, the
  build, the review and the close itself, in its own container. The parent pins nothing in
  the child's repo and writes no routing record there: the child's transcript lives in its
  own container, and its close captures it on its own branch. `outcome_branch` names the
  branch the child pushes, but the clone is not left on it: this feature's own session,
  created on 2026-10-26 with `outcome_branch: claude/cloud-wave-sessions`, opened on a
  detached HEAD. So the brief always passes `--branch <outcome_branch>`. That is harmless
  when the checkout is already on the branch, and when it is not, the start cuts the
  branch and the child is the feature's coordinator all the same — `from` at its first
  transcript instant, no pin, no routing record — since a container holds one feature
  (`self/features/cloud-branch-window-from`; design §3). Nothing in the child's "Next"
  lines asks for a pin, and the child runs none.
- **Name each child's model on `create_session`; never inherit the parent's by
  accident.** The repo's tiering ("Model tiering" below, `AGENT_PLANS.md`) applies to the
  session itself: the cheapest model that does the job, in the plan-suffix names
  (`haiku`/`sonnet`/`opus`). A hand-method coordinator whose shape is already decided — a
  propagation pull, a merge-and-re-close, a doc or script edit — is `sonnet` work; one
  that needs judgment — a design decision, rework to a conflicting PR's semantics,
  adversarial reading — is `opus`. The review executor's model is its plan suffix's,
  whoever coordinates. A parent on a higher tier passes `model` explicitly, so a wave does
  not inherit that tier by default.
- **A reclaimed child comes back on `main`.** When an idle child's container is reclaimed,
  the next message wakes it in a new container cloned on `main`, not on its feature's
  branch, and it cannot switch there: the hook refuses the switch and says so. The parent
  does not ask the child to switch; it launches a fresh session on the feature's branch
  (`create_session` with that branch) and briefs it to continue the feature
  (`LIFECYCLE.md` → step 2, "A restarted container is off its feature's branch").
- **The parent is a router.** Its spend is routing overhead: it opens several features and
  belongs to none of them. It is never pinned in a child's manifest, and it builds nothing
  in any child's repo.
- **The parent checks on children with `get_session` and `list_events`, never by polling.**
  No sleep loop, and no `send_later` per child per minute. Where it is enabled, a child
  whose turn fails wakes the parent with a child-session event; a child that finishes
  cleanly does not, and its `status_bucket` tells the two apart (`failed` against a
  plain idle `status`). For the rest, one
  `send_later` check-in a little past the expected end of the round, then `get_session`
  for each child's state and `list_events` (filtered with `kinds`) for its last reply.
  Once a child's PR is open, and its last line has given the link, `archive_session` it:
  the PR now carries the work, and an idle child holds a container.

**A session launched on the feature's branch is its coordinator, wherever it runs**
(`self/DESIGN-2026-10-05-cloud-execution.md` §3). Router or coordinator is derived from
the branch the session's checkout was on when `feature-start.sh` began, never configured:
on another branch — `main`, locally — it is a router and the start writes its routing
record; on the feature's own branch it is the coordinator, claimed by that branch under
`LIFECYCLE.md` rule 1 with no pin and no routing record, and the start opens the
feature's window at that session's first transcript instant so the capture selects it.
In a Claude Code cloud container that is every session: the container is the worktree,
and the session starts the feature on its assigned branch — or, given none, cuts it with
`--branch` from `main` or a detached HEAD, and is the coordinator all the same, since a
container holds one feature (`self/features/cloud-branch-window-from`).

## Why

Every agent wake re-bills its entire context, so an agent whose main activity is
waiting is a token leak. Measured on the first cross-repo run of this workflow:
three monitor agents at 300–380k context each took 100+ tool rounds apiece —
tens of millions of input tokens spent watching a pipeline that settles its own
failures (that is what the tier ladder is for). Interruption churn multiplies the
loss: a usage-limit kill or stall watchdog forces a resume, and resuming a large
context is expensive, while a dead architect costs nothing when everything it knew
is on disk.

The warm-context argument for keeping the architect alive through execution does not
survive contact: in practice the ladder settled essentially every failure without
design input, so the standing context was paid for and never used. `NOTES.md` is the
warm context, persisted, at a fraction of the cost.

## Rules

- Never make a delegate the parent of a runner. `run-batch.sh` runs as the
  coordinator's background shell; completion notifications wake the coordinator.
  Nobody polls, ever — no sleep loops, no "check the queue again". The permission hook
  holds the line: a `sleep` on any Bash line is sent back with "nobody polls: run it in
  the background and wait for the notification" (`hooks/README.md`).
- **The coordinator, never a delegate, owns any run longer than a few minutes** — the
  whole gate, a batch, a long suite (`self/DESIGN-2026-10-05-cloud-execution.md` §8). A
  delegate's brief ends at "commit and checkpoint, then stop", so a container restart in
  the middle of a long run costs no delegate: everything it knew is on disk, and only the
  run is lost. Re-run a gate under `GATE_RESUME=1` (the runners and `feature-start.sh`
  set it) and it skips the checks that already passed on that tree.
- **In a Claude Code cloud session, arm one `send_later` check-in before such a run**, a
  little past its expected end. A container restart kills the run and the notification it
  would have sent, and leaves the coordinator with nothing to wake it; the check-in is
  that wake. It is the session's tool, not a script's — the harness cannot call it — so
  this is doctrine, not code. One check-in, not a polling loop: on waking, read the
  run's output or re-run it, and arm the next only before the next long run.
- All state lives on disk: queues, manifests, gate reports, `NOTES.md`. Any agent
  must be killable at any moment with zero loss. If losing an agent would lose
  information, that information should already have been written down.
- Briefs point at files and sections, not documents. The brief for a judgment
  one-shot names the three inputs above and nothing else.
- Model tiering: opus for architecture and escalation judgment; sonnet for delegated
  mechanical work; the coordinator's own hands for anything that is just commands.
- Delegate interim messages are one or two lines. The final report follows the
  brief. If a delegate must die early anyway, its handoff contains only what is not
  recoverable from disk.
- The manifest's fence is the lifecycle scripts' to write, not a coordinator's
  (`LIFECYCLE.md`): `feature-start.sh` opens the window and records the base a stacked
  feature branched from, pinning nothing unless asked; `feature-capture.sh`, which
  `feature-close.sh` runs on the branch after it opens the PR, stamps the window's
  provisional end and warns about a delegate whose brief names this feature and that no
  route claims. The close is the coordinator's last command — it refuses any tree a clean
  review has not judged — and merging the PR is the step after it, after which the next
  `feature-start.sh` prunes the worktree. One branch, one worktree and one window per
  feature is what the naming rule buys — a coordinator that finds itself hand-editing
  those fields is working around a step it skipped.
- A delegate's transcript inherits the coordinator's `gitBranch`, so an architect
  spawned from `main` is invisible to the feature's `branches`. Pin its agent id in the
  manifest's `subagents` with `analysis/manifest.py [--self] <slug> pin-subagent <id>` —
  the id the Agent tool returned, or `capture_planning.py --list-subagents --unclaimed`
  finds it.
- **Every delegate brief opens with `feature: <repo>/<slug>`** — the repo's directory
  name and the feature directory it is for, on the first line, before anything else.
  That line is what `capture_planning.py --list-subagents --unclaimed` reads to
  propose the pin, and what a pin is checked against; a delegate without it can be
  attributed only by a human reading its prompt. After a run, `--unclaimed` must
  come back empty before the cost is quoted.

## NOTES.md

Written by the architect as its last act, in the feature directory next to the
queues. Contents, tersely: the rulings that are judgment rather than spec, with a
one-line rationale each; deviations from the design doc, and why; open questions for
the coordinator or the human; the exact resume/state-inspection commands for this
feature; anything a cold successor would otherwise re-derive. It is the standing
replacement for the architect's head.
