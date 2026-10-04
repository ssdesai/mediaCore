# Unpin, and a pinned delegate yields

Two loose ends from `router-brief-writes` (#76). **First**, nothing removes an id from a
manifest's fence: `pin-session` and `pin-subagent` only append, so the wave router pinned
to three humanNetworkMap features (`access-page`, `article-render-sandbox`,
`article-render-javascript`, router `756102ea-…`, about $4.33) and the
`exclude_subagents` lists hand-written to stop those features claiming each other's
delegates can only come out by editing the fence by hand, which the rules forbid. This
feature adds the three removers, so the cleanup is a script. **Second**, a session a
feature selects (by pin or branch) claims every delegate it spawned in the window, even
one another feature pins; `exclude_subagents` exists only to stop that, and has to be
hand-maintained in the selecting feature. This feature makes the capture do it: a
**parent-selected** delegate that another feature **pins** is left to that feature
(*yields*), so `exclude_subagents` is no longer needed for new work. Built direct, by
one implementer.

## The spec

### 1. `manifest.py` removers

Three subcommands, each the exact inverse of an existing writer and shaped like it
(`--self` first, `<slug>` next, as `pin-session`/`pin-subagent`):

| Command | List | Twin of |
|---|---|---|
| `unpin-session <id>` | `sessions[]` | `pin-session` |
| `unpin-subagent <agent-id>` | `subagents[]` | `pin-subagent` |
| `unexclude-subagent <agent-id>` | `exclude_subagents[]` | none — the list was only ever hand-written |

- Removes the one id, prints the new list in the twin's format (`sessions = [...]`,
  `subagents = [...]`, `exclude_subagents = [...]`), exit 0. Nothing else in the file
  moves — the diff is that one line.
- An id the list does not hold is a no-op: exit 0, nothing written, a line saying the
  list does not hold it.
- An empty id is refused, exit 1, file untouched. `unpin-subagent` and
  `unexclude-subagent` apply `pin-subagent`'s id validation (`AGENT_ID_RE`, the
  `agent-` prefix message) — same refusals, same exit 1.
- On a feature that already has a `planning.json`, print what `set-window-from` prints
  there: the fence is input to the next capture, and the frozen figure does not move
  until one runs (on the branch: `feature-capture.sh`; after the merge:
  `--recapture`).
- The manifest is in `COST_FILES`, so the dirty `README.md` passes the close's stray
  check and the capture commits it — the same path `pin-session` relies on. No change
  needed there; assert it holds.

### 2. The capture: a pinned delegate yields

