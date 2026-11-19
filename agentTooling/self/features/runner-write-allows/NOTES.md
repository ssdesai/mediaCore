# runner-write-allows — rulings

The coordinator's rulings, written before the build. The builder records what it finds
under "Build log" below. Each F-number is one of the audit findings in the manifest.

## Rulings

1. **Allowlist, not denylist, for the three runners.** `RUNNER_FORBIDDEN_FLAGS` is
   replaced by an allowlist per runner. Each allowlist is a named constant set and is
   checked word by word:
   - **Exact match.** No prefixes, and so no abbreviations (F5).
   - **Value flags.** A flag that takes a value is listed as one. Its value is the next
     word, which must not start with `-` (or `@`), or the value comes in the long form's
     `--flag=value`.
   - **Positionals.** These are files or node ids, already path-checked by
     `token_confined`.
   - **`@`.** Any word starting with `@`, positional or value, is no approval (F5).
   - **Anything else** prompts: an unknown flag, an attached short value (`-kfoo`), a
     bare `--`.

   The same rule covers `ruff`, `mypy` and `pytest`, a path to them (`.venv/bin/ruff`),
   and `python[3] -m ruff|mypy|pytest`.
2. **ruff.** The only approved shapes are these:
   - `ruff check [flags] [paths]`.
   - `ruff format --check|--diff [flags] [paths]`. `--check` or `--diff` is required, as
     today.
   - `ruff --version`, `ruff version` and `ruff rule <code>`.

   Every other subcommand prompts. That includes `clean`, which deletes the cache,
   `server` and `analyze`.

   The allowlisted flags are read-only:
   - Rule selection: `--select`, `--ignore`, `--extend-select`, `--extend-ignore`,
     `--per-file-ignores`, `--extend-per-file-ignores`.
   - File selection: `--exclude`, `--extend-exclude`, `--respect-gitignore`,
     `--no-respect-gitignore`, `--force-exclude`, `--no-force-exclude`.
   - Settings and output: `--target-version`, `--line-length`, `--preview`,
     `--no-preview`, `--isolated`, `--no-cache`, `--output-format`, `--statistics`,
     `--show-fixes`, `--no-show-fixes`, `--show-files`, `--show-settings`, `--diff`,
     `--no-fix`, `--exit-zero`/`-e`, `-q`/`--quiet`, `-s`/`--silent`, `-v`/`--verbose`.

   `--config <value>` (and `--config=<value>`) is approved only when the value names an
   existing regular file inside the root (F1). Never approved:
   - `--fix`, `--fix-only`, `--unsafe-fixes` and `--add-noqa` (F2);
   - `--output-file`/`-o` (F4);
   - `--cache-dir` and `--watch`.

   Global flags may come before or after the subcommand.
3. **mypy.** Positional files are approved, and so are these flags:
   - Targets: `-p`/`--package <pkg>` and `-m`/`--module <mod>`.
   - Strictness: `--strict`, `--ignore-missing-imports`, `--check-untyped-defs`,
     `--disallow-untyped-defs`, `--disallow-incomplete-defs`, `--warn-unused-ignores`,
     `--warn-return-any`, `--warn-redundant-casts`, `--no-implicit-optional`.
   - Import handling: `--follow-imports <v>`, `--namespace-packages`,
     `--explicit-package-bases`.
   - Output: `--show-error-codes`, `--hide-error-codes`, `--show-column-numbers`,
     `--show-error-context`, `--hide-error-context`, `--pretty`, `--no-pretty`,
     `--no-error-summary`, `--no-color-output`, `--color-output`, `--show-traceback`,
     `--soft-error-limit <n>`.
   - Run settings: `--no-incremental`, `--python-version <v>`, `--platform <p>`.
   - Information: `--version`/`-V` and `-h`/`--help`.

   `--config-file <file>` is approved when the file exists and is in-root (as ruling 2).
   Never approved:
   - `--python-executable` (F3);
   - `--junit-xml` and every `--*-report` (F4);
   - `--install-types` and its abbreviations (F5);
   - `--cache-dir`, `--sqlite-cache`, `--cache-fine-grained` and `-c`/`--command`.
