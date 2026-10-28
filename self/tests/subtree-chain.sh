#!/usr/bin/env bash
set -uo pipefail

# Self-test for update.sh's trailer-chain check and re-anchor
# (self/features/subtree-pull-keeps-base/, LIFECYCLE.md -> "Propagate"). Run by
# self/gate.sh, or by hand: bash self/tests/subtree-chain.sh
#
# `git subtree pull --squash` merges from the newest commit reachable from HEAD whose
# message carries `git-subtree-dir: <prefix>` and a `git-subtree-split:`. A consumer whose
# propagation PRs are squash-merged by the forge keeps that commit only as text in the
# squash-merge's body, and one body without the text — a hand-resolved pull, in mediaCore's
# pr92 — leaves the base behind the vendored tree, so every later pull conflicts. Asserts:
#
#   C1. the bug, without the fix: after a title-only squash-merge onto main, a plain
#       `git subtree pull --squash` of an upstream that changed the same line again
#       conflicts;
#   C2. the old way out — `git checkout --theirs`, add, commit, squash-merge onto main by
#       title again — leaves the vendored tree upstream's, and `update.sh --check` says
#       `broken` and exits 1, writing nothing (HEAD and the tree unmoved);
#   C3. with the fix, update.sh on the next pull feature's branch says `chain broken`,
#       re-anchors (`anchor` line, one merge commit whose tree is HEAD's and whose second
#       parent is a parentless squash commit with the trailers in its closing paragraph),
#       pulls with exit 0, the line lands, and `split` is the upstream head;
#   C4. after that pull, --check says `intact` and exits 0;
#   C5. merged onto main with a merge commit, the next pull is clean with no `anchor`
#       line and exactly the one merge the pull makes;
#   C6. a squash-merge that kept the commit bodies: --check says `fragile`, exit 0;
#   C7. a committed local edit under the prefix: --check says `edited`, exit 0, and
#       update.sh re-anchors nothing;
#   C8. local edits against upstream changes — the doc's line rewritten, and a file
#       upstream deletes (a modify/delete conflict, which a per-file `--theirs` cannot
#       take): update.sh exits 1 with the merge left in progress (MERGE_HEAD), a
#       `conflict` line naming the file and a `resolve` line naming `git read-tree
#       --prefix=… -u MERGE_HEAD`; resolved with exactly the commands it names, the
#       deleted file is gone, --check is `intact` and the next pull is clean;
#   C9. `--base` with a sha not in upstream's history is refused, HEAD unmoved;
#       `--check --base` is a usage error;
#   C10. a PR that re-anchored, then squash-merged keeping the bodies: --check is
#       `fragile` (the anchor's trailer block survived as text) and the next pull is
#       clean with no anchor.
#
# Builds a bare upstream holding the real update.sh, a stub sync-plans.sh and one doc,
# and a consumer that `git subtree add`s it, local layout (each pull branch has its
# manifest at plans/features/<branch>/README.md). No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/subtree-chain.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

PREFIX="agentTooling"
UPSTREAM_BRANCH="main"
FEATURES_REL="plans/features"
MANIFEST_NAME="README.md"
DOC="DOC.md"
REFUSED_RC=1
USAGE_RC=2
# The pull features this fixture starts, one per round
PULL_BRANCHES=(pull-1 pull-2 pull-3 pull-4 pull-5 pull-6 pull-7 pull-8 pull-9 pull-10)
# A second upstream file, deleted upstream in C8 while the consumer edits it
GONE="GONE.md"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

gitq() { git -c user.email=test@example.invalid -c user.name="subtree chain test" "$@"; }
export GIT_AUTHOR_NAME="subtree chain test" GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME="subtree chain test" GIT_COMMITTER_EMAIL=test@example.invalid

echo "subtree-chain"

UPSTREAM="$TMP/upstream.git"
WORK="$TMP/work"
C="$TMP/consumer"

