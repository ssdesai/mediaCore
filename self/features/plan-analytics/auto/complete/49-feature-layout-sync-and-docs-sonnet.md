# 49 — Feature-scoped plan tree: sync, templates, and the authoring rules

Feature: plan-analytics (plan 2 of 9) — tooling to price a feature end-to-end (planning
plus execution) and surface where delegated fanout wasted effort. This plan makes the
per-feature layout the documented default and teaches `sync-plans.sh` to generate it.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Independent of other plans. Runs alongside 48.

## Pinned facts

- `agentTooling/` is a `git subtree` shared across repos. `sync-plans.sh` regenerates
  exactly the paths named in its `GENERATED` array and unconditionally overwrites them.
  `PROJECT_FACTS.md` and `gate.sh` are seeded once, the first time they're missing, and
  never touched again after that.
- A new generated stub must be added to BOTH the `GENERATED` array (line 23) and the
  `mkdir -p` line (line 30) of `sync-plans.sh`.
- `sync-plans.sh` uses `set -euo pipefail`.
- `templates/plans/auto/README.md` and `templates/plans/verify/README.md` become
  obsolete — their content folds into the new `features/README.md`. A build executor
  cannot delete files, so this plan does not attempt to delete them or the repo's stale
  `plans/auto/`/`plans/verify/` trees; that deletion is interactive plan 51's job.
  Removing the two obsolete stubs from `GENERATED` is enough to stop them being
  regenerated, and that removal IS this plan's job.
- The four per-feature state folders (`incomplete/`, `inprogress/`, `complete/`,
  `failed/`, under both `auto/` and `verify/`) must NOT each get their own `README.md` —
  that's eight near-identical stubs per feature. `plans/features/README.md` documents
  the whole subtree shape once, for every feature. State this explicitly in that file so
  a later CONVENTIONS.md-following agent doesn't "fix" the apparent gap by adding one.

## Files

- Modify `agentTooling/sync-plans.sh`
- Create `agentTooling/templates/plans/features/README.md`
- Create `agentTooling/templates/plans/features/TEMPLATE.md`
- Modify `agentTooling/templates/plans/README.md`
- Modify `agentTooling/AGENT_PLANS.md`
- Modify `agentTooling/README.md`

## `agentTooling/sync-plans.sh`

Replace line 23:

```bash
GENERATED=(README.md auto/README.md verify/README.md interactive/README.md)
```

with:

```bash
GENERATED=(README.md interactive/README.md features/README.md features/TEMPLATE.md)
```

Replace line 30:

```bash
mkdir -p "$PLANS_DIR/auto" "$PLANS_DIR/verify" "$PLANS_DIR/interactive"
```

with:

```bash
mkdir -p "$PLANS_DIR/interactive" "$PLANS_DIR/features"
```

Nothing else in this file changes. The `PROJECT_FACTS.md` and `gate.sh` seed blocks
(lines 41–54) are untouched.

## `agentTooling/templates/plans/features/README.md` (create)

New generated stub — write exactly:

```markdown
# Feature plan trees

_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`. Edit the template, not this file._

Every feature this repo works on gets one directory here, named by its slug:

    plans/features/<slug>/
      README.md          the feature manifest — goal, plan table, exclusions, machine-readable JSON
      auto/{incomplete,inprogress,complete,failed}/     file-edit-only build plans (Bash disabled)
      verify/{incomplete,inprogress,complete,failed}/   post-build verification plans (Bash enabled)
      interactive/       bash-heavy steps run by hand, belonging to THIS feature
      planning.json      written later by the analysis tooling
      report.md / report.json

- `auto/` — build plans, run unattended by `../../agentTooling/run-plans.sh` with Bash
  disabled. Plans move through `incomplete/` → `inprogress/` → `complete/` or `failed/`
  as the runner works, each carrying a `.progress.md` log and a `.stream.jsonl` event
  stream.
- `verify/` — post-build verification plans, run unattended by
  `../../agentTooling/run-verify.sh` with Bash enabled, after this feature's auto plans
  finish. Same four-folder layout as `auto/`.
- `interactive/` — this feature's bash-heavy steps run by hand (migrations, one-off
  ops). Distinct from the top-level `../interactive/`, which holds standing runbooks
  that outlive any one feature (e.g. first-run setup).

The execution model itself — state folders, resume semantics, what the logs contain,
how to read a failure — is documented once in `../../agentTooling/RUNNER.md`, not
repeated per feature.

**There is no separate archiving step.** The feature directory IS the archive: a
completed feature's `auto/complete/` and `verify/complete/` are its permanent record,
left in place. Nothing moves a finished feature elsewhere.

**The four state folders do not get their own `README.md`** — not per queue, not per
feature. Eight near-identical stubs (`auto/incomplete/README.md`,
`auto/complete/README.md`, and so on, repeated in every feature directory) would
document nothing this one file plus `RUNNER.md` doesn't already say. This README
documents the whole subtree shape once, for every feature that will ever exist here —
do not "fix" the apparent gap by adding one per folder.

