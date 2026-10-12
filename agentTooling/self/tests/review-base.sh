#!/usr/bin/env bash
set -uo pipefail

# Self-test for the review's base (self/features/review-base-and-cloud-hook/, Part B):
# run-review.sh fetches `origin <base>` before each review plan — best-effort — and tells
# the executor to diff `origin/<base>...HEAD`, falling back to the local `<base>` only
# when there is no `origin/<base>` to diff against. Run by self/gate.sh, or by hand:
# bash self/tests/review-base.sh
#
# The scenario the fix exists for: a feature cut from main at M0 merges a NEWER
# origin/main (M1, somebody else's merged work) mid-way, while the local `main` stays at
# M0 — and, as in a fresh container, the remote-tracking `origin/main` is stale too. Three
# dots take the merge-base, so `main...HEAD` is M0...HEAD and carries M1's change; the
# review must instead see only the feature's own commits.
#
# A consuming repo is built under mktemp -d with run-review.sh and the runner library
# under agentTooling/, a stub `claude` that saves the prompt it is handed, and a bare
# origin. Asserts, under BOTH profiles (AGENTTOOLING_PROFILE=local, then cloud, with
# CLAUDE_CODE_REMOTE cleared), with identical results:
#   B0. the premise: the local `main...HEAD` diff carries the already-merged file, and
#       origin/main is stale before the run;
#   B1. the pass exits 0, and the fetch moved origin/main to the remote's tip;
#   B2. the prompt names `git diff origin/main...HEAD` — the remote's base;
#   B3. the diff from the base the prompt names holds the feature's files and NOT the
#       already-merged one — this is what fails if the base reverts to the local `main`;
#   B4. both profiles name the same base and the same diff;
#   W1. an unreachable origin with no origin/main: a warning naming the fetch, the pass
#       still exits as the reachable one did, and the prompt falls back to `main...HEAD`,
#       saying there is no origin/main;
#   N1. no remote at all: the pass exits the same, the prompt names `main...HEAD` and
#       says there is no origin/main.
#
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/review-base.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

BASE="main"
SLUG="feat-review"
REMOTE="origin"
FEATURE_FILES=(feature-one.txt feature-two.txt)
MERGED_FILE="already-merged.txt"
RUNNER_FILES=(run-review.sh plan-runner-lib.sh plan-runner-roots.sh stamp-timing.sh)
PROFILES=(local cloud)
# What the prompt says when it falls back, and what the fetch warning names
FALLBACK_WORDS="no $REMOTE/$BASE"
FETCH_WARN_RE="WARN.*fetch"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${@: -1}" > "${PROMPT_OUT:?}"
printf '{"type":"result","total_cost_usd":0,"session_id":"stub"}\n'
STUB
chmod +x "$TMP/bin/claude"

gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
commit_file() {  # commit_file <repo> <file> <subject>
  echo "$2" > "$1/$2"
  gitq "$1" add -A
  gitq "$1" commit -q -m "$3"
}

