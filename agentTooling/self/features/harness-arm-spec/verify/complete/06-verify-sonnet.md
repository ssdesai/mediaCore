# 06 — verify: harness-arm-spec

feature: agentTooling/harness-arm-spec — the batch's one verify pass. Base-arm
experiments gain `--arm-spec-path <label>=<path>,…`: each cell reads its spec from its
own worktree at the arm's path, the prompts say it is never to be edited, and without the
option every prompt is byte for byte what it was at the base.

Read `self/gate-report.txt` first; do not re-run the whole gate, install, or the full
smoke suite unless a fix touches it.

1. **Generate the byte-identity fixture from the base — this is the one thing the build
   could not do.** `harness/tests/arm-spec.shared.md` does not exist yet (build executors
   have no shell). Run
   `bash harness/tests/arm-spec.sh --write-expected --from-ref b0faad18` — the fixture is
   the base's own templates filled with the fixed values, never this tree's — then
   `bash harness/tests/arm-spec.sh` and require it green. If the shared-mode comparison
   fails, the build changed a shared prompt: fix `lib.sh`'s `_SHARED` texts or the
   templates (never the fixture) until it passes. Commit nothing yourself.
2. Triage every red in the gate report first, then re-run only the failing check. Expect
   the README-index check to want a line for `arm-spec.shared.md` in
   `harness/tests/README.md`; plan 05 was told to add it — confirm.
3. `self/tests/direct-bare-pair.sh` fills the method templates with its own
   `HARNESS_*` values (around its line 73) and does not set `HARNESS_SPEC_PROVENANCE`:
   confirm it still passes and still means what it meant (read it); if it now compares
   text with an empty provenance, set the shared value there.
4. Read `harness/tests/arm-spec.sh` and smoke section 8c, then check only what they leave
   uncovered — in particular that `run.sh`'s resume path (`--from` after setup) of an
   arm-spec cell neither adds a shared spec worktree nor loses `SPEC_SOURCE`, by reading the
   code; write a smoke assertion if it is cheap, otherwise report it.

Passing: `arm-spec.sh`, `arm-base.sh`, `smoke.sh` and the README-index check green;
`arm-spec.shared.md` generated from `b0faad18`. Keep fixes local; anything structural is
reported for review.
