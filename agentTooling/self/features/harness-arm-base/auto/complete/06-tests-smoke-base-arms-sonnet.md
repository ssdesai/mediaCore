# 06 — tests: base arms and reading fields in the smoke test

**Feature `harness-arm-base`, plan 6 of 9.** The experiment harness gains arms that differ
by a commit of the measured repository (`base_arms`) beside agentTooling arms, and records
per-cell reading metrics beside the cost figures.

Summary: add a base-arm section to `harness/tests/smoke.sh` (scaffold, refusals, dry run,
one full cell), and assert the new row fields on rows the smoke test already writes.

Depends on: `01-base-arms-driver-sonnet.md`, `02-reading-metrics-sonnet.md`,
`03-scorecard-sonnet.md`. Read `harness/lib.sh`'s new constants
(`HARNESS_ARM_KINDS_EXCLUSIVE_MSG`, `HARNESS_BASE_ARMS_NO_PROGRAMS_MSG`,
`HARNESS_BASE_ARM_REPO_RULE`) and `run.sh`'s `dry_run_cell` before writing the greps.

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

Pinned facts (all in `harness/tests/smoke.sh`):
- Helpers and names already defined: `check "<label>" "<shell condition>"`, `$WORK`,
  `$REPO` (the consumer; `origin` is a bare remote), `$BASE_SHA` (the smoke base, line
  371), `$FIXTURE_NAME` (`smoke`), `$NEW_EXPERIMENT`, `$RUN`, `$RESULTS` (the first full
  run's ledger; its line 1 is the unpinned null cell), `$PIN_DIR` (section 6's
  experiment), `$PIN_SUBJECT_PREFIX`, `$PRICED_CELL_RESULTS` and `priced_cell_row`
  (section 9c2). The fixed-names block is lines 57–~210.
- Section 6 (lines 962–1026) is the model for the new section: scaffold with
  `"$NEW_EXPERIMENT" … --consumer "$REPO"`, refusals as `check "…" "! '$NEW_EXPERIMENT' …"`,
  a dry run to a file and greps, then `"$RUN" "$DIR" --consumer "$REPO" --only
  "<fixture>:null:<arm>" --no-cleanup`, printing the output when it fails. Section 8
  (lines 1088–1152) shows a prep commit made in a throwaway worktree off `$BASE_SHA`.
- A base-arm cell is named `<stem><Method><Arm>`: stem `smokeBased`, method `null`, arm
  `new` → `smokeBasedNullNew`; its worktree is `$REPO-smokeBasedNullNew`.
- The full run's sessions leave no transcript, so its row's three reading fields are
  `null`; the priced cell's fake implementer leaves a transcript with no tool calls in its
  worktree's project directory, so its row's fields are `0`.
- bash 3.2, `set -uo pipefail`, no `set -e`; every literal a named constant in the
  fixed-names block; no model names.

## Files

- `harness/tests/smoke.sh` — modify
- `harness/tests/README.md` — modify

## `harness/tests/smoke.sh`

1. Fixed names, after the control-run block (~line 105):
   ```bash
   # The base-arm run: arms that differ by a commit of the measured repository — `old` the
   # smoke base, `new` a restructure commit cut from it on a branch pushed to origin.
   BASE_ARM_EXPERIMENT="smokeBaseArms"
   BASE_ARM_STEM="smokeBased"
   BASE_ARM_OLD="old"
   BASE_ARM_NEW="new"
   BASE_ARM_OLD_BRANCH="smokeBasedNullOld"
   BASE_ARM_NEW_BRANCH="smokeBasedNullNew"
   BASE_ARM_TREE="$REPO-$BASE_ARM_NEW_BRANCH"
   BASE_ARM_PREP_BRANCH="smokeRestructure"
   BASE_ARM_PREP_TREE="$WORK/restructure-prep"
   BASE_ARM_MARKER_RELPATH="plans/restructure-marker.md"
   BASE_ARM_UNKNOWN_SHA="0000000000000000000000000000000000000000"
   BASE_ARM_REPO_RULE_TEXT="runs from, and lives on"
   ARM_KINDS_EXCLUSIVE_TEXT="never both"
   BASE_ARMS_NO_PROGRAMS_TEXT="does not combine with programs"
   ```
2. In section 6, after the check `pinned row carries the arm and the agentTooling commit`,
   add `check "pinned row's arm_kind is agent_tooling" "[[ \$(jq -r '.arm_kind' '$PIN_DIR/results.jsonl') == agent_tooling ]]"`.
   After the check `unpinned row carries an empty arm`, add one asserting line 1 of
   `$RESULTS` has `arm_kind == ""` and `read_files_before_edit`, `read_bytes_before_edit`
   and `readme_bytes_read` all `null` (no transcript: not measured).
