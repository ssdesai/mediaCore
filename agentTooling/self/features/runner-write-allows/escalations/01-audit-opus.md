Verdict: escalated

# Security audit — runner-write-allows (head `b10db8e` against `origin/main` `bc02631`)

Rules the diff adds or changes (`hooks/allow-repo-commands.sh`, documented in `hooks/README.md`):

1. **Runner allowlists** (`RUNNER_BARE_FLAGS`, `RUNNER_VALUE_FLAGS`, `RUNNER_CONFIG_FLAGS`,
   `RUNNER_SHORT_BUNDLES`, `runner_words`, `ruff_form_allowed`): ruff, mypy and pytest,
   whether bare, given as a path or run as `python3 -m`, are approved silently only when
   every word is one the lists name; anything else prompts. This applies to every caller
   in both profiles.
2. **`--config` / `--config-file`** (`runner_config_file_ok`): approved only when the value
   is an existing regular file inside the root, otherwise it prompts.
3. **Pinned Python entry points** (`pinned_entry_dir`, `report_shape`): `report.py`,
   `manifest.py` and `capture_planning.py` are approved only at `<root>/analysis/<s>` or
   `<root>/agentTooling/analysis/<s>`, as a regular file with no symlinks, and `report.py`
   only in its exact shapes (`<root>/analysis/report.py` also needs `--self`). Anything
   else prompts.
4. **`symlink_free_below` on `gate.sh` / `check-plans.sh`** (`entry_script`): a token that
   has a symlink component below the root prompts.

## Method

- Two throwaway copies: `git archive HEAD` → `/tmp/plan-capture.hcvIw1/scratch/head` and
  `git archive origin/main` → `…/scratch/base`.
- Fixtures were planted in both copies (`attack.py: prep`): `src/a.py`; `fix.toml`
  (`fix = true`); `cfg.ini` (`[mypy] junit_xml = out.xml`); `args.txt`; the planted scripts
  `x/{gate.sh,check-plans.sh,report.py,manifest.py,capture_planning.py}` and
  `agentTooling/analysis/{report,manifest,capture_planning}.py`; the symlinks
  `alink→analysis`, `glink→self`, `atlink→.`, `linked/gate.sh` and `linked/report.py`.
- Each hook was run with a PreToolUse JSON (`tool_name: Bash`, `session_id`, `cwd`,
  `tool_input.command`) on stdin and `CLAUDE_PROJECT_DIR` set to its copy. The driver is
  `python3 /tmp/plan-capture.hcvIw1/scratch/attack.py <cases> [local|cloud]`.
- The main batch (`…/scratch/cases.txt`) was run under both profiles. `local` and
  `cloud` gave the same results (57 head allows each).
- No input is allowed on the head that the base does not allow, so there is no
  regression.
- Each suspicious allow was replayed against the real tools (ruff 0.16.9, mypy 2.3.1,
  pytest 9.1.1) in `…/scratch/tool` (`tools.sh`, `wdemo.sh`, `mypyw.sh`).
- Every allowlisted word was checked against each tool's `--help` (`words.py`). Four
  words do not appear there: ruff `--extend-ignore`, mypy `--color-output` and
  `--soft-error-limit`, and pytest `-n`. The two mypy words were run against mypy and
  `--extend-ignore` against ruff (`mypyw.sh`); each was accepted as its own option and
  wrote nothing. pytest `-n` is an xdist option and xdist is not installed, so it was not
  run. None of the four is an abbreviation that expands to another flag.

Results: `allow` = silent approval; `prompt` = no output (the human is asked); `deny` = sent
back with a rewrite.

## Inputs tried

