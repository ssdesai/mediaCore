# 55 — Capture and freeze a feature's planning-phase cost

Feature: plan-analytics (plan 7 of 9) — tooling to price a feature end-to-end
(planning plus execution) and surface where delegated fanout wasted effort. This plan
adds `agentTooling/analysis/capture_planning.py`, which mines the interactive session
transcripts behind a feature's plans and freezes their dollar cost into
`plans/features/<slug>/planning.json`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Depends on: 53-analysis-pricing-haiku.md — imports `compute_cost`, `get_rates`, and
`is_rates_stale` from `agentTooling/analysis/pricing.py` (same directory; no package
`__init__.py` needed, the invoked script's directory is on `sys.path[0]`). Only
useful once at least one `usage.json` sidecar exists (from the runner, plan 52, or the
backfill, plan 54) since those supply the runner-session exclusion list — but does not
import anything from 51.

## THE CRITICAL DESIGN POINT

Cost is computed **once, here**, and written as dollars into `planning.json`
alongside the token counts, the `rates_applied`, and a `rates_source` string.
`report.py` (plan 56) must never recompute — it only reads and sums the dollar figures
this script already produced. Rates change (Sonnet 5's intro window expires
2026-08-31), so recomputing at report time would silently reprice a completed
feature's planning cost and destroy cross-feature comparison. This module's docstring
must state this contract explicitly.

## Pinned facts

- `agentTooling/` is a `git subtree`; `REPO_DIR` is its parent. From
  `agentTooling/analysis/capture_planning.py`, `REPO_DIR = Path(__file__).resolve().parents[2]`.
- Feature manifest `plans/features/<slug>/README.md` ends with a fenced ` ```json ` block:
  `{slug, branches:[], plans:[], session_window:{from,to}|null, exclude_sessions:[]}`.
  Parse it by finding the *last* ` ```json ` fence in the file with a regex and
  `json.loads`-ing its contents — do not assume it is the only fence in the file.
  `session_window` is **optional and frequently absent**; treat a missing key, a `null`
  value, and `{"from": null, "to": null}` as identical to "no window".
- Session transcripts live at
  `~/.claude/projects/<cwd-with-slashes-as-dashes>/<session-uuid>.jsonl`. Derive the
  directory name with `str(REPO_DIR).replace("/", "-")` (e.g.
  `/Users/sahildesai/dev/vinylCatalogue` -> `-Users-sahildesai-dev-vinylCatalogue`).
- **That directory is not the only one holding this repo's sessions.** A session whose
  `cwd` moved into its scratchpad gets its own project directory, named for the scratchpad
  path — which embeds the encoded repo name, e.g.
  `-private-tmp-claude-501--Users-sahildesai-dev-vinylCatalogue-<uuid>-scratchpad`, with a
  `cwd` of `/private/tmp/claude-501/-Users-sahildesai-dev-vinylCatalogue/<uuid>/scratchpad`.
  Measured on this repo: 71 sessions sit at the canonical directory and 2 sit in
  scratchpad-named ones — but those 2 include the single largest session in the whole
  history (1701 events). Scanning only the canonical directory, or testing
  `cwd == str(REPO_DIR)`, drops them and understates planning cost with no visible symptom.

  So: glob `Path.home()/".claude"/"projects"` for **every** directory whose name contains
  `transcript_dir_name(REPO_DIR)` as a substring, and accept a session when
  `cwd == str(REPO_DIR)` **or** `transcript_dir_name(REPO_DIR)` appears in its `cwd`. The
  second test needs the encoded form, not the raw path — the scratchpad `cwd` contains
  `-Users-sahildesai-dev-vinylCatalogue` with dashes, so a substring test against the raw
  `/Users/...` path fails.
- Transcript line shape: `type` (`assistant`/`user`/`summary`/...), `timestamp`,
  `sessionId`, `cwd`, `gitBranch`, `isSidechain` are top-level fields on every line
  (not nested under `message`). For `type == "assistant"` lines: `message.model` and
  `message.usage{input_tokens,cache_creation_input_tokens,cache_read_input_tokens,
  output_tokens}`, with `message.usage.cache_creation{ephemeral_5m_input_tokens,
  ephemeral_1h_input_tokens}` giving the TTL split. **There is no cost field** — dollars
  must be computed here via `pricing.compute_cost`.
- `isSidechain: true` messages are Explore/Plan subagent calls — the planning-phase
  fanout cost, tracked and reported as a separate headline number from the main-thread
  cost.
- Runner-spawned sessions land in this same transcripts directory and MUST be
  excluded. Identify them by session id appearing in any `usage.json`'s `session_id`
  field — glob `Path(REPO_DIR, "plans", "features").rglob("*.usage.json")`, which covers
  every feature and both queues in one pass. Also exclude any id listed in the manifest's
  `exclude_sessions`.
- Session selection: a transcript file belongs to this feature if it passes the repo test
  above, has `gitBranch` in the manifest's `branches`, its **session start** falls inside
  `session_window`, and its `sessionId` is not in either exclusion set.
- `session_window` filtering: compare the session's **full ISO 8601 start timestamp** —
  its earliest line's `timestamp`, not the date portion — against `from`/`to`
  **inclusive**, as plain string comparison. ISO 8601 sorts lexicographically, so a bare
  `>=`/`<=` on the strings is correct. A `null` bound is open-ended on that side. Bounds
  in the manifest are written as full timestamps (`2026-07-29T21:35:00`); a bound given as
  a bare date still works, but only as a coarse boundary — see below for why that is not
  enough.

  This exists because **one branch can host several features in sequence**: this repo's
  `browseImages` branch hosted `manual-readings-and-browse`, `image-versions-and-copies`
  and `plan-analytics`, so branch alone would attribute every planning session to all
  three and report roughly triple the true cost for each. Getting this wrong is invisible
  in the output — the numbers look plausible, just uniformly inflated — so it is worth a
  line in the module docstring saying what the window is for.

  **Date granularity is provably insufficient on this repo's own data**, which is why the
  comparison is on timestamps. The three features' planning sessions are
  `2026-07-29T18:29`–`21:34`, `2026-07-29T21:36`–`2026-07-30T15:47`, and
  `2026-07-30T15:51`–onward: the middle session starts on the same calendar day the first
  ends and finishes on the same calendar day the third begins, so **every** date-level
  boundary either drops a real session or double-counts one. The gaps between features are
  minutes wide, not days.
- A session is attributed by its start timestamp alone, so a session that *spans* a
  boundary lands entirely in one window. Detect it: if a selected session's last
  `timestamp` is greater than a non-null `to`, or an unselected same-branch session's last
  timestamp reaches past `from` while its start precedes it, add a `warnings` entry naming
  the session id and both bounds. On this repo's data no session spans a boundary, so a
  warning here means the manifest's window has drifted from reality and needs re-deriving.
- Report, in the output's `warnings` and on stdout, when a feature's `branches` overlap
  another manifest's and **neither** declares a `session_window`. That is the shape of
  the double-counting bug above, and it is cheap to detect here: read every
  `plans/features/*/README.md` fence, not just this feature's.
- Design decision (state it in the module docstring): price **per (session, model,
  is_sidechain)**, using that session's own date, then sum the resulting dollars — do
  not sum raw tokens across sessions first and price once. A feature whose planning
  phase straddles the Sonnet 5 intro-pricing expiry (2026-08-31) would otherwise have
  every token priced at whichever rate wins after aggregation, silently mispricing
  part of the feature. A session's date is simplified to a single value — the date
  portion of its earliest line's `timestamp` — since planning sessions are short-lived
  relative to the intro-pricing window.
- Must warn (not fail, via a `warnings` list in the output, plus a printed line) when:
  - `pricing.is_rates_stale()` is true.
  - `pricing.compute_cost` returns `(None, None)` for some (session, model) — i.e. an
    unrecognized model. Its tokens still appear in `priced` with `cost_usd: null` and
    `rates_applied: null` (never coerced to 0); set `cost_usd.total_is_partial: true` in
    that case since the total then excludes an unpriced chunk.

## `planning.json` output shape (exact — pin this for plan 56 too)

```
{
  "slug": "<slug>",
  "captured_at": "<ISO8601 timestamp, now, UTC>",
  "manifest_branches": ["..."],
  "sessions": [ {"session_id": "...", "git_branch": "...", "date": "YYYY-MM-DD"} ],
  "excluded_session_ids": ["..."],
  "priced": [
    { "session_id": "...", "model": "claude-sonnet-5", "is_sidechain": false,
      "date": "YYYY-MM-DD",
      "tokens": {"input": N, "output": N, "cache_read": N,
                 "cache_creation_5m": N, "cache_creation_1h": N},
      "cost_usd": 1.2345 | null,
      "rates_applied": {...pricing.RatesApplied...} | null }
  ],
  "cost_usd": {"main": float, "sidechain": float, "total": float,
               "total_is_partial": bool},
  "rates_source": "agentTooling/analysis/pricing.py RATES_VERIFIED=2026-07-30",
  "warnings": ["..."]
}
```

`main` sums `cost_usd` over `priced` entries with `is_sidechain == false`; `sidechain`
sums the rest; `total` = `main + sidechain`, treating a `null` entry as contributing 0
to the sum while still setting `total_is_partial`.

## Files

- Create `agentTooling/analysis/capture_planning.py`
- Modify `agentTooling/analysis/README.md`

## `agentTooling/analysis/capture_planning.py`

Paste these two small pure helpers verbatim:

```python
def transcript_dir_name(repo_dir):
    """cwd path -> its transcript directory name under ~/.claude/projects/,
    e.g. /Users/x/dev/vinylCatalogue -> -Users-x-dev-vinylCatalogue."""
    return str(repo_dir).replace("/", "-")


def session_date(timestamp):
    """ISO8601 event timestamp -> its date portion, e.g.
    "2026-07-29T18:04:11.123Z" -> "2026-07-29".

    For PRICING only — which rate table row applies. Window filtering must use the
    full timestamp instead: this repo's features are minutes apart, not days, so a
    date-level boundary cannot separate them."""
    return timestamp[:10]
```

And this token-accumulation helper verbatim (folds one assistant message's usage into
a running per-(model, is_sidechain) totals dict, keyed as described below):

```python
def add_usage(totals, key, usage):
    """Fold one assistant message's usage into totals[key], a dict with keys
    input, output, cache_read, cache_creation_5m, cache_creation_1h. `key` is
    whatever the caller groups by (e.g. (session_id, model, is_sidechain))."""
    bucket = totals.setdefault(
        key,
        {"input": 0, "output": 0, "cache_read": 0,
         "cache_creation_5m": 0, "cache_creation_1h": 0},
    )
    bucket["input"] += usage.get("input_tokens", 0)
    bucket["output"] += usage.get("output_tokens", 0)
    bucket["cache_read"] += usage.get("cache_read_input_tokens", 0)
    cache_creation = usage.get("cache_creation") or {}
    bucket["cache_creation_5m"] += cache_creation.get("ephemeral_5m_input_tokens", 0)
    bucket["cache_creation_1h"] += cache_creation.get("ephemeral_1h_input_tokens", 0)
```

Describe the rest in prose — this is new-from-scratch orchestration built on the
decisions pinned above, not a settled single-shape block:

- Module docstring states the critical-design-point contract verbatim (cost frozen
  here, never recomputed downstream) and the per-(session, model, is_sidechain) pricing
  decision and why.
- CLI via `argparse`: one required positional arg, the feature slug.
- `REPO_DIR = Path(__file__).resolve().parents[2]`.
- Load the manifest: read `plans/features/<slug>/README.md`, regex the last ` ```json ` fence,
  `json.loads` it, pull `branches`, `plans` (unused here — planning cost is
  branch-scoped, not plan-scoped), `exclude_sessions`.
- Build the runner-session exclusion set from every `usage.json`'s `session_id` field
  (glob as pinned above), union with `exclude_sessions` from the manifest.
- List transcript files: `Path.home() / ".claude" / "projects" / transcript_dir_name(REPO_DIR)`,
  glob `*.jsonl`. For each file, stream it line by line (`json.loads` per line,
  skip lines that fail to parse) and:
  - Track whether any line has `cwd == str(REPO_DIR)` and `gitBranch` in
    `manifest["branches"]`, and the file's `sessionId` (take it from the first line
    that has one — expect it to be consistent for the whole file).
  - If the session id is in the exclusion set, skip the whole file.
  - If the file matches, walk its lines again (or in the same pass) and for every
    `type == "assistant"` line call `add_usage(totals, (session_id, message["model"],
    line.get("isSidechain", False)), message["usage"])`. Track the minimum `timestamp`
    seen for the session to derive its `session_date` once at the end.
- After all matching transcripts are processed, for each `(session_id, model,
  is_sidechain)` key in `totals`: call `pricing.compute_cost(model, tokens,
  as_of=session_date_for(session_id))`, and build one `priced` entry per the shape
  above. Append a warning string for any `(None, None)` result naming the model and
  session id.
- Compute `cost_usd.main` / `.sidechain` / `.total` / `.total_is_partial` per the
  aggregation rule above. If `pricing.is_rates_stale()`, append a warning
  `"RATES_VERIFIED is stale (verified {pricing.RATES_VERIFIED})"`.
- `rates_source = f"agentTooling/analysis/pricing.py RATES_VERIFIED={pricing.RATES_VERIFIED}"`.
- Build the `sessions` list (one entry per matched, non-excluded session:
  `session_id`, `git_branch`, `date`) and `excluded_session_ids` (sorted list of the
  exclusion set actually encountered, for auditability).
- Write `plans/features/<slug>/planning.json` with `json.dump(data, f, indent=2)`.
- Print a one-line summary: sessions matched, sessions excluded, total cost (or "cost
  unavailable — see warnings" if `total_is_partial`), and print each warning.

## `agentTooling/analysis/README.md`

Append one entry under `## Scripts`, same Rule 1 field-list shape as the existing
entries:

> - `capture_planning.py` — mines `~/.claude/projects/` session transcripts for a
>   feature's branches, excludes runner-spawned sessions (any id already in a
>   `usage.json`) and `exclude_sessions`, sums tokens per `(session, model,
>   is_sidechain)`, prices each with `pricing.compute_cost` using that session's own
>   date, and freezes the result as dollars into `plans/features/<slug>/planning.json`.
>   Cost is computed once here; nothing downstream recomputes it. Usage:
>   `python3 agentTooling/analysis/capture_planning.py <slug>`.

Add the `planning.json` field list to `## JSON artifacts` (paste the exact
shape from this plan's "output shape" section above, condensed to one bullet per README
Rule 1).
