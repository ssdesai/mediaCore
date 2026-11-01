# Spec: review-base-and-cloud-hook

The handoff this feature was planned from, verbatim from "Background" on. The decisions
here are settled; the implementer does not reopen them.

## Background
Cloud fixes already merged in ssdesai/agentTooling#85:
- feature-start fast-forwards local main in the cloud;
- LIFECYCLE.md opens with a local/cloud table;
- new session-start.sh as the SessionStart hook.

This feature is the agreed follow-up: two parts, B first, in one feature, since a container
holds one feature.

## Part B: the review compares against origin/<base>, not local <base>
Problem: the review diffs `<base>...HEAD` against LOCAL main, which can be older than the point
where the feature branched off. The three dots use the merge-base, so a NEWER main is harmless;
only an OLDER one leaks already-merged commits into the review and the PR description.

Remaining ways that happens, in both profiles:
- the feature merges a newer origin/main mid-way (the conflict-fix path) without local main
  being updated;
- a review runs in a fresh container whose local main is whatever the clone had;
- a consumer that hasn't pulled #85.

Agreed fix (no recorded sha, no new manifest field):
- run-review.sh runs `git fetch origin <base>` before each pass: best-effort, warn and carry
  on if it fails.
- The diff is taken against `origin/<base>...HEAD`, falling back to `<base>` when there is no
  remote. Places that name the diff today:
  - feature-start.sh, the review stub ("Base is `$BASE`. `git diff $BASE...HEAD --stat`");
  - run-review.sh, the prompt step 3 ("`git diff <base>...HEAD` … the plan names the base");
  - AGENT_DIRECT.md (`git log --oneline <base>..HEAD`).
