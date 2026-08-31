# 60 — Self-corpus scaffold

Feature: `agenttooling-self-host`, plan 2 of 5. Makes `agentTooling/` able to run the
delegated-plan workflow on itself (`--self`), so harness features are planned, executed
and costed inside agentTooling instead of inside whichever repo vendors it.

Create the `agentTooling/self/` tree that `--self` drains, plus the `.gitignore` and
`CLAUDE.md` that tree depends on.

Independent of other plans. (Plan 59 teaches the runners to *read* this tree; neither
plan reads the other's files.)

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- Every file under `agentTooling/` ships to every consuming repo through
  `git subtree`. `agentTooling/.gitignore` therefore has to work both standalone and
  vendored — git reads `.gitignore` at any directory depth, with patterns relative to
  the file's own directory, so plain `self/**/*.stream.jsonl` is correct in both.
- The consuming repo's own `.gitignore` uses `plans/**/*.stream.jsonl`, which does
  **not** match `agentTooling/self/features/**`. That gap is why this file must exist
  before plan 64 moves anything in.
- `agentTooling/self/gate.sh` is written by plan 61, not here. This plan's READMEs
  describe it; do not create it.
- Do not run `sync-plans.sh` or copy from `templates/` — those stubs are for a consuming
  repo and every path in them points back up at `../agentTooling/…`, which is wrong from
  inside agentTooling. The files below are hand-written and stay hand-written.
- Content below is settled prose; paste it as given rather than paraphrasing.

## Files

- Create `agentTooling/.gitignore`
- Create `agentTooling/CLAUDE.md`
- Create `agentTooling/self/README.md`
- Create `agentTooling/self/PROJECT_FACTS.md`
- Create `agentTooling/self/features/README.md`
- Create `agentTooling/self/interactive/README.md`
- Modify `agentTooling/sync-plans.sh`
- Modify `agentTooling/AGENT_PLANS.md`

## `agentTooling/.gitignore` (create)

```gitignore
# This file ships with the subtree, so it must hold for both a standalone agentTooling
# checkout and a vendored copy inside a consuming repo. Patterns are relative to this
# directory in both cases, and the consuming repo's own plans/**/ patterns do not reach
# in here.

# run-plans.sh / run-verify.sh raw event streams from --self runs — 0.2-1.5 MB each,
# kept on disk as the full record of what an executor did, never committed.
self/**/*.stream.jsonl
self/**/*.logfifo

# Output of self/gate.sh — regenerated on every --self batch, read by the verify plan.
self/gate-report.txt

# analysis/ scripts are stdlib-only and run directly, but python still writes these.
__pycache__/
*.py[cod]

# macOS. A tracked .DS_Store aborts `git subtree add/pull/push`, which require a clean
# working tree even for changes unrelated to the prefix.
.DS_Store
```

## `agentTooling/CLAUDE.md` (create)

```markdown
@CONVENTIONS.md

## What this directory is

The shared Claude Code conventions and delegated-plan harness, vendored into each repo
with `git subtree`. A change here ships to **every** consuming repo on its next
`subtree pull` — there is no such thing as a local-only fix in this directory.

## Self-hosted work

agentTooling builds its own features with its own harness. Its plan corpus is
`self/features/<slug>/`, drained by `./run-plans.sh --self` and friends; the facts a
plan author needs are in `self/PROJECT_FACTS.md`. See `RUNNER.md` → "Self-hosted mode"
for how `--self` differs from an ordinary run, and `AGENT_PLANS.md` for how to author
the plans themselves.

This file exists because a `--self` executor's cwd is this directory, not the consuming
repo root — without it, such an executor would never load `CONVENTIONS.md` at all. In a
consuming repo that root `CLAUDE.md` already imports `@agentTooling/CONVENTIONS.md`, so
editing inside this directory loads the conventions twice. That is the accepted cost;
see the `agenttooling-self-host` manifest's exclusions.

### Commands

- Mechanical gate: `./self/gate.sh` (syntax checks; there is no test suite)
- Build a self feature: `./run-plans.sh --self <slug>`, then `./run-verify.sh --self <slug>`
- Cost report: `python3 analysis/report.py --self <slug>`
```

## `agentTooling/self/README.md` (create)

```markdown
# self

agentTooling's own plan corpus — the harness applied to itself. This is the exact
counterpart of a consuming repo's `plans/` directory, one level in, and it is drained by
passing `--self` to the runners:

```bash
./agentTooling/run-batch.sh --self <slug>    # build pass, then verify pass
./agentTooling/run-plans.sh --self <slug>    # build pass only
./agentTooling/run-verify.sh --self <slug>   # verify pass only
```

| Path | What it is |
|---|---|
| `features/` | One directory per agentTooling feature: manifest, `auto/`, `verify/`, `interactive/`, and the JSON cost artifacts. See `features/README.md`. |
| `interactive/` | Standing runbooks that outlive any one feature. A feature's own bash-heavy steps live in `features/<slug>/interactive/` instead. |
| `PROJECT_FACTS.md` | The facts every agentTooling plan must pin — bash version, no test suite, how the analysis scripts import each other. Read before authoring. |
| `gate.sh` | The mechanical gate `run-batch.sh --self` runs between the build and verify passes, writing `gate-report.txt`. |
| `gate-report.txt` | Gate output. Gitignored — regenerated every batch. |

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
```

## `agentTooling/self/PROJECT_FACTS.md` (create)

```markdown
# Project facts for plan authors

Facts an agentTooling plan must pin so an executor doesn't re-derive them. This is the
`--self` counterpart of a consuming repo's `plans/PROJECT_FACTS.md`; see
`../AGENT_PLANS.md` → "Pin the facts executors would otherwise hunt for".

The overriding one: **every file here ships to every consuming repo** on its next
`git subtree pull`. There is no local-only change in this directory, and a path or a
filename referenced from a consuming repo's `plans/` stub cannot be renamed unilaterally.

## Layout

- Shared machinery at the top level: `run-plans.sh`, `run-verify.sh`, `run-batch.sh`,
  `plan-runner-lib.sh`, `plan-runner-roots.sh`, `sync-plans.sh`,
  `migrate-plans-layout.sh`.
- Doctrine at the top level too: `CONVENTIONS.md`, `AGENT_PLANS.md`, `RUNNER.md`,
  `README.md`.
- `templates/` — the stubs `sync-plans.sh` writes into a *consuming* repo's `plans/`.
  Never edited in the consuming repo.
- `analysis/` — stdlib-only Python 3 cost tooling.
- `self/` — this corpus. Not generated from `templates/`.

## Commands

- Mechanical gate: `./self/gate.sh` — writes `self/gate-report.txt`.
- Build: `./run-plans.sh --self <slug>`; verify: `./run-verify.sh --self <slug>`.
- Cost: `python3 analysis/backfill_usage.py --self`,
  `python3 analysis/capture_planning.py --self <slug>`,
  `python3 analysis/report.py --self <slug>`.
- `--self` is always the **first** argument, before any slug.

## Tests

**There is no test suite, and no test runner to add one to.** Verification is syntax
checking plus a human running the thing:

- `bash -n <script>` parses every shell script.
- `shellcheck` if it happens to be installed; it is not a dependency and `self/gate.sh`
  skips it when absent.
- `python3 -m py_compile analysis/*.py`.
- Everything else is an interactive plan under `self/features/<slug>/interactive/`.

A verify plan for a self feature therefore has less to lean on than in a repo with
pytest — say what to run by hand and what "passing" looks like, rather than pointing at
assertions that don't exist.

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
- **Plan numbers are global and never reused**, across both this corpus and every
  consuming repo's. `plan-analytics` is `48`–`58`; `agenttooling-self-host` is `59`–`64`.
```

## `agentTooling/self/features/README.md` (create)

```markdown
# Feature plan trees

Every agentTooling feature gets one directory here, named by its slug:

    self/features/<slug>/
      README.md          the feature manifest — goal, plan table, exclusions, machine-readable JSON
      auto/{incomplete,inprogress,complete,failed}/     file-edit-only build plans (Bash disabled)
      verify/{incomplete,inprogress,complete,failed}/   post-build verification plans (Bash enabled)
      interactive/       bash-heavy steps run by hand, belonging to THIS feature
      planning.json      written later by analysis/capture_planning.py --self
      report.md / report.json

- `auto/` — build plans, run unattended by `../../run-plans.sh --self` with Bash
  disabled. Plans move through `incomplete/` → `inprogress/` → `complete/` or `failed/`
  as the runner works, each carrying a `.progress.md` log, a `.stream.jsonl` event
  stream, and a committed `.usage.json` cost sidecar.
- `verify/` — post-build verification plans, run unattended by `../../run-verify.sh
  --self` with Bash enabled, after this feature's auto plans finish. Same four-folder
  layout as `auto/`.
- `interactive/` — this feature's bash-heavy steps run by hand. Distinct from the
  top-level `../interactive/`, which holds standing runbooks that outlive any one
  feature.

The execution model — state folders, resume semantics, what the logs contain, how to
read a failure — is documented once in `../../RUNNER.md`. The four state folders get no
README of their own, per feature or per queue; this file documents the shape once for
every feature that will ever exist here.

**There is no separate archiving step.** The feature directory IS the archive: a
completed feature's `auto/complete/` and `verify/complete/` are its permanent record.

To start a new feature, copy the manifest skeleton from
`../../templates/plans/features/TEMPLATE.md` and fill it in at
`self/features/<slug>/README.md`. See `../../AGENT_PLANS.md` → "The feature manifest"
for what belongs in it — the template is shared with consuming repos even though the
rest of this tree is not.

## Features

- `plan-analytics` — cost measurement and the `plans/features/<slug>/` restructure that
  made a feature addressable. Plans `48`–`58`. Built before `--self` existed, out of
  `vinylCatalogue`'s queue, and moved here afterward.
- `agenttooling-self-host` — `--self` mode itself, this tree, and the move above. Plans
  `59`–`64`. Also built out of `vinylCatalogue`'s queue, necessarily: it is what made
  self-hosting possible.
```

## `agentTooling/self/interactive/README.md` (create)

```markdown
# Standing runbooks

Bash-heavy procedures for agentTooling that outlive any one feature and are run by hand.
No runner touches this directory — `run-plans.sh --self` drains
`../features/<slug>/auto/`, and `run-verify.sh --self` drains `.../verify/`.

A step belonging to one feature goes in that feature's own
`../features/<slug>/interactive/` instead; this directory is for procedures with no
feature to belong to, such as the `git subtree` push/pull cycle documented in
`../../README.md` → "Updating".

Empty for now.
```

## `agentTooling/sync-plans.sh`

The header comment explains what this script generates and what it deliberately leaves
alone. Add a paragraph to it recording that `self/` is out of scope and why:

```
# Scope: this writes into the CONSUMING repo's plans/ only. agentTooling's own corpus
# under self/ is hand-written and is never generated from templates/ — every stub here
# points back up at ../agentTooling/…, which is wrong from inside agentTooling, and this
# directory is the source those stubs point at rather than a copy of it. There is no
# --self flag; there would be nothing to generate.
```

## `agentTooling/AGENT_PLANS.md`

Plan authors need to know which corpus a feature belongs in. Directly after the
`## Precedence` section, add:

```markdown
## Which corpus a feature belongs in

Read the diff, not the cwd. A feature whose changes are confined to `agentTooling/` is
an agentTooling feature: its manifest and plans go in `agentTooling/self/features/<slug>/`
and it is run with `--self`. Everything else belongs in the consuming repo's
`plans/features/<slug>/`. A feature that genuinely spans both is a sign the harness
change should be split out and landed first.

Throughout this file, `plans/features/<slug>/` is written for the ordinary case. Under
`--self` read it as `agentTooling/self/features/<slug>/`; nothing else about authoring a
plan changes. The facts to pin come from `agentTooling/self/PROJECT_FACTS.md` instead of
`plans/PROJECT_FACTS.md`, and the gate report a verify plan reads is
`self/gate-report.txt` instead of `plans/gate-report.txt`.
```
