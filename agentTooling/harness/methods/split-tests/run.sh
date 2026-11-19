#!/usr/bin/env bash
set -uo pipefail

# split-tests — vanilla-conv plus an independent test author: two fresh sessions, in
# sequence, in the same tree. The first writes the acceptance tests the spec implies and
# commits them alone; the second is vanilla-conv's implementer, told to make them pass.
#
#   run.sh <tree> <brief> <slug>
#
# <brief> is the harness's fill of template.md, which carries BOTH briefs: the test
# author's above the BRIEF_SPLIT_MARKER line, the implementer's below it (README.md says
# why one file). The harness has already filled every @@NAME@@ in both and refused an
# unfilled one; the implementer's one slot this script fills, TESTS_SHA_SLOT, is the sha
# of the author's commit, which exists only once the author has run.
#
# Side outputs go in the cell's log directory (HARNESS_LOG_DIR), never in the tree — a
# dirty path there stops feature-close.sh (../plans/run.sh says how that was learned):
#   <branch>-author-brief.md, <branch>-implementer-brief.md   the two briefs as sent
#   <branch>-author-result.json                               the author's result object
#   <branch>-author-start                                     HEAD before the author ran
#   <branch>-test-diff.txt    git diff --stat <tests sha>..HEAD -- <the authored files>:
#                             what the implementer did to the tests; empty = untouched
# HARNESS_METHOD_RESULT gets the implementer's result (or the author's, on the author's
# usage-limit stop, so the harness reads the reset time from it).
#
# Exit 0 = PR open, 2 = usage-limit stop (resumable), 1 = work failure (do not retry),
# the convention harness/SPEC.md §1 pins and plan-runner-lib.sh already uses. Also 1: an
# author who commits nothing, commits a file that is neither a test nor the README.md of a
# folder holding one of its tests, commits after its tests commit, or leaves other work
# uncommitted in the tree — the last two checked on its usage-limit stop too, once its tests
# commit exists, since the re-entry then goes straight to the implementer.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib.sh
source "$SCRIPT_DIR/../../lib.sh"

TREE="${1:?tree required}"
BRIEF="${2:?brief required}"
SLUG="${3:?slug required}"

# The two briefs in one template: the line between them, and the implementer's own slot
BRIEF_SPLIT_MARKER='<!-- split-tests: the implementer brief starts on the next line -->'
TESTS_SHA_SLOT='%%TESTS_SHA%%'
UNFILLED_PLACEHOLDER_RE='@@[A-Z_]+@@'
# The subject the author's commit carries (both briefs name it)
TESTS_SUBJECT="$SLUG: acceptance tests"
# A test file: a directory on its path is one of these, or its name has a test's shape
# (conftest.py is pytest's test support, wherever a repo keeps it)
TEST_DIR_RE='(^|/)(tests?|__tests__|e2e)/'
TEST_NAME_RE='(^|/)(test_[^/]*|conftest\.py|[^/]*_test\.[^/]*|[^/]*\.(test|spec)\.[^/]*|[^/]*Tests?\.[^/]*)$'
# The folder index the brief asks the author to keep: allowed beside a test file the same
# commit adds or changes, so a repo that keeps tests next to their source is not refused
TEST_README_NAME='README.md'

LOG_DIR="${HARNESS_LOG_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$LOG_DIR"
STEM="${HARNESS_BRANCH_NAME:-$SLUG}"
AUTHOR_BRIEF="$LOG_DIR/$STEM-author-brief.md"
IMPLEMENTER_BRIEF="$LOG_DIR/$STEM-implementer-brief.md"
AUTHOR_RESULT="$LOG_DIR/$STEM-author-result.json"
AUTHOR_START="$LOG_DIR/$STEM-author-start"
TEST_DIFF="$LOG_DIR/$STEM-test-diff.txt"
RESULT="${HARNESS_METHOD_RESULT:-$(mktemp "${TMPDIR:-/tmp}/harness-split-tests.XXXXXX")}"
# Every session the same as vanilla-conv's one
CLAUDE_FLAGS=(--model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash)

