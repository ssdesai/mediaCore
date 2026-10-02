#!/usr/bin/env bash
set -uo pipefail

# Lint one feature's manifest fence and plan files before a paid run:
# check-plans.sh [--self] <slug> (self/features/sweep-and-check/README.md).
#
# run-batch.sh runs this immediately after stamp_timing batch_start and stops
# before the build pass on any FAIL — a malformed corpus (a plan without a model
# suffix, a stem missing from plans[], a review stub still carrying @@TODO@@) is
# otherwise found late: by a runner mid-batch, or by a cost report that omits a
# plan.
#
# Two filenames are the harness's own rather than a plan author's and are exempt
# accordingly: the level sentinel NN-gate.md (auto/ only, exempt from checks 11 and 13)
# and the tier-2 escalation NN-escalation-MODEL.md (verify/ only, synthesized mid-batch
# by run-escalation-plan.sh so no manifest can list it — exempt from check 11 alone).
#
# Check 7 covers the whole of a `session_window`: both bounds carry a zone, and `to` is
# either null — the feature is in flight — or an instant strictly after `from`. An empty
# window is not refused anywhere downstream; it simply owns no session, and the feature
# reports $0.00.
#
# Prints one line per check, fourteen in order:
#   ok    <label>
#   FAIL  <label>: <detail>
# then one last line: "check-plans: <N> checks, <M> failed"
#
# Exit codes: 2 usage (no slug, an unknown flag, or an extra argument);
# 0 every check passed; 1 at least one FAILed.

USAGE_RC=2
FAIL_RC=1
MODEL_RE='haiku|sonnet|opus'
PLAN_FILENAME_RE="^[0-9]+-[a-z0-9-]+-(${MODEL_RE})\\.md\$"
GATE_FILENAME_RE='^[0-9]+-gate\.md$'
# run-escalation-plan.sh / write_escalation_plan (plan-runner-lib.sh) synthesize
# verify/incomplete/NN-escalation-MODEL.md at runtime when a level's gate stays red
# after tier 1, so the file cannot be in a `plans[]` array authored before the batch
# ran — analysis/report.py's ESCALATION_STEM rolls the same names in for the same
# reason. Recognised under verify/ only, the way NN-gate.md is recognised under auto/.
ESCALATION_FILENAME_RE="^[0-9]+-escalation-(${MODEL_RE})\\.md\$"
ZONE_RE='(Z|[+-][0-9]{2}:[0-9]{2})$'
# Check 7's label. One check over both `session_window` bounds — each carries a zone, and
# `to` is null (in flight) or strictly after `from`. Two checks would have printed two
# lines about one fence; the detail says which half failed.
WINDOW_LABEL="window bounds carry a zone and to follows from"
TODO_MARKER="@@TODO@@"
QUEUES=(auto verify review)
STATES=(incomplete inprogress complete failed)
KNOWN_METHODS=(plans direct hand)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/plan-runner-roots.sh"
resolve_roots "${1:-}"
if [[ "${1:-}" == "--self" ]]; then shift; fi

usage() {
  echo "usage: check-plans.sh [--self] <slug>" >&2
  exit "$USAGE_RC"
}

SLUG="${1:-}"
case "$SLUG" in
  ""|--*) usage ;;
