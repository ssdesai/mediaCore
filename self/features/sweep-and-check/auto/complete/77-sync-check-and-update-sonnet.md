# 77 — sync-plans.sh --check, template-version lines, update.sh

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 5 of 8 build plans.

Give `sync-plans.sh` a read-only `--check`, stamp the three repo-owned templates and
their `self/` copies with a `template-version` line, and write `update.sh`. Plan 74's
`self/tests/sync-check.sh` asserts every line of the contract below.

Depends on: nothing at build time. `sweep-and-check/74` is the test.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- bash 3.2; `sync-plans.sh` already runs under `set -euo pipefail` — keep that, and
  remember a command whose non-zero status you want to inspect must be wrapped
  (`if cmp -s …; then`), never left bare.
- `sync-plans.sh` resolves `SCRIPT_DIR`, `REPO_DIR`, `TEMPLATE_DIR`, `PLANS_DIR` from its
  own location and lists the stubs in `GENERATED=( … )`. Its repo-owned files are handled
  in four near-identical `if [[ -f … ]]` blocks — collapse those into a loop over a
  `REPO_OWNED_SCRIPTS=(gate.sh pr.sh worktree-setup.sh)` constant plus the
  `PROJECT_FACTS.md` case, keeping the existing `kept`/`created` lines and their
  per-file hints verbatim.
- The header of each template script: `templates/plans/gate.sh` starts with a shebang
  and `set -uo pipefail`; `templates/plans/pr.sh` the same; `templates/plans/worktree-setup.sh`
  a shebang and `set -euo pipefail`. `self/gate.sh`, `self/pr.sh`, `self/worktree-setup.sh`
  are the self-hosted copies of the same three and are never generated.
- Every magic value is a named constant at the top of the file.
- The update script rewrites itself: `git subtree pull` replaces `update.sh` on disk while
  bash is still reading it. The whole body therefore lives in one function invoked on the
  last line — bash has parsed the function before the pull runs.

## Files

- modify `sync-plans.sh`
- create `update.sh` (executable)
- modify `templates/plans/gate.sh`, `templates/plans/pr.sh`, `templates/plans/worktree-setup.sh`
- modify `self/gate.sh`, `self/pr.sh`, `self/worktree-setup.sh`
- modify `README.md` (two Contents rows — see below)

## The contract (this block is repeated verbatim in plan 74)

```
sync-plans.sh [--check]                 any other argument: usage on stderr, exit 2
--check writes nothing. One line per file, status in a 10-wide left-aligned column, exactly
as the write path's "  synced     plans/…" lines are shaped:
  generated stubs, in GENERATED order (README.md interactive/README.md features/README.md
  features/TEMPLATE.md .gitignore):
    in-sync    plans/<rel>
    STALE      plans/<rel> (differs from templates/plans/<rel>; run sync-plans.sh)
    missing    plans/<rel> (run sync-plans.sh)
  repo-owned scripts, in this order (gate.sh pr.sh worktree-setup.sh):
    in-sync    plans/<f> (template-version <N>)
    DRIFT      plans/<f> (template-version <copy> < <template>; hand-merge, see agentTooling/README.md -> Updating)
    missing    plans/<f> (never seeded; run sync-plans.sh)
  then PROJECT_FACTS.md:
    in-sync    plans/PROJECT_FACTS.md
    unfilled   plans/PROJECT_FACTS.md (still the skeleton; fill it before authoring plans)
    missing    plans/PROJECT_FACTS.md (never seeded; run sync-plans.sh)
last line and exit code:
    plans/ is in sync with agentTooling/templates/.        exit 0
    plans/ needs attention: <N> item(s) above.             exit 1   (N = STALE+DRIFT+missing+unfilled)
template-version: a line `# template-version: <integer>` in the header of each of the
three template scripts and of every seeded copy, read with
  sed -n 's/^# template-version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <file> | head -n 1
