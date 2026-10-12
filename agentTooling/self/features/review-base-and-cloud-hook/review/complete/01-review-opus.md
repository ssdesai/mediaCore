# 01 — review: review-base-and-cloud-hook

Written before the build, from the spec (the handoff that planned this feature, restated
below). Never from the implementer's report. "No findings" is a legitimate verdict.

## What the feature was supposed to do

Two parts, B first.

**Part B — the review compares against `origin/<base>`, not local `<base>`.** A review that
diffs `<base>...HEAD` against a LOCAL base older than the feature's branch point leaks
already-merged commits into the review and the PR description (a newer local base is
harmless: three dots take the merge-base). It still happens when the feature merges a newer
`origin/main` mid-way without updating local `main`, when a review runs in a fresh container,
and in a consumer that has not pulled #85. The agreed fix, with no recorded sha and no new
manifest field:

- `run-review.sh` runs `git fetch origin <base>` before each pass — best-effort: a failure
  warns and the pass carries on.
- The diff is taken against `origin/<base>...HEAD`, falling back to `<base>` when there is
  no remote. Every place that names the diff says so: `feature-start.sh`'s review stub
  ("Base is `$BASE`. `git diff $BASE...HEAD --stat`"), `run-review.sh`'s prompt step 3, and
  `AGENT_DIRECT.md`'s resume paragraph (`git log --oneline <base>..HEAD`).
- The PR target stays the branch NAME (`pr.sh`'s `FEATURE_BASE`) — GitHub needs a branch.
- `feature-start.sh`'s own fetch and local-main fast-forward are unchanged.

**Part A — in the cloud the hook refuses wrong-environment git commands with a
cloud-correct reason.**

1. **One detection module, `hooks/env_profile.py`** (not `profile.py`, which shadows the
   standard library). The rule: an explicit `AGENTTOOLING_PROFILE` wins, a value other than
   `local`/`cloud` is an error; else `CLAUDE_CODE_REMOTE=true` → cloud; else local. It
   returns the profile and what decided it, and is the ONLY place either variable is
   spelled (outside prose and tests). The hook imports it in-process like `policy.py` — no
   extra process per Bash call. `env-profile.sh` calls it ONCE when sourced (one python3
   call) to set `AGENTTOOLING_PROFILE` and `PROFILE_DECIDED_BY`, and keeps every bash
   function unchanged, so `feature-start.sh`, `forge.sh`, `session-start.sh` and the
   templates need no edits. `self/profile-confinement.sh` allowlists the module instead of
   `env-profile.sh` as the detector; the hook is NOT allowlisted.
2. **The git deny reason is chosen by profile.** Local: the existing `GIT_DENY_REASON`,
   unchanged. Cloud: this container is the feature's checkout on `<branch>`; run
   `./agentTooling/feature-start.sh <slug>` here (`./feature-start.sh --self` in
   agentTooling); never create, switch or delete a branch; push only `<branch>`; naming the
   started feature and its close when one exists, as `session-start.sh` does.
3. **Two cloud-only denies, as entries in `hooks/policy.py`'s table:** switching to any
   branch other than the current one; a `git push` whose target is not the current branch
   (`origin main`, `HEAD:x`, `--all`, `--mirror`, …). Plain `git push` and
   `git push -u origin <current>` keep today's answer (prompt). Locally nothing changes.

**Record, don't build:** two `self/BACKLOG.md` entries in its existing style (bold one-line
title, detail, "Raised by …"): a squash-merged cloud branch can't start its next feature;
running several features at once from one cloud orchestrator is undocumented (with the
points the spec lists: spawning and briefing children, monitoring via get_session /
list_events / send_message and that a child cannot message back, permission prompts
answered per child, overlapping features merging in PR order, where the orchestrator's own
cost goes).

## The diff

Fetch first (`git fetch origin main`), then compare against `origin/main`:
`git diff origin/main...HEAD --stat`, then the full diff. If there is no `origin`, use
`main`. This feature changes exactly that rule, so if the diff you get contains commits
already on `origin/main` (anything from PR #85 or earlier), say so — it is a finding
against Part B.

## Contracts to hold it to

**Part B**
- The fetch is best-effort: a failing `git fetch` (no network, no remote) prints a warning
  and the pass still runs; it never refuses and never changes the exit code.
- The fallback is real: a checkout with no `origin` (or no `origin/<base>`) diffs against
  `<base>` and says so, rather than handing the executor a ref that does not exist.
- All three named sites say the same thing, and no other place in tracked code or doctrine
  still tells a reviewer to diff against the bare local base (grep `\.\.\.HEAD` and
  `\.\.HEAD` across top-level scripts and `*.md`). `pr.sh` / `FEATURE_BASE` and the PR
  target are untouched.
- `feature-start.sh`'s fetch and fast-forward are unchanged (diff it).
- A test: a feature that merged a newer `origin/main` mid-way while local `main` stayed
  stale — the review's diff starts from the right point (contains only the feature's
  commits). It runs under BOTH profiles with identical results. Check it is in
  `self/tests/`, is recorded by `self/gate.sh`, and actually fails if the base is reverted
  to the local one (read the assertion, not just its name).

