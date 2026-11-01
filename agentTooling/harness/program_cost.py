#!/usr/bin/env python3
"""Price a program cell's orchestrator session(s) into one dollar figure.

    python3 harness/program_cost.py <analysis-dir> --session <id>[@<from-ts>] [--session ...]
                                    --from <ts> --to <ts> [--projects-root <dir>]

A program cell's `cost_overhead_usd` is what the orchestrator spent, priced inside
`[t_method_start, t_method_end]`. The pricing path is the DRIVER's analysis copy
(`<analysis-dir>/capture_planning.py`, `price_session_in_window`), not the arm's pinned
one: every arm is priced by the same rates and the same dating rule, which is what makes
the arms comparable. The module is imported by path, so `<analysis-dir>` is put on
`sys.path` explicitly rather than found by the interpreter.

An orchestrator is resumed once per feature, and a resume may fork into a new session id
that replays old history under old timestamps. Each `--session` therefore takes an
optional `@<from-ts>`: that id is priced from the instant of ITS first call, not from the
program's start, so replayed history is not counted twice. An id with no `@` uses
`--from`. Ids are priced separately and summed.

Prints ONE number on stdout: the summed `cost_usd.total` in dollars, four decimals
(`0.0000` when no transcript carries any id; each such id is named on stderr, as is each
id whose total is partial because a model had no rate). Exit codes: 0 a figure was
printed, 2 usage error (unreadable analysis directory, unparseable timestamp).
"""

import argparse
import sys
from pathlib import Path

# Exit codes
EXIT_OK = 0
EXIT_USAGE = 2

# Session spec: <id>[@<from-ts>]
FROM_SEPARATOR = "@"

# Output
COST_DECIMALS = 4


def parse_session(spec):
    """`<id>` or `<id>@<from-ts>` -> (id, from-ts or None)."""
    session_id, separator, from_ts = spec.partition(FROM_SEPARATOR)
    return session_id, (from_ts if separator and from_ts else None)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Price orchestrator sessions inside a window.")
    parser.add_argument("analysis_dir", help="the driver's analysis/ directory")
    parser.add_argument("--session", action="append", default=[], required=True,
                        help="session id, optionally <id>@<from-ts>; repeatable")
    parser.add_argument("--from", dest="window_from", required=True, help="window start (ISO 8601)")
    parser.add_argument("--to", dest="window_to", required=True, help="window end (ISO 8601)")
    parser.add_argument("--projects-root", default=None,
                        help="transcript root (default ~/.claude/projects)")
    try:
        args = parser.parse_args(argv)
    except SystemExit as stop:
        return EXIT_USAGE if stop.code else EXIT_OK

    analysis_dir = Path(args.analysis_dir)
    if not (analysis_dir / "capture_planning.py").is_file():
        print(f"usage error: no capture_planning.py in {analysis_dir}", file=sys.stderr)
        return EXIT_USAGE
    sys.path.insert(0, str(analysis_dir))
    from capture_planning import price_session_in_window
    from transcript import to_utc

    window_to = to_utc(args.window_to)
    if window_to is None:
        print(f"usage error: cannot parse --to {args.window_to!r}", file=sys.stderr)
        return EXIT_USAGE

    total = 0.0
    for spec in args.session:
        session_id, own_from = parse_session(spec)
        window_from = to_utc(own_from or args.window_from)
        if not session_id or window_from is None:
            print(f"usage error: bad --session or --from for {spec!r}", file=sys.stderr)
            return EXIT_USAGE
        priced = price_session_in_window(
            session_id, {"from": window_from, "to": window_to}, projects_root=args.projects_root)
        if priced is None:
            print(f"warning: no transcript carries session {session_id}; priced at 0", file=sys.stderr)
            continue
        cost = priced.get("cost_usd") or {}
        if cost.get("total_is_partial"):
            print(f"warning: session {session_id} total is partial (a model has no rate)", file=sys.stderr)
        total += float(cost.get("total") or 0.0)
    print(f"{total:.{COST_DECIMALS}f}")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
