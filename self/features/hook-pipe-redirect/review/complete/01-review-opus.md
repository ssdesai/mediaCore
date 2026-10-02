# 01 — review: hook-pipe-redirect

## What the feature was supposed to do

Close two `self/BACKLOG.md` entries:

1. **A pipe into an interpreter followed by a redirect is not read as one.**
   `cat <<'EOF' | python3 > out` (with a heredoc body) and `ls | sh > out` are now denied
   with `OPAQUE_DENY_REASON`, exactly like the same lines without the redirect. The fix
   reuses the redirect-stripping that `redirect_members` already does rather than adding a
   second reader, and `python3 < script.py` keeps whatever reading it had.
2. **`git stash list` is denied with the rest of `git stash`.** `git stash list` is
   approved as a read-only git; every mutating form (`push`, `pop`, `apply`, `drop`,
   `clear`, `branch`, `save`, bare `git stash`) stays denied. `git stash show` is a stated
   decision either way in NOTES.md.

`CONVENTIONS.md` "Shell commands" reflects both in a few words, since that file ships to
every consumer.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Read
`self/features/hook-pipe-redirect/NOTES.md` for the implementer's rulings, but judge
against this brief, not against the notes.

## Contracts to hold it to

- The hook test suite has positive and negative cases for every line named above, and
  `pytest > out.log` (a captured output, handed to the human) is unchanged.
- If the `git stash` deny lives in `hooks/wire-settings.py`'s generated settings rather
  than hook code, the allow for `git stash list` is placed where a deny rule cannot beat
  it, and the `wire-settings.py` test covers the change.
- No other shape's verdict changes: run the whole hook suite and read the diff of any
  fixture expectations that moved.
- `CONVENTIONS.md`'s change is minimal and in the file's voice; `hooks/README.md`
  describes any changed function.
- The gate is green; READMEs of every touched folder are current.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
