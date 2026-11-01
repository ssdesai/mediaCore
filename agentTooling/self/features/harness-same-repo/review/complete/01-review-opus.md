# 01 — review: harness-same-repo

Written from the feature's spec before any review ran; "no findings" is a legitimate verdict.

## What the feature was supposed to do

The owner's rule: **every experiment runs from, and lives on, the repository it measures.**
Under it the measured repository is always the consuming repository the harness is vendored
in (`CONSUMER_ROOT`). Required behaviour:

1. `fixture.json`'s `repo` is optional. Absent, the fixture's repository is the consumer,
   remote `origin`; `repo.remote` alone may still name another remote of the consumer.
   When `repo.url` or `repo.path` is present it must identify the consumer (owner/repo,
   case-insensitive, `.git` dropped, so a cloud proxy URL matches); anything else is a
   `harness_die` at the first point the fixture is read (check-fixture, new-experiment,
   run, the dry run included) saying this fixture measures `<owner/repo>`, that an
   experiment runs from and lives on the repository it measures, and to move the fixture
   into that repository's `plans/experiments/fixtures/` and run it there. The fixture
   repository is never resolved, searched for or cloned; the cell worktree is added from
   `CONSUMER_ROOT`. `harness_resolve_repo`, `HARNESS_REPO_ROOTS`, `HARNESS_REPO_DIR_<KEY>`,
   the clone and its cloud remedy remain, used only for `spec.url` and the arm's agentTooling
   pin. `new-fixture.sh`: `--repo` optional and must be the consumer; the fixture it writes
   has no `repo` block (or only `remote`); `--spec-repo` defaults to the consumer.
2. `program.json`'s `repo` is optional with the same rule (refusal naming the program);
   `harness_program_check` requires every fixture to be on the consumer and keeps an error
   for a fixture naming another repository. `program-stages.sh`, `new-experiment.sh` use
   `CONSUMER_ROOT`.
3. `spec.url` (and legacy `spec.repo`) optional: absent, the spec worktree is added from the
   consumer at `spec.commit`; present, resolved as before, read-only. The dry run says which.
4. `run.sh`, `new-experiment.sh`, `check-fixture.sh`, `new-fixture.sh`, `publish.sh` refuse
   when the running harness is not the consumer's vendored copy (physical-path comparison of
   `CONSUMER_ROOT/agentTooling` and the script's own `AGENT_TOOLING_DIR`). Only the
   test seam `HARNESS_TEST_EXTERNAL_DRIVER=1` (a named constant) allows it, documented in
   `harness/tests/README.md` as a test seam and nowhere as an operator option.
5. The smoke test keeps its assertions and adds: a repo-less fixture end to end plus one
   naming the consumer's own URL; a fixture and a program on another repository refused;
   spec from the consumer when `spec.url` is absent; the external-driver refusal; the
   `HARNESS_REPO_DIR_*`/`HARNESS_REPO_ROOTS`/clone sections retargeted at `spec.url`.
6. Docs: `harness/EXPERIMENTS.md` states the rule first; `harness/README.md` (Repositories
   by URL, cloud container, fixture/program shapes with one sentence that a consumer fixture
   naming another repository is now refused, `new-fixture.sh`), `SPEC.md`,
   `tests/README.md` and every touched folder README are accurate; the arm's agentTooling
   pin and an external spec are stated to stay, read-only.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Nothing in the fixture path resolves, searches for or clones a repository other than
  `CONSUMER_ROOT`; trace `run.sh`, `program-stages.sh`, `new-experiment.sh`,
  `check-fixture.sh`, `new-fixture.sh` for any remaining `harness_resolve_repo` use on
  `repo`.
- The mismatch comparison is `harness_repo_identity` of the consumer's `origin`, and the
  refusal fires in a dry run and before any worktree or network action.
- The driver check compares physical paths and cannot be bypassed by anything but the
  test variable; check each of the five scripts calls it after argument parsing.
- bash 3.2 compatibility, no `set -e`, named constants, no magic literals; `set -u` safety
  of the new lib functions.
- Docs: READMEs list the changed behaviour (CONVENTIONS.md "READMEs"); no doc advertises
  the seam as an operator option, a standalone driver, or push access to a second repo.
- Smoke assertions test the behaviour, not just exit codes, and none was weakened.
- Do not demand work outside this scope: consumer-side fixture moves, propagation and
  experiments are the orchestrator's later waves.

## Verdict

First line of the report: `Verdict: clean` or `Verdict: escalated`. Fix local findings in
the pass; escalate structural ones.
