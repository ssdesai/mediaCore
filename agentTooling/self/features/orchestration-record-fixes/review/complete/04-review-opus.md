# 04 — review: orchestration-record-fixes (round 4)

Round 3 escalated (`escalations/03-review-opus.md`). Commit `849c102` closes its findings;
`51bb211` then merges `origin/main` (#140, the orchestrator allowlist) into the branch, with one
textual conflict in `ORCHESTRATION.md` (both sides kept). Review `849c102` against the findings
below and the merge for combined behaviour. "No findings" is a legitimate verdict, and a bypass
you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved. A report's
`report` path is read from the consuming repo's root (item 2).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff 6110b3b..849c102 --
hooks/allow-repo-commands.sh self/tests/hook-cloud-profile.sh` closely, and drive the hook
yourself (`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`).

## Contracts to hold it to

- A `$(…)` or backtick pair inside double quotes is lifted out and read as commands:
  `echo "$(git push origin HEAD:main)"`, `` echo "`git push origin HEAD:main`" `` are DENY;
  `echo '$(git push origin main)'` (single quotes) and `grep -n "("` are not substitutions.
- `git $(true) push origin HEAD:main` is DENY (`git_subcommand_args` skips the `$` stand-in on
  the deny side only); `git $(echo reset --hard) status` stays a prompt, never an allow.
- `punctuation_pieces` cannot spin on a `CHAIN_PUNCTUATION` character with no operator (the
  `for … else` fallback); H1/H2 in `self/tests/hook-cloud-profile.sh` assert full operator
  coverage.
- Every payload is a row in table T; `hooks/README.md` and NOTES.md → round 3 describe it.
- The merge: the orchestrator allowlist's `git push -u origin <branch>` shape runs through
  these push rules; nothing in `ORCHESTRATOR_*` / `orchestrator_words` reads a redirect,
  quoted operator word or substitution as an argument or command.
- Look for what the earlier rounds did not: a shape where masking, the piece walk or the
  stand-in hides a word or a command from a git rule, or turns a denial into an allow.

## Verdict
