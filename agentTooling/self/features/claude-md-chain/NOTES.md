# claude-md-chain — builder's notes

Hand build, coordinated from the cloud session on `claude/brave-planck-no5foj`.

## What was measured

A throwaway project with an `InstructionsLoaded` hook logging every load
(`hooks.InstructionsLoaded` in its `.claude/settings.json`), run under `claude -p`
(Claude Code 2.1.314, haiku), laid out as root `CLAUDE.md` → `@sub/CONV.md`;
`sub/CLAUDE.md` → `@CONV.md`; `sub2/.claude/CLAUDE.md`; a file in each subdirectory.

| Launch cwd | Action | Loaded, in order | Load reasons |
|---|---|---|---|
| root | `cat sub/file.txt`, `cat sub2/file.txt` | `CLAUDE.md`, `sub/CONV.md`, `sub/CLAUDE.md`, `sub2/.claude/CLAUDE.md` | `session_start`, `include`, `nested_traversal`, `nested_traversal` |
| `sub/` | none | root `CLAUDE.md`, `sub/CONV.md`, `sub/CLAUDE.md` (the model's own report; the hook is the root project's and did not fire there) | — |

Findings:

1. `sub/CLAUDE.md`'s `@CONV.md` produced no second `include` event, and the model
   reported one occurrence of the shared file's marker in both runs: an import already
   loaded is not loaded again. The "loads the conventions twice" cost in
   `agentTooling/CLAUDE.md` and the claim in `RUNNER.md` that a `--self` executor never
   sees the consuming repo's root `CLAUDE.md` were both wrong; both files are corrected.
2. A subdirectory's `.claude/CLAUDE.md` is lazily loaded exactly like its `CLAUDE.md`
   (`nested_traversal` on the first read under it), so relocating `agentTooling/CLAUDE.md`
   there would change nothing. Not done.
3. `/doctor prompt-audit` runs headless (`claude -p "/doctor prompt-audit"`) and reports
   in prose; it called the double import "working redundancy" and left it alone.

Sizes that motivated the trim (bytes, before): `CONVENTIONS.md` 18,557 (240 lines; the
docs recommend under 200), of which the shell section was ~130 lines restating the hook
whose denials already carry the rewrite; vinylCatalogue's root `CLAUDE.md` 16,217, two
thirds of it a CLI reference; the READMEs the traversal rule forced whole into context:
agentTooling's own 95,248, humanNetworkMap's root 64,106, its `server/tests/README.md`
208,101, vinylCatalogue's `tests/README.md` 288,340.

## Rulings

- The shell-commands table stays in `CONVENTIONS.md` in full: it is the one thing a
  model needs before its first Bash call, and each row's denial names only its own
  rewrite. The reasoning behind the rows was already in `hooks/README.md` ("The three
  outcomes", "The rewritable shapes", "A file authored through the shell"), so nothing
  was moved, only the duplicate prose cut.
- README Rules 1 and 2 and "Keeping READMEs up to date" are kept verbatim in substance:
  they are what makes the READMEs an index worth reading. What goes is the sequence that
  forbade search and the "name the README entry before any Grep" ritual.
- The debugging section keeps the one specific heuristic (a literal `undefined` in a
  payload is a typing gap at the producer) and drops the three-file limit and "fix before
  reading more": counter-wandering rules that push a current model into premature fixes.
- The retired Edit deny is a new kind of retired entry rather than a reuse of
  `policy.retired_bash_deny_rules()`: the Edit rules live in `wire-settings.py`, not the
  policy table, and the message names its kind (`N retired Edit deny rule(s)`) as the
  Bash one does.

## Doctor on the consumers

`/doctor prompt-audit` ran headless (Sonnet) in each consumer against the *vendored*
`CONVENTIONS.md`, the one this feature replaces, so its findings there are a test of the
rewrite. Reports in the session scratchpad (`doctor/<repo>.md`), not committed.

Where it and this feature agree, already done upstream by the rewrite:

- The pressure register of "Navigating the codebase" and "Keeping READMEs up to date"
  (`REQUIRED sequence — no exceptions`, `Never use Glob or Grep`, `you MUST`, `Do not
  skip this step`): all four reports, medium confidence. Gone.
- "Stop conditions" (the three-file limit, "do not read more files first"):
  humanNetworkMap, mediaCore. Gone.
- "Avoiding redundant reads" restates a default: humanNetworkMap, mediaCore. Gone.
- The `cp` contradiction ("a copy reaches the human" against "never `cp`"): musicMap,
  high confidence. The rewrite keeps only the first; a copy is a human-judged write.
- `agentTooling/CLAUDE.md`'s "there is no test suite": humanNetworkMap. Corrected.

Where it found what this feature had not, verified against the code and agreed —
consumer-side edits, for a session in that repo:

- vinylCatalogue `CLAUDE.md`: "Every command accepts `--dry-run`" contradicts the
  `export-release` entry forty lines up and `cli.py` (`export-release` refuses it in
  release format). Qualify the sentence.
- vinylCatalogue `CLAUDE.md`: the `record.json` example omits `issue`, `in_collection`,
  `master_fetched_at`, `audio_checked_at`, `deleted_entries[]`, `split_entries[]`
  (`models/record.py`); it is the file's own model of a complete Rule 1 list.
- mediaCore `CLAUDE.md`: the `Release` field list omits `original_year`
  (`release.py:199`), likewise the repo's model Rule 1 entry.
- vinylCatalogue: `src/vinylcat/build/` is source, and File Access's example list names
  `build/`. One line in the root `CLAUDE.md`; the rule itself says "only autogenerated".

Where they differ:

- humanNetworkMap's "Branch naming" section: doctor would rewrite it to add the cloud
  case; this feature's `CONVENTIONS.md` says branch rules do not belong in a root
  `CLAUDE.md` at all (`LIFECYCLE.md` and `feature-start.sh` carry them). Delete it.
- mediaCore's "Branch naming" (`Bare camelCase … releaseContract`): doctor passed it;
  it contradicts `LIFECYCLE.md`'s kebab slug and `feature-start.sh` refuses such a
  name. Delete it, as above.
- Doctor's keep-list accepted "`CONVENTIONS.md` is loaded twice" as a documented cost;
  the measurement above shows it is not loaded twice, and the sentence is corrected.
- musicMap: doctor found every path and symbol in the root `CLAUDE.md` current and
  called it clean. This feature's concern there was size and duplication with
  `backend/README.md`, not staleness; no contradiction, no action.
- Doctor flagged the Named-constants example as TypeScript-shaped in a Python repo
  (mediaCore, low). Not changed: the rule is language-neutral and the example is one.
- The vinylCatalogue CLI reference with its "as amended" dates: doctor flagged it low;
  this feature's view is the same, that it belongs in the spec it already cites.
- Settings files were outside doctor's scope; the `Edit(**/agentTooling/hooks/**)`
  deny/ask drift is retired here through `wire-settings.py`.

## Left undone

- The four consumers' root `CLAUDE.md` files (see the manifest's exclusions and the
  consumer-side list above).
- A README-entry design that keeps entries short: proposed to the owner with the
  measurements above, not legislated here.
