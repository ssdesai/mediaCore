# Notes: hook-audit-gaps

Rulings, with a one-line reason each. The coordinator's come first; the implementer
appends its own under "Build rulings" as it makes them.

## Source

A security audit in humanNetworkMap, auditing its subtree pull of agentTooling main
9b8059a, found three gaps in `hooks/allow-repo-commands.sh`. The pull did not cause any
of them. The owner asked for all three to be fixed.

- **B1 (High)**: heredoc terminator. The whole-argument `"$(cat <<'EOF' … EOF)"` reading
  (`HEREDOC_ARGUMENT_RE`, `\n\2\n?\s*\)\"`) accepts `EOF)` as the end of the body, but
  bash ends a heredoc only at a line holding exactly the delimiter (tabs stripped under
  `<<-`). Exploit as reported:
  `git commit -m "$(cat <<'EOF' ... EOF)" ; ./agentTooling/feature-start.sh zz ; echo "\nEOF\n)"`
  (with real line breaks), which should be denied outright and only prompts. Same for
  `gh pr create --body "$(cat <<'EOF' …)"`.
- **B2 (Low)**: `chain_tokens` drops a quoted or escaped digit before a redirect, so
  `git push origin <own-branch> "2">/dev/null` hides a push of a branch named `2`.
- **B3 (Low)**: `own_push_allowed` reads `branches[0]` from the working tree, so an
  uncommitted edit to the manifest makes any current branch the started feature's, and
  its push is approved silently.

## Coordinator rulings

1. **B3: read `branches[0]` from HEAD, not refuse on a dirty manifest.** `own_push_allowed`
   calls `started_feature(..., tree="HEAD")`, the committed-tree reading that function
   already has for the off-branch case. Why: a commit is a write that goes to the human,
   so HEAD is human-gated while the working tree is not; HEAD is also what the push sends.
   Refusing on a dirty manifest would add a second probe (`git status`/`diff`) and still
   trust a tree that a later edit could change between the probe and the read; reading
   the commit has no such window. Legitimate pushes are unaffected: `feature-start.sh`
   commits the manifest in `<slug>: start` before any push.
2. **B1 and B2 wait for PR #139.** #139 (orchestration-record-fixes, round 14 at the
   time) rewrites the hook's tokenizer, redirect and heredoc reading (`QuotedWord`,
   `is_bare_descriptor`, `is_heredoc_operator`, `judged_tokens`, `fails_closed`). Its
   implementer reported B2 already fixed on its head (b96b3b4) and B1's short form
   (without the trailing `echo "\nEOF\n)"`) already denied for an orchestrator on main.
   So: red tests now, B3 now, and B1/B2 fixed after #139 merges, only where its code
   still fails our tests. If B1 cannot be made red on main with the audit's exact
   exploit, it is recorded here as not reproduced, with the probe output, and the code
   is not changed for it.
3. **`git push -fu origin <branch>` is taken.** #139 recorded it as a follow-up it is not
   fixing; it is the same class (a hook gap letting a force push through to a prompt)
   and the owner's "fix all three" covers closing these gaps. It must be denied like
   `-f`, `--force` and `+<ref>`.
4. **Tests go in the existing files.** B1 and B2 shapes in `self/tests/allow-repo-commands.sh`
   (B1 under an orchestrator record where the deny is the role's) or
   `self/tests/hook-orchestrator-role.sh`; B2, B3 and `-fu` in
   `self/tests/hook-cloud-profile.sh`, beside the `2>&1` push rows.

5. The owner added F1, F2, A, B and C from #139's audits; trade-offs as recorded in the build
   rulings (F1 and F2 from #139's independent audit, whose text is not in the repo; A, B and C
   from `self/features/orchestration-record-fixes/escalations/14-audit-opus.md`).

6. **Phase 3, two items and a self-audit.** (a) A build script fed through input redirection
   on the unreadable-ledger path (`bash < agentTooling/run-plans.sh`, `<>`, `N<`) must get the
   deny a pipe into an interpreter gets, with that reason and no new one. (b) The cloud's
   refusal of `git push -u origin "$(git branch --show-current)"` is right and the
   documentation was wrong: a push that is approved silently names its branch as a literal,
   so the hook can check it against `branches[0]`; every place that documented the
   substitution spelling now documents `git push -u origin <branch>`, and no verdict changes.
   (c) Before the commit the implementer audits the whole feature diff as the auditor will;
   a bypass of a fix's own rule gets a red row and a fix, a different class is recorded.

7. **Round 2's design rule: judge both readings.** Round 1 escalated (review item 1; audit
   E1, E2, E3), and each finding was an edge of a place where the hook emulated bash more
   finely than before. The feature this hook's reading came from took 15 review rounds that
   way. So, for the rework: *wherever the hook must decide whether a stretch of text is
   hidden from the deny side (a comment, a heredoc body, a deleted continuation), and bash
   could read it differently, the deny side judges BOTH readings and denies if either
   denies. It hides text only where the reading is certain. Prefer removing a special case
   over refining it. An over-deny on an exotic spelling is acceptable and gets documented; a
   prompt where bash runs a denied command is not.* A differential check against bash 5.2
   (every row of both escalation files, and a generated corpus) decides what "bash runs"
   means; its harness is not committed, and its summary is under "Round 2" below.

## Build rulings