git init -q --bare "$UPSTREAM"
git -C "$UPSTREAM" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
git clone -q "$UPSTREAM" "$WORK" 2>/dev/null
git -C "$WORK" symbolic-ref HEAD "refs/heads/$UPSTREAM_BRANCH"
cp "$AT/update.sh" "$WORK/update.sh"
printf '#!/usr/bin/env bash\necho "sync stub ran"\nexit 0\n' > "$WORK/sync-plans.sh"
chmod +x "$WORK/update.sh" "$WORK/sync-plans.sh"
echo "v1" > "$WORK/$DOC"
echo "kept for now" > "$WORK/$GONE"
gitq -C "$WORK" add -A
gitq -C "$WORK" commit -q -m "upstream v1"
git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null

# upstream_line <text> — upstream rewrites the doc's one line and pushes
upstream_line() {
  echo "$1" > "$WORK/$DOC"
  gitq -C "$WORK" commit -q -am "upstream $1"
  git -C "$WORK" push -q origin "$UPSTREAM_BRANCH" 2>/dev/null
}
upstream_head() { git -C "$UPSTREAM" rev-parse "$UPSTREAM_BRANCH"; }

mkdir -p "$C"
git -C "$C" init -q
git -C "$C" symbolic-ref HEAD refs/heads/main
echo "consumer" > "$C/README.md"
for b in "${PULL_BRANCHES[@]}"; do
  mkdir -p "$C/$FEATURES_REL/$b"
  echo "manifest for $b" > "$C/$FEATURES_REL/$b/$MANIFEST_NAME"
done
gitq -C "$C" add -A
gitq -C "$C" commit -q -m "init"
gitq -C "$C" subtree add --prefix="$PREFIX" "$UPSTREAM" "$UPSTREAM_BRANCH" --squash >/dev/null 2>&1

# start <branch> — the pull feature's branch, off main
start() { git -C "$C" checkout -q -b "$1" main; }
# land_squash <branch> <message> — the forge's squash-merge of the branch onto main
land_squash() {
  git -C "$C" checkout -q main
  git -C "$C" merge -q --squash "$1" >/dev/null 2>&1
  gitq -C "$C" commit -q -m "$2"
}
update() { "$C/$PREFIX/update.sh" --remote "$UPSTREAM" "$@"; }
doc_is() { [[ "$(cat "$C/$PREFIX/$DOC")" == "$1" ]]; }

# ── Round 1: a clean pull, squash-merged by title only — the chain breaks ──────
upstream_line v2
start pull-1
update >/dev/null 2>&1
land_squash pull-1 "pull-agenttooling-pr2 (#1)"

# ── C1: without the fix, the next pull conflicts ─────────────────────────────
upstream_line v3
start pull-2
gitq -C "$C" subtree pull --prefix="$PREFIX" "$UPSTREAM" "$UPSTREAM_BRANCH" --squash >/dev/null 2>&1
c1_rc=$?
check "C1 a plain subtree pull from the stale base conflicts" \
  '(( c1_rc != 0 )) && git -C "$C" rev-parse -q --verify MERGE_HEAD >/dev/null'

# ── C2: resolved the old way and squash-merged by title again ────────────────
git -C "$C" checkout -q --theirs -- "$PREFIX"
git -C "$C" add "$PREFIX"
gitq -C "$C" commit -q -m "resolve by hand"
land_squash pull-2 "pull-agenttooling-pr3 (#2)"
check "C2a the vendored tree is upstream's after the hand resolution" 'doc_is v3'
start pull-3
head_before="$(git -C "$C" rev-parse HEAD)"
c2_out="$(update --check 2>&1)"; c2_rc=$?
check "C2b --check says broken and exits 1" '(( c2_rc == 1 )) && grep -q "chain  broken" <<<"$c2_out"'
check "C2c --check moves nothing and leaves the tree clean" \
  '[[ "$(git -C "$C" rev-parse HEAD)" == "$head_before" && -z "$(git -C "$C" status --porcelain)" ]]'

# ── C3: the fix re-anchors and the pull is clean ─────────────────────────────
upstream_line v4
c3_out="$(update 2>&1)"; c3_rc=$?
check "C3a update.sh reports the broken chain and an anchor" \
  'grep -q "chain  broken" <<<"$c3_out" && grep -q "^  anchor " <<<"$c3_out"'
