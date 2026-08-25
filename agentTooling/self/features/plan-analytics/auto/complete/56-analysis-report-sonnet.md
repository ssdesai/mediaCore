# 56 — Cross-feature cost and waste report

Feature: plan-analytics (plan 8 of 9) — tooling to price a feature end-to-end
(planning plus execution) and surface where delegated fanout wasted effort. This plan
adds `agentTooling/analysis/report.py`, which reads a feature's frozen cost figures
and its plans' execution records and writes the committed report: cost roll-up, waste
metrics, and tripwires for one feature, plus a `--all` cross-feature trend view.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Depends on: 55-analysis-capture-planning-sonnet.md for `planning.json`'s shape
(read-only), and on `usage.json` sidecars existing (written by the runner per plan 52,
or backfilled per 54-analysis-backfill-sonnet.md). May import `pricing.RATES_VERIFIED`
/ `pricing.is_rates_stale` purely to footnote rate freshness in the report — must NOT
call `compute_cost` or recompute any dollar figure; every cost number in the output
comes from a `usage.json`'s `total_cost_usd` or a `planning.json`'s `cost_usd`, summed
or divided, never repriced.

## Pinned facts

- `agentTooling/` is a `git subtree`; `REPO_DIR` is its parent. From
  `agentTooling/analysis/report.py`, `REPO_DIR = Path(__file__).resolve().parents[2]`.
- Feature manifest `plans/features/<slug>/README.md` ends with a fenced ` ```json ` block:
  `{slug, branches:[], plans:[], exclude_sessions:[]}`. Parse by regexing the last
  ` ```json ` fence and `json.loads`.
- `planning.json` shape (written by plan 55, read-only here):
  ```
  { slug, captured_at, manifest_branches, sessions:[{session_id,git_branch,date}],
    excluded_session_ids, priced:[{session_id,model,is_sidechain,date,tokens{input,
    output,cache_read,cache_creation_5m,cache_creation_1h},cost_usd,rates_applied}],
    cost_usd:{main,sidechain,total,total_is_partial}, rates_source, warnings }
  ```
  This report's "planning" cost bucket is `planning.cost_usd.total`.
- `<plan>.usage.json` shape (written by the runner or backfilled by plan 54):
  ```
  { plan, model, outcome, session_id, subtype, is_error, num_turns, duration_ms,
    total_cost_usd, usage:{input_tokens,cache_creation_input_tokens,
    cache_read_input_tokens,output_tokens}, model_usage:{<modelId>:{...}},
    permission_denials, tool_counts:{<ToolName>:<int>}, files_edited:[repo-relative
    paths], edit_count }
  ```
- Locate a manifest plan's `usage.json` (and its sibling `.md` and `.stream.jsonl`) by
  globbing recursively, never by assuming a fixed directory: build an index
  `{plan_stem: path}` from `Path(REPO_DIR,"plans","features").rglob("*.usage.json")`,
  keyed by each JSON's own `"plan"` field (not by filename position). A plan's `.md` and
  `.stream.jsonl` (if present) are siblings of its `usage.json` in that same directory.
  Whether a plan is "build" or "verify" cost comes from the `<queue>` segment of its path
  (`plans/features/<slug>/<queue>/<state>/`), not from its filename — a plan named
  `NN-verify-*` is not necessarily a verify-queue plan, and vice versa.
- Per `RUNNER.md`, the mutating tool calls that make up a plan's edits are `Edit`,
  `Write`, `MultiEdit`, `NotebookEdit` — already reflected in `usage.json`'s
  `files_edited` / `edit_count`; do not recompute these from streams.
- **Degrade gracefully, explicitly.** Re-hunting and cross-plan edit overlap need
  `.stream.jsonl`, which is gitignored and may be absent (evicted, or a batch that
  predates capture and was never backfilled with streams kept). If a manifest plan's
  stream is missing, compute that metric across the plans that do have one and name
  which stems were skipped. If **none** of the batch's plans have a stream, emit
  exactly the string `"not computed: streams unavailable"` for that metric — never a
  silent zero or empty table.

## `report.json` output shape

