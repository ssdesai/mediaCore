Verdict: escalated

# Review — hook-hash-chained-cd

## What the batch was supposed to do

Fix the reported approval of `cd <root>; grep -n '^#' TEST_SPEC.md | head -300; wc -l TEST_SPEC.md`:

1. Make the `#` guard quote-aware with one helper, `unquoted_comment_char`. Every deny or
   rewrite reader that used to test `COMMENT_CHAR in …` now calls it.
2. Stop the approval analysis approving a chained `cd`. Now `command_allowed` approves a `cd` only as
   the whole command, and no cwd is threaded between members.

## Does it do it

Mostly, yes. The gate is green, including the allow-repo-commands self-test. Checked against the plan's contracts:

- **The reported line is denied.** I probed the hook directly and the reported line returns `deny`. The new
  `DENY` rows cover the double-quoted and backslash-escaped forms.
- **No widening.** `subcommand_allowed` and `expansion_allowed` still take the same
  `cwd` they always had, because a non-`cd` member never changed it. Removing the
  threading only matters when a member is a `cd`, and those chains are now refused by the
  `len(groups) > 1` guard in `command_allowed`. Every change narrows. A path-spelled
  `cd`, such as `/usr/bin/cd /r && ls`, never matches `CHDIR_PROGRAMS`, but it also never
  passes `subcommand_allowed`, so it was never approved.
- **`ls # && cd <root>`** is tokenized by `command_allowed` with no commenters, so it becomes two groups,
  one of them a `cd`, and the line prompts. The `CHAINED_NOT_APPROVED` rows cover this.
- **`member_allowed`'s assumption** that no member of a sequence moves the directory is now true by construction.
- **Edge cases the plan named.** `\#` inside double quotes, `'…'"#"` and a `#` inside
  `$(…)` all behave correctly. The first two are read as quoted. The third counts as
  unquoted, which is the safe direction: the line is left unjudged.
- **Rewrite rows newly reachable on a quoted `#`.** None misfires. `grep '#' $F` still
  gets the `$NAME` rewrite, and `echo '#' > f` still gets the authoring rewrite. Both
  verdicts are correct, because the `#` is literal there.
- **`hooks/README.md`** agrees with the code.

One contract does not hold: **"no new deny on a guess"** fails for ANSI-C quoting. Details below.

## Fixed in this pass

Nothing. I tried to make the one-function fix below. The edit to
`hooks/allow-repo-commands.sh` was refused because that path is not auto-accepted for
this pass.

## Escalated to the next round

### 1. `unquoted_comment_char` misreads `$'…'`, so a real comment is denied

- **File:** `hooks/allow-repo-commands.sh`, `unquoted_comment_char` (just above `chains_chdir`).
- **Failing command:** `ls $'\'' # '; cd src`
  - Bash reads `$'\''` as one `'` character, so it runs `ls "'"`, and `# '; cd src` is a comment.
  - **Expected:** no decision (prompt), which is `main`'s behaviour, since `main` skipped any line containing a `#`.
  - **Actual:** `deny`, with the chained-cd reason. I confirmed this by feeding the hook directly.
    `echo $'\'' # x' && cd src` is denied in the same way.
- **Cause:** the scanner treats `$'…'` as a plain single-quoted string, where a backslash is
  literal. So it sees `'\'` close and then `' # '` open again, and it places the `#`
  inside quotes. `shlex` makes the same mistake, so the chain reader then finds
  `; cd src`. Before this batch, the raw `COMMENT_CHAR in command` test hid this. The
  quote-aware guard brings it out. The same misreading reaches every caller of the guard:
  `command_words`, `does_not_tokenize`, `rewrite_reason_lines` and `authoring_reason_lines`.
- **Fix:** track ANSI-C quoting in the scanner.
  - Add a constant `ANSI_C_QUOTE_PREFIX = "$"` next to `QUOTE_SINGLE`.
  - When a `'` follows an unquoted, unescaped `$`, enter an `in_ansi` state. In that
    state a backslash escapes the next character and only an unescaped `'` closes it.
  - Count `in_ansi` in the unclosed-quote return.
  - The line then counts as having an unquoted `#` and goes back to being unjudged.
  - This keeps the signature and needs no new function.
- **Missing test:** add `ls $'\\'' # '; cd src` to `NOT_DENIED` in
  `self/tests/allow-repo-commands.sh` (Python string: `"ls $'\\\\'' # '; cd src"`). Also
  add a `DENY` row where the `#` really is inside ANSI-C quotes, such as
  `cd <root> && grep $'#' f`, so the fix cannot overcorrect.

This only happens with contrived input. The cost is a wrong rewrite message, not a widened
approval. It is still a regression from `main`, and it breaks a contract the plan states explicitly.

### 2. Missing assertion (cheap; same test file)

This is correct today, but no test asserts it: `cd <root> && grep -n '^'"#" README.md`
should be a `DENY` row, because a single-quoted run joined to a double-quoted `#` is
still a literal.
