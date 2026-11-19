# 01 — review: python-entry-exact

A hand build: the coordinator built this feature itself, so there is no build plan and no
builder's brief. Review the diff against the spec below — never against the builder's
account of it — and say "no findings" when there are none: that is a legitimate verdict
(AGENT_PLANS.md → "Review plans").

## What the feature was supposed to do

The spec is the manifest, `self/features/python-entry-exact/README.md`: its opening paragraph (what
the feature delivers and why) and its "Deliberately excluded" list. Read it before the
diff. If that paragraph is still the template's `<One paragraph: …>` placeholder there is
no spec to review against: say so and return `Verdict: escalated`.
`self/features/python-entry-exact/NOTES.md` is the builder's record — its rulings and what it left
undone. Read it after the diff, to check its claims, not to learn what was intended.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

## Contracts to hold it to

- Every behaviour the spec names is implemented, and nothing the spec excludes is.
- New or changed behaviour has a test that would fail without it, and the gate
  (`self/gate.sh`) is green on this tree: its report says so, and the review does
  not re-run it.
- Every folder the diff touches has a README that still describes it (CONVENTIONS.md →
  "Keeping READMEs up to date"); a generated README is changed only through the file its
  header names.
- No magic literal in new code that CONVENTIONS.md → "Named constants" would name.
- NOTES.md's claims hold: what it says was done is in the diff, and what it says was left
  is not silently half-done.

This feature's own contracts:

- **B1 and B2 are not approved, in any role or profile.** As found
  (`python3 agentTooling/analysis/manifest.py --orchestration A --orchestration get
  --orchestration=orch-test set-window-to 2030-01-01T00:00:00Z`;
  `python3 agentTooling/analysis/capture_planning.py <slug> --forc --since '--list- x'` and
  `… --al --recapture --since '--list- x'`) and in their variants: a repeated option in each
  position, `--x=y` forms, every abbreviation of each writing flag, decoy values that look
  like flags. Not approved means the plain session prompts and the orchestrator role gets
  the allowlist denial — never an `allow`.
- **Exact shapes, no argparse emulation.** `python_entry_allowed`'s `capture_planning.py` and
  `manifest.py` rows match the documented shapes word by word (`capture_listing_shape`,
  `manifest_get_shape`); any word the shape does not name, a repeat, a `--x=y` form or an
  unlisted `-` word is no approval. Check the shapes against the docs that print them
  (`AGENT_PLANS.md`, `analysis/capture_planning.py`'s usage, `hooks/README.md`).
- **Every documented read-only shape is still approved** — `manifest.py [--self]
  [--orchestration] <slug> get <key>`, the `--list-sessions`/`--list-subagents` forms with
  their documented options — and the orchestrator's record tool keeps its four
  subcommands, repeated `--checkout`, and the listings.
- **`allow_abbrev=False`** on `capture_planning.py`'s, both of `manifest.py`'s and
  `report.py`'s parsers, and no documented call site or test relies on an abbreviation.
- **NOTES.md lists every entry point `python_entry_allowed` and the orchestrator allowlist
  approve by reading flags**, and what was decided for each.
- No edit to `.claude/` or settings; `hooks/README.md`'s tables say what the code does.

## Verdict
