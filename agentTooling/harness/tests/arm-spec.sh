#!/usr/bin/env bash
set -uo pipefail

# Per-arm specs (experiment.json arm_spec_paths): lib.sh's harness_check_arm_spec_paths,
# the shared-spec prompts byte for byte, and the arm-mode prompt texts.
#
#   harness/tests/arm-spec.sh
#   harness/tests/arm-spec.sh --write-expected [--from-ref <ref>]
#   harness/tests/arm-spec.sh --from-ref <ref>
#
# --write-expected writes the shared-mode fill to the expected file instead of comparing.
# --from-ref fills with the harness as it was at <ref> (byte-identity section only).
# No network, no money: a `mktemp -d` directory, removed on exit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

# Files
EXPECTED_FILE="$HARNESS_DIR/tests/arm-spec.shared.md"

# Fixtures
SHA_OLD="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_NEW="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
ARM_OLD="old"
ARM_NEW="new"
ARM_MID="mid"
PATH_OLD="spec.md"
PATH_NEW="spec/README.md"
FIXED_SIBLINGS="  - /fixed/sibling"
FIXED_TREE="/fixed/tree"
ARM_TREE="v-TREE"
GIT_USER="t"
GIT_EMAIL="t@t"
DIFF_LINES=40

# What lib.sh and the prompts say
MSG_NO_BASE_ARMS="needs base_arms"
TEXT_ARM_COPY="this arm's own copy"
TEXT_NEVER_EDITED="never to be"
TEXT_SHARED_ISOLATION="The read-only spec worktree at"
TEXT_SHARED_METHOD="out detached at the commit this experiment pins"
SOURCE_ARM="arm"
SOURCE_BOGUS="bogus"

# The prompts to fill, in order (relative to a harness dir)
PROMPTS=(
  methods/plans/template.md
  methods/direct/template.md
  methods/direct-bare/template.md
  methods/null/template.md
  templates/review-preamble.md
  templates/rework-preamble.md
)
METHOD_PROMPTS=(
  methods/plans/template.md
  methods/direct/template.md
  methods/direct-bare/template.md
  methods/vanilla/template.md
  methods/vanilla-conv/template.md
  methods/split-tests/template.md
)

# The scalar placeholders the fill loop reads (lib.sh harness_fill_template), less TREE and SIBLINGS
FILL_NAMES=(
  FACTS REVIEW_BRIEF FINDINGS_TEXT FEATURES RECORD_COMMANDS DEPENDS METHOD_CHOICE
  BRANCH BASE SLUG SPEC_TREE SPEC_PATH SPEC_SECTIONS
  GATE_COMMAND GATE_MINUTES FIXTURE EXPERIMENTS_DIR
  AGENT_TOOLING FINDINGS BRIEF
  PROGRAM PROGRAM_SLUG PROGRAM_BRANCH PROGRAM_TREE ARM FEATURE_COUNT POSITION
  PR_BASE PR_FIRST_LINE BRIEF_PATH BRIEF_DIR RECORD_PATH BRIEF_TEMPLATE
)

