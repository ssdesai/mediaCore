# 84 — review: stale-failed-sidecars

Independent review of one direct-built feature's diff. Written before the build, from
the manifest and the brief that produced it; nothing here comes from the builder's
report. `run-review.sh` refuses a brief still carrying the stub marker, so this file
being written is itself the gate on the build having started from a spec.

## What the feature was supposed to do

`self/features/stale-failed-sidecars/README.md` — the summary paragraph, "The defect",
"The rulings" and "Deliberately excluded". Read all four before the diff and hold it to
them ruling by ruling. The rulings are not reopened: a diff that picked a different
design for one of them is a finding, however good the design.

In one sentence: a plan whose first run was killed and whose retry succeeded leaves a
`.progress.md` + `.usage.json` pair in `<queue>/failed/` with no `.md` beside it, and
`analysis/report.py` must survive that — deterministically picking the live sidecar,
warning rather than crashing on the absent plan file, and counting the killed attempt's
money exactly once — without the runner touching the `failed/` pair at all.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`analysis/report.py` (the index and its callers, the sibling-`.md` readers),
`analysis/README.md` (the `report.py` entry describing the index), `RUNNER.md` (the
`failed/` paragraph), a new `self/tests/stale-failed-sidecars.sh`, `self/gate.sh` (two
registrations), `self/tests/README.md` (the new test's row), a new `self/BACKLOG.md`,
and this feature's own directory — `README.md`, `NOTES.md`, `CHECKPOINT.md`,
`timing.jsonl`, this brief — which is the record, not the feature.

`plan-runner-lib.sh`, `feature-close.sh` and `analysis/recover_attempts.py` should not
appear in the diff at all. They belong to the sibling feature `recover-cost-at-close` or
are out of scope by ruling; any hunk touching them is a finding on its own.

## Contracts to hold it to

- **The index is deterministic and plan-aware.** `build_usage_index` must never depend
  on `rglob` order. For a stem with several usage files: the live one is the one whose
  sibling `<stem>.md` exists; ties (or a total absence of siblings) break by directory
  rank `complete` > `inprogress` > `incomplete` > `failed`; candidates are sorted before
  either rule is applied. Check the tie-break is total — two candidates in the *same*
  state directory must still resolve to the same file on every run. Read the sort key,
  not the prose about it.
- **The index's return shape is one shape, and every caller consumes it.** Whether it is
  a dataclass or a `(live, priors)` tuple, `grep -n usage_index analysis/*.py` must show
  every reader updated to the new shape — `manifest_plan_stems`, `load_manifest_plans`,
  `find_orphan_usage` and the call site in `run_single_feature` at minimum. A caller
  still treating the value as a bare `Path` is a finding even if it happens to work.
- **The old docstring sentence is gone.** "whichever file rglob reached last" described
  the defect; if it survives, the docstring now lies about code that no longer behaves
  that way. The replacement must state the sibling rule and the directory rank.
- **A missing sibling `.md` is a warning, never a crash.** `grep -n "with_name"
  analysis/*.py` finds every sibling lookup; each `.read_text()` on one must be guarded,
  the plan skipped from that table, and one warning line emitted naming the path that
  was looked for. `compute_plan_length_vs_loc` is the one that crashed;
  `compute_plan_drift` reads a `.md` the same way and must be guarded too. A function
  that gained a warning must have gained a `warnings` parameter and had its call site
  updated — a warning appended to a list nobody renders is not a warning.
- **A prior attempt's money counts once, and is not dropped.** In `compute_cost_rollup`,
  a plan's cost is the live sidecar's `total_cost_usd` plus, per prior attempt, its
  `total_cost_usd` when non-null and its `attempts[].recovered_cost_usd` when present.
  Check both directions: the sum is right when a prior attempt has a recovered figure,
  and nothing is double-counted when the same money is reachable by two routes. A plan
  is "priced without cost" only when the live file has null cost **and** no prior
  attempt contributed anything.
- **The unpriced-plan warning's wording is unchanged.** The sibling feature
  `recover-cost-at-close` owns that string. What triggers it may change; the text may
  not. Diff the literal.
- **The `failed/` pair is untouched, and that is documented as a decision.** No hunk
  moves, renames, deletes or rewrites anything under `failed/` — it is the record of the
  killed attempt and carries the session id `recover_attempts.py` needs. `RUNNER.md`'s
  `failed/` paragraph must say so in the affirmative: after a retry succeeds a stale
  pair may sit there beside nothing, and the analysis handles it. A paragraph that reads
  as an apology or a TODO is a finding.
- **`recover_attempts.py` still reaches the `failed/` sidecar.** It walks the tree with
  its own `rglob`, not through the index, so the change must not have narrowed what it
  visits. `NOTES.md` must state this as a checked finding, not an assumption.
- **The test was RED first, and is red without the fix.** `self/tests/stale-failed-sidecars.sh`
  in the style of `self/tests/cost-recovery.sh`: throwaway `mktemp -d` checkout, no
  model, no network. It must stand up a `complete/` set with a priced usage file and a
  `failed/` progress+usage pair with null cost and no `.md`, the manifest listing the
  stem once, and assert (a) `report.py` exits 0; (b) the reported cost is the
  `complete/` file's; (c) with a `recovered_cost_usd` planted in the `failed/` file's
  `attempts[]`, the reported cost is the sum; (d) the same layout with `failed/` created
  first still picks `complete/`. Verify (d) actually exercises ordering rather than
  passing vacuously, and that `NOTES.md` records the pre-fix failure line verbatim.
  Check each assertion would go red against `main`'s `analysis/report.py`.
- **`./self/gate.sh` is green and the new test is registered twice** — in
  `shell_scripts` (for `bash -n`) and as its own `record` line. The gate does not glob;
  a test added to only one of the two lists runs half. `self/tests/README.md` gains a
  row in the shape of its neighbours, naming what the script depends on that its imports
  do not show.
- **`self/BACKLOG.md` exists in `~/dev/vinylCatalogue/plans/BACKLOG.md`'s shape** —
  header paragraph, one bullet per item, bold lead sentence, the assertion that would
  catch it, `Raised by \`<slug>\`.` Its first entry is `stream_shows_usage_limit`'s
  blindness to a hard-killed session. Entries describe what was found and left, never
  what was fixed here.
- **bash 3.2 and the repo's shell rules** (`self/PROJECT_FACTS.md`): no associative
  arrays, no `${var^^}`, `${a[@]+"${a[@]}"}` for a possibly-empty array under `set -u`;
  `set -uo pipefail` with no `set -e`, so any status the script branches on is checked
  with `if`, never left to `-e`.
- **The no-recompute contract holds.** `report.py`'s module docstring forbids it calling
  `compute_cost` or repricing any figure. A prior attempt's dollars are read from disk
  and summed, never derived. Check no new import of `pricing`'s cost functions appeared.
- **Every touched folder's README is current** (`CONVENTIONS.md` → "Keeping READMEs up
  to date"): `analysis/README.md`'s `report.py` entry describes the index's new shape and
  the prior-attempt rule, and `self/tests/README.md` carries the new row.

## Verdict

"No findings" is a legitimate verdict. Findings are phrased as assertions — what must
hold, and what in the diff does not — with the file and line. Local findings (a stale
README row, a missing `shell_scripts` entry, a test that passes vacuously, a docstring
still describing the old behaviour) are fixed here and listed as fixed. Anything
structural — an index shape a caller does not consume, a ruling implemented as a
different design, a runner change that files or deletes the `failed/` pair — is a
finding for the human, not a rework done here.
