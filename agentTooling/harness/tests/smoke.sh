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
# commits the experiment directory on a results branch and opens the (fake) PR. Then the
# repository rule (a fixture's repository is always the consumer: no `repo` block, or one
# naming the consumer's own URL; one naming another repository is refused; its spec comes
# from the consumer unless `spec.url` names an external repository, resolved by an
# override, a root or a clone, or the legacy `spec.repo` path, with a warning; the harness
# refuses to be driven from another checkout than the consumer's own agentTooling/,
# HARNESS_TEST_EXTERNAL_DRIVER being this test's seam) and a pinned arm (an
# experiment naming an agentTooling commit per arm: the worktree's vendored copy replaced
# and committed before the method runs, the arm in the ledger row and the scorecard). Last,
# the two ways a pin goes wrong: a cell whose pin died after its worktree was added is
# pinned, once, by the re-run (and by no later one), and a malformed `agent_tooling` is
# refused instead of running every cell unpinned. And the control arm: a cell whose base
# already vendors the arm's commit changes nothing when pinned, and still gets its pin
# commit — empty, once.
#
# Last of all, program cells (harness/README.md → "The program row"): a program of two
# fixtures, the second depending on the first, run by an orchestrator the fake `claude`
# plays (a new session, then a resume per feature that forks to a new session id, then the
# record), with an implementer per feature that commits and opens its PR through the fake
# forge against the base the brief names. Asserted: the two PRs and the second's base being
# the first's branch, the pushed program branch (no PR), the kind=program row and its
# figures, the scorecard's Programs section, the worktrees gone, and the refusal of an
# unpinned program (its agentTooling/ is a symlink) and of an arm below the version floor.
# Then the same program with feature 1's implementer failing (feature 2 still runs), `--only`
# selecting only the program cell, `--from record` re-appending a row from state, a dry run
# that creates nothing, and direct tests of harness_check_program_floor,
# harness_program_check and program_cost.py (a fabricated transcript tree).

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

# An explicit template under $TMPDIR, never `mktemp -d -t <prefix>`: GNU mktemp refuses
# a template with no X's, and WORK was then empty — the test wrote its repo, its fake
# binaries (`/bin/claude`) and its logs at the filesystem root on Linux, and
# `rm -rf ""` cleaned nothing up (self/PROJECT_FACTS.md → "Conventions and gotchas").
WORK="$(mktemp -d "${TMPDIR:-/tmp}/harness-smoke.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
REPO="$WORK/repo"
REMOTE_URL="$WORK/remote.git"
BIN="$WORK/bin"
TREE="$REPO-$EXPECTED_BRANCH"
SPEC_TREE="$REPO-fx-$FIXTURE_NAME"
# The pinned-arm run: one more experiment over the same fixture, on a fresh stem, under
# this checkout's HEAD as the arm `head`.
PIN_EXPERIMENT="smokePin"
PIN_STEM="smokePinned"
PIN_ARM="head"
PIN_BRANCH="smokePinnedNullHead"
PIN_TREE="$REPO-$PIN_BRANCH"
PIN_SUBJECT_PREFIX="EXPERIMENT ARM (revert before merge): pin agentTooling to upstream"
# The resume run: a pin that dies after the worktree is added, then the same cell re-run.
RESUME_EXPERIMENT="smokeResume"
RESUME_STEM="smokeResumed"
RESUME_BRANCH="smokeResumedNullHead"
RESUME_TREE="$REPO-$RESUME_BRANCH"
RESUME_PIN_COMMITS_EXPECTED=1
# The control run: a fixture whose base already vendors the arm's agentTooling commit, so
# the pin changes nothing and its commit is empty.
CONTROL_FIXTURE="smokeControl"
CONTROL_EXPERIMENT="smokeControlRun"
CONTROL_STEM="smokeControlled"
CONTROL_BRANCH="smokeControlledNullHead"
CONTROL_TREE="$REPO-$CONTROL_BRANCH"
CONTROL_PREP_BRANCH="smokeControlPrep"
CONTROL_PREP_TREE="$WORK/control-prep"
CONTROL_PIN_COMMITS_EXPECTED=1
# The repository rule (an experiment runs from, and lives on, the repository it measures):
# a fixture naming the consumer's own URL, one naming another repository, a spec that lives
# in an external repository (reached by `spec.url`, or by the legacy `spec.repo` path), and a
# consumer whose agentTooling/ is not the harness being run.
OWN_URL_FIXTURE="smokeOwnUrl"
OWN_URL_STEM="smokeOwn"
OWN_URL_EXPERIMENT="smokeOwnUrlRun"
OTHER_REPO_URL="https://example.invalid/acme/other.git"
OTHER_REPO_IDENTITY="acme/other"
OTHER_FIXTURE="smokeOther"
OTHER_STEM="smokeOtherStem"
OTHER_EXPERIMENT="smokeOtherRun"
OTHER_PROGRAM="smokeOtherProg"
OTHER_PROGRAM_EXPERIMENT="smokeOtherProgRun"
SPEC_REMOTE_URL="$WORK/specremote.git"
SPEC_CHECKOUT="$WORK/specrepo"
SPEC_REPO_NAME="specremote"
SPEC_REPO_ENV_KEY="HARNESS_REPO_DIR_SPECREMOTE"
EXT_SPEC_FIXTURE="smokeExtSpec"
EXT_SPEC_STEM="smokeExt"
EXT_SPEC_EXPERIMENT="smokeExtSpecRun"
LEGACY_SPEC_FIXTURE="smokeLegacy"
FOREIGN_CONSUMER="$WORK/foreign-consumer"
OWN_DRIVER_MESSAGE="measured repository's own agentTooling/"
OWN_DRIVER_UPDATE_HINT="agentTooling/update.sh"
OTHER_REPO_REMEDY="run it there"
# A fixture's `repo.path` is checked on its own, beside any `repo.url`.
PATH_OWN_FIXTURE="smokePathOwn"
PATH_OWN_STEM="smokePathOwnStem"
PATH_OTHER_FIXTURE="smokePathOther"
PATH_OTHER_STEM="smokePathOtherStem"
PATH_OTHER_CHECKOUT="$WORK/pathother"
PATH_MISSING_FIXTURE="smokePathMissing"
PATH_MISSING_STEM="smokePathMissingStem"
PATH_MISSING_DIR="$WORK/no-such-checkout"
PATH_STALE_FIXTURE="smokePathStale"
PATH_STALE_STEM="smokePathStaleStem"
CONSUMER_SPEC_LABEL="from the consumer's own checkout"
# An experiment whose agent_tooling is not an object of <label>: <sha>.
BAD_ARMS_EXPERIMENT="smokeBadArms"
NO_REVIEW_EXPERIMENT="smokeNoReview"
BAD_ARMS_VALUE="abc"
BAD_ARMS_SHAPE="agent_tooling in .* must be an object of <label>: <full sha>"
# Program cells: two fixtures off the smoke one, a program over them, three experiments.
# The first line of every implementer brief the fake orchestrator writes; the fake
# `claude` knows an implementer prompt by it.
PROGRAM_IMPL_FIRST_LINE="SMOKE PROGRAM IMPLEMENTER BRIEF"
PROGRAM_NAME="smokeProg"
PROGRAM_STEM_NAME="smokeProg"
PROGRAM_FIXTURE_ONE="smokeAlpha"
PROGRAM_FIXTURE_TWO="smokeBeta"
PROGRAM_ARM="head"
PROGRAM_DEFAULT_PR_BASE="main"
PROGRAM_METHOD_NAME="orchestrator"
PROGRAM_MARKER_GLOB="program-marker-*.txt"
# Experiment 1: the program alone, pinned. Branches follow the rulings:
# <programStem>Orchestrator<Arm> and <fixtureStem><ProgramStem><Arm>.
PROGRAM_EXPERIMENT="smokeProgRun"
PROGRAM_BRANCH_ONE="smokeProgOrchestratorHead"
PROGRAM_SLUG_ONE="smoke-prog-orchestrator-head"
PROGRAM_FEATURE_BRANCH_A="smokeAlphaSmokeProgHead"
PROGRAM_FEATURE_BRANCH_B="smokeBetaSmokeProgHead"
PROGRAM_FEATURE_SLUG_A="smoke-alpha-smoke-prog-head"
PROGRAM_FEATURE_SLUG_B="smoke-beta-smoke-prog-head"
# Experiment 2: the same program, unpinned (the tree's agentTooling/ is a symlink).
PROGRAM_BARE_EXPERIMENT="smokeProgBare"
PROGRAM_BARE_STEM="smokeBare"
PROGRAM_BARE_BRANCH="smokeBareOrchestrator"
# Experiment 3: an ordinary cell beside the program, the program's feature 1 failing.
PROGRAM_MIX_EXPERIMENT="smokeProgMix"
PROGRAM_MIX_STEM="smokeFail"
PROGRAM_MIX_BRANCH="smokeFailOrchestratorHead"
PROGRAM_MIX_FEATURE_BRANCH_A="smokeAlphaSmokeFailHead"
PROGRAM_MIX_FEATURE_BRANCH_B="smokeBetaSmokeFailHead"
PROGRAM_MIX_CELL_BRANCH="smokeAlphaNullHead"
# Experiment 4: an arm below the version floor.
PROGRAM_FLOOR_EXPERIMENT="smokeProgFloor"
PROGRAM_FLOOR_ARM="old"
PROGRAM_FLOOR_ADDED_FILE="templates/plans/ORCHESTRATOR_BRIEF.md"
# The scorecard heading and the orchestrator calls the fake logs.
PROGRAM_SCORECARD_HEADING="## Programs"
PROGRAM_MIN_ORCHESTRATOR_SESSIONS=2
# The full run's fabricated billed responses, and what the fake implementer reports claude
# itself spent (below what the capture prices, so nothing is flagged unpriced).
PROGRAM_PRICED_INPUT_TOKENS=100000
PROGRAM_PRICED_OUTPUT_TOKENS=10000
PROGRAM_PRICED_REPORTED_USD="0.01"
# Row arithmetic is compared to this many decimals (the row rounds to 4); the program row's
# and the priced ordinary cell's checks share it.
ARITHMETIC_TOLERANCE="0.0002"
# An ordinary (non-program) cell run under the priced HOME: the `direct` method, whose fake
# implementer builds the marker and opens its PR, pinned to this checkout so the capture runs
# from a real vendored copy. Branch = stem + Direct + Head.
PRICED_CELL_EXPERIMENT="smokePricedCell"
PRICED_CELL_STEM="smokePricedCell"
PRICED_CELL_METHOD="direct"
PRICED_CELL_BRANCH="smokePricedCellDirectHead"
PRICED_CELL_SLUG="smoke-priced-cell-direct-head"
# What the priced cell's fake implementer reports claude itself spent (below what the capture
# prices, so nothing is flagged unpriced).
PRICED_CELL_REPORTED_USD="0.01"
# The capture's own lines that mean a session was not claimed or not priced.
PRICED_CELL_UNCLAIMED_PATTERN="cannot claim|launched_elsewhere"
PRICED_CELL_UNPRICED_PATTERN="claude reported"
# The no-review run: `stages {review: false}` as a whole run (the null method, pinned).
NO_REVIEW_RUN_EXPERIMENT="smokeNoReviewRun"
NO_REVIEW_RUN_STEM="smokeNoReviewRun"
NO_REVIEW_RUN_BRANCH="smokeNoReviewRunNullHead"
NO_REVIEW_RUN_SLUG="smoke-no-review-run-null-head"
# The unpriced run: an implementer that reports spend the capture cannot find, and a feature
# whose brief is never written.
PROGRAM_UNPRICED_EXPERIMENT="smokeProgUnpriced"
PROGRAM_UNPRICED_STEM="smokeUnpriced"
PROGRAM_UNPRICED_BRANCH="smokeUnpricedOrchestratorHead"
PROGRAM_UNPRICED_FEATURE_BRANCH_A="smokeAlphaSmokeUnpricedHead"
PROGRAM_UNPRICED_REPORTED_USD="0.75"
# program_cost.py's fabricated transcripts.
COST_SESSION_ONE="smoke-orch-one"
COST_SESSION_TWO="smoke-orch-two"
COST_SESSION_MISSING="smoke-orch-missing"
COST_EARLY="2030-06-01T10:00:00Z"
COST_LATE="2030-06-01T12:00:00Z"
COST_BETWEEN="2030-06-01T11:00:00Z"
COST_WINDOW_FROM="2030-06-01T09:00:00Z"
COST_WINDOW_TO="2030-06-01T13:00:00Z"
COST_INPUT_TOKENS=1000000
COST_OUTPUT_TOKENS=100000
COST_OUTPUT_SHARE="0.1"
COST_USAGE_EXIT=2

cleanup() {
  if (( KEEP )); then
    printf '\n(kept: %s)\n' "$WORK"
    return
  fi
  [[ -d "$TREE" ]] && git -C "$REPO" worktree remove --force "$TREE" >/dev/null 2>&1
  [[ -d "$PIN_TREE" ]] && git -C "$REPO" worktree remove --force "$PIN_TREE" >/dev/null 2>&1
  [[ -d "$RESUME_TREE" ]] && git -C "$REPO" worktree remove --force "$RESUME_TREE" >/dev/null 2>&1
  [[ -d "$CONTROL_TREE" ]] && git -C "$REPO" worktree remove --force "$CONTROL_TREE" >/dev/null 2>&1
  [[ -d "$CONTROL_PREP_TREE" ]] && git -C "$REPO" worktree remove --force "$CONTROL_PREP_TREE" >/dev/null 2>&1
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

# The fixture names no repository: it measures the consumer it lives on, and its spec is
# taken from the consumer's own checkout (no `repo` block, no `spec.url`). The bare remote
# below is the consumer's origin; later sections add fixtures that name it, another
# repository, or an external spec repository.
cat > "$FIXTURE_DIR/fixture.json" <<FIXTURE
{
  "name": "$FIXTURE_NAME",
  "base": "$BASE_SHA",
  "spec": {"commit": "$BASE_SHA", "path": "SPEC.md", "sections": ["1"]},
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
# the forge's `pr-open` (the fake) is reached.
git init -q --bare "$REMOTE_URL"
git -C "$REPO" remote add origin "$REMOTE_URL"
git -C "$REPO" push -q -u origin HEAD 2>/dev/null

# ── The fake claude ──────────────────────────────────────────────────────────
# Reads the prompt the way the real one is called (on stdin — lib.sh never passes it
# as a positional, see harness_claude), acts on which preamble it was handed, and
# prints the result object the harness reads session_id and total_cost_usd from.
cat > "$BIN/claude" <<FAKECLAUDE
#!/usr/bin/env bash
prompt=""
if [ ! -t 0 ]; then prompt="\$(cat)"; fi

# SMOKE_ARGV_LOG, when set, collects one line of argv per call, so a test can assert which
# flags (--effort) reached the seam. The fake accepts every flag and ignores it.
if [ -n "\${SMOKE_ARGV_LOG:-}" ]; then printf '%s\n' "\$*" >> "\$SMOKE_ARGV_LOG"; fi

tree="\$(printf '%s' "\$prompt" | sed -n 's/^- Worktree: \`\([^\`]*\)\`.*/\1/p' | head -1)"

# A program cell's orchestrator turns and implementers are another script's business
# (program-claude, written below); it gets the prompt back on stdin and the same argv.
case "\$prompt" in
  "# Harness program"*|"$PROGRAM_IMPL_FIRST_LINE"*) exec "$BIN/program-claude" "\$@" <<<"\$prompt" ;;
esac

cost=0      # what this call reports as total_cost_usd
bills=0     # whether this call leaves a priced transcript (SMOKE_PRICED_TRANSCRIPTS=1)
case "\$prompt" in
  "feature: "*"You are the sole implementer"*)
    # An ordinary cell's \`direct\` implementer: the marker the fixture's probe looks for,
    # committed, pushed, and its PR opened through the fake forge.
    branch="\$(git branch --show-current)"
    printf 'built by the fake direct implementer\n' > "$NULL_MARKER_RELPATH"
    git add -A && git commit -q -m "build \$branch"
    git push -q -u origin "\$branch" 2>/dev/null
    body="\$(mktemp "\${TMPDIR:-/tmp}/smoke-pr-body.XXXXXX")"
    printf 'one arm of an experiment — do not merge until it picks a winner\n' > "\$body"
    "\$HARNESS_FORGE_BIN" pr-open "\$branch" main "smoke: \$branch" "\$body" >/dev/null
    rm -f "\$body"
    cost="\${SMOKE_IMPL_REPORTED_USD:-0}"
    bills=1
    ;;
  *"# Harness review pass"*)
    bills=1
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
    bills=1
    printf 'rework ran\n' > "\$tree/$REWORK_MARKER_RELPATH"
    ;;
