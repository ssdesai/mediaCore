# 02 — lib and templates: spec source, spec rule, path checks

feature: agentTooling/harness-arm-spec — plan 2 of 5 (build). Base-arm experiments gain
`--arm-spec-path <label>=<path>,…` (`experiment.json` `arm_spec_paths`): each cell then
reads its spec from its own worktree at the arm's path instead of the shared spec
worktree, and the prompts say that spec is never to be edited.

Add the lib constants and helpers, and make the prompts' spec wording depend on the spec
source while leaving every shared-mode prompt byte for byte as it is today.

Depends on: 01-tests-arm-spec-sonnet.md (its test is the contract; read
`harness/tests/arm-spec.sh` first).

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none in this plan).

Pinned facts:
- `harness/lib.sh:95-102` holds the arm constants (`HARNESS_ARM_LABEL_RE`,
  `HARNESS_ARM_KIND_BASE`, `HARNESS_BASE_ARMS_KEY`, `HARNESS_ARM_KINDS_EXCLUSIVE_MSG`,
  `HARNESS_BASE_ARMS_NO_PROGRAMS_MSG`, `HARNESS_BASE_ARM_REPO_RULE`); `harness_experiment_arms`
  is at `lib.sh:260-274` — mirror its jq style. `harness_die` is the fatal helper.
- `harness_fill_template` (`lib.sh:646-680`) and `harness_build_isolation`
  (`lib.sh:684-695`); read both. `harness_replace_literal <text> <pattern> <replacement>`
  sets `HARNESS_REPLACED` — never use `${t//p/$v}`.
- bash 3.2: no associative arrays; `set -uo pipefail`, no `set -e`.
- The three method templates each have, at `methods/plans/template.md:16-17`,
  `methods/direct/template.md:14-15`, `methods/direct-bare/template.md:14-15`, the text
  `— read-only, checked` ending one line and `   out detached at the commit this experiment pins. This is …`
  starting the next. `templates/isolation.md:20-21` (its last two lines) is the bullet
  `- The read-only spec worktree at \`@@SPEC_TREE@@\` is reference material, checked out`
  / `  detached at a pinned commit. Read it; never write to it.`

## Files

- Modify `harness/lib.sh`
- Modify `harness/templates/isolation.md`
- Modify `harness/methods/plans/template.md`, `harness/methods/direct/template.md`,
  `harness/methods/direct-bare/template.md`

## `harness/lib.sh`

1. After the arm constants block (line 102), add a `# Arm spec paths` block:

```bash
# Arm spec paths — experiment.json arm_spec_paths, new-experiment.sh --arm-spec-path
HARNESS_ARM_SPEC_PATHS_KEY="arm_spec_paths"
HARNESS_SPEC_SOURCE_SHARED="shared"
HARNESS_SPEC_SOURCE_ARM="arm"
HARNESS_ARM_SPEC_NEEDS_BASE_ARMS_MSG="arm_spec_paths (--arm-spec-path) needs base_arms (--base-arms): a spec path per arm means something only when each arm is a commit of the measured repository"
# The spec's wording in the prompts, by source. The shared texts are the base's own words,
# byte for byte (harness/tests/arm-spec.sh compares them with arm-spec.shared.md).
HARNESS_SPEC_PROVENANCE_SHARED="checked
   out detached at the commit this experiment pins"
HARNESS_SPEC_PROVENANCE_ARM="never to be
   edited: it is this arm's own copy, inside your tree"
HARNESS_SPEC_RULE_SHARED="- The read-only spec worktree at \`@@SPEC_TREE@@\` is reference material, checked out
  detached at a pinned commit. Read it; never write to it."
HARNESS_SPEC_RULE_ARM="- The spec at \`@@SPEC_TREE@@/@@SPEC_PATH@@\` is this arm's own copy, inside your tree.
  It is reference material: read it; never edit, move or delete it, and never commit a
  change to it."
```

2. Add `harness_check_arm_spec_paths <base_arms json> <arm_spec_paths json>` after
   `harness_experiment_arms`. Behaviour (the test in plan 01 pins it): second argument
   empty, `null` or `{}` → return 0. Otherwise: base arms empty/`null`/`{}` → die
   `$HARNESS_ARM_SPEC_NEEDS_BASE_ARMS_MSG`; not an object whose values are all strings →
   die `"$HARNESS_ARM_SPEC_PATHS_KEY must be an object of <label>: <path>"`; each key not in
   base arms → die `"$HARNESS_ARM_SPEC_PATHS_KEY: $label is not a base arm (base arms: <space-separated labels>)"`;
   each base arm with no key → die `"$HARNESS_ARM_SPEC_PATHS_KEY: base arm $label has no spec path — give every base arm one, or none"`;
   each path through `harness_arm_spec_path_ok` → die
   `"$HARNESS_ARM_SPEC_PATHS_KEY: $label: '$path' must be a file path relative to the tree, with no '..' component"`.
   Also add `harness_arm_spec_path_ok <path>`: false when empty, starting with `/`, or
   having a `..` component (split on `/`; `..` alone counts).
   And `harness_arm_spec_path_for <arm_spec_paths json> <label>`: prints the path or
   nothing (jq `-r '.[$l] // empty'`; empty/`null` input prints nothing).

3. In `harness_build_isolation`, after `HARNESS_ISOLATION` is read: choose by
   `${HARNESS_SPEC_SOURCE:-$HARNESS_SPEC_SOURCE_SHARED}` — `shared` → the two `_SHARED`
   texts, `arm` → the two `_ARM` texts, anything else → `harness_die "unknown spec source: <value>"`.
   Set `HARNESS_SPEC_PROVENANCE` to the provenance text, and substitute `@@SPEC_RULE@@`
   in `HARNESS_ISOLATION` with the rule text via `harness_replace_literal` (so the rule's
   own `@@SPEC_TREE@@`/`@@SPEC_PATH@@` are resolved by the later fill loop).

4. In `harness_fill_template`'s name list (line 657), insert `SPEC_PROVENANCE` before
   `SPEC_TREE`.

## `harness/templates/isolation.md`

Replace its last two lines (20-21) with the single line `@@SPEC_RULE@@`. Preserve
whether the file ends in a newline exactly as it does now (`$(cat)` strips one trailing
newline either way, so only the line content matters).

## The three method templates

In each, replace `checked` at the end of the spec line and `   out detached at the
commit this experiment pins` at the start of the next with `@@SPEC_PROVENANCE@@`, joining
the two lines, so the template reads (plans; direct and direct-bare keep their own tail
after `. This is`):

```
1. `@@SPEC_TREE@@/@@SPEC_PATH@@`, sections **@@SPEC_SECTIONS@@** — read-only, @@SPEC_PROVENANCE@@. This is your entire brief for *what
   to build*. It pins names; use them exactly.
```

Everything else in those files is unchanged.
