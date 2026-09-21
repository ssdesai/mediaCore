# Notes — minutes-slug-and-quoting

Rulings, deviations and open questions from the direct build of
`minutes-slug-and-quoting` (`AGENT_DIRECT.md`), against
`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §1–§5 and the manifest's S1–S5.
Written as each was made, not at the end.

All five slices are built. S5b was paused for the coordinator and then built to its
ruling — see rulings 4 and 11, which belong together.

## Rulings

1. **`slug_of_start_command` splits into two functions, and the per-line one is the
   one with the rule in it.** `slug_of_start_line` holds the positional scan exactly
   as it was; `slug_of_start_command` joins the `\`-continuations and feeds it one
   line at a time. `re.MULTILINE` came off `COMMAND_POSITION_RE` — with the match now
   confined to a single line it decides nothing, and leaving a flag whose whole effect
   was the defect would invite it back.

2. **Several lines may run the script, and the first that NAMES a slug wins.** The
   design says "the slug is the token after the script on that same line, or nothing",
   which leaves open what to do when line 1 is a slugless start and line 2 is a real
   one. A slugless start names no feature, so it is not an answer; the scan passes over
   it and keeps looking — but only at another line that RUNS the script, never at an
   arbitrary word, which is the whole of what went wrong before. Asserted from the
   other side by R10b/R10c: a non-start line is never read for a slug.

3. **`is_router_lines` now returns False for a session whose only start carries no
   slug**, and that is correct rather than incidental. It asks
   `bool(feature_start_slugs(lines))`, and a start that names no feature contributes
   no entry — so such a session started nothing, is not a router, and stays in
   `--list-sessions --unclaimed` where its cost can still be seen. The old behaviour
   was the opposite and was the defect's real cost: `./feature-start.sh --self` above
   `ls` made the session a router that had opened a feature called `ls`, which dropped
   it out of the one listing whose job is to surface unclaimed cost. Asserted as R4i.

4. **S5b was not built until the coordinator had ruled on it** (see ruling 11 for the
   ruling and what it changed). §5b widens what the hook
   AUTO-APPROVES, which is the one kind of change in this feature that can cost
   something if it is wrong, so it is held for a decision rather than taken by the
   implementer. Two things were established before pausing, and both should feed that
   decision:

   - **The design's literal wording is unsafe.** It says the approval side should skip
     "the same global value options as the deny side" — `GIT_GLOBAL_VALUE_FLAGS`, which
     includes `-c`, `--config-env` and `--exec-path`. Skipping `-c` would auto-approve
     `git -c core.pager='sh -c id' log`, which runs `sh`. That command is in the test's
     PROMPT list today precisely because it is a bypass the audit found, and the review
     brief requires every existing case to keep passing. So the built rule must be the
     narrower one: skip only the options that name a LOCATION (`-C`, `--git-dir`,
     `--work-tree`, `--namespace`), each value confined to the project root, and leave
     the other three prompting. The tests were written to that narrower rule, with the
     three unsafe options asserted as still prompting.
   - **The residual risk of even the narrow rule** is that `git -C <path in the root>
     <read-only subcommand>` becomes an approval rather than a prompt. The subcommand
     is still judged by `GIT_READ_ONLY_SUBCOMMANDS` and the deny side still runs first,
     so `git -C <root> branch new` and `git -C <root> worktree add x` stay denied; the
     confinement is `value_confined`, the same one every other path in the file gets,
     so `git -C /elsewhere` still prompts. What is genuinely new is that a read in a
     sibling worktree inside the root no longer asks.

5. **S5a is a narrowing and was kept separate from S5b for that reason.** `path_body`
   changes only `substitution_in_path`, which only feeds `is_opaque`, which runs only
   after the approval analysis has already declined. It can therefore turn a DENY into
   a prompt and can never turn a prompt into an approval. Verified rather than argued:
   with it applied and S5b absent, the ALLOW group (56 cases) and the audited-bypass
   group (141 cases) are both unchanged, and the only failing cases in the file are
   S5b's seven.

6. **The mechanism §5a names is not the mechanism that was wrong.** The design says the
   opaque scan "reads the raw line for `SHELL_ACTIVE_CHARS`". It does not:
   `SHELL_ACTIVE_CHARS` is read only by `shell_active_outside_quotes`, on the approval
   side, which has always been quote-aware. The real path was `word_body` stripping a
   word's outer single quotes before `substitution_in_path` asked whether it held a
   substitution — so the backticks inside `'/```json/,/```/p'` read as unquoted. The
   fix is `path_body`, which strips double quotes only. The observable contract in the
   design is unchanged; only its account of the cause is.

7. **§5a's "`$HOME` and `<(x)` outside quotes are still opaque" is not built, because
   it is not true today and making it true would widen the deny.** `cat $HOME/f`
   prompts now (`ASSIGN_NOT_DENIED`), and `ls \`id\`` prompts as a whole-argument
   substitution (`OPAQUE_NOT_DENIED`) — which is also why the design's own example
   ``echo `date` `` is not denied today and was not made so: it is the same shape as
   `ls \`id\``, and the review brief requires that case to keep passing. The assertion
   was taken as the manifest and the review brief phrase it — "an unquoted backtick is
   still denied" — and pinned on the two shapes that really are denied,
   `` cat `pwd`/README.md `` and `` `which ls` src ``, plus two new guards
   (``sed -n 5p `pwd`/README.md``, `cat $(pwd)/src/a.py`) so the narrowing cannot drift
   into the unquoted case.

