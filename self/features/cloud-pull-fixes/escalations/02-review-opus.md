Verdict: escalated

# Review: cloud-pull-fixes, round 2 (tie template hashes to versions)

## What this round was supposed to do

Round 1 found a hole in `self/tests/template-versions.sh`: you could edit a template,
re-record only its hash in `TEMPLATE_VERSIONS`, leave the version alone, and the check
stayed green. That is PR 85's failure, one command away. This round adds a comparison
with the base branch's copy of each template (`git show origin/main:templates/plans/<f>`,
falling back to local `main`). The base's hash is recomputed using the current rule. The
check fails when the version is unchanged but the content differs, and when the version is
lower than the base's. A new template passes. If no base can be found, the check fails and
the message names `git fetch origin main`.

## Does it do it

Yes. I checked each contract myself and did not rely on the implementer's report:

1. **The four cases plus B11 and B13.** `self/tests/template-version-bump.sh` covers B8–B14
   against a fixture base whose branch is not `main`, and all of them pass. I ran the test
   myself. In the fixture, the base's `TEMPLATE_VERSIONS` is deleted, which shows the
   base's table is never consulted (NOTES 21).
2. **The branch passes.** `template-versions.sh` against the real `origin/main` is green on
   all six templates. `git diff origin/main HEAD -- templates/plans` touches only
   `cloud-setup.sh` (bumped from 1 to 2) and `TEMPLATE_VERSIONS`. The five rows re-recorded
   under the new comments-count rule have no content drift from main, so recomputing the
   hash hides nothing.
3. **Shallow clone.** B14 runs a re-record and the unchanged case through a `--depth 1`
   clone (`is-shallow-repository` true). Failing when no base resolves is the right call:
   passing it as "unchecked" would bring back the PR-85 silence. Falling back to local
   `main` is acceptable as a last resort (NOTES 22–23).
4. **Nothing else changed.** `git diff d27a66b..HEAD --stat` lists only the brief's files
   plus feature-corpus bookkeeping (the feature `README.md` manifest's `plans`/`subagents`,
   `timing.jsonl`, the review brief).
5. **Quality.** The new literals are named constants (`BASE_REF`, `FALLBACK_BASE_BRANCH`,
   `BASE_TEMPLATE_DIR`, `BUMP_HINT`). The code is bash-3.2 clean. B1–B7 are unchanged and
   still pass. The `TEMPLATE_VERSIONS` header, `self/tests/README.md` (both rows) and
   `templates/README.md` all match the code.
6. **Gate.** `self/gate-report.txt` ends `all checks passed`, with nothing skipped.

NOTES rulings 20–23 are sound, apart from the consequence of ruling 20 escalated below.

## Fixed in this pass

- `self/tests/template-versions.sh`, the lower-version message: it said only "a version
  never goes backwards", and the natural reading of that is "bump it". It now adds "if
  this branch predates that bump, merge <base> rather than bumping here". B11 still
  greps `backwards`, and the test still passes.

## Escalated to the next round

1. **The check compares with the base's tip, not the merge-base, so branches that never
   touched a template go red once someone else's bump lands on main.**
   `self/tests/template-versions.sh`, `base_compare` (the `version < base_version` branch).
   - **Scenario:** branch X forks when `gate.sh` is at 3. Main later merges `gate.sh` 4.
     X's gate now fails `gate.sh version moves with its content` ("below origin/main's 4"),
     even though X never edited the file. The "same version, different content" case
     can't misfire this way, but the lower-version case always does.
   - **Why it matters:** `self/gate.sh` is blocking, and every `--self` executor and verify
     pass runs it. An agent that sees the failure may "fix" it by bumping X's stale copy to
     5. That passes, and it rolls main's version-4 content back at the next merge, which is
     exactly the silent staleness this check exists to stop. The reworded message makes
     merging the obvious remedy, but nothing enforces that.
   - **The decision needed:** either
     - (a) compare with `git merge-base HEAD <base>` when it resolves (any non-shallow or
       sufficiently deep clone), and fall back to the tip only in a depth-1 clone; or
     - (b) accept "a branch must be current with main for its gate to pass" as a stated
       invariant, and record it as a NOTES ruling and in the `self/tests/README.md` row.
   - **Missing test:** either way, add a B15 to `template-version-bump.sh`. Use a fixture
     base with two commits (template at N, then at N+1) and a copy matching the first
     commit. Under (a) it passes against the merge-base. Under (b) it fails and the
     message names the merge.
