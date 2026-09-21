# agentTooling

Shared Claude Code conventions and a delegated-plan execution harness, vendored
into each repo with `git subtree` so fixes are made once and pulled everywhere.

## Contents

Read by category. A consuming repo sees all of this under `agentTooling/`; the runners
and the two lifecycle scripts are invoked from that repo's root as
`./agentTooling/<script>`.

### Start here

| File | What it is |
|---|---|
| `LIFECYCLE.md` | The six steps a feature runs through — route, start, brief, build, review and PR (which captures the cost on the branch), merge — plus propagating this directory's own changes to the consuming repos, each naming the script that does it or the doc that governs it, plus the naming rule every step derives from (slug `S` → branch `S`, worktree `<repo>/.worktrees/S`, inside the primary and kept out of git) and the three rules the rest assumes: a session is billed to the branch of the directory it was launched in, agents never create branches or worktrees, and the manifest's fence belongs to the scripts. Read first; everything below is one step of it. |

### Building a feature

Three methods, one rule for where the work happens (`ORCHESTRATION.md`, and the
`AGENT_*` doc for the method). Every feature, whichever method, ends in the same review
pass and the same PR hook.

| File | What it is |
|---|---|
| `ORCHESTRATION.md` | How to run the tier above the runners — a coordinator session automating the human who would run `run-batch.sh`, across repos or across interleaving features in one repo. The architect plans; the coordinator runs. Read before delegating feature work to subagents. |
| `AGENT_DIRECT.md` | The other way to build a feature: one opus implementer, acceptance tests first, gate to green, commit, then an independent review pass whose verdict ends the round — clean, `feature-close.sh` opens the PR; escalated, the rework is round 2. When it beats the plan workflow (measured: under roughly a thousand lines of diff, or when the hour matters), what its brief carries, the procedure it follows, and how a dead implementer is replaced from its checkpoint rather than resumed. |
| `AGENT_PLANS.md` | How to author plans for the delegated-execution workflow. Overrides parts of `CONVENTIONS.md` during plan generation (see its "Precedence" section). |
| `RUNNER.md` | How execution works — the queue state machine, resume semantics, progress and event logs, and the build/verify/review/interactive split. Read when authoring plans or debugging a failed run. |

**The runners, and the scripts that bracket them.** Three passes, one per queue under a
feature, plus the sequencer that runs them in order; the direct method uses only the
review pass. `feature-start.sh`, `feature-close.sh`, `feature-capture.sh` and
`stamp-timing.sh` drain no queue — they open a feature, close it, record its cost on the
branch, and stamp a build that has no runner. A feature is a sequence of **rounds** (build
→ gate → verify → review) and the two bracketing scripts are the only ways in and out.

