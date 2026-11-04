# Notes: cloud-branch-window-from

Built by hand by the coordinator. The investigation, the rulings, and the red proof.

## The reproduction (from the code, and from this session)

`feature-start.sh` set `COORDINATOR=1` only when `LAUNCH_BRANCH == FEATURE_BRANCH`. A cloud
start via `--branch` from `main` (`LAUNCH_BRANCH=main`) or a detached HEAD
(`LAUNCH_BRANCH=""`) therefore took the router path:

- `session_window.from` = `NOW`, read **after** the base gate. That is later than the
  session's first line, and later than the stretch the gate ran on the new branch.
- a `routing.json` was written for the session;
- "Next" step 2 told it to `pin-session` itself.

The capture (`capture_planning.py`, `select_parent`) selects a branch-matched session
when `in_window(start_ts, window)` holds, where `start_ts` is the session's **first**
line. Branch matching is by any line's `gitBranch` (`branches_seen & branches`), so a
session that opens on `main` does match. The two symptoms follow from that:

- **musicMap** did not pin. `start_ts < from`, so the session was rejected outright
  (only the "may span the window boundary" warning). `set-window-from` by hand was the
  only fix.
- **humanNetworkMap** pinned, as told. A pin is always selected, but the sole-claimant
  cut (`pin_is_cut`, from `cost-capture-collisions`) walks a pinned session through the
  split whenever it outruns its window. Everything before the clock-stamped `from` (the
  investigation before the start, and the start and its gate) went to the unclaimed
  remainder: the $0.52.

This very session reproduced it live. It was spawned detached at `main` with no local
`claude/cloud-branch-window-from`, so it had to start with `--branch`. The pre-fix start
printed `routing … (router cc0fce2a…, not pinned)`, `from 2026-10-26T16:49:33Z` (the
clock), and the pin-session advice.

## Rulings

1. **Yes: a cloud start via `--branch` from main or a detached HEAD is meant to make the
   session the coordinator.** The router concept exists because a local session in the
   primary opens several features and belongs to none of them. In a container that
   cannot happen: the start refuses a second feature (one branch, one feature), so the
   session that runs it routes to exactly one feature and has no other session to hand it
   to. The old ruling (design 2026-10-05, "A cloud session that starts with `--branch`
   from the base is a router … it must pin itself") predates the interaction with the
   sole-claimant cut, and following its own advice loses the head. That makes it a bug,
   not intended behaviour. The design record now carries a "Superseded" note.
2. **The rule is `profile_is_cloud ⇒ COORDINATOR=1`**, not a second comparison of launch
   branches. In the cloud it holds for every start, the assigned-branch case included,
   so the router-or-coordinator question is answered by the profile adapter that already
   decides the layout. The lock's `launched_on` is still written and read; it now only
   names the launch branch in the `routing` line.
3. **The pre-branch stretch is claimable, by window and with no pin.** Its lines carry
   `gitBranch: main` (or `HEAD`), but selection is per session: it matches by its later
   lines and is selected by its first instant once `from` is there. A sole claimant is
   billed whole, so the head is included. No capture change was needed. N1e proves it:
   `selected_by: branch`, `unclaimed_usd` 0.
4. **No pin, even though one would now be harmless.** With `from` at the first instant a
   pin would not be cut, but one owner per session and the branch claim are enough. A pin
   only adds a second spelling of the same claim. `--pin` is still honoured if asked.
5. **The local profile is untouched.** A local start from the primary is on `main`, the
   branch is the slug, and the session is a router exactly as before (P1, and
   `feature-lifecycle.sh`).
6. **This feature's own record was corrected by hand, once**, because the start that
   opened it was the pre-fix code. `set-window-from "$(manifest.py session-start <id>)"`
   moved `from` 16:49:33Z → 16:40:30.102Z, and the routing record the start wrote was
   removed (`git rm`). That is the hand step the fix removes for every later start.

## Red proof

`bash self/tests/cloud-start.sh` before the `feature-start.sh` change (tests rewritten
first):

    FAIL  N1c. ... and the session, launched on main, is the coordinator: no routing record, no pin, no advice to pin
    FAIL  N1d. ... its window opens at its first instant, on main before the branch existed (…14:50:17.500Z; got …16:50:17Z)
    FAIL  N1e. a capture selects it by branch and bills it whole: nothing unclaimed, the head included (got 1)
    FAIL  N2.  a refused --branch start re-run from its branch is still the coordinator, from its first instant
    FAIL  N4.  --branch from a detached HEAD: the coordinator, from its first instant, no routing record
    cloud-start: 5 assertion(s) FAILED

After: `cloud-start: all assertions passed`.
