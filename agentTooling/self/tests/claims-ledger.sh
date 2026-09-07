#!/usr/bin/env bash
set -uo pipefail

# Self-test for what the claims ledger counts as claimed
# (self/features/recovered-duration-lower-bound/README.md, items 2 and 3). Run by
# self/gate.sh, or by hand: bash self/tests/claims-ledger.sh
#
# Same scaffolding as subagent-capture.sh — copies of the analysis scripts into a
# throwaway agentTooling checkout under mktemp -d, hand-written manifests, and synthesized
# transcripts under a redirected $HOME. No model, no network; a few seconds.
#
# $HOME is redirected rather than a ledger path being passed in: `Path.home()` resolves
# the ledger AND the transcript glob, so redirecting it moves the whole of `~/.claude` at
# once. A ledger-only override would let a test move the ledger and still read the real
# transcripts (self/tests/README.md).
#
# Two defects, both surfaced by closing seven features on 2026-09-07:
#   - every close printed its delegates under "unclaimed delegates briefed for …"
#     followed by `Pin each in <slug>'s manifest as "subagents": […]` — and then claimed
#     every one of them as `pinned` in the capture. "Unclaimed" meant "not claimed
#     through a branch", so a delegate pinned by this very manifest counted as unclaimed
#     and the close told the human to do what was already done;
#   - the coordinator session that ran all seven was pinned in each manifest and priced
#     in full by each close, so seven report.md files sum its cost seven times and none
#     of them says so. The ledger refused a *subagent* claimed twice and knew nothing
#     about top-level sessions at all.
#
# Asserts, in order:
#   A. --list-subagents --unclaimed --for <repo>/<slug>:
#      A1-A2. a delegate whose id is in that feature's manifest `subagents` is not
#             unclaimed and is dropped from the list, while an unpinned sibling briefed
#             for the same feature is still listed with the advice line beside it;
#      A3-A4. with every delegate pinned the list is empty and the advice line is gone —
#             it is printed only when there is something left to pin;
#      A5.    a delegate already in the ledger is dropped as before, read from a LEGACY
#             flat ledger file (the shape on every machine today), which must keep
#             loading;
#      A6.    a delegate briefed for another feature is still not this one's.
#   B. one session, two manifests:
#      B1-B2. the first capture claims the pinned session and records no `also_claimed_by`
#             — nobody else has it;
#      B3-B5. the second feature's capture is NOT refused (a coordinator legitimately
#             spans features, unlike a subagent), and its session entry names the other
#             feature in `also_claimed_by`;
#      B6.    the ledger holds both claims under that session id — a list, not the single
#             claimant a subagent id gets;
#      B7-B8. re-capturing the first feature now names the second, and the annotation is
#             symmetric;
#      B9-B11. report.py renders it: `cost.shared_sessions[]` carries {session_id,
#             cost_usd, also_claimed_by} and report.md prints one footnote under the Cost
#             table naming the session, its dollars and the other feature.
#   C. the annotate-only path over a FROZEN record (review escalation 1). Two features
#      closed before either had claimed the other's coordinator — the seven closes of
#      2026-09-07, and the case item 3 was built for. `sweep.sh` runs
#      `capture_planning.py --all` with NO `--recapture`, so before this the frozen
#      records returned "skipped" before the scan and the annotation never appeared:
#      C1-C2. one plain `--all` leaves each of the two naming the other — the ledger is
#             filled for the whole run before any record is annotated, so convergence
#             does not depend on the order the corpus is swept in;
#      C3.    every other field is byte-identical — the dollars, the durations,
#             `captured_at`, the priced rows. Nothing is re-derived;
#      C4.    the run reports them as `annotated`, not `skipped`;
#      C5.    the shared session's transcript is DELETED before the run: the annotate
#             path opens none, which is the whole reason a frozen record can take it;
#      C6.    report.py then renders `cost.shared_sessions[]` and the footnote for the
#             feature that was frozen first;
#      C7.    a second `--all` writes nothing at all and says "skipping".
#   D. `--unclaimed --for` prefers the corpus the query is for (review escalation 2).
#      A `plans/features/<slug>` and a `self/features/<slug>` may share a name, and
#      matching the pin by slug across both let the OTHER corpus's pin suppress a
#      genuinely unpinned delegate — silencing feature-close.sh's stop-on-unpinned guard,
#      whose whole job is to stop on it, and losing its cost with nothing said:
#      D1.    with `--self`, the self corpus's same-slug feature pins nothing, so the
#             delegate IS listed as unclaimed;
#      D2.    without `--self`, the plans corpus's feature pins it, so it is not;
#      D3.    a slug the queried corpus does not hold at all still falls back to the slug
#             alone across both — the vendored-subtree case the docstring argues for.
#
# A1-A4, every B assertion, C1, C2, C4, C6 and D1 were RED until their feature landed: A
# on `--for` listing a pinned delegate, B on the second capture being refused as a double
# claim, C on `--all` returning "skipped" before the scan, D1 on the other corpus's pin.
# A5, A6, B1, D2 and D3 guard behaviour that already worked; C0, C3, C5 and C7 pin the
# shape of the new path rather than its existence, and pass vacuously against the old
# code, which wrote nothing at all. A missing script fails its own assertions loudly
# rather than aborting the run — the cost-recovery.sh convention.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/claims-ledger.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/.git"
for f in pricing.py roots.py transcript.py capture_planning.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
jf() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

