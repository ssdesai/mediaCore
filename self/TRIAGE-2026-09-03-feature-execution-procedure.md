# Feature execution: from instructions to costed merge — triage (2026-09-03)

_Moved here from `vinylCatalogue/plans/` on 2026-09-03 (it landed there in vinylCatalogue
PR #95). Everything it measures happened in that repo, and every `file:line` was read
against the agentTooling copy vendored there at split `c6cb394` — this repo's `main`
before PR #27, which did not touch the code cited. Paths with no `agentTooling/` prefix
(`plans/pr.sh`, `plans/features/README.md`) are the consuming repo's. Every fix in §3
lands in this directory, which is why the file lives here; §5's brief still names
vinylCatalogue and predates that decision._

The procedure for taking a feature from a human's instruction through a branch or worktree,
a build, a review, a PR, and a frozen cost record is spread across five files and has
three holes in it. Every hole was hit, at least once, while building
`compilation-artists-and-runout` (PR #94) alongside `filter-and-selection-grammar`
(PR #92/#93). This file lays out the steps that are documented, the caveats that are not,
and the fixes in the order they should land. Everything marked **measured** was observed in
this repo on 2026-09-03; everything marked **read** was verified against the code at the
line given; nothing here is inferred from memory.

Read this whole file before doing anything. Then read, in order: `agentTooling/AGENT_DIRECT.md`,
`agentTooling/ORCHESTRATION.md`, `agentTooling/AGENT_PLANS.md` → "The feature manifest",
`agentTooling/analysis/README.md` → "How to run them", `plans/features/README.md`,
`agentTooling/templates/plans/features/TEMPLATE.md`, `plans/pr.sh`.

## 1. The documented procedure (direct one-shot, which is what both features used)

| # | Step | Where it is written |
|---|---|---|
| 1 | Route by size: under ~1000 lines of diff → direct; above → plans | `AGENT_DIRECT.md` → "When it is the right choice" |
| 2 | Copy `plans/features/TEMPLATE.md` → `plans/features/<slug>/README.md`; fill `slug`, `method`, `plans`, `branches`, `session_window.from` | `plans/features/README.md` (last paragraph); `AGENT_DIRECT.md` → "Checklist before spawning" |
| 3 | Author the review brief into `review/incomplete/NN-review-opus.md` **before** the build | `AGENT_DIRECT.md` → "The review is not optional" |
| 4 | Gate green on the base; in-scope READMEs current | `AGENT_DIRECT.md` → "Checklist before spawning" |
| 5 | Branch / worktree | **Not documented.** The whole of it is one parenthetical in `AGENT_DIRECT.md` → "The brief" item 2: *"The implementer works in the checked-out tree (or a named worktree); absolute paths in every command."* |
| 6 | Spawn the implementer; brief opens `feature: <repo>/<slug>` | `ORCHESTRATION.md` → "Rules" |
| 7 | Checkpoint → acceptance tests (own commit) → build → rulings to `NOTES.md` → gate green → commit → terminate | `AGENT_DIRECT.md` → "The procedure" |
| 8 | `./agentTooling/run-review.sh <slug>`; a clean pass calls `plans/pr.sh`, which opens the PR with `review-report.md` as body | `AGENT_DIRECT.md` → "The review is not optional"; `plans/README.md` |
| 9 | `capture_planning.py --list-subagents --unclaimed` must be empty; pin any delegate | `ORCHESTRATION.md` → "Rules"; `TEMPLATE.md` → `subagents` |
| 10 | Weekly cadence: rates check → `backfill_usage.py` → `recover_attempts.py` → `capture_planning.py --all` → `report.py` | `analysis/README.md` → "How to run them" |

Costing is well documented at exactly two points: the manifest field semantics (`TEMPLATE.md`
and `AGENT_PLANS.md` → "The feature manifest": every trap in `branches`, `Z` bounds, chained
windows, pins) and the weekly cadence (why `--all` skips, why `--recapture` is dangerous).
Nothing between step 5 and step 10 says how the choices made in step 5 change what step 10
reports.

## 2. The caveats — what is not written, with evidence

### C1. Worktrees have no procedure, and the things that go wrong in one are known

Worktrees appear in the corpus only as experiment arms (`EXPERIMENTS.md`) and as the permitted
read-only baseline trick in `run-verify.sh`/`run-review.sh`. For ordinary feature work there
is nothing on: creating one, giving it its own `.venv` (never share one across worktrees —
the editable install points at whichever tree installed last), running `npm install` in it,
or the dev-server trap below.

**Measured:** a stray `npm run dev` on the default port in the primary checkout, plus
`playwright.config.ts`'s `reuseExistingServer: !process.env.CI`, made a worktree A/B of the
browser suite a silent no-op — both arms drove the same app, and 14 failures were reported as
"red at baseline" before the user asked what shells were running. `plans/gate.sh` probes
per-run ports so the *gate* is safe; a hand-run dev server is not. `VINYLCAT_DEV_PORT` per
arm is the guard; it is in `plans/PROJECT_FACTS.md` now. Any worktree procedure has to say it.

### C2. The directory a session is *launched* in decides its `gitBranch`, not where it works

**Measured** from transcripts under `~/.claude/projects/`:

- session `5ff71613`, launched inside `…/vinylCatalogue-compilation-artists`, records
  `gitBranch: compilation-artists-and-runout` — correct;
- session `f1202243`, launched in `…/vinylCatalogue` (the primary checkout) and `cd`-ing
  into the worktree for every command, records `filter-and-selection-grammar`, `main`, and
  `fix/pr-sh-direct-oneshot-base` — the primary checkout's branches over the day — for the
  entire build. A `cd` in Bash never changes what the transcript records.

`ORCHESTRATION.md` covers only the *subagent* form ("a delegate's transcript inherits the
coordinator's `gitBranch`"). The coordinator-in-a-worktree form has no rule. The consequence
was `filter-and-selection-grammar`'s window (11:55–13:00Z) claiming this feature's whole build
by branch + window, fixed by hand with `exclude_sessions` on their manifest and a four-branch
`branches` list on ours.

### C3. `capture_planning.py` run from a worktree reports `$0.00`, with a misleading warning

**Read:** `agentTooling/analysis/capture_planning.py:228` `find_transcript_dirs` matches
project directories by *substring* of `transcript_dir_name(repo_dir)`, and `repo_dir` comes
from the script's own location (`roots.py`), never `cwd`. The match is directional: from the
primary checkout the fragment `-Users-sahildesai-dev-vinylCatalogue` matches all 17 project
dirs, including every worktree's; from the worktree the fragment
`…-vinylCatalogue-compilation-artists` matches none. The warning that results — "branch
matched no session in any transcript … either the name is wrong or the transcripts have aged
out" — names two causes and this is a third.

`analysis/README.md` → "Where to run them" says *"which copy you invoke selects the repo,
and `cwd` is irrelevant"*. True, and it hides that the worktree's vendored copy is always the
wrong copy.

### C4. Even from the primary checkout, a session launched in a worktree is invisible

**Read:** `capture_planning.py:1087`:

```python
repo_match = any(
    line.get("cwd") == session_dir_str
    or (isinstance(line.get("cwd"), str) and line["cwd"].startswith(session_dir_str + "/"))
    for line in lines
)
```

`session_dir_str` is the session root (nearest ancestor with `.git`, `roots.py:60`). A
worktree at `…/vinylCatalogue-compilation-artists` is a *sibling* path: it fails both the
equality and the `+ "/"` prefix test. So its project dir is walked (C3's substring match
includes it) and every session in it is then dropped. **A session launched in a worktree is
uncountable from either direction.** This inverts the obvious fix for C2 — "launch the session
in the worktree so `branches` attributes correctly" — which would produce a correct
`gitBranch` and still report `$0.00`. Until C4 is fixed, worktree isolation and cost
attribution are mutually exclusive.

### C5. A `$0.00` capture was frozen and committed, and `--all` then protected it

**Measured:** `plans/features/compilation-artists-and-runout/planning.json` was captured from
inside the worktree (C3), produced `$0.00` with the "matched no session" warning on all four
branches, and was swept into commit `93d481e` by `git add`. It merged to `main` in #94. The
next `capture_planning.py --all` reported *"already captured … total $0.0000 — skipping"*.
It took `capture_planning.py compilation-artists-and-runout --recapture` from the primary
checkout to get the real figure: 1 session matched (`f1202243`, 12:30:30–16:57:16Z),
**$56.23**, filed under build by `method: direct`; `report.py` total $60.51 with the review
pass's $4.28. The correction is on local branch `cost/capture-after-compilation-artists`
(two commits, unpushed).

There is no guard between "zero sessions matched" and "write the file". A frozen zero looks
exactly like "planning was free", which `AGENT_PLANS.md` already identifies as the failure
that held five features at zero before anyone noticed.

### C6. Nothing marks the moment a feature stops accruing

- No step in `AGENT_DIRECT.md`'s procedure, in `run-review.sh`, or in `pr.sh` sets
  `session_window.to`. The prose owner ("set a real bound as soon as it is done") has no
  step. Both features' windows were wrong until fixed by hand.
- No step triggers capture for *this* feature. The only trigger is the weekly `--all`, which
  captures from whatever the manifest says at that moment, so a feature's frozen number is
  right only if the manifest was corrected before the next cadence run happened to fire.
- **Measured:** capture froze a live session. `f1202243` was still running when it was
  captured (the transcript's `ended_at` is simply the last line at that moment), and
  `filter-and-selection-grammar`'s `ed7a721a` froze at $23.72 with `ended_at` 15:17:19Z when
  the session actually ran to 15:55:26Z. Capture timing relative to session end is
  undocumented; a "close" step is where it belongs.

### C7. There is no unclaimed check for top-level sessions

**Read:** `capture_planning.py:446` `unclaimed_under` and `:522` `list_subagents` walk
`subagents/` directories only. `ORCHESTRATION.md`'s standing rule — "`--unclaimed` must come
back empty before the cost is quoted" — cannot see a *session* that no manifest's
branch + window selects. `f1202243` was one for most of a day. It was found because a number
looked wrong, not because anything listed it.

### C8. `pr.sh` assumes the plan workflow, twice

**Measured, run 1 (pre-#93 `pr.sh`):** after the clean review pass, `pr.sh` set
`BASE_BRANCH="$current_branch"` (= `compilation-artists-and-runout`), cut
`review/compilation-artists-and-runout` off it, pushed only the review branch, and
`gh pr create` failed: *"Base ref must be a branch … No commits between …"*. Correct for a plan
batch (which runs on `main` and cuts the review branch off it); never correct for a direct
one-shot, which already built on its own branch. The PR was opened by hand:
`review/compilation-artists-and-runout` → `main`.

**Read, the fix that landed in #93 (`plans/pr.sh:69–74`):**

```bash
work_already_committed=false
if [[ -z "$(git status --porcelain)" ]] && git show-ref --verify --quiet "refs/heads/$DEFAULT_BASE" \
  && [[ "$current_branch" != "$DEFAULT_BASE" ]] \
  && [[ "$(git rev-list --count "$DEFAULT_BASE".."$current_branch")" -gt 0 ]]; then
  work_already_committed=true
fi
```

Its comment assumes the review pass leaves the tree clean. In run 1 it did not: the reviewer
edited `src/vinylcat/review/state.py`, `apply.py`, `review/README.md`, the manifest and the
backlog, and `pr.sh`'s own commit step (`:105`) is what swept them into `c636760`. With a
dirty tree the guard is false and control falls to the same `else` branch. **The #93 fix
handles a direct one-shot whose review found nothing, and not one whose review fixed
something** — and review passes routinely fix local documentation drift, so that is the
common case. Inferring the workflow from tree state is the wrong signal; the manifest's
`method` field is the right one.

### C9. Two doctrine lines contradict what actually happens

- `AGENT_PLANS.md` → "The feature manifest": *"Never written or edited by a build, verify or
  review executor."* `AGENT_DIRECT.md` step 6 has the implementer commit "the feature
  manifest", and **measured**, the review executor edited the manifest's
  "Deliberately excluded" bullet in `c636760` (correcting a false premise — the right call,
  and the rule says it may not).
- The review pass edits `src/`. `AGENT_PLANS.md` → "Review plans" frames review as reading
  the diff and phrasing findings as assertions; `run-review.sh` gives it Bash and it fixes
  local drift. Fine in practice, but "local findings are fixed there" (`AGENT_DIRECT.md`)
  and "never edited by a review executor" cannot both be true of the manifest.

### C10. The `$0.00` warning conflates three causes with three different fixes

Wrong branch name (fix: copy from `git branch --show-current`), expired transcripts (fix:
nothing; `--carry-lost` if a pin is being added), and running from a worktree (fix: run from
the primary checkout). The warning text at `capture_planning.py:~762` names the first two.

## 3. The fixes, in the order they should land

Ordered so each one makes the next one safe to do. 1–2 and 7–8 are in shared `agentTooling`
(a `git subtree`; see memory note on pushing it back — squash pulls break `subtree push`).
3–6 are repo-owned (`plans/`) or doctrine.

1. **`repo_match` accepts the primary checkout's worktrees** (`capture_planning.py:1087`).
   Compute the set once per capture: `git -C <session_root> worktree list --porcelain`
   → every `worktree <path>` line; a session matches if its `cwd` equals or is under any of
   them. Also record the session's cwd in `planning.json`'s session entry so a reader can see
   which tree it ran in. Without this, fixes 4–5 cannot tell people to launch in the
   worktree. Assertion: a transcript whose `cwd` is a registered worktree path is selected;
   one whose `cwd` is an unregistered sibling (`…-vinylCatalogue-baseline` after
   `worktree remove`) is not.
2. **Refuse the silent zero.** Two guards in `capture_planning.py`:
   (a) if `git rev-parse --git-dir` ≠ `git rev-parse --git-common-dir` at the artifact root,
   exit non-zero naming the primary checkout — it is the parent of `--git-common-dir`, so the
   message can print the exact command to run instead (**measured**: primary gives
   `.git`/`.git`; the worktree gives `…/.git/worktrees/<name>`/`…/.git`);
   (b) if zero sessions and zero subagents matched, do not write `planning.json`; print the
   three-cause triage (C10) and exit non-zero. `--force` overrides (b) for a feature whose
   transcripts have genuinely aged out. Assertion: a capture that matches nothing leaves no
   file behind.
3. **`pr.sh` reads `method` from the manifest** (`plans/pr.sh`, repo-owned; then the
   template `agentTooling/templates/plans/pr.sh`). `"direct"` → base is `main`
   (`BASE_BRANCH` env still overrides), head is the current branch, the review pass's edits
   are committed onto it, no `review/` branch is cut, the branch is pushed. `"plans"` or absent
   → today's behaviour. Delete the `work_already_committed` inference. Assertion: with a
   dirty tree and `method: direct`, no second branch is created and the PR targets `main`.
4. **`plans/feature-start.sh <slug> [--worktree]`** (repo-owned, seeded from a template like
   `gate.sh`/`pr.sh`). Creates the branch off `origin/main`; with `--worktree`, `git worktree
   add ../<repo>-<slug> -b <slug>`, then `python -m venv .venv && uv pip install -e ".[dev]"`
   (or the repo's equivalent from `PROJECT_FACTS.md`) and `npm install` inside it. Copies
   `TEMPLATE.md` to `plans/features/<slug>/README.md` with `slug`, `method: "direct"`,
   `plans: ["01-review-opus"]`, `branches` (from `git branch --show-current`, verbatim) and
   `session_window.from` (from `date -u +%Y-%m-%dT%H:%M:%SZ`) filled and `to: null`. Creates
   `review/incomplete/`. Ends by printing, in this order: the `VINYLCAT_DEV_PORT` warning
   (C1), and **"launch the coordinator session in `<worktree path>`, not here"** (C2) — which
   is only safe once fix 1 has landed, so the script should refuse `--worktree` if
   `capture_planning.py` predates it (check for the worktree-list code, or a version
   constant).
5. **`plans/feature-close.sh <slug>`** — the missing lifecycle event (C6). Refuses to run
   from a worktree (same test as fix 2a). Stamps `session_window.to` with now (UTC, `Z`) if
   it is `null`. Runs `capture_planning.py --list-subagents --unclaimed --since <from date>`
   and stops if non-empty. Runs `capture_planning.py <slug>` (no `--recapture` unless
   `--recapture` was passed through), then `report.py <slug>`, and prints the total with the
   session ids it matched so the human reads what was claimed before quoting it. Leaves the
   commit to the human. Documented as: run after the PR merges, from the primary checkout,
   before the coordinator session that built the feature ends (so its transcript is
   complete — C6's live-session point).
6. **Doctrine edits**, each one line where it belongs:
   - `AGENT_DIRECT.md` → "The brief" item 2 and `ORCHESTRATION.md` → "Rules": *the branch a
     session is billed to is the branch of the directory it was launched in, never the
     directory it worked in; a `cd` changes nothing.* Point at `feature-start.sh`.
   - `AGENT_DIRECT.md` → "The procedure": add step 8, *close* — `feature-close.sh` after
     merge; and reconcile step 6 with `AGENT_PLANS.md`'s never-edited rule by saying which
     manifest fields the implementer and the review executor may touch (the excluded-list
     prose, yes; the JSON fence, no).
   - `analysis/README.md` → "Where to run them": the worktree copy is the wrong copy, and
     why (C3); "How to run them": the per-feature close is `feature-close.sh`; the weekly
     `--all` is the sweep behind it.
   - `plans/features/README.md` last paragraph: "To start a new feature, run
     `plans/feature-start.sh <slug>`" instead of "copy `TEMPLATE.md`".
7. **`capture_planning.py --list-sessions --unclaimed`** (C7): every top-level session in
   this repo's project dirs that no manifest's branch + window + pins selects, with start,
   `gitBranch`, `cwd`, and cost. `feature-close.sh` runs it too. This is the session-level
   twin of the delegate check `ORCHESTRATION.md` already mandates.
8. **The warning text** (C10) names all three causes and the command for each.

Backlog entries to add when this lands, if not fixed in the same pass: the #93 `pr.sh` guard's
clean-tree assumption (C8) — currently recorded nowhere; and the three
`_merge_credits`/`_merge_misc`/`_merge_matrix_runout` constructors that still name their
leaves explicitly (from `compilation-artists-and-runout`'s `CHECKPOINT.md`, unrelated to this
triage but left undone there).

## 4. Facts pinned for whoever executes this

- Primary checkout: `/Users/sahildesai/dev/vinylCatalogue`, on `main` at `e59913a` (#94
  merged). Local branch `cost/capture-after-compilation-artists` holds two unpushed commits
  (`d100b21`, `2cc273f`): the recaptured `planning.json` for four features and this
  feature's `report.md`/`report.json`. Merge or PR it first; nothing depends on it, but
  `--all` will re-skip the zero if it is lost.
- No worktrees exist now (`git worktree list` shows only the primary). Transcript project
  dirs for old worktrees (`…-baseline`, `…-exportStoreDirect1` etc.) still exist under
  `~/.claude/projects/` and are what fix 1's assertion should be built from.
- `capture_planning.py` and `report.py` are stdlib Python 3; run as
  `python3 agentTooling/analysis/<name>.py` from the primary checkout. `uv` is not on PATH
  on this machine; `plans/gate.sh` falls back to `.venv/bin/python`.
- The `pr.sh` currently on `main` is the #93 version (has `work_already_committed`). The
  seed template is `agentTooling/templates/plans/pr.sh`; `sync-plans.sh` seeds it once and
  never overwrites, so both copies need the change.
- The test conventions for `agentTooling` itself: `agentTooling/self/tests/*.sh`
  (e.g. `timestamps-are-utc.sh`); features whose diff is entirely inside `agentTooling` are
  costed with `--self` and live under `agentTooling/self/features/`.
- Session ids used above, for checking claims against transcripts: `f1202243-ab49-4323-88b0-32469c20c6b5`
  (this feature's build, primary checkout, claimed by `compilation-artists-and-runout`),
  `ed7a721a-bea0-4f0c-a967-c26fc6833fb8` (`filter-and-selection-grammar`'s coordinator on
  `main`), `5ff71613…` (launched in the worktree; look it up under
  `~/.claude/projects/-Users-sahildesai-dev-vinylCatalogue-compilation-artists/`),
  `021cb889…` (this feature's review executor; excluded via its `usage.json`).
- Sizing: fixes 1–3 and 7–8 together are well under a thousand lines and touch two Python
  scripts, two shell scripts and five markdown files. Direct one-shot per `AGENT_DIRECT.md`,
  with a review brief written first. Fixes 4–6 are a second slice; 4 must not ship before 1.

## 5. Brief for the executing session

    feature: vinylCatalogue/feature-execution-procedure

    Read plans/TRIAGE-2026-09-03-feature-execution-procedure.md in full, then the files its
    header lists, in that order. Work in /Users/sahildesai/dev/vinylCatalogue on a branch
    off origin/main named feature-execution-procedure. Do NOT use a worktree for this one:
    fix 1 is what makes worktrees costable, and it does not exist yet.

    Before the first edit: copy plans/features/TEMPLATE.md to
    plans/features/feature-execution-procedure/README.md, method "direct", branches
    ["feature-execution-procedure"] copied from `git branch --show-current`,
    session_window.from = now in UTC with a Z, to = null. Write the review brief to
    review/incomplete/01-review-opus.md from §2 and §3 of the triage — what each fix must
    hold to, and its assertion — before building anything.

    Then AGENT_DIRECT.md → "The procedure": CHECKPOINT.md with the slices (§3 items 1, 2, 3,
    7, 8 first; 4, 5, 6 second), acceptance tests first and committed on their own, build,
    rulings to NOTES.md as they are made, gate green, commit. Every measured fact in the
    triage is a test you can write; write the ones §3 names as assertions at minimum.

    When done, from the primary checkout: set session_window.to, run the new
    feature-close.sh on this feature as its own first test, and read back which session it
    claimed before quoting the number.
