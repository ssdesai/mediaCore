#!/usr/bin/env bash
set -uo pipefail

# Self-test for the PR body refresh (self/features/pr-body-refresh/): a feature is a
# sequence of rounds, every round's close calls the same `pr.sh <slug> <body-file>`, and
# from template-version 7 a PR an earlier round opened has its body replaced with the
# current round's — `forge.sh pr-edit <pr-url> <body-file>`, a PATCH of
# /repos/{o}/{r}/pulls/{n}. Run by self/gate.sh, or by hand:
# bash self/tests/pr-body-refresh.sh
#
# Part R — both pr.sh copies (self/pr.sh and templates/plans/pr.sh), each run from a
# throwaway repo with a bare origin, FORGE_SCRIPT naming a stub forge that logs every
# verb and the bytes of every body file it is handed, and a stub `gh` on PATH only so the
# "no forge CLI" skip does not fire. For each copy:
#   R1. already open: exit 0, `pr-edit <url> <the body file it was given>` called with
#       the report's bytes, `already open, body refreshed: <url>` printed, no pr-open;
#   R2. already open with no report written: the refresh still runs, with the fallback
#       body (the same one a fresh open would send);
#   R3. pr-edit refused: exit 1, a `fail` line naming pr-edit, no `body refreshed`
#       line, no pr-open, and the url on a `  pr      already open, body NOT refreshed:`
#       line — pr.sh's stdout contract puts a url only on `  pr ` lines;
#   R4. nothing open: unchanged — pr-open called with the body file, pr-edit not,
#       the new url printed, exit 0.
#
# Part E — forge.sh pr-edit itself, copied to the root of a throwaway checkout whose
# origin is https://github.com/<o>/<r>.git, with a stub `gh` that logs its argv. Under
# each profile (local, then cloud — the same REST path in both, no split):
#   E1. a PATCH of repos/<o>/<r>/pulls/<n>, the number taken from the url, the body sent
#       as `-F body=@<file>` with quotes, `$(…)` and backticks unexpanded; the url printed;
#   E2. a url that does not end in a number: exit 1, no gh call;
#   E3. a missing body file: exit 1, no gh call;
#   E4. a failed call: exit 1, the message naming PATCH and the endpoint;
#   E5. an answer with no html_url: exit 1;
#   E6. too few arguments: exit 2;
#   E7. no call was `gh pr …`, `gh auth status` or GraphQL.
#
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pr-body-refresh.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
BRANCH="claude/feat-refresh"
SLUG="feat-refresh"
OPEN_URL="https://example.invalid/o/r/pull/7"
NEW_URL="https://example.invalid/o/r/pull/8"
PR_COPIES=(self/pr.sh templates/plans/pr.sh)
REPORT_TEXT='Verdict: clean

Round 2 — the body a human approves now, not round 1'"'"'s.'
FALLBACK_WORDS="No review report was written"
FORGE_OWNER="forge-owner"
FORGE_REPO="forge-repo"
EDIT_PR_NUMBER="42"
EDIT_PR_URL="https://github.com/$FORGE_OWNER/$FORGE_REPO/pull/$EDIT_PR_NUMBER"
# A body whose bytes a shell would mangle if it ever read them
TRICKY_BODY='Verdict: clean
quotes " and '"'"', a $(touch should-not-exist) and a `backtick`'
FORGE_FILES=(forge.sh env-profile.sh hooks/env_profile.py)
PROFILES=(local cloud)
FORBIDDEN_GH_CALL_RE='^(pr |auth |api graphql)'

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# The profile is forced per call, never inherited from the machine (self/tests/README.md).
unset CLAUDE_CODE_REMOTE
export AGENTTOOLING_PROFILE=local

mkdir -p "$TMP/bin"
# Stub forge for Part R: logs `<verb> <args…>`, writes the body file's bytes to
# FORGE_BODY_OUT, answers pr-find with STUB_OPEN_URL (nothing when unset), pr-edit with
# its url or STUB_EDIT_RC, pr-open with STUB_NEW_URL.
cat > "$TMP/bin/forge-stub" <<'STUB'
#!/usr/bin/env bash
verb="$1"; shift
echo "$verb $*" >> "${FORGE_LOG:?}"
case "$verb" in
  pr-find)
    if [[ -n "${STUB_OPEN_URL:-}" ]]; then echo "$STUB_OPEN_URL"; fi
    exit 0 ;;
  pr-edit)
    cat "$2" > "${FORGE_BODY_OUT:?}"
    if [[ "${STUB_EDIT_RC:-0}" != "0" ]]; then
      echo "  forge     PATCH refused by the stub" >&2
      exit "$STUB_EDIT_RC"
    fi
    echo "$1"; exit 0 ;;
  pr-open)
    cat "$4" > "${FORGE_BODY_OUT:?}"
    echo "${STUB_NEW_URL:?}"; exit 0 ;;
