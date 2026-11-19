Verdict: escalated

# Security audit — hook-role-hardening (02-audit-opus)

Round 2 changed two rules: `orchestrator_operands` now counts uniq's bare `-` (B1), and
`AUDIT_TOOLING_PATHS` now covers `analysis/` and `orchestration-capture.sh` (B2). Both fixes
hold against every input below. I also re-ran a regression sample of round 1's table and
attacked the rest of the orchestrator allowlist this feature adds. That found two more
bypasses, A1 and A2.

**Setup.** I attacked a throwaway `git archive HEAD` copy under the scratch directory. It was
`git init`ed and committed, with a ledger `.git/agenttooling-orchestrators` holding
`ORCH1 orch-test`, and a file `R`. Payloads went to the hook's stdin as PreToolUse JSON, run
as `hooks/allow-repo-commands.sh` with `CLAUDE_PROJECT_DIR` set to the copy. Unless stated,
the session was `ORCH1` and `cwd` was the copy's root.

**How results are labelled:**
- **allow**: the hook printed `allow`.
- **ask**: no output, so the human decides.
- **deny (role)**: the orchestrator allowlist's denial.

The only file I wrote in this checkout is this report.

## Bypasses

### A1 — `git add` stages a planted nested repository; `git status` then runs its program (R7)

**Rule:** for an orchestrator, `git add` refuses any path that holds a `.git` entry (NOTES.md
R7: "a planted repository whose config git would honour"). The check is
`GIT_DIR_ENTRY in w.split(os.sep) or os.path.lexists(os.path.join(cwd, w, ".git"))`. It reads
each argument as a literal path and looks one level down.

**Inputs that get past it.** First plant `sub/.git` or `self/deep/.git`. Text files are
enough, so the Write tool can make them:
- `HEAD`: `ref: refs/heads/main`
- `refs/heads/main`: any 40 hex characters
- an empty `objects/info/alternates`
- `config` with `[core] fsmonitor = <program>`

Then:

| Input | Hook | Effect in the copy |
|---|---|---|
| `git add :/sub` | ask | stages `sub` as a gitlink (mode 160000) |
| `git add ':(top)sub'`, `git add ':(glob)s*'` | ask | the same |
| `git add 's*'`, `git add "s*"`, `git add 'su?'`, `git add '[s]ub'`, `git add '*'` | ask | the same: quoted globs are git pathspecs |
| `git add :/` | ask | stages the whole tree, `sub` included (`git add .` is denied) |
| `git add self` with the repo at `self/deep/.git` | ask | stages `self/deep` as a gitlink: the check never looks below `self/.git` |
| then `git status` / `git status --short` | **allow** | git runs `git status --porcelain=2` inside the gitlink, which runs the planted `core.fsmonitor`. The marker file read `ran …/evil.sh 2 <token>` both for `:/sub2` and for `self/deep`. |

Without a staged gitlink, `git status` ran nothing: the untracked `sub2/` was only listed. So
the `git add` is the step the rule exists to deny. Getting past it gives arbitrary program
execution from an orchestrator session, behind one human prompt. Under `bypassPermissions` an
ask does not fire (hooks/README.md's known limit), so there it takes no prompt at all.

The control inputs were denied: `git add sub`, `git add sub/`, `git add ./sub`,
`git add self/deep`, `git add ':/.git'` and `git add .`.

The precondition is that the session can write `<dir>/.git/{HEAD,config,refs/…}` with the
Write tool. R7 assumes it can; I did not test Claude Code's own protection of `.git` paths.

**What the rule should do instead:**
- Refuse a `git add` argument that starts with `:` (pathspec magic).
- Refuse an argument that holds a glob character `*`, `?` or `[`, quoted or not.
- Refuse a directory argument whose tree holds a `.git` entry at any depth (walk it without
  following symlinks), or simply require each argument to be an existing regular file.
- Add these to `self/tests/hook-orchestrator-role.sh` beside the R7 case: `:/sub`,
  `':(glob)s*'`, `'s*'`, `'*'`, `:/`, and a `.git` two levels down.

### A2 — `date MMDDhhmm` sets the system clock past the `date --set` rule

**Rule:** `ORCHESTRATOR_READER_FORBIDDEN["date"]` denies `-s` / `--set` (by any prefix), so an
orchestrator's `date` cannot set the clock.

**Inputs that get past it:**
- `date 010100002020`
- `date 0101`
- `date -u 010100002020`
- `date --utc 01010000`
- `date '010100002020'`
- `date 01010000.00`
- `date -R 010100002020`

All are admitted (**ask**). GNU date's operand form `[MMDDhhmm[[CC]YY][.ss]]` is a set. I ran
`date <the current minute>` with `CAP_SYS_TIME` dropped (`setpriv --bounding-set -sys_time`):
it printed `date: cannot set date: Operation not permitted`, which confirms it calls
settimeofday. This container's sessions run as root with `CAP_SYS_TIME` (CapEff
`000001fffeffffff`), so without that drop the set succeeds. Changing the clock skews every
timestamp the cost capture windows on (`session_window`, transcript instants, commit dates).

