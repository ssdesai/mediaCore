# prototype

The measuring instrument behind the figures in `self/DESIGN-2026-11-19-hook-allowlist.md`.
Evidence, wired into nothing: no gate check, hook or script reads this folder, and the
build writes its own reader (`hooks/simple_line.py`, design §8) rather than promoting this
one. Every script is stdlib Python, run `python3 -B`, and reads the hook by importing
`hooks/allow-repo-commands.sh` as a module — so each depends on that file's function names
(`command_allowed`, `chains_chdir`, `git_denial`, `uses_own_assignment`, `command_verdict`,
`chain_tokens`, `judged_texts`, `never_judged`, `comment_and_heredoc_free`, `GIT_WORD_RE`,
`GIT_WORD_DROPPED_CHARS`) as they stand at this feature's base.

| File | What it is |
|---|---|
| `simple_line.py` | The grammar of design §1 as a reader: `simple_line(text)` returns the commands (words, redirects, environment prefix, heredoc flag) or `None`; `approval_eligible(text)` is §1's narrower tier; `why_outside(text)` a coarse label for a line outside it. The 20,000-character cap is not modelled. |
| `measure_lib.py` | Shared: loads the hook as a module, and harvests the upper-case list tables out of a test file's embedded Python with `ast` (a table a test builds in a loop is not seen; `ROOT` stands as `/fixture/repo`). |
| `measure.py` | `<root> <claude projects dir>` — the grammar against the test files' approval tables, the replay fixture, and every Bash command in the transcripts under the projects directory (today's verdict from the hook's own functions). Design §6. |
| `probe.py` | `<root> <empty dir>` — builds a fixture with three symlinks out of the root and prints, per line, today's `command_allowed`, grammar membership and what bash 5.2 does; then every table's rows in and outside the grammar. Design "The defect". |
| `probe_dropped.py` | `<root> <empty dir>` — today's approval for one example of each shape §1 drops. |
| `deny_side.py` | `<root>`, with `AGENTTOOLING_PROFILE=local` — the deny-side tables: rows outside the grammar, how many the three shape denies deny today, and how many a single plain reading would keep, lose and add. Design §3. |
| `outside_rows.py` | `<root> <test file> <TABLE>…` — the rows of the named tables outside the grammar, by the shape that puts them there. |
| `mini_diff.py` | `<empty dir>` — the differential of design §4, check 1: generated lines read by `simple_line` and run by bash in an empty sandbox with logging functions. About 150 seconds. |
| `heredoc_probe.py` | The canonical heredoc word with hostile bodies, run by bash. |

## Recorded output (2026-11-19, bash 5.2.21, no zsh installed)

`mini_diff.py`, the grammar as committed:

```
cases 87988; in the grammar 5489; of those: bash ran an invocation the reader did not read 0, bash made a file the reader did not read 0, bash -n refused 0; outside the grammar and bash ran something: 26826
```

Its first run, before "never a pattern in a command's first word or a redirect's target"
and before double quotes took POSIX's escapes (6,110 lines in the grammar then):

```
  FAIL run      'p0 >a|*' -> Counter({('a',): 1})
```

`measure.py /home/user/agentTooling /root/.claude/projects`:

```
== 1. tables of the hook's test files ==
  allow-repo-commands.sh       ALLOW                      rows  56  not approvable under the grammar   2
      unquoted # (comment)               'ls src # list it'
      bracket glob / [ ]                 'cat [R]EADME.md'
  allow-repo-commands.sh       ENTRY_ALLOW                rows  34  not approvable under the grammar   0
  allow-repo-commands.sh       RUNNER_READ_ALLOW          rows  51  not approvable under the grammar   0
  allow-repo-commands.sh       SWEEP_ALLOW                rows  16  not approvable under the grammar   0
  allow-repo-commands.sh       UNCHAINED_ALLOW            rows   8  not approvable under the grammar   0
  allow-repo-commands.sh       BRACE_ALLOW                rows  10  not approvable under the grammar   9
      brace                              'ls {src,tests}'
      brace                              'cat {src/a.py,README.md}'
      brace                              'ls {src,tests}/*.py'
      brace                              'ls /fixture/repo/{src,tests}'
      brace                              'wc -l {src,tests}/*.py | sort'
      brace                              'ls src/{a,b}.py'
      brace                              'head -5 README.md {src/a.py,tests/test_a.py}'
      brace                              'grep -n x {src,tests}'
      brace                              'git diff HEAD -- {src,tests}'
  hook-escalation.sh           SCRATCH_ALLOW              rows  10  not approvable under the grammar   0
  total rows                         2521
  total outside                      799
  total allow rows                   185
  total allow rows losing approval   11
== 2. replay fixture (its own expected verdicts) ==
  ALLOW    in grammar approvable 6
  ASK      in grammar -          2
  ASK      in grammar approvable 3
  ASK      outside    -          1
  DENY     in grammar approvable 2
  DENY     outside    -          1
  REWRITE  in grammar -          3
  REWRITE  in grammar approvable 3
  REWRITE  outside    -          7
== 3. this machine's transcripts, today's hook run on each Bash command ==
  commands: 58
  today ALLOW        in grammar 18
  today ASK          in grammar 38
  today ASK          outside    2
  approved today, not approvable under the grammar: 0
  outside: ! or other character                 2
```

