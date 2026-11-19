#!/usr/bin/env bash
set -uo pipefail

# Self-test for orchestration records living in the repo that ran them (self/features/
# orchestration-records-in-repo): without `--self` a record is written to, read from and priced
# against the CONSUMING repo (`plans/orchestrations/<slug>/`, its features' `report` paths
# relative to that repo's root); with `--self` it is agentTooling's own `self/orchestrations/`,
# as before. Run by self/gate.sh, or by hand: bash self/tests/orchestration-records-in-repo.sh
#
# The fixture is consumer-shaped: a repo with agentTooling vendored under it (no `.git` of its
# own, as `git subtree` leaves it) and `plans/features/<slug>/report.json` carrying
# `cost.total`.
#
# Asserts:
#   R1. `orchestration-start.sh <slug> --coordinator --session K` writes
#       `plans/orchestrations/<slug>/README.md` in the consuming repo and nothing under
#       `agentTooling/self/orchestrations/`; `--self` from the vendored copy is refused and
#       writes in neither (self/features/consumer-record-guard/; its own test,
#       consumer-record-guard.sh, holds every writer);
#   R2. `manifest.py --orchestration <slug> add-feature … report=plans/features/<f>/report.json`
#       then `report.py --orchestration <slug>` prices the feature with no `--checkout`:
#       `unpriced_count` 0 and the group total is the feature's total; the home repo's name is
#       compared case-insensitively; a missing report in the home repo says the path does not
#       exist; a feature in another repository without a checkout still asks for `--checkout`;
#       `--checkout` still wins; (under `--self` a feature in agentTooling resolves against
#       agentTooling: R7, in the standalone checkout, since consumer-record-guard);
#   R3. a slug found only at the legacy vendored `agentTooling/self/orchestrations/<slug>` is
#       refused (exit 1) by `report.py --orchestration`, `manifest.py --orchestration … get`
#       and `orchestration-capture.sh`, naming `git mv agentTooling/self/orchestrations/<slug>
#       plans/orchestrations/<slug>`, writing nothing; `orchestration-start.sh` refuses the
#       same slug too; with `--self` the legacy record is just a record and reads as before;
#   R4. `hooks/orchestrator_role.py` returns an orchestrator record under
#       `plans/orchestrations/`, and nothing for a coordinator record there;
#   R5. `analysis/coordinator_check.py` counts a record under `plans/orchestrations/` as
#       naming its session.
# Round 2 (NOTES.md rulings 14-17):
#   R3 (amended). only a STRANDED legacy record — its last fence lists a feature whose repo is
#       the consuming repo's, any case — draws the `git mv`;
#   R6. agentTooling's own shipped records vendored in the consumer (a feature in agentTooling,
#       or no feature) draw no `git mv` from any tool, say they are agentTooling's own and name
#       `--self`, and a start of the same slug is NOT refused: it writes plans/orchestrations/;
#   R7. in a standalone agentTooling checkout (`.git` in it) every record tool without `--self`
#       (start, capture, manifest, report, orchestration_capture.py) refuses (1), naming
#       `--self`, and writes nothing — least of all in the checkout's parent; `--self` still works,
#       its next steps carry `--self`, and its report prices an agentTooling feature from the
#       checkout's own root;
#   R8. the role hook ignores the parent's `plans/orchestrations/` from a standalone checkout and
#       still reads it from a vendored copy;
#   R9. the coordinator advisory names `--self` for a `--self` start in agentTooling's own
#       checkout, and not otherwise — not from a vendored copy, where that start is refused
#       (consumer-record-guard) — and feature-start.sh passes the mode through;
#   R10. the classifier is one: `roots.py stranded` answers yes for a stranded record and no for
#       a shipped one. (That the shell's roots and refusal texts are roots.py's is no longer
#       asserted by comparing copies: both read hooks/shared_rules.py, held by shared-rules.sh.)
# Round 3 (merged with hook-role-hardening; NOTES.md round-3 rulings):
#   R11. the role's history and ledger sources span both roots: a COMMITTED plans/orchestrations
#       record edited to a coordinator or deleted still names its session; a consumer ledger line
#       names the plans/orchestrations folder of its slug (or the consumer root when there is
#       none); the real start's ledger line holds the role for a deleted uncommitted record; a
#       standalone checkout reads neither its parent's working tree nor its parent's history.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/orchestration-records-in-repo.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
CONSUMER="$TMP/consumer"
AT="$CONSUMER/agentTooling"
FAKE_HOME="$TMP/home"
export HOME="$FAKE_HOME"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_SESSION_ID

