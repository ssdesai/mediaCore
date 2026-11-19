#!/usr/bin/env bash
set -uo pipefail

# Self-test that harness/methods/split-tests/ stays vanilla-conv plus an independent test
# author (harness/methods/split-tests/README.md). Run by self/gate.sh, or by hand:
#   bash self/tests/split-tests-pair.sh
#
# split-tests' template.md carries two briefs split at one marker line: the test author's,
# then the implementer's. The implementer's must be vanilla-conv's brief plus exactly one
# added paragraph, so the arm measures the test author and nothing else; this derives the
# expected implementer half from vanilla-conv/template.md and fails on any other difference.
#
# Asserts: 1. the marker is there once, both halves open with the `feature:` line, and the
# implementer half is vanilla-conv/template.md with one paragraph inserted before `## Finish`
# — a paragraph carrying the sha slot and the "Test changes" heading, and found nowhere in
# vanilla-conv; 2. template.md fills through harness_fill_template with nothing left, uses
# no placeholder vanilla-conv lacks, and a copy with an unknown @@NAME@@ in the author half
# still aborts the fill; 3. run.sh is executable and launches both sessions from the tree
# with vanilla-conv's flags; 4. run.sh end to end with a fake `claude` behind
# HARNESS_CLAUDE_BIN: a good author then an implementer (exit 0, the briefs as sent, the sha
# filled, the test diff in the log directory naming the edited test and not the source); an
# author who commits nothing, commits a source file, commits a README in a folder with none
# of its tests, leaves source uncommitted, uses the wrong subject, or commits after the tests
# commit, on its own or before a usage limit, or leaves source uncommitted at a usage limit
# after its tests commit (exit 1, no implementer); tests kept beside their
# source with that folder's README, and a root conftest.py (exit 0); an author on a usage
# limit (exit 2, the result where the harness reads it); a re-entry after it (no second
# author); a failing implementer (exit 1, the diff still written); 5. the branch name
# (exportStoreSplitTests).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
METHODS="$HERE/harness/methods"
CONV="$METHODS/vanilla-conv"
SPLIT="$METHODS/split-tests"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/split-tests-pair.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

