# 105 — review: start-procedure-and-routing

Written before the build, from `self/DESIGN-2026-09-16-lifecycle-restructure.md` (§2,
§3.1, §3.4, §3.7, §4), never from the implementer's report. "No findings" is a legitimate
verdict (AGENT_PLANS.md → "Review plans"). Fix local drift in this pass; anything
structural is an escalation in the verdict, not a rewrite. The hook policy denies edits
under `hooks/`; a hook finding is therefore always an escalation, never a fix here.

## What the feature was supposed to do

The first of three features that replace session pins with the rule in design §2: one
coordinator session per feature, launched in its worktree; the session that runs
`feature-start.sh` is a **router**, never pinned, and its spend is a category of its own.

1. **`feature-start.sh` pins nothing by default.** `--pin` restores the old behaviour
   (`--no-pin` may stay as an accepted no-op or go; either way the manifest a plain start
   writes has `"sessions": []`). `--session <id>` keeps its meaning only with `--pin`.
2. **`--open`** launches the coordinator through a repo-owned hook seeded like
   `worktree-setup.sh`: `templates/plans/open-session.sh` (row in
   `templates/plans/README.md`, entry in `TEMPLATE_VERSIONS`, written by `sync-plans.sh`
   once and then owned by the repo) and `self/open-session.sh`. The seeded implementation
   opens a Terminal.app window via `osascript` running `cd <worktree> && claude` — text
   handed to a human terminal, not a Bash tool call. The script receives the worktree path
   as its argument. Without `--open` the "Next" block names the one place to coordinate
   from: the worktree.
3. **Prune before create.** Every worktree under `.worktrees/` whose branch is an ancestor
   of `origin/main` (after the fetch the script already does) is removed with `git worktree
   remove` and its local branch deleted with `git branch -d`. A dirty worktree is left in
   place with one line saying so. The primary checkout and any non-merged worktree are
   never touched. Nothing is committed or pushed by the prune.
4. **The routing record.** `feature-start.sh` writes
   `self/routing/<session-id>.json` (`plans/routing/` in a consuming repo) for the session
   that ran it (`$CLAUDE_CODE_SESSION_ID`, or `--session <id>`) and includes it in the
   `S: start` commit. Shape, design §3.4:
   `{ session_id, launched_in, git_branch, model, started_at, ended_at, duration_s,
   cost_usd, features_started: [{slug, at}], captured_at }`. Content is derived from the
   router's transcript by a new module in `analysis/` (imported bare like its siblings);
   `features_started` comes from the transcript's `feature-start.sh <slug>` tool calls
   **plus the slug being started now**, so a transcript that has not flushed the current
   call still lists it. Provisional-and-replaced: each start rewrites its own router's
   record whole. No `started_by` field in the fence — the router owns the list.
5. **Router detection and the unclaimed listing.** A router is a session launched in the
   primary checkout, on `main`, whose transcript contains a `feature-start.sh` tool call.
   `capture_planning.py --list-sessions --unclaimed` no longer lists routers; every other
   session on `main` still appears.
6. **The report.** `report.py --all` gains a Routing table: per router session its cost,
   minutes and the features it started with their frozen totals; per period, routing
   spend as a fraction of feature spend. A single feature's report prints "routed by
   `<id>`, alongside `<slugs>`" found by scanning the routing files for its slug — a sum,
   never a split.
7. **Analyzable commands in the hook.** A new deny in `hooks/allow-repo-commands.sh`: an
   assignment at command position (`NAME=value` as its own simple command) followed by
   `$NAME` or `${NAME}` later in the same command line is denied with a reason that says to
   inline the path. Same guards as the `cd` deny: a heredoc, a `#`, or an unbalanced
   quote is never denied. `CONVENTIONS.md` → "Shell commands" gains one paragraph: every
   path a literal, every program named, nothing decided at run time — no variables in
   paths, no `$(…)` in paths, no heredocs into interpreters, one line per call.
