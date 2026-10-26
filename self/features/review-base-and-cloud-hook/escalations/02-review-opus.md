Verdict: escalated

# Review — review-base-and-cloud-hook, round 2

## What round 2 was supposed to do

`SPEC.md` → "Round 2": refuse a `git push` whose destination is `main` in **both**
profiles, for every spelling. Locally the hook reads it from the command's words alone, with
no git probe, and gives a new reason of its own. In the cloud it gives the existing cloud
reason, and the current branch resolves `HEAD` and a bare `git push`. The protected name is
one constant in `hooks/policy.py`. The entry is hook-only: no prefix rule, and
`.claude/settings.json` is unchanged. The round also fixes the `--repo <r>` / `--repo=<r>`
reading in both push judges. Nothing else was supposed to move.

## Does it do it

Yes. The code is correct and the change is scoped as the spec asks. The only open item is a
documentation line that I could not edit from this pass.

- **The diff I reviewed** was `0e3e4d1..HEAD` (round 1's review commit to the round-2
  commit). The whole-feature stat shows only the expected files: the hook, `policy.py`,
  three test files, the docs and the feature records. Round 1's code paths are untouched
  apart from `push_goes_elsewhere`, which was refactored onto the new `push_reading` and
  `refspec_destination` helpers and keeps the same behaviour.
- **Every spelling the spec lists is denied in both profiles.** `self/tests/hook-cloud-profile.sh`
  has a row with the local and cloud answer for each one, and runs every row under both
  profiles. I also probed spellings that are not in the tables, under both profiles with the
  profile pinned:
  - **Denied in both:** `main~1:main`, `:refs/heads/main`, `+refs/heads/main`,
    `-o ci.skip origin main`, `-oci.skip`, `--push-option x`, `-- origin main`,
    `origin -- main`, `--set-upstream`, `@:main`, `-q`, a double-quoted `"main"`, a push
    followed by `;` or `||`, and a push inside `$(…)`.
  - **Still a prompt locally:** `main:refs/tags/x`, `main:mainline`, `refs/remotes/origin/main`,
    `--receive-pack main origin x`, `--exec=main origin x`, `git push origin HEAD`, a bare
    `git push`, and a `--repo origin` with no refspec. The cloud refuses the ones whose
    target is not the current branch, as round 1 did.
- **No false refusals.** `mainline`, `feature/main`, `main-x`, `main:x`, `git log main`,
  `git checkout main -- f`, an `echo` of the text and a commit message containing it all keep
  their answers. Ruling 22 (`main` as the source only is not a push to `main`) follows the
  spec's wording, "whose destination is `main`", and is recorded in `NOTES.md`.
- **Locally there is no git probe.** X1 covers the whole table, X1b covers the `main`
  checkout (M) and X4 covers pushes to `main`. All of them run under the logging `git`
  stub and assert zero calls. Ruling 21 records that a bare `git push` on `main` stays a
  prompt locally.
- **The cloud refuses a push whose resolved target is `main`.** `cloud_refuses` adds
  `push_reaches_protected(rest, branch)`, and `ON_MAIN_TABLE` asserts that a bare
  `git push`, `origin HEAD` and `--repo origin HEAD` are refused there while still prompting
  locally.
- **The table stays hook-only.** The new table is the sibling `GIT_HOOK_ONLY`, with
  `hook_only_rule()`; the renderers never read it. `policy-table.sh` §7 asserts that no
  rendered rule matches any spelling of the push, and `bash_deny_rules()` and
  `.claude/settings.json` are unchanged.
- **The reasons are right for each profile.** The local reason names rule 2, the feature's
  branch, the PR `feature-close.sh` opens, and the human merge. R5 asserts it contains
  nothing cloud-specific, and R6/R6b assert the cloud reason. One wording note, not
  escalated: "push the feature's own branch — the one you are on" assumes the session is
  on the feature's branch. That matches the existing `GIT_DENY_REASON`, which already says
  "Commit on the branch you are on".
- **The `--repo` fix covers the cloud judge too.** `git push --repo origin x` and
  `--repo=origin x` are prompts locally and refused in the cloud. Ruling 25 records that this
  reading departs from git's own precedence, and that the departure can only refuse more.
- **Nothing else moved.** I diffed the test tables. The only expectations that changed are
  the `… main` rows going from prompt to denied (`origin main`, `+main`,
  `origin <branch> main`, `refs/heads/main`, `-C <root> push origin main`), which is exactly the spec's
  change. F1b on a detached HEAD was re-pointed from `origin main` to `origin x`, so it
  still tests the cloud-only fallback, and the new F1d asserts that `main` is denied there.
- **Malformed input never crashes the hook.** F4 covers `--repo`, `--repo=`,
  `origin --repo`, `-o`, `:`, `+` and `''` in both profiles. `names_protected_push` wraps
  its reading in `try`, and the cloud path was already guarded.
- **Gate:** `self/gate-report.txt` is green, and none of its checks is SKIPPED.

## Fixed in this pass

Nothing. My one attempted fix was to `hooks/README.md`, which sits under the `Edit` ask rule
for `hooks/`. A headless pass cannot approve that prompt, so the fix is escalated below.

## Escalated to the next round

1. **`hooks/README.md:1292-1305` — the list of constants the hook binds and owns has
   drifted.** The paragraph names the policy objects the hook binds "under the same names —
   the cloud-only entries (`GIT_CLOUD_ONLY` and its flags) included", followed by the
   argument-reading constants that "stay here". Round 2 added names to both groups and the
   paragraph lists none of them:
   - the bindings `PUSH_TO_PROTECTED`, `GIT_PROTECTED_BRANCH` and `GIT_HOOK_ONLY_RULE`
     (`= policy.hook_only_rule`), at `hooks/allow-repo-commands.sh:340-342`;
   - the hook's own `GIT_PUSH_PROTECTED_DENY_REASON`;
   - the reading constant `GIT_PUSH_REPO_FLAG`, at `allow-repo-commands.sh:357`.

   The fix is a few words in that paragraph:
   - after "(`GIT_CLOUD_ONLY` and its flags) included", add: ", and the both-profile
     push-to-`main` entry (`PUSH_TO_PROTECTED`, `GIT_PROTECTED_BRANCH`,
     `GIT_HOOK_ONLY_RULE` bound to `policy.hook_only_rule`), whose local reason
     `GIT_PUSH_PROTECTED_DENY_REASON` is the hook's own";
   - add `GIT_PUSH_REPO_FLAG` before `GIT_PUSH_VALUE_FLAGS` in the reading list.

   This is a local, attended edit, or one for a build plan that is allowed to edit `hooks/`.
   No code changes.

No other findings. No invariant is left without a test: every behaviour the spec states has
a table row or a named assertion (T, R5–R6, F1d/F2c/F3c/F4, X1b/X4, policy-table §7).
