#!/usr/bin/env bash
set -uo pipefail

# Self-test for the routing record — `analysis/routing.py`, the router exclusion in
# `capture_planning.py --list-sessions --unclaimed`, and `analysis/report.py`'s Routing
# table (self/DESIGN-2026-09-16-lifecycle-restructure.md §3.4, §4). Run by self/gate.sh,
# or by hand: bash self/tests/routing-record.sh
#
# The rule under test (design §2): the session that runs `feature-start.sh` is a
# **router**, never pinned, and its spend is a category of its own. The link from router
# to feature is a JSON record committed on the feature's branch, derived from the
# router's transcript so that two branches refreshing it write the same bytes.
#
# Scaffolding is `session-share.sh`'s: copies of `analysis/{pricing,roots,transcript,
# capture_planning,report,routing}.py` into a throwaway agentTooling checkout with a bare
# `mkdir .git` (so `roots.session_root` resolves to it), and, under a redirected `$HOME`,
# the `~/.claude/projects/*/<session-id>.jsonl` transcripts the derivation reads. No model,
# no network.
#
# Asserts, in order:
#   R1. a router transcript with two `feature-start.sh <slug>` Bash tool calls yields both
#       slugs with their timestamps, UNION the slug being started now (which the current
#       call has not flushed, so it carries a null `at`), plus `launched_in`, `git_branch`
#       from the transcript's `gitBranch`, the session's first and last instants, its span
#       and its cost through `pricing.compute_cost`;
#   R2. a second write from the same transcript is byte-identical — `captured_at` is the
#       content's as-of instant, not the wall clock, so two branches cannot conflict;
#   R3. a session with no transcript still writes a record — the current slug, null
#       figures, a warning on stderr — and never refuses the start;
#   R4. router detection is exact: `--list-sessions --unclaimed` drops the router and keeps
#       a `main` session with no such call, a session on a feature branch that has one, and
#       one launched in a worktree. It also keeps a `main` session that only *names*
#       `feature-start.sh` — `grep -n x feature-start.sh hooks` is not a start, though
#       `hooks` passes the slug pattern — while a call at command position behind `&&` and
#       `bash` still counts; a plain `--list-sessions` keeps them all;
#   R5. `report.py --all` renders a Routing table with each router's cost, minutes and
#       started slugs beside their frozen totals, plus routing spend as a fraction of
#       feature spend; `report.py <slug>` prints "routed by" for a routed feature, names
#       the slugs it was started alongside, and prints nothing extra for an unrouted one.
#
# All RED until analysis/routing.py and its two readers land. A missing script fails its
# own assertions loudly rather than aborting the run (no `set -e`), the convention
# `cost-recovery.sh` uses.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/routing.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features" "$AT/.git"

for f in pricing.py roots.py transcript.py capture_planning.py report.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
# Claude Code's project directory for a launch cwd: every `/` and `.` becomes `-`.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/.' '--')"; }

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# pj <json file> <python expr over d> — one field of a JSON file.
pj() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

MODEL="claude-opus-5"
ROUTER="r0000000-0000-0000-0000-000000000001"
PLAIN="p0000000-0000-0000-0000-000000000002"
BRANCHY="b0000000-0000-0000-0000-000000000003"
INWT="w0000000-0000-0000-0000-000000000004"
ROUTER2="r0000000-0000-0000-0000-000000000005"
GREPPY="g0000000-0000-0000-0000-000000000006"
CHAINED="c0000000-0000-0000-0000-000000000007"
GHOST="00000000-0000-0000-0000-00000000dead"
ROUTING_DIR="$AT/self/routing"
WT_ALPHA="$AT/.worktrees/alpha"

T_ALPHA="2026-09-10T10:00:00.000Z"
T_BETA="2026-09-10T10:30:00.000Z"
T_END="2026-09-10T11:00:00.000Z"
ROUTER_SPAN_S=3600

PRIMARY_PROJ="$(project_dir "$AT")"
WT_PROJ="$(project_dir "$WT_ALPHA")"
mkdir -p "$PRIMARY_PROJ" "$WT_PROJ"

# The router: launched in the primary, on main, with two feature-start.sh Bash tool calls
# and a plain response after them.
{
  bash_tool_line "$ROUTER" "$AT" "main" "m-r1" "$MODEL" "$T_ALPHA" \
    "./feature-start.sh --self alpha --method direct" 1000 2000
  bash_tool_line "$ROUTER" "$AT" "main" "m-r2" "$MODEL" "$T_BETA" \
    "./feature-start.sh --self beta" 1000 2000
  session_line "$ROUTER" "$AT" "main" "m-r3" "$MODEL" "$T_END" 1000 2000 0 0 0
} > "$PRIMARY_PROJ/$ROUTER.jsonl"
# A second router, for the report table.
{
  bash_tool_line "$ROUTER2" "$AT" "main" "m-r2a" "$MODEL" "$T_ALPHA" \
    "./feature-start.sh --self gamma" 500 1000
  session_line "$ROUTER2" "$AT" "main" "m-r2b" "$MODEL" "$T_BETA" 500 1000 0 0 0
} > "$PRIMARY_PROJ/$ROUTER2.jsonl"
# On main in the primary, no feature-start call: not a router, and still unclaimed.
session_line "$PLAIN" "$AT" "main" "m-p1" "$MODEL" "$T_ALPHA" 100 200 0 0 0 \
  > "$PRIMARY_PROJ/$PLAIN.jsonl"
