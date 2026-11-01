#!/usr/bin/env python3
"""Price an orchestrator's own transcript into `self/orchestrations/<slug>/planning.json`.

    python3 agentTooling/analysis/orchestration_capture.py <slug>

The record (`orchestration-start.sh`) names the orchestrator's session id and a
`session_window`. This prices that session — and its own subagents — inside the window
through `capture_planning.price_session_in_window`, the one pricing path for a bare
session id; `to` null means now. The output's fields are `planning.json`'s own
(`sessions`, `subagents`, `priced`, `cost_usd`, `duration_s`, `rates_source`, `warnings`),
so `report.py` reads a feature's and an orchestration's with one loader; it differs by
carrying `orchestration` and `agent_tooling` and `session_window` where a feature's carries
`manifest_branches`, and by no claim machinery (no `share_basis`, no `also_claimed_by`):
nothing else claims the orchestrator's session.

Exit codes: 0 captured, 1 refused (no record, no session, no transcript).
"""

import argparse
import json
import sys
from datetime import datetime, timezone

from capture_planning import HISTORY_FILENAME, RATES_VERIFIED, price_session_in_window
from roots import orchestrations_root
from routing import parse_manifest
from transcript import to_utc

PLANNING_NAME = "planning.json"
JSON_INDENT = 2


def capture(slug):
    folder = orchestrations_root() / slug
    readme = folder / "README.md"
    if not readme.is_file():
        print(f"refusing: no orchestration record at {readme}", file=sys.stderr)
        return 1
    record = parse_manifest(readme)
    session_id = record.get("session")
    if not session_id:
        print("refusing: the record carries no `session`", file=sys.stderr)
        return 1
    window_record = record.get("session_window") or {}
    window = {"from": to_utc(window_record.get("from")), "to": to_utc(window_record.get("to"))}
    priced = price_session_in_window(session_id, window)
    if priced is None:
        print(
            f"refusing: no transcript for session {session_id} under ~/.claude/projects/ — "
            "the id is wrong, or it has aged out",
            file=sys.stderr,
        )
        return 1
    data = {
        "slug": slug,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "orchestration": True,
        "agent_tooling": record.get("agent_tooling"),
        "session_window": window_record,
        **priced,
        "rates_source": f"agentTooling/analysis/{HISTORY_FILENAME} checked={RATES_VERIFIED}",
    }
    (folder / PLANNING_NAME).write_text(json.dumps(data, indent=JSON_INDENT) + "\n")
    cost = data["cost_usd"]
    partial = " (partial)" if cost["total_is_partial"] else ""
    print(f"  captured  {folder / PLANNING_NAME}  orchestrator overhead ${cost['total']:.4f}{partial}")
    for warning in data["warnings"]:
        print(f"  warn      {warning}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("slug")
    return capture(parser.parse_args().slug)


if __name__ == "__main__":
    sys.exit(main())
