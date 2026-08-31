# Project facts for plan authors

Facts an agentTooling plan must pin so an executor doesn't re-derive them. This is the
`--self` counterpart of a consuming repo's `plans/PROJECT_FACTS.md`; see
`../AGENT_PLANS.md` → "Pin the facts executors would otherwise hunt for".

The overriding one: **every file here ships to every consuming repo** on its next
`git subtree pull`. There is no local-only change in this directory, and a path or a
filename referenced from a consuming repo's `plans/` stub cannot be renamed unilaterally.

## Layout

- Shared machinery at the top level: `run-plans.sh`, `run-verify.sh`, `run-review.sh`,
  `run-batch.sh`, `run-escalation-plan.sh`, `plan-runner-lib.sh`, `plan-runner-roots.sh`,
  `sync-plans.sh`, `migrate-plans-layout.sh`.
- Doctrine at the top level too: `CONVENTIONS.md`, `AGENT_PLANS.md`, `RUNNER.md`,
  `EXPERIMENTS.md`, `README.md`.
- `templates/` — the stubs `sync-plans.sh` writes into a *consuming* repo's `plans/`.
  Never edited in the consuming repo.
- `analysis/` — stdlib-only Python 3 cost tooling.
- `self/` — this corpus. Not generated from `templates/`. `self/tests/` holds the
  harness's own behavioural checks, run by `self/gate.sh`.

## Commands

- Mechanical gate: `./self/gate.sh [NN]` — writes `self/gate-report.txt`, plus
  `self/gate-report.NN.txt` when given a level label.
- Build: `./run-plans.sh --self <slug>`; verify: `./run-verify.sh --self <slug>`;
  review: `./run-review.sh --self <slug>`; all three: `./run-batch.sh --self <slug>`.
- Cost: `python3 analysis/backfill_usage.py --self`,
  `python3 analysis/capture_planning.py --self --all` (captures features with no
  `planning.json`; a single `<slug>` works too, and `--recapture` rebuilds one that is
  already captured), `python3 analysis/report.py --self <slug>`.
- `--self` is always the **first** argument, before any slug.

## Tests

**There is no test *runner* here** — no pytest, no framework, nothing to register a test
with. What `self/gate.sh` runs is:

- `bash -n <script>` parses every shell script.
- `shellcheck` if it happens to be installed; it is not a dependency and `self/gate.sh`
  skips it when absent.
- `python3 -m py_compile analysis/*.py`.
- `self/tests/*.sh` — plain bash scripts the gate `record`s directly, each exiting
  non-zero on a failed assertion. They stand up a throwaway checkout in a `mktemp -d`
  with a stub `claude` and a stub gate, so they assert runner *behaviour* without calling
  a model or the network. See `self/tests/README.md`.
- Everything else is an interactive plan under `self/features/<slug>/interactive/`.

**A new runner contract belongs in `self/tests/`, not in a verify brief.** A check
re-performed by a verify executor each batch pays a high-rate model to relearn the same
thing; the same assertion as a bash script runs free forever (`AGENT_PLANS.md` → "A check
that will still matter next batch is a test, not a check"). What genuinely cannot be
scripted — a `git subtree` cycle, a real batch end to end — is what a verify plan should
say to run by hand, along with what "passing" looks like.

## Conventions and gotchas

- **bash 3.2.** The system bash on macOS, and what these scripts must run under. No
  associative arrays, no `${var^^}`. Expanding a possibly-empty array under `set -u`
  needs `${a[@]+"${a[@]}"}` — the naive `"${a[@]}"` aborts the run. See
  `plan-runner-lib.sh`'s `CLAUDE_BUDGET_ARGS` call site.
- **`set -uo pipefail`, deliberately no `set -e`.** The runners route failures through
  explicit exit codes (`finalize_plan`), so an `&&` short-circuit that leaves a non-zero
  status behind is a real hazard where `set -e` would have caught it. Use
  `if …; then …; fi` over `cond && cmd` for anything whose status is not being checked.
- **`jq` and `claude` are hard dependencies**, verified by `require_tools` at startup
  (exit 127). Both `jq` call sites suppress stderr, which is exactly why the startup
  check exists: a missing `jq` would otherwise produce an empty progress log, no
  terminal output, and every plan still filed as complete.
- **Model suffix.** A plan file is `NN-description-MODEL.md` with `MODEL` one of
  `haiku`, `sonnet`, `opus`; `extract_model` parses the trailing segment and warns-and-
  defaults to `sonnet` otherwise. Interactive plans carry no model suffix.
- **The analysis scripts import each other bare** — `from pricing import compute_cost`,
  `from roots import …`. That works because Python puts the *script's own directory* on
  `sys.path`; there is no package, no `__init__.py`, no install step. A new shared module
  goes in `analysis/` and is imported the same way.
- **Artifact root vs session root.** The two are the same in an ordinary run and diverge
  under `--self`: artifacts are written under `agentTooling/`, but planning transcripts
  are recorded against the enclosing git toplevel. Anything reading
  `~/.claude/projects/` needs the session root; anything writing a feature artifact
  needs the artifact root. See `analysis/README.md` → "Where to run them".
- **Manifest `branches` are the enclosing repo's branch names** when agentTooling is
  vendored as a subtree, because that is what a session's `gitBranch` reports. A self
  feature's manifest naming `browseImages` is correct, not a mistake.
- **`git subtree` needs a clean working tree** for add, pull and push — including for
  changes unrelated to the prefix. Push, then pull straight back to record the split, or
  the next push is rejected. `../README.md` → "Updating" has the full explanation.
- **Plan numbers run as one sequence across this corpus** and are never reused within it:
  `plan-analytics` is `48`–`58`, `agenttooling-self-host` `59`–`64`, `test-first-levels`
  `65`–`70`. This is a local convention, not the general rule — `AGENT_PLANS.md` → "Plan
  file format" numbers **per feature**, from `01`, and nothing in `list_plans` compares
  numbers across features. Continuing the sequence here is compatible with it (it is
  always ≥ the per-feature minimum) and is worth keeping only because this corpus is small
  enough that a global number identifies a plan unambiguously in a commit message. Do not
  carry the convention into a consuming repo, and do not read it as licence to number a
  consuming repo's feature from that repo's plan-history count.
- A file named `NN-gate.md` in `auto/incomplete/` is a level sentinel, never executed;
  `run-plans.sh` exits 64 (`LEVEL_PAUSE_RC`) at one when a verify plan numbered ≤ `NN` is queued and the gate is not green. 64 is reserved: `finalize_plan` and `run_level_gate` remap a child that exits 64 to 1.
