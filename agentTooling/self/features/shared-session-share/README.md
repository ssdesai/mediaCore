# Shared-session share

`feature-start.sh` pins the session that ran it, so a session that starts N features
pins itself into N manifests as a matter of course — and `select_parent` then prices
each of those N features for the **whole** transcript, because a pin is honoured
"whatever the window says" and the window is only ever used to *include* a session,
never to slice it. Measured on the corpus this feature was planned in: session
`3571cc77-…` cost $47.18 and is pinned by four features, which between them book
$188.71 and each report its full 22.8-hour span as their own duration; session
`ed088063-…` cost $70.50 and is pinned by **eight** features across two repos, booking
$563.97. Nothing refuses it and nothing is wrong in the ledger — `record_session_claims`
says outright that two features may both legitimately count one coordinator — but the
disclosure in `also_claimed_by` is the whole remedy today, and the money is not split.

This feature splits it. A session claimed by **more than one** feature is priced by
*concurrent share*: each billable response is attributed to every claimant whose
`session_window` covers its timestamp and divided equally among them; everything before
the earliest claim belongs to the earliest claimant (its planning); everything after the
last claim's `to` belongs to nobody and is reported rather than silently dropped. Time
is partitioned by the same rule, so a feature that took eight minutes stops reporting the
coordinator's 1,367. A session with exactly **one** claimant is priced and timed exactly
as it is today — the over-count only exists when somebody else is also counting, and
slicing a session nobody else claims would trade a disclosed over-count for a silent
under-count.

The rule is exact by construction: the claims partition the transcript, so the shares of
all claimants sum to the session's own cost. On the four-feature session that turns
$188.71 into $47.18 ($31.98 / $9.73 / $3.56 / $1.91); on the eight-feature one, $563.97
into $70.50 with $0.28 falling outside every claim and said so.

`window-slicing-brief.md` beside this file is the brief the bug was reported in, kept
because it is the evidence and because one of its recommendations is deliberately not
taken (see below).

## Plans

| Plan | What it does |
|---|---|
| `auto/incomplete/89-share-arithmetic-tests-sonnet.md` | `self/tests/session-share.sh` — the arithmetic black-box against the real `capture_planning.py`: four claimants over one synthetic session, shares plus the unclaimed remainder equal the undivided total, the head, the tail, a response straddling a boundary billed once, sliced durations, an unshared session unchanged. RED until 91. |
| `auto/incomplete/90-claim-set-tests-sonnet.md` | `self/tests/session-claims.sh` — *who* the claimants are: the other corpus's manifest, a third repo's ledger claim, a manifest outranking its own stale ledger entry, a legacy claim with no window, sidechain lines, and the frozen-record warning. RED until 91. |
| `auto/incomplete/91-share-pricing-sonnet.md` | `analysis/capture_planning.py` and `analysis/transcript.py`: claim collection across both corpora and the ledger, `window` on a ledger session claim, the share walk in `select_parent`, the new `planning.json` fields, the warnings, and `analysis/README.md`'s capture entry. |
| `auto/incomplete/92-gate.md` | Level sentinel — the capture layer must be green before the report layer is built on it. |
| `auto/incomplete/93-report-tests-sonnet.md` | `self/tests/claims-ledger.sh` part B rewritten from "priced in full by both" to the share, plus the two shares summing to the session and a legacy record still reported the old way. RED until 94. |
| `auto/incomplete/94-report-share-sonnet.md` | `analysis/report.py`'s `compute_shared_sessions` and Cost footnote, and the four places that assert no apportionment: `analysis/README.md`, `AGENT_PLANS.md`, `templates/plans/features/TEMPLATE.md`. |
| `verify/incomplete/92-level-capture-sonnet.md` | Level-verify for the 92 sentinel — tier 1 of the ladder if the capture layer is red. |
| `verify/incomplete/95-verify-sonnet.md` | The final verify: the real corpus, a real shared re-capture in a scratch worktree, adversarial windows, and proof the unshared path did not move. |
| `review/incomplete/96-review-opus.md` | The review pass — reads the diff, writes the verdict, opens the PR. |

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| 1 — capture | 89–91 | `92-gate.md` | `92-level-capture-sonnet.md` | shell syntax, `py_compile analysis`, `self/tests/session-share.sh`, `self/tests/session-claims.sh`, `self/tests/capture-guard.sh`, `self/tests/subagent-capture.sh`, `self/tests/claims-ledger.sh` |
| 2 — report and doctrine | 93–94 | final gate | — | everything, `self/tests/claims-ledger.sh` part B included |

Level 1 owns every dollar decision; level 2 only renders and documents them. The sentinel
is where that split is enforced: nothing in level 2 may change what a share *is*.

