#!/usr/bin/env bash
set -uo pipefail

# End-to-end smoke test for the experiment harness. Must pass with no network and no
# money: every stage runs for real against a throwaway git repo, with the `null` method
# in place of a builder and a fake `claude` behind HARNESS_CLAUDE_BIN.
#
#   harness/tests/smoke.sh [--keep]
#
# What it proves, in the order the run does it: --dry-run touches nothing and names the
# branch it would create; a full run walks every stage and writes a ledger row with the
# review's escalation count, the rework's having run, and the acceptance verdict;
# SCORECARD.md renders; --from re-enters at a later stage off the saved state; and the
# worktree is removed at the end while its branch — the cost record — stays.
#
# The capture stage runs against a fake session, so it can price nothing. That is
# asserted as a recorded 0, not as a dollar figure.
#
# After the run it exercises the scaffolding: new-fixture.sh pins full commit ids and
# writes stubs that check-fixture.sh rejects; check-fixture.sh passes the real fixture;
# new-experiment.sh refuses a branch that exists and accepts an override; publish.sh
# commits the experiment directory on a results branch and opens the (fake) PR.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR_UNDER_TEST="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_TOOLING_UNDER_TEST="$(cd "$HARNESS_DIR_UNDER_TEST/.." && pwd)"

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

# ── Fixed names this test and the files it writes have to agree on ───────────
FIXTURE_NAME="smoke"
EXPERIMENT_NAME="smokeNull"
BRANCH_STEM="smoke"
EXPECTED_BRANCH="smokeNull"
EXPECTED_SLUG="smoke-null"
NULL_MARKER_RELPATH="plans/null-method-marker.md"
REWORK_MARKER_RELPATH="plans/rework-marker.md"
GATE_GREEN="all checks passed"
FAKE_PR_URL="https://example.invalid/pr/1"
SCAFFOLD_FIXTURE="smokeTwo"
SCAFFOLD_EXPERIMENT="smokeScaffold"
SCAFFOLD_STEM="smokeAgain"
RESULTS_BRANCH="smokeNullResults"

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d -t harness-smoke)"
REPO="$WORK/repo"
BIN="$WORK/bin"
TREE="$REPO-$EXPECTED_BRANCH"
SPEC_TREE="$REPO-fx-$FIXTURE_NAME"

