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
| `EXPERIMENTS.md` | How to think about an A/B: what is measured, the checklist written first, arms as pinned worktrees, what counts as noise, and what the pilots established. This directory is how one is run. |
| `SPEC.md` | The build spec and design record: nouns, stages, naming, file shapes, the pinned facts every part of this depends on. Where this README and the code disagree with it, it is the one that decided. |
| `run.sh` | The driver. `run.sh <experiment-dir> [--only <fixture>[:<method>[:<arm>][:<n>]]] [--only <program>[:orchestrator[:<arm>][:<n>]]] [--from <stage>] [--dry-run] [--no-cleanup]`, run from the consuming repo root with that repo's own vendored harness (it refuses to run from any other copy — "Repositories by URL"). Walks the eight stages per cell (fixture × method × arm × repeat), pins the arm's agentTooling version at setup (or, for a base arm, cuts the worktree at the arm's commit of the measured repository; both kinds together are refused), writes the state file and the ledger row, renders the scorecard, removes the worktree and keeps the branch. For each program in `experiment.json`'s `programs` (program × arm × repeat) it sources `program-stages.sh` and walks the program stages `setup brief loop collect review rework accept capture record` ("Program cells" below); `--only` selects a program the same way as a cell, the program name in the fixture's place and the literal `orchestrator` in the method's. `--from` accepts the union of the cell and program stage names. |
| `program-stages.sh` | The program cell's stages, sourced by `run.sh`, never run: the orchestrator turns (`claude -p --session-id`, then `--resume`), the per-feature loop (brief, worktree, implementer, tip and dependency check), the collect turn, the per-feature review/rework/accept/capture through `run.sh`'s own cell functions, the overhead pricing and the `kind: "program"` row. Depends on `orchestration-start.sh` and `analysis/manifest.py --orchestration` of the arm's pinned copy (the record's path layout `agentTooling/self/orchestrations/<PSLUG>/README.md`), on the titles and placeholders of `templates/program-*.md`, and on `scorecard.py` reading the row it writes. |
| `program_cost.py` | `program_cost.py <analysis-dir> --session <id>[@<from-ts>]… --from <ts> --to <ts> [--projects-root <dir>]` — prices the orchestrator session(s) inside a window with the **driver's** `capture_planning.price_session_in_window` (imported by path from `<analysis-dir>`) and prints one dollar figure, four decimals. Exit 0 a figure was printed, 2 a usage error. An id with no transcript prices at 0 with a stderr warning; a partial total (a model without a rate) warns too. |
| `lib.sh` | Everything a stage or a method would otherwise implement twice: naming, template filling, the manifest skeleton, gate running and counting, findings parsing, state-file writes, `harness_fixture_repo` / `harness_check_measured_repo` / `harness_require_own_driver` (the measured repository is the consumer, a `repo` block naming another is refused, and the running harness must be the consumer's own vendored copy), `harness_fixture_spec_repo`, `harness_resolve_repo` (a repository URL to a checkout on this machine — override, search, clone — used only for the two external read-only inputs: `spec.url` and the agentTooling pin), `harness_replace_literal` (the one literal substitution `harness_fill_template` uses — never `${t//pat/$value}`, which bash 5.2's `patsub_replacement` rewrites at an `&` in the value), `harness_resolve_commit` (a base that is on no fetched branch is fetched by sha once, no ref created), `harness_forge_for` / `harness_forge_run` / `harness_pr_url` / `harness_pr_open` / `harness_branch_pushed` / `harness_branch_has_commits` (the forge seam: the driver's `forge.sh` pointed at a checkout), `harness_pin_agent_tooling` (an arm's pin), `harness_experiment_arm_kind` (an experiment's one arm kind — `agent_tooling`, `base_arms` or none — refusing both together; `base_arms` with `programs` is refused by its callers, `new-experiment.sh` and `run.sh`) and `harness_experiment_arms` (one `<label> <sha>` line per arm of that kind, or `- -`), and `harness_claude` — the **single** seam every model call goes through, which appends `--effort "$HARNESS_EFFORT"` when that variable is set (validated against `HARNESS_EFFORT_LEVELS` on source; `harness_effort_dry` renders the dry-run fragment). Sourced, never run. |
| `scorecard.py` | `scorecard.py <experiment-dir>` — renders `results.jsonl` into `SCORECARD.md`. Stdlib only, like `analysis/`. Reprices nothing; every dollar in it was frozen at capture time. Ledger rows with `kind: "program"` ("File shapes" below) are split off first: every cell section runs on the ordinary rows alone, and a `## Programs` section follows the cost-band section — a table of program cells, a table of features per cell, per-arm means once a program has repeats, and one comparison line per program and arm pair under the band heading (to PR-open and to green on the group figures, then PRs open, green and overhead %). A ledger with no program row renders exactly as it did before they existed. A `## Reading before the first edit` table follows the Runs table, one row per cell row carrying the reading fields (`—` for not measured); a ledger without them renders exactly as before. A base arm is labelled `<arm> (base <sha7>)` and the header lists `base arms: <label>=<sha7>, …`. |
| `new-fixture.sh` | `new-fixture.sh <name> --base <ref> --spec-ref <ref> --spec-path <file> [--spec-repo <url or checkout>] [--sections …] [--setup '<cmd>']… [--gate-*] [--branch-stem …]` — scaffolds `plans/experiments/fixtures/<name>/` for the consuming repo it runs in: the fixture measures that repository, so it writes no `repo` block (only `repo.remote` when `--remote` is not `origin`; an optional `--repo` must be the consumer or is refused). `--spec-repo` is only for a spec living in another repository (a checkout contributes its `origin`; recorded as `spec.url`); omitted, the spec is taken from the consumer. Resolves both refs to full commit ids and writes `fixture.json` pinned to them, verifies the spec path exists at that commit and the gate script at base, and writes `facts.md`, `review-brief.md` and `accept/accept.py` as stubs that fail loudly (a `@@TODO@@` placeholder aborts any run at the brief stage; the stub probe exits 1). |
| `check-fixture.sh` | `check-fixture.sh <name>` — one line per check, exit = failures: a fixture whose `repo` block names a repository other than the consumer dies at once, then every field the stages read, the base resolves in the consumer's own checkout (a base missing there is fetched by sha once before it counts as unresolved — a prep commit on no fetched branch) and the spec in the consumer or, when the fixture names `spec.url`, in the checkout that resolves to (cloned if need be, read-only; a bare `spec.repo` path passes with a warning naming `spec.url` to add), both commits resolve, spec path at the spec commit, gate script at base, the three hand-written files are present, not stubs, and use only the placeholders the harness fills, `accept.py` compiles. `new-experiment.sh` runs it on every fixture it names. |
| `new-experiment.sh` | `new-experiment.sh <name> [--fixtures <a,b> --methods <x,y>] [--programs <p,q>] --prediction '<text>' [--agent-tooling <label>=<ref>,…] [--base-arms <label>=<ref>,…] [--repeats N] [--noise-band 15] [--compare-to <path>] [--no-review\|--no-rework\|--no-accept] [--override <fixture-or-program>=<stem>]…` — scaffolds `plans/experiments/<name>/{experiment.json,README.md}`. Checks every fixture (`check-fixture.sh`) and every method directory, pins each arm's ref to a full agentTooling commit id, computes each cell's branch and **refuses if it already exists** locally or on the consumer's remote (so a replay needs `--override`, which becomes `branch_stem_override`). The prediction is required. `--fixtures` and `--methods` go together; at least one of `--fixtures` / `--programs` is required. For each `--programs` name it requires a bare-camelCase name that is not a fixture's, runs `harness_program_check` on `plans/experiments/programs/<name>/program.json`, refuses an arm whose pinned agentTooling lacks the version floor (`orchestration-start.sh`, `templates/plans/ORCHESTRATOR_BRIEF.md`; an unpinned experiment is checked against the consumer's vendored copy), and collision-checks the program branch and every feature branch. `--base-arms` resolves each ref in the measured repository's own checkout (a sha missing locally is fetched by sha from `origin` once) and refuses one that does not resolve there; it refuses `--agent-tooling` together with `--base-arms` (one kind of arm per experiment) and `--base-arms` with `--programs` (a program pins its own `base`). |
| `publish.sh` | `publish.sh <experiment-dir> [--branch <name>]` — after a run: re-renders the scorecard, commits only the experiment directory (`<experiment>: run <n> results`, `n` = ledger rows; `logs/` stays gitignored), pushes with `-u`, and opens the PR through the forge seam (the driver's `forge.sh` — in the results PR's case the consumer's own vendored copy, since the harness is that — or `HARNESS_FORGE_BIN`) with `SCORECARD.md` as the body unless one is already open for the branch (the results PR opens on the measured repository itself, from its own vendored harness). On the consumer's default branch it first creates `<experiment>Results` (or `--branch`); on any other branch it commits there. |
| `templates/` | The prompts the harness itself owns: the isolation paragraph pasted into every brief, the review and rework preambles, and a program cell's three orchestrator prompts (`program-brief.md`, `program-feature.md`, `program-collect.md`). See `templates/README.md`. |
| `methods/` | One directory per way of turning a worktree at `base` into an open PR — `plans`, `direct`, `direct-bare` (`direct` without its procedure steps, the control that measures their cost), and the `null` test double. Adding a method is adding a directory. `orchestrator` is a reserved name (a program cell's method) and has no directory. See `methods/README.md`. |
| `reading_metrics.py` | `reading_metrics.py <analysis-dir> <tree> --from <ts> --to <ts> [--projects-root <dir>]` — prints one JSON line `{read_files_before_edit, read_bytes_before_edit, readme_bytes_read, transcripts}` (the three figures integers, or `null` when no transcript fell in the window) for a cell's worktree. Imports the driver's `capture_planning.py` and `transcript.py` by path from `<analysis-dir>`. Exit 0 a figure was printed, 2 a usage error. Definitions in the module's docstring and "The ledger row" below. |
| `tests/smoke.sh` | The whole pipeline against a throwaway repo with a fake `claude` and a fake `forge.sh`: no network, no money. Prices an ordinary `direct` cell end to end (implementer, review and rework each non-zero) and runs `stages {review: false}` as a whole run. Covers a program cell too (two fixtures, the second dependent; a failed implementer; `--only` and `--from record`; the floor refusal; the lib and cost unit checks). See `tests/README.md`. |
| `tests/scorecard-arms.sh` | `scorecard.py`'s arm-vs-arm and method-vs-method comparison lines, the noise-band wording, and the unpinned row's never being paired with a pinned one, on a hand-built ledger. See `tests/README.md`. |
| `tests/scorecard-programs.sh` | `scorecard.py`'s program section on a hand-built ledger of `kind: "program"` rows: the Programs and per-feature tables, the `✓`/`✗` dependency mark, the program comparison line and its counts suffix, program rows staying out of the cell sections, and the byte-identity of a program-free ledger's scorecard against `tests/scorecard-programs.cells.md`. See `tests/README.md`. |
| `tests/arm-base.sh` | Base arms, offline: `lib.sh`'s arm-kind helpers on hand-written `experiment.json`s (none, `agent_tooling`, `base_arms`, both refused, malformed) and the scorecard's base-arm header, labels and comparison lines. The end-to-end half — `new-experiment.sh --base-arms` resolving and refusing, `run.sh` refusing a hand-edited experiment and cutting a cell's worktree at the arm's commit — is `tests/smoke.sh` section 8b. See `tests/README.md`. |
| `tests/reading-metrics.sh` | `reading_metrics.py` on hand-built transcripts: the window, the first edit, distinct files, bytes, README bytes, subagents, and `null` when not measured. See `tests/README.md`. |

Fixtures and experiments do **not** live here — they pin the consuming repo's own commits,
which is a project fact, so they live in the consuming repo under
`plans/experiments/fixtures/<name>/` and `plans/experiments/<experiment>/`. **An
experiment runs from, and lives on, the repository it measures** (`EXPERIMENTS.md` → "The
rule"): the cells are worktrees of the consuming repo's own checkout, the arm PRs and the
results PR open on it, and the harness is its own vendored copy. A fixture or program that
names another repository is refused.

## Adding one, from a feature description to a ledger row

Everything a script can do is scripted; the three files it cannot write are the ones
that carry judgement, and each is named below. Run all of it from the consuming repo
root — for a repo whose main checkout should stay untouched, from a worktree of it on a
branch (`git worktree add -b <experiment>Results ../<repo>-<experiment>Results origin/main`).

1. **Pick the pins.** `base` is a commit on the consuming repo's `main` that every arm
   branches from — the current `origin/main` for a new feature, or the earlier arms'
   merge-base for a replay. `spec` is a commit (a tag, or `main` after the spec landed)
   in the consuming repo, or in another repository when the spec is owned elsewhere, and
   the sections the delegate must read.
2. **Scaffold the fixture** — resolves the refs to full ids and verifies what it can:
   ```bash
   ./agentTooling/harness/new-fixture.sh <fixture> \
       --base origin/main --spec-ref v0.2.0 --spec-path INTEGRATION.md --sections 5.1,12 \
       --setup 'python3.13 -m venv .venv' --setup '.venv/bin/python -m pip install -q -e ".[dev]"' \
       --gate-minutes 2
   ```
   Defaults: gate `./plans/gate.sh`, green on `all checks passed`, branch stem = the
   fixture name. The fixture measures the repository it is scaffolded in, so `--repo` is
   not needed (given, it must be the consumer or is refused); add `--spec-repo <url or checkout>` only when the spec lives in another
   repository (a checkout path contributes its `origin`; that repository is read, never
   built in). It refuses a ref that does not resolve, a spec path absent at that commit,
   and a base with no gate script.
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
   `--override <fixture>=<newStem>`. To A/B two agentTooling versions, add
   `--agent-tooling before=<sha or tag>,after=<sha or tag>` ("Arms" below). To A/B two commits of the measured repository instead, add
   `--base-arms old=<sha>,new=<sha or ref>` (one kind of arm per experiment). Replace the
   `@@TODO@@` paragraph in its README.
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
paths and stage list, and runs nothing — a repository it would have to clone is named,
not cloned. `--from <stage>` re-enters a run at
`setup | brief | method | review | rework | accept | capture | record` off the state
file (a program cell's stages are `setup | brief | loop | collect | review | rework |
accept | capture | record`, "Program cells" below). `--only <fixture>[:<method>[:<arm>][:<n>]]`
narrows to one cell (the arm is letters, the repeat digits); `--only
<program>[:orchestrator[:<arm>][:<n>]]` narrows to one program cell. `--from loop` or
`--from collect` on an ordinary cell skips all of its stages (they are not its stages);
`--from method` on a program cell means `loop`. The consuming repo root is the parent of
`agentTooling/`, and the harness must be that repo's own vendored copy: `run.sh`,
`new-experiment.sh`, `check-fixture.sh`, `new-fixture.sh` and `publish.sh` refuse to run
from any other checkout ("the harness runs from the measured repository's own
agentTooling/; bring it up to date there (agentTooling/update.sh) instead of driving it
from another checkout"). `--consumer <path>`, which names a root, is a development flag
and is refused unless that root's `agentTooling/` is the running copy.

Requires `claude`, `jq`, `git` and `python3`; `gh` behind `forge.sh` for the PR check.
The environment seams: `HARNESS_CLAUDE_BIN` (default `claude`) is the model;
`HARNESS_FORGE_BIN` is the forge adapter (unset: the **driver's** `forge.sh`, pointed at
the checkout being asked about — see "The forge seam"); `HARNESS_REPO_ROOTS`,
`HARNESS_REPO_DIR_<NAME>` and `HARNESS_AGENT_TOOLING_URL` are how the two external
read-only inputs, a spec repository named by `spec.url` and the agentTooling an arm is
pinned to, are found on this machine ("Repositories by URL"). `HARNESS_MODEL` (default `opus`),
`HARNESS_EFFORT` (default empty: the CLI's own effort; otherwise one of `low`, `medium`,
`high`, `xhigh`, `max`, passed to every model call as `claude --effort <level>` by
`harness_claude`, shown by `--dry-run`, and recorded as `effort` in both row shapes;
any other value is refused when the harness starts, naming the levels),
`REVIEW_BUDGET_USD` (`$7.00`) and `REWORK_BUDGET_USD` (`$10.00`) are the other knobs;
`PROGRAM_BUDGET_USD` (unset: no cap) caps each orchestrator call of a program cell.

## Repositories by URL

**The repository a fixture or program builds in is never resolved.** It is the consuming
repository the harness is vendored in (`CONSUMER_ROOT`, remote `origin` unless
`repo.remote` names another of its remotes): not searched for, not cloned, never named by
a path. The cell worktrees are added from that checkout. Only the two **external,
read-only** inputs go through a resolver, because neither is where the experiment runs or
lives:

- a spec that lives in another repository, named by `spec.url` (absent: the spec worktree
  is added from the consumer at `spec.commit`);
- the agentTooling an arm is pinned to, at `HARNESS_AGENT_TOOLING_URL` (default
  `update.sh`'s `DEFAULT_REMOTE`).

A URL, never a path: a path is one machine's, and the first fixtures —
`/Users/<owner>/dev/vinylCatalogue` — could run nowhere else. For those two, every script
that needs a checkout asks `harness_resolve_repo` (`lib.sh`), which answers, in order:

1. `HARNESS_REPO_DIR_<NAME>=<path>` in the environment — `NAME` the repository's name in
   upper case, anything but `[A-Z0-9]` as `_` (`vinylCatalogue` → `VINYLCATALOGUE`);
2. a URL that is itself a local checkout;
3. the fixture's optional path hint (`spec.repo` — the pre-URL shape, kept as a hint and,
   with a warning, honoured on its own when it exists here);
4. a **main** checkout under one of `HARNESS_REPO_ROOTS` (colon-separated; default the
   directory holding the consuming repo — `~/dev` on a laptop, `/home/user` in a cloud
   container) whose `origin` names the same repository: `owner/repo` compared
   case-insensitively with `.git` dropped, so a lowercase cloud clone matches, and the
   harness's own worktrees beside the clone (same origin) are never picked;
5. a fresh clone into the first root, named after the repository.

Both are only read: the harness fetches from them and adds a detached spec worktree or
extracts a pinned tree, and pushes nothing to either.

## The forge seam

The harness asks the forge two things — is a PR open for this head, open one — and asks
them through `forge.sh pr-find` / `pr-open` (`gh api` REST), never `gh pr view` /
`gh pr create`: a Claude Code cloud container's proxy refuses the GraphQL those two use,
and REST is the one path that works there and on a laptop alike (`forge.sh`'s header).
**Measuring is the driver's, building is the arm's.** The arm's own `agentTooling/` only
builds (the method's implementer or plans run, its `plans/pr.sh`); the harness — the copy
`run.sh` lives in — does the lookup and the bookkeeping. `harness_forge_for` is the
driver's `forge.sh` (or `HARNESS_FORGE_BIN` when set, the smoke test's fake), and
`harness_forge_run` runs it from the checkout being asked about with `FORGE_CHECKOUT=<that
checkout>`, which `forge.sh` reads its `owner/repo` from in place of its own directory — the
arm's worktree for the method's PR, the consuming repo for `publish.sh`. An arm built from
a historical base may carry no `forge.sh` at all, or an old one; it makes no difference to
the lookup. (The `direct` brief still tells its *implementer* to open the PR with
`<tree>/agentTooling/forge.sh pr-open`: that is the arm building.)

**A built branch with no PR.** When a method exits 0, its branch is on `origin`, it has
commits beyond `base`, and `pr-find` finds no open PR — an August arm's `plans/pr.sh` with
`gh` unauthenticated in a cloud container — the harness opens the PR itself through the
driver's forge (`harness_pr_open`: title the cell's slug, base `HARNESS_PR_BASE`, a body
saying the harness opened it and why) instead of marking `method_failed`. It is never
silent: the row carries `pr_opened_by_harness: true` and an `interventions[]` entry naming
the PR. A method that exits non-zero, or leaves no commits beyond `base` or no pushed
branch, is still `method_failed`.

**Resuming a cell an older harness failed for want of a PR.** A cell whose state records
the method stage as `no-pr` and `method_failed` (the method built and pushed; the PR
could not be opened — vinylCatalogue's `exportStorePlansOpusMax2`) is resumed with

    agentTooling/harness/run.sh <experiment-dir> --from review

(add `--only <fixture>:<method>[:<arm>][:<n>]` to pick the cell). Because the method stage
is skipped, `run.sh` runs only the PR step instead (`do_pr_resume`): it re-adds the
worktree and spec worktree if the earlier record stage removed them, runs the same
check-then-open as above, clears `method_failed`, records `pr_opened_by_harness` and a
"resumed from no-pr" intervention, **never re-runs the method**, and then goes on to
review, rework, accept, capture and record. The capture stage re-captures the method's
cost with `--recapture` and the driver's rates. A new row is appended; the earlier
`method_failed` row stays in the ledger as the history.

## Arms: pinning an agentTooling version, or a commit

An experiment may run every cell under several agentTooling versions — the A/B
`EXPERIMENTS.md` was written for. `new-experiment.sh --agent-tooling before=<ref>,after=<ref>`
resolves each ref in the upstream checkout to a full commit id and writes
`agent_tooling: {before: <sha>, after: <sha>}`; a label is bare lower-case letters. The
cells are then fixtures × methods × arms × repeats, each on its own branch
(`<stem><Method><Arm><n>`: `exportStoreDirectBefore`, `exportStoreDirectAfter2`). At setup,
on a fresh worktree, before the fixture's own setup or any gate: the tree's `agentTooling/`
is removed, the pinned commit's tree extracted in its place (`git archive | tar`), the
**pinned** copy's `sync-plans.sh` run (drift it reports in the repo-owned stubs is logged,
not fatal — it is the fixture's state, which every arm shares), and the lot committed as
`EXPERIMENT ARM (revert before merge): pin agentTooling to upstream <sha7>` — the recipe
`EXPERIMENTS.md` → "Setting up the arms" gave by hand, so the commit can never be merged
by accident. An arm pinned to the commit the base already vendors (the control arm) changes
nothing in the tree, and its pin commit is then empty: still made, so the branch records
its version and the re-run guard below still finds it. Everything after reads the pinned
copy: the fixture's setup, the gate, the
method (a `plans` arm's `run-batch.sh` included), the review and rework passes (their
preambles are the driver's and identical across arms, but the tree's `CLAUDE.md` imports
the pinned `CONVENTIONS.md`), and the capture. The driver itself — this directory's
`run.sh` — is one version for the whole experiment. The row records `arm` and
`agent_tooling`; the scorecard compares arms pairwise within each fixture × method, to
PR-open (the method alone) and to green, each against the band. A resumed branch that
already carries its pin commit is not re-pinned; one whose earlier pin died before
committing (the tree there, the commit not) is pinned on the re-run.

A **base arm** differs by a commit of the measured repository instead.
`new-experiment.sh --base-arms <label>=<ref>,…` (or `experiment.json`
`base_arms: {<label>: <full sha>}`) resolves each ref in the measured repository's **own
checkout** (a sha missing locally is fetched by sha from `origin` once); a ref that does not
resolve there is refused, citing the rule that an experiment runs from and lives on the
repository it measures. Each cell's worktree is cut at its arm's commit instead of the
fixture's `base`; the spec pin, facts, review brief, accept probe, setup, gate, method,
review and rework are the fixture's and unchanged. The branch is `<stem><Method><Arm><n>`
as for agentTooling arms, and there is **no pin commit**. The tree's vendored
`agentTooling/` is whatever that commit carries, so a base arm also varies the agentTooling
version if the two commits vendor different ones. **One kind per experiment**: `agent_tooling`
and `base_arms` together are refused by `new-experiment.sh` and by `run.sh`
(`harness_experiment_arm_kind`), and `base_arms` with `programs` is refused too — a program
pins its own `base`. The scorecard compares base arms exactly as agentTooling arms. The row
records `arm_kind: "base"`, `arm`, and `base` as the arm's commit (`agent_tooling` empty).

## In a Claude Code cloud container

The harness runs there as it does on a laptop, given three things. **The session's
primary repository is the measured repository**: it is the consuming repo's own clone
(`/home/user/<repo>`), already carrying an up-to-date vendored `agentTooling/`, and the
harness runs from that copy. No second repository needs push access — the arm branches,
the arm PRs and the results PR are all on the measured repository. The two read-only
inputs are the only others: the spec repository (only when the fixture names `spec.url`)
and agentTooling (only for arm pins). The container's git proxy serves only attached
repositories, so if it does not already serve one of those, attach it with `add_repo`
for **read** access only; a clone or fetch of an unattached repository fails to
authenticate, which the resolver says in one line naming the repository (the default
search root is `/home/user`, and a clone elsewhere is found by `HARNESS_REPO_ROOTS` or
`HARNESS_REPO_DIR_<NAME>`). **Let the fixture's `setup[]` and the repo's `plans/cloud-setup.sh` provide the
toolchain**: `python3.13`, `uv`, node and the Playwright browsers under `/opt/pw-browsers`
are in the image, and a consuming repo's gate already reads `plans/environment.sh` for
what differs. The `claude -p` sessions the stages launch run in the container under the
session's own credentials and write their transcripts under `/root/.claude/projects/`,
where the capture stage reads them, as on a laptop.

## Stages, per (fixture, method, arm, repeat)

Sequential; each stage's start, end and outcome are written to
`<experiment-dir>/state/<branch>.json`.

1. **setup** — fetch, resolve `base` (a base that is a prep commit on a branch no clone has
   fetched is fetched by sha once — `harness_resolve_commit`, which creates no ref — before
   the run dies on it), add the worktree at `base` (a base arm's commit for a base arm), pin the arm's agentTooling version
   when the experiment names one ("Arms" above), run `fixture.setup`, run the gate and
   require `gate.green` (a red gate stops the run: the fixture is broken, not the
   method), add the read-only spec worktree, write the manifest skeleton with
   `session_window.from` open.
2. **brief** — fill `methods/<m>/template.md` into `<tree>/plans/features/<slug>/BRIEF.md`.
   Generated from fixture + method only.
3. **method** — `methods/<m>/run.sh`; on exit 2 wait out the usage limit and retry once;
   on exit 1 record `method_failed` and skip to capture. On success verify the PR
   exists (opening it when the method pushed commits and opened none — "The forge seam"),
   close the manifest window, commit that one edit, push.
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
   three slugs, **run from the driver's own `analysis/`** (measuring is the driver's,
   building is the arm's: an arm's vendored copy, from a historical base, has no rates for
   today's `opus` and `sonnet`, so it excluded those sessions and priced a $3.26 run at $0)
   with `--arm-root <worktree>`, which points the driver's scripts at the worktree's
   `plans/features/`. The transcripts are found as before: the session root is the primary
   checkout the worktree belongs to, and `claim_roots` admits the cwd the sessions ran
   from, `<repo>-<Branch>`, through the manifests' `branches`. The dollars go in the row
   and `report.{json,md}` are deleted. `do_reading_metrics` then runs `reading_metrics.py` over
   the cell's window and writes the three reading fields to the state file, before `record`. `planning.json` is committed onto the branch, since the transcripts behind it
   expire and the branch is the cost record.
8. **record** — append the ledger row, re-render `SCORECARD.md`, and remove the feature
   worktree unless `--no-cleanup`. The branch and the PR stay.

### Program cells

A **program cell** is `program × orchestrator × arm × repeat`: one orchestrator session
runs an ordered list of features (`program.json`, "File shapes") under one agentTooling
version, one implementer session per feature, and the two arms are compared as one
feature set. It has its own stages, in `program-stages.sh`; the program's state is
`<experiment-dir>/state/<programBranch>.json` and each feature's
`<experiment-dir>/state/<featureBranch>.json`. Names are in "Naming".

1. **setup** — the *program* tree: fetch, worktree at the program's `base` on the program
   branch, pin the arm, refuse a program tree whose `agentTooling` is a symlink (the
   orchestration record is written through that path; pin an arm), refuse an arm below the
   version floor (the pinned copy lacks `orchestration-start.sh` or
   `templates/plans/ORCHESTRATOR_BRIEF.md`), `program.json`'s `setup[]`, the gate
   (`program.json`'s, else the first fixture's) required green, then
   `orchestration-start.sh <PSLUG> --session <orchestrator session id>` in the pinned copy,
   committed as `<PSLUG>: start the orchestration record`.
2. **brief** — the first orchestrator call: `claude -p --session-id <S>` in the program
   tree (`--model $HARNESS_MODEL --permission-mode acceptEdits --allowedTools Bash`, plus
   `--max-budget-usd $PROGRAM_BUDGET_USD` when that is set) with
   `templates/program-brief.md`: the orchestrator's role, the ordered feature list with
   each fixture's facts, and the brief template. It replies `ready` and writes nothing.
   `t_method_start` is stamped before it. If this call fails, the loop and collect are
   skipped; capture and record still run.
3. **loop** — for each feature in order: (a) **setup** — the feature's worktree on its own
   branch, cut at the program's `base` or, for a dependent feature, at the previous
   feature's branch tip as it stood when that implementer finished (its `tip`), the arm
   pin (a dependent branch inherits its predecessor's pin commit), `fixture.setup`, the
   fixture's gate (or `program.json`'s `gate`) required green (a dependent feature whose
   predecessor's tip is red runs anyway: warning, an intervention, setup outcome
   `gate-red-ran-anyway`), the spec worktree; the
   manifest skeleton is **not** written yet. (b) **brief** — `claude -p --resume` of the
   most recent orchestrator session id with `templates/program-feature.md` (the previous
   feature's PR or failure and its implementer's report, then this feature's facts, branch,
   worktree, PR base, dependency and method); the orchestrator writes
   `<program tree>/plans/programs/<PSLUG>/briefs/<NN>-<fixture>.md` and ends its reply with
   `METHOD: <direct|plans|hand>`. The harness takes the last such line; a method pinned in
   `program.json` wins and the prompt says so; an absent or invalid line is `direct`,
   recorded as an intervention. The brief is committed on the program branch
   (`<PSLUG>: brief for <fixture>`). A brief file absent or empty after the turn means no
   implementer: the feature gets `brief_written: false`, `failure_reason:
   "brief-unwritten"`, `method_failed: true`, and the program is marked `method_failed`.
   (c) **method** — the manifest skeleton, then the brief copied to the feature's
   `plans/features/<slug>/BRIEF.md` and handed as the prompt to a separate top-level
   `claude -p` in the feature's own worktree (`--model $HARNESS_MODEL --permission-mode
   acceptEdits --allowedTools Bash Agent Task`), so the implementer may use subagents. A
   usage-limit stop waits once and runs the same brief again. Exit 0 with an open PR
   (found through `forge.sh pr-find`): the PR URL and `pr_base` are recorded, the manifest
   window closed at PR-open, committed and pushed. Exit 1 is `failure_reason:
   "implementer-exit-N"`; exit 0 with no PR is `"no-pr"`; either is `method_failed` on
   the feature only. (d) The feature's `tip` (its HEAD) and, for a dependent feature,
   `dependency_ok` — `git merge-base --is-ancestor <previous tip> <this branch>`, a boolean
   — are recorded and `feature_done` is set. A dependent feature still runs after a failed
   predecessor, cut at whatever the predecessor's branch holds. A re-entry at `loop` skips
   every `feature_done` feature (delete its state file to redo it) and reuses a brief that
   is `brief_written` and on disk.
4. **collect** — the last orchestrator call (`--resume`) with `templates/program-collect.md`:
   run the exact `manifest.py --orchestration <PSLUG> add-feature …` commands the driver
   built for every feature that has a branch, then `set-window-to now`, fill the record's
   paragraph, commit it as `<PSLUG>: orchestration record` and push. `t_method_end` is the
   instant this turn ended. The harness then adds any feature the record does not name and
   closes a window still open (each an intervention), commits whatever is left and pushes
   the program branch. **No PR is opened for the program branch.**
5. **review**, **rework**, **accept** — per feature, in order, through the cell functions
   (`do_review`, `do_rework`, `do_accept`) on the feature's own tree. A feature that is
   `method_failed` or has no tree skips all three.
6. **capture** — per feature with a tree, `do_capture` (so `cost_method_usd`,
   `cost_review_usd`, `cost_rework_usd` come from the same per-tree capture as a cell's).
   Then `cost_overhead_usd`: `program_cost.py` prices every orchestrator session id, each
   from its own first call's start (so a resume that forks and replays old history is
   not counted twice), to `t_method_end`, with the driver's analysis copy. Then, best
   effort and never fatal, the pinned copy's `orchestration-capture.sh <PSLUG>` and
   `analysis/report.py --orchestration <PSLUG>`; `record_report` is read from the record's
   `report.json` (`null` when absent). The record files are committed
   (`<PSLUG>: freeze the harness cost capture`) and the program branch pushed.
7. **record** — one `kind: "program"` row appended to `results.jsonl` ("The program row"),
   the scorecard re-rendered, and the feature and program worktrees removed unless
   `--no-cleanup`. A feature is **green** when `!method_failed` and (the accept stage is
   off or `accept_pass`).

The `METHOD:` name is a label: `methods/<name>/` is never run in a program cell. The
implementer is always one top-level `claude -p` with the orchestrator's brief as its prompt,
and the name is recorded in the feature's `method`.

Other behaviours: the arms' own `feature-start.sh` and `feature-close.sh` are **outside the
comparison** — the harness starts every feature itself, because an arm's `feature-start.sh`
refuses a copy inside a worktree, and opens no close PR. A usage-limit stop (exit 2) on an
orchestrator call waits once (`harness_wait_for_usage_reset`) and `--resume`s the same
session; any other non-zero orchestrator exit marks the program `method_failed`, is an
intervention, and the loop still tries every remaining feature. `PROGRAM_BUDGET_USD`
(unset: no cap) is passed as `--max-budget-usd` to each orchestrator call; the orchestrator
runs at `HARNESS_MODEL`. The orchestrator's session id is minted by the harness
(`harness_new_session_id`); every call records the `session_id` its result reports, and the
next `--resume` targets the most recent reported id, falling back to the minted one.
Orchestrator results are at `<logs>/<programBranch>-orchestrator-<kind>[-NN]-result.json`
(`kind` is `brief`, `feature` with the zero-padded position, or `collect`).

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
- **`orchestrator` is a reserved method name.** A program cell's method is the literal
  `"orchestrator"`; there is no `methods/orchestrator/` and none may be added (the
  name stands for the program cell's method in its rows, branches and `--only`), and `program.json` may not pin
  `orchestrator` or `null` on a feature (checked wherever it is read). The one
  exception to "never edit `agentTooling/`": a program cell's orchestration record lives in
  the pinned copy inside the program worktree
  (`agentTooling/self/orchestrations/<PSLUG>/README.md`) and is written there, by the
  orchestrator and the harness, on the program branch.

## File shapes

### `fixture.json` — `plans/experiments/fixtures/<name>/fixture.json`

`{ name, repo?{remote?, url?, path?}, base, spec{url?, commit, path, sections[], repo?}, setup[], gate{command, green, minutes}, branch_stem, diff_lines }`

- `name` — the fixture directory's own name; the spec worktree is `<spec checkout>-fx-<name>`.
- `repo` — optional, and normally absent: the fixture's repository is the consumer, the
  repository it lives in, and is never resolved or cloned; the harness fetches from the
  consumer's own checkout and adds worktrees beside it. `repo.remote` alone — which of the
  consumer's remotes, default `origin`. `repo.url` / `repo.path`, if present, must
  identify the consumer itself (`owner/repo` compared case-insensitively, `.git` dropped,
  so a cloud proxy URL matches). `repo.url` and `repo.path` are each checked, so a fixture
  still carrying a `repo.path` that is not the consumer is refused even with a matching
  `repo.url`: drop the `repo.path`. A consumer fixture that names another repository is now
  refused wherever it is read, with a message telling you to move it into the repository
  it measures.
- `base` — the commit every run branches from, in the consumer.
- `spec` — a commit, checked out **detached and read-only** at
  `<spec checkout>-fx-<name>`, so a fixture stays valid after the spec's branch merges or
  moves. `spec.url` is optional: absent, the spec worktree is added from the consumer;
  present, it names an external spec repository, resolved to a checkout ("Repositories
  by URL") and only read (`spec.repo` the optional legacy path hint).
  `spec.sections` are the sections the brief tells the delegate to read.
- `setup[]` — shell commands run inside the fresh worktree before the gate rehearsal.
- `gate.command` — run from the worktree; `gate.green` is the substring the harness
  greps the gate's last lines for; `gate.minutes` is quoted into briefs.
- `branch_stem` — the branch is `<branch_stem><Method><Arm><n>` (§4 of `SPEC.md`).
- `diff_lines` — informational: the recorded size of the feature, for the ledger.

### `experiment.json` — `plans/experiments/<experiment>/experiment.json`

`{ name, fixtures[], methods[], programs[]?, repeats, stages{review, rework, accept}, noise_band_pct, prediction, compare_to, agent_tooling{<label>: <sha>}?, base_arms{<label>: <sha>}?, branch_stem_override{<fixture-or-program>: <stem>}? }`

`prediction` is required and is copied into the scorecard before any run — the
checklist-first rule from `EXPERIMENTS.md`. `stages` turns off a stage for the whole
experiment; `noise_band_pct` is the band under which a cost difference reads as a tie;
`compare_to` is a path to whatever earlier scorecard this run is answering.
`agent_tooling` is optional: the arms, each a bare-letters label naming a full
agentTooling commit id ("Arms" above); absent, every cell runs on the tree's own vendored
copy, with an empty `arm` in its row.
`base_arms` is optional and exclusive with `agent_tooling`: the arms, each a bare-letters
label naming a full commit id of the measured repository ("Arms" above); each cell's
worktree is cut there instead of at the fixture's `base`. `programs` cannot be combined with it.
`programs` is optional: the names of programs (`program.json`, below) to run as program
cells, one per program × arm × repeat; at least one of `fixtures` / `programs` is
non-empty, a program's name is never a fixture's, and `repeats`, `agent_tooling`, `stages`
and `noise_band_pct` are shared with the cells. `branch_stem_override` may key a program
as well as a fixture (it replaces the program's stem, or a feature fixture's stem).
`branch_stem_override` is optional and rarely needed: it replaces one fixture's
`branch_stem` for this experiment, which is how a replay of a feature that has already
been built stays off the recorded arm's branch. Without it the harness would refuse to
start — a branch that already exists and that the cell has no state for is treated as a
collision, since continuing would append this arm's commits to whatever that branch is
the record of (`HARNESS_ALLOW_EXISTING_BRANCH=1` overrides, and should be rare).

### `program.json` — `plans/experiments/programs/<name>/program.json`

`{ name, repo?{remote?, url?, path?}, base, branch_stem, gate{command, green, minutes}?, setup[]?, features[{ fixture, depends_on_previous, method? }] }`, with a hand-written `README.md` beside it.

- `name` — required; the program's directory name by convention. The program is identified
  by its directory, which `experiment.json`'s `programs` names: bare camelCase and never
  the name of a fixture (the branch-stem override keys on it).
- `repo` — optional, and normally absent: the features are built in the consumer, which
  is never resolved or cloned. If present it must identify the consumer (a program that
  names another repository is refused, naming the program); every feature's fixture must
  be on the consumer too (`harness_program_check`: "fixture X is on repository Y, not the
  consumer's Z"). `repo.remote` — default `origin`.
- `base` — a **full 40-hex commit id**, required. The program branch and every
  non-dependent feature branch are cut here. A fixture's own `base` is ignored in a
  program cell; one warning names the fixtures whose differs.
- `branch_stem` — bare camelCase; the program branch is `<branch_stem>Orchestrator<Arm><n>`
  and the stem sits where a cell's method does in every feature branch ("Naming").
- `gate` — optional `{command, green, minutes}`, run in the program tree at setup and, when
  named, governing every feature too; absent (or without `command`), the program tree uses
  the first feature's fixture's gate and each feature its own fixture's.
- `setup[]` — optional shell commands run once in the **program** tree before its gate (each
  feature's toolchain comes from its fixture's `setup[]`).
- `features[]` — non-empty, in run order. `fixture` — a directory under
  `plans/experiments/fixtures/`, appearing once. `depends_on_previous` — boolean; `false`
  on the first. `method` — optional pin: `direct`, `plans`, `hand`, or the name of a
  directory under `methods/` — never `null` or `orchestrator`; absent, the orchestrator
  chooses.

`harness_program_check` (`lib.sh`) enforces these wherever the file is read
(`new-experiment.sh` and `run.sh`).

### The ledger row — one JSON object per line in `results.jsonl`

`{ experiment, fixture, method, repeat, arm, agent_tooling, arm_kind, branch, slug, pr_url, base, spec_commit, model, effort, t_setup_start, t_method_start, t_pr_open, t_review_end, t_rework_end, t_green, cost_method_usd, cost_method_reported_usd, cost_review_usd, cost_rework_usd, cost_green_usd, cost_lost_usd, read_files_before_edit, read_bytes_before_edit, readme_bytes_read, review_fixed, review_escalated, rework_ran, gate_counts_pr_open, gate_counts_green, accept_pass, accept_lines[], method_failed, pr_opened_by_harness, interventions[{t, what}], harness_version }`

`model` is `HARNESS_MODEL`; `effort` is `HARNESS_EFFORT` as a string (`"low"` … `"max"`), or
`null` when it was unset and the CLI's default applied.

Every `t_*` is UTC with a `Z`, the convention `analysis/README.md` makes load-bearing.
`cost_green_usd` is the sum of `cost_method_usd`, `cost_review_usd` and `cost_rework_usd`. `cost_lost_usd` is spend from a killed attempt's orphaned open manifest window, priced when the stage re-runs and kept out of every method figure. `cost_method_reported_usd` is the `total_cost_usd` the method's first `claude -p` session reported for itself, kept beside the captured figure as a cross-check: captured below 90% of it (or zero against a non-zero report) makes the capture stage warn. A `planning.json` stamped before its slug's current manifest window opened is a stale freeze from an earlier attempt — a reused branch, or a stage a `--from` resume re-ran — and is rebuilt with `--recapture`. `gate_counts_*` are whatever the
gate printed, as a string. `arm` is the arm's label and `agent_tooling` the upstream
commit its vendored copy was pinned to — both empty for a run with no pin. For a base arm
`agent_tooling` is empty and `base` is the arm's commit (the fixture's `base` otherwise).
`arm_kind` is `"agent_tooling"`, `"base"`, or `""` with no arm; it is absent on older rows —
read absent as `"agent_tooling"` when `agent_tooling` is non-empty, else `""`.
`read_files_before_edit`, `read_bytes_before_edit` and `readme_bytes_read` are integers, or
`null` when not measured (no transcript in the window; absent on older rows). Their
definitions are `reading_metrics.py`'s docstring: the transcripts under the worktree's own
project directory (exact name) and their subagents, lines inside `[t_method_start,
t_pr_open]` (now when no PR opened), the first edit being the first
`Edit`/`Write`/`MultiEdit`/`NotebookEdit`; a read is a non-error `Read` result, bytes its
UTF-8 text; files are counted distinct; `readme_bytes_read` is every `README.md` read in the
window, before or after the first edit. Only the `Read` tool counts — a `cat` through `Bash`
does not. The figures come from the `capture` stage (`do_reading_metrics`), from the
driver's `analysis/` modules, and reach the state file before `record`.
`harness_version` is the agentTooling commit that ran it (the driver's; in a vendored
copy, the consuming repo's HEAD). `pr_opened_by_harness` is a boolean: `true` when the
method exited 0 with its branch pushed and commits beyond `base` but no PR open, and the
harness opened the PR itself through the driver's forge ("The forge seam"); `false`
otherwise, including every row written before the field existed (read an absent field as
`false`). A `true` row also carries an `interventions[]` entry naming the PR, so the
comparison never counts a harness-opened PR as the method's own work unremarked.

The state file `<experiment-dir>/state/<branch>.json` carries the same fields as they
are filled, plus a `stages` object of `{start, end, outcome}` per stage. `--from` reads
it, and a finished run's state file stays.

### The program row — a ledger row with `kind: "program"`

A **program cell** is an orchestrator session running an ordered list of features under
one agentTooling version, one implementer per feature; the two arms are compared as one
feature set. It appends one row to the same `results.jsonl`. A row without `kind` is an
ordinary cell and reads exactly as above; `scorecard.py` splits the two on `kind`. The program row and its `features[]` carry neither
`arm_kind` nor the reading fields (a program feature's capture does not run the extractor),
and a program cell cannot run under base arms.

`{ kind: "program", experiment, program, method: "orchestrator", repeat, arm, agent_tooling, branch, slug, base, model, effort, orchestrator_sessions[], orchestration_record, t_setup_start, t_method_start, t_method_end, cost_overhead_usd, cost_group_usd, cost_group_green_usd, overhead_pct, features_count, features_pr_open, features_green, method_failed, record_report{group_total_usd, overhead_pct, unpriced_count}|null, features[{ position, fixture, depends_on_previous, method, branch, slug, session, pr_url, pr_base, t_implementer_start, t_implementer_end, brief_written, dependency_ok, cost_method_usd, cost_review_usd, cost_rework_usd, cost_green_usd, unpriced_reason, review_fixed, review_escalated, rework_ran, accept_pass, accept_lines[], gate_counts_green, green, method_failed }], interventions[{t, what}], harness_version }`

- `program` — the program's name; with `arm` and `repeat` it identifies a program cell,
  as `fixture`, `method`, `arm` and `repeat` do an ordinary one. `method` is always
  `"orchestrator"`. `experiment`, `repeat`, `arm`, `agent_tooling`, `base`, `model`, `effort`,
  `t_setup_start`, `interventions[]` and `harness_version` mean what they mean on a cell
  row; `t_method_start` / `t_method_end` bracket the orchestrator's run.
- `branch` / `slug` — the program's **own** branch and its slug: the orchestrator's tree,
  carrying the arm pin and the orchestration record. `orchestrator_sessions[]` — the
  orchestrator's session ids, in order, each distinct id once (more than one only if a
  `--resume` reported a different id). `orchestration_record` — the record's path
  relative to that tree, always `agentTooling/self/orchestrations/<slug>/README.md`.
- `cost_overhead_usd` — the orchestrator's own cost. `cost_group_usd` =
  `cost_overhead_usd` + Σ `features[].cost_method_usd`: the group to PR-open.
  `cost_group_green_usd` adds every feature's review and rework cost: the group to green.
  `overhead_pct` = `cost_overhead_usd` / `cost_group_usd` × 100 — the definition
  `analysis/report.py --orchestration` uses.
- `features_count`, `features_pr_open`, `features_green` — how many features the program
  listed, how many opened a PR (`pr_url` non-empty) and how many came out green.
  `method_failed` — the orchestrator did not finish the program: any orchestrator call
  failed, any brief was left unwritten, or the collect turn failed. A failed *implementer*
  is `method_failed` on its feature and not here.
- `record_report` — the `{group_total_usd, overhead_pct, unpriced_count}` the arm's own
  `report.py --orchestration` wrote, kept only as a cross-check against `cost_group_usd`
  and `overhead_pct`; `null` when the arm wrote none. It is not like for like: the record's
  group total sums each priced feature's whole `report.json` total (review and rework
  included, unpriced features left out), so it sits nearer `cost_group_green_usd` and its
  `overhead_pct` is over that larger denominator. The scorecard prints
  `group_total_usd` beside the harness's own figure and never uses it in a comparison.
- `features[]` — one object per feature, in run order. `position` is 1-based.
  `depends_on_previous` says the feature was meant to start from the previous feature's
  branch; `dependency_ok` whether its branch really contains the previous branch's tip
  (`null` when it was not dependent; for a dependent feature always a boolean, `false`
  when the predecessor left no tip). `brief_written` — the orchestrator wrote
  the implementer's brief. `session` — the implementer's session id. `pr_base` — the
  branch the feature's PR targets. `t_implementer_start` / `t_implementer_end` bracket the
  implementer. `unpriced_reason` is `null` when `cost_method_usd` is a measurement and a
  string when it is not: the feature has no manifest directory (no implementer ran), or the
  captured cost is below 90% of what `claude` reported for the implementer (or zero against a
  non-zero report), in which case the string names both figures and says the capture missed
  the session. A feature with no worktree at `capture` is skipped there and keeps
  `null` (the loop never reached it: `method_failed` marks it instead). `method`,
  `fixture`, `branch`, `slug`, `pr_url`, `green`, `accept_pass`, `accept_lines[]`,
  `review_fixed`, `review_escalated`, `rework_ran`, `gate_counts_green`, `method_failed`
  and the four `cost_*` fields mean what they mean on a cell row; `cost_green_usd` is the
  sum of the feature's method, review and rework cost.

`cost_overhead_usd` is priced in `[t_method_start, t_method_end]` with the **driver's**
analysis copy through `program_cost.py`, never the arm's, so every arm is priced by the
same rates. A feature the loop never reached (its state file absent or empty) appears with
`method_failed: true` and zeros. `green` is `!method_failed` and (the accept stage off or
`accept_pass`).

The state files carry the row's fields as they are filled, plus these keys. Program state
(`<experiment-dir>/state/<programBranch>.json`): `session_id` (the id the harness minted
for `--session-id`; replaced by a fresh id when the first call was killed, below),
`orchestrator_sessions[]`, `orchestrator_session_starts{<id>: start of that id's first
call}`, `orchestrator_calls`, `orchestrator_first_call_started` (the instant the first
`--session-id` call began, set before it; with `orchestrator_calls` still 0 on a re-entry it
means that call never completed, so the harness mints a fresh `session_id`, keeps the old one
in `orchestrator_sessions[]` so whatever it cost is priced, and records an intervention
naming both), `t_setup_start`, `t_method_start`,
`t_method_end`, `agent_tooling`, `cost_overhead_usd`, `record_report` (object or `null`),
`method_failed`, `stages`, `interventions[]`. Feature state (`…/<featureBranch>.json`, a
cell's keys plus): `position`, `program`, `depends_on_previous`, `start_point` (the commit
the branch was cut at), `brief_written`, `method` (the one chosen), `session` (the
implementer's), `t_implementer_start`, `t_implementer_end`, `pr_base`, `tip`,
`dependency_ok` (dependent features only), `failure_reason` (`brief-unwritten`,
`implementer-exit-N`, `no-pr`), `unpriced_reason` (written by `capture`; string or `null`)
and `feature_done`.

The scorecard reads `features_count`, `features_pr_open` and `features_green` from the
row, and counts `features[]` itself only when a row omits them or holds `null`; likewise
it reads `overhead_pct`, and computes `cost_overhead_usd` / `cost_group_usd` × 100 only
when that is absent or `null` (0 for a zero or missing group cost). Every dollar figure is
read from the row, never recomputed.

## Naming

- Branch: `<branch_stem><Method><Arm><n>` in bare camelCase, method and arm label
  capitalised, the arm omitted when the experiment pins nothing, `n` omitted when
  `repeats` is 1 — `exportStoreDirect`, `exportStorePlans2`, `exportStoreDirectAfter3`.
  A hyphenated method name is camelCased with the hyphens dropped (`direct-bare` →
  `exportStoreDirectBare2`); the row's `method` stays the directory name.
  **Never a `user/` prefix**: `capture_planning.py` matches the manifest's `branches`
  entry literally against each session's `gitBranch`, and a mismatch silently reports
  `$0.00`. A session is matched on two things: that branch name literally, and its launch
  cwd being one of the feature's claim roots — the harness's own tree `<repo>-<Branch>`
  is one, admitted for each entry of the manifest's `branches` (`claim_roots`,
  `analysis/README.md`), so the implementer, review and rework sessions all price.
- Slug: the branch in kebab-case — `export-store-direct`, `export-store-direct-after-3`;
  the review and rework manifests append `-review` / `-rework`.
- Program cell: a program's branch is `<programStem>Orchestrator<Arm><n>`
  (`mediaProgramOrchestratorAfter2`) and a feature's inside it
  `<fixtureStem><ProgramStem><Arm><n>` (`exportStoreMediaProgramAfter2`); the arm is
  omitted when the experiment pins nothing and `n` when `repeats` is 1, as above. The
  slug is the branch in kebab-case.
- Worktree: `<repo checkout>-<branch>`, the repo checkout being the consumer's own.
  Spec worktree: `<spec checkout>-fx-<fixture>`, beside the consumer unless `spec.url`
  names an external spec repository.