esac

# With SMOKE_PRICED_TRANSCRIPTS=1 the call leaves what a real session would: one billed
# response in \$HOME/.claude/projects/<the cwd's project directory>/<session>.jsonl, recording
# the real cwd and branch, so capture_planning.py has to claim the harness's own tree to price it.
if [ "\${SMOKE_PRICED_TRANSCRIPTS:-0}" = 1 ] && [ "\$bills" = 1 ]; then
  sid="smoke-\$\$"
  project="\$(printf '%s' "\$PWD" | tr '/.' '--')"
  mkdir -p "\$HOME/.claude/projects/\$project"
  jq -c -n --arg sid "\$sid" --arg b "\$(git branch --show-current)" --arg cwd "\$PWD" \
    --arg ts "\$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" --arg model "\$SMOKE_COST_MODEL" \
    --argjson i "\$SMOKE_COST_INPUT_TOKENS" --argjson o "\$SMOKE_COST_OUTPUT_TOKENS" \
    '{type: "assistant", sessionId: \$sid, timestamp: \$ts, gitBranch: \$b, cwd: \$cwd,
      message: {id: (\$sid + "-m1"), model: \$model, usage: {input_tokens: \$i, output_tokens: \$o}}}' \
    >> "\$HOME/.claude/projects/\$project/\$sid.jsonl"
  # The stage's manifest window closes after this call: stay clear of its whole-second end.
  sleep 1
fi

printf '{"type":"result","subtype":"success","is_error":false,"session_id":"smoke-%s","total_cost_usd":%s,"result":"fake claude ok"}\n' "\$\$" "\$cost"
exit 0
FAKECLAUDE

cat > "$BIN/forge.sh" <<FAKEFORGE
#!/usr/bin/env bash
# The forge adapter's two verbs the harness uses (forge.sh): \`pr-find <head>\` — the
# open PR's url for that branch from a per-branch file, or nothing — and
# \`pr-open <head> <base> <title> <body-file>\`, which records a url for the head and
# prints it. The real one asks GitHub's REST API through \`gh api\`.
mkdir -p "\${SMOKE_PR_DIR:?SMOKE_PR_DIR not set}"
case "\${1:-}" in
  pr-find)
    [[ -f "\$SMOKE_PR_DIR/\${2:-}" ]] && cat "\$SMOKE_PR_DIR/\$2"
    exit 0 ;;
  pr-open)
    [[ -f "\${5:-}" ]] || { echo "  forge     no body file" >&2; exit 1; }
    echo "https://example.invalid/pr/\$2" > "\$SMOKE_PR_DIR/\$2"
    # The base the PR was opened against, for the program cell's pr_base assertions.
    echo "\${3:-}" > "\$SMOKE_PR_DIR/\$2.base"
    cat "\$SMOKE_PR_DIR/\$2"
    exit 0 ;;
esac
exit 2
FAKEFORGE
chmod +x "$BIN/claude" "$BIN/forge.sh"

export HARNESS_CLAUDE_BIN="$BIN/claude"
export HARNESS_FORGE_BIN="$BIN/forge.sh"
export SMOKE_PR_DIR="$WORK/prs"
# The upstream an arm is pinned to: this checkout itself (a local checkout is its own
# resolution), so the pinned run below needs no network.
export HARNESS_AGENT_TOOLING_URL="$AGENT_TOOLING_UNDER_TEST"
# The test seam (lib.sh): this test drives throwaway consumers from agentTooling's own
# checkout. Only the external-driver section unsets it, to see the refusal.
export HARNESS_TEST_EXTERNAL_DRIVER=1

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
check "dry run's repository is the consumer (the fixture names none)" "grep -q 'repo:  *$REPO\$' '$DRY_OUT'"
check "dry run says the spec worktree comes from the consumer's own checkout" "grep 'spec worktree:' '$DRY_OUT' | grep -qF \"$CONSUMER_SPEC_LABEL\""
check "the smoke fixture has no repo block and no spec.url" \
  "jq -e 'has(\"repo\") | not' '$FIXTURE_DIR/fixture.json' >/dev/null && jq -e '.spec | has(\"url\") | not' '$FIXTURE_DIR/fixture.json' >/dev/null"
check "dry run names the worktree it would create" "grep -q '$TREE' '$DRY_OUT'"
check "dry run names the forge seam for the PR check" "grep -q 'forge.sh pr-find $EXPECTED_BRANCH' '$DRY_OUT'"
check "dry run created no worktree" "[[ ! -d '$TREE' ]]"
check "dry run created no branch" "! git -C '$REPO' show-ref --verify --quiet refs/heads/$EXPECTED_BRANCH"
check "dry run wrote no ledger" "[[ ! -f '$RESULTS' ]]"
check "dry run shows no --effort when HARNESS_EFFORT is unset" "! grep -q -- '--effort' '$DRY_OUT'"

# HARNESS_EFFORT: set, the dry run shows the flag on the method, review and rework lines.
EFFORT_LEVEL=max
EFFORT_BAD_LEVEL=huge
EFFORT_DRY_OUT="$WORK/dry-run-effort.txt"
HARNESS_EFFORT="$EFFORT_LEVEL" "$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --dry-run > "$EFFORT_DRY_OUT" 2>&1
check "dry run under HARNESS_EFFORT=$EFFORT_LEVEL exits 0" "(( $? == 0 ))"
check "... shows --effort $EFFORT_LEVEL on the method line" \
  "grep -E 'methods/.*/run\.sh' '$EFFORT_DRY_OUT' | grep -q -- '--effort $EFFORT_LEVEL'"
check "... on the review line" "grep 'review preamble' '$EFFORT_DRY_OUT' | grep -q -- '--effort $EFFORT_LEVEL'"
check "... and on the rework line" "grep 'rework preamble' '$EFFORT_DRY_OUT' | grep -q -- '--effort $EFFORT_LEVEL'"
EFFORT_BAD_OUT="$WORK/dry-run-effort-bad.txt"
HARNESS_EFFORT="$EFFORT_BAD_LEVEL" "$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --dry-run > "$EFFORT_BAD_OUT" 2>&1
effort_bad_rc=$?
check "HARNESS_EFFORT=$EFFORT_BAD_LEVEL makes the dry run exit non-zero" "(( $effort_bad_rc != 0 ))"
check "... naming the value and the levels" \
  "grep -q \"$EFFORT_BAD_LEVEL\" '$EFFORT_BAD_OUT' && grep -q 'low medium high xhigh max' '$EFFORT_BAD_OUT'"

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
check "row: effort is null when HARNESS_EFFORT is unset" "jq -e '.effort == null' '$RESULTS' >/dev/null"
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
check "the spec worktree is <consumer>-fx-<fixture> and exists" "[[ -d '$SPEC_TREE' ]]"
check "... it was added from the consumer (its common git dir is the consumer's)" \
  "[[ \$(git -C '$SPEC_TREE' rev-parse --path-format=absolute --git-common-dir) == '$REPO/.git' ]]"
check "... detached at the fixture's spec commit, holding SPEC.md" \
  "[[ \$(git -C '$SPEC_TREE' rev-parse HEAD) == '$BASE_SHA' && -f '$SPEC_TREE/SPEC.md' ]]"
check "... and the consumer lists it as a worktree" "git -C '$REPO' worktree list --porcelain | grep -qx 'worktree $SPEC_TREE'"

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
EFFORT_ARGV_LOG="$WORK/effort-argv.log"
SMOKE_ARGV_LOG="$EFFORT_ARGV_LOG" HARNESS_EFFORT="$EFFORT_LEVEL" \
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
check "run under HARNESS_EFFORT=$EFFORT_LEVEL: the claude call carried --effort $EFFORT_LEVEL" \
  "grep -q -- '--effort $EFFORT_LEVEL' '$EFFORT_ARGV_LOG'"
check "... and its row records effort == $EFFORT_LEVEL" \
  "[[ \$(sed -n 4p '$RESULTS' | jq -r '.effort') == '$EFFORT_LEVEL' ]]"
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

NO_REPO_FIXTURE="smokeNoRepoArgs"
"$NEW_FIXTURE" "$NO_REPO_FIXTURE" --base HEAD --spec-ref HEAD --spec-path SPEC.md \
  --setup 'true' --gate-green "$GATE_GREEN" --consumer "$REPO" > "$WORK/new-fixture-norepo.txt" 2>&1
check "new-fixture with no --repo and no --spec-repo exits 0" "(( $? == 0 ))"
check "... writes no repo block and no spec.url" \
  "jq -e 'has(\"repo\") | not' '$REPO/plans/experiments/fixtures/$NO_REPO_FIXTURE/fixture.json' >/dev/null && jq -e '.spec | has(\"url\") | not' '$REPO/plans/experiments/fixtures/$NO_REPO_FIXTURE/fixture.json' >/dev/null"
"$NEW_FIXTURE" smokeOtherRepoArg --repo "$OTHER_REPO_URL" --base HEAD --spec-ref HEAD --spec-path SPEC.md --consumer "$REPO" > "$WORK/new-fixture-other.txt" 2>&1
check "new-fixture refuses a --repo that is not the consumer" "(( $? != 0 )) && grep -q '$OTHER_REPO_IDENTITY' '$WORK/new-fixture-other.txt' && grep -q '$OTHER_REPO_REMEDY' '$WORK/new-fixture-other.txt'"

CF_OUT="$WORK/check-fixture-stub.txt"
"$CHECK_FIXTURE" "$SCAFFOLD_FIXTURE" --consumer "$REPO" > "$CF_OUT" 2>&1
check "check-fixture rejects the stubbed fixture" "(( $? != 0 ))"
check "check-fixture names the stub" "grep -q 'still carries the stub' '$CF_OUT' && grep -q 'still the stub' '$CF_OUT'"
"$CHECK_FIXTURE" "$FIXTURE_NAME" --consumer "$REPO" > "$WORK/check-fixture-real.txt" 2>&1
check "check-fixture passes the real fixture" "(( $? == 0 ))"
check "... taking its spec from the consumer's own checkout" "grep -q 'spec is taken from the consumer' '$WORK/check-fixture-real.txt'"

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

# ── 5. The repository a fixture measures: the consumer, never another ──────────
echo ""
echo "=== smoke: the repository a fixture measures ==="
# derived_fixture <name> <stem> <jq filter over the smoke fixture.json> — a fixture beside
# the smoke one with its own name and stem, the filter applied, and the smoke fixture's
# facts, review brief, README and acceptance probe.
derived_fixture() {
  local dir="$REPO/plans/experiments/fixtures/$1"
  mkdir -p "$dir/accept"
  jq --arg name "$1" --arg stem "$2" ".name = \$name | .branch_stem = \$stem | $3" "$FIXTURE_DIR/fixture.json" > "$dir/fixture.json"
  cp "$FIXTURE_DIR/facts.md" "$FIXTURE_DIR/review-brief.md" "$FIXTURE_DIR/README.md" "$dir/"
  cp "$FIXTURE_DIR/accept/accept.py" "$dir/accept/"
}
# derived_experiment <name> <fixture> <stem> — an experiment of that one fixture, null method.
derived_experiment() {
  mkdir -p "$REPO/plans/experiments/$1"
  jq --arg name "$1" --arg fx "$2" --arg stem "$3" '.name = $name | .fixtures = [$fx] | .branch_stem_override = {($fx): $stem}' \
    "$EXPERIMENT_DIR/experiment.json" > "$REPO/plans/experiments/$1/experiment.json"
}

# A fixture that names the consumer's own URL is the consumer too: nothing is resolved.
derived_fixture "$OWN_URL_FIXTURE" "$OWN_URL_STEM" ".repo = {url: \"$REMOTE_URL\", remote: \"origin\"}"
derived_experiment "$OWN_URL_EXPERIMENT" "$OWN_URL_FIXTURE" "$OWN_URL_STEM"
"$CHECK_FIXTURE" "$OWN_URL_FIXTURE" --consumer "$REPO" > "$WORK/check-own-url.txt" 2>&1
check "check-fixture passes a fixture whose repo.url is the consumer's own origin" "(( $? == 0 ))"
check "... and says the fixture's repository is the consumer" "grep -q \"the fixture's repository is the consumer ($REPO)\" '$WORK/check-own-url.txt'"
"$RUN" "$REPO/plans/experiments/$OWN_URL_EXPERIMENT" --consumer "$REPO" --dry-run > "$WORK/dry-run-own-url.txt" 2>&1
check "run --dry-run accepts a fixture whose repo.url is the consumer's own origin" "(( $? == 0 )) && grep -q 'repo:  *$REPO\$' '$WORK/dry-run-own-url.txt'"
"$NEW_EXPERIMENT" smokeOwnUrlNew --fixtures "$OWN_URL_FIXTURE" --methods null --prediction p --override "$OWN_URL_FIXTURE=$OWN_URL_STEM" \
  --consumer "$REPO" > "$WORK/new-experiment-own-url.txt" 2>&1
check "new-experiment accepts it too" "(( $? == 0 ))"

# A fixture that names another repository is refused wherever it is read, naming that
# repository and the remedy (move it there and run it there).
derived_fixture "$OTHER_FIXTURE" "$OTHER_STEM" ".repo = {url: \"$OTHER_REPO_URL\", remote: \"origin\"}"
derived_experiment "$OTHER_EXPERIMENT" "$OTHER_FIXTURE" "$OTHER_STEM"
"$CHECK_FIXTURE" "$OTHER_FIXTURE" --consumer "$REPO" > "$WORK/check-other-repo.txt" 2>&1
check "check-fixture refuses a fixture whose repo.url names another repository" "(( $? != 0 ))"
check "... naming that repository" "grep -q 'this fixture measures $OTHER_REPO_IDENTITY' '$WORK/check-other-repo.txt'"
check "... and the remedy" "grep -q '$OTHER_REPO_REMEDY' '$WORK/check-other-repo.txt' && grep -q 'plans/experiments/fixtures/' '$WORK/check-other-repo.txt'"
"$RUN" "$REPO/plans/experiments/$OTHER_EXPERIMENT" --consumer "$REPO" --dry-run > "$WORK/dry-run-other-repo.txt" 2>&1
check "run --dry-run refuses it" "(( $? != 0 ))"
check "... naming that repository and the remedy, and no branch" \
  "grep -q '$OTHER_REPO_IDENTITY' '$WORK/dry-run-other-repo.txt' && grep -q '$OTHER_REPO_REMEDY' '$WORK/dry-run-other-repo.txt' && ! grep -q 'branch:' '$WORK/dry-run-other-repo.txt'"
