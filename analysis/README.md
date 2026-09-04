# analysis

This folder holds the `plan-analytics` feature's tooling — stdlib-only Python 3 scripts (no pip installs, no venv) that price and report what a feature cost to plan and build, plus the JSON artifacts they read and write under `plans/`. Scripts are run directly (`python3 agentTooling/analysis/<name>.py`), not installed as a package.

## Where to run them

**Run the copy vendored into the repo you want to analyze**, i.e. `<that-repo>/agentTooling/analysis/<name>.py`. Which copy you invoke still selects the repo, and `cwd` is still irrelevant — every root the scripts use derives from the script's **own location on disk**, via `roots.py`, never from `cwd` and never from an argument.

Without `--self`, the artifact root is the consuming repo (`roots.AGENT_TOOLING_DIR.parent`, i.e. `parents[2]` from a script's own file) and the feature tree is `plans/features/`. With `--self`, both are the agentTooling checkout itself: the artifact root is `roots.AGENT_TOOLING_DIR` (`parents[1]`) and the feature tree is `self/features/` — the corpus for features whose diff is entirely inside agentTooling.

**Two roots, not one.** `capture_planning.py` alone also reads `~/.claude/projects/`, whose directory names encode the `cwd` a session actually ran from. Under `--self` that is the enclosing repo, not `agentTooling/` — a `--self` executor's cwd is the agentTooling directory (see `agentTooling/CLAUDE.md`), but interactive planning sessions ran from the repo root above it. So the session root is resolved separately, as the nearest ancestor holding `.git`. Concretely: a `--self` capture in a subtree checkout reads `~/.claude/projects/-Users-…-vinylCatalogue/` (the session root) but writes `agentTooling/self/features/<slug>/planning.json` (the artifact root) — two different directories, both correct for what they're used for.

A standalone `agentTooling` clone works too, with both roots landing on the clone itself — that is why the session-root rule is "nearest ancestor holding `.git`" rather than "the parent directory": one rule covers both a vendored subtree and a standalone checkout.

**A feature worktree's copy is the wrong copy for an ordinary capture.** A worktree holds a `.git` of its own (a file rather than a directory, which is why the rule tests `.exists()`), so both roots resolve to the worktree: a capture invoked from `R-<slug>` scans transcripts under `R-<slug>` and the worktree it would derive from *that*, `R-<slug>-<slug>`, and writes its `planning.json` into the worktree's own tree. The primary checkout's sessions are outside both. Run `R`'s copy, which reaches the primary and the feature worktree `R-<slug>` alike (`../LIFECYCLE.md`); the worktree path is derived from the slug rather than looked up, so it stays matchable after `feature-close.sh` removes the worktree. `feature-start.sh` and `feature-close.sh` refuse to run from a worktree for the same reason.

The scripts never take a repo path, so there is no way to point one repo's checkout at another repo's plans. That is deliberate: the subtree is shared across repos, and a `--repo` flag would make it possible to write one repo's costs into another's `plans/` tree. `--self` does not weaken this — it selects between two fixed roots derived from the script's own location, not an arbitrary path.

## Every instant is UTC

One convention, because cost depends on it: **every timestamp is normalized to UTC before it is compared, sorted, or turned into a date.** `transcript.to_utc` does the parsing and `transcript.utc_date` the dating; nothing here slices `timestamp[:10]` or compares two ISO strings with `<`.

- **Transcripts** are written UTC with a `Z`. That is what makes string handling *look* correct — it is right only while every string is the same shape, and nothing enforced that.
- **`session_window` bounds** are typed by a human, usually read off `git log`, which prints **local** time. **End every bound with `Z`.** One with no offset is interpreted as UTC — what every bound in the committed corpora already means — so a local time pasted bare silently shifts the window by your UTC offset, 4–5 hours in US Eastern, which is more than the gap between consecutive features. Write local only with the offset spelled out (`2026-07-17T18:00:00-04:00`); it is converted. `capture_planning.check_naive_bounds` warns on any bound that declares no zone, because the string cannot describe itself and nothing else can catch it.
- **The pricing date** (`as_of`) is the UTC date of a session's earliest instant, and it selects the rate tier. An offset timestamp late in the day belongs to the *next* UTC day, so dating it locally can price a session on the wrong side of an intro-rate boundary — a dollar error, not a display one.
- **Wall-clock "today"** is `pricing.utc_today()`, never `date.today()`, so the one date that does not come from a transcript is UTC like the rest.

Asserted by `self/tests/timestamps-are-utc.sh`.

## How to run them

**One feature is closed by `../feature-close.sh <slug>`, not by hand** (`../LIFECYCLE.md`
→ step 6). It runs step 4 below for that slug in the order that makes it safe — the
unclaimed-delegate check, then `capture_planning.py`, then `report.py`, and only then
`session_window.to` — and shows what was claimed before the number is quoted. What
follows is the weekly **sweep behind it**, over the whole corpus: it catches the feature
whose delegate was pinned after it closed, the batch whose `.stream.jsonl` was never
converted, and the killed attempt nobody recovered — each of which reads as a correct
number until someone looks.

Weekly, `../sweep.sh [--self]` runs the cadence in this order, then lists the unclaimed delegates and sessions. The order is a real dependency chain, not a suggestion — `report.py` reads the `planning.json` and `usage.json` files the two capture steps write, and reports nothing where they are missing rather than failing loudly.

**1. Check the rate table first.** Costs are tokens × table; there is no cost field in a transcript to fall back on. A stale table silently skews every figure it touches.

```bash
python3 -c "import sys; sys.path.insert(0,'agentTooling/analysis'); import pricing; print(pricing.RATES_VERIFIED, pricing.is_rates_stale())"
```

`True` means `RATES_VERIFIED` is more than `STALENESS_THRESHOLD_DAYS` old. Re-check published rates, update `RATES` and bump `RATES_VERIFIED` in `pricing.py`, then continue. `capture_planning.py` and `report.py` also surface this in their `warnings[]` — they warn, never fail, so an unread warning becomes a wrong number.

**Unconfirmed: `claude-sonnet-5`'s `intro.starts`** — the `2026-08-22` start date in `RATES` was inferred from observed billing ratios across this repo's own corpus (every sonnet day from 2026-07-30 to 2026-08-21 billed 1.5x what the intro rate computes, 2026-08-22 billed 1.0x), not read off a published price list. `RATES_VERIFIED` was bumped with it, so `is_rates_stale()` will not flag it — confirm the date against Anthropic's published rates at the next re-check.

**Owed work: planning.json price correction** — every `planning.json` frozen before 2026-08-22 was priced with the intro tier applied retroactively and is therefore roughly 33% low. Correcting them means a full refresh (`capture_planning.py --all --recapture`) and committing the diff — and it is now only possible for features whose transcripts still exist, which is the whole argument for doing it promptly. This batch has not done so; see the feature manifest.

**2. Backfill usage sidecars** for any batch that ran before the runner captured usage itself. Idempotent, so it is safe (and cheap) to run every time:

```bash
python3 agentTooling/analysis/backfill_usage.py
```

**3. Recover killed-attempt costs** from session transcripts. Idempotent: an attempt that already carries `recovered_cost_usd` is skipped unless `--force`:

```bash
python3 agentTooling/analysis/recover_attempts.py
```

**4. Capture planning cost, then report.** `capture_planning.py --all` walks the corpus and captures the features that have no `planning.json` yet, **skipping the ones that already do**. It also skips any feature whose `session_window.to` is still `null` — in flight, its first capture is `feature-close.sh`'s, and a record frozen here would make that close skip and report a premature figure. That skip is what makes this step ordinary cadence work rather than something to be careful with: a frozen record is not rebuilt unless you ask for it, so the run cannot rewrite a figure it can no longer reproduce, and it costs almost nothing (a skipped feature is never scanned). The sweep reports each feature whose cost files changed, then `--all` for a cross-feature trend.

`report.py` reads only what is already on disk, so re-run it for whatever changed — it is the capture step that has to be careful, not this one.

**A full refresh is `--all --recapture`, and it is not cadence work.** It re-derives every `planning.json` from transcripts, so reach for it with a reason — a pricing correction, a manifest fix — and read the diff before committing. On a corpus older than transcript retention it does two different things: where a *priced* session is gone, `check_frozen_cost` refuses that feature, leaves it untouched, and the run carries on (exiting non-zero at the end) — `--carry-lost` instead keeps those entries verbatim (each marked `carried_from`, the file gaining a top-level `carried_from`) and adds what the scan reaches, which is how a subagent pin is added to a feature whose own sessions have expired; where only a *runner* session is gone, the feature re-captures **successfully** with fewer `excluded_session_ids` than before, which is a silent metadata loss no guard catches. Both are reasons the default is to skip.

Each command takes `--self` in the same position to operate on agentTooling's own corpus instead:

```bash
python3 agentTooling/analysis/backfill_usage.py --self
python3 agentTooling/analysis/recover_attempts.py --self
python3 agentTooling/analysis/capture_planning.py --self --all
python3 agentTooling/analysis/report.py --self <slug>
```

### Why the cadence matters

Both capture steps read sources that expire, which is what makes this a recurring job rather than something to run once when you happen to want a number:

- `.stream.jsonl` is gitignored and lives only on the machine that ran the batch. It is the sole cost record for any plan predating runner-side usage capture, and `backfill_usage.py` is what converts it into a committed `usage.json` before it is lost.
- Session transcripts under `~/.claude/projects/` are on a retention clock. `capture_planning.py` freezes each session's cost into `planning.json` as dollars; once a transcript ages out, an uncaptured feature's planning cost is unrecoverable. Similarly, a killed attempt's cost is recoverable from its session transcript by `recover_attempts.py` only while that transcript survives — once aged out, the cost is unrecoverable.

Both write into `plans/` — commit the results, or the next run has nothing to build a trend from.

## Scripts

- `roots.py` — root resolution shared by the other scripts below (`transcript.py`
  imports neither `roots` nor any of them — it is pure transcript parsing). Exposes
  `AGENT_TOOLING_DIR`, `add_self_flag(parser)`, `artifact_root(self_mode)`,
  `features_root(self_mode)`, `all_features_roots()`, `session_root(self_mode)`. Every
  script resolves its roots through this module rather than computing `parents[N]`
  itself, so the ordinary and `--self` modes cannot drift apart.
  `all_features_roots()` returns **both** corpora and is read-only — it exists because
  the two trees share one branch namespace, so anything scanning for "every session a
  runner spawned" must span both. Everything that *writes* uses
  `features_root(self_mode)`.
- `pricing.py` — rate table and cost calculator. Exposes `utc_today()` (today's UTC date — the wall-clock source for everything here, since `date.today()` is the machine's *local* date and would disagree with every transcript-derived date for part of each day), `RATES_VERIFIED` (date the table was last checked), `STALENESS_THRESHOLD_DAYS`, `RATES` (per-model USD/Mtok `{input, output}`, optional `intro{input, output, starts, expires}`), `CACHE_READ_MULTIPLIER` / `CACHE_WRITE_5M_MULTIPLIER` / `CACHE_WRITE_1H_MULTIPLIER`, `normalize_model_id(model_id)`, `get_rates(model_id, as_of) -> RatesApplied | None`, `compute_cost(model_id, tokens, as_of) -> (cost_usd | None, rates_applied | None)`, `is_rates_stale(today=None) -> bool`. Any script that prices tokens imports `compute_cost` / `get_rates` / `is_rates_stale` from here rather than hardcoding rates — the table lives in exactly one place.
- `transcript.py` — session-transcript parsing shared by `capture_planning.py` and
  `recover_attempts.py`. Exposes `to_utc(timestamp) -> aware datetime | None`,
  `utc_date(timestamp) -> "YYYY-MM-DD" | None`, `SYNTHETIC_MODEL`,
  `iter_billable_messages(lines) ->
  yields (model, usage, is_sidechain)`, `add_usage(totals, key, usage)`.
  `iter_billable_messages` bills each API response exactly once — a response is written
  to a transcript as several `assistant` lines, one per content block, each repeating
  that response's `usage` verbatim, so it dedups on `message.id` (summing per line
  measured 2.4x–2.8x over) and skips `model: "<synthetic>"` lines (locally-generated
  notices with all-zero usage). `add_usage` folds one message's `usage` into a
  five-key token bucket (`input`, `output`, `cache_read`, `cache_creation_5m`,
  `cache_creation_1h`) — the shape `pricing.compute_cost` consumes, and the only place
  the 5m/1h cache-creation split survives; `usage.json`'s own `usage{}` block flattens
  it into one total (see "Do not re-price build or verify cost" below).
  `to_utc` is the single parse point for the UTC convention above: it normalizes `Z` to
  `+00:00` (`datetime.fromisoformat` rejects `Z` before Python 3.11, and these scripts
  are stdlib-only on whatever interpreter a consuming repo has) and treats an
  offset-less value as UTC rather than local, which is what the committed
  `session_window` bounds already mean. `utc_date` is what replaced `timestamp[:10]`
  everywhere; the slice read the date in whatever zone the string carried, so an
  evening offset timestamp was dated a day early and could price against the wrong
  rate tier.
