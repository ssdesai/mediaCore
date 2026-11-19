Verdict: clean

# Security audit — orchestration-record-fixes (plan 15, opus)

## Setup

I extracted two throwaway copies under the pass's scratch directory, one from
`git archive HEAD` (`b97f1cd`) and one from `git archive origin/main`. Each copy's
`hooks/allow-repo-commands.sh` was loaded as a module and its `main()` was driven with
PreToolUse payloads on stdin (`tool_name: Bash`, a fresh `session_id` per case, `cwd` and
`CLAUDE_PROJECT_DIR` set to the copy, `AGENTTOOLING_PROFILE=local`). There were three modes:

- **none**: `orchestrator_record` returns None. This exercises the git, chdir and assignment
  denies and the approval analysis.
- **unreadable**: `orchestrator_record` returns `LEDGER_UNREADABLE`, the only path that reaches
  `build_script_denial` and `unreadable_ledger_refuses`.
- **cloudpush**: the cloud profile, with `checkout_state` and `started_feature` stubbed so that
  `claude/feat` is the current branch and the started feature's `branches[0]`. This is the one
  write the hook approves silently (`own_push_allowed`), so it is the main target for a
  silent-allow bypass.

Each input was run against both copies. Candidate build-script bypasses were also run in
**real bash** in a sandbox holding a fake `run-plans.sh` that leaves a marker file when it runs.

## What changed since round 14

The hook rules in this feature's diff are byte-identical to what round 14 attacked: `b96b3b4`
→ HEAD touches `hooks/allow-repo-commands.sh` only through the merges of `origin/main`
(#142, #143), which add the guarded `shared_rules` import and `ORCHESTRATOR_SLUG_RE`. Those
come from `origin/main`, not from this diff. `b97f1cd` changes only NOTES.md and README.md. It
records round 14's A–C as pre-existing gaps that are out of scope for this feature and hands
them to `hook-audit-gaps`. This audit applies that scope: a finding is a regression against
`origin/main` or a new silent allow.

`analysis/report.py`'s change (an `agentTooling` entry's `report` path is resolved against
the agentTooling directory) is a read of a record's own path by a report tool. It adds no
hook rule; the path is joined the same way `repo_root` already was.

**Rules under attack:**

1. **R-sep:** `quoted_separator_word`, together with masking in `chain_tokens`. A quoted or
   escaped operator word (`';'`, `\;`, `"|"`) is never approved, and the deny readers keep it
   as an argument.
2. **R-fd:** `is_bare_descriptor`. Only an unquoted digit run of at most INT_MAX, or a `{name}`,
   is dropped as a redirect's descriptor.
3. **R-ops:** `punctuation_pieces`, `is_operator_token` and `is_heredoc_operator`. Operator runs
   are read longest first, as bash reads them.
4. **R-heredoc:** `judged_tokens`. A heredoc's own line is judged and its body is not.
5. **R-fail-closed:** `fails_closed`. A git word together with `$(`, a backtick, `<(`, `>(`,
   `<<` or `case` is never approved.
6. **R-ledger:** `unreadable_ledger_refuses`. On an unreadable ledger, a raw line holding a
   marker is refused.
7. **R-build:** `invokes_build_script`, rerouted through `chain_tokens`.

## Inputs tried

Key: `allow` means approved silently. `ask` means the hook printed nothing or asked, so the
human decides. `deny` means a deny from any judge: the git deny, the role or ledger deny, or
a rewrite deny.

### Silent-allow attacks on the cloud own-push approval (cloudpush)

