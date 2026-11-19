# 02 — review: own-push-real-gitdir

Round 2: a re-review of the round-1 rework. The spec is unchanged: `NOTES.md` →
"Coordinator rulings" 1–8, plus ruling 9, which is round 1's triage. Do not read the
builder's report as the spec. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Everything `review/complete/01-review-opus.md` → "What the feature was supposed to do"
states still holds. Round 1's own verdict on the rest of the feature stands, unless this
round's diff changed it. On top of that, ruling 9:

- **New presence keys.** `OWN_PUSH_PRESENT_KEYS` / `OWN_PUSH_PRESENT_KEY_RES` also prompt
  on:
  - `submodule.recurse`
  - `push.followtags`
  - `hook.<name>.event` and `hook.<name>.command`

  Each has a Q7 row in `self/tests/hook-cloud-profile.sh` that asserts a prompt.
- **Exclusion sentence.** `hooks/README.md`'s exclusion sentence also names `core.askPass`
  and `remote.origin.proxy`. Its key list names the new keys.
- **What did not change.** No other code changed. No row changed its answer except the new
  ones.

Excluded, filed or ruled out in ruling 9:

- `http.sslVerify` and `http.curloptResolve`.
- The hook's own environment.
- The read-only git approvals in a planted gitdir, in `self/BACKLOG.md`.

None of these is a finding.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff. Round 2's own change is the commits after
`own-push-real-gitdir: review stamps`.

## Contracts to hold it to

All of round 1's contracts (`review/complete/01-review-opus.md` → "Contracts to hold it
to"), plus:

- The new keys are named constants beside the existing ones, compared in git's normalised
  form. That means lower-case section and key, with the `hook.<name>` subsection matched by
  the regex.
- The approve rows still pass with this container's real config.
- `./self/gate.sh` is green.
- Convergence: a finding is escalated only if it is a silent approval or a regression
  against origin/main. Anything else goes under observations, and does not escalate.

## Verdict
