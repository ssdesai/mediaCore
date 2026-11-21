# Notes: orchestrator-move-length-cap

## Rulings made in the build

1. **The cap check goes in `orchestrator_moves_own_record` itself**, as the brief says, so
   every caller (today `main()` and `orchestrator_command_allowed`) gets it. The check in
   `orchestrator_command_allowed` stays. With the two lines removed, H29's four 20001-character
   rows fail (each one ALLOWed with `ORCHESTRATOR_MOVE_REASON`). With them in place, all
   pass.
2. **The go-ahead token is a shared rule.** `ROOTS_CLI_GO_AHEAD = "ok"` lives in
   `hooks/shared_rules.py`, which `roots.py` binds as `CLI_GO_AHEAD`. `orchestration-start.sh`
   reads it through the CLI it already uses, so no file restates the literal (`shared-rules.sh`
   S3). The start keeps its old refusal for a non-zero exit, and adds a fixed refusal ("exited
   0 without its go-ahead") for an exit 0 whose output is anything but the token. Three stubs
   are tested for each check: an empty file, `sys.exit(0)`, and a file that prints another
   line.
3. **The owner's addition is in `OWNER_BRIEF.md`.** The orchestrator relayed it while the
   start was running, before the start copied the brief, so the `start` commit carries it.
   (`feature-close.sh` refuses an owner brief that changed after the start, so it could not
   have been added any later.) Its numbered list is renumbered 6–9 so `conformance.py items`
   keeps one id per item: the original brief's own list already holds 1–5, and a repeated
   id would merge two items into one table row. That renumbering is the only change to the
   relayed text.
4. **The first start was refused, and resumed.** It was refused because files changed while
   its gate ran: the build had started in parallel with it. The start was re-run with the fix
   committed, and resumed at the setup hook. No harm, but a start's gate needs a still tree.

## Diagnosis: the conformance flip (owner item 6)

**Where the verdict comes from.** It is pure model judgment. `run-review.sh`
`build_conformance_prompt` gives a fresh `claude -p`, launched with `--tools ""`, exactly
four things:

- fixed instructions;
- the item list (`conformance.py items`);
- `OWNER_BRIEF.md` verbatim;
- `git diff <base>...HEAD`, with the feature's own directory left out (and cut at 400 kB).

It sees **none** of the following:

- the owner's rulings (they live in `NOTES.md`, inside the excluded directory);
- the review's report;
- any earlier round's conformance verdict.

`conformance-report.md` is deleted before every pass. `feature-close.sh` then requires
`conformance.py check-close` to find every owner item `done` in this round's table, and any
other value is "review says X, conformance says Y".

**Why the same input yields different verdicts.**

1. **Sampling.** Each round is an independent run. An item whose verdict is a judgment call,
   such as a prose section like "The problem" (a numbered heading, and so an owner item, that
   describes rather than asks), sits close to the done/partial line. A re-run can land on
   either side with no change in the input.
2. **The input does change, just not where the item is.** The diff is the whole feature
   against the base. Every rework round adds lines elsewhere, so the prompt that judges item 1
   in round 6 is not round 5's prompt, even when no line touching item 1 moved. A longer diff
   also dilutes the attention given to any one item. Past 400 kB the diff is cut, and the
   instructions then say an unverifiable item is `partial`.
3. **No memory, no rulings.** The check cannot see that round 5 found item 1 done, nor any
   owner ruling that settled what an item means. So nothing anchors it to an earlier reading,
   and a downgrade costs it nothing to state: "partial" needs no changed-evidence reason.
4. **The close treats every non-done as fatal.** A flip on an unchanged item is therefore a
   refused close and one more round, which is what #385 paid for in rounds 6 and 7.

## Ruling: carry forward at the close, not in the prompt (owner item 7)

The rule below is round 0's. Round 1 reworked how evidence is matched and which round
anchors the carry (see "Round 1 rework" below). The close carries an item forward as `done`
when all of the following hold:

- the previous round's committed conformance report marked it `done`, with evidence naming
  at least one file;
- the review marks it `done` now;
- no file named in either round's evidence for it changed between the tree that round judged
  and the judged head. That tree is the parent of its `<slug>: review round N-1` commit, so
  that round's own fixes count as changes; the feature's own directory is left out, as the
  check's diff leaves it out.

It prints a `carried` line instead of a problem. Everything else still refuses:

- a changed evidence file;
- a downgrade whose own evidence names a changed file (the "stated changed-evidence reason");
- a previous `done` that named no file (nothing to anchor it to);
- a previous verdict that was not `done`;
- an item the review does not call done;
- a first round.

Why the close and not the prompt: giving the executor its previous verdicts would make the
check anchor on itself, and its independence (brief and diff only, R8 of
brief-conformance-checks) is what makes it worth running. The close's rule is mechanical, and
it is tested end to end (V2).

What it does not catch: a real gap in an item whose evidence files are untouched since a
round judged it done. The previous round's check missed such a gap and this one found it.
The review's own acceptance table still has to say `done`, and that table is judged against
the owner's brief every round, so the gap is not unguarded. It is the price of "a done does
not regress on unchanged evidence", which is what the owner asked for.

On round 6 of #385: item 1 was done in rounds 4 and 5. If round 5's evidence named a file
and that file did not change in round 6, the close would have carried it, and that round
would have closed on the remaining items. Round 5's item 3 (partial, the review done) was a
real gap in a docs file, and it would still have refused, either because it was not done in
round 4 or because its evidence file was the one the fix changed.

## Round 1 rework: evidence is matched, not parsed; the anchor walks back

Round 1's audit found that the carry rule still let downgrades through when the evidence
named a changed file. Its regex path parser missed these spellings:

- absolute and `~` paths;
- folders and globs;
- `Makefile`, `docs/frob.1` and `.gitignore`;
- names with spaces or non-ASCII characters (git also quoted those in the changed list);
- a renamed file's old name (rename detection hid it).

Round 1's review found two more problems. A dotted identifier (`shared_rules.ROOTS_…`) counted
as a file anchor. And a carry lasted only one round, because round N's table still said
`partial`.

The rework drops path parsing:

- **Matching is textual and broad.** For each changed path, the item's evidence text is
  searched for the path in any spelling (substring), its file name standing alone, its module
  stem standing alone, a `<folder>/` holding it, or a glob matching it. A false match only
  refuses the carry, which is the old behaviour.
- **The changed list** comes from `git diff -z --no-renames`. Names are never quoted, and a
  rename lists both names.
- **Anchors must be real files.** `feature-close.sh` passes `git ls-tree -r -z` at the judged
  head (`--tracked`). An anchor is a tracked path the evidence names; an identifier names
  none.
- **The anchor is the newest earlier round that said `done`.** `feature-close.sh` passes every
  earlier round's report with its own changed list (`--round …`, newest first). The evidence
  from every round between that one and now is checked too, so a round that cited a changed
  file blocks the carry.

## Round 3: globs fail closed (the owner's ruling, 2026-11-21)

Round 2's audit found four more spellings that slipped past the matcher:

- a glob followed by punctuation (`*.sh.`, `*.sh:`);
- a brace glob (`*.{sh,py}`);
- a folder written `hooks/.`;
- an NFD path against git's NFC one.

Every audit round has found new pattern spellings. The owner ruled "fail-closed on globs"
instead of more matching:

- **Globs and braces:** evidence holding any of `*?[{`, in any round from the anchor through
  now, carries nothing. The `fnmatch` matching is gone.
- **The other two findings:** evidence and both path lists are compared in NFC, and `/./` or
  a trailing `/.` reads as `/`.
- **Round 2's review suggestion:** V1l pins the review's non-UTF-8 fix.

## Owner's ruling: split (2026-11-21, received after round 2)

The owner ruled to split defect 3 out of this feature, with four parts:

1. Remove the carry-forward from this feature.
2. Keep its diagnosis here, and file it in `self/BACKLOG.md`.
3. Authorise one more review and audit round, on defects 1 and 2 only.
4. Judge owner items 1 and 5 by hand, closing past the conformance refusal on those two
   only.

Done in round 3's preparation. `conformance.py`, `feature-close.sh`,
`self/tests/brief-conformance.sh`, `LIFECYCLE.md` and the root `README.md` are restored to the
branch base, `29e0b674`. So are the V1/V2 lines of `self/tests/README.md`. The backlog entry
carries:

- the diagnosis;
- the structural cause (process items the check cannot see);
- the design the three rounds converged on, globs failing closed included;
- its assertions.

The sections below on the carry-forward ("Ruling: carry forward…", "Round 1 rework…" and
"Round 3: globs fail closed") record what was built and audited. None of it ships in this
feature.

Owner items 7 and 8 are split out, so the conformance check will say `not done` on them. Item
6's diagnosis is now outside the feature directory only through the backlog entry, so the
check may also say `partial` on item 6. The owner's ruling names items 1 and 5 as the ones
to close past. If 6, 7 or 8 also block the close, they are reported, not closed past.

## Ruling: owner items the conformance check cannot see

Round 1's conformance check marked these owner items done or not done as follows:

- item 1 (start): **not done**;
- item 5 (gate, review, close): **not done**;
- item 6 (diagnose in NOTES): **partial**.

None of these is a flip. Its diff leaves out the feature's own directory, by design (R8 of
brief-conformance-checks): the start commit's records, the NOTES diagnosis and every round's
reports all live there. And the close is the step that runs the check. So a process item
whose evidence lives only in the feature's records can never be `done` for it. A carry
cannot help either, since the check never said `done` in the first place.

