# orchestration-record-fixes — notes

## Item 1: push reading and redirections — no code change

The brief says `git push origin <current> 2>&1` is denied on main, by `push_reading` taking
`2>&1` as a refspec. It is not, on `origin/main` as this feature started: it is allowed in the
cloud, and so are `-u`, `2>&1 | tail -3`, `2>/dev/null`, `2> /dev/null` and `2>&1` before the
refspec. Redirects are already taken out where words are produced: `command_words` (which
`git_commands`, so every git rule, reads) drops a redirect operator and its target, and
`chain_tokens` drops the file descriptor digit — since `ablation-harness-fixes`
(`32194f0`, 2026-11-07). The orchestration ran 11-08 to 11-09 in humanNetworkMap, so its
vendored copy of the hook most likely predated that subtree pull; a `subtree pull` is the
fix there, not a change here.

**Where it is fixed: where the words are produced, not in `push_reading`.** Stripping in
`push_reading` alone would leave `push_goes_elsewhere`'s siblings (`switch_leaves`,
`checkout_leaves`, `git_mutates`) reading a redirect target as a positional. One place covers
every git rule, and it already exists. The redirect handling itself needed no change; the
audit below did change the hook (two fixes).

What is added is the pin the brief asked for, in `self/tests/hook-cloud-profile.sh` table T:
the current branch with `2>&1`, `2> /dev/null`, `2>&1` before the refspec, `-u` with each,
`2>&1 | tail -3`; a file-writing redirect (`> log`, `>out`, `>> log`, `&>x`, `< in`,
`2>&1 >out`) prompts, never a deny; `main` with `2>&1`, `> log`, `2>/dev/null` and
`2>&1` ahead of the remote is denied, and another branch with `2>&1`, `> log`, `&>x`, `< in`
is denied. `hooks/README.md` says redirects are out of every git rule's words.

A write redirect on the current branch (`git push origin <current> > log`) prompts the human:
it is a write, one the policy cannot approve silently. That is the policy, not the fault the
brief describes. The orchestrator's answer is `2>&1`, which is allowed, not `> log`.

## Security audit of the hook (requested by the repository owner via the #138 orchestrator)

A separate Opus subagent drove the hook (both profiles) with the owner's list and its own.
**Correct, no change:** every unquoted spelling — `main 2>&1`, `main>x`, `>x main`,
`2>/dev/null origin main`, `HEAD:main 2>&1`, `:main 2>&1`, `--force other &>x`,
`--repo >x origin main`, `>main origin other`, `2>main other`, heredoc/herestring/`<` forms,
`|&`, trailing `;`, and switch/checkout/branch/reset with a redirect, in either position: the
redirect's target is the file, as in bash, and no refspec or remote is hidden from a git rule.
A quoted `'2>&1'` is a branch name and is denied in the cloud; `main2>&1` is the refspec
`main2`; `2>&1main` and `>xmain` are bash errors or a plain `git push origin`.
`git push origin '>' main` prompts (git aborts: no local ref `>`) — left as is.

**Two real bypasses, both older than this feature, both fixed with tests (table T):**

1. *A quoted separator word read as an operator* (`command_words`, `command_allowed`,
   `split_subcommands`: shlex loses the quoting). `git branch ';'` was allowed and created
   `refs/heads/;`; `git push origin <current> ';' ls :main` was allowed as two reads while bash
   runs one push of `:main`. Fix: `quoted_separator_word` — a quoted or escaped word made only
   of operator characters — makes `command_allowed` refuse, so such a line is the human's
   (a prompt where an allow was given; the deny side's reading is unchanged).
2. *A quoted, escaped or non-ASCII digit before `>` dropped as a descriptor* (`chain_tokens`).
   `git -C '1'>/dev/null push origin main` read as `-C push` — no push at all — and so did
   `-o '1'>…`, `git push origin '2'>x`, `git branch '7'>/dev/null`. Fix: `is_bare_descriptor`
   — an ASCII digit run is a descriptor only as a whole unquoted word, from the line start,
   whitespace or an operator.

Not changed: `git push origin '>' main` (prompt, harmless as above).

### Round 3: the independent audit of #139 (head bf464c49, `Verdict: findings`)

It found no new silent allow and confirmed both fixes above, but the README's policy (a push of
`main` or elsewhere stays refused with or without redirections) did not hold for five older
families, and one usability regression. All fixed in `hooks/allow-repo-commands.sh`; every
payload is a row in `self/tests/hook-cloud-profile.sh` table T (a push of `main` expects DENY
in both profiles, another branch the refusal of its plain form, the F6 reads ALLOW).

