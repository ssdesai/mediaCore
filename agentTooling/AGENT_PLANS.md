# AGENT_PLANS.md

Instructions for Claude when asked to generate plans for the delegated-execution workflow: **build plans** in `plans/features/<slug>/auto/incomplete/` (run unattended by `run-plans.sh`, no bash); then **verify plans** in `plans/features/<slug>/verify/` (run afterward by `run-verify.sh` under a wider permission scope — see "Verify plans" below); and optionally, last, a **review plan** in `plans/features/<slug>/review/` (run by `run-review.sh` after verify — see "Review plans" below).

## Precedence

This file governs plan-creation behavior and overrides `CONVENTIONS.md` where they conflict — specifically, the "never Glob/Grep for discovery" rule and the requirement to traverse *every ancestor* README before *every edit*. READMEs are still the cheap index for bounding scope — see step 2 below. `CONVENTIONS.md` still applies as source-of-truth for codebase conventions (code style, named constants, etc.) when you're writing the actual code inside plan bodies.

## Which corpus a feature belongs in

Read the diff, not the cwd. A feature whose changes are confined to `agentTooling/` is
an agentTooling feature: its manifest and plans go in `agentTooling/self/features/<slug>/`
and it is run with `--self`. Everything else belongs in the consuming repo's
`plans/features/<slug>/`. A feature that genuinely spans both is a sign the harness
change should be split out and landed first.

Throughout this file, `plans/features/<slug>/` is written for the ordinary case. Under
`--self` read it as `agentTooling/self/features/<slug>/`; nothing else about authoring a
plan changes. The facts to pin come from `agentTooling/self/PROJECT_FACTS.md` instead of
`plans/PROJECT_FACTS.md`, and the gate report a verify plan reads is
`self/gate-report.txt` instead of `plans/gate-report.txt`.

## Before generating any plan

1. **Confirm scope with me, don't explore.** If the file list isn't obvious from my request, ask. Do not Glob/Grep/Read broadly to "discover what's involved" — that's the most expensive thing you can do in plan-creation. A 30-second question to me is cheaper than reading 15 files.

2. **Orient via READMEs before delegating.** When scope is uncertain, that's the trigger to *orient*, not to delegate. Read the root README and follow its pointers down to the relevant folder READMEs — that's the cheap index that bounds the footprint. This is targeted index-reading, not the broad discovery step 1 forbids. Only after orienting do you decide the next move: a small footprint you can read directly, or a broad one worth delegating. Orienting first is asymmetric — worst case it adds a few cheap reads, best case it eliminates the subagent entirely.

3. **Delegate only when orientation isn't enough.** When orientation reveals broad or cross-cutting scope, or the READMEs are too thin to locate the work, spawn an Explore or Plan subagent with a tight brief ("list the files that implement X and the pattern they use, under 400 words"). Do not pull those files into your own context. You only need the subagent's summary. If the subagent returns a thin or confusing summary, stop and ask me for the file list rather than reading the files yourself in the main context. Don't delegate scope-discovery you could finish with a few README reads.

4. **Push back on plans that shouldn't exist.** Tell me explicitly if:
   - The change is a trivial single-file edit under 20 LoC → I should do it myself, not plan it. "Trivial" means mechanical: renames, one-liner additions, cosmetic tweaks. Non-trivial changes (schema/migrations, auth, anything requiring judgment or touching shared state) deserve a plan regardless of line count.
   - A proposed plan is just README updates → fold into the code plan that owns them, don't make a dedicated README plan. CONVENTIONS.md already mandates README updates during any change.
   - A proposed plan has no code changes, only audit/verification → it's a **verify plan** (automated post-build test/check pass; see "Verify plans"), a **review plan** (post-verify judgment on the diff; see "Review plans"), or an **interactive plan** (bash-heavy step a human runs by hand) — either way, not `plans/auto/`. Which of the first two: if answering it means *running* something, it's verify; if answering it means *reading* the change, it's review.

## Context budget (hard rule)

You may read at most **3 implementation files** (non-README) into your own context while authoring a plan. Before opening a 4th, stop — the scope is broad by definition. Spawn one Explore/Plan subagent to read the rest and return signatures + line ranges, and author from that summary. READMEs are the cheap index and don't count against this budget.

**Declare before you read.** Before opening the first non-README file, state one line: how many files the plan will touch and how many layers it spans, then the route — `≤3 files / single layer → read directly`, else `→ delegate`. Writing this declaration is mandatory; skipping it is the failure mode — incremental "just one more file" reads are how the broad-scope trigger gets evaded, each read feeling small while the total blows past the budget. A change spanning ≥2 layers (e.g. client + server) is delegate-by-default regardless of file count.

## Routing for cost

Plan generation has two phases. Match each to the right model.

- **Decisions / structure** (plan splitting, data-flow choices, edge-case spotting, resolving spec gaps) — worth Opus.
- **Filling in literal code** (CRUD signatures with one new arg, route prefix transforms, README bullets, repeating a settled pattern across N files) — don't burn Opus on this.

When the bulk of a plan is the second phase: hand it to the **Plan subagent** (decisions + Explore output already settled) so the parent context isn't paying for the expansion, or ask the user to drop to Sonnet / `/fast`.

**Tie the model choice to the scope declaration above.** If the declared scope spans ≥2 layers or is majority mechanical expansion (mirror-the-pattern across files), the authoring belongs on a Plan subagent or Sonnet / `/fast` — flag this to the user before expanding. Do not silently author the expansion on Opus; the decisions are the only part that earns Opus.

## Sizing plans for executor cost

The section above governs *authoring* cost. This one governs *execution* cost, which is larger and driven by something else entirely.

An executor is billed the sum of its context over every turn, and context only grows within a session — every file it reads and every line it writes is re-sent as input on all remaining turns. A plan's cost is therefore **superlinear in its turn count**, not proportional to the code it produces. Measured on two plans from one batch (`usage.json`, cached input): 31 turns read 1.0M, while 65 turns read 10.3M. 2.1× the turns, 10× the cached input.

