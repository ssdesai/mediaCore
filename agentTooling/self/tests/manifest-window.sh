#!/usr/bin/env bash
set -uo pipefail

# Self-test for `analysis/manifest.py set-window-from` — the head's remedy
# (self/DESIGN-2026-09-18-ledger-and-routing.md §4). Run by self/gate.sh, or by hand:
# bash self/tests/manifest-window.sh
#
# `set-window-to`'s own cases are `feature-lifecycle.sh`'s W phases, where they belong:
# they are asserted through a real capture, which is where that bound comes from. This
# file is the `from` side, which has no capture in it at all — nothing derives a `from`,
# a human types it — so it drives the command directly against a fence and a transcript
# and asserts the four answers it can give.
#
# The rule under test: `from` moves BACK, never forwards, and never behind the first
# instant of the session whose unclaimed head it is being moved over. That session is
# named with `--session`, its transcript is found by the same glob `routing.find_transcript`
# uses, and `manifest.py` imports `routing` for it and never `capture_planning` (which
# reads this fence on every capture; the reader must not import its writer).
#
# Asserts:
#   M1. a `from` moved back is applied and echoed old -> new, with `to` untouched;
#   M2. an instant before the session's first timestamped instant is refused, naming that
#       instant, leaving the fence byte-identical;
#   M3. a LATER instant is refused — narrowing is not this command's job — and the message
#       says which command is not it either, leaving the fence byte-identical;
#   M4. the instant already written is a no-op, exit 0, nothing rewritten;
#   M5. a session no transcript carries is refused: the guard cannot be evaluated, and a
#       guard that cannot be evaluated is not waived;
#   M6. on a feature already captured the move is applied AND the output says --recapture
#       is what moves the figure;
#   M7. a fence whose `from` is null is refused — there is no bound to move back;
#   M8. --session is required (argparse's own usage error, exit 2).
#
# Every one of these was RED until `set-window-from` landed: the subcommand did not exist,
# and argparse exited 2 for all of them, which is why M1-M7 assert exit 1 (or 0) and a
# message rather than merely "non-zero".
#
# No model, no network, no git.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path, not the symlinked one — roots.py resolves AGENT_TOOLING_DIR with
# Path.resolve(), so on macOS an unresolved /var/... fixture path matches no transcript.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

# manifest.py imports routing, which imports pricing, roots and transcript.
for f in pricing.py rates_history.json roots.py transcript.py routing.py manifest.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

# session_root() walks up for the nearest ancestor holding .git; without one it would
# escape the sandbox and resolve to a real repo above /tmp.
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

SLUG="head-remedy"
FEATURE_DIR="$AT/self/features/$SLUG"
README="$FEATURE_DIR/README.md"
PLANNING="$FEATURE_DIR/planning.json"
BRANCH="someFeatureBranch"
MODEL="claude-sonnet-5"
SESSION="ssssssss-0000-0000-0000-000000000001"
UNKNOWN_SESSION="dddddddd-0000-0000-0000-00000000000d"
# The session's own first and last instants. The head this command exists to cover begins
# at the first of them, which is also the earliest bound the command accepts.
SESSION_FIRST="2026-06-10T09:00:00Z"
SESSION_LAST="2026-06-10T11:00:00Z"
WINDOW_FROM="2026-06-10T12:00:00Z"
WINDOW_TO="2026-06-10T20:00:00Z"
BEFORE_SESSION="2026-06-10T08:00:00Z"
LATER_THAN_FROM="2026-06-10T13:00:00Z"
INSIDE="2026-06-10T10:00:00Z"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS" "$FEATURE_DIR"

