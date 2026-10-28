# Notes: tooling-backlog-2026-09

Rulings the implementer made where the manifest left the call open, each with a one-line
rationale, plus deviations and open questions. The manifest's own decisions
(`README.md` → "The items, with the decision each one is built to") are not reopened
here; only what it did not settle.

## Rulings

- **The item-5 assertions live in a new `self/tests/direct-timing.sh`, not in
  `cost-recovery.sh`.** The manifest allowed either. `cost-recovery.sh` is one contract
  end to end — killed-attempt recovery and the pricing window — and its fixtures are
  transcripts and sidecars; a `stamp-timing.sh` CLI and a timing.jsonl-driven Time table
  share none of that machinery, and folding them in would have made the file's own
  header a list of two unrelated subjects. Item 9's assertions *did* go into
  `cost-recovery.sh`, as the manifest requires: they are about the same
  `compute_cost_rollup` partial-total contract its assertions 13–14 already cover.

- **`stamp-timing.sh` refuses rather than shrugs.** `stamp_timing` itself is silent when
  no feature is resolved — correct inside a runner that may not have one yet. As a CLI
  that would swallow a typo'd slug, so the script exits 2 on an unknown feature, on a
  missing slug or event, and on a detail argument with no `=` (`stamp_timing` splits on
  the first `=`, so a bare word becomes `{word: "word"}`). It also exits 127 without
  `jq` — the builder suppresses jq's stderr, so a missing jq would otherwise be a silent
  no-op — and 1 if the line did not actually land, checked by line count. Exit codes are
  named constants at the top (`USAGE_RC`, `MISSING_TOOL_RC`, `STAMP_FAILED_RC`).

- **A checkpoint status is read at its FIRST instant.** The checkpoint file is rewritten
  whole at every milestone and a resumed implementer re-declares where it is, so a
  status can appear more than once. The first time a milestone was reached is what the
  span means; a later re-stamp of `implementing` must not move `tests-written`.

- **A span with a missing endpoint is `null`, not `0`.** A build killed before
  `committed`, or one whose implementer skipped a stamp, has no gate span. A zero there
  would render as "0.0 min" and read as an instant gate. `render_time_section` omits the
  row entirely when the value is `None`.

- **The three keys are absent, not `null`, when a feature stamped no checkpoint.**
  `compute_checkpoint_spans` returns `{}` and the roll-up adds nothing, so every
  existing report — planned or direct — is byte-identical. Asserted both ways in
  `direct-timing.sh` phases 4 and 5.

- **Checkpoint spans are computed for `method: direct` only.** They subdivide the
  implementer row, and a planned feature has no such row for them to sit under. A stray
  `checkpoint` event on a planned feature is ignored rather than rendered under
  "planning" — asserted in `direct-timing.sh` phase 5.

- **Sub-row labels are `↳ acceptance tests` / `↳ implementation` / `↳ gate`, with
  minutes and no dollars.** "Indented" in a markdown table has no markup for it; `↳` is
  the same glyph the repo already uses for continuation. The dollar and rate cells are
  blank because the implementer's transcript is priced as one span and nothing divides
  its cost the way the instants divide its minutes — a per-sub-row rate would be an
  invented figure.

- **A runner-skipped plan is detected from its progress log's first line** (item 9).
  It is the only marker on disk: the plan file itself is an ordinary brief, and the
  absence of a `usage.json` is exactly what has to be told apart from a real absence.
  `build_skipped_index` mirrors `build_usage_index` — scoped to one feature, keyed by
  filename, since plan numbers restart per feature.

- **`skipped_plans[]` is a new `cost` key rather than a warning alone**, and is rendered
  as a one-line "Skipped, not missing" note *outside* the partial block. A feature whose
  only unloaded plan was skipped has a whole total, so the partial block never prints,
  and without the note nothing would explain why that plan carries no cost.

- **Item 4's README step is its own "Adopting stacked pull requests" subsection under
  "Updating", not a fifth step in the level-adoption list.** That list is explicitly for
  a repo whose `gate.sh` predates level sentinels; a `pr.sh` merge has a different
  trigger and a repo may need one and not the other. Three numbered steps, one sentence
  each, as the manifest asked.

- **Item 6: nothing was missing from agentTooling's own root `.gitignore`.** It already
  carries `self/**/*.stream.jsonl`, `self/**/*.logfifo` and `self/gate-report*.txt`, and
  the gate only ever writes its reports to `self/gate-report*.txt` (final and per-level),
  so the narrower prefix covers the same files the template's `gate-report*.txt` covers
  under `plans/`. Left as it is rather than widened to `self/**/gate-report*.txt`: a
  wider ignore would silently swallow a fixture someone deliberately commits.

- **`templates/plans/.gitignore` is a live `.gitignore` where it sits, and that is
  harmless.** Nothing under `templates/plans/` matches `gate-report*.txt`,
  `**/*.stream.jsonl`, `**/*.logfifo` or `/review-report.md`. Noted in
  `templates/README.md` so the next reader does not have to work it out.

- **Item 7's message is kept off the `--everywhere` and `--unclaimed` paths.**
  `unclaimed` implies `everywhere`, and a scan that already looked everywhere cannot be
  wrong about its root, so telling it to pass `--everywhere` would be noise.

- **Item 2's empty-`NN` message names both sources that came back empty.** The manifest
  required a message and exit 1; the message says the runner reported nothing *and* that
  `auto/complete/` has no sentinel, because those are two different failures and the fix
  differs.

## Deviations

- None from the manifest's decisions. Two acceptance assertions were tightened after
  first being written too broadly — never weakened:
  `direct-timing.sh` 3f now checks the row immediately following `build: implementer`
  instead of the second table row in the file (the Cost table's own total row was
  matching first), and `cost-recovery.sh` 15c now checks the **Cost** table's total row
  and the absence of "Missing usage for", because that fixture's Time total is
  legitimately partial (its `planning.json` carries no `duration_s`) and a bare grep for
  "lower bound" was reading the wrong section.

## Open questions

- The build's own `tests_s` span is not derivable from this feature's `timing.jsonl`:
  `stamp-timing.sh` did not exist when the `planned` and `tests-written` milestones
  passed, and back-dating a stamp would have been a guessed instant of exactly the kind
  item 8 forbids. The `implementing`, `gating` and `committed` stamps are real, so
  `gate_s` is derivable and `tests_s` / `direct_build_s` are `null` — which is the
  missing-endpoint case working as designed, on its first real feature.
- `analysis/README.md` still says "record`ed by `../gate.sh` alongside the other two" in
  the `cost-recovery.sh` entry of `self/tests/README.md`; there are now seven test
  scripts. Left alone under `CONVENTIONS.md` → "Scope discipline" — it predates this
  feature and is its own tidy-up.
