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

Two, and the number of features decides which. Whichever it is, **launch the coordinator
inside a repository checkout** — the agentTooling checkout, or the repo that holds most of
the work, on its default branch — never in a directory above the checkouts. That is where
its branch is recorded, and where that repository's `.claude/settings.json` wires
`hooks/allow-repo-commands.sh`, so the shell rules and the `Agent` brief-header rule hold in
the coordinator itself. A session launched above the checkouts — a Claude Code cloud
session with several repositories starts in their parent directory unless its starting
directory is chosen in the app — loads no repository's settings, so no hook and no
`session-start.sh` runs in it, and it records branch `HEAD`. Nothing in a repository can
detect that from inside the session; the first place it shows is a delegate's
`feature-start.sh`, which (cloud profile) prints a `warn` naming the coordinator and
`orchestration-start.sh <slug> --coordinator --session <id>` (with `--self` for a `--self`
start) when that session works outside the start's checkout and no record names it (`analysis/coordinator_check.py`).

**A coordinator of several features records its own cost, once.** Its delegates are
claimed by the features they build (their `feature: <repo>/<slug>` header, or a pin); its
own transcript — the briefs, the analysis, the reading of results — is claimed by no
feature, wherever it was launched, and pinning it to one feature would bill the others' share
to that one. So at the start of a wave, or afterwards with `--session <id>`, run
`orchestration-start.sh <slug> --coordinator`, `manifest.py --orchestration <slug>
add-feature …` per feature (`report=` its `report.json`, relative to its own repository:
`plans/features/<slug>/report.json` for a feature of the repo the record is read in, priced
from that repo's root with no `--checkout`; `self/features/<slug>/report.json` for an
agentTooling one — never `session=` or `branch=`, which are an orchestrator's and which
`manifest.py` refuses on a coordinator record, since a coordinator record carrying them is
read as a role),
and at the end `set-window-to now`, `orchestration-capture.sh <slug>` and `report.py
--orchestration <slug> --checkout <repo>=<path> …`. The record is written to the repo the
coordinator works in — `plans/orchestrations/<slug>/`, beside `plans/features/`, committed
with that repo's own work — and the features of that same repo need no `--checkout`: their
`report` paths resolve from its root. (In agentTooling itself, every one of these takes
`--self`, and the record is `self/orchestrations/<slug>/`.) It is a **coordinator record**, priced as the
coordinator's own line beside the features, and **no role** — nothing is refused in the
coordinator or in the delegates that share its session id (`LIFECYCLE.md` →
"Orchestration records"; `self/features/coordinator-cost-records/`). An orchestrator — the
cloud-sessions shape below, with child sessions of their own ids — keeps its ordinary
record, which is the role.

- **One feature → coordinate from inside its worktree.** `feature-start.sh --open`
  launches the session there (`LIFECYCLE.md` → step 2); it and every delegate it spawns
  carry the feature's branch and are claimed with no pin.
- **A wave of features → one coordinator, wherever it runs, spawning an implementer or
  architect per feature** and pinning each with `manifest.py <slug> pin-subagent <id>`
  as it spawns it. Never peer coordinators opened with `--open`, one per feature: twenty
  standing sessions each idling on a large context is the token leak below, twenty times
  over. The coordinator is the router that started them, so its own spend is routing
  overhead and it is never pinned; in the cloud, where no routing record is written, its
  coordinator record (above) is where that spend is counted. It writes each feature's review briefs and manifest
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
- **The child runs the start in the background and waits.** The start runs the base gate
  (minutes) and refuses a tree that changes while it runs, so a child that edits before the
  start's exit notification gets a refusal and a lock (`LIFECYCLE.md`, cloud start); its
  start commit carries the feature directory only.
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
  (`haiku`/`sonnet`/`opus`/`fable`). A hand-method coordinator whose shape is already decided — a
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
- **A continuing child can come up detached at its branch's tip, and a fresh session
  does not cure it.** On 2026-10-27, twice in a row (humanNetworkMap,
  `pull-agenttooling-pr99`), a session created with `source_revision` and
  `outcome_branch` both set to an existing branch opened with HEAD detached exactly at
  `origin/<branch>` and the local branch, cached from an earlier clone, 12 commits
  behind. The child fixes this one itself: the hook's reason and `session-start.sh` name
  `attach-branch.sh <branch>`, which re-attaches HEAD moving nothing and refuses any
  other shape. The parent's brief for a continuing child can say so up front
  (`LIFECYCLE.md` → step 2, "A cached clone comes up detached at its branch's tip").