- **F1, quoted operator words on the deny side.** `chain_tokens` now masks every operator
  character that is quoted or escaped (`mask_quoted_punctuation`) before shlex lexes the line,
  and returns a word made only of such characters as a `QuotedWord`; `is_operator_token` is the
  one test `chains_chdir` and `command_words` use, so `';'`, `'>'`, `\;` are arguments (`-o ';'
  origin HEAD:main`, `2> '&&' origin HEAD:other` are pushes).
- **F2, a separator glued to a redirect.** `punctuation_pieces` reads a punctuation run the way
  bash does (left to right, longest operator first: `&&>x` is `&&` then `>`), so a separator
  flushes the command and sets `at_head` and only a redirect sets `redirect_target`
  (`true;>x git push …`, `ls|>x …`, `ls&&>x …`).
- **F3, process substitution.** `<(` and `>(` are a word of the command around them with a scope
  of their own: `command_words` keeps the outer command's words on a stack while the inside
  runs as commands, and `git_subcommand_args` never takes the stand-in for a subcommand (it may
  be glued to a global option, `-c a.b=>(cat)`). `$(…)` gets the same scoping, which also
  fixes `git push -o $(x) origin main` losing its `origin main`.
- **F4, `{fd}>`.** A `{name}` word the lexer ended on `<` or `>` is a descriptor
  (`VARIABLE_DESCRIPTOR_RE`), dropped like a digit run, so it no longer hides the git command
  behind the brace skip.
- **F5, overflow digits.** A digit run is a descriptor only up to `MAX_DESCRIPTOR`
  (2147483647); a longer run is a word, as in bash. `is_bare_descriptor`'s docstring says so.
- **Round 3's escalation (review of `6110b3b`).**
  - *A substitution inside double quotes or backticks.* `mask_quoted_punctuation` masked the
    `(` of `"$(git push …)"`, so the push was one word and never judged. It is now a scan with a
    context stack: a `$(…)` or a backtick pair is lifted out of the quotes around it
    (`"a$(x)b"` is lexed as `"a"$(x)"b"`, a backtick pair as `$(…)`) and its inside is read
    as unquoted text with quotes of its own. The masked line is no longer the line's width;
    only `chain_tokens` reads it.
  - *`git $(true) push origin HEAD:main`.* The `$` left by `$(…)` is skipped among git's global
    options like `<(`/`>(`, so the push behind it is denied. The reviewer asked not to skip it
    for the allow side, and it is not: this changes only the deny side, and a line with a
    substitution is never approved (`command_allowed` refuses a `$`), so `git $(echo reset
    --hard) status` reads as `git status` for the deny side and stays a prompt.
  - *`punctuation_pieces` could spin.* A character of `CHAIN_PUNCTUATION` with no operator would
    never advance the loop. A `for … else` now reads it as a one-character separator, and
    `self/tests/hook-cloud-profile.sh` H1/H2 assert every character has a one-character
    operator.
  - Out of scope as the reviewer listed: `{ git push …; }`, a trailing `#x`, `{fd}` as a bare
    brace argument — no redirection, quoting or substitution; left for a brace/comment feature.
