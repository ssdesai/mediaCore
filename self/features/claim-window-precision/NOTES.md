# Notes — claim-window-precision

Rulings the brief left open, deviations from it and why, and the mutation every new
assertion was proved red against. Written as the build went, per `AGENT_DIRECT.md` step 4.

## Rulings

1. **`--last-branch-instant` prints the BOUND, not the raw last instant.** The brief
   defines the evidence as "one second after the last instant" and then says the CLI
   "prints that instant"; the flag's name points the other way. The arithmetic lives in
   the CLI because `feature-close.sh` is bash and adding a second to an ISO timestamp
   there is a second implementation of the rule in a language with no datetime type. The
   flag keeps the name the brief pins; the help text, `analysis/README.md` and the
   docstring all say it prints the bound.

2. **The bound is truncated to whole seconds before the second is added.** A real
   transcript timestamp carries milliseconds, so `last + 1s` would write
   `2026-09-07T19:30:02.245000Z` into a fence where every other bound — `from` included,
   which `manifest.py init` writes with `%H:%M:%SZ` — is second-resolution. `replace(
   microsecond=0) + 1s` is still strictly after the instant it came from (`…:56.700`
   yields `…:57`), so nothing is lost and the fence stays uniform.

3. **A runner session counts as evidence. Deviation from the brief's letter, measured.**
   The brief says branch-selected means "what `select_parent` selects by `branches` +
   `session_window` … minus `exclude_sessions`", and `select_parent` is never reached for
   a session some `usage.json` already holds. Taken literally the branch route finds a
   bound for **1 of agentTooling's 16 features**; counting runner sessions finds one for
   **9**, each between one and eleven hours tighter than the `to` the close had stamped
   (`feature-lifecycle` 05:46:54 → 20:06:16 the previous evening;
   `tooling-backlog-2026-09-06` 15:42:50 → 04:29:43). Every one of the nine is EARLIER
   than the recorded bound, so tighten-only holds across the whole corpus. The two rules
   answer different questions: the capture's exclusion says what this record may PRICE (a
   runner session's dollars are in its own sidecar), while the bound says when work on the
   branch STOPPED, and a `claude -p` executor draining a plan in the feature's own
   worktree is the plainest evidence of that there is. Reading it the other way would have
   left `feature-close.sh` back at its wall clock for every plans- and direct-method
   feature — the defect. The manifest's own `exclude_sessions` IS honoured. Recorded in
   the function's docstring, in `analysis/README.md`, and named here because it is the one
   term a reviewer should check against the brief.

4. **"Not by pin" means the pin ROUTE, not the pin list.** A session that the branch route
   would select anyway — on the branch, in the window, launched somewhere claimable — is
   evidence whether or not the manifest also pins it; the pin is redundant there. The
   brief's stated reason for excluding pins is that "the pinned coordinator started N
   features and outlives all of them", and such a coordinator sits on `main` in the
   primary checkout, which the branch test already rejects. Reading it as "drop any id in
   `sessions`" would additionally discard genuine branch evidence, and would break
   `recover-at-close.sh`'s fixture, whose one session is pinned AND on the branch — the
   fixture that documents a real flake caused by a `to` landing in the same second as the
   transcript, which stamping from evidence removes by construction.

5. **A tighten refusal warns the close; it does not fail it.** `set-window-to --tighten`
   exits non-zero on a later instant (asserted, W4a-c). `feature-close.sh --recapture`
   prints `warn      session_window.to was left as it is — a bound is never widened` and
   continues to the capture. Failing there would strand the repair the run came for behind
   a hand edit, and would protect nothing the refusal has not already protected: the bound
   it declined to widen is the one already published.

6. **An EQUAL bound is a no-op under `--tighten`, not a refusal.** `recover-at-close.sh`
   C12 pins that a `--recapture` over a feature just closed leaves `to` where the first
   close put it — and the second run re-derives exactly the same evidence, so "only
   earlier" had to mean "refuse only strictly later". Asserted directly (W4d).

7. **`STAMPED` is read off `git status --porcelain -- <manifest>`, not off the stamp's
   output.** The primary is verified clean at entry and nothing before step 6 touches the
   manifest, so a dirty manifest at that point is this stamp and nothing else. That makes
   `rollback_stamp` exact without parsing three different success messages.

8. **The index keeps `features_dir` per entry.** `session_claim_intervals` excludes its
   own feature by `(features_dir, slug)`, not by slug alone — two features may share a
   slug across the two corpora (`claims-ledger.sh` part D) — so the index carries the
   directory each manifest was read from.