8. **Docs.** The `feature-start.sh` header comment, root `README.md` rows for
   `feature-start.sh` and `templates/`, `templates/plans/README.md`, `self/README.md`
   (new `routing/` row, `open-session.sh` row), `analysis/README.md` (new module, the
   routing record's field list under README Rule 1), `hooks/README.md` (the new deny),
   `self/tests/README.md`, `self/PROJECT_FACTS.md` where it names the start command,
   `templates/plans/features/TEMPLATE.md` (the `sessions` prose: pins are now the
   exception). `LIFECYCLE.md` step 2 says the router is unpinned and where its record
   lives; steps 6 and close are the next feature's and stay as they are.

Not in this feature: `feature-close.sh`, `run-review.sh`, `pr.sh`, `sweep.sh`, the
lifecycle-test rewrite of the close half. A change there needs a reason in `NOTES.md`.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff. Expect changes in
`feature-start.sh`, `analysis/` (one new module plus `capture_planning.py` and
`report.py`), `hooks/allow-repo-commands.sh`, `CONVENTIONS.md`, `templates/plans/`,
`self/open-session.sh`, `self/routing/`, `self/tests/`, `sync-plans.sh` if the seed
needed it, and the READMEs above.

## Contracts to hold it to

Read each as an assertion; check a test asserts it and the code satisfies it.

- **A plain start pins nothing.** In `self/tests/feature-lifecycle.sh` (or a sibling using
  its scaffold): after `feature-start.sh --self <slug>` with `CLAUDE_CODE_SESSION_ID`
  set, the fence has `"sessions": []`; with `--pin` it has that id; the `S: start` commit
  contains `self/routing/<id>.json` and its `features_started` names the slug.
- **The record is derived, not typed.** From a fixture transcript with two
  `feature-start.sh` tool calls the module yields both slugs with their timestamps, the
  session's cost through `pricing.py`, its start and end, and `git_branch` from the
  transcript's `gitBranch`. A second write of the same record from the same transcript is
  byte-identical. A missing transcript still writes a record with the current slug, null
  figures, and a warning on stderr — never a refusal to start.
- **Router detection is exact.** A fixture `main` session with no `feature-start.sh` tool
  call is still listed by `--list-sessions --unclaimed`; the one with the call is not; a
  session on a feature branch with the call is not a router.
- **Prune is safe.** In the scaffold: a merged worktree is removed and its branch
  deleted; an unmerged one and a dirty merged one survive with a message; the primary's
  tracked tree is untouched; nothing is pushed (compare the bare remote's refs before and
  after).
- **`--open` calls the hook and nothing else.** The scaffold replaces `open-session.sh`
  with a script that records its argument; the test asserts the worktree path arrived.
  The seeded script's own body is not run by any test (it talks to Terminal.app).
- **The hook deny never fires on a guess.** `X=/p; cat $X/f`, `X=/p; cat ${X}/f`, and
  `export X=/p; ls $X` are DENY with the inline reason; `X=/p` alone, `echo '$X'`,
  `cat $HOME/f` (no assignment on the line), `X=1 make` (assignment as an environment
  prefix, not a command), `$(…)` with no prior assignment, and a heredoc body containing
  `X=/p; cat $X` are all NOT_DENIED. Every existing case in
  `self/tests/allow-repo-commands.sh` still holds.
- **Report shape.** With fixtures holding two routing records and three frozen features,
  `report.py --all` renders the Routing table with the frozen totals beside each started
  slug and the routing fraction; `report.py --self <slug>` for a routed feature prints the
  "routed by" line; for an unrouted one it prints nothing extra.
- **Template seeding.** `sync-plans.sh` writes `plans/open-session.sh` when absent and
  never overwrites it; `TEMPLATE_VERSIONS` has its row and `self/tests/template-versions.sh`
  passes against the checked-in tree.
- **Named constants** for every new path, field name list, reason string and table
  heading; bash 3.2; `set -uo pipefail` and no `set -e`; no `cd` chained with another
  command anywhere in the diff, including test fixtures and the seeded `open-session.sh`
  (the `cd … && claude` text there is a string passed to `osascript`, which is the one
  permitted spelling, and the header comment must say why).
- **README Rule 1** for the routing record's field list in `analysis/README.md`, and Rule 2
  wherever `feature-start.sh`'s README row now depends on `$CLAUDE_CODE_SESSION_ID` and the
  transcript directory layout.
- **Every branch of §6** above is either present or named in `NOTES.md` as a deliberate
  exclusion with a `self/BACKLOG.md` entry.

## Verdict

Write it as the PR body will read it: what the diff does, each contract above as
holds / fixed here / escalated, and the files touched by this pass.
