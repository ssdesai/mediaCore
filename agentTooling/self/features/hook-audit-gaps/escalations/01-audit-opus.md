Verdict: escalated

# Security audit — hook-audit-gaps (round 1)

Scope: the diff `origin/main...HEAD` of `hooks/allow-repo-commands.sh` and `hooks/README.md`.
The attack ran on throwaway copies under the pass's scratch directory: `git archive HEAD` and
`git archive origin/main` each turned into a git repo, a HEAD copy whose `.git` names no
directory (the unreadable-ledger checkout, where the build-script judge is the deny every
session gets), a clone for the cloud own-push rule, and a clone whose ledger names session
`sess-S` as an orchestrator. Every input was also run under **bash 5.2.21** in a sandbox. That
sandbox had a logging `git` stub on `PATH` and logging stubs named after the build scripts, so
each row records what bash actually ran (the "bash ran" column). Nothing in this checkout
was edited apart from this report.

## Rules the diff adds or changes

1. **Heredoc body placement (`heredoc_body_span`, `comment_and_heredoc_free`, `judged_texts`).**
   The deny side (the git deny, the chained-`cd` deny, the own-assignment deny and the
   build-script judge) now reads the commands after a heredoc's body and leaves the body out.
   It places a body only where bash does.
2. **Comment stripping.** A `#` is a comment only where bash starts one. A comment is not read
   for any session, so an apostrophe in it hides nothing. A `#` inside a word is now judged.
3. **`bundles_push_force`.** `-fu`, `-uf` and `-vfq` are a force push in both profiles. The
   letters stop at `-o`.
4. **`brace_words`.** The git deny expands brace groups (nested groups and sequences) as bash
   does, and refuses past `MAX_BRACE_WORDS`.
5. **Own push in the cloud.** `branches[0]` is read from the manifest committed at `HEAD`.
6. **Build-script judge, for an unreadable ledger.** It deletes line continuations, reads files
   fed by input redirection, treats any non-filter command as a launcher, reads bracket
   expressions as `?`, splits a line that does not lex at operators, reads assignment values,
   and reads git exec flags abbreviated or clustered.
7. **Orchestrator allowlist.** The heredoc message is read with `heredoc_argument_at(strict=True)`,
   and the B1 smuggle is meant to get the role denial.

## Bypasses

### E1 — regression: a body line that starts with the delimiter and ends with `)` ends a `$(…)` heredoc in bash 5.2 (rules 1 and 7)

`heredoc_body_span` treats a line as a "run-on" only when an **operator character** follows the
delimiter directly (`HEREDOC_RUN_ON_CHARS`). Bash 5.2 ends a heredoc inside `$(…)` at any body
line that **begins with the delimiter** and goes on to close the substitution with `)`. A blank
(`EOF )`, `EOF\t)`), a word character (`EOFS)`, `EOFxyz ; true)`) or a quote (`EOF'q')`) may
come between them. The hook reads those lines as body. The whole-argument heredoc then stands
as `""` up to a later bare `EOF` line, and the command bash runs in between is hidden.
`hooks/README.md` says "`EOF ` and `EOFS` are plain body lines". That holds only when no `)`
follows on that line.

Reproduce. Each command below is one string with real line breaks (⏎):

- Git deny: `git commit -m "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; echo "⏎EOF⏎)"`
  — HEAD: **prompt**. origin/main: DENY. Bash runs `git push -f origin y`. The same happens
  with `EOF\t)`, `EOF x)`, `EOFS)`, `EOF a b c)`, `EOFxyz ; true)` and `EOF'q')` (batches
  c6 and c7).
- Orchestrator role (session `sess-S` in the ledger):
  `git commit -m "$(cat <<'EOF'⏎x⏎EOF )" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` — HEAD:
  **prompt**, where the role denial is expected. Bash runs `./feature-start.sh zz`. `EOF\t)`
  behaves the same. This is the audit's B1 exploit (H26) with one blank added.

What the rule should do instead: inside a substitution, a body line that starts with the
delimiter (after tab-stripping under `<<-`) and is not exactly the delimiter should be
unplaced, or read both ways as the operator-character run-on already is, whatever character
follows. The strict orchestrator reader should refuse it. The H8 rows asserting that `EOF ` and
`EOFS` are plain body lines should be narrowed to lines with no later `)`.

### E2 — regression: a comment ending in a backslash swallows the next line (rule 6)

`invokes_build_script` deletes every `\⏎` before it removes comments. Bash does not continue a
comment past a backslash-newline, so the next line is a command. The deletion joins that line
into the comment, and the comment strip then drops it.