# In the primary but on a feature branch, with the call: the branch term of the rule.
bash_tool_line "$BRANCHY" "$AT" "alpha" "m-b1" "$MODEL" "$T_ALPHA" \
  "./feature-start.sh --self somethingelse" 100 200 > "$PRIMARY_PROJ/$BRANCHY.jsonl"
# Launched in a worktree, with the call: the launch-directory term of the rule.
bash_tool_line "$INWT" "$WT_ALPHA" "main" "m-w1" "$MODEL" "$T_ALPHA" \
  "./feature-start.sh --self somethingelse" 100 200 > "$WT_PROJ/$INWT.jsonl"
# On main in the primary, naming feature-start.sh but never running it: the command-
# POSITION term of the rule. `hooks` would pass the slug pattern, so a match anywhere on
# the line read this as a start and silently dropped an ordinary maintenance session out
# of the one listing that surfaces unclaimed cost.
bash_tool_line "$GREPPY" "$AT" "main" "m-g1" "$MODEL" "$T_ALPHA" \
  "grep -n x feature-start.sh hooks" 100 200 > "$PRIMARY_PROJ/$GREPPY.jsonl"
# The other side of that term: the call IS at command position — second in a chain, and
# behind `bash` — so this one is a router.
bash_tool_line "$CHAINED" "$AT" "main" "m-c1" "$MODEL" "$T_ALPHA" \
  "git fetch origin && bash ./feature-start.sh --self chainedslug" 100 200 \
  > "$PRIMARY_PROJ/$CHAINED.jsonl"