ANALYSIS_FILES="pricing.py litellm_prices.py rates_history.json roots.py transcript.py routing.py manifest.py capture_planning.py report.py orchestration_capture.py coordinator_check.py"
# vendor_tooling <dir>: the scripts this test runs, copied to <dir> as a vendored agentTooling
vendor_tooling() {
  mkdir -p "$1/analysis" "$1/hooks" "$1/templates/plans/features" "$1/self/features"
  mkdir -p "$1/hooks" && cp "$HERE/hooks/shared_rules.py" "$1/hooks/"  # roots.py imports it
  for f in $ANALYSIS_FILES; do
    cp "$HERE/analysis/$f" "$1/analysis/$f"
  done
  cp "$HERE/hooks/brief_header.py" "$HERE/hooks/orchestrator_role.py" "$1/hooks/"
  cp "$HERE/templates/plans/features/TEMPLATE.md" "$1/templates/plans/features/TEMPLATE.md"
  cp "$HERE/orchestration-start.sh" "$HERE/orchestration-capture.sh" "$HERE/plan-runner-roots.sh" "$1/"
  # The start decides the profile through env-profile.sh (orchestration-start-branch-v2)
  cp "$HERE/env-profile.sh" "$1/"; cp "$HERE/hooks/env_profile.py" "$1/hooks/"
}
# Pinned local: the cloud branch rule is orchestrator-role.sh's B
export AGENTTOOLING_PROFILE=local
mkdir -p "$FAKE_HOME/.claude/projects"
vendor_tooling "$AT"
# The consuming repo is the git checkout; the vendored agentTooling has no `.git` of its own.
git -C "$CONSUMER" init -q -b main
git -C "$CONSUMER" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

MANIFEST=(python3 -B "$AT/analysis/manifest.py")
REPORT=(python3 -B "$AT/analysis/report.py")
CHECK=(python3 -B "$AT/analysis/coordinator_check.py")
ROLE=(python3 -B "$AT/hooks/orchestrator_role.py")
K="cccccccc-0000-0000-0000-00000000000a"
O="dddddddd-0000-0000-0000-00000000000b"
L="eeeeeeee-0000-0000-0000-00000000000c"  # the legacy record's orchestrator
SLUG="wave"
PLANS_REL="plans/orchestrations"
LEGACY_REL="agentTooling/self/orchestrations"
FOLDER="$CONSUMER/$PLANS_REL/$SLUG"
RECORD="$FOLDER/README.md"
fence_get() {
  python3 -c '
import json, re, sys
text = open(sys.argv[1]).read()
d = json.loads(re.findall(r"```json\n(.*?)\n```", text, re.S)[-1])
print(eval(sys.argv[2]))' "$1" "$2"
}
json_get() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
# roots_text <NAME> [slug]: a message constant of analysis/roots.py, formatted for <slug>
roots_text() {
  python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); import roots; print(getattr(roots, sys.argv[2]).format(slug=sys.argv[3]))' \
    "$HERE/analysis" "$1" "${2:-x}"
}

