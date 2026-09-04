# methods

One directory per way of turning a worktree at `base` into an open PR. Adding a method
is adding a directory — nothing in `run.sh` or `lib.sh` knows any method's name.

Each holds three files:

- `template.md` — the delegate brief, with the placeholders `run.sh` (the harness's, not
  the method's) fills: `@@TREE@@`, `@@BRANCH@@`, `@@BASE@@`, `@@SLUG@@`, `@@SPEC_TREE@@`,
  `@@SPEC_PATH@@`, `@@SPEC_SECTIONS@@`, `@@FACTS@@`, `@@GATE_COMMAND@@`,
  `@@GATE_MINUTES@@`, `@@FIXTURE@@` and `@@ISOLATION@@`. An unfilled placeholder aborts
  the run rather than reaching a model.
- `run.sh <tree> <brief> <slug>` — the method itself.
- `README.md` — what this method is and what it costs.

| Method | What it does |
|---|---|
| `plans/` | An opus architect authors the plan corpus and `NOTES.md`, then `run-batch.sh` drains it (build → gate → verify → review → PR). The batch's own review plan and `pr.sh` are part of the method; the harness review still runs afterwards. |
| `direct/` | One opus implementer builds the feature, gates it green, commits, pushes and opens the PR. One shot, no resume. |
| `null/` | The harness's own test double: no model at all. Writes a marker file, commits, and opens the "PR" through the repo's `plans/pr.sh`. Used by `harness/tests/smoke.sh`. |

Expected next, none of them written yet: `direct-selfreview` (the same brief plus a
self-review pass against the spec), `direct-sonnet` (the same brief at `--model sonnet`),
`spec-opus-build-sonnet`.

## The contract every one of them keeps

- **Input:** a worktree on its branch at `base`, gate rehearsed green, `fixture.setup`
  run, the manifest skeleton at `plans/features/<slug>/README.md` with
  `session_window.from` set, and the generated brief.
- **Output:** a PR open from the branch to `main`, body's first line *one arm of an
  experiment — do not merge until it picks a winner*; the manifest's `plans` array
  populated, or left `[]` for a method with no plans.
- **Exit:** `0` PR-open, `2` usage-limit stop (resumable — the harness waits and
  retries once), `1` work failure (do not retry).
- **Never:** read another worktree, read `plans/experiments/`, edit `agentTooling/`, or
  run git/pip/npm outside `<tree>`. The harness pastes those rules into the brief from
  `templates/isolation.md`; a `run.sh` does not repeat them.
- **No self-review the harness relies on.** Every tree gets the harness's review stage,
  `direct` included, from the same preamble and the same fixture brief. A method whose
  brief contains a self-review is a different method, not a shortcut past that stage.

Every model call goes through `harness_claude` in `../lib.sh`, so a method inherits the
`HARNESS_CLAUDE_BIN` seam and the usage-limit detector without doing anything.
