# 02 — review: pull-round-cleanups (round 2, rework of the round-1 audit)

Review this feature's whole diff, paying particular attention to the round-2 rework. "No
findings" is a legitimate verdict: if the diff does what is listed below, holds the contracts,
and breaks nothing, say so and stop.

## What the feature was supposed to do

The spec is unchanged from round 1 (`complete/01-review-opus.md` → "What the feature was
supposed to do"; the acceptance table in `../../README.md`): item 1, the stranded-record
classifier; item 2, resolved by item 1, with nothing removed under `self/orchestrations/`;
item 3, the docs on a cloud pull child's `add_repo` and the parent's merge scope; item 4, the
backlog entries; and the orchestrator addendum, the role test clearing the caller's
`AGENTTOOLING_PROFILE` and holding itself to it.

Round 1's review was clean. The round-1 security audit (`../../audit-report.md`) escalated two
blocking findings, which are one regression. Round 1 called a vendored record agentTooling's own
whenever its last fence listed an agentTooling feature. A consumer-run mixed wave left in the
vendored copy has the same bytes, so a start of its slug, which the base refused with the
`git mv`, went on (finding 1). In a consumer whose name is agentTooling's, every record was
exempt (finding 2). The rework this round must:

- never make a start that the base refused go on;
- still never tell a consumer to `git mv` a record that also lists an agentTooling feature,
  since that is item 1's point: moving an agentTooling wave deletes shipped code from the
  consumer's `agentTooling/`;
- keep `roots.py stranded <slug>` answering "no" for such a record, so a consumer's check stops
  demanding the move.

The rework's design is in `../../NOTES.md` §1 ("Round 2"): a three-way `legacy_record_claim`
(stranded, ambiguous or own), and an ambiguous record refused at start and by every record tool
with a text that names both readings.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `roots.legacy_record_claim(slug)` is the ONE classifier. `is_stranded_record`,
  `legacy_start_refusal`, `record_refusal`, `roots.py stranded` and `roots.py start-refusal`
  derive from it; `orchestration-start.sh` asks `roots.py start-refusal` and restates no rule.
- No case is more permissive than the base. For every vendored record the base refused to
  start, the head refuses too. A start the base allowed (agentTooling's own record, no record) is
  still allowed. The start fails closed: any exit but 0 from `start-refusal`, a crash included,
  refuses and writes nothing.
- The ambiguous text is defined once (`roots.AMBIGUOUS_RECORD_REFUSAL`) and built from
  `shared_rules.LEGACY_RECORD_MOVE`. It is not a copy of that move's string. Nothing under
  `hooks/` or `.claude/` changes.
- `self/tests/orchestration-records-in-repo.sh` R3, R6 and R10 hold unchanged. R12 asserts the
  mixed wave: not stranded, the ambiguous text from report.py, manifest.py and the start, and
  nothing written. It also asserts the consumer-only record (the `git mv` from the tools and the
  start), `start-refusal` exit 0 for an own record and for none, and the fail-closed start. R13
  asserts the same-name consumer.
- `analysis/README.md`'s `roots.py` entry and `self/tests/README.md`'s entry describe the
  three-way rule, R12 and R13. The `orchestration-start.sh` header and constants comments
  agree with it.
- Everything round 1 held still holds: the role test (passes with `AGENTTOOLING_PROFILE=cloud`
  exported, and exports it itself before clearing it); no change to `self/gate.sh`,
  `self/orchestrations/` or another feature's folder; the docs of item 3 and the backlog entries
  of item 4.
- The gate is green, `./self/gate.sh`.

## Verdict
