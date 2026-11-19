Verdict: escalated

# Review: consumer-record-guard

## What the batch was supposed to do

When agentTooling is vendored into a consuming repo, stop every record tool from writing
under the vendored `agentTooling/self/orchestrations/`, `--self` included. Each tool must
refuse before it writes anything, and the refusal must name `plans/orchestrations/<slug>/`.
Three things must stay as they were:

- `--self` writes in agentTooling's own standalone checkout.
- Shipped records in a vendored copy stay readable.
- A consumer's runs without `--self` behave as before.

## Does it do it

Mostly, yes.

- **One classifier.** `roots.record_write_refusal` decides through `is_standalone_checkout()`
  and nothing else. The shell start asks the same function through a new CLI word,
  `roots.py self-write <slug>`, and refuses when it gets anything but exit 0, so a crash also
  refuses. No second `.git` test was added.
- **Every writer is guarded.** That covers `orchestration-start.sh` (both kinds),
  `manifest.py --orchestration add-feature`, `set-feature` and `set-window-to`,
  `orchestration_capture.py` (and the shell wrapper over it), and `report.py --orchestration`.
  All of them share the one `VENDORED_SELF_WRITE_REFUSAL` text.
- **`get` still reads.** It keeps the read-only `record_refusal` check.
- **The new test checks behaviour.** `self/tests/consumer-record-guard.sh` runs the real
  scripts in a scratch consumer and compares before/after snapshots of both record roots and
  the ledger. It also confirms the standalone `--self` path still writes, and that a shipped
  record still reads through `get` and the role hook.
- **Existing tests.** `orchestration-records.sh` and `coordinator-records.sh` are untouched.
  `orchestration-records-in-repo.sh` R1 and R2 were changed on purpose: they used to show a
  vendored `--self` start writing, which this feature forbids. The standalone half of those
  checks moved to R7.
- **Docs.** `LIFECYCLE.md`, `analysis/README.md`, the root `README.md`,
  `self/orchestrations/README.md`, `self/tests/README.md`, `self/README.md`,
  `PROJECT_FACTS.md` and the orchestrator brief template all describe the refusal.
- **Gate.** Green. The rate-history staleness check exits 1, but it does not block and is
  unrelated to this feature.

## Fixed in this pass

- `analysis/orchestration_capture.py` (in `capture`) and `analysis/report.py` (in
  `run_orchestration`): the new comments read as if the record's folder were
  `self/features/consumer-record-guard/`. I reworded both to say the tool writes into the
  record's folder, so it asks the write guard, and kept the feature citation.

## Escalated to the next round

1. **The coordinator advisory tells users to run a command this feature now always refuses.**
   This contract is now enforced on one side only.
   - **Where:** `analysis/coordinator_check.py:121` builds the flag with
     `flag = SELF_FLAG_WORDING if self_mode else NO_FLAG_WORDING`.
   - **What happens:** `feature-start.sh --self` from a copy vendored in a consuming repo
     (cloud profile, coordinator outside the checkout) passes `--self`. The advisory then
     prints `orchestration-start.sh --self <slug> --coordinator --session <id>`. In that same
     copy, `orchestration-start.sh` now refuses exactly that command with
     `VENDORED_SELF_WRITE_REFUSAL`.
   - **The test pins the wrong advice:** `self/tests/orchestration-records-in-repo.sh` R9
     (around line 278) runs `coordinator_check.py "$K" "$AT" --self` against the vendored
     `$AT` and asserts the `--self` wording.
   - **Fix:** name `--self` only where the record write is allowed. For example, use
     `SELF_FLAG_WORDING if self_mode and roots.record_write_refusal(True, "") is None else NO_FLAG_WORDING`,
     or a small `roots` predicate built on `is_standalone_checkout`, so it stays the one
     classifier.
   - **Tests:** move R9's `--self` assertion to the standalone checkout `$SA`. Add an
     assertion that a vendored `--self` call names no flag.
   - **Docs:** the module docstring (lines 6–8) and its `analysis/README.md` entry should say
     the same.
   - **Why I did not fix it here:** it changes what the advisory says and needs a test
     rewritten, which is a decision for a build plan rather than a local fix.

2. **No test checks that the coordinator advisory still reads a shipped record** (minor,
   missing assertion). The plan's contract says `coordinator_check.py` still reads both roots.
   Consumer-record-guard C3 checks `get` and the role hook but not the advisory's `recorded()`
   path. Add a C3 assertion that
   `coordinator_check.py <L> <some other checkout>` prints nothing in the vendored copy,
   because the shipped record names `L`.
