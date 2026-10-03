# Notes — policy-module

Rulings, deviations and open questions from the direct build of `policy-module`
(`AGENT_DIRECT.md`), against `self/DESIGN-2026-09-17-policy-module.md` §1–§12 and the
manifest's slices P1–P7. Every decision the design took is built as written; what is
below is what the design left open, plus the three places the build had to choose
between two readings of it.

## Rulings

1. **Every constant a prefix rule is rendered from is an ordered tuple, not a
   frozenset.** `bash_deny_rules()`'s output is compared byte for byte with the committed
   `.claude/settings.json`, so its order is part of the contract, and a frozenset has
   none — `GIT_ALWAYS_MUTATING` as a set would have rendered `clean`, `stash`, `rebase` in
   whatever order the hash gave that interpreter. Membership (`subcommand in
   GIT_ALWAYS_MUTATING`) reads identically on a six-element tuple, so the hook's own
   analysis is unchanged. `GIT_WORKTREE_SUBCOMMANDS` is a dict, which has been insertion
   ordered since 3.7. Said once, at the top of `policy.py`, because a later reader
   "tidying" these into frozensets would break the gate in a way the diff does not show.

2. **`--self --write` GENERATES the whole file; it does not merge.** The design (§3) fixes
   only the check: byte-for-byte against what a write from empty would produce. But a
   merging write cannot satisfy its own check — it appends what is missing, so
   `Edit(**/hooks/**)` and the six new `branch`/`worktree` rules would have landed at the
   end of the list instead of in canonical position, and `--check` would have failed on
   the file `--write` had just produced. Two ways out: teach the check to compare sets
   (which is the defect), or make the write authoritative in the mode where the file is
   generated. The mode already says "wholly generated"; the write now says it too.
   Consuming repos are untouched — `--write` without `--self` merges exactly as before.
   The cost, stated in `hooks/README.md`: a hand edit to that one file is *lost* on the
   next write rather than merged, which is what generated means.

3. **`--self` never reports `INVALID`.** It follows from ruling 2: a generated file that
   does not parse is drift like any other, and the write replaces it rather than refusing
   and asking a human to delete it by hand. `INVALID` remains a merge status, with its
   `permissions.ask` type check beside the `deny` one, and `self/tests/hook-wiring.sh`
   asserts it in the vendored mode where it is reachable.

4. **The drift message names the first differing line *and* the first entry each side has
   that the other lacks.** The design asks for "a diff-shaped message naming the first
   differing entry". A first differing *line* is not that: when the drift is an appended
   section — the commonest hand edit, an added allow rule — the first line that differs is
   the `]` that used to close the deny list, which names nothing. `describe_drift` reports
   the line number, then "carries `"allow": [`" and/or "is missing `Bash(git clean:*)`",
   and says "holds the same entries in a different order" when neither applies (a pure
   reorder, which is real drift and would otherwise point at a bracket with no
   explanation).

5. **"Every case in the test's ALLOW/NOT_DENIED/GIT_NOT_DENIED/ASSIGN_NOT_DENIED lists is
   unchanged" (§4) means every *readable* case.** Four cases in those lists are
   unbalanced quotes — `cat 'x` (PROMPT), `cd 'x && ls` (NOT_DENIED), `git rebase 'main`
   (GIT_NOT_DENIED), `X='/p; cat $X` (ASSIGN_NOT_DENIED) — and §4 names two of them as the
   assertions the seventh shape must make DENY. The sentence cannot hold for those four;
   it holds for everything else, and does. They moved to the new `UNREADABLE_DENY` list,
   with `UNREADABLE_NOT_DENIED` beside it for the guards. No other expectation in those
   lists changed.

6. **The heredoc and `#` guards are looked for in the RAW text.** Every other guard in the
   file asks `command_words`/`shlex` whether a token starts with `<<` or contains `#` — but
   a line that will not lex cannot be asked anything, which is the whole premise of this
   check. `does_not_tokenize` therefore returns False for any command containing `<<` or
   `#` at all, before it tries to lex. That is conservative in the safe direction (a
   prompt, never a wrong deny) and keeps `cat <<'EOF' … don't … EOF` and `ls src # don't`
   printing nothing, as §4 requires.

7. **`bash <scratch>/x.sh --flag` flips from prompt to approved.** It was a
   `SCRATCH_PROMPT` case with the comment "run by name means by name alone", and §5
   deletes that rule: an argument is judged now, and a bare flag is confined by
   `token_confined` for the same reason a flag is confined anywhere else — it carries no
   path. The four §5 assertions sit beside it, and the prompts that remain are the ones
   about *paths* (`/etc/passwd`, a file beside the scratch directory, a link out of it)
   plus `bash -x`, which is a flag before the script.