Phase 1 of 2 (tests red, B3 fixed; B1, B2 and `-fu` wait for PR #139).

1. **B1 reproduced on main; bash's real terminator.** Probed on bash 5.2.21 with
   `printf '%s\n' "$(cat <<'EOF'` ⏎ `x` ⏎ `EOF)" ; echo SMUGGLED ; echo "` ⏎ `EOF` ⏎ `)"`:
   bash warns `here-document ... delimited by end-of-file (wanted 'EOF')` and **runs**
   `echo SMUGGLED` (output `x`, `SMUGGLED`, then the stray `EOF`/`)`); the short form without the
   trailing `echo "⏎EOF⏎)"` also runs its smuggled command. So `EOF)` is body text to bash, as
   the audit said. The hook, for an orchestrator session (fixtures as `hook-orchestrator-role.sh`,
   local and cloud, `./feature-start.sh` and `./agentTooling/feature-start.sh`, `git commit -m`
   and `gh pr create --body`): the full form is **silent (a prompt)**, not denied — so B1
   reproduces on main and H26 is red (8 rows); the short form IS denied (the role reason),
   matching the other implementer's report, and the bare `./feature-start.sh zz` is denied.
2. **Tests placed per coordinator ruling 4**: B1 as H26 in `hook-orchestrator-role.sh` (both
   fixtures, both profiles, both heads, plus "another session is not the role denial");
   B2, `-fu`/`-uf` rows in the T table of `hook-cloud-profile.sh` beside the `2>&1` rows; B3 as
   Q5 there (a committed manifest naming another branch, then an uncommitted edit; the
   committed edit; an uncommitted edit away from a committed one).
3. **`-fu` table rows**: `(D, D)` for `-fu`/`-uf` on the current branch and `-fu origin x`.
   Red now: local (all three) and cloud (current branch only; `x` is already refused there).
4. **B3 fix**: `own_push_allowed` calls `started_feature(real_top, features_dir, branch,
   tree=GIT_HEAD)`; the function's `tree` path already strips the `HEAD:` prefix git grep
   prints and reads the fence with `git show HEAD:<rel>`. `GIT_HEAD` is the existing constant.
   Q5 is green; the existing T/Q rows keep their verdicts.
5. **Docs**: the committed-at-HEAD reading is stated in `hooks/README.md` (own-branch push
   list), `CONVENTIONS.md` ("Approved silently") and the `self/tests/README.md` rows for both
   test files.

Phase 2 (after PR #139 and #143 merged at f5f98d9).

6. **Re-run on the merged tree.** Red before any phase-2 edit: `-fu`/`-uf` (5 rows in
   `hook-cloud-profile.sh`) and H26 (8 rows in `hook-orchestrator-role.sh`). **B2 was already
   green** after #139 (`is_bare_descriptor`): no hook change for it, and the three B2 rows stay as
   regression rows. B3/Q5 stayed green.
7. **One place computes a body's span: `heredoc_body_span(text, start, delimiter, strip_tabs)`**
   (F1 reuses it: `comment_and_heredoc_free`/`judged_text` and `heredoc_argument_at` both ask it).
   The terminator is the first line holding the delimiter alone (tabs stripped under `<<-`). Where
   bash 5.2 may end a `$(…)` heredoc and run the rest of the line — a body line whose delimiter
   runs on into an operator character (`EOF)`, `EOF;`) — or where no terminator exists, the body is
   **unplaced**: the caller reads the text as commands, never as a message. A blank or word
   character after the delimiter (`EOF `, `EOFS`) is plain body (H21's `EOF ` row requires it).
8. **B1 on the allowlist and the build-script judge.** `ORCHESTRATOR_HEREDOC_RE` and
   `HEREDOC_ARGUMENT_RE` are gone: `heredoc_argument_at(text, at, strict)` matches the head, asks
   the span, and requires the `)"` after the terminator (strict, for the orchestrator: a quoted
   delimiter, no `<<-`, `)"` on the next line). The audit's H26 exploit is now denied with the role
   reason (8 rows green). The deny side's quote-aware reading already read the exploit's tail as
   commands, so no other B1 change was needed there.
9. **F1: read after the body, not fail-closed-deny.** `comment_and_heredoc_free` walks the line once
   (quotes, escapes, comments, every unquoted `<<` that is not `<<<`, multiple heredocs per line) and
   returns it without comments and placed bodies; `judged_tokens`, `command_words`, `chains_chdir`
   and the assignment deny read that. So `true;<<EOF cat⏎x⏎EOF⏎git push origin main`, `&<<`,
   `|<<`, `&&<<`, `||<<`, `(<<`, the chained-cd form and the plain `cat <<EOF⏎x⏎EOF⏎git push origin
   main` are all hard denies. The plain spelling was a prompt on both trees and is now a deny (the
   coordinator's instruction); its T row in `hook-cloud-profile.sh` changed from `P, P` to `D, D`.
   An unplaced body reads the raw line (bodies as commands): a deny may fire on text bash would take
   for a body, which is the price of never hiding a command. `chains_chdir` instead returns False
   there (it never denies on a guess). The approval side needed no change: a line with a git word and
   `<<` is already never approved (`fails_closed`).
10. **`-fu`/`-uf`:** `bundles_push_force(token)` in `git_mutates`: a short-flag cluster is a force if
    `f` comes before any `o` (`-o` takes the rest of the word as its value); `-uq`, `-ofoo`, `-u`
    keep their prompt. Both profiles, since `git_mutates` is the both-profile deny.
11. **F2: expand, never skip.** `git_commands` no longer skips a command holding a brace; it judges
    `expanded_argv(words)` (the approval analysis's own expansion; a group it does not read is
    judged as the word written). `git branch -D old {a,b}` and the `';'`/`\;`/`'|'` forms are
    denied. **Trade-off:** `git branch {-a,new}` and `git worktree {add,list} x` were pinned as
    prompts ("the deny expands no braces"); they are denies now, and their rows moved from
    `GIT_NOT_DENIED`/`BRACE_PROMPT` in `allow-repo-commands.sh` to `GIT_AUDIT_DENY`.
12. **A: strip the comment, do not refuse the unlexable line.** Of the audit's two options, the
    deny side now reads `judged_text` (an unquoted word-initial `#` through the end of its line is
    dropped), so `git push origin main # '` is the push it is. Why: it reads the line as bash does,
    fixes the git deny and the build-script judge at once, and adds no new denies for lines that
    merely do not lex. A `#` inside a word (`a#b`) stays `never_judged`. Costs: a `cd` chain with a
    trailing comment (`cd x && ls # note`) is now the chained-cd deny (it was unjudged), and so is
    any git deny on a line with a comment; the `# read it` row of `CHAINED_NOT_APPROVED` moved to
    `DENY` and a mid-word `a#.py` row took its place. Not stripped: the line holds `$'`, or its
    quotes never close outside a comment (read raw, as before).
13. **B: build-script rewrite denies on the unreadable-ledger path.** `invokes_build_script` deletes
    a line continuation before reading (`./run-pla\⏎ns.sh`), scans an unlexable line for patterns as
    well as names unless it holds `<<` (H4 pins the heredoc case), and counts a pattern in an exempt
    reader as a name when the line also launches (`ls run-p*.sh | sh`, `bash -c '…'`): all role
    denies, which do not decay after `OPAQUE_REWRITE_ATTEMPTS`.
14. **C: the coarse closure, on that path only.** `mentions_build_script_pattern(word)`: a build
    script's name or a pattern for one in the word or any blank-separated piece of it (also with
    quote/paren/brace characters stripped; find's `{}` excluded) in any argument of a non-exempt
    command is a run (`unshare`, `setpriv`, `prlimit`, awk `system()`, sed `e`, `git -c alias.x=!…`
    all denied). **Over-denies, for an orchestrator whose ledger is unreadable only:** a bare glob
    given to a non-exempt command — `cp * dest`, `tar -cf x.tar *.sh`, `jq . *` — since `*` could
    expand to a build script's name; a glob with a directory or a suffix that matches no build
    script (`*/report.json`, `tests/*.py`) is fine. The exempt commands (readers, read-only git, gh
    pr/issue, `sed -n Np`, `bash -n`) keep their pass. A comment that mentions a build script's name
    is no longer a run (`ls # ./run-plans.sh`), as bash runs nothing there.
15. **Tests written after the fix, not before, for B/C/F1/F2/A.** The coordinator's extension came
    mid-build; the F1/F2/A rows were run against the old hook first (probe: prompt, prompt, deny-decay
    as described), but the H6-H8 build-script and span rows were added with the fix and were never red.
    Rows changed rather than weakened: the three above and the plain-heredoc T row.
16. **Out of scope, as ruled:** `ls ';' ; ./agentTooling/feature-start.sh foo` decaying from an
    escalating deny to a prompt (`quoted_separator_word`). `report.py`'s unchecked `report` path
    went to `self/BACKLOG.md`. No item exceeded ~150 lines of hook code.

Phase 3 (redirect-fed build scripts, the literal-branch push doc, the self-audit).

17. **(a) was red: C did not catch it.** Run against 8424c16's hook before any edit, 28 of the
    31 inherited H9 rows failed — every `<`, `<>`, `N<`, `{fd}<` spelling, glued, with `sh`,
    `zsh`, `ksh93`, `env bash`, a glob, the redirect before the program, and each build
    script. `command_words` drops a redirect's target, so no judge ever saw the name. Green
    already: `./run-plans.sh < /dev/null` (the name is the program) and `cat run-plans.sh |
    bash`. End to end in a checkout with an unreadable ledger they were prompts.
18. **(a) fix: the fed file is read like a name in an exempt reader** (`fed_files`,
    `REDIRECT_INPUT_FILE_OPS`). It is a run once the line holds a command that may launch, so
    `bash < run-plans.sh` gets `orchestrator_reason` — the piped script's deny, compared for
    equality in H14 — while `cat < run-plans.sh`, `wc -l <`, `sort <` and `sed -n 5p <` stay
    reads. `bash -n < run-plans.sh` IS a run: with no file after `-n` it is not the exempt
    form, exactly as `cat run-plans.sh | bash -n` already was not (the inherited test had it
    as no run; that row moved). The previous implementer's uncommitted H9 block was kept with
    that row moved, its comment rewritten to the rule built, and quoted, tab, continuation,
    `exec N<` and `source /dev/stdin <` rows added.
19. **(b): documentation only.** `ORCHESTRATION.md` (the allowlist paragraph),
    `hooks/README.md` (the fail-closed paragraph, the allowlist table's git-writes row, the
    tokenizer paragraph) and the hook's `ORCHESTRATOR_ALLOWLIST_TEXT`, `fails_closed` and
    `orchestrator_words` docstrings name `git push -u origin <branch>`. The tokenizer still
    reads the substitution as a pushed branch (H15's row stays: it is on the allowlist, then
    the cloud's push rule refuses it), and the docs say so. No test asserted the old text.
    R7 pins the cloud refusal with its reason (`push only \`<branch>\``) and the literal push
    as approved.
20. **Self-audit: a `#` inside a word no longer leaves the line unjudged.** Ruling 12 kept it
    unjudged; the probes showed that makes A a one-character bypass (`git push --force origin
    x a#b`, `echo $# ; git push …` were prompts), so it is A's class and is closed: the
    walk's text has no comment left, and `command_words` hides the remaining `#` from
    `never_judged`. `never_judged` itself is unchanged, so the rewrites and the chained-`cd`
    deny keep their guard (`cd x && ls a#b` stays a prompt, its pinned rows untouched).
21. **Self-audit: the walk reads a comment only where bash starts one.** Not after an escaped
    blank or operator (`a\ #`, `\;#`), not after a carriage return, not inside `${…}`; inside
    backticks only to the closing backtick; and `$'…'` is walked as the quote it is instead
    of sending the whole line back unread (`git push … # $'` was a prompt). The first two
    were regressions of phase 2 on the unreadable-ledger path: main's text scan denied `echo
    a\ # ; ./run-plans.sh`, phase 2's comment stripping hid it.
22. **Self-audit: a body is placed only where bash reads one there.** A `<<` after `((` or
    `$[`, in a subscript or in `${…}` may be a shift (bash 5.2 ran the "body"); a delimiter
    holding a backtick, `$(`, `$"`, `$'` or a carriage return is read differently by bash; a
    substitution opening between the operator and the end of its line is read through first.
    Each leaves the body unplaced, and an unplaced line is now read with its comments
    removed (it was read raw, so one comment made it unjudged).
23. **Self-audit: `EOF)` is read both ways inside a substitution, and as body outside one.**
    `heredoc_body_span(…, run_on=)`; `judged_texts` returns every reading and `command_words`
    judges them all. Probed on bash 5.2: `$(…)`, `<(…)` and backticks end the body at the
    run-on line and run the rest; the main parser (a plain subshell included) does not. A
    backtick joined `HEREDOC_RUN_ON_CHARS` (`EOF\`` ended a backtick heredoc and was read as
    body). The whole-argument `"$(cat <<'EOF' …)"` stands as one empty word on the deny side
    (quoted delimiter, nothing substituted before it), so B1's shape with a `"` in the body
    is denied; before, the flat quote reading made that line unlexable.
24. **Self-audit: the git deny has its own brace expansion** (`brace_words`,
    `brace_sequence`). `expanded_argv` returns None for a nested group, and reads no
    sequence, so `git push --forc{e,{x,y}}` fell to the brace REWRITE (which decays to an
    ask) and `--forc{e..e}`, `reset --har{d..d}`, `checkout -{b..b} x` were prompts. Past
    `MAX_BRACE_WORDS` a git command is judged as `GIT_UNREADABLE_ARGS` — denied, not passed
    on. **Cost:** a git command with a brace word past the cap, or a nested group, is the git
    deny where it was the brace rewrite; a quoted brace group is expanded, as it already was.
25. **Self-audit: the build-script judge's neighbours (unreadable-ledger path only).**
    Beside a reader that names a build script any non-filter command launches (`| unshare sh`,
    `| ash`); bracket expressions read as `?`; the text scan splits at operators; an
    assignment's value is read for a pattern; git's exec flags by prefix and in a cluster
    (`orchestrator_option_hits`). **Costs, all prompt → role deny:** `wc -l run-plans.sh &&
    pytest`, `bash -n < run-plans.sh`, `VAR=<glob> cmd`; stated in `hooks/README.md`.
26. **Size.** 158 code lines added or rewritten in the hook and 39 replaced, 119 net
    (comments and docstrings apart) — at the brief's "about 150", which is why the wrappers
    and abbreviations below were recorded and not built.
27. **Tests after the probes, before the hook edit.** Every phase-3 row was run as a probe
    against 8424c16's hook first (the table below), then written, then the hook was edited
    once, in one batch. Two of the new T rows were denies before too, by a decaying rewrite
    deny rather than git's (R8 asserts the reason on a third attempt).

### Phase 3 probes

Verdicts are local / cloud, `P` a prompt, `D` a deny (git's unless noted), `A` an allow;
"before" is 8424c16. Probe scripts ran against a scratch copy of the tree; bash 5.2.21 and
git were asked what they really do for every row marked "bash runs it".

| Probe | Before | After | Note |
|---|---|---|---|
| `bash < run-plans.sh`, `sh <>…`, `bash 3<…`, `bash<'…'`, `< … bash`, `zsh <`, `bash < run-p*.sh` (unreadable ledger) | P | D role | (a) |
| `cat < run-plans.sh`, `wc -l <`, `sort <`, `ls > run-plans.sh.log` | P | P | reads |
| `cat run-plans.sh \| unshare sh`, `\| ash`, `\| rbash`, `\| prlimit sh` | P | D role | C, pipe side |
| `grep -c x run-plans.sh \| sort`, `cat … \| head -3`, `\| tee x` | A/A/P | same | filters |
| `./run-plans.s[^x]`, `[[:alpha:]]`, `unshare ./run-plan[[:lower:]].sh` | P | D role | fnmatch |
| `true;./run-p*.sh;true # '`, `./run-p*.sh>x # '` | P | D role | text scan |
| `GIT_EDITOR='./run-p*.sh' git commit`, `PAGER=./run-pl?ns.sh git log` | P | D role | bash/git run it |
| `git grep --open=./run-plans.sh x`, `-nO./…`, `git push --receive=…` | P | D role | git runs it |
| `printf './run-%s.sh' plans \| sh` | D opaque | same | documented limit: no name |
| `cat <<-EOF` with tabs; `<<'EOF'`, `<<\EOF`, `<<E"O"F`, `<<"E F"`; `EOF ` and space-then-tab lines | D or P as bash | same | exact already |
| CRLF: `cat <<EOF\r⏎x\r⏎EOF\r⏎git push --force …` | P | D | bash's delimiter is `EOF\r` |
| `cat <<\`a b\`⏎…`, `cat <<$"x"⏎…` then a push | P | D | delimiter read differently |
| two heredocs on a line; the second body holding a push | D / P | same | exact already |
| `echo $((1<<2))⏎git push …⏎2`, `(( x = 1 << 2 ))`, `$[1<<2]`, `a[1<<2]=5`, `${HOME:1<<2}` | D opaque (decays) | D | a shift, bash runs it |
| `cat <<EOF $(echo a⏎git push …⏎EOF⏎)` | P | D | bash runs it |
| `echo $(cat <<EOF⏎it's⏎EOF) ; git push …⏎EOF` | P | D | both readings |
| ``echo `cat <<EOF⏎x⏎EOF` ; git push …`` | D opaque (decays) | D | backtick run-on |
| `cat <<EOF⏎it's⏎EOF)⏎EOF⏎git push …` | P | D | top level: `EOF)` is body |
| `cat <<EOF⏎EOF) git stash⏎EOF⏎ls` | D | P | body to bash: the deny was a guess |
| `(cat <<EOF⏎x⏎EOF) ; git push …⏎EOF⏎)` | D | D opaque | body to bash; no git deny owed |
| `cat <<EOF > "$(pwd)/f"⏎git stash⏎EOF` | D authoring rewrite | D | cost: a substitution after the operator, body read as commands |
| `git commit -m "$(cat <<'EOF'⏎a " b⏎EOF⏎)" ; git push …` | P | D | stand-in |
| B1's shape with `"` or `'` in the body | P / D | D | both readings |
| `git commit -m "$(cat <<'EOF'⏎" $(git push …)⏎EOF⏎)"` | P | P | quoted delimiter: text |
| `git push … # '`, `;# '`, `&# '`, `(# '`, `#⏎git push …` | D | D | A held |
| `echo a\ # ; git push …`, `echo \;# ; …`, `echo a\r# ; …` | P | D | no comment to bash |
| `echo a#b ; git push …`, `git push … x a#b`, `$#`, `${x#y}`, `${x:- #y}`, `'a'#b` | P | D | ruling 20 |
| ``echo `echo a # b` ; git push …``, ``echo `# x`; git push …`` | P | D | backtick comment |
| `git push … # $'`, `echo $'a' # '⏎git push …` | P | D | ANSI-C walked |
| `echo 'a' #b ; git push …`, ``echo a # `; git push …` `` | P | P | a real comment |
| `-fu`, `-uf`, `-qf`, `-fq`, `-nf`, `-4f`, `--force-with-lease[=x]`, `-- -f` | D | D | held |
| `-of`, `-uo f`, `--force-if-includes`, `--no-force` | P / D cloud | same | no force |
| `--forc` | P / D cloud | same | git: ambiguous, an error |
| `--force-w`, `reset --har`, `checkout -qb x`, `switch -qc x` | P (cloud D for push, switch) | same | **found, not fixed** |
| `push origin +x`, `+<current>` | P / D cloud, P / P | same | pinned policy |
| `git branch -D old {a,b}`, `-{f,u}`, `--forc{e,}`, `{--force,}`, `{git,} push --force` | D | D | F2 held |
| `--forc{e,{x,y}}`, `--{force,{quiet,verbose}}` | D rewrite (decays) / D | D | nested |
| `--forc{e..e}`, `reset --har{d..d}`, `checkout -{b..b} x`, `--forc{e,{a}}` | P (cloud D for push) | D | sequences |
| 300 alternatives; `--forc{e,x}{,a}…{,h}`; `--forc{{1..300},e}` | D rewrite (decays) / P | D | past the cap |
| `git stash {list,show}`, `git log -1 {a..c}`, `git status {a,b}` | P / P / A | same | reads |
| `X=1 git push --force`, `env git …`, `! git …`, `{ git …; }`, `time`, `sudo`, `xargs` | P | P | **found, not fixed** |
| `git push --force origin x⏎echo '` | D no-tokenize (decays) | same | **found, not fixed** |
| `cat <<EOF⏎$(git push …)⏎EOF`; `echo "$(echo " # ")" ; git push …`; `echo $'it\'s' ; git push …` | P | P | **found, not fixed** |

### Found, not fixed

Each is a prompt, never an allow, was the same on `main`, and has a `self/BACKLOG.md` entry.

- **Git only at command position** — `X=1 git …`, `env git …`, `command`, `time`, `sudo`,
  `xargs`, `! git …`, `{ git …; }`. A class of its own (wrappers), not one of this feature's.
- **Flags as written** — an abbreviated long option (`push --force-w`, `reset --har`), a
  short cluster on another subcommand (`checkout -qb`), and the `+<refspec>` push, which
  `hook-cloud-profile.sh` pins as a prompt and which wants an owner ruling.
- **An unlexable line loses the git deny** — finding A's other option, not taken in ruling
  12. It covers an open quote after a push, an unplaced body holding an odd quote, and a
  whole-argument heredoc with an odd `"` after another substitution on the line.
- **Substitution scope** — a `$(…)` in an unquoted heredoc's body, a quote nested in
  `"$(…)"`, an ANSI-C quote escaping a quote. The fail-closed rule's documented prompt.
- **Unreadable-ledger path, as documented before**: a name built at run time (`printf
  './run-%s.sh' plans | sh`), a wrapper or copied script, a program named `cat` at another
  path, git config naming a program.

## Round 2

The rework of `escalations/01-review-opus.md` (item 1 and three minor notes) and
`escalations/01-audit-opus.md` (E1, E2, E3, one hardening, the "not regressions" list),
under coordinator ruling 7. Tests were written red first and run against round 1's hook
before any edit (`allow-repo-commands.sh`: 11 new rows red under each profile;
`hook-cloud-profile.sh`: 22 new checks red, then a `TypeError` at the first call with a
parameter the hook did not have yet), every edit was made and run on a scratch copy of the
tree, and the hook was then changed in four Edit calls and `hooks/README.md` in three (the
third for the constants list under "Editing the policy", missed until the first two had
landed). Rows
for what the differential check found afterwards (several run-on lines, a backtick line,
continuations, the caps) were written with their fix, after a probe showed each failing.

### Build rulings

28. **Review item 1: only a `${` nests.** In `comment_and_heredoc_free` a bare `{` no longer
    deepens `expansion_depth`, so `echo ${x:-{} ; git push --force origin x # '` leaves the
    expansion at its first `}` and the comment is read. The review's condition and its two
    `GIT_AUDIT_DENY` rows are in, with the same rows in the T table.
29. **E1: a run-on line is any body line that begins with the delimiter and goes on.**
    `HEREDOC_RUN_ON_CHARS` is gone: `heredoc_body_span` no longer asks what follows the
    delimiter (bash 5.2 ends a `$(…)` heredoc there whenever a `)` follows on the line, as
    the audit's probes and this round's differential check both show, and the hook does not
    ask whether one does, per ruling 7). Such a line leaves the body unplaced for a caller that
    says nothing, so the strict orchestrator reader refuses it; the deny side reads it every
    way. Three things the differential check added, each the same rule applied again:
    (a) inside a backtick substitution the body ends at the closing backtick whatever the
    line holds (`foo\``, `EOF"\``), so after a backtick a line holding one is a run-on line
    too, with a reading of its own (`HEREDOC_RUN_ON_BACKTICK`); (b) a body may hold several
    run-on lines and end at any of them (`EOFS⏎EOF git push …)` ends at the second), so the
    end is tried at each in turn (`skip`, `ended`), up to `MAX_RUN_ON_LINES`; (c) past that
    cap the line is not read finely (ruling 32). H8's `EOF `/`EOFS` row is narrowed to what
    is still true — plain body lines to the main parser — and `hooks/README.md`'s sentence
    is corrected.
30. **E2: a continuation is judged both ways by the build-script judge, and deleted where
    bash deletes it by the walk.** `invokes_build_script` judges the line with every `\⏎`
    deleted and as written, a run when either is (the brief's second option: which
    backslash sits in a comment is not asked). The differential check then found the same
    gap one level down, on a line holding a comment's backslash AND a real continuation
    (`ls # x \⏎./run-pla\⏎ns.sh`), and on the git deny, which never deleted one (`git
    pu\⏎sh --force` was a prompt on `main` too). So `comment_and_heredoc_free` deletes a
    `\⏎` itself, outside single and ANSI-C quotes — after it has left each comment behind,
    which is exactly where bash deletes none. A last backslash that escapes nothing is
    dropped (bash runs the command; shlex refused the whole line).
31. **E3: a comment past an opener is in doubt, and `)` stays in `COMMENT_PREDECESSORS`** —
    a deviation from the brief's item 4, which said to drop it. Probed on bash 5.2: a `#`
    starts a comment after `&`, `|`, `;`, `(`, `<`, `>`, a blank, a tab and a line break,
    always; after a `)` it does when the paren closed a subshell, a `case` pattern or a
    function's `()`, and does not when it closed a word (`a=(x)#b`, `$(x)#b`, `<(x)#b`,
    `$((1))#b`). Dropping `)` closes E3 and loses a deny round 1 had: `git push --force
    origin y; (ls)# it's` (bash runs the push; with `)` dropped the apostrophe opens a
    quote and the line does not lex). Ruling 7 covers both: the `#` is read BOTH ways. The
    same doubt holds for a `#` after a blank inside `$((…))`, a subscript, a pattern, or a
    quote nested in a quoted substitution, none of which the walk can place — so the rule
    is not about `)`: a `#` that may start a comment is certain only when none of `(`, `[`,
    `{` or a backtick is in the text kept before it (`COMMENT_DOUBT_OPENERS`), and in
    doubt otherwise. No other member of `COMMENT_PREDECESSORS` was removed: bash starts a
    comment after each. Both rows are pinned (`a=(x)#b; git push …` and `git push …;
    (ls)# it's`, each a deny).
32. **Every combination of the comments in doubt is read, up to a cap.** `judged_texts`
    asks the walk for each `#` in doubt dropped and kept, on its own (a line may hold one
    that is a comment and one that is not: `a=(x)#b; git push --force origin y # '`), at
    most `2 ** MAX_COMMENT_DOUBTS` readings. Past `MAX_COMMENT_DOUBTS` (5), or
    `MAX_RUN_ON_LINES` (4), the line is not read: one that names git anywhere is judged as
    a git command that cannot be read (`GIT_UNREADABLE_ARGS`, as a brace word past
    `MAX_BRACE_WORDS` already is), and any other raises `OverflowError`, which is a run to
    the build-script judge (`build_script_denial` takes a reading that fails for one) and
    no deny to the rest (main's judges catch it).
33. **The audit's hardening: the HEAD manifest probes ignore replace refs.**
    `own_push_allowed` sets `GIT_NO_REPLACE_OBJECTS=1` in the hook's own environment before
    its probes, so `git grep … HEAD` and `git show HEAD:<manifest>` read the committed blob
    (Q6: a replace ref over it, proved live, approves nothing). The environment variable
    rather than `--no-replace-objects` on `git_probe`: it is one statement in the function
    the audit named, and every probe after it inherits it.
34. **`$$'…'` (the audit's first "not a regression") is fixed in the same walk.** `$'` is
    ANSI-C after an odd run of `$` only; `$$'a\'` is the PID and a plain quote, and `$${x`
    opens no expansion. `never_judged` takes any `$'` for ANSI-C, on purpose (zsh reads
    `$$'…'` the other way, and a chained-`cd` deny must not fire on a line the shells read
    differently — a pinned row), so the git deny's readings leave the PID out of their
    text (`drop_pid`) and the chained-`cd` deny's does not: the git deny denies when
    either shell's reading runs the command, the `cd` deny keeps its guard.
35. **The audit's second "not a regression" closed as a side effect:** a quote nested in a
    backtick or `$(…)` inside `"…"` followed by a `#` (``echo "`echo " #"`"; git push …``)
    is a comment past an opener, so it is read both ways and denied. The third (a build
    script's name built at run time) is recorded, with a new `self/BACKLOG.md` entry.
36. **The review's minor notes.** The `own_push_allowed` docstring says "committed at
    `HEAD`"; the bare `"<"` literals are `HERESTRING_OPERATOR`; `hooks/README.md` has an
    over-deny list, with the quoted brace sequence past `MAX_BRACE_WORDS` on it.
37. **Rows moved, none weakened.** (a) H8 "`EOF ` and `EOFS` are plain body lines" now
    asserts it for the main parser (`HEREDOC_RUN_ON_IS_BODY`), with nine rows beside it
    for the unplaced reading; (b) `hook-orchestrator-role.sh` H21's `git commit -m "$(cat
    <<'EOF'⏎msg⏎EOF ⏎$(touch pwned)⏎EOF⏎)"` left `ROUND3_ADMITTED` and is denied (a body
    line that begins with the delimiter and goes on is refused whatever follows: ruling 7's
    text); (c) nothing else changed verdict in the three files. Two lines of round 1's
    audit table read differently now and are not test rows: `echo a \⏎#b ; git push -f
    origin y` was a deny and is a prompt (bash deletes the continuation and starts a
    comment there — certain, with no opener before it — and runs no push), and `(ls)#b; git
    push -f origin y` was a prompt and is a deny (an over-deny, below).
38. **Size.** 58 net code lines in the hook (2915 → 2973, comments and docstrings apart;
    124 physical lines), under the brief's 120. No tokenizer change: `chain_tokens`,
    `mask_quoted_punctuation`, `never_judged` and `quoted_separator_word` are untouched.

### Differential check

A harness in the scratch directory (not committed): three checkouts built from one tree's
`hooks/` — a readable ledger and another session, a `.git` naming no directory (the
unreadable ledger), and a ledger naming the session as an orchestrator — the hook's `main()`
called in-process for each line in each, and the same line run by `bash -c` (5.2.21) in a
sandbox whose `PATH` holds a logging `git` stub and whose directory holds logging stubs
named after each build script. A line FAILS in a checkout when bash ran a ref-moving git
command (the hook's own `git_mutates` over the argv the stub was handed) or a build script
(the unreadable-ledger and orchestrator checkouts only) and the hook's answer there was not
a deny that holds (a rewrite deny that decays to an ask counts as no deny).

| Corpus | Lines | Failing on round 1's hook | Failing after |
|---|---|---|---|
| every row of both escalation files' tables | 301 | 60 | 10 |
| the feature's constructs × `git push -f origin y`, `./run-plans.sh` (heredocs in and out of `$(…)`, backticks, `<(…)`; 25 delimiter-line endings; a `#` after each punctuation character; `\⏎` in and out of comments; `${…}` with braces; brace expansion; `-f` clusters) | 29,621 | 1,807 | 82 |
| mixed shapes (a comment in doubt beside a certain one, a payload on the run-on line, odd quotes in a body, a `#` in arithmetic, `$$`, many doubts) | 33,236 | 2,215 | 634 |
| the fix's own mechanisms (several run-on lines, continuations in words, quotes and comments, a last backslash, doubts at and past the cap) | 16,702 | 3,154 | 504 |
| hand-picked probes of those mechanisms against each other | 264 | 17 | 0 |
| **all** | **80,124** | **7,253** | **1,230** |

No line fails after that did not fail before, in any checkout, and none fails in the
orchestrator checkout (1,220 fail the git rule with a readable ledger, 41 of them with an
unreadable one as well, and 10 the build rule with an unreadable one). Every line still
failing also fails on `origin/main`'s hook (run over the same lines: all of them), and falls
in one of four classes, each recorded rather than fixed:

- **Inside or after a quoted substitution** (992 lines): the payload INSIDE
  `"$(…)"` or quoted backticks, a heredoc's run-on line there included (`git commit -m
  "$(cat <<'EOF'⏎x⏎EOF git push -f origin y)"`); a body line holding a `"` inside quoted
  backticks; a whole-argument heredoc with an unquoted or backslash-quoted delimiter whose
  body holds an odd `"`; a quote left open later on the line. The plain reading takes a
  quoted substitution for one word, and a line that does not lex loses the git deny —
  `self/BACKLOG.md`'s "does not follow a substitution's scope" and "cannot tokenize"
  entries, both older than this feature. For an orchestrator each of these is the role
  denial; the failures are in the other two checkouts' git column.
- **An ANSI-C quote escaping a quote** (222 lines; `echo $'a\'' ; git push …`,
  `$$$'a\''`, `\$$'a\''`): `never_judged` holds the line back, as on `main`.
- **A build script's name built at run time**, unreadable ledger only (10 lines, the
  audit's list: awk concatenation, a quote glued inside a sed `e` script, `printf … | sh`,
  `tr`, a grep that selects the name).
- **git behind an environment prefix** (6 lines: `x=1# \⏎git push -f origin y`): the
  wrapper class, with its `self/BACKLOG.md` entry.

### Over-denies (each documented in `hooks/README.md` → "What the both-readings rule over-denies")

- A comment bash does start, past an opener, holding a separator and then a denied
  command: `(ls) # then; git push --force origin y`, `(ls)#b; git push …`. With no opener
  before it a comment is certain (`ls src # then; git push …` stays a prompt: pinned).
- Inside a substitution, a body line that begins with the delimiter and does NOT go on to
  a `)`: bash keeps reading the body, the hook also reads what follows as commands
  (`echo $(cat <<EOF⏎x⏎EOF ⏎git push -f origin y⏎EOF⏎)`). For an orchestrator a commit
  message or PR body with such a line (`EOF notes`) is refused with the role reason.
- A line with more than `MAX_COMMENT_DOUBTS` comments in doubt, or a body with more than
  `MAX_RUN_ON_LINES` run-on lines: denied when it names git anywhere; on the
  unreadable-ledger path, a run whatever it names.
- A quoted brace sequence past `MAX_BRACE_WORDS` in a git argument (`git commit -m "ids
  {1..1000}"`): round 1's, listed now.
- On the unreadable-ledger path, a comment in doubt naming a build script after a command
  word (`(cd x) # then ./run-plans.sh`).

### Found, not fixed (round 2)

Each a prompt, never an allow, the same on `main`, with a `self/BACKLOG.md` entry: the four
classes above. The first entry's text there now names the run-on line inside a quoted
substitution and the quoted-backtick body; the run-time name has an entry of its own.

## Round 3

The rework of `escalations/02-review-opus.md` (item 1) and `escalations/02-audit-opus.md`
(R2-1, R2-2, R2-3), under coordinator ruling 7 and the coordinator's direction for the round:
close the CLASS — the walk reads raw text where bash has first deleted a backslash-newline —
not the spellings. Tests were written red first and run against round 2's hook before any
edit (`allow-repo-commands.sh`: 31 rows red under each profile — 27 git, 2 chained-`cd`, 2
own-assignment, the last three git rows written with ruling 43's fix after a probe showed
each a prompt; `hook-cloud-profile.sh`: a `TypeError` at the first call with a parameter
the hook did not have yet; `hook-orchestrator-role.sh`'s four new H26 rows were green
already — the allowlist's strict reader was never fooled — and are pins). Every edit was
made and run on a scratch copy of the tree, and
the real hook was then changed in four Edit calls and compared byte for byte with the copy
the tests and the differential check had run on; `hooks/README.md` took five.

### Build rulings

39. **The design: delete the continuation before the test, not while passing it.** Round 2's
    walk deleted a `\⏎` when its index reached one, so every test that looked AHEAD
    (`startswith("<<")`, the herestring check, `heredoc_delimiter`, the whole-argument head's
    regex) or BEHIND through the raw line (`substituted()`, `HEREDOC_SHIFT_RE`, `BACKTICK in
    command[:index]`) still saw the two pieces. The walk now deletes it from the line itself
    (`join`): at the top of each step, where round 2 did, and ahead of each test that looks
    ahead — the operator, the delimiter (inside `heredoc_delimiter`, which knows the word's
    quotes), the head and tail of a whole-argument heredoc (`join_head`,
    `HEREDOC_ARGUMENT_TAIL_RE`). Everything behind the index is then already as bash read
    it, so the look-behind tests needed no change. The coordinator's coarser alternative —
    one extra reading with every `\⏎` deleted everywhere — was tried on paper and does not
    close the class: `cat <<EOF⏎EO\⏎F⏎ls # x \⏎git push -f origin y⏎EOF` needs the first
    continuation deleted (a terminator) and the second kept (a comment), and neither the
    raw reading nor the all-deleted one denies it. No tokenizer change: `chain_tokens`,
    `mask_quoted_punctuation`, `never_judged` and `quoted_separator_word` are untouched.
40. **R2-1: a body's lines are joined where bash joins them, and the caller says where.**
    `heredoc_body_span(…, joins=)` reads each line through `heredoc_body_line`. Probed on
    bash 5.2 (a body `a` + N backslashes + ⏎ + `EOF`, N from 0 to 5, in four contexts): an
    unquoted delimiter's body is joined at an ODD run of backslashes, in the main parser,
    `$(…)` and `<(…)` alike (`EO\⏎F` ends it, `EO\\⏎F` does not, `x\⏎EOF` hides its `EOF`);
    a quoted delimiter's nowhere. So the audit's first alternative, not its second (leave
    such a body unplaced): an unplaced body is read as commands, and one holding an
    apostrophe then loses the deny (`cat <<EOF⏎x\⏎EOF⏎it's⏎EOF⏎git push -f origin y` is a
    row). `heredoc_delimiter` returns `(delimiter, strip_tabs, end, quoted)`.
41. **The quoted-delimiter twin is a PROMPT** — `cat <<'EOF'⏎EO\⏎F⏎git push -f origin
    y⏎EOF`, the verdict the review asked to have pinned: bash joins nothing there and runs
    no push, the hook reads it so, and the rows (`GIT_NOT_DENIED`, the T table) hold it,
    with `<<\EOF` and the escaped-backslash twin `EO\\⏎F` beside it.
42. **Two more readings of a body, on a line that holds a heredoc and a continuation**
    (`HEREDOC_JOINS_*`, ruling 7). Inside backticks bash deletes a continuation from the
    substitution's text before any heredoc there is read, so a QUOTED delimiter's body is
    joined too, and the walk knows only that a backtick came earlier on the line: read
    both ways. And the reading that joins nothing — round 2's — is kept beside bash's, so
    that a line it denied is still denied (the audit's tc3, `cat <<EOF⏎x\⏎EOF⏎git push -f
    origin y⏎EOF`, where bash runs no push: a T row).
43. **Inside backticks bash halves each run of backslashes** when it takes the
    substitution's text (probed: N = 1, 2, 3 and 5 join an unquoted body, 4 does not), so
    `\\⏎` is a continuation to the substitution's own parser. The differential check found
    it (30 lines of the generated corpus), and it is the same class one level down, so it
    is closed: `join` deletes it in the walk and before the operator, `heredoc_delimiter`
    in the delimiter, `HEREDOC_JOIN_BACKTICK` in an unquoted body, and a continuation
    there is deleted inside single quotes too (`BACKTICK_ESCAPE_CYCLE`).
44. **R2-2 needed nothing of its own once ruling 39 was in** — `<\⏎(`, `$\⏎(`, `>\⏎(` and
    the arithmetic openers are joined before `substituted()` and `HEREDOC_SHIFT_RE` read
    them. The raw-text tests beside the walk were changed to match: `judged_texts` looks for
    the operator, the whole-argument head and (past a cap) the git word with every
    continuation deleted, and `unreadable_ledger_refuses` for its markers both ways
    (`$\⏎(` and `<\⏎<` reached the finer build-script reading round 13 took off that path).
45. **The review's third reproduction is a different class, and is closed too.** `echo
    "$(cat <<EOF⏎EO\⏎F⏎git push --force origin y⏎EOF⏎)"` was a prompt — and so was its
    twin WITHOUT the continuation, on round 2 and on `origin/main`: the plain reading takes
    a `"$(…)"` for one quoted word (`self/BACKLOG.md`, "does not follow a substitution's
    scope"), which round 3's review brief lists as not in the round. But the brief also
    lists this line as denied, and the construct is this feature's (`heredoc_argument_at`),
    so, by ruling 7: a whole-argument head that is not stood in is read TWICE, closed as
    before and opened (`open_heads`: its `"` and the next `"` dropped, its heredoc placed
    like any other, what follows the body read as commands). Narrow on purpose — only the
    `"$(cat <<` head; every other `"$(…)"` stays the one word it was, with its BACKLOG entry.
46. **R2-3:** `uses_own_assignment` looks for the use in every reading, each with its own
    offsets.
47. **Rows moved, none weakened.** No assertion in the three test files changed verdict or
    was deleted. Nineteen verdicts of the generated corpora went from deny to prompt (or to
    the decaying rewrite), on lines where bash runs no denied command and round 2's deny was
    a body it had failed to place, read as commands: a QUOTED delimiter whose operator or
    delimiter word is split by one continuation and whose body holds a line joined to
    `EOF` by another (`cat <<\⏎'EOF'⏎x⏎EO\⏎F⏎git push -f origin y⏎EOF`; `cat <<A
    <<'B'⏎x⏎A\⏎⏎y⏎B\⏎⏎git push -f origin y⏎B`). They are not test rows; the round's rule is
    that no line bash runs a denied command on loses its deny, and none did.
48. **Size.** 83 net code lines in the hook (2975 → 3058, comments and docstrings apart;
    170 physical lines).

### Differential check

Round 2's harness (the same three checkouts, the same logging stubs, bash 5.2.21), over
three new corpora and round 2's five again. "Before" is round 2's hook (`4ed1ff6`).

| Corpus | Lines | Failing on round 2's hook | Failing after |
|---|---|---|---|
| every row of round 2's audit tables, and the review's reproductions | 127 | 28 | 3 |
| a `\⏎`, and an escaped backslash before a line break (`\\⏎`), inserted at EVERY position of 50 constructs × 2 payloads (heredocs plain, quoted, `<<-`, two on a line, in `$(…)`, `<(…)`, backticks and `"$(cat <<…)"`; run-on lines; shifts; a herestring; comments certain and in doubt; `${…}`; `$'…'`, `$$'…'`; quotes), and two continuations at every pair of positions in each line's first 24 characters | 36,806 | 2,466 | 40 |
| hand-picked probes of the round's mechanisms against each other | 230 | 58 | 6 |
| round 2's five corpora, again | 80,124 | 1,230 | 606 |
| **all** | **117,287** | **3,782** | **655** |

No line fails after that did not fail before, in any checkout, and none fails in the
orchestrator checkout (643 fail the git rule with a readable ledger, 19 of them with an
unreadable one as well, and 12 the build rule with an unreadable one). No line was approved
on which bash ran anything. The 655, each failing on round 2's hook too, by class:

- **Inside or after a quoted substitution that is no whole-argument heredoc** (381):
  `echo "$(cat <<EOF ; git push -f origin y⏎x⏎EOF⏎)"`, a `<<\EOF` head, a `"` nested in
  quoted backticks. `self/BACKLOG.md`'s scope entry; round 2 counted 992 here, and the
  opened reading of ruling 45 took the rest.
- **An ANSI-C quote escaping a quote** (226): `never_judged` holds the line back, as before.
- **A line that does not tokenize** (29): a quote left open after the command — in the new
  corpus, by a continuation that lets a quote out of the comment that held it (`git push
  -f origin y # \⏎'`: bash deletes none in a comment, runs the push, then fails on the
  quote) — and a delimiter bash reads differently over a body with an apostrophe. The
  BACKLOG's "cannot tokenize" entry, which now names the comment spelling.
- **A build script's name built at run time**, unreadable ledger only (12).
- **git behind an environment prefix** (6).
- **`git push -${o}f origin x`** (1): the variable rewrite, which decays.

Of the new corpus's 40: 27 hold an ESCAPED backslash before the line break, which is no
continuation, and fail for one of the reasons above; 13 are the comment spelling. None is
a continuation bash deletes and the hook does not.

### Over-denies (each in `hooks/README.md` → "What the both-readings rule over-denies")

1,228 verdicts of the 117,287 lines × 3 checkouts are a deny that was none before on a
line where bash runs no denied command (1,198 of them in round 2's corpora):

- A whole-argument heredoc that is not stood in, read opened: text bash keeps inside the
  quotes after the substitution (`echo "$(cat <<EOF⏎x⏎EOF⏎) ; git push -f origin y"`), and
  the rest of a body after a line that begins with its own delimiter word (`"$(cat
  <<EOF⏎x⏎EOF notes⏎git push -f origin y⏎EOF⏎)"` — the kind round 2 already listed for an
  unquoted `$(…)`). A commit message or PR body in the stood-in shape (`<<'EOF'`, its
  `)"` after the terminator) is not touched.
- A body line bash joins to the one before it, then the delimiter alone, then a denied
  command (ruling 42's as-written reading).
- After a backtick anywhere earlier on the line, a quoted delimiter's body with a
  terminator joined across a continuation.

### Found, not fixed (round 3)

Nothing new. The five classes above are round 2's, each with its `self/BACKLOG.md` entry;
two entries were edited (the scope entry names what ruling 45 closed and what it left; the
"cannot tokenize" entry names the comment's backslash and drops the unquoted-delimiter
spelling, which is denied now).

## Round 4

The rework of `escalations/03-audit-opus.md` (R3-1, R3-2); round 3's review was clean. A
small round by the owner's choice, and the coordinator's decision for R3-1 was the coarse
one: a reading the walk builds that then fails to tokenize is never dropped — the line is
denied. Tests were written red first and run against round 3's hook before any edit
(`allow-repo-commands.sh`: 33 rows red under each profile — 25 git, 4 with no git, their 4
reason checks; `hook-cloud-profile.sh`: an `AttributeError` at H18's first line, on a name
the hook did not have yet). The change was composed and run on a scratch copy of the tree —
all twelve hook test files and the differential check — and then applied to the real files
in two Edit calls for the hook and one for `hooks/README.md`, each compared byte for byte
with the copy the tests had run on.

### Build rulings

49. **Where the reading was lost.** Not at the lexer's `try`/`except`: in the walk itself.
    `comment_and_heredoc_free` returned the line AS IT CAME whenever its quotes never closed,
    whatever it had built by then — so in `echo "$(cat <<'EOF'⏎x⏎EOF )" ; git push -f origin
    y⏎EOF⏎)"` the reading that stands the heredoc in at the run-on line (bash's) came back
    as the raw line, which does not lex, and `command_words` dropped it like any text it
    cannot read. `chain_tokens` returning None downstream was only where it showed.
50. **R3-1: one test, asked of every reading** (`torn_reading`). The walk now returns such a
    line as a `TornReading` — a `str` equal to the line, so every other caller (the
    chained-`cd` deny's own walk among them) reads exactly what it read before — when what
    it had kept differs from the line it was given. `judged_texts` asks `torn_reading` of
    each reading it takes and notes a hit in `torn`; a line with one that names git is
    judged as a git command that cannot be read (`unread()`, the same answer the two caps
    give, now in one place), and any other keeps its texts and takes the does-not-tokenize
    deny: `does_not_tokenize` asks `tears_a_reading` before its heredoc and `#` guards. No
    tokenizer change: `chain_tokens`, `mask_quoted_punctuation`, `never_judged` and
    `quoted_separator_word` are untouched.
51. **What is not a built reading**, each for a row that would otherwise have moved. (a) A
    dropped `$$` alone: `grep $$'\'#' README.md` is pinned a prompt (bash and zsh read it
    differently), so `torn_reading` asks the walk again with the PID kept, and a `$$`
    beside a real build excuses nothing (a row). (b) A comment in doubt kept as TEXT:
    `git commit -m "$(cat <<EOF⏎msg⏎EOF⏎)" # it's done` would have been denied on the
    reading that takes a real comment for words; the reading that drops it is asked. (c)
    Bodies read as commands because none could be placed (`keep_bodies`): a guess to begin
    with, with `judged_tokens`' first-line fallback written for it.
52. **w10 and w14 take the tokenize deny, not the chained-`cd` and own-assignment reasons.**
    The coordinator's decision as written ("otherwise with the tokenize rewrite deny the
    plain line gets"). Both are denied again, with `UNREADABLE_DENY_REASON`; it is a
    rewrite deny, so it decays to an ask after two attempts, as x7's does. Giving them
    their own reasons would mean reading a torn reading up to its open quote in every
    judge — `chains_chdir` reads one walk of its own — which is past "a helper plus a regex".
53. **R3-2: the head is respelled, not re-matched.** `HEREDOC_OPENED_HEAD_RE` matches `"$(`,
    blanks and line breaks, `cat`, blanks, `<<`, with a line continuation allowed between
    any two characters; `judged_texts` rewrites each match to `HEREDOC_ARGUMENT_START` in
    the line the OPENED reading walks, and the walk is unchanged — so the opened reading
    does for `"$( cat <<EOF` exactly what round 3 made it do for `"$(cat <<EOF`, and
    nothing it did not (the delimiter and the line break after it are still
    `HEREDOC_ARGUMENT_HEAD_RE`'s; a herestring is no head). `"$(cat<<EOF` is one of the
    spellings. `"x$(cat <<…` (the audit's o9) and `"$(command cat <<…` stay the documented
    class, with the BACKLOG scope entry.
54. **Where the new names sit.** `TornReading`, `torn_reading`, `CONTINUATIONS_PATTERN`,
    `HEREDOC_OPENED_HEAD_RE` and `tears_a_reading` are defined beside `judged_texts`, not in
    the constants block at the top of the file, and `hooks/README.md` names them in "What
    the deny side reads" rather than in "Editing the policy"'s list: the owner approves
    every `hooks/` edit at a prompt and the round was capped at two for the hook and one
    for its README, each a single contiguous region. The walk reads `TornReading` when it
    is called, by which time the module has defined it.
55. **Rows moved stricter, none weakened or deleted.** No existing assertion changed. Lines
    whose verdict moved and that are not rows: `git pu\⏎sh -f origin y ; echo '` went from
    the tokenize rewrite deny to the git deny (a new row pins it); a line with a quote
    really left open after a comment, a placed body, a stood-in heredoc or a continuation
    went from a prompt to a deny (rows `git push -f origin y # \⏎'`, `cat <<EOF⏎x⏎EOF⏎git
    push -f origin y⏎echo '` and their no-git twins).
56. **Size.** 25 net code lines in the hook (39 added, 14 replaced, comments and docstrings
    apart; 88 physical lines added, 17 removed).

### Differential check

Round 2's harness again (three checkouts, logging stubs, bash 5.2.21). "Before" is round
3's hook (`72f5e35`), rerun over every corpus rather than read from round 3's files.

| Corpus | Lines | Failing on round 3's hook | Failing after |
|---|---|---|---|
| round 4's: a run-on terminator inside `"$(cat <<…)"`, `$(…)`, `<(…)` and backticks × 5 delimiters × 9 run-on spellings × 14 tails after the payload (none, an odd `"`, `\"`, a comment, `$'\''`, `$$'a'`, an apostrophe, no terminator line); the opened head in 13 spellings × 7 bodies; other built readings with a quote left open; 1,011 legitimate lines (messages, PR bodies and heredocs with quotes, apostrophes, backticks, a line that begins with the delimiter, trailing comments, nested quotes); every row of the round-3 audit's R3-1 and R3-2 tables | 62,742 | 13,848 | 3,830 |
| rounds 2 and 3's eight corpora, again | 117,287 | 655 | 441 |
| **all** | **180,029** | **14,503** | **4,271** |

No line fails after that did not fail before, in any checkout; no verdict is looser than
round 3's on any line (0 of 540,087); no line is newly approved, and none is approved on
which bash ran a denied command. The 4,271, each failing on round 3's hook too, by class:

- **Inside or after a quoted substitution that is not this head** (2,363): a
  backslash-quoted delimiter (`"$(cat <<\EOF⏎x⏎EOF )" ; git push …`, neither stood in nor
  opened), text before the `$(`, `"$(cat - <<`, quoted backticks, a command on the head's own
  line. `self/BACKLOG.md`'s scope entry.
- **An ANSI-C quote escaping a quote** (1,781): `never_judged` holds the line back. This
  includes a BUILT reading whose quotes close and which holds one (`echo "$(cat
  <<'EOF'⏎x⏎EOF )" ; git push -f origin y ; echo $'\'' "⏎EOF⏎)"`): it is dropped by
  `never_judged`, not by a failure to tokenize, and denying it would move pinned rows
  (`ls $'\'' # '; cd src` and `grep $'it\'s' README.md` are prompts by decision). Left,
  and named in the BACKLOG entry.
- **A line that does not tokenize and on which nothing was built, a delimiter bash reads
  differently, a build script inside `<(…)` or backticks on the plain checkout's ask**
  (109), **a build script's name built at run time** (12), **git behind an environment
  prefix** (6).

### Over-denies (each in `hooks/README.md` → "What the both-readings rule over-denies")

13,962 verdicts are a deny or a decaying deny that was none before on a line where the
harness saw bash run no ref-moving git command and no build script. Nearly all are the
corpus's own attack lines with a payload the harness does not count (a chained `cd`, an
own assignment, a build script on the readable-ledger checkout) or lines that are broken
for bash too (a quote really left open). Of the 1,011 legitimate lines, 73 changed, all
of two kinds:

- **A message or PR body with a line that begins with its own delimiter word, and an odd
  quote after it** (72: `git commit -m "$(cat <<'EOF'⏎EOF notes⏎it's fine⏎EOF⏎)"`, and
  `line \⏎EOF isn't`, which the as-written reading takes for one). The reading that ends
  the body at that line reads the rest as commands, and it does not lex. A git line is
  denied as a git command that cannot be read; a `gh pr create` takes the tokenize deny.
  For an orchestrator such a body was refused already.
- **After a heredoc, a quote nested in a later `"$(…)"` with an odd quote of the other
  kind inside** (1: `cat <<EOF⏎x⏎EOF⏎echo "$(grep "don't" f)"`): the plain reading ends the
  outer `"` at the inner one.

The other 938 did not move: the usual `"$(cat <<'EOF'⏎…⏎EOF⏎)"` message with apostrophes,
quotes, backticks and `$(…)` in its body, an unquoted delimiter over an odd `"`, a trailing
comment holding an apostrophe, `(ls) # it's`.

### Found, not fixed (round 4)

One thing, restated rather than new: a built reading whose quotes close and that
`never_judged` holds back (the ANSI-C class above). And one cost of ruling 52: w10 and w14
are denied with the tokenize reason, which decays, not with the hard chained-`cd` and
own-assignment denies. Two BACKLOG entries were edited (the "cannot tokenize" entry names
what round 4 closed and what is left; the scope entry names the head's spellings).

## Round 5

The rework of `escalations/04-audit-opus.md` (R4-1); round 4's review was clean. A coarse,
small round by the owner's choice: a whole-argument `"$(cat <<` head whose delimiter is not
a bare or fully quoted identifier is not read for a message at all — the line is treated as
a torn reading (round 4's path). Tests were written red first and run against round 4's
hook before any edit (`allow-repo-commands.sh`: 43 rows red under each profile — 37 git, 3
with no git, their 3 reason checks; `hook-cloud-profile.sh`: an `AttributeError` at H19's
first line, on a name the hook did not have yet). The change was composed and run on a
scratch copy of the tree — all twelve hook test files and the differential check — and then
applied to the real files in ONE Edit call for the hook and ONE for `hooks/README.md`, each
compared byte for byte with the copy the tests had run on.

### Build rulings

57. **R4-1: a predicate and a call site.** `unread_head(text)` is true when the text holds
    a head in any spelling of round 4's `HEREDOC_OPENED_HEAD_RE` and what follows its `<<`
    is not the delimiter `HEREDOC_ARGUMENT_HEAD_RE` reads. `judged_texts`' `read()` asks it
    of every reading it takes and notes a hit in `torn`, beside round 4's `torn_reading`.
    Everything after that is round 4's: a line that names git is a git command that cannot
    be read (`unread()`), any other keeps its texts and takes the does-not-tokenize deny
    (`does_not_tokenize` → `tears_a_reading`). The walk, the stand-in, the opened reading
    and every tokenizer are untouched.
58. **The delimiter word is not parsed** (the owner's instruction). `HEREDOC_HEAD_WORD_RE`
    takes the `-` and blanks and then everything up to the next blank or operator character
    (`CHAIN_PUNCTUATION`, `CHAIN_WHITESPACE`); the predicate puts that behind
    `HEREDOC_ARGUMENT_START` and asks `HEREDOC_ARGUMENT_HEAD_RE` itself, so the identifier
    form is written once. A quoted blank or operator cuts the word short (`'E O F'` is
    taken as `'E`, `'E)F'` as `'E`), which is still no plain word.
59. **Asked of the readings, not of the raw line and not inside the walk.** Of the raw line
    it would refuse a usual message whose BODY names such a head — this repository writes
    those — and a head in a comment; a reading has stood the body in and dropped the
    comment. Inside the walk (at the `"` where the stand-in and the opened reading are
    decided) it would have needed a way out for a walk that returns None on a later body,
    which is a signature change and a second edit region; and it would rest on the walk's
    quote state, which a quote nested in an earlier `"$(…)"` turns over. Asked of every
    reading — built or not, comments in doubt kept or dropped, bodies read as commands when
    none is placed — it holds after a body no reading places and after a quote-state flip
    (`echo "$(echo '"')" "$(cat <<''…` is denied; H19 and the differential's `r4-1-mix`
    rows). The cost is ruling 61's second over-deny.
60. **What is not this head.** A herestring (`"$(cat <<<"x")"`: the word class stops at
    `<`, so it is excluded by name). A plain delimiter with something after it on the
    head's own line (`"$(cat <<EOF | tr a b`, `"$(cat <<'EOF' -A`): the crude word is the
    plain one, and the line stays the documented class it was (the audit's n10, n11). Text
    before the `$(`, `"$$$(cat <<`, a command word other than a bare `cat`, quoted
    backticks: not `HEREDOC_OPENED_HEAD_RE`'s head with an identifier delimiter either, so
    the odd-delimiter twin is no worse than the plain one (BACKLOG scope entry, extended).
61. **Rows moved stricter, none weakened or deleted.** No existing assertion changed. Lines
    whose verdict moved and that are not attack rows: a message or PR body under a
    backslash-quoted delimiter (`git commit -m "$(cat <<\EOF⏎msg⏎EOF⏎)"`) went from a
    prompt to a deny — the task names `E\OF` and `\E\O\F` as delimiters to refuse, and
    `\EOF` is the same spelling; `hooks/README.md`'s "what still reaches a prompt" and the
    BACKLOG entry no longer list it. The audit's p1 and e7 (denied before, by the plain
    reading) are now denied as a git command that cannot be read. Round 4's two documented
    over-denies are pinned as the denies they are, as round 4's review asked (three rows in
    `allow-repo-commands.sh`, two in the T table).
62. **Where the new names sit.** `HEREDOC_HEAD_WORD_RE` and `unread_head` are defined
    between `judged_texts` and `tears_a_reading`, beside their one user, as round 4's were
    (ruling 54): one contiguous Edit. `hooks/README.md` names them in "What the deny side
    reads".
63. **Size.** 8 net code lines in the hook (9 added, 1 replaced, comments and docstrings
    apart; 32 physical lines added, 3 removed). Two `hooks/` Edit calls, one per file.

### Differential check

Round 2's harness again (three checkouts, logging stubs, bash 5.2.21). "Before" is round
4's hook (`09c962f`'s tree), rerun over every corpus rather than read from round 4's files.

| Corpus | Lines | Failing on round 4's hook | Failing after |
|---|---|---|---|
| round 5's: 33 delimiters (the audit's table of 20, `E'O'F`, `E"O"F`, `'E'OF`, `''`, `""`, `\EOF`, a split one, `'EOF'x`, `$EOF`, and the four plain controls) × 16 heads (the head's seven spellings, `<<-` and `<< `, text before the `$(`, `$$$(`, `cat -`, `$(`, `<(`, backticks) × 10 body shapes (canonical with an odd `"`, run-on, balanced, a second heredoc that is never placed, a continuation) × 7 payloads (two git, a chained `cd`, an own assignment, three build-script spellings); such a head beside a usual message, after a heredoc, a comment in doubt, a quote-state flip; 942 legitimate lines (messages and bodies under seven plain delimiters, three of them naming such a head in the body, herestrings, a pipe on the head's line, greps for the head's text); every row of the round-4 audit's R4-1 tables | 80,338 | 8,428 | 3,277 |
| round 4's corpus, again | 62,742 | 3,830 | 2,926 |
| rounds 2 and 3's eight corpora, again | 117,287 | 441 | 435 |
| **all** | **260,367** | **12,699** | **6,638** |

No line fails after that did not fail before, in any checkout; no verdict is looser than
round 4's on any line (0 of 781,101); no line is newly approved, and none is approved on
which bash ran a denied command. No line whose verdict changed lacks such a head. Of round
5's corpus, no line that still fails holds a `"$(cat <<` head with an odd delimiter: the
3,277 are text before the `$(`, `"$$$(cat <<` and `"$(cat - <<` (668 each), quoted
backticks (656), an unquoted `$(`, `<(` or backtick substitution followed by a heredoc that
is never placed (553) and the same after a plain-delimiter head (64) — each failing on
round 4's hook too, each the BACKLOG scope entry's or the "cannot tokenize" entry's. The
6,638 by the harness's classes: inside or after a quoted substitution that is not this
head (3,781), an ANSI-C quote escaping a quote (1,541), a line that does not tokenize and
on which nothing was built (1,146), backticks (152), a build script's name built at run
time (12), git behind an environment prefix (6).

### Over-denies (each in `hooks/README.md` → "What the both-readings rule over-denies")

15,899 verdicts are a deny or a decaying deny that was none before on a line where the
harness saw bash run no ref-moving git command and no build script. Nearly all are the
corpora's own attack lines with a payload the harness does not count on the readable-ledger
checkout (a chained `cd`, an own assignment, a build script). Of the 1,953 legitimate lines
in round 4's and round 5's corpora, 161 changed, of three kinds:

- **A message or PR body under a backslash-quoted delimiter** (150, all of round 4's
  `<<\EOF` messages): by design, ruling 61. Write `'EOF'`.
- **The head's text inside single quotes on a line that names git** (2: `git log --grep
  '"$(cat <<' -1`, `git commit -m 'about "$(cat <<123'`): ruling 59's cost. A `grep` or
  `echo` of the same text did not move (the `grep` is still approved).
- **A message under an UNQUOTED delimiter whose body names such a head, in a reading that
  leaves the body in** (9, each with a trailing comment holding an apostrophe).

The other 1,792 did not move: the usual message and PR body under `'EOF'`, `"EOF"`, `EOF`,
`-EOF`, `-'EOF'`, `'END_OF_MSG'` and `- 'EOF'` with apostrophes, quotes, backticks and
`$(…)` in the body, the same under `'EOF'` naming such a head, herestrings, a pipe on the
head's own line, a CRLF message, the odd delimiters on a plain heredoc.

### Found, not fixed (round 5)

Nothing new. Two costs, restated: a line with no git on it takes the does-not-tokenize
deny, which decays to an ask and whose reason speaks of an open quote the line does not
have (ruling 52's cost, now for this head too); and the odd delimiter behind a head that
is not `HEREDOC_OPENED_HEAD_RE`'s (text before the `$(`, `cat -`) is still one quoted
word, as its plain twin is. Two BACKLOG entries were edited (the "cannot tokenize" entry no
longer lists the backslash-quoted whole-argument spelling; the scope entry names what round
5 refused and what it left).

## Round 6

The rework of `escalations/05-audit-opus.md` (B1); round 5's review was clean. A coarse,
small round by the owner's choice: **a line that names git and does not tokenize is a git
command that cannot be read**, whatever `<<` or `#` it holds — round 4's torn-reading path
and the caps' answer, reused. Tests were written first and run red against round 5's hook
(`allow-repo-commands.sh`: every `UNLEXED_GIT_DENY` row whose tail holds a `<<` or a `#`
red under each profile, a prompt; `hook-cloud-profile.sh`: the same rows of the T block
red locally and in the cloud; `hook-escalation.sh`: 10a red, three of five lines a prompt). The change was composed and
run on a scratch copy of the tree — all twelve hook test files and the differential check —
and then applied in ONE Edit call to the hook, compared byte for byte with the copy the
tests had run on, and TWO to `hooks/README.md`.

### Build rulings

64. **B1: one test at `judged_texts`' return.** Once every reading is taken, `judged_texts`
    asks whether `chain_tokens` can lex any of them. When it can lex none, the line is
    answered as a torn reading is: `unread()` — a git command that cannot be read
    (`GIT_UNREADABLE_ARGS`) when the line names git, and the texts as they were when it
    does not. Every caller that judges git reads `judged_texts`, so the deny, its reason
    and its no-decay are round 4's, untouched. `does_not_tokenize`, `never_judged`,
    `tears_a_reading` and the walk are not edited: a line with no git on it reaches the
    same code with the same texts and keeps its verdict (the tokenize rewrite deny, or the
    prompt the heredoc and `#` guards leave — the audit's B1 tails after `ls`, `cd /tmp &&
    ls` and `X=/p; cat $X/f` are pinned as the prompts they were).
65. **"Does not tokenize" is `chain_tokens`, not `judged_tokens`.** The first scratch draft
    asked `judged_tokens`, which falls back to a heredoc's first line when the whole text
    does not lex. That left the BACKLOG entry's other half open — a body no reading places
    whose text holds an odd quote (`cat <<Z⏎x⏎Z⏎git push -f origin y⏎cat <<EOF⏎echo '`: 45
    lines of round 6's corpus still failing, 1,080 verdicts in round 5's). `chain_tokens`
    is the lexer itself and the same line count; compared over four corpora, the second
    draft moved only prompts and decaying denies to this deny, and no legitimate row.
66. **The one excuse is `never_judged`'s ANSI-C quote.** A reading that holds a `$'…'`
    escaping a quote counts as one that tokenizes: shlex refuses `git commit -m $'it\'s'`
    and bash runs it, and `command_words` holds the same text back by the same test (with
    the reading's `#`s removed, as there). So `git push -f origin y⏎echo $'\'' '#` is
    still a prompt: the recorded ANSI-C class, the BACKLOG scope entry's.
67. **Rows moved stricter, none weakened or deleted.** Two assertions of a REASON moved,
    because the lines they name are this deny now: `git rebase 'main` left "the unreadable
    deny names the quote" (`ls 'src` stands there) and `git push -f origin y⏎echo '` left
    "... with the reason that names the quote". Both lines are still asserted DENY
    (`UNREADABLE_DENY` is untouched; `UNLEXED_GIT_DENY` holds both) and their reason is
    asserted to be the git deny's (`GIT_REASON_WORDS`); `hook-escalation.sh` §10 asserts
    they no longer decay. Verdicts that moved and are not attack rows: a read before the
    open quote (`git status⏎echo '#`), a message whose terminator and closing quote were
    dropped (`git commit -m "$(cat <<'EOF'⏎msg`), a heredoc never terminated with an odd
    quote after it on a line that names git — each a prompt before, each pinned as a deny.
    The usual message and PR body rows are unchanged.
68. **Docs.** `hooks/README.md`: a round-6 over-deny bullet, the rule's paragraph and a
    rewritten "What still reaches a prompt" (one Edit — the three are adjacent), and the
    sentence under "The git shape" that said the git deny does not judge such a line (the
    second). The seventh opaque shape's paragraph still gives `git rebase 'main` as its
    example; the rule's paragraph names that sentence and says which deny the line takes
    now — a third `hooks/` Edit was outside the round's limit. `self/BACKLOG.md`'s
    "cannot tokenize" entry is rewritten: closed for a line that names git, three
    leftovers named. No new constant: the test reuses `COMMENT_CHAR`, `chain_tokens`,
    `never_judged` and `unread()`.
69. **Size.** 2 net code lines in the hook (2 added, 1 replaced; 8 physical lines added,
    1 removed, 5 of them a comment). Three `hooks/` Edit calls: one on the hook, two on
    `hooks/README.md`.

### Differential check

Round 2's harness again (three checkouts, logging stubs, bash 5.2.21). "Before" is round
5's hook (`30d239d`'s tree), rerun over every corpus.

| Corpus | Lines | Failing on round 5's hook | Failing after |
|---|---|---|---|
| round 6's: 16 payloads (the audit's six git commands, `gi""t`, `g\it`, `git -C .`, a split `pu\⏎sh`, `git status`, two build-script spellings, a chained `cd`, an own assignment, `ls`) × 9 things before them (nothing, a placed heredoc, comments, a quoted `<<` or `#`, a usual message) × 30 tails (an open quote around or beside a `#`, a `<<`, both, neither; a whole-argument head with no terminator, with a body, with a terminator and no `)"`; a PR body and a message cut short; quoted backticks; a heredoc never terminated; an ANSI-C quote) × 3 things after; the same joined by `;` and `&&`, with the tail first, and with the payload in a `$(…)`; 2,011 legitimate lines (messages, PR bodies and tags under seven delimiters with `'#`, `'<<` and a head in the body, plain heredocs with odd quotes, comments with apostrophes, ANSI-C); the audit's B1 rows | 16,919 | 3,323 | 148 |
| round 5's corpus, again | 80,338 | 3,277 | 593 |
| round 4's corpus, again | 62,742 | 2,926 | 1,969 |
| rounds 2 and 3's eight corpora, again | 117,287 | 435 | 324 |
| **all** | **277,286** | **9,961** | **3,034** |

No line fails after that did not fail before, in any checkout; no verdict is looser than
round 5's on any line (0 of 831,858); no line is newly approved, and none is approved on
which bash ran a denied command. Every line whose verdict changed names git and is one
`judged_texts` now answers as the unreadable git command (0 exceptions). The moves: a
prompt to this deny (13,674 verdicts), and a decaying deny — the opaque shape's, the
tokenize one's, or the `ask` they decay to — to this deny (5,844). The 3,034 still failing,
by the harness's classes: an ANSI-C quote escaping a quote (1,671, 130 of them round 6's
own tails behind ruling 66's excuse), inside or after a quoted substitution that is no
whole-argument head (1,031), a line one reading of which tokenizes (312), a build script's
name built at run time (12), git behind an environment prefix (6), backticks (2).

### Over-denies (each in `hooks/README.md` → "What the both-readings rule over-denies")

8,104 verdicts on 6,630 lines are this deny where there was a prompt before and the
harness saw bash run no ref-moving git command and no build script. All are the corpora's
attack lines: a line that names git and that the hook's lexer cannot read, on which bash
either stopped before the git command or ran one the harness does not count (`git push
origin main` outside a checkout whose branch is known, `git status`). Of the 3,964
legitimate lines in rounds 4, 5 and 6's corpora, none changed. What the rule costs, by
kind (the README bullet's four):

- **A read before the open quote** (`git status⏎echo '#`): bash runs the read and stops.
- **A message or PR body whose terminator and closing quote were both dropped** (`git
  commit -m "$(cat <<'EOF'⏎msg`): bash runs nothing. A prompt before; close it.
- **A heredoc never terminated, an odd quote after it, on a line that names git** (`git
  status ; cat <<EOF⏎it's`): bash reads the rest as the body and warns.
- **A git word that is only text inside the open quote** (`echo 'git push`): the tokenize
  deny before, this one now — a reason about the lifecycle on a line that wanted a quote.

### Found, not fixed (round 6)

- **One reading tokenizes, bash's does not hold the command in quotes** (312 lines, each
  failing on round 5's hook too): a comment in doubt kept as text, whose apostrophe pairs
  with a later odd quote, beside a body no reading places — `(ls) # it's⏎git push -f
  origin y⏎cat <<EOF⏎echo '`. Bash parses the line (the heredoc runs to its end) and runs
  the push; the reading that keeps `# it's` as text lexes, with the push inside a quote.
  `self/BACKLOG.md`, leftover (c); `hooks/README.md`, "What still reaches a prompt".
- **Text before the `$(` with an odd delimiter and a run-on line** (111 of round 5's
  corpus, `echo "x$(cat <<"E'F"⏎x⏎E'F )" ; git push -f origin y⏎E'F⏎)"`): `bash -n` refuses
  the line and bash still ran the push; the hook's plain reading tokenizes it as quoted
  words. The BACKLOG scope entry's class (a head that is not `HEREDOC_OPENED_HEAD_RE`'s),
  failing before the round as well.
- **The ANSI-C excuse on a broken line** (ruling 66) and **a line with no git** that holds a
  `<<` or a `#` (still a prompt where its twin without them is the tokenize deny): BACKLOG
  leftovers (a) and (b).

## Round 7

The rework of `escalations/06-review-opus.md` (round 6's rule hard-denied valid bash: `git
commit -m "$(echo "it's")"`) and `escalations/06-audit-opus.md` (B1: one `$'\''` anywhere
switched the rule off on a line bash cannot parse either). Both came from the hook guessing
what bash parses. The coordinator's decision, owner-approved: **round 6's deny also requires
that bash itself refuses the line** — `bash -n` over the command text — and when bash refuses,
the ANSI-C excuse does not apply; when bash parses the line it keeps exactly the verdict round
5 gave it. Tests were written first and run red against round 6's hook (`allow-repo-commands.sh`:
167 failures over the two profiles — every `BASH_REFUSED_GIT_DENY` row a prompt, every
`BASH_PARSED_QUOTE_DENY` row the git reason, the two `#` rows of `BASH_PARSED_PROMPT` a deny;
`hook-escalation.sh`: 10c and 10d red). The change was composed and run on a scratch copy of
the tree — all twelve hook test files and the differential — and then applied in ONE Edit call
to the hook, compared byte for byte with the copy the tests had run on, and TWO to
`hooks/README.md`.

### Build rulings

70. **The condition.** `judged_texts`' last test is now: no reading is JUDGED — for every
    text, `chain_tokens` returns None or `never_judged` (its `#`s removed) holds it back,
    which is the test `command_words` makes of each reading — AND the line names git AND
    `bash_refuses(command)`. Then `unread()`, as before. Round 6 counted a held-back reading
    as one that tokenizes; that was the excuse, and it is gone. It had to go on BOTH sides
    of the lexer: `git push -f origin y⏎echo $'\'' '` is a line shlex lexes (it pairs the
    quotes wrongly) and `never_judged` holds back, so "no reading lexes" alone would have
    left the audit's second reproduction a prompt. A torn reading and a line past a cap are
    answered before bash is ever asked, as in rounds 4 and 5.
71. **How bash is asked, and why nothing runs.** `subprocess.run(("bash", "--norc",
    "--noprofile", "-n"), input=<the line, encoded>, env={"PATH": "/usr/bin:/bin"},
    capture_output=True, timeout=5)` — each literal a named constant (`BASH_SYNTAX_ARGV`,
    `BASH_SYNTAX_ENV`, `BASH_SYNTAX_TIMEOUT_SECONDS`, `BASH_UNREADABLE_CHAR`), the answer
    cached per line in `BASH_REFUSALS`. Point by point:
    - *Never executes.* The text is stdin, never `-c` and never a file path, so nothing the
      attacker writes is an option or a path; stdin is a pipe that closes after the text, so
      the shell is not interactive (an interactive shell ignores `-n`). Tried on bash 5.2.21
      with sixty texts that each try to create a canary file — a plain command; `$(…)`,
      backticks, `<(…)`, `>(…)`; a substitution in a heredoc body, in `${x:=…}`, in
      `$((…))`, in an array subscript, in `[[ ]]`, `(( ))`, `case`, `for`, `select`; a
      redirect (`> f`, `exec 3> f`); `set +n` and `set +o noexec` before the command; traps
      on EXIT, DEBUG and ERR; `PS4`, `PROMPT_COMMAND`; `shopt -s expand_aliases` with an
      alias, a function defined and called; `eval`, `exec`, `.`, `command`, `coproc`, a NUL,
      a line with an open quote after the command: **none created the file**
      (scratchpad `r7/bashn_probe.py`; seventeen of them are kept as a canary check in
      `hook-cloud-profile.sh` H20).
    - *No startup file, no inherited state.* `--norc --noprofile`, and an environment of
      `PATH` alone — no `BASH_ENV`, `ENV`, `SHELLOPTS`, `BASHOPTS`, `BASH_FUNC_*`; H20 sets
      `BASH_ENV`, `ENV` and `SHELLOPTS` in the test's own environment and the canary stays
      absent. The `PATH` is the system's two directories, not the session's, so a `bash`
      planted in the project or earlier on the session's `PATH` is not the one asked.
    - *Aliases, `shopt`, extglob.* Nothing executes, so a `shopt -s extglob` or an `alias`
      on the line turns nothing on: `shopt -s extglob⏎git add !(x) $'\''` is refused (a
      syntax error at the `(`), as is `git add !(x) $'\''` alone. That can only add a deny,
      and only on a line no reading judges; it is one of the round's over-denies, pinned.
    - *Fails closed.* `bash_refuses` is True unless the exit status is 0 AND stdout and
      stderr are both empty AND the text holds no NUL. No bash on the PATH, a program that
      cannot be run, a timeout, a non-zero exit, any output, a character that does not
      encode: refused (H20 patches the constants and asserts each, with the review's line
      becoming the unreadable git command). "Any output" matters: a heredoc that is never
      terminated exits **0** with a warning, and bash ran what stood before it (`git push -f
      origin y⏎cat <<EOF⏎echo '` — round 6's ruling 65 — would otherwise have reopened).
    - *Only adds.* The call sits behind `unjudged and unread()` in one `and` chain: its
      answer is read nowhere else, and the two outcomes are `unread()` (the git deny) and
      `texts` (what round 5 returned for a line that is not torn). No approval reads it.
    - *Cost.* Asked only when no reading is judged and the line names git; once per line.
      H20 asserts nothing is asked for a judged line, a line with no git or a torn reading.
      One call is about 1.6 ms here.
72. **`eval`, and the shell that really runs the line.** Claude Code hands the command to
    `eval` in the session's shell. `eval` parses and runs a command at a time, as bash reads
    stdin, so the two agree on which lines stop part-way: over 112 lines (round 7's 56 tails
    after a stub push, joined by a line break and by `;`), `bash -n` refused exactly the
    lines on which `bash -c 'eval "$1"'` reported a parse error, except the two that begin
    `shopt -s extglob` (refused by `-n`, run by `eval`: the over-deny above) — scratchpad
    `r7/eval7.py`. What `-n` cannot model is the session: its aliases and `shopt`s (a
    snapshot may enable both), its bash version, or zsh. A line that parses only there is
    denied; a line that fails part-way only there and parses for the system bash keeps the
    verdict round 5 gave it. Neither direction approves anything. BACKLOG leftover (d).
73. **Rows.** None weakened, deleted or moved. New in `allow-repo-commands.sh`:
    `BASH_REFUSED_GIT_DENY` (38 rows: the audit's five first lines × five second lines, ten
    variants, a heredoc never terminated, two pinned over-denies), `BASH_PARSED_QUOTE_DENY`
    (5: the review's first and third lines and three twins — DENY, the quote's reason, none
    of the git deny's words), `BASH_PARSED_PROMPT` (7: the review's second line and its twin after
    a push, four well-formed ANSI-C lines, the audit's tail with no git). `hook-cloud-profile.sh`:
    H20 (15 checks) and the T table's round-7 block (39 rows). `hook-escalation.sh`: 10c
    (the review's lines decay: deny, deny, ask) and 10d (five B1 lines never do). Kept as
    prompts, as the brief asked: `git commit -m $'it\'s'` and `git push -f origin y⏎echo
    $'\''`. One verdict round 6's documents called a prompt is a deny now and is pinned as
    one: `git push -f origin y; echo $'\'' "` (one line; bash runs nothing of it).
74. **Docs.** `hooks/README.md`: the round-6 over-deny bullet (its false "NOT one: anything
    bash tokenizes" is now "anything bash parses", with the review's class named), the
    rule's paragraph, a new paragraph on `bash_refuses` with the four security points, and
    "What still reaches a prompt" (one Edit — the three are adjacent); and the seventh
    opaque shape's stale `git rebase 'main` example (the second). "The git shape" still
    says a line that does not tokenize is "refused whole"; the rule's paragraph names that
    sentence and says when it holds — a third `hooks/` README Edit was outside the limit.
    `self/BACKLOG.md`: the "cannot tokenize" entry's leftover (a) rewritten (what bash
    parses), leftover (d) added (the bash asked is not the session's shell).
75. **Size.** 15 net code lines in the hook (18 added, 3 replaced; 53 physical lines
    added, 8 removed, the rest comment and docstring). Three `hooks/` Edit calls: one on the
    hook, two on `hooks/README.md`.

### Differential check

Round 2's harness again (three checkouts, logging stubs, bash 5.2.21), all three trees rerun
over every corpus: round 5's hook (`30d239d`'s), round 6's (`HEAD` before this round) and
this round's. Round 7's corpus is new: 16 payloads × 7 things before them × 56 tails (32
with an ANSI-C quote escaping a quote — 26 that bash refuses, 6 well formed — and 24
without: 11 bash parses, valid bash the lexer mostly refuses (a quoted substitution,
backticks, `${x:-"…"}`, `$"…"`, an alias), and 13 it refuses (the same left open, a quote
inside `(( ))`, `${x:-'}`, `[[ ]]` and an array, extglob, heredocs never terminated)) × 3
things after; the same joined by `;` and `&&`, tail first, payload in a
`$(…)`, tail as an argument; 576 legitimate lines (eight commands × twelve message words —
the review's three, backticks, `${x:-"it's"}`, ANSI-C, a usual heredoc — × six endings).

| Corpus | Lines | Failing on round 5's hook | On round 6's | After |
|---|---|---|---|---|
| round 7's | 23,936 | 7,131 | 4,966 | 2,769 |
| round 6's, again | 16,919 | 3,323 | 148 | 19 |
| round 5's, again | 80,338 | 3,277 | 593 | 1,269 |
| round 4's, again | 62,742 | 2,926 | 1,969 | 1,625 |
| rounds 2 and 3's eight, again | 117,287 | 435 | 324 | 434 |
| **all** | **301,222** | **17,092** | **8,000** | **6,116** |

The two baselines reproduce round 6's table on the old corpora (9,961 and 3,034).

- **Against round 5's hook: 0 verdicts looser of 903,666**, no line newly failing, no line
  newly approved, none approved on which bash ran a denied command. 26,461 verdicts moved,
  every one to the unreadable-git deny: 18,926 from a prompt, 7,535 from a decaying deny or
  the ask it decays to. Of the 4,540 legitimate rows (the 3,964 of rounds 4, 5 and 6's
  corpora and round 7's 576), none changed.
- **Against round 6's hook: 3,244 verdicts looser, every one on a line `bash -n` accepts**
  (0 on a line it refuses) — 1,771 from the git deny back to a prompt, 1,473 back to a
  decaying deny. On 1,790 of those lines bash ran a denied command: valid bash after or
  around a push that no reader here lexes (`git push -f origin y⏎echo "$(echo "it's")"`),
  which is the decision's stated cost — the verdict round 5 gave, never an approval — and
  the BACKLOG's quoted-substitution class. Stricter than round 6: 6,389 verdicts (5,989 from
  a prompt), all on lines bash refuses behind an ANSI-C quote. 170 legitimate rows changed,
  all round 7's own and all the review's class (the git deny back to the tokenize deny or
  the prompt); none of the 3,964.
- **The 6,116 still failing**, by what bash and the hook say of the line: bash parses it
  and no reading is judged, so bash was asked and said yes — 3,432 (1,846 behind an ANSI-C
  quote, 1,586 behind a quoted substitution and its kin); bash parses it and a reading is
  judged that does not hold the command — 1,352; bash REFUSES it and a reading is judged, so
  bash was not asked — 1,320, each failing on rounds 5 and 6's hooks too (the comment in
  doubt kept as text, 342; a run-on line inside a quoted substitution with an ANSI-C quote
  after it, 853; text before the `$(` with an odd delimiter, 111; a process substitution,
  14); a build script's name built at run time — 12.

### Over-denies (each in `hooks/README.md` → "What the both-readings rule over-denies")

Against round 6's hook, 2,715 verdicts on 2,715 lines are this deny where there was a prompt
(2,333) or a decaying deny (382) and the harness saw bash run no ref-moving git command and
no build script. All are attack rows of the corpora, and all hold an ANSI-C quote on a line
bash refuses. By kind:

- **One line with a quote left open after the ANSI-C one** (`git push -f origin y; echo
  $'\'' "`, and with `&&`, or the broken tail first): bash runs nothing. A prompt before.
- **A command the harness does not count before the broken line** (`git push origin main⏎echo
  $'\'' "` outside a checkout whose branch is known, `git status⏎…`): bash ran it and stopped.
- **A heredoc never terminated with the escaped quote in its body** (`git status cat
  <<EOF⏎$'\''`): bash reads the body to the end and warns.
- **A git word inside what zsh reads as an ANSI-C quote and bash as an open one** (`echo
  $$'a\' ; git push -f origin y '`): bash runs nothing; zsh would have echoed it.
- **A line that parses only under an option the check does not have** (`shopt -s
  extglob⏎git add !(x) $'\''`): valid where it runs, refused here. The one over-deny of
  this round that is not broken for the shell that runs it; needs an ANSI-C quote escaping a
  quote (or another shape no reading judges) on the same line.

Round 6's four kinds remain as that round listed them, each on a line bash refuses. Round
6's fifth, which its review found — the quoted substitution with an odd inner quote — is
gone: bash parses it.

### Found, not fixed (round 7)

- **Valid bash no reader here judges, on a line that names git** (4,784 lines of the corpora
  where bash ran a denied command): `git push -f origin y⏎echo "$(echo "it's #")"` and
  `git push -f origin y⏎echo $'\''` are prompts, and without a `#` or a `<<` the first is
  the decaying tokenize deny. Round 6 denied the first kind; the decision gives it back. An
  attacker who can write the line can therefore still buy a prompt (never an approval) for a
  push by appending such a word — as on `main`, and as with the ANSI-C word in every round.
  `self/BACKLOG.md`, leftover (a) and the scope entry.
- **Bash refuses the line, a reading is judged, and the judged reading does not hold the
  command** (1,320 lines, failing before the feature's rounds 5 and 6 as well): bash is not
  asked. Asking bash about EVERY line that names git and is not already denied would close
  these — at the cost of a subprocess per git line and of denying what parses only in the
  session (`git add !(x)`, which the hook reads today) and every unterminated heredoc on a
  git line. Not this round's decision; BACKLOG leftover (c).
- **The bash asked is not the session's shell** (ruling 72): BACKLOG leftover (d). Bash 3.2
  (the macOS `/bin/bash`) was not available to try; `-n`, `--norc` and `--noprofile` are
  all older than it, and what it refuses that 5.2 parses is one more deny.

