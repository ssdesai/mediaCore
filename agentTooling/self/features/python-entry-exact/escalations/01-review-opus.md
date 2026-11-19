Verdict: escalated

# Review: python-entry-exact, round 1

## What the batch was supposed to do

The spec is the opening paragraph of `self/features/python-entry-exact/README.md`. It
closes two cases where the permission hook silently approved a write:

- **B1:** a repeated `--orchestration` made `manifest.py … set-window-to` look like a `get`.
- **B2:** an abbreviated `--force`/`--all` sat next to a decoy `--since '--list- x'`.

The fix has three parts:

- `python_entry_allowed` approves `capture_planning.py` and `manifest.py` only in their
  documented read-only shapes, matched word by word.
- The orchestrator allowlist applies the same exact rule to its record tool, its
  `--checkout` values and its listing rows.
- The three scripts' top-level parsers set `allow_abbrev=False` as defence in depth.

## Does it do it

Yes. Base is `origin/main`. What I checked in the diff:

- **`capture_listing_shape`** (`hooks/allow-repo-commands.sh`) accepts `[--self]`, then a
  listing word, then that listing's own options in any order, each once. A value is one
  word that does not start with `-`.
- **`manifest_get_shape`** accepts exactly `[--self] [--orchestration] <slug> get <key>`,
  with the slug passed through `fullmatch` against `SLUG_RE`.
- **B1 is closed** in both roles:
  - The plain shape refuses the repeated `--orchestration`.
  - The orchestrator row refuses any `-` word after the slug, and requires the subcommand
    to be one of the four with the right number of operands.
- **B2 is closed.** `--forc` and the bare slug are not words the shape names.
- **Every documented form is still approved.** I collected every `--list-sessions` /
  `--list-subagents` and `manifest.py … get` spelling in the repo's `*.md`/`*.sh` files.
  The only ones the new shapes refuse are test rows that expect a refusal.
- **The orchestrator's record tool** keeps all four subcommands, and repeated `--checkout`
  still works.
- **`allow_abbrev=False`** is set on `capture_planning.py`'s parser, both of `manifest.py`'s
  top-level parsers, and `report.py`'s. Subparsers are left alone, as the "Deliberately
  excluded" list says. The plain `report.py` row is unchanged, as excluded.
- **No edit** to `.claude/` or settings.
- **Tests:** `self/tests/allow-repo-commands.sh` and `hook-orchestrator-role.sh` H27 add both
  exploits as found, plus their variants: repeats in each position, `=` forms, every
  abbreviation of each writing mode with and without the decoy, and extra or missing words.
  They also add every documented shape as allowed.
- **Gate:** `self/gate-report.txt` says "all checks passed", and both suites ran the new
  rows. The rate-staleness probe exited 1, but the gate treats it as advisory.
- **NOTES.md:**
  - Its rulings match the diff.
  - Its table of entry points that read flags covers every row `python_entry_allowed` and
    the orchestrator allowlist approve that way.
  - Its claim that no call site relies on an abbreviation holds against the grep above.
- **Security audit:** the audit beside this review (`audit-report.md`, `Verdict: clean`)
  matches my reading.

## Fixed in this pass

Nothing. I tried one local README fix (the second escalation item below), but the Edit was
refused because write permission for `hooks/README.md` was not granted in this pass.

## Escalated to the next round

1. **No test asserts `allow_abbrev=False`.** The spec names it as a deliverable, and the
   contract requires changed behaviour to have a test that fails without it. Deleting
   `allow_abbrev=False` from any of the four parsers would leave the gate green, because
   every new row exercises the hook only.

   Add runtime rows to an existing analysis test that already uses a scratch `HOME`, such
   as `self/tests/manifest-window.sh` next to M8. Each row should assert exit 2 and
   `unrecognized arguments`:
   - `manifest.py --se <slug> get base`
   - `manifest.py --orch <slug> get session`
   - `capture_planning.py --list-sessions --forc`
   - `report.py --orch <slug>`

   argparse rejects each of these before any file I/O. The audit report's "Runtime check"
   table already has the expected outputs.

2. **`hooks/README.md` → "Cross-layer dependencies", the new first bullet, is wrong.** It
   says that renaming a parser option leaves the shape naming a dead word, and that "it
   then prompts, never approves". It does not prompt:
   - The hook's shape still names the old word, so the hook still approves it.
   - argparse then refuses that word as unrecognized: a usage error, not a write.

   Replace the parenthetical with: "(the hook still approves the old word, and argparse
   refuses it as unrecognized: a usage error, never a write)". This is a one-line doc fix
   that this pass could not write.

## Not findings

These are recorded so the next round does not chase them:

- **Globs in a value or key position** (`get *`, `--since [-]-force`) still pass the
  shapes. This is the audit's note 1: bash expands a glob only against files that already
  exist, and the expanded word can only reach a free-text slot.
- **The orchestrator `report.py` slug check still uses `.match`.** That line is unchanged
  by this diff, and `report.py` only reads (audit note 2).
