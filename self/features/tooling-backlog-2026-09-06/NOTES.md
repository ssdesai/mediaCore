# Notes: tooling-backlog-2026-09-06

Rulings the implementer made where the manifest left the call open, each with a one-line
rationale, plus deviations and open questions. The manifest's own decisions
(`README.md` → "The items, with the decision each one is built to") are not reopened
here; only what it did not settle.

## Rulings

### Where each item's assertions live

- **Item 1 gets its own `self/tests/usage-limit-kill.sh`.** The manifest allowed an
  existing scaffold "if one fits better". The nearest is `stream-capture.sh`, whose stub
  already has a `usage-limit` mode — but that file's stub emits 3002 lines to test
  capture *throughput*, and every phase here is a three-line canned stream. Sharing the
  scaffold would have meant either slowing eight new phases down to that stub's pace or
  giving it a second, contradictory mode; a `cat "$CLAUDE_STUB_STREAM"` stub is the
  whole fixture instead.

- **Item 9 gets its own `self/tests/batch-sigpipe.sh`.** `level-sentinel.sh` and
  `tiered-gates.sh` both drive `run-batch.sh`, but each is one contract end to end (the
  sentinel ladder, the tier ladder) with a fixture built for it, and neither has any use
  for a closed consumer. The scaffolding is copied from `level-sentinel.sh` as the
  manifest says; only the file is new.

- **Items 5 and 6 get `self/tests/report-footnotes.sh`, a third new file.** The manifest
  names no home for them. `recover-at-close.sh` is the close's contract and
  `stale-failed-sidecars.sh` is the usage index's; folding "what the two tables say when
  a figure is missing" into either would have made that file's own header a list of
  unrelated subjects — the same call, for the same reason, that
  `tooling-backlog-2026-09` recorded when it put its item 5 in a new `direct-timing.sh`
  rather than in `cost-recovery.sh`. Its scaffolding is copied from
  `stale-failed-sidecars.sh`, which is the report-only sandbox.

- **Item 7's assertions extend `recover-at-close.sh`'s C phase, not
  `feature-lifecycle.sh`.** The manifest allowed either. C10-C12 already close a feature
  and then `--recapture` it with the worktree and local branch gone; C13-C17 are that
  same fixture with one more ref deleted, so the new case costs four lines of setup
  instead of a second close fixture.

### The behaviour the manifest left open

- **The hard-kill signal matches over the whole `error` event, stringified.** The
  manifest says the payload must name 429 or a limit "in the same terms the existing
  matcher accepts". The existing matcher reads `.result // .error // .subtype` off a
  `result` event; an `error` event has no settled field layout, and the platform has put
  the status code in `.error.status`, `.error.message` and `.error.type` at different
  times. Stringifying the event and matching the same regex reads all of them, and the
  three conditions around it (no `result` event, `type == "error"`, and *last*) are what
  keep it from becoming the whole-stream scan the current implementation exists to
  avoid. `self/tests/usage-limit-kill.sh` phases 4, 5 and 7 are the boundary.

- **The limit vocabulary is one named constant, `STREAM_LIMIT_TEXT_RE`.** Two copies of
  that regex would let a limit route two ways depending on which event carried it, which
  is the shape of the defect being fixed rather than a fix for it.

- **`†` marks the cell, and the footnote carries the recovery note too.** The manifest
  fixes the footnote's shape as `† review: unpriced <stem> — <reason>` and says it
  *replaces* the **Unpriced plans** paragraph. That paragraph also carried what recovery
  made of the figure, which is the difference between "re-run `recover_attempts.py`" and
  "the money is gone for good"; the footnote therefore reads
  `† review: unpriced <stem> — <reason>, <recovery>`, the same clause order
  `cost_bucket_cell` already prints in the line `feature-close.sh` shows. Nothing is
  lost in the replacement.

- **The Time table's footnote is `† <bucket>: no duration for <stem> — <reason>`.** The
  manifest specifies the mark and the footnote treatment for the Time table by reference
  to item 5's and gives no text. "unpriced" would be wrong there — the plan may be fully
  priced and merely untimed, which is exactly `report-footnotes.sh` phase 4's fixture.

- **A missing duration gets its own reason vocabulary, not `unpriced_reason`'s.** Both
  facts come from the same `result` event, so the branches are the same three, but the
  words are about the missing figure: `missing_duration_reason` returns `killed`, `no
  result event`, or `no duration reported, cause not recorded`. Reusing
  `unpriced_reason` would have printed "no cost reported" beside a bucket whose dollars
  are right there in the next column.

