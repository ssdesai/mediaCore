# Notes: feature-lifecycle

Rulings made where the manifest left the call open, each with a one-line rationale,
plus deviations and open questions. The manifest's decisions are not reopened here.

## Rulings

- **A session that started on `main` is claimed by pin, not by `main` in `branches`.**
  An open window on `main` sweeps in every later session in the primary checkout
  (`planning-window-must-close`, measured 5x inflation in vinylCatalogue); a pin names
  one session and nothing else. `feature-start.sh` pins `$CLAUDE_CODE_SESSION_ID`, so
  the common case needs no hand edit.
- **`method: "hand"` rather than reusing `direct`.** `direct` means "an implementer
  delegate built it"; a hand build has no delegate to pin and its transcript is the
  coordinator's. The cost rows are the same; the label should not lie about who built it.
- **The stub review brief carries `@@TODO@@` and the runner refuses it**, rather than
  the start script leaving `review/incomplete/` empty. An empty queue is a clean no-op
  for `run-review.sh`, which is exactly how a forgotten brief would go unnoticed; a
  stub that fails loudly cannot be skipped by accident. Same marker the harness uses.
- **`feature-start.sh` commits the feature directory.** The branch's first commit is
  the manifest, so a feature branch with no manifest cannot exist by this route.
- **`feature-close.sh` pushes `main`** (decided with the user): the commit holds only
  generated cost files and the closed manifest, and the script refuses if anything else
  is dirty. A cost PR per feature is ceremony for files no reviewer reads.
- **`--list-sessions --unclaimed` means "no `planning.json` in this corpus lists it and
  no manifest pins it"**, not "no manifest's branch and window would select it". The
  latter needs a full selection pass per manifest; the former is the question close
  actually asks, and it is one scan of the corpus.
- **Close removes the local worktree and branch, and leaves the remote branch alone.**
  Forges delete merged branches on their own setting; a script deleting remote refs is
  a wider blast radius than a close should have.
- **A pass's trailing timing stamps are the record, not leftovers, so close carries them
  home instead of forcing past them.** `pr_opened` — which carries the PR URL
  `analysis/report.py`'s Time table reads — and `pass_end`, from `plan-runner-lib.sh`'s
  EXIT trap, are both written *after* the PR hook has committed and pushed, in every
  runner flow, old and new. They therefore live only in the worktree, no branch will ever
  carry them, and a `git worktree remove --force` would silently drop the one line naming
  the PR. So `feature-close.sh` appends the lines the primary's `timing.jsonl` does not
  already hold — before the capture, so the report is written over the complete record,
  and deduped by exact line, which is safe precisely because the file is append-only JSON
  lines, so a re-run or a second close after a `--keep-worktree` one carries nothing
  twice. The teardown then restores the worktree's copy, which is now a duplicate of what
  is on `main`, so the plain `git worktree remove` succeeds; a worktree dirty with
  anything else is still left in place.

- **A pinned session that is also excluded is warned about from the manifest alone**,
  after the scan, not inside the loop: a session pinned from another project directory
  never enters the loop, and the warning must fire wherever the transcript sits. Same
  shape as the `subagents`/`exclude_subagents` warning.
- **`report.py` labels a hand build `build: by hand`** and otherwise treats it exactly
  as direct; the one-line "Built direct" note in the cost section varies by method so
  it does not name a delegate that never existed.
- **Slices 6–9 were built by delegates, not by hand**, after the user asked for fresh
  context on each: one opus implementer for feature-close.sh, pr.sh, the gate wiring and
  the tests README; one for LIFECYCLE.md, the prune and the README rows; one sonnet
  pass for the timestamps test. Their agent ids are pinned in the manifest's
  `subagents`, so the feature's build cost is this session plus the three of them —
  `method: "hand"` still describes who decided; the manifest prose says who typed.

- **The stub-marker refusal is anchored to the start of a line.** Found by this
  feature's own first review pass: the brief mentioned the marker mid-sentence and was
  refused. The stub always writes it at column one; a brief that talks about it does not.
  Asserted as T1f.

- **The review pass's two escalations were reworked by a fourth delegate, on the
  findings file alone**, per `AGENT_DIRECT.md` → "The review is not optional". Its two
  rulings: the close asks capture for the delegates briefed for exactly this feature
  (`--list-subagents --unclaimed --for <repo>/<slug>`, compared as the `(repo, slug)`
  pair, never as text in the printed table); and the timing carry stays before the
  capture so the report reads the complete record, with a refused capture rolling the
  carried lines back so the primary is left exactly as found and the re-run carries
  them again.

## Deviations

- **`capture-guard.sh` 7b and 14b were re-fixtured** (manifest item 6 says so): both
  read a `$0.00` file that a nothing-matched capture used to write. 7b now re-captures
  over a zero-cost prior *with* a transcript present, which is the frozen-guard case it
  was testing; 14b asserts that an empty window leaves no file.

## Open questions

- None yet.
