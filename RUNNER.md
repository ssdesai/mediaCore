# Runner execution model

How `run-plans.sh`, `run-verify.sh`, `run-review.sh`, and `run-batch.sh` execute a
batch. Read this when authoring plans, and when working out what a failed run actually
did. Install and update instructions are in `README.md`; how to write a plan is in
`AGENT_PLANS.md`.

By default, the runners operate on the consuming repo's `plans/features/<slug>/`
directories, one per feature (see "Choosing a feature" below). Passing `--self` as the
first argument switches the whole run to agentTooling's own corpus instead — see
"Self-hosted mode" below.

- `plans/features/<slug>/auto/` — file-edit-only build plans, run by `run-plans.sh`
  with **Bash disabled**
- `plans/features/<slug>/verify/` — post-build verification plans, run by
  `run-verify.sh` with **Bash enabled**
- `plans/features/<slug>/review/` — post-verify diff review, run by `run-review.sh`
  with **Bash enabled**
- `plans/features/<slug>/interactive/` — bash-heavy steps a human runs by hand; no
  runner touches these

## The four modes

### Build plans (`plans/features/<slug>/auto/`)

File-edit-only, run in headless mode (`claude -p --permission-mode acceptEdits`).
These must NOT include bash commands — automated verification belongs in
`plans/features/<slug>/verify/`, and bash-heavy human-in-the-loop steps in
`plans/features/<slug>/interactive/`.

The runner disables the Bash tool (`--disallowedTools Bash`), so the "no shell
commands" rule is enforced rather than merely requested — a plan that needs bash
fails loudly instead of quietly shelling out under `acceptEdits`.

### Verify plans (`plans/features/<slug>/verify/`)

The last plans authored for a batch. Build plans cannot run what they wrote, so
typecheck breaks and failing assertions survive until something exercises the code.
The verify plan closes that gap: it runs the work and checks it.

- **Bash is ENABLED.** `run-verify.sh` runs `claude -p --permission-mode acceptEdits
  --allowedTools Bash`, so the executor can run typecheck, tests, and codegen checks,
  and auto-accept the edits it makes to fix defects. The build runner stays bash-free;
  only this privileged pass gets the wider scope.
- **…but repo-wide VCS state is off limits.** The executor prompt forbids `git stash`,
  `git checkout`, `git reset`, `git clean` and branch switches; `git worktree add` is the
  sanctioned way to get a baseline to compare against. The queue this run is being driven
  from is untracked working-tree state, so `git stash -u` sweeps the executing plan out
  from under the runner — and the budget cap can stop the run between a stash and its pop,
  stranding the batch's whole uncommitted output in a stash nobody knows to look for.
- **Model: `sonnet` by default.** Verify is judgment work — reading unfamiliar output,
  deciding whether a failure is a test bug or a real defect. But once the mechanical
  checks are the gate's job and world-building is a test's job, what remains is triage
  plus a few cross-layer invariants, which is `sonnet`-shaped. Spend `opus` only on a
  genuinely adversarial surface. `run-verify.sh` reads the model from
  `NN-verify-MODEL.md` exactly as `run-plans.sh` does.
- **Written as a brief, not a diff.** The plan states the goal and the checks — not
  step-by-step edits — and grants latitude to correct *local* defects in the build
  output rather than re-plan them.
- **It checks what the suite doesn't.** The executor reads the tests covering a
  behaviour before checking that behaviour by hand, and never reconstructs a
  collection/fixtures/running server to do so — that setup is a test to be written,
  and reporting the missing assertion beats performing the check once. See
  AGENT_PLANS.md → "Verify plans" for the measured cost of ignoring this.
- **`--up-to NN` bounds the queue at a level sentinel.** Used to drain just the
  level-verify plan queued at a level boundary before the next level's build plans run
  against it. Plans numbered above `NN` — including the batch's final verify — are left
  queued; since `resolve_feature` calls `list_plans` too, a feature whose only queued
  verify plan is above the bound resolves as nothing queued, a clean no-op rather than
  an error. With the slug given explicitly — which is how `run-batch.sh` always calls
  it — `resolve_feature` returns before that check and the same no-op comes from the
  drain loop finding nothing under the bound. Either way: exit 0, nothing run.

### Review plans (`plans/features/<slug>/review/`)