"$NEW_EXPERIMENT" smokeOtherNew --fixtures "$OTHER_FIXTURE" --methods null --prediction p --override "$OTHER_FIXTURE=$OTHER_STEM" \
  --consumer "$REPO" > "$WORK/new-experiment-other-repo.txt" 2>&1
check "new-experiment refuses it, naming that repository and the remedy" \
  "(( $? != 0 )) && grep -q '$OTHER_REPO_IDENTITY' '$WORK/new-experiment-other-repo.txt' && grep -q '$OTHER_REPO_REMEDY' '$WORK/new-experiment-other-repo.txt' && [[ ! -e '$REPO/plans/experiments/smokeOtherNew' ]]"

# `repo.path` is checked as well as `repo.url`: the consumer's own directory passes; another
# repository's checkout, a path that is not there, and a stale path beside the consumer's own
# URL are refused, the message naming the checkout's repository (or the path itself).
derived_fixture "$PATH_OWN_FIXTURE" "$PATH_OWN_STEM" ".repo = {path: \"$REPO\", remote: \"origin\"}"
"$CHECK_FIXTURE" "$PATH_OWN_FIXTURE" --consumer "$REPO" > "$WORK/check-path-own.txt" 2>&1
check "check-fixture passes a fixture whose repo.path is the consumer's own directory" "(( $? == 0 )) && grep -q \"the fixture's repository is the consumer ($REPO)\" '$WORK/check-path-own.txt'"
mkdir -p "$PATH_OTHER_CHECKOUT"
git init -q "$PATH_OTHER_CHECKOUT"
git -C "$PATH_OTHER_CHECKOUT" remote add origin "$OTHER_REPO_URL"
derived_fixture "$PATH_OTHER_FIXTURE" "$PATH_OTHER_STEM" ".repo = {path: \"$PATH_OTHER_CHECKOUT\", remote: \"origin\"}"
"$CHECK_FIXTURE" "$PATH_OTHER_FIXTURE" --consumer "$REPO" > "$WORK/check-path-other.txt" 2>&1
check "check-fixture refuses a repo.path that is a checkout of another repository, naming it and the remedy" \
  "(( $? != 0 )) && grep -q 'this fixture measures $OTHER_REPO_IDENTITY' '$WORK/check-path-other.txt' && grep -q '$OTHER_REPO_REMEDY' '$WORK/check-path-other.txt'"
derived_fixture "$PATH_MISSING_FIXTURE" "$PATH_MISSING_STEM" ".repo = {path: \"$PATH_MISSING_DIR\", remote: \"origin\"}"
"$CHECK_FIXTURE" "$PATH_MISSING_FIXTURE" --consumer "$REPO" > "$WORK/check-path-missing.txt" 2>&1
check "check-fixture refuses a repo.path that does not exist, naming the path" \
  "(( $? != 0 )) && grep -qF 'this fixture measures $PATH_MISSING_DIR' '$WORK/check-path-missing.txt'"
derived_fixture "$PATH_STALE_FIXTURE" "$PATH_STALE_STEM" ".repo = {url: \"$REMOTE_URL\", path: \"$PATH_MISSING_DIR\", remote: \"origin\"}"
"$CHECK_FIXTURE" "$PATH_STALE_FIXTURE" --consumer "$REPO" > "$WORK/check-path-stale.txt" 2>&1
check "check-fixture refuses the consumer's own repo.url beside a stale repo.path, naming the path" \
  "(( $? != 0 )) && grep -qF 'this fixture measures $PATH_MISSING_DIR' '$WORK/check-path-stale.txt'"

# The spec may live in another repository: an external checkout, reached by `spec.url`,
# resolved on this machine by HARNESS_REPO_DIR_<NAME>, the roots, or a clone — read-only.
mkdir -p "$SPEC_CHECKOUT"
git init -q "$SPEC_CHECKOUT"
git -C "$SPEC_CHECKOUT" config user.email smoke@example.invalid
git -C "$SPEC_CHECKOUT" config user.name "Harness Smoke"
cp "$REPO/SPEC.md" "$SPEC_CHECKOUT/SPEC.md"
git -C "$SPEC_CHECKOUT" add -A
git -C "$SPEC_CHECKOUT" commit -q -m "smoke external spec"
SPEC_SHA="$(git -C "$SPEC_CHECKOUT" rev-parse HEAD)"
git init -q --bare "$SPEC_REMOTE_URL"
git -C "$SPEC_CHECKOUT" remote add origin "$SPEC_REMOTE_URL"
git -C "$SPEC_CHECKOUT" push -q -u origin HEAD 2>/dev/null
derived_fixture "$EXT_SPEC_FIXTURE" "$EXT_SPEC_STEM" ".spec = {url: \"$SPEC_REMOTE_URL\", commit: \"$SPEC_SHA\", path: \"SPEC.md\", sections: [\"1\"]}"
derived_experiment "$EXT_SPEC_EXPERIMENT" "$EXT_SPEC_FIXTURE" "$EXT_SPEC_STEM"
check "the external-spec fixture's spec commit is in the spec repository, not the consumer" \
  "git -C '$SPEC_CHECKOUT' cat-file -e '$SPEC_SHA^{commit}' && ! git -C '$REPO' cat-file -e '$SPEC_SHA^{commit}' 2>/dev/null"
# With no checkout of it under the roots searched, the override names one and nothing is
# cloned; without the override, spec.url is cloned into the first root.
ELSEWHERE="$WORK/elsewhere"
mkdir -p "$ELSEWHERE"
env "HARNESS_REPO_ROOTS=$ELSEWHERE" "$SPEC_REPO_ENV_KEY=$SPEC_CHECKOUT" "$CHECK_FIXTURE" "$EXT_SPEC_FIXTURE" --consumer "$REPO" > "$WORK/check-override.txt" 2>&1
check "check-fixture honours HARNESS_REPO_DIR_<NAME> for spec.url (exits 0)" "(( $? == 0 ))"
check "... says spec.url resolves to that checkout" "grep -q 'spec.url resolves to a checkout here ($SPEC_CHECKOUT)' '$WORK/check-override.txt'"
check "... and cloned nothing" "[[ -z \"\$(ls -A '$ELSEWHERE')\" ]]"
HARNESS_REPO_ROOTS="$ELSEWHERE" "$CHECK_FIXTURE" "$EXT_SPEC_FIXTURE" --consumer "$REPO" > "$WORK/check-clone.txt" 2>&1
check "check-fixture clones a spec repository it cannot find (exits 0)" "(( $? == 0 ))"
check "... into the first root, named after the repository" "[[ -d '$ELSEWHERE/$SPEC_REPO_NAME/.git' ]]"
check "... and says so" "grep -q 'cloning into $ELSEWHERE/$SPEC_REPO_NAME' '$WORK/check-clone.txt'"
check "... and the consumer itself was not cloned" "[[ ! -e '$ELSEWHERE/remote' ]]"
ELSEWHERE_DRY="$WORK/elsewhere-dry"
mkdir -p "$ELSEWHERE_DRY"
HARNESS_REPO_ROOTS="$ELSEWHERE_DRY" "$RUN" "$REPO/plans/experiments/$EXT_SPEC_EXPERIMENT" --consumer "$REPO" --dry-run > "$WORK/dry-run-clone.txt" 2>&1
check "a dry run of the external-spec fixture exits 0 and names the external spec repository" \
  "(( $? == 0 )) && grep 'spec worktree:' '$WORK/dry-run-clone.txt' | grep -qF 'external spec repository $SPEC_REMOTE_URL'"
check "... resolves the spec to the clone it would otherwise make, without making it" \
  "grep -q 'git -C $ELSEWHERE_DRY/$SPEC_REPO_NAME worktree add --detach' '$WORK/dry-run-clone.txt' && [[ -z \"\$(ls -A '$ELSEWHERE_DRY')\" ]]"
check "... while the fixture's own repository is still the consumer" "grep -q 'repo:  *$REPO\$' '$WORK/dry-run-clone.txt'"
# A fixture in the pre-URL shape for its spec (spec.repo, a path; no spec.url) still runs
# here, with a warning naming spec.url. Its repository is the consumer's all the same.
derived_fixture "$LEGACY_SPEC_FIXTURE" smokeLegacyStem ".spec = {repo: \"$SPEC_CHECKOUT\", commit: \"$SPEC_SHA\", path: \"SPEC.md\", sections: [\"1\"]}"
"$CHECK_FIXTURE" "$LEGACY_SPEC_FIXTURE" --consumer "$REPO" > "$WORK/check-legacy.txt" 2>&1
check "check-fixture passes a spec.repo-only fixture (exits 0)" "(( $? == 0 ))"
check "... warning that the path is this machine's and naming spec.url" "grep -q 'warn.*spec.repo is a path.*add spec.url' '$WORK/check-legacy.txt'"
derived_experiment smokeLegacySpecRun "$LEGACY_SPEC_FIXTURE" smokeLegacyStem
"$RUN" "$REPO/plans/experiments/smokeLegacySpecRun" --consumer "$REPO" --dry-run > "$WORK/dry-run-legacy.txt" 2>&1
check "run --dry-run takes the spec.repo path hint too, warning once" \
  "(( $? == 0 )) && grep -q 'names no spec.url' '$WORK/dry-run-legacy.txt' && grep -q 'git -C $SPEC_CHECKOUT worktree add --detach' '$WORK/dry-run-legacy.txt'"

# ── 5b. The harness runs from the measured repository's own agentTooling/ ───────
echo ""
echo "=== smoke: the external-driver refusal ==="
# The seam is off for these calls (env -u). The temp consumers elsewhere in this test have
# agentTooling/ symlinked to this checkout, so they ARE driven by their own copy; the
# refused consumer carries a different agentTooling/ (an empty directory).
mkdir -p "$FOREIGN_CONSUMER/agentTooling"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$RUN" "$EXPERIMENT_DIR" --consumer "$FOREIGN_CONSUMER" --dry-run > "$WORK/driver-run.txt" 2>&1
check "run.sh --consumer <a repo with another agentTooling/> exits non-zero without the seam" "(( $? != 0 ))"
check "... saying the harness runs from the measured repository's own agentTooling/" "grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-run.txt'"
check "... and naming agentTooling/update.sh" "grep -qF '$OWN_DRIVER_UPDATE_HINT' '$WORK/driver-run.txt'"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$CHECK_FIXTURE" "$FIXTURE_NAME" --consumer "$FOREIGN_CONSUMER" > "$WORK/driver-check.txt" 2>&1
check "check-fixture.sh refuses likewise" "(( $? != 0 )) && grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-check.txt'"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$NEW_EXPERIMENT" smokeDriver --fixtures "$FIXTURE_NAME" --methods null --prediction p --consumer "$FOREIGN_CONSUMER" > "$WORK/driver-new-experiment.txt" 2>&1
check "new-experiment.sh refuses likewise" "(( $? != 0 )) && grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-new-experiment.txt'"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$NEW_FIXTURE" smokeDriver --base HEAD --spec-ref HEAD --spec-path SPEC.md --consumer "$FOREIGN_CONSUMER" > "$WORK/driver-new-fixture.txt" 2>&1
check "new-fixture.sh refuses likewise" "(( $? != 0 )) && grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-new-fixture.txt'"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$PUBLISH" "$EXPERIMENT_DIR" --consumer "$FOREIGN_CONSUMER" > "$WORK/driver-publish.txt" 2>&1
check "publish.sh refuses likewise" "(( $? != 0 )) && grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-publish.txt'"
env -u HARNESS_TEST_EXTERNAL_DRIVER "$RUN" "$EXPERIMENT_DIR" --consumer "$REPO" --dry-run > "$WORK/driver-own.txt" 2>&1
check "without the seam, a consumer whose agentTooling/ is this very checkout is driven by its own copy (exits 0)" \
  "(( $? == 0 )) && ! grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-own.txt'"
HARNESS_TEST_EXTERNAL_DRIVER=1 "$RUN" "$EXPERIMENT_DIR" --consumer "$FOREIGN_CONSUMER" --dry-run > "$WORK/driver-seam.txt" 2>&1
check "with the seam set, the same foreign consumer gets past the driver check" "! grep -qF \"$OWN_DRIVER_MESSAGE\" '$WORK/driver-seam.txt'"

# ── 6. A pinned arm: the experiment names an agentTooling commit per arm ──────
echo ""
echo "=== smoke: pinned arm ==="
AT_HEAD="$(git -C "$AGENT_TOOLING_UNDER_TEST" rev-parse HEAD)"
PIN_DIR="$REPO/plans/experiments/$PIN_EXPERIMENT"
"$NEW_EXPERIMENT" "$PIN_EXPERIMENT" --fixtures "$FIXTURE_NAME" --methods null \
  --agent-tooling "$PIN_ARM=HEAD" --override "$FIXTURE_NAME=$PIN_STEM" \
  --prediction 'the arm runs on the pinned agentTooling' --consumer "$REPO" > "$WORK/new-pin.txt" 2>&1
check "new-experiment --agent-tooling exits 0" "(( $? == 0 ))"
check "new-experiment pinned the arm to the full commit id" "[[ \$(jq -r '.agent_tooling.$PIN_ARM' '$PIN_DIR/experiment.json') == '$AT_HEAD' ]]"
check "new-experiment README lists the arm's branch" "grep -q '$PIN_BRANCH' '$PIN_DIR/README.md'"
check "new-experiment refuses an arm label that is not bare letters" \
  "! '$NEW_EXPERIMENT' smokeBadArm --fixtures '$FIXTURE_NAME' --methods null --agent-tooling 'v2=HEAD' --override $FIXTURE_NAME=badArm --prediction p --consumer '$REPO' >/dev/null 2>&1"
check "new-experiment refuses an arm ref that does not resolve" \
  "! '$NEW_EXPERIMENT' smokeBadRef --fixtures '$FIXTURE_NAME' --methods null --agent-tooling 'old=no-such-ref' --override $FIXTURE_NAME=badRef --prediction p --consumer '$REPO' >/dev/null 2>&1"
