# bundle-store-direct

The `direct` arm of the F1 (`mediacore.store`) run of humanNetworkMap's
`plans/experiments/wp7-bundle-store/`. One Opus delegate implemented `INTEGRATION.md`
§5.1 from the shared brief, ran `plans/gate.sh` itself and opened the PR — no plans, no
`run-batch.sh`. That is the only difference from the `bundle-store-plans` arm, which
builds the same brief through the delegated-plan harness.

- Worktree `~/dev/mediaCore-direct`, branch `bundleStoreDirect`, off `f47d670` (the prep
  commit: §5.1/§13 amendment from PR #6 plus the subagent-capture pull — none of the feature).
- Gate rehearsed green in this worktree before the run, so a red gate during it would
  have been the delegate's change and not the environment.
- Delivered as PR #8, marked do-not-merge until the experiment picks a winner.

## Plans

None. `plans: []` is the arm, not an omission: it measures what a feature costs when
nobody authors plans for it.

## Cost bookkeeping

This manifest exists to claim **one** thing — the delegate's transcript. It is pinned by
id because a subagent inherits its parent's `gitBranch` and `cwd` at spawn: the
coordinator ran from humanNetworkMap's root on `main`, so the delegate is filed under
*that* repo's project directory and no branch or window in this repo can reach it.
`find_pinned_elsewhere` honours the pin across repos and records it as `cross_repo`.

- The **coordinator's own** context cost is charged separately, by
  `plans/features/bundle-store-direct-coordinator/` in humanNetworkMap (checklist → E,
  "coordinator session"). That manifest carries `exclude_subagents` naming this
  delegate, so the two claims do not overlap and the claims ledger stays consistent.
- Expect one warning on capture: `branch 'bundleStoreDirect' matched no session in any
  transcript for this repo`. It is correct and not actionable — no session ever recorded
  that branch, because the only agent that worked on it was a subagent carrying `main`.
  The name is declared anyway because it is where the code is.

## Deliberately excluded

- F2–F5: the consumer inbox endpoints (`…/imports/release/inbox`,
  `…/preview-from-store`) and `vinylcat export-release --store`. They live in other
  repos and build *against* this seam once the winning F1 arm merges.
- The experiment's checklist and `score_b.py` were withheld from the delegate, and
  `plans/experiments/**` and the other arm's worktree were forbidden to it, so the arm
  cannot have optimised to the grader.

## Machine-readable

```json
{
  "slug": "bundle-store-direct",
  "plans": ["12-review-opus"],
  "branches": ["bundleStoreDirect"],
  "session_window": {"from": "2026-08-27T21:48:00Z", "to": "2026-08-27T22:07:00Z"},
  "exclude_sessions": [],
  "subagents": ["a8de4a2fdd869ce6e"]
}
```
