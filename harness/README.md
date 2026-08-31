# harness

A method-agnostic experiment harness: it builds one feature several ways from a frozen
fixture, reviews and reworks every tree the same way, scores each run, and appends the
numbers to a ledger. `EXPERIMENTS.md` says how to think about an A/B; this is how to run
one without paying a session to do it by hand.

It replaces the session that ran the WP7 delegation experiment manually, which cost $238
across five features — as much as both arms it was measuring — and broke isolation
twice: it reused one arm's review plan on the other tree, and cross-checked the two trees
to write each other's rework list. Both are ruled out here structurally: a run's inputs
are its fixture and its method and nothing else, the review brief exists before any
method runs, the rework reads only its own tree's findings, and no stage reads across
worktrees. There is no cross-check stage.

`SPEC.md` is the design record and the contract. Read it before changing anything here.

## Contents

| File | What it is |
|---|---|
| `SPEC.md` | The build spec and design record: nouns, stages, naming, file shapes, the pinned facts every part of this depends on. Where this README and the code disagree with it, it is the one that decided. |
| `run.sh` | The driver. `run.sh <experiment-dir> [--only <fixture>:<method>[:<n>]] [--from <stage>] [--dry-run] [--no-cleanup] [--consumer <path>]`, run from the consuming repo root. Walks the eight stages per cell, writes the state file and the ledger row, renders the scorecard, removes the worktree and keeps the branch. |
| `lib.sh` | Everything a stage or a method would otherwise implement twice: naming, template filling, the manifest skeleton, gate running and counting, findings parsing, state-file writes, and `harness_claude` — the **single** seam every model call goes through. Sourced, never run. |
| `scorecard.py` | `scorecard.py <experiment-dir>` — renders `results.jsonl` into `SCORECARD.md`. Stdlib only, like `analysis/`. Reprices nothing; every dollar in it was frozen at capture time. |
| `new-fixture.sh` | `new-fixture.sh <name> --repo <path> --base <ref> --spec-repo <path> --spec-ref <ref> --spec-path <file> [--sections …] [--setup '<cmd>']… [--gate-*] [--branch-stem …]` — scaffolds `plans/experiments/fixtures/<name>/`: resolves both refs to full commit ids and writes `fixture.json` pinned to them, verifies the spec path exists at that commit and the gate script at base, and writes `facts.md`, `review-brief.md` and `accept/accept.py` as stubs that fail loudly (a `@@TODO@@` placeholder aborts any run at the brief stage; the stub probe exits 1). |
| `check-fixture.sh` | `check-fixture.sh <name>` — one line per check, exit = failures: every field the stages read, both commits resolve, spec path at the spec commit, gate script at base, the three hand-written files are present, not stubs, and use only the placeholders the harness fills, `accept.py` compiles. `new-experiment.sh` runs it on every fixture it names. |
| `new-experiment.sh` | `new-experiment.sh <name> --fixtures <a,b> --methods <x,y> --prediction '<text>' [--repeats N] [--noise-band 15] [--compare-to <path>] [--no-review\|--no-rework\|--no-accept] [--override <fixture>=<stem>]…` — scaffolds `plans/experiments/<name>/{experiment.json,README.md}`. Checks every fixture (`check-fixture.sh`) and every method directory, computes each cell's branch and **refuses if it already exists** locally or on the fixture repo's remote (so a replay needs `--override`, which becomes `branch_stem_override`). The prediction is required. |
| `publish.sh` | `publish.sh <experiment-dir> [--branch <name>]` — after a run: re-renders the scorecard, commits only the experiment directory (`<experiment>: run <n> results`, `n` = ledger rows; `logs/` stays gitignored), pushes with `-u`, and opens the PR through `HARNESS_GH_BIN` with `SCORECARD.md` as the body unless one is already open for the branch. On the consumer's default branch it first creates `<experiment>Results` (or `--branch`); on any other branch it commits there. |
| `templates/` | The three prompts the harness itself owns: the isolation paragraph pasted into every brief, and the review and rework preambles. See `templates/README.md`. |
| `methods/` | One directory per way of turning a worktree at `base` into an open PR — `plans`, `direct`, and the `null` test double. Adding a method is adding a directory. See `methods/README.md`. |
| `tests/smoke.sh` | The whole pipeline against a throwaway repo with a fake `claude` and a fake `gh`: no network, no money. See `tests/README.md`. |