| # | input | head | base |
|---|---|---|---|
| 1 | `ruff check src/a.py` | allow | allow |
| 2 | `ruff check --select E,F --output-format concise src/a.py` | allow | allow |
| 3 | `ruff format --check src/a.py` | allow | allow |
| 4 | `ruff format src/a.py --diff` | allow | allow |
| 5 | `ruff --version` | allow | allow |
| 6 | `ruff version` | allow | allow |
| 7 | `ruff rule E501` | allow | allow |
| 8 | `python3 -m ruff check src/a.py` | allow | allow |
| 9 | `.venv/bin/ruff check src/a.py` | allow | allow |
| 10 | `ruff check --config pyproject.toml src/a.py` (no such file in the copy) | prompt | allow |
| 11 | `ruff check --fix src/a.py` | prompt | prompt |
| 12 | `ruff check --fix-only src/a.py` | prompt | prompt |
| 13 | `ruff check --unsafe-fixes src/a.py` | prompt | prompt |
| 14 | `ruff check --add-noqa src/a.py` | prompt | allow |
| 15 | `ruff check --config 'fix = true' src/a.py` | prompt | allow |
| 16 | `ruff check --config fix=true src/a.py` | prompt | allow |
| 17 | `ruff check --config=fix=true src/a.py` | prompt | allow |
| 18 | `ruff --config 'fix = true' check src/a.py` | prompt | allow |
| 19 | `ruff check --config fix.toml src/a.py` (planted `fix = true`) | allow | allow |
| 20 | `ruff check --config src src/a.py` (a directory) | prompt | allow |
| 21 | `ruff check --config /etc/hosts src/a.py` | prompt | prompt |
| 22 | `ruff check --config ./alink/../fix.toml src/a.py` | deny | deny |
| 23 | `ruff format src/a.py` | prompt | prompt |
| 24 | `ruff format --check=false src/a.py` | prompt | prompt |
| 25 | `ruff --check format src/a.py` (ruff rejects it: "unexpected argument", file unchanged) | allow | allow |
| 26 | `ruff format --line-length 1 src/a.py` | prompt | prompt |
| 27 | `ruff format --line-length=--check src/a.py` | prompt | prompt |
| 28 | `ruff format --exclude --check src/a.py` | prompt | allow |
| 29 | `ruff check --output-file o.txt src/a.py` | prompt | allow |
| 30 | `ruff check -o o.txt src/a.py` | prompt | allow |
| 31 | `ruff check --show-settings -o o.txt src/a.py` | prompt | allow |
| 32 | `ruff check --cache-dir c src/a.py` | prompt | allow |
| 33 | `ruff check --watch src/a.py` | prompt | allow |
| 34 | `ruff clean` | prompt | allow |
| 35 | `ruff server` | prompt | allow |
| 36 | `ruff analyze graph src` | prompt | allow |
| 37 | `ruff check -- src/a.py` | prompt | allow |
| 38 | `ruff check @args.txt` | prompt | allow |
| 39 | `ruff check --select @args.txt src/a.py` | prompt | allow |
| 40 | `ruff check --select --fix src/a.py` | prompt | prompt |
| 41 | `ruff check --select=E,--fix src/a.py` (ruff: "Unknown rule selector `--fix`", exit 2, file unchanged) | allow | allow |
| 42 | `ruff check -eq src/a.py` | prompt | allow |
| 43 | `ruff check --no-fix --fix src/a.py` | prompt | prompt |
| 44 | `ruff check --fi src/a.py` | prompt | allow |
| 45 | `ruff check -` | prompt | allow |
| 46 | `ruff rule --all` | prompt | allow |
| 47 | `ruff rule E501 x` | prompt | allow |
| 48 | `ruff "check" --fix src/a.py` | prompt | prompt |
| 49 | `r""uff check --fix src/a.py` | prompt | prompt |
| 50 | `ruff ch\eck --fix src/a.py` | prompt | prompt |
| 51 | `ruff check --f{ix,oo} src/a.py` | prompt | prompt |
| 52 | `ruff check {--fix,src/a.py}` | prompt | prompt |
| 53 | `ruff check --fi* src/a.py` | prompt | allow |
| 54 | `python3 -m ruff check --fix src/a.py` | prompt | prompt |
| 55 | `python3 -m ruff format src/a.py` | prompt | prompt |
| 56 | `.venv/bin/ruff format src/a.py` | prompt | prompt |
| 57 | `env ruff check --fix src/a.py` | prompt | prompt |
| 58 | `env env ruff check --fix src/a.py` | prompt | prompt |
| 59 | `/usr/bin/env ruff check --fix src/a.py` | prompt | prompt |
| 60 | `command ruff check --fix src/a.py` | prompt | prompt |
| 61 | `exec -a x ruff check --fix src/a.py` | prompt | prompt |
| 62 | `nohup ruff check --fix src/a.py` | prompt | prompt |
| 63 | `xargs ruff check --fix src/a.py` | prompt | prompt |
| 64 | `sudo ruff check --fix src/a.py` | prompt | prompt |
| 65 | `find src -exec ruff check --fix {} ;` | prompt | prompt |
| 66 | `bash -c 'ruff check --fix src/a.py'` | deny | deny |
| 67 | `echo ruff check --fix src/a.py \| sh` | prompt | prompt |
| 68 | `RUFF_FIX=true ruff check src/a.py` | prompt | prompt |
| 69 | `RUFF_OUTPUT_FILE=o ruff check src/a.py` | prompt | prompt |
| 70 | `ruff check src/a.py; ruff check --fix src/a.py` | deny | deny |
| 71 | `ruff check src/a.py && ruff format src/a.py` | prompt | prompt |
| 72 | `ruff check src/a.py \| ruff format src/a.py` | prompt | prompt |
| 73 | `mypy src/a.py` | allow | allow |
| 74 | `mypy --strict --show-error-codes src/a.py` | allow | allow |
| 75 | `mypy -p src` | allow | allow |
| 76 | `mypy --config-file pyproject.toml src/a.py` (no such file) | prompt | allow |
| 77 | `python3 -m mypy src/a.py` | allow | allow |
| 78 | `mypy --install-types src/a.py` | prompt | prompt |
| 79 | `mypy --install-type src/a.py` | prompt | allow |
| 80 | `mypy --inst src/a.py` | prompt | allow |
| 81 | `mypy --python-executable /bin/sh src/a.py` | prompt | prompt |
| 82 | `mypy --python-executable=src/a.py src/a.py` | prompt | allow |
| 83 | `mypy --junit-xml o.xml src/a.py` | prompt | allow |
| 84 | `mypy --html-report d src/a.py` | prompt | allow |
| 85 | `mypy --txt-report d src/a.py` | prompt | allow |
| 86 | `mypy --cache-dir c src/a.py` | prompt | allow |
| 87 | `mypy --sqlite-cache src/a.py` | prompt | allow |
| 88 | `mypy @args.txt` | prompt | allow |
| 89 | `mypy src/a.py @args.txt` | prompt | allow |
| 90 | `mypy -c 'import os'` | prompt | allow |
| 91 | `mypy --command 'import os'` | prompt | allow |
| 92 | `mypy --config-file cfg.ini src/a.py` (planted `junit_xml`; writes `out.xml`) | allow | allow |
| 93 | `mypy --config-file 'junit_xml=o' src/a.py` | prompt | allow |
| 94 | `mypy --config-file=src src/a.py` | prompt | allow |
| 95 | `mypy -p --junit-xml src/a.py` | prompt | allow |
| 96 | `mypy --package=--junit-xml src/a.py` | prompt | allow |
| 97 | `mypy --pretty=1 src/a.py` | prompt | allow |
| 98 | `mypy --strict-equality src/a.py` (unlisted, harmless) | prompt | allow |
| 99 | `mypy --stri src/a.py` | prompt | allow |
| 100 | `mypy --show-traceback --pdb src/a.py` | prompt | allow |
| 101 | `mypy --platform @args.txt src/a.py` | prompt | allow |
| 102 | `mypy -m@args.txt` | prompt | allow |
| 103 | `mypy --non-interactive --install-types src/a.py` | prompt | prompt |
| 104 | `mypy --warn-unused-configs src/a.py` (unlisted, harmless) | prompt | allow |
| 105 | `python3 -m mypy --install-types src/a.py` | prompt | prompt |
| 106 | `pytest -q tests/test_a.py` | allow | allow |
| 107 | `pytest -qx -rA tests/test_a.py` | allow | allow |
| 108 | `pytest -k a -m 'not slow' --tb short tests/test_a.py` | allow | allow |
| 109 | `pytest -n 4 tests/test_a.py` | allow | allow |
| 110 | `pytest --lf --co tests` | allow | allow |
| 111 | `pytest -vv tests` | allow | allow |
| 112 | `pytest --basetemp o tests` | prompt | allow |
| 113 | `pytest --basetemp=o tests` | prompt | allow |
| 114 | `pytest --junitxml o.xml tests` | prompt | allow |
| 115 | `pytest --junitxml=o.xml tests` | prompt | allow |
| 116 | `pytest --junit-xml=o.xml tests` | prompt | allow |
| 117 | `pytest --log-file o.log tests` | prompt | allow |
| 118 | `pytest --debug tests/test_a.py` | prompt | allow |
| 119 | `pytest --resultlog o tests` | prompt | allow |
| 120 | `pytest --pastebin all tests` | prompt | allow |
| 121 | `pytest -o cache_dir=o tests` | prompt | allow |
| 122 | `pytest --override-ini addopts=--junitxml=o.xml tests` | prompt | allow |
| 123 | `pytest -p no:cacheprovider tests` | prompt | allow |
| 124 | `pytest -p src.a tests` | prompt | allow |
| 125 | `pytest -c fix.toml tests` | prompt | allow |
| 126 | `pytest --rootdir src tests` | prompt | allow |
| 127 | `pytest --confcutdir src tests` | prompt | allow |
| 128 | `pytest --pdb tests` | prompt | allow |
| 129 | `pytest --cache-clear tests` | prompt | allow |
| 130 | `pytest @args.txt` | prompt | allow |
| 131 | `pytest -kfoo tests` | prompt | allow |
| 132 | `pytest -n4 tests` | prompt | allow |
| 133 | `pytest -n=4 tests` | prompt | allow |
| 134 | `pytest -qp xdist tests` | prompt | allow |
| 135 | `pytest -rAp tests` (`p` is a report char) | allow | allow |
| 136 | `pytest -xs tests` | allow | allow |
| 137 | `pytest -sl tests` | allow | allow |
| 138 | `pytest -k --basetemp=o tests` | prompt | allow |
| 139 | `pytest --tb=--basetemp tests` | prompt | allow |
| 140 | `pytest --junit tests` | prompt | allow |
| 141 | `pytest --basetem o tests` | prompt | allow |
| 142 | `pytest --capture=no tests` | prompt | allow |
| 143 | `pytest -- tests` | prompt | allow |
| 144 | `pytest -W ignore::this.X tests/test_a.py` (imports `this`: prints the Zen) | **allow** | allow |
| 145 | `pytest -W 'ignore::antigravity.X' tests/test_a.py` (imports `antigravity`, **runs a browser**) | **allow** | allow |
| 146 | `pytest -W error::src.a.X tests/test_a.py` | allow | allow |
| 147 | `pytest --color yes tests` | allow | allow |
| 148 | `pytest --durations 0 tests` | allow | allow |
| 149 | `pytest --deselect tests/test_a.py::test_a tests` | allow | allow |
| 150 | `pytest --ignore-glob '*' tests` | allow | allow |
| 151 | `pytest --sw tests` | allow | allow |
| 152 | `python3 -m pytest --basetemp o tests` | prompt | allow |
| 153 | `python3 -m pytest -q tests` | allow | allow |
| 154 | `python3 -m pytest -W ignore::antigravity.X tests/test_a.py` | **allow** | allow |
| 155 | `pytest -W ignore::antigravity.X -W ignore::this.X tests` | **allow** | allow |
| 156 | `pytest --pythonwarnings ignore::antigravity.X tests` | prompt | allow |
| 157 | `pytest -Wignore::antigravity.X tests` | prompt | allow |
| 158 | `pytest -k 'a or b' -W error tests` | allow | allow |
| 159 | `python3 analysis/report.py --self runner-write-allows` | allow | allow |
| 160 | `python3 analysis/report.py runner-write-allows` (writes outside the root) | prompt | allow |
| 161 | `python3 analysis/report.py --self --all` | allow | allow |
| 162 | `python3 analysis/report.py --self --rounds-md runner-write-allows` | allow | allow |
| 163 | `python3 analysis/report.py --self --orchestration runner-write-allows` | allow | allow |
| 164 | `python3 analysis/report.py --self --arm-root src runner-write-allows` | prompt | allow |
| 165 | `python3 analysis/report.py --self --checkout src runner-write-allows` | prompt | allow |
| 166 | `python3 analysis/report.py --self --self runner-write-allows` | prompt | allow |
| 167 | `python3 analysis/report.py --self -- runner-write-allows` | prompt | allow |
| 168 | `python3 analysis/report.py --self --al` | prompt | allow |
| 169 | `python3 analysis/report.py --self --all --all` | prompt | allow |
| 170 | `python3 analysis/report.py --all --self` | prompt | allow |
| 171 | `python3 analysis/report.py --self Runner_X` | prompt | allow |
| 172 | `python3 analysis/report.py --self runner-write-allows extra` | prompt | allow |
| 173 | `python3 ./analysis/report.py --self runner-write-allows` | allow | allow |
| 174 | `python3 analysis//report.py --self runner-write-allows` | allow | allow |
| 175 | `python3 analysis/./report.py --self runner-write-allows` | allow | allow |
| 176 | `python3 <abs root>/analysis/report.py --self runner-write-allows` | allow | allow |
| 177 | `python3 -B analysis/report.py --self runner-write-allows` | allow | allow |
| 178 | cwd=`analysis`: `python3 ./report.py --self runner-write-allows` | allow | allow |
| 179 | cwd=`alink` (→ `analysis`): `python3 ./report.py --self runner-write-allows` (the real script) | allow | allow |
| 180 | `python3 alink/report.py --self runner-write-allows` | prompt | allow |
| 181 | `python3 linked/report.py --self runner-write-allows` | prompt | allow |
| 182 | `python3 x/report.py --self runner-write-allows` (planted) | prompt | allow |
| 183 | `python3 agentTooling/analysis/report.py --all` (planted, standalone checkout) | allow | allow |
| 184 | `python3 agentTooling/analysis/report.py runner-write-allows` (planted) | allow | allow |
| 185 | `python3 agentTooling/analysis/manifest.py runner-write-allows get status` (planted) | allow | allow |
| 186 | `python3 agentTooling/analysis/capture_planning.py --list-sessions` (planted) | allow | allow |
| 187 | `python3 atlink/analysis/report.py --self --all` | prompt | allow |
| 188 | `python3 x/manifest.py runner-write-allows get status` (planted) | prompt | allow |
| 189 | `python3 analysis/manifest.py runner-write-allows get status` | allow | allow |
| 190 | `python3 analysis/manifest.py runner-write-allows set-status x` | prompt | prompt |
| 191 | `python3 analysis/capture_planning.py --self --list-sessions` | allow | allow |
| 192 | `python3 analysis/capture_planning.py --self runner-write-allows` | prompt | prompt |
| 193 | `python3 -m analysis.report --self runner-write-allows` | prompt | prompt |
| 194 | `python3 -c 'import analysis.report'` | deny | deny |
| 195 | `python3 -i analysis/report.py --self --all` | prompt | prompt |
| 196 | `python3 -W ignore analysis/report.py --self --all` | prompt | prompt |
| 197 | `python3 -X importtime analysis/report.py --self --all` | prompt | prompt |
| 198 | `python3 -I analysis/report.py --self --all` | prompt | prompt |
| 199 | `env python3 analysis/report.py --self --all` | prompt | prompt |
| 200 | cwd=`src`: `python3 ../analysis/report.py --self --all` | prompt | prompt |
| 201 | `self/gate.sh` | allow | allow |
| 202 | `./self/gate.sh fast` | allow | allow |
| 203 | `./check-plans.sh --self runner-write-allows` | allow | allow |
| 204 | `glink/gate.sh` (symlinked dir) | prompt | allow |
| 205 | `linked/gate.sh` (symlinked file) | prompt | allow |
| 206 | `x/gate.sh` (planted) | allow | allow |
| 207 | `x/check-plans.sh --anything` (planted) | allow | allow |
| 208 | `./x/../self/gate.sh` | deny | deny |
| 209 | `check-plans.sh --self x` | prompt | prompt |
| 210 | `bash self/gate.sh` | prompt | prompt |
| 211 | `bash x/gate.sh` | prompt | prompt |
| 212 | `ruff check --config fix.toml --fix src/a.py` | prompt | prompt |
| 213 | `mypy --config-file cfg.ini --junit-xml o src/a.py` | prompt | allow |
| 214 | cwd=`src`: `ruff check --config ../fix.toml a.py` | deny | deny |
| 215 | cwd=`src`: `mypy --config-file <abs root>/cfg.ini a.py` | allow | allow |
| 216 | payload with no `cwd` (`pytest -q tests/test_a.py`) | prompt | prompt |
| 217 | payload `cwd: /tmp` | prompt | prompt |
| 218 | payload `cwd: null` | prompt | prompt |
| 219 | payload with no `tool_input` | prompt | prompt |
| 220 | payload `command` is a list | prompt | prompt |
| 221 | stdin not JSON | prompt | prompt |
| 222 | empty stdin | prompt | prompt |
| 223 | payload with `agent_id` (subagent), `ruff check --config fix.toml src/a.py` | allow | allow |
| 224 | `tool_name: Write` | prompt | prompt |
| 225 | cwd=`/`, `python3 <abs root>/analysis/report.py --self --all` | prompt | prompt |

