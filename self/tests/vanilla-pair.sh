#!/usr/bin/env bash
set -uo pipefail

# Self-test that harness/methods/vanilla/ and vanilla-conv/ stay one layer apart
# (harness/methods/vanilla/README.md). Run by self/gate.sh, or by hand:
#   bash self/tests/vanilla-pair.sh
#
# The two are the bottom rungs of the tooling-ablation ladder: the same minimal brief, the
# one run with the tree's conventions and command hook live, the other with both taken out
# for the build. They may differ in that and in nothing else, and neither may carry doctrine.
#
# Asserts: 1. the two templates are byte-identical, fill through harness_fill_template with
# no placeholder left, use no placeholder direct lacks, carry the harness's own parts (the
# feature line, isolation, the forge PR step, the banner) and none of the doctrine's words;
# 2. vanilla-conv/run.sh is executable and equals direct/run.sh once comments and the method
# name are set aside; vanilla/run.sh is executable and equals vanilla-conv/run.sh once its
# `# vanilla-only` lines are removed too; 3. neutralize.sh on a throwaway repo: the import
# lines and the hooks/permissions keys go, the rest of each file stays, git status is clean,
# a `git add -A` commit carries none of it, verify passes, restore puts HEAD back and clears
# every skip-worktree bit, a leaked commit fails verify, a killed attempt is restored by the
# next neutralization, and a tree with nothing to take out is left alone; 4. vanilla/run.sh
# end to end with a fake claude that records what it saw and commits with `git add -A`,
# then one whose commit leaks a neutralized file (exit 1) and one killed by TERM (restored); 5.
# the branch names (exportStoreVanilla, exportStoreVanillaConv2).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
METHODS="$HERE/harness/methods"
DIRECT="$METHODS/direct"
VANILLA="$METHODS/vanilla"
CONV="$METHODS/vanilla-conv"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/vanilla-pair.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

ONLY_MARK='# vanilla-only'
DOCTRINE_RE='CLAUDE\.md|CONVENTIONS|PROJECT_FACTS|README|[Nn]amed constant|CHECKPOINT|stamp-timing|AGENT_DIRECT|AGENT_PLANS|acceptance test'
HARNESS_PARTS=('feature: @@SLUG@@' '@@ISOLATION@@' 'forge.sh pr-open' 'one arm of an experiment — do not merge until it picks a winner' '@@GATE_COMMAND@@')
IMPORT_ROOT='@agentTooling/CONVENTIONS.md'
IMPORT_NESTED='@CONVENTIONS.md'
PROJECT_LINE='## Project status — kept'
GIT_ID=(-c user.name=t -c user.email=t@t)

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# ── 1: the briefs ────────────────────────────────────────────────────────────
check "1a. vanilla/template.md and vanilla-conv/template.md are byte-identical" \
  'cmp -s "$VANILLA/template.md" "$CONV/template.md"'
fill() {
  (
    export HARNESS_TREE=/t HARNESS_BRANCH=b HARNESS_BASE=main HARNESS_SLUG=s \
      HARNESS_SPEC_TREE=/spec HARNESS_SPEC_PATH=p HARNESS_SPEC_SECTIONS=1 \
      HARNESS_SPEC_PROVENANCE=prov HARNESS_FACTS=facts HARNESS_GATE_COMMAND=gate \
      HARNESS_GATE_MINUTES=1 HARNESS_FIXTURE=fx HARNESS_ISOLATION=iso
    # shellcheck source=../../harness/lib.sh
    source "$HERE/harness/lib.sh" && harness_fill_template "$1"
  )
}
fill "$VANILLA/template.md" > "$TMP/vanilla.filled" 2>&1; rc=$?
check "1b. the vanilla brief fills (rc $rc) and carries no @@" '[[ $rc -eq 0 ]] && ! grep -q "@@" "$TMP/vanilla.filled"'
grep -oE '@@[A-Z_]+@@' "$DIRECT/template.md" | sort -u > "$TMP/direct.ph"
grep -oE '@@[A-Z_]+@@' "$VANILLA/template.md" | sort -u > "$TMP/vanilla.ph"
check "1c. it uses no placeholder direct does not" '[[ -z "$(comm -13 "$TMP/direct.ph" "$TMP/vanilla.ph")" ]]'
for part in "${HARNESS_PARTS[@]}"; do
  check "1d. it keeps the harness's own part: $part" 'grep -qF -- "$part" "$VANILLA/template.md"'
