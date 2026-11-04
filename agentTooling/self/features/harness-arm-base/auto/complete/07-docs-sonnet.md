# 07 — docs: base arms and reading metrics

**Feature `harness-arm-base`, plan 7 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics (files and bytes read before the first edit, README bytes read)
beside the cost figures.

Summary: document both halves where the harness's contracts live — `harness/README.md`
(Contents, Arms, Stages, both file shapes, the ledger row's full field list, the program
row's statement), `SPEC.md`, `EXPERIMENTS.md` — and the gate's new test count wherever it
is quoted, and record the two exclusions in `self/BACKLOG.md`.

Depends on: plans 01–06. Read, before writing: `harness/lib.sh` (the constants after
`HARNESS_ARM_LABEL_RE` and `harness_experiment_arm_kind`), `harness/new-experiment.sh`'s
header comment, `harness/run.sh`'s `resolve_cell`, `do_reading_metrics` and
`build_ledger_row`, and `harness/reading_metrics.py`'s docstring. Those are the contract;
describe what they do, not this plan.

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Rulings to document (verbatim facts):
- `--base-arms <label>=<ref>,…` / `experiment.json` `base_arms: {<label>: <full sha>}`:
  each ref resolved in the **measured repository's own checkout** (a sha missing locally
  fetched by sha from `origin` once); a ref that does not resolve there is refused, citing
  the rule that an experiment runs from and lives on the repository it measures. Each
  cell's worktree is cut at its arm's commit instead of the fixture's `base`; the spec
  pin, facts, review brief, accept probe, setup, gate, method, review and rework are the
  fixture's and unchanged. Branch `<stem><Method><Arm><n>` as for agentTooling arms. No
  pin commit. The tree's vendored `agentTooling/` is whatever that commit carries — so a
  base arm also varies the agentTooling version if the two commits vendor different ones;
  say so.
- **One kind per experiment.** `agent_tooling` and `base_arms` together are refused by
  `new-experiment.sh` and by `run.sh` (`harness_experiment_arm_kind`). `base_arms` with
  `programs` is refused too: a program pins its own `base`.
- The scorecard compares base arms exactly as agentTooling arms — pairwise within each
  fixture × method, to PR-open and to green, under `noise_band_pct` — labels a base arm
  `<arm> (base <sha7>)`, and lists `base arms: <label>=<sha7>, …` in its header.
- New cell-row fields: `arm_kind` (`"agent_tooling"`, `"base"`, or `""` with no arm;
  absent on older rows — read absent as `"agent_tooling"` when `agent_tooling` is
  non-empty, else `""`); `base` is the arm's commit for a base arm (the fixture's `base`
  otherwise, as before); `agent_tooling` is `""` for a base arm.
  `read_files_before_edit`, `read_bytes_before_edit`, `readme_bytes_read` — integers, or
  `null` when not measured (no transcript in the window; absent on older rows). Their
  definitions are `reading_metrics.py`'s docstring: the transcripts under the worktree's
  own project directory (exact name) and their subagents, lines inside `[t_method_start,
  t_pr_open]` (now when no PR opened), the first edit being the first `Edit`/`Write`/
  `MultiEdit`/`NotebookEdit`; a read is a non-error `Read` result, bytes its UTF-8 text;
  files counted distinct; README bytes are every `README.md` read in the window, before
  or after the first edit. Only the `Read` tool counts — a `cat` through `Bash` does not.
  The figures come from the `capture` stage (`do_reading_metrics`), from the driver's
  `analysis/` modules, and reach the state file before `record`.
- The scorecard's `## Reading before the first edit` table follows the Runs table, one
  row per cell row carrying the fields (`—` for not measured); a ledger without them
  renders exactly as before.
