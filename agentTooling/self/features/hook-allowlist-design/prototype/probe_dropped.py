"""Today's approval for the shapes the grammar drops, one example each.

Usage: python3 -B probe_dropped.py <agentTooling root> <empty scratch dir>
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_lib import load_hook                  # noqa: E402
from simple_line import approval_eligible          # noqa: E402

AT, SCRATCH = sys.argv[1], os.path.realpath(sys.argv[2])
ROOT = os.path.join(SCRATCH, "repo")
os.makedirs(os.path.join(ROOT, "src"))
for name in ("README.md", "src/a.py"):
    open(os.path.join(ROOT, name), "w").close()
hook = load_hook(AT)
PROBES = [
    "ls src # list it", "cat src/a#b", "ls {src,README.md}", "cat [R]EADME.md",
    "grep -n \\# README.md", "grep -n \"a\\.b\" README.md", "grep -n \"\\$x\" README.md",
    "ls src &", "ls src;",
    "cat =python3", "ls src/**", "ls src/*.py", "ls -la src | head -3",
    "cat README.md 2>/dev/null", "git log -1 HEAD~1", "git show HEAD^",
    "cat <<EOF\nx\nEOF", "ls src\tREADME.md", "X=1 ls src",
]
for command in PROBES:
    try:
        allowed = hook.command_allowed(command, ROOT, ROOT)
    except Exception as error:
        allowed = "raised %s" % type(error).__name__
    print("  %-32r approved today=%-5s approvable under the grammar=%s"
          % (command, allowed, approval_eligible(command)))
