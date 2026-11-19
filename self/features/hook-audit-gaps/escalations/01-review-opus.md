Verdict: escalated

# Review: hook-audit-gaps

## What the batch was supposed to do

Close the gaps the audits found in the Bash policy hook `hooks/allow-repo-commands.sh`:

- **B1**: a heredoc body ends only where bash ends it.
- **B2**: a quoted or escaped digit before a redirect is an argument.
- **B3**: the cloud own-branch push reads `branches[0]` from the manifest committed at `HEAD`.
- **Bundled `-f`**: `-fu` and similar short-flag clusters are a force push.
- **F1**: a heredoc operator glued to a separator.
- **F2**: brace words in a git command.
- **A**: a quote inside a `#` comment.
- **B**: the build-script rewrite denies no longer decay to a prompt.
- **C**: the coarse build-script rule for a checkout whose ledger can't be read.
- **Phase 3**: build scripts fed in through a redirect, the literal-branch push in the docs, and a self-audit of the neighbouring spellings.

## Does it do it

Mostly yes. Here is what I checked against the brief's contracts:

- **Tests came first.** `86807f8 hook-audit-gaps: acceptance tests` comes before the fixes.
- **No assertion was weakened.** The only rows removed from the tests moved to a stricter verdict:
  - `git branch {-a,new}` and `git worktree {add,list} x` went from prompt to DENY (F2).
  - `cd … && cat a.py # read it` went from not-approved to the chained-cd DENY. A comment is now read as a comment.
  - `cat <<EOF⏎x⏎EOF⏎git push origin main` went from prompt to DENY (F1).
- **`own_push_allowed` reads the committed manifest.** It calls `started_feature(…, tree=GIT_HEAD)`, and nothing on that path reads the manifest from the working tree any more. Q5 in `hook-cloud-profile.sh` pins this.
- **The one heredoc reader is sound.** `heredoc_body_span` now decides where every heredoc body ends. The deny readers (`judged_texts`) and the whole-argument readers (`heredoc_argument_at`, its strict form for the orchestrator) all use it. A body it cannot place is read as commands, never hidden.
- **The `-fu` check is sound.** `bundles_push_force` stops at `o`, so `-ofoo` is not read as a force.
- **The brace check is sound.** `brace_words` matches what bash does: only a `${` nests, comma groups and sequences expand, and past the cap the command is denied rather than passed on.
- **The docs agree with the code.** `CONVENTIONS.md` → "Shell commands", `ORCHESTRATION.md`, the `hooks/README.md` allowlist table and the `self/tests/README.md` rows all match. `BACKLOG.md` carries the `report.py` containment line and the classes found but not fixed.
- **The gate is green.** `.claude/settings.json` is in sync. "Pricing rate history is current" exited 1, but it is an advisory staleness check, has nothing to do with this diff, and the gate still reports all checks passed.

I judge C's over-deny (any argument naming a build-script pattern) acceptable. It applies only on the path where the ledger can't be read, where every session is already refused building.

## Fixed in this pass

Nothing. I wrote the one-line fix below, but this pass may not edit `hooks/allow-repo-commands.sh`. I reverted the test row I had added for it, so the suite is not left red. The working tree holds none of my edits.

## Escalated to the next round

1. **A brace inside `${…}` loses finding A's deny.**
   - **What happens:** `echo ${x:-{} ; git push --force origin x # '` gets no deny and goes to a prompt. Bash runs the force push. I confirmed this by feeding the hook directly, local profile. Without the trailing `# '`, the same line is denied, and so is `git push --force origin x # '` alone. This breaks rule A as the feature states it: "an unbalanced quote inside a `#` comment does not lose the git deny, in any checkout."
   - **Cause:** `comment_and_heredoc_free` (`hooks/allow-repo-commands.sh`, the `BRACE_OPEN` branch, about line 1450) increments `expansion_depth` for *any* `{` once inside `${…}`. Bash nests only on `${`; on bash 5.2.21, `echo ${x:-{} }` prints `{ }` and `echo ${x:-{a}}` prints `{a}`. So the walk never leaves the expansion, never sees the `#` as a comment, and opens a quote on the `'`. The text then can't be tokenized, and the line falls into the does-not-tokenize path.
   - **Fix:** change the condition to
     ```python
     elif ch == BRACE_OPEN and command[index - 1:index] == SUBSTITUTION_PREFIX and not after_literal:
     ```
     That drops the `expansion_depth or`. Add to `GIT_AUDIT_DENY` in `self/tests/allow-repo-commands.sh`:
     - `"echo ${x:-{} ; git push --force origin x # '"`
     - `"echo ${x:-${y:-{}}} ; git stash # it's"`

     The second row shows a nested `${` still nests. Add the same rows to the T table in `self/tests/hook-cloud-profile.sh`.
   - **Severity:** a prompt, not a silent approval. But it bypasses a rule this feature states, in code this feature added.

## Minor notes (not escalated)

- **Stale docstring.** The `own_push_allowed` docstring (about line 3766) still says "a tracked manifest's `branches[0]`". It should say "committed at `HEAD`", as the comment eight lines below it does. Fix it alongside item 1.
- **Unnamed literals.** `comment_and_heredoc_free` uses a bare `"<"` twice in the heredoc-operator test (`HEREDOC_OPERATOR + "<"`, `!= "<"`). Under the named-constants rule these want a named constant, such as a herestring operator.
- **Possible over-deny.** `brace_words` expands quoted words as well, by design ("more words, never fewer"). So a quoted brace sequence past `MAX_BRACE_WORDS` in an ordinary git argument is denied as unreadable, for example `git commit -m "ids {1..1000}"`. The usual heredoc commit message is not affected, because its body is replaced before this point. Worth a line in `hooks/README.md`'s over-deny list if the next round touches it.