cleanup() {
  if (( KEEP )); then
    printf '\n(kept: %s)\n' "$WORK"
    return
  fi
  [[ -d "$TREE" ]] && git -C "$REPO" worktree remove --force "$TREE" >/dev/null 2>&1
  [[ -d "$SPEC_TREE" ]] && git -C "$REPO" worktree remove --force "$SPEC_TREE" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== smoke: building a throwaway repo at $REPO ==="
mkdir -p "$REPO/plans" "$BIN"

cat > "$REPO/SPEC.md" <<'SPEC'
# Smoke spec

## 1. What the smoke feature is

Nothing. This document exists so a fixture can pin a spec commit in a repo that has one.
SPEC

cat > "$REPO/.gitignore" <<'IGNORE'
plans/gate-report*.txt
plans/**/*.stream.jsonl
plans/experiments/*/logs/
IGNORE

cat > "$REPO/plans/gate.sh" <<GATE
#!/usr/bin/env bash
# Throwaway gate: always green, and it writes the report the harness reads counts from.
REPORT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/gate-report.txt"
{
  echo "# Gate report"
  echo "## tests"
  echo "3 passed, 0 failed"
  echo ""
  echo "# VERDICT"
  echo "$GATE_GREEN"
} > "\$REPORT"
echo "=== gate: done — $GATE_GREEN ==="
exit 0
GATE

cat > "$REPO/plans/pr.sh" <<PRHOOK
#!/usr/bin/env bash
# Throwaway PR hook: records a URL per branch in a directory instead of calling a forge CLI.
mkdir -p "\${SMOKE_PR_DIR:?SMOKE_PR_DIR not set}"
echo "$FAKE_PR_URL" > "\$SMOKE_PR_DIR/\$(git branch --show-current)"
echo "  pr      $FAKE_PR_URL"
exit 0
PRHOOK
chmod +x "$REPO/plans/gate.sh" "$REPO/plans/pr.sh"

ln -s "$AGENT_TOOLING_UNDER_TEST" "$REPO/agentTooling"

# ── The fixture ──────────────────────────────────────────────────────────────
FIXTURE_DIR="$REPO/plans/experiments/fixtures/$FIXTURE_NAME"
mkdir -p "$FIXTURE_DIR/accept"

cat > "$FIXTURE_DIR/facts.md" <<'FACTS'
There is no toolchain here. The gate is always green and the feature is a marker file.
FACTS

cat > "$FIXTURE_DIR/review-brief.md" <<'BRIEF'
Check that the marker file exists and says which brief produced it.
BRIEF

cat > "$FIXTURE_DIR/accept/accept.py" <<ACCEPT
#!/usr/bin/env python3
"""Smoke acceptance probe: one check, one line, exit 0 pass / 1 fail."""
import sys
from pathlib import Path

MARKER = "$NULL_MARKER_RELPATH"

tree = Path(sys.argv[1])
ok = (tree / MARKER).is_file()
print(("PASS" if ok else "FAIL") + f" marker {MARKER} exists")
sys.exit(0 if ok else 1)
ACCEPT

cat > "$FIXTURE_DIR/README.md" <<'FIXREADME'
# smoke

The harness's own fixture: a feature that is one marker file, in a repo built by
`agentTooling/harness/tests/smoke.sh` and thrown away with it.
FIXREADME

# ── The experiment ───────────────────────────────────────────────────────────
EXPERIMENT_DIR="$REPO/plans/experiments/$EXPERIMENT_NAME"
mkdir -p "$EXPERIMENT_DIR"
cat > "$EXPERIMENT_DIR/README.md" <<'EXPREADME'
# smokeNull

The harness's own end-to-end run: the `smoke` fixture built by the `null` method.
EXPREADME

# ── The base commit ──────────────────────────────────────────────────────────
git -C "$REPO" init -q
git -C "$REPO" config user.email smoke@example.invalid
git -C "$REPO" config user.name "Harness Smoke"
git -C "$REPO" add -A
# A stale freeze on the base: a planning.json stamped long before any run's setup, as a
# reused branch from a failed attempt would carry. The capture stage must rebuild it
# (log line "recapturing") instead of reporting its $5 as this run's cost.
mkdir -p "$REPO/plans/features/$EXPECTED_SLUG"
cat > "$REPO/plans/features/$EXPECTED_SLUG/planning.json" <<'STALE'
{"captured_at": "2000-01-01T00:00:00+00:00", "cost": {"total": 5.0}, "sessions": [], "subagents": []}
STALE
git -C "$REPO" add -A
git -C "$REPO" commit -q -m "smoke base"
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"

cat > "$FIXTURE_DIR/fixture.json" <<FIXTURE
{
  "name": "$FIXTURE_NAME",
  "repo": {"path": "$REPO", "remote": "origin"},
  "base": "$BASE_SHA",
  "spec": {"repo": "$REPO", "commit": "$BASE_SHA", "path": "SPEC.md", "sections": ["1"]},
  "setup": [],
  "gate": {"command": "./plans/gate.sh", "green": "$GATE_GREEN", "minutes": 0},
  "branch_stem": "$BRANCH_STEM",
  "diff_lines": 1
}
FIXTURE

cat > "$EXPERIMENT_DIR/experiment.json" <<EXPERIMENT
{
  "name": "$EXPERIMENT_NAME",
  "fixtures": ["$FIXTURE_NAME"],
  "methods": ["null"],
  "repeats": 1,
  "stages": {"review": true, "rework": true, "accept": true},
  "noise_band_pct": 15,
  "prediction": "the harness completes every stage without a model and without a network",
  "compare_to": ""
}
EXPERIMENT

git -C "$REPO" add -A
git -C "$REPO" commit -q -m "smoke fixture and experiment"
# A bare remote, so the pushes the harness and publish.sh make have somewhere to land and
# `gh pr create` (the fake) is reached.
git init -q --bare "$WORK/remote.git"
git -C "$REPO" remote add origin "$WORK/remote.git"
git -C "$REPO" push -q -u origin HEAD 2>/dev/null

# ── The fake claude ──────────────────────────────────────────────────────────
# Reads the prompt the way the real one is called (on stdin — lib.sh never passes it
# as a positional, see harness_claude), acts on which preamble it was handed, and
# prints the result object the harness reads session_id and total_cost_usd from.
cat > "$BIN/claude" <<FAKECLAUDE
#!/usr/bin/env bash
prompt=""
if [ ! -t 0 ]; then prompt="\$(cat)"; fi

tree="\$(printf '%s' "\$prompt" | sed -n 's/^- Worktree: \`\([^\`]*\)\`.*/\1/p' | head -1)"

case "\$prompt" in
  *"# Harness review pass"*)
    findings="\$(printf '%s' "\$prompt" | grep -oE '/[^ \`]*/review/findings\.md' | head -1)"
    mkdir -p "\$(dirname "\$findings")"
    cat > "\$findings" <<'FINDINGS'