Reproduce in the unreadable-ledger checkout: `ls # x \⏎./run-plans.sh` gives HEAD **prompt**,
and bash runs `./run-plans.sh`. origin/main's `invokes_build_script` returns True (DENY).
These variants behave the same: `ls #\⏎./run-plans.sh`, `echo x;#a \⏎./run-plans.sh`,
`ls #a\⏎\⏎./run-plans.sh`, `ls # x \⏎./run-plans.sh --self x # y`, `ls #\⏎bash < run-plans.sh`
and `ls #\⏎cat run-plans.sh | unshare sh`. The git deny is not affected:
`ls #\⏎git push -f origin y` is DENY.

What the rule should do instead: delete a continuation only outside a comment, either during
the same walk or after comments are removed. Alternatively, judge the line both with and
without the deletion.

### E3 — `#` right after a `)` is not a comment in bash (rule 2; a regression for the build-script judge)

`COMMENT_PREDECESSORS` holds `)`. Bash starts no comment after the `)` of `name=(…)`, `$(…)`,
`<(…)` or `$((…))`, because the `#` continues the word. The walk strips the rest of the line.

- Build-script judge (unreadable ledger): `a=(x)#b; ./run-plans.sh` gives HEAD **prompt**,
  and bash runs `./run-plans.sh`. origin/main's `invokes_build_script` returns True. The
  `$(…)#` form is masked in that checkout by the raw-`$(` refusal, but its judge is also
  False on HEAD where main was True.
- Git deny (not a regression; main prompts too): `a=(x)#b; git push -f origin y` and
  `echo $(echo a)#b; git push -f origin y` give **prompt**, and bash runs the force push. This
  contradicts the README's new claim that "a `#` is a comment only where bash starts one".

What the rule should do instead: count `)` as a comment start only when it closes a subshell
or group. The simplest safe form drops `)` from `COMMENT_PREDECESSORS`: the text after it is
then read as commands, which over-reads in the safe direction (`(ls)#b` is a bash syntax error
anyway).

## Gaps found that are not regressions (each a prompt on origin/main too)

- `$$'…'` is walked as an ANSI-C quote. `echo $$'a\' ; git push -f origin y #'` gives a
  prompt, and bash runs the push.
- A quote nested in a backtick inside `"…"`, for example
  `echo "\`echo " #"\`"; git push -f origin y`, gives a prompt. The README already documents
  this class.
- Build-script names built at run time, which no line reader can see, all give a prompt:
  awk string concatenation (`awk 'BEGIN{system("./run-pl" "ans.sh")}'`),
  `printf './run-pl%sns.sh' a | sh`, `echo ./run-plbns.sh | tr b a | sh`, and a grep regex
  feeding `xargs sh` (`ls | grep plans | xargs sh`).
- Cloud own push: `git grep` and `git show` at `HEAD` honour `refs/replace/`. A replace ref
  pointing HEAD's manifest blob at a staged blob naming `claude/evil` made
  `git push -u origin claude/evil` **ALLOW** with no commit. This is **not counted as a
  bypass**: writing under `.git/` needs a human-approved write, because the wired settings deny
  `Edit(**/.git/**)` and `git replace`/`update-ref` are writes. Hardening suggestion: run the
  probe with `--no-replace-objects` (or `GIT_NO_REPLACE_OBJECTS=1`).

## Attempts

The "bash ran" column comes from the logging stubs: a `git` stub prints its argv, and the
build-script stubs print `BUILD:<name>`. "—" means bash ran neither.

### Cloud own push (`AGENTTOOLING_PROFILE=cloud`; a clone on `claude/hook-audit-gaps`)

| case | input | HEAD |
|---|---|---|
| committed manifest | `git push -u origin claude/hook-audit-gaps` | ALLOW |
| `--set-upstream` | `git push --set-upstream origin claude/hook-audit-gaps` | ALLOW |
| `-uf` bundle | `git push -uf origin claude/hook-audit-gaps` | DENY |
| `-fu` bundle | `git push -fu origin claude/hook-audit-gaps` | DENY |
| brace force | `git push -u{f,} origin claude/hook-audit-gaps` | DENY |
| trailing comment | `git push -u origin claude/hook-audit-gaps # x` | prompt |
| comment with a quote | `git push -u origin claude/hook-audit-gaps # it's` | prompt |
| heredoc on the push | `git push -u origin <b> <<EOF⏎x⏎EOF` | DENY |
| force after a heredoc | `cat <<EOF⏎x⏎EOF⏎git push -f origin <b>` | DENY |
| quoted branch | `git push -u origin '<b>'` | ALLOW (the same push) |
| `-C .` | `git -C . push -u origin <b>` | ALLOW (the same push) |
| substitution | `git push -u origin "$(git branch --show-current)"` | DENY |
| `env` wrapper | `env git push -u origin <b>` | prompt |
| `+` refspec | `git push -u origin +<b>` | prompt (documented) |
| brace adding `main` | `git push -u origin {<b>,main}` | DENY |
| brace adding a refspec | `git push -u origin <b>{,:main}` | DENY |
| single brace | `git push -u origin {<b>}` | DENY |
| another branch, manifest unchanged | `git push -u origin claude/evil` | prompt |
| worktree manifest edited to `claude/evil` | same | prompt |
| the edit staged | same | prompt |
| new untracked feature manifest | same | prompt |
| new staged feature manifest | same | prompt |
| `.git/refs/replace/<old blob>` → staged blob | same | ALLOW (needs a human-approved `.git` write; see above) |
| manifest committed | same | ALLOW (expected) |
| slug-named branch, fenceless untracked README | `git push -u origin evil2` | prompt |