**Part A**
- `hooks/env_profile.py` exists under that name; no file named `profile.py` was added.
  It is stdlib-only, does no I/O beyond reading the environment, and returns both the
  profile and the decider. An invalid override is an error, never a silent `local`.
- `env-profile.sh` makes exactly one `python3` call when sourced, sets and EXPORTS
  `AGENTTOOLING_PROFILE` and sets `PROFILE_DECIDED_BY` with the same three values as
  before (`AGENTTOOLING_PROFILE`, `CLAUDE_CODE_REMOTE`, `default`), and every function it
  defined before is still defined with the same behaviour. `profile_check` still refuses an
  invalid value. Its callers (`feature-start.sh`, `forge.sh`, `session-start.sh`, the
  templates) are not edited for this.
- `self/profile-confinement.sh`: `hooks/env_profile.py` is in the allowlist,
  `allow-repo-commands.sh` is NOT, and the check still passes on the tree — so the hook
  spells neither variable. Whether `env-profile.sh` stays listed depends on whether it still
  spells a variable; if it does, it must be listed, and the README/comment must say why.
- The hook imports the module in-process (no subprocess for detection). Any subprocess it
  adds (e.g. to read the current branch or find the started feature's manifest) runs only
  on the cloud path of a git command that could be denied — never on every Bash call, and
  never locally.
- The two new denies are entries in `hooks/policy.py`'s table, not constants hidden in the
  hook. `policy.bash_deny_rules()` must be unaffected unless the change deliberately adds
  prefix rules — and if it does, `.claude/settings.json` was regenerated with
  `wire-settings.py --self --write` and `self/tests/policy-table.sh` still holds. (A prefix
  rule cannot express "a branch other than the current one", so the expectation is that
  these are hook-only, cloud-only entries; check the table says so.)
- Local behaviour is unchanged for EVERY existing case in `self/tests/allow-repo-commands.sh`
  — the spec requires all existing cases run under both profiles with identical answers,
  except the named differing cases.
- The decided differing cases hold: `git switch main` and `git push origin main` → local
  prompt, cloud refused with the cloud reason; `git checkout -b x` → local refused with the
  LOCAL reason, cloud refused with the CLOUD reason. Non-differing: `git push -u origin
  <current>` and plain `git push` prompt in both; reads approved in both. Also probe:
  `git switch <current branch>` (not refused), `git checkout -- README.md` and
  `git checkout <path>` (a file checkout is not a branch switch — must not be refused),
  `git checkout main` in the cloud (refused), `git push origin HEAD:x`, `--all`,
  `--mirror`, `--tags` (decide whether `--tags` is a target that is not the branch, and
  check the implementer recorded the ruling), `git -C <root> push origin main`, and a
  detached HEAD in the cloud (no current branch — what happens must be deliberate and
  recorded, and must not crash the hook).
- Every hook test pins the profile (`AGENTTOOLING_PROFILE` set, `CLAUDE_CODE_REMOTE`
  cleared). This container sets `CLAUDE_CODE_REMOTE=true`, so an unpinned test silently
  tests cloud. Check the test harness, not just a sample of cases.
- The module is covered: the three detection steps plus an invalid override, through BOTH
  the Python import and `env-profile.sh`.
- Failure modes stay safe: if detection fails or the branch cannot be read in the cloud,
  the hook falls back to today's answers (prompt), never to an allow and never to a crash
  (a crash in a `PreToolUse` hook is a hard stop for every Bash call in every consuming
  repo). Hook exceptions must not escape.
- The cloud reason is accurate: it names `<branch>`, the right start command for the repo
  shape (`./agentTooling/feature-start.sh <slug>` vs `./feature-start.sh --self` in
  agentTooling), and the started feature and its `feature-close.sh` when one exists. It
  never tells a cloud session to use `.worktrees/` or the primary checkout.

**Docs and records**
- `self/BACKLOG.md` has both entries, in its existing style, with every point the spec lists.
- READMEs current per `CONVENTIONS.md`: `README.md` rows for touched scripts
  (`run-review.sh`, `env-profile.sh`, `feature-start.sh` if its stub changed, `hooks/`),
  `hooks/README.md` (the new module with what it returns, the profile-chosen reason, the
  cloud-only entries), `self/tests/README.md` (a row per new or changed test file),
  `self/README.md`. `LIFECYCLE.md` rule 2 and `PROJECT_FACTS.md`'s mention of
  `env-profile.sh` as "the only place" the variables may be read should match the new truth.
- Named constants for every new magic value (`CONVENTIONS.md` → Named constants);
  bash 3.2-compatible shell; `set -uo pipefail` without `set -e`.
- `./self/gate.sh` green.

## Verdict

Write `self/review-report.md`. Its FIRST line is exactly `Verdict: clean` or
`Verdict: escalated`. Fix local findings in this pass (and say what you fixed); escalate
only structural ones — a contract the design itself gets wrong, or a fix too wide for a
review pass. Then the findings, each with file:line and what you checked; then what you
probed and found sound. No findings is a legitimate verdict.
