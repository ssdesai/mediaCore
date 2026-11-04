# 02 — tests: the README-index checker, black-box

Feature: `readme-index-check` (agentTooling, `--self`) — plan 1 of 3 build plans. The
feature ships `check-readme-index.py`, a read-only checker that reports every tracked
file and direct subfolder its folder's `README.md` never names, wires it into
`self/gate.sh`, and documents opt-in adoption for consuming repos.

Write `self/tests/readme-index.sh`, the behavioural test of the checker's contract below,
register it in `self/gate.sh`, and list it in `self/tests/README.md`. It is RED until plan
03 creates the checker; that is expected.

Independent of other plans (plan 03 builds what this asserts).

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

## Pinned facts

- bash 3.2: no associative arrays, no `${var^^}`; `set -uo pipefail`, deliberately no
  `set -e`; use `if …; then …; fi` rather than `cond && cmd` where the status matters.
- `mktemp -d` always takes an explicit template under `$TMPDIR`:
  `TMP="$(mktemp -d "${TMPDIR:-/tmp}/readme-index.XXXXXX")"`, then
  `trap 'rm -rf "$TMP"' EXIT`.
- Helper style to mirror: `self/tests/model-suffix.sh:25` (`HERE=…/../..`) and `:42-44`
  (`fails=0`, `ok()`, `fail()`), ending with `<name>: all checks passed` / exit non-zero
  on any FAIL, as `:109` does.
- Offline, no model, no network. Never touch the real checkout: copy the checker into the
  sandbox (`cp "$HERE/check-readme-index.py" "$TMP/bin/"`) and run that copy as
  `python3 -B "$TMP/bin/check-readme-index.py" …`. If the source file is missing, every
  case FAILs loudly (no abort) — the convention `cost-recovery.sh` uses.
- Fixture repos: `git init -q <dir>`, files written with `printf` / `cat` into the
  sandbox (that is the test script's own doing, not a tool call), then
  `git -C <dir> add -A`. Staging is enough — the checker reads `git ls-files`, which lists
  the index; no commit, no identity needed.
- For the not-a-checkout case, run with `GIT_CEILING_DIRECTORIES="$TMP"` so git cannot
  find an enclosing repo above the sandbox.
- No model name may appear anywhere in the file or the README entry.

## The checker's contract (what the cases assert)

CLI: `check-readme-index.py [--root DIR] [--ignore FILE] [--report-only]`; `--root`
defaults to `.`; `--ignore` is resolved against the cwd.

- **Folders checked:** every folder (the root included) whose `README.md` is a tracked
  file present on disk. Folders without one are not checked.
- **Entries:** a checked folder's direct tracked files (present on disk; `README.md`
  itself excluded) and its direct subfolders (any folder holding a tracked file somewhere
  below it). Untracked, ignored and deleted-but-tracked files are never entries.
- **Recognition:** an entry is named when its name occurs in the README text verbatim,
  **case-sensitive**, with the character before it (if any) not a letter, digit, `_`,
  `.` or `-`, and the character after it (if any) neither a letter, digit, `_` or `-`
  nor a `.` followed by one of those. So `tools/run.sh.` names `run.sh` (a path prefix
  and a sentence-ending period are boundaries); `integrate`/`gates` do not name `gate`;
  `tool.py.bak` does not name `tool.py`; `Notes.md` does not name `notes.md`.
- **Ignore file:** one pattern per line; blank lines and lines starting `#` skipped;
  anchored at the root, matched one `/`-separated segment at a time with fnmatch; a
  trailing `/` matches folders only. A pattern matching a path or any of its ancestors
  ignores it: not reported, and an ignored folder's README is not checked. A pattern
  starting with `/`, or with an empty, `.` or `..` segment, is an error.
