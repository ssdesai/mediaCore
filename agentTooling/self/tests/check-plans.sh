#!/usr/bin/env bash
set -uo pipefail

# Self-test for check-plans.sh (self/features/sweep-and-check/README.md), the pre-run
# lint over a feature's plan corpus. Run by self/gate.sh, or by hand:
# bash self/tests/check-plans.sh
#
# Builds a throwaway agentTooling checkout under mktemp -d, copies in the real
# check-plans.sh and plan-runner-roots.sh (a missing check-plans.sh is tolerated — RED
# until plan 76 lands, the convention cost-recovery.sh uses), and drives it against
# synthesized feature manifests and plan-directory trees under $TMP/plans/features (the
# ordinary corpus) and $TMP/agentTooling/self/features (the --self one; both roots come
# from plan-runner-roots.sh's resolve_roots, sourced by check-plans.sh from its own
# directory). No model, no network.
#
# Asserts the contract (repeated verbatim in the plan check-plans.sh itself implements):
#   usage: exit 2 on no slug, an unknown flag, or an extra argument;
#   a well-formed feature prints exactly 14 "  ok    <label>" lines, no "  FAIL  " line,
#     and a last line "check-plans: 14 checks, 0 failed";
#   a missing feature directory FAILs check 1 but still ends with a "check-plans: " line;
#   the fourteen checks in order — feature directory exists, manifest present, fence
#     parses, fence slug matches directory, method known, branches non-empty, window
#     bounds carry a zone, plan filenames well-formed, plan numbers padded alike, no
#     @@TODO@@ stubs queued, every plan file listed in plans[], every plans[] entry has a
#     file, every queued plan names the feature, plans method has a queue — each FAILing
#     on the input built to trip it and passing otherwise, with the offending path or stem
#     named in the FAIL detail where the contract specifies one;
#   the two sentinels' exemptions: NN-gate.md is well-formed under auto/ only and exempt
#     from checks 11 and 13; NN-escalation-MODEL.md — synthesized into verify/ at runtime
#     by run-escalation-plan.sh, so no manifest authored before the batch can list it —
#     is well-formed under verify/ only and exempt from check 11 alone;
# and the batch stop: run-batch.sh spends no claude call on a feature whose plan corpus
# fails check 8 (malformed filenames), and does spend one on a well-formed feature.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
AT="$TMP/agentTooling"
mkdir -p "$AT" "$TMP/plans/features"

for f in check-plans.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
chmod +x "$AT/check-plans.sh" 2>/dev/null || true

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# mkfeature <features-root> <slug> <plans-json-array> [<branches-json-array>] [<from>] [<method>]
mkfeature() {
  local root="$1" slug="$2" plans="$3" branches="${4:-}" from="${5:-2026-09-04T00:00:00Z}" method="${6:-}"
  [[ -n "$branches" ]] || branches="[\"$slug\"]"
  mkdir -p "$root/$slug"
  {
    echo "# $slug"
    echo ""
    echo '```json'
    if [[ -n "$method" ]]; then
      printf '{"slug": "%s", "plans": %s, "branches": %s, "session_window": {"from": "%s", "to": null}, "method": "%s"}\n' \
        "$slug" "$plans" "$branches" "$from" "$method"
    else
      printf '{"slug": "%s", "plans": %s, "branches": %s, "session_window": {"from": "%s", "to": null}}\n' \
        "$slug" "$plans" "$branches" "$from"
    fi
    echo '```'
  } > "$root/$slug/README.md"
}

# mkplan <features-root> <slug> <queue> <state> <name> [<first line>]
mkplan() {
  local root="$1" slug="$2" queue="$3" state="$4" name="$5" first="${6:-# plan}"
  mkdir -p "$root/$slug/$queue/$state"
  { echo "$first"; echo "feature: agentTooling/$slug"; } > "$root/$slug/$queue/$state/$name"
}

PLANS="$TMP/plans/features"

echo "check-plans"

# ── 1. usage ───────────────────────────────────────────────────────────────────
"$AT/check-plans.sh" >/dev/null 2>&1; rc=$?
check "1a. no slug: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'
"$AT/check-plans.sh" --bogus x >/dev/null 2>&1; rc=$?
check "1b. unknown flag: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'
"$AT/check-plans.sh" x extra >/dev/null 2>&1; rc=$?
check "1c. extra argument: exit 2 (got $rc)" '[[ $rc -eq 2 ]]'

