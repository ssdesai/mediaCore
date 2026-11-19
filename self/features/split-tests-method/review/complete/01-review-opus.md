# 01 — review: split-tests-method

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/split-tests-method/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`self/features/split-tests-method/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own:

- `harness/methods/split-tests/template.md`: the text after the marker line
  `<!-- split-tests: the implementer brief starts on the next line -->` is
  `harness/methods/vanilla-conv/template.md` byte for byte plus exactly one paragraph,
  placed before `## Finish`. That paragraph names the `%%TESTS_SHA%%` slot and
  `@@SLUG@@: acceptance tests`, says to make the tests pass and not delete or weaken them,
  limits changes to tests that contradict the spec or guess an open name or seam, and asks
  for each change with its reason under "Test changes" in the PR body. Every `@@NAME@@` in
  either half is one the harness fills, and an unfilled one still aborts
  (`harness_fill_template` is unchanged). Check that the author brief asks for black-box
  tests only, no implementation, one commit with the right subject staged by path, and no
  push or PR.
- `harness/methods/split-tests/run.sh`: both sessions go through `harness_claude` from
  `"$TREE"` with `--model "$HARNESS_MODEL" --permission-mode acceptEdits --allowedTools
  Bash`. Exit 0, 2 or 1 per `harness/methods/README.md` → "The contract". Exit 1, with no
  implementer, when the author commits nothing, when the range changes a non-test path, when
  its tip is not the `<slug>: acceptance tests` commit, or when it leaves newly dirty paths
  outside `plans/features/<slug>/`. The test diff goes to
  `$HARNESS_LOG_DIR/<branch>-test-diff.txt`, whatever the implementer's exit. Nothing the
  method writes lands in the tree. A re-entry after a usage-limit stop skips the author
  when its commit exists. No `${x//pat/$var}` (the patsub guard in
  `self/tests/harness-driver-measures.sh`).
- `self/tests/split-tests-pair.sh` is recorded by `self/gate.sh`. It fails when the
  implementer half drifts from `vanilla-conv`'s template plus one paragraph.
- `harness/methods/README.md` (table row, ladder text: `split-tests` beside `vanilla-conv`,
  not on the ladder), `harness/README.md`'s `methods/` row,
  `harness/methods/vanilla-conv/README.md`, `self/tests/README.md` and the new
  `harness/methods/split-tests/README.md` describe what the diff does.
- Out of bounds for this feature: `harness/run.sh`, `harness/lib.sh`, `hooks/` and
  `harness/check-fixture.sh` are unchanged (another feature's files).

## Verdict
