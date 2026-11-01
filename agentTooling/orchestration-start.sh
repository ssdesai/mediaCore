#!/usr/bin/env bash
set -uo pipefail

# Start an orchestration record: orchestration-start.sh <slug> [--session <id>]
#
# An orchestrator session spawns one implementer session per feature and builds nothing
# itself. This writes the record of that group — `self/orchestrations/<slug>/README.md`,
# an opening paragraph and a JSON fence — so the cost of the group (the orchestrator's own
# transcript plus every feature it spawned) can be read together:
#
#   orchestration-start.sh <slug>
#   python3 analysis/manifest.py --orchestration <slug> add-feature repo=R slug=S …
#   orchestration-capture.sh <slug>
#   python3 analysis/report.py --orchestration <slug>
#
# The fence (analysis/README.md → manifest.py, "the orchestration record"):
#
#   slug           the record's slug
#   session        the orchestrator's session id: `--session`, else $CLAUDE_CODE_SESSION_ID —
#                  the way feature-start.sh learns the current session
#   agent_tooling  `git rev-parse HEAD` of this checkout, or null when it is not a git
#                  checkout of its own (a vendored copy has no .git to ask) — the version an
#                  experiment comparing two agentTooling versions at the orchestrator level
#                  pins the run to
#   session_window {from: now, to: null} — `manifest.py --orchestration <slug> set-window-to
#                  now` closes it
#   features       empty; `manifest.py --orchestration <slug> add-feature` fills it
#
# It refuses a slug that fails the pattern, an existing record, and a run with no session
# id. It commits nothing: the orchestrator commits its record, and nothing else, on its
# assigned branch, as a records-only PR (the README's prose says so).
#
# Exit codes: 2 usage; 1 any refusal.

USAGE_RC=2
REFUSED_RC=1
SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'
# Where records live, relative to this script (analysis/roots.py's orchestrations_root).
ORCHESTRATIONS_REL="self/orchestrations"
RECORD_NAME="README.md"
UTC_STAMP_FORMAT='+%Y-%m-%dT%H:%M:%SZ'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: orchestration-start.sh <slug> [--session <id>]" >&2
  exit "$USAGE_RC"
}
refuse() {
  echo "  refused  $*" >&2
  exit "$REFUSED_RC"
}

SLUG="${1:-}"; [[ -n "$SLUG" ]] || usage; shift
SESSION_OPT=""
while (( $# )); do
  case "$1" in
    --session) (( $# >= 2 )) || usage; SESSION_OPT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$SLUG" =~ $SLUG_PATTERN ]] || refuse "slug '$SLUG' must match $SLUG_PATTERN — kebab-case, no slash, no prefix"
SESSION="${SESSION_OPT:-${CLAUDE_CODE_SESSION_ID:-}}"
[[ -n "$SESSION" ]] || refuse "no session id: \$CLAUDE_CODE_SESSION_ID is unset and --session was not given"

FOLDER="$SCRIPT_DIR/$ORCHESTRATIONS_REL/$SLUG"
[[ ! -e "$FOLDER" ]] || refuse "$FOLDER already exists — a record is started once; edit it with analysis/manifest.py --orchestration $SLUG"

# `.git` is a directory in a standalone clone and a file in a linked worktree; a vendored
# copy has neither of its own, and `git -C` there would answer with the consuming repo's HEAD.
AGENT_TOOLING="null"
if [[ -e "$SCRIPT_DIR/.git" ]]; then
  head_id="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)"
  if [[ -n "$head_id" ]]; then AGENT_TOOLING="\"$head_id\""; fi
fi
NOW="$(date -u "$UTC_STAMP_FORMAT")"

mkdir -p "$FOLDER" || refuse "cannot create $FOLDER"
cat > "$FOLDER/$RECORD_NAME" <<RECORD
# Orchestration: $SLUG

<One paragraph: the group of features this orchestrator session was asked to run, and
why they are measured together.>

The orchestrator spawns one implementer session per feature and builds nothing itself.
It commits nothing except this record, which it pushes on its assigned branch as a
records-only PR; each feature's own record travels in that feature's PR. Cost is read
together: \`orchestration-capture.sh $SLUG\` prices the orchestrator's own transcript
(overhead) into \`planning.json\`, and \`python3 analysis/report.py --orchestration $SLUG\`
joins it with every feature's \`report.json\` into \`report.md\` and \`report.json\`.

\`\`\`json
{
  "slug": "$SLUG",
  "session": "$SESSION",
  "agent_tooling": $AGENT_TOOLING,
  "session_window": {"from": "$NOW", "to": null},
  "features": []
}
\`\`\`
RECORD
[[ -f "$FOLDER/$RECORD_NAME" ]] || refuse "could not write $FOLDER/$RECORD_NAME"
echo "  record    $ORCHESTRATIONS_REL/$SLUG/$RECORD_NAME  (session $SESSION, agent_tooling ${AGENT_TOOLING//\"/})"
echo ""
echo "Next:"
echo "  1. Replace the placeholder paragraph in the record's README."
echo "  2. For each feature: feature-start.sh [--self] <slug> --orchestration $SLUG …, then"
echo "       python3 analysis/manifest.py --orchestration $SLUG add-feature repo=<repo> slug=<feature> session=<id> branch=<branch>"
echo "  3. At the end: python3 analysis/manifest.py --orchestration $SLUG set-window-to now,"
echo "       orchestration-capture.sh $SLUG, python3 analysis/report.py --orchestration $SLUG"
