# Plans

_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`. Edit the template, not this file._

This repo's plan corpus for the delegated-execution workflow, plus the facts plans
need about this codebase. The runners and the workflow documentation are **not**
here — they live in `../agentTooling/`, a `git subtree` shared across repos, so a fix
to the machinery is made once and pulled everywhere.

- `features/` — one directory per feature: its manifest plus its own `auto/`,
  `verify/`, `review/`, and `interactive/`. See `features/README.md` for the full shape.
- `interactive/` — standing runbooks that outlive any one feature (e.g. first-run
  setup). A feature's own bash-heavy steps live in `features/<slug>/interactive/`
  instead.
- `PROJECT_FACTS.md` — repo-specific facts every plan must pin. Read this before authoring.
- `gate.sh` — *seeded once from the skeleton by `sync-plans.sh` on first run, then
  repo-owned and never overwritten again* — same treatment as `PROJECT_FACTS.md`. Runs this
  repo's deterministic checks (install, lint, tests, typecheck, build) between the build and
  verify passes and writes `gate-report.txt` for the verify and review plans to read, so no
  model spends turns running them. Fill in the freshly-seeded copy's REPO-SPECIFIC sections before relying
  on it — until then it records "GATE NOT CONFIGURED" rather than a false green. Advisory only:
  it exits non-zero solely when the environment is unusable.
  See `../agentTooling/AGENT_PLANS.md` → "The mechanical gate".
- `pr.sh` — *seeded once, then repo-owned* — same treatment as `gate.sh`. Run by
  `run-review.sh` after a clean review pass: branches if needed, commits, pushes, and
  opens a PR whose body is `review-report.md`. It lives here rather than in the shared
  harness because opening a PR is forge-specific (`gh`, `glab`, `tea`) and the harness
  must not pin every repo to one vendor. Check its `BASE_BRANCH` and `FORGE_CLI` before
  relying on it. Advisory: a failure here is reported and never unwinds the review pass.
- `review-report.md` — the review executor's verdict, and the body of the PR `pr.sh`
  opens. Gitignored and regenerated every batch, like `gate-report.txt`.

Run from the repo root:

```bash
./agentTooling/run-batch.sh    # build pass, then verify pass, then review pass
./agentTooling/run-plans.sh    # build pass only
./agentTooling/run-verify.sh   # verify pass only
./agentTooling/run-review.sh   # review pass only
```

Each accepts an optional feature slug as its first argument; omitted, the runner infers
it from whichever feature has work queued, and errors if more than one does. See
`../agentTooling/RUNNER.md` → "Choosing a feature".

Shared documentation:

- `../agentTooling/RUNNER.md` — how execution works: state folders, resume semantics, the
  progress and `.stream.jsonl` logs, how to read a failure.
- `../agentTooling/AGENT_PLANS.md` — how to author a plan.