"$RUN" "$PIN_DIR" --consumer "$REPO" --dry-run > "$WORK/pin-dry-run.txt" 2>&1
check "pinned dry run exits 0" "(( $? == 0 ))"
check "pinned dry run names the arm's branch" "grep -q 'branch:  *$PIN_BRANCH' '$WORK/pin-dry-run.txt'"
check "pinned dry run names the pin" "grep -q 'pinned to upstream $AT_HEAD (arm $PIN_ARM)' '$WORK/pin-dry-run.txt'"
"$RUN" "$PIN_DIR" --consumer "$REPO" --only "$FIXTURE_NAME:null:nope" --dry-run > "$WORK/pin-only.txt" 2>&1
check "--only with another arm selects no cell" "! grep -q 'branch:' '$WORK/pin-only.txt'"
# An agent_tooling that is not an object must stop the run, not read as "no pin" and run
# every cell on the tree's own vendored copy under an experiment meant to compare versions.
BAD_ARMS_DIR="$REPO/plans/experiments/$BAD_ARMS_EXPERIMENT"
mkdir -p "$BAD_ARMS_DIR"
jq --arg name "$BAD_ARMS_EXPERIMENT" --arg bad "$BAD_ARMS_VALUE" '.name = $name | .agent_tooling = $bad' \
  "$PIN_DIR/experiment.json" > "$BAD_ARMS_DIR/experiment.json"
check "the malformed experiment really carries agent_tooling \"$BAD_ARMS_VALUE\"" \
  "[[ \$(jq -r '.agent_tooling' '$BAD_ARMS_DIR/experiment.json') == '$BAD_ARMS_VALUE' ]]"
"$RUN" "$BAD_ARMS_DIR" --consumer "$REPO" --dry-run > "$WORK/bad-arms-dry-run.txt" 2>&1
bad_arms_rc=$?
check "a malformed agent_tooling makes the dry run exit non-zero" "(( $bad_arms_rc != 0 ))"
check "... and no cell was resolved (no branch: line)" "! grep -q 'branch:' '$WORK/bad-arms-dry-run.txt'"
check "... and the error names the expected shape" "grep -q 'ERROR: $BAD_ARMS_SHAPE' '$WORK/bad-arms-dry-run.txt'"
# An explicit `"review": false` in `stages` must read as false, not as the absent-flag
# default (`// true` treats false as absent); the dry run prints the flags it read.
NO_REVIEW_DIR="$REPO/plans/experiments/$NO_REVIEW_EXPERIMENT"
mkdir -p "$NO_REVIEW_DIR"
jq --arg name "$NO_REVIEW_EXPERIMENT" '.name = $name | .stages = {review: false}' \
  "$PIN_DIR/experiment.json" > "$NO_REVIEW_DIR/experiment.json"
"$RUN" "$NO_REVIEW_DIR" --consumer "$REPO" --dry-run > "$WORK/no-review-dry-run.txt" 2>&1
check "stages {review: false} makes the dry run exit 0" "(( $? == 0 ))"
check "... reading review as false, and the absent rework and accept flags as true" \
  "grep -q 'review: false   rework: true   accept: true' '$WORK/no-review-dry-run.txt'"
PIN_OUT="$WORK/pin-run.txt"
"$RUN" "$PIN_DIR" --consumer "$REPO" --only "$FIXTURE_NAME:null:$PIN_ARM" --no-cleanup > "$PIN_OUT" 2>&1
pin_rc=$?
if (( pin_rc != 0 )); then
  echo "--- run output ---"
  cat "$PIN_OUT"
  echo "------------------"
fi
check "pinned run exits 0" "(( $pin_rc == 0 ))"
check "the worktree's agentTooling/ is a directory holding the pinned tree, not the symlink" \
  "[[ -d '$PIN_TREE/agentTooling' && ! -L '$PIN_TREE/agentTooling' && -f '$PIN_TREE/agentTooling/harness/lib.sh' ]]"
check "the pin is one commit titled so it cannot be merged by accident" \
  "git -C '$PIN_TREE' log --format=%s | grep -qF '$PIN_SUBJECT_PREFIX ${AT_HEAD:0:7}'"
check "the pinned copy's sync ran (generated plans/README.md present)" "[[ -f '$PIN_TREE/plans/README.md' ]]"
check "pinned row carries the arm and the agentTooling commit" \
  "[[ \$(jq -r '.arm' '$PIN_DIR/results.jsonl') == '$PIN_ARM' && \$(jq -r '.agent_tooling' '$PIN_DIR/results.jsonl') == '$AT_HEAD' ]]"
check "pinned row reached the PR (the null method's pr.sh) and the accept probe" \
  "[[ \$(jq -r '.pr_url' '$PIN_DIR/results.jsonl') == '$FAKE_PR_URL' && \$(jq -r '.accept_pass' '$PIN_DIR/results.jsonl') == true ]]"
check "pinned scorecard shows the arm" "grep -q '$PIN_ARM (${AT_HEAD:0:7})' '$PIN_DIR/SCORECARD.md'"
check "unpinned row carries an empty arm" "[[ \$(sed -n 1p '$RESULTS' | jq -r '.arm') == '' ]]"

# ── 7. Resuming a cell whose pin died after its worktree was added ────────────
echo ""
echo "=== smoke: resume after a failed pin ==="
# The first run cannot reach agentTooling's upstream: HARNESS_AGENT_TOOLING_URL names a
# directory that is not a checkout, and the one root searched is empty, so the clone fails
# — after `worktree add`, which is the failure harness_clone_remedy tells the user to fix
# and re-run. The fixture's own repository is the consumer and is never resolved.
RESUME_DIR="$REPO/plans/experiments/$RESUME_EXPERIMENT"
NOT_A_CHECKOUT="$WORK/not-a-checkout"
EMPTY_ROOT="$WORK/empty-root"
mkdir -p "$NOT_A_CHECKOUT" "$EMPTY_ROOT"
pin_commits_on_resume_branch() {
  git -C "$REPO" log --format=%s "$BASE_SHA..$RESUME_BRANCH" | grep -cxF "$PIN_SUBJECT_PREFIX ${AT_HEAD:0:7}"
}
"$NEW_EXPERIMENT" "$RESUME_EXPERIMENT" --fixtures "$FIXTURE_NAME" --methods null \
  --agent-tooling "$PIN_ARM=HEAD" --override "$FIXTURE_NAME=$RESUME_STEM" \
  --prediction 'a pin that died is redone by the re-run' --consumer "$REPO" > "$WORK/new-resume.txt" 2>&1
check "new-experiment for the resume run exits 0" "(( $? == 0 ))"
RESUME_FAIL_OUT="$WORK/resume-fail.txt"
HARNESS_AGENT_TOOLING_URL="$NOT_A_CHECKOUT" HARNESS_REPO_ROOTS="$EMPTY_ROOT" \
  "$RUN" "$RESUME_DIR" --consumer "$REPO" --only "$FIXTURE_NAME:null:$PIN_ARM" --no-cleanup > "$RESUME_FAIL_OUT" 2>&1
resume_fail_rc=$?
check "the run whose pin cannot reach upstream exits non-zero" "(( $resume_fail_rc != 0 ))"
check "... for that reason (the clone of agentTooling failed)" "grep -q 'could not clone $NOT_A_CHECKOUT' '$RESUME_FAIL_OUT'"
check "... after the worktree was added" "[[ -d '$RESUME_TREE' ]]"
check "... leaving the arm's branch" "git -C '$REPO' show-ref --verify --quiet refs/heads/$RESUME_BRANCH"
check "... with no pin commit on it" "[[ \$(pin_commits_on_resume_branch) -eq 0 ]]"
check "... and the tree still carries the base's symlinked agentTooling" "[[ -L '$RESUME_TREE/agentTooling' ]]"
check "... and wrote no ledger row" "[[ ! -s '$RESUME_DIR/results.jsonl' ]]"

RESUME_OUT="$WORK/resume-run.txt"
"$RUN" "$RESUME_DIR" --consumer "$REPO" --only "$FIXTURE_NAME:null:$PIN_ARM" --no-cleanup > "$RESUME_OUT" 2>&1
resume_rc=$?
if (( resume_rc != 0 )); then
  echo "--- run output ---"
  cat "$RESUME_OUT"
  echo "------------------"
fi
check "the re-run with the real upstream exits 0" "(( $resume_rc == 0 ))"
check "... reusing the worktree the failed run left" "grep -q 'worktree already present: $RESUME_TREE' '$RESUME_OUT'"
check "... the pin commit is on the branch exactly once" \
  "[[ \$(pin_commits_on_resume_branch) -eq $RESUME_PIN_COMMITS_EXPECTED ]]"
check "... agentTooling/ is a real directory holding the pinned tree, not the symlink" \
  "[[ -d '$RESUME_TREE/agentTooling' && ! -L '$RESUME_TREE/agentTooling' && -f '$RESUME_TREE/agentTooling/harness/lib.sh' ]]"
check "... the ledger row's agent_tooling is the arm's full sha" \
  "[[ \$(jq -r '.agent_tooling' '$RESUME_DIR/results.jsonl') == '$AT_HEAD' && \$(jq -r '.arm' '$RESUME_DIR/results.jsonl') == '$PIN_ARM' ]]"

RESUME_AGAIN_OUT="$WORK/resume-again.txt"
"$RUN" "$RESUME_DIR" --consumer "$REPO" --only "$FIXTURE_NAME:null:$PIN_ARM" --from setup --no-cleanup > "$RESUME_AGAIN_OUT" 2>&1
resume_again_rc=$?
if (( resume_again_rc != 0 )); then
  echo "--- run output ---"
  cat "$RESUME_AGAIN_OUT"
  echo "------------------"
fi
check "a further --from setup run exits 0" "(( $resume_again_rc == 0 ))"
check "... and the branch still has exactly one pin commit" \
  "[[ \$(pin_commits_on_resume_branch) -eq $RESUME_PIN_COMMITS_EXPECTED ]]"
check "... and agentTooling/ is still the real directory" \
  "[[ -d '$RESUME_TREE/agentTooling' && ! -L '$RESUME_TREE/agentTooling' ]]"

# ── 8. An arm equal to the version the base already vendors (the control arm) ──
echo ""
echo "=== smoke: control arm (pin equal to the base) ==="
# The smoke repo's agentTooling/ is a symlink, so every pin above changed something. Here
# the fixture's base is a commit whose agentTooling/ is a real directory already holding
# the arm's commit (what a subtree-vendored copy at that upstream commit is), with its
# generated files already synced: the extract and the sync then change nothing, and the
# pin commit must still be made, empty.
git -C "$REPO" worktree add -q -b "$CONTROL_PREP_BRANCH" "$CONTROL_PREP_TREE" "$BASE_SHA" >/dev/null 2>&1
rm -f "$CONTROL_PREP_TREE/agentTooling"
mkdir -p "$CONTROL_PREP_TREE/agentTooling"
git -C "$AGENT_TOOLING_UNDER_TEST" archive "$AT_HEAD" | tar -x -C "$CONTROL_PREP_TREE/agentTooling"
( cd "$CONTROL_PREP_TREE" && ./agentTooling/sync-plans.sh ) > "$WORK/control-prep-sync.txt" 2>&1
git -C "$CONTROL_PREP_TREE" add -A
git -C "$CONTROL_PREP_TREE" commit -q -m "smoke control base: agentTooling vendored at ${AT_HEAD:0:7}"
CONTROL_BASE_SHA="$(git -C "$CONTROL_PREP_TREE" rev-parse HEAD)"
git -C "$REPO" worktree remove --force "$CONTROL_PREP_TREE" >/dev/null 2>&1
check "the control base is a commit past the smoke base" "[[ -n '$CONTROL_BASE_SHA' && '$CONTROL_BASE_SHA' != '$BASE_SHA' ]]"
check "... whose agentTooling/ is a real directory, not a symlink" \
  "[[ \$(git -C '$REPO' ls-tree '$CONTROL_BASE_SHA' agentTooling | cut -c1-6) == 040000 ]]"

CONTROL_FIXTURE_DIR="$REPO/plans/experiments/fixtures/$CONTROL_FIXTURE"
mkdir -p "$CONTROL_FIXTURE_DIR/accept"
jq --arg name "$CONTROL_FIXTURE" --arg base "$CONTROL_BASE_SHA" --arg stem "$CONTROL_STEM" \
  '.name = $name | .base = $base | .branch_stem = $stem' \
  "$FIXTURE_DIR/fixture.json" > "$CONTROL_FIXTURE_DIR/fixture.json"
cp "$FIXTURE_DIR/facts.md" "$FIXTURE_DIR/review-brief.md" "$FIXTURE_DIR/README.md" "$CONTROL_FIXTURE_DIR/"
cp "$FIXTURE_DIR/accept/accept.py" "$CONTROL_FIXTURE_DIR/accept/"
CONTROL_DIR="$REPO/plans/experiments/$CONTROL_EXPERIMENT"
"$NEW_EXPERIMENT" "$CONTROL_EXPERIMENT" --fixtures "$CONTROL_FIXTURE" --methods null \
  --agent-tooling "$PIN_ARM=HEAD" --prediction 'a pin equal to the base is an empty commit' \
  --consumer "$REPO" > "$WORK/new-control.txt" 2>&1
check "new-experiment for the control run exits 0" "(( $? == 0 ))"
control_pin_commit() {
  git -C "$REPO" log --format=%H -n 1 --fixed-strings --grep="$PIN_SUBJECT_PREFIX ${AT_HEAD:0:7}" "$CONTROL_BASE_SHA..$CONTROL_BRANCH"
}
control_pin_commits() {
  git -C "$REPO" log --format=%s "$CONTROL_BASE_SHA..$CONTROL_BRANCH" | grep -cxF "$PIN_SUBJECT_PREFIX ${AT_HEAD:0:7}"
}
CONTROL_OUT="$WORK/control-run.txt"
"$RUN" "$CONTROL_DIR" --consumer "$REPO" --only "$CONTROL_FIXTURE:null:$PIN_ARM" --no-cleanup > "$CONTROL_OUT" 2>&1
control_rc=$?
if (( control_rc != 0 )); then
  echo "--- run output ---"
  cat "$CONTROL_OUT"
  echo "------------------"
fi
check "the run whose pin equals the base exits 0" "(( $control_rc == 0 ))"
check "... exactly one pin commit is on the branch" "[[ \$(control_pin_commits) -eq $CONTROL_PIN_COMMITS_EXPECTED ]]"
check "... the pin commit lists no files (git show --stat)" \
  "[[ -n \"\$(control_pin_commit)\" && -z \"\$(git -C '$REPO' show --stat --format= \"\$(control_pin_commit)\")\" ]]"
check "... and its tree is its parent's" \
  "[[ \$(git -C '$REPO' rev-parse \"\$(control_pin_commit)^{tree}\") == \$(git -C '$REPO' rev-parse \"\$(control_pin_commit)^^{tree}\") ]]"
check "... agentTooling/ is the real directory the base vendored" \
  "[[ -d '$CONTROL_TREE/agentTooling' && ! -L '$CONTROL_TREE/agentTooling' && -f '$CONTROL_TREE/agentTooling/harness/lib.sh' ]]"
check "... the ledger row's agent_tooling is the arm's full sha" \
  "[[ \$(jq -r '.agent_tooling' '$CONTROL_DIR/results.jsonl') == '$AT_HEAD' && \$(jq -r '.arm' '$CONTROL_DIR/results.jsonl') == '$PIN_ARM' ]]"

CONTROL_AGAIN_OUT="$WORK/control-again.txt"
"$RUN" "$CONTROL_DIR" --consumer "$REPO" --only "$CONTROL_FIXTURE:null:$PIN_ARM" --from setup --no-cleanup > "$CONTROL_AGAIN_OUT" 2>&1
control_again_rc=$?
check "a further --from setup run exits 0" "(( $control_again_rc == 0 ))"
check "... and the empty pin commit was found, not made again" \
  "[[ \$(control_pin_commits) -eq $CONTROL_PIN_COMMITS_EXPECTED ]]"

