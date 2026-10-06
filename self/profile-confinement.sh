#!/usr/bin/env bash
set -uo pipefail

# The profile confinement check (self/DESIGN-2026-10-05-cloud-execution.md §1):
#
#   self/profile-confinement.sh [<checkout>]       default: the checkout holding this file
#
# **The lifecycle never asks where it is running.** Only the detector (env-profile.sh),
# the adapters and their tests may spell the two profile variables; every other script
# calls the functions env-profile.sh defines. This fails — exit 1, one `FAIL` line per
# offending file with its first matching line — when either name appears in any other
# TRACKED file of <checkout>. self/gate.sh records it as a blocking check;
# self/tests/env-profile.sh runs it against planted repos to show it is not vacuous.
#
# What counts (self/features/execution-profiles/NOTES.md, rulings 6–8):
#   - tracked files only (`git ls-files`): an untracked scratch file never fails a gate;
#   - whole words only (`grep -w`): CLAUDE_CODE_REMOTE_SESSION_ID, which
#     plan-runner-lib.sh scrubs from a runner child's environment, is a different
#     variable and not a hit;
#   - prose is exempt — every `*.md` file. The design, the READMEs and the doctrine name
#     the variables to describe the rule; the rule is about code that READS them.
#
# Exit codes: 0 confined; 1 an offending file; 2 <checkout> is not a git checkout.

CONFINED_NAMES_RE='CLAUDE_CODE_REMOTE|AGENTTOOLING_PROFILE'
PROSE_SUFFIX=".md"
# The detector, the adapters that branch on the profile, and this check itself, relative
# to the checkout root. The two environment adapters of design §7 are adapters by
# definition and listed with them, though both ask env-profile.sh's functions today and
# spell neither variable. The SessionStart hook's guard is cloud-setup.sh's own, so the
# wiring (hooks/wire-settings.py) spells nothing and is not listed
# (self/features/execution-profiles/NOTES.md).
CONFINEMENT_ALLOWED=(
  env-profile.sh
  forge.sh
  self/open-session.sh
  templates/plans/open-session.sh
  templates/plans/environment.sh
  templates/plans/cloud-setup.sh
  self/profile-confinement.sh
)
# The tests, which force the profile to stay independent of the machine they run on.
CONFINEMENT_ALLOWED_PREFIX="self/tests/"
NOT_A_CHECKOUT_RC=2
OFFENDING_RC=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if ! git -C "$CHECKOUT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "  FAIL  $CHECKOUT is not a git checkout"
  exit "$NOT_A_CHECKOUT_RC"
fi

allowed() {
  local path="$1" entry
  case "$path" in
    *"$PROSE_SUFFIX") return 0 ;;
    "$CONFINEMENT_ALLOWED_PREFIX"*) return 0 ;;
  esac
  for entry in "${CONFINEMENT_ALLOWED[@]}"; do
    if [[ "$path" == "$entry" ]]; then return 0; fi
  done
  return 1
}

checked=0
offending=0
while IFS= read -r path; do
  [[ -n "$path" && -f "$CHECKOUT/$path" ]] || continue
  if allowed "$path"; then continue; fi
  checked=$((checked + 1))
  hit="$(grep -nwE "$CONFINED_NAMES_RE" "$CHECKOUT/$path" 2>/dev/null | head -n 1)"
  if [[ -n "$hit" ]]; then
    offending=$((offending + 1))
    echo "  FAIL  $path:$hit — only env-profile.sh, the adapters and their tests may read the profile; call env-profile.sh's functions instead"
  fi
done < <(git -C "$CHECKOUT" ls-files 2>/dev/null)

if (( offending > 0 )); then
  echo "profile-confinement: $offending file(s) read the profile outside the detector and its adapters"
  exit "$OFFENDING_RC"
fi
echo "profile-confinement: $checked tracked file(s) checked, none reads the profile"
exit 0
