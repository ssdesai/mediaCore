# harness-cloud-pins — builder's notes

Hand build, coordinated from the cloud session on `claude/brave-planck-no5foj`, the
branch `claude-md-chain` (#104) had just merged from.

## Rulings

- **Identity is the URL, resolution is per machine.** A fixture must carry nothing that
  is one machine's. The resolver's order (override, local checkout, hint, search, clone)
  puts the explicit before the inferred and never guesses between two checkouts: a
  search hit must name the same `owner/repo` as its origin, folded for case because the
  cloud clones are lower-case. Linked worktrees are excluded from the search by comparing
  `--git-dir` with `--git-common-dir`; without that, `vinylcatalogue-exportStoreDirect`
  beside `vinylcatalogue` would have been found by its origin and had worktrees added
  beside *it*.
- **The old path fields stay as hints, with a warning.** The two existing fixtures keep
  running on the owner's laptop unchanged; in a container they fail with the field to
  add named, instead of a `cd` into a path that does not exist.
- **One forge seam, the lifecycle's.** `forge.sh` was already the one piece of
  agentTooling that talks to the forge, and it reads its own checkout's origin, so the
  harness runs the copy vendored in the checkout it asks about. `HARNESS_GH_BIN` had
  no other use and is gone rather than kept as an alias.
- **A pin replaces the tree; it does not pull.** `git subtree pull --squash` cannot
  reach an older upstream commit (the squash chain only goes forward), which is why the
  hand recipe used `git archive | tar`. The harness does the same, from a checkout of
  `HARNESS_AGENT_TOOLING_URL`, and the pinned copy's own `sync-plans.sh` rewrites the
  generated files. Its exit status reports drift in the repo-owned stubs — the smoke
  repo's `gate.sh` has no template version, a real consumer's lags — which every arm
  shares, so it is logged, not fatal.
- **Labels are letters.** `exportStoreDirectAfter2` reads; `exportStoreDirectV22` does
  not say where the label ends and the repeat begins.
- **Both costs in a comparison.** The review and rework passes run inside the tree, under
  the pinned `CONVENTIONS.md`, so to-green differs by arm for two reasons; to PR-open is
  the method alone. The scorecard prints both against the band.
- **The merged-manifest exception.** The start's "a container pushes one branch, so it
  holds one feature" check read every tracked manifest at HEAD; after a merge, HEAD is
  `origin/main` and carries the merged feature's manifest naming the very branch the
  platform assigns the next session. A manifest `origin/main` already holds is a finished
  feature's: `started_features_on` skips it (so `update.sh`'s lookup and the session
  orientation agree) and the start's inline loop skips it against the feature's own base.
  `self/tests/cloud-start.sh` S2 holds it. Bootstrapping that fix on this very branch
  needed the fix in the tree before the start could run, and the start refuses a dirty
  tree, so the three edited files were hidden from `git status` with
  `git update-index --skip-worktree` for the one start and unhidden after it; the start
  commit carries only the feature directory, as it always does.

- **The coordinator does not build (owner's rule, 2026-10-30, mid-feature).** This
  feature was hand-built up to its first gate run, which is the last time that happens:
  the coordinator's context is for deciding and briefing; building, testing, debugging
  and drafting go to the cheapest model that can do them (Sonnet for implementation and
  debugging, Haiku for mechanical edits, Opus only for the harness's review pass and for
  plan authoring), and the method is chosen by whose context fills, not by diff size.
  The remainder of this feature — verification, the record of the rule in
  `self/PROJECT_FACTS.md` and `LIFECYCLE.md`, the commits — was delegated to Sonnet.

- **An arm equal to the base is the control arm, and it still gets its pin commit
  (round 2 ruling).** When the fixture's base already vendors the arm's commit, the
  extract and the sync change nothing and `git commit` had refused with "nothing to
  commit". That arm is the natural control — EXPERIMENTS.md builds every arm off the same
  prep commit — so the pin commits with `--allow-empty`: the branch then records which
  version it ran under exactly as the other arms do, and `do_setup`'s re-run guard (the
  pin subject in `BASE..HEAD`) keeps working. Skipping the commit instead would have
  left the control arm's branch indistinguishable from an unpinned cell.
- **The gate runs the harness (round 2 ruling).** `self/gate.sh` syntax-checks every
  shell script under `harness/`, compiles `scorecard.py`, and runs `scorecard-arms.sh`
  and `smoke.sh`; both are offline and need only what the gate already requires. The
  cost is the smoke test's running time on every gate, which is the price of the harness
  being covered by anything other than someone remembering to run it.

## What was measured

- In this container (Claude Code 2.1.314): `gh auth status` fails and `gh api` works;
  `python3.13`, `uv`, node 22 and `/opt/pw-browsers` are present; clones are
  `/home/user/<repo>` in lower case with `https://github.com/ssdesai/<repo>` origins
  (mediaCore's at `/home/user/ssdesai/mediacore`, which the default root does not reach —
  `HARNESS_REPO_ROOTS` or `HARNESS_REPO_DIR_MEDIACORE` does).
- `git archive HEAD | tar` of agentTooling: 9,072,640 bytes.
- `harness/tests/smoke.sh` on Linux: `WORK` empty, the repo at `/repo`, the fakes at
  `/bin/claude` and `/bin/forge.sh` (`/bin` → `/usr/bin`), twenty log files at `/`. The
  two fake binaries were removed; the directories and logs at `/` in this container were
  left for the owner (a removal there is not the agent's to make).

## Left undone

- The two humanNetworkMap fixtures' `repo.url` / `spec.url`, and the A/B itself (manifest
  → "Deliberately excluded").
- A `harness_version` that names an agentTooling commit from inside a vendored copy
  (`update.sh --check`'s split would do).
