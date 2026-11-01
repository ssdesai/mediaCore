# Lifecycle restructure: one session per feature, capture on the branch, no manual close — design (2026-09-16)

_Written in the router session `8a695645-c764-471b-98f3-751e6c484adf` on 2026-09-16, from an
audit of the feature flow and cost tracking and the discussion that followed. Everything
marked **measured** was read off this machine's corpus that day; everything marked
**decided** is a decision the user confirmed in that discussion; everything marked
**open** is theirs to make. This file is the input for the features in §6, in the way
`TRIAGE-2026-09-03-feature-execution-procedure.md` was for `feature-execution-procedure`._

## 0. State when this was written

- `permissions-policy-inherit` is built and gated green on its branch (worktree
  `/Users/sahildesai/dev/agentTooling/.worktrees/permissions-policy-inherit`, commits
  `e855402` start, `6846122` review brief, `6b4d76f` acceptance tests, `66c9c42` build,
  `cd7320a` delegate pin). Not yet reviewed, not pushed, no PR. §7 has its remaining steps.
- The primary checkout is on `main` at `627053b`, clean.
- This router session is pinned in `permissions-policy-inherit`'s `sessions`, so under the
  current rule the whole audit is billed to that feature. That is the worked example of the
  problem §2 fixes. Leave it; the record for that feature will carry the boundary warning.

## 1. The audit: how the flow gates and records cost today, and where it leaks

| Step | Who runs it | Cost gate | Recorded |
|---|---|---|---|
| 1 Route | human or router session | the ~1000-line heuristic (prose) | `method` |
| 2 Start | human, `feature-start.sh` | refuses a red base gate | fence: branch, base, `from`, pinned session |
| 3 Brief | human/coordinator | `check-plans.sh` (14 lints), `@@TODO@@` refusal | nothing |
| 4 Build (plans) | `run-batch.sh` | build pass **uncapped**; verify $3, level-verify $6, escalation $8 | `usage.json` per plan, `timing.jsonl` |
| 4 Build (direct) | one opus delegate | **none** | nothing until close |
| 5 Review | `run-review.sh` | $7 cap (`RUNNER.md` still says $5 — doc drift) | `usage.json`, `pr_opened` stamp |
| 6 Close | human, `feature-close.sh`, post-merge, from primary on `main` | refuses unpinned delegates | `planning.json`, `report.*`, ledger, `to`; commits and **pushes to `main`** |
| 7 Sweep | human, weekly by convention | none | backfill, recover, annotate |

Leaks, all **measured**:

- Direct features bill 85–95% of spend to the build bucket (the coordinator session plus
  its delegate); nothing caps or estimates either.
- A pinned single-claimant session is priced over its whole transcript, window ignored
  (`capture_planning.py` `boundary_warning` docstring; deliberate). `hook-cd-deny-braces`
  carries $1.67 past its `to`; `feature-lifecycle` bills one 12.4-hour session in full;
  `claim-window-precision` shows $17.07 unclaimed on a shared session.
- Session `ed088063` is claimed by 11 features across 4 repos, each in full (memory note
  `ed088063-repair-pending`); repair blocked on vinylCatalogue's dirty primary.
- `report.py --all` renders only features with a `report.json`: `killed-attempt-cost-recovery`,
  `recovered-totals-stay-honest`, `review-pass-and-cost-attribution` have a `planning.json`
  and no report, so they are absent from every trend table. The sweep regenerates reports
  only for files that changed in `git status`.
- `recovered-totals-stay-honest` has `to` (16:46:31) before `from` (17:00:00); total $0;
  `check-plans.sh` does not check window ordering or zone.
- `run-batch.sh` runs `check-plans.sh` only when the slug is explicit
  (`if [[ -n "$FEATURE_SLUG" && -x … ]]`); an inferred slug skips the lint.
- Unclaimed in this repo: sessions `fbe0d9c3` (main, 245 min, $6.24), `0b3bf126`
  (`capturePopulates`, $6.23), `e8a6b6df` (`testing-restruct`, $0.17) — dead branches and a
  routing session, $14.66 with this session's $2.02. Cross-repo: five survey/verify
  delegates launched from `~/dev` (no repo), $8.67, claimable only by pin and nothing to pin
  them to. vinylCatalogue `tracklist-natural-order` delegates $22.33 in flight (close will
  catch them; the refusal works).
