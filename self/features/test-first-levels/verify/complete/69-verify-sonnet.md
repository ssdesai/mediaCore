# 69 — Verify `test-first-levels`

Feature `test-first-levels`, plan 5 of 6. The feature reorders a batch into **levels** —
tests first, then per-layer build plans — with the free mechanical gate run at every level
boundary via a sentinel plan file `NN-gate.md`, so a cross-layer seam fails at the
boundary it crosses instead of at review one batch later.

You are verifying plans 65–68: sentinel handling in `plan-runner-lib.sh`, `--up-to` in
`run-verify.sh`, the level loop in `run-batch.sh`, the gate label / `record_skip` in
`templates/plans/gate.sh` and `self/gate.sh`, and the doctrine in `AGENT_PLANS.md`.

Read `self/gate-report.txt` first. `bash -n` over every script and `py_compile` already
ran there; do not repeat them. There is no test suite in this repo (`self/PROJECT_FACTS.md`
→ Tests), so what follows is the minimum exercise of the new paths that a script cannot
express. Do it with a **scratch feature** you create and delete inside
`self/features/_scratch-levels/`; never touch another feature's queue, and never run
`git stash`/`checkout`/`reset`.

Checks, in order — stop early and report if one fails structurally:

1. **Sentinel alone.** Create `self/features/_scratch-levels/auto/incomplete/05-gate.md`
   (one comment line) and nothing else queued. Run `./run-plans.sh --self _scratch-levels`.
   Expect: `self/gate.sh` ran with label `05` (terminal shows `=== level 05: mechanical
   gate`), `self/gate-report.05.txt` exists and its header says `level: 05`, the sentinel is
   in `auto/complete/` with **no** `.progress.md`, `.stream.jsonl` or `.usage.json` beside
   it, exit code 0, and `claude` was never invoked.
2. **Sentinel with a level-verify queued.** Reset the scratch queue; add `05-gate.md` to
   `auto/incomplete/` and an empty-bodied `05-level-sonnet.md` plus `10-verify-sonnet.md`
   to `verify/incomplete/`. Run `./run-plans.sh --self _scratch-levels`. Expect exit **4**
   and a summary line naming `run-verify.sh --self --up-to 05 _scratch-levels`.
3. **`--up-to` bounds the queue.** With only `10-verify-sonnet.md` queued in
   `verify/incomplete/`, `./run-verify.sh --self --up-to 05 _scratch-levels` must print the
   "nothing to do" message and exit 0 without invoking `claude`. Then confirm
   `./run-verify.sh --self --up-to 10 _scratch-levels` *would* select it: you may run it for
   real only if you make the plan body "Reply with the single word done and stop" and
   rename it `10-verify-haiku.md`; otherwise reason from `list_plans` and say so.
4. **`record_skip` verdict.** In a copy of `templates/plans/gate.sh` under the scratch
   dir, drive the verdict branch by calling `record_skip` once with no failures and confirm
   the `# VERDICT` line says SKIPPED and is not "all checks passed"; confirm a `record`
   failure still outranks it.
5. **bash 3.2.** `/bin/bash --version` on this machine is 3.2; every new construct must
   run under it — `[[ … =~ … ]]`, `${base%%-*}`, `[[ -le ]]`. If you used `$(( ))` on a
   zero-padded number anywhere, that is a defect (`08`/`09` are octal there).
6. **Doctrine matches mechanics.** Read the new `AGENT_PLANS.md` section and the
   `RUNNER.md`/`README.md` additions against what you just observed: the exit code, the
   flag order (`--self` before `--up-to`), the per-level report filename. Fix drifted
   prose locally.

Delete `self/features/_scratch-levels/` and every `self/gate-report.*.txt` you produced
before finishing. Fix only local defects (a wrong variable name, a message that names
the wrong flag order, drifted prose); anything structural is a finding for the next
batch, reported with the command and its verbatim output. End with: what you ran, what
passed, what you fixed, what is escalated.
