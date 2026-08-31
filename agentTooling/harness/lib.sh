#!/usr/bin/env bash
# Shared machinery for the experiment harness: sourced by harness/run.sh and by every
# method's run.sh. Not run directly.
#
# One rule governs this file: anything a method or a stage could plausibly implement
# twice lives here once. In particular EVERY `claude` invocation in the harness goes
# through harness_claude, which honours HARNESS_CLAUDE_BIN — that single seam is what
# lets harness/tests/smoke.sh drive the whole pipeline with a fake binary, no network
# and no money.
#
# Sourcing it requires nothing to be set first. It sources agentTooling's own
# plan-runner-lib.sh for the usage-limit detector (see harness_stopped_on_usage_limit)
# rather than writing a second one.

# ── Paths ────────────────────────────────────────────────────────────────────
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_TOOLING_DIR="$(cd "$HARNESS_DIR/.." && pwd)"
# Same derivation the runners use: the consuming repo is the parent of agentTooling/.
# --consumer overrides it for development (harness/run.sh sets CONSUMER_ROOT).
DEFAULT_CONSUMER_ROOT="$(cd "$AGENT_TOOLING_DIR/.." && pwd)"

HARNESS_TEMPLATES_DIR="$HARNESS_DIR/templates"
HARNESS_METHODS_DIR="$HARNESS_DIR/methods"

# ── The two binaries the harness shells out to, both seams ───────────────────
# HARNESS_CLAUDE_BIN is the model seam (smoke test: a fake `claude`).
# HARNESS_GH_BIN is the forge seam — the harness only ever asks it to *read* whether a
# PR exists, so a fake that answers from a file is a faithful stand-in offline.
HARNESS_CLAUDE_BIN="${HARNESS_CLAUDE_BIN:-claude}"
HARNESS_GH_BIN="${HARNESS_GH_BIN:-gh}"

# ── Exit-code convention, copied from plan-runner-lib.sh ─────────────────────
# A method's run.sh reports its outcome with these and nothing else.
METHOD_OK_RC=0          # PR open
METHOD_FAILED_RC=1      # work failure — do not retry
METHOD_USAGE_LIMIT_RC=2 # usage limit — resumable

# ── Model and budget defaults ────────────────────────────────────────────────
# The harness never hard-codes a price (analysis/pricing.py owns rates); these are
# circuit breakers on a single pass, in the shape run-verify.sh / run-review.sh use.
HARNESS_MODEL="${HARNESS_MODEL:-opus}"
REVIEW_BUDGET_USD="${REVIEW_BUDGET_USD:-7.00}"
REWORK_BUDGET_USD="${REWORK_BUDGET_USD:-10.00}"

# ── Waiting out a usage limit ────────────────────────────────────────────────
# plan-runner-lib.sh detects a usage-limit stop but never parses a reset time — it
# leaves the plan queued and lets the next run resume. The harness has no next run to
# wait for, so it parses what the result event happens to carry and otherwise waits a
# fixed interval before its one retry.
USAGE_RESET_DEFAULT_WAIT_S=900     # 15 min when the message names no reset time
USAGE_RESET_MAX_WAIT_S=21600       # 6 h ceiling on any parsed reset time
USAGE_RESET_SLACK_S=60             # wake up this long after the stated reset

# ── Gate ─────────────────────────────────────────────────────────────────────
GATE_TAIL_LINES=20                 # how many trailing gate lines `gate.green` is sought in
GATE_REPORT_RELPATH="plans/gate-report.txt"
# What counts as a "test count" line in the gate report, for the ledger's
# gate_counts_* fields. Deliberately loose: the row records whatever the gate prints.
GATE_COUNT_RE='[0-9]+ (passed|failed|skipped|error|errors|deselected|xfailed)|Tests +[0-9]+|[0-9]+ (test|spec)s? (passed|failed)'
GATE_COUNTS_JOIN=' | '

