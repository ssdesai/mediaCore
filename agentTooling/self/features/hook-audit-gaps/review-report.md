Verdict: clean

# Review — hook-audit-gaps, round 7

## What the round was supposed to do

Close both round-6 escalations with the fix the owner chose. Round 6's deny (a line that
names git and that no reading lexes is a git command that cannot be read) now also needs
`bash -n` to refuse the line. The ANSI-C excuse no longer applies when bash refuses it. The
bash call takes the text on stdin, runs with `--norc --noprofile` and a PATH-only
environment, has a named timeout, fails closed, and can only add a deny.

## Does it do it

Yes. The change is `ced8e00`: `judged_texts` and the new `bash_refuses` in
`hooks/allow-repo-commands.sh`, plus tests and docs.

- **The round-6 review's lines are back at their round-5 verdicts.**
  - `git commit -m "$(echo "it's")"` and the `printf` form get the does-not-tokenize deny,
    which decays. `hook-escalation.sh` 10c asserts this as `DENY, DENY, ASK`.
  - The `#1` form is a prompt again.
  - These match the round-5 verdicts recorded in `escalations/06-review-opus.md`.
  - The false README sentence "NOT one: anything bash tokenizes" now reads "anything bash
    parses", with the quoted-substitution example.
- **The round-6 audit's B1 lines are denied.** All 5×5 first/second-line combinations and
  the named variants are git denies in both profiles: the T table, `BASH_REFUSED_GIT_DENY`,
  and 10d (never decays). That includes `echo $'\'' '`, which shlex lexes by pairing its
  quotes wrongly.
- **`git commit -m $'it\'s'` and `git push -f origin y⏎echo $'\''` stay prompts.** They are
  pinned in `BASH_PARSED_PROMPT` and the table.
- **The subprocess call is safe.**
  - **What it runs:** `BASH_SYNTAX_ARGV = ("bash", "--norc", "--noprofile", "-n")`, with the
    text sent as `input=`. There is no `-c` and no file.
  - **Environment:** `env={"PATH": "/usr/bin:/bin"}`. Python resolves `bash` against that
    PATH, not the hook's own, and H20 "no bash on the PATH" proves it.
  - **Timeout:** `BASH_SYNTAX_TIMEOUT_SECONDS`.
  - **Fails closed:** an `OSError`, a `SubprocessError` or a `ValueError` counts as refused,
    and the `ValueError` covers a `UnicodeEncodeError` on a surrogate. So do a non-zero exit,
    any stdout or stderr, and a NUL.
  - **Only adds a deny:** the answer is read in one place,
    `(torn or unjudged and unread() and bash_refuses(command)) and unread() or texts`.
    - It runs only when `unread()` is truthy, meaning the line names git.
    - "Refused" returns the git deny.
    - "Parsed" returns `texts`, the same value round 5 returned.
    - No approval path reads it.
  - **Tested by H20:**
    - A canary under 17 execution vectors (substitutions, `<(…)`, heredoc body, `set +n`,
      `trap`, aliases, functions, `eval`, `exec`), with `BASH_ENV`, `ENV` and `SHELLOPTS`
      set in the parent environment.
    - Each fail-closed mode, swapped in one at a time.
    - That bash is never asked about a judged line, a no-git line or a torn line.
    - That bash is asked once per line.
- **Contracts.**
  - No existing test assertion is deleted or weakened: round 7's test diff adds lines only,
    apart from one comment line.
  - `.claude/settings.json` is not in the diff.
  - The gate report's verdict is "all checks passed". Its only non-zero exit is the
    informational pricing-staleness probe, which predates this feature.
  - Every new literal is a named constant.
  - `hooks/README.md`, `self/BACKLOG.md` (item (d), the system bash) and
    `self/tests/README.md` describe the new behaviour. The one stale "refused whole" phrase
    is the one the brief excuses.

**A note on scope, not a finding.** The brief says bash runs "only when round 6's condition
already holds". The code's condition is wider: `all(never_judged(t) or chain_tokens(t) is
None)`, which also covers a reading that shlex lexes but `never_judged` holds back. Closing
the audit's own `echo $'\'' '` variant needs this, and it can only add denies to lines that
name git. It is recorded in NOTES rulings 70–75. It matches the owner's intent, so I did not
escalate it.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.

## Not counted (already-recorded classes)

- **`echo $'\'' && git push -f origin y` is a prompt, not a force-push deny.** It is in the
  ANSI-C class, and `BASH_PARSED_PROMPT` pins it deliberately.
- **Valid bash that no reader judges is a prompt.** This is in BACKLOG item (a) and in "What
  still reaches a prompt".
- **The check uses the system bash, not the session's shell.** The extglob-beside-ANSI-C
  over-deny follows from this. Both are in BACKLOG item (d) and the README over-deny list.
- **On a host with no bash in `/usr/bin` or `/bin`, every unjudged git line is denied.**
  This is the fail-closed behaviour the owner asked for, and it is documented.
- **Bash-refused lines where one reading is judged are not sent to bash.** They prompt, as
  on round 5 and `origin/main`. This is in BACKLOG item (c).
