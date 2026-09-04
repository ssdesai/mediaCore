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
- `experiments/` — one directory per A/B of the doctrine or the runner (or of the
  delegation tier itself): the checklist written before either arm runs, the behaviour
  score script, batch logs and the scorecard. Also `experiments/fixtures/`, the frozen
  features `../agentTooling/harness/` builds, and the experiment directories it appends
  `results.jsonl` to. See `../agentTooling/harness/EXPERIMENTS.md` → "Running one" and
  `../agentTooling/harness/README.md`. Absent until the repo runs one.
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
  `run-review.sh` after a clean review pass: it **never creates a branch** — the feature
  already ran on its own, in the worktree `../agentTooling/feature-start.sh` made
  (`../agentTooling/LIFECYCLE.md`) — so it commits whatever the pass left, pushes the
  current branch, and opens a PR from it whose body is `review-report.md`. The base is
  `FEATURE_BASE`, which `run-review.sh` exports from the manifest's `base`, else
  `BASE_BRANCH` from the environment, else `main`; a feature stacked on one that has not
  merged therefore targets the feature beneath it and its diff shows only its own work.
  On the base branch itself it refuses — there is no feature branch to open a PR from.
  It lives here rather than in the shared
  harness because opening a PR is forge-specific (`gh`, `glab`, `tea`) and the harness
  must not pin every repo to one vendor. Check its `FORGE_CLI` before
  relying on it. Advisory: a failure here is reported and never unwinds the review pass.
- `worktree-setup.sh` — *seeded once, then repo-owned* — this repo's per-worktree setup,
  run inside a freshly created feature worktree by `../agentTooling/feature-start.sh`
  before the gate: a venv (one per worktree — never shared, since an editable install
  points at whichever tree ran it last), `npm install`, a dev port no other worktree
  uses. It ships as a no-op skeleton whose comments list those; a non-zero exit stops the
  start with the worktree left in place.
- `review-report.md` — the review executor's verdict, and the body of the PR `pr.sh`
  opens. Gitignored and regenerated every batch, like `gate-report.txt`.
- `.gitignore` — *generated, overwritten every sync* — the four patterns whose files are
  rewritten every batch and never committed: `gate-report*.txt` (including the per-level
  `gate-report.<NN>.txt`), `**/*.stream.jsonl`, `**/*.logfifo` and `/review-report.md`.
  That last one is anchored to this directory so it catches the batch's live verdict
  without catching a feature's archived copy (`features/<slug>/review-report.md`), which
  is committed on purpose. Generated rather than an install instruction because nothing
  detects a missed instruction; a repo that skipped the old hand-written step committed a
  gate report on every batch.

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