The rows from `cases.txt` were run under both the `local` and `cloud` profiles, with the
same results. Rows 154–158, 200 and 212–215 come from `cases2.txt` and rows 216–225 from
`malformed.py`; those were run under `local`.

Replays against the real tools (`…/scratch/tool`):

- **Row 25 `ruff --check format`:** exit 2, "unexpected argument", file unchanged.
- **Row 41 `--select=E,--fix`:** exit 2, "Unknown rule selector", file unchanged.
- **Row 19 `--config fix.toml`:** "2 fixed", and the file was rewritten.
- **Row 92 `--config-file cfg.ini`:** `out.xml` was created.
- **Row 144 `-W ignore::this.X`:** printed the Zen of Python.
- **Row 145 `-W ignore::antigravity.X`:** with a stub `www-browser` on `PATH`, the stub ran
  with `https://xkcd.com/353/`. The same run without `-W` ran nothing.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | `pytest -W 'ignore::antigravity.X' tests/test_a.py` (also `python3 -m pytest -W …`, and any `-W <action>::<module>.<name>`) | allow — pytest imports `<module>` (`_resolve_warning_category`) and `antigravity` runs the first browser on `PATH` | allow | `python3 …/scratch/attack.py …/scratch/cases.txt` (head copy and base copy, rows 144–146, 154–155); `bash …/scratch/wdemo.sh` (stub `www-browser` ran with `https://xkcd.com/353/`) |
