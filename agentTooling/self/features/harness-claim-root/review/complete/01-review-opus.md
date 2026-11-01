# 01 — review: harness-claim-root

Review the feature `harness-claim-root` against the spec below, written before the build
and not from the builder's report. "No findings" is a legitimate verdict; report only what
you can show from the diff or by running something. Local findings you fix in this pass;
structural ones you escalate (AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The experiment harness runs every `claude` session of a feature with cwd
`<repo checkout>-<Branch>` (`harness_worktree_path`, `harness/lib.sh`, camelCase).
`analysis/capture_planning.py` priced a session for a feature only from `claim_roots`
(the primary, `<primary>/.worktrees/<slug>`, the legacy sibling `<primary>-<slug>`), so a
harness session landed in `launched_elsewhere` and the feature priced $0, for the
implementer, `<slug>-review` and `<slug>-rework` alike. Required:

1. `claim_roots` gains, for every entry of the manifest's `branches`, the root
   `<primary>-<branch>`. Existing roots and whole-component matching (`cwd_claimable`)
   stay. Empty `branches` adds no root. Both call sites pass the branches (capture and
   `--last-branch-instant`); the `launched_elsewhere` warning text names the new roots.
   The review and rework manifests the harness writes carry the feature branch
   (`write_stage_manifest`, `harness_write_manifest`): verify that claim.
2. `self/tests/harness-claim-root.sh`: a manifest with `branches` holding
   `exportStoreDirectAfter2`; a transcript with cwd `<primary>-exportStoreDirectAfter2` is
   priced; `<primary>-otherBranch` is not claimed and the warning names it; empty
   `branches` adds no sibling root. Registered in `self/gate.sh` (both the `bash -n` list
   and the `record` list) and in `self/tests/README.md`.
3. `harness/tests/smoke.sh`: the fabricated legacy cwd (the comment and the `tcwd=`
   substitution) is removed so the priced fake transcript records the real `$PWD`; the
   program full run's non-zero cost assertions still pass.
4. `jq '.stages.x // true'` treated an explicit `false` as `true`. One lib helper
   `harness_stage_enabled <experiment.json> <stage>` (`null` → true, otherwise the value)
   is used everywhere the flags are read (`harness/run.sh`; check `program-stages.sh`
   and `new-experiment.sh` for any other reader), with a smoke assertion that
   `"stages": {"review": false}` reads as false.
5. Docs: `analysis/README.md` (four claim roots), `harness/README.md` ("Naming", "Stages"),
   `harness/EXPERIMENTS.md` (the implementer-session assumption is now proven by the smoke;
   reworded, paragraph kept), `harness/SPEC.md` where it pinned that assumption,
   `harness/tests/README.md`, `self/tests/README.md`.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Code in `analysis/` is stdlib-only Python; shell is bash 3.2, `set -uo pipefail`, no
  `set -e`, named constants for magic values (CONVENTIONS.md "Named constants").
- `claim_roots` returns `(roots, fences)`; the fence `<primary>/.worktrees` still beats the
  primary root. A branch containing a path-special character must not widen a root beyond
  `<primary>-<branch>`.
- The warning must stay a single f-string per cwd and name each claimable root.
- Every changed folder's README still describes it (CONVENTIONS.md "Keeping READMEs up to
  date"); no file under `.claude/` or another feature's folder is touched; no model
  identifier appears in a committed file.
- Run `bash self/tests/harness-claim-root.sh` and `bash self/tests/worktree-claims.sh`;
  both must pass. Do not run the full gate.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
