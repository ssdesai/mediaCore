#!/usr/bin/env bash
set -uo pipefail

# Self-test that harness/methods/direct-bare/ stays `direct` minus its procedure steps
# (harness/methods/direct-bare/README.md). Run by self/gate.sh, or by hand:
#   bash self/tests/direct-bare-pair.sh
#
# direct-bare is the control of an experiment that measures what direct's CHECKPOINT.md,
# stamp-timing.sh and tests-first steps cost, so the two briefs may differ in those steps
# and nowhere else. This derives the expected direct-bare/template.md from direct's by the
# two removals and fails on any other difference — an edit to direct/template.md fails
# here until direct-bare follows it.
#
# Asserts: 1. the derivation removes something (the markers still exist in direct's
# template, so the test cannot pass vacuously); 2. direct-bare/template.md equals the
# derivation byte for byte, and carries no trace of the removed steps; 3. both templates
# fill through the harness's own harness_fill_template with the same environment, leaving
# no placeholder, and direct-bare uses no placeholder direct lacks; 4. direct-bare/run.sh
# is executable and equals direct/run.sh once comments and the method name are set aside;
# 5. harness_branch_name camelCases a hyphenated method (direct-bare → DirectBare) and every
# methods/ directory yields a branch matching ^[a-z][A-Za-z0-9]*$.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
METHODS="$HERE/harness/methods"
DIRECT="$METHODS/direct"
BARE="$METHODS/direct-bare"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROCEDURE_HEADING='## Procedure'
NEXT_HEADING='## Quality bar'
CHECKPOINT_PAREN=' (`CHECKPOINT.md` at status `committed`)'

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── 1: the markers are still there ───────────────────────────────────────────
check "1a. direct/template.md has the Procedure heading" 'grep -qxF "$PROCEDURE_HEADING" "$DIRECT/template.md"'
check "1b. ... and the heading that follows the section" 'grep -qxF "$NEXT_HEADING" "$DIRECT/template.md"'
check "1c. ... and the CHECKPOINT parenthetical in Finish step 2" 'grep -qF "$CHECKPOINT_PAREN" "$DIRECT/template.md"'

# ── 2: direct-bare/template.md is the derivation, exactly ────────────────────
# Drop from the Procedure heading up to (not including) the next heading, then the
# parenthetical. The blank line before the heading stays, so one blank separates the
# sections around the cut.
awk -v start="$PROCEDURE_HEADING" -v stop="$NEXT_HEADING" '
  $0 == start { skipping = 1 }
  $0 == stop  { skipping = 0 }
  !skipping   { print }
' "$DIRECT/template.md" > "$TMP/derived.1"
EXPECTED="$TMP/expected.md"
: > "$EXPECTED"
while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "${line/"$CHECKPOINT_PAREN"/}" >> "$EXPECTED"
done < "$TMP/derived.1"

check "2a. direct-bare/template.md exists" '[[ -f "$BARE/template.md" ]]'
diff "$EXPECTED" "$BARE/template.md" > "$TMP/template.diff" 2>&1; rc=$?
check "2b. it is direct/template.md minus the Procedure section and the parenthetical, nothing else (diff rc $rc)" '[[ $rc -eq 0 ]]'
[[ $rc -ne 0 ]] && sed 's/^/        /' "$TMP/template.diff"
check "2c. it names no CHECKPOINT.md, stamp-timing or AGENT_DIRECT" '! grep -qE "CHECKPOINT|stamp-timing|AGENT_DIRECT|acceptance tests" "$BARE/template.md"'