4. **pytest.** Positional files and node ids are approved, and so are these flags:
   - Verbosity: `-q`, `-v`, `-x`, `-s`, `-l`, and bundles of those letters (`-qx`,
     `-vv`), plus `--quiet`, `--verbose`, `--exitfirst`, `--showlocals`.
   - Reporting: `-r<chars>` with chars from pytest's report set (`fEsxXpPaAwN`).
   - Selection: `-k <expr>`, `-m <expr>`, `--deselect <id>`, `--ignore <path>`,
     `--ignore-glob <glob>`.
   - Run control and output: `--maxfail <n>`, `--tb <style>`, `--durations <n>`,
     `--color <v>`, `-W <spec>`, `--strict-markers`, `--disable-warnings`, `--no-header`,
     `--no-summary`, `--co`/`--collect-only`, `--lf`/`--last-failed`,
     `--ff`/`--failed-first`, `--sw`/`--stepwise`, `-n <num>` (xdist).

   Long value flags may use the `=` form. Never approved:
   - `--basetemp`, `--junitxml`/`--junit-xml`, `--log-file*`, `--debug`,
     `--resultlog`, `--pastebin` (F6);
   - `-o`/`--override-ini` (F6);
   - `-p`, `-c`/`--config-file`, `--rootdir`, `--confcutdir`, `--pdb`/`--trace`, `--`.

   The pytest allowlist is new; a hang (`--pdb`) now prompts, which is a tightening.
5. **report.py (F7, F9).** `python3 [-B] <path>/report.py` is approved only when both
   hold:
   - The path is pinned. It must be exactly `<root>/analysis/report.py` (standalone or
     `--self` checkout) or `<root>/agentTooling/analysis/report.py` (consuming repo). The
     lexical path must equal that, with no symlink component below the root, and the
     realpath must be the real file.
   - The words are an exact shape: `[--self] <slug>`, `[--self] --all`,
     `[--self] --rounds-md <slug>` or `[--self] --orchestration <slug>`.

   `--arm-root` and `--checkout` prompt. The pinned `<root>/analysis/report.py` also
   **requires `--self`**: without it, it writes to `<root>/../plans/features/`, outside
   the root. `<root>/agentTooling/analysis/report.py` writes `<root>/plans/features/`
   either way, so `--self` is optional there.
6. **The other entry points.**
   - `capture_planning.py` and `manifest.py` are pinned the same way: `analysis/` or
     `agentTooling/analysis/` under the root, with no symlink component. Their shapes are
     unchanged.
   - `gate.sh` and `check-plans.sh` keep basename matching, but a token with any symlink
     component below the root is no approval (F9).
   - The orchestrator allowlist (`ORCHESTRATOR_REPORT`, ~line 4749) must not approve
     anything the main path now refuses on these grounds. Check it, and tighten it to the
     same pin if it does.
7. **F10.** Fix `hooks/README.md`'s "Considered and not a bypass" row and the
   `PYTHON_INTERPRETER_FLAGS` comment. `-B` does not stop `py_compile` writing
   `__pycache__/*.pyc`; the write is the check's own output, confined to the root. List
   it under the new "Tool caches" accepted limit.
8. **Accepted limit, new.** "Tool caches": `.ruff_cache`, `.mypy_cache`, `.pytest_cache`
   and `py_compile`'s `.pyc`, at their default places, written by the approved read forms.
   Every flag that moves them prompts. The writes a repo's own config asks for stay under
   "Repo code runs" and "A planted file needs a prior write".
9. **F12.** No change. Recorded in the manifest's exclusions.
10. **Nothing loosens.** Any input that was ask or deny on base must stay ask or deny,
    except a deny that becomes an ask on a form the human must judge anyway, and that only
    if unavoidable; say so in the build log. Keep CONVENTIONS.md's "approved silently"
    paragraph true, saying "in their read-only forms".

## Build log

### Ground truth (ruff 0.16.9, mypy 2.3.1, pytest 9.1.1, run in `mktemp -d` copies)

