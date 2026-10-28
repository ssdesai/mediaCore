# 06 — retract "unrecoverable", wire the self-test into the gate

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Plan 6 of 6 build plans. Documentation and one gate line. No behaviour changes.

## 1. The gate

`self/gate.sh` runs its behavioural checks under `=== gate: level sentinels ===` with

```
record "level sentinel self-test" bash self/tests/level-sentinel.sh
record "tiered gates self-test" bash self/tests/tiered-gates.sh
```

Add `record "cost recovery self-test" bash self/tests/cost-recovery.sh` alongside them.
Blocking, not `record_info` — every assertion in it is a contract `recover_attempts.py` and
`report.py` branch on. Also add `self/tests/cost-recovery.sh` to the `shell_scripts` array
in the `=== gate: shell syntax ===` section, so `bash -n` covers it like its neighbours.

## 2. The claim to retract

`analysis/README.md`, in the `usage.json` field-list entry, currently says:

> An attempt with `total_cost_usd: null` is one that was killed before writing a `result`
> event: its spend is real but unrecoverable, which is why `report.py` marks any total
> containing one as partial.

This is now false in its main clause and in its consequence. Replace it with the true
statement: such an attempt has no CLI-reported cost, but its spend is recoverable from its
session transcript by `recover_attempts.py` while that transcript survives; a recovered
attempt carries `recovered_cost_usd` and no longer makes a total partial; only an attempt
whose transcript has aged out does.

Then check these two for the same claim and correct any copy you find — do not assume, read
them: `plan-runner-lib.sh`'s `write_usage_sidecar` comment block, and `AGENT_PLANS.md`
wherever it describes `usage.json` or killed attempts.

## 3. The weekly cadence

`analysis/README.md` → "How to run them" lists a numbered order that is a real dependency
chain. `recover_attempts.py` reads sidecars and must run **after** `backfill_usage.py`
creates them and **before** `report.py` reads them. Add it as its own numbered step between
the two, with the `--self` variant shown, matching the existing entries' form.

Extend "Why the cadence matters" with the retention point: a killed attempt's cost is
recoverable only while its transcript survives under `~/.claude/projects/`. That section
already makes exactly this argument for `capture_planning.py`; this is a second instance of
it, not a new idea.

## 4. Owed work

Record in `analysis/README.md`, near the rate-table step, that every `planning.json` frozen
before 2026-08-22 was priced with the intro tier applied retroactively and is therefore
roughly 33% low, and that correcting them means re-running `capture_planning.py` per feature
and committing the diff. This batch deliberately does not do it (see the feature manifest).
State it as owed work with the reason, not as a warning without a remedy.

## Done when

`bash self/gate.sh` is green, including the new self-test line, and no README in
`agentTooling/` still claims a killed attempt's cost is unrecoverable.
