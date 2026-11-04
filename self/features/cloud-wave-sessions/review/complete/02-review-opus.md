# 02 — review: cloud-wave-sessions (round 2)

"No findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix local
findings in the pass; escalate structural ones.

## What the feature was supposed to do

Unchanged from round 1 (`review/complete/01-review-opus.md`): document the cloud-session
coordinator shape in `ORCHESTRATION.md` → "Cloud sessions" (assign `outcome_branch`
`claude/<slug>`, a self-contained brief, the child coordinates its own feature, the parent
is an unpinned router that checks in with `get_session`/`list_events` and archives children
once their PR is open), cross-reference it from `LIFECYCLE.md` → Propagate step 4 and the
design doc, and make `feature-start.sh`'s cloud refusal on the base or a detached HEAD
name `--branch claude/<slug>`, tested in `self/tests/cloud-start.sh` (B1d, B2a–c).

Round 1 was clean. Round 2 exists because `origin/main` moved under the feature: PRs #91
(`cloud-branch-window-from`), #93 and #94 merged, and this branch merged `origin/main`
(a merge commit, no rebase). #91 changed what round 1's docs were written against. Under
the old start, a cloud session that cut its branch with `--branch` from the base or a
detached HEAD was a **router** and the start's "Next" lines said to pin it; round 1's text
said a cloud child "pins itself". Under #91, **every** cloud start's session is the
feature's **coordinator**, the `--branch` case included: `from` at its first transcript
instant, no pin, no routing record (`self/features/cloud-branch-window-from/`, `LIFECYCLE.md`
step 2 and `ORCHESTRATION.md` → "A session launched on the feature's branch is its
coordinator, wherever it runs"). The merge resolved four textual conflicts and rewrote
this feature's text to #91's semantics:

- `README.md`, the `feature-start.sh` row: main's coordinator wording, plus this branch's
  clause that the cloud refusal names `--branch claude/<slug>`;
- `self/DESIGN-2026-10-05-cloud-execution.md` §10: main's **Superseded** note kept, and this
  branch's observation now says a wave's child "is the coordinator all the same"; §12 says
  each child is its own feature's coordinator;
- `templates/plans/features/TEMPLATE.md`, the `sessions` bullet: main's wording, this
  branch's "is a router and pins itself" parenthetical dropped;
- `ORCHESTRATION.md` ~line 59: #94's `add_repo` sentence and this branch's cloud-sessions
  sentence both kept; "Cloud sessions" third bullet rewritten to "the start cuts the branch
  and the child is the feature's coordinator all the same", keeping "the brief always
  passes `--branch <outcome_branch>`";
- `LIFECYCLE.md` Propagate step 4, the cloud-child bullet: "pins itself when the start's
  Next lines say so" replaced with "is that feature's coordinator, with no pin";
- the fence `README.md`: the pin finding is recorded as true under the old start and
  superseded by #91; the session pin in the fence stays as the record of what happened.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. The round-2 change on its own is
the merge commit against its first parent, round 1's `cost records` commit:
`git diff HEAD^1 HEAD`.

## Contracts to hold it to

- **No text this feature ships states the old semantics.** Nowhere in the diff against
  `origin/main` does a cloud session that starts with `--branch` get called a router, told
  to pin itself, or said to have a routing record — except as history, explicitly marked
  as superseded, inside `self/features/cloud-wave-sessions/` (its README and round 1's
  brief). The round-1 brief and report are the record of round 1 and are not to be edited.
- **No text in the merged tree states the rule two ways.** `ORCHESTRATION.md` → "Cloud
  sessions", `ORCHESTRATION.md`'s "A session launched on the feature's branch is its
  coordinator" paragraph, `LIFECYCLE.md` step 2 and Propagate step 4, the design doc's §3,
  §10 and §12, the root `README.md`'s `feature-start.sh` row and the manifest template's
  `sessions` bullet all say the same thing about a cloud `--branch` start.
- **Every claim about `feature-start.sh` matches the script on the merged tree**: what the
  cloud refusal says (the `--branch` flag, `--branch claude/<slug>` with the real slug, "a
  detached HEAD" rather than "the base" when HEAD is detached), that `--branch X` while on
  `X` is accepted, and that a `--branch` start from the base or a detached HEAD writes no
  routing record, pins nothing and prints no advice to pin (its "Next" lines).
- **The merge carries nothing but this feature's own change.** `git diff origin/main...HEAD
  --stat` names only: `LIFECYCLE.md`, `ORCHESTRATION.md`, `README.md`, `feature-start.sh`,
  `self/DESIGN-2026-10-05-cloud-execution.md`, `self/tests/README.md`,
  `self/tests/cloud-start.sh`, and files under `self/features/cloud-wave-sessions/`. In
  particular `templates/plans/features/TEMPLATE.md` is unchanged against `origin/main`.
- **`self/tests/cloud-start.sh` holds #91's N1–N4 and this feature's B1d and B2a–c in one
  file for the first time.** No assertion in it encodes the router/pin behaviour; B1d and
  B2a–c still assert the conventional-branch name and "a detached HEAD". Do not re-run it:
  the coordinator ran it and `./self/gate.sh` on the merged tree and both passed.
- `CLOUD_BRANCH_PREFIX` is still a named constant in `feature-start.sh` and in the test
  (CONVENTIONS.md → Named constants).
- No `sleep` or polling loop is recommended anywhere, and no claim about the MCP tools
  (`create_session`'s `outcome_branch`, `get_session`'s `status_bucket`, `list_events`'
  `kinds`, `archive_session`, `send_later`) is invented.
- READMEs touched where their content changed: the root `README.md` row, `self/tests/README.md`.

## Verdict

The first line of the review report the runner names: `Verdict: clean` or
`Verdict: escalated`.