# The features the record will price: two reports in the consuming repo, one in agentTooling
mkdir -p "$CONSUMER/plans/features/feat-x" "$CONSUMER/plans/features/feat-y" "$AT/self/features/feat-s"
printf '{"cost": {"total": 13.54}}\n' > "$CONSUMER/plans/features/feat-x/report.json"
printf '{"cost": {"total": 8.14}}\n' > "$CONSUMER/plans/features/feat-y/report.json"
printf '{"cost": {"total": 2.0}}\n' > "$AT/self/features/feat-s/report.json"

echo "== R1 start writes into the repo that ran it =="
out="$("$AT/orchestration-start.sh" "$SLUG" --coordinator --session "$K" 2>&1)"; rc=$?
check "R1 a start with no --self exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R1 the record is $PLANS_REL/$SLUG/README.md in the consuming repo" '[[ -f "$RECORD" ]]'
check "R1 nothing is written inside the vendored agentTooling" '[[ ! -e "$AT/self/orchestrations" ]]'
check "R1 the start's output names plans/orchestrations and no --self in its next steps" '[[ "$out" == *"$PLANS_REL/$SLUG/README.md"* && "$out" != *"--self"* ]]'
# --self from a vendored copy writes nothing in either root (self/features/consumer-record-guard/,
# whose own test holds every writer); --self writing self/orchestrations/ is R7's, standalone.
"$AT/orchestration-start.sh" --self selfwave --coordinator --session "$O" >/dev/null 2>&1; rc=$?
check "R1 --self from a vendored copy is refused (1) and writes in neither root (got $rc)" '[[ $rc -eq 1 && ! -e "$AT/self/orchestrations/selfwave" && ! -e "$CONSUMER/$PLANS_REL/selfwave" ]]'
"$AT/orchestration-start.sh" "$SLUG" --coordinator --session "$K" >/dev/null 2>&1; rc=$?
check "R1 a second start of the same slug is refused (1)" '[[ $rc -eq 1 ]]'

echo "== R2 report prices from the record's own repo root =="
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=consumer slug=feat-x report=plans/features/feat-x/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=Consumer slug=feat-y report=plans/features/feat-y/report.json >/dev/null
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null 2>&1; rc=$?
R="$FOLDER/report.json"
check "R2 report.py --orchestration exits 0 and writes beside the record (got $rc)" '[[ $rc -eq 0 && -f "$R" && -f "$FOLDER/report.md" ]]'
check "R2 both features are priced with no --checkout (unpriced_count 0)" '[[ "$(json_get "$R" "d[\"unpriced_count\"]")" == "0" ]]'
check "R2 the features total is the two reports (13.54 + 8.14)" '[[ "$(json_get "$R" "round(d[\"features_total_usd\"], 2)")" == "21.68" ]]'
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=consumer slug=feat-gone report=plans/features/feat-gone/report.json >/dev/null
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=other slug=feat-o report=plans/features/feat-o/report.json >/dev/null
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null 2>&1
check "R2 a missing report in the home repo says the path does not exist" '[[ "$(json_get "$R" "[f[\"unpriced_reason\"] for f in d[\"features\"] if f[\"slug\"]==\"feat-gone\"][0]")" == *"does not exist"* ]]'
check "R2 a feature in another repo with no checkout asks for --checkout" '[[ "$(json_get "$R" "[f[\"unpriced_reason\"] for f in d[\"features\"] if f[\"slug\"]==\"feat-o\"][0]")" == *"--checkout other="* ]]'
mkdir -p "$TMP/other-checkout/plans/features/feat-o"
printf '{"cost": {"total": 1.0}}\n' > "$TMP/other-checkout/plans/features/feat-o/report.json"
"${REPORT[@]}" --orchestration "$SLUG" --checkout "other=$TMP/other-checkout" >/dev/null 2>&1
check "R2 --checkout still prices a feature in another repository" '[[ "$(json_get "$R" "[f[\"total_usd\"] for f in d[\"features\"] if f[\"slug\"]==\"feat-o\"][0]")" == "1.0" ]]'
# An agentTooling feature in a consuming repo's record: agentTooling is on disk as the vendored
# directory, so its `self/features/<slug>/report.json` is priced from there with no --checkout
# (self/features/orchestration-record-fixes/, item 2)
mkdir -p "$AT/self/features/feat-a"
printf '{"cost": {"total": 0.75}}\n' > "$AT/self/features/feat-a/report.json"
"${MANIFEST[@]}" --orchestration "$SLUG" add-feature repo=agentTooling slug=feat-a report=self/features/feat-a/report.json >/dev/null
"${REPORT[@]}" --orchestration "$SLUG" >/dev/null 2>&1
check "R2 an agentTooling entry is priced from the vendored agentTooling/ with no --checkout" '[[ "$(json_get "$R" "[f[\"total_usd\"] for f in d[\"features\"] if f[\"slug\"]==\"feat-a\"][0]")" == "0.75" ]]'