esac
exit 2
STUB
# Stub gh: logs its argv; for `api`, writes the `-F body=@<file>` bytes to GH_BODY_OUT,
# fails with GH_RC, answers nothing under GH_NO_URL, else the PR's url.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_ARGV_LOG:?}"
if [[ "${1:-}" != "api" ]]; then exit 0; fi
shift
while (( $# )); do
  case "$1" in
    -F|--field)
      if [[ "$2" == body=@* ]]; then
        body_file="${2#body=@}"
        cat "$body_file" > "${GH_BODY_OUT:?}"
      fi
      shift 2 ;;
    *) shift ;;
  esac
done
if [[ "${GH_RC:-0}" != "0" ]]; then echo "gh: stubbed REST failure (HTTP 502)" >&2; exit "$GH_RC"; fi
if [[ -n "${GH_NO_URL:-}" ]]; then exit 0; fi
echo "${GH_STUB_URL:?}"
STUB
chmod +x "$TMP/bin/forge-stub" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export FORGE_LOG="$TMP/forge.log" FORGE_BODY_OUT="$TMP/forge-body.out"
export GH_ARGV_LOG="$TMP/gh-argv.log" GH_BODY_OUT="$TMP/gh-body.out"
export GH_STUB_URL="$EDIT_PR_URL"

gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ── R. both pr.sh copies against the stub forge ─────────────────────────────────
REPO="$TMP/repo"
ORIGIN="$TMP/origin.git"
git init -q --bare "$ORIGIN"
git init -q "$REPO"
gitq "$REPO" symbolic-ref HEAD "refs/heads/$BASE"
gitq "$REPO" config user.email test@example.invalid
gitq "$REPO" config user.name test
echo seed > "$REPO/seed.txt"
gitq "$REPO" add -A
gitq "$REPO" commit -q -m seed
gitq "$REPO" remote add origin "$ORIGIN"
gitq "$REPO" checkout -q -b "$BRANCH"
REPORT="$TMP/review-report.md"
printf '%s\n' "$REPORT_TEXT" > "$REPORT"

# run_pr <copy> [<body-file>] — the copy from the repo root, as the close runs it.
run_pr() {
  (
    cd "$REPO" || exit 97
    FEATURE_BASE="$BASE" FORGE_SCRIPT="$TMP/bin/forge-stub" STUB_NEW_URL="$NEW_URL" \
      "$HERE/$1" "$SLUG" "${@:2}" 2>&1
  )
}
reset_logs() { : > "$FORGE_LOG"; rm -f "$FORGE_BODY_OUT"; }

for copy in "${PR_COPIES[@]}"; do
  echo "pr-body-refresh: $copy"

  reset_logs
  out="$(STUB_OPEN_URL="$OPEN_URL" run_pr "$copy" "$REPORT")"; rc=$?
  check "R1a. $copy: already open exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
  check "R1b. ... calling pr-edit with the url and the body file it was given" \
    'grep -qxF "pr-edit $OPEN_URL $REPORT" "$FORGE_LOG"'
  check "R1c. ... sending the report's bytes" '[[ "$(cat "$FORGE_BODY_OUT")" == "$REPORT_TEXT" ]]'
  check "R1d. ... printing the refreshed line with the url" \
    'grep -qxF "  pr      already open, body refreshed: $OPEN_URL" <<<"$out"'
  check "R1e. ... and opening nothing" '! grep -q "^pr-open" "$FORGE_LOG"'

  reset_logs
  out="$(STUB_OPEN_URL="$OPEN_URL" run_pr "$copy")"; rc=$?
  check "R2. $copy: with no report the refresh sends the fallback body (got $rc)" \
    '[[ $rc -eq 0 ]] && grep -q "^pr-edit $OPEN_URL " "$FORGE_LOG" && grep -qF "$FALLBACK_WORDS" "$FORGE_BODY_OUT"'

  reset_logs
  out="$(STUB_OPEN_URL="$OPEN_URL" STUB_EDIT_RC=1 run_pr "$copy" "$REPORT")"; rc=$?
  check "R3a. $copy: a refused pr-edit exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
  check "R3b. ... with a fail line naming pr-edit" \
    'grep -E "^  fail " <<<"$out" | grep -q "pr-edit failed"'
  check "R3c. ... no refreshed line and no pr-open" \
    '! grep -q "body refreshed" <<<"$out" && ! grep -q "^pr-open" "$FORGE_LOG"'
  check "R3d. ... and the open PR's url on a '  pr ' line, the one place the close reads it" \
    'grep -qxF "  pr      already open, body NOT refreshed: $OPEN_URL" <<<"$out"'

  reset_logs
  out="$(run_pr "$copy" "$REPORT")"; rc=$?
  check "R4a. $copy: nothing open still opens one, exit 0 (got $rc)" '[[ $rc -eq 0 ]]'
  check "R4b. ... pr-open with the body file, pr-edit never" \
    'grep -qxF "pr-open $BRANCH $BASE $SLUG $REPORT" "$FORGE_LOG" && ! grep -q "^pr-edit" "$FORGE_LOG"'
  check "R4c. ... printing the new url" 'grep -qxF "  pr      $NEW_URL" <<<"$out"'
