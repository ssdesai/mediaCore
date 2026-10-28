# bounded-opening-stretch — implementer brief

feature: agentTooling/bounded-opening-stretch

## Where

Worktree `/Users/sahildesai/dev/agentTooling-bounded-opening-stretch`, branch
`bounded-opening-stretch`, base `main`. Work only there. This is a direct build
(`AGENT_DIRECT.md`): you write the acceptance tests first and commit them red, then the
change, then `NOTES.md` and `CHECKPOINT.md`, and you stamp timing as that file says.

## Read order

1. `AGENT_DIRECT.md`, then `self/PROJECT_FACTS.md` and `self/tests/README.md`.
2. `analysis/README.md` → the share paragraph that begins "A session with more is split
   by concurrent claim" (around line 285) through the end of the paragraph on the
   empty-window ranking (around line 312).
3. `analysis/capture_planning.py`: `share_owners`, `partition_seconds`, the per-response
   split in the scan (`iter_billable_messages_at` … `share_owners(moment, intervals)`),
   `is_empty_window`, `check_empty_window`, and the "unclaimed by any feature" warning.
4. `self/tests/session-share.sh` in full — its header lists every phase; the fixture
   builder is `self/tests/fixtures/transcripts/build-transcript.sh`.

## The defect

`share_owners`' fallback hands every instant before the earliest `from` to the earliest
claimant, however far back that stretch reaches. The rationale in its docstring — "a
session's opening stretch is the planning that led to the first feature it started" — is
true of minutes and false of days. Measured on session `2d8b1236` (2026-09-04T16:47Z to
2026-09-06T16:28Z, $58.47 of its own cost): three agentTooling self features claim it,
all windowed on 2026-09-06 — `stale-failed-sidecars` 14:00:51–14:25:53,
`recover-cost-at-close` 14:01:40–15:11:48, `stream-capture-file-first` 15:06:37–16:05:10.
`stale-failed-sidecars`, earliest by 49 seconds, therefore owns the 45-hour head: $50.12
of its $50.92 share, against a window 25 minutes long. That head was the coordination of
fifteen features in three other repos, each of which selects its sessions by branch and
never claims this one. No rule can attribute it correctly; the honest answer is the one
the tail already gets — unclaimed, disclosed, with the remedy named.

## Rulings (settled — do not reopen)

1. **The opening stretch is bounded by the earliest claimant's own window length.** An
   instant before every dated claimant's `from` belongs to the earliest claimant (the
   same `min` on `(from, feature)` as today, over the same dated, non-empty pool) only
   when it lies no further before that claimant's `from` than that claimant's window is
   long — `min_from - moment <= to - from` of the earliest claim. Earlier than that,
   nobody owns it: `share_owners` returns `[]` and the response or span falls to the
   unclaimed remainder exactly as the tail does. An earliest claimant whose `to` is
   `null` (still in flight) keeps the unbounded head — its close stamps `to`, and the
   recapture that follows applies the bound. A relative bound and not a fixed one, because
   the head is planning for the feature that follows, and that scales with the feature;
   a fixed hour would pay a two-minute feature an hour it did not plan for.
2. **One rule, written once, for both the dollars and the seconds.** Introduce a helper
   beside `share_owners` — name it for what it answers, e.g. `head_bound(intervals)`,
   returning the earliest instant the opening-stretch fallback may pay (or `None` when
   the fallback is unbounded or there is no dated claim). `share_owners` consults it, and
   `partition_seconds` adds it to its cut points so the duration split and the cost
   split cannot disagree — the `is_empty_window` pattern. Without that edge the whole
   `[start, min_from)` span is judged at `start` and the paid part of the head is lost
   from `duration_s`.
3. **No new `planning.json` field.** The head that nobody owns goes into the existing
   `unclaimed_usd` and `unclaimed_duration_s`; the sum invariants stay as they are. What
   changes is the disclosure: the "unclaimed by any feature" warning must, whenever any
   of the unclaimed remainder lies before every claimant's `from`, say how much of it
   (dollars and seconds) is that head, and name the remedy for that side — pin the
   session into the feature that work belongs to, or move the earliest claimant's `from`
   back by hand (`from` has no `set-window-to`; say so). The tail's sentence stays as it
   is when the remainder is all tail.
