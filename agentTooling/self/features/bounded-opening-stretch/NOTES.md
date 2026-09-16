# Notes: bounded-opening-stretch

Rulings made where the brief left the call open, each with a one-line rationale, plus the
red-proof table and the mutation every new assertion was proved against. The brief's five
rulings are settled and are not reopened here.

## What changed, and why

- **`analysis/capture_planning.py::earliest_dated_claim(intervals)`** — the claim the
  opening-stretch fallback pays, `min` on `(from, feature)` over dated, non-empty claims.
  Split out of `share_owners` because `head_bound` needs the same claim over the same
  pool, and two spellings of "earliest claimant" would drift the way `is_empty_window`
  exists to stop. The pool and the ordering are byte-for-byte the old ones; the
  empty-window filter moved with them, so phases 9-11 are untouched.
- **`head_bound(intervals)`** — `from - (to - from)` of that claim: the earliest instant
  the fallback may pay. `None` when there is no dated claim, and `None` when the earliest
  claimant's `to` is still `null` (a window with no end has no length to bound by; the
  recapture after `feature-close.sh` stamps `to` applies the bound).
- **`is_unpaid_head(moment, intervals, bound=None)`** — whether an instant nobody owns is
  in the opening stretch rather than in a gap between windows or in the tail. Asked only
  of instants `share_owners` returned `[]` for, and answered from the bound alone.
- **`share_owners`** consults `head_bound` and returns `[]` below it — the response falls
  to the unclaimed remainder exactly as the tail does. **`partition_seconds`** adds the
  bound to its cut points and returns a third value, `unclaimed_head_seconds`.
- **`select_parent`**'s share walk accumulates `unclaimed_head_tokens` beside
  `unclaimed_tokens` (a subset of them, not a fourth bucket), computing the bound once per
  session rather than per response, and carries it in `share_detail`.
- **`capture_feature`** prices those tokens and, when there is a head, replaces the
  "unclaimed by any feature" sentence with one naming the head's dollars and seconds, the
  rest's dollars and seconds, and the remedies for each side. With no head the old
  sentence is emitted verbatim.
- **Docs**: `analysis/README.md` — the share paragraph's rule sentence now carries the
  bound, a new paragraph states it in full (the `2d8b1236` measurement, relative not
  fixed, the in-flight exemption, one rule for dollars and seconds, the disclosure), the
  two `is_empty_window` cross-references now name `earliest_dated_claim`, and the
  `planning.json` field prose for `unclaimed_usd`/`unclaimed_duration_s` says what they
  actually hold. `self/tests/README.md` — phase 15 in the `session-share.sh` row.
  `self/PROJECT_FACTS.md` states no share rule (grepped `opening`); nothing to change.
  `self/BACKLOG.md` — one entry.

## Rulings

- **The bound is a function, not a predicate.** The brief offered `head_bound(intervals)`
  returning the earliest payable instant; kept, because `partition_seconds` needs the
  instant itself as a cut point, and a `head_covers(moment, intervals)` predicate would
  have forced the edge to be re-derived at the call site — the exact split the ruling
  forbids.
- **Three helpers, not one.** `earliest_dated_claim` is separate from `head_bound` because
  `share_owners` needs the claim and `partition_seconds` needs the instant, and computing
  one from the other inline is how the ranking pool comes to be written twice.
  `is_unpaid_head` is separate again because "unowned" and "unowned *and* before the
  bound" are asked in two places (the token walk and the seconds walk) and must agree.
- **`unclaimed_head_seconds` is a third return value, not a fourth partition.** It is a
  subset of `unclaimed_seconds`, so the sum invariant `shares + unclaimed ==
  session_duration_s` is arithmetically unchanged — asserted by `15d-sum` beside the
  existing `5g`. Returning it separately was preferred to a `{"head": …, "rest": …}` dict
  because the two existing values are positional and one caller unpacks them.
- **The head tokens do not warn again for an unpriced model.** They are a subset of the
  remainder's, so the remainder's "no rate for model … is a lower bound" warning has
  already been emitted for that model; a second copy says nothing new, and both figures
  are then lower bounds together.
