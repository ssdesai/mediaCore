# 51 — Migrate `plans/` to the per-feature layout (run by hand)

Feature: plan-analytics. Plans 48–50 changed what the runner *reads* and wrote the
migration script; nothing has moved on disk yet. Build executors have no bash, so the
move itself is here. Run this after batch A (plans 48, 49, 50) finishes and before
batch B (52–57).

This lands as two commits — the runner change (step 3) and the move (step 10). Do not push
until step 9 passes.

## 0. Preconditions

```bash
git status --short          # must be clean apart from the batch-A output
ls plans/auto/complete/     # 48, 49, 50 should be here, having just run
```

Batch A is run with `./agentTooling/run-plans.sh`, **not** `run-batch.sh` — the layout
change has no verify plan (its verification is this file, with a human present), and
`plans/verify/incomplete/` is deliberately empty.

Note what just happened: plans 48–50 rewrote `run-plans.sh` and `plan-runner-lib.sh`
*while that runner was executing them*. That is safe here only because bash had already
consumed both files by the time `run_all` started — `run_all` is the last line of
`run-plans.sh`, and the `source` of the library completes before it. The edits take
effect on the **next** invocation, which is step 9. Do not re-run the build pass before
migrating; it would drain batch B's queue under half-migrated assumptions.

## 1. Rename the archive folders to their final slugs

The migration script derives each feature's slug from the archive folder name, and plan
50 wrote the historical manifests at the *descriptive* slugs. Renaming first is what
makes those two meet; doing it afterwards would leave five manifests orphaned beside
five differently-named directories.

```bash
for q in auto verify; do
  mv plans/$q/complete/pr1-implementation           plans/$q/complete/core-library-and-gui
  mv plans/$q/complete/pr2-gui-collection-selection plans/$q/complete/collection-selection
  mv plans/$q/complete/pr3-extractor-backends       plans/$q/complete/extractor-backends
  mv plans/$q/complete/browseImages                 plans/$q/complete/manual-readings-and-browse
done
```

Plain `mv`, not `git mv`: these directories hold gitignored `.stream.jsonl` files
alongside tracked plans, and `git mv` refuses the ignored ones. `git add -A` at step 3
records the renames anyway — git detects them by content, not by how the file moved.

## 2. Pre-stage the two un-archived batches

`plans/auto/complete/` also holds loose plans from two batches that were never archived:
39–46 (`image-versions-and-copies`) and the 48–50 you just ran (`plan-analytics`). The
migration script refuses to guess which loose file belongs to which feature — correctly,
since here the answer is "two different ones". Turning both into archive folders first
means the script sees only the case it can handle unambiguously.

```bash
mkdir -p plans/auto/complete/image-versions-and-copies \
         plans/verify/complete/image-versions-and-copies \
         plans/auto/complete/plan-analytics

mv plans/auto/complete/39-* plans/auto/complete/4[0-6]-* plans/auto/complete/image-versions-and-copies/
mv plans/verify/complete/47-*                            plans/verify/complete/image-versions-and-copies/
mv plans/auto/complete/48-* plans/auto/complete/49-* plans/auto/complete/50-* plans/auto/complete/plan-analytics/
```

Confirm nothing is left loose before continuing:

```bash
ls plans/auto/complete/*.md plans/verify/complete/*.md 2>/dev/null   # expect "No such file"
```

## 3. Commit batch A, and make the script executable

The migration refuses to run against a dirty tree — it uses `git mv`, and the guard exists
so a bad run is recoverable with `git checkout`. Batch A's output plus steps 1 and 2 have
left plenty uncommitted, so commit before going further:

```bash
git add -A
git commit -m "Feature-scoped plan runner, migration script, archive renames"
```

Two commits rather than one is the right shape here: this one is *the runner changed*, and
step 10's is *the files moved*. If the migration goes wrong, that boundary is what you reset
to.

Plan 50's executor had no Bash tool and could not set the executable bit:

```bash
chmod +x agentTooling/migrate-plans-layout.sh
git update-index --chmod=+x agentTooling/migrate-plans-layout.sh
```

## 4. Dry-run the migration

```bash
./agentTooling/migrate-plans-layout.sh --dry-run
```

Expect only archive moves — six features across the two queues — and **zero** loose
files reported. If it lists loose files, step 2 missed something; fix that rather than
reaching for `--loose-slug`, which would file them all under one feature.

Read the destination paths in the output before running for real. This is the only
point at which a wrong slug is cheap to correct.

## 5. Run it

```bash
./agentTooling/migrate-plans-layout.sh
```

Then check the shape:

```bash
find plans/features -maxdepth 2 -type d | sort
ls plans/features/*/README.md
```

Six feature directories, each with a `README.md` manifest: `core-library-and-gui`,
`collection-selection`, `extractor-backends`, `manual-readings-and-browse`,
`image-versions-and-copies`, `plan-analytics`.