Fixtures and experiments do **not** live here — they name another repo's commits, which
is a project fact, so they live in the consuming repo under
`plans/experiments/fixtures/<name>/` and `plans/experiments/<experiment>/`.

## Adding one, from a feature description to a ledger row

Everything a script can do is scripted; the three files it cannot write are the ones
that carry judgement, and each is named below. Run all of it from the consuming repo
root — for a repo whose main checkout should stay untouched, from a worktree of it on a
branch (`git worktree add -b <experiment>Results ../<repo>-<experiment>Results origin/main`).

1. **Pick the pins.** `base` is a commit on the feature repo's `main` that every arm
   branches from — the current `origin/main` for a new feature, or the earlier arms'
   merge-base for a replay. `spec` is a commit in the spec's repo (a tag, or `main`
   after the spec landed) and the sections the delegate must read.
2. **Scaffold the fixture** — resolves the refs to full ids and verifies what it can:
   ```bash
   ./agentTooling/harness/new-fixture.sh <fixture> \
       --repo ~/dev/<featureRepo> --base origin/main \
       --spec-repo ~/dev/<specRepo> --spec-ref v0.2.0 --spec-path INTEGRATION.md --sections 5.1,12 \
       --setup 'python3.13 -m venv .venv' --setup '.venv/bin/python -m pip install -q -e ".[dev]"' \
       --gate-minutes 2
   ```
   Defaults: gate `./plans/gate.sh`, green on `all checks passed`, branch stem = the
   fixture name. It refuses a ref that does not resolve, a spec path absent at that
   commit, and a base with no gate script.
