# self/tests

Behavioural checks for the harness, run by `../gate.sh`. Each is a plain bash script that
exits non-zero on a failed assertion and prints one `ok`/`FAIL` line per check; none
calls a model or the network. `../PROJECT_FACTS.md` → Tests says there is no test
*runner* here — that is still true; these are scripts the gate `record`s directly.

**No test reads or writes the real `~/.claude`.** The seam is `$HOME`: every script here
that touches a transcript or the claims ledger exports `HOME` to its own `mktemp -d`
before calling a script under `analysis/`, and `Path.home()` — which resolves the
`~/.claude/projects/` glob, `routing.find_transcript` and `claims_ledger_path()` alike —
follows it. That now includes every script that runs `feature-start.sh`
(`feature-lifecycle.sh`, `plan-numbering.sh`), because a start derives its routing record
from the running session's transcript.

**Every sandbox that copies `capture_planning.py`, `report.py` or `manifest.py` copies
`routing.py` too.** All three import it — the first for the router predicate, the second
for the Routing table, the third for `set-window-from`'s transcript lookup — and a
missing copy is an `ImportError` in every capture rather than one failed assertion. There is no
narrower override, deliberately: one that moved the ledger alone would let a test write
the ledger under `mktemp -d` while still reading the machine's own transcripts.

- `level-sentinel.sh` — copies the runner scripts into a `mktemp -d` checkout with a stub
  `claude` (exit code from `CLAUDE_STUB_RC`) and a stub `self/gate.sh` (verdict from
  `GATE_STUB_VERDICT`), then asserts the level-sentinel contract `run-batch.sh` depends
  on: a sentinel is filed with no sidecars and the gate runs labelled; a red gate with a
  queued level-verify exits `LEVEL_PAUSE_RC` (64); a green gate files the level-verify as
  skipped and continues (D3); `run-verify.sh --up-to 08` drains `08` and not `09`; a
  `claude` exiting 64 is a failure, not a pause; `run-batch.sh` resolves the pausing
  sentinel's number and finishes; and the `LEVEL_PAUSE_NN_OUT` handshake — `run-plans.sh`
  writes the pausing sentinel's `NN` to that file, `run-batch.sh` reads it in preference
  to re-deriving the number from a sort over `auto/complete/` (asserted with that
  directory empty, so the sort has nothing to offer), and a pause that reports no number
  at all stops the batch with a message instead of running `run-verify.sh --up-to ""`.
  Its last phase replaces `run-plans.sh` and `run-verify.sh` in the throwaway checkout
  with stubs, since what is under test there is the batch's own resolution rather than
  the runners' behaviour; it is last for that reason. Depends on `plan-runner-roots.sh`
  defining `LEVEL_PAUSE_RC` and on the stub gate honouring the label contract
  (`gate-report.<label>.txt`) the real template implements.
- `tiered-gates.sh` — same scaffolding, with the stub gate's verdict read from a file the
  stub `claude` can flip green (`CLAUDE_STUB_FIX_AT=tier1|tier2`, recognised from the
  prompt's preamble) and every `claude` call's flags logged. Asserts the tier ladder
  `run-batch.sh` → `settle_level` implements: tier 1 green → no escalation, build resumes;
  tier 1 red → `NN-escalation-opus` synthesized, run on opus under `ESCALATION_BUDGET_USD`
  with the escalation preamble; red after both → exit 1, next level not built, and a
  re-run neither re-escalates nor rebuilds; a resumed batch settles a crossed level before
  its build pass, **including when `auto/incomplete/` is empty** — the ladder is owed to
  the level, not to the queue behind it, and without it a batch killed during its last
  level's level-verify reports that level's failure only at the final gate, with no tier
  in between — and a settled level is not re-settled on a re-run; `run-review.sh` stamps
  the round's `verdict` (read from the report's first line) when the cap fires *after* the
  report was written and nothing at all when it fires before, and opens no PR either way,
  that being `feature-close.sh`'s; a sentinel's `expected-red:`/`defer:` lines reach
  the gate at that level only and make it green without a tier. It also copies
  `check-plans.sh` into the sandbox, so the corpus lint really runs at the head of every
  `run-batch.sh` call here rather than being skipped by that script's `-x` guard: two
  assertions pin `check-plans: 14 checks, 0 failed` in the batch output, one on the first
  build and one on the re-run that has a synthesized `NN-escalation-opus` on disk — the
  resume the lint used to block. That is why this test's fixture manifest is a real
  fenced JSON manifest declaring the stems each phase writes, with a non-empty `branches`
  and a body naming the slug in every queued plan. Depends on `run-escalation-plan.sh`,
  `run-verify.sh`'s `budget_for_plan` hook and `level_expectations` in
  `plan-runner-roots.sh`.
