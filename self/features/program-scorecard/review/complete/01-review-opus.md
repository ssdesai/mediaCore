# 01 — review: program-scorecard

Read the diff and judge it against the contract below. Findings are defects that survive a
green gate; "no findings" is a legitimate verdict and the right one when the diff holds.
Fix what is local and mechanical; escalate anything that changes a contract or needs a
decision.

## What the feature was supposed to do

The experiment harness compares agentTooling versions one feature at a time. This feature
fixes the contract for a *program-level* A/B (an orchestrator session running an ordered
list of features, one implementer per feature, the two arms compared as one feature set)
before the driver that produces it exists. Nothing here runs `claude`.

1. **A ledger row with `kind: "program"`**, documented in `harness/README.md` → "File
   shapes" with every field listed (README Rule 1): `kind, experiment, program, method
   ("orchestrator"), repeat, arm, agent_tooling, branch, slug, base, model,
   orchestrator_sessions[], orchestration_record, t_setup_start, t_method_start,
   t_method_end, cost_overhead_usd, cost_group_usd, cost_group_green_usd, overhead_pct,
   features_count, features_pr_open, features_green, method_failed, record_report
   ({group_total_usd, overhead_pct, unpriced_count} or null), features[] (position,
   fixture, depends_on_previous, method, branch, slug, session, pr_url, pr_base,
   t_implementer_start, t_implementer_end, brief_written, dependency_ok, cost_method_usd,
   cost_review_usd, cost_rework_usd, cost_green_usd, unpriced_reason, review_fixed,
   review_escalated, rework_ran, accept_pass, accept_lines[], gate_counts_green, green,
   method_failed), interventions[], harness_version`. Meanings: `cost_group_usd =
   cost_overhead_usd + Σ features[].cost_method_usd`; `cost_group_green_usd` adds every
   feature's review and rework; `overhead_pct = cost_overhead_usd / cost_group_usd × 100`
   (the definition `report.py --orchestration` uses); `record_report` is a cross-check
   only. "Naming" must say a program's branch is `<programStem>Orchestrator<Arm><n>` and a
   feature's inside it `<fixtureStem><ProgramStem><Arm><n>`.
2. **`harness/scorecard.py`**: `split_rows(rows) -> (cells, programs)`; every existing
   section runs on cells only and a ledger with no program row renders **byte-identically**
   to before; `compare()` takes its cost fields as a parameter (default the cell pair; the
   program pair is `cost_group_usd` / `cost_group_green_usd`); `render()` adds the program
   count to the header, considers both kinds in its "no runs" check, calls
   `render_programs()` after the cell comparisons, and folds program interventions,
   failures and feature gate counts into the existing sections; `render_programs(experiment,
   rows, band)` renders a `## Programs` table, one `### <program> · arm <arm> #<n>` table
   per program cell (✓ / ✗ when `dependency_ok` is false / — when not dependent), a `Per
   program cell` block when repeats > 1 (mean and spread of group-to-green, mean overhead
   %, mean PRs open, mean green) and one comparison line per program under the existing
   band heading, in the cell lines' wording and band logic, from `program_counts()`, with
   an n=1 comparison marked; helpers `program_counts(rows)` and `feature_flags(feature)`;
   every new label a named constant at the top of the file (CONVENTIONS.md → Named
   constants).
3. **`harness/tests/scorecard-programs.sh`** on a hand-built ledger (two program rows,
   arms before/after, one pair inside the band on to-PR-open and outside it on to-green,
   PRs open 2/2 vs 1/2, one dependent feature with `dependency_ok` false, one
   `record_report` null and one with a figure, plus ordinary cell rows) asserting the
   Programs rows, the per-feature tables including ✗, the comparison line and its counts
   suffix, the overhead %, that program rows are absent from the cell sections, and the
   byte-identity of the cell-only render. Registered in `self/gate.sh` beside the other two
   harness tests.
4. **Docs**: `harness/README.md` (Contents, File shapes, Naming, the scorecard entry),
   `harness/EXPERIMENTS.md` ("Scoring" and "Reporting", one paragraph each on the program
   comparison), `harness/tests/README.md`, `CLAUDE.md` and `self/PROJECT_FACTS.md` ("two
   tests" becomes three), and the README of every folder touched.

Out of scope and must not be touched: `templates/`, `analysis/routing.py`,
`LIFECYCLE.md`, `.claude/`, other features' directories, `self/orchestrations/`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- A ledger with no `kind: "program"` row renders byte for byte as `origin/main`'s
  `scorecard.py` renders it: check every changed line of `render()` for an extra blank
  line, a changed header, a reordered section, a changed table. Check
  `harness/tests/scorecard-programs.cells.md` is the *old* rendering and that the test
  really compares against it.
- Program rows never reach a cell section (Runs, Per cell, cell comparisons); cell rows
  never reach a program section.
- The `cost_group_*` arithmetic and the overhead % definition in the docs match what the
  code computes and what `analysis/report.py --orchestration` computes; the code never
  recomputes a dollar figure it should read from the row, and falls back only where the
  README says it does.
- The row shape documented in `harness/README.md` lists every field in the brief above,
  and `scorecard.py` reads no field the README omits.
- Edge cases that do not crash: no cells and only programs; a program with `features`
  empty or absent; `record_report` null; `cost_*` null or unpriced; a program with one arm
  only; an arm of `""`; a zero group cost; `dependency_ok` null/absent.
- Named constants at the top of `scorecard.py` for every new label, column title and
  format; no inline magic literals. Shell test follows `scorecard-arms.sh`'s conventions
  and bash 3.2 (no associative arrays, no `set -e`) and `self/PROJECT_FACTS.md`.
- Docs agree with the code: every folder touched has a README that still describes it
  (README Rules 1 and 2), the "two tests" wording is gone everywhere outside historical
  records, and the gate registration has a comment like its neighbours.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`, then the
findings, each with file, line, and the failing scenario.
