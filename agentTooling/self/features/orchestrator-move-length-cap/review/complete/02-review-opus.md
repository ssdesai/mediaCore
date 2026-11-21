# 02 — review: orchestrator-move-length-cap

## What the feature was supposed to do

The same three fixes as round 1's brief (`review/complete/01-review-opus.md`), judged against
`OWNER_BRIEF.md`:

1. the hook's line cap on the orchestrator's record move;
2. the `roots.py` go-ahead token;
3. the conformance carry-forward.

There are also three backlog entries. Round 2 reworks only the carry-forward, for round 1's
escalations:

- **Review 1:** a carry lasted one round. The anchor is now the newest earlier round whose
  conformance report said `done`. `feature-close.sh` passes every earlier round
  (`--round <report> <changed>`, newest first), and the evidence from every round since the
  anchor is checked.
- **Review 2:** a dotted identifier counted as a file. Anchors are now only paths tracked at
  the judged head (`--tracked`, from `git ls-tree -r -z`).
- **Audit, blocking 1–5:** the regex path parser missed changed files named by absolute or
  `~` path, as a folder or glob, extensionless, with a digit extension, as a dotfile, with a
  space or non-ASCII, or by a renamed file's old name. Evidence is now matched against the
  changed paths as text: the path in any spelling, its file name, its module stem, a
  `<folder>/` holding it, or a glob matching it. The changed list comes from `git diff -z
  --no-renames`.

Also in round 2:

- `NOTES.md` → "Ruling: owner items the conformance check cannot see". Items 1 and 5 cannot
  be `done` for a check whose diff excludes the feature directory. Item 6's diagnosis is now
  also in `LIFECYCLE.md`. Items 1 and 5 are left for an owner ruling, not changed here.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Everything round 1's brief lists for the hook cap and the go-ahead token, unchanged.
- **`conformance.py check-close [--tracked <f> --round <report> <changed> ...]`.**
  - `--round` without `--tracked` is exit 2.
  - With no `--round`, nothing is carried.
  - An item is carried only when all of these hold:
    - the review says `done`;
    - the newest round marking it `done` names a tracked path in its evidence;
    - no evidence for it, from that round through the current one, is "about" a path in
      that round's changed list.
  - Path lists are read NUL-separated, or newline-separated when the file has no NUL.
- **`feature-close.sh`.**
  - Reads each `<slug>: review round K` commit for K = N−1 down to 1, skipping any with no
    commit or report.
  - Lists the changes from `K^` to the judged head with `-z --no-renames`, the feature
    directory excluded.
  - Passes `--tracked` only when at least one round is passed.
- **`self/tests/brief-conformance.sh` must pass.**
  - V1a–k cover the audit's C2–C10, C17 and C19, and the review's identifier and walk-back
    cases.
  - V2a/V2c/V2b test the real close: V2c is the repeated flip, still carried.
  - K2 and D1 are renumbered to rounds 12 and 13.
- **Docs.** `LIFECYCLE.md` step 5 item 3 (rule and diagnosis), `README.md`'s `conformance.py`
  row and `self/tests/README.md` describe the new interface.

"No findings" is a legitimate verdict.

## Verdict
