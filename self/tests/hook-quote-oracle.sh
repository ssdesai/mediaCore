#!/usr/bin/env bash
set -uo pipefail

# Self-test for `never_judged` in hooks/allow-repo-commands.sh, the guard every deny and
# rewrite keeps (hooks/README.md → "The chained `cd`"), with the shells themselves as the
# oracle. Run by self/gate.sh, or by hand: bash self/tests/hook-quote-oracle.sh
#
# The guard is a hand-written model of shell quoting, and three review rounds of
# `hook-hash-chained-cd` each found it wrong by reasoning about bash: `$'\''` read as a
# plain quote, `$$'…'` read as an ANSI-C one, and — which no round found — zsh reading
# `$$'…'` the other way from bash. A model of the shell is checked against the shell.
#
# Every string of up to EXHAUSTIVE_MAX_LEN characters from `' " \ $ # space a`, and
# RANDOM_CASES longer ones from a fixed seed, is put to each installed shell twice:
#
#   as written   `: F ; echo OK` — no OK and status 0 means the shell read a COMMENT;
#   spaced out   the same with every `#` written ` # `, which turns each `#` the shell
#                reads unquoted and unescaped into a comment and leaves a quoted one a
#                literal, so it answers "is any `#` in F outside quotes".
#
# Asserts, per shell (bash always; zsh when installed — Claude Code runs the Bash tool in
# the user's own shell, and on macOS that is zsh by default):
#   1. the guard lets through no line the shell reads a comment in;
#   2. nor one the shell reads an unquoted `#` in;
#   3. nor one the shell cannot parse that carries a `#`;
#   4. and what it lets through and shlex refuses to split, the shell refuses too — the
#      "does not tokenize" deny tells the model to close a quote, which must be open.
# And across the shells:
#   5. the guard holds a line back only for a reason: some shell reads an unquoted `#`
#      or cannot parse a line carrying one, or a `$'…'` escapes a quote. Without this a
#      guard that held everything back would pass 1–4.
#
# No model, no network. The shells run `:` and `echo` and nothing else: the alphabet has
# no separator, no redirect and no substitution.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "hook-quote-oracle"
python3 - "$AT/hooks/allow-repo-commands.sh" "$TMP" <<'PY'
import importlib.machinery
import importlib.util
import itertools
import os
import random
import re
import shlex
import shutil
import subprocess
import sys

HOOK, TMP = sys.argv[1], sys.argv[2]
sys.dont_write_bytecode = True

# The corpus
ALPHABET = ["'", '"', "\\", "$", "#", " ", "a"]
EXHAUSTIVE_MAX_LEN = 5
RANDOM_CASES = 20000
RANDOM_MIN_LEN, RANDOM_MAX_LEN = 6, 14
RANDOM_SEED = 20261001
# Weighted towards the characters whose interplay is the subject
RANDOM_WEIGHTED = ["'"] * 4 + ['"'] * 2 + ["\\"] * 3 + ["$"] * 4 + ["#"] * 3 + [" "] * 2 + ["a"]

# The oracle
REQUIRED_SHELL = "bash"
OPTIONAL_SHELLS = ["zsh"]
COMMENT_CHAR = "#"
SPACED_COMMENT_CHAR = " # "
ESCAPE = "\\"
MARK_RAN = "OK"
STATUS_PREFIX = "rc="
RAN, COMMENT, ERROR = "ran", "comment", "error"
DRIVER = """while IFS= read -r line; do
  eval ": $line ; echo %s" 2>/dev/null
  echo "%s$?"
done < "$1"
""" % (MARK_RAN, STATUS_PREFIX)
# A `$'…'` whose body ends in a backslash at its first quote: the guard's second reason
DOLLAR_QUOTE_ESCAPE_RE = re.compile(r"\$'[^']*\\'")
MAX_SHOWN = 5


def load_hook():
    spec = importlib.util.spec_from_loader(
        "allow_repo_commands", importlib.machinery.SourceFileLoader(
            "allow_repo_commands", HOOK))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hook = load_hook()


