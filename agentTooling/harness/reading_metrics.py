#!/usr/bin/env python3
"""Count what a cell's method sessions read before their first edit.

    python3 harness/reading_metrics.py <analysis-dir> <tree> --from <ts> --to <ts>
                                       [--projects-root <dir>]

Prints ONE line, a JSON object (sorted keys) with `read_files_before_edit`,
`read_bytes_before_edit`, `readme_bytes_read` and `transcripts`.

The window. Every `*.jsonl` directly in the tree's project directory (named by exact
match from the tree path, so a sibling whose name merely contains it is not read), and
each one's subagent transcripts, is read; a line counts when `to_utc(line["timestamp"])`
is inside `[--from, --to]`, both inclusive. `transcripts` is how many files contributed
at least one counted line. Counted lines are ordered by (instant, file order, line
order), files in sorted path order with each session's subagents after it.

The first edit is the instant of the earliest counted `tool_use` whose `name` is in
`EDIT_TOOLS`. With none, every read in the window is "before the first edit".

A read is a `Read` `tool_use` whose `tool_result` (matched by `tool_use_id`) is counted
and not `is_error`. Its bytes are the UTF-8 length of the result's text: the string
itself, or the concatenated `text` of its `text` blocks (other blocks add 0). A read is
before the first edit when its `tool_use` instant is earlier than the first edit's.

`read_files_before_edit` is the distinct `input.file_path` values among reads before the
first edit. `read_bytes_before_edit` is the sum of those reads' bytes, repeats included.
`readme_bytes_read` is the bytes of every read in the window, before or after the first
edit, whose `file_path` basename is exactly `README.md`.

No transcript (no project directory, or no counted line): the three figures are `null`
and `transcripts` is `0` -- the row then says "not measured", never 0.

The analysis modules are the DRIVER's copy, imported by path from `<analysis-dir>`.
Exit codes: 0 a line was printed, 2 usage error (no `capture_planning.py` in the
analysis directory, unparseable `--from` / `--to`).
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Output keys -- the ledger row's field names (harness/README.md -> "The ledger row")
FILES_BEFORE_EDIT_KEY = "read_files_before_edit"
BYTES_BEFORE_EDIT_KEY = "read_bytes_before_edit"
README_BYTES_KEY = "readme_bytes_read"
TRANSCRIPTS_KEY = "transcripts"

# What counts as reading and as editing
READ_TOOL = "Read"
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
README_NAME = "README.md"
TEXT_ENCODING = "utf-8"

# Transcript layout and shapes
DEFAULT_PROJECTS_ROOT = "~/.claude/projects"
SESSION_GLOB = "*.jsonl"
ANALYSIS_ENTRY = "capture_planning.py"
TYPE_ASSISTANT = "assistant"
TYPE_USER = "user"
BLOCK_TOOL_USE = "tool_use"
BLOCK_TOOL_RESULT = "tool_result"
BLOCK_TEXT = "text"

# Exit codes
EXIT_OK = 0
EXIT_USAGE = 2


def content_blocks(line):
    """The list of content blocks of a transcript line, or [] when it has none."""
    message = line.get("message")
    if not isinstance(message, dict):
        return []
    content = message.get("content")
    if not isinstance(content, list):
        return []
    return [block for block in content if isinstance(block, dict)]


def result_bytes(content):
    """UTF-8 length of a tool_result's text (string, or its `text` blocks)."""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        text = "".join(
            block.get("text", "") for block in content
            if isinstance(block, dict) and block.get("type") == BLOCK_TEXT
            and isinstance(block.get("text"), str))
    else:
        text = ""
    return len(text.encode(TEXT_ENCODING))