- `recover_attempts.py` — recovers a killed attempt's cost from its own session
  transcript. Walks every `usage.json` under `roots.features_root(self_mode)`; for each
  `attempts[]` entry with `total_cost_usd: null` and a `session_id`, sums that session's
  tokens with `transcript.iter_billable_messages` + `add_usage`, prices them with
  `pricing.compute_cost` using the session's own earliest timestamp, and writes
  `recovered_cost_usd`, `recovered_tokens` (the five-key shape, per model),
  `recovered_from: "transcript"`, `recovered_at`, `rates_applied` onto the attempt —
  never onto `total_cost_usd`, which must stay distinguishable as the CLI's own figure.
  A model the transcript names but `pricing.RATES` has no rate for is excluded from
  `recovered_cost_usd` rather than coerced to 0 (the rule `pricing.py` states): that
  attempt also gets `unpriced_models[]` naming the excluded ids and
  `recovered_is_partial: true` — its `rates_applied` entry for those models is `null` —
  and the run prints them under a `partial (unpriced models excluded from
  recovered_cost_usd):` heading.
  Also sets the sidecar's top-level `recovered_cost_usd` to the sum over its recovered
  attempts, but only on a run that recovered something: a re-run that skips every
  already-recovered attempt rewrites nothing, so `--force` is what repairs a top-level
  figure that has drifted from `attempts[]`. A killed attempt whose transcript has aged
  out is left untouched, counted, and printed under an `unrecoverable:` heading; the run
  still exits 0. Idempotent, like
  `backfill_usage.py`: an attempt that already carries `recovered_cost_usd` is skipped
  unless `--force`. Usage: `python3 agentTooling/analysis/recover_attempts.py [--self]
  [--force]`.
  Depends on two things not visible from its imports: it locates a transcript by
  globbing `~/.claude/projects/*/<session_id>.jsonl` directly, never via
  `roots.session_root` — session ids are unique, and a `--self` executor's cwd
  (`agentTooling/`) differs from a host-repo executor's (the repo root), so the two
  land in different `~/.claude/projects/` directories, and a glob is correct for both;
  and it depends on the runner writing `session_id` into every `attempts[]` entry,
  including a killed one, in `write_usage_sidecar` (`plan-runner-lib.sh`) — that field
  is the one thing a killed run still yields.
