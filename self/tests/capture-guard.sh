#!/usr/bin/env bash
set -uo pipefail

# Self-test for capture_planning.py's two write guards — the frozen-cost refusal and the
# already-captured skip. Run by self/gate.sh, or by hand: bash self/tests/capture-guard.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d — copies of
# `analysis/{pricing,roots,transcript,capture_planning}.py` — plus a synthesized
# `self/features/<slug>/` corpus and, under a redirected $HOME, the
# `~/.claude/projects/*/<session_id>.jsonl` transcripts capture reads. No model, no
# network; runs in a few seconds.
#
# What it guards. `planning.json` is a *frozen* record: it is the only surviving
# account of a feature's planning cost once the session transcripts under
# ~/.claude/projects/ age out of retention. capture_planning.py rebuilds that file from
# those transcripts, so re-running it on a feature whose transcripts have expired finds
# nothing and writes $0.00 over a real recorded figure. That is not hypothetical — it
# zeroed 11 features in humanNetworkMap ($151.58 -> $0.00 on add-component-tests among
# them) in one documented cadence run before the guard existed.
#
# The rule under test: refuse the write when a session the prior capture priced is
# absent from the new scan AND has no transcript left on disk. Transcript-still-present
# is the discriminator that keeps the guard from firing on ordinary work — a session
# dropped by a manifest edit is reproducible and therefore safe, while a session whose
# transcript is gone is unrecoverable and therefore protected.
#
# The second rule, in front of it: a feature that already has a `captured_at` is not
# re-captured at all unless asked. The refusal above protects the figure that would be
# destroyed; the skip protects everything else in the file — `excluded_session_ids` a
# later scan can no longer see, `rates_source`, `captured_at` itself — none of which the
# refusal looks at, since a re-capture that finds every priced session still reachable is
# a legitimate write that can still silently drop metadata. It also makes the cadence
# cheap: a skipped feature is never scanned.
#
# Asserts, in order:
#   1. a first capture, with no prior planning.json, writes a non-zero cost;
#   2. re-capturing while the transcript still exists rewrites the file normally —
#      the guard does not block ordinary re-capture;
#   3. re-capturing after the transcript is gone REFUSES: exit non-zero, planning.json
#      byte-identical to before, and the prior figure named on stdout;
#   4. --force overwrites that same refusal, zeroing the total (the escape hatch works);
#   5. a session dropped by a session_window edit, transcript still present, does NOT
#      trip the guard — that is a deliberate manifest change, and it is exactly what
#      fixing an overlapping-window warning does;
#   6. a session that is gone from disk but now excluded (claimed by a usage.json as a
#      runner session) does NOT trip the guard — reclassified, not lost;
#   7. a prior capture whose total is 0.0 is overwritable without --force — there is no
#      frozen figure to protect;
#   8. a transcript the scan can no longer reach (an orphaned worktree's) is treated as
#      lost, not as merely deselected;
#   9. a declared branch that matches no transcript is warned about;
#  10. a second run over an already-captured feature SKIPS: exit 0, planning.json byte-
#      identical (captured_at included), and the message names --recapture. It skips
#      whether or not the transcripts are still there, so the cadence over a mature
#      corpus is quiet rather than a wall of refusals;
#  11. --recapture rewrites it, and --force implies --recapture (forcing a write past
#      the frozen-cost guard cannot also be silently skipped by the one in front of it);
#  12. --all walks every feature, capturing the uncaptured and skipping the rest;
#  13. --all --recapture — the full refresh — does not abort on a refusal: the remaining
#      features are still captured, and the run exits non-zero at the end;
#  14. an empty session_window (from == to, or from > to) is warned about, while an
#      open-ended one and a real interval written across two zone formats are not;
#  15. the naming rule: a session launched in the feature's own worktree, R-<slug>, is
#      selected and its entry records that cwd, while one launched in any other sibling
#      directory is not, and the warning names the directory it came from;
#  16. a capture that matches no session and no subagent writes nothing and exits
#      non-zero, naming the three causes; --force writes the honest zero.
#  17. that refusal is lifted when the only sessions on the branch are excluded ones —
#      named in the manifest's exclude_sessions, or claimed by a usage.json as a runner
#      session — because either route proves the branch name is right; capture writes
#      the zero without --force and says so, while a branch with no session at all is
#      still refused, and so is a corpus whose excluded session carries some OTHER
#  18. --all skips a feature whose session_window.to is null as in flight and writes
#      nothing; naming the slug still captures it.
#      branch (17d): the evidence is pinned to the manifest's branches, not to the
#      presence of excluded sessions in the repo, or a branch typo would read as an
#      evidenced $0.00 in every repo that has ever run a batch.
#
# Assertions 3-7 were RED until the guard landed in analysis/capture_planning.py; 10-13
# were RED until the skip did; 14 until check_empty_window did. A run against a script
# missing any of them is expected to FAIL them, not to crash.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Physical path, not the symlinked one. roots.py resolves AGENT_TOOLING_DIR through
# Path.resolve(), so on macOS it sees /private/var/... while mktemp -d hands back
# /var/... — and capture matches a transcript by comparing its `cwd` against that
# resolved root, so an unresolved fixture path matches nothing and every assertion
# below passes or fails vacuously on an empty scan.
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"