### Orchestrator allowlist (S = the ledger's session, T = another session; HEAD)

| input | S | T | bash ran |
|---|---|---|---|
| `git commit -m "$(cat <<'EOF'⏎msg⏎EOF⏎)"` | prompt | prompt | commit |
| `… <<'EOF'⏎x⏎EOF)" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"` (B1) | DENY (role) | prompt | commit, BUILD |
| `… EOF;" ; ./feature-start.sh zz …` | DENY (role) | prompt | commit only |
| ``… EOF`" ; ./feature-start.sh zz …`` | DENY (role) | prompt | commit only |
| **`… EOF )" ; ./feature-start.sh zz ; echo "⏎EOF⏎)"`** | **prompt** | prompt | **commit, BUILD:./feature-start.sh** |
| **`… EOF\t)" ; ./feature-start.sh zz …`** | **prompt** | prompt | **commit, BUILD:./feature-start.sh** |
| `… EOF\r⏎)" ; ./feature-start.sh zz …` | prompt | prompt | commit only |
| `… ⏎\tEOF⏎)" ; ./feature-start.sh zz …` | prompt | prompt | commit only |
| `"$(cat <<"EOF"⏎x⏎EOF⏎)"` | prompt | prompt | commit |
| quoted body holding `$(./feature-start.sh)` and a backtick | prompt | prompt | commit only |
| unquoted delimiter, body `$(./feature-start.sh zz)` | DENY (role) | prompt | BUILD, commit |
| `<<-'EOF'` | DENY (role) | prompt | commit |
| `<< 'EOF'` | prompt | prompt | commit |
| `…)"x` | DENY (role) | prompt | commit |
| `…)";./feature-start.sh zz` | DENY (role) | prompt | commit, BUILD |
| `…)" && ./feature-start.sh zz` | DENY (role) | prompt | commit, BUILD |
| `…⏎) ; ./feature-start.sh zz ; echo "` | DENY (role) | prompt | commit only |
| body `)"` | prompt | prompt | commit |
| empty body | prompt | prompt | commit |
| two `-m` heredocs | DENY (role) | prompt | commit |
| `gh pr create … --body "$(cat <<'EOF'⏎x⏎EOF)" ; ./feature-start.sh zz …` | DENY (role) | prompt | BUILD |
| `git push -u origin "$(git branch --show-current)"` | prompt | prompt | push |
| `./feature-start.sh zz` | DENY (role) | prompt | BUILD |

### Function-level comparison, HEAD against origin/main (`invokes_build_script` and the git deny)

| input | HEAD build | main build | HEAD git deny | main git deny |
|---|---|---|---|---|
| `ls # x \⏎./run-plans.sh` | False | **True** | — | — |
| `ls # \⏎bash run-plans.sh --self x` | False | **True** | — | — |
| `git log -1 # note \⏎./run-p*.sh --self x` | False | False | — | — |
| `ls \⏎# x⏎./run-plans.sh` | True | True | — | — |
| `echo $(echo a)#b; git push -f origin y` | — | — | False | False |
| `echo $(echo a)#b; ./run-plans.sh` | False | **True** | — | — |
| `echo <(true)#b; git push -f origin y` | — | — | False | False |
| `echo $((1))#b; git push -f origin y` | — | — | False | False |
| `echo $(true)#x; cd /tmp && ls` (cd chain) | False | False | — | — |
| `a=(x)#b; ./run-plans.sh` | False | **True** | — | — |
| `a=(x)#b; git push -f origin y` | — | — | False | False |
| `echo x;#a \⏎./run-plans.sh`, `ls #\⏎./run-plans.sh`, `ls #a\⏎\⏎./run-plans.sh`, `ls # x \⏎./run-plans.sh --self x # y`, `ls #\⏎bash < run-plans.sh`, `ls #\⏎cat run-plans.sh \| unshare sh` | False (each) | **True** (each) | — | — |
| `x="$(cat <<EOF⏎"⏎EOF⏎)" ; git push -f origin y ; echo "` | — | — | False | False |
| `git push -f origin y` | — | — | True | True |