MARKER='<!-- split-tests: the implementer brief starts on the next line -->'
SHA_SLOT='%%TESTS_SHA%%'
FEATURE_LINE='feature: @@SLUG@@'
FINISH_HEADING='## Finish'
TEST_CHANGES='"Test changes"'
CLAUDE_FLAGS_LINE='--model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools Bash'
AUTHOR_TEXT='Write the acceptance tests'
SLUG=e2e
GIT_ID=(-c user.name=t -c user.email=t@t)

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── 1: the two briefs ────────────────────────────────────────────────────────
check "1a. template.md carries the split marker exactly once" '[[ "$(grep -cxF -- "$MARKER" "$SPLIT/template.md")" == 1 ]]'
awk -v m="$MARKER" '$0 == m { exit } { print }' "$SPLIT/template.md" > "$TMP/author.md"
awk -v m="$MARKER" 'seen { print } $0 == m { seen = 1 }' "$SPLIT/template.md" > "$TMP/implementer.md"
check "1b. the author half opens with '$FEATURE_LINE'" '[[ "$(head -1 "$TMP/author.md")" == "$FEATURE_LINE" ]]'
check "1c. the implementer half opens with '$FEATURE_LINE'" '[[ "$(head -1 "$TMP/implementer.md")" == "$FEATURE_LINE" ]]'
check "1d. vanilla-conv/template.md has one '$FINISH_HEADING'" '[[ "$(grep -cxF -- "$FINISH_HEADING" "$CONV/template.md")" == 1 ]]'
# The added paragraph: the non-blank lines just above the blank line before ## Finish.
lines=()
while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done < "$TMP/implementer.md"
finish_at=-1
for (( i = 0; i < ${#lines[@]}; i++ )); do
  if [[ "${lines[$i]}" == "$FINISH_HEADING" ]]; then finish_at=$i; break; fi
done
: > "$TMP/paragraph.md"
if (( finish_at > 1 )) && [[ -z "${lines[$((finish_at - 1))]}" ]]; then
  start=$((finish_at - 2))
  while (( start > 0 )) && [[ -n "${lines[$((start - 1))]}" ]]; do start=$((start - 1)); done
  for (( i = start; i <= finish_at - 2; i++ )); do printf '%s\n' "${lines[$i]}" >> "$TMP/paragraph.md"; done
fi
check "1e. a paragraph sits right above '$FINISH_HEADING' in the implementer half" '[[ -s "$TMP/paragraph.md" ]]'
check "1f. it carries the sha slot $SHA_SLOT and the $TEST_CHANGES heading" \
  'grep -qF -- "$SHA_SLOT" "$TMP/paragraph.md" && grep -qF -- "$TEST_CHANGES" "$TMP/paragraph.md"'
check "1g. vanilla-conv has no line of it" '! grep -qxFf "$TMP/paragraph.md" "$CONV/template.md"'
EXPECTED="$TMP/expected.md"
: > "$EXPECTED"
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "$FINISH_HEADING" ]]; then cat "$TMP/paragraph.md" >> "$EXPECTED"; printf '\n' >> "$EXPECTED"; fi
  printf '%s\n' "$line" >> "$EXPECTED"
done < "$CONV/template.md"
diff "$EXPECTED" "$TMP/implementer.md" > "$TMP/implementer.diff" 2>&1; rc=$?
check "1h. the implementer half is vanilla-conv/template.md plus that paragraph, nothing else (diff rc $rc)" '[[ $rc -eq 0 ]]'
[[ $rc -ne 0 ]] && sed 's/^/        /' "$TMP/implementer.diff"
check "1i. the sha slot appears in the implementer half only" \
  '! grep -qF -- "$SHA_SLOT" "$TMP/author.md" && [[ "$(grep -cF -- "$SHA_SLOT" "$TMP/implementer.md")" == 1 ]]'

# ── 2: the fill ──────────────────────────────────────────────────────────────
fill() {   # fill <template> [tree] — the harness's own fill, as run.sh's caller does it
  (
    export HARNESS_TREE="${2:-/t}" HARNESS_BRANCH=b HARNESS_BASE=main HARNESS_SLUG="$SLUG" \
      HARNESS_SPEC_TREE=/spec HARNESS_SPEC_PATH=p HARNESS_SPEC_SECTIONS=1 \
      HARNESS_SPEC_PROVENANCE=prov HARNESS_FACTS=facts HARNESS_GATE_COMMAND=gate \
      HARNESS_GATE_MINUTES=1 HARNESS_FIXTURE=fx HARNESS_ISOLATION=iso
    # shellcheck source=../../harness/lib.sh
    source "$HERE/harness/lib.sh" && harness_fill_template "$1"
  )
}
fill "$SPLIT/template.md" > "$TMP/filled.md" 2>&1; rc=$?
check "2a. template.md fills (rc $rc) and carries no @@" '[[ $rc -eq 0 ]] && ! grep -q "@@" "$TMP/filled.md"'
grep -oE '@@[A-Z_]+@@' "$CONV/template.md" | sort -u > "$TMP/conv.ph"
grep -oE '@@[A-Z_]+@@' "$SPLIT/template.md" | sort -u > "$TMP/split.ph"
check "2b. it uses no placeholder vanilla-conv does not" '[[ -z "$(comm -13 "$TMP/conv.ph" "$TMP/split.ph")" ]]'
{ printf '@@NOT_A_HARNESS_NAME@@\n'; cat "$SPLIT/template.md"; } > "$TMP/bogus.md"
fill "$TMP/bogus.md" > "$TMP/bogus.out" 2>&1; rc=$?
check "2c. an unknown placeholder in the author half still aborts the fill, naming it" \
  '[[ $rc -ne 0 ]] && grep -q "@@NOT_A_HARNESS_NAME@@" "$TMP/bogus.out"'

# ── 3: run.sh ────────────────────────────────────────────────────────────────
check "3a. run.sh is executable" '[[ -x "$SPLIT/run.sh" ]]'
check "3b. vanilla-conv launches with the flags this test pins" 'grep -qF -- "$CLAUDE_FLAGS_LINE" "$CONV/run.sh"'
check "3c. split-tests holds the same flags for both sessions" 'grep -qF -- "CLAUDE_FLAGS=($CLAUDE_FLAGS_LINE)" "$SPLIT/run.sh"'
check "3d. both sessions launch from the tree with them" \
  '[[ "$(grep -cF -- "\"\$TREE\" \"\${CLAUDE_FLAGS[@]}\"" "$SPLIT/run.sh")" == 2 ]]'
check "3e. it fills its slot with the literal replace (marker and slot agree with this test)" \
  'grep -qF -- "$MARKER" "$SPLIT/run.sh" && grep -qF -- "$SHA_SLOT" "$SPLIT/run.sh" && grep -q harness_replace_literal "$SPLIT/run.sh"'

# ── 4: run.sh end to end with a fake claude ──────────────────────────────────
make_repo() {   # make_repo <dir> — a tree with a source and a tests folder, and the harness's untracked files
  local d="$1"
  mkdir -p "$d/src/components" "$d/tests" "$d/plans/features/$SLUG"
  git init -q "$d"
  echo 'def existing(): pass' > "$d/src/app.py"
  printf '# tests\n' > "$d/tests/README.md"
  printf '# components\n' > "$d/src/components/README.md"
  git -C "$d" add -A && git -C "$d" "${GIT_ID[@]}" commit -qm base
  echo manifest > "$d/plans/features/$SLUG/README.md"
  echo brief > "$d/plans/features/$SLUG/BRIEF.md"
}
FAKE="$TMP/fake-claude"
cat > "$FAKE" <<FAKECLAUDE
#!/usr/bin/env bash
# Plays the test author or the implementer, by the brief on stdin; FAKE_AUTHOR picks how
# the author behaves. Every prompt is kept in FAKE_SEEN, numbered.
prompt="\$(cat)"
n=\$(( \$(ls "\$FAKE_SEEN" | wc -l) + 1 ))
printf '%s\n' "\$prompt" > "\$FAKE_SEEN/\$n.md"
gitc() { git ${GIT_ID[*]} "\$@"; }
if [[ "\$prompt" == *"$AUTHOR_TEXT"* ]]; then
  case "\${FAKE_AUTHOR:-good}" in
    limit)
      printf '{"type":"result","is_error":true,"session_id":"a","total_cost_usd":0,"result":"Claude AI usage limit reached|1756500000"}\n'
      exit 1 ;;
    none) ;;
    source)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      echo 'def feature(): pass' > src/feature.py
      git add tests/test_feature.py src/feature.py && gitc commit -qm "$SLUG: acceptance tests" ;;
    dirty)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add tests/test_feature.py && gitc commit -qm "$SLUG: acceptance tests"
      echo 'def feature(): pass' > src/feature.py ;;
    subject)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add tests/test_feature.py && gitc commit -qm "tests" ;;
    after)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add tests/test_feature.py && gitc commit -qm "$SLUG: acceptance tests"
      echo 'def feature(): pass' > src/feature.py
      git add src/feature.py && gitc commit -qm "start the feature" ;;
    limitafter)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add tests/test_feature.py && gitc commit -qm "$SLUG: acceptance tests"
      echo 'def feature(): pass' > src/feature.py
      git add src/feature.py && gitc commit -qm "start the feature"
      printf '{"type":"result","is_error":true,"session_id":"a","total_cost_usd":0,"result":"Claude AI usage limit reached|1756500000"}\n'
      exit 1 ;;
    limitdirty)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add tests/test_feature.py && gitc commit -qm "$SLUG: acceptance tests"
      echo 'def feature(): pass' > src/feature.py
      printf '{"type":"result","is_error":true,"session_id":"a","total_cost_usd":0,"result":"Claude AI usage limit reached|1756500000"}\n'
      exit 1 ;;
    colocated)
      echo 'it("renders", () => { throw new Error("no Foo") })' > src/components/Foo.test.tsx
      echo '- Foo.test.tsx' >> src/components/README.md
      git add src/components/Foo.test.tsx src/components/README.md && gitc commit -qm "$SLUG: acceptance tests" ;;
    conftest)
      echo 'import pytest' > conftest.py
      echo 'def test_feature(): assert False' > tests/test_feature.py
      git add conftest.py tests/test_feature.py && gitc commit -qm "$SLUG: acceptance tests" ;;
    strayreadme)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      echo '- feature' >> src/components/README.md
      git add tests/test_feature.py src/components/README.md && gitc commit -qm "$SLUG: acceptance tests" ;;
    *)
      echo 'def test_feature(): assert False' > tests/test_feature.py
      echo '- test_feature.py' >> tests/README.md
      git add tests/test_feature.py tests/README.md && gitc commit -qm "$SLUG: acceptance tests" ;;
  esac
  printf '{"type":"result","session_id":"a","total_cost_usd":0,"result":"author done"}\n'
  exit 0
