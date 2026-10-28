#!/usr/bin/env bash
set -uo pipefail

# Append one wall-clock milestone to a feature's timing.jsonl by hand:
#
#   ./agentTooling/stamp-timing.sh [--self] <slug> <event> [key=value ...]
#
# The runners stamp their own boundaries as they go (stamp_timing, plan-runner-roots.sh),
# so a planned feature's Time table can split planning from build from verify from review
# without anyone typing anything. A DIRECT feature (AGENT_DIRECT.md) has no runner until
# the review pass: its whole build is one implementer's transcript, one undivided span,
# and the report can say how long it took but not how the hours split between writing the
# acceptance tests, building, and gating. This is how the implementer says so — it runs
#
#   ./agentTooling/stamp-timing.sh <slug> checkpoint status=<status>
#
# at each checkpoint milestone (AGENT_DIRECT.md -> "Checkpoint and resume"), and
# analysis/report.py turns the `planned` / `tests-written` / `gating` / `committed`
# instants into sub-rows under the build row.
#
# Nothing here is specific to that use: any event name and any details are accepted, and
# the line lands in the same timing.jsonl the runners append to. What it does NOT do is
# guess — an unknown feature, a missing event, or a detail that is not key=value is an
# error rather than a silently dropped stamp, because between a direct build's commits
# this file is the only record there is.
#
# --self goes first, before the slug, like every other script here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if (( SELF_MODE )); then shift; fi

USAGE="usage: stamp-timing.sh [--self] <slug> <event> [key=value ...]"
# Exit codes, matching the runners': 2 is a usage error the caller can fix from the
# message, 127 a missing hard dependency, 1 a stamp that was asked for and did not land.
USAGE_RC=2
MISSING_TOOL_RC=127
STAMP_FAILED_RC=1

SLUG_ARG="${1:-}"
EVENT="${2:-}"
if [[ -z "$SLUG_ARG" || -z "$EVENT" ]]; then
  echo "$USAGE" >&2
  exit "$USAGE_RC"
fi
shift 2

# stamp_timing builds the line with jq and suppresses its stderr, so a missing jq would
# otherwise be a silent no-op — the same failure mode require_tools exists to prevent in
# the runners (which this script does not source: it needs the roots, not the queue).
if ! command -v jq >/dev/null 2>&1; then
  echo "stamp-timing.sh needs jq on PATH" >&2
  exit "$MISSING_TOOL_RC"
fi

# stamp_timing reads the slug from FEATURE_SLUG and returns quietly when the feature
# directory is absent. Quiet is right inside a runner that may not have resolved a
# feature yet; here it would swallow a typo, so check first.
FEATURE_SLUG="$SLUG_ARG"
if [[ ! -d "$FEATURES_DIR/$FEATURE_SLUG" ]]; then
  echo "no feature '$FEATURE_SLUG' under $FEATURES_LABEL" >&2
  exit "$USAGE_RC"
fi

# A bare word would become {word: "word"} — stamp_timing splits on the first '='  and a
# string with none is its own key and its own value. Reject it rather than write a line
# whose detail means nothing.
for kv in "$@"; do
  if [[ "$kv" != *=* ]]; then
    echo "detail '$kv' is not key=value; nothing stamped" >&2
    echo "$USAGE" >&2
    exit "$USAGE_RC"
  fi
done

TIMING_PATH="$FEATURES_DIR/$FEATURE_SLUG/timing.jsonl"
lines_before=0
if [[ -f "$TIMING_PATH" ]]; then lines_before="$(wc -l < "$TIMING_PATH")"; fi

stamp_timing "$EVENT" "$@"

lines_after=0
if [[ -f "$TIMING_PATH" ]]; then lines_after="$(wc -l < "$TIMING_PATH")"; fi
if (( lines_after <= lines_before )); then
  echo "stamp-timing.sh: nothing was appended to $FEATURES_LABEL/$FEATURE_SLUG/timing.jsonl" >&2
  exit "$STAMP_FAILED_RC"
fi

echo "  stamped  $EVENT -> $FEATURES_LABEL/$FEATURE_SLUG/timing.jsonl"
