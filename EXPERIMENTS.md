# EXPERIMENTS.md

How to test a change to the planning doctrine or the runner *against the version before
it*, so a rule earns its place with a measurement rather than an argument. Written from
the `field-choice` pilot (2026-08-21/22: baseline, levels, then tiered — one feature, one
brief, three worktrees) and meant to be re-run every time `AGENT_PLANS.md` or
`run-batch.sh` changes behaviour.

## What is being measured

Two things, in this order, and the first one decides:

1. **Correctness** — does the arm deliver the feature, and which defects escape every
   pass? Scored against a checklist written *before either arm runs*
   (`templates/experiment/CHECKLIST.md`). A defect found in one arm is then checked in
   the other, so a review pass that happens to look in the right place does not get
   credited as a doctrine win.
2. **Cost** — the `*.usage.json` sidecars rolled up by `analysis/report.py`, split by
   pass (build / level passes / verify / review), plus the count of human interventions
   the batch needed (re-queues, budget raises, hand-run steps). Planning cost is the
   author's session and is shared when one author writes both arms.

A tie on correctness with a cost difference under ~15% is **noise** at n=1: run-to-run
executor variance is that large. Either run again or weight the defect lists, which are
deterministic enough to compare.

## Setting up the arms

One worktree per arm, all off the same prep commit, each pinned to the agentTooling
version it is testing. Pinning is a commit in the worktree's branch that checks out
the subtree at the wanted upstream commit, titled so it cannot be merged by accident:

```bash
git worktree add ../repo-<arm> -b <user>/<slug>-<arm> <prep-commit>
cd ../repo-<arm>
git -C ~/dev/agentTooling archive <upstream-commit> | tar -x -C agentTooling   # replace the subtree's files
./agentTooling/sync-plans.sh
git add -A && git commit -m "EXPERIMENT ARM (revert before merge): pin agentTooling to upstream <commit>"
```

Each arm needs its own toolchain (`.venv`, `node_modules`, browsers) — `gate.sh` is what
proves the environment, so run it once by hand before the batch. Sharing is not a
shortcut: an editable install points at whichever tree ran `pip install -e` last, so a
symlinked `.venv` makes one arm test the other's source.

The arms' gates also run at the same time, and any suite that binds a fixed port (a dev
server, a real-backend browser suite) makes two concurrent gates race for it — either
side can lose, and the loser reads as a red arm rather than a collision. Have the gate
bind-probe free ports per run and export them to the suites' configs, with the configs
defaulting to the usual values so a bare run behaves as before; `templates/plans/gate.sh`
shows the shape. Rehearse it once — two trees, both gates simultaneously, both green
with different port lines in their reports — before trusting a red arm.

The **prep commit** carries anything both arms need that is not the feature: a gate fix,
a `.gitignore` line, a dependency. It must not carry any of the feature, or the arm that
would have built that part is no longer being measured.

**Tag a doctrine change while it is unsettled.** Wrapping each block a change adds to
`AGENT_PLANS.md` in `<!-- <tag>:begin -->` / `<!-- <tag>:end -->` markers makes the
"before" arm one `perl -0pi -e 's/<!-- <tag>:begin -->.*?<!-- <tag>:end -->\n//sg'` away,
with no second copy of the file to keep in step. Strip the markers once the A/B decides —
they are scaffolding for one comparison, not a permanent index of which rule came from
where, and left in place they accumulate across every experiment the doctrine survives.

## Authoring

Same brief, same design decisions, same *per-file plan content* — restructured per each
arm's doctrine (levels / sentinels / contracts table / level-verify briefs in one; flat
numbering in the other). One author for both keeps the plans' cross-layer identifiers
equally pinned, which is the fairest comparison and also the reason the first two arms
found no seam-defect difference: a doctrine that targets seams needs plans that have
them. The third arm is what corrected this — its upper-level plans *referenced* the
lower level's code where the first two pasted a prediction of it (Levels item 8), and
that is where its extra two checklist points came from. Author each arm to its own
doctrine wherever the doctrines actually differ; authoring them identically is fair on
the brief and hides the thing being measured.

Write the checklist before authoring the plans, not after — the plan author knows where
the bodies are buried.

## Running

Sequentially, the same command in each arm, nothing touched between the start and the
PR except what the checklist's process section says to log:

```bash
cd ../repo-<arm> && (nohup ./agentTooling/run-batch.sh <slug> > <slug>-batch.log 2>&1 &)
```

Log every intervention with a timestamp and what it cost: a re-queue, a raised cap, a
usage-limit wait, a hand-opened PR. Those are process findings and go in the scorecard
— the first pilot's were the whole list of harness fixes that followed.

## Scoring

- **A — mechanical.** The arm's own gate, re-run by hand after the batch (the on-disk
  report is stale the moment verify edits anything): pytest, typecheck, lint, build,
  browser suite, twice if flaky.
- **B — behaviour.** A script that drives the *real* routes, CLI and disk of the arm
  (`TestClient`, the console script, `record.json` on disk) and prints PASS/FAIL per
  checklist item — never the arm's own tests, which were written by the thing under
  test. Keep it under `plans/experiments/<slug>/score_b.py` in the consuming repo so it
  is rerunnable against the merged result. The `field-choice` one is the worked example.
- **C — code quality.** Read the diff with the checklist: one predicate on both sides,
  one component, README field lists, spec amended, provenance never collapsed.
- **D — process.** Interventions, pauses, capped passes, resume order.
- **E — cost.** `report.py` per arm; per-pass split; planning cost once.

Then the cross-check: every defect either review escalated, confirmed against the other
arm's tree by hand. Defects present in both are brief or design gaps (charge them to the
author); defects in one arm only are the signal.

## Reporting

One scorecard, both arms side by side, the verdict in the first line. Keep the
checklist, the score script, the batch logs and the scorecard together under
`plans/experiments/<slug>/` in the consuming repo; the two (or three) branches and PRs
stay open until the owner picks one, and the losing arm's pin commit is never merged.

## What the pilots established

**Round 1 — levels vs. a flat baseline** (`field-choice`, 2026-08-21):

- Correctness tie at 14/17 each; levels +32% cost, all of it in level-verify ($3 cap hit,
  re-run at $6) and a larger final verify. Build cost within 10%.
- Both arms missed the same design gaps (retraction semantics, an affordance the route
  rejects, an unpinned verdict in a TS test) — three of five escapes were in the shared
  plans, not in either doctrine.
- The one true seam defect escaped both because the upper level's tests mocked the
  seam. That is the finding Levels items 8–10 and the tier ladder were written from.

**Round 2 — tiered vs. both** (same feature and brief, 2026-08-22): 16/17 at $32.52,
against 14/17 at $36.39 (levels) — better on correctness *and* cheaper, so it is the
doctrine that stands. What produced the difference, and what it cost:

- The two extra checklist items it passed (an affordance matrix, a single affordance
  rule) are exactly what items 8–10 target: referenced contracts and fixtures at the
  seam instead of a pasted prediction and a mocked one.
- The ladder paid for itself: tier 1 $6.63, tier 2 $5.18, and a **final verify of $1.67**
  against the levels arm's $12.42 — red found at the boundary is much cheaper than red
  found at the end.
- It also exposed two harness gaps that were fixed mid-run rather than scored: a level
  gate reporting the whole suite's verdict (so a level was red for tests it does not own
  — now the sentinel's `expected-red:` / `defer:` lines), and a resume that would have
  built the next level on an unsettled one. Interventions mid-experiment are legitimate
  when the harness is the thing failing, but log them and say what they would have saved
  — level 1 cost $6.78 where the fix makes it $2.51.