So **two plans of N turns cost far less than one plan of 2N**. Splitting is the largest available lever on execution cost, but it is not free and not unlimited:

- Output tokens are **irreducible** — the same code gets written either way, and output is ~30% of a tests plan's bill.
- Each split pays a fresh **cache-creation** charge to load its base context, billed at 12.5× the cache-read rate. This sets a floor: a restart costs ~$0.27, while a fresh context saves ~$0.03/turn against a ballooned one, so **a split must run more than ~10 turns to pay for itself**. Measured — a plan resumed after an interruption did its last 7 turns for $0.54, where continuing in the original session would have cost ~$0.47. Shards below that line are worse than not splitting.

Splitting attacks only the cached-input term. Re-measured across this repo's 46 tests-plan sessions by fitting `cache_read ≈ a·T + b·T²/2` (a = base context re-sent each turn, b = context growth per turn): tests plans fit `30,478·T + 2,133·T²/2`, R² = 0.91 — the quadratic term is real and dominant past ~40 turns. Splitting halves it, so the saving is `b·T²/4` cached-input tokens minus one fresh cache-creation charge. In money: **~18% off a 100-turn plan and ~6% off a 65-turn one** — smaller than the 40%/15% first estimated from a two-plan comparison, but the same direction. The win scales with how far the monolith's context balloons; below the threshold below, don't bother.

### Split by volume of new code, not by file count

The predictor is how many lines of *new* code one session writes. Adding cases to an existing file is cheap; creating files from scratch is not. Split any plan expected to produce more than **~300 lines of new code**.

Tests plans are where this bites, because a batch's tests are its largest block of new code and are habitually authored as one plan. Measured across this repo: the monolithic ones produced 800–950 lines in a single session, ran 65–100 turns, cost $6–8.50 each, and were ~50% of their whole feature's bill. Plans producing 150–300 lines ran 23–38 turns and cost $0.70–1.60. Same repo, same model, same work.

At authoring time, estimate from the cases you enumerate — a pytest case here averages ~25–30 lines. **More than ~12 enumerated cases means split.**

### Splitting tests plans

- One plan per test file: `NN-tests-<module>-MODEL.md`, never one `NN-tests-MODEL.md` covering the batch. A single file needing more than ~12 cases splits again, by behaviour group.
- **Shared `conftest.py` fixtures belong to the lowest-numbered tests plan in the batch**, which specifies them; the rest carry `Depends on: NN-tests-<first>.md` and use them by name. Two plans independently adding builders to `conftest.py` is the one failure mode splitting introduces — naming the owner prevents it.
- Each split plan pins only the facts its own file needs. Copying the batch's whole pinned-facts block into every split reinstates the context you just removed.

### Do not split verify plans — measured, and the answer is no

A verify plan looks like exactly the monolith this section is about: one file, one session, 60-odd turns, reading broadly. The obvious conclusion is that it should be split the same way. **The data says it should not.**

Fitting the same `cache_read ≈ a·T + b·T²/2` model over this repo's 32 verify sessions (11–110 turns, $83.96 total, mean $2.62, mean 61 turns) gives `78,945·T − 162·T²/2`, R² = 0.82. **The quadratic term is negative** — verify sessions do not balloon. Dropping the two budget-capped runs changes nothing (`78,399·T − 167·T²/2`). Corroborating: `corr(turns, $/turn)` is +0.12 for verify against +0.39 for tests plans and +0.45 for other auto plans; and the corpus's longest verify run (110 turns) read 7.1M cached tokens where a tests plan of that length would have read 16.3M.

The shape differs because the work differs. A tests plan's turns each *write* 25–30 lines that are re-sent on every later turn (mean output 1,134 tok/turn); a verify pass runs shell commands and reads output it mostly discards (449 tok/turn) against a base context that is already large at turn one — hence the ~79K constant, the largest in the corpus.

So splitting verify saves `b·T²/4` ≈ **nothing**, while adding one fresh cache-creation charge: mean 115,830 tokens, **$0.43 at sonnet's cache-write rate — 17% of a mean verify run, spent before the second session does any work.** Two verify plans cost more than one, not less.

The lever for verify is **turns, not sessions**: its bill is ~75% cached input and linear in turn count (`corr(turns, cost)` = +0.81, `corr(bash calls, cost)` = +0.72, `corr(edits, cost)` = +0.69). That is what the rules in "Verify plans" below already attack — don't re-run the gate's mechanical checks, don't build a world, read the tests before asking for an observation, budget the fix loop. Tightening the brief is the whole optimisation; adding a second verify plan is a 17% surcharge for nothing.

### Point the read list at READMEs, not sources

Every plan names the files its executor may read. That instruction gets ignored when the pinned facts don't cover a shape the executor needs: measured, a plan saying "read exactly these three files, and no others" produced 26 source reads, seven of them model modules opened purely to learn constructor fields.

Name the **README** carrying those fields rather than the modules. CONVENTIONS.md Rule 1 requires every cross-module shape to have a full field list in its folder's README, so the answer is already written in one place instead of spread across seven files. Do not copy those field lists into `PROJECT_FACTS.md` — that duplicates a canonical source into a third place that will rot.

## Routing the Explore subagent

Explore inherits the parent's model unless overridden. Default is overkill for read-and-summarize.

- **Quick lookups** (read N known files, paste signatures back) → `model: "haiku"`, `thoroughness: "quick"`.
- **Pattern discovery in one area** (find the convention for X across a folder) → `model: "sonnet"`, `thoroughness: "medium"`.
- **Architecture / cross-cutting** (how does flow X work end-to-end?) → inherit parent or `sonnet`, `thoroughness: "very thorough"`.

Pick deliberately; the default ("inherit parent, no thoroughness specified") is the worst path.

## Plan file format

