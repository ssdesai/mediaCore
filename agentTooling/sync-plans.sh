#!/usr/bin/env bash
set -euo pipefail

# Refreshes the generated stubs — the READMEs, the feature template and .gitignore — in
# the consuming repo's plans/ tree from templates/plans/. Run after `git subtree pull`,
# and after install in place of copying the template by hand.
#
# The stubs are pointers into this directory ("see agentTooling/RUNNER.md"), so any
# change here that moves the target — a renamed subtree prefix, a restructured queue,
# a doc that gets split — silently staleness every copy already sitting in a repo.
# Copying once solves nothing; syncing keeps one source of truth.
#
# Overwriting the generated stubs is safe because they carry no repo-specific content;
# the four files that do — PROJECT_FACTS.md, gate.sh, pr.sh and worktree-setup.sh — are
# seeded from the skeleton on first run and never overwritten again. `--check` reports
# on both halves without writing anything: STALE or missing generated stubs, and
# repo-owned scripts whose template-version line trails the template's, plus an
# unfilled PROJECT_FACTS.md. The write path below is unchanged and ends with that same
# repo-owned report, since the stubs it just wrote are always in sync.
#
# Scope: this writes into the CONSUMING repo's plans/ only. agentTooling's own corpus
# under self/ is hand-written and is never generated from templates/ — every stub here
# points back up at ../agentTooling/…, which is wrong from inside agentTooling, and this
# directory is the source those stubs point at rather than a copy of it. There is no
# --self flag; there would be nothing to generate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates/plans"
PLANS_DIR="$REPO_DIR/plans"
USAGE_RC=2
STATUS_COL_WIDTH=11

# The stubs that are regenerated every run. PROJECT_FACTS.md is deliberately absent.
#
# .gitignore is generated for the same reason the READMEs are: it holds no repo-specific
# content, and the install step it replaces was hand-maintained with nothing to detect a
# missed one — a repo that skipped it committed a per-level gate report every batch. Its
# patterns are relative to plans/, so a root-level `plans/**/…` pattern from an earlier
# install is redundant rather than wrong.
GENERATED=(README.md interactive/README.md features/README.md features/TEMPLATE.md .gitignore)

# The repo-owned scripts: seeded once from the skeleton, then never overwritten again.
# Checked by template-version rather than by content, since a repo customizes
# everything below each script's REPO-SPECIFIC marker.
REPO_OWNED_SCRIPTS=(gate.sh pr.sh worktree-setup.sh)

usage() {
  echo "usage: sync-plans.sh [--check]" >&2
  exit "$USAGE_RC"
}

# template_version <file> — the integer after "# template-version:" in its header, or 0
# when the line is absent (an unversioned copy predating this contract).
template_version() {
  local v
  v="$(sed -n 's/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n 1)"
  echo "${v:-0}"
}

# The one-time hint printed when a repo-owned script is freshly seeded.
repo_owned_created_hint() {
  case "$1" in
    gate.sh) echo "fill in the REPO-SPECIFIC sections before relying on it" ;;
    pr.sh) echo "check its forge CLI before relying on it; it bases the PR on whatever branch is checked out" ;;
    worktree-setup.sh) echo "fill in this repo's per-worktree setup (venv, npm install, dev port)" ;;
  esac
}

# check_stubs — one in-sync/STALE/missing line per $GENERATED entry, in order. Returns
# the count of items that need attention.
check_stubs() {
  local rel count=0
  for rel in "${GENERATED[@]}"; do
    if [[ ! -f "$PLANS_DIR/$rel" ]]; then
      printf "  %-${STATUS_COL_WIDTH}s%s\n" "missing" "plans/$rel (run sync-plans.sh)"
      count=$((count + 1))
    elif cmp -s "$TEMPLATE_DIR/$rel" "$PLANS_DIR/$rel"; then
      printf "  %-${STATUS_COL_WIDTH}s%s\n" "in-sync" "plans/$rel"
    else
      printf "  %-${STATUS_COL_WIDTH}s%s\n" "STALE" "plans/$rel (differs from templates/plans/$rel; run sync-plans.sh)"
      count=$((count + 1))
    fi
  done
  return "$count"
}