check "C3b the pull exits 0 and the upstream line lands" '(( c3_rc == 0 )) && doc_is v4'
check "C3c the split line is the upstream head" 'grep -q "split  $(upstream_head)" <<<"$c3_out"'
anchor_merge="$(git -C "$C" rev-list --merges --reverse "$head_before..HEAD" | head -n 1)"
anchor_sq="$(git -C "$C" rev-parse "$anchor_merge^2")"
check "C3d the anchor merge changes no file" \
  '[[ "$(git -C "$C" rev-parse "$anchor_merge^{tree}")" == "$(git -C "$C" rev-parse "$head_before^{tree}")" ]]'
check "C3e its squash commit is parentless and ends in a trailer block" \
  '[[ -z "$(git -C "$C" log -n 1 --format=%P "$anchor_sq")" ]] && git -C "$C" log -n 1 --format="%(trailers:key=git-subtree-dir,valueonly)" "$anchor_sq" | grep -qx "$PREFIX"'
check "C3f the anchor merge's own message carries no subtree trailer line" \
  '! git -C "$C" log -n 1 --format=%B "$anchor_merge" | grep -q "^git-subtree-"'

# ── C4: intact after the repaired pull ───────────────────────────────────────
c4_out="$(update --check 2>&1)"; c4_rc=$?
check "C4 --check says intact and exits 0" '(( c4_rc == 0 )) && grep -q "chain  intact" <<<"$c4_out"'

# ── C5: landed with a merge commit, the next pull needs no anchor ────────────
git -C "$C" checkout -q main
gitq -C "$C" merge -q --no-ff -m "Merge pull-3" pull-3
upstream_line v5
start pull-4
before5="$(git -C "$C" rev-parse HEAD)"
c5_out="$(update 2>&1)"; c5_rc=$?
check "C5a the pull is clean, with no anchor" \
  '(( c5_rc == 0 )) && doc_is v5 && ! grep -q "^  anchor " <<<"$c5_out"'
check "C5b the pull added exactly one merge" \
  '[[ "$(git -C "$C" rev-list --count --merges --first-parent "$before5..HEAD")" == 1 ]]'

# ── C6: a squash-merge that kept the bodies is fragile, not broken ───────────
git -C "$C" checkout -q main
git -C "$C" merge -q --squash pull-4 >/dev/null 2>&1
gitq -C "$C" commit -q -m "pull-agenttooling-pr5 (#4)" -m "$(git -C "$C" log --format='* %B' main..pull-4)"
start pull-5
c6_out="$(update --check 2>&1)"; c6_rc=$?
check "C6 --check says fragile and exits 0" '(( c6_rc == 0 )) && grep -q "chain  fragile" <<<"$c6_out"'

# ── C7: a local edit under the prefix is left alone ─────────────────────────
echo "local note" > "$C/$PREFIX/LOCAL.md"
gitq -C "$C" add -A
gitq -C "$C" commit -q -m "a local edit under the prefix"
c7_out="$(update --check 2>&1)"; c7_rc=$?
check "C7a --check says edited and exits 0" '(( c7_rc == 0 )) && grep -q "chain  edited" <<<"$c7_out"'
before7="$(git -C "$C" rev-parse HEAD)"
c7b_out="$(update 2>&1)"
check "C7b update.sh re-anchors nothing" '! grep -q "^  anchor " <<<"$c7b_out"'

# ── C8: a real conflict, and the resolution update.sh names ─────────────────
git -C "$C" checkout -q main
gitq -C "$C" merge -q --no-ff -m "Merge pull-5" pull-5
start pull-6
git -C "$C" rm -q "$PREFIX/LOCAL.md"
echo "local v5 edit" > "$C/$PREFIX/$DOC"
echo "a local edit of a file upstream drops" > "$C/$PREFIX/$GONE"
gitq -C "$C" commit -q -am "C7's note dropped, and local edits of two upstream files"
git -C "$WORK" rm -q "$GONE"
upstream_line v6
c8_out="$(update 2>&1)"; c8_rc=$?
check "C8a a conflicting pull exits 1 with the merge in progress" \
  '(( c8_rc == REFUSED_RC )) && git -C "$C" rev-parse -q --verify MERGE_HEAD >/dev/null'