- **A new feature always gets a new branch, normally in a new child session; a
  squash-merged branch is never taken over.** One feature per child session and per branch.
  Once a session's feature PR has merged, the next feature is a new child session on a new
  `claude/<slug>` branch (`outcome_branch`, as above), never a reuse of the merged branch:
  a squash merge leaves that branch carrying commits git does not see on `origin/main`, so
  `feature-start.sh` refuses a next feature there, and a start refuses a merged feature's
  branch anyway (`LIFECYCLE.md` → "Orchestrator and implementer sessions"). The
  orchestrator's own records branch, if squash-merged mid-wave, gets a normal merge of
  `origin/main` (no reset, no force-push) or a fresh records branch. There is no takeover to
  automate: matching a branch's commits to `main` by `git patch-id` ignores where in a file
  a change lands, so a branch edit to one of two identical blocks looks "already on main"
  when `main` edited the other, and a force-push would silently lose it (a prototype that
  did this, `claude/start-squash-merged-branch`, was parked for that reason).
- **The parent is a router.** Its spend is routing overhead: it opens several features and
  belongs to none of them. It is never pinned in a child's manifest, and it builds nothing
  in any child's repo.
- **A parent that opened an orchestration record is held to it.** Its session id is the
  record's `session`, so `feature-start.sh`, the four runners and `feature-close.sh` refuse
  in that session and the hook denies them, and an `Agent` delegate whose prompt opens with
  a `feature: <repo>/<slug>` header, naming the record and the remedy: a child session per
  feature (the parent's own delegates open `feature: none — <reason>`, which passes)
  (`LIFECYCLE.md` → "Orchestrator and implementer sessions"). The parent is started from
  `plans/ORCHESTRATOR_SESSION_BRIEF.md` (`templates/plans/` in agentTooling itself).
- **The parent gets its own branch from its start: `orchestration-start.sh … --branch
  claude/<slug>`.** A cloud session created with no branch comes up on a detached HEAD, and
  once its record exists its Bash allowlist holds no `git checkout -b` (on 2026-11-17 the
  orchestrator created and pushed its branch through the GitHub API instead). So in the
  cloud the start refuses a detached HEAD or `main` without `--branch`, naming `--branch
  claude/<slug>`; given it, it cuts that branch off `origin/main` before it writes the
  record — refusing a name origin already has (asked with `git ls-remote`, not the local
  cache) or a merged feature's manifest names — then commits the record on it and pushes
  it. `--branch` takes `claude/<slug>` only, the slug matching the lifecycle's slug pattern:
  any other name (`main`, `+main`, `origin/main`, …) is refused before anything is written.
  Pass the parent's `outcome_branch` when it is such a name (`self/features/orchestration-start-branch-v2/`).
- **The parent's Bash is an allowlist** (`hooks/README.md` → "The orchestrator role";
  `self/features/hook-role-hardening/`). Once its record names it, every Bash command it
  runs is denied unless every command on the line is one of: a reader over literal paths
  (`ls`, `cat`, `head`, `tail`, `wc`, `grep`, `rg`, `find` without `-exec`/`-delete`,
  `sed -n '<N>p'`, `stat`, `du`, `jq`, `diff`, `sort`, `uniq`, `cut`, `tr`, `date`, `pwd`,
  `echo`, `printf`); `git status|log|diff|show|rev-parse|ls-files`, `git branch
  --show-current`, `git remote -v`, `git worktree list`, `git fetch origin <branch>`;
  its records PR — `git add <files>` (existing regular files only), `[mkdir -p
  plans/orchestrations && ] git mv agentTooling/self/orchestrations/<slug>
  plans/orchestrations/<slug>` from the consuming repo's root for its OWN record stranded at
  the old vendored place (the remedy the start's refusal prints; approved outright, and no
  other `git mv` or `mkdir`), `git commit -m "<literal>"` or `-m "$(cat <<'EOF' …
  EOF)"`, `git push -u origin <branch>` (the branch's name written out: a push that is
  approved names its branch as a literal), `gh pr create --title …
  --body …`, `gh pr view|list|checks`; and its record's tools — `orchestration-start.sh`,
  `orchestration-capture.sh`, `analysis/manifest.py [--self] --orchestration …`,
  `analysis/report.py [--self] --orchestration <slug>`,
  `analysis/capture_planning.py --list-sessions|--list-subagents` (this checkout's own files,
  resolved against the cwd). No `$`, glob, `git grep`, refspec, test runner or other program:
  anything else goes to a SEPARATE session — `create_session`, or `send_message` to an
  implementer session — or to the human. An in-process subagent is no way out: it shares the
  parent's session id, so it has the Read, Grep and Edit tools but the same Bash list. Other
  sessions are not affected.
