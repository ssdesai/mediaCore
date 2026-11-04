# 01 — base arms in the driver

**Feature `harness-arm-base`, plan 1 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`, `--base-arms old=<ref>,new=<ref>`) as
an alternative to agentTooling arms, and records per-cell reading metrics (files and bytes
read before the first edit, README bytes read) beside the cost figures.

Summary: add `base_arms` to `lib.sh`, `new-experiment.sh` and `run.sh` so each cell's
worktree is cut at its arm's commit instead of the fixture's `base`, and the row records
`arm_kind`.

Independent of other plans.

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts:
- bash 3.2: no associative arrays, no `${v^^}`; a possibly-empty array under `set -u` is
  expanded `${a[@]+"${a[@]}"}`. Scripts run `set -uo pipefail`, deliberately no `set -e`:
  use `if …; then …; fi`, not `cond && cmd`, where the status is not checked.
- Every meaningful literal is a named constant at the top of its file (lib.sh's constants
  block is lines ~16–170; `HARNESS_ARM_LABEL_RE='^[a-z]+$'` is at line 95).
- `harness_die` prints `ERROR: <msg>` and exits 1; inside `$(…)` it exits the subshell, so
  callers write `x="$(f)" || exit 1`.
- `harness_resolve_commit <repo> <ref> [<remote>]` (lib.sh:817) prints a full sha or
  returns 1; a 7–40-hex ref missing locally is fetched by sha once, no ref created.
- `CONSUMER_IDENTITY_REMOTE="origin"` (lib.sh:51); `CONSUMER_ROOT` is the measured repo.
- An arm line is `"<label> <sha>"`, or `"- -"` for no arm; both scripts loop them with
  `while read -r -u 3 arm_label arm_sha`. Keep that two-word shape.
- The existing agentTooling-arm error text `agent_tooling in <file> must be an object of
  <label>: <full sha>` is asserted by `harness/tests/smoke.sh` (`BAD_ARMS_SHAPE`): keep
  it byte for byte for the `agent_tooling` key.
- Never name a model anywhere in these files.

## Files

- `harness/lib.sh` — modify
- `harness/new-experiment.sh` — modify
- `harness/run.sh` — modify

## `harness/lib.sh`

After `HARNESS_ARM_LABEL_RE` (line 95) add:

```bash
# Arm kinds: what an experiment's arms vary — one kind per experiment.
HARNESS_ARM_KIND_AGENT_TOOLING="agent_tooling"   # experiment.json key agent_tooling
HARNESS_ARM_KIND_BASE="base"                     # experiment.json key base_arms
HARNESS_BASE_ARMS_KEY="base_arms"
HARNESS_ARM_KINDS_EXCLUSIVE_MSG="an experiment's arms vary one thing — the agentTooling version (agent_tooling, --agent-tooling) or the measured repository's commit (base_arms, --base-arms) — never both"
HARNESS_BASE_ARMS_NO_PROGRAMS_MSG="base_arms (--base-arms) does not combine with programs (--programs): a program pins its own base"
HARNESS_BASE_ARM_REPO_RULE="an experiment runs from, and lives on, the repository it measures (harness/EXPERIMENTS.md): push the commit there and name a ref that resolves in its checkout"
```

Replace `harness_experiment_arms` (lines 227–236, with its comment) by:

```bash
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
```

## `harness/new-experiment.sh`

1. Header (lines 3–35): add `[--base-arms <label>=<ref>[,<label>=<ref>]...]` to the synopsis
   beside `--agent-tooling`, and after the `--agent-tooling` paragraph a paragraph saying:
   `--base-arms` is the other kind of arm — each label names a commit of the measured
   repository (any ref its checkout resolves; a sha missing locally is fetched by sha from
   `origin` once), pinned to its full id and written as `base_arms: {<label>: <sha>}`;
   every cell's worktree is then cut at its arm's commit instead of the fixture's `base`,
   and nothing else changes. A commit that does not resolve in the measured repository is
   refused. `--base-arms` refuses `--agent-tooling` and `--programs` beside it. Then
   change `usage()`'s `sed -n '3,35p'` to the header's new last line.
2. Variables (line 45): add `BASE_ARMS=""`. Parser (after the `--agent-tooling)` case,
   line 61): `--base-arms) BASE_ARMS="${2:?--base-arms needs <label>=<ref>[,...]}"; shift 2 ;;`
3. After the `--noise-band` validation (line 83), before `harness_require_tools`:
   ```bash
   [[ -z "$ARMS" || -z "$BASE_ARMS" ]] || harness_die "$HARNESS_ARM_KINDS_EXCLUSIVE_MSG"
   [[ -z "$BASE_ARMS" || -z "$PROGRAMS" ]] || harness_die "$HARNESS_BASE_ARMS_NO_PROGRAMS_MSG"
   ```
4. After the agentTooling arms block (ends line 150) and before the `ARM_LINES=` line, add
   a block `# ── Base arms: each ref pinned to a full commit of the measured repository ─`
   that mirrors lines 138–150: `BASE_ARMS_JSON='{}'`; when `BASE_ARMS` is set, fetch
   `CONSUMER_IDENTITY_REMOTE` quietly in `CONSUMER_ROOT` (warn on failure, as line 141
   does); for each comma pair require `<label>=<ref>` (die `--base-arms takes
   <label>=<ref>: <pair>`), the label matching `HARNESS_ARM_LABEL_RE` (same message as line
   145), resolve with `harness_resolve_commit "$CONSUMER_ROOT" "$ref"
   "$CONSUMER_IDENTITY_REMOTE"`, and on failure die
   `base arm <label>: <ref> is not a commit of the measured repository <CONSUMER_ROOT> — $HARNESS_BASE_ARM_REPO_RULE`;
   log `base arm <label>: <ref> -> <sha>`; add it to `BASE_ARMS_JSON` with the same jq as
   line 149.
