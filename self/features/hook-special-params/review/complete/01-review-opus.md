# 01 — review: hook-special-params

Read the diff against `main` and judge it against the spec below. "No findings" is a
legitimate verdict: this is a two-line regex change with a test row and two doc rows,
and a review that must produce findings will produce speculative ones. Phrase every
finding as an assertion — a missing test case is the highest-value output — and sort
them into the two lists at the end.

## What the feature was supposed to do

`CONVENTIONS.md` → "What is sent back with a rewrite" says a `$NAME` the shell will
expand is denied with the "inline the literal" reason. `VAR_USE_RE` in
`hooks/allow-repo-commands.sh` matched only `[A-Za-z_][A-Za-z0-9_]*`, so a command
carrying a special or positional parameter — `$?`, `$$`, `$!`, `$*`, `$@`, `$-`, `$0`…`$9`,
`${10}` — fell through the rewrite layer and reached the human as a silent prompt. A
consuming-repo session reported this about itself.

The fix widens `VAR_USE_RE` to those parameters and nothing else. The suite gains one
`VAR_REWRITE` row per spelling. The `$NAME` row in `CONVENTIONS.md` and `hooks/README.md`
says the parameters are included.

Three existing test cases used `AT="$(cd "$(dirname "$0")/.." && pwd)"` to pin *other*
shapes (a `cd` inside a substitution is not a chained cd; an assignment nobody
dereferences is not the own-assignment deny; a whole-argument `$(…)` is exempt from the
opaque deny) and expected "prompt". They passed only because `$0` fell through the regex
— the `$HOME` twin of the same command was already denied. Those three now use a literal
path in place of `"$0"`, and the `$0` spelling is added to `VAR_REWRITE`. The exemptions
they pinned must still be pinned.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- **`hooks/README.md` → "The three outcomes".** A REWRITE narrows ASK and never touches
  ALLOW. `VAR_USE_RE` is consumed only by `active_var_uses`, which feeds
  `expands_a_variable` (the rewrite layer, reached only after the approval analysis has
  declined) and `uses_own_assignment` (whose names come from `ASSIGNMENT_RE`, still
  letters-and-underscores only, so no special parameter can ever equal an assigned name).
  Confirm from the code that no command approved before this diff is approved differently
  after it, and that the own-assignment deny is unchanged.
- **Quote-awareness is untouched.** `active_var_uses`'s single-quote, double-quote and
  backslash walk is not in the diff. `'$?'`, `"\$$"` and `\$1` must still be literal;
  `"$@"` must still be a use.
- **`$(…)`, `$'…'` and `$"…"` still match nothing.** The pattern's new alternatives are
  `[0-9]+` and `[?$!#*@-]`; `(`, `'` and `"` are in neither.
- **`#` never reaches the rewrite layer** (`rewrite_reason_lines` returns `[]` when
  `COMMENT_CHAR` is on the line), so `$#` and `${#X}` in the character class are
  unreachable there by design. This is noted in the manifest's exclusions; it is not a
  finding unless the guard itself changed.
- **The three moved test cases.** Each still asserts the shape its list is for:
  `OPAQUE_NOT_DENIED` (whole-argument `$(…)` exempt), `NOT_DENIED` (cd inside a
  substitution), `ASSIGN_NOT_DENIED` (assignment with no own use). A literal path in
  place of `"$0"` must not have turned any of them into a different rewrite (`..` is
  inside the substitution, which `parent_path_component` does not read — verify from the
  code, not by running the suite).
- **The doc rows.** `CONVENTIONS.md` line 55 and `hooks/README.md`'s copy of the table say
  the same thing; the hook's own comment above `VAR_USE_RE` lists the same parameters.
- **README accuracy.** `hooks/README.md` → "Editing the policy" names `VAR_USE_RE`; no
  constant was added or renamed, so nothing else there should have needed a change.

## Verdict

Say what the feature was supposed to do and whether the diff does it, then two lists:
**fixed here** (local defects you corrected in this pass, each with the file and what
changed) and **escalated** (structural findings for the next round, each as an
assertion). A clean verdict means the escalated list is empty.
