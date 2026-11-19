# 05 — review: orchestration-record-fixes (round 5)

Round 4 escalated (`escalations/04-review-opus.md`, and the security audit's
`escalations/04-audit-opus.md`). Commit `291eb20` closes both. Review it against the findings
below. "No findings" is a legitimate verdict, and a bypass you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff 51bb211..HEAD --
hooks/allow-repo-commands.sh hooks/README.md self/tests` closely, and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`).

## Contracts to hold it to

- B1: `echo $(case x in x) git push origin main;; esac)`, its backtick and `cat <(…)` forms,
  and `git reset --hard HEAD~1` in the same shape are DENY in both profiles; `git push origin
  HEAD:other` and `git switch main` in that shape are the cloud refusal (local: prompt).
- `command_words` reads each line twice (`command_words_read(…, True)` scoped and `(…, False)`
  flat, `chain_tokens(…, lift=False)`) and returns the union; the union only denies more and
  approves nothing (`command_allowed` is untouched, a `$`/backtick line is still refused).
- The outer word is whole in the flat reading: `X="$(pwd)"; cat $X/f` keeps the assign-then-use
  deny; `"./run-$(echo plans).sh" --self x` and the other five shapes in H12 of
  `self/tests/hook-orchestrator-role.sh` are build-script runs.
- `hooks/README.md` and NOTES.md → round 4 describe lifting, the `$` stand-in and the two
  readings.
- Look for a shape where one reading's output makes the other's absence matter: a command
  only the flat reading sees that is falsely denied in a way that costs a legitimate read
  (a deny on a common approved read is a regression), or a hidden command neither reading sees.

## Verdict
