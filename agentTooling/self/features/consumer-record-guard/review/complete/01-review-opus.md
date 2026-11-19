# 01 — review: consumer-record-guard

Written before the build, from the implementer brief's items, never from the builder's
report. Read the diff against the contracts below; "no findings" is a legitimate verdict.

## What the feature was supposed to do

Before humanNetworkMap pulled `orchestration-records-in-repo`, the vendored tooling wrote
that repo's orchestration records into `agentTooling/self/orchestrations/`, and the
stranded ones had to be moved by hand. The record tools already refuse to *read* a
stranded record; this feature closes the *write* side upstream, so every consumer gets it.

1. **Confirm the hole, then close it.** A test establishes which writers can still put a
   record (or a file beside one) under the vendored `self/orchestrations/` when the copy is
   vendored in a consuming repo: `orchestration-start.sh` with and without `--self`, with
   and without `--coordinator`; `manifest.py --orchestration` writes (`add-feature`,
   `set-feature`, `set-window-to`); `orchestration-capture.sh` (and the
   `orchestration_capture.py` it runs); and any other tool that writes into a record folder
   (`report.py --orchestration` writes `report.json`/`report.md` there). Each writer that
   can is made to refuse in consuming-repo mode **before any write**, naming
   `plans/orchestrations/<slug>/` as the place. If none could, `NOTES.md` says so with the
   evidence and the test stays as a regression guard.
2. **Unchanged:** agentTooling's own `--self` use in its own standalone checkout (no
   consuming repo above it) writes exactly as before; agentTooling's shipped records under
   `self/orchestrations/` in a vendored copy stay readable (`manifest.py --self
   --orchestration <slug> get …`, the role hook, the coordinator advisory); the no-`--self`
   behaviour in a consumer (records in `plans/orchestrations/`, stranded-record `git mv`
   refusal, own-record note) is unchanged.
3. **Tests** under `self/tests/` (extending `orchestration-records-in-repo.sh` or a
   sibling): each guarded writer refuses in a scratch consumer with a vendored copy and
   writes nothing; each still works under `--self` in a standalone checkout; reading a
   shipped record in a vendored copy is unaffected.
4. **Docs:** `LIFECYCLE.md` → "Orchestration records" and `analysis/README.md` state the
   refusal; the README of every folder touched is current; `self/tests/README.md` lists
   the test.

Excluded: the Edit tool writing under `agentTooling/self/orchestrations/` (the consumer's
settings already ask), `feature-start.sh --orchestration` (writes a feature manifest, not a
record), `feature-close.sh` and the "file before close" rule (a sibling feature's).

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **One classifier.** "Is this a vendored copy in a consuming repo" is decided in
  `analysis/roots.py` by what already decides it (`is_standalone_checkout`), and every
  guarded writer — `orchestration-start.sh` included — reaches that decision there (the
  shell through a `roots.py` CLI word, as it already asks `roots.py stranded`). No second
  `.git`-presence test or path comparison is added anywhere.
- **Refusal before any write.** A refused run leaves the vendored `self/orchestrations/`
  and the consumer's `plans/orchestrations/` byte-identical (no `mkdir`, no ledger line,
  no `planning.json`, no report files); exit 1; the text names
  `plans/orchestrations/<slug>/` and is one message shared by every tool.
- **Reads are not writes.** `manifest.py --self --orchestration <slug> get` on a shipped
  record in a vendored copy still exits 0 with the value; `hooks/orchestrator_role.py` and
  `analysis/coordinator_check.py` still read both roots.
- **Standalone `--self` unchanged.** `self/tests/orchestration-records.sh` and
  `self/tests/coordinator-records.sh` (standalone fixtures) pass unedited in substance.
- **Tests assert behaviour**, through the real scripts in a scratch consumer, including
  "wrote nothing" by a before/after snapshot, not by grepping source.
- **Docs and READMEs**: `LIFECYCLE.md` → "Orchestration records", `analysis/README.md`,
  `self/tests/README.md`, and the feature's `NOTES.md` (rulings) agree with the code;
  named constants for every new literal (`CONVENTIONS.md` → "Named constants"); bash 3.2
  and `set -uo pipefail` conventions (`self/PROJECT_FACTS.md`).
- `./self/gate.sh` green.

## Verdict
