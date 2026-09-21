# Notes — hook-rewrite-or-ask

Rulings, deviations and open questions from the direct build of `hook-rewrite-or-ask`
(`AGENT_DIRECT.md`), against `self/DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1–§7 and the
manifest's S0–S6. Written as each was made, not at the end.

All seven slices are built. Three rulings (1, 2, 3) are corrections to the design's
*mechanism*, each taken because building it as written would have **widened ALLOW**, which
the design's own §1 and the review brief forbid above everything else. The observable
contract in each case is the design's.

## Rulings

1. **`command_allowed` keeps its bool, and the verdict layer sits on top of it.** The
   manifest's S1 says `command_allowed` and `subcommand_allowed` "return a verdict". They
   do not; `command_verdict` does, and it asks `command_allowed` for ALLOW and nothing
   else. Deriving the line's ALLOW from per-member verdicts widens it: `ls ;; ls` has two
   members that are each approved on their own and a separator (`;;`) the whole-line
   analysis refuses, so a per-member walk would approve a line that prompts today — and
   the same is true of every refusal `command_allowed` makes *between* members (`|&`, a
   leftover punctuation token, a redirect). The design's observable rule — any REWRITE
   member makes the line REWRITE, else any ASK member makes it ASK, else ALLOW — is
   implemented exactly, with ALLOW answered by the existing oracle. The one place a
   per-member verdict is genuinely needed is §2's mixed sequence, and `member_allowed`
   asks the same oracle about one member's text. The consequence is the feature's safety
   property, stated at `command_verdict`: this layer can only turn a silent prompt into a
   deny, never a prompt into an approval.

2. **`UNANALYSABLE` stays exactly where it is; only its judgement is split.** The design
   says "The `UNANALYSABLE` tuple goes, its members judged one by one". Removing it from
   `command_allowed` widens ALLOW three ways, each verified against the tests: `ls\nls`
   lexes as one approved command (shlex treats the break as whitespace); `cat ../absent`
   is approved because "a value that names nothing on disk is not a path"; and — the case
   the design itself lists as an ASK — `git diff main...HEAD` becomes an **approval** the
   moment the raw `".." in command` guard is replaced by the component test, because
   `main...HEAD` carries no `..` component and `git diff` is read-only. So the refusal is
   untouched and the *verdict* over it is what the new rules decide: a `..` component or a
   line break is REWRITE, a `..` elsewhere, a CR and a NUL are ASK. Every assertion the
   design asks for holds (`cat ../x` denied, `git diff main...HEAD` silent); what is not
   true is that the tuple went.

3. **The seven opaque shapes are judged before the seven new ones, and after the approval
   analysis — the existing order, unchanged.** Running the raw-text shapes first would
   expose every approved command to them, and "a command this hook understands well enough
   to allow is readable by construction" is the invariant that keeps `ls src # list it`
   approved. So `command_verdict` asks, in order: ALLOW? then `opaque_deny_reason`
   (unchanged), then the new shapes, then ASK. A command carrying both kinds keeps the
   opaque reason, which is the more specific of the two.

4. **The new shapes keep the heredoc and `#` guards the three older denies keep.** Without
   the heredoc guard, `cat <<'EOF' … cd x … EOF` is a relative `cd` (the body line reads as
   a member) and `cat a#<<EOF … EOF` with it; without the `#` guard, `ls src # X=/p; cat
   $X` is a `$NAME` the shell expands, though bash reads the whole tail as a comment. Both
   are cases the existing tests pin as prompts, and a deny must not fire on a guess about a
   body. The cost, stated where a reader meets it: `ls x#; rm -rf src` — a mid-word `#`,
   which bash really does run as two commands — stays a prompt rather than becoming the
   mixed-sequence rewrite it otherwise would.

5. **The brace rewrite fires only for the three cases the design's table names** — a quote
   or backslash mixed into a braced word, nesting, and an expansion past
   `MAX_BRACE_WORDS`. A comma-less `{a}`, a sequence expression `{a..c}` and find's `{}`
   are braces **bash itself leaves alone**: nothing expands, so there is no expansion for
   the model to do by hand and no rewrite to name. They keep prompting, and
   `find . -exec rm {} \;` — which would otherwise collect a nonsense "expand the brace
   yourself" — is asserted as a guard in `BRACE_PROMPT`.

6. **A wholly single-quoted word is not a path token for the `..` rule.** `grep '../x'
   src` carries a regex, not a path, and `path_body` already leaves single quotes where
   they are for exactly this reason (`minutes-slug-and-quoting` ruling 5). The rule
   therefore skips a `single_quoted_word`, and requires a `/` in the word before splitting
   it into components, so `cd ..` is answered by the `cd` rule and `{a..c}` by the brace
   rule. The value after a `=` is tested too, which is what catches `--out=../x`.

