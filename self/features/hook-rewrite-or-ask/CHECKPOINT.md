# Checkpoint: hook-rewrite-or-ask

status: committed        planned | tests-written | implementing | gating | committed
updated: 2026-09-21T15:27:34Z
gate: round 2: all checks passed, level final, no SKIPPED (self/gate-report.txt)

## Round 2 (rework of escalations/01-review-opus.md, brief review/incomplete/02-review-sonnet.md)
- [x] tests — self/tests/allow-repo-commands.sh: two new ASK_CASES (a real newline inside
      a double-quoted argument), two new BRACE_PROMPT cases (a brace inside double
      quotes), `ls "{src,/etc}"` moved back from BRACE_REWRITE to BRACE_PROMPT — 5 FAIL
      confirmed red (committed first, 5ee1daa)
- [x] fix — `carries_line_break` walks the same single/double/escape state
      `active_var_uses` keeps and only fires on a `\n` outside both quotes; a new
      `brace_outside_quotes` helper makes `brace_expansion_refused` only refuse when the
      braces themselves are unquoted
- [x] docs — CONVENTIONS.md and hooks/README.md's two table rows, the design file's §1
      table + a note that round 1 corrected it, NOTES.md ruling 13 for the moved case
- [x] gate green, commit

## Done
Neither `command_allowed` nor anything it calls is in this diff; no test case moved into
an ALLOW group; every existing ALLOW/DENY case still passes (self/gate.sh, final level).
`self/tests/hook-escalation.sh`'s `NEW_SHAPES` list touches neither reworked shape, so it
is unchanged and still green. `self/tests/fixtures/hook-replay-2026-09-18.json` has no
record with a quoted brace or a quoted line break, so it is unchanged.

## Learned
- The three older shape denies (`chains_chdir`, `mutates_git_refs`,
  `uses_own_assignment`) run in `main()` before `command_verdict`, so a quoted newline
  inside an assignment-deny case (e.g. `R={ROOT}\nls $R/src`) is unaffected by the
  `carries_line_break` fix — it is denied earlier for a different reason.
- Neither fixture record needs a verdict change: no record in
  `hook-replay-2026-09-18.json` has a quoted brace or a quoted line break.
- `self/tests/hook-escalation.sh`'s `NEW_SHAPES` list touches none of the two shapes
  being reworked, so it needs no edit; confirmed by reading it.

## Resume
- Round 1's committed tree is `hook-rewrite-or-ask: review round 1` (15eca93). Read
  `escalations/01-review-opus.md` and `review/incomplete/02-review-sonnet.md`, then the
  `ASK_CASES`/`BRACE_REWRITE`/`BRACE_PROMPT` groups in
  `self/tests/allow-repo-commands.sh`, then the fix in `hooks/allow-repo-commands.sh`.
