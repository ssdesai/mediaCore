#!/usr/bin/env bash
set -uo pipefail

# Self-test for the stale failed/ sidecar contract
# (self/features/stale-failed-sidecars/README.md). Run by self/gate.sh, or by hand:
# bash self/tests/stale-failed-sidecars.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — copies of
# `analysis/pricing.py`, `analysis/roots.py`, `analysis/transcript.py` and
# `analysis/report.py` — plus a synthesized `self/features/` corpus of feature
# directories, each a manifest README with a fenced JSON `plans` array, a
# `planning.json`, and hand-written plan files and `usage.json` sidecars. No model, no
# network, no transcripts: every dollar figure here is a literal in a sidecar, which is
# exactly what report.py's no-recompute contract says it reads.
#
# The layout under test is what a usage-limit kill plus a manual retry leaves behind
# (RUNNER.md -> the `failed/` paragraph). The runner files a plan's four sidecars as a
# set, so a killed first run puts `<stem>.progress.md` and `<stem>.usage.json` into
# `<queue>/failed/`; the retry moves only the `.md` back to `incomplete/` and from there
# to `complete/`, where a fresh progress log and a fresh sidecar are written beside it.
# The result is two `usage.json` files claiming one plan stem, and a `failed/` pair with
# no `.md` beside it. Ruling 1 of the manifest is that the pair STAYS there — it is the
# record of the killed attempt and the only surviving copy of its session id, which is
# what analysis/recover_attempts.py needs — so every fix here is in the analysis.
#
# Every fixture creates `failed/` (or `inprogress/`) BEFORE `complete/`, so a
# filesystem-ordered walk offers the wrong file first. That ordering is the point: the
# defect was `build_usage_index` keeping whichever file `rglob` reached last.
#
# Asserts, in order:
#   1. the stale pair does not crash the report: report.py exits 0 over a feature whose
#      plan has a priced sidecar in complete/ and a null-cost twin in failed/ with no
#      .md beside it (this is the vinylCatalogue group-commit-all-adjudication crash);
#   2. ...the reported cost is the complete/ sidecar's figure, and — since the twin
#      carries neither a cost nor a recovered figure — the total is marked a lower bound
#      with that attempt's session id named under cost.unrecoverable_attempts[];
#   3. ...the live sidecar really is complete/'s, read off the plan-length table, which
#      can only have found the .md that exists there — and no warning names a failed/
#      plan file;
#   4. ...and the stem is neither missing usage nor an orphan;
#   5. a recovered_cost_usd planted in the failed/ sidecar's attempts[] is added to the
#      live figure rather than dropped with the file that lost the index, shows up as
#      recovered dollars, and — being recovered rather than absent — leaves the total
#      whole, which is the contrast that keeps assertion 2 precise;
#   6. directory rank breaks a tie when BOTH candidates have a sibling .md and the
#      sibling rule therefore cannot decide: complete/ outranks inprogress/, whichever
#      the filesystem offers first — read off the plan-length table, since the two plan
#      files are deliberately different lengths — while the outranked sidecar's own
#      measured dollars are still rolled in, and the roll-in is announced;
#   7. a missing sibling .md is a warning naming the path, never a crash: report.py
#      still exits 0, still prices the plan, and drops it from the plan-length table;
#   8. an attempt reachable through BOTH sidecars is counted once: two same-stem files
#      whose attempts[] share a session_id contribute that attempt's dollars once;
#   9. ...and name it once under cost.unrecoverable_attempts[] when it carries no
#      figure at all, rather than twice;
#  10. a stem with more than one sidecar is reported as such —
#      cost.multi_sidecar_stems[] and one line under the Cost table — while a stem with
#      exactly one is not;
#  11. a deduplicated attempt takes whichever copy carries a figure: where the live copy
#      is null on both figures and the prior carries a recovered one, that figure is
#      counted once, the total stays whole, and the session is named in neither
#      cost.unrecoverable_attempts[] nor cost.unpriced_plans[] — both where that is the
#      plan's only attempt and where the live sidecar prices one of its own;
#  12. ...while a session null in EVERY copy is still unpriced, exactly as before — the
#      contrast that keeps 11 precise;
#  13. ...and where both copies carry a figure and disagree, the LIVE one wins, once.
#
# RED before the fix. Against main's analysis/report.py, phase 1 dies inside
# compute_plan_length_vs_loc with a FileNotFoundError for the failed/ .md that the
# retry moved away, so every assertion below it reads a report.json that was never
# written. Phases 2c-2e, 8, 9 and 10 are the 2026-09-06 backlog items (2, 3 and 4):
# 2c REVERSES what this file asserted before them — ruling 4 of stale-failed-sidecars
# deliberately let a priorless prior read as free, and widening it changes what
# total_is_partial means for every feature in both corpora, which is the point.
# Phase 11 is the precedence gap that batch's review escalated: before the rework the
# dedupe kept the live copy unconditionally, so 11b-11e, 11g and 11i-11k fail there. Phases 12 and 13
# are green before the rework as well as after — they are the two contrasts that keep 11
# from being satisfiable by a rule that just prefers the prior. A
# missing analysis script is tolerated rather than fatal (the cost-recovery.sh
# convention), so the phases fail loudly instead of the run aborting.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py report.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# The two figures every phase is built from. Distinct, and distinct from each other's
# sums, so no assertion below can pass by coincidence.
LIVE_COST="2.5"          # the successful retry, in complete/
STALE_RECOVERED="1.25"   # what the sweep recovers into the failed/ sidecar
DECOY_COST="9.75"        # a rank fixture's losing candidate, and the prior copy's
                         # disagreeing figure in phase 13