# write_manifest [FROM_JSON] — the feature README whose last ```json fence manifest.py
# edits. FROM_JSON defaults to the quoted WINDOW_FROM; M7 passes a bare `null`.
write_manifest() {
  local from_json="${1:-\"$WINDOW_FROM\"}"
  cat > "$README" <<MANIFEST
# $SLUG

Fixture feature for self/tests/manifest-window.sh.

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": $from_json, "to": "$WINDOW_TO"},
  "exclude_sessions": [],
  "sessions": ["$SESSION"],
  "subagents": []
}
\`\`\`
MANIFEST
}

{
  session_line "$SESSION" "$AT" "$BRANCH" "m0" "$MODEL" "$SESSION_FIRST" 100 1000 0 0 0
  session_line "$SESSION" "$AT" "$BRANCH" "m1" "$MODEL" "$SESSION_LAST" 100 2000 0 0 0
} > "$PROJECTS/$SESSION.jsonl"

set_from() {
  HOME="$FAKE_HOME" python3 "$AT/analysis/manifest.py" --self "$SLUG" set-window-from "$@" 2>&1
}
# fence_field KEY — one session_window bound as the fence carries it, JSON null included.
# The fence marker is spelled chr(96)*3 rather than written out: three backticks inside a
# double-quoted shell word are a command substitution, and the shell would run the fence.
fence_field() {
  python3 -c "import json,sys; t=open(sys.argv[1]).read(); m=chr(96)*3; b=t.rsplit(m + 'json', 1)[1].split(m)[0]; v=json.loads(b)['session_window'][sys.argv[2]]; print('null' if v is None else v)" \
    "$README" "$1"
}

echo "manifest.py set-window-from"

# ── M1. a `from` moved back is applied and echoed ─────────────────────────────
write_manifest
out1="$(set_from "$SESSION_FIRST" --session "$SESSION")"; rc1=$?
check "M1. moving the from bound back to the session's first instant is applied (exit 0)" "[ $rc1 -eq 0 ]"
check "M1b. and echoed old -> new" \
  "[ \"$out1\" = \"session_window.from moved back: $WINDOW_FROM -> $SESSION_FIRST\" ]"
check "M1c. the fence carries the new bound" "[ \"$(fence_field from)\" = '$SESSION_FIRST' ]"
check "M1d. and the to bound is untouched" "[ \"$(fence_field to)\" = '$WINDOW_TO' ]"

# ── M2. earlier than the session's own first instant is refused ───────────────
write_manifest
cp "$README" "$TMP/before-m2.md"
out2="$(set_from "$BEFORE_SESSION" --session "$SESSION")"; rc2=$?
check "M2. an instant before the session's first is refused with a plain 1" "[ $rc2 -eq 1 ]"
check "M2b. naming the session and the instant it starts at" \
  "grep -q '$SESSION' <<< \"\$out2\" && grep -q '$SESSION_FIRST' <<< \"\$out2\""
check "M2c. and the manifest is left byte-identical" "cmp -s '$TMP/before-m2.md' '$README'"

# ── M3. a later instant is refused, and the message says nothing narrows ──────
cp "$README" "$TMP/before-m3.md"
out3="$(set_from "$LATER_THAN_FROM" --session "$SESSION")"; rc3=$?
check "M3. a later instant is refused with a plain 1" "[ $rc3 -eq 1 ]"
check "M3b. saying this command only moves the bound back" "grep -q 'only ever moves .from. BACK' <<< \"\$out3\""
check "M3c. and naming set-window-to as the one that is not it either" \
  "grep -q 'set-window-to' <<< \"\$out3\" && grep -q 'Nothing narrows' <<< \"\$out3\""
check "M3d. the manifest is left byte-identical" "cmp -s '$TMP/before-m3.md' '$README'"

# ── M4. the instant already written is a no-op ────────────────────────────────
cp "$README" "$TMP/before-m4.md"
out4="$(set_from "$WINDOW_FROM" --session "$SESSION")"; rc4=$?
check "M4. the bound already written is a no-op, exit 0" \
  "[ $rc4 -eq 0 ] && grep -q 'already $WINDOW_FROM; left alone' <<< \"\$out4\""
check "M4b. and nothing is rewritten" "cmp -s '$TMP/before-m4.md' '$README'"

# ── M5. a session no transcript carries is refused ────────────────────────────
cp "$README" "$TMP/before-m5.md"
out5="$(set_from "$INSIDE" --session "$UNKNOWN_SESSION")"; rc5=$?
check "M5. a session with no transcript is refused rather than waived" \
  "[ $rc5 -eq 1 ] && grep -q 'no transcript for session' <<< \"\$out5\""
check "M5b. naming the id it looked for" "grep -q '$UNKNOWN_SESSION' <<< \"\$out5\""
check "M5c. and the manifest is left byte-identical" "cmp -s '$TMP/before-m5.md' '$README'"

# ── M6. on a captured feature the move says --recapture ───────────────────────
printf '{"captured_at": "2026-06-11T00:00:00+00:00", "sessions": [], "subagents": []}\n' > "$PLANNING"
out6="$(set_from "$INSIDE" --session "$SESSION")"; rc6=$?
check "M6. the move is still applied on a captured feature" \
  "[ $rc6 -eq 0 ] && [ \"$(fence_field from)\" = '$INSIDE' ]"
check "M6b. and the output says --recapture is what moves the figure" \
  "grep -q 'recapture' <<< \"\$out6\" && grep -q 'captured 2026-06-11' <<< \"\$out6\""
rm -f "$PLANNING"

# ── M7. a null `from` has no bound to move back ───────────────────────────────
write_manifest null
cp "$README" "$TMP/before-m7.md"
out7="$(set_from "$INSIDE" --session "$SESSION")"; rc7=$?
check "M7. a null from bound is refused — there is nothing to move" \
  "[ $rc7 -eq 1 ] && grep -q 'no bound to move back' <<< \"\$out7\""
check "M7b. and the manifest is left byte-identical" "cmp -s '$TMP/before-m7.md' '$README'"

# ── M8. --session is not optional ─────────────────────────────────────────────
write_manifest
out8="$(set_from "$SESSION_FIRST")"; rc8=$?
check "M8. --session is required, and its absence is argparse's usage error (exit 2)" \
  "[ $rc8 -eq 2 ] && grep -q 'session' <<< \"\$out8\""

echo
if [ "$fails" -eq 0 ]; then
  echo "manifest-window: all checks passed"
else
  echo "manifest-window: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
