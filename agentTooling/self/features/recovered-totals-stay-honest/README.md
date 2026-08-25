# Two ways a recovered total still looks whole and is low

`killed-attempt-cost-recovery` shipped the fix for a cost that vanished. Its own review found
the same defect class reintroduced one layer up, twice. Both are escalations 1 and 2 of
`agentTooling/self/features/killed-attempt-cost-recovery/review-report.md`; this batch closes
them on the same branch and the same pull request (#58).

The class is specific and worth naming, because it is what the parent feature existed to
remove: **a total that reads as complete while missing real spend.** A missing number that
announces itself is a nuisance; a missing number that does not is a wrong answer.

## The two defects

**1 — an unpriced model is dropped silently.** `analysis/recover_attempts.py:89-90` is
`if cost is not None: total_cost += cost`. `pricing.compute_cost` returns `(None, None)` for
a model absent from `RATES`, and `pricing.py:117-118` is explicit that *"a silent 0 reads as
'planning was cheap' when it means 'unmeasured'; callers must propagate None, not coerce
it."* `capture_planning.py:376-381` is the house precedent: it warns and sets
`total_is_partial`. Recovery does neither, so a killed attempt on an unknown model id writes
`rates_applied[model] = null` and a `recovered_cost_usd` omitting that model's dollars —
and `report.py` files it under *recovered*, not partial.

**2 — the runner erases the key `report.py` reads.** `report.py:276` takes a plan's recovered
dollars from the sidecar's **top-level** `recovered_cost_usd`. `write_usage_sidecar`
(`plan-runner-lib.sh:554-581`) rebuilds that top-level object from a fixed key list on every
write; `attempts[]` entries pass through whole, so the attempt-level fields survive, but the
top-level key is not in the list and is dropped. A resumed or re-run plan therefore loses its
recovered dollars from `cost.build` and `cost.recovered` while still being classed as
recovered — so the total is not marked partial. Re-running recovery does not repair it:
`recover_attempts.py:135` skips an attempt that already carries `recovered_cost_usd`, nothing
is rewritten, and `--force` is the only cure with nothing pointing at it.

## Plans

| Plan | Model | Does |
|---|---|---|
| `01-tests-partial-and-durable-sonnet` | sonnet | Two assertions in `self/tests/cost-recovery.sh`: an unpriced model must not produce a whole-looking total; a sidecar with attempt-level recovery and no top-level key must still roll up. |
| `02-propagate-partial-and-sum-attempts-sonnet` | sonnet | Both fixes, plus the README field lists. |

One level. Two plans and one gate do not need a tier ladder between them.

## Design resolutions

1. **Defect 2 is fixed in the reader, not the runner.** `report.py` sums the attempt-level
   `recovered_cost_usd` values — the durable location — and uses the top-level field only as
   a cross-check, warning when the two disagree. Teaching `write_usage_sidecar` to preserve
   unknown top-level keys is arguably more correct but is a runner change affecting every
   consuming repo's sidecar writes; the reviewer said as much. Keep the top-level field: it
   is a useful summary and now a checkable one.
2. **Defect 1 propagates rather than refuses.** A killed attempt on an unknown model still
   gets its priceable models recovered and its tokens recorded — throwing the whole attempt
   away would lose more than it protects. It carries `recovered_is_partial: true` and
   `unpriced_models[]`, and `report.py` treats such an attempt as partial rather than whole.
3. **`normalize_model_id` is not widened.** The failure is a model absent from `RATES`, and
   the fix is to say so, not to guess a rate for it.

## Deliberately excluded

- Re-running the backfill. The corpus was backfilled with the current code; if defect 1 had
  fired anywhere, `rates_applied` would carry a null — the verify pass checks whether it did
  rather than assuming.

## Machine-readable

**This feature's planning cost is booked to `killed-attempt-cost-recovery`, not here.**
It shipped on that feature's branch and PR (#58), and the branch carries exactly one
planning session (`9275c2cd`, `2026-08-22T19:36:43Z` → `2026-08-23T16:58:03Z`) covering
the planning for both. A session is matched atomically on its start, so it cannot be
split between the two features; the parent claims it in full. The window below therefore
chains off the parent's `to` and is expected to match nothing — a real `$0.00`, not a
missed capture. Do not "fix" it by widening it back over the parent's window: that
double-counts the session and `check_branch_overlap` will say so.

```json
{
  "slug": "recovered-totals-stay-honest",
  "branches": ["ssdesai/killed-attempt-cost-recovery"],
  "plans": [
    "01-tests-partial-and-durable-sonnet",
    "02-propagate-partial-and-sum-attempts-sonnet",
    "03-verify-sonnet",
    "04-review-opus"
  ],
  "session_window": {"from": "2026-08-23T17:00:00Z", "to": null},
  "exclude_sessions": []
}
```
