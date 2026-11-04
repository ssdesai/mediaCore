#!/usr/bin/env bash
set -uo pipefail

# Self-test for "measuring is the driver's, building is the arm's" (self/features/
# harness-driver-measures). An experiment arm's worktree carries a vendored agentTooling/
# from a historical fixture base; the harness (the driver, the copy run.sh lives in) must
# do the measuring and bookkeeping itself. Run by self/gate.sh, or by hand:
# bash self/tests/harness-driver-measures.sh
#
# No model, no network: a stub `gh` on PATH, throwaway git repos under mktemp -d, and
# transcripts under a redirected $HOME. Asserts, in order:
#   T1. harness_fill_template substitutes literally under bash 5.2's patsub_replacement
#       (on and off): a facts value holding `&`, `\&`, `\`, `/`, `@@OTHER@@` and newlines
#       comes out byte for byte, and so does a PREV_OUTCOME holding `@@NAME@@`;
#       harness_replace_literal is literal for the same values;
#   T2. harness_resolve_commit fetches a prep commit by sha once, creates no ref, and
#       still fails (returning nothing) for a sha no remote has;
#   T3. harness_pr_url asks the DRIVER's forge.sh about the ARM checkout's origin (stub
#       gh sees repos/<arm origin>/pulls), also when the arm has no agentTooling/forge.sh;
#       HARNESS_FORGE_BIN still overrides;
#   T4. an arm whose vendored rates lack the model is priced at the driver's rates:
#       capture_planning.py and report.py run from the driver's analysis/ with --arm-root
#       write the arm's plans/features/<slug>/ and price the session, where the arm's own
#       copy prices it $0; --arm-root with --self is a usage error;
#   T5. an old arm's feature directory (the corpus's oldest, agenttooling-self-host, from
#       August) goes through the driver's capture with --arm-root without a traceback.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness.driver.measures.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Physical path: roots.py resolves AGENT_TOOLING_DIR with Path.resolve() (capture-guard.sh).
TMP="$(cd "$TMP" && pwd -P)"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
# The profile is forced, never inherited from the machine (self/tests/README.md).
unset CLAUDE_CODE_REMOTE
export AGENTTOOLING_PROFILE=local
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# shellcheck source=../../harness/lib.sh
source "$HERE/harness/lib.sh"

echo "harness driver measures"

# ── T1. The template fill is literal ───────────────────────────────────────────
FILL_TEMPLATE="$TMP/fill-template.md"
printf 'before @@FACTS@@ middle @@SLUG@@ after\nprev: @@PREV_OUTCOME@@\n' > "$FILL_TEMPLATE"
# `&` and `\&` are what bash 5.2's patsub_replacement rewrites; `\`, `/` and newlines are
# what a naive escape would mangle. A facts value holding `@@OTHER@@` would trip the
# fill's unfilled-placeholder check by design (it would ship to a model verbatim), so that
# shape is asserted on the literal helper below; PREV_OUTCOME, which is never scanned, may
# carry an `@@NAME@@` through the fill.
FACTS_VALUE=$'the A&B table: x \\& y \\\\ z / w\nsecond line & more'
PREV_VALUE=$'it said @@NAME@@ & \\& done'
export HARNESS_FACTS="$FACTS_VALUE" HARNESS_SLUG="the-slug" HARNESS_PREV_OUTCOME="$PREV_VALUE"
EXPECTED_FILL="before $FACTS_VALUE middle the-slug after"$'\n'"prev: $PREV_VALUE"$'\n'

fill_with_patsub() {  # $1 on|off — run the fill in a bash with that setting
  if [[ "$1" == on ]]; then shopt -s patsub_replacement 2>/dev/null; else shopt -u patsub_replacement 2>/dev/null; fi
  harness_fill_template "$FILL_TEMPLATE" 2>&1
}
for mode in on off; do
  got="$(fill_with_patsub "$mode"; printf x)"; got="${got%x}"
  check "T1a. [patsub_replacement $mode] a facts value with & , \\& , \\\\ , / and newlines fills byte for byte" \
    '[[ "$got" == "$EXPECTED_FILL" ]]'
