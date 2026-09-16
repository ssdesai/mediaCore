#!/usr/bin/env bash
set -uo pipefail

# Self-test for feature-start.sh's --self plan numbering (self/PROJECT_FACTS.md → "Plan
# numbers run as one sequence across this corpus"). Run by self/gate.sh, or by hand:
# bash self/tests/plan-numbering.sh
#
# Stands up a minimal throwaway agentTooling checkout under mktemp -d — a real git repo
# with a bare origin beside it, the real feature-start.sh, plan-runner-roots.sh,
# analysis/{manifest,roots}.py and the manifest template — and runs `feature-start.sh
# --self <slug> --no-gate` once per corpus state, reading the number off the review stub
# it writes. The corpus a start sees is whatever `main` holds, because the worktree is
# cut from origin/<base>; each phase rewrites it on main and pushes before starting.
#
# The rule under test: the next stem continues the corpus's own sequence, however many
# digits it has. Asserts that with 104-x-opus.md present the next stem is 105 — the
# two-digit `find`/`sed` this replaced saw nothing at all past 99 and handed out 100 a
# second time — that with only 08-x-opus.md present it is 09 (the `10#` guard: bash
# reads a leading zero as octal, and `08` would otherwise abort the start), that with a
# mixed corpus the highest is taken numerically rather than lexically (99 does not beat
# 104), and that an empty corpus starts at 01, two-digit padded. No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
ORIGIN="$TMP/origin.git"
FEATURES="$AT/self/features"
mkdir -p "$AT/analysis" "$FEATURES" "$AT/templates/plans/features"

for f in feature-start.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
# routing.py and its own imports ride along because the start writes a routing record for
# the session that ran it; without them every start here would print a warning it did not
# mean to test.
for f in roots.py manifest.py pricing.py transcript.py routing.py; do
  cp "$HERE/analysis/$f" "$AT/analysis/$f" 2>/dev/null || true
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md" 2>/dev/null || true
chmod +x "$AT"/*.sh 2>/dev/null || true

git -C "$AT" init -q
git -C "$AT" symbolic-ref HEAD refs/heads/main
git -C "$AT" config user.email test@example.invalid
git -C "$AT" config user.name "plan numbering test"
git -C "$AT" add -A && git -C "$AT" commit -q -m "init"
git init -q --bare "$ORIGIN"
git -C "$AT" remote add origin "$ORIGIN"
git -C "$AT" push -q -u origin main 2>/dev/null

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# set_corpus <relative plan path>... — the plan files main carries when the next start
# runs. Committed and pushed, since the new worktree is cut from origin/main.
set_corpus() {
  rm -rf "${FEATURES:?}"
  mkdir -p "$FEATURES"
  for rel in "$@"; do
    mkdir -p "$(dirname "$FEATURES/$rel")"
    echo "a plan in the corpus, so the sequence has something to continue" > "$FEATURES/$rel"
  done
  git -C "$AT" add -A
  git -C "$AT" commit -q -m "corpus" >/dev/null 2>&1
  git -C "$AT" push -q origin main 2>/dev/null
}

# next_stem <slug> — the stem of the review stub a start writes, or "" if none
next_stem() {
  local stub
  stub="$(ls "$AT/.worktrees/$1/self/features/$1/review/incomplete/"*.md 2>/dev/null | head -1)"
  [[ -n "$stub" ]] && basename "$stub" .md
}

# $HOME is redirected because the start derives its routing record from the running
# session's transcript, and no test may read the machine's own ~/.claude (README.md).
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
start() { ( cd "$TMP" && HOME="$FAKE_HOME" "$AT/feature-start.sh" --self "$1" --no-gate >/dev/null 2>&1 ); }

echo "plan numbering"

# ── N1. past 99 ───────────────────────────────────────────────────────────────
set_corpus "old/review/complete/07-review-opus.md" "old/auto/complete/104-build-sonnet.md"
start numbering-past-ninetynine
check "N1. with 104 in the corpus the next stem is 105" \
  '[[ "$(next_stem numbering-past-ninetynine)" == "105-review-opus" ]]'

# ── N2. the leading zero ──────────────────────────────────────────────────────
set_corpus "old/review/complete/08-review-opus.md"
start numbering-octal
check "N2. with only 08 in the corpus the next stem is 09, not an octal abort" \
  '[[ "$(next_stem numbering-octal)" == "09-review-opus" ]]'

# ── N3. numeric, not lexical ──────────────────────────────────────────────────
set_corpus "old/auto/complete/99-build-sonnet.md" "old/review/complete/104-review-opus.md" \
           "old/auto/complete/09-build-haiku.md"
start numbering-mixed
check "N3. the highest is taken numerically — 104 beats 99" \
  '[[ "$(next_stem numbering-mixed)" == "105-review-opus" ]]'

# ── N4. an empty corpus ───────────────────────────────────────────────────────
set_corpus
start numbering-empty
check "N4. with no plan at all the next stem is 01, two-digit padded" \
  '[[ "$(next_stem numbering-empty)" == "01-review-opus" ]]'

if (( fails )); then echo "plan numbering: FAILED ($fails)"; exit 1; fi
echo "plan numbering: all checks passed"