The last pass. Build wrote the code, the gate ran the deterministic checks, and verify
ran the work and fixed what running revealed. Review reads the **diff** and judges the
code itself — the defects that are still there while every check is green.

- **It is not a second verify plan.** The two passes differ in how they generate
  observations, and that is the whole reason both exist. Verify generates them by
  *running* the work: it finds what only execution reveals. Review generates them by
  *reading the diff*: an invariant no test asserts, a contract broken on one side of a
  layer boundary, a field list that no longer matches the shape it documents. Neither
  subsumes the other. Note that this does not contradict AGENT_PLANS.md → "The
  mechanical gate", which rules out handing a high model a *transcript* to summarize;
  reading a diff generates observations that did not previously exist, which is exactly
  the property that section says verification value depends on.
- **Bash is ENABLED**, and the same VCS restrictions apply as for verify. Read-only git
  is not merely permitted here, it is the pass's primary tool: establishing what the
  batch changed is `git diff`/`git log`/`git show`.
- **Same fix policy as verify: local fixes, structural escalations.** A drifted README
  line or a missing null guard is fixed in-pass; anything needing a new function, a
  changed signature, or a design decision is reported for the next batch's build plan.
  Expect review to escalate more often than verify — a defect found by reading skews
  structural, and rewriting a design at peak context on this pass's model is the most
  expensive way this workflow can correct anything.
- **Model: `opus` by default**, unlike verify's `sonnet`. Judging whether a change
  respects an invariant nobody wrote down is the adversarial-reasoning case verify's
  own model note reserves for opus. `run-review.sh` reads the model from
  `NN-review-MODEL.md` exactly as the other runners do.
- **Budgeted separately.** `--max-budget-usd` defaults to `$5.00`
  (`REVIEW_BUDGET_USD`), higher than verify's `$3.00` because the default model is more
  expensive. That figure is an estimate, not a measurement — re-derive it from the first
  few real runs the way verify's was.
- **It writes a verdict, and that verdict becomes a PR.** The executor writes its
  findings to `plans/review-report.md`; on a clean pass `run-review.sh` then runs the
  repo-owned `plans/pr.sh`, which branches if needed, commits, pushes, and opens a pull
  request with that report as its body. So the batch ends at something a human approves
  in a browser rather than at a terminal summary.
- **The PR step is a script, not a prompt instruction.** Branching, committing, pushing
  and calling a forge CLI is deterministic work with a real exit code — the same reason
  the mechanical checks live in `gate.sh` rather than in a verify brief. The model's
  contribution is the review; the plumbing around it is not model work. `pr.sh` is
  repo-owned for the same reason `gate.sh` is: `gh` is GitHub's, `glab` is GitLab's, and
  the shared harness must not pin every consuming repo to one forge.
- **The PR step is gated and advisory.** It runs only when the pass finished with
  nothing left in `failed/`, `inprogress/` or `incomplete/` — a budget-capped review has
  not finished judging the batch, and a PR opened on its behalf would carry a
  half-written verdict past a human who assumes otherwise. If `pr.sh` itself fails, the
  runner reports the exit code and still exits with the review pass's own status: a
  review that succeeded is not made wrong by a push that didn't.
- **Optional per feature.** An empty `review/incomplete/` is a clean no-op that exits 0,
  so features authored before this queue existed still run unchanged under
  `run-batch.sh`.

### Interactive plans (`plans/features/<slug>/interactive/`)

Verification, migration, and other bash-heavy steps that need a human in the loop,
run by hand. Distinct from verify plans, which are scripted and unattended, just
privileged — same "after the build plans" timing, no human in the loop.

## Layout and state

Each feature is one directory, `plans/features/<slug>/`, holding everything about
that feature: a manifest (`README.md`), the state subfolders below for each of
`auto/`, `verify/`, `review/`, and `interactive/`, and the JSON artifacts the analysis
tooling writes (cost records, fanout reports). Nothing about a feature spans two
directories.

Within each queue (`auto/`, `verify/`, `review/`), plans live in state subfolders. The
runner promotes them between folders as it works. Each plan has a sidecar progress log
(`<plan>.progress.md`) that travels with it.

- `incomplete/` — queued plans. Run order is lexical (`[0-9]*.md`). No log yet.
- `inprogress/` — the plan currently executing, plus its progress log. If the runner is
  killed mid-plan, the plan and log stay here; the next run's phase 1 resumes them.
