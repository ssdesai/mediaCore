"""Prototype of the simple-line grammar of self/DESIGN-2026-11-19-hook-allowlist.md §1.

simple_line(command) -> list of Command, or None when the line is outside the grammar.
Not the build and wired into nothing: the measuring instrument behind the design's figures
(README.md beside this file). The length cap of §1 is not modelled here.
"""
import re

BLANKS = " \t"
BARE_CHARS = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:@%+,=-")
GLOB_CHARS = frozenset("*?")
SUFFIX_CHARS = frozenset("~^")          # only after a letter, a digit or another of the two
DQ_REFUSED = frozenset("$`\0")          # unescaped, inside double quotes
DQ_ESCAPABLE = frozenset("$`\"\\")      # what a backslash escapes there; else it is a literal
SEPARATORS = ("&&", "||", ";", "|")
RESERVED = frozenset("if then else elif fi for while until do done case esac select function "
                     "time coproc in".split())
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC_HEAD_RE = re.compile(r"\"\$\(cat <<'([A-Za-z_][A-Za-z0-9_]*)'\n")
HEREDOC_TAIL_RE = re.compile(r"[ \t]*\)\"")
REDIRECT_HEAD_RE = re.compile(r"(2>&1)|(&>|[12]?>>|[12]?>|<)")
HARMLESS_TARGET = "/dev/null"


class Command(object):
    def __init__(self):
        self.env, self.words, self.redirects, self.heredoc = [], [], [], False


def heredoc_at(line, at):
    head = HEREDOC_HEAD_RE.match(line, at)
    if not head:
        return None
    delimiter, index = head.group(1), head.end()
    while True:
        end = line.find("\n", index)
        if end < 0:
            return None
        body_line = line[index:end]
        if body_line == delimiter:
            tail = HEREDOC_TAIL_RE.match(line, end + 1)
            return tail.end() if tail else None
        if body_line.startswith(delimiter) or "\0" in body_line:
            return None
        index = end + 1


def simple_line(line):
    commands, current, i, n = [], Command(), 0, len(line)
    word, raw_start, pending_redirect, globbed = None, 0, None, False

    def end_item():
        nonlocal word, pending_redirect, globbed
        if word is None:
            return True
        had_glob, globbed = globbed, False
        if had_glob and (pending_redirect is not None or not current.words):
            return False        # a program or a redirect target is a literal, never a pattern
        if pending_redirect is not None:
            current.redirects.append((pending_redirect, word))
            pending_redirect = None
        elif not current.words and ASSIGNMENT_RE.match(line[raw_start:i]) and \
                line[raw_start] not in "'\"":
            current.env.append(word)
        else:
            if not current.words and line[raw_start:i] in RESERVED:
                return False
            current.words.append(word)
        word = None
        return True

    def end_command():
        nonlocal current
        if pending_redirect is not None or not current.words:
            return False
        commands.append(current)
        current = Command()
        return True

    while i < n:
        ch = line[i]
        if ch in BLANKS:
            if not end_item():
                return None
            i += 1
            continue
        sep = next((s for s in SEPARATORS if line.startswith(s, i)), None)
        if sep:
            if not end_item() or not end_command():
                return None
            i += len(sep)
            continue
        if word is None:
            raw_start = i
            redirect = REDIRECT_HEAD_RE.match(line, i)
            if redirect and pending_redirect is None:
                if redirect.group(1):
                    after = redirect.end()
                    if after < n and line[after] not in BLANKS and \
                            not any(line.startswith(s, after) for s in SEPARATORS):
                        return None
                    current.redirects.append(("2>&1", None))
                    i = after
                    continue
                pending_redirect = redirect.group(2)
                i = redirect.end()
                while i < n and line[i] in BLANKS:
                    i += 1
                raw_start = i
                continue
            end = heredoc_at(line, i)
            if end is not None:
                if end < n and line[end] not in BLANKS and \
                        not any(line.startswith(s, end) for s in SEPARATORS):
                    return None
                if not current.words or pending_redirect is not None:
                    return None
                current.words.append("<heredoc>")
                current.heredoc = True
                i = end
                continue
        if ch == "'":
            close = line.find("'", i + 1)
            if close < 0 or "\0" in line[i:close]:
                return None
            word = (word or "") + line[i + 1:close]
            i = close + 1
            continue
        if ch == '"':
            # POSIX double quotes: a backslash escapes `$`, a backtick, `"` and itself, and
            # is a literal before anything else; a bare `$` or backtick is refused
            pieces, at = [], i + 1
            while True:
                inner = line[at:at + 1]
                if inner == "" or inner in DQ_REFUSED:
                    return None
                if inner == '"':
                    break
                if inner == "\\":
                    following = line[at + 1:at + 2]
                    if following == "" or following == "\n":
                        return None
                    if following in DQ_ESCAPABLE:
                        pieces.append(following)
                        at += 2
                        continue
                pieces.append(inner)
                at += 1
            word = (word or "") + "".join(pieces)
            i = at + 1
            continue
        if ch in BARE_CHARS:
            if ch == "=" and word is None:
                return None
        elif ch in GLOB_CHARS:
            if ch == "*" and line[i - 1:i] == "*":
                return None
            globbed = True
        elif ch in SUFFIX_CHARS:
            previous = line[i - 1:i]
            if word is None or not (previous.isascii() and previous.isalnum()
                                    or previous in SUFFIX_CHARS):
                return None
        else:
            return None
        word = (word or "") + ch
        i += 1
    if not end_item() or not end_command():
        return None
    return commands


def approval_eligible(line):
    """The reader's half of ALLOW: in the grammar, one physical line, no heredoc word, no
    environment prefix, no redirect but the harmless ones, no `..`."""
    if "\n" in line or "\r" in line or ".." in line:
        return False
    commands = simple_line(line)
    if not commands:
        return False
    for command in commands:
        if command.heredoc or command.env:
            return False
        for operator, target in command.redirects:
            if operator != "2>&1" and (target != HARMLESS_TARGET or operator == "<"):
                return False
    return True


def why_outside(line):
    """A coarse label for a line outside the grammar: the first shape that puts it there."""
    if simple_line(line) is not None:
        return "in grammar"
    stripped = re.sub(r"'[^']*'", "''", line)
    checks = (
        ("heredoc (not the canonical word)", "<<" in stripped),
        ("$( or backtick", "$(" in stripped or "`" in stripped),
        ("$NAME / ${…} / $'…'", "$" in stripped),
        ("backslash outside single quotes", "\\" in stripped),
        ("line break outside quotes", "\n" in re.sub(r"\"[^\"]*\"", '""', stripped)),
        ("unquoted # (comment)", "#" in re.sub(r"\"[^\"]*\"", '""', stripped)),
        ("brace", "{" in stripped or "}" in stripped),
        ("bracket glob / [ ]", "[" in stripped or "]" in stripped),
        ("subshell or group ( )", "(" in stripped or ")" in stripped),
        ("background or other &", "&" in stripped.replace("&&", "").replace("2>&1", "")
         .replace("&>", "")),
        ("tilde at a word start", bool(re.search(r"(^|[\s=:])~", stripped))),
        ("redirect glued to a word or another form", ">" in stripped or "<" in stripped),
        ("trailing or doubled separator", bool(re.search(r"[;|&]\s*$|;;|\|&", stripped))),
        ("! or other character", True),
    )
    return next(label for label, hit in checks if hit)