| File | What it is |
|---|---|
| `run-plans.sh` | Build runner. Drains `plans/features/<slug>/auto/incomplete/` unattended with **Bash disabled**, so a build plan can only edit files. Takes the slug as its first argument; with none, infers it from the single feature that has queued work and errors if two do. A plan named `NN-gate.md` is a level sentinel: the runner runs `plans/gate.sh NN` in its place and exits 64 (`LEVEL_PAUSE_RC`) instead of continuing when a verify plan numbered ≤ NN is queued and the level's gate is not green; a green gate files the level-verify as skipped and continues. |
| `run-verify.sh` | Verify runner. Drains `plans/features/<slug>/verify/incomplete/` with **Bash enabled**, so a post-build pass can probe what a script can't express — cross-layer invariants, security boundaries, adversarial inputs. Mechanical checks belong to `plans/gate.sh`; world-building belongs in a test; fixes here stay local. Capped per plan: the final verify by `VERIFY_BUDGET_USD` (`$3.00`), a level-verify (`NN-level-*`, or any plan under `--up-to`) by `LEVEL_VERIFY_BUDGET_USD` (`$6.00`), a synthesized `NN-escalation-*` by `ESCALATION_BUDGET_USD` (`$8.00`); exceeding a cap routes the plan to `failed/`. A level-verify's prompt carries the tier-1 rule (fix the tree, never a contract; write `escalations/NN.md` instead); an escalation gets its own preamble and may edit queued plans. `--up-to NN` (after `--self`) drains only verify plans numbered ≤ NN. |
| `run-review.sh` | Review runner, and the end of a **round**. Drains `plans/features/<slug>/review/incomplete/` after verify, reading the **diff** rather than running the work — the defects that stay green: an invariant with no test, a contract broken on one side, a field list that drifted from its shape. Same tool scope and same fix policy as verify (local fixes, structural escalations). The executor writes its verdict to `plans/review-report.md`, whose **first line** is `Verdict: clean` or `Verdict: escalated` (`VERDICT_PREFIX` and friends, `plan-runner-roots.sh`); the runner reads that line, commits the pass's own output as `<slug>: review round N` — only when on a branch that is not the feature's `base`, which it reads from the manifest — stamps that round's `plan_end` with `verdict=` and `head=` (the sha of that commit: the tree the verdict judged), then `pass_end`, and **stops**. It opens no PR and runs no capture: those belong to `feature-close.sh`, which the pass names, and holding them behind the verdict is what stops a rework happening behind a PR body that describes the tree before it. A first line it cannot read is `unreadable` and is treated exactly like escalated — fail closed. On escalated or unreadable it copies the report to `plans/features/<slug>/escalations/<review-stem>.md` — the rework brief, in the directory the tier ladder already writes into — and prints the next round's three steps. Defaults to `opus`; capped by `--max-budget-usd` (default `$7.00`, override `REVIEW_BUDGET_USD`). A cap that fires after the report was written still records the verdict, with a banner in the report. Optional per feature — an empty queue is a clean no-op. |
| `run-batch.sh` | Runs the build pass, then, for each level boundary that paused it, climbs the red-gate tier ladder (level-verify → re-gate → synthesized opus escalation → re-gate → stop; `RUNNER.md` → "Red gates") and resumes the build; then the final gate, verify and review passes, each gated on the one before it. **Then it ends the round the review decided**, reading the verdict with the same two readers the close uses (`latest_review_plan`, `review_plan_end`): clean → it calls `feature-close.sh`, so the unattended path still ends in a PR with the cost record on the branch; escalated or unreadable → it prints the rework brief's path and exits 1. A re-run with an explicit slug settles an unsettled level before building on it. The corpus lint (`check-plans.sh`) runs once per batch on whichever slug the run is about — the explicit one before the build pass, an inferred one as soon as the build pass has resolved it, and a FAIL stops the batch there. |
| `check-plans.sh` | Lints one feature's manifest fence and plan files before a paid run — fourteen `ok`/`FAIL` checks, exit 1 on any. Check 7 covers the whole `session_window`: both bounds carry a zone, and `to` is null (in flight) or an instant strictly after `from`, compared as instants rather than as text. `run-batch.sh` runs it once per batch — before the build pass when the slug is explicit, and otherwise as soon as the build pass has resolved it. |
| `run-escalation-plan.sh` | Writes the tier-2 `NN-escalation-opus.md` brief into a feature's `verify/incomplete/` (from `write_escalation_plan` in the lib) and refuses to write a second one for the same level. Called by `run-batch.sh`; by hand, how to re-arm tier 2 after editing `escalations/NN.md`. |
| `feature-start.sh` | Opens a feature: `feature-start.sh [--self] <slug>`, plus `--method` (`direct`, `plans` or `hand`), `--base <branch>`, `--no-gate`, `--pin`, `--session <id>`, `--open`. Run from the primary checkout, and the only sanctioned way to create a feature branch or worktree — branch `<slug>`, worktree `<repo>/.worktrees/<slug>` inside the primary, so a session launched in the primary reaches it with no access outside its folder. It keeps `.worktrees/` out of git by appending `/.worktrees/` to the common git dir's `info/exclude` — once, idempotently, and nothing tracked changes — so the primary's `git status` stays clean. It then **prunes the features that have merged** (every worktree under `.worktrees/` whose branch is an ancestor of `origin/main` is removed and its local branch deleted with `git branch -D` — ancestry against `origin/main` is the check, and `-d` would re-decide it against the primary's own `HEAD`, which lags whenever the PR merged on the forge and nobody pulled; a dirty one is left with a line saying so, an unmerged one is never touched, and nothing is committed or pushed), runs the repo-owned `plans/worktree-setup.sh` and the gate inside the new worktree, and writes and commits the feature directory there: the manifest with its fence filled, a review-brief stub carrying `@@TODO@@` that `run-review.sh` refuses to run, and the **routing record** for the session that ran it (`plans/features/<slug>/routing.json`, `self/features/` under `--self`, written by `analysis/routing.py` from that session's transcript — inside the feature it links, so no two features ever write one path and the one `git add` carries it). **It pins nothing by default** — the session that starts a feature is a *router*, its spend is routing overhead rather than any feature's, and `--pin` is the opt-in for the rare case where it really is this feature's coordinator (`--no-pin` is still accepted and does nothing). `--open` runs the repo-owned `plans/open-session.sh` with the worktree path, which is how the coordinator session is launched inside the worktree. Refuses a slug that is not kebab-case, an existing branch or worktree, a base whose gate is not green, and being run from a worktree's copy. Depends on `$CLAUDE_CODE_SESSION_ID` (or `--session`) to name the router, and on that session's transcript being under `~/.claude/projects/`; a missing transcript costs the record its figures and never the start. `LIFECYCLE.md` → step 2. |
| `feature-capture.sh` | Records a feature's cost **on its branch, before the merge**: `feature-capture.sh [--self] <slug> [--recapture] [--no-push]`. Called by `feature-close.sh` after `pr.sh`, and re-runnable by hand from the worktree; no model is involved, and the merge is the freeze. Which run it is follows from where it runs. **On the branch** (the checkout this copy lives in has `<slug>` checked out — the feature's worktree): it refuses first if anything but cost records is dirty (`stray_paths`, `plan-runner-roots.sh`, which `feature-close.sh` calls before its PR too); stamps `session_window.to` from evidence — one second past the last instant of the sessions this feature's branches and window select, and of their subagents — with `manifest.py set-window-to --replace`, since before the merge the bound moves either way; recovers unpriced attempts (`recover_attempts.py --for`); captures (`--recapture` once a record exists, so a second run replaces the first) and reports; prints what `planning.json` claims; **annotates** every other already-captured record in this corpus whose `sessions[].also_claimed_by` the claims ledger has changed (`capture_planning.py --annotate-frozen`, a ledger read that opens no transcript and moves no figure) and re-renders each of those features' reports; refreshes this feature's own routing record and no other feature's copy of it (`routing.py --refresh-for`, silent when the feature has none); **warns** — never refuses — about a delegate whose brief names `<repo>/<slug>` and that no route claims; prints the **residue** — the rate table's verified date, and the corpus-wide sessions and delegates (routers excluded) no feature claims, over the last `RESIDUE_LOOKBACK_DAYS`, which is where the retired weekly sweep's last step went and is never a refusal; commits `COST_FILES` (the routing record among them), the queue/state usage sidecars and each annotated feature's `planning.json`/`report.*` as `<slug>: cost records`; and pushes the branch, never `main`. **The stray check is strict before the annotation and admits the annotated slugs after it**: the run that opens refusing a sibling's `report.md` — a record it did not write, which would otherwise be neither refused nor committed and ride the push as dirt — re-runs the same reader before the commit with exactly the slugs `--annotate-frozen` returned, whose three `ANNOTATION_FILES` are cost records this run wrote, and nothing else under another feature's directory. **After the merge** (anywhere else, typically the primary on `main`): for a feature merged under the old flow and never closed, or to repair one with `--recapture` (`--tighten`: a bound only ever moves earlier, and the widen refusal, `manifest.py`'s exit 3 alone, warns and carries on) — it refuses an unmerged branch, proceeds with no branch left only on the manifest being tracked there and its `<slug>: start` commit in history, and **writes locally, commits nothing, pushes nothing**. A capture that refuses restores the stamp and any recovered sidecar from a snapshot taken before either was written. Depends on `roots.session_root` resolving a worktree's copy to the primary checkout, so the worktree copy selects what the primary's would. `LIFECYCLE.md` → steps 5 and 6. |
| `feature-close.sh` | Closes a feature: `feature-close.sh [--self] <slug> [--no-push]`, from the feature's worktree, on its branch, by the coordinator or by `run-batch.sh`. The **only way out**, and the counterpart of `feature-start.sh`. It refuses first, before anything is written, so a refusal costs nothing and comes before a PR rather than after one: a checkout not on branch `<slug>` (the post-merge repair path is `feature-capture.sh` from the primary), a feature no review has finished (naming `run-review.sh`), a latest review whose `plan_end` verdict is not `clean` (naming the escalations file and the round that would follow), a `HEAD` that is neither the stamped `head` nor that sha followed only by the harness's own subjects (`<slug>: cost records`, `<slug>: PR` — anything else is a change no review read, and that is a new round), and a dirty path that is not one of the harness's records — **the capture's own reader** (`stray_paths` with no sibling slug admitted, `plan-runner-roots.sh`), so exactly what step 3 would refuse after the PR is refused here before it. The round it prints and stamps is the one the closing review's `plan_end` recorded, with `completed_review_count` only as the fallback for a `timing.jsonl` written before rounds existed — a review capped after writing its report sits in `review/failed/` and counts toward no round. Then, in an order that is the point: commit the review pass's trailing stamps as `<slug>: PR` (which keeps `pr.sh`'s fallback commit the no-op it now is) → the repo-owned `plans/pr.sh <slug> <body>`, with the review's report and `analysis/report.py --rounds-md`'s Rounds table as that body → the `pr_opened` stamp with its rc and url → `feature-capture.sh`, which commits the cost records on the branch (the stamp rides that commit) and pushes → `plans/pr.sh --merge-request <slug>` **last**, which asks the forge to merge under `PR_AUTO_MERGE` only now that the record is pushed. That ordering is the whole of the `PR_AUTO_MERGE` race it replaces. A refused capture is printed with the command that re-runs it, skips the merge request, and exits 1; a seeded `pr.sh` below `template-version: 4` has no `--merge-request` entry point, which it says once and skips. Re-runnable: a second run finds the PR open and the capture replacing its own record. Depends on the review runner's `plan_end` stamp carrying `verdict` and `head`, and on `pr.sh` printing the PR url on stdout. `LIFECYCLE.md` → step 6. |
| `stamp-timing.sh` | Appends one wall-clock line to a feature's `timing.jsonl` by hand: `stamp-timing.sh [--self] <slug> <event> [key=value ...]`. The runners stamp their own boundaries; this is for the one build that has no runner — a **direct** feature's implementer stamping `checkpoint status=<status>` at each checkpoint milestone (`AGENT_DIRECT.md`), which is what lets `analysis/report.py` split its single transcript span into tests, build and gate. An unknown feature, a missing event or a detail that is not `key=value` is an error, never a silently dropped stamp. |
| `plan-runner-lib.sh` | The queue/resume/logging/routing machinery all three runners source. Single source of truth for the subtle parts — the file-first stream capture (`claude` writes `.stream.jsonl` itself; `follow_stream` feeds the FIFO and the display from it), the SIGPIPE trap that keeps a closed consumer from failing a plan, the FIFO-PID wait race, usage-limit detection, stream finalization, and the per-attempt accumulation that keeps a resumed plan's earlier runs from being re-billed as planning cost. Not run directly. `QUEUE` is only ever used to build paths, which is why a new queue costs a wrapper script and no change here. Also owns sentinel handling (`is_gate_sentinel`, `level_verify_queued`, `run_level_gate`) and the `PLAN_MAX_NN` bound on `list_plans`. |
| `plan-runner-roots.sh` | Resolves normal vs `--self` roots (`REPO_DIR`, `FEATURES_DIR`, gate script, PR hook, review-report path) for all the runners, and holds what the runners, `run-batch.sh`, `feature-close.sh`, `feature-capture.sh` and `stamp-timing.sh` must agree on: `stamp_timing` (one `timing.jsonl` line per event, every detail a string, every line carrying its `round`); the verdict vocabulary and its reader (`VERDICT_PREFIX`, `VERDICT_CLEAN`, `VERDICT_ESCALATED`, `VERDICT_UNREADABLE`, `report_verdict` — the report's **first line** and nothing else, its case folded and its space and `\r` trimmed before the prefix is matched); the round arithmetic (`completed_review_count`, `next_round`, `TIMING_ROUND` fixed once per pass); the readers of a round's outcome (`latest_review_plan` over `review/complete/` and `review/failed/`, highest by the stem's **leading number** and not lexically, since a feature whose own numbering crosses 99 holds stems of two widths until its filenames are re-padded; `review_plan_end <slug> <stem> verdict\|head\|round`); and **the one reader of which dirty paths are the harness's own records** — `COST_FILES` (the feature's `routing.json` among them), the per-plan sidecar constants, `ANNOTATION_FILES`, `is_cost_usage_path`, and `stray_paths <status output> <admitted sibling slugs>` over the three path labels `stray_labels <slug> <checkout>` sets (`FEATURE_REL`, `FEATURES_REL`, `STRAY_SLUG`). Its two callers are `feature-capture.sh`, which admits `NO_SIBLINGS` before its annotation step and exactly the slugs `--annotate-frozen` returned after it, and `feature-close.sh`, which admits none because it annotates nothing. One copy of each, because a runner and the close disagreeing about a verdict is how an unreviewed tree gets merged, and a close looser than the capture is a file refused after the PR is open instead of before it. `stray_paths`' RETURN CODE, not just its stdout, is the contract: 0 means the three labels were set and its list is complete, `STRAY_UNJUDGED_RC` means `stray_labels` was never called and it judged nothing — so every caller must be `if ! STRAY="$(stray_paths …)"; then refuse …; fi`, which also refuses on any other way the command substitution's subshell can die (`set -u` on a missing label used to kill only that subshell and read back as "nothing is stray"). Sourced, never run directly; `self/tests/verdict-readers.sh` calls the round readers and `stray_paths`/`stray_labels` directly. |

### Costing

| File | What it is |
|---|---|
| `analysis/` | Stdlib-only Python scripts pricing and reporting what a feature cost to plan and build — the rate table, planning-session capture, the claims ledger, the routing record, and the cross-feature cost report (`report.py --all`, which first writes the report of every feature that has a `planning.json` and no `report.json`). `feature-capture.sh` runs them for one feature on its branch; there is **no weekly sweep** — what is left of one is `analysis/README.md` → "Repair tools" (`backfill_usage.py`, a corpus-wide `recover_attempts.py`, `capture_planning.py --all`, `--recapture`, `--carry-lost`), each with the one reason to reach for it. See `analysis/README.md`. |

### Experiments

| File | What it is |
|---|---|
| `harness/` | The experiment harness that runs one: it builds a frozen fixture several ways, reviews and reworks every tree from the same brief, scores each run and appends it to a ledger. `harness/run.sh <experiment-dir>` from the consuming repo root, `--dry-run` first; `new-fixture.sh` / `check-fixture.sh` / `new-experiment.sh` / `publish.sh` scaffold, validate, and publish around it. Isolation between arms is structural rather than a rule — no stage reads across worktrees, and the review brief exists before any method runs. Fixtures and experiments live in the consuming repo under `plans/experiments/`, since they pin other repos' commits. See `harness/README.md`; `harness/SPEC.md` is the design record. |
| `harness/EXPERIMENTS.md` | How to A/B a doctrine or runner change against the version before it — arms as pinned worktrees, a checklist written first, a behaviour score script through real routes, `report.py` for cost, and what counts as noise. `templates/experiment/CHECKLIST.md` is the skeleton. |

### Installing into a consuming repo, and keeping it current

| File | What it is |
|---|---|
| `CONVENTIONS.md` | Repo-agnostic working conventions — README traversal, file access, shell command shape, debugging discipline, named constants. Imported by each repo's root `CLAUDE.md`. |
| `sync-plans.sh` | Writes the generated `plans/` stubs (`README.md`, `interactive/README.md`, `features/README.md`, `features/TEMPLATE.md`, `.gitignore`) from `templates/`, and seeds the six repo-owned files (`PROJECT_FACTS.md`, `BACKLOG.md`, `gate.sh`, `pr.sh`, `worktree-setup.sh`, `open-session.sh`) only when absent. Run at install and after every `subtree pull`. Never overwrites those six. Its write path also runs `analysis/routing.py --migrate`, which empties the old `plans/routing/` into the feature each record names (`plans/features/<slug>/routing.json`) and prints one line per move for the human to commit — idempotent, silent once the directory is gone, and never a failure; `--check` writes nothing, so it does not run it. Also merges the `PreToolUse` hook entry for `hooks/allow-repo-commands.sh`, the `Edit` and `Bash` deny rules and the `hooks/` `Edit` ask rule from `hooks/wire-settings.py` into the repo's `.claude/settings.json` — each appended when absent, left alone when present, never copied over, and nothing the repo had is removed, and never an allow rule. `--check` reports without writing: stale stubs, repo-owned scripts behind the template's `template-version`, an unfilled `PROJECT_FACTS.md`, a missing `BACKLOG.md`, an unwired hook or a missing deny or ask rule, counted by kind. |
| `update.sh` | From a consuming repo: refuse on a dirty tree, `git subtree pull --squash`, then the freshly pulled `sync-plans.sh`. |
| `hooks/` | Claude Code hook scripts. `allow-repo-commands.sh` is a `PreToolUse` hook approving repo-confined read and test Bash commands, simple brace lists and the harness's own read-only entry points (`gate.sh`, `check-plans.sh`, `bash -n`, `shellcheck`, `py_compile`, `report.py`, a listing `capture_planning.py`, `manifest.py get`) included — each only when the word carries a directory component, since bash resolves a bare name along `$PATH` — and answering one of three verdicts for everything else: **REWRITE** — a command it could not read, denied with the rewrite as the reason so the model corrects itself rather than the human approving it — or **ASK** — a command it read and cannot vouch for, where it prints nothing and the human decides. Three shapes it reads perfectly well are denied outright with a reason each: a chained `cd`, naming the rewrite; a git command that moves a ref or rewrites history, naming `LIFECYCLE.md` rule 2 and both `feature-start.sh` (the way in) and `feature-close.sh` (the way out, from the worktree, before the merge); and an assignment at command position whose own `$NAME` is used later on the line, saying to inline the literal. The REWRITE class is a heredoc into an interpreter, code as a string, a pipe into one, a program or a path decided at run time, a one-line compound (write the script to the scratchpad and run it by name); a line that does not tokenize, naming the quote; and, since 2026-09-18, a `$NAME` the shell expands, a `~`, a brace group the expansion refuses, a `..` path component, a bare or relative `cd`, a line break outside a quote or a heredoc, and a sequence mixing approved reads with one write — one write per Bash call, nothing else on the line (`CONVENTIONS.md` § Shell commands). After two such commands in one session it returns `ask` instead, keyed on the payload's `session_id` and `agent_id`; under `AGENTTOOLING_HEADLESS`, which `plan-runner-lib.sh` exports into every `claude -p` beside a per-pass `AGENTTOOLING_SCRATCH` directory it approves scripts from (with arguments, each confined to the project root or that directory; and `--add-dir` for it, since `acceptEdits` reaches the working directory only), it prints nothing there. Reads and tests only; writes still prompt, and every bypass the audit found is a case in `self/tests/allow-repo-commands.sh`, with the counter, the escalation and the scratch entry point in `self/tests/hook-escalation.sh`. `policy.py` is the git policy as data — the table the hook's deny reads and `bash_deny_rules()` renders the prefix rules from, so the two halves cannot drift (`self/tests/policy-table.sh`). `wire-settings.py` merges the hook entry plus `Edit` deny rules for `.git/`, `.claude/`, the virtualenvs and `node_modules/`, an `Edit` **ask** rule for `agentTooling/hooks/` itself (an attended session is prompted, a headless executor refused), and the `Bash` prefix deny rules, into the repo's `.claude/settings.json`; `sync-plans.sh` calls it, and `--self` **generates** agentTooling's own, where `--check` is byte-for-byte (committed at `.claude/settings.json` here, checked by `self/gate.sh`). See `hooks/README.md`. |
| `templates/` | Source for the generated `plans/` stubs, plus the `PROJECT_FACTS.md`, `BACKLOG.md`, `gate.sh`, `pr.sh`, `worktree-setup.sh` and `open-session.sh` skeletons. Edited here, never in the consuming repo. The last six are seeded once and then repo-owned, and each carries a `# template-version:` line recorded with its content hash in `templates/plans/TEMPLATE_VERSIONS` (`self/tests/template-versions.sh` keeps the two honest; `pr.sh` is at 4, which is the version whose `--merge-request` entry point `feature-close.sh` needs). `open-session.sh` is what `feature-start.sh --open` runs to put a coordinator session inside the new worktree; its seeded body opens a Terminal.app window, and swapping that for a tmux window or an editor is exactly why it is repo-owned. |

### Self-hosting

| File | What it is |
|---|---|
| `self/` | agentTooling's own plan corpus — features, `PROJECT_FACTS.md`, `gate.sh`, `pr.sh`, and the behavioural checks in `self/tests/` — drained by `--self`. See `self/README.md`. |
| `.claude/settings.json` | This checkout's own permission policy — the `PreToolUse` hook entry, the `Edit` and `Bash` deny rules and the `hooks/` ask rule — **generated** by `hooks/wire-settings.py --self --write`, never by hand, and kept honest by a blocking `self/gate.sh` check that compares it byte for byte with a fresh write, so an added rule fails it as surely as a missing one. Committed, because a `git worktree` inherits no `.claude/` of its own. It ships with the subtree like every other file here; a consuming repo's own copy lives at *its* root and is written by `sync-plans.sh`. |

Requires `claude` and `jq` on `PATH`. The runners check both at startup and exit 127
if either is missing — `jq` in particular would otherwise fail silently, since both of
its call sites suppress stderr, leaving an empty progress log and no terminal output
while plans still got filed as complete.

## Installing into a repo

**Mount at `agentTooling/`, exactly one level below the repo root.** The runners derive
`REPO_DIR` as `$SCRIPT_DIR/..` and the plan queue as
`$REPO_DIR/plans/features/<slug>/{auto,verify,review}`. Mounting deeper
(`tooling/agentTooling/`) silently resolves `REPO_DIR` to the wrong directory — `claude`
then runs from a subdirectory and the queue is never found. The scripts under
`analysis/` inherit the same constraint one level deeper (`parents[2]` from the script
file); see `analysis/README.md` → Where to run them.

```bash
git subtree add --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

Then, in the consuming repo:

**1. Import the conventions from the root `CLAUDE.md`.** Keep that file thin — the
import plus whatever is genuinely project-specific:

```markdown
@agentTooling/CONVENTIONS.md

## Project-specific examples

[real field lists and file paths for README Rules 1 and 2, build/test commands]
```

Relative imports resolve against the file containing them, so `@agentTooling/CONVENTIONS.md`
is correct from a root `CLAUDE.md`. Paths in backticks are not imported, so
`` `@agentTooling/CONVENTIONS.md` `` stays literal text when you want to mention it.

**2. Nothing to do — `sync-plans.sh` writes `plans/.gitignore`** in step 3, covering the
per-level gate reports, the runners' raw event streams and the batch's live review
verdict (`gate-report*.txt`, `**/*.stream.jsonl`, `**/*.logfifo`, `/review-report.md`).
This used to be a hand-maintained block in the repo's root `.gitignore`; equivalent
root-level patterns from an earlier install are harmless and can go.

**3. Create `plans/`:**

```bash
./agentTooling/sync-plans.sh
```

The first run ends `plans/ needs attention: 1 item(s).` and exits 1 — the freshly seeded
`plans/PROJECT_FACTS.md` is still the skeleton. That is the report doing its job, not a
failure; filling the file makes the run exit 0.

That creates `features/`, `interactive/`, writes their README/template stubs, and seeds
`plans/PROJECT_FACTS.md`, `plans/BACKLOG.md`, `plans/gate.sh`, `plans/pr.sh`,
`plans/worktree-setup.sh` and `plans/open-session.sh` from the skeletons. `BACKLOG.md` ships empty and stays that
way until a feature leaves something behind — an exclusion that is real work, a review
escalation not taken, a defect found and not fixed (`AGENT_PLANS.md` → "The feature
manifest"). `pr.sh` opens the PR when `feature-close.sh` closes a clean round, from the
feature's own branch against the base its manifest records (`main` unless the feature was
stacked), and — called again as `pr.sh --merge-request <slug>`, after the cost record has
been pushed — asks the forge to merge under `PR_AUTO_MERGE`; the two entry points are why
it is at `template-version: 4`. Check its forge CLI (`gh` by default) before relying on
it; it is repo-owned precisely so a non-GitHub repo can swap that out. `worktree-setup.sh` ships as a no-op skeleton and is
where this repo's per-worktree setup goes — a venv, `npm install`, a dev port —
because `feature-start.sh` runs it inside every new feature worktree
(`LIFECYCLE.md`). `open-session.sh` is the other repo-owned hook that script runs — with
`--open`, and with the worktree path as its only argument — to launch the coordinator
session inside the worktree; it ships opening a Terminal.app window running `claude`, and
is the one file in this subtree where a `cd <path> && <command>` string is allowed,
because it is text for a human terminal rather than a Bash tool call. A feature's own queue state
directories (`incomplete/`, `inprogress/`, `complete/`, `failed/`, under
`features/<slug>/auto/`, `.../verify/` and `.../review/`) are not created here — git
doesn't track empty directories, and the runners make them on first use.

Sync rather than a one-time copy because the stubs are pointers *into this directory*.
Rename the subtree prefix or restructure the queue, and every hand-copied stub in every
repo silently goes stale. Re-running the script is the fix; it overwrites the five
generated stubs unconditionally, which is safe because none of them contain
repo-specific content — and never touches the five repo-owned files, which is why a
`BACKLOG.md` entry or a filled `PROJECT_FACTS.md` survives every pull.

**4. Fill in `plans/PROJECT_FACTS.md`.** It ships as a list of prompts. It holds the
repo-specific facts that plans must pin — where generated types live, API route
templates, the test command, naming gotchas — so a plan author copies from one place
instead of rediscovering them per batch. This is `AGENT_PLANS.md` → "Pin the facts
executors would otherwise hunt for" applied to the repo as a whole. The README stubs
need no editing; they point at `RUNNER.md` for the execution model, which is why that
model is documented once rather than restated per repo.

You're ready: author plans per `AGENT_PLANS.md` into
`plans/features/<slug>/auto/incomplete/`, then run the batch.

## What stays in the consuming repo

Everything under `plans/` — `features/`, `interactive/`, the plan corpus and
its execution history, `PROJECT_FACTS.md`, `BACKLOG.md`, and `plans/README.md`. Only the shared
machinery and doctrine live here. There are two separate corpora: everything under the
consuming repo's `plans/` is that repo's own, and everything under `agentTooling/self/`
is the harness's own and ships with the subtree.

## Running

From the consuming repo's root:

```bash
./agentTooling/run-batch.sh      # build, verify, review — and the close on a clean round
./agentTooling/run-plans.sh      # build pass only
./agentTooling/run-verify.sh     # verify pass only
./agentTooling/run-review.sh     # review pass only: the round's verdict, and nothing after it
./agentTooling/feature-close.sh <slug>   # PR, capture, merge request — from the worktree
./agentTooling/run-batch.sh --self <slug>    # build + verify + review + close, on agentTooling itself
./agentTooling/run-verify.sh --up-to 05 <slug>   # only the level-verify plans numbered ≤ 05
```

`--self` goes first, before the optional slug. See `RUNNER.md` → "Self-hosted mode".

All three runners are resumable: an interrupted plan is left in `inprogress/` and picked
up on the next run. See `RUNNER.md` for the full execution model — state folders,
resume phases, what the progress and `.stream.jsonl` logs contain, and how to read a
failure.

## Updating

Pull the latest into a repo:

```bash
./agentTooling/update.sh
```

This runs `git subtree pull --squash` and then the freshly pulled `sync-plans.sh`.

**Always run `sync-plans.sh` after a pull.** The pull updates this directory; it does
not touch the generated stubs in `plans/`, which point back here. Skipping it leaves
them pointing at whatever the layout used to be — and a stale pointer fails silently,
since nothing validates that a README's paths still resolve.

**Feature worktrees live inside the checkout**, at `.worktrees/<slug>` (`LIFECYCLE.md`),
kept out of git by an entry `feature-start.sh` appends to `.git/info/exclude` — nothing
to commit, and nothing a pull can conflict with. Anything that walks the checkout will
see them, though: scope a linter or test runner to the repo's own directories rather than
to `.`, and know that `git clean -fdx` skips a live worktree as a nested repository while
`git clean -ffdx` — two `-f`s — deletes it. A feature started before this layout keeps
its sibling `<repo>-<slug>`.

`sync-plans.sh` ends with a report on the repo-owned files. `sync-plans.sh --check` gives the same report without writing. A `DRIFT` line names a script whose `template-version` is behind the template's and points at the hand-merge sections below.

Push a fix made in a consuming repo back upstream, then pull it straight back:

```bash
git subtree push --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main
git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

**The pull after a push is not redundant.** `subtree push` sends commits upstream but
writes nothing locally, so the repo's recorded split — the `git-subtree-split:` trailer
naming the upstream commit this directory last matched — stays where it was before the
push. The pull records the new one. It changes no files, since the content is already
what you just pushed.

Skip it and the *next* push fails, because subtree rebuilds the branch it pushes from
the recorded split. From a stale one, that branch omits everything upstream gained since
— so the tip it offers is behind the remote and git rejects it:

```
error: failed to push some refs
hint: Updates were rejected because a pushed branch tip is behind its remote counterpart.
```

The hint is misleading here: `git pull` is not the fix, and neither is force-pushing —
the content is already in sync, only the pointer is stale. Run the `subtree pull` above
to record the current split, then push again.

A squash merge is the usual way this pointer gets left behind. It preserves the trailers
from the commits it flattens, so pulls keep working, but the split it records is whatever
the branch last pulled — not what a `subtree push` from that branch sent upstream
afterward.

Use `--squash` consistently. Mixing squashed and unsquashed pulls on the same
prefix produces conflicts that are tedious to unpick.

**All three subtree commands require a clean working tree** and abort with
`fatal: working tree has modifications. Cannot add.` otherwise — including for changes
in files that have nothing to do with this prefix. Commit or stash first. A tracked
`.DS_Store` is a common culprit on macOS.

**Renaming the prefix** is not a `git mv`: subtree records the directory in a
`git-subtree-dir:` trailer on its commits, and a moved directory leaves that trailer
pointing at the old path, so the next pull can't find its baseline. Remove the
directory, commit, then `subtree add` at the new prefix.

### Adopting feature-branch PRs

A repo whose `plans/pr.sh` still cuts a `review/<slug>` branch of its own opens the PR
from the wrong head: the whole feature already ran on its own branch, in the worktree
`feature-start.sh` made (`LIFECYCLE.md`). `sync-plans.sh` cannot fix it — `pr.sh` is
repo-owned and never overwritten — so hand-merge these two edits from
`templates/plans/pr.sh`:

1. Delete the branch step. The head is `git rev-parse --abbrev-ref HEAD`, whatever it
   is; nothing here creates a branch, and `BRANCH_PREFIX` and `REVIEW_BRANCH` go with it.
2. Read the base as `BASE_BRANCH="${FEATURE_BASE:-${BASE_BRANCH:-$FALLBACK_BASE}}"` and
   refuse when the current branch *is* that base, since there is then no feature branch
   to open a PR from — `feature-close.sh` exports `FEATURE_BASE` from the manifest's
   `base`, so a stacked feature targets the one beneath it and the forge retargets that
   PR when it merges.

`sync-plans.sh --check` reports the un-merged copy as `DRIFT plans/pr.sh (template-version 0 < 3; …)`; after merging these and the edit in the next section, add the line `# template-version: 3` directly after the script's `set -…` line so the check goes quiet.

### Adopting capture on the branch

`feature-capture.sh` runs right after `plans/pr.sh` on a clean round, so the cost records
are a second commit on the feature branch and there is nothing to run after the merge
(`LIFECYCLE.md` → steps 5 and 6). Version 3 is where that landed, with `run-review.sh`
calling both; the section below moves them to `feature-close.sh`, which is what calls
them now. A `plans/pr.sh` at template-version 2 keeps working unchanged — it still commits
the pass's work, pushes and opens the PR, and the capture commits after it. Version 3 adds
one opt-in, which is the only hand-merge:

1. Above the repo-specific section, `AUTO_MERGE="${PR_AUTO_MERGE:-0}"`.
2. In it, `AUTO_MERGE_ON`, `AUTO_MERGE_ARGS=(--auto --merge --delete-branch)` (a merge commit, never a squash — the prune and the post-merge capture test ancestry) and the
   `auto_merge` function from `templates/plans/pr.sh`, called after the "already open"
   line and after the PR is created. `PR_AUTO_MERGE=1` then asks the forge to merge once
   the PR's requirements pass; unset, nothing changes. Turn it on only where the base
   requires a status check — otherwise the forge may merge before the capture's commit is
   pushed.

`sync-plans.sh --check` reports a version-2 copy as `DRIFT plans/pr.sh (template-version 2 < 3; …)`; after merging, change its `# template-version:` line to `3`. A feature that merged before this pull and was never closed is captured from the primary with `feature-capture.sh`, where it writes locally and commits nothing.

### Adopting rounds and the close

`run-review.sh` no longer opens the PR or captures: it records the round's verdict — the
first line of `plans/review-report.md`, `Verdict: clean` or `Verdict: escalated` — commits
its pass as `<slug>: review round N`, and stops. `feature-close.sh` does the rest, in an
order that matters (`LIFECYCLE.md` → step 6), and refuses any tree a clean review has not
judged. Nothing in a consuming repo has to change for that; the one hand-merge is
`plans/pr.sh`, from version 3 to **4**:

1. Above the repo-specific section, accept the second entry point:
   `MERGE_REQUEST=0` and `if [[ "${1:-}" == "--merge-request" ]]; then MERGE_REQUEST=1; shift; fi`
   before `SLUG=`.
2. In it, delete both `auto_merge` calls from the open path (after the "already open" line
   and after the PR is created) and add, right after `current_branch` is resolved,
   `if (( MERGE_REQUEST )); then auto_merge; exit 0; fi`. Give `auto_merge`'s off-branch a
   line saying no merge was requested, since it is now the only caller's whole output.

`PR_AUTO_MERGE=1` then means "merge once the PR's requirements pass", asked for by the
close *after* the cost commit is pushed — which is why the flag no longer needs a required
status check to be safe. A copy left at 3 keeps working: the close says once that it found
no `--merge-request` entry point and skips the request, and `sync-plans.sh --check`
reports the drift as `DRIFT plans/pr.sh (template-version 3 < 4; …)`.

### Adopting levels and tiered gates

A repo whose `plans/gate.sh` predates level sentinels needs these once. `sync-plans.sh`
cannot do it: the gate is repo-owned and never overwritten, and a gate that ignores the
level contract fails silently — sentinels still run, but every level reads as unlabelled
and a skipped check reads as a pass.

1. `sync-plans.sh` as always.
2. Hand-merge the gate edits from `templates/plans/gate.sh` into `plans/gate.sh`: accept
   `$1` as a level label, copy the report to `gate-report.<label>.txt`, add `record_skip`
   and the SKIPPED verdict, honour `GATE_DEFERRED` in `_record`, and turn
   `GATE_EXPECTED_RED` into test-runner ignore flags.
3. Nothing to do for the gitignore — `sync-plans.sh` writes `plans/.gitignore`, whose
   `gate-report*.txt` already covers the per-level reports; a root-level
   `plans/gate-report.txt` from an earlier install is harmless and can go.
4. Author the next feature in the shape `AGENT_PLANS.md` → "Levels" describes, giving each
   sentinel its `expected-red:` / `defer:` lines.

`sync-plans.sh --check` reports the un-merged copy as `DRIFT plans/gate.sh (template-version 0 < 2; …)`; after merging, add the line `# template-version: 2` directly after the script's `set -…` line so the check goes quiet.
