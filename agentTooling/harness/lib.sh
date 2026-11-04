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

# ── The two programs the harness shells out to, both seams ───────────────────
# HARNESS_CLAUDE_BIN is the model seam (smoke test: a fake `claude`).
# HARNESS_FORGE_BIN is the forge seam: a `forge.sh` (agentTooling's adapter, `pr-find`
# and `pr-open` over `gh api` REST — the one path that works on a laptop AND in a Claude
# Code cloud container, whose proxy refuses `gh pr view` / `gh pr create`). Unset, the
# harness uses the vendored copy inside whichever checkout it is asking about
# (harness_forge_for), since forge.sh reads the origin of the checkout it lives in. The
# smoke test sets it to a fake that answers from a per-branch file.
HARNESS_CLAUDE_BIN="${HARNESS_CLAUDE_BIN:-claude}"
HARNESS_FORGE_BIN="${HARNESS_FORGE_BIN:-}"
DRIVER_FORGE="$AGENT_TOOLING_DIR/forge.sh"
# The base every arm's PR targets, and what the harness tells the forge.
HARNESS_PR_BASE="${HARNESS_PR_BASE:-main}"

# ── The measured repository is the consumer ──────────────────────────────────
# The owner's rule: every experiment runs from, and lives on, the repository it measures.
# So the repository a fixture or a program builds in is CONSUMER_ROOT — never resolved,
# searched for or cloned — and the harness that drives it is that repository's own vendored
# copy (harness_require_own_driver). A `repo` block that names another repository is
# refused (harness_check_measured_repo). Two inputs stay outside, read-only: an arm's
# pinned agentTooling (HARNESS_AGENT_TOOLING_URL) and a spec that lives in another
# repository (`spec.url`); only those go through harness_resolve_repo below.
# Test seam, never an operator option: the smoke test drives throwaway consumers from
# agentTooling's own checkout and sets this to 1 to be allowed to.
HARNESS_TEST_EXTERNAL_DRIVER="${HARNESS_TEST_EXTERNAL_DRIVER:-0}"
# The consumer's remote that names it, and the remote a fixture builds against by default.
CONSUMER_IDENTITY_REMOTE="origin"
HARNESS_FIXTURES_RELDIR="plans/experiments/fixtures"

# ── Repositories by URL, resolved per machine ────────────────────────────────
# Only the two EXTERNAL inputs name a repository by URL — `spec.url` (a spec that lives in
# another repository) and the agentTooling an arm is pinned to — never by a path:
# a path is one machine's (the first fixtures carried /Users/<owner>/dev/…, which no
# cloud container has). harness_resolve_repo turns a URL into a checkout on THIS machine,
# in this order (the first that answers wins):
#   1. HARNESS_REPO_DIR_<KEY>=<path> in the environment, KEY the repository's name in
#      upper case with anything but [A-Z0-9] as `_` (vinylCatalogue → VINYLCATALOGUE);
#   2. a URL that is itself a local git checkout (a path) — that checkout;
#   3. the fixture's optional path hint (`spec.repo`), when it exists here;
#   4. a checkout under one of HARNESS_REPO_ROOTS (colon-separated; default: the directory
#      holding the consuming repo, which is ~/dev on a laptop and /home/user in a cloud
#      container) whose `origin` names the same repository — owner/repo compared
#      case-insensitively, `.git` dropped, so a lowercase cloud clone matches;
#   5. a fresh clone into the first root, named after the repository. In a cloud
#      container that needs the repository attached to the session (`add_repo`); a
#      failed clone there says so, as update.sh does for its fetch.
# agentTooling itself — the upstream an arm is pinned to — is a repository like any other,
# at HARNESS_AGENT_TOOLING_URL (update.sh's DEFAULT_REMOTE; the four copies of that string
# move together).
HARNESS_AGENT_TOOLING_URL="${HARNESS_AGENT_TOOLING_URL:-https://github.com/ssdesai/agentTooling.git}"
HARNESS_REPO_ROOTS="${HARNESS_REPO_ROOTS:-}"
HARNESS_REPO_DIR_PREFIX="HARNESS_REPO_DIR_"
REPO_GIT_SUFFIX=".git"
# What a cloud container's git proxy answers for a repository not attached to the session
# (update.sh's AUTH_FAILURE_RE, the same string).
REPO_AUTH_FAILURE_RE="could not read Username|Authentication failed|returned error: 40[13]|Repository not found"
REPO_ATTACH_TOOL="add_repo"

# ── Pinning an arm's vendored agentTooling ───────────────────────────────────
# An experiment may run its cells under several agentTooling versions ("arms"):
# `agent_tooling: {<label>: <full sha>}` in experiment.json. The setup stage replaces the
# worktree's `agentTooling/` with that upstream commit's tree, runs the pinned copy's
# sync-plans.sh, and commits — the recipe EXPERIMENTS.md → "Setting up the arms" gave by
# hand, titled so the commit cannot be merged by accident.
HARNESS_PIN_SUBJECT_PREFIX="EXPERIMENT ARM (revert before merge): pin agentTooling to upstream"
AGENT_TOOLING_RELPATH="agentTooling"
SYNC_PLANS_RELPATH="agentTooling/sync-plans.sh"
PIN_SHORT_SHA_LEN=7
# An arm label is bare lower-case letters: it is capitalised into the branch name
# (`exportStoreDirectAfter2`) and must not run into the repeat index.
HARNESS_ARM_LABEL_RE='^[a-z]+$'
# Arm kinds: what an experiment's arms vary — one kind per experiment.
HARNESS_ARM_KIND_AGENT_TOOLING="agent_tooling"   # experiment.json key agent_tooling
HARNESS_ARM_KIND_BASE="base"                     # experiment.json key base_arms
HARNESS_BASE_ARMS_KEY="base_arms"
HARNESS_ARM_KINDS_EXCLUSIVE_MSG="an experiment's arms vary one thing — the agentTooling version (agent_tooling, --agent-tooling) or the measured repository's commit (base_arms, --base-arms) — never both"
HARNESS_BASE_ARMS_NO_PROGRAMS_MSG="base_arms (--base-arms) does not combine with programs (--programs): a program pins its own base"
HARNESS_BASE_ARM_REPO_RULE="an experiment runs from, and lives on, the repository it measures (harness/EXPERIMENTS.md): push the commit there and name a ref that resolves in its checkout"

