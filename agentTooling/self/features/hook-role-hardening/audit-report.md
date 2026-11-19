Verdict: clean

# Security audit — hook-role-hardening (04-audit-opus)

Round 4 (`440c0c9`) changed one rule, in `hooks/allow-repo-commands.sh`, and it applies only
to orchestrator sessions:

- **`date`** (`orchestrator_date_reads_only`): when the short-cluster scan reaches `I`, it
  now stops. Everything after `I` in that word is `-I`'s optional attached argument, so none
  of it can be an option that consumes the next word. This is the fix for round 3's C1
  (`date -Id 010100002020` set the clock). The new constant is
  `ORCHESTRATOR_DATE_OPTIONAL_ATTACHED = "I"`.

Since round 3's audit (`8bdabcf..HEAD`), nothing else changed in the plan's file list except
`self/tests/hook-orchestrator-role.sh`, which gained the H24 cases. I attacked the changed
rule and found no bypass.

**Setup.** I attacked a throwaway `git archive HEAD` copy under the scratch directory,
`git init`ed and committed, with:

- a ledger `.git/agenttooling-orchestrators` holding `ORCH1 orch-test`;
- a regular file `R`.

I sent PreToolUse JSON to the copy's `hooks/allow-repo-commands.sh` (run with `python3`) on
stdin, with `CLAUDE_PROJECT_DIR` and `cwd` set to the copy and session `ORCH1`, unless a row
says otherwise.

Every input the hook passed with no output (**ask**) I then ran through the real GNU date
(coreutils 9.4) with `CAP_SYS_TIME` dropped (`setpriv --bounding-set -sys_time --inh-caps
-sys_time`). A run that tries to set the clock prints `cannot set date`; the control,
`date 010100002020`, printed it.

**How results are labelled:**
- **allow**: the hook printed `allow`.
- **ask**: no output, so the human decides.
- **deny (role)**: the orchestrator allowlist's denial ("this session is the orchestrator of
  `orch-test` …").

The only file I wrote in this checkout is this report.

## Inputs tried

### Controls

| Input | Result |
|---|---|
| `ls` | allow |
| `date +%s`, `date -Id`, `date -I -d now` | ask (read only; real date printed the date) |
| `date 010100002020` | deny (role); real date: `cannot set date` (control) |
| `date -Id 010100002020`, `date 010100002020` with session `OTHER` | ask (no role: unchanged behaviour) |

### The round 4 rule: `-I` and its attached argument

| Input | Result |
|---|---|
| `date -Id 010100002020`, `date -uId 010100002020`, `date -uuId 010100002020`, `date -uuuuId 010100002020` | deny (role). C1 is closed |
| `date -I 010100002020`, `date -IId …`, `date -iId …`, `date -Ida …`, `date -uIdate …`, `date -Id+%s …`, `date -I -- …` | deny (role) |
| `date -dI …`, `date -fI …`, `date -rI …`, `date -rId …`, `date -dId …` (`I` attached as the value of `-d`/`-f`/`-r`) | deny (role) |
| `date -uI …`, `date -RI …`, `date -IR …`, `date -Ir …`, `date -Ird …`, `date -RId …` | deny (role) |
| `date -Isd …`, `date -Is`, `date -I s` | deny (role). The `-s` forbidden-letter check fires; this denies more than it needs to, but is not a bypass |
| `date -Id -d now 010100002020`, `date -Id 010100002020 -d now`, `date -Id -f - 010100002020` | deny (role) |
| `date -Id<TAB>010100002020`, `date -Id  010100002020` (two spaces) | deny (role) |
| `date -I"d" …`, `date "-Id" …`, `date -I\d …`, `date $'-Id' …`, `date -I{d,} …`, `date -Id … # comment` | deny (role) |
| `date -Id -d 010100002020`, `date -Id --date 010100002020` | ask. **Not a bypass**: in real date the operand is `-d`'s value, `invalid date '010100002020'`, nothing set |

### Long-option prefixes the rule takes as value-taking

| Input | Result |
|---|---|
| `date --d 010100002020`, `date --r …`, `date --re …` | ask. **Not a bypass**: real date refuses `option '--d' is ambiguous` (likewise `--r` and `--re`) before setting anything |
| `date --f …`, `date --fi …`, `date --ref …` | ask. **Not a bypass**: real date reads the word as a file name (`No such file or directory`) |
| `date --da 010100002020` | ask. **Not a bypass**: real date treats it as `--date`'s value (`invalid date`) |
| `date --rfc-3339 …`, `date --rfc-3339=date …`, `date --iso-8601 …` | deny (role) |
| `date --s 2020-01-01`, `date --set=2020-01-01`, `date --se=2020` | deny (role) |
| `date -- 010100002020`, `date --- …`, `date - …` | deny (role) |

### Wrappers, spelling, sequences and substitutions around `date`

| Input | Result |
|---|---|
| `/usr/bin/date …`, `/bin/date …`, `env date …`, `env env date …`, `/usr/bin/env date …`, `command date …`, `exec date …`, `exec -a x date …`, `nohup date …`, `timeout 5 date …`, `sudo date …` | deny (role) |
| `xargs date …`, `echo 010100002020 \| xargs date`, `find . -maxdepth 0 -exec date 010100002020 ;`, `bash -c 'date …'`, `echo date … \| bash` | deny (role) |
| `"date" …`, `da""te …`, `\date …`, `'date' …`, `date "010100002020"`, `date 0101""00002020`, `date \010100002020` | deny (role) |
| `date +%s 010100002020`, `date 010100002020 +%s` | deny (role) |
| `date +%s; date …`, `… && date …`, `… \|\| date …`, `… \| date …`, `… & date …` | deny (role) |
| `ls $(date …)`, `echo $(date …)`, ``echo `date …` ``, `ls <(date …)`, a bare `$(date …)` line | deny (role) |
| `TZ=UTC date …`, `D=010100002020 date $D` | deny (role) |
| `date {010100002020,+%s}`, `date 0101000020{20,}`, `date 01010000202?` | deny (role) |

Each `…` here is `010100002020`.

## Not exercised

- Round 4 changed no other rule. I did not re-attack the rest of the allowlist,
  `orchestrator_role.py`, `feature-close.sh`, `run-review.sh`, `wire-settings.py` or
  `manifest.py`; rounds 1–3's tables cover them, and none changed since.
- Date implementations other than GNU coreutils 9.4. The rule models GNU's
  `d:f:I::r:Rs:u` option string, and it is the `date` these sessions run.
- I tested a heredoc into `cat` carrying `$(date …)` line by line (each line was denied), not
  as one multi-line command; that rule is unchanged since round 1.
