# Notes: runner-sandbox

Built direct (`AGENT_DIRECT.md`) against Claude Code **2.1.284** (`claude --version`), on
macOS (Darwin 25.5, Seatbelt). Sandbox facts from
<https://code.claude.com/docs/en/sandboxing.md>, checked 2026-09-30.

## Rulings

- **No `denyWrite` of our own.** The backlog entry asked for a narrow `denyWrite` on
  `.git/hooks`, `.git/config` and `.claude`. With `enabled: true` Claude Code already
  applies built-in write denies that cannot be exempted: `.git/hooks`, `.git/config`,
  `.git/HEAD`, `objects/`, `refs/`, every `.claude/settings*`,
  `.claude/{skills,agents,commands,hooks,workflows}/`, `.mcp.json`, shell rc files,
  `.gitconfig`, `~/.claude/`, `~/.claude.json`. That is narrower than "all of `.claude`"
  — e.g. `.claude/` files outside that list stay writable by a subprocess — and the
  deviation is deliberate: the listed paths are the ones that execute or grant
  permissions, and restating them would only be a second list to drift. The `Edit` deny
  rules still cover all of `.claude/` for the Edit tool.
- **`strictAllowlist` left off.** Project settings also govern the user's interactive
  sessions, where a prompt for a new domain is useful; in `claude -p` there is nobody to
  answer, so the same prompt is a refusal. Attended sessions prompt, runners are denied.
- **`failIfUnavailable: true` and `allowUnsandboxedCommands: false` are owned, and reach
  every developer.** Raised by the validation run's reviewer. A machine where the
  sandbox cannot start cannot run Claude Code in a consuming repo, and `sync-plans.sh`
  switches both back on even if the repo changed them. Kept: the alternative is a batch
  that runs unsandboxed without saying so. The per-checkout override is
  `.claude/settings.local.json` (which also unsandboxes that checkout's runners). This
  amends `wire-settings.py`'s old "only restrictions" invariant; recorded in its
  docstring, `sync-plans.sh`'s header and `hooks/README.md` → "The sandbox block".
- **`autoAllowBashIfSandboxed` never written.** Bash approval stays the runner's
  `--allowedTools` and the hook's policy.
- **Merge semantics.** Owned scalars set wherever they stand (compared by identity, so
  `1` or `"true"` is wrong); `denyRead` and `allowedDomains` unioned, the repo's own
  entries first; every other sandbox key untouched. Under `--self` the block is
  generated like the rest of the file.
- **`describe_drift` compares entries without their trailing comma.** Appending to a list
  moved the comma onto the old last entry, which was then named as the drift.
- **An explicit `null` is INVALID, not absent** (`wrong_type` in `structure_error`).
  Raised by the reviewer: a write would `setdefault()` into the null and crash. Fixed for
  the pre-existing `hooks` / `permissions` keys too, since it is one function.

## Validation run

One real headless run under the generated settings: `run-review.sh --self runner-sandbox`
(opus, `claude -p --permission-mode acceptEdits --allowedTools Bash --add-dir <scratch>`),
2026-09-30T14:24Z–14:26Z, against the committed build (`2a8381d`). The reviewer confirmed
from inside the session that `enabled`, the three `denyRead` paths and the seven domains
were in its sandbox config.

- **Network:** no refusal. The pass ran `git`, `grep`, `ls` and `python3` only; nothing
  it did needed a host. **No domain added** by the run — the list stays the seven it
  was built with: the brief's six plus `objects.githubusercontent.com` (GitHub's
  release-asset host), which was written at build time, not added for a refusal.
- **Scratch directory:** writable. The executor wrote `probe.py` into
  `$TMPDIR/plan-capture.*/scratch/` with the Write tool and ran it with `python3 -B`; the
  launch's `--add-dir` is enough. **No `filesystem.allowWrite` added.**
- **Writes (the negative assertion, live):** the reviewer's probe opened existing files
  for append and wrote nothing. Excerpt from the stream:

  ```
  DENIED   /Users/sahildesai/dev/agentTooling/.git/hooks/pre-commit.sample (Operation not permitted)
  DENIED   /Users/sahildesai/dev/agentTooling/.git/config (Operation not permitted)
  DENIED   /Users/sahildesai/dev/agentTooling/.worktrees/runner-sandbox/.git (Operation not permitted)
  DENIED   /Users/sahildesai/dev/agentTooling/.worktrees/runner-sandbox/.claude/settings.json (Operation not permitted)
  ```

  So the built-in deny reaches the **common** git dir from a worktree (where `.git` is a
  file and the real hooks live in the primary). It went through a script in the scratch
  dir rather than `python3 -c`, which the hook policy refuses before the sandbox is ever
  reached; the OS-level result is the same `open()` either way.
- **Reads:** `ls /Users/sahildesai/Library/Caches` → `Operation not permitted`. The
  session's effective `denyRead` held the home directory, with the worktree and a few
  `~/.claude` subdirectories allowed back — not from this block but from
  `permissions.blockReadsOutsideWorkingDirectories`, which the sandbox enforces at the OS
  level. The rationale text was corrected to say so; a consumer Playwright run is filed
  in `self/BACKLOG.md`.

**What was removed afterwards** so the plan is back for the real review: the commit
`c3ff3c2 runner-sandbox: review round 1` stays in history, and a later commit undoes its
artefacts — `review/complete/01-review-opus.md` moved back to `review/incomplete/`;
`review/complete/01-review-opus.progress.md`, `review/complete/01-review-opus.usage.json`
and `escalations/01-review-opus.md` deleted; the untracked
`review/complete/01-review-opus.stream.jsonl` deleted; and the round's four
`timing.jsonl` stamps (`pass_start`, `plan_start`, `plan_end`, `pass_end`) removed. No
`self/review-report.md` was written (the verdict went to `escalations/`). **Deviation:**
that round-1 commit also swept up this build's then-uncommitted doc edits
(`RUNNER.md`, `hooks/README.md`, `self/tests/README.md`, the manifest prose), because the
runner commits the whole tree; no history was rewritten, and the later commits carry
the rest.

## The reviewer's other findings, and what was done

1. Slices unfinished at the time (NOTES, RUNNER.md, README rows, backlog, gate) — done
   in this build.
2. Read surface narrower than documented — text corrected; consumer run filed.
3. `null` crash — fixed, three `hook-wiring.sh` cases added.
4. `failIfUnavailable` reaching interactive sessions — ruling above.

## Open

- Linux/WSL (bubblewrap) not validated; a consumer Playwright verify pass under the
  sandbox not run — both in `self/BACKLOG.md`.
