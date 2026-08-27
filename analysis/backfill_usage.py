"""Backfill `<plan>.usage.json` sidecars from pre-existing `.stream.jsonl` files.

Plan 52's runner now writes a `usage.json` sidecar as part of `finalize_plan`, but
every plan that ran before that landed only has its raw `.stream.jsonl` on disk.
This script performs the same extraction, one shot, for any stream file that does
not yet have a sidecar.

Contract: the `usage.json` this script writes must be field-for-field
interchangeable with what the runner's own `finalize_plan` writes going forward.
Downstream tooling (`report.py`, plan 56) must be able to treat a runner-produced
and a backfilled `usage.json` identically, with no special-casing.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from roots import add_self_flag, artifact_root, features_root

STATE_DIRS = {"incomplete", "inprogress", "complete", "failed"}
QUEUE_DIRS = {"auto", "verify", "review"}

# Mutating tool calls the runner itself tracks for a plan's progress log (see
# RUNNER.md) — kept identical here so backfilled files_edited/edit_count agree
# with what the runner would have logged.
EDIT_TOOL_NAMES = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


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
    """Absolute tool-call path -> path relative to REPO_DIR, POSIX-separated.

    A path outside REPO_DIR (e.g. a scratch file under /tmp written while
    driving a GUI check) is left as the raw path given, unchanged — matching
    the runner's own jq `ltrimstr($repo)` (plan-runner-lib.sh), which only
    strips the prefix when it matches and otherwise passes the string through.
    """
    resolved = Path(abs_path).resolve()
    try:
        return resolved.relative_to(repo_dir).as_posix()
    except ValueError:
        return abs_path


def find_queue_segment(stream_path):
    """The <queue> path segment (must be "auto", "verify" or "review") two levels above
    the state dir, i.e. plans/features/<slug>/<queue>/<state>/<stem>.stream.jsonl.
    Returns None if the path doesn't match that shape."""
    state_dir = stream_path.parent
    while state_dir.name not in STATE_DIRS:
        if state_dir == state_dir.parent:
            return None
        state_dir = state_dir.parent
    queue_dir = state_dir.parent
    return queue_dir.name if queue_dir.name in QUEUE_DIRS else None


def load_events(stream_path):
    """Parse each non-blank line as JSON, skipping (not raising on) a line that
    fails to parse — a truncated final line from a killed process is possible."""
    events = []
    with open(stream_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def extract_usage(stream_path, plan_stem, repo_dir):
    """Build the usage.json dict for one stream file, or return None (with a
    printed warning) if no result event was found."""
    events = load_events(stream_path)

    result = None
    for event in events:
        if event.get("type") == "result":
            result = event

    if result is None:
        print(f"WARN: no result event in {stream_path}, skipping")
        return None

    tool_counts = {}
    edit_count = 0
    seen_files = set()

    for event in events:
        if event.get("type") != "assistant":
            continue
        content = event.get("message", {}).get("content", [])
        for block in content:
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            tool_counts[name] = tool_counts.get(name, 0) + 1
            if name in EDIT_TOOL_NAMES:
                file_path = block.get("input", {}).get("file_path")
                if file_path:
                    edit_count += 1
                    seen_files.add(to_repo_relative(file_path, repo_dir))

    # Sorted, matching the runner's own jq `unique` (plan-runner-lib.sh), which
    # sorts and dedupes in one step — the two writers must agree field-for-field.
    files_edited = sorted(seen_files)

    usage = result.get("usage", {})
    outcome = derive_outcome(stream_path)
    return {
        "plan": plan_stem,
        "model": derive_model(plan_stem),
        "outcome": outcome,
        "session_id": result.get("session_id"),
        "subtype": result.get("subtype"),
        "is_error": result.get("is_error"),
        "num_turns": result.get("num_turns"),
        "duration_ms": result.get("duration_ms"),
        "total_cost_usd": result.get("total_cost_usd"),
        "usage": {
            "input_tokens": usage.get("input_tokens", 0),
            "cache_creation_input_tokens": usage.get(
                "cache_creation_input_tokens", 0
            ),
            "cache_read_input_tokens": usage.get("cache_read_input_tokens", 0),
            "output_tokens": usage.get("output_tokens", 0),
        },
        "model_usage": result.get("modelUsage", {}),
        "permission_denials": len(result.get("permission_denials") or []),
        "tool_counts": tool_counts,
        "files_edited": files_edited,
        "edit_count": edit_count,
        # Always exactly one attempt. A `.stream.jsonl` holds a single `claude -p`
        # invocation — run_plan truncates it per attempt — so a backfilled plan that
        # was in fact resumed has lost its earlier attempts before this script ever
        # runs; there is nothing here to recover them from. The field exists so a
        # backfilled sidecar stays field-for-field interchangeable with the runner's
        # own, which capture_planning.py and report.py both now read.
        "attempts": [
            {
                "session_id": result.get("session_id"),
                "outcome": outcome,
                "total_cost_usd": result.get("total_cost_usd"),
                "num_turns": result.get("num_turns"),
                "duration_ms": result.get("duration_ms"),
            }
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite an existing usage.json instead of skipping it",
    )
    add_self_flag(parser)
    args = parser.parse_args()

    features_dir = features_root(args.self_mode)
    if not features_dir.exists():
        print(f"no features directory at {features_dir}, nothing to do")
        return

    written = 0
    skipped_existing = 0
    skipped_no_result = 0

    for stream_path in sorted(features_dir.rglob("*.stream.jsonl")):
        queue = find_queue_segment(stream_path)
        if queue is None:
            print(f"WARN: no auto/verify/review queue ancestor for {stream_path}, skipping")
            continue

        plan_stem = stream_path.name[: -len(".stream.jsonl")]
        usage_path = stream_path.with_name(f"{plan_stem}.usage.json")

        if usage_path.exists() and not args.force:
            skipped_existing += 1
            continue

        data = extract_usage(stream_path, plan_stem, artifact_root(args.self_mode))
        if data is None:
            skipped_no_result += 1
            continue

        with open(usage_path, "w") as f:
            json.dump(data, f, indent=2)

        written += 1

    print(
        f"backfill complete: {written} written, {skipped_existing} skipped "
        f"(already existed), {skipped_no_result} skipped (no result event)"
    )


if __name__ == "__main__":
    main()