# ── 9. Program cells: the fixtures, the program, the fake orchestrator ─────────
echo ""
echo "=== smoke: program cells (setup) ==="
# Two fixtures off the smoke one (same repository, same base — the program's base governs
# anyway, and a differing fixture base would only draw a warning); their acceptance probe
# looks for the marker the fake implementer commits.
PROGRAM_FIXTURES_DIR="$REPO/plans/experiments/fixtures"
for fx in "$PROGRAM_FIXTURE_ONE" "$PROGRAM_FIXTURE_TWO"; do
  mkdir -p "$PROGRAM_FIXTURES_DIR/$fx/accept"
  jq --arg name "$fx" --arg stem "$fx" '.name = $name | .branch_stem = $stem' \
    "$FIXTURE_DIR/fixture.json" > "$PROGRAM_FIXTURES_DIR/$fx/fixture.json"
  cp "$FIXTURE_DIR/facts.md" "$FIXTURE_DIR/review-brief.md" "$FIXTURE_DIR/README.md" "$PROGRAM_FIXTURES_DIR/$fx/"
  cat > "$PROGRAM_FIXTURES_DIR/$fx/accept/accept.py" <<ACCEPTPROGRAM
#!/usr/bin/env python3
"""Smoke acceptance probe for a program feature: the implementer's marker is committed."""
import sys
from pathlib import Path

tree = Path(sys.argv[1])
ok = any(tree.glob("$PROGRAM_MARKER_GLOB"))
print(("PASS" if ok else "FAIL") + " a program marker file exists")
sys.exit(0 if ok else 1)
ACCEPTPROGRAM
done

PROGRAM_DIR="$REPO/plans/experiments/programs/$PROGRAM_NAME"
mkdir -p "$PROGRAM_DIR"
cat > "$PROGRAM_DIR/program.json" <<PROGRAMJSON
{
  "name": "$PROGRAM_NAME",
  "base": "$BASE_SHA",
  "branch_stem": "$PROGRAM_STEM_NAME",
  "features": [
    {"fixture": "$PROGRAM_FIXTURE_ONE", "depends_on_previous": false},
    {"fixture": "$PROGRAM_FIXTURE_TWO", "depends_on_previous": true}
  ]
}
PROGRAMJSON
cat > "$PROGRAM_DIR/README.md" <<'PROGRAMREADME'
# smokeProg

The harness's own program: two smoke fixtures, the second depending on the first.
PROGRAMREADME

# The fake orchestrator and implementer. The harness's fake `claude` (above) hands every
# `# Harness program …` prompt and every prompt that starts with the implementer's first
# line to this script, with its argv. It logs one `<new|resume> <id given> <id replied>` line
# per orchestrator call to $SMOKE_ORCH_LOG; a resume replies with a NEW session id (a fork),
# which is what the harness must follow and record in orchestrator_sessions[].
cat > "$BIN/program-claude" <<'PROGRAMCLAUDE'
#!/usr/bin/env bash
mode=""; given=""
while (( $# )); do
  case "$1" in
    --session-id) mode=new; given="$2"; shift 2 ;;
    --resume) mode=resume; given="$2"; shift 2 ;;
    *) shift ;;
  esac
done
prompt="$(cat)"
reply="fake program claude ok"
replied="$given"
failed=0
cost=0          # what this call reports as total_cost_usd
bills=0         # whether this call leaves a priced transcript under $HOME/.claude/projects
project=""; tbranch=""; tcwd=""
case "$prompt" in
  "# Harness program brief"*)
    reply="ready"; bills=1; project="smoke-orchestrator" ;;
  "# Harness program feature"*)
    bills=1; project="smoke-orchestrator"
    path="$(printf '%s\n' "$prompt" | sed -n 's/^Write the implementer.s brief to `\([^`]*\)`.*/\1/p' | head -1)"
    branch="$(printf '%s\n' "$prompt" | sed -n 's/^- Branch: `\([^`]*\)`.*/\1/p' | head -1)"
    base="$(printf '%s\n' "$prompt" | sed -n 's/^- PR base: `\([^`]*\)`.*/\1/p' | head -1)"
    mkdir -p "$(dirname "$path")"
    if [[ -z "${SMOKE_BRIEF_SKIP_FOR:-}" || "$branch" != *"$SMOKE_BRIEF_SKIP_FOR"* ]]; then
      printf '%s\nbranch: %s\nbase: %s\nBuild the marker file, commit it, open the PR to the base above.\n' \
        "$PROGRAM_IMPL_FIRST_LINE" "$branch" "$base" > "$path"
    fi
    reply="brief written
METHOD: direct" ;;
  "# Harness program collect"*)
    # Later than every earlier transcript instant, so the window the overhead is priced in
    # (which ends after this call) holds them all.
    [[ "${SMOKE_PRICED_TRANSCRIPTS:-0}" != 1 ]] || sleep 1
    while IFS= read -r line; do
      bash -c "$line" >/dev/null || failed=1
    done < <(printf '%s\n' "$prompt" | grep '^python3 agentTooling/analysis/manifest.py')
    slug="$(printf '%s\n' "$prompt" | sed -n 's/^   `\([^`]*\): orchestration record`.*/\1/p' | head -1)"
    git add -A && git commit -q -m "${slug:-program}: orchestration record"
    reply="recorded" ;;
  "$PROGRAM_IMPL_FIRST_LINE"*)
    branch="$(git branch --show-current)"
    base="$(printf '%s\n' "$prompt" | sed -n 's/^base: //p' | head -1)"
    if [[ -n "${SMOKE_IMPL_FAIL_FOR:-}" && "$branch" == *"$SMOKE_IMPL_FAIL_FOR"* ]]; then
      echo '{"type":"result","subtype":"error","is_error":true,"session_id":"smoke-impl-failed","total_cost_usd":0,"result":"the implementer gave up"}'
      exit 1
    fi
    cost="${SMOKE_IMPL_REPORTED_USD:-0}"
    # The transcript is filed under the tree's own project directory, as a real session's is,
    # and records the real cwd: the harness's tree <primary>-<branch>, which claim_roots
    # admits through the manifest's `branches`.
    bills=1; tcwd="$PWD"; tbranch="$branch"; project="$(printf '%s' "$PWD" | tr '/.' '--')"
    printf 'built %s\n' "$branch" > "program-marker-$branch.txt"
    git add -A && git commit -q -m "build $branch"
    git push -q -u origin "$branch" 2>/dev/null
    body="$(mktemp "${TMPDIR:-/tmp}/smoke-pr-body.XXXXXX")"
    printf 'one arm of an experiment — do not merge until it picks a winner\n' > "$body"
    "$HARNESS_FORGE_BIN" pr-open "$branch" "$base" "smoke: $branch" "$body" >/dev/null
    rm -f "$body"
    replied="smoke-impl-$branch"
    reply="built $branch" ;;
esac
if [[ "$mode" == resume ]]; then replied="smoke-orch-fork-$$"; fi
if [[ -n "$mode" ]]; then
  printf '%s %s %s\n' "$mode" "$given" "$replied" >> "${SMOKE_ORCH_LOG:-/dev/null}"
fi
# With SMOKE_PRICED_TRANSCRIPTS=1 the call also leaves what a real session would: one billed
# response in $HOME/.claude/projects/<project>/<session>.jsonl, dated now, so the real
# pricing paths (program_cost.py, capture_planning.py) find a non-zero figure.
if [[ "${SMOKE_PRICED_TRANSCRIPTS:-0}" == 1 && "$bills" == 1 ]]; then
  mkdir -p "$HOME/.claude/projects/$project"
  jq -c -n --arg sid "$replied" --arg b "$tbranch" --arg cwd "$tcwd" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" --arg model "$SMOKE_COST_MODEL" \
    --argjson i "$SMOKE_COST_INPUT_TOKENS" --argjson o "$SMOKE_COST_OUTPUT_TOKENS" \
    '{type: "assistant", sessionId: $sid, timestamp: $ts, message: {id: ($sid + "-m1"), model: $model, usage: {input_tokens: $i, output_tokens: $o}}}
     + (if $b != "" then {gitBranch: $b, cwd: $cwd} else {} end)' \
    >> "$HOME/.claude/projects/$project/$replied.jsonl"
  # The implementer's PR opens (closing its manifest window) after this call: stay clear of
  # the window's whole-second end.
  [[ -z "$tbranch" ]] || sleep 1
fi
jq -c -n --arg s "$replied" --arg r "$reply" --argjson c "$cost" \
  '{type:"result",subtype:"success",is_error:false,session_id:$s,total_cost_usd:$c,result:$r}'
exit "$failed"
PROGRAMCLAUDE
chmod +x "$BIN/program-claude"
export PROGRAM_IMPL_FIRST_LINE

# How the orchestrator's calls chained: the first was the minted --session-id, and every
# later --resume targeted the id the call before it replied with.
orch_chain_ok() {  # $1 log
  awk 'NR == 1 { if ($1 != "new") bad = 1; prev = $3; next }
       { if ($1 != "resume" || $2 != prev) bad = 1; prev = $3 }
       END { exit (bad || NR < 2) }' "$1"
}

NEW_PROGRAM_OUT="$WORK/new-program-experiment.txt"
PROGRAM_EXP_DIR="$REPO/plans/experiments/$PROGRAM_EXPERIMENT"
"$NEW_EXPERIMENT" "$PROGRAM_EXPERIMENT" --programs "$PROGRAM_NAME" --agent-tooling "$PROGRAM_ARM=HEAD" \
  --prediction 'a program of two features runs under one orchestrator' --consumer "$REPO" > "$NEW_PROGRAM_OUT" 2>&1
check "new-experiment --programs exits 0" "(( $? == 0 ))"
check "... experiment.json carries programs, no fixtures" \
  "[[ \$(jq -c '.programs' '$PROGRAM_EXP_DIR/experiment.json') == '[\"$PROGRAM_NAME\"]' ]]"
check "... the README lists the program branch and the feature branches" \
  "grep -q '$PROGRAM_BRANCH_ONE' '$PROGRAM_EXP_DIR/README.md' && grep -q '$PROGRAM_FEATURE_BRANCH_A' '$PROGRAM_EXP_DIR/README.md' && grep -q '$PROGRAM_FEATURE_BRANCH_B' '$PROGRAM_EXP_DIR/README.md'"
check "new-experiment refuses a program named like a fixture" \
  "! '$NEW_EXPERIMENT' smokeProgClash --fixtures '$PROGRAM_FIXTURE_ONE' --methods null --programs '$PROGRAM_FIXTURE_ONE' --prediction p --consumer '$REPO' >/dev/null 2>&1"

# ── 9a. A dry run names the program branch and creates nothing ────────────────
echo ""
echo "=== smoke: program cell, dry run ==="
PROGRAM_TREE_ONE="$REPO-$PROGRAM_BRANCH_ONE"
PROGRAM_RESULTS_ONE="$PROGRAM_EXP_DIR/results.jsonl"
PROGRAM_STATE_ONE="$PROGRAM_EXP_DIR/state/$PROGRAM_BRANCH_ONE.json"
"$RUN" "$PROGRAM_EXP_DIR" --consumer "$REPO" --dry-run > "$WORK/program-dry-run.txt" 2>&1
check "program dry run exits 0" "(( $? == 0 ))"
check "... names the program branch" "grep -q 'program branch: *$PROGRAM_BRANCH_ONE' '$WORK/program-dry-run.txt'"
check "... names both feature branches" \
  "grep -q 'branch $PROGRAM_FEATURE_BRANCH_A' '$WORK/program-dry-run.txt' && grep -q 'branch $PROGRAM_FEATURE_BRANCH_B' '$WORK/program-dry-run.txt'"
check "... names the pin" "grep -q 'pinned to upstream $AT_HEAD (arm $PROGRAM_ARM)' '$WORK/program-dry-run.txt'"
check "... created no program worktree" "[[ ! -d '$PROGRAM_TREE_ONE' ]]"
check "... created no program branch" "! git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_BRANCH_ONE"
check "... created no feature branch" \
  "! git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_FEATURE_BRANCH_A && ! git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_FEATURE_BRANCH_B"
check "... wrote no ledger and no state" "[[ ! -f '$PROGRAM_RESULTS_ONE' && ! -f '$PROGRAM_STATE_ONE' ]]"
check "... shows no --effort when HARNESS_EFFORT is unset" "! grep -q -- '--effort' '$WORK/program-dry-run.txt'"
HARNESS_EFFORT="$EFFORT_LEVEL" "$RUN" "$PROGRAM_EXP_DIR" --consumer "$REPO" --dry-run > "$WORK/program-dry-run-effort.txt" 2>&1
check "program dry run under HARNESS_EFFORT=$EFFORT_LEVEL exits 0" "(( $? == 0 ))"
check "... shows --effort $EFFORT_LEVEL on the orchestrator, implementer, review and rework lines" \
  "[[ \$(grep -c -- '--effort $EFFORT_LEVEL' '$WORK/program-dry-run-effort.txt') -ge 6 ]]"

# ── 9b. An unpinned program is refused: its agentTooling/ is a symlink ─────────
echo ""
echo "=== smoke: program cell, unpinned ==="
PROGRAM_BARE_DIR="$REPO/plans/experiments/$PROGRAM_BARE_EXPERIMENT"
"$NEW_EXPERIMENT" "$PROGRAM_BARE_EXPERIMENT" --programs "$PROGRAM_NAME" --override "$PROGRAM_NAME=$PROGRAM_BARE_STEM" \
  --prediction 'an unpinned program is refused' --consumer "$REPO" > "$WORK/new-program-bare.txt" 2>&1
check "new-experiment accepts an unpinned program (the symlink is the run's to refuse)" "(( $? == 0 ))"
PROGRAM_BARE_OUT="$WORK/program-bare-run.txt"
"$RUN" "$PROGRAM_BARE_DIR" --consumer "$REPO" > "$PROGRAM_BARE_OUT" 2>&1
program_bare_rc=$?
check "the unpinned program's run exits non-zero" "(( $program_bare_rc != 0 ))"
check "... on the program branch the unpinned cell would have run" "grep -q '$PROGRAM_BARE_BRANCH' '$PROGRAM_BARE_OUT'"
check "... naming the symlink and the remedy" "grep -q 'symlink' '$PROGRAM_BARE_OUT' && grep -q 'pin an arm' '$PROGRAM_BARE_OUT'"
check "... and wrote no ledger row" "[[ ! -s '$PROGRAM_BARE_DIR/results.jsonl' ]]"
check "... and ran no orchestrator" "! grep -q 'program stage brief' '$PROGRAM_BARE_OUT'"