echo "== R3 a record at the legacy vendored place is moved, not read =="
LEGACY="$CONSUMER/$LEGACY_REL"
mkdir -p "$LEGACY/old"
printf '# old\n\n```json\n{"slug": "old", "session": "%s", "features": [{"repo": "Consumer", "slug": "feat-x"}]}\n```\n' "$L" > "$LEGACY/old/README.md"
MOVE="git mv $LEGACY_REL/old $PLANS_REL/old"
before="$(find "$CONSUMER/$PLANS_REL" "$LEGACY" | sort)"
out="$("${REPORT[@]}" --orchestration old 2>&1)"; rc=$?
check "R3 report.py refuses (1), printing the git mv (got $rc)" '[[ $rc -eq 1 && "$out" == *"$MOVE"* ]]'
out="$("${MANIFEST[@]}" --orchestration old get session 2>&1)"; rc=$?
check "R3 manifest.py --orchestration refuses (1), printing the git mv (got $rc)" '[[ $rc -eq 1 && "$out" == *"$MOVE"* ]]'
out="$("${MANIFEST[@]}" --orchestration old add-feature repo=consumer slug=feat-x 2>&1)"; rc=$?
check "R3 an add-feature is refused too (1)" '[[ $rc -eq 1 && "$out" == *"$MOVE"* ]]'
out="$("$AT/orchestration-capture.sh" old 2>&1)"; rc=$?
check "R3 orchestration-capture.sh refuses (1), printing the git mv (got $rc)" '[[ $rc -eq 1 && "$out" == *"$MOVE"* ]]'
out="$("$AT/orchestration-start.sh" old --coordinator --session "$O" 2>&1)"; rc=$?
check "R3 orchestration-start.sh refuses the same slug (1), printing the git mv (got $rc)" '[[ $rc -eq 1 && "$out" == *"$MOVE"* ]]'
check "R3 the start's refusal carries the LEGACY_RECORD_REFUSAL text word for word (output: the shell reads it from shared_rules)" '[[ "$out" == *"$(roots_text LEGACY_RECORD_REFUSAL old)"* ]]'
out="$("${REPORT[@]}" --orchestration old 2>&1)"
check "R3 report.py's refusal is the same text" '[[ "$out" == *"$(roots_text LEGACY_RECORD_REFUSAL old)"* ]]'
check "R3 a refusal wrote nothing" '[[ "$(find "$CONSUMER/$PLANS_REL" "$LEGACY" | sort)" == "$before" ]]'
out="$("${MANIFEST[@]}" --self --orchestration old get session 2>&1)"; rc=$?
check "R3 under --self the same record reads as before (got $rc)" '[[ $rc -eq 0 && "$out" == "$L" ]]'
git -C "$CONSUMER" mv "$LEGACY_REL/old" "$PLANS_REL/old" 2>/dev/null || { mkdir -p "$CONSUMER/$PLANS_REL" && mv "$LEGACY/old" "$CONSUMER/$PLANS_REL/old"; }
out="$("${MANIFEST[@]}" --orchestration old get session 2>&1)"; rc=$?
check "R3 after the move the record reads in the consuming repo (got $rc)" '[[ $rc -eq 0 && "$out" == "$L" ]]'

