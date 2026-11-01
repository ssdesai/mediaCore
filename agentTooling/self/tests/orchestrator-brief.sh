#!/usr/bin/env bash
set -uo pipefail

# Self-test for the orchestrator brief template (self/features/orchestrator-brief/).
# Run by self/gate.sh, or by hand: bash self/tests/orchestrator-brief.sh
#
# Reads the real checkout and writes nothing. The template is what an orchestrator copies
# to brief one implementer session, and the one thing it must never do again is tell that
# session it has an assigned branch: an orchestrator-created session has none, and the
# start refuses a detached HEAD without --branch. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"

# The template's path under templates/, its path in a consuming repo, and the phrase the
# brief must not carry.
BRIEF_REL="templates/plans/ORCHESTRATOR_BRIEF.md"
BRIEF_IN_CONSUMER="plans/ORCHESTRATOR_BRIEF.md"
BRIEF_FILE_NAME="ORCHESTRATOR_BRIEF.md"
FORBIDDEN_PHRASE="assigned branch"
BRANCH_LINE='--branch claude/<slug>'
START_SHAPE='<tooling>/feature-start.sh [--self] <slug> --method <method> --branch claude/<slug> [--orchestration <orchestration>]'
BACKGROUND_PHRASE='Run it in the background'
CAPTURE_PHRASE='its output captured to a file in your scratchpad'
WAIT_PHRASE='its exit notification before you read or edit anything in the tree'
REFUSAL_PHRASE='refuses a tree that changes while it runs'

fails=0
ok()  { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "orchestrator-brief"

BRIEF="$AT/$BRIEF_REL"
check "B1. the template exists at $BRIEF_REL" '[[ -f "$BRIEF" ]]'
check "B2. it carries the literal $BRANCH_LINE" 'grep -qF -- "$BRANCH_LINE" "$BRIEF"'
check "B3. it carries the feature-start.sh invocation shape" 'grep -qF -- "$START_SHAPE" "$BRIEF"'
check "B3b. it tells the implementer to run the start in the background and wait for its exit notification before touching the tree" \
  'grep -qF -- "$BACKGROUND_PHRASE" "$BRIEF" && grep -qF -- "$CAPTURE_PHRASE" "$BRIEF" && grep -qF -- "$WAIT_PHRASE" "$BRIEF" && grep -qF -- "$REFUSAL_PHRASE" "$BRIEF"'
check "B4. it never says \"$FORBIDDEN_PHRASE\"" '! grep -qiF -- "$FORBIDDEN_PHRASE" "$BRIEF"'
check "B5. it stays under 80 lines of prose (got $(wc -l < "$BRIEF" 2>/dev/null))" '[[ "$(wc -l < "$BRIEF")" -le 80 ]]'
check "B6. LIFECYCLE.md names its path in a consumer ($BRIEF_IN_CONSUMER)" 'grep -qF -- "$BRIEF_IN_CONSUMER" "$AT/LIFECYCLE.md"'
check "B7. LIFECYCLE.md names its path in agentTooling ($BRIEF_REL)" 'grep -qF -- "$BRIEF_REL" "$AT/LIFECYCLE.md"'
check "B8. sync-plans.sh syncs it (listed in GENERATED)" \
  'grep -E "^GENERATED=\(.*$BRIEF_FILE_NAME" "$AT/sync-plans.sh" >/dev/null'
check "B9. templates/README.md and plans/README.md list it" \
  'grep -qF -- "$BRIEF_FILE_NAME" "$AT/templates/README.md" && grep -qF -- "$BRIEF_FILE_NAME" "$AT/templates/plans/README.md"'
check "B10. every agentTooling-root path in the brief carries the <tooling> prefix" \
  '! sed -E "s#<tooling>/(feature-start|CONVENTIONS|LIFECYCLE)\.(sh|md)##g" "$BRIEF" | grep -qE "feature-start\.sh|CONVENTIONS\.md|LIFECYCLE\.md"'

# The generated-stub list is mirrored by hand in two more places; each name in
# sync-plans.sh's GENERATED must appear in the templates/README.md table and in
# sync-check.sh's 1b loop.
GENERATED_NAMES="$(sed -n 's/^GENERATED=(\(.*\))$/\1/p' "$AT/sync-plans.sh")"
check "B11. GENERATED parsed (got: $GENERATED_NAMES)" '[[ -n "$GENERATED_NAMES" ]]'
# Each name is matched as a whole word with its dots escaped: a bare README.md must not be
# satisfied by interactive/README.md.
for name in $GENERATED_NAMES; do
  name_re="${name//./\\.}"
  check "B12. $name is in the templates/README.md table" 'grep -qE "^plans/$name_re[[:space:]]+generated" "$AT/templates/README.md"'
  check "B13. $name is in sync-check.sh 1b's loop" 'grep -E "^for rel in (.*[[:space:]])?$name_re(;|[[:space:]])" "$AT/self/tests/sync-check.sh" >/dev/null'
done

echo
if [[ $fails -eq 0 ]]; then
  echo "orchestrator-brief: all checks passed"
  exit 0
fi
echo "orchestrator-brief: $fails check(s) failed"
exit 1