### End to end. `head` and `main` are the readable-ledger copies (`local` profile); `broken` is HEAD with an unreadable ledger

In the inputs, `\n` is a line break, `\t` a tab, `\r` a carriage return, and ˋ a backtick.

#### Batch c1 (git deny: bundles, braces, heredocs, comments)

| input | head | main | bash ran |
|---|---|---|---|
| `git push --force origin x` | DENY | DENY | push --force origin x |
| `git push -fu origin x` | DENY | prompt | push -fu origin x |
| `git push -uf origin x` | DENY | prompt | push -uf origin x |
| `git push -vfq origin x` | DENY | prompt | push -vfq origin x |
| `git push -uvf origin x` | DENY | prompt | push -uvf origin x |
| `git push -uof origin x` | prompt | prompt | push -uof origin x (`-o f`, no force) |
| `git push -fo x origin y` | DENY | prompt | push -fo x origin y |
| `git push -nf origin x` | DENY | prompt | push -nf origin x |
| `git push -4f origin x` | DENY | prompt | push -4f origin x |
| `git push -df origin x` | DENY | prompt | push -df origin x |
| `git push origin x -uf` | DENY | prompt | push origin x -uf |
| `git push origin x -- -uf` | DENY | prompt | push origin x -- -uf |
| `git -C . push -uf origin x` | DENY | prompt | -C . push -uf origin x |
| `git push -u -f origin x` | DENY | DENY | push -u -f origin x |
| `git push '-uf' origin x` | DENY | prompt | push -uf origin x |
| `git push \"-u\"f origin x` | DENY | prompt | push -uf origin x |
| `git push -u\\f origin x` | DENY | prompt | push -uf origin x |
| `git push -u{f,} origin x` | DENY | prompt | push -uf -u origin x |
| `git push -u{f..f} origin x` | DENY | prompt | push -uf origin x |
| `git push --forc{e,} origin x` | DENY | prompt | push --force --forc origin x |
| `git push --forc{e,{x,y}} origin x` | DENY | DENY | push --force --forcx --forcy origin x |
| `git reset --har{d..d}` | DENY | prompt | reset --hard |
| `git reset --hard{,}` | DENY | prompt | reset --hard --hard |
| `git {push,--force} origin x` | DENY | prompt | push --force origin x |
| `{git,push} --force origin x` | DENY | prompt | push --force origin x |
| `git push -{u,f} origin x` | DENY | prompt | push -u -f origin x |
| `git push -{u..f} origin x` | DENY | prompt | push -u -t … -f origin x |
| `git push -{a..z} origin x` | DENY | prompt | push -a … -z origin x |
| `git push --force{,} origin x` | DENY | prompt | push --force --force origin x |
| `git push --forc{e..e..1} origin x` | DENY | prompt | push --force origin x |
| `git push --forc{e..e..-1} origin x` | DENY | prompt | push --force origin x |
| `git push --forc{e..g..2} origin x` | DENY | prompt | push --force --forcg origin x |
| `git branch -D old {a,b}` | DENY | prompt | branch -D old a b |
| `git branch {-D,x} old` | DENY | prompt | branch -D x old |
| `git push -{f,} origin x{1..300}` | DENY | prompt | push -f - origin x1 … |
| `git push origin x{1..300} -f` | DENY | prompt | push origin x1 … -f |
| `git reset --hard x{1..300}` | DENY | prompt | reset --hard x1 … |
| `git clean{,} -fd` | DENY | prompt | clean clean -fd |
| `git cl{e,}an -fd` | DENY | prompt | clean clan -fd |
| `git c{l,}ean -fd` | DENY | prompt | clean cean -fd |
| `gi{t,} push -f origin x` | prompt | prompt | gi push … (not git) |
| `cat <<EOF\nx\nEOF\ngit push -f origin y` | DENY | prompt | push -f origin y |
| `cat <<EOF; git push -f origin y\nbody\nEOF` | DENY | DENY | push -f origin y |
| `cat <<E\"O\"F\nx\nEOF\ngit push -f origin y` | DENY | prompt | push -f origin y |
| `cat <<A <<B\nx\nA\ny\nB\ngit push -f origin z` | DENY | prompt | push -f origin z |
| `cat <<-EOF\n\tx\n\tEOF\ngit push -f origin y` | DENY | prompt | push -f origin y |
| `cat <<-EOF\n  EOF\ngit push -f origin y\nEOF` | prompt | prompt | — |
| `echo $(cat <<EOF\nx\nEOF) ; git push -f origin y\nEOF\n)` | DENY | prompt | push -f origin y |
| `cat <(cat <<EOF\nx\nEOF) ; git push -f origin y\nEOF\n)` | DENY | prompt | push -f origin y |
| `echo ˋcat <<EOF\nx\nEOFˋ ; git push -f origin y\nEOF\nˋ` | DENY | DENY | push -f origin y |
| `(cat <<EOF\nx\nEOF) ; git push -f origin y\nEOF\n)` | DENY | prompt | — |
| `echo ˋcat <<EOFˋ\ngit push -f origin y\nEOF` | DENY | DENY | push -f origin y |
| `echo $(cat <<EOF)\ngit push -f origin y\nEOF` | prompt | prompt | — |
| `echo $(cat <<EOF\nEOF\n) ; git push -f origin y` | DENY | prompt | push -f origin y |
| `git push origin main # '` | DENY | prompt | push origin main |
| `git push -f origin x # it's` | DENY | prompt | push -f origin x |
| **`echo $(echo a)#b; git push -f origin y`** | **prompt** | prompt | **push -f origin y** (E3) |
| `echo \"$(echo a)\"#b; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo x>#y; git push -f origin z` | prompt | prompt | — |
| `echo x\|#y\ngit push -f origin z` | DENY | prompt | push -f origin z |
| `echo a ;#b\ngit push -f origin z` | DENY | prompt | push -f origin z |
| `ls #\\\ngit push -f origin z` | DENY | prompt | push -f origin z |
| `echo \"ˋecho \" #\"ˋ\"; git push -f origin y` | prompt | prompt | push -f origin y (documented) |
| `echo $$'a\\' ; git push -f origin y #'` | prompt | prompt | push -f origin y (not a regression) |
| `echo ${x#*}; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo ${#x}; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo ${x:-}#; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo ${x/a/}#b ; git push -f origin y` | DENY | prompt | push -f origin y |
| `x=\"$(cat <<'EOF'\nhi\nEOF\n)\"#c; git push -f origin y` | DENY | prompt | push -f origin y |
| `git commit -m \"$(cat <<'EOF'\nmsg \" odd\nEOF\n)\" ; git push -f origin y` | DENY | prompt | commit, push -f origin y |
| `git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\" # ; git push -f origin y` | prompt | prompt | commit only |
| `git commit -m \"$(cat <<'EOF'\nmsg\n EOF\n)\" ; git push -f origin y\nEOF\n)\"` | prompt | prompt | commit only |
| `git commit -m \"$(cat <<-'EOF'\nmsg\n\tEOF\n)\" ; git push -f origin y` | DENY | DENY | commit, push -f origin y |
| `git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n  )\" ; git push -f origin y` | DENY | DENY | commit, push -f origin y |
| `echo a\\\n#b ; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo a \\\n#b ; git push -f origin y` | DENY | prompt | — |
| `echo a\r#b ; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo a\r; git push -f origin y` | DENY | DENY | push -f origin y |
| `echo ˋ#xˋ; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo ˋecho #ˋ; git push -f origin y` | DENY | prompt | push -f origin y |
| `echo \\ˋ#ˋ; git push -f origin y` | DENY | prompt | — |
| `cat <<EOF $(echo a\ngit push -f origin y\nEOF\n)` | DENY | prompt | push -f origin y |
| `cat <<EOF \"$(echo a\nEOF\n)\"\ngit push -f origin y` | DENY | prompt | — |
| `cat <<EOF\nx\nEOF\n\ngit reset --hard` | DENY | prompt | reset --hard |
| `cat <<EOF\nx\nEOF \ngit reset --hard\nEOF` | prompt | prompt | — |
| `cat <<EOF\r\nx\nEOF\r\ngit reset --hard` | DENY | prompt | reset --hard |
| `cat << EOF\nx\nEOF\ngit reset --hard` | DENY | prompt | reset --hard |
| `cat <<\\EOF\nx\nEOF\ngit reset --hard` | DENY | prompt | reset --hard |
| `cat <<''\nx\n\ngit reset --hard` | DENY | prompt | reset --hard |
| `cat <<\"\"\nx\n\ngit reset --hard` | DENY | prompt | reset --hard |
| `let x=1<<2\ngit reset --hard\n2` | DENY | DENY | — |
| `[[ a<<b ]]\ngit reset --hard\nb` | prompt | prompt | — |
| `echo $((1<<2))\ngit reset --hard\n2` | DENY | DENY | reset --hard |
| `a[1<<2]=5\ngit reset --hard\n2]=5` | DENY | DENY | reset --hard |
| `echo a[1<<2]\ngit reset --hard\n2]` | DENY | DENY | — |
| `echo [ <<EOF\nx\nEOF\ngit reset --hard` | DENY | DENY | reset --hard |
| `echo $[ ] ; cat <<EOF\nx\nEOF\ngit reset --hard` | DENY | prompt | reset --hard |
| `echo '((' ; cat <<EOF\nx\nEOF\ngit reset --hard` | DENY | prompt | reset --hard |
| `case x in x) cat <<EOF\nx\nEOF\n;; esac; git reset --hard` | DENY | DENY | reset --hard |
| `cat <<EOF \| git push -f origin y\nx\nEOF` | DENY | DENY | push -f origin y |
| `f() { cat <<EOF\nx\nEOF\n}; git reset --hard` | DENY | DENY | reset --hard |