done
shopt -u patsub_replacement 2>/dev/null
unset HARNESS_FACTS HARNESS_SLUG HARNESS_PREV_OUTCOME

LITERAL_VALUE=$'a & b \\& c \\\\ d / e @@OTHER@@ f\ng'
for mode in on off; do
  if [[ "$mode" == on ]]; then shopt -s patsub_replacement 2>/dev/null; else shopt -u patsub_replacement 2>/dev/null; fi
  harness_replace_literal "x @@PAT@@ y @@PAT@@ z" "@@PAT@@" "$LITERAL_VALUE"
  check "T1b. [patsub_replacement $mode] harness_replace_literal replaces every occurrence, value untouched" \
    '[[ "$HARNESS_REPLACED" == "x $LITERAL_VALUE y $LITERAL_VALUE z" ]]'
  harness_replace_literal "no placeholder here" "@@PAT@@" "$LITERAL_VALUE"
  check "T1c. [patsub_replacement $mode] a text without the pattern is returned as it was" \
    '[[ "$HARNESS_REPLACED" == "no placeholder here" ]]'
done
shopt -u patsub_replacement 2>/dev/null
# The premise: on a bash that has the option, the old spelling really does break.
if shopt -s patsub_replacement 2>/dev/null; then
  old_text="x @@A@@ y"; old_value='a & b'
  old_result="${old_text//@@A@@/$old_value}"
  check "T1d. premise: on this bash \${t//pat/\$v} expands & (the bug the helper avoids)" \
    '[[ "$old_result" == "x a @@A@@ b y" ]]'
  shopt -u patsub_replacement 2>/dev/null
else
  ok "T1d. premise: this bash has no patsub_replacement, so the old spelling was safe here"
fi
# No other ${x//pat/$var} — a variable replacement patsub_replacement would rewrite —
# may remain in the harness's code (comments aside).
VAR_REPLACEMENT_RE='\$\{[A-Za-z_][A-Za-z_0-9]*//[^}]*/[^}]*\$'
var_replacements="$(grep -nE "$VAR_REPLACEMENT_RE" "$HERE"/harness/*.sh "$HERE"/harness/methods/*/run.sh 2>/dev/null | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#')"
check "T1e. no \${x//pat/\$var} substitution remains in harness/ (got: ${var_replacements:-none})" \
  '[[ -z "$var_replacements" ]]'

# ── T2. A base that is a prep commit on no fetched branch ──────────────────────
BARE="$TMP/origin.git"
SEED="$TMP/seed"
git init -q --bare "$BARE"
gitq "$BARE" config uploadpack.allowAnySHA1InWant true
git init -q "$SEED"
gitq "$SEED" config user.email test@example.invalid
gitq "$SEED" config user.name test
gitq "$SEED" symbolic-ref HEAD refs/heads/main
echo base > "$SEED/f.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m base
gitq "$SEED" remote add origin "$BARE"
gitq "$SEED" push -q origin main
gitq "$SEED" checkout -q -b prep
echo prep > "$SEED/prep.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m "prep commit"
PREP_SHA="$(git -C "$SEED" rev-parse HEAD)"
gitq "$SEED" push -q origin prep
# The clone is taken from main only: it has no idea the prep branch exists.
CLONE="$TMP/clone"
git clone -q --single-branch --branch main "file://$BARE" "$CLONE" 2>/dev/null
check "T2a. premise: the fresh clone does not have the prep commit" \
  '! git -C "$CLONE" cat-file -e "$PREP_SHA^{commit}" 2>/dev/null'
