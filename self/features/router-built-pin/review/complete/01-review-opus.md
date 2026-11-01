# 01 — review: router-built-pin

## What the feature was supposed to do

The session that runs `feature-start.sh` without `--pin` is the feature's **router**. It
is recorded in `<slug>/routing.json` and its cost is routing overhead, never the
feature's. When that same session then builds the feature, the build cost is reported as
routing overhead and the feature's total shows only its review. That happened twice on
2026-09-23. This feature makes it a refusal at the close:

- `feature-close.sh` refuses, before the PR, when the feature's routing record names a
  session that no manifest in the corpus pins in `sessions`, and that session's
  transcript shows it working in this feature's worktree. Working means a line whose
  `cwd` is at or under `<launched_in>/.worktrees/<slug>`, or an `Edit`/`Write`/
  `NotebookEdit` tool call whose path is at or under it. The refusal names the session
  and the remedy command, and says that nothing was written and no PR was opened.
- The predicate lives in `analysis/routing.py`, with a CLI entry point the close calls.
  `feature_worktree_path` and `WORKTREES_DIR_NAME` move there from `capture_planning.py`,
  which imports them back.
- The remedy is `manifest.py [--self] <slug> pin-session <id>`. It adds the id to the
  fence's `sessions[]` idempotently and leaves the rest of the file as it was. Because
  the manifest is a cost record, a re-run of the close passes the dirty-files check and
  the capture commits the pin.
- `self/BACKLOG.md` gains an entry for re-render drift in annotated frozen reports.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect
`analysis/routing.py`, `analysis/capture_planning.py` (the import only),
`analysis/manifest.py`, `feature-close.sh`, `self/tests/routing-record.sh` (R12),
`self/tests/feature-lifecycle.sh` (RB), the READMEs that describe those, and
`self/BACKLOG.md`.

## Contracts to hold it to

- **No false refusal on the intended flow.** A router whose transcript stays in the
  primary checkout (its `cwd` is the primary, and it only runs `feature-start.sh`, reads
  and greps) is never refused. Neither is a feature with no routing record, nor one whose
  router is pinned in *any* manifest's `sessions`, nor one whose router's transcript
  cannot be found.
- **Path containment is by path component.** `.worktrees/<slug>-two` is not under
  `.worktrees/<slug>`.
- **The worktree is derived as the capture derives it.** It uses the one
  `feature_worktree_path`, from the record's `launched_in` (the primary), so a `--self`
  feature in a vendored copy and an ordinary one each resolve their own.
- **Fail closed.** If the check itself cannot run, the close refuses, as the stray check
  does. It never proceeds on a crash.
- **The refusal comes before anything is written.** No commit, no PR call and no stamp
  happens before it. Once the router is pinned, the same close exits 0 and the pin rides
  the `<slug>: cost records` commit.
- `pin-session` is idempotent, rejects an empty id, and changes only `sessions` in the
  fence. `FENCE_KEY_ORDER` and the one-key-per-line shape are kept.
- Every existing router fixture is launched in the primary and never enters a worktree, so
  every existing check in `feature-lifecycle.sh` and `routing-record.sh` still passes.
- The moved helpers behave identically for `capture_planning.py`'s claim roots.
- The code reads like the rest of the files: named constants, bash 3.2, the `if ! X="$(…)"`
  shape for a checker whose return code is its contract.
- The READMEs describe the refusal, the predicate, the command and the moved helpers
  (CONVENTIONS.md → "Keeping READMEs up to date"). `LIFECYCLE.md`/`README.md` list the
  close's refusals, so the list must be complete.

Out of scope: a concurrent feature, `litellm-pricing`, edits `pricing.py`, the report's
rates footer and README entries about pricing, and it adds its own `BACKLOG.md` entry. It
does not touch `routing.py`, `feature-close.sh` or `manifest.py`.

## Verdict

"No findings" is a legitimate verdict. Report only defects against the contracts above,
each one with the concrete sequence of events that triggers it.