done

# ── E. forge.sh pr-edit itself ───────────────────────────────────────────────────
FC="$TMP/forge-checkout"
mkdir -p "$FC/hooks"
for f in "${FORGE_FILES[@]}"; do cp "$HERE/$f" "$FC/$f"; done
chmod +x "$FC/forge.sh"
git init -q "$FC"
gitq "$FC" remote add origin "https://github.com/$FORGE_OWNER/$FORGE_REPO.git"
BODY="$TMP/tricky-body.md"
printf '%s\n' "$TRICKY_BODY" > "$BODY"
EDIT_CALL="api -X PATCH repos/$FORGE_OWNER/$FORGE_REPO/pulls/$EDIT_PR_NUMBER"

e1_calls=""
for profile in "${PROFILES[@]}"; do
  echo "pr-body-refresh: forge.sh pr-edit under $profile"
  export AGENTTOOLING_PROFILE="$profile"

  : > "$GH_ARGV_LOG"; rm -f "$GH_BODY_OUT"
  out="$(cd "$TMP" && "$FC/forge.sh" pr-edit "$EDIT_PR_URL" "$BODY" 2>&1)"; rc=$?
  check "E1a. [$profile] pr-edit exits 0 and prints the url (got $rc)" \
    '[[ $rc -eq 0 && "$out" == "$EDIT_PR_URL" ]]'
  check "E1b. [$profile] ... one PATCH of repos/$FORGE_OWNER/$FORGE_REPO/pulls/$EDIT_PR_NUMBER" \
    '[[ "$(grep -c "^$EDIT_CALL " "$GH_ARGV_LOG")" == "1" ]]'
  check "E1c. [$profile] ... with the body file's bytes unexpanded" \
    '[[ "$(cat "$GH_BODY_OUT")" == "$TRICKY_BODY" && ! -e "$TMP/should-not-exist" ]]'
  e1_calls+="$(cat "$GH_ARGV_LOG")"$'\n'

  : > "$GH_ARGV_LOG"
  "$FC/forge.sh" pr-edit "https://github.com/$FORGE_OWNER/$FORGE_REPO/pull/x" "$BODY" >/dev/null 2>&1; rc=$?
  check "E2. [$profile] a url with no PR number: exit 1, no gh call (got $rc)" '[[ $rc -eq 1 && ! -s "$GH_ARGV_LOG" ]]'

  : > "$GH_ARGV_LOG"
  "$FC/forge.sh" pr-edit "$EDIT_PR_URL" "$TMP/no-such-body.md" >/dev/null 2>&1; rc=$?
  check "E3. [$profile] a missing body file: exit 1, no gh call (got $rc)" '[[ $rc -eq 1 && ! -s "$GH_ARGV_LOG" ]]'

  out="$(GH_RC=1 "$FC/forge.sh" pr-edit "$EDIT_PR_URL" "$BODY" 2>&1)"; rc=$?
  check "E4. [$profile] a failed call: exit 1, naming PATCH and the endpoint (got $rc)" \
    '[[ $rc -eq 1 ]] && grep -qF "PATCH repos/$FORGE_OWNER/$FORGE_REPO/pulls/$EDIT_PR_NUMBER failed" <<<"$out"'

  out="$(GH_NO_URL=1 "$FC/forge.sh" pr-edit "$EDIT_PR_URL" "$BODY" 2>&1)"; rc=$?
  check "E5. [$profile] an answer with no html_url: exit 1 (got $rc)" '[[ $rc -eq 1 ]] && grep -q "no html_url" <<<"$out"'

  "$FC/forge.sh" pr-edit "$EDIT_PR_URL" >/dev/null 2>&1; rc=$?
  check "E6. [$profile] too few arguments: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'
done
export AGENTTOOLING_PROFILE=local
check "E1d. both profiles made the same call — one REST path, no split" \
  '[[ "$(printf "%s" "$e1_calls" | sort -u | grep -c .)" == "1" ]]'
check "E7. no call was gh pr, gh auth status or GraphQL" \
  '! printf "%s" "$e1_calls" | grep -qE "$FORBIDDEN_GH_CALL_RE"'

echo
if (( fails > 0 )); then
  echo "pr-body-refresh: $fails check(s) failed"
  exit 1
fi
echo "pr-body-refresh: all checks passed"