- **The warning is one sentence-pair, not a second warning.** A separate warning line
  would be read as a separate problem; the head and the rest are two parts of one figure
  and the reader needs to see which part he can act on with which remedy. The no-head
  sentence is emitted byte-identically to before (ruling 3's "the tail's sentence stays as
  it is"), which is why the branch is `if head: … elif unclaimed: …` rather than a
  conditional clause appended to one string.
- **The disclosure names the *rest*, not the *tail*.** In the phase-15 fixture the
  non-head remainder is a gap between two windows, not a tail past every `to`; calling it
  "the tail" would be wrong wherever windows fail to chain. The remedy named for it is
  still the tail's, because widening a `to` bound forwards is what closes a gap too.
- **No new `planning.json` field, and no attempt to re-derive the head from a frozen
  record.** Ruling 3. The head is recoverable from `share_basis` (the earliest claim's
  `from` and `to` give the bound) plus `started_at`, and the warning is frozen into
  `planning.json`'s `warnings[]`, so the disclosure survives the capture that made it.
- **`is_unpaid_head`'s `bound` parameter defaults to recomputing.** A caller with the
  bound in hand passes it; one without gets the right answer anyway. `None` is both "not
  supplied" and a legitimate bound value, which is safe here only because a `None` bound
  makes the predicate `False` either way — noted in the docstring so the next reader does
  not have to re-derive that it is not a latent bug.

## The red-proof table, and the mutation

**The mutation** is `main`'s `analysis/capture_planning.py` — the unbounded fallback,
which pays the earliest claimant every instant before the earliest `from` however far back
it reaches. Phase 15 was written and committed first (`c1cb2b3`,
`bounded-opening-stretch: acceptance tests`) and run against the worktree while
`capture_planning.py` was still byte-identical to `main` — no separate sandbox copy was
needed, since no line of it had been touched at that point. `10 of the 14` new checks
failed; phases 1-14 stayed green throughout.

| check | against `main` | after | what `main` did |
|---|---|---|---|
| `15a` head-a's total is r1 + r2 | **FAIL** | ok | paid r0 too — 7000/10000, not 6000/10000 |
| `15b` unclaimed_usd is r0's share | **FAIL** | ok | `unclaimed_usd` absent (nothing unclaimed on the dollars) |
| `15b-sum` totals + remainder = session_cost_usd | **FAIL** | ok | red only because the absent field makes the sum unreadable |
| `15c` head-b's total is r3 alone | ok | ok | guard — the bound moves nothing on a later claimant |
| `15d` head-a's duration_s is 7200 | **FAIL** | ok | 10800: paid 08:00-11:00, not 09:00-11:00 |
| `15d-unclaimed` unclaimed_duration_s is 7200 | **FAIL** | ok | 3600: the 11:00-12:00 gap alone, no head |
| `15d-sum` spans + remainder = 18000 | ok | ok | guard — the invariant holds on both sides |
| `15e` warning quantifies the head's dollars | **FAIL** | ok | no head clause in the sentence at all |
| `15e-seconds` … and its seconds | **FAIL** | ok | " |
| `15e-rest` … and the rest, separately | **FAIL** | ok | " |
| `15e-remedy-pin` … names the pin remedy | **FAIL** | ok | " |
| `15e-remedy-from` … and `from` by hand | **FAIL** | ok | " |
| `15f` in-flight claimant keeps the head | ok | ok | guard — `to: null` has no length to bound by |
| `15f-unclaimed` … and nothing is unclaimed | ok | ok | guard |

Mapped to the brief's six: **15a, 15b, 15d and 15e were red**; **15c and 15f were green on
both sides and are the guard**, as `15d-sum` also is. `15b-sum` reads red against `main`
for a mechanical reason worth naming — `unclaimed_usd` is absent there, so `field()`
returns `""` and the sum cannot be computed; the invariant it asserts is not violated on
`main`, it is unmeasurable. Phase 3 is the same guard on the dollars from the other side
and was never touched: `share-a`'s window is eight hours and its head response two hours
out, so it is still paid — which is what stops the bound being read as a fixed grace
period.

## The rework: the review's four escalations

A second, one-shot pass over `self/review-report.md` -> "Escalated to the next batch".
One code change and four groups of assertions; nothing in the first build's rulings is
reopened.

### What changed

- **`capture_planning.py`'s head warning drops the rest when there is no rest.**
  `rest_cost` and `rest_seconds` both zero now suppress the "and $X (Ys) is the rest"
  clause *and* the "For the rest, widen a claimant's `to` bound…" sentence. Escalation 1:
  the mirror of ruling 3's tail-only sentence, which the head branch never had. The shape
  is not exotic — one claimant whose window covers the session's last instant leaves no
  tail, and a single claimant leaves no gap either — and the sentence handed that reader
  `$0.0000 (0s)` plus the one remedy that provably cannot reach a head.
- **`self/tests/session-share.sh`** gains phases **16** (a remainder that is all head) and
  **17** (a response landing exactly on `head_bound`), both on fresh session ids, plus
  **`15f-duration*`** (the in-flight exemption asserted on the seconds) and **`8c`** (the
  no-head sentence). The header's phase list and both red-proof notes are extended.
- **Docs**: `analysis/README.md`'s bound paragraph now states the all-head case beside the
  all-tail one; `self/tests/README.md`'s `session-share.sh` row carries 16, 17,
  `15f-duration*` and `8c`, and its phase-8 clause names `8c`.

### Rulings

- **With no rest to contrast against, the head's remedy stops being introduced as "For
  the head".** Dropping the rest clause alone would leave "…window is long. For the head,
  pin the session…" pointing at a distinction the sentence no longer draws. The lead is
  `"For the head, pin"` when there is a rest and `"Pin"` when there is not; with a rest
  present the whole warning is byte-identical to the first build's, which is what keeps
  every `15e` check reading the same string.
- **The head's own figures are still printed in full in the all-head case, even though
  they equal the remainder's.** `"has $X (Ys) unclaimed by any feature, of which $X (Ys)
  is the opening stretch"` repeats a number, which is the mild version of the defect being
  fixed — but the repetition is *true*, where `$0.0000 (0s) is the rest` was an invitation
  to act, and the "of which … is the opening stretch" clause is what `15e`/`16b` and any
  reader grep for. Rewriting it to "all of it the opening stretch" was rejected as a
  second wording change the review did not ask for.
- **Phase 16's premise is asserted before its wording is.** `16a`/`16a-usd` pin
  `unclaimed_duration_s` at 3600 and `unclaimed_usd` at `n0`'s share, because `16c` and
  `16d` are negative greps and would pass on any session with no head at all. A negative
  assertion needs a positive one beside it or it measures nothing.
- **Phase 17 is a fresh session, not a fifth response on phase 15's.** The review's own
  instruction, and the reason is arithmetic: every `15a`-`15f` expectation is a fraction of
  that session's 10000 output tokens.
- **Phase 17's bound coincides with its session start on purpose.** `partition_seconds`
  adds a cut point only for `start < head_edge < end`, so at `head_edge == start` there is
  no edge to add and the `09:00`-`10:00` segment is judged at `09:00` by `share_owners`'
  fallback itself — the inclusive comparison under test, reached with nothing else in the
  way.

### The red-proof table, and the mutations

Two different proofs, because the two defects are of different kinds. Escalation 1 is a
**behaviour** the code got wrong, so its checks are red against the pre-rework tree.
Escalations 2-4 are behaviours the code got *right* and nothing pinned, so their checks
are proved by **mutation**: the pre-rework tree is green on them, and the mutation is what
they exist to catch.

**Mutation A** — the pre-rework tree itself (`d1f3fba`, this branch before the rework):
the head branch of the "unclaimed by any feature" warning always emitted both halves of
the sentence pair.

**Mutation B** — `share_owners`' `if bound is not None and moment < bound:`
(`analysis/capture_planning.py:1985`) flipped to `moment <= bound`, making the bound the
first *unpayable* instant instead of the earliest payable one. Applied and reverted in the
worktree; `analysis/capture_planning.py` is byte-identical to its pre-mutation copy after.

| check | vs pre-rework (A) | vs `<=` (B) | after | what the mutation did |
|---|---|---|---|---|
| `8c` no-head warning is the old tail sentence, no head clause | ok | ok | ok | guard — escalation 4; the `elif` branch had no reader at all before it |
| `15f-duration` head-a's `duration_s` is 16200 in flight | ok | ok | ok | guard — escalation 3; `head_edge` is `None`, so no cut point and no bound to flip |
| `15f-duration-b` head-b's is 1800 | ok | ok | ok | guard |
| `15f-duration-unclaimed` no `unclaimed_duration_s` | ok | ok | ok | guard |
| `16a` the remainder really is all head (3600s) | ok | **FAIL** (7200) | ok | premise check — B pushes the `09:00`-`10:00` hour into the remainder |
| `16a-usd` … and `unclaimed_usd` is n0's share | ok | ok | ok | premise check |
| `16b` the warning names the opening stretch and its seconds | ok | **FAIL** | ok | guard — B changes the seconds it names |
| `16c` … and reports no rest of nothing | **FAIL** | **FAIL** | ok | A printed `and $0.0000 (0s) is the rest` |
| `16d` … nor the remedy for that nothing | **FAIL** | **FAIL** | ok | A printed `For the rest, widen a claimant's to bound…` |
| `16e` … the head's own two remedies still named | ok | ok | ok | guard |
| `17a` a response exactly ON the bound is paid to the earliest claimant | ok | **FAIL** (2000/6000, not 3000/6000) | ok | escalation 2, the dollars |
| `17b` … and `[bound, from)` is in its `duration_s` (7200) | ok | **FAIL** (3600) | ok | escalation 2, the seconds |
| `17c` … so nothing on the session is unclaimed either way | ok | **FAIL** (both fields appear) | ok | escalation 2, the invariant |

So: **`16c` and `16d` were red against the pre-rework code** (escalation 1's wording);
**`17a`, `17b` and `17c` are the mutation kill** for escalation 2; and **`8c`,
`15f-duration*`, `16a`, `16a-usd`, `16b` and `16e` are guards**, green on both sides.

One correction to the review's finding 2 while we are here: flipping `<` to `<=` does
**not** leave all of `session-share.sh` green — `15d` and `15d-unclaimed` catch it on the
*seconds*, because phase 15's bound `09:00` is a cut point inside its span. What was
genuinely unpinned is the **dollars** at the edge: `15a` stays green under mutation B,
since phase 15 has no response at `09:00` at all. `17a` is the check that closes that,
and the finding's conclusion — that the edge was untested — is right even where its
"all 84 green" is not.

Phases 1-15 stay green throughout; the file goes from 84 checks to 97, all green.

## Verification beyond the new phase

- Every earlier phase of `session-share.sh` (1-14, 70 of its 84 checks) green before and
  after.
- `git diff main...HEAD -- 'self/features/*/planning.json'` is **empty**: no frozen record
  moved, and nothing was recaptured. Ruling 5.
- `share_owners` and `partition_seconds` were grepped across both corpora and this repo's
  scripts: `analysis/capture_planning.py` is their only caller, so widening
  `partition_seconds`' return touched exactly one call site. `report.py` reads no
  unclaimed field at all.

## Gate

The rework's run, after the change: `bash self/gate.sh` from this worktree — **`all checks
passed`**, 67 recorded sections, 666 checks, 0 FAIL, 0 SKIP; `session share self-test`
inside it is 97/97 (84 before the rework).

The build pass's run, unchanged below for the record:

`bash self/gate.sh` from this worktree: **`all checks passed`** — 67 recorded sections,
0 FAIL, 0 SKIP. 42 `bash -n` parses, 22 behavioural self-tests including
`session share self-test`, `session claims self-test` and `claims ledger self-test` (the
three that exercise the split), `py_compile analysis`, and the two informational checks.
`shellcheck` is not installed on this machine and the gate skips it by design without
counting a skip.

## Open questions

- **Nothing tells a reader where the bound fell on a frozen record.** It is derivable —
  the earliest entry in `share_basis` carries the `from` and `to` the bound is computed
  from — but derivable is not printed, and `report.py` shows neither. Ruling 3 forbids a
  field, and the warning carries the figure, so this is left as it is rather than
  backlogged: the same record answers it, one subtraction away.
- **A head that no claimant can reach still has no command to fix it.** The warning tells
  the reader to move the earliest claimant's `from` back by hand; `manifest.py` has
  `set-window-to` and no `set-window-from`, and building one is a different feature —
  moving `from` back is a *widening*, so the guard that makes `set-window-to` safe does
  not transfer. `self/BACKLOG.md`, with the assertion that would catch it.

## Left to the coordinator

- The manifest fence's `subagents` is untouched — the coordinator pins this implementer's
  agent id there before `feature-close.sh` runs (`AGENT_DIRECT.md` → "The feature
  directory").
- The three `2d8b1236` claimants (`stale-failed-sidecars`, `recover-cost-at-close`,
  `stream-capture-file-first`) are **not** recaptured here, per ruling 5. That is the
  coordinator's step once this merges.