# ── Findings ─────────────────────────────────────────────────────────────────
FINDINGS_RELDIR="review"
FINDINGS_NAME="findings.md"
FINDINGS_ESCALATED_RE='^escalated:[[:space:]]*([0-9]+)'
FINDINGS_FIXED_RE='^fixed:[[:space:]]*([0-9]+)'

# ── Stage names, in order ────────────────────────────────────────────────────
# `brief` is generated, not resumable on its own: --from method re-generates it, since
# it is a pure function of fixture + method and costs nothing.
HARNESS_STAGES="setup brief method review rework accept capture record"

# ── Reuse, never re-implement: the runners' usage-limit detector ─────────────
# plan-runner-lib.sh reads two variables at source time; give them values that make
# sourcing inert (nothing here calls run_all, and no trap is installed at source time).
PLAN_KIND="${PLAN_KIND:-harness stage}"
SUMMARY_TITLE="${SUMMARY_TITLE:-Harness}"
# shellcheck source=../plan-runner-lib.sh
source "$AGENT_TOOLING_DIR/plan-runner-lib.sh"

# ── Small helpers ────────────────────────────────────────────────────────────
harness_log() { printf '=== harness: %s\n' "$*"; }
harness_warn() { printf 'WARN: %s\n' "$*" >&2; }
harness_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Every instant the harness records is UTC with a Z, the convention analysis/README.md
# makes load-bearing: a naive bound in a session_window is read as UTC, and a local one
# pasted bare hands sessions to the wrong feature.
harness_utc_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

HARNESS_REQUIRED_TOOLS="${HARNESS_REQUIRED_TOOLS:-claude jq git python3}"

