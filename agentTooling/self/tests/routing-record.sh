#!/usr/bin/env bash
set -uo pipefail

# Self-test for the routing record — `analysis/routing.py`, the router exclusion in
# `capture_planning.py --list-sessions --unclaimed`, and `analysis/report.py`'s Routing
# table (self/DESIGN-2026-09-16-lifecycle-restructure.md §3.4, §4;
# self/DESIGN-2026-09-18-ledger-and-routing.md §1). Run by self/gate.sh, or by hand:
# bash self/tests/routing-record.sh
#
# The rule under test (design 2026-09-16 §2): the session that runs `feature-start.sh` is
# a **router**, never pinned, and its spend is a category of its own. The link from router
# to feature is a JSON record committed on the feature's branch, derived from the router's
# transcript so that two branches refreshing it write the same bytes.
#
# **The record lives in the feature it links** (design 2026-09-18 §1):
# `<features root>/<slug>/routing.json`, one copy per feature, so no two features ever
# write one path and two branches cut from the same `main` cannot conflict. A router that
# started three features has three copies of its record, and the reader that wants one row
# per router keeps the copy with the latest `captured_at`.
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
#       and its cost through `pricing.compute_cost` — written to
#       `self/features/<slug>/routing.json`, the directory of the feature being started;
#   R2. a second write from the same transcript is byte-identical — `captured_at` is the
#       content's as-of instant, not the wall clock;
#   R3. a session with no transcript still writes a record — the current slug, null
#       figures, a warning on stderr — and never refuses the start;
#   R4. router detection is exact: `--list-sessions --unclaimed` drops the router and keeps
#       a `main` session with no such call, a session on a feature branch that has one, and
#       one launched in a worktree. It also keeps a `main` session that only *names*
#       `feature-start.sh` — `grep -n x feature-start.sh hooks` is not a start, though
#       `hooks` passes the slug pattern — while a call at command position behind `&&` and
#       `bash` still counts; a plain `--list-sessions` keeps them all. A start whose own
#       line carries no slug starts no feature, so its session is not a router either and
#       stays in the listing (R10's rule seen from the outside);
#   R5. `report.py --all` renders a Routing table with each router's cost, minutes and
#       started slugs beside their frozen totals, plus routing spend as a fraction of
#       feature spend, and ONE row per router though three feature directories hold that
#       router's record; `report.py <slug>` prints "routed by" for a routed feature from
#       that feature's own copy, names the slugs it was started alongside, and prints
#       nothing extra for an unrouted one;
#   R6. `routing.py --refresh-for <slug>` — what feature-capture.sh runs — rewrites
#       `<slug>/routing.json` from the router's transcript as it stands now, keeps the
#       prior record's slugs the transcript never carried, prints the path it rewrote,
#       is byte-identical on a second run, prints nothing for a slug with no record, and
#       leaves a record whose transcript is gone untouched with a warning;
#   R7. that refresh touches ITS OWN slug's file and nothing else: the other two features'
#       copies of the same router's record are byte-identical afterwards. This is the
#       whole of the add/add defect — under one shared path those copies were one file;
#   R8. `load_records` collapses the copies: one record per `session_id`, the one with the
#       latest `captured_at` (a router only grows, so that copy names every feature),
#       and on an equal `captured_at` the copy naming more features;
#   R9. `--migrate` moves each legacy `<corpus>/routing/<id>.json` into the directory of
#       every slug its `features_started` names, deletes the legacy file, prints each
#       move, and is idempotent — a second run prints nothing and changes nothing. A
#       target already holding a record captured as late or later is skipped rather than
#       overwritten; a slug with no feature directory is skipped and said so (no feature
#       directory is ever created to hold a record); a legacy record no slug of which has
#       a directory is KEPT, since deleting it would destroy the only copy; and an absent
#       legacy directory is nothing to do.
#  R10. `slug_of_start_command` reads the slug off the START'S OWN LINE
#       (self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §2): `\`-newline
#       continuations joined first, then one line at a time. A start with no slug on its
#       line yields nothing rather than the next line's first word; a `\`-continued start
#       yields its slug; a value-taking flag before the slug (`--base x`, `--method
#       direct`) never becomes one.
#  R11. a pinned session is never also a router (self/features/shell-write-rewrite, part
#       2): a routing record whose `session_id` some manifest in the corpus pins in
#       `sessions` has no row in the Routing table and is not in its fraction, `--all`
#       names it in one line with the pinning feature, the feature's "routed by" line is
#       gone, and the record file, the feature totals and the unpinned routers are all
#       exactly as they were.
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