- **Generated READMEs:** a README with a line starting `_Generated from ` among its first
  12 lines is generated. If those lines name ``repo-owned `<path>` `` (whitespace between
  the two allowed), the folder is checked against the README's text plus that file's
  (resolved against the README's folder; absent → empty).
- **Output (stdout), sorted by folder then entry name:** one line per missing entry —
  `<readme>: <entry>` for an ordinary README, `<owned> (generated <readme>): <entry>` for
  a generated one — paths root-relative, a folder entry ending in `/`. Last line:
  `readme-index: <N> READMEs checked, none missing`, or
  `readme-index: <M> missing in <R> of <N> READMEs checked`, plus ` (report only)` under
  `--report-only`.
- **Exit codes:** 0 none missing; 1 any missing; `--report-only` → 0 with missing
  entries; 2 on any error (not a git checkout, ignore file unreadable, bad pattern, bad
  argument), with `readme-index: error: <detail>` on stderr.
- **Read-only:** writes nothing — no file, no index change, no `__pycache__`.

## Files

- Create `self/tests/readme-index.sh`
- Modify `self/gate.sh`
- Modify `self/tests/README.md`

## `self/tests/readme-index.sh`

Header comment: what it tests, how to run it by hand (`bash self/tests/readme-index.sh`),
"no model, no network". Then `HERE`, `TMP`, `CHECKER="$TMP/bin/check-readme-index.py"`,
the helpers, and a `run_check <root> [args…]` helper that sets `OUT` (stdout and stderr
together) and `RC`. Add `has_line <text>` (`printf '%s\n' "$OUT" | grep -qxF -- "$1"`)
and `lacks <text>` (no line *containing* it, `grep -qF`). One builder function per fixture
repo; each case is labelled `I1`…`I13` in its ok/fail text.

- **I1 clean** — root `README.md` names `` `a.sh` `` and `` `sub/` ``; `sub/README.md`
  names `` `b.txt` ``; files `a.sh`, `sub/b.txt`. RC 0 and the line
  `readme-index: 2 READMEs checked, none missing`.
- **I2 unlisted file** — I1 plus a staged `c.sh`: RC 1, line `README.md: c.sh`, and a last
  line starting `readme-index: 1 missing in 1 of 2 READMEs checked`.
- **I3 unlisted subfolder** — I1 plus `newdir/x.txt` (no README there): line
  `README.md: newdir/`, and nothing mentioning `newdir/x.txt`.
- **I4 depth** — I1 plus `sub/c2.txt`: line `sub/README.md: sub/c2.txt`; no line
  `README.md: sub/c2.txt`.
- **I5 tracked only** — I1 plus an unstaged `untracked.sh`, a `.gitignore` holding
  `ignored.log` (root README names `` `.gitignore` ``), and an `ignored.log` file; also a
  staged `gone.sh` then deleted from disk. RC 0; nothing mentions `untracked.sh`,
  `ignored.log` or `gone.sh`.
- **I6 boundaries and case** — files `gate`, `run.sh`, `tool.py`, `notes.md`; root README
  text exactly: `Integrate the gates. See tools/run.sh. Old copy: tool.py.bak. Also Notes.md.`
  Lines `README.md: gate`, `README.md: tool.py`, `README.md: notes.md`; no line
  `README.md: run.sh`.
- **I7 report-only** — the I2 repo with `--report-only`: RC 0, line `README.md: c.sh`, last
  line `readme-index: 1 missing in 1 of 2 READMEs checked (report only)`.
- **I8 ignore list** — root README names `` `records/` `` and `` `ignore.txt` `` but not
  `fixtures`; `ignore.txt` (staged) holds a `#` comment, a blank line, `records/*/` and
  `fixtures/`. Files: `records/README.md` (text `Records.`), `records/r1/README.md`
  (`Manifest.`), `records/r1/auto/p.md`, `records/loose.md`, `fixtures/README.md`
  (`Data.`), `fixtures/f.json`. With `--ignore <repo>/ignore.txt`: line
  `records/README.md: records/loose.md` (a folder-only pattern does not match a file);
  nothing mentioning `records/r1` or `fixtures`. RC 1.
- **I9 usage errors** — each RC 2: `--ignore "$TMP/nonexistent"` (and the output contains
  `readme-index: error:`); an ignore file holding `/abs`; one holding `a/../b`; an unknown
  flag `--bogus`.
- **I10 not a checkout** — a plain directory with a `README.md`, run under
  `GIT_CEILING_DIRECTORIES="$TMP"`: RC 2 and output containing `readme-index: error:`.
- **I11 generated README** — root README names `` `plans/` ``. `plans/README.md` is these
  lines (write them with `printf`):
  `# Plans`, ``, ``_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`, and``,
  ``**overwritten on every pull** — never edit it. Entries go in the repo-owned `PROJECT_FACTS.md`._``,
  ``, ``- `gate.sh` — the gate.``, ``- `features/` — the features.``.
  `plans/PROJECT_FACTS.md` names `` `extra.sh` ``. Files `plans/gate.sh`, `plans/extra.sh`,
  `plans/other.sh`. Also `plans/features/README.md` generated the same way but naming
  ``repo-owned `../MISSING.md` ``, and `plans/features/x.md`. Assert: line
  `plans/PROJECT_FACTS.md (generated plans/README.md): plans/other.sh`; line
  `plans/MISSING.md (generated plans/features/README.md): plans/features/x.md`; nothing
  mentioning `plans/extra.sh` or `plans/gate.sh`; RC 1.
- **I12 read-only** — before the first case, record `git -C <repo> status --porcelain` and
  `cksum <repo>/.git/index` for the I2 and I11 repos; after the last case, both unchanged;
  and `find "$TMP" -name __pycache__` prints nothing.
- **I13 a subfolder is named by its name** — I1 with the root README's `` `sub/` ``
  replaced by the prose word `sub` alone (`The sub folder.`): RC 0.

End with the summary line and `exit 1` when `fails > 0`.

## `self/gate.sh`

1. In the `shell_scripts=(…)` list, after the line `  self/tests/review-report-untrack.sh`,
   add `  self/tests/readme-index.sh`.
2. After the line
   `record "review report untrack self-test" bash self/tests/review-report-untrack.sh`, add:

```bash
# The README-index checker's contract (../check-readme-index.py): tracked files only,
# direct children only, the recognition rule's boundaries and case, the ignore list, a
# generated README checked against the repo-owned file its header names, report-only
# exiting 0, errors exiting 2, and nothing written (self/features/readme-index-check/).
record "readme index self-test" bash self/tests/readme-index.sh
```

## `self/tests/README.md`

Append one bullet at the end of the file (after the `gate-resume.sh` bullet), in the
shape of its neighbours: `- \`readme-index.sh\` — …` describing the sandbox (a copy of
`../../check-readme-index.py` run with `python3 -B` over `git init` repos in one
`mktemp -d`, files staged, never committed), each case I1–I13 in a clause, and
"Depends on the checker's output lines and exit codes as its docstring states them. No
model, no network."