8. **`scratch_entry_allowed` gained `cwd` and `root`, and `SCRATCH_SCRIPT_ARG_COUNT`
   became `SCRATCH_SCRIPT_MIN_ARGS`.** The old name says "exactly one" and the new rule is
   "at least one, the first being the script" (§5's own words). The two new parameters are
   what an argument is judged against; its one call site in `subcommand_allowed` already
   had both.

9. **`GIT_WORKTREE_READ_ONLY` — an approval-side constant — is taken from the table too.**
   §2 leaves the approval constants in the hook, and they are; this one is the exception
   because it is the *same question* as the deny side's (`git worktree list`), and two
   copies of that answer could approve and deny one command at once. The rest
   (`GIT_READ_ONLY_SUBCOMMANDS`, `GIT_BRANCH_ALLOWED_FLAGS`, the flag lists) stay in the
   hook, as §2 says.

10. **`git branch --list 'feat*'` is NOT denied, and still prompts.** §9 asks only for the
    deny to stop, and that is all that changed: the approval side reads any positional to
    `git branch` as a name whatever the flags say, so the command falls through to the
    prompt rather than being approved. The test asserts `"prompt"`, which is the honest
    expectation; widening the approval is a separate decision nobody has taken.

11. **The seventh shape's reason is its own constant, not a clause appended to
    `OPAQUE_DENY_REASON`.** §4 allowed either. The generic reason's three rewrites — write
    a script, use Read/Grep, inline the literal — are all wrong for an unterminated quote,
    and a deny whose reason names the wrong fix is the thing this whole category exists to
    avoid. `UNREADABLE_DENY_REASON` says to close the quote, and offers the Write tool for
    the case where the text was meant to be data. `opaque_deny_reason()` is the tri-state
    §4 asks for: the six shapes' reason, the quote's, or `None`.

12. **`self/tests/policy-table.sh` is a new file, not a phase in `hook-wiring.sh`** (§11
    allowed either), and it loads `hooks/allow-repo-commands.sh` **as a module** by path to
    assert the twin directly: for every rule `bash_deny_rules()` renders, the hook's own
    `git_mutates` must deny the command that rule names. Asserting the rendering against a
    hand-written expected list would only have restated the table; asserting it against the
    *enforcement* is what makes a future drift in either direction fail. It reads the
    checked-in tree and stands up no sandbox, like `template-versions.sh`.

13. **The `gate.sh` fixture gained a copy at the fixture root.** Without a `gate.sh` at
    the root of the throwaway repo, the new "a bare `gate.sh` prompts" assertion would pass
    because the file does not exist, not because the name has no directory component — a
    vacuous guard. `check-plans.sh` was already there, which is why the bare form was
    approved and is the case that was actually red.

14. **The backlog's opaque entry was kept and rewritten, not removed.** The manifest's
    exclusions keep it, but its assertion (`cat 'x` and `git rebase 'main` denied naming
    the quote) is exactly what §4 built, so leaving the text alone would have left an entry
    claiming an open defect that is closed. It now says the seventh shape landed and names
    what is still deliberately unbuilt — the structural refusals beyond it, where a
    redirect hides nothing. The other kept entry (the vendored
    `agentTooling/.claude/settings.json`) is untouched.

15. **Both scripts set `sys.dont_write_bytecode = True` before importing the table.** The
    import happens inside the repo the hook is guarding, on a `PreToolUse` that runs before
    every Bash call; without this each session would leave a `hooks/__pycache__` in the
    tree. `.gitignore` covers it, but the gate's own `-B` on `py_compile hooks` shows the
    standard this directory is held to.

16. **A consuming repo keeps its old `Edit(**/agentTooling/hooks/**)` deny rule, and deny
    wins over ask.** The merge never removes a rule (that is the contract), so the next
    `sync-plans.sh` there adds the ask rule beside a deny that still refuses everyone.
    Automating the removal would mean teaching the merge to delete, which is the one thing
    it promises not to do. Written down in `hooks/README.md` § The deny rules → `Edit`
    instead: a human deletes one line, once, per repo. Nothing in this feature reaches
    into another repo, as the exclusions say.

## Round 2

17. **`scratch_argument_allowed` judges a relative argument LEXICALLY, before existence
    gets a vote.** Round 1's review (`escalations/01-review-opus.md`) found that
    `bash <scratch>/x.sh ../x` — and the same path spelled `--out=../x` — was approved
    whenever `../x` did not yet exist, and prompted only once it did: the function
    delegates to `token_confined` → `value_confined`, and `value_confined`'s "a value
    that names nothing on disk is not a path" is right for a reader argument that only
    fails on its own (`cat ../x`) but wrong here, because a scratch script's argument may
    well be the OUTPUT path it is about to create. Whether a write is approved must not
    depend on whether the script has already run once before. Decision (a) from the
    escalation: a relative, non-flag value — including the value after `=` — must resolve
    under the project root or the scratch root, `os.path.normpath(os.path.join(cwd,
    value))`, whether or not anything is there yet; only once that lexical check passes
    does the existing existence-and-symlink check (`token_confined`, or
    `lexically_inside`/`inside` against the scratch directory) get the final say, so a
    symlink out of either root is still not confined once the path exists. A bare flag
    (`--flag`, `-v`) carries no path and is unaffected; an absolute value keeps `inside()`'s
    existing behaviour, which already judges by resolution rather than existence — the
    escalation noted the absolute form was never the bug.

    **Existence must not decide** because it makes the same command's approval a function
    of *when* it is run rather than of what it names: a script re-run after its first
    write would flip from approved to prompting for the identical argument, which is
    exactly backwards — a script's own output path is the ordinary case this needed to
    keep working, not the dangerous one.

    Reproducing the exact escalation example (`bash <scratch>/x.sh ../x`) through the
    full hook already prompts today, independently of this defect: `command_allowed`
    refuses any command containing a literal `..` outright (`UNANALYSABLE`), before the
    scratch logic is ever reached. The defect is real in `scratch_argument_allowed` as a
    unit, though — confirmed by calling it directly, bypassing `command_allowed`, before
    this fix: `scratch_argument_allowed("../x", ...)` and `scratch_argument_allowed(
    "--out=../x", ...)` both returned `True` (approved) against an absent path. The fix
    closes the function's own defect rather than leaning on the coarser guard, since nothing
    says `UNANALYSABLE`'s scope stays as wide as it is today.

    **Assertions** (`self/tests/hook-escalation.sh`, § 7): `SCRATCH_PROMPT` gains
    `bash <scratch>/x.sh ../x` (`../x` absent) and `bash <scratch>/x.sh --out=../x`;
    `SCRATCH_ALLOW` gains `bash <scratch>/x.sh new-output.txt` (relative, absent, inside
    the root) to lock in that the ordinary output-path case keeps working. All three ran
    against the full hook: the two prompt cases already read `prompt` before the source
    fix (for the `UNANALYSABLE` reason above, not because the defect was absent), and the
    allow case already read `ALLOW` before the fix too, since `new-output.txt` was inside
    the root either way. Those three commands alone cannot show whether the fix inside
    `scratch_argument_allowed` is doing anything, so the round 2 review pass added § 8:
    the hook loaded as a module (the technique `policy-table.sh` uses) and
    `scratch_argument_allowed` called directly, bypassing `command_allowed` and its
    `UNANALYSABLE` guard entirely. That is the persisted, function-level check that shows
    the fix changed behaviour — `False`, `False`, `True` for the same three cases, plus a
    fourth confirming `../x` stays refused once a real file exists there — against
    `True`, `True`, `True` (no existence check at all) before this fix, reproduced by
    hand against the pre-round-2 source during this review.

## Deviations from the design and the manifest

- **None in scope.** Every slice P1–P7 landed. Rulings 2, 3 and 4 are decisions §3 left to
  the build rather than departures from it; rulings 5 and 7 are the two places an existing
  test expectation had to flip for a design decision to hold, both named in the design's
  own assertions.
- **`self/README.md`'s `DESIGN-2026-09-17-policy-module.md` row was not touched**, as
  briefed. Its `gate.sh` and `tests/` rows were.
- **`self/PROJECT_FACTS.md` moved, though neither the design's scope nor the review
  brief lists it** (ruling added by the review pass). Its `hooks/` bullet and its gate
  list stated the old drift check ("still matches the constants") and the old
  `py_compile hooks` line; left alone they would have told the next plan author the
  opposite of what the gate now does. Docs-only; no fact a plan pins changed meaning.
  `self/routing/654e3f53-….json` also moved on this branch, but in the `policy-module:
  start` commit — `feature-start.sh`'s routing record, not the build.

## Open questions

- **The vendored `agentTooling/.claude/settings.json` now carries an ask rule that names
  the wrong path.** It ships with the subtree holding `Edit(**/hooks/**)` and
  `Edit(/hooks/**)`, and in a consuming repo `/hooks/**` resolves against *that* repo's
  root. Nothing reads that nested file today — the existing backlog entry is about exactly
  this, for the hook command — so this changes nothing about the risk, but it adds a second
  wrong value to the same file, and whatever closes that entry should close both.
- **An `ask` rule is untested end to end here.** `hook-wiring.sh` asserts the rule is
  written into `permissions.ask` and not into `permissions.deny`; that Claude Code prompts
  on it under `acceptEdits` and refuses it in `claude -p` is read from the permissions docs
  (§7), not from a test — nothing in this harness can drive the permission system. The
  first real evidence will be the next runner pass that tries to edit `hooks/`.

## Timing

- The `checkpoint status=tests-written` stamp landed **after** the hook half of the
  implementation, not at the moment the tests went red: the four red runs are in this
  session's transcript before any hook edit, but the stamp was not. So the report's
  tests-first sub-row over-reports by roughly the `allow-repo-commands.sh` edits, and the
  build sub-row under-reports by the same. Noted rather than corrected, since a stamp
  moved by hand afterwards would be a guessed instant.
