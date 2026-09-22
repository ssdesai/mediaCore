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
  `check-plans.sh`, `sync-plans.sh`, `update.sh`, `stamp-timing.sh`, `feature-start.sh`,
  `feature-close.sh` and `feature-capture.sh`.
- Doctrine at the top level too: `LIFECYCLE.md`, `CONVENTIONS.md`, `AGENT_PLANS.md`,
  `AGENT_DIRECT.md`, `ORCHESTRATION.md`, `RUNNER.md`, `README.md`. `EXPERIMENTS.md` lives
  with its tool, under `harness/`.
- `templates/` — the stubs `sync-plans.sh` writes into a *consuming* repo's `plans/`.
  Never edited in the consuming repo. Five are generated and overwritten every sync;
  six are seeded once and then repo-owned (`PROJECT_FACTS.md`, `BACKLOG.md`, `gate.sh`,
  `pr.sh`, `worktree-setup.sh`, `open-session.sh`). Nothing repo-specific ever goes in here.
- `analysis/` — stdlib-only Python 3 cost tooling.
- `hooks/` — the permission policy: the `PreToolUse` hook, the `policy.py` table both it
  and the wiring read (the git deny's constants and the `bash_deny_rules()` that renders
  their `permissions.deny` twin), and the helper that wires them.
  This checkout has its own committed `.claude/settings.json` at the top level, generated
  by `python3 -B hooks/wire-settings.py --self --repo <root> --write` and never by hand;
  `self/gate.sh` records the matching `--check` as a blocking check, and under `--self`
  that check is **byte for byte**, so editing the
  constants without re-running the write fails the gate — and so does editing the file.
  It carries no allow rules;
  its `Edit(/.claude/**)` deny rule means the file cannot be changed with the Edit tool,
  and `hooks/` itself is an `Edit` **ask** rule, which prompts an attended session and
  refuses a headless one.
- `self/` — this corpus. Not generated from `templates/`. `self/tests/` holds the
  harness's own behavioural checks, run by `self/gate.sh`.

## Commands