| Input | HEAD | main |
|---|---|---|
| `git push origin claude/feat` (control) | allow | allow |
| `git push -u origin claude/feat` | allow | allow |
| `git -C . push origin claude/feat`, `git -C '.' push origin claude/feat` | allow | allow |
| `git push origin claude/feat 2>&1`, `1>/dev/null`, `>/dev/null 2>&1`, `&>/dev/null`, `1>/dev/null 2>/dev/null` | allow | allow |
| `git push origin claude/feat 2>&1 \| tail -3`, `… 2>/dev/null&`, `…;`, `… ; ls`, `… && git log -1` | allow | allow |
| `git push origin 'claude/feat' ;ls` | allow | allow |
| `git push origin claude/feat ';' ls :main` | deny | **allow** |
| `… ";" ls :main`, `… \; ls :main`, `… ''\; ls :main` | deny | **allow** |
| `… '&&' ls :main`, `… '\|' cat :main` | deny | **allow** |
| `… ';'';' ls :main`, `… ')' ls :main`, `… '(' ls :main`, `… '<' x` | deny | ask |
| `git push origin claude/feat 2>&1 ';' :main` | deny | ask |
| `git push origin claude/feat 99999999999>/dev/null` | deny | ask |
| `git push origin claude/feat '' `, `… ""`, `git push '' origin claude/feat` | deny | ask |
| `git push origin claude/feat $';' ls :main` | deny | deny |
| `git push origin claude/feat '1'>/dev/null :main`, `… >/dev/null :main` | deny | deny |
| `git push origin claude/feat 2>/dev/null:main` | ask | ask |
| `git push origin claude/feat {fd}>/dev/null` | ask | ask |
| `git -C ';' push origin claude/feat`, `git -C 1>/dev/null push origin claude/feat` | ask | ask |
| `git push origin claude/feat # :main`, `… # x`, `… #` | ask | ask |
| `git push origin claude/feat;git push origin main`, `… & git push -f origin x`, `… \|\| git push -f origin claude/feat` | deny | deny |
| `git push origin claude/feat ;>/dev/null git push origin :main` | deny | deny |
| `git push origin claude/feat:main`, `'claude/feat:main'`, `claude/feat\:main` | deny | deny |
| `git push origin +claude/feat` | ask | ask |
| `git push -u origin claude/feat --force`, `… -f` | deny | deny |
| `git push origin claude/feat\tls`, `…\x0b:main`, `…\x0c:main`, `…\xa0:main`, `…​` | deny | deny |
| `git push origin claude/feat\r`, `git push origin　claude/feat` | ask | ask |
| `git push origin claude/feat ;;`, `… \|& cat` | ask | ask |
| `git push origin claude/feat 2>/dev/null\|sh` | deny | deny |
| `env git push origin claude/feat`, `GIT_SSH_COMMAND=x git push origin claude/feat` | ask | ask |
| `git push origin claude/feat case` | deny | deny |
| `git push origin "$(git branch --show-current)"` | deny | deny |
| `case x in x) git push origin claude/feat;; esac` | deny | deny |

### Git deny (none)