- **Program rows are not affected**: neither the program row nor its `features[]` carries
  the reading fields (a program feature's capture does not run the extractor), and a
  program cell cannot have base arms.

## Files

- `harness/README.md` — modify
- `harness/SPEC.md` — modify
- `harness/EXPERIMENTS.md` — modify
- `harness/tests/README.md` — modify
- `self/PROJECT_FACTS.md` — modify
- `CLAUDE.md` — modify
- `self/BACKLOG.md` — modify

## `harness/README.md`

- **Contents** (lines 20–37): a row for `reading_metrics.py` (usage line, what it prints,
  exit codes, that it imports the driver's `capture_planning.py` and `transcript.py` by
  path); rows for `tests/arm-base.sh` and `tests/reading-metrics.sh` after
  `tests/scorecard-programs.sh`; in the `new-experiment.sh` row add `[--base-arms
  <label>=<ref>,…]` to the synopsis and the refusals; in the `run.sh` row mention base
  arms beside the agentTooling pin; in the `scorecard.py` row the reading table; in the
  `lib.sh` row `harness_experiment_arm_kind`.
- **Adding one** step 5 (line ~86): after the `--agent-tooling` sentence, one sentence for
  `--base-arms old=<sha>,new=<sha or ref>`.
- **Arms** (line 218): retitle `## Arms: pinning an agentTooling version, or a commit` and
  add a second paragraph from the rulings above (base arms, one kind per experiment, no
  programs, the vendored-copy caveat, the row's `arm_kind` / `base`).
- **Stages**, step 1 setup (line ~272): "add the worktree at `base` (a base arm's commit
  for a base arm)"; step 7 capture: one sentence for `do_reading_metrics`.
- **`experiment.json`** (line 461): add `base_arms{<label>: <sha>}?` to the shape and a
  paragraph after the `agent_tooling` one.
- **The ledger row** (line 515): insert `arm_kind` after `agent_tooling`, and
  `read_files_before_edit, read_bytes_before_edit, readme_bytes_read` after
  `cost_lost_usd`, in the field list (every field listed — README Rule 1); then a
  paragraph each for `arm_kind` (with the absent-field reading) and the three reading
  fields; and amend "`arm` is the arm's label and `agent_tooling` the upstream commit…" to
  cover a base arm (`agent_tooling` empty, `base` the arm's commit).
- **The program row** (line 536): one sentence after the intro paragraph: the program row
  and its `features[]` carry neither `arm_kind` nor the reading fields, and a program
  cell cannot run under base arms.

## `harness/SPEC.md`

- §6 (line 267): add `arm_kind` and the three reading fields to the field list, and one
  sentence to the `scorecard.py renders` paragraph for the reading table.
- A new section at the end, `## 15. Base arms and reading metrics (added 2026-11-03)`,
  naming `self/features/harness-arm-base/`, in §12's register: what each half does, the
  one-kind and no-programs refusals, the reading definitions and window, and that program
  rows are unchanged.

## `harness/EXPERIMENTS.md`

"Setting up the arms" (line 106): one paragraph after the first, on comparing two commits
of the measured repository (a restructure branch's tip against the commit it was cut
from) with `--base-arms`: the fixture stays the same, both commits must be in the
repository the experiment lives on, and an experiment varies one thing.

## `harness/tests/README.md`

The paragraph under the table (lines 10–20): "runs all three" → all five, naming the steps
`harness arm base self-test` and `harness reading metrics self-test`, and add their two
`./agentTooling/harness/tests/…` lines to the run-alone block.

## `self/PROJECT_FACTS.md`

"Tests" (lines 172–176): list `harness/tests/arm-base.sh` and
`harness/tests/reading-metrics.sh` beside the existing three harness tests; the
`py_compile` bullet (line 161) adds `harness/reading_metrics.py`.

## `CLAUDE.md`

The "Mechanical gate" line: "the harness's three tests" → "the harness's five tests".

## `self/BACKLOG.md`

Append two entries in the file's shape (bold title, the assertion that would catch it,
`Raised by \`harness-arm-base\`.`):
- **Program cells carry no reading metrics.** Assertion: a program row's `features[]`
  entries carry `read_files_before_edit`, `read_bytes_before_edit` and
  `readme_bytes_read`, measured over each implementer's window in its feature worktree.
- **Base arms do not combine with programs.** Assertion: an experiment with `base_arms`
  and `programs` cuts each program cell's program branch and non-dependent feature
  branches at the arm's commit instead of `program.json`'s `base`.
