Verdict: escalated

# Security audit — hook-audit-gaps (round 2)

Scope: the diff `origin/main...HEAD` of `hooks/allow-repo-commands.sh` and `hooks/README.md`.
I ran the attacks on throwaway copies under the pass's scratch directory. Each copy came from
`git archive` and was made into a fresh repo. The copies were: HEAD (`head`), `origin/main`
(`main`), and HEAD with a `.git` file that names no directory (`broken`). `broken` is the
unreadable-ledger checkout, where the build-script judge is the deny that every session gets.
The `head` and `main` copies carry a ledger line that names session `sess-S` as the
orchestrator of `wave`.

Every input was also run under **bash 5.2.21** with a logging `git` stub on `PATH` and logging
stubs named after the build scripts. The "bash ran" column comes from those logs; "—" means
bash ran neither a git command nor a build script. Each hook call used a fresh session id, so
the rewrite-deny counter never decayed a result. The only file I wrote in this checkout is
this report.

## Rules the diff adds or changes

1. **Heredoc body placement and the walk** (`heredoc_body_span`, `comment_and_heredoc_free`,
   `judged_texts`). The git deny, the chained-`cd` deny, the own-assignment deny and the
   build-script judge read the commands after a heredoc's body. Inside a substitution, a
   run-on line is read every way. Text is hidden only where the reading is certain.
2. **Comment handling.** A comment is not read. A `#` that is in doubt (one with an opener
   kept before it) is read both ways. Past `MAX_COMMENT_DOUBTS`, a line that names git is
   denied as unreadable.
3. **`bundles_push_force`.** A short-flag cluster that holds `f` is a force push. The letters
   stop at `-o`.
4. **`brace_words`.** The git deny expands brace groups as bash does. Past `MAX_BRACE_WORDS`
   the line is denied as unreadable.
5. **Cloud own push.** `branches[0]` is read from the manifest committed at `HEAD`, with
   `GIT_NO_REPLACE_OBJECTS=1`.
6. **Build-script judge (unreadable ledger).** It reads the line both with and without
   continuations, reads files fed by input redirects, treats any non-filter command as a
   launcher, reads bracket expressions, assignment values and git exec flags, and treats a
   pattern in any argument as a run.
7. **Orchestrator allowlist.** The heredoc message is read with
   `heredoc_argument_at(strict=True)`, so any body line that begins with the delimiter
   refuses the line.

## Bypasses

### R2-1 — a line continuation in a heredoc terminator line (rule 1)

`heredoc_body_span` compares each **raw** body line with the delimiter. For a heredoc with an
**unquoted** delimiter, bash first deletes each backslash-newline in the body and then looks
for the terminator. So `EO\⏎F`, `E\⏎O\⏎F`, `EOF\⏎` followed by an empty line, and
`⇥EO\⏎F` under `<<-` all end the body for bash. The hook keeps reading body until a later
plain `EOF` line, and the commands bash runs in between are hidden from every deny.

Reproduce (⏎ = line break):

| input | head | main | bash ran |
|---|---|---|---|
| `cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f origin y** |
| `cat <<EOF⏎x⏎EOF\⏎⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f origin y** |
| `cat <<-EOF⏎x⏎⇥EO\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f origin y** |
| `ls; cat <<EOF⏎x⏎E\⏎O\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f origin y** |
| `cat <<EOF⏎x⏎EO\⏎F⏎cd /tmp && ls⏎EOF` (cd chain) | prompt | prompt | cd chain runs |

These lines are not regressions: `main` read nothing after a heredoc and gives a prompt too.
They do break the rule this diff adds, though: "the commands after the body are read" and
"Text is hidden only where the reading is certain". The plain shape
`cat <<EOF⏎x⏎EOF⏎git push -f origin y` is a DENY on HEAD.

The fix: when the delimiter is unquoted, delete continuations from the body before looking
for the terminator. Or, when any body line ends in a backslash, leave the body unplaced so it
is read as commands. For a quoted delimiter bash joins nothing, and the hook is right
(`cat <<'EOF'⏎x⏎EO\⏎F⏎git push…`: bash ran nothing).

