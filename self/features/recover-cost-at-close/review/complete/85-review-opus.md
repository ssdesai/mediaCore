# 85 — review: recover-cost-at-close

Read the diff and judge it. This brief was written from the spec before the build, not
from the builder's report; do not read `NOTES.md` or `CHECKPOINT.md` as evidence that a
contract holds — they say what the implementer believed. **"No findings" is a legitimate
verdict.** A pass that must produce findings produces speculative ones, and the next
batch spends turns disproving each.

Never redo verify's work: no re-running the gate, no building fixtures. If a question can
only be settled by running something, say so and move on — the highest-value output here
is a *missing assertion*, phrased as the check that would catch the defect forever.

## What the feature was supposed to do

Three reviews that ran to completion — exit 0, PR opened, verdict written — were recorded
at `$0` and the closes committed that zero into the cost records. musicMap `pin-ruff`'s
close printed `review $0.0000 (0.0%) ... time 8.0 min (partial)`; two vinylCatalogue
features closed on 2026-09-04 show the same shape.

The mechanism has three parts, and the feature fixes all three:

1. `plan-runner-lib.sh::write_usage_sidecar` builds the sidecar from the **last
   `type=="result"` event** of the `claude -p --output-format stream-json` stream. In
   these runs that event was absent, so `total_cost_usd`, `num_turns`, `duration_ms`,
   `usage.*`, `model_usage` and `tool_counts` are all null/zero/empty while `outcome` —
   computed from the exit code alone — says `"complete"`. Nothing on disk distinguished
   "this ran and cost nothing" from "this ran and nobody recorded what it cost".
2. `analysis/report.py::compute_cost_rollup` reads `total_cost_usd`, finds `None`, files
   the stem under `priced_without_cost`, emits one warning and `continue`s — so the
   bucket prints a literal `$0.0000` and only `(partial)` on the *time* figure hints that
   anything is wrong.
3. `analysis/recover_attempts.py` can price exactly this from the session transcript, and
   its loop is not gated on `outcome` — but it is only ever invoked from `sweep.sh`, the
   weekly cadence. `feature-close.sh` never calls it, so at close time recovery has
   simply not run and the zero is what the cost commit carries.

Deliberately **out of scope**, and not a finding: the root cause of the missing result
event on a 0-exit session (unknown, not reproducible, backlogged); `report.py`'s usage
index, its plan/LOC computation, its manifest-plan loading and the *summing* inside
`compute_cost_rollup` (a sibling feature owns those); and the runner's failed/complete
routing, which is correct as it stands — the run really did complete.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect changes in
`plan-runner-lib.sh`, `analysis/{recover_attempts,report,backfill_usage}.py`,
`feature-close.sh`, `analysis/README.md`, `self/tests/` and `self/BACKLOG.md`.

## Contracts to hold it to

1. **The sidecar says when it is unpriced, and why.** `write_usage_sidecar` must write
   `"result_event": "seen"` when the stream held a result event and `"result_event":
   "missing"` when it did not. `outcome` must keep meaning what the plan *did* (from the
   exit code) — check that the diff did not quietly reroute a resultless-but-successful
   run to `failed/` or invent a new `outcome` value. Then find **every reader** that
   decides "is this priced" and confirm none of them infers it from `outcome`: search the
   diff for `outcome ==` / `.get("outcome")` and judge each site. Confirm the field is
   documented where the sidecar's fields are listed, that a sidecar written before the
   field existed still reads correctly (absent ≠ `"missing"`), and that
   `backfill_usage.py` — whose stated contract is a field-for-field interchangeable
   sidecar — was kept in step.

2. **The close recovers before it captures.** `feature-close.sh` must gain a step between
   its steps 4 and 5 (after the timing carry, before the capture) that runs
   `analysis/recover_attempts.py [--self] --for <slug>`. Hold it to four things:
   - `--for` restricts the walk to one feature's directory, and **without it the script
     keeps its whole-tree behaviour** — `sweep.sh:73` passes no `--for` and must be
     unaffected. Check `--for` against a slug that does not exist.
   - Recovery failure is **reported, never fatal**: the close must still reach its
     capture, its report and its commit. A plan whose transcript is gone must be named in
     the printed output, not swallowed.
   - The usage files recovery rewrites live in the feature dir on `main`, so they must be
     part of the exact set step 8 commits as `<slug>: cost records` — read the
     `COST_FILES` comment near the top of the script and confirm the extension covers a
     nested `<queue>/<state>/<stem>.usage.json` and nothing wider. A recovered usage file
     left dirty must **not** trip step 8's "anything else dirty" refusal, and must not
     make the teardown force-remove a worktree holding somebody's real work.
   - The refusal paths still leave the primary byte-identical. Step 5's contract is "the
     primary is exactly as this run found it" — a capture that refuses after recovery has
     rewritten files leaves the primary dirty, and step 1 then refuses the re-run on dirt
     this script made. Judge whether the diff honours that contract or breaks it.