8. **The opener's AppleScript escaping is written with literal patterns, not named
   ones, and the comment says why.** `${text//$VAR/…}` works for the single quote and
   silently does nothing for the backslash: a `\` expanded from a variable is taken as
   a pattern escape by bash's own substitution and matches nothing (verified under bash
   3.2.57). So `SHELL_QUOTE`/`SHELL_QUOTE_ESCAPED` are named constants and the two
   AppleScript patterns are `${text//\\/\\\\}` and `${text//\"/\\\"}` inline. This is
   the one place in either copy where naming the value would stop it working, and that
   is stated at the call site rather than left for a reader to rediscover.

9. **The opener's round trip is a NEW test file, `self/tests/open-session.sh`, not a
   phase of `feature-lifecycle.sh`.** The brief allowed either. The round trip needs a
   PATH of its own with `osascript` and `claude` stubbed, and a worktree path holding a
   `"` and a `\` — neither of which belongs inside the lifecycle driver, which is
   already 1,600 lines and stands up a whole git checkout for a different purpose.
   `self/gate.sh` gains the two additive lines that register it (its `shell_scripts`
   list and one `record` line), the same treatment `manifest-window.sh` got in
   `ledger-and-routing` ruling 22. `feature-lifecycle.sh` S5 keeps the text reads and
   gains S5e/S5f, so the two files divide as "reads it" and "runs it".

10. **The two footnote entry shapes gained fields rather than new marks**, as §1 asks.
    `missing_duration_plans[]` entries carry `unmeasured_attempts` and `attempt_count`,
    `recovered_duration_plans[]` entries carry `measured_attempts` and
    `recovered_attempts`, and the existing `†`/`‡` marks are untouched. Phases 4b, 4f
    and 6b of `report-footnotes.sh` are re-pinned to the richer shapes — they assert
    the entry by exact equality, so a new field is a deliberate change to them and not
    a silent one.

11. **The coordinator's S5b decision**, taken on the analysis in ruling 4 and recorded
    here because the built rule is narrower than the design's §5b and a later reader will
    otherwise read the difference as drift. Proceed with the narrowed rule, under five
    constraints, all of which are built and asserted:

    1. **Three options skipped, not seven**: `-C`, `--git-dir`, `--work-tree`
       (`GIT_GLOBAL_LOCATION_OPTIONS`). Not `--namespace` — nothing needs it, and
       unlisted means prompt, which is the safe default. Never `-c`, `--config-env` or
       `--exec-path`, for the reason ruling 4 gives. The constant's comment says it is a
       subset of `GIT_GLOBAL_VALUE_FLAGS` and why each of the other four is out.
    2. **Nothing else in front of the subcommand is skipped.** Any other token starting
       with `-` ends the walk and the command is not approved — a bare flag is not
       harmless just because it takes no value, since `--paginate`/`-p` forces the pager
       config names even when stdout is not a tty. `git --paginate log`, `git -p -C
       <root> log`, `git --no-pager -C <root> log` (an accepted cost) and `git -C <root>
       -c core.pager=x log` all prompt.
    3. **A location option's value must be present and must not itself start with `-`**,
       in both the attached and the separate spellings: `git -C` and `git -C --git-dir
       status` prompt.
    4. **Confinement is not repeated.** The existing `token_confined` pass over every
       argument in `subcommand_allowed` already covers both spellings and every
       repetition, so `git -C <root> -C /tmp status` fails there on the second value. A
       second confinement path would be a second place for the two to disagree, so
       `git_location_args` takes no `cwd`/`root` and `git_allowed` keeps its signature.
    5. **Approval side only.** The deny side's `git_subcommand_args` and its wider
       `GIT_GLOBAL_VALUE_FLAGS` loop are untouched, and the forbidden-flag list still
       applies to what follows the subcommand (`git -C <root> diff --ext-diff` prompts).

    The coordinator also audited S5a at `6f8a131` independently and confirmed it a
    narrowing, probing the partial-quoting shapes this build did not: ``cat ''`$(pwd)`/x``,
    `cat 'a'$(pwd)'/x'`, `cat '\'$(pwd)/x` and `cat "$(pwd)/README.md"` are all still
    DENY. Those are the cases where `path_body` strips nothing and `unquoted_index`'s own
    quote state has to carry the judgement, so they are the ones that would have shown a
    partial-quote hole if there were one.

## Open

- Nothing from this feature. The three backlog entries it closes are removed; the three
  it does not are untouched.
