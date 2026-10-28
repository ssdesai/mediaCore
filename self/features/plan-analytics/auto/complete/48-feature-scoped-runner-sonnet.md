# 48 — Runner resolves a feature, not a fixed queue path

Feature: plan-analytics (plan 1 of 9) — tooling to price a feature end-to-end (planning
plus execution) and surface where delegated fanout wasted effort. This plan moves the
plan queue from `plans/auto/…` to `plans/features/<slug>/auto/…` so that everything
about one feature — its manifest, its plans, its logs, its cost record — sits in one
directory. Nothing can be reported per-feature until the queue is scoped per-feature.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README/doc files explicitly listed below.

Independent of other plans. Runs first in this batch.

## Pinned facts

- `agentTooling/` is a `git subtree` shared across repos. `plan-runner-lib.sh` is
  sourced by `run-plans.sh` and `run-verify.sh`; `run-batch.sh` shells out to both.
- `run-plans.sh` and `run-verify.sh` start with `set -uo pipefail` (**no `-e`**).
  `plan-runner-lib.sh` has no shebang and sets no options — it inherits the wrapper's.
- Target shell is **bash 3.2** (the system bash on macOS): no associative arrays, no
  `mapfile`, and `${#arr[@]}` on an array that was never assigned aborts under `set -u`.
  Every array below is initialised with `arr=()` first, matching the existing code at
  `plan-runner-lib.sh` line 40.
- `list_plans` (line 62) globs `"$dir"/[0-9]*.md` and depends on `nullglob` — without it
  an empty directory yields the literal pattern string. `run_all` currently sets
  `shopt -s nullglob` at line 311, *after* the point where feature resolution now has to
  happen. The `shopt` therefore moves up.
- The four `*_DIR` globals are currently derived at **source time** (lines 20–23), from a
  `PLAN_DIR` the wrapper sets before sourcing. They must become runtime assignments,
  because the directory is no longer known until the feature is resolved.
- `print_status` reads those four globals from an `EXIT` trap. They are ordinary globals,
  so assigning them inside `run_all` still works — but they must **not** be declared
  `local` there, or the trap sees empty strings.
- There is currently no automated archiving. Completed batches were moved into
  branch-named subfolders (`plans/auto/complete/browseImages/`) **by hand**. Under the
  new layout the feature directory is the archive boundary, so that habit stops.
- Moving the existing files on disk is **not** this plan's job — plan 50 writes the
  migration script and plan 51 runs it. This plan only changes what the runner reads.

## Files

- Modify `agentTooling/plan-runner-lib.sh` — the real change
- Modify `agentTooling/run-plans.sh` — 3 lines
- Modify `agentTooling/run-verify.sh` — 3 lines
- Modify `agentTooling/run-batch.sh` — forward the slug to both passes, and carry an
  inferred slug from the build pass to the verify pass
- Modify `agentTooling/RUNNER.md` — docs

Read `plan-runner-lib.sh` in full. The other three shell files are small and the exact
replacement lines are given below — do not read further afield than the lines quoted.

## `agentTooling/plan-runner-lib.sh`

### 1. Replace the header contract block and the derived dirs

Replace lines 8–23 (from `#   REPO_DIR         — repo root;` through
`FAILED_DIR="$PLAN_DIR/failed"`) with exactly:

```bash
#   REPO_DIR         — repo root; the runner cd's here so claude runs from root
#   FEATURES_DIR     — $REPO_DIR/plans/features, the root of the per-feature tree
#   QUEUE            — which queue this runner drains: "auto" or "verify"
#   PLAN_KIND        — singular noun for log lines: "plan" or "verify plan"
#   SUMMARY_TITLE    — header for the end-of-run status block
#   CLAUDE_TOOL_ARGS — array of extra claude flags scoping tool access; this is
#                      the security boundary between the two runners
#                      (--disallowedTools Bash vs --allowedTools Bash)
#   build_prompt <plan_path> <log_path> — echoes the executor prompt for one plan
# then calls: run_all "$@"

# Set by run_all once the feature is resolved — NOT at source time, because which
# directory this run drains is not known until then. Declared here (rather than left
# unset) so the EXIT trap can read them even if the run dies early under `set -u`.
FEATURE_SLUG=""
PLAN_DIR=""
INCOMPLETE_DIR=""
INPROGRESS_DIR=""
COMPLETE_DIR=""
FAILED_DIR=""
```

### 2. Name the feature in the status block

In `print_status`, replace:

```bash
  echo "  $SUMMARY_TITLE: $exit_reason"
```

with:

```bash
  echo "  $SUMMARY_TITLE [${FEATURE_SLUG:-none}]: $exit_reason"
```

### 3. Add the resolver

Insert this function immediately **after** `list_plans` (it calls `list_plans`, so it
must come after it in the file) and before `extract_model`:

```bash
# Decide which feature's queue this run drains. Plans live under
# plans/features/<slug>/<queue>/{incomplete,inprogress,complete,failed}; a run operates
# on exactly one feature, and the feature directory is what makes a batch's plans, logs
# and cost records addressable as a unit.
#
# The slug may be passed explicitly (first arg to run_all). Otherwise it is inferred
# from whichever feature has work sitting in this queue. Inference is deliberately
# all-or-nothing: two features with queued work is an ERROR, not a pick. Guessing wrong
# does not merely run the wrong plans — it files their completed logs, streams and
# usage records under another feature, corrupting a cost report that nothing downstream
# can detect as wrong.
#
# Sets FEATURE_SLUG. Leaves it empty (returning 0) when nothing is queued anywhere:
# an empty queue is a no-op, the same as it was before this was per-feature.
resolve_feature() {
  local requested="${1:-}"
  local d slug

  if [[ -n "$requested" ]]; then
    if [[ ! -d "$FEATURES_DIR/$requested" ]]; then
      echo "ERROR: no such feature: plans/features/$requested" >&2
      echo "  known features:" >&2
      for d in "$FEATURES_DIR"/*/; do echo "    $(basename "$d")" >&2; done
      return 1
    fi
    FEATURE_SLUG="$requested"
    return 0
  fi

  local candidates=()
  for d in "$FEATURES_DIR"/*/; do
    slug="$(basename "$d")"
    if [[ -n "$(list_plans "$d$QUEUE/incomplete")$(list_plans "$d$QUEUE/inprogress")" ]]; then
      candidates+=("$slug")
    fi
  done

  if (( ${#candidates[@]} == 0 )); then
    FEATURE_SLUG=""
    return 0
  fi

  if (( ${#candidates[@]} > 1 )); then
    echo "ERROR: ${#candidates[@]} features have queued ${PLAN_KIND}s; name one explicitly:" >&2
    for slug in "${candidates[@]}"; do
      echo "    $(basename "$0") $slug" >&2
    done
    return 1
  fi

  FEATURE_SLUG="${candidates[0]}"
  return 0
}
```

### 4. Rework the top of `run_all`

Replace the first five lines of `run_all` — from `run_all() {` through
`shopt -s nullglob` — with exactly:

```bash
run_all() {
  require_tools
  cd "$REPO_DIR"
  # Before resolve_feature, not after: list_plans globs, and without nullglob an empty
  # queue directory expands to the literal pattern and reads as "has work queued".
  shopt -s nullglob

  resolve_feature "${1:-}" || exit 2

  if [[ -z "$FEATURE_SLUG" ]]; then
    echo "No ${PLAN_KIND}s queued under plans/features/*/$QUEUE/incomplete. Nothing to do."
    return 0
  fi

  PLAN_DIR="$FEATURES_DIR/$FEATURE_SLUG/$QUEUE"
  INCOMPLETE_DIR="$PLAN_DIR/incomplete"
  INPROGRESS_DIR="$PLAN_DIR/inprogress"
  COMPLETE_DIR="$PLAN_DIR/complete"
  FAILED_DIR="$PLAN_DIR/failed"
  mkdir -p "$INCOMPLETE_DIR" "$INPROGRESS_DIR" "$COMPLETE_DIR" "$FAILED_DIR"

  echo "Feature: $FEATURE_SLUG   queue: $QUEUE"

  # Report the resolved slug to a caller that asked for it, so run-batch.sh can hand the
  # verify pass the same feature the build pass chose instead of letting it infer again.
  if [[ -n "${FEATURE_SLUG_OUT:-}" ]]; then
    echo "$FEATURE_SLUG" > "$FEATURE_SLUG_OUT"
  fi
```

The `trap` lines and both phases that follow are unchanged. Note the exit code: an
unresolvable feature exits **2**, distinct from `claude`'s own non-zero codes, so
`run-batch.sh` forwarding it is unambiguous.

`FEATURE_SLUG_OUT` is read with `${...:-}` because `run_all` executes under `set -u` and
the variable is unset in the ordinary case — a bare `$FEATURE_SLUG_OUT` would abort the
run. Nothing else in the library reads it, and a direct `run-plans.sh` invocation leaves
it unset and writes nothing.

