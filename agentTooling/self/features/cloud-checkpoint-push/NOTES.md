# cloud-checkpoint-push — rulings

The coordinator's rulings, written before the build. The brief is the session's task text
(the problem seen in a humanNetworkMap cloud session, compare-sources, 2026-11-07).

1. **Where pushes happen.** Under the `cloud` profile only: `feature-start.sh` pushes
   right after its `<slug>: start` commit; `run-review.sh` pushes once at the end of a
   round that recorded a verdict, after the stamps commit — the round commit and the stamps
   commit are made back to back, so one push carries both and leaves `origin/<branch>` at
   the local head. Nothing is pushed when the runner committed nothing (base branch,
   detached HEAD) — it pushes `branches[0]` only when the checkout is on it.
   `feature-capture.sh` keeps its push as is. Under `local` nothing changes, not even
   output.
2. **One push function, no retry.** The capture's `git push -q -u origin <branch>` (with
   its "no origin → skip" check) moves into `plan-runner-roots.sh` and is called by the
   capture and the checkpoints. `feature-close.sh` had no retry/backoff to reuse, so none
   is added: a checkpoint push is advisory (one warning line, the script's exit status
   unchanged), and every later checkpoint and the close's capture push the whole branch
   again, so a transient failure heals at the next one. The capture's push stays fatal
   there, as it was.
3. **`run-plans.sh` / `run-verify.sh`.** Neither script makes a commit (the executors
   may, under the plans method), so "push after each commit the script makes" adds nothing
   there. Whether to push after each *plan* is the owner's call — the brief named it as
   one; the default taken is **no**: the round's push carries every executor commit before
   it, and a plan run is not a checkpoint the lifecycle names. Recorded as an open
   question for the owner, not built.
4. **In-flight queue state.** Not changed. While a review pass runs, the executor edits
   tracked files (it fixes local findings) and the runner moves the brief
   `review/incomplete` → `review/inprogress` and appends to `timing.jsonl`; committing any
   of that mid-pass would race the executor and split one round across commits the close's
   head check does not accept. The round already ends on a clean tree (round commit, then
   stamps commit, now pushed). A Stop hook that fires *during* a background review will
   still see a dirty tree; the answer to it is "the runner commits and pushes at the end of
   the round" — documented in `LIFECYCLE.md` step 5.
5. **The hook's approval.** Approved silently only when all hold: the cloud profile
   (`env_profile`), the words are exactly `git [-C <path inside the root>] push
   [-u|--set-upstream] origin <B>` with no other flag and `<B>` a plain branch name (no
   `+`, `:`, `HEAD`, `refs/`), git reads the current branch as `<B>`, and a tracked
   manifest names `<B>` as `branches[0]` (the existing `started_feature` reading). Every
   probe failure approves nothing. The deny paths are evaluated first and unchanged. The
   remote name is a constant (`origin`), as in the shell.

## Taken in the build

Rulings 1–5 were built as written. What the build decided that they leave open:

6. **`run-review.sh` sources `env-profile.sh` only when it sits beside it.** Many fixtures
   copy `run-review.sh` with a short file list and no profile adapter; an unconditional
   `source` would break them with an error line. A copy without the adapter is a local one:
   `push_round` tests `declare -F profile_is_cloud` first and pushes nothing. Every real
   install ships the adapter.
7. **The checkpoint push sets `GIT_TERMINAL_PROMPT=0`** (`CHECKPOINT_TERMINAL_PROMPT`), as
   the review's fetch does: unattended, a credential prompt must fail the push, not hang the
   round. The capture's push is unchanged, prompt and all.
8. **Return codes, not output, from the shared function.** `push_feature_branch` prints
   nothing and returns 0 / `PUSH_RC_NO_REMOTE` / `PUSH_RC_FAILED`; the capture keeps its three
   lines and its refusal from them, and `checkpoint_push` is the advisory wrapper (one
   `  push` line, one `  warn` line, nothing with no `origin`). `ORIGIN_REMOTE` in the
   capture is now `PUSH_REMOTE`'s value; the hook spells `origin` once itself
   (`OWN_PUSH_REMOTE`), as it cannot source the shell.
9. **The hook's approval reads `-C <path>` only** among git's global options (`--git-dir`,
   `-c` before `push` prompt), requires the checkout's toplevel to contain
   `CLAUDE_PROJECT_DIR` (a nested repo does not count), and prefixes the features directory
   when the root is a subdirectory of the toplevel. All of it fails closed.
10. **`policy.py` is untouched**, so `.claude/settings.json` needs no regeneration: the
    approval is hook-only and renders no rule.
11. **The owner's open question** ("push after each plan in `run-plans.sh`?", ruling 3) is
    `self/BACKLOG.md`'s first-class entry, with the assertion that would close it.
