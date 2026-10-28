# Notes: router-brief-writes

Rulings made while building, one line of rationale each.

## Rulings

- **Output contract: one line, `<session-id>\t<evidence>`, or nothing.** A tab cannot
  occur in a session id and is unlikely in a path; one line keeps "nothing printed means
  no builder" exactly as it was. `feature-close.sh` splits it with `%%`/`#` on the tab
  (bash 3.2-safe). The only consumer was confirmed by grepping the tree for
  `--unpinned-builder` / `UNPINNED_BUILDER` / `unpinned_builder`.
- **`unpinned_builder` returns `(session_id, evidence)` or None** rather than a bare id;
  `worked_in` returns the evidence string or None (truthiness unchanged for any reader).
  No caller outside `routing.py` used either.
- **Feature dir in the worktree is derived with a new `roots.checkout_of(path)`** — the
  nearest ancestor holding `.git` — rather than relative to the routing record's
  `launched_in`. Comparing against `launched_in` would break whenever the copy that runs
  is the worktree's (its `features_dir` is under the worktree, not the primary) or the
  record spells the primary differently (a symlinked `/tmp`); the relative path from the
  checkout is the same in either copy. `session_root` now starts from `checkout_of` too,
  so the walk is written once.
- **A `features_dir` in no checkout carves out nothing** — every write counts, as before
  this feature. Refusing too much is recoverable (pin); refusing too little loses cost.
- **`REVIEW_DIR_NAME` is new in `routing.py`; the manifest name reuses `MANIFEST_NAME`**,
  already in the same module. `report.py` compares a queue to the literal `"review"` but
  is not this feature's to change.
- **Evidence is the first line in file order that made the session a builder**, checking
  each line's `cwd` before its tool calls (the order `worked_in` already used).
- **"`.worktrees/<slug>-two/.../review/x.md` still a builder" read as the feature
  directory `<slug>-two/review/` inside this slug's worktree** (R12n). A write into the
  sibling *worktree* `.worktrees/<slug>-two/` is outside this feature's worktree and was
  never building it; R12e already covers that it is not.
- **One commit, as the brief asks**, rather than AGENT_DIRECT's separate
  `<slug>: acceptance tests` commit. The RED run is recorded in CHECKPOINT.md.
- **The RB phase of `feature-lifecycle.sh` gains RBb2** (the evidence in the real
  refusal) — the only end-to-end proof that the close parses the new line.
- **R12 gains a vendored consumer checkout** (R12r–t) for the derivation contract: the
  existing fixture is only the standalone `--self` layout.

## Not done

- `manifest.py`'s `pin-session` docstring still says the router "worked in its worktree";
  loose but not wrong, and not on the brief's doc list.
- The `checkpoint status=tests-written` timing stamp was not written at the time; it was
  not back-filled, since a late stamp would misreport the span.
