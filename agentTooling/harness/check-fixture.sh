#!/usr/bin/env bash
set -uo pipefail

# Check a fixture is runnable before anything paid touches it.
#
#   harness/check-fixture.sh <name> [--consumer <path>]
#
# Run from the consuming repo root, with that repo's own vendored harness. Prints one line
# per check and exits with the number of failures, so `new-experiment.sh` and a person get
# the same answer. Dies at once on a fixture whose `repo` block names another repository
# than the consumer (an experiment runs from, and lives on, what it measures). Fails on: a
# fixture.json missing a field the stages read; a base or spec commit that does not resolve
# (the base in the consumer; the spec in the consumer, or in the checkout `spec.url`
# resolves to, cloned if need be; a bare `spec.repo` path is a warning); a spec path absent at the spec commit; a gate script absent at base; a
# facts.md or review-brief.md that is missing, empty, still carries the new-fixture stub
# (`@@TODO@@`) or uses a placeholder the harness does not fill; an accept.py that is
# missing, does not compile, or is still the stub. Warns (does not fail) on an
# abbreviated commit id, a base that no remote branch contains, and a spec section whose
# heading it cannot find.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_REQUIRED_TOOLS="jq git python3"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# The placeholders a fixture file may use; anything else at @@…@@ is a typo or a stub.
FIXTURE_PLACEHOLDERS="TREE SPEC_TREE GATE_COMMAND GATE_MINUTES"
STUB_MARKER="harness/new-fixture.sh stub"
FULL_SHA_RE='^[0-9a-f]{40}$'

NAME=""
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --consumer) CONSUMER_ROOT="$(cd "${2:?--consumer needs a path}" && pwd)"; shift 2 ;;
    -h|--help)  usage 0 ;;
    -*)         harness_die "unknown option: $1" ;;
    *)          [[ -z "$NAME" ]] || harness_die "unexpected argument: $1"
                NAME="$1"; shift ;;
  esac
done
[[ -n "$NAME" ]] || usage 1

harness_require_tools
harness_require_own_driver

FIXTURE_DIR="$CONSUMER_ROOT/plans/experiments/fixtures/$NAME"
FIXTURE_JSON="$FIXTURE_DIR/fixture.json"

failures=0
ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$(( failures + 1 )); }
warn() { printf '  warn  %s\n' "$1"; }

echo "=== check-fixture: $NAME ==="
[[ -d "$FIXTURE_DIR" ]] || harness_die "no fixture directory at $FIXTURE_DIR"
[[ -f "$FIXTURE_JSON" ]] || harness_die "no fixture.json in $FIXTURE_DIR"
jq -e . "$FIXTURE_JSON" >/dev/null 2>&1 || harness_die "fixture.json is not valid JSON"
# A fixture measures the consumer: a repo block naming another repository is refused here,
# the first point the fixture is read (an experiment runs from, and lives on, what it measures).
harness_check_measured_repo "$FIXTURE_JSON" fixture

# ── Fields the stages read ───────────────────────────────────────────────────
for field in .name .base .spec.commit .spec.path .gate.command .gate.green .branch_stem; do
  if [[ -n "$(harness_json "$FIXTURE_JSON" "$field")" ]]; then ok "fixture.json has $field"; else fail "fixture.json is missing $field"; fi
done
# The repositories: the fixture's own is the consumer (never resolved); only an external
# spec repository is resolved on this machine (by `spec.url`; a bare `spec.repo` path is
# the pre-URL shape and warns).
RESOLVE_ERR="$(mktemp "${TMPDIR:-/tmp}/check-fixture.XXXXXX")"
resolve_spec_field() {  # sets RESOLVED, prints the check
  RESOLVED=""
  if RESOLVED="$(harness_fixture_spec_repo "$FIXTURE_JSON" 2>"$RESOLVE_ERR")"; then
    # What the resolver did on the way (a clone, say) is worth a line here.
    sed -n 's/^=== harness: /  info  /p' "$RESOLVE_ERR"
    if ! harness_fixture_spec_external "$FIXTURE_JSON"; then
      ok "spec is taken from the consumer's own checkout ($RESOLVED)"
    elif [[ -n "$(harness_json "$FIXTURE_JSON" .spec.url)" ]]; then
      ok "spec.url resolves to a checkout here ($RESOLVED)"
    else
      warn "spec.repo is a path, not a URL — this machine's only; add spec.url (using $RESOLVED)"
    fi
  else
    fail "spec.url: $(grep -v '^===' "$RESOLVE_ERR" | tail -1)"
  fi
}
[[ "$(harness_json "$FIXTURE_JSON" .name)" == "$NAME" ]] && ok "name matches the directory" || fail "name in fixture.json is not $NAME"
jq -e '.spec.sections | type == "array"' "$FIXTURE_JSON" >/dev/null 2>&1 && ok "spec.sections is a list" || fail "spec.sections must be a list"
jq -e '.setup | type == "array"' "$FIXTURE_JSON" >/dev/null 2>&1 && ok "setup is a list" || fail "setup must be a list"
STEM="$(harness_json "$FIXTURE_JSON" .branch_stem)"
[[ "$STEM" =~ ^[a-z][A-Za-z0-9]*$ ]] && ok "branch_stem is bare camelCase" || fail "branch_stem must be bare camelCase with no user/ prefix: $STEM"

