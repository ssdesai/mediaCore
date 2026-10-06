#!/usr/bin/env bash
set -uo pipefail

# Self-test for the manifest fence's three removers — `analysis/manifest.py unpin-session`,
# `unpin-subagent` and `unexclude-subagent` (self/features/unpin-and-yield, spec §1). Run
# by self/gate.sh, or by hand: bash self/tests/manifest-unpin.sh
#
# Until these existed `pin-session` and `pin-subagent` only appended, so a pin written in
# error — the wave router pinned into three humanNetworkMap features — and the
# hand-written `exclude_subagents` lists could only come out by editing the fence by hand,
# which LIFECYCLE.md rule 3 forbids. Each remover is the exact inverse of its twin: same
# argument order, same output shape, same id validation, an absent id a no-op, nothing
# else in the file moved.
#
# Asserts:
#   U1. unpin-session removes the id, echoes `sessions = [...]`, exit 0, and every other
#       line of the file is byte-identical;
#   U2. pin-session then unpin-session returns the file byte-identical (the inverse);
#   U3. an id the list does not hold is a no-op: exit 0, a line saying so, file untouched;
#   U4. an empty or blank session id is refused with a plain 1, file untouched;
#   U5. unpin-subagent removes, echoes `subagents = [...]`, other lines byte-identical,
#       and pin-subagent then unpin-subagent is byte-identical;
#   U6. unpin-subagent and unexclude-subagent refuse exactly what pin-subagent refuses —
#       empty, blank, `agent-` prefix (naming the bare id), truncated, uppercase,
#       placeholder, session UUID — exit 1, file byte-identical;
#   U7. unexclude-subagent removes from a HAND-WRITTEN `exclude_subagents` (a multi-line
#       list in a fence whose other lines are not in manifest.py's own shape) and moves
#       nothing else — the case the humanNetworkMap cleanup is;
#   U8. unexclude-subagent on an absent id, or on a fence with no such key, is a no-op;
#   U9. on a feature with a planning.json, each remover prints the frozen-record note
#       (captured at, feature-capture.sh on the branch, --recapture after the merge);
#   U10. the consuming-repo layout (no --self) works the same way;
#   U11. a manifest README.md left dirty by a remover is a cost record to the close's and
#        the capture's stray check (`stray_paths`), the path pin-session relies on.
#
# RED until the removers landed: argparse exits 2 for every unknown subcommand, which is
# why the refusals assert exit 1 rather than merely non-zero. No model, no network, no git.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/manifest-unpin.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves through Path.resolve(); see capture-guard.sh.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
CONSUMER="$TMP/consumer"
mkdir -p "$AT/analysis" "$AT/self/features" "$CONSUMER/agentTooling/analysis" "$CONSUMER/plans/features"

# manifest.py imports routing, which imports pricing, roots and transcript; pricing loads
# rates_history.json from beside itself.
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
ANALYSIS_FILES=(pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py)
for f in "${ANALYSIS_FILES[@]}"; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
  cp "$HERE/analysis/$f" "$CONSUMER/agentTooling/analysis/$f"
done
mkdir -p "$AT/.git" "$CONSUMER/.git"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="unpin-target"
README="$AT/self/features/$SLUG/README.md"
CONSUMER_README="$CONSUMER/plans/features/$SLUG/README.md"
PLANNING="$AT/self/features/$SLUG/planning.json"
SESSION_1="11111111-0000-0000-0000-000000000001"
SESSION_2="22222222-0000-0000-0000-000000000002"
SESSION_3="33333333-0000-0000-0000-000000000003"
AGENT_1="abdc44b0d582d0b92"
AGENT_2="a0123456789abcdef"
AGENT_3="a3333333333333333"
CAPTURED_AT="2026-10-01T12:00:00+00:00"

# write_canonical PATH — a fence in the shape manifest.py init writes (one key per line,
# compact values), with an example fence above it that must never be mistaken for the
# manifest, and prose under it.
write_canonical() {
  mkdir -p "$(dirname "$1")"
  {
    printf '# %s\n\nFixture feature for self/tests/manifest-unpin.sh.\n\n' "$SLUG"
    printf '```json\n{"sessions": ["%s"], "example": "not the manifest"}\n```\n\n' "$SESSION_1"
    printf '```json\n{\n'
    printf '  "slug": "%s",\n' "$SLUG"
    printf '  "method": "direct",\n'
    printf '  "plans": ["01-review-opus"],\n'
    printf '  "branches": ["%s"],\n' "$SLUG"
    printf '  "base": "main",\n'
    printf '  "session_window": {"from": "2026-07-01T00:00:00Z", "to": null},\n'
    printf '  "exclude_sessions": [],\n'
    printf '  "exclude_subagents": ["%s"],\n' "$AGENT_3"
    printf '  "sessions": ["%s", "%s"],\n' "$SESSION_1" "$SESSION_2"
    printf '  "subagents": ["%s", "%s"]\n' "$AGENT_1" "$AGENT_2"
    printf '}\n```\n\nProse under the fence.\n'
  } > "$1"
}