- `feature-lifecycle.sh` — stands up a throwaway agentTooling checkout that is a real git
  repo with a bare `origin` beside it, copies in the real `feature-start.sh`,
  `feature-capture.sh`, `feature-close.sh`, all four runners (`run-plans.sh`,
  `run-verify.sh`, `run-review.sh`, `run-batch.sh`), `stamp-timing.sh`,
  `plan-runner-{lib,roots}.sh`, `self/pr.sh`, `templates/plans/pr.sh` (outside the repo,
  as a consumer's copy) and `analysis/*.py` including `recover_attempts.py`, adds a stub
  gate, a stub setup hook and stub `claude`/`gh` on `PATH`, and drives the whole loop
  with `--self` — start a feature, refuse its stub brief, capture its cost on the branch,
  review it (which records the round's verdict and stops), close it (PR, stamp, capture,
  merge request), merge it, watch the next start prune
  it — synthesizing under a redirected `$HOME` the transcripts the captures read. The stub
  `claude` writes the review report for the runner to read back
  (`CLAUDE_REPORT_OUT`, and `CLAUDE_REPORT_FIRST_LINE` for the verdict under test), and
  the stub `gh` remembers per branch that a PR was created — so a second close finds it
  already open the way a forge would — and records the ORIGIN branch's head at the moment
  of a `pr merge` (`GH_MERGE_HEAD_OUT`), which is how the close's ordering is asserted
  rather than assumed. Every
  capture is run from `$TMP`, outside every checkout, so nothing cwd-relative inside the
  script could reach the repo running the test. The rule under test
  (`../../LIFECYCLE.md`): for slug `S` and primary checkout `R`, branch `S`, worktree
  `R/.worktrees/S` inside the primary, every session a feature costs is either launched in
  that worktree or pinned by id, and the cost record is written on `S` before the merge. Its `project_dir` helper mangles `.` as well as `/`, as Claude Code does,
  which is what files a nested worktree's transcripts under `…-R--worktrees-S`. Asserts
  that `feature-start.sh` creates the branch and worktree off `origin/main` at
  `R/.worktrees/S` (nothing at the legacy `R-S`), leaving the primary on `main` and
  clean — `git status --porcelain` empty with the worktree nested in it, because the
  common git dir's `info/exclude` now carries `/.worktrees/` exactly once, still exactly
  once after seven more starts, every entry it already held (an unterminated last line
  included) intact, and nothing tracked touched — writes the manifest (`branches [S]`, `base main`, a `Z`
  `from`, `to` null, and **no pin**: the session that runs a start is a router, never a
  claimant) and a
  `@@TODO@@` review stub numbered `01`, whatever another feature's corpus holds
  (`plan-numbering.sh` is the rule's own test), commits `S: start` with
  the routing record for that router inside the feature directory
  (`self/features/S/routing.json`, naming S in `features_started` and the router as its
  `session_id`, with nothing written beside the corpus at `self/routing/`),
  names the worktree in its "Next" block without teaching
  a chained `cd`, and
  refuses a bad slug, an existing branch, a worktree path already taken and a worktree's
  copy while creating nothing; that `--pin` restores the pin and writes **no** routing
  record, in the tree or in the `S: start` commit (S3a3–S3a4: a pinned session is never
  also a router), `--no-pin` is an accepted
  no-op and `--session` names the router with or without it; that a start **prunes** every
  worktree under `.worktrees/` whose branch is an ancestor of `origin/main` and whose tree
  is clean, deleting that branch with `git branch -D`, while a dirty merged one and an
  unmerged one survive and the bare remote's refs are untouched — including the case a
  second clone builds, where the merge happened on `origin/main` and this checkout's own
  `main` lags, which is where `git branch -d` refuses and leaves a removed worktree
  whose branch the output claimed was gone. There the first start only fast-forwards
  `main`, starts and prunes nothing, and exits 3 with the rerun command; the rerun
  prunes. A diverged `main`, a primary behind while off `main`, and a fast-forward git
  itself refuses (an untracked file in its way) are refused with nothing moved or started
  (S4h–S4n). It also asserts that `--open` runs the repo's
  `open-session.sh` with the worktree path as its only argument (a recording stub — the
  seeded script talks to Terminal.app, and `open-session.sh` in this directory is what
  runs its body) and that both copies of that script pass the path through **both**
  escaping layers before it reaches the string they hand to Terminal.app — `S5d` the shell
  quoting, `S5e` the AppleScript escaping, `S5f` that the bare single-quoted `$WORKTREE`
  of template-version 2 is gone; and that a
  `--self` start from an agentTooling **vendored** one directory inside the primary
  commits the feature directory with `agentTooling/self/features/<slug>/routing.json`
  inside it, and names that prefixed path in its output — a
  second, smaller scaffold built from `$AT`'s first commit with `git archive`, since the
  main one is a standalone checkout by construction. Most features it later **merges** are
  started with no session id (`start_unrouted`), which is simply the cheaper fixture; the
  routed case, two features one router starts from one `main`, is **MR** below. The first **S1** step
  also asserts the printed "Next" names `feature-close.sh --self S` as what opens the PR
  and still ends at the merge — the two steps after a clean verdict, in the start's own
  last lines.
  **T1**: `run-review.sh` files a brief still carrying `@@TODO@@` to `failed/` without
  calling `claude` or the PR hook. **C1** (`capture-on-branch`, design §3.2): after a
  commit of work, `feature-capture.sh` run from the worktree commits `S: cost records`
  over it and pushes the BRANCH — the bare remote's `S` carries `planning.json`,
  `report.*`, `timing.jsonl` and the manifest with `to` exactly one second past the
  session's instant, the remote's `main` ref is unchanged, the worktree is clean and
  present, the worktree session is claimed by branch with its `cwd`; a delegate of a
  coordinator on `main` whose brief names `S` and that no route claims is a **warning**
  line naming its id and the `"subagents"` pin, and a sibling briefed for `S-two` is never
  **warned** about (it is named once, in the residue, which is the corpus's listing and not
  this feature's); the router's routing record, refreshed from the router transcript
  planted for it, gains a cost and rides the commit. **C3**, the residue the retired weekly
  sweep used to print (design §3.5): the capture's output carries a `=== residue ===`
  section, after `what planning.json claims` and before `=== commit ===`, holding the rate
  table's verified date, the `main` session no feature claims and the unclaimed delegates —
  and NOT the router that started `S`, whose spend is routing overhead rather than an
  unclaimed remainder — while the capture still exits 0. **C2**: a later line in the session and a second
  capture move `to` LATER, rewrite `planning.json` in a second cost commit, and meet no
  refusal or already-captured skip. **N1**: a feature no routing record names captures
  with no word about routing. **V1**, a clean round
  (`../DESIGN-2026-09-17-close-and-review-rounds.md` §3 and §9): with a review edit in the
  tree, the pass commits `S: review round 1` carrying that edit, stamps a `plan_end` with
  `verdict=clean`, `head=` the sha of that very commit and `round=1`, writes exactly one
  `plan_end` and one `pass_end` (the held stamp is flushed once, and the EXIT trap adds
  none), opens no PR, pushes nothing, adds no cost commit, leaves `timing.jsonl` as the
  ONLY dirty path, and names `feature-close.sh --self S` as the next step.
  **T3**: a brief that merely mentions the marker mid-line runs; its feature has
  no session, so the CLOSE's capture refuses — the close exits non-zero with the
  `feature-capture.sh --self <slug>` re-run command, the PR is open all the same, no merge
  is ever requested (the record is not pushed, which is the whole reason for the order),
  and `to` is rolled back to null.
  **T4**, where the forge is unreachable: with the stub `gh` failing `auth status`
  (`GH_AUTH_RC=1`), the review pass makes no forge call at all and commits its own round,
  then the close's `pr.sh` takes its `skip` path and opens nothing while the capture still
  commits `<slug>: cost records` over the round's commit, leaving a clean worktree with no
  "capture exited" line — the shape that used to fail every clean review in a repo with no
  forge login. **T5**: the review runner invoked from the primary on `main` commits
  nothing, says it is on the feature's base and left the output uncommitted, leaves the
  primary's work in progress where it was, and touches no forge and no capture.
  **P1**: `pr.sh` honours `FEATURE_BASE`, refuses on the base branch, and both copies carry
  identical logic below their REPO-SPECIFIC line and never `checkout -b`. **P2**,
  `PR_AUTO_MERGE` behind the second entry point: the OPEN path makes no `pr merge` call
  even with it set, `--merge-request` with it set makes exactly one `pr merge … --auto`
  asking for `--merge` and never `--squash` (the prune and the post-merge capture both
  decide "merged" by ancestry, which a squash merge never gives) and opens no PR of its
  own, `--merge-request` with it unset exits 0 saying nothing was requested, `self/pr.sh`
  makes no call even with it set, and both copies read `template-version 4`.
  **X1**, the close's refusals, each asserted to come before any `pr create`: from the
  primary (not on the feature's branch), on a feature no review has finished (naming
  `run-review.sh`), and after a commit whose subject is not the harness's own follows the
  judged head (naming its short sha). **X4** is the fourth, and the one that used to be the
  capture's alone: an untracked `NOTES.md.tmp` inside the feature directory is not a cost
  record, so the close names that path, the forge stub's log is empty (not merely free of
  `pr create` — nothing was called at all), the refusal says nothing was written and no PR
  was opened, and the same close exits 0 once the file is gone, which is what keeps the
  assertion from passing for some other reason.
  **V2**, an escalated round: the pass still exits 0, `plan_end` carries
  `verdict=escalated` and `round=1`, the report is copied byte for byte to
  `escalations/<stem>.md` and rides the `review round 1` commit, no PR and no capture run
  and the branch is never pushed, the output names the brief and the next round's steps
  (`set-plans` included), and the close refuses naming that file. **V3**: a report whose
  first line carries no verdict stamps `verdict=unreadable`, says so, writes the brief and
  is refused by the close exactly like an escalated one — fail closed.
  **RD**, rounds across a rework: round 1 escalates, a by-hand
  `stamp-timing.sh … checkpoint` during the rework reads `round=2` (computed fresh, with
  nobody passing it), a second brief at a cheaper model (`NN+1-review-sonnet.md`) comes
  back clean with `round=2` on its stamps and a `review round 2` commit, and the close then
  succeeds — opening the PR, committing the records, stamping `pr_opened` with `round=2`,
  the round that closed, and requesting no merge because `self/pr.sh` keeps auto-merge off
  whatever the environment says. **X2**, the close's order and the race it closes: with the
  template `pr.sh` committed on the branch and `PR_AUTO_MERGE=1`, `pr create` precedes
  `pr merge`, the cost records are committed and pushed, `pr_opened` carries the PR url and
  rides that commit, **the origin head recorded at the `pr merge` call is already the cost
  commit**, there is exactly one merge request, and the last lines name the PR and the
  merge. **X3**: a second close run exits 0, finds the PR already open and opens no second
  one, and ends with one record, the cost commit on top and a clean worktree.
  **X5** is the consuming repo that never hand-merged the version-4 edits: a fixture
  `pr.sh` built from the real template with its `# template-version:` line rewritten to 3,
  committed on the branch, drives the close's skip branch — it names 3 and the 4 it needs,
  the forge log holds exactly one `pr create` and no `pr merge`, the cost records are
  committed all the same, and the close exits 0.
  **RC** is where the close's round comes from: a round-2 review whose budget cap fired
  after it wrote a clean report (the stub's `CLAUDE_STUB_BUDGET_CAP`, with the previous
  round's report removed first so `report_fingerprint` sees this round's as new) is filed
  to `review/failed/`, so `review/complete/` still holds one plan while the `plan_end`
  carries `verdict=clean`, `round=2` and the head it judged — and the close's banner and
  its `pr_opened` stamp both say 2, where the completed count would have said 1. **RF** is
  the fallback beside it: with `round` stripped from every `plan_end`, the same close says
  1, which is that count.
  **B1/B2**, `run-batch.sh` ending a round: over empty build and verify queues (a clean
  no-op) a clean review makes it call the close — `pr create` seen, the record written and
  committed — and say so, while an escalated one exits 1 with no PR, no record, and the
  rework brief's path printed. **M1**: merging `S` into the remote's `main` and starting another feature
  prunes `S`'s worktree and local branch and pushes nothing. **MR** is the merge the
  routing record used to break (`../DESIGN-2026-09-18-ledger-and-routing.md` §1): one
  router session starts two features off the same `main`, the second **before** the first
  merges — so the two records differ in `features_started` and `captured_at`, which is
  what made them a conflict — and both merge in turn with no conflict and no unmerged
  path, `main` carries a `routing.json` inside each feature directory, and
  `report.py --all`'s Routing table holds exactly one row for that router naming both
  slugs. Started after the first merges it would assert nothing: `main` would already
  carry the file. RED before the record moved, with the second merge exiting 1. **R1**: `--recapture` from
  the primary after the merge, with a later instant in the evidence, refuses to widen
  (manifest `to` unchanged, "never widened"), commits nothing and leaves the remote's refs
  byte-identical; with a hand-written later bound it tightens onto the evidence
  (`old -> new`), writes locally, commits nothing, pushes nothing, and says to open a PR.
  **L1**: a feature in the legacy sibling layout `R-S` (moved there by
  `git worktree move`), merged and never captured, captures from the primary — its
  session claimed by branch with its `cwd`, `to` stamped, nothing committed or pushed.
  **C4**: with the sandbox's own `analysis/pricing.py` rewritten to an ancient
  `RATES_VERIFIED` (restored immediately after), a capture warns in its residue that the
  rate table is stale and still exits 0 — every figure depends on that table, and a table
  nobody re-checked is not a reason to leave a feature uncaptured.
  Its **W** phases are where `session_window.to` comes from
  (`self/features/claim-window-precision/README.md`, item 1). The fixture moves the
  feature's `from` back to a fixed instant with `set_bound` — a local helper that rewrites
  one bound inside the manifest's last fence, by hand because two of the shapes it needs
  are exactly what `manifest.py` refuses to write — and plants a branch session running
  `12:00:00.700` to `12:45` at a fixed date hours earlier plus, under it, a delegate that
  ran on to `13:00:00.700`. That fixture is what lets **W1** assert one exact `to`
  (`13:00:01Z`) carrying three separate facts: it is the DELEGATE's last instant +1s, not
  the parent's, so the subagent walk in `last_branch_instant` cannot be deleted silently;
  it is at second resolution though the evidence carried milliseconds, so the
  `replace(microsecond=0)` truncation cannot be dropped silently (an untruncated
  `13:00:01.700000Z` parses everywhere and would fail nothing else); and it carries a date
  a bound stamped at capture time could never equal. W1 also asserts that both the session
  and the delegate are still captured under the now-exclusive bound. **W7**: on the branch
  a hand-written `to` LATER than the evidence is moved EARLIER onto it — before the merge
  the bound moves either way (C2 is the other way). **W2** gives a feature nothing but a
  pinned session off the branch and in another checkout: no branch-selected session, so
  the capture falls back to its own clock and prints the `no branch session` line.
  **W5**: a capture over a fence with no `to` key at all (so `set-window-to` fails for a
  reason that is not a refused widen) must refuse, name what `set-window-to` printed
  rather than a widen it never attempted, write no `planning.json` and commit nothing,
  leaving the worktree clean. Its feature is given a real branch session on purpose —
  without one the capture would refuse anyway and the assertion would pass whatever the
  stamp did. After the window feature merges: **W3** moves its bound later by hand and
  pins that `--recapture` from the primary tightens it back onto the evidence, printing
  `old -> new`. **W4** is the refusals, and their exit codes: `set-window-to --tighten`
  with a LATER instant must leave the fence byte-identical, name both bounds, and exit
  **3**, the widen refusal's own code — the exit code matters because the capture
  continues past that one and only that one, and asserting merely "non-zero" would pass
  vacuously under an unimplemented `--tighten`, where argparse exits 2; the bound it
  already carries is asserted to be a no-op rather than a refusal; and a bound at or
  before the fence's `from` — an empty window, which every other feature's split would
  then drop — is refused as a plain exit 1, naming both, with the primary left clean by
  all four. **W6** is the reason the exit code is asserted at all: the tolerated code is
  written down twice, `WIDEN_REFUSED_EXIT` in `manifest.py` and `WIDEN_REFUSED_RC` in
  `feature-capture.sh`, since bash cannot import it, so a drift between them would turn
  every declined widen into a refused capture. It moves the bound to `12:30` by hand —
  between the session's first line and its last, the one shape from which the evidence
  widens rather than tightens, which is why the W1 fixture carries that middle `12:45`
  line — and asserts the `--recapture` warns, captures anyway and leaves the published
  bound where it found it. **A1**, the frozen-record annotation at capture (design §3.5):
  two features pin the same session, the first is captured and merged so the second's
  branch carries its frozen record, and capturing the second writes `also_claimed_by` onto
  that record — every other byte of it identical, asserted over the whole record with the
  key stripped — regenerates the first feature's `report.json`, names the record it
  annotated in its output, and commits both with its own cost records, leaving the
  worktree clean. **A2** is the other side of that admission, and the reason it is an
  argument rather than a rule: the same sibling's `report.md` dirtied by hand *before* the
  run — nothing the annotation touched — refuses the capture by name and leaves that one
  path as the only dirt, where it used to be neither refused nor committed and the branch
  was pushed dirty. No model, no network. A missing script fails its own
  assertions loudly rather than aborting the run, the convention `cost-recovery.sh` uses.
  Depends on `plan-runner-lib.sh` refusing the `@@TODO@@` marker and writing `pass_end`
  once (`stamp_pass_end`), on `run-review.sh` committing the pass under pr.sh's own subject
  and then running `feature-capture.sh` after `pr.sh` and the two stamps, and on its
  `capped_after_report` branch stamping a verdict from a report it can prove this pass
  wrote, on `feature-start.sh` writing the `info/exclude` entry, numbering the review stub
  `01` and printing the close and then the merge as its last steps, on `feature-close.sh`
  reading its round from that stamp and refusing on `stray_paths` with no sibling admitted,
  on `plan-runner-roots.sh` owning that reader and `stray_labels`, on `feature-capture.sh`
  choosing its mode from the checked-out
  branch and printing its `=== residue ===`, `=== annotate ===` and `=== commit ===`
  banners, on `capture_planning.py`'s `--list-subagents --unclaimed --for`,
  `--list-sessions --unclaimed` (router exclusion included), `--annotate-frozen`, its zero
  refusal and its `--last-branch-instant` (including the subagent walk and the whole-second
  truncation), on `routing.py --refresh-for`, on `pricing.RATES_VERIFIED` being a
  module-level assignment the fixture can rewrite, and on `analysis/manifest.py`'s `init`,
  `get`, `claimed` and `set-window-to [--tighten|--replace]`.
- `verdict-readers.sh` — the only test here that calls `plan-runner-roots.sh`'s round
  readers, and (since round 2) its stray-records reader, **directly**: it sources the file,
  points `FEATURES_DIR` at a `mktemp -d` corpus of its own for the round readers, and sets
  `REPO_DIR`/`FEATURES_LABEL` by hand for the stray phase — the globals
  `report_verdict`, `latest_review_plan`, `completed_review_count`, `next_round`,
  `stray_paths` and `stray_labels` read (a whole fake checkout for `resolve_roots` to find
  would buy nothing else). Everywhere else these run through a lifecycle, where the
  report's first line is always one of two exact strings, every stem is one width, and
  every caller of `stray_paths` calls `stray_labels` first, so four rules they implement
  are otherwise unasserted and a "simplification" could delete any of them silently.
  Asserts: `Verdict: clean` and `Verdict: escalated` read as
  themselves; a report whose FIRST LINE is prose reads `unreadable` though its body says
  `Verdict: clean` — the defect a `grep` would ship, since a real report says both words
  all through its prose; `  VERDICT:  CLEAN ` with a trailing `\r` reads `clean`, the case
  folded and the space trimmed *before* the prefix is matched; an unknown verdict word and
  a missing file read `unreadable`; with `98-review-opus.md` and `101-review-sonnet.md`
  both in `review/complete/`, `latest_review_plan` returns `101-review-sonnet` (lexically
  the 98 would win, which would hand the close the earlier round's verdict); a stem in
  `review/failed/` — a review capped after writing its report — is returned by
  `latest_review_plan` and is *not* counted by `completed_review_count`, with `next_round`
  the count plus one; an `08` stem neither wins nor aborts the reader on octal (`10#`); a
  `.progress.md` beside a plan is neither read nor counted; and an unknown slug is empty
  rather than an error. Its **stray reader** phase (round 2's escalation,
  `self/features/lifecycle-records-and-numbering/escalations/01-review-opus.md`) asserts
  that `stray_paths`, called with no prior `stray_labels` call so
  `FEATURE_REL`/`FEATURES_REL`/`STRAY_SLUG` are genuinely unset, returns
  non-zero and names `stray_labels` on stderr — RED against the pre-round-2 reader, which
  instead let `set -u` kill the command substitution's subshell with an "unbound variable"
  message naming no function at all; that after `stray_labels x <checkout>` derives the
  labels for a `--self`-shaped checkout, the identical input returns 0 and reports the
  path as stray (it is nobody's cost record); that a `planning.json` path under the
  same feature directory returns 0 and reports nothing; and (**S7/S8**) that this
  feature's own `routing.json` is a cost record like the rest while a sibling's copy of
  the same router's record is stray — the routing record is a `COST_FILES` entry inside
  the feature it links now, and `ROUTING_REL`, the fourth label, is gone with the
  directory it named. No model, no network, no git. RED
  until `report_verdict` folded and
  trimmed the line before matching it (`self/features/lifecycle-records-and-numbering/README.md`,
  slice A2), and, for the stray phase, until `stray_paths` checked its four globals before
  its loop instead of trusting `set -u` (round 2).
- `capture-from-worktree.sh` — a real git repo `R` with the analysis scripts committed in
  it and a real `git worktree add R/.worktrees/S` (plus a second worktree for another
  feature), so the worktree carries its own copy of `capture_planning.py`, and under a
  redirected `$HOME` four transcripts: one launched in the worktree on `S` with a
  delegate, one in `R` on `main` unpinned, one in `R` on `main` pinned in the manifest's
  `sessions`, and one launched in the other feature's worktree on `S`. Asserts
  (`self/DESIGN-2026-09-16-lifecycle-restructure.md` §3.2, §4) that `roots.session_root`
  from the worktree's copy is `R`, not the worktree; that a capture run from the worktree's
  copy exits 0 and writes `planning.json` into the worktree's corpus and none into `R`'s;
  that it claims the worktree session by branch with its `cwd` and its delegate with it,
  the pinned primary session as `pinned`, and neither the unpinned `main` session nor the
  other worktree's; that `--last-branch-instant` from the worktree's copy is the delegate's
  last instant + 1s; and that `--list-sessions` from it lists the sessions filed under `R`'s
  own project directory as well as the worktree's. F1 and F7 were RED until
  `session_root` followed a worktree's `.git` file to its primary (`worktree_primary`).
  Copies `routing.py` with `capture_planning.py`, per the rule above. No model, no network.
- `routing-record.sh` — `session-share.sh`'s scaffolding (copies of
  `analysis/{pricing,roots,transcript,capture_planning,report,routing}.py` in a throwaway
  agentTooling checkout with a bare `mkdir .git`, transcripts under a redirected `$HOME`)
  asserting the routing record (`self/DESIGN-2026-09-16-lifecycle-restructure.md` §3.4,
  `self/DESIGN-2026-09-18-ledger-and-routing.md` §1).
  A router transcript carrying two `feature-start.sh <slug>` Bash tool calls — built with
  `bash_tool_line` from `fixtures/transcripts/build-transcript.sh` — yields both slugs
  with the instants of their own calls, unioned with the slug being started now (whose
  `at` is null, its call not yet flushed), plus `launched_in`/`git_branch` from the
  transcript's `cwd`/`gitBranch`, its first and last instants, their span, and its cost
  through `pricing.compute_cost` — written to `self/features/<slug>/routing.json`, the
  directory of the feature being started, with nothing at the legacy `self/routing/`;
  `captured_at` equals `ended_at`, because it is the
  content's as-of instant rather than the wall clock, which is what makes a second write
  **byte-identical** and is what latest-wins ranks by. A session with no
  transcript still writes a record (current slug, null figures, a warning on stderr) and
  never refuses. Router detection is pinned from all three sides: `--list-sessions
  --unclaimed` drops the two routers and keeps a `main` session with no such call, a
  session on a feature branch that has one, one launched in a worktree, and one whose only
  mention of the script is `grep -n x feature-start.sh hooks` — naming the file is not
  running it, though `hooks` would pass the slug pattern — while a call at command position
  behind `&&` and `bash` still counts as a router, and a plain
  `--list-sessions` keeps them all. **R4i and R10 pin that the slug is on the start's own
  line** (`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §2). R10 calls
  `routing.slug_of_start_command` directly, because which LINE a slug came from is
  invisible from any record but by its absence: a start with no slug on its line yields
  `None` rather than the next line's first word, a `\`-continued start yields its slug, a
  `--base x` before the slug does not become one, and a non-start line is never read for a
  slug at all. R4i is the same rule from the outside — a `main` session in the primary
  whose only `feature-start.sh` call carries no slug started no feature, so it is **not** a
  router and stays in the unclaimed listing, where before it was a router that had opened a
  feature called `ls`. Its fixture passes `\n` as a JSON escape through `bash_tool_line`,
  so the command really is two lines. And `report.py --all` renders the Routing table with
  each started slug beside its frozen total and the routing fraction — **one row** for the
  router whose record three feature directories hold — while
  `report.py <slug>` prints `routed by` with the other slugs for a routed feature, read
  from that feature's own copy, and nothing extra for an unrouted one. **R6** is the
  capture's refresh, `routing.py
  --refresh-for <slug>`: after the router's transcript grows a later start, that slug's
  record is rewritten (the new slug present, `ended_at` moved) and its path
  printed, the slug the transcript never carried is kept with its null `at`, a second
  refresh is byte-identical, a slug with no record prints nothing, and a record whose
  transcript is gone is left byte-identical with a warning naming the session.
  **R7** is the point of the location: that refresh leaves the other two features' copies
  of the same router's record byte-identical, with a third assertion that the refreshed
  copy really did change so the first two cannot pass vacuously. **R8** is
  `load_records`, called directly because what it decides is invisible from any renderer
  but by its absence: one record per `session_id`, the copy with the latest `captured_at`,
  and on an equal `captured_at` the copy naming more features (a hand-written copy holding
  none is the loser). **R9** is `--migrate`: a legacy record naming two slugs lands in both
  feature directories and its file is deleted, one printed line per move; a target already
  holding a record captured as late or later is skipped rather than overwritten and its
  legacy file still goes; a slug with no feature directory is skipped and no directory is
  created for it; a record no slug of which has a directory is KEPT, since deleting it
  would destroy its only copy; an emptied legacy directory is removed; and a second run
  over a corpus with none exits 0, prints nothing and changes no byte under the features
  root (asserted with `diff -r` over a copy). **R11** is one owner per session
  (`../features/shell-write-rewrite/` part 2): a hand-written record for a third router,
  pinned in the `sessions` of a *different* feature's manifest, has no row in the Routing
  table, leaves the `routing overhead $X` figure exactly what it was before the record
  existed (so the fraction counts only the unpinned routers), is named in one `--all` line
  with the pinning slug, drops the pinned-out feature's "routed by" line while an unpinned
  router's stays, and is byte-identical afterwards; both features' `report.json` totals
  are their own, and `load_records` still returns the record — the skip is the readers'.
  Depends on `analysis/routing.py` and on
  `capture_planning.py` importing `is_router_lines` from it; RED until both landed, and
  R1/R6–R9 RED again until the record moved inside the feature.
  No model, no network.
- `worktree-claims.sh` — `capture-guard.sh`'s scaffolding (copies of
  `analysis/{pricing,roots,transcript,capture_planning}.py` in a throwaway checkout, a
  bare `mkdir .git`, transcripts under a redirected `$HOME`), asserting which launch
  directories feature `S` claims a session from now that worktrees are nested in the
  primary `R` (`self/features/in-repo-worktrees/README.md`). Its `mktemp -d` template is
  `wt.claims.XXXXXX` on purpose: the dots put a `.` in `R`'s own path, so every project
  dir is named with `/` and `.` both mangled to `-`, as Claude Code names them, and W0
  checks that premise and the `…-R--worktrees-S` name of the nested one. One manifest
  and six sessions on `S`'s branch, all in the window: launched in `R`, in
  `R/.worktrees/S` (with a delegate under it), in the legacy sibling `R-S`, and — later
  than those — in `R/.worktrees/<other>` and in the prefix-sharing `R/.worktrees/S-two`
  and `R-S-two`. Asserts that capture selects the first three by branch with their
  `cwd`s (W1) and none of the other three, although each sits under `R` or starts with
  one of `S`'s own worktree paths, naming the other worktree's directory in the warning
  (W2; W2d–e are the prefix cases, which a bare `startswith(root)` in
  `path_at_or_under` fails, verified by weakening it); that the delegate filed under the nested project dir
  is priced with its parent (W3); that `--last-branch-instant` is the delegate's last
  instant + 1s rather than the other worktree's later one (W4); and that
  `--list-sessions` and `--list-subagents` find what is filed under the nested and
  legacy project dirs (W5). W1c-d, W2 and W4 were RED until `capture_planning.py`
  fenced `R/.worktrees` (`claim_roots`, `cwd_claimable`); everything was RED until
  `transcript_dir_name` mangled `.`. Depends on `session_line`/`subagent_line`/
  `subagent_prompt_line` from `fixtures/transcripts/build-transcript.sh`. The legacy half
  of the rule is also `capture-guard.sh` phase 15. No model, no network.
- `check-plans.sh` — copies the real `check-plans.sh` and `plan-runner-roots.sh` into a
  throwaway checkout (a missing `check-plans.sh` is tolerated — RED until it lands, the
  `cost-recovery.sh` convention) and drives it against synthesized feature manifests and
  plan-directory trees under `$TMP/plans/features` (the ordinary corpus) and
  `$TMP/agentTooling/self/features` (the `--self` one). Asserts the usage contract (exit
  2 on no slug, an unknown flag, or an extra argument); that a well-formed feature prints
  exactly 14 `  ok    ` lines, no `  FAIL  ` line, and ends `check-plans: 14 checks, 0
  failed`; and, one at a time, each of the fourteen ordered checks — feature directory
  exists, manifest present, fence parses, fence slug matches directory, method known,
  branches non-empty, `window bounds carry a zone and to follows from` (a naive bound
  FAILs; an offset one passes; a `to` at or before `from` FAILs naming both bounds, since
  an empty window owns nothing; a null `to` is in flight and passes; and two bounds in
  different zones are compared as instants, which a string comparison gets backwards),
  plan filenames well-formed, plan
  numbers padded alike, no `@@TODO@@` stubs queued, every plan file listed in `plans[]`,
  every `plans[]` entry has a file, every queued plan names the feature, plans method has
  a queue — FAILing on the input built to trip it, naming the offending path or stem in
  the detail where the contract specifies one, and passing otherwise; a missing feature
  directory still ends with a `check-plans: ` summary line. Pins both halves of the
  escalation exemption (`11b`/`11c`): a `verify/complete/NN-escalation-MODEL.md` absent
  from `plans[]` still prints `ok    every plan file listed in plans[]` — it is
  synthesized at runtime and no manifest can list it — while the same filename under
  `auto/` FAILs check 8, the way an `NN-gate.md` outside `auto/` does (`8b`). Also
  asserts the batch stop:
  `run-batch.sh` spends no `claude` call on a feature whose corpus fails check 8
  (malformed filenames) and does spend one on a well-formed feature — copying in
  `run-batch.sh`, the other runners and a stub `claude` (logging its args to
  `$TMP/claude.log`) for that last phase only. No model, no network. Depends on
  `plan-runner-roots.sh`'s `resolve_roots` and `manifest_field`, and — for check 10 — on
  `plan-runner-lib.sh`'s refusal rule (`grep -q '^@@TODO@@'`, any line) matching the
  lint's, since the lint exists to predict that refusal: the `10c` fixture is the stub
  `feature-start.sh` really writes, marker on line 3 under a title.
- `cost-recovery.sh` — copies `analysis/pricing.py`, `analysis/roots.py`,
  `analysis/report.py`, `analysis/transcript.py` and `analysis/recover_attempts.py` into a
  throwaway checkout, synthesizes a `self/features/` corpus of `usage.json` sidecars (and,
  for the report.py-level assertions, minimal feature dirs with a manifest `README.md` and
  `planning.json`) and, under a redirected `$HOME`, the
  `~/.claude/projects/*/<session_id>.jsonl` transcripts they point at, and asserts the
  killed-attempt-cost-recovery contract: `pricing.py`'s intro tier is a two-sided window (a
  date before it starts, or after it expires, prices standard; a date inside it prices intro
  at exactly 2/3 of standard); `recover_attempts.py` fills a killed attempt's
  `recovered_cost_usd` / `recovered_tokens` / `recovered_from` / `recovered_at` /
  `rates_applied` from its transcript without touching `total_cost_usd`; a usage.json's
  top-level `recovered_cost_usd` sums its recovered attempts; the 5m/1h cache-creation
  split prices in the `CACHE_WRITE_1H_MULTIPLIER` / `CACHE_WRITE_5M_MULTIPLIER` ratio (the
  guard against reading `usage.json`'s flat, unsplit `cache_creation_input_tokens` instead);
  an already-measured attempt and a second run are both no-ops; a missing transcript is
  reported unrecoverable rather than erroring; per-`message.id` dedup bills one API response
  once; a killed attempt on a model absent from `pricing.RATES` is marked
  `recovered_is_partial` with `unpriced_models` naming it (propagating the models it could
  price rather than refusing the whole attempt), and `report.py` classes such a plan's total
  as partial rather than recovered-and-whole; attempt-level recovery survives
  `write_usage_sidecar` erasing the sidecar's top-level `recovered_cost_usd` (`report.py`
  sums `attempts[]` instead, using the top-level field only as a cross-check that warns
  naming both figures on disagreement); and a level-verify the runner filed as **skipped**
  — `verify/complete/NN-level-*.md` with a `.progress.md` opening `skipped:` and no
  `.usage.json`, by design (`AGENT_PLANS.md` → Levels, D3) — is neither listed under
  `missing_usage_plans` nor allowed to mark the feature's total a lower bound, while a
  plan with no sidecar and no `skipped:` line still is; and `backfill_usage.py` over a
  `.stream.jsonl` holding an `init` event and assistant events but **no** `result` event
  writes the sidecar `write_usage_sidecar` would — `result_event: "missing"`, the
  session id from the first event, null figures, one null attempt — rather than skipping
  the file and leaving the plan in `missing_usage_plans`, which reads as "never ran".
  That last phase runs after the idempotency snapshot, so the sidecar it writes cannot
  disturb it. Builds its fixtures with the shell helpers in
  `fixtures/`. No model, no network. Depends on `analysis/pricing.py`'s
  `get_rates`/`compute_cost`, `analysis/report.py`'s `compute_cost_rollup` and
  `analysis/transcript.py` and `analysis/recover_attempts.py` — a missing copy of the
  latter two is tolerated rather than fatal (the script was authored RED against
  `pricing.py` alone), so every recovery assertion fails loudly instead of the run
  aborting; the `report.py`-level assertions (13-14) were likewise authored RED against
  `self/features/recovered-totals-stay-honest`'s plan 02, which has since landed.
  `record`ed by `../gate.sh` alongside the other two.
- `recover-at-close.sh` — three throwaway checkouts under one `mktemp -d`, a stub `claude`
  whose closing `result` event is suppressed by `CLAUDE_STUB_NO_RESULT`, a stub `gh`, and
  synthesized transcripts under a redirected `$HOME`. Asserts the contract that a review
  which ran to completion is never recorded at `$0` unexplained
  (`self/features/recover-cost-at-close/README.md`): `write_usage_sidecar` writes
  `result_event: "missing"` when the stream held no `result` event and `"seen"` when it
  did — driven through the real `run-plans.sh`, since what is under test is the field a
  real stream produces — while `outcome` still says `complete` (it is the exit code's
  fact, not pricing's), `total_cost_usd` stays null, the plan is still filed to
  `auto/complete/`, and the sidecar still carries the session id from the stream's first
  event; `recover_attempts.py --for <slug>` recovers a **`complete`**-outcome null-cost
  attempt (recovery was never gated on `outcome`, and this is the case its docstring used
  to omit) while leaving every other feature's sidecar byte-identical, refuses an unknown
  slug without writing, and leaves the flagless whole-tree walk — the corpus-wide repair
  run (`../../analysis/README.md` → "Repair tools") — unchanged; and `feature-capture.sh`, run from the feature's worktree on its branch,
  recovers before it captures — with the transcript present the review bucket carries
  real dollars and the rewritten `usage.json` is inside the branch's `<slug>: cost
  records` commit rather than named as a stray (which would refuse the capture), and with
  the transcript gone the capture still exits 0, names the plan as unrecoverable, and
  prints `review $0.0000 (0.0%, unpriced: <stem> — no result event, transcript not
  found)` instead of the bare `review $0.0000 (0.0%)` the defect printed. Each fixture
  starts with `--pin --session planning-<slug>` so its one planning session is claimed by
  id, whatever second the stamp lands in.
  The C phase then runs the repair path for the features whose zero is already committed:
  the feature is merged, its worktree removed and local branch deleted as the prune would,
  and `--recapture` from the primary re-captures, writing locally, committing nothing and
  leaving `session_window.to` where the branch capture put it. It runs on to the state a
  forge with delete-on-merge really leaves — the remote branch deleted from the bare
  origin AND its remote-tracking ref removed — and pins that a plain capture and
  `--recapture` both then proceed on the manifest being tracked on `main` and the
  `<slug>: start` commit being in `main`'s history, committing nothing, while
  `--recapture` for a feature that was never started refuses "nothing to capture".
  Three later phases came out of the review: **D** pins each of `report.py`'s three
  `unpriced_reason` strings by exact text, from a sidecar of that shape — no
  `result_event` at all (which every sidecar on disk still has, so it is the branch the
  documented repair runs), `missing`, and a `killed` attempt the runner harvested — so no
  single return value satisfies them all, and pins `set(QUEUE_COST_BUCKETS) ==
  QUEUE_DIRS` by asserting a drifted copy of `report.py` refuses to import. **E** pins
  the recovery rollback: a capture that refuses *after* recovery rewrote a sidecar leaves
  the worktree clean and the sidecar as it was (restored from the capture's snapshot), and
  the re-run refuses for the same reason rather than for stray dirt this run made. **F**
  pins the narrowed sidecar match at the capture's up-front stray check: a worktree holding
  an untracked `notes/left-behind.usage.json` makes the capture refuse, naming it and
  writing nothing, while one holding `review/complete/99-extra-sonnet.usage.json` is the
  harness's own and rides the cost commit.
  The B4, C9 and D6 assertions carry their own anti-vacuity guards, since argparse reads
  `--for` as an abbreviation of `--force`, the bare-zero line is a *substring* of the
  annotated one, and a guard that is merely true today is not a guard. Builds its sidecars
  with `write_unpriced_usage_json` from `fixtures/` and its transcripts with
  `transcript_line`/`session_line`. No model, no network. Depends on
  `plan-runner-lib.sh`'s `write_usage_sidecar`, `analysis/recover_attempts.py`'s `--for`,
  `analysis/report.py`'s `cost.unpriced_plans[]`, `unpriced_reason` and its
  `QUEUE_COST_BUCKETS` import guard, and `feature-capture.sh`'s recovery step, snapshot
  rollback, post-merge ancestry check and `is_cost_usage_path`; RED until each landed (C,
  E and F again, when they moved from `feature-close.sh` to `feature-capture.sh`).
- `recover-duration.sh` — `recover-at-close.sh`'s phase-B scaffolding on its own:
  `analysis/{pricing,roots,transcript,recover_attempts}.py` in a throwaway checkout, a
  synthesized `self/features/` corpus of `usage.json` sidecars, and
  `~/.claude/projects/*/<session_id>.jsonl` transcripts under a redirected `$HOME`.
  Asserts the lower bound `recover_attempts.py` derives beside the dollars
  (`self/features/recovered-duration-lower-bound/README.md`, item 1): an unpriced attempt
  whose transcript survives gains `recovered_duration_s`, the seconds between the
  transcript's **first and last timestamped lines** — the fixture's last line is a `user`
  line later than any assistant response, so a span taken over
  `iter_billable_messages`'s yields instead of over the transcript fails the assertion —
  while `total_cost_usd` and `duration_ms` both stay null; the sidecar's top-level
  `recovered_duration_s` is the sum over its recovered attempts, as the top-level
  `recovered_cost_usd` beside it already was; a transcript with fewer than two
  timestamped lines writes no duration at all rather than `0.0`, and no top-level key
  either; an attempt whose transcript is gone is left byte-identical and reported
  unrecoverable; an attempt carrying a recovered cost and no duration — every attempt
  recovered before this existed — is skipped by an ordinary run and backfilled by
  `--force`; and an attempt with a measured `duration_ms` is never visited. Depends on
  `recover_attempts.py`'s `recover_attempt` returning the span in its field dict and on
  its top-level merge writing the duration key only when some attempt carries one;
  RED until both landed.
- `capture-guard.sh` — copies `analysis/{pricing,roots,transcript,capture_planning}.py` into
  a throwaway checkout, synthesizes one feature manifest and, under a redirected `$HOME`,
  the `~/.claude/projects/*/<session_id>.jsonl` transcripts capture selects on, and asserts
  `capture_planning.py`'s frozen-cost guard: a re-capture whose priced session has lost its
  transcript is refused (non-zero exit, `planning.json` byte-identical, the session id and
  the preserved dollar figure both named), `--force` overrides it, and the three safe cases
  stay quiet — transcript still present, a session dropped by a `session_window` edit while
  its transcript survives, and a session now claimed by a `usage.json` as runner cost. Also
  covers that a zero-cost prior capture needs no `--force`. Resolves its `mktemp -d` through
  `pwd -P` because `roots.py` resolves `AGENT_TOOLING_DIR` with `Path.resolve()`: on macOS
  the unresolved `/var/...` fixture path matches no transcript, and every assertion would
  then pass or fail vacuously against an empty scan. Uses `session_line` from
  `fixtures/transcripts/build-transcript.sh`. No model, no network.
  Also pins the two failures found after the guard first shipped: a transcript moved
  into an **orphaned worktree's** project directory (name still contains the repo's
  fragment, so the scan walks it; `cwd` is the worktree, so `repo_match` fails forever)
  must be treated as lost and refused — the filename-glob version vouched for it and
  re-zeroed the feature with exit 0 — and a declared branch matching no transcript must
  be warned about, the failure that silently held five features at `$0.00`.
  Covers the **already-captured skip** in the same file, since it is the guard in front
  of that one: a second run over a feature with a `captured_at` exits 0 leaving
  `planning.json` byte-identical and naming `--recapture`, skips the same way when the
  transcripts are gone (quiet, not a refusal — the cadence crosses a corpus of expired
  features every week), yields to `--recapture` and to `--force`, and under `--all`
  captures only the feature that had none. It also pins that `--all --recapture`
  does not abort on a refusal: the feature after the refusing one is still captured and
  the run exits non-zero at the end. The helpers say which is which — `capture` is the
  raw invocation, `recapture` adds the flag, and every frozen-cost phase goes through
  `recapture` because those assertions are about what the scan does, not about whether
  it runs.
  Its last phase pins `check_empty_window`, the sibling of the unmatched-branch warning:
  a window with `from == to` — and its inverted twin, `from > to` — is warned about even
  though the branch matches and the transcripts are present, while an open-ended window
  and a real interval whose two bounds are written in different zone formats
  (`05:00:00-04:00` .. `13:00:00Z`) are not. That last pair is what pins the check to
  instants rather than strings, and it is the assertion that fails if someone
  "simplifies" it to a lexicographic compare. RED until `check_empty_window` landed.
  Its phase 17 pins the evidenced-zero case: a session excluded by the manifest's
  `exclude_sessions`, or claimed elsewhere by a `usage.json` as a runner session, proves
  the branch name is right when the scan meets it **on one of the manifest's branches**
  — capture writes the $0.00 without `--force` and says `evidenced` on stdout,
  `excluded_session_ids` names the id, and `sessions` stays empty — while a branch no
  transcript carries at all is still refused, asserted right beside it for contrast
  (`17c`). `17d` is what scopes the evidence to the branch rather than to the corpus: an
  excluded session that is present, reachable and runner-excluded but carries branch
  `other`, under a manifest declaring `typo`, must still refuse and write no
  `planning.json`. It is the shape of every repo that has ever run a batch, so were the
  serialized (repo-wide) `excluded_session_ids` the set behind the refusal instead of
  `excluded_on_branch`, a branch typo would read as an evidenced $0.00 everywhere. Phase 18: `--all` skips a feature whose `session_window.to` is still null as in flight and writes nothing, while naming the slug still captures it — a corpus-wide run must not freeze a feature `feature-capture.sh` has not captured.
- `subagent-capture.sh` — same scaffolding as `capture-guard.sh`, plus the
  `<session_id>/subagents/agent-<id>.jsonl` files beside the parent transcripts (built with
  `subagent_line` / `subagent_prompt_line` from `fixtures/transcripts/build-transcript.sh`).
  Asserts `capture_planning.py`'s subagent attribution: a selected parent's in-window
  subagent is priced and the total rises by exactly `cost_usd.subagents`, with
  `subagents[]` naming it as selected by `"parent"`; one starting after the window's `to`
  is not; a subagent under a parent on `main` — the coordinator case, where the child
  inherits the parent's `gitBranch` and can never be branch-matched — is unpriced until
  the manifest pins its id, then priced as `"pinned"` while the parent stays out of
  `sessions[]`; a pin matching nothing is warned about by id; the frozen-cost guard
  refuses a re-capture whose subagents directory is gone, naming `agent-<id>`, and
  `--force` still overrides; `--list-subagents` prints every reachable subagent with its
  opening prompt and parent, and `--since` drops earlier ones; a subagent of a runner
  session (parent claimed by a `usage.json`) is not priced even when pinned, and the pin
  is reported unmatched; two manifests pinning one id are warned about, naming the
  other feature; and `--unclaimed --for <repo>/<slug>` keeps exactly the delegates whose
  brief names that feature — a `<slug>-two` one is not among them, one whose
  `<repo>/<slug>` outruns the 26-character pin column is, the agent id prints untruncated
  for `feature-capture.sh` to read, and `--for` without `--unclaimed` or not shaped
  `<repo>/<slug>` is a usage error. RED until the subagent walk landed.
  Its phase **19** is `ledger-and-routing`'s zero-cost pin
  (`../DESIGN-2026-09-18-ledger-and-routing.md` §3): a pinned delegate whose transcript is
  a `subagent_prompt_line` and nothing else — no `assistant` line, so nothing billable —
  is still captured into `subagents[]` as `pinned` (`19a`, the half the design said to
  verify), earns no `priced[]` row (`19b`), and is written to the ledger under this
  feature with `cost_usd` **0** (`19c`, `19d`), after which
  `--list-subagents --unclaimed` stops listing it (`19e`). The listing BEFORE the pin is
  the guard and comes first: a delegate the listing never held would satisfy `19e` on its
  own. RED until the ledger was written from `subagents[]` instead of from the priced
  rows — before that the id was in no feature's claims and every run told the human to
  write the pin that was already in the manifest.
- `claims-ledger.sh` — `subagent-capture.sh`'s scaffolding, asserting what the ledger at
  `$HOME/.claude/subagent-claims.json` counts as claimed
  (`self/features/recovered-duration-lower-bound/README.md`, items 2 and 3, plus that
  feature's two review escalations). Four parts.
  **A**: `--list-subagents --unclaimed --for <repo>/<slug>` drops a delegate whose id is
  already in that feature's manifest `subagents` — "unclaimed" used to mean "not claimed
  through a branch", so every close printed its own pinned delegates and told the human
  to pin them — while an unpinned sibling briefed for the same feature is still listed
  with the `Pin each in` advice beside it, and with every delegate pinned the list is
  empty and the advice is gone. A delegate already in the ledger is still dropped, read
  from a **legacy flat** ledger file (agent id → claim, no section keys — the shape on
  every machine today), which is how that half asserts an old ledger still loads. **B**:
  two manifests pinning one session id — the coordinator that spans features. The second
  capture is *not* refused the way a doubly-claimed subagent is, its `planning.json`
  session entry gains `also_claimed_by: ["<repo>/<slug>"]`, the ledger holds both claims
  under that session id as a **list** (a session may have many claimants, a subagent
  exactly one), and re-capturing the first feature annotates it symmetrically. Neither
  manifest declares a `session_window`, so both claims are unbounded and the money is
  split evenly between them: `report.py` renders
  `cost.shared_sessions[{session_id, cost_usd, session_cost_usd, also_claimed_by}]`,
  where `cost_usd` is this feature's own share and `session_cost_usd` the undivided
  session beside it, the two features' shares sum to `session_cost_usd`, and the one
  footnote under the Cost table names the session and the other feature without saying
  it is counted in full — the sentence that was the whole disclosure before the split
  existed. A `planning.json` frozen before the share rule carries `also_claimed_by` but
  none of `share_basis`/`session_cost_usd`/`session_duration_s`, and is still reported
  the old way: `shared_sessions[]` with no `session_cost_usd`, and a footnote that falls
  back to saying the session is counted in full there. Finally the **in-flight
  co-claimant**: `also_claimed_by` stripped while `share_basis` is left in place — the
  shape of a feature that captures while another feature pinning the same session has not
  captured yet, so the split found the co-claimant through its manifest but the ledger
  holds no claim from it. That record still produces a `shared_sessions[]` entry naming
  the co-claimant recovered from `share_basis`, and a footnote, because keying the
  disclosure off the ledger alone prints a halved figure with nothing saying what halved
  it — a silent under-count, worse than the disclosed over-count the split removed, and
  the corpus's normal case rather than a corner. The record is restored from a copy
  immediately afterwards, since part C asserts an exact `2 annotated` count over an
  `--all` run of the whole corpus.
  **C**: the annotate-only path over a record that is already **frozen** — two features
  each captured while the ledger held no claim on their shared coordinator, which is the
  shape the seven closes of 2026-09-07 left behind. One plain `capture_planning.py --all`
  (no `--recapture`, the corpus-wide repair run) leaves each of them naming the other, and it
  does so in a single run because every frozen record is registered in the ledger before
  any is annotated — convergence must not depend on the order the corpus is walked in.
  Everything else in both files is byte-identical (asserted over the whole record with
  `also_claimed_by` stripped, not over a list of fields), the run reports them as
  `annotated`, `report.py` then renders the footnote, and a second `--all` writes
  nothing. The shared session's transcript is **deleted before that run**, which is what
  asserts the path opens none — the reason a frozen record can take it at all. **D**: the
  same-slug corpus preference — a `plans/features/<slug>` pinning a delegate and a
  `self/features/<slug>` of the same name that does not. Under `--self` the delegate is
  still listed as unclaimed (the self corpus owns the query), without `--self` it is not,
  and a slug the queried corpus does not hold at all falls back to the slug alone across
  both. Before it, the other corpus's pin silenced the close's stop-on-unpinned guard (now
  `feature-capture.sh`'s unclaimed-delegate warning) and the delegate was never priced.
  Depends on `capture_planning.py`'s `load_ledger`/`save_ledger` two-section shape,
  `manifest_pinned_subagents`, `register_frozen_claims`/`annotate_frozen_record`, and
  `report.py`'s `compute_shared_sessions`; RED until each landed. D writes into
  `$TMP/plans/features`, the host repo's corpus, which `all_features_roots()` resolves
  as the sibling of the throwaway agentTooling checkout.
- `session-share.sh` — `claims-ledger.sh`'s arithmetic counterpart: same scaffolding
  (copies of `analysis/{pricing,roots,transcript,capture_planning}.py` into a throwaway
  agentTooling checkout, `mkdir -p "$AT/.git"`, and, under a redirected `$HOME`, the
  `~/.claude/projects/*/<session_id>.jsonl` transcripts capture reads, built with
  `session_line` from `fixtures/transcripts/build-transcript.sh`). Asserts what a session
  claimed by more than one feature is priced and timed by — *concurrent share* rather
  than being counted in full by every claimant. One session
  (`11111111-0000-0000-0000-000000000001`) carries six responses, all input/cache-read/
  cache-creation `0` so cost is proportional to output tokens alone:

  | id | timestamp | output tokens |
  |---|---|---|
  | `r0` | `08:00` | 1000 |
  | `r1` | `10:30` | 2000 |
  | `r2` | `12:30` | 4000 |
  | `r3` | `14:30` | 6000 |
  | `r4` | `16:30` | 12000 |
  | `r5` | `20:30` | 800 |

  Four features (`share-a`..`share-d`) pin that session id in their manifest's
  `sessions`, with `branches` naming a branch no transcript carries — the pin is the only
  route in — and these windows: `share-a` `10:00`-`18:00`, `share-b` `12:00`-`18:00`,
  `share-c` `14:00`-`18:00`, `share-d` `16:00`-`18:00`. A fifth, `share-solo`, pins its own
  session and is claimed by nobody else. Ownership per response is every claimant whose
  window covers its timestamp, with the earliest claimant alone owning anything before
  every window opens and nobody owning anything after every window closes: owned output
  tokens are **a 10000, b 7000, c 5000, d 3000, unclaimed 800**, summing to the session's
  25800; duration, partitioned the same way over `[first line, last line]` = 45000s, is
  **a 22200, b 7800, c 4200, d 1800, unclaimed 9000**. Captures the four in order a, b, c,
  d, then re-captures `share-a` so its record sees the other three claims — a claimant not
  yet captured is still found through its manifest alone. Asserts, in order: (1) the four
  shares plus the unclaimed remainder equal the session's own `cost_usd.total`, to `1e-9`
  — the assertion the whole feature exists for; (2) each feature's `cost_usd.total`
  matches its predicted token-ratio share; (3) the earliest claimant's total strictly
  exceeds what its share would be without the head response, while the other three carry
  none of it; (4) `share_basis` on the earliest claimant's entry names all four claimants
  — itself first with `source: "self"`, the other three `"manifest"` with their own
  manifests' `from`/`to`, asserted as a set rather than an order; (5) `duration_s` is
  apportioned by the same rule (22200/7800/4200/1800), `session_duration_s` is the whole
  45000s span on every entry, the unclaimed span is **read from the record's own
  `unclaimed_duration_s`** and the four apportioned spans plus it sum to 45000 — an
  earlier cut asserted the unclaimed `9000` as a literal, which supplied the missing
  seconds itself instead of catching their absence and so could not see a session leaking
  time, and `started_at`/`ended_at` stay the session's own first and last instants
  throughout — only `duration_s` is apportioned; (6) `share-solo`'s single-claimant entry
  carries none of `share_basis`, `session_cost_usd`, `session_duration_s` or
  `unclaimed_usd`, no `priced[]` row carries `share` or `full_cost_usd`, `duration_s`
  equals `ended_at - started_at`, and `cost_usd.total` is the whole transcript's cost;
  (7) a second `r2` line appended at `11:59:59.500`, before `share-b`'s `from` of `12:00`,
  while `r2`'s first line — first in *file* order, which is what `iter_billable_messages_at`
  keys on — stays at `12:30` inside that window: the two lines of one response sit in
  *different* ownership stretches, `{share-a}` and `{share-a, share-b}`. It is still billed
  once and to its first line's owners: assertion (1)'s invariant still holds and `share-a`/
  `share-b`'s totals from (2) are unchanged. Both halves are load-bearing — a walk that
  buckets lines by window and dedups within each bucket bills `r2` once per bucket and
  breaks (1), and one that dates a response by its *last* line hands all 4000 tokens to
  `share-a` and breaks (2). An earlier cut of this phase appended the line at
  `12:00:00.001`, on the same side of every boundary as `12:30` and in the same ownership
  set, where no dedup strategy can differ and all three checks passed vacuously; (8) capture output names the session in an
  unclaimed-remainder warning, `unclaimed_usd` is exactly the `800/25800` share of the
  session cost, and — `8c`, added by `bounded-opening-stretch`'s rework — that warning is
  the pre-existing tail sentence with no head clause in it, this session having no head
  (`share-a`'s eight-hour window puts its bound four hours before `r0`); (9) a sixth feature `share-empty`, pinning the same session with a
  *backwards* window (`09:00`-`03:00`), owns nothing — not the head its early `from` would
  otherwise rank it first for, and not a second of duration — while a-d's totals and the
  sum invariant are unchanged; (10) the same defect from its other side, `share-empty-2`
  (`05:00`-`03:00`, opening before the session's own first response), must not strand the
  head in the unclaimed remainder; (11) its costliest shape — `share-solo-empty` pins
  `share-solo`'s single-claimant session with a backwards window, and `share-solo` must
  stay unshared (no `share_basis`, whole cost, untouched duration) with the offending
  claim named on stdout. An empty claim from another feature is dropped from the claim set
  outright rather than merely refused a share, because `select_parent` branches on
  `len(intervals) <= 1`: counted, it flips a solo session onto the share path and its one
  real owner loses everything past its own `to`. Phases 9 and 10 are the two ways an empty window
  reaches the split — pinning by id skips window matching entirely, so a backwards window
  arrives intact and the head-stretch ranking orders on `from` alone: one shape pays it,
  the other silently underpays the legitimate earliest claimant. Both were caught in the
  verify pass, not the build. Extracts the repeated JSON reads into `field` (a `python3 -c` over
  `json.load`) and `close_enough` (the `1e-9` float comparison) near the top rather than
  repeating a one-liner in every check. Phases 1-5 and 7-8 were RED until
  `capture_planning.py` learns to share a multiply-claimed session — a run against
  today's code is expected to FAIL them, not crash. Phase 6 is GREEN today and must stay
  green: it is the no-change half of the contract, pinning that a session with a single
  claimant is never touched by this feature. Phases 9-10 were RED against the build pass's
  own first cut of `share_owners`, which filtered empty windows out of `in_window` matching
  but not out of the opening-stretch ranking. No model, no network.
  Two later phases are `claim-window-precision`'s. **12** is the size of what phase 6
  leaves unsliced: `share-outside` pins a session of its own with 1000 output tokens
  inside its window and 3000 after it, so the dollars past `to` are exactly three quarters
  of the session's cost and a warning that named the whole session, or only the part
  inside, prints a different figure. The figure is read back out of the warning
  numerically (a 4-decimal string compare would fail on a last-place rounding difference)
  and `cost_usd.total` is asserted to exceed it, which is what pins the session as still
  priced whole; `12g` is the other branch of the same sentence, `not counted`, off
  share-a's own capture. **13** tightens `share-d`'s `to` to `16:15` — past its `from` but
  before its only response at `16:30` — through the real `manifest.py set-window-to
  --tighten`, which is why this file also copies `manifest.py` into the sandbox. share-d
  then owns nothing and the sum invariant from (1) still holds; `13c` asserts share-c's
  total ROSE, so a tighten that silently did nothing cannot pass. `16:00` was rejected as
  the tightened bound: it makes share-d's own window empty, and the assertion would then
  be satisfied by the pre-existing empty-claim drop rather than by the moved bound.
  **14** is phase 12's warning where there is nothing to quantify: `share-quiet` pins a
  session with one response well inside its window and, half a second past `to`, an
  unbilled `user_line`. The warning fires on the last LINE while the quantity counts
  billable RESPONSES at or after `to`, so the two are out of step and the quantified
  sentence would assert a measurement of nothing. The assertion is the absence of the
  figure — read back with the same `sed` phase 12 uses to read its presence, so a
  formatted `$0.0000` fails rather than passing as "zero is zero anyway" — plus the
  qualitative sentence saying no billable response falls past `to`, and `cost_usd.total`
  still non-zero, the warning being prose either way.
  **15** is `bounded-opening-stretch`'s, on a session and claimants of its own
  (`66666666-0000-0000-0000-000000000006`; `head-a` `10:00`-`11:00`, `head-b`
  `12:00`-`18:00`; responses `r0` `08:00`/1000, `r1` `09:30`/2000, `r2` `10:30`/4000,
  `r3` `13:00`/3000) so that nothing above is re-run or disturbed. The opening-stretch
  fallback pays the earliest claimant only as far back as that claimant's own window is
  long — `head-a`'s hour puts its bound at `09:00`, so `r1` is still its own and `r0`,
  two hours out, is owned by nobody. Asserts `head-a`'s total is `r1 + r2`; that
  `unclaimed_usd` is exactly `r0`'s `1000/10000` share and the two totals plus it equal
  `session_cost_usd`; that `head-b` is unchanged at `r3` alone; that `duration_s` splits
  the same way — `head-a` `09:00`-`11:00` = 7200s, `unclaimed_duration_s` the 3600s
  before the bound plus the 3600s gap between the two windows, the three summing to the
  18000s span; that the unclaimed warning names the head's dollars and seconds APART from
  the rest of the remainder (the figure read back numerically, as `12c` does) and names
  the remedies that reach a head — pin the session, or move the earliest claimant's
  `from` back by hand, `from` having no `set-window-to`; and that an earliest claimant
  whose `to` is still `null` keeps the UNBOUNDED head, a window with no end having no
  length to bound by, which is why `write_manifest` writes a bare JSON `null` for a `to`
  of the literal string `null`. `15a`, `15b` and `15b-sum`, `15d` and `15d-unclaimed`,
  and every `15e` check were RED against the unbounded fallback on `main`, which pays
  `head-a` the `08:00` response and `08:00`-`11:00` of the span; `15c`, `15d-sum`, `15f`
  and `15f-unclaimed` are green on both sides and are the guard, as is phase 3 — an
  eight-hour window still reaches a head response two hours out, which is what stops the
  bound being read as a fixed grace period. `15f-duration*` is that phase's rework
  addition, the seconds side of the in-flight exemption: with `head-a`'s `to` `null`,
  `head-a`'s `duration_s` is 16200 (`08:00`-`10:00` as the unbounded head, `10:00`-`12:00`
  as its own open-ended window, and half of the `12:00`-`13:00` overlap), `head-b`'s is
  1800, and there is no `unclaimed_duration_s` at all. It is the one path where
  `partition_seconds` gets `head_edge = None` and adds no cut point, so it is where the
  dollars and the seconds are least constrained to agree, and `15f` asserted only dollars.
  **16** and **17** are the same feature's rework. **16** is a remainder that is ALL head:
  a session of its own (`77777777-0000-0000-0000-000000000007`; `n0` `08:00`/1000, `n1`
  `10:30`/2000, `n2` `13:00`/3000) with `allhead-a` `10:00`-`11:00` and `allhead-b`
  `11:00`-`14:00` chaining end to end — `in_window` is half-open, so `to == from` leaves
  no gap — and running past the last response, so the only unowned instants are the
  `08:00`-`09:00` before `allhead-a`'s bound. The warning must then drop its "and $0.0000
  (0s) is the rest" clause and its "For the rest" sentence rather than hand the reader the
  `to`-widening remedy for nothing, which no `to` widened forwards could reach anyway.
  `16a`/`16a-usd` assert the fixture's own premise — `unclaimed_duration_s` is 3600 and
  `unclaimed_usd` is `n0`'s `1000/6000` share — without which the two negative greps would
  pass vacuously on any session that simply has no head. **17** pins the bound's INCLUSIVE
  edge (ruling 1 is `min_from - moment <= to - from`): a fresh session again
  (`88888888-0000-0000-0000-000000000008`; `e0` `09:00`/1000, `e1` `10:30`/2000, `e2`
  `13:00`/3000, `edge-a` `10:00`-`11:00`, `edge-b` `11:00`-`18:00`), since a fifth response
  on phase 15's session would re-base every token fraction in `15a`-`15f`. `edge-a`'s hour
  puts its bound at `09:00` exactly, where `e0` sits: its `cost_usd.total` is `e0 + e1`,
  its `duration_s` is 7200 (`[bound, from)` plus its own window), and nothing on the
  session is unclaimed in either currency. `16c` and `16d` were RED against the build
  pass's own warning, which always emitted both halves of the sentence pair; `17a`, `17b`
  and `17c` are red only under a mutation — flip `share_owners`' `moment < bound` to `<=`
  and all three move, while `15a` (the dollars) stays green, which is exactly the gap.
  `8c`, `15f-duration*`, `16a`, `16a-usd`, `16b` and `16e` are guards, green before and
  after. `8c` is the fourth escalation, on phase 1's output: with no head the warning is
  the pre-existing tail sentence and carries no head clause at all — the `elif` branch had
  no reader before it.
  **18**, **19** and **20** are `ledger-and-routing`'s, the open co-claimant
  (`../DESIGN-2026-09-18-ledger-and-routing.md` §2), on a fresh day and two fresh
  sessions so nothing above moves. `open-cap` is captured; `open-co` is in flight
  (`to: null`), pins the same session (`99999999-…-000000000009`; `o0` `10:00`/1000, `o1`
  `12:00`/2000, `o2` `14:00`/3000) and has a **branch session of its own**
  (`aaaaaaaa-…-00000000000a` on `openCoBranch`, last instant `13:00:00`) — which is what
  `write_manifest`'s fifth argument is for, since every other fixture here declares a
  branch no transcript carries and is claimed by pin alone. Its provisional bound is
  therefore `13:00:01Z`, one second past that instant, exactly what its own close would
  stamp. **18** asserts `open_claimants` names it, its `share_basis` entry carries
  `open: true` and that `provisional_to` as its `to`, the capturing feature's own (closed)
  claim carries neither key, and `open-cap`'s share is the bounded `5000/6000` — with
  `18c-guard` asserting it is NOT the `3500/6000` an unbounded open claim would leave it,
  so a bound derived and then ignored fails here. **19** is the drift WARN over
  `--annotate-frozen`: silent while `open-co` is still open, silent once its close stamps
  the same bound, and exactly one line naming the record, both bounds and `--recapture`
  once it stamps a different one (read from a `2>&1` capture, the WARN being on stderr so
  that `feature-capture.sh` can go on reading that pass's stdout as slugs). **20** is the
  reason the bound is derived with the function the close calls: with `open-co` closed at
  that bound, a re-capture of `open-cap` reports the same dollars and the record stops
  naming an open claimant. The **no-evidence** half of the rule is phase **15f**, where
  `head-a` is in flight and its `branches` match no transcript: `last_branch_instant`
  finds nothing, the claim is empty, the empty-claim rule drops it naming it as open with
  no evidence (`15f-open-no-evidence`), and `head-b` — which used to be paid a 1800s share
  of `head-a`'s unbounded claim — owns the session whole, which is what `15f-duration-b`
  now reads. `15e-remedy-from` moved with §4: the head's second remedy is the
  `set-window-from` command, filled in, and `15e-remedy-by-hand` pins that the sentence it
  replaced ("back by hand") is gone.
- `session-claims.sh` — `session-share.sh`'s counterpart on the claim-set side: same
  scaffolding, plus a `write_host_manifest` twin of `write_self_manifest` that writes into
  `$TMP/plans/features` (the enclosing repo's own corpus, per `claims-ledger.sh` part D)
  and direct writes/edits of `$FAKE_HOME/.claude/subagent-claims.json`. One session
  (`33333333-0000-0000-0000-000000000003`) with four responses two hours apart from
  `2026-06-02T10:00:00.000Z`, equal output tokens so cost is proportional to them alone;
  `claim-here`, in the self corpus, pins it with window `10:00`-`20:00`. Asserts the three
  sources a claimant is found from and their ranking: (1) a manifest in the OTHER corpus —
  `claim-there`, window `14:00`-`20:00` — is found live, `share_basis` naming
  `<enclosing repo>/claim-there` with source `"manifest"`, claim-here's total three
  quarters of the session cost (it owns the first two responses alone, half of the last
  two); (2) with that manifest gone, a claimant in a THIRD repo this checkout cannot read
  a manifest from at all — `otherRepo/claim-elsewhere` — is found from the ledger's
  `sessions` section instead, same three quarters, source `"ledger"`; (3) a *stale* ledger
  entry for `claim-there` under its own `(repo, slug)` does not duplicate its live,
  current manifest entry — one entry, source `"manifest"`, carrying the manifest's
  current `from` rather than the ledger's old one; (4) a claim with no `window` key at all
  (the shape recorded before this feature existed) is read as unbounded — `from`/`to` both
  null in `share_basis` — splits claim-here's cost exactly in half, and is warned about by
  name; the same claim seeded into a LEGACY FLAT ledger (no `subagents`/`sessions` keys)
  still loads but is never read as a session claim — claim-here's cost reverts to the
  full, unshared figure, no `share_basis` at all; (5) a fifth response appended as the
  parent transcript's OWN sidechain line (`session_line … true`, plan 89's addition),
  inside every claimant's window, is shared the same way: `cost_usd.sidechain` is halved
  on this feature and `cost_usd.total` still equals `main + sidechain`; (6) after a
  capture, the ledger's own `agentTooling/claim-here` entry carries a `window` of
  NORMALIZED instants (python `isoformat`, `+00:00`) rather than the manifest's raw
  strings, asserted by parsing rather than string equality — the shape a third repo's
  capture (assertion 2's scenario) reads; (7) a record frozen with no other claimant, then
  claimed by a manifest and a ledger entry that both appear only after the freeze, is
  ANNOTATED by a plain `--all` (no `--recapture`) rather than recomputed — every field
  byte-identical to the frozen copy but `also_claimed_by` (asserted with
  `same_but_annotation`, `claims-ledger.sh` part C's helper), and the run separately warns
  naming the slug and the session that the frozen figure predates the share rule and
  `--recapture` would rebuild it while the transcript still exists — and goes on warning on
  the SECOND consecutive `--all` (7d-7f), which writes nothing: the annotation converges on
  the first pass and the stale full-count figure does not, so a warning keyed off "did
  this run write" asks for the repair once and then goes quiet for as long as the
  transcript has left, while the `skipping` line still means the run wrote nothing;
  (8) the subagent side
  of the ledger is untouched — a subagent claim-here already claims still refuses a second
  feature's (`claim-twin`'s) capture outright, one check, asserted by reference to
  `subagent-capture.sh`'s own fixture rather than re-derived here; (9) the claimant scan is
  indexed once per capture rather than repeated per selected session — a `python3 - <<'PY'`
  block (the `sys.path` insert of the copied `analysis/` the other tests use) wraps
  `parse_manifest` in a counter, calls `build_claimant_index`, then
  `session_claim_intervals` for three different session ids, and asserts the counter did
  not grow after the index was built. It refuses to pass on an empty corpus (`VACUOUS`
  below two manifests parsed), since a count of zero is trivially stable; what the index
  must not change is any *answer*, and that is asserted by every other check in this file
  and in `session-share.sh` rather than here; (10) the same claim set asked of the
  **vendored** layout, in a second sandbox — assertions 1-9 stand up the standalone shape
  (`$AT` holds the `.git`), where the self corpus's identity comes out right whichever
  rule derives it. Here a consuming repo `vendorHost` holds a real `git init` with a real
  `origin` (not the bare `mkdir .git` the rest of the file uses: an invalid `.git` makes
  the subprocess exit 128 and `repo_identity` fall back to the *vendored* directory's own
  name, `agentTooling`, which is accidentally the right answer — the wrong answer needs a
  `git` that succeeds), `agentTooling/` beneath it with no `.git`, and the transcripts
  filed under the enclosing directory's project path with `cwd` the enclosing directory,
  so `session_root(True)` is the consumer. Four equal responses, `claim-here` and
  `claim-self-twin` both in the self corpus with windows covering the whole transcript:
  the twin appears in `share_basis` as `agentTooling/claim-self-twin` with source
  `manifest` (10a) and nothing in `share_basis` is named for the enclosing repo, the
  capturing feature itself included (10b); a ledger claim on the same feature under the
  declared identity and a *different* window dedupes into that one entry rather than
  becoming a third claimant (10c), keeping the manifest's `from` (10d); `claim-here`'s
  total is therefore half the session, not the 5/12 three claims produce (10e); and the
  ledger row the capture writes for itself carries `repo`
  `https://github.com/ssdesai/agentTooling.git` and `repo_name` `agentTooling` (10f, 10g).
  The fixture's own precondition is checked rather than assumed — `git -C $VHOST remote
  get-url origin` really is `$VENDOR_ORIGIN` (10-pre) — because a `git` that failed there
  would hand the rule the *right* answer by accident and pass the whole phase vacuously.
  10h-10j then put assertion 7's shape into the same layout, which is the only route
  through `register_frozen_claims` and the `--all` loop's `annotate_frozen_record` call:
  the ledger is reseeded to the two rows a SHARED ledger really holds here — `claim-here`'s
  own and a second feature's, both under the declared identity, since the standalone
  checkout's `--self` runs wrote them — and a plain `--all` (no `--recapture`) annotates
  the frozen record rather than recomputing it (10-annotated, `same_but_annotation`
  again), naming `agentTooling/claim-self-twin` in `also_claimed_by` (10h) and nothing
  ending in `/claim-here` (10i), while the ledger keeps exactly ONE `claim-here` row and
  it carries the declared identity (10j). 10i is the defect in that path:
  `other_session_claimants` excludes a feature's own claim by `(repo, slug)`, so a frozen
  `--self` record annotated under the consumer's origin misses its own `agentTooling`
  ledger row and lists ITSELF among its co-claimants.
  1-7 were RED until `capture_planning.py` looked beyond its own corpus and its own
  manifest for a session's claimants, and 10a-10g, 10i and 10j until `corpus_identity`
  declared the self corpus's identity rather than deriving it (10-pre, 10-annotated and
  10h are green either way: they pin the fixture and the branch taken, not the identity); (8) was GREEN throughout — the subagent
  refusal it pins is pre-existing and must stay exactly as it is while the session side
  grows around it. No model, no network.
- `manifest-window.sh` — `analysis/manifest.py set-window-from`, the head's remedy
  (`../DESIGN-2026-09-18-ledger-and-routing.md` §4). A throwaway agentTooling checkout
  holding `analysis/{pricing,roots,transcript,routing,manifest}.py` (`routing` because
  `manifest.py` imports it for the transcript lookup, per the rule at the top of this
  file), one fixture manifest, and under a redirected `$HOME` one session transcript whose
  first and last instants are `09:00` and `11:00` on a fixed date. **`set-window-to`'s own
  cases are not here** — they are `feature-lifecycle.sh`'s W phases, asserted through a
  real capture because that is where a `to` bound comes from. Nothing derives a `from`, so
  this file drives the command straight at a fence and asserts the four answers it can
  give: a bound moved BACK to the session's first instant is applied and echoed
  `old -> new` with `to` untouched (M1); an instant before that first instant is refused,
  naming it (M2); a LATER instant is refused, the message saying this command only moves
  the bound back and that nothing narrows a `from` — `set-window-to` moves `to` (M3); the
  instant already written is a no-op at exit 0 (M4); a session no transcript carries is
  refused rather than waived, the guard being unevaluable (M5); on a feature whose
  `planning.json` carries a `captured_at` the move is applied AND the output names
  `--recapture` (M6); a null `from` is refused, there being no bound to move (M7); and
  `--session` is required, which is argparse's own exit 2 (M8). Every refusal asserts the
  manifest is left **byte-identical** beside the exit code, and each expects 1 (or 0)
  rather than merely non-zero — against the branch before the subcommand existed argparse
  exited 2 for all of them, so "non-zero" would have passed vacuously. The fence markers
  in its readers are spelled `chr(96)*3`: three backticks inside a double-quoted shell
  word are a command substitution. No model, no network, no git.
- `timestamps-are-utc.sh` — same scaffolding, asserting the UTC convention in
  `analysis/README.md` → "Every instant is UTC": `transcript.utc_date` dates an offset
  timestamp by its UTC day (`2026-07-01T23:00:00-04:00` → `2026-07-02`), a session's start
  is the earliest *instant* rather than the lexicographically smallest string, a
  `session_window` bound with an explicit offset selects exactly what its `Z` equivalent
  selects, an offset-less bound means UTC (what the committed corpus already means), windows
  chained across the two formats raise no false overlap warning, and `pricing.utc_today()`
  is identical under `TZ=Pacific/Kiritimati` and `TZ=Pacific/Midway` — whose local dates
  always differ, since the two offsets span 25 hours, making that a deterministic check that
  it is not `date.today()`. The assertion worth the most: a session at
  `2026-08-21T23:00:00-04:00` is `2026-08-22` UTC and must price at sonnet-5's **intro**
  tier, 2/3 of standard — the old `timestamp[:10]` slice dated it locally and priced it
  standard. Calls `reset_capture` between phases, since the frozen-cost guard would
  otherwise (correctly) refuse a write once a previous phase's transcript is removed, and
  passes `--recapture` on every call, since capture otherwise skips a feature that
  already has a `planning.json` and several phases here re-capture under a changed
  manifest with no reset in between.
  Also covers `check_naive_bounds`: a bound with no zone is warned about by field name
  and value, a `Z`-suffixed or explicit-offset one is not, and a *sibling* manifest's
  naive bound is not — that last one is what keeps the warning actionable rather than a
  standing complaint about every other feature in both corpora.
- `allow-repo-commands.sh` — builds a throwaway project root with a venv symlink, an
  in-repo worktree, the harness's own entry points in both spellings (a consuming repo's
  `plans/gate.sh`, `agentTooling/check-plans.sh`, `agentTooling/analysis/*.py` and this
  checkout's `self/gate.sh`, `./check-plans.sh`, `analysis/*.py` — empty files, since the
  hook judges paths and arguments, not contents) and three symlinks that escape the tree,
  then feeds the real `hooks/allow-repo-commands.sh` the payload Claude Code sends, one
  command at a time.
  Asserts that ordinary reads and runs are approved; that each entry point is approved by
  basename when its path resolves inside the root, and prompts outside it, through an
  escaping symlink, or in a writing form (`capture_planning.py --recapture`/`--all`,
  `manifest.py init`/`set-*`/`get init`, `python3 -c`, `bash` without `-n`,
  `feature-start.sh` and the rest of the scripts that move refs or freeze cost) — so
  basename matching never widens `python3`; that a BARE `check-plans.sh` or `gate.sh`
  prompts, since bash would resolve a word with no directory component along `$PATH`
  while the hook judged a file it found in the repo; that every ref-moving git shape is **denied**
  wherever it sits on the line (after a separator, in a `(…)` subshell or a `$(…)`
  substitution, behind `-C`, `--git-dir=` or `-c k=v`) with a reason naming LIFECYCLE
  rule 2, `feature-start.sh` as the way in **and** `feature-close.sh` as the way out —
  `git worktree move|lock|unlock|repair` and `git branch --delete|--move` among the
  denied, the four shapes `permissions.deny` used to miss — while `git branch --show-current`, `git worktree
  list`, `git branch --list 'feat*'` (after a listing flag a positional is a pattern),
  a plain `git push`, `git checkout -- <file>`, `git reset <file>`, a quoted
  `'git rebase'`, a heredoc and a `#` are not; that
  both denies fire with no `CLAUDE_PROJECT_DIR` and no `cwd`; that any command chaining `cd` or
  `pushd` with another command is **denied** (separators `&&`, `||`, `;`, `|`, `&`, a
  line break, a `(` subshell) with a reason naming the rewrite, while `cd`
  as an argument, in quotes, as a redirect target, in a heredoc body (including one
  behind a mid-word `#`), inside a `$(…)` substitution quoted or not (nested ones too,
  with a word after the `)` not read as a command) or on its own is not; that the four
  motivating shapes are approved once rewritten as a standalone `cd` and the command;
  and that simple brace lists are approved when every expansion passes; that every
  bypass the audit found is refused (variable expansion, `--flag=value` paths, attached
  and combined short flags, sed's `w`, `git branch` mutation, exec-through flags,
  brace expansion to a path outside, a forbidden flag, `~`, or through nested, quoted
  or escaped braces, `|&`, a command hidden behind a mid-word `#` that shlex would read
  as a comment, relative paths and globs through symlinks,
  symlink-following recursion, redirects, a NUL byte); that the second audit's closures
  hold — an assignment at command position read as the program (`X=…/pytest src/a.py`
  executed `src/a.py`), an attached-value flag path (`grep -f/etc/hosts`), `ls -L`/`ls
  -RL`/`du -L` walking through a symlink out, `rg --hostname-bin`/`-z` and
  `git --textconv`/`--ext-diff` running an external program, `ruff --fix` and a bare
  `ruff format` rewriting the tree, `mypy --install-types`, and
  `capture_planning.py --force` — each beside the near-miss guard that must stay
  approved (`grep -d recurse`, `find -H`, `git log --format=%x41`, `ruff format
  --check`, `ls -la`, `du -sh`), so a closure that over-reached fails here rather than
  in a consuming repo; that every **opaque** shape is denied with a reason naming the
  rewrite — a heredoc into an interpreter, `-c`/`-e` code as a string (including behind
  `xargs` and `find -exec`), a pipe into an interpreter, a `$CMD`/`$(…)` program, a
  `$(…)` inside a path, a one-line `for`/`while`/`if`/`until`/`case` — while the
  exemptions are not: a heredoc feeding `cat`, `git commit -m "$(cat <<'EOF' … EOF)"`,
  `x=$(cd dir && pwd)`, a whole-argument `$(…)`, an interpreter named in a flag's
  VALUE rather than at a command position, and a *script's* own `-c`/`-e`
  (`python3 src/a.py -c conf.yaml`); that the `cat` exemption covers the heredoc's body
  and not the rest of its first line, so `cat <<'EOF' | python3` and
  `bash -c "$(cat <<'EOF' … EOF)"` are denies; that a line which does not tokenize at
  all — the seventh shape — is denied with a reason naming the **quote** (`cat 'x`,
  `git rebase 'main`, `cd 'x && ls`, `X='/p; cat $X`, each of which used to sit in a
  NOT_DENIED list), while the same quote inside a heredoc body or behind a `#` still
  prompts; that single-quoted shell
  characters are literal while double-quoted ones are not — including **for the opaque
  scan**, which read a word's outer single quotes off before asking whether it held a
  substitution and so DENIED `sed -n '/```json/,/```/p' <path outside the root>` as a path
  decided at run time (it prompts now, and `grep 'a`b' README.md` is approved), while the
  unquoted forms `` cat `pwd`/README.md `` and `` `which ls` src `` are still denied and
  two new guards — ``sed -n 5p `pwd`/README.md``, `cat $(pwd)/src/a.py` — keep the
  narrowing from drifting into them; that each **rewritable shape** of the 2026-09-18
  design is denied with a reason carrying the member AS WRITTEN and the fix — a `$NAME`
  the shell expands (`grep x $FILE`, `cat "$HOME/.zshrc"`), a `~`, a brace group the
  expansion refuses (a quote or backslash mixed into an unquoted brace group, nesting,
  past the cap — while a comma-less `{a}`, `{a..c}`, find's `{}` and a brace a quote
  encloses (`jq -r ".[] | {name}" data.json`, `git show "stash@{0}"`) keep prompting,
  since bash expands none of them), a `..` **component** of a path token (`cat ../x`,
  `ls a/../b`, `--out=../x`, while `git diff main...HEAD` has none), a bare or relative
  `cd`/`pushd`, a line break outside a quote or a heredoc (`git commit -m "subject\n\nbody"`
  is one argument and keeps prompting), and a sequence mixing approved members with one to run alone
  (`grep x f && git commit -m m`, whose reason names the first as approved and the second
  to run alone) — each of which used to print nothing, and every one of which is moved
  from a prompting list rather than from ALLOW or DENY
  (`self/features/hook-rewrite-or-ask/NOTES.md` lists the moves); that the **ASK** class
  prints nothing at all (`git diff main...HEAD`, `x=$(cd dir && pwd)`, an all-ASK
  sequence, a pipeline, `X=1 make`, `cat README.md > f`, `cat /etc/hosts`, a CR, a NUL), with no
  `ask` decision anywhere in it; that a heredoc or a `#` anywhere holds the new shapes off
  the line entirely, as it does the three older denies; that a **file authored through
  the shell** (`../features/shell-write-rewrite/`) is denied with a reason naming the
  member as written, the Write and Edit tools and why (`AUTHORING_REWRITE`: `echo`/`printf`
  through every redirect operator and spelling, `cat`/`tee` fed a heredoc, a herestring or
  a pipe from `echo` with output to a path — the motivating `cat >> tests/test_x.py
  <<'EOF'` among them — and every `sed -i` spelling), that a literal-fed `tee` gets that
  reason and not the scratchpad one while a heredoc into an interpreter with an output file
  is still the opaque deny, that a chained `cd` or an own-assignment on the same line
  still gets its own older deny reason (`AUTHORING_BEHIND_SHAPE_DENIES`), and that
  captured output, the commit-message heredoc, a quoted
  or escaped `>`, fd duplications, the non-file targets, a process substitution, `sed`
  without `-i`, `cp`/`mv`/`touch`/`mkdir`/`rm`/`ln`, a heredoc body full of redirects and a
  `#` on the judged line are not (`AUTHORING_NOT_DENIED`) — nine cases moved into that
  list from `PROMPT`, `OPAQUE_NOT_DENIED`, `ASK_CASES` and `MIXED_REWRITE`, whose `echo x >
  cd && ls` became `cat README.md > cd && ls` to keep its point
  (`../features/shell-write-rewrite/NOTES.md`); that `self/tests/fixtures/hook-replay-2026-09-18.json`
  replays with the verdict each record claims and each denial's reason (its `echo x > f`
  record is REWRITE now);
  that a read-only git subcommand **behind the global
  location options** is judged by the subcommand (`git -C <root> status`,
  `git --git-dir=<root>/.git log`, `git --work-tree=<root> status` approved; `git -C /tmp
  status` and `git --git-dir=/tmp/x log` prompt on the value; `git -c core.pager='sh -c
  id' log`, `git -C <root> -c core.pager=x log`, `git --exec-path=<root> log` and
  `git --namespace=x log` prompt because none of those names a location; `git --paginate
  log`, `git -p -C <root> log` and `git --no-pager -C <root> log` prompt because nothing
  else in front of the subcommand is read past; `git -C` and `git -C --git-dir status`
  prompt for want of a value; `git -C <root> -C /tmp status` prompts on the second value;
  `git -C <root> diff --ext-diff` prompts on the forbidden flag; and `git -C <root> branch
  new`, `git -C <root> worktree add x` and `git --git-dir=<root>/.git stash` are still
  **denied**) — 26 cases, since finding a subcommand must never be mistaken for approving
  it; that a worktree session
  cannot reach the main repo; and that a payload without `cwd`, with `cwd` outside the
  root, for another tool, or without `CLAUDE_PROJECT_DIR` approves nothing. `~` and
  `/etc/hosts` are symlink targets and command text only — nothing is read from
  either. Every payload here carries **no `session_id`**, so the hook writes no
  escalation state and every opaque command is a plain `deny`: the counter, the `ask`
  and the scratch entry point are `hook-escalation.sh`'s. The list of bypasses is
  `hooks/README.md` → What the audit found.
- `hook-escalation.sh` — the other half of the same policy, with `$TMPDIR` redirected to
  its own `mktemp -d` for the whole run, since that is where the hook keeps its state.
  One throwaway root, a scratch directory holding `x.sh`, `x.py` and a symlink out, and
  the same root's basenames repeated in an `elsewhere/` directory. Asserts that two
  opaque commands in a row are denied and the third is `ask`, with a reason saying the
  command is still unreadable after the two rewrites and is the human's call; that a
  readable command between them resets the counter whether it is approved (`ls src`),
  merely refused (`rm -rf src`) or itself denied for one of the three older shapes
  (`git worktree add x`) — "readable", not "approved", is the rule; that two session ids
  count independently and a payload carrying an `agent_id` counts independently of its
  parent session, which is how a delegate is told from the session it shares a
  `session_id` with (Claude Code hooks reference: `agent_id` is present only inside a
  subagent call); that a corrupt, empty or absent state file counts as zero rather than
  crashing or denying, and a payload with no `session_id` is denied every time and never
  escalates; that every state file lands under the redirected `$TMPDIR`, one per counted
  session, and nothing is written into the project root; that `AGENTTOOLING_HEADLESS`
  turns the escalation into silence while the counter still advances, so the same
  session asks the moment it is not headless, and changes nothing below the escalation;
  and that with `AGENTTOOLING_SCRATCH` set, `bash <scratch>/x.sh` and `python3 [-B]
  <scratch>/x.py` are approved although they are outside the project root — **with
  arguments**, each of which must itself be confined (an absolute or relative path inside
  the project root, a file inside the scratch directory, or a bare flag) — while the
  same basename elsewhere, a symlink out of the scratch directory, a missing file, an
  argument outside both roots (`/etc/passwd`, a file beside the scratch directory, a link
  out of it), a flag BEFORE the script (`bash -x`), `sh`, direct execution and every one
  of them
  with the variable unset are not. Existence never decides a relative argument (round 2,
  NOTES ruling 17): `bash <scratch>/x.sh new-output.txt` is approved although the file
  does not exist yet, because it resolves inside the project root, while `… ../x` and
  `… --out=../x` prompt because `../x` resolves outside both roots — whether or not `../x`
  exists. Those three full-hook commands prompt either way, though, because
  `command_allowed`'s `UNANALYSABLE` guard refuses any command holding a literal `..`
  before the scratch logic runs — so this file also loads the hook as a module, the same
  way `policy-table.sh` does, and calls `scratch_argument_allowed` directly on all three
  values, plus a fourth check that creating the file `../x` for real does not flip its
  answer. Those same two commands are **denied** now rather than silent (§7d): a `..`
  component in a path token is a rewritable shape, answered before the scratch logic
  exactly as the `UNANALYSABLE` refusal was. Its §9 is the 2026-09-18 design's half of the
  escalation: a `$NAME`, a `~`, a `..` component, a relative `cd` and a refused brace
  group are each denied on a fresh session, two of them in a row escalate to `ask` on the
  third whatever mix of shapes got there, a command of the **ASK** class (`cat README.md >
  f`, a captured output, which prints nothing — `echo x > f` was this resetter until
  `shell-write-rewrite` made it a REWRITE) resets the counter so the next one is a deny
  again, and a headless runner prints nothing at that escalation while the counter still
  advances. §9h–9i: a file authored through the shell counts the same way — two
  (`echo x > f`, a `cat` heredoc into a file) are denied and a third (`sed -i`) is the
  `ask` with the escalation's own reason. Depends on
  `OPAQUE_REWRITE_ATTEMPTS` being 2 and on
  the state directory being an explicit name under `$TMPDIR`. No model, no network.
- `hook-wiring.sh` — sixteen throwaway repos, one per starting state of
  `.claude/settings.json` (absent, unrelated content, hook only, deny rules only, a
  partial deny list with a repo's own rule in it, the hook and the `Edit` rules but no
  `Bash` rules, everything but the ask rule, complete, a different hook, seven malformed
  shapes), plus three more for the
  two modes. The `Bash` deny list is **imported** from `hooks/policy.py` rather than
  retyped, so a rule added to the table reaches this file with nobody editing it.
  Asserts `hooks/wire-settings.py --check` and `--write` report the
  documented status and exit code and agree; that after a write every deny rule and the
  `hooks/` ask rule are
  present — the ask rule in `permissions.ask` and not in `permissions.deny` — and exactly
  one hook entry names the script; that nothing the repo had is
  removed or changed, including a hand-customized hook path and whatever it had under
  `allow` — which stays exactly as it was in every case, absent included; that a second
  write is `kept` with the file byte-identical and `--check` then says `in-sync`; that
  malformed files (a `permissions.ask` of the wrong type among them) are `INVALID` in
  both modes and untouched; that a file carrying the
  hook and the `Edit` rules and no `Bash` rules reports `UNWIRED` naming the count of
  missing `Bash` rules and no other gap, and that the write then appends exactly those,
  in order; that a file missing only the ask rule names it and nothing else; and that
  `--self` writes `${CLAUDE_PROJECT_DIR}/hooks/allow-repo-commands.sh`
  and the ask rules `Edit(**/hooks/**)`, `Edit(/hooks/**)` and differs from an ordinary
  run in nothing else — the two files
  are compared with those swapped — while `--self --check` over a
  vendored-spelling file reports `UNWIRED`. Its last phase is the **byte-for-byte** half
  (`self/DESIGN-2026-09-17-policy-module.md` §3): a hand-added allow rule, a hook command
  repointed at the vendored path, and a merely REORDERED deny list each fail
  `--self --check` — all three of which the merge check read as complete — the message
  names the line and the entry, `--self --write` restores the generated bytes exactly,
  and this checkout's own committed `.claude/settings.json` passes the same call
  `self/gate.sh` records.
- `policy-table.sh` — the odd one out beside `template-versions.sh`: it stands up no
  sandbox at all, reading the checked-in `hooks/` instead. It imports `hooks/policy.py`,
  the one table the hook's git deny and `wire-settings.py`'s prefix rules are both built
  from, and loads `hooks/allow-repo-commands.sh` as a module by path (it is Python with a
  `.sh` name) so the two halves can be compared directly. Asserts that
  `bash_deny_rules()` renders exactly one rule per MUTATING entry and none for a
  READ_ONLY one, in the documented order (push force ×3, `reset --hard`, the
  always-mutating verbs, worktree ×7, checkout, switch, branch ×6), with nothing
  rendered twice; that every rule is a `Bash(git …:*)` prefix and none is an allow rule;
  that the hook's own `git_mutates` **denies the command each rendered rule names** —
  the twin check, which is what a drift in either direction fails — and does not deny
  the table's read-only spellings (`git worktree list`, `git branch --list <pattern>`, a
  plain `git push`, `git reset <file>`); and that neither script keeps a copy of the
  table, by reading their source for a `BASH_DENY_RULES` tuple and a `GIT_*` frozenset
  that must no longer be there, and by checking the hook's constants are the table's own
  objects. RED until `hooks/policy.py` landed. No model, no network, no filesystem of its
  own.
- `plan-numbering.sh` — two throwaway checkouts under one `mktemp -d`, each a real git repo
  with a bare `origin` beside it carrying the real `feature-start.sh`,
  `plan-runner-roots.sh`, `analysis/{roots,manifest,pricing,transcript,routing}.py` and the
  manifest template: a **`--self`** one (a standalone agentTooling clone, `self/features/`
  at its root) and a **consumer** one (agentTooling vendored one directory down,
  `plans/features/` at the repo's root — the layout `resolve_roots` takes without `--self`).
  `feature-start.sh … --no-gate` runs once per corpus state and the stem is read off the
  review stub it writes; the corpus a start sees is whatever `main` holds, the worktree
  being cut from `origin/<base>`, so each phase rewrites the features root on `main` and
  pushes first. All four phases assert the same number — `01-review-opus` — with an empty
  corpus (N1), with another feature holding `104-build-sonnet.md` (N2), with another
  holding `08-review-opus.md` (N3), and in the consumer layout (N4). The corpus used to
  number every feature's plans as one sequence, and it was retired because two features
  started from the same base both saw the same highest number and both took it (twice on
  2026-09-17) and because a corpus past 99 left stems of two widths that every reader had
  to sort numerically to stay consistent with itself. So this test no longer reads a
  number out of the corpus at all: N2 and N3 exist to show the corpus that would have
  driven the old sequence elsewhere moves nothing. Depends on `feature-start.sh` writing
  the stub number unconditionally in both modes (`../PROJECT_FACTS.md` → "Plan numbers are
  per feature, from 01") and on `$HOME` being redirected, since a start derives its routing
  record from the running session's transcript.
- `sync-check.sh` — copies the real `sync-plans.sh`, `update.sh` and `templates/` (a
  missing `update.sh` is tolerated — RED until plan 77 lands, the `cost-recovery.sh`
  convention) into two throwaway fixtures. Fixture A is a consuming repo at
  `$TMP/consumer` holding copies of the three under `agentTooling/`; it asserts the
  `sync-plans.sh --check` contract: a fresh seed reports the five generated stubs and
  the three repo-owned scripts (`gate.sh`, `pr.sh`, `worktree-setup.sh`) in-sync with
  their `# template-version: <N>` line (2, 4, 1 in that order — `pr.sh` is at 4, the
  version with the `--merge-request` entry point `feature-close.sh` needs) and only
  `PROJECT_FACTS.md` unfilled, exit 1, `needs attention: 1 item(s)`; that the seeded
  `BACKLOG.md` is `in-sync` rather than a second unfilled item — an *empty* backlog is
  the correct steady state for a repo that has closed everything it found, so only its
  absence is an item — and that the generated `plans/README.md` names it, the line
  humanNetworkMap had added by hand and a sync overwrote; filling
  `PROJECT_FACTS.md` brings it to exit 0 `is in sync`; a stale generated stub is
  reported `STALE` with `--check` writing nothing, and the plain sync repairs it; a
  repo-owned script stripped of its `template-version` line is reported `DRIFT` by both
  `--check` and the plain sync (which still keeps the file); a body-only edit below a
  script's `REPO-SPECIFIC` marker is not drift; a deleted repo-owned script is reported
  `missing` and the plain sync recreates it; a `BACKLOG.md` carrying the repo's own
  entry survives a plain sync byte-identical as `kept` and is not drift, while a deleted
  one is `missing` and is re-seeded; and an unknown flag is a usage error, exit
  2. It also reads — never writes — the real checkout, asserting `gate.sh`/`pr.sh`/
  `worktree-setup.sh` carry the same `template-version` in `templates/plans/` and in
  `self/` (8), and that the upstream URL is ONE string across the three places that
  mirror it by hand: `analysis/roots.py`'s `SELF_CORPUS_IDENTITY` (read by importing
  `roots`), `update.sh`'s `DEFAULT_REMOTE` (read by parsing the literal) and the root
  `README.md`'s `git subtree` commands (8b-8d). All three comments say they move
  together and nothing else enforces it; the failure mode is silent and is the one
  `self-corpus-identity` fixed — move the remote in one and not the others and every new
  `--self` ledger claim carries a `repo` matching none of the historical rows, so one
  feature deduplicates against nothing and is counted twice. Fixture B is a subtree cycle: a bare `$TMP/upstream.git`, a `$TMP/work` clone
  that commits the same three copies as `main`, and `$TMP/consumer2`, which
  `git subtree add`s it at `agentTooling/`, seeds `plans/` and fills
  `PROJECT_FACTS.md`; it asserts `update.sh`: a pull with a clean tree brings across a
  new upstream file and re-runs `sync-plans.sh`, exit 0; a dirty tree refuses without
  pulling, naming the untracked file, exit 1; running it from the source checkout
  itself (no prefix to pull into) refuses naming "source checkout", exit 1; and an
  unknown flag is a usage error, exit 2. No model, no network. Depends on `git subtree`
  being available and on the three templates carrying a `template-version` line, which
  plan 77 adds. Fixture C (phases 13-14,
  `self/features/ledger-and-routing/escalations/01-review-opus.md`) asserts the routing
  migration on the write path, which nothing above exercises: `$TMP/consumer` never
  copies `analysis/{routing,pricing,roots,transcript}.py`, so `migrate_routing`
  (`sync-plans.sh:194`, called at `:284`) always returned before `routing.py --migrate`
  ever ran. Its own `$TMP/consumer-routing`, with those four modules copied in, a
  `plans/routing/<id>.json` naming slugs `a` and `b` in `features_started` (built with
  `routing.py`'s own `serialize`, so the byte-equality checks compare against the exact
  bytes the migration would produce) and `plans/features/{a,b}/` present: a plain sync
  leaves both features' `routing.json` byte-equal to the legacy record, removes
  `plans/routing/` entirely, and prints one `routing    moved  <source> -> <target>`
  line per slug (13a-f); a second plain sync over the same corpus prints no `routing`
  line and changes nothing (13g-h); and `--check` over a fresh copy of the same
  fixture (`$TMP/consumer-routing-check`) leaves `plans/routing/<id>.json` in place,
  byte-identical, and writes no `routing.json` (14a-e) — `--check`'s branch never
  calls `migrate_routing`, which sits below it, on the write path only.
- `audit-fixes.sh` — the two items from the 2026-09-16 audit with no home in another file
  (`../DESIGN-2026-09-16-lifecycle-restructure.md` §3.8), each a gap that read as correct
  output. Two sandboxes under one `mktemp -d`, no model and no network. **A.** A throwaway
  `agentTooling` checkout — a real git repo, since `capture_planning.py` resolves its
  session root by walking up to the nearest `.git` — with `analysis/*.py`, one `--self`
  feature whose manifest names the branch a synthesized transcript carries (`session_line`
  from `fixtures/transcripts/build-transcript.sh`, under a redirected `$HOME`), and a
  `planning.json` frozen by `capture_planning.py` with no `report.json` beside it: asserts
  `report.py --self --all` writes that feature's `report.json` **and** `report.md`, prints
  `1 report(s) written`, and then prints a trend table carrying its row; and that a second
  `--all` fills nothing (`0 report(s) written`), leaves the report byte-identical and still
  prints the row. **B.** An ordinary (non-`--self`) sandbox repo with the runners, a stub
  `claude` and a stub `plans/gate.sh`, holding exactly ONE feature — so the build pass
  resolves the slug with none given — whose `session_window.to` precedes its `from`:
  asserts that `run-batch.sh` with no slug argument prints the `check-plans` banner, FAILs
  that feature's window bounds naming the inferred slug, exits non-zero, and stops there,
  with neither the verify nor the review pass run. Depends on `check-plans.sh`'s check 7
  label (`window bounds carry a zone and to follows from`) and on `run-batch.sh` writing
  the inferred slug through the `FEATURE_SLUG_OUT` handshake.
- `template-versions.sh` — the odd one out: it reads the checked-in tree rather than
  standing up a sandbox, and calls no runner. For each of the three repo-owned templates
  (`templates/plans/{gate,pr,worktree-setup}.sh`) it asserts that the
  `# template-version: N` line matches the version recorded in
  `templates/plans/TEMPLATE_VERSIONS` (rows `<file> <version> <sha256>`) and that the
  file's content hash matches the one recorded beside it — sha256 over the file with
  comment-only and blank lines stripped, so a comment edit is free and any change to the
  code is not. A body edited without a bump FAILs, naming the file and saying to bump
  `template-version` and re-record the hash. Blocking in `../gate.sh` because such an edit
  reports `in-sync` in every consuming repo while their seeded copies are stale, which
  `sync-check.sh` assertion 8 cannot see (it only compares `templates/plans/X` and
  `self/X` to each other). Depends on the three templates carrying a `template-version`
  line and on `TEMPLATE_VERSIONS` being kept in step with them by hand.
- `direct-timing.sh` — copies `plan-runner-roots.sh`, the top-level `stamp-timing.sh` and
  `analysis/{pricing,roots,transcript,report}.py` into a throwaway checkout and
  synthesizes a `self/features/` corpus of hand-written manifests, `planning.json` files
  and `timing.jsonl` streams, asserting the direct build's milestone record
  (`../../AGENT_DIRECT.md` → "Checkpoint and resume"): `stamp-timing.sh --self <slug>
  checkpoint status=<status>` appends one line carrying that event, that key and a UTC
  `at` to the second, and appends rather than replaces; it refuses — non-zero, writing
  nothing — a missing slug or event, an unknown feature (naming it), and a detail
  argument that is not `key=value`, because a silently dropped milestone is a hole in the
  only record a direct build leaves between commits; `report.py` derives `tests_s`
  (`planned` → `tests-written`), `direct_build_s` (`tests-written` → `gating`) and
  `gate_s` (`gating` → `committed`) for a `method: direct` feature that has checkpoint
  events and renders them as `↳` sub-rows under "build: implementer" whose minutes sum to
  that row; and neither the keys nor the rows appear for a direct feature without
  checkpoint events or for a `method: plans` feature that has them. A missing
  `stamp-timing.sh` is tolerated rather than fatal, the same convention `cost-recovery.sh`
  uses, so the phases fail loudly instead of the script aborting. No model, no network.
  Depends on `stamp_timing` (`plan-runner-roots.sh`) writing through `jq`, and on
  `report.py`'s `compute_time_rollup` / `render_time_section` reading
  `event: "checkpoint"` with a `status`.
- `stale-failed-sidecars.sh` — copies `analysis/{pricing,roots,transcript,report}.py`
  into a throwaway checkout and synthesizes a `self/features/` corpus of hand-written
  manifests, `planning.json` files, plan `.md` files and `usage.json` sidecars. No
  transcripts, no model, no network: every dollar is a literal in a sidecar, which is
  what `report.py`'s no-recompute contract says it reads. The layout under test is what
  a usage-limit kill plus a manual retry leaves behind (`../../RUNNER.md` → the
  `failed/` paragraph): the runner files a plan's four sidecars as a set, so the killed
  run's `.progress.md` and `.usage.json` sit in `<queue>/failed/` while the retry's
  four sit in `complete/` — two sidecars claiming one stem, and a `failed/` pair with
  no `.md` beside it, which is exactly what crashed the close (now `feature-capture.sh`) on
  vinylCatalogue's `group-commit-all-adjudication`. Every fixture creates `failed/` (or
  `inprogress/`) **before** `complete/`, so a filesystem-ordered walk offers the wrong
  file first — that ordering is the assertion, since the defect was
  `build_usage_index` keeping whichever file `rglob` reached last. Asserts: the stale
  pair does not crash the report and the plan prices at the `complete/` sidecar's
  figure, whole rather than a lower bound; the live sidecar really is `complete/`'s,
  read off the plan-length table, which can only have found the `.md` that exists
  there; the stem is neither missing usage nor an orphan; a `recovered_cost_usd`
  planted in the `failed/` sidecar's `attempts[]` is added to the live figure exactly
  once and reported as recovered dollars, so money recovery writes into a file that
  lost the index is not dropped with it; directory rank breaks a tie when **both**
  candidates have a sibling `.md` (`complete` > `inprogress`, whichever the filesystem
  offers first — the sibling rule cannot decide there, so this is the only assertion
  that pins the rank); and a missing sibling `.md` is a warning naming the path rather
  than a crash, the plan dropped from the plan-length table but still priced. Three later phases are
  the 2026-09-06 backlog items: a prior attempt with **neither** a cost nor a recovered
  figure now marks the total a lower bound and names its `session_id` under
  `cost.unrecoverable_attempts[]`, exactly as the same shape on the live sidecar already
  did — which REVERSES what assertion 2c asserted before, since ruling 4 deliberately
  let such a prior read as free and widening it changes what `total_is_partial` means
  for every feature in both corpora; an attempt reachable through both sidecars (a
  hand-copied file: `write_usage_sidecar` merges by `session_id` into the file at the
  plan's current path) contributes its dollars once and is named once; and
  `cost.multi_sidecar_stems[]` plus one line under the Cost table report a stem with
  more than one sidecar, absent when every stem has exactly one. The recovered-twin
  phase is the contrast that keeps the first of those precise: a prior that WAS
  recovered leaves the total whole. Three further phases are that batch's review
  escalation, closed by its rework: WHICH copy of a deduplicated attempt the dollars
  come from. A live copy null on both figures beside a prior carrying
  `recovered_cost_usd` contributes that figure once, leaves the total whole and names
  the session in neither `cost.unrecoverable_attempts[]` nor `cost.unpriced_plans[]` —
  asserted both where the shared attempt is the plan's only one (the whole-plan unpriced
  path) and where the live sidecar prices an attempt of its own beside it (the
  per-attempt path the escalation described); the same fixture with the prior's figure
  removed is still unpriced, so a merge rule cannot credit a copy that carries nothing;
  and where both copies carry a figure and disagree, the LIVE one is counted, once. The
  last two are green before the rework as well as after — they are what keeps the first
  from being satisfiable by a rule that simply prefers the prior. RED until
  the deterministic index landed — the pre-fix run dies inside
  `compute_plan_length_vs_loc` with a `FileNotFoundError` for the `failed/` `.md` the
  retry moved away. A missing `analysis/` script is tolerated rather than fatal, the
  `cost-recovery.sh` convention. Depends on `report.py`'s `build_usage_index` returning
  a live path plus prior attempts, on `prior_attempt_cost` returning the merged
  `attempts` list `compute_cost_rollup` classifies and on its `ATTEMPT_FIGURE_FIELDS`
  precedence, and on the sibling-`.md`
  readers (`compute_plan_length_vs_loc`, `compute_plan_drift`) warning instead of
  raising — none of which is visible from an import line.
- `stream-capture.sh` — copies the runner scripts into a `mktemp -d` checkout with a stub
  `claude` that **ignores SIGPIPE** and emits an init event, 1500 `assistant`/`tool_use`
  pairs and a priced `result` event (ending chosen by `CLAUDE_STUB_MODE`:
  `normal` | `no-result` | `usage-limit`), and drives it through a real `run-plans.sh
  --self`. The stub's SIGPIPE disposition is the fixture: one that dies with the pipeline
  cannot tell the fix from the defect it was written against — a `tee` in the *middle* of
  the capture pipeline, whose last stage wrote to the caller's stdout, so a consumer that
  stopped reading truncated the record while `claude` ran on to a clean exit (nine merged
  reviews filed as successes with a 689-byte `.stream.jsonl`, a 0-byte `.progress.md` and
  `total_cost_usd: null`). Asserts, for a healthy consumer and again for one that exits
  after two lines — before `claude` is started — and again for one that exits mid-stream:
  the plan is filed to `complete/`, the runner exits 0, `.stream.jsonl` holds all 3002
  lines and ends with the `result` event, the sidecar is priced, and `.progress.md`
  carries one `edit: <path>` line per mutating `tool_use`. Also: a stub emitting no
  `result` event and exiting 0 is still filed by its exit code but warns, naming the plan
  and the stream file, which survives; and the usage-limit routing is unchanged — plan
  left in `inprogress/`, exit 1, reason naming the limit — with the consumer present and
  with it gone. The pre-fix run failed 14 of 31: phase 3 captured 94 of 3002 stream lines
  and 39 of 1500 progress lines, ending on an `assistant` event.
  Four later phases came from the review. **6** feeds in a stream carrying one non-JSON
  line — `claude`'s stderr is merged into it, so a runtime warning lands there — and
  pins that the sidecar and the truncation warning agree about it (priced,
  `result_event: "seen"`, no warning); they used to disagree, one `jq` tolerating bad
  lines and the other not. **7** points `$TMPDIR` at a directory that does not exist so
  `mktemp -d` fails, and asserts the plan is filed to `failed/` naming that directory
  rather than the runner hanging on a marker it can never write — the assertion is the
  watchdog, so a hang is reported instead of stalling the gate. **8** sends SIGTERM to
  the runner alone and **9** to its whole process group (`set -m` gives it one of its
  own), asserting for both that the plan stays in `inprogress/`, the runner exits 130,
  the stream holds what was captured, no `claude`/follower/`tail` is left behind, and the
  capture directory is gone — the orphan check is deliberately budgeted well under the
  `slow` stub's remaining runtime, or an unkilled `claude` finishing by itself would
  satisfy it. Verified by mutation: dropping `stop_capture`'s `kill` fails 8f, dropping
  its `rm -rf` fails 9g, and dropping `follow_stream`'s pid stop condition fails 8f
  and 9f. **10** is the executor's own environment, which nothing else can see: the stub
  records `AGENTTOOLING_HEADLESS`, `AGENTTOOLING_SCRATCH`, its last argument (the
  prompt, to a file of its own — it is many lines) and its whole argv (`.argv`, one word
  per line), and the phase asserts the runner exported both, that the scratch directory is
  under the redirected `$TMPDIR` and exists while the executor runs, that the prompt names
  it alongside the plan's own brief, that `--add-dir` carries that same directory — the
  environment says where it is, only the flag says the executor may write to it, since
  `acceptEdits` reaches the working directory alone — and that it is gone when the pass
  ends. `hooks/allow-repo-commands.sh` is the only reader
  of either variable, so without this phase the two ends of that contract are asserted
  nowhere together. No model, no network.
  Depends on `plan-runner-lib.sh`'s `run_plan` capturing the stream where nothing
  downstream can truncate it, on `finalize_plan` warning on `rc == 0` with no `result`
  event, on `run_all` leaving the runner alive when its own stdout is closed, and — for
  phases 7 to 9 — on `mktemp -d` being given an explicit template under `$TMPDIR` (a bare
  `mktemp -d` ignores it on macOS, which would make every capture-directory assertion
  here pass vacuously). Phase 10 also depends on the executor scratch directory living
  INSIDE `CAPTURE_TMPDIR`: `capture_dirs_left` counts directories at depth 1 under
  `$TMPDIR` and 8b/9b assert exactly one, so a second `mktemp -d` beside it would fail
  those instead. None of this is visible from an import line.
- `usage-limit-kill.sh` — the runner scripts in a `mktemp -d` checkout with a stub
  `claude` that `cat`s a canned `.stream.jsonl` (`CLAUDE_STUB_STREAM`) and exits with
  `CLAUDE_STUB_RC`, driven through the real `run-plans.sh --self`. The canned stream is
  the whole fixture, which is why this is not a mode of `stream-capture.sh`: that stub
  emits 3002 lines to test capture throughput and every phase here is three events.
  Asserts the hard-killed-session half of `stream_shows_usage_limit`: a stream with no
  `result` event whose last parsed event is an `error` naming HTTP 429 — or naming a
  limit in words — leaves the plan in `auto/inprogress/` and stops the runner with a
  reason naming the limit, while the boundary cases keep routing exactly as before. No
  result and no error event is still an ordinary failure to `auto/failed/`; so is an
  `error` event naming no limit; so is a 429 error followed by more events, since the
  signal is how the stream ENDED and not a scan of its body. A trailing non-JSON line —
  `claude`'s merged stderr — does not hide the error event, since both readers parse
  with `STREAM_EVENTS_JQ`. A stream that DID reach a result event is judged by that
  event alone: a success result after a 429 error is filed complete, and assistant text
  mentioning a rate limit is still not a limit. The original signal is asserted last,
  unchanged. No model, no network. Depends on `plan-runner-lib.sh`'s
  `STREAM_HARD_KILL_LIMIT_JQ` and the shared `STREAM_LIMIT_TEXT_RE`, and on
  `finalize_plan`'s `rc == 2` branch leaving the plan queued.
- `batch-sigpipe.sh` — `level-sentinel.sh`'s scaffolding (the runner scripts, a stub
  `claude` emitting one priced `result` event, a stub green `self/gate.sh`), with
  `run-batch.sh --self` driven into `head -2` so the pipe closes while the batch is
  still inside its build pass. `check-plans.sh` is deliberately NOT copied in, so that
  script's `-x` guard skips the lint and the batch's first stdout line is always its own
  `BATCH 1/3` banner — copying it in would move the "two lines" boundary. Asserts that
  the batch survives its own closed stdout: it exits with its own code rather than 141,
  the build AND verify passes both run and file their plans with sidecars (the verify
  pass is only reachable past the gate banner that used to kill it), and a failing build
  under the same closed stdout exits 1 rather than 141. A healthy-consumer control runs
  first, so a phase-2 failure can only be the closed stdout, and it also pins that the
  batch really does print more than two lines. `${PIPESTATUS[0]}` is read inside the
  subshell that ran the pipeline; the caller's `$?` is the substitution's. Depends on
  `run-batch.sh` installing `trap 'exec >/dev/null; printf "\n"' PIPE` above its first
  write — a handler, never `trap '' PIPE`, for the reason `../PROJECT_FACTS.md` records.
- `report-footnotes.sh` — `stale-failed-sidecars.sh`'s report-only scaffolding
  (`analysis/{pricing,roots,transcript,report}.py` in a throwaway checkout, a
  synthesized `self/features/` corpus of hand-written manifests, `planning.json` files,
  plan `.md` files and sidecars; no transcripts, every dollar a literal). Its own file
  rather than a phase of that one because the subject differs: that file is about which
  sidecar the index picks, this one about what the two tables say when a figure is
  missing. Asserts the `†` mark and its footnote on both: a review plan that RAN and
  carries no `total_cost_usd` makes the Cost table's review cell something other than a
  bare `$0.0000`, with a footnote directly under the table naming the bucket, the stem,
  the reason and what recovery made of it, and with the separate **Unpriced plans**
  paragraph gone rather than duplicated — while the build and verify rows, genuinely
  empty, stay unmarked, so the mark means "unpriced" and not "zero". A fully priced
  feature carries no mark and no footnote anywhere. A review plan with a null
  `duration_ms` gets the same treatment in the Time table, and
  `time.missing_duration_plans[]` carries the `{plan, queue, reason}` shape
  `cost.unpriced_plans[]` does — both reason branches pinned by exact text (`no result
  event` from `result_event: "missing"`, `no duration reported, cause not recorded` from
  a sidecar with no such field, the shape every sidecar committed before the field
  existed still has), so no single return value satisfies both. Depends on `report.py`'s
  `MISSING_FIGURE_MARK`, `group_by_bucket`/`bucket_mark`/`bucket_footnote_lines`,
  `missing_duration_reason`, and `compute_time_rollup` returning dicts rather than
  stems — none of which is visible from an import line.
  Two later phases pin the Time table's **second** mark
  (`self/features/recovered-duration-lower-bound/README.md`, item 1): a plan whose
  `duration_ms` is null but whose attempt carries a `recovered_duration_s` contributes
  that span to its bucket, is listed under `time.recovered_duration_plans[]` in the
  `{plan, queue, reason}` shape plus `recovered_s`, is **not** also listed under
  `missing_duration_plans[]`, and its row reads `7.5 ‡` rather than `0.0 †` — two marks
  because `†` says the bucket has no figure and `‡` says it has one and it is a lower
  bound — with a footnote naming the plan, the seconds and the transcript span, while
  `total_is_partial` and the lower-bound line both stay. The phase beside it re-reads the
  transcript-is-gone fixture and pins that nothing about it changed: still `†`, still a
  bare `0.0`, no `‡` anywhere. Both marks are asserted by glyph, so changing either is a
  visible change to the tests.
  **Phases 8–10 pin the per-attempt walk**
  (`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §1), with a `resumed_usage_json`
  fixture whose `attempts[]` holds one entry per `claude -p` run: a plan with one measured
  attempt and one recovered one reports the SUM (930s, `15.5 ‡`), is in
  `recovered_duration_plans[]` with `measured_attempts: 1` and `recovered_attempts: 1`,
  is not in `missing_duration_plans[]`, and its footnote says `1 of 2 attempts recovered`;
  a plan with an attempt carrying neither figure is in `missing_duration_plans[]` with
  `unmeasured_attempts: [2]` and `attempt_count: 2`, marks `†`, footnotes `attempt 2 of 2
  unmeasured`, and **still contributes the attempt that was measured** (480s); and a plan
  whose only duration lives in a PRIOR sidecar — the `failed/` pair a killed attempt left
  behind — is measured from it and is in neither list, and `--rounds-md` (the PR body's
  copy of the Rounds table, built by `run_rounds_md` and not by `run_single_feature`)
  prints that plan's review minutes as `report.md`'s Rounds row does (10e–10f; it needs
  `run_rounds_md` to hand `compute_time_rollup` the same `usage_index` the report's does).
  Phases 4b, 4f and 6b assert their
  entries by exact equality, so the added fields are a deliberate change to them.
  **Phase 11 pins that a read does not rewrite** (§4): two consecutive `report.py` runs
  over an unchanged corpus leave `report.md` and `report.json` byte-identical (`cmp`),
  `--all` leaves an existing record alone, a feature with no record still gets one, and a
  run after `planning.json` changed rewrites both. Depends on `report.py`'s
  `attempt_copies`/`plan_duration` and on `write_record`/`GENERATED_AT_MASK_RE` — none of
  which is visible from an import line.
- `open-session.sh` — the session opener's **body**, which no test ran before: both
  `self/open-session.sh` and `templates/plans/open-session.sh`, with `osascript` and
  `claude` stubbed in a throwaway `PATH` directory, run against a worktree path holding a
  space, a `'`, a `"` and a `\`. The recorded `do script` argument is AppleScript-
  unescaped the way Terminal unescapes a string literal, then run by a shell whose
  `claude` prints `$PWD` — which must be that path intact
  (`self/DESIGN-2026-09-18-minutes-slug-and-quoting.md` §3). Also pins both copies at
  `template-version: 3` and that the two compose the same command, since they are
  hand-kept in step. Nothing is opened and nothing is billed: no Terminal, no model, no
  network. `feature-lifecycle.sh` S5c–S5f read the same two files as **text** (the two
  escaping layers are present, the bare single-quoted path is gone, neither spells a
  chained `cd` as a command of its own); this file runs them, which is the only way a
  quoting bug in a path nobody has yet is caught before it bills a session to the wrong
  branch. Depends on `shell_single_quote` and `applescript_escape` by name — the text
  reads in `feature-lifecycle.sh` grep for exactly those call sites.
- `report-rounds.sh` — `report-footnotes.sh`'s scaffolding with one input added: a
  hand-written `timing.jsonl`. Same throwaway checkout
  (`analysis/{pricing,roots,transcript,routing,report}.py`), same synthesized
  `self/features/` corpus of manifests, `planning.json` files, plan `.md` files and
  sidecars where every dollar and every minute is a literal, and no transcript, model or
  network. Asserts the Rounds table
  (`../DESIGN-2026-09-17-close-and-review-rounds.md` §4, and §9's RD and no-`round`
  fallback): a feature whose stamps carry `round=1` then `round=2`, escalated then
  clean, yields two `rounds[]` rows in that order with each round's build/verify/review
  dollars and minutes partitioned by the round its plans' stamps carry, the review
  plan's stem, its verdict, and `escalations_file` set on the escalated round **only** —
  and the rows' dollars sum to `cost.build + cost.verify + cost.review`, so the Rounds
  and Cost tables cannot drift apart. Each fixture's figures are distinct powers of two,
  so no assertion can pass by reading the wrong plan and no sum is reachable two ways.
  The other phases pin the cases that are easy to get wrong: a `timing.jsonl` with no
  `round` key anywhere renders as exactly **one** round, round 1, unmarked (every record
  committed before this feature); `--rounds-md` prints the heading, the header and the
  rows and **nothing else** — no Cost, Time or Churn section — exits 0 and leaves
  `report.json` and `report.md` byte-identical (`cmp`), which is what `feature-close.sh`
  calls to compose the PR body; the same flag on a feature with **no `planning.json` at
  all**, the state every feature is in when its first PR is opened, still prints the
  table and marks the unfrozen build figure instead of printing a bare zero; and a
  review plan whose `plan_end` carries no `verdict` key leaves `verdict` null while
  still naming its plan, because "unknown" must never render as `clean`. Its last phase is
  the contrast to that `--rounds-md` case: the **plain** `report.py --self <slug>` over a
  feature with a manifest and no `planning.json` — the state before the close captures —
  exits non-zero with one line naming `planning.json` and `feature-close.sh`, no
  `Traceback` in stderr and no `report.json` written, where the PR-body flag beside it
  tolerates the same absence and still prints its table. Depends on
  `report.py`'s `compute_rounds`, `render_rounds_section`, `ROUND_KEY`/`VERDICT_KEY` and
  the `--rounds-md` flag, and on the stamp contract `plan-runner-roots.sh`'s
  `stamp_timing` and `run-review.sh` write (`round` on every pass-stamped event,
  `verdict` and `head` on the review plan's `plan_end`, every detail value a string) —
  none of which is visible from an import line. The table's heading, header row, the `†`
  mark and the `—` absent cell are asserted by value, so a change to any of them is a
  visible change here.