# ── Base ─────────────────────────────────────────────────────────────────────
REPO="$(harness_fixture_repo "$FIXTURE_JSON")"
ok "the fixture's repository is the consumer ($REPO)"
REMOTE="$(jq -r '.repo.remote // "origin"' "$FIXTURE_JSON")"
BASE="$(harness_json "$FIXTURE_JSON" .base)"
if [[ -n "$REPO" ]] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  ok "repo checkout is a git repository"
  git -C "$REPO" remote get-url "$REMOTE" >/dev/null 2>&1 && ok "repo has remote $REMOTE" || warn "repo has no remote $REMOTE (run.sh fetches from it)"
  if BASE_SHA="$(git -C "$REPO" rev-parse --verify --quiet "${BASE}^{commit}")"; then
    ok "base resolves ($BASE_SHA)"
    [[ "$BASE" =~ $FULL_SHA_RE ]] || warn "base is abbreviated ($BASE) — a full id cannot become ambiguous later"
    [[ -n "$(git -C "$REPO" branch -r --contains "$BASE_SHA" 2>/dev/null)" ]] && ok "base is on a remote branch" || warn "base is on no remote branch of $REPO"
    GATE_SCRIPT="$(harness_json "$FIXTURE_JSON" .gate.command)"; GATE_SCRIPT="${GATE_SCRIPT%% *}"; GATE_SCRIPT="${GATE_SCRIPT#./}"
    git -C "$REPO" cat-file -e "$BASE_SHA:$GATE_SCRIPT" 2>/dev/null && ok "gate script $GATE_SCRIPT exists at base" || fail "gate script $GATE_SCRIPT does not exist at base"
  else
    fail "base does not resolve in $REPO: $BASE"
  fi
elif [[ -n "$REPO" ]]; then
  fail "repo checkout is not a git repository: $REPO"
fi

# ── Spec ─────────────────────────────────────────────────────────────────────
resolve_spec_field
SPEC_REPO="$RESOLVED"
SPEC_COMMIT="$(harness_json "$FIXTURE_JSON" .spec.commit)"
SPEC_PATH="$(harness_json "$FIXTURE_JSON" .spec.path)"
if [[ -n "$SPEC_REPO" ]] && git -C "$SPEC_REPO" rev-parse --git-dir >/dev/null 2>&1; then
  ok "spec checkout is a git repository"
  if SPEC_SHA="$(git -C "$SPEC_REPO" rev-parse --verify --quiet "${SPEC_COMMIT}^{commit}")"; then
    ok "spec commit resolves ($SPEC_SHA)"
    [[ "$SPEC_COMMIT" =~ $FULL_SHA_RE ]] || warn "spec.commit is abbreviated ($SPEC_COMMIT)"
    if git -C "$SPEC_REPO" cat-file -e "$SPEC_SHA:$SPEC_PATH" 2>/dev/null; then
      ok "spec path exists at that commit"
      spec_text="$(git -C "$SPEC_REPO" show "$SPEC_SHA:$SPEC_PATH")"
      for section in $(jq -r '.spec.sections[]' "$FIXTURE_JSON"); do
        printf '%s\n' "$spec_text" | grep -qE "^#+[[:space:]]+§?${section//./\\.}([[:space:].:]|$)" \
          && ok "section $section has a heading" || warn "no heading found for section $section"
      done
    else
      fail "spec path $SPEC_PATH does not exist at $SPEC_SHA"
    fi
  else
    fail "spec commit does not resolve in $SPEC_REPO: $SPEC_COMMIT"
  fi
elif [[ -n "$SPEC_REPO" ]]; then
  fail "spec checkout is not a git repository: $SPEC_REPO"
fi
rm -f "$RESOLVE_ERR"

# ── The three files a person writes ──────────────────────────────────────────
check_prose() {
  local file="$1" label="$2" unknown
  if [[ ! -s "$FIXTURE_DIR/$file" ]]; then fail "$label is missing or empty"; return; fi
  if grep -q '@@TODO@@' "$FIXTURE_DIR/$file"; then fail "$label still carries the stub (@@TODO@@)"; return; fi
  unknown=""
  for placeholder in $(grep -oE '@@[A-Z_]+@@' "$FIXTURE_DIR/$file" | sort -u | sed 's/@@//g'); do
    [[ " $FIXTURE_PLACEHOLDERS " == *" $placeholder "* ]] || unknown+="$placeholder "
  done
  if [[ -n "$unknown" ]]; then fail "$label uses placeholder(s) the harness does not fill: $unknown"; else ok "$label is written (no stub, only known placeholders)"; fi
}
check_prose facts.md "facts.md"
check_prose review-brief.md "review-brief.md"

ACCEPT="$FIXTURE_DIR/accept/accept.py"
if [[ ! -s "$ACCEPT" ]]; then
  fail "accept/accept.py is missing"
elif grep -q "$STUB_MARKER" "$ACCEPT"; then
  fail "accept/accept.py is still the stub"
elif ! python3 -m py_compile "$ACCEPT" 2>/dev/null; then
  fail "accept/accept.py does not compile"
else
  ok "accept/accept.py compiles and is not the stub"
fi
rm -rf "$FIXTURE_DIR/accept/__pycache__"

[[ -s "$FIXTURE_DIR/README.md" ]] && ok "README.md exists" || fail "README.md is missing"
grep -q '@@TODO@@' "$FIXTURE_DIR/README.md" "$FIXTURE_DIR/accept/README.md" 2>/dev/null && warn "a README still carries @@TODO@@ lines"

echo ""
if (( failures > 0 )); then
  echo "=== check-fixture: $NAME — $failures check(s) FAILED ==="
  exit "$failures"
fi
echo "=== check-fixture: $NAME — all checks passed ==="
