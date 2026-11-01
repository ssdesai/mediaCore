Verdict: escalated

# Review: program-cells

## What the batch was supposed to do

Add the driver for `kind: "program"` ledger rows: one headless orchestrator session
(`--session-id`, then `--resume` once per feature and once for the record), plus one
top-level implementer `claude -p` per feature, each in its own worktree. Dependent features
are cut at the previous feature's tip. `cost_overhead_usd` is priced with the driver's
analysis copy. There is a version floor, `orchestrator` is a reserved method name, and the
ordinary-cell path must be unchanged. The contract is `harness/README.md` → "The program
row" and `harness/tests/scorecard-programs.sh`.

## Does it do it

Mostly, yes. The gate is green, with no SKIPPED checks. On reading:

- **Row shape.** `build_program_row` produces every top-level and `features[]` field the
  README lists. The dollar fields are JSON numbers, `position` is 1-based, and
  `cost_group_usd`, `cost_group_green_usd` and `overhead_pct` use the stated arithmetic.
- **Ordinary cells.** The `run.sh` refactor (`require_fixture` / `read_fixture_fields` /
  `reset_cell_results`, `setup_tree`, `START_POINT`, `GATE_RED_FATAL`) is behaviour-neutral
  for them. `START_POINT` falls back to `$BASE`, `GATE_RED_FATAL` defaults to 1, and program
  cells run after every ordinary cell. No program global is left set where a cell could read
  it.
- **Resume.** A `--from` resume re-derives everything from `program.json`,
  `experiment.json` and the state files. The session chain (`orchestrator_sessions[]`, the
  latest id resumed, `orchestrator_session_starts` per id) is persisted.
- **Isolation.** The isolation paragraph is in `program-brief.md`, and no stage reads across
  feature worktrees.
- **`program.json` checks** run in both `new-experiment.sh` and `run.sh`.
- **Docs.** `SPEC.md` §13, `EXPERIMENTS.md` and the READMEs agree with the code, with one
  exception (escalation 1).

## Fixed in this pass

1. `harness/new-experiment.sh`: the program-name/fixture-name check only compared against
   the experiment's own `--fixtures`. The README rule is "never the name of a fixture", and a
   program's own feature fixtures also key `branch_stem_override`. So a program named like
   one of its features passed, and an override would then rename both the program branch and
   that feature's branch. The check now also refuses any existing
   `plans/experiments/fixtures/<program>/` directory.
2. `harness/program-stages.sh`: `HARNESS_PREV_OUTCOME` was `export`ed. That put the previous
   implementer's report into the environment of every later child process, including the
   next feature's implementer. Nothing needs the export, because the template is filled in
   the same shell. Both assignments are now plain. `bash -n` passes on both files.

## Escalated to the next round

1. **`unpriced_reason` is never produced** (`harness/program-stages.sh:837`). The row reads
   `$s.unpriced_reason // null`, but no stage writes that key, so every feature reports
   `null`. Two documents promise otherwise:
   - `harness/README.md` says it "is `null` when `cost_method_usd` is real".
   - `harness/EXPERIMENTS.md` → "Program cells", assumption 3, says a misplaced implementer
     transcript "prices at `$0` with an `unpriced_reason`".

   As built, an unmeasured feature looks like a cheap one. That is the silent spoiling the
   paragraph warns about, and `scorecard.py:431` has a note path that can never fire.

   **Next round:** in `do_program_capture`, after `do_capture`, set `unpriced_reason` in the
   feature state. Proposed cases:
   - the feature's manifest directory is absent: no implementer ran;
   - `cost_method_usd` is 0 while `cost_method_reported_usd` > 0: the capture missed the
     session;
   - the capture's total is partial.

   Exactly which reasons to use is a design decision. Add a smoke assertion that a feature
   whose captured cost is 0 against a non-zero reported cost carries a non-null
   `unpriced_reason`.
2. **No test checks the program row's arithmetic.** The smoke full run only checks that
   `cost_overhead_usd`, `cost_group_usd` and `overhead_pct` are numbers.
   `scorecard-programs.sh` uses hand-built rows, so it never exercises `build_program_row`.

   **Next round:** in the full-run section of `harness/tests/smoke.sh`, assert:
   - `cost_group_usd == cost_overhead_usd + Σ features[].cost_method_usd` (4-dp rounding);
   - `cost_group_green_usd == cost_group_usd + Σ (cost_review_usd + cost_rework_usd)`;
   - each feature's `cost_green_usd` is its method, review and rework cost summed;
   - `overhead_pct == cost_overhead_usd / cost_group_usd × 100`.

   Use a non-zero overhead so the ratio is not 0/0. The section already fabricates
   transcripts for `program_cost.py`, so it can reuse them.
3. **A killed first orchestrator call cannot be resumed cleanly**
   (`harness/program-stages.sh` `orch_invoke` / `orchestrator_call`). `orchestrator_calls`
   only goes up once a result reports a session id or the call exits 0. If the harness
   process is killed during the brief call, after `claude` has already created session `S`,
   then `--from brief` sends `--session-id S` again. The real CLI refuses an id that is
   already in use. That call fails, the program is marked `method_failed`, and the loop is
   skipped.

   **Next round:** before the first call, persist a marker that it was started. On re-entry
   with `orchestrator_calls == 0` and the marker set, either mint a fresh id (recording it in
   `session_id`) or `--resume S`. Either way, add the behaviour to `EXPERIMENTS.md`'s list of
   assumptions to rehearse against a real `claude`.

## Notes (not escalated)

- `--from` now accepts the program stage names. With `--from loop` or `--from collect`, an
  ordinary cell in the same experiment runs no stage and returns 0, where before such a
  `--from` was rejected. Only input that used to be invalid is affected; mentioned so it is
  a visible decision.
