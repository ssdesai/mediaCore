# consumer-record-guard — rulings

Raised by the 2026-11-17 orchestration wave: before humanNetworkMap pulled
`orchestration-records-in-repo`, its orchestration records were written under the vendored
`agentTooling/self/orchestrations/` and several were stranded there, each moved by hand
(a helper session plus an owner approval, because of the orchestrator-role hook). The record
tools already refused to *read* a stranded record; nothing refused a *write* there.

## The hole existed — evidence

`self/tests/consumer-record-guard.sh`, run against the unguarded `origin/main` code in a
scratch consumer with a vendored copy, failed 11 checks. Every writer put files under the
vendored `self/orchestrations/` under `--self`:

- `orchestration-start.sh --self <slug>` wrote the record and the ledger line (exit 0).
  `--coordinator` is the same code path; in that run it only refused because the
  orchestrator start had already created the folder ("already exists").
- `manifest.py --self --orchestration <slug> add-feature`, `set-feature` and `set-window-to`
  rewrote a shipped record's fence (exit 0 each).
- `orchestration-capture.sh --self` and `orchestration_capture.py --self` wrote
  `planning.json` beside a shipped record.
- `report.py --self --orchestration` wrote `report.json` and `report.md` beside it.

Without `--self` none of them wrote there: `orchestrations_root(False)` is the consumer's
`plans/orchestrations/`, and `record_refusal` already turned a legacy slug into the `git mv`
or the own-record note. The hole was `orchestrations_root(True)`, which is the vendored
folder whenever the copy is vendored.

## Rulings

1. **One decision, `roots.record_write_refusal(self_mode, slug)`.** Under `--self` in a copy
   that is not a standalone checkout (`not is_standalone_checkout()`, the existing test, with
   no second `.git` probe), it returns `VENDORED_SELF_WRITE_REFUSAL`. Otherwise it returns
   `record_refusal`'s answer, so the no-`--self` refusals are unchanged. The text names
   `agentTooling/self/orchestrations/<slug>/` as what would have been written and
   `plans/orchestrations/<slug>/` as the place, and says to drop `--self`. An agentTooling
   feature is listed in the consumer's record with `repo=agentTooling`, which the report
   already prices from the vendored directory (orchestration-record-fixes, item 2).
2. **Every writer asks it before writing; readers do not.** These writers ask it:
   `manifest.py --orchestration` through `load_orchestration(args, write=True)` on
   `add-feature`, `set-feature` and `set-window-to`; `orchestration_capture.capture`; and
   `report.run_orchestration`. `report.py --orchestration` is a writer too: it writes
   `report.json`/`report.md` into the record folder, so it is guarded even though the brief
   did not name it. The readers keep `record_refusal`: `manifest.py … get`, and
   `hooks/orchestrator_role.py` and `coordinator_check.py`, which never called it. So a
   shipped record stays readable with `--self` from a vendored copy, and the role it carries
   still holds.
3. **The shell start asks the same function**, through `python3 roots.py self-write <slug>`
   (the existing `roots.py stranded` CLI shape). It asks only under `--self`, right after
   the slug check and before the "already exists" check, the reverse guard and any `mkdir`
   or ledger append. Exit 0 means write. Any other outcome refuses: the printed text, or a
   generic refusal when roots.py crashed. A crash also exits 1 but prints nothing, so the
   check fails closed.
4. **A copy with no checkout anywhere** (no `.git` in or above it) also counts as "not
   standalone" and is refused under `--self`. That is the only answer `is_standalone_checkout`
   gives, and a record written there would have no repository to carry it anyway.
5. **Tests.** `self/tests/consumer-record-guard.sh` (C1–C6) is the new guard's test.
   `orchestration-records-in-repo.sh` had asserted the hole as behaviour: R1 checked that a
   `--self` start in the vendored copy wrote `self/orchestrations/`, and R2 did a `--self`
   add-feature and report there. R1 now asserts the refusal. R2's `--self` pricing check and
   R1's "next steps carry `--self`" check moved to R7, which runs in the standalone checkout
   where they belong.

## Round 2 (review 01 escalation)

6. **The coordinator advisory names `--self` only where the start may write.**
   `coordinator_check.py` had worded its command from the start's mode alone. So a `--self`
   start from a vendored copy was told to run `orchestration-start.sh --self …`, which this
   feature refuses there. The wording now asks `roots.self_record_write_allowed()`, which is
   `is_standalone_checkout()` under the name both its askers use, the guard and the advisory,
   so there is still one classifier. Elsewhere the command names no flag: a consumer's record.
   `orchestration-records-in-repo.sh` R9 now asserts the `--self` wording in the standalone
   checkout and no flag from the vendored copy.
7. **The advisory still reads a shipped record.** `consumer-record-guard.sh` C3 asserts that
   `coordinator_check.py` stays silent for the shipped record's session, and checks against a
   control: a session no record names still draws the warning.

## Excluded

- The Edit tool writing under `agentTooling/self/orchestrations/`: a consumer's settings
  already ask (`hooks/wire-settings.py`).
- `feature-start.sh --orchestration`: it writes a feature manifest's key, not a record.
