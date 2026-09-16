#!/usr/bin/env bash
set -uo pipefail

# Self-test for the *claim set* half of session sharing — plan 89 asserts the share
# arithmetic once the claimants are known; this asserts who counts as a claimant of one
# session and which of the three sources it was found from. Run by self/gate.sh, or by
# hand: bash self/tests/session-claims.sh
#
# Same scaffolding as session-share.sh — copies of analysis/{pricing,roots,transcript,
# capture_planning}.py into a throwaway agentTooling checkout under mktemp -d, and, under
# a redirected $HOME, the ~/.claude/projects/*/<session_id>.jsonl transcripts capture
# reads, built with session_line/subagent_line/subagent_prompt_line from
# fixtures/transcripts/build-transcript.sh. No model, no network.
#
# The rule under test: a session's claimants are not limited to manifests in the
# capturing feature's own corpus. There are three sources, ranked in this order:
#   1. a manifest in EITHER corpus (self/features or the enclosing repo's plans/features)
#      pinning the session directly — read live, so it is always current;
#   2. failing that, the shared ledger ($HOME/.claude/subagent-claims.json)'s "sessions"
#      section, which is how a claimant in a THIRD repo (one this checkout cannot read a
#      manifest from at all) is found — written by that repo's own capture, so it is a
#      cache of what another capture already knew, not a live read;
#   3. a manifest claim always outranks a ledger claim for the SAME (repo, slug): the
#      ledger can be stale, the manifest cannot.
# A claim with no `window` at all is the shape recorded before this feature existed — it
# is read as unbounded (claims every response) and split evenly, with a warning, rather
# than either refused or silently ignored. A LEGACY flat ledger file (no "subagents"/
# "sessions" keys — the shape on every machine today) must keep loading, and nothing in
# it is ever read as a session claim, since a flat file has no sessions section to read.
# The claims ledger's own subagent side (one claimant only, refused outright on a second)
# is untouched by any of this and is pinned by reference to subagent-capture.sh's own
# assertion, not re-derived here.
#
# One session (33333333-0000-0000-0000-000000000003), four responses two hours apart
# from 2026-06-02T10:00:00.000Z, output tokens 1000/1000/1000/1000 and everything else
# zero so cost is proportional to output tokens alone. `claim-here`, in the self corpus,
# pins it with window 10:00-20:00.
#
# Asserts, in order:
#   1. a claimant in the OTHER corpus (plans/features, the enclosing repo's) is found
#      from its manifest: share_basis holds two entries, the second naming
#      "<enclosing repo>/claim-there" with source "manifest", and claim-here's total is
#      three quarters of the session's own cost (it owns the first two responses alone
#      and half of each of the last two, claim-there's window opening exactly on the
#      third response);
#   2. with claim-there's manifest gone, a claimant in a THIRD repo — one with no
#      manifest in either corpus at all — is found from the ledger instead: same three
#      quarters, share_basis naming "otherRepo/claim-elsewhere" with source "ledger";
#   3. when claim-there's manifest returns with a DIFFERENT window while the ledger still
#      carries a claim for it under its own (repo, slug) — stale, from before this
#      change — share_basis holds exactly one entry for it, source "manifest", carrying
#      the manifest's current `from`, not the stale ledger's: the manifest is current,
#      the ledger is a cache;
#   4. a legacy claim with no `window` key is read as unbounded (`from`/`to` both null in
#      share_basis), splits this feature's cost exactly in half (an even split over the
#      whole transcript), and is warned about by name; the same claim seeded into a
#      LEGACY FLAT ledger file (no section keys) is not read as a session claim at all —
#      the file loads, and claim-here's cost is the full, unshared figure;
#   5. a fifth response appended as this parent transcript's own sidechain line, inside
#      every claimant's window, is shared exactly like a main-line one: cost_usd.sidechain
#      is halved on this feature and cost_usd.total still equals main plus sidechain;
#   6. after a capture, the ledger's own entry for agentTooling/claim-here carries a
#      `window` of NORMALIZED instants (python isoformat, "+00:00") rather than the
#      manifest's raw strings — so a third repo's capture (assertion 2's scenario) can
#      read it without re-parsing whatever zone format the pinning manifest happened to
#      use;
#   7. a record frozen with no other claimant, later claimed by a manifest AND a ledger
#      entry that appear only after the freeze, is ANNOTATED by a plain `--all` (no
#      `--recapture`) rather than recomputed: `also_claimed_by` gains the other feature,
#      every other field is byte-identical to the frozen copy, and the run separately
#      warns naming the slug and the session that the frozen figure predates the share
#      rule and a `--recapture` would rebuild it while the transcript still exists — and
#      goes on warning on the SECOND consecutive `--all`, which writes nothing: the
#      repair is asked for on every pass, while `skipping` still means "this run wrote
#      nothing";
#   8. the subagent side of the ledger is untouched by any of this: a subagent already
#      claimed by one feature still refuses a second feature's capture outright, asserted
#      by reference to subagent-capture.sh's own fixture rather than re-derived here;
#   9. the claimant scan is indexed once per capture rather than repeated per selected
#      session: three `session_claim_intervals` queries over one built index parse no
#      manifest again;
#  10. in the VENDORED layout — a second sandbox, since assertions 1-9 stand up the
#      standalone shape — the self corpus's identity is the DECLARED one and not whatever
#      `git` answers from the enclosing consuming repo: a self-corpus manifest is a
#      claimant as `agentTooling/<slug>` rather than `<consumer>/<slug>`, a ledger claim on
#      the same feature under the declared identity dedupes against it instead of becoming
#      a third claimant, the split is two-way and not the phantom's three, and the ledger
#      row the capture writes for itself carries the declared identity and `agentTooling`.
#
# 1-7 were RED until analysis/capture_planning.py learned to look beyond its own corpus and
# its own manifest for a session's claimants. Assertion 8 was GREEN then: the subagent
# refusal it pins is pre-existing and must stay exactly as it is while the session side
# grows around it. 10a-10g were RED until `corpus_identity` declared the self corpus's
# identity instead of deriving it (self/features/self-corpus-identity/).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path, not the symlinked one — roots.py resolves AGENT_TOOLING_DIR with
# Path.resolve(), so on macOS an unresolved /var/... fixture path matches no transcript
# and every assertion below passes or fails vacuously (capture-guard.sh).
TMP="$(cd "$TMP" && pwd -P)"
# The enclosing repo has no .git of its own in this fixture (only $AT does), so
# repo_identity falls back to its directory name — computed once, here, since mktemp's
# name is otherwise unpredictable. It is the identity of the HOST corpus
# ($TMP/plans/features) only; the self corpus's is declared, not derived from any of
# this, which is what phase 10 stands up a second sandbox for.
ENCLOSING_NAME="$(basename "$TMP")"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py capture_planning.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f"
done

