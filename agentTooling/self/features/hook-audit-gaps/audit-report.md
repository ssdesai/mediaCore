Verdict: clean

# Security audit (round 7, opus): hook-audit-gaps

Audited: `hooks/allow-repo-commands.sh` and `hooks/README.md`, `git diff origin/main...HEAD`.
The audit focused on round 7's change (`ced8e00`). That change replaces round 6's ANSI-C
excuse in `judged_texts` with `bash_refuses`, which runs `bash --norc --noprofile -n` on stdin
with `PATH=/usr/bin:/bin` alone and fails closed. The README section it rewrote is "A line that
names git and that no reading tokenizes".

Every input ran against a throwaway `git archive HEAD` copy under
`/tmp/plan-capture.RfRNpw/scratch`, with `CLAUDE_PROJECT_DIR` pointing at the copy. Some inputs
also ran against an `origin/main` copy for comparison. The payload was `tool_name: Bash`,
`session_id`, `cwd` and `tool_input.command`, in profile `local` and, where marked, also in
profile `cloud`. Each line was also run by real bash (`bash -c 'eval "$1"'`) with logging stubs
for `git` and `gh` first on `PATH`. That records whether bash really runs the denied command.

Key: "deny" means denied. "prompt" means no output, so the human is asked. "allow" means
approved. **No input was allowed.**

## Rule the round changes

| # | Rule | Denies, for whom |
|---|---|---|
| R7-1 | `judged_texts`: when no reading of the line is judged, the line names git (`GIT_WORD_RE` after quotes and backslashes are dropped) and `bash -n` refuses the line, the line is judged as `GIT_UNREADABLE_ARGS`. "Not judged" means every reading either fails to tokenize or is held back by `never_judged`. The bash check is `bash_refuses`. It counts no bash, a timeout, a NUL, an unencodable character, a non-zero exit or any output as a refusal. | git deny, every session, both profiles |

Rules R1–R8 and R6-1 from earlier rounds were re-checked with a regression sample (last table).

## Inputs tried

`P` = `git push -f origin y`. `⏎` = newline. "bash runs?" says whether stub git recorded the
command.

### Round 6's B1 (should now deny)