- One plan per file, in `plans/features/<slug>/auto/incomplete/`.
- Filename convention: `NN-description-MODEL.md` where `NN` is a two-digit order number and `MODEL` is one of `haiku`, `sonnet`, or `opus`. Examples: `01-backend-haiku.md`, `02-frontend-sonnet.md`. `run-plans.sh` parses the trailing segment to pick the model for that plan.
- `NN-gate.md` is a sentinel, not a plan — no model suffix, no content required (an empty
  file works; a one-line comment naming the level is better), never listed in the
  manifest's `plans[]`, never sent to an executor.
- A sentinel SHOULD say what its level does not own, or its gate is red by design and the
  tier ladder runs on a green level. Two directive lines, both optional:
  `expected-red: tests/test_acceptance_x.py tests/test_api_*.py` (globs the gate's test run
  ignores at this level — plan 01's file and every higher level's tests plan) and
  `defer: npm run typecheck, npm run build` (gate section labels, as written in the repo's
  `gate.sh`, recorded DEFERRED and not run). The manifest's Levels table "Must be green"
  column is the same information in prose; write the sentinel from it. The final gate owns
  everything and ignores both.
- **Numbering is per-feature, not global.** `NN` starts at `01` for a brand-new feature. For an additional batch on an existing feature, continue from one past the highest number already used anywhere under that feature's own `auto/` and `verify/` trees (`incomplete/`, `inprogress/`, `complete/`, `failed/`) — never from a count of plans in other features. `list_plans` in `plan-runner-lib.sh` globs one feature's queue directory at a time and never compares across features, so this needs no executor change: two different features may legitimately reuse the same `NN`.
- **If one feature's own numbering ever passes 99**, every plan filename in that feature's `auto/` and `verify/` trees must be re-padded to the same digit count (`001`, not a mix of `05` and `101`) — `list_plans`' glob sorts lexically, so mismatched digit counts sort out of order. Resetting per feature (previous bullet) is what makes this rare: it now takes one feature accumulating 100 plans of its own, not the whole repo's plan history combined.
- Because numbers now repeat across features, qualify any cross-feature reference with the slug (`gui-import-extract-review/05`, not bare `05`) — in commit messages, `PROJECT_FACTS.md`, or a verify plan that names another feature's work.
- Default to `haiku`. Use `sonnet` only when the change requires judgment (state fan-out, cross-file coordination, tricky refactors). Reserve `opus` for rare cases that need heavy reasoning.
- Each plan must be self-contained — `run-plans.sh` workers have no context from prior plans.
- Length target: if the change is N lines of code, the plan should be ~N lines. A 15 LoC change should not have 40 lines of prose justification.
- Size cap: a plan producing more than ~300 lines of new code splits. See "Sizing plans for executor cost".

## Plan content

Each plan must have, in this order:

1. **Feature header**, directly under the title: the feature slug, this plan's position
   in the batch (`plan N of M`), and one or two sentences on what the whole feature
   does. Every plan in the batch repeats this — executors cold-start with no context
   from sibling plans, so the slug is both the machine-readable grouping key cost
   reports key off of and the only thing telling a reader six months later what this
   plan was part of.
2. **One-sentence summary** at the top.
3. **Dependency note** (only if needed): "Depends on: 01-*.md" or "Independent of other plans."
4. **File list** — every path to create/modify/delete. No prose descriptions of "what's involved."
5. **Per-file changes** — for each file, paste the exact code to add or the exact diff. Not prose.

## The feature manifest

One `plans/features/<slug>/README.md` per feature — written once, at plan-generation
time, by whoever authors the batch. Never written or edited by a build, verify or
review executor.

It holds what does not belong in every individual plan: the feature's goal, a table of
every plan in the batch and what it does, and what was deliberately excluded and why.
Plans repeat only the one-line feature header (see item 1 above); the manifest is where
the full picture lives. The plans themselves live in that feature's own `auto/`,
`verify/`, `review/`, and `interactive/` subfolders —
`plans/features/<slug>/auto/incomplete/`, etc. — never in a shared top-level queue.

The manifest ends with a machine-readable fence:

```json
{
  "slug": "plan-analytics",
  "plans": ["48-feature-scoped-runner-sonnet", "57-verify-sonnet", "58-review-opus"],
  "branches": ["browseImages"],
  "session_window": {"from": "2026-07-30T15:49:00Z", "to": "2026-07-30T19:03:00Z"},
  "exclude_sessions": []
}
```

- `slug` — kebab-case, stable for the life of the feature; cost reports key off it.
- `plans` — every plan stem in the batch, **across all queues** — build plans, the
  verify plan, and the review plan alike. `analysis/report.py` rolls up cost by walking
  this list, so a plan omitted here runs and bills but appears in no cost record, and
  the feature's total silently under-reports. It is the one field whose omission is
  invisible in the output rather than flagged.
- `branches` — every git branch the work happened on, **written exactly as
  `git branch --show-current` reports it**. This is matched literally against the
  `gitBranch` recorded in each session transcript, so any embellishment — a `ssdesai/`
  or other owner prefix the branch never actually carried, a renamed branch, a guess —
  matches nothing, and every session on it goes uncounted. The feature then reports
  `$0.00`, which reads as "planning was free" rather than "this manifest is wrong";
  that failure held five features at zero before anything noticed.
  `analysis/capture_planning.py` now warns when a declared branch matches no transcript,
  but the warning cannot tell a wrong name from expired transcripts, so it is a prompt
  to check rather than a verdict. Copy the name, don't retype it.
  A branch that is renamed or deleted mid-feature keeps its old name in the transcripts
  already written — list **both** names rather than replacing one with the other.