- `backfill_usage.py` — one-shot extraction of `<plan>.usage.json` sidecars from
  `.stream.jsonl` files already on disk, for batches that ran before the runner
  captured usage directly (plan 52). Idempotent: skips a plan that already has a
  `usage.json` unless `--force` is passed. Run once, promptly — `.stream.jsonl` is
  gitignored and is the only surviving cost record for pre-existing batches. Output
  is field-for-field identical in shape to the runner's own `usage.json` (see
  `AGENT_PLANS.md` / the runner's `finalize_plan`) so downstream tooling never needs
  to distinguish the two.
- `capture_planning.py` — mines `~/.claude/projects/` session transcripts for a
  feature's branches, excludes runner-spawned sessions (any id already in a
  `usage.json`) and `exclude_sessions`, sums tokens per `(session, model,
  is_sidechain)`, prices each with `pricing.compute_cost` using that session's own
  date, and freezes the result as dollars into `<features root>/<slug>/planning.json`.
  Cost is computed once here; nothing downstream recomputes it. Usage:
  `python3 agentTooling/analysis/capture_planning.py <slug>`,
  `… --all [--recapture]`, `… --list-subagents [--since YYYY-MM-DD]`,
  `… --list-subagents --unclaimed [--for <repo>/<slug>]`, or
  `… --list-sessions [--unclaimed] [--since YYYY-MM-DD]`.
  **Sessions are pinned the way subagents are.** A manifest's
  `"sessions": ["<session-id>"]` claims a top-level session outright — across every
  project directory, regardless of branch, window or `cwd`. That is how a planning
  session which began on `main` before the feature branch existed is claimed without
  widening `branches` to `main`, which would sweep in every later session in that
  checkout; `feature-start.sh` pins the session that ran it, so the ordinary case needs
  no hand edit (`../LIFECYCLE.md`). A pinned session that branch and window would also
  select is priced once, every `sessions[]` entry records `selected_by`
  (`"pinned"`/`"branch"`) and the `cwd` it was launched in, and a pin also listed in
  `exclude_sessions` warns and wins. `--list-sessions` is the discovery step: every
  top-level session launched in the primary checkout or one of its sibling worktrees,
  with date, id, branch, `cwd`, model, cost, minutes and opening prompt. `--unclaimed`
  keeps the ones no manifest pins, no `planning.json` in either corpus lists as selected
  or excluded, and no `usage.json` already holds as runner cost — sessions that belong to
  somebody and are counted by nobody, which is the pin still to write and what
  `feature-close.sh` prints before it captures.
  **Time is frozen beside cost.** Every session and subagent entry carries
  `started_at`/`ended_at`/`duration_s` (the transcript's first and last instants), every
  `priced[]` entry the `duration_s` of what it prices, and `duration_s{sessions,
  subagents}` sums them at the top — two figures, never one, because a delegate's span
  is its working time while a session's includes every idle minute and, for a
  coordinator, every minute spent waiting on a batch. `report.py`'s Time table keeps
  the rows apart for that reason. A `planning.json` captured before this existed has no
  `duration_s`; re-capture it while the transcripts survive. `--list-subagents` shows
  each delegate's minutes beside its cost.
  **Subagent transcripts are priced too.** A session that spawned delegates keeps their
  transcripts beside its own, at `<session-id>/subagents/agent-<id>.jsonl`; before this
  scan read them, an opus architect's whole cost was invisible — $184 across one
  four-repo program, next to a $206 coordinator that was on `main` and therefore also
  unmatched. A subagent inherits its parent's `gitBranch` and `cwd` at spawn and never
  records its own, so it cannot be selected by branch. Two routes in: a subagent whose
  **parent is selected** is priced when its own start is inside the `session_window`;
  and a manifest's `"subagents": ["<agent-id>"]` **pins** one on its id alone,
  bypassing branch and window — the coordinator-on-`main` case, where the pin is the
  human's word. A pin also outranks an `exclude_sessions` entry on its parent, so a
  feature can drop the coordinator's context cost and keep its architect; only
  runner-spawned sessions (already priced by a usage.json) refuse pins. A pin is also
  honoured across repos: the transcript is filed under the *parent's* cwd, so an
  architect a coordinator in repo A spawned to work on repo B sits under A's project
  directory — B's manifest pins it by id and it is priced from there (`cross_repo:
  true`); `--list-subagents --everywhere` is how B finds it.
  **The claims ledger enforces the pins.** Every subagent this tool prices is recorded
  in `~/.claude/subagent-claims.json` — `{ <agent-id>: { repo, repo_name, slug,
  selected_by, cost_usd, claimed_at } }`, `repo` being the origin URL so worktrees and
  clones agree and `repo_name` its last segment (what a brief's `feature:` line says) — beside the transcripts and scoped like them. A capture whose subagent
  is already claimed by a *different* feature (in any repo) is refused outright, since
  neither manifest can see the other and two features cannot own one transcript's
  cost; re-capturing a feature replaces its own entries, so a dropped pin becomes
  unclaimed again. `--list-subagents --unclaimed` lists every transcript on this
  machine no feature has claimed, with the feature its brief names (the
  `feature: <repo>/<slug>` first line `ORCHESTRATION.md` requires) as the pin to
  write; adding `--for <repo>/<slug>` keeps only the rows whose brief names exactly that
  feature, compared as the `(repo, slug)` pair rather than as text in the printed table —
  a `<slug>-two` delegate is somebody else's and a name too long for the 26-character pin
  column is still matched — which is what `feature-close.sh`'s stray-delegate guard reads,
  and it is a usage error without `--unclaimed`. `--all` ends by counting the unclaimed
  under this repo's directories. A pin
  whose brief names another feature is warned about — the pin is the human's word,
  the brief the coordinator's, and one is wrong. `exclude_subagents` is the pin's
  inverse — a selected session's children that another feature pins, so a
  coordinator's manifest and its arm's manifest do not both claim the architect
  (recorded in `excluded_agent_ids`). Dropping a cross-repo pin does not
  trip `check_frozen_cost`: the transcript is proved still on disk before the guard
  looks, so "unpinned" is not read as "expired".
  `--list-subagents` is the discovery step: every reachable subagent with
  its date, id, parent, branch, model, priced cost and opening prompt, so the plan
  author can be told from the reconnaissance one-shot. An **empty** narrow scan says
  which root it scanned and names `--everywhere`, because "no subagent transcripts
  found" has two causes that look identical from the output — there genuinely are none,
  or the copy of the script that was invoked resolves a session root the transcripts are
  not under (see "Where to run them"). The `--everywhere` and `--unclaimed` scans keep
  the bare message: they already looked everywhere. Pinned cost lands in
  `subagents[]` (`agent_id`, `parent_session_id`, `date`, `selected_by: parent|pinned`,
  `cross_repo`),
  in `priced[]` under its `agent_id`, and in `cost_usd.subagents` — a subset of
  `cost_usd.sidechain`, reported apart because it is the figure the delegation-tier
  comparison needs. A subagent of a runner session is never priced here (its parent is
  excluded, and the sidecar's `total_cost_usd` already includes it) — a pin on one is
  reported unmatched. `check_unmatched_subagents` and `check_subagent_overlap` are the
  pin's versions of the branch checks: a pinned id no transcript carries, and an id two
  manifests both pin. `check_frozen_cost` covers subagents the same way it covers
  sessions, reporting a lost one as `agent-<id>`.
  **Populates only what is not yet populated.** `prior_capture` reads the existing
  `planning.json`'s own `captured_at` — not its mtime, which a checkout or a rebase
  resets on every committed file at once — and a feature that has one is skipped:
  exit 0, file untouched, one line naming when it was captured, **what total is already
  recorded**, and that `--recapture` rebuilds it. `--force` implies `--recapture`, since
  it is the stronger ask of the two and must not be swallowed by the guard in front of
  the one it overrides.
  The total is on that line because a frozen `$0.00` is the one prior capture worth
  revisiting — the last run found nothing, which a corrected `branches` entry or a run
  from the right checkout may now find — and a skip is the one path where nothing else
  says so: `check_unmatched_branches`, the warning that usually explains a zero, has no
  scan to speak from. Nothing retries a captured feature on its own.
  This sits *before* the transcript scan, so `--all` over a mostly-frozen corpus is
  near-instant, and it protects a strictly wider surface than `check_frozen_cost` below:
  that guard asks only whether a re-capture would drop a *priced* session, while a
  re-capture that drops none still rewrites `captured_at`, `rates_source` and
  `excluded_session_ids` — and that last one shrinks as runner transcripts age out, so an
  unasked-for re-run quietly forgets which sessions were runner cost. Observed, twice, on
  this repo's corpus.
  On a skip the two manifest checks (`check_naive_bounds`, `check_branch_overlap`) still
  run and still print, since they read READMEs rather than transcripts and a missing `to`
  bound stays worth hearing about after the cost is frozen.
  `check_unmatched_branches` cannot run there — its evidence is the scan that did not
  happen.
  `--all` walks `feature_slugs(features_root(self_mode))` — every directory holding a
  `README.md`, the same set `check_branch_overlap` scans — one full capture per feature,
  not a shared walk. It never aborts partway: a refusal, or a manifest that will not
  parse, is counted, printed, and the walk continues, with the exit code set from the
  counts at the end. One expired feature must not cost you the run.
  Excludes a runner session by finding its id in some `usage.json` — reading
  `attempts[]`, not only the top-level `session_id`, since that field names only a
  resumed plan's last invocation. Anything the sidecars do not account for is priced
  here, so a runner session the runner failed to record does not go missing, it
  reappears as planning cost.
  `check_unmatched_branches` warns for each declared branch that no transcript in this
  repo carries. A name that matches nothing — a typo, or an owner prefix the branch
  never had — leaves every session on it uncounted and the feature reporting `$0.00`,
  which is indistinguishable in the output from a feature that genuinely had no planning.
  The warning names both possible causes, since expired transcripts produce it too and
  the two cannot be told apart from here.
  `check_naive_bounds` warns for each `session_window` bound that states no timezone,
  naming the field and the value and saying it was read as UTC. Scoped to the captured
  feature's own manifest — `check_branch_overlap` reads every other manifest in both
  corpora, and warning about those would bury the actionable line under noise about
  files the author is not editing. It warns rather than fails because the committed
  corpora were all written naive against exactly that reading.
  Its `session_window` bounds are **half-open** — `from` inclusive, `to` exclusive — and
  a session is matched atomically on its start (`min(timestamps)`), the whole session or
  none of it. Exclusive `to` is what lets consecutive features chain windows end to end
  (`{"to": T}` then `{"from": T}`) and be genuinely disjoint, which is how this corpus is
  already written; under an inclusive `to` every such handoff is a latent double-count.
  `check_empty_window` is the other edge of that half-openness: a window with
  `from == to` selects nothing, and `from > to` is the same emptiness written backwards.
  Either way every session on the branch is dropped and the feature freezes at `$0.00`
  with a perfectly correct branch name — the `check_unmatched_branches` failure arriving
  by a route that warning cannot see. Unlike the overlap warning this is *proven* from
  the manifest alone rather than over-approximated, so the message says the feature will
  capture as zero rather than hedging. It compares the normalized instants, not the raw
  strings, so `19:00:00-04:00` against `23:00:00Z` reads as the empty window it is.
  Two features in `self/features/` shipped with `from == to` and held **$38.76** of real
  planning cost at zero until this check was added.
  `check_branch_overlap` warns when two manifests share a branch **and** their windows
  intersect, using the same half-open test — the two must agree, since a guard stricter
  than the matcher warns about safe manifests and a looser one stays silent through a real
  double-count. It previously warned only when *neither* manifest declared a window, which
  meant declaring one on both silenced the only check there was: two open-ended windows on
  a shared branch, the natural thing to write mid-feature, then double-counted every shared
  session in total silence. Shared branch plus overlapping windows is a *possible* double
  count rather than a proven one — it is computed from two manifests without walking a
  transcript — and that over-approximation is deliberate: a false warning costs a `to`
  bound, a missed one costs a silently wrong number.
  That scan, and the branch-overlap warning, both read `roots.all_features_roots()` —
  **both** corpora, never just the one being captured. A branch carries whatever ran on
  it, so a host-repo feature's executor sessions can sit on the same branch as a
  `--self` feature's planning; scoping the scan to one tree prices them a second time,
  as planning, on top of their `usage.json`. This is only visible as an inflated
  planning figure, never as an error.
  Sums tokens for each transcript via `transcript.iter_billable_messages` +
  `add_usage` — see that entry above for the two transcript-format facts
  (per-`message.id` dedup, skipping `model: "<synthetic>"` lines) this depends on but
  that are not visible from the import line.
  It is the only one of these scripts that calls `roots.session_root` rather than
  `roots.artifact_root` for its transcript lookup — nothing in its imports reveals
  that; see "Where to run them" above for why the two must differ under `--self`.
  **No silent zero.** A capture that matches no session and no subagent writes nothing
  and exits non-zero, printing the three things that can be true — a wrong branch name
  (with `git branch --list` as the check), sessions launched somewhere the feature
  cannot claim from (each `cwd` seen, and the feature worktree to launch inside or the
  ids to pin), or transcripts that have aged out. `--force` writes the zero, which is
  the honest record for the third case. Under `--all` a refused zero is counted with the
  other refusals: the walk continues and the run exits non-zero at the end. A `$0.00`
  reads as "planning was free", which is why it has to be asked for. Except when it is
  evidenced: an excluded session — a runner session, or one named in `exclude_sessions`
  — that **carries one of the manifest's `branches` and passed `repo_match`** proves the
  branch name is right and lifts the refusal without `--force`, with a warning saying so.
  Only that narrower set (`excluded_on_branch`) lifts it. The serialized
  `excluded_session_ids` is wider — every excluded session whose transcript sits in this
  repo's directories, on any branch, from any directory — so it is non-empty in every
  repo that has ever run a batch, and a typo'd `branches` would read as an evidenced
  `$0.00` if the refusal rested on it. A session that carries the branch but was launched
  somewhere the feature cannot claim from is the *launched somewhere else* cause above,
  not evidence against it.
  **The one script here that can destroy data, and the only one that refuses a write.**
  `check_frozen_cost` compares the sessions the prior `planning.json` priced against the
  ones **this scan could reach**: a prior session that is neither reachable nor in
  `excluded_ids` is unreproducible, so the run prints what it is protecting and exits 1
  rather than overwriting. `--force` overrides. Reachability is recorded during the walk,
  at the point `repo_match` proves the transcript is usable from this checkout, which is
  what keeps ordinary work quiet — a session dropped by narrowing a `session_window`
  (what settling a `check_branch_overlap` warning does) stays reachable and re-captures
  cleanly. Absent this guard, the documented per-feature loop above is a data-loss
  cadence: one run over humanNetworkMap zeroed 11 features, `add-component-tests` from
  $151.58 to $0.00.
  **Reachability, not file existence** — the distinction is load-bearing, and getting it
  wrong let the guard fail open on the very case it was written for. Asking whether a
  file named `<session_id>.jsonl` exists anywhere under `~/.claude/projects/` is a wider
  question than whether this scan can use it: planning that ran from a git worktree
  leaves transcripts in that worktree's own project directory, whose name contains the
  repo's fragment (so the scan walks it) but whose `cwd` is the worktree (so `repo_match`
  fails, permanently, from this checkout). A filename glob finds that file and vouches
  for a session the scan can never select again — which re-zeroed two features on
  musicMap with exit 0 and no `--force`.
  Asserted by `self/tests/capture-guard.sh`.
- `report.py` — reads a feature's manifest, `planning.json`, and every
  manifest plan's `usage.json` and `.md`, and writes `plans/features/<slug>/report.md`
  / `.report.json` (cost roll-up, re-hunting, churn ratio, cold-start tax, model fit,
  plan-length-vs-LoC, plan-drift and edit-overlap tripwires). Never recomputes a
  dollar figure — every cost comes from a `usage.json` or `planning.json` already on
  disk. Cost is rolled up by walking the manifest's `plans` array, and both directions
  of disagreement with what is on disk are reported: a listed plan with no `usage.json`
  (`missing_usage_plans`) and a `usage.json` with no manifest entry
  (`orphan_usage_plans`). One absence is not a disagreement and is filtered out of the
  first list: a level-verify the runner **skipped** because its level's gate was green
  has no `usage.json` by design, and is reported as `skipped_plans[]` with a one-line
  note instead of making the feature's total a lower bound. The second is the one worth understanding — the runners are
  directory-driven and never read the manifest, so a plan authored into a queue but
  omitted from `plans` runs, bills, and is then excluded from every figure here, making
  the total quietly too low rather than visibly incomplete. Both set `total_is_partial`.
  Within a loaded plan, the recovered figure it rolls up is read from `attempts[]`'s
  own `recovered_cost_usd` values, summed — the durable location. The sidecar's
  top-level `recovered_cost_usd` (`recover_attempts.py`'s convenience sum, as of when it
  last ran) is read too, but only as a cross-check: `write_usage_sidecar`
  (`plan-runner-lib.sh`) rebuilds the sidecar from a fixed key set on any later write to
  a resumed plan, which drops the top-level key while the attempt-level fields survive
  it. They survive because that rebuild merges `attempts[]` **by `session_id`** and a
  resumed attempt is a fresh `claude -p` with a fresh id, so an existing entry passes
  through untouched; an entry whose id *does* match is replaced by the rebuilt five-key
  attempt, which would take `recovered_cost_usd` with it. "Resume gets a new session id"
  is what makes the attempt-level location the durable one.
  When both are present and disagree by more than a cent, `report.py` warns naming
  both figures rather than silently preferring either — a disagreement means something
  rewrote the sidecar since recovery ran.
  Each `attempts[]` entry with `total_cost_usd: null` is further split into three
  buckets: recovered (`recovered_cost_usd` present, `recovered_is_partial` absent — the
  whole transcript priced cleanly; folded into the relevant
  `cost.build`/`cost.verify`/`cost.review` bucket and totalled separately as
  `cost.recovered`), partially recovered (`recovered_cost_usd` present but
  `recovered_is_partial: true` — `recover_attempts.py` found a model in the transcript
  absent from `pricing.RATES`, so the recovered figure prices only the rest; still
  folded into the queue bucket and `cost.recovered`, but named in
  `cost.partially_recovered_attempts[]`), or unrecoverable (`recovered_cost_usd` absent
  too — either `recover_attempts.py` has not been run over this feature yet, or it ran
  and the transcript was already gone; named in `cost.unrecoverable_attempts[]`). The
  partially-recovered and unrecoverable buckets both set `total_is_partial`; only a
  plan whose every killed attempt fully recovered reports a whole, non-partial total.
  `report.py` still never reprices a recovered figure — it only reads
  `recovered_cost_usd` and sums it in, exactly like `total_cost_usd`.
  A manifest with **no** `plans` key at all is a warning rather than a `KeyError`:
  `manifest_plan_stems` falls back to the stems that left a `usage.json`, sorted into
  batch order, and sets `total_is_partial` itself — the recovered list is built from the
  usage index, so neither `missing_usage_plans` nor `orphan_usage_plans` can speak for a
  plan that never ran. `plans/features/TEMPLATE.md` omitted the key for long enough that
  manifests written from it lack it; the template now carries it, and the fallback is for
  the ones already written.
  Resolves each manifest stem to a `usage.json` **within that feature's own
  directory only**: plan numbers restart per feature, so stems like `05-tests-sonnet`
  exist in several features at once and a tree-wide scan would silently price the
  wrong one. Nothing in the imports reveals that constraint. Its model-fit flags
  also cover *scope* — a build-queue plan over `PLAN_HIGH_TURN_THRESHOLD` turns is
  flagged as one to split, not as one on the wrong model (`AGENT_PLANS.md`, "Sizing
  plans for executor cost"); verify- and review-queue plans are exempt, as the
  `--max-budget-usd` their own runners pass is their guard. **Time is rolled up the way cost is.** A `## Time` table mirrors the Cost table row
  for row — planning split into sessions and delegates (from `planning.json`'s
  `duration_s`), build/verify/review from each `usage.json`'s `attempts[].duration_ms`
  — with dollars per minute beside each. Executor minutes sum over plans, so a parallel
  pair counts twice; the wall clock under the table is the runner's own record,
  read from the feature's `timing.jsonl` (`stamp_timing`, `plan-runner-roots.sh`):
  batch span, each pass, the gates, and when the PR opened. A feature with no
  `timing.jsonl` ran before stamping existed and says so. A missing duration input
  marks the time total `(partial)` and suppresses its rate, for the same reason a
  partial cost total is marked. **The manifest's `method` decides what `planning.json`
  means:** absent or `"plans"`, its dollars and minutes are planning; `"direct"`
  (`AGENT_DIRECT.md`), they are the build — the implementer's transcript — and both
  tables say so (`cost.implementer`, `time.implementer_s`). A direct feature that
  stamped `checkpoint` events into `timing.jsonl` gets that one span subdivided:
  `compute_checkpoint_spans` reads the first instant of each `status` and
  `render_time_section` renders `tests_s`, `direct_build_s` and `gate_s` as sub-rows
  under the implementer row. A planned feature's report is unchanged by this even if
  checkpoint events are somehow present — the spans divide an implementer's span, and a
  planned feature has none. An unknown value is warned
  about and read as `"plans"`. `--all` scans every committed `*.report.json`
  and prints a cross-feature trend table (with a minutes column) to stdout (no file
  written). Usage:
  `python3 agentTooling/analysis/report.py <slug>` or
  `python3 agentTooling/analysis/report.py --all`.
- `manifest.py` — reads and writes a feature manifest's machine-readable fence, and reads
  what its `planning.json` claimed: the JSON edits the lifecycle scripts need, kept out of
  bash. Five subcommands, `--self` first as everywhere. `init --method M --branch B --base
  BASE --from TS [--session ID]… [--plan STEM]…` writes `<features root>/<slug>/README.md`
  from `templates/plans/features/TEMPLATE.md` with the template's fence replaced by a
  filled one, and refuses if the file exists — `feature-start.sh` runs it once, in the new
  worktree. `get <key>` prints one scalar or JSON array from the **last** fenced JSON block,
  the one `capture_planning.py` reads — the same fence `plan-runner-roots.sh`'s
  `manifest_field` reads on the shell side with awk and `jq`, which is how
  `run-review.sh` gets `base` for `FEATURE_BASE` without a Python call. `set-window-to [TS]` replaces a `null` `to` bound with TS (default: now,
  UTC, `Z`) and touches nothing else in the file; a bound already set is left alone and
  reported, since a second stamp would move a boundary another manifest may chain to.
  `set-plans <stem>...` replaces the manifest's `plans[]` with the given stems, in the order given, and refuses a stem that is not `NN-name-MODEL` — a sentinel is never a plan.
  `claimed` prints the sessions and subagents `planning.json` holds, each with how it was
  selected and where it was launched, plus the total — what `feature-close.sh` shows the
  human before the number is quoted. The fence it writes is
  `{ slug, method, plans[], branches[], base, session_window{from,to}, exclude_sessions[],
  exclude_subagents[], sessions[], subagents[] }`, one key per line in that order with
  compact values — the shape every hand-written manifest in both corpora already has, so a
  diff after `init` or `set-window-to` shows the change and nothing else. `method` is one
  of `plans`, `direct`, `hand`. Depends on `TEMPLATE.md` still carrying a fenced JSON block to
  replace, and on `roots.features_root` for where the file goes.

## JSON artifacts

Usage, planning, and report artifacts (`usage.json`, `planning.json`, `report.json` / `report.md`) written under `plans/features/<slug>/` by the scripts above, plus the manifest fence they all key off.

- The **feature manifest's fence** — the last fenced JSON block in
  `plans/features/<slug>/README.md`:
  `{ slug, method, plans[], branches[], base, session_window{from,to},
  exclude_sessions[], exclude_subagents[], sessions[], subagents[] }`. Written by
  `manifest.py` on behalf of `feature-start.sh` (`init`) and `feature-close.sh`
  (`set-window-to`); read by `capture_planning.py` (`branches`, `session_window`,
  `exclude_sessions`, `exclude_subagents`, `sessions`, `subagents`),
  by `report.py` (`method`, `plans`) and by `run-review.sh` (`base`, through
  `plan-runner-roots.sh`'s `manifest_field`). `method` is `"plans"` (or absent),
  `"direct"`, or `"hand"` — the last two say the transcripts in `planning.json` are the
  build rather than the planning. `base` is the branch the feature branched from, which
  becomes `FEATURE_BASE` and the PR's base. `sessions` are session ids claimed outright,
  the top-level twin of `subagents`. `agentTooling/AGENT_PLANS.md` → "The feature
  manifest" is the authoring guide; this is the field list the scripts here depend on.
- `usage.json` — `{ plan, model, outcome, session_id, subtype, is_error, num_turns,
  duration_ms, total_cost_usd, usage{input_tokens,cache_creation_input_tokens,
  cache_read_input_tokens,output_tokens}, model_usage{<modelId>:{...}},
  permission_denials, tool_counts{<ToolName>:<int>}, files_edited[repo-relative
  paths], edit_count, attempts[{session_id,outcome,total_cost_usd,num_turns,
  duration_ms,recovered_cost_usd,recovered_tokens{<modelId>:{input,output,cache_read,
  cache_creation_5m,cache_creation_1h}},recovered_from,recovered_at,rates_applied,
  recovered_is_partial,unpriced_models[]}],
  recovered_cost_usd }` — sidecar to a plan's `.md`, written by the runner
  (`finalize_plan`) or backfilled by `backfill_usage.py`; both produce the identical
  shape.
  `attempts[]` holds one record per `claude -p` invocation, oldest first — a resumed
  plan has several, each with its own session id (see `RUNNER.md` → "How resume
  works"). `num_turns`, `duration_ms`, `total_cost_usd`, `usage{}`,
  `permission_denials`, `tool_counts`, `files_edited` and `edit_count` are **sums or
  unions across every attempt**; `session_id`, `outcome`, `subtype`, `is_error` and
  `model_usage` describe only the **latest**. An attempt with `total_cost_usd: null`
  is one that was killed before writing a `result` event: the CLI never learned its
  cost, but `recover_attempts.py` can still price it from its session transcript and
  write `recovered_cost_usd` (plus `recovered_tokens`/`recovered_from`/`recovered_at`/
  `rates_applied`) onto the same attempt — `total_cost_usd` itself is left `null`
  forever, so a measured figure and a recovered one stay distinguishable. If the
  session's transcript contains a model absent from `pricing.RATES`, that model's
  tokens are excluded from `recovered_cost_usd` rather than coerced to a silent 0 (the
  rule `pricing.py` states and `capture_planning.py` already follows): the attempt
  instead carries `unpriced_models` (the excluded model ids) and
  `recovered_is_partial: true`, and `recover_attempts.py` prints the same information
  in its summary line so a partial figure isn't discoverable only by opening the JSON.
  The
  top-level `recovered_cost_usd` is the sum over the sidecar's recovered attempts and
  is absent until `recover_attempts.py` has run — and dropped again by
  `write_usage_sidecar`'s fixed-key rebuild on a resumed plan's later write, which is
  why `report.py` reads the durable `attempts[]` figures instead; see its entry above
  for the three-bucket rule.
  Sidecars written before attempt-tracking landed have no `attempts` key at all, so
  consumers read the top-level `session_id` as well.
- `planning.json` — `{ slug, captured_at, manifest_branches[], sessions[{session_id,
  git_branch,selected_by,cwd,date,started_at,ended_at,duration_s}], subagents[{agent_id,
  parent_session_id,date,started_at,ended_at,duration_s,selected_by,cross_repo}],
  excluded_session_ids[], priced[{session_id,agent_id,model,is_sidechain,date,
  duration_s,tokens{input,output,cache_read,cache_creation_5m,cache_creation_1h},
  cost_usd,rates_applied}], cost_usd{main,sidechain,subagents,total,total_is_partial},
  duration_s{sessions,subagents,entries_without_duration[]}, rates_source,
  warnings[] }` — a feature's frozen planning-phase cost and time, written by
  `capture_planning.py`. `cost_usd` and `rates_applied` are computed once at capture
  time; `report.py` (plan 56) only reads and sums these dollar figures, never
  recomputes them. `duration_s` is a span in whole seconds (first to last transcript
  instant), summed separately over sessions and subagents; an entry carried forward
  from a capture that predates the field has none and is named in
  `entries_without_duration`, so the sums are then lower bounds.
  A session entry's `selected_by` is `"branch"` or `"pinned"` — which of the two routes
  claimed it (the manifest's `branches` plus `session_window`, or its `sessions` pin) —
  and `cwd` is the directory that session was launched in, the fact the whole naming
  rule turns on (`../LIFECYCLE.md`): it is what says whether a session is claimable from
  this checkout at all, and it is `null` only for an entry carried forward from a
  capture that predates the field. `subagents[]` carries its own `selected_by`,
  `"parent"` or `"pinned"`, and no `cwd` — a delegate inherits its parent's.
- `report.json` — `{ slug, generated_at, cost{method,planning,implementer,build,verify,review,total,
  planning_pct,build_pct,verify_pct,review_pct,cost_per_plan,cost_per_file,total_is_partial,
  missing_usage_plans[],skipped_plans[],orphan_usage_plans[],recovered,unrecoverable_attempts[{plan,
  session_id}],partially_recovered_attempts[{plan,session_id}]}, time{method,
  planning_sessions_s,planning_subagents_s,planning_s,implementer_s,tests_s?,
  direct_build_s?,gate_s?,build_s,verify_s,review_s,
  executor_s,total_s,total_is_partial,missing_duration_plans[],wall_clock{first_at,
  last_at,batch_span_s,batch_runs,batch_runs_s,passes_s{auto,verify,review},gates_s,
  gate_runs,plans_s,plan_runs,pr_opened_at,pr_url} | null}, planning_cost_split{
  sessions,subagents}, cold_start_tax_tokens,
  model_fit[{model,plan_count,total_turns,total_cost_usd,total_duration_s,flags[]}], churn[{plan,
  edit_count,files_edited,churn_ratio}], plan_length_vs_loc[{plan,plan_md_lines,
  loc_changed}], re_hunting[{target,tool,plans[]}] | "not computed: streams
  unavailable", plan_drift[{plan,edited_not_listed[],listed_not_edited[]}],
  edit_overlap[{file,earlier_plan,later_plan,overlap_chars}] | "not computed: streams
  unavailable", warnings[] }` — a feature's cost roll-up and waste tripwires, written
  by `report.py`. Every figure comes from a `usage.json` or `planning.json` already on
  disk — summed or divided, never repriced. `total_is_partial` is set when any manifest
  plan has no `usage.json`, any loaded plan has no `total_cost_usd`, or `planning.json`
  is itself partial; both renderings mark such a total `(partial)`, because a roll-up
  missing an input is still a number and otherwise reads as a complete one.
  `report.md` is the human-readable rendering of this same data, with no independent
  numbers of its own.
  `time.tests_s` / `time.direct_build_s` / `time.gate_s` are **present only** for a
  `method: direct` feature whose `timing.jsonl` carries `checkpoint` events (see that
  entry below); each is seconds or `null`, and a report without them is byte-identical
  to one written before they existed. They render as indented sub-rows under the Time
  table's "build: implementer", carrying minutes and no dollars — the implementer's
  transcript is priced as one span and nothing divides its cost the way the instants
  divide its minutes.
  `cost.skipped_plans[]` names the manifest plans the runner filed **without running**
  (`skip_level_verify`, `plan-runner-lib.sh`: a level whose gate came back green does
  not owe its level-verify, so the plan goes to `verify/complete/` with a one-line
  `.progress.md` and no `usage.json`). They are deliberately kept out of
  `missing_usage_plans` and out of `total_is_partial`: nothing ran, nothing was billed,
  and nothing is absent. Detected from the progress log's first line
  (`report.build_skipped_index`), which is the only marker on disk — read with a `[]`
  default, like every key added after the fact.
  **`cost.review`/`cost.review_pct` are read with a `0.0` default,
  never indexed** — every `report.json` written before the review queue existed lacks
  both keys, and `--all`'s whole job is ranking those historical features beside new
  ones. A feature that ran no review pass legitimately reports `0.0`.
  `cost.recovered`/`cost.unrecoverable_attempts[]`/`cost.partially_recovered_attempts[]`
  follow the same precedent, read with a `0.0`/`[]`/`[]` default: every `report.json`
  written before `recover_attempts.py` existed lacks all three. An attempt with
  `total_cost_usd: null` (the CLI never reported a cost) falls into one of three
  buckets: recovered (`recovered_cost_usd` present, `recovered_is_partial` absent — the
  whole session transcript priced cleanly, folded into `cost.build`/`cost.verify`/
  `cost.review` and counted separately in `cost.recovered`), partially recovered
  (`recovered_cost_usd` present but `recovered_is_partial: true` — at least one model in
  the transcript is absent from `pricing.RATES`, so the recovered figure covers only the
  priced portion; still folded into the queue bucket and `cost.recovered`, but named in
  `cost.partially_recovered_attempts[]`), or unrecoverable (`recovered_cost_usd` absent
  too — recovery has not run over the feature, or it ran and the transcript had already
  aged out; named in `cost.unrecoverable_attempts[]`). The partially-recovered and
  unrecoverable buckets both set `total_is_partial`; `cost.unrecoverable_attempts[]` and
  `cost.partially_recovered_attempts[]` each name exactly those `{plan, session_id}`
  pairs.

- `timing.jsonl` — one JSON object per line, `{ at, event, ...detail }`, appended by the
  runners (`stamp_timing`, `plan-runner-roots.sh`) as a batch runs: `batch_start`/
  `batch_end{rc}`, `pass_start`/`pass_end{queue,reason}`, `plan_start`/`plan_end{plan,
  queue,rc}`, `gate_start`/`gate_end{level,rc,green,regate?}`, `pr_opened{rc,url}`, plus
  `checkpoint{status}` appended by hand. `at`
  is UTC to the second; every detail value is a string.
  **`checkpoint{status}`** is a **direct** feature's own milestone
  (`AGENT_DIRECT.md` → "Checkpoint and resume"), written by the implementer with the
  top-level `stamp-timing.sh [--self] <slug> checkpoint status=<status>` at each rewrite
  of its `CHECKPOINT.md`. `status` is one of `planned`, `tests-written`, `implementing`,
  `gating`, `committed` — the checkpoint file's own vocabulary. There is no runner
  between a direct build's commits, so these are the only record of how its one span
  divided; `report.py` reads the **first** instant of each status (a status can be
  re-stamped by a resumed implementer) and derives `tests_s` (`planned` →
  `tests-written`), `direct_build_s` (`tests-written` → `gating`) and `gate_s`
  (`gating` → `committed`). A missing endpoint yields `null` for that span rather than a
  zero, and a feature that stamped no checkpoint gains none of the three keys at all. This is the only record of what
  happens *between* executors — the gates, the parallelism, the stretch to the PR —
  which no `usage.json` can carry. Small and committed. `report.py` pairs the
  start/end events into the Time section's wall clock; an unclosed start (a killed run)
  contributes nothing. A feature without one ran before stamping existed.

### Do not re-price build or verify cost

`usage.json.total_cost_usd` is the **CLI's own** figure, taken from the run's `result`
event; `pricing.py` exists for planning cost, which has no such figure and must be
derived from transcripts. Re-deriving build/verify cost from `usage.json.usage{}` gives a
number roughly 1.5x too low, because that block reports `cache_creation_input_tokens` as
a single total with no 5m/1h split — and these runs are **1-hour** cache writes, billed at
2x base input, not the 1.25x of a 5m write. Solved exactly against a single-model haiku
run: with input, output and cache reads accounted for, the residual divided by the
cache-creation tokens is 2.0000. `model_usage{}` carries a per-model `costUSD` if you need
the breakdown; prefer it over recomputing.