refs_before="$(git -C "$CLONE" for-each-ref)"
got="$(harness_resolve_commit "$CLONE" "$PREP_SHA" origin)"; rc=$?
check "T2b. harness_resolve_commit fetches the base by sha and prints it (rc $rc)" '[[ $rc -eq 0 && "$got" == "$PREP_SHA" ]]'
check "T2c. ... and created or moved no ref" '[[ "$(git -C "$CLONE" for-each-ref)" == "$refs_before" ]]'
MISSING_SHA="0123456789abcdef0123456789abcdef01234567"
got="$(harness_resolve_commit "$CLONE" "$MISSING_SHA" origin)"; rc=$?
check "T2d. a sha no remote has still fails, printing nothing (rc $rc)" '[[ $rc -ne 0 && -z "$got" ]]'
got="$(harness_resolve_commit "$CLONE" "main" origin)"; rc=$?
check "T2e. a ref that resolves is returned without any fetch (rc $rc)" '[[ $rc -eq 0 && -n "$got" ]]'
got="$(harness_resolve_commit "$CLONE" "no-such-branch" origin)"; rc=$?
check "T2f. a name that is not a sha is never fetched (rc $rc)" '[[ $rc -ne 0 && -z "$got" ]]'

# ── T3. The PR lookup is the driver's forge, pointed at the arm's origin ───────
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_ARGV_LOG:?}"
echo "${GH_STUB_URL:-}"
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_ARGV_LOG="$TMP/gh-argv.log"
export GH_STUB_URL="https://github.com/acme/widget/pull/7"
ARM_ORIGIN="https://github.com/acme/widget.git"
ARM_NO_FORGE="$TMP/arm-no-forge"   # an August arm: no agentTooling/forge.sh at all
git init -q "$ARM_NO_FORGE"
gitq "$ARM_NO_FORGE" remote add origin "$ARM_ORIGIN"
check "T3a. premise: the arm checkout has no forge.sh of its own" '[[ ! -e "$ARM_NO_FORGE/agentTooling/forge.sh" ]]'
check "T3b. harness_forge_for is the driver's forge.sh when HARNESS_FORGE_BIN is unset" \
  '[[ -z "$HARNESS_FORGE_BIN" && "$(harness_forge_for "$ARM_NO_FORGE")" == "$AGENT_TOOLING_DIR/forge.sh" ]]'
: > "$GH_ARGV_LOG"
url="$(harness_pr_url "$ARM_NO_FORGE" some-branch)"
check "T3c. harness_pr_url finds the PR for an arm with no forge.sh (got '$url')" '[[ "$url" == "$GH_STUB_URL" ]]'
check "T3d. ... asking the arm checkout's repository (acme/widget), not the driver's" \
  'grep -q "repos/acme/widget/pulls" "$GH_ARGV_LOG" && grep -q "head=acme:some-branch" "$GH_ARGV_LOG"'
printf 'body\n' > "$TMP/pr-body.md"
: > "$GH_ARGV_LOG"
url="$(harness_pr_open "$ARM_NO_FORGE" some-branch "a title" "$TMP/pr-body.md")"
check "T3e. harness_pr_open opens it the same way (got '$url')" \
  '[[ "$url" == "$GH_STUB_URL" ]] && grep -q "repos/acme/widget/pulls" "$GH_ARGV_LOG" && grep -q "base=main" "$GH_ARGV_LOG" && grep -q "title=a title" "$GH_ARGV_LOG"'
cat > "$TMP/bin/override-forge" <<'STUB'
#!/usr/bin/env bash
echo "override $FORGE_CHECKOUT $*"
STUB
chmod +x "$TMP/bin/override-forge"
HARNESS_FORGE_BIN="$TMP/bin/override-forge"
url="$(harness_pr_url "$ARM_NO_FORGE" some-branch)"
check "T3f. HARNESS_FORGE_BIN still overrides, and is told the arm checkout (got '$url')" \
  '[[ "$url" == "override $ARM_NO_FORGE pr-find some-branch" ]]'
