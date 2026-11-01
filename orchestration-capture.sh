#!/usr/bin/env bash
set -uo pipefail

# Capture an orchestration's own cost: orchestration-capture.sh <slug>
#
# Prices the orchestrator's transcript — the session id and window in
# `self/orchestrations/<slug>/README.md`'s fence, `to` null meaning now — into
# `self/orchestrations/<slug>/planning.json`, through analysis/orchestration_capture.py
# (every transcript file for that id across every project directory under
# ~/.claude/projects, the one with the latest instant priced). It stamps, commits and
# pushes nothing: the orchestrator commits its record and pushes its branch itself.
# `python3 analysis/report.py --orchestration <slug>` is the next step.
#
# Exit codes: 2 usage; 1 refused (no record, no session, no transcript).

USAGE_RC=2
SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SLUG="${1:-}"
if [[ -z "$SLUG" || $# -ne 1 ]]; then
  echo "usage: orchestration-capture.sh <slug>" >&2
  exit "$USAGE_RC"
fi
if [[ ! "$SLUG" =~ $SLUG_PATTERN ]]; then
  echo "  refused  slug '$SLUG' must match $SLUG_PATTERN" >&2
  exit 1
fi
python3 -B "$SCRIPT_DIR/analysis/orchestration_capture.py" "$SLUG"