# Review findings — smoke-null

fixed: 0      escalated: 1

## Escalated
- id: R1
  file: $NULL_MARKER_RELPATH
  gap: the marker does not say the rework pass ran
  fix: write $REWORK_MARKER_RELPATH beside it

## Fixed
FINDINGS
    ;;
  *"# Harness rework pass"*)
    printf 'rework ran\n' > "\$tree/$REWORK_MARKER_RELPATH"
    ;;
esac

printf '{"type":"result","subtype":"success","is_error":false,"session_id":"smoke-%s","total_cost_usd":0,"result":"fake claude ok"}\n' "\$\$"
exit 0
FAKECLAUDE

cat > "$BIN/gh" <<FAKEGH
#!/usr/bin/env bash
# The read the harness performs — gh pr view <branch> --json url --jq .url — answered
# from a per-branch file, and the one write publish.sh performs — gh pr create — which
# records a URL for the current branch and prints it.
mkdir -p "\${SMOKE_PR_DIR:?SMOKE_PR_DIR not set}"
if [[ "\${1:-}" == "pr" && "\${2:-}" == "view" ]]; then
  [[ -f "\$SMOKE_PR_DIR/\${3:-}" ]] || exit 1
  cat "\$SMOKE_PR_DIR/\$3"
  exit 0
fi
if [[ "\${1:-}" == "pr" && "\${2:-}" == "create" ]]; then
  branch="\$(git branch --show-current)"
  echo "https://example.invalid/pr/\$branch" > "\$SMOKE_PR_DIR/\$branch"
  cat "\$SMOKE_PR_DIR/\$branch"
  exit 0
fi
exit 1
FAKEGH
chmod +x "$BIN/claude" "$BIN/gh"

export HARNESS_CLAUDE_BIN="$BIN/claude"
export HARNESS_GH_BIN="$BIN/gh"
export SMOKE_PR_DIR="$WORK/prs"

RUN="$HARNESS_DIR_UNDER_TEST/run.sh"
STATE_FILE="$EXPERIMENT_DIR/state/$EXPECTED_BRANCH.json"
RESULTS="$EXPERIMENT_DIR/results.jsonl"

# ── 1. Dry run ───────────────────────────────────────────────────────────────
echo ""
echo "=== smoke: --dry-run ==="
DRY_OUT="$WORK/dry-run.txt"
"$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --dry-run > "$DRY_OUT" 2>&1
dry_rc=$?
check "dry run exits 0" "(( $dry_rc == 0 ))"
check "dry run names the branch" "grep -q 'branch:  *$EXPECTED_BRANCH' '$DRY_OUT'"
check "dry run names the worktree it would create" "grep -q '$TREE' '$DRY_OUT'"
check "dry run created no worktree" "[[ ! -d '$TREE' ]]"
check "dry run created no branch" "! git -C '$REPO' show-ref --verify --quiet refs/heads/$EXPECTED_BRANCH"
check "dry run wrote no ledger" "[[ ! -f '$RESULTS' ]]"

# ── 2. The full run ──────────────────────────────────────────────────────────
echo ""
echo "=== smoke: full run ==="
FULL_OUT="$WORK/full-run.txt"
"$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --no-cleanup > "$FULL_OUT" 2>&1
full_rc=$?
if (( full_rc != 0 )); then
  echo "--- run output ---"
  cat "$FULL_OUT"
  echo "------------------"
fi
check "full run exits 0" "(( $full_rc == 0 ))"
check "state file exists" "[[ -f '$STATE_FILE' ]]"
for stage in setup brief method review rework accept capture record; do
  check "state records stage $stage" \
    "[[ -n \"\$(jq -r '.stages.$stage.outcome // empty' '$STATE_FILE' 2>/dev/null)\" ]]"
