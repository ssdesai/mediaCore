# 01 — review: sandbox-consumer-reads

## What the feature was supposed to do

Record a finding, close the doc gap it exposes, and ship the sandbox block switched
off — code kept, `enabled: false` — until the read problem below is solved on the
user's machine.

The finding (Claude Code 2.1.286, https://code.claude.com/docs/en/settings-reference.md
→ "Sandboxed commands under the block"): while `permissions.blockReadsOutsideWorkingDirectories`
is on — it is, in the user's global settings — the sandbox denies every read under the
home directory to a Bash subprocess, and **`allowRead` entries from repository settings
don't count**. A live probe from a sandboxed `claude -p` in this worktree, with a
temporary `allowRead` for `~/Library/Caches/ms-playwright` in the generated settings,
was still refused (`Operation not permitted`). So the Playwright cache a consumer's
verify pass needs can only be re-opened from user or managed settings, never by
`hooks/wire-settings.py`.

Deliverables: (0) A single switch constant `SANDBOX_ENABLED = False` in
`hooks/wire-settings.py` from which `SANDBOX_OWNED_SETTINGS` takes `enabled`; the rest
of the block (`failIfUnavailable`, `allowUnsandboxedCommands`, `denyRead`,
`allowedDomains`) is generated unchanged; the generator still owns `enabled` in both
layouts, so a consumer copy switched on by hand is set back to the constant's value.
Tests in `self/tests/hook-wiring.sh` and `self/tests/self-settings.sh` assert the value
and the ownership. (1) `hooks/README.md` → "The sandbox block" opens by saying the block
is generated but off by default, why, and that flipping the constant plus a propagation
pull turns it on; `RUNNER.md`'s sandbox paragraph is conditional and says the runners
currently execute without the OS boundary. The same README section no longer says the fix is an
`allowRead` in this block; it states the rule, the probe, and that the re-allow is a
per-machine user-settings entry (`~/.claude/settings.json` →
`sandbox.filesystem.allowRead`), with the doc URL and version; `RUNNER.md`'s sandbox
paragraph says the same in one clause. (2) `self/BACKLOG.md`: the entry "No consumer
verify pass has run under the sandbox…" is rewritten so its fix is the user-settings
entry plus the vinyl verify run, not a constant; a new entry records that the runner's
gate executes agent-authored code (tests, conftests, `package.json` scripts, Playwright
configs) outside the sandbox, with an assertion. (3) NOTES.md holds the probe: the
command, the three result lines, the version, the doc sentence relied on. (4) Manifest
prose above the fence; the gate green.

## The diff

The branch was cut from `main`; judge `git diff main...HEAD --stat`, then the full diff.
Read `self/features/sandbox-consumer-reads/NOTES.md` for the implementer's rulings, but
judge against this brief, not against the notes.

## Contracts to hold it to

- `wire-settings.py`'s only behavioural change is the switch: `enabled` comes from
  `SANDBOX_ENABLED` (false), nothing else in the block changes, no `allowRead` is
  generated or asserted, and the ownership test shows a hand-enabled consumer copy set
  back to false. The worktree's regenerated settings pass `--self --check` (the gate).
- The README and RUNNER.md text is true to the doc: repo-level `allowRead` is dropped
  under the block; user settings are where it goes; the doc URL and version are cited.
- The rewritten backlog entry keeps its run-a-known-green-vinyl-verify assertion and
  names the user-settings prerequisite; the new gate entry names the gap precisely
  (`run_level_gate` / the batch re-gate run `gate.sh` from the runner's shell, not from
  `claude -p`), says why locking `gate.sh` alone does not close it, and has an assertion.
- NOTES.md's probe evidence is complete enough to re-run.
- READMEs of every touched folder are current; the gate is green.

Fix local findings in the pass; escalate structural ones. "No findings" is a legitimate
verdict.

## Verdict

First line of `self/review-report.md`: `Verdict: clean` or `Verdict: escalated`.