# check_repo_owned — the three scripts by template-version, then PROJECT_FACTS.md by
# content. Returns the count of items that need attention.
check_repo_owned() {
  local f tver cver count=0
  for f in "${REPO_OWNED_SCRIPTS[@]}"; do
    if [[ ! -f "$PLANS_DIR/$f" ]]; then
      printf "  %-${STATUS_COL_WIDTH}s%s\n" "missing" "plans/$f (never seeded; run sync-plans.sh)"
      count=$((count + 1))
    else
      tver="$(template_version "$TEMPLATE_DIR/$f")"
      cver="$(template_version "$PLANS_DIR/$f")"
      if [[ "$cver" == "$tver" ]]; then
        printf "  %-${STATUS_COL_WIDTH}s%s\n" "in-sync" "plans/$f (template-version $tver)"
      else
        printf "  %-${STATUS_COL_WIDTH}s%s\n" "DRIFT" "plans/$f (template-version $cver < $tver; hand-merge, see agentTooling/README.md -> Updating)"
        count=$((count + 1))
      fi
    fi
  done

  if [[ ! -f "$PLANS_DIR/PROJECT_FACTS.md" ]]; then
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "missing" "plans/PROJECT_FACTS.md (never seeded; run sync-plans.sh)"
    count=$((count + 1))
  elif cmp -s "$TEMPLATE_DIR/PROJECT_FACTS.md" "$PLANS_DIR/PROJECT_FACTS.md"; then
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "unfilled" "plans/PROJECT_FACTS.md (still the skeleton; fill it before authoring plans)"
    count=$((count + 1))
  else
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "in-sync" "plans/PROJECT_FACTS.md"
  fi
  return "$count"
}

# finish <count> — the last line and exit code, shared by --check and the write path.
finish() {
  local count="$1"
  if (( count == 0 )); then
    echo "plans/ is in sync with agentTooling/templates/."
    exit 0
  fi
  echo "plans/ needs attention: $count item(s) above."
  exit 1
}

MODE="write"
if [[ $# -gt 0 ]]; then
  [[ "$1" == "--check" ]] || usage
  MODE="check"
  shift
fi
[[ $# -eq 0 ]] || usage

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: no templates found at $TEMPLATE_DIR" >&2
  exit 1
fi

if [[ "$MODE" == "check" ]]; then
  count=0
  rc=0; check_stubs || rc=$?; count=$((count + rc))
  rc=0; check_repo_owned || rc=$?; count=$((count + rc))
  finish "$count"
fi

mkdir -p "$PLANS_DIR/interactive" "$PLANS_DIR/features"

for rel in "${GENERATED[@]}"; do
  if [[ -f "$PLANS_DIR/$rel" ]] && cmp -s "$TEMPLATE_DIR/$rel" "$PLANS_DIR/$rel"; then
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "unchanged" "plans/$rel"
  else
    cp "$TEMPLATE_DIR/$rel" "$PLANS_DIR/$rel"
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "synced" "plans/$rel"
  fi
done

if [[ -f "$PLANS_DIR/PROJECT_FACTS.md" ]]; then
  printf "  %-${STATUS_COL_WIDTH}s%s\n" "kept" "plans/PROJECT_FACTS.md (repo-owned — never overwritten)"
else
  cp "$TEMPLATE_DIR/PROJECT_FACTS.md" "$PLANS_DIR/PROJECT_FACTS.md"
  printf "  %-${STATUS_COL_WIDTH}s%s\n" "created" "plans/PROJECT_FACTS.md — fill in the prompts before authoring plans"
fi

for f in "${REPO_OWNED_SCRIPTS[@]}"; do
  if [[ -f "$PLANS_DIR/$f" ]]; then
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "kept" "plans/$f (repo-owned — never overwritten)"
  else
    cp "$TEMPLATE_DIR/$f" "$PLANS_DIR/$f"
    chmod +x "$PLANS_DIR/$f"
    printf "  %-${STATUS_COL_WIDTH}s%s\n" "created" "plans/$f — $(repo_owned_created_hint "$f")"
  fi
done

count=0
rc=0; check_repo_owned || rc=$?; count=$((count + rc))
finish "$count"
