# <slug> — acceptance checklist (write BEFORE running either arm)

Arms: `<arm-a>` (agentTooling <commit>) vs `<arm-b>` (agentTooling <commit>). Same brief,
same plan content; only the doctrine differs. Scoring rules: agentTooling/harness/EXPERIMENTS.md.

## A — mechanical (re-run the gate by hand after each batch)

| # | Check | arm-a | arm-b |
|---|---|---|---|
| A1 | pytest: all pass, count | | |
| A2 | typecheck clean | | |
| A3 | lint + format clean | | |
| A4 | frontend build | | |
| A5 | browser suite ×2 (flake check) | | |

## B — behaviour (score script through real routes / CLI / disk)

| # | Check | arm-a | arm-b |
|---|---|---|---|
| B1 | <the bug as reported is fixed — the exact observable> | | |
| B2 | <each design decision D1..Dn, as an observable> | | |
| Bn | <legacy data still loads> | | |

## C — code quality (read the diff)

| # | Check | arm-a | arm-b |
|---|---|---|---|
| C1 | <one predicate on both sides of the seam> | | |
| C2 | <one shared component; no duplicated row UI> | | |
| C3 | README field lists updated for every changed shape | | |
| C4 | spec amended where behaviour changed | | |

## D — process (from the batch log)

| # | Observation | arm-a | arm-b |
|---|---|---|---|
| D1 | interventions (re-queue, cap raise, hand PR) | | |
| D2 | pauses / capped passes, and at which level | | |
| D3 | wall-clock start → PR | | |

## E — cost (`analysis/report.py`)

| | arm-a | arm-b |
|---|---|---|
| build | | |
| level passes (tier 1 / tier 2) | | |
| final verify | | |
| review | | |
| **total** | | |

## Cross-check

Every defect either review escalated, confirmed in the other arm's tree:

| Defect | arm-a | arm-b | in shared plans? |
|---|---|---|---|