- F1 `ruff check --config 'fix = true' f.py`, `--config fix=true`, `ruff --config 'fix = true' check f.py`: rewrote the file (removed the unused import) — confirmed.
- F2 `ruff check --add-noqa f.py`: appended `# noqa: F401, I001` to the file — confirmed.
- F4 ruff `--output-file=X`, `--output-file X`, `-o X`, and `--show-settings -o X`: each created X — confirmed.
- ruff `--cache-dir cd1`: created `cd1` — confirmed (never approved). `ruff clean`: deleted `.ruff_cache` — confirmed.
- F3 `mypy --python-executable ./fakepy m.py` and the `=` form: executed `./fakepy` (it touched a marker outside the tree) — confirmed.
- F4 mypy `--junit-xml j.xml`: wrote `j.xml` — confirmed. `--html-report`/`--txt-report` need lxml, which is not installed here (the tool exits before writing); they are still refused, because the reports write on a machine that has lxml.
- F5 mypy `--install-type` and `--inst` are accepted by the argument parser as abbreviations of `--install-types`; `--junit` is rejected as ambiguous (`--junit-xml`/`--junit-format`). `@args.txt` containing `--junit-xml j3.xml` wrote `j3.xml` — `@file` confirmed.
- mypy `--cache-dir mc`: created `mc` — confirmed.
- F6 pytest `--basetemp=bt1` and `--basetemp bt2`: created the directory once a test uses `tmp_path` — confirmed.
- F6 pytest `--junitxml=`/`--junit-xml=`, `--log-file=`, `-o cache_dir=`, `-o log_file=`, `-o addopts=--junitxml=`: each wrote its file/dir — confirmed.
- F6 pytest `--debug tests/test_x.py`: `--debug` takes an optional value and consumed the test file as its output name, **overwriting the test file with the debug log** — confirmed (worst case). `--debug=dbg.log` wrote `dbg.log`.
- F6 pytest `--resultlog=`: unrecognized in 9.1.1 (the option is gone), so a no-op there; still refused (older pytest wrote it). `--pastebin=failed`: accepted with a warning; it uploads a failure's output to a pastebin when a test fails — not reproducible offline, refused regardless.
- pytest `@pargs.txt` holding `--junitxml=jx4.xml`: wrote `jx4.xml` — `@file` confirmed. `-p plug` imported and ran `plug.py` (wrote a marker) — confirmed; `-c o.ini` with `addopts=--junitxml=…`: wrote the report — confirmed.
- pytest 9.1.1 does NOT accept option abbreviations (`--basete`, `--junitx`, `--log-f`, `--maxf` all "unrecognized arguments"); older pytest did. mypy DOES accept abbreviations (`--inst` runs as `--install-types`, `--install-type` too) and `@file`. Both are covered by exact-word allowlists, which do not depend on the installed version. Attached short values (`-ktest_a`) work in pytest, and are no approval here.
- Plain read forms: `ruff check f.py`, `ruff format --check f.py`, `mypy m.py`, `pytest -q tests/x.py` ran and wrote only `.ruff_cache`, `.mypy_cache`, `.pytest_cache`. `python -m ruff|mypy|pytest` is "No module named …" here (the tools are uv tool installs, not importable from `python`), so the module spellings were judged by reading the hook, not run.
- F7 standalone copy (`git archive HEAD` + `git init`), `python3 -B analysis/report.py <slug>` without `--self`, with `<root>/../plans/features/<slug>/` holding a record: wrote `report.md` and `report.json` into `<root>/../plans/features/<slug>/` — outside the root, confirmed. With `--self` it writes `<root>/self/features/<slug>/` (inside). In a consuming layout (`<root>/agentTooling/analysis/report.py`) it writes `<root>/plans/features/` either way. `--orchestration <slug>` without `--self` in a standalone checkout refuses before writing (`STANDALONE_REFUSAL`); `--rounds-md` writes nothing.
- F10 `python3 -B -m py_compile a.py` still wrote `__pycache__/a.cpython-313.pyc` — confirmed; `-B` does not stop it.
- F6 `--basetemp=bt1` / `--basetemp bt2` create the directory once any test uses `tmp_path` (a first run with a test that did not use it created nothing) — confirmed.

### Implementation

