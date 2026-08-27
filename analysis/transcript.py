"""Session-transcript parsing shared by `capture_planning.py` and `recover_attempts.py`.

Both consumers need the same two transcript-format facts: one API response is
written as several `assistant` lines, each repeating that response's `usage`
verbatim, so tokens must be summed once per response rather than once per line;
and a locally-generated `model: "<synthetic>"` notice carries no real usage and
must be skipped. Duplicating that dedup rule across two files is how it drifts,
so it lives here once.
"""

from __future__ import annotations

from datetime import datetime, timezone

# Claude Code writes locally-generated notices ("You've hit your session limit", API
# error banners) as `assistant` lines carrying this in place of a model id, with all
# usage counters zero. It is a marker, not a model: pricing it would report every
# affected feature's total as partial over tokens that do not exist.
SYNTHETIC_MODEL = "<synthetic>"


def to_utc(timestamp):
    """ISO 8601 timestamp -> an aware `datetime` in UTC, or None if unparseable.

    THE timestamp convention for every script here: an instant is compared, sorted and
    dated only after passing through this function. Timestamps reach us as strings from
    two sources that do not agree on shape — transcripts write UTC with a `Z`, while a
    `session_window` bound is typed by a human, often read off `git log`, which prints
    LOCAL time. Comparing those as strings is right only while every one of them happens
    to be same-shape UTC, and nothing enforced that.

    A value carrying no offset is interpreted as UTC rather than local. That is what the
    committed corpus already means — every `session_window` bound in it is naive and was
    written against a lexicographic comparison with `Z`-suffixed transcript timestamps —
    so reading them as local would silently move every existing window by the author's
    offset. An author who wants to write local time states the offset explicitly
    ("2026-07-17T18:00:00-04:00") and it is converted here.

    `Z` is normalized to `+00:00` because `datetime.fromisoformat` rejects it before
    Python 3.11, and these scripts are stdlib-only across whatever interpreter a
    consuming repo happens to have.
    """
    if not timestamp:
        return None
    text = timestamp.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def utc_date(timestamp):
    """ISO 8601 timestamp -> its UTC calendar date as "YYYY-MM-DD", or None.

    Not `timestamp[:10]`. That slice reads the date in whatever zone the string was
    written in, so "2026-07-01T23:00:00-04:00" slices to 2026-07-01 when the instant is
    2026-07-02 UTC. The pricing date selects the rate tier (`pricing.get_rates`), so a
    day off by one is a dollar error, not a display one: a session on the eve of an
    intro-rate window prices at the wrong tier in whichever direction the offset points.
    """
    parsed = to_utc(timestamp)
    return parsed.date().isoformat() if parsed else None


def iter_billable_messages(lines):
    """Yield (model, usage, is_sidechain) once per billable API response.

    One API response is written as several `assistant` lines, one per content
    block, each repeating that response's `usage` verbatim — summing per line
    measured 2.4x-2.8x over. Bill each response once, keyed on its API id. A
    line with no id cannot be de-duplicated; count it, since dropping it would
    under-bill. `model: "<synthetic>"` marks a locally-generated notice with
    all-zero usage and is skipped.
    """
    seen_message_ids = set()
    for line in lines:
        if line.get("type") != "assistant":
            continue
        message = line.get("message") or {}
        model = message.get("model")
        usage = message.get("usage")
        if not model or not usage or model == SYNTHETIC_MODEL:
            continue
        message_id = message.get("id")
        if message_id is not None:
            if message_id in seen_message_ids:
                continue
            seen_message_ids.add(message_id)
        yield model, usage, bool(line.get("isSidechain", False))


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
