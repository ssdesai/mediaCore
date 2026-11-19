# 02 — review: own-push-credential-keys

Re-review this feature against its spec, which is the coordinator's rulings in
`self/features/own-push-credential-keys/NOTES.md` → "Coordinator rulings", rulings 1-9.
Ruling 9 is round 1's triage. Do not use the builder's report as the spec.
"No findings" is a legitimate verdict.

## What the feature was supposed to do

The spec is everything round 1 reviewed (`review/complete/01-review-opus.md`): in the cloud
profile, `git push [-u] origin <own-branch>` prompts instead of approving silently when
any of these holds:
- `credential.helper`, a url-scoped `credential.<sub>.helper` or `core.askPass` is in the
  effective config;
- `GIT_ASKPASS` or `SSH_ASKPASS` is set non-empty in the hook's environment.

The round-2 change closes round 1's blocking audit finding
(`escalations/01-audit-opus.md`). An empty subsection, `[credential ""] helper = …`, which
git lists as `credential..helper`, was a silent allow, and git runs that helper for every
url. Per ruling 9, every subsection regex in `OWN_PUSH_PRESENT_KEY_RES` (`branch`,
`includeif`, `hook`, `credential`) now accepts an empty subsection (`.*` for `.+`).

Excluded: any deny, `http.proxy*`, the non-program credential keys, and the wider
writable-config class, which goes to `self/BACKLOG.md` only.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every contract in `review/complete/01-review-opus.md` → "Contracts to hold it to" still
  holds.
- `OWN_PUSH_PRESENT_KEY_RES` matches `credential..helper`, `includeif..path`,
  `hook..command` and `branch..pushremote`.
- It still does not match `credential.helper` through a regex (that is the exact key),
  `credential.helperx`, `credential.x.helpers`, `credential.interactive` or
  `credential.x.username`.
- Q8 in `self/tests/hook-cloud-profile.sh` has these rows:
  - `[credential ""]` written as raw config text in the repo config;
  - the same in the global config only;
  - one row each for the other three empty-subsection keys.
- NOTES records the credential rows as red on round 1's hook (b0ae205).
- `hooks/README.md` names the empty subsection.
- `./self/gate.sh` is green.

## Verdict