done
check "ledger has exactly one row" "[[ \$(wc -l < '$RESULTS') -eq 1 ]]"
check "row: review_escalated == 1" "[[ \$(jq -r '.review_escalated' '$RESULTS') == 1 ]]"
check "row: rework_ran == true" "[[ \$(jq -r '.rework_ran' '$RESULTS') == true ]]"
check "row: accept_pass == true" "[[ \$(jq -r '.accept_pass' '$RESULTS') == true ]]"
check "row: method_failed == false" "[[ \$(jq -r '.method_failed' '$RESULTS') == false ]]"
check "row: pr_url recorded" "[[ \$(jq -r '.pr_url' '$RESULTS') == '$FAKE_PR_URL' ]]"
check "row: capture priced nothing (0)" "jq -e '.cost_green_usd == 0' '$RESULTS' >/dev/null"
check "row: stale freeze on the branch was rebuilt, not reported" "jq -e '.cost_method_usd == 0' '$RESULTS' >/dev/null"
check "capture did not honour the stale freeze" "! grep -q 'already captured' '$EXPERIMENT_DIR/logs/$EXPECTED_BRANCH-capture.log'"
check "row: reported method cost carried (fake claude reports 0)" "jq -e '.cost_method_reported_usd == 0' '$RESULTS' >/dev/null"
check "row: gate counts captured" "[[ -n \"\$(jq -r '.gate_counts_green' '$RESULTS')\" ]]"
check "row: branch and slug" \
  "[[ \$(jq -r '.branch' '$RESULTS') == '$EXPECTED_BRANCH' && \$(jq -r '.slug' '$RESULTS') == '$EXPECTED_SLUG' ]]"
check "SCORECARD.md rendered" "[[ -s '$EXPERIMENT_DIR/SCORECARD.md' ]]"
check "SCORECARD carries the prediction" "grep -q 'without a network' '$EXPERIMENT_DIR/SCORECARD.md'"
check "brief was filled (no placeholders left)" \
  "! grep -q '@@' '$TREE/plans/features/$EXPECTED_SLUG/BRIEF.md'"
check "manifest window was closed at PR-open" \
  "! grep -q '\"to\": null' '$TREE/plans/features/$EXPECTED_SLUG/README.md'"
check "review wrote findings" "[[ -f '$TREE/plans/features/$EXPECTED_SLUG/review/findings.md' ]]"
check "rework marker written" "[[ -f '$TREE/$REWORK_MARKER_RELPATH' ]]"
check "review manifest exists" "[[ -f '$TREE/plans/features/$EXPECTED_SLUG-review/README.md' ]]"
check "rework manifest exists" "[[ -f '$TREE/plans/features/$EXPECTED_SLUG-rework/README.md' ]]"
check "no report.json left behind" \
  "[[ ! -f '$TREE/plans/features/$EXPECTED_SLUG/report.json' ]]"
check "worktree still present (--no-cleanup)" "[[ -d '$TREE' ]]"

# ── 2b. --from capture: freezes postdating their windows are honoured ────────
echo ""
echo "=== smoke: --from capture ==="
FROMCAP_OUT="$WORK/from-capture.txt"
# Seed a freeze stamped AFTER the rework window opened: it must be honoured, while
# the base repo's committed 2000-01-01 seed (never replaced — capture prices nothing
# against fake sessions) legitimately recaptures on every run.
cat > "$TREE/plans/features/$EXPECTED_SLUG-rework/planning.json" <<'FRESH'
{"captured_at": "2099-01-01T00:00:00+00:00", "cost": {"total": 5.0}, "sessions": [], "subagents": []}
FRESH
"$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --from capture --no-cleanup > "$FROMCAP_OUT" 2>&1
fromcap_rc=$?
check "--from capture exits 0" "(( $fromcap_rc == 0 ))"
check "--from capture appended a second row" "[[ \$(wc -l < '$RESULTS') -eq 2 ]]"
check "--from capture recaptured only the base repo's stale seed" \
  "[[ \$(grep -c 'recapturing' '$FROMCAP_OUT') -eq 1 ]]"
