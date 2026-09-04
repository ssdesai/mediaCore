# Feature lifecycle: one rule for branches and worktrees, and the scripts that enforce it

The procedure for taking a feature from an instruction to a costed merge was spread over
five doctrine files and had no step for isolation, none for closing, and no naming rule
for the branch and worktree a feature runs in. `self/TRIAGE-2026-09-03-feature-execution-procedure.md`
measured what that cost in vinylCatalogue: sessions billed to the wrong feature, a
frozen `$0.00`, a PR the hook could not open. This feature replaces the procedure with
three scripts and one rule, prunes the prose they make redundant, and reorganizes the
root README so the repo reads by category. Built by hand in one session
(`method: "hand"`); see "How this feature is costed" at the end.

## The rule

For a feature with slug `S` in a repo whose primary checkout is at `R`:

    slug      ^[a-z0-9]+(-[a-z0-9]+)*$     kebab-case, no slash, no owner prefix
    branch    S
    worktree  R-S                          a sibling directory of the primary checkout

Everything cost capture needs is derived from the slug: the branch to match, the
worktree path, and therefore the transcript directory a session launched there is
filed under. The primary checkout stays on `main` and is used only to start and close
features. A session is billed to the branch of the directory it was **launched** in, at
every message, whatever it `cd`s into; so the coordinator session for a feature is
launched inside `R-S`. A session that began somewhere else — on `main`, before the
feature existed — is claimed by id, never by widening `branches`.

Agents never run `git worktree add`, `git checkout -b` or `git branch`. `feature-start.sh`
is the only thing that creates a feature branch or worktree, and it refuses a slug that
fails the pattern.

## The items, with the decision each one is built to

### A. Index

1. **`README.md` reads by category.** The flat contents table becomes one table per
   category: start here; the three methods (plans, direct, by hand), each with its doc
   and its scripts; the runners and their library; costing; experiments; installing and
   updating consumers; self-hosting. Rows keep their current text. Nothing moves except
   the two items below.
2. **`EXPERIMENTS.md` moves to `harness/EXPERIMENTS.md`.** The harness is its only tool
   and nearly every reference is already inside `harness/`. Every reference in this repo
   is updated (`AGENT_DIRECT.md`, `AGENT_PLANS.md`, `ORCHESTRATION.md`, `README.md`,
   `self/PROJECT_FACTS.md`, `templates/README.md`, `templates/plans/README.md`,
   `templates/plans/gate.sh`, `templates/experiment/CHECKLIST.md`, the harness's own
   files, the triage).
3. **`migrate-plans-layout.sh` is retired.** All four consuming repos (humanNetworkMap,
   mediaCore, musicMap, vinylCatalogue) are on the per-feature layout it produced,
   measured 2026-09-03. Deleted, with its rows in `README.md`, `RUNNER.md`,
   `self/PROJECT_FACTS.md` and `self/gate.sh`'s `shell_scripts`.

### B. Capture knows the rule

4. **A session launched in the feature worktree is claimable.**
   `analysis/capture_planning.py`'s `repo_match` accepts a transcript whose `cwd` is the
   session root `R`, under it, the feature worktree `R-<slug>`, or under that. Every
   session entry in `planning.json` records `cwd`. The "matched no session" warning is
   replaced by one that names all three causes with the command for each: a wrong
   branch name (`git branch --list`), sessions carrying the branch that were launched
   elsewhere (each `cwd` seen, and that they are not claimable from here), and
   transcripts that have aged out. Assertion (`self/tests/capture-guard.sh`): a
   transcript with `cwd` `R-<slug>` is selected; one with `cwd` `R-other` is not and its
   `cwd` is named in the warning; the selected entry carries `cwd`.
5. **Session pins.** The manifest fence gains `"sessions": ["<session-id>"]`, the
   top-level twin of `subagents`: each id is claimed outright, across every project
   directory, regardless of branch, window or `cwd`. A session entry carries
   `selected_by`: `"pinned"` or `"branch"`. A pinned session that branch and window
   would also select is priced once. A pin that is also in `exclude_sessions` warns and
   the pin wins, as for subagents. `--list-sessions [--since <date>] [--unclaimed]` is
   the twin of `--list-subagents`: every top-level session under `R` and `R-*` with
   start, `gitBranch`, `cwd`, cost and opening prompt; `--unclaimed` keeps the ones no
   manifest pins and no `planning.json` in this corpus lists as selected or excluded.
   Assertions (`self/tests/subagent-capture.sh`, new phase): a session pinned from
   another project directory is claimed with `selected_by: "pinned"`; branch-selected
   entries say `"branch"`; `--list-sessions --unclaimed` lists an unpinned session and
   omits one that a `planning.json` already lists.
