# Notes: sandbox-consumer-reads

## The finding

The original brief was to add `SANDBOX_ALLOW_READ` (the Playwright cache paths) as a
`sandbox.filesystem.allowRead` list in the block `hooks/wire-settings.py` generates. When
I checked how `allowRead` works against the docs before relying on it, the docs said it
could not work under the user's read block. The probe below confirmed that, and the
router rescoped the feature to recording the finding (review brief rewritten in f233b81).

**The doc sentence relied on.** Claude Code 2.1.286,
<https://code.claude.com/docs/en/settings-reference.md> → "Sandboxed commands under the
block" (fetched 2026-09-30):

> When sandboxing is on, the block also covers sandboxed commands. Claude Code denies them
> read access to your home directory and to the other roots that hold user files:
> `/Users`, `/home`, `/root`, `/Volumes`, `/mnt`, `/media`, `/run/media`, and `/srv`. It
> then re-opens the working directories, worktrees Claude Code creates in the session, the
> session temp directory, and the parts of `~/.claude` that commands need, such as skills
> and plugins. While the block is in force, `allowRead` and `allowWrite` entries from
> repository settings don't count.

The `sandbox.filesystem.allowRead` entry on the same page agrees: Claude Code "leaves out
entries from repository settings while `permissions.blockReadsOutsideWorkingDirectories`
is on". The sandboxing page (<https://code.claude.com/docs/en/sandboxing.md>) describes
`allowRead` as re-opening a path inside a `denyRead` region. That is true, but it does not
apply to the read block, which that page defers to the settings reference.

## The probe (live, 2026-09-30)

`claude --version` → `2.1.286 (Claude Code)`. The brief's facts named 2.1.284; the
installed version had moved on.

1. **Temporary, uncommitted** edit to `hooks/wire-settings.py`: an `allowRead` list with
   `~/Library/Caches/ms-playwright` and `~/.cache/ms-playwright`, written into
   `sandbox.filesystem` beside `denyRead`.
2. Regenerated the worktree's settings:
   `python3 -B /Users/sahildesai/dev/agentTooling/.worktrees/sandbox-consumer-reads/hooks/wire-settings.py --self --repo /Users/sahildesai/dev/agentTooling/.worktrees/sandbox-consumer-reads --write`
   → `wired`. The file then held `"enabled": true`, `failIfUnavailable: true`,
   `allowUnsandboxedCommands: false`, the three `denyRead` paths and the two `allowRead`
   paths.
3. A probe script `probe_reads.py`, written with the Write tool into the delegate's
   scratch directory. It calls `os.listdir()` on each path and prints `<path>: OK (<n>
   entries)` or `<path>: <OSError>`. The paths are `/Users/sahildesai/Library/Caches/ms-playwright`,
   `/Users/sahildesai/.ssh` and `/Users/sahildesai/Library/Caches`.
4. Launched in the runner's shape (`plan-runner-lib.sh` 783–791), with the worktree as cwd,
   from a launcher script, because the delegate's shell cwd does not persist:

   ```
   cd /Users/sahildesai/dev/agentTooling/.worktrees/sandbox-consumer-reads
   claude -p --model sonnet --permission-mode acceptEdits --add-dir <scratch> \
     --allowedTools Bash --output-format stream-json --verbose "<prompt>" > <scratch>/probe-stream.jsonl
   ```

   The prompt said to run `python3 -B <scratch>/probe_reads.py` sandboxed as usual (no
   `dangerouslyDisableSandbox`, no retry) and print its output verbatim. The launch was not
   refused and exited 0. The executor's one Bash call in the stream was that command,
   with no `dangerouslyDisableSandbox` input.

**Result, verbatim from the stream:**

```
/Users/sahildesai/Library/Caches/ms-playwright: [Errno 1] Operation not permitted: '/Users/sahildesai/Library/Caches/ms-playwright'
/Users/sahildesai/.ssh: [Errno 1] Operation not permitted: '/Users/sahildesai/.ssh'
/Users/sahildesai/Library/Caches: [Errno 1] Operation not permitted: '/Users/sahildesai/Library/Caches'
```

