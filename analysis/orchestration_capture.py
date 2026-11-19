#!/usr/bin/env python3
"""Price an orchestrator's own transcript into `plans/orchestrations/<slug>/planning.json`
(`self/orchestrations/<slug>/planning.json` under `--self`).

    python3 agentTooling/analysis/orchestration_capture.py [--self] <slug>

The record (`orchestration-start.sh`) names the orchestrator's session id and a
`session_window`. This prices that session — and its own subagents — inside the window
through `capture_planning.price_session_in_window`, the one pricing path for a bare
session id; `to` null means now. The output's fields are `planning.json`'s own
(`sessions`, `subagents`, `priced`, `cost_usd`, `duration_s`, `rates_source`, `warnings`),
so `report.py` reads a feature's and an orchestration's with one loader; it differs by
carrying `orchestration` and `agent_tooling` and `session_window` where a feature's carries
`manifest_branches`, and by no claim machinery (no `share_basis`, no `also_claimed_by`):
nothing else claims the orchestrator's session.

A **coordinator record** (`"kind": "coordinator"`, self/features/coordinator-cost-records/)
is priced as its own cost only: its own transcript, plus the delegates that are its own —
a brief opening `feature: none — <reason>` (an analysis or bookkeeping delegate no feature
owns) whose agent id no feature has claimed (the machine's claims ledger,
`capture_planning.load_claims`, and the `subagents` pins of every manifest this checkout can
read). Every other delegate is claimed by the feature it built, or names one, so pricing it
here would count it twice; it is listed in `subagents_not_priced[]` instead.
`planning.json` then carries `kind: "coordinator"`, and one warning names any feature that
claims the coordinator's session itself (a manifest's `sessions` pin, or the ledger's
session section) — that feature already counts the transcript this line counts.

Exit codes: 0 captured, 1 refused (no record, no session, no transcript).
"""

import argparse
import json
import sys
from datetime import datetime, timezone

from capture_planning import (
    HISTORY_FILENAME, LEDGER_SESSIONS_KEY, LEDGER_SUBAGENTS_KEY, RATES_VERIFIED, brief_header,
    brief_header_of, load_ledger, price_session_in_window,
)
from roots import (
    ORCH_KIND_COORDINATOR, add_self_flag, all_features_roots, orchestration_kind,
    orchestrations_root, record_write_refusal, shared_rules,
)
from routing import parse_manifest
from transcript import to_utc

PLANNING_NAME = "planning.json"
JSON_INDENT = 2
# The record file of an orchestration (the glob below reads orchestration roots only)
MANIFEST_NAME = shared_rules.RECORD_NAME
# A feature manifest's ids claimed outright (manifest.py pin-session / pin-subagent)
PINNED_SESSIONS_KEY = "sessions"
PINNED_SUBAGENTS_KEY = "subagents"
DOUBLE_COUNT_WARNING = (
    "{feature} claims this coordinator's session {session}: the transcript priced here is in "
    "that feature's total too — unpin it there or drop this record"
)
LEDGER_LABEL = "the claims ledger"


def manifest_pins(key):
    """`{id: [feature label…]}` for every id under `key` (`sessions` or `subagents`) in
    every manifest of both corpora this checkout can read; labels are
    `<corpus>/<slug>`, e.g. `self/features/x`."""
    pins = {}
    for root in all_features_roots():
        if not root.is_dir():
            continue
        for readme in sorted(root.glob("*/" + MANIFEST_NAME)):
            try:
                ids = parse_manifest(readme).get(key) or []
            except Exception:  # an unreadable manifest pins nothing here
                continue
            label = f"{root.parent.name}/{root.name}/{readme.parent.name}"
            for pinned in ids if isinstance(ids, list) else []:
                pins.setdefault(pinned, []).append(label)
    return pins


def coordinator_owns(claimed):
    """The `subagent_filter` for a coordinator: a delegate is the coordinator's own when its
    brief opens `feature: none — …` and no feature has claimed its id."""
    def owns(agent_id, lines):
        header = brief_header_of(lines)
        return (header is not None and header[0] == brief_header.KIND_NONE
                and agent_id not in claimed)
    return owns


def session_claimants(session_id):
    """Who claims the coordinator's session itself: manifest `sessions` pins, then the
    ledger's session section."""
    claimants = list(manifest_pins(PINNED_SESSIONS_KEY).get(session_id, []))
    if session_id in (load_ledger()[LEDGER_SESSIONS_KEY] or {}):
        claimants.append(LEDGER_LABEL)
    return claimants


def capture(slug, self_mode):
    # It writes planning.json into the record's folder, so it asks the write guard
    # (self/features/consumer-record-guard/)
    refusal = record_write_refusal(self_mode, slug)
    if refusal:
        print(f"refusing: {refusal}", file=sys.stderr)
        return 1
    folder = orchestrations_root(self_mode) / slug
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
    kind = orchestration_kind(record)
    coordinator = kind == ORCH_KIND_COORDINATOR
    subagent_filter = None
    if coordinator:
        claimed = set(load_ledger()[LEDGER_SUBAGENTS_KEY] or {}) | set(manifest_pins(PINNED_SUBAGENTS_KEY))
        subagent_filter = coordinator_owns(claimed)
    priced = price_session_in_window(session_id, window, subagent_filter=subagent_filter)
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
        "kind": kind,
        "agent_tooling": record.get("agent_tooling"),
        "session_window": window_record,
        **priced,
        "rates_source": f"agentTooling/analysis/{HISTORY_FILENAME} checked={RATES_VERIFIED}",
    }
    if coordinator:
        for feature in session_claimants(session_id):
            data["warnings"].append(DOUBLE_COUNT_WARNING.format(feature=feature, session=session_id))
    (folder / PLANNING_NAME).write_text(json.dumps(data, indent=JSON_INDENT) + "\n")
    cost = data["cost_usd"]
    partial = " (partial)" if cost["total_is_partial"] else ""
    print(f"  captured  {folder / PLANNING_NAME}  {kind} overhead ${cost['total']:.4f}{partial}")
    if coordinator:
        print(f"  own       {len(data['subagents'])} `feature: none` delegate(s) no feature claims, priced here")
        print(f"  excluded  {len(data.get('subagents_not_priced') or [])} delegate(s): claimed by, "
              "or briefed for, a feature")
    for warning in data["warnings"]:
        print(f"  warn      {warning}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_self_flag(parser)
    parser.add_argument("slug")
    args = parser.parse_args()
    return capture(args.slug, args.self_mode)


if __name__ == "__main__":
    sys.exit(main())
