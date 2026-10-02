#!/usr/bin/env bash
set -uo pipefail

# Scaffold a fixture: pin the commits, verify what a script can verify, write the rest
# as stubs that fail loudly until a person replaces them.
#
#   harness/new-fixture.sh <name> --repo <path> --base <ref> \
#                          --spec-repo <path> --spec-ref <ref> --spec-path <file> \
#                          [--sections 5.1,12] [--setup '<cmd>']... \
#                          [--gate-command ./plans/gate.sh] [--gate-green 'all checks passed'] \
#                          [--gate-minutes N] [--branch-stem <stem>] [--diff-lines N] \
#                          [--consumer <path>]
#
# Run from the consuming repo root. Writes plans/experiments/fixtures/<name>/ with a
# fixture.json whose `base` and `spec.commit` are full commit ids resolved from the refs
# given (a ref moves; a fixture must not), and the three files only a person can write —
# facts.md, review-brief.md, accept/accept.py — as stubs: the first two carry a
# `@@TODO@@` placeholder, which aborts any run at the brief stage, and the probe exits 1.
# Finish with harness/check-fixture.sh <name>, which is green only once all three are real.
#
# What is verified here: both refs resolve; the base is on a remote branch (else a
# warning — another machine could not fetch it); spec.path exists at spec.commit and each
# section heading is found in it (else a warning); the gate script exists at base.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_REQUIRED_TOOLS="jq git python3"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# ── Defaults for what a fixture usually looks like ───────────────────────────
DEFAULT_REMOTE="origin"
DEFAULT_GATE_COMMAND="./plans/gate.sh"
DEFAULT_GATE_GREEN="all checks passed"
DEFAULT_GATE_MINUTES=2
DEFAULT_DIFF_LINES=0
# What the stubs say so check-fixture.sh can tell a stub from the real thing.
STUB_MARKER="harness/new-fixture.sh stub"

# ── Arguments ────────────────────────────────────────────────────────────────
NAME=""; REPO=""; BASE_REF=""; SPEC_REPO=""; SPEC_REF=""; SPEC_PATH=""
SECTIONS=""; SETUP=(); GATE_COMMAND="$DEFAULT_GATE_COMMAND"; GATE_GREEN="$DEFAULT_GATE_GREEN"
GATE_MINUTES="$DEFAULT_GATE_MINUTES"; BRANCH_STEM=""; DIFF_LINES="$DEFAULT_DIFF_LINES"
REMOTE="$DEFAULT_REMOTE"
CONSUMER_ROOT="$DEFAULT_CONSUMER_ROOT"

usage() {
  sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while (( $# > 0 )); do
  case "$1" in
    --repo)         REPO="$(cd "${2:?--repo needs a path}" && pwd)"; shift 2 ;;
    --remote)       REMOTE="${2:?--remote needs a name}"; shift 2 ;;
    --base)         BASE_REF="${2:?--base needs a ref}"; shift 2 ;;
    --spec-repo)    SPEC_REPO="$(cd "${2:?--spec-repo needs a path}" && pwd)"; shift 2 ;;
    --spec-ref)     SPEC_REF="${2:?--spec-ref needs a ref}"; shift 2 ;;
    --spec-path)    SPEC_PATH="${2:?--spec-path needs a file}"; shift 2 ;;
    --sections)     SECTIONS="${2:?--sections needs a comma list}"; shift 2 ;;
    --setup)        SETUP+=("${2:?--setup needs a command}"); shift 2 ;;
    --gate-command) GATE_COMMAND="${2:?--gate-command needs a command}"; shift 2 ;;
    --gate-green)   GATE_GREEN="${2:?--gate-green needs a string}"; shift 2 ;;
    --gate-minutes) GATE_MINUTES="${2:?--gate-minutes needs a number}"; shift 2 ;;
    --branch-stem)  BRANCH_STEM="${2:?--branch-stem needs a stem}"; shift 2 ;;
    --diff-lines)   DIFF_LINES="${2:?--diff-lines needs a number}"; shift 2 ;;
    --consumer)     CONSUMER_ROOT="$(cd "${2:?--consumer needs a path}" && pwd)"; shift 2 ;;
    -h|--help)      usage 0 ;;
    -*)             harness_die "unknown option: $1" ;;
    *)              [[ -z "$NAME" ]] || harness_die "unexpected argument: $1"
                    NAME="$1"; shift ;;
  esac
done

[[ -n "$NAME" ]] || usage 1
for required in REPO BASE_REF SPEC_REPO SPEC_REF SPEC_PATH; do
  [[ -n "${!required}" ]] || harness_die "--$(printf '%s' "$required" | tr '[:upper:]_' '[:lower:]-') is required"