# ── 2. well-formed ─────────────────────────────────────────────────────────────
mkfeature "$PLANS" c02 '["01-build-haiku","02-verify-sonnet","03-review-opus"]'
mkplan "$PLANS" c02 auto incomplete 01-build-haiku.md
mkplan "$PLANS" c02 auto incomplete 02-gate.md "# 02 — gate"
mkplan "$PLANS" c02 verify incomplete 02-verify-sonnet.md
mkplan "$PLANS" c02 review incomplete 03-review-opus.md
out="$("$AT/check-plans.sh" c02 2>&1)"; rc=$?
check "2a. well-formed feature exits 0 (got $rc)" '[[ $rc -eq 0 ]]'
ok_lines="$(grep -c '^  ok    ' <<<"$out")"
check "2b. exactly 14 ok lines (got $ok_lines)" '[[ "$ok_lines" -eq 14 ]]'
check "2c. no FAIL lines" '! grep -q "^  FAIL  " <<<"$out"'
check "2d. last line is 'check-plans: 14 checks, 0 failed'" '[[ "$(tail -1 <<<"$out")" == "check-plans: 14 checks, 0 failed" ]]'

# ── 3. slug with no directory ─────────────────────────────────────────────────
out="$("$AT/check-plans.sh" c03-missing 2>&1)"; rc=$?
check "3a. missing feature dir: exit 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "3b. FAIL feature directory exists" 'grep -q "^  FAIL  feature directory exists" <<<"$out"'
check "3c. last line still starts with 'check-plans: '" '[[ "$(tail -1 <<<"$out")" == check-plans:\ * ]]'

# ── 4. fence slug mismatch ────────────────────────────────────────────────────
mkdir -p "$PLANS/c04"
printf '# c04\n\n```json\n{"slug": "other", "plans": ["01-build-haiku"], "branches": ["c04"], "session_window": {"from": "2026-09-04T00:00:00Z", "to": null}}\n```\n' \
  > "$PLANS/c04/README.md"
mkplan "$PLANS" c04 auto incomplete 01-build-haiku.md
out="$("$AT/check-plans.sh" c04 2>&1)"; rc=$?
check "4a. fence slug 'other' != directory: FAIL fence slug matches directory" 'grep -q "^  FAIL  fence slug matches directory" <<<"$out"'

# ── 5. method known ───────────────────────────────────────────────────────────
mkfeature "$PLANS" c05a '["01-build-haiku"]' "" "" bogus
mkplan "$PLANS" c05a auto incomplete 01-build-haiku.md
out="$("$AT/check-plans.sh" c05a 2>&1)"; rc=$?
check "5a. method bogus: FAIL method known" 'grep -q "^  FAIL  method known" <<<"$out"'
mkfeature "$PLANS" c05b '[]' "" "" direct
out="$("$AT/check-plans.sh" c05b 2>&1)"; rc=$?
check "5b. method direct, no auto/: exit 0 (got $rc)" '[[ $rc -eq 0 ]]'

# ── 6. branches non-empty ─────────────────────────────────────────────────────
mkfeature "$PLANS" c06 '[]' '[]'
out="$("$AT/check-plans.sh" c06 2>&1)"; rc=$?
check "6a. empty branches: FAIL branches non-empty" 'grep -q "^  FAIL  branches non-empty" <<<"$out"'

# ── 7. window bounds carry a zone ─────────────────────────────────────────────
mkfeature "$PLANS" c07a '[]' "" "2026-09-04T00:00:00"
out="$("$AT/check-plans.sh" c07a 2>&1)"; rc=$?
check "7a. naive from: FAIL window bounds carry a zone" 'grep -q "^  FAIL  window bounds carry a zone" <<<"$out"'
mkfeature "$PLANS" c07b '[]' "" "2026-09-04T00:00:00+05:30"
out="$("$AT/check-plans.sh" c07b 2>&1)"; rc=$?
check "7b. offset from: ok window bounds carry a zone" 'grep -q "^  ok    window bounds carry a zone" <<<"$out"'

# ── 8. plan filenames well-formed ─────────────────────────────────────────────
mkfeature "$PLANS" c08a '["01-build-haiku"]'
mkplan "$PLANS" c08a auto incomplete 01-build-haiku.md
mkplan "$PLANS" c08a auto incomplete 04-thing.md
out="$("$AT/check-plans.sh" c08a 2>&1)"; rc=$?
check "8a. extra malformed file: FAIL plan filenames well-formed names it" \
  'grep "^  FAIL  plan filenames well-formed" <<<"$out" | grep -q "04-thing.md"'

mkfeature "$PLANS" c08b '["01-build-haiku"]'
mkplan "$PLANS" c08b auto incomplete 01-build-haiku.md
mkplan "$PLANS" c08b verify incomplete 05-gate.md
out="$("$AT/check-plans.sh" c08b 2>&1)"; rc=$?
check "8b. gate sentinel outside auto/: FAIL plan filenames well-formed" 'grep -q "^  FAIL  plan filenames well-formed" <<<"$out"'