7. **A `pushd` is judged with `cd`.** The design's table says "a lone relative or bare
   `cd`"; `CHDIR_PROGRAMS` already holds both for the chained-cd deny, and a relative
   `pushd` has the same rewrite. Using the same constant keeps one list.

8. **Only `\n` is a line break for the rewrite; a CR is not.** The design's table names
   "a line break outside a `cat` heredoc body, or a `\` continuation" and its ASK list
   names "a CR or NUL in the command". A `\` continuation leaves a newline behind, so the
   one test covers both. `ls\r` stays a silent prompt, asserted in `ASK_CASES`.

9. **The replay fixture is composed, not transcribed.** `self/tests/fixtures/hook-replay-2026-09-18.json`
   holds 27 records, one per shape in the design's table and one per kind of approved read.
   The 2026-09-18 replay behind the design's "5 approved, 18 prompted with no reason, 1
   denied" was recorded as **counts**: neither `self/features/minutes-slug-and-quoting/README.md`
   nor the design carries the 24 commands themselves, and no transcript this build could
   read holds them. The fixture's own `provenance` field says so, as does
   `self/tests/fixtures/README.md`. Its shape is the brief's — `{command, verdict,
   reason_contains}` — with `verdict` one of ALLOW / REWRITE / DENY / ASK, DENY being the
   three older shape denies and REWRITE a denial whose reason is the rewrite. Every path in
   it is relative to the test's throwaway root, so no record carries a machine path.

10. **It is the first data fixture under `self/tests/fixtures/`**, whose README said in so
    many words that the directory holds function libraries and never JSON blobs. That
    README now carries the exception and the reason for it: a corpus can be synthesized, a
    *command line* cannot — the commands are the fixture.

11. **The backlog entry "the opaque deny covers seven named shapes, not every structural
    refusal" is closed and removed.** This feature is the decision it was waiting for: each
    remaining structural refusal is now judged on its own — six of them denied with a
    reason naming *their own* fix (a `$NAME`, a `~`, a brace, a `..` component, a relative
    `cd`, a line break), and the rest (a redirect, an environment prefix, a CR, a NUL, a
    `..` that is not a path component) deliberately ASK, on the grounds the entry itself
    gives: a redirect hides nothing and "write the script to the scratchpad" is not its
    fix. The entry's closing assertion asked that every case in the `NOT_DENIED`-style
    lists be *unchanged*; that clause was written before the three-verdict design, which
    moves such cases by construction, so the moves are listed below instead — and the
    clause that still binds, every ALLOW and every DENY case unchanged, holds.

12. **`self/tests/hook-escalation.sh` §7b loses two cases to a new §7d.** `bash
    <scratch>/x.sh ../x` and `bash <scratch>/x.sh --out=../x` were prompts; a `..`
    component is a rewritable shape now, so both are denied with the rewrite. `§8`'s direct
    calls on `scratch_argument_allowed` are untouched and still pin that existence never
    decides a relative argument.

13. **Round 2 (rework of `escalations/01-review-opus.md`).** `ls "{src,/etc}"` moves back
    from `BRACE_REWRITE` to `BRACE_PROMPT`, and two cases join it there:
    `jq -r ".[] | {name}" data.json`, `git show "stash@{0}"`. Round 1's review found
    `brace_expansion_refused` denying any braced word that carried a quote or backslash
    ANYWHERE in it, even when the brace itself sat inside the quote and bash would never
    touch it — a literal, with nothing to expand and no rewrite to name, the same shape
    ruling 5 already carves out for `{a}` and `{a..c}`. The coordinator's ruling: a quote
    or backslash counts as "mixed in" only when the braces THEMSELVES are unquoted; a
    word whose every brace sits inside a quote is a literal and stays ASK. The new
    `brace_outside_quotes` walks the same single/double/escape state `active_var_uses`
    keeps and answers exactly that question, once, before the existing quote/backslash
    check runs. `cat {'/etc/passwd',x}` (a quote mixed into the group beside braces that
    are themselves bare) and `cat \{src,/etc/passwd\}` (bare braces, merely escaped — a
    backslash does not enclose a character in a quote the way `'…'` or `"…"` does) still
    refuse, unchanged. The companion fix, `carries_line_break` walking the same
    single/double/escape state so a `\n` inside a quoted argument
    (`git commit -m "subject\n\nbody"`) is one argument rather than a second command, is
    the same local correction escalation #1 asked for and needed no design ruling.

## Every moved case

Each was asserted as a prompt before this feature and is asserted as a **deny with the
shape's reason** now. No case moved into an ALLOW group; no ALLOW or DENY case moved at
all; every move is a shape in the design's §1 table. Group names are
`self/tests/allow-repo-commands.sh`'s.

**From `PROMPT` (the audited-bypass group) →**

| Case | To | Shape |
|---|---|---|
| `cat $HOME/.ssh/id_rsa` | `VAR_REWRITE` | `$NAME` |
| `ls ${PWD}/../` | `VAR_REWRITE` | `$NAME` (and a `..` component — the reason carries both lines) |
| `cat "$HOME/.zshrc"` | `VAR_REWRITE` | `$NAME` |
| `cat 'a'$HOME` | `VAR_REWRITE` | `$NAME` |
| `cat "'$HOME'"` | `VAR_REWRITE` | `$NAME` — and the case the quote walk had to be fixed for |
| `cat \\$HOME` | `VAR_REWRITE` | `$NAME` behind an escaped backslash |
| `ls ~` | `TILDE_REWRITE` | `~` |
| `ls ~/` | `TILDE_REWRITE` | `~` |
| `ls ~user` | `TILDE_REWRITE` | `~` |
| `cd {ROOT}/../other` | `PARENT_REWRITE` | `..` component |
| `cd .worktrees/wt` | `CHDIR_REWRITE` | relative `cd` |
| `cd` | `CHDIR_REWRITE` | bare `cd` |
| `cd -` | `CHDIR_REWRITE` | relative `cd` |
| `ls\nrm -rf /` | `LINE_BREAK_REWRITE` | a line break |
| `ls ; sh` | `MIXED_REWRITE` | a sequence mixing an approved read with one to ask about |

**From `ENTRY_PROMPT` →** `python3 ../report.py` and `../plans/gate.sh`, both to
`PARENT_REWRITE` (`..` component). Each still asserts what it asserted — an entry point
outside the tree is not approved — and now says why in its reason.

**From `BRACE_PROMPT` →** `cat {a,{/etc/passwd,b}}`, `cat {'/etc/passwd',x}`,
`cat \{src,/etc/passwd\}` and the 512-word `cat {1..8}{1..8}{1..8}` expansion, all to
`BRACE_REWRITE` (nesting, a quote or backslash mixed into an unquoted brace group, past
the cap); `cat {src,$HOME}` to `VAR_REWRITE`, the `$NAME` in it being the reason its group
refuses to expand it. `ls "{src,/etc}"` moved here too in round 1's build; round 2 moved
it back to `BRACE_PROMPT` (ruling 13) once the quote/backslash test was scoped to
unquoted braces.

**From `NOT_DENIED` (the chained-`cd` guard group) →**

| Case | To | Note |
|---|---|---|
| `cd` | `CHDIR_REWRITE` | the same case as PROMPT's |
| `x=$(cd <root>; pwd) && ls` | `MIXED_REWRITE` | an assignment nothing here can judge beside an approved `ls`. The exemption it also guarded — a whole-argument `$(…)` is not opaque — is still asserted by `x=$(cd <root> && pwd)`, `echo $(pwd)`, `AT="$(cd …)"`, `ls $(cat /etc/passwd)` and `ls \`id\``, each of which stays a prompt |
| `echo x > cd && ls` | `MIXED_REWRITE` | it guarded "a redirect target named `cd` is not a chained `cd`", and still does: the reason it now carries is the sequence rewrite, **not** `DENY_REASON`, which the group's reason assertion pins |

