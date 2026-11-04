# Tooling backlog, 6 September 2026: the nine `self/BACKLOG.md` items, plus the missing BACKLOG stub

Every entry in `self/BACKLOG.md` as of 2026-09-06 — raised by `stale-failed-sidecars`,
`recover-cost-at-close` and `stream-capture-file-first` — plus one defect found the same
day while surveying the consuming repos. None is large; together they are one direct
one-shot (`../../../AGENT_DIRECT.md`), the same shape as `tooling-backlog-2026-09`
(PR #27). This manifest is the spec: each item below carries the decision it is built
to, and `self/BACKLOG.md` loses each entry this feature closes.

## The items, with the decision each one is built to

1. **`stream_shows_usage_limit` recognises a hard-killed session.** Today it inspects only
   the final `result` event, so a session the platform cuts off at a usage limit — which
   never emits one — files as an ordinary failure. Add a second signal, scoped tightly:
   when the stream has **no** `result` event, and its last parsed JSON event is an
   `error`-typed event (parse with `STREAM_EVENTS_JQ`, skipping the merged-stderr lines)
   whose payload names HTTP `429` or a rate/usage limit in the same terms the existing
   matcher accepts, route as a usage limit — plan left in `inprogress/`, `exit_reason`
   naming the limit, the `rc == 2` branch of `finalize_plan`. Nothing else changes: a
   stream ending mid-turn with no such event still routes to `failed/`, and a `result`
   event that merely mentions "rate limit" in assistant text is still not a limit. Assert
   both cases in `self/tests/` with the stub `claude` writing a canned stream — a new
   `usage-limit-kill.sh` unless an existing scaffold fits better.
2. **A prior attempt with neither a cost nor a recovered figure marks the total a lower
   bound.** `compute_cost_rollup` (`analysis/report.py`) classifies the *live* sidecar's
   null-cost attempts; a prior sidecar in `failed/` is added when priced and silently
   absent when not. Widen ruling 4 of `stale-failed-sidecars` deliberately: a prior
   sidecar with `total_cost_usd: null` and no `recovered_cost_usd` anywhere in its
   `attempts[]` sets `cost.total_is_partial: true` and lists its `session_id` under
   `cost.unrecoverable_attempts[]`, exactly as a live one would. This changes what
   `total_is_partial` means for every feature in both corpora — that is the point, and
   `analysis/README.md` says so where it documents the flag. Assert in
   `self/tests/stale-failed-sidecars.sh`.
3. **An attempt reachable through two same-stem sidecars is counted once.** Item 2 makes
   the roll-up read priors at attempt level, which is the condition the backlog entry set
   for this being worth doing. Dedupe by `session_id` across the live sidecar and every
   prior of the same stem: dollars once, and one entry in `unrecoverable_attempts[]`.
   Assert beside item 2: two same-stem sidecars whose `attempts[]` share a `session_id`
   contribute that attempt's dollars once, not twice.
4. **A stem with more than one sidecar is reported as such.** `find_orphan_usage` cannot
   see a same-stem twin. Add `cost.multi_sidecar_stems[]` to `report.json` —
   `{plan, queue, count}` — and one line under the Cost table in `report.md` naming them
   (`Plans with more than one sidecar: <stem> (<count>)…`), absent when the list is
   empty. The existing per-plan roll-in warning stays. Assert in
   `stale-failed-sidecars.sh`: a feature with two sidecars for one listed stem reports it
   there.
5. **The Cost table's bucket row is marked when the bucket had unpriced work.** For every
   queue named by `cost.unpriced_plans[]`, `render_report_md` appends `†` to that row's
   dollar cell and emits one footnote line per marked row directly under the table —
   `† review: unpriced <stem> — <reason>` — replacing the separate **Unpriced plans**
   paragraph rather than duplicating it. Assert: a `cost` carrying an `unpriced_plans`
   entry with `queue: review` renders a review row that is not exactly
   `| review | $0.0000 | 0.0% |`, and the footnote names the stem and reason.
6. **The time roll-up says why minutes are missing, the way the cost roll-up does.**
   `compute_time_rollup` gains `time.missing_duration_plans[]` in the same
   `{plan, queue, reason}` shape as `cost.unpriced_plans[]` (today it is a bare list and
   one warning), and the Time table gives a bucket whose plan has a null `duration_ms` the
   same `†` and footnote treatment as item 5, so the review time row names the plan
   rather than printing `0.0`. Deriving a lower bound from the transcript's first and
   last instants is **not** in scope (see Deliberately excluded). Assert: a feature whose
   only review plan has a null `duration_ms` renders a review time row naming the plan,
   and `time.missing_duration_plans[]` carries the shape.
7. **`feature-close.sh --recapture` works after the branch is gone.** It resolves the
   slug as `refs/heads/<slug>` or `refs/remotes/origin/<slug>` and refuses "nothing to
   close" when neither exists, but a successful close deletes the local branch by design
   and a forge with delete-on-merge takes the remote one. With `--recapture`, when neither
   ref exists: proceed if the feature's manifest is tracked on `main` and its `<slug>:
   start` commit is an ancestor of `main` (that is the ancestry the refusal exists to
   check, knowable without the branch); refuse with the existing message only when that
   too is absent. The non-recapture path is unchanged. Assert in
   `self/tests/feature-lifecycle.sh` or `recover-at-close.sh`, whichever already closes
   a feature in its sandbox: delete both refs after a close, run `--recapture`, and see
   it re-capture and re-commit rather than refuse.
8. **`backfill_usage.py` writes a sidecar for a stream with no `result` event.** Today it
   returns early with `WARN: no result event … skipping`, so the plan lands in
   `missing_usage_plans` and reads as "never ran". Instead write the sidecar
   `write_usage_sidecar` would: `result_event: "missing"`, the session id from the first
   event, null figures — so `recover_attempts.py` can price it from the transcript later.
   Assert in `self/tests/cost-recovery.sh`: a `.stream.jsonl` holding an `init` event and
   assistant events but no `result` yields that sidecar, not a skip.
9. **`run-batch.sh` survives a closed stdout.** It sources only `plan-runner-roots.sh`
   and installs no SIGPIPE handler, so a coordinator that backgrounds it with its output
   piped onward kills the batch on its next banner. Install the same handler the runners
   use — `trap 'exec >/dev/null; printf "\n"' PIPE`, a handler and never `trap '' PIPE`,
   for the buffer-clearing reason `self/PROJECT_FACTS.md` records — before its first
   write. Assert: `run-batch.sh --self <slug>` whose stdout is closed after two lines
   still runs the build and verify passes, files their plans, and exits with the batch's
   code, not 141. Use the sandbox `level-sentinel.sh` / `tiered-gates.sh` already build,
   in a new `batch-sigpipe.sh` if neither file is the right home.
10. **The generated `plans/README.md` names `BACKLOG.md`, and `sync-plans.sh` seeds one.**
    Found 2026-09-06: humanNetworkMap had added a `BACKLOG.md` line to its
    `plans/README.md` by hand, and that morning's `update.sh` overwrote it, because the
    stub is `GENERATED` and `templates/plans/README.md` has no such line. Three edits:
    (a) `templates/plans/README.md` gains the entry, in this shape — "`BACKLOG.md` —
    escalations and decisions left open by finished batches, one entry per item phrased
    as the assertion that would catch it. Deferrals go here, not in a NOTES.md." — beside
    `PROJECT_FACTS.md`; (b) a `templates/plans/BACKLOG.md` skeleton (the same header
    `self/BACKLOG.md` opens with, adapted for a consuming repo, and no entries) that
    `sync-plans.sh` **seeds once and never overwrites**, exactly as it treats
    `PROJECT_FACTS.md`, reported by `--check` the same way; (c) one sentence each in
    `AGENT_DIRECT.md` → "The procedure" step 4 and `AGENT_PLANS.md` → "The feature
    manifest" (the Deliberately-excluded paragraph): anything a feature deliberately
    leaves unbuilt — an exclusion that is real work, a review escalation not taken, a
    defect found and not fixed — gets a `plans/BACKLOG.md` entry as part of that
    feature's work; a NOTES.md line is not a record. `templates/README.md` and
    `README.md` → Installing list the new stub; `self/tests/sync-check.sh` asserts the
    seed and the non-overwrite; `self/tests/template-versions.sh` gets whatever its table
    needs.

Then `self/BACKLOG.md` loses the nine entries items 1–9 close. The file keeps its header.

## Deliberately excluded

- A duration lower bound derived from a transcript's first and last instants (item 6's
  backlog entry mentions one). A transcript span is not the executor's wall clock, and
  `recover_attempts.py` would have to carry timestamps it does not read today; that is a
  design, and it stays in `self/BACKLOG.md` as its own entry, written by this feature.
- Any usage-limit signal beyond an `error` event naming 429 or a rate/usage limit (item
  1). No heuristics over assistant text; the false-positive hole the current
  implementation closes stays closed.
- Consuming repos' `plans/README.md` and the seeded `plans/BACKLOG.md` (item 10). They
  regain the line, and gain the stub where absent, on their next `update.sh`; nothing in
  this feature touches a consuming repo.

## Plans

| Plan | Model | Does |
|---|---|---|
| `87-review-opus` | opus | Independent review of the diff against `main`, from this manifest, not from the implementer's report. |

Built directly: no `auto/`, no `verify/`. `CHECKPOINT.md` and `NOTES.md` are the
implementer's.

## Machine-readable

```json
{
  "slug": "tooling-backlog-2026-09-06",
  "method": "direct",
  "plans": ["87-review-opus"],
  "branches": ["tooling-backlog-2026-09-06"],
  "base": "main",
  "session_window": {"from": "2026-09-06T22:18:44Z", "to": "2026-09-07T15:42:50Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["ed088063-7aea-498e-84b1-7503d4bd88e1"],
  "subagents": ["a4da240bf8e600f8b", "a81b3d1117dbb16ab", "a1253ddba7c3ffd5a"]
}
```