echo "== R4 the role guard reads plans/orchestrations =="
"$AT/orchestration-start.sh" orch --session "$O" >/dev/null 2>&1; rc=$?
check "R4 an orchestrator start writes plans/orchestrations/orch (got $rc)" '[[ $rc -eq 0 && -f "$CONSUMER/$PLANS_REL/orch/README.md" ]]'
check "R4 the role is found for the orchestrator's session" '[[ "$("${ROLE[@]}" "$AT" "$O")" == "$CONSUMER/$PLANS_REL/orch/README.md" ]]'
check "R4 a coordinator record under plans/orchestrations is no role" '[[ -z "$("${ROLE[@]}" "$AT" "$K")" ]]'

echo "== R5 the coordinator advisory counts records in both roots =="
mkdir -p "$TMP/outside" "$FAKE_HOME/.claude/projects/-outside"
printf '{"type":"user","sessionId":"%s","cwd":"%s","gitBranch":"HEAD","timestamp":"2026-07-02T10:00:00.000Z","message":{"role":"user","content":"hi"}}\n' "$K" "$TMP/outside" > "$FAKE_HOME/.claude/projects/-outside/$K.jsonl"
check "R5 a session named by a plans/orchestrations record gets no advisory" '[[ -z "$("${CHECK[@]}" "$K" "$AT")" ]]'
rm -rf "$CONSUMER/$PLANS_REL/$SLUG" "$CONSUMER/$PLANS_REL/old"
check "R5 ... and one no record names does" '[[ "$("${CHECK[@]}" "$K" "$AT")" == *"--coordinator --session $K"* ]]'

echo "== R6 agentTooling's own shipped records are never 'stranded' =="
# A consumer's vendored agentTooling/self/orchestrations/ holds agentTooling's own records. One
# lists a feature in agentTooling, one lists none, one has a consumer feature in an EARLIER fence
# only (the last fence is the record).
LEGACY="$CONSUMER/$LEGACY_REL"
mkdir -p "$LEGACY/program-ab" "$LEGACY/idle-one" "$LEGACY/fence-last"
printf '# p\n\n```json\n{"slug": "program-ab", "session": "%s", "features": [{"repo": "agentTooling", "slug": "feat-s"}]}\n```\n' "$L" > "$LEGACY/program-ab/README.md"
printf '# i\n\n```json\n{"slug": "idle-one", "session": "%s", "features": []}\n```\n' "$L" > "$LEGACY/idle-one/README.md"
printf '# f\n\n```json\n{"features": [{"repo": "consumer", "slug": "feat-x"}]}\n```\n\n```json\n{"slug": "fence-last", "session": "%s", "features": []}\n```\n' "$L" > "$LEGACY/fence-last/README.md"
for s in program-ab idle-one fence-last; do
  before="$(find "$CONSUMER/$PLANS_REL" "$LEGACY" | sort)"
  out="$("${REPORT[@]}" --orchestration "$s" 2>&1)"; rc=$?
  check "R6 report.py ($s): refuses (1) with roots.py's own-record note, no git mv" '[[ $rc -eq 1 && "$out" == *"$(roots_text OWN_RECORD_NOTE "$s")"* && "$out" == *"--self"* && "$out" != *"git mv"* ]]'
  out="$("${MANIFEST[@]}" --orchestration "$s" get session 2>&1)"; rc=$?
  check "R6 manifest.py ($s): the same" '[[ $rc -eq 1 && "$out" == *"$(roots_text OWN_RECORD_NOTE "$s")"* && "$out" != *"git mv"* ]]'
  out="$("$AT/orchestration-capture.sh" "$s" 2>&1)"; rc=$?
  check "R6 orchestration-capture.sh ($s): the same" '[[ $rc -eq 1 && "$out" == *"$(roots_text OWN_RECORD_NOTE "$s")"* && "$out" != *"git mv"* ]]'
  check "R6 ($s): the refusals wrote nothing" '[[ "$(find "$CONSUMER/$PLANS_REL" "$LEGACY" | sort)" == "$before" ]]'
  out="$("${MANIFEST[@]}" --self --orchestration "$s" get session 2>&1)"; rc=$?
  check "R6 ($s): under --self it reads as agentTooling's own record (got $rc)" '[[ $rc -eq 0 && "$out" == "$L" ]]'