9. **`session-share.sh` phase 13 tightens `share-d` to 16:15, not to the 16:00 the brief
   suggested.** `share-d`'s `from` is 16:00, so a `to` of 16:00 makes its own window
   *empty*, and an empty claim is already dropped from every other feature's claim set by
   `shared-session-share`. The assertion would then pass against a build that ignored `to`
   entirely for non-empty windows — it would be testing the empty-claim drop, not the
   tightened bound. 16:15 is after `from` and before `r4` at 16:30, so share-d owns
   nothing for the reason the phase is named. Recorded in `self/tests/README.md` too.

10. **The W phase went into `feature-lifecycle.sh` rather than a new
    `self/tests/window-stamp.sh`.** The brief allows either. That file already stands up
    the whole close scaffolding — a real git repo with a bare origin, stub gate/`claude`/
    `gh`, `project_dir`, `start`/`close`/`fence`/`pj` — and the phase reuses all of it in
    ~60 lines; a new file would have duplicated ~120 lines of setup to assert four things
    about the same script. `feature-lifecycle.sh` is now 460 lines.

11. **`outside_window_cost` reports `at least` when a model in that stretch has no rate**,
    rather than silently dropping it. The unclaimed remainder already warns in that case;
    a disclosure warning that quietly under-reports is the failure mode this whole item
    exists to remove.

## Deviations from the brief

- Ruling 3 (runner sessions count as evidence) is the one substantive deviation, and it is
  the difference between the feature working on 9 of 16 features and on 1.
- Ruling 9 (16:15 rather than 16:00) changes a test value the brief gave parenthetically,
  to keep the assertion from being satisfiable by pre-existing behaviour.
- `templates/plans/features/TEMPLATE.md`'s `session_window.to` bullet was updated too. The
  brief named `AGENT_PLANS.md` for the same contradiction; the template says the same
  thing and is copied verbatim into every manifest `feature-start.sh` writes, so leaving
  it would have shipped the contradiction to every new feature in every consuming repo.

## Every new assertion, and the mutation it went red against

Each mutation was applied to the working tree, the test run, the FAIL observed, and the
file restored from a copy. No VCS state was touched (`git show <base>:<path>` reads only).

| Assertion | Pins | Mutation it went red against |
|---|---|---|
| `feature-lifecycle.sh` W1b, W1c | `to` is the branch session's last instant + 1s, and that session is still captured under the exclusive bound | **M1** — `feature-close.sh` restored from `shared-session-share`. `to` becomes the close's own clock. |
| `feature-lifecycle.sh` W2b, W2c | no branch session announces the fallback | **M1**. No `no branch session` line is printed at all. |
| `feature-lifecycle.sh` W3b, W3c | `--recapture` tightens onto the evidence, printing `old -> new` | **M1** (the close passes no `--tighten` and no timestamp) and **M2** — `analysis/manifest.py` restored from `shared-session-share` (the flag does not exist). |
| `feature-lifecycle.sh` W4b, W4d | the refusal names both bounds; an equal bound is a no-op | **M2**. W4a alone passes vacuously under M2 — argparse also exits non-zero — which is why W4b asserts the message and W4d the exit-0 no-op. |
| `session-share.sh` 12c-12f | the boundary warning's dollars, seconds, `counted in full`, and the total still counting them | **M3** — `boundary_warning(…)` in `select_parent` replaced by the old one-line warning. |
| `session-share.sh` 12g | the same warning says `not counted` on the share path | **M3**. |
| `session-share.sh` 13a-13c | `--tighten` moves the bound and the split follows it | **M2**. share-d keeps r4 and share-c's total does not move. |
| `session-claims.sh` 7e | the `predates the share rule` WARN fires on a sweep that wrote nothing | **M4** — `annotate_frozen_record` returns `(None, False)` when unchanged and the call site iterates `annotated or []`. |
| `session-claims.sh` 9 | the claimant scan parses each manifest once per capture | **M5** — `session_claim_intervals` calls `build_claimant_index` itself instead of reading `share_ctx["claimants"]`. |

`session-share.sh` 12a, 12b, 13d and `session-claims.sh` 7d, 7f are guards rather than new
behaviour: they hold before and after, and their job is to keep the assertions beside them
from passing for the wrong reason (12a — the session really is unshared; 12b — the warning
fires at all; 13d — the sum invariant survives; 7d/7f — the second sweep really wrote
nothing and still says `skipping`).

## Proof on the real corpus

`python3 analysis/capture_planning.py --self --all` (no `--recapture`) over the live
corpus: `16 features: 0 captured, 11 already captured, 0 refused, 5 in flight`,
`git diff -- 'self/features/*/planning.json'` empty — nothing frozen moved. The same run
printed the `predates the share rule` WARN for three records
(`stale-failed-sidecars`, `stream-capture-file-first`, `tooling-backlog-2026-09-06`) whose
annotations had already converged, which is precisely the case that printed nothing
before: item 3, on the corpus that raised it.

