#!/usr/bin/env bash
set -uo pipefail

# Behavioural test of the README-index checker (self/features/readme-index-check/).
# Run by self/gate.sh, or by hand: bash self/tests/readme-index.sh
#
# Copies check-readme-index.py into a mktemp -d, builds small `git init` repos beside it
# (files staged, never committed) and runs the copy over each with `python3 -B`, so the
# real checkout is never touched. Asserts, per case:
#   I1  a clean repo exits 0 and says so;           I2  an unlisted file is reported (exit 1);
#   I3  an unlisted subfolder is reported;           I4  a file is checked against its own
#   folder's README only;                            I5  only tracked, present files count;
#   I6  the recognition rule's boundaries and case;  I7  --report-only exits 0;
#   I8  the ignore list (folder-only patterns, comments, ancestors);
#   I9  usage errors exit 2;                         I10 not a checkout exits 2;
#   I11 a generated README is checked against the repo-owned file its header names;
#   I12 nothing is written (status, index, __pycache__);
#   I13 a subfolder is named by its bare name.
# No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/readme-index.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
CHECKER="$TMP/bin/check-readme-index.py"
CHECKER_MISSING=0
if [ -f "$HERE/check-readme-index.py" ]; then
  cp "$HERE/check-readme-index.py" "$CHECKER"
else
  CHECKER_MISSING=1
fi

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
assert() { local label="$1"; shift; if "$@"; then ok "$label"; else fail "$label"; fi; }

# Exit codes and output
OUT=""
RC=0
MISSING_RC=99
EXIT_CLEAN=0
EXIT_MISSING=1
EXIT_ERROR=2

run_check() {
  local root="$1"; shift
  if [ "$CHECKER_MISSING" -eq 1 ]; then
    OUT="check-readme-index.py is missing"
    RC=$MISSING_RC
    return 0
  fi
  OUT="$(python3 -B "$CHECKER" --root "$root" "$@" 2>&1)"
  RC=$?
}

has_line() { printf '%s\n' "$OUT" | grep -qxF -- "$1"; }
lacks()    { ! printf '%s\n' "$OUT" | grep -qF -- "$1"; }
no_line()  { ! has_line "$1"; }
contains() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
rc_is()    { [ "$RC" -eq "$1" ]; }
last_line_starts() {
  local l
  l="$(printf '%s\n' "$OUT" | tail -n 1)"
  case "$l" in "$1"*) return 0 ;; esac
  return 1
}
last_line_is() { [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "$1" ]; }

# Fixture helpers
put() { # put <dir> <relpath> <text>
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
}
stage() { git -C "$1" add -A; }
new_repo() { mkdir -p "$1"; git init -q "$1"; }

gen_readme() { # gen_readme <dir> <relpath> <owned path> [extra line]
  local f="$1/$2"
  mkdir -p "$(dirname "$f")"
  {
    printf '%s\n' '# Generated'
    printf '%s\n' ''
    printf '%s\n' '_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`, and'
    printf '%s\n' "**overwritten on every pull** — never edit it. Entries go in the repo-owned \`$3\`._"
    printf '%s\n' ''
    if [ -n "${4:-}" ]; then printf '%s\n' "$4"; fi
  } > "$f"
}

# I1 base: clean repo
mk_base() {
  new_repo "$1"
  put "$1" README.md 'Files: `a.sh`, `sub/`.'
  put "$1" sub/README.md 'Files: `b.txt`.'
  put "$1" a.sh 'echo a'
  put "$1" sub/b.txt 'b'
  stage "$1"
}

# Repos built up front so I12 can snapshot the two it names
R1="$TMP/r1"
R2="$TMP/r2"
R11="$TMP/r11"

mk_base "$R1"

mk_base "$R2"
put "$R2" c.sh 'echo c'
stage "$R2"

