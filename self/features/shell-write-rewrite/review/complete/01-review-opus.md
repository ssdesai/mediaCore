# 01 — review: shell-write-rewrite

## What the feature was supposed to do

Two small changes: part 1 below, and part 2 under "Contracts". Part 1 adds one REWRITE shape to `hooks/allow-repo-commands.sh`: **a file authored through the
shell**. When content written in the command lands in a file, the command is denied with
a reason that names the member as written and says to use the Write tool (new file or
whole rewrite) or the Edit tool (a change, including an append). Before this feature,
such a command returned ASK and printed nothing. The spec is the prose of
`self/features/shell-write-rewrite/README.md`: the three spellings (`echo`/`printf`
redirected to a path; `cat`/`tee` fed literally, meaning a heredoc, a herestring, or for
`tee` a pipe from `echo`/`printf`/heredoc-fed `cat`, with output to a path; `sed -i` /
`--in-place`), the non-file targets, where the shape is judged, and the "Not this shape"
list. Hold the diff to that prose, not to the builder's `NOTES.md`.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`hooks/allow-repo-commands.sh`, `self/tests/allow-repo-commands.sh` (and the replay
fixture if a record's verdict moved), `hooks/README.md`, `CONVENTIONS.md`, and the
feature directory.

## Contracts to hold it to

1. **ALLOW is untouched.** `command_verdict` returns ALLOW from `command_allowed` alone,
   before the new check runs. No command approved on `main` may be denied, and none may
   become approved. Look for a new call path that reaches the shape check before the
   `command_allowed` branch, or that changes what `command_allowed` sees.
2. **Only ASK becomes REWRITE.** Every case the shape fires on must be one that printed
   nothing on `main`. Check the ordering in `command_verdict` against the three shape
   denies in `main()` (chained `cd`, git, own-assignment). Those still run first.
3. **Heredoc bodies are data.** On a line carrying `<<`, only the text before the first
   line break is judged. A body containing `> x`, `echo a > f`, `sed -i` or `tee f` must
   not fire. Neither may a `#` on the judged text.
4. **Quotes hide the operator.** A `>` inside single or double quotes is not a redirect.
   An fd duplication (`2>&1`, `>&2`), `>(…)`, and the targets `/dev/null`,
   `/dev/stdout`, `/dev/stderr` and `/dev/tty` are not file targets.
5. **The exclusions stay what they were:** captured output (`pytest > out.log`,
   `git diff > p.patch`, `cmd | tee log`, `cat a > b`), `git commit -m "$(cat <<'EOF' …
   EOF)"`, `sed -n …p`, and `cp`/`mv`/`touch`/`mkdir`/`rm`. Each needs a test in a
   not-denied list, not just an absence of a deny case.
6. **Precedence over the opaque shapes.** `tee f <<'EOF' … EOF` gets the Write/Edit
   reason, not `OPAQUE_DENY_REASON`. A heredoc into an interpreter (`python3 - <<EOF >
   f`) is still the opaque deny.
7. **It is a REWRITE for the escalation.** It counts toward `OPAQUE_REWRITE_ATTEMPTS`
   through the same path as the other shapes, not a parallel one.
8. **Conventions of this directory.** Every magic value is a named constant at the top
   of the hook beside its siblings (`CONVENTIONS.md` → "Named constants"). The shape is
   a row in `rewrite_reason_lines`'s table or a sibling of it, not a special case bolted
   into `main()`. `hooks/README.md` has the row in "The rewritable shapes", the new
   constants in "Editing the policy", and the entry at the top of the file lists the
   shape. `CONVENTIONS.md`'s rewrite table has the row, and its "What reaches the human"
   and "Writing files" text no longer says a shell-authored file reaches the human.
9. **Tests are black-box through the hook**, the way the rest of
   `self/tests/allow-repo-commands.sh` is: a DENY list, a reason-words check, a
   member-as-written check, and a not-denied list covering contract 5. `./self/gate.sh`
   is green.

### Part 2: a pinned session is never also a router

The manifest's "Part 2" section is the spec. Hold the diff to these:

10. **`feature-start.sh --pin` writes no `routing.json`** and still pins the session.
    Without `--pin`, the record is written exactly as on `main`. The `S: start` commit
    carries whichever one applies. Look for a test through the script (or the part of it
    the existing feature-start tests drive) for both spellings.
11. **One predicate, in `analysis/routing.py`.** A routing record whose `session_id` any
    manifest in the corpus pins in `sessions` is skipped by the Routing table, by its
    fraction line, and by `report.py <slug>`'s `routed by` line. All three call the same
    routing.py function. None of them re-reads manifests on its own.
12. **The skip is visible.** `--all` names each skipped record in one line. The record
    files are not modified or deleted by any reader.
13. **Nothing else moves.** Feature totals, `report.json`, the capture's
    `--refresh-for`, and a router pinned by no manifest are all unchanged. A test puts
    one pinned and one unpinned router in a fixture corpus and asserts the table total
    counts only the unpinned one.
14. **Docs.** `analysis/README.md` (the `routing.py` and `report.py` entries), and
    `LIFECYCLE.md` step 2 and `feature-start.sh`'s header comment, stop saying the
    record is written "always".

The highest-value finding is a missing assertion. If a contract above has no test
that would fail when it breaks, name the case and which list it belongs in.

## Verdict

"No findings" is a legitimate verdict, so don't invent one. Fix local defects in place.
Escalate only what needs a design change. Report two separate lists: fixed here, and
escalated. `Verdict: clean` means the escalated list is empty.