done
check "1e. it names none of the doctrine ($DOCTRINE_RE)" '! grep -qE "$DOCTRINE_RE" "$VANILLA/template.md"'

# ── 2: the run.sh pairs ──────────────────────────────────────────────────────
check "2a. both run.sh are executable" '[[ -x "$VANILLA/run.sh" && -x "$CONV/run.sh" ]]'
grep -v '^#' "$DIRECT/run.sh" > "$TMP/direct.run"
grep -v '^#' "$CONV/run.sh" | sed 's/vanilla-conv/direct/g' > "$TMP/conv-as-direct.run"
check "2b. vanilla-conv/run.sh is direct/run.sh apart from comments and the name" \
  'diff -q "$TMP/direct.run" "$TMP/conv-as-direct.run" >/dev/null'
grep -v '^#' "$CONV/run.sh" | sed 's/vanilla-conv/vanilla/g' > "$TMP/conv-as-vanilla.run"
grep -v '^#' "$VANILLA/run.sh" | grep -vF -- "$ONLY_MARK" > "$TMP/vanilla-shared.run"
check "2c. vanilla/run.sh is vanilla-conv/run.sh plus its '$ONLY_MARK' lines" \
  'diff -q "$TMP/conv-as-vanilla.run" "$TMP/vanilla-shared.run" >/dev/null'
check "2d. vanilla/run.sh has '$ONLY_MARK' lines to remove" '[[ $(grep -cF -- "$ONLY_MARK" "$VANILLA/run.sh") -ge 4 ]]'
check "2e. both launch claude with the tree as cwd (harness_claude ... \"\$TREE\")" \
  'grep -q "harness_claude \"\$RESULT\" \"\$BRIEF\" \"\$TREE\"" "$VANILLA/run.sh" && grep -q "harness_claude \"\$RESULT\" \"\$BRIEF\" \"\$TREE\"" "$CONV/run.sh"'

# ── 3: neutralize.sh on a throwaway repo ─────────────────────────────────────
make_repo() {   # make_repo <dir> — a tree with the shapes a consumer has
  local d="$1"
  mkdir -p "$d/.claude" "$d/agentTooling" "$d/frontend"
  git init -q "$d"
  printf '%s\n\n%s\nUse uv run pytest.\n' "$IMPORT_ROOT" "$PROJECT_LINE" > "$d/CLAUDE.md"
  printf '%s\n\n## What this directory is\n' "$IMPORT_NESTED" > "$d/agentTooling/CLAUDE.md"
  printf '# frontend notes\nmentions CONVENTIONS.md in prose, not as an import\n' > "$d/frontend/CLAUDE.md"
  cat > "$d/.claude/settings.json" <<'JSON'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "x"}]}]},
 "permissions": {"deny": ["Bash(git clean:*)"]},
 "sandbox": {"enabled": false}}
JSON
  echo code > "$d/app.py"
  git -C "$d" add -A && git -C "$d" "${GIT_ID[@]}" commit -qm base
}
lib() { source "$HERE/harness/lib.sh" && source "$VANILLA/neutralize.sh"; }

R="$TMP/repo"; make_repo "$R"
BASE_SHA="$(git -C "$R" rev-parse HEAD)"
( lib && vanilla_neutralize "$R" ) > "$TMP/n.log" 2>&1; rc=$?
check "3a. neutralize exits 0" '[[ $rc -eq 0 ]]'
check "3b. the root import is gone, the project text stays" \
  '! grep -qxF "$IMPORT_ROOT" "$R/CLAUDE.md" && grep -qxF "$PROJECT_LINE" "$R/CLAUDE.md"'
check "3c. the vendored copy's own import is gone" '! grep -qxF "$IMPORT_NESTED" "$R/agentTooling/CLAUDE.md"'
check "3d. a CLAUDE.md with no import line is untouched" 'git -C "$R" diff --quiet -- frontend/CLAUDE.md && [[ "$(git -C "$R" ls-files -v frontend/CLAUDE.md)" == H* ]]'
check "3e. settings lose hooks and permissions, keep sandbox" \
  'jq -e "(has(\"hooks\") or has(\"permissions\")) | not" "$R/.claude/settings.json" >/dev/null && jq -e ".sandbox.enabled == false" "$R/.claude/settings.json" >/dev/null'