- **The parent checks on children with `get_session` and `list_events`, never by polling.**
  No sleep loop, and no `send_later` per child per minute. Where it is enabled, a child
  whose turn fails wakes the parent with a child-session event; a child that finishes
  cleanly does not, and its `status_bucket` tells the two apart (`failed` against a
  plain idle `status`). For the rest, one
  `send_later` check-in a little past the expected end of the round, then `get_session`
  for each child's state and `list_events` (filtered with `kinds`) for its last reply.
  Once a child's PR is open, and its last line has given the link, `archive_session` it:
  the PR now carries the work, and an idle child holds a container.
- **Steer a child with `send_message`; read its answer in its transcript.** A cloud child
  receives the parent's message as a turn of its own, but cannot be relied on to message
  the parent back: what it says in answer is read with `list_events`, and its last line
  (the PR link or the exact blocker) is the report.
- **Permission prompts are answered in each child's own session.** A child's Bash runs
  under the same hook as any session, so a command it asks about (a lifecycle write such
  as `feature-start.sh` or `feature-sync.sh`, an unlisted program) waits for a human in
  THAT session; the parent cannot answer it, and a child stopped on one reads as idle in
  `get_session`. The human approves it in the child's own session in the Claude app.
- **Overlapping features merge in PR order, and the later one does the merge.** When two
  children touch the same files, the first PR lands as it is. The second child then runs
  `feature-sync.sh [--self] <slug>` to merge the new `origin/main` into its branch with an
  ordinary merge commit — never a rebase, a reset or a force-push (`LIFECYCLE.md` rule 2) —
  resolves any conflict, renumbers any migration or test id that now collides with the
  first's, keeps every sibling's fields in the shared schemas and fixtures, and re-runs the
  gate and a review scoped to the merge before its own close. The parent checks a PR's
  base includes the current `main` before it merges it. In the 2026-11-17 wave each
  humanNetworkMap claim feature added a migration and test-spec ids that collided with a
  sibling's, and every later child did this by hand
  (`self/orchestrations/tooling-wave-2026-11-17/ORCHESTRATOR-STATE.md`).
- **About five concurrent Opus children is the practical usage-limit ceiling.** In the
  2026-11-17 wave four concurrent Opus children all hit the five-hour usage limit within
  about half an hour of each other. A usage-limit stop is reported to the owner once; the
  parent does not resume the children in a loop, but once after the reset, each told to
  re-check its state and re-run any gate or review the stop cut off.