esac
shift
(( $# == 0 )) || usage

checks=0
failed=0
pass()  { echo "  ok    $1"; checks=$((checks + 1)); }
failc() { echo "  FAIL  $1: $2"; checks=$((checks + 1)); failed=$((failed + 1)); }

D="$FEATURES_DIR/$SLUG"
MANIFEST="$D/README.md"

# 1. feature directory exists
if [[ -d "$D" ]]; then
  pass "feature directory exists"
else
  failc "feature directory exists" "$D is not a directory"
fi

# 2. manifest present
if [[ -f "$MANIFEST" ]]; then
  pass "manifest present"
else
  failc "manifest present" "$MANIFEST does not exist"
fi

# 3. fence parses
FENCE_SLUG="$(manifest_field "$MANIFEST" slug)"
if [[ -n "$FENCE_SLUG" ]]; then
  pass "fence parses"
else
  failc "fence parses" "manifest_field $MANIFEST slug printed nothing"
fi

# 4. fence slug matches directory
if [[ "$FENCE_SLUG" == "$SLUG" ]]; then
  pass "fence slug matches directory"
else
  failc "fence slug matches directory" "fence slug '$FENCE_SLUG' != directory '$SLUG'"
fi

# 5. method known
METHOD="$(manifest_field "$MANIFEST" method)"
if [[ -z "$METHOD" ]]; then
  pass "method known"
else
  method_known=0
  for m in "${KNOWN_METHODS[@]}"; do
    if [[ "$METHOD" == "$m" ]]; then method_known=1; break; fi
  done
  if (( method_known )); then
    pass "method known"
  else
    failc "method known" "method '$METHOD' is not one of plans|direct|hand"
  fi
fi

# 6. branches non-empty
BRANCHES_JSON="$(manifest_field "$MANIFEST" branches)"
BRANCHES_LEN=0
if [[ -n "$BRANCHES_JSON" ]]; then
  BRANCHES_LEN="$(jq -r 'length' <<<"$BRANCHES_JSON" 2>/dev/null)"
  [[ -n "$BRANCHES_LEN" ]] || BRANCHES_LEN=0
fi
if (( BRANCHES_LEN >= 1 )); then
  pass "branches non-empty"
else
  failc "branches non-empty" "branches is empty or absent"
fi

# 7. window bounds carry a zone, and `to` is null or strictly after `from`
#
# Both halves are about a bound that cannot describe itself. A zone-less one is read as
# UTC and is silently off by the author's offset (analysis/README.md → "Every instant is
# UTC"); a `to` at or before `from` is an EMPTY window, which
# `capture_planning.is_empty_window` drops from every share split, so the feature owns
# nothing and reports $0.00 with no refusal anywhere — `recovered-totals-stay-honest`
# carries exactly that, `to` 13 minutes before `from`
# (self/DESIGN-2026-09-16-lifecycle-restructure.md §1). A null `to` is "still in flight"
# and is the right value until the feature's first capture, so it is never out of order.
WINDOW_JSON="$(manifest_field "$MANIFEST" session_window)"
window_detail=""
# add_window_detail <text> — one check, one line: several findings over the same fence
# are joined rather than printed apart.
add_window_detail() {
  if [[ -n "$window_detail" ]]; then window_detail="$window_detail; $1"; else window_detail="$1"; fi
}
# window_order <from> <to> — "ok", "empty" (to at or before from) or "unparsed".
# Compared as INSTANTS, never as text: `2026-09-04T14:00:00-04:00` sorts before
# `2026-09-04T17:00:00Z` as a string and is an hour after it as a moment, which is the
# case a string comparison gets backwards. A bound with no zone is read as UTC, exactly
# as the capture reads it — the zone half above is what reports that separately.
window_order() {
  python3 -B -c 'import sys
from datetime import datetime, timezone

def moment(value):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)

start, end = moment(sys.argv[1]), moment(sys.argv[2])
if start is None or end is None:
    print("unparsed")
else:
    print("ok" if end > start else "empty")' "$1" "$2" 2>/dev/null
}
if [[ -n "$WINDOW_JSON" ]]; then
  FROM_VAL="$(jq -r '.from // empty' <<<"$WINDOW_JSON" 2>/dev/null)"
  TO_VAL="$(jq -r '.to // empty' <<<"$WINDOW_JSON" 2>/dev/null)"
  if [[ -n "$FROM_VAL" ]] && ! [[ "$FROM_VAL" =~ $ZONE_RE ]]; then
    add_window_detail "from '$FROM_VAL' carries no zone"
  fi
  if [[ -n "$TO_VAL" ]] && ! [[ "$TO_VAL" =~ $ZONE_RE ]]; then
    add_window_detail "to '$TO_VAL' carries no zone"
  fi
  if [[ -n "$FROM_VAL" && -n "$TO_VAL" ]]; then
    case "$(window_order "$FROM_VAL" "$TO_VAL")" in
      empty)
        add_window_detail "to '$TO_VAL' is at or before from '$FROM_VAL' — an empty window owns nothing" ;;
      ok) ;;
      *)
        add_window_detail "from '$FROM_VAL' and to '$TO_VAL' do not both parse as instants" ;;
    esac
  fi
