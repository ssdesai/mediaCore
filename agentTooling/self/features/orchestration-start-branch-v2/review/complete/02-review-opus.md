# 02 — review: orchestration-start-branch-v2 (round 2)

Review the whole diff against the spec below, and in particular the round-2 rework of the
two round-1 escalations (`../../escalations/01-review-opus.md`,
`../../escalations/01-audit-opus.md`). "No findings" is a legitimate verdict. A finding blocks
only when an item below is not closed or the diff introduces a regression; anything else is
filed in `self/BACKLOG.md` as non-blocking.

## What the feature was supposed to do

1. **`orchestration-start.sh --branch claude/<slug>`.** Under the cloud profile, for an
   orchestrator record (not `--coordinator`): refused on a detached HEAD or `main` without
   `--branch`, naming `--branch claude/<slug>`, writing nothing; with `--branch <name>`, cuts
   `<name>` off `origin/main` before any write, writes the record and ledger line, commits the
   record on that branch. Existence is asked of origin (`git ls-remote --exit-code --heads
   origin refs/heads/<name>`: 0 refuses, 2 goes on, other refuses "cannot ask origin"); a
   local branch of that name refuses; a branch a tracked manifest on `origin/main` names
   refuses; manifests are enumerated NUL-separated, `held_feature` included; the unmerged-
   branches decision is in `NOTES.md`; the brief template and `ORCHESTRATION.md` use the flag.
   Excluded: the experiment driver's same gap; the local profile's behaviour.

2. **The orchestrator may move its own stranded record.** The remedy
   `shared_rules.LEGACY_RECORD_REFUSAL` prints, `mkdir -p plans/orchestrations && git mv
   agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>` (round 2: the `mkdir`
   lead, since git tracks no empty directory), naming the session's OWN record, from the
   consuming repo's root, is approved and works; so is the bare `git mv` when the folder
   exists. Any other move or `mkdir` — another record, file, destination, option, extra word,
   cwd, a standalone checkout, a symlinked `plans` or `plans/orchestrations`, a record README
   that is a symlink — is not approved.
   Excluded: parts 2–4 of the backlog's orchestrator-role gaps.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Round 1's contracts (`01-review-opus.md` beside this file, under `review/`).
- `hooks/shared_rules.py`: `LEGACY_RECORD_MKDIR` and the new `LEGACY_RECORD_MOVE` are the
  one definition; `self/tests/shared-rules.sh` pins both; `roots.py` and the start print the
  same text.
- `hooks/allow-repo-commands.sh`: `orchestrator_record_move` never resolves the record path,
  refuses any symlink on it or on the destination's parents; `orchestrator_moves_own_record`
  admits only the bare move or exactly `LEGACY_RECORD_MKDIR && ` before it;
  `orchestrator_command_allowed` admits `mkdir` nowhere else.
- H28 in `self/tests/hook-orchestrator-role.sh` asserts the approved remedy with `plans/`
  absent and that it really moves a committed record, and the symlink and near-miss denials.
- `./self/gate.sh` green.

## Verdict
