# Notes: recover-cost-at-close

What changed and why, the pre-fix RED lines, what the stream turned out to hold, the
re-capture procedure for the coordinator, and the open questions.

## What changed

**Ruling 1 — the sidecar says when it is unpriced, and why.**
`plan-runner-lib.sh::write_usage_sidecar` now writes `result_event: "seen"` when the
stream held a `type == "result"` event and `"missing"` when it did not. It sits beside
`outcome` at the top level, and like `subtype`/`is_error`/`model_usage` it describes the
latest attempt. `outcome` is unchanged and still comes from the exit code: these runs
really did complete, and rerouting a resultless success to `failed/` would make the plan
queue lie to fix a bookkeeping problem. `analysis/backfill_usage.py` writes the same key
(always `"seen"` — it returns early on a stream with no result event), keeping the
field-for-field interchangeability its docstring promises.

**Every reader of the new field.** `analysis/report.py::unpriced_reason` is the only one,
and everything else goes through it: `compute_cost_rollup` (both `priced_without_cost`
sites), the printed cost line, and `report.md`'s **Unpriced plans** block. It reads
`result_event` first and consults `outcome` only to separate `killed` from `no result
event` once a null cost has established that there is *something* to explain — never to
decide whether a plan is priced. A sidecar written before the field existed reports
`no cost reported, cause not recorded` rather than guessing.

**Ruling 2 — the close recovers before it captures.** `analysis/recover_attempts.py`
gains `--for <slug>`, which scopes the walk to one feature directory and refuses a slug
that names none (exit 2) rather than reporting a quiet "0 recovered" a caller would read
as clean. Without it the whole-tree walk `sweep.sh:73` makes is unchanged.
`feature-close.sh` gains a step between its old 4 and 5 — the header's nine numbered
steps are now ten — that runs it and reports any failure without stopping the close.

The cost-file list is extended: `COST_FILES` keeps the five flat names, and a new
`COST_USAGE_GLOB="*/*.usage.json"` covers the per-plan sidecars, which are not flat names
(`<queue>/<state>/<stem>.usage.json`, one level deeper for an archived batch). `*` spans
`/` in a `case` pattern, so every depth is covered; the leading `*/` keeps it to a sidecar
inside a queue. `stray_paths` consults both, so the recovered file is committed rather
than refused as a stranger's work — and the glob is deliberately narrower than "anything
under the feature dir", since a plan `.md`, a progress log or a stream still belongs to
whoever put it there.

**A gap in ruling 2, closed rather than left.** The ruling put the step before the
capture but said nothing about the capture's refusal path, whose standing contract is
"the primary is exactly as this run found it" — `rollback_carry` exists precisely so a
refusal does not leave dirt the *next* run then refuses on. Recovery rewrites files in
the primary, so without a matching rollback the first refusal would have caused a second
one naming a cost record the human must not simply discard. Added `rollback_recovery`,
called beside `rollback_carry`. Nothing is lost: every recovered figure is still derivable
from a transcript that is still there, and the re-run derives it again.