To start a new feature, copy `features/TEMPLATE.md` to `plans/features/<slug>/README.md`
and fill it in. See `../../agentTooling/AGENT_PLANS.md` → "The feature manifest" for
what belongs in it.
```

## `agentTooling/templates/plans/features/TEMPLATE.md` (create)

New generated stub — the skeleton an author copies to `plans/features/<slug>/README.md`.
Write exactly (note the outer fence below is 4 backticks specifically so the inner
` ```json ` fence in the target file renders literally — write only the inner content to
the target file, not the outer fence):

````markdown
# <Feature title>

<One paragraph: what this feature delivers and why the work exists. No plan-level
detail — that's what the table below is for.>

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/NN-description-MODEL.md` | <one line> |
| `verify/incomplete/NN-verify-MODEL.md` | <one line> |

## Deliberately excluded

- <Something that looked in-scope but isn't — and why.>

## Machine-readable

```json
{
  "slug": "<feature-slug>",
  "branches": ["<branch-name>"],
  "session_window": {"from": "<YYYY-MM-DD>", "to": null},
  "exclude_sessions": ["<session-id>"]
}
```
````

## `agentTooling/templates/plans/README.md`

Replace:

```markdown
- `auto/` — file-edit-only build plans (Bash disabled)
- `verify/` — post-build verification plans (Bash enabled), run after the auto plans in a batch
- `interactive/` — bash-heavy steps run by hand
```

with:

```markdown
- `features/` — one directory per feature: its manifest plus its own `auto/`,
  `verify/`, and `interactive/`. See `features/README.md` for the full shape.
- `interactive/` — standing runbooks that outlive any one feature (e.g. first-run
  setup). A feature's own bash-heavy steps live in `features/<slug>/interactive/`
  instead.
```

The `PROJECT_FACTS.md` and `gate.sh` bullets directly below are unchanged.

Then, immediately after the closing ` ``` ` of the `run-batch.sh`/`run-plans.sh`/
`run-verify.sh` code block and before the "Shared documentation:" line, insert this new
paragraph:

```markdown
Each accepts an optional feature slug as its first argument; omitted, the runner infers
it from whichever feature has work queued, and errors if more than one does. See
`../agentTooling/RUNNER.md` → "Choosing a feature".
```

## `agentTooling/AGENT_PLANS.md`

Five separate edits, in file order.

### 1. Opening paragraph

Replace:

```markdown
Instructions for Claude when asked to generate plans for the delegated-execution workflow: **build plans** in `plans/auto/incomplete/` (run unattended by `run-plans.sh`, no bash) and, as the last plans in a batch, **verify plans** in `plans/verify/` (run afterward by `run-verify.sh` under a wider permission scope — see "Verify plans" below).
```

with:

```markdown
Instructions for Claude when asked to generate plans for the delegated-execution workflow: **build plans** in `plans/features/<slug>/auto/incomplete/` (run unattended by `run-plans.sh`, no bash) and, as the last plans in a batch, **verify plans** in `plans/features/<slug>/verify/` (run afterward by `run-verify.sh` under a wider permission scope — see "Verify plans" below).
```

### 2. Plan file format bullet

Replace:

```markdown
- One plan per file, in `plans/auto/incomplete/`.
```

with:

```markdown
- One plan per file, in `plans/features/<slug>/auto/incomplete/`.
```

### 3. Plan content — new item 1, renumber, plus the new section

Replace:

```markdown
Each plan must have, in this order:

1. **One-sentence summary** at the top.
2. **Dependency note** (only if needed): "Depends on: 01-*.md" or "Independent of other plans."
3. **File list** — every path to create/modify/delete. No prose descriptions of "what's involved."
4. **Per-file changes** — for each file, paste the exact code to add or the exact diff. Not prose.
```

