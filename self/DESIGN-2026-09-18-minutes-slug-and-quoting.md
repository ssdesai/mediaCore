# Design 2026-09-18 — a plan's minutes per attempt, the start's slug, the opener's quoting, and two small readers

Feature slug: `minutes-slug-and-quoting`. Base: `ledger-and-routing` (stacked, so it
can run while that PR waits; retarget to `main` at the close once that PR has merged).
Five small defects with nothing in common but their size: three from the backlog, two
found on 2026-09-18 while the two features before this one were run. Built direct by one
implementer, tests first.

## §1 A plan's minutes walk the attempts the way its dollars do (D5)

**Defect.** `report.py`'s `duration_from_usage` sums the live sidecar's
`attempts[].duration_ms` and stops, so a resumed plan whose first attempt was killed and
whose second completed reports the second's minutes as the whole, marks no row, and is
in neither `missing_duration_plans` nor `recovered_duration_plans`. The dollars already
walk each attempt and read prior sidecars too (`compute_cost_rollup`,
`prior_attempt_cost`, `ATTEMPT_FIGURE_FIELDS`, live before prior).

**Rule.** The time roll-up walks attempts exactly as the cost roll-up does: for each
attempt (keyed by session, live copy before prior copies) the first copy holding
`duration_ms` gives a *measured* figure; else `recovered_duration_s` gives a *recovered*
figure (a lower bound); else the attempt is *unmeasured*. A plan's seconds are the sum.
The bucket rule: any unmeasured attempt → `missing_duration_plans`, the missing mark,
footnote "attempt k of n unmeasured"; else any recovered attempt →
`recovered_duration_plans`, the lower-bound mark, footnote "n of m attempts recovered
from transcript, lower bound"; a cell holding both a measurement and a recovered span is
one figure carrying the lower-bound mark — a sum with a lower-bound term is a lower
bound. `time.recovered_duration_plans[]` entries gain `measured_attempts` and
`recovered_attempts` counts. The marks and the footnote block are the existing ones
(`report-footnotes.sh` fixes their shape); no new mark.

**Assertion** (`report-footnotes.sh`): a plan with one measured attempt and one attempt
whose duration was recovered reports the sum, is in `recovered_duration_plans` with both
counts, and its footnote says which part is a lower bound; a plan with an attempt that
has neither is in `missing_duration_plans` naming the attempt; a plan whose only figures
are in a prior sidecar reads them.

## §2 The start's slug is on the start's line (D6)

**Defect.** `routing.slug_of_start_command` matches with `re.MULTILINE` and takes the
argument after `feature-start.sh [--self]` from wherever the regex lands: a start line
with no slug hands it the first word of the next line (`./feature-start.sh --self` then
`ls` records a feature named `ls`), and a start split over two lines with a trailing
`\` yields no slug.

**Rule.** Join `\`-newline continuations first, then match one line at a time; the slug
is the token after the script (and optional `--self`, `--base <b>`, `--pin`) on that
same line, or nothing. Named constants for the continuation and the flags that take a
value.

**Assertions** (`routing-record.sh`): the slug is taken from the script's line; a start
with no slug on its line yields nothing; a `\`-continued start yields its slug; a start
with `--base x` before the slug yields the slug.

## §3 The opener's path survives every quote (D7)

**Defect.** Both copies of `open-session.sh` wrap the worktree path in single quotes
inside the `osascript` string, which a path containing `'`, `"` or `\` still breaks:
the coordinator opens in the wrong directory and bills the wrong branch.