The same third section under the first draft of the grammar, which refused a backslash in
double quotes (49 commands at the time):

```
  today ALLOW        in grammar 15
  today ALLOW        outside    3
  approved today, not approvable under the grammar: 3
      backslash outside single quotes    'grep -rlE "^\\[[0-9:]+\\] Bash|Bash: |\\"Bash\\"" --include=*.progress.md self/features --count'
      backslash outside single quotes    'grep -rln "audit-opus\\|AUDIT_TEMPLATE\\|audit template" --include=*.sh --include=*.md --include=*.py . --exclud'
      backslash outside single quotes    'grep -rn "AUDIT.md\\|audit.*template\\|REVIEW_AUDIT" run-review.sh templates/README.md'
```

`probe.py` (first section; `vm` is the content of `/etc/hostname`, the links' target, so a
line that prints it read a file outside the root):

```
  "cat 'a >/dev/null b'"             approved=True  grammar=True  bash rc=0 out='vm'
  "cat 'a  b'"                       approved=True  grammar=True  bash rc=1 out=''
  'cat dir/[^i]*'                    approved=True  grammar=False bash rc=0 out='vm'
  'cat dir/[!i]*'                    approved=False grammar=False bash rc=0 out='vm'
  'cat "dir/\\`x"'                   approved=True  grammar=True  bash rc=0 out='vm'
  'grep "\\$x" README.md'            approved=True  grammar=True  bash rc=1 out=''
  'ls &'                             approved=True  grammar=False bash rc=0 out='README.md'
  'ls src &'                         approved=True  grammar=False bash rc=0 out='a.py'
  'ls;'                              approved=True  grammar=False bash rc=0 out='README.md'
  'ls src # list it'                 approved=True  grammar=False bash rc=0 out='a.py'
  'cat =python3'                     approved=True  grammar=False bash rc=1 out=''
  'ls src\xa0README.md'              approved=True  grammar=False bash rc=2 out=''
  'grep -n "it\'s" README.md'        approved=True  grammar=True  bash rc=1 out=''
  'git log -1 --format=%H'           approved=True  grammar=True  bash rc=128 out=''
  'X=1 ls'                           approved=False grammar=True  bash rc=0 out='README.md'
  'ls ; ; ls'                        approved=True  grammar=False bash rc=2 out=''
  'cat README.md > /dev/null'        approved=True  grammar=True  bash rc=0 out=''
  'cat dir/esc'                      approved=False grammar=True  bash rc=0 out='vm'
```

`approved` is today's hook. The first and fifth lines are in the grammar, where the reader
returns the path bash opens (`a >/dev/null b`, ``dir/`x``) and the unchanged confinement
check then refuses the link.

`probe_dropped.py`:

```
  'ls src # list it'               approved today=True  approvable under the grammar=False
  'cat src/a#b'                    approved today=True  approvable under the grammar=False
  'ls {src,README.md}'             approved today=True  approvable under the grammar=False
  'cat [R]EADME.md'                approved today=True  approvable under the grammar=False
  'grep -n \\# README.md'          approved today=True  approvable under the grammar=False
  'grep -n "a\\.b" README.md'      approved today=True  approvable under the grammar=True
  'grep -n "\\$x" README.md'       approved today=True  approvable under the grammar=True
  'ls src &'                       approved today=True  approvable under the grammar=False
  'ls src;'                        approved today=True  approvable under the grammar=False
  'cat =python3'                   approved today=True  approvable under the grammar=False
  'ls src/**'                      approved today=True  approvable under the grammar=False
  'ls src/*.py'                    approved today=True  approvable under the grammar=True
  'ls -la src | head -3'           approved today=True  approvable under the grammar=True
  'cat README.md 2>/dev/null'      approved today=True  approvable under the grammar=True
  'git log -1 HEAD~1'              approved today=True  approvable under the grammar=True
  'git show HEAD^'                 approved today=True  approvable under the grammar=True
  'cat <<EOF\nx\nEOF'              approved today=False approvable under the grammar=False
  'ls src\tREADME.md'              approved today=True  approvable under the grammar=True
  'X=1 ls src'                     approved today=False approvable under the grammar=False
```

