# A recovered duration lower bound, and two things the closes of 2026-09-07 showed

`self/BACKLOG.md`'s one entry (raised by `tooling-backlog-2026-09-06`): a plan whose
`result` event is missing has a null `duration_ms`, so its bucket's minutes read `0.0`
with a `†` naming it, and nobody derives the number its transcript could give. The
entry calls that "a design, not an edit"; this feature is the design, built as one
direct one-shot (`../../../AGENT_DIRECT.md`). Closing seven features on 2026-09-07 with
`feature-close.sh` also surfaced two smaller defects in what the close prints and what
the report counts; they are items 2 and 3 because the fix for each sits in the same
files and the same run.

## The decision, in full

### Item 1 — `recovered_duration_s`

1. **`analysis/recover_attempts.py` derives a duration when it derives a cost.** For an
   attempt whose `duration_ms` is null and whose transcript is found, the span from the
   first to the last timestamped line `iter_billable_messages` already walks (as
   `analysis/transcript.py` parses them, UTC) is written on the attempt as
   `recovered_duration_s` (float, seconds), beside `recovered_cost_usd`. A transcript
   with fewer than two timestamped lines writes nothing. It is idempotent the way
   `recovered_cost_usd` is (`--force` re-derives). An attempt whose transcript is gone
   is untouched and reported exactly as today.
2. **The sidecar's top level carries the sum the same way it does for dollars** —
   whatever `write`/merge step keeps the top-level `recovered_cost_usd` in step with
   `attempts[]` does the same for `recovered_duration_s`; read the existing code and
   mirror it rather than inventing a second mechanism.
3. **`compute_time_rollup` (`analysis/report.py`) uses it as a lower bound.** A plan whose
   `duration_ms` is null but whose attempts carry `recovered_duration_s` contributes that
   figure to its bucket and to the total, and is listed under a new
   `time.recovered_duration_plans[]` with the same `{plan, queue, reason}` shape as
   `time.missing_duration_plans[]` plus `recovered_s`. It is *not* also listed under
   `missing_duration_plans`. `time.total_is_partial` stays `true` for it: a transcript
   span is not the executor's wall clock — it includes the model's own waiting and
   excludes whatever the runner did around the call — so the total is still a lower
   bound, and the reason string says why.
4. **The Time table renders it visibly distinct from a measured figure.** A bucket
   carrying a recovered duration is marked (a `‡` beside the minutes, or the existing
   `†` with a distinct footnote — one mark per meaning, defined next to
   `MISSING_FIGURE_MARK`) and the footnote below the table names the plan, the recovered
   seconds and that it is a transcript span. The "**This total is a lower bound**" line
   stays. A plan whose transcript is gone still renders exactly as today.
5. **`self/BACKLOG.md`** loses its one entry. Nothing else in that file changes.

### Item 2 — the close's "Pin each in …" advice when everything is already pinned

