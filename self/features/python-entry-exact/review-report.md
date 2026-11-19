Verdict: clean

# Round 2 review: python-entry-exact

## What the batch was supposed to do
Resolve round 1's two escalations: (1) assert `allow_abbrev=False` at run time, (2) say in `hooks/README.md` what a renamed option does.

## Does it
- **Escalation 1: resolved.** `self/tests/manifest-window.sh` M9 runs `manifest.py` (both parsers), `capture_planning.py` and `report.py` with abbreviated options. Each expects exit 2 and "unrecognized arguments". I ran the script and all M9 rows pass. Each remaining abbreviation is a unique prefix of one real option:
  - `--se` is `--self`.
  - `--sel` is `--self` on the orchestration parser.
  - `--forc` is `--force`.
  - `--al` is `--all`.
  - `--list-sess` is `--list-sessions`.
  - `--orch` on `report.py` is `--orchestration`.
  - `--rounds` is `--rounds-md`.

  The `capture_planning.py` and `report.py` rows run the checkout's own scripts under `-B`. argparse refuses them before any root is resolved, so nothing is written.
- **Escalation 2: resolved.** The `hooks/README.md` bullet now says the hook still approves the old word, the script refuses it with a usage error (exit 2), and no write happens.
- `self/tests/README.md` lists M9, and so does the test file's header.
- No hook code and no analysis script changed in the rework.
- NOTES.md's pre-existing `.match` finding is on `origin/main` and untouched by the diff.
- I did not re-run the gate; I read `self/gate-report.txt` and it is green.

## Fixed in this pass
- The row `manifest.py --orch <slug> get session` could not fail. The feature parser has no `--orchestration` option, so `--orch` has nothing to abbreviate and is refused even with `allow_abbrev` on. It tested nothing. I removed it from `manifest-window.sh`, `self/tests/README.md` and NOTES.md. `--se` still covers the feature parser, and `--orchestration … --sel` covers the orchestration parser.

## Escalated
None.
