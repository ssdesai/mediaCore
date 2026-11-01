Verdict: escalated

# Review: harness-same-repo

## What the batch was supposed to do

Enforce the owner's rule, *every experiment runs from, and lives on, the repository it
measures*:

- A fixture's or program's `repo` block is optional. When it is present it must identify
  the consumer (`CONSUMER_ROOT`'s `origin`); otherwise the harness refuses at the first
  read, the dry run included.
- The cell worktree is always added from `CONSUMER_ROOT`.
- `spec.url` is optional. Absent, the spec comes from the consumer.
- The five entry scripts refuse to run unless they are the consumer's own vendored copy.
  The only exception is the test seam `HARNESS_TEST_EXTERNAL_DRIVER=1`.
- The smoke test and the docs were to be updated to match.

## Does it do it

Yes. What I checked in the diff:

- **No fixture path resolves another repository.** `harness_resolve_fixture_repo`,
  `harness_fixture_url` and `harness_fixture_hint` are gone, and nothing calls them any
  more. `run.sh`, `new-experiment.sh` and `check-fixture.sh` now go through
  `harness_fixture_repo`, which runs the check and then returns `CONSUMER_ROOT`.
  `program-stages.sh` and the programs loop in `new-experiment.sh` use `CONSUMER_ROOT`
  directly, after `harness_program_check` has refused any foreign `repo` block.
  `harness_resolve_repo` is now reached only through `harness_fixture_spec_repo` (for
  `spec.url` and the legacy `spec.repo`) and the arm pin.
- **The comparison uses the consumer's `origin`.** `harness_measured_repo_problem`
  compares `harness_repo_identity` of `repo.url` against that of the consumer's `origin`.
  In `run.sh` the check runs inside `resolve_cell`, before `dry_run_cell` or `run_cell`,
  so it fires in a dry run and before any worktree or network step for that cell.
  `harness_experiment_arms` only parses JSON.
- **The driver check.** `harness_require_own_driver` compares physical paths
  (`pwd -P`) of `CONSUMER_ROOT/agentTooling` and `AGENT_TOOLING_DIR`. It is called after
  argument parsing in all five scripts (`run.sh`, `new-experiment.sh`, `check-fixture.sh`,
  `new-fixture.sh`, `publish.sh`). Only `HARNESS_TEST_EXTERNAL_DRIVER=1` bypasses it, and
  it is documented only as a test seam (`lib.sh`, `harness/tests/README.md`).
- **Shell safety.** No `set -e`. The new lib functions declare their locals and are safe
  under `set -u`, and no bash-4 constructs were added. The new literals have named
  constants (`CONSUMER_IDENTITY_REMOTE`, `HARNESS_FIXTURES_RELDIR`).
- **Smoke test.** Every old assertion was either kept or retargeted at `spec.url`
  (override, clone, legacy path hint). New checks cover:
  - a fixture with no `repo` block, run end to end, with the spec worktree's common git
    dir asserted to be the consumer's;
  - a fixture naming the consumer's own URL: passes `check-fixture.sh`, the dry run and
    `new-experiment.sh`;
  - a fixture and a program naming another repository: refused, and the message names
    `acme/other` and the remedy;
  - `new-fixture.sh` with no `--repo`, and with a foreign `--repo`;
  - the driver refusal in all five scripts, plus the positive case and the seam.

  The assertions check message content and filesystem state, not just exit codes.
- **Docs.** `EXPERIMENTS.md` states the rule first. The `harness/README.md` sections
  ("Repositories by URL", the cloud container, the fixture and program shapes, the
  `new-fixture.sh` entry), `SPEC.md` and `tests/README.md` all match the code. No doc
  advertises the seam as an operator option or asks for push access to a second
  repository.

The gate (`self/gate-report.txt`) is green and includes `harness/tests/smoke.sh`.

## Fixed in this pass

- `harness/README.md`, step 2 of the fixture walkthrough said "there is no `--repo`".
  `new-fixture.sh` still accepts `--repo` and refuses it unless it is the consumer, as
  the file table in the same README says. The sentence now reads "`--repo` is not needed
  (given, it must be the consumer or is refused)".

## Escalated to the next round

1. **Missing test: the `repo.path` branch of `harness_measured_repo_problem` is never
   exercised** (`harness/lib.sh`, the `if [[ -n "$path" ]]` block). The smoke test only
   writes `repo.url` variants. The old smoke had a `repo.path` legacy fixture, which this
   batch retargeted to `spec.repo`. That leaves three paths with no assertion: a
   `repo.path` that is the consumer's own directory (should pass), a `repo.path` that is
   a checkout of another repository (should be refused, naming that checkout's
   `owner/repo`), and a `repo.path` that does not exist (refused, naming the path). Add
   one `derived_fixture` per case in section 5 of `harness/tests/smoke.sh` and run
   `check-fixture.sh` against each.

2. **Decision needed: a matching `repo.url` plus a stale `repo.path` is refused.** Under
   `harness-cloud-pins`, `repo.url` was the identity and `repo.path` was only a hint. Now
   both are checked independently. A consumer fixture with `repo.url` set to the
   consumer and a laptop-only `repo.path` (`/Users/<owner>/dev/<repo>`) is refused in a
   cloud container. The message is misleading: "this fixture measures
   /Users/<owner>/dev/<repo>". This matches the brief and the docs as written ("`repo.url`
   / `repo.path`, if present, must identify the consumer"), so it is not a bug against
   the spec. But it amends the earlier hint contract without saying so. Two options for
   the owner:
   - (a) Treat a matching `repo.url` as authoritative and ignore `repo.path` when it is
     present: a one-line `return 0` after the url match in
     `harness_measured_repo_problem`, plus a doc sentence in `harness/README.md`
     (fixture shape) and `SPEC.md` §14.
   - (b) Keep the refusal, and say in the same docs that a fixture still carrying a
     `repo.path` should drop it.

   Either way, add a smoke assertion for the chosen behaviour.

Nothing else is outstanding. Consumer-side fixture moves and propagation are out of
scope (later waves).