fi
if [[ -z "$window_detail" ]]; then
  pass "$WINDOW_LABEL"
else
  failc "$WINDOW_LABEL" "$window_detail"
fi

# 8–13 share one pass over every plan file under D/{auto,verify,review}/{incomplete,
# inprogress,complete,failed}/, collecting parallel arrays so 9, 11 and 13 need no
# second walk. A queue or state directory that does not exist is simply empty.
PLAN_RELS=()
PLAN_STEMS=()
PLAN_STATES=()
PLAN_SENTINEL=()
# Exempt from check 11 only — a runtime-synthesized escalation is a real plan file that
# no manifest can list. Kept separate from PLAN_SENTINEL, which also exempts check 13.
PLAN_SYNTHESIZED=()
BAD_FILENAMES=()

for q in "${QUEUES[@]}"; do
  for s in "${STATES[@]}"; do
    dir="$D/$q/$s"
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.md; do
      [[ -e "$f" ]] || continue
      [[ "$f" == *.progress.md ]] && continue
      base="$(basename "$f")"
      rel="$q/$s/$base"
      stem="${base%.md}"
      well_formed=0
      is_sentinel=0
      is_synthesized=0
      # Tested before PLAN_FILENAME_RE, which would otherwise match an escalation name
      # anywhere: an NN-escalation-MODEL.md outside verify/ is not the harness's file and
      # is reported by check 8, exactly as an NN-gate.md outside auto/ is.
      if [[ "$base" =~ $ESCALATION_FILENAME_RE ]]; then
        if [[ "$q" == "verify" ]]; then
          well_formed=1
          is_synthesized=1
        fi
      elif [[ "$base" =~ $PLAN_FILENAME_RE ]]; then
        well_formed=1
      elif [[ "$q" == "auto" && "$base" =~ $GATE_FILENAME_RE ]]; then
        well_formed=1
        is_sentinel=1
      fi
      PLAN_RELS+=("$rel")
      PLAN_STEMS+=("$stem")
      PLAN_STATES+=("$s")
      PLAN_SENTINEL+=("$is_sentinel")
      PLAN_SYNTHESIZED+=("$is_synthesized")
      if (( ! well_formed )); then BAD_FILENAMES+=("$rel"); fi
    done
  done
done

