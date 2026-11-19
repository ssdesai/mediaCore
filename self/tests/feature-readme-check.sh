#!/usr/bin/env bash
set -uo pipefail

# Self-test for `manifest.py check-prose`, the check feature-close.sh refuses on
# (self/features/lifecycle-loose-ends, item 2). Run by self/gate.sh, or by hand:
# bash self/tests/feature-readme-check.sh
#
# A feature README that still matches templates/plans/features/TEMPLATE.md is a feature
# nobody described; vinylCatalogue's import-experiment-fixtures merged that way. Against a
# throwaway copy of analysis/ and the real template (the real corpus is never written):
#   P1. a README `init` just wrote is refused, each unfilled section named;
#   P2. a filled one passes — its Levels and Contracts sections deleted, as the template
#       says to;
#   P3. a `--method hand` propagation pull's README (a goal paragraph, one review row, no
#       exclusions) passes — the shape LIFECYCLE.md's "Propagate" step 3 asks for;
#   P4. each placeholder on its own is refused: the title, the opening paragraph, a plan
#       row, the exclusions bullet, a section left as the template wrote it;
#   P5. prose that merely mentions `<name>` is not refused for it;
#   P6. a slug with no README is refused (exit 1), and the check writes nothing.
# feature-close.sh's refusal itself is feature-lifecycle.sh's phase RP. No model, no network.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/feature.readme.check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

AT="$TMP/at"
mkdir -p "$AT/analysis" "$AT/templates/plans/features"
mkdir -p "$AT/hooks" && cp "$HERE/hooks/shared_rules.py" "$AT/hooks/"  # roots.py imports it
cp "$HERE"/analysis/*.py "$HERE"/analysis/*.json "$AT/analysis/"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
cp "$HERE/templates/plans/features/TEMPLATE.md" "$AT/templates/plans/features/TEMPLATE.md"
FEATURES="$AT/self/features"
MANIFEST_CMD=(python3 -B "$AT/analysis/manifest.py" --self)
TAIL_FROM='/^## Machine-readable/,$p'

init_feature() {  # $1 slug — a README exactly as feature-start.sh writes it
  "${MANIFEST_CMD[@]}" "$1" init --method hand --branch "$1" --base main \
    --from 2026-01-01T00:00:00.000Z --plan 01-review-opus >/dev/null
}
write_prose() {  # $1 slug, prose on stdin — replaces everything above the fence
  { cat; sed -n "$TAIL_FROM" "$FEATURES/$1/README.md"; } > "$TMP/next-readme"
  cp "$TMP/next-readme" "$FEATURES/$1/README.md"
}
prose_check() { "${MANIFEST_CMD[@]}" "$1" check-prose 2>&1; }

echo "feature-readme-check"

# ── P1. Straight from the start ───────────────────────────────────────────────
init_feature blank
out="$(prose_check blank)"; rc=$?
check "P1a. a README as init wrote it is refused (got $rc)" '[[ $rc -eq 1 ]]'
for section in "title and opening paragraph" "section 'Plans'" "section 'Levels'" \
               "section 'Contracts across levels'" "section 'Deliberately excluded'"; do
  check "P1b. ... naming $section" 'grep -qF -- "$section" <<<"$out"'
done

# ── P2. A filled README ───────────────────────────────────────────────────────
init_feature filled
write_prose filled <<'PROSE'
# Filled feature

What it delivers, and why the work exists.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | the review of the direct build |

## Deliberately excluded

- Branch deletion permissions: the owner's, in GitHub settings.

PROSE
out="$(prose_check filled)"; rc=$?
check "P2. a filled README passes, its level sections deleted (got $rc: $out)" '[[ $rc -eq 0 && -z "$out" ]]'

# ── P3. A hand pull's README ──────────────────────────────────────────────────
init_feature pull-agenttooling-pr118
write_prose pull-agenttooling-pr118 <<'PROSE'
# Propagate agentTooling PR 118

Pulls agentTooling PR 118 (`harness-driver-measures`, split `e4e08b9`) into this repo with
`update.sh`; the prefix diff is the upstream range and nothing else.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | reviews the pull |

PROSE
out="$(prose_check pull-agenttooling-pr118)"; rc=$?
check "P3. a hand pull's README passes (got $rc: $out)" '[[ $rc -eq 0 && -z "$out" ]]'

# ── P4. Each placeholder alone ────────────────────────────────────────────────
FILLED_PROSE_HEAD='# Real title

A real paragraph.

## Plans

| Plan | What it does |
|---|---|
'
case_check() {  # $1 label, $2 slug, $3 prose, $4 text the output must name
  init_feature "$2"
  printf '%s\n' "$3" | write_prose "$2"
  out="$(prose_check "$2")"; rc=$?
  named="$4"
  check "P4. $1 is refused, naming $named (got $rc)" '[[ $rc -eq 1 ]] && grep -qF -- "$named" <<<"$out"'
}
case_check "a template title" p4-title \
  "# <Feature title>

A real paragraph.

## Plans

| Plan | What it does |
|---|---|
| \`review/incomplete/01-review-opus.md\` | reviews |
" "title and opening paragraph"
case_check "a template paragraph" p4-para \
  "# Real title

<One paragraph: what this feature delivers and why the work exists. No plan-level
detail — that's what the table below is for.>

## Plans

| Plan | What it does |
|---|---|
| \`review/incomplete/01-review-opus.md\` | reviews |
" "title and opening paragraph"
case_check "a plan row still saying <one line>" p4-row \
  "${FILLED_PROSE_HEAD}| \`review/incomplete/01-review-opus.md\` | <one line>
" "section 'Plans'"
case_check "the exclusions bullet left as written" p4-excl \
  "${FILLED_PROSE_HEAD}| \`review/incomplete/01-review-opus.md\` | reviews

## Deliberately excluded

- <Something that looked in-scope but isn't — and why.>
" "section 'Deliberately excluded'"
case_check "a Levels section left in" p4-levels \
  "${FILLED_PROSE_HEAD}| \`review/incomplete/01-review-opus.md\` | reviews

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| <1> | <NN-NN> | \`NN-gate.md\` | \`NN-level-*-MODEL.md\` or — | <gate sections> |

Delete this section when the batch has a single level.
" "section 'Levels'"

# ── P5. A mention of <name> is prose, not a placeholder ───────────────────────
init_feature p5-mention
write_prose p5-mention <<'PROSE'
# Mentions

Reads `<name>` from the fence, as the old `<name>.json` fixtures did.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | reviews |

PROSE
out="$(prose_check p5-mention)"; rc=$?
check "P5. prose mentioning <name> passes (got $rc: $out)" '[[ $rc -eq 0 ]]'

# ── P6. No README ─────────────────────────────────────────────────────────────
before="$(find "$FEATURES" -type f | sort | tr '\n' ' ')"
out="$(prose_check no-such-feature)"; rc=$?
check "P6a. a slug with no README is refused (got $rc)" '[[ $rc -eq 1 ]]'
check "P6b. ... and nothing was written" '[[ "$(find "$FEATURES" -type f | sort | tr "\n" " ")" == "$before" ]]'

echo
if [[ $fails -eq 0 ]]; then
  echo "feature-readme-check: all checks passed"
  exit 0
fi
echo "feature-readme-check: $fails check(s) failed"
exit 1