for f in pricing.py roots.py transcript.py capture_planning.py; do
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

SLUG="frozen-cost"
FEATURE_DIR="$AT/self/features/$SLUG"
PLANNING="$FEATURE_DIR/planning.json"
BRANCH="someFeatureBranch"
MODEL="claude-sonnet-5"
SESSION_A="aaaaaaaa-0000-0000-0000-000000000001"
SESSION_B="bbbbbbbb-0000-0000-0000-000000000002"

# $HOME is redirected so the fixture transcripts are the only ones on disk — a real
# ~/.claude/projects/ would otherwise leak sessions into every scan below.
FAKE_HOME="$TMP/home"
PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/' '-')"
mkdir -p "$PROJECTS"

mkdir -p "$FEATURE_DIR"

# write_manifest [FROM] [TO] — the feature README whose last ```json fence capture reads.
write_manifest() {
  # Default `to` is a far bound, not null: capture --all skips an open window as in
  # flight (phase 18), and every --all phase here means to walk this feature.
  local frm="${1:-null}" to="${2:-2099-01-01T00:00:00.000Z}"
  [ "$frm" != "null" ] && frm="\"$frm\""
  [ "$to" != "null" ] && to="\"$to\""
  cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

Fixture feature for self/tests/capture-guard.sh.

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": $frm, "to": $to},
  "exclude_sessions": []
}
\`\`\`
EOF
}

# write_transcript SESSION_ID TIMESTAMP OUTPUT_TOKENS
write_transcript() {
  session_line "$1" "$AT" "$BRANCH" "msg-$1" "$MODEL" "$2" 100 "$3" 0 0 0 \
    > "$PROJECTS/$1.jsonl"
}

capture() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$SLUG" "$@" 2>&1; }
# Every phase below that means "rebuild the file" says so, because the default is now to
# skip a feature that already has one. The frozen-cost assertions are about what happens
# once the scan actually runs, so they all go through here; the raw `capture` is reserved
# for the phases testing the skip itself and for a genuinely first capture.
recapture() { capture --recapture "$@"; }
capture_all() { HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --all "$@" 2>&1; }

total_of() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['cost_usd']['total'])" "$1"; }

echo "capture_planning frozen-cost guard"

# ── 1. first capture, nothing to protect ──────────────────────────────────────
write_manifest
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
capture > "$TMP/out1.txt"
first_total="$(total_of "$PLANNING")"
check "1. first capture writes a non-zero cost" \
  "python3 -c \"import sys; sys.exit(0 if float('$first_total') > 0 else 1)\""

# ── 2. re-capture with the transcript still present ───────────────────────────
recapture > "$TMP/out2.txt"
rc2=$?
check "2. re-capture with transcript present is allowed" "[ $rc2 -eq 0 ]"
check "2b. re-capture with transcript present preserves the total" \
  "python3 -c \"import sys; sys.exit(0 if abs(float('$(total_of "$PLANNING")') - float('$first_total')) < 1e-9 else 1)\""

# ── 3. transcript aged out — the destructive case ─────────────────────────────
cp "$PLANNING" "$TMP/planning.before.json"
rm "$PROJECTS/$SESSION_A.jsonl"
recapture > "$TMP/out3.txt"
rc3=$?
check "3. re-capture after the transcript is gone exits non-zero" "[ $rc3 -ne 0 ]"
check "3b. planning.json is left byte-identical" \
  "cmp -s '$TMP/planning.before.json' '$PLANNING'"
check "3c. the refusal names the session it is protecting" \
  "grep -q '$SESSION_A' '$TMP/out3.txt'"
check "3d. the refusal names the dollar figure at risk" \
  "grep -qi 'refus\|would overwrite\|--force' '$TMP/out3.txt'"

# ── 4. --force is the escape hatch ────────────────────────────────────────────
capture --force > "$TMP/out4.txt"
rc4=$?
check "4. --force overwrites the frozen capture" "[ $rc4 -eq 0 ]"
check "4b. --force actually zeroed the total" \
  "python3 -c \"import sys; sys.exit(0 if float('$(total_of "$PLANNING")') == 0.0 else 1)\""

# ── 5. a window edit that drops a live session is not loss ────────────────────
# Restore a two-session capture, then narrow the window so B falls outside it. Both
# transcripts stay on disk, so the dropped session is reproducible — the shape of
# fixing an overlapping-window warning between two features sharing a branch.
write_manifest
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
write_transcript "$SESSION_B" "2026-07-09T10:00:00.000Z" 5000
recapture > /dev/null
two_total="$(total_of "$PLANNING")"
write_manifest null "2026-07-05T00:00:00.000Z"
recapture > "$TMP/out5.txt"
rc5=$?
check "5. a window edit dropping a live session is allowed" "[ $rc5 -eq 0 ]"
check "5b. the narrowed window really did drop a session" \
  "python3 -c \"import sys; sys.exit(0 if float('$(total_of "$PLANNING")') < float('$two_total') else 1)\""

# ── 6. gone from disk but reclassified as a runner session ────────────────────
# B's transcript disappears, but a usage.json now claims it — its cost is accounted
# for as build cost, so dropping it from planning is a correction, not a loss.
write_manifest
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
write_transcript "$SESSION_B" "2026-07-09T10:00:00.000Z" 5000
recapture > /dev/null
rm "$PROJECTS/$SESSION_B.jsonl"
mkdir -p "$FEATURE_DIR/auto/complete"
printf '{"plan":"01-x","attempts":[{"session_id":"%s","outcome":"complete","total_cost_usd":1.0}]}\n' \
  "$SESSION_B" > "$FEATURE_DIR/auto/complete/01-x.usage.json"
recapture > "$TMP/out6.txt"
rc6=$?
check "6. a vanished session now claimed by a usage.json is allowed" "[ $rc6 -eq 0 ]"
rm -rf "$FEATURE_DIR/auto"

# ── 7. nothing to protect when the prior total is zero ────────────────────────
write_manifest
rm -f "$PROJECTS/$SESSION_A.jsonl" "$PROJECTS/$SESSION_B.jsonl"
capture --force > /dev/null
check "7. prior capture is zero-cost" \
  "python3 -c \"import sys; sys.exit(0 if float('$(total_of "$PLANNING")') == 0.0 else 1)\""
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
recapture > "$TMP/out7.txt"
rc7=$?
check "7b. overwriting a zero-cost capture needs no --force" "[ $rc7 -eq 0 ]"

# ── 8. a transcript the scan can no longer reach is lost, not merely deselected ──
# The exact shape that re-zeroed two features after the guard shipped: planning ran from
# a git worktree (…/musicMap-levels) that has since been removed. Its project directory
# still contains the fragment of the repo's own, so the scan walks it — but every line's
# cwd is the worktree, so repo_match fails and the session can never be selected from
# this checkout again. A guard that asks only "does a file with this id exist somewhere"
# finds it and vouches for it, and the overwrite proceeds to $0.00, exit 0, no --force.
write_manifest
rm -f "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
recapture > /dev/null
reachable_total="$(total_of "$PLANNING")"
check "8. baseline: the session is priced while reachable" \
  "python3 -c \"import sys; sys.exit(0 if float('$reachable_total') > 0 else 1)\""

# Move it into an orphaned worktree's project dir, rewriting cwd to that worktree.
WORKTREE="$AT-levels"
WT_PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$WORKTREE" | tr '/' '-')"
mkdir -p "$WT_PROJECTS"
session_line "$SESSION_A" "$WORKTREE" "$BRANCH" "msg-$SESSION_A" "$MODEL" \
  "2026-07-01T10:00:00.000Z" 100 5000 0 0 0 > "$WT_PROJECTS/$SESSION_A.jsonl"
rm -f "$PROJECTS/$SESSION_A.jsonl"

cp "$PLANNING" "$TMP/planning.before8.json"
recapture > "$TMP/out8.txt"
rc8=$?
check "8b. an unreachable transcript is refused, not silently zeroed" "[ $rc8 -ne 0 ]"
check "8c. the priced figure survives" \
  "cmp -s '$TMP/planning.before8.json' '$PLANNING'"
rm -rf "$WT_PROJECTS"

# ── 9. a declared branch that matches no transcript is called out ─────────────
# A mistyped or reprefixed branch name (e.g. "ssdesai/foo" for a branch actually named
# "foo") matches nothing, and every session on it goes uncounted — the feature reports
# $0.00 and reads as "planning was free" rather than "the manifest is wrong".
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH", "ssdesai/$BRANCH"],
  "session_window": {"from": null, "to": null},
  "exclude_sessions": []
}
\`\`\`
EOF
capture > "$TMP/out9.txt"
check "9. a branch matching no transcript is warned about" \
  "grep -q 'ssdesai/$BRANCH' '$TMP/out9.txt'"
check "9b. a branch that did match is not warned about" \
  "! grep -q \"branch '$BRANCH'\" '$TMP/out9.txt'"

# ── 10. an already-captured feature is left alone ─────────────────────────────
# The frozen-cost guard only asks whether a re-capture would drop a priced session. A
# re-capture that drops nothing priced still rewrites captured_at, rates_source and
# excluded_session_ids — and that last one shrinks as runner transcripts age out, so a
# clean-looking re-run quietly forgets which sessions were runner cost. Nothing should
# rewrite a frozen record without being asked.
write_manifest
rm -f "$PLANNING" "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
capture > /dev/null
cp "$PLANNING" "$TMP/planning.before10.json"
prior_at="$(python3 -c "import json;print(json.load(open('$TMP/planning.before10.json'))['captured_at'])")"
prior_total="$(python3 -c "import json;print('%.4f' % json.load(open('$TMP/planning.before10.json'))['cost_usd']['total'])")"

capture > "$TMP/out10.txt"
rc10=$?
check "10. a second run over a captured feature exits 0" "[ $rc10 -eq 0 ]"
check "10b. planning.json is byte-identical, captured_at included" \
  "cmp -s '$TMP/planning.before10.json' '$PLANNING'"
check "10c. the skip says how to rebuild it" \
  "grep -q -- '--recapture' '$TMP/out10.txt'"
check "10d. the skip names the prior capture time" \
  "grep -qF '$prior_at' '$TMP/out10.txt'"
# A frozen $0.00 is the one prior capture worth revisiting, and after a skip the warning
# that normally explains a zero (check_unmatched_branches) has no scan to speak from — so
# the recorded figure has to be on the skip line itself.
check "10e. the skip states the frozen total" \
  "grep -qF '\$$prior_total' '$TMP/out10.txt'"

# The cadence runs over a whole corpus, most of it years-old features whose transcripts
# are long gone. Those must be skipped like any other captured feature — quietly, not as
# a refusal, which is a failure exit and reads as something needing attention.
rm -f "$PROJECTS"/*.jsonl
capture > "$TMP/out10f.txt"
rc10f=$?
check "10f. a captured feature whose transcripts are gone is skipped, not refused" \
  "[ $rc10f -eq 0 ] && ! grep -qi 'refus' '$TMP/out10f.txt'"
check "10g. and its planning.json is still untouched" \
  "cmp -s '$TMP/planning.before10.json' '$PLANNING'"

# ── 11. asking for it rebuilds it ─────────────────────────────────────────────
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
recapture > "$TMP/out11.txt"
rc11=$?
check "11. --recapture rebuilds an already-captured feature" \
  "[ $rc11 -eq 0 ] && ! cmp -s '$TMP/planning.before10.json' '$PLANNING'"

# --force is the harder ask of the two: it overwrites past the frozen-cost guard. The
# skip sitting in front of that guard must not swallow it.
cp "$PLANNING" "$TMP/planning.before11b.json"
capture --force > "$TMP/out11b.txt"
rc11b=$?
check "11b. --force implies --recapture rather than being skipped" \
  "[ $rc11b -eq 0 ] && ! cmp -s '$TMP/planning.before11b.json' '$PLANNING'"

# ── 12. --all walks the corpus, populating only what is new ───────────────────
SLUG2="frozen-cost-two"
DIR2="$AT/self/features/$SLUG2"
BRANCH2="otherFeatureBranch"
SESSION_C="cccccccc-0000-0000-0000-000000000003"
mkdir -p "$DIR2"
cat > "$DIR2/README.md" <<EOF
# $SLUG2

Second fixture feature, so --all has something to walk.

\`\`\`json
{
  "slug": "$SLUG2",
  "branches": ["$BRANCH2"],
  "session_window": {"from": null, "to": "2099-01-01T00:00:00.000Z"},
  "exclude_sessions": []
}
\`\`\`
EOF
session_line "$SESSION_C" "$AT" "$BRANCH2" "msg-$SESSION_C" "$MODEL" \
  "2026-07-02T10:00:00.000Z" 100 5000 0 0 0 > "$PROJECTS/$SESSION_C.jsonl"

cp "$PLANNING" "$TMP/planning.before12.json"
capture_all > "$TMP/out12.txt"
rc12=$?
check "12. --all exits 0 when nothing is refused" "[ $rc12 -eq 0 ]"
check "12b. --all captures the feature that had none" "[ -f '$DIR2/planning.json' ]"
check "12c. --all leaves the already-captured feature untouched" \
  "cmp -s '$TMP/planning.before12.json' '$PLANNING'"
check "12d. --all reports on both features" \
  "grep -q '$SLUG:' '$TMP/out12.txt' && grep -q '$SLUG2:' '$TMP/out12.txt'"

HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --all "$SLUG" \
  > "$TMP/out12e.txt" 2>&1
rc12e=$?
check "12e. --all with a slug is rejected rather than half-honoured" "[ $rc12e -ne 0 ]"

# ── 13. the full refresh survives a refusal mid-corpus ────────────────────────
# --all --recapture over a mature corpus WILL hit the frozen-cost guard — that is the
# point of the guard. A refusal must not take the rest of the run down with it, or one
# old feature makes the whole refresh unusable.
rm -f "$PROJECTS/$SESSION_A.jsonl"
cp "$PLANNING" "$TMP/planning.before13.json"
cp "$DIR2/planning.json" "$TMP/two.before13.json"
capture_all --recapture > "$TMP/out13.txt"
rc13=$?
check "13. --all --recapture exits non-zero when a feature refuses" "[ $rc13 -ne 0 ]"
check "13b. the refusing feature's frozen figure survives" \
  "cmp -s '$TMP/planning.before13.json' '$PLANNING'"
check "13c. a refusal does not stop the features after it" \
  "! cmp -s '$TMP/two.before13.json' '$DIR2/planning.json'"

# ── 14. an empty session_window is called out ─────────────────────────────────
# The sibling of assertion 9, by a different route: `from == to` on a half-open window
# matches nothing, so every session on the branch is dropped and the feature freezes at
# $0.00 while the branch name is perfectly correct. Two features in this corpus shipped
# that way and held $38.76 of real planning cost at zero. Unlike the overlap warning
# this is proven from the manifest alone, so it must fire even though the branch matches
# and the transcripts are present.
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000

write_manifest "2026-07-01T09:00:00Z" "2026-07-01T09:00:00Z"
capture > "$TMP/out14.txt"
check "14. an empty window (from == to) is warned about" \
  "grep -q 'session_window is empty' '$TMP/out14.txt'"
check "14b. the empty window really does match nothing — no planning.json is written" \
  "[ ! -f '$PLANNING' ]"

# Backwards is the same emptiness, and must not read as a valid window.
write_manifest "2026-07-01T12:00:00Z" "2026-07-01T08:00:00Z"
capture --recapture > "$TMP/out14c.txt"
check "14c. an inverted window (from > to) is warned about too" \
  "grep -q 'session_window is empty' '$TMP/out14c.txt'"

# The check compares instants, not strings: these two bounds are 09:00Z and 13:00Z, so
# the window is a real four-hour interval despite `from` sorting above `to` as text.
write_manifest "2026-07-01T05:00:00-04:00" "2026-07-01T13:00:00Z"
capture --recapture > "$TMP/out14d.txt"
check "14d. a non-empty window written across two zone formats is not warned about" \
  "! grep -q 'session_window is empty' '$TMP/out14d.txt'"
check "14e. that window still selects its session" \
  "python3 -c \"import sys; sys.exit(0 if float('\$(total_of '$PLANNING')') > 0 else 1)\""

# An open-ended side is unbounded, never empty.
write_manifest
capture --recapture > "$TMP/out14f.txt"
check "14f. an open-ended window is not warned about" \
  "! grep -q 'session_window is empty' '$TMP/out14f.txt'"

# ── 15. the naming rule: R-<slug> is the feature's worktree ────────────────────
# LIFECYCLE.md: for slug S in a repo whose primary checkout is R, the worktree is R-S,
# and the coordinator session is launched inside it. Its transcript lives in that
# path's own project directory with every line's cwd = R-S — a sibling of R, so the
# old prefix test (cwd under R) dropped it. Capture derives R-S from the slug and
# accepts it; any other sibling stays out, and the warning says where it was seen.
write_manifest
rm -f "$PLANNING" "$PROJECTS"/*.jsonl
FEATURE_WT="$AT-$SLUG"
FEATURE_WT_PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$FEATURE_WT" | tr '/' '-')"
OTHER_WT="$AT-other"
OTHER_WT_PROJECTS="$FAKE_HOME/.claude/projects/$(echo "$OTHER_WT" | tr '/' '-')"
mkdir -p "$FEATURE_WT_PROJECTS" "$OTHER_WT_PROJECTS"
session_line "$SESSION_A" "$FEATURE_WT" "$BRANCH" "msg-$SESSION_A" "$MODEL" \
  "2026-07-01T10:00:00.000Z" 100 5000 0 0 0 > "$FEATURE_WT_PROJECTS/$SESSION_A.jsonl"
session_line "$SESSION_B" "$OTHER_WT" "$BRANCH" "msg-$SESSION_B" "$MODEL" \
  "2026-07-01T11:00:00.000Z" 100 5000 0 0 0 > "$OTHER_WT_PROJECTS/$SESSION_B.jsonl"
capture > "$TMP/out15.txt"
rc15=$?
check "15. a session launched in R-<slug> is selected" \
  "[ $rc15 -eq 0 ] && [ \"\$(python3 -c \"import json;print([s['session_id'] for s in json.load(open('$PLANNING'))['sessions']])\")\" = \"['$SESSION_A']\" ]"
check "15b. its entry records the cwd it was launched in, and that it was selected by branch" \
  "[ \"\$(python3 -c \"import json;s=json.load(open('$PLANNING'))['sessions'][0];print(s['cwd'], s['selected_by'])\")\" = '$FEATURE_WT branch' ]"
check "15c. a session in another sibling directory is not selected" \
  "! grep -q '$SESSION_B' '$PLANNING'"
check "15d. and the warning names the directory it was launched from" \
  "grep -q '$OTHER_WT' '$TMP/out15.txt'"
rm -rf "$FEATURE_WT_PROJECTS" "$OTHER_WT_PROJECTS"

# ── 16. nothing matched: no silent zero ───────────────────────────────────────
# The frozen \$0.00 that reads as "planning was free". A first capture that matches
# nothing must not leave a file behind for --all to protect ever after.
write_manifest
rm -f "$PLANNING" "$PROJECTS"/*.jsonl
capture > "$TMP/out16.txt"
rc16=$?
check "16. a capture that matches nothing exits non-zero" "[ $rc16 -ne 0 ]"
check "16b. and writes no planning.json" "[ ! -f '$PLANNING' ]"
check "16c. naming the three causes and the command for each" \
  "grep -q 'git branch --list' '$TMP/out16.txt' && grep -qi 'aged out' '$TMP/out16.txt' && grep -qi 'launched' '$TMP/out16.txt'"
capture --force > "$TMP/out16d.txt"
rc16d=$?
check "16d. --force writes the honest zero" \
  "[ $rc16d -eq 0 ] && [ \"\$(total_of '$PLANNING')\" = '0.0' ]"
# Under --all the refusal counts like any other: the run goes on and exits non-zero.
rm -f "$PLANNING"
capture_all > "$TMP/out16e.txt"
rc16e=$?
check "16e. --all counts the refusal and exits non-zero" \
  "[ $rc16e -ne 0 ] && [ ! -f '$PLANNING' ] && grep -q 'refused' '$TMP/out16e.txt'"

# ── 17. an evidenced zero: excluded sessions met on the branch lift the refusal ──
# A feature whose only sessions on its branch are excluded ones — runner sessions a
# usage.json already prices, or ids the manifest excludes — has still been seen on that
# branch: the name is right, and the $0.00 is evidenced rather than suspicious. Unlike
# assertion 16, this case must not need --force.

# 17a. the manifest's exclude_sessions names the one session that carries the branch.
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["$BRANCH"],
  "session_window": {"from": null, "to": null},
  "exclude_sessions": ["$SESSION_A"]
}
\`\`\`
EOF
capture > "$TMP/out17a.txt"
rc17a=$?
check "17a. a manifest-excluded session carrying the branch is not refused" "[ $rc17a -eq 0 ]"
check "17a2. planning.json is written" "[ -f '$PLANNING' ]"
check "17a3. sessions is empty" \
  "python3 -c \"import json,sys; sys.exit(0 if json.load(open('$PLANNING'))['sessions'] == [] else 1)\""
check "17a4. excluded_session_ids holds it" \
  "python3 -c \"import json,sys; sys.exit(0 if '$SESSION_A' in json.load(open('$PLANNING'))['excluded_session_ids'] else 1)\""
check "17a5. cost_usd.total is 0" \
  "[ \"\$(total_of '$PLANNING')\" = '0.0' ]"
check "17a6. stdout says the zero is evidenced" \
  "grep -qi 'evidenced' '$TMP/out17a.txt'"

# 17b. the manifest excludes nothing; a usage.json elsewhere claims the session as a
# runner session (attempts[].session_id) — the other route collect_excluded_session_ids
# checks.
write_manifest
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
write_transcript "$SESSION_A" "2026-07-01T10:00:00.000Z" 5000
mkdir -p "$FEATURE_DIR/auto/complete"
printf '{"plan":"01-x","attempts":[{"session_id":"%s","outcome":"complete","total_cost_usd":1.0}]}\n' \
  "$SESSION_A" > "$FEATURE_DIR/auto/complete/01-x-haiku.usage.json"
capture > "$TMP/out17b.txt"
rc17b=$?
check "17b. a runner session claimed by a usage.json is not refused" "[ $rc17b -eq 0 ]"
check "17b2. planning.json is written" "[ -f '$PLANNING' ]"
check "17b3. sessions is empty" \
  "python3 -c \"import json,sys; sys.exit(0 if json.load(open('$PLANNING'))['sessions'] == [] else 1)\""
check "17b4. excluded_session_ids holds it" \
  "python3 -c \"import json,sys; sys.exit(0 if '$SESSION_A' in json.load(open('$PLANNING'))['excluded_session_ids'] else 1)\""
check "17b5. cost_usd.total is 0" \
  "[ \"\$(total_of '$PLANNING')\" = '0.0' ]"
check "17b6. stdout says the zero is evidenced" \
  "grep -qi 'evidenced' '$TMP/out17b.txt'"
rm -rf "$FEATURE_DIR/auto"

# 17c. no session at all still refuses — the two outcomes side by side.
write_manifest
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
capture > "$TMP/out17c.txt"
rc17c=$?
check "17c. a branch no transcript carries is still refused" "[ $rc17c -ne 0 ]"
check "17c2. and writes no planning.json" "[ ! -f '$PLANNING' ]"

# 17d. the evidence has to be on THIS feature's branch. A corpus with an excluded session
# on some other branch is every repo that has ever run a batch, so if that alone lifted
# the refusal a typo'd `branches` would read as an evidenced $0.00 — the one failure the
# refusal exists to catch. Unlike 17c the corpus is not empty: the transcript is there,
# in a claimable directory, runner-excluded exactly as in 17b, and carries branch `other`.
rm -f "$FEATURE_DIR/planning.json" "$PROJECTS"/*.jsonl
session_line "$SESSION_A" "$AT" "other" "msg-$SESSION_A" "$MODEL" \
  "2026-07-01T10:00:00.000Z" 100 5000 0 0 0 > "$PROJECTS/$SESSION_A.jsonl"
mkdir -p "$FEATURE_DIR/auto/complete"
printf '{"plan":"01-x","attempts":[{"session_id":"%s","outcome":"complete","total_cost_usd":1.0}]}\n' \
  "$SESSION_A" > "$FEATURE_DIR/auto/complete/01-x-haiku.usage.json"
cat > "$FEATURE_DIR/README.md" <<EOF
# $SLUG

\`\`\`json
{
  "slug": "$SLUG",
  "branches": ["typo"],
  "session_window": {"from": null, "to": null},
  "exclude_sessions": []
}
\`\`\`
EOF
capture > "$TMP/out17d.txt"
rc17d=$?
check "17d. an excluded session on another branch is not evidence for a typo'd one" \
  "[ $rc17d -ne 0 ]"
check "17d2. and writes no planning.json" "[ ! -f '$PLANNING' ]"
check "17d3. the refusal is the three-cause one, naming the branch check" \
  "grep -q 'git branch --list' '$TMP/out17d.txt' && ! grep -qi 'evidenced' '$TMP/out17d.txt'"
rm -rf "$FEATURE_DIR/auto"

# ── 18: --all skips a feature whose window is still open ─────────────────────
# A sweep over the corpus must not freeze a feature feature-close.sh has not captured:
# a record written here would make that close skip as "already captured" and report the
# premature figure. Naming the slug still captures it.
write_manifest "2026-07-01T00:00:00.000Z" null
rm -f "$PLANNING"
HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self --all > "$TMP/out18.txt" 2>&1
check "18a. --all reports the open-window feature as in flight" \
  "grep -q '^$SLUG: in flight' '$TMP/out18.txt' && grep -q 'in flight' '$TMP/out18.txt'"
check "18b. and writes no planning.json for it" "[ ! -f '$PLANNING' ]"
capture > "$TMP/out18c.txt"
check "18c. naming the slug does not skip it as in flight" "! grep -q 'in flight' '$TMP/out18c.txt'"
rm -f "$PLANNING"

echo
if [ "$fails" -eq 0 ]; then
  echo "capture-guard: all checks passed"
else
  echo "capture-guard: $fails check(s) failed"
fi
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