def corpus():
    cases = ["".join(combo) for n in range(1, EXHAUSTIVE_MAX_LEN + 1)
             for combo in itertools.product(ALPHABET, repeat=n)]
    rng = random.Random(RANDOM_SEED)
    for _ in range(RANDOM_CASES):
        length = rng.randint(RANDOM_MIN_LEN, RANDOM_MAX_LEN)
        cases.append("".join(rng.choice(RANDOM_WEIGHTED) for _ in range(length)))
    return cases


def shell_reading(shell, lines, tag):
    """RAN, COMMENT or ERROR for each line, as the shell itself read it."""
    driver, path = os.path.join(TMP, "driver.sh"), os.path.join(TMP, tag)
    with open(driver, "w") as fh:
        fh.write(DRIVER)
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    out = subprocess.run([shell, driver, path], capture_output=True, text=True).stdout
    readings, ran = [], False
    for row in out.splitlines():
        if row == MARK_RAN:
            ran = True
        elif row.startswith(STATUS_PREFIX):
            status = int(row[len(STATUS_PREFIX):])
            readings.append(RAN if ran else COMMENT if status == 0 else ERROR)
            ran = False
    if len(readings) != len(lines):
        raise SystemExit("%s answered %d of %d cases" % (shell, len(readings), len(lines)))
    return readings


def shlex_refuses(text):
    """True when the lexer every deny reads with cannot split the line."""
    lexer = shlex.shlex(text, posix=True, punctuation_chars=hook.CHAIN_PUNCTUATION)
    lexer.whitespace = hook.CHAIN_WHITESPACE
    lexer.whitespace_split = True
    lexer.commenters = hook.SHLEX_NO_COMMENTERS
    try:
        list(lexer)
    except ValueError:
        return True
    return False


def ends_escaping(text):
    """A trailing backslash escapes the oracle's own ` ; echo`: not a case for shlex."""
    return (len(text) - len(text.rstrip(ESCAPE))) % 2 == 1


fails = 0


def check(name, wrong, total):
    global fails
    for case in wrong[:MAX_SHOWN]:
        print("  FAIL  %s: %r" % (name, case))
    if wrong:
        print("  FAIL  %s: %d of %d cases" % (name, len(wrong), total))
    else:
        print("  ok    %s (%d cases)" % (name, total))
    fails += len(wrong)


cases = corpus()
spaced = [c.replace(COMMENT_CHAR, SPACED_COMMENT_CHAR) for c in cases]
held = [hook.never_judged(c) for c in cases]
refused = [shlex_refuses(c) and not ends_escaping(c) for c in cases]
reasoned = [bool(DOLLAR_QUOTE_ESCAPE_RE.search(c)) for c in cases]

shells = [shutil.which(REQUIRED_SHELL)]
for name in OPTIONAL_SHELLS:
    if shutil.which(name):
        shells.append(shutil.which(name))
    else:
        print("  skip  %s (not installed)" % name)

for shell in shells:
    name = os.path.basename(shell)
    written = shell_reading(shell, cases, name + "-written")
    apart = shell_reading(shell, spaced, name + "-spaced")
    rows = list(zip(cases, held, written, apart, refused))
    check("%s: no line with a comment is let through" % name,
          [c for c, h, w, _a, _r in rows if w == COMMENT and not h], len(cases))
    check("%s: no line with an unquoted # is let through" % name,
          [c for c, h, _w, a, _r in rows if a == COMMENT and not h], len(cases))
    check("%s: no unparseable line carrying a # is let through" % name,
          [c for c, h, _w, a, _r in rows if a == ERROR and COMMENT_CHAR in c and not h],
          len(cases))
    check("%s: what shlex refuses of the lines let through, the shell refuses" % name,
          [c for c, h, w, _a, r in rows if r and not h and w == RAN], len(cases))
    for index, (c, _h, _w, a, _r) in enumerate(rows):
        if a == COMMENT or (a == ERROR and COMMENT_CHAR in c):
            reasoned[index] = True

check("a line is held back only for an unquoted #, an open quote with a #, or a $'…' "
      "escaping a quote",
      [c for c, h, why in zip(cases, held, reasoned) if h and not why], len(cases))
sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-quote-oracle: all checks passed"; else echo "hook-quote-oracle: FAILED"; fi
exit "$rc"
