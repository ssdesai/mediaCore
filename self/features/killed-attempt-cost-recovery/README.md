# A killed attempt's cost is recoverable, and today we throw it away

`analysis/README.md` states, of an attempt with `total_cost_usd: null`, that "its spend is
real but unrecoverable". That is false, and this feature is the demonstration plus the fix.

The runner takes cost from a run's final `result` event (`plan-runner-lib.sh`,
`write_usage_sidecar`). A killed run never emits one, so `attempts[].total_cost_usd` stays
null and `report.py:270-292` drops that attempt's spend and marks the total a lower bound.
But the session transcript survives under `~/.claude/projects/<project>/<session_id>.jsonl`,
and `attempts[].session_id` is recorded even for a killed attempt — the sidecar already
holds the key to a file nothing opens. Every token is in that transcript, including the
5m/1h cache-creation split, and `pricing.py` already prices exactly that shape.

**This was measured, not assumed.** Session `ba053b6a` (a killed attempt of
`entry-delete-and-gate-parity`'s plan 11) yields `output 24,958 / cache_read 3,148,936 /
cache_creation_1h 139,054`, which `pricing.compute_cost` prices at **$1.4357**. Running the
identical derivation over that plan's *successful* attempt (`fdc02b3a`) returns **$2.8960**
against the CLI's own recorded `$2.8959532` — a 0.00% delta. The method is exact, not an
estimate, and the validation is reproducible: it is assertion 9 of plan 01.

## The second defect, found while validating the first

`pricing.py:86` reads `if intro is not None and as_of <= intro["expires"]` — a one-sided
window. The sonnet entry carries `intro: {input: 2, output: 10, expires: "2026-08-31"}` with
no start date, so the introductory discount is applied to **every date before the expiry**,
including runs that predate the promotion.

Measured across all 259 sonnet runs in this repo's corpus, grouped by day: every day from
2026-07-30 through 2026-08-21 bills at exactly **1.500x** what `pricing.py` computes, and
2026-08-22 bills at **1.000x**. 1.5 is precisely the standard/intro ratio ($15 vs $10 output,
$0.30 vs $0.20 cache read, $6 vs $4 for a 1-hour write). The intro tier began on 2026-08-22;
the table applies it to the preceding three weeks as well.

Consequence: every planning-cost dollar `capture_planning.py` has frozen into a
`planning.json` for a pre-2026-08-22 session is ~33% low, and `is_rates_stale()` returns
False so nothing warns. This is the same failure as the killed attempt — a cost figure that
is quietly wrong rather than visibly missing — in the same file the recovery work must
import, so it is fixed here rather than filed away.

**The start date is derived from billing evidence, not from a published price list.** Plan 02
records it as such and bumps `RATES_VERIFIED` with an explicit note to confirm it against
Anthropic's published rates; the batch must not present an inferred date as a verified one.

## Levels

| Level | Plans | Sentinel | Level-verify | Must be green |
|---|---|---|---|---|
| 1 core | 01, 02, 03 | `04-gate.md` | `04-level-core-sonnet` | shell syntax, python syntax, level sentinels, cost-recovery self-test |
| 2 integration | 05, 06 | `07-gate.md` | `07-level-integration-sonnet` | all of the above |

Level 1's sentinel carries no `expected-red:` — plan 01 writes the self-test and plans 02-03
make it pass, all inside level 1, so the level owns its own red.

## Plans

| Plan | Model | Does |
|---|---|---|
| `01-tests-cost-recovery-sonnet` | sonnet | `self/tests/cost-recovery.sh`: 12 black-box assertions over a synthesized transcript + sidecar corpus. RED until 02-03. |
| `02-pricing-intro-window-haiku` | haiku | Give `intro` a `starts` bound; require `starts <= as_of <= expires`; set sonnet's to 2026-08-22 with provenance; bump `RATES_VERIFIED`. |
| `03-transcript-helper-and-recovery-sonnet` | sonnet | New `analysis/transcript.py` (shared billable-message iterator) and `analysis/recover_attempts.py`; `capture_planning.py` refactored onto the helper. |
| `04-gate.md` | — | Level 1 sentinel. |
| `05-report-reads-recovered-sonnet` | sonnet | `report.py` sums recovered cost, reports it separately, stops calling a fully-recovered total partial. |
| `06-docs-and-gate-wiring-haiku` | haiku | Retract the "unrecoverable" claim in three places; wire the self-test into `self/gate.sh`; add recovery to the weekly cadence. |
| `07-gate.md` | — | Level 2 sentinel. |

## Contracts across levels

| Value / identifier | Produced by | Consumed by | Fixture |
|---|---|---|---|
| `intro.starts` | 02, `analysis/pricing.py` | 03 (recovery prices by session date), 06 (README) | `self/tests/cost-recovery.sh` assertions 1-3 |
| `transcript.iter_billable_messages(path)` | 03, `analysis/transcript.py` | 03 (`recover_attempts.py`, `capture_planning.py`) | `self/tests/fixtures/transcripts/` |
| `attempts[].recovered_cost_usd` (+ `recovered_tokens`, `recovered_from`, `recovered_at`, `rates_applied`) | 03, `recover_attempts.py` | 05, `report.py:compute_cost_rollup` | `self/tests/fixtures/usage/` |
| top-level `recovered_cost_usd` | 03 | 05 | same |
| `cost.recovered` / `cost.unrecoverable_attempts[]` in `report.json` | 05 | 06 (README field list) | — |

## Design resolutions

1. **A new script, not an extension of `backfill_usage.py`.** Backfill's job is a plan with
   *no* sidecar, read from `.stream.jsonl` under the artifact root. This job is an attempt
   *inside* an existing sidecar, read from session transcripts under the session root —
   the two-roots distinction `analysis/README.md` already draws. Same cadence, adjacent step.
2. **`total_cost_usd` keeps its meaning: the CLI's own figure.** Recovery never overwrites
   it. Recovered dollars land in a parallel `recovered_cost_usd` so a reader can always
   tell a measured figure from a derived one, and so a future CLI that does report cost for
   killed runs cannot silently conflict with us.
3. **Tokens come from the transcript, never from `usage.json.usage{}`.** That block reports
   `cache_creation_input_tokens` as one flat total with no 5m/1h split, and these are 1-hour
   writes billed at 2x base input. `analysis/README.md` → "Do not re-price build or verify
   cost" measures the resulting error at ~1.5x too low. The transcript carries
   `usage.cache_creation.ephemeral_{5m,1h}_input_tokens` and is the only correct source.
   Plan 01 assertion 7 fails any implementation that takes the flat total.
4. **Find the transcript by globbing `~/.claude/projects/*/<session_id>.jsonl`.** Session ids
   are unique, and this sidesteps root resolution entirely — which matters because a
   `--self` executor's cwd is `agentTooling/` while the host repo's is its own root, so the
   two write into different project directories.
5. **A missing transcript is a first-class outcome, not an error.** Transcripts are on a
   retention clock. Recovery reports it as `unrecoverable` and leaves the attempt untouched;
   the total stays partial, which is then the honest verdict rather than a stale one.
6. **Recovery prices by the session's own date, never wall-clock.** `get_rates`' docstring
   already commits to this and `capture_planning.py` already honours it; with `starts` added
   the rule finally has two-sided meaning. Plan 01 asserts a 2026-08-01 transcript prices at
   standard and a 2026-08-22 one at intro, from identical token counts.
7. **The self-test is bash, like its neighbours.** `self/PROJECT_FACTS.md` says there is no
   Python test runner here and this feature does not add one; `self/tests/*.sh` scripts that
   the gate `record`s directly are the house form.

## Deliberately excluded

- Recovering `num_turns` from a transcript. Turn count is not a billing input and the
  transcript's line structure is not a turn structure; a wrong number is worse than null.
- Backfilling the corpus. The script is idempotent and safe to run over everything, but
  running it and committing 371 sidecars is an operational step, not a code change.
- Re-capturing the existing `planning.json` files at corrected rates. Every pre-2026-08-22
  figure is ~33% low and `capture_planning.py` freezes cost at capture time by design, so
  fixing them means re-running capture per feature and committing the diff. That is an
  operational pass over 20-odd features, not a code change; plan 06 records it as owed work
  in `analysis/README.md` rather than leaving it implicit.
- Pushing the `agentTooling/` subtree upstream. This batch commits into the host repo on
  its own branch; propagating to other consuming repos is a separate manual `subtree push`.

## Machine-readable

The window opens before this branch's single planning session
(`9275c2cd`, starts `2026-08-22T19:36:43Z`) and closes after it ends
(`2026-08-23T16:58:03Z`). `recovered-totals-stay-honest` shipped on this same branch and
PR, so its window chains off this one's `to` rather than overlapping it: that session
covers the planning for both features, a session is matched atomically on its start, and
so its cost is booked here, to the parent, in full. The eleven other sessions on this
branch are runner-spawned and excluded by their `usage.json` sidecars, not by this window.

```json
{
  "slug": "killed-attempt-cost-recovery",
  "branches": ["ssdesai/killed-attempt-cost-recovery"],
  "plans": [
    "01-tests-cost-recovery-sonnet",
    "02-pricing-intro-window-haiku",
    "03-transcript-helper-and-recovery-sonnet",
    "05-report-reads-recovered-sonnet",
    "06-docs-and-gate-wiring-haiku",
    "04-level-core-sonnet",
    "07-level-integration-sonnet",
    "08-verify-sonnet",
    "09-review-opus"
  ],
  "session_window": {"from": "2026-08-22T19:00:00Z", "to": "2026-08-23T17:00:00Z"},
  "exclude_sessions": []
}
```
