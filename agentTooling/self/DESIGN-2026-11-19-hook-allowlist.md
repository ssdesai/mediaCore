# Design 2026-11-19 — the hook approves an allowlist of simple lines, and reads nothing else

Feature slug of this record: `hook-allowlist-design` (a design only; no code changes with
it). Status: **proposed**. The owner's merge of this feature's PR is the sign-off, and the
decisions in §7 are then taken as recommended unless the merge says otherwise. The build is
three later features (§8). Approved in direction by the owner on 2026-11-18; this record
answers the eight questions that approval asked, one per section. Every statement about
today's hook is of `hooks/allow-repo-commands.sh` at this feature's base (5,867 lines), and
every measurement was made in this feature's container (bash 5.2.21, no zsh) with the
scripts in `features/hook-allowlist-design/prototype/`; its `README.md` holds their output.

## The defect

The hook decides what bash will run by reading the line itself. Approval
(`command_allowed`, line 4995) refuses the `UNANALYSABLE` texts and `fails_closed` lines,
deletes `HARMLESS_REDIRECT_RE` matches from the raw text, refuses a `SHELL_ACTIVE_CHARS`
character outside single quotes and any brace that is not simple, then lexes with `shlex`
and judges each group. The deny side reads **every reading bash may make** (`judged_texts`):
`comment_and_heredoc_free` with its flips, run-on lines, joins and opened heads, then
`chain_tokens` (shlex again, over a masked line), `never_judged`, torn readings, and since
round 7 of `hook-audit-gaps` a `bash -n` call. Those readers — `never_judged` at line 1292
through `judged_tokens` at line 2090 — are about 800 lines, and `hooks/README.md` spends
lines 338–693 describing them.

It does not converge. `orchestration-record-fixes` patched one grammar shape per round from
round 3 to round 8 and removed the scoped reading in round 9 (its `NOTES.md`).
`hook-audit-gaps` ran seven rounds; its last differential check still counted 6,116 of
301,222 generated lines on which bash ran a denied command and the hook's answer was not a
deny that holds (`NOTES.md`, round 7). Each round also wrote a stronger sentence into the
README, and each sentence became the next audit's target.

Writing the grammar of §1 down found three more disagreements in an afternoon, **on the
approval side**, each confirmed against bash (`prototype/probe.py`). In each, `command_allowed`
returns True and bash reads a file the hook did not judge:

| Line | What the hook judged | What bash opens |
|---|---|---|
| `cat 'a >/dev/null b'` | `cat 'a  b'`: `HARMLESS_REDIRECT_RE.sub` runs over the raw text before any quote is read | the path `a >/dev/null b` |
| `cat dir/[^i]*` | the files `value_confined`'s Python `glob` matches, where `[^i]` is the set of `^` and `i` | every file **not** starting with `i` |
| ``cat "dir/\`x"`` | ``dir/\`x``: shlex keeps a backslash before a backtick inside double quotes | ``dir/`x`` |

With a symlink at the path bash opens, each read a file outside the root. All three need a
link already in the tree, which `hooks/README.md` → "Accepted limits" counts as a prior
write, and none is in `self/BACKLOG.md`. They are evidence of the class: an approval that
rests on two readers agreeing has a next spelling. Today's reader also approves `ls src &`,
`ls src;` and `cat =python3` (the last is `/usr/bin/python3` to a zsh, which this container
does not have to confirm).

**The rule this design adopts.** The hook stops modelling bash. It reads one small language,
the *simple line*, with a reader that admits characters instead of refusing them. A line in
that language means the same to every shell the Bash tool runs in; a line outside it is
never approved silently, and is not read finely for anything else either.

## §1 The approved grammar (D1)

One reader, `simple_line(text)`, replaces `shlex` and every walk. It returns the line's
commands — each a list of literal words, its redirects and its environment prefix — or
nothing. It generalises `orchestrator_words` (line 5380), which already reads the
orchestrator's allowlist this way: character by character, a word a plain literal or the
line refused.

```
line      = command { sep command }
sep       = "&&" | "||" | ";" | "|"                    blanks around it optional
command   = { assignment blank } word { blank ( word | redirect ) }
redirect  = "2>&1"
          | ( ">" | ">>" | "1>" | "1>>" | "2>" | "2>>" | "&>" | "<" ) [ blank ] word
word      = piece { piece }  |  heredoc
piece     = bare { bare }  |  "'" { any character but ' }  "'"
          |  '"' { any character but " $ ` \  |  "\" any character but LF } '"'
