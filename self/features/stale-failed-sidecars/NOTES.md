# Notes: stale-failed-sidecars

Rulings made where the manifest left the call open, each with a one-line rationale, plus
the pre-fix RED evidence, what was checked rather than assumed, and open questions. The
manifest's decisions are not reopened here.

## What changed, and why

- **`analysis/report.py::build_usage_index` returns `PlanUsage(live, priors)` per stem
  instead of one path.** Candidates come from `sorted(feature_dir.rglob(...))` — sorted
  before anything looks at them, so filesystem order never reaches the decision — and are
  ranked on `(sibling <stem>.md exists, USAGE_STATE_PREFERENCE index, path string)`. The
  losers are returned rather than dropped, because their dollars are real.
- **`USAGE_STATE_PREFERENCE = ("complete", "inprogress", "incomplete", "failed")`** and
  `usage_state_rank`, built on a new `find_state_segment`. `find_queue_segment` was
  already walking up to the state dir to survive archived batches nested under
  `complete/<branch>/`; that walk is now `find_state_dir`, shared by both, so the queue
  and the state are read the same way and cannot drift.
- **`read_plan_md(stem, usage_path, warnings)`** is the single reader of a sibling plan
  file. `compute_plan_length_vs_loc` and `compute_plan_drift` both go through it and both
  gained a `warnings` parameter; their call sites in `run_single_feature` were updated.
  The other four `with_name` hits in the file are `.stream.jsonl` lookups that were
  already `.exists()`-guarded.
- **`prior_attempt_cost(stem, usage_index, warnings)`** and `compute_cost_rollup`'s new
  `usage_index=` parameter. A plan's queue total is the live sidecar's `total_cost_usd`,
  plus its own `attempts[].recovered_cost_usd`, plus each prior's top-level
  `total_cost_usd` where non-null and its `attempts[].recovered_cost_usd` where present.
  `cost.recovered` gains the priors' recovered dollars for the same reason it holds the
  live file's: they came from a transcript, not from the CLI.
