# Re-review: cloud-pull-fixes, round 3 (compare templates at the fork point)

## Round and escalation

Round 3. Round 2 (`escalations/02-review-opus.md`) passed everything except one item it
escalated: `self/tests/template-versions.sh` compared each template with the base's TIP, so
a branch that never touched a template went red once someone else's bump landed on main, and
the obvious "fix" (bump the stale copy) would roll main's newer template back on merge.

## The decision (coordinator, option (a))

Compare against the branch's FORK POINT: the base copy is `git show <merge-base of HEAD and
the base>:templates/plans/<file>`. Fall back to the base tip only when the merge base cannot
be computed (a shallow clone without the shared history); neither resolving is still the
"no base" failure naming `git fetch origin main`. Round 2's base resolution and overrides
(`TEMPLATE_BASE_REPO`, `TEMPLATE_BASE_REF`, origin/main then local main) are unchanged; one
override was added, `TEMPLATE_BRANCH_REPO` (the checkout whose HEAD is the branch), so the
fixture can hold branch and base together. Recorded as NOTES rulings 24-25. Residual: a
stale shallow branch can still trip on a newer main bump; the lower-version message says to
merge the base on the tip path and says the branch lowered it on the fork-point path.

## Contracts to check

1. **B15a**: main gains a template bump after the branch forks, the branch touched no
   template: passes, and the output names the fork point.
2. **B15b**: the branch edits a template and re-records the hash without a bump, main having
   moved: still FAILs ("not a bump"), relative to the fork point.
3. B15c: a version below the fork point FAILs and carries no "merge" advice. B15d: with no
   shared history the check falls back to the tip, FAILs a stale copy, and says to merge.
4. Earlier B cases (B1-B14) still pass unchanged; the depth-1 case (B14) is the meaningful
   tip-fallback case (the clone's history shares nothing with this checkout's HEAD).
5. The branch passes: `template-versions.sh` is green against the real `origin/main`, now
   at the fork point.
6. Nothing else changed since round 2's tree: the diff from round 2 is
   `self/tests/template-versions.sh`, `self/tests/template-version-bump.sh`,
   `self/tests/README.md` (two rows), NOTES.md (rulings 24-25), CHECKPOINT.md and this brief
   (plus feature-corpus bookkeeping). Literals are named constants (`BRANCH_REPO`,
   `SHORT_SHA_LEN`); bash 3.2 compatible. `self/gate.sh` ends `all checks passed`.

## Verdict

