# 101 — tests: the hook denies a chained cd and approves simple brace lists

feature: agentTooling/hook-cd-deny-braces — plan 1 of 4. `hooks/allow-repo-commands.sh`
gains a `deny` decision for any Bash command that chains `cd`/`pushd` with another
command (the reason tells the model how to rewrite it), and stops refusing simple brace
lists (`ls {src,tests}`) in otherwise-approvable reads by expanding them before its
path checks.

Rewrite `self/tests/allow-repo-commands.sh` to assert the new policy. RED until plan 102.

Executor note: file paths are authoritative — do not traverse ancestor READMEs
before editing. Update only the README files explicitly listed below.

Pinned facts:
- The test drives the real hook as a subprocess and reads its stdout. A decision is one
  JSON object `{"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "allow"|"deny", "permissionDecisionReason": "..."}}`, or no output.
- `ROOT`, `WT`, `HOME` and the symlinks `link-home` (→ home) and `dir/esc` (→ /etc/hosts)
  are built at the top of the file's Python block. Nothing new needs creating.
- Inside the Python f-strings, a literal brace is written `{{` / `}}`. The new brace cases
  below are plain strings (not f-strings) unless shown with `f`.

## Files

- Modify `self/tests/allow-repo-commands.sh`
- Modify `self/tests/README.md` (the `allow-repo-commands.sh` entry only)
- Modify `self/README.md` (the `tests/` row's parenthetical on `allow-repo-commands.sh` only)

## `self/tests/allow-repo-commands.sh`

1. **`decide`** returns `"DENY"` when the stdout JSON's
   `hookSpecificOutput.permissionDecision` is `"deny"`, `"ALLOW"` when it is `"allow"`,
   `"prompt"` on empty stdout, and `"ERR"` on a non-zero exit or stdout that is not JSON.
   Parse with `json.loads`, not a substring test. `run` gains no new parameters.

2. **Remove from `ALLOW`** these six entries (they chain cd and are now denied):
   the four `cd {WT}…` entries at the top, `f"cd {ROOT}/src && cat a.py"`, and
   `f"cd {ROOT}/dir && cat inner.txt"`.

3. **Remove from `PROMPT`** every entry that chains a cd:
   `"(cd /etc && cat passwd)"`, `f"cd {ROOT}/dir && cat esc"`, `f"cd {HOME}/.ssh && ls"`,
   `"cd .worktrees/wt && ls"`, `"cd && ls"`, `"cd - && ls"`,
   `f"cd {ROOT}/../other && ls"`, `f"cd {os.path.dirname(ROOT)} && ls"`,
   `f"cd {ROOT} && {HOME}/evil/python -m pytest"`, `f"cd {ROOT}/src && cd /etc && ls"`,
   `f"cd {ROOT}/src || cd /etc; ls"`, `f"cd {ROOT}/link-home && ls"`.
   Also remove the two existing brace entries (`"cat {/etc/passwd,}"` and the
   `id_rsa,README.md` one); they move to `BRACE_PROMPT` below.

4. **Add to `PROMPT`** the standalone forms, so the cd-target checks keep their coverage:

```python
    f"cd {HOME}/.ssh", "cd .worktrees/wt", "cd", "cd -", f"cd {ROOT}/../other",
    f"cd {os.path.dirname(ROOT)}", f"cd {ROOT}/link-home", "cd /etc",
    f"{HOME}/evil/python -m pytest",
```

5. **Add these lists** after `PROMPT`:

```python
# The rewritten, unchained shapes of the commands that motivated the hook: cd on its own,
# then the command with cwd where the cd left it
UNCHAINED_ALLOW = [
    (f"cd {WT}", ROOT), (f"cd {WT}/frontend", ROOT), (f"cd {ROOT}/src", ROOT),
    (".venv/bin/python -m pytest tests/test_acceptance_issue.py -q 2>&1 | tail -30", WT),
    ("npx playwright test tests/x.spec.ts --reporter=line 2>&1 | tail -45", f"{WT}/frontend"),
    ("ls src/*.css src/styles 2>/dev/null", f"{WT}/frontend"),
    ("sed -n 40,120p tests/x.spec.ts", f"{WT}/frontend"), ("cat a.py", f"{ROOT}/src"),
]
UNCHAINED_PROMPT = [("cat esc", f"{ROOT}/dir")]

# A cd or pushd sharing the command with anything else is denied, whatever else the
# command does — reads, writes, or shapes the approval analysis would refuse anyway
DENY = [
    f"cd {ROOT} && ls", f"cd {ROOT}; ls", f"cd {ROOT} || ls", f"cd {ROOT} | ls",
    f"cd {ROOT} & ls", f"ls && cd {ROOT}", f"cd {ROOT}&&ls", f"cd {ROOT};ls",
    f"cd {ROOT}/src && cd {ROOT}/dir", f"pushd {ROOT} && ls",
    f"cd {WT} && .venv/bin/python -m pytest tests -q 2>&1 | tail -30",
    f"cd {ROOT}/src && cat a.py", f"cd '{ROOT}/src' && ls", f'cd "{ROOT}/src"; ls',
    f"cd {ROOT} 2>&1 && ls", f"cd {ROOT} >/dev/null; ls",
    f"cd {ROOT}\nls", f"cd {ROOT}\n.venv/bin/python -c \"import os\nprint(1)\"",
    "(cd /etc && cat passwd)", f"x=$(cd {ROOT} && pwd)",
    f"cd {ROOT} && git checkout -b x", f"cd {ROOT} && rm -rf src",
    "cd && ls", "cd - && ls", f"cd {HOME}/.ssh && ls", "cd .worktrees/wt && ls",
    f"cd {ROOT}/../other && ls", f"cd {ROOT}/src || cd /etc; ls",
    f"cd {ROOT}/link-home && ls", f"cd {ROOT}/dir && cat esc",
    f"cd {ROOT} && cat $HOME/x", "cd /tmp && ls ~",
]
# `cd` that is not a chained command: a standalone cd, cd as an argument or inside quotes,
# a heredoc body, a quoted substitution, and an unbalanced quote (unjudgeable, so not denied)
NOT_DENIED = [
    (f"cd {ROOT}/src", "ALLOW"), (f"cd {ROOT}/src;", "ALLOW"), (f"cd {ROOT} 2>&1", "ALLOW"),
    ("echo cd && ls", "ALLOW"), ("ls && echo cd", "ALLOW"), ("grep -rn 'cd ' src", "ALLOW"),
    ("grep -n 'cd x && ls' src", "ALLOW"), ("find . -name cd", "ALLOW"),
    ('git commit -m "cd x && ls"', "prompt"), ("cat <<'EOF'\ncd x\nEOF", "prompt"),
    ('AT="$(cd "$(dirname "$0")/.." && pwd)"', "prompt"), ("cd 'x && ls", "prompt"),
    ("cd", "prompt"),
]

# Simple brace lists are expanded before the path checks, as bash expands them
BRACE_ALLOW = [
    "ls {src,tests}", "cat {src/a.py,README.md}", "ls {src,tests}/*.py", f"ls {ROOT}/{{src,tests}}",
    "wc -l {src,tests}/*.py | sort", "ls src/{a,b}.py", "head -5 README.md {src/a.py,tests/test_a.py}",
    "grep -n x {src,tests}", "git diff HEAD -- {src,tests}", "grep '{a,b}' src/a.py",
]
# Each expansion is checked, and anything but a simple unquoted list still refuses
BRACE_PROMPT = [
    "cat {/etc/passwd,}", f"cat {{{HOME}/.ssh/id_rsa,README.md}}",
    "cat {src/a.py,/etc/passwd}", "cat {src/a.py,dir/esc}", "ls {src,link-home}/",
    "cat {src/a.py,~/.zshrc}", "sed -{n,i} 5p README.md", "sort -{r,o}x README.md",
    "sort --{output,x}=out.txt README.md", "git branch '{-a,-v}'", "git branch {-a,new}",
    "cat {a,{/etc/passwd,b}}", "cat {src/a.py}", 'ls "{src,/etc}"', "cat {'/etc/passwd',x}",
    "cat \\{src,/etc/passwd\\}", "cat {src,$HOME}", "cat {a..c}",
    "cat {1,2,3,4,5,6,7,8}{1,2,3,4,5,6,7,8}{1,2,3,4,5,6,7,8}",
]
```

6. **`WT_CASES`**: replace `(f"cd {ROOT} && ls", "prompt")` with `(f"cd {ROOT}", "prompt")`
   and add `(f"cd {ROOT} && ls", "DENY")`.

7. **A deny-reason check.** Add a helper that runs the hook on one command and returns the
   parsed `hookSpecificOutput` dict (or `{}`), and a group
   `"deny names the fix"` over `[f"cd {ROOT} && ls"]` whose judge returns `"ok"` when
   `hookEventName == "PreToolUse"`, `permissionDecision == "deny"`, and the reason
   contains all of `"cd"`, `"own"` and `"absolute"`. Otherwise it returns a short
   description of what was wrong. The expected value is `"ok"`.

8. **Groups.** After the existing two `group(...)` calls for `ALLOW` and `PROMPT`, add in
   this order (mirror the existing `group` calls' shape):
   - `"approves the unchained rewrites"`: `UNCHAINED_ALLOW`, judge `lambda cw: run(cw[0], cwd=cw[1])`,
     expected `"ALLOW"`; `"refuses an unchained escape"`: `UNCHAINED_PROMPT`, same judge, `"prompt"`.
   - `"denies every chained cd"`: `DENY`, expected `"DENY"`.
   - `"does not deny cd that is not chained"`: `NOT_DENIED` pairs as given.
   - `"approves simple brace lists"`: `BRACE_ALLOW`, `"ALLOW"`.
   - `"refuses brace bypasses"`: `BRACE_PROMPT`, `"prompt"`.
   - the deny-reason group.
   Leave the worktree, payload and `CLAUDE_PROJECT_DIR` groups where they are.
   `group`'s FAIL line prints `str(c)[:100]`, which works for tuples too; keep it.

9. **Header comment** (lines 4-20): say the hook approves repo-confined reads and runs,
   **denies** a chained `cd`/`pushd` with a reason naming the fix, and expands simple brace
   lists before checking each word. Drop "the four command shapes that motivated the hook
   are approved" and "brace expansion" from the bypass list. Add that the motivating shapes
   are asserted as denied when chained and approved when rewritten unchained.

## `self/tests/README.md`

In the `allow-repo-commands.sh` entry, replace "Asserts the four `cd X && cmd` shapes that
motivated the hook are approved along with ordinary reads and runs" with: asserts that
ordinary reads and runs are approved; that any command chaining `cd` or `pushd` with
another command is **denied** (separators `&&`, `||`, `;`, `|`, `&`, a line break, a
subshell or substitution) with a reason naming the rewrite, while `cd` as an argument, in
quotes, in a heredoc body or on its own is not; that the four motivating shapes are
approved once rewritten as a standalone `cd` and the command; and that simple brace lists
are approved when every expansion passes. In the bypass list, replace "brace expansion" with
"brace expansion to a path outside, a forbidden flag, `~`, or through nested, quoted or
escaped braces".

## `self/README.md`

In the `tests/` row, replace `every audited bypass refused, the motivating \`cd X && cmd\`
shapes approved` with `every audited bypass refused, a chained \`cd\` denied with its fix,
simple brace lists approved`.