for f in pricing.py rates_history.json roots.py transcript.py capture_planning.py report.py routing.py; do
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
NOSLUG="s0000000-0000-0000-0000-000000000008"
GHOST="00000000-0000-0000-0000-00000000dead"
FEATURES="$AT/self/features"
# The record's name and where it lives, one per feature (design 2026-09-18 §1), and the
# legacy directory --migrate reads.
RECORD_NAME="routing.json"
LEGACY_DIR="$AT/self/routing"
record_of() { echo "$FEATURES/$1/$RECORD_NAME"; }
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
# A second router, for the report table: one start, one feature.
{
  bash_tool_line "$ROUTER2" "$AT" "main" "m-r2a" "$MODEL" "$T_ALPHA" \
    "./feature-start.sh --self solo" 500 1000
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
# On main in the primary, with a start that names NO slug and a second command under it.
# `\n` is a JSON escape here, so the command really is two lines. Under the multiline
# regex the word after the script was `ls`, which passes the slug pattern, so this session
# was a router that had started a feature called `ls` — and dropped out of the one listing
# that surfaces unclaimed cost (design 2026-09-18 §2).
bash_tool_line "$NOSLUG" "$AT" "main" "m-s1" "$MODEL" "$T_ALPHA" \
  './feature-start.sh --self\nls' 100 200 > "$PRIMARY_PROJ/$NOSLUG.jsonl"

routing() {
  ( HOME="$FAKE_HOME" python3 -B "$AT/analysis/routing.py" --self --primary "$AT" "$@" 2>&1 )
}
migrate() {
  ( HOME="$FAKE_HOME" python3 -B "$AT/analysis/routing.py" --self --migrate 2>&1 )
}
capture() {
  ( HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$@" 2>&1 )
}
report() {
  ( HOME="$FAKE_HOME" python3 "$AT/analysis/report.py" --self "$@" 2>&1 )
}
# records <python expr over `recs`> — routing.load_records over the sandbox corpus, the
# reader that collapses a router's copies. Called directly because what it decides
# (which copy of a record wins) is invisible from any renderer but by its absence.
records() {
  python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
import routing
recs = routing.load_records(sys.argv[2])
print(eval(sys.argv[3]))" "$AT/analysis" "$FEATURES" "$1" 2>&1
}
# slug_of <command> — routing.slug_of_start_command called directly. Which LINE a slug
# came from is invisible from any record but by its absence, so the function is asked.
slug_of() {
  python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
import routing
print(routing.slug_of_start_command(sys.argv[2]))" "$AT/analysis" "$1" 2>&1
}

echo "routing record"

# ── R1. the record is derived, not typed, and lives in its feature ─────────────
out="$(routing --session "$ROUTER" --slug gamma)"; rc=$?
REC="$(record_of gamma)"
check "R1a. routing.py exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R1b. the record is at self/features/<slug>/routing.json" '[[ -f "$REC" ]]'
check "R1b2. ... and nothing was written to the legacy self/routing/" '[[ ! -d "$LEGACY_DIR" ]]'
check "R1b3. ... and the path it printed is that file" 'grep -qx "$REC" <<<"$out"'
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
GREC="$(record_of delta)"
check "R3a. a session with no transcript still exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R3b. ... and writes a record naming the current slug" \
  '[[ -f "$GREC" && "$(pj "$GREC" "[f[\"slug\"] for f in d[\"features_started\"]]")" == "['"'"'delta'"'"']" ]]'
check "R3c. ... with null figures" \
  '[[ "$(pj "$GREC" "d[\"cost_usd\"] is None and d[\"started_at\"] is None and d[\"duration_s\"] is None")" == "True" ]]'
check "R3d. ... and one warning line naming the session" 'grep -qi "transcript" <<<"$out" && grep -q "$GHOST" <<<"$out"'
rm -rf "$FEATURES/delta"

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
check "R4i. a start with no slug on its own line starts no feature, so its session is still listed" \
  'grep -q "$NOSLUG" <<<"$unclaimed"'
listed="$(capture --list-sessions)"
check "R4h. a plain --list-sessions still shows the router" 'grep -q "$ROUTER" <<<"$listed"'

# ── R5. the report ────────────────────────────────────────────────────────────
# Four features, each a minimal manifest plus a frozen planning.json — enough for
# report.py to write a report.json the Routing table reads. The one router that started
# alpha, beta and gamma has a copy of its record in each of the three, which is the shape
# the table has to collapse.
write_feature() {                       # write_feature <slug> <total-usd>
  local slug="$1" total="$2" dir="$FEATURES/$1"
  mkdir -p "$dir"
  printf '# %s\n\nTest fixture only, for self/tests/routing-record.sh.\n\n```json\n{"slug": "%s", "method": "direct", "plans": [], "branches": ["%s"]}\n```\n' \
    "$slug" "$slug" "$slug" > "$dir/README.md"
  printf '{"cost_usd": {"total": %s, "total_is_partial": false}, "sessions": [], "subagents": [], "priced": []}\n' \
    "$total" > "$dir/planning.json"
}
write_feature alpha 3.0
write_feature beta 5.0
write_feature gamma 2.0
write_feature solo 1.0
write_feature unrouted 7.0
routing --session "$ROUTER" --slug alpha >/dev/null 2>&1
routing --session "$ROUTER" --slug beta >/dev/null 2>&1
routing --session "$ROUTER2" --slug solo >/dev/null 2>&1
for slug in alpha beta gamma solo unrouted; do report "$slug" >/dev/null 2>&1; done

all_out="$(report --all)"
routing_table="$(awk '/Routing overhead/{f=1} f' <<<"$all_out")"
check "R5a. the Routing table names both router sessions" \
  'grep -q "$ROUTER" <<<"$routing_table" && grep -q "$ROUTER2" <<<"$routing_table"'
check "R5b. ... with each started slug beside its frozen total" \
  'grep -E "$ROUTER.*alpha.*3\.00" <<<"$routing_table" >/dev/null && grep -E "$ROUTER.*beta.*5\.00" <<<"$routing_table" >/dev/null'
check "R5c. ... and routing spend as a fraction of feature spend" \
  'grep -qi "routing" <<<"$routing_table" && grep -q "%" <<<"$routing_table"'
check "R5d. an unrouted feature is not named in the Routing table" \
  '! grep -q "unrouted" <<<"$routing_table"'
check "R5d2. three copies of one router's record are ONE row (got $(grep -c "$ROUTER " <<<"$routing_table"))" \
  '[[ "$(grep -c "| $ROUTER |" <<<"$routing_table")" == "1" ]]'

alpha_out="$(report alpha)"
check "R5e. a routed feature's report names the router that started it" \
  'grep -q "routed by" <<<"$alpha_out" && grep -q "$ROUTER" <<<"$alpha_out"'
check "R5f. ... and the slugs it was started alongside" 'grep -q "beta" <<<"$alpha_out"'
unrouted_out="$(report unrouted)"
check "R5g. an unrouted feature's report says nothing about routing" \
  '! grep -q "routed by" <<<"$unrouted_out"'

# ── R6. --refresh-for: the capture's refresh of the router that started a slug ─
# feature-capture.sh rewrites its own feature's routing record from the transcript as it
# stands now (design 2026-09-16 §3.2 step 4). The router has grown since R1: a later start
# of `epsilon`. `gamma` was never in the transcript — it was the slug being started when
# R1 wrote the record — so a refresh that re-derived from the transcript alone would
# silently drop it; the prior record's entries are kept.
T_LATER="2026-09-10T12:00:00.000Z"
bash_tool_line "$ROUTER" "$AT" "main" "m-r4" "$MODEL" "$T_LATER" \
  "./feature-start.sh --self epsilon" 1000 2000 >> "$PRIMARY_PROJ/$ROUTER.jsonl"
cp "$(record_of alpha)" "$TMP/alpha.before"
cp "$(record_of beta)" "$TMP/beta.before"
refresh() { ( HOME="$FAKE_HOME" python3 -B "$AT/analysis/routing.py" --self --refresh-for "$@" 2>&1 ); }
out="$(refresh gamma)"; rc=$?
check "R6a. --refresh-for <slug> exits 0 (got $rc) and prints the record it rewrote" \
  '[[ $rc -eq 0 ]] && grep -qx "$REC" <<<"$out"'
check "R6b. ... re-deriving the grown router: epsilon is started, ended_at moved to the later call" \
  '[[ "$(pj "$REC" "[f[\"slug\"] for f in d[\"features_started\"]]")" == *epsilon* && "$(pj "$REC" "d[\"ended_at\"]")" == "2026-09-10T12:00:00Z" ]]'
check "R6c. ... keeping the prior record's slug the transcript never carried, at null" \
  '[[ "$(pj "$REC" "[f[\"at\"] for f in d[\"features_started\"] if f[\"slug\"] == \"gamma\"]")" == "[None]" ]]'
cp "$REC" "$TMP/record.refreshed"
refresh gamma >/dev/null 2>&1
check "R6e. a second refresh from the same transcript is byte-identical" 'cmp -s "$TMP/record.refreshed" "$REC"'
out="$(refresh nobody-started-this)"; rc=$?
check "R6f. a slug with no record exits 0 and prints nothing (got $rc)" '[[ $rc -eq 0 && -z "$out" ]]'
routing --session "$GHOST" --slug zeta >/dev/null 2>&1
ZREC="$(record_of zeta)"
cp "$ZREC" "$TMP/ghost.before"
out="$(refresh zeta)"; rc=$?
check "R6g. a record whose transcript is gone is left byte-identical, with a warning (got $rc)" \
  '[[ $rc -eq 0 ]] && cmp -s "$TMP/ghost.before" "$ZREC" && grep -q "$GHOST" <<<"$out" && ! grep -qx "$ZREC" <<<"$out"'
rm -rf "$FEATURES/zeta"

# ── R7. a refresh touches its own feature's file and no other ─────────────────
# The whole of the defect this location fixes: alpha and beta hold copies of the SAME
# router's record, and gamma's capture must not write either of them. Under the old
# shared path those three were one file, and two branches adding it were an add/add
# conflict a human resolved by hand.
check "R7a. another feature's copy of the same router's record is byte-identical" \
  'cmp -s "$TMP/alpha.before" "$(record_of alpha)"'
check "R7b. ... and so is the third" 'cmp -s "$TMP/beta.before" "$(record_of beta)"'
check "R7c. the refreshed copy really did change — the assertion above is not vacuous" \
  '! cmp -s "$TMP/alpha.before" "$REC"'

# ── R8. load_records keeps one copy per router: the latest captured_at ────────
check "R8a. one record per session id, not one per file" \
  '[[ "$(records "len(recs)")" == "$(records "len({r[\"session_id\"] for r in recs})")" ]]'
check "R8b. the router's copies collapse to the one refreshed latest" \
  '[[ "$(records "[r[\"captured_at\"] for r in recs if r[\"session_id\"] == \"$ROUTER\"]")" == "['"'"'2026-09-10T12:00:00Z'"'"']" ]]'
check "R8c. ... which is the copy naming every feature it started" \
  '[[ "$(records "[f[\"slug\"] for r in recs if r[\"session_id\"] == \"$ROUTER\" for f in r[\"features_started\"]]")" == *epsilon* ]]'
# The tie: two copies of one router captured at the same instant, one naming a feature
# and one naming none. A router only grows, so the fuller copy is the later read of that
# instant — and a tie broken the other way would drop a feature out of the Routing table
# for as long as that router never started another.
mkdir -p "$FEATURES/tiebreak"
printf '{\n  "captured_at": "2026-09-10T10:30:00Z",\n  "cost_usd": 1.0,\n  "duration_s": 60,\n  "ended_at": "2026-09-10T10:30:00Z",\n  "features_started": [],\n  "git_branch": "main",\n  "launched_in": "%s",\n  "model": "%s",\n  "session_id": "%s",\n  "started_at": "2026-09-10T10:00:00Z"\n}\n' \
  "$AT" "$MODEL" "$ROUTER2" > "$(record_of tiebreak)"
check "R8d. the second router still has exactly one record" \
  '[[ "$(records "len([r for r in recs if r[\"session_id\"] == \"$ROUTER2\"])")" == "1" ]]'
check "R8e. ... and on an equal captured_at it is the copy naming more features" \
  '[[ "$(records "[f[\"slug\"] for r in recs if r[\"session_id\"] == \"$ROUTER2\" for f in r[\"features_started\"]]")" == "['"'"'solo'"'"']" ]]'
rm -rf "$FEATURES/tiebreak"

# ── R9. --migrate: the legacy directory, emptied into the features it names ───
# `<corpus>/routing/<session-id>.json` is where every record written before design
# 2026-09-18 §1 lives. The migration copies each into the directory of every slug it
# names, deletes it, and says what it did; `sync-plans.sh` runs it after a pull.
MIG_ONE="m1111111-0000-0000-0000-000000000011"
MIG_ORPHAN="m2222222-0000-0000-0000-000000000012"
MIG_NEWER="m3333333-0000-0000-0000-000000000013"
write_feature mig-one 1.5
write_feature mig-two 2.5
write_feature mig-three 3.5
legacy_record() {                       # legacy_record <session-id> <captured_at> <slug>...
  local id="$1" captured="$2"; shift 2
  local entries="" slug
  for slug in "$@"; do
    entries="${entries:+$entries, }{\"slug\": \"$slug\", \"at\": null}"
  done
  mkdir -p "$LEGACY_DIR"
  printf '{\n  "captured_at": "%s",\n  "cost_usd": 1.0,\n  "duration_s": 60,\n  "ended_at": "%s",\n  "features_started": [%s],\n  "git_branch": "main",\n  "launched_in": "%s",\n  "model": "%s",\n  "session_id": "%s",\n  "started_at": "%s"\n}\n' \
    "$captured" "$captured" "$entries" "$AT" "$MODEL" "$id" "$captured" \
    > "$LEGACY_DIR/$id.json"
}
legacy_record "$MIG_ONE" "2026-09-11T09:00:00Z" mig-one mig-two
legacy_record "$MIG_ORPHAN" "2026-09-11T09:30:00Z" never-merged
legacy_record "$MIG_NEWER" "2026-09-11T08:00:00Z" mig-three
# mig-three already holds a copy captured LATER — the case where the feature's own capture
# has already refreshed it and the legacy file is the stale side.
printf '{\n  "captured_at": "2026-09-12T10:00:00Z",\n  "cost_usd": 2.0,\n  "duration_s": 60,\n  "ended_at": "2026-09-12T10:00:00Z",\n  "features_started": [{"slug": "mig-three", "at": null}],\n  "git_branch": "main",\n  "launched_in": "%s",\n  "model": "%s",\n  "session_id": "%s",\n  "started_at": "2026-09-12T09:00:00Z"\n}\n' \
  "$AT" "$MODEL" "$MIG_NEWER" > "$(record_of mig-three)"
cp "$(record_of mig-three)" "$TMP/mig-three.before"

out="$(migrate)"; rc=$?
check "R9a. --migrate exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "R9b. a legacy record naming two slugs lands in both feature directories" \
  '[[ -f "$(record_of mig-one)" && -f "$(record_of mig-two)" ]]'
check "R9c. ... as the record it was, session id and all" \
  '[[ "$(pj "$(record_of mig-one)" "d[\"session_id\"]")" == "$MIG_ONE" && "$(pj "$(record_of mig-two)" "d[\"session_id\"]")" == "$MIG_ONE" ]]'
check "R9d. ... with one printed line per move, naming source and target" \
  '[[ "$(grep -c "$LEGACY_DIR/$MIG_ONE.json" <<<"$out")" -ge 2 ]] && grep -q "$(record_of mig-two)" <<<"$out"'
check "R9e. ... and the legacy file is deleted" '[[ ! -e "$LEGACY_DIR/$MIG_ONE.json" ]]'
check "R9f. a target already holding a record captured later is not overwritten" \
  'cmp -s "$TMP/mig-three.before" "$(record_of mig-three)"'
check "R9g. ... and is said to have been skipped" 'grep -qi "skipped" <<<"$out" && grep -q "$MIG_NEWER" <<<"$out"'
check "R9h. ... while its legacy file still goes, nothing having been lost" \
  '[[ ! -e "$LEGACY_DIR/$MIG_NEWER.json" ]]'
check "R9i. a slug with no feature directory is skipped, and no directory is created for it" \
  'grep -q "never-merged" <<<"$out" && [[ ! -e "$FEATURES/never-merged" ]]'
check "R9j. ... and that record is KEPT — deleting it would destroy its only copy" \
  '[[ -f "$LEGACY_DIR/$MIG_ORPHAN.json" ]]'
rm -f "$LEGACY_DIR/$MIG_ORPHAN.json"
out="$(migrate)"; rc=$?
check "R9k. a second run over an emptied legacy directory removes it and says so (got $rc)" \
  '[[ $rc -eq 0 && ! -d "$LEGACY_DIR" ]] && grep -q "$LEGACY_DIR" <<<"$out"'
cp -R "$FEATURES" "$TMP/features.before"
out="$(migrate)"; rc=$?
check "R9l. with no legacy directory at all there is nothing to do: exit 0, no output" \
  '[[ $rc -eq 0 && -z "$out" ]]'
check "R9m. ... and nothing under the features root changed" \
  'diff -r "$TMP/features.before" "$FEATURES" >/dev/null'

# ── R10. the slug is on the start's own line ──────────────────────────────────
# A Bash tool call is often several commands, one per line, and `re.MULTILINE` let the
# match land on one line while the argument scan ran on from wherever the match ended.
# The two halves of that: a start with no slug swallowed the next line's first word, and
# a start continued with a trailing `\` found its slug on a line the regex never reached.
# Continuations are joined first, then each line is matched on its own.
check "R10a. the slug is the token after the script on the script's own line" \
  '[[ "$(slug_of "./feature-start.sh --self alpha")" == "alpha" ]]'
check "R10b. a start with no slug on its line yields nothing, not the next line's first word" \
  '[[ "$(slug_of "$(printf "./feature-start.sh --self\\nls")")" == "None" ]]'
check "R10c. ... nor a slug-shaped word from a later command" \
  '[[ "$(slug_of "$(printf "./feature-start.sh --self\\n./run-batch.sh --self beta")")" == "None" ]]'
check "R10d. a start continued with a trailing backslash yields its slug" \
  '[[ "$(slug_of "$(printf "./feature-start.sh --self \\\\\\n  gamma")")" == "gamma" ]]'
check "R10e. --base and its value before the slug do not become the slug" \
  '[[ "$(slug_of "./feature-start.sh --self --base other delta")" == "delta" ]]'
check "R10f. --method and its value after the slug leave the slug alone" \
  '[[ "$(slug_of "./feature-start.sh --self epsilon --method direct")" == "epsilon" ]]'
check "R10g. a start that is the last thing on its line and on the transcript yields nothing" \
  '[[ "$(slug_of "./feature-start.sh --self")" == "None" ]]'
check "R10h. a start on the SECOND line still reads that line's slug" \
  '[[ "$(slug_of "$(printf "git fetch origin\\n./feature-start.sh --self zeta")")" == "zeta" ]]'
check "R10i. a command that only names the script is still not a start" \
  '[[ "$(slug_of "grep -n x feature-start.sh hooks")" == "None" ]]'

# ── R11. a pinned session is never also a router ──────────────────────────────
# One owner per session (self/features/shell-write-rewrite, part 2): a session some
# manifest in the corpus pins in `sessions` is that feature's, so its routing record —
# one written before `feature-start.sh --pin` stopped writing them — must not ALSO be
# counted as routing overhead, or the `--all` fraction counts it on both sides. The
# predicate is routing.py's; the table, its fraction and the "routed by" line all call it.
# The record file itself is left alone. ROUTER3 is the pinned one; the two routers above
# are pinned by nobody and must be exactly where they were.
ROUTER3="r0000000-0000-0000-0000-000000000009"
ROUTER3_COST="9.0"
overhead_of() { grep -oE 'routing overhead \$[0-9.]+' <<<"$1"; }
before_overhead="$(overhead_of "$(report --all)")"
mkdir -p "$FEATURES/pinned-feat" "$FEATURES/pinner"
printf '{\n  "captured_at": "2026-09-10T10:30:00Z",\n  "cost_usd": %s,\n  "duration_s": 60,\n  "ended_at": "2026-09-10T10:30:00Z",\n  "features_started": [{"slug": "pinned-feat", "at": null}],\n  "git_branch": "main",\n  "launched_in": "%s",\n  "model": "%s",\n  "session_id": "%s",\n  "started_at": "2026-09-10T10:00:00Z"\n}\n' \
  "$ROUTER3_COST" "$AT" "$MODEL" "$ROUTER3" > "$(record_of pinned-feat)"
write_feature pinned-feat 4.0
# The pin sits in ANOTHER feature's manifest: "some manifest in the corpus", not only the
# record's own feature.
printf '# pinner\n\nTest fixture only.\n\n```json\n{"slug": "pinner", "method": "direct", "plans": [], "branches": ["pinner"], "sessions": ["%s"]}\n```\n' \
  "$ROUTER3" > "$FEATURES/pinner/README.md"
printf '{"cost_usd": {"total": 6.0, "total_is_partial": false}, "sessions": [], "subagents": [], "priced": []}\n' \
  > "$FEATURES/pinner/planning.json"
cp "$(record_of pinned-feat)" "$TMP/pinned.before"
report pinned-feat >/dev/null 2>&1
report pinner >/dev/null 2>&1
all_out="$(report --all)"
routing_table="$(awk '/Routing overhead/{f=1} f' <<<"$all_out")"
check "R11a. the pinned router has no row in the Routing table" \
  '! grep -q "| $ROUTER3 |" <<<"$routing_table"'
check "R11b. ... while both unpinned routers keep theirs" \
  'grep -q "| $ROUTER |" <<<"$routing_table" && grep -q "| $ROUTER2 |" <<<"$routing_table"'
check "R11c. the routing overhead counts only the unpinned routers ($before_overhead before)" \
  '[[ -n "$before_overhead" && "$(overhead_of "$all_out")" == "$before_overhead" ]]'
check "R11d. --all names the skipped record in one line, with the feature that pins it" \
  '[[ "$(grep -c "$ROUTER3" <<<"$all_out")" == "1" ]] && grep "$ROUTER3" <<<"$all_out" | grep -q "pinner"'
check "R11e. the pinned-out feature's report prints no routed-by line" \
  '! grep -q "routed by" <<<"$(report pinned-feat)"'
check "R11f. an unpinned router's routed-by line is untouched" \
  'grep -q "routed by $ROUTER" <<<"$(report alpha)"'
check "R11g. the record file is not modified by any reader" \
  'cmp -s "$TMP/pinned.before" "$(record_of pinned-feat)"'
check "R11h. the feature totals are unchanged — pinned-feat and pinner report their own" \
  '[[ "$(pj "$FEATURES/pinned-feat/report.json" "d[\"cost\"][\"total\"]")" == "4.0" && "$(pj "$FEATURES/pinner/report.json" "d[\"cost\"][\"total\"]")" == "6.0" ]]'
check "R11i. load_records itself still returns the pinned record — the skip is the readers'" \
  '[[ "$(records "len([r for r in recs if r[\"session_id\"] == \"$ROUTER3\"])")" == "1" ]]'

# ── R12. a router that built its feature, unpinned ────────────────────────────
# `routing.py --unpinned-builder <slug>` is what feature-close.sh refuses on
# (self/features/router-built-pin): it prints the router's session id when the feature's
# own routing record names a session no manifest pins in `sessions` AND that session's
# transcript shows it at work in `<launched_in>/.worktrees/<slug>` — a line whose `cwd`
# is at or under it, or an Edit/Write/NotebookEdit aimed under it. Otherwise it prints
# nothing and exits 0, which is every case the intended flow produces.
T_RB="2026-09-11T09:00:00.000Z"
# tool_line <session> <cwd> <msg-id> <tool> <input-key> <input-path> — one assistant line
# carrying one tool_use block, the shape a real Edit/Write/Read call is written as.
tool_line() {
  printf '{"type":"assistant","sessionId":"%s","cwd":"%s","gitBranch":"main","timestamp":"%s","isSidechain":false,"message":{"id":"%s","model":"%s","content":[{"type":"tool_use","name":"%s","input":{"%s":"%s"}}],"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}\n' \
    "$1" "$2" "$T_RB" "$3" "$MODEL" "$4" "$5" "$6"
}
# rb_feature <slug> <router-session> — a feature whose routing record names that router,
# launched in the primary, which is where every real router record says it was launched.
rb_feature() {
  write_feature "$1" 1.0
  printf '{\n  "captured_at": "2026-09-11T09:00:00Z",\n  "cost_usd": 1.0,\n  "duration_s": 60,\n  "ended_at": "2026-09-11T09:00:00Z",\n  "features_started": [{"slug": "%s", "at": null}],\n  "git_branch": "main",\n  "launched_in": "%s",\n  "model": "%s",\n  "session_id": "%s",\n  "started_at": "2026-09-11T09:00:00Z"\n}\n' \
    "$1" "$AT" "$MODEL" "$2" > "$(record_of "$1")"
}
# rb_start <session> <slug> — the router's own start, from the primary, on main.
rb_start() { bash_tool_line "$1" "$AT" "main" "m-$1-start" "$MODEL" "$T_RB" "./feature-start.sh --self $2" 10 20; }
builder_of() { HOME="$FAKE_HOME" python3 -B "$AT/analysis/routing.py" --self --unpinned-builder "$1" 2>&1; }

RB_CWD="rb000000-0000-0000-0000-000000000001"
RB_EDIT="rb000000-0000-0000-0000-000000000002"
RB_NOTEBOOK="rb000000-0000-0000-0000-000000000003"
RB_READER="rb000000-0000-0000-0000-000000000004"
RB_SIBLING="rb000000-0000-0000-0000-000000000005"
RB_PINNED="rb000000-0000-0000-0000-000000000006"

# Built from inside the worktree: its cwd moved there after the start.
rb_feature rb-cwd "$RB_CWD"
{ rb_start "$RB_CWD" rb-cwd
  bash_tool_line "$RB_CWD" "$AT/.worktrees/rb-cwd" "main" "m-rbc2" "$MODEL" "$T_RB" "ls" 10 20
} > "$PRIMARY_PROJ/$RB_CWD.jsonl"
# Built from the primary: every cwd is the primary, but an Edit landed in the worktree.
rb_feature rb-edit "$RB_EDIT"
{ rb_start "$RB_EDIT" rb-edit
  tool_line "$RB_EDIT" "$AT" "m-rbe2" "Edit" "file_path" "$AT/.worktrees/rb-edit/analysis/x.py"
} > "$PRIMARY_PROJ/$RB_EDIT.jsonl"
rb_feature rb-notebook "$RB_NOTEBOOK"
{ rb_start "$RB_NOTEBOOK" rb-notebook
  tool_line "$RB_NOTEBOOK" "$AT" "m-rbn2" "NotebookEdit" "notebook_path" "$AT/.worktrees/rb-notebook/n.ipynb"
} > "$PRIMARY_PROJ/$RB_NOTEBOOK.jsonl"
# The intended flow: the router starts the feature and only looks — a Read of a worktree
# file and a Write in the PRIMARY. It built nothing.
rb_feature rb-reader "$RB_READER"
{ rb_start "$RB_READER" rb-reader
  tool_line "$RB_READER" "$AT" "m-rbr2" "Read" "file_path" "$AT/.worktrees/rb-reader/README.md"
  tool_line "$RB_READER" "$AT" "m-rbr3" "Write" "file_path" "$AT/notes.md"
} > "$PRIMARY_PROJ/$RB_READER.jsonl"
# A sibling whose name only STARTS with this slug: `.worktrees/rb-sib-two` is not under
# `.worktrees/rb-sib`.
rb_feature rb-sib "$RB_SIBLING"
{ rb_start "$RB_SIBLING" rb-sib
  bash_tool_line "$RB_SIBLING" "$AT/.worktrees/rb-sib-two" "main" "m-rbs2" "$MODEL" "$T_RB" "ls" 10 20
  tool_line "$RB_SIBLING" "$AT" "m-rbs3" "Edit" "file_path" "$AT/.worktrees/rb-sib-two/x.py"
} > "$PRIMARY_PROJ/$RB_SIBLING.jsonl"
# Built from inside the worktree, and pinned — in ANOTHER feature's manifest, as R11 pins.
rb_feature rb-pinned "$RB_PINNED"
{ rb_start "$RB_PINNED" rb-pinned
  bash_tool_line "$RB_PINNED" "$AT/.worktrees/rb-pinned" "main" "m-rbp2" "$MODEL" "$T_RB" "ls" 10 20
} > "$PRIMARY_PROJ/$RB_PINNED.jsonl"
mkdir -p "$FEATURES/rb-pinner"
printf '# rb-pinner\n\nTest fixture only.\n\n```json\n{"slug": "rb-pinner", "method": "hand", "plans": [], "branches": ["rb-pinner"], "sessions": ["%s"]}\n```\n' \
  "$RB_PINNED" > "$FEATURES/rb-pinner/README.md"
# A record whose router's transcript is gone: nothing can be judged, so nothing is refused.
rb_feature rb-ghost "$GHOST"

out12="$(builder_of rb-cwd)"; rc12=$?
check "R12a. a router whose cwd moved into the worktree is named (got '$out12', exit $rc12)" \
  '[[ "$out12" == "$RB_CWD" && $rc12 -eq 0 ]]'
check "R12b. ... and so is one that stayed in the primary but Edited a file in the worktree" \
  '[[ "$(builder_of rb-edit)" == "$RB_EDIT" ]]'
check "R12c. ... and one whose NotebookEdit landed there" \
  '[[ "$(builder_of rb-notebook)" == "$RB_NOTEBOOK" ]]'
check "R12d. a router that only started the feature, read into the worktree and wrote in the primary is not" \
  '[[ -z "$(builder_of rb-reader)" ]]'
check "R12e. a worktree whose name only starts with the slug is not this feature's" \
  '[[ -z "$(builder_of rb-sib)" ]]'
check "R12f. a router some manifest pins in sessions is never named — it is that feature's already" \
  '[[ -z "$(builder_of rb-pinned)" ]]'
out12g="$(builder_of rb-ghost)"; rc12g=$?
check "R12g. a router whose transcript is gone is not named, and the check still exits 0 (exit $rc12g)" \
  '[[ -z "$out12g" && $rc12g -eq 0 ]]'
out12h="$(builder_of unrouted)"; rc12h=$?
check "R12h. a feature with no routing record is not a question (exit $rc12h)" \
  '[[ -z "$out12h" && $rc12h -eq 0 ]]'

echo
if (( fails > 0 )); then echo "routing record: $fails assertion(s) FAILED"; exit 1; fi
echo "routing record: all assertions passed"