routing() {
  ( HOME="$FAKE_HOME" python3 "$AT/analysis/routing.py" --self --primary "$AT" "$@" 2>&1 )
}
capture() {
  ( HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$@" 2>&1 )
}
report() {
  ( HOME="$FAKE_HOME" python3 "$AT/analysis/report.py" --self "$@" 2>&1 )
}

echo "routing record"

# ── R1. the record is derived, not typed ──────────────────────────────────────
out="$(routing --session "$ROUTER" --slug gamma)"; rc=$?
REC="$ROUTING_DIR/$ROUTER.json"
check "R1a. routing.py exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R1b. the record is at self/routing/<session-id>.json" '[[ -f "$REC" ]]'
check "R1c. session_id is the router's" '[[ "$(pj "$REC" "d[\"session_id\"]")" == "$ROUTER" ]]'
check "R1d. launched_in is the transcript's cwd" '[[ "$(pj "$REC" "d[\"launched_in\"]")" == "$AT" ]]'
check "R1e. git_branch comes from the transcript's gitBranch" '[[ "$(pj "$REC" "d[\"git_branch\"]")" == "main" ]]'
check "R1f. model names the transcript's model" '[[ "$(pj "$REC" "d[\"model\"]")" == "$MODEL" ]]'
check "R1g. started_at and ended_at are the first and last instants" \
  '[[ "$(pj "$REC" "d[\"started_at\"]")" == "2026-09-10T10:00:00Z" && "$(pj "$REC" "d[\"ended_at\"]")" == "2026-09-10T11:00:00Z" ]]'
check "R1h. duration_s is the span in whole seconds (want $ROUTER_SPAN_S)" \
  '[[ "$(pj "$REC" "d[\"duration_s\"]")" == "$ROUTER_SPAN_S" ]]'
check "R1i. cost_usd is priced through pricing.compute_cost" \
  '[[ "$(pj "$REC" "d[\"cost_usd\"] is not None and d[\"cost_usd\"] > 0")" == "True" ]]'
check "R1j. features_started names both transcript slugs and the current one, in order" \
  '[[ "$(pj "$REC" "[f[\"slug\"] for f in d[\"features_started\"]]")" == "['"'"'alpha'"'"', '"'"'beta'"'"', '"'"'gamma'"'"']" ]]'
check "R1k. each transcript slug carries the instant of its own tool call" \
  '[[ "$(pj "$REC" "[f[\"at\"] for f in d[\"features_started\"]][:2]")" == "['"'"'2026-09-10T10:00:00Z'"'"', '"'"'2026-09-10T10:30:00Z'"'"']" ]]'
check "R1l. the slug being started now has a null at — its call has not flushed" \
  '[[ "$(pj "$REC" "d[\"features_started\"][2][\"at\"]")" == "None" ]]'
check "R1m. captured_at is the content's as-of instant, equal to ended_at" \
  '[[ "$(pj "$REC" "d[\"captured_at\"]")" == "$(pj "$REC" "d[\"ended_at\"]")" && -n "$(pj "$REC" "d[\"captured_at\"]")" ]]'

# ── R2. a second write is byte-identical ──────────────────────────────────────
cp "$REC" "$TMP/record.before"
routing --session "$ROUTER" --slug gamma >/dev/null 2>&1; rc=$?
check "R2a. a second write from the same transcript exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R2b. ... and is byte-identical" 'cmp -s "$TMP/record.before" "$REC"'

# ── R3. a missing transcript never refuses the start ──────────────────────────
out="$(routing --session "$GHOST" --slug delta)"; rc=$?
GREC="$ROUTING_DIR/$GHOST.json"
check "R3a. a session with no transcript still exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R3b. ... and writes a record naming the current slug" \
  '[[ -f "$GREC" && "$(pj "$GREC" "[f[\"slug\"] for f in d[\"features_started\"]]")" == "['"'"'delta'"'"']" ]]'
check "R3c. ... with null figures" \
  '[[ "$(pj "$GREC" "d[\"cost_usd\"] is None and d[\"started_at\"] is None and d[\"duration_s\"] is None")" == "True" ]]'
check "R3d. ... and one warning line naming the session" 'grep -qi "transcript" <<<"$out" && grep -q "$GHOST" <<<"$out"'
rm -f "$GREC"

# ── R4. router detection is exact ─────────────────────────────────────────────
unclaimed="$(capture --list-sessions --unclaimed)"
check "R4a. the router is not listed as unclaimed" '! grep -q "$ROUTER" <<<"$unclaimed"'
check "R4b. ... nor the second router" '! grep -q "$ROUTER2" <<<"$unclaimed"'
check "R4c. a main session with no feature-start call is still listed" 'grep -q "$PLAIN" <<<"$unclaimed"'
check "R4d. a session on a feature branch with the call is not a router" 'grep -q "$BRANCHY" <<<"$unclaimed"'
check "R4e. a session launched in a worktree with the call is not a router" 'grep -q "$INWT" <<<"$unclaimed"'
check "R4f. a main session that only greps feature-start.sh is still listed as unclaimed" \
  'grep -q "$GREPPY" <<<"$unclaimed"'
check "R4g. ... while one that runs it after && behind bash is a router" \
  '! grep -q "$CHAINED" <<<"$unclaimed"'
listed="$(capture --list-sessions)"
check "R4h. a plain --list-sessions still shows the router" 'grep -q "$ROUTER" <<<"$listed"'

# ── R5. the report ────────────────────────────────────────────────────────────
# Three routed features and one unrouted, each a minimal manifest plus a frozen
# planning.json — enough for report.py to write a report.json the Routing table reads.
write_feature() {                       # write_feature <slug> <total-usd>
  local slug="$1" total="$2" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  printf '# %s\n\nTest fixture only, for self/tests/routing-record.sh.\n\n```json\n{"slug": "%s", "method": "direct", "plans": [], "branches": ["%s"]}\n```\n' \
    "$slug" "$slug" "$slug" > "$dir/README.md"
  printf '{"cost_usd": {"total": %s, "total_is_partial": false}, "sessions": [], "subagents": [], "priced": []}\n' \
    "$total" > "$dir/planning.json"
}
write_feature alpha 3.0
write_feature beta 5.0
write_feature gamma 2.0
write_feature unrouted 7.0
routing --session "$ROUTER2" --slug gamma >/dev/null 2>&1
for slug in alpha beta gamma unrouted; do report "$slug" >/dev/null 2>&1; done

all_out="$(report --all)"
check "R5a. the Routing table names both router sessions" \
  'grep -q "$ROUTER" <<<"$all_out" && grep -q "$ROUTER2" <<<"$all_out"'
check "R5b. ... with each started slug beside its frozen total" \
  'grep -E "$ROUTER.*alpha.*3\.00" <<<"$all_out" >/dev/null && grep -E "$ROUTER.*beta.*5\.00" <<<"$all_out" >/dev/null'
check "R5c. ... and routing spend as a fraction of feature spend" \
  'grep -qi "routing" <<<"$all_out" && grep -q "%" <<<"$all_out"'
check "R5d. an unrouted feature is not named in the Routing table" \
  '! grep -q "unrouted" <<<"$(grep -A100 -i "routing" <<<"$all_out")"'

alpha_out="$(report alpha)"
check "R5e. a routed feature's report names the router that started it" \
  'grep -q "routed by" <<<"$alpha_out" && grep -q "$ROUTER" <<<"$alpha_out"'
check "R5f. ... and the slugs it was started alongside" 'grep -q "beta" <<<"$alpha_out"'
unrouted_out="$(report unrouted)"
check "R5g. an unrouted feature's report says nothing about routing" \
  '! grep -q "routed by" <<<"$unrouted_out"'

echo
if (( fails > 0 )); then echo "routing record: $fails assertion(s) FAILED"; exit 1; fi
echo "routing record: all assertions passed"