# ── Exit-code convention, copied from plan-runner-lib.sh ─────────────────────
# A method's run.sh reports its outcome with these and nothing else.
METHOD_OK_RC=0          # PR open
METHOD_FAILED_RC=1      # work failure — do not retry
METHOD_USAGE_LIMIT_RC=2 # usage limit — resumable

# ── Model and budget defaults ────────────────────────────────────────────────
# The harness never hard-codes a price (analysis/pricing.py owns rates); these are
# circuit breakers on a single pass, in the shape run-verify.sh / run-review.sh use.
HARNESS_MODEL="${HARNESS_MODEL:-opus}"
# Reasoning effort, the claude CLI's `--effort <level>`. Empty means the CLI's own
# default and adds no flag; otherwise one of the levels below (checked once, after
# harness_die is defined). harness_claude applies it to every call.
HARNESS_EFFORT="${HARNESS_EFFORT:-}"
HARNESS_EFFORT_LEVELS="low medium high xhigh max"
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

# ── Program cells ────────────────────────────────────────────────────────────
# A program cell hands an ordered list of fixtures' features to one orchestrator session
# (harness/README.md → "Program cells"). Its stage names replace `method` with `loop` and
# add `collect`; `orchestrator` is a reserved method name, so no methods/orchestrator/.
HARNESS_PROGRAM_METHOD="orchestrator"
HARNESS_PROGRAM_STAGES="setup brief loop collect review rework accept capture record"
HARNESS_PROGRAMS_RELDIR="plans/experiments/programs"
HARNESS_PROGRAM_FILE="program.json"
# The first line of every feature PR body in a program cell, so a reader of the forge sees
# at once that the PR belongs to an experiment.
HARNESS_PR_FIRST_LINE="one arm of an experiment — do not merge until it picks a winner"
# What an arm's pinned agentTooling must carry to run a program cell (paths inside it).
HARNESS_PROGRAM_FLOOR_FILES="orchestration-start.sh templates/plans/ORCHESTRATOR_BRIEF.md"
# The tools an implementer run is allowed: it may spawn subagents, unlike a subagent itself.
PROGRAM_IMPLEMENTER_TOOLS="Bash Agent Task"
# program.json rules
PROGRAM_BASE_RE='^[0-9a-f]{40}$'
PROGRAM_STEM_RE='^[a-z][A-Za-z0-9]*$'
PROGRAM_RESERVED_METHODS="null $HARNESS_PROGRAM_METHOD"
PROGRAM_CHOICE_METHODS="direct plans hand"
PROGRAM_GATE_FIELDS="command green minutes"
PROGRAM_UUID_RELPATH="/proc/sys/kernel/random/uuid"

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

# HARNESS_EFFORT is validated here, the first point the harness can refuse: empty is
# allowed, anything else must be one of HARNESS_EFFORT_LEVELS.
if [[ -n "$HARNESS_EFFORT" && " $HARNESS_EFFORT_LEVELS " != *" $HARNESS_EFFORT "* ]]; then
  harness_die "HARNESS_EFFORT='$HARNESS_EFFORT' is not an effort level (one of: $HARNESS_EFFORT_LEVELS)"
fi

# harness_effort_dry — " --effort <level>" for a dry-run line, nothing when unset.
harness_effort_dry() { [[ -z "$HARNESS_EFFORT" ]] || printf ' --effort %s' "$HARNESS_EFFORT"; }

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
# Branch: <stem><Method><Arm><n>, bare camelCase, method and arm label capitalised, the
# arm omitted when the experiment pins no agentTooling version, n omitted at repeats=1.
# Never a user/ prefix: capture_planning.py matches `branches` literally against each
# session's gitBranch, and a mismatch silently reports $0.00.
#
# A hyphenated name (`direct-bare`, `direct-selfreview`: methods/README.md) is camelCased,
# each hyphen-separated part capitalised and the hyphens dropped, so the branch stays bare
# camelCase (`exportStoreDirectBare`). Only the branch changes: the row's `method` stays the
# directory name. Plain `tr` and `${1:0:1}`, not `${part^}`: macOS ships bash 3.2.
harness_capitalise() {
  local word out="" rest="$1"
  while [[ "$rest" == *-* ]]; do
    word="${rest%%-*}"
    rest="${rest#*-}"
    out+="$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
  done
  printf '%s%s%s' "$out" "$(printf '%s' "${rest:0:1}" | tr '[:lower:]' '[:upper:]')" "${rest:1}"
}

