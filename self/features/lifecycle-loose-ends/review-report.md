Verdict: clean

# Review: lifecycle-loose-ends

## What the batch was supposed to do

Fix four lifecycle snags:

1. The start names the review-brief stub to fill, and its sections, in its last lines. The orchestrator brief tells the implementer to fill it before building.
2. `feature-close.sh` refuses a feature README that still matches its template, before any PR.
3. `harness_resolve_commit` falls back from a sha fetch to one deepen of a shallow clone, then to one fetch of the PR heads. It fails naming what it tried and creates no ref. The arm pin and the spec commit use the same resolver, and `check-fixture.sh` warns about a PR-only pin.
4. A rule against moving file bytes through a model goes into `ORCHESTRATION.md` and the brief template.

## Does it do it

Yes. Reviewed against `origin/main...HEAD`, item by item:

- **Item 1.** `feature-start.sh` ends, while the marker is present, with the brief's path relative to the worktree, the two headings (`What the feature was supposed to do`, `Contracts to hold it to`) and what goes under each. `feature-lifecycle.sh` S1n3 asserts this.
  - `ORCHESTRATOR_BRIEF.md` has the fill-before-build step (B3c), and B5 still caps the brief at 80 lines.
  - `run-review.sh` is untouched, so its refusal of the stub still stands.
- **Item 2.** `manifest.py check-prose` compares each prose section with the template's. A section counts as unfilled if it is identical to the template's fill-in text, or if it still holds one of the template's placeholders of 8 characters or more.
  - A deleted Levels or Contracts section passes.
  - The close runs the check next to its other pre-write refusals and fails closed when the checker cannot run.
  - Tests: `feature-readme-check.sh` covers the blank, filled, hand-pull and per-placeholder cases. `feature-lifecycle.sh` RP asserts the refusal names the section, makes no PR call and commits nothing.
  - This feature's own README passes the check.
- **Item 3.** The fallback order and the failure message are as specified. The PR heads are listed with `ls-remote` and fetched by exact name, so they land only in `FETCH_HEAD`. All of these go through the one resolver:
  - `check-fixture.sh` (base and spec commit, plus the PR-only warning)
  - `new-experiment.sh` (arm ref)
  - `harness_pin_agent_tooling`

  `resolve-commit.sh` tests this against a strict local bare repo, including a commit beyond the shallow depth and one reachable only from `refs/pull/*`.
- **Item 4.** The rule is in both docs, and B3d and B3e assert it.
- **Docs.** The READMEs of the touched folders and `LIFECYCLE.md` describe the new behaviour, and both new tests are listed in `self/tests/README.md`. The new values in `lib.sh`, `manifest.py` and `feature-close.sh` are named constants. The gate report has no failures and no SKIPPED checks.

One deliberate narrowing to note. The spec says no **local branch** is created or moved, and the implementation keeps that. The `--unshallow` step uses the remote's configured refspec, so it can still move `refs/remotes/<remote>/*`. That is harmless, and the comment in `lib.sh` says so.

## Fixed in this pass

- **`harness/lib.sh`, deepen step.** `git fetch --unshallow <remote>` used the configured refspec, so it auto-followed every tag pointing into the history it brought. In a real repo with tags that creates `refs/tags/*`, which breaks the contract that no ref is created. The test missed it because R1d compared only `refs/heads` and the fixture had no tags.
  - Added `--no-tags` to that fetch and widened the header comment to cover tags.
- **`self/tests/resolve-commit.sh`.** The fixture now pushes a tag beyond the clone's depth. It is placed on a commit other than the pinned one, so the strict server still refuses the sha fetch. R1d now compares `refs/heads` and `refs/tags` before and after.
  - I re-ran this one test after the change, and all checks pass.
- **`self/tests/README.md`.** The R1d description now says it checks tags too.

## Escalated to the next round

None.
