# 03 — review: orchestration-record-fixes (round 3)

Rounds 1 and 2 were `clean`. An independent audit of #139 (head bf464c49) then returned
`Verdict: findings`: the README's policy — a push of `main` or elsewhere stays refused with or
without redirections — did not hold for five older families, plus one regression from round
1's own fix. Commit `6110b3b` closes them. Review that commit against the findings below;
"no findings" is a legitimate verdict, and a bypass you find is a finding.

## What the feature was supposed to do

The hook's reading of a command never lets a redirection, a quoted operator word or a
substitution hide a refspec, the remote or the git command from the push rules. Pushes to
`main` stay DENY in both profiles with any of them present; a push elsewhere gets the refusal
of its plain form; a grep pattern like `'\('` is no operator and stays approved.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`; for this round read `git diff a48717b..HEAD --
hooks/allow-repo-commands.sh self/tests/hook-cloud-profile.sh` closely, and drive the hook
yourself (`echo '{"tool_name":"Bash","tool_input":{"command":CMD},"cwd":"<repo>"}' |
CLAUDE_PROJECT_DIR=<repo> python3 hooks/allow-repo-commands.sh`, with
`AGENTTOOLING_PROFILE=cloud` and `local`).

## Contracts to hold it to

- F1: `git push > ';' origin HEAD:main`, `2>';'`, `-o ';'`, `-o '>'`, `-o \;`,
  `2> '&&' origin HEAD:other` — a quoted or escaped operator word is a word
  (`mask_quoted_punctuation`, `QuotedWord`, `is_operator_token`).
- F2: `true;>x git push …`, `ls|>x …`, `ls;>x …`, `ls&&>x …` — `punctuation_pieces` reads a
  run left to right, longest operator first; only a redirect sets `redirect_target`.
- F3: `-o >(cat)`, `> >(cat)`, `-c a.b=>(cat) push`, `--repo=<(cat)` — `command_words` scopes
  `<(`/`>(`/`$(` with the outer command's words kept; `git_subcommand_args` skips the stand-in.
- F4: `{fd}>` dropped as a descriptor. F5: digit runs past 2147483647 are words.
- F6: `grep -n '\('`, `'\|'`, `rg -n '\(\)'`, `git log --grep '\|' -1` are ALLOW; `';'`, `"|"`,
  `\;` still refuse approval (`quoted_separator_word`).
- Every payload is a row in table T of `self/tests/hook-cloud-profile.sh`; `chains_chdir`
  reads the same pieces; NOTES.md → round 3 and `hooks/README.md` describe each fix.
- Look for what the audit did not: a shape where masking, the piece walk or the stand-in
  hides a word or a command from a git rule, or turns a denial into an allow.

## Verdict