done
legacy_before="$(cat "$LEGACY/program-ab/README.md")"
out="$("$AT/orchestration-start.sh" program-ab --coordinator --session "$O" 2>&1)"; rc=$?
check "R6 a start named like a shipped record is NOT refused (0; got $rc)" '[[ $rc -eq 0 && -f "$CONSUMER/$PLANS_REL/program-ab/README.md" ]]'
check "R6 ... and the shipped record is untouched" '[[ "$(cat "$LEGACY/program-ab/README.md")" == "$legacy_before" ]]'
mkdir -p "$LEGACY/fresh-start"
printf '# s\n\n```json\n{"slug": "fresh-start", "session": "%s", "features": [{"repo": "CONSUMER", "slug": "feat-y"}]}\n```\n' "$L" > "$LEGACY/fresh-start/README.md"
out="$("$AT/orchestration-start.sh" fresh-start --coordinator --session "$O" 2>&1)"; rc=$?
check "R6 a stranded record (its feature repo in another case) still blocks a start, with the git mv (got $rc)" '[[ $rc -eq 1 && "$out" == *"git mv $LEGACY_REL/fresh-start $PLANS_REL/fresh-start"* ]]'

echo "== R7 a no-flag record tool in agentTooling's own checkout refuses =="
SA_PARENT="$TMP/standalone"
SA="$SA_PARENT/agentTooling"
vendor_tooling "$SA"
git -C "$SA" init -q -b main
SA_MANIFEST=(python3 -B "$SA/analysis/manifest.py")
SA_REPORT=(python3 -B "$SA/analysis/report.py")
SA_ROLE=(python3 -B "$SA/hooks/orchestrator_role.py")
STANDALONE_TEXT="$(roots_text STANDALONE_REFUSAL)"
snap() { find "$SA_PARENT" | sort; }
before="$(snap)"
out="$("$SA/orchestration-start.sh" wave --coordinator --session "$K" 2>&1)"; rc=$?
check "R7 orchestration-start.sh refuses (1) with roots.py's STANDALONE_REFUSAL naming --self (got $rc)" '[[ $rc -eq 1 && "$out" == *"$STANDALONE_TEXT"* && "$out" == *"--self"* ]]'
out="$("$SA/orchestration-capture.sh" wave 2>&1)"; rc=$?
check "R7 orchestration-capture.sh refuses (1), the same text (got $rc)" '[[ $rc -eq 1 && "$out" == *"$STANDALONE_TEXT"* ]]'
out="$(python3 -B "$SA/analysis/orchestration_capture.py" wave 2>&1)"; rc=$?
check "R7 orchestration_capture.py refuses (1), the same text (got $rc)" '[[ $rc -eq 1 && "$out" == *"$STANDALONE_TEXT"* ]]'
out="$("${SA_MANIFEST[@]}" --orchestration wave get session 2>&1)"; rc=$?
check "R7 manifest.py --orchestration refuses (1), the same text (got $rc)" '[[ $rc -eq 1 && "$out" == *"$STANDALONE_TEXT"* ]]'
out="$("${SA_REPORT[@]}" --orchestration wave 2>&1)"; rc=$?
check "R7 report.py --orchestration refuses (1), the same text (got $rc)" '[[ $rc -eq 1 && "$out" == *"$STANDALONE_TEXT"* ]]'
check "R7 the refusals wrote nothing, in the checkout or its parent" '[[ "$(snap)" == "$before" && ! -e "$SA_PARENT/plans" ]]'
out="$("$SA/orchestration-start.sh" --self wave --coordinator --session "$O" 2>&1)"; rc=$?
check "R7 --self starts agentTooling's own record in the checkout (got $rc)" '[[ $rc -eq 0 && -f "$SA/self/orchestrations/wave/README.md" && ! -e "$SA_PARENT/plans" ]]'
check "R7 the --self start's next steps carry --self" 'grep -q -- "--self --orchestration wave" "$SA/self/orchestrations/wave/README.md"'
mkdir -p "$SA/self/features/feat-s"
printf '{"cost": {"total": 2.0}}\n' > "$SA/self/features/feat-s/report.json"
"${SA_MANIFEST[@]}" --self --orchestration wave add-feature repo=agentTooling slug=feat-s report=self/features/feat-s/report.json >/dev/null
"${SA_REPORT[@]}" --self --orchestration wave >/dev/null 2>&1; rc=$?
check "R7 --self report reads it (got $rc)" '[[ $rc -eq 0 ]]'
check "R7 under --self a feature in agentTooling is priced from agentTooling's root" '[[ "$(json_get "$SA/self/orchestrations/wave/report.json" "(d[\"unpriced_count\"], d[\"features_total_usd\"])")" == "(0, 2.0)" ]]'