check "C8b it names the conflicted files and the read-tree resolution" \
  'grep -q "^  conflict " <<<"$c8_out" && grep -q "$PREFIX/$DOC" <<<"$c8_out" && grep -q "$PREFIX/$GONE" <<<"$c8_out" && grep -q "^  resolve .*git read-tree --prefix=$PREFIX/ -u MERGE_HEAD" <<<"$c8_out"'
# exactly the commands the resolve line names
git -C "$C" rm -r -q -- "$PREFIX"
git -C "$C" read-tree --prefix="$PREFIX/" -u MERGE_HEAD
gitq -C "$C" commit -q --no-edit
c8c_out="$(update --check 2>&1)"; c8c_rc=$?
check "C8c resolved as it says: the deleted file is gone, --check is intact" \
  '(( c8c_rc == 0 )) && grep -q "chain  intact" <<<"$c8c_out" && doc_is v6 && [[ ! -e "$C/$PREFIX/$GONE" ]] && [[ -z "$(git -C "$C" status --porcelain)" ]]'
upstream_line v7
c8d_out="$(update 2>&1)"; c8d_rc=$?
check "C8d the next pull is clean" '(( c8d_rc == 0 )) && doc_is v7 && ! grep -q "^  anchor " <<<"$c8d_out"'

# ── C9: --base is checked ────────────────────────────────────────────────────
git -C "$C" checkout -q main
gitq -C "$C" merge -q --no-ff -m "Merge pull-6" pull-6
start pull-7
before9="$(git -C "$C" rev-parse HEAD)"
foreign="$(git -C "$C" rev-parse "main~1")"
update --base "$foreign" >/dev/null 2>&1; c9_rc=$?
check "C9a --base outside upstream's history is refused, HEAD unmoved" \
  '(( c9_rc == REFUSED_RC )) && [[ "$(git -C "$C" rev-parse HEAD)" == "$before9" ]]'
update --check --base "$foreign" >/dev/null 2>&1; c9b_rc=$?
check "C9b --check with --base is a usage error" '(( c9b_rc == USAGE_RC ))'

# ── C10: an anchor inside a PR squash-merged with its bodies kept ────────────
upstream_line v8
update >/dev/null 2>&1
land_squash pull-7 "pull-agenttooling-pr8 (#7)"
upstream_line v9
start pull-8
c10a_out="$(update 2>&1)"; c10a_rc=$?
check "C10a the title-only squash-merge broke the chain, and update.sh re-anchored and pulled" \
  '(( c10a_rc == 0 )) && grep -q "^  anchor " <<<"$c10a_out" && doc_is v9'
git -C "$C" checkout -q main
git -C "$C" merge -q --squash pull-8 >/dev/null 2>&1
# GitHub's squash body lists the PR's commits oldest first, so the last split line in it
# is the pull's own squash, not the anchor's
gitq -C "$C" commit -q -m "pull-agenttooling-pr9 (#8)" -m "$(git -C "$C" log --reverse --format='* %B' main..pull-8)"
start pull-9
c10b_out="$(update --check 2>&1)"; c10b_rc=$?
check "C10b squash-merged with bodies, the anchor's trailers survive: fragile, exit 0" \
  '(( c10b_rc == 0 )) && grep -q "chain  fragile" <<<"$c10b_out"'
upstream_line v10
c10c_out="$(update 2>&1)"; c10c_rc=$?
check "C10c the next pull is clean, with no anchor" \
  '(( c10c_rc == 0 )) && doc_is v10 && ! grep -q "^  anchor " <<<"$c10c_out"'

if (( fails )); then
  echo "subtree-chain: $fails failure(s)"
  exit 1
fi
echo "subtree-chain: all checks passed"