**Ruling 3 — never a bare `$0.0000` for a bucket that had work.** `compute_cost_rollup`
now returns `unpriced_plans[{plan, queue, reason, recovery}]` alongside the existing
`priced_without_cost`, filled at both sites that append to it. The summing is untouched
(the sibling's): the only additions inside the loop are a `find_queue_segment` call and
two list appends on the paths that already `continue` or already warn. The printed line
renders each bucket through `cost_bucket_cell`:

    close-unpriced: total $0.0130 — planning $0.0000 (0.0%), build $0.0130 (100.0%),
    verify $0.0000 (0.0%), review $0.0000 (0.0%, unpriced: 02-review-opus — no result
    event, transcript not found); time 0.0 min (partial)

`(partial)` on the total is untouched. A fully recovered plan is not reported as unpriced,
because it has real dollars. `report.md` gains the same facts as an **Unpriced plans**
paragraph, and the existing "Unpriced attempts" text stops saying killed-only.

**Ruling 5 — the docstrings.** `recover_attempts.py`'s module docstring now opens on the
two cases and states outright that nothing is gated on `outcome`; `analysis/README.md`'s
entry, its `usage.json` entry, its cadence step 3 and its retention-clock bullet say the
same. `LIFECYCLE.md` steps 6 and 7 follow.

**Ruling 7 — `self/BACKLOG.md`.** Created (it did not exist on this branch); five entries,
listed below.

## The RED lines

`self/tests/recover-at-close.sh`, run before any implementation. 11 of the then-20
assertions failed:

    FAIL  A1. a stream with no result event records result_event: missing (got None)
    FAIL  A5. the same run WITH a result event records result_event: seen (got None)
    FAIL  B1. --for <slug> recovers a complete-outcome null-cost attempt (rc 2, got None on a 'complete' attempt)
    FAIL  B3. ... reporting one attempt recovered, not two
    FAIL  B4. --for an unknown slug is refused (got 2), naming it, and writes nothing
    FAIL  C1. the close exits 0 (got 1)
    FAIL  C2. the review sidecar on main carries a recovered cost (got <absent>)
    FAIL  C3. the printed cost line is not a bare $0.0000 review bucket
    FAIL  C4. the rewritten usage.json is inside the 'close-recovers: cost records' commit (got: )
    FAIL  C6. a close whose recovery finds no transcript still exits 0 — reported, never fatal (got 1)
    FAIL  C8. ... and the review bucket names the plan, why it is unpriced, and what recovery did

C10–C12 (`--recapture` over an already-closed feature) were added after the fix as the
evidence for ruling 4 and were never red; they are a regression guard, and the file says
so. Two anti-vacuity guards were added during the RED pass because the first draft passed
for the wrong reason: **B4** needed `! grep -qi unrecognized`, since argparse reads
`--for` as an abbreviation of `--force` and rejects the slug as a stray positional — an
exit 2 naming the slug, for entirely the wrong reason; and **C9** asserts the *absence* of
`review $0.0000 (0.0%);`, which is a substring of the annotated line and so cannot pass
once the annotation exists.

## What the stream actually held

The brief allowed ten minutes. The `.stream.jsonl` is gitignored and dies with the
worktree, so for `pin-ruff` there is nothing left to read — but the derived evidence is
sharper than the missing result event alone, and a fresh occurrence arrived mid-build
(agentTooling `stale-failed-sidecars`, review `84-review-opus`, closed 2026-09-06) with
the same shape:

- The **session transcript** of every affected run ends normally. pin-ruff's last line is
  an ordinary `assistant` message, `stop_reason: "end_turn"`, "Review complete. Verdict
  written to `plans/review-report.md`", with 20 billable assistant messages;
  `stale-failed-sidecars`' has 52 and ends the same way. Neither is a killed session.
- The sidecar carries a `session_id`, which can only have come from
  `write_usage_sidecar`'s `$events[0].session_id` fallback — so the captured stream held
  at least the `init` event.
- **The `.progress.md` beside every one of the nine is 0 bytes.** `log_stream_events`
  writes a line per mutating `tool_use`, and these reviews did edit files. So the captured
  stream held no `assistant` events either — it stopped a few hundred bytes in, not at the
  end.

So this is a **stdout-capture defect in the runner**, not a CLI that omitted its result
event. The coordinator's correlation fits exactly: every zero-cost review was launched by
a coordinator session as a backgrounded Bash command whose stdout was piped to `tail`,
while foreground delegate-launched reviews priced normally. `run_plan` writes the stream
from a `tee` in the *middle* of `claude … | tee "$stream_file" | tee "$log_fifo" |
display_stream`, whose last stage inherits the caller's stdout; when that consumer closes
early the last stage takes `SIGPIPE`, the `tee`s die on their next write, the file stops
growing, and `claude` — which does not die with them — runs to completion with
`PIPESTATUS[0]` 0. A one-line probe reproduces the signature: a producer that ignores
`SIGPIPE` and exits 0, piped through `tee FILE | head -2`, leaves **38 of 50,000 lines**
in FILE. That is the observed shape at the smallest scale.

Evidenced, not reproduced end to end, and deliberately not chased further: it is
`self/BACKLOG.md`'s first entry, with both candidate fixes (decouple capture from display,
or make the `rc == 0` + `result_event: "missing"` combination loud and keep the stream).

## Re-capturing the closed features

For the coordinator. **This feature deliberately ran none of it**: every command below
writes to a consumer repo or to the agentTooling primary, both out of bounds here.

Order matters — nothing works until this feature's PR has merged into agentTooling `main`,
because the recovery step and the annotated cost line are what the re-capture is *for*.

1. **After this PR merges**, from the agentTooling primary checkout
   (`~/dev/agentTooling`, on `main`, clean), re-close its own affected feature — no
   subtree pull is involved for agentTooling itself:

       cd ~/dev/agentTooling && git pull --ff-only
       ./feature-close.sh --self stale-failed-sidecars --recapture