check "--from capture honoured the freeze postdating its window" \
  "! grep -q '$EXPECTED_SLUG-rework carries a freeze' '$FROMCAP_OUT'"
check "--from capture row carries the review counts from the state file" \
  "[[ \$(sed -n 2p '$RESULTS' | jq -r '.review_escalated') == 1 ]]"

# ── 3. Re-entry at a later stage, from the saved state ───────────────────────
echo ""
echo "=== smoke: --from rework ==="
FROM_OUT="$WORK/from-rework.txt"
# A killed attempt leaves its stage manifest's window open; re-open the rework
# window so the resume prices it into cost_lost_usd before resetting it.
REWORK_MANIFEST="$TREE/plans/features/$EXPECTED_SLUG-rework/README.md"
python3 - "$REWORK_MANIFEST" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
new, n = re.subn(r'"to": "[^"]*"', '"to": null', text, count=1)
assert n == 1, "no closed window to re-open in " + path
open(path, "w").write(new)
PY
rm -f "$TREE/plans/features/$EXPECTED_SLUG-rework/planning.json"
"$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --from rework --no-cleanup > "$FROM_OUT" 2>&1
from_rc=$?
if (( from_rc != 0 )); then
  echo "--- run output ---"
  cat "$FROM_OUT"
  echo "------------------"
fi
check "--from rework exits 0" "(( $from_rc == 0 ))"
check "--from rework skipped setup" "! grep -q 'stage setup' '$FROM_OUT'"
check "--from rework ran rework" "grep -q 'stage rework' '$FROM_OUT'"
check "--from rework appended a third row" "[[ \$(wc -l < '$RESULTS') -eq 3 ]]"
check "--from rework row carries gate counts from the state file" \
  "[[ -n \$(sed -n 3p '$RESULTS' | jq -r '.gate_counts_pr_open') ]]"
check "--from rework priced the orphaned open window into cost_lost_usd" \
  "sed -n 3p '$RESULTS' | jq -e 'has(\"cost_lost_usd\")' >/dev/null"
check "--from rework noted the orphan as an intervention" \
  "sed -n 3p '$RESULTS' | jq -r '.interventions[].what' | grep -q cost_lost_usd"
check "worktree kept (--no-cleanup)" "[[ -d '$TREE' ]]"
check "branch kept (it is the cost record)" \
  "git -C '$REPO' show-ref --verify --quiet refs/heads/$EXPECTED_BRANCH"

# ── 3b. Redoing a completed stage: its old freeze is stale, not this run's cost ─
echo ""
echo "=== smoke: --from rework again ==="
FROM2_OUT="$WORK/from-rework-again.txt"
# The fake sessions price nothing, so capture leaves no freeze behind; seed the
# stale freeze a real run's capture stage would have written for the redone stage.
cat > "$TREE/plans/features/$EXPECTED_SLUG-rework/planning.json" <<'STALE'
{"captured_at": "2000-01-01T00:00:00+00:00", "cost": {"total": 5.0}, "sessions": [], "subagents": []}
STALE
cat > "$TREE/plans/features/$EXPECTED_SLUG-review/planning.json" <<'FRESH'
{"captured_at": "2099-01-01T00:00:00+00:00", "cost": {"total": 5.0}, "sessions": [], "subagents": []}
FRESH
"$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --from rework > "$FROM2_OUT" 2>&1
from2_rc=$?
if (( from2_rc != 0 )); then
  echo "--- run output ---"
  cat "$FROM2_OUT"
  echo "------------------"
fi
check "second --from rework exits 0" "(( $from2_rc == 0 ))"
check "second --from rework appended a fourth row" "[[ \$(wc -l < '$RESULTS') -eq 4 ]]"
check "the redone stage's old freeze was recaptured, not reported" \
  "grep -q '$EXPECTED_SLUG-rework carries a freeze predating its manifest window' '$FROM2_OUT'"
check "the review stage did not re-run, so its freeze was kept" \
  "! grep -q '$EXPECTED_SLUG-review carries a freeze' '$FROM2_OUT'"
check "worktree removed after cleanup" "[[ ! -d '$TREE' ]]"