`--last-branch-instant` over all 16 features gives a bound for 9, every one earlier than
the `to` recorded there, so `feature-close.sh --self <slug> --recapture` tightens rather
than refusing on any of them. The two stale over-counts named in the backlog entry need
that run anyway.

## Open

- The in-flight co-claimant limit is in `self/BACKLOG.md` as this feature's entry.
- Nothing in this feature re-stamps the bounds already written. The repair is per feature
  and by hand, as the manifest's "Deliberately excluded" says.

# Rework — review escalations 1–5

The review pass escalated five findings (`self/review-report.md` → "Escalated to the next
batch"); this section is the rework one-shot's half of this file. Rulings continue the
numbering above; the red-proof table is its own, because these assertions were proved
against mutations of the *reworked* tree, not of `shared-session-share`.

## Rulings

12. **The widen refusal gets exit code 3, not 2.** The review suggested 2. argparse exits
    2 on a usage error — a flag `feature-close.sh` passed wrongly, a missing argument —
    and a close that read that as a declined widen would stamp nothing, warn about a cause
    that did not happen, and then capture, commit, push and delete the branch, leaving a
    closed feature with a permanently open window: the exact defect item 3 reports, moved
    rather than fixed. `WIDEN_REFUSED_EXIT = 3` in `manifest.py`, `WIDEN_REFUSED_RC=3` in
    `feature-close.sh`, and the close matches on the code and on nothing else — not on the
    message, which would break the first time the wording changed, and not on "non-zero".

13. **A stamp refusal rolls back the carry and the recovery, and never the stamp.**
    Symmetry with the capture refusal is the rule (ruling 7 and `rollback_stamp`), but the
    stamp is not one of the three things to undo on its own failure: `set-window-to`
    writes the manifest only on a path that exits 0, so there is nothing on disk to
    restore, and `STAMPED` is computed after this point anyway. The two rollbacks that DO
    apply are `rollback_carry` and `rollback_recovery`, called exactly as the capture
    refusal calls them, which is what W5d asserts byte for byte.

14. **The `from` refusal is scoped to `--tighten`, and ordered last of the three checks.**
    Order: refuse a widen (3), no-op an equal bound (0), then refuse a bound at or before
    `from` (1), then write. Putting the `from` check first would turn `--recapture` over an
    already-empty window from ruling 5's warn-and-continue into a hard refusal, and would
    break ruling 6's C12 no-op on such a manifest; last, it fires only on a bound this run
    would actually write. Not applied to the plain stamp of a `null` bound, because that
    bound is either the evidence (one second past a session that started at or after
    `from`, so strictly later than `from`) or this run's clock — neither can precede
    `from`, so a check there would guard nothing and could only misfire on a manifest
    whose `from` is itself wrong.

15. **Items 1 and 2 share one fixture, and both instants carry `.700`.** Taken literally
    the review's two fixture lines cancel: a delegate ending at `13:00:00Z` makes the
    parent's `12:00:00.700Z` irrelevant to the bound, and item 2's assertion would then
    pass with the truncation deleted. So the delegate ends at `13:00:00.700Z` and the
    parent at `12:00:00.700Z`: W1b's one exact `to` is red against BOTH mutations, and
    W1d — the bound matches a second-resolution regex — pins the truncation on its own.

16. **The zero-quantity branch needs the dollars AND the seconds to be nothing.** Not
    either: an unbilled ten-minute tail is a real overrun that the seconds describe
    truthfully, and a sub-second overrun that cost money is real money. Both zero is the
    only shape where the sentence would assert a measurement of nothing, and it is the
    shape a trailing `user` line or `<synthetic>` notice produces. Two named constants
    (`NO_OUTSIDE_COST_USD`, `MIN_REPORTED_OUTSIDE_SECONDS`) rather than bare literals,
    since the second one carries the reasoning that `seconds` is already an `int`.

17. **`user_line` moved into `build-transcript.sh` rather than being copied.** It was
    local to `recover-duration.sh`, which sources `build-transcript.sh` anyway, so a
    second copy for `session-share.sh` would have been a duplicate helper in a file that
    already sources the shared one. Same signature, same body; `recover-duration.sh` keeps
    a comment saying where it went, and its assertions still pass.

18. **W4i, the primary-clean guard, is load-bearing.** `manifest.py` writes to a manifest
    tracked in the throwaway checkout's PRIMARY, so a refusal that wrote anyway leaves the
    primary dirty — and W5's close would then refuse on the dirty primary rather than on
    its own stamp, passing for the wrong reason. That is exactly what happened under
    mutation M9 (see the table), which is the evidence that the guard is not decoration.

19. **The tolerated exit code is written down twice, so it gets an assertion of its own.**
    `manifest.py` cannot export a constant to bash, so `WIDEN_REFUSED_EXIT = 3` has a twin
    `WIDEN_REFUSED_RC=3` in `feature-close.sh`, and nothing but a test keeps the two in
    step — a drift would turn ruling 5's warn-and-continue into a refused close on every
    repair run. W6 pins it from the close's side: a `--recapture` whose evidence would
    widen the bound warns, captures anyway, and leaves the published bound alone. Added
    during the build rather than in the tests-first commit, because it guards an
    implementation choice (a duplicated literal) that did not exist when the tests were
    written; it is a guard, not a spec assertion — it holds against the pre-rework tree
    too, and goes red only against the drift itself.

20. **W6's shape is why the W1 fixture has a middle line.** The evidence is clamped by the
    window it is derived under — a session is only evidence if its START is in the window —
    so the only bound the evidence can exceed is one written BETWEEN a selected session's
    first line and its last. The W1 session therefore runs `12:00:00.700` to `12:45` (with
    the delegate on to `13:00:00.700`), and W6 sets the bound to `12:30`. With a
    single-line session there is no such bound and the widen path is unreachable from a
    close at all, which is the sense in which ruling 5's tolerated refusal is rare.

## Deviations from the rework brief

- None on substance. The one departure from the *review's* suggested shape is ruling 12's
  exit code (3, not the 2 the review proposed), which the brief settled the same way.

## Every new assertion, and the mutation it went red against

Each mutation was applied to the working tree, the test run, the FAIL observed, and the
file restored from a copy taken first. No VCS state was touched.

| Assertion | Pins | Mutation it went red against |
|---|---|---|
| `feature-lifecycle.sh` W1b, W1c | the bound is one second past the DELEGATE's last instant, and both the session and the delegate are still captured under it | **M6** — the subagent walk in `last_branch_instant` deleted. `to` falls back to `12:45:01Z`, the parent's own last instant, which then excludes the delegate the capture had claimed. |
| `feature-lifecycle.sh` W1b, W1d | the bound is at second resolution though the evidence carried milliseconds | **M7** — `latest.replace(microsecond=0)` dropped. The fence reads `2026-06-01T13:00:01.700000Z`, which parses everywhere and fails nothing else. |
| `feature-lifecycle.sh` W4a | the widen refusal carries its own exit code | **M8a** — `cmd_set_window_to` returns 1 instead of `WIDEN_REFUSED_EXIT`. |
| `feature-lifecycle.sh` W5a–W5e | a stamp that fails for any other reason refuses the close, names what `set-window-to` printed, captures nothing and rolls the carry back | **M8b** — the stamp block restored to `if ! set-window-to; then warn; fi`. The close exits 0, writes `planning.json`, commits and pushes a feature whose window is still open, and prints the widen warning for a widen that never happened. |
| `feature-lifecycle.sh` W4e–W4i | `--tighten` refuses a bound at or before `from`, as a plain 1, leaving the fence byte-identical and the primary clean | **M9** — the `from` check removed from `cmd_set_window_to`. The empty window is written (W4e/W4g), the AT-`from` case is then refused as a widen instead (W4h), and the primary is left dirty (W4i), which drags W5b/W5d/W5e down with it. |
| `feature-lifecycle.sh` W6a | the close continues past the widen refusal, and past that code alone | **M11** — `WIDEN_REFUSED_RC` in `feature-close.sh` drifted to 2, the twin of `WIDEN_REFUSED_EXIT` left at 3. Every declined widen then refuses the close. |
| `session-share.sh` 14c, 14d | the warning discloses no quantity when there is none | **M10** — the zero branch removed from `boundary_warning`. It prints the quantified sentence again: `$0.0000 and 0s of it fall at or after` the bound, `counted in full`. |

`feature-lifecycle.sh` W1a, W4b–W4d, W6b, W6c and `session-share.sh` 14a, 14b, 14e are guards rather
than new behaviour: they hold before and after, and keep the assertions beside them from
passing for the wrong reason (W1a — the close really did succeed; W6b/W6c — the warning
and the untouched bound, which hold under M11 too and would let W6a pass alone; W4b–W4d — the widen
refusal's message and the equal-bound no-op are unchanged by the new exit code; 14a — the
session really is on the unshared path; 14b — the warning fires at all, so 14c is not
measuring its absence; 14e — the session is still priced whole).

## Open

- Nothing from the five escalations is left unbuilt. The `to` bounds already written in
  both corpora still need their per-feature `feature-close.sh --self <slug> --recapture`,
  which is the pre-existing entry in `self/BACKLOG.md`, not new work from this rework.