new_repo "$R11"
put "$R11" README.md 'Folders: `plans/`.'
gen_readme "$R11" plans/README.md PROJECT_FACTS.md '- `gate.sh` — the gate.'
printf '%s\n' '- `features/` — the features.' >> "$R11/plans/README.md"
put "$R11" plans/PROJECT_FACTS.md 'Also `extra.sh`.'
put "$R11" plans/gate.sh 'echo gate'
put "$R11" plans/extra.sh 'echo extra'
put "$R11" plans/other.sh 'echo other'
gen_readme "$R11" plans/features/README.md ../MISSING.md
put "$R11" plans/features/x.md 'x'
stage "$R11"

snapshot() {
  GIT_OPTIONAL_LOCKS=0 git -C "$1" status --porcelain
  cksum "$1/.git/index"
}
SNAP2_BEFORE="$(snapshot "$R2")"
SNAP11_BEFORE="$(snapshot "$R11")"

if [ "$CHECKER_MISSING" -eq 1 ]; then
  fail "check-readme-index.py is missing at $HERE (every case below fails)"
fi

# ── I1 clean ─────────────────────────────────────────────────────────────────
run_check "$R1"
assert "I1 clean repo exits 0" rc_is $EXIT_CLEAN
assert "I1 clean repo says none missing" has_line "readme-index: 2 READMEs checked, none missing"

# ── I2 unlisted file ─────────────────────────────────────────────────────────
run_check "$R2"
assert "I2 unlisted file exits 1" rc_is $EXIT_MISSING
assert "I2 reports README.md: c.sh" has_line "README.md: c.sh"
assert "I2 summary line" last_line_starts "readme-index: 1 missing in 1 of 2 READMEs checked"

# ── I3 unlisted subfolder ────────────────────────────────────────────────────
R3="$TMP/r3"
mk_base "$R3"
put "$R3" newdir/x.txt 'x'
stage "$R3"
run_check "$R3"
assert "I3 reports README.md: newdir/" has_line "README.md: newdir/"
assert "I3 does not report newdir/x.txt" lacks "newdir/x.txt"

# ── I4 depth ─────────────────────────────────────────────────────────────────
R4="$TMP/r4"
mk_base "$R4"
put "$R4" sub/c2.txt 'c2'
stage "$R4"
run_check "$R4"
assert "I4 reports sub/README.md: sub/c2.txt" has_line "sub/README.md: sub/c2.txt"
assert "I4 does not report it against the root README" no_line "README.md: sub/c2.txt"

# ── I5 tracked only ──────────────────────────────────────────────────────────
R5="$TMP/r5"
new_repo "$R5"
put "$R5" README.md 'Files: `a.sh`, `sub/`, `.gitignore`.'
put "$R5" sub/README.md 'Files: `b.txt`.'
put "$R5" a.sh 'echo a'
put "$R5" sub/b.txt 'b'
put "$R5" .gitignore 'ignored.log'
put "$R5" ignored.log 'noise'
put "$R5" gone.sh 'echo gone'
stage "$R5"
put "$R5" untracked.sh 'echo untracked'
rm -f "$R5/gone.sh"
run_check "$R5"
assert "I5 exits 0" rc_is $EXIT_CLEAN
assert "I5 ignores an untracked file" lacks "untracked.sh"
assert "I5 ignores a gitignored file" lacks "ignored.log"
assert "I5 ignores a deleted tracked file" lacks "gone.sh"

# ── I6 boundaries and case ───────────────────────────────────────────────────
R6="$TMP/r6"
new_repo "$R6"
put "$R6" README.md 'Integrate the gates. See tools/run.sh. Old copy: tool.py.bak. Also Notes.md.'
put "$R6" gate 'g'
put "$R6" run.sh 'r'
put "$R6" tool.py 't'
put "$R6" notes.md 'n'
stage "$R6"
run_check "$R6"
assert "I6 gate is not named by integrate/gates" has_line "README.md: gate"
assert "I6 tool.py is not named by tool.py.bak" has_line "README.md: tool.py"
assert "I6 notes.md is not named by Notes.md" has_line "README.md: notes.md"
assert "I6 run.sh is named by tools/run.sh." no_line "README.md: run.sh"

