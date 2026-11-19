#!/usr/bin/env bash
set -uo pipefail

# Self-test for filing a clean round's non-blocking findings after the review
# (self/features/close-after-filing/; LIFECYCLE.md → "The security audit" and "6. Close").
# Run by self/gate.sh, or by hand: bash self/tests/close-backlog.sh
#
# Fixtures, under mktemp -d, in security-audit.sh's shape: throwaway agentTooling checkouts
# (the real runners, feature-close.sh, analysis/, hooks/ and templates/ copied in, and a
# self/BACKLOG.md), each a git repo with a bare origin, on `claude/feat`, whose manifest
# queues `01-review-opus`. A stub `claude` writes a clean review report, or a clean audit
# report for the audit's prompt. The review runs once per fixture; each case below resets
# to the tree it left (the round commit and its stamps), adds its commits, and runs the
# close, which a stray file stops at the check after the head and audit checks. No model,
# no network.
#
# Asserts, on a feature that changes no audit path:
#   K1. one commit `feat: backlog` touching only self/BACKLOG.md after the clean judged head
#       passes the head check: the close reaches the stray check;
#   K2. two such commits in a row: the same;
#   K3. `feat: backlog` touching self/BACKLOG.md and another file is refused, the refusal
#       naming the allowed path (the file and the subject);
#   K4. self/BACKLOG.md alone under another subject is refused, naming the allowed path;
#   K5. `feat: backlog` touching an audit path (hooks/policy.py), alone or beside the
#       BACKLOG, is refused;
#   K6. `feat: backlog` deleting self/BACKLOG.md, turning it into a symlink, or making it
#       executable is refused;
#   K7. `feat: backlog` touching plans/BACKLOG.md — the consuming repo's file, not this
#       layout's — is refused;
#   K8. a merge commit under `feat: backlog` whose first-parent diff is the BACKLOG alone is
#       refused (one parent only: a combined diff hides what a side brought in);
#   K11. a new file named `self/BACKLOG.md<LF>`, or an executable `self/BACKLOG.md<LF><LF>`,
#       alone under `feat: backlog` is refused — `$(…)` strips trailing newlines, so the
#       names are compared past a sentinel (security audit round 1, B1);
#   K12. the same trick under `feat: review stamps` (`timing.jsonl<LF>`) is refused too;
#   K13. a gitlink beside the BACKLOG (or beside timing.jsonl under `feat: review stamps`)
#       hidden from a porcelain diff by an excluded `.gitmodules` with `ignore = all`, or at
#       hooks/sub hidden by `diff.ignoreSubmodules=all`, is refused (audit round 2, B2);
#   K14. `feat: review stamps` making timing.jsonl executable is refused (round 2, C24);
#   K15. an unreviewed hooks/policy.py commit shadowed by a local `git replace` with a
#       stand-in on the same parent — touching only the BACKLOG under `feat: backlog`, or only
#       timing.jsonl under `feat: review stamps` — is refused: the close reads history with
#       replace refs off (round 3, B3/A09);
#   K16. an unreviewed docs-notes.txt change hidden by a cyclic `.git/info/grafts` (the real
#       commit given a fabricated parent that differs from it in the allowed file alone),
#       under `feat: backlog` or `feat: review stamps`, is refused: grafts off (round 4, B06);
# on a feature that changes the hook, behind a clean security audit:
#   K9. a `feat: backlog` commit after the stamps commit: the audit line still prints and
#       the close reaches the stray check;
#   K10. `feat: backlog` touching the BACKLOG and hooks/policy.py is refused;
# and:
#   L1. resolve_roots names self/BACKLOG.md under --self and plans/BACKLOG.md otherwise;
#   L2. audit_paths_in_range, called directly, lists a gitlink at hooks/sub under
#       diff.ignoreSubmodules=all (K13c is refused by the subject loop before F1 runs);
#   D1. the docs state the rule the code holds: ORCHESTRATION.md, LIFECYCLE.md and
#       templates/SECURITY_AUDIT.md each name the `<slug>: backlog` commit.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/close-backlog.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
export RATES_LIVE_LOOKUP=off  # pricing.py never fetches LiteLLM here (self/tests/README.md)
unset CLAUDE_CODE_SESSION_ID CLAUDE_CODE_REMOTE GATE_RESUME
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects"