WRITE_EXPECTED=false
FROM_REF=""
while (( $# > 0 )); do
  case "$1" in
    --write-expected) WRITE_EXPECTED=true; shift ;;
    --from-ref)
      [[ $# -ge 2 && -n "$2" ]] || { echo "--from-ref needs a ref" >&2; exit 2; }
      FROM_REF="$2"; shift 2 ;;
    *) echo "usage: arm-spec.sh [--write-expected] [--from-ref <ref>]" >&2; exit 2 ;;
  esac
done

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
check() { if eval "$2"; then pass "$1"; else fail "$1 — [$2]"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/arm-spec.XXXXXX")"
[[ -n "$WORK" && -d "$WORK" ]] || { echo "could not make a work directory" >&2; exit 1; }
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

lib_call() { ( source "$HARNESS_DIR/lib.sh"; "$@" ) 2>&1; }

# ── harness_check_arm_spec_paths: shapes ─────────────────────────────────────
echo "=== arm-spec: harness_check_arm_spec_paths ==="
BASE="$(jq -cn --arg o "$SHA_OLD" --arg n "$SHA_NEW" --arg ao "$ARM_OLD" --arg an "$ARM_NEW" \
  '{($ao): $o, ($an): $n}')"

# ok_shape <base> <paths>: exit 0 and no output.
ok_shape() {
  local out rc
  out="$(lib_call harness_check_arm_spec_paths "$1" "$2")"; rc=$?
  (( rc == 0 )) && [[ -z "$out" ]]
}
# ok_exit <base> <paths>: exit 0.
ok_exit() { lib_call harness_check_arm_spec_paths "$1" "$2" >/dev/null; }
# bad_shape <base> <paths> [needle]: non-zero, and the output names <needle> when given.
bad_shape() {
  local out rc
  out="$(lib_call harness_check_arm_spec_paths "$1" "$2")"; rc=$?
  (( rc != 0 )) || return 1
  [[ -z "${3-}" ]] || grep -qF -- "$3" <<<"$out"
}

PATHS_OK="$(jq -cn --arg ao "$ARM_OLD" --arg an "$ARM_NEW" --arg po "$PATH_OLD" --arg pn "$PATH_NEW" \
  '{($ao): $po, ($an): $pn}')"
check "matching labels and relative paths: exit 0, no output" 'ok_shape "$BASE" "$PATHS_OK"'
check "empty object: exit 0" 'ok_exit "$BASE" "{}"'
check "literal null: exit 0" 'ok_exit "$BASE" "null"'
check "empty object with no base arms: exit 0" 'ok_exit "{}" "{}"'

check "no base arms with paths: non-zero, '$MSG_NO_BASE_ARMS'" \
  'bad_shape "{}" "$PATHS_OK" "$MSG_NO_BASE_ARMS"'

PATHS_EXTRA="$(jq -cn --arg ao "$ARM_OLD" --arg an "$ARM_NEW" --arg am "$ARM_MID" --arg po "$PATH_OLD" --arg pn "$PATH_NEW" \
  '{($ao): $po, ($an): $pn, ($am): "x.md"}')"
check "a label that is not a base arm: non-zero, names '$ARM_MID'" 'bad_shape "$BASE" "$PATHS_EXTRA" "$ARM_MID"'

PATHS_MISSING="$(jq -cn --arg ao "$ARM_OLD" --arg po "$PATH_OLD" '{($ao): $po}')"
check "a base arm with no path: non-zero, names '$ARM_NEW'" 'bad_shape "$BASE" "$PATHS_MISSING" "$ARM_NEW"'

for bad_path in "/abs/spec.md" "../spec.md" "spec/../x.md" "spec/.." ""; do
  bad_paths="$(jq -cn --arg ao "$ARM_OLD" --arg an "$ARM_NEW" --arg po "$PATH_OLD" --arg pn "$bad_path" \
    '{($ao): $po, ($an): $pn}')"
  if [[ -z "$bad_path" ]]; then
    check "empty path: non-zero" 'bad_shape "$BASE" "$bad_paths"'
  else
    check "path '$bad_path': non-zero, names the path" 'bad_shape "$BASE" "$bad_paths" "$bad_path"'
  fi
done

check "a non-string path: non-zero" 'bad_shape "$BASE" "{\"old\":1,\"new\":\"x\"}"'
check "a string instead of an object: non-zero" 'bad_shape "$BASE" "\"abc\""'

# ── fill_all: every prompt, shared mode ──────────────────────────────────────
# fill_all <harness dir>: fills the prompts with fixed values and prints them all.
fill_all() {
  local dir="$1"
  (
    source "$dir/lib.sh"
    if [[ ! -d "$WORK/repo/.git" ]]; then
      git init -q "$WORK/repo"
      git -C "$WORK/repo" -c user.name="$GIT_USER" -c user.email="$GIT_EMAIL" \
        commit -q --allow-empty -m init
    fi
    unset HARNESS_SPEC_SOURCE
    harness_build_isolation "$WORK/repo" "$WORK/repo"
    HARNESS_SIBLINGS="$FIXED_SIBLINGS"
    HARNESS_TREE="$FIXED_TREE"
    local name rel
    for name in "${FILL_NAMES[@]}"; do
      printf -v "HARNESS_$name" '%s' "v-$name"
    done
    HARNESS_PREV_OUTCOME="v-PREV_OUTCOME"
    for rel in "${PROMPTS[@]}"; do
      printf '===== %s =====\n' "$rel"
      harness_fill_template "$dir/$rel"
    done
  )
}

echo ""
echo "=== arm-spec: shared mode is byte for byte the base ==="
FILL_DIR="$HARNESS_DIR"
if [[ -n "$FROM_REF" ]]; then
  mkdir -p "$WORK/ref"
  # lib.sh sources ../plan-runner-lib.sh (and ../env-profile.sh), so both come too.
  if ! git -C "$REPO_ROOT" archive "$FROM_REF" harness plan-runner-lib.sh env-profile.sh | tar -x -C "$WORK/ref"; then
    echo "could not extract harness at $FROM_REF" >&2
    exit 2
  fi
  FILL_DIR="$WORK/ref/harness"
fi

if [[ "$WRITE_EXPECTED" == true ]]; then
  fill_all "$FILL_DIR" > "$EXPECTED_FILE" || { echo "fill failed" >&2; exit 1; }
  echo "wrote $EXPECTED_FILE"
  exit 0
fi

SHARED_OUT="$WORK/shared.out"
fill_all "$FILL_DIR" > "$SHARED_OUT" 2>&1
check "the expected file exists" '[[ -f "$EXPECTED_FILE" ]]'
if [[ -f "$EXPECTED_FILE" ]]; then
  if cmp -s "$EXPECTED_FILE" "$SHARED_OUT"; then
    pass "shared-mode prompts match the expected file"
  else
    diff -u "$EXPECTED_FILE" "$SHARED_OUT" | head -n "$DIFF_LINES"
    fail "shared-mode prompts match the expected file"
  fi
fi

# ── arm mode ─────────────────────────────────────────────────────────────────
echo ""
echo "=== arm-spec: arm mode ==="
# fill_arm <relative path>: one prompt, filled in arm mode.
fill_arm() {
  local rel="$1"
  (
    source "$HARNESS_DIR/lib.sh"
    if [[ ! -d "$WORK/repo/.git" ]]; then
      git init -q "$WORK/repo"
      git -C "$WORK/repo" -c user.name="$GIT_USER" -c user.email="$GIT_EMAIL" \
        commit -q --allow-empty -m init
    fi
    HARNESS_SPEC_SOURCE="$SOURCE_ARM"
    harness_build_isolation "$WORK/repo" "$WORK/repo"
    HARNESS_SIBLINGS="$FIXED_SIBLINGS"
    HARNESS_TREE="$FIXED_TREE"
    local name
    for name in "${FILL_NAMES[@]}"; do
      printf -v "HARNESS_$name" '%s' "v-$name"
    done
    HARNESS_SPEC_TREE="$ARM_TREE"
    HARNESS_SPEC_PATH="$PATH_NEW"
    HARNESS_PREV_OUTCOME="v-PREV_OUTCOME"
    harness_fill_template "$HARNESS_DIR/$rel"
  )
}

for rel in "${PROMPTS[@]}"; do
  out="$(fill_arm "$rel")"; rc=$?
  check "$rel: fills (exit 0)" '(( rc == 0 ))'
  check "$rel: no placeholder left" '! grep -qE "@@[A-Z_]+@@" <<<"$out"'
  if grep -q '^## Isolation' <<<"$out"; then
    check "$rel: isolation says '$TEXT_ARM_COPY'" 'grep -qF -- "$TEXT_ARM_COPY" <<<"$out"'
    check "$rel: isolation drops '$TEXT_SHARED_ISOLATION'" '! grep -qF -- "$TEXT_SHARED_ISOLATION" <<<"$out"'
  fi
done

for rel in "${METHOD_PROMPTS[@]}"; do
  out="$(fill_arm "$rel")"
  check "$rel: names $ARM_TREE/$PATH_NEW" 'grep -qF -- "$ARM_TREE/$PATH_NEW" <<<"$out"'
  check "$rel: says '$TEXT_NEVER_EDITED'" 'grep -qF -- "$TEXT_NEVER_EDITED" <<<"$out"'
  check "$rel: drops '$TEXT_SHARED_METHOD'" '! grep -qF -- "$TEXT_SHARED_METHOD" <<<"$out"'
done

# ── unknown source ───────────────────────────────────────────────────────────
echo ""
echo "=== arm-spec: unknown source ==="
bogus_isolation() {
  (
    source "$HARNESS_DIR/lib.sh"
    HARNESS_SPEC_SOURCE="$SOURCE_BOGUS"
    harness_build_isolation "$WORK/repo" "$WORK/repo"
  ) 2>&1
}
out="$(bogus_isolation)"; rc=$?
check "HARNESS_SPEC_SOURCE=$SOURCE_BOGUS: harness_build_isolation exits non-zero naming it" \
  '(( rc != 0 )) && grep -qF -- "$SOURCE_BOGUS" <<<"$out"'

echo ""
if (( failures > 0 )); then
  echo "arm-spec: $failures failed"
else
  echo "arm-spec: all passed"
fi
exit $(( failures > 0 ))
