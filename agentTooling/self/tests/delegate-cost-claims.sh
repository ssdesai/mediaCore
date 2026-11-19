#!/usr/bin/env bash
set -uo pipefail

# Self-test for delegate cost claims (self/features/delegate-cost-claims): the brief header
# is one definition (hooks/brief_header.py), the capture auto-claims an unclaimed delegate
# whose brief names the feature it is capturing, and `capture_planning.py --claim-check`
# tells the close whether the build is claimed — and, when it is not, which sessions and
# delegates it saw and the pin for each. Run by self/gate.sh, or by hand:
# bash self/tests/delegate-cost-claims.sh
#
# Same scaffolding as subagent-capture.sh: a throwaway agentTooling checkout under
# mktemp -d with the analysis scripts and hooks/brief_header.py, synthesized manifests, and
# under a redirected $HOME the transcripts the capture reads. No model, no network.
#
# Asserts:
#   B1. the header grammar: `feature: <repo>/<slug>` and `feature: none — <reason>` (em
#       dash, en dash, `-`, `--`) on the first non-empty line are headers; a trailing remark
#       after the slug, a missing slash, a `none` with no reason, and a header below the
#       first line are not; feature_lines finds every header line of a brief;
#   A1. a capture auto-claims the unclaimed delegate whose brief opens
#       `feature: agentTooling/<slug>` — through manifest.py pin-subagent, the fence's
#       `subagents` now naming it — and says so; the record prices it as `pinned`;
#   A2. ... and one whose repo half differs only in case (the listing's rule);
#   A3. it does not claim a `<slug>-two` brief (a partial slug), a header with a trailing
#       remark, a brief that names this feature on its first line and another further down
#       (ambiguous), a delegate another feature's manifest pins, one the ledger holds for
#       another feature, a headerless one, or one this feature excludes;
#   A4. a second capture pins nothing new and the fence is unchanged;
#   A5. a delegate briefed for the feature whose parent is a runner session is not pinned
#       (its cost is in the runner's usage.json), and the capture warns of no pinned
#       subagent matching no transcript;
#   A6. a delegate briefed for the feature whose parent the capture selects (a session on
#       the feature's branch) is not pinned, and is priced through that parent;
#   K1. --claim-check on a feature whose build is claimed exits 0 and writes nothing;
#   K2. --claim-check on a feature that claims nothing but met a manually excluded session
#       on its branch and an unclaimed headerless delegate in its window exits 5, naming
#       the excluded session with its `pin-session` command and the delegate with its exact
#       `manifest.py --self <slug> pin-subagent <id>` command, and writes nothing — not
#       even the auto-claim, which it only reports;
#   K7. a feature built entirely by runners (runner sessions on its branch, cost in
#       usage.json) is claimed: --claim-check exits 0, and the real capture of the same
#       fixture agrees — it exits 0 and writes the evidenced zero;
#   K3. ... while a delegate briefed for ANOTHER feature, and one that started before the
#       window, are not named;
#   K4. --claim-check counts a delegate the capture WOULD auto-claim as claimed (exit 0,
#       saying it would pin it) and leaves the fence untouched;
#   K5. a feature that claims nothing and meets nothing exits 0 — the capture's own
#       refusal is what speaks for it;
#   K6. an unclaimed session in the primary on main, in the window, is named with its
#       `pin-session` command;
#   R1. `manifest.py allow-unclaimed` refuses an empty reason and writes nothing;
#   R2. ... and writes a reason into the fence as `allow_unclaimed`;
#   R3. the capture copies it into planning.json;
#   R4. report.py prints it among the report's warnings.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/hooks" "$AT/self/features"
mkdir -p "$AT/hooks" && cp "$HERE/hooks/shared_rules.py" "$AT/hooks/"  # roots.py imports it

export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
for f in pricing.py litellm_prices.py rates_history.json roots.py transcript.py capture_planning.py routing.py manifest.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done
cp "$HERE/hooks/brief_header.py" "$AT/hooks/brief_header.py"
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
ELSEWHERE="$FAKE_HOME/.claude/projects/-home-user"
mkdir -p "$PROJECTS" "$ELSEWHERE"
MODEL="claude-sonnet-5"
WINDOW_FROM="2026-07-01T00:00:00Z"
T_IN="2026-07-02T10:00:00.000Z"
T_BEFORE="2026-06-20T10:00:00.000Z"
# The coordinator, launched outside any repo (a cloud container's /home/user): its delegates
# record branch HEAD, so no branch selects them.
COORD="c0c0c0c0-0000-0000-0000-000000000001"
COORD_CWD="/home/user"
mkdir -p "$ELSEWHERE/$COORD/subagents"
session_line "$COORD" "$COORD_CWD" "HEAD" "msg-coord" "$MODEL" "$T_IN" 100 100 0 0 0 > "$ELSEWHERE/$COORD.jsonl"