fi
echo 'def feature(): pass' > src/feature.py
echo '# loosened by the implementer' >> tests/test_feature.py
git add src tests && gitc commit -qm "implement"
printf '{"type":"result","session_id":"i","total_cost_usd":0,"result":"implementer done"}\n'
exit "\${FAKE_IMPL_RC:-0}"
FAKECLAUDE
chmod +x "$FAKE"

run_case() {   # run_case <name> [VAR=value...] — a fresh repo and log dir; sets R, LOGS, SEEN, rc
  local name="$1"; shift
  R="$TMP/$name/repo"; LOGS="$TMP/$name/logs"; SEEN="$TMP/$name/seen"
  mkdir -p "$LOGS" "$SEEN"; make_repo "$R"
  fill "$SPLIT/template.md" "$R" > "$TMP/$name/brief.md"
  env "$@" FAKE_SEEN="$SEEN" HARNESS_CLAUDE_BIN="$FAKE" HARNESS_LOG_DIR="$LOGS" HARNESS_BRANCH_NAME="$name" \
    HARNESS_METHOD_RESULT="$LOGS/$name-method-result.json" \
    "$SPLIT/run.sh" "$R" "$TMP/$name/brief.md" "$SLUG" > "$TMP/$name/run.log" 2>&1
  rc=$?
}
sessions() { ls "$SEEN" | wc -l | tr -d ' '; }

