Verdict: clean

# Review — smoke-priced-cells

## What the batch was supposed to do

Add two sections to `harness/tests/smoke.sh`, with no change to the harness itself:

1. **An ordinary cell priced end to end.** A pinned `direct` cell runs under the priced HOME with `SMOKE_PRICED_TRANSCRIPTS=1`, and the test asserts that its implementer, review and rework costs are each above 0, that they sum to `cost_green_usd`, that `cost_method_reported_usd` matches what the fake reported, that there is no unpriced warning, and that the capture log has no `cannot claim` / `launched_elsewhere` line.
2. **`stages {review: false}` as a real run**, not only a dry run, asserting what `run.sh` actually records.
3. **Docs** in `harness/tests/README.md`, `harness/README.md` and `harness/EXPERIMENTS.md` describing what the smoke test now proves.

## Does it do it

Yes. I read the diff (`origin/main...HEAD`) and checked it against the code it asserts on:

- **Priced cell.**
  - The fake's new implementer branch matches `"feature: "*"You are the sole implementer"*`. Only the `direct` template (`methods/direct/template.md`) starts that way; the review and rework preambles do not contain that phrase.
  - Billing only happens when `SMOKE_PRICED_TRANSCRIPTS=1`. That variable is set as a per-command prefix on the program run and the priced cell only, so the ordinary full run (method `null`) still bills nothing and still reports 0.
  - The cell is derived from `PIN_DIR`, which is pinned to the full commit id. Capture therefore runs from a real vendored copy.
  - The fake transcripts record the real `$PWD` and branch. If `claim_roots` stopped admitting the `<primary>-<branch>` tree, all three `> 0` checks would fail.
  - The warning pattern `claude reported` matches the `harness_warn` text in `do_capture` (`run.sh:558`). The `cannot claim` pattern matches the text `capture_planning.py` emits at line 3789.
- **No-review run.** Each asserted value matches `run.sh`:
  - `do_review` returns before `stage_begin`, so there is no `stages.review`, no `t_review_end`, no `review_*` keys and no prompt at `logs/<branch>-review-prompt.md`.
  - `do_rework` finds no findings file and returns before `stage_begin`.
  - `do_capture` records `cost_review_usd` as the capture of a missing directory, which is `0`.
  - The branch checks with `cat-file` mean something, because review and rework commit their manifests and findings onto the branch (`harness_commit_all` and `harness_push`). They are not checks that pass whatever happens.
  - If `harness_stage_enabled` regressed to `// true`, review would run and these checks would fail.
- **Fake `claude` heredoc.** Runtime `$`, `$$` and backticks are escaped. `$NULL_MARKER_RELPATH` and `$BIN` are expanded when the script is built, which is intended. `%3N` is the same GNU `date` form the program fake already used.
- **Program section.** Review and rework there are now billed too. No assertion pins them to 0, and the arithmetic checks still hold. The comment at the priced HOME was updated to say so.
- **Docs.** All three files match the code. The rehearsal item in `EXPERIMENTS.md` was reworded, not deleted. The tests README names both new sections and every env variable the fake reads, and it now correctly says the prompt arrives on stdin (the old text said "last argument", which was wrong).
- **Scope.** Nothing under `.claude/` or any other feature changed, and no committed file contains a model identifier.

The gate is green (`self/gate-report.txt`: "smoke: all checks passed"), and it lists no SKIPPED checks.

## Fixed in this pass

Nothing.

## Escalated to the next round

Nothing.
