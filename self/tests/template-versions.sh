#!/usr/bin/env bash
set -uo pipefail

# Self-test: the repo-owned templates' `# template-version: N` lines are honest.
# Run by self/gate.sh, or by hand: bash self/tests/template-versions.sh
#
# Why this exists. The whole drift mechanism — sync-plans.sh's template_version compare,
# the `DRIFT` line a consuming repo acts on — rests on an author remembering to bump the
# number when a template's body changes. Nothing could see an edit that did not: such a
# change reports `in-sync` in every consumer while their seeded copies are stale, which
# is worse than having no drift detection at all. sync-check.sh's assertion 8 cannot
# catch it either; it only asserts templates/plans/X and self/X carry the *same* number.
#
# Mechanism: templates/plans/TEMPLATE_VERSIONS is a checked-in table, one line per
# template, `<file> <version> <sha256>`. The hash is taken over the file with
# comment-only and blank lines stripped, so a comment or documentation edit never forces
# a bump while any change to the code does. A body edit therefore goes red here, naming
# the file, until the version line is bumped and the hash re-recorded.
#
# This is not the "contract-header diffing" the sweep-and-check manifest excludes — that
# was about how a *consumer* detects drift. This keeps the version line honest at source.
#
# Prints one `  ok    <label>` / `  FAIL  <label>: <detail>` line per template and exits
# non-zero if any FAILed, the shape its neighbours in this directory use.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="$HERE/templates/plans"
VERSIONS_TABLE="$TEMPLATE_DIR/TEMPLATE_VERSIONS"
VERSION_LINE_RE='^# template-version:[[:space:]]*\([0-9][0-9]*\).*'
# The three seeded, repo-owned scripts — templates/README.md's list. The generated stubs
# are overwritten on every sync and carry no version line.
TEMPLATES=(gate.sh pr.sh worktree-setup.sh)
BUMP_HINT="bump template-version and re-record the hash in templates/plans/TEMPLATE_VERSIONS"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1: $2"; fails=$((fails + 1)); }

# The recorded hash's definition, in one place: strip comment-only and blank lines so a
# comment edit is free, then hash what is left.
stripped_hash() {
  grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$' | shasum -a 256 | awk '{print $1}'
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

echo "template-versions"

if [[ ! -f "$VERSIONS_TABLE" ]]; then
  fail "version table present" "$VERSIONS_TABLE does not exist"
  echo
  echo "template-versions: $fails check(s) failed"
  exit 1
fi
ok "version table present"

for t in "${TEMPLATES[@]}"; do
  path="$TEMPLATE_DIR/$t"
  if [[ ! -f "$path" ]]; then
    fail "$t version and content hash are recorded" "$path does not exist"
    continue
  fi
  version="$(template_version "$path")"
  hash="$(stripped_hash "$path")"
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
      "templates/plans/$t changed below its comments but is still version $version; $BUMP_HINT"
  else
    ok "$t version and content hash are recorded"
  fi
done

echo
if (( fails > 0 )); then
  echo "template-versions: $fails check(s) failed"
  exit 1
fi
echo "template-versions: all checks passed"