**Then confirm the two `session_window` dates**, which plan 50 wrote as estimates and
flagged as provisional. Three features share the `browseImages` branch, so the windows
are the only thing keeping them from each claiming all of that branch's planning
sessions. Find the real boundaries:

```bash
git log --format='%ad %s' --date=short -- plans/features/manual-readings-and-browse \
                                          plans/features/image-versions-and-copies | tail -30
```

The handover date is where the last `29`–`38` plan was committed and the first `39`–`47`
plan appears. Edit `manual-readings-and-browse`'s `to` and `image-versions-and-copies`'s
`from` to straddle it, leaving no gap and no overlap. `plan-analytics` starts the day
after `image-versions-and-copies` ends.

Getting this wrong is not loud: the reports still generate, they just each bill the same
sessions. If two of the three come back with near-identical planning cost, that is the
symptom.

## 6. Move the feature-specific interactive plan

```bash
mv plans/interactive/48-migrate-collection-to-copies.md \
   plans/features/image-versions-and-copies/interactive/
```

`plans/interactive/01-first-run-real-photos.md` stays where it is — top-level
`interactive/` is for standing runbooks that outlive any one feature, and a first-run
setup guide is exactly that.

## 7. Delete the legacy trees and the obsolete templates

Build executors cannot delete files, so plans 48–50 could only stop *generating* these.
Check they are empty, then remove them:

```bash
find plans/auto plans/verify -type f        # expect no output
rm -rf plans/auto plans/verify
rm agentTooling/templates/plans/auto/README.md agentTooling/templates/plans/verify/README.md
rmdir agentTooling/templates/plans/auto agentTooling/templates/plans/verify
```

If `find` prints anything, stop and look — a file there means the migration skipped it.

## 8. Sync the generated stubs

```bash
./agentTooling/sync-plans.sh
```

Expect `synced plans/features/README.md`, `synced plans/features/TEMPLATE.md`, a synced
or unchanged `plans/README.md` and `plans/interactive/README.md`, and `kept` for both
`PROJECT_FACTS.md` and `gate.sh`. A `created` on either of those last two means the
repo-owned file was lost — stop and restore it.

There should be no line mentioning `plans/auto/README.md` or `plans/verify/README.md`.
If there is, plan 49's `GENERATED` edit didn't land.

## 9. Smoke-test the runner

Syntax first — three of these were edited by a bash-free executor that could not run them:

```bash
for f in agentTooling/*.sh; do bash -n "$f" && echo "ok  $f"; done
```

Then exercise the one genuinely new function directly, rather than by starting a run you
would have to interrupt:

**Run this through `bash`, not in your shell.** The interactive shell here is zsh, which
has no `shopt` and indexes arrays from 1 — a subshell `( ... )` inherits zsh and the test
fails on `candidates[0]: parameter not set`, which looks exactly like a bug in
`resolve_feature` and is not one. Pipe it to `bash` so it runs under the shell the runner
actually uses:

```bash
bash <<'EOF'
set -uo pipefail
REPO_DIR="$PWD"; FEATURES_DIR="$PWD/plans/features"; QUEUE=auto
PLAN_KIND=plan; SUMMARY_TITLE=x; CLAUDE_TOOL_ARGS=()
shopt -s nullglob
source agentTooling/plan-runner-lib.sh
resolve_feature "" && echo "inferred: [$FEATURE_SLUG]"
resolve_feature nonesuch || echo "correctly rejected an unknown slug"
resolve_feature plan-analytics && echo "accepted: [$FEATURE_SLUG]"
QUEUE=verify
resolve_feature "" && echo "verify queue inferred: [$FEATURE_SLUG]"
EOF
```

`inferred: [plan-analytics]` is the expected first line — it is the only feature with
anything left in `auto/incomplete/`. The unknown slug must print the error and the list of
known features. The verify-queue call must also land on `plan-analytics` (plan 57). If
inference returns empty, the queue didn't move; if it errors with "2 features have queued
plans", something was filed under the wrong feature in step 2.

## 10. Update the status line and commit

`plans/PROJECT_FACTS.md` has a status line naming the current batch and layout. Correct
it: batches 1–6 plus the layout migration are complete, plans live under
`plans/features/<slug>/`, and batch B (52–57) is authored and queued.

```bash
git add -A
git status --short | head -40    # read this before committing — it is a large diff
git commit -m "Move the plan queue under plans/features/<slug>/"
```

## 11. What runs next

```bash
./agentTooling/run-batch.sh plan-analytics
```

The slug is optional — inference would find it — but pass it explicitly the first time,
so a wrong inference shows up as an error rather than as a batch running somewhere
unexpected. Then work through
`plans/features/plan-analytics/interactive/58-plan-analytics-install.md`.

Do **not** push the subtree yet. Plan 58 does that once, after batch B, so `agentTooling/`
goes upstream in one piece rather than in two halves that each fail the other's checks.