# ── 9c. The full program run ──────────────────────────────────────────────────
echo ""
echo "=== smoke: program cell, full run ==="
export SMOKE_ORCH_LOG="$WORK/orchestrator-one.log"
PROGRAM_OUT_ONE="$WORK/program-run.txt"
# The run's HOME holds fabricated transcripts the fake sessions write (SMOKE_PRICED_TRANSCRIPTS),
# one billed response each, so overhead and feature costs go through the real pricing paths
# (program_cost.py, capture_planning.py, both reading $HOME/.claude/projects) as non-zero figures.
# The ordinary fake bills the review and rework calls under it too, so each feature's
# review and rework figures are non-zero here as well.
PRICED_HOME="$WORK/priced-home"
mkdir -p "$PRICED_HOME"
PRICED_RATES="$AGENT_TOOLING_UNDER_TEST/analysis/rates_history.json"
HOME="$PRICED_HOME" \
  SMOKE_PRICED_TRANSCRIPTS=1 \
  SMOKE_COST_MODEL="$(jq -r '.models | keys[0]' "$PRICED_RATES")" \
  SMOKE_COST_INPUT_TOKENS="$PROGRAM_PRICED_INPUT_TOKENS" SMOKE_COST_OUTPUT_TOKENS="$PROGRAM_PRICED_OUTPUT_TOKENS" \
  SMOKE_IMPL_REPORTED_USD="$PROGRAM_PRICED_REPORTED_USD" \
  "$RUN" "$PROGRAM_EXP_DIR" --consumer "$REPO" > "$PROGRAM_OUT_ONE" 2>&1
program_rc=$?
if (( program_rc != 0 )); then
  echo "--- run output ---"
  cat "$PROGRAM_OUT_ONE"
  echo "------------------"
fi
PROGRAM_TREE_A="$REPO-$PROGRAM_FEATURE_BRANCH_A"
PROGRAM_TREE_B="$REPO-$PROGRAM_FEATURE_BRANCH_B"
remote_has_branch() { git -C "$REMOTE_URL" show-ref --verify --quiet "refs/heads/$1"; }
program_row() { jq -e "$1" "$PROGRAM_RESULTS_ONE" >/dev/null; }
check "program run exits 0" "(( $program_rc == 0 ))"
check "ledger has exactly one row" "[[ -s '$PROGRAM_RESULTS_ONE' && \$(wc -l < '$PROGRAM_RESULTS_ONE') -eq 1 ]]"
check "program row: effort is null when HARNESS_EFFORT is unset" "program_row '.effort == null'"
check "row: kind program, method orchestrator, the program, the branch and slug" \
  "program_row '.kind == \"program\" and .method == \"$PROGRAM_METHOD_NAME\" and .program == \"$PROGRAM_NAME\" and .branch == \"$PROGRAM_BRANCH_ONE\" and .slug == \"$PROGRAM_SLUG_ONE\"'"
check "row: the arm and the agentTooling commit" \
  "program_row '.arm == \"$PROGRAM_ARM\" and .agent_tooling == \"$AT_HEAD\"'"
check "row: features_count 2" "program_row '.features_count == 2 and (.features | length) == 2'"
check "row: features_pr_open 2" "program_row '.features_pr_open == 2'"
check "row: both features picked up the orchestrator's METHOD line" \
  "program_row '[.features[].method] == [\"direct\", \"direct\"] and ([.features[].brief_written] | all)'"
check "row: feature order and fixtures" \
  "program_row '[.features[].fixture] == [\"$PROGRAM_FIXTURE_ONE\", \"$PROGRAM_FIXTURE_TWO\"] and [.features[].position] == [1, 2]'"
check "row: feature 1 has no dependency_ok (null)" "program_row '.features[0].dependency_ok == null and .features[0].depends_on_previous == false'"
check "row: feature 2 dependency_ok is true" "program_row '.features[1].dependency_ok == true and .features[1].depends_on_previous == true'"
check "row: feature 1's PR targets the usual base" "program_row '.features[0].pr_base == \"$PROGRAM_DEFAULT_PR_BASE\"'"
check "row: feature 2's PR targets feature 1's branch" "program_row '.features[1].pr_base == \"$PROGRAM_FEATURE_BRANCH_A\"'"
check "row: both PR urls recorded" \
  "program_row '.features[0].pr_url == \"https://example.invalid/pr/$PROGRAM_FEATURE_BRANCH_A\" and .features[1].pr_url == \"https://example.invalid/pr/$PROGRAM_FEATURE_BRANCH_B\"'"
check "the fake forge was asked to open feature 2's PR against feature 1's branch" \
  "[[ \$(cat '$SMOKE_PR_DIR/$PROGRAM_FEATURE_BRANCH_B.base') == '$PROGRAM_FEATURE_BRANCH_A' && \$(cat '$SMOKE_PR_DIR/$PROGRAM_FEATURE_BRANCH_A.base') == '$PROGRAM_DEFAULT_PR_BASE' ]]"
check "row: cost_overhead_usd is a number" "program_row '.cost_overhead_usd | type == \"number\"'"
check "row: cost_group_usd and overhead_pct are numbers" "program_row '(.cost_group_usd | type == \"number\") and (.overhead_pct | type == \"number\")'"
check "row: orchestrator_sessions[] is non-empty" "program_row '(.orchestrator_sessions | length) > 0'"
check "row: more than one orchestrator session (the resumes forked)" \
  "program_row '(.orchestrator_sessions | length) > ($PROGRAM_MIN_ORCHESTRATOR_SESSIONS - 1) and ((.orchestrator_sessions | unique | length) == (.orchestrator_sessions | length))'"
check "row: method_failed false, no feature failed" "program_row '.method_failed == false and ([.features[].method_failed] | any | not)'"
check "row: record_report present (a figure or null) and the record path named" \
  "program_row 'has(\"record_report\") and (.orchestration_record | endswith(\"$PROGRAM_SLUG_ONE/README.md\"))'"
check "row: window instants recorded" "program_row '(.t_method_start | length) > 0 and (.t_method_end | length) > 0 and (.t_setup_start | length) > 0'"
check "row: each feature walked review, rework and accept" \
  "program_row '[.features[] | .review_escalated == 1 and .rework_ran and .accept_pass] | all'"
check "row: features green" "program_row '.features_green == 2 and ([.features[].green] | all)'"
# The row's arithmetic, on non-zero figures (the run priced fabricated transcripts).
ROW_ABS='def ab: if . < 0 then -. else . end;'
ROW_TOL="$ARITHMETIC_TOLERANCE"
check "row: the orchestrator and both implementers priced non-zero (overhead, method costs)" \
  "program_row '.cost_overhead_usd > 0 and ([.features[].cost_method_usd] | all(. > 0))'"
check "row: cost_group_usd == cost_overhead_usd + sum(features' cost_method_usd)" \
  "program_row '$ROW_ABS ((.cost_group_usd - (.cost_overhead_usd + ([.features[].cost_method_usd] | add))) | ab) <= $ROW_TOL'"
check "row: cost_group_green_usd == cost_group_usd + sum(review + rework)" \
  "program_row '$ROW_ABS ((.cost_group_green_usd - (.cost_group_usd + ([.features[] | .cost_review_usd + .cost_rework_usd] | add))) | ab) <= $ROW_TOL'"
check "row: each feature's cost_green_usd == method + review + rework" \
  "program_row '$ROW_ABS [.features[] | ((.cost_green_usd - (.cost_method_usd + .cost_review_usd + .cost_rework_usd)) | ab) <= $ROW_TOL] | all'"
check "row: overhead_pct == cost_overhead_usd / cost_group_usd * 100" \
  "program_row '$ROW_ABS .cost_group_usd > 0 and ((.overhead_pct - (.cost_overhead_usd / .cost_group_usd * 100)) | ab) <= $ROW_TOL'"
check "row: priced features carry no unpriced_reason (captured above what claude reported)" \
  "program_row '[.features[].unpriced_reason] | all(. == null)'"
check "the orchestrator's calls chained new -> resume -> resume ... on the latest id" "orch_chain_ok '$SMOKE_ORCH_LOG'"
check "the orchestrator was called for the brief, two features and the collect (4 calls)" "[[ \$(wc -l < '$SMOKE_ORCH_LOG') -eq 4 ]]"
check "the program branch is pushed to the remote" "remote_has_branch $PROGRAM_BRANCH_ONE"
check "both feature branches are pushed to the remote" "remote_has_branch $PROGRAM_FEATURE_BRANCH_A && remote_has_branch $PROGRAM_FEATURE_BRANCH_B"
check "no PR was opened for the program branch" "[[ ! -e '$SMOKE_PR_DIR/$PROGRAM_BRANCH_ONE' ]]"
check "feature 2's branch holds feature 1's marker (cut at its tip)" \
  "git -C '$REMOTE_URL' cat-file -e '$PROGRAM_FEATURE_BRANCH_B:program-marker-$PROGRAM_FEATURE_BRANCH_A.txt'"
check "feature 1's branch lacks feature 2's marker" \
  "! git -C '$REMOTE_URL' cat-file -e '$PROGRAM_FEATURE_BRANCH_A:program-marker-$PROGRAM_FEATURE_BRANCH_B.txt'"
check "the program branch carries the briefs, committed" \
  "git -C '$REMOTE_URL' cat-file -e '$PROGRAM_BRANCH_ONE:plans/programs/$PROGRAM_SLUG_ONE/briefs/01-$PROGRAM_FIXTURE_ONE.md' && git -C '$REMOTE_URL' cat-file -e '$PROGRAM_BRANCH_ONE:plans/programs/$PROGRAM_SLUG_ONE/briefs/02-$PROGRAM_FIXTURE_TWO.md'"
check "the pushed orchestration record names both features" \
  "git -C '$REMOTE_URL' show '$PROGRAM_BRANCH_ONE:agentTooling/self/orchestrations/$PROGRAM_SLUG_ONE/README.md' | grep -q '$PROGRAM_FEATURE_SLUG_A' && git -C '$REMOTE_URL' show '$PROGRAM_BRANCH_ONE:agentTooling/self/orchestrations/$PROGRAM_SLUG_ONE/README.md' | grep -q '$PROGRAM_FEATURE_SLUG_B'"
check "the pinned copy's pin commit is on the program branch" \
  "git -C '$REPO' log --format=%s '$BASE_SHA..$PROGRAM_BRANCH_ONE' | grep -qF '$PIN_SUBJECT_PREFIX ${AT_HEAD:0:7}'"
check "SCORECARD.md has a Programs section naming the program" \
  "grep -q '$PROGRAM_SCORECARD_HEADING' '$PROGRAM_EXP_DIR/SCORECARD.md' && grep -q '$PROGRAM_NAME' '$PROGRAM_EXP_DIR/SCORECARD.md'"
check "the program worktree was removed" "[[ ! -d '$PROGRAM_TREE_ONE' ]]"
check "both feature worktrees were removed" "[[ ! -d '$PROGRAM_TREE_A' && ! -d '$PROGRAM_TREE_B' ]]"
check "the branches stay (they are the cost record)" \
  "git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_BRANCH_ONE && git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_FEATURE_BRANCH_A"
check "the program state records every program stage" \
  "[[ \$(jq -r '[.stages | to_entries[] | select(.value.outcome != null)] | length' '$PROGRAM_STATE_ONE') -ge 9 ]]"

# ── 9c2. An ordinary cell, priced end to end ───────────────────────────────────
# The same pipeline as the full run, but the implementer is the `direct` method's fake and
# every claude call leaves a billed transcript, so the implementer, review and rework sessions
# must each be claimed (the harness's own <primary>-<branch> tree) and priced by the capture.
# This is what fails if the capture's claim root regresses: the full run above asserts only 0s.
echo ""
echo "=== smoke: ordinary cell, priced end to end ==="
PRICED_CELL_DIR="$REPO/plans/experiments/$PRICED_CELL_EXPERIMENT"
mkdir -p "$PRICED_CELL_DIR"
jq --arg name "$PRICED_CELL_EXPERIMENT" --arg stem "$PRICED_CELL_STEM" --arg method "$PRICED_CELL_METHOD" --arg fx "$FIXTURE_NAME" \
  '.name = $name | .methods = [$method] | .branch_stem_override = {($fx): $stem}' \
  "$PIN_DIR/experiment.json" > "$PRICED_CELL_DIR/experiment.json"
PRICED_CELL_RESULTS="$PRICED_CELL_DIR/results.jsonl"
PRICED_CELL_OUT="$WORK/priced-cell-run.txt"
HOME="$PRICED_HOME" \
  SMOKE_PRICED_TRANSCRIPTS=1 \
  SMOKE_COST_MODEL="$(jq -r '.models | keys[0]' "$PRICED_RATES")" \
  SMOKE_COST_INPUT_TOKENS="$PROGRAM_PRICED_INPUT_TOKENS" SMOKE_COST_OUTPUT_TOKENS="$PROGRAM_PRICED_OUTPUT_TOKENS" \
  SMOKE_IMPL_REPORTED_USD="$PRICED_CELL_REPORTED_USD" \
  "$RUN" "$PRICED_CELL_DIR" --consumer "$REPO" > "$PRICED_CELL_OUT" 2>&1
priced_cell_rc=$?
if (( priced_cell_rc != 0 )); then
  echo "--- run output ---"
  cat "$PRICED_CELL_OUT"
  echo "------------------"
fi
priced_cell_row() { jq -e "$1" "$PRICED_CELL_RESULTS" >/dev/null; }
PRICED_CELL_CAPTURE_LOG="$PRICED_CELL_DIR/logs/$PRICED_CELL_BRANCH-capture.log"
check "priced cell: run exits 0" "(( $priced_cell_rc == 0 ))"
check "priced cell: one row, for the direct cell's branch" \
  "[[ -s '$PRICED_CELL_RESULTS' && \$(wc -l < '$PRICED_CELL_RESULTS') -eq 1 ]] && priced_cell_row '.branch == \"$PRICED_CELL_BRANCH\" and .slug == \"$PRICED_CELL_SLUG\" and .method == \"$PRICED_CELL_METHOD\" and .method_failed == false'"
check "priced cell: the review escalated, the rework ran, the probe passed" \
  "priced_cell_row '.review_escalated == 1 and .rework_ran == true and .accept_pass == true'"
check "priced cell: cost_method_usd > 0 (the implementer's session was claimed and priced)" "priced_cell_row '.cost_method_usd > 0'"
check "priced cell: cost_review_usd > 0 (the review's session was claimed and priced)" "priced_cell_row '.cost_review_usd > 0'"
check "priced cell: cost_rework_usd > 0 (the rework's session was claimed and priced)" "priced_cell_row '.cost_rework_usd > 0'"
check "priced cell: cost_green_usd == cost_method_usd + cost_review_usd + cost_rework_usd" \
  "priced_cell_row 'def ab: if . < 0 then -. else . end; ((.cost_green_usd - (.cost_method_usd + .cost_review_usd + .cost_rework_usd)) | ab) <= $ARITHMETIC_TOLERANCE'"
check "priced cell: cost_method_reported_usd is what the fake implementer reported" \
  "priced_cell_row '.cost_method_reported_usd == $PRICED_CELL_REPORTED_USD'"
check "priced cell: no unpriced warning (captured is not below what claude reported)" \
  "! grep -q '$PRICED_CELL_UNPRICED_PATTERN' '$PRICED_CELL_OUT'"
check "priced cell: the capture log exists" "[[ -s '$PRICED_CELL_CAPTURE_LOG' ]]"
check "priced cell: the capture log has no \"cannot claim\" / launched_elsewhere line" \
  "! grep -qE '$PRICED_CELL_UNCLAIMED_PATTERN' '$PRICED_CELL_CAPTURE_LOG'"

