Verdict: escalated

# Review — orchestration-record-fixes, round 4 (`849c102` + merge `51bb211`)

## What the batch was supposed to do

Close round 3's escalations in `hooks/allow-repo-commands.sh`:

- A `$(…)` or backtick substitution inside double quotes, or a backtick pair anywhere, is read
  as commands, so a push of `main` inside one is DENY.
- `git $(true) push origin HEAD:main` is DENY, while `git $(echo reset --hard) status` stays a
  prompt and is never an allow.
- `punctuation_pieces` can no longer spin forever, and a test asserts operator coverage.

It also merges `origin/main` (#140, the orchestrator allowlist), whose push shape must run
through these push rules.

## Does it do it?

For the push rules, yes. I drove the hook with about 55 payloads in both profiles, each from
a fresh session id. All of the following held:

- **Round 3's table rows:** every new row gives its stated answer. The double-quoted,
  backticked and unquoted-backtick pushes of `main` are DENY/DENY. `git $(true) push …`,
  `git $(true) $(true) push …`, `` git `true` push … ``, `git -C . $(true) push …`,
  `git $(true) stash` and `git $(true) reset --hard` are all DENY. `git $(echo reset --hard)
  status` is a prompt.
- **Literals stay literals:** `echo '$(git push origin main)'`, `echo "\$(git push …)"` and
  ``echo \`git push …\` `` are ALLOW, which is correct: bash runs no substitution in any of
  them.
- **Mixed shapes:** nested and mixed forms deny correctly. That covers `"$(echo `git push …`)"`,
  `"$( (git push …) )"`, `"${x:-$(git push …)}"`, `git log --format="%H $(git push …)"` and
  `echo "a\"$(git push …)"`.
- **Pushes of another branch:** a quoted operator word, `$(true)` or a backtick pair before a
  second refspec (`… <branch> $(true) main`) stays DENY.
- **No new allows:** no probe turned a denial into an allow. Every line holding a
  substitution is refused approval.
- **Operator guard:** the `for … else` fallback is sound, and H1/H2 assert full operator
  coverage.
- **The merge:** the orchestrator allowlist runs before every judge. The push rules still
  apply after it (`main()`, the judge loop). `orchestrator_words` refuses `$`, backticks and
  `<>()&` outside its one exact `"$(git branch --show-current)"` placeholder, so nothing in
  it reads a redirect, quoted operator word or substitution as an argument. `git push -u
  origin <current branch>` is ALLOW in cloud with or without `2>&1` / `> /dev/null`.
  Following it with `">" main`, `";" main`, `$(true) main` or `` `true` main `` is DENY.

The gate is green, and nothing in it is SKIPPED.

The lifting does have one side effect the push rules don't show. Lifting splits the word
around a quoted or backtick substitution into fragments. `command_words` is read by two
other deny judges, and two of them now read those lines differently from `origin/main`.
Nothing becomes an allow, but a documented deny is lost (below).

## Fixed in this pass

Nothing. I tried one local documentation fix, but the edit was refused permission, so it is
escalated as item 2.

## Escalated to the next round

1. **Lifting splits the outer word, and two other `command_words` readers lose a deny.**
   - **Cause:** `mask_quoted_punctuation` (`hooks/allow-repo-commands.sh:1064`) rewrites
     `"a$(x)b"` as `"a"$(x)"b"` and a backtick pair as `$(…)`. `command_words` then returns
     the outer word as separate fragments.
     - `X="$(pwd)"` becomes `['X=$', '']`, where `origin/main` had `['X=$(pwd)']`.
     - `"./run-$(echo plans).sh"` becomes `['./run-$', '.sh']`.
     - ``./run-`echo plans`.sh``, unquoted, is now split the same way.
   - **The git rules don't mind this.** The other consumers do; I compared each function
     directly against `origin/main`'s hook:
     - **`invokes_build_script`** (the fail-closed build-script deny, `LEDGER_UNREADABLE`;
       hooks/README.md → "What the name matching still does": "a line that names, or may
       expand to, a build script"). It is True on `origin/main` and False now for:
       - `"./run-$(echo plans).sh" --self x`
       - `bash "./run-$(echo plans).sh" --self x`
       - `"./run-`echo plans`.sh" --self x`
       - ``./run-`echo plans`.sh --self x`` (unquoted)
       - `bash "./ru$(true)n-plans.sh"`
       - `"./run-plans$(true).sh"`
       
       `BUILD_SCRIPT_EXPANSION_RE` reads a `$(…)` or backtick inside a word as `*`, but
       the word no longer holds one. Unquoted `./run-$(echo plans).sh` was already False on
       `origin/main`; that gap predates this batch.
     - **`assigned_names` / `uses_own_assignment`.** On `origin/main`,
       `X="$(pwd)"; cat $X/f`, `X="`pwd`"; cat $X/f` and `X="a$(pwd)"; cat $X/f` get the
       assign-then-use deny. Now they fall through to the generic "expands a variable"
       deny.
   - **Effect:** still fail-safe. Each of these lines is still denied, by the opaque or
     variable rewrite. But those denials bump the escalation counter and turn into a
     prompt after two. The build-script and assignment denies clear the counter and never
     give way. No test row covers any of these shapes.
   - **Fix (a design decision, so not done here):** make `command_words` keep a lifted
     substitution's outer word whole. Re-glue the fragment before the `$(` and the one
     after the `)` (or closing backtick) when no whitespace separates them in the masked
     text. Leave a stand-in inside the word that `BUILD_SCRIPT_EXPANSION_RE` reads as `*`,
     e.g. keep the `$` and append `*`. The git rules keep what they have now: the `$`
     stand-in rule only skips a whole `$` word.
   - **Missing rows:**
     - For `self/tests/hook-orchestrator-role.sh`, asserting `invokes_build_script(...)` is
       True: each of the six shapes above.
     - For `self/tests/allow-repo-commands.sh`, asserting the assign-then-use reason:
       `X="$(pwd)"; cat $X/f`, ``X="`pwd`"; cat $X/f`` and `X="a$(pwd)"; cat $X/f`.

2. **`hooks/README.md` doesn't describe round 3's rework.** The plan's contract says it
   should. The paragraph at lines 503–511 still describes masking as quote-only, and
   doesn't mention lifting `$(…)` and backticks out of double quotes or the `$` stand-in in
   `git_subcommand_args`. NOTES.md → round 3 does describe both. Insert after "…with a scope
   of their own (`…NOTES.md` → round 3, F1–F6).":
   > That holds inside double quotes and for a backtick pair too: `mask_quoted_punctuation`
   > lifts a `$(…)` or a backtick pair out of the quotes around it (`"a$(x)b"` is lexed as
   > `"a"$(x)"b"`, a backtick pair as `$(…)`), so `echo "$(git push origin HEAD:main)"` is the
   > push it is; and the `$` a `$(…)` leaves among git's global options is skipped like
   > `<(`/`>(` (`git_subcommand_args`), so `git $(true) push origin HEAD:main` is denied — on
   > the deny side only, since a line with a substitution is never approved.
   
   This review pass tried that edit, and the edit was refused permission.

### Seen, out of this feature's scope (no action asked)

- **The orchestrator's documented push is denied in cloud.** In the cloud profile,
  `git push -u origin "$(git branch --show-current)"` is DENY: the push rules can't read
  the branch a substitution names. `ORCHESTRATION.md` and the allowlist give that line as
  the orchestrator's push. `origin/main` gives the same DENY, so the merge didn't cause it.
  An orchestrator in a cloud container has to push the literal branch name instead, which
  is ALLOW. Locally both shapes are a prompt.
- **Some shapes still prompt where bash runs a push of `main`.** These are fail-safe, never
  an allow:
  - nested escaped backticks: ``echo "`echo \`git push origin HEAD:main\``"``
  - a `case` pattern's `)` inside `"$(…)"`
  - a refspec assembled by a substitution in the local profile, e.g. `HEAD:ma$(true)in` or
    `HEAD:$(echo main)` (cloud denies these)