# ── 4. Scaffolding: new-fixture, check-fixture, new-experiment, publish ──────
echo ""
echo "=== smoke: scaffolding ==="
NEW_FIXTURE="$HARNESS_DIR_UNDER_TEST/new-fixture.sh"
CHECK_FIXTURE="$HARNESS_DIR_UNDER_TEST/check-fixture.sh"
NEW_EXPERIMENT="$HARNESS_DIR_UNDER_TEST/new-experiment.sh"
PUBLISH="$HARNESS_DIR_UNDER_TEST/publish.sh"
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
SCAFFOLD_FIXTURE_DIR="$REPO/plans/experiments/fixtures/$SCAFFOLD_FIXTURE"
SCAFFOLD_EXPERIMENT_DIR="$REPO/plans/experiments/$SCAFFOLD_EXPERIMENT"

NF_OUT="$WORK/new-fixture.txt"
"$NEW_FIXTURE" "$SCAFFOLD_FIXTURE" --repo "$REPO" --base HEAD --spec-repo "$REPO" --spec-ref HEAD \
  --spec-path SPEC.md --sections 1,9 --setup 'true' --gate-green "$GATE_GREEN" --consumer "$REPO" > "$NF_OUT" 2>&1
check "new-fixture exits 0" "(( $? == 0 ))"
check "new-fixture pinned base to the full commit id" "[[ \$(jq -r '.base' '$SCAFFOLD_FIXTURE_DIR/fixture.json') == '$HEAD_SHA' ]]"
check "new-fixture pinned spec to the full commit id" "[[ \$(jq -r '.spec.commit' '$SCAFFOLD_FIXTURE_DIR/fixture.json') == '$HEAD_SHA' ]]"
check "new-fixture recorded setup and sections" \
  "[[ \$(jq -c '.setup' '$SCAFFOLD_FIXTURE_DIR/fixture.json') == '[\"true\"]' && \$(jq -c '.spec.sections' '$SCAFFOLD_FIXTURE_DIR/fixture.json') == '[\"1\",\"9\"]' ]]"
check "new-fixture warned about the missing section 9" "grep -q 'section 9' '$NF_OUT'"
check "new-fixture stubs carry @@TODO@@" "grep -q '@@TODO@@' '$SCAFFOLD_FIXTURE_DIR/facts.md' && grep -q '@@TODO@@' '$SCAFFOLD_FIXTURE_DIR/review-brief.md'"
check "new-fixture stub accept.py exits 1" "! python3 '$SCAFFOLD_FIXTURE_DIR/accept/accept.py' '$REPO' >/dev/null 2>&1"
check "new-fixture refuses an existing fixture" "! '$NEW_FIXTURE' '$SCAFFOLD_FIXTURE' --repo '$REPO' --base HEAD --spec-repo '$REPO' --spec-ref HEAD --spec-path SPEC.md --consumer '$REPO' >/dev/null 2>&1"
check "new-fixture refuses a ref that does not resolve" "! '$NEW_FIXTURE' smokeThree --repo '$REPO' --base no-such-ref --spec-repo '$REPO' --spec-ref HEAD --spec-path SPEC.md --consumer '$REPO' >/dev/null 2>&1"
check "new-fixture refuses a spec path absent at the commit" "! '$NEW_FIXTURE' smokeThree --repo '$REPO' --base HEAD --spec-repo '$REPO' --spec-ref HEAD --spec-path NOPE.md --consumer '$REPO' >/dev/null 2>&1"

CF_OUT="$WORK/check-fixture-stub.txt"
"$CHECK_FIXTURE" "$SCAFFOLD_FIXTURE" --consumer "$REPO" > "$CF_OUT" 2>&1
check "check-fixture rejects the stubbed fixture" "(( $? != 0 ))"
check "check-fixture names the stub" "grep -q 'still carries the stub' '$CF_OUT' && grep -q 'still the stub' '$CF_OUT'"
"$CHECK_FIXTURE" "$FIXTURE_NAME" --consumer "$REPO" > "$WORK/check-fixture-real.txt" 2>&1
check "check-fixture passes the real fixture" "(( $? == 0 ))"

NE_OUT="$WORK/new-experiment-collision.txt"
"$NEW_EXPERIMENT" "$SCAFFOLD_EXPERIMENT" --fixtures "$FIXTURE_NAME" --methods null \
  --prediction 'scaffold' --consumer "$REPO" > "$NE_OUT" 2>&1