# ── 3: both fill through the harness's own fill ──────────────────────────────
# The same environment for both arms; every placeholder either template may use is set,
# so an unfilled one in either is a placeholder the harness does not fill.
fill() {   # fill <template> — filled text on stdout, non-zero if the harness refused it
  (
    export HARNESS_TREE=/t HARNESS_BRANCH=b HARNESS_BASE=main HARNESS_SLUG=s \
      HARNESS_SPEC_TREE=/spec HARNESS_SPEC_PATH=p HARNESS_SPEC_SECTIONS=1 \
      HARNESS_FACTS=facts HARNESS_GATE_COMMAND=gate HARNESS_GATE_MINUTES=1 \
      HARNESS_FIXTURE=fx HARNESS_ISOLATION=iso
    # shellcheck source=../../harness/lib.sh
    source "$HERE/harness/lib.sh" && harness_fill_template "$1"
  )
}
fill "$DIRECT/template.md" > "$TMP/direct.filled" 2>/dev/null; rc_direct=$?
fill "$BARE/template.md" > "$TMP/bare.filled" 2>"$TMP/bare.err"; rc_bare=$?
check "3a. direct fills (rc $rc_direct)" '[[ $rc_direct -eq 0 ]]'
check "3b. direct-bare fills (rc $rc_bare)" '[[ $rc_bare -eq 0 ]]'
check "3c. the filled direct-bare brief carries no @@" '! grep -q "@@" "$TMP/bare.filled"'
grep -oE '@@[A-Z_]+@@' "$DIRECT/template.md" | sort -u > "$TMP/direct.ph"
grep -oE '@@[A-Z_]+@@' "$BARE/template.md" | sort -u > "$TMP/bare.ph"
check "3d. direct-bare uses no placeholder direct does not" '[[ -z "$(comm -13 "$TMP/direct.ph" "$TMP/bare.ph")" ]]'

# ── 4: run.sh is direct's, renamed ───────────────────────────────────────────
check "4a. direct-bare/run.sh is executable" '[[ -x "$BARE/run.sh" ]]'
grep -v '^#' "$DIRECT/run.sh" > "$TMP/direct.run"
grep -v '^#' "$BARE/run.sh" | sed 's/direct-bare/direct/g' > "$TMP/bare.run"
check "4b. apart from comments and the method name it is direct/run.sh" 'diff -q "$TMP/direct.run" "$TMP/bare.run" >/dev/null'

# ── 5: a hyphenated method name yields a bare-camelCase branch ───────────────
# harness_branch_name (harness/lib.sh, SPEC §4) camelCases `direct-bare` to `DirectBare`;
# every directory under harness/methods/ must yield a branch matching the rule
# publish.sh and new-experiment.sh enforce, so the next hyphenated name cannot ship broken.
BRANCH_RULE='^[a-z][A-Za-z0-9]*$'
branch() {   # branch <stem> <method> <repeat> <repeats> [label]
  ( source "$HERE/harness/lib.sh" && harness_branch_name "$@" )
}
check "5a. direct-bare, one repeat: exportStoreDirectBare" '[[ "$(branch exportStore direct-bare 1 1)" == "exportStoreDirectBare" ]]'
check "5b. direct-bare, repeat 2 of 3: exportStoreDirectBare2" '[[ "$(branch exportStore direct-bare 2 3)" == "exportStoreDirectBare2" ]]'
check "5c. with an arm label: exportStoreDirectBareAfter2" '[[ "$(branch exportStore direct-bare 2 3 after)" == "exportStoreDirectBareAfter2" ]]'
check "5d. a method without a hyphen is unchanged: exportStoreDirect" '[[ "$(branch exportStore direct 1 1)" == "exportStoreDirect" ]]'
check "5e. three parts: exportStoreSpecOpusBuild" '[[ "$(branch exportStore spec-opus-build 1 1)" == "exportStoreSpecOpusBuild" ]]'
for method_dir in "$METHODS"/*/; do
  method="$(basename "$method_dir")"
  name="$(branch exportStore "$method" 1 1)"
  check "5f. methods/$method yields a bare-camelCase branch ($name)" '[[ "$name" =~ $BRANCH_RULE ]]'
done

if (( fails > 0 )); then echo "direct-bare-pair: $fails assertion(s) FAILED"; exit 1; fi
echo "direct-bare-pair: all assertions passed"
