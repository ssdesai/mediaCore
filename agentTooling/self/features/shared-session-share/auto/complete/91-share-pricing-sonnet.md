# 91 — share a multiply-claimed session between its claimants

feature: agentTooling/shared-session-share — plan 3 of 6. A session claimed by more than
one feature is priced and timed by concurrent share instead of counted in full by each.
This plan is the whole of that change in `analysis/capture_planning.py`; plans 89 and 90
are its tests and are RED until it lands.

Depends on: `89-share-arithmetic-tests-sonnet.md`, `90-claim-set-tests-sonnet.md` — they
define the contract. Read `self/tests/session-share.sh`'s expected-split tables before
writing the walk; they are the spec.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- `in_window(moment, window)` takes any dict with `from`/`to` keys holding aware UTC
  datetimes or `None`, and is **half-open** — `from` inclusive, `to` exclusive. The claim
  dicts below are shaped to be passed to it directly.
- `normalize_window(manifest)` turns a manifest's `session_window` into that shape.
- `parse_manifest(readme_path)` reads the last ```json fence of a feature README.
- `repo_identity(dir)` is the origin URL (directory name when there is none);
  `repo_display_name(identity)` its last segment. A corpus directory's repo is
  `repo_identity(features_dir.parents[1])` — `…/agentTooling/self/features` → the
  agentTooling checkout, `…/plans/features` → the enclosing repo.
- `add_usage(totals, key, usage)` folds one response's usage into `totals[key]`; the key
  is whatever the caller groups by.
- `compute_cost(model, tokens, as_of)` returns `(cost, rates_applied)` and `(None, None)`
  for an unknown model — never `(0.0, None)`.
- 58% of real API responses are written as several transcript lines carrying **different**
  timestamps (measured, up to 1.5s apart). Any grouping of lines that de-duplicates
  message ids per group bills a straddling response once per group.
- bash 3.2 is irrelevant here; this file is Python 3, stdlib only, no new imports beyond
  what is already at the top.

## Files

- Modify `analysis/transcript.py`
- Modify `analysis/capture_planning.py`
- Modify `analysis/README.md`

## `analysis/transcript.py`

`iter_billable_messages` must also be able to say **when** each response happened, and the
dedup rule may not be duplicated to get it — this file's own docstring says why. Add
`iter_billable_messages_at(lines)`, move the existing body into it unchanged except that
it yields a 4-tuple `(model, usage, is_sidechain, moment)`, and reduce
`iter_billable_messages` to a wrapper yielding the first three. `moment` is
`to_utc(line.get("timestamp"))` of the **first** line of that response — the line whose
message id was not yet seen — and may be `None` when the line carries no parseable
timestamp.

Its docstring must say why the first line and not any other: one response's content-block
lines carry different timestamps, so an instant-based consumer that took the last line, or
grouped lines before de-duplicating, would bill a response straddling a boundary twice.
`recover_attempts.py` keeps calling `iter_billable_messages` and is not edited.

## `analysis/capture_planning.py`

### 1. The claim shape and where claims come from

A **claim** is `{"feature": "<repo_name>/<slug>", "from": dt|None, "to": dt|None,
"source": "self"|"manifest"|"ledger"}` — shaped so `in_window` takes it directly.

Add `LEDGER_CLAIM_WINDOW_KEY = "window"` beside `LEDGER_SESSIONS_KEY`, with a comment: a
session claim records the window it was claimed with so a capture in another repo can
split the session against it; a claim written before this field exists is read as
unbounded, which reproduces the old "counts the whole transcript" behaviour as an even
split rather than silently dropping the claimant.

Add `session_claim_intervals(session_id, session_start, session_branches, share_ctx,
warnings)` returning the claims list, this feature's first and the rest sorted by
`(from or datetime.min, feature)`. Sources, in precedence order, de-duplicated by
`feature`:

- **self** — always present: this feature, from its own normalized `window`.
- **manifest** — every feature README under any directory in `share_ctx["features_dirs"]`
  other than this capture's own `(features_dir, slug)`, whose fence either pins
  `session_id` in `sessions`, **or** shares a branch with `session_branches` and whose
  normalized window contains `session_start`; and which does not list `session_id` in its
  `exclude_sessions`. The branch route is what makes two features sharing a branch with
  overlapping windows share the money too — the `$37.14` double-count `AGENT_PLANS.md`
  names. Skip a README whose fence will not parse; a broken manifest elsewhere must not
  end this capture.
- **ledger** — every entry in `share_ctx["session_claims"].get(session_id)` whose
  `(repo, slug)` is neither this feature's nor already contributed by a manifest, read
  from its `window` key. This is the only route that reaches a repo neither corpus holds.

When a ledger claim carries no `window`, use `{"from": None, "to": None}` and append a
warning naming the feature and the session: the claim predates recorded windows, so it is
read as covering the whole transcript and the split is even. Warn once per such claim.

### 2. The two pure helpers

Paste these verbatim, above `select_parent`, with the docstrings as written:

```python
def share_owners(moment, intervals):
    """Which claims own one instant. Every claim whose window contains it; failing that,
    the earliest claim alone when the instant precedes every `from`, because a session's
    opening stretch is the planning that led to the first feature it started. `[]` when
    the instant is past every `to` — owned by nobody, and reported rather than dropped."""
    owners = [claim for claim in intervals if in_window(moment, claim)]
    if owners:
        return owners
    dated = [claim for claim in intervals if claim["from"] is not None]
    if dated and moment is not None and moment < min(claim["from"] for claim in dated):
        return [min(dated, key=lambda claim: (claim["from"], claim["feature"]))]
    return []


