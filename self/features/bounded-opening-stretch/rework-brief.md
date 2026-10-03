# bounded-opening-stretch — rework brief

feature: agentTooling/bounded-opening-stretch

One-shot rework of the review's four escalations. Read `self/review-report.md` →
"Escalated to the next batch" in full first, then `brief.md` (rulings settled),
`NOTES.md`, and the current `analysis/capture_planning.py` and
`self/tests/session-share.sh` phase 15. Worktree
`/Users/sahildesai/dev/agentTooling-bounded-opening-stretch`, branch
`bounded-opening-stretch`. Work only there; never touch `~/dev/agentTooling` or
`~/.claude`; no stash, checkout, reset, clean, branch switch, rebase; do not push, do not
open a PR, do not edit the manifest's fence.

## Do exactly this

1. **A remainder that is all head must not print a zero "rest" or its remedy.** When the
   non-head part of the remainder is zero in both dollars and seconds, the warning names
   the head and its remedies only — no "and $0.0000 (0s) is the rest", no "For the rest"
   sentence. Add the assertion the review names: a phase-15-shaped session on a **fresh**
   session id where every unclaimed instant is head (two claimants, since the share path
   needs two, whose windows together cover everything after the earliest `from`), asserting
   the warning names the opening stretch and does not contain `is the rest`.
2. **Pin the bound's inclusive edge.** A response at exactly `head_bound` is paid to the
   earliest claimant (ruling 1 is `<=`). On a fresh session id (a fifth response on the
   phase-15 session re-bases 15a–15f), assert that response is in the earliest claimant's
   `cost_usd.total` and that the segment `[bound, from)` is in its `duration_s`. Prove it
   red by flipping the comparison (`<` → `<=`) and record the mutation in `NOTES.md`.
3. **Assert the in-flight exemption on the seconds too.** Extend 15f: with `head-a`'s `to`
   null, `head-a`'s `duration_s` is 16200, `head-b`'s is 1800, and `unclaimed_duration_s`
   is absent. Derive from the fixture, do not paste the numbers unverified.
4. **Read the no-head sentence.** One `grep -q` in phase 8 (or beside 8a) asserting the
   phase-1 session's unclaimed warning is the pre-existing tail sentence and contains no
   head clause — ruling 3's "stays as it is" gets coverage.

Any new check must be red against the pre-rework code where the review says it would be
(1, 2, 4 for item 1's wording and item 4 only if the sentence were wrong — say which were
red and which are guards). Phases 1–15 stay green. Update the `session-share.sh` row in
`self/tests/README.md` if the phase list changes. Gate green (`bash self/gate.sh`, ~3
min), then one commit on the branch: `bounded-opening-stretch: rework — review
escalations 1–4`, including the dirty `timing.jsonl` and `CHECKPOINT.md`/`NOTES.md`
updates. Report tersely: gate verdict, files changed, red-proof table, commit hash.
