# Notes — self-corpus-identity

The implementer's rulings, in the order they were made. The brief's own rulings 1-6 are
settled and not repeated here; what follows is everything it left open.

## Rulings

- **The vendored fixture needs a real `git init`, not a bare `mkdir .git`.** The brief
  suggested the bare directory ("`repo_identity` falls back to the enclosing directory's
  name, which is what a wrong answer looks like"). It does not: an invalid `.git` makes
  `git -C … remote get-url origin` exit 128, and `repo_identity` then returns
  `Path(features_dir.parents[1]).name` — the **vendored** directory's own name,
  `agentTooling`, which is accidentally the right display name. Phase 10 would have been
  green against the defect it exists to catch. The wrong answer needs a `git` that
  succeeds, so `$VHOST` gets `git init` plus `remote add origin
  https://github.com/someone/vendorHost.git` — which is also the real consumer shape, and
  the one that produced the measured phantoms. `feature-lifecycle.sh` already stands up a
  real repo in a fixture, so this is in convention. Recorded in the phase's own header
  comment and in `self/tests/README.md`.

- **10d is asserted by the ledger's name, not by "the surviving twin entry".** Written as
  "the entry whose feature ends in `/claim-self-twin`" it passes on the pre-change tree,
  where the first such entry happens to be the manifest's (under the wrong repo) with the
  right `from`. Naming `agentTooling/claim-self-twin` exactly makes it red there — that
  entry is the *ledger's*, with the ledger's 14:00 `from` — and green only once the two
  collapse into one. Every one of 10a-10g is red against `main`.

- **`register_frozen_claims`'s `sessions_dir` parameter is dropped.** It existed for the
  single `repo_identity(sessions_dir)` call this feature replaces with
  `corpus_identity(features_dir)`; nothing else in the function read it. Keeping an unused
  parameter would leave the next reader believing the frozen-claims path still asks the
  session root who the feature belongs to, which is exactly the confusion this feature is
  removing. `main`'s only call site is updated in the same commit.

- **`--for` needs no routing.** Ruling 2 asks for any further place that writes or
  compares a *feature's* repo under `--self`. `--for` compares `parse_feature_ref`'s pair
  against `brief_feature_of`'s — both are the **display** halves of `feature: <repo>/<slug>`
  lines, typed by a human and written by a coordinator, and neither is derived from `git`.
  The declared identity's `repo_display_name` is `agentTooling`, the same string those
  lines already carry, so nothing there moves. `manifest_pinned_subagents` is slug-only by
  ruling 5 and unchanged.

- **The ledger's subagent side is routed, and it is the same line.**
  `capture_feature` computes one `repo`/`repo_name` pair and uses it for `check_claims`,
  `record_claims`, `record_session_claims` and `share_ctx` alike, so routing that one
  assignment through `corpus_identity` moves the subagent claims with the session claims.
  They must move together: a subagent claim written under the consumer's origin and read
  back under the declared one would refuse a re-capture of the feature that wrote it.

- **`self/tests/subagent-capture.sh` and `claims-ledger.sh` keep their expected strings.**
  Both assert on `repo_name`, and `repo_display_name` of the declared identity is
  `agentTooling` — the same value the old directory-name fallback produced in those
  fixtures. Only the *reasons* stated beside them were wrong after this change (they said
  the identity falls back to the directory name), so the comments are rewritten and the
  assertions are untouched. `claims-ledger.sh`'s seeded legacy row keeps `"repo": "$AT"`:
  it is a legacy flat-ledger entry matched by agent id alone, and it equalled neither the
  old identity nor the new one.

- **`feature-lifecycle.sh` needed no edit.** Its fixture has a real bare `origin`, so its
  `--self` ledger rows now carry the declared identity instead of that path — but every
  feature in it is `--self`, so they all move together and no assertion reads `repo`.
  Confirmed by the gate rather than by inspection alone.

## Red proof

Phase 10 run against the pre-change tree (`analysis/roots.py` and
`analysis/capture_planning.py` identical to `main` at `a5d7155`; `git diff main --
analysis/` empty at the time of the run), assertions 1-9 green throughout:

| Assertion | Pre-change | Why |
|---|---|---|
| 10a. twin is `agentTooling/claim-self-twin`, source `manifest` | RED | the manifest's claim was named `vendorHost/claim-self-twin` |
| 10b. nothing in `share_basis` names the enclosing repo | RED | both the twin and `claim-here` itself were named `vendorHost/…` |
| 10c. one entry for the twin, not two | RED | manifest `(vendorHost, twin)` and ledger `(agentTooling, twin)` are different keys — both survived |
| 10d. that entry is the manifest's, with the manifest's `from` | RED | `agentTooling/claim-self-twin` was the *ledger's* entry, `from` 14:00 |
| 10e. two-claimant split | RED | three claimants, 5/12 of the session instead of 1/2 |
| 10f. ledger row's `repo` is the declared identity | RED | `https://github.com/someone/vendorHost.git` |
| 10g. ledger row's `repo_name` is `agentTooling` | RED | `vendorHost` |

The mutation that turns all seven green: `roots.SELF_CORPUS_IDENTITY` plus
`capture_planning.corpus_identity(features_dir)`, returning it when `features_dir` is
`features_root(True)` and `repo_identity(features_dir.parents[1])` otherwise, routed
through all four sites that answer "which repo does this corpus belong to"
(`build_claimant_index`, `register_frozen_claims`, the `annotate_frozen_record` call in
the `--all` loop, `capture_feature`'s `repo`/`repo_name`).

## Deviations from the brief

- The fixture's enclosing directory is a real git repo, not a bare `mkdir .git` (first
  ruling above).
- The brief's four assertions are written as seven checks (10a-10g), splitting its 10a
  into the positive name and the negative one, and its 10d into `repo` and `repo_name`.
  Nothing is dropped.

## Open questions

None. Nothing in scope was left undone, so `self/BACKLOG.md` gains no entry.

# Rework

The rework one-shot's rulings, from `rework-brief.md` — the review's escalations 1-4
(`self/review-report.md` → "Escalated to the next batch"). The build's rulings above are
settled and are not reopened here.

## Rulings

- **Item 1's ledger is reseeded, not inherited.** The three assertions run after 10a-10g,
  which have already written `claim-here`'s ledger row — under the declared identity on
  this tree and under the *consumer's* origin on `main`. Inheriting that state would make
  10i pass against `main` with nothing to catch: `other_session_claimants` would find no
  `agentTooling/claim-here` row to fail to exclude. So the phase writes `$VLEDGER` fresh
  to exactly the two rows a SHARED ledger really holds in this layout — `claim-here`'s own
  and `claim-self-twin`'s, both under the declared identity, because the standalone
  checkout's own `--self` runs wrote them, which is the same reasoning 10c already seeds
  the twin's row on. The fixture then says the same thing whichever tree it runs against.

- **A fourth check beyond the three the report names: `10-annotated`.** The three assert
  the identity used on the annotate-only path; none of them proves that path was *taken*.
  Were the record recomputed instead, all three would pass off the recompute branch —
  which sets `also_claimed_by` too (`capture_planning.py:2430`) — and say nothing about
  `register_frozen_claims` or the `--all` loop's `annotate_frozen_record` call, the two
  sites item 1 exists to cover. `same_but_annotation` (assertion 7a's helper) is one line
  and closes it. It is green against `main` as well: it pins the branch, not the identity.

- **Item 3's precondition is `10-pre`, before 10a rather than beside it.** The check has
  to fail the phase *loudly* before any assertion reads a value derived from a `git` that
  did not run, so it sits immediately after the `remote add`, where the report asks for
  it. Green against `main` for the same reason as `10-annotated`.

- **Item 2's check lives in `self/tests/sync-check.sh`, section 8b-8d, not in
  `self/gate.sh`.** The brief's condition is "where the gate already checks `update.sh` if
  such a place exists". `self/gate.sh`'s own contact with `update.sh` is `bash -n` — a
  syntax parse that cannot read a value — while `sync-check.sh` *is* the gate's `update.sh`
  test (`record "sync check self-test"`), and its section 8 is already the read-only pass
  over the real checkout that asserts two hand-mirrored files agree. This is the same
  shape: `roots.SELF_CORPUS_IDENTITY` read by importing `roots`, `DEFAULT_REMOTE` read by
  parsing the literal out of `update.sh`, and the root `README.md` grepped for the string
  on a `git subtree` line. Three literal sources, one check, no model and no network. A
  new `self/tests/*.sh` for three lines would have added a gate row and a README row to
  say what section 8 already says.

- **Item 4 names `corpus_identity` as `repo_identity`'s only caller in both documents.**
  The finding is that a reader goes looking for a live session-side call and finds
  nothing. Renaming the parameter to `checkout_dir` and deleting the claim would leave the
  same reader with no answer, so both rewrites state the distinction as conceptual —
  which repo a *checkout* is, versus which corpus a *feature* belongs to — and say where
  the one remaining call is. No session-side call is reintroduced: nothing in `analysis/`
  asks `git` who a `--self` session's feature belongs to.

- **10j is red against `main` too.** The report predicted only (b). Asserting the ledger
  holds exactly one `claim-here` row rather than reading the first one that matches makes
  (c) red as well: on `main`, `register_frozen_claims` adds a second row under the
  consumer's origin beside the seeded `agentTooling` one, and a `next(...)` over the list
  would have found the seeded row and passed. Recorded because it is a stronger assertion
  than the report asked for, not a different one.

## Red proof

`analysis/` from `main` (`git archive main analysis`) into a scratch root beside this
branch's `self/tests/session-claims.sh` and `self/tests/fixtures/` — `HERE` resolves to
that root, so the fixture copies `main`'s four modules and nothing else changes. 1-9 green
throughout, 10a-10g red as the build recorded them:

| Assertion | vs `main` | Why |
|---|---|---|
| 10-pre. `$VHOST`'s origin is `$VENDOR_ORIGIN` | green | the fixture's precondition, not the rule under test |
| 10-annotated. annotated, not recomputed | green | the annotate-only branch is taken on both trees |
| 10h. `also_claimed_by` names `agentTooling/claim-self-twin` | green | the twin's seeded ledger row is named the same either way |
| 10i. nothing in it ends in `/claim-here` | **RED** | `also_claimed_by` was `['agentTooling/claim-here', 'agentTooling/claim-self-twin']` — annotated under `https://github.com/someone/vendorHost.git`, the self-exclusion missed its own `agentTooling` row |
| 10j. one `claim-here` ledger row, declared identity | **RED** | two rows: `['https://github.com/someone/vendorHost.git', 'https://github.com/ssdesai/agentTooling.git']` — `register_frozen_claims` wrote a second under the consumer's origin |

The mutation that turns both green is the build's own: `corpus_identity(features_dir)` at
`register_frozen_claims` and at the `annotate_frozen_record` call, which this rework only
covers rather than changes. No `analysis/` behaviour is modified by the rework — its only
`analysis/` edit is item 4's parameter rename and docstring.

## Deviations from the rework brief

- Two guards beyond the three assertions item 1 names (`10-annotated`, and item 3's
  `10-pre` numbered as a precondition rather than as `10h`). Nothing is dropped.
- Item 2 is three `check` lines (8b, 8c, 8d) rather than one, so a failure names which of
  the three literals moved. One check in the brief's sense: one section, one source of
  truth, read three ways.

## Open questions

None. Every escalated item is taken; nothing in scope is left undone, so `self/BACKLOG.md`
gains no entry.
