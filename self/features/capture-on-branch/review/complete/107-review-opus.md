# 107 — review: capture-on-branch

Written before the build, from `self/DESIGN-2026-09-16-lifecycle-restructure.md` (§2,
§3.2, §3.3, §3.6, §4, §5), never from the implementer's report. "No findings" is a
legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix local drift in this pass;
anything structural is an escalation in the verdict, not a rewrite.

Two files are **escalate-only** in this pass, never edited by it: anything under `hooks/`
(the policy denies the edit), and `run-review.sh` itself — this pass is being driven by
the worktree's copy of that script, and bash reads a running script incrementally, so an
in-place edit shifts the driver mid-run. The same holds for `feature-capture.sh`, which
this pass's own runner calls after `pr.sh`.

## What the feature was supposed to do

The second of three lifecycle-restructure features. The first (merged, PR #44) stopped
pinning routers and made `feature-start.sh` prune merged worktrees. This one makes the
cost capture happen **on the feature branch, before the merge**, triggered by the review
pass, so that merging the PR is the last step of a feature and there is no manual close.

1. **Rename.** `feature-close.sh` → `feature-capture.sh`. The name `feature-close.sh` is
   referenced from consuming repos' docs and habits: it survives as a thin shim that says
   close is now automatic and forwards to `feature-capture.sh` (or refuses with that
   message) — the implementer's call, recorded in `NOTES.md`. No logic lives in the shim.
2. **Runs in the worktree, on the branch.** Design §3.2, in order: stamp `to` from
   evidence (`capture_planning.py --last-branch-instant`; pre-merge it may move **either
   way**, so a re-run after more work moves it later) → `recover_attempts.py --for
   <slug>` → capture → report → refresh the routing record of the router that started
   this slug (found by scanning the routing directory for the slug; no fence field) →
   commit the cost records on the branch (`COST_FILES` + usage sidecars + that routing
   record) → push the branch. Re-runnable by hand from the worktree; a second run replaces
   the first record.
3. **Removed from the old close:** the primary-clean-and-on-`main` refusal, `pull main`,
   the push to `main`, the "worktree's copy is the wrong copy" refusal (and the matching
   git-dir ≠ common-dir guard in `capture_planning.py`), the timing carry-home, the
   worktree and branch teardown (the prune in `feature-start.sh` owns that now), and the
   unpinned-delegate **refusal**, which becomes a **warning** for a delegate whose brief
   names this slug and that neither route claims.
4. **The legacy path.** `--recapture` stays for features captured under the old rule:
   tighten-only `to` (`manifest.py set-window-to --tighten`), writes locally, **pushes
   nothing**, and says the human opens a PR for the repair. A feature that merged under
   the old flow and was never closed must still be capturable from the primary after the
   merge the same way (writes locally, pushes nothing) — consuming repos have such
   features in flight today.
5. **`run-review.sh` triggers it**, on a clean pass, in exactly this order: `pr.sh` →
   `pr_opened` stamp → `pass_end` stamp → capture → commit → push. The trailing stamps
   therefore ride the capture commit, and `pass_end` must not be stamped a second time by
   the EXIT trap on that path. A capture failure is advisory, like `pr.sh`'s: reported with
   the exact re-run command, never unwinding a review that succeeded.
6. **`pr.sh`** (`templates/plans/pr.sh` and `self/pr.sh`): either its commit is deferred
   to the capture or two commits are accepted — the implementer's call, in `NOTES.md`.
   Adds an opt-in `PR_AUTO_MERGE` (off by default in the template; `self/pr.sh` off
   regardless, with the reason — agentTooling ships to every consumer) that runs `gh pr
   merge --auto` after a clean review. Body change → `template-version` bumped in both
   copies, `TEMPLATE_VERSIONS` re-recorded, and the consumer hand-merge named where
   `sync-plans.sh`'s report and the root README "Updating" section would tell a consumer.
7. **Docs (§3.6, close-side).** `LIFECYCLE.md`: step 5 "Review and PR" says it captures;
   step 6 "Close" becomes "Merge", on the forge, nothing to run after; rule 2's
   "`feature-close.sh` the only way out" and rule 3's "`feature-close.sh` closes the
   window" rewritten (`to` is provisional until merge); retire "after every session that
   cost it has ended". Step 7 (sweep) is the next feature's and stays. Plus: root
   `README.md` rows, `AGENT_DIRECT.md` (close step → merge), `ORCHESTRATION.md` wherever
   it tells a coordinator to close, `RUNNER.md` where it describes the review pass's tail,
   `analysis/README.md` "Where to run them" (the worktree copy is now the right copy),
   `templates/plans/features/TEMPLATE.md` fence prose (`to` stamped by capture, not
   close), `self/PROJECT_FACTS.md` → Commands, `self/README.md`, `self/tests/README.md`,
   and `feature-start.sh`'s printed "Next" step 4.
8. **Tests (§4).** `self/tests/feature-lifecycle.sh` rewritten for the new flow against its
   bare remote; a capture-from-worktree fixture test.

Not in this feature: `sweep.sh` retirement, `report.py --all` filling missing reports,
the `check-plans.sh` window lints, `run-batch.sh`'s inferred-slug lint, `RUNNER.md`'s
$5→$7 review cap (all design §3.5/§3.8, the next feature's). A change there needs a reason
in `NOTES.md`. The open items (per-feature budget, `git stash list`) are not built.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect changes in
`feature-close.sh` → `feature-capture.sh` (+ shim), `run-review.sh`,
`analysis/capture_planning.py` (guard lifted), possibly `analysis/routing.py` (refresh
by slug), `templates/plans/pr.sh`, `self/pr.sh`, `TEMPLATE_VERSIONS`, `feature-start.sh`
(printed Next only), `self/tests/`, and the docs above.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **Capture on the branch commits and pushes the branch, never `main`.** In
  `feature-lifecycle.sh` against the bare remote: after start → a commit of work → capture
  from the worktree, the branch head on the remote contains `planning.json`, `report.*`,
  the manifest with `to` set, and `timing.jsonl`; the remote's `main` ref is unchanged
  (compare refs before/after); the worktree is clean and still present.
- **A second capture replaces the first.** More work after the first capture (a later
  transcript instant in the fixture) → a second capture moves `to` **later** and rewrites
  `planning.json`; no refusal about a frozen prior record on the branch.
- **The review pass's tail order.** With stub `claude`, stub gate and a stub `pr.sh` that
  records its call: a clean `run-review.sh --self <slug>` ends with `pr_opened` then
  `pass_end` in the committed `timing.jsonl` (exactly one `pass_end` for that pass), a
  capture commit on the branch after the `pr.sh` commit, and a clean worktree. A failing
  capture leaves the review pass's exit status as it was and prints the re-run command.
- **Merge then next start prunes.** Merge the branch into the remote's `main`, start
  another feature: the first worktree and its local branch are gone; nothing was pushed by
  the start.
- **`--recapture` post-merge refuses to widen and pushes nothing.** A later bound is
  refused (manifest `to` unchanged), an earlier one tightens; the remote's refs are
  byte-identical before and after.
- **Legacy merged-never-closed feature** captures from the primary post-merge, locally,
  with no push.
- **The worktree copy selects the worktree's sessions.** Fixture dirs under a fake
  `$HOME/.claude/projects`: sessions filed under
  `-…-agentTooling--worktrees-<slug>` and their delegates are captured; a session in the
  primary's dir on `main` is not (unless pinned); `capture_planning.py` run from the
  worktree no longer refuses.
- **Unpinned delegate is a warning.** A delegate transcript whose brief opens
  `feature: <repo>/<slug>` and that is neither pinned nor under the branch → capture
  succeeds and prints a warning naming its id and how to pin it.
- **Routing record refresh.** A routing file naming the slug in `features_started` is
  rewritten by the capture and included in the capture commit; with no such file the
  capture says nothing about routing and does not fail.
- **The shim.** `feature-close.sh` carries no logic of its own; its behaviour is one
  asserted case.
- **`pr.sh`**: `PR_AUTO_MERGE` unset → no `gh pr merge` call (stub `gh` records calls);
  set to `1` in the template → exactly one `gh pr merge --auto` call; `self/pr.sh` never
  calls it. `self/tests/template-versions.sh` and `sync-check.sh` pass.
- **No stale references.** `grep -rn "feature-close"` over the tree finds only the shim,
  its test, `NOTES.md`/`BACKLOG.md`, the design record, and historical feature corpora
  under `self/features/` (which are records and are not rewritten).
- **Named constants** for every new path, message prefix, flag and env var name; bash 3.2;
  `set -uo pipefail` and no `set -e`; no chained `cd` anywhere in the diff, fixtures
  included; every python run with `-B`.
- **README Rule 2** on `run-review.sh`'s and `feature-capture.sh`'s README rows: the
  contract that capture runs from the worktree after `pr.sh`, and that `pass_end` is
  stamped before capture.
- **Every item of the list above** is present or named in `NOTES.md` as a deliberate
  exclusion with a `self/BACKLOG.md` entry.

## Verdict

Write it as the PR body will read it: what the diff does, each contract above as
holds / fixed here / escalated, and the files touched by this pass.
