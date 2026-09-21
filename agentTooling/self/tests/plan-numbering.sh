#!/usr/bin/env bash
set -uo pipefail

# Self-test for feature-start.sh's plan numbering (self/PROJECT_FACTS.md → "Plan numbers
# are per feature, from 01"). Run by self/gate.sh, or by hand:
# bash self/tests/plan-numbering.sh
#
# The rule under test: a new feature's review stub is `01`, whatever another feature's
# corpus holds — self mode or the ordinary per-repo layout, empty corpus or not. This
# corpus used to number its plans as one sequence across every feature instead
# (`find | sed | sort -n` over the whole tree, with a `10#` guard against bash reading a
# leading zero as octal): two features started from the same base both saw the same
# highest number and both got highest-plus-one, twice, on 2026-09-17 — the sequence
# assumed only one feature would ever be mid-start — and a corpus past 99 held stems of
# two widths that every reader had to sort numerically rather than lexically just to stay
# consistent with itself. `lifecycle-records-and-numbering` deleted that branch:
# `feature-start.sh` writes `01-review-opus` unconditionally, in both modes, exactly as
# `AGENT_PLANS.md` → "Plan file format" already specified for a consuming repo. This test
# no longer reads the corpus at all — the phases below exist to prove that, by showing the
# stub is `01` even when another feature's corpus would have driven the old sequence
# somewhere else.
#
# Stands up two throwaway checkouts under mktemp -d, each a real git repo with a bare
# origin beside it, carrying the real feature-start.sh, plan-runner-roots.sh,
# analysis/{manifest,roots,pricing,transcript,routing}.py and the manifest template:
#
#   - a --self checkout: a standalone agentTooling clone, self/features at its root
#     (mirrors this repo's own layout);
#   - a "consumer" checkout: agentTooling vendored one directory down, plans/features at
#     the consumer's root (mirrors a repo that installed this subtree) — the layout
#     `feature-start.sh` resolves without --self (plan-runner-roots.sh's `resolve_roots`,
#     the "normal" branch).
#
# The corpus a start sees is whatever `main` holds, because the worktree is cut from
# origin/<base>; each phase rewrites it on main and pushes before starting. No model, no
# network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# copy_tooling <destination agentTooling dir> — the slice of this repo a start needs:
# the two scripts under test, the analysis modules manifest.py and routing.py import
# (routing.py rides along because a start derives its routing record from the running
# session's transcript, and without it every start here would print a warning it did not
# mean to test), and the manifest template.
copy_tooling() {
  local dest="$1"
  mkdir -p "$dest/analysis" "$dest/templates/plans/features"
  local f
  for f in feature-start.sh plan-runner-roots.sh; do
    cp "$HERE/$f" "$dest/$f" 2>/dev/null || true
  done
  for f in roots.py manifest.py pricing.py transcript.py routing.py; do
    cp "$HERE/analysis/$f" "$dest/analysis/$f" 2>/dev/null || true
  done
  cp "$HERE/templates/plans/features/TEMPLATE.md" \
    "$dest/templates/plans/features/TEMPLATE.md" 2>/dev/null || true
  chmod +x "$dest"/*.sh 2>/dev/null || true
}

# init_repo <checkout dir> <bare origin dir> — a real git repo on main, pushed to a bare
# origin, so the worktree a start cuts sees whatever main holds.
init_repo() {
  local checkout="$1" origin="$2"
  git -C "$checkout" init -q
  git -C "$checkout" symbolic-ref HEAD refs/heads/main
  git -C "$checkout" config user.email test@example.invalid
  git -C "$checkout" config user.name "plan numbering test"
  git -C "$checkout" add -A && git -C "$checkout" commit -q -m "init" >/dev/null 2>&1
  git init -q --bare "$origin"
  git -C "$checkout" remote add origin "$origin"
  git -C "$checkout" push -q -u origin main 2>/dev/null
}

# ── Self-mode checkout: a standalone agentTooling clone ───────────────────────
AT="$TMP/agentTooling"
AT_ORIGIN="$TMP/agentTooling-origin.git"
AT_FEATURES="$AT/self/features"
mkdir -p "$AT_FEATURES"
copy_tooling "$AT"
init_repo "$AT" "$AT_ORIGIN"

# ── Non-self checkout: a consumer repo with agentTooling vendored one level down ─
CONSUMER="$TMP/consumer"
CONSUMER_ORIGIN="$TMP/consumer-origin.git"
CONSUMER_AT="$CONSUMER/agentTooling"
CONSUMER_FEATURES="$CONSUMER/plans/features"
mkdir -p "$CONSUMER_FEATURES"
copy_tooling "$CONSUMER_AT"
init_repo "$CONSUMER" "$CONSUMER_ORIGIN"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# set_corpus <features dir> <checkout dir> <relative plan path>... — the plan files the
# base carries when the next start runs. Committed and pushed, since the new worktree is
# cut from origin/main.
set_corpus() {
  local features_dir="$1" checkout="$2"; shift 2
  rm -rf "${features_dir:?}"
  mkdir -p "$features_dir"
  local rel
  for rel in "$@"; do
    mkdir -p "$(dirname "$features_dir/$rel")"
    echo "a plan in another feature's corpus, to prove this one ignores it" \
      > "$features_dir/$rel"
  done
  git -C "$checkout" add -A
  git -C "$checkout" commit -q -m "corpus" >/dev/null 2>&1
  git -C "$checkout" push -q origin main 2>/dev/null
}

# next_stem <primary checkout> <slug> <features label> — the stem of the review stub a
# start writes, or "" if none. <features label> is "self/features" or "plans/features",
# the path a start's own worktree carries it at relative to itself in each mode.
next_stem() {
  local primary="$1" slug="$2" label="$3" stub
  stub="$(ls "$primary/.worktrees/$slug/$label/$slug/review/incomplete/"*.md 2>/dev/null | head -1)"
  [[ -n "$stub" ]] && basename "$stub" .md
}

# $HOME is redirected because a start derives its routing record from the running
# session's transcript, and no test may read the machine's own ~/.claude (README.md).
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
start_self() {
  ( cd "$TMP" && HOME="$FAKE_HOME" "$AT/feature-start.sh" --self "$1" --no-gate >/dev/null 2>&1 )
}
start_consumer() {
  ( cd "$TMP" && HOME="$FAKE_HOME" "$CONSUMER_AT/feature-start.sh" "$1" --no-gate >/dev/null 2>&1 )
}

echo "plan numbering"

# ── N1. an empty corpus, self mode ────────────────────────────────────────────
set_corpus "$AT_FEATURES" "$AT"
start_self numbering-empty
check "N1. self mode, empty corpus: the stub is 01" \
  '[[ "$(next_stem "$AT" numbering-empty "self/features")" == "01-review-opus" ]]'

# ── N2. another feature past the old sequence's two-digit width, self mode ────
set_corpus "$AT_FEATURES" "$AT" "old/auto/complete/104-build-sonnet.md"
start_self numbering-past-ninetynine
check "N2. self mode, another feature holding 104-x-opus.md: the stub is still 01" \
  '[[ "$(next_stem "$AT" numbering-past-ninetynine "self/features")" == "01-review-opus" ]]'

# ── N3. another feature at a leading-zero stem, self mode ─────────────────────
set_corpus "$AT_FEATURES" "$AT" "old/review/complete/08-review-opus.md"
start_self numbering-octal
check "N3. self mode, another feature holding 08-x-opus.md: the stub is still 01" \
  '[[ "$(next_stem "$AT" numbering-octal "self/features")" == "01-review-opus" ]]'

# ── N4. the ordinary per-repo layout, plans/features/, no --self ──────────────
set_corpus "$CONSUMER_FEATURES" "$CONSUMER"
start_consumer numbering-consumer
check "N4. the consuming-repo layout (plans/features/, no --self): the stub is 01" \
  '[[ "$(next_stem "$CONSUMER" numbering-consumer "plans/features")" == "01-review-opus" ]]'

if (( fails )); then echo "plan numbering: FAILED ($fails)"; exit 1; fi
echo "plan numbering: all checks passed"
