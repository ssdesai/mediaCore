# 01 — review: cloud-branch-window-from

feature: agentTooling/cloud-branch-window-from

## What the feature was supposed to do

A Claude Code cloud session with no assigned branch starts on `main` or a detached HEAD.
It runs `feature-start.sh --self <slug> --branch <name>`, which cuts the branch off
`origin/main`. Before this feature, the start treated such a session as a **router**:
`session_window.from` at the post-gate clock, a `routing.json`, and "Next" advice to
`pin-session` itself. In the field that caused two problems:
- an unpinned session was not selected by the capture (its start was before `from`) until
  someone ran `set-window-from` by hand;
- a pinned one was cut to the clock-stamped window, so its opening stretch was claimed by
  no feature.

The spec asked whether such a session is meant to be the coordinator. If yes: fix it with
a failing test first in `self/tests/`, make claiming the pre-branch stretch automatic,
and record the rulings in `NOTES.md`. If no: document the behaviour in LIFECYCLE.md
step 2. The ruling taken is **yes**: in the cloud, the session running the start is
always the coordinator, with `from` at its first transcript instant, no routing record
and no pin. The local profile is unchanged.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

Expect: `feature-start.sh`, `self/tests/cloud-start.sh`, `self/tests/README.md`,
`LIFECYCLE.md`, `ORCHESTRATION.md`, `self/DESIGN-2026-10-05-cloud-execution.md`,
`templates/plans/features/TEMPLATE.md`, and this feature's directory. The removal of this
feature's own `routing.json` and its moved `from` are deliberate (NOTES.md ruling 6).

## Contracts to hold it to

1. Under the cloud profile, a start from `main`, from a detached HEAD, and a resumed
   start that was launched on `main` all write **no** `routing.json` and pin nothing.
   Their `from` is exactly `manifest.py session-start <id>`, and the "Next" output never
   tells the session to `pin-session`. Check `self/tests/cloud-start.sh` N1, N2 and N4
   actually assert each of these, and would fail against the old `COORDINATOR` line.
2. A capture of such a feature selects the session `by branch` and bills it whole,
   including transcript lines whose `gitBranch` is `main` or `HEAD`: N1e. Confirm against
   `analysis/capture_planning.py` (`select_parent`, `session_claim_intervals`) that this
   holds generally and is not an artefact of the two-line fixture. For example, is there
   any path where a `main`-branch line makes another feature a co-claimant, or makes the
   session's selection depend on its first line's branch?
3. The local profile is byte-for-byte unchanged in behaviour: a start from the primary on
   `main` is still a router with a routing record (`cloud-start.sh` P1,
   `feature-lifecycle.sh`). The no-transcript case still falls back to the clock with one
   warning (A5).
4. The docs say one thing. LIFECYCLE.md step 2, ORCHESTRATION.md, the design record's
   superseded note, the `feature-start.sh` header and comments, the template's `sessions`
   bullet, and `self/tests/README.md`'s N1–N4 entry all agree with the code. No remaining
   doc or comment says a cloud `--branch` session is a router or must pin itself.
5. `./self/gate.sh` is green; read `self/gate-report.txt`.

"No findings" is a legitimate verdict. Escalate only for a defect against the contracts
above or a real regression, not for style.

## Verdict

Write `self/review-report.md` with `Verdict: clean` or `Verdict: escalated` as its first
line, then the findings.
