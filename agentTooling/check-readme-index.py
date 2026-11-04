#!/usr/bin/env python3
"""check-readme-index.py - report what a folder's README.md never names.

Usage:
    python3 -B check-readme-index.py [--root DIR] [--ignore FILE] [--report-only]

    --root DIR       the git checkout to check (default: the current directory).
    --ignore FILE    an ignore file (format below), resolved against the cwd.
    --report-only    print the report but exit 0 whatever is missing.

This docstring is the one statement of the rules; the root README.md and
CONVENTIONS.md point here rather than restating them.

Checked folders and entries
    The files checked are the ones `git ls-files` lists under --root that still
    exist on disk. A folder is *checked* when it holds a tracked README.md (the
    root included) and is not ignored. Its *entries* are its direct children -
    the tracked files in it and each direct subfolder that holds a tracked file
    somewhere below - except its own README.md and any ignored path. A file is
    held to its own folder's README only, never an ancestor's.

Recognition
    An entry is named when its bare name (a subfolder by its name, no slash)
    appears verbatim and case-sensitively in the README text. The character
    before the name may not be a letter, digit, "_", "." or "-"; the character
    after it may not be a letter, digit, "_" or "-", nor a "." followed by one.
    So a path prefix (`self/gate.sh` names `gate.sh`), backticks, a trailing "/"
    and a sentence's full stop are all boundaries, while `integrate` does not
    name `gate` and `tool.py.bak` does not name `tool.py`.

Ignore file
    UTF-8, one pattern per line. Lines are stripped; empty lines and lines
    starting with "#" are skipped. A trailing "/" makes a pattern match folders
    only (and is removed). A pattern is "/"-separated segments, each an
    fnmatch glob, matched against the first segments of a root-relative path,
    so it also covers everything below a matching folder. A pattern starting
    with "/" or with an empty, "." or ".." segment is an error. An ignored
    folder is not checked, and an ignored path is never an entry.

Generated READMEs
    A README whose first 12 lines carry a line starting "_Generated from " is a
    sync-written stub, overwritten on every pull. This is how a consuming repo's
    plans/ stubs are held to CONVENTIONS.md -> "Generated READMEs": the stub is
    never edited, the repo's own entries go in the repo-owned file its header
    names (`repo-owned `<path>``, resolved against the README's folder), and the
    check reads both. A missing or out-of-tree owned file counts as empty. A
    generated README whose header names no owned file is checked as an ordinary
    one.

Output (stdout)
    One line per missing entry, folders in path order, entries in name order:
        <readme>: <entry>
    or, for a generated README:
        <owned> (generated <readme>): <entry>
    Paths are root-relative with "/", a folder entry with a trailing "/". The
    last line is
        readme-index: <N> READMEs checked, none missing
    or
        readme-index: <M> missing in <R> of <N> READMEs checked
    with " (report only)" appended under --report-only.

Exit codes
    0 nothing missing (or --report-only); 1 something missing; 2 an error,
    printed to stderr as "readme-index: error: <detail>". A usage error (an
    unknown flag, a flag missing its value) also exits 2, with argparse's own
    "usage:" and "check-readme-index.py: error:" lines.

Writes nothing: no file, no cache, and of git only `rev-parse` and `ls-files`.
"""

import argparse
import fnmatch
import os
import posixpath
import re
import subprocess
import sys

# Exit codes
EXIT_CLEAN = 0
EXIT_MISSING = 1
EXIT_ERROR = 2

# Files and report text
README_NAME = "README.md"
REPORT_PREFIX = "readme-index: "
ERROR_PREFIX = REPORT_PREFIX + "error: "
REPORT_ONLY_SUFFIX = " (report only)"
IGNORE_COMMENT = "#"

# Recognition: a name counts only between non-name characters (docstring, "Recognition")
NAME_BEFORE_GUARD = r"(?<![A-Za-z0-9_.\-])"
NAME_AFTER_GUARD = r"(?![A-Za-z0-9_\-])(?!\.[A-Za-z0-9_\-])"

# Generated READMEs: a sync-written stub, checked with the repo-owned file it names
GENERATED_HEADER_LINES = 12
GENERATED_MARKER_RE = re.compile(r"^_Generated from ", re.MULTILINE)
OWNED_FILE_RE = re.compile(r"repo-owned\s+`([^`]+)`")

# Text decoding
TEXT_ENCODING = "utf-8"
TEXT_ERRORS = "replace"


class CheckError(Exception):
    """A reportable failure; main() prints it and exits EXIT_ERROR."""


def is_named(text, name):
    """True when `name` occurs in `text` as a whole name, case-sensitively."""
    return re.search(NAME_BEFORE_GUARD + re.escape(name) + NAME_AFTER_GUARD, text) is not None


def is_ignored(path, is_dir, patterns):
    """True when a pattern matches `path` or one of its ancestor folders.

    `patterns` holds (segments, dir_only) pairs. A pattern of n segments matches the
    first n segments of `path`, each by fnmatch.fnmatchcase; a dir_only pattern matches
    only when those n segments name a folder.
    """
    parts = path.split("/")
    for segments, dir_only in patterns:
        n = len(segments)
        if n > len(parts):
            continue
        prefix_is_dir = n < len(parts) or is_dir
        if dir_only and not prefix_is_dir:
            continue
        if all(fnmatch.fnmatchcase(p, s) for p, s in zip(parts[:n], segments)):
            return True
    return False


