# 03 — driver: `--arm-spec-path` in `new-experiment.sh` and `run.sh`

feature: agentTooling/harness-arm-spec — plan 3 of 5 (build). Base-arm experiments gain
`--arm-spec-path <label>=<path>,…` (`experiment.json` `arm_spec_paths`): each cell then
reads its spec from its own worktree at the arm's path instead of the shared spec
worktree, and the prompts say that spec is never to be edited.

Wire the option through scaffolding and the driver, and add `spec_source` / `spec_path` to
every row.

Depends on: 02-lib-templates-sonnet.md. Read `harness/lib.sh`'s `# Arm spec paths`
block and `harness_check_arm_spec_paths`, `harness_arm_spec_path_ok`,
`harness_arm_spec_path_for` and the spec-source branch in `harness_build_isolation`
before editing — they are the contract; do not re-implement any shape check here.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none in this plan).

Pinned facts:
- bash 3.2, `set -uo pipefail`, no `set -e`; `if …; then …; fi` over `cond && cmd`.
- In `run.sh`'s `set_template_vars`, `HARNESS_SPEC_SOURCE` must be set **before**
  `harness_build_isolation` is called; it chooses the prompts' spec wording.

## Files

- Modify `harness/new-experiment.sh`
- Modify `harness/run.sh`

## `harness/new-experiment.sh`

Read lines 1-100, 160-200 and 270-330 first.

- Usage (line 10) and the doc comment (25-36): add `[--arm-spec-path <label>=<path>,…]`
  after `--base-arms`, with one comment line: each base arm reads its spec at `<path>` in
  its own tree, at its own commit, instead of the shared spec worktree; every base arm
  needs one.
- Parse `--arm-spec-path` beside `--base-arms` (line 70) into `ARM_SPEC_PATHS`
  (declared beside `BASE_ARMS`, line 53).
- Beside the refusals at 94-95: `[[ -z "$ARM_SPEC_PATHS" || -n "$BASE_ARMS" ]] || harness_die "$HARNESS_ARM_SPEC_NEEDS_BASE_ARMS_MSG"`.
- After the base-arm block (164-176): when `ARM_SPEC_PATHS` is set, build
  `ARM_SPEC_PATHS_JSON` from its `<label>=<path>` pairs the way `BASE_ARMS_JSON` is built
  (a pair without `=` dies `--arm-spec-path takes <label>=<path>: <pair>`; a repeated label
  dies naming it), then `harness_check_arm_spec_paths "$BASE_ARMS_JSON" "$ARM_SPEC_PATHS_JSON"`,
  then for each label: its sha from `BASE_ARMS_JSON`, and refuse unless
  `git -C "$CONSUMER_ROOT" cat-file -t "$sha:$path"` prints `blob` —
  `harness_die "$HARNESS_ARM_SPEC_PATHS_KEY: $label: $path does not exist at $sha (a file, at the arm's commit)"`.
  Default `ARM_SPEC_PATHS_JSON='{}'`.
- The experiment.json jq (274-289): `--argjson arm_spec_paths "$ARM_SPEC_PATHS_JSON"` and
  `+ (if ($arm_spec_paths | length) > 0 then {arm_spec_paths: $arm_spec_paths} else {} end)`,
  mirroring `base_arms` at 279/286.
- The README it writes (base-arm line at 321): when set, one line per arm saying where its
  spec is read (`- arm <label>: spec <path> in its own tree`), mirroring that line's style.

## `harness/run.sh`

Read lines 90-230, 270-330, 420-440, 690-870 and 915-935 first.

- Globals (96-100): add `SPEC_SOURCE` and `ARM_SPEC_PATHS_JSON`.
- At the hand-edit refusals (925-928): read `ARM_SPEC_PATHS_JSON` from the experiment
  (`jq -c ".$HARNESS_ARM_SPEC_PATHS_KEY // {}"`), read the base arms object the same way,
  and call `harness_check_arm_spec_paths` on the two, prefixing nothing (the helper's
  message names the key). This refuses arm spec paths without base arms, which also covers
  an experiment with `agent_tooling` or `programs` and no `base_arms`.
- `resolve_cell` (132-174): after `SPEC_TREE` is computed (line 170), set
  `SPEC_SOURCE="$HARNESS_SPEC_SOURCE_SHARED"`; when `ARM_BASE` is non-empty and
  `harness_arm_spec_path_for "$ARM_SPEC_PATHS_JSON" "$ARM"` prints a path, set
  `SPEC_SOURCE="$HARNESS_SPEC_SOURCE_ARM"`, `SPEC_TREE="$TREE"` and `SPEC_PATH` to that
  path. If `TREE` is not yet set at that point, move the assignment after the line that
  sets it — read the function to see where it is. `SPEC_PATH` from `read_fixture_fields`
  (line 190) must not overwrite it afterwards: check the call order.
- `set_template_vars` (208-225): `HARNESS_SPEC_SOURCE="$SPEC_SOURCE"` before
  `harness_build_isolation`.
- Setup (315-319) and the resume path (433-436): add the shared spec worktree only when
  `SPEC_SOURCE` is shared. When it is arm, after the cell worktree exists, refuse unless
  `[[ -f "$TREE/$SPEC_PATH" ]]`:
  `harness_die "arm $ARM: spec $SPEC_PATH is not in the cell's tree at $BASE"`.
- Dry run: line 813 — for arm, print instead
  `say "  spec:          $SPEC_PATH in the cell's own tree (arm $ARM; reference only, never edited)"`;
  line 833 — skip the `dry … worktree add --detach` line for arm.
- State and row: write `spec_source` and `spec_path` to the state file where `arm_kind` is
  written (865), and add `--arg spec_source "$SPEC_SOURCE" --arg spec_path "$SPEC_PATH"`
  and `spec_source: $spec_source, spec_path: $spec_path` (right after `spec_commit`) to the
  row jq (735-769). Every row carries them, shared included.