# write_hand PATH — a fence a human wrote: keys out of manifest.py's order, extra spaces,
# a multi-line `exclude_subagents`, the shape the humanNetworkMap manifests carry.
write_hand() {
  mkdir -p "$(dirname "$1")"
  {
    printf '# %s\n\nHand-written fixture.\n\n' "$SLUG"
    printf '```json\n{\n'
    printf '  "slug":  "%s",\n' "$SLUG"
    printf '  "branches": [ "%s" ],\n' "$SLUG"
    printf '  "session_window": { "from": "2026-07-01T00:00:00Z", "to": null },\n'
    printf '  "exclude_subagents": [\n'
    printf '    "%s",\n' "$AGENT_1"
    printf '    "%s"\n' "$AGENT_2"
    printf '  ],\n'
    printf '  "subagents": [ "%s" ],\n' "$AGENT_3"
    printf '  "method": "plans"\n'
    printf '}\n```\n'
  } > "$1"
}

mf()          { HOME="$TMP/home" python3 -B "$AT/analysis/manifest.py" --self "$SLUG" "$@" 2>&1; }
mf_consumer() { HOME="$TMP/home" python3 -B "$CONSUMER/agentTooling/analysis/manifest.py" "$SLUG" "$@" 2>&1; }
# fence_of PATH EXPR — EXPR over the LAST ```json fence as `d` (chr(96)*3: three backticks
# in a double-quoted shell word are a command substitution).
fence_of() {
  python3 -c "import json,sys; t=open(sys.argv[1]).read(); m=chr(96)*3; b=t.rsplit(m + 'json', 1)[1].split(m)[0]; d=json.loads(b); print(eval(sys.argv[2]))" \
    "$1" "$2" 2>/dev/null
}
# all_but KEY PATH — the file with that fence key's line removed, so a test can say
# nothing ELSE moved.
all_but() { grep -v "^  \"$1\": " "$2"; }

echo "manifest.py unpin-session / unpin-subagent / unexclude-subagent"

# ── U1. unpin-session removes, and nothing else moves ─────────────────────────
write_canonical "$README"
all_but sessions "$README" > "$TMP/u1.rest"
out1="$(mf unpin-session "$SESSION_1")"; rc1=$?
check "U1. unpin-session exits 0 (got $rc1)" "[ $rc1 -eq 0 ]"
check "U1b. echoing the new list in pin-session's shape (got: $out1)" \
  "[ \"\$out1\" = 'sessions = [\"$SESSION_2\"]' ]"
check "U1c. the fence no longer holds it" \
  "[ \"\$(fence_of '$README' \"d['sessions']\")\" = \"['$SESSION_2']\" ]"
check "U1d. every other byte is as it was — prose, example fence (which names the id too), other keys" \
  "all_but sessions '$README' | cmp -s - '$TMP/u1.rest'"

# ── U2. pin then unpin is the identity ────────────────────────────────────────
write_canonical "$README"
cp "$README" "$TMP/u2.before"
mf pin-session "$SESSION_3" > /dev/null
out2="$(mf unpin-session "$SESSION_3")"; rc2=$?
check "U2. pin-session then unpin-session leaves the file byte-identical (rc $rc2)" \
  "[ $rc2 -eq 0 ] && cmp -s '$TMP/u2.before' '$README'"
mf unpin-session "$SESSION_2" > /dev/null
mf unpin-session "$SESSION_1" > /dev/null
check "U2b. the last id out leaves an empty list, not a missing key" \
  "[ \"\$(fence_of '$README' \"d['sessions']\")\" = '[]' ] && grep -q '^  \"sessions\": \[\],\$' '$README'"

# ── U3. an absent id is a no-op ───────────────────────────────────────────────
write_canonical "$README"
cp "$README" "$TMP/u3.before"
out3="$(mf unpin-session "$SESSION_3")"; rc3=$?
check "U3. unpin-session on an id the list does not hold exits 0 (got $rc3)" "[ $rc3 -eq 0 ]"
check "U3b. saying the list does not hold it (got: $out3)" \
  "grep -q 'sessions does not hold $SESSION_3' <<< \"\$out3\""