echo "== R8 the role hook reads the parent's plans/orchestrations only from a vendored copy =="
mkdir -p "$SA_PARENT/$PLANS_REL/stray"
P="ffffffff-0000-0000-0000-00000000000d"  # the stray record's orchestrator
printf '# s\n\n```json\n{"slug": "stray", "session": "%s", "features": []}\n```\n' "$P" > "$SA_PARENT/$PLANS_REL/stray/README.md"
check "R8 a standalone checkout ignores a record in its parent's plans/orchestrations (no role)" '[[ -z "$("${SA_ROLE[@]}" "$SA" "$P")" ]]'
mkdir -p "$CONSUMER/$PLANS_REL/stray"
printf '# s\n\n```json\n{"slug": "stray", "session": "%s", "features": []}\n```\n' "$P" > "$CONSUMER/$PLANS_REL/stray/README.md"
check "R8 a vendored copy still reads its consuming repo's plans/orchestrations" '[[ "$("${ROLE[@]}" "$AT" "$P")" == "$CONSUMER/$PLANS_REL/stray/README.md" ]]'

echo "== R9 the coordinator advisory names the mode's flag =="
# --self is named only where the start may write it: agentTooling's own checkout. From a
# vendored copy that start is refused (self/features/consumer-record-guard/), so it names none.
out_self="$(python3 -B "$SA/analysis/coordinator_check.py" "$K" "$SA" --self)"
out_vendored_self="$("${CHECK[@]}" "$K" "$AT" --self)"
out_plain="$("${CHECK[@]}" "$K" "$AT")"
check "R9 for a --self start in agentTooling's own checkout the advisory says orchestration-start.sh --self <slug>" '[[ "$out_self" == *"orchestration-start.sh --self <slug> --coordinator --session $K"* ]]'
check "R9 for a --self start from a vendored copy it names no flag (that start is refused there)" '[[ "$out_vendored_self" == *"orchestration-start.sh <slug> --coordinator --session $K"* && "$out_vendored_self" != *"--self"* ]]'
check "R9 otherwise it names no flag" '[[ "$out_plain" == *"orchestration-start.sh <slug> --coordinator --session $K"* && "$out_plain" != *"--self"* ]]'
check "R9 feature-start.sh hands its mode to coordinator_check.py" 'grep -q "COORDINATOR_CHECK_MODULE\" \"\$ROUTER_SESSION\" \"\$WORKTREE\" .*SELF_FLAG" "$HERE/feature-start.sh"'

