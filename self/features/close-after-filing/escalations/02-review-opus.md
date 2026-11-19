Verdict: escalated

# Review — close-after-filing, round 2

## What this round was supposed to do

Round 1's security audit escalated on B1: a `<slug>: backlog` commit could add a file named
`self/BACKLOG.md<LF>` and still pass, because `$(…)` stripped the trailing newline before the
name list was compared. This round:

- moves both post-review checks into one helper, `commit_changes_only <sha> <path>` in
  `feature-close.sh`. The `: backlog` case and the `: review stamps` case both use it. The
  helper requires one parent, turns renames off, reads the names NUL-separated, and adds a
  sentinel after the list so nothing trailing gets stripped.
- adds tests K11 (`self/BACKLOG.md<LF>`, and an executable `self/BACKLOG.md<LF><LF>`) and K12
  (`timing.jsonl<LF>` under `S: review stamps`).
- tightens K5 so it checks that the refusal names the allowed path.
- updates the docs: NOTES.md and `self/tests/README.md`.

## Does it do it

Yes, for B1:

- **The sentinel comparison is exact.** For one changed name `p`, the substitution produces
  `p\n.`. Any of these breaks the equality, and the substitution can no longer strip a
  trailing character:
  - a trailing or embedded newline in the name;
  - a second name;
  - an empty diff;
  - a failed `git diff`.
- **It works in bash 3.2.** No `mapfile -d` is used.
- **The stamps commit is not refused.** `run-review.sh`'s own stamps commit still closes:
  `feature-lifecycle.sh` and `security-audit.sh` pass in the gate.
- **The tests pass.** `close-backlog.sh` passes in full, including K1/K2/K9, K5a/b with the
  stronger assertion, K11a/b and K12.
- **Constants are named:** `SINGLE_PARENT_WORDS` and `NAME_LIST_SENTINEL`.

**Gate:** everything passes except `pricing rate history is current` (exit 1). That check
depends on the date and on the rate table. This diff touches neither, so it does not count
against this feature.

## Fixed in this pass

- `self/features/close-after-filing/NOTES.md:45` still used the old constant name
  `BACKLOG_SINGLE_PARENT_WORDS`, which this round renamed to `SINGLE_PARENT_WORDS`. I updated
  the line.

## Escalated to the next round

**E1. A hidden submodule change still gets past `commit_changes_only`.**

- **What fails:** the contract says "no second name rides along". With submodule diffs
  suppressed, a second name does ride along.
- **Where:** `feature-close.sh:150`.
- **Who found it:** this round's security audit (`self/features/close-after-filing/audit-report.md`,
  B2, cases C18/S1/S2). I confirmed the cause by reading the code.
- **Why:** `git diff` is porcelain. It follows `submodule.<name>.ignore` from the worktree's
  `.gitmodules` and `diff.ignoreSubmodules` from config, even when it compares two commits.
  So a commit can add a gitlink beside the BACKLOG and still list only `self/BACKLOG.md`. An
  uncommitted `.gitmodules` with `ignore = all`, listed in `.git/info/exclude`, is enough, and
  the stray check does not see it.
- **Impact:** the base branch refuses this commit; this branch accepts it, so this is a
  regression. The `: review stamps` case has the same gap (audit S4), but the base already
  allowed that one.
- **Fix:**
  - Add `--ignore-submodules=none` to that `git diff`. The audit checked this flag on a
    patched copy (T1). Another option is plumbing that reads no submodule or diff config,
    such as `git diff-tree -r --no-renames --name-only -z`; that needs the same test before
    anyone relies on it.
  - Add a K13 to `self/tests/close-backlog.sh`: a `feat: backlog` commit that has a gitlink
    `sub` beside the BACKLOG, with an excluded worktree `.gitmodules` that sets
    `ignore = all`, must be refused.
  - Add the same case under `feat: review stamps`.
  - Record the ruling in NOTES.md and list K13 in `self/tests/README.md`.
- **Why I did not apply it here:** it is a one-flag change, but it changes a security rule
  and needs a new test case. The audit has already escalated this round, so the fix belongs
  in that round's build plan, with the next audit checking it.

## Non-blocking notes

- **Stamps commit file mode (audit C24).** `: review stamps` does not check the file mode, so
  a stamps commit can make `timing.jsonl` executable. This was already allowed before this
  feature. The next round could add the `100644` check that `: backlog` already has, or file
  it in `self/BACKLOG.md`.
- **Unverified issue reference.** NOTES.md says round 1's other two non-blocking notes "are
  filed on #153". I did not check that from this pass.