- `session_window` — optional. One branch can host several features in sequence — this
  repo's `browseImages` branch hosted three — so `branches` alone over-attributes
  planning cost to whichever feature you're asking about. `session_window` narrows
  attribution to a time range, compared against each session's **start**, `from`
  inclusive and `to` exclusive. Matching is atomic: a session is claimed whole or not at
  all, so a session that spans two features cannot be split between them afterwards.

  **End every bound with `Z`.** A bound that states no offset is read as UTC, and the
  natural place to find a timestamp is `git log`, which prints **local** time — so a
  value copied from there and pasted bare is silently off by your UTC offset, four hours
  in US Eastern. That is more than the gap between consecutive features, so it hands
  sessions to the wrong one. If you do mean local, spell the offset out
  (`2026-07-17T18:00:00-04:00`) and it is converted; `analysis/capture_planning.py`
  warns on any bound that declares no zone. Transcript timestamps are UTC, so a `Z`
  bound compares against them directly.

  **Use full ISO 8601 timestamps, not bare dates.** Consecutive features are commonly
  minutes apart, and a single planning session can straddle midnight — in this repo the
  three `browseImages` features' sessions ran `07-29T18:29`–`21:34`,
  `07-29T21:36`–`07-30T15:47`, and `07-30T15:51`–onward, where every date-level boundary
  either drops a real session or double-counts one. Derive each bound from the gap between
  the adjacent sessions' actual timestamps rather than picking a plausible day.

  **Set `to` as soon as the feature is done.** `"to": null` is correct only while the
  feature is still being planned. Two open-ended windows on a shared branch each claim
  the other's sessions, and the cost lands in both totals with nothing visibly wrong —
  this is not hypothetical, it is how `discogs-field-reconciliation` and
  `discogs-provenance-and-packaging` came to report the same $37.14 apiece.
  `analysis/capture_planning.py` now warns when two manifests share a branch *and* their
  windows intersect; a `to` bound is how you answer it. Because `to` is exclusive, the
  next feature's `from` may be the same instant — chained windows are exactly disjoint.
- `exclude_sessions` — optional escape hatch for sessions inside that window that still
  belong to a different feature. Both `session_window` and `exclude_sessions` are
  optional and usually absent.
- `subagents` — optional. Agent ids (`agent-<id>.jsonl` under the parent session's
  `subagents/` directory) to claim outright. Needed only when the delegate's parent was
  not on the feature's branch — a plan author spawned from a coordinator sitting on
  `main` inherits `main` as its `gitBranch` and can never be branch-matched. A delegate
  whose parent is selected is claimed with it, by window, without a pin. A pin outranks
  an `exclude_sessions` entry on its parent (runner sessions excepted), so a coordinator
  can be excluded from a feature while its architect is kept. A pin is resolved across
  every project directory, since a delegate's transcript is filed under its parent's
  cwd — a coordinator in another repo — not under the repo it worked on.
  `capture_planning.py --list-subagents [--everywhere|--unclaimed]` prints the ids
  with each one's cost and brief; `--unclaimed` is the ones no feature has claimed
  yet. Claims are ledgered per machine, and one transcript claimed by two features
  refuses the second capture. Pinning onto a feature whose own sessions have expired
  needs `--carry-lost`, which keeps the frozen entries and adds the pin.
- `exclude_subagents` — optional. The opposite of a pin: delegates of a selected
  session that another feature owns, so a coordinator's manifest can carry the
  coordinator's context cost without also claiming the architect the arm pins.

**The windows are a patch over a workflow problem, not the fix for it.** Both fields exist
because one session, or one branch, held work for more than one feature. If you keep to one
session and one branch per feature, `branches` attributes correctly on its own and neither
field has to be load-bearing. Prefer that; reach for `session_window` when the history is
already made.

A batch built as levels (see "Levels: tests first, gate between layers") adds two optional
tables to the manifest's human-readable part; the JSON fence above is unchanged — sentinels
are not plans and never appear in `plans[]`. **Levels** —
`| Level | Plans | Sentinel | Level-verify | Must be green |`, one row per level; the last
column names gate sections. **Contracts across levels** —
`| Value / identifier | Produced by (plan, file:line) | Consumed by (plan, file:line) |
Asserted by |`, one row per thing that crosses a level boundary; the last column is a test in
plan 01 or in a level tests plan, and an empty last column is a finding at authoring time.

The contracts table has one more column, **Fixture** — the
`tests/fixtures/contracts/*.json` file the producing level's test writes and the consuming
level's tests load (Levels item 9) — and **Asserted by** names a test on *each* side. An
escalation at level NN (RUNNER.md → "Red gates: the tier ladder") writes
`plans/features/<slug>/escalations/NN.md`; the review brief should tell the reviewer to
read it, because what it records is a contract the batch changed after authoring.

See `templates/plans/features/TEMPLATE.md` for the skeleton to copy.

## Writing the per-file changes

