# Project facts for plan authors

Repo-specific facts that plans must pin so cold-start executors don't re-derive them
by grepping. See `../agentTooling/AGENT_PLANS.md` → "Pin the facts executors would
otherwise hunt for". Copy the relevant lines into each plan that depends on them —
executors share no context, so repeating a fact across plans in a batch is correct.

Rule of thumb: **if you had to look it up to author a plan, an executor will too.**
Pin only non-obvious, edit-relevant facts — this is a list of contracts that aren't
visible from a file list, not a data dictionary.

Replace the prompts below with this repo's real answers, and delete any section that
doesn't apply.

## Types

- Where shared types are defined, generated, or re-exported from — especially when the
  path an executor would guess does **not** exist. Name the wrong guess explicitly.
- Any file that is generated and must never be hand-edited, plus the command that
  regenerates it and the check that catches staleness.
- Any import that is deliberately forbidden even though it would work.

## API paths

- Route prefixes and path templates, including asymmetries between modules.
- How the client builds URLs, and anything that throws when a precondition is unset.

## Commands

Build plans have no bash — these belong in verify plans and interactive plans.

- The test command(s), and any environment variable they require.
- Codegen, typecheck, or lint guards that CI runs.
- Any command that refuses to run against production data, and what it checks.

## Tests

- Where the behavioral spec lives, if plans are meant to quote from it rather than
  decide coverage themselves.
- Conventions a test plan must follow: file layout, naming, libraries that are
  deliberately not used.

## Conventions and gotchas

- Naming or structural rules the edits assume but the file list doesn't show.
