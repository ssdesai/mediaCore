Verdict: clean

# Security audit — audit-blocking-classes (01-audit-opus)

Base `origin/main`, head `HEAD` of `claude/audit-blocking-classes`. Two throwaway copies,
`git archive HEAD` and `git archive origin/main`, under the pass's scratch directory; nothing
in this checkout was edited except this report.

## Rules the diff adds or changes

1. **`feature-close.sh` + `plan-runner-roots.sh` `audit_report_unclassed`** (new): when a
   feature changes the hook, the close now refuses a `Verdict: clean` audit report unless its
   `## Findings` section holds only `None.`, one `class` header row, separator rows, and
   rows whose first cell is `non-blocking`. It refuses a `blocking` row, any other line, and a
   missing section. This applies to whoever runs the close: the coordinator, or a session
   closing a hook-changing feature.
2. **`feature-start.sh` worktree refusal** (reworded): a `feature-start.sh` run from a linked
   worktree still refuses. Only the path it names changed, which now uses
   `--path-format=absolute`.
3. **`run-review.sh` audit prompt step 4, `templates/SECURITY_AUDIT.md`, `hooks/README.md`**:
   text only (the classification the auditor applies). They add no refusal and no hook
   decision. The template is still matched byte-for-byte by `audit_plan_matches_template`, and
   that check is unchanged. `hooks/allow-repo-commands.sh` itself is not in the diff; it was
   run as a control (table C).

How each was run:
- **A.** `bash scratch/unit.sh <copy> scratch/cases`. It sources the copy's
  `plan-runner-roots.sh` and runs `audit_report_unclassed` on each case (mawk 1.3.4). Base has
  no such function, so the base column is taken from table B.
- **B.** `bash scratch/close.sh <copy> <label> <case>…`. This runs the
  `self/tests/security-audit.sh` fixture and `run-review.sh --self feat` (the stub audit writes
  the case file as the report), then `feature-close.sh --self feat` with a stray file planted.
  "passed" means the close got past every audit check and stopped at the stray-file check
  after them.
- **S.** `bash scratch/start.sh <copy> <label>`: `feature-start.sh` run from a linked worktree.
- **C.** `python3 <copy>/hooks/allow-repo-commands.sh` on PreToolUse JSON,
  `CLAUDE_PROJECT_DIR=<copy>`. No output means the hook hands the command to the human (asked).

## Inputs tried

Every report below opens `Verdict: clean` and has the stub's input table, then the section
shown, then `## Non-blocking findings` / `None.` (`H` = `| class | input | head | base | evidence |` + `|---|…|`).

### A. The reader alone (head copy)