6. **No silent zero.** When a capture matches no session and no subagent it writes
   nothing, prints the three-cause message from item 4, and exits non-zero; `--force`
   writes the zero (the honest record for a feature whose transcripts are gone). Under
   `--all` a refused zero counts with the other refusals: the run continues and exits
   non-zero at the end. The frozen-cost guard and the already-captured skip are
   untouched; `capture-guard.sh` assertions 1–14 still pass, with two re-fixtured so
   they keep testing what they tested rather than this refusal: 7b re-captures over a
   zero-cost prior *with* a transcript present, and 14b asserts that an empty window
   leaves no file rather than a `$0.00` one. Assertion: a capture that matches nothing
   leaves no `planning.json`; the same capture with `--force` writes one with total
   `0.0`; under `--all` the refusal is counted and the exit is non-zero.
7. **`method: "hand"`.** A feature built interactively, by the coordinator itself, with
   no delegate and no plans. `analysis/report.py` treats it as it treats `direct`: the
   transcripts in `planning.json` are the build, filed under a row reading
   `build: by hand`; checkpoint sub-rows apply if stamped. `KNOWN_METHODS` gains it; the
   unknown-method warning still fires for anything else. A planned feature's report is
   byte-identical before and after. Assertion (`self/tests/direct-timing.sh`, new
   phase): `method: "hand"` yields the build row and no method warning.
8. **`base` in the fence.** `feature-start.sh` writes `"base": "<branch>"` — what the
   feature branched from, `main` unless `--base` said otherwise. `run-review.sh` reads it
   and exports `FEATURE_BASE` for `pr.sh`; capture ignores it. A helper in
   `plan-runner-roots.sh`, `manifest_field <readme> <key>`, reads a scalar from the last
   `json` fence with `jq`, so no runner parses markdown twice.

### C. Start

9. **`feature-start.sh [--self] <slug> [--method direct|plans|hand] [--base <branch>] [--no-gate] [--no-pin] [--session <id>]`**,
   at the top level beside `stamp-timing.sh`, sourcing `plan-runner-roots.sh`.
   `--method` defaults to `direct`. In order:
   - refuses a slug that fails the pattern, a branch or worktree path that already
     exists, and being run from a worktree (`git rev-parse --git-dir` differs from
     `--git-common-dir`); the primary need not be clean, because nothing below touches
     it;
   - `git fetch origin` when `origin` exists; base is `--base`, else `origin/main` when
     it exists, else `main`; `git worktree add R-<slug> -b <slug> <base>`;
   - runs the repo's setup hook inside the worktree when present and executable:
     `plans/worktree-setup.sh` (or `self/worktree-setup.sh` under `--self`). A non-zero
     exit stops the script with the worktree left in place for inspection;
   - runs the repo's gate inside the worktree (`plans/gate.sh`, or `self/gate.sh`) unless
     `--no-gate`, and stops on anything but a green verdict, worktree left in place: a
     red base is the implementer's context spent on someone else's failures;
   - writes the feature directory in the worktree: the manifest from
     `templates/plans/features/TEMPLATE.md` with its fence replaced by the filled one
     (`slug`, `method`, `plans`, `branches: ["<slug>"]`, `base`, `session_window.from`
     from `date -u` with `Z`, `to: null`, `exclude_sessions: []`, `sessions`,
     `subagents: []`); `review/incomplete/NN-review-opus.md` as a stub carrying the
     review-brief section headers and a `@@TODO@@` line, with its stem in `plans` —
     `NN` is `01` in a consuming repo and the next number in the global sequence under
     `--self` (`self/PROJECT_FACTS.md` → Conventions); an empty `NOTES.md` is not
     written — the author or implementer writes it;
   - `sessions` is `[$CLAUDE_CODE_SESSION_ID]` when that variable is set, `[<id>]` with
     `--session`, `[]` with `--no-pin`. A planning session that runs this script claims
     itself; that is the answer to "I started on `main` and then cut the branch";
   - commits the feature directory on `<slug>` in the worktree, `<slug>: start`;
   - prints, last: the worktree path, `cd R-<slug> && claude`, the line every brief
     opens with (`feature: <repo>/<slug>`), and that the review brief must replace its
     `@@TODO@@` before the review pass runs.