echo "== R10 the stranded-record classifier is one =="
# The shell's two relative roots and refusal texts are no longer a copy of roots.py's to be
# held equal: both read hooks/shared_rules.py (self/tests/shared-rules.sh holds that).
python3 -B "$AT/analysis/roots.py" stranded fresh-start; s1=$?
python3 -B "$AT/analysis/roots.py" stranded program-ab; s2=$?
check "R10 the classifier is one: roots.py stranded says yes (0) for a stranded record, no (1) for a shipped one (got $s1, $s2)" '[[ $s1 -eq 0 && $s2 -eq 1 ]]'

echo "== R11 the role's history and ledger sources span both roots (round 3, merged with hook-role-hardening) =="
GIT_ID=(-c user.name=t -c user.email=t@example.com)
H="abababab-0000-0000-0000-00000000000e"  # a committed plans/orchestrations record's orchestrator
mkdir -p "$CONSUMER/$PLANS_REL/hist"
printf '# h\n\n```json\n{"slug": "hist", "session": "%s", "features": []}\n```\n' "$H" > "$CONSUMER/$PLANS_REL/hist/README.md"
git -C "$CONSUMER" add "$PLANS_REL/hist/README.md"
git -C "$CONSUMER" "${GIT_ID[@]}" commit -q -m "hist record"
printf '# h\n\n```json\n{"slug": "hist", "kind": "coordinator", "session": "%s", "features": []}\n```\n' "$H" > "$CONSUMER/$PLANS_REL/hist/README.md"
check "R11 a committed plans/orchestrations record edited to a coordinator in the working tree still names its session (history)" '[[ "$("${ROLE[@]}" -- "$AT" "$H")" == "$CONSUMER/$PLANS_REL/hist/README.md" ]]'
rm -rf "$CONSUMER/$PLANS_REL/hist"
check "R11 ... and with the record deleted" '[[ "$("${ROLE[@]}" -- "$AT" "$H")" == "$CONSUMER/$PLANS_REL/hist/README.md" ]]'
Q="acacacac-0000-0000-0000-00000000000f"  # named by the consumer's ledger only
mkdir -p "$CONSUMER/$PLANS_REL/ledgered"
printf '%s ledgered\n' "$Q" >> "$CONSUMER/.git/agenttooling-orchestrators"
check "R11 a ledger line names the plans/orchestrations folder that holds its slug" '[[ "$("${ROLE[@]}" -- "$AT" "$Q")" == "$CONSUMER/$PLANS_REL/ledgered/README.md" ]]'
Q2="adadadad-0000-0000-0000-000000000010"
printf '%s vanished\n' "$Q2" >> "$CONSUMER/.git/agenttooling-orchestrators"
check "R11 a ledger slug with no folder in either root is still the role, under the consuming repo's root" '[[ "$("${ROLE[@]}" -- "$AT" "$Q2")" == "$CONSUMER/$PLANS_REL/vanished/README.md" ]]'
O2="aeaeaeae-0000-0000-0000-000000000011"  # an orchestrator started by the real script
"$AT/orchestration-start.sh" written --session "$O2" >/dev/null 2>&1
check "R11 orchestration-start.sh appends the consumer's ledger, so a deleted uncommitted plans record keeps the role" \
  'rm -rf "$CONSUMER/$PLANS_REL/written"; [[ "$("${ROLE[@]}" -- "$AT" "$O2")" == "$CONSUMER/$PLANS_REL/written/README.md" ]]'
git -C "$SA_PARENT" init -q -b main
git -C "$SA_PARENT" add "$PLANS_REL/stray/README.md"
git -C "$SA_PARENT" "${GIT_ID[@]}" commit -q -m "stray record"
rm -rf "$SA_PARENT/$PLANS_REL/stray"
check "R11 a standalone checkout never reads its parent's plans/orchestrations history either (no role)" '[[ -z "$("${SA_ROLE[@]}" -- "$SA" "$P")" ]]'

echo ""
if (( fails )); then
  echo "orchestration-records-in-repo: $fails check(s) FAILED"
  exit 1
fi
echo "orchestration-records-in-repo: all checks passed"
