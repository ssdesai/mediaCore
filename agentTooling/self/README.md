# self

agentTooling's own plan corpus — the harness applied to itself. This is the exact
counterpart of a consuming repo's `plans/` directory, one level in, and it is drained by
passing `--self` to the runners:

```bash
./agentTooling/run-batch.sh --self <slug>    # build, then verify, then review
./agentTooling/run-plans.sh --self <slug>    # build pass only
./agentTooling/run-verify.sh --self <slug>   # verify pass only
./agentTooling/run-review.sh --self <slug>   # review pass only
```

| Path | What it is |
|---|---|
| `features/` | One directory per agentTooling feature: manifest, `auto/`, `verify/`, `review/`, `interactive/`, and the JSON cost artifacts. See `features/README.md`. |
| `interactive/` | Standing runbooks that outlive any one feature. A feature's own bash-heavy steps live in `features/<slug>/interactive/` instead. |
| `PROJECT_FACTS.md` | The facts every agentTooling plan must pin — bash version, what stands in for a test runner, how the analysis scripts import each other. Read before authoring. |
| `gate.sh` | The mechanical gate `run-batch.sh --self` runs after the build pass, writing `gate-report.txt` for the verify and review passes to read. Syntax checks plus the behavioural scripts in `tests/`. |
| `tests/` | Behavioural checks the gate `record`s — the runner contracts (`level-sentinel.sh`, `tiered-gates.sh`), the feature lifecycle's (`feature-lifecycle.sh`: start, the stub-brief refusal, the PR hook, close), the cost tooling's (`cost-recovery.sh`, `capture-guard.sh`, `subagent-capture.sh`, `timestamps-are-utc.sh`), the plan-linting's (`check-plans.sh`), the update-sync's (`sync-check.sh`), the sweep's (`sweep.sh`), the direct build's milestone record (`direct-timing.sh`), and the template version/hash table (`template-versions.sh`, the one that reads the checked-in tree instead of a sandbox). See `tests/README.md`. |
| `pr.sh` | Opens the PR after a clean `--self` review pass. agentTooling's own copy of `templates/plans/pr.sh`; not written by `sync-plans.sh`, so keep it in step by hand when the template changes. |
| `worktree-setup.sh` | The setup hook `../feature-start.sh --self` runs inside a new feature worktree, before the gate. agentTooling's own counterpart of `templates/plans/worktree-setup.sh`; it does nothing, because this repo is bash and stdlib Python with no install step — it exists so the hook path is the same in both modes. |
| `TRIAGE-2026-09-03-feature-execution-procedure.md` | Triage of the direct one-shot's cost-attribution and PR gaps, measured in vinylCatalogue on 2026-09-03: the documented steps, ten caveats with evidence, eight fixes in dependency order. Moved here because every fix lands in this directory; the input for the `feature-execution-procedure` self feature. |
| `gate-report.txt` | Gate output. Gitignored — regenerated every batch. |
| `review-report.md` | The review pass's verdict, used verbatim as the PR body. Gitignored — regenerated every batch. |

## Not generated

A consuming repo's `plans/` stubs are written by `sync-plans.sh` from `templates/`, and
every one of them points back up at `../agentTooling/…`. From here those relative paths
are wrong and the "edit the template, not this file" banner would be a lie — this
directory *is* the source. Everything here is hand-written and stays that way;
`sync-plans.sh` does not touch it and takes no `--self` flag.

## Why costs land here, not in the host repo

A feature whose entire diff is under `agentTooling/` should carry its manifest, plans,
logs and cost records under `agentTooling/` too. Filing them in whichever repo happened
to vendor the subtree misattributes the work and strands it there — the next repo to
vendor agentTooling would have to recreate the history by hand. `plan-analytics` is the
worked example: it changed nothing outside this directory, and it lives here.

The execution model itself — state folders, resume semantics, the progress and usage
logs, how to read a failure — is documented once in `../RUNNER.md`, not repeated here.