4. **The empty-window rules are untouched.** `is_empty_window`, `check_empty_window`, the
   ranking pool and phases 9–11 of `session-share.sh` stay exactly as they are. The bound
   is computed from the earliest *non-empty* dated claim.
5. **Nothing frozen moves in this build.** Do not recapture any real feature; the
   coordinator recaptures the three `2d8b1236` claimants after this merges. `git diff
   main...HEAD -- 'self/features/*/planning.json'` must be empty.
6. **The existing head test stays green as the no-change half.** Phase 3 of
   `session-share.sh` (share-a, window 10:00–18:00, head response at 08:00) is two hours
   before an eight-hour window and is still paid. Do not weaken it.

## Acceptance tests (write first, commit as `bounded-opening-stretch: acceptance tests`)

Extend `self/tests/session-share.sh` with a new numbered phase (15) on a **fresh**
session id, so nothing earlier in the file is re-run or disturbed. Two claimants pin it:
`head-a` windowed 10:00–11:00 (one hour) and `head-b` 12:00–18:00, both on
`$MANIFEST_BRANCH` as the fixture does. Responses: r0 at 08:00 (two hours before
`head-a`'s `from`, beyond its one-hour window), r1 at 09:30 (inside the hour), r2 at 10:30
(inside the window), r3 at 13:00 (`head-b` alone). Compute expected shares from the
fixture's token counts as the existing phases do. Assert, reading `planning.json` and the
capture output only:

- 15a. `head-a`'s `cost_usd.total` is r1 + r2 — r0 is not in it;
- 15b. `unclaimed_usd` on the session entry is exactly r0's share of the session cost, and
  the two totals plus the remainder equal `session_cost_usd`;
- 15c. `head-b`'s total is r3 alone;
- 15d. `unclaimed_duration_s` is the span before `head-a`'s bound (08:00–09:00) plus the
  uncovered gap between the windows (11:00–12:00), `head-a`'s `duration_s` is 09:00–11:00,
  and the apportioned spans plus the remainder sum to `session_duration_s`;
- 15e. the capture output's unclaimed warning names the head's dollars and seconds
  separately from the tail's and names both remedies (pin; `from` by hand);
- 15f. with `head-a`'s `to` set to `null`, r0 is paid to `head-a` and `unclaimed_usd` holds
  none of it — the in-flight case keeps today's behaviour. `write_manifest` will need to
  accept a null bound; keep the change minimal.

15a, 15b, 15d and 15e must be red against `main`'s `capture_planning.py` (copy it from
`git show main:analysis/capture_planning.py` into the sandbox); 15c and 15f are green
before and after and are the guard. Record the red-proof table and the mutation in
`NOTES.md`. Every earlier phase stays green throughout.

Update the `session-share.sh` row in `self/tests/README.md`.

## Docs

`analysis/README.md` — the share paragraph's rule sentence ("the opening stretch before
any window opens goes to the earliest claimant alone") becomes the bounded rule, and the
empty-window paragraph that follows still reads true against it; `share_owners`' and
`partition_seconds`' docstrings; `self/PROJECT_FACTS.md` if it states the rule (grep
"opening"). `self/BACKLOG.md`: add an entry for anything in scope you leave undone; there
is none to close.

## The finish

Gate green (`bash self/gate.sh`), then commit on the branch — code, tests, docs,
`NOTES.md`, `CHECKPOINT.md` at `status: committed`. Do not push, do not open a PR, do not
edit the manifest's fence. Never mutate repo-wide VCS state: no stash, checkout, reset,
clean, branch switch, rebase. Never touch `~/.claude` or `~/dev/agentTooling`.

## The report

Terse: the gate's verdict line and counts; files added/changed; each ruling you had to
make beyond the ones above and where it is recorded; the red-proof table; anything in
scope left undone and why.
