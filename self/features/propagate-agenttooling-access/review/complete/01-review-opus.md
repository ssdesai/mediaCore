# 01 — review: propagate-agenttooling-access

"No findings" is a legitimate verdict (AGENT_PLANS.md → "Review plans"). Fix local
findings in the pass; escalate structural ones.

## What the feature was supposed to do

On 2026-10-26, propagating agentTooling PR 90 from Claude Code cloud sessions, three of
four consuming repos' `agentTooling/update.sh` failed at `git subtree pull` from
`https://github.com/ssdesai/agentTooling`: authentication failed until the session ran the
`add_repo` tool (claude-code-remote MCP) for `ssdesai/agentTooling` with read access. A
cloud session's git proxy serves only repos attached to the session, and nothing in the
docs said so.

The spec asked for:

1. That step documented where a propagating session reads it: `LIFECYCLE.md` →
   "Propagate" step 2 (cloud path), `README.md` → "Updating", and wherever else the cloud
   pull is described (`self/DESIGN-2026-10-05-cloud-execution.md`, docs the README index
   names).
2. Optionally, `update.sh` recognising the failure in the cloud profile — an auth/403 from
   the subtree fetch when `env-profile.sh` says cloud — and printing a one-line remedy
   naming the agentTooling repo to attach. **Only if reliable and tested offline in
   `self/tests/`** (see `self/tests/update-cloud-branch.sh`); otherwise docs-only, with the
   ruling in the feature's `NOTES.md`.
3. READMEs kept current per `CONVENTIONS.md`; `./self/gate.sh` green.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- **The remedy is cloud-only and auth-only.** Under the local profile, or for a pull that
  fails for another reason (missing remote, merge conflict, dirty tree), `update.sh`'s
  output and exit code are what they were before. Under cloud with an auth failure, exit
  is still `1` and git's own error is still shown; exactly one extra line is added.
- **`update.sh` still survives overwriting itself.** Everything new runs inside `main()` or
  a function defined before it; nothing is added after the last line `main "$@"`.
- **Profile confinement holds.** `update.sh` must not spell `CLAUDE_CODE_REMOTE` or
  `AGENTTOOLING_PROFILE`; it asks `env-profile.sh` (`self/profile-confinement.sh`).
- **No regression in the pull path.** stdout and stderr of a successful pull still reach
  the caller; the exit status of `git subtree pull` is the one tested, not `tee`'s; no
  temporary file is left behind.
- **The test is not vacuous and needs no network.** U6 must fail if the remedy is removed;
  U7/U8 must fail if the remedy is printed unconditionally. U1–U5 unchanged.
- **Docs are where a propagating cloud session reads them**, accurate (the tool is
  `add_repo`, read access, `ssdesai/agentTooling`), and do not restate the rule in a way
  that contradicts `update.sh`'s actual behaviour.
- **READMEs**: the root `README.md`'s `update.sh` entry names the new `env-profile.sh`
  dependency (CONVENTIONS.md Rule 2); `self/tests/README.md` describes U6–U8.
- `NOTES.md` records why the code change was taken rather than docs-only.

## Verdict

First line of the review report the runner names: `Verdict: clean` or `Verdict: escalated`.
