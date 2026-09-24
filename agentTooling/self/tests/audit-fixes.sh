#!/usr/bin/env bash
set -uo pipefail

# Self-test for the two audit items with no home in another test file
# (self/DESIGN-2026-09-16-lifecycle-restructure.md §3.8;
# self/features/sweep-retirement-and-audit-fixes/README.md). Run by self/gate.sh, or by
# hand: bash self/tests/audit-fixes.sh
#
# Both were found by the 2026-09-16 audit as gaps that read as correct output:
# `report.py --all` rendered a trend table that silently omitted every feature whose
# report had never been written (three of this corpus's own), and `run-batch.sh` ran its
# corpus lint only when the slug was typed — an inferred slug bought the batch without
# one.
#
# Two sandboxes under one mktemp -d, no model and no network:
#
#   A. report.py --all fills the gaps. A throwaway agentTooling checkout (a real git
#      repo, since capture_planning.py resolves its session root by walking up to the
#      nearest .git) with one --self feature whose manifest names a branch a synthesized
#      transcript carries. capture_planning.py freezes its planning.json; no report.json
#      exists. Asserts: `--all` writes report.json AND report.md for it, prints
#      "1 report(s) written", and the trend table it then prints carries that feature's
#      row; a second `--all` fills nothing ("0 report(s) written"), leaves the report
#      byte-identical, and still prints the row.
#
#   B. run-batch.sh lints an INFERRED slug. An ordinary (non---self) sandbox repo with
#      exactly one feature, so the build pass resolves the slug with none given, and a
#      manifest whose session_window.to precedes its from — the lint check-plans.sh
#      gained with it. Asserts: with no slug argument the batch prints the check-plans
#      banner, FAILs on that feature, exits non-zero, and stops there — the verify and
#      review passes never run.
#
# A missing script fails its assertions loudly rather than aborting the run (no `set -e`;
# every cp below tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

echo "audit-fixes"

