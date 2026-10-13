#!/usr/bin/env bash
set -uo pipefail

# Self-test: the repo-owned templates' `# template-version: N` lines are honest.
# Run by self/gate.sh, or by hand: bash self/tests/template-versions.sh [<templates dir>]
# (the directory defaults to templates/plans; self/tests/template-version-bump.sh hands it
# an edited copy).
#
# Why this exists. The whole drift mechanism — sync-plans.sh's template_version compare,
# the `DRIFT` line a consuming repo acts on — rests on an author remembering to bump the
# number when a template changes. Nothing could see an edit that did not: such a change
# reports `in-sync` in every consumer while their seeded copies are stale, which is worse
# than having no drift detection at all. sync-check.sh's assertion 8 cannot catch it
# either; it only asserts templates/plans/X and self/X carry the *same* number.
#
# Mechanism: templates/plans/TEMPLATE_VERSIONS is a checked-in table, one line per
# template, `<file> <version> <sha256>`. The hash is taken over the WHOLE file except its
# `# template-version:` line — comments included. It used to strip comment-only and
# blank lines, so that a documentation edit was free; that is exactly how PR 85 reworded
# cloud-setup.sh's header (it is run by session-start.sh now, not wired as the hook) at
# version 1 and every consumer's stale copy read `in-sync` forever
# (self/features/cloud-pull-fixes/NOTES.md). A seeded script's comments are the consumer's
# documentation of how it is run, so they are content. Any edit therefore goes red here,
# naming the file, until the version line is bumped and the hash re-recorded. A committed
# table rather than a diff against history, so it holds in a shallow clone.
#
# The table alone cannot tell a bump from a re-record: edit a template, re-record only its
# hash, leave the version, and the table agrees with the file. So each template is also
# compared with the BASE branch's copy (`git show <commit>:templates/plans/<file>`; base =
# origin/main, the local main if origin/main is absent; neither: FAIL naming the fetch).
# The commit is the branch's FORK POINT from the base (`git merge-base HEAD <base>`), not
# the base tip: the check is about what THIS branch changed, so a branch that never touched
# templates passes however far main has moved, and nobody is pushed to bump a stale copy
# (which would roll main's newer template back on merge). Only when the merge base cannot be
# computed (a shallow clone without the shared history) does it fall back to the tip, and
# then a stale branch can trip on a newer main bump: the message says to merge the base.
# The base's hash is recomputed from its file by the rule above, not read from
# its table. Same version + different content fails; a lower version fails; a template
# with no base copy (new) passes; one removed has no row to check. Env overrides for the
# self-test: TEMPLATE_BASE_REPO, TEMPLATE_BASE_REF, TEMPLATE_BRANCH_REPO.
#
# This is not the "contract-header diffing" the sweep-and-check manifest excludes — that
# was about how a *consumer* detects drift. This keeps the version line honest at source.
#
# Prints one `  ok    <label>` / `  FAIL  <label>: <detail>` line per template and exits
# non-zero if any FAILed, the shape its neighbours in this directory use.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="${1:-$HERE/templates/plans}"
VERSIONS_TABLE="$TEMPLATE_DIR/TEMPLATE_VERSIONS"
VERSION_LINE_RE='^# template-version:[[:space:]]*\([0-9][0-9]*\).*'
# The one line the hash leaves out: the stamp it is checked against
VERSION_LINE_PREFIX_RE='^# template-version:'
# The six seeded, repo-owned scripts — templates/README.md's list, the last two the
# environment adapters of self/DESIGN-2026-10-05-cloud-execution.md §7. The generated
# stubs are overwritten on every sync and carry no version line.
TEMPLATES=(gate.sh pr.sh worktree-setup.sh open-session.sh environment.sh cloud-setup.sh)
BUMP_HINT="bump template-version FIRST, then re-record the hash in templates/plans/TEMPLATE_VERSIONS"
# The base the versions are tied to (needs only its tip, so a depth-1 fetch serves). Both
# are overridable for the self-test's fixture repo.
BASE_REPO="${TEMPLATE_BASE_REPO:-$HERE}"
BASE_REF="${TEMPLATE_BASE_REF:-origin/main}"
FALLBACK_BASE_BRANCH="main"
BASE_TEMPLATE_DIR="templates/plans"
# The checkout whose HEAD is "this branch" (the fork point is the merge base of its HEAD
# and the base). Overridable so the self-test's fixture can hold both.
BRANCH_REPO="${TEMPLATE_BRANCH_REPO:-$HERE}"
SHORT_SHA_LEN=9

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1: $2"; fails=$((fails + 1)); }

# The recorded hash's definition, in one place, and the same command TEMPLATE_VERSIONS'
# header gives: everything but the version line, so no edit at all is free.
stamped_hash() {
  grep -v "$VERSION_LINE_PREFIX_RE" "$1" | shasum -a 256 | awk '{print $1}'
}

template_version() {
  sed -n "s/$VERSION_LINE_RE/\\1/p" "$1" 2>/dev/null | head -n 1
}

# table_field <file> <1=version|2=hash> — the recorded value, or nothing.
table_field() {
  awk -v want="$1" -v col="$2" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == want { print (col == 1 ? $2 : $3); exit }
  ' "$VERSIONS_TABLE"
}

# resolve_base — print the ref to compare against: BASE_REF if it resolves, else the local
# FALLBACK_BASE_BRANCH (run-review.sh's review_diff_base precedent), else nothing.
resolve_base() {
  local ref
  for ref in "$BASE_REF" "$FALLBACK_BASE_BRANCH"; do
    if git -C "$BASE_REPO" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
      echo "$ref"
      return 0
    fi
  done
  return 1
}