def partition_seconds(start, end, intervals):
    """Split `[start, end]` among the claims by the rule `share_owners` applies to one
    instant, returning `({feature: seconds}, unclaimed_seconds)`.

    Time is apportioned because the alternative is what the ledger holds today: three
    features that took an evening, eight minutes and an afternoon, each recording one
    coordinator's whole 22.8-hour span as its own duration. The cut points are every
    claim's bounds clamped into the span, so the parts are contiguous and sum to it."""
    if start is None or end is None or end <= start:
        return {}, 0.0
    edges = {start, end}
    for claim in intervals:
        for bound in (claim["from"], claim["to"]):
            if bound is not None and start < bound < end:
                edges.add(bound)
    ordered = sorted(edges)
    per_feature = {}
    unclaimed = 0.0
    for lower, upper in zip(ordered, ordered[1:]):
        seconds = (upper - lower).total_seconds()
        owners = share_owners(lower, intervals)
        if not owners:
            unclaimed += seconds
            continue
        for claim in owners:
            per_feature[claim["feature"]] = (
                per_feature.get(claim["feature"], 0.0) + seconds / len(owners)
            )
    return per_feature, unclaimed
```

### 3. The walk in `select_parent`

`select_parent` gains two arguments, `share_ctx` and `share_detail` (an out-dict keyed by
session id). Everything above the pricing loop — the timestamp collection, the window
membership decision at the `selected = pinned or in_window(...)` line, the boundary
warnings, `matched_session_ids`, `session_start`/`session_end`/`session_branch` — is
**unchanged**. Only the loop that fills `totals` changes.

Build `intervals = session_claim_intervals(...)` once, after selection is decided. Then:

- **One claim** (`len(intervals) <= 1`): bill every response into
  `totals[(session_id, None, model, is_sidechain, ())]` and write no `share_detail` entry.
  This must be byte-identical in effect to today — the ordinary feature's `planning.json`
  does not move. A session nobody else claims has no double-count to remove, and slicing
  it would trade a disclosed over-count for a silent under-count.
- **More than one**: walk `iter_billable_messages_at(lines)` once. Accumulate every
  response into a `session_tokens` bucket keyed `(model, is_sidechain)` — the undivided
  session. Then take `owners = share_owners(moment, intervals)`; with none, accumulate
  into an `unclaimed_tokens` bucket and continue; when this feature's own ref is not among
  them, continue; otherwise `add_usage(totals, (session_id, None, model, is_sidechain,
  refs), usage)` where `refs` is the sorted tuple of owner features.

Record `share_detail[session_id] = {"intervals": intervals, "session_tokens": …,
"unclaimed_tokens": …}`.

`price_subagent` writes into the same `totals`; give its key the same fifth element `()`.

### 4. Serialisation

The `totals` key is now five-wide. Extend the sort key to `(k[0], k[1] or "", k[2], k[3],
k[4])` and unpack `session_id, agent_id, model, is_sidechain, refs`.

A `priced[]` row whose `refs` holds more than one feature carries **this feature's share**
in `cost_usd` — divided, so every existing sum downstream (`cost_usd.main`, `.sidechain`,
`.total`, `report.py`'s roll-up, `frozen_session_costs`) is already right without being
touched — plus three new keys: `full_cost_usd` (the undivided bucket), `share`
(`1/len(refs)`) and `shared_with` (the other features). A row with one or no ref gains
none of them, so an unshared record is unchanged. When `compute_cost` returns `None` the
row is unpriced exactly as today; do not divide `None`.

A `sessions[]` entry for a session with a `share_detail` gains `share_basis` (the claims,
with `from`/`to` as ISO strings or null, and `source`), `session_cost_usd` and
`session_duration_s` (the undivided figures), `unclaimed_usd` (only when non-zero), and a
`duration_s` that is this feature's share from `partition_seconds(session_start,
session_end, intervals)` rather than the whole span. `started_at`/`ended_at` stay the
session's own first and last instants — they are the transcript's bounds, not the share's,
and only `duration_s` is apportioned. Say that in a comment; it is the field pair most
likely to be "fixed" into agreement later.

Price `session_cost_usd` and `unclaimed_usd` with `compute_cost` against the session's own
start date, the same `as_of` the priced rows use. Where a model has no rate, leave the
figure out rather than under-reporting it, and say so in a warning.

### 5. Warnings

- One per shared session: the number of claimants, this feature's share, the session's own
  cost, and the other features. This is the line a human reads at `feature-close.sh` time.
- One when `unclaimed_usd` is non-zero: the dollars and seconds falling outside every
  claim, and that widening a `to` bound or pinning the session to another feature is how
  they get counted.
- The ledger-claim-without-window warning from step 1.

### 6. The ledger records its window

`record_session_claims` and `add_session_claims` each gain a `window` argument and write
`LEDGER_CLAIM_WINDOW_KEY` into every claim they create, as
`{"from": <iso or None>, "to": <iso or None>}` from the **normalized** instants, not the
manifest's raw strings — a bound written `19:00:00-04:00` must reach another repo's
capture as the instant it is. `add_session_claims` still leaves an existing claim entirely
alone, its missing `window` included; refreshing it there would rewrite a frozen figure's
provenance from a record it must not touch.

Update both call sites — `record_session_claims` at the end of `capture_feature`, and
`add_session_claims` inside `register_frozen_claims`, which must read the window from the
feature's own manifest (`normalize_window(parse_manifest(...))`) since it has no scan.

### 7. Moving two reads above the walk

`repo`/`repo_name` and `ledger`/`claims`/`session_claims` are currently computed after the
transcript walk; `share_ctx` needs all of them before it. Move both blocks above the
`for transcript_dir in find_transcript_dirs(sessions_dir):` loop, leaving the comment on
the ledger read amended to say it is read before the walk because the share needs the
other features' claims, and still once. Nothing else about either block changes.

### 8. The frozen-record warning

In `capture_feature`'s already-captured branch, after `annotate_frozen_record` returns a
non-empty list, print a `WARN:` for each annotated session whose entry has no
`share_basis`: the record was frozen before the share rule and counts that session in
full, so `--recapture` would rebuild it — while the transcript survives. The annotate path
still opens no transcript and changes no figure; this only asks.

## `analysis/README.md`

Two edits, both in the `capture_planning.py` entry and the `planning.json` shape entry —
this is `analysis/`'s own README and the change is not done without it.

1. In the `capture_planning.py` entry, replace the paragraph beginning **"A session may
   belong to more than one feature, and the ledger says so."** Keep the ledger's two-arity
   explanation; replace its closing argument — currently "There is no apportionment… the
   honest record is that each feature counts it in full and each says so" — with the rule
   this plan implements: a session with one claimant is priced whole as before; a session
   with more is split by concurrent claim, each response going to every claimant whose
   window covers it and divided equally, the opening stretch to the earliest claimant, the
   tail past every `to` to nobody and reported. Say that the split is exact by
   construction — the claims partition the transcript, so the claimants' shares plus the
   unclaimed remainder equal the session's own cost — and that it is an *estimator* where
   claims overlap, not a measurement: concurrent features genuinely interleave and an even
   split is the least-wrong reading, which is why `share_basis` records every claim the
   split used so the number can be re-derived. Name the measured cases: `3571cc77` at
   $47.18 booked as $188.71 by four features, `ed088063` at $70.50 booked as $563.97 by
   eight across two repos.
2. In the `planning.json` shape entry (`analysis/README.md:742`), add the new fields to
   the inline shape — `sessions[…, share_basis[]?, session_cost_usd?,
   session_duration_s?, unclaimed_usd?]` and `priced[…, share?, full_cost_usd?,
   shared_with[]?]` — and a short paragraph after the `selected_by`/`also_claimed_by` one
   saying what each means, that all of them are absent on a singly-claimed session, and
   that `duration_s` on a shared entry is the share while `started_at`/`ended_at` are the
   transcript's own bounds.