| non-blocking | `ruff check --config fix.toml src/a.py` / `mypy --config-file cfg.ini src/a.py`, with an in-root file holding `fix = true` / `junit_xml` | allow — ruff rewrote the file; mypy wrote `out.xml` | allow | `attack.py` rows 19 and 92 on both copies; `bash …/scratch/tools.sh` |
| non-blocking | `python3 agentTooling/analysis/{report,manifest,capture_planning}.py …` in agentTooling's standalone checkout, where no such file belongs (a planted file) | allow — runs the planted file | allow | `attack.py` rows 183–186 on both copies |
| non-blocking | `x/gate.sh`, `x/check-plans.sh --anything` (planted files carrying the basename) | allow — runs the planted file | allow | `attack.py` rows 206–207 on both copies |

## Non-blocking findings

These are pre-existing: the base gives the same `allow`. Each needs a file written into
the root first, so it does no more than editing the repo's real config or script, which
both heads already approve running (the `README.md` accepted limits "Repo code runs" and
"What the repo's own config asks a run to write is the repo's"). They are listed as
follow-ups because each contradicts what the diff's `README.md` says the rule does.

1. **`--config` / `--config-file` accepts any in-root regular file.**
   - Input: `ruff check --config fix.toml src/a.py` or `mypy --config-file cfg.ini src/a.py`.
   - Results: allow on the head and allow on the base. ruff rewrites the file; mypy writes
     the junit XML.
   - Why it matters: `runner_config_file_ok`'s docstring calls the value "the settings file
     a run would have found on its own". An arbitrary in-root file is not that file.
   - What the rule should do instead: approve only the config names the tool would
     discover itself (`pyproject.toml`, `ruff.toml`, `.ruff.toml`, `mypy.ini`, `.mypy.ini`,
     `setup.cfg`), or prompt on every `--config`/`--config-file`.