3. **Never a bare `$0.0000` for a bucket that had work.** Where the close prints the cost
   line, a bucket containing an unpriced plan must name the plan and say why: the reason
   from contract 1 (`no result event` / `killed`) plus what recovery did (`recovered $X
   from transcript` / `transcript not found`). Check that the reason is read from the new
   sidecar field rather than re-derived from `outcome`; that the `(partial)` marker on the
   total survives; that a fully recovered plan is *not* reported as unpriced (it has real
   dollars now); and that the edit stayed on `compute_cost_rollup`'s output/warning path
   and did not touch its summing.

4. **`--recapture` fixes the already-closed features.** The diff must leave
   `feature-close.sh <slug> --recapture` working for a feature whose worktree is gone —
   no step may newly require the worktree. `NOTES.md` must carry, under
   "Re-capturing the three closed features", the exact command, the directory to run it
   from, and the subtree pull that must precede it, for `musicMap/pin-ruff` and the
   vinylCatalogue slugs. Judge the procedure as a reader who has to run it: does it say
   what to do when the capture refuses? Does it name every affected feature, or only the
   ones the spec happened to list? Nothing in a consumer repo may have been written.

5. **The docstrings stop saying "killed only".** `recover_attempts.py`'s module docstring
   and its `analysis/README.md` entry must state both cases — a killed run, and a
   completed run whose stream lost its result event. A doc that still frames null cost as
   "a killed run never emits a result event" is a finding.

6. **Tests first, and they were RED.** The acceptance tests must be in `self/tests/`
   (extending `cost-recovery.sh` or a new `recover-at-close.sh`), follow the fixture
   pattern the tests README describes — throwaway `mktemp -d` checkout, stub `claude`,
   stub transcripts under a redirected `$HOME`, no model, no network — and be registered
   in `self/gate.sh` and given a row in `self/tests/README.md`. They must assert:
   (a) a sidecar written from a stream with **no result event** carries
   `result_event: missing` and `outcome: complete`, driven through the real runner with a
   stub `claude` that prints assistant events and exits 0 without a result line;
   (b) `recover_attempts.py --for <slug>` touches only that feature's files and recovers a
   `complete`-outcome null-cost attempt from a planted transcript;
   (c) the close's printed cost line names the unpriced plan and the recovery outcome
   instead of a bare `$0.0000`, and the recovered usage file is in the cost commit.
   `NOTES.md` must record each pre-fix RED line. Judge whether each assertion could pass
   *vacuously* — an assertion that would still pass with the fix reverted is worse than
   none, and saying so is the highest-value finding available here.

7. **Backlog, not NOTES, for what was left.** `self/BACKLOG.md` must exist (created in the
   shape of `~/dev/vinylCatalogue/plans/BACKLOG.md` — header paragraph, one bullet per
   item, bold lead, the assertion that would catch it, "Raised by `<slug>`.") or be
   appended to if the sibling created it. It must carry the unknown cause of the missing
   result event on a 0-exit session, with whatever the stream showed, and anything else
   found and not fixed. Anything left in `NOTES.md` that belongs in the backlog is a
   finding.

Also hold the diff to the repo's standing rules: bash 3.2 (no associative arrays; an
empty array expands as `${a[@]+"${a[@]}"}`), `set -uo pipefail` with no `set -e`, the
analysis scripts' bare cross-imports, and the README rules in `CONVENTIONS.md` — every
touched folder's README current, field lists for the on-disk shapes that changed.

## Verdict

Write `self/review-report.md`: what the feature was supposed to do, whether it does it,
then two separate lists — **fixed in this pass** and **escalated to the next batch**. It
is used verbatim as the PR body, so write it for the human approving the PR. "No
findings" is a legitimate verdict.
