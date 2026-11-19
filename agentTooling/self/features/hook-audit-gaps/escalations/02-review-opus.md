Verdict: escalated

# hook-audit-gaps — round 2 review

## What the round was supposed to do

Fix round 1's four escalations in `hooks/allow-repo-commands.sh` (review item 1: a bare `{`
inside `${…}`; audit E1: a `$(…)` heredoc run-on line such as `EOF )` hid a command; E2: a
comment ending in `\` hid the next line from the build-script judge; E3: a `#` right after
`)` was taken for a comment). All four were to follow coordinator ruling 7: where the hook
would hide text from the deny side and bash could read it differently, judge both readings
and deny if either one denies. The round also covered the replace-ref hardening, the `$$'…'`
PID quote, and round 1's minor notes.

## Does it do it

Yes, for everything it set out to fix. I read the round's commit (`4ed1ff6`) against the
brief:

- **Item 1.** Only a `${` nests now (`after_dollars % 2 == 1`), so `${x:-{}` ends at its
  first `}`. Rows are pinned in `GIT_AUDIT_DENY`.
- **E1.** `heredoc_body_span` no longer asks what follows the delimiter. A run-on line is read
  three ways: left unplaced, as body text, and as the end of the body. Each run-on line is
  tried as the end in turn (`skip`/`ended`, capped). A backtick line gets its own reading.
  The strict orchestrator reader refuses such a body. The audit's six spellings are pinned in
  `allow-repo-commands.sh` and in `hook-orchestrator-role.sh` H26. H21's `EOF ⏎` row moved
  from admitted to denied (a stricter verdict), and NOTES.md ruling 37 records the move.
- **E2.** The build-script judge reads each line twice: with continuations deleted and as
  written. The walk itself deletes `\⏎` outside single and ANSI-C quotes, and never inside a
  comment. I probed the mixed case `ls # x \⏎./run-pla\⏎ns.sh` and it holds.
- **E3.** A `#` counts as a certain comment only when the kept text before it holds none of
  `([{` or a backtick. Otherwise every combination of the doubtful comments is judged, up to
  `MAX_COMMENT_DOUBTS`. Past that cap, a line naming git is denied as unreadable.
- **Replace refs.** `own_push_allowed` sets `GIT_NO_REPLACE_OBJECTS=1` before its HEAD
  probes, and Q6 in `hook-cloud-profile.sh` proves a live replace ref approves nothing.
- **The moved audit row.** `echo a \⏎#b ; git push -f origin y` moved from deny to prompt.
  That is correct: bash deletes the continuation, starts a comment, and runs no push.
- **Docs and constants.** Every new literal is a named constant: `COMMENT_DOUBT_OPENERS`,
  `MAX_COMMENT_DOUBTS`, `MAX_RUN_ON_LINES`, `HEREDOC_RUN_ON_BACKTICK`, `PID_PARAMETER`,
  `HERESTRING_OPERATOR` and `GIT_NO_REPLACE_ENV`/`_ON`. `hooks/README.md` lists them, no
  longer calls `EOF `/`EOFS` plain body lines without qualification, and has a "What the
  both-readings rule over-denies" section that matches the code. `self/tests/README.md` is
  current. I found nothing in `CONVENTIONS.md` → "Shell commands" that contradicts the new
  behaviour.
- **Gate.** The verdict is "all checks passed". One step, "pricing rate history is current",
  exits 1, but it is not counted in the verdict and has nothing to do with this diff. No
  check is listed as SKIPPED.

## Fixed in this pass

Nothing.

## Escalated to the next round

### 1. A delimiter joined by `\⏎` in an unquoted heredoc body hides a command from the git deny

This hides text the way ruling 7 forbids, in the construct this feature reworked
(`heredoc_body_span`, plus the round's new continuation deletion).

With an **unquoted** delimiter, bash deletes backslash-newline while it reads the body, and
only then checks for the delimiter. So the body below ends at the joined line `EO\⏎F`, and
the next line runs as a command:

```
cat <<EOF
EO\
F
git push --force origin y
EOF
```

`heredoc_body_span` compares each raw line against the delimiter. It does not see `EO\`/`F`
as the terminator, so it places the body all the way to the final `EOF`.
`judged_texts(...)` returns `['cat <<EOF\n']`, the push is hidden, and the hook emits
nothing, which means a prompt.

I confirmed this in the scratch directory with bash 5.2 and a logging `git` stub. Bash ran
`git push --force origin y` in all three spellings:

- the plain one above;
- `cat <<EOF⏎x⏎EO\⏎F⏎git push …⏎EOF`;
- inside `echo "$(cat <<EOF⏎EO\⏎F⏎git push …⏎EOF⏎)"`.

The hook gave a prompt for all three, not a deny. With a quoted delimiter (`<<'EOF'`) bash
does not join lines and runs no push, so the hook is right there.

Scope of the damage:

- **Not a silent approval.** All three are prompts.
- **Not a regression.** `origin/main` and round 1 (`9ba1162`) also give a prompt.
- **The orchestrator allowlist is unaffected.** Its strict reader requires a quoted
  delimiter.
- **The build-script judge already holds.** `invokes_build_script` returns True for the same
  shape with `./run-plans.sh`.

What is missing is the git deny (and the other `judged_texts` denies) on a line where bash
runs the push. That breaks ruling 7, which says text is hidden only where the reading is
certain. It also contradicts `hooks/README.md`, which says "Bash ends a heredoc at the first
line holding the delimiter and nothing else" and "A line continuation is deleted where bash
deletes it".

What it should be:

- **The fix.** `heredoc_body_span` (`hooks/allow-repo-commands.sh`, around line 1218) needs
  to know whether the delimiter was quoted. It has callers in `comment_and_heredoc_free`
  (from `heredoc_delimiter`) and in `heredoc_argument_at` (`head.group(2)`), so this is a
  signature change and not a local fix. With an unquoted delimiter, either:
  - join `\⏎` before comparing lines, or
  - per ruling 7, leave unplaced any body that holds a line ending in an unescaped `\`, so
    the deny side reads it as commands.
- **The tests.** Add the three lines above to `GIT_AUDIT_DENY` in
  `self/tests/allow-repo-commands.sh`. Add the quoted-delimiter twin
  (`cat <<'EOF'⏎EO\⏎F⏎git push …⏎EOF`, where bash runs no push) as a prompt row, so the fix
  does not over-reach without anyone noticing.
- **The docs.** Update the "Where a heredoc's body ends" paragraph in `hooks/README.md`, and
  the matching sentence in `CONVENTIONS.md` → "Shell commands" ("The heredoc's body ends
  only at a line holding the delimiter alone, as in bash"), to name the joined line.
