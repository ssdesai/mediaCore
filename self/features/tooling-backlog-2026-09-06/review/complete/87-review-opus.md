# 87 — review: tooling backlog, 6 September 2026

Independent review of one direct one-shot's diff. Written before the build, from the
manifest; nothing here comes from the implementer's report, and the implementer did not
write it.

## What the feature was supposed to do

`self/features/tooling-backlog-2026-09-06/README.md` → "The items, with the decision each
one is built to": ten items, each with its decision settled there, and the nine
`self/BACKLOG.md` entries they close removed. Read that section first and hold the diff
to it item by item. The decisions are not reopened; a diff that picked a different
design for one of them is a finding, however good the design.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`plan-runner-lib.sh` (item 1), `analysis/report.py` (items 2–6), `feature-close.sh`
(item 7), `analysis/backfill_usage.py` (item 8), `run-batch.sh` (item 9),
`templates/plans/README.md`, a new `templates/plans/BACKLOG.md`, `sync-plans.sh`,
`AGENT_DIRECT.md`, `AGENT_PLANS.md`, `templates/README.md`, `README.md` (item 10),
`self/BACKLOG.md`, self tests under `self/tests/` with their README rows, and
`analysis/README.md`. Also `self/features/tooling-backlog-2026-09-06/` itself —
`CHECKPOINT.md`, `NOTES.md` — which is the implementer's record, not the feature.

## Contracts to hold it to

- **Every runner and tooling change has a self test that pins it.** `self/PROJECT_FACTS.md`
  → Tests: a new contract belongs in `self/tests/`, never in a verify brief. For each of
  items 1–9 find the assertion; read it against the manifest's decision, not against the
  implementation; and check it would fail without the change (a scenario that passes on
  `main`'s copy of the script under test is not a test of this diff — checking `main`'s
  copy of that one file into the scratch checkout is a fair way to see).
- **`./self/gate.sh` is green**, with no SKIPPED check, and every new test script is
  wired into it the way the existing ones are.
- **bash 3.2** (`self/PROJECT_FACTS.md` → Conventions): no associative arrays, no
  `${var^^}`, `${a[@]+"${a[@]}"}` for possibly-empty arrays under `set -u`; no `set -e`
  in the runners; the SIGPIPE handler is `exec >/dev/null; printf "\n"` and never
  `trap '' PIPE`.
- **Item 1 both ways.** A stream with no `result` event ending in an `error` event naming
  429 or a rate/usage limit routes as a limit (plan in `inprogress/`, `exit_reason`
  naming it); a stream ending mid-turn with no such event still routes to `failed/`; and
  a `result` event whose text merely mentions a rate limit is still not one. The matcher
  must use `STREAM_EVENTS_JQ` — stderr is merged into the stream file.
- **Items 2 and 3 change the meaning of `total_is_partial` deliberately** and
  `analysis/README.md` says so. Check the dedupe by `session_id` counts an attempt once in
  the dollars *and* once in `unrecoverable_attempts[]`, and that a priced prior sidecar is
  still added exactly as before.
- **Items 5 and 6 share one rendering.** The `†` and footnote are one mechanism used by
  both tables; the old **Unpriced plans** paragraph is gone, not duplicated;
  `time.missing_duration_plans[]` has exactly the `{plan, queue, reason}` shape of
  `cost.unpriced_plans[]`. A planned feature with nothing unpriced renders byte-identical
  to before (`python3 analysis/report.py --self test-first-levels` on `main` and on this
  branch).
- **Item 7 does not weaken the refusal.** With no refs and no manifest on `main`,
  `feature-close.sh <slug> --recapture` still refuses; the non-`--recapture` path is
  unchanged.
- **Item 8's sidecar is the live shape.** Compare the fields against what
  `write_usage_sidecar` writes for a run with no result event; a shape that only
  `backfill_usage.py` produces is a finding.
- **Item 10: the stub is seeded once and never overwritten**, like `PROJECT_FACTS.md`,
  and nothing in the diff touches a consuming repo. `sync-plans.sh --check` reports a
  missing `plans/BACKLOG.md` the way it reports the other seeded files.
- **`self/BACKLOG.md`** lost exactly the nine entries the items close, kept its header,
  and gained the one entry the manifest says this feature writes (the duration lower
  bound). No other entry was touched.
- **READMEs** (`CONVENTIONS.md` → Keeping READMEs up to date): `self/tests/README.md` for
  every test touched, in that file's paragraph-per-test style; `analysis/README.md` for
  every new report key; `templates/README.md` and `README.md` → Installing for the stub.

## Judgment calls to check

1. Item 1: how "last parsed JSON event" is found when stderr lines follow it, and that a
   stream whose *last* event is a `result` never takes the new path.
2. Item 7: what "tracked on `main`" and "ancestor of `main`" are checked against in a
   sandbox whose `main` is local — the test must not depend on a remote.
3. Item 9: where the trap is installed relative to the first banner, and that a child
   runner's own trap is unaffected (a handler is reset in children; `trap ''` is not).
4. Item 10: the skeleton's header must make sense in a consuming repo that has never
   seen `self/BACKLOG.md` — no reference to "this one is agentTooling's own".

## Verdict

Write it to the path the runner names, for the person approving the PR: what the diff
was supposed to do, whether it does it, then two lists — fixed in this pass, escalated.
Fix local defects here (a missing README row, a wrong message, an assertion that does
not bite); escalate structural ones, and write each escalation into `self/BACKLOG.md`
as an entry in that file's shape — an escalation that lives only in this verdict is not
recorded. "No findings" is a legitimate verdict; say it outright rather than
manufacturing concerns.
