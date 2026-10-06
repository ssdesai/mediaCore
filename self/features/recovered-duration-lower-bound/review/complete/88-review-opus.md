# 88 — review: recovered duration lower bound, close advice, shared sessions

Independent review of one direct one-shot's diff. Written before the build, from the
manifest; nothing here comes from the implementer's report, and the implementer did not
write it. "No findings" is a legitimate verdict.

## What the feature was supposed to do

`self/features/recovered-duration-lower-bound/README.md` → "The decision, in full": three
items, seven numbered points, and the assertion under "Assertion the feature is judged
by". Read them first and hold the diff to them point by point. The line that must not
blur: a recovered duration is a **lower bound**, marked as such everywhere it appears,
and never sits in a column as if measured.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`analysis/recover_attempts.py`, `analysis/report.py`, `analysis/capture_planning.py`,
`feature-close.sh`, tests under `self/tests/` with their README rows, `analysis/README.md`
(the sidecar and report shapes are documented there — `recovered_duration_s`,
`time.recovered_duration_plans[]`, `cost.shared_sessions[]`, `also_claimed_by` must all
appear), `self/BACKLOG.md`, and `self/features/recovered-duration-lower-bound/` itself —
`CHECKPOINT.md`, `NOTES.md` — which is the implementer's record, not the feature.

## Contracts to hold it to

- **A measured `duration_ms` is never overwritten or shadowed** by a recovered figure;
  recovery runs only where `duration_ms` is null.
- **The span is first-to-last of the timestamped lines the transcript walker already
  yields**, UTC via `transcript.to_utc`, not a re-parse; fewer than two lines writes
  nothing.
- **Idempotence and `--force`** behave exactly as they do for `recovered_cost_usd`; a
  missing transcript leaves the sidecar byte-identical.
- **`time.total_is_partial` stays `true`** for a plan priced by recovery, with a reason
  string that says "transcript span"; the plan is in `recovered_duration_plans[]` and not
  in `missing_duration_plans[]`.
- **One mark per meaning** in `report.md`: the recovered-duration mark is defined beside
  `MISSING_FIGURE_MARK` and its footnote names plan, seconds and source. A plan with no
  transcript renders exactly as before this feature (diff a before/after report over the
  existing fixture corpus if the tests do not already).
- **Item 2**: the stop-on-unpinned rule in `feature-close.sh` step 3 is unchanged;
  only what is *printed* for already-pinned delegates changed, and `--unclaimed --for`
  now excludes ids present in the manifest's `subagents` or the ledger for that pair.
- **Item 3**: a session claimed by two features is not refused; the ledger's subagent
  refusal is unchanged; `also_claimed_by`, `cost.shared_sessions[]` and the footnote
  agree with each other; no apportionment anywhere.
- **Every script's own tests still pass** (`./self/gate.sh`), and no test reads
  `~/.claude` — the ledger tests point `CLAIMS_LEDGER` (or whatever override exists) at a
  temp file; if no override exists, adding one is in scope and documented.
- **`self/BACKLOG.md`** is exactly one entry shorter, header intact.

## Judgment calls to check

1. How the top-level sum of `recovered_duration_s` is kept in step with `attempts[]`, and
   that it mirrors the existing dollars mechanism rather than adding a second.
2. Whether a measured-plus-recovered bucket (one plan measured, one recovered) renders a
   figure the reader can tell is mixed.
3. The exact key the ledger uses for session claims and whether an old ledger file
   without that section still loads.

## Verdict

Findings, each with file:line, the contract it breaks, and whether it is local (fix in
this pass) or structural (escalate). Then one line: **pass**, **pass with fixes**, or
**escalate**.