#### Batch c4 (a `#` glued after an operator or `)`, and comment continuations)

| input | broken | head | main | bash ran |
|---|---|---|---|---|
| `(ls)#b; ./run-plans.sh` | prompt | prompt | prompt | — |
| `(ls)#b; git push -f origin y` | prompt | prompt | prompt | — |
| `case x in x)#b ;; esac; ./run-plans.sh` | DENY | DENY | prompt | — |
| `case x in x)#b\n;; esac; git push -f origin y` | DENY | DENY | DENY | push -f origin y |
| **`a=(x)#b; ./run-plans.sh`** | **prompt** | prompt | prompt | **BUILD:./run-plans.sh** (E3) |
| **`a=(x)#b; git push -f origin y`** | prompt | **prompt** | prompt | **push -f origin y** (E3) |
| `echo @(x)#b; ./run-plans.sh` | DENY | prompt | prompt | — |
| `ls &#b\n./run-plans.sh` | DENY | prompt | prompt | BUILD:./run-plans.sh |
| `echo a 2>&1#b; ./run-plans.sh` | DENY | prompt | prompt | BUILD:./run-plans.sh |
| `echo a 2>&1#b; git push -f origin y` | DENY | DENY | prompt | push -f origin y |
| `echo a >&2#b; git push -f origin y` | DENY | DENY | prompt | push -f origin y |
| `ls\|\|#b\n./run-plans.sh` | DENY | prompt | prompt | — |
| **`echo x;#a \\\n./run-plans.sh`** | **prompt** | prompt | prompt | **BUILD:./run-plans.sh** (E2) |
| **`ls #\\\n./run-plans.sh`** | **prompt** | prompt | prompt | **BUILD:./run-plans.sh** (E2) |
| `ls #\\\ngit push -f origin y` | DENY | DENY | prompt | push -f origin y |
| **`ls #a\\\n\\\n./run-plans.sh`** | **prompt** | prompt | prompt | **BUILD:./run-plans.sh** (E2) |
| `echo 'a#b \\\n./run-plans.sh'` | prompt | prompt | prompt | — |
| `ls # it's \\\n./run-pl?ns.sh` | DENY | prompt | prompt | BUILD:./run-plans.sh |
| **`ls # x \\\n./run-plans.sh --self x # y`** | **prompt** | prompt | prompt | **BUILD:./run-plans.sh** (E2) |

