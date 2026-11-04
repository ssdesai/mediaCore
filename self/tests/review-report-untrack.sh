#!/usr/bin/env bash
set -uo pipefail

# Self-test for the live review report that must never be tracked
# (self/features/review-report-never-tracked/). Run by self/gate.sh, or by hand:
# bash self/tests/review-report-untrack.sh
#
# The bug: a consuming repo committed plans/review-report.md before the generated
# plans/.gitignore's `/review-report.md` line reached it. A .gitignore never untracks a
# tracked file, and run-review.sh's commit step is `git add -A`, so every round re-committed
# it and any two features reviewed at once conflicted on it at merge. The one-time repair
# lives in two places — run-review.sh's commit step and sync-plans.sh's write path —
# whichever an affected repo runs first.
#
# A consuming repo is built under mktemp -d with the runner, sync-plans.sh and
# templates/plans/ under agentTooling/, plans/review-report.md TRACKED on main and the
# template's plans/.gitignore beside it, and a stub `claude` that writes a clean verdict.
# Asserts:
#   U0. the premise: two branches that each rewrite the tracked report conflict on merge;
#   R1. a review on feature A untracks it: the pass says so, HEAD no longer carries it,
#       and the file is still on disk for feature-close.sh's PR body;
#   R2. the verdict's committed record: plans/features/A/review-report.md is in HEAD and
#       holds the verdict the pass wrote;
#   R3. the next `git add -A` commit, after the report is rewritten, does not re-add it;
#   R4. feature B, reviewed the same way off the same main, merges into main after A
#       with no conflict, and main ends with the report untracked;
#   R5. a tracked report nothing ignores is left tracked, and the pass says to run
#       sync-plans.sh — an untrack the next `git add -A` would undo is no repair;
#   S1. `sync-plans.sh --check` reports it TRACKED and changes nothing in the index;
#   S2. `sync-plans.sh` untracks it (UNTRACKED), leaves the file on disk, and leaves
#       tracked both a feature's own review-report.md and a file only the repo's root
#       .gitignore ignores — only plans/.gitignore's own patterns count.
#
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-report-untrack.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
SLUG_A="feat-a"
SLUG_B="feat-b"
REPORT="plans/review-report.md"
IGNORE_LINE="/review-report.md"
ROOT_IGNORED="plans/root-ignored.txt"
RUNNER_FILES=(run-review.sh plan-runner-lib.sh plan-runner-roots.sh stamp-timing.sh sync-plans.sh)
UNTRACK_WORDS="untracked $REPORT"
SYNC_HINT_WORDS="run sync-plans.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf 'Verdict: clean\n\n%s reviewed it.\n' "${REVIEWER:?}" > plans/review-report.md
printf '{"type":"result","total_cost_usd":0,"session_id":"stub"}\n'
STUB
chmod +x "$TMP/bin/claude"

gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
tracked() { [[ -n "$(git -C "$1" ls-files -- "$2")" ]]; }
in_head() { git -C "$1" cat-file -e "HEAD:$2" 2>/dev/null; }

# manifest <repo> <slug> — a started feature with one review plan queued
manifest() {
  mkdir -p "$1/plans/features/$2/review/incomplete"
  printf '# %s\n\n```json\n{"slug": "%s", "base": "%s", "branches": ["%s"], "plans": ["01-review-opus"]}\n```\n' \
    "$2" "$2" "$BASE" "$2" > "$1/plans/features/$2/README.md"
  printf '# 01 — review\n\nfeature: agentTooling/%s\n\nReview it.\n' "$2" \
    > "$1/plans/features/$2/review/incomplete/01-review-opus.md"
}

