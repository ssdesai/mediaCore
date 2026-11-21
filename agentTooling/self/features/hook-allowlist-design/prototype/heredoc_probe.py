"""The canonical heredoc word against bash: hostile bodies, each run with `p0` a logging
function. The reader's claim: one invocation, `p0 -m <body>`, and nothing else runs.

Usage: python3 -B heredoc_probe.py
"""
import os
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from simple_line import simple_line     # noqa: E402

BODIES = [
    "plain message",
    "it's \"quoted\" and `ticked` and $(p0 PWNED) and ${HOME} and \\",
    "x ) \" ; p0 PWNED ; echo \"(",
    "x )\" ; p0 PWNED ; echo \"$(cat <<'EOF'",
    ")\"\np0 PWNED\necho \"",
    " EOF\n)\" ; p0 PWNED ; echo \"",
    "# a comment\n\n\ttabbed\n",
    "EOF)\" ; p0 PWNED ; echo \"",          # begins with the delimiter: outside the grammar
    "EOFS\nmore",                              # likewise
]
SCRIPT = r"""
p0() { printf 'I'; for word in "$@"; do printf '\037%s' "$word"; done; printf '\036'; }
eval "$1"
"""
for body in BODIES:
    line = "p0 -m \"$(cat <<'EOF'\n" + body + "\nEOF\n)\" ; p0 after"
    read = simple_line(line)
    done = subprocess.run(["bash", "--norc", "--noprofile", "-c", SCRIPT, "probe", line],
                          capture_output=True, env={"PATH": "/usr/bin:/bin"})
    runs = [tuple(r.split("\x1f")[1:]) for r in done.stdout.decode().split("\x1e") if r]
    expected = [("-m", body.rstrip("\n")), ("after",)]     # `$(…)` drops trailing line breaks
    print("  grammar=%-5s bash ran exactly [p0 -m <body>, p0 after]=%-5s body=%r"
          % (read is not None, runs == expected, body[:44]))
    if read is not None and runs != expected:
        print("    MISMATCH: %r" % (runs,))
