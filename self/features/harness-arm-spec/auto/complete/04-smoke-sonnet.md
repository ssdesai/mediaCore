# 04 — smoke: arm spec paths end to end (section 8c)

feature: agentTooling/harness-arm-spec — plan 4 of 5 (build). Base-arm experiments gain
`--arm-spec-path <label>=<path>,…` (`experiment.json` `arm_spec_paths`): each cell then
reads its spec from its own worktree at the arm's path instead of the shared spec
worktree, and the prompts say that spec is never to be edited.

Add a smoke section 8c that drives `new-experiment.sh --arm-spec-path` and one real
`new` cell through `run.sh`.

Depends on: 03-driver-sonnet.md. The contract is `harness/new-experiment.sh` and
`harness/run.sh` as plan 03 left them (search both for `arm_spec_paths` /
`ARM_SPEC_PATHS` / `SPEC_SOURCE`) and `harness/lib.sh`'s `# Arm spec paths` block; read
them before writing assertions — never assert a message you have not read.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none in this plan).

Pinned facts:
- `harness/tests/smoke.sh` section 8b is lines 1172-1265; section 9 starts at 1267. Read
  8b whole: insert 8c between them, reusing 8b's variables (the restructure commit,
  `BASE_ARM_NEW`, `BASE_ARM_NEW_SHA`, the base sha, its marker file) and its
  `base_arm_refusal` helper (1197-1208) or a sibling of it.
- Assertions are `check "<label>" "<shell expression string>"` (`smoke.sh:72-75`).
- The shared spec is the fixture's `SPEC.md` (`SPEC_TREE="$REPO-fx-$FIXTURE_NAME"`, line 87).
- 8b's cells are on branches `smokeBasedNullOld` / `smokeBasedNullNew`, so 8c's
  experiment needs `--override <fixture>=<another stem>` (e.g. `smokeArmSpecced`) to not
  collide; read how earlier sections pass `--override`.

## Files

- Modify `harness/tests/smoke.sh`

## Section 8c — arm spec paths

1. **Scaffold.** `new-experiment.sh smokeArmSpec` with the same fixture × `null`,
   `--base-arms old=<base>,new=<restructure ref>`,
   `--arm-spec-path old=SPEC.md,new=<the restructure commit's marker file>` and the
   override. Check: exit 0; `experiment.json` has `.arm_spec_paths.old == "SPEC.md"` and
   `.arm_spec_paths.new` the marker path.
2. **Refusals**, each non-zero and naming what the message names (read the messages):
   `--arm-spec-path` without `--base-arms` (`needs base_arms`); with `--agent-tooling`
   and no `--base-arms`; a label `mid` that is not a base arm; only `old=SPEC.md` (base arm
   `new` has no path); `new=/abs/x.md`; `new=sub/../x.md`; `new=` a path absent at the
   restructure commit (`does not exist at`); and `old=<the marker file>`, which exists at
   `new`'s commit but not at the base (proves the check is per arm's commit).
3. **Hand-edited experiment.** Copy the scaffolded `experiment.json` into a sibling
   experiment dir and delete `base_arms` with jq: `run.sh --dry-run` exits non-zero, prints
   no `branch:` line, and names `needs base_arms`.
4. **Dry run** of `smokeArmSpec`: a `spec:` line naming the marker path and `own tree`
   for arm `new`, and `SPEC.md` for arm `old`; no `worktree add --detach` line for either.
5. **Full run** of the `new` cell only (`--only "<fixture>:null:new"`, as 8b does), with
   `--no-cleanup` if needed to read the brief (or read it from the branch with
   `git show <branch>:plans/features/<slug>/BRIEF.md` — read how earlier sections inspect
   a finished cell and match it). Check: exit 0; the brief names
   `<cell tree>/<marker path>` and contains `this arm's own copy`, and does not contain
   `The read-only spec worktree at`; the row (last line of the experiment's
   `results.jsonl`) has `spec_source == "arm"`, `spec_path` the marker path,
   `arm_kind == "base"`, `arm == "new"`.
6. **Shared rows.** Over the smoke run's earlier ordinary ledger (the first
   `results.jsonl` the script wrote — find its variable), the last row has
   `spec_source == "shared"` and `spec_path == "SPEC.md"`.

Clean up any worktree you kept with `--no-cleanup` the way earlier sections do.
