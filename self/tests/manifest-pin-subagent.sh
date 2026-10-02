#!/usr/bin/env bash
set -uo pipefail

# Self-test for `analysis/manifest.py pin-subagent` — the only sanctioned writer of a
# manifest's `subagents[]` (self/features/manifest-pin-subagent). Run by self/gate.sh, or
# by hand: bash self/tests/manifest-pin-subagent.sh
#
# A coordinator launched outside a feature's worktree — one session running a wave of
# features — spawns delegates whose transcripts carry ITS branch, so each is claimed only
# by a pin in the feature's `subagents` (LIFECYCLE.md rule 1). Until this command the only
# writer of that list was a hand edit of the fence, which rule 3 forbids. `pin-session` is
# the pattern mirrored: append once, a repeat writes nothing, a bad id is refused with the
# fence untouched.
#
# The id shape is not guessed: every agent id Claude Code has written — the
# `agent-<id>.jsonl` filenames `capture_planning.py --list-subagents` reads, and the
# `agentId` on their lines — is 17 lowercase hex characters (`abdc44b0d582d0b92`). The
# fixtures here and in subagent-capture.sh are that shape too.
#
# Asserts:
#   P1. a pin is appended, echoed as the new list, and nothing else in the fence moves;
#   P2. the same id again is a no-op, exit 0, the file byte-identical;
#   P3. a second id is appended after the first, in order;
#   P4. an empty, blank, `agent-`-prefixed, truncated, uppercase, placeholder or
#       session-UUID id is refused with a plain 1, and the file is byte-identical;
#   P5. a fence with no `subagents` key gains one;
#   P6. the consuming-repo layout (no --self, plans/features/) works the same way;
#   P7. a capture then claims the pinned delegate — one spawned from a coordinator on
#       `main`, which no branch route can ever reach — as `pinned`, where before the pin
#       it claimed nothing;
#   P8. `--list-subagents --unclaimed --for` names this command in its advice line, and
#       drops the delegate once it is pinned;
#   P9. capture_planning has no parse_manifest of its own: it IS routing.parse_manifest.
#
# RED until `pin-subagent` landed (argparse exits 2 for every P1-P7 call, which is why
# the refusals assert exit 1 rather than merely non-zero) and, for P9, until the fold.
# The end-to-end half — feature-capture.sh's own warning naming the command, and its
# capture then claiming the pinned delegate on the branch — is feature-lifecycle.sh C1i
# and C2f-C2i. No model, no network, no git.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pin-subagent.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Physical path — roots.py resolves through Path.resolve(); see capture-guard.sh.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
CONSUMER="$TMP/consumer"
mkdir -p "$AT/analysis" "$AT/self/features" "$CONSUMER/agentTooling/analysis" "$CONSUMER/plans/features"

# manifest.py and capture_planning.py both import routing, which imports pricing, roots
# and transcript; pricing loads rates_history.json from beside itself.
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
ANALYSIS_FILES=(pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py capture_planning.py)
for f in "${ANALYSIS_FILES[@]}"; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
  cp "$HERE/analysis/$f" "$CONSUMER/agentTooling/analysis/$f"
done
# session_root() walks up for the nearest ancestor holding .git; without one it would
# escape the sandbox and resolve to a real repo above it.
mkdir -p "$AT/.git" "$CONSUMER/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="pin-target"
README="$AT/self/features/$SLUG/README.md"
CONSUMER_README="$CONSUMER/plans/features/$SLUG/README.md"
PLANNING="$AT/self/features/$SLUG/planning.json"
REPO_NAME="$(basename "$AT")"
MODEL="claude-sonnet-5"
AGENT_1="abdc44b0d582d0b92"
AGENT_2="a0123456789abcdef"
SESSION_UUID="mmmmmmmm-0000-0000-0000-000000000001"
SESSION_M="$SESSION_UUID"   # a coordinator on main: its delegates carry `main`
WINDOW_FROM="2026-07-01T00:00:00Z"
WINDOW_TO="2026-07-05T00:00:00Z"
T_M="2026-07-02T10:00:00.000Z"
T_D="2026-07-02T10:30:00.000Z"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS"