bare      = letter | digit | one of  _ - . / : @ % + , =  |  "*"  |  "?"  |  "~"  |  "^"
heredoc   = '"$(cat <<' "'" NAME "'" LF { body-line LF } NAME LF { blank } ')"'
blank     = space | tab
```

with these conditions, each one a refusal:

- **Characters.** Outside quotes, only the `bare` characters, blanks and the separators and
  redirect operators above. Everything else puts the line outside the grammar: `$`, a
  backtick, `\`, `#`, `&` alone, `(` `)` `{` `}` `[` `]` `!`, `<` or `>` in any other form
  (`<<`, `<<<`, `<(`, `>&`, `>|`, `<>`, a descriptor other than `1` or `2`), a line break,
  a carriage return, any other control character, and any non-ASCII character. A NUL is
  refused anywhere.
- **Quotes.** Single quotes hold literals. Double quotes are POSIX's and no more: a
  backslash escapes `$`, a backtick, `"` and itself, is a literal before any other
  character, and is refused before a line break; a bare `$` or backtick is refused. Outside
  quotes there is no escape character: an unquoted backslash is refused.
- **Words.** `=` may not start a word (zsh expands `=name` to a path). `~` and `^` are
  admitted only directly after a letter, a digit, `~` or `^` (`HEAD~2`, `HEAD^`), never at
  a word's start or after `=` or `:`. `**` is refused (zsh, and bash under `globstar`,
  recurse). `*` and `?` are the only patterns, and never in a command's first word or a
  redirect's target, which are literals.
- **Commands.** No empty command: no leading, trailing or doubled separator. The first
  word, when written bare, is not a shell reserved word: bash's (`if then else elif fi for
  while until do done case esac select function time coproc in`), zsh's own (`repeat
  foreach end nocorrect`), or a declaration command (`declare export float integer local
  readonly typeset`), which zsh parses as a reserved word and both shells read an
  assignment-shaped argument of differently from an ordinary word. An `assignment` is
  `NAME=` followed by pieces, before the first word only: an environment prefix.
- **The heredoc word** is the one canonical commit-message form and nothing near it: a
  whole word, never the first of a command; `cat`, one space, `<<`, a single-quoted
  identifier; no `<<-`; no body line that **begins with** the delimiter (so no run-on line
  exists for bash 5.2 to end the substitution at); the terminator alone on its line; then
  optional blanks and `)"`, and the word ends there. Its value is the body, trailing line
  breaks removed, as `$(…)` removes them. This is `heredoc_argument_at(…, strict=True)`
  (line 2039) narrowed to a single-quoted delimiter directly after the `<<`, with blanks
  admitted before the `)`.
- **Length.** A line longer than `ORCHESTRATOR_MAX_LINE_CHARS` (20,000) is outside it.

A line break is admitted inside quotes and in a heredoc body, where it is text. So the
language has no expansion but pathname expansion of `*` and `?`, no quoting that two shells
read differently, and no construct whose extent depends on what follows it.

**Two tiers.** *In the grammar* means read: the deny side judges such a line exactly (§3).
*Approvable* is narrower, and is what `command_allowed` asks before today's per-command
rules (`subcommand_allowed`: the program lists, `token_confined`, the git and runner
forms), which do not change:

- one physical line: no line break anywhere, quoted or not, and no `..`, as `UNANALYSABLE`
  has it today;