HARNESS_FORGE_BIN=""
check "T3g. harness_branch_pushed / harness_branch_has_commits read origin and the base" \
  'gitq "$SEED" push -q origin prep; ! harness_branch_pushed "$SEED" no-such-branch && harness_branch_pushed "$SEED" prep && harness_branch_has_commits "$SEED" main && ! harness_branch_has_commits "$SEED" prep'

# ── T4. An arm with stale rates is priced at the driver's ──────────────────────
CONSUMER="$TMP/consumer"
SLUG="driver-priced"
BRANCH="driverPricedArm"
MODEL="claude-sonnet-5-5"
git init -q "$CONSUMER"
gitq "$CONSUMER" config user.email test@example.invalid
gitq "$CONSUMER" config user.name test
mkdir -p "$CONSUMER/agentTooling/analysis"
cp "$HERE"/analysis/*.py "$HERE/analysis/rates_history.json" "$CONSUMER/agentTooling/analysis/"
echo seed > "$CONSUMER/seed.txt"
gitq "$CONSUMER" add -A
gitq "$CONSUMER" commit -q -m seed
ARM="$CONSUMER-$BRANCH"
gitq "$CONSUMER" worktree add -b "$BRANCH" "$ARM"
# The arm's vendored copy is old: its rates table has no price for today's model.
mkdir -p "$ARM/agentTooling/analysis"
cp "$HERE"/analysis/*.py "$ARM/agentTooling/analysis/"
jq --arg m "$MODEL" 'del(.models[$m])' "$HERE/analysis/rates_history.json" > "$ARM/agentTooling/analysis/rates_history.json"
check "T4a. premise: the arm's rates lack $MODEL and the driver's have it" \
  'jq -e --arg m "$MODEL" ".models | has(\$m) | not" "$ARM/agentTooling/analysis/rates_history.json" >/dev/null && jq -e --arg m "$MODEL" ".models | has(\$m)" "$CONSUMER/agentTooling/analysis/rates_history.json" >/dev/null'
mkdir -p "$ARM/plans/features/$SLUG"
cat > "$ARM/plans/features/$SLUG/README.md" <<EOF
# $SLUG

\`\`\`json
{"slug": "$SLUG", "plans": [], "branches": ["$BRANCH"],
 "session_window": {"from": "2026-06-01T00:00:00Z", "to": "2026-06-02T00:00:00Z"}}
\`\`\`
EOF
make_home() {  # $1 home dir — one billed response launched in the arm's worktree
  mkdir -p "$1/.claude/projects/$(printf '%s' "$ARM" | tr '/.' '--')"
  session_line "dddddddd-0000-0000-0000-000000000001" "$ARM" "$BRANCH" "msg-d" "$MODEL" \
    "2026-06-01T10:00:00.000Z" 100 1000 0 0 0 \
    > "$1/.claude/projects/$(printf '%s' "$ARM" | tr '/.' '--')/dddddddd-0000-0000-0000-000000000001.jsonl"
}
DRIVER_HOME="$TMP/driver-home"; ARM_HOME="$TMP/arm-home"
make_home "$DRIVER_HOME"; make_home "$ARM_HOME"
DRIVER_ANALYSIS="$CONSUMER/agentTooling/analysis"

# The arm's own copy, as run.sh used to run it: the model has no rate, so it prices $0.
HOME="$ARM_HOME" python3 -B "$ARM/agentTooling/analysis/capture_planning.py" "$SLUG" >/dev/null 2>&1
ARM_PJ="$ARM/plans/features/$SLUG/planning.json"
arm_total="$(pj "$ARM_PJ" 'd["cost_usd"]["total"]')"
check "T4b. the arm's own stale copy prices the session at \$0 (got $arm_total) — the defect" '[[ "$arm_total" == "0" || "$arm_total" == "0.0" ]]'
rm -f "$ARM_PJ"

out="$(HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/capture_planning.py" "$SLUG" --arm-root "$ARM" 2>&1)"; rc=$?
check "T4c. the driver's capture with --arm-root exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "T4d. ... and wrote the ARM's plans/features/$SLUG/planning.json, not the driver's repo" \
  '[[ -f "$ARM_PJ" && ! -e "$CONSUMER/plans/features/$SLUG" ]]'
check "T4e. ... pricing the session at the driver's rates (non-zero, session found by the worktree's project dir)" \
  '[[ "$(pj "$ARM_PJ" "d[\"cost_usd\"][\"total\"] > 0")" == "True" && "$(pj "$ARM_PJ" "[s[\"session_id\"] for s in d[\"sessions\"]]")" == "['"'"'dddddddd-0000-0000-0000-000000000001'"'"']" ]]'
HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/report.py" "$SLUG" --arm-root "$ARM" >/dev/null 2>&1; rc=$?
ARM_REPORT="$ARM/plans/features/$SLUG/report.json"
check "T4f. report.py with --arm-root writes the arm's report.json with the same non-zero total (rc $rc)" \
  '[[ $rc -eq 0 && "$(pj "$ARM_REPORT" "d[\"cost\"][\"total\"] > 0")" == "True" ]]'
HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/capture_planning.py" "$SLUG" --self --arm-root "$ARM" >/dev/null 2>&1; rc=$?
check "T4g. --arm-root with --self is a usage error (rc $rc)" '[[ $rc -eq 2 ]]'
HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/capture_planning.py" "$SLUG" --arm-root "$TMP/no-such-dir" >/dev/null 2>&1; rc=$?
check "T4h. --arm-root naming no directory is a usage error (rc $rc)" '[[ $rc -eq 2 ]]'

# ── T5. An old arm's feature directory through the driver's capture ────────────
OLD_SLUG="agenttooling-self-host"
OLD_SRC="$HERE/self/features/$OLD_SLUG"
mkdir -p "$ARM/plans/features/$OLD_SLUG"
cp -R "$OLD_SRC"/. "$ARM/plans/features/$OLD_SLUG/"
rm -f "$ARM/plans/features/$OLD_SLUG/report.json" "$ARM/plans/features/$OLD_SLUG/report.md"
OLD_PJ_BEFORE="$(cat "$ARM/plans/features/$OLD_SLUG/planning.json")"
out="$(HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/capture_planning.py" "$OLD_SLUG" --arm-root "$ARM" 2>&1)"; rc=$?
check "T5a. an August-era frozen record is honoured by the driver's capture: exit 0, no traceback (rc $rc)" \
  '[[ $rc -eq 0 ]] && ! grep -q Traceback <<<"$out"'
check "T5b. ... and left byte for byte as it was" '[[ "$(cat "$ARM/plans/features/$OLD_SLUG/planning.json")" == "$OLD_PJ_BEFORE" ]]'
out="$(HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/report.py" "$OLD_SLUG" --arm-root "$ARM" 2>&1)"; rc=$?
check "T5c. the driver's report.py reads that record: exit 0, a report.json with a cost total, no traceback (rc $rc)" \
  '[[ $rc -eq 0 && -f "$ARM/plans/features/$OLD_SLUG/report.json" ]] && ! grep -q Traceback <<<"$out" && [[ "$(pj "$ARM/plans/features/$OLD_SLUG/report.json" "\"total\" in d[\"cost\"]")" == "True" ]]'
out="$(HOME="$DRIVER_HOME" python3 -B "$DRIVER_ANALYSIS/capture_planning.py" "$OLD_SLUG" --arm-root "$ARM" --recapture 2>&1)"; rc=$?
check "T5d. --recapture of it (transcripts long gone) ends without a traceback (rc $rc)" '! grep -q Traceback <<<"$out"'

echo
if (( fails > 0 )); then echo "harness-driver-measures: $fails assertion(s) FAILED"; exit 1; fi
echo "harness-driver-measures: all assertions passed"
