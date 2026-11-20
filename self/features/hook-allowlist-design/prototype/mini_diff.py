"""A small differential of the prototype reader against bash itself.

Every string of up to EXHAUSTIVE_MAX tokens, and RANDOM_CASES longer ones, each prefixed
`p0 `, is (1) read by simple_line and (2) run by bash in an empty sandbox where `p0`, `a` and
`b` are logging shell functions. For a line the reader places in the grammar:
  - every invocation bash made must be one the reader read (same program, same words);
  - every file bash created must be a redirect target the reader read;
  - `bash -n` must accept the line.

Usage: python3 -B mini_diff.py <empty work dir>
"""
import collections
import itertools
import os
import random
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from simple_line import simple_line     # noqa: E402

WORK = os.path.realpath(sys.argv[1])
TOKENS = ["p0", "a", "b", " ", "\t", "'", '"', ";", "|", "&&", "||", "&", ">", ">>", "<",
          "2>&1", "#", "\\", "$", "*", "?", "=", "~", "^", "(", ")", "{", "}",
          "!", "\n", "if", "time", "1", "2", ",", "-"]
EXHAUSTIVE_MAX = 3
RANDOM_CASES = 40000
RANDOM_MIN, RANDOM_MAX = 4, 9
RANDOM_SEED = 20261119
PREFIX = "p0 "
FUNCTIONS = ["p0", "a", "b"]
DRIVER = r"""
LOG="$1"; CASES="$2"; SANDBOX="$3"
for name in %s; do
  eval "$name() { { printf 'I\037%%s' $name; for word in \"\$@\"; do printf '\037%%s' \"\$word\"; done; printf '\036'; } >>\"\$LOG\" 2>/dev/null; }"
done
mapfile -d '' -t lines < "$CASES"
cd "$SANDBOX" || exit 9
index=0
for line in "${lines[@]}"; do
  printf 'C\037%%s\036' "$index" >>"$LOG"
  ( PATH=/nonexistent; eval "$line"; wait ) </dev/null >/dev/null 2>&1
  for made in * .[!.]*; do
    if [ -e "$made" ] || [ -L "$made" ]; then
      printf 'F\037%%s\036' "$made" >>"$LOG"
      /bin/rm -rf -- "$made"
    fi
  done
  index=$((index + 1))
done
""" % " ".join(FUNCTIONS)


def corpus():
    cases = ["".join(combo) for n in range(1, EXHAUSTIVE_MAX + 1)
             for combo in itertools.product(TOKENS, repeat=n)]
    rng = random.Random(RANDOM_SEED)
    for _ in range(RANDOM_CASES):
        cases.append("".join(rng.choice(TOKENS)
                             for _ in range(rng.randint(RANDOM_MIN, RANDOM_MAX))))
    return [PREFIX + case for case in cases]


cases = corpus()
sandbox = os.path.join(WORK, "sandbox")
os.makedirs(sandbox)
log, case_file, driver = (os.path.join(WORK, name) for name in ("log", "cases", "driver.sh"))
with open(case_file, "wb") as handle:
    handle.write(b"\0".join(case.encode() for case in cases) + b"\0")
with open(driver, "w") as handle:
    handle.write(DRIVER)
subprocess.run(["bash", "--norc", "--noprofile", driver, log, case_file, sandbox],
               env={"PATH": "/usr/bin:/bin", "HOME": sandbox}, check=False)

ran = collections.defaultdict(list)
made = collections.defaultdict(list)
current = None
for record in open(log, "rb").read().split(b"\x1e"):
    if not record:
        continue
    fields = record.decode(errors="replace").split("\x1f")
    if fields[0] == "C":
        current = int(fields[1])
    elif fields[0] == "I":
        ran[current].append(tuple(fields[1:]))
    elif fields[0] == "F":
        made[current].append(fields[1])

in_grammar = wrong_run = wrong_file = refused = ran_something_outside = 0
shown = collections.Counter()
for index, case in enumerate(cases):
    commands = simple_line(case)
    if commands is None:
        if ran[index]:
            ran_something_outside += 1
        continue
    in_grammar += 1
    predicted = collections.Counter(tuple(command.words) for command in commands)
    actual = collections.Counter(ran[index])
    targets = set(target for command in commands for _op, target in command.redirects if target)
    bad_run = actual - predicted
    bad_file = [name for name in made[index] if name not in targets]
    syntax = subprocess.run(["bash", "--norc", "--noprofile", "-n"], input=case.encode(),
                            env={"PATH": "/usr/bin:/bin"}, capture_output=True)
    for kind, bad in (("run", bad_run), ("file", bad_file),
                      ("bash -n", syntax.returncode or syntax.stderr)):
        if bad:
            if shown[kind] < 8:
                print("  FAIL %-8s %r -> %r" % (kind, case, bad))
            shown[kind] += 1
    wrong_run += bool(bad_run)
    wrong_file += bool(bad_file)
    refused += bool(syntax.returncode or syntax.stderr)
print("cases %d; in the grammar %d; of those: bash ran an invocation the reader did not read "
      "%d, bash made a file the reader did not read %d, bash -n refused %d; outside the "
      "grammar and bash ran something: %d"
      % (len(cases), in_grammar, wrong_run, wrong_file, refused, ran_something_outside))