**Rule.** Two escaping layers, each a named function: shell single-quoting (`'` →
`'\''`) for the command Terminal runs, then AppleScript string escaping (`\` → `\\`,
`"` → `\"`) for the literal it is handed. Both copies move to `template-version: 3` and
`templates/plans/TEMPLATE_VERSIONS` re-records the hash. The header's "the one file
that may spell `cd <path> && <command>`" stays.

**Assertion** (`feature-lifecycle.sh` S5, beside the existing text reads, or a new
`open-session.sh` test): with `osascript` stubbed on `PATH` to record its argument,
running each copy with a path holding a space, `'`, `"` and `\` produces a `do script`
string that, AppleScript-unescaped and run with `claude` stubbed to print its `$PWD`,
prints the path intact. `template-versions.sh` passes on the new hash.

## §4 A read of the report does not rewrite it (D8, found 2026-09-18)

**Defect.** `python3 analysis/report.py --self <slug>` rewrites `report.md` and
`report.json` on every run, and when nothing has changed the only difference is
`generated_at`. A merged worktree whose report was read after the close is therefore
dirty, and `feature-start.sh`'s prune keeps it ("merged into origin/main but has
uncommitted changes") — `policy-module` and `lifecycle-records-and-numbering` on
2026-09-18, one timestamp line each.

**Rule.** The report is written only when its content other than `generated_at` differs
from the file on disk: the renderer compares the new body with the existing file's body,
each with its `generated_at` masked by one named regex, and leaves both files untouched
when they match, printing the report either way. `--all` follows the same rule per
feature. A record that does not exist yet is written.

**Assertion** (`report-footnotes.sh`, or the test that already runs `report.py` twice if
one exists — `self/tests/README.md` says): two consecutive runs over an unchanged corpus
leave `report.md` and `report.json` byte-identical and `git status` clean; a run after
`planning.json` changed rewrites them.

## §5 Two shapes the hook reads wrong (D9, found 2026-09-18)

Replaying one coordinating session's 24 commands through `hooks/allow-repo-commands.sh`
found two verdicts that are the hook's mistake rather than the policy's intent. The
rest of that replay — every line that bundled a read with a write, `git -C` to another
worktree, `ps`, `cp` from the scratchpad, the harness entry points that write — prompted
correctly and is a habit to change, not a rule to add (`CONVENTIONS.md` § Shell
commands already says one line per call).

**Defect a.** The opaque-shape scan reads the raw line for `SHELL_ACTIVE_CHARS`
(`<>$\``), so a backtick inside single quotes counts as a command substitution:
`sed -n '/```json/,/```/p' <path outside the root>` is **denied** as "a program or a path
decided at run time" where the same line with a path inside the root is approved (the
read-only approval runs first and never reaches the scan). A literal in single quotes
is a literal; the human should have been asked, not refused.

**Rule a.** The opaque scan judges active characters only outside single quotes — it
walks the line with the same quote state the tokenizer uses, or tokenizes and inspects
the raw spans that were unquoted — so `'x`y'`, `'$HOME'` and `'<'` are literals and
`` `x` ``, `$HOME` and `<(x)` outside quotes are still opaque. A line that will not
tokenize stays the seventh shape.

**Defect b.** `git -C <path> status` prompts even when `<path>` is inside the root: the
deny side skips `-C <value>` before judging the subcommand (`GIT_GLOBAL_VALUE_OPTIONS`),
the approval side does not, so `-C` reads as the subcommand and matches nothing.

**Rule b.** The approval side skips the same global value options as the deny side, and
approves the subcommand when each option's value that is a path is confined to the
project root (the same confinement `scratch_argument_allowed` applies) — `git -C
<root>/sub log` is approved, `git -C /elsewhere log` prompts, `git -C <root> worktree
add x` is still denied.

**Assertions** (`allow-repo-commands.sh`): `sed -n '/```json/,/```/p' /outside/x.md`
prompts (not denied); `grep 'a`b' README.md` approved; `echo `date`` still denied;
`git -C <root> status` approved; `git -C /tmp status` prompts; `git -C <root> branch
new` denied; `git --git-dir=<root>/.git log` approved. `hooks/README.md`'s § on the
opaque shapes and the git shape say so.

## §6 Deliberately excluded

- The vendored `agentTooling/.claude/settings.json` in a consuming repo: Claude Code
  reads project settings from the project root only, so nothing reads the nested file;
  the two "wrong" values in it (the hook command, the ask rule) are inert. No fix short of
  excluding `.claude/` from the subtree, which `git subtree` cannot do. The entry stays.
- Approving `ps`, `cp` from the scratchpad, or any harness entry point that writes
  (`stamp-timing.sh`, `manifest.py set-plans`, `run-review.sh`, `feature-start.sh`):
  each is a write, and the prompt is the policy. The coordinator's rule is one mutation
  per call with nothing else on the line, so the human approves one thing.
- Everything the `ledger-and-routing` feature owns.

## §7 Build

One opus implementer, direct, tests first, from the worktree; the review runs once,
sonnet (five precise contracts).
