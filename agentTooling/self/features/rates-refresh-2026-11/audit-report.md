Verdict: clean

# Security audit — rates-refresh-2026-11 (01-audit-opus)

## What the diff changes

`git diff origin/main...HEAD -- analysis/rates_history.json` is the only audit-path change:
`checked` moves from `2026-10-13` to `2026-11-18`, and two models are appended
(`claude-fable-5-2`, `claude-mythos-5-2`, both `0000-01-01`, `source: litellm`). No existing
entry changes. The file triggers the audit only because `plan-runner-roots.sh`'s
`AUDIT_TOOLING_PATHS` lists `analysis/` whole.

**No hook rule is added or changed.** `hooks/allow-repo-commands.sh` and its sibling modules
never read `rates_history.json`, and nothing in `hooks/` imports `pricing`. The only
readers are `analysis/pricing.py`, which the hook does not import, plus two informational
lifecycle checks: `self/gate.sh` "pricing rate history is current" (`record_info`) and
`feature-capture.sh` § 8 residue, which only prints WARN or note lines. Neither one refuses
anything. The rule the data feeds that does block is the gate's
`self/tests/rates-history.sh`, which requires the history to be append-only and to price
the seed the same way. Its result on both copies is in the table below.

The audit therefore checks two things. First, that every hook decision is the same on the
head and on the base for the same inputs, including after this file is corrupted or
deleted in the copy. Second, that the lifecycle checks reading this file do not get more
permissive.

## Method

- Copies: `git archive HEAD` → `/tmp/plan-capture.zWHuF2/scratch/head`, `git archive origin/main` →
  `/tmp/plan-capture.zWHuF2/scratch/base`, each `git init`ed and committed so that
  git-reading rules can run. The real checkout was not touched.
- Hook: `python3 <copy>/hooks/allow-repo-commands.sh` with the PreToolUse JSON on stdin
  (`hook_event_name`, `tool_name: Bash`, a fresh `session_id` per input so the two-denial
  counter never trips, `cwd` = copy, `tool_input.command`) and `CLAUDE_PROJECT_DIR` = copy.
  Script: `scratch/audit.py {intact|corrupt|missing}`. `corrupt` writes `{not json` over
  `analysis/rates_history.json` in both copies, and `missing` deletes it there.
- Lifecycle checks: `scratch/rates_checks.sh` restores the file, then runs
  `self/tests/rates-history.sh`, `pricing.is_rates_stale()` and `pricing.get_rates` in each copy.

Results: **allow** = the hook prints `permissionDecision: allow`. **deny** = it denies and
gives the rewrite as the reason. **no output** = the hook gives no opinion and the call
goes to Claude Code's own permission check, which is the hook's designed "handed to the
human" path. All rc = 0.

## Inputs tried

Each row was run three times on both copies: with the file intact, corrupted and deleted.
All three runs gave the same result on head and base.

| # | input (`tool_input.command` or payload) | head | base |
|---|---|---|---|
| 1 | `cat analysis/rates_history.json` | allow | allow |
| 2 | `python3 analysis/refresh_rates.py --check` | no output | no output |
| 3 | `python3 analysis/refresh_rates.py` | no output | no output |
| 4 | `python3 analysis/refresh_rates.py --only claude-fable-5-2` | no output | no output |
| 5 | `sed -i 's/40/4/' analysis/rates_history.json` | deny | deny |
| 6 | `echo '{}' > analysis/rates_history.json` | deny | deny |
| 7 | `cp /tmp/x analysis/rates_history.json` | no output | no output |
| 8 | `env python3 analysis/refresh_rates.py` | no output | no output |
| 9 | `env env python3 analysis/refresh_rates.py` | no output | no output |
| 10 | `/usr/bin/env python3 analysis/refresh_rates.py` | no output | no output |
| 11 | `command python3 analysis/refresh_rates.py` | no output | no output |
| 12 | `exec -a x python3 analysis/refresh_rates.py` | no output | no output |
| 13 | `nohup python3 analysis/refresh_rates.py` | no output | no output |
| 14 | `sudo python3 analysis/refresh_rates.py` | no output | no output |
| 15 | `echo analysis/refresh_rates.py \| xargs python3` | no output | no output |
| 16 | `find analysis -name rates_history.json -exec rm {} \;` | no output | no output |
| 17 | `bash -c 'cat analysis/rates_history.json'` | deny | deny |
| 18 | `cat analysis/rates_history.json \| sh` | deny | deny |
| 19 | `python3 - <<'EOF'` / `import json` / `EOF` | deny | deny |
| 20 | `python3 -c 'import json'` | deny | deny |
| 21 | `cat "analysis/rates_hist""ory.json"` | allow | allow |
| 22 | `cat analysis/rates_hist\ory.json` | allow | allow |
| 23 | `cat analysis/rates_*.json` | allow | allow |
| 24 | `cat analysis/rates_hist{ory,x}.json` | allow | allow |
| 25 | `X=analysis; cat $X/rates_history.json` | deny | deny |
| 26 | `cat $(echo analysis)/rates_history.json` | deny | deny |
| 27 | `cat ../agentTooling/analysis/rates_history.json` | deny | deny |
| 28 | `python3 analysis/report.py --self rates-refresh-2026-11` | allow | allow |
| 29 | `python3 analysis/pricing.py` | no output | no output |
| 30 | `rm analysis/rates_history.json` | no output | no output |
| 31 | `git push --force origin HEAD` | deny | deny |
| 32 | payload with no `tool_input` | no output | no output |
| 33 | payload whose `tool_input.command` is a list | no output | no output |
| 34 | payload with no `session_id` | no output | no output |
| 35 | payload with `cwd: /tmp` (outside root), `rm analysis/rates_history.json` | no output | no output |
| 36 | stdin not JSON (`not json {`) | no output | no output |

Lifecycle checks that read the file:

| check | head | base |
|---|---|---|
| `bash self/tests/rates-history.sh` (gate, blocking: append-only and seed parity) | rc=0, all assertions passed | rc=0, all assertions passed |
| `pricing.is_rates_stale()` (gate `record_info`, informational) | current | stale |
| `pricing.get_rates("claude-fable-5-2", "2026-11-18")` | 8/40/0.2/10/16, `source: litellm` | 8/40/0.2/10/16, `source: litellm-live` |
| `pricing.get_rates("claude-mythos-5-2", "2026-11-18")` | 8/40/0.2/10/16, `source: litellm` | 8/40/0.2/10/16, `source: litellm-live` |
| `pricing.get_rates("claude-opus-5-5", "2026-11-18")` | unchanged (`manual`) | unchanged (`manual`) |

The staleness check moving from stale to current is what the refresh is for, and that
check is informational: it refuses nothing on either side. The new models price at the
same figures as before. The only difference is that the figures now come from the
committed history instead of a live fetch.

## Findings

None.

## Non-blocking findings

None. Every "no output" row is the hook's designed "handed to the human" path, not a
silent allow. Every row behaves the same on base and head.

## Blocking findings

None.