- **The parent's own cost is the orchestration record's.** It runs no start, so no routing
  record names it and no feature's capture prices it; `orchestration-capture.sh` prices its
  transcript and its own `feature: none` delegates, and `analysis/report.py --orchestration
  <slug>` sets that overhead beside every feature it ran (`LIFECYCLE.md` → "Orchestration
  records").

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
- A security audit escalates a round only on a blocking finding (`LIFECYCLE.md` → "The
  security audit"), and only a regression is blocking. The non-blocking findings of a clean
  report, a pre-existing silent allow included, are filed in the BACKLOG by the coordinator
  before the close, not reworked in the round: after the clean verdict, as one commit
  touching only the BACKLOG file (`self/BACKLOG.md`, or `plans/BACKLOG.md` in a consuming
  repo) under the subject `<slug>: backlog`, the one coordinator commit `feature-close.sh`
  accepts after the judged head (`LIFECYCLE.md` → "6. Close").
- **The orchestrator writes or supplies the owner's brief, and merges by it**
  (`LIFECYCLE.md` → "The owner's brief and the conformance check"). The owner's request goes
  into the feature as `OWNER_BRIEF.md` — the words the owner used, unchanged, never a
  paraphrase — written by the orchestrator to a file and handed to `feature-start.sh
  --owner-brief <file>` (the implementer brief's "Owner's request (verbatim)" section is that
  text, and its start line carries the option), or committed on the branch before the
  review. Number the owner's items — as `### N.` headings, or as a top-level numbered list
  (`1. …` at column 0) when the owner wrote them that way — so each is checked on its own
  row; a brief with neither is one item. It is the yardstick every review and the
  independent conformance check judge the diff by. **An orchestrator never merges a PR whose "Deviations from the brief" section is
  non-empty — its title carries `[deviations]` — without the owner's word:** it puts the
  section to the owner and merges only on their say-so. It may merge a clean PR without
  asking only when all four are present: the owner brief, an all-`done` acceptance table, an
  agreeing conformance check (the close already refuses anything less) and no `[deviations]`
  mark on the title. A PR from a feature with no owner brief has none of the first three, so
  it is the owner's call to merge, not the orchestrator's.
- **One gap per hook feature.** A coordinator brief for a fix under `hooks/` names one
  gap. New findings a round turns up (an audit's, a review's, the implementer's own) go to
  the BACKLOG, not into the open feature: each added gap cost a full gate, review and audit
  round. The audit's own limit is the round cap in `LIFECYCLE.md` → "The security audit".
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
- **Never move bytes through a model.** A file copied between repos by pasting it — base64
  included — through a prompt came out corrupted. Copy with git instead: `git show
  <rev>:<path> > <dest>`, `git archive <rev> <path> | tar -x`, or a fetch of the commit
  that carries it, run inside the session that owns the destination repo (the source
  repo's session pushes a branch or names a sha; the destination's session fetches it). Never retype,
  paste or encode file contents into a prompt or a message to another session.
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
- **Every delegate brief opens with `feature: <repo>/<slug>`** — the repo's name and the
  feature directory it is for, on the first line, before anything else — or
  `feature: none — <reason>` for work no feature owns (`CONVENTIONS.md` → "Delegate
  briefs"; the format is `analysis/README.md` → "The brief header"). That line is what the
  capture reads to pin the delegate itself, what `capture_planning.py --list-subagents
  --unclaimed` reads to propose the pin, and what a pin is checked against; a delegate
  without it can be attributed only by a human reading its prompt, and the hook sends an
  `Agent` call without it back. After a run, `--unclaimed` must come back empty before the
  cost is quoted.

## NOTES.md

Written by the architect as its last act, in the feature directory next to the
queues. Contents, tersely: the rulings that are judgment rather than spec, with a
one-line rationale each; deviations from the design doc, and why; open questions for
the coordinator or the human; the exact resume/state-inspection commands for this
feature; anything a cold successor would otherwise re-derive. It is the standing
replacement for the architect's head.