# write_manifest PATH [SUBAGENTS_LINE] — a fence in the shape manifest.py init writes,
# with a prose fence above it that must never be mistaken for the manifest. The optional
# second argument replaces the whole `subagents` line; P5 passes nothing-at-all for it.
write_manifest() {
  local path="$1" subagents_line="${2-  \"subagents\": []}"
  mkdir -p "$(dirname "$path")"
  {
    printf '# %s\n\nFixture feature for self/tests/manifest-pin-subagent.sh.\n\n' "$SLUG"
    printf '```json\n{"example": "not the manifest"}\n```\n\n'
    printf '```json\n{\n'
    printf '  "slug": "%s",\n' "$SLUG"
    printf '  "method": "direct",\n'
    printf '  "plans": ["01-review-opus"],\n'
    printf '  "branches": ["%s"],\n' "$SLUG"
    printf '  "base": "main",\n'
    printf '  "session_window": {"from": "%s", "to": "%s"},\n' "$WINDOW_FROM" "$WINDOW_TO"
    printf '  "exclude_sessions": [],\n'
    printf '  "exclude_subagents": [],\n'
    if [[ -n "$subagents_line" ]]; then
      printf '  "sessions": [],\n'
      printf '%s\n' "$subagents_line"
    else
      printf '  "sessions": []\n'
    fi
    printf '}\n```\n\nProse under the fence.\n'
  } > "$path"
}

pin()          { HOME="$FAKE_HOME" python3 -B "$AT/analysis/manifest.py" --self "$SLUG" pin-subagent "$@" 2>&1; }
pin_consumer() { HOME="$FAKE_HOME" python3 -B "$CONSUMER/agentTooling/analysis/manifest.py" "$SLUG" pin-subagent "$@" 2>&1; }
capture()      { HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self "$SLUG" --recapture 2>&1; }
list_unclaimed() {
  HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self --list-subagents --unclaimed \
    --for "$REPO_NAME/$SLUG" 2>&1
}
# fence_of PATH EXPR — EXPR evaluated over the LAST ```json fence as `d`. The fence marker
# is spelled chr(96)*3: three backticks in a double-quoted shell word are a command
# substitution.
fence_of() {
  python3 -c "import json,sys; t=open(sys.argv[1]).read(); m=chr(96)*3; b=t.rsplit(m + 'json', 1)[1].split(m)[0]; d=json.loads(b); print(eval(sys.argv[2]))" \
    "$1" "$2" 2>/dev/null
}
# everything_but_subagents PATH — the file with the fence's subagents line removed, so P1
# can say nothing ELSE moved. The prose, the example fence and every other key must match.
everything_but_subagents() { grep -v '^  "subagents": ' "$1"; }
planning_field() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$PLANNING" "$1" 2>/dev/null; }

echo "manifest.py pin-subagent"

# ── P1. a pin is appended, and nothing else moves ─────────────────────────────
write_manifest "$README"
everything_but_subagents "$README" > "$TMP/before-p1.rest"
out1="$(pin "$AGENT_1")"; rc1=$?
check "P1. pin-subagent exits 0 (got $rc1)" "[ $rc1 -eq 0 ]"
check "P1b. and echoes the new list, pin-session's shape" "[ \"\$out1\" = 'subagents = [\"$AGENT_1\"]' ]"
check "P1c. the fence carries the id" "[ \"\$(fence_of '$README' \"d['subagents']\")\" = \"['$AGENT_1']\" ]"
check "P1d. and every other byte of the file is as it was — prose, example fence, other keys" \
  "everything_but_subagents '$README' | cmp -s - '$TMP/before-p1.rest'"

# ── P2. the same id again writes nothing ──────────────────────────────────────
cp "$README" "$TMP/before-p2.md"
out2="$(pin "$AGENT_1")"; rc2=$?
check "P2. a repeat pin is a no-op, exit 0 (got $rc2)" "[ $rc2 -eq 0 ]"
check "P2b. saying the id is already pinned" "grep -q 'subagents already pins $AGENT_1' <<< \"\$out2\""
check "P2c. and the file is byte-identical" "cmp -s '$TMP/before-p2.md' '$README'"

# ── P3. a second id is appended after the first ───────────────────────────────
out3="$(pin "$AGENT_2")"; rc3=$?
check "P3. a second id is appended in order (got $rc3)" \
  "[ $rc3 -eq 0 ] && [ \"\$(fence_of '$README' \"d['subagents']\")\" = \"['$AGENT_1', '$AGENT_2']\" ]"

# ── P4. a malformed id is refused and the fence is untouched ──────────────────
# Each is a mistake a human pasting from some other output would plausibly make: the
# `agent-<id>` form `manifest.py claimed` and the frozen-cost guard print, a column cut
# short, a session id from `--list-sessions`, the template's own placeholder.
cp "$README" "$TMP/before-p4.md"
p4_case() {
  local label="$1" id="$2" out rc
  out="$(pin "$id")"; rc=$?
  check "P4 ($label). refused with a plain 1 (got $rc)" "[ $rc -eq 1 ] && grep -q '^refusing:' <<< \"\$out\""
  check "P4 ($label). and the file is byte-identical" "cmp -s '$TMP/before-p4.md' '$README'"
}
p4_case "empty" ""
p4_case "blank" "   "
p4_case "agent- prefix" "agent-$AGENT_1"
p4_case "truncated" "${AGENT_1:0:16}"
p4_case "uppercase" "ABDC44B0D582D0B92"
p4_case "placeholder" "<agent-id>"
p4_case "a session uuid" "$SESSION_UUID"
out4="$(pin "agent-$AGENT_1")"
check "P4h. the agent- refusal says which part to drop" "grep -q 'without the .agent-. prefix' <<< \"\$out4\""

