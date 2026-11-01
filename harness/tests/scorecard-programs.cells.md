# scorecardPrograms

_Rendered from `results.jsonl` by `agentTooling/harness/scorecard.py`. Every figure below comes from a frozen `planning.json` / `usage.json`; nothing here reprices anything._

## Prediction, written before the first run

> the scorecard reads a program cell as one feature set

Fixtures: f  ·  methods: a, b  ·  repeats: 1  ·  noise band: ±15%  ·  agentTooling arms: before=1111111, after=2222222

## Runs

| Fixture | Method | Arm | Branch | To PR-open | Review fixed/esc. | Rework | To green | Wall to PR | Accept | PR |
|---|---|---|---|---|---|---|---|---|---|---|
| f | a | before (1111111) | `fABefore` | $10.00 | 2/0 | — | $11.00 | 30m | pass | https://example.test/pr/10 |
| f | b | before (1111111) | `fBBefore` | $20.00 | 1/1 | $3.00 | $25.00 | — | FAIL | https://example.test/pr/11 |

## Cost against the ±15% band

- **f · arm before**: a vs b — to PR-open $10.00 vs $20.00 (+100%, b dearer, outside the band); to green $11.00 vs $25.00 (+127%, b dearer, outside the band).

## Interventions and failures

- `fABefore` 2026-10-30T10:10:00Z: re-queued after a usage limit
- `fBBefore` accept: FAIL export drops the header row

## Gate counts

| Branch | At PR-open | At green |
|---|---|---|
| `fABefore` | 40 pass | 41 pass |
| `fBBefore` | 38 pass | 41 pass |