10. **The setup hook.** `templates/plans/worktree-setup.sh` is a no-op skeleton with the
    common steps as comments (a venv per worktree — never shared, the editable install
    points at whichever tree installed last; `npm install`; a per-worktree dev port).
    `sync-plans.sh` seeds it into `plans/` once, like `gate.sh` and `pr.sh`, and never
    overwrites it; `templates/README.md` and `README.md` list it. `self/worktree-setup.sh`
    is this repo's own, and does nothing.
11. **A stub brief cannot run.** `plan-runner-lib.sh` refuses to run a plan whose file
    contains `@@TODO@@`: it is filed to `failed/` with a progress log naming the marker,
    and the pass continues. Assertion (`self/tests/feature-lifecycle.sh`): a review pass
    over a stub brief files it failed without calling `claude`.

### D. Close

12. **`feature-close.sh [--self] <slug> [--recapture] [--keep-worktree] [--no-push]`**,
    same place, same sourcing. Run by the human from the primary checkout after the PR
    merges and after the feature's sessions have ended; no model is involved. In order:
    - refuses to run from a worktree, or when the primary is not on `main`, or when its
      tree is dirty;
    - `git fetch origin`; refuses unless `<slug>` is an ancestor of `origin/main` ("PR not
      merged"); `git pull --ff-only`;
    - `capture_planning.py --list-subagents --unclaimed --since <from date>`: stops if
      any row's brief names `<repo>/<slug>`, printing the pin to write;
      `--list-sessions --unclaimed --since <from date>` is printed for the human and
      does not stop the run;
    - `capture_planning.py [--self] <slug> [--recapture]`; a non-zero exit (the zero
      refusal, the frozen-cost refusal) stops the run;
    - `report.py [--self] <slug>`, then prints every session and subagent
      `planning.json` claims — id, `selected_by`, `cwd`, start, end, cost — and the
      total, so the human reads what was claimed before quoting it;
    - only now stamps `session_window.to` with `date -u` and a `Z` if it is `null`,
      through `analysis/manifest.py set-window-to [--self] <slug>` — a stdlib helper
      that edits only that value in the last fence, preserving the file's formatting.
      After capture, not before: a `to` of now excludes nothing that exists now, and a
      capture that refuses must leave the manifest untouched and the primary clean;
    - commits, only if every dirty path is under the feature directory and is one of
      `README.md`, `planning.json`, `report.md`, `report.json`, `timing.jsonl` — anything
      else dirty is named and the run stops — as `<slug>: cost records`, and pushes
      `main` unless `--no-push`;
    - `git worktree remove R-<slug>` and `git branch -d <slug>` unless `--keep-worktree`.
      Capture ran first by construction: a removed worktree is still matched by the
      derived path, but the order is the guarantee that its transcripts were read while
      the branch record was fresh. The remote branch is left to the forge's own
      delete-on-merge setting.
    Assertions (`self/tests/feature-lifecycle.sh`): refuses from a worktree, refuses
    an unmerged branch, stamps `to`, commits exactly the cost files, removes the
    worktree, and keeps it under `--keep-worktree`.

### E. Review and PR

13. **`pr.sh` never cuts a branch.** In `templates/plans/pr.sh` and `self/pr.sh`
    alike: the head is the current branch; the base is `FEATURE_BASE` from the
    environment, else `BASE_BRANCH`, else `main`; it refuses when the current branch is
    the base ("nothing to open a PR from"); it commits whatever the review pass left,
    pushes with `-u`, and opens the PR unless one is already open. The `review/` prefix,
    `REVIEW_BRANCH`, and the `checkout -b` step are gone; a plans batch runs in its
    feature worktree like everything else, so its output is already on its own branch.
    `run-review.sh` exports `FEATURE_BASE` from the manifest (item 8) before calling
    the hook. `README.md` → "Adopting stacked pull requests" becomes "Adopting
    feature-branch PRs": the two edits a repo-owned `pr.sh` needs, one sentence each.
    Assertions (`self/tests/feature-lifecycle.sh`, stub `gh`): on branch `<slug>` with a
    dirty tree the hook creates no branch, commits, and calls
    `pr create --base main --head <slug>`; with `FEATURE_BASE=other` the base is
    `other`; on `main` it refuses.

### F. Doctrine

14. **`LIFECYCLE.md`** at the top level is the entry point: the seven steps — route,
    start, brief, build, review and PR, close, sweep and propagate — one paragraph each
    naming the script that does it or the doc that governs it, and the three rules (a
    session is billed to the directory it was launched in; agents never create branches
    or worktrees; the manifest's fence is written by the scripts only, its prose by
    whoever authors the feature, and an executor may correct the prose and never the
    fence). It says when to run which script and nothing a script already enforces.
15. **Prune what the scripts replace.** `AGENT_DIRECT.md`: "Checklist before spawning"
    becomes one line (`feature-start.sh` enforces it); "The brief" item 2 names the
    worktree the script made; "The feature directory" loses the layout the script
    writes. `ORCHESTRATION.md` → Rules: the stacking export, the window-chaining rule and
    the pin-timing rule become one bullet pointing at start and close; the
    `feature:` line and the delegate rules stay. `analysis/README.md` → "How to run
    them": the per-feature close is `feature-close.sh`; the weekly `--all` is the sweep
    behind it; "Where to run them" says why a worktree's copy is the wrong copy for an
    ordinary capture. `AGENT_PLANS.md` → "The feature manifest": `method` gains `hand`;
    `base` and `sessions` are documented; "never written or edited by an executor"
    becomes the fence rule from item 14. `templates/plans/features/README.md` and
    `self/features/README.md`: "to start a new feature, run `feature-start.sh`".
16. **Every touched folder's README is current**, including field lists:
    `analysis/README.md` → JSON artifacts documents `cwd` and `selected_by` on session
    entries; `README.md`'s index has rows for `LIFECYCLE.md`, `feature-start.sh`,
    `feature-close.sh`; `self/README.md` and `templates/README.md` list
    `worktree-setup.sh`; `self/tests/README.md` has a row for `feature-lifecycle.sh`;
    `self/gate.sh`'s `shell_scripts` lists every new script and `record`s the new test.

## Deliberately excluded

- A `feature: <repo>/<slug>` first line for top-level sessions as an attribution key.
  Session pins (item 5) cover the case that motivated it, with no parsing.
- The weekly cadence as a script, `check-plans.sh`, and `sync-plans.sh --check` for
  repo-owned drift. Second tier; not on the costing path.
- Moving the runners or the doctrine into subdirectories. Four consuming repos invoke
  them by path from files `sync-plans.sh` never overwrites.
- The harness's own conventions: camelCase arm branches, capture from the worktree's
  copy, its own PR flow. Experiments stay as they are.
- Rolling out to consumers: subtree pull, `sync-plans.sh`, the hand-merge of each
  repo-owned `pr.sh`, filling each `worktree-setup.sh`. Per repo, after this merges.
- Rewriting existing manifests or frozen records to the new fields.
- Deleting the remote branch at close.

## Plans

| Plan | Model | Does |
|---|---|---|
| `72-review-opus` | opus | Independent review of the diff against `main`, from this manifest, not from the builder's report. |

Built by hand: no `auto/`, no `verify/`. `CHECKPOINT.md` and `NOTES.md` are the
builder's.

## How this feature is costed

This is the bootstrap: it was built before `feature-start.sh` existed, by the session
that designed it, which was launched in the primary checkout on `main` and worked in
`R-feature-lifecycle` by absolute path. Its transcript therefore records `main`, never
`feature-lifecycle`. It is claimed by **session pin** (item 5), which is exactly the
mechanism the script will apply automatically from now on; `branches` names only the
feature branch, and `main` appears nowhere. `feature-close.sh` on this feature is the
first run of the close, and the number it prints should be read against the session id
below before it is quoted.

```json
{
  "slug": "feature-lifecycle",
  "method": "hand",
  "plans": ["72-review-opus"],
  "branches": ["feature-lifecycle"],
  "base": "main",
  "session_window": {"from": "2026-09-03T17:44:00Z", "to": "2026-09-04T05:46:54Z"},
  "exclude_sessions": [],
  "sessions": ["48f81318-3e51-4559-a82c-37fe75be5308"],
  "subagents": ["a1193ae274db55efb", "a416e963b95bdf0a2", "abdd1b760eb2eb2f8", "ade1fd29da9eac1ad"]
}
```
