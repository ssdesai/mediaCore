"""Measure the proposed grammar against (1) every table of commands in the hook's test files,
(2) the replay fixture, (3) the Bash commands of the session transcripts on this machine.

Usage: python3 -B measure.py <agentTooling root> <claude projects dir>
"""
import collections
import glob
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_lib import harvest, load_hook                              # noqa: E402
from simple_line import approval_eligible, simple_line, why_outside     # noqa: E402

AT, PROJECTS = sys.argv[1], sys.argv[2]
TEST_FILES = ["allow-repo-commands.sh", "hook-cloud-profile.sh", "hook-escalation.sh",
              "hook-orchestrator-role.sh"]
REPLAY_FIXTURE = "self/tests/fixtures/hook-replay-2026-09-18.json"
SHOWN_COMMAND_CHARS = 110


def report_tables():
    print("== 1. tables of the hook's test files ==")
    total = collections.Counter()
    for name in TEST_FILES:
        for table, commands in harvest(os.path.join(AT, "self", "tests", name)).items():
            ineligible = [c for c in commands if not approval_eligible(c)]
            total["rows"] += len(commands)
            total["outside"] += sum(1 for c in commands if simple_line(c) is None)
            if "ALLOW" in table and "NOT" not in table:
                total["allow rows"] += len(commands)
                total["allow rows losing approval"] += len(ineligible)
                print("  %-28s %-26s rows %3d  not approvable under the grammar %3d"
                      % (name, table, len(commands), len(ineligible)))
                for command in ineligible:
                    print("      %-34s %r" % (why_outside(command), command))
    for key in ("rows", "outside", "allow rows", "allow rows losing approval"):
        print("  total %-28s %d" % (key, total[key]))


def report_fixture():
    print("== 2. replay fixture (its own expected verdicts) ==")
    cross = collections.Counter()
    for record in json.load(open(os.path.join(AT, REPLAY_FIXTURE)))["records"]:
        command = record["command"]
        cross[(record["verdict"], "in grammar" if simple_line(command) is not None else "outside",
               "approvable" if approval_eligible(command) else "-")] += 1
        if record["verdict"] == "ALLOW" and not approval_eligible(command):
            print("      loses approval: %r (%s)" % (command, why_outside(command)))
    for key, count in sorted(cross.items()):
        print("  %-8s %-10s %-10s %d" % (key + (count,)))


def transcript_commands():
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        for line in open(path, errors="replace"):
            try:
                event = json.loads(line)
            except ValueError:
                continue
            message = event.get("message") if isinstance(event, dict) else None
            content = message.get("content") if isinstance(message, dict) else None
            for block in content if isinstance(content, list) else []:
                if isinstance(block, dict) and block.get("type") == "tool_use" \
                        and block.get("name") == "Bash":
                    command = (block.get("input") or {}).get("command")
                    if isinstance(command, str) and command.strip():
                        yield command, event.get("cwd") or AT


def today(hook, command, cwd):
    """Today's verdict from the hook's own functions, the shape denies first as main() has
    them (no orchestrator record, a readable ledger)."""
    os.environ["CLAUDE_PROJECT_DIR"] = AT
    for judge, label in ((lambda: hook.chains_chdir(command), "DENY cd"),
                         (lambda: hook.git_denial(command, cwd), "DENY git"),
                         (lambda: hook.uses_own_assignment(command), "DENY assign")):
        try:
            if judge():
                return label
        except Exception:
            pass
    root = hook.project_root()
    start = os.path.realpath(cwd) if hook.inside(cwd, root) else None
    return hook.command_verdict(command, start, root)[0]


def report_transcripts(hook):
    print("== 3. this machine's transcripts, today's hook run on each Bash command ==")
    commands = list(transcript_commands())
    cross, moved = collections.Counter(), []
    for command, cwd in commands:
        verdict = today(hook, command, cwd)
        cross[(verdict, "in grammar" if simple_line(command) is not None else "outside")] += 1
        if verdict == "ALLOW" and not approval_eligible(command):
            moved.append((why_outside(command), command))
    print("  commands: %d" % len(commands))
    for (verdict, where), count in sorted(cross.items()):
        print("  today %-12s %-10s %d" % (verdict, where, count))
    print("  approved today, not approvable under the grammar: %d" % len(moved))
    for why, command in moved:
        print("      %-34s %r" % (why, command[:SHOWN_COMMAND_CHARS]))
    outside = collections.Counter(why_outside(c) for c, _ in commands if simple_line(c) is None)
    for why, count in outside.most_common():
        print("  outside: %-36s %d" % (why, count))


report_tables()
report_fixture()
report_transcripts(load_hook(AT))
