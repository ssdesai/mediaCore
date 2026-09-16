# Checkpoint: start-procedure-and-routing

status: committed          planned | tests-written | implementing | gating | committed
updated: 2026-09-16T21:30:33Z
gate: all checks passed    (81 checks, 0 FAILED, 0 SKIPPED; shellcheck absent, which the
      gate skips by design rather than recording)

## Slices
- [x] acceptance tests — `self/tests/routing-record.sh` (26 red), the assignment-deny cases in
      `self/tests/allow-repo-commands.sh` (11 red), the S-phase cases in
      `self/tests/feature-lifecycle.sh` (11 red, plus the C3 block which is red only until
      the pin default flips), their rows in `self/gate.sh`
- [x] 1. `analysis/routing.py` — record derivation, router detection, record readers
- [x] 2. `feature-start.sh` — `--pin` opt-in, `--no-pin` no-op, prune, `--open`, routing record in `S: start`
- [x] 3. `open-session.sh` seed — `templates/plans/open-session.sh`, `self/open-session.sh`,
      `sync-plans.sh` REPO_OWNED_SCRIPTS, `TEMPLATE_VERSIONS` row, `template-versions.sh`/`sync-check.sh` rows
- [x] 4. hook deny (`hooks/allow-repo-commands.sh`) + `CONVENTIONS.md` § Shell commands paragraph
- [x] 5. `capture_planning.py` — routers out of `--list-sessions --unclaimed`
- [x] 6. `report.py` — `--all` Routing table and fraction, `--self <slug>` "routed by" line
- [x] 7. every sandbox that copies `capture_planning.py` or `report.py` now copies
      `routing.py` too (13 test files)
- [x] READMEs: root, `analysis/`, `hooks/`, `templates/`, `templates/plans/`, `self/`,
      `self/tests/`, `self/PROJECT_FACTS.md`, `templates/plans/features/TEMPLATE.md`,
      `LIFECYCLE.md`, `CONVENTIONS.md`, `self/BACKLOG.md`
- [x] 8. rework pass — the six items the first review escalated, plus the feature README's
      prose (`NOTES.md` rulings 10–14; the decisions themselves are in
      `review/incomplete/106-review-opus.md`):
      prune deletes with `git branch -D` (`feature-lifecycle.sh` S4h–S4k, a second clone
      merging on the remote so the primary's `main` lags); a vendored `--self` start
      (S6, a second scaffold from `$AT`'s first commit); the conflict rule is "later
      `captured_at` wins" in `analysis/README.md`, design §3.4, `NOTES.md` 7,
      `self/BACKLOG.md` and `routing.py`; router detection at command position only
      (`COMMAND_POSITION_RE`, `routing-record.sh` R4f–R4g); both `open-session.sh` copies
      quote the worktree path, at `template-version: 2` with a re-recorded hash;
      `report.render_routed_by` calls `routing.routers_of`

## Learned
- `hooks/**` is Edit-denied by this checkout's own `.claude/settings.json`; `hooks/README.md`
  says the sanctioned path is a script that writes it (a scratchpad patch script run once).
- `routing.py` must not import `capture_planning` — `capture_planning` imports it for router
  detection. It locates a transcript by globbing `~/.claude/projects/*/<id>.jsonl`, the way
  `recover_attempts.py` already does, so no mangling helper is needed and there is no cycle.
- The lifecycle test merges several feature branches into `origin/main` mid-run, so the prune
  really fires there; nothing after line ~440 references the worktrees it takes. S4's new
  remote-merge case must level the primary's `main` with `origin/main` again before it ends
  — the C and W phases push `main` from that checkout and a lagging one fails the push.
- `git worktree add -b X origin/main` sets X's upstream to `origin/main`, so `git branch -d`
  succeeds there. The shape that made `-d` refuse is the real loop's: `self/pr.sh` pushes
  with `-u`, the forge deletes the branch, `fetch.prune` drops the tracking ref, and `-d`
  falls back to the primary's lagging `HEAD`. That is what S4h–S4k build.
- The standalone lifecycle scaffold cannot nest, but it does not have to be rewritten:
  `git archive` of `$AT`'s first commit unpacks the whole harness — stubs, templates,
  analysis modules — one directory inside a fresh consumer repo, which is all a vendored
  `--self` start needs.

## Resume
- Nothing to resume: the branch carries `start-procedure-and-routing: acceptance tests`,
  the build commit, the first review's commit and `start-procedure-and-routing: rework`,
  and the gate is green. The second review pass is next
  (`./run-review.sh --self start-procedure-and-routing` from the worktree), which runs
  `review/incomplete/106-review-opus.md`.
- To re-check by hand, from
  `/Users/sahildesai/dev/agentTooling/.worktrees/start-procedure-and-routing`:
  `bash self/tests/routing-record.sh`, `bash self/tests/allow-repo-commands.sh`,
  `bash self/tests/feature-lifecycle.sh`, `bash self/tests/template-versions.sh`,
  then `./self/gate.sh` (about two minutes), verdict in `self/gate-report.txt`