# resolve_compare_point — print the commit the templates are compared against: the FORK
# POINT (merge base of this branch's HEAD and the base) when it can be computed, else the
# base tip (a shallow clone without the shared history). The check is about what THIS
# branch changed, so a branch that never touched a template passes however far the base
# has moved; the tip is only the fallback (the caller tells the two apart: the tip comes
# back as the ref name BASE_USED, the fork point as a commit id).
resolve_compare_point() {
  local head mb
  head="$(git -C "$BRANCH_REPO" rev-parse --verify -q "HEAD^{commit}" 2>/dev/null)"
  if [[ -n "$head" ]] && mb="$(git -C "$BASE_REPO" merge-base "$head" "$BASE_USED" 2>/dev/null)" && [[ -n "$mb" ]]; then
    echo "$mb"
    return 0
  fi
  echo "$BASE_USED"
}

# base_compare <file> <version> <hash> — ties the hash to the version against the compare
# point. The base's hash is recomputed from its file with the CURRENT rule, never read
# from the base's table, so a change of rule cannot read as an edit. No base file: a new
# template, passes. A lower version fails; the same version with other content fails.
base_compare() {
  local t="$1" version="$2" hash="$3" blob base_version base_hash label hint
  label="$t version moves with its content"
  if (( COMPARE_AT_TIP )); then
    hint="if this branch predates that bump, merge $BASE_USED rather than bumping here"
  else
    hint="this branch lowered it since forking from $BASE_USED"
  fi
  blob="$(mktemp "${TMPDIR:-/tmp}/template-base.XXXXXX")"
  if ! git -C "$BASE_REPO" show "$COMPARE_REF:$BASE_TEMPLATE_DIR/$t" > "$blob" 2>/dev/null; then
    rm -f "$blob"
    ok "$label (new template, nothing on $COMPARE_LABEL)"
    return 0
  fi
  base_version="$(template_version "$blob")"
  base_hash="$(stamped_hash "$blob")"
  rm -f "$blob"
  if [[ -z "$base_version" ]]; then
    ok "$label (no version line on $COMPARE_LABEL)"
  elif (( version < base_version )); then
    fail "$label" "version $version is below $COMPARE_LABEL's $base_version; a version never goes backwards — $hint"
  elif (( version == base_version )) && [[ "$hash" != "$base_hash" ]]; then
    fail "$label" "content differs from $COMPARE_LABEL but the version is still $version — re-recording the hash is not a bump; bump the '# template-version:' line first, then re-record"
  else
    ok "$label"
  fi
}

echo "template-versions"

if [[ ! -f "$VERSIONS_TABLE" ]]; then
  fail "version table present" "$VERSIONS_TABLE does not exist"
  echo
  echo "template-versions: $fails check(s) failed"
  exit 1
fi
ok "version table present"

# The base must be readable: without it a re-recorded hash cannot be told from a bump.
if ! BASE_USED="$(resolve_base)"; then
  fail "base branch available" \
    "neither $BASE_REF nor local $FALLBACK_BASE_BRANCH resolves in $BASE_REPO — run: git fetch origin main (a depth-1 fetch is enough)"
  echo
  echo "template-versions: $fails check(s) failed"
  exit 1
fi
ok "base branch available ($BASE_USED)"

COMPARE_REF="$(resolve_compare_point)"
if [[ "$COMPARE_REF" == "$BASE_USED" ]]; then COMPARE_AT_TIP=1; else COMPARE_AT_TIP=0; fi
if (( COMPARE_AT_TIP )); then
  COMPARE_LABEL="$BASE_USED"
  ok "compare point: tip of $BASE_USED (no shared history with HEAD)"
else
  COMPARE_LABEL="the fork point from $BASE_USED (${COMPARE_REF:0:$SHORT_SHA_LEN})"
  ok "compare point: $COMPARE_LABEL"
fi

for t in "${TEMPLATES[@]}"; do
  path="$TEMPLATE_DIR/$t"
  if [[ ! -f "$path" ]]; then
    fail "$t version and content hash are recorded" "$path does not exist"
    continue
  fi
  version="$(template_version "$path")"
  hash="$(stamped_hash "$path")"
  want_version="$(table_field "$t" 1)"
  want_hash="$(table_field "$t" 2)"
  if [[ -z "$want_version" || -z "$want_hash" ]]; then
    fail "$t version and content hash are recorded" \
      "no row for $t in TEMPLATE_VERSIONS — add '$t ${version:-0} $hash'"
  elif [[ -z "$version" ]]; then
    fail "$t version and content hash are recorded" \
      "templates/plans/$t carries no '# template-version:' line; $BUMP_HINT"
  elif [[ "$version" != "$want_version" ]]; then
    fail "$t version and content hash are recorded" \
      "templates/plans/$t is version $version, TEMPLATE_VERSIONS records $want_version; $BUMP_HINT"
  elif [[ "$hash" != "$want_hash" ]]; then
    fail "$t version and content hash are recorded" \
      "templates/plans/$t changed (comments count) but is still version $version; $BUMP_HINT"
  else
    ok "$t version and content hash are recorded"
    base_compare "$t" "$version" "$hash"
  fi
done

echo
if (( fails > 0 )); then
  echo "template-versions: $fails check(s) failed"
  exit 1
fi
echo "template-versions: all checks passed"