## Contracts across levels

| Value / identifier | Produced by (plan, file:line) | Consumed by (plan, file:line) | Fixture | Asserted by |
|---|---|---|---|---|
| `planning.json` `sessions[].share_basis` — `[{feature, from, to, source}]`, every claim the split used, this feature's first | 91, `analysis/capture_planning.py` (`capture_feature` serialisation) | 94, `analysis/report.py` `compute_shared_sessions` | — (see below) | 89 `self/tests/session-share.sh` / 93 `self/tests/claims-ledger.sh` B |
| `planning.json` `sessions[].session_cost_usd` — the undivided cost of the whole transcript | 91, `analysis/capture_planning.py` | 94, `analysis/report.py` `compute_shared_sessions` and the Cost footnote | — | 89 / 93 |
| `planning.json` `priced[].share` and `.full_cost_usd` — the divisor and the undivided bucket, `cost_usd` already being this feature's share | 91, `analysis/capture_planning.py` | 94, `analysis/report.py` (sums `cost_usd`, unchanged) | — | 89 / 93 |
| Ledger session claim `window: {from, to}` in `~/.claude/subagent-claims.json` | 91, `analysis/capture_planning.py` `record_session_claims` / `add_session_claims` | 91, `analysis/capture_planning.py` `session_claim_intervals` (cross-repo claimants) | — | 90 `self/tests/session-claims.sh` |

**Fixture is `—` on every row, and that is not an omission.** `self/tests/` has no
`fixtures/contracts/` directory and no consumer that could load one: each script stands
up its own throwaway world under `mktemp -d` with a redirected `$HOME`
(`self/tests/README.md`), and the shared builder is
`self/tests/fixtures/transcripts/build-transcript.sh`, which emits transcript *lines*
rather than a frozen contract. The level-2 test therefore produces its own
`planning.json` by running the real level-1 capture over its own transcripts — which is
the property the fixture rule exists for (the consumer's input was produced by verified
code) reached by a different route, not skipped.

## Deliberately excluded

- **A session with exactly one claimant is not sliced.** The brief recommends slicing
  branch-selected sessions too, "converting the boundary warning into a statement of how
  much was excluded". Not taken: a session nobody else claims has no double-count to
  remove, so slicing it drops dollars that no other feature picks up — a disclosed
  over-count traded for a silent under-count, on every consuming repo, for every feature
  whose session outran its `to`. The `may span the window boundary` warning stays exactly
  as it is. Backlog entry written.
