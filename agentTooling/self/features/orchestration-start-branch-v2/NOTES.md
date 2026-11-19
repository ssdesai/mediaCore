# orchestration-start-branch-v2 — notes

Rebuild of the parked `orchestration-start-branch` (4 rounds, branch deleted, owner ruling
2026-11-18), starting from the findings its reviews left in `self/BACKLOG.md`.

## Decisions

- **Cloud only, orchestrator records only.** The branch rule mirrors `feature-start.sh`'s
  cloud layout: under the local profile `--branch` is refused (the human creates branches
  there) and nothing else changes; a `--coordinator` record is a cost record registered from
  any branch, so it takes no `--branch` and is never refused for its branch. The profile is
  read through `env-profile.sh`, so the start now needs that adapter beside it and refuses,
  naming it, when it is missing or undecided — for an orchestrator record in a git checkout
  only.
- **Origin is asked, never the cache.** `git ls-remote -q --exit-code --heads origin
  refs/heads/<name>`: 0 refuses, 2 goes on, anything else refuses ("cannot ask origin"). No
  `origin` remote: only the local branch check applies.
- **Unmerged features' branches: not read off origin's `claude/*` branches.** Every pushed
  branch — an unmerged feature's included, since its manifest names its own branch — is
  already refused by the ls-remote above, whatever its manifest says. An unpushed one exists
  only in its own container, which no check here can see however many refs it reads. Reading
  each `claude/*` branch's manifests would add a fetch per branch and see nothing ls-remote
  does not already refuse. What IS read is `origin/main`'s tracked manifests (`ls-tree -z`),
  for a merged feature whose branch origin has since deleted: its name is still that
  feature's in every transcript's `gitBranch`, so reusing it would hand the orchestrator's
  transcript to that feature's capture.
- **NUL-separated enumeration.** `held_feature` (`ls-files -z`) and the new `branch_named_at`
  (`ls-tree -z`) read with `read -r -d ''`; a manifest directory with a non-ASCII name is
  found (orchestrator-role.sh V4, B5).
- **The record is committed, and pushed as a checkpoint, only on a branch `--branch` named.**
  On an assigned branch with no `--branch`, nothing changes: the orchestrator commits the
  record itself, as before.
- **The record move is approved outright.** An orchestrator's `git mv
  <tooling>/self/orchestrations/<slug> plans/orchestrations/<slug>` passes the allowlist only
  for its own record (the path `orchestrator_record` returns), from a vendored copy, from the
  consuming repo's root, to a destination not yet there; alone on the line the hook emits
  `allow` (`ORCHESTRATOR_MOVE_REASON`). Inside a longer allowlisted line it goes on to the
  ordinary judges like any other allowlisted write.

## Round 2 (round 1's review and audit escalated)

- **Review: the approved move failed with no `plans/orchestrations/`** — git tracks no empty
  directory, so that is the usual state. Chosen fix: options (a) and (b) together.
  `shared_rules.LEGACY_RECORD_MOVE` (and so `LEGACY_RECORD_REFUSAL`, which every caller prints)
  now leads with `LEGACY_RECORD_MKDIR` (`mkdir -p plans/orchestrations && `), and the hook
  approves that exact line for the record's own orchestrator, the bare `git mv` still too.
  No other `mkdir` joins the allowlist. Option (c), creating the folder on a refusal, was not
  taken: it breaks "a refusal writes nothing".
- **Audit: symlink escapes.** The record's path is no longer resolved: it is taken as the
  role lookup returned it and refused when it (or a directory above it) is a symlink (M71),
  and `plans/orchestrations` must resolve to itself, so neither `plans` nor
  `plans/orchestrations` is a symlink (M65, M66, M72, M59). H28 asserts each.

## Round 3 (round 2's review clean; its audit escalated)

- **`--branch +main` force-pushed origin's main.** `git check-ref-format --branch` accepts
  `+main`, and the checkpoint push `git push -u origin +main` reads it as a force refspec.
  Fixed twice over: the start refuses any `--branch` that is not a plain name
  (`BRANCH_NAME_PATTERN`, the hook's `ORCHESTRATOR_BRANCH_RE` shape; no `refs/`/`heads/` lead,
  no `..`), and `push_feature_branch` pushes `refs/heads/<b>:refs/heads/<b>`, so no caller's
  name can become another ref (this also hardens `feature-start.sh` and `run-review.sh`,
  which share the helper). orchestrator-role.sh B7 asserts the refusals and that origin's
  `main` is unchanged.
- This was the second escalated audit round, so per the owner's scope rule the round-3
  review waits for an owner ruling.

## Round 4 (round 3's review clean; its audit escalated; owner ruling 2026-11-19)

- **`--branch origin/main` shadowed the remote-tracking ref.** It passed round 3's
  plain-name check and cut a local `refs/heads/origin/main`, after which `origin/main` in
  that container named the orchestrator's branch. Owner ruling: stop patching spellings —
  `--branch` takes exactly `claude/<slug>`, the slug matching the shared `SLUG_PATTERN`, and
  everything else is refused before any write, naming `--branch claude/<slug>`. Round 3's
  `BRANCH_NAME_*` constants are gone; its explicit `refs/heads/<b>:refs/heads/<b>` push stays.
  B7 asserts `origin/main`, `origin/HEAD`, `origin/claude/x`, `+main`, `main`,
  `claude/Bad_Name` and the round-2 spellings, with origin's and the checkout's refs compared
  whole.
- Merged `origin/main` first (#168, `hook-silent-allow-sweep`): one conflict, in
  `self/BACKLOG.md`, resolved keeping both sides' changes. `feature-sync.sh` named in the
  orchestrator's message does not exist on this branch, so the merge was a plain `git merge
  origin/main`.

## Brief facts found untrue

- `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md` carries no `template-version` line and is
  not in `TEMPLATE_VERSIONS` (it is generated, overwritten every pull — `templates/README.md`),
  so there was no version to bump.
