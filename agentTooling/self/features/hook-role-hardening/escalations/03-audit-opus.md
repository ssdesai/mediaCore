Verdict: escalated

# Security audit — hook-role-hardening (03-audit-opus)

Round 3 changed two rules in `hooks/allow-repo-commands.sh`, both only for orchestrator
sessions:

- **`git add`** now takes only existing regular files, named plainly (fixes A1).
- **`date`** now takes only `+FORMAT` operands (fixes A2).

`hooks/README.md`'s table changed to match; nothing else under the plan's file list changed
since round 2. I attacked both rules. The `git add` rule held against every input I tried.
The `date` rule has one bypass, **C1**.

**Setup.** I attacked a throwaway `git archive HEAD` copy under the scratch directory,
`git init`ed and committed. It had:

- a ledger `.git/agenttooling-orchestrators` holding `ORCH1 orch-test`;
- a file `R`, and a symlink `lnk → R`;
- a regular file literally named `s\ub`;
- a planted nested repository `sub/.git`, made of text files: `HEAD`, `refs/heads/main`,
  an empty `objects/info/alternates`, and a `config` with `core.fsmonitor = <copy>/evil.sh`.
  `evil.sh` appends to a `marker` file when it runs.

I sent PreToolUse JSON to the copy's `hooks/allow-repo-commands.sh` on stdin, with
`CLAUDE_PROJECT_DIR` and `cwd` set to the copy and session `ORCH1`, unless a row says
otherwise.

**How results are labelled:**
- **allow**: the hook printed `allow`.
- **ask**: no output, so the human decides.
- **deny (role)**: the orchestrator allowlist's denial.

The only file I wrote in this checkout is this report.

## Bypass

### C1 — `date -Id MMDDhhmm…` sets the clock past the round 3 `date` rule

**Rule:** an orchestrator's `date` is admitted only when every operand is a `+FORMAT`. The
values of `-d`/`--date`, `-f`/`--file` and `-r`/`--reference` are skipped as those options'
values (`orchestrator_date_reads_only`).

**Inputs that get past it** (all **ask**; the same inputs are denied without the `I`):

- `date -Id 010100002020`
- `date -uId 010100002020`
- `date -uuId 010100002020`

**Cause.** The short-cluster loop scans for the first letter in `dfr`. When it finds `d` as
the last letter of the cluster, it sets `takes_value`, so the next word (the clock operand)
is skipped and never checked. But GNU date's short options are `d:f:I::r:Rs:u`: `-I` takes
an **optional attached** argument. So in `-Id`, the `d` is `-I`'s argument (`date`, by
abbreviation), not the `-d` option. The next word is therefore an operand, and GNU date's
`MMDDhhmm[[CC]YY][.ss]` operand sets the clock.

**Reproduced** with GNU coreutils 9.4 and `CAP_SYS_TIME` dropped
(`setpriv --bounding-set -sys_time --inh-caps -sys_time`):

- `date -Id 010100002020` printed `date: cannot set date: Operation not permitted` and then
  `2020-01-01`. That shows it called settimeofday.
- `date -uId 010100002020` printed the same.

These sessions run as root with `CAP_SYS_TIME`, so without the drop the set succeeds. That
is A2's impact again: every timestamp the cost capture windows on is skewed.

**What the rule should do instead:**
- In the short-cluster scan, stop at `I`. Everything after it in the same word is `-I`'s
  argument, so set `takes_value = False` and `break`, before looking for `d`/`f`/`r`. This
  generalises to any option with an optional attached argument; `I` is GNU date's only one.
- Add `date -Id 010100002020` and `date -uId 010100002020` to
  `self/tests/hook-orchestrator-role.sh` beside the A2 cases, expecting deny (role).
- Keep `date -Id` and `date -uId +%s` there expecting admission. (GNU rejects the latter as
  "multiple output formats", which is harmless.)

## Inputs tried

### `date` (round 3 rule)

| Input | Result |
|---|---|
| `date -Id 010100002020`, `date -uId 010100002020`, `date -uuId 010100002020` | **ask — C1** (sets the clock, verified) |
| `date -Id 010100002020` with session `OTHER` | ask (no role: unchanged behaviour) |
| `date +%s`, `date -u +%s`, `date -d now`, `date --date now`, `date -f R`, `date -r R`, `date --reference R`, `date -Id`, `date -Id +%s`, `date -uId +%s` | ask (reads only; GNU rejects the two `-Id +FMT` forms as "multiple output formats") |
| `date -- -s` | ask. GNU reads `-s` after `--` as an operand. It is not a valid date, so nothing is set |
| `date -Ihd 010100002020`, `date -RId 010100002020` | ask. GNU refuses both before setting anything (`invalid argument 'hd' for '--iso-8601'`; `multiple output formats specified`), checked |
| `date 010100002020`, `date -- 010100002020`, `date -d now 010100002020`, `date --dat now 010100002020`, `date --d now 010100002020`, `date --re R 010100002020`, `date --rfc-3339 010100002020` | deny (role) |
| `date -I 010100002020`, `date -I d 010100002020`, `date -Idate 010100002020`, `date --iso-8601=d 010100002020`, `date -Id -- 010100002020` | deny (role) |
| `date -s 2020-01-01`, `date -us 2020`, `date --se 2020`, `date -Is 010100002020` | deny (role) |

### `git add` (round 3 rule; planted `sub/.git` present)

| Input | Result |
|---|---|
| `git add R`, `git add ./R`, `git add <absolute path of R>` | ask (a regular file) |
| `git add 's\ub'` (a regular file of that name exists) | ask, **not a bypass**. `\` is a git glob special, but git 2.43 matched the pathspec literally: it staged only the file `s\ub` (mode 100644), no gitlink, and `git status` ran nothing (no marker) |
| `git add sub`, `git add R/`, `git add R sub`, `git add R<TAB>sub`, `git add -- R`, `git add` | deny (role) |
| `git add :/sub`, `git add ':(literal)R'`, `git add 's*'`, `git add 'su?'`, `git add '[s]ub'`, `git add '\s\u\b'`, `git add "s\\ub"`, `git add s\\ub` | deny (role) |
| `git add sub/.git/config`, `git add sub/.git/HEAD`, `git add nonexistent`, `git add lnk` (a symlink) | deny (role) |
| `git add sub` with session `OTHER` | ask (no role) |

The control, run directly against git in the copy, not through the hook: `git add 's*'` stages
`sub` as a gitlink (mode 160000), and a `git status --short` afterwards ran the planted
`evil.sh` (marker: `ran …/evil.sh 2 <token>`). So A1's chain is live in git 2.43. Round 3's
`git add` check is what stops it. `git add sub/x` (a file inside the nested repo) exited 0 and
staged nothing.

### Role controls (session `ORCH1`)

| Input | Result |
|---|---|
| `ls` | allow |
| `./run-plans.sh --self x`, `ls $HOME` | deny (role) |

## Not exercised

- Round 3 changed no other rule, so I did not re-attack the rest of the allowlist,
  `orchestrator_role.py`, `feature-close.sh`, `run-review.sh`, `wire-settings.py` or
  `manifest.py`. Rounds 1 and 2's tables cover them.
- A file swapped between the hook's `isfile` check and the human's approval of the ask. Doing
  that needs a concurrent write, which the allowlist does not admit.
- Whether the Write tool can create `<dir>/.git/*`. That is A1's precondition, which R7
  already assumes.