| Input | HEAD | main |
|---|---|---|
| `g""it push origin main`, `gi''t …`, `\git …`, `'git' …`, `/usr/bin/git push origin main` | deny | deny |
| `git push origin ma''in`, `m\ain`, `'main'`, `HEAD:main` | deny | deny |
| `git push origin main ';' ls`, `… '#'`, `git reset --hard HEAD~1 ';'` | deny | deny |
| `git push origin '1'>/dev/null main`, `1>…`, `\1>…`, `x1>…`, `0002>…`, `١>…`, `²>…`, `2147483647>…`, `2147483648>…` | deny | deny |
| `git -C 99999999999>/dev/null push origin main` | deny | ask |
| `git push origin {fd}>/dev/null main` | deny | ask |
| `git push origin {f-d}>/dev/null main` | ask | ask |
| `git push ${x}>/dev/null origin main` | deny | deny |
| `true;>x git push origin main`, `true &&>x …`, `true \|&>x …`, `true ;;>x …` | deny | ask |
| `true&>x git push origin main`, `true <>x git push origin main` | ask | ask |
| `>x git push origin main` | deny | deny |
| `git push origin main <<<x`, `true <<<x; git push origin main`, `true <<< x ; git reset --hard HEAD~1` | deny | deny |
| `echo '<<' ; git push origin main`, `echo \<\< ; …`, `cat '<<'EOF ; …`, `cat "<<" ; …` | deny | ask |
| `cat <\< x ; git push origin main`, `cat <'<' x ; …` | deny | deny |
| `echo x<<-E ; git push origin main⏎E`, `git push origin main 2>&1 <<EOF⏎x⏎EOF`, `git push origin main <<'E'⏎x⏎E` | deny | deny |
| `cat <<'E' ; git push origin main⏎x⏎E`, `cat <<E ; git push origin main⏎don't⏎E` | deny | ask |
| `cat <<EOF \| git push origin main⏎x⏎EOF`, `cat <<EOF && git push origin main⏎y⏎EOF` | deny | ask |
| `cat <<'E;F' ; git push origin main⏎x⏎E;F`, `cat <<\EOF ; …`, `cat <<'' ; …`, `cat << ; …` | deny | ask |
| `cat <<E⏎x⏎E⏎git push origin main`, `… ⏎ git push origin main`, `cat <<E⏎x⏎E⏎git reset --hard HEAD~1` | ask | ask |
| `x <<E ; y⏎E⏎git push origin main` | deny | deny |
| `echo "a\"" ; git push origin main`, `echo 'a\' ; …`, `echo (x) ; …`, `( git push origin main )` | deny | deny |
| `x=$(true) git push origin main`, `echo <(true) git push origin main` | deny | deny |
| `echo $'\'' ; git push origin main #'` | ask | ask |
| `g?t push origin main`, `g[i]t push origin main` | ask | ask |
| `git reset --hard HEAD~1 2>&1`, `git branch -D x 2>&1 \| tail -3` | deny | deny |
| `case x in x) git push origin main;; esac` | deny | deny |
| `git push origin main # x`, `git push origin main # '`, `git reset --hard HEAD~1 # '` | ask | ask |
| `git push -fu origin x` | ask | ask |

### Chdir and assignment rewrites, and approvals (none)

| Input | HEAD | main |
|---|---|---|
| `cd /tmp && ls`, `cd /tmp 2>x; ls`, `ls <(cd /tmp) ; ls`, `(cd /tmp) && ls` | deny | deny |
| `cd /tmp;>x ls` | deny | ask |
| `cd /tmp '&&' ls` (bash: one `cd` with three arguments) | ask | deny |
| `ls >(cd /tmp && ls)` | ask | ask |
| `X=/p; cat $X/f`, `X=/p ';' cat $X/f`, `X=/p\; cat $X/f`, `X=/p 2>x; cat $X/f`, `X=/p;>y cat $X/f` | deny | deny |
| `ls ';' ls` | ask | allow |
| `grep -n '\(' README.md`, `grep -n 'a;b' README.md`, `ls 2>&1`, `ls '>'x`, `ls x'>'`, `ls '$(' x` | allow | allow |
| `cat README.md 1>/dev/null`, `git log --oneline -1` | allow | allow |
| `grep -n ';' README.md`, `ls '>' /etc/passwd`, `cat README.md '\|' /etc/passwd`, `cat README.md \| /etc/passwd` | ask | ask |
| `ls '<<' x`, `git log '<<' -1`, `ls x<y`, `cat <README.md`, `cat </etc/passwd`, `cat 0</etc/passwd`, `cat '0'</etc/passwd` | ask | ask |
| `cat README.md 3>/dev/null`, `cat README.md {fd}>/dev/null`, `ls >'x'` | ask | ask |
| `cat README.md ;>/dev/null`, `echo hi 2>&1 >x`, `ls ; >x` | deny | deny |
| `git log --grep=case -1`, `git log 'case' -1` (documented cost) | ask | allow |
| `case x in x) ls;; esac` | deny | deny |

### Build script on an unreadable ledger (unreadable)

