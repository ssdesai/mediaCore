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
   author's session and is shared when one author writes both arms. When the author is
   a delegate rather than the human's own session, its transcript is a subagent file
   under the coordinator's session and inherits the coordinator's branch — pin its id
   in the arm's manifest (`subagents`, `AGENT_PLANS.md` → manifest) or it prices as $0.
   The coordinator's own manifest lists that delegate under `exclude_subagents`, or the
   two manifests claim it twice and the ledger refuses the second capture.
   Brief every delegate with `feature: <repo>/<slug>` on its first line, and before
   scoring E run `capture_planning.py --list-subagents --unclaimed` — it must be empty.
   Charge the coordinator too: run each arm's coordination from its own session, from
   the repo root, and claim it with `main` + a `session_window`; a four-day coordinator
   measured at $206 was the largest single line of the program it ran, and no
   per-feature figure saw it.

A tie on correctness with a cost difference under ~15% is **noise** at n=1: run-to-run
executor variance is that large. Either run again or weight the defect lists, which are
deterministic enough to compare.

## Running one: `harness/`

Everything below this section describes doing the work by hand, which is how rounds 1–3
were run. From now on, run an experiment with `harness/` instead. The hand method's
failure modes are what it exists to remove: round 3 cost $238 across five features — as
much as the arms it was measuring — and broke isolation twice, reusing one arm's review
plan on the other tree and cross-checking the two trees to write each other's rework
list. In the harness a run's inputs are its fixture and its method and nothing else, the
review brief is written from the spec before any arm runs, and the rework reads only its
own tree's findings.

```bash
./agentTooling/harness/new-fixture.sh <fixture> --repo … --base … --spec-repo … --spec-ref … --spec-path …
#   then write facts.md, review-brief.md and accept/accept.py from the spec, before any arm runs
./agentTooling/harness/check-fixture.sh <fixture>
./agentTooling/harness/new-experiment.sh <experiment> --fixtures <fixture> --methods direct,plans --prediction '…'
./agentTooling/harness/run.sh plans/experiments/<experiment> --dry-run
./agentTooling/harness/run.sh plans/experiments/<experiment>
./agentTooling/harness/publish.sh plans/experiments/<experiment>
```

`harness/README.md` → "Adding one" walks those seven steps, naming what each script
verifies and the three files a person still writes. Three nouns. A **fixture** is a feature frozen so it can be built again — a base commit,
a pinned spec commit, the toolchain facts handed to every arm, the review brief, an
acceptance probe — and lives in the consuming repo at
`plans/experiments/fixtures/<name>/`. A **method** is one way of turning a worktree at
that base into an open PR, and lives in `harness/methods/<name>/`; `plans` and `direct`
ship with it. An **experiment** says which cells to run and carries the prediction, at
`plans/experiments/<experiment>/`, where the harness appends `results.jsonl` and renders
`SCORECARD.md`.

The harness runs the same review and the same rework over every tree, whatever built it,
so "direct" always means one model call *plus* that review — never the model call alone,
which is the comparison the WP7 scorecards had to correct by hand.

What stays true from the sections below: the checklist — here the fixture's
`review-brief.md` and `accept/accept.py` — is written before any arm runs; each arm gets
its own worktree and its own toolchain; cost comes from `report.py` over frozen
sidecars; and a tie inside ±15% at n=1 is noise, which `noise_band_pct` in
`experiment.json` records and the scorecard applies. See `harness/README.md` for the file
shapes and `harness/SPEC.md` for why each stage sits where it does.

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
author); defects in one arm only are the signal. Round 3 showed the cost of using it to
*drive* rework: each tree's fix list then depends on the other tree, and to-green figures
compare the pair rather than the arms. From `harness/` on, the review is a fixture-owned
brief written before any arm runs, rework reads only its own tree's findings, and the
cross-check is read-only — a scoring aid, never an input to either tree.

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

**Round 3 — the plan workflow vs one Opus one-shot** (WP7, five features across four repos,
2026-08-27 → 29; scorecards in humanNetworkMap `plans/experiments/wp7-bundle-store/`). Each
feature built twice from the same spec section: an architect + `run-batch.sh` against a
single Opus implementer that ran the gate and opened the PR itself; the same review plan on
both trees, then one rework pass per arm to the same checklist. Coordinators were Opus
subagents of the design session so their cost is in every figure.

- **Cost.** To checklist-green, plans $120.02 vs direct $128.94 in total (+7% direct);
  plans cheaper or tied on four of five, direct cheaper only on the seam module itself
  (−33%). The useful number is the crossover: the one-shot's cost tracks the diff
  ($4.55 → $21.38 from ~0.4k to ~1.8k lines) while the architect's barely moves
  ($3.20–6.89) and the sonnet/haiku build+verify stays $4.6–11.1 — so above roughly a
  thousand lines the plan workflow wins on cost and the margin widens with size (+45% on
  the largest crossing; +15% on a repeat of the small cell shows the noise). n=1 per cell.
- **Rework was not measured cleanly.** The hypothesis — build/verify catch drift, so
  plans avoid rework — went untested: the direct tree was reviewed with the plans arm's
  review plan, and each arm's rework list was the union of its review's escalations and
  what the *other* tree had asserted, so equal rework ($28.87 vs $33.64 in total)
  reflects the union's construction as much as the arms. The clean comparison is to
  PR-open, where the arms were isolated: plans $91.15 vs direct $95.30 (+5% direct),
  the same direction as the green totals. What the plan workflow reliably added *before*
  any cross-check was *test surface*: the architect's
  acceptance-tests-first plan wrote black-box assertions the one-shot never did (the
  nothing-stored snapshot, the dry-run-plus-store case, the redirect case), which the
  direct review then had to ask for. A direct brief should say "write the black-box
  acceptance test first"; that is the transferable half of the doctrine.
- **Speed and design.** The one-shot was 2–4× faster to PR every time (120 min against
  318 min in total) and its tree was picked on design all five times, narrowly on the
  last: one context makes the more coherent calls (typed vocabularies shared by core and
  wire, honest wire shapes, the failing URL in every message). Plans buys cost, not a
  better tree.
- **Harness.** Two of five plans batches were stopped by a usage limit and resumed
  cleanly (the resume rule is what made that free); a coordinator that re-runs with the
  brief's `>` redirect overwrites run 1's `batch.log` — use `>>` or a per-run file. The
  coordinator tier costs $0.5–2.2 as a subagent of the design session against $5–6 as a
  standalone session (F1).
- **Rule of thumb from this round.** Green gate and READMEs in place, feature above ~1k
  lines of diff, wall clock not the constraint → the plan workflow. The foundation or
  seam module, or anything where the hour matters more than $5–10 → a direct Opus
  one-shot briefed to write its acceptance test first. Either way an independent review
  — a brief written from the spec before the build, never the other arm's review plan —
  and one rework pass from its findings, because that is where both arms' remaining
  defects were found.
