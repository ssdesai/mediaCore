feature: agentTooling/self-corpus-identity

# Rework one-shot brief — self-corpus-identity

## Where

Worktree `/Users/sahildesai/dev/agentTooling-self-corpus-identity`, branch
`self-corpus-identity`, base `main`. Absolute paths everywhere; never touch
`/Users/sahildesai/dev/agentTooling` or `~/.claude`. `--self` everywhere; gate
`bash self/gate.sh` (~3 min; verdict line must read `all checks passed`). Timing
stamps: `./stamp-timing.sh --self self-corpus-identity checkpoint status=<status>`.

## Read, in this order

1. This file, then `AGENT_DIRECT.md` → "The procedure" and "Checkpoint and resume".
2. `self/review-report.md` → "Escalated to the next batch", items 1–4. That section is
   the whole spec; the rest of the report is context.
3. `self/features/self-corpus-identity/NOTES.md` and `CHECKPOINT.md` — the build's
   rulings; do not reopen them.
4. `self/tests/session-claims.sh` phase 10 (the vendored fixture you extend) and
   assertion 7 (the annotate-only pattern you reuse); `self/tests/README.md`;
   `self/gate.sh` and `self/tests/sync-check.sh` before deciding where item 2's check
   lives.

## Rulings (settled)

1. **Item 1** — add the three assertions exactly as the report names them, in phase 10,
   after the existing `--recapture` runs: a plain `--all` against the frozen record with
   a second feature's ledger claim seeded; `also_claimed_by` names
   `agentTooling/claim-self-twin`; no entry ends in `/claim-here`; the ledger row for the
   frozen record carries the declared identity. Prove (b) red against `main`'s
   `analysis/` the same way the build proved phase 10 red, and record the table in
   NOTES.md under a `# Rework` heading.
2. **Item 2** — a check that `roots.SELF_CORPUS_IDENTITY`, `update.sh`'s
   `DEFAULT_REMOTE` and the root `README.md`'s subtree commands carry one string. Put it
   where the gate already checks `update.sh` if such a place exists, else its own short
   `self/tests/*.sh` with a README row. Three literal sources, one check, no model.
3. **Item 3** — check `git -C "$VHOST" remote get-url origin` equals `$VENDOR_ORIGIN`
   right after the `remote add`, as a `check` line.
4. **Item 4** — rename `repo_identity`'s parameter to `checkout_dir`, and reword the
   docstring paragraph at `capture_planning.py` ~527 and `self/PROJECT_FACTS.md` ~131 so
   the distinction is stated as conceptual (which repo a *checkout* is vs. which corpus a
   *feature* belongs to) with no claim of a live `session_root` call. No session-side
   call is reintroduced.

## The finish

Rewrite `CHECKPOINT.md` whole for the rework's slices; append the `# Rework` half to
`NOTES.md`; update `self/tests/README.md` rows touched; gate green; commit on the branch
as `self-corpus-identity: rework — <what>`. Do not push, do not touch the manifest fence,
no stash/checkout/reset/rebase.

## The report

Terse: gate verdict line; files changed; the red-proof line for item 1(b); where item 2's
check lives and why; anything left undone.
