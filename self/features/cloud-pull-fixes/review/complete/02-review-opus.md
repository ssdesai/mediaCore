# 02 — review: cloud-pull-fixes (round 2)

You are re-reviewing a direct build in agentTooling's own corpus (`--self`) after one
rework. Round 1 (`review/complete/01-review-opus.md`, escalation
`escalations/01-review-opus.md`) held A and C and the audit half of B, fixed two doc nits,
and escalated one finding. Judge the rework against that finding, never against the
implementer's report. Read `self/features/cloud-pull-fixes/NOTES.md` (rulings 20-23 are this
round's; judge each), `CONVENTIONS.md` (README rules, named constants) and
`self/PROJECT_FACTS.md` (bash 3.2, `set -uo pipefail` with no `set -e`). "No findings" is a
legitimate verdict. Fix what is local and plainly wrong yourself; escalate what is structural.

## The finding (round 1)

**B: the check passed when a template was edited and its hash re-recorded without a version
bump.** `self/tests/template-versions.sh` only checked that the file's stamp equalled the
table's version and the file's hash equalled the table's hash. Nothing tied a hash to a
version, so: edit `templates/plans/gate.sh`, see red, run the re-record command from the
`TEMPLATE_VERSIONS` header, update only that row's hash, and the gate is green while every
consumer reads `in-sync` with a stale copy — PR 85's failure one command away. No test
covered it.

## The fix (round 2)

Option 1 of the finding. `template-versions.sh` also compares each template with the base
branch's copy:

- `git show <base>:templates/plans/<file>`, base = `origin/main` (`BASE_REF`), else local
  `main` (the `run-review.sh` `review_diff_base` precedent); neither resolving fails with a
  message naming `git fetch origin main`. Only the base tip is read, so a depth-1 fetch
  serves.
- The base's hash is **recomputed from its file with the current rule**, never read from the
  base's `TEMPLATE_VERSIONS` — so the five rows this feature re-recorded under the
  comments-count rule (NOTES 7) read as unchanged content at an unchanged version, and a
  future rule change is immune.
- Same version, different content: FAIL ("re-recording the hash is not a bump"). Lower
  version: FAIL ("never goes backwards"). No base copy (new template): pass. A removed
  template has no row left to check.
- `TEMPLATE_BASE_REPO` / `TEMPLATE_BASE_REF` override the base for the self-test fixture.
- The `TEMPLATE_VERSIONS` header and `BUMP_HINT` now say bump FIRST, then re-record, and
  that the check compares with `origin/main`. `self/tests/README.md` (both rows) and
  `templates/README.md` are updated.

Files changed this round: `self/tests/template-versions.sh`,
`self/tests/template-version-bump.sh`, `templates/plans/TEMPLATE_VERSIONS` (header comment
only; no row changed), `self/tests/README.md`, `templates/README.md`, `NOTES.md`,
`CHECKPOINT.md`, this brief.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. For round 2 alone, the commit is
`cloud-pull-fixes: round 2 — tie template hashes to versions` (`git show HEAD --stat` from
its tree).

## Contracts to hold it to

1. **The four cases** (`self/tests/template-version-bump.sh`, B8-B14 against a fixture repo
   standing in for `origin/main`): a hash re-recorded at an unchanged version FAILs naming
   the file (B9, rc 1, "not a bump"); a bump with a new hash passes (B10); an unchanged tree
   passes (B8); a new template — no copy on the base — passes (B12). Also: a version below
   the base's FAILs (B11); an unavailable base FAILs naming the fetch (B13).
2. **The branch passes.** `bash self/tests/template-versions.sh` on this tree against the
   real `origin/main` is green, including cloud-setup.sh (bumped 1 to 2 by this feature) and
   the five rows re-recorded at unchanged versions. Confirm none of those five has real
   content drift from main's copy that the recompute rule is hiding: compare
   `git show origin/main:templates/plans/<f>` with the tree, ignoring the version line.
3. **Shallow clone.** The check reads only the base tip: B14 re-runs the re-record and the
   unchanged case through a `--depth 1` clone (`is-shallow-repository` true). Judge that
   failing (rather than passing "unchecked") when no base ref resolves is right, and that
   the local-`main` fallback is acceptable.
4. **Nothing else changed since round 1's tree.** `git diff d27a66b..HEAD --stat` (round 1's
   commit to this one) lists only the files above plus feature-corpus bookkeeping
   (`timing.jsonl`, review/escalation files). A, C, the other template rows and every other
   test are as round 1 saw them.
5. **Quality bar.** Named constants for every literal that carries meaning; bash 3.2; the
   touched READMEs current; `template-version-bump.sh` still asserts everything B1-B7 did.
6. **Gate green.** Read `self/gate-report.txt` from this round's run (verdict line in
   CHECKPOINT.md); do not re-run the whole gate. Run `self/tests/template-versions.sh` and
   `self/tests/template-version-bump.sh` to settle any finding.

## Verdict
