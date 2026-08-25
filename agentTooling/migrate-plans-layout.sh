#!/usr/bin/env bash
set -euo pipefail

# migrate-plans-layout.sh — one-time, repo-agnostic migration from the flat
# plans/{auto,verify}/{state}/ queue to the per-feature
# plans/features/<slug>/{auto,verify}/{state}/ layout that the plan runner reads
# (see agentTooling/RUNNER.md). Safe to re-run: every step is idempotent, and
# --dry-run is the default-safe path to reach for first — it prints every move
# this script would make and changes nothing on disk.
#
# Rule 1 below turns each archived batch directory's name into a feature slug.
# Those slugs are a starting point, not a final answer — renaming a slug to
# something better, or splitting one archive across more than one feature, is a
# human step done afterward, not this script's job.
#
# This file is written by a plan executor with no Bash tool, so it cannot set
# its own executable bit. Plan 51 (interactive, has Bash) must run
# `chmod +x agentTooling/migrate-plans-layout.sh` before running it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PLANS_DIR="$REPO_DIR/plans"
FEATURES_DIR="$PLANS_DIR/features"
QUEUES=(auto verify)
STATES=(incomplete inprogress complete failed)

DRY_RUN=0
LOOSE_SLUG=""
MOVE_COUNT=0

usage() {
  cat <<'EOF'
Usage: migrate-plans-layout.sh [--dry-run] [--loose-slug SLUG] [--help]

  --dry-run           Print every move this script would make; change nothing.
  --loose-slug SLUG   Feature slug to migrate loose (unarchived) plan files into.
  --help              Print this usage and exit.

Run with --dry-run first to preview the moves before committing to them.
EOF
}

while (( "$#" )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --loose-slug)
      LOOSE_SLUG="${2:?"--loose-slug needs a value"}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if (( DRY_RUN == 1 )); then
  echo "DRY RUN — printing planned moves, changing nothing."
fi

if [[ ! -d "$FEATURES_DIR" ]]; then
  echo "ERROR: $FEATURES_DIR does not exist. Run plan 48/49's sync-plans.sh first" >&2
  echo "       to create the plans/features/ layout before migrating into it." >&2
  exit 1
fi

if (( DRY_RUN == 0 )); then
  if ! git diff-index --quiet HEAD --; then
    echo "ERROR: working tree has uncommitted changes. This script uses 'git mv' so" >&2
    echo "       history follows the moved files; commit or stash first, or re-run" >&2
    echo "       with --dry-run to preview without that requirement." >&2
    exit 1
  fi
fi

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

ensure_skeleton() {
  local slug="$1"
  mkdir -p "$FEATURES_DIR/$slug"/{auto,verify}/{incomplete,inprogress,complete,failed} "$FEATURES_DIR/$slug/interactive"
}

shopt -s nullglob

# Rule 1 — archives: plans/<queue>/complete/<slug>/ directories, one per feature
# batch already run. The slug here is just the archive directory's name
# (browseImages, pr1-implementation, ...) — picking a better name, or splitting one
# archive across more than one feature, is a human step afterward, not this rule's
# job. These archives are flat: files sit directly inside, not in subdirectories.
for queue in "${QUEUES[@]}"; do
  for dir in "$PLANS_DIR/$queue/complete"/*/; do
    dir="${dir%/}"
    slug="$(basename "$dir")"
    ensure_skeleton "$slug"
    target="$FEATURES_DIR/$slug/$queue/complete"
    for from in "$dir"/*; do
      [[ -f "$from" ]] || continue
      base="$(basename "$from")"
      if [[ "$base" == "README.md" && -f "$target/README.md" ]]; then
        echo "  skip    $from (README.md already exists at destination)"
        continue
      fi
      move_one "$from" "$target/$base"
    done
    rmdir "$dir" 2>/dev/null || true
  done
done

# Rule 2 — loose files: anything sitting directly as a file (not inside a
# subdirectory) in plans/<queue>/<state>/. Runs after Rule 1, so anything Rule 1
# already archived is gone from complete/ and won't double-count.
LOOSE_FOUND=()
for queue in "${QUEUES[@]}"; do
  for state in "${STATES[@]}"; do
    for from in "$PLANS_DIR/$queue/$state"/*; do
      [[ -f "$from" ]] || continue
      LOOSE_FOUND+=("$from")
    done
  done
done

if (( ${#LOOSE_FOUND[@]} > 0 )); then
  if [[ -z "$LOOSE_SLUG" ]]; then
    echo "Loose plan files found — pass --loose-slug to migrate them:"
    for from in "${LOOSE_FOUND[@]}"; do
      echo "  loose   $from"
    done
    exit 1
  fi

  # --loose-slug is one value for the whole run, so if loose files currently span
  # more than one intended feature (this repo's plans/auto/incomplete/ loose files
  # and its plans/auto/complete/ loose files are, at time of writing, two different
  # features), migrating them correctly takes more than one invocation — run once
  # per group, moving the other group's files aside first if a single run's glob
  # would otherwise catch both. That reconciliation is plan 51's job, not this
  # script's.
  ensure_skeleton "$LOOSE_SLUG"
  for from in "${LOOSE_FOUND[@]}"; do
    rel="${from#"$PLANS_DIR"/}"
    queue="${rel%%/*}"
    rest="${rel#*/}"
    state="${rest%%/*}"
    move_one "$from" "$FEATURES_DIR/$LOOSE_SLUG/$queue/$state/$(basename "$from")"
  done
fi

if (( MOVE_COUNT == 0 )); then
  echo "Nothing to migrate."
else
  echo "$MOVE_COUNT file(s) moved."
fi

exit 0