- **Docs**: `analysis/README.md`'s `report.py` entry (the index's new shape, the ranking,
  the prior-attempt rule, the missing-`.md` guard), `RUNNER.md`'s `failed/` paragraph
  (ruling 1, stated as a decision), `self/tests/README.md` (the new test's row),
  `self/README.md` (the `tests/` row and a `BACKLOG.md` row), and `self/BACKLOG.md`.

## Rulings

- **`(live, priors)` as a `typing.NamedTuple`, not a `dataclass`.** The brief offered
  either. `PlanUsage` is a tuple, so `live, priors = usage_index[stem]` works and the
  shape stays destructurable the way the old bare `Path` was assignable; a dataclass
  would have bought nothing here and `dataclasses` is one more import for two fields.
- **The rollup reads the index, not a widened `loaded_plans`.** The alternative was to
  make `load_manifest_plans` return 4-tuples carrying the priors. Eight call sites unpack
  those triples (`compute_cold_start_tax`, `compute_model_fit`, `compute_churn`,
  `compute_time_rollup`, `compute_plan_length_vs_loc`, `compute_re_hunting`,
  `compute_plan_drift`, `compute_edit_overlap`, plus the `files_edited` loop), none of
  which has any use for a prior attempt — priors carry no plan file, no stream and no
  `files_edited`. Passing `usage_index` to the one function that needs it keeps the
  triple contract intact and puts the new coupling where the money is computed.
- **`priors` are re-read from disk in the rollup rather than cached in the index.**
  `build_usage_index` already parses every sidecar to find its `plan` field and throws
  the data away; keeping it would make the index hold every sidecar's full JSON to serve
  the one function that reads a prior. A prior is rare and small.
- **The missing-`.md` warning is deduplicated by exact message.** Two tables reading the
  same absent file is one fact about the tree, not two, and `read_plan_md` is called once
  per table per plan. The dedupe lives in the helper so a third reader gets it free.
- **`prior_attempt_cost` follows the ruling's two levels literally** — top-level
  `total_cost_usd` for measured dollars, `attempts[].recovered_cost_usd` for recovered
  ones — and they cannot double-count: `recover_attempts.py` fills an attempt's recovered
  figure only where that attempt's `total_cost_usd` is null, and a null attempt
  contributes nothing to the top-level sum the CLI wrote.
- **A prior sidecar that will not parse warns and is skipped**, matching
  `build_usage_index`'s own `except (OSError, json.JSONDecodeError): continue`. It is by
  definition not the file the report is built on, so it must not be able to end the run —
  which is the whole lesson of the defect.
- **The roll-in is announced.** A plan whose priors contributed anything gets a warning
  naming the count and the dollars. Silent extra money in a total is the failure mode
  `find_orphan_usage` exists for; a prior attempt is the same money arriving by a
  different route.
- **The unpriced-plan warning's wording is untouched**, per the brief — only its trigger
  changed, gaining `and not prior_total`.
- **Nothing under `failed/` is written, moved or deleted by any code in this diff**, and
  no runner file is touched at all.

## The pre-fix RED line

`self/tests/stale-failed-sidecars.sh` was written first and run against this branch's
then-unmodified `analysis/report.py`: **17 of 18 assertions FAILED**. The failure is the
vinylCatalogue `group-commit-all-adjudication` crash reproduced exactly —

```
  File ".../analysis/report.py", line 1432, in run_single_feature
    plan_length_vs_loc = compute_plan_length_vs_loc(loaded_plans)
  File ".../analysis/report.py", line 848, in compute_plan_length_vs_loc
    plan_md_lines = len(md_path.read_text().splitlines())
FileNotFoundError: [Errno 2] No such file or directory:
  '.../self/features/sfs-stale/review/failed/01-review-opus.md'
```

— so `report.py` exited 1 and wrote no `report.json`, and every assertion reading one
failed with it. The single pre-fix pass was `6a` (two candidates that both have a sibling
`.md` do not crash), and `6b` beside it failed, which is what showed the choice between
them was filesystem order. Phase 6 was later re-fixtured: the two plan files are now
different lengths so the plan-length row names the winner, since the original `6b` asserted
the *total* was the live figure alone — wrong under ruling 4, which rolls a prior's
measured dollars in. The reworked phase asserts both halves (`complete/` is live; the
outranked sidecar's `$9.75` is still counted). Post-fix: **20 of 20 pass**.

## Ruling 5: does `recover_attempts.py` still reach the `failed/` sidecar?

**Yes, unaffected.** Read at `analysis/recover_attempts.py:138`: its main loop is
`for usage_path in sorted(features_dir.rglob("*.usage.json"))` over
`roots.features_root(self_mode)`. It walks the feature tree itself, imports only
`pricing`, `transcript` and `roots`, and never calls `build_usage_index` or imports
`report` at all — so it visits every sidecar in the tree including the `failed/` one,
exactly as before, and finds the killed attempt's `session_id` there. That is the
mechanism ruling 1 protects: the pair is the only surviving copy of that id, and the
index's ranking now keeps the file discoverable for the report without it having to be
the live one.

## Verification beyond the new test

`analysis/report.py` was re-run over the two committed self features that have report
artifacts (`sweep-and-check`, `feature-lifecycle`). Both `report.json` files came back
**identical field for field** with only `generated_at` differing, and both `report.md`
files differed on their `Generated …` line and nothing else. The regenerated copies were
restored, so neither feature's committed record moved. Neither has a same-stem twin, which
is the point: the new ranking is a no-op wherever the old dict was already unambiguous.

## Gate

`./self/gate.sh` from this worktree: **`all checks passed`**, 49 recorded sections, 0
FAIL, 0 SKIP. 33 `bash -n` parses (including the new
`self/tests/stale-failed-sidecars.sh`), 13 behavioural self-tests all green — the new
`stale failed sidecars self-test` among them, and `cost recovery self-test`,
`capture guard self-test`, `direct timing self-test` and `feature lifecycle self-test`
unchanged beside it, which is what says the index's new shape did not move any existing
`report.py` assertion — `py_compile analysis`, and the two informational checks (rate
table current, `claude` and `jq` on PATH). `shellcheck` is not installed on this machine
and the gate skips it by design without counting a skip.

## Open questions

- **Should a prior attempt with neither a cost nor a recovered figure mark the total a
  lower bound?** Ruling 4 defines "priced without cost" from the live file and the
  priors' contribution, and says nothing about partiality, so it does not. That is right
  for the case that raised this feature — vinylCatalogue's killed run was cut off before
  anything was billed, `total_cost_usd: null` with all-zero usage — but a kill that
  really did bill would read as free until someone runs `recover_attempts.py`. Widening
  `total_is_partial` silently would change what that flag means for every feature in both
  corpora, so it is a `self/BACKLOG.md` entry with the assertion that would catch it, not
  a change made here.
- **`prior_attempt_cost` does not deduplicate an attempt reachable through both
  sidecars.** No route the runner takes can produce that overlap (`write_usage_sidecar`
  merges `attempts[]` by `session_id` into the sidecar at the plan's *current* path, and
  a plan moved back to `incomplete/` and re-run starts a fresh file at its new home), and
  the ruling specifies the prior's contribution at file level for cost and attempt level
  for recovery, which is where it is implemented. Also in the backlog.
- **`stream_shows_usage_limit`'s blindness to a hard-killed session is left unfixed**, by
  the manifest's own exclusion list — it is runner routing, it belongs to a different
  file, and fixing it would not have prevented this crash (the rc==2 path leaves the plan
  in `inprogress/`, which a manual retry moves the same way). First backlog entry.

## Left to the coordinator

- The manifest fence's `subagents` is untouched — the coordinator pins the implementer's
  agent id there before `feature-close.sh` runs (`AGENT_DIRECT.md` → "The feature
  directory").
- `self/BACKLOG.md` is new here and the sibling feature `recover-cost-at-close` may
  create the same file. A merge conflict on it is expected and resolves keep-both: the
  entries are independent and neither file's header paragraph differs in substance.