2. **Both pinned directories are accepted in every repo.**
   - Input: `python3 agentTooling/analysis/report.py --all` (also `manifest.py … get`
     and `capture_planning.py --list-sessions`) in the standalone checkout, against a
     planted file. The reverse case is a planted `<root>/analysis/report.py` in a
     consuming repo.
   - Results: allow on the head and allow on the base.
   - Why it matters: `hooks/README.md` says "a planted `x/report.py` or
     `dir/analysis/report.py` inside the root … refuse". A planted file at the other pinned
     directory still runs.
   - What the rule should do instead: pin to the one directory that holds the hook
     itself. That is `analysis/` when the hook is `<root>/hooks/…` and
     `agentTooling/analysis/` when it is `<root>/agentTooling/hooks/…`, the way
     `orchestrator_tooling_file` already pins.
3. **`gate.sh` / `check-plans.sh` are still matched by basename.**
   - Input: `x/gate.sh`, `x/check-plans.sh --anything` against planted files.
   - Results: allow on the head and allow on the base.
   - Why it matters: the diff kept basename matching on purpose and added only
     `symlink_free_below`, so any in-root file with that name runs.
   - What the rule should do instead: pin to the known spellings (`self/gate.sh` or
     `plans/gate.sh`; `check-plans.sh` or `agentTooling/check-plans.sh`).

