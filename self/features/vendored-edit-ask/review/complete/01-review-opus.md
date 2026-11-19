# 01 — review: vendored-edit-ask

Review the diff against the spec below, from the spec and never from the builder's report.
"No findings" is a legitimate verdict: report a finding only where the diff breaks a
behaviour or contract named here, or leaves the security hole open.

## What the feature was supposed to do

Close finding B1 of humanNetworkMap's security audit of ssdesai/agentTooling#141: in a
consuming repo, `hooks/allow-repo-commands.sh`'s orchestrator allowlist runs vendored
agentTooling entry points silently (`analysis/report.py`, `analysis/manifest.py`,
`orchestration-start.sh`, `orchestration-capture.sh`, and the `plan-runner-roots.sh` /
`plan-runner-lib.sh` they source), while `hooks/wire-settings.py`'s consumer ask rules
covered only `agentTooling/hooks/**` and the records folders — so an Edit/Write to one of
those files went unasked and the planted code then ran without a prompt.

The owner's rulings are in `self/features/vendored-edit-ask/NOTES.md` → "Rulings". In
short:

- In a consuming repo, `wire-settings.py` writes the ask rule `Edit(**/agentTooling/**)`
  covering the whole vendored tree.
- The subsumed narrower rules `Edit(**/agentTooling/hooks/**)` and
  `Edit(**/agentTooling/self/orchestrations/**)` leave the wanted set and are removed, by
  exact string, from a consumer's settings in the same write that adds the broad rule.
- `Edit(**/plans/orchestrations/**)` stays.
- `--self` (agentTooling's own checkout and its tracked `.claude/settings.json`) is
  unchanged.
- `update.sh` / the subtree pull writes through git, not the Edit tool, and no
  consumer-side lifecycle step uses Edit/Write under `agentTooling/`.

Excluded: narrowing the orchestrator allowlist; subprocess writes to vendored files.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- `hooks/wire-settings.py`: the consumer `POLICY_ASK_RULES` contains
  `Edit(**/agentTooling/**)` and `Edit(**/plans/orchestrations/**)`, and no longer the two
  narrower vendored rules; a retired-ask list holds exactly those two strings and is
  removed by exact match only, never a repo's own spelling; `--check` reports a consumer
  settings file missing the broad rule (or still carrying a retired one) as needing
  attention, and `--write` leaves it with the broad rule and without the retired ones;
  a repo carrying both the broad rule and nothing retired is left byte-for-byte alone.
  `SELF_POLICY_ASK_RULES` and the generated `--self` `.claude/settings.json` are unchanged
  (the gate's byte-for-byte check holds it).
- The docstring and comments in `wire-settings.py` say why the rule is tree-wide.
- `self/tests/hook-wiring.sh` asserts the new rule set, the retirement (a consumer file
  with the old narrow asks is rewritten to the broad one; an unrelated repo-authored ask
  survives), and `--self` unchanged. `self/tests/security-audit.sh`, if it lists these
  rules, is updated to match.
- `hooks/README.md` (the rules block near "Edit(**/agentTooling/hooks/**) # vendored", the
  retired-rules prose, the records section that names the ask rules) and any other doc
  naming the old rule set (`grep -rn "agentTooling/hooks/\*\*"`) now describe the broad
  rule; the README index check stays green.
- No consumer-side lifecycle script or template instructs an Edit/Write under
  `agentTooling/`.
- `./self/gate.sh` green.

## Verdict
