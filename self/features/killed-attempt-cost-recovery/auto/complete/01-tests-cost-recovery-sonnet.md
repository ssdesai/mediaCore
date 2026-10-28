# 01 — the self-test for cost recovery and the intro-rate window

Feature: a killed attempt's cost is recoverable from its session transcript, and
`pricing.py`'s intro tier must not apply to dates before the promotion began.

Plan 1 of 6 build plans. Everything you write here is RED until plans 02 and 03 land —
that is intended. Write no production code in this plan.

## Deliverable

`self/tests/cost-recovery.sh`, a bash self-test in the exact form of its neighbours
`self/tests/level-sentinel.sh` and `self/tests/tiered-gates.sh`: build a throwaway corpus
under `mktemp -d`, run the real scripts against it, assert, print one `ok`/`FAIL` line per
assertion, exit non-zero on any failure. No model calls, no network. Read
`self/tests/README.md` first — it states the house form, and your new entry goes in it.

Fixtures go in `self/tests/fixtures/` (create it): synthesized session transcripts and
`usage.json` sidecars. They must be written by the script into its temp dir, not committed
as large blobs — a transcript here is a handful of JSON lines, so build them with a shell
helper that takes tokens and a date and emits a valid line.

## What a session transcript line looks like

One `assistant` line per content block, all repeating the same response's `usage`:

```json
{"type":"assistant","timestamp":"2026-08-22T21:16:12.752Z","sessionId":"S","isSidechain":false,
 "message":{"id":"msg_01","model":"claude-sonnet-5","usage":{"input_tokens":4,"output_tokens":900,
 "cache_read_input_tokens":120000,"cache_creation":{"ephemeral_5m_input_tokens":0,
 "ephemeral_1h_input_tokens":5000}}}}
```

Two facts your fixtures must exercise, both documented in `analysis/README.md` under
`capture_planning.py`: **(a)** one API response is written as several `assistant` lines, each
repeating `usage` verbatim, so tokens are summed per distinct `message.id`; **(b)**
`model: "<synthetic>"` marks a locally-generated notice with all-zero usage and is skipped.

## The 12 assertions

Rates: `pricing.py`'s sonnet entry is standard `{input: 3, output: 15}` with intro
`{input: 2, output: 10}`; cache read is `CACHE_READ_MULTIPLIER` x base input and a 1-hour
write is `CACHE_WRITE_1H_MULTIPLIER` x base input. Compute expected dollars in the test with
`python3 -c` calling `pricing.compute_cost`, never by hardcoding a dollar figure — a
hardcoded figure turns the next real rate change into a red gate for no reason.

**Intro-rate window (RED until plan 02):**
1. A transcript dated `2026-08-01` prices at the **standard** tier — `get_rates(...)["tier"] == "standard"`.
2. The identical token counts dated `2026-08-22` price at the **intro** tier, and at exactly 2/3 the cost of assertion 1.
3. A date after `expires` prices standard again. The window is closed on both sides.

**Recovery (RED until plan 03):**
4. Given a `usage.json` whose `attempts[]` holds `{session_id: S, outcome: "killed", total_cost_usd: null}` and a transcript for `S` on disk, `recover_attempts.py` fills that attempt's `recovered_cost_usd`, `recovered_tokens`, `recovered_from: "transcript"`, `recovered_at`, and `rates_applied`.
5. It does **not** modify `total_cost_usd` — measured and recovered stay distinguishable.
6. Top-level `recovered_cost_usd` equals the sum over recovered attempts.
7. **The 5m/1h split is honoured.** Two sidecars with identical *total* cache-creation tokens, one all-5m and one all-1h, must recover **different** costs, in the ratio `CACHE_WRITE_1H_MULTIPLIER / CACHE_WRITE_5M_MULTIPLIER`. This assertion is the guard against an implementation that reads `usage.json`'s flat `cache_creation_input_tokens` instead of the transcript's split — see `analysis/README.md` → "Do not re-price build or verify cost", which measures that mistake at ~1.5x too low.
8. An attempt that already has a real `total_cost_usd` is left byte-identical.
9. Idempotence: running twice produces the same file as running once.
10. A killed attempt whose transcript is **absent** (aged out) leaves the attempt untouched, reports it as unrecoverable on stdout, and exits 0. Not an error.
11. Per-`message.id` dedup: a transcript where one response is split across 3 `assistant` lines bills that response once. Build the same fixture with the dedup defeated and assert the two differ, so the assertion cannot pass vacuously.
12. `model: "<synthetic>"` lines contribute nothing.

## Do not

- Do not touch `pricing.py`, `capture_planning.py`, `report.py`, or write `transcript.py` /
  `recover_attempts.py`. Plans 02 and 03 own those; a test plan that fixes its own subject
  proves nothing.
- Do not wire the script into `self/gate.sh` — plan 06 does that, after it can pass.
- Do not add a Python test runner. `self/PROJECT_FACTS.md` → Tests is explicit that there
  is none here, and `self/gate.sh` `record`s these scripts directly.

## Done when

`bash self/tests/cost-recovery.sh` runs to completion and fails with a clear per-assertion
report naming the 12 above. A test that errors out on a missing import instead of failing an
assertion is not done — the script must reach and report every assertion it can.

Update `self/tests/README.md` with an entry for the new script in the form of the two
existing entries, naming what it depends on.
