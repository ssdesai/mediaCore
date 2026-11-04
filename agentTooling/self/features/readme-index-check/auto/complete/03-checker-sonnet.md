# 03 — build: `check-readme-index.py`

Feature: `readme-index-check` (agentTooling, `--self`) — plan 2 of 3 build plans. The
feature ships `check-readme-index.py`, a read-only checker that reports every tracked
file and direct subfolder its folder's `README.md` never names, wires it into
`self/gate.sh`, and documents opt-in adoption for consuming repos.

Create the checker at the agentTooling top level, to the contract `self/tests/readme-index.sh`
(plan 02) asserts.

Depends on: `02-tests-readme-index-sonnet.md` (read `self/tests/readme-index.sh` first —
its cases I1–I13 are the acceptance criteria; make every one pass).

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

## Pinned facts

- **Why Python, not bash:** the recognition rule is a lookaround regex and the ignore
  matcher is per-segment fnmatch; both are one line in Python and fragile in bash 3.2's
  `[[ =~ ]]` (no lookarounds). Stdlib only (`argparse`, `fnmatch`, `os`, `re`,
  `subprocess`, `sys`), Python 3.8-compatible, a single file importing no local module.
  It is always run as `python3 -B …`; a script run as `__main__` is never byte-compiled,
  so it leaves no `__pycache__` either way.
- Named constants at the top of the file, grouped with a label comment
  (`CONVENTIONS.md` → "Named constants"): exit codes, `README.md`, the 12-line generated
  header window, the regexes, the report prefix.
- No model name anywhere in the file.
- `agentTooling` may be vendored with no `.git` of its own: `git -C <root> ls-files -z`
  lists the files under `<root>` relative to it whether `<root>` is a repo's top level or a
  subdirectory, so never call `rev-parse --show-toplevel` and re-root.

## Files

- Create `check-readme-index.py` (the agentTooling top level, beside `check-plans.sh`)

## `check-readme-index.py`

`#!/usr/bin/env python3`. The **module docstring is the one statement of the rules** —
the root `README.md` and `CONVENTIONS.md` point at it rather than restating them — so it
carries, in this order: usage; what a checked folder and an entry are; the recognition
rule; the ignore-file format; the generated-README treatment; the output lines; exit
codes; and "writes nothing". Take each from the contract below, in prose.

### The contract

CLI (argparse; its own usage errors exit 2, which is the error code):
`check-readme-index.py [--root DIR] [--ignore FILE] [--report-only]`. `--root` defaults
to `.`; `--ignore` is resolved against the cwd, like any CLI path.

1. **Tracked files.** `git -C <root> ls-files -z`, keeping only paths that exist on disk
   (`os.path.lexists`). Before that, `git -C <root> rev-parse --is-inside-work-tree`; a
   missing `git` (`FileNotFoundError`), a non-zero exit, or `--root` not a directory is an
   error: `not a git checkout: <root>`.
2. **Folders and entries.** From the path list build, per folder (`""` is the root), the
   set of `(name, is_dir)` direct children: the file itself in its own folder, and each
   ancestor folder as a directory child of its parent. A folder is **checked** when
   `<folder>/README.md` (or `README.md` at the root) is in the list and the folder is not
   ignored. Its entries are its children minus the file `README.md`, minus ignored paths.
3. **Recognition** — paste:

```python
# Recognition: a name counts only between non-name characters (docstring, "Recognition")
NAME_BEFORE_GUARD = r"(?<![A-Za-z0-9_.\-])"
NAME_AFTER_GUARD = r"(?![A-Za-z0-9_\-])(?!\.[A-Za-z0-9_\-])"


def is_named(text, name):
    """True when `name` occurs in `text` as a whole name, case-sensitively."""
    return re.search(NAME_BEFORE_GUARD + re.escape(name) + NAME_AFTER_GUARD, text) is not None
```

   Docstring wording to carry: the name must appear verbatim and case-sensitively; the
   character before it may not be a letter, digit, `_`, `.` or `-`, and the character
   after it may not be a letter, digit, `_` or `-`, nor a `.` followed by one; so a path
   prefix (`self/gate.sh` names `gate.sh`), backticks, a trailing `/` and a sentence's
   full stop are all boundaries, while `integrate` does not name `gate` and
   `tool.py.bak` does not name `tool.py`. A subfolder is named by its bare name.
4. **Ignore file** — paste the matcher; write the loader in prose to the rules below:

```python
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
```

   Loader: read the file as UTF-8 (unreadable/missing → error
   `cannot read ignore file: <path>`); strip each line; skip empty lines and lines
   starting `#`; a trailing `/` sets `dir_only` and is removed; then a pattern starting
   with `/`, or any segment that is empty, `.` or `..`, is an error
   `bad ignore pattern on line <n>: <pattern>`. No `--ignore` → no patterns.
5. **Generated READMEs** — paste the constants:

```python
# Generated READMEs: a sync-written stub, checked with the repo-owned file it names
GENERATED_HEADER_LINES = 12
GENERATED_MARKER_RE = re.compile(r"^_Generated from ", re.MULTILINE)
OWNED_FILE_RE = re.compile(r"repo-owned\s+`([^`]+)`")
```

   Take the README's first `GENERATED_HEADER_LINES` lines; if `GENERATED_MARKER_RE`
   finds a match there it is generated. `OWNED_FILE_RE` searched in the same header gives
   the owned path, resolved against the README's folder and normalised to a root-relative
   POSIX path; read it if it is a file inside `<root>`, else use empty text. The folder's
   entries are checked against README text + `"\n"` + owned text. A generated README
   whose header names no owned file is checked against itself alone, as an ordinary one.
   Docstring wording: this is how a consuming repo's `plans/` stubs, overwritten on every
   pull, are held to `CONVENTIONS.md` → "Generated READMEs": the stub is never edited,
   the repo's own entries go in the file its header names, and the check reads both.
6. **Reading text:** UTF-8 with `errors="replace"`.
7. **Output.** Folders in sorted order of their path, entries in sorted order of name.
   One stdout line per missing entry: `<readme>: <entry>`, or for a generated README
   `<owned> (generated <readme>): <entry>`; paths root-relative with `/`, a folder entry
   with a trailing `/`. Then the last line, `N` = checked READMEs, `M` = missing entries,
   `R` = READMEs with at least one:
   `readme-index: <N> READMEs checked, none missing`, or
   `readme-index: <M> missing in <R> of <N> READMEs checked`, with ` (report only)`
   appended under `--report-only`.
8. **Exit codes:** 0 none missing; 1 any missing; 0 under `--report-only` whatever is
   missing; 2 on any error, printed to stderr as `readme-index: error: <detail>` (raise a
   small private exception class from the helpers and catch it once in `main`).
9. **Writes nothing.** No file, no git command that writes (only `rev-parse` and
   `ls-files`), no cache.

`main()` returns the exit code; the file ends `if __name__ == "__main__": sys.exit(main())`.
