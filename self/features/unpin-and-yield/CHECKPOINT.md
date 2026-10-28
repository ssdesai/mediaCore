# Checkpoint: unpin-and-yield

status: committed
updated: 2026-10-03T00:10:03Z
gate: all checks passed (109 checks, none skipped)

## Slices
- [x] acceptance tests — self/tests/manifest-unpin.sh (U1–U11), self/tests/subagent-capture.sh
      phase Y (Y0–Y7), self/tests/capture-from-worktree.sh F8–F9 (committed red)
- [x] 1. manifest.py: unpin-session / unpin-subagent / unexclude-subagent, shared
      `agent_id_refusal` and `print_frozen_note`
- [x] 2. capture_planning.py: `corpus_copies`, `other_feature_pins`, yield arm,
      `yielded_agent_ids`, info lines
- [x] 3. check_claims 5-tuple + `pin_over_parent_advice`
- [x] manifest-unpin.sh registered in self/gate.sh (bash -n list and record)
- [x] 4. docs: analysis/README.md, TEMPLATE.md, LIFECYCLE.md rule-3 line, AGENT_PLANS.md
      exclude_subagents bullet, self/tests/README.md, PROJECT_FACTS.md commands line,
      two BACKLOG entries (cross-repo pin over parent; humanNetworkMap cleanup)
- [x] gate green, commit `unpin-and-yield: build`

## Learned
- the manifest's `subagents` pin of this implementer was written by the coordinator
  mid-build; committed as found.
- reachable_agent_ids is filled before the selection arms, so a yielded id is never "lost".

## Resume
- nothing to resume: the review pass (`./run-review.sh --self unpin-and-yield`) is next.