BASE="main"
BRANCH="claude/feat"
SLUG="feat"
FEATURE_REL="self/features/$SLUG"
REVIEW_STEM="01-review-opus"
BACKLOG_REL="self/BACKLOG.md"
CONSUMER_BACKLOG_REL="plans/BACKLOG.md"
BACKLOG_SUBJECT="$SLUG: backlog"
OTHER_SUBJECT="$SLUG: file the findings"
HOOK_PATH="hooks/policy.py"
TOP_FILES=(run-review.sh plan-runner-lib.sh plan-runner-roots.sh stamp-timing.sh feature-close.sh
           feature-capture.sh env-profile.sh check-plans.sh .gitignore run-plans.sh run-verify.sh
           run-batch.sh feature-start.sh)
STRAY_WORDS="are not $SLUG's cost records"
UNREVIEWED_WORDS="landed after the review judged this feature"
HINT_WORDS="touching only $BACKLOG_REL, under the subject '$BACKLOG_SUBJECT'"
AUDIT_LINE="  audit     "

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
gitq() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
prompt="${@: -1}"
if [[ "$prompt" == *"SECURITY AUDIT plan"* ]]; then
  printf 'Verdict: clean\n\n| input | result |\n|---|---|\n| x | denied |\n\n## Findings\n\nNone.\n\n## Non-blocking findings\n\nNone.\n' > "${AUDIT_OUT:?}"
else
  printf 'Verdict: clean\n\nNo findings.\n' > "${REVIEW_OUT:?}"
fi
printf '{"type":"system","subtype":"init","session_id":"stub"}\n'
printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.5,"num_turns":1,"duration_ms":10,"session_id":"stub","usage":{"input_tokens":1,"output_tokens":1,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"modelUsage":{}}\n'
STUB
chmod +x "$TMP/bin/claude"

