# Notes: python-entry-exact

A hand build in a Claude Code cloud container, on `claude/python-entry-exact`. The
method is `hand` rather than the owner's default `direct` on Sonnet because the session
that built it is itself a delegate with no Agent tool to spawn one; the diff is about
fifty lines of hook and parser code plus test rows.

## Rulings

1. **Exact shapes, not searches.** `python_entry_allowed` now calls `capture_listing_shape`
   and `manifest_get_shape`, which match the documented forms word by word. The design was
   the orchestrator's: any extra word, repeated option, `--x=y` form or unlisted `-` word
   is no approval, and nothing emulates argparse.
2. **Options in any order, each once.** A listing's options (`--unclaimed`, `--everywhere`,
   `--since <v>`, `--for <v>`) are accepted in any order after the listing word, since the
   docs print them in more than one order and argparse gives each order the same meaning.
   A repeat is refused. A value is one word that does not start with `-`, so a decoy value
   that looks like a flag is refused even though argparse would take one with a space in it.
3. **Per-listing option sets.** `--everywhere` and `--for` are `--list-subagents`'s only
   (the docs and `capture_planning.py`'s help say so); `--list-sessions --everywhere` is
   harmless but undocumented, so it prompts.
4. **`--self` only first**, as `PROJECT_FACTS.md` says it always is. The listing word must
   come next; `--unclaimed --list-sessions` prompts.
5. **The manifest slug must match `shared_rules.SLUG_RE`** with `fullmatch` (`re.match` with a
   `$` would accept a trailing newline), and with no `shared_rules.py` it matches nothing, as
   the orchestrator allowlist already did. `ORCHESTRATOR_SLUG_RE` and `ORCHESTRATOR_SELF_FLAG`
   are now the entry section's `ENTRY_SLUG_RE` and `ENTRY_SELF_FLAG`, one definition each.
6. **The orchestrator's record tool is tightened too.** B1 is "allowed for both plain and
   orchestrator sessions", and the brief requires every role to deny it. The row was
   `args[:1] == ["--orchestration"]`; it is now `--orchestration <slug> <subcommand>
   <operands>` with no `-` word after the slug, `get`/`set-window-to` taking exactly one
   operand and `add-feature`/`set-feature` one or more. The bare
   `manifest.py --orchestration` row in H21 therefore left the admitted set (it did nothing
   but print a usage error).
7. **The orchestrator's capture row shares the plain shape** (`capture_listing_shape`),
   replacing "exactly one listing word and no `--`" — which admitted `--list-sessions --forc`.
   `ORCHESTRATOR_CAPTURE_LISTINGS` is gone.
8. **`report.py --checkout` values may not start with `-`** in the orchestrator row: a
   `--checkout --orchestration` pair was admitted by the even-length rule. Repeated
   `--checkout` stays admitted (it is `action="append"`, documented repeatable).
9. **`allow_abbrev=False` on the top-level parsers** of `capture_planning.py`, both of
   `manifest.py`'s, and `report.py` (approved by flag in the orchestrator row). No
   documented call site, script or test uses an abbreviation: every `manifest.py`,
   `capture_planning.py` and `report.py` option spelled in a `*.sh`/`*.py` file was checked
   against the full option names; the only short spellings (`--list`, `--listx`,
   `--listing`, `--list-s`) are hook test rows that expect a denial.
10. **Size.** The hook grew by about forty lines net, most of it comments: the two shape
    functions and their constants replace two search expressions and the orchestrator's
    rows. Not smaller, because an exact shape has to name its words; no parsing layer was
    added — each function walks the word list once.

## Every entry point checked

| Entry point | Approval reads flags? | Repeated option / abbreviation class | Outcome |
|---|---|---|---|
| `capture_planning.py` (plain) | yes | B2: open | exact listing shape |
| `manifest.py` (plain) | yes | B1: open | exact `get` shape |
| `report.py` (plain) | no — any arguments | none: no mode is excluded | unchanged (excluded in the manifest) |
| `python3 [-B] -m py_compile <files>` | only that no word starts `-`/`+` | none: no flag passes | unchanged |
| `python3 -B` interpreter flags | `-B` only, repeatable | `-B -B` is harmless | unchanged |
| `gate.sh` | argument count only | none (bash `${1:-}`, no flag parsing) | unchanged |
| `check-plans.sh` | no | none (bash `$1 == --self`, exact) | unchanged |
| `bash -n`, `shellcheck` | `-n` first, then no `-`/`+` word | none | unchanged |
| orchestrator `manifest.py --orchestration` | first word only | B1: open | exact record-tool shape |
| orchestrator `report.py --orchestration <slug> --checkout …` | exact words | `--checkout <flag>` value | values may not start `-` |
| orchestrator `capture_planning.py` | one listing word, no `--` | abbreviation open | shared exact listing shape |
| orchestrator `orchestration-start.sh` | `--session` refused as a word | none: bash `case` matches exactly, so no abbreviation or `=` form reaches `--session` | unchanged |
| orchestrator `orchestration-capture.sh` | no | none (bash, `--self` exact) | unchanged |

## Round 2 (rework of `escalations/01-review-opus.md`)

11. **`allow_abbrev=False` is asserted at run time**, in `self/tests/manifest-window.sh` M9
    (the review's suggested home: it already builds a sandbox `manifest.py`). `manifest.py
    --se` and `--orchestration <slug> --sel` run the sandbox copy;
    `capture_planning.py --forc`/`--al`/`--list-sess` and `report.py --orch`/`--rounds` run
    this checkout's own under `-B`, which argparse refuses before any root is resolved. Each
    expects exit 2 and "unrecognized arguments"; with abbreviations on, `--se` and `--sel`
    would parse as `--self` and the rows would fail.
12. **`hooks/README.md` → "Cross-layer dependencies"** now says what a renamed option does:
    the hook still approves the old word and the script refuses it with argparse's usage
    error — a dead approval, never a write.

## Not changed, and why

- **A glob in a value or key position** (`get *`, `--since [-]-force`) passes the shapes
  (audit round 1, note 1). Bash expands it only against files already in the cwd, so
  turning it into a flag needs a `-`-named file planted first, itself a write the human
  approves; the expanded word can reach only a free-text slot, and both scripts then refuse
  or ignore it before writing. Not patched: the brief's rule is no new parsing layer, and
  the review recorded it as not a finding.

## Pre-existing findings

- **The orchestrator `report.py` row's slug check is `ORCHESTRATOR_SLUG_RE.match`**, not
  `fullmatch` (audit round 1, note 2): `SLUG_RE` ends in `$`, which `re.match` lets match
  before a trailing newline. Identical on `origin/main` (`df98316`) and untouched by this
  diff; `orchestrator_words` refuses a newline inside a word before this check, and
  `report.py` only reads. Recorded, not patched.