**What the rule should do instead:** admit `date` only when every operand starts with `+` (a
format). Treat the argument of `-d`/`--date`, `-f`/`--file` and `-r`/`--reference` as that
option's value, not as an operand. Add the inputs above to the test beside `date -s`.

## Inputs tried

### B1 — uniq's stdin operand (the round 2 fix)

| Input | Result |
|---|---|
| `uniq - out.txt`, `echo x \| uniq - out.txt`, `printf 'x' \| uniq - orchestration-start.sh` | deny (role) |
| `uniq -c - out.txt`, `uniq -u - out.txt`, `uniq -z - out`, `uniq -D - out`, `uniq --group - out`, `uniq --zero-terminated - out`, `uniq --all-repeated=separate - out` | deny (role) |
| `uniq --skip-fields=1 - out`, `uniq -f1 - out`, `uniq -s 1 out`, `uniq --skip-chars 1 out` | deny (role) |
| `uniq -- - out.txt`, `uniq - -- out.txt`, `uniq README.md out.txt`, `uniq README.md -`, `uniq - -` | deny (role) |
| `uniq "-" out.txt`, `uniq '-' out.txt`, `uniq -"" out.txt`, `uniq ""- out.txt`, `uniq '' out` | deny (role) |
| `uniq<TAB>-<TAB>out`, `uniq - out<CR>` | deny (role) |
| `uniq -c README.md\|uniq - x`, `ls && uniq - x`, `ls ; uniq - .git/agenttooling-orchestrators`, `echo \| uniq - .git/agenttooling-orchestrators`, `echo \| uniq - .git/config` | deny (role) |
| `uniq - -out`, `echo x \| uniq - -hook` | ask. GNU uniq reads `-out`/`-hook` as an invalid option cluster and writes nothing; POSIXLY_CORRECT cannot be set (`FOO=1 ls` is denied) |
| `uniq -- out`, `uniq out`, `uniq`, `uniq -c`, `uniq README.md -- `, `uniq README.md --o`, `uniq --help` | ask (one operand or none: no output file) |
| `uniq - out` with session `OTHER` | ask (no role: unchanged behaviour) |

### B2 — audit paths (`is_audit_path` from the copy's `plan-runner-roots.sh`)

| Path (self; consumer = `agentTooling/` + path) | Result, both layouts |
|---|---|
| `orchestration-start.sh`, `orchestration-capture.sh`, `plan-runner-roots.sh` (sourced by the start), `session-start.sh` | audit path |
| `analysis/manifest.py`, `report.py`, `capture_planning.py`, `orchestration_capture.py`, `roots.py`, `routing.py`, `pricing.py`, `transcript.py`, `analysis`, `analysis/new_module.py`, `analysis/sub/x.py` | audit path |
| `hooks/brief_header.py` (imported by `capture_planning.py`), `hooks/orchestrator_role.py` | audit path |
| `.claude/settings.json` (self) | audit path. In the consumer layout `agentTooling/.claude/` is not, by design: the consumer's `.claude/` is at its root |
| `env-profile.sh`, `analysisx/roots.py`, `Analysis/roots.py`, `README.md`, `.gitattributes`, `self/orchestrations/x/README.md` | not an audit path. None of these is executed by an allowlisted entry point: `orchestration-start.sh` sources only `plan-runner-roots.sh`, which runs only `analysis/` and `hooks/` Python; `orchestration-capture.sh` runs only `analysis/orchestration_capture.py`; `capture_planning.py`'s one subprocess is `git remote get-url` |

