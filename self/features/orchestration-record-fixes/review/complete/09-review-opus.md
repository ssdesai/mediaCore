# 09 — review: orchestration-record-fixes (round 9)

Rounds 3 to 8 each patched one shell-grammar shape in the git deny's reading and each escalated
with the next. The repository owner re-scoped the work, and commit `9297a93` replaces that
approach with a fail-closed rule (`NOTES.md` → "Round 9"). Round 8's open findings were B1 (a
quoted `'<<'`, `\<\<` or a `<<<` herestring switched every git deny on the line off) and B5 (a
redirect before the command hid it from the crude reading). "No findings" is a legitimate
verdict, and a bypass you find is a finding.

## What the feature is now supposed to do

- Item 1 (unchanged): a redirection word is never read as a refspec or remote by the push
  rules; a quoted operator word is an argument; a quoted digit is no descriptor.
- **The fail-closed rule:** a line holding a git word and a `$(…)`, a backtick, `<(`/`>(`, a
  `<<` (heredoc or herestring) or the word `case` — anywhere, quoted or not — is never approved
  (`fails_closed` in `command_allowed`). The deny side has one plain reading (`command_words`:
  every operator ends a command, a quoted word is one word) and refuses what it finds; what it
  misses there prompts. Prompt rather than a rewrite deny, so `git commit -m "$(cat <<'EOF' …
  EOF)"` and `git push -u origin "$(git branch --show-current)"` keep their answers.
- **A heredoc-looking token never switches a deny off:** only an unquoted `<<` operator is a
  heredoc (`is_heredoc_operator`); the heredoc's own line is read and only its body and what
  follows are left out (`judged_tokens`).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then `git diff origin/main...HEAD
--stat`; for this round read `git diff 267a3a6..9297a93 -- hooks/allow-repo-commands.sh
hooks/README.md self/tests` closely, and drive the hook yourself
(`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>","session_id":"<fresh>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`; a fresh `session_id` per call — after two rewrite
denials in one session the policy asks the human instead). Compare with `origin/main`'s hook.

## Contracts to hold it to

- **No ALLOW** for any line holding a git word and one of the markers above, quoted or not.
  Look for a way past `fails_closed` (a git word it does not see while bash runs git, a marker
  it misses while bash substitutes) on a line `command_allowed` would otherwise approve.
- **No deny switched off** by a quoted/escaped `<<`, a `<<<`, or a real heredoc, for any command
  on the heredoc's own line. Table T's B1 rows are DENY in both profiles.
- **No regression from `origin/main`:** every line `origin/main` denies is still denied, and
  nothing `origin/main` refused is now approved. Lines round 8 denied and this round prompts
  (quoted substitutions, `case` inside them, `<(`/`>(`, `git $(true) push`) are the rule's
  decided outcome, not a finding, when `origin/main` also prompted.
- Decided, not in scope: wrappers (`env`, `command`, `exec`, `!`, `time`), brace groups,
  comments, assignment prefixes, and commands after a heredoc's body — they prompt, never an
  allow, as on `origin/main`. File one only with a payload that is approved or that `origin/main`
  denied.
- The rule's pinned costs: `git log --grep '$(x)' -1`, `git log --grep case -1` now prompt.

## Verdict
