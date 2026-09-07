#!/usr/bin/env bash
set -uo pipefail

# Self-test for cost recovery at close time
# (self/features/recover-cost-at-close/README.md). Run by self/gate.sh, or by hand:
# bash self/tests/recover-at-close.sh
#
# Three throwaway checkouts under one mktemp -d, a stub `claude`, a stub `gh`, and
# synthesized `~/.claude/projects/*/<session_id>.jsonl` transcripts under a redirected
# $HOME. No model, no network; a few seconds.
#
# The defect under test: a review that ran to completion (exit 0, PR opened) whose event
# stream carried no `result` event was recorded at $0, and the close committed that zero.
# Nothing on disk told the difference between "this cost nothing" and "nobody recorded
# what this cost", and recovery — which can price it from the session transcript — was
# only ever run by the weekly sweep, never by the close.
#
# Asserts, in order:
#   A. write_usage_sidecar records whether the stream held a result event at all:
#      A1-A3. a run that exits 0 with assistant events but NO result line yields
#             `result_event: "missing"`, `outcome: "complete"` (the exit code is what
#             `outcome` means, and it really did complete), `total_cost_usd: null`, and
#             is still filed to auto/complete/ — the routing is not the bug;
#      A4.    that sidecar still carries a session_id, from the stream's first event;
#      A5-A6. the same run WITH a result line yields `result_event: "seen"` and the
#             CLI's own cost. Without A5 the field could be hardcoded and A1 pass;
#      A7-A8. the runner's other two unpriced shapes, for D to price the reasons of: a
#             non-zero rc with no result line is `failed` + `missing` and goes to
#             auto/failed/, and a leftover stream beside a resumed plan is harvested as
#             a `killed` attempt (harvest_orphan_attempt).
#   B. recover_attempts.py --for <slug>:
#      B1-B2. recovers a `complete`-outcome null-cost attempt — recovery is not gated on
#             `outcome`, and the completed-with-no-result-event case is exactly what it
#             must price — and leaves every other feature's sidecar byte-identical;
#      B3.    reports one attempt recovered, not two;
#      B4.    an unknown slug is a refusal (non-zero) that writes nothing;
#      B5.    without --for the whole-tree walk is unchanged — sweep.sh passes no --for.
#   C. feature-close.sh recovers before it captures:
#      C1-C5. with the transcript present the review bucket carries real dollars instead
#             of $0.0000, the rewritten usage.json is inside the `<slug>: cost records`
#             commit (not named as a stray, which would refuse the close), and
#             report.json agrees;
#      C6-C9. with the transcript gone the close still exits 0 — recovery is reported,
#             never fatal — names the plan as unrecoverable, and the printed cost line
#             reads `review $0.0000 (0.0%, unpriced: <stem> — no result event, transcript
#             not found)` rather than the bare `review $0.0000 (0.0%)` the defect printed;
#      C10-C12. `--recapture` closes an already-closed feature again with its worktree and
#             local branch gone — the repair path for the features whose zero is already
#             committed — re-committing the cost records without moving session_window.to;
#      C13-C17. ...and again with the REMOTE branch gone too, which is what a forge with
#             delete-on-merge leaves: `--recapture` proceeds on the manifest being on
#             main and the `<slug>: start` commit being an ancestor of it, while a plain
#             close still refuses "nothing to close" and so does `--recapture` for a
#             feature that was never started.
#   D. report.py's unpriced_reason and the queue->bucket mapping:
#      D1-D4. each of the three reason strings, from a sidecar of that shape — no
#             `result_event` at all (the shape EVERY sidecar on disk has today, so the
#             branch the documented repair runs), `missing`, and a harvested `killed`
#             attempt. Pinned by exact text, so no single return value satisfies them all;
#      D5-D6. `set(QUEUE_COST_BUCKETS) == QUEUE_DIRS`, and that report.py refuses to
#             import when it does not — the cheap guard against a queue whose dollars are
#             summed while its unpriced plans vanish from the printed line.
#   E. rollback_recovery, the mirror of feature-lifecycle.sh's C5f for rollback_carry: a
#      capture that refuses AFTER recovery rewrote a sidecar leaves the primary clean and
#      the sidecar as it was, and the re-run refuses for the same reason rather than for
#      dirt this run made.
#   F. a `.usage.json` outside a queue is a stranger: the worktree holding one is kept
#      with a warning rather than force-removed, while one inside a queue is the
#      harness's own and the worktree comes away.
#
# A, B and C were RED until the feature landed: A on the absent `result_event` field, B on
# the absent `--for` flag, C on both plus the close's new step. D5-D6 and F1-F2 were RED
# until the rework (the import guard, and narrowing the sidecar match to known queues);
# D1-D4 and E are the missing assertions that rework added for behaviour already shipped,
# which is what the review escalated. A missing script or flag fails its own assertions
# loudly rather than aborting the run — the convention cost-recovery.sh uses (no `set -e`,
# and every cp below tolerates absence).

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# pwd -P for the same reason capture-guard.sh does it: roots.py resolves
# AGENT_TOOLING_DIR with Path.resolve(), and on macOS an unresolved /var/... fixture path
# matches no transcript, which would make every assertion pass or fail vacuously.
TMP="$(cd "$TMP" && pwd -P)"

