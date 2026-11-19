Verdict: escalated

# Review — hook-audit-gaps, round 6

## What the round was supposed to do

Close round 5's audit finding B1. B1 was a destructive git command on line 1 followed by a
later line whose quote never closes and whose raw text holds `<<` or `#`. Bash runs line 1
before it hits the parse error, but the hook only prompted. The owner chose a coarse rule:
**a line that names git and does not tokenize (for the hook) is denied as a git command that
cannot be read.** A line that does not tokenize and names no git keeps its old verdict.

## Does it?

Mostly yes. The code change is one test at the return of `judged_texts`
(`hooks/allow-repo-commands.sh:1746-1748`). It asks whether `chain_tokens` lexes any reading.
A reading that `never_judged` holds back for an ANSI-C quote counts as one that lexes. If no
reading lexes and the line names git, the hook returns `unread()`, the same non-decaying git
deny that torn readings and the caps already return.

- **B1 is closed as stated.** Every reproduction and variant has a row in
  `UNLEXED_GIT_DENY`, the T table's round-6 block and `hook-escalation.sh` §10.
- **Nothing that held was broken.** The gate is green. `.claude/settings.json` did not
  change this round.
- **No assertion was weakened.** The only removed test lines are the two reason rows. Both
  moved to a stricter reason, as NOTES ruling 67 records, and both are still asserted DENY.
- **The usual message and PR body still prompt.** The heredoc body is placed, so the rule
  never sees it.
- **Gate note:** the gate's advisory "pricing rate history is current" check exited 1. It
  has nothing to do with this diff, and the gate's verdict is still "all checks passed".

## Fixed in this pass

Nothing. I tried to correct the `hooks/README.md` sentence below, but edits under `hooks/`
are not auto-accepted in this pass and the write was refused.

## Escalated to the next round

1. **The rule also denies a valid command, and `hooks/README.md` says it does not.**
   - **What happens:** a quoted substitution whose inner double quotes hold an odd quote
     is valid bash. Python's `shlex` (the lexer the hook uses) cannot lex it, so the new
     rule denies it.
   - **Evidence:** I ran the HEAD hook once on three lines:
     - `git commit -m "$(echo "it's")"`
     - `git commit -m "$(echo "it's #1")"`
     - `git commit -m "$(printf "%s" "don't")"`

     All three are the git deny ("this git command creates, switches or deletes a branch,
     … moves a ref"). That deny does not decay, and its reason is about the lifecycle, not
     the quote.
   - **What changed from round 5:**
     - The version without a `#` was the tokenize deny, which decays.
     - The version with a `#` was a prompt. `never_judged` excused it because its quotes
       never close and it holds a `#`.
     - For the `#` version, a prompt became a permanent deny on a command bash runs.
   - **What the docs say:** `hooks/README.md:573-576` ends the round-6 over-deny bullet with
     "NOT one: anything bash tokenizes". That is false for this class. NOTES' claim that "of
     the 3,964 legitimate lines … none changed" holds only because the corpus had no such
     line.
   - **What it should be:** this fits the owner's literal rule ("does not tokenize" means
     for the hook), so the behaviour may well be accepted. If it is, the fix is small and
     local:
     - **(a)** In `hooks/README.md`, name it as a fifth over-deny in that bullet, just before
       "NOT one". Suggested text: "One is NOT broken for bash: a quoted substitution whose
       inner double quotes hold an odd quote (`git commit -m "$(echo "it's")"`), which bash
       reads and shlex does not — the decaying does-not-tokenize deny before (a prompt when
       it held a `#`), this deny now; write the message as the usual heredoc." Then change
       "NOT one: anything bash tokenizes" to "NOT one: anything else bash tokenizes".
     - **(b)** Add `git commit -m "$(echo "it's #1")"` to `self/tests/allow-repo-commands.sh`
       as a DENY row with `GIT_REASON_WORDS`, so the over-deny is an asserted decision and
       not a side effect.
     - **(c)** Add a line under NOTES "Over-denies" or `self/BACKLOG.md` (the
       quoted-substitution class), noting that this class is now over-denied without decay.

     If the owner does not accept the over-deny, the alternative is a design change. The
     hook would need to recognise nested quotes inside `"$(…)"` before `chain_tokens`, which
     is the BACKLOG "substitution's scope" item, so it is not for this round.

## Not counted

- One line names git and a reading the hook builds lexes it, but bash's own reading does
  not (`(ls) # it's⏎git push …⏎cat <<EOF⏎echo '`). Recorded in NOTES "Found, not fixed
  (round 6)" and BACKLOG leftover (c).
- A broken line that has an ANSI-C quote escaping a quote is still excused, as ruling 66
  says. This is the recorded ANSI-C class, BACKLOG leftover (a).
- A line that names no git and holds a `<<` or a `#` still prompts. This is BACKLOG
  leftover (b).