- Start a feature: `./feature-start.sh --self <slug> [--method direct|plans|hand] [--open]`,
  from
  the primary checkout — it makes branch `<slug>` and worktree `<repo>/.worktrees/<slug>`
  (inside the primary, ignored through the common git dir's `info/exclude`) and writes
  `self/features/<slug>/` there, the routing record `self/features/<slug>/routing.json`
  for the session that ran it among them. That session is a **router** and is never pinned: coordinate
  the feature from a session launched inside the worktree, which `--open` does for you
  through `self/open-session.sh`. `--pin` is the opt-in for the rare case where the
  starting session really is the feature's coordinator, and writes no routing record — a
  pinned session is never also a router. Each start also prunes the feature
  worktrees whose branches have merged into `origin/main`. A feature started before that layout has the sibling
  `<repo>-<slug>` instead, and captures the same way. `feature-start.sh` refuses to run
  from a worktree.
- Close a feature: `./feature-close.sh --self <slug> [--no-push]`, **from the feature's
  worktree, on its branch** — the only way out, and what `run-batch.sh --self` calls on a
  clean round. It refuses unless the latest completed review's `plan_end` carries
  `verdict=clean` and `HEAD` is the `head` that stamp names (or that sha followed only by
  `<slug>: cost records` / `<slug>: PR`), then: `self/pr.sh` → the `pr_opened` stamp →
  `./feature-capture.sh` → `self/pr.sh --merge-request`, in that order. Under `self/pr.sh`
  the merge is never requested (`AUTO_MERGE=0`). See `../LIFECYCLE.md` → step 6.
- Capture a feature's cost: `./feature-capture.sh --self <slug>`, **from the feature's
  worktree, on its branch** — `./feature-close.sh --self <slug>` runs it after `self/pr.sh`,
  so by hand it is only a re-run after a refusal. It stamps
  `to`, captures, reports, refreshes the router's routing record, commits the cost records
  on the branch and pushes the branch. Merging the PR is the last step; nothing runs
  after it. From the primary after a merge it captures a feature merged under the old flow
  and never closed, or repairs one with `--recapture`, writing locally and committing and
  pushing nothing. See `../LIFECYCLE.md`.
- Mechanical gate: `./self/gate.sh [NN]` — writes `self/gate-report.txt`, plus
  `self/gate-report.NN.txt` when given a level label.
- Lint: `./check-plans.sh --self <slug>` — run by `./run-batch.sh --self <slug>` first,
  exits 1 on lint failures.
- Build: `./run-plans.sh --self <slug>`; verify: `./run-verify.sh --self <slug>`;
  review: `./run-review.sh --self <slug>`; all three plus the close on a clean round:
  `./run-batch.sh --self <slug>`. The review pass records the round's verdict — the first
  line of `self/review-report.md`, `Verdict: clean` or `Verdict: escalated` — and stops;
  an escalated round's rework is briefed from
  `self/features/<slug>/escalations/<review-stem>.md` and is a new round.
- **There is no sweep.** `sweep.sh` is retired: the rates line, the corpus-wide unclaimed
  listings and the frozen-record annotation are printed or run by `./feature-capture.sh`,
  and what is left are repair tools (`analysis/README.md` → "Repair tools").
- Cost: `python3 analysis/backfill_usage.py --self`,
  `python3 analysis/capture_planning.py --self --all` (captures features with no
  `planning.json`; a single `<slug>` works too, and `--recapture` rebuilds one that is
  already captured), `python3 analysis/capture_planning.py --self --annotate-frozen`
  (refresh the corpus's `also_claimed_by` from the claims ledger; the capture runs it),
  `python3 analysis/report.py --self <slug>`, `python3 analysis/report.py --self --all`
  (writes any missing `report.json` first, then the trend table),
  `python3 analysis/manifest.py [--self] <slug> set-plans <stem>...`.
- `--self` is always the **first** argument, before any slug.

## Tests

**There is no test *runner* here** — no pytest, no framework, nothing to register a test
with. What `self/gate.sh` runs is:

- `bash -n <script>` parses every shell script.
- `shellcheck` if it happens to be installed; it is not a dependency and `self/gate.sh`
  skips it when absent.
- `python3 -m py_compile analysis/*.py`, and `hooks/{policy.py,wire-settings.py,
  allow-repo-commands.sh}` — the hook keeps a `.sh` name and is Python.
- `python3 -B hooks/wire-settings.py --self --repo <root> --check` — the committed
  `.claude/settings.json` is byte for byte what the constants generate.
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
- **Surviving SIGPIPE means redirecting *and* flushing.** The runners trap SIGPIPE so a
  consumer that stops reading their stdout cannot fail a plan (`../RUNNER.md` →
  "Capturing the stream"), and `run-batch.sh` installs the same handler above its own
  first write — it is a separate process that sources only `plan-runner-roots.sh`, so
  the trap in `run_all` never covered it and a closed consumer killed the batch (not the
  plan) at its next banner. A trap alone is not enough: the bytes of the write that failed
  stay in bash's stdio buffer, and every later `$(…)` that runs a function or a list, and
  every `<(…)`, inherits the dirty buffer and flushes it into its own stdout — which is
  that substitution's pipe. The observed result was `$(wc -c < f)` returning the byte
  count plus the text of the failed echo, and `<(list_plans …)` handing `run_all` a
  "=== Finished: … ===" line as the next plan to run. The handler is therefore
  `exec >/dev/null; printf "\n"`: point stdout somewhere that cannot break, then make one
  successful write to clear the buffer. A zero-byte write does not clear it. Use a
  *handler*, never `trap '' PIPE` — an ignored disposition is inherited through `exec` and
  would change SIGPIPE for `claude`, `jq`, `git`, `gh` and a consuming repo's own
  `plans/gate.sh`, while a handled one is reset to default in children.
- **`claude` writes `.stream.jsonl` itself** — its stdout is redirected to the file and it
  runs as a background job, so nothing that reads the stream can truncate it. A plan that
  needs the events live reads the file, it does not insert itself into a pipe in front of
  it, and nothing writes a sentinel line into that file: `write_usage_sidecar` and
  `stream_shows_usage_limit` parse it. Two things that file's readers must respect:
  `claude`'s **stderr is merged into it** (`2>&1`), so anything asking "did this stream
  reach a `result` event?" parses with `fromjson?` and skips the lines that are not JSON —
  there is one copy of that expression (`STREAM_EVENTS_JQ`) and both readers splice it in;
  and `mktemp -d` is always given an **explicit template under `$TMPDIR`**, because a bare
  `mktemp -d` on macOS asks the OS for the per-user temp directory and ignores `$TMPDIR`
  entirely, which makes anything built on it unconfigurable and untestable.
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
  **The third fact is corpus identity, and it is declared, not derived**:
  `roots.SELF_CORPUS_IDENTITY` (`https://github.com/ssdesai/agentTooling.git`, the same
  string as `update.sh`'s `DEFAULT_REMOTE`) is who `self/features` belongs to, and
  `capture_planning.corpus_identity(features_dir)` is the one rule that answers it —
  the declared constant for this corpus, `repo_identity(features_dir.parents[1])` for a
  consuming repo's. Neither root can be asked: a vendored `agentTooling/` has no `.git`,
  so `git` there answers with the consumer's origin and files agentTooling's features
  under the consumer. Which repo a *checkout* is — the origin of a directory on disk,
  which is what `repo_identity` answers and what its `checkout_dir` parameter is named
  for — is a different question from which corpus a *feature* belongs to, and
  `corpus_identity` is the only thing that asks it: a `--self` session in a vendored
  checkout really did run in the consumer's repo while the feature it was building
  belongs to agentTooling.
- **Manifest `branches` are the enclosing repo's branch names** when agentTooling is
  vendored as a subtree, because that is what a session's `gitBranch` reports. A self
  feature's manifest naming `browseImages` is correct, not a mistake.
- **`git subtree` needs a clean working tree** for add, pull and push — including for
  changes unrelated to the prefix. Push, then pull straight back to record the split, or
  the next push is rejected. `../README.md` → "Updating" has the full explanation.
- **Plan numbers are per feature, from `01`, here as everywhere** —
  `AGENT_PLANS.md` → "Plan file format" is the general rule, and nothing in `list_plans`
  compares numbers across features. This corpus ran one shared sequence across every
  feature instead until `lifecycle-records-and-numbering` retired it on 2026-09-17: two
  features started from the same base both saw the same highest number and both got
  highest-plus-one, because the sequence assumed only one feature would ever be
  mid-start. Features issued before the retirement keep the numbers they were issued —
  `plan-analytics` is `48`–`58`, `agenttooling-self-host` `59`–`64`, `test-first-levels`
  `65`–`70`, and so on through the rest of `self/features/README.md`'s list — as history,
  not as a convention to continue: the ranges quoted there were issued under the retired
  sequence, and a new feature starts at `01` regardless of what the highest number
  anywhere else in the corpus happens to be. Because two features can now both hold, say,
  a `01-review-opus`, qualify a cross-feature reference with the slug
  (`AGENT_PLANS.md` already says this for a consuming repo).
- A file named `NN-gate.md` in `auto/incomplete/` is a level sentinel, never executed;
  `run-plans.sh` exits 64 (`LEVEL_PAUSE_RC`) at one when a verify plan numbered ≤ `NN` is queued and the gate is not green. 64 is reserved: `finalize_plan` and `run_level_gate` remap a child that exits 64 to 1.
