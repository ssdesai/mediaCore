# 50 — Migration script and the historical feature manifests

Feature: plan-analytics (plan 3 of 9) — tooling to price a feature end-to-end (planning
plus execution) and surface where delegated fanout wasted effort. This plan writes the
one-time migration into the per-feature layout, plus a manifest for each batch that
already ran, so historical work is reportable too.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before editing.

Depends on: 48 and 49 for the layout they define; writes files, moves none.

## Pinned facts

- `agentTooling/` is a `git subtree` shared across repos (same fact plan 48 pins). The
  migration script is repo-agnostic: it must derive slugs from directory names it finds
  on disk, never hardcode the five slugs from Part B below. Those five are *this* repo's
  data, written straight into `plans/features/`, not into the shared script.
- Target shell is bash 3.2 (macOS system bash) — same constraint plan 48 pins for
  `plan-runner-lib.sh`. No associative arrays, no `mapfile`. Initialise every array with
  `arr=()`. Any glob that can legitimately match zero entries needs
  `shopt -s nullglob` first, or an empty directory expands to the literal unmatched
  pattern string and downstream `basename`/`mkdir` calls operate on garbage.
- `.gitignore` (repo root) contains exactly:
  ```
  plans/**/*.stream.jsonl
  plans/**/*.logfifo
  ```
  `.md` and `.progress.md` sidecars are tracked; `.stream.jsonl` and `.logfifo` are not.
  `git mv` errors on an untracked path, so the move helper must dispatch on tracked-ness
  (`git ls-files --error-unmatch`), not on file extension — a future `.usage.json`
  sidecar (plan 49) is tracked and must go through `git mv` like the `.md` files.
- The four state directories are always `incomplete`, `inprogress`, `complete`, `failed`,
  under each of the two queues `auto` and `verify`.
- `browseImages` hosted three features in sequence — manual-readings-and-browse,
  image-versions-and-copies, and plan-analytics — so pricing by branch alone would count
  the same planning sessions three times. That is why `session_window` appears on
  exactly the two manifests below that need to split that branch's history; the dates
  are a provisional boundary a human confirms in plan 51, not verified fact.
- `sync-plans.sh` derives its own location like this (paste verbatim into the new
  script):
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  ```
- `agentTooling/sync-plans.sh` and `agentTooling/run-plans.sh` are both committed with
  the executable bit set (mode `100755`). A plan executor writing a new file has no
  Bash tool and cannot set that bit — say so in the script's own section below so
  nobody expects this plan to have done it. Plan 51 (interactive, has Bash) must
  `chmod +x agentTooling/migrate-plans-layout.sh` before running it.

## Files

- Create `agentTooling/migrate-plans-layout.sh`
- Create `plans/features/core-library-and-gui/README.md`
- Create `plans/features/collection-selection/README.md`
- Create `plans/features/extractor-backends/README.md`
- Create `plans/features/manual-readings-and-browse/README.md`
- Create `plans/features/image-versions-and-copies/README.md`
- Modify `agentTooling/README.md`

## `agentTooling/migrate-plans-layout.sh`

One-time, repo-agnostic migration from the flat `plans/{auto,verify}/{state}/` queue to
the per-feature `plans/features/<slug>/{auto,verify}/{state}/` layout that plan 48's
runner now reads. Shipped in the shared subtree because every consuming repo needs to
run this exactly once, the same way `sync-plans.sh` is shared.

**Cannot be set executable by this plan's executor (no Bash tool) — note this inline as
a comment near the top of the file, and leave it for plan 51 to `chmod +x`.**

### Header and setup

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Then the doc comment: what it does, that it is safe to re-run (idempotent), that
`--dry-run` is the default-safe path to reach for first, and that Rule 1's archive-name
slugs are a starting point — renaming a slug to something better afterwards is a human
step, not this script's.

Then, pasted verbatim from the Pinned Facts block above, the `SCRIPT_DIR`/`REPO_DIR`
two lines, followed by:

```bash
PLANS_DIR="$REPO_DIR/plans"
FEATURES_DIR="$PLANS_DIR/features"
QUEUES=(auto verify)
STATES=(incomplete inprogress complete failed)

