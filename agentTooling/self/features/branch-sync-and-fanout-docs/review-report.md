Verdict: clean

# Review — branch-sync-and-fanout-docs

## What the batch was supposed to do

1. Add `feature-sync.sh [--self] <slug>`, a lifecycle script that fetches `origin/<base>` and
   merges it into the started feature's branch with an ordinary merge commit. It refuses a
   dirty tree, a checkout that is not on the feature's branch, and an orchestrator's
   session. On a conflict it leaves the merge in progress and names the conflicted files.
   On any refusal it moves nothing. It also needed a `self/tests/` test and gate wiring,
   plus entries in README, LIFECYCLE rule 2 and PROJECT_FACTS, and its BACKLOG entry had
   to be removed.
2. Close the BACKLOG entry for cloud fan-out by adding the missing points to the "Cloud
   sessions" bullets in `ORCHESTRATION.md`.

## Does it do it

Yes, both items are closed.

- **`feature-sync.sh`** follows the contract:
  - It uses `set -uo pipefail` with no `set -e`, has named constants at the top, and
    sources `plan-runner-roots.sh`.
  - It uses `resolve_roots`, `manifest_field`, `manifest_branch`, `started_features_on`
    and `refuse_orchestrator_session`.
  - Exit codes: 1 for a refusal, 2 for usage, 3 for a conflict.
  - The only thing it moves is the current branch, through `git merge --no-ff`. It has no
    push, reset, rebase, `checkout -B`, `branch -f` or `update-ref`.
  - Every refusal happens before the fetch or the merge.
- **The branch check reads the manifest, not the slug.** The branch comes from
  `manifest_branch`, and the manifest must also be tracked (`started_features_on`).
- **Hook:** `hooks/` is unchanged. The hook already prompts for any program not on its
  read-only entry-point list, so the new script prompts the same way `feature-start.sh`
  and `attach-branch.sh` do. `.claude/` is untouched.
- **Test:** `self/tests/feature-sync.sh` runs offline in a `mktemp -d` and is recorded by
  `self/gate.sh`. It covers the five required behaviours:
  - a clean merge (M1)
  - a dirty tree, tracked or untracked (R1, R2)
  - a checkout not on the feature's branch (R3–R5)
  - a conflict left in progress with the file named (C1)
  - the branch not moving on any refusal (every R case)

  It has an entry in `self/tests/README.md`.
- **Docs:**
  - The root README has a row for the script, LIFECYCLE rule 2 points to it, and
    PROJECT_FACTS lists it under Layout.
  - The `ORCHESTRATION.md` additions stay inside the "Cloud sessions" bullets. They cover:
    steering a child with `send_message`; answering permission prompts in each child's own
    session; merging overlapping features in PR order, with the later one running
    `feature-sync.sh`, renumbering colliding ids, keeping every sibling's fields and
    re-running the gate and review; the ceiling of about five Opus children, with a
    usage-limit stop reported once and children resumed once after the reset; and where
    the parent's own cost is recorded.
  - The cited `self/orchestrations/tooling-wave-2026-11-17/ORCHESTRATOR-STATE.md` exists.
- **BACKLOG:** both entries are removed.
- **Gate:** green, including the README-index check.

## Fixed in this pass

- **`feature-sync.sh`: an in-progress merge was missed when the script ran from anywhere
  other than the checkout root.**
  - The cause: both MERGE_HEAD checks used `[[ -f "$(git -C "$CHECKOUT" rev-parse
    --git-path MERGE_HEAD)" ]]`. In a primary checkout that command returns a path
    relative to the `-C` directory (`.git/MERGE_HEAD`), but `-f` resolves it against the
    script's own working directory.
  - The effect, when run from a subdirectory or with an absolute path from elsewhere:
    - The "merge already in progress" refusal never fired. The dirty-tree check usually
      caught the case anyway, but with the wrong reason.
    - A real conflict came out as exit 1, "git merge refused and left the branch where it
      was", instead of exit 3 with the conflicted files and next commands.
  - The fix: both checks now go through a `merge_in_progress` helper,
    `git -C "$CHECKOUT" rev-parse -q --verify MERGE_HEAD`, which does not depend on the
    working directory.
  - Checked with `bash -n` and one run of `self/tests/feature-sync.sh`: all assertions
    pass.
- **`LIFECYCLE.md` rule 2:** the builder's insertion left one line far over the wrap
  width. I re-wrapped it; the text is unchanged.

## Escalated to the next round

None.

## Non-blocking, for `self/BACKLOG.md`

These do not block: neither is an open item from the spec nor a regression this feature
introduced.

- **No test runs `feature-sync.sh` from outside the checkout root.**
  - Every case in `self/tests/feature-sync.sh` runs from the repo root, which is why the
    MERGE_HEAD bug above stayed green.
  - Missing assertion: run from `<repo>/plans/`, the conflict case exits 3, names the
    file, and a re-run is refused with "already in progress".
- **No test covers being on a named branch that is not the manifest's.**
  - R3 ("on main") is refused by the no-manifest check, because the manifest is not on
    `main`. R4 hits the branch-mismatch refusal, but only through a detached HEAD.
  - Missing assertion: on a second named branch that also carries the manifest, the
    script is refused with "not on '<branches[0]>'" and nothing moves.
