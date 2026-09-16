#!/usr/bin/env python3
"""Derive a router session's routing record, and say which sessions are routers.

A **router** is the session that runs `feature-start.sh`. Under the rule in
`self/DESIGN-2026-09-16-lifecycle-restructure.md` §2 it is never pinned into a feature's
manifest: one coordinator session per feature, launched in that feature's worktree, and
the session that opened the feature is overhead of its own kind. Its spend is reported
as routing overhead (§3.4), per repo, never attributed to or split across features.

The link from router to feature is this record, written by `feature-start.sh` into
`plans/routing/<session-id>.json` (`self/routing/` under `--self`) and committed in the
`S: start` commit — so the link is in git before any transcript can expire.

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
format, timestamps truncated to the second. That is what lets two feature branches each
refresh the same router's record without conflicting *when the router has not grown in
between* — two starts by one router do differ, and their branches are an add/add conflict
whose resolution is the side with the later `captured_at`, the superset (design §3.4) —
and it is why `captured_at` is
*derived* (the transcript's last instant) rather than taken from the wall clock: a
wall-clock stamp would make every refresh a conflict. It answers "how current is this
record", which is the question a reader of a stale one asks, and it moves only when the
router itself grows.

**Nothing here imports `capture_planning`** — that module imports *this* one, for router
detection in `--list-sessions --unclaimed`, so the dependency can only run one way. A
session's transcript is located by globbing `~/.claude/projects/*/<session-id>.jsonl`,
the way `recover_attempts.py` already does and for the same reason: session ids are
unique, so no project-directory name has to be reconstructed. `cwd` and `gitBranch` are
read off the lines rather than off a directory name.

A missing transcript is never a refusal: the record is written with the current slug,
null figures, and one warning on stderr. `feature-start.sh` must not fail because a
transcript has not been flushed or has aged out.

Usage: python3 agentTooling/analysis/routing.py [--self] --session ID --slug SLUG \\
           [--primary DIR]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from pricing import compute_cost
from roots import add_self_flag, features_root
from transcript import add_usage, iter_billable_messages, to_utc

# Where the records live, beside the feature corpus rather than inside it: a router is
# not a feature, and `capture_planning.feature_slugs` walks every directory under the
# features root. `self/routing/` under --self, `plans/routing/` otherwise, derived from
# the features root so the two modes cannot drift apart.
ROUTING_DIR_NAME = "routing"
RECORD_SUFFIX = ".json"

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
# MULTILINE because a Bash tool call is often several lines, each its own command.
COMMAND_POSITION_RE = re.compile(
    r"(?:^|[;|&])[ \t]*(?:bash[ \t]+)?(?:[^\s;|&]*/)?"
    + FEATURE_START_SCRIPT.replace(".", r"\.")
    + r"(?=[\s;|&]|$)",
    re.MULTILINE,
)
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


def routing_dir(features_dir):
    """`<corpus>/routing/` for the corpus whose features are at `features_dir`."""
    return Path(features_dir).parent / ROUTING_DIR_NAME


def record_path(features_dir, session_id):
    return routing_dir(features_dir) / (session_id + RECORD_SUFFIX)


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


def slug_of_start_command(command):
    """The slug a `feature-start.sh` command names, or None when it is not one.

    The script token is found by `COMMAND_POSITION_RE`, so only a command that *runs*
    `feature-start.sh` counts — a `grep`, a `diff` or a `cat` that merely names the file
    is not a start. Past it the tokens are read positionally: `--self` and the other bare
    flags are dropped, a value-taking flag takes the token after it, a separator ends the
    command, and the first token left is the slug. Anything that is not a slug by
    `feature-start.sh`'s own pattern yields None — a record must never invent a feature
    name.
    """
    match = COMMAND_POSITION_RE.search(command)
    if match is None:
        return None
    rest = command[match.end():].split()
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


def write_record(features_dir, record):
    path = record_path(features_dir, record["session_id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(serialize(record))
    return path


def load_records(features_dir):
    """Every routing record of one corpus, sorted by session id. Read-only, and quiet
    about a file that will not parse — a report must not fail on one bad record."""
    directory = routing_dir(features_dir)
    if not directory.is_dir():
        return []
    records = []
    for path in sorted(directory.glob("*" + RECORD_SUFFIX)):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and data.get("session_id"):
            records.append(data)
    return records


def started_slugs(record):
    return [entry.get("slug") for entry in record.get("features_started") or [] if entry.get("slug")]


def routers_of(features_dir, slug):
    """Every routing record naming `slug` — the "routed by" lookup, design §3.4: the
    router owns the list, and a feature that wants to know scans for its own name rather
    than carrying a second copy in its fence."""
    return [record for record in load_records(features_dir) if slug in started_slugs(record)]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    add_self_flag(parser)
    parser.add_argument("--session", required=True, metavar="ID",
                        help="the router session's id — $CLAUDE_CODE_SESSION_ID")
    parser.add_argument("--slug", required=True,
                        help="the feature being started now, unioned into features_started")
    parser.add_argument("--primary", metavar="DIR",
                        help="the primary checkout, used for launched_in when the "
                             "transcript cannot be read")
    args = parser.parse_args()

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
    path = write_record(features_root(args.self_mode), record)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