- The sweep is unscheduled and unrecorded; oldest surviving transcript here is 2026-08-20,
  so retention is roughly four weeks.
- `feature-start.sh`'s `--self` numbering matched two-digit stems only and handed this
  feature `100` instead of `105` (fixed in `permissions-policy-inherit`).

## 2. The root cause and the rule — decided

The pin is the root cause. `feature-start.sh` pins the session that ran it, so one long
session that starts several features is claimed by all of them, and every piece of the
shared-session machinery (ledger, split, `head_bound`, in-flight co-claimant backlog entry)
exists to apportion it. Stop pinning and none of it is exercised for new features.

**The rule.** One coordinator session per feature, launched inside the worktree
(LIFECYCLE rule 1 already says a session is billed to the branch of the directory it was
launched in). Its delegates inherit the branch. The session that runs `feature-start.sh` is
a **router**, never pinned; its spend is **routing overhead**, a category of its own
(§3.4), reported per repo, never attributed to or split across features. A feature can no
longer be coordinated from a session that also coordinates another — that constraint is
the point. The session's lifetime matches the feature's: the worktree goes at merge, the
session with it.

## 3. The design — decided unless marked open

### 3.1 `feature-start.sh`

- **No pin by default**; `--pin` keeps the old behaviour for the rare case.
- **`--open`** launches the coordinator in the worktree with `claude` running, through a
  repo-owned hook seeded like `worktree-setup.sh` (`templates/plans/open-session.sh`, and
  `self/open-session.sh`), default implementation `osascript` → Terminal.app `do script
  "cd <worktree> && claude"` (a human-terminal hint, not a Bash tool call, so the hook's cd
  deny never sees it). The printed "Next" collapses from two choices to one.
- **Prunes** merged features before creating the new one: every worktree whose branch is
  an ancestor of `origin/main` → `git worktree remove`, `git branch -d`. This is the whole
  of post-merge teardown. Nothing is committed or pushed by the prune.
- **Writes the routing record** for its own session (§3.4) into the feature directory's
  corpus (`plans/routing/<session-id>.json`, `self/routing/` under `--self`) and commits it
  in the `S: start` commit on the branch. The link router → feature is thereby in git
  before any transcript can expire.
- Keeps: slug pattern, base gate green, `--base`, `--no-gate`, `S: start` commit on the
  branch, `.worktrees/` in `info/exclude`. Nothing pushes.

### 3.2 `feature-capture.sh` (renamed from `feature-close.sh`)

> **Superseded 2026-09-17** by `DESIGN-2026-09-17-close-and-review-rounds.md` in one
> respect only: "there is no close" is no longer true. `feature-close.sh` is a real script
> again — still in the worktree, on the branch, before the merge — and it is what runs
> `pr.sh`, this capture and the merge request, in that order, and only for a tree a clean
> review round judged. Everything below about the capture itself still holds; what changed
> is who calls it (the close, not `run-review.sh`) and that a rework after an escalated
> review is a new round rather than a by-hand capture.

Runs **in the worktree, on the branch, before the merge**. The merge is the freeze.

1. Stamp `to` from evidence (`capture_planning.py --last-branch-instant`). Pre-merge it may
   move **either way** (a re-run after more work moves it later); the tighten-only rule
   applies only post-merge via `--recapture`.
2. `recover_attempts.py --for <slug>`.
3. Capture, report.
4. Refresh the routing record of the router that started this feature — found by scanning
   `plans/routing/*.json` for this slug (no fence field; §3.4).
5. Commit the cost records on the branch (`COST_FILES` + usage sidecars + routing record)
   and push the branch. The PR carries them; the human reads the report in the PR.

Triggered by `run-review.sh` after `pr.sh`, in this order: `pr.sh` → `pr_opened` stamp →
`pass_end` stamp → capture → commit → push, so the trailing stamps ride the capture commit
and the carry-home hack goes. Re-runnable by hand from the worktree after a rework that
skipped a full review. Scope extension before merge is just more work on the branch: a
second review brief queued in `review/incomplete/`, its stem added to `plans`,
`run-review.sh` again (`pr.sh` already handles an existing PR: pushes and reports it open),
capture again replaces the provisional record.

