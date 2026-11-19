Verdict: clean

# Security audit — runner-write-allows (round 2)

Hook files changed against `origin/main`: `hooks/allow-repo-commands.sh`, `hooks/README.md`.

## Rules the diff adds or changes

1. **Runner allowlists** (`runner_words`, `RUNNER_BARE_FLAGS` / `RUNNER_VALUE_FLAGS` /
   `RUNNER_CONFIG_FLAGS` / `RUNNER_SHORT_BUNDLES`): ruff, mypy and pytest (bare, as a path, or
   `python[3] -m`) are approved only when every word is an exact listed flag, a listed
   value flag with a value that starts with neither `-` nor `@`, or a positional. Anything
   else prompts. This applies to every Bash caller.
2. **`ruff_form_allowed`**: ruff is approved only as `check`, `format --check|--diff`,
   `version`, `rule <code>`, or an information flag on its own. `clean`, `server`,
   `analyze` and a bare `format` prompt.
3. **`runner_config_file_ok`**: `ruff --config` and `mypy --config-file` are approved only
   when the value is an existing regular file inside the root (realpath). An inline TOML
   override prompts.
4. **`symlink_free_below` on `entry_script`**: `gate.sh` and `check-plans.sh` are still
   matched by basename, but a token with a symlink component below the root prompts.
5. **`pinned_entry_dir`**: `report.py`, `capture_planning.py` and `manifest.py` are
   approved only at exactly `<root>/analysis/<script>` or
   `<root>/agentTooling/analysis/<script>`. The file must be a regular file with no
   symlink below the root, and its realpath must equal its lexical path.
6. **`report_shape`**: `report.py` is approved only as `[--self] <slug>`, `[--self] --all`,
   `[--self] --rounds-md <slug>` or `[--self] --orchestration <slug>`. The checkout's own
   `<root>/analysis/report.py` requires `--self`.

## Method

- `git archive HEAD` → `/tmp/plan-capture.JJksds/scratch/head` and `git archive origin/main`
  → `…/scratch/base` (`setup.sh`). Each copy's own `hooks/allow-repo-commands.sh` was run
  with `CLAUDE_PROJECT_DIR` set to that copy, `AGENTTOOLING_PROFILE=cloud`,
  `CLAUDE_CODE_REMOTE` unset, and the payload
  `{tool_name: Bash, session_id, agent_id: "", cwd, tool_input: {command}}`
  (`attack.py <cases>`, `{ROOT}` substituted per copy).
- All 371 inputs were rerun under `AGENTTOOLING_PROFILE=local`. No input was more
  permissive on head than on base under either profile.
- Fixtures planted in both copies: `src/a.py`, `tests/test_x.py`, `fixcfg.toml`
  (`fix = true`), `args.txt` (an `@file` holding `--junit-xml out.xml`), and the
  `cfgdir/` directory. Planted scripts: `x/{report,manifest,capture_planning}.py`,
  `x/{gate,check-plans}.sh`, `dir/analysis/report.py`, and a copy at
  `agentTooling/analysis/report.py`. Symlinks: `linked/{report.py,manifest.py,gate.sh,check-plans.sh}`,
  `alink → analysis`, `glink → self`, `agentTooling/alinkdir → analysis`, `tmplink → /tmp`,
  `outlink.toml → /etc/passwd`, `cfglink.toml → fixcfg.toml`. Flag-named files were
  planted under `g/`: `--add-noqa`, `--junit-xml=o.xml`, `-p`.
- Real tools (ruff 0.16.9, mypy 2.3.1, pytest 9.1.1) were checked on a separate scratch tree
  (`real.sh`, `globreal.sh`). mypy's `--color-output` and `--soft-error-limit`, which
  `--help` does not list, are exact flags: mypy accepts both. `pytest -rAp evil` reads `Ap`
  as `-r`'s value and `evil` as a path, so no plugin loads. `ruff check --config fixcfg.toml src`
  does rewrite `src/a.py`. `ruff check *` over a planted `--add-noqa` file does append
  `# noqa` to the file.
- Every allowlisted mypy word was checked against `mypy/main.py`: each one is exact, so
  argparse never reads it as an abbreviation of another flag (`flags.py`).
- The previous round's blocking finding is closed. `pytest -W ignore::antigravity.X …`
  and `python3 -m pytest -W …` (rows 197–202, 253) now prompt.

## Inputs tried

"prompt" means the hook printed nothing, so the call is asked. "allow" and "deny" are the
hook's `permissionDecision`. Rows run from the root unless `[cwd=…]` is given.