check "3f. git status is clean while neutralized" '[[ -z "$(git -C "$R" status --porcelain)" ]]'
echo more >> "$R/app.py"
git -C "$R" add -A && git -C "$R" "${GIT_ID[@]}" commit -qam "the build" 2>/dev/null
check "3g. a git add -A commit carries only the feature" '[[ "$(git -C "$R" diff --name-only HEAD~1 HEAD)" == app.py ]]'
( lib && git -C "$R" add CLAUDE.md ) >/dev/null 2>&1
check "3h. an explicit git add of a neutralized file stages nothing" 'git -C "$R" diff --cached --quiet'
( lib && vanilla_verify "$R" "$BASE_SHA" ) >/dev/null 2>&1; rc=$?
check "3i. verify passes on an honest build" '[[ $rc -eq 0 ]]'
( lib && vanilla_restore "$R" ) > /dev/null 2>&1; rc=$?
check "3j. restore exits 0 and leaves the tree clean" '[[ $rc -eq 0 && -z "$(git -C "$R" status --porcelain)" ]]'
check "3k. every file is HEAD's again" 'grep -qxF "$IMPORT_ROOT" "$R/CLAUDE.md" && jq -e "has(\"hooks\")" "$R/.claude/settings.json" >/dev/null'
check "3l. no skip-worktree bit is left" '! git -C "$R" ls-files -v | grep -q "^S"'
check "3m. no list is left in the git dir" '[[ ! -e "$R/.git/harness-vanilla-neutralized" ]]'

# A leak: a commit since the start changed a neutralized file.
L="$TMP/leak"; make_repo "$L"; LEAK_BASE="$(git -C "$L" rev-parse HEAD)"
( lib && vanilla_neutralize "$L" ) >/dev/null 2>&1
git -C "$L" update-index --no-skip-worktree CLAUDE.md
git -C "$L" add CLAUDE.md && git -C "$L" "${GIT_ID[@]}" commit -qm leak
( lib && vanilla_verify "$L" "$LEAK_BASE" ) > "$TMP/leak.log" 2>&1; rc=$?
check "3n. verify fails on a commit that carries a neutralized file, naming it" '[[ $rc -ne 0 ]] && grep -q "CLAUDE.md" "$TMP/leak.log"'

# A killed attempt: neutralize twice; the second restores first and ends the same.
K="$TMP/killed"; make_repo "$K"
( lib && vanilla_neutralize "$K" && vanilla_neutralize "$K" ) > "$TMP/killed.log" 2>&1; rc=$?
check "3o. a second neutralization over a killed attempt restores first and succeeds" \
  '[[ $rc -eq 0 ]] && grep -q "earlier attempt" "$TMP/killed.log" && [[ $(wc -l < "$K/.git/harness-vanilla-neutralized") -eq 3 ]]'
( lib && vanilla_restore "$K" ) >/dev/null 2>&1
check "3p. ... and one restore then cleans it" '[[ -z "$(git -C "$K" status --porcelain)" ]] && ! git -C "$K" ls-files -v | grep -q "^S"'

# Nothing to take out.
N="$TMP/none"; mkdir -p "$N"; git init -q "$N"; echo '# plain' > "$N/CLAUDE.md"
git -C "$N" add -A && git -C "$N" "${GIT_ID[@]}" commit -qm base
( lib && vanilla_neutralize "$N" ) > "$TMP/none.log" 2>&1; rc=$?
check "3q. a tree with no import and no settings is left alone, and the log says so" \
  '[[ $rc -eq 0 ]] && grep -q "nothing to neutralize" "$TMP/none.log" && ! git -C "$N" ls-files -v | grep -q "^S"'

# ── 4: vanilla/run.sh end to end with a fake claude ──────────────────────────
E="$TMP/e2e"; make_repo "$E"
FAKE="$TMP/fake-claude"
SEEN="$TMP/seen.txt"
cat > "$FAKE" <<FAKECLAUDE
#!/usr/bin/env bash
# Records what the session would load from its cwd, builds, commits with git add -A.
cat > /dev/null
{ grep -c '^@.*CONVENTIONS.md' CLAUDE.md; jq 'has("hooks")' .claude/settings.json; pwd; } > "$SEEN"
# FAKE_TERM: run.sh is killed mid-build — our parent is harness_claude's subshell, its
# parent run.sh (no setsid: macOS does not ship it)
[[ -n "\${FAKE_TERM:-}" ]] && { kill -TERM "\$(ps -o ppid= -p "\$PPID" | tr -d ' ')"; exit 0; }
# FAKE_LEAK: the build clears the bit on a neutralized file and commits it
[[ -n "\${FAKE_LEAK:-}" ]] && { git update-index --no-skip-worktree CLAUDE.md; echo leaked >> CLAUDE.md; }
echo built >> app.py
git add -A && git ${GIT_ID[*]} commit -qm "e2e build"
printf '{"session_id":"s","total_cost_usd":0,"result":"done"}\n'
exit "\${FAKE_RC:-0}"
FAKECLAUDE
chmod +x "$FAKE"
echo brief > "$TMP/brief.md"
E_BASE="$(git -C "$E" rev-parse HEAD)"
HARNESS_CLAUDE_BIN="$FAKE" HARNESS_METHOD_RESULT="$TMP/result.json" \
  "$VANILLA/run.sh" "$E" "$TMP/brief.md" e2e > "$TMP/e2e.log" 2>&1; rc=$?