# fixture <name> <changed-path> — a checkout whose feature commit changes <changed-path>,
# reviewed clean; prints the checkout
fixture() {
  local at="$TMP/$1/agentTooling" origin="$TMP/$1/origin.git" f
  mkdir -p "$at/$FEATURE_REL/review/incomplete" "$at/hooks" "$at/analysis" "$at/templates"
  for f in "${TOP_FILES[@]}"; do cp "$HERE/$f" "$at/$f" 2>/dev/null; done
  cp "$HERE"/analysis/*.py "$HERE"/analysis/*.json "$at/analysis/" 2>/dev/null
  cp "$HERE"/hooks/*.py "$HERE"/hooks/*.sh "$at/hooks/"
  cp "$HERE/templates/SECURITY_AUDIT.md" "$at/templates/"
  printf '# Backlog\n\n- **An entry already filed.**\n' > "$at/$BACKLOG_REL"
  git init -q "$at"
  gitq "$at" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$at" config user.email test@example.invalid
  gitq "$at" config user.name "close backlog test"
  gitq "$at" add -A
  gitq "$at" commit -q -m base
  git init -q --bare "$origin"
  gitq "$origin" symbolic-ref HEAD "refs/heads/$BASE"
  gitq "$at" remote add origin "$origin"
  gitq "$at" push -q origin "$BASE"
  gitq "$at" checkout -q -b "$BRANCH"
  printf '# %s\n\nA feature.\n\n```json\n{"slug": "%s", "method": "direct", "plans": ["%s"], "branches": ["%s"], "base": "%s"}\n```\n' \
    "$SLUG" "$SLUG" "$REVIEW_STEM" "$BRANCH" "$BASE" > "$at/$FEATURE_REL/README.md"
  printf '# 01 — review\n\nReview it.\n' > "$at/$FEATURE_REL/review/incomplete/$REVIEW_STEM.md"
  mkdir -p "$(dirname "$at/$2")"
  echo "# changed by the feature" >> "$at/$2"
  gitq "$at" add -A
  gitq "$at" commit -q -m "feat: change $2"
  ( cd "$at" && env AGENTTOOLING_PROFILE=local PATH="$TMP/bin:$PATH" \
      AUDIT_OUT="$at/$FEATURE_REL/audit-report.md" REVIEW_OUT="$at/self/review-report.md" \
      ./run-review.sh --self "$SLUG" >/dev/null 2>&1 )
  echo "$at"
}

# reset_to <at> <sha> — back to the reviewed tree, nothing stray
reset_to() { gitq "$1" reset -q --hard "$2"; rm -f "$1/stray.txt"; }
# file_backlog <at> <subject> — append one finding to the BACKLOG and commit it alone
file_backlog() {
  echo "- **A finding filed after the review.**" >> "$1/$BACKLOG_REL"
  gitq "$1" add -A
  gitq "$1" commit -q -m "$2"
}
# close_it <at> — the close, stopped by a stray file at the check after the head and audit checks
close_it() {
  echo "a stray" > "$1/stray.txt"
  ( cd "$1" && env AGENTTOOLING_PROFILE=local PATH="$TMP/bin:$PATH" ./feature-close.sh --self "$SLUG" 2>&1 )
}
passed_head_check() { [[ $1 -ne 0 ]] && grep -qF "$STRAY_WORDS" <<<"$2" && ! grep -qF "$UNREVIEWED_WORDS" <<<"$2"; }
refused_unreviewed() { [[ $1 -eq 1 ]] && grep -qF "$UNREVIEWED_WORDS" <<<"$2" && grep -qF "$HINT_WORDS" <<<"$2" && ! grep -qF "$STRAY_WORDS" <<<"$2"; }

echo "close-backlog"

# ── A feature that changes no audit path ─────────────────────────────────────
AT="$(fixture plain docs-notes.txt)"
REVIEWED="$(git -C "$AT" rev-parse HEAD)"
check "setup: the review left a clean tree on its stamps commit" \
  '[[ -z "$(git -C "$AT" status --porcelain)" && "$(git -C "$AT" log -1 --format=%s)" == "$SLUG: review stamps" ]]'

file_backlog "$AT" "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K1 a '$BACKLOG_SUBJECT' commit touching $BACKLOG_REL alone passes the head check" 'passed_head_check $rc "$out"'

reset_to "$AT" "$REVIEWED"
file_backlog "$AT" "$BACKLOG_SUBJECT"; file_backlog "$AT" "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K2 two such commits pass it too" 'passed_head_check $rc "$out"'

reset_to "$AT" "$REVIEWED"
echo "# unreviewed" >> "$AT/docs-notes.txt"
file_backlog "$AT" "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K3 the subject with another file beside the BACKLOG is refused, naming the allowed path (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
file_backlog "$AT" "$OTHER_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K4 the BACKLOG alone under another subject is refused, naming the allowed path (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
mkdir -p "$AT/hooks"; echo "# unreviewed" >> "$AT/$HOOK_PATH"
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K5a an audit path alone under the subject is refused, naming the allowed path (got $rc)" 'refused_unreviewed $rc "$out"'
reset_to "$AT" "$REVIEWED"
echo "# unreviewed" >> "$AT/$HOOK_PATH"
file_backlog "$AT" "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K5b an audit path beside the BACKLOG under the subject is refused, naming the allowed path (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
gitq "$AT" rm -q "$BACKLOG_REL"; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K6a deleting the BACKLOG under the subject is refused (got $rc)" 'refused_unreviewed $rc "$out"'
reset_to "$AT" "$REVIEWED"
rm -f "$AT/$BACKLOG_REL"; ln -s ../hooks/policy.py "$AT/$BACKLOG_REL"
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K6b turning the BACKLOG into a symlink under the subject is refused (got $rc)" 'refused_unreviewed $rc "$out"'
reset_to "$AT" "$REVIEWED"
chmod +x "$AT/$BACKLOG_REL"
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K6c making the BACKLOG executable under the subject is refused (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
mkdir -p "$AT/plans"; echo "- **Filed in the wrong layout.**" > "$AT/$CONSUMER_BACKLOG_REL"
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K7 $CONSUMER_BACKLOG_REL under the subject in the self layout is refused (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
gitq "$AT" checkout -q -b side
file_backlog "$AT" "$BACKLOG_SUBJECT"
gitq "$AT" checkout -q "$BRANCH"
gitq "$AT" merge -q --no-ff -m "$BACKLOG_SUBJECT" side
out="$(close_it "$AT")"; rc=$?
check "K8 a merge under the subject, its first-parent diff the BACKLOG alone, is refused (got $rc)" \
  '[[ "$(git -C "$AT" rev-list --parents -n 1 HEAD | wc -w | tr -d " ")" == 3 ]] && refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
printf 'payload\n' > "$AT/$BACKLOG_REL"$'\n'
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K11a a file named '$BACKLOG_REL<LF>' alone under the subject is refused (audit round 1, B1; got $rc)" \
  '[[ -n "$(git -C "$AT" show --name-only --format= HEAD)" ]] && refused_unreviewed $rc "$out"'
reset_to "$AT" "$REVIEWED"
printf '#!/bin/sh\necho payload\n' > "$AT/$BACKLOG_REL"$'\n\n'; chmod +x "$AT/$BACKLOG_REL"$'\n\n'
gitq "$AT" add -A; gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K11b an executable '$BACKLOG_REL<LF><LF>' alone under the subject is refused (got $rc)" 'refused_unreviewed $rc "$out"'

reset_to "$AT" "$REVIEWED"
printf 'payload\n' > "$AT/$FEATURE_REL/timing.jsonl"$'\n'
gitq "$AT" add -A; gitq "$AT" commit -q -m "$SLUG: review stamps"
out="$(close_it "$AT")"; rc=$?
check "K12 the same name trick under '$SLUG: review stamps' ('timing.jsonl<LF>') is refused too (got $rc)" 'refused_unreviewed $rc "$out"'

# K13: a gitlink beside the one file, hidden from a porcelain diff by an uncommitted
# `.gitmodules` (`ignore = all`, kept out of the stray check by info/exclude) or by
# `diff.ignoreSubmodules=all` (security audit round 2, B2/S4)
hide_gitlinks() {
  printf '[submodule "sub"]\n\tpath = sub\n\turl = ./nowhere\n\tignore = all\n' > "$1/.gitmodules"
  echo ".gitmodules" >> "$1/.git/info/exclude"
}
add_gitlink() { gitq "$1" update-index --add --cacheinfo "160000,$REVIEWED,$2"; }
reset_to "$AT" "$REVIEWED"
hide_gitlinks "$AT"
echo "- **A finding.**" >> "$AT/$BACKLOG_REL"; gitq "$AT" add "$BACKLOG_REL"; add_gitlink "$AT" sub
gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K13a a gitlink beside the BACKLOG under the subject, hidden by .gitmodules ignore=all, is refused (got $rc)" \
  '[[ "$(git -C "$AT" ls-tree HEAD -- sub | cut -c1-6)" == 160000 ]] && refused_unreviewed $rc "$out"'
reset_to "$AT" "$REVIEWED"
echo '{"event":"x"}' >> "$AT/$FEATURE_REL/timing.jsonl"; gitq "$AT" add "$FEATURE_REL/timing.jsonl"; add_gitlink "$AT" sub
gitq "$AT" commit -q -m "$SLUG: review stamps"
out="$(close_it "$AT")"; rc=$?
check "K13b the same gitlink beside timing.jsonl under '$SLUG: review stamps' is refused (got $rc)" 'refused_unreviewed $rc "$out"'
rm -f "$AT/.gitmodules"
reset_to "$AT" "$REVIEWED"
gitq "$AT" config diff.ignoreSubmodules all
echo "- **A finding.**" >> "$AT/$BACKLOG_REL"; gitq "$AT" add "$BACKLOG_REL"; add_gitlink "$AT" hooks/sub
gitq "$AT" commit -q -m "$BACKLOG_SUBJECT"
out="$(close_it "$AT")"; rc=$?
check "K13c a gitlink at hooks/sub beside the BACKLOG, hidden by diff.ignoreSubmodules=all, is refused (got $rc)" \
  '[[ $rc -eq 1 ]] && ! grep -qF "$STRAY_WORDS" <<<"$out"'
gitq "$AT" config --unset diff.ignoreSubmodules
reset_to "$AT" "$REVIEWED"
chmod +x "$AT/$FEATURE_REL/timing.jsonl"
gitq "$AT" add -A; gitq "$AT" commit -q -m "$SLUG: review stamps"
out="$(close_it "$AT")"; rc=$?
check "K14 '$SLUG: review stamps' making timing.jsonl executable is refused (audit round 2, C24; got $rc)" 'refused_unreviewed $rc "$out"'

# K15: an unreviewed commit shadowed by a local replace ref to a stand-in on the same parent
# that touches only the one file the subject allows (security audit round 3, B3/A09)
# shadow <at> <subject> <stand-in path> — commit an unreviewed hooks/policy.py change under
# <subject>, then replace it with a stand-in touching only <stand-in path>, index resynced
shadow() {
  local at="$1" real fake
  echo "# unreviewed" >> "$at/$HOOK_PATH"; gitq "$at" add "$HOOK_PATH"; gitq "$at" commit -q -m "$2"
  real="$(git -C "$at" rev-parse HEAD)"
  gitq "$at" checkout -q --detach "$REVIEWED"
  echo "- **A stand-in.**" >> "$at/$3"; gitq "$at" add "$3"; gitq "$at" commit -q -m "$2"
  fake="$(git -C "$at" rev-parse HEAD)"
  gitq "$at" checkout -q "$BRANCH"
  gitq "$at" replace "$real" "$fake"
  gitq "$at" read-tree -u --reset HEAD
}
reset_to "$AT" "$REVIEWED"
shadow "$AT" "$BACKLOG_SUBJECT" "$BACKLOG_REL"
out="$(close_it "$AT")"; rc=$?
check "K15a an unreviewed commit shadowed by a replace ref to a BACKLOG-only '$BACKLOG_SUBJECT' is refused (got $rc)" \
  '[[ -n "$(git -C "$AT" replace -l)" ]] && refused_unreviewed $rc "$out"'
gitq "$AT" replace -d "$(git -C "$AT" replace -l)"
reset_to "$AT" "$REVIEWED"
shadow "$AT" "$SLUG: review stamps" "$FEATURE_REL/timing.jsonl"
out="$(close_it "$AT")"; rc=$?
check "K15b the same, shadowed by a timing.jsonl-only '$SLUG: review stamps', is refused (got $rc)" \
  '[[ -n "$(git -C "$AT" replace -l)" ]] && refused_unreviewed $rc "$out"'
gitq "$AT" replace -d "$(git -C "$AT" replace -l)"

# K16: an unreviewed non-audit change hidden by a cyclic .git/info/grafts that gives the real
# commit a fabricated parent differing from it in the one allowed file alone (round 4, B06/B08)
# graft_hide <at> <subject> <allowed path>
graft_hide() {
  local at="$1" judged parent tree fake real
  judged="$(git -C "$at" rev-parse "$REVIEWED^")"; parent="$(git -C "$at" rev-parse "$judged^")"
  gitq "$at" checkout -q --detach "$REVIEWED"
  echo "# unreviewed" >> "$at/docs-notes.txt"; gitq "$at" commit -q -am "fabricated"
  tree="$(git -C "$at" rev-parse 'HEAD^{tree}')"
  gitq "$at" checkout -q -f "$BRANCH"
  fake="$(git -C "$at" commit-tree "$tree" -p "$parent" -m fabricated)"
  echo "# unreviewed" >> "$at/docs-notes.txt"; echo "- **A finding.**" >> "$at/$3"
  gitq "$at" commit -q -am "$2"
  real="$(git -C "$at" rev-parse HEAD)"
  printf '%s %s\n%s %s\n%s %s %s\n' "$real" "$fake" "$fake" "$judged" "$judged" "$parent" "$fake" > "$at/.git/info/grafts"
}
reset_to "$AT" "$REVIEWED"
graft_hide "$AT" "$BACKLOG_SUBJECT" "$BACKLOG_REL"
out="$(close_it "$AT")"; rc=$?
check "K16a an unreviewed change hidden by a cyclic graft under '$BACKLOG_SUBJECT' is refused (got $rc)" \
  '[[ "$(git -C "$AT" -c advice.graftFileDeprecated=false diff --name-only HEAD^ HEAD)" == "$BACKLOG_REL" ]] && refused_unreviewed $rc "$out"'
rm -f "$AT/.git/info/grafts"
reset_to "$AT" "$REVIEWED"
graft_hide "$AT" "$SLUG: review stamps" "$FEATURE_REL/timing.jsonl"
out="$(close_it "$AT")"; rc=$?
check "K16b the same under '$SLUG: review stamps' is refused (got $rc)" \
  '[[ "$(git -C "$AT" -c advice.graftFileDeprecated=false diff --name-only HEAD^ HEAD)" == "$FEATURE_REL/timing.jsonl" ]] && refused_unreviewed $rc "$out"'
rm -f "$AT/.git/info/grafts"

# L2: audit_paths_in_range itself lists a gitlink at an audit path that diff.ignoreSubmodules
# would hide — K13c is refused by the subject loop first, so it cannot show this
reset_to "$AT" "$REVIEWED"
gitq "$AT" config diff.ignoreSubmodules all
add_gitlink "$AT" hooks/sub; gitq "$AT" commit -q -m "$SLUG: change"
in_range="$( source "$AT/plan-runner-roots.sh"; resolve_roots --self; audit_paths_in_range "$AT" "$REVIEWED..HEAD" )"
check "L2 audit_paths_in_range lists a gitlink at hooks/sub despite diff.ignoreSubmodules=all" '[[ "$in_range" == "hooks/sub" ]]'
gitq "$AT" config --unset diff.ignoreSubmodules

# ── A feature that changes the hook, behind a clean security audit ──────────
ATH="$(fixture hook hooks/allow-repo-commands.sh)"
REVIEWED_H="$(git -C "$ATH" rev-parse HEAD)"
file_backlog "$ATH" "$BACKLOG_SUBJECT"
out="$(close_it "$ATH")"; rc=$?
check "K9 a hook change: the BACKLOG commit after the stamps keeps the audit line, and the close reaches the stray check" \
  'passed_head_check $rc "$out" && grep -qF "$AUDIT_LINE" <<<"$out"'

reset_to "$ATH" "$REVIEWED_H"
echo "# unreviewed" >> "$ATH/$HOOK_PATH"
file_backlog "$ATH" "$BACKLOG_SUBJECT"
out="$(close_it "$ATH")"; rc=$?
check "K10 a hook change: the BACKLOG and an audit path under the subject are refused (got $rc)" \
  '[[ $rc -eq 1 ]] && grep -qF "$UNREVIEWED_WORDS" <<<"$out" && ! grep -qF "$STRAY_WORDS" <<<"$out"'

# ── The layout's BACKLOG, and the docs ───────────────────────────────────────
roots_label() { ( source "$HERE/plan-runner-roots.sh"; resolve_roots "${1:-}"; echo "$BACKLOG_LABEL" ); }
check "L1 resolve_roots: $BACKLOG_REL under --self, $CONSUMER_BACKLOG_REL otherwise" \
  '[[ "$(roots_label --self)" == "$BACKLOG_REL" && "$(roots_label)" == "$CONSUMER_BACKLOG_REL" ]]'
check "D1 ORCHESTRATION.md, LIFECYCLE.md and templates/SECURITY_AUDIT.md name the '<slug>: backlog' commit" \
  'grep -qF "<slug>: backlog" "$HERE/ORCHESTRATION.md" && grep -qF "S: backlog" "$HERE/LIFECYCLE.md" && grep -qF "<slug>: backlog" "$HERE/templates/SECURITY_AUDIT.md"'

echo ""
if (( fails )); then echo "close-backlog: $fails check(s) failed"; exit 1; fi
echo "close-backlog: all checks passed"