5. Replace line 153 so `ARM_LINES` reads whichever kind is set:
   ```bash
   ARM_SOURCE_JSON="$ARMS_JSON"
   if [[ "$BASE_ARMS_JSON" != '{}' ]]; then ARM_SOURCE_JSON="$BASE_ARMS_JSON"; fi
   ARM_LINES="$(jq -r 'if length == 0 then "- -" else to_entries[] | "\(.key) \(.value)" end' <<<"$ARM_SOURCE_JSON")"
   ```
   The collision loops below need no change: base-arm cells are named
   `<stem><Method><Arm><n>` exactly like agentTooling-arm cells.
6. The `jq -n` write (lines 245–258): add `--argjson base_arms "$BASE_ARMS_JSON"` and,
   after the `agent_tooling` clause,
   `+ (if ($base_arms | length) > 0 then {base_arms: $base_arms} else {} end)`.
7. The generated README (line ~291): after the agentTooling **Arms** bullet add one for
   `BASE_ARMS_JSON != "{}"`: `- **Arms:** each cell runs from the commit of this
   repository named in `experiment.json`'s `base_arms`, its worktree cut there instead
   of the fixture's `base`; everything else is the fixture's.` (Same `printf` shape and
   quoting as the existing bullet.)

## `harness/run.sh`

1. Line 93: add `EXPERIMENT_ARM_KIND=""; ARM_BASE=""; FIXTURE_BASE=""` beside the arm globals.
2. Before line 873 (`ARMS="$(harness_experiment_arms …)"`):
   ```bash
   EXPERIMENT_ARM_KIND="$(harness_experiment_arm_kind "$EXPERIMENT_JSON")" || exit 1
   if [[ "$EXPERIMENT_ARM_KIND" == "$HARNESS_ARM_KIND_BASE" && -n "$(jq -r '.programs[]?' "$EXPERIMENT_JSON")" ]]; then
     harness_die "$EXPERIMENT_JSON: $HARNESS_BASE_ARMS_NO_PROGRAMS_MSG"
   fi
   ```
3. `resolve_cell` (lines 127–136): after the `"-"` line, move a base arm's commit out of
   `ARM_SHA` (which is the agentTooling pin everywhere else) into `ARM_BASE`:
   ```bash
   ARM_BASE=""
   if [[ -n "$ARM" && "$EXPERIMENT_ARM_KIND" == "$HARNESS_ARM_KIND_BASE" ]]; then
     ARM_BASE="$ARM_SHA"; ARM_SHA=""
   fi
   ```
   and make the existing `[[ -n "$ARM_SHA" ]] || harness_die "arm $ARM names no agentTooling
   commit …"` check apply only when `ARM_BASE` is empty, with a sibling check for base
   arms: `arm $ARM names no commit of the measured repository in $EXPERIMENT_JSON`.
   After line 142 (`BASE="$(harness_json "$FIXTURE_JSON" .base)"`):
   ```bash
   FIXTURE_BASE="$BASE"
   if [[ -n "$ARM_BASE" ]]; then BASE="$ARM_BASE"; fi
   ```
   Everything downstream (`harness_resolve_commit` at setup, `worktree add … "${START_POINT:-$BASE}"`,
   the pin check's `$BASE..HEAD`, `harness_branch_has_commits`, `HARNESS_BASE` in
   `set_template_vars`, the row's `base`) then uses the arm's commit unchanged.
4. Add, next to `state_or` (line ~656):
   ```bash
   cell_arm_kind() {  # the row's arm_kind: agent_tooling or base for an arm, "" for none
     if [[ -n "$ARM" ]]; then printf '%s' "$EXPERIMENT_ARM_KIND"; fi
   }
   ```
5. `run_cell` (line 813, after `arm`): `harness_state_set_str "$STATE" arm_kind "$(cell_arm_kind)"`
   and `harness_state_set_str "$STATE" base "$BASE"`.
6. `build_ledger_row`: add `--arg arm_kind "$(cell_arm_kind)"` and the field
   `arm_kind: $arm_kind,` directly after `agent_tooling: $agent_tooling,`. `base` already
   carries `$BASE`, now the arm's commit for a base arm.
7. `dry_run_cell` (lines 765–776): change `[[ -z "$ARM" ]] || say "  agentTooling: …"` to
   test `ARM_SHA` instead of `ARM`, and the pin block's `if [[ -n "$ARM" ]]` to
   `if [[ -n "$ARM_SHA" ]]`; add after the agentTooling line:
   `[[ -z "$ARM_BASE" ]] || say "  base:          arm $ARM at $ARM_BASE (the fixture's own base $FIXTURE_BASE is not used)"`.