### R2-2 — a substitution opener split by a line continuation (rule 1)

`substituted()` searches the **raw** command for `$(`, `<(`, `>(` or a backtick. Bash deletes
`\⏎` first, so `<\⏎(` is a process substitution to bash. The hook then decides the heredoc
belongs to the main parser and reads a run-on line as body. Bash 5.2 ends the body at that
line and runs the rest of it.

| input | head | main | bash ran |
|---|---|---|---|
| `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | **prompt** | prompt | **push -f origin y** |
| `cat <\⏎(cat <<'EOF'⏎x⏎EOF) ; git push -f origin y⏎EOF⏎)` | **prompt** | prompt | **push -f origin y** |
| `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git reset --hard⏎EOF⏎)` | **prompt** | prompt | **reset --hard** |
| `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git branch -D main⏎EOF⏎)` | **prompt** | prompt | **branch -D main** |

The `$\⏎(` form is caught by the opaque check ("hides code"). The `>\⏎(` form is caught by
the redirect-write deny. `<\⏎(` reaches no deny. These lines are not regressions (`main`
prompts), but they are the round-1 E1 shape that this round claims to close: with `<(`
written out, `cat <(cat <<EOF⏎x⏎EOF ) ; git push…` is a DENY on HEAD.

The fix: test for openers in the walk's continuation-deleted text, not the raw command, and
apply the same to `HEREDOC_SHIFT_RE`. The arithmetic forms (`(\⏎(`, `$\⏎[`, `a[1\⏎<<2]`)
happen to be denied today by other paths (rows ar1–ar5 below), but they read the same raw
text.

### R2-3 (minor) — the own-assignment deny reads only the first reading (rule 2)

`hooks/README.md` says `command_words`, which feeds the git, assignment and build-script
denies, "reads every text `judged_texts` returns, and a deny is owed when ANY of them holds
one". `assigned_names` does find the assignment that way. But `uses_own_assignment` looks for
the use in `judged_text(command)`, the first reading, where a comment in doubt is dropped. So
`a=(x)#b; X=/p; cat $X/f` gives a **prompt** on HEAD, while `X=/p; cat $X/f # it's` gives a
DENY. Bash runs `cat /p/f`. This is not a regression (`main` prompts), and the effect is a
rewrite deny lost to a prompt.

The chained-`cd` deny reads only the first walk, as documented (`a=(x)#b; cd /tmp && ls`
gives a prompt). I list that for completeness; it is not counted.

## Not counted as bypasses

These were found on HEAD and also give a prompt on `main`, or are already documented:

- `ls | grep plans | xargs sh` on the unreadable-ledger checkout: the name is built at run
  time (documented class).
- `git push --force-w`, `-{Z..a}`: documented prompts.

## Attempts

### Round-1 escalations, retested (git deny, `local`)

| case | input | head | main | bash ran |
|---|---|---|---|---|
| e1a | `git commit -m "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY | DENY | commit, push -f |
| e1b | same with `EOF⇥)` | DENY | DENY | commit, push -f |
| e1c | same with `EOFS)` | DENY | DENY | commit, push -f |
| e1d | `echo "$(cat <<'EOF'⏎x⏎EOFxyz ; true)" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY | DENY | push -f |
| e1e | same with `EOF'q')` | DENY | DENY | push -f |
| e1f | `echo $(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | DENY | prompt | push -f |
| e1g | `echo "$(cat <<'EOF'⏎EOFS⏎EOF x)" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY | DENY | push -f |
| e3a | `a=(x)#b; git push -f origin y` | DENY | prompt | push -f |
| e3b | `echo $(echo a)#b; git push -f origin y` | DENY | prompt | push -f |
| e3c | `echo <(true)#b; git push -f origin y` | DENY | prompt | push -f |
| e3d | `echo $((1))#b; git push -f origin y` | DENY | prompt | push -f |
| pid | `echo $$'a\' ; git push -f origin y #'` | DENY | prompt | push -f |
| base | `git push -f origin y` | DENY | DENY | push -f |

### Line continuations against the walk's raw-text checks

| case | input | head | main | bash ran |
|---|---|---|---|---|
| cs1 | `echo $\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | DENY (opaque) | DENY (opaque) | push -f |
| cs2 | `echo "$\⏎(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY | DENY | push -f |
| cs3 / ps1 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | **prompt** | prompt | **push -f** (R2-2) |
| cs4 | `git commit -m "$\⏎(cat <<'EOF'⏎x⏎EOF)" ; git push -f origin y ; echo "⏎EOF⏎)"` | DENY | DENY | commit, push -f |
| ps2 | `diff <\⏎(cat <<EOF⏎x⏎EOFS) <(true) ; git push -f origin y⏎EOF⏎)` | DENY (opaque) | DENY (opaque) | push -f |
| ps3 | `echo >\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | DENY (redirect write) | DENY | push -f |
| ps4 | `x=$\⏎(cat <<EOF⏎x⏎EOF ) ; git push -f origin y⏎EOF⏎)` | DENY (opaque) | DENY (opaque) | push -f |
| ps5 | `cat <\⏎(cat <<'EOF'⏎x⏎EOF) ; git push -f origin y⏎EOF⏎)` | **prompt** | prompt | **push -f** (R2-2) |
| ps6 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git reset --hard⏎EOF⏎)` | **prompt** | prompt | **reset --hard** (R2-2) |
| ps7 | `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; git branch -D main⏎EOF⏎)` | **prompt** | prompt | **branch -D main** (R2-2) |
| ar1 | `(\⏎( x = 1<<2 ))⏎git push -f origin y⏎2` | DENY (opaque) | DENY (opaque) | push -f |
| ar2 | `echo $\⏎[1<<2]⏎git push -f origin y⏎2]` | DENY | DENY (opaque) | push -f |
| ar3 | `a[1\⏎<<2]=5⏎git push -f origin y⏎2]=5` | DENY | DENY (opaque) | push -f |
| ar4 | `echo $(\⏎(1<<2))⏎git push -f origin y⏎2))` | DENY (opaque) | DENY (opaque) | push -f |
| ar5 | `((\⏎x=1<<2))⏎git push -f origin y⏎2))` | DENY | DENY (opaque) | push -f |
| tc1 | `cat <<EOF⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f** (R2-1) |
| tc2 | `cat <<EOF⏎x⏎EOF\⏎⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f** (R2-1) |
| tc3 | `cat <<EOF⏎x\⏎EOF⏎git push -f origin y⏎EOF` | DENY | prompt | — |
| tc4 | `cat <<'EOF'⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF` | prompt | prompt | — |
| tc5 | `cat <<-EOF⏎x⏎⇥EO\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f** (R2-1) |
| tc6 | `cat <<EOF⏎x⏎\⏎EOF⏎git push -f origin y⏎EOF` | DENY | prompt | push -f |
| tc7 | `ls; cat <<EOF⏎x⏎E\⏎O\⏎F⏎git push -f origin y⏎EOF` | **prompt** | prompt | **push -f** (R2-1) |
| cd2 | `cat <<EOF⏎x⏎EO\⏎F⏎cd /tmp && ls⏎EOF` | prompt | prompt | cd chain (R2-1) |

### Orchestrator allowlist (session `sess-S`)

| case | input | head | main | bash ran |
|---|---|---|---|---|
| o1 | `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | prompt | prompt | commit |
| o2 | `… <<'EOF'⏎x⏎EOF )" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` | DENY (role) | prompt | commit, BUILD |
| o3 | same with `EOFS)` | DENY (role) | prompt | commit, BUILD |
| o4 | same with `EO\⏎F)` | prompt | prompt | commit only (quoted delimiter: no join) |
| o5 | same with `⇥EOF )` | prompt | prompt | commit only |
| o6 | same with `EOF\r)` | DENY (role) | prompt | commit, BUILD |
| o7 | `git push -u origin "$(git branch --show-current)"` | prompt | prompt | push |
| o8 | `./feature-start.sh zz` | DENY (role) | DENY (role) | BUILD |
| o9 | `gh pr create --title t --body "$(cat <<'EOF'⏎b⏎EOF x)" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` | DENY (role) | prompt | BUILD |

### `bundles_push_force` and `brace_words`

| case | input | head | main | bash ran |
|---|---|---|---|---|
| b1 | `git push -fu origin x` | DENY | prompt | push -fu |
| b2 | `git push -uof origin x` | prompt | prompt | push -uof (`-o f`, no force) |
| b3 | `git push -${o}f origin x` | DENY (variable) | DENY (variable) | push -f |
| b4 | `git push -u$'f' origin x` | DENY | prompt | push -uf |
| b5 | `git push -qvnf4 origin x` | DENY | prompt | push -qvnf4 |
| b6 | `git push -o x -f origin y` | DENY | DENY | push -f |
| b7 | `git push -uo -f origin y` | DENY | DENY | push -uo -f |
| b8 | `git push --force-w origin y` | prompt | prompt | push --force-w (documented) |
| br1 | `git push -{u,f} origin x` | DENY | prompt | push -u -f |
| br2 | `git push -u{f\,x} origin x` | DENY | DENY | push -u{f,x} (over-deny, safe) |
| br3 | `git push --forc{e..e} origin x` | DENY | prompt | push --force |
| br4 | `git push -u{e..g} origin x` | DENY | prompt | push -ue -uf -ug |
| br5 | `git reset --{hard,soft}` | DENY | prompt | reset --hard --soft |
| br6 | `git push origin {x,+main}` | DENY | prompt | push origin x +main |
| br7 | `git branch -{D..D} x` | DENY | prompt | branch -D x |
| br8 | `git push -{0..9}f origin x` | DENY | prompt | push -0f … -9f |
| br9 | `git push origin x{1..99999}` | DENY (unreadable) | prompt | push origin x1 … |
| br10 | `git push -u{,,}{,,}{,,}{,,}{,,}{,,}{,,}f origin x` | DENY | DENY | push -uf … |
| br11 | `git {re,}set --hard` | DENY | prompt | reset set --hard |
| br12 | `git push -{Z..a} origin x` | prompt | prompt | no force flag |

### Comments in doubt, the cap, the assignment and `cd` denies

| case | input | head | main | bash ran |
|---|---|---|---|---|
| cm1 | `a=(x)#b; git push -f origin y` | DENY | prompt | push -f |
| cm2 | `(ls) # c; git push -f origin y` | DENY | prompt | — (documented over-deny) |
| cm3 | `echo { # '⏎` ×6, then `git push -f origin y` | DENY (unreadable) | prompt | push -f |
| cm4 | same with `g\it push -f origin y` | DENY | prompt | push -f |
| cm5 | `echo [ #a⏎[ #b⏎…[ #f⏎git push -f origin y` | DENY | prompt | push -f |
| cm6 | `a=(x)#b; cd /tmp && ls` | prompt | prompt | cd chain (documented) |
| cm7 | `ls # x⏎cd /tmp && ls` | DENY (cd) | prompt | — |
| cm8 | `ls x #y \⏎git push -f origin y` | DENY | prompt | push -f |
| cm9 | `case x in #c⏎x) git push -f origin y;; esac` | DENY | DENY | push -f |
| cm10 | ``echo `#`; git push -f origin y`` | DENY | prompt | push -f |
| cm11 | `echo ${x#⏎} ; git push -f origin y` | DENY | prompt | push -f |
| cm12 | `x=(a #b⏎); git push -f origin y` | DENY | prompt | push -f |
| as1 | `cat <<EOF⏎x⏎EOF⏎X=/p; cat $X/f` | DENY (assignment) | prompt | — |
| as2 | `X=/p; cat $X/f # it's` | DENY (assignment) | prompt | — |
| as3 | `a=(x)#b; X=/p; cat $X/f` | **prompt** | prompt | `cat /p/f` (R2-3) |
| cd1 | `ls;<<EOF cat⏎x⏎EOF⏎cd /tmp && ls` | DENY (cd) | DENY (opaque) | — |

### Build-script judge (`broken`, unreadable ledger)

Every DENY in this table carries the ledger reason.

| case | input | broken | bash ran |
|---|---|---|---|
| u1 | `./run-plans.sh --self x` | DENY | BUILD |
| u2 | `ls # x \⏎./run-plans.sh` | DENY | BUILD |
| u3 | `a=(x)#b; ./run-plans.sh` | DENY | BUILD |
| u4 | `ls #a\⏎\⏎./run-plans.sh` | DENY | BUILD |
| u5 | `a=(x)#b; ` ×6, then `./run-plans.sh` | DENY | BUILD |
| u6 | `exec 3<run-plans.sh; bash <&3` | DENY | BUILD |
| u7 | `bash /dev/fd/3 3<run-plans.sh` | DENY | BUILD |
| u8 | `source /dev/stdin < run-plans.sh` | DENY | BUILD |
| u9 | `cat run-plans.sh > x.sh; sh x.sh` | DENY | BUILD |
| u10 | `tee x.sh < run-plans.sh >/dev/null; sh x.sh` | DENY | BUILD |
| u11 | `cp run-pla?s.sh y; ./y` | DENY | BUILD |
| u12 | `find . -name 'run-pl*' -print \| sh` | DENY | BUILD |
| u13 | `sh -c 'for f in run-pl*; do ./$f; done'` | DENY | BUILD |
| u14 | `ls \| grep plans \| xargs sh` | prompt | BUILD (name built at run time; known) |
| u15 | `printf '%s' ./run-pl ans.sh \| sh` | DENY (opaque) | BUILD |
| u16 | `bash < run-pla\⏎ns.sh` | DENY | BUILD |
| u17 | `bash<'run-plans'.sh` | DENY | BUILD |
| u18 | `bash 0<>run-plans.s[h]` | DENY | BUILD |
| u19 | `(ls) # x \⏎./run-plans.sh` | DENY | BUILD |
| u20 | `ls⇥#x \⏎./run-plans.sh` | DENY | BUILD |
| u21 | `echo a=(x)#b \⏎./run-plans.sh` | DENY | — |
| u22 | `ls x # \⏎\⏎./run-plans.sh` | DENY | BUILD |
| u23 | `cat run-plans.sh \| sort \| sh` | DENY | BUILD |
| u24 | `cat run-plans.sh \| busybox sh` | DENY | — |
| u25 | `wc -l < run-plans.sh` | prompt | — (a read) |
| u26 | `cat < run-plans.sh` | prompt | — (a read) |
| u27 | `ls a\ #b; ./run-plans.sh` | DENY | BUILD |
| u28 | `ls x; #'⏎./run-p*.sh` | DENY | BUILD |

### Cloud own push (`AGENTTOOLING_PROFILE=cloud`, the HEAD copy on `claude/hook-audit-gaps`)

| case | input | head |
|---|---|---|
| cp1 | `git push -u origin claude/hook-audit-gaps` | ALLOW (expected) |
| cp4 | `git push -u origin claude/evil` | DENY |
| cp5 | `git push -fu origin claude/hook-audit-gaps` | DENY |
| cp6 | `git push -u origin claude/hook-audit-gaps # it's` | prompt |

I stopped one further line of testing on this rule partway through and did not finish it;
it has no rows here. The manifest-at-`HEAD` change and the replace-ref hardening were not
attacked beyond the rows above. Round 1's rows on uncommitted, staged and untracked
manifest edits (all prompts) were not re-run.

## What held

Every round-1 escalation (E1's run-on spellings, E2's comment continuations, E3's `)#`) and
the `$$'…'` gap are now denied, on the git deny and on the build-script judge. Every bundle
and brace spelling tried was denied, as were the doubt-cap overflows when git is named. The
orchestrator gets the role deny for every run-on spelling bash 5.2 ends a body at. The
build-script judge denied every redirect, copy, pattern and comment shape tried, apart from
the known name built at run time.

The bypasses that remain are R2-1 and R2-2. Both come from the walk comparing **raw** text
where bash has already deleted a line continuation (a heredoc terminator line, a `<(` opener),
plus the minor R2-3. Each gives a prompt, never an allow.