3. **Write the three files** in `plans/experiments/fixtures/<fixture>/` — *before* any
   arm runs, from the spec only: `facts.md` (scope boundary and toolchain, handed to every
   method verbatim), `review-brief.md` (what the review checks — the scoring instrument),
   `accept/accept.py` (the real CLI or routes, never the arm's tests). Then the `@@TODO@@`
   lines in the two READMEs. Existing fixtures are the models.
4. **Check it:** `./agentTooling/harness/check-fixture.sh <fixture>` — green only when
   the stubs are gone.
5. **Scaffold the experiment**, prediction first:
   ```bash
   ./agentTooling/harness/new-experiment.sh <experiment> --fixtures <fixture> --methods direct,plans \
       --repeats 1 --prediction 'direct reaches PR-open within ±15% of plans' \
       --compare-to plans/experiments/<earlier>/SCORECARD.md
   ```
   It refuses any cell whose branch already exists; a replay of a built feature takes
   `--override <fixture>=<newStem>`. Replace the `@@TODO@@` paragraph in its README.
6. **Run:** `--dry-run` first, then the run. A red gate at setup means the fixture is
   broken, not the method.
   ```bash
   ./agentTooling/harness/run.sh plans/experiments/<experiment> --dry-run
   ./agentTooling/harness/run.sh plans/experiments/<experiment>
   ```
7. **Publish:** `./agentTooling/harness/publish.sh plans/experiments/<experiment>` —
   commits the ledger, scorecard and state, pushes, opens the PR. Add a results section
   to the experiment's README (the row against the prediction) and commit that on the
   same branch. The arm branches and their PRs stay as cost records; do not merge an
   arm's PR unless the experiment picks it.

A new **method** is a directory under `methods/` with `template.md`, `run.sh` and a
README (see `methods/README.md`); nothing else knows its name, and `new-experiment.sh`
accepts it as soon as the directory exists.

## Running one

```bash
./agentTooling/harness/run.sh plans/experiments/<experiment> --dry-run   # read it first
./agentTooling/harness/run.sh plans/experiments/<experiment>
./agentTooling/harness/publish.sh plans/experiments/<experiment>         # commit, push, PR
```

`--dry-run` prints every command it would run with the resolved branch names, worktree
paths and stage list, and runs nothing. `--from <stage>` re-enters a run at
`setup | brief | method | review | rework | accept | capture | record` off the state
file. `--only` narrows to one cell. `--consumer <path>` overrides the consuming repo
root, which is otherwise the parent of `agentTooling/` — needed only when the harness
is not yet vendored into the repo holding the fixtures.

Requires `claude`, `jq`, `git` and `python3`; `gh` for the PR check. Two environment
seams matter: `HARNESS_CLAUDE_BIN` (default `claude`) and `HARNESS_GH_BIN` (default
`gh`). `HARNESS_MODEL` (default `opus`), `REVIEW_BUDGET_USD` (`$7.00`) and
`REWORK_BUDGET_USD` (`$10.00`) are the other knobs.

## Stages, per (fixture, method, repeat)

Sequential; each stage's start, end and outcome are written to
`<experiment-dir>/state/<branch>.json`.

1. **setup** — fetch, add the worktree at `base`, run `fixture.setup`, run the gate and
   require `gate.green` (a red gate stops the run: the fixture is broken, not the
   method), add the read-only spec worktree, write the manifest skeleton with
   `session_window.from` open.
2. **brief** — fill `methods/<m>/template.md` into `<tree>/plans/features/<slug>/BRIEF.md`.
   Generated from fixture + method only.
3. **method** — `methods/<m>/run.sh`; on exit 2 wait out the usage limit and retry once;
   on exit 1 record `method_failed` and skip to capture. On success verify the PR
   exists, close the manifest window, commit that one edit, push.
4. **review** — a fresh `claude` in the tree with `templates/review-preamble.md` plus the
   fixture's `review-brief.md`: fix what is local, escalate the rest, write
   `plans/features/<slug>/review/findings.md`, gate, commit `review: <fixture>`, push.
   Its own manifest `<slug>-review` with its own window.
5. **rework** — only when `findings.md` escalates something. One `claude` with
   `templates/rework-preamble.md` plus that file and nothing else. Manifest
   `<slug>-rework`.
6. **accept** — the fixture's `accept/accept.py <tree>`; then the gate once more, whose
   counts become the checklist-green counts.
7. **capture** — `analysis/capture_planning.py` then `analysis/report.py` for each of the
   three slugs, **run from the worktree's own vendored copy** (its session root is the
   cwd the sessions ran from); the dollars go in the row and `report.{json,md}` are
   deleted. `planning.json` is committed onto the branch, since the transcripts behind it
   expire and the branch is the cost record.
8. **record** — append the ledger row, re-render `SCORECARD.md`, and remove the feature
   worktree unless `--no-cleanup`. The branch and the PR stay.

## The method contract

The only thing the harness knows about a method:

- **Input** — a worktree on its branch at `base`, gate rehearsed green, `fixture.setup`
  run, the manifest skeleton at `plans/features/<slug>/README.md` with
  `session_window.from` set, and the generated brief file.
- **Output** — a PR open from the branch to `main` whose body's first line says *one arm
  of an experiment — do not merge until it picks a winner*, and the manifest's `plans`
  array populated (or left `[]` for a method with no plans).
- **Exit** — `0` PR-open, `2` usage-limit stop (resumable), `1` work failure (do not
  retry).
- **Never** — read another worktree, read `plans/experiments/`, edit `agentTooling/`, or
  run git/pip/npm outside `<tree>`. The harness passes these rules into the brief, so
  `run.sh` does not repeat them.
- **No method has a review of its own that the harness relies on.** Every tree goes
  through the harness review, `direct` included. A method may include a self-review in
  its brief — that is a method variant, and the harness review still runs after it.

## File shapes

### `fixture.json` — `plans/experiments/fixtures/<name>/fixture.json`

`{ name, repo{path, remote}, base, spec{repo, commit, path, sections[]}, setup[], gate{command, green, minutes}, branch_stem, diff_lines }`

