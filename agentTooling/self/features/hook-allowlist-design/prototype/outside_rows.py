"""List the rows of chosen tables that fall outside the grammar, with the shape that puts
each there.

Usage: python3 -B outside_rows.py <agentTooling root> <test file> <TABLE>...
"""
import collections
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_lib import harvest                    # noqa: E402
from simple_line import simple_line, why_outside   # noqa: E402

AT, TEST_FILE, WANTED = sys.argv[1], sys.argv[2], sys.argv[3:]
tables = harvest(os.path.join(AT, "self", "tests", TEST_FILE))
for table in WANTED:
    rows = [c for c in tables.get(table, []) if simple_line(c) is None]
    print("== %s: %d outside ==" % (table, len(rows)))
    for label, count in collections.Counter(why_outside(c) for c in rows).most_common():
        print("  %-40s %d" % (label, count))
    for command in rows[:40]:
        print("    %-36s %r" % (why_outside(command), command[:100]))
