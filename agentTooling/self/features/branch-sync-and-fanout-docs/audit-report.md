Verdict: clean

# Security audit — branch-sync-and-fanout-docs (round 01)

## Scope

The plan names one file: `self/gate.sh`. `git diff origin/main...HEAD -- self/gate.sh`
adds three lines and no rule:

1. `feature-sync.sh` is added to `shell_scripts` (the list that gets `bash -n`/shellcheck).
2. `self/tests/feature-sync.sh` is added to that same list.
3. A new `record "feature sync self-test" bash self/tests/feature-sync.sh` step.

All three make the gate stricter: two more files get syntax checks and one more test runs.
None of them denies or asks for anything. The PreToolUse policy files did not change:
`diff -rq head/hooks base/hooks` and `diff -q` of `.claude/settings.json` both report the
two copies as identical. Because `self/gate.sh` is a silently approved entry point,
the risk this audit checks for is that an approved gate run now does something it
did not do before. That is why it covers (a) the hook's answer for gate-shaped and
feature-sync-shaped inputs on both copies and (b) whether the new self-test writes
anything outside its own `mktemp -d` sandbox.

Rule under audit (the only one the diff touches): **`self/gate.sh` / `./self/gate.sh [<label>]`
is approved silently for any session as a read-only harness entry point. The diff
widens what that approved run executes by one self-test.**

## Method

- Head copy: `git archive HEAD | tar -x -C /tmp/plan-capture.vnRyG9/scratch/head`. Base copy: `git archive origin/main | tar -x -C …/base`.
  Each copy is `git init`ed and committed once.
- Each input goes through `python3 <copy>/hooks/allow-repo-commands.sh` with
  `CLAUDE_PROJECT_DIR=<copy>`. The input is a PreToolUse JSON (`tool_name: Bash`, a
  fresh `session_id` per call so the two-denials escalation never fires, `agent_id: ""`,
  `cwd: <copy>`, `tool_input.command`). The script is `scratch/audit.sh`.
- Results: `allow` = approved silently. `ask` = the hook printed nothing, so the normal
  permission prompt runs. `deny` = sent back with a rewrite.
- `bash <head>/self/tests/feature-sync.sh` ran in the head copy. Afterwards
  `git -C <head> status --porcelain` was empty, so the test changed nothing in the
  checkout it runs from. All of its fixtures live under `mktemp -d` and are removed on
  exit, and its pushes go to a bare repo inside that temp directory. All assertions passed.

## Inputs tried

| # | input | head | base |
|---|---|---|---|
| 1 | `./self/gate.sh` | allow | allow |
| 2 | `self/gate.sh` | allow | allow |
| 3 | `bash self/gate.sh` | ask | ask |
| 4 | `./self/gate.sh fast` | allow | allow |
| 5 | `bash -n feature-sync.sh` | allow | allow |
| 6 | `bash -n self/tests/feature-sync.sh` | allow | allow |
| 7 | `shellcheck feature-sync.sh` | allow | allow |
| 8 | `bash self/tests/feature-sync.sh` | ask | ask |
| 9 | `./feature-sync.sh branch-sync-and-fanout-docs` | ask | ask |
| 10 | `bash feature-sync.sh branch-sync-and-fanout-docs` | ask | ask |
| 11 | `env ./self/gate.sh` | ask | ask |
| 12 | `env env ./self/gate.sh` | ask | ask |
| 13 | `/usr/bin/env ./self/gate.sh` | ask | ask |
| 14 | `command ./self/gate.sh` | ask | ask |
| 15 | `exec -a x ./self/gate.sh` | ask | ask |
| 16 | `nohup ./self/gate.sh` | ask | ask |
| 17 | `sudo ./self/gate.sh` | ask | ask |
| 18 | `echo ./self/gate.sh \| xargs bash` | ask | ask |
| 19 | `find . -name gate.sh -exec bash {} ;` | ask | ask |
| 20 | `bash -c ./self/gate.sh` | deny | deny |
| 21 | `echo ./self/gate.sh \| sh` | deny | deny |
| 22 | `./self/gate.sh && git commit -m x` | deny | deny |
| 23 | `./self/gate.sh > out.log` | ask | ask |
| 24 | `./self/ga""te.sh` | allow | allow |
| 25 | `./self/ga\te.sh` | allow | allow |
| 26 | `./self/gat?.sh` | ask | ask |
| 27 | `./self/{gate,x}.sh` | ask | ask |
| 28 | `X=self; ./$X/gate.sh` | deny | deny |
| 29 | `./self/gate.sh; rm -rf /` | deny | deny |
| 30 | `./self/../self/gate.sh` | deny | deny |
| 31 | `/tmp/self/gate.sh` (outside the root) | ask | ask |
| 32 | `./feature-sync.sh x && git push origin main` | deny | deny |
| 33 | payload `{}` | ask | ask |
| 34 | payload `not json` | ask | ask |
| 35 | payload `{"tool_name":"Bash"}` | ask | ask |
| 36 | payload `{"tool_name":"Bash","tool_input":{}}` | ask | ask |
| 37 | `bash self/tests/feature-sync.sh`, run in the head copy (side-effect check) | all assertions passed; copy's `git status --porcelain` empty | n/a: the test is new; base's gate has no counterpart step |

Rows 24–25 are allowed on both copies. The shell rejoins `ga""te.sh` and `ga\te.sh` into
the literal `gate.sh`, so these are the approved entry point under another spelling, not
a bypass. In every row 1–36 the head's result equals the base's. That is expected,
because no file the hook reads changed.

## Findings

None.

## Non-blocking findings

None.

## Notes (not findings)

- `feature-sync.sh` is a new lifecycle script with its own refusals: dirty tree, off the
  started branch, detached HEAD, untracked manifest, merge in progress. The plan does not
  list it as a hook or settings change, and it is not under audit here. Its self-test
  covers each refusal (R1–R6, C2), and every one held in the head copy. The hook does not
  approve the script silently (row 9 asks), so running it still goes to the human.