2. **Then propagate to each consumer repo**, which is what puts the fixed
   `agentTooling/` into it (`README.md` → "Updating"; the tree must be clean):

       cd ~/dev/musicMap        && ./agentTooling/update.sh
       cd ~/dev/vinylCatalogue  && ./agentTooling/update.sh

   Commit whatever `update.sh` brings across before step 3 — `feature-close.sh` refuses a
   dirty primary.

3. **Re-close each affected feature**, from that repo's primary checkout, on `main`,
   clean. No `--self`, and no worktree is needed (see below):

       cd ~/dev/musicMap && ./feature-close.sh pin-ruff --recapture

       cd ~/dev/vinylCatalogue
       ./feature-close.sh bulk-settle-atomic             --recapture
       ./feature-close.sh decision-ledger-identity       --recapture
       ./feature-close.sh decline-single-row-staged      --recapture
       ./feature-close.sh merge-section-constructors     --recapture
       ./feature-close.sh proposal-target-path-stability --recapture
       ./feature-close.sh reopen-and-clear-extraction    --recapture
       ./feature-close.sh track-position-sort-and-sides  --recapture

   Each run recovers the review's cost from its session transcript, rebuilds
   `planning.json`, rewrites `report.md`/`report.json` and commits
   `<slug>: cost records`. Read the printed cost line before quoting it: a bucket that
   still says `unpriced: … transcript not found` is a cost that is genuinely gone.

**Nine features, not the three the brief names.** `grep -l '"total_cost_usd": null'` over
vinylCatalogue's `review/complete/*.usage.json` returns seven with this exact shape, all
closed 2026-09-04 except `decision-ledger-identity` (2026-09-05), and every one committed
`| review | $0.0000 | 0.0% |`. With `pin-ruff` and `stale-failed-sidecars` that is nine.
**All nine session transcripts are still under `~/.claude/projects/`** as of 2026-09-06, so
every one of them is recoverable today — which is the argument for doing this promptly
rather than waiting for a sweep.

**Ruling 4, confirmed two ways.** By reading: the timing carry is guarded on
`[[ -f "$WT_TIMING" ]]` and the teardown on `[[ -d "$WORKTREE" ]]` (else `worktree prune`
and "already gone"), so no step needs the worktree; `manifest.py set-window-to` leaves an
already-stamped `to` alone and exits 0, so a re-close does not move the window. And by
test: `self/tests/recover-at-close.sh` C10–C12 re-close the feature its previous phase
just closed — worktree removed, local branch deleted — and assert exit 0, a second
`<slug>: cost records` commit, and an unmoved `to`.

**One thing it does need, exactly:** a branch ref. `feature-close.sh` resolves `<slug>` as
`refs/heads/<slug>` or `refs/remotes/origin/<slug>` and refuses "nothing to close" without
either — and a successful close deletes the local branch. All nine still have
`origin/<slug>` today, so the procedure works; on a forge with delete-on-merge it would
not, which is a backlog entry rather than a fix here (the merge commit is in `main` either
way, so the ancestry the refusal checks is knowable without the branch).

**If a re-capture refuses.** `--recapture` re-derives `planning.json` from transcripts, so
`check_frozen_cost` refuses when a previously *priced* session's transcript has aged out.
Two ways on: drop `--recapture` (a plain `feature-close.sh <slug>` skips the already-
captured feature quietly, still recovers, still re-reports and still commits — which is
all the review cost needs, since it comes from the `usage.json` sidecar and not from
`planning.json`), or pass `--force` and read the diff. Prefer the first: it changes only
what this fix is about.

## Gate

`./self/gate.sh` from the worktree, green:

    === gate: done — all checks passed ===
    # VERDICT
    all checks passed

49 checks, 0 failed, 0 skipped at the `recover-cost-at-close: build` commit; **51 after
merging `origin/main`**, which brought the sibling's `stale-failed-sidecars.sh` and its
`bash -n`. Both runs green. (shellcheck is not installed on this machine and the gate
skips it by design — it is not a dependency.) The checks are the `bash -n` parses, the
behavioural scripts under `self/tests/` — `recover at close self-test` among them, 23
assertions, ten consecutive green runs — `py_compile analysis`, the rate-table check and
the runner-prerequisites check.

