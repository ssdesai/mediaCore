Verdict: escalated

# Review — policy-module

Base `lifecycle-records-and-numbering`, diff `git diff lifecycle-records-and-numbering...HEAD`
(4 commits, 22 files). Gate: green on every check (`self/gate-report.txt`, level `final`);
none SKIPPED.

## What the feature was supposed to do

Write the git policy down once, as data (`hooks/policy.py`), and have both halves read it:
the hook's `git_mutates` and `wire-settings.py`'s `permissions.deny` prefix rules. Make the
`--self` drift check byte-for-byte. Turn the `hooks/` Edit rule into an `ask` rule that
matches at any depth. Deny a line that does not tokenize as the seventh opaque shape.
Accept arguments after a scratch script. Make bare entry-point names prompt. Stop denying
`git branch --list <pattern>`. Retire `sweep.sh` and the old git reason. Remove eight
backlog entries.

## Does it do it

Yes, apart from one case in the scratch-argument contract (escalated below). Each
contract checked:

- **One source.** `GIT_ALWAYS_MUTATING`, the flag tuples and `GIT_WORKTREE_SUBCOMMANDS`
  are defined only in `policy.py`. The hook binds `policy.*` by name. `wire-settings.py`
  calls `policy.bash_deny_rules()`. `BASH_DENY_RULES` no longer exists as a literal tuple
  anywhere; the name survives only in prose. Both scripts insert
  `dirname(realpath(__file__))` on `sys.path` and set `dont_write_bytecode` before the
  import.
- **The twins cannot drift.** `self/tests/policy-table.sh` 1a–1d build the expected rules
  from the table itself (`worktree_mutating()`, `GIT_BRANCH_MUTATING_FLAGS`, …), not from
  a retyped list. Test 3 then runs every rendered rule through the hook's own
  `git_mutates`. If you drop the branch line from `denied_git_commands()`, 1a and 1d
  fail. If you drop a flag from the hook's reading, 3 fails.
- **Byte-for-byte under `--self`.** `run_self` compares the file against
  `generated_text(True)`. `hook-wiring.sh` shows that each of these fails the check: an
  added allow rule, a repointed hook command, and a reordered deny list. A write restores
  the exact bytes. Consumer-mode merge is unchanged: the `partial` case keeps its own
  `Edit(/secrets/**)`, and `--check` after the write is `in-sync`.
- **The ask rule is live.** The committed `.claude/settings.json` has
  `ask: [Edit(**/hooks/**), Edit(/hooks/**)]` and no `hooks/` entry under `deny`. The
  vendored spelling is `Edit(**/agentTooling/hooks/**)`. `hooks/README.md` states the
  headless refusal, the `bypassPermissions` limit, and that a consuming repo's old deny
  outranks the new ask.
- **Seventh shape.** `does_not_tokenize` → `UNREADABLE_DENY_REASON` goes through the same
  counter as the other six. Four unbalanced-quote cases moved from NOT_DENIED lists to
  `UNREADABLE_DENY` (NOTES ruling 5), and no other expectation changed. The heredoc and
  `#` guards look at the raw text, so both still prompt.
- **Bare names and `--list`.** `entry_script` requires `os.path.dirname(token)`. The
  `--list`/`-l` exit in `git_mutates` comes after the mutating-flag check, so
  `git branch --list --delete old` is still denied (a `GIT_DENY` case).
- **The reason.** `GIT_DENY_REASON` names LIFECYCLE rule 2, `feature-start.sh` and
  `feature-close.sh` ("from the feature's worktree … BEFORE the merge"). No
  `GIT_REASON_ABSENT` anywhere, and no `sweep.sh` in `hooks/` or the test file.
  `LIFECYCLE.md` already said the same, so it did not need to change.
- **Docs.** The `hooks/README.md` `policy.py` entry carries the Rule 1 constants list and
  the Rule 2 sibling-import dependency. "The git shape", "The deny rules" and "What
  `wire-settings.py` will and won't touch" have been rewritten, and "Editing the policy"
  points at `policy.py`. The root README `hooks/` row, the `self/README.md` gate row and
  design-doc row, and the `self/tests/README.md` entries for all four touched tests are
  updated.