- `name` — the fixture directory's own name; the spec worktree is `<spec.repo>-fx-<name>`.
- `repo.path` — absolute path to the repo's **main checkout**; the harness only ever
  fetches from it and adds worktrees beside it. `repo.remote` — default `origin`.
- `base` — the commit every run branches from.
- `spec` — a commit in the spec's own repo, checked out **detached and read-only** at
  `<spec.repo>-fx-<name>`, so a fixture stays valid after the spec's branch merges or
  moves. `spec.sections` are the sections the brief tells the delegate to read.
- `setup[]` — shell commands run inside the fresh worktree before the gate rehearsal.
- `gate.command` — run from the worktree; `gate.green` is the substring the harness
  greps the gate's last lines for; `gate.minutes` is quoted into briefs.
- `branch_stem` — the branch is `<branch_stem><Method><n>` (§4 of `SPEC.md`).
- `diff_lines` — informational: the recorded size of the feature, for the ledger.

### `experiment.json` — `plans/experiments/<experiment>/experiment.json`

`{ name, fixtures[], methods[], repeats, stages{review, rework, accept}, noise_band_pct, prediction, compare_to, branch_stem_override{<fixture>: <stem>} }`

`prediction` is required and is copied into the scorecard before any run — the
checklist-first rule from `EXPERIMENTS.md`. `stages` turns off a stage for the whole
experiment; `noise_band_pct` is the band under which a cost difference reads as a tie;
`compare_to` is a path to whatever earlier scorecard this run is answering.
`branch_stem_override` is optional and rarely needed: it replaces one fixture's
`branch_stem` for this experiment, which is how a replay of a feature that has already
been built stays off the recorded arm's branch. Without it the harness would refuse to
start — a branch that already exists and that the cell has no state for is treated as a
collision, since continuing would append this arm's commits to whatever that branch is
the record of (`HARNESS_ALLOW_EXISTING_BRANCH=1` overrides, and should be rare).

### The ledger row — one JSON object per line in `results.jsonl`

`{ experiment, fixture, method, repeat, branch, slug, pr_url, base, spec_commit, model, t_setup_start, t_method_start, t_pr_open, t_review_end, t_rework_end, t_green, cost_method_usd, cost_method_reported_usd, cost_review_usd, cost_rework_usd, cost_green_usd, cost_lost_usd, review_fixed, review_escalated, rework_ran, gate_counts_pr_open, gate_counts_green, accept_pass, accept_lines[], method_failed, interventions[{t, what}], harness_version }`

Every `t_*` is UTC with a `Z`, the convention `analysis/README.md` makes load-bearing.
`cost_green_usd` is the sum of `cost_method_usd`, `cost_review_usd` and `cost_rework_usd`. `cost_lost_usd` is spend from a killed attempt's orphaned open manifest window, priced when the stage re-runs and kept out of every method figure. `cost_method_reported_usd` is the `total_cost_usd` the method's first `claude -p` session reported for itself, kept beside the captured figure as a cross-check: captured below 90% of it (or zero against a non-zero report) makes the capture stage warn. A `planning.json` stamped before its slug's current manifest window opened is a stale freeze from an earlier attempt — a reused branch, or a stage a `--from` resume re-ran — and is rebuilt with `--recapture`. `gate_counts_*` are whatever the
gate printed, as a string. `harness_version` is the agentTooling commit that ran it.

The state file `<experiment-dir>/state/<branch>.json` carries the same fields as they
are filled, plus a `stages` object of `{start, end, outcome}` per stage. `--from` reads
it, and a finished run's state file stays.

## Naming

- Branch: `<branch_stem><Method><n>` in bare camelCase, method capitalised, `n` omitted
  when `repeats` is 1 — `exportStoreDirect`, `exportStorePlans2`. **Never a `user/`
  prefix**: `capture_planning.py` matches the manifest's `branches` entry literally
  against each session's `gitBranch`, and a mismatch silently reports `$0.00`.
- Slug: the branch in kebab-case — `export-store-direct`, `export-store-plans-2`; the
  review and rework manifests append `-review` / `-rework`.
- Worktree: `<repo.path>-<branch>`. Spec worktree: `<spec.repo>-fx-<fixture>`.