mkfeature "$PLANS" c08c '["01-build-haiku"]'
mkplan "$PLANS" c08c auto incomplete 01-build-haiku.md
echo "progress" > "$PLANS/c08c/auto/incomplete/01-build-haiku.progress.md"
out="$("$AT/check-plans.sh" c08c 2>&1)"; rc=$?
check "8c. progress sidecar ignored: ok plan filenames well-formed" 'grep -q "^  ok    plan filenames well-formed" <<<"$out"'

# ── 9. plan numbers padded alike ──────────────────────────────────────────────
mkfeature "$PLANS" c09 '["01-build-haiku","001-extra-haiku"]'
mkplan "$PLANS" c09 auto incomplete 01-build-haiku.md
mkplan "$PLANS" c09 auto incomplete 001-extra-haiku.md
out="$("$AT/check-plans.sh" c09 2>&1)"; rc=$?
check "9a. mixed digit-run lengths: FAIL plan numbers padded alike" 'grep -q "^  FAIL  plan numbers padded alike" <<<"$out"'

# ── 10. no @@TODO@@ stubs queued ──────────────────────────────────────────────
mkfeature "$PLANS" c10a '["01-build-haiku"]'
mkplan "$PLANS" c10a auto incomplete 01-build-haiku.md "@@TODO@@ replace me"
out="$("$AT/check-plans.sh" c10a 2>&1)"; rc=$?
check "10a. queued @@TODO@@ stub: FAIL no @@TODO@@ stubs queued" 'grep -q "^  FAIL  no @@TODO@@ stubs queued" <<<"$out"'
mkfeature "$PLANS" c10b '["01-review-opus"]'
mkplan "$PLANS" c10b review complete 01-review-opus.md "@@TODO@@ replace me"
out="$("$AT/check-plans.sh" c10b 2>&1)"; rc=$?
check "10b. @@TODO@@ outside incomplete/: ok no @@TODO@@ stubs queued" 'grep -q "^  ok    no @@TODO@@ stubs queued" <<<"$out"'
# The shape feature-start.sh actually writes: title, blank line, then the marker. A
# check that reads only line 1 passes this and the batch bills before plan-runner-lib.sh
# refuses it — so assert the real artifact, not the fixture that is easy to build.
mkfeature "$PLANS" c10c '["01-build-haiku", "01-review-opus"]'
mkdir -p "$PLANS/c10c/review/incomplete"
printf '# 01 — review: c10c\n\n@@TODO@@ — write this brief BEFORE the build\n' \
  > "$PLANS/c10c/review/incomplete/01-review-opus.md"
mkplan "$PLANS" c10c auto incomplete 01-build-haiku.md
out="$("$AT/check-plans.sh" c10c 2>&1)"; rc=$?
check "10c. marker under a title line, as feature-start.sh writes it: FAIL" \
  'grep -q "^  FAIL  no @@TODO@@ stubs queued" <<<"$out"'
check "10c2. ... naming the stub" 'grep -q "review/incomplete/01-review-opus.md" <<<"$out"'

# ── 11. every plan file listed in plans[] ─────────────────────────────────────
mkfeature "$PLANS" c11 '["01-build-haiku"]'
mkplan "$PLANS" c11 auto incomplete 01-build-haiku.md
mkplan "$PLANS" c11 auto incomplete 04-stray-haiku.md
out="$("$AT/check-plans.sh" c11 2>&1)"; rc=$?
check "11a. file not listed in plans[]: FAIL names 04-stray-haiku" \
  'grep "^  FAIL  every plan file listed in plans\[\]" <<<"$out" | grep -q "04-stray-haiku"'

# A tier-2 escalation is synthesized into verify/ by run-escalation-plan.sh *during* the
# batch, so it can never be in a plans[] array authored before it ran. Check 11 flagging
# it blocked every documented resume once tier 2 had fired on any level.
mkfeature "$PLANS" c11b '["01-build-haiku"]'
mkplan "$PLANS" c11b auto incomplete 01-build-haiku.md
mkplan "$PLANS" c11b verify complete 05-escalation-opus.md
out="$("$AT/check-plans.sh" c11b 2>&1)"; rc=$?
check "11b. a synthesized escalation absent from plans[]: ok every plan file listed in plans[]" \
  'grep -q "^  ok    every plan file listed in plans\[\]" <<<"$out"'
