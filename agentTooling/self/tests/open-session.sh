#!/usr/bin/env bash
set -uo pipefail

# Self-test for the session opener — `self/open-session.sh` and its consuming-repo
# counterpart `templates/plans/open-session.sh`
# (self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §3). Run by self/gate.sh, or by
# hand: bash self/tests/open-session.sh
#
# The defect. Both copies wrapped the worktree path in SINGLE QUOTES inside the
# `osascript` string — `do script "cd '$WORKTREE' && claude"` — which survives a space
# and nothing else. A path holding a `'` closes that quote early, a `"` closes the
# AppleScript string literal, and a `\` is eaten by AppleScript's own escaping. Terminal
# then starts the session in the wrong directory, or in none, and a session is billed to
# the branch of the directory it was launched in (../LIFECYCLE.md, rule 1) — so the
# mistake is silent and lands in the ledger as somebody else's money.
#
# What is asserted, per copy: with `osascript` stubbed on `PATH` to record the arguments
# it was handed, the opener run with a path holding a space, a `'`, a `"` and a `\`
# produces a `do script` string that, unescaped the way AppleScript unescapes a string
# literal and run by a shell with `claude` stubbed to print its `$PWD`, prints that path
# INTACT. That is the whole contract: two escaping layers, and the path reaches `claude`
# as it was handed in. Both copies must also be at `template-version: 3`, the version
# that has them (`self/tests/template-versions.sh` asserts the recorded hash).
#
# `feature-lifecycle.sh` S5 keeps the other half — that `--open` runs the hook at all,
# with the worktree path as its only argument, and that neither copy spells a chained
# `cd` as a command of its own. This file runs the body; that one reads it as text.
#
# No model, no network, and no Terminal: `osascript` and `claude` are both stubs in a
# throwaway PATH directory, so nothing is opened and nothing is billed.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/open-session.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

# The two copies under test, and the version both must carry after §3.
SELF_COPY="$HERE/self/open-session.sh"
TEMPLATE_COPY="$HERE/templates/plans/open-session.sh"
EXPECTED_TEMPLATE_VERSION="3"
VERSION_LINE_RE='^# template-version:[[:space:]]*\([0-9][0-9]*\).*'

# One directory name carrying every character the old quoting broke on: a space, a single
# quote, a double quote and a backslash. Nothing here is a path separator, so the name is
# legal on every filesystem this harness runs on.
NASTY_DIR="a b'c\"d\\e"
WT="$TMP/$NASTY_DIR/wt"
mkdir -p "$WT"

# Where the stub osascript records what it was handed, one argument per line. The
# `do script` argument carries no newline, so a line is an argument.
OSASCRIPT_OUT="$TMP/osascript.args"
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/osascript" <<STUB
#!/usr/bin/env bash
: > "$OSASCRIPT_OUT"
for arg in "\$@"; do printf '%s\n' "\$arg" >> "$OSASCRIPT_OUT"; done
STUB

# What Terminal.app would run last. Printing \$PWD is the whole measurement: it is the
# directory the session was launched in, which is what the billing rule reads.
cat > "$STUB_BIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$PWD"
STUB
chmod +x "$STUB_BIN/osascript" "$STUB_BIN/claude"

# AppleScript's string-literal unescaping, which is what Terminal does to the text before
# handing it to a shell: a backslash escapes the character after it, and nothing else.
cat > "$TMP/unescape.py" <<'PYEOF'
"""Print the `do script` argument recorded by the stub osascript, AppleScript-unescaped."""
import sys

MARKER = 'do script "'

for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    at = line.find(MARKER)
    if at < 0:
        continue
    body = line[at + len(MARKER):]
    if not body.endswith('"'):
        sys.exit("do script argument is not a closed AppleScript string: %r" % line)
    out, escaped = [], False
    for ch in body[:-1]:
        if escaped:
            out.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        else:
            out.append(ch)
    sys.stdout.write("".join(out))
    break
else:
    sys.exit("no `do script` argument was recorded")
PYEOF

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

template_version() {
  sed -n "s/$VERSION_LINE_RE/\\1/p" "$1" 2>/dev/null | head -n 1
}

# run_opener <script> — run one copy with the nasty worktree path and the stubs on PATH.
run_opener() {
  rm -f "$OSASCRIPT_OUT"
  ( PATH="$STUB_BIN:$PATH" bash "$1" "$WT" >/dev/null 2>&1 )
}

# launched_in — the directory the recorded `do script` string actually starts a session
# in: unescaped as AppleScript would, then run by a shell with `claude` stubbed.
launched_in() {
  local command
  command="$(python3 "$TMP/unescape.py" "$OSASCRIPT_OUT" 2>/dev/null)" || return 1
  ( PATH="$STUB_BIN:$PATH" bash -c "$command" 2>/dev/null )
}

echo "open-session"

for copy in "$SELF_COPY" "$TEMPLATE_COPY"; do
  label="$(basename "$(dirname "$copy")")/$(basename "$copy")"
  run_opener "$copy"; rc=$?
  check "O1. $label exits 0 with a path holding a space, ' , \" and \\ (got $rc)" \
    '[[ $rc -eq 0 ]]'
  check "O2. $label hands osascript a do script string" \
    'grep -q "do script" "$OSASCRIPT_OUT" 2>/dev/null'
  got="$(launched_in)"
  check "O3. $label reaches claude with the path intact (got ${got:-<nothing>})" \
    '[[ "$got" == "$WT" ]]'
  check "O4. $label is at template-version $EXPECTED_TEMPLATE_VERSION (got $(template_version "$copy"))" \
    '[[ "$(template_version "$copy")" == "$EXPECTED_TEMPLATE_VERSION" ]]'
done

# The two copies are hand-kept in step (self/README.md), so the command they compose has
# to be the same string — a divergence here is a consuming repo opening its sessions
# differently from this one.
run_opener "$SELF_COPY"
self_command="$(python3 "$TMP/unescape.py" "$OSASCRIPT_OUT" 2>/dev/null)"
run_opener "$TEMPLATE_COPY"
template_command="$(python3 "$TMP/unescape.py" "$OSASCRIPT_OUT" 2>/dev/null)"
check "O5. both copies compose the same command for Terminal" \
  '[[ -n "$self_command" && "$self_command" == "$template_command" ]]'

echo
if (( fails > 0 )); then echo "open-session: $fails assertion(s) FAILED"; exit 1; fi
echo "open-session: all assertions passed"
