# 01 — review: carry-stream-sections

## What the feature was supposed to do

Stop `report.py` from destroying a frozen report's stream-derived sections when it
re-renders the report with the streams gone. `*.stream.jsonl` is gitignored and exists
only in the worktree the runner ran in. `feature-capture.sh` step 5 annotates every other
frozen record whose `sessions[].also_claimed_by` changed, re-runs `report.py` on each, and
commits the result in the closing feature's cost-records commit. With the streams gone,
"LoC changed", "Re-hunting" and "Cross-plan edit overlap" became `not computed: streams
unavailable`, so one feature's PR rewrote another feature's frozen report
(humanNetworkMap, 2026-09-23).

The fix treats the committed `report.json` as the frozen record of what the streams said.
When there is no stream to compute from, `report.py` carries the previous report's value:
- per plan for `plan_length_vs_loc[].loc_changed`, when that plan's stream is missing and
  the previous report has an integer for the same plan;
- the whole section for `re_hunting` and `edit_overlap`, when *no* plan has a stream and
  the previous report holds a computed list.

When some streams exist, behaviour is unchanged. With no previous report, or an unreadable
one, the old `not computed` value stands. Separately, `self/BACKLOG.md` gains an entry for
the interrupted `feature-start.sh` defect.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`analysis/report.py` (the three `compute_*` functions, a reader for the previous report,
and the call site in `run_single_feature`), `self/tests/report-footnotes.sh` (a new
phase 12), `analysis/README.md` and `self/tests/README.md` (the `report.py` and
`report.json` entries, and the test's row), and `self/BACKLOG.md`.

## Contracts to hold it to

- **A re-render with every stream gone changes nothing the streams decided.** Over an
  unchanged corpus it writes nothing at all: `write_record`'s masked comparison finds the
  same body. After `planning.json` changes, the only differences are those that change
  causes.
- **A stream that exists always wins.** Stream present means the value is computed fresh,
  never carried, even when the previous report disagrees.
- **Carry only a computed value.** A previous `not computed …` string, a non-integer
  `loc_changed`, a missing key, a missing `report.json`, or one that does not parse leave
  the old `not computed` result in place. None of them may raise.
- **Carry by plan, never by position.** A `loc_changed` is carried only onto the row for
  the same plan stem.
- **The partial-stream path is unchanged.** At least one stream present means re-hunting
  and edit overlap compute from what exists and warn about the rest, as before.
- **No new warning, mark or key in the report for a carried value.** Any of those would
  itself be a diff on every re-render, which is the defect.
- `--all`'s gap-filling (`fill_missing_reports`) and `--rounds-md` behave as before.
- The code reads like the rest of the file: the `not computed` sentence is one named
  constant rather than three literals, and the call site passes the previous report the
  way the other inputs are passed.
- The READMEs describe the carry accurately, including in the `report.json` field list's
  `| "not computed: streams unavailable"` alternatives (CONVENTIONS.md → "Keeping READMEs
  up to date").

Out of scope: `feature-capture.sh`'s annotate step itself is unchanged by design. A
concurrent feature, `litellm-pricing`, edits `report.py`'s pricing import and "Rates last
verified" footer, and `analysis/README.md`'s `pricing.py` entries. Those regions are not
this feature's.

## Verdict

"No findings" is a legitimate verdict. Report only defects against the contracts above,
each one with the concrete sequence of events that triggers it.