Every per-file change is one of two shapes: **paste** or **describe**. Choose deliberately — the wrong choice wastes tokens in one of two ways (Opus writing code it shouldn't, or Sonnet re-deriving what was already settled).

**Paste literal code when the answer is settled and has one right shape:**
- Alembic migrations and their data-copy SQL — boilerplate, high cost of error.
- Pydantic schemas, TypeScript interface definitions — exact field lists.
- New SQL CHECK constraints, validators, regexes.
- A three-line helper function or a small pure module.

For these, paste verbatim. Words force the executor to reinvent what's already decided.

**Hard cap on paste length.** Paste blocks max out at ~30 lines for anything that isn't a migration, schema, or pure-data constant. Beyond that, length itself is the signal: you are locking in too many decisions from a stale Explore summary. Switch to prose, even if every individual decision feels settled.

**Describe in prose when the executor needs to match surrounding code:**
- CRUD handlers, router endpoints, relationship wiring — the executor reads the real neighboring code and matches its style better than a plan-author guessing from an Explore summary.
- Component prop redesigns, import paths, fetch/auth helper usage — conventions that live in the file, not in your head.
- Anywhere you'd write "mirror the existing pattern" or "match the fetch style used elsewhere."

For these, point the executor at the reference (`mirror src/components/ThingList.tsx:45-92`) and let them read it. Do not paste skeleton code based on an Explore summary — you will get the imports, helpers, or style wrong, and the executor will apply your wrong version without checking.

**Absence of a sibling pattern is not a license to paste.** When a component, hook, or module is new-from-scratch with no direct precedent, the executor still derives style from the modules they import (types, hooks, helpers) — they read those files; you only saw an Explore summary of them. New-from-scratch components, hooks, and modules go in prose by default, with paste reserved for their settled sub-pieces (constants, types, pure helpers, CSS).

**New React component split.** Paste the constants block, type definitions, pure helpers (sort comparators, formatters), and the CSS. Describe the component signature, prop wiring, and JSX structure in prose, citing one sibling component by line range for import and prop style. Never paste a full JSX render body for a new component.

**The failure mode to avoid:** pasting a new file (model, router, component) whose imports and dependencies you only half-know. Opus time spent writing half-guessed code is strictly worse than Sonnet spending execute-time reading the real sibling files.

**Never paste code with a caveat.** If a pasted block needs a note like "fix if path differs," "match whatever is already imported," or "adjust if naming is different," delete the paste. The caveat is proof the answer isn't settled. Rewrite as prose pointing at the reference file. This is a hard rule, not a heuristic — the caveat itself is the signal, regardless of how settled the rest of the block feels.

**Other rules:**
- **Cite reference patterns by line range.** `mirror src/components/ThingList.tsx:45-92` — the executor reads just that range, not the whole file.
- **Don't restate constraints that the code already expresses.** If the function signature includes `Optional[str] = None`, you don't also need a sentence explaining that fields are optional.
- **No motivation / background sections.** The executor doesn't need the why; they need the what.

## What build executors can and can't do

`run-plans.sh` workers run in `acceptEdits` mode with no bash access. (Verify plans run under a different script *with* bash — see "Verify plans".) When writing **build** plans:

- Don't instruct them to run typecheck, tests, or dev servers — they have no bash. That check is the verify plan's job.
- Don't instruct them to "verify X works" — verification is a separate pass (a verify plan, or an interactive plan), never a build-plan step.
- Don't tell them to explore for files — every path must be listed explicitly.
- If they need to see a reference pattern, either paste it inline or cite the exact line range.

## Split work by executor capability

Auto-plan (build) executors can only create or modify file contents. Any step that requires another tool — shell commands, file deletion, package installs, schema migrations, verification, anything that touches state outside the edited files — belongs elsewhere: automated test/verification in the batch's **verify plan**, and human-run migrations/ops in a sibling `plans/features/<slug>/interactive/NN-description.md`.

When generating an auto plan, ask: *does every step here reduce to editing text in a listed file?* If no, lift the non-edit steps out — test/verification into the batch's verify plan, human-run steps into an interactive plan — and reference them in the auto plan's dependency note.

## Levels: tests first, gate between layers

Two A/Bs settled this section (`EXPERIMENTS.md` → "What the pilots established"): items
1–7 against a flat batch, then items 8–11 and the `Fixture` column against items 1–7
alone. The runner needs no switch either way — a batch containing no `NN-gate.md` behaves
exactly as it did before sentinels existed, which is what makes a levels A/B a
doctrine-only change.

1. **Plan 01 of every batch is the wanted behaviour as tests.** Black-box, top-down from
   the requirement, through the real boundaries the feature crosses (the real request
   body, the real producer of the string being compared, the real store the view reads).
   Red for the whole build; that is expected. Its assertions are the feature's
   enumeration — an "all X" in the requirement is one assertion per X *that the manifest
   does not exclude*, and the manifest's plan table says so.

   **Plan 01 is bounded by the manifest's "Excluded, and why".** Red between levels is the
   one sanctioned red; the final gate owns everything and must be green, so an assertion
   that can only go green by doing an excluded thing is an authoring contradiction, and
   the final gate is red by construction. Before finishing plan 01, walk every exclusion
   against every assertion. Narrow the assertion to what the batch *will* deliver and say
   why in a comment beside it. Measured once: a manifest excluded making two modal triggers
   focusable while plan 01 asserted "focus returns to the trigger" for all four modals;
   the batch shipped with its final gate red and needed a second batch to fix the
   assertion, not the code.
2. **A level is one layer:** its tests plan, then its build plan(s), then a sentinel
   `NN-gate.md`. Order levels bottom-up by dependency. Two or three levels per batch; five
   means the batch is too big.
3. **Level tests are white-box and cheap; plan 01 is black-box.** Leaf tests written from
   the author's own model of a shape pass against that model; only the black-box test at
   the top catches a shape the other layer cannot produce. Never let level tests stand in
   for plan 01.
4. **The sentinel runs the gate at no model cost.** Red at a boundary is normal; the point
   is that the next level's author knows, at authoring time, which gate sections must be
   green at each boundary, and says so in the optional level-verify brief.
5. **Every sentinel gets a level-verify plan, and it is tier 1 of the ladder.** A verify
   plan — bash, `sonnet`, numbered between its sentinel and the next build plan
   (`05-gate.md` → `05-level-backend-sonnet.md` in `verify/`) — whose brief names which
   gate sections must be green and which contract rows the level owns. It costs nothing
   to author (a ten-line brief) and nothing to run on a green level: **the runner skips
   it when the gate verdict is `all checks passed`**. On a red level it is the first rung
   of the tier ladder (RUNNER.md → "Red gates: the tier ladder") and the runner's prompt
   gives it one extra rule the brief must not contradict: *fix the tree to the contract,
   never the contract to the tree* — it may not rename, re-type or re-shape anything a
   plan above could be pinning, and writes `escalations/NN.md` instead when it must.
   Tier 2 is synthesized by the runner, not authored; nothing above the sentinel needs to
   anticipate it.
6. **The final verify shrinks.** Its brief is "read plan 01's test file and the level
   tests; check only what they leave uncovered." Everything in "Verify plans" still
   applies.
7. **Ran and passed, never "no failures".** A SKIPPED section in any level's gate report
   means that level is unverified, not green; `record_skip` in `gate.sh` and the verify
   prompt both say so.
8. **Across a gate, reference; never paste a prediction.** A plan above a sentinel may
   paste code only for what it creates itself. Everything it takes from a lower level —
   a signature, a field list, a route path, a fixture shape, an enum — it names by
   *file path* and tells the executor to read ("the contract is
   `tests/review/test_decisions.py` and `review/discogs.py:is_open`; read both before
   writing the route tests"). The lower level is green on disk by the time the executor
   runs; a pasted signature written before it existed is the one thing in the plan
   guaranteed to be a guess. The first pilot's single cross-layer defect (a button the
   route rejected) lived exactly in a pasted prediction. The 30-line paste cap and
   "never paste with a caveat" still apply within a level.
9. **Contract fixtures at every seam a test would otherwise mock.** The level that
   *produces* a serialized shape owns a test that writes the real thing to
   `tests/fixtures/contracts/<name>.json` (or the path `PROJECT_FACTS.md` pins); the level
   that *consumes* it loads that file in its tests instead of hand-writing the object.
   Route tests dump the response; component and store tests import it; a Playwright
   route-mock serves it. This is what makes "the lower level is clean" load-bearing —
   the upper level's test inputs were produced by verified code, so mock drift is
   impossible by construction. The manifest's contracts table gains a `Fixture` column,
   and a row with none is a finding at authoring time.
10. **An allowed-actions contract is a matrix, not a sentence.** When the contract is
    "which actions are valid in which state" (a verdict × action table, a status × edit
    rule), the contracts row enumerates every cell, and both sides assert every cell — the
    producer's route test and the consumer's component test. "Edit is offered on rows the
    route 400s" is the defect class this rule exists for; it escaped two review passes
    because the matrix was never written down.
11. **The top level's gate drives the real stack once.** Route-mocked browser tests stay
    (they are cheap and stable), but the final gate also runs the end-to-end suite against
    the real backend over a seeded collection at least once. If the repo has no such
    suite, the batch's plan 01 is where it starts.

Target shape:

```
auto/incomplete/
  01-acceptance-tests-sonnet.md      # wanted behaviour, black-box, RED until the end
  02-backend-tests-haiku.md          # level 1: tests for the pieces 01 depends on
  03-backend-schema-haiku.md         # level 1: build
  04-backend-service-sonnet.md       # level 1: build
  05-gate.md                         # sentinel — gate runs here, labelled "05"
  06-frontend-tests-haiku.md         # level 2
  07-frontend-store-haiku.md         # level 2
  08-frontend-view-sonnet.md         # level 2
  09-gate.md                         # sentinel — gate runs here, labelled "09"
verify/incomplete/
  05-level-backend-sonnet.md         # optional level-verify, drained after 05-gate
  10-verify-sonnet.md                # the final verify, smaller than before
review/incomplete/
  11-review-opus.md
```

## Verify plans

Build plans run under `run-plans.sh` with no bash — they can't run what they wrote, so latent defects (typecheck breaks, failing assertions) survive until something exercises the code. The **last** plans authored for a batch close that gap: verify plans, a post-build pass that actually runs the work and checks it.

- **Run by a separate script, not `run-plans.sh`.** Verify plans live in `plans/features/<slug>/verify/` and run afterward under `run-verify.sh`, which scopes permissions differently: bash enabled, a high-level model, and latitude to read broadly, run typecheck/tests, and fix or report defects the build executors couldn't catch. Keeping this in its own script and directory is deliberate — the build runner stays bash-free, and only the verify pass gets the wider scope.
- **Authored and numbered last, and there is normally exactly one.** Continue the batch's numbering so the verify plan sorts after every build plan it checks. Do not split it to save money — see "Do not split verify plans" above; measured, a second verify session costs 17% more before doing any work, because verify's context does not balloon the way a tests plan's does. Split only when a batch genuinely has two unrelated surfaces to judge, and then for clarity, not for cost.
- **Written as a brief, not a diff.** Build plans paste exact code; verify plans invert that — give the goal and the checks, not step-by-step edits. State what to run, what "passing" looks like (e.g. "the client test suite green, 0 skips"), which spec sections to confirm, and the freedom to correct small defects in the build output rather than re-plan them. Don't over-prescribe; the point of a high-level model here is judgment about what a failure means.
- **Model.** Verify is judgment work — reading unfamiliar output, deciding whether a failure is a test bug or a real one. With the rules below applied, though, what remains is triage plus a handful of cross-layer invariants, and that is `sonnet`-shaped: default to `sonnet`, and spend `opus` only when the batch's surface genuinely needs adversarial reasoning (a new security boundary, a concurrency change). A brief that reads as "run X and confirm Y" has drifted into being an expensive integration test and should be `haiku` or a test instead. Filename convention is unchanged: `NN-verify-MODEL.md`; `run-verify.sh` reads the model from the suffix exactly as `run-plans.sh` does.
- **Never spend verify turns on mechanical checks.** See "The mechanical gate" below. A verify plan must not instruct the executor to run install/lint/tests/typecheck/build itself — those already ran, and their output is waiting in `plans/gate-report.txt`.
- **A level-verify brief is ten lines.** Which gate sections must be green, which contract
  rows this level owns (so the executor knows what it may not change), and nothing else —
  the runner's prompt adds the tier-1 rules. Do not list checks; a red level's failing
  tests are the checklist.
- **Read the tests before asking for an observation.** `gate-report.txt` says which checks ran; it does not say what they *assert*. Name the test files covering the batch's surface in the brief and instruct the executor to read them first, then check only what they leave uncovered. Measured: one verify run spent 51 turns and 3.67M billed input tokens, and its headline check — "an extract job reaches `done` with no API key" — was already a passing test written by that same batch's build plan. A single missing negative assertion was the entire legitimate gap.
- **Never build a world.** Constructing a collection, generating fixtures, starting a server and driving it over HTTP is a *test's* job — written once, run free thereafter. Most of that run's 43 bash calls were setup (`mkdir`, generating images with PIL, `nohup`-ing a server, `curl`), re-derived from scratch at the highest model rate in the workflow because nobody had written it down. If a check needs a world, the plan's deliverable is the test that builds it, not the check.
- **Never check model behaviour.** "Confirm an unrelated `CLAUDE.md` doesn't change the transcription" tests whether a model obeys an instruction. It is flaky by construction, cannot fail informatively, and belongs in a human spot-check rather than an unattended pass.
- **A check that will still matter next batch is a test, not a check.** Verify's most valuable output is often "this invariant has no test, here is the assertion" — the next batch implements it at haiku prices and `gate.sh` runs it forever. A check re-performed each batch pays a high-rate model every time to learn the same thing.
- **Never ask for a working-tree A/B.** "Stash the batch's changes and re-run the suite against `HEAD` to see whether the failure is pre-existing" is the natural way to phrase a triage check, and it is forbidden. The plan queue is untracked working-tree state, so `git stash -u` sweeps the *running plan*, its progress log and its usage record out from under `run-verify.sh`; `git stash pop` then restores the files but not the queue directories it emptied, and the run's own routing into `complete/`/`failed/` fails on directories that no longer exist. Observed: a budget-capped verify pass that should have been filed to `failed/` was left sitting in `inprogress/`, where the next run would have resumed it and bought the same mis-scoped brief another full budget. Worse, the cap fires after *any* turn — a stop between the stash and the pop leaves the batch's entire uncommitted output in a stash nobody knows to look for. If a brief genuinely needs a baseline comparison, name `git worktree add <scratch-path> HEAD`, which never touches the working tree; otherwise ask for "which failures look pre-existing, and the command to confirm it" and leave the A/B to a human or the next batch. `run-verify.sh`'s executor prompt enforces this, but a brief that asks for it anyway is inviting the executor to talk itself past the rule.
- **Budget the fix loop.** Fixes land last, at peak context, and every fix→re-run→re-verify cycle re-bills the whole investigation that found it. Measured across three runs: 52–82% of billed tokens landed after the first edit, at 240–540K per defect fixed. Keep fixes to what is genuinely local — a wrong monkeypatch target, an assertion on the wrong field, a drifted README line. Anything needing a new function or a signature change is a build plan for the next batch, where it costs baseline context on a cheaper model.

## Review plans

The pass after verify, and the last one in a batch. Build wrote the code, the gate ran the deterministic checks, verify ran the work and fixed what running revealed. A review plan reads the **diff** and judges the code — the defects that survive all three because nothing about them is red.

**Why this is not "an expensive model reads the cheap model's output".** That pattern is ruled out below under "The mechanical gate", and the distinction is exact: it forbids handing a high model a *transcript to summarize*, because the defects worth finding are not in the output. Reading a diff generates observations that did not previously exist, which is the property that section says verification value depends on. The measured evidence supports the split — of the three real defects one verify pass found, two needed execution (a 500 reachable only via an unreadable directory; a job run across a config switch) and one, a one-round-trip race in a React effect, is pure diff-reading. Neither pass subsumes the other.

- **Normally exactly one, numbered after the verify plan.** Continue the batch's numbering so it sorts last. Do not author one per surface; the pass reads the whole diff, and splitting it pays a fresh cache-creation charge for context it would have had anyway (the arithmetic under "Do not split verify plans" applies unchanged).
- **Optional.** A batch that is entirely mechanical expansion — the same settled pattern applied across N files, already covered by tests — does not need one. Author a review plan when the batch made a judgment call: a new invariant, an amended one, a cross-layer contract, a shape written to disk that will be expensive to migrate later.
- **Written as a brief, and shorter than a verify brief.** State what the batch was supposed to do, name the base to diff against, and list the contracts to hold it to — the spec sections it claims, the README field lists it must still match, the invariants it may have amended. Do not enumerate files to open; the diff is the file list.
- **Model: `opus`.** This is the adversarial-reasoning case the verify model note reserves opus for. A review brief that reads as "confirm X is present" has drifted into being a verify check or a test — move it.
- **Never redo verify's work.** No re-running tests, no starting a server, no building fixtures. If a question can only be settled by running something, it belongs in the verify plan or, better, in a test. Say so and move on.
- **The highest-value output is a missing assertion.** "This invariant has no test, here is the assertion" costs the next batch a haiku-priced plan and then `gate.sh` runs it forever. A finding phrased as a permanent check beats one phrased as an observation about this diff.
- **Same fix policy as verify: local fixes, structural escalations** — see that section's "Budget the fix loop". Expect to escalate more often here, because a defect found by reading skews structural.
- **Ask for a verdict, and make "no findings" a legitimate one.** A pass that must produce findings will produce speculative ones, and the next batch then spends turns disproving each. Say this in the brief.
- **The verdict is the PR body — write the brief knowing that.** `run-review.sh`'s prompt already tells the executor to write `plans/review-report.md`, and `plans/pr.sh` uses that file verbatim as the body of the pull request it opens. So the audience for the verdict is the human approving the PR, not the harness: ask for what the batch was supposed to do, whether it does it, and two separate lists (fixed here / escalated to the next batch). Don't ask for a transcript of the investigation.
- **List the review plan in the manifest's `plans` array**, like every other plan. `analysis/report.py` rolls cost up by walking that list, so an omitted review plan runs and bills into a cost record that never mentions it.

## The mechanical gate

Running the test suite is deterministic and needs no model. `run-batch.sh` therefore runs an optional repo-provided `plans/gate.sh` between the build and verify passes; it performs install, format, lint, tests, typecheck, and build, and writes the results to `plans/gate-report.txt`.

This exists because of where the cost actually is. In one measured verify run, only 15 of 61 bash calls were mechanical — but they came with the setup toil around them (discovering `uv` wasn't installed, falling back to a `.venv`, running `npm install`) at the highest model rate in the workflow. Meanwhile the three real defects that pass found came entirely from exploration: constructing an unreadable directory to prove a 500 was reachable, reasoning about a one-round-trip race in a React effect, and running a job across a config switch. **All mechanical checks were green while those defects existed.**

That last point is the load-bearing one, and it rules out the obvious cheaper alternative:

- **Don't try to split verify into "a cheap model runs it, an expensive model reads the output."** The defects worth finding are not in the output. Handing a high model a transcript reading "all green" produces "looks good, ship it." Verification value comes from generating observations that don't exist yet, which is the part that can't be delegated downward.
- **Do move the deterministic part out of the model entirely.** A shell script produces the same result for free, with a real exit code. A model asked to "run the tests and fail if they fail" *cannot* comply — the executor has no control over `claude -p`'s exit code, so a model-based gate reports failure and the runner proceeds anyway.

**The gate is advisory, not a blocker.** Build plans run without bash and can't run what they wrote, so a red tree is frequently the exact thing the verify pass exists to fix — gating on it would defeat the purpose. `gate.sh` exits non-zero only when the environment itself is unusable (no interpreter, install failed), because only then is every downstream result meaningless. Test failures are recorded and passed through.

When authoring a verify plan, assume the gate has run:

- Open with: read `plans/gate-report.txt` first; do not re-run install, lint, tests, typecheck, or build.
- If the report shows failures, triage and fix those first, then re-run **only** the specific check that failed to confirm.
- Spend the plan's actual instructions on what a script can't do: cross-layer invariants, security boundaries, concurrency, "is this output usable at all" judgments, and adversarial cases nobody wrote a test for.
- Checks with known pre-existing findings (a lint rule set with a standing backlog) belong in the gate as *informational* — recorded for baseline comparison, never counted toward its verdict, or the verdict line stops carrying information.
- **The gate must be self-contained per tree.** Two gates run at once whenever two worktrees are in flight — experiment arms, or one batch per feature — and anything a gate shares with a sibling tree is a race: a fixed port a suite binds (either side can lose, and the loser reads as red), or a `.venv` whose editable install points at whichever tree installed last. Probe free ports per run and export them to the suites' configs; give each tree its own toolchain. `templates/plans/gate.sh` shows the port probe, and a test section that can run in parallel workers (`pytest -n auto --dist loadfile`) is worth the flag: the section is the gate's longest deterministic step and the split-by-file policy keeps fixture writers on one worker.

- **Seeded once, then repo-owned.** `plans/gate.sh` is copied from `templates/plans/gate.sh` by `sync-plans.sh` the first time it's missing — same treatment as `PROJECT_FACTS.md` — and never touched again after that, so a repo edits its own copy freely. The seeded copy runs no checks and reports `GATE NOT CONFIGURED` in `gate-report.txt` until its two REPO-SPECIFIC sections are filled in with this project's real commands. A repo where `plans/gate.sh` doesn't exist or isn't executable (e.g. `sync-plans.sh` has never been run) simply skips the step.
- **Distinct from `plans/interactive/`.** Interactive plans are bash-heavy steps a human runs by hand (migrations, one-off ops). Verify plans are scripted and unattended, just privileged — same "after the build plans" timing, no human in the loop. This supersedes the older blanket rule that all verification-only work lives in `plans/interactive/`: automated post-build verification is now a verify plan; human-in-the-loop migration/verification is still interactive.

## Bypass CONVENTIONS.md's README traversal for executors

CONVENTIONS.md requires reading every ancestor README before touching a file. That's the right rule for humans/interactive Claude but wasteful for executors who already have an exact file list. At the top of each plan, include:

```
Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.
```

## Pin the facts executors would otherwise hunt for

Executors cold-start: no context from prior plans, and (per the executor note) they don't read READMEs. Every fact not in the plan gets re-derived by Grep/Glob — and across a batch the *same* fact is re-hunted plan after plan. That redundant search is the dominant waste in a multi-plan run: in one recent batch most of the executors' search calls were re-hunting a `types.ts` that doesn't exist (types come from generated code) and re-deriving the same API path templates in plan after plan.

Pin any repo-specific fact the plan's edits depend on that isn't visible from the file list. Rule of thumb: **if you had to look it up to author the plan, the executor will too — write it down.** Put it in a one-line-per-fact block at the top of the plan, right under the executor note. That block is cheaper than the 3–6 searches it replaces.

What belongs there:
- Where a shared type is defined or re-exported from — so they don't hunt for a file that doesn't exist (e.g. "types come from `src/api/generated.ts`, re-exported via `index.ts`").
- Exact API route prefixes / path templates, including asymmetries (e.g. "some routes use `{pid}`; others use `{project_id}`").
- The canonical import path for a shared helper, factory, or fixture the plan uses.
- A naming or convention gotcha the edits assume.

When several plans in a batch need the same fact, repeat it in each — they don't share context, so repetition across plan files is correct; making the executor grep is not. Pin only non-obvious, edit-relevant facts — this is README Rule 2 (name the contract that isn't visible from imports) applied to plans, not a data dictionary.

## Plan completeness checklist

Before finishing a plan that involves schema or data-model changes, walk this list:

1. **New required column?** Every code path that instantiates the model must be updated, not just CRUD. Check: seed scripts, fixtures, factories, admin/backfill scripts, tests.
2. **Renamed/removed column?** Same list, plus any JSON schema, Pydantic, or frontend type file.
3. **New folder created?** Add its `README.md` to the Create list — CONVENTIONS.md requires one per folder.
4. **New top-level concept** (entity, module, view)? Update the parent's `README.md` too, not just the new folder's.
5. **Seed/fixture data schema change?** Confirm seeded-from-scratch still works AND seeded-into-migrated still works.
6. **Identifier introduced in one file and resolved in another?** (a route path, an event
   name, a field the other side reads) — both files in one plan, or two plans that name
   each other in `Depends on:` and spell the identifier identically; and one row in the
   manifest's contracts table.
7. **Every plan 01 assertion satisfiable under "Excluded, and why"?** Walk the two lists
   against each other (Levels item 1). An assertion the exclusions make impossible is
   narrowed now, not discovered at the final gate. A red final gate is not a PR.

## After generating plans

End with a short summary:
- The feature manifest path written (`plans/features/<slug>/README.md`)
- Number of plans generated
- Files touched across all plans (unique count)
- Any plans that could run in parallel
- Any mechanical plans you recommend I do by hand instead

That's it. Keep the output of plan-generation under 200 words of your own commentary — the plan files themselves are the deliverable.