done
[[ "$NAME" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "fixture name must be bare camelCase: $NAME"
[[ -z "$BRANCH_STEM" ]] && BRANCH_STEM="$NAME"
[[ "$BRANCH_STEM" =~ ^[a-z][A-Za-z0-9]*$ ]] || harness_die "branch stem must be bare camelCase (no user/ prefix): $BRANCH_STEM"

harness_require_tools

FIXTURE_DIR="$CONSUMER_ROOT/plans/experiments/fixtures/$NAME"
[[ ! -e "$FIXTURE_DIR" ]] || harness_die "fixture already exists: $FIXTURE_DIR"

# ── Pin the base ─────────────────────────────────────────────────────────────
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || harness_die "not a git repository: $REPO"
if git -C "$REPO" remote get-url "$REMOTE" >/dev/null 2>&1; then
  harness_log "fetching $REMOTE in $REPO"
  git -C "$REPO" fetch -q "$REMOTE" || harness_warn "fetch of $REMOTE failed; resolving against what is local"
else
  harness_warn "$REPO has no remote named $REMOTE — the fixture will still name it, as run.sh fetches from it"
fi
BASE_SHA="$(git -C "$REPO" rev-parse --verify --quiet "${BASE_REF}^{commit}")" \
  || harness_die "base ref does not resolve in $REPO: $BASE_REF"
if [[ -z "$(git -C "$REPO" branch -r --contains "$BASE_SHA" 2>/dev/null)" ]]; then
  harness_warn "base $BASE_SHA is on no remote branch of $REPO — push it, or a worktree on another machine cannot start from it"
fi
harness_log "base   $BASE_REF -> $BASE_SHA"

# ── Pin the spec ─────────────────────────────────────────────────────────────
git -C "$SPEC_REPO" rev-parse --git-dir >/dev/null 2>&1 || harness_die "not a git repository: $SPEC_REPO"
SPEC_SHA="$(git -C "$SPEC_REPO" rev-parse --verify --quiet "${SPEC_REF}^{commit}")" \
  || harness_die "spec ref does not resolve in $SPEC_REPO: $SPEC_REF"
git -C "$SPEC_REPO" cat-file -e "$SPEC_SHA:$SPEC_PATH" 2>/dev/null \
  || harness_die "$SPEC_PATH does not exist at $SPEC_SHA in $SPEC_REPO"
harness_log "spec   $SPEC_REF -> $SPEC_SHA ($SPEC_PATH)"

SECTIONS_JSON="$(jq -cn --arg s "$SECTIONS" '$s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')"
if [[ "$SECTIONS_JSON" != "[]" ]]; then
  spec_text="$(git -C "$SPEC_REPO" show "$SPEC_SHA:$SPEC_PATH")"
  for section in $(jq -r '.[]' <<<"$SECTIONS_JSON"); do
    if printf '%s\n' "$spec_text" | grep -qE "^#+[[:space:]]+§?${section//./\\.}([[:space:].:]|$)"; then
      harness_log "section $section found"
    else
      harness_warn "no heading for section $section in $SPEC_PATH at $SPEC_SHA — the brief will still name it"
    fi
  done
fi

# ── The gate must exist at base ──────────────────────────────────────────────
GATE_SCRIPT="${GATE_COMMAND%% *}"
GATE_SCRIPT="${GATE_SCRIPT#./}"
git -C "$REPO" cat-file -e "$BASE_SHA:$GATE_SCRIPT" 2>/dev/null \
  || harness_die "gate script $GATE_SCRIPT does not exist at base $BASE_SHA — the setup stage rehearses it before any method runs"

# ── Write it ─────────────────────────────────────────────────────────────────
mkdir -p "$FIXTURE_DIR/accept"

if (( ${#SETUP[@]} > 0 )); then
  SETUP_JSON="$(printf '%s\n' "${SETUP[@]}" | jq -R . | jq -sc .)"
else
  SETUP_JSON="[]"
fi

jq -n \
  --arg name "$NAME" --arg repo "$REPO" --arg remote "$REMOTE" --arg base "$BASE_SHA" \
  --arg srepo "$SPEC_REPO" --arg scommit "$SPEC_SHA" --arg spath "$SPEC_PATH" \
  --argjson sections "$SECTIONS_JSON" --argjson setup "$SETUP_JSON" \
  --arg gcmd "$GATE_COMMAND" --arg ggreen "$GATE_GREEN" --argjson gmin "$GATE_MINUTES" \
  --arg stem "$BRANCH_STEM" --argjson diff "$DIFF_LINES" \
  '{name: $name,
    repo: {path: $repo, remote: $remote},
    base: $base,
    spec: {repo: $srepo, commit: $scommit, path: $spath, sections: $sections},
    setup: $setup,
    gate: {command: $gcmd, green: $ggreen, minutes: $gmin},
    branch_stem: $stem,
    diff_lines: $diff}' > "$FIXTURE_DIR/fixture.json"

cat > "$FIXTURE_DIR/facts.md" <<FACTS
## What this feature is — and is not

@@TODO@@ ($STUB_MARKER) — replace this whole file before running anything. It is handed
to every method verbatim, so it says, in the spec's own terms: what the feature is and
which spec sections settle it; what is explicitly out of scope; which calls the spec
leaves to the implementer (name them, do not make them); and the toolchain facts of the
worktree — interpreter and tool paths, what is already installed, what the gate runs and
how long it takes, what must never be started or written. Use \`@@TREE@@\`,
\`@@SPEC_TREE@@\`, \`@@GATE_COMMAND@@\` and \`@@GATE_MINUTES@@\` for paths and numbers the
harness fills per run; never a literal worktree path. An existing fixture's facts.md is
the model.

## The toolchain in this worktree — facts, not choices

@@TODO@@
FACTS

cat > "$FIXTURE_DIR/review-brief.md" <<BRIEF
Written from \`$SPEC_PATH\` $( [[ "$SECTIONS_JSON" != "[]" ]] && printf '§%s ' $(jq -r '.[]' <<<"$SECTIONS_JSON") )at \`${SPEC_SHA:0:7}\` before any method ran. It says
**what** to check; the preamble above says how. Nothing here was derived from any arm's
tree — if the tree solved a problem this list does not mention, that is not a finding.

@@TODO@@ ($STUB_MARKER) — replace this file before running anything: restate the
contract from the spec so a reviewer can check against it without leaving this file,
then list the checks in the order to make them, each naming what a finding looks like.
Write it from the spec only, before any tree exists — it is the scoring instrument.
BRIEF

cat > "$FIXTURE_DIR/accept/accept.py" <<ACCEPT
#!/usr/bin/env python3
"""Acceptance probe for the $NAME fixture: \`accept.py <tree>\` — exit 0 pass / 1 fail,
one line per check, PASS/FAIL first on the line.

Drive the arm's REAL CLI or HTTP routes; never its tests, which were written by the thing
under test. Stdlib only, run with any python3; shell out to <tree>'s own interpreter or
console scripts for anything that needs the arm's environment. Build any collection or
database the checks need under a temp directory — \`accept.py <tree>\` is the whole
interface and the harness passes nothing else.
"""
import sys

STUB = "$STUB_MARKER"

print(f"FAIL accept.py for $NAME has not been written ({STUB})")
sys.exit(1)
ACCEPT

cat > "$FIXTURE_DIR/accept/README.md" <<ACCEPTREADME
# accept

The acceptance probe for this fixture, run by the harness at checklist-green
(\`harness/SPEC.md\` → stage 6) and rerunnable by hand against any arm's worktree:

\`\`\`bash
python3 accept.py <tree>
\`\`\`

- \`accept.py\` — @@TODO@@ ($STUB_MARKER): list each check it makes over the arm's **real**
  CLI or routes, one line each. Exit code 0 if every check passed, 1 otherwise. Never
  imports the arm's code and never runs the arm's tests.
ACCEPTREADME

cat > "$FIXTURE_DIR/README.md" <<README
# $NAME

@@TODO@@ ($STUB_MARKER): one paragraph on what the feature is and which spec sections
define it, frozen so it can be built again by any method.

| File | What it is |
|---|---|
| \`fixture.json\` | The pins: repo, base, spec commit, setup, gate, branch stem. |
| \`facts.md\` | The scope boundary and this worktree's toolchain, handed to every method verbatim. Uses \`@@TREE@@\` / \`@@SPEC_TREE@@\` / \`@@GATE_COMMAND@@\` / \`@@GATE_MINUTES@@\`, which the harness fills. |
| \`review-brief.md\` | What the harness's review pass checks, written from the spec before any method ran. |
| \`accept/accept.py\` | The acceptance checks over the real CLI or routes. |

## The pins, and where they came from

- \`base\` — \`$BASE_SHA\`, resolved from \`$BASE_REF\` in \`$REPO\` on $(harness_utc_now).
  @@TODO@@: say why this commit (the merge-base of earlier arms, \`main\` after a
  particular merge, …).
- \`spec\` — \`$SPEC_PATH\` at \`$SPEC_SHA\`, resolved from \`$SPEC_REF\` in \`$SPEC_REPO\`;
  sections $SECTIONS_JSON. The harness checks it out detached at
  \`$SPEC_REPO-fx-$NAME\` and points every brief there, so the fixture survives that
  branch moving.
- \`setup\` — $SETUP_JSON. @@TODO@@: say why each command is needed before the gate.
- \`gate\` — \`$GATE_COMMAND\`, green when its last lines contain \`$GATE_GREEN\`, about
  $GATE_MINUTES minute(s).
README

harness_log "wrote $FIXTURE_DIR"
harness_log "next: replace facts.md, review-brief.md and accept/accept.py (and the @@TODO@@ lines in the READMEs), then run: harness/check-fixture.sh $NAME"