The positive read was refused with the repository `allowRead` in place, as the doc says.
Afterwards the temporary edit was removed (`git status` clean) and the settings were
regenerated from the unchanged constants.

To re-run: repeat steps 1–4 from the probe, or skip step 1 and put the `allowRead` in
`~/.claude/settings.json` → `sandbox.filesystem` instead. That variant is the fix the
backlog entry now names, and it has **not** been run.

## The off switch (scope addendum from the user, via the router)

After the rescope the user added one requirement: ship the sandbox block **switched off**,
with all its code kept, so it can be turned on once the Playwright read problem is solved
on the user's side. That made this a code change, so acceptance-tests-first applied
again. The tests went in as their own commit (9b17542), red against the old generator: every
written file had `enabled: True`, and E1/E8 in `self-settings.sh` failed. They are green
after the build.

- **`SANDBOX_ENABLED = False`** in `hooks/wire-settings.py` is the one switch.
  `SANDBOX_OWNED_SETTINGS` takes `enabled` from it. `failIfUnavailable: true` and
  `allowUnsandboxedCommands: false` stay as they were: inert while off, correct once on.
  The comment beside the constant gives the reason and says that flipping it plus a
  propagation pull is the whole procedure.
- **The generator still owns `enabled`**, with unchanged semantics: a consumer that
  turned the sandbox on by hand is set back to `false` on its next `sync-plans.sh`, so the
  constant is the one place to flip it. `hook-wiring.sh`'s `enabled-flip` case and
  `self-settings.sh` E8 assert the set-back. Once the switch is flipped, the same cases
  assert the other direction, because the fixture flips `enabled` against the switch
  rather than hardcoding `true`.
- **The tests hardcode the expected value** (`SANDBOX_ENABLED_EXPECTED = False` in
  `hook-wiring.sh`, `"False"` in `self-settings.sh`) rather than import it. A test that
  read the constant would pass whatever the constant said. Flipping the switch therefore
  means editing three lines, and the tests' comments say so.
- **What this switches off, where.** This worktree's generated `.claude/settings.json` was
  regenerated (`--self --write`), so the gate's `--check` passes. The primary checkout's
  file (`/Users/sahildesai/dev/agentTooling/.claude/settings.json`) keeps `"enabled":
  true` until it is regenerated after the merge. That can be `feature-start.sh --self`
  when the file is missing, or by hand with `python3 -B hooks/wire-settings.py --self
  --repo <root> --write`, and `self/gate.sh` there fails until it is regenerated. Every
  consumer's file switches off on its next propagation pull (`sync-plans.sh`). Until
  then a consumer runs sandboxed, as it did after #72.

## Rulings

- **Acceptance tests came first for the switch only.** Before the addendum there was no
  code change. The one candidate behaviour, an `allowRead` in generated output, is inert
  (the probe), and a test asserting it would lock in a no-op. No test asserts an
  `allowRead`, per the review brief's contract.
- **`wire-settings.py`'s `SANDBOX_DENY_READ` comment stays as is.** "That is the other
  layer's choice, not this one" is still true: this block does not, and cannot, override
  the read block.
- **The re-allow is documented as a user-settings entry, not written.** The user's
  `~/.claude/settings.json` belongs to the user. The doc excludes only *repository*
  entries under the block, so a user-settings entry should count. That is inference
  from the doc, not something a run has shown; `hooks/README.md` says so, and the backlog
  entry's assertion runs with it in place.
- **`hooks/README.md` → "The sandbox block"** is where the finding lives for readers;
  `RUNNER.md`'s sandbox paragraph points there in one clause.

## Backlog

- Rewrote "No consumer verify pass has run under the sandbox…": its fix is now the
  user-settings entry, then `SANDBOX_ENABLED = True`, then a propagation pull, then the
  known-green vinylCatalogue verify run. It is not a constant.
- Added "The runner's gate executes agent-authored code outside the sandbox", as the
  original brief's step 4 described it.
