# 05 — docs: arm spec paths

feature: agentTooling/harness-arm-spec — plan 5 of 5 (build). Base-arm experiments gain
`--arm-spec-path <label>=<path>,…` (`experiment.json` `arm_spec_paths`): each cell then
reads its spec from its own worktree at the arm's path instead of the shared spec
worktree, and the prompts say that spec is never to be edited.

Document the feature in every README and design doc that describes arms, prompts, the
experiment and row shapes, and the tests.

Depends on: 01–04. The code is the source of truth: read `harness/lib.sh`'s
`# Arm spec paths` block and `harness_check_arm_spec_paths`; search `new-experiment.sh`
and `run.sh` for `arm_spec_paths`, `ARM_SPEC_PATHS` and `SPEC_SOURCE` (you have no
shell, so no `git diff`); and read `harness/tests/arm-spec.sh`
and `smoke.sh`'s section 8c before writing. Describe what they do, not what this plan
predicts.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Facts the docs must carry:
- Option: `new-experiment.sh --base-arms … --arm-spec-path <label>=<path>,…`;
  `experiment.json` `arm_spec_paths{<label>: <path>}?`, only with `base_arms`, one path per
  base arm, relative, no `..`, a file at that arm's commit.
- With it: the cell's `SPEC_TREE` is its own worktree, `SPEC_PATH` the arm's path, no
  shared spec worktree for that cell; the prompts say the spec is never to be edited (the
  method templates' `@@SPEC_PROVENANCE@@`, the isolation paragraph's `@@SPEC_RULE@@`,
  both set by `harness_build_isolation` from `HARNESS_SPEC_SOURCE`). Without it the
  prompts are byte for byte the base's, held by `harness/tests/arm-spec.sh` against
  `harness/tests/arm-spec.shared.md` (generated with `arm-spec.sh --write-expected
  --from-ref <ref>` from that ref's templates, never hand-edited).
- Row and state: `spec_source` (`"shared"` | `"arm"`) and `spec_path` on every row; absent
  on older rows — read absent as `"shared"` and the fixture's `spec.path`.
- Refusals: without `--base-arms` (so with `--agent-tooling` or `--programs` alone); a
  label not a base arm; a base arm with no path; absolute or `..`; missing at the arm's
  commit; `run.sh` refuses the same shapes in a hand-edited `experiment.json` and a path
  missing from the cell's tree at setup.
- The `null` method and the program templates keep their spec lines; program cells cannot
  have base arms, so they never see arm mode.

## Files

- Modify `harness/README.md` — Contents rows for `lib.sh` (the new helpers and
  constants), `new-experiment.sh` (the option and its refusals), and a new row for
  `tests/arm-spec.sh`; "Arms" (`:249-263`, a paragraph after the base-arm one); "Stages"
  step 1 (the spec worktree is not added for an arm-spec cell); `experiment.json` shape
  line and bullets (`:485-509`); the ledger row shape line and bullets (`:542-576`).
- Modify `harness/SPEC.md` — a new `## 16. Arm spec paths (added 2026-11-04)` at the end,
  in the voice of §15 (`:759-797`): `harness-arm-spec` (`self/features/harness-arm-spec/`),
  the problem in two sentences, then the facts above.
- Modify `harness/EXPERIMENTS.md` — in "Setting up the arms" (`:107-168`), a short
  paragraph: comparing two shapes of a repo's spec (a monolith against a split) needs
  base arms *and* `--arm-spec-path`, otherwise both arms read the fixture's one spec.
- Modify `harness/templates/README.md` — the `isolation.md` row: its last bullet is
  `@@SPEC_RULE@@`, filled by `harness_build_isolation` by spec source.
- Modify `harness/methods/README.md` — wherever it lists the placeholders the harness fills
  (around `:9-11`), add `@@SPEC_PROVENANCE@@` and say what it carries.
- Modify `harness/tests/README.md` — table rows for `arm-spec.sh` and
  `arm-spec.shared.md` (mirror the `scorecard-programs.cells.md` row), the run-alone list,
  the gate paragraph (six tests now; step `harness arm spec self-test`), and a paragraph
  for smoke's section 8c after 8b's.
- Modify `self/PROJECT_FACTS.md` — the "Tests" bullet listing `harness/tests/*.sh`
  (`:181-186`): add `harness/tests/arm-spec.sh`.

Keep each edit to what changed; do not rewrite surrounding prose.