In `capture_planning.capture_feature`'s subagent loop, the `parent_selected and
in_window(...)` arm (today `selected_by = "parent"`) gains one check first: if **another
feature pins this agent id**, skip it and record it as yielded. A delegate this feature
itself pins is still `"pinned"` (the pin arm comes first, unchanged), and
`exclude_subagents` still works exactly as today (frozen records and old manifests rely
on it).

"Another feature pins it" is the union of two sources, so the rule does not depend on
which feature captures first within one repo:

1. **Manifests reachable from this repo**: every feature manifest in this corpus under
   the primary checkout *and* under every worktree in `<primary>/.worktrees/*/` (same
   corpus-relative path — `self/features` under `--self`, `plans/features` otherwise),
   excluding this slug's own. A wave's pins sit on unmerged branches in sibling
   worktrees; the primary's copy alone would miss them. Use `roots`' existing primary
   resolution rather than a new path derivation; a manifest that does not parse is
   skipped, as `check_subagent_overlap` does.
2. **The claims ledger**: a claim on the id whose `(repo, slug)` differs from this one
   and whose `selected_by` is `"pinned"` — the cross-repo case, where no manifest is
   reachable.

Output and record:

- `planning.json` gains `yielded_agent_ids`: a sorted list of `{ agent_id, to }`, `to`
  being `<repo_name>/<slug>` of the pinning feature (the first found, manifest before
  ledger). Present always, `[]` when none, beside `excluded_agent_ids`.
- One info line per yielded id on the capture's output naming the pinning feature.
- A yielded id is **not** "lost" to `check_frozen_cost` on a recapture: its transcript is
  on disk, and dropping it is the rule working, exactly as a dropped cross-repo pin is
  handled today. Verify the guard, and add a case if it does trip.
- `check_claims`, the cross-repo ordering hole: when this capture **pins** an id the
  ledger holds as `"parent"` for another feature, the refusal stays (no record is
  rewritten behind its owner's back), but its message names the other feature and says
  its recapture will now yield the delegate — `feature-capture.sh --recapture` from the
  primary if merged, `feature-capture.sh` in its worktree if not.

### 3. Docs

- `analysis/README.md`: the `manifest.py` entry ("Eight subcommands" becomes eleven, each
  remover described as its twin's inverse), the subagent-routes paragraph (the yield rule,
  and `exclude_subagents` now needed only for records captured before it), and the
  `planning.json` field list (`yielded_agent_ids`), per README Rule 1.
- `templates/plans/features/TEMPLATE.md`: the `exclude_subagents` bullet says a pinned
  delegate now yields on its own, the list is kept for older records, and
  `unexclude-subagent` removes an entry; the `sessions` and `subagents` bullets name
  `unpin-session` / `unpin-subagent` as the way a pin comes out. `self/tests/sync-check.sh`
  and the generated stubs follow the template; run `sync-plans.sh --self`-equivalent
  checks the gate already runs.
- `ORCHESTRATION.md` / `LIFECYCLE.md`: only where they tell a reader to hand-edit
  `exclude_subagents` or say a pin cannot be removed. Grep them for `exclude_subagents`
  and `pin-session`; touch nothing else.
- `self/tests/README.md` for every test file touched or added.

### 4. Acceptance tests, written first

- `self/tests/manifest-pin-subagent.sh` (or a sibling `manifest-unpin.sh`, implementer's
  call — say which in the report): each remover removes, no-ops on an absent id, refuses
  an empty / malformed id with the file byte-identical, leaves every other fence line
  byte-identical, and prints the frozen-record note when `planning.json` exists.
- `self/tests/subagent-capture.sh` or `claims-ledger.sh` scaffolding (whichever already
  builds a parent session with delegates): **Y1** a parent-selected delegate pinned by a
  sibling manifest in `.worktrees/<other>/…` yields, `yielded_agent_ids` names it, the
  feature's cost excludes it; **Y2** the same with the pin only in the ledger
  (`selected_by: "pinned"`, other repo) yields; **Y3** a ledger claim by another feature
  with `selected_by: "parent"` does **not** yield (only a pin outranks); **Y4** this
  feature's own pin still wins (`"pinned"`, not yielded); **Y5** `exclude_subagents`
  still excludes as before and lands in `excluded_agent_ids`, not `yielded_agent_ids`;
  **Y6** the pinning feature's capture then succeeds with no double-claim refusal;
  **Y7** the `check_claims` refusal message for pin-over-parent names the other feature
  and the recapture.
- `./self/gate.sh` green.

## Plans

| Plan | What it does |
|---|---|
| `review/incomplete/01-review-opus.md` | Reviews the removers, the yield rule's two sources and the docs against the spec above |

## Deliberately excluded

- **Retiring `exclude_subagents`.** Frozen records and every manifest written before the
  yield rule read it; a recapture of one of those must select what it selected before.
  It stays read, gains a remover, and is described as legacy.
- **`exclude-subagent` (the writer).** Declined in `router-brief-writes`, 2026-10-02; the
  yield rule makes it less needed, not more.
- **Cleaning the three humanNetworkMap manifests.** That is work in that repo, after this
  merges and is pulled there (`pull-agenttooling-pr<N>`), on each feature's own branch:
  `unpin-session 756102ea-…`, `unexclude-subagent` per id, then re-run
  `feature-capture.sh` in its worktree. Another session is active on those branches;
  doing it from here would race it.
- **Yielding a *pinned* session's own cost**, or a branch-selected session another
  feature pins. Session sharing is already split by window (`session-share.sh`); this
  rule is about delegates only.

## Machine-readable

```json
{
  "slug": "unpin-and-yield",
  "method": "direct",
  "plans": ["01-review-opus"],
  "branches": ["unpin-and-yield"],
  "base": "main",
  "session_window": {"from": "2026-10-02T23:47:59Z", "to": "2026-10-03T00:12:38Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["eac89e2c-1ae1-431a-8ea2-96b237c1850e"],
  "subagents": ["a74f52c4de22409b6"]
}
```
