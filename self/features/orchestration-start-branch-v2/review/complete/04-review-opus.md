# 04 — review: orchestration-start-branch-v2 (round 4, the last)

Scope (owner ruling 2026-11-19): the merge of `origin/main` (#168, `hook-silent-allow-sweep`,
2108a449) into this branch, and round 4's fix of round 3's audit escalation
(`../../escalations/03-audit-opus.md`). The rest of the diff passed rounds 1–3's reviews; read
it only as far as the merge or the fix touches it. "No findings" is a legitimate verdict. A
finding blocks only when the fix does not close the escalation or the merge or the fix
introduces a regression; anything else is filed in `self/BACKLOG.md` as non-blocking.

## What the feature was supposed to do

- **The fix:** `orchestration-start.sh --branch` accepts only `claude/<slug>`, `<slug>`
  matching the shared `SLUG_PATTERN` (`^[a-z0-9]+(-[a-z0-9]+)*$`), and refuses anything else
  before any write, the refusal naming `--branch claude/<slug>`. It replaces round 3's
  plain-name check (spellings patched one at a time). Round 3's explicit
  `refs/heads/<b>:refs/heads/<b>` push in `plan-runner-roots.sh` stays.
- **The merge:** a normal merge (no rebase, no force-push) keeping both features'
  behaviour: #168's changes to `hooks/allow-repo-commands.sh` and its tests, and this
  feature's orchestrator record move (`orchestrator_record_move`,
  `orchestrator_moves_own_record`, the `ORCHESTRATOR_MOVE_*` constants, H28). The one
  conflict was in `self/BACKLOG.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. For the merge, also `git show --stat HEAD` history: the merge commit
`orchestration-start-branch-v2: merge origin/main (hook-silent-allow-sweep, #168)`.

## Contracts to hold it to

- `self/tests/orchestrator-role.sh` B7: `origin/main`, `origin/HEAD`, `origin/claude/x`,
  `+main`, `main`, `claude/Bad_Name` (and the round-2 spellings) are each refused, naming the
  flag, with nothing written and origin's and the checkout's refs unchanged; B2–B6 still cut
  and push a `claude/<slug>` branch.
- `self/tests/hook-orchestrator-role.sh` (H28 and #168's own checks) green on the merged hook.
- Docs describing `--branch`: `orchestration-start.sh`'s header, `ORCHESTRATION.md` →
  "Cloud sessions", `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`, `self/tests/README.md`,
  the feature's `NOTES.md`.
- `./self/gate.sh` green.

## Verdict