DRY_RUN=0
LOOSE_SLUG=""
MOVE_COUNT=0
```

### Argument parsing

A `while (( "$#" ))` loop over `case "$1" in ... esac`, structurally:

- `--dry-run` → `DRY_RUN=1; shift`
- `--loose-slug` → requires a following value (`${2:?"--loose-slug needs a value"}`),
  sets `LOOSE_SLUG="$2"; shift 2`
- `--help` → print usage (see below) and `exit 0`
- anything else → print "unknown flag: $1", print usage, `exit 1`

`--help` output: a usage line (`Usage: migrate-plans-layout.sh [--dry-run] [--loose-slug SLUG] [--help]`)
plus one line per flag describing what it does, plus a closing line recommending
`--dry-run` be run first. Keep it to what's stated here — don't invent additional flags.

If `DRY_RUN` is set, print a one-line banner before doing anything else:
`"DRY RUN — printing planned moves, changing nothing."`

### Guards

Both guards run before any migration logic, in this order:

1. `plans/features` must exist (`[[ -d "$FEATURES_DIR" ]]`), **regardless of
   `--dry-run`** — if it's missing, print an error naming plan 48/49 as the prerequisite
   and `exit 1`.
2. The clean-tree guard — **paste this verbatim**, since it is the non-obvious
   correctness fragment (the reason `--dry-run` is carved out is that the whole check
   exists only to protect a real `git mv`):

```bash
if (( DRY_RUN == 0 )); then
  if ! git diff-index --quiet HEAD --; then
    echo "ERROR: working tree has uncommitted changes. This script uses 'git mv' so" >&2
    echo "       history follows the moved files; commit or stash first, or re-run" >&2
    echo "       with --dry-run to preview without that requirement." >&2
    exit 1
  fi