3. In section 9c2, after the `cost_method_reported_usd` check, add
   `check "priced cell: the reading fields are measured (0 — the fake's transcript holds no tool calls)" "priced_cell_row '.read_files_before_edit == 0 and .read_bytes_before_edit == 0 and .readme_bytes_read == 0'"`.
4. A new section between section 8's last check and `# ── 9. Program cells` (~line 1153),
   headed `# ── 8b. Base arms: the arms differ by a commit of the measured repository ──`
   and `echo "=== smoke: base arms ==="`:
   - **Prep.** In a worktree at `$BASE_SHA` on `$BASE_ARM_PREP_BRANCH`, write the marker
     file, commit `smoke restructure`, record `BASE_ARM_NEW_SHA`, remove the worktree,
     push the branch to `origin` quietly. Check the new sha differs from `$BASE_SHA`.
   - **Scaffold.** `new-experiment.sh "$BASE_ARM_EXPERIMENT" --fixtures "$FIXTURE_NAME"
     --methods null --base-arms "$BASE_ARM_OLD=$BASE_SHA,$BASE_ARM_NEW=$BASE_ARM_PREP_BRANCH"
     --override "$FIXTURE_NAME=$BASE_ARM_STEM" --no-review --no-rework --prediction …`.
     Checks: exit 0; `.base_arms.old == $BASE_SHA` and `.base_arms.new == $BASE_ARM_NEW_SHA`
     (the branch resolved to its full sha); `has("agent_tooling") == false`; the README
     lists both arm branches.
   - **Refusals** (each a fresh experiment name and `--override` stem; each exits non-zero
     and its output contains the text named): `--base-arms new=no-such-ref` →
     `$BASE_ARM_REPO_RULE_TEXT`; `--base-arms new=$BASE_ARM_UNKNOWN_SHA` (fetched by sha,
     still absent) → `$BASE_ARM_REPO_RULE_TEXT`; `--base-arms …` with `--agent-tooling
     head=HEAD` → `$ARM_KINDS_EXCLUSIVE_TEXT`; `--base-arms …` with `--programs x` →
     `$BASE_ARMS_NO_PROGRAMS_TEXT`; label `v2` → non-zero.
   - **Hand-edited experiments.** Copy the scaffolded `experiment.json` with jq into two
     new experiment directories: one adding `agent_tooling: {head: <BASE_SHA>}` (both
     kinds), one adding `programs: ["x"]`. `run.sh --dry-run` on each exits non-zero,
     prints no `branch:` line, and names `$ARM_KINDS_EXCLUSIVE_TEXT` /
     `$BASE_ARMS_NO_PROGRAMS_TEXT` respectively.
   - **Dry run** of the scaffolded experiment: exit 0; `branch:  *$BASE_ARM_OLD_BRANCH` and
     `branch:  *$BASE_ARM_NEW_BRANCH` both present; a `base:  *arm new at
     $BASE_ARM_NEW_SHA` line; no `pinned to upstream` line.
   - **Full run** `--only "$FIXTURE_NAME:null:$BASE_ARM_NEW" --no-cleanup`: exit 0 (print
     the output when not); the tree holds the marker file; `git -C "$BASE_ARM_TREE"
     merge-base --is-ancestor "$BASE_ARM_NEW_SHA" HEAD` succeeds; the branch log since
     `$BASE_ARM_NEW_SHA` has no `$PIN_SUBJECT_PREFIX` subject; the tree's `agentTooling`
     is still the base's symlink (`-L`); the row has `arm == "new"`, `arm_kind == "base"`,
     `base == $BASE_ARM_NEW_SHA`, `agent_tooling == ""`, `fixture == "smoke"`; the
     experiment's `SCORECARD.md` contains `new (base ${BASE_ARM_NEW_SHA:0:7})` and
     `base arms:`.

## `harness/tests/README.md`

After the control-arm paragraph (the one beginning "Last, the control arm"), add a
paragraph describing section 8b in the same register: the restructure commit cut from
the smoke base on `smokeRestructure` and pushed; `new-experiment.sh --base-arms
old=<base>,new=smokeRestructure` writing `base_arms` with full shas and no
`agent_tooling`; the five refusals and the two hand-edited `experiment.json` refusals;
the dry run naming both branches and the `base:` line with no pin; the full `new` cell cut
at the restructure commit (marker present, no pin commit, `agentTooling/` still the
symlink) and its row's `arm`, `arm_kind: "base"`, `base`, empty `agent_tooling`, and the
scorecard's `new (base <sha7>)`. Then add one sentence to the "pinned arm" paragraph (the
one beginning "Then a pinned arm") that the pinned row carries `arm_kind:
"agent_tooling"` and the unpinned row `arm_kind: ""` with the three reading fields
`null`, and one to the priced-cell bullet that its row's reading fields are `0`.
