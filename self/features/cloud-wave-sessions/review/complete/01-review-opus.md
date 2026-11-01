# 01 — review: cloud-wave-sessions

## What the feature was supposed to do

The spec, from the coordinator's brief. On 2026-10-26 a coordinator in a Claude Code cloud
container propagated agentTooling PR 90 into four repos using the claude-code-remote MCP's
`create_session`, one child per repo, with no `outcome_branch`. Each child improvised a
branch: two used `feature-start.sh --branch claude/pull-agenttooling-pr90`, one invented
`pullAgenttoolingPr90`, and one stalled on `main`. `ORCHESTRATION.md` said nothing about a
coordinator that spawns cloud sessions.

Scope (docs):

1. In `ORCHESTRATION.md`, the cloud-session coordinator shape. Cross-reference it from
   `LIFECYCLE.md` → Propagate, where that section describes a multi-repo round. It must say:
   - each child is created with its branch assigned up front (`outcome_branch`):
     `claude/pull-agenttooling-pr<N>` for a propagation, `claude/<slug>` for a self feature;
   - the child is then its feature's coordinator on that branch. The spec says "no pin, no
     routing record". See the finding below, which the build documents as a refinement;
   - the parent is a router, and its spend is routing overhead;
   - the brief is self-contained: it names the slug, the method and the close-on-clean rule;
   - the parent checks on children with `get_session`/`list_events`, not by polling with
     sleep, and archives children once their PR is open.
2. Check `self/DESIGN-2026-10-05-cloud-execution.md` for anything that contradicts this or
   should point at it.
3. Optionally, make `feature-start.sh`'s cloud refusal on `main` or a detached HEAD name
   `--branch claude/<slug>` explicitly. If it changes, it must be tested in `self/tests/`.
4. READMEs kept current per CONVENTIONS.md.

**Finding the builder reported, which you should verify or refute from the evidence
offered.** This feature's own session was created by `create_session` with
`outcome_branch: claude/cloud-wave-sessions`, and its checkout opened on a detached HEAD.
The SessionStart hook line and `git status` showed it, and `get_session` showed the
outcome branch. So the docs say the brief always passes `--branch <outcome_branch>` and the
child pins itself, per the existing design §10 ruling, rather than "no pin". Judge whether
that refinement is right and is stated consistently everywhere it appears.

Out of scope, and a finding if it is touched: the cost-window `from` for sessions that cut
their branch with `--branch`. The sibling feature `cloud-branch-window-from` owns it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff. Use the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every claim the new doc text makes about `feature-start.sh` matches the script: what it
  refuses, what it calls router or coordinator, what its "Next" lines print, and that
  `--branch X` while on `X` is accepted.
- The refusal names `--branch claude/<slug>` with the real slug. It says "a detached HEAD"
  and not "the base" when HEAD is detached. It still names the `--branch` flag, and it still
  creates nothing. `self/tests/cloud-start.sh` B1 and B2 assert all of this and pass.
  `CLOUD_BRANCH_PREFIX` is a named constant (CONVENTIONS.md → Named constants).
- The ORCHESTRATION.md, LIFECYCLE.md (step 2 and Propagate step 4), design doc and root
  README entries agree with each other. No rule is stated two different ways.
- No claim about the MCP tools is invented. Check them against the tool behaviour the text
  cites (`create_session`'s `outcome_branch`, `get_session`'s `status_bucket`,
  `list_events`' `kinds`, `archive_session`, `send_later`).
- No `sleep` or polling loop is recommended anywhere.
- READMEs touched where their content changed: root `README.md` and `self/tests/README.md`.
- `./self/gate.sh` is green.

"No findings" is a legitimate verdict.

## Verdict