fi
```

### The move helper — paste this verbatim

This is the single most likely bug: `git mv` aborts on an untracked path (a gitignored
`.stream.jsonl`), so every move must dispatch on tracked-ness, not on extension.

```bash
# git mv aborts on an untracked path (e.g. a gitignored .stream.jsonl); plain mv is
# fine there since there's no history to carry. Dispatch on tracked-ness, not on the
# extension — .progress.md sidecars are tracked, .stream.jsonl and .logfifo aren't.
move_one() {
  local from="$1" to="$2"
  if (( DRY_RUN == 0 )); then
    if git ls-files --error-unmatch "$from" >/dev/null 2>&1; then
      git mv "$from" "$to"
    else
      mv "$from" "$to"
    fi
  fi
  echo "  moved  $from  ->  $to"
  MOVE_COUNT=$((MOVE_COUNT + 1))
}
```

### A skeleton helper

A small function, `ensure_skeleton <slug>`, that runs
`mkdir -p "$FEATURES_DIR/$slug"/{auto,verify}/{incomplete,inprogress,complete,failed} "$FEATURES_DIR/$slug/interactive"`
— the full skeleton for both queues, regardless of which queue's archive triggered the
call. `mkdir -p` is naturally idempotent and never touches an existing `README.md`, so
no extra guard is needed here; the "never overwrite README.md" rule instead lives in the
per-file move logic below, where an actual `README.md` could collide.

### Rule 1 — archives

For each `queue` in `QUEUES`, with `shopt -s nullglob` in effect, iterate
`"$PLANS_DIR/$queue/complete"/*/ ` (directories only). For each match:

- `slug="$(basename "$dir")"` (strip trailing slash first)
- `ensure_skeleton "$slug"`
- `target="$FEATURES_DIR/$slug/$queue/complete"`
- for each file directly inside `$dir` (not recursing — these archives are flat, e.g.
  `plans/auto/complete/browseImages/*.md`, `*.progress.md`, `*.stream.jsonl` sitting
  side by side): if its basename is `README.md` **and** `"$target/README.md"` already
  exists, print `"  skip    $from (README.md already exists at destination)"` and
  continue without moving it; otherwise call `move_one "$from" "$target/$(basename "$from")"`.
- after the file loop, `rmdir "$dir" 2>/dev/null || true` — removes the now-empty
  archive folder; harmless no-op if a skipped `README.md` left it non-empty, and that
  same state is what a second run will see (idempotent, not a bug).

State plainly in a comment: the slug here is just the archive directory's name
(`browseImages`, `pr1-implementation`, …) — picking a better name, or splitting one
archive across more than one feature, is a human step afterward, not this rule's job.

### Rule 2 — loose files

Loose files are anything sitting directly as a *file* (not inside a subdirectory) in
`plans/<queue>/<state>/` for every `queue` in `QUEUES` and `state` in `STATES` — this
runs after Rule 1, so anything Rule 1 already archived is gone from `complete/` and
won't double-count.

- Build one flat list, `LOOSE_FOUND`, of every such file path across all eight
  `(queue, state)` combinations (`shopt -s nullglob` applies here too).
- If `LOOSE_FOUND` is empty, skip this rule entirely (no error, regardless of whether
  `--loose-slug` was passed).
- If `LOOSE_FOUND` is non-empty and `LOOSE_SLUG` is empty: print
  `"Loose plan files found — pass --loose-slug to migrate them:"` followed by one
  `"  loose   <path>"` line per file, then `exit 1`. Do not guess a slug.
- If `LOOSE_FOUND` is non-empty and `LOOSE_SLUG` is set: `ensure_skeleton "$LOOSE_SLUG"`,
  then for each file, `move_one "$from" "$FEATURES_DIR/$LOOSE_SLUG/$queue/$state/$(basename "$from")"`
  (using that file's own `queue`/`state`, not a fixed one).

Note in a comment: `--loose-slug` is one value for the whole run, so if loose files
currently span more than one intended feature (this repo's `plans/auto/incomplete/`
loose files and its `plans/auto/complete/` loose files are, at time of writing, two
different features), migrating them correctly takes more than one invocation — run
once per group, moving the other group's files aside first if a single run's glob would
otherwise catch both. That reconciliation is plan 51's job, not this script's.

### Summary and exit

After both rules: if `MOVE_COUNT -eq 0`, print `"Nothing to migrate."`; otherwise print
`"$MOVE_COUNT file(s) moved."`. Exit 0 in both cases (Rule 2's `exit 1` above is the only
non-zero path once the guards pass).

## `plans/features/<slug>/README.md` — the five historical manifests

All five share one shape, matching `plans/features/plan-analytics/README.md:1-79`
exactly:

```
# <slug>

<goal paragraph(s), given verbatim per feature below>

## Plans

| Plan | What it does |
|---|---|
<one row per stem listed below, in that order>

## Machine-readable

```json
<object given verbatim per feature below>
```
```

For the `## Plans` table: write one row per stem, `| <stem> | <clause>. |`, where
`<clause>` is a short sentence you write yourself from the stem's own words alone (e.g.
`02-models-sonnet` → "Data models."). **Do not open the archived plan files to check** —
that reads dozens of files for zero benefit here; the stem is all the signal this table
needs, the same way `plan-analytics`'s table entries are one clause each.

For `## Machine-readable`: paste the JSON object given for that feature verbatim,
unchanged — `slug`, `branches`, `plans` (the same stems, as a JSON array, same order),
`exclude_sessions` (always `[]` for these five), and `session_window` only where given.

### `core-library-and-gui`

Goal paragraph:

> The initial build: packaging, models, ingest and pairing, vision extraction, the
> transcription verification core, the FastAPI web API, the CLI, and the React
> transcription GUI.

Stems, in order:

```
01-packaging-core-sonnet
02-models-sonnet
03-ingest-pair-status-sonnet
04-extract-sonnet
05-verify-core-sonnet
06-web-api-sonnet
07-cli-sonnet
08-frontend-scaffold-haiku
09-frontend-transcription-view-sonnet
10-tests-sonnet
11-verify-opus
```

Machine-readable object:

```json
{
  "slug": "core-library-and-gui",
  "branches": ["implementation"],
  "plans": [
    "01-packaging-core-sonnet",
    "02-models-sonnet",
    "03-ingest-pair-status-sonnet",
    "04-extract-sonnet",
    "05-verify-core-sonnet",
    "06-web-api-sonnet",
    "07-cli-sonnet",
    "08-frontend-scaffold-haiku",
    "09-frontend-transcription-view-sonnet",
    "10-tests-sonnet",
    "11-verify-opus"
  ],
  "exclude_sessions": []
}
```

### `collection-selection`

Goal paragraph:

> Choosing and switching collection roots from the GUI, so the app is not pinned to one
> folder at launch.

Stems, in order:

```
12-collection-core-haiku
13-web-collection-switching-sonnet
14-cli-gui-rootless-haiku
15-frontend-folder-picker-sonnet
16-frontend-collection-gating-sonnet
17-tests-collection-sonnet
18-verify-opus
```

Machine-readable object:

```json
{
  "slug": "collection-selection",
  "branches": ["gui-collection-selection"],
  "plans": [
    "12-collection-core-haiku",
    "13-web-collection-switching-sonnet",
    "14-cli-gui-rootless-haiku",
    "15-frontend-folder-picker-sonnet",
    "16-frontend-collection-gating-sonnet",
    "17-tests-collection-sonnet",
    "18-verify-opus"
  ],
  "exclude_sessions": []
}
```

### `extractor-backends`

Goal paragraph:

> A second extraction backend (the Claude CLI) alongside the API extractor, with
> per-backend settings, key gating, and session isolation. This feature ran two verify
> passes (23 and 27) because work continued after the first verify — real signal about
> the feature, not an error in this manifest.

Stems, in order:

```
19-claude-cli-extractor-sonnet
20-tests-claude-cli-sonnet
21-web-extractor-settings-sonnet
22-frontend-extractor-panel-sonnet
23-verify-opus
24-extract-key-gate-per-backend-haiku
25-claude-cli-session-isolation-haiku
26-tests-extractor-route-and-key-gate-sonnet
27-verify-opus
28-backend-requires-api-key-field-haiku
```

Machine-readable object:

```json
{
  "slug": "extractor-backends",
  "branches": ["extractor-backends"],
  "plans": [
    "19-claude-cli-extractor-sonnet",
    "20-tests-claude-cli-sonnet",
    "21-web-extractor-settings-sonnet",
    "22-frontend-extractor-panel-sonnet",
    "23-verify-opus",
    "24-extract-key-gate-per-backend-haiku",
    "25-claude-cli-session-isolation-haiku",
    "26-tests-extractor-route-and-key-gate-sonnet",
    "27-verify-opus",
    "28-backend-requires-api-key-field-haiku"
  ],
  "exclude_sessions": []
}
```

### `manual-readings-and-browse`

Goal paragraph:

> Manual transcription state and blank readings, the unlabelled-asset queue, the `label`
> CLI command, and the browse grid.
>
> This ran on the `browseImages` branch, which hosted three features in sequence — this
> one, image-versions-and-copies, and plan-analytics. Pricing by branch alone would
> count the same planning sessions against all three, so `session_window` scopes this
> manifest to the sessions up to 2026-07-22. That boundary is a provisional date a human
> confirms in plan 51, not a verified fact.

Stems, in order:

```
29-manual-state-and-blank-readings-haiku
30-verify-manual-write-path-haiku
31-web-unlabelled-assets-haiku
32-cli-label-command-sonnet
33-frontend-types-and-field-helpers-haiku
34-frontend-editable-reading-sonnet
35-frontend-browse-grid-sonnet
36-tests-manual-library-haiku
37-tests-manual-adapters-sonnet
38-verify-sonnet
```

Machine-readable object:

```json
{
  "slug": "manual-readings-and-browse",
  "branches": ["browseImages"],
  "plans": [
    "29-manual-state-and-blank-readings-haiku",
    "30-verify-manual-write-path-haiku",
    "31-web-unlabelled-assets-haiku",
    "32-cli-label-command-sonnet",
    "33-frontend-types-and-field-helpers-haiku",
    "34-frontend-editable-reading-sonnet",
    "35-frontend-browse-grid-sonnet",
    "36-tests-manual-library-haiku",
    "37-tests-manual-adapters-sonnet",
    "38-verify-sonnet"
  ],
  "exclude_sessions": [],
  "session_window": {"from": null, "to": "2026-07-22"}
}
```

### `image-versions-and-copies`

Goal paragraph:

> Per-asset image versions backed by real on-disk copies, version-aware extraction,
> version routes in the API, and the browse/viewer rework (thumbnails, fit-and-crop).
>
> Same `browseImages` branch-sharing problem as manual-readings-and-browse (see that
> manifest): the branch hosted three features in sequence, so `session_window` scopes
> this one to 2026-07-23 through 2026-07-29. Again, that boundary is provisional —
> confirmed by a human in plan 51, not asserted here as verified.

Stems, in order:

```
39-core-image-versions-sonnet
40-ingest-real-copies-haiku
41-extract-reads-active-version-sonnet
42-web-version-routes-sonnet
43-frontend-version-types-haiku
44-frontend-browse-thumbnails-sonnet
45-frontend-viewer-fit-and-crop-sonnet
46-tests-versions-and-copies-sonnet
47-verify-sonnet
```

Machine-readable object:

```json
{
  "slug": "image-versions-and-copies",
  "branches": ["browseImages"],
  "plans": [
    "39-core-image-versions-sonnet",
    "40-ingest-real-copies-haiku",
    "41-extract-reads-active-version-sonnet",
    "42-web-version-routes-sonnet",
    "43-frontend-version-types-haiku",
    "44-frontend-browse-thumbnails-sonnet",
    "45-frontend-viewer-fit-and-crop-sonnet",
    "46-tests-versions-and-copies-sonnet",
    "47-verify-sonnet"
  ],
  "exclude_sessions": [],
  "session_window": {"from": "2026-07-23", "to": "2026-07-29"}
}
```

## `agentTooling/README.md`

In the `## Contents` table, insert a new row immediately after this existing row (match
it verbatim to find the spot):

```
| `sync-plans.sh` | Writes the generated `plans/` README stubs from `templates/`. Run at install and after every `subtree pull`. Never touches `plans/PROJECT_FACTS.md`. |
```

New row to insert after it:

```
| `migrate-plans-layout.sh` | One-time, repo-agnostic migration from the flat `plans/{auto,verify}/{state}/` queue to the per-feature `plans/features/<slug>/{auto,verify}/{state}/` layout (see `RUNNER.md`). `--dry-run` first; otherwise requires a clean working tree, since it uses `git mv` so history follows the moved files. Not part of the ordinary batch flow — run once, by a human. |
```

No other line in `agentTooling/README.md` changes.