source "$HERE/self/tests/fixtures/transcripts/build-transcript.sh"
source "$HERE/self/tests/fixtures/usage/build-usage.sh"

fails=0
ok()   { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# One field of a JSON file, or the empty string if the file, the path or the interpreter
# is not there — an absent deliverable must fail an assertion, never abort the script.
jf() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }
# One field of the manifest's last ```json fence — the one capture_planning.py reads.
fence() { python3 -c "import json,re,sys; t=open(sys.argv[1]).read(); m=re.findall(r'\`\`\`json\n(.*?)\n\`\`\`', t, re.S); d=json.loads(m[-1]); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null; }

MODEL="claude-opus-5"
# The review sessions this feature exists to price ran on 2026-09-04; the date only
# selects a rate tier here. A session the CAPTURE must see is stamped now instead, since
# feature-start.sh opens `session_window.from` at the moment it runs and a bound is a
# bound (fixtures/transcripts/build-transcript.sh).
TS="2026-09-04T20:00:00.000Z"
now_z() { date -u '+%Y-%m-%dT%H:%M:%S.000Z'; }

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.claude/projects"
export HOME="$FAKE_HOME"
# ~/.claude/projects/<cwd with every / replaced by ->, the encoding Claude Code uses.
project_dir() { echo "$FAKE_HOME/.claude/projects/$(echo "$1" | tr '/' '-')"; }

mkdir -p "$TMP/bin"
# Stub claude: the shape a real `--output-format stream-json --verbose` run streams — an
# init event carrying the session id, then one assistant event with a mutating tool call.
# The closing `result` event, which is the only place the CLI reports cost, is emitted
# unless CLAUDE_STUB_NO_RESULT is set. That is the defect's exact shape: a run that
# exits 0 having done its work, whose stream never said what it cost.
cat > "$TMP/bin/claude" <<'STUB'
#!/usr/bin/env bash
SID="${CLAUDE_STUB_SESSION:-stub-session}"
printf '{"type":"system","subtype":"init","session_id":"%s"}\n' "$SID"
printf '{"type":"assistant","session_id":"%s","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/y.txt"}}]}}\n' "$SID"
if [[ -z "${CLAUDE_STUB_NO_RESULT:-}" ]]; then
  printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":1.25,"num_turns":3,"duration_ms":4000,"session_id":"%s","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"modelUsage":{}}\n' "$SID"
fi
exit "${CLAUDE_STUB_RC:-0}"
STUB
# Stub gh: logs every argv line; no PR is ever already open.
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${GH_LOG:-/dev/null}"
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view")     exit 1 ;;
  "pr create")   echo "https://example.invalid/pr/1"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/claude" "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"

echo "recover at close"

# ── A. the sidecar says whether a result event was seen ───────────────────────
# Driven through the real runner rather than by calling write_usage_sidecar directly:
# what is under test is the field a real `claude -p` stream produces, and the runner is
# what decides the outcome from the exit code.
RA="$TMP/runner/agentTooling"
mkdir -p "$RA/self/features" "$RA/self"
for f in run-plans.sh plan-runner-lib.sh plan-runner-roots.sh; do
  cp "$HERE/$f" "$RA/$f" 2>/dev/null || true