| # | report shape under `## Findings` | head reader output | close would |
|---|---|---|---|
| 01 | `None.` | nothing | pass |
| 02 | H + `\| non-blocking \| \`a \| sh\` \| …` | nothing | pass |
| 03 | H + `\| blocking \| x \| …` | `blocking: …` | refuse |
| 04 | H + row indented two spaces | `unclassified: …` | refuse |
| 05 | H + row indented by a tab | `unclassified: …` | refuse |
| 06 | H + `\|\| blocking \| x \|` (empty first cell) | `unclassified: …` | refuse |
| 07 | H + `\| non-blocking \\\| blocking \| x \|` (escaped pipe) | `unclassified: …` | refuse |
| 08 | H + a second `\| class \| blocking \|` header | `unclassified: …` | refuse |
| 09 | no header, `\| blocking \| x \|` first | `blocking: …` | refuse |
| 10 | `` \| `CLASS` \| `` header + `\| NON-BLOCKING \|` | nothing | pass (case-insensitive, correct) |
| 11 | H + `<!-- \| blocking \| x \| -->` | `unclassified: …` | refuse |
| 12 | H + `\| <!-- --> non-blocking \| x \|` | `unclassified: …` | refuse |
| 13 | H + a fenced block holding a blocking row | `unclassified`/`blocking` | refuse |
| 14 | H + `### More` then a blocking row | `unclassified`, `blocking` | refuse |
| 15 | `None.`, `# Other` (h1), blocking row | `unclassified`, `blocking` | refuse |
| 16 | `None.`, bare `##`, blocking row | `unclassified`, `blocking` | refuse |
| 17 | heading `## Findings<TAB>` | `no ## Findings section` | refuse |
| 18 | heading `## findings` | `no ## Findings section` | refuse |
| 19 | heading `## Findings ##` | `no ## Findings section` | refuse |
| 20 | setext heading `Findings` / `---` | `no ## Findings section` | refuse |
| 21 | no section at all | `no ## Findings section` | refuse |
| 22 | whole file CRLF, blocking row | `blocking: …` | refuse |
| 23 | whole file CRLF, non-blocking row | nothing | pass (correct) |
| 24 | `non‑blocking` with U+2011 hyphen | `unclassified: …` | refuse |
| 25 | `non-blocking` + U+200B zero-width space | `unclassified: …` | refuse |
| 26 | `None.` then a blocking row | `blocking: …` | refuse |
| 27 | `None.<TAB>` | `unclassified: None.` | refuse |
| 28 | H + `\| --- \| : \|` separator-only row | nothing | pass (no content, correct) |
| 29 | a prose line | `unclassified: …` | refuse |
| 30 | `None.`; a blocking row under `## Non-blocking findings` | nothing | **pass** |
| 31 | `## Findings`/`None.`/`## end` only inside a fenced block | nothing | **pass** |
| 32 | `## Findings`/`None.`/`## end` only inside an HTML comment | nothing | **pass** |
| 33 | `None.`, `## Other`, a second `## Findings` with a blocking row | `blocking: …` | refuse |
| 34 | H + `> \| blocking \| x \|` (blockquote) | `unclassified: …` | refuse |
| 35 | H + `\| non-blocking-ish \| x \|` | `unclassified: …` | refuse |
| 36 | H + `\|non-blocking` (no closing pipe) | nothing | pass (correct) |
| 37 | H + `` \| `blocking` \| x \| `` | `blocking: …` | refuse |
| 38 | H + `\| non-blocking \| x \|<CR>\| blocking \| y \|` (a lone CR mid-line) | nothing | **pass** |
| 39 | H + `\| non-blocking<NUL>\| blocking \| y \|` | `unclassified: …` | refuse |
| 40 | heading ` ## Findings` (leading space) | `no ## Findings section` | refuse |
| 41 | report file missing | nothing (mawk cannot open it and skips `END`) | pass in isolation; see B |

### B. The full close, head vs base

| case | head `feature-close.sh` | base `feature-close.sh` |
|---|---|---|
| 01-none | passed audit checks | passed audit checks |
| 02-nb-only | passed audit checks | passed audit checks |
| 03-blocking | refused (not all classed non-blocking) | passed |
| 04-indented-blocking | refused | passed |
| 09-no-header | refused | passed |
| 13-fenced-block | refused | passed |
| 21-no-section | refused | passed |
| 22-crlf | refused | passed |
| 29-prose | refused | passed |
| 30-blocking-in-nb-section | **passed** | passed |
| 31-findings-in-fence-only | **passed** | passed |
| 32-findings-in-comment-only | **passed** | passed |
| 33-two-sections-second-blocking | refused | passed |
| 36-nb-no-close | passed | passed |
| 38-cr-mid-row | **passed** | passed |
| missing report | refused ('unreadable' verdict, earlier check) | refused (same) |

The head is never more permissive than the base: every case either keeps the base's result
or turns the base's pass into a refusal.

### S. `feature-start.sh` from a linked worktree

| layout | head | base |
|---|---|---|
| standalone (`--self probe-slug`) | refused, rc=1, no branch, no feature dir | refused, rc=1, no branch, no feature dir |
| vendored (`agentTooling/` subdir) | refused, rc=1, no branch, no feature dir | refused, rc=1, no branch, no feature dir |

### C. Hook control (`allow-repo-commands.sh`, not in the diff)

