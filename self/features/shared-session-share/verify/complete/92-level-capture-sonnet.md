# 92 — level-verify: the capture layer

feature: agentTooling/shared-session-share. Tier 1 for the `92-gate.md` sentinel. Skipped
entirely when that gate is green.

Must be green at this level: `bash -n` over every script, `py_compile analysis`, and the
behavioural tests — `self/tests/session-share.sh`, `self/tests/session-claims.sh`,
`self/tests/capture-guard.sh`, `self/tests/subagent-capture.sh`,
`self/tests/claims-ledger.sh`.

This level owns every dollar and second decision. The contracts it may not change:
`planning.json`'s `sessions[].share_basis`, `.session_cost_usd`, `.session_duration_s`,
`.unclaimed_usd`, and `priced[].share` / `.full_cost_usd` / `.shared_with` — plan 94 is
written against those names and reads them. The one invariant everything rests on is that
a session's claimants' shares plus its unclaimed remainder equal its own cost; if a test
is red because that does not hold, the tree is wrong, never the assertion.