fail() { harness_warn "split-tests: $*"; exit "$METHOD_FAILED_RC"; }

# ── 1. Split the brief ───────────────────────────────────────────────────────
markers="$(grep -cxF -- "$BRIEF_SPLIT_MARKER" "$BRIEF")"
[[ "$markers" == 1 ]] || fail "$BRIEF carries the split marker $markers time(s), not once"
awk -v m="$BRIEF_SPLIT_MARKER" '$0 == m { exit } { print }' "$BRIEF" > "$AUTHOR_BRIEF"
IMPLEMENTER_TEXT="$(awk -v m="$BRIEF_SPLIT_MARKER" 'seen { print } $0 == m { seen = 1 }' "$BRIEF")"
[[ "$IMPLEMENTER_TEXT" == *"$TESTS_SHA_SLOT"* ]] || fail "the implementer brief has no $TESTS_SHA_SLOT slot"
if grep -qE "$UNFILLED_PLACEHOLDER_RE" "$BRIEF"; then
  fail "unfilled placeholder(s) in $BRIEF: $(grep -oE "$UNFILLED_PLACEHOLDER_RE" "$BRIEF" | sort -u | tr '\n' ' ')"
fi

is_test_path() { [[ "$1" =~ $TEST_DIR_RE || "$1" =~ $TEST_NAME_RE ]]; }

# The newest commit in <start>..HEAD whose subject is TESTS_SUBJECT, or nothing.
tests_commit() {
  git -C "$TREE" log --format='%H%x09%s' "$1..HEAD" 2>/dev/null \
    | awk -F '\t' -v s="$TESTS_SUBJECT" '$2 == s { print $1; exit }'
}

# Everything git would show as changed or new, the harness's own feature directory aside
# (its manifest and BRIEF.md are untracked there while the method runs).
dirty_paths() {
  git -C "$TREE" status --porcelain --untracked-files=all | cut -c4- \
    | grep -vE "^plans/features/$SLUG/"
  return 0
}

# Refuses paths the author left dirty that were not dirty before it ran (dirty_before).
refuse_author_leftovers() {
  local left
  left="$(comm -13 <(printf '%s\n' "$dirty_before" | sort) <(dirty_paths | sort) | grep -v '^$' | tr '\n' ' ')"
  [[ -z "$left" ]] || fail "the test author left work uncommitted$1: $left"
}

# ── 2. The test author ───────────────────────────────────────────────────────
# A usage-limit stop makes the harness run this script again. The HEAD the first author
# started from is kept, so a re-entry finds the author's commit and goes straight to the
# implementer instead of authoring a second set of tests.
START=""
if [[ -s "$AUTHOR_START" ]]; then START="$(cat "$AUTHOR_START")"; fi
# One left by a cell since reset is not on this tree's line, and is not this run's start.
if [[ -n "$START" ]] && git -C "$TREE" merge-base --is-ancestor "$START" HEAD 2>/dev/null; then
  harness_log "split-tests: re-entered; the test author started at ${START:0:12}"
else
  START="$(git -C "$TREE" rev-parse HEAD)" || fail "$TREE is not a git checkout"
  printf '%s\n' "$START" > "$AUTHOR_START"
fi

TESTS_SHA="$(tests_commit "$START")"
if [[ -n "$TESTS_SHA" ]]; then
  harness_log "split-tests: '$TESTS_SUBJECT' is already ${TESTS_SHA:0:12} — re-entered, implementer only"
