# 74 — tests: sync-plans.sh --check and update.sh

Feature: sweep-and-check — the weekly cost sweep, a pre-run lint of a feature's plan
corpus, drift detection for repo-owned files and the consumer update, each as a script
(manifest: `self/features/sweep-and-check/README.md`). Plan 2 of 8 build plans.

Write `self/tests/sync-check.sh`: the contract of `sync-plans.sh --check`, of the
`template-version` line, and of `update.sh`, all of which plan 77 implements. RED until
plan 77 lands.

Independent of other plans (77 implements what this asserts).

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- Test shape: read `self/tests/feature-lifecycle.sh:53-140` — `TMP="$(mktemp -d)"`,
  `AT="$(cd "$(dirname "$0")/../.." && pwd)"`, `ok`/`fail`/`check` helpers, a `fails`
  counter, exit 1 when any failed, a `trap` removing `$TMP`. That file also shows how a
  throwaway git repo with a bare `origin` is made and how commits are given an identity
  (`git -c user.name=… -c user.email=…` or the `GIT_AUTHOR_*` variables) — reuse it.
- `sync-plans.sh` resolves everything from its own location: `REPO_DIR` is its parent's
  parent, `PLANS_DIR=$REPO_DIR/plans`, `TEMPLATE_DIR=<its dir>/templates/plans`. So a copy
  of `sync-plans.sh`, `update.sh` and the whole `templates/` tree into
  `$TMP/consumer/agentTooling/` is a complete consuming-repo fixture.
- `git subtree` is available (`git subtree add --prefix=<p> <repo> <ref> --squash`,
  `git subtree pull …`). It needs a clean working tree and a real commit on both sides.
- bash 3.2; never touch the real checkout; assertion 8 reads `$AT` and writes nothing.

## Files

- create `self/tests/sync-check.sh`
- modify `self/tests/README.md`

## The contract under test (this block is repeated verbatim in plan 77)

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

## `self/tests/sync-check.sh`

**Fixture A — a consuming repo.** `$TMP/consumer` is `git init`ed with one commit;
`$TMP/consumer/agentTooling/` holds copies of `$AT/sync-plans.sh`, `$AT/update.sh` and
`$AT/templates/`. `S="$TMP/consumer/agentTooling/sync-plans.sh"`. Run the plain sync once
to seed `plans/`. Assertions (each a `check` with its number in the label):

1. `$S --check` → rc 1; output has the five `in-sync    plans/` stub lines, three
   `in-sync    plans/<script> (template-version N)` lines with N = 2, 2, 1 in that order,
   one `unfilled   plans/PROJECT_FACTS.md` line, and a last line
   `plans/ needs attention: 1 item(s) above.`
2. append a line to `plans/PROJECT_FACTS.md` → `--check` rc 0, last line
   `plans/ is in sync with agentTooling/templates/.`
3. append a line to `plans/README.md`; copy it aside; `--check` → rc 1, a
   `STALE      plans/README.md` line, and the file is byte-identical to the copy (the
   check wrote nothing). Then the plain sync prints `synced     plans/README.md`, and
   `--check` is rc 0 again.
4. delete the `# template-version:` line from `plans/pr.sh` → `--check` rc 1 with a line
   starting `DRIFT      plans/pr.sh (template-version 0 < 2;`; the plain sync (no
   `--check`) also prints that DRIFT line and exits 1, and still prints
   `kept       plans/pr.sh`; restore the file from the template.
5. append a line below the `REPO-SPECIFIC` marker of `plans/gate.sh` → `--check` rc 0
   (drift is the version line, not the body).
6. `rm plans/worktree-setup.sh` → `--check` rc 1 with
   `missing    plans/worktree-setup.sh (never seeded; run sync-plans.sh)`; the plain
   sync recreates it (`created    plans/worktree-setup.sh`) and `--check` is rc 0.
7. `$S --bogus` → rc 2.
8. against the real checkout, read-only: for each of `gate.sh pr.sh worktree-setup.sh`,
   the version read from `$AT/templates/plans/<f>` is a non-empty integer and equals the
   version read from `$AT/self/<f>`.

**Fixture B — a subtree cycle.** `$TMP/upstream.git` bare; `$TMP/work` a clone whose
`main` commits `sync-plans.sh`, `update.sh` and `templates/` (the same copies) and is
pushed. `$TMP/consumer2` `git init`ed with an initial commit, then
`git subtree add --prefix=agentTooling "$TMP/upstream.git" main --squash`; run its
`agentTooling/sync-plans.sh`, append a line to `plans/PROJECT_FACTS.md`, commit
everything. Then commit a new file `MARKER.txt` in `$TMP/work` and push.

9. `(cd "$TMP/consumer2/plans" && ../agentTooling/update.sh --remote "$TMP/upstream.git")`
   → rc 0; `$TMP/consumer2/agentTooling/MARKER.txt` exists; output contains
   `  pull   agentTooling <- ` and `  sync   agentTooling/sync-plans.sh`; the newest
   commit subject on consumer2 starts with `Merge commit` or contains `Squashed`.
10. touch `$TMP/consumer2/untracked.txt`; commit `MARKER2.txt` upstream; `update.sh
    --remote …` → rc 1, output names `untracked.txt`, and `agentTooling/MARKER2.txt` does
    not exist. Remove the untracked file afterwards.
11. `"$TMP/work/update.sh"` → rc 1, output contains `source checkout`.
12. `update.sh --bogus` → rc 2.

## `self/tests/README.md`

Add one bullet for `sync-check.sh` in the shape of the others: the two fixtures, what is
asserted (the status words, the version line, the subtree cycle), and that it depends on
`git subtree` being available and on the three templates carrying a `template-version`
line.
