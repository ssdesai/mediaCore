# 02 — review: audit-round-cap (round 2)

A doc-only feature: two process rules, no code. Review the diff against the spec below, never against the builder's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Same as round 1 (`review/complete/01-review-opus.md`): a cap of 2 escalated audit rounds in `LIFECYCLE.md` → "The security audit", and a one-gap-per-hook-feature rule in `ORCHESTRATION.md` → "Rules", with the two BACKLOG entries removed. Round 1 escalated one point, fixed in this round by a document-only choice (option a in `escalations/01-review-opus.md`): the cap paragraph no longer promises a close the unchanged close checks refuse (a closing ruling first needs a round that backs out what the moved findings flag and ends in a clean audit, else the feature is abandoned), and a `stale` stamp counts as an escalated audit round. No `feature-close.sh` change is in scope.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Only `LIFECYCLE.md`, `ORCHESTRATION.md`, `self/BACKLOG.md` and this feature's folder change; exactly the two named BACKLOG entries are removed.
- The cap paragraph is true against the close's unchanged checks and promises no route the close refuses.
- It still states: 2, coordinator stops, owner rules, BACKLOG destination, feature continues or closes per the ruling; and stays consistent with the non-blocking and `<slug>: backlog` rules.
- The one-gap rule and its cross-references are correct.

## Verdict