def reading_figures(events):
    """(files_before_edit, bytes_before_edit, readme_bytes) over ordered counted lines.

    `events` is a list of (instant, line) in counted order.
    """
    first_edit = None
    reads = []  # (instant, file_path, tool_use_id)
    results = {}  # tool_use_id -> bytes, for results that are not errors
    for instant, line in events:
        for block in content_blocks(line):
            kind = block.get("type")
            if kind == BLOCK_TOOL_USE:
                name = block.get("name")
                if name in EDIT_TOOLS and first_edit is None:
                    first_edit = instant
                elif name == READ_TOOL:
                    tool_input = block.get("input")
                    path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
                    if isinstance(path, str) and block.get("id"):
                        reads.append((instant, path, block["id"]))
            elif kind == BLOCK_TOOL_RESULT and not block.get("is_error"):
                results.setdefault(block.get("tool_use_id"), result_bytes(block.get("content")))
    files = set()
    bytes_before = 0
    readme_bytes = 0
    for instant, path, tool_id in reads:
        if tool_id not in results:
            continue
        size = results[tool_id]
        if first_edit is None or instant < first_edit:
            files.add(path)
            bytes_before += size
        if os.path.basename(path) == README_NAME:
            readme_bytes += size
    return len(files), bytes_before, readme_bytes


def transcript_files(transcript_dir, subagent_transcript_paths):
    """Session files in sorted order, each followed by its subagents' transcripts."""
    ordered = []
    for session in sorted(transcript_dir.glob(SESSION_GLOB)):
        ordered.append(session)
        ordered.extend(Path(p) for p in subagent_transcript_paths(transcript_dir, session.stem))
    return ordered


def load_events(files, window_from, window_to, load_transcript_lines, to_utc):
    """Counted lines ordered by (instant, file order, line order); and contributing files."""
    keyed = []
    contributing = 0
    for file_order, path in enumerate(files):
        counted = 0
        for line_order, line in enumerate(load_transcript_lines(path)):
            if not isinstance(line, dict):
                continue
            instant = to_utc(line.get("timestamp"))
            if instant is None or not (window_from <= instant <= window_to):
                continue
            counted += 1
            keyed.append((instant, file_order, line_order, line))
        if counted:
            contributing += 1
    keyed.sort(key=lambda item: item[:3])
    return [(instant, line) for instant, _, _, line in keyed], contributing


def main(argv=None):
    parser = argparse.ArgumentParser(description="Reading metrics for a cell's method window.")
    parser.add_argument("analysis_dir", help="the driver's analysis/ directory")
    parser.add_argument("tree", help="the cell's worktree (the sessions' cwd)")
    parser.add_argument("--from", dest="window_from", required=True, help="window start (ISO 8601)")
    parser.add_argument("--to", dest="window_to", required=True, help="window end (ISO 8601)")
    parser.add_argument("--projects-root", default=DEFAULT_PROJECTS_ROOT,
                        help=f"transcript root (default {DEFAULT_PROJECTS_ROOT})")
    try:
        args = parser.parse_args(argv)
    except SystemExit as stop:
        return EXIT_USAGE if stop.code else EXIT_OK

    analysis_dir = Path(args.analysis_dir)
    if not (analysis_dir / ANALYSIS_ENTRY).is_file():
        print(f"usage error: no {ANALYSIS_ENTRY} in {analysis_dir}", file=sys.stderr)
        return EXIT_USAGE
    sys.path.insert(0, str(analysis_dir))
    from capture_planning import (
        load_transcript_lines, subagent_transcript_paths, transcript_dir_name)
    from transcript import to_utc

    window_from = to_utc(args.window_from)
    window_to = to_utc(args.window_to)
    if window_from is None or window_to is None:
        print(f"usage error: cannot parse --from {args.window_from!r} or --to {args.window_to!r}",
              file=sys.stderr)
        return EXIT_USAGE

    projects_root = Path(args.projects_root).expanduser()
    transcript_dir = projects_root / transcript_dir_name(args.tree)
    events, contributing = [], 0
    if transcript_dir.is_dir():
        files = transcript_files(transcript_dir, subagent_transcript_paths)
        events, contributing = load_events(
            files, window_from, window_to, load_transcript_lines, to_utc)

    if contributing:
        files_n, bytes_n, readme_n = reading_figures(events)
    else:
        files_n = bytes_n = readme_n = None
    print(json.dumps({
        FILES_BEFORE_EDIT_KEY: files_n,
        BYTES_BEFORE_EDIT_KEY: bytes_n,
        README_BYTES_KEY: readme_n,
        TRANSCRIPTS_KEY: contributing,
    }, sort_keys=True))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
