Verdict: clean

# Security audit — audit-blocks-only-new (round 2)

## Scope

The diff against `origin/main` touches two audit paths, and both are prose:

- `hooks/README.md`: one paragraph re-describing the finding classes.
- `templates/SECURITY_AUDIT.md`: the classification rule. Blocking is now only a
  regression, which includes a silent allow that the head introduces. A pre-existing silent
  allow is now non-blocking: it goes under `## Non-blocking findings` and is filed in the
  BACKLOG before the close. Round 1's dangling "(a)" is now "the REGRESSION rule".

No executable rule changed. I extracted `git archive HEAD` and `git archive origin/main` and
compared them with `diff -rq`. They differ only in `LIFECYCLE.md`, `ORCHESTRATION.md`,
`hooks/README.md`, `self/BACKLOG.md`, `self/tests/README.md`, `self/tests/security-audit.sh`,
`templates/SECURITY_AUDIT.md` and this feature's own directory. These are byte-identical:
`hooks/allow-repo-commands.sh`, `plan-runner-roots.sh` (which holds `audit_report_unclassed`),
`feature-close.sh`, `run-review.sh` and `.claude/`.

The diff changes two rules, and both were attacked:

1. **R1, the hook's command policy** (`hooks/allow-repo-commands.sh`). It allows read-only
   commands, sends back unreadable shapes and asks about the rest, for every Bash call.
   Only its README text changed. It was attacked to confirm that head and base return the
   same result for every input.
2. **R2, the audit classification and the close's enforcement of it.** `feature-close.sh`
   calls `audit_report_unclassed`, which refuses a `Verdict: clean` report that has a
   `blocking` row, an unclassified row or line, or no `## Findings` section. The diff
   changes what an auditor may class as non-blocking. It does not change the parser.

Copies: `/tmp/plan-capture.IQZ83S/scratch/head` (HEAD) and
`/tmp/plan-capture.IQZ83S/scratch/base` (origin/main), built by `scratch/setup.sh`. R1 was
run with `scratch/hook.py` and R2 with `scratch/reports.sh`. Every R1 payload is a
PreToolUse JSON with `tool_name: Bash`, a fresh `session_id`, `agent_id: ""` and `cwd` and
`CLAUDE_PROJECT_DIR` set to the copy. Each was run as
`python3 <copy>/hooks/allow-repo-commands.sh`. "ask" means no output, so the human decides.

## Attempts

### R1: the hook, the same payload on both copies

| # | input | head | base |
|---|---|---|---|
| 1 | `ls` | allow | allow |
| 2 | `git status` | allow | allow |
| 3 | `rm -rf /` | ask | ask |
| 4 | `env rm -rf x` | ask | ask |
| 5 | `env env rm x` | ask | ask |
| 6 | `/usr/bin/env rm x` | ask | ask |
| 7 | `command rm x` | ask | ask |
| 8 | `exec -a ls rm x` | ask | ask |
| 9 | `nohup rm x` | ask | ask |
| 10 | `echo a \| xargs rm` | ask | ask |
| 11 | `sudo ls` | ask | ask |
| 12 | `find . -exec rm {} \;` | ask | ask |
| 13 | `find . -delete` | ask | ask |
| 14 | `bash -c "ls"` | deny | deny |
| 15 | `cat f \| sh` | deny | deny |
| 16 | `python3 - <<'EOF'` … `EOF` (heredoc) | deny | deny |
| 17 | `r""m x` | ask | ask |
| 18 | `r\m x` | ask | ask |
| 19 | `ls {a,b}` | allow | allow |
| 20 | `X=/; ls $X` | deny | deny |
| 21 | `ls $(pwd)/x` | deny | deny |
| 22 | `` ls `pwd` `` | ask | ask |
| 23 | `git push --force origin main` | deny | deny |
| 24 | `git push -fu origin claude/audit-blocks-only-new` | deny | deny |
| 25 | `git push --forc{e,x} origin main` | deny | deny |
| 26 | `echo x > f` | deny | deny |
| 27 | `sed -i s/a/b/ f` | deny | deny |
| 28 | `sed -n 1p f > g` | ask | ask |
| 29 | `ls > out` | ask | ask |
| 30 | `tee f < /dev/null` | ask | ask |
| 31 | `cat f \| tee g` | ask | ask |
| 32 | `cat ~/x` | deny | deny |
| 33 | `cat ../x` | deny | deny |
| 34 | `cat /etc/passwd` | ask | ask |
| 35 | `git -C /tmp status` | ask | ask |
| 36 | `sleep 5` | deny | deny |
| 37 | `git commit -m x` | ask | ask |
| 38 | `git stash` | deny | deny |
| 39 | `git checkout main` | ask | ask |
| 40 | `cp a b` | ask | ask |
| 41 | `python3 x.py` | ask | ask |
| 42 | `ls; rm x` | deny | deny |
| 43 | `ls && rm x` | deny | deny |
| m1 | payload `{}` | ask | ask |
| m2 | payload `not json` | ask | ask |
| m3 | payload `{"tool_name":"Bash","tool_input":{}}` | ask | ask |
| m4 | payload `{"tool_name":"Bash","tool_input":{"command":123}}` | ask | ask |

Every input got the same result on head and base. None of them writes or runs anything that
is not read-only and is silently allowed, on either copy.

### R2: the close's report parser on crafted `Verdict: clean` reports

Each report was checked as `source <copy>/plan-runner-roots.sh; audit_report_unclassed <report>`.
"accepted" means nothing was printed, so the close goes on.

| # | report's `## Findings` content | head | base |
|---|---|---|---|
| r1 | `None.` | accepted | accepted |
| r2 | header + `non-blocking` row describing a pre-existing silent allow | accepted | accepted |
| r3 | header + `blocking` row | refused (`blocking:`) | refused (`blocking:`) |
| r4 | first cell `pre-existing silent allow` (a third class) | refused (`unclassified:`) | refused (`unclassified:`) |
| r5 | first cell `Non-Blocking`, with `\|` inside a later backticked cell | accepted | accepted |
| r6 | first cell `non-blocking silent` | refused (`unclassified:`) | refused (`unclassified:`) |
| r7 | no `## Findings` section, only `## Non-blocking findings` | refused (`no ## Findings section`) | refused (same) |
| r8 | no header row: `non-blocking` row, then `blocking` row | refused (`blocking:`) | refused (`blocking:`) |
| r9 | header + `non-blocking` row + a free-text note line | refused (`unclassified:`) | refused (`unclassified:`) |
| r10 | first cell `non-blocking (pre-existing silent allow)` | refused (`unclassified:`) | refused (`unclassified:`) |
| r11 | first cell `\|non-blocking\|` with no padding | accepted | accepted |
| r12 | a second `class` header row standing in for a finding | refused (`unclassified:`) | refused (`unclassified:`) |

The parser admits no third class, and an annotation in the class cell does not pass either.
To be accepted, a pre-existing silent allow has to be classed `non-blocking` and flagged in
`## Non-blocking findings`, which is what the amended rule asks for.

Other checks:
- `grep -nE "\((a|b)\)|SILENT ALLOW|even when the base"` over the head's
  `templates/SECURITY_AUDIT.md`, `LIFECYCLE.md`, `hooks/README.md` and `ORCHESTRATION.md`
  returns nothing. No prose still refers to a removed clause.
- `bash <head>/self/tests/security-audit.sh` passes every check, B4 included.

## Findings

None.

## Non-blocking findings

None. No pre-existing silent allow was found: on both copies, every input in R1 that is not
read-only is asked or denied.

## Blocking findings

None.