**From `ASSIGN_NOT_DENIED` →** `cat $HOME/f`, `ls ${PWD}/src` and `X=/p; cat $Y/f` to
`VAR_REWRITE` (the design names the first of these explicitly); `X=/p; ls src` to
`MIXED_REWRITE`. The group keeps every case that makes its own point — `X=/p`,
`R=<root>`, `X=1 make`, `FOO=1 ls`, `echo '$X'`, `grep -n '\$X' src`, `echo $(pwd)`, the
heredoc, the `#` and `AT="$(cd …)"`.

**From `OPAQUE_NOT_DENIED` →** `x=$(cd <root>; pwd) && ls` only (the same case as
`NOT_DENIED`'s, which that group also held).

**From `self/tests/hook-escalation.sh` §7b →** `bash <scratch>/x.sh ../x` and
`bash <scratch>/x.sh --out=../x`, to the new §7d (ruling 12).

Nothing moved out of `ALLOW`, `ENTRY_ALLOW`, `UNCHAINED_ALLOW`, `BRACE_ALLOW`, `DENY`,
`GIT_DENY`, `ASSIGN_DENY`, `OPAQUE_DENY`, `UNREADABLE_DENY`, `GIT_NOT_DENIED`,
`GIT_GLOBAL_OPTION_CASES`, `UNREADABLE_NOT_DENIED`, `WT_CASES` or `PAYLOAD_CASES`. The
counts after the build: ALLOW 56 cases, the audited-bypass group 126, the entry points 26,
brace lists 10, the git deny 52, the opaque deny 44 — every one of them green.

## Open

- Nothing from this feature. The one backlog entry it closes is removed (ruling 11); the
  other two are untouched.