NO_COST="0.0"            # what a bucket holds when no copy of its attempt was priced

# ── Fixture helpers ───────────────────────────────────────────────────────────

# feature_dir <slug> — the throwaway feature's directory, created with the manifest and
# planning.json report.py needs before it will read anything else. planning.json's total
# is 0.0 throughout: every dollar in these assertions must come from a usage.json, so a
# planning figure would only make a wrong total harder to read.
feature_dir() {
  local slug="$1" dir="$AT/self/features/$1"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MDEOF
# $slug

Test fixture only, for self/tests/stale-failed-sidecars.sh.

\`\`\`json
{"plans": ["01-review-opus"]}
\`\`\`
MDEOF
  cat > "$dir/planning.json" <<'JSONEOF'
{"cost_usd": {"total": 0.0, "total_is_partial": false}}
JSONEOF
  echo "$dir"
}

# plan_md <path> — a plan file with a body long enough that its line count is a
# distinguishable number (assertion 3 reads it back).
plan_md() {
  cat > "$1" <<'MDEOF'
# 01-review-opus

Test fixture plan for stale-failed-sidecars.sh. Not a real plan.

## Files

- `analysis/report.py`
MDEOF
}
PLAN_MD_LINES=7

# plan_md_decoy <path> — the same plan, a different length. Assertion 6 needs the two
# candidates' plan files to be distinguishable: the plan-length row is read off the
# sibling of whichever sidecar the index called live, so a differing line count is how
# the test says which directory won without the report printing a path.
plan_md_decoy() {
  cat > "$1" <<'MDEOF'
# 01-review-opus

Test fixture plan for stale-failed-sidecars.sh. Not a real plan. This copy is the
one under inprogress/, deliberately a different length from the copy under
complete/ so the plan-length table names which of the two the index chose.

## Files

- `analysis/report.py`
MDEOF
}
PLAN_MD_DECOY_LINES=10

# usage_json_attempts <path> <total_cost_usd|null> <session_id> <attempts json array> —
# a sidecar in the shape write_usage_sidecar writes (plan-runner-lib.sh), with attempts[]
# given verbatim. The one helper both forms below are built from, so a phase that needs
# two attempts in one file — or one attempt shared with a twin — differs from the
# ordinary fixture in exactly that array and nothing else.
usage_json_attempts() {
  local path="$1" cost="$2" session_id="$3" attempts="$4"
  cat > "$path" <<JSONEOF
{
  "plan": "01-review-opus",
  "model": "opus",
  "outcome": "complete",
  "session_id": "$session_id",
  "subtype": null,
  "is_error": null,
  "num_turns": null,
  "duration_ms": null,
  "total_cost_usd": $cost,
  "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0},
  "model_usage": {},
  "permission_denials": 0,
  "tool_counts": {},
  "files_edited": [],
  "edit_count": 0,
  "attempts": $attempts
}
JSONEOF
}

# usage_json <path> <total_cost_usd|null> [recovered_cost_usd|null] [session_id] — one
# attempt, its session id defaulting to the state directory the file sits in so the two
# twins in a phase are distinguishable without the caller saying so. The null-cost form
# is verbatim what the killed run left in vinylCatalogue's review/failed/ (commit
# 48e0f12), session id aside. Pass the fourth argument to make two twins claim the SAME
# attempt, which is what phases 8 and 9 are about.
usage_json() {
  local path="$1" cost="$2" recovered="${3:-null}"
  local session_id="${4:-sess-$(basename "$(dirname "$path")")}"
  local attempt_recovered=""
  if [[ "$recovered" != "null" ]]; then
    attempt_recovered=", \"recovered_cost_usd\": $recovered, \"recovered_from\": \"transcript\""
  fi
  usage_json_attempts "$path" "$cost" "$session_id" \
    "[{\"session_id\": \"$session_id\", \"outcome\": \"complete\", \"total_cost_usd\": $cost, \"num_turns\": null, \"duration_ms\": null$attempt_recovered}]"
}

# ── Python verification helper ────────────────────────────────────────────────
# JSON parsing and float comparison belong in Python, not bash.
cat > "$TMP/verify.py" <<'PYEOF'
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def get_path(data, dotted):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def cmd_field_equals(args):
    report_path, dotted, expected_json = args
    print(get_path(load(report_path), dotted) == json.loads(expected_json))


def cmd_field_close(args):
    report_path, dotted, expected, tol = args
    actual = get_path(load(report_path), dotted)
    print(actual is not None and abs(float(actual) - float(expected)) <= float(tol))


def cmd_warning_contains(args):
    report_path = args[0]
    substrings = args[1:]
    warnings = load(report_path).get("warnings") or []
    print(any(all(s in w for s in substrings) for w in warnings))


def cmd_no_warning_contains(args):
    report_path = args[0]
    substrings = args[1:]
    warnings = load(report_path).get("warnings") or []
    print(not any(all(s in w for s in substrings) for w in warnings))


def cmd_plan_md_lines(args):
    """The plan-length row for a stem, or NONE when the plan was dropped from the
    table. It is read off the sibling <stem>.md of whichever usage.json the index
    called live, so it names the directory that won without the report having to
    print a path."""
    report_path, stem = args
    for row in load(report_path).get("plan_length_vs_loc") or []:
        if row.get("plan") == stem:
            print(row.get("plan_md_lines"))
            return
    print("NONE")


def cmd_list_names_plan(args):
    """True when any entry of the list at <dotted> names <plan> — the dict entries of
    cost.unpriced_plans[] and cost.unrecoverable_attempts[] as well as a bare stem
    list. Lets a phase pin membership without spelling out the reason and recovery
    text that sits beside the name."""
    report_path, dotted, plan = args
    entries = get_path(load(report_path), dotted) or []
    print(any((e.get("plan") if isinstance(e, dict) else e) == plan for e in entries))


COMMANDS = {
    "field_equals": cmd_field_equals,
    "field_close": cmd_field_close,
    "warning_contains": cmd_warning_contains,
    "no_warning_contains": cmd_no_warning_contains,
    "plan_md_lines": cmd_plan_md_lines,
    "list_names_plan": cmd_list_names_plan,
}

if __name__ == "__main__":
    COMMANDS[sys.argv[1]](sys.argv[2:])
PYEOF

V() { python3 "$TMP/verify.py" "$@" 2>/dev/null; }
report_for() { python3 "$AT/analysis/report.py" "$1" --self >/dev/null 2>&1; }

# ── 1-4: the stale pair, exactly as the retry left it ─────────────────────────
# review/failed/ holds the killed run's progress log and null-cost sidecar and NO .md;
# review/complete/ holds the successful retry's four files. failed/ is created first so
# a filesystem-ordered walk reaches it first.
D1="$(feature_dir sfs-stale)"
mkdir -p "$D1/review/failed"
echo "failed (exit 1): " > "$D1/review/failed/01-review-opus.progress.md"
usage_json "$D1/review/failed/01-review-opus.usage.json" null
mkdir -p "$D1/review/complete"
plan_md "$D1/review/complete/01-review-opus.md"
echo "review pass complete" > "$D1/review/complete/01-review-opus.progress.md"
usage_json "$D1/review/complete/01-review-opus.usage.json" "$LIVE_COST"

report_for sfs-stale
rc1=$?
check "1. a stale failed/ pair does not crash the report (report.py exit $rc1)" '(( rc1 == 0 ))'

R1="$D1/report.json"
r2a="$(V field_close "$R1" cost.review "$LIVE_COST" 1e-9)"
check "2a. the plan is priced at the complete/ sidecar's figure (got $r2a)" '[[ "$r2a" == "True" ]]'
r2b="$(V field_close "$R1" cost.total "$LIVE_COST" 1e-9)"
check "2b. ...and the twin adds no dollars of its own to the total (got $r2b)" '[[ "$r2b" == "True" ]]'
# The reversal of the original ruling 4. A prior attempt with neither a cost nor a
# recovered figure really did run: reading it as free is the silent zero this whole
# family of items exists to stop, so it marks the total a lower bound exactly as the
# same shape on the LIVE sidecar already did.
r2c="$(V field_equals "$R1" cost.total_is_partial true)"
check "2c. ...while the priorless twin DOES make the total a lower bound (got $r2c)" '[[ "$r2c" == "True" ]]'
r2d="$(V field_equals "$R1" cost.unrecoverable_attempts '[{"plan": "01-review-opus", "session_id": "sess-failed"}]')"
check "2d. ...naming the prior attempt's session id, once (got $r2d)" '[[ "$r2d" == "True" ]]'
r2e="$(V warning_contains "$R1" "01-review-opus" "sess-failed" "lower bound")"
check "2e. ...and saying so in a warning (got $r2e)" '[[ "$r2e" == "True" ]]'

# The plan-length row can only exist if the index resolved to complete/: that is the
# only directory holding a 01-review-opus.md at all.
r3a="$(V plan_md_lines "$R1" 01-review-opus)"
check "3a. the live sidecar is complete/'s — its sibling .md was found (got $r3a lines, want $PLAN_MD_LINES)" '[[ "$r3a" == "'"$PLAN_MD_LINES"'" ]]'
r3b="$(V no_warning_contains "$R1" "failed/01-review-opus.md")"
check "3b. ...and nothing warns about a plan file under failed/ (got $r3b)" '[[ "$r3b" == "True" ]]'

r4a="$(V field_equals "$R1" cost.missing_usage_plans '[]')"
check "4a. the stem is not reported as missing usage (got $r4a)" '[[ "$r4a" == "True" ]]'
r4b="$(V field_equals "$R1" cost.orphan_usage_plans '[]')"
check "4b. ...and its twin is not an orphan (got $r4b)" '[[ "$r4b" == "True" ]]'

# ── 5: a prior attempt's recovered money counts, once ─────────────────────────
# recover_attempts.py walks the tree itself, so it reaches and fills the failed/
# sidecar whatever the index thinks. The money is real; dropping the file from the index
# must not drop the dollars with it.
D5="$(feature_dir sfs-recovered)"
mkdir -p "$D5/review/failed"
echo "failed (exit 1): " > "$D5/review/failed/01-review-opus.progress.md"
usage_json "$D5/review/failed/01-review-opus.usage.json" null "$STALE_RECOVERED"
mkdir -p "$D5/review/complete"
plan_md "$D5/review/complete/01-review-opus.md"
echo "review pass complete" > "$D5/review/complete/01-review-opus.progress.md"
usage_json "$D5/review/complete/01-review-opus.usage.json" "$LIVE_COST"

report_for sfs-recovered
rc5=$?
check "5a. the recovered-twin layout reports cleanly (report.py exit $rc5)" '(( rc5 == 0 ))'
R5="$D5/report.json"
EXPECTED5="$(python3 -c "print($LIVE_COST + $STALE_RECOVERED)")"
r5b="$(V field_close "$R5" cost.review "$EXPECTED5" 1e-9)"
check "5b. a prior attempt's recovered_cost_usd is added to the live figure (want $EXPECTED5, got $r5b)" '[[ "$r5b" == "True" ]]'
r5c="$(V field_close "$R5" cost.total "$EXPECTED5" 1e-9)"
check "5c. ...and counted exactly once in the total (got $r5c)" '[[ "$r5c" == "True" ]]'
r5d="$(V field_close "$R5" cost.recovered "$STALE_RECOVERED" 1e-9)"
check "5d. ...and reported as recovered dollars (got $r5d)" '[[ "$r5d" == "True" ]]'
# The contrast that keeps 2c honest: a prior attempt IS priced once recovery has run, so
# the widened rule must not mark every feature with a stale twin a lower bound.
r5e="$(V field_equals "$R5" cost.total_is_partial false)"
check "5e. ...leaving the total whole, unlike the priorless twin in 2c (got $r5e)" '[[ "$r5e" == "True" ]]'

# ── 6: directory rank breaks a tie both candidates could win ──────────────────
# Both sidecars have a sibling .md here, so the sibling rule cannot decide and the rank
# complete > inprogress > incomplete > failed must. inprogress/ is created first, and
# its plan file is a different length from complete/'s so the plan-length table says
# which of the two the index called live. This is the only phase that pins the rank:
# everywhere else the sibling rule settles it first.
D6="$(feature_dir sfs-rank)"
mkdir -p "$D6/review/inprogress"
plan_md_decoy "$D6/review/inprogress/01-review-opus.md"
echo "resuming" > "$D6/review/inprogress/01-review-opus.progress.md"
usage_json "$D6/review/inprogress/01-review-opus.usage.json" "$DECOY_COST"
mkdir -p "$D6/review/complete"
plan_md "$D6/review/complete/01-review-opus.md"
echo "review pass complete" > "$D6/review/complete/01-review-opus.progress.md"
usage_json "$D6/review/complete/01-review-opus.usage.json" "$LIVE_COST"

report_for sfs-rank
rc6=$?
check "6a. two siblings do not crash the report (report.py exit $rc6)" '(( rc6 == 0 ))'
R6="$D6/report.json"
r6b="$(V plan_md_lines "$R6" 01-review-opus)"
check "6b. complete/ outranks inprogress/ as the live sidecar (want $PLAN_MD_LINES lines, not $PLAN_MD_DECOY_LINES; got $r6b)" '[[ "$r6b" == "'"$PLAN_MD_LINES"'" ]]'
# The loser is a prior attempt, not a discard: its measured dollars are rolled in beside
# the live figure. Both halves matter — the rank decides which sidecar the tables read,
# not which money is counted.
EXPECTED6="$(python3 -c "print($LIVE_COST + $DECOY_COST)")"
r6c="$(V field_close "$R6" cost.review "$EXPECTED6" 1e-9)"
check "6c. ...while the outranked sidecar's measured cost is still rolled in (want $EXPECTED6, got $r6c)" '[[ "$r6c" == "True" ]]'
r6d="$(V warning_contains "$R6" "01-review-opus" "earlier attempt")"
check "6d. ...and the roll-in is announced rather than silent (got $r6d)" '[[ "$r6d" == "True" ]]'

# ── 7: no sibling .md anywhere — a warning, not a crash ───────────────────────
# The rank still decides, and every reader of a sibling plan file has to survive its
# absence: this is the crash's general form, with no retry to have moved the .md.
D7="$(feature_dir sfs-nosibling)"
mkdir -p "$D7/review/failed"
echo "failed (exit 1): " > "$D7/review/failed/01-review-opus.progress.md"
usage_json "$D7/review/failed/01-review-opus.usage.json" null
mkdir -p "$D7/review/complete"
echo "review pass complete" > "$D7/review/complete/01-review-opus.progress.md"
usage_json "$D7/review/complete/01-review-opus.usage.json" "$LIVE_COST"

report_for sfs-nosibling
rc7=$?
check "7a. a missing sibling .md does not crash the report (report.py exit $rc7)" '(( rc7 == 0 ))'
R7="$D7/report.json"
r7b="$(V warning_contains "$R7" "01-review-opus.md")"
check "7b. ...it warns naming the plan file it looked for (got $r7b)" '[[ "$r7b" == "True" ]]'
r7c="$(V plan_md_lines "$R7" 01-review-opus)"
check "7c. ...and drops the plan from the plan-length table (got $r7c)" '[[ "$r7c" == "NONE" ]]'
r7d="$(V field_close "$R7" cost.review "$LIVE_COST" 1e-9)"
check "7d. ...while still pricing it from the ranked sidecar (got $r7d)" '[[ "$r7d" == "True" ]]'

# ── 8: one attempt reachable through two sidecars is billed once ──────────────
# Item 2 makes the roll-up read priors at attempt level, which is the condition the
# backlog entry set for this being worth doing. The overlap needs a hand-copied sidecar
# to occur at all — write_usage_sidecar merges attempts[] by session_id into the file at
# the plan's CURRENT path — but once it exists the same claude -p run is reachable
# through both files, and adding both figures invents money nobody spent.
D8="$(feature_dir sfs-dedupe)"
mkdir -p "$D8/review/failed"
echo "failed (exit 1): " > "$D8/review/failed/01-review-opus.progress.md"
usage_json "$D8/review/failed/01-review-opus.usage.json" "$LIVE_COST" null sess-shared
mkdir -p "$D8/review/complete"
plan_md "$D8/review/complete/01-review-opus.md"
echo "review pass complete" > "$D8/review/complete/01-review-opus.progress.md"
usage_json "$D8/review/complete/01-review-opus.usage.json" "$LIVE_COST" null sess-shared

report_for sfs-dedupe
rc8=$?
check "8a. two sidecars sharing an attempt do not crash the report (report.py exit $rc8)" '(( rc8 == 0 ))'
R8="$D8/report.json"
r8b="$(V field_close "$R8" cost.review "$LIVE_COST" 1e-9)"
check "8b. the shared attempt's dollars are counted once, not twice (want $LIVE_COST, got $r8b)" '[[ "$r8b" == "True" ]]'
r8c="$(V field_close "$R8" cost.total "$LIVE_COST" 1e-9)"
check "8c. ...in the total too (got $r8c)" '[[ "$r8c" == "True" ]]'

# ── 9: ...and named once when it carries no figure at all ─────────────────────
# The live sidecar has a priced attempt and a null one; the hand-copied twin holds only
# the null one. Both reach the same session, and the reader must be told about it once.
D9="$(feature_dir sfs-dedupe-unpriced)"
mkdir -p "$D9/review/failed"
echo "failed (exit 1): " > "$D9/review/failed/01-review-opus.progress.md"
usage_json_attempts "$D9/review/failed/01-review-opus.usage.json" null sess-shared \
  '[{"session_id": "sess-shared", "outcome": "killed", "total_cost_usd": null, "num_turns": null, "duration_ms": null}]'
mkdir -p "$D9/review/complete"
plan_md "$D9/review/complete/01-review-opus.md"
echo "review pass complete" > "$D9/review/complete/01-review-opus.progress.md"
usage_json_attempts "$D9/review/complete/01-review-opus.usage.json" "$LIVE_COST" sess-live \
  "[{\"session_id\": \"sess-shared\", \"outcome\": \"killed\", \"total_cost_usd\": null, \"num_turns\": null, \"duration_ms\": null}, {\"session_id\": \"sess-live\", \"outcome\": \"complete\", \"total_cost_usd\": $LIVE_COST, \"num_turns\": null, \"duration_ms\": null}]"

report_for sfs-dedupe-unpriced
rc9=$?
check "9a. a shared unpriced attempt does not crash the report (report.py exit $rc9)" '(( rc9 == 0 ))'
R9="$D9/report.json"
r9b="$(V field_equals "$R9" cost.unrecoverable_attempts '[{"plan": "01-review-opus", "session_id": "sess-shared"}]')"
check "9b. the shared unpriced attempt is named exactly once (got $r9b)" '[[ "$r9b" == "True" ]]'
r9c="$(V field_equals "$R9" cost.total_is_partial true)"
check "9c. ...and still marks the total a lower bound (got $r9c)" '[[ "$r9c" == "True" ]]'
r9d="$(V field_close "$R9" cost.review "$LIVE_COST" 1e-9)"
check "9d. ...while the priced attempt is billed once (got $r9d)" '[[ "$r9d" == "True" ]]'

# ── 10: a stem with more than one sidecar is reported as such ─────────────────
# find_orphan_usage cannot see a same-stem twin — a second sidecar for a stem the
# manifest DOES list collapses into that stem's index entry — so a corpus with a
# hand-copied or mis-filed sidecar looked identical to a clean one. The per-plan roll-in
# warning stays; this is the list a reader can count.
R1_MULTI='[{"plan": "01-review-opus", "queue": "review", "count": 2}]'
r10a="$(V field_equals "$R1" cost.multi_sidecar_stems "$R1_MULTI")"
check "10a. the two-sidecar stem is listed with its queue and count (got $r10a)" '[[ "$r10a" == "True" ]]'
check "10b. ...and named under the Cost table" 'grep -qF "Plans with more than one sidecar: 01-review-opus (2)" "$D1/report.md"'

# The other half: one sidecar is not a disagreement, and the line is absent rather than
# empty — without this the list could be hardcoded and 10a would still pass.
D10="$(feature_dir sfs-single)"
mkdir -p "$D10/review/complete"
plan_md "$D10/review/complete/01-review-opus.md"
echo "review pass complete" > "$D10/review/complete/01-review-opus.progress.md"
usage_json "$D10/review/complete/01-review-opus.usage.json" "$LIVE_COST"
report_for sfs-single
rc10=$?
check "10c. a single-sidecar feature still reports cleanly (report.py exit $rc10)" '(( rc10 == 0 ))'
r10d="$(V field_equals "$D10/report.json" cost.multi_sidecar_stems '[]')"
check "10d. ...with an empty multi_sidecar_stems (got $r10d)" '[[ "$r10d" == "True" ]]'
check "10e. ...and no line under the Cost table" '! grep -q "Plans with more than one sidecar" "$D10/report.md"'

# ── 11: a deduplicated attempt takes the copy that carries a figure ───────────
# Phase 8 settled that a shared attempt's dollars are counted ONCE; it did not settle
# which copy they come from. Here the live copy is null on both figures and
# recover_attempts.py has written recovered_cost_usd into the PRIOR — which is exactly
# the file it writes to for a killed attempt, since it walks the tree itself rather than
# through the index — so the only figure this session has lives on the file the index
# outranked. Before the rework the dedupe `continue`d past the prior before reading it
# and the money was lost twice over: not summed, and the live null copy then read as
# unrecoverable, marking a total that was in fact whole.
D11="$(feature_dir sfs-prior-figure)"
mkdir -p "$D11/review/failed"
echo "failed (exit 1): " > "$D11/review/failed/01-review-opus.progress.md"
usage_json "$D11/review/failed/01-review-opus.usage.json" null "$STALE_RECOVERED" sess-shared
mkdir -p "$D11/review/complete"
plan_md "$D11/review/complete/01-review-opus.md"
echo "review pass complete" > "$D11/review/complete/01-review-opus.progress.md"
usage_json "$D11/review/complete/01-review-opus.usage.json" null null sess-shared

report_for sfs-prior-figure
rc11=$?
check "11a. a figure carried only by the prior copy does not crash the report (report.py exit $rc11)" '(( rc11 == 0 ))'
R11="$D11/report.json"
r11b="$(V field_close "$R11" cost.review "$STALE_RECOVERED" 1e-9)"
check "11b. the prior copy's figure is counted (want $STALE_RECOVERED, got $r11b)" '[[ "$r11b" == "True" ]]'
r11c="$(V field_close "$R11" cost.total "$STALE_RECOVERED" 1e-9)"
check "11c. ...once, in the total too (got $r11c)" '[[ "$r11c" == "True" ]]'
r11d="$(V field_close "$R11" cost.recovered "$STALE_RECOVERED" 1e-9)"
check "11d. ...and reported as recovered dollars (got $r11d)" '[[ "$r11d" == "True" ]]'
r11e="$(V field_equals "$R11" cost.total_is_partial false)"
check "11e. ...leaving the total whole, since the session IS priced (got $r11e)" '[[ "$r11e" == "True" ]]'
r11f="$(V field_equals "$R11" cost.unrecoverable_attempts '[]')"
check "11f. ...naming it in neither cost.unrecoverable_attempts[] (got $r11f)" '[[ "$r11f" == "True" ]]'
r11g="$(V list_names_plan "$R11" cost.unpriced_plans 01-review-opus)"
check "11g. ...nor cost.unpriced_plans[] (got $r11g)" '[[ "$r11g" == "False" ]]'

# The same rule where the plan itself is priced, which is the shape the escalation
# described: the live sidecar has a good attempt of its own beside the shared null one,
# so the stem never takes the whole-plan unpriced path above and the shared session is
# classified attempt by attempt. That is where the live null copy fell into
# unrecoverable_sessions, naming a session the prior had a figure for.
D11B="$(feature_dir sfs-prior-figure-priced)"
mkdir -p "$D11B/review/failed"
echo "failed (exit 1): " > "$D11B/review/failed/01-review-opus.progress.md"
usage_json_attempts "$D11B/review/failed/01-review-opus.usage.json" null sess-shared \
  "[{\"session_id\": \"sess-shared\", \"outcome\": \"killed\", \"total_cost_usd\": null, \"num_turns\": null, \"duration_ms\": null, \"recovered_cost_usd\": $STALE_RECOVERED, \"recovered_from\": \"transcript\"}]"
mkdir -p "$D11B/review/complete"
plan_md "$D11B/review/complete/01-review-opus.md"
echo "review pass complete" > "$D11B/review/complete/01-review-opus.progress.md"
usage_json_attempts "$D11B/review/complete/01-review-opus.usage.json" "$LIVE_COST" sess-live \
  "[{\"session_id\": \"sess-shared\", \"outcome\": \"killed\", \"total_cost_usd\": null, \"num_turns\": null, \"duration_ms\": null}, {\"session_id\": \"sess-live\", \"outcome\": \"complete\", \"total_cost_usd\": $LIVE_COST, \"num_turns\": null, \"duration_ms\": null}]"

report_for sfs-prior-figure-priced
rc11b=$?
check "11h. the same shape beside a priced attempt does not crash the report (report.py exit $rc11b)" '(( rc11b == 0 ))'
R11B="$D11B/report.json"
EXPECTED11="$(python3 -c "print($LIVE_COST + $STALE_RECOVERED)")"
r11i="$(V field_close "$R11B" cost.review "$EXPECTED11" 1e-9)"
check "11i. both figures are counted, each once (want $EXPECTED11, got $r11i)" '[[ "$r11i" == "True" ]]'
r11j="$(V field_equals "$R11B" cost.unrecoverable_attempts '[]')"
check "11j. ...and the session the prior priced is not called unrecoverable (got $r11j)" '[[ "$r11j" == "True" ]]'
r11k="$(V field_equals "$R11B" cost.total_is_partial false)"
check "11k. ...so the total is not marked a lower bound for it (got $r11k)" '[[ "$r11k" == "True" ]]'

# ── 12: ...while a session null in EVERY copy is still unpriced ───────────────
# Phase 11's fixture with the recovered figure taken off the prior, and nothing else
# changed: the contrast that keeps 11 precise, since a merge rule that credited a copy
# carrying no figure would pass 11 and invent a zero here. The plan is named in
# cost.unpriced_plans[] rather than cost.unrecoverable_attempts[] because a stem with no
# dollars from ANY source is unpriced as a whole plan, before its attempts are
# classified — phase 2d is the same session on a plan whose live sidecar IS priced, and
# that is the path that names sessions one by one.
D12="$(feature_dir sfs-no-figure-anywhere)"
mkdir -p "$D12/review/failed"
echo "failed (exit 1): " > "$D12/review/failed/01-review-opus.progress.md"
usage_json "$D12/review/failed/01-review-opus.usage.json" null null sess-shared
mkdir -p "$D12/review/complete"
plan_md "$D12/review/complete/01-review-opus.md"
echo "review pass complete" > "$D12/review/complete/01-review-opus.progress.md"
usage_json "$D12/review/complete/01-review-opus.usage.json" null null sess-shared

report_for sfs-no-figure-anywhere
rc12=$?
check "12a. two figure-less copies do not crash the report (report.py exit $rc12)" '(( rc12 == 0 ))'
R12="$D12/report.json"
r12b="$(V field_close "$R12" cost.review "$NO_COST" 1e-9)"
check "12b. no dollars are invented for a session no copy priced (got $r12b)" '[[ "$r12b" == "True" ]]'
r12c="$(V field_equals "$R12" cost.total_is_partial true)"
check "12c. ...and the total is a lower bound (got $r12c)" '[[ "$r12c" == "True" ]]'
r12d="$(V list_names_plan "$R12" cost.unpriced_plans 01-review-opus)"
check "12d. ...with the plan named in cost.unpriced_plans[] (got $r12d)" '[[ "$r12d" == "True" ]]'
r12e="$(V field_equals "$R12" cost.unrecoverable_attempts '[]')"
check "12e. ...and not also attempt by attempt, the plan having no priced attempt to classify beside it (got $r12e)" '[[ "$r12e" == "True" ]]'

# ── 13: where both copies carry a figure and disagree, the live one wins ──────
# The live sidecar is the file the runner writes to at the plan's CURRENT path, and the
# file every other figure in the report is read from; a prior that disagrees is an older
# record of the same session, not a second charge. Green before the rework as well as
# after — the dedupe already kept the live copy — and here so the merge rule phase 11
# adds cannot turn the precedence around unnoticed.
D13="$(feature_dir sfs-prior-disagrees)"
mkdir -p "$D13/review/failed"
echo "failed (exit 1): " > "$D13/review/failed/01-review-opus.progress.md"
usage_json "$D13/review/failed/01-review-opus.usage.json" "$DECOY_COST" null sess-shared
mkdir -p "$D13/review/complete"
plan_md "$D13/review/complete/01-review-opus.md"
echo "review pass complete" > "$D13/review/complete/01-review-opus.progress.md"
usage_json "$D13/review/complete/01-review-opus.usage.json" "$LIVE_COST" null sess-shared

report_for sfs-prior-disagrees
rc13=$?
check "13a. two disagreeing copies do not crash the report (report.py exit $rc13)" '(( rc13 == 0 ))'
R13="$D13/report.json"
r13b="$(V field_close "$R13" cost.review "$LIVE_COST" 1e-9)"
check "13b. the LIVE copy's figure is the one counted (want $LIVE_COST, not $DECOY_COST; got $r13b)" '[[ "$r13b" == "True" ]]'
r13c="$(V field_close "$R13" cost.total "$LIVE_COST" 1e-9)"
check "13c. ...once, and not summed with the prior's (got $r13c)" '[[ "$r13c" == "True" ]]'
r13d="$(V field_equals "$R13" cost.total_is_partial false)"
check "13d. ...leaving the total whole (got $r13d)" '[[ "$r13d" == "True" ]]'

if (( fails > 0 )); then echo "stale-failed-sidecars: $fails assertion(s) FAILED"; exit 1; fi
echo "stale-failed-sidecars: all assertions passed"