check "new-experiment refuses a branch that already exists" "(( $? != 0 ))"
check "new-experiment names the colliding branch" "grep -q '$EXPECTED_BRANCH' '$NE_OUT'"
check "new-experiment wrote nothing on refusal" "[[ ! -e '$SCAFFOLD_EXPERIMENT_DIR' ]]"
check "new-experiment refuses a stubbed fixture" "! '$NEW_EXPERIMENT' smokeStub --fixtures '$SCAFFOLD_FIXTURE' --methods null --prediction p --override $SCAFFOLD_FIXTURE=fresh --consumer '$REPO' >/dev/null 2>&1"
check "new-experiment refuses an unknown method" "! '$NEW_EXPERIMENT' smokeStub --fixtures '$FIXTURE_NAME' --methods nosuch --prediction p --override $FIXTURE_NAME=fresh --consumer '$REPO' >/dev/null 2>&1"
check "new-experiment requires a prediction" "! '$NEW_EXPERIMENT' smokeStub --fixtures '$FIXTURE_NAME' --methods null --override $FIXTURE_NAME=fresh --consumer '$REPO' >/dev/null 2>&1"
"$NEW_EXPERIMENT" "$SCAFFOLD_EXPERIMENT" --fixtures "$FIXTURE_NAME" --methods null --repeats 2 \
  --prediction 'scaffold' --override "$FIXTURE_NAME=$SCAFFOLD_STEM" --consumer "$REPO" > "$WORK/new-experiment.txt" 2>&1
check "new-experiment exits 0 with an override" "(( $? == 0 ))"
check "new-experiment wrote the override" "[[ \$(jq -r '.branch_stem_override.$FIXTURE_NAME' '$SCAFFOLD_EXPERIMENT_DIR/experiment.json') == '$SCAFFOLD_STEM' ]]"
check "new-experiment wrote the prediction and repeats" "[[ \$(jq -r '.prediction' '$SCAFFOLD_EXPERIMENT_DIR/experiment.json') == scaffold && \$(jq -r '.repeats' '$SCAFFOLD_EXPERIMENT_DIR/experiment.json') == 2 ]]"
check "new-experiment README lists the branches" "grep -q '${SCAFFOLD_STEM}Null2' '$SCAFFOLD_EXPERIMENT_DIR/README.md'"
"$RUN" "$SCAFFOLD_EXPERIMENT_DIR" --consumer "$REPO" --dry-run > "$WORK/scaffold-dry-run.txt" 2>&1
check "scaffolded experiment dry-runs" "(( $? == 0 ))"
check "scaffolded experiment resolves the overridden branch" "grep -q 'branch:  *${SCAFFOLD_STEM}Null1' '$WORK/scaffold-dry-run.txt'"

PUB_OUT="$WORK/publish.txt"
"$PUBLISH" "$EXPERIMENT_DIR" --branch "$RESULTS_BRANCH" --consumer "$REPO" > "$PUB_OUT" 2>&1
check "publish exits 0" "(( $? == 0 ))"
check "publish created the results branch" "[[ \$(git -C '$REPO' branch --show-current) == '$RESULTS_BRANCH' ]]"
check "publish committed the run count" "[[ \$(git -C '$REPO' log -1 --format=%s) == '$EXPERIMENT_NAME: run 4 results' ]]"
check "publish committed the ledger and state" "git -C '$REPO' ls-files --error-unmatch plans/experiments/$EXPERIMENT_NAME/results.jsonl plans/experiments/$EXPERIMENT_NAME/state/$EXPECTED_BRANCH.json >/dev/null 2>&1"
check "publish did not commit logs" "! git -C '$REPO' ls-files --error-unmatch plans/experiments/$EXPERIMENT_NAME/logs >/dev/null 2>&1"
check "publish opened the PR" "grep -q 'PR: https://example.invalid/pr/$RESULTS_BRANCH' '$PUB_OUT'"
"$PUBLISH" "$EXPERIMENT_DIR" --consumer "$REPO" > "$WORK/publish-again.txt" 2>&1
check "publish again is a no-op on the same branch" "(( $? == 0 )) && grep -q 'nothing new' '$WORK/publish-again.txt' && grep -q 'already open' '$WORK/publish-again.txt'"

echo ""
if (( failures > 0 )); then
  echo "=== smoke: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== smoke: all checks passed ==="