| Input | HEAD local | HEAD cloud | bash runs? |
|---|---|---|---|
| `P⏎echo $'\'' "` | deny | deny | yes |
| `P⏎echo $'\'' '` | deny | deny | yes |
| `P⏎echo $'\''⏎echo "` | deny | deny | yes |
| `echo $'\''⏎P⏎echo "` | deny | deny | yes |
| `git reset --hard⏎echo $'\'' "` | deny | deny | yes |
| `P⏎echo $'\''` (bash parses it; documented as BACKLOG (a)) | prompt | prompt | yes |
| `git commit -m $'it\'s'` (valid) | prompt | prompt | yes |
| `git commit -m "$(echo "it's")"` (valid; round 6's review) | deny (does-not-tokenize, decays) | same | yes |
| `git commit -m "$(cat <<'EOF'⏎it's fine⏎EOF⏎)"` | prompt | prompt | yes |

### The "names git" gate, on a broken line

| Input | HEAD | Well-formed twin (no `⏎echo '`) | bash runs? |
|---|---|---|---|
| `gi$'t' push -f origin y⏎echo '` | deny (does-not-tokenize) | prompt | yes |
| ``gi``t push -f origin y⏎echo '`` | prompt | prompt | yes |
| `gi$()t push -f origin y⏎echo '` | prompt | prompt | yes |
| `gi${_:0:0}t push -f origin y⏎echo '` | prompt | — | yes |
| `gi$@t push -f origin y⏎echo '` | prompt | deny (variable) | no |
| `GIT_X=1 P⏎echo '`, `env P⏎echo '`, `command P⏎echo '`, `\P⏎echo '`, `"git" push -f origin y⏎echo '` | deny | — | yes |

### Pushes hidden by a misreading of quotes nested in a substitution

| Input | HEAD | origin/main | bash runs? |
|---|---|---|---|
| `echo "$(echo "it's")" ; P ; echo '` (one line) | prompt | — | no (bash refuses the whole line first) |
| `echo "$(echo "it's")" ; P` | deny (does-not-tokenize) | — | yes |
| `echo "$(echo "it's")" ; P⏎echo '` | prompt | prompt | yes |
| `echo "$(echo "it's")"⏎P⏎echo '` | prompt | prompt | yes |
| ``echo "`echo "it's"`" ; P⏎echo '`` | prompt | prompt | yes |
| `echo "$(echo "it's")" ; git reset --hard⏎echo '` | prompt | prompt | yes |
| `echo "$(echo "it's")" ; P⏎: '`, `…⏎P⏎'` | prompt | prompt | yes |
| `echo "$(echo "it's")" ; P⏎echo "'"` | deny (does-not-tokenize) | deny | yes |
| `echo "$(echo 'a"b')" ; P ; echo "`, ``echo `echo "it's"` ; P ; echo '``, `echo ${x:-"it's"} ; P ; echo '`, `echo "${x:-'}" ; P ; echo '`, `echo $"it's" ; P ; echo '` | deny | — | no |
| `P⏎echo "$(echo "it's #")"` (documented as BACKLOG (a)) | prompt | — | yes |
| `P⏎echo "$(echo "it's #")"⏎echo '` | deny | — | yes |
| `shopt -s extglob⏎P⏎echo @(x) "` | deny | — | yes |
| `P⏎echo "$(cat <<EOF⏎x⏎EOF⏎)" '` | deny | — | yes |

### `bash -n` executes nothing (canary files, hook only)

Each of these lines was denied, and no canary file appeared afterwards:

| Input (each followed by an unclosed `$'\'' "`) | HEAD |
|---|---|
| `P⏎…⏎touch canary1` | deny |
| `P⏎…$(touch canary2)…` | deny |
| `P⏎set +n⏎touch canary3⏎…` | deny |
| `P⏎cat <(touch canary4) >canary5⏎…` | deny |
| `P⏎cat <<EOF⏎$(touch canary6)⏎EOF⏎…` | deny |
| `P⏎trap 'touch canary7' EXIT⏎…` | deny |
| `P⏎exec 3>canary8⏎…` | deny |
| ``P⏎echo `touch canary9` …`` | deny |

### Malformed payloads and the fail-closed paths

| Payload (command `P⏎echo $'\'' "` unless stated) | HEAD |
|---|---|
| A NUL appended; a NUL in the bash-parsable `P⏎echo $'\''` | deny, deny |
| A lone surrogate (`\ud800`) in the command | deny |
| No `cwd`; no `session_id`; `agent_id` set; `cwd: /` | deny each |
| 200k-character line; 3,000 nested `$(`; CRLF line ends | deny each |
| Copy with `BASH_SYNTAX_ARGV` pointing at a missing program | deny (both the broken line and `P⏎echo $'\''`) |
| Copy with `BASH_SYNTAX_TIMEOUT_SECONDS = 0.000001` | deny (both) |
| Control: copy with `true` in place of bash (the "parses" answer) | prompt (both), which shows the answer comes from bash |

### Regression sample from rounds 1–6

| Input | HEAD | bash runs? |
|---|---|---|
| `git push -fu origin y`, `-{f,u}`, `--forc{e,x}` | deny | yes |
| `git push -uof origin y` | prompt (correct: `f` is `-o`'s value) | runs, no force |
| `P⏎echo "$(cat <<EOF`, `P⏎echo '#`, `P⏎gh pr create --body "$(cat <<'EOF'⏎x` | deny | yes |
| `echo "$(cat <<E'O'F⏎x"⏎EOF⏎)" ; P`, `echo "$(cat <<'EOF'⏎x⏎EOF )" ; P⏎EOF⏎)"` | deny | yes |
| `cat <\⏎(cat <<EOF⏎x⏎EOF ) ; P⏎EOF⏎)`, `echo "$(cat <<EOF⏎EO\⏎F⏎git push --force origin y⏎EOF⏎)"`, `cat <<EOF⏎EO\⏎F⏎P⏎EOF` | deny | yes |
| `ls;<<EOF cat⏎x⏎EOF⏎cd /tmp && ls` | deny (chained cd) | — |
| `git push origin main # '` | deny | yes |
| `ls # x; P` | prompt | no (it is a comment) |
| `(ls) # it's⏎P⏎cat <<EOF⏎echo '` (documented as BACKLOG (c)) | prompt | yes |
| The usual commit message and PR body under `'EOF'` | prompt | yes |
| `git status` | allow | yes |

## Bypasses

None. Every input that R7-1 exists to deny was denied. To be in R7-1's scope, a line must name
git, no reading here may judge it, and bash must refuse it. `bash -n` executed nothing, and
every failure path of `bash_refuses` denied. Round 6's B1 is closed in both profiles.

## Outside the round (pre-existing, prompts, never allows)

- **Quotes nested in a `"$(…)"` or quoted backticks, then a push, then an open quote on a later
  line.** `echo "$(echo "it's")"⏎git push -f origin y⏎echo '` is a prompt, and bash runs the
  push.
  - The flat reading closes the outer `"` at the inner one. That leaves the push inside a
    `'…'` that runs to the last line, so that reading tokenizes and R7-1 never asks bash.
  - The well-formed twin (no last line) takes the does-not-tokenize deny. Adding the open quote
    therefore turns a deny into a prompt.
  - `origin/main` gives the same prompt, so this is not a regression.
  - It falls under `self/BACKLOG.md`'s class (c), "a line that names git of which one reading
    tokenizes, though not bash's", and under the next entry, "the deny side does not follow a
    substitution's scope". BACKLOG (c)'s only example is the doubtful-comment one, so this
    spelling could be added there as a second example. It is not a bypass of the round's rule,
    whose scope excludes a line some reading judges.
- **A substitution or ANSI-C quote inside the program word.** ``gi``t``, `gi$()t`,
  `gi${_:0:0}t` and `gi$'t'` are prompts, broken line or not. `unread`'s `GIT_WORD_RE` does not
  see these spellings as git, and the git deny does not either. This is already recorded
  ("a substitution as the program word", "ANSI-C quoting of a git word").
- `self/BACKLOG.md` (a)–(d) behave as documented. Spot-checked: `P⏎echo $'\''` and
  `P⏎echo "$(echo "it's #")"` (both prompts), and `(ls) # it's⏎P⏎cat <<EOF⏎echo '` (prompt).