# ── 9c3. stages {review: false}, as a run ──────────────────────────────────────
# The dry run above asserts the flags the harness read; this asserts what a run does with
# them: a review that is not wanted leaves no stage, no brief, no manifest and no cost, and
# the rework that depends on its findings does not run either.
echo ""
echo "=== smoke: stages {review: false}, as a run ==="
NO_REVIEW_RUN_DIR="$REPO/plans/experiments/$NO_REVIEW_RUN_EXPERIMENT"
mkdir -p "$NO_REVIEW_RUN_DIR"
jq --arg name "$NO_REVIEW_RUN_EXPERIMENT" --arg stem "$NO_REVIEW_RUN_STEM" --arg fx "$FIXTURE_NAME" \
  '.name = $name | .stages = {review: false} | .branch_stem_override = {($fx): $stem}' \
  "$PIN_DIR/experiment.json" > "$NO_REVIEW_RUN_DIR/experiment.json"
NO_REVIEW_RUN_RESULTS="$NO_REVIEW_RUN_DIR/results.jsonl"
NO_REVIEW_RUN_STATE="$NO_REVIEW_RUN_DIR/state/$NO_REVIEW_RUN_BRANCH.json"
NO_REVIEW_RUN_OUT="$WORK/no-review-run.txt"
"$RUN" "$NO_REVIEW_RUN_DIR" --consumer "$REPO" > "$NO_REVIEW_RUN_OUT" 2>&1
no_review_run_rc=$?
if (( no_review_run_rc != 0 )); then
  echo "--- run output ---"
  cat "$NO_REVIEW_RUN_OUT"
  echo "------------------"
fi
no_review_row() { jq -e "$1" "$NO_REVIEW_RUN_RESULTS" >/dev/null; }
no_review_state() { jq -e "$1" "$NO_REVIEW_RUN_STATE" >/dev/null; }
check "no-review run: exits 0" "(( $no_review_run_rc == 0 ))"
check "no-review run: said the review stage was disabled" "grep -q 'review stage disabled' '$NO_REVIEW_RUN_OUT'"
check "no-review run: the state file records no review stage at all (it never began)" \
  "no_review_state '.stages | has(\"review\") | not'"
check "no-review run: ... no review end time, no review findings counts, and a review cost of 0 (the capture's)" \
  "no_review_state '(has(\"t_review_end\") or has(\"review_fixed\") or has(\"review_escalated\")) | not' && no_review_state '(.cost_review_usd | tonumber) == 0'"
check "no-review run: the rework did not run either (no findings to escalate): no rework stage" \
  "no_review_state '.stages | has(\"rework\") | not'"
check "no-review run: the stages that do not depend on the review still ran" \
  "no_review_state '.stages.setup.outcome == \"ok\" and .stages.method.outcome == \"ok\" and .stages.accept.outcome == \"pass\" and .stages.capture.outcome == \"ok\" and .stages.record.outcome == \"ok\"'"
check "no-review run: one row" "[[ -s '$NO_REVIEW_RUN_RESULTS' && \$(wc -l < '$NO_REVIEW_RUN_RESULTS') -eq 1 ]]"
check "no-review run: row: cost_review_usd == 0" "no_review_row '.cost_review_usd == 0'"
check "no-review run: row: review_escalated and review_fixed at their not-run value 0" \
  "no_review_row '.review_escalated == 0 and .review_fixed == 0'"
check "no-review run: row: rework_ran false, cost_rework_usd 0" "no_review_row '.rework_ran == false and .cost_rework_usd == 0'"
check "no-review run: row: no review end time, the probe still ran and passed" \
  "no_review_row '.t_review_end == \"\" and .t_rework_end == \"\" and .accept_pass == true and .method_failed == false'"
check "no-review run: no review prompt was written" "[[ ! -e '$NO_REVIEW_RUN_DIR/logs/$NO_REVIEW_RUN_BRANCH-review-prompt.md' ]]"
check "no-review run: the branch holds no review manifest" \
  "! git -C '$REPO' cat-file -e '$NO_REVIEW_RUN_BRANCH:plans/features/$NO_REVIEW_RUN_SLUG-review/README.md' 2>/dev/null"
check "no-review run: the branch holds no review findings" \
  "! git -C '$REPO' cat-file -e '$NO_REVIEW_RUN_BRANCH:plans/features/$NO_REVIEW_RUN_SLUG/review/findings.md' 2>/dev/null"
check "no-review run: the branch holds no rework manifest" \
  "! git -C '$REPO' cat-file -e '$NO_REVIEW_RUN_BRANCH:plans/features/$NO_REVIEW_RUN_SLUG-rework/README.md' 2>/dev/null"

# ── 9d. The same program, feature 1's implementer failing; --only; --from record ─
echo ""
echo "=== smoke: program cell, a failing implementer, --only, --from record ==="
PROGRAM_MIX_DIR="$REPO/plans/experiments/$PROGRAM_MIX_EXPERIMENT"
"$NEW_EXPERIMENT" "$PROGRAM_MIX_EXPERIMENT" --fixtures "$PROGRAM_FIXTURE_ONE" --methods null --programs "$PROGRAM_NAME" \
  --agent-tooling "$PROGRAM_ARM=HEAD" --override "$PROGRAM_NAME=$PROGRAM_MIX_STEM" \
  --prediction 'a failed first feature does not stop the second' --consumer "$REPO" > "$WORK/new-program-mix.txt" 2>&1
check "new-experiment for a cell and a program together exits 0" "(( $? == 0 ))"
PROGRAM_MIX_RESULTS="$PROGRAM_MIX_DIR/results.jsonl"
PROGRAM_MIX_SELECTOR="$PROGRAM_NAME:$PROGRAM_METHOD_NAME:$PROGRAM_ARM"
mix_row() { jq -e "$1" "$PROGRAM_MIX_RESULTS" >/dev/null; }

"$RUN" "$PROGRAM_MIX_DIR" --consumer "$REPO" --only "$PROGRAM_NAME" --dry-run > "$WORK/mix-dry-program.txt" 2>&1
check "--only <program> dry run selects the program cell" \
  "grep -q 'program branch: *$PROGRAM_MIX_BRANCH' '$WORK/mix-dry-program.txt'"
check "... and not the ordinary cell" "! grep -q 'branch:  *$PROGRAM_MIX_CELL_BRANCH' '$WORK/mix-dry-program.txt'"
"$RUN" "$PROGRAM_MIX_DIR" --consumer "$REPO" --only "$PROGRAM_FIXTURE_ONE" --dry-run > "$WORK/mix-dry-fixture.txt" 2>&1
check "--only <fixture> dry run selects the ordinary cell" \
  "grep -q 'branch:  *$PROGRAM_MIX_CELL_BRANCH' '$WORK/mix-dry-fixture.txt'"
check "... and not the program" "! grep -q 'program branch:' '$WORK/mix-dry-fixture.txt'"

export SMOKE_ORCH_LOG="$WORK/orchestrator-mix.log"
PROGRAM_MIX_OUT="$WORK/program-mix-run.txt"
SMOKE_IMPL_FAIL_FOR="$PROGRAM_MIX_FEATURE_BRANCH_A" \
  "$RUN" "$PROGRAM_MIX_DIR" --consumer "$REPO" --only "$PROGRAM_MIX_SELECTOR" > "$PROGRAM_MIX_OUT" 2>&1
program_mix_rc=$?
if [[ ! -s "$PROGRAM_MIX_RESULTS" ]]; then
  echo "--- run output (rc $program_mix_rc) ---"
  cat "$PROGRAM_MIX_OUT"
  echo "------------------"
fi
check "--only <program>:orchestrator wrote exactly one row" "[[ -s '$PROGRAM_MIX_RESULTS' && \$(wc -l < '$PROGRAM_MIX_RESULTS') -eq 1 ]]"
check "... the program's" "mix_row '.kind == \"program\" and .branch == \"$PROGRAM_MIX_BRANCH\"'"
check "... and the ordinary cell in the same experiment did not run (no branch, no state)" \
  "! git -C '$REPO' show-ref --verify --quiet refs/heads/$PROGRAM_MIX_CELL_BRANCH && [[ ! -e '$PROGRAM_MIX_DIR/state/$PROGRAM_MIX_CELL_BRANCH.json' ]]"
check "feature 1: method_failed true, no PR, brief was written" \
  "mix_row '.features[0].method_failed == true and .features[0].pr_url == \"\" and .features[0].brief_written == true and .features[0].green == false'"
check "feature 2 still ran: PR open, not failed" \
  "mix_row '.features[1].method_failed == false and .features[1].pr_url != \"\"'"
check "feature 2 was cut at feature 1's branch and targets it (dependency_ok true)" \
  "mix_row '.features[1].dependency_ok == true and .features[1].pr_base == \"$PROGRAM_MIX_FEATURE_BRANCH_A\"'"
check "row: features_pr_open 1, features_count 2" "mix_row '.features_pr_open == 1 and .features_count == 2'"
check "row: only feature 2 is green" "mix_row '.features_green == 1 and .features[1].green == true'"
check "row: the program itself did not fail (the orchestrator did its job)" "mix_row '.method_failed == false'"
check "no PR was opened for the failed feature" "[[ ! -e '$SMOKE_PR_DIR/$PROGRAM_MIX_FEATURE_BRANCH_A' ]]"
check "the failed feature's review did not run" \
  "! git -C '$REPO' show '$PROGRAM_MIX_FEATURE_BRANCH_A:plans/features/smoke-alpha-smoke-fail-head/review/findings.md' >/dev/null 2>&1"
check "the failed feature's worktree was removed too" "[[ ! -d '$REPO-$PROGRAM_MIX_FEATURE_BRANCH_A' && ! -d '$REPO-$PROGRAM_MIX_FEATURE_BRANCH_B' ]]"

FROM_RECORD_OUT="$WORK/program-from-record.txt"
"$RUN" "$PROGRAM_MIX_DIR" --consumer "$REPO" --only "$PROGRAM_MIX_SELECTOR" --from record > "$FROM_RECORD_OUT" 2>&1
from_record_rc=$?
check "--from record exits 0" "(( $from_record_rc == 0 ))"
check "... skipped every earlier stage" "! grep -q 'program stage setup' '$FROM_RECORD_OUT' && ! grep -q 'program stage loop' '$FROM_RECORD_OUT' && grep -q 'program stage record' '$FROM_RECORD_OUT'"
check "... appended a second row" "[[ \$(wc -l < '$PROGRAM_MIX_RESULTS') -eq 2 ]]"
check "... rebuilt from state: the same figures as the first row" \
  "[[ \"\$(sed -n 1p '$PROGRAM_MIX_RESULTS' | jq -c '[.features_count, .features_pr_open, .features_green, .orchestrator_sessions, [.features[].pr_base]]')\" == \"\$(sed -n 2p '$PROGRAM_MIX_RESULTS' | jq -c '[.features_count, .features_pr_open, .features_green, .orchestrator_sessions, [.features[].pr_base]]')\" ]]"

# ── 9d2. unpriced_reason: a feature with no manifest, and one the capture missed ─
echo ""
echo "=== smoke: program cell, unpriced features ==="
PROGRAM_UNPRICED_DIR="$REPO/plans/experiments/$PROGRAM_UNPRICED_EXPERIMENT"
"$NEW_EXPERIMENT" "$PROGRAM_UNPRICED_EXPERIMENT" --programs "$PROGRAM_NAME" --agent-tooling "$PROGRAM_ARM=HEAD" \
  --override "$PROGRAM_NAME=$PROGRAM_UNPRICED_STEM" \
  --prediction 'a feature that cannot be priced says why' --consumer "$REPO" > "$WORK/new-program-unpriced.txt" 2>&1
check "new-experiment for the unpriced program exits 0" "(( $? == 0 ))"
PROGRAM_UNPRICED_RESULTS="$PROGRAM_UNPRICED_DIR/results.jsonl"
unpriced_row() { jq -e "$1" "$PROGRAM_UNPRICED_RESULTS" >/dev/null; }
export SMOKE_ORCH_LOG="$WORK/orchestrator-unpriced.log"
PROGRAM_UNPRICED_OUT="$WORK/program-unpriced-run.txt"
# Feature 1's brief is never written (so no implementer runs and it has no manifest); feature 2's
# implementer reports spend, but nothing is filed where the capture looks (the run's HOME is the
# real one, which holds no transcript for these worktrees).
SMOKE_BRIEF_SKIP_FOR="$PROGRAM_UNPRICED_FEATURE_BRANCH_A" SMOKE_IMPL_REPORTED_USD="$PROGRAM_UNPRICED_REPORTED_USD" \
  "$RUN" "$PROGRAM_UNPRICED_DIR" --consumer "$REPO" > "$PROGRAM_UNPRICED_OUT" 2>&1
if [[ ! -s "$PROGRAM_UNPRICED_RESULTS" ]]; then
  echo "--- run output ---"
  cat "$PROGRAM_UNPRICED_OUT"
  echo "------------------"
fi
check "the unpriced program wrote a row" "[[ -s '$PROGRAM_UNPRICED_RESULTS' ]]"
check "feature 1 (brief never written, no manifest): unpriced_reason says no implementer ran" \
  "unpriced_row '.features[0].brief_written == false and (.features[0].unpriced_reason | type == \"string\" and contains(\"no implementer ran\"))'"
check "feature 2 (reported spend, nothing captured): unpriced_reason names both figures" \
  "unpriced_row '.features[1].cost_method_usd == 0 and (.features[1].unpriced_reason | type == \"string\" and contains(\"\$0 \") and contains(\"\$$PROGRAM_UNPRICED_REPORTED_USD\") and contains(\"missed the session\"))'"

# A first orchestrator call that was started and never counted: the next one gets a fresh id.
KILLED_STATE="$WORK/killed-first-call.json"
KILLED_OLD_ID="smoke-killed-first-call"
KILLED_STARTED="2030-06-01T10:00:00Z"
jq -n --arg id "$KILLED_OLD_ID" --arg s "$KILLED_STARTED" \
  '{session_id: $id, orchestrator_calls: 0, orchestrator_first_call_started: $s}' > "$KILLED_STATE"
( source "$HARNESS_DIR_UNDER_TEST/lib.sh"; source "$HARNESS_DIR_UNDER_TEST/program-stages.sh"
  PSTATE="$KILLED_STATE"; orch_replace_killed_session ) > "$WORK/killed-first-call.out" 2>&1
check "a killed first call: orch_replace_killed_session exits 0" "(( $? == 0 ))"
killed() { jq -e --arg o "$KILLED_OLD_ID" --arg s "$KILLED_STARTED" "$1" "$KILLED_STATE" >/dev/null; }
check "... a fresh session_id, distinct from the killed one" "killed '(.session_id | length) > 0 and .session_id != \$o'"
check "... the old id is in orchestrator_sessions[] with the marker's instant as its start" \
  "killed '.orchestrator_sessions[0] == \$o and .orchestrator_session_starts[\$o] == \$s and (.orchestrator_sessions | last) == .session_id'"
check "... an intervention names both ids" \
  "killed '. as \$r | (\$r.interventions | length) == 1 and (\$r.interventions[0].what | contains(\$o) and contains(\$r.session_id))'"
