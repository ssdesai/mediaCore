# 01 — review: hand-start-friction

A hand build. Review the diff against the spec below, never against the builder's account
of it, and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans"). Fix local findings in the pass; escalate structural
ones.

## What the feature was supposed to do

The spec is the manifest, `self/features/hand-start-friction/README.md`: its opening
paragraph and its "Deliberately excluded" list. In short, three fixes, each one a snag
that every hand-method session in a consuming repo hit:

1. **Cloud setup race.** In a cloud container (and not locally), a consuming repo's
   `feature-start.sh` must wait for the setup `session-start.sh` began, via the
   `plans/cloud-setup.sh --wait` contract, before it runs the base gate. It must print one
   line saying it waited. The local profile must be unchanged.
2. **Review stub refusal.** A hand-method session that follows feature-start's printed
   instructions must not hit a review-stub refusal, and the planned-build rule (a
   `@@TODO@@` stub refused until a real brief replaces it) must not be weakened for
   `plans` and `direct`.
3. **Chain line.** `update.sh`'s `chain intact` line must be a whole sentence, consistent
   with the `broken` line.

`self/features/hand-start-friction/NOTES.md` is the builder's record and holds the
rulings. Read it after the diff, to check its claims.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The wait (item 1).**
  - `feature-start.sh` calls `plans/cloud-setup.sh --wait` only when all of these hold:
    `profile_is_cloud`, not `--self`, and the copy exists and carries the flag.
  - The call comes before the setup hook and the gate. It prints exactly one `setup`
    line, refuses on a non-zero exit, and leaves the start resumable (the cloud lock is
    already written at that point).
  - Under the local profile the start's output and behaviour are unchanged.
  - `feature-start.sh` never reads `CLAUDE_CODE_REMOTE` or `AGENTTOOLING_PROFILE` itself
    (`self/profile-confinement.sh`).
- **The template (v3).**
  - `--wait` cannot hang forever, exits 0 when nothing was started, and fails on a
    recorded non-zero code or on a missing code.
  - `setup_in_background` starts nothing while an earlier step is still running, writes
    only under the git dir, and leaves the hook's stdout free (no inherited pipe).
  - The skeleton's behaviour when nothing is configured is unchanged.
  - Outside the cloud profile it is still a no-op (`--wait` included).
  - It runs under bash 3.2 with `set -uo pipefail`.
- **Template bookkeeping.**
  - The version line is 3, and `TEMPLATE_VERSIONS` is re-recorded by its own documented
    command (`self/tests/template-versions.sh` green).
  - Every assertion and doc that named version 2 or `1 < 2` for cloud-setup.sh is moved.
- **The hand brief (item 2).**
  - Under `--method hand` the brief has no line beginning `@@TODO@@`.
  - It names the manifest as its spec, gives the diff and the gate, and asks for the
    feature's own contracts.
  - A resumed cloud start keeps an existing brief.
  - `plans` and `direct` starts still write the stub, and `run_all` still refuses it
    (moved to `failed/`, claude never called).
  - The new refusal text names both paths, relative to the repo root, and the three
    things a brief holds.
  - The "Next" step 1 tells the truth for each method.
- **The chain line (item 3).** The line reads exactly `chain  intact — base <sha> records
  split <sha>, the vendored tree's own commit; a pull merges from it cleanly`.
- **Tests.** `self/tests/cloud-setup-wait.sh` is registered in `self/gate.sh`, both in
  the `bash -n` list and as a `record`. It would fail without the wait (W2a2/W2c).
  `feature-lifecycle.sh` S3d2–S3d4, T1c2 and T3, and `subtree-chain.sh` C4b, assert the
  new behaviour.
- **Gate.** `./self/gate.sh` is green on this tree.
- **READMEs.** The READMEs of every touched folder describe the change: root
  `README.md`, `templates/README.md`, `templates/plans/README.md`, `self/README.md`,
  `self/tests/README.md`, and `LIFECYCLE.md` steps 2–3.
- **Scope.**
  - Nothing under `hooks/` changed.
  - No new magic literal outside a named constant.
  - No `.venv` fix was made in a template where NOTES says none was due. Check that
    claim against the templates.

## Verdict
