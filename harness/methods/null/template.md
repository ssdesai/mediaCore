feature: @@SLUG@@

This is the `null` method's brief. No model ever reads it: `null/run.sh` writes a marker
file and calls the repo's PR hook, so the harness can be exercised end to end with no
network and no money (`harness/tests/smoke.sh`).

It is still generated and still filled, because the smoke test's job is to prove the
brief stage works — an unfilled placeholder below would fail the same way it would in a
real method's brief.

- Worktree: `@@TREE@@`, branch `@@BRANCH@@`, off `@@BASE@@`
- Feature: `@@SLUG@@` in fixture `@@FIXTURE@@`
- Spec: `@@SPEC_TREE@@/@@SPEC_PATH@@`, sections @@SPEC_SECTIONS@@
- Gate: `@@GATE_COMMAND@@` (about @@GATE_MINUTES@@ minutes), expected green

@@ISOLATION@@

## Facts

@@FACTS@@
