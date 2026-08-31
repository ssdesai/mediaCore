# Orchestration

How to run the tier *above* the runners: a coordinator session automating the human
who would otherwise sit at a terminal running `run-batch.sh`. This tier appears when
work spans repos, or when several features interleave in one repo. It sits above
`AGENT_PLANS.md` (which governs the delegate authoring plans) and `RUNNER.md` (which
governs execution); nothing here changes either.

The one-line rule: **the architect plans; the coordinator runs.**

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
- **Judgment one-shot** — spawned only for a failure the red-gate tier ladder could
  not settle. Briefed with `NOTES.md`, the failed plan's `.progress.md`, and the one
  relevant spec section — never "read the design doc". Dies on delivery.

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
  Nobody polls, ever — no sleep loops, no "check the queue again".
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
- Features sharing a branch chain their manifests' `session_window`s end-to-start —
  two open windows on one branch double-count planning cost.
- A delegate's transcript inherits the coordinator's `gitBranch`, so an architect
  spawned from `main` is invisible to the feature's `branches`. Pin its agent id in the
  manifest's `subagents` (find it with `capture_planning.py --list-subagents`), and do
  it while the transcript still exists — the coordinator's own cost is claimed the
  same way, with `main` in `branches` and a window around the run.
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