# 8. plan filenames well-formed
if (( ${#BAD_FILENAMES[@]} == 0 )); then
  pass "plan filenames well-formed"
else
  detail=""
  for f in "${BAD_FILENAMES[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $f"; else detail="$f"; fi
  done
  failc "plan filenames well-formed" "$detail"
fi

# 9. plan numbers padded alike
DIGIT_LENS=()
for stem in ${PLAN_STEMS[@]+"${PLAN_STEMS[@]}"}; do
  if [[ "$stem" =~ ^([0-9]+) ]]; then
    len=${#BASH_REMATCH[1]}
    seen=0
    for l in ${DIGIT_LENS[@]+"${DIGIT_LENS[@]}"}; do
      if [[ "$l" == "$len" ]]; then seen=1; break; fi
    done
    if (( ! seen )); then DIGIT_LENS+=("$len"); fi
  fi
done
if (( ${#DIGIT_LENS[@]} <= 1 )); then
  pass "plan numbers padded alike"
else
  detail=""
  for l in "${DIGIT_LENS[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $l"; else detail="$l"; fi
  done
  failc "plan numbers padded alike" "leading digit-run lengths found: $detail"
fi

# 10. no @@TODO@@ stubs queued
TODO_OFFENDERS=()
for q in "${QUEUES[@]}"; do
  dir="$D/$q/incomplete"
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*.md; do
    [[ -e "$f" ]] || continue
    [[ "$f" == *.progress.md ]] && continue
    # Exactly plan-runner-lib.sh's rule (`grep -q '^@@TODO@@'`), and it has to be: this
    # check exists to predict that refusal before the batch bills for it. The stub
    # feature-start.sh writes carries the marker on line 3, under a title and a blank
    # line, so anything narrower than the whole file passes the one corpus it was
    # written for.
    if grep -q "^$TODO_MARKER" "$f" 2>/dev/null; then
      TODO_OFFENDERS+=("$q/incomplete/$(basename "$f")")
    fi
  done
done
if (( ${#TODO_OFFENDERS[@]} == 0 )); then
  pass "no @@TODO@@ stubs queued"
else
  detail=""
  for f in "${TODO_OFFENDERS[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $f"; else detail="$f"; fi
  done
  failc "no @@TODO@@ stubs queued" "$detail"
fi

# 11. every plan file listed in plans[]
PLANS_JSON="$(manifest_field "$MANIFEST" plans)"
MISSING_FROM_PLANS=()
i=0
n=${#PLAN_RELS[@]}
while (( i < n )); do
  if [[ "${PLAN_SENTINEL[$i]}" == "0" && "${PLAN_SYNTHESIZED[$i]}" == "0" ]]; then
    stem="${PLAN_STEMS[$i]}"
    in_plans=0
    if [[ -n "$PLANS_JSON" ]]; then
      in_plans="$(jq -r --arg s "$stem" 'if index($s) != null then "1" else "0" end' <<<"$PLANS_JSON" 2>/dev/null)"
      [[ -n "$in_plans" ]] || in_plans=0
    fi
    if [[ "$in_plans" != "1" ]]; then MISSING_FROM_PLANS+=("$stem"); fi
  fi
  i=$((i + 1))
done
if (( ${#MISSING_FROM_PLANS[@]} == 0 )); then
  pass "every plan file listed in plans[]"
else
  detail=""
  for stem in "${MISSING_FROM_PLANS[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $stem"; else detail="$stem"; fi
  done
  failc "every plan file listed in plans[]" "$detail"
fi

# 12. every plans[] entry has a file
GHOST_STEMS=()
if [[ -n "$PLANS_JSON" ]]; then
  while IFS= read -r stem; do
    [[ -n "$stem" ]] || continue
    found=0
    for s in ${PLAN_STEMS[@]+"${PLAN_STEMS[@]}"}; do
      if [[ "$s" == "$stem" ]]; then found=1; break; fi
    done
    if (( ! found )); then GHOST_STEMS+=("$stem"); fi
  done < <(jq -r '.[]' <<<"$PLANS_JSON" 2>/dev/null)
fi
if (( ${#GHOST_STEMS[@]} == 0 )); then
  pass "every plans[] entry has a file"
else
  detail=""
  for stem in "${GHOST_STEMS[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $stem"; else detail="$stem"; fi
  done
  failc "every plans[] entry has a file" "$detail"
fi

# 13. every queued plan names the feature
NOT_NAMING_FEATURE=()
i=0
while (( i < n )); do
  if [[ "${PLAN_STATES[$i]}" == "incomplete" && "${PLAN_SENTINEL[$i]}" == "0" ]]; then
    f="$D/${PLAN_RELS[$i]}"
    if ! grep -qF -- "$SLUG" "$f" 2>/dev/null; then
      NOT_NAMING_FEATURE+=("${PLAN_RELS[$i]}")
    fi
  fi
  i=$((i + 1))
done
if (( ${#NOT_NAMING_FEATURE[@]} == 0 )); then
  pass "every queued plan names the feature"
else
  detail=""
  for f in "${NOT_NAMING_FEATURE[@]}"; do
    if [[ -n "$detail" ]]; then detail="$detail, $f"; else detail="$f"; fi
  done
  failc "every queued plan names the feature" "$detail"
fi

# 14. plans method has a queue
if [[ "$METHOD" == "direct" || "$METHOD" == "hand" ]]; then
  pass "plans method has a queue"
else
  has_auto=0
  for s in "${STATES[@]}"; do
    dir="$D/auto/$s"
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*.md; do
      [[ -e "$f" ]] || continue
      [[ "$f" == *.progress.md ]] && continue
      has_auto=1
    done
  done
  if (( has_auto )); then
    pass "plans method has a queue"
  else
    failc "plans method has a queue" "method '${METHOD:-plans}' but no plan file exists under $D/auto/"
  fi
fi

echo "check-plans: $checks checks, $failed failed"
if (( failed > 0 )); then exit "$FAIL_RC"; fi
exit 0