harness_branch_name() {
  local stem="$1" method="$2" repeat="$3" repeats="$4" label="${5:-}"
  local name
  name="$stem$(harness_capitalise "$method")"
  [[ -z "$label" ]] || name+="$(harness_capitalise "$label")"
  if (( repeats > 1 )); then
    printf '%s%s' "$name" "$repeat"
  else
    printf '%s' "$name"
  fi
}

# harness_experiment_arm_kind <experiment.json> — what its arms vary: agent_tooling, base,
# or nothing (no arms). Both keys at once dies: one experiment varies one thing.
harness_experiment_arm_kind() {
  local has_at has_base
  has_at="$(jq -r --arg k "$HARNESS_ARM_KIND_AGENT_TOOLING" 'has($k)' "$1")" || harness_die "cannot read $1"
  has_base="$(jq -r --arg k "$HARNESS_BASE_ARMS_KEY" 'has($k)' "$1")" || harness_die "cannot read $1"
  if [[ "$has_at" == true && "$has_base" == true ]]; then
    harness_die "$1: $HARNESS_ARM_KINDS_EXCLUSIVE_MSG"
  fi
  if [[ "$has_base" == true ]]; then printf '%s' "$HARNESS_ARM_KIND_BASE"
  elif [[ "$has_at" == true ]]; then printf '%s' "$HARNESS_ARM_KIND_AGENT_TOOLING"; fi
}

# The arms an experiment runs: one "<label> <sha>" line each — the sha an agentTooling
# commit or, for base arms, a commit of the measured repository — or one "- -" line when
# experiment.json names no arms (the tree's own vendored copy at the fixture's base).
harness_experiment_arms() {
  local kind key arms
  kind="$(harness_experiment_arm_kind "$1")" || exit 1
  key="$HARNESS_ARM_KIND_AGENT_TOOLING"
  if [[ "$kind" == "$HARNESS_ARM_KIND_BASE" ]]; then key="$HARNESS_BASE_ARMS_KEY"; fi
  # A malformed value dies rather than reading as "no arms": an experiment meant to
  # compare arms must not quietly run every cell unpinned.
  arms="$(jq -r --arg k "$key" '(.[$k] // {}) | to_entries[] | "\(.key) \(.value)"' "$1")" \
    || harness_die "$key in $1 must be an object of <label>: <full sha>"
  if [[ -n "$arms" ]]; then printf '%s\n' "$arms"; else printf -- '- -\n'; fi
}

# ── Repositories by URL ──────────────────────────────────────────────────────
# harness_repo_name <url> — the repository's name: the last path segment, `.git` dropped.
harness_repo_name() {
  local url="${1%/}" name
  url="${url%"$REPO_GIT_SUFFIX"}"
  name="${url##*/}"; name="${name##*:}"
  printf '%s' "$name"
}

# harness_repo_identity <url> — what two spellings of one repository have in common:
# `owner/repo` in lower case for a forge URL (https, ssh://, scp-style, a proxied
# http://…/git/o/r), else the whole URL lower-cased with `.git` and a trailing `/` dropped.
harness_repo_identity() {
  local url="${1%/}" rest path owner repo
  url="${url%"$REPO_GIT_SUFFIX"}"
  case "$url" in
    *://*) rest="${url#*://}"; path="${rest#*/}" ;;
    *@*:*) path="${url#*:}" ;;
    *)     printf '%s' "$url" | tr '[:upper:]' '[:lower:]'; return 0 ;;
  esac
  if [[ "$path" == */* ]]; then
    repo="${path##*/}"; owner="${path%/*}"; owner="${owner##*/}"
    printf '%s/%s' "$owner" "$repo" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$url" | tr '[:upper:]' '[:lower:]'
  fi
}

harness_repo_env_key() {
  printf '%s%s' "$HARNESS_REPO_DIR_PREFIX" "$(harness_repo_name "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g')"
}