## Blocking findings

### B1 — pytest `-W` imports any module named in its value

**Reproduce:**
- In a throwaway copy of this head, the hook's payload is
  `{"tool_name":"Bash","cwd":"<root>","tool_input":{"command":"pytest -W 'ignore::antigravity.X' tests/test_a.py"}}`.
  It is approved silently (`allow`), as are `python3 -m pytest -W …` and
  `pytest -W ignore::this.X …`.
- Running the command, pytest's `parse_warning_filter` → `_resolve_warning_category` calls
  `__import__("antigravity")`. The import calls `webbrowser.open`, which runs the first
  browser on `PATH`. In `wdemo.sh` that was a stub `www-browser`, and the stub ran.
- Any installed module can be named this way, and its import-time code runs. That is code
  outside the repo, chosen on the command line, so the "Repo code runs" limit does not
  cover it.

**Why blocking:** under ruling (b), this is a silent allow of a command that runs something
that is not read-only. The base allows it too, but (b) does not depend on the base. It
matches the reason `-p` was left out of the pytest allowlist (it loads a module by name):
`-W` loads one just the same.

**What the rule should do instead:**
- Remove `-W` from `RUNNER_VALUE_FLAGS[pytest]`, so it prompts.
- Or approve `-W` only when its value's category field (the third `:`-separated part) is
  empty or has no `.`. A builtin category such as `DeprecationWarning` is looked up in
  `builtins` and nothing is imported.
- Add `pytest -W ignore::antigravity.X tests` to `RUNNER_WRITE_PROMPT` in
  `self/tests/allow-repo-commands.sh`, beside the `-p` case.