with (the numbered list gains item 1 and renumbers; the new `## The feature manifest`
section is appended immediately after, still before the existing `## Writing the
per-file changes` heading — the outer fence here is 4 backticks only because this
replacement itself contains a ` ```json ` example fence):

````markdown
Each plan must have, in this order:

1. **Feature header**, directly under the title: the feature slug, this plan's position
   in the batch (`plan N of M`), and one or two sentences on what the whole feature
   does. Every plan in the batch repeats this — executors cold-start with no context
   from sibling plans, so the slug is both the machine-readable grouping key cost
   reports key off of and the only thing telling a reader six months later what this
   plan was part of.
2. **One-sentence summary** at the top.
3. **Dependency note** (only if needed): "Depends on: 01-*.md" or "Independent of other plans."
4. **File list** — every path to create/modify/delete. No prose descriptions of "what's involved."
5. **Per-file changes** — for each file, paste the exact code to add or the exact diff. Not prose.

## The feature manifest

One `plans/features/<slug>/README.md` per feature — written once, at plan-generation
time, by whoever authors the batch. Never written or edited by a build or verify
executor.

It holds what does not belong in every individual plan: the feature's goal, a table of
every plan in the batch and what it does, and what was deliberately excluded and why.
Plans repeat only the one-line feature header (see item 1 above); the manifest is where
the full picture lives. The plans themselves live in that feature's own `auto/`,
`verify/`, and `interactive/` subfolders — `plans/features/<slug>/auto/incomplete/`,
etc. — never in a shared top-level queue.

The manifest ends with a machine-readable fence:

```json
{
  "slug": "plan-analytics",
  "branches": ["browseImages"],
  "session_window": {"from": "2026-07-01", "to": null},
  "exclude_sessions": []
}
```

- `slug` — kebab-case, stable for the life of the feature; cost reports key off it.
- `branches` — every git branch the work happened on.
- `session_window` — optional. One branch can host several features in sequence — this
  repo's `browseImages` branch hosted three — so `branches` alone over-attributes
  planning cost to whichever feature you're asking about. `session_window` narrows
  attribution to a date range.
- `exclude_sessions` — optional escape hatch for sessions inside that window that still
  belong to a different feature. Both `session_window` and `exclude_sessions` are
  optional and usually absent.

See `templates/plans/features/TEMPLATE.md` for the skeleton to copy.
````

### 4. Split work by executor capability

Replace:

```markdown
belongs elsewhere: automated test/verification in the batch's **verify plan**, and
human-run migrations/ops in a sibling `plans/interactive/NN-description.md`.
```

with:

```markdown
belongs elsewhere: automated test/verification in the batch's **verify plan**, and
human-run migrations/ops in a sibling `plans/features/<slug>/interactive/NN-description.md`.
```

### 5. Verify plans — "Run by a separate script" bullet

Replace:

```markdown
- **Run by a separate script, not `run-plans.sh`.** Verify plans live in `plans/verify/` and run afterward under `run-verify.sh`, which scopes permissions differently: bash enabled, a high-level model, and latitude to read broadly, run typecheck/tests, and fix or report defects the build executors couldn't catch. Keeping this in its own script and directory is deliberate — the build runner stays bash-free, and only the verify pass gets the wider scope.
```

with:

```markdown
- **Run by a separate script, not `run-plans.sh`.** Verify plans live in `plans/features/<slug>/verify/` and run afterward under `run-verify.sh`, which scopes permissions differently: bash enabled, a high-level model, and latitude to read broadly, run typecheck/tests, and fix or report defects the build executors couldn't catch. Keeping this in its own script and directory is deliberate — the build runner stays bash-free, and only the verify pass gets the wider scope.
```

### 6. After generating plans — name the manifest path

Replace:

```markdown
End with a short summary:
- Number of plans generated
- Files touched across all plans (unique count)
- Any plans that could run in parallel
- Any mechanical plans you recommend I do by hand instead
```

with:

```markdown
End with a short summary:
- The feature manifest path written (`plans/features/<slug>/README.md`)
- Number of plans generated
- Files touched across all plans (unique count)
- Any plans that could run in parallel
- Any mechanical plans you recommend I do by hand instead
```

## `agentTooling/README.md`

Four separate edits.

### 1. `sync-plans.sh` table row

Replace:

```markdown
| `sync-plans.sh` | Writes the generated `plans/` README stubs from `templates/`. Run at install and after every `subtree pull`. Never touches `plans/PROJECT_FACTS.md`. |
```

with:

```markdown
| `sync-plans.sh` | Writes the generated `plans/` stubs (`README.md`, `interactive/README.md`, `features/README.md`, `features/TEMPLATE.md`) from `templates/`. Run at install and after every `subtree pull`. Never touches `plans/PROJECT_FACTS.md`. |
```

### 2. Step 3 ("Create `plans/`")

Replace:

```markdown
That creates `auto/`, `verify/`, `interactive/`, writes their README stubs, and seeds
`plans/PROJECT_FACTS.md` from the skeleton. The queue state directories
(`incomplete/`, `inprogress/`, `complete/`, `failed/`) are not created here — git
doesn't track empty directories, and the runners make them on first use.
```

with:

```markdown
That creates `features/`, `interactive/`, writes their README/template stubs, and
seeds `plans/PROJECT_FACTS.md` from the skeleton. A feature's own queue state
directories (`incomplete/`, `inprogress/`, `complete/`, `failed/`, under
`features/<slug>/auto/` and `.../verify/`) are not created here — git doesn't track
empty directories, and the runners make them on first use.
```

### 3. "You're ready" line

Replace:

```markdown
You're ready: author plans per `AGENT_PLANS.md` into `plans/auto/incomplete/`, then
run the batch.
```

with:

```markdown
You're ready: author plans per `AGENT_PLANS.md` into
`plans/features/<slug>/auto/incomplete/`, then run the batch.
```

### 4. "What stays in the consuming repo"

Replace:

```markdown
Everything under `plans/` — `auto/`, `verify/`, `interactive/`, the plan corpus and
its execution history, `PROJECT_FACTS.md`, and `plans/README.md`. Only the shared
machinery and doctrine live here.
```

with:

```markdown
Everything under `plans/` — `features/`, `interactive/`, the plan corpus and
its execution history, `PROJECT_FACTS.md`, and `plans/README.md`. Only the shared
machinery and doctrine live here.
```