# ── P5. a fence with no subagents key gains one ───────────────────────────────
write_manifest "$README" ""
out5="$(pin "$AGENT_1")"; rc5=$?
check "P5. a fence with no subagents key gains one holding the id (got $rc5)" \
  "[ $rc5 -eq 0 ] && [ \"\$(fence_of '$README' \"d['subagents']\")\" = \"['$AGENT_1']\" ]"

# ── P6. the consuming-repo layout ─────────────────────────────────────────────
write_manifest "$CONSUMER_README"
out6="$(pin_consumer "$AGENT_1")"; rc6=$?
check "P6. without --self it pins into plans/features/<slug> (got $rc6)" \
  "[ $rc6 -eq 0 ] && [ \"\$(fence_of '$CONSUMER_README' \"d['subagents']\")\" = \"['$AGENT_1']\" ]"
cp "$CONSUMER_README" "$TMP/before-p6.md"
pin_consumer "$AGENT_1" > /dev/null
check "P6b. and a repeat there is byte-identical too" "cmp -s '$TMP/before-p6.md' '$CONSUMER_README'"

# ── P7. a capture then claims the pinned delegate ─────────────────────────────
# A coordinator on `main` and one delegate it spawned for this feature. The delegate
# inherits `main`, so neither the branch route nor the parent route can ever reach it.
write_manifest "$README"
session_line "$SESSION_M" "$AT" "main" "msg-m" "$MODEL" "$T_M" 100 1000 0 0 0 > "$PROJECTS/$SESSION_M.jsonl"
mkdir -p "$PROJECTS/$SESSION_M/subagents"
{
  subagent_prompt_line "$SESSION_M" "$AGENT_1" "$AT" "main" "$T_D" "feature: $REPO_NAME/$SLUG\\nbuild it"
  subagent_line "$SESSION_M" "$AGENT_1" "$AT" "main" "msg-d" "$MODEL" "$T_D" 100 2000 0 0 0
} > "$PROJECTS/$SESSION_M/subagents/agent-$AGENT_1.jsonl"

out8a="$(list_unclaimed)"
capture > "$TMP/out7a.txt"
check "P7. before the pin the capture matches nothing, refuses the \$0.00 record and writes none" \
  "grep -q 'no session and no subagent matched' '$TMP/out7a.txt' && [ ! -e '$PLANNING' ]"
pin "$AGENT_1" > /dev/null
capture > "$TMP/out7b.txt"; rc7=$?
check "P7b. after it, the capture exits 0 (got $rc7)" "[ $rc7 -eq 0 ]"
check "P7c. and claims the delegate as pinned, under its real parent" \
  "[ \"\$(planning_field \"[(s['agent_id'], s['selected_by'], s['parent_session_id']) for s in d['subagents']]\")\" = \"[('$AGENT_1', 'pinned', '$SESSION_M')]\" ]"
check "P7d. its coordinator stays out of sessions[] — the pin claims the delegate alone" \
  "[ \"\$(planning_field \"[s['session_id'] for s in d['sessions']]\")\" = '[]' ]"

# ── P8. the unclaimed listing names the command, then drops the pinned one ────
# Its listing BEFORE the pin is the guard: a delegate the listing never held would satisfy
# P8c on its own.
check "P8. before the pin, the unclaimed listing for this feature holds the delegate" "grep -q '$AGENT_1' <<< \"\$out8a\""
check "P8b. and its advice names pin-subagent rather than a hand edit of the fence" \
  "grep -q 'pin-subagent' <<< \"\$out8a\""
out8c="$(list_unclaimed)"
check "P8c. after the pin and the capture, the delegate is no longer listed" "! grep -q '$AGENT_1' <<< \"\$out8c\""

# ── P9. one parse_manifest, routing's ─────────────────────────────────────────
identity="$(cd "$AT/analysis" && python3 -B -c 'import capture_planning, routing; print(capture_planning.parse_manifest is routing.parse_manifest)' 2>&1)"
check "P9. capture_planning.parse_manifest is routing.parse_manifest (got $identity)" "[ '$identity' = 'True' ]"

echo
if [ "$fails" -eq 0 ]; then
  echo "manifest-pin-subagent: all checks passed"
else
  echo "manifest-pin-subagent: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