- `complete/` — plans the runner finished cleanly, with their final logs.
- `failed/` — plans where `claude -p` exited non-zero, with their logs. Inspect, fix,
  and move back to `incomplete/` to retry. Also where a plan lands when it exceeds its
  run budget (see below) — deliberately not `inprogress/`, since resuming would just buy
  the same brief another budget's worth of turns.

**Level sentinels.** `NN-gate.md` moves `incomplete/ → complete/` directly with no
sidecars; the runner runs the gate with `NN` as its label instead of calling `claude`;
cost tooling never sees it because it has no `.usage.json`.

`auto/`, `verify/` and `review/` each get their own set; the runners create them on
first use, and `finalize_plan` recreates the one it is about to move into. That second
`mkdir` is not redundant: a state folder is an empty directory until a plan lands in it,
git does not track empty directories, and the verify and review executors have bash — a
`git stash -u` / `git stash pop` in the working tree removes them and restores only the
files (the plan queue is untracked, so `-u` sweeps it). Without it every `mv` fails, the
plan stays in `inprogress/`, and the next run resumes a plan that was meant to be filed.

## Choosing a feature

A run operates on exactly one feature. The slug may be given explicitly as the first
argument to `run-plans.sh`, `run-verify.sh`, `run-review.sh`, or `run-batch.sh`.
Otherwise it is inferred from whichever feature under `plans/features/` has plans queued
(`incomplete/` or `inprogress/`) in the queue that runner drains.

- **Zero features with queued work** is a no-op: the runner prints a message and exits 0.
- **Exactly one** is resolved and used.
- **Two or more is an error**, not a pick — guessing wrong doesn't just run the wrong
  plans, it files completed logs, streams, and usage records under the wrong feature,
  corrupting a cost report that nothing downstream can detect as wrong. Name the
  feature explicitly to break the tie.

`run-batch.sh` forwards an explicit slug to all three passes; when inferring, it
captures whichever feature the build pass resolved and hands that same slug to the
verify and review passes, so the three stages can never resolve to different features.

Each pass is gated on the one before it. A non-zero build code skips verify, because
the code under test was never finished being written. A non-zero verify code skips
review, for a different reason: verify is permitted to edit, so a verify pass that
stopped early leaves a half-fixed tree, and reviewing a state nobody intends to keep
produces findings nobody wants. The skip prints the `run-review.sh` command to run once
verify is settled.

Exit code **64** (`LEVEL_PAUSE_RC`, `plan-runner-roots.sh`) from `run-plans.sh` means
paused at a level boundary with a level-verify plan queued **and the level's gate not
green**; `run-batch.sh` handles it by climbing the tier ladder (next section) and
re-invoking the build pass; by hand, run `run-verify.sh --up-to NN`, re-run the gate, and
continue only on green. When the level's gate verdict is
`all checks passed` there is nothing for a fix session to fix, so the runner files every
queued verify plan numbered ≤ NN to `verify/complete/` with a `.progress.md` saying
`skipped: level NN gate reported 'all checks passed'` and continues without pausing (D3,
revised after the first pilot measured an always-run level-verify at 23% of the final
verify for no finding). The pause is advisory and fires once: the sentinel is already in
`complete/` when the runner exits 64, so re-running `run-plans.sh` without the
level-verify simply continues into the next level. Nothing enforces that the level-verify
ran — `run-batch.sh` is what makes the sequence reliable.

64 is reserved. `finalize_plan` remaps a `claude` that exits 64 to 1, and
`run_level_gate` does the same for a gate script, so neither can impersonate a pause and
make `run-batch.sh` skip past a failed plan. `self/tests/level-sentinel.sh` asserts all of
this against a throwaway checkout and runs in `self/gate.sh`.

## Red gates: the tier ladder

A level's gate going red is normal — build plans cannot run what they wrote. What the
batch does about it is a ladder, climbed by `run-batch.sh`'s `settle_level`, with no
human on any rung until the last:

| Tier | What runs | Model, cap | May change a contract | Leaves behind |
|---|---|---|---|---|
| 1 | the authored `NN-level-*` verify plan (`run-verify.sh --up-to NN`) | sonnet, `LEVEL_VERIFY_BUDGET_USD` ($6) | **no** — writes `escalations/NN.md` instead | its progress log |
| re-gate | `gate.sh NN` | none | — | `gate-report.NN.txt` |
| 2 | `NN-escalation-opus`, synthesized by `run-escalation-plan.sh` into `verify/incomplete/` | opus, `ESCALATION_BUDGET_USD` ($8) | **yes**, and must patch queued plans that mirror it | `## Decided at tier 2` in `escalations/NN.md` |
| re-gate | `gate.sh NN` | none | — | — |
| 3 | nothing — the batch exits 1 | — | — | `## Needs a human` in `escalations/NN.md` |

Green at either re-gate resumes the build pass. A tier that stops for a **usage limit or
interrupt** (its plan left in `inprogress/`) is not an outcome: the batch exits with that
code and the next run resumes the same rung. A tier that stops for its **budget** is an
outcome (the plan is in `failed/`): the ladder re-gates and climbs.

**What the level gate measures.** The sentinel's `expected-red:` and `defer:` lines
(`AGENT_PLANS.md` → "Plan file format") are exported to the repo's `gate.sh` as
`GATE_EXPECTED_RED` and `GATE_DEFERRED` by `level_expectations` (`plan-runner-roots.sh`),
from both `run_level_gate` and the batch's re-gate. Without them the first tiered pilot ran
tier 1 *and* tier 2 on level 1 because plan 01's acceptance file was red — which it is
supposed to be until level 2. A DEFERRED section is not SKIPPED: deferred is "a later
level's", skipped is "could not run", and only the latter keeps a level from being green.

**Resume.** `run-batch.sh <slug>` (explicit slug) first looks at the highest sentinel in
`auto/complete/`; if a level plan ≤ NN is still queued or that gate's last verdict is not
green while build plans remain, it settles the level before running the build pass. The
first pilot's re-run after a capped level-verify built level 3 on a half-fixed level 2;
this is the rule that stops it.

**Once per level.** `run-escalation-plan.sh` refuses to write a second
`NN-escalation-*` for a level that has one in any state, so a red-forever level costs one
tier-1 run and one tier-2 run, then a human. To re-arm tier 2 after editing the note, move
the old escalation plan out of `verify/failed/` by hand.

**Cost attribution.** The synthesized plan has no manifest entry; `analysis/report.py`
recognises the `NN-escalation-<model>` stem and rolls it in with a warning instead of
excluding it as an orphan.

**Review after a cap.** `run-review.sh` opens the PR when the budget cap fired *after*
the report was written (content fingerprint before/after), appending a banner saying so,
and still exits non-zero. A cap before the report still opens nothing.

`self/tests/tiered-gates.sh` asserts every row of this table against a throwaway checkout.

**There is no archiving step any more.** The feature directory *is* the archive — a
finished feature's `complete/` folders are its permanent record. The branch-named
subfolders that predate this (e.g. `plans/auto/complete/<branch>/`) are migrated once by
`agentTooling/migrate-plans-layout.sh`.

Every finished plan — complete or failed — lands with four files, not two:

- `<plan>.md` and `<plan>.progress.md`. On a failure the log's last line is
  `failed (exit N): <reason>`, extracted from the run's final `result` event, so a plan
  that died before its first Edit still says why instead of leaving an empty log.
- `<plan>.stream.jsonl` — the raw stream-json event log: the full record of what the
  model did, including the tool inputs and results the terminal summary drops. Kept on
  both success and failure so any run can be analysed after the fact. Gitignore it —
  useful locally, too large and too machine-specific to commit.
- `<plan>.usage.json` — a small, committed extract of the final `result` event: cost,
  turns, duration, token counts, tool-call counts, and files edited. Exists because the
  stream it comes from is gitignored and too large to commit — this is what per-plan
  cost survives on. Written by `finalize_plan` before the stream is moved, so it lands
  alongside the plan in whichever directory it settles in.

  **Accumulates across attempts.** Each resume is a separate `claude -p` with its own
  session id, and `run_plan` truncates the stream per attempt, so the sidecar is
  merged rather than overwritten: `attempts[]` lists one record per invocation and
  every total sums over it. A run killed outright never reaches `finalize_plan`, so
  `run_plan` recovers that attempt from the leftover stream just before truncating it
  (`harvest_orphan_attempt`) — otherwise its session would look interactive to
  `analysis/capture_planning.py` and be re-billed as planning cost.

Usage-limit stops leave the plan and log in `inprogress/` and exit. The next
invocation's phase 1 picks them up.

## Self-hosted mode