- The PR target stays the branch name (pr.sh's FEATURE_BASE) — GitHub needs a branch there.
- Keep feature-start's own fetch and local-main fast-forward as they are.

Test: a feature that merged a newer origin/main while local main stayed stale. The review must
compare from the right point. Run it under BOTH profiles (behaviour must be identical).

## Part A: the hook refuses wrong-environment git commands in the cloud, with a cloud-correct reason
Problem: hooks/allow-repo-commands.sh has one deny reason, GIT_DENY_REASON, that describes only
the local layout ("run it from the primary checkout … edit inside .worktrees/<slug>, never in
the primary"). In the cloud that advice is wrong. Also, `git switch main`, `git checkout main`
and `git push origin main` (any push to another branch) are PROMPTS today
(self/tests/allow-repo-commands.sh ~587-589). In the cloud they should be refused.

Agreed design, in this order:
1. Shared detection module.
   - Move the profile rule into ONE Python module, hooks/env_profile.py. Do NOT name it
     profile.py: that shadows a standard-library module.
   - The rule: an explicit AGENTTOOLING_PROFILE wins (a value other than local/cloud is an
     error); else CLAUDE_CODE_REMOTE=true → cloud; else local. It returns the profile and what
     decided it, and is the only place either variable is spelled.
   - The hook imports it in-process, the way it imports hooks/policy.py: no extra process per
     Bash call.
   - env-profile.sh calls it ONCE when sourced (one python3 call) to set AGENTTOOLING_PROFILE
     and PROFILE_DECIDED_BY, and keeps all its bash functions unchanged, so feature-start.sh,
     forge.sh, session-start.sh and the templates need no edits.
   - self/profile-confinement.sh: the module replaces env-profile.sh as the detector in the
     allowlist. The hook is NOT allowlisted, because it never spells the variables itself.
   - Editing hooks/ triggers the existing ask rule; that's intended.
2. The deny reason is chosen by profile.
   - Local: unchanged.
   - Cloud: this container is the feature's checkout on <branch>; run
     ./agentTooling/feature-start.sh <slug> here (./feature-start.sh --self in agentTooling);
     never create, switch or delete a branch; push only <branch>. Name the started feature and
     its close when one exists, as session-start.sh does.
3. Two cloud-only denies, added as entries in hooks/policy.py's table:
   - switching to any branch other than the current one;
   - a git push whose target is not the current branch (e.g. `origin main`, `HEAD:x`, `--all`,
     `--mirror`).

   Plain `git push` and `git push -u origin <current>` keep today's answer. Locally nothing
   changes.

Tests (decided):
- Write the table FIRST, before code: every case with its expected LOCAL and CLOUD answer, run
  under both profiles. Include the differing cases:
  - `git switch main`, `git push origin main`: local prompt; cloud refused with the cloud
    reason;
  - `git checkout -b x`: local refused with the local reason; cloud refused with the cloud
    reason.
- Include cases that must NOT differ:
  - `git push -u origin <current>`: prompt in both;
  - reads: approved in both.
- Run ALL existing allow-repo-commands.sh cases under both profiles, expecting identical
  answers.
- Pin the profile in every hook test (AGENTTOOLING_PROFILE set, CLAUDE_CODE_REMOTE cleared):
  this container sets CLAUDE_CODE_REMOTE=true, so unpinned tests silently test the wrong
  profile.
- Cover the module itself: the three detection steps plus an invalid override, through both
  the Python import and env-profile.sh.

What the hook reading the profile does NOT open up, for the review:
- An env prefix on a command (`AGENTTOOLING_PROFILE=local git push …`) affects only that
  command, not the hook, and is already an ASK.
- If detection fails in the cloud, behaviour falls back to today's prompts.
- The harness's own scripts aren't affected: the hook sees only the typed command, not the git
  run inside feature-close.sh or update.sh.

## Record, don't build
Add two entries to self/BACKLOG.md, in its existing style (a bold one-line title, then the
detail, then "Raised by …").

1. **A squash-merged cloud branch can't start its next feature.**
   - After a PR is squash-merged, the session's assigned claude/… branch still carries commits
     not on origin/main, though its tree is identical.
   - So feature-start.sh refuses a next feature there ("somebody's work"), and no agent can
     reset the branch: the hook denies reset --hard, checkout -B and force-push
     (LIFECYCLE.md rule 2).
   - Possible fix: the start recognises a branch whose tree equals origin/<base> (or whose own
     commits are all patch-equivalent, `git cherry`) and resets it itself, since the start is
     the one place allowed to move refs; the close then pushes with --force-with-lease.
   - Raised by the session that merged ssdesai/agentTooling#85.

2. **Running several features at once from one cloud orchestrator is undocumented.**
   - Agent-tool subagents share the orchestrator's container and branch, so they can't hold a
     second feature.
   - Child cloud sessions (create_session) each get their own container and claude/… branch,
     so each can run feature-start.sh and coordinate one feature.
   - ORCHESTRATION.md covers routers, coordinators and in-session delegates, but not this. It
     should say:
     - how the orchestrator spawns and briefs children;
     - how it monitors them: get_session and list_events, steering with send_message. A cloud
       child can't message its parent back; the parent is only notified when a child's turn
       fails;
     - that permission prompts must be answered in each child's session;
     - that overlapping features merge in PR order, the later one resolving conflicts;
     - where the orchestrator's own cost goes: it never runs a start, so no routing record is
       written and its spend is attributed to no feature. Decide whether that's acceptable or
       whether it needs a record of its own.
   - Until then create_session has only been used to acceptance-test self-cloud-bootstrap.
   - Raised by the same session.

Keep READMEs current per CONVENTIONS.md: README.md's rows for touched scripts, hooks/README.md,
self/tests/README.md, self/README.md.

## Round 2: a push to `main` is refused in BOTH profiles

Decided by the human after round 1's clean review (PR #86 open). This supersedes "Locally
nothing changes" for exactly this one shape and nothing else.

- **A `git push` whose destination is `main` is denied in both profiles**, every spelling:
  `origin main`, `-u origin main`, `origin HEAD:main`, `origin x:main`, `origin +main`,
  `origin refs/heads/main`, `--repo origin main`, `--repo=origin main`, a deletion
  (`origin :main`, `--delete origin main`), and behind git's global options
  (`git -C <root> push origin main`). The protected name is a constant in
  `hooks/policy.py`'s table (`main` only — not `master`, not the manifest's base; one
  literal, no probe), and the entry is **hook-only**: no `permissions.deny` prefix rule,
  since a prefix cannot tell `main` from `main-x`, so `bash_deny_rules()` and
  `.claude/settings.json` stay unchanged.
- **Reasons are by profile.** Locally a new reason: agents never push `main`; push the
  feature's own branch, and work reaches `main` only through the PR `feature-close.sh`
  opens and the human merges (LIFECYCLE.md rule 2 and step 6). In the cloud, the existing
  cloud reason.
- **Locally the judge runs no git probe**: it reads the destination from the command words
  alone. So a bare `git push` (or `git push origin HEAD`) while checked out on `main`
  locally is NOT caught and stays a prompt — record this as a ruling. In the cloud, where
  the hook already reads the current branch, a push whose resolved target is `main` is
  refused even when `main` is the current branch.
- **Fix the `--repo` spelling for the cloud push judge too** (round 1's review note):
  `--repo <r>` / `--repo=<r>` takes a value, and what follows are refspecs, so
  `git push --repo origin main` is judged like `git push origin main` in both profiles.
- Must NOT change: `git push origin mainline`, `git push origin feature/main`,
  `git push origin main-x` (local prompt; cloud as round 1 — refused as "not the current
  branch"), plain `git push` and `git push -u origin <current>` (prompt in both, unless
  current is `main` in the cloud), every other existing case.
- Tests: the both-profile table in `self/tests/hook-cloud-profile.sh` gains these rows
  with their local and cloud answers; `self/tests/allow-repo-commands.sh`'s
  `("git push origin main", "prompt")` moves to the denied set; `policy-table.sh` asserts
  the new entry renders no prefix rule.
- Docs: `hooks/README.md` (the git shape by profile), `LIFECYCLE.md` rule 2's list of
  denied shapes, `README.md`'s `hooks/` row, `NOTES.md` rulings.

## Round 4: a re-capture on the branch can move `to` later

Decided by the human after round 3's close, which left about $14.63 of this feature's own
later work unclaimed.

**The defect.** `feature-capture.sh` step 2 stamps `session_window.to` from
`capture_planning.py --last-branch-instant <slug>` with `set-window-to --replace`, and its
doctrine says the bound "moves EITHER way, so a re-run after more work moves it later"
(also `LIFECYCLE.md` step 6). It cannot. `last_branch_instant` admits a session only when
`in_window(min(timestamps), normalize_window(manifest))`, and that window carries the `to`
the PREVIOUS capture stamped. Every session that begins after the first stamp — a later
round's review runner, a rework implementer's parent, a new coordinator session — starts
after `to`, is not admitted, and contributes no evidence. So once a feature has been
captured on its branch, its `to` can never move later. Observed here: round 1's close
stamped `2026-10-07T19:16:08Z`; rounds 2 and 3's runner sessions (2026-10-08, 2026-10-10)
were never admitted, and round 3's close left the bound alone.

**The fix.**
- When the capture runs **on the branch** (the provisional path that uses
  `set-window-to --replace`), the evidence ignores the fence's `to`: a session is admitted
  on `from`, branch, cwd and exclusions exactly as today, with no upper bound. One explicit
  option or parameter (e.g. `--last-branch-instant <slug> --ignore-to`, or an
  `ignore_to=True` argument), named for what it does; `feature-capture.sh`'s on-branch
  path passes it. A named constant or flag, not a magic literal.
- **Unchanged:** the post-merge path (`--recapture` with `--tighten`, which only ever
  moves the bound earlier — it keeps reading the window as written); the open-co-claimant
  bounding in the claim index (`provisional_to`, which only runs for a window whose `to`
  is null, where the two readings agree); the pin route still contributes no evidence (the
  docstring's rationale stands); runner sessions still count; `exclude_sessions` still
  honoured.
- The doc that promises the either-way move (`feature-capture.sh`'s header step 2,
  `last_branch_instant`'s docstring, `LIFECYCLE.md` step 6, `analysis/README.md` where it
  describes `--last-branch-instant`) says how it is now true.

**Tests.** A self test (extend whichever `self/tests/` file covers the window stamp —
`self/tests/README.md` names it — or add one, recorded by `self/gate.sh` with its README
row): a feature already captured with `to` = T, then a new branch session that begins
after T; a re-capture on the branch moves `to` past that session's last instant. And the
same set-up through the post-merge `--recapture` path still never widens. Show the new
assertion red against today's code first.

**This feature's own record** is then corrected by the round-4 close itself, which runs
the fixed capture: no hand edit of the fence.