| # | input | head | base |
|---|---|---|---|
| 1 | `ruff check src` | allow | allow |
| 2 | `ruff check src/a.py --output-format concise` | allow | allow |
| 3 | `ruff check --output-format=json src` | allow | allow |
| 4 | `ruff format --check src` | allow | allow |
| 5 | `ruff format src --diff` | allow | allow |
| 6 | `python3 -m ruff check src` | allow | allow |
| 7 | `python -m ruff check src` | allow | allow |
| 8 | `ruff --version` | allow | allow |
| 9 | `ruff version` | allow | allow |
| 10 | `ruff rule F401` | allow | allow |
| 11 | `ruff check --config pyproject.toml src` (no such file in the copy) | prompt | allow |
| 12 | `ruff check --select E,F --ignore E501 src` | allow | allow |
| 13 | `ruff check --fix src` | prompt | prompt |
| 14 | `ruff check src --fix` | prompt | prompt |
| 15 | `ruff check --fix-only src` | prompt | prompt |
| 16 | `ruff check --unsafe-fixes --fix src` | prompt | prompt |
| 17 | `ruff check --fi src` | prompt | allow |
| 18 | `ruff check --fix=true src` | prompt | prompt |
| 19 | `ruff check --no-fix --fix src` | prompt | prompt |
| 20 | `ruff check --add-noqa src` | prompt | allow |
| 21 | `ruff check --add-noqa=x src` | prompt | allow |
| 22 | `ruff check -o out.txt src` | prompt | allow |
| 23 | `ruff check --output-file out.txt src` | prompt | allow |
| 24 | `ruff check --output-file=out.txt src` | prompt | allow |
| 25 | `ruff check --show-settings -o out.txt src` | prompt | allow |
| 26 | `ruff check --cache-dir /tmp/rc src` | prompt | prompt |
| 27 | `ruff check --cache-dir=cache src` | prompt | allow |
| 28 | `ruff check --watch src` | prompt | allow |
| 29 | `ruff format src` | prompt | prompt |
| 30 | `ruff format src/a.py` | prompt | prompt |
| 31 | `ruff format --check=false src` | prompt | prompt |
| 32 | `ruff format --no-check src` | prompt | prompt |
| 33 | `ruff format -- --check src` | prompt | allow |
| 34 | `ruff format src -- --check` | prompt | allow |
| 35 | `ruff clean` | prompt | allow |
| 36 | `ruff server` | prompt | allow |
| 37 | `ruff analyze graph src` | prompt | allow |
| 38 | `ruff check --config 'fix = true' src` | prompt | allow |
| 39 | `ruff check --config fix=true src` | prompt | allow |
| 40 | `ruff check --config=fix=true src` | prompt | allow |
| 41 | `ruff --config 'fix = true' check src` | prompt | allow |
| 42 | `ruff check --config 'fix=true' --config pyproject.toml src` | prompt | allow |
| 43 | `ruff check --config pyproject.toml --config fix=true src` | prompt | allow |
| 44 | `ruff check --config fixcfg.toml src` (planted `fix = true`) | allow | allow |
| 45 | `ruff check --config=fixcfg.toml src` | allow | allow |
| 46 | `ruff check --config ./fixcfg.toml src` | allow | allow |
| 47 | `ruff check --config cfglink.toml src` (in-root link to it) | allow | allow |
| 48 | `ruff check --config outlink.toml src` (link to `/etc/passwd`) | prompt | prompt |
| 49 | `ruff check --config cfgdir src` | prompt | allow |
| 50 | `ruff check --config /etc/hostname src` | prompt | prompt |
| 51 | `ruff check --config @args.txt src` | prompt | allow |
| 52 | `ruff check --config -x src` | prompt | allow |
| 53 | `ruff check --config` | prompt | allow |
| 54 | `ruff check --select` | prompt | allow |
| 55 | `ruff check --select @args.txt src` | prompt | allow |
| 56 | `ruff check --select=@args.txt src` | prompt | allow |
| 57 | `ruff check @args.txt` | prompt | allow |
| 58 | `ruff check -- src` | prompt | allow |
| 59 | `ruff check - src` | prompt | allow |
| 60 | `ruff check -e src` | allow | allow |
| 61 | `ruff check -eq src` | prompt | allow |
| 62 | `ruff check -qe src` | prompt | allow |
| 63 | `ruff -q check --fix src` | prompt | prompt |
| 64 | `ruff check --extend-select=F --fix src` | prompt | prompt |
| 65 | `ruff check --select --fix src` | prompt | prompt |
| 66 | `ruff check --output-format --fix src` | prompt | prompt |
| 67 | `ruff check --exclude src --fix` | prompt | prompt |
| 68 | `ruff check --stdin-filename src/a.py src` | prompt | allow |
| 69 | `ruff check src -n` | prompt | allow |
| 70 | `ruff rule --all` | prompt | allow |
| 71 | `ruff rule F401 F402` | prompt | allow |
| 72 | `ruff version --output-format json` | allow | allow |
| 73 | `ruff -h` | allow | allow |
| 74 | `ruff check -h` | allow | allow |
| 75 | `ruff format --check --config 'line-length=1' src` | prompt | allow |
| 76 | `ruff format --check --config 'format.quote-style="single"' src` | prompt | allow |
| 77 | `ruff format --diff --line-length 1 src` | allow | allow |
| 78 | `ruff format --check --preview src` | allow | allow |
| 79 | `ruff check --preview --unsafe-fixes src` | prompt | prompt |
| 80 | `ruff "check" "--fix" src` | prompt | prompt |
| 81 | `ruff ch""eck --f""ix src` | prompt | prompt |
| 82 | `ruff check --f\ix src` | prompt | prompt |
| 83 | `ruff check '--fix' src` | prompt | prompt |
| 84 | `ruff check --{fix,x} src` | prompt | prompt |
| 85 | `ruff check --fi* src` | prompt | allow |
| 86 | `ruff check --fix* src` | prompt | allow |
| 87 | `.venv/bin/ruff check --fix src` | prompt | prompt |
| 88 | `x/ruff check --fix src` | prompt | prompt |
| 89 | `/root/.local/bin/ruff check --fix src` | prompt | prompt |
| 90 | `/root/.local/bin/ruff check src` | prompt | prompt |
| 91 | `env ruff check --fix src` | prompt | prompt |
| 92 | `env env ruff check --fix src` | prompt | prompt |
| 93 | `/usr/bin/env ruff check --fix src` | prompt | prompt |
| 94 | `command ruff check --fix src` | prompt | prompt |
| 95 | `exec ruff check --fix src` | prompt | prompt |
| 96 | `exec -a ruff ruff check --fix src` | prompt | prompt |
| 97 | `nohup ruff check --fix src` | prompt | prompt |
| 98 | `timeout 5 ruff check --fix src` | prompt | prompt |
| 99 | `xargs ruff check --fix < src/a.py` | prompt | prompt |
| 100 | `find src -exec ruff check --fix {} ;` | prompt | prompt |
| 101 | `sudo ruff check --fix src` | prompt | prompt |
| 102 | `bash -c 'ruff check --fix src'` | deny | deny |
| 103 | `echo src \| sh` | prompt | prompt |
| 104 | `ruff check src \| sh` | prompt | prompt |
| 105 | `ruff check src && ruff check --fix src` | prompt | prompt |
| 106 | `ruff check src; ruff format src` | prompt | prompt |
| 107 | `ruff check src \|\| ruff format src` | prompt | prompt |
| 108 | `ruff check src > out.txt` | prompt | prompt |
| 109 | `ruff check src 2> out.txt` | prompt | prompt |
| 110 | `ruff check src \| tee out.txt` | prompt | prompt |
| 111 | `ruff check $(echo --fix) src` | prompt | prompt |
| 112 | ``ruff check `echo --fix` src`` | prompt | prompt |
| 113 | `ruff check --config "$HOME/x.toml" src` | deny | deny |
| 114 | `F=--fix ruff check src` | prompt | prompt |
| 115 | `RUFF_FIX=1 ruff check src` | prompt | prompt |
| 116 | `mypy src/a.py` | allow | allow |
| 117 | `mypy --strict src` | allow | allow |
| 118 | `python3 -m mypy src` | allow | allow |
| 119 | `mypy -p src` | allow | allow |
| 120 | `mypy --follow-imports=skip src` | allow | allow |
| 121 | `mypy --follow-imports skip src` | allow | allow |
| 122 | `mypy --config-file fixcfg.toml src` (planted in-root file) | allow | allow |
| 123 | `mypy --install-types src` | prompt | prompt |
| 124 | `mypy --install-types --non-interactive src` | prompt | prompt |
| 125 | `mypy --inst src` | prompt | allow |
| 126 | `mypy --install-type src` | prompt | allow |
| 127 | `mypy --python-executable src/a.py src` | prompt | allow |
| 128 | `mypy --python-executable=src/a.py src` | prompt | allow |
| 129 | `mypy --python-exec src/a.py src` | prompt | allow |
| 130 | `mypy --junit-xml out.xml src` | prompt | allow |
| 131 | `mypy --junit-xml=out.xml src` | prompt | allow |
| 132 | `mypy --html-report r src` | prompt | allow |
| 133 | `mypy --txt-report r src` | prompt | allow |
| 134 | `mypy --linecount-report r src` | prompt | allow |
| 135 | `mypy --cache-dir c src` | prompt | allow |
| 136 | `mypy --sqlite-cache src` | prompt | allow |
| 137 | `mypy -c 'import os'` | prompt | allow |
| 138 | `mypy --command 'import os'` | prompt | allow |
| 139 | `mypy @args.txt` | prompt | allow |
| 140 | `mypy src @args.txt` | prompt | allow |
| 141 | `mypy -p @args.txt` | prompt | allow |
| 142 | `mypy --package=@args.txt` | prompt | allow |
| 143 | `mypy --config-file 'x'` | prompt | allow |
| 144 | `mypy --config-file @args.txt src` | prompt | allow |
| 145 | `mypy --config-file cfgdir src` | prompt | allow |
| 146 | `mypy --config-file outlink.toml src` | prompt | prompt |
| 147 | `mypy --strict=1 src` | prompt | allow |
| 148 | `mypy --strict --junit-xml out.xml src` | prompt | allow |
| 149 | `mypy -- src` | prompt | allow |
| 150 | `mypy - src` | prompt | allow |
| 151 | `mypy --shadow-file src/a.py src/b.py src` | prompt | allow |
| 152 | `mypy --pretty --junit src` | prompt | allow |
| 153 | `mypy --no-incremental --cache-fine-grained src` | prompt | allow |
| 154 | `mypy --soft-error-limit -1 src` | prompt | allow |
| 155 | `mypy -m os` | allow | allow |
| 156 | `mypy -m --junit-xml src` | prompt | allow |
| 157 | `mypy --python-version 3.12 --plat linux src` | prompt | allow |
| 158 | `mypy --strict --i src` | prompt | allow |
| 159 | `mypy -V` | allow | allow |
| 160 | `mypy --version` | allow | allow |
| 161 | `pytest` | allow | allow |
| 162 | `pytest -q tests/test_x.py` | allow | allow |
| 163 | `pytest -qx tests` | allow | allow |
| 164 | `pytest -vv tests` | allow | allow |
| 165 | `pytest -rA tests` | allow | allow |
| 166 | `pytest -k test_a tests` | allow | allow |
| 167 | `pytest -m slow tests` | allow | allow |
| 168 | `pytest -n 4 tests` | allow | allow |
| 169 | `pytest --tb short tests` | allow | allow |
| 170 | `pytest --tb=short tests` | allow | allow |
| 171 | `pytest --co tests` | allow | allow |
| 172 | `pytest --lf tests` | allow | allow |
| 173 | `pytest tests/test_x.py::test_a` | allow | allow |
| 174 | `python3 -m pytest -q tests` | allow | allow |
| 175 | `python -m pytest tests` | allow | allow |
| 176 | `pytest --basetemp /tmp/bt tests` | prompt | prompt |
| 177 | `pytest --basetemp=bt tests` | prompt | allow |
| 178 | `pytest --junitxml out.xml tests` | prompt | allow |
| 179 | `pytest --junit-xml=out.xml tests` | prompt | allow |
| 180 | `pytest --junitx out.xml tests` | prompt | allow |
| 181 | `pytest --log-file l tests` | prompt | allow |
| 182 | `pytest --log-file=l tests` | prompt | allow |
| 183 | `pytest --debug tests/test_x.py` | prompt | allow |
| 184 | `pytest --debug=tests/test_x.py` | prompt | allow |
| 185 | `pytest --resultlog r tests` | prompt | allow |
| 186 | `pytest --pastebin all tests` | prompt | allow |
| 187 | `pytest -o cache_dir=/tmp/x tests` | prompt | prompt |
| 188 | `pytest --override-ini cache_dir=/tmp/x tests` | prompt | prompt |
| 189 | `pytest -p no:cacheprovider tests` | prompt | allow |
| 190 | `pytest -p evil tests` | prompt | allow |
| 191 | `pytest -pevil tests` | prompt | allow |
| 192 | `pytest -c fixcfg.toml tests` | prompt | allow |
| 193 | `pytest --rootdir /tmp tests` | prompt | prompt |
| 194 | `pytest --confcutdir / tests` | prompt | prompt |
| 195 | `pytest --pdb tests` | prompt | allow |
| 196 | `pytest --trace tests` | prompt | allow |
| 197 | `pytest -W ignore::antigravity.X tests` | prompt | allow |
| 198 | `pytest -Wignore::antigravity.X tests` | prompt | allow |
| 199 | `pytest --pythonwarnings ignore::antigravity.X tests` | prompt | allow |
| 200 | `pytest --pythonwarnings=ignore::antigravity.X tests` | prompt | allow |
| 201 | `pytest -qW ignore::antigravity.X tests` | prompt | allow |
| 202 | `pytest -xW ignore::antigravity.X tests` | prompt | allow |
| 203 | `pytest -kfoo tests` | prompt | allow |
| 204 | `pytest -k -W tests` | prompt | allow |
| 205 | `pytest -k @args.txt tests` | prompt | allow |
| 206 | `pytest -k=foo tests` | prompt | allow |
| 207 | `pytest -m=foo tests` | prompt | allow |
| 208 | `pytest -n=4 tests` | prompt | allow |
| 209 | `pytest @args.txt` | prompt | allow |
| 210 | `pytest tests @args.txt` | prompt | allow |
| 211 | `pytest -- tests` | prompt | allow |
| 212 | `pytest - tests` | prompt | allow |
| 213 | `pytest --cache-clear tests` | prompt | allow |
| 214 | `pytest --cache-show tests` | prompt | allow |
| 215 | `pytest -qp evil tests` | prompt | allow |
| 216 | `pytest -qo cache_dir=x tests` | prompt | allow |
| 217 | `pytest -rAp evil tests` (pytest reads `Ap` as `-r`'s value and `evil` as a path; no plugin loads, confirmed) | allow | allow |
| 218 | `pytest -rA -p evil tests` | prompt | allow |
| 219 | `pytest -vc fixcfg.toml tests` | prompt | allow |
| 220 | `pytest -sc fixcfg.toml tests` | prompt | allow |
| 221 | `pytest -lp evil tests` | prompt | allow |
| 222 | `pytest --import-mode=importlib tests` | prompt | allow |
| 223 | `pytest --fixtures tests` | prompt | allow |
| 224 | `pytest --setup-plan tests` | prompt | allow |
| 225 | `pytest --tb=@args.txt tests` | prompt | allow |
| 226 | `pytest --deselect=@args.txt tests` | prompt | allow |
| 227 | `pytest --durations=-1 tests` | prompt | allow |
| 228 | `pytest --maxfail 1 --junitxml o tests` | prompt | allow |
| 229 | `pytest -x --basetemp t tests` | prompt | allow |
| 230 | `pytest --strict-markers=1 tests` | prompt | allow |
| 231 | `pytest --co=x tests` | prompt | allow |
| 232 | `pytest --verbose --verbosity 99 tests` | prompt | allow |
| 233 | `pytest --sw-skip tests` | prompt | allow |
| 234 | `pytest --stepwise-skip tests` | prompt | allow |
| 235 | `pytest --last-failed-no-failures none tests` | prompt | allow |
| 236 | `pytest --lfnf none tests` | prompt | allow |
| 237 | `pytest -k 'foo or bar' tests` | allow | allow |
| 238 | `pytest -k "$X" tests` | deny | deny |
| 239 | `env pytest --basetemp t tests` | prompt | prompt |
| 240 | `command pytest --junitxml o tests` | prompt | prompt |
| 241 | `nohup pytest -p evil tests` | prompt | prompt |
| 242 | `xargs pytest -p evil < args.txt` | prompt | prompt |
| 243 | `find tests -exec pytest --junitxml o {} +` | prompt | prompt |
| 244 | `bash -c 'pytest -p evil'` | deny | deny |
| 245 | `pytest tests \| sh` | prompt | prompt |
| 246 | `x/pytest tests` (path to a planted program named `pytest`) | allow | allow |
| 247 | `.venv/bin/pytest --junitxml o tests` | prompt | allow |
| 248 | `.venv/bin/python -m pytest -p evil tests` | prompt | allow |
| 249 | `python3 -B -m pytest tests` | prompt | prompt |
| 250 | `python3 -m pytest -p evil tests` | prompt | allow |
| 251 | `python3 -m mypy --python-executable src/a.py src` | prompt | allow |
| 252 | `python3 -m ruff check --fix src` | prompt | prompt |
| 253 | `python3 -m pytest -W ignore::antigravity.X tests` | prompt | allow |
| 254 | `python3 analysis/report.py --self runner-write-allows` | allow | allow |
| 255 | `python3 analysis/report.py runner-write-allows` | prompt | allow |
| 256 | `python3 analysis/report.py --self --all` | allow | allow |
| 257 | `python3 analysis/report.py --all` | prompt | allow |
| 258 | `python3 analysis/report.py --self --rounds-md runner-write-allows` | allow | allow |
| 259 | `python3 analysis/report.py --self --orchestration runner-write-allows` | allow | allow |
| 260 | `python3 analysis/report.py --orchestration runner-write-allows` | prompt | allow |
| 261 | `python3 analysis/report.py --self --orchestration runner-write-allows --checkout a=/tmp` | prompt | prompt |
| 262 | `python3 analysis/report.py --self --arm-root /tmp runner-write-allows` | prompt | prompt |
| 263 | `python3 analysis/report.py --self --arm-root=/tmp runner-write-allows` | prompt | prompt |
| 264 | `python3 analysis/report.py runner-write-allows --self` | prompt | allow |
| 265 | `python3 analysis/report.py --self --self runner-write-allows` | prompt | allow |
| 266 | `python3 analysis/report.py --self --all --all` | prompt | allow |
| 267 | `python3 analysis/report.py --self --all runner-write-allows` | prompt | allow |
| 268 | `python3 analysis/report.py --self -- runner-write-allows` | prompt | allow |
| 269 | `python3 analysis/report.py --self @args.txt` | prompt | allow |
| 270 | `python3 analysis/report.py --self '../x'` | prompt | prompt |
| 271 | `python3 analysis/report.py --self 'a/b'` | prompt | allow |
| 272 | `python3 analysis/report.py --self x` | allow | allow |
| 273 | `python3 analysis/report.py --self -h` | prompt | allow |
| 274 | `python3 analysis/report.py` | prompt | allow |
| 275 | `python3 -B analysis/report.py --self runner-write-allows` | allow | allow |
| 276 | `python3 -B -B analysis/report.py --self runner-write-allows` | allow | allow |
| 277 | `python3 -I analysis/report.py --self runner-write-allows` | prompt | prompt |
| 278 | `python analysis/report.py --self runner-write-allows` | allow | allow |
| 279 | `./analysis/report.py --self runner-write-allows` | prompt | prompt |
| 280 | `python3 ./analysis/report.py --self runner-write-allows` | allow | allow |
| 281 | `python3 analysis/./report.py --self runner-write-allows` | allow | allow |
| 282 | `python3 analysis//report.py --self runner-write-allows` | allow | allow |
| 283 | `python3 ./analysis/../analysis/report.py --self runner-write-allows` | deny | deny |
| 284 | `python3 <root>/analysis/report.py --self runner-write-allows` | allow | allow |
| 285 | `python3 agentTooling/analysis/report.py runner-write-allows` (planted copy, standalone checkout) | allow | allow |
| 286 | `python3 agentTooling/analysis/report.py --self runner-write-allows` (same) | allow | allow |
| 287 | `python3 x/report.py --self runner-write-allows` | prompt | allow |
| 288 | `python3 dir/analysis/report.py --self runner-write-allows` | prompt | allow |
| 289 | `python3 linked/report.py --self runner-write-allows` | prompt | allow |
| 290 | `python3 alink/report.py --self runner-write-allows` | prompt | allow |
| 291 | `python3 agentTooling/alinkdir/report.py --self runner-write-allows` | prompt | allow |
| 292 | `python3 tmplink/report.py --self runner-write-allows` | prompt | prompt |
| 293 | `python3 analysis/report.py\  --self runner-write-allows` | prompt | prompt |
| 294 | `python3 analysis/repo""rt.py --self runner-write-allows` | allow | allow |
| 295 | `python3 analysis/report.p? --self runner-write-allows` | prompt | prompt |
| 296 | `python3 analysis/report.{py,x} --self runner-write-allows` | prompt | prompt |
| 297 | `python3 analysis/report.py --self runner-write-allows ; python3 x/report.py --self a` | deny | allow |
| 298 | `python3 -m analysis.report --self runner-write-allows` | prompt | prompt |
| 299 | `env python3 analysis/report.py --self runner-write-allows` | prompt | prompt |
| 300 | `.venv/bin/python analysis/report.py --self runner-write-allows` | allow | allow |
| 301 | `x/python3 analysis/report.py --self runner-write-allows` (planted interpreter path) | allow | allow |
| 302 | `[cwd=src] python3 <root>/analysis/report.py --self runner-write-allows` | allow | allow |
| 303 | `[cwd=analysis] python3 report.py --self runner-write-allows` | prompt | prompt |
| 304 | `[cwd=analysis] python3 ./report.py --self runner-write-allows` | allow | allow |
| 305 | `[cwd=alink] python3 ./report.py --self runner-write-allows` (resolves to the real script) | allow | allow |
| 306 | `python3 analysis/capture_planning.py --self --list-sessions` | allow | allow |
| 307 | `python3 analysis/capture_planning.py --self --list-subagents --unclaimed` | allow | allow |
| 308 | `python3 analysis/capture_planning.py --self runner-write-allows` | prompt | prompt |
| 309 | `python3 analysis/capture_planning.py --self --list-sessions --force` | prompt | prompt |
| 310 | `python3 x/capture_planning.py --self --list-sessions` | prompt | allow |
| 311 | `python3 agentTooling/analysis/capture_planning.py --list-sessions` (not planted) | prompt | prompt |
| 312 | `python3 analysis/manifest.py --self runner-write-allows get branches` | allow | allow |
| 313 | `python3 analysis/manifest.py --self runner-write-allows set-window-to x` | prompt | prompt |
| 314 | `python3 x/manifest.py --self runner-write-allows get branches` | prompt | allow |
| 315 | `python3 linked/manifest.py --self runner-write-allows get branches` | prompt | allow |
| 316 | `python3 alink/manifest.py --self runner-write-allows get branches` | prompt | allow |
| 317 | `self/gate.sh` | allow | allow |
| 318 | `./self/gate.sh` | allow | allow |
| 319 | `self/gate.sh blocking` | allow | allow |
| 320 | `self/gate.sh a b` | prompt | prompt |
| 321 | `linked/gate.sh` | prompt | allow |
| 322 | `x/gate.sh` (planted) | allow | allow |
| 323 | `glink/gate.sh` | prompt | allow |
| 324 | `./check-plans.sh --self runner-write-allows` | allow | allow |
| 325 | `linked/check-plans.sh --self runner-write-allows` | prompt | allow |
| 326 | `x/check-plans.sh --self runner-write-allows` (planted) | allow | allow |
| 327 | `check-plans.sh --self runner-write-allows` | prompt | prompt |
| 328 | `<root>/self/gate.sh` | allow | allow |
| 329 | `[cwd=self] ./gate.sh` | allow | allow |
| 330 | `bash self/gate.sh` | prompt | prompt |
| 331 | `bash -n self/gate.sh` | allow | allow |
| 332 | `python3 -m py_compile analysis/report.py` | allow | allow |
| 333 | `python3 -B -m py_compile analysis/report.py` | allow | allow |
| 334 | `[cwd=g] ruff check *` (planted `--add-noqa` file; rewrites `a.py`, confirmed) | allow | allow |
| 335 | `[cwd=g] ruff check *.py` | allow | allow |
| 336 | `[cwd=g] mypy *` | allow | allow |
| 337 | `[cwd=g] pytest *` | allow | allow |
| 338 | `[cwd=g] pytest -k x *` | allow | allow |
| 339 | `ruff check g/*` | allow | allow |
| 340 | `ruff check --con{fig,x} 'fix=true' src` | prompt | allow |
| 341 | `ruff check --config{,} fixcfg.toml src` | prompt | allow |
| 342 | `ruff check {--fix,src}` | prompt | prompt |
| 343 | `ruff check --select{,=E} src` | prompt | allow |
| 344 | `mypy {--inst,src}` | prompt | allow |
| 345 | `pytest {-p,evil} tests` | prompt | allow |
| 346 | `ruff check --config 'fixcfg.toml' src` | allow | allow |
| 347 | `ruff check --config "fix = true" src` | prompt | allow |
| 348 | `ruff check --config=' fixcfg.toml' src` | prompt | allow |
| 349 | `ruff check --config 'fixcfg.toml ' src` | prompt | allow |
| 350 | `ruff check --config fixcfg.toml\  src` | prompt | allow |
| 351 | `pytest -k 'a' -m "b" --tb=short --durations 3 --maxfail=2 --color=yes -n 2 -rA -qq tests` | allow | allow |
| 352 | `mypy --strict --config-file fixcfg.toml --follow-imports=silent --python-version 3.12 -m os` | allow | allow |
| 353 | `ruff format --check --diff --config fixcfg.toml src` | allow | allow |
| 354 | `ruff format --check --line-length=1 src` | allow | allow |
| 355 | `ruff check --target-version py312 --per-file-ignores 'a.py:E1' src` | allow | allow |
| 356 | `ruff check --exclude=src src` | allow | allow |
| 357 | `ruff rule` | prompt | allow |
| 358 | `ruff rule F401 --output-format json` | allow | allow |
| 359 | `ruff version extra` | prompt | allow |
| 360 | `ruff check` | allow | allow |
| 361 | `ruff --isolated check src` | allow | allow |
| 362 | `ruff --isolated format src` (rewrites; base approved it) | prompt | allow |
| 363 | `ruff -q -h` | allow | allow |
| 364 | `ruff --no-cache` | prompt | allow |
| 365 | `pytest --help` | allow | allow |
| 366 | `pytest -h --junitxml o` | prompt | allow |
| 367 | `mypy -h --junit-xml o` | prompt | allow |
| 368 | `mypy` | allow | allow |
| 369 | `python3 -m mypy` | allow | allow |
| 370 | `python3 -m ruff` | prompt | allow |
| 371 | `python3 -m pytest` | allow | allow |

### Malformed payloads (`malformed.py`)

These commands were each run under nine payload variants: `ruff check --fix src`,
`ruff check src`, `python3 analysis/report.py --self runner-write-allows`,
`python3 x/report.py --self runner-write-allows`, `pytest -p evil tests` and
`mypy --python-executable src/a.py src`.

| variant | head | base |
|---|---|---|
| no `cwd` | prompt (all six) | prompt (all six) |
| `cwd: "/tmp"` | prompt (all six) | prompt (all six) |
| `cwd: "src"` (relative) | prompt (all six) | prompt (all six) |
| `cwd: null` | prompt (all six) | prompt (all six) |
| `command` as a list | prompt (all six) | prompt (all six) |
| no `tool_input` | prompt (all six) | prompt (all six) |
| `tool_name: "Read"` | prompt (all six) | prompt (all six) |
| `agent_id: "a1"`, `session_id` set | allow `ruff check src` and the pinned `report.py`; prompt the other four | allow all except `ruff check --fix src` |
| no `CLAUDE_PROJECT_DIR` | prompt (all six) | prompt (all six) |
| non-JSON stdin / empty stdin | prompt | prompt |

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | `ruff check --config fixcfg.toml src` (also `=`, `./`, an in-root symlink to it) with a planted in-root `fixcfg.toml` holding `fix = true`; `mypy --config-file fixcfg.toml src`, where an in-root INI could name `junit_xml`, `python_executable` or `plugins` | allow — ruff rewrote `src/a.py` (confirmed on a scratch tree) | allow | `attack.py cases1.txt` rows 44–47, `cases2.txt` row 122, on both copies; `real.sh` |
| non-blocking | `[cwd=g] ruff check *` where `g/` holds a planted file named `--add-noqa` (likewise `mypy *` and `pytest *` with `--junit-xml=o.xml` or `-p`) | allow — bash expands the glob to `--add-noqa`, and ruff appended `# noqa` to `a.py` (confirmed) | allow | `attack.py cases4.txt` rows 334–338 on both copies; `globreal.sh` |
| non-blocking | `x/pytest tests`, `x/python3 analysis/report.py --self <slug>` — a planted program carrying a runner basename | allow — runs the planted program | allow | `attack.py` rows 246, 301 on both copies |
| non-blocking | `x/gate.sh`, `x/check-plans.sh --self <slug>`, `python3 agentTooling/analysis/report.py <slug>` in the standalone checkout — planted files at a basename or at the other pinned directory | allow — runs the planted file | allow | `attack.py` rows 285–286, 322, 326 on both copies |

## Non-blocking findings

Every row below needs a file planted in the root first. The hook README calls this an
accepted limit ("A planted file needs a prior write"), and base's result is the same for
every one. None of them is a command whose own words write against the tree as committed.

1. **Planted settings file passed by `--config`/`--config-file`.**
   - Input: `ruff check --config fixcfg.toml src`, where `fixcfg.toml` is an in-root file
     holding `fix = true`, and `mypy --config-file <in-root ini>`.
   - Results: allow on head, allow on base.
   - Follow-up: `runner_config_file_ok` should accept only the settings files the tool
     would discover on its own: `pyproject.toml`, `ruff.toml` or `.ruff.toml` for ruff;
     `mypy.ini`, `.mypy.ini`, `pyproject.toml` or `setup.cfg` for mypy. An arbitrary
     in-root file would then prompt. The README already records this as an accepted limit
     (`hooks/README.md` → "The runners' allowlists").
2. **An unquoted glob in a runner positional can expand to a flag.**
   - Input: `ruff check *` in a directory holding a file named `--add-noqa`.
   - Results: allow on head, allow on base. It rewrote `a.py`.
   - Follow-up: `runner_words` reads `*` as a positional, but bash hands ruff the
     filename as a flag. A runner positional holding an unquoted glob character
     (`*`, `?`, `[`) should prompt, or the glob should be expanded against the tree and
     every result judged as a word. This is the runner analogue of the README's
     "unquoted glob that expands to `-delete`".
3. **Planted program carrying a runner or interpreter basename.**
   - Input: `x/pytest tests`, `x/python3 analysis/report.py …`.
   - Results: allow on head, allow on base.
   - Follow-up: a runner or interpreter spelled as an in-root path that is neither under
     `.venv/bin/`/`venv/bin/` nor `node_modules/.bin/` should prompt. This is the
     README's "look-alike `python` symlink" accepted limit.
4. **Planted `x/gate.sh`, `x/check-plans.sh`, and a planted `agentTooling/analysis/` in the
   standalone checkout (or `analysis/` in a consuming repo).**
   - Results: allow on head, allow on base. The README documents both as staying approved.
   - Follow-up: pin `gate.sh` to `<root>/self/gate.sh` and `<root>/plans/gate.sh`, and
     `check-plans.sh` to `<root>/check-plans.sh` and `<root>/agentTooling/check-plans.sh`,
     as `pinned_entry_dir` now does for the Python scripts. Choose the pinned Python
     directory by whether the root is the standalone checkout (`is_standalone_checkout`),
     not by accepting both.

Observations that are not findings:

- Rows 11 and 305. The hook resolves `cwd` before pinning, so `[cwd=alink] ./report.py`
  is the real script. `--config pyproject.toml` prompts only because the copy has no
  `pyproject.toml`.
- `pinned_entry_dir` requires `realpath(path) == path`. If `CLAUDE_PROJECT_DIR` is spelled
  through a symlink, the real scripts would prompt. That is a usability cost, not an allow.
- `report.py --self <slug>|--all|--orchestration <slug>` writes its own report under the
  root. This is the harness entry point that `CONVENTIONS.md` lists as approved silently,
  and the diff narrows it (`--arm-root`, `--checkout`, and no-`--self` from the checkout's
  own script now prompt).

## Blocking findings

None.
