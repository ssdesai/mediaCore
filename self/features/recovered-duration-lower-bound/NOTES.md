# Notes: recovered-duration-lower-bound

Rulings this build made where the spec left a choice, with the reason each. Written as
they were made (`AGENT_DIRECT.md` step 4). The spec's own decisions are not repeated
here; only what it left open.

## The mark a recovered duration carries

**`‡` (`RECOVERED_FIGURE_MARK`), beside `†` (`MISSING_FIGURE_MARK`), not a second
meaning for `†`.** The spec allowed either. One mark per meaning is the rule the two
marks now state together: `†` means *there is no figure here* — the bucket's minutes are
missing an input entirely — and `‡` means *there is a figure and it is a lower bound* —
a transcript span stood in for a wall clock. A reader who has learned `†` from the Cost
table would otherwise have to read the footnote to find out which of the two a Time
row's `†` meant, and the mark exists precisely so the cell can be quoted without the
footnote.

A bucket can carry both (one plan unrecovered, another recovered), and then prints
`| review | 8.0 † ‡ |` with one footnote line each. `bucket_mark` and
`bucket_footnote_lines` therefore take the mark as an argument rather than closing over
the constant.

## The span itself: the transcript's first and last instants

`recover_attempt` already computes `moments` — every timestamped line of the transcript,
parsed by `transcript.to_utc` — to date the session for its rate tier. The recovered
duration is `max(moments) - min(moments)` over that same list, which is the backlog
entry's and the spec's assertion word for word ("that transcript's first and last
instants"). It is deliberately not restricted to the lines `iter_billable_messages`
yields: a session's last assistant response is not its last instant, and the span is
meant to bound the run, not the billing.

Fewer than two moments writes nothing at all — not `0.0`. A one-line transcript cannot
distinguish "this took no time" from "there is nothing to measure", which is the same
argument the sidecar's null `duration_ms` makes.

## The top-level sum mirrors the dollars, with one difference

`recover_attempts.py` writes the sidecar's top-level `recovered_duration_s` in the same
`if changed:` block, from the same `attempts[]` walk, that keeps the top-level
`recovered_cost_usd` in step — read and mirrored rather than reinvented, as the spec
asks. The one difference: the dollar sum is written unconditionally, while the duration
key is written **only when at least one attempt carries a span**. Summing an empty list
would write `recovered_duration_s: 0.0` onto a sidecar whose every transcript was one
line long, and a top-level `0.0` beside a recovered dollar figure reads as "the run took
no time" — the exact confusion the missing-figure marks exist to prevent.

Like the dollars, it is a convenience sum as of the last recovery run: `report.py` reads
the durable `attempts[]` figures, never this key, because `write_usage_sidecar`'s
fixed-key rebuild drops it on a resumed plan's later write.

An attempt recovered before this feature existed carries `recovered_cost_usd` and no
`recovered_duration_s`, and is skipped by the idempotence check like any other recovered
attempt. `--force` is what backfills it — the same repair path the top-level dollar
figure already documents.

## Which plans the Time table credits

`compute_time_rollup` consults a plan's recovered spans only when
`duration_from_usage()` returns `None` — i.e. when no attempt of the live sidecar
reported a measured `duration_ms` and there is no top-level one either. A plan with one
measured attempt and one null attempt keeps its measured figure and is not credited with
the recovered span of the other: blending a wall clock and a transcript span inside one
cell would produce a figure that is neither, and the plan is already counted. That
attempt-level gap is pre-existing (the Time table has always summed only the attempts
that reported) and is now a `self/BACKLOG.md` entry rather than a silent choice.

`total_is_partial` stays `true` for a recovered plan, per the spec: the span includes the
model's own waiting and excludes whatever the runner did around the call, so the total is
still a lower bound. The Time table's explanatory paragraph, which said "Recovery cannot
fill it — a transcript gives tokens, not the executor's wall clock", is no longer true
and has been rewritten in both `report.py` and `analysis/README.md`.

## The ledger's key for session claims, and how an old ledger loads

The file at `~/.claude/subagent-claims.json` becomes two sections,
`{"subagents": {…}, "sessions": {…}}`:

- **`subagents`** — unchanged: `{<agent-id>: {repo, repo_name, slug, selected_by,
  cost_usd, claimed_at}}`, one claimant, and a second is refused.
- **`sessions`** — `{<session-id>: [{repo, repo_name, slug, selected_by, cost_usd,
  claimed_at}, …]}`, a **list** of claimants. This is the shape difference the decision
  forces: a coordinator legitimately spans features, so a session claimed twice is not a
  conflict, and a single-claimant map could only record the last capture to run.

**An old ledger loads unchanged.** `load_ledger` reads a file carrying neither section
key as the legacy flat map it is and files the whole of it under `subagents`; nothing
migrates on read, and the two-section shape is written on the next capture. The
discriminator is safe because an agent id is a hex-ish token and can never be the
literal string `subagents` or `sessions`.

Every session in `planning.json`'s `sessions[]` is recorded, not only the pinned ones.
The spec's wording is about the case that occurred (a pinned coordinator), but two
features sharing a branch can double-count a branch-selected session just as quietly,
and "the sessions this feature counts" is the honest set to record. `also_claimed_by`
is set on any session entry the ledger records for a different `(repo, slug)`, in
`<repo_name>/<slug>` form — the same form a brief's `feature:` line uses.

A shared session's dollars in `cost.shared_sessions[]` are its **own** priced entries
(`priced[]` rows carrying that `session_id` and no `agent_id`), not its delegates':
a subagent is claimed by exactly one feature, refused otherwise, so rolling its cost
into the shared figure would report money that is not in fact double-counted.

## Keeping the tests off `~/.claude`

**No new environment variable. `$HOME` is the override, and it already exists.**
`claims_ledger_path()` derives from `Path.home()`, which follows `$HOME` on every
platform these scripts run on, and every test in the suite that touches the ledger or a
transcript already redirects `$HOME` to a `mktemp -d` (`recover-at-close.sh:111`,
`capture-guard.sh:120`, `subagent-capture.sh:86`, `feature-lifecycle.sh:123`). A
ledger-only variable would be a second, narrower seam: a test could then redirect the
ledger and still write the real `~/.claude/projects`, which is the failure the rule
exists to prevent. The two must move together, and `$HOME` is what moves them.
`analysis/README.md` says so in the ledger's entry.

## Deliberately not built

- **Apportioning a shared session's cost** — the spec excludes it.
- **Re-capturing the seven features closed on 2026-09-07** — the spec excludes it, and
  it is still not done here. *(Superseded in part by the rework below: an ordinary sweep
  now DOES pick the annotation up, by annotating the frozen record in place rather than
  re-capturing it. The paragraph this replaced said the sweep could not, which was true
  of the build and is what review escalation 1 was raised on.)*
- **A recovered duration for a plan whose other attempt is measured** — see above; a new
  `self/BACKLOG.md` entry.
- **A recovered-seconds clause in `recover_attempts.py`'s summary line.** The line
  reports dollars; the durations are visible in the sidecar and in the report. Adding a
  clause would change a string three existing tests match on for no assertion's sake.

## Rework (review escalations 1–2)

A second one-shot, after the independent review passed the build with fixes and escalated
two items that needed code. Scope was exactly those two: escalation 3 stays a
`self/BACKLOG.md` entry and escalation 4 is recorded in the PR body. `self/BACKLOG.md`
and `self/review-report.md` are untouched, no `--recapture` was run on any real feature,
and nothing under `templates/` changed — the annotate path needed no template change,
because it lives entirely in `analysis/capture_planning.py`, which is not a template.

### Escalation 1 — an annotate-only path for frozen records

`capture_feature` returned `"skipped"` before the transcript scan for any `planning.json`
carrying a `captured_at`, so `sweep.sh`'s `capture_planning.py --all` could never put
`also_claimed_by` on a feature that was closed before a second feature claimed its
session — which is every one of the seven closed on 2026-09-07, the case item 3 exists
for. The review's option (b), taken:

- **`annotate_frozen_record`** refreshes `sessions[].also_claimed_by` from the claims
  ledger and writes `planning.json` only when that one key changed. It opens no
  transcript. Every dollar, duration, `captured_at`, `rates_source`, warning, session and
  subagent entry is byte-identical before and after — asserted in the test over the whole
  record with `also_claimed_by` stripped, rather than over a list of fields someone has to
  remember to extend.
- **`cost.shared_sessions[]` needed no second write.** It is a `report.json` field, not a
  `planning.json` one: `report.py`'s `compute_shared_sessions` derives it from exactly
  these entries. Refreshing `also_claimed_by` is therefore the whole of what puts the
  array and the Cost-table footnote in the next report, and the existing footnote code
  reads it unchanged — verified by C6, which renders the report for the feature that was
  frozen first.

**Ruling — the return value.** `capture_feature` returns a new `"annotated"` when it
wrote and keeps `"skipped"` when nothing changed, and prints a line saying which. Two
outcomes rather than one because they mean different things to a reader of a sweep log:
`skipped` means this record is as it was, `annotated` means a file under `features/` is
now dirty and wants committing. `main` counts it separately (`… , N annotated` in the
`--all` summary, printed only when non-zero) and it is **not** an error — the exit code
still comes from `refused`/`conflict`/`unreadable` alone. `sweep.sh` needed no change at
all: it derives its report slugs from `git status --porcelain` over the features
directory, so an annotated `planning.json` is picked up and its report regenerated by the
step that already exists.

**Ruling — register first, then annotate.** The ledger is the only seam between features,
and `capture_feature` handles one feature at a time, so registering and annotating in the
same step would leave the first of N frozen features sharing a coordinator naming none of
the others and the last naming all of them — an artefact of walk order, not a fact about
the corpus. `main` therefore runs `register_frozen_claims` over the run's whole slug list
*before* the capture loop, whenever `--recapture` is absent. It reads each frozen
`planning.json` (never a manifest, except for the same in-flight test `--all` applies, and
never a transcript), derives each session's own dollars from `priced[]` rows with no
`agent_id` — the same arithmetic the capture does — and adds a claim only where the ledger
holds none for that `(repo, slug)`. Add-if-missing rather than
`record_session_claims`'s wholesale replace: this path has not re-derived anything, so an
existing claim keeps its own `claimed_at` and dollars, and a second sweep over an
unchanged corpus writes neither the ledger nor a `planning.json`. It runs under the
per-feature form too (`--self <slug>` with no `--recapture`), where the slug list is one
long.

**Ruling — cross-repo convergence takes a second sweep, and cannot take fewer.** Within
one repo's run the pre-pass makes all N converge at once. Across repos there is no
ordering to fix: each repo sweeps its own corpus and writes the one shared ledger, so a
record can only name the claimants whose repos have already registered. Sweep every repo
once and the ledger is complete; the second pass over each is the one whose annotations
are final. A repo swept once and never again keeps a partial list — a stale annotation,
never a wrong figure. `analysis/README.md` says this plainly beside the cadence, in the
ledger's entry, and in the `planning.json` field list.

### Escalation 2 — `manifest_pinned_subagents` prefers the corpus that owns the slug

**Ruling — prefer, do not switch to the pair.** The docstring's argument stands and is
kept: the `(repo, slug)` pair is never compared, because under a vendored subtree a
`--self` feature's brief says `agentTooling/<slug>` while the checkout's own identity is
the enclosing repo. What changed is which tree is read first. The function takes a
`preferred_dir` — `features_root(args.self_mode)`, i.e. `self/features` under `--self` and
`plans/features` otherwise — and when that tree holds a manifest for the slug it is the
only one read; when it does not, the lookup falls back to the slug alone across both
corpora, unchanged. `feature-close.sh` already passes `--self` through to this call, so
its stop-on-unpinned guard gets the right corpus with no change to that script.

### Files changed

`analysis/capture_planning.py` (the annotate path, the pre-pass, the corpus preference,
the module docstring), `analysis/README.md` (the sweep cadence, the ledger entry, the
skip's entry, the pin-is-the-claim entry, the `planning.json` field list),
`self/tests/claims-ledger.sh` (groups C and D), `self/tests/README.md` (its entry), and
one line under item 3 of this feature's `README.md` prose. The fence is untouched.

### Tests

`self/tests/claims-ledger.sh` gains eleven assertions. **C** builds two features that
each pin one coordinator and are each captured with the ledger holding no claim on it —
the shape the seven closes left behind — then deletes that session's transcript and runs
one plain `--all`: C1/C2 each names the other in the same run, C3 asserts nothing else in
either record moved, C4 that the run reports them `annotated`, C5 that the transcript was
gone throughout, C6 that `report.py` then renders `cost.shared_sessions[]` and the
footnote, C7 that a second `--all` writes nothing and says `skipping`. **D** puts a
`plans/features/dup` that pins a delegate beside a `self/features/dup` that does not:
under `--self` the delegate is still unclaimed, without `--self` it is not, and a slug the
queried corpus does not hold falls back to both. C1, C2, C4, C6 and D1 were confirmed RED
against `HEAD`'s `analysis/` before the fix; C0, C3, C5, C7, D2 and D3 pass either way and
pin the shape rather than the existence.

### Gate

`./self/gate.sh` — **all checks passed**, 63 checks, 0 FAILED, 0 SKIPPED, 0
informational failures (`self/gate-report.txt`). Same count as the build's: no test
script was added, so `self/gate.sh` needed no new `record` line.
