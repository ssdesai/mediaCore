# 01 — review: pull-round-cleanups

Review this feature's diff against what it was supposed to do. "No findings" is a
legitimate verdict: if the diff does what is listed below, holds the contracts, and breaks
nothing, say so and stop.

## What the feature was supposed to do

The spec is the orchestrator's session brief (orchestration `tooling-wave-2026-11-18`),
four items found during the propagation pulls of #169, plus an addendum the orchestrator
ruled on with the owner's go. The acceptance table in `../../README.md` lists them.

1. **The stranded-record classifier must tell an agentTooling-run record from a consumer's
   stranded one.** `analysis/roots.py`'s `is_stranded_record` flagged
   `agentTooling/self/orchestrations/tooling-wave-2026-11-17/` in a consuming repo. That
   record is an agentTooling-run wave whose last fence lists humanNetworkMap features among
   agentTooling ones, and the only remedy offered was a `git mv` into the consumer's
   `plans/orchestrations/`, a local deletion under the consumer's `agentTooling/` (an
   `edited` subtree chain). After the change, a record that lists an agentTooling feature
   is agentTooling's own: no `git mv` from any record tool, `roots.py stranded` exit 1, and a
   start of that slug in the consumer is not refused. A record that lists consumer features
   and no agentTooling one is still stranded, with the `git mv`. Both cases are tested.
2. **Remove the stranded consumer copy `self/orchestrations/readme-structure/`**, but only
   if its fence lists only humanNetworkMap features and nothing in agentTooling reads it;
   otherwise stop and report. The orchestrator has since ruled this item resolved by item 1
   (the premise is untrue; see `../../NOTES.md` §2), so the expected diff removes NOTHING
   under `self/orchestrations/`.
3. **Docs**: in `LIFECYCLE.md` → "Propagate", `README.md` → "Updating" and `ORCHESTRATION.md`
   → "Cloud sessions", say that a cloud pull child's `add_repo` call is refused by the
   session's auto-mode permission check even with the owner's OK relayed by the parent. It
   goes through only when the owner types the OK in the child's own session, or has a
   permission rule for `mcp__claude-code-remote__add_repo`. Say what the parent tells the
   owner. Also: the parent can merge a consumer's propagation PR only if that repo is in its
   own GitHub scope.
4. **Backlog** (`self/BACKLOG.md`): (a) starting without `--branch` when the assigned
   branch is not `claude/<slug>`. Left alone if #169 already filed it, which it did. (b) One
   entry for the three pre-existing silent approvals `cat 'a >/dev/null b'`,
   `cat dir/[^i]*` and ``cat "dir/\`x"``, pointing at
   `self/DESIGN-2026-11-19-hook-allowlist.md` (merged as #170).
5. **Orchestrator addendum (owner's go)**: `self/tests/orchestrator-role.sh` clears the
   caller's `AGENTTOOLING_PROFILE`. A cloud `feature-start.sh` exports `cloud` and runs the
   gate under it, so 21 role checks failed and every cloud start of an agentTooling feature
   was refused. The other self-tests are checked for the same leak, and any that inherit
   the caller's profile or cloud environment get the same treatment. Also a backlog entry:
   the gate report keeps only the last 40 lines of a section and so drops a failing test's
   FAIL lines.

Excluded: fixing the gate report's truncation itself, and any change under `hooks/` (a
sibling feature, `orchestrator-record-move-guard`, owns the hook and its tests this round).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `roots.is_stranded_record(slug)` stays the ONE classifier: `record_refusal`,
  `python3 roots.py stranded <slug>` (exit 0 stranded / 1 not) and `orchestration-start.sh`
  all go through it, and no second copy of the rule appears anywhere.
- The agentTooling name is not a new literal: it comes from the declared self corpus
  identity (`orchestration_home_repo(True)`), compared case-insensitively, the way the
  consumer's name already is.
- Every case `self/tests/orchestration-records-in-repo.sh` R3, R6 and R10 held before still
  holds; the new R12 asserts the mixed wave (not stranded, own-record note, no `git mv`, the
  start not refused, nothing written by a refusal) and a consumer-only record (stranded,
  `git mv`). `analysis/README.md`'s `roots.py` entry and `self/tests/README.md`'s entries
  describe the new rule and R12.
- `self/tests/orchestrator-role.sh` passes with `AGENTTOOLING_PROFILE=cloud` exported, a
  check of that is lasting (it fails if the clearing is removed), and
  its fixtures that pin a profile explicitly (`AGENTTOOLING_PROFILE=cloud`/`local` on the
  child command lines) are unchanged.
- No file under `hooks/` or `.claude/` changes; no other feature's folder changes; nothing
  under `self/orchestrations/` changes.
- The doc text in the three files agrees (same mechanism, same two remedies, same merge
  scope rule) and contradicts nothing nearby, such as the "Permission prompts are answered
  in each child's own session" bullet.
- Each backlog entry is phrased as the assertion that would catch it, names the feature
  that raised it, and the 4(b) entry points at the design document and its §8 build feature.
- The gate is green, `./self/gate.sh`, including with `AGENTTOOLING_PROFILE=cloud`
  exported.

## Verdict