This is plausibly part of #385's pattern too. Its item 1, "The problem", is a prose section
that the diff can only illustrate.

Item 6 was for a time also met outside the feature directory, in `LIFECYCLE.md` step 5's
item 3; the split restored `LIFECYCLE.md` to the branch base, so it is now met there only
through the `self/BACKLOG.md` entry. Items 1 and 5 cannot be. The close will refuse on them however clean the round,
so this needs an owner ruling (reported to the orchestrator). The options:

1. accept a `[deviations]` close by hand;
2. let the check see the start commit and the feature's verdict records;
3. let an owner brief mark process items, which the conformance check skips.

The third changes the check's contract, so it is not built here.

## Ruling: no split (owner item 9) — superseded

Superseded by "Owner's ruling: split" above: the owner split defect 3 out after round 2, and
none of the code below ships in this feature. Kept as the build's reasoning at the time.

The fix is a handful of functions in `conformance.py` (`carry_forward` and its matchers,
about 100 lines) and one block in `feature-close.sh`. Nothing changes in the runner, the
prompt or any file format. That is small enough to ride with the rest of this feature.

## Owner's ruling: the close by hand (2026-11-21, after round 3)

Round 3 came back clean on both the review and the security audit. `feature-close.sh --self`
then refused, writing nothing. The conformance check disagreed with the review on five owner
items:

- items 1 and 5: process steps the check cannot see;
- item 6: its diagnosis sits in this directory, which the check cannot see;
- items 7 and 8: split out.

The owner ruled as follows. Where the review and the security audit are clean, and the
conformance check refuses only on items the owner has ruled not owed, split out, or process
steps it cannot see, the PR is opened by hand:

- titled `[deviations]`;
- carrying the acceptance table and the conformance report unedited;
- listing each disagreement.

Cost capture runs after the merge (`feature-capture.sh --self orchestrator-move-length-cap`).
The close's own stamps (`pr_opened`, the window's `to`) are therefore not written by
`feature-close.sh` for this feature.