6. Every one of the seven closes printed the feature's delegates under "unclaimed
   delegates briefed for <repo>/<slug>" followed by `Pin each in <slug>'s manifest as
   "subagents": […]` — and then claimed every one of them as `pinned` in the capture.
   The list is `capture_planning.py --list-subagents --unclaimed --for <repo>/<slug>`
   (the advice line is at `analysis/capture_planning.py:789`), and "unclaimed" there
   means not claimed through a *branch*; a delegate pinned by this very manifest counts
   as unclaimed. Decision: a delegate whose id is in the manifest's `subagents` (or in
   the claims ledger for this `(repo, slug)`) is not unclaimed. `--unclaimed --for` drops
   it; `feature-close.sh` step 3 then prints the advice only when the remaining list is
   non-empty, and otherwise one line: `pinned    N delegate(s) already pinned in the
   manifest`. The stop-on-unpinned rule is unchanged.

### Item 3 — one session, seven manifests, seven times the money

7. The coordinator session that ran all seven features (`ed088063…`, launched in
   `~/dev`, pinned by `feature-start.sh` in each manifest's `sessions`) was priced in
   full by each close — $28.58, $29.93, … — so the seven `report.md`s sum its cost seven
   times and none of them says so. The claims ledger (`analysis/capture_planning.py`
   → `CLAIMS_LEDGER_NAME`, `~/.claude/subagent-claims.json`) already refuses a
   *subagent* claimed by two features; top-level sessions are not in it. Decision: the
   capture records top-level session claims in the same ledger under the same
   `(repo, slug)` key, and a pinned session found already claimed by another
   `(repo, slug)` is **not refused** — a coordinator legitimately spans features — but
   its `planning.json` entry gains `also_claimed_by: ["<repo>/<slug>", …]`, the report
   gains `cost.shared_sessions[]` (`{session_id, cost_usd, also_claimed_by}`), and
   `report.md` prints one footnote under the Cost table naming the session, its dollars
   and the other features counting it. No apportionment: the transcript cannot say which
   feature a message served, and a split by count would be a number nobody measured.
   The seven closed features are not re-captured by this feature; the next sweep or a
   `--recapture` picks the annotation up.
   *(Rework, review escalation 1: the sweep does this by annotating frozen records in
   place — `capture_planning.py --all` refreshes `also_claimed_by` from the ledger
   without opening a transcript or changing a figure. See `NOTES.md`.)*

## Assertion the feature is judged by

The backlog entry's own: an attempt with a null `duration_ms` whose transcript survives
carries a `recovered_duration_s` derived from that transcript's first and last instants,
the Time table renders it as a lower bound visibly distinct from a measured figure, and
an attempt whose transcript is gone still renders as it does today. Plus: a close whose
delegates are all pinned prints no "Pin each" instruction, and a report whose pinned
session is also claimed by another feature says so in `report.json` and `report.md`.

## Tests

`self/tests/` is the suite (`./self/gate.sh` runs it; read `self/PROJECT_FACTS.md` and
`self/tests/README.md` first — fixtures are synthetic corpora under `tmp` dirs, never
`~/.claude`). Acceptance first:

- A `recover-duration.sh` (or an extension of the existing recover test) over a
  synthetic transcript with known first/last timestamps: the sidecar gains the field, a
  one-line transcript does not, `--force` re-derives, a missing transcript is untouched.
- A report test over a corpus with a recovered-duration plan: `report.json`'s
  `time.recovered_duration_plans[]`, the bucket figure, `total_is_partial`, and the
  rendered mark and footnote; and one with the transcript gone, unchanged from today.
- A `--list-subagents --unclaimed --for` test with a pinned delegate: absent from the list.
- A ledger test: two manifests pinning one session; second capture succeeds,
  `also_claimed_by` set, `shared_sessions` rendered.

## Deliberately excluded

- **Apportioning a shared session's cost** (item 3's last sentence).
- **Re-capturing the seven features closed on 2026-09-07.** Their records are frozen by
  their closes; the sweep re-reads them.
- **Any change to what `duration_ms` means when the `result` event exists.** Measured
  figures stay measured.

## Machine-readable

```json
{
  "slug": "recovered-duration-lower-bound",
  "method": "direct",
  "plans": ["88-review-opus"],
  "branches": ["recovered-duration-lower-bound"],
  "base": "main",
  "session_window": {"from": "2026-09-07T15:54:34Z", "to": "2026-09-07T20:03:41Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["ed088063-7aea-498e-84b1-7503d4bd88e1"],
  "subagents": ["ad14001cb4cdc4fed", "a489ebe686a5d08cc"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, `from`, and a pin for the session that ran it — and
`feature-close.sh` stamps `to` when the feature is closed
(`agentTooling/LIFECYCLE.md`). Do not hand-copy it. Only `slug`, `plans` and `branches`
are required: `method` reads as `"plans"` when absent, `base` as `main`,
`session_window` as unbounded, and the four id lists as empty. These are the ones that
go wrong quietly:

- **`method`** — optional, `"plans"` when absent. `"direct"` marks a feature built per
  `agentTooling/AGENT_DIRECT.md` by one implementer delegate; `"hand"` one the
  coordinator built itself, with no delegate to pin and no plans. Under either, the
  transcripts `planning.json` captures are the **build**, and `analysis/report.py` files
  their dollars and minutes there instead of under planning — as `build: implementer`
  and `build: by hand` respectively. Leave it out for a planned feature; a wrong value
  here moves money between buckets without a warning about which was right.
- **`base`** — the branch the feature branched from, `main` unless
  `feature-start.sh --base` said otherwise. `run-review.sh` reads it and exports
  `FEATURE_BASE`, which is the base `plans/pr.sh` opens the PR against, so a feature
  stacked on one that has not merged shows only its own diff. Cost capture ignores it.

- **`branches`** — copy each name from `git branch --show-current`, verbatim. It is
  matched literally against the `gitBranch` in every session transcript, so an added
  owner prefix, or a name retyped from memory, matches nothing and leaves every session
  on it uncounted — the feature then reports `$0.00`, which reads as "planning was free"
  rather than "this manifest is wrong". `analysis/capture_planning.py` warns when a
  declared branch matches no transcript. If a branch was renamed mid-feature, list both
  names: transcripts keep whatever name was current when they were written.
- **`plans`** — every plan stem in the table above, *without* the `.md` extension and
  without its queue/state path, in batch order. `analysis/report.py` prices exactly this
  list: a stem left out is a plan whose cost lands in no report, and an array left out
  entirely drops the whole feature back onto a fallback that can only see plans which
  already ran.
- **`session_window` timezone** — end every bound with `Z`. A bound with no offset is
  read as UTC, and the natural place to find a timestamp is `git log`, which prints
  **local** time — so a value copied from there and pasted bare is silently off by your
  UTC offset, four hours in US Eastern, which is enough to hand a session to the wrong
  feature. Write local time only with its offset spelled out (`2026-07-17T18:00:00-04:00`);
  `analysis/capture_planning.py` warns on any bound that states no zone.
- **`sessions`** — session ids claimed outright, across every project directory,
  regardless of branch, window or `cwd` — the top-level twin of `subagents`.
  `feature-start.sh` pins the session that ran it, which is what claims a planning
  session that began on `main` before the branch existed; widening `branches` to `main`
  instead sweeps in every later session in that checkout. A pinned session that branch
  and window would also select is priced once, and every entry in `planning.json`
  records how it was selected (`selected_by`: `"pinned"` or `"branch"`) and the `cwd` it
  was launched in. A pin that is also in `exclude_sessions` warns, and the pin wins.
  Find an id with `python3 agentTooling/analysis/capture_planning.py --list-sessions
  [--unclaimed] [--since <date>]`, which prints every session launched in this repo's
  primary checkout or one of its feature worktrees with its branch, `cwd`, cost and
  opening prompt.
- **`subagents`** — optional; usually absent. Agent ids of delegates whose *parent*
  session was not on this feature's branch — the coordinator-on-`main` case. A subagent
  inherits its parent's `gitBranch` at spawn and never records its own, so an architect
  spawned from `main` is invisible to `branches` and `session_window` alike; pinning its
  id claims it outright. Find the id with
  `python3 agentTooling/analysis/capture_planning.py --list-subagents --since <date>`,
  which prints each one's cost and opening prompt. A subagent whose parent *is* on the
  branch needs no pin — it is claimed with its parent when its own start is in the window.
  A pin wins over an `exclude_sessions` entry naming its parent: excluding the coordinator
  drops the coordinator's own context cost and keeps the pinned architect. Runner sessions
  are the exception — their usage.json already holds the cost, pins included. A
  delegate's transcript is filed under its *parent's* cwd, so one spawned by a
  coordinator sitting in another repo is found by `--list-subagents --everywhere`
  and pinned here all the same. `--list-subagents --unclaimed` is the standing
  question — every delegate on this machine no feature has claimed, with the
  feature its brief names; a pin already claimed by another feature refuses the
  capture rather than counting twice.
- **`exclude_subagents`** — optional. Delegates of a session this manifest *does* select
  that belong to another feature — a coordinator's manifest (on `main`, windowed around
  the run) lists the architect it spawned, which the arm's own manifest pins. Without it
  the parent route claims the architect here too and the ledger refuses the other
  capture as a double claim.
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