check "U3c. and the file is byte-identical" "cmp -s '$TMP/u3.before' '$README'"

# ── U4. an empty session id is refused ────────────────────────────────────────
for bad in "" "   "; do
  out4="$(mf unpin-session "$bad")"; rc4=$?
  check "U4 ('$bad'). an empty session id is refused with a plain 1 (got $rc4)" \
    "[ $rc4 -eq 1 ] && grep -q '^refusing:' <<< \"\$out4\""
  check "U4 ('$bad'). and the file is byte-identical" "cmp -s '$TMP/u3.before' '$README'"
done

# ── U5. unpin-subagent removes, and is pin-subagent's inverse ─────────────────
write_canonical "$README"
all_but subagents "$README" > "$TMP/u5.rest"
out5="$(mf unpin-subagent "$AGENT_1")"; rc5=$?
check "U5. unpin-subagent exits 0 (got $rc5)" "[ $rc5 -eq 0 ]"
check "U5b. echoing subagents = [...] (got: $out5)" "[ \"\$out5\" = 'subagents = [\"$AGENT_2\"]' ]"
check "U5c. and nothing else in the file moved" "all_but subagents '$README' | cmp -s - '$TMP/u5.rest'"
cp "$README" "$TMP/u5.before"
mf pin-subagent "$AGENT_3" > /dev/null
mf unpin-subagent "$AGENT_3" > /dev/null
check "U5d. pin-subagent then unpin-subagent leaves the file byte-identical" "cmp -s '$TMP/u5.before' '$README'"
out5e="$(mf unpin-subagent "$AGENT_3")"; rc5e=$?
check "U5e. an absent agent id is a no-op saying so, file untouched (rc $rc5e)" \
  "[ $rc5e -eq 0 ] && grep -q 'subagents does not hold $AGENT_3' <<< \"\$out5e\" && cmp -s '$TMP/u5.before' '$README'"

# ── U6. the id validation is pin-subagent's, for both agent-id removers ───────
write_canonical "$README"
cp "$README" "$TMP/u6.before"
u6_case() {
  local cmd="$1" label="$2" id="$3" out rc
  out="$(mf "$cmd" "$id")"; rc=$?
  check "U6 ($cmd, $label). refused with a plain 1 (got $rc)" "[ $rc -eq 1 ] && grep -q '^refusing:' <<< \"\$out\""
  check "U6 ($cmd, $label). and the file is byte-identical" "cmp -s '$TMP/u6.before' '$README'"
}
for cmd in unpin-subagent unexclude-subagent; do
  u6_case "$cmd" "empty" ""
  u6_case "$cmd" "blank" "   "
  u6_case "$cmd" "agent- prefix" "agent-$AGENT_1"
  u6_case "$cmd" "truncated" "${AGENT_1:0:16}"
  u6_case "$cmd" "uppercase" "ABDC44B0D582D0B92"
  u6_case "$cmd" "placeholder" "<agent-id>"
  u6_case "$cmd" "a session uuid" "$SESSION_1"
  out6="$(mf "$cmd" "agent-$AGENT_1")"
  pin6="$(mf pin-subagent "agent-$AGENT_1")"
  check "U6 ($cmd). the agent- refusal is pin-subagent's, word for word" \
    "grep -q 'without the .agent-. prefix: $AGENT_1' <<< \"\$out6\" && [ \"\$out6\" = \"\$pin6\" ]"
done

# ── U7. unexclude-subagent on a hand-written fence moves nothing else ─────────
write_hand "$README"
python3 -c "import sys; t=open(sys.argv[1]).read(); s=t.index('  \"exclude_subagents\": ['); e=t.index('  ],', s)+len('  ],\n'); open(sys.argv[2],'w').write(t[:s]); open(sys.argv[3],'w').write(t[e:])" \
  "$README" "$TMP/u7.head" "$TMP/u7.tail"
out7="$(mf unexclude-subagent "$AGENT_1")"; rc7=$?
check "U7. unexclude-subagent exits 0 (got $rc7)" "[ $rc7 -eq 0 ]"
check "U7b. echoing exclude_subagents = [...] (got: $out7)" \
  "[ \"\$out7\" = 'exclude_subagents = [\"$AGENT_2\"]' ]"
check "U7c. the fence no longer excludes it, and still parses" \
  "[ \"\$(fence_of '$README' \"d['exclude_subagents']\")\" = \"['$AGENT_2']\" ]"
check "U7d. every byte before the list is as it was (hand spacing, key order)" \
  "head -c \$(wc -c < '$TMP/u7.head') '$README' | cmp -s - '$TMP/u7.head'"
