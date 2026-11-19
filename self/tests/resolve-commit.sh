#!/usr/bin/env bash
set -uo pipefail

# Self-test for harness_resolve_commit's fallbacks (self/features/lifecycle-loose-ends,
# item 3). Run by self/gate.sh, or by hand: bash self/tests/resolve-commit.sh
#
# A fixture pin must resolve in a cloud clone, which is shallow (50 commits) and fetches
# no PR heads. Against a local bare repo whose server is as strict as can be made (no
# any-sha or reachable-sha wants, protocol v0 on the clone) this asserts, per case, the
# sha found, the step that found it, and that no ref was created or moved:
#   R1. a commit older than a shallow clone's depth;
#   R2. a commit reachable only through refs/pull/*/head;
#   R3. a sha nothing has fails, printing a message that names the sha and every step
#       tried (local, sha, --unshallow on a shallow clone, the pull heads);
#   R4. a ref that resolves locally costs no fetch, and a branch name is never fetched;
#   R5. harness_pin_agent_tooling's lookup and check-fixture's base/spec checks go through
#       the resolver (grep: no private cat-file/rev-parse fetch fallback remains);
#   R6. check-fixture's PR-only warning fires exactly for the pull step.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resolve.commit.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# shellcheck source=../../harness/lib.sh
source "$HERE/harness/lib.sh"

# Clone depth, and how many commits main holds beyond the one the old pin names.
SHALLOW_DEPTH=2
MAIN_COMMITS=6
# How far below main's tip the tag sits: beyond SHALLOW_DEPTH, above the oldest commit.
OLD_TAG_DEPTH=3

echo "resolve-commit"

BARE="$TMP/origin.git"
SEED="$TMP/seed"
git init -q --bare "$BARE"
gitq "$BARE" config uploadpack.allowAnySHA1InWant false
gitq "$BARE" config uploadpack.allowReachableSHA1InWant false
git init -q "$SEED"
gitq "$SEED" config user.email test@example.invalid
gitq "$SEED" config user.name test
gitq "$SEED" symbolic-ref HEAD refs/heads/main
gitq "$SEED" remote add origin "$BARE"
OLD_SHA=""
for n in $(seq 1 "$MAIN_COMMITS"); do
  echo "$n" > "$SEED/f.txt"
  gitq "$SEED" add -A
  gitq "$SEED" commit -q -m "c$n"
  [[ -n "$OLD_SHA" ]] || OLD_SHA="$(git -C "$SEED" rev-parse HEAD)"
done
gitq "$SEED" push -q origin main
# A tag inside the history beyond the clone's depth (not on OLD_SHA, which would advertise
# it): a deepen that auto-followed tags would create refs/tags/old-tag in the clone.
gitq "$SEED" tag old-tag "HEAD~$OLD_TAG_DEPTH"
gitq "$SEED" push -q origin old-tag
# A commit only a PR head holds: pushed to refs/pull/10/head, on no branch.
gitq "$SEED" checkout -q -b pr-work
echo pr > "$SEED/pr.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m "pr only"
PR_SHA="$(git -C "$SEED" rev-parse HEAD)"
# A second PR commit on top, so PR_SHA is no longer the advertised tip: a strict server
# refuses a want for it, and only fetching the pull heads (tip and ancestry) brings it.
echo pr2 > "$SEED/pr2.txt"
gitq "$SEED" add -A
gitq "$SEED" commit -q -m "pr tip"
gitq "$SEED" push -q origin "HEAD:refs/pull/10/head"

new_clone() {  # $1 dir — a shallow main-only clone on protocol v0
  git -c protocol.version=0 clone -q --depth "$SHALLOW_DEPTH" --single-branch --branch main "file://$BARE" "$1" 2>/dev/null
  gitq "$1" config protocol.version 0
}

# ── R1. Older than the shallow depth ──────────────────────────────────────────
C1="$TMP/c1"; new_clone "$C1"
check "R1a. premise: the clone is shallow and lacks the old commit" \
  '[[ "$(git -C "$C1" rev-parse --is-shallow-repository)" == true ]] && ! git -C "$C1" cat-file -e "$OLD_SHA^{commit}" 2>/dev/null'
refs_before="$(git -C "$C1" for-each-ref refs/heads refs/tags)"
harness_resolve_commit_core "$C1" "$OLD_SHA" origin; rc=$?
check "R1b. it resolves (rc $rc, via ${HARNESS_RESOLVED_VIA:-none})" '[[ $rc -eq 0 && "$HARNESS_RESOLVED_SHA" == "$OLD_SHA" ]]'
check "R1c. ... through the deepen step, the one a strict server leaves" '[[ "$HARNESS_RESOLVED_VIA" == "$RESOLVE_VIA_DEEPEN" ]]'
check "R1d. ... and created or moved no local branch or tag (heads and tags unchanged, the deepen followed no tag)" \
  '[[ "$(git -C "$C1" for-each-ref refs/heads refs/tags)" == "$refs_before" ]]'

