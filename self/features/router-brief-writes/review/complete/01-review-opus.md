# 01 — review: router-brief-writes

## What the feature was supposed to do

`feature-close.sh` refuses a feature whose unpinned router "worked in" its worktree
(`analysis/routing.py --unpinned-builder`, `worked_in`). Before this feature, *any*
Edit/Write/NotebookEdit under the worktree counted as working there. But the docs give the
router writes of its own inside the worktree: LIFECYCLE step 3 (replace the review-brief
stub, fill the manifest's prose) and step 5 (queue a re-review brief after an escalated
round). A wave coordinator following ORCHESTRATION → "Coordinator shapes" — the router,
unpinned, never `cd`-ing in — was therefore refused as the builder every time it wrote a
brief, and its only way past was to pin itself, which claimed its delegates for every other
feature in the wave too.

The fix is to the definition, not an exception list: **building is work in the worktree
other than the router's own step-3/step-5 writes.** Concretely, a write tool aimed at

- a path at or under `<worktree>/<features dir>/<slug>/review/` (any review brief, any round), or
- exactly `<worktree>/<features dir>/<slug>/README.md` (the manifest),

does not count, where `<features dir>` is the feature corpus as the worktree holds it
(`plans/features`, or `self/features` / `agentTooling/self/features` under `--self`).
Everything else still counts: a `cwd` at or under the worktree (unchanged), and a write to
any other path — product code, `auto/`, `verify/`, `NOTES.md`, `CHECKPOINT.md`, another
feature's directory.

The refusal in `feature-close.sh` now also names the **evidence** — the first transcript
line that made the session a builder (its `cwd`, or the tool and path) — so a refused
router can see what tripped it.

Decided and deliberately **not** done (do not flag their absence): no
`manifest.py exclude-subagent` command; no `feature-start.sh --review-brief` input; no
change to how the capture splits a session several features claim.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- The carve-out is exactly the two shapes above, by whole path component
  (`is_at_or_under`): `review-old/`, `README.md.bak`, `<slug>-two/review/` and a `review/`
  in a *different* feature's directory must all still count as building. The carve-out
  must not widen to the whole feature directory.
- The feature directory is derived, not hard-coded to one corpus layout: it must be right
  for a consuming repo (`plans/features`), this repo under `--self` (`self/features`), and
  a vendored `--self` (`agentTooling/self/features`), for transcripts that record absolute
  worktree paths.
- The `cwd` rule is untouched: a router whose `cwd` entered the worktree is still a builder,
  even if its only write was a brief.
- `--unpinned-builder`'s output contract: whatever it now prints, `feature-close.sh` is its
  only consumer and must parse it; with no builder it still prints nothing and exits 0.
- `self/tests/` R12 (see `self/tests/README.md`) gains the cases above — a brief write, a
  re-review brief, a manifest README edit (each **not** a builder) and the near-miss paths
  (each still a builder) — and the gate runs them.
- Docs say one thing: LIFECYCLE steps 3, 5 and 6, ORCHESTRATION → "Coordinator shapes",
  `analysis/README.md` → `routing.py`, the `feature-close.sh` header comment and
  `self/tests/README.md` R12 all describe the same definition of building, and none still
  tells a wave router that writing a brief gets it refused.
- Constants per CONVENTIONS → "Named constants" (the `review` dir name and `README.md`
  name are named once, and reused if `routing.py` or a sibling already names them).

## Verdict

"No findings" is a legitimate verdict. Phrase each finding as the assertion that would
catch it; keep the two lists (fixed here / escalated) separate.
