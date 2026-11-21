"""Estimate the deny side under the design: exact on lines in the grammar, one plain reading
(today's lexer over the raw line, then over each physical line) outside it.

For every row of the deny-side tables: today's answer from the hook's own three shape denies
(local profile), and the answer with the many-readings machinery replaced by that fallback.

Usage: python3 -B deny_side.py <agentTooling root>, with the profile pinned to local in the
environment (README.md beside this file spells the variable; this file may not)
"""
import collections
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from measure_lib import harvest, load_hook     # noqa: E402
from simple_line import simple_line            # noqa: E402

AT = sys.argv[1]
CWD = "/fixture/repo"
TABLES = ["DENY", "NOT_DENIED", "CHAINED_NOT_APPROVED", "GIT_DENY", "GIT_PUSH_MAIN_DENY",
          "GIT_NOT_DENIED", "GIT_AUDIT_DENY", "UNLEXED_GIT_DENY", "BASH_REFUSED_GIT_DENY",
          "BASH_PARSED_QUOTE_DENY", "BASH_PARSED_PROMPT", "TORN_READING_DENY",
          "TORN_READING_NOT_DENIED", "ASSIGN_DENY", "ASSIGN_NOT_DENIED", "OPAQUE_NOT_DENIED",
          "UNREADABLE_NOT_DENIED", "ASK_CASES", "AUTHORING_NOT_DENIED"]


def shape_deny(hook, command):
    for judge, label in ((lambda: hook.chains_chdir(command), "cd"),
                         (lambda: hook.git_denial(command, CWD), "git"),
                         (lambda: hook.uses_own_assignment(command), "assign")):
        try:
            if judge():
                return label
        except Exception:
            pass
    return None


today_hook = load_hook(AT)
fallback_hook = load_hook(AT)


def fallback_texts(command, torn=None):
    if fallback_hook.chain_tokens(command) is not None:
        return [command]
    lines = [line for line in command.split("\n")
             if line.strip() and fallback_hook.chain_tokens(line) is not None]
    return lines or [command]


fallback_hook.judged_texts = fallback_texts
fallback_hook.judged_text = lambda command: fallback_texts(command)[0]
fallback_hook.never_judged = lambda text: False
fallback_hook.comment_and_heredoc_free = lambda command, **how: command

GIT_WORD = today_hook.GIT_WORD_RE
DROPPED = today_hook.GIT_WORD_DROPPED_CHARS

tables = harvest(os.path.join(AT, "self", "tests", "allow-repo-commands.sh"))
print("%-26s %5s | outside the grammar: %5s  today deny %5s  fallback deny %5s  lost %4s  "
      "gained %4s | names git %5s" % ("table", "rows", "rows", "", "", "", "", ""))
totals = collections.Counter()
examples = collections.defaultdict(list)
for table in TABLES:
    rows = tables.get(table, [])
    outside = [c for c in rows if simple_line(c) is None]
    today = {c: shape_deny(today_hook, c) for c in outside}
    after = {c: shape_deny(fallback_hook, c) for c in outside}
    lost = [c for c in outside if today[c] and not after[c]]
    gained = [c for c in outside if not today[c] and after[c]]
    git_named = [c for c in outside if GIT_WORD.search(c.translate(DROPPED))]
    git_not_denied_today = [c for c in git_named if not today[c]]
    print("%-26s %5d | %5d  %5d  %5d  %4d  %4d | %5d (not denied today %d)"
          % (table, len(rows), len(outside), sum(1 for c in outside if today[c]),
             sum(1 for c in outside if after[c]), len(lost), len(gained), len(git_named),
             len(git_not_denied_today)))
    for key, value in (("rows", len(rows)), ("outside", len(outside)), ("lost", len(lost)),
                       ("gained", len(gained)), ("git named", len(git_named)),
                       ("today deny", sum(1 for c in outside if today[c])),
                       ("git named not denied today", len(git_not_denied_today))):
        totals[key] += value
    examples["lost"].extend((table, c) for c in lost[:3])
    examples["gained"].extend((table, c) for c in gained[:3])
    examples["git prompt today"].extend((table, c) for c in git_not_denied_today[:3])
print(dict(totals))
for kind, found in examples.items():
    print("== %s (up to 3 per table) ==" % kind)
    for table, command in found:
        print("  %-24s %r" % (table, command[:120]))