agentTooling builds its own features with its own harness: a change to the runner or
its doctrine is planned, executed and costed in the repo it belongs to, instead of in
whichever repo happens to vendor it.

Pass `--self` as the **first** argument, before any slug:

```bash
./agentTooling/run-batch.sh --self <slug>
```

`run-batch.sh` forwards it to both passes.

| | normal | `--self` |
|---|---|---|
| `REPO_DIR` (executor cwd) | consuming repo root | `agentTooling/` |
| feature tree | `plans/features/<slug>/` | `agentTooling/self/features/<slug>/` |
| gate | `plans/gate.sh` → `plans/gate-report.txt`, plus `gate-report.<NN>.txt` per level sentinel | `self/gate.sh` → `self/gate-report.txt`, plus `gate-report.<NN>.txt` per level sentinel |
| facts | `plans/PROJECT_FACTS.md` | `agentTooling/self/PROJECT_FACTS.md` |

Everything else — the state folders, resume phases, budget, progress and usage
sidecars — is identical, because both modes drive the same `plan-runner-lib.sh`.

The executor's cwd being `agentTooling/` is why `agentTooling/CLAUDE.md` exists: a
`--self` executor never sees the consuming repo's root `CLAUDE.md`.

One asymmetry is worth naming: the analysis scripts take `--self` too, but their
session root is *not* `REPO_DIR` — planning transcripts are recorded against the git
toplevel, which is the consuming repo when agentTooling is a subtree. See
`analysis/README.md` rather than restating it here.

## The run budget

`run-verify.sh` passes `--max-budget-usd` (default `$3.00`, override with
`VERIFY_BUDGET_USD`) and `run-review.sh` passes its own (default `$5.00`, override with
`REVIEW_BUDGET_USD`); `run-plans.sh` sets no cap. It is a circuit breaker, not a budget —
it should fire rarely, and firing means the brief asked for more than that pass should
do. Every other rule in `AGENT_PLANS.md` → "Verify plans" / "Review plans" is an
instruction the executor can talk itself out of mid-run with a plausible reason; this is
the one limit that does not depend on it judging its own scope correctly.

The two caps differ because the two passes default to different models. Verify's `$3.00`
was derived from measured sonnet runs; review's `$5.00` is a starting estimate for an
opus pass and has not been measured yet — re-derive it from the first few real runs the
same way (median of the honest runs, doubled).

`claude -p` exits 1 for a budget stop, a usage limit, *and* a genuine failure, so the three
are told apart by the final `result` event: `subtype == "error_max_budget_usd"` (budget) is
matched on that exact field, while the usage-limit check matches message text, and the two
are deliberately disjoint — a mis-scoped brief must never be mistaken for a rate limit and
silently re-queued. The progress log records `stopped: reached the run budget (spent $N)`.
The cap is enforced after each API call, so a run overshoots by at most one turn's spend.

## How resume works

Each runner runs in two phases:

1. **Phase 1 — resume.** Anything already in `inprogress/` is re-run first. Claude is
   told to read the `.progress.md` log as a hint about what is already done, but to
   verify each target file's on-disk state before editing — the log is a hint, not a
   source of truth.
2. **Phase 2 — fresh plans.** Queued plans in `incomplete/` are moved into `inprogress/`
   one at a time, each with a fresh empty log, and run.

The log is written by the harness, not by Claude: the runner filters the event stream
for mutating tool calls (`Edit`/`Write`/`MultiEdit`/`NotebookEdit`) and appends one
`<tool>: <absolute path>` line each. This is what makes "pick up and finish a half-done
plan" work without requiring the plan itself to track state, and it means entries
survive a mid-turn kill.

**An empty log on a failed plan is meaningful, not broken.** Only mutating calls are
recorded, so a plan that failed while still reading — or a verify plan that only read
files and ran bash — has nothing to show. Read the `failed (exit N)` line and the
`.stream.jsonl` in that case.

The log is fed through a FIFO whose PID the script waits on, rather than a `tee >(...)`
process substitution: bash does not wait for process substitutions, and the failure
path calls `exit` immediately, so pending writes could otherwise be lost exactly when
they matter most.

## Idempotency

Plans should describe the **desired end state** of each file ("the model should have
these fields") rather than imperative diffs ("add line X"). Even with the log, the
runner re-verifies each target, so plans written declaratively converge cleanly.
