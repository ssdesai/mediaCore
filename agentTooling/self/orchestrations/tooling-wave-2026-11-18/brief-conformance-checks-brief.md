agentTooling feature `brief-conformance-checks` — implementer brief

## Role

You are the implementer session for ONE feature, `brief-conformance-checks`, in agentTooling, start to close. An orchestrator session created you (orchestration `tooling-wave-2026-11-18`). It reads your final report and forwards anything you need from the repository owner: if you are blocked, say exactly what you need and stop. Sibling sessions are building `hook-silent-allow-sweep` (hooks) and `orchestration-start-branch-v2` (`orchestration-start.sh`, `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`, `ORCHESTRATION.md` → "Cloud sessions"); never do their work. Whichever of you merges second runs `./feature-sync.sh --self <slug>` (merged in #166), resolves, re-gates and reviews the merge.

## Branch

Your first command in the repo is exactly:

    ./feature-start.sh --self brief-conformance-checks --method direct --branch claude/brief-conformance-checks --orchestration tooling-wave-2026-11-18

Run it in the background, its output captured to a file in your scratchpad, and wait for its exit notification before you read or edit anything in the tree. Your branch is `claude/brief-conformance-checks`; create or push no other. If the start refuses, report the refusal verbatim and stop.

## Read first (in this order, before any edit)

1. `CLAUDE.md`, `CONVENTIONS.md`, `LIFECYCLE.md` (steps 3–6: the review brief, rounds, the close, the PR), `ORCHESTRATION.md`, `AGENT_PLANS.md`, `self/PROJECT_FACTS.md`.
2. `templates/README.md` (template versions and bumps), `templates/plans/ORCHESTRATOR_BRIEF.md`, the review-plan templates and stubs `feature-start.sh` writes, `run-review.sh`, `plan-runner-lib.sh` (how a review plan is run and its verdict read), `feature-close.sh`, `self/pr.sh` and `templates/plans/pr.sh` (how the PR body is built from the review report), the audit pass (`self/features/audit-round-cap/`, `self/features/hook-planted-gitdir/` for how an audit round is queued and read), and `self/tests/feature-lifecycle.sh`.

## Lifecycle

- Before you build anything, fill the review brief the start names (`review/incomplete/01-review-opus.md`) from the Items below. This feature changes the lifecycle every repo runs, so the owner requires an independent audit round as well as the review: run it the way `LIFECYCLE.md` and `audit-round-cap` define, and close only when both are clean.
- Run the gate (`./self/gate.sh`) in the background, output to a scratchpad file; wait for its exit notification (no `sleep`, no polling). Fix failures in the code, never by weakening a check.
- Review: `./run-review.sh --self brief-conformance-checks`. An escalated verdict is a new round. On a clean review and a clean audit, run `./feature-close.sh --self brief-conformance-checks` straight away.
- Scope rule from the owner: a finding blocks only if it leaves an item below open or is a regression this feature introduces; everything else is filed in `self/BACKLOG.md`. After 2 escalated audit rounds or 3 escalated review rounds, stop and report.
- Commit as you go with subjects prefixed `brief-conformance-checks:`. Every commit message ends with the two trailer lines your session instructions give you. Never put a model identifier in a committed file. Never edit anything under `.claude/`, nor under another feature's folder. Any template you change gets its version bump per `templates/README.md`.

## Why

Today the implementer writes its own review brief from the orchestrator's brief, and the reviewer grades the work against that. A misreading of the owner's request is therefore baked into the criteria, and a review can be clean while the PR does something other than what was asked. Nothing compares the final diff with the owner's own words. The owner ruled on 2026-11-19 that four checks become part of the harness, and that the orchestrator may merge clean PRs without asking only once these checks are in agentTooling and audited.

## Items

Each item: the mechanism, a `self/tests/` assertion (extend `feature-lifecycle.sh` or add a test file), and the docs (`LIFECYCLE.md`, `ORCHESTRATION.md`, the templates) that say how to use it. Design the exact file names and flags yourself and record the decisions in NOTES.md; the behaviours below are fixed.

### 1. The owner's request is the review's yardstick
A feature can carry the owner's request verbatim as a file in its feature directory (e.g. `OWNER_BRIEF.md`), supplied at start (a `feature-start.sh` option taking a file) or added by the orchestrator before the review. When it exists, every review plan is given it word for word, with the instruction that the work is judged against it and not against the implementer's restatement; a review brief may add contracts but may not narrow it. The orchestrator writes or supplies this file; `ORCHESTRATION.md` and `templates/plans/ORCHESTRATOR_BRIEF.md` say so. Assertion: a feature started with the owner-brief option has the file committed in its start commit, and the review prompt the runner builds contains its text verbatim.

### 2. Acceptance table
Each owner-brief item and each acceptance line maps to the test(s) that prove it, with the result. The review report carries this as a fixed section (item → evidence: test name or file:line → result: done / partial / not done). `pr.sh` puts it at the top of the PR body. A review report whose acceptance table is missing, or has a row whose result is not "done", cannot be closed as clean: `feature-close.sh` refuses, naming the row. Assertion: a stub review report with a "partial" row is refused by the close; with all rows "done" the close proceeds and the PR body begins with the table.

### 3. Independent conformance check
A separate pass, run by a fresh `claude -p` that is given ONLY the owner's brief and the feature's diff against its base (not the implementer's NOTES, review brief or transcript), returns per item done / partial / not done with evidence, and lists every changed file it cannot tie to an item (out-of-scope edits). It runs as part of the review round (or as its own runner the close requires; your choice, recorded in NOTES), its cost is recorded like any other pass, and the close refuses unless it agrees with the review's acceptance table. Model: the review's tier. Assertion: with a stubbed model answer of "not done" for an item the review marked done, the close refuses naming the disagreement; with an out-of-scope file listed, the PR body's deviations section names it.

### 4. Deviations section
The review report and the PR body carry a fixed "Deviations from the brief" section: where the work reads the owner's brief differently, leaves something out, or edits outside its scope (including item 3's out-of-scope list). Empty is written as "None". A non-empty section does not block the close, but `pr.sh` marks the PR (a title prefix or label the forge supports in both profiles; your choice) so an orchestrator's merge rule can see it, and `ORCHESTRATION.md` states the rule: an orchestrator never merges a PR with a non-empty deviations section without the owner's word. Assertion: a report with one deviation yields a marked PR body/title; with "None", an unmarked one.

### Rollout
Without an owner brief (older features, hand features), items 1–3 degrade to today's behaviour with a one-line notice, so no consuming repo breaks on the next pull; say so in `LIFECYCLE.md`. Add a `self/BACKLOG.md` entry for making the owner brief mandatory for orchestrated features once one wave has used it.

## Report, terse

The PR URL; the `report.py` cost table (build, review, audit, conformance); per item what changed, by file; each check that failed on first run and what you changed; anything filed to the backlog instead of fixed; anything not done and why; any fact in this brief you found untrue. Your last line is the PR link or the exact blocker.