- **Round 4's escalation (review of `849c102` + the #140 merge, and the security audit).**
  - *B1, a `case` arm's `)` inside `$(…)`, a backtick pair or `<(…)`.* The scoped reading
    ended the scope there and read the commands after it as the outer command's words, so
    `echo $(case x in x) git push origin main;; esac)` fell from DENY to a prompt. Fix:
    `command_words` reads the line twice — scoped, and flat (`chain_tokens(…, lift=False)`,
    `command_words_read(…, False)`: the quote-only mask, every operator ends a command, as
    `origin/main` did) — and returns both readings' commands. The union only denies more; it
    gives back `echo $(true) git push origin main` as a deny, as before this feature.
  - *The fragmenting of an outer word* (the review's item 1): the flat reading keeps
    `X="$(pwd)"` and `"./run-$(echo plans).sh"` whole, so `assigned_names`/`uses_own_assignment`
    and `invokes_build_script` read what they did on `origin/main`. Rows: `self/tests/
    allow-repo-commands.sh` ASSIGN_DENY, `self/tests/hook-orchestrator-role.sh` H12.
  - *Round 5 (B2): the same shape inside double quotes.* Neither reading saw
    `echo "$(case x in x) git push origin main;; esac)"` (the scoped mask closed the lifted
    substitution at the pattern's `)` and masked the rest as quoted text; the flat reading
    masks the whole string). Fix at the cause, in `mask_quoted_punctuation`: it counts the open
    `case`s per substitution or backtick frame (`case` / `esac` at command position,
    `CASE_KEYWORD_RE`) and reads a `)` met while one is open as a separator
    (`CASE_PATTERN_SEPARATOR`), so the commands after a pattern are commands of their own and
    the substitution still closes on its own `)`. That also makes the unquoted forms deny in the
    scoped reading, with the flat one as a second net. Rows: table T (B2, nested, assignment),
    and the audit's "the union approves nothing" row (`echo $(true) git status` stays a prompt).
  - *Round 6 (B3a, B3b): the case counter is not shell grammar.* A `case` after `!`, `time`,
    `then`, `do`, `else`, and an `esac` that is a pattern word (`x|esac) …`) fooled the counter,
    the same miss as B2. Two rounds of patching it show that the structural readings cannot
    follow grammar, so the design stops chasing it: `command_words` returns a third reading,
    `command_words_crude`, for a line holding a substitution and the word `case` — cut at every
    operator, quote, paren, brace and `$`, reserved words dropped from each fragment's front,
    deny-side only. The known cost, pinned by a row: `grep -n "case $(x) git push origin main"
    README.md` is refused. Rows: B3a and B3b of the audit, and the false-depth rows
    (`cat "$(echo case-x)" README.md` P, the `esac`-less case D).
  - *Round 7 (B4): the crude cut split quoted words.* `CRUDE_CUT_RE` cut at quotes and kept
    backslashes, so `git push origin 'main'` and `g\it push …` hid the command on exactly the
    lines the crude reading is for. It now deletes `"`, `'` and `\` first (`CRUDE_JOINED_CHARS`)
    and cuts at operators, parens, braces, backticks and `$` only; it over-reads (`'a b'` is two
    words), which only denies more. The `command_words` docstring now says two ways, three with
    the crude one. Not done, by decision: `! git push origin main`, `env git push …`,
    `command git …`, `exec`/`nohup` wrappers and `gi? push` prompt at the top level (no
    substitution, no `case`), as on `origin/main`; they are neither redirection, quoting nor
    substitution, and nothing approves them. A reserved-word and wrapper model for the deny's
    command heads is its own feature.
  - *`hooks/README.md`* describes lifting, the `$` stand-in and the two readings.
  - Not done, as the audit lists them (pre-existing, a prompt, never an allow): `$'\''`
    ANSI-C quoting with an escaped quote, comments, braces, wrappers. The cloud DENY of
    `git push -u origin "$(git branch --show-current)"` is the same on `origin/main`.
- **F6, the regression.** `quoted_separator_word` is now "any `QuotedWord` in `chain_tokens`",
  so the word is de-quoted as shlex does: `'\(' ` and `'\|'` (a backslash, then the character —
  a grep pattern) are words and `grep -n '\(' README.md`, `rg -n '\(\)' …` and
  `git log --grep '\|' -1` are approved again, while `';'`, `"|"` and `\;` stay flagged.

### Round 9: the fail-closed rule replaces the layered readings

Rounds 3 to 8 each patched one grammar shape in the deny side's reading and each came back
escalated with the next one. The repository owner re-scoped the work: item 1 asked only that a
redirection word is never a refspec or remote, which held on `main` and is pinned; the hook stops
following shell grammar and fails closed instead.

**The rule.** A line holding a git word and a `$(…)`, a backtick, `<(`/`>(`, a `<<` (heredoc or
herestring) or the word `case` — anywhere, quoted or not — is not read finely
(`fails_closed`). It is never approved (`command_allowed` refuses it), and the deny side
refuses only what one plain reading finds; whatever that reading misses there prompts the
human. **Prompt, not a rewrite deny,** because a deny would break the documented shapes:
`git commit -m "$(cat <<'EOF' … EOF)"` holds a git word, a substitution and a heredoc, and a
deny would refuse every commit message written that way; the orchestrator allowlist's
`git push -u origin "$(git branch --show-current)"` likewise. Both keep their previous answers
(prompt; the cloud's existing deny of the second is unchanged from `origin/main`). The git word
is found with quotes and backslashes deleted (`g""it`, `g\it`); over-matching only prompts more.

**Removed from `hooks/allow-repo-commands.sh`:** the scoped reading (substitution lifting out of
double quotes and backticks, the per-frame `case` counter, the outer-word stack in
`command_words`), the crude third reading (`command_words_crude`, `CRUDE_*`), the union of
readings, `chain_tokens(…, lift)`, and the skipping of `$`/`<(`/`>(` among git's global options
in `git_subcommand_args`. `mask_quoted_punctuation` is quote-only again and keeps the line's
width. **Kept:** the quoting and redirection fixes — `QuotedWord`, `quoted_separator_word`,
`punctuation_pieces`, `is_bare_descriptor` (F1, F2, F4, F5, F6 and the first audit's two bypasses).
**Added:** `fails_closed`, `is_heredoc_operator` and `judged_tokens` (below). About 110 lines
lighter than round 8 (199 removed, 91 added).

**`command_words` now** reads the line once, the way the flat reading did: every operator ends a
command, a paren included, and a quoted word is one word. So `echo $(git push origin main)`,
`echo $(case x in x) git push origin main;; esac)` and `echo $(true) git push origin main` are
denied (as on `origin/main`), and `X="$(pwd)"` stays whole for `assigned_names`.

**Dispositions.**
- *Round 8 B1 (quoted `'<<'`, `\<\<`, `<<<` switched every git deny off): fixed.* A heredoc is
  only an unquoted `<<` operator piece (`is_heredoc_operator`): a `QuotedWord` is not one, and
  `<<<` is a plain redirect whose target is dropped. A real heredoc no longer makes the line
  unread either: `judged_tokens` reads the heredoc's own line and stops at the first line break
  after the `<<` (the body is data), falling back to that first line alone when a body does not
  lex. `echo '<<' ; git push origin main`, `cat <<< x; git reset --hard HEAD~1`,
  `cat <<'EOF' ; git push origin main` and `git push origin main <<EOF⏎don't⏎EOF` are denied;
  a command after a heredoc's body (`cat <<EOF⏎x⏎EOF⏎git push origin main`) prompts, as on
  `origin/main`, and is never approved. `chains_chdir` uses the same heredoc test.
- *Round 8 B5 (a redirect before the command in the crude reading): moot.* The crude reading is
  gone. Unquoted, the plain reading drops the redirect and denies
  (`echo $(! case x in x) 2>&1 git push origin main;; esac)`); inside double quotes it is one
  word and prompts — the fail-closed outcome, and `origin/main`'s.
- *Rounds 3–7 (F3, B2, B3a, B3b, B4, round 3's quoted substitutions and `git $(true) push`):
  covered by the rule, not patched.* Each such line now prompts (round 8 denied them), which is
  what `origin/main` did; none is approved. The table T rows for them now expect a prompt.
- *Costs of the rule, pinned:* `git log --grep '$(x)' -1`, `git log --grep case -1` and
  `echo '$(git push origin main)'` were approved and now prompt. The round-6 false deny
  `grep -n "case $(x) git push origin main" README.md` is gone (a prompt).
- *Noted, not changed:* `x=1 git push origin main` and the wrapper shapes (`env`, `command`,
  `!`, `time`, braces, comments) prompt as on `origin/main` — never an allow.

Tests: `self/tests/hook-cloud-profile.sh` table T — the fail-closed block, B1 (12 rows), the
heredoc rows, B5 (7 rows) and the rule's costs; the gate passes.

**Round 9's verdicts:** review `clean`; security audit `escalated`, one finding (below). The
review's one nit (`FAIL_CLOSED_MARKERS` repeating the `<(`/`>(` literals) is fixed: it now reuses
`PROCESS_SUBSTITUTION_OPENERS`.

### Round 10: the build-script judge after a heredoc

- *Round 9 audit: a build script after a heredoc's body escaped the build-script deny — fixed.*
  This was a regression this feature caused, not an existing prompt, so it is patched rather
  than recorded. `invokes_build_script` is the one deny a checkout with an unreadable
  orchestrator ledger gives. On `origin/main`, `command_words` returned None for any heredoc
  and the judge fell back to scanning the whole text; round 9's `judged_tokens` reads only the
  heredoc's own line, so `cat <<EOF⏎x⏎EOF⏎./run-plans.sh --self x` prompted. The judge now
  reads a line still holding `<<` (after whole-argument heredocs are swapped for placeholders)
  as text, as on `origin/main`. The git deny keeps `judged_tokens`. Pinned by
  `self/tests/hook-cloud-profile.sh` H3 (four must-run lines and one control). The orchestrator
  allowlist was unaffected: it has its own lexer.

**Round 10's verdicts:** review `clean`; security audit `escalated`, one finding (below).

### Round 11: only a real heredoc takes the text scan

- *Round 10 audit: a quoted `<<` hid a globbed build script — fixed.* Round 10 tested the raw
  substring `<<`, so `echo 'a<<' ; ./run-p*.sh --self x` and `git log --grep='<<' ;
  ./run-p*.sh` took the text scan, which matches a literal name but not a glob, and prompted
  where `origin/main` denied (unreadable-ledger path only; never an allow). The text scan is
  now taken only when the line holds a real heredoc operator (`is_heredoc_operator` over
  `chain_tokens`) or does not lex at all; a quoted `<<` and a `<<<` herestring keep the
  tokenized reading, so `cat <<< x ; ./run-p*.sh` is now denied too (it prompted on
  `origin/main`). A glob after a real heredoc's body (`cat <<EOF⏎x⏎EOF⏎./run-p*.sh`) prompts,
  as on `origin/main`. Pinned by `self/tests/hook-cloud-profile.sh` H4.

**Round 11's verdicts:** review `clean`, audit `clean`. Then `origin/main` (#141) was merged
(see "Item 2" → "After merging #141").

### Round 12 → 13: fail-closed for the build-script judge

**Round 12's verdicts:** review `clean`; audit `escalated`, and stamped stale (the review fixed
a doc line in `analysis/README.md` after the audit ran).

- *Round 12 audit B1: a build script run from a substitution in a reader's arguments
  (`ls "$(./run-plans.sh --self x)"`, `cat "$(./run-p*.sh …)"`, backticks, `git log "$(…)"`)
  was not denied by `invokes_build_script` — fixed, by the orchestrator's ruling.* Not a
  regression (`origin/main` answered the same), but on the deny side of a rule this diff
  reroutes. The plain reading keeps a quoted substitution in one word, and an exempt reader
  (`ls`, `cat`, git's read subcommands) then swallows it. The fix is the git rule's shape:
  `substitution_may_build` — a line holding `$(`, a backtick or `<(`/`>(` and, cut at
  whitespace, operators, parens, backticks and `$` with quoting removed, a word that names a
  build script or a pattern that could match one, is a run. It is applied after whole-argument
  heredocs become placeholders, so `git commit -m "$(cat <<'EOF' … run-plans.sh … EOF)"` is no
  run, and the cut keeps `"$(pwd)"` from reading as `*`. Over-matching only refuses building
  on an unreadable checkout. Pinned by `self/tests/hook-cloud-profile.sh` H5.
- *Round 13's verdicts: review and audit both `escalated`* — four more spellings past
  `substitution_may_build`, all identical on `origin/main`, all prompts on the unreadable-ledger
  path only: (A) `HEREDOC_ARGUMENT_RE` parks an unquoted `<<EOF` body, which bash expands, and
  ends a body at the wrong delimiter line; (B) `ANSI_C_QUOTE_RE` reads a quoted `'$'` as the
  start of `$'…'` and swallows a substitution; (C) an empty expansion or a `$` in a bracket
  glob splits the name (`./run-pla$(:)ns.sh`, `./run-plan[s$].sh`); (D) `${VAR: -N}`.
- **Round 14: the coarse rule, by the orchestrator's ruling.** It was the grammar chase again,
  so `substitution_may_build` is removed and replaced by `unreadable_ledger_refuses` in
  `build_script_denial`: with the role ledger unreadable, a RAW command — read before any
  heredoc placeholder, ANSI-C or extglob rewrite — holding `$(`, a backtick, `<(`/`>(`, `<<`,
  `$'`, `$"` or `${` is refused outright with `UNREADABLE_LEDGER_REASON`, which names the fix
  (repair `.git` or the ledger, or drop the substitution or heredoc). A–D and round 12's B1
  are subsumed. The cost: on such a checkout, `git commit -m "$(cat <<'EOF' … EOF)"` is refused
  too; that checkout is already refused building and arises only when `.git` is broken. A
  readable ledger, or no record at all, is untouched — the heredoc commit keeps its answer
  (table T; `hook-orchestrator-role.sh`). Pinned by `self/tests/hook-cloud-profile.sh` H5.
- **For the reviewer and auditor: finer readings on the unreadable-ledger path are out of scope
  by design.** A spelling that hides a build script from `invokes_build_script` on a line with
  none of the markers above is in scope; one that needs a substitution, heredoc or quoting
  form is refused by the coarse rule and is not a finding.
- **Round 14's verdicts:** review `clean`; audit `escalated`. The audit found no bypass of the
  coarse rule (stable across a session's retries; it subsumes round 12's B1 and round 13's
  A–D). It escalated three older gaps on marker-free lines — all **pre-existing, identical on
  `origin/main`, and prompt-only (never a silent allow)**:
  - **A, an unbalanced quote in a `#` comment** hides the line from the readers
    (`chain_tokens` does not lex it): `./run-p*.sh --self x # '` escapes the build-script text
    scan (literal names only), and on any checkout, ledger readable or not,
    `git push origin main # '` and `git reset --hard HEAD~1 # '` lose their deny and prompt.
  - **B, the two-strikes rewrite prompt:** `./run-p*.sh --self x \`, a line continuation inside
    a name, `ls run-p*.sh | sh`, `bash -c './run-p*.sh'` get only the general rewrite deny,
    which becomes a prompt after `OPAQUE_REWRITE_ATTEMPTS`.
  - **C, the launcher denylist:** a launcher not in `BUILD_SCRIPT_LAUNCHERS` (`unshare`,
    `setpriv`, `prlimit`, awk's `system`, sed's `e`, a git alias) takes a glob through.

  **By the repository owner's ruling, A–C are out of scope for this feature**, handed to
  `hook-audit-gaps`. An audit of this feature judges whether the diff regresses anything versus
  `origin/main` or adds a silent allow; the pre-existing gaps recorded here are not counted.
- *Follow-up, not in this feature:* the audit's pre-existing `git push -fu origin x` — a
  bundled short flag holding `f` is not read as a force push by `git_mutates`, so it prompts
  rather than being denied (identical on `origin/main`). A separate feature should read
  bundled short flags. Also pre-existing and out of scope: `env git …`/`command git …`
  wrappers and a brace word before a git command.

## Item 2: orchestration report root

`roots.record_repo_root()` is the root a `report` path is read against by default: the
directory holding `agentTooling/` when agentTooling is vendored (no `.git` of its own — the
test `roots.py` documents for vendored copies), agentTooling's own root in a standalone
checkout. `report.py --orchestration` passes it as `repo_root`, and `artifact_root(True)`
(the agentTooling directory) as the new `home_root`, which an `agentTooling` entry
(`self/features/<slug>/report.json`) resolves against; with `home_root` omitted it is
`repo_root`, so every existing call is unchanged. Built on `coordinator-cost-records`' (#138)
`compute_orchestration_report(…, checkouts)` and `--checkout`, which stays the override.

**Cross-repo features are out of scope**, as #138 covers them. An entry in a repo other than
`agentTooling` with no `--checkout` is resolved against the project root; a file there prices
it, else it is unpriced with `UNPRICED_NEEDS_CHECKOUT`. The entry's repo cannot be told from
the host repo's name (a directory name is not an identity), so a missing report in the host
repo gets that `--checkout` hint rather than `report path does not exist`. It is a hint
that works (`--checkout <repo>=.`), and the alternative — pricing a foreign repo's feature
from a project root that merely holds the same path — risks a wrong total.

Tests: `self/tests/orchestration-records.sh` S7 (a consuming-repo layout fixture) and S6 (the
standalone layout, unchanged); `self/tests/coordinator-records.sh` K4 stays green.

**After merging #141 (orchestration-records-in-repo).** #141 moved a consuming repo's records
into `plans/orchestrations/` and resolves `report` paths against the record's own repo root
(`artifact_root(self_mode)`), naming that repo `home_repo` (`roots.orchestration_home_repo`),
so a missing report in the home repo now reads `report path does not exist` and only another
repo's asks for `--checkout`. That supersedes `record_repo_root()`, which is removed, and the
"cross-repo" paragraph above. What item 2 still adds is the `agentTooling` entry:
`compute_orchestration_report(…, tooling_root=)`, passed `artifact_root(True)`, resolves an
`ORCH_TOOLING_REPO` entry against the agentTooling directory, which is on disk in every
checkout, so a consuming repo's record prices an agentTooling feature without a `--checkout`
(under #141 alone it was foreign and asked for one). S7 moved to
`self/tests/orchestration-records-in-repo.sh` R2 (the agentTooling-entry row); #141's own R2
rows cover the rest of the old S7. #141's hook change (`--self` admitted for the allowlisted
record tools) carries no git word or fail-closed marker, so the fail-closed rule does not
touch it; `self/tests/hook-orchestrator-role.sh` holds the allowlist's shapes.

## Facts in the brief that were untrue

- `git push origin <current> 2>&1` is denied on main — it is allowed (above).
