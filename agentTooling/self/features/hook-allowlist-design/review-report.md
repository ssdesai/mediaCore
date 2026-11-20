Verdict: clean

# Review — hook-allowlist-design

## What the batch was supposed to do

Write `self/DESIGN-2026-11-19-hook-allowlist.md`: the design that replaces the permission
hook's re-implementation of bash's reader with silent approval for an allowlist of simple
lines, `bash -n` as a parse oracle, a committed differential harness, and a
`hooks/README.md` that promises only what a gate test holds. It answers the owner's eight
questions. The diff may contain documents only: the design, its `self/README.md` index line,
pointer lines in `self/BACKLOG.md`, and the feature's own folder, which holds the measuring
prototype and its recorded output.

## Whether it does

Yes.

- **Documents only.** `git diff origin/main...HEAD --stat` touches only the design, one
  `self/README.md` line, nine pointer lines appended to `self/BACKLOG.md` (no entry removed
  or reworded), and `self/features/hook-allowlist-design/`. Nothing under `hooks/`,
  `analysis/`, `.claude/`, `self/tests/` or `templates/` changes, and no existing script
  does. The gate report has no failing check.
- **The eight questions.** Each has a section, and each answer is a decision: a grammar
  (§1) with every refused class listed and a rewrite for each shape approved today that it
  drops; a `bash_refuses` call kept as it is and moved onto the approval path (§2); four
  deny rules plus a disposition table (§3); a generator, a sandbox oracle, four failing
  checks and a budget (§4); a guarantee table mapped to test rows (§5); verdict changes
  counted per table, plus a friction replay (§6); seven decisions, each with a
  recommendation (§7); and three build features, each with its assertions (§8).
- **Claims about today's hook.** I checked them against the base. Each cited line number
  (`command_allowed` 4995, `never_judged` 1292, `judged_tokens` 2090, `bash_refuses` 1971,
  `heredoc_argument_at` 2039, `orchestrator_words` 5380, the environment-prefix rule at
  4899) is correct. So are the file length (5,867), `ORCHESTRATOR_MAX_LINE_CHARS` (20,000),
  `UNANALYSABLE`, `SHELL_ACTIVE_CHARS` and `HARMLESS_REDIRECT_RE`. The constants behave as
  described: `HARMLESS_REDIRECT_RE` is applied to raw text before quotes are read, which is
  defect 1, and `fails_closed` refuses `$(` and `case` whether quoted or not. Every cited
  test table and the checks H20 and 10d exist. The three defects and the eight dropped
  shapes match `prototype/README.md`'s recorded `probe.py` / `probe_dropped.py` output.
- **Figures.** Every number in §3, §4 and §6 matches the recorded output under
  `prototype/README.md`: 451, 336, 242, 94, 21, 298, 34 (11+12+6+5), 38 (23+15), 28,
  11 of 185, 87,988 lines over 36 tokens, 5,489, and 58 replayed commands with 18 approved.
  The one exception was the replay-fixture count, fixed below.
- **Widening.** §1 names the three kinds of line that become approvable: a `<`/`>` inside
  double quotes, a quoted operator word, and a git line holding `case` or a single-quoted
  `$(`. It explains why each is safe and says nothing else widens. The verdict-layer rule
  of `DESIGN-2026-09-18-hook-rewrite-or-ask.md` §1 is kept explicitly.
- **Backlog dispositions.** All ten entries the brief names are disposed of by name in §3:
  the five deny-side entries, the three motivating entries, "A writable git config…" (left
  open, with the reason) and the pattern-location entry. The pointer lines match: the git
  config entry is left open and correctly has none.

## Fixed in this pass

- `self/DESIGN-2026-11-19-hook-allowlist.md` §6: the replay fixture
  `self/tests/fixtures/hook-replay-2026-09-18.json` holds 28 records, not 24. That count is
  also the sum of `measure.py`'s recorded section 2. The "24" came from the 2026-09-18
  design, written before the fixture grew.
- `self/DESIGN-2026-11-19-hook-allowlist.md` §1, "Commands": the reserved words refused at
  command position were bash's only, but the design says bash and zsh read every line of
  the grammar alike. zsh's own reserved words, `repeat`, `foreach`, `end` and `nocorrect`,
  would have been admitted. So would the declaration commands (`declare export float
  integer local readonly typeset`), which zsh parses as reserved words and which both
  shells read assignment-shaped arguments of specially. `repeat 2 p0` runs `p0` twice
  under zsh, while the reader would return a program named `repeat`. That disagrees with
  G2. No approval was at risk: none of these words is an allowlisted program, and rule 2
  finds a `git` word anywhere in a command. The list now names all three groups. The
  prototype's `RESERVED` set is evidence only and its alphabet holds none of these words,
  so no recorded figure changes. The build's `hooks/simple_line.py` takes the list from §1.

## Escalated to the next round

None.

## Non-blocking notes for the build (not defects in this diff)

- §4's generator alphabet should include the zsh-only reserved words added above, so that
  differential check 1 under zsh would catch a reader that admits one.

## Deviations from the brief

None