( source "$HARNESS_DIR_UNDER_TEST/lib.sh"; source "$HARNESS_DIR_UNDER_TEST/program-stages.sh"
  PSTATE="$KILLED_STATE"; orch_replace_killed_session ) > /dev/null 2>&1
check "... the marker is kept, so a second kill replaces again (three distinct ids)" \
  "killed '(.orchestrator_sessions | unique | length) == 3'"
check "the full run's program state carries the marker and counted all 4 orchestrator calls" \
  "jq -e '(.orchestrator_first_call_started | length) > 0 and .orchestrator_calls == 4' '$PROGRAM_STATE_ONE' >/dev/null"

# ── 9e. The version floor, the program checks and program_cost.py, directly ────
echo ""
echo "=== smoke: program cells (floor, checks, cost) ==="
FLOOR_PARENT="$(git -C "$AGENT_TOOLING_UNDER_TEST" log --diff-filter=A --format=%H -- "$PROGRAM_FLOOR_ADDED_FILE" 2>/dev/null | tail -1)"
FLOOR_REF=""
if [[ -n "$FLOOR_PARENT" ]]; then
  FLOOR_REF="$(git -C "$AGENT_TOOLING_UNDER_TEST" rev-parse --verify --quiet "$FLOOR_PARENT^" 2>/dev/null)"
fi
if [[ -z "$FLOOR_REF" ]]; then
  echo "  skip  floor refusal at new-experiment: the commit before $PROGRAM_FLOOR_ADDED_FILE was added is not in this (shallow?) history"
else
  FLOOR_OUT="$WORK/program-floor.txt"
  "$NEW_EXPERIMENT" "$PROGRAM_FLOOR_EXPERIMENT" --programs "$PROGRAM_NAME" --agent-tooling "$PROGRAM_FLOOR_ARM=$FLOOR_REF" \
    --prediction 'an arm below the floor is refused' --consumer "$REPO" > "$FLOOR_OUT" 2>&1
  floor_rc=$?
  check "new-experiment refuses an arm pinned below the version floor" "(( $floor_rc != 0 ))"
  check "... naming the missing file" "grep -qF '$PROGRAM_FLOOR_ADDED_FILE' '$FLOOR_OUT'"
  check "... and the arm" "grep -q 'arm $PROGRAM_FLOOR_ARM ' '$FLOOR_OUT'"
  check "... and wrote nothing" "[[ ! -e '$REPO/plans/experiments/$PROGRAM_FLOOR_EXPERIMENT' ]]"
fi

# harness_check_program_floor on a directory lacking each file in turn.
# CONSUMER_ROOT names the measured repository the way run.sh's --consumer does; the program
# and fixture checks compare a `repo` block against its origin.
lib_call() { ( CONSUMER_ROOT="$REPO"; source "$HARNESS_DIR_UNDER_TEST/lib.sh"; "$@" ) 2>&1; }
FLOOR_FILES="orchestration-start.sh templates/plans/ORCHESTRATOR_BRIEF.md"
FLOOR_CHECK_DIR="$WORK/floor-check"
mkdir -p "$FLOOR_CHECK_DIR/full/templates/plans"
for f in $FLOOR_FILES; do : > "$FLOOR_CHECK_DIR/full/$f"; done
lib_call harness_check_program_floor "$FLOOR_CHECK_DIR/full" "" > "$WORK/floor-full.txt"
check "harness_check_program_floor passes a tree carrying both files" "(( $? == 0 )) && [[ ! -s '$WORK/floor-full.txt' ]]"
floor_n=0
for missing in $FLOOR_FILES; do
  floor_n=$(( floor_n + 1 ))
  d="$FLOOR_CHECK_DIR/lacks$floor_n"
  mkdir -p "$d/templates/plans"
  for f in $FLOOR_FILES; do
    [[ "$f" == "$missing" ]] || : > "$d/$f"
  done
  lib_call harness_check_program_floor "$d" "$PROGRAM_FLOOR_ARM" > "$WORK/floor-lacks$floor_n.txt"
  floor_check_rc=$?
  check "harness_check_program_floor refuses a tree lacking $missing" "(( $floor_check_rc != 0 ))"
  check "... naming the file and the arm" "grep -qF '$missing' '$WORK/floor-lacks$floor_n.txt' && grep -q 'arm $PROGRAM_FLOOR_ARM ' '$WORK/floor-lacks$floor_n.txt'"
done
lib_call harness_check_program_floor "$FLOOR_CHECK_DIR/lacks1" "" > "$WORK/floor-lacks-unlabelled.txt"
check "... an unlabelled tree is named as the tree's own vendored copy" "grep -q 'vendored copy' '$WORK/floor-lacks-unlabelled.txt'"

# harness_program_check: the violations the rulings name, each on a fixtures directory of its own.
CHECK_DIR="$WORK/program-check"
CHECK_FIXTURES="$CHECK_DIR/fixtures"
CHECK_ALIEN="smokeAlien"
CHECK_OFFBASE="smokeOffBase"
CHECK_OFFBASE_SHA="0000000000000000000000000000000000000000"
mkdir -p "$CHECK_FIXTURES/$PROGRAM_FIXTURE_ONE" "$CHECK_FIXTURES/$PROGRAM_FIXTURE_TWO" "$CHECK_FIXTURES/$CHECK_ALIEN" "$CHECK_FIXTURES/$CHECK_OFFBASE"
cp "$PROGRAM_FIXTURES_DIR/$PROGRAM_FIXTURE_ONE/fixture.json" "$CHECK_FIXTURES/$PROGRAM_FIXTURE_ONE/"
cp "$PROGRAM_FIXTURES_DIR/$PROGRAM_FIXTURE_TWO/fixture.json" "$CHECK_FIXTURES/$PROGRAM_FIXTURE_TWO/"
jq '.repo.url = "https://github.com/someone/elsewhere.git"' "$PROGRAM_FIXTURES_DIR/$PROGRAM_FIXTURE_ONE/fixture.json" > "$CHECK_FIXTURES/$CHECK_ALIEN/fixture.json"
jq --arg b "$CHECK_OFFBASE_SHA" '.base = $b' "$PROGRAM_FIXTURES_DIR/$PROGRAM_FIXTURE_ONE/fixture.json" > "$CHECK_FIXTURES/$CHECK_OFFBASE/fixture.json"
program_variant() {  # $1 name, $2 jq filter over the real program.json
  jq "$2" "$PROGRAM_DIR/program.json" > "$CHECK_DIR/$1.json"
  lib_call harness_program_check "$CHECK_DIR/$1.json" "$CHECK_FIXTURES" > "$CHECK_DIR/$1.out"
}
program_variant valid '.'
check "harness_program_check passes the real program" "(( $? == 0 )) && ! grep -q . '$CHECK_DIR/valid.out'"
program_variant firstdep '.features[0].depends_on_previous = true'
check "harness_program_check refuses a first feature that depends on a previous one" \
  "(( $? != 0 )) && grep -q 'first feature cannot depend' '$CHECK_DIR/firstdep.out'"
program_variant duplicate ".features[1].fixture = \"$PROGRAM_FIXTURE_ONE\""
check "harness_program_check refuses a fixture listed twice" \
  "(( $? != 0 )) && grep -q 'fixture $PROGRAM_FIXTURE_ONE appears more than once' '$CHECK_DIR/duplicate.out'"
program_variant alien ".features[1].fixture = \"$CHECK_ALIEN\""
check "harness_program_check refuses a fixture on another repository" \
  "(( $? != 0 )) && grep -q 'fixture $CHECK_ALIEN is on repository' '$CHECK_DIR/alien.out'"
check "... the message names the consumer's repository, not the program's" \
  "grep -q 'not the consumer' '$CHECK_DIR/alien.out' && grep -q 'someone/elsewhere' '$CHECK_DIR/alien.out'"
program_variant ownurl ".repo = {url: \"$REMOTE_URL\", remote: \"origin\"}"
check "harness_program_check passes a program whose repo.url is the consumer's own origin" \
  "(( $? == 0 )) && ! grep -q . '$CHECK_DIR/ownurl.out'"
program_variant otherrepo ".repo = {url: \"$OTHER_REPO_URL\", remote: \"origin\"}"
check "harness_program_check refuses a program whose repo.url names another repository" \
  "(( $? != 0 )) && grep -q 'this program measures $OTHER_REPO_IDENTITY' '$CHECK_DIR/otherrepo.out'"
check "... and the remedy (run it there, in the programs directory)" \
  "grep -q '$OTHER_REPO_REMEDY' '$CHECK_DIR/otherrepo.out' && grep -q 'plans/experiments/programs/' '$CHECK_DIR/otherrepo.out'"
OTHER_PROGRAM_DIR="$REPO/plans/experiments/programs/$OTHER_PROGRAM"
mkdir -p "$OTHER_PROGRAM_DIR"
jq --arg name "$OTHER_PROGRAM" ".name = \$name | .repo = {url: \"$OTHER_REPO_URL\", remote: \"origin\"}" "$PROGRAM_DIR/program.json" > "$OTHER_PROGRAM_DIR/program.json"
"$NEW_EXPERIMENT" "$OTHER_PROGRAM_EXPERIMENT" --programs "$OTHER_PROGRAM" --agent-tooling "$PROGRAM_ARM=HEAD" \
  --prediction p --consumer "$REPO" > "$WORK/new-program-other-repo.txt" 2>&1
check "new-experiment --programs refuses a program on another repository, naming it" \
  "(( $? != 0 )) && grep -q '$OTHER_REPO_IDENTITY' '$WORK/new-program-other-repo.txt' && grep -q '$OTHER_REPO_REMEDY' '$WORK/new-program-other-repo.txt' && [[ ! -e '$REPO/plans/experiments/$OTHER_PROGRAM_EXPERIMENT' ]]"
program_variant offbase ".features[1].fixture = \"$CHECK_OFFBASE\""
check "harness_program_check passes a fixture with another base, warning once, naming it" \
  "(( $? == 0 )) && [[ \$(grep -c 'differs from the program' '$CHECK_DIR/offbase.out') -eq 1 ]] && grep -q '$CHECK_OFFBASE' '$CHECK_DIR/offbase.out'"
program_variant shortbase '.base = "abc123"'
check "harness_program_check refuses a base that is not a full commit id" \
  "(( $? != 0 )) && grep -q 'full 40-hex commit id' '$CHECK_DIR/shortbase.out'"
program_variant reserved '.features[1].method = "orchestrator"'
check "harness_program_check refuses a feature pinned to the reserved method" \
  "(( $? != 0 )) && grep -q 'not a choice a feature can pin' '$CHECK_DIR/reserved.out'"

# program_cost.py on a fabricated transcript tree: two responses an hour apart, priced at
# the first rate the history gives some model (read from it, never named here).
COST_PY="$HARNESS_DIR_UNDER_TEST/program_cost.py"
COST_ANALYSIS="$AGENT_TOOLING_UNDER_TEST/analysis"
COST_ROOT="$WORK/projects"
COST_MODEL="$(jq -r '.models | keys[0]' "$COST_ANALYSIS/rates_history.json")"
COST_RATE_IN="$(jq -r --arg m "$COST_MODEL" '.models[$m][-1].input' "$COST_ANALYSIS/rates_history.json")"
COST_RATE_OUT="$(jq -r --arg m "$COST_MODEL" '.models[$m][-1].output' "$COST_ANALYSIS/rates_history.json")"
cost_figure() {  # $1 number of responses priced
  awk -v n="$1" -v ri="$COST_RATE_IN" -v ro="$COST_RATE_OUT" -v ti="$COST_INPUT_TOKENS" -v to="$COST_OUTPUT_TOKENS" \
    'BEGIN { printf "%.4f", n * (ti * ri + to * ro) / 1000000 }'
}
cost_response() {  # $1 message id, $2 timestamp
  jq -c -n --arg id "$1" --arg ts "$2" --arg model "$COST_MODEL" --argjson i "$COST_INPUT_TOKENS" --argjson o "$COST_OUTPUT_TOKENS" \
    '{type: "assistant", timestamp: $ts, message: {id: $id, model: $model, usage: {input_tokens: $i, output_tokens: $o}}}'
}
mkdir -p "$COST_ROOT/project"
{ cost_response m1 "$COST_EARLY"; cost_response m2 "$COST_LATE"; } > "$COST_ROOT/project/$COST_SESSION_ONE.jsonl"
cost_response m3 "$COST_EARLY" > "$COST_ROOT/project/$COST_SESSION_TWO.jsonl"
cost_run() {  # session args…; prints the figure, warnings go to $COST_ERR
  python3 "$COST_PY" "$COST_ANALYSIS" "$@" --projects-root "$COST_ROOT" 2> "$COST_ERR"
}
COST_ERR="$WORK/program-cost.err"
check "the fabricated rate is a positive number" "awk -v r='$COST_RATE_IN' 'BEGIN { exit !(r > 0) }'"
check "program_cost.py prices a session's two responses" \
  "[[ \$(cost_run --session $COST_SESSION_ONE --from $COST_WINDOW_FROM --to $COST_WINDOW_TO) == '$(cost_figure 2)' ]]"
check "... a window ending between them prices one" \
  "[[ \$(cost_run --session $COST_SESSION_ONE --from $COST_WINDOW_FROM --to $COST_BETWEEN) == '$(cost_figure 1)' ]]"
check "... id@from narrows that id's window (the fork's replayed history is not counted)" \
  "[[ \$(cost_run --session $COST_SESSION_ONE@$COST_BETWEEN --from $COST_WINDOW_FROM --to $COST_WINDOW_TO) == '$(cost_figure 1)' ]]"
check "... ids are priced separately and summed, each with its own from" \
  "[[ \$(cost_run --session $COST_SESSION_ONE@$COST_BETWEEN --session $COST_SESSION_TWO --from $COST_WINDOW_FROM --to $COST_WINDOW_TO) == '$(cost_figure 2)' ]]"
check "... a missing id prices 0.0000" \
  "[[ \$(cost_run --session $COST_SESSION_MISSING --from $COST_WINDOW_FROM --to $COST_WINDOW_TO) == '0.0000' ]]"
check "... and warns, naming the id" "grep -q 'no transcript carries session $COST_SESSION_MISSING' '$COST_ERR'"
check "... a missing id beside a priced one adds nothing" \
  "[[ \$(cost_run --session $COST_SESSION_TWO --session $COST_SESSION_MISSING --from $COST_WINDOW_FROM --to $COST_WINDOW_TO) == '$(cost_figure 1)' ]]"
python3 "$COST_PY" "$WORK/no-analysis-here" --session x --from "$COST_WINDOW_FROM" --to "$COST_WINDOW_TO" > /dev/null 2>&1
check "... an analysis directory without capture_planning.py is a usage error (exit $COST_USAGE_EXIT)" "(( $? == $COST_USAGE_EXIT ))"
python3 "$COST_PY" "$COST_ANALYSIS" --session x --from not-a-time --to "$COST_WINDOW_TO" --projects-root "$COST_ROOT" > /dev/null 2>&1
check "... an unparseable --from is a usage error (exit $COST_USAGE_EXIT)" "(( $? == $COST_USAGE_EXIT ))"

echo ""
if (( failures > 0 )); then
  echo "=== smoke: $failures check(s) FAILED ==="
  exit 1
fi
echo "=== smoke: all checks passed ==="
