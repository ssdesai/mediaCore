#!/usr/bin/env bash
set -uo pipefail

# Capture an orchestration's own cost: orchestration-capture.sh [--self] <slug>
#
# Prices the orchestrator's transcript — the session id and window in
# `plans/orchestrations/<slug>/README.md`'s fence (`self/orchestrations/<slug>/` under
# `--self`), `to` null meaning now — into `planning.json` beside it, through
# analysis/orchestration_capture.py (every transcript file for that id across every project
# directory under ~/.claude/projects, the one with the latest instant priced). A slug found
# only at the old vendored place, `agentTooling/self/orchestrations/<slug>`, is refused with
# the `git mv` that moves it; `--self` from a copy vendored in a consuming repo is refused
# before planning.json is written (roots.py's `record_write_refusal`,
# self/features/consumer-record-guard/). It stamps, commits and pushes nothing: the orchestrator commits
# its record and pushes its branch itself.
# `python3 analysis/report.py [--self] --orchestration <slug>` is the next step.
#
# Exit codes: 2 usage; 1 refused (no record, no session, no transcript).

USAGE_RC=2
SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# The script's own directory with every symlink resolved, before anything is sourced from it
# (security audit round 4): a link to this script placed elsewhere must not make it source a
# library planted beside the link.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_LINK="$(readlink "$SCRIPT_PATH")"
  if [[ "$SCRIPT_LINK" == /* ]]; then SCRIPT_PATH="$SCRIPT_LINK"; else SCRIPT_PATH="$(dirname "$SCRIPT_PATH")/$SCRIPT_LINK"; fi
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"

SELF_FLAG=()
if [[ "${1:-}" == "--self" ]]; then SELF_FLAG=(--self); shift; fi
SLUG="${1:-}"
if [[ -z "$SLUG" || $# -ne 1 ]]; then
  echo "usage: orchestration-capture.sh [--self] <slug>" >&2
  exit "$USAGE_RC"
fi
if [[ ! "$SLUG" =~ $SLUG_PATTERN ]]; then
  echo "  refused  slug '$SLUG' must match $SLUG_PATTERN" >&2
  exit 1
fi
python3 -B "$SCRIPT_DIR/analysis/orchestration_capture.py" ${SELF_FLAG[@]+"${SELF_FLAG[@]}"} "$SLUG"
