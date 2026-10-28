# 01 — review: env-profile-set-e

## What the feature was supposed to do

`env-profile.sh`'s `detect_profile` reads the detector's two output lines with two
`IFS= read -r` calls inside a `{ … } < <(python3 -B … 2>/dev/null)` group. Its documented
contract: when the module cannot be asked (python3 missing, or `hooks/env_profile.py` not
beside the file) the profile is EMPTY, a warning naming the module goes to stderr, and
the sourcing script carries on so that `profile_check` can refuse by name.

Under `set -e` that contract broke: with no output, the first `read` hits EOF and
returns 1, and `set -e` kills the sourcing shell on the spot — silently, before the
warning. A consuming repo's `plans/gate.sh` sources `plans/environment.sh` under
`set -e`, which sources `agentTooling/env-profile.sh`, so a container or laptop with no
python3 lost its gate with no message (reported by a consuming repo's agent).

The fix makes both reads tolerate a failed command (`|| true`), so `detect_profile`
behaves the same under `set -e` as without it, and adds a self-test that sources the
file under `set -euo pipefail` with no python3 on `PATH` and with no module beside it.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `env-profile.sh`'s header: when the module cannot be asked, the profile is empty, the
  warning goes to stderr, and `profile_check` refuses — never a quiet `local`, and now
  never a silent exit under `set -e` either.
- The happy path is unchanged: one python3 call when sourced (M7), the same two lines
  read into `AGENTTOOLING_PROFILE` and `PROFILE_DECIDED_BY`.
- Nothing else in the sourced file may now fail a `set -e` caller on the
  undetected path — check the rest of `detect_profile` and the top-level assignments
  for the same shape, and say whether the new test would catch a regression of each.
- `self/tests/env-profile.sh`'s header list of assertions matches the assertions in the
  file; `self/tests/README.md` and `self/features/README.md` describe what changed.
- `templates/plans/environment.sh` promises to be safe under `set -u` and `set -e`; the
  file it sources must now keep that promise.

"No findings" is a legitimate verdict. Phrase any finding as an assertion a test could
make, and keep two lists: fixed here, and escalated to the next round.

## Verdict