The merge itself conflicted only where both features wrote the same two files, resolved
keep-both: `self/BACKLOG.md` (the sibling created one too — its four entries first, then
this feature's five, under main's header paragraph) and `self/README.md`'s `tests/` row
(one row naming both new scripts; main's `BACKLOG.md` row was already there, so the
duplicate this branch added was dropped). `analysis/report.py` auto-merged cleanly and
correctly: the sibling's `prior_total` term joined the same `if cost is None …` guard this
feature's `unpriced_plans` block sits inside, so a plan whose live sidecar has no cost but
whose *prior* attempt paid is no longer reported as unpriced — which is the right answer
and neither feature would have got it alone.

## Backlog

`self/BACKLOG.md`, created here (five entries, each with the assertion that would catch
it): the unknown cause of the missing result event with the evidence and the probe above;
`report.md`'s Cost **table** still printing a bare `$0.0000` in the bucket row while only
the total carries `(partial)`; the time roll-up having no equivalent of
`cost.unpriced_plans[]`, so a plan that ran eight minutes contributes `0.0` with nothing
beside it; `--recapture` needing a branch ref a delete-on-merge forge would have removed;
and `backfill_usage.py` skipping a resultless stream outright, so the case that most needs
a sidecar gets none at all.

## Rework — 2026-09-06

