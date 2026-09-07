"""Recover an unpriced attempt's cost from its own session transcript.

The runner takes cost from a run's final `result` event. **Two different things
leave an attempt without one**, and both end as `attempts[].total_cost_usd:
null` — the CLI itself never learned the number:

  * a **killed** run (Ctrl-C, SIGKILL, a machine that went away) never reaches
    the end of its stream, so no result event was ever emitted; and
  * a **completed** run — exit 0, work done, PR opened — whose captured stream
    lost its result event anyway. Cause unknown and not reproducible
    (`self/BACKLOG.md`); it is what recorded three merged reviews at $0. Its
    sidecar says `outcome: "complete"` and `result_event: "missing"`.

Nothing here is gated on `outcome`, and that is deliberate: a null
`total_cost_usd` with a `session_id` beside it is the whole precondition, and
the completed case needs recovery exactly as much as the killed one.

The runner records `session_id` for every attempt either way, and that session's
transcript survives under `~/.claude/projects/` with every token it actually
spent. This script prices those tokens straight from the transcript and writes
the result onto the attempt as `recovered_cost_usd` — never onto
`total_cost_usd`, which must stay distinguishable as the CLI's own figure.

The same transcript bounds the run: an attempt with no `duration_ms` gets a
`recovered_duration_s`, the seconds between the transcript's first and last
timestamped lines. It is a **lower bound**, not a wall clock — it includes the
model's own waiting and excludes whatever the runner did around the call — and
`report.py` renders it as one, under its own mark, never in the column a
measured figure would occupy. `duration_ms` itself is left null forever, for the
reason `total_cost_usd` is.

Tokens are summed from the transcript's own `usage.cache_creation.ephemeral_
{5m,1h}_input_tokens` split, not from a `usage.json`'s flat
`cache_creation_input_tokens` total, which cannot tell a 1.25x 5-minute cache
write from a 2x 1-hour one.

Idempotent: an attempt that already carries `recovered_cost_usd` is skipped
unless `--force`.

Usage:
    python3 agentTooling/analysis/recover_attempts.py [--self] [--force] [--for <slug>]

`--for <slug>` restricts the walk to one feature directory — what
`feature-close.sh` runs just before it captures, so a feature is priced at the
moment it is closed rather than at the next weekly sweep. Without it the whole
tree is walked, which is what `sweep.sh` calls and must stay unchanged.
"""

from __future__ import annotations

import argparse
import glob
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from pricing import compute_cost
from roots import add_self_flag, features_root
from transcript import add_usage, iter_billable_messages, to_utc

# How many timestamped lines a transcript needs before its span means anything. One line
# gives an instant, not a duration; the difference between "the run took no time" and
# "there is nothing to measure" is exactly what a recovered figure must not blur.
MIN_MOMENTS_FOR_SPAN = 2


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
    """Price one session's transcript and bound its run. Returns the fields to write
    onto the attempt, or None if no transcript for this session survives.

    `recovered_duration_s` is absent from the returned dict when the transcript holds
    fewer than MIN_MOMENTS_FOR_SPAN timestamped lines, so an attempt never gains the key
    with nothing behind it."""
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

    # The same instants, used a second way: their span is the lower bound on how long the
    # run took, which is the one thing a transcript can say about a null `duration_ms`.
    # Over every timestamped line, not only the ones iter_billable_messages yields — a
    # session's last assistant response is not its last instant, and the span is meant to
    # bound the run rather than the billing.
    #
    # Fewer than two instants is not a zero-length run, it is nothing to measure, and
    # `0.0` beside a real dollar figure would read as "this took no time" — the same
    # argument the sidecar's null duration_ms makes. Write nothing.
    recovered_duration_s = (
        (max(moments) - min(moments)).total_seconds()
        if len(moments) >= MIN_MOMENTS_FOR_SPAN
        else None
    )

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
    if recovered_duration_s is not None:
        result["recovered_duration_s"] = recovered_duration_s
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
    # Named `--for`, not `--slug`, to read the way feature-close.sh calls it. It is a
    # prefix of `--force`, so before this existed `--for <slug>` was silently parsed as
    # `--force` plus a stray positional; an exact match wins in argparse, so adding it
    # takes that spelling back. `--forc` still abbreviates `--force`; `--fo` is now
    # ambiguous and rejected, which is the honest answer.
    parser.add_argument(
        "--for",
        dest="feature",
        metavar="SLUG",
        help="restrict the walk to one feature directory (feature-close.sh passes this; "
        "sweep.sh passes nothing and walks the whole tree)",
    )
    add_self_flag(parser)
    args = parser.parse_args()

    features_dir = features_root(args.self_mode)
    if args.feature:
        features_dir = features_dir / args.feature
        if not features_dir.is_dir():
            # A refusal, not an empty walk: a typo would otherwise report "0 attempts
            # recovered" — indistinguishable from a feature that had nothing to recover,
            # and the close above would take it for a clean pass.
            print(
                f"no feature directory at {features_dir}; nothing recovered",
                file=sys.stderr,
            )
            return 2

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
            # The same convenience sum for the spans, kept in step with attempts[] by the
            # same walk — and written only when some attempt HAS one. A sum over an empty
            # list is 0.0, and a top-level `recovered_duration_s: 0.0` beside a real
            # recovered dollar figure reads as a run that took no time; every attempt's
            # transcript being one line long is the ordinary way to reach that. Like the
            # dollars, this is a convenience: report.py reads the durable attempts[]
            # figures, because write_usage_sidecar's fixed-key rebuild drops the top level.
            spans = [
                a["recovered_duration_s"]
                for a in attempts
                if a.get("recovered_duration_s") is not None
            ]
            if spans:
                data["recovered_duration_s"] = sum(spans)
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
    # main() returns a non-zero code for a --for that names no feature; every other
    # path returns None, which SystemExit reads as 0. An unrecoverable transcript is
    # reported and still exits 0 — it is news, not a failure.
    raise SystemExit(main())