Removed from the old close: the primary-clean-and-on-`main` refusal, `pull main`, the push
to `main`, the "worktree's copy is the wrong copy" refusal (under the rule the worktree is
exactly where the feature's sessions and delegates are filed — lift the matching guard in
`capture_planning.py` too), the timing carry-home, and the unpinned-delegate **refusal**,
which becomes a warning for a delegate whose brief names this slug and that neither route
claims. `--recapture` stays as the repair path for features closed under the old rule:
tighten-only, writes locally, no push, the human opens a PR for the repair.

Accepted consequence: the frozen record covers work up to the last capture; the coordinator's
reading of the PR and the merge click are not in it.

### 3.3 `pr.sh` (repo-owned template + `self/pr.sh`)

- Either defer its commit to the capture (one commit after review) or accept two. Template
  change plus a hand-merge in each consumer; bump `template-version`.
- **Open:** `PR_AUTO_MERGE=1` opt-in → `gh pr merge --auto --squash --delete-branch` after
  a clean review. Recommended **off** by default everywhere, and off for agentTooling
  regardless (its changes ship to every consumer). With it on, the tail from verdict to
  costed merge is unattended.

### 3.4 Routing overhead

- **Record:** `plans/routing/<session-id>.json` — `{ session_id, launched_in, git_branch,
  model, started_at, ended_at, duration_s, cost_usd, features_started[{slug, at}],
  captured_at }`. `features_started` is read from the transcript's `feature-start.sh
  <slug>` tool calls. **No `started_by` in the fence** — decided: the router owns the list;
  a feature report that wants "routed by" scans the routing files for its slug. One copy
  cannot disagree with itself.
- **Router detection:** a session launched in the primary checkout, on `main`, whose
  transcript contains a tool call that **runs** `feature-start.sh` — the script at command
  position, the first word of a simple command (start of line, or after `&&`, `||`, `;`,
  `|`, `&`), optionally preceded by `bash`. Naming the file is not running it: a session
  that greps or diffs `feature-start.sh` is not a router. Everything else on `main` stays
  in the unclaimed listing (abandoned branches, delegates from outside any repo).
- **When written:** provisional-and-replaced. `feature-start.sh` refreshes its own router's
  record; `feature-capture.sh` refreshes the record of the router named for its slug. Content
  is derived deterministically from the transcript, so parallel branches produce identical
  bytes unless the router grew between them; **a conflict resolves by taking the side with
  the later `captured_at`** — a router only grows, so that side's `features_started` is a
  superset. (Amended 2026-09-16 by the `start-procedure-and-routing` review, which
  replaced "taking either side": the older side is missing the newer feature's slug, which
  costs that feature its "routed by" line and its Routing-table row, and no later refresh
  restores it unless the same router starts something else.) The layout stays one file per
  session. Final version = last refresh before the transcript aged out.
  Abandoned features take their copy with them; the next feature from the same router
  writes it again.
- **Report:** `report.py --all` gains a Routing table — per session: cost, minutes,
  features started with their frozen totals side by side; per period: routing spend as a
  fraction of feature spend. A feature's own report shows "routed by `<id>`, alongside
  `<slugs>`" as a sum, never a split.
- **Unclaimed listing** excludes router sessions (they have a category) and keeps the rest.

### 3.5 `sweep.sh` retired

Every step is either historical or moves into capture: backfill / corpus recover /
capture `--all` served features predating runner-side usage, recover-at-close and close
itself (all 21 self features have a `planning.json`); the rates warning is already in
capture's `warnings[]`; the per-feature report is capture's; `--all` is a disk-only read and
runs at capture; frozen-record annotation (`also_claimed_by`) runs at capture scoped to the
repo (ledger read, no transcript opened) and converges cross-repo on the other repo's next
capture. Residue — the corpus-wide unclaimed listing and the rates check — is printed by
capture; an optional launchd tick may print it weekly. `sweep.sh` and `--all --recapture`
et al. move to a "repair tools" section of `analysis/README.md`; the "How to run them"
cadence prose is rewritten.

The shared-session machinery (ledger, split, `--recapture`, `--carry-lost`) is **kept** for
the existing corpus and not exercised by features started under the rule. The
`ed088063` repair is unchanged and still pending.

### 3.6 Docs

- `LIFECYCLE.md`: six steps — route, start, brief, build, review + PR (which captures),
  merge. Rule 1 unchanged; rule 2 unchanged (the hook now enforces it); rule 3: the fence is
  the scripts', `to` is provisional until merge. Retire "after every session that cost it
  has ended". Step 6 "Close" becomes "Merge", performed on the forge.
- Root `README.md` rows (`feature-start.sh`, `feature-capture.sh`, `sweep.sh` → repair,
  `analysis/`), `analysis/README.md` ("Where to run them": the worktree copy is now the
  right copy; "How to run them" → per-feature capture, repair tools), `RUNNER.md` (review
  cap $5 → $7), `AGENT_DIRECT.md` (close step → merge; "Checklist before spawning"),
  `ORCHESTRATION.md` → Rules (pin advice → launch in the worktree; router definition),
  `templates/plans/features/TEMPLATE.md` (the `sessions`/`subagents` prose: pins are the
  exception), `self/PROJECT_FACTS.md` → Commands, `self/README.md`.

### 3.7 Analyzable commands — decided, lands with the hook

Generalisation of the `cd` rule: what blocks the reads fence and the hook is anything
decided at run time, not several commands on a line.

- **Deny** (hook, same treatment as the chained `cd`): an assignment at command position
  (`NAME=value` as its own subcommand) followed by `$NAME` in the same command. Always
  replaceable by the literal; reason says "inline the path". Add a `BASH_DENY_RULES` twin
  only if a prefix rule can express it (it cannot; hook-only).
- **Prose** (`CONVENTIONS.md` § Shell commands, one paragraph): every path a literal, every
  program named, nothing decided at run time — no variables in paths, no `$(…)` in paths,
  no heredocs into interpreters, one line per call. Heredocs stay prose, not deny: the fix
  is a rewrite (a `grep -o` with context, or Write a script to the scratchpad and run it),
  not a substitution.
- **Measured trigger:** a vinylCatalogue session's `R=…; sed -n … $R/…; python3 - <<'EOF'`
  was flagged as unanalysable; as five absolute-path `sed` calls and one `grep -o` it would
  have been approved with zero prompts. This router session also used chained `cd`, `for`
  loops and Python heredocs repeatedly in a checkout where nothing enforced the rule —
  the case for the deny over the prose.

### 3.8 Small audit items to fold in

- `report.py --all` renders any feature with a `planning.json` and no `report.json`, and
  says how many it filled in.
- `check-plans.sh`: `to` is null or after `from`, both with a zone.
- `run-batch.sh` runs `check-plans.sh` on an inferred slug too, once the build pass has
  resolved it.
- `RUNNER.md` review cap `$5.00` → `$7.00` (two places, lines ~102 and ~362).
- **Open:** a per-feature budget in the fence, set at start from the route, printed against
  actual at capture, warned on when exceeded. The only gate that would ever touch the
  build bucket. Changes the fence; the user's call.
- **Open:** `git stash list` is denied by the new hook (implementer's ruling: one keystroke
  from `git stash`); relax to allow `stash list`/`stash show` if the false deny bites.
- Delete by hand (per-machine, cannot be fixed from here): vinylCatalogue
  `.claude/settings.local.json` `Bash(npx playwright *)`, `Bash(gh pr *)`; humanNetworkMap
  `Bash(npm run *)`. Both reopen shapes the hook's audit closed.
- Backlog (filed by the implementer): the vendored `agentTooling/.claude/settings.json`
  ships with the subtree and its hook path does not resolve in a consumer; harmless today
  because nothing reads a nested settings file.

## 4. Tests (all `self/tests/*.sh`, bash 3.2, no runner)

- `feature-lifecycle.sh` rewritten for the new flow against a bare remote: start writes no
  pin and commits a routing record in `S: start`; capture on the branch commits cost records
  and pushes the branch, not `main`; a second capture replaces the first (later `to`);
  merge then start-of-next prunes the worktree and local branch; `--recapture` post-merge
  refuses to widen and pushes nothing.
- Routing record derivation from a fixture transcript with two `feature-start.sh` tool
  calls; router detection excludes a `main` session with no such call; unclaimed listing
  excludes routers.
- Capture from the worktree copy selects sessions filed under the worktree's transcript
  dir and their delegates (fixture dirs under a fake `~/.claude/projects`), and none from
  the primary's dir.
- Hook: `X=/p; cat $X/f` DENY with the inline reason; `X=/p` alone, `echo '$X'`, `$(…)`
  without a prior assignment NOT_DENIED.
- `check-plans.sh` window-order and zone lints; `report.py --all` fills missing reports.

## 5. Facts pinned

- Primary: `/Users/sahildesai/dev/agentTooling`, standalone (not vendored), `REL_AT` empty,
  scripts at the root, corpus `self/features/`, `--self` always first argument.
- Worktrees: `<primary>/.worktrees/<slug>`; transcripts for a session launched there are
  under `~/.claude/projects/-Users-sahildesai-dev-agentTooling--worktrees-<slug>/`.
- Rule 1 mechanics: `gitBranch` in the transcript is the branch of the launch directory;
  a `cd` changes nothing; a delegate is filed under its parent's cwd and inherits its branch.
- `capture_planning.py` refuses from a worktree today (git-dir ≠ common-dir guard, triage
  fix 2a); `session_root` is the nearest `.git` ancestor; `find_transcript_dirs` matches by
  substring of the repo dir name.
- `manifest.py` subcommands: `init`, `get`, `set-window-to [--tighten]`, `set-plans`,
  `claimed`. No pin command — pinning `subagents` today is a hand edit of the fence array.
- `pr.sh` template handles an existing PR (`gh pr view` → "already open") and pushes the
  branch with `-u`.
- `run-review.sh` stamps `pr_opened` after `pr.sh` returns; `pass_end` comes from the EXIT
  trap; both currently land only in the worktree.
- Rates verified 2026-09-04, threshold 30 days → stale on 2026-10-04.
- Consuming repos and their state (2026-09-16): vinylCatalogue (primary dirty on
  `merge-queue-settle-semantics`, blocks `update.sh`), humanNetworkMap, musicMap,
  mediaCore — all four carry the identical hook entry and nine Edit deny rules.

## 6. Sizing and order — recommended

Three direct features, in this order, each under a thousand lines; `--method direct`,
review brief written first from this file. Start each **from a fresh router session or
this one**, but coordinate each from a session launched in its own worktree — start
practising the rule before the script enforces it.

1. **`start-procedure-and-routing`** — §3.1 (no pin, `--open`, prune, routing record),
   §3.4 (record, detection, report table, unclaimed exclusion), §3.7 (hook deny +
   conventions paragraph), `feature-start.sh` docs. Does not touch close.
2. **`capture-on-branch`** — §3.2 (rename, worktree-run, lift guards, order in
   `run-review.sh`, drop the removed refusals, `--recapture` legacy path), §3.3 (`pr.sh`
   template + `self/pr.sh`, `PR_AUTO_MERGE` off), §3.6 lifecycle docs, the lifecycle test
   rewrite.
3. **`sweep-retirement-and-audit-fixes`** — §3.5, §3.8 (minus the open items unless
   decided), analysis README rewrite.

Item 1 before 2 because 2's tests assume no pin. Item 3 last because it deletes what 1 and
2 make redundant.

## 7. `permissions-policy-inherit` — what was about to happen

Under the **old** flow, since it started under it:

1. From this router session, launch the review pass in the background from the
   **worktree's copy** (the primary's copy resolves the corpus to the primary, where the
   feature does not exist):
   `/Users/sahildesai/dev/agentTooling/.worktrees/permissions-policy-inherit/run-review.sh --self permissions-policy-inherit`.
   Cost cap $7. On a clean verdict `self/pr.sh` pushes the branch and opens the PR with the
   verdict as body; `pr_opened` and `pass_end` land in the worktree's `timing.jsonl`.
2. Read the PR; merge it on GitHub.
3. From the primary, on `main`, clean: `./feature-close.sh --self permissions-policy-inherit`.
   It will print the boundary warning for this router session (priced in full) — expected.
   It commits the cost records to `main` and pushes; this is the last feature that does.
4. If the review escalates rather than fixes: a rework one-shot briefed with
   `self/review-report.md`, committed on the branch, then step 1 again (re-queue the review
   brief or add a second one and its stem to `plans`).
5. Then `update.sh` in each consuming repo (vinylCatalogue blocked until its primary is
   clean on `main`) to pull the hook and the new deny rules; each needs a new session to
   load them. The hook's approvals arrive with no settings change.