# ── I7 report-only ───────────────────────────────────────────────────────────
run_check "$R2" --report-only
assert "I7 report-only exits 0" rc_is $EXIT_CLEAN
assert "I7 still reports README.md: c.sh" has_line "README.md: c.sh"
assert "I7 summary says report only" last_line_is "readme-index: 1 missing in 1 of 2 READMEs checked (report only)"

# ── I8 ignore list ───────────────────────────────────────────────────────────
R8="$TMP/r8"
new_repo "$R8"
put "$R8" README.md 'Folders: `records/`, file `ignore.txt`.'
printf '%s\n' '# comment' '' 'records/*/' 'fixtures/' > "$R8/ignore.txt"
put "$R8" records/README.md 'Records.'
put "$R8" records/r1/README.md 'Manifest.'
put "$R8" records/r1/auto/p.md 'p'
put "$R8" records/loose.md 'l'
put "$R8" fixtures/README.md 'Data.'
put "$R8" fixtures/f.json '{}'
stage "$R8"
run_check "$R8" --ignore "$R8/ignore.txt"
assert "I8 exits 1" rc_is $EXIT_MISSING
assert "I8 a folder-only pattern does not match a file" has_line "records/README.md: records/loose.md"
assert "I8 ignored folder records/r1 not mentioned" lacks "records/r1"
assert "I8 ignored folder fixtures not mentioned" lacks "fixtures"

# ── I9 usage errors ──────────────────────────────────────────────────────────
run_check "$R1" --ignore "$TMP/nonexistent"
assert "I9 unreadable ignore file exits 2" rc_is $EXIT_ERROR
assert "I9 unreadable ignore file names the error" contains "readme-index: error:"
printf '%s\n' '/abs' > "$TMP/abs.ign"
run_check "$R1" --ignore "$TMP/abs.ign"
assert "I9 an absolute pattern exits 2" rc_is $EXIT_ERROR
printf '%s\n' 'a/../b' > "$TMP/dots.ign"
run_check "$R1" --ignore "$TMP/dots.ign"
assert "I9 a .. segment exits 2" rc_is $EXIT_ERROR
run_check "$R1" --bogus
assert "I9 an unknown flag exits 2" rc_is $EXIT_ERROR

# ── I10 not a checkout ───────────────────────────────────────────────────────
mkdir -p "$TMP/plain"
printf '%s\n' 'Plain.' > "$TMP/plain/README.md"
export GIT_CEILING_DIRECTORIES="$TMP"
run_check "$TMP/plain"
unset GIT_CEILING_DIRECTORIES
assert "I10 not a checkout exits 2" rc_is $EXIT_ERROR
assert "I10 not a checkout names the error" contains "readme-index: error:"

# ── I11 generated README ─────────────────────────────────────────────────────
run_check "$R11"
assert "I11 exits 1" rc_is $EXIT_MISSING
assert "I11 checked against the repo-owned file" has_line "plans/PROJECT_FACTS.md (generated plans/README.md): plans/other.sh"
assert "I11 an absent owned file counts as empty" has_line "plans/MISSING.md (generated plans/features/README.md): plans/features/x.md"
assert "I11 owned file's entries are named" lacks "plans/extra.sh"
assert "I11 README's own entries are named" lacks "plans/gate.sh"

# ── I13 a subfolder is named by its name ─────────────────────────────────────
R13="$TMP/r13"
mk_base "$R13"
put "$R13" README.md 'Files: `a.sh`. The sub folder.'
stage "$R13"
run_check "$R13"
assert "I13 a bare subfolder name names it" rc_is $EXIT_CLEAN

# ── I12 read-only ────────────────────────────────────────────────────────────
assert "I12 I2 repo status and index unchanged" test "$SNAP2_BEFORE" = "$(snapshot "$R2")"
assert "I12 I11 repo status and index unchanged" test "$SNAP11_BEFORE" = "$(snapshot "$R11")"
assert "I12 no __pycache__ written" test -z "$(find "$TMP" -name __pycache__)"

if [ "$fails" -gt 0 ]; then
  echo "readme-index: $fails check(s) FAILED"
  exit 1
fi
echo "readme-index: all checks passed"