def load_ignore(path):
    """Parse the ignore file into (segments, dir_only) pairs; no path -> no patterns."""
    if path is None:
        return []
    try:
        with open(path, encoding=TEXT_ENCODING) as handle:
            lines = handle.read().splitlines()
    except (OSError, UnicodeDecodeError):
        raise CheckError("cannot read ignore file: " + path)
    patterns = []
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith(IGNORE_COMMENT):
            continue
        dir_only = line.endswith("/")
        if dir_only:
            line = line[:-1]
        segments = line.split("/")
        if line.startswith("/") or any(s in ("", ".", "..") for s in segments):
            raise CheckError("bad ignore pattern on line %d: %s" % (number, raw.strip()))
        patterns.append((segments, dir_only))
    return patterns


def tracked_paths(root):
    """Root-relative POSIX paths git tracks under `root` that still exist on disk."""
    if not os.path.isdir(root):
        raise CheckError("not a git checkout: " + root)
    try:
        probe = subprocess.run(
            ["git", "-C", root, "rev-parse", "--is-inside-work-tree"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if probe.returncode != 0:
            raise CheckError("not a git checkout: " + root)
        listing = subprocess.run(
            ["git", "-C", root, "ls-files", "-z"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise CheckError("not a git checkout: " + root)
    if listing.returncode != 0:
        raise CheckError("not a git checkout: " + root)
    paths = []
    for raw in listing.stdout.split(b"\0"):
        if not raw:
            continue
        rel = os.fsdecode(raw)
        if os.path.lexists(os.path.join(root, rel)):
            paths.append(rel)
    return paths


def build_children(paths):
    """Map folder ('' is the root) -> set of (name, is_dir) direct children."""
    children = {}
    for path in paths:
        parts = path.split("/")
        for depth in range(len(parts)):
            folder = "/".join(parts[:depth])
            is_dir = depth < len(parts) - 1
            children.setdefault(folder, set()).add((parts[depth], is_dir))
    return children


def read_text(root, rel):
    try:
        with open(os.path.join(root, rel), encoding=TEXT_ENCODING, errors=TEXT_ERRORS) as handle:
            return handle.read()
    except OSError:
        return ""


def owned_path_and_text(root, folder, readme_text):
    """For a generated README: (root-relative owned path, its text); else (None, '')."""
    header = "\n".join(readme_text.splitlines()[:GENERATED_HEADER_LINES])
    if not GENERATED_MARKER_RE.search(header):
        return None, ""
    found = OWNED_FILE_RE.search(header)
    if not found:
        return None, ""
    owned = posixpath.normpath(posixpath.join(folder, found.group(1)))
    inside = not (owned == ".." or owned.startswith("../") or owned.startswith("/"))
    text = ""
    if inside and os.path.isfile(os.path.join(root, owned)):
        text = read_text(root, owned)
    return owned, text


def check(root, patterns):
    """Return (checked READMEs, list of (label, entry) missing lines in report order)."""
    paths = tracked_paths(root)
    tracked = set(paths)
    children = build_children(paths)
    checked = 0
    missing = []
    readmes_with_missing = 0
    for folder in sorted(children):
        readme = posixpath.join(folder, README_NAME) if folder else README_NAME
        if readme not in tracked or (folder and is_ignored(folder, True, patterns)):
            continue
        checked += 1
        text = read_text(root, readme)
        label = readme
        owned, owned_text = owned_path_and_text(root, folder, text)
        if owned is not None:
            text = text + "\n" + owned_text
            label = "%s (generated %s)" % (owned, readme)
        found_any = False
        for name, is_dir in sorted(children[folder]):
            if name == README_NAME and not is_dir:
                continue
            full = posixpath.join(folder, name) if folder else name
            if is_ignored(full, is_dir, patterns):
                continue
            if not is_named(text, name):
                missing.append("%s: %s%s" % (label, full, "/" if is_dir else ""))
                found_any = True
        if found_any:
            readmes_with_missing += 1
    return checked, missing, readmes_with_missing


def main():
    parser = argparse.ArgumentParser(
        prog="check-readme-index.py",
        description="Report tracked files and subfolders their folder's README.md never names.")
    parser.add_argument("--root", default=".", help="the git checkout to check")
    parser.add_argument("--ignore", default=None, help="ignore file")
    parser.add_argument("--report-only", action="store_true", help="always exit 0")
    args = parser.parse_args()
    try:
        patterns = load_ignore(args.ignore)
        checked, missing, with_missing = check(args.root, patterns)
    except CheckError as err:
        print(ERROR_PREFIX + str(err), file=sys.stderr)
        return EXIT_ERROR
    for line in missing:
        print(line)
    if missing:
        summary = "%s%d missing in %d of %d READMEs checked" % (
            REPORT_PREFIX, len(missing), with_missing, checked)
    else:
        summary = "%s%d READMEs checked, none missing" % (REPORT_PREFIX, checked)
    if args.report_only:
        summary += REPORT_ONLY_SUFFIX
    print(summary)
    if missing and not args.report_only:
        return EXIT_MISSING
    return EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
