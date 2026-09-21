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
- `BACKLOG.md` — escalations and decisions left open by finished batches, one entry per
  item phrased as the assertion that would catch it. Deferrals go here, not in a
  NOTES.md. *Seeded once by `sync-plans.sh` and never overwritten* — same treatment as
  `PROJECT_FACTS.md`, so a repo's own entries survive every `subtree pull`.
- `gate.sh` — *seeded once from the skeleton by `sync-plans.sh` on first run, then
  repo-owned and never overwritten again* — same treatment as `PROJECT_FACTS.md`. Runs this
  repo's deterministic checks (install, lint, tests, typecheck, build) between the build and
  verify passes and writes `gate-report.txt` for the verify and review plans to read, so no
  model spends turns running them. Fill in the freshly-seeded copy's REPO-SPECIFIC sections before relying
  on it — until then it records "GATE NOT CONFIGURED" rather than a false green. Advisory only:
  it exits non-zero solely when the environment is unusable.
  See `../agentTooling/AGENT_PLANS.md` → "The mechanical gate".
- `pr.sh` — *seeded once, then repo-owned* — same treatment as `gate.sh`, and at
  `template-version: 4`, which is the version that has **two entry points**. Run by
  `../agentTooling/feature-close.sh`, never by a runner:
  - **`pr.sh <slug> <body-file>`** opens the PR. It **never creates a branch** — the
    feature already ran on its own, in the worktree `../agentTooling/feature-start.sh`
    made (`../agentTooling/LIFECYCLE.md`) — so it pushes the current branch and opens a PR
    from it whose body is the file the close composed (the review's verdict, then the
    Rounds table). Its `git add -A` commit is only ever a **fallback** now: the review pass
    commits its own output as `<slug>: review round N` and the close commits the stamps
    that followed, so a current harness leaves a clean tree here. The base is
    `FEATURE_BASE`, which `feature-close.sh` exports from the manifest's `base`, else
    `BASE_BRANCH` from the environment, else `main`; a feature stacked on one that has not
    merged therefore targets the feature beneath it and its diff shows only its own work.
    On the base branch itself it refuses — there is no feature branch to open a PR from.
  - **`pr.sh --merge-request <slug>`** asks the forge to merge the PR that is already
    open, under `PR_AUTO_MERGE=1` (`gh pr merge --auto --merge --delete-branch`; a merge
    commit, never a squash, since the prune and the post-merge capture both test
    ancestry). It opens nothing and pushes nothing. `feature-close.sh` calls it **last**,
    after `../agentTooling/feature-capture.sh` has committed the cost records on the
    branch and pushed them — which is why the flag is safe without a required status
    check, and why a version-3 copy, whose open path requested the merge itself, is worth
    hand-merging (`../agentTooling/README.md` → "Adopting rounds and the close"). Unset,
    it says so and exits 0.

  It lives here rather than in the shared harness because talking to a forge is
  forge-specific (`gh`, `glab`, `tea`) and the harness must not pin every repo to one
  vendor. Check its `FORGE_CLI` before relying on it. Advisory: a failure here is reported
  and never unwinds a review round that came back clean.
- `worktree-setup.sh` — *seeded once, then repo-owned* — this repo's per-worktree setup,
  run inside a freshly created feature worktree by `../agentTooling/feature-start.sh`
  before the gate: a venv (one per worktree — never shared, since an editable install
  points at whichever tree ran it last), `npm install`, a dev port no other worktree
  uses. It ships as a no-op skeleton whose comments list those; a non-zero exit stops the
  start with the worktree left in place.
- `open-session.sh` — *seeded once, then repo-owned* — how this repo opens a coordinator
  session inside a new feature worktree. `../agentTooling/feature-start.sh --open` runs it
  with the worktree's absolute path as its only argument; a session launched there is
  billed to the feature's branch and needs no pin, while the session that ran the start
  stays a router and is never pinned (`../agentTooling/LIFECYCLE.md`, rule 1). It ships
  opening a Terminal.app window running `claude`; swap in a tmux window, an iTerm profile
  or an editor. Advisory: a non-zero exit is reported and the feature is already started.
  It is the one file in the tree that may spell `cd <path> && <command>`, because that
  string is handed to Terminal.app and not to the Bash tool — and at `template-version: 3`
  the path crosses **two named escaping layers** on the way there: `shell_single_quote`
  (`'` → `'\''`), because the shell Terminal.app starts word-splits what it gets and a
  checkout under a path with a space would otherwise open the session in the wrong
  directory; then `applescript_escape` (`\` → `\\`, `"` → `\"`), because that command line
  is itself written into an AppleScript string literal. Version 2 had the first layer
  only, as a bare pair of quotes, so a path holding `'`, `"` or `\` still broke it — and a
  session is billed to the branch of the directory it was launched in, so the mistake was
  silent and landed in the ledger as somebody else's money. **Keep both layers in any
  replacement body**: whichever launcher a repo swaps in, the path reaches it through
  somebody's quoting.
- `features/<slug>/routing.json` — the **router** that started that feature (the session
  that ran `feature-start.sh`), written by that script from the router's own transcript
  and committed in the `<slug>: start` commit. It is the link from router to feature, in
  git before the transcript can expire:
  `{ session_id, launched_in, git_branch, model, started_at, ended_at, duration_s,
  cost_usd, features_started[{slug, at}], captured_at }`. The router's spend is routing
  overhead, reported per repo by `../agentTooling/analysis/report.py --all` and never
  attributed to or split across the features it opened. It lives inside the feature it
  links, so a router that opened three features leaves three copies and no two features
  ever write one path; the report keeps the copy with the latest `captured_at`. Committed,
  small, and rewritten whole by each refresh. Records written before that rule sat in a
  `routing/` directory here, one file per router shared by every feature it started;
  `sync-plans.sh` moves them (`../agentTooling/analysis/routing.py --migrate`) and tells
  you to commit the moves.
- `review-report.md` — the review executor's verdict, whose **first line** is
  `Verdict: clean` or `Verdict: escalated` (what `run-review.sh` reads to decide whether
  the round can be closed), and the body of the PR `feature-close.sh` opens. On an
  escalated round the runner copies it to `features/<slug>/escalations/<review-stem>.md`,
  where it becomes the rework brief. Gitignored and regenerated every batch, like
  `gate-report.txt`.
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
./agentTooling/run-batch.sh    # build, verify, review — and the close on a clean round
./agentTooling/run-plans.sh    # build pass only
./agentTooling/run-verify.sh   # verify pass only
./agentTooling/run-review.sh   # review pass only: the round's verdict, and nothing after it
./agentTooling/feature-close.sh <slug>   # PR, capture, merge request — from the worktree
```

Each accepts an optional feature slug as its first argument; omitted, the runner infers
it from whichever feature has work queued, and errors if more than one does. See
`../agentTooling/RUNNER.md` → "Choosing a feature".

Shared documentation:

- `../agentTooling/RUNNER.md` — how execution works: state folders, resume semantics, the
  progress and `.stream.jsonl` logs, how to read a failure.
- `../agentTooling/AGENT_PLANS.md` — how to author a plan.