| Input | HEAD | main | bash |
|---|---|---|---|
| `./run-plans.sh --self x` ×3, same session | deny ×3 | deny ×3 | RAN |
| `./run-p*.sh --self x`, `( ./run-p*.sh … )`, `{ ./run-p*.sh …; }`, `echo x \|& ./run-p*.sh`, `ls ; ./run-p\*.sh` | deny | deny | — |
| `echo ';' ; ./run-p*.sh …`, `echo \; ; ./run-p*.sh …`, `true 2>x; ./run-p*.sh …` | deny | deny | — |
| `true;>x ./run-p*.sh --self x` | deny | ask | RAN |
| `{fd}>x ./run-p*.sh --self x` | deny | deny | RAN |
| `99999999999>x ./run-p*.sh --self x` | ask | deny | **no** |
| `true '1'>x ./run-p*.sh` | ask | ask | no |
| `echo '<<' ; ./run-p*.sh …`, `echo \<\< ; ./run-p*.sh …` | deny | ask | — |
| `echo '$(' ; ./run-p*.sh …`, `echo $"x" ; ./run-p*.sh`, `echo $'x' ; ./run-p*.sh`, `echo $ (./run-p*.sh)` | deny | deny | — |
| `ls "$(./run-plans.sh)"` ×3, same session | deny ×3 | ask ×3 | — |
| `cat <<E⏎x⏎E⏎./run-p*.sh --self x` | deny | ask | — |
| `echo ${X:-./run-plans.sh}` | deny | deny | — |
| `echo $\(./run-p*.sh)` | ask | ask | no |
| `ls README.md`, `git status` | allow | allow | — |
| `./run-p*.sh --self x # '`, `env ./run-p*.sh --self x # '` (round 14's A) | ask | ask | RAN (round 14) |
| `./run-p*.sh --self x \` ×3, `bash -c './run-p*.sh --self x'` ×3 (round 14's B) | deny, deny, ask | deny, deny, ask | — |
| `unshare ./run-p*.sh …`, `awk 'BEGIN{system("./run-p*.sh …")}'`, `git -c alias.z='!./run-p*.sh …' z` (round 14's C) | ask | ask | RAN (round 14) |

## Findings

**No bypass found.** No input reaches a silent allow on HEAD that it does not also reach on
`origin/main`, and wherever the two copies differ, HEAD is the stricter one, with three
exceptions. Each of those is correct:

- **`99999999999>x ./run-p*.sh --self x`**: HEAD asks where main denied. Real bash does not
  run the script, because the over-INT_MAX digit run is a word (the program name), not a
  descriptor. The same holds for `2147483647>x` and `2147483648>x`. HEAD's reading is the
  accurate one, and there is nothing to deny.
- **`cd /tmp '&&' ls`**: HEAD asks where main denied. The quoted `&&` is an argument to `cd`,
  not a chain, so main's deny was a false positive.
- **`git log --grep=case -1`, `git log 'case' -1`**: HEAD asks where main allowed. This is a
  prompt, not an allow, and it is the documented cost of `fails_closed`.

The silent allows of a protected push that main has (`git push origin <own branch> ';' ls
:main` and the other quoted-separator spellings, which bash runs as one push of `:main`) are
closed on HEAD. Every spelling I tried is denied: single, double, backslash, empty-quote,
`&&`, `|`, a double `;;` and both parens.

**Pre-existing gaps, out of scope by the recorded ruling (NOTES.md, "Round 14's verdicts").**
Each one reproduces identically on HEAD and on `origin/main`, and each ends in a prompt, never
a silent allow:

- **Round 14's A, generalised:** any unquoted `#` makes `never_judged` switch every deny off for
  the line (`git push origin main # x`, as well as `# '`). This is deliberate on main.
- **Round 14's B:** the two-strikes rewrite prompt.
- **Round 14's C:** the launcher denylist.
- **Already-recorded limits:** commands after a heredoc's body are not read (`cat <<E⏎x⏎E⏎git
  push origin main`), and `git push -fu`.

The ruling is recorded in NOTES.md (commit `b97f1cd`) and attributed there to the repository
owner. This audit applies it as written and did not verify it independently.

Note on the driver: the third attempt of a rewrite-denied line came back as no output rather
than an explicit `ask`, presumably because the headless environment variable is set in this
container. Either way the human or the runner policy decides, not a silent allow.