- **`cost.multi_sidecar_stems[]` carries the LIVE sidecar's queue.** `{plan, queue,
  count}` leaves open which of the twins' queues to report when they differ. The live
  one is the sidecar every other figure in the report is read from, so it is the one a
  reader following the entry will find.

- **A consuming repo's `plans/BACKLOG.md` reports `in-sync`, never `unfilled`.** The
  manifest says `sync-plans.sh` treats it "exactly as it treats `PROJECT_FACTS.md`,
  reported by `--check` the same way": seeded once, never overwritten, `missing` when
  absent. The one part of `PROJECT_FACTS.md`'s treatment that does not carry over is the
  `unfilled` state — an unfilled `PROJECT_FACTS.md` is a defect, while an *empty*
  backlog is the correct steady state for a repo that has closed everything it found.
  Reporting it as an item forever would make `needs attention` a standing complaint and
  train readers to ignore the line. `sync-check.sh` assertion 1h (still `1 item(s)` on a
  fresh seed) is what pins this.

### Made while building

- **`prior_attempt_cost` sums a prior's `attempts[]` rather than reading its top-level
  `total_cost_usd`.** Item 3's dedupe has to be able to remove one attempt from a
  prior's contribution, and the top-level figure IS the sum of that file's attempts —
  there is nothing to subtract from. A prior with no `attempts[]` at all (written before
  the array existed) still falls back to the top level, and has no session id to
  deduplicate on either way, so nothing regresses for the corpus already on disk.

- **`self/tests/template-versions.sh` needed nothing.** The manifest said it "gets
  whatever its table needs". `TEMPLATE_VERSIONS` exists to catch a *body* edit to a
  seeded script that consumers must hand-merge; `BACKLOG.md` is a doc whose seeded copy
  is the repo's own content, with nothing to merge — exactly `PROJECT_FACTS.md`'s
  position, and that is not in the table either. Adding a row would have made every
  future wording change to the skeleton a `DRIFT` line in every consumer for no action
  they could take.

- **No "Adopting …" section in `README.md` for the new stub.** Those sections exist for
  what `sync-plans.sh` *cannot* do — the three repo-owned scripts it must never
  overwrite. `BACKLOG.md` is seeded automatically by the next `update.sh`, so the
  Installing list and `templates/README.md` are the whole of it.

- **The Time table's "**This total is a lower bound**" sentence lost its
  `Missing durations for: …` clause.** The footnotes under the table now name each plan
  beside the bucket whose minutes it is missing from, which is where a reader looking at
  a `0.0` actually is; repeating the list below would be the duplication that replacing
  the **Unpriced plans** paragraph exists to avoid. The sentence still stands on its own
  — a `planning.json` with no `duration_s` makes the total partial with no plan to name.

- **`render_time_section` tolerates the old bare-stem `missing_duration_plans`.** A
  `report.json` written before the shape changed carries strings, and `--all` re-renders
  those. Such an entry names no queue, so it marks no row and falls to the `no queue`
  footnote — the honest rendering of what it knows, rather than a crash.

- Two pre-existing inaccuracies were corrected in passing, both in paragraphs this
  feature already had to edit: `README.md` said `sync-plans.sh` "overwrites the four
  generated stubs" (there are five), and `analysis/README.md`'s `report.json` shape
  listed `unpriced_plans[]` twice, once at the top level where it does not live.

## The resume

The first implementer died at a platform usage limit with slices 1-8 landed and
uncommitted; a second finished slice 9. Two consequences for whoever reads this
feature's own numbers, neither of them a code change:

- **The `gating` stamp is the SECOND implementer's**, appended when it ran the first
  gate. `timing.jsonl` has no stamp between `implementing` (2026-09-06T23:01:05Z) and
  `gating` (2026-09-07T04:18:38Z), so the build sub-row spans the dead implementer's
  work, the gap before the resume, and the second one's verification in one figure.
  Nothing can split it: the checkpoint is rewritten whole and keeps no history, which
  is the property `AGENT_DIRECT.md` → "Checkpoint and resume" warns about. Read the
  build row as an upper bound on the hours and not a measurement.
- **The second implementer's session is not pinned in the manifest.** Pinning it is the
  coordinator's step, not the implementer's (`AGENT_DIRECT.md`: "Pin the second
  implementer's agent id beside the first in the manifest's `subagents`"), and the
  manifest is the spec this build was not to edit. Discovery should reach it anyway —
  both ran on `tooling-backlog-2026-09-06` inside an open `session_window` — but
  `capture_planning.py --list-sessions --unclaimed` before the close is what confirms
  it, and this feature's cost is understated by one implementer if it does not.

Every ticked slice was re-verified against the tree before it was trusted, per the
hint-not-truth rule: each item's assertions re-read against the manifest, and
`--self test-first-levels` rendered under `main`'s `report.py` and this branch's to
confirm a clean corpus's `report.md` is byte-identical (bar the generated-at stamp) and
its `report.json` differs only by the new empty `multi_sidecar_stems`.

## Rework

One escalation from `self/review-report.md` → "Escalated to the next batch": which copy
of a deduplicated attempt the dollars come from. Closed here, to the ruling below;
nobody was listening for questions, so the ruling is the record.

### The ruling

- **A deduplicated attempt contributes whichever copy carries a figure, and a session
  priced by any copy is priced.** Where one `session_id` reaches both the live sidecar's
  `attempts[]` and a prior's, its dollars are taken once, from the first copy that has a
  figure: the live copy's `total_cost_usd`, then its `recovered_cost_usd`, then the
  prior's `total_cost_usd`, then the prior's `recovered_cost_usd`
  (`ATTEMPT_FIGURE_FIELDS`, live before prior). Only a session null in **every** copy is
  unrecoverable — then, exactly as before, `cost.unrecoverable_attempts[]`,
  `cost.unpriced_plans[]` and `total_is_partial`. Where both copies carry a figure and
  disagree the live one wins: it is the file the runner writes to at the plan's current
  path and the file every other figure in the report is read from.
  `analysis/README.md` says so in one sentence beside the dedupe rule.

- **`prior_attempt_cost` merges rather than skips, and its third return value changed
  meaning.** It was "the prior entries not already reachable through the live file",
  which the caller appended to the live `attempts[]`; it is now the whole deduplicated
  list, one entry per session, each the copy that won the precedence. A merge cannot be
  expressed as a skip plus a concatenation — the point is that the prior copy *replaces*
  a figure-less live copy in the list the caller classifies, which is what stops the
  same session being priced from one file and called unrecoverable from the other. The
  caller's `all_attempts = attempts + prior_attempts` is gone; `attempts` is still the
  live list, still the source of `plan_recovered`.

- **A prior attempt carrying BOTH figures now contributes only the first.** Before, a
  prior attempt's `total_cost_usd` and `recovered_cost_usd` were summed together; the
  precedence takes one per copy. The two cannot co-occur — `recover_attempts.py` fills
  the recovered figure only where `total_cost_usd` is null — and no attempt in either
  corpus has both (checked over every `self/features/**/*.usage.json`), so this is the
  precedence stated uniformly rather than a second rule for the shared case.

### Red before the change, and what was not

The brief asked for three assertions and said each must fail first. One of the three
does; the other two cannot, and pretending otherwise would have meant writing a
different assertion than the one the decision names:

- **Phase 11 is red.** Against the pre-rework `analysis/report.py`, `11b`, `11c`, `11d`,
  `11e` and `11g` fail on the plain fixture and `11i`, `11j`, `11k` fail on the priced
  one — eight assertions, all of them on `prior_attempt_cost`'s
  `if session_id in seen_sessions: continue` (`analysis/report.py:682-683` before the
  change), which `continue`s past the prior copy before reading either figure.
- **Phase 12 (both copies null) is green before and after**, because the brief's own
  words for it are "unrecoverable, as today" — an assertion that failed on today's code
  would be asserting a change nobody decided. It is the contrast that keeps 11 honest: a
  merge rule that credited a copy carrying nothing would pass 11 and invent a zero here.
- **Phase 13 (both priced, disagreeing) is green before and after**, because the old
  dedupe already kept the live copy — it kept it unconditionally, which was the defect.
  Its job is to stop a fix that turns the precedence around, and it fails the moment the
  merge prefers the prior.

### A correction to the finding

The escalation says the live null copy "then falls into `unrecoverable_sessions`, adding
the plan to `cost.unpriced_plans[]`, its session to `cost.unrecoverable_attempts[]`".
That is the behaviour only where the live sidecar prices some *other* attempt. Where the
shared attempt is the plan's only one, `compute_cost_rollup`'s earlier
`cost is None and not plan_recovered and not prior_total` test short-circuits first: the
stem is unpriced as a whole plan, named in `cost.unpriced_plans[]` and never classified
attempt by attempt, so `cost.unrecoverable_attempts[]` stays empty. Both paths lose the
same money and both are now asserted — `11a-11g` the whole-plan path, `11h-11k` the
per-attempt path the finding described.

### Bar

`self/tests/stale-failed-sidecars.sh` all green, and every existing feature renders as
before: `self/features/`'s twelve reportable features re-rendered under the pre-rework
`report.py` and this one, in two throwaway trees, give byte-identical `report.md` and
`report.json` apart from `generated_at`. The self corpus has no same-stem twin at all,
so nothing in it could have moved.