- **Backlog.** The eight named entries are gone. The vendored-settings entry is kept as
  it was. The opaque entry is kept and rewritten to "seven shapes" (NOTES ruling 14).

## Fixed in this pass

1. **`self/tests/allow-repo-commands.sh`: added `./gate.sh` and `./gate.sh 08` to
   `ENTRY_ALLOW`.** NOTES ruling 13 added a root `gate.sh` fixture so that the bare
   `gate.sh` prompt would not pass just because the file was missing. But nothing showed
   the root copy approving with a directory component, as the contract says `gate.sh`
   should ("same for `gate.sh`"). I ran that one test file to check the edit: 26 entry
   cases, all passing.
2. **`self/features/policy-module/NOTES.md`: added a ruling for `self/PROJECT_FACTS.md`.**
   That file changed in the build commit, but neither the design's scope nor the brief
   lists it. The change is a docs-only correction of its drift-check and `py_compile`
   statements. The same bullet notes that the `self/routing/*.json` change comes from the
   `start` commit, not from the build.

## Escalated to round 2

1. **A scratch-script argument that is a relative path outside the project root is
   approved if the path does not exist yet.**
   - **Where:** `hooks/allow-repo-commands.sh`, `scratch_argument_allowed`.
   - **Why:** it delegates to `token_confined` → `value_confined`, which returns True for
     a relative value that "names nothing on disk". That rule is right for readers like
     `cat ../x`, which fail harmlessly. It is wrong for a script's argument, which may
     well be an output path.
   - **What happens:** `bash <scratch>/x.sh ../x` is approved when `../x` is absent and
     prompts only when it exists. The same goes for `bash <scratch>/x.sh --out=../x`.
     The absolute form `bash <scratch>/x.sh /abs/outside/new` does prompt, because
     `inside()` does not care whether the path exists. So which way it goes depends on
     how the path is spelled.
   - **Brief vs tests:** the brief's contract says `bash <scratch>/x.sh ../x` prompts.
     `hook-escalation.sh` has no `../x` case either way.
   - **Severity:** low. The script's body is unchecked, so this does not open a
     capability the body lacks. It does leave a stated contract unmet and untested.
   - **Decision for round 2:** either (a) in `scratch_argument_allowed`, require a
     relative non-flag value (including the value after `=`) to be *lexically* inside
     the root — `normpath(join(cwd, value))` under `root` — whether or not it exists, as
     well as passing `token_confined`; or (b) keep the current rule and record in
     `hooks/README.md` § the scratch entry point that a nonexistent relative path is
     accepted, and why.
   - **Assertions to add to `SCRATCH_PROMPT` in `self/tests/hook-escalation.sh`**, for
     (a): `bash <scratch>/x.sh ../x` with `../x` absent, and
     `bash <scratch>/x.sh --out=../x`, both prompting, beside a `SCRATCH_ALLOW` case
     `bash <scratch>/x.sh new-output.txt` (relative, absent, inside the root).

## Noted, not escalated

- `does_not_tokenize` uses POSIX `shlex`, which has no ANSI-C quoting. So
  `echo $'it\'s'` is valid bash but is denied as unreadable, with a reason telling the
  model to close a quote that is already closed. It is rare, and the deny costs one
  retry. Recorded so nobody has to rediscover it.
- NOTES' open question stands: nothing in this harness can drive the permission system,
  so whether the `ask` rule really prompts under `acceptEdits` and refuses in `claude -p`
  comes from the docs, not a test. The first runner pass that edits `hooks/` will be the
  evidence.

## Files this pass touched

- `self/tests/allow-repo-commands.sh` (two `ENTRY_ALLOW` cases and a comment)
- `self/features/policy-module/NOTES.md` (one deviation bullet)
- `self/review-report.md` (this report)