`deny_side.py` (columns: rows; then, of the rows outside the grammar: how many, denied
today by a shape deny, denied by the single reading, lost, gained; then how many name git):

```
DENY                          51 |    23     23     22     1     0 |     0 (not denied today 0)
NOT_DENIED                    18 |    10      0      4     0     4 |     0 (not denied today 0)
CHAINED_NOT_APPROVED           8 |     8      0      5     0     5 |     0 (not denied today 0)
GIT_DENY                      66 |     3      3      3     0     0 |     3 (not denied today 0)
GIT_PUSH_MAIN_DENY            11 |     0      0      0     0     0 |     0 (not denied today 0)
GIT_NOT_DENIED                44 |    11      0      6     0     6 |    11 (not denied today 11)
GIT_AUDIT_DENY               175 |   170    170     85    85     0 |   170 (not denied today 0)
UNLEXED_GIT_DENY              87 |    87     87     82     5     0 |    87 (not denied today 0)
BASH_REFUSED_GIT_DENY         38 |    38     38     35     3     0 |    38 (not denied today 0)
BASH_PARSED_QUOTE_DENY         5 |     5      0      0     0     0 |     5 (not denied today 5)
BASH_PARSED_PROMPT             7 |     7      0      2     0     2 |     6 (not denied today 6)
TORN_READING_DENY              9 |     9      0      1     0     1 |     0 (not denied today 0)
TORN_READING_NOT_DENIED       36 |    30      0      1     0     1 |    12 (not denied today 12)
ASSIGN_DENY                   15 |    15     15     15     0     0 |     0 (not denied today 0)
ASSIGN_NOT_DENIED             11 |     7      0      2     0     2 |     0 (not denied today 0)
OPAQUE_NOT_DENIED             38 |     8      0      0     0     0 |     0 (not denied today 0)
UNREADABLE_NOT_DENIED          9 |     7      0      0     0     0 |     0 (not denied today 0)
ASK_CASES                     12 |     3      0      0     0     0 |     0 (not denied today 0)
AUTHORING_NOT_DENIED          40 |    10      0      0     0     0 |     0 (not denied today 0)
{'rows': 680, 'outside': 451, 'lost': 94, 'gained': 21, 'git named': 332, 'today deny': 336, 'git named not denied today': 34}
```

"Denied today" here is the three shape denies only (`chains_chdir`, `git_denial` under the
local profile, `uses_own_assignment`); a REWRITE from the verdict layer is not counted, which
is why `BASH_PARSED_QUOTE_DENY` and `TORN_READING_DENY` read 0.

`outside_rows.py … allow-repo-commands.sh DENY ASSIGN_DENY` (the 38 rows of design §6):

```
== DENY: 23 outside ==
  heredoc (not the canonical word)         5
  $NAME / ${…} / $'…'                      5
  $( or backtick                           4
  line break outside quotes                2
  subshell or group ( )                    2
  unquoted # (comment)                     2
  background or other &                    1
  tilde at a word start                    1
  backslash outside single quotes          1
== ASSIGN_DENY: 15 outside ==
  $NAME / ${…} / $'…'                      11
  $( or backtick                           3
  heredoc (not the canonical word)         1
```

(The one `ASSIGN_DENY` row labelled a heredoc holds a `$X` as well.)

`heredoc_probe.py`:

```
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body='plain message'
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body='it\'s "quoted" and `ticked` and $(p0 PWNED) a'
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body='x ) " ; p0 PWNED ; echo "('
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body='x )" ; p0 PWNED ; echo "$(cat <<\'EOF\''
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body=')"\np0 PWNED\necho "'
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body=' EOF\n)" ; p0 PWNED ; echo "'
  grammar=True  bash ran exactly [p0 -m <body>, p0 after]=True  body='# a comment\n\n\ttabbed\n'
  grammar=False bash ran exactly [p0 -m <body>, p0 after]=False body='EOF)" ; p0 PWNED ; echo "'
  grammar=False bash ran exactly [p0 -m <body>, p0 after]=True  body='EOFS\nmore'
```

## Found on the way, outside this feature's scope

- `hooks/README.md` → "Accepted limits" says any `$` outside single quotes prompts "even
  when escaped inside double quotes"; `grep "\$x" README.md` is approved today (above).
- The three lines of the design's "The defect" are pre-existing silent allows behind a
  planted link, in no `self/BACKLOG.md` entry (design §7, decision 7).
