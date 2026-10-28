# 95 — verify: shared-session share

feature: agentTooling/shared-session-share. The final verify. Read `self/gate-report.txt`
first; do not re-run `bash -n`, `py_compile`, or any test in it.

The batch's tests already cover the arithmetic (`self/tests/session-share.sh`), the claim
set and its three sources (`self/tests/session-claims.sh`), and the report side
(`self/tests/claims-ledger.sh` part B). **Read those three files before checking
anything** — they are the checklist of what is already covered, and re-performing them
here is the expensive way to learn nothing.

What they leave uncovered, and what this pass is for:

1. **The real corpus.** Run `python3 analysis/capture_planning.py --self --all` and
   `python3 analysis/report.py --self --all` against this checkout and confirm no frozen
   record's figures changed — `git diff --stat self/features` must show changes only to
   `also_claimed_by` and nothing else, since `--all` without `--recapture` may not
   re-derive money. Two of this corpus's own features (`tooling-backlog-2026-09-06` and
   `recovered-duration-lower-bound`) pin one session, so the new frozen-record warning
   should fire for them; confirm it names both and asks for `--recapture`, and do **not**
   run that `--recapture` — repairing the corpus is the human's call, not this pass's.
2. **A real shared re-capture, in a scratch worktree.** `git worktree add` a scratch tree
   at `HEAD`, and there re-capture exactly one of those two features with `--recapture`.
   Confirm its total falls, that `share_basis` names the other feature, and that the two
   figures now sum to the session's own cost. Never `git stash` — the plan queue is
   untracked working-tree state and stashing it destroys the run.
3. **Adversarial windows.** Three cases no test covers and the arithmetic must survive:
   two claims with identical `from` and `to` (a straight halving, no ordering ambiguity);
   a claim whose `from` is later than its `to` (`check_empty_window` already warns — the
   share must not divide by zero or claim a negative span); and a claimant list of one
   after the others are excluded by `exclude_sessions`, which must collapse back to the
   unshared path rather than leaving a `share_basis` of length 1 in the record.
4. **The unshared path is genuinely untouched.** Pick one feature in this corpus whose
   session no other feature claims, re-capture it in the scratch worktree, and diff the
   record against the committed one. Anything other than `captured_at`, `rates_source`
   and `excluded_session_ids` moving is a defect.

Fixes here stay local — a wrong assertion, a warning that names the wrong field, a drifted
README line. Anything needing a new function or a changed signature is a finding for the
review pass or the next batch, not an edit here.