```
{
  "slug": "<slug>",
  "generated_at": "<ISO8601 timestamp, now, UTC>",
  "cost": {"planning": float, "build": float, "verify": float, "total": float,
           "planning_pct": float, "build_pct": float, "verify_pct": float,
           "cost_per_plan": float, "cost_per_file": float},
  "cold_start_tax_tokens": int,
  "model_fit": [{"model": "...", "plan_count": int, "total_turns": int,
                 "total_cost_usd": float | null, "flags": ["..."]}],
  "churn": [{"plan": "...", "edit_count": int, "files_edited": int,
             "churn_ratio": float}],
  "plan_length_vs_loc": [{"plan": "...", "plan_md_lines": int,
                          "loc_changed": int | "not computed: streams unavailable"}],
  "re_hunting": [{"target": "...", "tool": "Grep|Glob|Read", "plans": ["..."]}]
               | "not computed: streams unavailable",
  "plan_drift": [{"plan": "...", "edited_not_listed": [...], "listed_not_edited": [...]}],
  "edit_overlap": [{"file": "...", "earlier_plan": "...", "later_plan": "...",
                    "overlap_chars": int}] | "not computed: streams unavailable",
  "warnings": ["..."]
}
```

`report.md` is the human-readable rendering of the same computed values — one
section per key above, tables for the list-valued ones — generated from this same
data, never recomputing a number.

## Files

- Create `agentTooling/analysis/report.py`
- Modify `agentTooling/analysis/README.md`

## `agentTooling/analysis/report.py`

Paste these two named-constant blocks verbatim (magic thresholds, not hardcoded
inline):

```python
# Model-fit flags: turn counts outside these bounds get called out in the report.
HAIKU_HIGH_TURN_THRESHOLD = 8   # a haiku plan taking this many turns suggests it
                                # needed more judgment than haiku gives
SONNET_LOW_TURN_THRESHOLD = 3   # a sonnet plan finishing this fast suggests haiku
                                # would have sufficed

# Cross-plan edit overlap: minimum shared-substring length to count as a real
# region overlap rather than a trivial match (shared whitespace, a common import
# line). Below this, two plans touching the same file are not a finding — see
# AGENT_PLANS.md's frontend/src/App.tsx counter-example (plans 44/45, disjoint
# regions, zero interaction).
EDIT_OVERLAP_MIN_CHARS = 40
```

Describe the rest in prose — new-from-scratch orchestration over the data pinned
above:

- Module docstring states the no-recompute contract verbatim.
- CLI via `argparse`: one positional arg `slug` (optional when `--all` is passed,
  required otherwise), one flag `--all`.
- `REPO_DIR = Path(__file__).resolve().parents[2]`.

**Single-feature mode (`slug` given, no `--all`):**

- Load the manifest (`plans/features/<slug>/README.md`) for `plans` (ordered list of plan
  stems) and `slug`.
- Load `plans/features/<slug>/planning.json`.
- Build the `{plan_stem: usage_json_path}` index as pinned above; load each manifest
  plan's `usage.json`. A plan listed in the manifest with no `usage.json` found is a
  warning (`"no usage.json for plan {stem}"`), not a crash — skip it from the
  cost/churn/model-fit tables but still note it.
- **Cost roll-up:** `planning = planning.cost_usd.total`; `build` = sum of
  `total_cost_usd` over usage.json's whose path `<queue>` segment is `auto`; `verify` =
  same for `verify`; `total = planning + build + verify`. Percentages = each / total * 100
  (0 if total is 0). `cost_per_plan = total / len(manifest["plans"])`.
  `cost_per_file = total / (number of distinct repo-relative paths across the union of
  every loaded usage.json's files_edited)`.
- **Cold-start tax:** sum `usage["cache_creation_input_tokens"]` (the flat runner
  field, not the transcript's split — this metric is about the *build/verify* fanout,
  not planning) across every loaded `usage.json`. Single int.