# write_manifest <slug> <branch> <subagents-json> [exclude_subagents-json] [sessions-json]
#                [exclude_sessions-json]
write_manifest() {
  mkdir -p "$AT/self/features/$1"
  cat > "$AT/self/features/$1/README.md" <<MANIFEST
# $1

Fixture feature for self/tests/delegate-cost-claims.sh.

\`\`\`json
{
  "slug": "$1",
  "method": "direct",
  "plans": [],
  "branches": ["$2"],
  "base": "main",
  "session_window": {"from": "$WINDOW_FROM", "to": null},
  "exclude_sessions": ${6:-[]},
  "exclude_subagents": ${4:-[]},
  "sessions": ${5:-[]},
  "subagents": $3
}
\`\`\`
MANIFEST
}
# delegate <agent-id> <timestamp> <brief> — one delegate of the coordinator, its brief the
# opening user line (`\n` for a line break, as the transcript stores it).
delegate() {
  {
    subagent_prompt_line "$COORD" "$1" "$COORD_CWD" "HEAD" "$2" "$3"
    subagent_line "$COORD" "$1" "$COORD_CWD" "HEAD" "msg-$1" "$MODEL" "$2" 100 2000 0 0 0
  } > "$ELSEWHERE/$COORD/subagents/agent-$1.jsonl"
}
fence() {
  python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
capture() { HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self "$@" 2>&1; }

echo "delegate-cost-claims"

# ── B1. the header grammar ───────────────────────────────────────────────────
B_OUT="$(python3 -B - "$AT/hooks" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import brief_header as b
cases = [
    ("feature: agentTooling/x\nbody", ("feature", "agentTooling", "x")),
    ("\n\n  feature: musicMap/a-b.c  \nbody", ("feature", "musicMap", "a-b.c")),
    ("feature: none — read-only analysis", ("none", "read-only analysis")),
    ("feature: none – audit", ("none", "audit")),
    ("feature: none - audit", ("none", "audit")),
    ("feature: none -- audit", ("none", "audit")),
    ("feature: agentTooling/x (setup; read the rest)", None),
    ("feature: x", None),
    ("feature: none", None),
    ("feature: none — ", None),
    ("Build it.\nfeature: agentTooling/x", None),
    ("", None),
]
for text, want in cases:
    got = b.parse(text)
    print("%s %r -> %r" % ("ok" if got == want else "BAD", text, got))
print("%s feature_of" % ("ok" if b.feature_of("feature: r/s\n") == ("r", "s") and b.feature_of("feature: none - x") is None else "BAD"))
lines = b.feature_lines("feature: r/s\nmore\n  feature: r/t\nfeature: r/u (x)")
print("%s feature_lines %r" % ("ok" if lines == [("r", "s"), ("r", "t")] else "BAD", lines))
PY
)"
check "B1. the header grammar holds every case (got: $(grep BAD <<<"$B_OUT" | head -3))" \
  '[[ -n "$B_OUT" ]] && ! grep -q BAD <<<"$B_OUT"'

# ── K5. nothing claimed and nothing met — before any delegate exists ──────────
write_manifest "empty" "claude/empty" "[]"
oute="$(capture --claim-check empty)"; rce=$?
check "K5. a feature with nothing claimed and nothing met exits 0 (got $rce: $oute)" '[[ $rce -eq 0 ]]'

# ── A. auto-claim during capture ──────────────────────────────────────────────
SLUG="feat"
FD="$AT/self/features/$SLUG"
A_OK="a0000000000000001"
A_CASE="a0000000000000002"
A_TWO="a0000000000000003"
A_TRAIL="a0000000000000004"
A_AMBIG="a0000000000000005"
A_OTHERPIN="a0000000000000006"
A_LEDGER="a0000000000000007"
A_NONE="a0000000000000008"
A_EXCL="a0000000000000009"
write_manifest "$SLUG" "claude/$SLUG" "[]" "[\"$A_EXCL\"]"
write_manifest "other" "claude/other" "[\"$A_OTHERPIN\"]"
delegate "$A_OK" "$T_IN" "feature: agentTooling/$SLUG\\nbuild it"
delegate "$A_CASE" "$T_IN" "feature: agenttooling/$SLUG\\nbuild part of it"
delegate "$A_TWO" "$T_IN" "feature: agentTooling/$SLUG-two\\nbuild the other one"
delegate "$A_TRAIL" "$T_IN" "feature: agentTooling/$SLUG (setup; read on)\\nbuild"
delegate "$A_AMBIG" "$T_IN" "feature: agentTooling/$SLUG\\nthen\\nfeature: agentTooling/other"
delegate "$A_OTHERPIN" "$T_IN" "feature: agentTooling/$SLUG\\npinned by other"
delegate "$A_LEDGER" "$T_IN" "feature: agentTooling/$SLUG\\nclaimed elsewhere"
delegate "$A_NONE" "$T_IN" "Build something with no header."
delegate "$A_EXCL" "$T_IN" "feature: agentTooling/$SLUG\\nexcluded here"
mkdir -p "$FAKE_HOME/.claude"
printf '{"subagents": {"%s": {"repo": "https://example.invalid/elsewhere.git", "repo_name": "elsewhere", "slug": "theirs", "selected_by": "parent", "cost_usd": 1.0, "claimed_at": "2026-07-03T00:00:00Z"}}, "sessions": {}}\n' \
  "$A_LEDGER" > "$FAKE_HOME/.claude/subagent-claims.json"

out="$(capture "$SLUG")"; rc=$?
claimed_ids="$(fence "$FD/README.md" "sorted(d['subagents'])")"
check "A1. the capture exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "A1b. ... and pins the delegate briefed for agentTooling/$SLUG into the fence (got $claimed_ids)" \
  'grep -q "$A_OK" <<<"$claimed_ids"'
check "A1c. ... saying it did, by id and by the pin command it ran" \
  'grep "auto-claim" <<<"$out" | grep -q "$A_OK" && grep "auto-claim" <<<"$out" | grep -q "pin-subagent"'
check "A1d. ... and the record prices it as pinned" \
  '[[ "$(pj "$FD/planning.json" "[a[\"selected_by\"] for a in d[\"subagents\"] if a[\"agent_id\"]==\"$A_OK\"]")" == "['"'"'pinned'"'"']" ]]'
check "A2. the delegate whose repo half differs only in case is claimed too" \
  'grep -q "$A_CASE" <<<"$claimed_ids"'
for pair in "A_TWO:a <slug>-two brief" "A_TRAIL:a header with a trailing remark" \
            "A_AMBIG:a brief naming two features" "A_OTHERPIN:a delegate another manifest pins" \
            "A_LEDGER:a delegate the ledger holds for another feature" "A_NONE:a headerless brief" \
            "A_EXCL:a delegate this feature excludes"; do
  var="${pair%%:*}"; what="${pair#*:}"; id="${!var}"
  check "A3. $what is not auto-claimed ($id)" '! grep -q "$id" <<<"$claimed_ids"'
done
check "A3b. ... the ambiguous one and the one pinned elsewhere are named with the reason they were left" \
  'grep "$A_AMBIG" <<<"$out" | grep -qi "ambiguous" && grep "$A_OTHERPIN" <<<"$out" | grep -q "other"'
cp "$FD/README.md" "$TMP/feat-after-first"
out2="$(capture "$SLUG" --recapture)"; rc2=$?
check "A4. a second capture exits 0, pins nothing new and leaves the fence as it was (got $rc2)" \
  '[[ $rc2 -eq 0 ]] && cmp -s "$TMP/feat-after-first" "$FD/README.md" && ! grep -q "auto-claim pinned" <<<"$out2"'

# ── K. --claim-check, the close's question ───────────────────────────────────
outk="$(capture --claim-check "$SLUG")"; rck=$?
check "K1. --claim-check on a feature whose build is claimed exits 0 (got $rck: $outk)" \
  '[[ $rck -eq 0 ]] && cmp -s "$TMP/feat-after-first" "$FD/README.md"'

ZERO="zero"
ZFD="$AT/self/features/$ZERO"
MANUAL="e0e0e0e0-0000-0000-0000-000000000002"
Z_HEADLESS="b0000000000000001"
Z_OTHER="b0000000000000002"
Z_EARLY="b0000000000000003"
write_manifest "$ZERO" "claude/$ZERO" "[]" "[]" "[]" "[\"$MANUAL\"]"
session_line "$MANUAL" "$AT" "claude/$ZERO" "msg-manual" "$MODEL" "$T_IN" 100 100 0 0 0 > "$PROJECTS/$MANUAL.jsonl"
delegate "$Z_HEADLESS" "$T_IN" "Build four fixes, no header."
delegate "$Z_OTHER" "$T_IN" "feature: vinylCatalogue/elsewhere\\nnot this one"
delegate "$Z_EARLY" "$T_BEFORE" "An earlier headerless job."
cp "$ZFD/README.md" "$TMP/zero-before"
outz="$(capture --claim-check "$ZERO")"; rcz=$?
check "K2. --claim-check on a feature that claims nothing but met something exits 5 (got $rcz)" '[[ $rcz -eq 5 ]]'
check "K2b. ... naming the manually excluded session on its branch with its pin-session command" \
  'grep -qF "manifest.py --self $ZERO pin-session $MANUAL" <<<"$outz"'
check "K2c. ... and the headerless delegate in its window with its exact pin command" \
  'grep -qF "manifest.py --self $ZERO pin-subagent $Z_HEADLESS" <<<"$outz"'
check "K2d. ... writing nothing" 'cmp -s "$TMP/zero-before" "$ZFD/README.md" && [[ ! -e "$ZFD/planning.json" ]]'
check "K3. a delegate briefed for another feature is not named" '! grep -q "$Z_OTHER" <<<"$outz"'
check "K3b. ... nor one that started before the window" '! grep -q "$Z_EARLY" <<<"$outz"'

WOULD="would"
WFD="$AT/self/features/$WOULD"
W_AGENT="c0000000000000001"
write_manifest "$WOULD" "claude/$WOULD" "[]"
delegate "$W_AGENT" "$T_IN" "feature: agentTooling/$WOULD\\nbuild it"
cp "$WFD/README.md" "$TMP/would-before"
outw="$(capture --claim-check "$WOULD")"; rcw=$?
check "K4. a delegate the capture would auto-claim counts as claimed (got $rcw: $outw)" \
  '[[ $rcw -eq 0 ]] && grep "$W_AGENT" <<<"$outw" | grep -qi "would"'
check "K4b. ... and the check left the fence untouched" 'cmp -s "$TMP/would-before" "$WFD/README.md"'

SESS="5e5e5e5e-0000-0000-0000-000000000003"
session_line "$SESS" "$AT" "main" "msg-main" "$MODEL" "$T_IN" 100 100 0 0 0 > "$PROJECTS/$SESS.jsonl"
outs="$(capture --claim-check "$ZERO")"; rcs=$?
check "K6. an unclaimed session in the primary, in the window, is named with its pin-session command (got $rcs)" \
  '[[ $rcs -eq 5 ]] && grep -qF "manifest.py --self $ZERO pin-session $SESS" <<<"$outs"'

# ── K7 / A5. a feature built entirely by runners ─────────────────────────────
RONLY="ronly"
RFD="$AT/self/features/$RONLY"
R_EXEC="r1r1r1r1-0000-0000-0000-000000000011"
R_REVIEW="r2r2r2r2-0000-0000-0000-000000000012"
R_DELEGATE="d0000000000000001"
write_manifest "$RONLY" "claude/$RONLY" "[]"
mkdir -p "$RFD/auto/complete" "$RFD/review/complete" "$PROJECTS/$R_EXEC/subagents"
printf '{"session_id": "%s", "total_cost_usd": 3.0}\n' "$R_EXEC" > "$RFD/auto/complete/01-a.usage.json"
printf '{"session_id": "%s", "total_cost_usd": 0.5}\n' "$R_REVIEW" > "$RFD/review/complete/01-review-opus.usage.json"
session_line "$R_EXEC" "$AT" "claude/$RONLY" "msg-rexec" "$MODEL" "$T_IN" 100 100 0 0 0 > "$PROJECTS/$R_EXEC.jsonl"
session_line "$R_REVIEW" "$AT" "claude/$RONLY" "msg-rrev" "$MODEL" "$T_IN" 100 100 0 0 0 > "$PROJECTS/$R_REVIEW.jsonl"
# The executor spawns a delegate headed for this feature, as the hook requires.
{
  subagent_prompt_line "$R_EXEC" "$R_DELEGATE" "$AT" "claude/$RONLY" "$T_IN" "feature: agentTooling/$RONLY\\nexplore the code"
  subagent_line "$R_EXEC" "$R_DELEGATE" "$AT" "claude/$RONLY" "msg-rdel" "$MODEL" "$T_IN" 100 2000 0 0 0
} > "$PROJECTS/$R_EXEC/subagents/agent-$R_DELEGATE.jsonl"
cp "$RFD/README.md" "$TMP/ronly-before"
outro="$(capture --claim-check "$RONLY")"; rcro=$?
check "K7. --claim-check on a runner-only feature exits 0 (got $rcro: $outro)" '[[ $rcro -eq 0 ]]'
outrc7="$(capture "$RONLY")"; rcrc7=$?
check "K7b. ... and the real capture of the same fixture agrees: exit 0, evidenced zero written (got $rcrc7)" \
  '[[ $rcrc7 -eq 0 && "$(pj "$RFD/planning.json" "d[\"cost_usd\"][\"total\"]")" == "0.0" ]] && grep -q "zero is evidenced" <<<"$outrc7"'
check "A5. the runner's headed delegate is not pinned (fence unchanged)" \
  'cmp -s "$TMP/ronly-before" "$RFD/README.md"'
check "A5b. ... the capture says why, naming the runner parent" \
  'grep "$R_DELEGATE" <<<"$outrc7" | grep -q "runner session"'
check "A5c. ... and gives no \"pinned subagent matches no transcript\" warning" \
  '! grep -q "matches no transcript" <<<"$outrc7"'

# ── A6. a headed delegate of a parent the capture selects ────────────────────
SEL="sel"
SFD="$AT/self/features/$SEL"
S_PARENT="5e1e5e1e-0000-0000-0000-000000000021"
S_DELEGATE="d0000000000000002"
write_manifest "$SEL" "claude/$SEL" "[]"
mkdir -p "$PROJECTS/$S_PARENT/subagents"
session_line "$S_PARENT" "$AT" "claude/$SEL" "msg-sel" "$MODEL" "$T_IN" 100 100 0 0 0 > "$PROJECTS/$S_PARENT.jsonl"
{
  subagent_prompt_line "$S_PARENT" "$S_DELEGATE" "$AT" "claude/$SEL" "$T_IN" "feature: agentTooling/$SEL\\nexplore"
  subagent_line "$S_PARENT" "$S_DELEGATE" "$AT" "claude/$SEL" "msg-sdel" "$MODEL" "$T_IN" 100 2000 0 0 0
} > "$PROJECTS/$S_PARENT/subagents/agent-$S_DELEGATE.jsonl"
cp "$SFD/README.md" "$TMP/sel-before"
outsel="$(capture "$SEL")"; rcsel=$?
check "A6. a headed delegate of a selected parent is not pinned (got $rcsel)" \
  '[[ $rcsel -eq 0 ]] && cmp -s "$TMP/sel-before" "$SFD/README.md" && ! grep -q "auto-claim pinned" <<<"$outsel"'
check "A6b. ... and the record prices it through its parent" \
  '[[ "$(pj "$SFD/planning.json" "[a[\"selected_by\"] for a in d[\"subagents\"] if a[\"agent_id\"]==\"$S_DELEGATE\"]")" == "['"'"'parent'"'"']" ]]'

# ── R. --allow-unclaimed's reason reaches the record ─────────────────────────
manifest() { HOME="$FAKE_HOME" python3 -B "$AT/analysis/manifest.py" --self "$@" 2>&1; }
cp "$ZFD/README.md" "$TMP/zero-before-allow"
outr0="$(manifest "$ZERO" allow-unclaimed "   ")"; rcr0=$?
check "R1. manifest.py allow-unclaimed refuses an empty reason, writing nothing (got $rcr0)" \
  '[[ $rcr0 -eq 1 ]] && cmp -s "$TMP/zero-before-allow" "$ZFD/README.md"'
REASON="the build ran in a session whose transcript expired"
outr="$(manifest "$ZERO" allow-unclaimed "$REASON")"; rcr=$?
check "R2. manifest.py allow-unclaimed writes the reason into the fence (got $rcr: $outr)" \
  '[[ $rcr -eq 0 && "$(fence "$ZFD/README.md" "d[\"allow_unclaimed\"]")" == "$REASON" ]]'
outrc="$(capture "$ZERO")"; rcrc=$?
check "R3. the capture of that evidenced zero writes planning.json carrying the reason (got $rcrc)" \
  '[[ $rcrc -eq 0 && "$(pj "$ZFD/planning.json" "d[\"allow_unclaimed\"]")" == "$REASON" ]]'
outrr="$(HOME="$FAKE_HOME" python3 -B "$AT/analysis/report.py" --self "$ZERO" 2>&1)"; rcrr=$?
check "R4. report.py prints it among the report's warnings (got $rcrr)" \
  '[[ $rcrr -eq 0 ]] && grep -q -- "--allow-unclaimed): $REASON" "$ZFD/report.md"'

if (( fails )); then echo "delegate-cost-claims: $fails FAILED"; exit 1; fi
echo "delegate-cost-claims: all checks passed"
