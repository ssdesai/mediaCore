# 54 — Backfill `usage.json` from existing streams

Feature: plan-analytics (plan 6 of 9) — tooling to price a feature end-to-end
(planning plus execution) and surface where delegated fanout wasted effort. This plan
is a one-shot backfill: `agentTooling/analysis/backfill_usage.py` extracts the same
`<plan>.usage.json` sidecar plan 52's runner now writes going forward, but for every
`.stream.jsonl` that already exists on disk from before that landed.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Independent of other plans. Shares `agentTooling/analysis/` with plan 53 but does not
import `pricing.py` — the runner's `result` event already carries `total_cost_usd`
directly, so nothing here needs repricing.

**Urgency:** `.stream.jsonl` is gitignored by design — it is the *only* surviving
record of cost for every batch that ran before plan 52's capture landed. Once a
`.stream.jsonl` is deleted or garbage-collected, that batch's cost is unrecoverable.
Run this backfill before that happens.

## Pinned facts

- Plan queue layout: `plans/features/<slug>/auto/{incomplete,inprogress,complete,failed}/`
  and the same four states under `.../verify/`, e.g.
  `plans/features/image-versions-and-copies/auto/complete/40-ingest-real-copies-haiku.stream.jsonl`.
  One recursive scan covers everything: `Path(REPO_DIR, "plans", "features").rglob("*.stream.jsonl")`.
- Derive queue and outcome from the path rather than the filename: for a stream at
  `plans/features/<slug>/<queue>/<state>/<stem>.stream.jsonl`, `state` is `path.parent.name`,
  `queue` is `path.parent.parent.name`, and `slug` is one level above that. Do not assume a
  fixed depth from `plans/` — assert the `<queue>` segment is `auto` or `verify` and skip
  (with a warning) anything that doesn't match, so a stray file can't be silently
  misattributed.
- `agentTooling/` is a `git subtree`; `REPO_DIR` is its parent. From
  `agentTooling/analysis/backfill_usage.py`, `REPO_DIR = Path(__file__).resolve().parents[2]`.
- Filename convention: `NN-description-MODEL.md` (and its `.stream.jsonl` /
  `.usage.json` siblings share the same stem `NN-description-MODEL`).
- `.stream.jsonl` is raw `claude -p --output-format stream-json` output, one JSON
  object per line. The final line is `{"type":"result", ...}` carrying `total_cost_usd`,
  `num_turns`, `duration_ms`, `usage{input_tokens,cache_creation_input_tokens,
  cache_read_input_tokens,output_tokens}`, `modelUsage{}` (camelCase — rename to
  `model_usage` in the sidecar, this is the one key that changes name),
  `permission_denials`, `session_id`, `subtype`, `is_error`.
- Assistant events are `{"type":"assistant","message":{"content":[...]}}` where content
  blocks of `{"type":"tool_use","name":...,"input":{...}}` carry tool calls. Edit blocks
  have `input.file_path`, `input.old_string`, `input.new_string`; Write has
  `input.file_path`, `input.content`.
- Per `RUNNER.md`, the mutating tool calls the runner itself tracks for a plan's
  progress log are exactly `Edit`, `Write`, `MultiEdit`, `NotebookEdit` — use this same
  set for `files_edited` / `edit_count` so the backfilled counts agree with what the
  runner would have logged.
- `<plan>.usage.json` exact shape:
  ```
  { plan, model, outcome, session_id, subtype, is_error, num_turns, duration_ms,
    total_cost_usd, usage:{input_tokens,cache_creation_input_tokens,
    cache_read_input_tokens,output_tokens}, model_usage:{<modelId>:{...}},
    permission_denials, tool_counts:{<ToolName>:<int>},
    files_edited:[repo-relative paths], edit_count }
  ```
- **Contract:** this script's output must be field-for-field interchangeable with
  what plan 52's runner writes going forward — `report.py` (plan 56) must be able to
  treat a runner-produced and a backfilled `usage.json` identically with no
  special-casing. State this in the module docstring.

## Files

- Create `agentTooling/analysis/backfill_usage.py`
- Modify `agentTooling/analysis/README.md`

## `agentTooling/analysis/backfill_usage.py`

Paste these three small pure helpers verbatim:

```python
STATE_DIRS = {"incomplete", "inprogress", "complete", "failed"}


def derive_outcome(stream_path):
    """First STATE_DIRS ancestor name walking up from the stream file — handles
    archived batches nested one level deeper under complete/<branch>/."""
    for parent in stream_path.parents:
        if parent.name in STATE_DIRS:
            return parent.name
    raise ValueError(f"no state directory ancestor for {stream_path}")


def derive_model(stem):
    """Trailing hyphen-segment of a plan stem, e.g.
    "40-ingest-real-copies-haiku" -> "haiku"."""
    return stem.rsplit("-", 1)[-1]


def to_repo_relative(abs_path, repo_dir):
    """Absolute tool-call path -> path relative to REPO_DIR, POSIX-separated."""
    from pathlib import Path

    return Path(abs_path).resolve().relative_to(repo_dir).as_posix()
```

Describe the rest in prose — this is new-from-scratch orchestration, not a settled
single-shape block:

- Module docstring states the interchangeability contract above.
- `REPO_DIR = Path(__file__).resolve().parents[2]`.
- CLI via `argparse`: no positional args, one flag `--force` (store_true) to overwrite
  an existing `usage.json` instead of skipping it.
- Collect stream paths: `sorted(Path(REPO_DIR, "plans", "features").rglob("*.stream.jsonl"))` (return early if that root doesn't exist).
- For each stream path:
  - `plan_stem` = filename with the `.stream.jsonl` suffix removed.
  - `usage_path` = sibling `<plan_stem>.usage.json`. If it exists and `--force` was not
    passed, skip (count as skipped, print nothing per-file — print a total at the end).
  - Read the file line by line, `json.loads` each non-blank line, skipping (not
    crashing on) a line that fails to parse — a truncated final line from a killed
    process is possible and should not abort the whole backfill.
  - Track the last event with `"type" == "result"` seen (defensive: don't assume it is
    strictly the final line).
  - Walk every `"type" == "assistant"` event's `message.content` list. For each block
    with `"type" == "tool_use"`: increment `tool_counts[block["name"]]`. If
    `block["name"]` is one of `Edit`, `Write`, `MultiEdit`, `NotebookEdit` and
    `block["input"]` has a `file_path`, convert it with `to_repo_relative` and append to
    an `edit_count` counter (every call) and a `files_edited` list (first-appearance
    order, deduplicated).
  - If no `result` event was found, skip this stream with a printed warning (nothing to
    write — a killed run before any result never happened per the runner's own model).
  - Build the `usage.json` dict per the pinned shape: `plan=plan_stem`,
    `model=derive_model(plan_stem)`, `outcome=derive_outcome(stream_path)`,
    `session_id`/`subtype`/`is_error`/`num_turns`/`duration_ms`/`total_cost_usd`/
    `permission_denials` copied directly off the result event, `usage` copied from
    `result["usage"]`, `model_usage` copied from `result["modelUsage"]` (the rename),
    plus the computed `tool_counts`, `files_edited`, `edit_count`.
  - Write with `json.dump(data, f, indent=2)`; create parent dirs is unnecessary since
    the sidecar always lands beside the stream file, which already exists.
- Print a final one-line summary: number written, number skipped (already existed),
  number skipped (no result event).

## `agentTooling/analysis/README.md`

Append one entry under the existing `## Scripts` section (do not restructure what plan
50 wrote), following the same Rule 1 field-list shape:

> - `backfill_usage.py` — one-shot extraction of `<plan>.usage.json` sidecars from
>   `.stream.jsonl` files already on disk, for batches that ran before the runner
>   captured usage directly (plan 52). Idempotent: skips a plan that already has a
>   `usage.json` unless `--force` is passed. Run once, promptly — `.stream.jsonl` is
>   gitignored and is the only surviving cost record for pre-existing batches. Output
>   is field-for-field identical in shape to the runner's own `usage.json` (see
>   `AGENT_PLANS.md` / the runner's `finalize_plan`) so downstream tooling never needs
>   to distinguish the two.

Add the `usage.json` field list to the `## JSON artifacts` section (still mostly a
placeholder after this plan — `planning.json` and the report artifacts are
added by plans 55 and 56):

> - `usage.json` — `{ plan, model, outcome, session_id, subtype, is_error, num_turns,
>   duration_ms, total_cost_usd, usage{input_tokens,cache_creation_input_tokens,
>   cache_read_input_tokens,output_tokens}, model_usage{<modelId>:{...}},
>   permission_denials, tool_counts{<ToolName>:<int>}, files_edited[repo-relative
>   paths], edit_count }` — sidecar to a plan's `.md`, written by the runner
>   (`finalize_plan`) or backfilled by `backfill_usage.py`; both produce the identical
>   shape.