- **Model fit:** group loaded `usage.json`s by `model`. Per group: `plan_count`,
  `total_turns` (sum `num_turns`), `total_cost_usd` (sum `total_cost_usd`, or `null` if
  any member plan's `total_cost_usd` is itself null/missing — do not silently treat
  missing as 0). Flags: append a string to `flags` when a `haiku` plan's `num_turns >
  HAIKU_HIGH_TURN_THRESHOLD`, or a `sonnet` plan's `num_turns < SONNET_LOW_TURN_THRESHOLD`
  (name the plan and its turn count in the flag text).
- **Churn ratio:** one row per plan: `edit_count`, `len(files_edited)` as
  `files_edited`, `churn_ratio = edit_count / files_edited` (skip a plan with 0 files
  edited rather than dividing by zero — note it separately).
- **Plan length vs LoC changed:** `plan_md_lines` = line count of the plan's `.md` file
  (always available, it's committed). `loc_changed`: if the plan's `.stream.jsonl` is
  present (sibling of its `usage.json`), sum over its `Edit`/`Write` tool_use blocks
  `max(len(old_string.splitlines()), len(new_string.splitlines()))` for Edit, and
  `len(content.splitlines())` for Write; else the string
  `"not computed: streams unavailable"` for that one row (per-plan degradation, not
  the whole metric).
- **Re-hunting (needs streams):** for every plan with a `.stream.jsonl`, scan its
  assistant tool_use blocks for `name in {"Grep","Glob","Read"}`, extracting a target
  string (`input.pattern` for Grep/Glob, `input.file_path` for Read). Build
  `target -> {plan stems that used it}`; keep only targets used by 2+ distinct plans.
  Apply the batch-wide degrade rule from "Pinned facts" above.
- **Plan drift (tripwire, silent unless non-empty):** for each plan's `.md`, find a
  heading line matching `## Files` case-insensitively (be lenient: accept any `##`
  heading containing "file"), collect the bullet lines until the next `##` heading,
  and extract backtick-quoted spans that look like a path (contain `/` or a `.`
  extension) as the "listed" set, repo-relativized. Compare against the plan's
  `files_edited`. `edited_not_listed` = edited − listed; `listed_not_edited` = listed −
  edited. Only include a plan in the output if either set is non-empty. Note in the
  module docstring that this extraction is a best-effort heuristic and may
  false-positive (e.g. a README updated per CONVENTIONS.md but not itemized in the
  plan's file list).
- **Cross-plan edit overlap (tripwire, needs streams):** process manifest plans in
  batch order (ascending numeric prefix of the stem). Maintain, per repo-relative file
  path, the list of `new_string` (Edit) / `content` (Write) values written by earlier
  plans, each tagged with the plan that wrote it. For each later plan's Edit tool_use
  block on that same file, check whether its `old_string` and any earlier plan's
  recorded text share a common substring of length >= `EDIT_OVERLAP_MIN_CHARS`
  (a simple substring containment check in either direction is sufficient — no need
  for a full LCS). Record `{file, earlier_plan, later_plan, overlap_chars}` for each
  hit. This must be region-level, not file-level: two plans editing the same file with
  no shared substring above the threshold is not a finding (see the App.tsx
  counter-example in the constants block above). Apply the batch-wide degrade rule.
- Assemble `report.json` per the shape above and write it with
  `json.dump(data, f, indent=2)` to `plans/features/<slug>/report.json`.
- Render `report.md`: one Markdown section per key in the JSON, in the same
  order, with the list-valued keys as tables. Include a footnote line using
  `pricing.RATES_VERIFIED` / `pricing.is_rates_stale()` noting whether rates are fresh
  as of report generation (display only, never affects any number above). Write to
  `plans/features/<slug>/report.md`.
- Print a one-line summary: total cost, planning/build/verify split, and any
  `warnings`.

**Trend mode (`--all`):**

- Glob `plans/features/*/report.json`, load each.
- Print a Markdown table to stdout only (no file is written for this mode — it is a
  terminal comparison view over already-committed reports): one row per feature,
  columns `slug`, `cost.total`, `cost.planning_pct`, `cost.build_pct`,
  `cost.verify_pct`, `cost.cost_per_plan`, `generated_at`. Sort rows by `generated_at`
  ascending so the table reads as a timeline. This is the point of `--all` — a single
  feature's numbers mean little without prior features to compare against.

## `agentTooling/analysis/README.md`

Append one entry under `## Scripts`:

> - `report.py` — reads a feature's manifest, `planning.json`, and every
>   manifest plan's `usage.json` and `.md`, and writes `plans/features/<slug>/report.md`
>   / `.report.json` (cost roll-up, re-hunting, churn ratio, cold-start tax, model fit,
>   plan-length-vs-LoC, plan-drift and edit-overlap tripwires). Never recomputes a
>   dollar figure — every cost comes from a `usage.json` or `planning.json` already on
>   disk. `--all` scans every committed `*.report.json` and prints a cross-feature
>   trend table to stdout (no file written). Usage:
>   `python3 agentTooling/analysis/report.py <slug>` or
>   `python3 agentTooling/analysis/report.py --all`.

Add the `report.json` field list (paste this plan's "output shape" section,
condensed to one Rule-1 bullet) to `## JSON artifacts`, and one line noting
`report.md` is the human-readable rendering of the same data with no
independent numbers of its own.
