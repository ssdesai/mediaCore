# 01 — review: readme-index-check

Review the branch against the spec below, never against any builder's report. "No findings"
is a legitimate verdict; do not invent findings to have something to write. Fix local
findings in the pass; escalate structural ones (`AGENT_PLANS.md` → "Review plans").

## What the feature was supposed to do

`CONVENTIONS.md` → "READMEs" says each folder's `README.md` indexes its files, but the
rule has not held in consuming repos: files go unlisted. This feature adds a mechanical
check that a consumer's gate can run, opt-in, shipped from agentTooling.

1. **A shared, read-only README-index checker.** For every tracked folder with a
   `README.md`, it reports each tracked file and each direct subfolder of that folder that
   the README never names, and exits non-zero if there is any. The recognition rule, the
   repo-owned ignore list (folders or files with legitimately no entry: fixtures,
   generated files), the treatment of generated READMEs (`CONVENTIONS.md` → "Generated
   READMEs": checked against the repo-owned file the header names, or skipped) and the
   report-only mode (lists missing entries, exits 0, so a consumer can adopt before it is
   clean) are all decided and **documented** by the feature. It must not edit anything.
2. **Wired into `self/gate.sh`**, with agentTooling's own READMEs made to pass it (missing
   entries added; folders that legitimately have none, such as `self/features/<slug>/`
   manifests and their `auto/`, `verify/`, `review/` queues, covered by the ignore list,
   not by padding READMEs).
3. **Adoption documented** for consumers: where the call goes in a consumer's `gate.sh`
   (`templates/plans/gate.sh`, updated if that is the right place, with its
   `template-version` bumped as the template-version tests require), a short note in
   `CONVENTIONS.md` → "Keeping READMEs up to date" that the gate enforces the index, and a
   docs-only description of the companion per-repo test checking each README Rule 1 field
   list against its schema, citing musicMap's `types.conformance.ts` as the model. That
   test is per-repo and is **not built here**.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **Read-only.** The checker writes nothing: no file, no index, no `__pycache__` (the gate
  runs python with `-B`; a new python module must be invoked so it leaves no cache).
- **Default turns no consumer's gate red.** The shipped template gate must not fail a
  consumer on its own after a subtree pull: the call is absent from, or non-failing in,
  the seeded `templates/plans/gate.sh` by default; adoption is an explicit opt-in in the
  consumer's gate. Check what a consumer with an unlisted file sees after pulling and
  re-syncing.
- **Exit codes.** Missing entries → non-zero; none → 0; report-only mode → always 0 on
  missing entries; a usage or environment error (not a git checkout, bad ignore file) is
  distinct and loud, never a silent pass. A folder with no `README.md` is not checked.
- **Tracked files only** (`git ls-files`): untracked and git-ignored files and folders
  are never reported. Direct children only: a file in a subfolder is that subfolder's
  README's business. A subfolder counts as named when its name appears in the README.
- **Generated READMEs are never expected to carry a consumer's entries.** The chosen
  treatment is documented, and a consumer's `plans/README.md` (generated from
  `templates/plans/README.md`) neither fails the check nor is asked to be edited.
- **The recognition rule is stated once** in the checker's docs and matches the code
  (name match, boundaries, case); no false pass from a name that is merely a substring
  of another word (e.g. `gate.sh` inside `self/gate.sh` is acceptable only if the docs say
  so; `gate` inside `integrate` for an extensionless name must not count).
- **bash 3.2 / stdlib-only** per `self/PROJECT_FACTS.md`; shell scripts added to the
  gate's `shell_scripts` list (`bash -n`), python to the `py_compile` list. Any new test
  lives in `self/tests/`, is recorded in `self/gate.sh`, and is listed in
  `self/tests/README.md`; it is offline and builds a throwaway repo in `mktemp -d`.
- **Scope.** `harness/` and `analysis/` are in flight on another feature and are not
  edited. `.claude/` is not edited. No model name appears in any committed file. Nothing
  repo-specific enters `templates/`. The per-repo Rule 1 conformance test is described in
  docs only, not built.
- **READMEs current.** Every folder the diff touches has a README that names every new
  file and describes changed behaviour (top-level `README.md`, `templates/plans/README.md`
  if the template changed, `self/tests/README.md`); `CONVENTIONS.md` carries the short
  enforcement note. `self/PROJECT_FACTS.md` Layout/Tests sections stay true.
- **Gate.** `./self/gate.sh` ends `all checks passed`, and the new check runs in it
  against agentTooling's own tree and passes honestly (not via an ignore list that
  swallows real indexes).

## Verdict

First line of `plans/review-report.md`-equivalent output: `Verdict: clean` or
`Verdict: escalated`, as `AGENT_PLANS.md` → "Review plans" specifies.