else
  dirty_before="$(dirty_paths)"
  harness_log "split-tests: test author on $SLUG (model $HARNESS_MODEL, no budget cap)"
  harness_claude "$AUTHOR_RESULT" "$AUTHOR_BRIEF" "$TREE" "${CLAUDE_FLAGS[@]}"
  rc=$?
  harness_claude_text "$AUTHOR_RESULT"
  if (( rc != 0 )); then
    if harness_stopped_on_usage_limit "$AUTHOR_RESULT"; then
      # The re-entry trusts a tests commit it finds and goes straight to the implementer,
      # so once that commit exists the author's work is checked here, while it can still
      # be told apart from an implementer's: no commit after it, nothing left uncommitted.
      limit_sha="$(tests_commit "$START")"
      if [[ -n "$limit_sha" ]]; then
        if [[ "$limit_sha" != "$(git -C "$TREE" rev-parse HEAD)" ]]; then
          fail "the test author committed after '$TESTS_SUBJECT' before its usage limit ($(git -C "$TREE" log --format=%s "$limit_sha..HEAD" | tr '\n' ';'))"
        fi
        refuse_author_leftovers " before its usage limit"
      fi
      cp "$AUTHOR_RESULT" "$RESULT"
      harness_log "split-tests: test author stopped on a usage limit"
      exit "$METHOD_USAGE_LIMIT_RC"
    fi
    fail "test author: claude exited $rc"
  fi
  [[ "$(git -C "$TREE" rev-parse HEAD)" != "$START" ]] || fail "the test author committed nothing"
  TESTS_SHA="$(tests_commit "$START")"
  [[ -n "$TESTS_SHA" ]] || fail "the test author made no commit with the subject '$TESTS_SUBJECT'"
  [[ "$TESTS_SHA" == "$(git -C "$TREE" rev-parse HEAD)" ]] \
    || fail "the test author committed after '$TESTS_SUBJECT' ($(git -C "$TREE" log --format=%s "$TESTS_SHA..HEAD" | tr '\n' ';'))"
  refuse_author_leftovers ""
fi

# Every path the author's commits changed. A non-test path passes only as the folder
# README beside a test file of the same range; anything else is refused.
TEST_FILES=()
other=()
test_dirs=" "
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  TEST_FILES+=("$path")
  if is_test_path "$path"; then
    test_dirs="$test_dirs$(dirname "$path")/ "
  else
    other+=("$path")
  fi
done < <(git -C "$TREE" diff --no-renames --name-only "$START" "$TESTS_SHA")
non_test=()
for path in ${other[@]+"${other[@]}"}; do
  if [[ "$(basename "$path")" == "$TEST_README_NAME" && "$test_dirs" == *" $(dirname "$path")/ "* ]]; then
    continue
  fi
  non_test+=("$path")
done
(( ${#TEST_FILES[@]} > 0 )) || fail "'$TESTS_SUBJECT' (${TESTS_SHA:0:12}) changes no file"
(( ${#non_test[@]} == 0 )) || fail "'$TESTS_SUBJECT' (${TESTS_SHA:0:12}) carries non-test file(s): ${non_test[*]}"
harness_log "split-tests: acceptance tests ${TESTS_SHA:0:12}: ${TEST_FILES[*]}"

# ── 3. The implementer ───────────────────────────────────────────────────────
harness_replace_literal "$IMPLEMENTER_TEXT" "$TESTS_SHA_SLOT" "$TESTS_SHA"
printf '%s\n' "$HARNESS_REPLACED" > "$IMPLEMENTER_BRIEF"

harness_log "split-tests: implementer on $SLUG (model $HARNESS_MODEL, no budget cap)"
harness_claude "$RESULT" "$IMPLEMENTER_BRIEF" "$TREE" "${CLAUDE_FLAGS[@]}"
rc=$?
harness_claude_text "$RESULT"

# What the implementer did to the authored tests, written whatever its exit.
git -C "$TREE" diff --stat "$TESTS_SHA..HEAD" -- "${TEST_FILES[@]}" > "$TEST_DIFF"
if [[ -s "$TEST_DIFF" ]]; then
  harness_log "split-tests: the implementer changed the acceptance tests — $TEST_DIFF"
else
  harness_log "split-tests: the implementer left the acceptance tests untouched — $TEST_DIFF (empty)"
fi

if (( rc != 0 )); then
  if harness_stopped_on_usage_limit "$RESULT"; then
    harness_log "split-tests: implementer stopped on a usage limit"
    exit "$METHOD_USAGE_LIMIT_RC"
  fi
  fail "implementer: claude exited $rc"
fi
exit "$METHOD_OK_RC"