# fixture <name> [no-ignore] — the legacy state at $TMP/<name>: the report tracked on main
fixture() {
  local repo="$TMP/$1" f
  mkdir -p "$repo/agentTooling/templates" "$repo/plans"
  for f in "${RUNNER_FILES[@]}"; do cp "$HERE/$f" "$repo/agentTooling/$f"; done
  cp -R "$HERE/templates/plans" "$repo/agentTooling/templates/plans"
  chmod +x "$repo"/agentTooling/*.sh
  git init -q "$repo"
  gitq "$repo" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$repo" config user.email test@example.invalid
  gitq "$repo" config user.name "review report untrack test"
  printf 'Verdict: clean\n\nan old round.\n' > "$repo/$REPORT"
  gitq "$repo" add -A
  gitq "$repo" commit -q -m "import: review stamps"
  if [[ "${2:-}" == "no-ignore" ]]; then
    grep -vxF "$IGNORE_LINE" "$HERE/templates/plans/.gitignore" > "$repo/plans/.gitignore"
  else
    cp "$HERE/templates/plans/.gitignore" "$repo/plans/.gitignore"
  fi
  manifest "$repo" "$SLUG_A"
  manifest "$repo" "$SLUG_B"
  gitq "$repo" add -A
  gitq "$repo" commit -q -m "start features"
  echo "$repo"
}

# review <repo> <slug> — the pass, as a coordinator runs it, on the feature's branch
review() {
  ( cd "$1" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE=local REVIEWER="$2" \
      PATH="$TMP/bin:$PATH" agentTooling/run-review.sh "$2" 2>&1 )
}

echo "review-report-untrack"

# U0 — the premise, on the old behaviour: both branches commit their rewrite of the report
repo="$(fixture premise)"
gitq "$repo" checkout -q -b old-a
echo "a's verdict" > "$repo/$REPORT"; gitq "$repo" commit -q -am "old-a: review round 1"
gitq "$repo" checkout -q -b old-b "$BASE"
echo "b's verdict" > "$repo/$REPORT"; gitq "$repo" commit -q -am "old-b: review round 1"
gitq "$repo" checkout -q "$BASE"
gitq "$repo" merge -q --no-edit old-a
merge_rc=0; gitq "$repo" merge -q --no-edit old-b || merge_rc=$?
check "U0. premise: two branches rewriting the tracked report conflict on merge (merge rc $merge_rc)" \
  '(( merge_rc != 0 ))'

# R1–R4 — the fix
repo="$(fixture fixed)"
gitq "$repo" checkout -q -b "$SLUG_A"
out_a="$(review "$repo" "$SLUG_A")"
check "R1. the review untracks $REPORT and says so, and the file stays on disk" \
  'grep -qF "$UNTRACK_WORDS" <<<"$out_a" && ! in_head "$repo" "$REPORT" && ! tracked "$repo" "$REPORT" && [[ -f "$repo/$REPORT" ]]'
archived="plans/features/$SLUG_A/review-report.md"
check "R2. the round's verdict is committed at $archived, holding what the pass wrote" \
  'in_head "$repo" "$archived" && git -C "$repo" show "HEAD:$archived" 2>/dev/null | grep -qF "$SLUG_A reviewed it."'
echo "rewritten after the round" > "$repo/$REPORT"
echo "more work" > "$repo/work.txt"
gitq "$repo" add -A
gitq "$repo" commit -q -m "more work"
check "R3. the next git add -A commit does not re-add $REPORT" \
  '! in_head "$repo" "$REPORT" && ! tracked "$repo" "$REPORT"'
gitq "$repo" checkout -q -b "$SLUG_B" "$BASE"
out_b="$(review "$repo" "$SLUG_B")"
gitq "$repo" checkout -q "$BASE"
merge_a=0; gitq "$repo" merge -q --no-edit "$SLUG_A" || merge_a=$?
merge_b=0; gitq "$repo" merge -q --no-edit "$SLUG_B" || merge_b=$?
check "R4. features A and B both merge into $BASE with no conflict, and $BASE no longer tracks $REPORT (rc $merge_a/$merge_b)" \
  '(( merge_a == 0 && merge_b == 0 )) && grep -qF "$UNTRACK_WORDS" <<<"$out_b" && ! in_head "$repo" "$REPORT"'

# R5 — nothing ignores it yet: left tracked, and the pass points at sync-plans.sh
repo="$(fixture unignored no-ignore)"
gitq "$repo" checkout -q -b "$SLUG_A"
out="$(review "$repo" "$SLUG_A")"
check "R5. a tracked report nothing ignores stays tracked, and the pass says to run sync-plans.sh" \
  'tracked "$repo" "$REPORT" && grep -qF "$SYNC_HINT_WORDS" <<<"$out" && ! grep -qF "$UNTRACK_WORDS" <<<"$out"'

# S1–S2 — the same repair from sync-plans.sh
repo="$(fixture sync)"
mkdir -p "$repo/plans/features/$SLUG_A"
echo "a committed verdict" > "$repo/plans/features/$SLUG_A/review-report.md"
echo "root ignores me" > "$repo/$ROOT_IGNORED"
gitq "$repo" add -A
gitq "$repo" commit -q -m "a feature's record and a root-ignored file"
printf '%s\n' "$ROOT_IGNORED" > "$repo/.gitignore"
gitq "$repo" add .gitignore
gitq "$repo" commit -q -m "root ignore"
index_before="$(git -C "$repo" ls-files -s | cksum)"
out="$( (cd "$repo" && agentTooling/sync-plans.sh --check 2>&1) )"
check "S1. sync-plans.sh --check reports $REPORT TRACKED and changes nothing in the index" \
  'grep -qE "TRACKED +$REPORT" <<<"$out" && [[ "$(git -C "$repo" ls-files -s | cksum)" == "$index_before" ]]'
out="$( (cd "$repo" && agentTooling/sync-plans.sh 2>&1) )"
check "S2. sync-plans.sh untracks $REPORT (UNTRACKED), keeps the file, and leaves the feature's record and the root-ignored file tracked" \
  'grep -qE "UNTRACKED +$REPORT" <<<"$out" && ! tracked "$repo" "$REPORT" && [[ -f "$repo/$REPORT" ]] && tracked "$repo" "plans/features/$SLUG_A/review-report.md" && tracked "$repo" "$ROOT_IGNORED" && ! grep -qF "$ROOT_IGNORED" <<<"$out"'

echo ""
if (( fails )); then
  echo "review-report-untrack: $fails check(s) FAILED"
  exit 1
fi
echo "review-report-untrack: all checks passed"
