# Notes: start-takeover

Rulings made during the direct build, one line of rationale each. The spec is the
`self/BACKLOG.md` entry "A start interrupted between `git worktree add` and its
`<slug>: start` commit blocks its own slug for good" (deleted by this feature) and the
brief's "What to build".

## Rulings

- **Lock location: `$(git -C <worktree> rev-parse --absolute-git-dir)/feature-start.lock`**,
  i.e. `.git/worktrees/<name>/`, not the feature directory. It is invisible to the
  worktree's `git status` (so the "clean" condition and the `S: start` commit never see
  it), `git worktree remove` deletes it with the rest, and it cannot ride a `git add`.
  Resolved through `rev-parse` rather than built from the slug, since git names the admin
  dir `<slug>1` when `<slug>` is taken.
- **Lock format: `key=value` lines** — `pid=<$$>`, `started=<UTC>`, and on a refusal
  `refused=<reason>`. Line-oriented so `sed` reads it under bash 3.2 and a refusal appends
  without rewriting. Key names are constants (`START_LOCK_*_KEY`).
- **The refusal path leaves the lock**, appending `refused=<reason>`: the lock then says
  which start abandoned the worktree and why, and its PID is dead the moment the script
  exits, which is exactly the evidence the next start needs. Removing it would turn every
  refused start into the "no lock" shape and lose that record.
- **Liveness is `ps -p <pid>`, not `kill -0`**: `kill -0` fails with EPERM on another
  user's process and would read a live start as dead. A PID the OS has reused reads as
  live — a refusal naming it, the safe direction; the message says a human removes the
  lock in that case.
- **A lock with no numeric `pid=` line reads as no lock.**
- **Takeover removes and recreates rather than adopting the worktree in place**: the base
  may have moved since the half-start, the hook and gate must run again anyway, and the
  rest of the start then runs exactly as a fresh one does — one code path.
- **The own-slug assessment runs twice**: at the existence check (so a refusal comes
  before any fetch or prune, as every other refusal does) and again right before the
  removal, after the stale-primary check (so a run that exits 3 has removed nothing, and a
  concurrent start caught between its `worktree add` and its lock write has had the
  fetch's seconds to write it).
- **The takeover happens before the prune** so the prune never reports this slug's own
  half-start as another start's.
- **Deviation — the prune treats a MISSING lock as "keep", where the takeover treats it as
  dead.** The brief says the prune uses the same predicate and "may now prune one whose
  lock is dead; a live lock is still skipped" — silent on a missing one. A start of
  another slug cannot tell a pre-lock half-start from a start caught between its
  `worktree add` and its lock write, and the prune never deletes what it cannot prove;
  `feature-lifecycle.sh` S4g2 (a hand-made `worktree add` with no lock, standing for a
  concurrent start) stays green because of it. The own-slug takeover takes the lockless
  shape per the brief, since a second start of the same slug inside that one-write window
  is the only way to be wrong there.
- **One deleter, `drop_half_or_merged`**: the prune and the takeover both remove a
  worktree and `git branch -D` its branch through it, each only after proving the branch
  holds no work. No refusal message tells anyone to delete a ref by hand.
- **Prune messages**: a dead half-start is `pruned … (an abandoned start, unmoved since
  its creation, whose start (pid N) is gone)`; a dirty one `kept … , but has uncommitted
  changes` — the merged-dirty line now reads `merged into origin/main, but has
  uncommitted changes` (a comma added; no test or reader matches that text).
- **Tests: a sibling `self/tests/start-takeover.sh`** rather than more phases in
  `feature-lifecycle.sh` (already ~1,850 lines); `plan-numbering.sh`'s scaffolding. The
  interrupt is real: the stub hook reads the running start's lock and `SIGKILL`s the PID
  it names, which also proves the lock exists, with the start's own PID, during the hook.
  The live-PID case forges the lock with a `sleep` started outside any job.

## Left unbuilt (each has a `self/BACKLOG.md` entry)

- A dead half-start cut from a stacked `--base` is never pruned by another slug's start
  (it is not an ancestor of `origin/main`); only a re-run of its own slug takes it over.
- A start SIGKILLed while its hook or gate is still running leaves that child running in
  the worktree with the start's PID already dead; a takeover or prune in that window
  removes the worktree under it.
- `feature-lifecycle.sh` T5 prints `No such file or directory` writing its brief into the
  primary's `self/features/lifecycle-one/` (seen while gating this feature, unrelated to
  it); its assertions still pass, so T5 may be passing without the brief it meant to run.