The review pass (PR #31) escalated four items, ranked; all four are closed here. The first
two are missing assertions for behaviour that already shipped — the defect class a review
exists to find, since each would let a real regression through a green gate. The last two
are changes with their own new assertions.

**1. `unpriced_reason`'s untested branches.** The function has three outcomes and only one
was asserted; collapsing it to a single `return` kept the whole gate green while making
the report claim a cause it does not know — and the untested `result_event`-absent branch
is the one the documented repair procedure actually runs, since **every sidecar on disk in
both corpora predates the field**. `self/tests/recover-at-close.sh` phase **D1–D4** now
pins each string by exact text, so no single return value satisfies them all. Three of the
four inputs are sidecars the runner really wrote, which needed two new phase-A shapes:
**A7** (non-zero rc with no result line → `outcome: "failed"`, `result_event: "missing"`,
filed to `auto/failed/`) and **A8** (a leftover stream beside a resumed plan, harvested by
`harvest_orphan_attempt` into a `killed` attempt). The fourth, D1, is the pre-field shape,
built by hand because no runner writes it any more.

**2. `rollback_recovery` untested.** `rollback_carry` is pinned by
`feature-lifecycle.sh`'s C5f; its twin had nothing. Phase **E1–E5** mirrors it: a close
whose capture refuses *after* recovery rewrote a sidecar exits non-zero saying `rolled back
the 1 recovered sidecar(s)`, the recovered figure is gone from the file again, the primary
is clean, and the re-run refuses for the same reason rather than for dirt this run made —
the two-close cascade the step-6 comment says the rollback exists to prevent.
`close_fixture` gained a fourth argument that withholds the planning transcript, which is
how the fixture reaches a refusing capture at all.

**3. The queue→bucket guard, taken.** `analysis/report.py` now raises at import when
`set(QUEUE_COST_BUCKETS) != QUEUE_DIRS`. Raised rather than `assert`ed, because `python3
-O` drops an assert and these scripts run on whatever interpreter a consuming repo has. It
cannot stop the summing chains and the dict disagreeing about which *bucket* a queue rolls
into — only reading the dict from the chains would, and the brief put the summing out of
scope — but it does stop the failure with no symptom: a queue added to `QUEUE_DIRS` and to
the chains but forgotten in the dict, whose dollars are counted while its unpriced plans
vanish from the printed line. **D5** asserts the sets match; **D6** asserts the guard is
real, by importing a copy of `report.py` with a fourth queue in `QUEUE_DIRS` and requiring
the failure to name both `QUEUE_COST_BUCKETS` and the added queue.

**4. `COST_USAGE_GLOB` narrowed.** `*/*.usage.json` asked only for *some* directory above
the file, so a `.usage.json` a human left anywhere under the feature directory was staged
into the cost commit and counted toward the `--force` teardown. Replaced by
`is_cost_usage_path`, which requires `<queue>/<state>/…` with `<queue>` from
`COST_USAGE_QUEUES` and `<state>` from `COST_USAGE_STATES` — the runner's own two sets
(`QUEUE` is assigned exactly one of the three in `run-plans.sh`, `run-verify.sh` and
`run-review.sh`; the four states are what `finalize_plan` routes between, per
`resolve_feature`'s comment), mirrored in `report.py` as `QUEUE_DIRS`/`STATE_DIRS`.

**The archived-batch layout does not need the glob kept wide.** The review could not
confirm it from the READMEs; the code and the corpora settle it. `find_queue_segment`
walks *up* from a sidecar to the nearest state directory and requires that directory's
parent to be a queue, so the queue segment is leftmost in the archived layout too — the
extra branch-named level sits *below* the state directory. `is_cost_usage_path` leaves
everything after the state directory unconstrained, so it matches. And empirically all 574
sidecars across the four corpora (`self/`, vinylCatalogue, musicMap, humanNetworkMap) are
`<queue>/<state>/<stem>.usage.json` exactly — none is deeper, and every leftmost segment is
`auto`, `verify` or `review`. Phase **F** pins the narrowing at the teardown, the other
caller of `stray_paths` and the only one a fixture can reach: an untracked file in the
primary trips step 1's dirty refusal long before step 9 runs, while the same file in the
worktree is exactly the question step 10 asks. A worktree holding
`notes/left-behind.usage.json` is kept with the warning (F1–F2); one holding
`review/complete/99-extra-sonnet.usage.json` is the harness's own and comes away (F3),
which is what stops F1 passing by the close simply never force-removing anything.

**One incidental fix.** Phase D's helper imported `report.py` from the sandbox primary
without `-B`, and the `analysis/__pycache__` it left made the primary dirty — so the very
next close refused on it. `-B` on both, which is the rule `feature-close.sh` already states
at the top of its own header.

`self/tests/recover-at-close.sh` goes from 23 assertions to **39**. `./self/gate.sh` green afterwards: 51 checks, 0 failed, 0 skipped.

## Open questions

- **The queue→bucket mapping is still two copies.** The rework took the cheap guard
  (`set(QUEUE_COST_BUCKETS) == QUEUE_DIRS`, raised at import), which catches a queue
  missing from the dict entirely. It does not catch the two copies disagreeing about
  which *bucket* a queue rolls into, because `compute_cost_rollup` and
  `compute_time_rollup` still sum by literal `if queue == "auto"` chains rather than
  reading the dict. Making them read it is the real fix and was out of scope twice over —
  the brief forbade touching the summing, and the sibling owns it.
- **The bucket cell versus the printed line.** Ruling 3 speaks about the line the close
  prints, and that is what changed. `report.md`'s Cost *table* — the file the close's
  closing sentence tells you to quote from — still shows `| review | $0.0000 | 0.0% |`
  with the explanation in a paragraph below it. Adding the reason to the paragraph was
  within "the output path"; changing the table's cell shape felt like a different
  decision, and it is in the backlog rather than made unilaterally.
- **`result_event` is top-level only.** The ruling specifies the sidecar's field, and it
  is written where `subtype` and `is_error` are: describing the latest attempt. A resumed
  plan whose *earlier* attempt lost its result event while the later one had one is
  therefore described by the later one; `unpriced_reason` falls back to the attempt's own
  `outcome`, which separates `killed` correctly but reports a resultless earlier attempt
  as `no result event` on inference rather than on record. Per-attempt would be exact;
  the sibling owns the neighbouring code and the brief asked for the minimum.
- **`recovery_note`'s "transcript not found".** Ruling 3 names the string, and the close
  runs recovery immediately before the report, so it is true there. Read out of an old
  `report.json` it means only "no recovered figure is on disk" — recovery may simply never
  have run. Documented in `analysis/README.md` rather than reworded.

## Deviations and near-misses worth recording

- **A bash 3.2 mis-parse of my own making.** The first draft of the recovery step built
  its rollback list with a `case` inside `$( … )`. bash 3.2 mis-parses the unbalanced `)`
  of a case pattern there — `syntax error near unexpected token 'newline'` on stderr while
  the assignment quietly succeeds, which is exactly the silent-failure shape
  `self/PROJECT_FACTS.md` warns about. Replaced with `cut -c4- | grep '\.usage\.json$'`.
- **A test that rode a real boundary.** C10 failed about one run in six. The cause was
  not the fix: `in_window`'s `to` bound is **exclusive** by design, and the fixture wrote
  its planning transcript with `now_z()` seconds before `feature-close.sh` stamped `to` —
  when both landed in the same second the re-capture correctly matched nothing. The
  fixture now pins the session with `feature-start.sh --session`, which claims it
  regardless of window; the window is `capture-guard.sh`'s subject, not this one's. Ten
  consecutive green runs afterwards.