run_case good
SHA="$(git -C "$R" log --format=%H --grep="^$SLUG: acceptance tests\$" | head -1)"
check "4a. a good author then an implementer: exit 0, two sessions (rc $rc)" '[[ $rc -eq 0 && "$(sessions)" == 2 ]]'
check "4b. the author got the author half, filled" 'grep -qF -- "$AUTHOR_TEXT" "$SEEN/1.md" && head -1 "$SEEN/1.md" | grep -qx "feature: $SLUG" && ! grep -qF -- "$MARKER" "$SEEN/1.md"'
check "4c. the implementer got the implementer half, the sha filled in" \
  '[[ -n "$SHA" ]] && grep -qF -- "\`$SHA\` (\`$SLUG: acceptance tests\`)" "$SEEN/2.md" && ! grep -qF -- "$SHA_SLOT" "$SEEN/2.md" && ! grep -qF -- "$AUTHOR_TEXT" "$SEEN/2.md"'
check "4d. both briefs as sent are kept in the log directory" '[[ -s "$LOGS/good-author-brief.md" && -s "$LOGS/good-implementer-brief.md" ]]'
check "4e. the test diff is in the log directory and names the test the implementer edited, not its source" \
  'grep -q "tests/test_feature.py" "$LOGS/good-test-diff.txt" && ! grep -q "src/feature.py" "$LOGS/good-test-diff.txt"'
check "4f. the method result is the implementer's; the author's is beside it" \
  'grep -q "implementer done" "$LOGS/good-method-result.json" && grep -q "author done" "$LOGS/good-author-result.json"'
