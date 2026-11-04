Verdict: escalated

# Review — orchestrator-brief

## What the batch was supposed to do

Ship a fill-in template for the orchestrator's implementer brief
(`templates/plans/ORCHESTRATOR_BRIEF.md`). The template names the branch outright with
`--branch claude/<slug>`, says a detached HEAD is expected, and never says "assigned
branch". The batch also had to register the template as a generated stub in
`sync-plans.sh`, point to it from `LIFECYCLE.md` and `self/PROJECT_FACTS.md`, teach
`analysis/routing.py` that `--branch` takes a value, add a self-test recorded in
`self/gate.sh`, and update the READMEs the change made wrong.

## Does it do it

Mostly, yes.

- **Template:** it has every required section, the literal start line, and no
  "assigned branch".
- **Sync:** `GENERATED` gained the name. `check_stubs`/`sync_stubs`/`stub_origin` treat
  every entry the same way, so the new stub reports `in-sync`, `STALE` or `EDITED` like
  the other five. `sync-check.sh` 1b now covers it, and `TEMPLATE_VERSIONS` is unchanged.
- **Routing:** `--branch` is in `START_VALUE_FLAGS`. R10a3 recovers the slug with
  `--branch` both before and after it, and alongside `--method`/`--orchestration`.
- **Scope:** nothing changed under `.claude/`, `self/orchestrations/` or another feature's
  folder, and no committed file names a model. The new test uses no `set -e`, puts its
  literals in named constants, and is bash 3.2-safe.
- **Gate:** green, with nothing SKIPPED.

One defect is still there with every check green: the template is correct only in
agentTooling itself, not in the consuming repos it is synced to (escalated below).

## Fixed in this pass

- `README.md` → "3." sync section: "overwrites the five generated stubs" → "six".
- `README.md` `templates/` table row: it said every generated stub's header names
  `PROJECT_FACTS.md`. The new brief's header doesn't, so the sentence now says this of
  the five folder stubs only.
- `templates/README.md`: the batch had changed "five stubs" to "six stubs" in a
  paragraph that still said each one "describes its folder", "points at `RUNNER.md`" and
  has a header "naming `PROJECT_FACTS.md`". None of that is true of the brief. The
  paragraph now says it of the five folder stubs and gives the brief its own sentence.
- `templates/plans/ORCHESTRATOR_BRIEF.md` authoring note: the note only required each
  `<placeholder>` to be replaced. The start line also has `[--self]` and
  `[--orchestration …]` optionals, and a copy that leaves those brackets in gives
  `feature-start.sh` a command it refuses. The note now says to keep each `[optional]`
  without its brackets or drop it. I re-ran `self/tests/orchestrator-brief.sh` after the
  edit: it passes, and the file is 67 lines.

## Escalated to the next round

1. **The brief's fixed text is wrong in a consuming repo**
   (`templates/plans/ORCHESTRATOR_BRIEF.md`, the Branch and "Read first" sections).
   - The file is a generated stub, so it ships to every consumer as
     `plans/ORCHESTRATOR_BRIEF.md`, and its header says everything but Why and Items is
     fixed.
   - In a consumer the implementer's working directory is the repo root. There the start
     script is `./agentTooling/feature-start.sh` (`LIFECYCLE.md` lines 16 and 79), and
     the docs are `agentTooling/CONVENTIONS.md` and `agentTooling/LIFECYCLE.md`.
   - The template hardcodes `./feature-start.sh …` and bare `CONVENTIONS.md`,
     `LIFECYCLE.md`. A consumer orchestrator that follows "the rest is fixed" sends a
     first command that doesn't exist, which is the same kind of untrue brief this
     feature set out to remove.
   - The plan pinned that literal start line, and `orchestrator-brief.sh` B3 asserts it.
     So fixing this is a design decision rather than a local edit. Options:
     - (a) make the prefix a placeholder: `<tooling>/feature-start.sh …`, with
       `<tooling>` = `.` in agentTooling and `./agentTooling` in a consumer, and the same
       prefix on the "Read first" doc paths;
     - (b) write the consumer form `./agentTooling/feature-start.sh` and note the `--self`
       spelling.
   - Whichever is chosen, update B3's `START_SHAPE` to match. Add an assertion that every
     agentTooling-root path in the brief's fixed text carries the prefix, so a bare
     `./feature-start.sh` cannot return.

2. **Missing assertion: the generated-stub lists stay in step.** `GENERATED` in
   `sync-plans.sh` is mirrored by hand in four places:
   - the root `README.md` list of stubs a repo never edits;
   - the `templates/README.md` table;
   - the stub-count prose ("five"/"six") in `README.md`, `templates/README.md`,
     `self/PROJECT_FACTS.md` and `self/tests/README.md`;
   - `sync-check.sh` 1b's loop.

   This batch missed two of those copies (fixed above), and no test caught it. A test
   should derive the list from `GENERATED` and assert each name appears in the
   `templates/README.md` table and in `sync-check.sh` 1b. Better still, make 1b iterate
   over the parsed `GENERATED` itself. A cheap model can write this.