check "4a. run.sh exits 0" '[[ $rc -eq 0 ]]'
check "4b. the session saw no import and no hook" '[[ "$(sed -n 1p "$SEEN")" == 0 && "$(sed -n 2p "$SEEN")" == false ]]'
check "4c. the session ran from the tree root" '[[ "$(sed -n 3p "$SEEN")" == "$E" ]]'
check "4d. the build commit carries only the feature" '[[ "$(git -C "$E" diff --name-only "$E_BASE" HEAD)" == app.py ]]'
check "4e. the tree is restored and clean afterwards" \
  '[[ -z "$(git -C "$E" status --porcelain)" ]] && grep -qxF "$IMPORT_ROOT" "$E/CLAUDE.md" && ! git -C "$E" ls-files -v | grep -q "^S"'
E2="$TMP/e2e-fail"; make_repo "$E2"
FAKE_RC=1 HARNESS_CLAUDE_BIN="$FAKE" HARNESS_METHOD_RESULT="$TMP/result2.json" \
  "$VANILLA/run.sh" "$E2" "$TMP/brief.md" e2e > "$TMP/e2e2.log" 2>&1; rc=$?
check "4f. a failing claude exits 1 and still leaves the tree restored" \
  '[[ $rc -eq 1 && -z "$(git -C "$E2" status --porcelain)" ]] && grep -qxF "$IMPORT_ROOT" "$E2/CLAUDE.md"'
E3="$TMP/e2e-leak"; make_repo "$E3"
FAKE_LEAK=1 HARNESS_CLAUDE_BIN="$FAKE" HARNESS_METHOD_RESULT="$TMP/result3.json" \
  "$VANILLA/run.sh" "$E3" "$TMP/brief.md" e2e > "$TMP/e2e3.log" 2>&1; rc=$?
check "4g. a build that commits a neutralized file fails the method (exit 1), naming it, and leaves no bit set" \
  '[[ $rc -eq 1 ]] && grep -q "changed CLAUDE.md" "$TMP/e2e3.log" && ! git -C "$E3" ls-files -v | grep -q "^S" && [[ ! -e "$E3/.git/harness-vanilla-neutralized" ]]'
E4="$TMP/e2e-term"; make_repo "$E4"
FAKE_TERM=1 HARNESS_CLAUDE_BIN="$FAKE" HARNESS_METHOD_RESULT="$TMP/result4.json" \
  "$VANILLA/run.sh" "$E4" "$TMP/brief.md" e2e > "$TMP/e2e4.log" 2>&1; rc=$?
check "4h. a run killed by TERM mid-build exits 143 and still restores the tree (rc $rc)" \
  '[[ $rc -eq 143 && -z "$(git -C "$E4" status --porcelain)" ]] && grep -qxF "$IMPORT_ROOT" "$E4/CLAUDE.md" && ! git -C "$E4" ls-files -v | grep -q "^S" && [[ ! -e "$E4/.git/harness-vanilla-neutralized" ]]'

# ── 5: branch names ──────────────────────────────────────────────────────────
branch() { ( source "$HERE/harness/lib.sh" && harness_branch_name "$@" ); }
check "5a. vanilla, one repeat: exportStoreVanilla" '[[ "$(branch exportStore vanilla 1 1)" == exportStoreVanilla ]]'
check "5b. vanilla-conv, repeat 2 of 3: exportStoreVanillaConv2" '[[ "$(branch exportStore vanilla-conv 2 3)" == exportStoreVanillaConv2 ]]'

if (( fails > 0 )); then echo "vanilla-pair: $fails assertion(s) FAILED"; exit 1; fi
echo "vanilla-pair: all assertions passed"