| command | head | base |
|---|---|---|
| `ls <copy>` | allow | allow |
| `cat <copy>/plan-runner-roots.sh` | allow | allow |
| `rm -rf <copy>/self` | asked | asked |
| `bash -c 'rm x'` | deny | deny |
| `<copy>/feature-close.sh --self …` | asked | asked |
| `<copy>/run-review.sh --self …` | asked | asked |
| `<copy>/feature-start.sh --self x` | asked | asked |
| `git -C <copy> push origin main` | deny | deny |
| `env <copy>/feature-close.sh --self x` | asked | asked |
| `awk -f /dev/stdin <copy>/…/audit-report.md` | asked | asked |

The new `AUDIT_*` names and `audit_report_unclassed` collide with nothing else in either copy
(grep across `*.sh`/`*.py`).

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | a clean report with `## Findings` / `None.` and a blocking row under `## Non-blocking findings` (case 30) | close passes the audit checks | close passes the audit checks | `scratch/close.sh scratch/head head cases/30-…md` vs `scratch/close.sh scratch/base base cases/30-…md` |
| non-blocking | `## Findings` / `None.` only inside a fenced code block, no rendered section (case 31) | close passes the audit checks | close passes the audit checks | `scratch/close.sh` on each copy with `cases/31-…md` |
| non-blocking | `## Findings` / `None.` only inside an HTML comment, no rendered section (case 32) | close passes the audit checks | close passes the audit checks | `scratch/close.sh` on each copy with `cases/32-…md` |
| non-blocking | a lone CR inside a row hides a blocking row that renders as its own line (case 38) | close passes the audit checks | close passes the audit checks | `scratch/close.sh` on each copy with `cases/38-…md` |
| non-blocking | `audit_report_unclassed` on a missing or unreadable file prints nothing (case 41) | reader passes it; the close refuses at the earlier verdict check | close refuses at the verdict check | `scratch/unit.sh scratch/head …` and `scratch/close.sh` on each copy with `-` (no report written) |

## Non-blocking findings

Each is a follow-up to file. None is a regression: the base runs no findings check, so it
passes every one of these reports.

1. **A blocking row filed under the wrong section (case 30).** The reader reads only
   `## Findings`, so a row whose first cell is `blocking` under `## Non-blocking findings` (or
   any other section) does not reach it. Head and base both pass the audit checks. The rule
   should also refuse a clean report with a first-cell `blocking` table row in any section
   after the verdict line, or at least in `## Non-blocking findings`.
2. **A heading inside a fenced code block (case 31) or HTML comment (case 32).** The reader
   takes `## Findings` inside the fence or comment as the section. The rendered report has no
   such section, which the template says the close refuses. Head and base both pass. The rule
   should track ```` ``` ````/`~~~` fences and `<!-- … -->` and not match a heading inside
   them. Since the report should hold no fence or comment, it could also simply refuse any
   fence or comment line anywhere in the report.
3. **A lone CR mid-line (case 38).** awk splits only on LF, so `| non-blocking | x |<CR>| blocking | y |`
   is one row with first cell `non-blocking`. CommonMark treats a bare CR as a line ending, so
   it renders as two rows, the second blocking. Head and base both pass. The rule should first
   turn every CR into a line break (e.g. `tr '\r' '\n'` before awk, after the trailing-CR strip
   that CRLF needs), or refuse any line that holds an interior CR.
4. **The reader fails open on a missing or unreadable file (case 41).** mawk cannot open the
   file, writes to stderr, skips `END` and prints nothing, which is the "all non-blocking"
   answer. The close is not exposed today: it refuses earlier when `report_verdict` reads the
   missing file as `unreadable`, on head as on base. The reader's own contract is "no such
   section at all is a problem — fail closed". It should print a problem line when the file is
   unreadable (e.g. `[[ -r "$1" ]] || { echo "unreadable report"; return 0; }`), so a future
   reordering of the close cannot turn this into a pass.

## Blocking findings

None. No input made the head more permissive than the base: the new reader only adds
refusals, and the reworded `feature-start.sh` refusal still refuses in both layouts. No input
silently allows a non-read-only command: the hook's decisions are identical on head and base
(table C), and its source is not in the diff.
