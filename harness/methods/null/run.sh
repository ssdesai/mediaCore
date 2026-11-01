#!/usr/bin/env bash
set -uo pipefail

# null — the harness's own test double. Calls no model at all: it writes a marker file,
# commits it, and opens the "PR" through the repo's own plans/pr.sh, which is the same
# hook run-review.sh uses. Kept in the shipped methods rather than in tests/ because
# harness/tests/smoke.sh needs a method that satisfies the method contract exactly, and
# a double that lives outside the methods directory stops being one the moment the
# contract changes.
#
#   run.sh <tree> <brief> <slug>
#
# Exit 0 = PR open, 2 = usage-limit stop, 1 = work failure. It only ever exits 0 or 1.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

# What the fixture's accept.py looks for, and where. A named path, because two files
# have to agree on it.
NULL_MARKER_RELPATH="plans/null-method-marker.md"
NULL_PR_HOOK="plans/pr.sh"

[[ -f "$BRIEF" ]] || { harness_warn "null: no brief at $BRIEF"; exit "$METHOD_FAILED_RC"; }

{
  echo "# null method"
  echo ""
  echo "slug: $SLUG"
  echo "brief: $BRIEF"
  echo ""
  echo "The brief the harness filled for this run, verbatim:"
  echo ""
  echo '```'
  cat "$BRIEF"
  echo '```'
} > "$TREE/$NULL_MARKER_RELPATH"

harness_commit_all "$TREE" "$SLUG: null method marker" || {
  harness_warn "null: nothing to commit"
  exit "$METHOD_FAILED_RC"
}

if [[ -x "$TREE/$NULL_PR_HOOK" ]]; then
  ( cd "$TREE" && "./$NULL_PR_HOOK" "$SLUG" "$TREE/$NULL_MARKER_RELPATH" ) || {
    harness_warn "null: PR hook failed"
    exit "$METHOD_FAILED_RC"
  }
else
  harness_warn "null: no PR hook at $TREE/$NULL_PR_HOOK"
  exit "$METHOD_FAILED_RC"
fi

exit "$METHOD_OK_RC"