# A working tree, not a bare repository — a bare `remote.git` beside a clone is a URL,
# never a checkout — and a MAIN checkout, not one of the linked worktrees the harness
# itself adds beside it (those name the same origin).
harness_is_checkout() {
  [[ -d "$1" && "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] \
    && [[ "$(git -C "$1" rev-parse --git-dir 2>/dev/null)" == "$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" ]]
}

# harness_checkout_names <dir> <identity> — the checkout's origin is that repository.
harness_checkout_names() {
  local dir="$1" identity="$2" origin
  harness_is_checkout "$dir" || return 1
  origin="$(git -C "$dir" config --get remote.origin.url 2>/dev/null)" || return 1
  [[ -n "$origin" && "$(harness_repo_identity "$origin")" == "$identity" ]]
}

# The roots searched for checkouts, one per line.
harness_repo_roots() {
  local roots="$HARNESS_REPO_ROOTS"
  [[ -n "$roots" ]] || roots="$(dirname "${CONSUMER_ROOT:-$DEFAULT_CONSUMER_ROOT}")"
  printf '%s\n' "$roots" | tr ':' '\n' | sed '/^$/d'
}

harness_clone_remedy() {
  local url="$1" errlog="$2"
  grep -qE "$REPO_AUTH_FAILURE_RE" "$errlog" 2>/dev/null || return 0
  [[ -f "$AGENT_TOOLING_DIR/env-profile.sh" ]] || return 0
  # shellcheck source=../env-profile.sh
  source "$AGENT_TOOLING_DIR/env-profile.sh"
  profile_is_cloud || return 0
  harness_warn "the clone of $url could not authenticate, and this is a Claude Code cloud session, whose git proxy serves only the repositories attached to the session: attach $(harness_repo_identity "$url") with the $REPO_ATTACH_TOOL tool, then run this again"
}

# harness_resolve_repo <url> [<path hint>] — prints the checkout for that repository on
# this machine, cloning it when none is found (the order in the header above); dies when
# it cannot. Only ever read from or added worktrees beside — never branched in.
harness_resolve_repo() {
  local url="$1" hint="${2:-}" key override identity root dir name errlog
  [[ -n "$url" ]] || harness_die "harness_resolve_repo: no url"
  key="$(harness_repo_env_key "$url")"
  eval "override=\${$key-}"
  if [[ -n "$override" ]]; then
    harness_is_checkout "$override" || harness_die "$key=$override is not a git checkout"
    ( cd "$override" && pwd ); return 0
  fi
  if [[ -d "$url" ]] && harness_is_checkout "$url"; then
    ( cd "$url" && pwd ); return 0
  fi
  if [[ -n "$hint" && -d "$hint" ]] && harness_is_checkout "$hint"; then
    ( cd "$hint" && pwd ); return 0
  fi
  identity="$(harness_repo_identity "$url")"
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    for dir in "$root"/*/; do
      dir="${dir%/}"
      if harness_checkout_names "$dir" "$identity"; then
        ( cd "$dir" && pwd ); return 0
      fi
    done
  done < <(harness_repo_roots)
  root="$(harness_repo_roots | head -1)"
  name="$(harness_repo_name "$url")"
  [[ -n "$root" && -n "$name" ]] || harness_die "cannot place a clone of $url: no root (HARNESS_REPO_ROOTS) or no repository name"
  dir="$root/$name"
  # A dry run executes nothing, a clone included: name where the clone would go.
  if [[ "${HARNESS_RESOLVE_NO_CLONE:-0}" == 1 ]]; then
    harness_log "no checkout of $url under $(harness_repo_roots | paste -sd: -) — a run would clone it into $dir" >&2
    printf '%s' "$dir"; return 0
  fi
  [[ ! -e "$dir" ]] || harness_die "$dir exists but is not a checkout of $url — move it, or point $key at the right checkout"
  harness_log "no checkout of $url under $(harness_repo_roots | paste -sd: -) — cloning into $dir" >&2
  errlog="$(mktemp "${TMPDIR:-/tmp}/harness-clone.XXXXXX")"
  if ! git clone -q "$url" "$dir" 2> >(tee "$errlog" >&2); then
    harness_clone_remedy "$url" "$errlog"
    rm -f "$errlog"
    harness_die "could not clone $url into $dir"
  fi
  rm -f "$errlog"
  ( cd "$dir" && pwd )
}

# ── The measured repository: the consumer ────────────────────────────────────
# harness_require_own_driver — the running harness must be the consumer's own vendored
# copy: CONSUMER_ROOT/agentTooling is this script's AGENT_TOOLING_DIR (physical paths).
# HARNESS_TEST_EXTERNAL_DRIVER=1 is the smoke test's seam and nothing else's.
harness_require_own_driver() {
  local theirs="$CONSUMER_ROOT/$AGENT_TOOLING_RELPATH"
  [[ "$HARNESS_TEST_EXTERNAL_DRIVER" != 1 ]] || return 0
  if [[ -d "$theirs" && "$(cd "$theirs" && pwd -P)" == "$(cd "$AGENT_TOOLING_DIR" && pwd -P)" ]]; then
    return 0
  fi
  harness_die "this harness (${AGENT_TOOLING_DIR}) is not the vendored copy of the measured repository $CONSUMER_ROOT. The harness runs from the measured repository's own agentTooling/: bring that one up to date there (agentTooling/update.sh) instead of driving it from another checkout."
}

# harness_consumer_identity — harness_repo_identity of the consumer's origin; empty when
# it has none.
harness_consumer_identity() {
  local url
  url="$(git -C "${CONSUMER_ROOT:-$DEFAULT_CONSUMER_ROOT}" config --get "remote.$CONSUMER_IDENTITY_REMOTE.url" 2>/dev/null)" || return 0
  [[ -z "$url" ]] || harness_repo_identity "$url"
}

# harness_measured_repo_problem <json> — the `repo` block of a fixture or program must be
# the consumer: absent, or a `repo.url` / `repo.path` that identifies it. Prints nothing
# and returns 0 when so; otherwise prints the repository it names (an identity) and returns 1.
harness_measured_repo_problem() {
  local json="$1" own url path root named
  own="$(harness_consumer_identity)"
  root="${CONSUMER_ROOT:-$DEFAULT_CONSUMER_ROOT}"
  url="$(harness_json "$json" .repo.url)"
  path="$(harness_json "$json" .repo.path)"
  if [[ -n "$url" ]]; then
    named="$(harness_repo_identity "$url")"
    if [[ -z "$own" || "$named" != "$own" ]]; then printf '%s' "$named"; return 1; fi
  fi
  if [[ -n "$path" ]]; then
    named=""
    if [[ -d "$path" && "$(cd "$path" && pwd -P)" == "$(cd "$root" && pwd -P)" ]]; then
      return 0
    fi
    if harness_is_checkout "$path"; then
      named="$(git -C "$path" config --get "remote.$CONSUMER_IDENTITY_REMOTE.url" 2>/dev/null)"
      [[ -z "$named" ]] || named="$(harness_repo_identity "$named")"
    fi
    [[ -n "${named:-}" ]] || named="$path"
    if [[ -z "$own" || "$named" != "$own" ]]; then printf '%s' "$named"; return 1; fi
  fi
  return 0
}

# harness_measured_repo_message <file> <fixture|program> <named repository> — the refusal.
harness_measured_repo_message() {
  local file="$1" kind="$2" named="$3" own dir
  own="$(harness_consumer_identity)"
  if [[ "$kind" == program ]]; then dir="$HARNESS_PROGRAMS_RELDIR/"; else dir="$HARNESS_FIXTURES_RELDIR/"; fi
  printf '%s: this %s measures %s, but it is on %s. An experiment runs from, and lives on, the repository it measures: move the %s into that repository'"'"'s %s and run it there.' \
    "$file" "$kind" "$named" "${own:-a repository with no origin}" "$kind" "$dir"
}

# harness_check_measured_repo <json> <fixture|program> — dies unless the file's `repo`
# block (if any) is the consumer. The first thing every reader of a fixture or program does.
harness_check_measured_repo() {
  local named
  if ! named="$(harness_measured_repo_problem "$1")"; then
    harness_die "$(harness_measured_repo_message "$1" "$2" "$named")"
  fi
}

# harness_fixture_repo <fixture.json> — the repository the fixture builds in: the consumer.
# Never resolved, searched for or cloned.
harness_fixture_repo() {
  harness_check_measured_repo "$1" fixture
  printf '%s' "${CONSUMER_ROOT:-$DEFAULT_CONSUMER_ROOT}"
}

# harness_fixture_spec_external <fixture.json> — the spec lives in another repository
# (`spec.url`, or the legacy `spec.repo` path hint); absent both, it is the consumer's.
harness_fixture_spec_external() {
  [[ -n "$(harness_json "$1" .spec.url)" || -n "$(harness_json "$1" .spec.repo)" ]]
}

# harness_spec_source_label <fixture.json> — for a dry run: where the spec worktree comes from.
harness_spec_source_label() {
  if harness_fixture_spec_external "$1"; then
    printf 'external spec repository %s' "$(harness_json "$1" .spec.url)"
  else
    printf "from the consumer's own checkout"
  fi
}

# harness_fixture_spec_repo <fixture.json> — the checkout the spec worktree is added from:
# the consumer when the fixture names no spec repository; else `spec.url` resolved like any
# external input, read-only. The legacy `spec.repo` path, with no URL, is honoured with a
# warning when it exists here.
harness_fixture_spec_repo() {
  local json="$1" url hint
  url="$(harness_json "$json" .spec.url)"
  hint="$(harness_json "$json" .spec.repo)"
  if [[ -n "$url" ]]; then
    harness_resolve_repo "$url" "$hint"
    return
  fi
  if [[ -n "$hint" ]]; then
    if [[ -d "$hint" ]] && harness_is_checkout "$hint"; then
      harness_warn "$json names no spec.url — using its path $hint, which is this machine's only; add spec.url so the fixture runs anywhere"
      ( cd "$hint" && pwd ); return 0
    fi
    harness_die "$json names no spec.url (and its path hint $hint is not a checkout here) — add spec.url: the repository's URL, resolved per machine, or drop spec.repo to take the spec from this repository"
  fi
  printf '%s' "${CONSUMER_ROOT:-$DEFAULT_CONSUMER_ROOT}"
}

# ── The forge seam ───────────────────────────────────────────────────────────
# harness_forge_for [<checkout>] — the forge adapter to ask about PRs: HARNESS_FORGE_BIN
# when set, else the DRIVER's own forge.sh (the copy this harness lives in) — never the
# checkout's vendored one, which an arm built from a historical base may not have at all.
# The checkout is passed to the forge as FORGE_CHECKOUT (harness_forge_run), so the
# driver's adapter asks about that checkout's origin. Prints nothing when there is no
# forge.sh to run.
harness_forge_for() {
  if [[ -n "$HARNESS_FORGE_BIN" ]]; then printf '%s' "$HARNESS_FORGE_BIN"; return 0; fi
  if [[ -x "$DRIVER_FORGE" ]]; then printf '%s' "$DRIVER_FORGE"; return 0; fi
  printf ''
}

# harness_forge_run <checkout> <forge verb and args…> — the verb through the forge seam,
# run in the checkout and pointed at its origin.
harness_forge_run() {
  local tree="$1" forge
  shift
  forge="$(harness_forge_for "$tree")"
  [[ -n "$forge" ]] || return 1
  ( cd "$tree" && FORGE_CHECKOUT="$tree" "$forge" "$@" )
}

# ── Pinning ──────────────────────────────────────────────────────────────────
# harness_pin_agent_tooling <tree> <sha> <agentTooling checkout> — replace the tree's
# vendored agentTooling/ with <sha>'s tree from that checkout, run the pinned copy's
# sync-plans.sh, commit as the arm's pin. Dies on any failure: an arm that is not on the
# version it claims measures nothing.
harness_pin_agent_tooling() {
  local tree="$1" sha="$2" at="$3" short
  short="${sha:0:$PIN_SHORT_SHA_LEN}"
  if ! git -C "$at" cat-file -e "$sha^{commit}" 2>/dev/null; then
    git -C "$at" fetch -q origin 2>/dev/null || true
    git -C "$at" cat-file -e "$sha^{commit}" 2>/dev/null \
      || harness_die "agentTooling commit $sha is not in $at, even after a fetch"
  fi
  rm -rf "${tree:?}/$AGENT_TOOLING_RELPATH"
  mkdir -p "$tree/$AGENT_TOOLING_RELPATH"
  git -C "$at" archive "$sha" | tar -x -C "$tree/$AGENT_TOOLING_RELPATH" \
    || harness_die "could not extract agentTooling $short into $tree"
  # The sync's exit status reports drift in the repo-owned stubs and an unfilled
  # PROJECT_FACTS.md — the fixture repo's state, which every arm shares — so it is logged,
  # not fatal: what the pin needs is the generated files rewritten from the pinned copy.
  local synclog="${HARNESS_LOG_DIR:-${TMPDIR:-/tmp}}/${HARNESS_BRANCH_NAME:-pin}-sync-plans.log"
  mkdir -p "$(dirname "$synclog")"
  ( cd "$tree" && "./$SYNC_PLANS_RELPATH" ) > "$synclog" 2>&1 \
    || harness_warn "the pinned copy's sync-plans.sh exited non-zero in $tree (drift in the repo-owned stubs is expected; see $synclog)"
  # An arm equal to the version the base already vendors (the control arm) changes nothing
  # in the tree; the commit is then empty, and still made, so the branch records its
  # version and do_setup's re-run guard (the pin subject in BASE..HEAD) still finds it.
  harness_commit_all "$tree" "$HARNESS_PIN_SUBJECT_PREFIX $short" --allow-empty \
    || harness_die "could not commit the pin of agentTooling to $short in $tree"
  harness_log "pinned $tree/$AGENT_TOOLING_RELPATH to upstream $short"
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

# harness_stage_enabled <experiment.json> <stage> — prints true or false. An absent flag
# is true; an explicit false stays false (`// true` would read it as absent).
harness_stage_enabled() {
  jq -r --arg s "$2" 'if .stages[$s] == null then true else .stages[$s] end' "$1"
}

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
  # HARNESS_EFFORT, when set, rides on every call from here, so no call site names it.
  local effort_args=()
  [[ -z "$HARNESS_EFFORT" ]] || effort_args=(--effort "$HARNESS_EFFORT")
  ( cd "$cwd" && "$HARNESS_CLAUDE_BIN" -p --output-format json ${effort_args[@]+"${effort_args[@]}"} "$@" < "$prompt_file" ) > "$out"
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
#
# Every substitution goes through harness_replace_literal, never `${text//pat/$value}`:
# bash 5.2 turns `patsub_replacement` on by default, and under it an `&` in the
# replacement expands to the matched text and a `\` quotes the next character, so a
# facts.md line with an `&` shipped as `@@FACTS@@` repeated into the brief.
harness_replace_literal() {
  local text="$1" pattern="$2" replacement="$3" result=""
  while [[ "$text" == *"$pattern"* ]]; do
    result="$result${text%%"$pattern"*}$replacement"
    text="${text#*"$pattern"}"
  done
  printf -v HARNESS_REPLACED '%s' "$result$text"
}

harness_fill_template() {
  local file="$1" text name value missing wants_prev=false
  text="$(cat "$file")"
  # The file-valued placeholders go in FIRST — isolation.md, facts.md, review-brief.md
  # and findings.md all carry scalar placeholders of their own (`@@SPEC_TREE@@`,
  # `@@GATE_MINUTES@@`, `@@TREE@@`), and only a pass that runs after they are inserted
  # can resolve them. Insert last and they ship to a model verbatim.
  harness_replace_literal "$text" '@@ISOLATION@@' "${HARNESS_ISOLATION-}"; text="$HARNESS_REPLACED"
  # The program templates' multi-line values (FEATURES, RECORD_COMMANDS, DEPENDS,
  # METHOD_CHOICE) carry scalar placeholders too, so they go in before the scalars.
  for name in FACTS REVIEW_BRIEF FINDINGS_TEXT FEATURES RECORD_COMMANDS DEPENDS METHOD_CHOICE \
              TREE BRANCH BASE SLUG SPEC_TREE SPEC_PATH SPEC_SECTIONS \
              GATE_COMMAND GATE_MINUTES FIXTURE SIBLINGS EXPERIMENTS_DIR \
              AGENT_TOOLING FINDINGS BRIEF \
              PROGRAM PROGRAM_SLUG PROGRAM_BRANCH PROGRAM_TREE ARM FEATURE_COUNT POSITION \
              PR_BASE PR_FIRST_LINE BRIEF_PATH BRIEF_DIR RECORD_PATH BRIEF_TEMPLATE; do
    eval "value=\${HARNESS_$name-}"
    harness_replace_literal "$text" "@@${name}@@" "$value"; text="$HARNESS_REPLACED"
  done
  # PREV_OUTCOME is a previous implementer's report, free text that may itself contain an
  # @@NAME@@: it is inserted last and never scanned, so it can neither be substituted into
  # nor trip the unfilled-placeholder check. Unset while the template uses it is still a bug.
  if [[ "$text" == *'@@PREV_OUTCOME@@'* ]]; then
    wants_prev=true
    [[ -n "${HARNESS_PREV_OUTCOME+set}" ]] || harness_die "unfilled placeholder(s) in $file: @@PREV_OUTCOME@@"
  fi
  missing="$(printf '%s' "$text" | grep -oE '@@[A-Z_]+@@' | sort -u | grep -vx '@@PREV_OUTCOME@@' | tr '\n' ' ')"
  if [[ -n "$missing" ]]; then
    harness_die "unfilled placeholder(s) in $file: $missing"
  fi
  if [[ "$wants_prev" == true ]]; then
    harness_replace_literal "$text" '@@PREV_OUTCOME@@' "${HARNESS_PREV_OUTCOME-}"; text="$HARNESS_REPLACED"
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
  local tree="$1" slug="$2" branch="$3" from="$4" title="$5" method="${6:-plans}"
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
  "method": "$method",
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
  harness_replace_literal "$counts" '|' "$GATE_COUNTS_JOIN"
  printf '%s' "$HARNESS_REPLACED"
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

# harness_commit_all <tree> <message> [--allow-empty] — stage everything and commit. Fails
# when there is nothing to commit, which every caller but the pin treats as a normal
# outcome; the pin passes --allow-empty because its commit is a record, not a change.
harness_commit_all() {
  local tree="$1" message="$2" empty_flag=""
  [[ "${3:-}" == --allow-empty ]] && empty_flag="--allow-empty"
  ( cd "$tree" && git add -A && git commit -q $empty_flag -m "$message" ) || return 1
}

harness_push() {
  local tree="$1" branch="$2"
  harness_has_remote "$tree" || { harness_log "no remote in $tree — not pushing"; return 0; }
  ( cd "$tree" && git push -q -u origin "$branch" ) || { harness_warn "push of $branch failed"; return 1; }
}

# The PR the method was asked to open. Read-only, through the forge seam: `pr-find`
# prints the open PR's url for that head, or nothing.
harness_pr_url() {
  local tree="$1" branch="$2"
  harness_forge_run "$tree" pr-find "$branch" 2>/dev/null || printf ''
}

# harness_pr_open <tree> <branch> <title> <body-file> — opens the PR into
# HARNESS_PR_BASE through the forge seam and prints its url; nothing when it could not.
harness_pr_open() {
  local tree="$1" branch="$2" title="$3" body="$4"
  harness_forge_run "$tree" pr-open "$branch" "$HARNESS_PR_BASE" "$title" "$body" || { printf ''; return 1; }
}

# harness_branch_has_commits <tree> <base> — whether HEAD carries commits beyond <base>.
harness_branch_has_commits() {
  [[ -n "$(git -C "$1" log --format=%H -1 "$2..HEAD" 2>/dev/null)" ]]
}

# harness_branch_pushed <tree> <branch> — whether origin has <branch> at all.
harness_branch_pushed() {
  [[ -n "$(git -C "$1" ls-remote origin "refs/heads/$2" 2>/dev/null)" ]]
}

# harness_resolve_commit <repo> <ref> [<remote>] — prints the commit sha <ref> names in
# <repo>. A fixture base can be a prep commit that is on no branch of main, so a clone has
# it only once someone fetched its branch; when the ref does not resolve and looks like a
# sha, fetch it by sha from the remote ONCE and retry. Fetching by sha creates and moves
# no ref (it lands in FETCH_HEAD). Prints nothing and returns 1 when it still does not
# resolve.
harness_resolve_commit() {
  local repo="$1" ref="$2" remote="${3:-origin}" sha
  if sha="$(git -C "$repo" rev-parse --verify --quiet "${ref}^{commit}" 2>/dev/null)"; then
    printf '%s' "$sha"; return 0
  fi
  [[ "$ref" =~ ^[0-9a-fA-F]{7,40}$ ]] || return 1
  git -C "$repo" fetch -q "$remote" "$ref" 2>/dev/null || return 1
  sha="$(git -C "$repo" rev-parse --verify --quiet "${ref}^{commit}" 2>/dev/null)" || return 1
  printf '%s' "$sha"
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

# ── Program cells: checks, ids, sessions ─────────────────────────────────────
# harness_check_program_floor <agentTooling dir> <arm label or ""> — 0 when the tree
# carries every file a program cell needs; else a message naming the first missing file and
# the arm on stderr, return 1 (the caller decides whether that is fatal).
harness_check_program_floor() {
  local dir="$1" label="${2:-}" file who
  if [[ -n "$label" ]]; then who="arm $label"; else who="the tree's own vendored copy"; fi
  for file in $HARNESS_PROGRAM_FLOOR_FILES; do
    if [[ ! -f "$dir/$file" ]]; then
      printf 'ERROR: %s of agentTooling has no %s — a program cell needs a version that has the orchestration machinery; pin a newer commit\n' \
        "$who" "$file" >&2
      return 1
    fi
  done
  return 0
}

# harness_program_check <program.json> <fixtures-dir> — every rule program.json carries
# (README → "Program cells"), each violation on stderr as `ERROR: …`; returns 1 if any.
# The ONE warning (fixture bases that differ from the program's, which are ignored) goes
# to stderr and does not fail. The gate's fall-back to the first fixture's is not checked
# here (harness_program_gate_field resolves it).
harness_program_check() {
  local json="$1" fixtures_dir="$2" bad=0 field value url identity fx fx_json fx_url seen="" differing="" method count i
  [[ -f "$json" ]] || { printf 'ERROR: no program at %s\n' "$json" >&2; return 1; }
  jq -e 'type == "object"' "$json" >/dev/null 2>&1 \
    || { printf 'ERROR: %s is not a JSON object\n' "$json" >&2; return 1; }
  for field in .name .base .branch_stem; do
    value="$(harness_json "$json" "$field")"
    if [[ -z "$value" ]]; then printf 'ERROR: %s: missing %s\n' "$json" "$field" >&2; bad=1; fi
  done
  value="$(harness_json "$json" .base)"
  if [[ -n "$value" && ! "$value" =~ $PROGRAM_BASE_RE ]]; then
    printf 'ERROR: %s: base must be a full 40-hex commit id, got %s\n' "$json" "$value" >&2; bad=1
  fi
  value="$(harness_json "$json" .branch_stem)"
  if [[ -n "$value" && ! "$value" =~ $PROGRAM_STEM_RE ]]; then
    printf 'ERROR: %s: branch_stem must be bare camelCase, got %s\n' "$json" "$value" >&2; bad=1
  fi
  count="$(jq -r '(.features // []) | if type == "array" then length else -1 end' "$json")"
  if (( count < 1 )); then
    printf 'ERROR: %s: features must be a non-empty array\n' "$json" >&2
    return 1
  fi
  if [[ "$(jq -r '.features[0].depends_on_previous // false' "$json")" == true ]]; then
    printf 'ERROR: %s: the first feature cannot depend on a previous one\n' "$json" >&2; bad=1
  fi
  # The program's repository is the consumer: absent, or a repo block that identifies it.
  if ! url="$(harness_measured_repo_problem "$json")"; then
    printf 'ERROR: %s\n' "$(harness_measured_repo_message "$json" program "$url")" >&2; bad=1
  fi
  identity="$(harness_consumer_identity)"
  for (( i = 0; i < count; i++ )); do
    fx="$(jq -r --argjson i "$i" '.features[$i].fixture // empty' "$json")"
    if [[ -z "$fx" ]]; then
      printf 'ERROR: %s: features[%d] names no fixture\n' "$json" "$i" >&2; bad=1; continue
    fi
    if [[ "$(jq -r --argjson i "$i" '.features[$i].depends_on_previous // false | type' "$json")" != boolean ]]; then
      printf 'ERROR: %s: features[%d] (%s): depends_on_previous must be true or false\n' "$json" "$i" "$fx" >&2; bad=1
    fi
    case "$seen" in
      *"|$fx|"*) printf 'ERROR: %s: fixture %s appears more than once\n' "$json" "$fx" >&2; bad=1 ;;
    esac
    seen+="|$fx|"
    method="$(jq -r --argjson i "$i" '.features[$i].method // empty' "$json")"
    if [[ -n "$method" ]]; then
      if [[ " $PROGRAM_RESERVED_METHODS " == *" $method "* ]]; then
        printf 'ERROR: %s: features[%d] (%s): method %s is not a choice a feature can pin\n' "$json" "$i" "$fx" "$method" >&2; bad=1
      elif [[ " $PROGRAM_CHOICE_METHODS " != *" $method "* && ! -d "$HARNESS_METHODS_DIR/$method" ]]; then
        printf 'ERROR: %s: features[%d] (%s): method %s is neither one of %s nor a directory under harness/methods/\n' \
          "$json" "$i" "$fx" "$method" "$PROGRAM_CHOICE_METHODS" >&2; bad=1
      fi
    fi
    fx_json="$fixtures_dir/$fx/fixture.json"
    if [[ ! -f "$fx_json" ]]; then
      printf 'ERROR: %s: fixture %s has no %s\n' "$json" "$fx" "$fx_json" >&2; bad=1; continue
    fi
    if ! fx_url="$(harness_measured_repo_problem "$fx_json")"; then
      printf 'ERROR: %s: fixture %s is on repository %s, not the consumer'"'"'s %s — an experiment runs from, and lives on, the repository it measures\n' \
        "$json" "$fx" "$fx_url" "${identity:-(no origin)}" >&2; bad=1
    fi
    if [[ "$(harness_json "$fx_json" .base)" != "$(harness_json "$json" .base)" && ", $differing, " != *", $fx, "* ]]; then
      differing+="${differing:+, }$fx"
    fi
  done
  if [[ -n "$differing" ]]; then
    harness_warn "$json: base of fixture(s) $differing differs from the program's; fixture bases are ignored in a program cell, every feature starts from the program's base"
  fi
  (( bad == 0 ))
}

# harness_program_gate_field <program.json> <fixtures-dir> <command|green|minutes> — the
# program's gate field, else the first feature's fixture's; prints nothing when neither has it.
harness_program_gate_field() {
  local json="$1" fixtures_dir="$2" field="$3" value first
  [[ " $PROGRAM_GATE_FIELDS " == *" $field "* ]] || harness_die "harness_program_gate_field: unknown gate field $field"
  value="$(harness_json "$json" ".gate.$field")"
  if [[ -z "$value" ]]; then
    first="$(harness_json "$json" '.features[0].fixture')"
    if [[ -n "$first" && -f "$fixtures_dir/$first/fixture.json" ]]; then
      value="$(harness_json "$fixtures_dir/$first/fixture.json" ".gate.$field")"
    fi
  fi
  printf '%s' "$value"
}

# A lower-case UUID for `claude --session-id`.
harness_new_session_id() {
  local id=""
  if command -v uuidgen >/dev/null 2>&1; then
    id="$(uuidgen 2>/dev/null)"
  elif [[ -r "$PROGRAM_UUID_RELPATH" ]]; then
    id="$(cat "$PROGRAM_UUID_RELPATH")"
  else
    id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  fi
  printf '%s' "$id" | tr '[:upper:]' '[:lower:]'
}

# harness_claude_new_session / harness_claude_resume <out> <prompt-file> <cwd> <session-id>
# [flags…] — harness_claude with the session pinned / resumed. Same output file, same exit code.
harness_claude_new_session() {
  local out="$1" prompt_file="$2" cwd="$3" session="$4"
  shift 4
  harness_claude "$out" "$prompt_file" "$cwd" --session-id "$session" "$@"
}

harness_claude_resume() {
  local out="$1" prompt_file="$2" cwd="$3" session="$4"
  shift 4
  harness_claude "$out" "$prompt_file" "$cwd" --resume "$session" "$@"
}