- `RUNNER_FORBIDDEN_FLAGS` is gone. `RUNNER_BARE_FLAGS`, `RUNNER_VALUE_FLAGS`, `RUNNER_CONFIG_FLAGS` and `RUNNER_SHORT_BUNDLES` hold the allowlists, per runner; `runner_words` walks the words, `ruff_form_allowed` judges the subcommand, `runner_config_file_ok` the `--config`/`--config-file` value (an existing regular file whose realpath is inside the root).
- Added beyond the rulings' lists, all read-only: `-V`/`--version`/`-h`/`--help` for all three runners (`RUNNER_INFO_FLAGS`; `pytest --version` and `ruff --help` were approved on base and stay so), and ruff's `--check` as a bare flag (it is how `format --check` is spelled).
- `entry_script` (gate.sh, check-plans.sh) now also requires `symlink_free_below`. `pinned_entry_dir` pins report.py, capture_planning.py and manifest.py; `report_shape` is the exact report.py shape and requires `--self` at `<root>/analysis/report.py`.
- Orchestrator allowlist (ruling 6): checked, no change. `orchestrator_tooling_file` already resolves the script to *this hook's own* `analysis/<name>` (realpath equality, final component not a symlink), and `report.py` is approved there only as `[--self] --orchestration <slug> [--checkout R=P]…`, which writes `plans/orchestrations/` or `self/orchestrations/` (and refuses standalone-without-`--self` itself). It approves nothing the main path now refuses on these grounds, so I left it untouched rather than add a root the function does not have.
- Existing test row changed: `python3 -B analysis/report.py --all` (ENTRY_ALLOW) now reads `python3 -B analysis/report.py --self --all`, because the checkout's own script without `--self` is the F7 write. The old spelling is now in `RUNNER_WRITE_PROMPT`. No other existing row changed.
- Tightenings beyond the F-cases, all "prompt" where base allowed: any flag not in an allowlist (so `pytest --pdb`, `--cache-clear`, `-p`, `-c`, `--rootdir`, unknown plugin flags prompt), a bare `ruff`/`ruff src`, `--help` without a subcommand beyond the info flags, and an entry script reached from a cwd that is not lexically the root (for example a worktree under `<root>/.worktrees/x` running its own `analysis/report.py`, whose lexical path is not `<root>/analysis/…`): the ruling's "exactly `<root>/analysis/report.py`" prompts there.
- Nothing loosens. The negative control (the new test file run against `git archive HEAD`'s hook) fails on the F-case rows and passes the read-form rows, so the read forms were approved on base too. No deny became an ask.
- Gate: not run (the coordinator's). Run: `self/tests/allow-repo-commands.sh`, `hook-cloud-profile`, `hook-escalation`, `hook-orchestrator-role`, `hook-quote-oracle`, `hook-wiring`, `policy-table`, `shared-rules`, `security-audit`, `self-settings`, `hook-brief-header`, `env-profile`, `propagation-pull` — all green; `py_compile hooks/allow-repo-commands.sh`, `check-readme-index.py` clean.

### Round 2

Rework for the audit's blocking finding B1 (`escalations/01-audit-opus.md`): pytest `-W` was
in `RUNNER_VALUE_FLAGS`, and pytest imports the module named in the value's category field
(`-W ignore::antigravity.X` runs that module's import-time code, a browser launch), so it was
a silent allow of something that is not read-only, the same reason `-p` was left out. `-W` is
now not an allowlisted word and prompts, with no parser for its value. `RUNNER_WRITE_PROMPT`
gained `pytest -W ignore::antigravity.X`, `python3 -m pytest -W ignore::this.X`,
`pytest -W error` and `--pythonwarnings`; the `pytest -W error tests` row moved out of
`RUNNER_READ_ALLOW`. `hooks/README.md` lists `-W` among the never-approved pytest flags and
the audit table has a B1 row. The three non-blocking findings are pre-existing accepted limits
(any in-root `--config` file, the other pinned `analysis/` directory, `gate.sh`/`check-plans.sh`
by basename): the README and `runner_config_file_ok`'s docstring now say so rather than imply
the settings file a run would find on its own, and each is a `self/BACKLOG.md` follow-up.