(The build-script judge speaks only for the `broken` column. In `head` and `main` a build
script is a prompt by design.)

#### Batch c6 (a body line that starts with the delimiter inside `$(…)`; E1)

| input | head | main | bash ran |
|---|---|---|---|
| **`git commit -m \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **commit, push -f origin y** |
| **`git commit -m \"$(cat <<'EOF'\nx\nEOF\t)\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **commit, push -f origin y** |
| `git commit -m \"$(cat <<'EOF'\nx\nEOF  ;)\" ; git push -f origin y ; echo \"\nEOF\n)\"` | prompt | DENY | — |
| **`git commit -m \"$(cat <<'EOF'\nx\nEOF x)\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **commit, push -f origin y** |
| `git commit -m \"$(cat <<'EOF'\nx\nEOF \n)\" ; git push -f origin y` | DENY | DENY | — |
| **`git commit -m \"$(cat <<'EOF'\nx\nEOFS)\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **commit, push -f origin y** |
| `echo $(cat <<EOF\nx\nEOF ) ; git push -f origin y\nEOF\n)` | prompt | prompt | push -f origin y |
| `echo $(cat <<EOF\nx\nEOF ; git push -f origin y)\nEOF\n` | prompt | prompt | — |
| `echo ˋcat <<EOF\nx\nEOF ˋ ; git push -f origin y\nEOF\nˋ` | DENY | DENY | push -f origin y |
| `cat <<EOF\nx\nEOF )\ngit push -f origin y\nEOF` | prompt | prompt | — |
| `(cat <<EOF\nx\nEOF )\ngit push -f origin y\nEOF\n)` | DENY | DENY | — |

#### Batch c7 (which run-on lines bash 5.2 ends at)

| input | head | main | bash ran |
|---|---|---|---|
| `echo \"$(cat <<'EOF'\nx\nEOFS\n)\" ; git push -f origin y ; echo \"\nEOF\n)\"` | prompt | DENY | — |
| `echo \"$(cat <<'EOF'\nx\nEOF x\n)\" ; git push -f origin y ; echo \"\nEOF\n)\"` | prompt | DENY | — |
| **`echo \"$(cat <<'EOF'\nx\nEOFxyz ; true)\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **push -f origin y** |
| **`echo \"$(cat <<'EOF'\nx\nEOF a b c)\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **push -f origin y** |
| **`echo \"$(cat <<'EOF'\nx\nEOF'q')\" ; git push -f origin y ; echo \"\nEOF\n)\"`** | **prompt** | DENY | **push -f origin y** |
| `echo \"$(cat <<'EOF'\nx\nEO)\" ; git push -f origin y ; echo \"\nEOF\n)\"` | prompt | DENY | — |
| `echo \"$(cat <<'EOF'\nx\n EOF)\" ; git push -f origin y ; echo \"\nEOF\n)\"` | prompt | DENY | — |
| `echo \"$(cat <<'EOF'\nx\nEOF x\nEOF\n)\" ; git push -f origin y` | DENY | DENY | push -f origin y |