check "11b2. ... and the feature is clean overall (exit 0, got $rc)" '[[ $rc -eq 0 ]]'
# The exemption is scoped to verify/, the only queue write_escalation_plan writes into —
# the same way the NN-gate.md sentinel is well-formed under auto/ and nowhere else (8b).
mkfeature "$PLANS" c11c '["01-build-haiku"]'
mkplan "$PLANS" c11c auto incomplete 01-build-haiku.md
mkplan "$PLANS" c11c auto complete 05-escalation-opus.md
out="$("$AT/check-plans.sh" c11c 2>&1)"; rc=$?
check "11c. the same name under auto/: FAIL plan filenames well-formed names it" \
  'grep "^  FAIL  plan filenames well-formed" <<<"$out" | grep -q "auto/complete/05-escalation-opus.md"'

# ── 12. every plans[] entry has a file ────────────────────────────────────────
mkfeature "$PLANS" c12a '["01-build-haiku","09-ghost-haiku"]'
mkplan "$PLANS" c12a auto incomplete 01-build-haiku.md
out="$("$AT/check-plans.sh" c12a 2>&1)"; rc=$?
check "12a. plans[] entry with no file: FAIL names 09-ghost-haiku" \
  'grep "^  FAIL  every plans\[\] entry has a file" <<<"$out" | grep -q "09-ghost-haiku"'
mkfeature "$PLANS" c12b '["01-build-haiku","09-ghost-haiku"]'
mkplan "$PLANS" c12b auto incomplete 01-build-haiku.md
mkplan "$PLANS" c12b auto complete 09-ghost-haiku.md
out="$("$AT/check-plans.sh" c12b 2>&1)"; rc=$?
check "12b. plans[] entry filed to complete/: ok every plans[] entry has a file" \
  'grep -q "^  ok    every plans\[\] entry has a file" <<<"$out"'

# ── 13. every queued plan names the feature ───────────────────────────────────
mkfeature "$PLANS" c13 '["01-build-haiku"]'
mkplan "$PLANS" c13 auto incomplete 01-build-haiku.md
echo "# no feature line" > "$PLANS/c13/auto/incomplete/01-build-haiku.md"
out="$("$AT/check-plans.sh" c13 2>&1)"; rc=$?
check "13a. queued plan body never mentions the slug: FAIL every queued plan names the feature" \
  'grep -q "^  FAIL  every queued plan names the feature" <<<"$out"'

# ── 14. plans method has a queue ──────────────────────────────────────────────
mkfeature "$PLANS" c14 '[]' "" "" plans
out="$("$AT/check-plans.sh" c14 2>&1)"; rc=$?
check "14a. method plans, no auto/: FAIL plans method has a queue" 'grep -q "^  FAIL  plans method has a queue" <<<"$out"'

# ── 15. --self ─────────────────────────────────────────────────────────────────
SELF_FEATURES="$AT/self/features"
mkfeature "$SELF_FEATURES" c15 '["01-build-haiku","02-verify-sonnet","03-review-opus"]'
mkplan "$SELF_FEATURES" c15 auto incomplete 01-build-haiku.md
mkplan "$SELF_FEATURES" c15 auto incomplete 02-gate.md "# 02 — gate"
mkplan "$SELF_FEATURES" c15 verify incomplete 02-verify-sonnet.md
mkplan "$SELF_FEATURES" c15 review incomplete 03-review-opus.md
out="$("$AT/check-plans.sh" --self c15 2>&1)"; rc=$?
check "15a. --self well-formed feature exits 0 (got $rc)" '[[ $rc -eq 0 ]]'

# ── 16. the batch stop ─────────────────────────────────────────────────────────
for f in run-batch.sh run-plans.sh run-verify.sh run-review.sh run-escalation-plan.sh plan-runner-lib.sh stamp-timing.sh; do
  cp "$HERE/$f" "$AT/$f" 2>/dev/null || true
done
chmod +x "$AT"/*.sh 2>/dev/null || true

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$TMP/claude.log"
printf '{"type":"result","total_cost_usd":0,"session_id":"stub"}\n'
STUB
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"

printf '#!/usr/bin/env bash\nexit 0\n' > "$PLANS/../gate.sh"
chmod +x "$PLANS/../gate.sh"

rm -f "$TMP/claude.log"
( cd "$TMP" && agentTooling/run-batch.sh c08a >/dev/null 2>&1 ); rc=$?
check "16a. run-batch.sh on the bad-filename feature exits non-zero (got $rc)" '[[ $rc -ne 0 ]]'
check "16b. ... and never called claude" '[[ ! -e "$TMP/claude.log" ]]'

rm -f "$TMP/claude.log"
( cd "$TMP" && agentTooling/run-batch.sh c02 >/dev/null 2>&1 )
check "16c. run-batch.sh on the well-formed feature calls claude" '[[ -e "$TMP/claude.log" ]]'

echo
if (( fails > 0 )); then echo "check-plans: $fails assertion(s) FAILED"; exit 1; fi
echo "check-plans: all assertions passed"
