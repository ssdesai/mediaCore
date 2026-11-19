# Notes — harness-ablation-methods

Rulings that are judgement rather than spec.

- **Neutralize by skip-worktree, not by a CLI flag.** `--setting-sources` would drop the
  project settings but, as the SDK uses it, also every project `CLAUDE.md` — taking the
  project text with the conventions, two layers in one rung. Rewriting the files in place
  under skip-worktree removes exactly the import lines and the `hooks`/`permissions` keys,
  keeps every other byte, and no commit shape short of `--sparse` can carry the change
  (probed on git 2.43: `add -A`, `commit -a`, `add <file>`, `add -f`).
- **Keep the project part of root `CLAUDE.md`** in `vanilla`, identical to `vanilla-conv`:
  it is the codebase's own documentation; the ladder changes one layer per rung.
- **The nested `agentTooling/CLAUDE.md` import is dropped too**: Claude Code loads it lazily
  when the session reads under `agentTooling/`, which would bring the conventions back.
- **The SessionStart hook goes with the PreToolUse one**: it is `agentTooling/session-start.sh`.
- **The harness-mandated parts stay in the vanilla brief**: the `feature:` line (cost
  capture), isolation, the gate command, `forge.sh pr-open` and the banner, and
  "decide, do not ask" (a headless run has nobody to answer).
- **Verify fails the method** (exit 1) when a commit touched a neutralized file: the PR is
  already pushed by then, so the honest record is a failed cell, not a silent repair.
- **Accept at PR-open lives in `settle_pr`**, so a `no-pr` resume measures it too; no new
  stage name, so `--from` is unchanged.
- **`state_json_or_null` now reads with `has()`**: `// null` turned a stored `false` into
  `null`. Same result for every existing caller (integers or null).
- **Scorecard (coordinator's additions)**: failed rows out of cost means and band lines;
  `Failed` and `Spend` (to-green + `cost_lost_usd`, every run) appended after the existing
  Per cell columns so earlier assertions and byte-held renders keep holding; the per-check
  table only when a probe line carries an id like `A1`, so older ledgers gain no section.
