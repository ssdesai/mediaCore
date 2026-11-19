# 03 — review: own-push-credential-keys

Re-review this feature against its spec, which is the coordinator's rulings in
`self/features/own-push-credential-keys/NOTES.md` → "Coordinator rulings", rulings 1-9.
Do not use the builder's report as the spec. "No findings" is a legitimate verdict.

## What the feature was supposed to do

The spec is unchanged from round 2 (`review/complete/02-review-opus.md`). In the cloud
profile, `git push [-u] origin <own-branch>` prompts instead of approving silently when any
of these holds:
- `credential.helper`, any `credential.<sub>.helper` (the empty subsection included) or
  `core.askPass` is in the effective config;
- `GIT_ASKPASS` or `SSH_ASKPASS` is set non-empty in the hook's environment.

Round 3 makes **no code change** to this feature. Since round 2, `origin/main` (5581bc5,
`audit-blocks-only-new`) has been merged into the branch with a merge commit. Under the
parent orchestrator's ruling, round 2's audit finding is a `self/BACKLOG.md` entry, not a
fix here: a `GIT_CONFIG` in the hook's environment hides the config from the probe, and the
base allows it too. Round 3 is a fresh review and a fresh audit under the new audit
template.

Excluded:
- any deny;
- `http.proxy*` and the non-program credential keys;
- the wider writable-config class and the `GIT_CONFIG` environment finding, both of which
  are BACKLOG entries.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every contract in `review/complete/01-review-opus.md` and `02-review-opus.md` →
  "Contracts to hold it to" still holds.
- The merge of `origin/main` lost none of this feature's lines. Check these:
  - in `hooks/allow-repo-commands.sh`: `OWN_PUSH_PRESENT_KEYS`, `OWN_PUSH_PRESENT_KEY_RES`,
    `OWN_PUSH_ASKPASS_ENVS` and the env check in `own_push_config_allows`;
  - Q8 in `self/tests/hook-cloud-profile.sh`;
  - the `hooks/README.md` sentences;
  - the `self/BACKLOG.md` entries.
- `self/BACKLOG.md` carries the `GIT_CONFIG` entry from round 2's audit.
- `./self/gate.sh` is green on the merged tree.

## Verdict
