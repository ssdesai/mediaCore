Verdict: escalated

# Review: orchestration-record-fixes, round 13

## What the round was supposed to do

Close round 12's audit finding B1. B1 was that a build script run from a substitution inside
a reader's arguments, such as `ls "$(./run-plans.sh --self x)"`, did not count as a run for
the build-script judge (`invokes_build_script`). That judge is the one deny a checkout with an
unreadable orchestrator ledger gives. The fix is commit `17d7019`, which adds
`substitution_may_build`: if a line holds `$(`, a backtick, `<(` or `>(`, and also a word that
names a build script or could match one, the line is a run. Whole-argument heredocs are
swapped for placeholders before this check.

## Does it do that?

Partly. Every listed contract holds:
- `substitution_may_build` only adds `True` returns ahead of the old reading, so every line
  `origin/main` refuses is still refused.
- The B1 inputs, and all eight H5 lines, are runs.
- `ls "$(pwd)"`, `git log "$(git branch --show-current)"` and a quoted-`'EOF'` commit message
  that only mentions a script are not runs.
- Nothing became an allow.

The gate is green. Its one non-zero check, "pricing rate history is current", is
non-blocking and unrelated to this diff.

The B1 *class* is still open, though. The new rule cuts its text at every `$`, paren and
backtick before it matches names. So a script name that is split by an expansion which
evaluates to nothing never reaches the matcher in one piece. The old reading catches the
same name at command position, because there the expansion becomes `*`. Inside a
substitution, nothing catches it.

## Fixed in this pass

Nothing. The plan forbids edits in this pass because the security audit has already
stamped.

## Escalated to the next round

1. **`substitution_may_build` misses a build-script name split by an empty expansion.**
   (`hooks/allow-repo-commands.sh:3558-3572`, `BUILD_SCRIPT_FAIL_CLOSED_CUT_RE` at :1044)

   I loaded the module and called `invokes_build_script` and `command_verdict` on HEAD
   directly:

   | line | `invokes_build_script` | `command_verdict` |
   |---|---|---|
   | `ls "$(./run-pla$(:)ns.sh --self x)"` | False | ask |
   | `ls "$(./run-pla$((0))ns.sh --self x)"` | False | ask |
   | ``ls "$(./run-pla``ns.sh --self x)"`` | False | ask |
   | `ls "$(./run-p$1lans.sh --self x)"` | False | rewrite |

   - Cause: the cut produces `./run-pla` and `ns.sh`. Neither names a script, and neither
     holds a glob character.
   - Impact: on an unreadable-ledger checkout, each of these lines reaches a human prompt (or
     a rewrite, then a prompt) instead of the orchestrator deny. That is exactly B1's outcome.
   - Not a regression: `origin/main` misses them too.
   - Proposed fix (a design choice, so not made here): replace the expansions with `*`
     before cutting, rather than cutting at them. That means applying
     `BUILD_SCRIPT_EXPANSION_RE`, repeatedly so nested `$(…)` collapses from the inside, to
     the text inside each substitution. Then `./run-pla*ns.sh` reaches
     `pattern_matches_build_script` whole. Keep the cut only at whitespace and operators.
     A bare `$X` that becomes `*` over-matches (`ls "$(cat $F)"`), and the docstring already
     accepts over-matching on this checkout. If that is too broad, require the `*` to be
     adjacent to other characters in the word.
   - Missing test: add these four lines to H5 in `self/tests/hook-cloud-profile.sh` as runs.

2. **An unquoted-delimiter heredoc argument is read as plain text, even though its body
   runs.** (`HEREDOC_ARGUMENT_RE`, `hooks/allow-repo-commands.sh:264-265`)

   - The `(['"]?)` group accepts `<<EOF` as well as `<<'EOF'`. So the line
     `git commit -m "$(cat <<EOF⏎$(./run-plans.sh --self x)⏎EOF⏎)"` has its body parked as
     text.
   - Result: `substitution_may_build` sees no marker. The plain reading files the name under
     an exempt `git commit` with no launcher, so `invokes_build_script` returns False and the
     outcome is ask. Bash expands `$(…)` in an unquoted heredoc body, so the script runs.
   - Not a regression: `origin/main` misses it too. It is the same class as B1, and the new
     docstring says a heredoc "that only mentions a script is no run", which is true only for
     a quoted delimiter.
   - Proposed fix: let `HEREDOC_ARGUMENT_RE` (or `keep_body`) park only quoted-delimiter
     bodies. An unquoted body stays on the line, where the fail-closed rule reads it.
   - Missing test: add this line to H5 as a run. The existing quoted-`'EOF'` row stays as
     not a run.

## Notes (no change needed)

- Expected over-match: `echo "$(cat ./*)"` is a run, because `./*` could match every
  script. The docstring accepts this, and it costs only on an unreadable checkout.
- `hooks/README.md` and `self/tests/README.md` describe H5 and the new rule accurately. After
  fix 1, the README sentence "a build-script name or a pattern that could match one" should
  add that expansions inside the substitution count as wildcards.