## `agentTooling/run-plans.sh`

Replace line 16 (`PLAN_DIR="$REPO_DIR/plans/auto"`) with:

```bash
FEATURES_DIR="$REPO_DIR/plans/features"
QUEUE="auto"
```

Replace the final line (`run_all`) with:

```bash
run_all "$@"
```

In the header comment, replace `executes the file-edit-only plans in plans/auto/`
with `executes the file-edit-only plans in plans/features/<slug>/auto/`, and add a
sentence: the feature slug may be given as the first argument, and is otherwise
inferred from whichever feature has plans queued.

## `agentTooling/run-verify.sh`

Replace line 19 (`PLAN_DIR="$REPO_DIR/plans/verify"`) with:

```bash
FEATURES_DIR="$REPO_DIR/plans/features"
QUEUE="verify"
```

Replace the final line (`run_all`) with:

```bash
run_all "$@"
```

Same header-comment update as above, with `plans/features/<slug>/verify/`.

## `agentTooling/run-batch.sh`

The slug is forwarded to both passes, and — when it was inferred rather than given — the
build pass's choice is captured and handed to the verify pass explicitly, so the two
cannot disagree.

Add after the `GATE_SCRIPT` assignment (line 27):

```bash
# When no slug is given, both passes would infer independently, and they read different
# queues: the build pass looks at auto/incomplete, the verify pass at verify/incomplete.
# A feature with a leftover queued verify plan would then capture the verify pass and get
# a verify run — and a usage record — belonging to the feature just built. Capture what
# the build pass resolved and pass it on.
FEATURE_SLUG_FILE="$(mktemp)"
trap 'rm -f "$FEATURE_SLUG_FILE"' EXIT
export FEATURE_SLUG_OUT="$FEATURE_SLUG_FILE"
```

Replace line 30 (`"$SCRIPT_DIR/run-plans.sh"`) with:

```bash
"$SCRIPT_DIR/run-plans.sh" "$@"
```

Replace line 53 (`"$SCRIPT_DIR/run-verify.sh"`) with:

```bash
batch_feature="${1:-}"
if [[ -z "$batch_feature" && -s "$FEATURE_SLUG_FILE" ]]; then
  batch_feature="$(cat "$FEATURE_SLUG_FILE")"
  echo "########## BATCH: verifying '$batch_feature' (inferred by the build pass) ##########"
fi
unset FEATURE_SLUG_OUT
"$SCRIPT_DIR/run-verify.sh" "$batch_feature"
```

`unset FEATURE_SLUG_OUT` before the verify pass so it does not overwrite the file it is
about to be told about — harmless in practice, but the export is only meant for the pass
that infers.

The file stays empty when the build pass found nothing queued (it returns before the
write), which is why the test is `-s` and not `-f`. In that case `batch_feature` stays
empty and the verify pass infers on its own — the correct fallback, since a verify-only
re-run of a finished batch is a legitimate thing to want.

Passing `"$batch_feature"` unquoted-empty is fine: `resolve_feature` treats an empty
first argument exactly as no argument (`"${1:-}"`), which is the same path a direct
`run-verify.sh` invocation takes.

Add to the header comment: the optional feature slug is forwarded to both passes, and is
otherwise inferred once by the build pass and reused by the verify pass.

## `agentTooling/RUNNER.md`

Read it, then update it to describe the new layout. Specifically:

- The three `### Build plans (plans/auto/)` / `### Verify plans (plans/verify/)` /
  `### Interactive plans (plans/interactive/)` headings become
  `plans/features/<slug>/auto/`, `.../verify/`, `.../interactive/`.
- `## Layout and state` — the four state folders are unchanged in meaning, but they now
  sit under a feature. Say what a feature directory holds: the manifest (`README.md`),
  the four state folders per queue, and the JSON artifacts the analysis tooling writes.
- Add a short `## Choosing a feature` subsection covering the resolution rules above:
  explicit slug wins; otherwise inferred from queued work; zero is a no-op; **two or
  more is an error** — and say why it errors rather than picks, in one line.
- Say plainly that **there is no archiving step any more**. The feature directory is the
  archive; a completed feature's `complete/` folder is its permanent record, and the
  branch-named subfolders that predate this are migrated once by
  `agentTooling/migrate-plans-layout.sh` (plan 50).

Do not document the migration script's flags here — that is plan 50's README work.