- no heredoc word, and no environment prefix (today's rule at line 4899);
- no redirect but `2>&1` and an output redirect whose target is exactly `/dev/null` — what
  `HARMLESS_REDIRECT_RE` admits today, read as a redirect instead of deleted as text;
- a pattern is confined when every path it matches, hidden names included, resolves
  inside the root (`value_confined`, with `*` and `?` only, where Python's `glob` and the
  shells agree; matching hidden names as well covers a session that sets `dotglob`).

"ALLOW is `command_allowed`'s answer and nothing else" (`DESIGN-2026-09-18-hook-rewrite-or-ask.md`
§1) stands; only that function's reader changes. The two things the reader newly *reads* —
an environment prefix and the heredoc word — are never approvable. Three kinds of line
become approvable that prompt today, each because today's raw-text tests refuse a literal
the reader reads exactly, and each still subject to every per-command rule: a `<` or `>`
inside double quotes (`grep "a<b" f`; `SHELL_ACTIVE_CHARS` is tested outside single quotes
only); a quoted word made of operator characters (`grep ';' f`; `quoted_separator_word`);
and a read-only git line holding the word `case` or a single-quoted `$(` (`git log --grep
case -1`; `fails_closed`, whose costs `orchestration-record-fixes` round 9 pinned). Nothing
else is approved that is not approved today.

**What is approved today and falls outside** (each verified with `prototype/probe_dropped.py`).
Each is sent back — the REWRITE verdict, with the escalation it has today — and the reason
names the rewrite:

| Shape, approved today | Example | The rewrite the denial names |
|---|---|---|
| a comment, or a `#` inside a word | `ls src # list it`, `cat src/a#b` | drop the comment (the Bash call's `description` carries it); single-quote a word that holds `#` |
| a simple brace group | `ls {src,tests}` | expand it yourself (`BRACE_REWRITE_REASON`, which today covers only the groups the expansion refuses) |
| a bracket pattern | `cat [R]EADME.md` | name the file, or use `*` / `?` |
| an unquoted backslash | `grep -n \# f` | single-quote the word |
| `&` | `ls src &` | run the call in the background instead |
| a trailing or empty command | `ls src;` | drop the separator |
| `**` | `ls src/**` | `find <dir> -name '<pattern>'` |
| a word starting with `=` | `cat =x` | quote it, or write the path |

Nothing else approved today is outside: `&&`, `||`, `;`, `|`, single and double quotes
(a `$`, a backtick or a `<` inside single quotes stays a literal, and `"a\|b"` and `"\$x"`
are read as bash reads them), `2>&1`, `/dev/null`, `*`, `?`, `HEAD~1`, `HEAD^`, tabs. A
plain `cat <<EOF`, `$'…'`, `$(…)` and a backtick were never approved.

## §2 The oracle (D2)

Two oracles, for two different questions.

**At run time: does bash parse the line?** `bash_refuses` (line 1971) is kept as it is —
`bash --norc --noprofile -n`, the line on stdin, an environment of `PATH=/usr/bin:/bin`
alone, a five-second timeout, and anything but exit 0 with no output a refusal — and its
caller changes. Today it is asked by `judged_texts` only, about a line that names git and
that no reading judges, and its answer only adds a deny. Under this design it is asked about
every line `command_allowed` is about to approve, and a refusal withdraws the approval: the
line prompts. No deny reads it any more (§3). The cost is one subprocess per approved
command, about 1.6 ms (`hook-audit-gaps/NOTES.md`, ruling 71).

It confirms that the system's bash finds the line complete: no quote left open, no
construct waiting for more input. For a line in the grammar it should never refuse; it is
there so that a mistake in the reader that admits an unbalanced line costs a prompt and not
an approval.

**At gate time: does the shell read the line as the hook did?** `bash -n` cannot say — it
prints nothing about words. The differential harness of §4 can, by running generated lines
in a sandbox and comparing what the shell invoked with what the reader returned. That check
is what stands behind "a line in the grammar is read as the shell runs it".

**When the session's shell differs** (`self/BACKLOG.md`, item (d) of "A line the hook cannot
tokenize"): the hook is not told which shell runs the command, and this design does not try
to find out. The oracle is a fixed reference, the system bash with no options, and the
guarantee is stated against named shells: the grammar is chosen so that bash and zsh, with
their default options, read every line of it alike, and the harness runs under every bash
and zsh it finds (`/bin`, `/usr/bin` and `PATH`: on the owner's Mac, bash 3.2 and zsh). Item
(d) is closed by that statement. The extglob over-deny it describes goes with the deny that
asked bash (§3).

**What neither confirms**, and `hooks/README.md` will say so:

- the session's aliases, functions and options (`alias ls=…`, `setopt extendedglob`,
  `shopt -s nocaseglob`): an approved `ls` is whatever `ls` is in that shell, as today;
- what an approved program does with its arguments: the program lists' business, unchanged;
- a shell not named above;
- **that a heredoc body is data under bash 3.2.** Bash 5.2 runs nothing from the bodies
  `prototype/heredoc_probe.py` tries. Bash before 4.0 found the end of a `$(…)` by matching
  parentheses and quotes without parsing the command inside, so a body holding `)"` may end
  the word early there. Not confirmed: this container has no bash 3.2. It is why a line with
  a heredoc word is never approvable, whatever the answer turns out to be.

## §3 The deny side (D3)

The deny side stops taking readings. Four rules, in `main()`'s order:

1. **An orchestrator session runs only its allowlist** — unchanged, and already the right
   shape: deny by default, so a build script in an orchestrator session is refused because
   it is not on the list, not because a reader found it. `orchestrator_words` is replaced
   by `simple_line`, with the allowlist's narrower conditions applied to what the reader
   returns (no pattern, no environment prefix, no backslash in double quotes, no redirect
   but `2>&1` and `> /dev/null`, a heredoc word only where the list names one). One
   spelling it reads today goes: `"$(git branch --show-current)"`, which the allowlist's
   own text no longer names and the cloud's push rule already refuses.
2. **In the grammar, the shape denies are exact.** The chained `cd`, the git table
   (`policy.py`: force push, the protected branch, reset, rebase, the branch and worktree
   forms, and the cloud-only switch and push), and the build-script deny on the
   unreadable-ledger path judge the reader's commands — the words bash runs. An environment
   prefix is read past, so `X=1 git push --force origin x` is the push it is. Every word
   that is `git` starts a git command for the table, whatever program leads the command
   (`env git …`, `command git …`, `sudo git …`, `xargs git …`; the cost is `echo git push
   --force origin x`, denied). A `-C`, `--git-dir` or `--work-tree` value holding `*` or
   `?` makes the git command unreadable, which the table already denies
   (`GIT_UNREADABLE_ARGS`).
3. **Outside the grammar, a line that names git is denied whole.** "Names git" is today's
   test: `GIT_WORD_RE` over the text with quotes and backslashes deleted
   (`GIT_WORD_DROPPED_CHARS`), and with line continuations deleted. The deny does not
   decay, and its reason says what put the line outside the grammar and the rewrite — the
   lifecycle text is for a ref-moving command the hook has read, not for a commit message
   with a backtick in it. A rewrite always exists: any argument can be written in single
   quotes or as the heredoc word, and a substitution is run first and its output inlined.
   This replaces `fails_closed`, the torn-reading and past-a-cap denies and the `bash -n`
   deny.
4. **Outside the grammar, anything else gets today's verdict layer**: the authoring,
   opaque and rewritable shapes of `command_verdict` (raw-text tests that name a rewrite,
   kept as they are less their `never_judged` guard), the new reasons of §1's table, and
   otherwise nothing printed. On the unreadable-ledger path such a line is refused
   outright, which widens `unreadable_ledger_refuses` from its markers to the whole class.
   The own-assignment deny goes: `X=/p; cat $X/f` is outside the grammar for its `$X`, and
   `VAR_USE_REWRITE_REASON` gives the same advice.

**Why rule 3 and not one plain reading.** `prototype/deny_side.py` ran both over the 680
rows of the deny-side tables in `self/tests/allow-repo-commands.sh`. 451 are outside the
grammar, and the three shape denies deny 336 of them today. A single reading (today's
`chain_tokens` over the raw line, then over each physical line) keeps 242 of those denies,
loses 94 to a prompt, and adds 21 denies on text bash never runs (a heredoc body, a
comment). Rule 3 keeps all 298 that name git with no reader at all, and can not be met by
the next spelling, because it does not look at the spelling.

**What stays best-effort, by design.** The hook's denies are early feedback, and the README
will say so (§5). A force push, a push to the protected branch or a build script reaches a
prompt rather than a deny when:

- git is run without its name on the line — `$CMD push --force`, `eval`, a script, an
  alias, a name `xargs` reads from a pipe;
- the spelling is one git accepts and the table does not list. Two known ones are built
  (an abbreviated long option, by `orchestrator_option_hits`'s unique-prefix test; a short
  cluster on `checkout` and `switch`, as `bundles_push_force` reads `push`'s); a git alias
  and whatever git adds next are not;
- on the unreadable-ledger path, the build script's name is made at run time.

None of these is an approval: an approved line is in the grammar, where its commands are
the allowlisted readers and a read-only git. Ref protection belongs to the forge and to
`permissions.deny`'s prefix rules, which bind in every permission mode; the hook's deny is
the finer net in front of them.

**The backlog entries.**

| Entry (`self/BACKLOG.md`) | Disposition |
|---|---|
| The git deny reads git only at command position | closed by the build: rule 2 for the prefix and the wrappers, rule 3 for `!`, `time` and `{ …; }`, which are outside the grammar |
| The git deny matches flags as written, not as git reads them | the two listed spellings built; the rest **best-effort by design**. `git push origin +x` keeps its pending owner ruling |
| A line the hook cannot tokenize: three leftovers | (b) closed by the build: the reader knows it stopped at an open quote, and no raw-text guard excuses it. (c) closed by the build: rule 3. (d) **closed by design**: §2 |
| The deny side does not follow a substitution's scope | every example names git: closed by the build, rule 3. A substitution on a line that does not: **best-effort by design** |
| On the unreadable-ledger path, a build script's name built at run time | **best-effort by design**: no line reader sees a name that is not on the line. Rule 4 refuses the lines outside the grammar there; `awk 'BEGIN{system("./run-pl" "ans.sh")}'` is inside it and stays a prompt |
| The git deny does not read a pattern location | closed by the build: rule 2 (`*`, `?`) and rule 3 (`[`, extglob) |
| The hook judges by re-implementing bash's reader | closed by the build: §1, §2 |
| The bash-vs-hook differential harness is not committed | closed by the build: §4 |
| `hooks/README.md` promises more than "never silently approved" | closed by the build: §5 |
| A writable git config defeats the hook's approvals generally | **left open**: not a reader problem. The same principle answers it (approve against a config the hook controls, not a list of keys to refuse), as its own feature |

The other entries filed by `hook-silent-allow-sweep` (a nested `--config`, the gate
spellings by layout, the role rule's sentinel, `GIT_TRACE*`, the two narrowings) and the
`.git` Edit-deny entry are about what is approved inside the grammar, and are untouched.

## §4 The differential harness (D4)

`self/tests/hook-grammar-differential.sh`, recorded by `self/gate.sh` beside
`hook-quote-oracle.sh`, which is its model (a fixed seed, the shells as the oracle, zsh when
installed) and which it replaces once `never_judged` is gone.

**What generates the commands.** Lines over an alphabet of tokens, not characters: the stub
programs `p0`, `a`, `b`; the words `git`, `push`, `-f`, `main`, `cd`; every character class
the grammar admits or refuses (a blank, a tab, both quotes, each separator, `&`, each
redirect operator, `2>&1`, `#`, `\`, `$`, `*`, `?`, `=`, `~`, `^`, each bracket, `!`, a
line break, a carriage return, a non-ASCII blank, a reserved word). Every string of up to
three tokens after a fixed `p0 `, and a seeded random set of longer ones; plus a second,
smaller corpus built **from** the grammar's productions, heredoc words with hostile bodies
included, so the test also fails when the reader stops accepting what this record says it
accepts.

**The oracle** is the shell itself, running each line: one driver per shell, each line
`eval`ed in a subshell whose `PATH` is empty and whose directory is an empty sandbox, with
`p0`, `a`, `b`, `git` and `cd` defined as functions that log their arguments. No generated
line can name a path outside the sandbox (the alphabet has no `/`, and `HOME` is the
sandbox), and nothing but the logging functions can run.

**What fails the gate**, per shell:

1. a line the reader places in the grammar on which the shell invoked something the reader
   did not return — a program, or any one word, differs — or created a file that is not
   one of the reader's redirect targets, or reported a syntax error;
2. a line of the grammar-built corpus that the reader refuses;
3. a line the hook's `main()` approves (called in-process, in a fixture root where the
   stubs' names are allowlisted reads) that is not approvable under §1;
4. a line on which the shell invoked `git` with arguments `git_mutates` calls ref-moving,
   and `main()`'s answer was not a deny that holds. Every such line names git, so rule 2 or
   rule 3 owes it.

Checks 1 and 3 together are the backlog's assertion ("no silent-approval path depends on
the hook's tokenizer agreeing with bash outside the allowlisted shapes"), and check 4 is
the differential's ("the gate fails on any generated command the hook approves while bash
runs a command the hook denies"), stated one step stronger.

**The prototype has run check 1** (`prototype/mini_diff.py`, bash 5.2.21): 87,988 lines over
36 tokens. Its first run failed on one line: `p0 >a|*`, where the redirect creates `a` and
the pattern in the second command's first word then expands to it. That is where "never a
pattern in a command's first word" in §1 comes from. With the grammar as §1 states it,
5,489 lines are in it: none on which bash ran or wrote anything the reader had not read,
and none that `bash -n` refuses.

**Budget.** Under 60 seconds per shell on the gate's machine, as a constant the test prints
its elapsed time against and does not assert. For scale: `hook-quote-oracle.sh` puts 39,607
cases to bash twice in 3.5 seconds here, and the prototype's 87,988 lines took about 150
seconds with a `bash -n` process per grammar line and no batching, which the build batches.
The corpus sizes are named constants; the exhaustive depth is the one to lower first.

## §5 The README contract (D5)

`hooks/README.md` gets one section, "The contract", that replaces lines 338–693: a table of
guarantees, each with the gate test that holds it, and a list of what is best-effort. A
sentence elsewhere in the README that reads as a guarantee is moved into the table or
reworded as a description. The history of the readers stays where it already is, in the
features' `NOTES.md`.

| # | Guarantee | Held by |
|---|---|---|
| G1 | A line outside the grammar is never approved silently | `hook-grammar-differential.sh` check 3; `allow-repo-commands.sh` `OUTSIDE_GRAMMAR_NOT_APPROVED`, one row per refused class of §1 |
| G2 | A line in the grammar is read as bash, and zsh where installed, runs it: the same commands, words and redirect targets | `hook-grammar-differential.sh` checks 1 and 2, per shell |
| G3 | A line is approved only when the system bash parses it; no bash, a timeout or any output approves nothing | `hook-cloud-profile.sh` H20, re-pointed at the approval |
| G4 | An approved line's every command is an allowlisted read confined to the root, or the cloud's own-branch push alone | the existing tables: `ALLOW`, `PROMPT`, `ENTRY_*`, `RUNNER_*`, `SWEEP_*`, `PLANTED_GITDIR_CASES`; `hook-cloud-profile.sh` for the push |
| G5 | In the grammar, a chained `cd` and a git command the table lists are denied, behind a prefix or a wrapper too | `allow-repo-commands.sh` `DENY`, `GIT_DENY`, `GIT_PUSH_MAIN_DENY`, `GIT_GLOBAL_OPTION_CASES`; differential check 4 |
| G6 | Outside the grammar, a line that names git is denied, and the deny does not decay | `allow-repo-commands.sh` `GIT_OUTSIDE_GRAMMAR_DENY` (today's `GIT_AUDIT_DENY`, `UNLEXED_GIT_DENY`, `BASH_REFUSED_GIT_DENY` and `TORN_READING_DENY` rows, one table); `hook-escalation.sh` 10d; differential check 4 |
| G7 | An orchestrator session runs only its allowlist | `hook-orchestrator-role.sh`, its tables as they are |

**Stated as best-effort, with no guarantee:** the three bullets of §3; every REWRITE reason
for a line outside the grammar (a miss is a prompt); and the four "neither confirms" items
of §2.

**The contract is itself checked.** A new `self/tests/hook-readme-contract.sh` reads the
table out of the README and fails when a "Held by" cell names a test file or a table that
does not exist — the backlog's assertion, "every guarantee the README states has a gate test
row", as a test. The audit template (`templates/SECURITY_AUDIT.md`) gets one line: a prompt
on a line outside the grammar is the contract, not a finding.

## §6 Migration and cost

**Test rows that change verdict** (`prototype/measure.py` and `deny_side.py`, over the
tables as the test files spell them; rows a test builds in a loop are not counted):

- *ALLOW to sent back: 11 of 185.* Of the rows in the seven tables that expect an approval
  (`ALLOW`, `ENTRY_ALLOW`, `RUNNER_READ_ALLOW`, `SWEEP_ALLOW`, `UNCHAINED_ALLOW`,
  `BRACE_ALLOW`, `hook-escalation.sh`'s `SCRATCH_ALLOW`): `ls src # list it`,
  `cat [R]EADME.md`, and nine of `BRACE_ALLOW`'s ten. Each moves to a REWRITE table with its
  reason asserted, never deleted.
- *Prompt or decaying deny to the git deny: 34.* Lines outside the grammar that name git
  and no shape deny denies today: 11 of `GIT_NOT_DENIED` (`git status # it's`, a heredoc
  body that mentions a push, `<<-'EOF'`), 12 of `TORN_READING_NOT_DENIED`, 6 of
  `BASH_PARSED_PROMPT` (`git commit -m $'it\'s'`) and the 5 of `BASH_PARSED_QUOTE_DENY`
  (`git commit -m "$(echo "it's")"`). Each is told its rewrite.
- *A shape deny to the outside-grammar verdict: 38.* The 23 chained-`cd` rows of `DENY`
  and the 15 of `ASSIGN_DENY` that are outside the grammar (`cd <root> && cat $HOME/x`,
  `(cd <root> && ls) && ls`, `X=/p; cat $X/f`). 28 of them hold a `$`, a `$(…)`, a line break,
  a `~` or a backslash and are sent back for that; the rest take §1's new reasons or a
  prompt. Once rewritten into the grammar, the chain is denied as before. This is the one
  place a deny that does not decay becomes one that does (§7, decision 2).
- *Unchanged:* the 298 git rows outside the grammar that are denied today stay denied (rule
  3), and every row in the grammar keeps its verdict.

**Friction.** Three samples, none large. The 28-record replay fixture
(`self/tests/fixtures/hook-replay-2026-09-18.json`): its six ALLOW records all stay
approvable. The tables above: 11 of 185 approved rows, ten of them shapes a test wrote to
pin a feature (brace groups, a bracket pattern) rather than shapes a session writes. And
the one real transcript this container holds, this feature's own session, replayed through
today's hook and the prototype: of 58 Bash commands, 18 are approved today and all 18 stay
approvable. That replay changed the grammar once. The first draft refused every backslash
outside single quotes and lost 3 of the 18, each a `grep` pattern in double quotes
(`"a\|b"`); double quotes now take POSIX's escapes, which the shells share and `shlex`
reads differently. It is a session of one author on one day, and it is what could be
measured here: the owner's machine holds the transcripts that would make this a figure, and
`prototype/measure.py <root> ~/.claude/projects` prints it. The argued expectation is the
trailing comment and the bare `$` in a double-quoted commit message, each a deny naming a
small fix, met a few times per session before the model stops writing them.

**`CONVENTIONS.md` § Shell commands** gains §1's table as rows of "Sent back with a
rewrite", gains "a git command outside the simple line" with its two rewrites (single
quotes, the heredoc form), and loses most of its "Exempt" paragraph: where a heredoc body
ends, joined delimiters and brace expansion before a git command are no longer anything a
session needs to know. The one-line rule stays: every path a literal, every program named,
nothing decided at run time.

**Shipping.** The hook ships with the subtree, so each consuming repo gets each build
feature on its next `pull-agenttooling-pr<N>` (`LIFECYCLE.md` → "Propagate"), with the
security audit a change under `hooks/` owes. `hooks/policy.py`'s table does not change, so
`.claude/settings.json` and every consumer's `permissions.deny` stay byte for byte as they
are, and no `sync-plans.sh` step is added. The reader is a sibling module the hook imports
as it imports `policy.py`; a consumer's generated `plans/README.md` is untouched.

## §7 Out of scope, and decisions for the owner

Out of scope: what is approved inside the grammar (the program lists, the runners'
allowlists, the entry points, the own-push probes); the git config entry; the scratch
entry point and the sandbox; the `Edit` rules; `policy.py` and the settings twin; the
contents of the orchestrator allowlist.

Decisions, each with the recommendation the build follows unless the merge says otherwise:

1. **A line outside the grammar that names git: deny, or prompt?** *Recommended: deny,
   without decay (§3 rule 3).* It is what makes the git deny stop depending on a reader. Its
   cost is the 34 rows of §6 and, in a session, a commit message with a bare `$` or
   backtick in double quotes, which is told to use single quotes or the heredoc form. The
   alternative is one plain reading and a prompt for what it misses: 94 of 336 pinned denies
   become prompts, and the audits keep having something to find.
2. **Accept that 38 pinned shape denies become the outside-grammar verdict?** *Recommended:
   yes.* `LIFECYCLE.md` → "What escalates a round" classes a deny that becomes an ask as a
   blocking regression, and a REWRITE asks after `OPAQUE_REWRITE_ATTEMPTS`. The sign-off of
   this record is the ruling the third build feature's audit brief cites for exactly these
   rows. The alternative keeps `chains_chdir` and `uses_own_assignment` on a raw reading
   for lines outside the grammar, which keeps the readers this design removes.
3. **Drop the simple brace group and the bracket pattern?** *Recommended: drop both.* Bash
   and zsh agree on `{a,b}`, so it could stay at the price of an expansion step in the
   reader; `[…]` is where Python and bash already disagree (`[^i]`).
4. **Drop the trailing comment?** *Recommended: drop.* Admitting one means deciding where a
   comment starts, which is the question `never_judged` exists for. The Bash tool's
   `description` field is where the note belongs.
5. **Ask `bash -n` on every approval?** *Recommended: yes.* About 1.6 ms a command, for a
   second opinion that costs nothing when the reader is right.
6. **Which shells must the harness have run under before the approval side merges?**
   *Recommended: the owner's Mac gate, once, for zsh and `/bin/bash` 3.2*, since this
   container has neither; and that run settles the bash 3.2 heredoc question of §2.
7. **Report the three disagreements of "The defect" where?** They are pre-existing silent
   allows behind a planted link. *Recommended: no separate fix* — the second build feature
   removes all three — *and one `self/BACKLOG.md` entry until it merges*, filed by the
   orchestrator, since this feature's brief limits its backlog edits to pointer lines.

## §8 Build

Three features, in this order, each `--method direct`, tests first, an opus review and the
security audit. The first two can only narrow what the hook approves.

**1. `hook-simple-reader`** — the reader and the harness; no verdict changes.
- `hooks/simple_line.py`: the grammar of §1 as one function, its character sets named
  constants, stdlib only, with its row in `hooks/README.md`.
- `self/tests/hook-grammar-differential.sh`, checks 1 and 2, recorded by `self/gate.sh` and
  listed in `self/tests/README.md`; a table of lines in and outside the grammar, one per
  condition of §1, each outside row with the condition that refuses it.
- Assertions: checks 1 and 2 pass under every shell found; the hook's own tests are
  untouched and green; `git diff` of `hooks/allow-repo-commands.sh` is empty.

**2. `hook-allowlist-approval`** — `command_allowed` reads through the reader.
- `shlex`, `shell_active_outside_quotes`, `braces_simple`, the brace expansion,
  `quoted_separator_word`, `HARMLESS_REDIRECT_RE` and `fails_closed` leave the approval
  path; `bash_refuses` is asked before an ALLOW; §1's new reasons; `CONVENTIONS.md`'s rows.
- Assertions: the 11 rows of §6 are sent back, each reason naming its rewrite; the three
  lines of "The defect", their links planted, and `ls src &`, `ls src;` and `cat =python3`
  are not approved; every
  other row of the seven approval tables is unchanged; H20's fail-closed cases withdraw an
  approval; differential check 3 passes; no row anywhere moves towards an approval.

**3. `hook-allowlist-deny`** — the deny side, the deletions and the contract.
- Rules 1–4 of §3; `never_judged` through `judged_tokens`, `command_words`,
  `brace_words`, `uses_own_assignment` and `orchestrator_words` are deleted (`bash_refuses`
  and `heredoc_argument_at`'s strict form survive, the latter inside the reader); the two
  flag spellings; `hooks/README.md` → "The contract", `self/tests/hook-readme-contract.sh`
  and the audit template's line;
  `hook-quote-oracle.sh` retired with the function it tests; the backlog entries of §3's
  table removed, each by name.
- Assertions: `GIT_OUTSIDE_GRAMMAR_DENY` holds every git row of §6 as a deny that does not
  decay; the 34 and the 38 rows are pinned at their new verdicts, each listed in the
  feature's `NOTES.md`; `X=1 git push --force origin x`, `env git push -f origin x`,
  `git push --force-w origin x`, `git checkout -qb x` and `git -C se?f switch main` are
  denied; every `hook-orchestrator-role.sh` row keeps its verdict but the
  `"$(git branch --show-current)"` spelling; differential check 4 passes; the contract
  check fails on a planted "Held by" cell naming no test; the hook is shorter than at this
  record's base by more than the reader module is long.

## Deliberately excluded

- A parser for more of bash. Every construct outside the grammar has a rewrite into it, or
  is a script, which the human is asked about.
- Asking the session's own shell anything: the hook is not told which it is, and a guess is
  what this record removes.
- A deny for the best-effort cases of §3: each would be a reader of something that is not on
  the line.
- Any change to the three verdicts, the escalation counter or the headless fall-through of
  `DESIGN-2026-09-18-hook-rewrite-or-ask.md`.
