#!/usr/bin/env bash
set -euo pipefail

# Refreshes the generated README stubs in the consuming repo's plans/ tree from
# templates/plans/. Run after `git subtree pull` — and after install, in place of
# copying the template by hand.
#
# The stubs are pointers into this directory ("see agentTooling/RUNNER.md"), so any
# change here that moves the target — a renamed subtree prefix, a restructured queue,
# a doc that gets split — silently staleness every copy already sitting in a repo.
# Copying once solves nothing; syncing keeps one source of truth.
#
# Overwriting is safe precisely because the stubs carry no repo-specific content. The
# files in plans/ that do — PROJECT_FACTS.md, gate.sh and pr.sh — are seeded from the
# skeleton on first run and never touched again.
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

# The stubs that are regenerated every run. PROJECT_FACTS.md is deliberately absent.
GENERATED=(README.md interactive/README.md features/README.md features/TEMPLATE.md)

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  echo "ERROR: no templates found at $TEMPLATE_DIR" >&2
  exit 1
fi

mkdir -p "$PLANS_DIR/interactive" "$PLANS_DIR/features"

for rel in "${GENERATED[@]}"; do
  if [[ -f "$PLANS_DIR/$rel" ]] && cmp -s "$TEMPLATE_DIR/$rel" "$PLANS_DIR/$rel"; then
    echo "  unchanged  plans/$rel"
  else
    cp "$TEMPLATE_DIR/$rel" "$PLANS_DIR/$rel"
    echo "  synced     plans/$rel"
  fi
done

if [[ -f "$PLANS_DIR/PROJECT_FACTS.md" ]]; then
  echo "  kept       plans/PROJECT_FACTS.md (repo-owned — never overwritten)"
else
  cp "$TEMPLATE_DIR/PROJECT_FACTS.md" "$PLANS_DIR/PROJECT_FACTS.md"
  echo "  created    plans/PROJECT_FACTS.md — fill in the prompts before authoring plans"
fi

if [[ -f "$PLANS_DIR/gate.sh" ]]; then
  echo "  kept       plans/gate.sh (repo-owned — never overwritten)"
else
  cp "$TEMPLATE_DIR/gate.sh" "$PLANS_DIR/gate.sh"
  chmod +x "$PLANS_DIR/gate.sh"
  echo "  created    plans/gate.sh — fill in the REPO-SPECIFIC sections before relying on it"
fi

if [[ -f "$PLANS_DIR/pr.sh" ]]; then
  echo "  kept       plans/pr.sh (repo-owned — never overwritten)"
else
  cp "$TEMPLATE_DIR/pr.sh" "$PLANS_DIR/pr.sh"
  chmod +x "$PLANS_DIR/pr.sh"
  echo "  created    plans/pr.sh — check its BASE_BRANCH and forge CLI before relying on it"
fi

echo "plans/ stubs are in sync with agentTooling/templates/."