# ── R2. Reachable only through refs/pull/* ────────────────────────────────────
C2="$TMP/c2"; new_clone "$C2"
heads_before="$(git -C "$C2" for-each-ref refs/heads)"
harness_resolve_commit_core "$C2" "$PR_SHA" origin; rc=$?
check "R2a. a PR-only commit resolves (rc $rc, via ${HARNESS_RESOLVED_VIA:-none})" '[[ $rc -eq 0 && "$HARNESS_RESOLVED_SHA" == "$PR_SHA" ]]'
check "R2b. ... through the pull-heads step, after the deepen" '[[ "$HARNESS_RESOLVED_VIA" == "$RESOLVE_VIA_PULL" ]]'
check "R2c. ... creating no ref (heads unchanged, no refs/pull locally)" \
  '[[ "$(git -C "$C2" for-each-ref refs/heads)" == "$heads_before" && -z "$(git -C "$C2" for-each-ref refs/pull)" ]]'
# The same on a full (non-shallow) clone: no deepen step is attempted.
C2B="$TMP/c2b"; git clone -q "file://$BARE" "$C2B" 2>/dev/null; gitq "$C2B" config protocol.version 0
harness_resolve_commit_core "$C2B" "$PR_SHA" origin; rc=$?
check "R2d. on a full clone it resolves via the pull step, trying no --unshallow (rc $rc)" \
  '[[ $rc -eq 0 && "$HARNESS_RESOLVED_VIA" == "$RESOLVE_VIA_PULL" && "$HARNESS_RESOLVE_TRIED" != *unshallow* ]]'

# ── R3. A sha nothing has ─────────────────────────────────────────────────────
MISSING_SHA="0123456789abcdef0123456789abcdef01234567"
err="$(harness_resolve_commit "$C2" "$MISSING_SHA" origin 2>&1 >/dev/null)"; rc=$?
out="$(harness_resolve_commit "$C2" "$MISSING_SHA" origin 2>/dev/null)"
check "R3a. it fails and prints nothing on stdout (rc $rc)" '[[ $rc -ne 0 && -z "$out" ]]'
check "R3b. the message names the sha and each step tried: $err" \
  '[[ "$err" == *"$MISSING_SHA"* && "$err" == *"git fetch origin $MISSING_SHA"* && "$err" == *"$RESOLVE_PULL_REFSPEC"* ]]'
C3="$TMP/c3"; new_clone "$C3"
err="$(harness_resolve_commit "$C3" "$MISSING_SHA" origin 2>&1 >/dev/null)"
check "R3c. on a shallow clone the message also names --unshallow" '[[ "$err" == *"--unshallow"* ]]'

# ── R4. No needless fetch ─────────────────────────────────────────────────────
harness_resolve_commit_core "$C3" main origin; rc=$?
check "R4a. a ref that resolves locally is found by the local step (via ${HARNESS_RESOLVED_VIA:-none})" \
  '[[ $rc -eq 0 && "$HARNESS_RESOLVED_VIA" == "$RESOLVE_VIA_LOCAL" ]]'
harness_resolve_commit_core "$C3" no-such-branch origin; rc=$?
check "R4b. a name that is not a sha is never fetched: only the local step is tried" \
  '[[ $rc -ne 0 && "$HARNESS_RESOLVE_TRIED" == "a local lookup" ]]'

# ── R5. Every pin goes through the one resolver ───────────────────────────────
check "R5a. harness_pin_agent_tooling resolves through harness_resolve_commit" \
  'sed -n "/^harness_pin_agent_tooling()/,/^}/p" "$HERE/harness/lib.sh" | grep -q "harness_resolve_commit"'
check "R5b. new-experiment.sh resolves the agentTooling arm ref through it" \
  'grep -q "harness_resolve_commit \"\$at\" \"\$ref\"" "$HERE/harness/new-experiment.sh"'
check "R5c. check-fixture.sh resolves the base and the spec commit through it" \
  '[[ "$(grep -c "harness_resolve_commit_core" "$HERE/harness/check-fixture.sh")" -ge 2 ]]'

# ── R6. check-fixture warns for a PR-only pin, not otherwise ──────────────────
# warn_if_pr_only is check-fixture.sh's own function; run its body against the results above.
WARN_BODY="$(sed -n '/^warn_if_pr_only()/,/^}/p' "$HERE/harness/check-fixture.sh")"
warn() { echo "warn $*"; }
eval "$WARN_BODY"
HARNESS_RESOLVED_VIA="$RESOLVE_VIA_PULL"; msg="$(warn_if_pr_only "base" "$PR_SHA")"
check "R6a. the pull step produces a warning naming refs/pull" '[[ "$msg" == *"refs/pull/"* && "$msg" == *"$PR_SHA"* ]]'
for via in "$RESOLVE_VIA_LOCAL" "$RESOLVE_VIA_SHA" "$RESOLVE_VIA_DEEPEN"; do
  HARNESS_RESOLVED_VIA="$via"; msg="$(warn_if_pr_only "base" "$OLD_SHA")"
  check "R6b. [$via] no warning" '[[ -z "$msg" ]]'
done

echo
if [[ $fails -eq 0 ]]; then
  echo "resolve-commit: all checks passed"
  exit 0
fi
echo "resolve-commit: $fails check(s) failed"
exit 1
