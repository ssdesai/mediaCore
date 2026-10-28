# Notes: shell-write-rewrite

Direct build (`AGENT_DIRECT.md`). Rulings in the order they were made, one line of
rationale each; the spec is `README.md` in this directory.

## Rulings

1. **The shape has its own reader, `redirect_members`, not `opaque_segments`.** The
   latter breaks at every `&` and `|`, so `2>&1`, `&> f` and `>| f` come apart there, and
   shlex drops quotes so a quoted `>` would read as an operator. The new reader keeps the
   same quote/backslash/backtick/`$(…)` tracking and reads redirect operators as bash does.
   `opaque_segments` itself is untouched, so no existing shape moves.
2. **The heredoc cut is the reader's `stop_at_line_break`, not a call to
   `segments_before_line_break`.** Same cut (the first line break outside every quote and
   substitution), but taken during the walk: scanning on into a body with an apostrophe
   (`don't`) would leave the reader in an open quote, and a line whose quotes are open at
   the end is judged by nothing here. Documented against `segments_before_line_break` in
   the docstring and in `hooks/README.md`.
3. **Judged as a sibling of `rewrite_reason_lines` (`authoring_reason_lines`), called in
   `command_verdict` after `command_allowed` and before `opaque_deny_reason`.** ALLOW is
   decided first and unchanged; the three shape denies in `main()` still run before
   `command_verdict` at all.
4. **When the shape fires, its lines are the whole reason.** Other rewrite lines on the
   same line (a `$NAME`, a mixed sequence) are not appended: the mixed-sequence reason
   would tell the model to run the authoring member alone, which contradicts "use the
   Write tool". The model sends what is left and gets that judged next.
5. **Only the member that authors is named** (`MEMBER_QUOTE`, from the member's own text
   slice — for a heredoc, its first line, e.g. `` `cat >> tests/test_x.py <<'EOF'` ``).
6. **`sed -i` scan stops at the first non-letter** as well as at a value-taking letter
   (`e`, `f`, `l`). Without it `sed -{n,i} 5p f` fired, which `BRACE_PROMPT` pins as a
   prompt for the brace rules' sake; `-i.bak` still fires since the `i` comes first.
7. **`>&word` is a file when `word` is not a descriptor number or `-`** — bash reads
   `>&f` as `&>f`. `>&2`, `2>&1`, `>&-` are fd duplications and not targets.
8. **A write inside `$(…)`, backticks or a `(…)` subshell is not judged** (one opaque
   word, as everywhere in this file). Conservative: stays ASK, never a false deny.
9. **`tee` operands exclude flags and the non-file targets and process substitutions**;
   `tee` with only a redirect to `/dev/null` and a file operand still fires on the operand.
10. **`X=1 echo x > f` fires** — `program_words` drops the environment prefix, as for the
    opaque shapes.
11. **Part 2's predicate needs a manifest reader, and routing.py cannot import any of the
    existing ones** (`report`, `capture_planning` and `manifest` all import routing). So
    `parse_manifest` moved from `report.py` into `routing.py` and `report.py` imports it —
    the number of copies did not grow. `capture_planning.py`'s identical copy is left (a
    test monkeypatches it); backlog entry filed.
12. **`split_pinned(records, features_dir)` is the one predicate** — returns
    `(kept, [(record, pinning slugs)])`; the table, its fraction (same function) and the
    "routed by" line call it. `pinned_sessions` reads every `<slug>/README.md` in the
    corpus, tolerating a broken manifest silently (as `read_record` does).
13. **The `--all` skip line is printed after the table** (or after the empty note when
    every record was skipped), one per skipped record, naming the pinning slugs.
14. **`feature-start.sh --pin` prints `routing   none (--pin: …)`** instead of writing,
    whether or not a session id was found.

## Deviations from the brief / spec

- **`self/tests/hook-escalation.sh` was touched**, though the brief expected not: its
  `ASK_RESETTER` was `echo x > f`, which is a REWRITE now. It is `cat README.md > f` (a
  captured output, still ASK), and §9h–9i assert the new shape escalates through the same
  counter (review contract 7).
- **One acceptance case was corrected after the acceptance commit**:
  `cat <<'EOF' | python3 > f` was expected to be the opaque deny, but it is ASK on `main`
  too (a pre-existing gap in `piped_into_interpreter`, now in `self/BACKLOG.md`) and this
  shape does not fire on it. Replaced by `python3 <<'EOF' >> out.txt`, a heredoc into an
  interpreter with an output file, which is the opaque deny.

## Moved test cases (self/tests/allow-repo-commands.sh)

- `PROMPT` → `AUTHORING_REWRITE`: `sed -i.bak 's/a/b/' README.md`, `sed -ni 5p README.md`,
  `sed -i '' 's/a/b/' README.md`, `echo hi > f`, `printf x > f`, `cat > x <<'EOF'`.
- `OPAQUE_NOT_DENIED` → `AUTHORING_REWRITE`: `cat > x <<'EOF'\nhello\nEOF`.
- `ASK_CASES` → `AUTHORING_REWRITE`: `echo x > f` (replaced in ASK by `cat README.md > f`).
- `MIXED_REWRITE` → `AUTHORING_REWRITE`: `echo x > cd && ls`; its point (a redirect
  target named `cd` is not a chained cd) is kept in MIXED by `cat README.md > cd && ls`.
- Replay fixture `hook-replay-2026-09-18.json`: the `echo x > f` record moved from ASK to
  REWRITE with `reason_contains: "Write tool"`; the record count is unchanged.

## Open questions

- BSD `sed -I` (in place, capital) is not in the spec's spelling list and is not caught.