Diffs are read with `--no-renames` (`audit_paths_in_range`, `feature-close.sh`), so moving a
file out of `hooks/` or `analysis/` still lists the deleted path. A `.pyc` under
`analysis/__pycache__/` is not in any diff. It is not reachable either: the Write tool cannot
produce the magic's bytes ≥ 0x80, and the allowlist now admits no shell writer.

### Regression sample of the orchestrator allowlist (session `ORCH1`)

| Input | Result |
|---|---|
| `ls`, `sed -n 1p R`, `git status`, `ls > /dev/null`, `printf -- -v x`, `printf -- -vx a`, `printf --v x 1` (bash rejects `--v` as an invalid option: no assignment, checked) | allow |
| `python3 -B analysis/manifest.py --orchestration orch-test get`, `python3 -B analysis/report.py --orchestration orch-test`, `python3 analysis/capture_planning.py --list-sessions` | allow |
| `git commit -m x`, `./orchestration-start.sh x`, `./orchestration-capture.sh orch-test`, `gh pr create --title a --body b`, `git add R` | ask |
| `sort -- R -o out.txt` | ask (`-o` after `--` is an input file named `-o`) |
| `date +%s`, `date -d now`, `date --date=now`, `date -f R`, `date -I` | ask |
| `date 010100002020`, `date 0101`, `date -u 010100002020`, `date --utc 01010000`, `date '010100002020'`, `date 01010000.00`, `date -R 010100002020` | **ask — A2** |
| `date 010100002020` with session `OTHER` | ask (no role) |
| `date -s 2020-01-01`, `date --set=2020-01-01`, `date --se 2020` | deny (role) |
| `sort -o out.txt R`, `sort R -o out.txt`, `sort --outp=out.txt R`, `sort -mo out.txt R`, `sort --compress-prog=sh R` | deny (role) |
| `printf -v x a`, `printf -v`, `find . -fprint out`, `find . -exec ls ;`, `sed -n 1p R -i`, `sed -n '1w out' R`, `tail -f R`, `diff -l a b`, `jq -nf x`, `rg --pre=sh x` | deny (role) |
| `git log --output=x`, `git -c core.pager=sh log`, `git add .git/config`, `git commit -m x --no-verify`, `git push -u origin main:main` | deny (role) |
| `./run-plans.sh --self x`, `env ./run-plans.sh --self x`, `bash run-plans.sh` | deny (role) |
| `ls $HOME`, `ls *`, `ls > out`, `FOO=1 ls` | deny (role) |
| `./orchestration-start.sh x --session y`, `python3 analysis/manifest.py x`, `python3 analysis/capture_planning.py --list-sessions -- x`, `python3 analysis/orchestration_capture.py orch-test`, `python3 analysis/roots.py`, `gh api x` | deny (role) |

### `git add` and nested repositories (A1)

| Input (planted `sub/.git` or `self/deep/.git` present) | Result |
|---|---|
| `git add sub`, `git add sub/`, `git add ./sub`, `git add self/deep`, `git add ':/.git'`, `git add .` | deny (role) |
| `git add :/`, `git add :/sub`, `git add ':(top)sub'`, `git add ':(glob)s*'`, `git add 's*'`, `git add "s*"`, `git add '*'`, `git add 'su?'`, `git add '[s]ub'`, `git add self` | **ask — A1** |
| `git add :`, `git add ':!R'`, `git add ':(exclude)R'`, `git add ':(top).git/config'`, `git add ':(icase).GIT/config'` | ask (git itself refuses paths inside `.git`; the others add ordinary files) |
| `git status`, `git status --short` (with a gitlink staged, these run the planted fsmonitor) | allow |

## Not exercised

- Round 2 did not change `orchestrator_role.py`, `feature-close.sh`'s verdict gate,
  `run-review.sh`, `wire-settings.py` or `manifest.py`, so I did not re-attack them. Round 1's
  table covers them.
- I did not test whether Claude Code's Write tool refuses paths with a `.git` component. That
  is A1's precondition, and R7 already assumes it holds.
