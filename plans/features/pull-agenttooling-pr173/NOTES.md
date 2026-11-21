# NOTES: pull-agenttooling-pr173

## Owner ruling (2026-11-21), typed in this session

The round-3 audit's blocking finding is **accepted for this pull**. If
`agentTooling/analysis/roots.py` is replaced by a stub (or a symlink to one) that prints
`ok`, `orchestration-start.sh` goes on past a stranded record, where the base refused. The
owner's reasons: the head refuses more tampered inputs than the base (a crash,
`sys.exit(1)`, a missing `roots.py` and `print("ok"); sys.exit(1)` all went on under the base
and are refused now), and editing `roots.py` is no harder than editing
`orchestration-start.sh` itself. The review is clean. The PR is opened by hand, titled
`[deviations]`, with the review and audit reports unedited and this ruling listed; the owner
merges it with a merge commit.

Nothing under `agentTooling/` was edited for it: that tree is upstream's at `b9b7f2d4`, and a
local edit would be overwritten by the next pull.

## Backlog for agentTooling (`self/BACKLOG.md`), report only

Filed here, not in this repo's `plans/BACKLOG.md`, because the work is upstream's:

1. **Stubbed `roots.py` passes `orchestration-start.sh`'s refusal** (round 3, ruled accepted
   above). Suggested fix, if ever wanted: before asking the classifier, check that
   `roots.py`, `routing.py` and `shared_rules.py` are unchanged from `HEAD`, and refuse
   otherwise.
2. Rounds 1 and 2 non-blocking audit findings: an edited `analysis/roots.py` defeats the
   classifier (the rule should use the committed copy, or check inside the hook); only a
   record's last fence is counted (the rule should count a repo listed in any fence).
3. `run-review.sh` (around lines 440-447) adds the audit's stem to the manifest's `plans`
   without checking whether it is already listed, so a duplicate counts the audit's cost
   twice; its self-test is missing.
4. Round 3 non-blocking: `HTTPS_PROXY` / `GIT_SSL_NO_VERIFY` in the hook's environment are
   not checked by the own-push rule, and a stubbed `roots.py` still allows the move of a
   record that is not stranded. Both behave the same way on the base.

## Not done, on purpose

- The subtree squash commits `38d1e38` and `358887c` were flagged by a stop hook as
  unverified (no signature). They were not amended: each is the second parent of its pull's
  merge and carries the `git-subtree-split` trailer the next pull merges from.