#### Batch c2 (build-script judge, unreadable ledger, HEAD)

| input | broken | bash ran |
|---|---|---|
| `./run-plans.sh --self x` | DENY | BUILD |
| `ls #\n./run-plans.sh --self x` | DENY | BUILD |
| **`ls # x \\\n./run-plans.sh`** | **prompt** | **BUILD** (E2) |
| `./run-pla\\\nns.sh --self x` | DENY | BUILD |
| `./run-p\\\n*.sh --self x` | DENY | BUILD |
| `./run-pl\\\\ans.sh` | prompt | — |
| `./run-plans.s[h] x` | DENY | BUILD |
| `./run-plans.s[!x] x` | DENY | BUILD |
| `./run-plans.s[[:alnum:]] x` | DENY | BUILD |
| `./run-plans.s[]h] x` | DENY | BUILD |
| `./run-plans.s[]] x` | DENY | — |
| `./run-plans.[r-t]h x` | DENY | BUILD |
| `./run-plans.s? x` | DENY | BUILD |
| `./run-plans.s?(h) x` | DENY | — |
| `./*plans.sh x` | DENY | BUILD |
| `./r*s.sh x` | DENY | BUILD |
| `./?un-plans.sh x` | DENY | BUILD |
| `./[q-s]un-plans.sh x` | DENY | BUILD |
| `./[^a]un-plans.sh x` | DENY | BUILD |
| `./[[:lower:]]un-plans.sh x` | DENY | BUILD |
| `./run-plans.sh< /dev/null` | DENY | BUILD |
| `bash<run-plans.sh` | DENY | BUILD |
| `bash 0<run-plans.sh` | DENY | BUILD |
| `bash 0<>run-plans.sh` | DENY | BUILD |
| `bash < run-pla[n]s.sh` | DENY | BUILD |
| `bash < run-p[^x]ans.sh` | DENY | BUILD |
| `bash < ./*plans.sh` | DENY | BUILD |
| `bash < ./r?n-plans.sh` | DENY | BUILD |
| `bash -s < run-plans.s[h]` | DENY | BUILD |
| `cat run-plans.sh \| sort \| sh` | DENY | BUILD |
| `cat run-plans.sh \| sort --com=sh -S1b` | DENY | — |
| `cat run-plans.sh \| sort --compress-prog sh -S1b` | DENY | — |
| `cat run-plans.sh \| /usr/bin/sort` | DENY | — |
| `cat run-plans.sh \| tr a a \| sh` | DENY | BUILD |
| `cat run-plans.sh \| cut -c1- \| uniq \| sh` | DENY | BUILD |
| `grep -l x run-plans.sh \| xargs sh` | DENY | BUILD |
| `ls \| grep plans \| xargs sh` | prompt | BUILD (name built at run time; not a regression) |
| `ls \| grep 'run-pl.ns' \| xargs -n1 sh` | prompt | BUILD (the same) |
| `ls \| grep -E 'run-p' \| sh` | DENY | — |
| `ls -1 \| head -1 \| xargs sh` | prompt | first file in the directory |
| `find . -name 'run-pl[a]ns.sh' -exec sh {} \\;` | DENY | BUILD |
| `find . -name 'run-plans.s?' -exec {} \\;` | DENY | BUILD |
| `find . -regex '.*run-pl.ns.sh' -exec {} \\;` | DENY | BUILD |
| `find . -newer /nonexistent -o -name x -exec sh {} \\;` | DENY | — |
| `find . -perm -u+x -type f -exec {} \\;` | DENY | BUILD (all) |
| `sh ./*` | DENY | BUILD |
| `sh ./r*` | DENY | BUILD |
| `awk 'BEGIN{system(\"./run-pl\" \"ans.sh\")}'` | prompt | BUILD (name built at run time) |
| `awk 'BEGIN{system(\"./run-pla\"\"ns.sh\")}'` | prompt | BUILD (the same) |
| `awk 'BEGIN{x=\"./run-pla\";system(x \"ns.sh\")}'` | prompt | BUILD (the same) |
| `sed -n '1e ./run-pl\"\"ans.sh' README.md` | prompt | — |
| `echo ./run-pl ans.sh \| tr -d ' ' \| sh` | DENY | BUILD |
| `echo ./run-plaXns.sh \| tr X ' ' \| sh` | DENY | — |
| `echo ./run-plbns.sh \| tr b a \| sh` | prompt | BUILD (name built at run time) |
| `printf './run-pl%sns.sh' a \| sh` | prompt | BUILD (the same) |
| `printf %s ./run-pla ns.sh \| sh` | prompt | BUILD (the same) |
| `echo ./run-pla''ns.sh \| sh` | DENY | BUILD |
| `echo './run-pla''ns.sh' \| sh` | DENY | BUILD |
| `echo ./run-pla\\ns.sh \| sh` | DENY | BUILD |
| `echo cnVuLXBsYW5zLnNo \| base64 -d \| sh` | DENY | — |
| `GIT_EDITOR=./run-pl[a]ns.sh git commit` | DENY | commit |
| `GIT_EDITOR=./run-pl?ns.sh git var GIT_EDITOR` | DENY | var |
| `X=./run-pl Y=ans.sh sh -c '$X$Y'` | DENY | BUILD |
| `x=./run-pl; ${x}ans.sh` | DENY | BUILD |
| `env ./run-pl[a]ns.sh` | DENY | BUILD |
| `env -S './run-pl?ns.sh'` | DENY | — |
| `git grep -nO./run-plans.sh x` | DENY | grep |
| `git grep --open-files=./run-plans.sh x` | DENY | grep |
| `git grep -n -O ./run-plans.sh x` | DENY | grep |
| `git grep -nO ./run-plans.sh x` | DENY | grep |
| `git grep -O./run-pl?ns.sh x` | DENY | grep |
| `git log --ext=./run-plans.sh -1` | DENY | log |
| `git -c core.pager=./run-plans.sh log -1` | DENY | log |
| `git -c core.pager=./run-pl?ns.sh log -1` | DENY | log |
| `git log -1 --format=%h ; ./run-p*.sh` | DENY | log, BUILD |
| `git log -1 #\n./run-p*.sh` | DENY | log, BUILD |
| `cat <<EOF\nx\nEOF\n./run-p*.sh --self x` | DENY | BUILD |
| `ls '#' ; ./run-p*.sh` | DENY | BUILD |
| `ls a#b ; ./run-p*.sh` | DENY | BUILD |
| `cat run-plans.sh \| sh -n` | DENY | — |
| `bash -n run-plans.sh` | ALLOW | — |
| `bash -n run-plans.sh ; bash run-plans.sh` | DENY | BUILD |
| `sed -n 1p run-plans.sh` | ALLOW | — |
| `cat run-plans.sh` | ALLOW | — |

## What held

The `-fu`/`-uf` bundles and every brace spelling tried were denied in both profiles. This
includes nested groups, sequences, steps and the past-the-cap overflow. A command after a
placed heredoc body is denied however the operator is spelled. A quote in a comment no longer
hides a push. `${…#…}`, `$#`, `a\r#b` and the `#` inside a backtick read as bash reads them.
The build-script judge closed every redirect, bracket, filter, assignment and git-exec-flag
shape it claims. The cloud own push is not approved by any uncommitted or staged edit to the
manifest. The orchestrator gets the role denial for every B1 run-on spelling except E1's
blank-or-word-character forms.