A copy without the line is version 0. Versions after this batch: gate.sh 2, pr.sh 2,
worktree-setup.sh 1; self/gate.sh, self/pr.sh, self/worktree-setup.sh carry the same.
Without --check the write path is unchanged and is followed by the repo-owned part of
the report (the three scripts and PROJECT_FACTS.md — the stubs were just written), with
the same last line and exit code.

update.sh [--remote <url>] [--branch <name>]        any other argument: usage, exit 2
 1 exit 1 with a message containing "source checkout" when the directory holding it is
   the git toplevel (nothing to pull into)
 2 exit 1 listing the paths when `git status --porcelain` at the toplevel is non-empty
 3 git subtree pull --prefix=<prefix> <remote> <branch> --squash, from the toplevel;
   prefix = the script's own directory relative to the toplevel; non-zero → exit 1
 4 runs <toplevel>/<prefix>/sync-plans.sh (the copy the pull just refreshed) and exits
   with its status
prints "  pull   <prefix> <- <remote> <branch>" before 3 and "  sync   <prefix>/sync-plans.sh" before 4
```

## The version lines

Insert, as the line directly after the `set -…` line in each of the six scripts:

- `templates/plans/gate.sh` and `self/gate.sh`: `# template-version: 2` — version 1 was
  the gate before level labels (`gate.sh NN` → `gate-report.NN.txt`); 2 has them.
- `templates/plans/pr.sh` and `self/pr.sh`: `# template-version: 2` — version 1 cut a
  `review/<slug>` branch; 2 opens the PR from the current branch.
- `templates/plans/worktree-setup.sh` and `self/worktree-setup.sh`: `# template-version: 1`.

In each *template*, add two sentences to the header comment below the line: the
version is what `sync-plans.sh --check` compares a seeded copy against; bump it when
the body below `REPO-SPECIFIC` changes in a way seeded copies must merge by hand.

## `sync-plans.sh`

Parse `$1`: absent → write mode; `--check` → check mode; anything else → usage to
stderr, exit `USAGE_RC=2`. Implement the report as functions that return their item
count — `check_stubs` (in-sync/STALE/missing over `GENERATED`), `check_repo_owned`
(the three scripts by version, then `PROJECT_FACTS.md` by `cmp -s` against
`$TEMPLATE_DIR/PROJECT_FACTS.md`) — and a `finish <count>` that prints the last line
and exits. Check mode runs both; write mode runs the existing copy loop and the
repo-owned seeding, then `check_repo_owned` and `finish`. Read a version with the exact
`sed` from the contract in a `template_version <file>` helper that echoes `0` when
nothing matched. Rewrite the header comment's third paragraph to say `--check` exists,
what it reports, and that the write path ends with the same repo-owned report.

## `update.sh`

Header comment: what it does, the four steps, that its body is a function because the
pull rewrites the file. Constants: `DEFAULT_REMOTE="https://github.com/ssdesai/agentTooling.git"`,
`DEFAULT_BRANCH="main"`, `USAGE_RC=2`, `REFUSED_RC=1`. Resolve
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`,
`TOPLEVEL="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"`, and
`PREFIX="${SCRIPT_DIR#"$TOPLEVEL"/}"`; when `SCRIPT_DIR == TOPLEVEL` refuse per step 1.
Parse `--remote <url>` and `--branch <name>` with an arity guard (a value flag given
as the last argument is a usage error — mirror `feature-start.sh`'s handling). Steps 2–4
as the contract says, every git command as `git -C "$TOPLEVEL" …`. Last line of the
file: `main "$@"`, with `exit` inside `main` so nothing after the call is ever read.

## `README.md`

In the Contents table's "Installing/updating consumers" group, add a row for
`update.sh` ("From a consuming repo: refuse on a dirty tree, `git subtree pull
--squash`, then the freshly pulled `sync-plans.sh`") and extend the `sync-plans.sh`
row with "`--check` reports without writing: stale stubs, repo-owned scripts behind the
template's `template-version`, an unfilled `PROJECT_FACTS.md`". Plan 81 rewrites the
"Updating" section itself; leave it alone here.