# session_root() walks up for the nearest ancestor holding .git; without one here it
# would escape the sandbox and resolve to a real repo above /tmp.
mkdir -p "$AT/.git"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# field PLANNING_JSON PY_EXPR — evaluates PY_EXPR against `d`, the parsed planning.json
# (or ledger). Errors are swallowed and read back as an empty string, so a check against
# them fails cleanly instead of crashing this script — the RED state before this feature
# exists.
field() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}

# close_enough A B — true when the two floats differ by less than 1e-9.
close_enough() {
  python3 -c "import sys; a=float(sys.argv[1]); b=float(sys.argv[2]); sys.exit(0 if abs(a - b) < 1e-9 else 1)" \
    "$1" "$2" 2>/dev/null
}

# parses_to INSTANT EXPECTED_ISO — true when INSTANT (a "Z" or "+00:00" suffixed string)
# parses to the same instant as EXPECTED_ISO. Compares instants, not strings — assertion
# 6 pins that the ledger's window is normalized, not that it is spelled one specific way.
parses_to() {
  python3 -c "
import sys
from datetime import datetime, timezone
got = datetime.fromisoformat(sys.argv[1].replace('Z', '+00:00'))
if got.tzinfo is None:
    got = got.replace(tzinfo=timezone.utc)
exp = datetime.fromisoformat(sys.argv[2].replace('Z', '+00:00'))
sys.exit(0 if got == exp else 1)
" "$1" "$2" 2>/dev/null
}

# same_but_annotation A B — "same" when two planning.json files differ in nothing but
# sessions[].also_claimed_by, asserted over the whole record rather than a list of
# fields somebody has to remember to extend. Mirrors claims-ledger.sh's helper of the
# same name.
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

echo "session claim set"

SESSION="33333333-0000-0000-0000-000000000003"
MODEL="claude-sonnet-5"
BRANCH="unclaimedBranch"           # in no manifest's `branches`: the pin is the only route in
MANIFEST_BRANCH="pinnedOnlyBranch" # every manifest's own declared branch — matches no transcript

FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/.' '--')"
mkdir -p "$PROJECTS"
LEDGER="$FAKE_HOME/.claude/subagent-claims.json"

FEATURE_HERE_DIR="$AT/self/features/claim-here"
PLANNING_HERE="$FEATURE_HERE_DIR/planning.json"

