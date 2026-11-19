#!/usr/bin/env python3
"""The delegate brief header, written once.

Every Agent/subagent brief begins with a first line naming the feature its cost belongs to
(`CONVENTIONS.md` → "Delegate briefs"; the format is specified in `analysis/README.md` →
"The brief header"). Cost attribution claims a delegate by that line: a coordinator launched
outside the feature's checkout records its delegates on a branch no feature selects, so the
line is the only thing in the transcript that says which feature spent the money.

The first non-empty line of the prompt, its surrounding whitespace stripped, is exactly one
of:

    feature: <repo>/<slug>       the feature this delegate's cost belongs to
    feature: none — <reason>     work that belongs to no feature (read-only analysis, ...)

`<repo>` and `<slug>` are each one or more of `[A-Za-z0-9_.-]`, joined by one `/`, with
nothing after the slug. In the `none` form the separator is an em dash, an en dash, `-` or
`--`, and the reason is any non-empty text. Anything else on the first line — a missing
slash, a trailing remark after the slug, the line further down the prompt — is not a header.

Two readers ask the same question and must never answer it differently, so the rule lives
here and nowhere else:

  * `allow-repo-commands.sh` — the PreToolUse hook, which sends an `Agent` call whose prompt
    carries no header back, naming `REQUIRED_FEATURE_HEADER` and `REQUIRED_NONE_HEADER`;
  * `analysis/capture_planning.py` — `brief_feature_of`, which the unclaimed listing's
    "brief names" column, the pinned-brief check and the capture's auto-claim all read.

Stdlib only, so the hook imports it as a sibling and `analysis/` reaches it by path.
"""

import re
import sys

sys.dont_write_bytecode = True

# The word every header opens with.
HEADER_PREFIX = "feature:"
# A header naming a feature. The two halves are the `(repo, slug)` pair the claims ledger and
# the unclaimed listing compare (repo case-insensitively, slug exactly).
FEATURE_HEADER_RE = re.compile(r"^feature:[ \t]*([\w.-]+)/([\w.-]+)$")
# A header naming no feature, with the reason why.
NONE_HEADER_RE = re.compile(r"^feature:[ \t]*none[ \t]+(?:—|–|--|-)[ \t]*(\S.*)$")
# What a sent-back brief is told to put first — both forms, spelled as a human types them.
REQUIRED_FEATURE_HEADER = "feature: <repo>/<slug>"
REQUIRED_NONE_HEADER = "feature: none — <reason>"
# The two kinds of header `parse` returns.
KIND_FEATURE = "feature"
KIND_NONE = "none"


def first_line(text):
    """The first non-empty line of `text`, stripped; "" when there is none."""
    if not isinstance(text, str):
        return ""
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


def parse(text):
    """The header on the first non-empty line of `text`: `("feature", repo, slug)`,
    `("none", reason)`, or None when that line is not a header."""
    line = first_line(text)
    match = FEATURE_HEADER_RE.match(line)
    if match:
        return (KIND_FEATURE, match.group(1), match.group(2))
    match = NONE_HEADER_RE.match(line)
    if match:
        return (KIND_NONE, match.group(1).strip())
    return None


def feature_of(text):
    """`(repo, slug)` when the first non-empty line is a `feature: <repo>/<slug>` header,
    else None — a `none` header names no feature."""
    header = parse(text)
    if header and header[0] == KIND_FEATURE:
        return (header[1], header[2])
    return None


def feature_lines(text):
    """Every `(repo, slug)` named by a line of `text` that is, stripped, a feature header —
    the opening one and any further down. More than one distinct pair is a brief that names
    two features, which no reader may resolve by guessing."""
    if not isinstance(text, str):
        return []
    found = []
    for line in text.splitlines():
        match = FEATURE_HEADER_RE.match(line.strip())
        if match:
            found.append((match.group(1), match.group(2)))
    return found