- **`feature-close.sh` still stamps `session_window.to` at close time.** The brief's fix
  part 2 — chain `to` to the next claimant's `from`, or read it off the branch's last
  commit — is what *slicing* would need, because slicing alone leaves three windows
  nested and still triple-counts `14:58→18:50`. Sharing does not need it: overlapping
  claims are the input to the split rather than a defect in it, and three features
  started five seconds apart (`ed088063`'s 22:22:56 / :57 / 23:01) are genuinely
  concurrent — no disjoint stamping can describe them, while an even split gives
  $6.52 / $6.89 / $6.29. Changing the stamp would also rewrite what every existing `to`
  in two corpora means. Backlog entry written.
- **Frozen records are not re-derived.** `--all` still skips a captured feature and
  `annotate_frozen_record` still opens no transcript, so the three records already
  booking $47.18 apiece are repaired only by `capture_planning.py --recapture <slug>`
  followed by `report.py`, and only while the transcript survives. What this feature adds
  is a warning on the annotate path when a shared record carries no `share_basis`, so the
  repair is asked for rather than assumed.
- **No apportionment of subagents.** A subagent transcript still belongs to exactly one
  feature and a second claim is still refused; only top-level sessions are shared.

## Machine-readable

```json
{
  "slug": "shared-session-share",
  "method": "plans",
  "plans": ["89-share-arithmetic-tests-sonnet", "90-claim-set-tests-sonnet", "91-share-pricing-sonnet", "92-level-capture-sonnet", "93-report-tests-sonnet", "94-report-share-sonnet", "95-verify-sonnet", "96-review-opus"],
  "branches": ["shared-session-share"],
  "base": "main",
  "session_window": {"from": "2026-09-08T19:02:29Z", "to": "2026-09-08T23:47:25Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": ["ed76cd6f-477a-4b4e-84fd-c7a340538f14"],
  "subagents": []
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base, `from`, and a pin for the session that ran it — and
`feature-close.sh` stamps `to` when the feature is closed
(`agentTooling/LIFECYCLE.md`). Do not hand-copy it. Only `slug`, `plans` and `branches`
are required: `method` reads as `"plans"` when absent, `base` as `main`,
`session_window` as unbounded, and the four id lists as empty. These are the ones that
go wrong quietly:

- **`method`** — optional, `"plans"` when absent. `"direct"` marks a feature built per
  `agentTooling/AGENT_DIRECT.md` by one implementer delegate; `"hand"` one the
  coordinator built itself, with no delegate to pin and no plans. Under either, the
  transcripts `planning.json` captures are the **build**, and `analysis/report.py` files
  their dollars and minutes there instead of under planning — as `build: implementer`
  and `build: by hand` respectively. Leave it out for a planned feature; a wrong value
  here moves money between buckets without a warning about which was right.
- **`base`** — the branch the feature branched from, `main` unless
  `feature-start.sh --base` said otherwise. `run-review.sh` reads it and exports
  `FEATURE_BASE`, which is the base `plans/pr.sh` opens the PR against, so a feature
  stacked on one that has not merged shows only its own diff. Cost capture ignores it.

- **`branches`** — copy each name from `git branch --show-current`, verbatim. It is
  matched literally against the `gitBranch` in every session transcript, so an added
  owner prefix, or a name retyped from memory, matches nothing and leaves every session
  on it uncounted — the feature then reports `$0.00`, which reads as "planning was free"
  rather than "this manifest is wrong". `analysis/capture_planning.py` warns when a
  declared branch matches no transcript. If a branch was renamed mid-feature, list both
  names: transcripts keep whatever name was current when they were written.
- **`plans`** — every plan stem in the table above, *without* the `.md` extension and
  without its queue/state path, in batch order. `analysis/report.py` prices exactly this
  list: a stem left out is a plan whose cost lands in no report, and an array left out
  entirely drops the whole feature back onto a fallback that can only see plans which
  already ran.
- **`session_window` timezone** — end every bound with `Z`. A bound with no offset is
  read as UTC, and the natural place to find a timestamp is `git log`, which prints
  **local** time — so a value copied from there and pasted bare is silently off by your
  UTC offset, four hours in US Eastern, which is enough to hand a session to the wrong
  feature. Write local time only with its offset spelled out (`2026-07-17T18:00:00-04:00`);
  `analysis/capture_planning.py` warns on any bound that states no zone.
- **`sessions`** — session ids claimed outright, across every project directory,
  regardless of branch, window or `cwd` — the top-level twin of `subagents`.
  `feature-start.sh` pins the session that ran it, which is what claims a planning
  session that began on `main` before the branch existed; widening `branches` to `main`
  instead sweeps in every later session in that checkout. A pinned session that branch
  and window would also select is priced once, and every entry in `planning.json`
  records how it was selected (`selected_by`: `"pinned"` or `"branch"`) and the `cwd` it
  was launched in. A pin that is also in `exclude_sessions` warns, and the pin wins.
  Find an id with `python3 agentTooling/analysis/capture_planning.py --list-sessions
  [--unclaimed] [--since <date>]`, which prints every session launched in this repo's
  primary checkout or one of its feature worktrees with its branch, `cwd`, cost and
  opening prompt.
- **`subagents`** — optional; usually absent. Agent ids of delegates whose *parent*
  session was not on this feature's branch — the coordinator-on-`main` case. A subagent
  inherits its parent's `gitBranch` at spawn and never records its own, so an architect
  spawned from `main` is invisible to `branches` and `session_window` alike; pinning its
  id claims it outright. Find the id with
  `python3 agentTooling/analysis/capture_planning.py --list-subagents --since <date>`,
  which prints each one's cost and opening prompt. A subagent whose parent *is* on the
  branch needs no pin — it is claimed with its parent when its own start is in the window.
  A pin wins over an `exclude_sessions` entry naming its parent: excluding the coordinator
  drops the coordinator's own context cost and keeps the pinned architect. Runner sessions
  are the exception — their usage.json already holds the cost, pins included. A
  delegate's transcript is filed under its *parent's* cwd, so one spawned by a
  coordinator sitting in another repo is found by `--list-subagents --everywhere`
  and pinned here all the same. `--list-subagents --unclaimed` is the standing
  question — every delegate on this machine no feature has claimed, with the
  feature its brief names; a pin already claimed by another feature refuses the
  capture rather than counting twice.
- **`exclude_subagents`** — optional. Delegates of a session this manifest *does* select
  that belong to another feature — a coordinator's manifest (on `main`, windowed around
  the run) lists the architect it spawned, which the arm's own manifest pins. Without it
  the parent route claims the architect here too and the ledger refuses the other
  capture as a double claim.
- **`session_window.to`** — `null` means "still open", and open is the right value only
  while the feature is still being planned. Set a real bound as soon as it is done. Two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