check "U7e. and every byte after it — the next key's odd spacing included" \
  "tail -c \$(wc -c < '$TMP/u7.tail') '$README' | cmp -s - '$TMP/u7.tail'"
check "U7f. the list itself is the only line between them" \
  "[ \$(( \$(wc -l < '$README') - \$(wc -l < '$TMP/u7.head') - \$(wc -l < '$TMP/u7.tail') )) -eq 1 ]"
mf unexclude-subagent "$AGENT_2" > /dev/null
check "U7g. the last one out leaves an empty list" \
  "[ \"\$(fence_of '$README' \"d['exclude_subagents']\")\" = '[]' ]"

# ── U8. unexclude-subagent no-ops ─────────────────────────────────────────────
write_canonical "$README"
cp "$README" "$TMP/u8.before"
out8="$(mf unexclude-subagent "$AGENT_1")"; rc8=$?
check "U8. an id exclude_subagents does not hold is a no-op saying so (rc $rc8)" \
  "[ $rc8 -eq 0 ] && grep -q 'exclude_subagents does not hold $AGENT_1' <<< \"\$out8\" && cmp -s '$TMP/u8.before' '$README'"
grep -v '"exclude_subagents"' "$TMP/u8.before" > "$README"
cp "$README" "$TMP/u8b.before"
out8b="$(mf unexclude-subagent "$AGENT_3")"; rc8b=$?
check "U8b. a fence with no exclude_subagents key at all is a no-op too, gaining no key (rc $rc8b)" \
  "[ $rc8b -eq 0 ] && grep -q 'does not hold' <<< \"\$out8b\" && cmp -s '$TMP/u8b.before' '$README'"

# ── U9. the frozen-record note ────────────────────────────────────────────────
write_canonical "$README"
printf '{"captured_at": "%s", "sessions": [], "subagents": []}\n' "$CAPTURED_AT" > "$PLANNING"
note_ok() { grep -q "captured $CAPTURED_AT" <<< "$1" && grep -q 'feature-capture.sh' <<< "$1" && grep -q -- '--recapture' <<< "$1"; }
out9a="$(mf unpin-session "$SESSION_1")"
out9b="$(mf unpin-subagent "$AGENT_1")"
out9c="$(mf unexclude-subagent "$AGENT_3")"
check "U9. unpin-session on a captured feature says the frozen figure waits for a capture" "note_ok \"\$out9a\""
check "U9b. so does unpin-subagent" "note_ok \"\$out9b\""
check "U9c. so does unexclude-subagent" "note_ok \"\$out9c\""
check "U9d. a no-op says nothing about a frozen figure it did not touch" \
  "! grep -q 'captured' <<< \"\$(mf unpin-session "$SESSION_1")\""
rm -f "$PLANNING"
out9e="$(mf unpin-session "$SESSION_2")"
check "U9e. and with no planning.json there is no note" "! grep -q 'captured' <<< \"\$out9e\""

# ── U10. the consuming-repo layout ────────────────────────────────────────────
write_canonical "$CONSUMER_README"
out10="$(mf_consumer unpin-subagent "$AGENT_2")"; rc10=$?
check "U10. without --self it unpins from plans/features/<slug> (rc $rc10)" \
  "[ $rc10 -eq 0 ] && [ \"\$(fence_of '$CONSUMER_README' \"d['subagents']\")\" = \"['$AGENT_1']\" ]"
out10b="$(mf_consumer unexclude-subagent "$AGENT_3")"; rc10b=$?
check "U10b. and unexcludes there too (rc $rc10b)" \
  "[ $rc10b -eq 0 ] && [ \"\$(fence_of '$CONSUMER_README' \"d['exclude_subagents']\")\" = '[]' ]"

# ── U11. the dirty manifest is a cost record to the stray check ───────────────
# shellcheck source=/dev/null
source "$HERE/plan-runner-roots.sh" 2>/dev/null || true
if declare -f stray_paths >/dev/null && declare -f stray_labels >/dev/null; then
  REPO_DIR="$AT"
  FEATURES_LABEL="self/features"
  stray_labels "$SLUG" "$AT"
  stray11="$(stray_paths " M self/features/$SLUG/README.md" "")"; rc11=$?
  check "U11. a remover's dirty README.md is a COST_FILES record, not stray (rc $rc11, got: $stray11)" \
    "[ $rc11 -eq 0 ] && [ -z \"\$stray11\" ]"
else
  fail "U11. plan-runner-roots.sh did not define stray_paths/stray_labels"
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "manifest-unpin: all checks passed"
else
  echo "manifest-unpin: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
