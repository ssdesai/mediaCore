# 01 — tests: `harness/tests/arm-spec.sh`

feature: agentTooling/harness-arm-spec — plan 1 of 5 (build). Base-arm experiments gain
`--arm-spec-path <label>=<path>,…` (`experiment.json` `arm_spec_paths`): each cell then
reads its spec from its own worktree at the arm's path instead of the shared spec
worktree, and the prompts say that spec is never to be edited.

Write the offline test for the lib half of the feature, and register it in the gate. It is
red until plan 02 lands; that is expected.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below (none in this plan).

Pinned facts:
- Mirror the structure of `harness/tests/arm-base.sh:1-99` (shebang, `set -uo pipefail`,
  constants block, `pass`/`fail`/`check`, `mktemp -d` WORK with an explicit template under
  `${TMPDIR:-/tmp}` and a cleanup trap, `lib_call() { ( source "$HARNESS_DIR/lib.sh"; "$@" ) 2>&1; }`).
  Read that range first.
- `harness_fill_template <file>` (`harness/lib.sh:646-680`) reads every value from
  `HARNESS_<NAME>`; read that range. `harness_build_isolation <repo> <tree>`
  (`lib.sh:684-695`) sets `HARNESS_SIBLINGS`, `HARNESS_TREE`, `HARNESS_ISOLATION` from
  `git -C <repo> worktree list`.
- After plan 02, `harness_build_isolation` also sets `HARNESS_SPEC_RULE` and
  `HARNESS_SPEC_PROVENANCE` from `HARNESS_SPEC_SOURCE` (`shared` when unset or empty,
  `arm`, anything else dies). Arm-mode texts contain the phrases `never to be` and
  `this arm's own copy`; shared texts contain `checked` / `out detached at the commit this
  experiment pins` (method templates) and `The read-only spec worktree at` (isolation).
- After plan 02, `lib.sh` has `harness_check_arm_spec_paths <base_arms json> <arm_spec_paths json>`:
  returns 0 silently when the second argument is `{}`, `null` or empty; otherwise dies
  (non-zero, message on stderr, via `harness_die`) when base arms is empty/`{}`, when the
  value is not an object of strings, when a label is not a base arm, when a base arm has
  no path, or when a path is empty, absolute, or has a `..` component. Messages name the
  offending label or path; the no-base-arms one contains `needs base_arms`.
- The prompts to fill, in this order (paths relative to a harness dir):
  `methods/plans/template.md`, `methods/direct/template.md`,
  `methods/direct-bare/template.md`, `methods/null/template.md`,
  `templates/review-preamble.md`, `templates/rework-preamble.md`.
- Gate registration: `self/gate.sh:544` is
  `record "harness arm base self-test" bash harness/tests/arm-base.sh`.

## Files

- Create `harness/tests/arm-spec.sh`
- Modify `self/gate.sh`

## `harness/tests/arm-spec.sh`

Options: `--write-expected` (write the expected file instead of comparing) and
`--from-ref <ref>` (fill with the harness as it was at `<ref>`: extract it with
`git -C "$REPO_ROOT" archive "$ref" harness | tar -x -C "$WORK/ref"` and use
`$WORK/ref/harness` as the harness dir for the byte-identity section only). `REPO_ROOT`
is the checkout this script lives in (`HARNESS_DIR`'s parent). The expected file is
`$HARNESS_DIR/tests/arm-spec.shared.md` (named constant). Usage errors exit 2.

Sections, each through `check`:

1. **Shape checks** (`lib_call harness_check_arm_spec_paths`), with
   `BASE='{"old":"<40 a>","new":"<40 b>"}'`:
   - `{"old":"spec.md","new":"spec/README.md"}` → exit 0, no output.
   - `{}` and the literal `null` → exit 0.
   - base arms `{}` with a non-empty paths object → non-zero, output contains `needs base_arms`.
   - `{"old":"spec.md","new":"spec/README.md","mid":"x.md"}` → non-zero, names `mid`.
   - `{"old":"spec.md"}` → non-zero, names `new`.
   - `/abs/spec.md`, `../spec.md`, `spec/../x.md`, `spec/..` and `""` as `new`'s path →
     each non-zero, naming the path (skip the naming check for `""`).
   - `{"old":1,"new":"x"}` and `"abc"` → non-zero.
2. **Shared mode is byte for byte the base.** Build a function `fill_all <harness dir>`
   that, in a subshell: `source <dir>/lib.sh`; makes a throwaway git repo
   `$WORK/repo` (`git init -q`, one empty commit with a fixed author via `-c user.name=t
   -c user.email=t@t`) if absent; unsets `HARNESS_SPEC_SOURCE`; calls
   `harness_build_isolation "$WORK/repo" "$WORK/repo"`; then overrides `HARNESS_SIBLINGS`
   and `HARNESS_TREE` with fixed strings (the mktemp path must not reach the output);
   sets every scalar in the fill loop's name list (`lib.sh:656-661`, except `TREE` and
   `SIBLINGS`) to the fixed value `v-<NAME>` — e.g. `HARNESS_SPEC_TREE=v-SPEC_TREE`; sets
   `HARNESS_PREV_OUTCOME=v-PREV_OUTCOME`; then for each prompt in order prints a line
   `===== <relative path> =====` followed by `harness_fill_template <dir>/<path>`.
   Under `--write-expected` write `fill_all <dir>` (dir = the `--from-ref` extract, else
   `$HARNESS_DIR`) to the expected file and exit 0. Otherwise check the expected file
   exists, then `cmp -s` it against `fill_all "$HARNESS_DIR"`; on a difference print
   `diff -u` (first 40 lines) before failing.
3. **Arm mode.** Same fixed values but `HARNESS_SPEC_SOURCE=arm`,
   `HARNESS_SPEC_TREE=v-TREE` (the tree itself) and `HARNESS_SPEC_PATH=spec/README.md`.
   For each of the six prompts: no `@@[A-Z_]+@@` left; the isolation part (every prompt
   that has an `## Isolation` heading) contains `this arm's own copy` and does not contain
   `The read-only spec worktree at`. For the three method templates (plans, direct,
   direct-bare): the output contains `v-TREE/spec/README.md`, contains `never to be`, and
   does not contain `out detached at the commit this experiment pins`.
4. **Unknown source.** `HARNESS_SPEC_SOURCE=bogus` → `harness_build_isolation` exits
   non-zero naming `bogus`.

End with a `passed`/`failed` summary line and `exit $(( failures > 0 ))`, as
`arm-base.sh` does.

## `self/gate.sh`

Directly after line 544, add:

```bash
record "harness arm spec self-test" bash harness/tests/arm-spec.sh
```