check "4g. nothing the method wrote is in the tree" '[[ -z "$(git -C "$R" status --porcelain --untracked-files=all | grep -v "plans/features/$SLUG/")" ]]'

for bad in none source dirty subject after strayreadme limitafter limitdirty; do
  run_case "$bad" FAKE_AUTHOR="$bad"
  check "4h. an author who does '$bad': exit 1, no implementer (rc $rc)" '[[ $rc -eq 1 && "$(sessions)" == 1 ]]'
done
check "4i. the source-file refusal names the file" 'grep -q "non-test file(s): src/feature.py" "$TMP/source/run.log"'
check "4i2. a README in a folder with none of the commit's tests is refused, naming it" \
  'grep -q "non-test file(s): src/components/README.md" "$TMP/strayreadme/run.log"'
check "4i3. a commit after the tests commit is refused on the usage-limit stop too, not resumed" \
  'grep -q "committed after .*before its usage limit" "$TMP/limitafter/run.log"'
check "4i4. work left uncommitted at the usage-limit stop is refused, naming it, not resumed" \
  'grep -q "uncommitted before its usage limit: src/feature.py" "$TMP/limitdirty/run.log"'
for good in colocated conftest; do
  run_case "$good" FAKE_AUTHOR="$good"
  check "4n. an author who does '$good' passes to the implementer (rc $rc)" '[[ $rc -eq 0 && "$(sessions)" == 2 ]]'
done
check "4n2. tests kept beside their source carry their folder's README" \
  'grep -qF "src/components/README.md" "$TMP/colocated/run.log" && grep -qF "src/components/Foo.test.tsx" "$TMP/colocated/run.log"'
check "4j. the uncommitted-work refusal names the file" 'grep -q "uncommitted: src/feature.py" "$TMP/dirty/run.log"'
check "4j2. a commit after the tests commit is refused, naming it" 'grep -q "committed after .*start the feature" "$TMP/after/run.log"'

run_case limit FAKE_AUTHOR=limit
check "4k. an author on a usage limit: exit 2, its result where the harness reads it (rc $rc)" \
  '[[ $rc -eq 2 && "$(sessions)" == 1 ]] && grep -q "usage limit" "$LOGS/limit-method-result.json"'
# The re-entry: the author's commit is already on the branch the harness re-runs into.
echo 'def test_feature(): assert False' > "$R/tests/test_feature.py"
git -C "$R" add tests/test_feature.py && git -C "$R" "${GIT_ID[@]}" commit -qm "$SLUG: acceptance tests"
env FAKE_SEEN="$SEEN" HARNESS_CLAUDE_BIN="$FAKE" HARNESS_LOG_DIR="$LOGS" HARNESS_BRANCH_NAME=limit \
  HARNESS_METHOD_RESULT="$LOGS/limit-method-result.json" \
  "$SPLIT/run.sh" "$R" "$TMP/limit/brief.md" "$SLUG" > "$TMP/limit/rerun.log" 2>&1; rc=$?
check "4l. a re-entry finds the tests commit and runs the implementer alone (rc $rc)" \
  '[[ $rc -eq 0 && "$(sessions)" == 2 ]] && ! grep -qF -- "$AUTHOR_TEXT" "$SEEN/2.md"'

run_case implfail FAKE_IMPL_RC=1
check "4m. a failing implementer: exit 1, the test diff still written (rc $rc)" \
  '[[ $rc -eq 1 ]] && grep -q "tests/test_feature.py" "$LOGS/implfail-test-diff.txt"'

# ── 5: branch name ───────────────────────────────────────────────────────────
branch() { ( source "$HERE/harness/lib.sh" && harness_branch_name "$@" ); }
check "5a. split-tests, one repeat: exportStoreSplitTests" '[[ "$(branch exportStore split-tests 1 1)" == exportStoreSplitTests ]]'

if (( fails > 0 )); then echo "split-tests-pair: $fails assertion(s) FAILED"; exit 1; fi
echo "split-tests-pair: all assertions passed"
