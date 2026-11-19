# 07 — review: harness-arm-spec

feature: agentTooling/harness-arm-spec

## What the feature was supposed to do

An experiment with base arms (`--base-arms old=<ref>,new=<ref>`) gives each arm its own
commit of the measured repository, but before this feature every arm read one shared,
read-only spec worktree at the fixture's `spec.commit`. So an experiment comparing a
monolithic spec (old arm) against a split one (new arm, `spec/README.md` + `spec/NN-*.md`)
could not measure the split. The feature adds:

- `new-experiment.sh --arm-spec-path <label>=<path>,…`, recorded as
  `arm_spec_paths: {<label>: <path>}` in `experiment.json`.
- With it set, a cell's `SPEC_TREE` is the cell's own worktree and `SPEC_PATH` the arm's
  path; no shared spec worktree is added for that cell. The spec is still reference-only,
  and every generated prompt must say it is never to be edited now that it lives in the
  arm's own tree: the three method templates (`plans`, `direct`, `direct-bare`) through the
  new `@@SPEC_PROVENANCE@@` placeholder, and the isolation paragraph through its
  `@@SPEC_RULE@@` bullet, which every prompt that includes `@@ISOLATION@@` inherits.
- Without the option the generated prompts are byte for byte what they were at the base,
  asserted against `harness/tests/arm-spec.shared.md` (generated from the base's own
  templates, never hand-written).
- Every ledger row (and state file) gains `spec_source` (`shared` | `arm`) and
  `spec_path`.
- Refusals, in `new-experiment.sh` and (for a hand-edited `experiment.json`) `run.sh`:
  without `--base-arms` (which also covers `--agent-tooling` and `--programs`); a label
  that is not a base arm; a base arm with no path; an absolute path or one with a `..`
  component; a path missing at the arm's commit (`new-experiment.sh`; `run.sh` refuses a
  path missing from the cell's tree at setup).

Excluded: program cells (they cannot have base arms); any scorecard change; the
`null` method template and `program-*.md` templates keep their spec lines as they are
(they inherit the isolation bullet only).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **Byte identity without the option.** `harness/tests/arm-spec.sh` must fill the same
  set of prompts the driver fills (the three method templates, `null`, the review and
  rework preambles, isolation included) and compare them with `cmp` against
  `arm-spec.shared.md`. Check the expected file was generated from the base's templates
  (its `--from-ref` path) and that nothing in shared mode can differ: the shared values of
  `HARNESS_SPEC_RULE` / `HARNESS_SPEC_PROVENANCE` must reproduce the base text exactly,
  newlines and indentation included, and `program-stages.sh` (which calls
  `harness_build_isolation` without setting a spec source) must get the shared text.
- **Placeholder order.** `@@SPEC_RULE@@`'s value carries `@@SPEC_TREE@@`/`@@SPEC_PATH@@`;
  it must be substituted before those are, or a literal placeholder ships (the fill's
  unfilled-placeholder check would catch it only for names it scans).
- **Arm mode wording.** No arm-mode prompt may still say the spec is "checked out
  detached" or "never write to it" about a path that is the delegate's own work tree
  (that would forbid the build itself); it must say the spec file is never to be edited.
- **Refusals** — each of the six shapes above refused with a message naming the label or
  path, in `new-experiment.sh`; the shape checks shared with `run.sh` through one `lib.sh`
  helper, not duplicated.
- **Row shape.** `spec_source` and `spec_path` on every row, `harness/README.md` → "The
  ledger row" and `SPEC.md` updated with them; `experiment.json`'s shape line names
  `arm_spec_paths{<label>: <path>}?`.
- **Docs and index.** `harness/README.md` (Contents, Arms, `experiment.json`, row),
  `harness/SPEC.md` (a new section), `harness/EXPERIMENTS.md`, the templates, methods and
  tests READMEs, and `self/PROJECT_FACTS.md`'s test list name the new test; every new
  file has its README line (`check-readme-index.py`); `self/gate.sh` records the new test.
- **Conventions.** bash 3.2 (no associative arrays; `${a[@]+"${a[@]}"}` for maybe-empty
  arrays), `set -uo pipefail` without `set -e`, `mktemp -d` with an explicit template under
  `$TMPDIR`, named constants for messages and labels, no model named in any file.

Do not re-run tests or the smoke suite; the gate and verify did. A missing assertion is
the most valuable finding. "No findings" is a legitimate verdict.

## Verdict