# write_self_manifest SLUG FROM TO SESSION_ID — a manifest in the self corpus.
write_self_manifest() {
  local slug="$1" frm="$2" to="$3" session_id="$4"
  local dir="$AT/self/features/$slug"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<EOF
# $slug

Fixture feature for self/tests/session-claims.sh.

\`\`\`json
{
  "slug": "$slug",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "$frm", "to": "$to"},
  "sessions": ["$session_id"],
  "exclude_sessions": []
}
\`\`\`
EOF
}

# write_host_manifest SLUG FROM TO SESSION_ID — the same shape, in the enclosing repo's
# OWN corpus ($TMP/plans/features), the way self/tests/claims-ledger.sh part D stands it
# up: all_features_roots() reads it regardless of --self.
write_host_manifest() {
  local slug="$1" frm="$2" to="$3" session_id="$4"
  local dir="$TMP/plans/features/$slug"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<EOF
# $slug

Fixture feature for self/tests/session-claims.sh, in the enclosing repo's own corpus.

\`\`\`json
{
  "slug": "$slug",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "$frm", "to": "$to"},
  "sessions": ["$session_id"],
  "exclude_sessions": []
}
\`\`\`
EOF
}

capture()    { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self claim-here 2>&1; }
recapture()  { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self claim-here --recapture 2>&1; }
capture_all(){ HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --all 2>&1; }

# ── the fixture: one session, four responses two hours apart, equal output tokens ─────
session_line "$SESSION" "$AT" "$BRANCH" "r0" "$MODEL" "2026-06-02T10:00:00.000Z" 0 1000 0 0 0  > "$PROJECTS/$SESSION.jsonl"
session_line "$SESSION" "$AT" "$BRANCH" "r1" "$MODEL" "2026-06-02T12:00:00.000Z" 0 1000 0 0 0 >> "$PROJECTS/$SESSION.jsonl"
session_line "$SESSION" "$AT" "$BRANCH" "r2" "$MODEL" "2026-06-02T14:00:00.000Z" 0 1000 0 0 0 >> "$PROJECTS/$SESSION.jsonl"
session_line "$SESSION" "$AT" "$BRANCH" "r3" "$MODEL" "2026-06-02T16:00:00.000Z" 0 1000 0 0 0 >> "$PROJECTS/$SESSION.jsonl"

write_self_manifest claim-here "2026-06-02T10:00:00Z" "2026-06-02T20:00:00Z" "$SESSION"

# ── 1. a claimant in the OTHER corpus is found from its manifest ──────────────────────
write_host_manifest claim-there "2026-06-02T14:00:00Z" "2026-06-02T20:00:00Z" "$SESSION"
capture > "$TMP/out1.txt"

session_cost="$(field "$PLANNING_HERE" "d['sessions'][0]['session_cost_usd']")"
cost_here="$(field "$PLANNING_HERE" "d['cost_usd']['total']")"
basis_len="$(field "$PLANNING_HERE" "len(d['sessions'][0]['share_basis'])")"
check "1a. share_basis holds two entries" "[ \"$basis_len\" = 2 ]"

self_feature="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][0]['feature']")"
self_source="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][0]['source']")"
check "1b. the first names claim-here itself, source self" \
  "[ \"$self_feature\" = 'agentTooling/claim-here' ] && [ \"$self_source\" = self ]"

other_feature="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][1]['feature']")"
other_source="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][1]['source']")"
check "1c. the second names <enclosing repo>/claim-there, source manifest" \
  "[ \"$other_feature\" = '$ENCLOSING_NAME/claim-there' ] && [ \"$other_source\" = manifest ]"

exp_1="$(python3 -c "print(0.75*float('$session_cost'))" 2>/dev/null)"
check "1d. claim-here's total is three quarters of the session cost" "close_enough '$cost_here' '$exp_1'"

# ── 2. with claim-there's manifest gone, a claimant in a THIRD repo is found from the
# ledger ────────────────────────────────────────────────────────────────────────────────
rm -rf "$TMP/plans/features/claim-there"
cat > "$LEDGER" <<JSON
{
  "subagents": {},
  "sessions": {
    "$SESSION": [
      {
        "repo": "git@github.com:someone/otherRepo.git",
        "repo_name": "otherRepo",
        "slug": "claim-elsewhere",
        "window": {"from": "2026-06-02T14:00:00Z", "to": "2026-06-02T20:00:00Z"}
      }
    ]
  }
}
JSON
recapture > "$TMP/out2.txt"

cost_here2="$(field "$PLANNING_HERE" "d['cost_usd']['total']")"
check "2a. claim-here's total is still three quarters of the session cost" "close_enough '$cost_here2' '$exp_1'"
ledger_feature="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][1]['feature']")"
ledger_source="$(field "$PLANNING_HERE" "d['sessions'][0]['share_basis'][1]['source']")"
check "2b. share_basis names otherRepo/claim-elsewhere, source ledger" \
  "[ \"$ledger_feature\" = 'otherRepo/claim-elsewhere' ] && [ \"$ledger_source\" = ledger ]"

# ── 3. a manifest claimant outranks the same feature's ledger entry ───────────────────
# A stale claim for claim-there, under its own (repo, slug), sitting in the ledger from
# before its window changed — added directly rather than produced by a real capture,
# since claim-there has no transcript of its own to capture in this fixture.
python3 - "$LEDGER" "$SESSION" "$ENCLOSING_NAME" <<'PY'
import json, sys
path, session_id, repo_name = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
d.setdefault("sessions", {}).setdefault(session_id, []).append({
    "repo": repo_name,
    "repo_name": repo_name,
    "slug": "claim-there",
    "window": {"from": "2026-06-02T14:00:00Z", "to": "2026-06-02T20:00:00Z"},
})
json.dump(d, open(path, "w"))
PY
write_host_manifest claim-there "2026-06-02T16:00:00Z" "2026-06-02T20:00:00Z" "$SESSION"
recapture > "$TMP/out3.txt"

there_count="$(field "$PLANNING_HERE" "sum(1 for e in d['sessions'][0]['share_basis'] if e['feature']=='$ENCLOSING_NAME/claim-there')")"
check "3a. share_basis holds exactly one entry for claim-there — no ledger duplicate" "[ \"$there_count\" = 1 ]"
there_source="$(field "$PLANNING_HERE" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='$ENCLOSING_NAME/claim-there')")"
there_from="$(field "$PLANNING_HERE" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='$ENCLOSING_NAME/claim-there')")"
check "3b. it is the manifest's entry, carrying the manifest's current from" \
  "[ \"$there_source\" = manifest ] && [ \"$there_from\" = '2026-06-02T16:00:00Z' ]"

# ── 4. a legacy claim with no window is unbounded, split evenly, and warned about; a
# flat legacy ledger is never read as a session claim at all ──────────────────────────
rm -rf "$TMP/plans/features/claim-there"
cat > "$LEDGER" <<JSON
{
  "subagents": {},
  "sessions": {
    "$SESSION": [
      {"repo": "git@github.com:nobody/legacyRepo.git", "repo_name": "legacyRepo", "slug": "legacy-claim"}
    ]
  }
}
JSON
recapture > "$TMP/out4.txt"

legacy_from="$(field "$PLANNING_HERE" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='legacyRepo/legacy-claim')")"
legacy_to="$(field "$PLANNING_HERE" "next(e['to'] for e in d['sessions'][0]['share_basis'] if e['feature']=='legacyRepo/legacy-claim')")"
check "4a. a windowless claim appears with from and to both null" \
  "[ \"$legacy_from\" = None ] && [ \"$legacy_to\" = None ]"

cost_legacy="$(field "$PLANNING_HERE" "d['cost_usd']['total']")"
exp_half="$(python3 -c "print(0.5*float('$session_cost'))" 2>/dev/null)"
check "4b. claim-here's total is exactly half the session cost" "close_enough '$cost_legacy' '$exp_half'"

check "4c. the run warns naming the windowless feature and that it predates recorded windows" \
  "grep -q 'legacyRepo/legacy-claim' '$TMP/out4.txt' && grep -qi 'predates' '$TMP/out4.txt'"

# Same claim, flat ledger shape (no "subagents"/"sessions" keys) — read as the subagents
# section entire, per the pinned fact; nothing in it can be a session claim.
cat > "$LEDGER" <<JSON
{
  "$SESSION": {"repo": "git@github.com:nobody/legacyRepo.git", "repo_name": "legacyRepo", "slug": "legacy-claim"}
}
JSON
recapture > "$TMP/out4b.txt"
rc4b=$?
check "4d. a flat legacy ledger still loads without crashing" "[ $rc4b -eq 0 ]"
cost_flat="$(field "$PLANNING_HERE" "d['cost_usd']['total']")"
check "4e. ...and is not read as a session claim — claim-here's cost is the full, unshared figure" \
  "close_enough '$cost_flat' '$session_cost'"
has_basis_flat="$(field "$PLANNING_HERE" "'share_basis' in d['sessions'][0]")"
check "4f. ...no share_basis at all, the shape of an ordinary unshared session" "[ \"$has_basis_flat\" = False ]"

# ── 5. a parent transcript's own sidechain lines are shared too ───────────────────────
cat > "$LEDGER" <<JSON
{
  "subagents": {},
  "sessions": {}
}
JSON
write_host_manifest claim-there "2026-06-02T14:00:00Z" "2026-06-02T20:00:00Z" "$SESSION"
session_line "$SESSION" "$AT" "$BRANCH" "r4" "$MODEL" "2026-06-02T16:00:00.000Z" 0 1000 0 0 0 true \
  >> "$PROJECTS/$SESSION.jsonl"
recapture > "$TMP/out5.txt"

session_cost5="$(field "$PLANNING_HERE" "d['sessions'][0]['session_cost_usd']")"
sidechain_here="$(field "$PLANNING_HERE" "d['cost_usd']['sidechain']")"
main_here="$(field "$PLANNING_HERE" "d['cost_usd']['main']")"
total_here="$(field "$PLANNING_HERE" "d['cost_usd']['total']")"
# Five equal-token responses at one rate: the sidechain one (r4) is 1/5 of the whole
# transcript, and it falls inside both claim-here's and claim-there's windows, so
# claim-here's own share of it is half of that fifth.
exp_sidechain="$(python3 -c "print(float('$session_cost5')/5*0.5)" 2>/dev/null)"
check "5a. cost_usd.sidechain is halved on this feature" "close_enough '$sidechain_here' '$exp_sidechain'"
main_plus_sidechain="$(python3 -c "print(float('$main_here')+float('$sidechain_here'))" 2>/dev/null)"
check "5b. cost_usd.total still equals main plus sidechain" "close_enough '$main_plus_sidechain' '$total_here'"

# ── 6. the ledger records the window it claimed with, normalized ─────────────────────
ledger_from="$(field "$LEDGER" "next(c['window']['from'] for c in d['sessions']['$SESSION'] if c.get('slug')=='claim-here')")"
ledger_to="$(field "$LEDGER" "next(c['window']['to'] for c in d['sessions']['$SESSION'] if c.get('slug')=='claim-here')")"
check "6a. the ledger's claim-here entry carries a window at all" \
  "[ -n \"$ledger_from\" ] && [ -n \"$ledger_to\" ]"
check "6b. from parses to the manifest's 10:00 instant" "parses_to '$ledger_from' '2026-06-02T10:00:00+00:00'"
check "6c. to parses to the manifest's 20:00 instant" "parses_to '$ledger_to' '2026-06-02T20:00:00+00:00'"

# ── 7. a frozen record newly claimed asks to be re-captured ──────────────────────────
rm -rf "$TMP/plans/features/claim-there"
cat > "$LEDGER" <<JSON
{
  "subagents": {},
  "sessions": {}
}
JSON
recapture > "$TMP/out7-freeze.txt"
cp "$PLANNING_HERE" "$TMP/claim-here-frozen.json"

write_host_manifest claim-there "2026-06-02T14:00:00Z" "2026-06-02T20:00:00Z" "$SESSION"
python3 - "$LEDGER" "$SESSION" "$ENCLOSING_NAME" <<'PY'
import json, sys
path, session_id, repo_name = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
d.setdefault("sessions", {}).setdefault(session_id, []).append({
    "repo": repo_name,
    "repo_name": repo_name,
    "slug": "claim-there",
    "window": {"from": "2026-06-02T14:00:00Z", "to": "2026-06-02T20:00:00Z"},
})
json.dump(d, open(path, "w"))
PY

capture_all > "$TMP/out7-all.txt"

check "7a. the frozen record is annotated: every figure byte-identical but also_claimed_by" \
  "[ \"\$(same_but_annotation \"$TMP/claim-here-frozen.json\" \"$PLANNING_HERE\")\" = same ]"
also_claimed="$(field "$PLANNING_HERE" "d['sessions'][0].get('also_claimed_by')")"
check "7b. also_claimed_by names the enclosing repo's claim-there" \
  "[ \"$also_claimed\" = \"['$ENCLOSING_NAME/claim-there']\" ]"
check "7c. the run separately warns naming the slug, the session, and predating the share rule" \
  "grep -q 'claim-here' '$TMP/out7-all.txt' && grep -q '$SESSION' '$TMP/out7-all.txt' && grep -qi 'predates' '$TMP/out7-all.txt' && grep -qi 'recapture' '$TMP/out7-all.txt'"

# The sweep runs weekly and the annotation converges on its first pass, so a warning that
# fires only on the run that CHANGED something is a warning nobody sees again while the
# stale full-count figure is still sitting there — `check_empty_window`'s doctrine a few
# hundred lines up the same file is the opposite ("worth hearing about on every pass, not
# only on the run that would rewrite it"). The second sweep writes nothing and must still
# ask for the repair.
cp "$PLANNING_HERE" "$TMP/claim-here-annotated.json"
capture_all > "$TMP/out7-all2.txt"
check "7d. a second consecutive --all writes nothing — the record is byte-identical" \
  "cmp -s '$TMP/claim-here-annotated.json' '$PLANNING_HERE'"
check "7e. ... and still warns, naming the same slug and session" \
  "grep -q 'claim-here' '$TMP/out7-all2.txt' && grep -q '$SESSION' '$TMP/out7-all2.txt' && grep -qi 'predates' '$TMP/out7-all2.txt' && grep -qi 'recapture' '$TMP/out7-all2.txt'"
check "7f. ... while reporting the feature as skipped, since nothing was written" \
  "grep -q 'skipping' '$TMP/out7-all2.txt'"

# ── 8. the subagent side is untouched: a second claim on one subagent still refuses ──
SESSION_COORD="44444444-0000-0000-0000-000000000004"
AGENT_X="a9999999999999999"
session_line "$SESSION_COORD" "$AT" "main" "msg-coord" "$MODEL" "2026-06-02T09:00:00.000Z" 100 500 0 0 0 \
  > "$PROJECTS/$SESSION_COORD.jsonl"
mkdir -p "$PROJECTS/$SESSION_COORD/subagents"
{
  subagent_prompt_line "$SESSION_COORD" "$AGENT_X" "$AT" "main" "2026-06-02T09:30:00.000Z" "Delegate brief"
  subagent_line "$SESSION_COORD" "$AGENT_X" "$AT" "main" "msg-$AGENT_X" "$MODEL" "2026-06-02T09:30:00.000Z" 100 2000 0 0 0
} > "$PROJECTS/$SESSION_COORD/subagents/agent-$AGENT_X.jsonl"

cat > "$FEATURE_HERE_DIR/README.md" <<EOF
# claim-here

Fixture feature for self/tests/session-claims.sh.

\`\`\`json
{
  "slug": "claim-here",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "2026-06-02T10:00:00Z", "to": "2026-06-02T20:00:00Z"},
  "sessions": ["$SESSION"],
  "exclude_sessions": [],
  "subagents": ["$AGENT_X"]
}
\`\`\`
EOF
recapture > /dev/null

mkdir -p "$AT/self/features/claim-twin"
cat > "$AT/self/features/claim-twin/README.md" <<EOF
# claim-twin

Fixture feature for self/tests/session-claims.sh — pins the subagent claim-here already
owns, to assert the subagent side still refuses a double claim.

\`\`\`json
{
  "slug": "claim-twin",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "2026-06-02T00:00:00Z", "to": "2026-06-03T00:00:00Z"},
  "sessions": [],
  "exclude_sessions": [],
  "subagents": ["$AGENT_X"]
}
\`\`\`
EOF
HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self claim-twin > "$TMP/out8.txt" 2>&1
rc8=$?
check "8. a subagent already claimed by claim-here still refuses claim-twin's capture" "[ $rc8 -ne 0 ]"

# ── 9. the claimant scan is indexed once per capture ──────────────────────────────────
# `session_claim_intervals` used to re-glob and re-parse every manifest under BOTH corpora
# on every call — and `select_parent` calls it once per selected session, so a 40-feature
# corpus with 30 selected sessions paid roughly 1200 manifest parses and 60
# `git remote get-url` subprocesses per capture. The manifests are indexed once where
# `share_ctx` is built; this counts the parses to prove the query no longer adds any.
# Correctness is asserted by every other check in this file and in session-share.sh —
# the index must not change a single answer.
python3 - "$AT" > "$TMP/out9-index.txt" 2>&1 <<'PY'
import sys

sys.path.insert(0, sys.argv[1] + "/analysis")
import capture_planning as cp
import roots

calls = {"n": 0}
real = cp.parse_manifest


def counting(path):
    calls["n"] += 1
    return real(path)


cp.parse_manifest = counting

features_dirs = list(roots.all_features_roots())
index = cp.build_claimant_index(features_dirs)
after_build = calls["n"]

share_ctx = {
    "repo": "fixture-repo",
    "repo_name": "fixture-repo",
    "slug": "claim-here",
    "features_dir": roots.features_root(True),
    "features_dirs": features_dirs,
    "window": {"from": None, "to": None},
    "session_claims": {},
    "claimants": index,
}
moment = cp.to_utc("2026-06-02T11:00:00Z")
for session_id in ("s-one", "s-two", "s-three"):
    cp.session_claim_intervals(session_id, moment, {"someBranch"}, share_ctx, [])

if after_build < 2:
    print("VACUOUS: the index parsed %d manifest(s); the corpus is empty" % after_build)
elif calls["n"] != after_build:
    print("GREW: %d parse(s) to build, %d after three queries" % (after_build, calls["n"]))
else:
    print("OK: %d manifest parse(s), unchanged by three session queries" % after_build)
PY
check "9. the claimant index is built once — three session queries parse no manifest again" \
  "grep -q '^OK:' '$TMP/out9-index.txt'"

# ── 10. the vendored layout: the self corpus's identity is DECLARED, not derived ──────
# Everything above stands up the STANDALONE shape — $AT holds the .git, so
# `repo_identity($AT)` and `session_root(True)` both answer with the agentTooling
# checkout and the corpus's identity happens to come out right whichever rule is used.
# The defect only shows in the VENDORED shape, so this phase builds a second sandbox in
# it: a consuming repo holding a real `.git` with a real `origin`, and `agentTooling/`
# beneath it with no `.git` of its own. There, `repo_identity(features_dir.parents[1])`
# walks up out of the vendored copy and answers with the CONSUMER's origin, so every
# self-corpus manifest enters the consumer's claim set as `<consumer>/<slug>` while the
# shared ledger holds the same feature as `agentTooling/<slug>` — two different (repo,
# slug) keys for one feature, both surviving the dedupe, the feature counted twice and
# `share_basis` naming one that does not exist.
#
# A real `git init` with an `origin`, rather than the bare `mkdir .git` the rest of this
# file uses: with an invalid `.git` the subprocess exits 128 and `repo_identity` falls
# back to `Path(features_dir.parents[1]).name`, which is the vendored directory's own
# name, `agentTooling` — accidentally the right answer, and the phase would be green
# against the defect it exists to catch. The wrong answer needs a git that succeeds.
VTMP="$(mktemp -d)"
# Re-armed rather than replaced: the first sandbox must still be removed on exit.
trap 'rm -rf "$TMP" "$VTMP"' EXIT
VTMP="$(cd "$VTMP" && pwd -P)"        # physical path, for the same reason $TMP is
VENDOR_NAME="vendorHost"              # the consuming repo — what a wrong answer names
VENDOR_ORIGIN="https://github.com/someone/$VENDOR_NAME.git"
VHOST="$VTMP/$VENDOR_NAME"
VAT="$VHOST/agentTooling"             # the vendored copy: no .git of its own
VSESSION="55555555-0000-0000-0000-000000000005"
VBRANCH="vendoredBranch"

mkdir -p "$VAT/analysis" "$VAT/self/features" "$VHOST/plans/features"
for f in pricing.py roots.py transcript.py capture_planning.py; do
  cp "$HERE/analysis/$f" "$VAT/analysis/$f"
done
git init -q "$VHOST" >/dev/null 2>&1
git -C "$VHOST" remote add origin "$VENDOR_ORIGIN"
# The precondition the paragraph above turns on, checked rather than assumed: if either
# git command fails (no git, a hook, a global config that refuses), `repo_identity` falls
# back to `Path(...).name` — `agentTooling`, accidentally the right answer — and every
# assertion below passes against the defect it exists to catch. Loud here, vacuous
# otherwise.
vendor_origin_now="$(git -C "$VHOST" remote get-url origin 2>/dev/null)"
check "10-pre. the fixture's enclosing repo really has origin $VENDOR_ORIGIN (got '$vendor_origin_now')" \
  '[ "$vendor_origin_now" = "$VENDOR_ORIGIN" ]'

VFAKE_HOME="$VTMP/home"
# Filed under the ENCLOSING directory's project path, with `cwd` the enclosing directory:
# that is where a session in a consuming repo runs from, and session_root(True) resolves
# to it here because the vendored copy has no .git of its own.
VPROJECTS="$VFAKE_HOME/.claude/projects/$(echo "$VHOST" | tr '/.' '--')"
mkdir -p "$VPROJECTS"
VLEDGER="$VFAKE_HOME/.claude/subagent-claims.json"
VPLANNING="$VAT/self/features/claim-here/planning.json"

# write_vendored_manifest SLUG FROM TO — a manifest in the VENDORED self corpus.
write_vendored_manifest() {
  local slug="$1" frm="$2" to="$3" dir="$VAT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<EOF
# $slug

Fixture feature for self/tests/session-claims.sh, in a VENDORED self corpus.

\`\`\`json
{
  "slug": "$slug",
  "branches": ["$MANIFEST_BRANCH"],
  "session_window": {"from": "$frm", "to": "$to"},
  "sessions": ["$VSESSION"],
  "exclude_sessions": []
}
\`\`\`
EOF
}

vcapture() {
  HOME="$VFAKE_HOME" python3 "$VAT/analysis/capture_planning.py" --self claim-here --recapture 2>&1
}

# The annotate-only path's runner: a corpus-wide sweep with no --recapture, which is what
# `sweep.sh` runs and the only route that reaches `register_frozen_claims` and the
# `annotate_frozen_record` call (10h-10j).
vcapture_all() {
  HOME="$VFAKE_HOME" python3 "$VAT/analysis/capture_planning.py" --self --all 2>&1
}

# Four responses two hours apart, equal output tokens, exactly like the first fixture —
# so a claimant whose window covers the whole transcript takes an even share of it.
session_line "$VSESSION" "$VHOST" "$VBRANCH" "v0" "$MODEL" "2026-06-02T10:00:00.000Z" 0 1000 0 0 0  > "$VPROJECTS/$VSESSION.jsonl"
session_line "$VSESSION" "$VHOST" "$VBRANCH" "v1" "$MODEL" "2026-06-02T12:00:00.000Z" 0 1000 0 0 0 >> "$VPROJECTS/$VSESSION.jsonl"
session_line "$VSESSION" "$VHOST" "$VBRANCH" "v2" "$MODEL" "2026-06-02T14:00:00.000Z" 0 1000 0 0 0 >> "$VPROJECTS/$VSESSION.jsonl"
session_line "$VSESSION" "$VHOST" "$VBRANCH" "v3" "$MODEL" "2026-06-02T16:00:00.000Z" 0 1000 0 0 0 >> "$VPROJECTS/$VSESSION.jsonl"

write_vendored_manifest claim-here      "2026-06-02T10:00:00Z" "2026-06-02T20:00:00Z"
write_vendored_manifest claim-self-twin "2026-06-02T10:00:00Z" "2026-06-02T20:00:00Z"
mkdir -p "$VFAKE_HOME/.claude"
cat > "$VLEDGER" <<JSON
{
  "subagents": {},
  "sessions": {}
}
JSON
vcapture > "$TMP/out10a.txt"

v_session_cost="$(field "$VPLANNING" "d['sessions'][0]['session_cost_usd']")"
twin_source="$(field "$VPLANNING" "next((e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/claim-self-twin'), None)")"
check "10a. a vendored self-corpus manifest is a claimant as agentTooling/claim-self-twin, source manifest" \
  "[ \"$twin_source\" = manifest ]"

vendor_named="$(field "$VPLANNING" "sum(1 for e in d['sessions'][0]['share_basis'] if e['feature'].split('/')[0]=='$VENDOR_NAME')")"
check "10b. no claim in share_basis is named for the enclosing repo — not the twin, not claim-here itself" \
  "[ \"$vendor_named\" = 0 ]"

# The same feature, under the identity the shared ledger holds it as — written by the
# standalone checkout's own --self runs — and carrying a DIFFERENT window. Deduped on
# (repo, slug), it must collapse into the manifest entry above rather than becoming a
# third claimant; the manifest is current and the ledger is a cache.
python3 - "$VLEDGER" "$VSESSION" <<'PY'
import json, sys
path, session_id = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d.setdefault("sessions", {}).setdefault(session_id, []).append({
    "repo": "https://github.com/ssdesai/agentTooling.git",
    "repo_name": "agentTooling",
    "slug": "claim-self-twin",
    "window": {"from": "2026-06-02T14:00:00Z", "to": "2026-06-02T20:00:00Z"},
})
json.dump(d, open(path, "w"))
PY
vcapture > "$TMP/out10c.txt"

twin_count="$(field "$VPLANNING" "sum(1 for e in d['sessions'][0]['share_basis'] if e['feature'].endswith('/claim-self-twin'))")"
check "10c. the ledger's claim on the same feature deduped against the manifest's — one entry, not two" \
  "[ \"$twin_count\" = 1 ]"
# Named by the identity the ledger holds, so this fails on the pre-change tree too:
# there the surviving `agentTooling/claim-self-twin` is the LEDGER's own entry, with the
# ledger's 14:00 `from`, and the manifest's claim sits beside it under the wrong repo.
twin_source2="$(field "$VPLANNING" "next(e['source'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/claim-self-twin')")"
twin_from2="$(field "$VPLANNING" "next(e['from'] for e in d['sessions'][0]['share_basis'] if e['feature']=='agentTooling/claim-self-twin')")"
check "10d. ... and it is the manifest's, carrying the manifest's own from" \
  "[ \"$twin_source2\" = manifest ] && [ \"$twin_from2\" = '2026-06-02T10:00:00Z' ]"

# Both claimants' windows cover the whole transcript, so a two-claimant split gives
# claim-here exactly half. The phantom made it three, and three claims over a transcript
# the ledger's window opens halfway through give 5/12 — the mis-booking this feature
# exists to stop.
v_cost_here="$(field "$VPLANNING" "d['cost_usd']['total']")"
v_exp_half="$(python3 -c "print(0.5*float('$v_session_cost'))" 2>/dev/null)"
check "10e. claim-here's total is the two-claimant split, not the phantom's three-way" \
  "close_enough '$v_cost_here' '$v_exp_half'"

v_ledger_repo="$(field "$VLEDGER" "next(c['repo'] for c in d['sessions']['$VSESSION'] if c.get('slug')=='claim-here')")"
v_ledger_name="$(field "$VLEDGER" "next(c['repo_name'] for c in d['sessions']['$VSESSION'] if c.get('slug')=='claim-here')")"
check "10f. the ledger's own claim-here entry carries the declared identity" \
  "[ \"$v_ledger_repo\" = 'https://github.com/ssdesai/agentTooling.git' ]"
check "10g. ... and repo_name agentTooling, not the enclosing repo's name" \
  "[ \"$v_ledger_name\" = agentTooling ]"

# ── 10h-10j. the annotate-only path, in the vendored layout ───────────────────────────
# Everything above runs under --recapture, which skips `register_frozen_claims` outright
# and takes the recompute branch rather than the annotate-only one — so two of the four
# sites that answer "which repo does this corpus belong to" (`register_frozen_claims`,
# and the `annotate_frozen_record` call in the --all loop) had no assertion in the only
# layout where the answer differs. This is assertion 7's shape — a frozen record
# annotated by a plain --all — in the VENDORED sandbox.
#
# The ledger is rewritten to exactly the two rows a SHARED ledger really holds here, both
# under the DECLARED identity because the standalone checkout's own --self runs wrote
# them: this feature's own claim-here row, and a second feature's. Seeded rather than
# inherited from the runs above, so the fixture says the same thing whichever tree it is
# run against — on the pre-change tree those runs leave claim-here under the consumer's
# origin instead, and 10i would pass with nothing to catch.
#
# 10i is the defect: `other_session_claimants` excludes a feature's own claim by
# (repo, slug), so a frozen --self record annotated under the CONSUMER's origin misses its
# own agentTooling row and lists ITSELF among its co-claimants.
cp "$VPLANNING" "$VTMP/claim-here-frozen.json"
python3 - "$VLEDGER" "$VSESSION" <<'LEDGER_SEED'
import json, sys
path, session_id = sys.argv[1], sys.argv[2]
declared = "https://github.com/ssdesai/agentTooling.git"
window = {"from": "2026-06-02T10:00:00Z", "to": "2026-06-02T20:00:00Z"}
rows = [
    {"repo": declared, "repo_name": "agentTooling", "slug": slug, "window": window}
    for slug in ("claim-here", "claim-self-twin")
]
json.dump({"subagents": {}, "sessions": {session_id: rows}}, open(path, "w"))
LEDGER_SEED
vcapture_all > "$TMP/out10h.txt"

# A guard rather than one of the three, and the same one 7a makes in the standalone
# fixture: were the record rebuilt rather than annotated, all three below would pass off
# the recompute branch and say nothing about the two sites they exist to cover.
check "10-annotated. the frozen record is annotated, not recomputed: byte-identical but for the annotation" \
  "[ \"\$(same_but_annotation \"$VTMP/claim-here-frozen.json\" \"$VPLANNING\")\" = same ]"

v_twin_named="$(field "$VPLANNING" "sum(1 for e in (d['sessions'][0].get('also_claimed_by') or []) if e == 'agentTooling/claim-self-twin')")"
check "10h. also_claimed_by names agentTooling/claim-self-twin" \
  "[ \"$v_twin_named\" = 1 ]"

v_self_named="$(field "$VPLANNING" "sum(1 for e in (d['sessions'][0].get('also_claimed_by') or []) if e.endswith('/claim-here'))")"
check "10i. ... and nothing in it names claim-here itself, under any repo" \
  "[ \"$v_self_named\" = 0 ]"

v_frozen_rows="$(field "$VLEDGER" "sorted(c['repo'] for c in d['sessions']['$VSESSION'] if c.get('slug')=='claim-here')")"
check "10j. the ledger holds one row for the frozen record, under the declared identity" \
  "[ \"$v_frozen_rows\" = \"['https://github.com/ssdesai/agentTooling.git']\" ]"

echo
if [ "$fails" -eq 0 ]; then
  echo "session-claims: all checks passed"
else
  echo "session-claims: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
