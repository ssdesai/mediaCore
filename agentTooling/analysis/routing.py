#!/usr/bin/env python3
"""Derive a router session's routing record, and say which sessions are routers.

A **router** is the session that runs `feature-start.sh`. Under the rule in
`self/DESIGN-2026-09-16-lifecycle-restructure.md` §2 it is never pinned into a feature's
manifest: one coordinator session per feature, launched in that feature's worktree, and
the session that opened the feature is overhead of its own kind. Its spend is reported
as routing overhead (§3.4), per repo, never attributed to or split across features.

The link from router to feature is this record, written by `feature-start.sh` into the
feature directory it links — `plans/features/<slug>/routing.json` (`self/features/`
under `--self`) — and committed in the `S: start` commit, so the link is in git before
any transcript can expire.

**A record of a link lives in the feature it links** (`self/DESIGN-2026-09-18-ledger-and-routing.md`
§1). A router that starts three features leaves three copies, each derived from the same
transcript at its own `captured_at`; no two features ever write one path, so two branches
cut from the same `main` cannot conflict, and a reader that wants one row per router keeps
the copy with the latest `captured_at` (`load_records`). Records written under the old
rule — one shared `<corpus>/routing/<session-id>.json` — are moved by `--migrate`.

    {
      "captured_at":      the instant the content is current as of (see below),
      "cost_usd":         the whole session priced through pricing.compute_cost,
      "duration_s":       whole seconds from its first to its last timestamped line,
      "ended_at":         that last instant,
      "features_started": [{"slug": ..., "at": ...}, ...] in the order they were started,
      "git_branch":       the transcript's gitBranch,
      "launched_in":      the transcript's cwd,
      "model":            the models the session billed, "/"-joined,
      "session_id":       the router's own id,
      "started_at":       its first instant
    }

**The output is byte-identical for identical input** — sorted keys, a fixed float
format, timestamps truncated to the second — and `captured_at` is *derived* (the
transcript's last instant) rather than taken from the wall clock, so a refresh that finds
the router unchanged rewrites the same bytes and shows up in no diff. It answers "how
current is this record", which is the question a reader of a stale one asks, it moves only
when the router itself grows, and it is what `load_records` ranks one router's copies by.

**Nothing here imports `capture_planning`** — that module imports *this* one, for router
detection in `--list-sessions --unclaimed`, so the dependency can only run one way. A
session's transcript is located by globbing `~/.claude/projects/*/<session-id>.jsonl`,
the way `recover_attempts.py` already does and for the same reason: session ids are
unique, so no project-directory name has to be reconstructed. `cwd` and `gitBranch` are
read off the lines rather than off a directory name.

A missing transcript is never a refusal: the record is written with the current slug,
null figures, and one warning on stderr. `feature-start.sh` must not fail because a
transcript has not been flushed or has aged out.

`feature-capture.sh` refreshes it (`--refresh-for <slug>`): the record of the feature it
captures, and only that one, is re-derived from its router's transcript as it stands then,
keeping the prior record's slugs the transcript never carried, and rides the capture
commit. Another feature's copy of the same router's record is not this capture's to write.
A record whose transcript has aged out is left as it is.

Usage: python3 agentTooling/analysis/routing.py [--self] --session ID --slug SLUG \\
           [--primary DIR]
       python3 agentTooling/analysis/routing.py [--self] --refresh-for SLUG
       python3 agentTooling/analysis/routing.py [--self] --migrate
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from pricing import compute_cost
from roots import add_self_flag, features_root
from transcript import add_usage, iter_billable_messages, to_utc

# Where a record lives: inside the feature directory it links, one copy per feature, so
# that no two features ever write one path. `capture_planning.feature_slugs` walks the
# features root by `README.md`, so a file beside a manifest is not a feature of its own.
RECORD_NAME = "routing.json"

# Where records written before design 2026-09-18 §1 live — one shared file per router,
# beside the features root (`self/routing/` under --self, `plans/routing/` otherwise) —
# and what one is named. Read by `--migrate` and by nothing else: there is one location
# for a record now, and one reader of it.
LEGACY_DIR_NAME = "routing"
LEGACY_RECORD_SUFFIX = ".json"

# Every field of the record, in the order the docstring lists them. Written sorted, so
# this tuple is the documentation and the serializer's contract, not its key order.
RECORD_FIELDS = (
    "captured_at", "cost_usd", "duration_s", "ended_at", "features_started",
    "git_branch", "launched_in", "model", "session_id", "started_at",
)
FEATURE_STARTED_FIELDS = ("slug", "at")

# Serialization: sorted keys and a fixed float precision, so two runs over one transcript
# produce the same bytes. Six decimals is well under a cent and past any figure a report
# renders.
JSON_INDENT = 2
COST_DECIMALS = 6
TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
MODEL_JOIN = "/"

# Where transcripts live. `Path.home()` and nothing narrower, exactly as
# `capture_planning.claims_ledger_path` argues: a test redirects `$HOME` and moves the
# transcripts with it.
PROJECTS_REL = (".claude", "projects")
TRANSCRIPT_SUFFIX = ".jsonl"

# Reading a router's own history out of its transcript. A Bash tool call is an
# `assistant` line whose message content holds a `tool_use` block named `Bash`, with the
# command under `input.command`.
ASSISTANT_TYPE = "assistant"
TOOL_USE_TYPE = "tool_use"
BASH_TOOL_NAME = "Bash"
COMMAND_KEY = "command"
# The script whose calls name the features this session started, matched on its basename
# so `./feature-start.sh`, `../agentTooling/feature-start.sh` and an absolute path all
# count. The slug is the first positional after it.
FEATURE_START_SCRIPT = "feature-start.sh"
# ...but only where the script is RUN: the first word of a simple command — at the start
# of a line or after `&&`, `||`, `;`, `|` or `&` — optionally preceded by `bash`, with any
# directory prefix. Matching the name anywhere on the line read `grep -n foo
# feature-start.sh hooks` as a start whose slug was `hooks`, which turned an ordinary
# maintenance session on `main` into a router and dropped it out of `--list-sessions
# --unclaimed` — the one listing whose job is to surface cost nobody has claimed.
#
# Matched against ONE LINE at a time, which is why it carries no `re.MULTILINE`. A Bash
# tool call is often several commands, one per line, and under a multiline match the
# regex landed on one line while the argument scan that followed it ran on into the next:
# `./feature-start.sh --self` with `ls` under it recorded a feature named `ls`
# (self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §2).
COMMAND_POSITION_RE = re.compile(
    r"(?:^|[;|&])[ \t]*(?:bash[ \t]+)?(?:[^\s;|&]*/)?"
    + FEATURE_START_SCRIPT.replace(".", r"\.")
    + r"(?=[\s;|&]|$)",
)
# A backslash at the end of a line continues the command onto the next one, so the two
# lines are one command and a start split that way carries its slug on the far side of
# the break. Joined before anything is matched, since from there on a match is per line.
# Both spellings, because a transcript may carry CRLF.
LINE_CONTINUATIONS = ("\\\r\n", "\\\n")
LINE_BREAK_RE = re.compile(r"[\r\n]")
# Tokens that end the command the match started: whatever follows one of these belongs to
# the next command, not to this start's argument list.
COMMAND_SEPARATORS = frozenset(["&&", "||", ";", "|", "&"])
# Flags `feature-start.sh` accepts, so the slug is not read off one of their values.
START_VALUE_FLAGS = frozenset(["--method", "--base", "--session"])
START_BARE_FLAGS = frozenset(["--self", "--no-gate", "--no-pin", "--pin", "--open"])
FLAG_PREFIX = "-"
# The slug pattern feature-start.sh itself refuses on; a token that fails it is not a
# slug, and a record must not invent one.
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Router detection (design §3.4): launched in the primary checkout — not in one of its
# worktrees — on `main`, with at least one `feature-start.sh` call in the transcript.
# Everything else on `main` keeps its place in the unclaimed listing.
ROUTER_BRANCH = "main"

WARN_PREFIX = "WARN:"
USAGE_RC = 2

# The floor a record with no readable `captured_at` ranks at — a record that cannot say
# how current it is loses to one that can, and two of them keep their path order.
UNDATED = datetime.min.replace(tzinfo=timezone.utc)

# What `--migrate` prints, one line per decision, so a human reading a `sync-plans.sh`
# run knows exactly what to commit and what was left alone.
MIGRATE_MOVED = "moved  {source} -> {target}"
MIGRATE_SKIPPED_ABSENT = (
    "skipped {source} -> {slug}: no feature directory under {features_dir} — a record is "
    "never a reason to create one"
)
MIGRATE_SKIPPED_NEWER = (
    "skipped {source} -> {target}: it already holds a record captured at {captured} or "
    "later"
)
MIGRATE_REMOVED = "removed {source}"
MIGRATE_KEPT_ORPHAN = (
    "kept   {source}: no feature directory for any slug it names ({slugs}) — deleting it "
    "would destroy the only copy of that record"
)
MIGRATE_KEPT_UNREADABLE = "kept   {source}: not a routing record — left for a human"
MIGRATE_REMOVED_DIR = "removed {directory} — the legacy routing directory is empty"


def record_path(features_dir, slug):
    """`<features root>/<slug>/routing.json` — the record of the feature `slug`."""
    return Path(features_dir) / slug / RECORD_NAME


def legacy_routing_dir(features_dir):
    """`<corpus>/routing/` — where records lived before design 2026-09-18 §1."""
    return Path(features_dir).parent / LEGACY_DIR_NAME


def projects_root():
    return Path.home().joinpath(*PROJECTS_REL)


def find_transcript(session_id):
    """The transcript of one top-level session, or None.

    A filename glob across every project directory, not a lookup by launch directory:
    session ids are unique, and the router may have been launched in a directory this
    checkout cannot reconstruct. `recover_attempts.py` makes the same argument.
    """
    root = projects_root()
    if not root.is_dir():
        return None
    hits = sorted(root.glob("*/" + session_id + TRANSCRIPT_SUFFIX))
    return hits[0] if hits else None


def load_lines(path):
    """Each non-blank line parsed as JSON, skipping one that does not parse."""
    lines = []
    try:
        with open(path, "r") as handle:
            for raw in handle:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    lines.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue
    except OSError:
        return []
    return lines


def first_value(lines, key):
    """The first non-empty value of `key` across the lines, or None."""
    for line in lines:
        value = line.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def bash_commands(lines):
    """(command, timestamp) for every Bash tool call in file order."""
    calls = []
    for line in lines:
        if line.get("type") != ASSISTANT_TYPE:
            continue
        content = (line.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != TOOL_USE_TYPE:
                continue
            if block.get("name") != BASH_TOOL_NAME:
                continue
            command = (block.get("input") or {}).get(COMMAND_KEY)
            if isinstance(command, str) and command:
                calls.append((command, line.get("timestamp")))
    return calls


def slug_of_start_line(line):
    """The slug a single LINE's `feature-start.sh` call names, or None.

    The script token is found by `COMMAND_POSITION_RE`, so only a line that *runs*
    `feature-start.sh` counts — a `grep`, a `diff` or a `cat` that merely names the file
    is not a start. Past it the tokens are read positionally: `--self` and the other bare
    flags are dropped, a value-taking flag takes the token after it, a separator ends the
    command, and the first token left is the slug. Anything that is not a slug by
    `feature-start.sh`'s own pattern yields None — a record must never invent a feature
    name. A line whose start has no argument at all yields None for the same reason: the
    tokens run out and there is nothing to read.
    """
    match = COMMAND_POSITION_RE.search(line)
    if match is None:
        return None
    rest = line[match.end():].split()
    position = 0
    while position < len(rest):
        word = rest[position]
        if word in COMMAND_SEPARATORS:
            return None
        if word in START_VALUE_FLAGS:
            position += 2
            continue
        if word in START_BARE_FLAGS or word.startswith(FLAG_PREFIX):
            position += 1
            continue
        return word if SLUG_RE.match(word) else None
    return None


def slug_of_start_command(command):
    """The slug a `feature-start.sh` command names, or None when it is not one.

    **The slug is on the start's own line** (design 2026-09-18 §2). A Bash tool call is
    usually several commands, one per line, so the text is first joined at its
    `\\`-newline continuations — which really are one command — and then read a line at a
    time. Before that, `re.MULTILINE` let the script token match on one line while the
    positional scan ran past the break into the next, which went wrong both ways: a start
    with no slug on its line took the following line's first word (`./feature-start.sh
    --self` above `ls` recorded a feature named `ls`, and turned an ordinary maintenance
    session into a router), and a start continued with a trailing `\\` found no slug at
    all, so that router was never recorded as one.

    Several lines may run the script; the first that names a slug wins. A slugless start
    is not an answer — it names no feature — so the scan passes over it and keeps looking
    for one that does, but only at another line that RUNS the script, never at an
    arbitrary word.
    """
    joined = command
    for continuation in LINE_CONTINUATIONS:
        joined = joined.replace(continuation, "")
    for line in LINE_BREAK_RE.split(joined):
        slug = slug_of_start_line(line)
        if slug is not None:
            return slug
    return None


def feature_start_slugs(lines):
    """[(slug, timestamp)] for every `feature-start.sh <slug>` call, in order, the first
    occurrence of each slug kept. A re-run of the same start is one feature, not two."""
    found = []
    seen = set()
    for command, timestamp in bash_commands(lines):
        slug = slug_of_start_command(command)
        if slug is None or slug in seen:
            continue
        seen.add(slug)
        found.append((slug, timestamp))
    return found


def is_router_lines(lines, primary):
    """Whether these transcript lines are a router's: launched in the primary checkout
    itself (a worktree is somebody's coordinator, not a router), on `main`, with at least
    one `feature-start.sh` call at command position (`COMMAND_POSITION_RE`) — a command
    that only names the script is not a start."""
    if first_value(lines, "cwd") != str(primary):
        return False
    if first_value(lines, "gitBranch") != ROUTER_BRANCH:
        return False
    return bool(feature_start_slugs(lines))


def moments_of(lines):
    """Every parseable instant in the transcript, in no particular order."""
    return [
        moment
        for moment in (to_utc(line.get("timestamp")) for line in lines)
        if moment is not None
    ]


def iso_or_none(moment):
    """An instant as ISO 8601 UTC with a `Z`, truncated to the second — the resolution
    every bound in both corpora is written at, and what keeps two writes identical."""
    return moment.strftime(TIMESTAMP_FORMAT) if moment is not None else None


def price_lines(lines, as_of):
    """(cost_usd, "/"-joined models) over a transcript's billable responses, or
    (None, None) when nothing in it is billable. Priced exactly as
    `capture_planning.list_sessions` prices a session: per model, on the session's own
    date, through `pricing.compute_cost`."""
    totals = {}
    for model, usage, _ in iter_billable_messages(lines):
        add_usage(totals, model, usage)
    if not totals:
        return None, None
    cost = 0.0
    for model in sorted(totals):
        priced, _ = compute_cost(model, totals[model], as_of=as_of)
        cost += priced or 0.0
    return round(cost, COST_DECIMALS), MODEL_JOIN.join(sorted(totals))


def build_record(session_id, slug, lines, primary=None):
    """The whole record for one router, derived from its transcript lines.

    `slug` — the feature being started now — is unioned into `features_started`: the tool
    call that is running this very moment may not have reached the transcript yet, and a
    record that omitted the feature it was written for would name nothing at all on a
    router's first start. It carries the transcript's instant when the call *has* flushed
    and a null `at` when it has not.
    """
    started = feature_start_slugs(lines)
    if slug is not None and slug not in [name for name, _ in started]:
        started.append((slug, None))
    moments = moments_of(lines)
    first = min(moments) if moments else None
    last = max(moments) if moments else None
    cost, model = (None, None)
    if first is not None:
        cost, model = price_lines(lines, as_of=first.date().isoformat())
    return {
        "captured_at": iso_or_none(last),
        "cost_usd": cost,
        "duration_s": int((last - first).total_seconds()) if first and last else None,
        "ended_at": iso_or_none(last),
        "features_started": [
            {"slug": name, "at": iso_or_none(to_utc(at))} for name, at in started
        ],
        "git_branch": first_value(lines, "gitBranch"),
        "launched_in": first_value(lines, "cwd") or (str(primary) if primary else None),
        "model": model,
        "session_id": session_id,
        "started_at": iso_or_none(first),
    }


def serialize(record):
    """The record's bytes: sorted keys, two-space indent, one trailing newline. The one
    place the byte-identity contract is implemented."""
    return json.dumps(record, indent=JSON_INDENT, sort_keys=True) + "\n"


def write_record(features_dir, slug, record):
    """Write `record` as the routing record of the feature `slug`.

    The parent is created when it is absent, which is the start's own case: the record is
    written moments after `manifest.py init` made the directory, and a start must not fail
    on the order of two writes. `--migrate` is the opposite case and creates nothing (see
    `migrate`): there the missing directory means the feature is not in this corpus.
    """
    path = record_path(features_dir, slug)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(serialize(record))
    return path


def read_record(path):
    """One record read off disk, or None — unreadable, unparseable, or not a record.
    Quiet about all three: a report must not fail on one bad file."""
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if isinstance(data, dict) and data.get("session_id"):
        return data
    return None


def record_rank(record):
    """How two copies of ONE router's record are ordered: by `captured_at`, and then by
    how many features they name.

    The instant is the rule (design 2026-09-18 §1) — a router only grows, so the later
    capture's `features_started` is a superset of the earlier one's, and taking the older
    copy would drop a feature out of the Routing table with nothing to restore it. The
    count breaks a tie, which is the case of two copies written from one transcript in the
    same second: the start that had already flushed is in both, the one still running is
    in only the copy written for it, and more is again the later read of that instant.
    """
    captured = to_utc(record.get("captured_at"))
    return (captured or UNDATED, len(record.get("features_started") or []))


def load_records(features_dir):
    """One routing record per router across a corpus, sorted by session id.

    Every feature keeps its own copy (`<slug>/routing.json`), so one router that started
    three features is on disk three times; the copy with the latest `captured_at` wins
    (`record_rank`) and the others are dropped. That is the rule a human used to apply by
    hand at an add/add conflict, written once, here, rather than at each renderer.
    """
    latest = {}
    for path in sorted(Path(features_dir).glob("*/" + RECORD_NAME)):
        record = read_record(path)
        if record is None:
            continue
        held = latest.get(record["session_id"])
        if held is None or record_rank(record) > record_rank(held):
            latest[record["session_id"]] = record
    return [latest[session_id] for session_id in sorted(latest)]


def started_slugs(record):
    return [entry.get("slug") for entry in record.get("features_started") or [] if entry.get("slug")]


def routers_of(features_dir, slug):
    """The routing record of one feature — the "routed by" lookup (design 2026-09-16
    §3.4), one file and nothing else.

    A list of at most one, because a feature has exactly one router and may have none (it
    was started before this rule, or by a shell rather than by a session). It stayed a list
    when the record moved into the feature: `report.render_routed_by` and
    `refresh_for` both read it as one, and the empty case is the one that carries meaning.
    """
    record = read_record(record_path(features_dir, slug))
    return [record] if record is not None else []


def refresh_record(record, lines):
    """A router's record re-derived from its transcript as it stands now, keeping every
    entry of the prior `record` the transcript does not carry.

    What the transcript cannot supply is exactly the slug each start was written for: the
    start's own tool call had not flushed when `build_record` ran, so it went in with a
    null `at`, and a transcript read later may still lack it. Re-deriving from the
    transcript alone would drop it — and with it that feature's "routed by" line — so the
    prior entries are unioned in, in their prior order, after the transcript's own, and an
    entry the transcript now dates takes the transcript's instant. Deterministic in its
    inputs, like `build_record`, so a second refresh writes the same bytes.
    """
    fresh = build_record(record["session_id"], None, lines)
    known = [entry["slug"] for entry in fresh["features_started"]]
    for entry in record.get("features_started") or []:
        if entry.get("slug") and entry["slug"] not in known:
            fresh["features_started"].append(
                {"slug": entry["slug"], "at": entry.get("at")}
            )
            known.append(entry["slug"])
    if fresh["launched_in"] is None:
        fresh["launched_in"] = record.get("launched_in")
    return fresh


def refresh_for(features_dir, slug):
    """Rewrite this feature's own routing record (`routers_of`) from its router's
    transcript — what `feature-capture.sh` runs, so the record that rides a feature's PR
    is as current as the capture beside it (design 2026-09-16 §3.2 step 4). Returns
    `(paths rewritten, warnings)`. **Only this feature's copy**: another feature's copy of
    the same router's record belongs to that feature's own capture, and writing it here
    would put a file this run has no claim on into this branch's cost commit. A record
    whose transcript is gone is left exactly as it is: a record written while the
    transcript existed is the better one, and the transcript will not come back."""
    rewritten, warnings = [], []
    for record in routers_of(features_dir, slug):
        transcript = find_transcript(record["session_id"])
        lines = load_lines(transcript) if transcript is not None else []
        if not lines:
            warnings.append(
                f"{WARN_PREFIX} no transcript for router {record['session_id']} under "
                f"{projects_root()} — its routing record is left as it is"
            )
            continue
        rewritten.append(write_record(features_dir, slug, refresh_record(record, lines)))
    return rewritten, warnings


def migrate(features_dir):
    """Empty the legacy `<corpus>/routing/` into the features its records name.

    Each legacy record is copied verbatim into `<slug>/routing.json` for every slug its
    `features_started` names, and the legacy file is then deleted; the copies carry the
    whole record, so nothing about the router is lost by the move. Returns the lines to
    print, one per decision. Idempotent — a second run finds no legacy file, prints
    nothing and writes nothing — and nothing at all to do when the directory is absent,
    which is every corpus that never ran under the old rule.

    Three cases are not moves, and each says so rather than passing in silence:

    - **a slug with no feature directory here.** The feature never merged, or was
      deleted. The record is not written, and no directory is created to hold it: a
      directory under the features root with no manifest is a feature to every walker of
      that tree (`capture_planning.feature_slugs`, `report.py --all`), so inventing one
      would be inventing a feature. The router is named in the copies its other slugs
      received, `features_started` and all, so the fact that it started that slug survives
      wherever anything about it survives at all.
    - **a target that already holds a record captured as late or later.** The feature's
      own capture has refreshed it since, and the legacy file is the stale side. It is
      skipped rather than overwritten — the same latest-wins rule `load_records` applies —
      and still counts as linked, since nothing is lost by deleting the older copy.
    - **a record none of whose slugs has a directory** (or that will not parse at all).
      The legacy file is KEPT. Deleting it would destroy the only copy of that record,
      which is the one thing a migration must not do; the line naming it is the standing
      notice, and a human decides.
    """
    features_dir = Path(features_dir)
    legacy = legacy_routing_dir(features_dir)
    lines = []
    if not legacy.is_dir():
        return lines
    for source in sorted(legacy.glob("*" + LEGACY_RECORD_SUFFIX)):
        record = read_record(source)
        if record is None:
            lines.append(MIGRATE_KEPT_UNREADABLE.format(source=source))
            continue
        slugs = started_slugs(record)
        linked = 0
        for slug in slugs:
            if not (features_dir / slug).is_dir():
                lines.append(MIGRATE_SKIPPED_ABSENT.format(
                    source=source, slug=slug, features_dir=features_dir))
                continue
            target = record_path(features_dir, slug)
            held = read_record(target)
            if held is not None and record_rank(held) >= record_rank(record):
                lines.append(MIGRATE_SKIPPED_NEWER.format(
                    source=source, target=target, captured=record.get("captured_at")))
                linked += 1
                continue
            write_record(features_dir, slug, record)
            lines.append(MIGRATE_MOVED.format(source=source, target=target))
            linked += 1
        if not linked:
            lines.append(MIGRATE_KEPT_ORPHAN.format(
                source=source, slugs=", ".join(slugs) or "none"))
            continue
        source.unlink()
        lines.append(MIGRATE_REMOVED.format(source=source))
    try:
        legacy.rmdir()
    except OSError:
        return lines
    lines.append(MIGRATE_REMOVED_DIR.format(directory=legacy))
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    add_self_flag(parser)
    parser.add_argument("--session", metavar="ID",
                        help="the router session's id — $CLAUDE_CODE_SESSION_ID")
    parser.add_argument("--slug",
                        help="the feature being started now, unioned into features_started")
    parser.add_argument("--primary", metavar="DIR",
                        help="the primary checkout, used for launched_in when the "
                             "transcript cannot be read")
    parser.add_argument("--refresh-for", metavar="SLUG", dest="refresh_for",
                        help="instead of writing one router's record, rewrite SLUG's own "
                             "record from its router's transcript, printing the path "
                             "rewritten — what feature-capture.sh runs")
    parser.add_argument("--migrate", action="store_true",
                        help="move every legacy <corpus>/routing/<id>.json into the "
                             "directory of each feature it names and delete it, printing "
                             "each move — what sync-plans.sh runs after a pull")
    args = parser.parse_args()

    if args.migrate:
        if args.session or args.slug or args.refresh_for:
            parser.error("--migrate takes no --session, --slug or --refresh-for")
        for line in migrate(features_root(args.self_mode)):
            print(line)
        return 0
    if args.refresh_for is not None:
        if args.session or args.slug:
            parser.error("--refresh-for takes no --session and no --slug")
        paths, warnings = refresh_for(features_root(args.self_mode), args.refresh_for)
        for warning in warnings:
            print(warning, file=sys.stderr)
        for path in paths:
            print(path)
        return 0
    if not (args.session and args.slug):
        parser.error(
            "--session and --slug are required unless --refresh-for or --migrate is given"
        )

    transcript = find_transcript(args.session)
    lines = load_lines(transcript) if transcript is not None else []
    if not lines:
        print(
            f"{WARN_PREFIX} no transcript for session {args.session} under "
            f"{projects_root()} — the routing record is written with {args.slug} and no "
            "figures",
            file=sys.stderr,
        )
    record = build_record(args.session, args.slug, lines, primary=args.primary)
    path = write_record(features_root(args.self_mode), args.slug, record)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