echo "claims ledger"

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/' '-')"
mkdir -p "$PROJECTS"
export HOME="$FAKE_HOME"
# repo_identity falls back to the directory name when there is no origin, so the repo
# half of every `feature: <repo>/<slug>` line below is the checkout's own name.
REPO="agentTooling"
LEDGER="$FAKE_HOME/.claude/subagent-claims.json"

MODEL="claude-sonnet-5"
BRANCH="claims-ledger-branch"
WINDOW_FROM="2026-07-01T00:00:00Z"
WINDOW_TO="2026-07-05T00:00:00Z"
TS="2026-07-02T10:00:00.000Z"

# manifest <slug> <sessions JSON> <subagents JSON>
manifest() {
  local slug="$1" sessions="$2" subagents="$3" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MANIFEST
# $slug

Fixture feature for self/tests/claims-ledger.sh.

\`\`\`json
{
  "slug": "$slug",
  "plans": [],
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "sessions": $sessions,
  "subagents": $subagents
}
\`\`\`
MANIFEST
}

# delegate <parent session> <agent id> <feature ref for the brief>
delegate() {
  mkdir -p "$PROJECTS/$1/subagents"
  {
    subagent_prompt_line "$1" "$2" "$AT" "main" "$TS" "feature: $3\\nbuild it"
    subagent_line "$1" "$2" "$AT" "main" "msg-$2" "$MODEL" "$TS" 100 2000 0 0 0
  } > "$PROJECTS/$1/subagents/agent-$2.jsonl"
}

capture()   { python3 "$AT/analysis/capture_planning.py" --self "$1" --recapture 2>&1; }
capture_all(){ python3 "$AT/analysis/capture_planning.py" --self --all 2>&1; }
list_for()  { python3 "$AT/analysis/capture_planning.py" --self --list-subagents --unclaimed --for "$1" 2>&1; }
# The same question asked of the OTHER corpus: no --self, so plans/features is the tree
# the query is for. Group D is the only caller.
list_for_plans() { python3 "$AT/analysis/capture_planning.py" --list-subagents --unclaimed --for "$1" 2>&1; }
report_for(){ python3 "$AT/analysis/report.py" --self "$1" >/dev/null 2>&1; }

# Whether two planning.json files differ in anything BUT sessions[].also_claimed_by —
# what "the annotate path changes no figure" means, asserted over the whole record rather
# than over a list of fields somebody has to remember to extend.
same_but_annotation() {
  python3 - "$1" "$2" <<'PYEOF'
import json, sys
def stripped(path):
    data = json.load(open(path))
    for entry in data.get("sessions") or []:
        entry.pop("also_claimed_by", None)
    return data
print("same" if stripped(sys.argv[1]) == stripped(sys.argv[2]) else "different")
PYEOF
}

# ── A. a pinned delegate is not unclaimed ─────────────────────────────────────
COORD="cccccccc-0000-0000-0000-000000000001"
AGENT_PINNED="a1111111111111111"
AGENT_STRAY="a2222222222222222"
AGENT_LEDGER="a3333333333333333"
AGENT_OTHER="a4444444444444444"
session_line "$COORD" "$AT" "main" "msg-c" "$MODEL" "$TS" 100 1000 0 0 0 > "$PROJECTS/$COORD.jsonl"
delegate "$COORD" "$AGENT_PINNED" "$REPO/alpha"
delegate "$COORD" "$AGENT_STRAY"  "$REPO/alpha"
delegate "$COORD" "$AGENT_LEDGER" "$REPO/alpha"
delegate "$COORD" "$AGENT_OTHER"  "$REPO/beta"
manifest alpha "[]" "[\"$AGENT_PINNED\"]"

# The ledger as every machine holds it today: a flat map of agent id -> claim, with no
# section keys. It must keep loading, which is what A5 is really asserting.
mkdir -p "$FAKE_HOME/.claude"
cat > "$LEDGER" <<JSON
{
  "$AGENT_LEDGER": {
    "repo": "$AT",
    "repo_name": "$REPO",
    "slug": "alpha",
    "selected_by": "pinned",
    "cost_usd": 1.0,
    "claimed_at": "2026-07-02T00:00:00+00:00"
  }
}
JSON

a_out="$(list_for "$REPO/alpha")"
check "A1. a delegate pinned in the feature's own manifest is not listed as unclaimed" '! grep -q "$AGENT_PINNED" <<<"$a_out"'
check "A2. ...while its unpinned sibling is, with the advice line beside it" 'grep -q "$AGENT_STRAY" <<<"$a_out" && grep -q "Pin each in" <<<"$a_out"'
check "A5. a delegate already in a LEGACY flat ledger file is dropped, as before" '! grep -q "$AGENT_LEDGER" <<<"$a_out"'
check "A6. a delegate briefed for another feature is not this one's" '! grep -q "$AGENT_OTHER" <<<"$a_out"'

manifest alpha "[]" "[\"$AGENT_PINNED\", \"$AGENT_STRAY\"]"
b_out="$(list_for "$REPO/alpha")"
check "A3. with every delegate pinned the list is empty and says so" 'grep -q "no unclaimed subagent transcripts briefed for $REPO/alpha" <<<"$b_out"'
check "A4. ...and the 'Pin each in' instruction is gone — there is nothing left to pin" '! grep -q "Pin each in" <<<"$b_out"'

# ── B. one session, two manifests ─────────────────────────────────────────────
# The coordinator that ran both features, pinned by each. Nothing else matches either
# manifest: no session carries $BRANCH, so the pin is the only route in and the capture
# stands or falls on it.
SHARED="ssssssss-0000-0000-0000-000000000002"
session_line "$SHARED" "/somewhere/else" "main" "msg-s" "$MODEL" "$TS" 100 4000 0 0 0 > "$PROJECTS/$SHARED.jsonl"
rm -f "$LEDGER"
manifest one "[\"$SHARED\"]" "[]"
manifest two "[\"$SHARED\"]" "[]"

one_out="$(capture one)"; one_rc=$?
P_ONE="$AT/self/features/one/planning.json"
check "B1. the first capture claims the pinned session (rc $one_rc)" '[[ $one_rc -eq 0 && -f "$P_ONE" ]]'
one_also="$(jf "$P_ONE" '[s.get("also_claimed_by") for s in d["sessions"]]')"
check "B2. ...and records no also_claimed_by — nobody else has it (got ${one_also:-<absent>})" '[[ "$one_also" == "[None]" || "$one_also" == "[[]]" ]]'

two_out="$(capture two)"; two_rc=$?
P_TWO="$AT/self/features/two/planning.json"
check "B3. the second capture is NOT refused — a coordinator legitimately spans features (rc $two_rc)" '[[ $two_rc -eq 0 && -f "$P_TWO" ]]'
check "B4. ...and says nothing about a double claim" '! grep -qi "REFUSING" <<<"$two_out"'
two_also="$(jf "$P_TWO" '[s.get("also_claimed_by") for s in d["sessions"]]')"
check "B5. ...its session entry naming the other feature (got ${two_also:-<absent>})" '[[ "$two_also" == "[['"'"'$REPO/one'"'"']]" ]]'
ledger_claims="$(jf "$LEDGER" 'sorted(c["slug"] for c in d["sessions"]["'"$SHARED"'"])')"
check "B6. the ledger holds both claims under that session id — a list, not one claimant (got ${ledger_claims:-<absent>})" '[[ "$ledger_claims" == "['"'"'one'"'"', '"'"'two'"'"']" ]]'

capture one > /dev/null
one_also2="$(jf "$P_ONE" '[s.get("also_claimed_by") for s in d["sessions"]]')"
check "B7. re-capturing the first feature now names the second (got ${one_also2:-<absent>})" '[[ "$one_also2" == "[['"'"'$REPO/two'"'"']]" ]]'
two_also2="$(jf "$P_TWO" '[s.get("also_claimed_by") for s in d["sessions"]]')"
check "B8. ...and the second's own annotation is untouched, so the two agree" '[[ "$two_also2" == "[['"'"'$REPO/one'"'"']]" ]]'

report_for two
R_TWO="$AT/self/features/two/report.json"
M_TWO="$AT/self/features/two/report.md"
shared_keys="$(jf "$R_TWO" 'sorted(d["cost"]["shared_sessions"][0].keys())')"
check "B9. cost.shared_sessions carries {session_id, cost_usd, also_claimed_by} (got ${shared_keys:-<absent>})" '[[ "$shared_keys" == "['"'"'also_claimed_by'"'"', '"'"'cost_usd'"'"', '"'"'session_id'"'"']" ]]'
shared_id="$(jf "$R_TWO" 'd["cost"]["shared_sessions"][0]["session_id"]')"
shared_cost="$(jf "$R_TWO" 'd["cost"]["shared_sessions"][0]["cost_usd"] > 0')"
check "B10. ...naming the session and its dollars (got ${shared_id:-<absent>}, positive: ${shared_cost:-<absent>})" '[[ "$shared_id" == "$SHARED" && "$shared_cost" == "True" ]]'
check "B11. report.md prints one footnote naming the session and the other feature" 'grep -q "$SHARED" "$M_TWO" && grep -q "$REPO/one" "$M_TWO"'

# ── C. a frozen record is annotated, and nothing else about it moves ──────────
# `three` and `four` both pin one coordinator, and each is captured with the ledger
# holding no claim on it — the shape the seven closes of 2026-09-07 left behind, where
# every record was frozen before any of the others existed to be named. The ledger is
# wiped between the two captures to produce it: without that, the second capture would
# see the first's claim and B5 would already be the whole story.
SHARED2="ssssssss-0000-0000-0000-000000000003"
session_line "$SHARED2" "/somewhere/else" "main" "msg-s2" "$MODEL" "$TS" 100 6000 0 0 0 \
  > "$PROJECTS/$SHARED2.jsonl"
manifest three "[\"$SHARED2\"]" "[]"
manifest four  "[\"$SHARED2\"]" "[]"
capture three > /dev/null
rm -f "$LEDGER"
capture four > /dev/null
P_THREE="$AT/self/features/three/planning.json"
P_FOUR="$AT/self/features/four/planning.json"
cp "$P_THREE" "$TMP/three-frozen.json"
cp "$P_FOUR" "$TMP/four-frozen.json"
frozen_pre="$(jf "$P_THREE" '[s.get("also_claimed_by") for s in d["sessions"]]')"

# The transcript goes before the sweep, not after: a frozen record's transcripts are
# expiring — that is why it is frozen — and the annotate path has to work without them.
rm -f "$PROJECTS/$SHARED2.jsonl"
check "C5. the shared session's transcript is deleted before the sweep" '[[ ! -f "$PROJECTS/$SHARED2.jsonl" ]]'
check "C0. ...and neither frozen record names the other yet (got ${frozen_pre:-<absent>})" '[[ "$frozen_pre" == "[None]" || "$frozen_pre" == "[[]]" ]]'

all_out="$(capture_all)"; all_rc=$?
three_also="$(jf "$P_THREE" '[s.get("also_claimed_by") for s in d["sessions"]]')"
four_also="$(jf "$P_FOUR" '[s.get("also_claimed_by") for s in d["sessions"]]')"
check "C1. a plain --all annotates the record frozen first (rc $all_rc, got ${three_also:-<absent>})" '[[ $all_rc -eq 0 && "$three_also" == "[['"'"'$REPO/four'"'"']]" ]]'
check "C2. ...and the other, in the SAME run — convergence does not depend on sweep order (got ${four_also:-<absent>})" '[[ "$four_also" == "[['"'"'$REPO/three'"'"']]" ]]'
check "C3. nothing but the annotation moved: dollars, durations, captured_at, priced rows" \
  '[[ "$(same_but_annotation "$TMP/three-frozen.json" "$P_THREE")" == "same" ]] && [[ "$(same_but_annotation "$TMP/four-frozen.json" "$P_FOUR")" == "same" ]]'
check "C4. the run reports them as annotated, not skipped" \
  'grep -q "three: already captured .* annotated 1 shared session" <<<"$all_out" && grep -q "2 annotated" <<<"$all_out"'

report_for three
R_THREE="$AT/self/features/three/report.json"
M_THREE="$AT/self/features/three/report.md"
three_shared="$(jf "$R_THREE" 'd["cost"]["shared_sessions"][0]["session_id"]')"
check "C6. report.py renders shared_sessions[] and the footnote for the frozen feature (got ${three_shared:-<absent>})" \
  '[[ "$three_shared" == "$SHARED2" ]] && grep -q "$SHARED2" "$M_THREE" && grep -q "$REPO/four" "$M_THREE"'

cp "$P_THREE" "$TMP/three-annotated.json"
again_out="$(capture_all)"
check "C7. a second --all writes nothing and says skipping" \
  'cmp -s "$TMP/three-annotated.json" "$P_THREE" && grep -q "three: already captured .* skipping" <<<"$again_out" && ! grep -q "annotated" <<<"$again_out"'

# ── D. --unclaimed --for prefers the corpus the query is for ──────────────────
# plans_manifest writes into the OTHER corpus. `all_features_roots()` reads
# `<agentTooling>/../plans/features` regardless of mode, which is $TMP/plans/features
# here, so a slug can exist in both trees exactly as it can in a real vendored checkout.
plans_manifest() {
  local slug="$1" subagents="$2" dir="$TMP/plans/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MANIFEST
# $slug

Fixture feature for self/tests/claims-ledger.sh, in the host repo's corpus.

\`\`\`json
{
  "slug": "$slug",
  "plans": [],
  "branches": ["$BRANCH"],
  "session_window": {"from": "$WINDOW_FROM", "to": "$WINDOW_TO"},
  "sessions": [],
  "subagents": $subagents
}
\`\`\`
MANIFEST
}

AGENT_DUP="a5555555555555555"
AGENT_VENDOR="a6666666666666666"
delegate "$COORD" "$AGENT_DUP" "$REPO/dup"
delegate "$COORD" "$AGENT_VENDOR" "$REPO/vendored"
# One slug, both corpora: the host repo's `dup` pins the delegate, agentTooling's does
# not. They are different features that happen to share a name.
plans_manifest dup "[\"$AGENT_DUP\"]"
manifest dup "[]" "[]"
# ...and one that exists in the host corpus only, which is what the slug-only fallback
# is for: under a vendored subtree a --self brief still says `agentTooling/<slug>`.
plans_manifest vendored "[\"$AGENT_VENDOR\"]"

d_self="$(list_for "$REPO/dup")"
d_plans="$(list_for_plans "$REPO/dup")"
d_fallback="$(list_for "$REPO/vendored")"
check "D1. --self: the self corpus's same-slug feature pins nothing, so the delegate is unclaimed" 'grep -q "$AGENT_DUP" <<<"$d_self"'
check "D2. no --self: the plans corpus's feature pins it, so it is not listed" '! grep -q "$AGENT_DUP" <<<"$d_plans"'
check "D3. a slug the queried corpus does not hold falls back to the slug alone across both" '! grep -q "$AGENT_VENDOR" <<<"$d_fallback"'

echo
if (( fails > 0 )); then echo "claims-ledger: $fails assertion(s) FAILED"; exit 1; fi
echo "claims-ledger: all assertions passed"
