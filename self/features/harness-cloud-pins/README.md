# harness-cloud-pins: run an experiment anywhere, under any agentTooling version

The experiment harness could only run on the laptop its fixtures were written on, and
the one comparison it was built for — two agentTooling versions, same fixture — was still
done by hand. Three things fix that. A fixture names its repositories by URL (`repo.url`,
`spec.url`) and `harness_resolve_repo` in `harness/lib.sh` turns a URL into a main
checkout on whichever machine runs it: an environment override, a local checkout, the old
path as a hint, a search of the consuming repo's parent directory by origin identity, else
a clone — so the `/Users/<owner>/dev/…` paths the first fixtures carried are hints at most,
and a cloud container runs the same fixture from `/home/user`. The harness asks the forge
through `forge.sh` (`pr-find`, `pr-open` over REST), the vendored copy inside the checkout
it is asking about, instead of `gh pr view` / `gh pr create`, which a cloud container's
proxy refuses; `HARNESS_FORGE_BIN` replaces `HARNESS_GH_BIN` as the seam, and the `direct`
brief opens its PR the same way. And `experiment.json` may name arms —
`agent_tooling: {<label>: <sha>}`, written by `new-experiment.sh --agent-tooling
before=<ref>,after=<ref>` — a third cell axis: the setup stage replaces a fresh worktree's
`agentTooling/` with that upstream commit's tree, runs the pinned copy's `sync-plans.sh`
and commits `EXPERIMENT ARM (revert before merge): pin agentTooling to upstream <sha7>`
before anything reads the vendored copy; the branch is `<stem><Method><Arm><n>`, the
ledger row carries `arm` and `agent_tooling`, and the scorecard compares arms within each
fixture × method to PR-open and to green. On the way: the smoke test was writing its
throwaway repo and fake binaries at the filesystem root on Linux (`mktemp -d -t <prefix>`
is macOS-only), and a cloud session's assigned branch, reused after its feature merged,
was refused as "already carrying" the merged feature — `started_features_on` and the
start's own lookup now skip a manifest that `origin/main` already holds.

## Plans

| Plan | What it does |
|---|---|
| `review/complete/01-review-opus.md` | Round 1: reviews the diff against this paragraph and the contracts in the brief. |
| `review/complete/02-review-opus.md` | Round 2: the same review, after round 1's escalated tests were added. |
| `review/complete/03-review-opus.md` | Round 3: the same review, after round 2's two rulings were built (the control arm's empty pin commit, the gate running the harness). |

## Deliberately excluded

- The consumers' fixtures (humanNetworkMap `plans/experiments/fixtures/{exportStore,importedWhere}/fixture.json`
  still say `repo.path` / `spec.repo`): they run as hints with a warning until each
  gains `repo.url` and `spec.url`, which is one edit per fixture in that repo, briefed
  into its next propagation feature. `facts.md` prose such as "there is no `uv` on this
  machine" is likewise the fixture's to revise.
- The A/B of the traversal rule itself (`exportStore` × `direct` × {before PR 104, after}
  × 3): this feature makes it runnable; running it, and the scorecard metric for bytes read
  before the first edit, is the next feature.
- `harness_version` in the ledger row still records the driver checkout's HEAD, which in
  a vendored copy is the consuming repo's commit, not an agentTooling one. The arm's
  `agent_tooling` is the field that answers which version built the tree.
- The hook's Python reading of `started_features_on` (`attachable_branch` in
  `hooks/allow-repo-commands.sh`) does not skip merged manifests; it only decides a
  remedy's wording on a detached HEAD, and a merged branch's tip is never HEAD there.
- A subtree pull that can move a consumer *back* to an older agentTooling: not possible
  with `git subtree pull --squash`, and not needed — an arm replaces the tree wholesale
  (`harness/EXPERIMENTS.md` → "Setting up the arms" says why).

## Machine-readable

```json
{
  "slug": "harness-cloud-pins",
  "method": "hand",
  "plans": ["01-review-opus", "02-review-opus", "03-review-opus"],
  "branches": ["claude/brave-planck-no5foj"],
  "base": "main",
  "profile": "cloud",
  "gate": "green",
  "session_window": {"from": "2026-10-30T13:13:18.000Z", "to": "2026-10-30T14:34:46Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["2483ee85-6358-53d1-b3fe-c7f1f895ab08"],
  "subagents": ["a02cb78bdb73b4fa6", "a8250dea111b28fc2", "aa0d2c2b028b6e81e"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, the profile, the gate and `from`, with the id lists empty — and
`feature-capture.sh` stamps `to` on the branch, provisionally until the merge freezes it
(`agentTooling/LIFECYCLE.md`). `from` here was moved forward by hand from the session's
first instant (`2026-10-30T01:02:29.906Z`, which `claude-md-chain` already claims) to
the instant this feature's work began; `manifest.py set-window-from` only ever moves it
back. Only `slug`, `plans` and `branches` are required: `method` reads as `"plans"` when
absent, `base` as `main`, `session_window` as unbounded, and the four id lists as empty.
