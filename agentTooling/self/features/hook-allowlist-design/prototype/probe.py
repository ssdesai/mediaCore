"""Probes of today's hook for the design's factual claims, and per-table grammar counts.

Usage: python3 -B probe.py <agentTooling root> <empty scratch dir>
"""
import collections
import os
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_lib import harvest, load_hook     # noqa: E402
from simple_line import simple_line            # noqa: E402

AT, SCRATCH = sys.argv[1], os.path.realpath(sys.argv[2])
ROOT = os.path.join(SCRATCH, "repo")
os.makedirs(os.path.join(ROOT, "dir"))
os.makedirs(os.path.join(ROOT, "src"))
for name in ("README.md", "dir/inner.txt", "src/a.py"):
    open(os.path.join(ROOT, name), "w").close()
os.symlink("/etc/hostname", os.path.join(ROOT, "dir", "esc"))
os.makedirs(os.path.join(ROOT, "a >", "dev"))
os.symlink("/etc/hostname", os.path.join(ROOT, "a >/dev/null b"))
os.symlink("/etc/hostname", os.path.join(ROOT, "dir", "`x"))

hook = load_hook(AT)
PROBES = [
    "cat 'a >/dev/null b'",
    "cat 'a  b'",
    "cat dir/[^i]*",
    "cat dir/[!i]*",
    "cat \"dir/\\`x\"",
    "grep \"\\$x\" README.md",
    "ls &",
    "ls src &",
    "ls;",
    "ls src # list it",
    "cat =python3",
    "ls src\u00a0README.md",
    "grep -n \"it's\" README.md",
    "git log -1 --format=%H",
    "X=1 ls",
    "ls ; ; ls",
    "cat README.md > /dev/null",
    "cat dir/esc",
]
print("== today's approval (command_allowed), and what bash 5.2 reads ==")
for command in PROBES:
    try:
        allowed = hook.command_allowed(command, ROOT, ROOT)
    except Exception as error:
        allowed = "raised %s" % type(error).__name__
    ran = subprocess.run(["bash", "--norc", "--noprofile", "-c", command], cwd=ROOT,
                         capture_output=True, text=True)
    out = (ran.stdout.strip().splitlines() or [""])[0][:40]
    print("  %-34r approved=%-5s grammar=%-5s bash rc=%d out=%r"
          % (command, allowed, simple_line(command) is not None, ran.returncode, out))

print("== per-table: rows in / outside the grammar ==")
for name in ("allow-repo-commands.sh", "hook-cloud-profile.sh", "hook-escalation.sh",
             "hook-orchestrator-role.sh"):
    for table, commands in harvest(os.path.join(AT, "self", "tests", name)).items():
        inside = sum(1 for c in commands if simple_line(c) is not None)
        print("  %-26s %-30s in %4d  outside %4d" % (name, table, inside, len(commands) - inside))
