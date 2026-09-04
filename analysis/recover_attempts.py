"""Recover a killed attempt's cost from its own session transcript.

The runner takes cost from a run's final `result` event, and a killed run never
emits one, so `attempts[].total_cost_usd` stays null forever — the CLI itself
never learned the number. But the runner records `session_id` for every attempt,
including a killed one, and that session's transcript survives under
`~/.claude/projects/` with every token it actually spent. This script prices
those tokens straight from the transcript and writes the result onto the attempt
as `recovered_cost_usd` — never onto `total_cost_usd`, which must stay
distinguishable as the CLI's own figure.

Tokens are summed from the transcript's own `usage.cache_creation.ephemeral_
{5m,1h}_input_tokens` split, not from a `usage.json`'s flat
`cache_creation_input_tokens` total, which cannot tell a 1.25x 5-minute cache
write from a 2x 1-hour one.

Idempotent: an attempt that already carries `recovered_cost_usd` is skipped
unless `--force`.

Usage:
    python3 agentTooling/analysis/recover_attempts.py [--self] [--force]
"""

from __future__ import annotations

import argparse
import glob
import json
from datetime import datetime, timezone
from pathlib import Path

from pricing import compute_cost
from roots import add_self_flag, features_root
from transcript import add_usage, iter_billable_messages, to_utc


def load_transcript_lines(path):
    """Parse each non-blank line as JSON, skipping (not raising on) a line that
    fails to parse."""
    lines = []
    with open(path, "r") as f:
        for raw_line in f:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                lines.append(json.loads(raw_line))
            except json.JSONDecodeError:
                continue
    return lines


def find_transcript(session_id):
    """Locate a session's transcript by globbing
    ~/.claude/projects/*/<session_id>.jsonl — never via roots.session_root.
    Session ids are unique, and a --self executor's cwd (agentTooling/) differs
    from a host-repo executor's (the repo root), so the two land in different
    ~/.claude/projects/ directories; a glob is correct for both and needs no
    root resolution."""
    matches = glob.glob(
        str(Path.home() / ".claude" / "projects" / "*" / f"{session_id}.jsonl")
    )
    return Path(matches[0]) if matches else None


def recover_attempt(session_id):
    """Price one session's transcript. Returns the fields to write onto the
    attempt, or None if no transcript for this session survives."""
    transcript_path = find_transcript(session_id)
    if transcript_path is None:
        return None

    lines = load_transcript_lines(transcript_path)

    totals = {}
    for model, usage, _is_sidechain in iter_billable_messages(lines):
        add_usage(totals, model, usage)

    # The session's earliest INSTANT, dated in UTC — not min() over raw strings then
    # sliced. String ordering picks the wrong line when a transcript mixes timestamp
    # formats, and the slice reads the date in whatever zone the string was written in.
    # `as_of` selects the rate tier, so either mistake is a dollar error; see
    # transcript.utc_date.
    moments = [
        moment
        for moment in (to_utc(line.get("timestamp")) for line in lines)
        if moment is not None
    ]
    as_of = min(moments).date().isoformat() if moments else None

    recovered_tokens = {}
    rates_applied = {}
    unpriced_models = []
    total_cost = 0.0
    for model, tokens in totals.items():
        cost, rates = compute_cost(model, tokens, as_of)
        recovered_tokens[model] = tokens
        rates_applied[model] = rates
        if cost is not None:
            total_cost += cost
        else:
            unpriced_models.append(model)

    result = {
        "recovered_cost_usd": total_cost,
        "recovered_tokens": recovered_tokens,
        "recovered_from": "transcript",
        "recovered_at": datetime.now(timezone.utc).isoformat(),
        "rates_applied": rates_applied,
    }
    # A model missing from pricing.RATES must not silently drop out of the sum
    # (pricing.py: "a silent 0 reads as 'planning was cheap' when it means
    # 'unmeasured'") — mark the attempt partial and name what was skipped, same as
    # capture_planning.py's per-model warn-and-mark-partial for the same case.
    if unpriced_models:
        result["unpriced_models"] = unpriced_models
        result["recovered_is_partial"] = True
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="re-recover an attempt that already carries recovered_cost_usd",
    )
    add_self_flag(parser)
    args = parser.parse_args()

    features_dir = features_root(args.self_mode)

    recovered_count = 0
    recovered_dollars = 0.0
    unrecoverable = []
    partial = []

    for usage_path in sorted(features_dir.rglob("*.usage.json")):
        try:
            data = json.loads(usage_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue

        attempts = data.get("attempts") or []
        if not attempts:
            continue

        plan_stem = data.get("plan") or usage_path.name
        changed = False
        for attempt in attempts:
            if attempt.get("total_cost_usd") is not None:
                continue
            session_id = attempt.get("session_id")
            if not session_id:
                continue
            if attempt.get("recovered_cost_usd") is not None and not args.force:
                continue

            fields = recover_attempt(session_id)
            if fields is None:
                unrecoverable.append((plan_stem, session_id))
                continue

            attempt.update(fields)
            changed = True
            recovered_count += 1
            recovered_dollars += fields["recovered_cost_usd"]
            if fields.get("recovered_is_partial"):
                partial.append((plan_stem, session_id, fields["unpriced_models"]))

        if changed:
            data["recovered_cost_usd"] = sum(
                a["recovered_cost_usd"]
                for a in attempts
                if a.get("recovered_cost_usd") is not None
            )
            with open(usage_path, "w") as f:
                json.dump(data, f, indent=2)

    print(
        f"recovery: {recovered_count} attempt(s) recovered, "
        f"${recovered_dollars:.4f} recovered, {len(unrecoverable)} unrecoverable, "
        f"{len(partial)} partial (unpriced model)"
    )
    if unrecoverable:
        print("unrecoverable:")
        for plan_stem, session_id in unrecoverable:
            print(f"  {plan_stem}: session {session_id} has no surviving transcript")
    if partial:
        print("partial (unpriced models excluded from recovered_cost_usd):")
        for plan_stem, session_id, unpriced_models in partial:
            print(
                f"  {plan_stem}: session {session_id} could not price "
                f"{', '.join(unpriced_models)}"
            )


if __name__ == "__main__":
    main()
