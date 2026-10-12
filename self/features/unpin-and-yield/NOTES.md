# Notes: unpin-and-yield

Rulings made during the direct build, one line of rationale each.

## Removers (`analysis/manifest.py`)

- **The removers rewrite only the one list value, in place, not the whole fence.** The pins
  re-render the fence (`render_fence`); on a fence in that shape the bytes are the same, so
  pin-then-unpin is still the identity (U2, U5d). But every `exclude_subagents` list was
  hand-written, and the humanNetworkMap manifests the cleanup targets are hand-written fences;
  re-rendering would move every other key. The in-place edit is parsed back and must equal
  the old fence less the id, or nothing is written (exit 1).
- **One id check, shared.** `agent_id_refusal(agent_id, verb)` is what `pin-subagent`,
  `unpin-subagent` and `unexclude-subagent` all call. The `agent-` refusal's wording moved
  from "pin the id without…" to "give the id without…", since it now serves removers too;
  the existing P4h assertion greps the unchanged part.
- **One frozen note, shared.** `print_frozen_note(args)` serves `set-window-from` and the
  three removers. Its text now names both routes the spec gives (on the branch:
  `feature-capture.sh`; after the merge: `feature-capture.sh --recapture`) instead of
  `capture_planning.py --recapture` alone; `manifest-window.sh` M6 still holds. Printed only
  when the fence was written — a no-op moved nothing a reader needs warning about.
- **Tests in a sibling file**, `self/tests/manifest-unpin.sh`, not `manifest-pin-subagent.sh`:
  the removers span three lists and a hand-written fence fixture the pin test has no use for.
- **COST_FILES**: asserted, not changed — U11 sources `plan-runner-roots.sh` and checks a
  dirty `self/features/<slug>/README.md` is not stray.
- `manifest-unpin.sh` is registered in `self/gate.sh` (the `bash -n` list and a `record`
  line) — the gate runs a named list, not a glob.

## The yield (`analysis/capture_planning.py`)

- **Where the scan looks** (`corpus_copies`): `roots.checkout_of(features_dir)`, then
  `roots.worktree_primary` (or the checkout itself), and the corpus path relative to that
  checkout joined onto the primary and onto each `<primary>/.worktrees/*`; plus
  `features_dir` itself if it is none of those (a legacy sibling). No new path derivation,
  and the other corpus is never read (F9). Order is primary, worktrees by name, then
  `features_dir`; the first manifest found names `to`, then the ledger.
- **The same slug in another copy is still "this feature"** — every copy's `<slug>/` is
  skipped, so a feature's own branch copy and its merged primary copy never yield to each
  other.
- **The ledger read is `selected_by == "pinned"` and `(repo, slug) != (this)`**, compared as
  the pair, never the slug alone. A parent claim never yields (Y3: the double-claim refusal
  stands).
- **The frozen guard needs no change.** `reachable_agent_ids` is filled before the selection
  arms, so a delegate a recapture newly yields is reachable, not "lost" — the same reason a
  dropped cross-repo pin is not. Covered by Y1 (and F8), both recaptures over a record that
  had priced the delegate.
- **Info lines print on the success path only**, after the result line and before the WARNs:
  `<slug>: agent-<id> yields to <repo>/<slug>, which pins it — …`. A refused capture writes
  nothing, so it yields nothing either.
- **`check_claims` now returns five fields** (`…, other_repo, other_selected_by`) so the
  refusal can tell pin-over-parent apart; it has one caller. The extra line names the other
  feature, `./feature-capture.sh [--self] <slug> --recapture` from its primary if merged and
  `./feature-capture.sh [--self] <slug>` in its worktree if not (`--self` when the claim's
  repo is `SELF_CORPUS_IDENTITY`).
- **Cross-repo pin over a parent claim is not closed.** When the parent-selecting feature is
  in another repo, its recapture sees this pin only through a `"pinned"` ledger claim, and
  the refused capture writes none — so the advised recapture would not yield. The refusal
  says so and points at `self/BACKLOG.md`; building a fix (a pin-intent record the refused
  capture may write without touching the other feature's claim) is beyond the spec.
- `session-claims.sh` counts manifest parses on the claimant index; the yield scan parses
  manifests through the same `parse_manifest` but outside that counted path, and the test
  stays green.