# fixture <name> — the scenario above, at $TMP/<name>/repo, origin at $TMP/<name>/origin.git
fixture() {
  local dir="$TMP/$1" repo origin other f m0
  repo="$dir/repo"; origin="$dir/origin.git"; other="$dir/other"
  mkdir -p "$repo/agentTooling" "$repo/plans/features/$SLUG/review/incomplete"
  for f in "${RUNNER_FILES[@]}"; do cp "$HERE/$f" "$repo/agentTooling/$f"; done
  chmod +x "$repo"/agentTooling/*.sh
  git init -q "$repo"
  gitq "$repo" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$repo" config user.email test@example.invalid
  gitq "$repo" config user.name "review base test"
  printf '# %s\n\n```json\n{"slug": "%s", "base": "%s", "branches": ["%s"], "plans": ["01-review-opus"]}\n```\n' \
    "$SLUG" "$SLUG" "$BASE" "$SLUG" > "$repo/plans/features/$SLUG/README.md"
  printf '# 01 — review\n\nfeature: agentTooling/%s\n\nReview it.\n' "$SLUG" \
    > "$repo/plans/features/$SLUG/review/incomplete/01-review-opus.md"
  commit_file "$repo" base.txt "M0: base"
  git init -q --bare "$origin"
  gitq "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$repo" remote add "$REMOTE" "$origin"
  gitq "$repo" push -q "$REMOTE" "$BASE"
  gitq "$repo" checkout -q -b "$SLUG"
  commit_file "$repo" "${FEATURE_FILES[0]}" "feature: one"
  # Somebody else's work merges to origin/main meanwhile
  git clone -q "$origin" "$other" 2>/dev/null
  gitq "$other" config user.email test@example.invalid
  gitq "$other" config user.name "other"
  commit_file "$other" "$MERGED_FILE" "M1: already merged elsewhere"
  gitq "$other" push -q "$REMOTE" "$BASE"
  # The conflict-fix path: the feature merges the newer origin/main; local main stays
  gitq "$repo" fetch -q "$REMOTE"
  gitq "$repo" merge -q --no-edit "$REMOTE/$BASE"
  commit_file "$repo" "${FEATURE_FILES[1]}" "feature: two"
  # A fresh container's remote-tracking ref: stale, so only a real fetch can move it
  m0="$(git -C "$repo" rev-parse "$BASE")"
  gitq "$repo" update-ref "refs/remotes/$REMOTE/$BASE" "$m0"
  echo "$repo"
}

# review <repo> <profile> <prompt-out> — the pass, as a coordinator runs it
review() {
  ( cd "$1" && env -u CLAUDE_CODE_REMOTE AGENTTOOLING_PROFILE="$2" PROMPT_OUT="$3" \
      PATH="$TMP/bin:$PATH" agentTooling/run-review.sh "$SLUG" 2>&1 )
}

# named_base <prompt> — the ref the prompt tells the executor to diff from
named_base() { grep -o 'git diff [^ `]*\.\.\.HEAD' "$1" | head -n 1 | sed -e 's/^git diff //' -e 's/\.\.\.HEAD$//'; }

echo "review-base"

results=""
for profile in "${PROFILES[@]}"; do
  repo="$(fixture "remote-$profile")"
  prompt="$TMP/remote-$profile.prompt"
  local_diff="$(git -C "$repo" diff --name-only "$BASE...HEAD")"
  stale="$(git -C "$repo" rev-parse "$REMOTE/$BASE")"
  check "B0. [$profile] premise: local $BASE...HEAD carries $MERGED_FILE, and $REMOTE/$BASE is stale" \
    'grep -qx "$MERGED_FILE" <<<"$local_diff" && [[ "$stale" == "$(git -C "$repo" rev-parse "$BASE")" ]]'
  out="$(review "$repo" "$profile" "$prompt")"; rc=$?
  check "B1. [$profile] the pass exits 0 and the fetch moved $REMOTE/$BASE to the remote's tip (got $rc)" \
    '[[ $rc -eq 0 && "$(git -C "$repo" rev-parse "$REMOTE/$BASE")" == "$(git -C "$TMP/remote-$profile/origin.git" rev-parse "$BASE")" ]]'
  base="$(named_base "$prompt" 2>/dev/null)"
  check "B2. [$profile] the prompt names git diff $REMOTE/$BASE...HEAD (got '$base')" \
    '[[ "$base" == "$REMOTE/$BASE" ]]'
  review_diff="$(git -C "$repo" diff --name-only "$base...HEAD" 2>/dev/null)"
  check "B3. [$profile] that diff holds the feature's files and not $MERGED_FILE" \
    'grep -qx "${FEATURE_FILES[0]}" <<<"$review_diff" && grep -qx "${FEATURE_FILES[1]}" <<<"$review_diff" && ! grep -qx "$MERGED_FILE" <<<"$review_diff"'
  results="$results|$base:$(git -C "$repo" diff --name-only "$base...HEAD" -- "${FEATURE_FILES[@]}" "$MERGED_FILE" 2>/dev/null | tr '\n' ',')"
done
first="$(cut -d'|' -f2 <<<"$results")"
second="$(cut -d'|' -f3 <<<"$results")"
check "B4. both profiles name the same base and the same diff ('$first' vs '$second')" \
  '[[ -n "$first" && "$first" == "$second" ]]'

# ── W. an unreachable origin, nothing fetched ever ──────────────────────────
repo="$(fixture unreachable)"
gitq "$repo" remote set-url "$REMOTE" "$TMP/unreachable/gone.git"
gitq "$repo" update-ref -d "refs/remotes/$REMOTE/$BASE"
prompt="$TMP/unreachable.prompt"
out="$(review "$repo" local "$prompt")"; rc=$?
base="$(named_base "$prompt" 2>/dev/null)"
check "W1a. an unreachable origin warns about the fetch and the pass still exits 0 (got $rc)" \
  '[[ $rc -eq 0 ]] && grep -qE "$FETCH_WARN_RE" <<<"$out"'
check "W1b. ... and the prompt falls back to $BASE...HEAD, saying there is $FALLBACK_WORDS (got '$base')" \
  '[[ "$base" == "$BASE" ]] && grep -qF "$FALLBACK_WORDS" "$prompt"'

# ── N. no remote at all ────────────────────────────────────────────────────────
repo="$(fixture noremote)"
gitq "$repo" remote remove "$REMOTE"
prompt="$TMP/noremote.prompt"
out="$(review "$repo" cloud "$prompt")"; rc=$?
base="$(named_base "$prompt" 2>/dev/null)"
check "N1. no remote: exits 0, the prompt names $BASE...HEAD and says there is $FALLBACK_WORDS (got $rc, '$base')" \
  '[[ $rc -eq 0 && "$base" == "$BASE" ]] && grep -qF "$FALLBACK_WORDS" "$prompt"'

echo
if (( fails > 0 )); then echo "review-base: $fails assertion(s) FAILED"; exit 1; fi
echo "review-base: all assertions passed"