done
chmod +x "$RA"/*.sh 2>/dev/null || true
printf '#!/usr/bin/env bash\nexit 0\n' > "$RA/self/gate.sh"; chmod +x "$RA/self/gate.sh"

RSLUG="noresult"
RF="$RA/self/features/$RSLUG"
run_one_plan() {                       # run_one_plan <stem>
  rm -rf "$RF"
  mkdir -p "$RF/auto/incomplete"
  echo '{"slug":"noresult","plans":[],"branches":[]}' > "$RF/README.md"
  echo "a plan for $RSLUG" > "$RF/auto/incomplete/$1.md"
  ( cd "$RA" && ./run-plans.sh --self "$RSLUG" >/dev/null 2>&1 )
  return 0                    # a non-zero rc is A7's subject, not an abort
}

CLAUDE_STUB_NO_RESULT=1 CLAUDE_STUB_SESSION="sess-no-result" run_one_plan 01-x-haiku
U_MISSING="$RF/auto/complete/01-x-haiku.usage.json"
re_missing="$(jf "$U_MISSING" 'd.get("result_event")')"
check "A1. a stream with no result event records result_event: missing (got ${re_missing:-<absent>})" '[[ "$re_missing" == "missing" ]]'
out_missing="$(jf "$U_MISSING" 'd.get("outcome")')"
cost_missing="$(jf "$U_MISSING" 'd.get("total_cost_usd")')"
check "A2. ... while outcome stays 'complete' — the exit code is what outcome means (got ${out_missing:-<absent>}/${cost_missing:-<absent>})" '[[ "$out_missing" == "complete" && "$cost_missing" == "None" ]]'
check "A3. ... and the plan is still filed to auto/complete/, not failed/" '[[ -f "$RF/auto/complete/01-x-haiku.md" && ! -e "$RF/auto/failed/01-x-haiku.md" ]]'
sid_missing="$(jf "$U_MISSING" 'd.get("session_id")')"
check "A4. ... carrying the session id from the stream's first event (got ${sid_missing:-<absent>})" '[[ "$sid_missing" == "sess-no-result" ]]'

# Kept before the next run_one_plan, which resets the feature directory. D2 prices this
# sidecar's reason, and it is the runner's own output rather than a hand-rolled shape.
cp "$U_MISSING" "$TMP/missing.usage.json"; U_MISSING_KEPT="$TMP/missing.usage.json"

CLAUDE_STUB_SESSION="sess-with-result" run_one_plan 02-y-haiku
U_SEEN="$RF/auto/complete/02-y-haiku.usage.json"
re_seen="$(jf "$U_SEEN" 'd.get("result_event")')"
check "A5. the same run WITH a result event records result_event: seen (got ${re_seen:-<absent>})" '[[ "$re_seen" == "seen" ]]'
cost_seen="$(jf "$U_SEEN" 'd.get("total_cost_usd")')"
check "A6. ... and the CLI's own cost (got ${cost_seen:-<absent>})" '[[ "$cost_seen" == "1.25" ]]'

# A7: the failure shape. `outcome` is the exit code's fact in both directions, so a
# non-zero rc with no result line is `failed` and `missing` — and the routing is still
# the runner's, not this field's.
CLAUDE_STUB_NO_RESULT=1 CLAUDE_STUB_RC=1 CLAUDE_STUB_SESSION="sess-failed" run_one_plan 03-z-haiku
U_FAILED="$RF/auto/failed/03-z-haiku.usage.json"
re_failed="$(jf "$U_FAILED" 'd.get("result_event")')"
out_failed="$(jf "$U_FAILED" 'd.get("outcome")')"
check "A7. a non-zero run with no result event is failed + missing, filed to auto/failed/ (got ${out_failed:-<absent>}/${re_failed:-<absent>})" '[[ "$out_failed" == "failed" && "$re_failed" == "missing" && -f "$RF/auto/failed/03-z-haiku.md" ]]'

# A8 resets the feature directory, so keep the two sidecars D2 and D4 price the reasons
# of — they are the runner's own output, which is the point of reading them there rather
# than hand-rolling the shapes.
cp "$U_FAILED" "$TMP/failed.usage.json"; U_FAILED_KEPT="$TMP/failed.usage.json"

# A8: the KILLED shape, written by the runner rather than hand-rolled.
# harvest_orphan_attempt runs at the top of run_plan when a leftover stream beside a
# resumed plan holds a session `attempts[]` has never seen — a run killed outright, which
# never reached finalize_plan. It files that attempt as `outcome: "killed"`, and the
# resume that follows adds its own attempt beside it. This is the resumed-plan shape
# compute_cost_rollup's per-attempt branch reads, and D4 prices its reason.
rm -rf "$RF"
mkdir -p "$RF/auto/inprogress"
echo '{"slug":"noresult","plans":[],"branches":[]}' > "$RF/README.md"
echo "a plan for $RSLUG" > "$RF/auto/inprogress/04-k-haiku.md"
: > "$RF/auto/inprogress/04-k-haiku.progress.md"
printf '{"type":"system","subtype":"init","session_id":"sess-killed"}\n' > "$RF/auto/inprogress/04-k-haiku.stream.jsonl"
( cd "$RA" && CLAUDE_STUB_SESSION="sess-resumed" ./run-plans.sh --self "$RSLUG" >/dev/null 2>&1 )
U_KILLED="$RF/auto/complete/04-k-haiku.usage.json"
killed_outcome="$(jf "$U_KILLED" '[a.get("outcome") for a in d["attempts"] if a.get("session_id")=="sess-killed"]')"
check "A8. a leftover stream from a killed run is harvested as a 'killed' attempt (got ${killed_outcome:-<absent>})" '[[ "$killed_outcome" == "['"'"'killed'"'"']" ]]'

# ── B. recover_attempts.py --for <slug> ──────────────────────────────────────
CA="$TMP/recover/agentTooling"
mkdir -p "$CA/analysis" "$CA/self/features"
for f in pricing.py roots.py transcript.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$CA/analysis/$f" 2>/dev/null || true
done
PROJ="$FAKE_HOME/.claude/projects/recover-fixtures"
mkdir -p "$PROJ"

S_ONE="sess-for-one"; S_TWO="sess-for-two"
F_ONE="$CA/self/features/featone/review/complete"
F_TWO="$CA/self/features/feattwo/review/complete"
mkdir -p "$F_ONE" "$F_TWO"
U_ONE="$F_ONE/01-review-opus.usage.json"
U_TWO="$F_TWO/01-review-opus.usage.json"
write_unpriced_usage_json "$U_ONE" "$S_ONE" opus
write_unpriced_usage_json "$U_TWO" "$S_TWO" opus
transcript_line m-one "$MODEL" "$TS" 1000 500 2000 0 0 > "$PROJ/$S_ONE.jsonl"
transcript_line m-two "$MODEL" "$TS" 1000 500 2000 0 0 > "$PROJ/$S_TWO.jsonl"
cp "$U_TWO" "$TMP/feattwo.pristine"

for_out="$(python3 "$CA/analysis/recover_attempts.py" --self --for featone 2>&1)"; for_rc=$?
one_recovered="$(jf "$U_ONE" 'd["attempts"][0].get("recovered_cost_usd")')"
one_outcome="$(jf "$U_ONE" 'd["attempts"][0].get("outcome")')"
check "B1. --for <slug> recovers a complete-outcome null-cost attempt (rc $for_rc, got ${one_recovered:-<absent>} on a '${one_outcome:-<absent>}' attempt)" '[[ $for_rc -eq 0 && -n "$one_recovered" && "$one_recovered" != "None" && "$one_outcome" == "complete" ]]'
check "B2. ... and touches no other feature's sidecar" 'cmp -s "$TMP/feattwo.pristine" "$U_TWO"'
check "B3. ... reporting one attempt recovered, not two" 'grep -q "1 attempt(s) recovered" <<<"$for_out"'

cp "$U_ONE" "$TMP/featone.after-for"
bad_out="$(python3 "$CA/analysis/recover_attempts.py" --self --for no-such-feature 2>&1)"; bad_rc=$?
# `! grep -qi unrecognized` is what keeps this from passing vacuously before the flag
# exists: argparse reads `--for` as an abbreviation of `--force` and rejects the slug as
# an unrecognized positional — an exit 2 naming the slug, for entirely the wrong reason.
check "B4. --for an unknown slug is refused (got $bad_rc), naming it, and writes nothing" '[[ $bad_rc -ne 0 ]] && grep -q "no-such-feature" <<<"$bad_out" && ! grep -qi "unrecognized" <<<"$bad_out" && cmp -s "$TMP/featone.after-for" "$U_ONE" && cmp -s "$TMP/feattwo.pristine" "$U_TWO"'

all_out="$(python3 "$CA/analysis/recover_attempts.py" --self 2>&1)"; all_rc=$?
two_recovered="$(jf "$U_TWO" 'd["attempts"][0].get("recovered_cost_usd")')"
check "B5. without --for the whole-tree walk is unchanged — sweep.sh's call still reaches feattwo (rc $all_rc, got ${two_recovered:-<absent>})" '[[ $all_rc -eq 0 && -n "$two_recovered" && "$two_recovered" != "None" ]]'

# ── C. the close recovers before it captures ─────────────────────────────────
# A real git repo with a bare origin beside it, the way feature-lifecycle.sh builds one:
# feature-close.sh refuses anywhere else, and the assertions here are about the commit it
# makes and the line it prints.
LA="$TMP/close/agentTooling"
LORIGIN="$TMP/close/origin.git"
mkdir -p "$LA/analysis" "$LA/self/features" "$LA/templates/plans/features"
for f in feature-start.sh feature-close.sh plan-runner-roots.sh plan-runner-lib.sh stamp-timing.sh; do
  cp "$HERE/$f" "$LA/$f" 2>/dev/null || true
done
for f in pricing.py roots.py transcript.py capture_planning.py report.py manifest.py recover_attempts.py; do
  cp "$HERE/analysis/$f" "$LA/analysis/$f" 2>/dev/null || true
done
cp "$HERE/templates/plans/features/TEMPLATE.md" "$LA/templates/plans/features/TEMPLATE.md" 2>/dev/null || true
cp "$HERE/self/pr.sh" "$LA/self/pr.sh" 2>/dev/null || true
printf '#!/usr/bin/env bash\nexit 0\n' > "$LA/self/worktree-setup.sh"
printf '#!/usr/bin/env bash\nHERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n{ echo "# Gate report"; echo ""; echo "# VERDICT"; echo "all checks passed"; } > "$HERE/self/gate-report.txt"\nexit 0\n' > "$LA/self/gate.sh"
chmod +x "$LA"/*.sh "$LA/self"/*.sh 2>/dev/null || true
printf 'self/gate-report*.txt\nself/review-report.md\n' > "$LA/.gitignore"

git -C "$LA" init -q
git -C "$LA" symbolic-ref HEAD refs/heads/main
git -C "$LA" config user.email test@example.invalid
git -C "$LA" config user.name "recover-at-close test"
git -C "$LA" add -A && git -C "$LA" commit -q -m "init"
git init -q --bare "$LORIGIN"
git -C "$LA" remote add origin "$LORIGIN"
git -C "$LA" push -q -u origin main 2>/dev/null

# feature_stem <slug> — the review stub's stem, read back from the manifest fence on
# main. feature-start.sh numbers it from the global sequence, so it is not knowable in
# advance; and close_fixture runs in a command substitution, so it cannot hand a variable
# back.
feature_stem() { fence "$LA/self/features/$1/README.md" 'd["plans"][0]'; }

# close_fixture <slug> <review session id> <plant review transcript: yes|no>
#               [<plant planning transcript: yes|no>, default yes] [<extra dirty paths>]
# Starts the feature, plants the unpriced review sidecar its manifest already lists,
# merges it, gives the capture one session to find, and closes it. Returns the close's
# combined output.
#
# The fourth argument withholds the one session the capture can claim, which is how E
# reaches the capture-refusal path with recovery having already rewritten a file. The
# fifth writes untracked files at those feature-relative paths in the WORKTREE before the
# close, which is how F puts a .usage.json outside any queue in front of stray_paths. The
# worktree rather than the primary: an untracked file in the primary trips the
# dirty-primary refusal in step 1, long before the stray test in steps 9 and 10 runs.
close_fixture() {
  local slug="$1" review_sid="$2" plant="$3"
  local plant_session="${4:-yes}" extra="${5:-}" rel
  local wt="$LA-$slug" fd
  # --session pins the planning session by id, which claims it "regardless of branch,
  # window or cwd". Without the pin this fixture rides a real boundary: `in_window`'s
  # `to` is EXCLUSIVE, feature-close.sh stamps `to` seconds after the transcript is
  # written, and roughly one run in six landed both in the same second — so the second
  # close (C10) refused "no session matched" at random. The window is not what this
  # test is about; capture-guard.sh owns it.
  ( cd "$TMP/close" && "$LA/feature-start.sh" --self "$slug" --no-gate --session "planning-$slug" >/dev/null 2>&1 )
  local stem
  fd="$wt/self/features/$slug"
  stem="$(fence "$fd/README.md" 'd["plans"][0]')"
  [[ -n "$stem" ]] || return 1
  # The review pass's own artifacts, as a green pass leaves them: the brief in complete/
  # and the sidecar beside it — here the one a stream with no result event produces.
  mkdir -p "$fd/review/complete"
  mv "$fd/review/incomplete/$stem.md" "$fd/review/complete/$stem.md"
  write_unpriced_usage_json "$fd/review/complete/$stem.usage.json" "$review_sid" opus
  git -C "$wt" add -A && git -C "$wt" commit -q -m "$slug: review pass"
  # The branch itself goes to origin, as plans/pr.sh pushes it before opening the PR:
  # feature-close.sh resolves `<slug>` locally or as `origin/<slug>`, and after a close
  # the remote ref is the only one left — which is what C10 re-closes against.
  git -C "$wt" push -q -u origin "$slug" 2>/dev/null
  git -C "$LA" merge -q --no-ff -m "Merge $slug" "$slug" && git -C "$LA" push -q origin main 2>/dev/null
  # One session launched in the worktree, on the branch, so the capture has something to
  # claim — a capture that matches nothing refuses and the close never reaches its report.
  if [[ "$plant_session" == "yes" ]]; then
    mkdir -p "$(project_dir "$wt")"
    session_line "planning-$slug" "$wt" "$slug" "msg-$slug" "$MODEL" "$(now_z)" 100 500 0 0 0 \
      > "$(project_dir "$wt")/planning-$slug.jsonl"
  fi
  if [[ "$plant" == "yes" ]]; then
    transcript_line "msg-r-$slug" "$MODEL" "$TS" 4000 2000 8000 0 0 > "$PROJ/$review_sid.jsonl"
  fi
  # Unquoted on purpose: the argument is a space-separated list of paths.
  for rel in $extra; do
    mkdir -p "$(dirname "$wt/self/features/$slug/$rel")"
    printf '{"plan":"a stranger","attempts":[]}\n' > "$wt/self/features/$slug/$rel"
  done
  ( cd "$TMP/close" && "$LA/feature-close.sh" --self "$slug" 2>&1 )
}

# C1-C5: the transcript survives, so recovery prices the review and the close commits it.
SLUG_OK="close-recovers"
out_ok="$(close_fixture "$SLUG_OK" "sess-close-recovers" yes)"; rc_ok=$?
STEM_OK="$(feature_stem "$SLUG_OK")"
FD_OK="$LA/self/features/$SLUG_OK"
U_OK="$FD_OK/review/complete/$STEM_OK.usage.json"
check "C1. the close exits 0 (got $rc_ok)" '[[ $rc_ok -eq 0 ]]'
ok_recovered="$(jf "$U_OK" 'd["attempts"][0].get("recovered_cost_usd")')"
check "C2. the review sidecar on main carries a recovered cost (got ${ok_recovered:-<absent>})" '[[ -n "$ok_recovered" && "$ok_recovered" != "None" ]]'
check "C3. the printed cost line is not a bare \$0.0000 review bucket" '! grep -q "review \$0.0000" <<<"$out_ok"'
commit_files="$(git -C "$LA" show --name-only --format= HEAD | tr "\n" " ")"
check "C4. the rewritten usage.json is inside the '$SLUG_OK: cost records' commit (got: $commit_files)" '[[ "$(git -C "$LA" log -1 --format=%s)" == "$SLUG_OK: cost records" ]] && grep -q "self/features/$SLUG_OK/review/complete/$STEM_OK.usage.json" <<<"$commit_files"'
check "C5. ... and it was never named as a stray path, which would have refused the close" '! grep -q "are not $SLUG_OK.s cost records" <<<"$out_ok" && [[ -z "$(git -C "$LA" status --porcelain)" ]]'

# C6-C9: the transcript is gone. Recovery fails, and that must be reported, not fatal —
# and the bucket must say so instead of printing a bare zero.
SLUG_GONE="close-unpriced"
out_gone="$(close_fixture "$SLUG_GONE" "sess-close-unpriced" no)"; rc_gone=$?
STEM_GONE="$(feature_stem "$SLUG_GONE")"
check "C6. a close whose recovery finds no transcript still exits 0 — reported, never fatal (got $rc_gone)" '[[ $rc_gone -eq 0 ]]'
check "C7. ... naming the plan whose transcript is gone" 'grep -q "$STEM_GONE" <<<"$out_gone" && grep -qi "unrecoverable\|no surviving transcript" <<<"$out_gone"'
check "C8. ... and the review bucket names the plan, why it is unpriced, and what recovery did" 'grep -q "unpriced: $STEM_GONE — no result event, transcript not found" <<<"$out_gone"'
check "C9. ... so the bare '\''review \$0.0000 (0.0%);'\'' the defect printed is gone" '! grep -q "review \$0.0000 (0.0%);" <<<"$out_gone"'

# C10-C12: --recapture over an already-closed feature. This is the repair path for the
# features whose zero is already committed, and the close must not need the worktree for
# it — C1 removed both the worktree and the local branch, leaving only `origin/<slug>`,
# which is exactly the state a merged-and-closed feature is left in.
TO_BEFORE="$(fence "$LA/self/features/$SLUG_OK/README.md" 'd["session_window"]["to"]')"
head_before="$(git -C "$LA" rev-parse HEAD)"
out_re="$( cd "$TMP/close" && "$LA/feature-close.sh" --self "$SLUG_OK" --recapture 2>&1 )"; rc_re=$?
check "C10. --recapture closes again with the worktree and local branch gone (got $rc_re)" '[[ $rc_re -eq 0 && ! -d "$LA-$SLUG_OK" ]] && ! git -C "$LA" show-ref --quiet "refs/heads/$SLUG_OK"'
check "C11. ... re-committing the cost records" '[[ "$(git -C "$LA" rev-parse HEAD)" != "$head_before" && "$(git -C "$LA" log -1 --format=%s)" == "$SLUG_OK: cost records" ]]'
TO_AFTER="$(fence "$LA/self/features/$SLUG_OK/README.md" 'd["session_window"]["to"]')"
check "C12. ... and leaving session_window.to where the first close put it (was $TO_BEFORE, now $TO_BEFORE)" '[[ -n "$TO_BEFORE" && "$TO_BEFORE" != "None" && "$TO_AFTER" == "$TO_BEFORE" ]]'

# C13-C17: the remote branch is gone too. C10 worked only because plans/pr.sh had pushed
# `<slug>` and the fixture's origin kept it; a forge with delete-on-merge takes that ref
# as soon as the PR merges, and then the repair path for an already-closed feature
# refuses "nothing to close" — self/BACKLOG.md's delete-on-merge entry. The merge commit
# is in main either way, so the ancestry the refusal exists to check is knowable without
# the branch. Both refs are removed here: the bare repo's, so a fetch cannot restore it,
# and the remote-tracking one, since the close's fetch does not prune.
git -C "$LORIGIN" update-ref -d "refs/heads/$SLUG_OK" 2>/dev/null
git -C "$LA" update-ref -d "refs/remotes/origin/$SLUG_OK" 2>/dev/null
check "C13. the fixture really has neither ref left" \
  '! git -C "$LA" show-ref --verify --quiet "refs/heads/$SLUG_OK" && ! git -C "$LA" show-ref --verify --quiet "refs/remotes/origin/$SLUG_OK"'

# The non-recapture path is unchanged: without --recapture there is nothing to repair
# and no reason to relax the refusal.
out_plain="$( cd "$TMP/close" && "$LA/feature-close.sh" --self "$SLUG_OK" 2>&1 )"; rc_plain=$?
check "C14. a plain close with both refs gone still refuses (got $rc_plain)" '[[ $rc_plain -ne 0 ]] && grep -q "nothing to close" <<<"$out_plain"'

head_before_re2="$(git -C "$LA" rev-parse HEAD)"
out_re2="$( cd "$TMP/close" && "$LA/feature-close.sh" --self "$SLUG_OK" --recapture 2>&1 )"; rc_re2=$?
check "C15. --recapture proceeds on the manifest and the start commit alone (got $rc_re2)" \
  '[[ $rc_re2 -eq 0 ]] && grep -q "no branch left" <<<"$out_re2"'
check "C16. ... re-committing the cost records" \
  '[[ "$(git -C "$LA" rev-parse HEAD)" != "$head_before_re2" && "$(git -C "$LA" log -1 --format=%s)" == "$SLUG_OK: cost records" ]]'
# And the refusal survives where it should: a slug with no branch AND no manifest on
# main is the case the message was written for, and --recapture must not swallow it.
out_none="$( cd "$TMP/close" && "$LA/feature-close.sh" --self never-started --recapture 2>&1 )"; rc_none=$?
check "C17. --recapture on a feature that was never started still refuses (got $rc_none)" \
  '[[ $rc_none -ne 0 ]] && grep -q "nothing to close" <<<"$out_none"'

# ── D. unpriced_reason's three branches, and the queue->bucket guard ─────────
# The reason string is what the close prints and the repair procedure is read off, and
# the function has three outcomes. Only one of them was asserted before this phase, and
# collapsing the other two into it — a simplification a later pass would read as
# obviously equivalent — kept the whole gate green while making the report claim a cause
# it does not know. Each assertion below pins its exact text, so no single return value
# can satisfy them all. Three of the four inputs are sidecars phase A's runner actually
# wrote; the fourth is the shape every sidecar on disk in both corpora has TODAY, since
# they all predate the field — and so the branch the documented repair runs.
cat > "$TMP/reason.py" <<'PYEOF'
import json
import sys

sys.path.insert(0, sys.argv[1])
import report

what = sys.argv[2]
if what == "reason":
    usage = json.load(open(sys.argv[3]))
    attempt = None
    if len(sys.argv) > 4 and sys.argv[4]:
        attempt = next(
            (a for a in usage.get("attempts") or [] if a.get("session_id") == sys.argv[4]),
            None,
        )
    print(report.unpriced_reason(usage, attempt))
elif what == "buckets":
    print(set(report.QUEUE_COST_BUCKETS) == report.QUEUE_DIRS)
PYEOF
# -B, like every python feature-close.sh runs: a __pycache__ left in the primary is
# untracked, and the next close refuses on a dirty primary.
R() { python3 -B "$TMP/reason.py" "$LA/analysis" "$@" 2>&1; }

# The pre-field shape: no `result_event` at all, which is not the same as "missing".
PREFIELD="$TMP/prefield.usage.json"
python3 - "$PREFIELD" <<'PYEOF'
import json
import sys
json.dump(
    {
        "plan": "01-review-opus", "model": "opus", "outcome": "complete",
        "session_id": "sess-prefield", "total_cost_usd": None,
        "attempts": [{"session_id": "sess-prefield", "outcome": "complete",
                      "total_cost_usd": None}],
    },
    open(sys.argv[1], "w"),
)
PYEOF
d1="$(R reason "$PREFIELD")"
check "D1. no result_event at all reads 'no cost reported, cause not recorded' (got $d1)" '[[ "$d1" == "no cost reported, cause not recorded" ]]'
d2="$(R reason "$U_MISSING_KEPT")"
check "D2. result_event: missing on a complete run reads 'no result event' (got $d2)" '[[ "$d2" == "no result event" ]]'
d3="$(R reason "$U_KILLED" sess-killed)"
check "D3. the runner-harvested killed attempt reads 'killed' (got $d3)" '[[ "$d3" == "killed" ]]'
d4="$(R reason "$U_FAILED_KEPT")"
check "D4. a failed run with no result event reads 'no result event' — outcome is not the pricing fact (got $d4)" '[[ "$d4" == "no result event" ]]'
d5="$(R buckets)"
check "D5. QUEUE_COST_BUCKETS covers exactly QUEUE_DIRS (got $d5)" '[[ "$d5" == "True" ]]'
# Not vacuous: the guard must be enforced at import, not merely true today. A copy with a
# fourth queue in QUEUE_DIRS and nothing added to the dict must refuse to import.
mkdir -p "$TMP/drift"
cp "$LA/analysis"/*.py "$TMP/drift/"
sed -i.bak 's/^QUEUE_DIRS = {"auto", "verify", "review"}$/QUEUE_DIRS = {"auto", "verify", "review", "escalate"}/' "$TMP/drift/report.py"
drift_out="$(python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); import report" "$TMP/drift" 2>&1)"; drift_rc=$?
check "D6. ... and a queue added to QUEUE_DIRS but not to the dict fails at import (got $drift_rc)" '[[ $drift_rc -ne 0 ]] && grep -q "QUEUE_COST_BUCKETS" <<<"$drift_out" && grep -q "escalate" <<<"$drift_out"'

# ── E. rollback_recovery ─────────────────────────────────────────────────────
# The mirror of feature-lifecycle.sh's C5f, which pins rollback_carry the same way. The
# capture refuses AFTER recovery has already rewritten a sidecar in the primary; if the
# rollback regresses, the primary is left dirty with files this script wrote and step 1
# of the NEXT close refuses on that dirt — the two-close cascade the step-6 comment says
# the rollback exists to prevent. Withholding the planning transcript is what makes the
# capture refuse; planting the review one is what gives recovery something to undo.
SLUG_ROLL="close-rolls-back"
out_roll="$(close_fixture "$SLUG_ROLL" "sess-close-rolls-back" yes no)"; rc_roll=$?
STEM_ROLL="$(feature_stem "$SLUG_ROLL")"
U_ROLL="$LA/self/features/$SLUG_ROLL/review/complete/$STEM_ROLL.usage.json"
check "E1. a close whose capture refuses exits non-zero (got $rc_roll)" '[[ $rc_roll -ne 0 ]] && grep -q "capture refused" <<<"$out_roll"'
check "E2. ... and recovery really had something to undo first" 'grep -q "1 attempt(s) recovered" <<<"$out_roll" && grep -q "rolled back the 1 recovered sidecar" <<<"$out_roll"'
roll_recovered="$(jf "$U_ROLL" 'd["attempts"][0].get("recovered_cost_usd")')"
check "E3. ... the recovered figure is gone from the sidecar again (got ${roll_recovered:-<absent>})" '[[ "$roll_recovered" == "None" ]]'
check "E4. ... the primary is clean, so the next close is not blocked by this one's dirt" '[[ -z "$(git -C "$LA" status --porcelain)" ]]'
out_roll2="$(cd "$TMP/close" && "$LA/feature-close.sh" --self "$SLUG_ROLL" 2>&1)"; rc_roll2=$?
check "E5. ... and the re-run refuses for the same reason, not for a dirty primary (got $rc_roll2)" '[[ $rc_roll2 -ne 0 ]] && ! grep -qi "is dirty" <<<"$out_roll2" && grep -q "capture refused" <<<"$out_roll2"'

# ── F. a .usage.json outside a queue is a stranger ───────────────────────────
# is_cost_usage_path matches <queue>/<state>/…, with both names read from the runner's own
# sets, so a sidecar a human left somewhere else under the feature directory is not the
# harness's to commit or to discard. Before it, `*/*.usage.json` asked only for SOME
# directory above the file, so `notes/left-behind.usage.json` qualified.
# Asserted at the teardown, the other caller of stray_paths, because that is where a
# fixture can reach it: an untracked file in the PRIMARY trips step 1's dirty refusal
# before step 9 ever runs, while the same file in the worktree is exactly the question
# step 10 asks — are these leftovers the harness's own, or somebody's work?
SLUG_STRAY="close-stray-usage"
out_stray="$(close_fixture "$SLUG_STRAY" "sess-close-stray" yes yes "notes/left-behind.usage.json")"; rc_stray=$?
check "F1. a worktree holding a .usage.json outside a queue is kept, not force-removed (got $rc_stray)" '[[ $rc_stray -eq 0 && -d "$LA-$SLUG_STRAY" ]]'
check "F2. ... and the close says so instead of discarding it" 'grep -q "uncommitted or untracked files that are not" <<<"$out_stray"'
# The complement, so F1 cannot pass by the close simply never force-removing anything: the
# same file INSIDE a queue is the harness's own, and the worktree comes away.
SLUG_OWNED="close-owned-usage"
out_owned="$(close_fixture "$SLUG_OWNED" "sess-close-owned" yes yes "review/complete/99-extra-sonnet.usage.json")"; rc_owned=$?
check "F3. ... while one inside a queue is the harness's own and the worktree comes away (got $rc_owned)" '[[ $rc_owned -eq 0 && ! -d "$LA-$SLUG_OWNED" ]] && grep -q "discarding uncommitted records already carried home" <<<"$out_owned"'

echo
if (( fails > 0 )); then echo "recover-at-close: $fails assertion(s) FAILED"; exit 1; fi
echo "recover-at-close: all assertions passed"