# ── A. report.py --all fills the missing reports ──────────────────────────────
AT="$TMP/a/agentTooling"
mkdir -p "$AT/analysis" "$AT/self/features"
for f in "$HERE"/analysis/*.py "$HERE"/analysis/rates_history.json; do
  cp "$f" "$AT/analysis/$(basename "$f")" 2>/dev/null || true
done
git -C "$AT" init -q
git -C "$AT" symbolic-ref HEAD refs/heads/main
git -C "$AT" config user.email test@example.invalid
git -C "$AT" config user.name "audit-fixes test"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
# Claude Code's project directory for a launch cwd: every `/` and `.` becomes `-`.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/.' '--')"; }
source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"

MODEL="claude-sonnet-5"
SLUG_A="feat-a"
FD_A="$AT/self/features/$SLUG_A"
mkdir -p "$FD_A"
printf '# %s\n\nFixture feature for self/tests/audit-fixes.sh.\n\n```json\n{"slug": "%s", "branches": ["%s"], "plans": [], "session_window": {"from": "2026-01-01T00:00:00Z", "to": "2026-12-31T00:00:00Z"}}\n```\n' \
  "$SLUG_A" "$SLUG_A" "$SLUG_A" > "$FD_A/README.md"
git -C "$AT" add -A && git -C "$AT" commit -q -m "init"

SESSION_A="aaaaaaaa-0000-0000-0000-00000000000a"
AP="$(project_dir "$AT")"
mkdir -p "$AP"
session_line "$SESSION_A" "$AT" "$SLUG_A" "msg-a" "$MODEL" "2026-06-01T00:00:00.000Z" \
  100 500 0 0 0 > "$AP/$SESSION_A.jsonl"

( cd "$TMP" && HOME="$FAKE_HOME" python3 -B "$AT/analysis/capture_planning.py" --self "$SLUG_A" ) >/dev/null 2>&1
check "A0. the premise: planning.json is frozen and no report.json exists" \
  '[[ -f "$FD_A/planning.json" && ! -e "$FD_A/report.json" ]]'

out="$( cd "$TMP" && HOME="$FAKE_HOME" python3 -B "$AT/analysis/report.py" --self --all 2>&1 )"; rc=$?
check "A1. report.py --self --all exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
check "A2. it wrote the missing report.json and report.md" \
  '[[ -f "$FD_A/report.json" && -f "$FD_A/report.md" ]]'
check "A3. ... and said how many it filled in" 'grep -q "1 report(s) written" <<<"$out"'
check "A4. the trend table carries the feature's row" 'grep -q "^| $SLUG_A |" <<<"$out"'

cp "$FD_A/report.json" "$TMP/report-a.before.json"
out="$( cd "$TMP" && HOME="$FAKE_HOME" python3 -B "$AT/analysis/report.py" --self --all 2>&1 )"; rc=$?
check "A5. a second --all fills nothing (got $rc)" '[[ $rc -eq 0 ]] && grep -q "0 report(s) written" <<<"$out"'
check "A6. ... leaving the report byte-identical" 'cmp -s "$TMP/report-a.before.json" "$FD_A/report.json"'
check "A7. ... and still printing the row" 'grep -q "^| $SLUG_A |" <<<"$out"'

# ── B. run-batch.sh lints an inferred slug ────────────────────────────────────
REPO="$TMP/b"
BT="$REPO/agentTooling"
mkdir -p "$BT" "$REPO/plans/features" "$TMP/bin"
for f in run-batch.sh run-plans.sh run-verify.sh run-review.sh run-escalation-plan.sh \
         plan-runner-lib.sh plan-runner-roots.sh stamp-timing.sh check-plans.sh; do
  cp "$HERE/$f" "$BT/$f" 2>/dev/null || true
done
chmod +x "$BT"/*.sh 2>/dev/null || true

cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$TMP/claude.log"
printf '{"type":"result","total_cost_usd":0,"session_id":"stub"}\n'
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/plans/gate.sh"
chmod +x "$REPO/plans/gate.sh"

# ONE feature in the corpus, so the build pass resolves the slug with none given, and a
# window whose `to` is 13 minutes before its `from` — the shape `recovered-totals-stay-
# honest` carries, and what check 7 now catches.
SLUG_B="inferred"
FD_B="$REPO/plans/features/$SLUG_B"
mkdir -p "$FD_B/auto/incomplete"
printf '# %s\n\n```json\n{"slug": "%s", "branches": ["%s"], "plans": ["01-build-haiku"], "session_window": {"from": "2026-09-04T17:00:00Z", "to": "2026-09-04T16:46:31Z"}}\n```\n' \
  "$SLUG_B" "$SLUG_B" "$SLUG_B" > "$FD_B/README.md"
printf '# 01 — build\n\nfeature: agentTooling/%s\n' "$SLUG_B" > "$FD_B/auto/incomplete/01-build-haiku.md"

rm -f "$TMP/claude.log"
out="$( cd "$REPO" && agentTooling/run-batch.sh 2>&1 )"; rc=$?
check "B1. a batch with no slug argument exits non-zero on the lint (got $rc)" '[[ $rc -ne 0 ]]'
check "B2. it printed the check-plans banner" 'grep -q "BATCH: check-plans" <<<"$out"'
check "B3. ... FAILing the window bounds of the inferred feature" \
  'grep -q "FAIL  window bounds carry a zone and to follows from" <<<"$out"'
check "B4. ... naming the slug it inferred" 'grep -q "$SLUG_B" <<<"$out"'
check "B5. ... and stopping before the verify and review passes" \
  '! grep -q "BATCH 2/3" <<<"$out" && ! grep -q "BATCH 3/3" <<<"$out"'

echo
if (( fails > 0 )); then echo "audit-fixes: $fails assertion(s) FAILED"; exit 1; fi
echo "audit-fixes: all assertions passed"