harness_require_tools() {
  local missing=() tool
  for tool in $HARNESS_REQUIRED_TOOLS; do
    [[ "$tool" == claude ]] && tool="$HARNESS_CLAUDE_BIN"
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if (( ${#missing[@]} > 0 )); then
    harness_die "missing required tool(s): ${missing[*]}"
  fi
}

# ── Naming (harness/SPEC.md §4) ──────────────────────────────────────────────
# Branch: <stem><Method><n>, bare camelCase, method capitalised, n omitted at repeats=1.
# Never a user/ prefix: capture_planning.py matches `branches` literally against each
# session's gitBranch, and a mismatch silently reports $0.00.
harness_branch_name() {
  local stem="$1" method="$2" repeat="$3" repeats="$4"
  local head rest
  head="$(printf '%s' "${method:0:1}" | tr '[:lower:]' '[:upper:]')"
  rest="${method:1}"
  if (( repeats > 1 )); then
    printf '%s%s%s%s' "$stem" "$head" "$rest" "$repeat"
  else
    printf '%s%s%s' "$stem" "$head" "$rest"
  fi
}

# Slug: the branch in kebab-case — exportStoreDirect -> export-store-direct,
# exportStorePlans2 -> export-store-plans-2.
harness_slug_of_branch() {
  printf '%s' "$1" \
    | sed -e 's/\([A-Z]\)/-\1/g' -e 's/\([0-9][0-9]*\)/-\1/g' -e 's/--*/-/g' -e 's/^-//' \
    | tr '[:upper:]' '[:lower:]'
}

harness_worktree_path() { printf '%s-%s' "$1" "$2"; }        # <repo path>-<branch>
harness_spec_worktree_path() { printf '%s-fx-%s' "$1" "$2"; } # <spec repo>-fx-<fixture>

# ── JSON readers ─────────────────────────────────────────────────────────────
harness_json() { jq -r "$2 // empty" "$1"; }
harness_json_raw() { jq -c "$2" "$1"; }

# ── The one claude seam ──────────────────────────────────────────────────────
# harness_claude <result-json-out> <prompt-file> <cwd> [extra claude flags...]
#
# --output-format json, so the result object carries session_id and total_cost_usd
# (SPEC.md §8). stdout is the JSON object and nothing else; stderr stays on the
# terminal. The exit code is claude's own: 1 covers a usage limit, a budget stop and a
# genuine failure alike, which is why the caller asks harness_stopped_on_usage_limit
# rather than reading the code.
harness_claude() {
  local out="$1" prompt_file="$2" cwd="$3"
  shift 3
  # The prompt goes in on stdin, never as a trailing positional: `--allowedTools` is
  # variadic, so a prompt placed after it is read as another tool name and `claude -p`
  # fails with "Input must be provided either through stdin or as a prompt argument"
  # (the first real replayF2Direct run died exactly there; the runners avoid it only
  # because another flag happens to follow their tool args).
  ( cd "$cwd" && "$HARNESS_CLAUDE_BIN" -p --output-format json "$@" < "$prompt_file" ) > "$out"
  local rc=$?
  return "$rc"
}

# stream_shows_usage_limit lives in plan-runner-lib.sh and matches the final result
# event's message text. A --output-format json result IS that event, so the same
# detector reads it unchanged — there is exactly one usage-limit regex in this repo.
harness_stopped_on_usage_limit() { stream_shows_usage_limit "$1"; }
harness_stopped_on_budget() { stream_shows_budget_exhausted "$1"; }

harness_claude_cost() { jq -r '(.total_cost_usd // 0) | tostring' "$1" 2>/dev/null || echo 0; }
harness_claude_session() { jq -r '.session_id // empty' "$1" 2>/dev/null || true; }
harness_claude_text() { jq -r '.result // empty' "$1" 2>/dev/null || true; }

# The reset instant a usage-limit result names, as epoch seconds, or nothing. Claude
# reports it either as a bare epoch ("limit reached|1756500000") or not at all.
harness_usage_reset_epoch() {
  jq -r '(.result // .error // .subtype // "" | tostring)' "$1" 2>/dev/null \
    | grep -oE '\b1[0-9]{9}\b' | head -1
}

harness_wait_for_usage_reset() {
  local result_file="$1" now epoch wait
  now="$(date -u '+%s')"
  epoch="$(harness_usage_reset_epoch "$result_file")"
  if [[ -n "$epoch" ]] && (( epoch > now )); then
    wait=$(( epoch - now + USAGE_RESET_SLACK_S ))
  else
    wait="$USAGE_RESET_DEFAULT_WAIT_S"
  fi
  (( wait > USAGE_RESET_MAX_WAIT_S )) && wait="$USAGE_RESET_MAX_WAIT_S"
  harness_log "usage limit reached — waiting ${wait}s for the reset, then retrying once"
  sleep "$wait"
}

# ── Templates ────────────────────────────────────────────────────────────────
# harness_fill_template <template file> — writes the filled text to stdout.
# Every placeholder is read from the environment; a template naming one that is unset
# is a bug, so the fill fails loudly rather than shipping a literal @@NAME@@ to a model.
# Multi-line values (facts, isolation) are ordinary bash variables: ${x//a/b} does not
# care about newlines.
harness_fill_template() {
  local file="$1" text name value missing
  text="$(cat "$file")"
  # The file-valued placeholders go in FIRST — isolation.md, facts.md, review-brief.md
  # and findings.md all carry scalar placeholders of their own (`@@SPEC_TREE@@`,
  # `@@GATE_MINUTES@@`, `@@TREE@@`), and only a pass that runs after they are inserted
  # can resolve them. Insert last and they ship to a model verbatim.
  text="${text//@@ISOLATION@@/${HARNESS_ISOLATION-}}"
  for name in FACTS REVIEW_BRIEF FINDINGS_TEXT \
              TREE BRANCH BASE SLUG SPEC_TREE SPEC_PATH SPEC_SECTIONS \
              GATE_COMMAND GATE_MINUTES FIXTURE SIBLINGS EXPERIMENTS_DIR \
              AGENT_TOOLING FINDINGS BRIEF; do
    eval "value=\${HARNESS_$name-}"
    text="${text//@@${name}@@/$value}"
  done
  missing="$(printf '%s' "$text" | grep -oE '@@[A-Z_]+@@' | sort -u | tr '\n' ' ')"
  if [[ -n "$missing" ]]; then
    harness_die "unfilled placeholder(s) in $file: $missing"
  fi
  printf '%s\n' "$text"
}

# The isolation paragraph names every path the delegate must not touch: every sibling
# worktree of the fixture repo, the experiments directory, and agentTooling.
harness_build_isolation() {
  local repo="$1" tree="$2"
  local siblings
  siblings="$(git -C "$repo" worktree list --porcelain \
              | awk '/^worktree /{print $2}' \
              | grep -v -x "$tree" \
              | sed 's/^/  - /')"
  [[ -n "$siblings" ]] || siblings="  - (none)"
  HARNESS_SIBLINGS="$siblings"
  HARNESS_TREE="$tree"
  HARNESS_ISOLATION="$(cat "$HARNESS_TEMPLATES_DIR/isolation.md")"
}

# ── Manifests ────────────────────────────────────────────────────────────────
# The skeleton capture_planning.py reads: it parses the LAST ```json fence in the
# feature README. `branches` must match `git branch --show-current` verbatim, and every
# session_window bound ends with Z.
harness_write_manifest() {
  local tree="$1" slug="$2" branch="$3" from="$4" title="$5"
  local dir="$tree/plans/features/$slug"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MANIFEST
# $title

Written by \`agentTooling/harness/run.sh\`. One arm of an experiment: this directory is
the feature's cost record, and its \`session_window\` is the harness's, not a human's.
Do not widen the window or add branches — \`capture_planning.py\` matches \`branches\`
literally against each session's \`gitBranch\`, and two open windows on one branch
double-count the same session.

## Plans

Populated by the method. A method with no plans leaves the array empty.

## Machine-readable

\`\`\`json
{
  "slug": "$slug",
  "plans": [],
  "branches": ["$branch"],
  "session_window": {"from": "$from", "to": null},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "subagents": []
}
\`\`\`
MANIFEST
}

# Close the window at PR-open (or at the end of a review / rework pass). Fails if the
# bound was already set: a second close would move a boundary another manifest chains to.
harness_close_manifest_window() {
  local tree="$1" slug="$2" to="$3"
  local readme="$tree/plans/features/$slug/README.md"
  [[ -f "$readme" ]] || { harness_warn "no manifest at $readme"; return 1; }
  python3 - "$readme" "$to" <<'PY'
import re, sys
path, to = sys.argv[1], sys.argv[2]
text = open(path).read()
new, n = re.subn(r'("to"\s*:\s*)null', r'\1"%s"' % to, text, count=1)
if n != 1:
    sys.stderr.write("ERROR: no open session_window.to in %s\n" % path)
    sys.exit(1)
open(path, "w").write(new)
PY
}

# ── Gate ─────────────────────────────────────────────────────────────────────
# Runs the fixture's gate command from the tree, logging OUTSIDE the tree: pr.sh commits
# with `git add -A`, so a log left in the working tree lands in the diff a human reviews.
harness_run_gate() {
  local tree="$1" command="$2" log="$3"
  mkdir -p "$(dirname "$log")"
  ( cd "$tree" && eval "$command" ) > "$log" 2>&1
  return $?
}

harness_gate_is_green() {
  local log="$1" green="$2"
  tail -n "$GATE_TAIL_LINES" "$log" 2>/dev/null | grep -qF -- "$green"
}

# Whatever the gate prints as counts, as one string for the ledger row.
harness_gate_counts() {
  # Two statements, not one `local a= b=$a`: bash expands every word of a command
  # before the builtin runs, so a second assignment cannot read the first.
  local tree="$1"
  local report="$tree/$GATE_REPORT_RELPATH" counts
  [[ -f "$report" ]] || { printf ''; return 0; }
  counts="$(grep -hoE "$GATE_COUNT_RE" "$report" 2>/dev/null | awk '!seen[$0]++' | paste -sd'|' - )"
  printf '%s' "${counts//|/$GATE_COUNTS_JOIN}"
}

# ── Findings ─────────────────────────────────────────────────────────────────
harness_findings_path() { printf '%s/plans/features/%s/%s/%s' "$1" "$2" "$FINDINGS_RELDIR" "$FINDINGS_NAME"; }

# Counts from the findings header, falling back to counting `- id:` rows under the
# heading — a review that wrote the list but not the tally still gets its rework.
harness_findings_count() {
  local file="$1" which="$2" re n
  [[ -f "$file" ]] || { printf '0'; return 0; }
  if [[ "$which" == escalated ]]; then re="$FINDINGS_ESCALATED_RE"; else re="$FINDINGS_FIXED_RE"; fi
  n="$(grep -oE "$re" "$file" | grep -oE '[0-9]+' | head -1)"
  if [[ -z "$n" ]]; then
    n="$(awk -v want="$which" '
      /^## +[Ee]scalated/ {sec="escalated"; next}
      /^## +[Ff]ixed/     {sec="fixed"; next}
      /^## /              {sec=""; next}
      /^- +id:/           {if (sec == want) c++}
      END {print c+0}' "$file")"
  fi
  printf '%s' "${n:-0}"
}

# ── git ──────────────────────────────────────────────────────────────────────
harness_has_remote() { [[ -n "$(git -C "$1" remote 2>/dev/null)" ]]; }

harness_commit_all() {
  local tree="$1" message="$2"
  ( cd "$tree" && git add -A && git commit -q -m "$message" ) || return 1
}

harness_push() {
  local tree="$1" branch="$2"
  harness_has_remote "$tree" || { harness_log "no remote in $tree — not pushing"; return 0; }
  ( cd "$tree" && git push -q -u origin "$branch" ) || { harness_warn "push of $branch failed"; return 1; }
}

# The PR the method was asked to open. Read-only, through the forge seam.
harness_pr_url() {
  local tree="$1" branch="$2"
  command -v "$HARNESS_GH_BIN" >/dev/null 2>&1 || { printf ''; return 0; }
  ( cd "$tree" && "$HARNESS_GH_BIN" pr view "$branch" --json url --jq .url 2>/dev/null ) || printf ''
}

# ── State file ───────────────────────────────────────────────────────────────
harness_state_init() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  [[ -f "$file" ]] || echo '{}' > "$file"
}

# harness_state_set <file> <key> <json value>
harness_state_set() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$file.tmp"
  jq --arg k "$key" --argjson v "$value" '.[$k] = $v' "$file" > "$tmp" && mv "$tmp" "$file"
}

harness_state_set_str() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$file.tmp"
  jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$file" > "$tmp" && mv "$tmp" "$file"
}

harness_state_get() { jq -r --arg k "$2" '.[$k] // empty' "$1" 2>/dev/null || true; }

# One row per stage in the state file's `stages` object: when it started, when it
# ended, and how it went.
harness_state_stage() {
  local file="$1" stage="$2" field="$3" value="$4" tmp
  tmp="$file.tmp"
  jq --arg s "$stage" --arg f "$field" --arg v "$value" \
     '.stages = ((.stages // {}) | .[$s] = ((.[$s] // {}) | .[$f] = $v))' "$file" > "$tmp" && mv "$tmp" "$file"
}

harness_state_intervention() {
  local file="$1" what="$2" tmp
  tmp="$file.tmp"
  jq --arg t "$(harness_utc_now)" --arg w "$what" \
     '.interventions = ((.interventions // []) + [{t: $t, what: $w}])' "$file" > "$tmp" && mv "$tmp" "$file"
}

harness_version() { git -C "$AGENT_TOOLING_DIR" rev-parse HEAD 2>/dev/null || echo unknown; }
