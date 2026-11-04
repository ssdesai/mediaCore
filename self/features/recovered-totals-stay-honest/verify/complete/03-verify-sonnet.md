# 03 — verify

Feature: two ways a recovered total still looks whole and is low.

Read `self/gate-report.txt` first — the checks already ran.

1. **Did defect 1 ever fire on the real corpus?** The backfill committed in
   `278d1df` recovered 8 attempts across both corpora using the pre-fix code. Grep every
   `usage.json` for a `rates_applied` entry whose value is `null`. If any exists, those
   dollars were silently dropped and the sidecar needs re-recovering with `--force`; report
   the figure. If none exists, say so — that is a real finding too, and it means the
   committed numbers are sound.
2. **The cross-check warning is reachable, not theoretical.** Construct a sidecar whose
   top-level `recovered_cost_usd` disagrees with its attempts and confirm `report.py` warns
   rather than silently preferring one. A guard nobody has seen fire is a guard nobody knows
   works.
3. **`report.py`'s buckets are now four, not three**: measured, recovered-whole,
   recovered-partial, unrecoverable. Confirm only the last two set `total_is_partial`, and
   that recovered-partial still contributes its dollars.
4. **Both corpora still render.** `report.py --all` and `--self --all`.
5. Full gate green.
