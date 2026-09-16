#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/allow-repo-commands.sh, the PreToolUse hook that auto-approves
# read/test Bash commands confined to the project root (hooks/README.md), denies any
# command that chains a `cd`/`pushd` with something else with a reason naming the fix,
# denies any git command that moves a ref or rewrites history with a reason naming
# LIFECYCLE.md rule 2, denies an assignment at command position whose own `$NAME` is used
# later on the same line with a reason saying to inline the literal, and expands simple
# brace lists before checking each word. Run by
# self/gate.sh, or by hand: bash self/tests/allow-repo-commands.sh
#
# Builds a throwaway project root under mktemp -d with a venv symlink, an in-repo
# worktree, the harness's own entry points in both spellings (a consuming repo's
# plans/gate.sh, agentTooling/check-plans.sh, agentTooling/analysis/*.py and this
# checkout's self/gate.sh, ./check-plans.sh, analysis/*.py), and three symlinks that
# escape the tree, then feeds the real hook the JSON payload Claude Code sends, one
# command at a time. Asserts that ordinary reads and runs are approved; that the harness
# entry points are approved by basename when the script resolves inside the root, and
# prompt outside it, through an escaping symlink, or in any of their writing forms
# (capture_planning.py --recapture/--all, manifest.py init/set-*, python3 -c, bash
# without -n); that every bypass the audit found is refused — variable expansion,
# `--flag=value` paths, attached and combined short flags, sed's `w`, `git branch`
# listing flags, exec-through flags, `|&`, relative paths and globs through symlinks,
# symlink-following recursion, redirects, a NUL byte; that single-quoted shell
# characters are literal while double-quoted ones are not; that the four command shapes
# that motivated the hook are denied when chained and approved once rewritten as a
# standalone `cd` and the command; that every ref-moving git shape is denied wherever it
# appears — after a separator, inside a `$(…)` substitution, behind `-C`, `--git-dir=` or
# `-c k=v` — while the read-only forms and the heredoc/`#`/quoted/unbalanced guards are
# not; that simple brace lists are approved when every expansion passes and refused
# through nested, quoted or escaped braces or an expansion outside the tree; that a
# worktree session cannot reach the main repo; and that a payload without cwd, with cwd
# outside the root, for another tool, or without CLAUDE_PROJECT_DIR approves nothing
# while a deny still fires. The home directory and /etc/hosts appear only as symlink
# targets and in command text — nothing is read from either. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "allow-repo-commands"
python3 - "$AT/hooks/allow-repo-commands.sh" "$TMP" <<'PY'
import json, os, subprocess, sys

HOOK, TMP = sys.argv[1], sys.argv[2]
ROOT = os.path.join(TMP, "repo")
WT = os.path.join(ROOT, ".worktrees", "wt")
HOME = os.path.expanduser("~")
NUL = chr(0)

for d in ["src", "tests", "dir", ".venv/bin", ".git/hooks",
          ".worktrees/wt/frontend/tests", ".worktrees/wt/.venv/bin"]:
    os.makedirs(os.path.join(ROOT, d))
for f in ["src/a.py", "tests/test_a.py", "dir/inner.txt", "README.md", "pyproject.toml",
          ".worktrees/wt/frontend/tests/x.spec.ts", ".git/config"]:
    open(os.path.join(ROOT, f), "w").close()
os.symlink("/usr/bin/python3", os.path.join(ROOT, ".venv/bin/python"))
os.symlink("/usr/bin/python3", os.path.join(WT, ".venv/bin/python"))
os.symlink(HOME, os.path.join(ROOT, "link-home"))
os.symlink("/etc/hosts", os.path.join(ROOT, "dir", "esc"))

# The harness's own entry points, in both spellings: a consuming repo's (plans/gate.sh,
# agentTooling/check-plans.sh, agentTooling/analysis/*.py) and this checkout's
# (self/gate.sh, ./check-plans.sh, analysis/*.py). Empty files are enough — the hook
# judges the path and the arguments, never the contents. The scripts that freeze cost or
# move a ref are here too, so their refusal is a real file being refused. OUTSIDE holds
# the same basenames outside the root, reachable through an escaping symlink.
OUTSIDE = os.path.join(TMP, "outside")
os.makedirs(OUTSIDE)
for d in ["plans", "agentTooling/analysis", "self", "analysis"]:
    os.makedirs(os.path.join(ROOT, d))
for f in ["plans/gate.sh", "self/gate.sh", "check-plans.sh", "agentTooling/check-plans.sh",
          "agentTooling/feature-start.sh", "agentTooling/feature-close.sh",
          "agentTooling/sweep.sh", "agentTooling/stamp-timing.sh",
          "analysis/report.py", "analysis/capture_planning.py", "analysis/manifest.py",
          "analysis/other.py", "agentTooling/analysis/report.py",
          "agentTooling/analysis/capture_planning.py", "agentTooling/analysis/manifest.py",
          "agentTooling/analysis/backfill_usage.py"]:
    open(os.path.join(ROOT, f), "w").close()
for f in ["gate.sh", "check-plans.sh", "report.py"]:
    open(os.path.join(OUTSIDE, f), "w").close()
os.symlink(OUTSIDE, os.path.join(ROOT, "link-out"))


def decide(payload, root=ROOT, env_root=True):
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    if env_root:
        env["CLAUDE_PROJECT_DIR"] = root
    p = subprocess.run([HOOK], input=json.dumps(payload), capture_output=True, text=True, env=env)
    if p.returncode != 0:
        return "ERR"
    if not p.stdout.strip():
        return "prompt"
    try:
        decision = json.loads(p.stdout)["hookSpecificOutput"]["permissionDecision"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return "ERR"
    return "DENY" if decision == "deny" else "ALLOW" if decision == "allow" else "ERR"


def run(cmd, cwd=ROOT, root=ROOT):
    return decide({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}, root)


def hook_output(cmd, cwd=ROOT, root=ROOT):
    payload = {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    env["CLAUDE_PROJECT_DIR"] = root
    p = subprocess.run([HOOK], input=json.dumps(payload), capture_output=True, text=True, env=env)
    if p.returncode != 0 or not p.stdout.strip():
        return {}
    try:
        return json.loads(p.stdout).get("hookSpecificOutput", {})
    except json.JSONDecodeError:
        return {}


def deny_reason_ok(cmd, words=("cd", "own", "absolute")):
    out = hook_output(cmd)
    if out.get("hookEventName") != "PreToolUse":
        return "hookEventName=%r" % out.get("hookEventName")
    if out.get("permissionDecision") != "deny":
        return "permissionDecision=%r" % out.get("permissionDecision")
    reason = out.get("permissionDecisionReason", "")
    missing = [w for w in words if w not in reason]
    if missing:
        return "reason missing %s: %r" % (missing, reason)
    return "ok"


# The git deny's reason must send the reader to the rule and to the sanctioned way in
GIT_REASON_WORDS = ("LIFECYCLE", "rule 2", "feature-start.sh", "feature-close.sh")


ALLOW = [
    "git status", "git log --oneline -5", "git diff HEAD~1 -- src/a.py", "git branch -a",
    "git worktree list", "git show HEAD:README.md", "git rev-parse --show-toplevel",
    "ls -la src", "cat README.md pyproject.toml", "head -20 src/a.py", "wc -l tests/*.py",
    "grep -rn 'resolve-view' src | head", "grep -rln x src --include='*.py'",
    "find . -name '*.py' -not -path './.venv/*'", "rg -n pattern src",
    "sed -n 5p README.md", "sed -n '/^import/,/^$/p' src/a.py", "sed -n '$p' README.md",
    "sed -nE '1,10p' src/a.py",
    ".venv/bin/python -m pytest tests -q", ".venv/bin/python -m ruff check src tests",
    ".venv/bin/ruff format --check src", f"{ROOT}/.venv/bin/python -m pytest -x",
    "python3 -m pytest tests/test_a.py::test_x -q", "npm run typecheck", "npm run build",
    "npm test", "npx playwright test --reporter=line",
    "cat dir/inner.txt | grep x | sort | head -3", "du -sh .venv", "stat src/a.py",
    "cat src/a.py > /dev/null; ls", "ls 2> /dev/null", "ls &>/dev/null", "sort -r README.md",
    "ls src # list it",
    "ls src", "grep -n '=>' src", "grep -n '\\$HOME' README.md", "grep '{' src/a.py",
    "cat 'a$b'", "grep -rn 'x' src 2>&1 | head -5", "cat '$HOME'/x",
]

# The harness's own entry points (hooks/README.md → What it approves). Matched by
# basename, so both spellings of the same script pass, and only when the path resolves
# inside the root.
ENTRY_ALLOW = [
    "plans/gate.sh", "./plans/gate.sh", "plans/gate.sh 08", "self/gate.sh", "./self/gate.sh",
    "self/gate.sh 12", f"{ROOT}/self/gate.sh",
    "check-plans.sh --self a-slug", "./check-plans.sh --self a-slug",
    "agentTooling/check-plans.sh a-slug", f"{ROOT}/agentTooling/check-plans.sh --self a-slug",
    "bash -n self/gate.sh", "bash -n plans/gate.sh self/gate.sh check-plans.sh",
    "shellcheck self/gate.sh", "shellcheck plans/gate.sh self/gate.sh",
    "python3 -m py_compile analysis/report.py",
    "python3 -B -m py_compile agentTooling/analysis/*.py",
    "python -m py_compile analysis/report.py analysis/manifest.py",
    "python3 analysis/report.py --self a-slug", "python3 -B analysis/report.py --all",
    "python3 agentTooling/analysis/report.py a-slug 2>&1 | tail -20",
    "python3 analysis/capture_planning.py --self --list-sessions --unclaimed",
    "python3 -B agentTooling/analysis/capture_planning.py --list-subagents --since 2026-01-01",
    "python3 analysis/manifest.py --self a-slug get base",
    "python3 -B agentTooling/analysis/manifest.py a-slug get session_window.to",
]
# The same basenames outside the tree, through an escaping symlink, and every writing or
# cost-freezing form: each falls through to the prompt.
ENTRY_PROMPT = [
    f"{OUTSIDE}/gate.sh", f"python3 {OUTSIDE}/report.py", f"bash -n {OUTSIDE}/gate.sh",
    f"{OUTSIDE}/check-plans.sh --self a-slug", "python3 /tmp/report.py",
    "python3 ../report.py", "../plans/gate.sh",
    "link-out/gate.sh", "python3 link-out/report.py", "bash -n link-out/gate.sh",
    "python3 analysis/capture_planning.py --recapture a-slug",
    "python3 analysis/capture_planning.py --self --all",
    "python3 analysis/capture_planning.py --self --all --recapture",
    "python3 analysis/capture_planning.py --list-sessions --recapture",
    "python3 analysis/capture_planning.py --self a-slug",
    "python3 analysis/manifest.py --self a-slug init --method direct",
    "python3 analysis/manifest.py --self a-slug set-plans 01-x-opus",
    "python3 analysis/manifest.py --self a-slug set-window-to 2026-01-01T00:00:00Z",
    "python3 analysis/manifest.py get init",
    "python3 analysis/other.py", "python3 agentTooling/analysis/backfill_usage.py --self",
    "python3 -c 'print(1)'", "python3 -B -c 'print(1)'", "python3 -m pdb analysis/report.py",
    "agentTooling/feature-start.sh a-slug", "agentTooling/feature-close.sh --self a-slug",
    "agentTooling/sweep.sh --self", "agentTooling/stamp-timing.sh --self a-slug checkpoint",
    "bash self/gate.sh", "bash -x self/gate.sh", "bash -n", "bash -c 'ls'",
    "shellcheck", "shellcheck -x self/gate.sh", "plans/gate.sh 08 extra",
]

PROMPT = [
    "cat $HOME/.ssh/id_rsa", "ls ${PWD}/../", 'cat "$HOME/.zshrc"',
    f"sort --output={HOME}/.zshrc README.md", f"git log --output={HOME}/x",
    f"git diff --output={HOME}/x", "python -m pytest --junit-xml=/tmp/x",
    "python -m pytest -o cache_dir=/tmp/x", f"grep --file={HOME}/.ssh/id_rsa src",
    "sed -i.bak 's/a/b/' README.md", "sed -ni 5p README.md", f"sort -o{HOME}/.zshrc README.md",
    "sort -T /tmp README.md", "sed -i '' 's/a/b/' README.md",
    f"sed 's/a/b/w {HOME}/.zshrc' README.md", f"sed -n 'w {HOME}/x' README.md",
    "sed -e 5p README.md", "sed -f script.sed README.md", "sed 5q README.md",
    "sed -n '5{p;q}' README.md",
    "git branch --set-upstream-to=x",
    "git -c core.pager='sh -c id' log", "git --git-dir=/tmp/x log",
    "git checkout -- .",
    "rg --pre 'sh -c id' x src", "rg --pre=cat x src", "sort --compress-program=sh README.md",
    "find . -exec rm {} \\;", "find . -delete", "find . -name x -execdir sh -c id \\;",
    "file -C -m magic",
    "ls |& sh", "ls | sh", "ls ; sh", "ls >& out", "ls ;; ls",
    "cat link-home/.zshrc", "cat dir/esc", "head dir/*", "cat link-home/*",
    "wc -l link-home/.zshrc", "grep x dir/esc",
    "grep -R secret .", "grep -rS secret .", "find . -L -name id_rsa", "find -L . -name x",
    "rg -L secret .", "rg --follow secret .",
    "tree -o out.txt", "uniq README.md out", "npm run dev", "npm run anything",
    "npx playwright install", "npx playwright codegen", "npx cowsay hi", "npx playwright",
    "npm run",
    "ls > /dev/nullx", "cat README.md > out.txt", "cat < README.md", "ls >> log", "ls 2>err",
    "cat README.md >/tmp/x", "cat > x <<'EOF'",
    f"cat {HOME}/.ssh/id_rsa", "rm -rf src",
    ".venv/bin/python -c 'print(1)'", ".venv/bin/python script.py", "python -m http.server",
    "ls $(cat /etc/passwd)", "ls `id`",
    "curl https://example.com", "/bin/ls /etc", "cat /etc/passwd",
    "ls ~", "ls ~/", "env", "FOO=1 ls", "eval ls", "exec ls", "sh -c ls", "bash", "xargs cat",
    "sudo ls", "ls\nrm -rf /", "ls\r", "echo hi > f", "printf x > f", "tee f",
    "cat -- /etc/passwd", "ls " + NUL,
    "cat 'a'$HOME", "cat \"'$HOME'\"", "cat 'x", 'ls "$(id)"', "ls $'\\x41'", "ls ~user",
    "cat \\\\$HOME", "ls '>' out", "grep '/usr/lib' src",
    "ls x#; rm -rf src", "cat README.md#;cat /etc/passwd", "ls src #x\nrm -rf src",
    f"cd {HOME}/.ssh", "cd .worktrees/wt", "cd", "cd -", f"cd {ROOT}/../other",
    f"cd {os.path.dirname(ROOT)}", f"cd {ROOT}/link-home", "cd /etc",
    f"{HOME}/evil/python -m pytest",
]

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
    "(cd /etc && cat passwd)", f"(cd {ROOT} && ls) && ls", f"cd {ROOT} && echo $(pwd)",
    f"x=$(pwd) && cd {ROOT}", f"echo $(cd {ROOT} && pwd) && cd {ROOT}",
    f"echo $(ls) cd && cd {ROOT}",
    f"cd {ROOT} && git checkout -b x", f"cd {ROOT} && rm -rf src",
    "cd && ls", "cd - && ls", f"cd {HOME}/.ssh && ls", "cd .worktrees/wt && ls",
    f"cd {ROOT}/../other && ls", f"cd {ROOT}/src || cd /etc; ls",
    f"cd {ROOT}/link-home && ls", f"cd {ROOT}/dir && cat esc",
    f"cd {ROOT} && cat $HOME/x", "cd /tmp && ls ~",
]
# `cd` that is not a chained command: a standalone cd, cd as an argument or inside quotes,
# a heredoc body, a substitution quoted or not (its cd moves no outer path), a word after a
# substitution, and an unbalanced quote (unjudgeable, so not denied)
NOT_DENIED = [
    (f"x=$(cd {ROOT} && pwd)", "prompt"), (f"ls $(cd {ROOT} && pwd)/src", "prompt"),
    (f"x=$(cd {ROOT}; pwd) && ls", "prompt"), ("echo $(pwd) cd", "prompt"),
    (f"echo $(echo $(cd {ROOT} && pwd))", "prompt"),
    (f"cd {ROOT}/src", "ALLOW"), (f"cd {ROOT}/src;", "ALLOW"), (f"cd {ROOT} 2>&1", "ALLOW"),
    ("echo cd && ls", "ALLOW"), ("ls && echo cd", "ALLOW"), ("grep -rn 'cd ' src", "ALLOW"),
    ("grep -n 'cd x && ls' src", "ALLOW"), ("find . -name cd", "ALLOW"),
    ('git commit -m "cd x && ls"', "prompt"), ("cat <<'EOF'\ncd x\nEOF", "prompt"),
    ('AT="$(cd "$(dirname "$0")/.." && pwd)"', "prompt"), ("cd 'x && ls", "prompt"),
    ("cd", "prompt"), ("echo x > cd && ls", "prompt"), ("cat a#<<EOF\ncd x\nls\nEOF", "prompt"),
]

# A git command that moves a ref, rewrites history or throws work away is denied
# wherever it sits on the line — after a separator, inside a `$(…)` substitution, or
# behind the global options that would otherwise hide the subcommand (LIFECYCLE.md rule 2)
GIT_DENY = [
    "git push --force", "git push -f origin main", "git push --force-with-lease origin main",
    "git push --force-with-lease=main:abc123 origin", "git push origin main --force",
    "git reset --hard", "git reset --hard HEAD~1", "git reset --hard origin/main",
    "git clean", "git clean -fdx src", "git stash", "git stash pop", "git stash list",
    "git rebase main", "git rebase -i HEAD~3", "git rebase --continue",
    "git worktree add x", f"git worktree add {ROOT}/.worktrees/y -b y",
    "git worktree remove wt", "git worktree prune", "git worktree add /tmp/x",
    "git checkout -b feature", "git checkout -B feature origin/main",
    "git switch -c feature", "git switch -C feature",
    "git branch new-branch", "git branch -d old", "git branch -D main",
    "git branch --delete old", "git branch -m a b", "git branch -M main",
    "git branch --move a b", "git branch --list --delete old",
    "ls && git worktree add x", "x=$(git rebase main)", "git status; git stash",
    "git status && git push --force", "(git clean -fd)", "git stash && ls",
    "echo $(git branch -D main)", "ls | git rebase main",
    f"git -C {ROOT} worktree add x", f"git -C {ROOT} branch -D main",
    f"git --git-dir={ROOT}/.git stash", f"git --git-dir {ROOT}/.git rebase main",
    "git -c user.name=x rebase main", "git -c core.pager=less -C /tmp worktree add x",
]
# Read-only git, the shapes that only look like mutations, and the same guards the
# chained-cd deny keeps: a heredoc, a `#`, quoted text, or a line that will not tokenize
# is never denied
GIT_NOT_DENIED = [
    ("git branch --show-current", "ALLOW"), ("git worktree list", "ALLOW"),
    ("git branch -a", "ALLOW"), ("git branch -v --list", "ALLOW"),
    ("git branch --merged main", "prompt"), ("git branch --contains HEAD", "prompt"),
    ("git push", "prompt"), ("git push origin main", "prompt"),
    ("git checkout -- README.md", "prompt"), ("git reset README.md", "prompt"),
    ("git commit -m 'git push --force'", "prompt"), ("git switch main", "prompt"),
    ("git worktree", "prompt"), ("git log --oneline -5", "ALLOW"),
    ("echo 'git rebase'", "ALLOW"), ("echo 'git clean -fd'", "ALLOW"),
    ("grep -rn 'git worktree add' src", "ALLOW"), ("ls src # git rebase main", "ALLOW"),
    ("cat <<'EOF'\ngit push --force\nEOF", "prompt"),
    ("cat a#<<EOF\ngit stash\nEOF", "prompt"), ("git rebase 'main", "prompt"),
    # The deny expands no braces, so a braced word is a word it cannot read: it prompts
    # here and the approval analysis, which does expand, refuses it (BRACE_PROMPT).
    ("git branch {-a,new}", "prompt"), ("git worktree {add,list} x", "prompt"),
]

# An assignment at command position followed by its own `$NAME` later on the line: the
# path is decided at run time, the reads fence cannot check it, and the literal is always
# available (design 2026-09-16 §3.7). Denied wherever the pair sits.
ASSIGN_DENY = [
    "X=/p; cat $X/f", "X=/p; cat ${X}/f", "export X=/p; ls $X",
    "X=/p && cat $X/f", "DIR=/tmp; sed -n 1p $DIR/f", "X=/p | cat $X",
    f"R={ROOT}; ls $R/src", f"R={ROOT}\nls $R/src",
    f"R={ROOT}; sed -n 1,5p $R/README.md; grep -n x $R/src/a.py",
    f"export R={ROOT}; cat ${{R}}/README.md",
]
# The shapes that merely look like it. An assignment with no use of its own name, an
# environment prefix on a command (which is not an assignment at command position), a
# variable nobody assigned on this line, a quoted `$`, and the three guards the other two
# denies keep — a heredoc, a `#`, and a line that will not tokenize.
ASSIGN_NOT_DENIED = [
    ("X=/p", "prompt"), (f"R={ROOT}", "prompt"), ("X=1 make", "prompt"),
    ("FOO=1 ls", "prompt"), ("X=/p; ls src", "prompt"), ("X=/p; cat $Y/f", "prompt"),
    ("echo '$X'", "ALLOW"), ("grep -n '\\$X' src", "ALLOW"),
    ("cat $HOME/f", "prompt"), ("echo $(pwd)", "prompt"), ("ls ${PWD}/src", "prompt"),
    ("cat <<'EOF'\nX=/p; cat $X\nEOF", "prompt"),
    ("cat a#<<EOF\nX=/p; cat $X\nEOF", "prompt"),
    ("ls src # X=/p; cat $X", "prompt"),
    ("X='/p; cat $X", "prompt"),
    ('AT="$(cd "$(dirname "$0")/.." && pwd)"', "prompt"),
]
# The deny's reason has to name the correction, as the other two do
ASSIGN_REASON_WORDS = ("inline", "literal", "run time")

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

WT_CASES = [(f"cat {ROOT}/README.md", "prompt"), ("cat frontend/tests/x.spec.ts", "ALLOW"),
            (f"cd {ROOT}", "prompt"), (f"cd {ROOT} && ls", "DENY")]
PAYLOAD_CASES = [
    ({"tool_name": "Bash", "tool_input": {"command": "ls"}}, "prompt"),
    ({"tool_name": "Bash", "cwd": "/etc", "tool_input": {"command": "ls"}}, "prompt"),
    ({"tool_name": "Edit", "cwd": ROOT, "tool_input": {"command": "ls"}}, "prompt"),
    ({"tool_name": "Bash", "cwd": ROOT, "tool_input": {}}, "prompt"),
    ({"tool_name": "Bash", "cwd": ROOT, "tool_input": {"command": "ls"}}, "ALLOW"),
]

fails = 0


def group(name, pairs, judge):
    global fails
    wrong = [(c, got) for c, want in pairs for got in [judge(c)] if got != want]
    for c, got in wrong:
        print("  FAIL  %s: got %s for %r" % (name, got, str(c)[:100]))
    if not wrong:
        print("  ok    %s (%d cases)" % (name, len(pairs)))
    fails += len(wrong)


group("approves repo-confined reads and runs", [(c, "ALLOW") for c in ALLOW], run)
group("refuses every audited bypass", [(c, "prompt") for c in PROMPT], run)
group("approves the harness's own entry points", [(c, "ALLOW") for c in ENTRY_ALLOW], run)
group("refuses an entry point outside the tree or in a writing form",
      [(c, "prompt") for c in ENTRY_PROMPT], run)
group("approves the unchained rewrites", [(cw, "ALLOW") for cw in UNCHAINED_ALLOW],
      lambda cw: run(cw[0], cwd=cw[1]))
group("refuses an unchained escape", [(cw, "prompt") for cw in UNCHAINED_PROMPT],
      lambda cw: run(cw[0], cwd=cw[1]))
group("denies every chained cd", [(c, "DENY") for c in DENY], run)
group("does not deny cd that is not chained", NOT_DENIED, run)
group("approves simple brace lists", [(c, "ALLOW") for c in BRACE_ALLOW], run)
group("refuses brace bypasses", [(c, "prompt") for c in BRACE_PROMPT], run)
group("denies every ref-moving git shape", [(c, "DENY") for c in GIT_DENY], run)
group("does not deny read-only git or an unjudgeable line", GIT_NOT_DENIED, run)
group("denies an assignment whose own $NAME is used later on the line",
      [(c, "DENY") for c in ASSIGN_DENY], run)
group("does not deny an assignment nobody dereferences, or an env prefix",
      ASSIGN_NOT_DENIED, run)
group("the assignment deny says to inline the literal",
      [(c, "ok") for c in ["X=/p; cat $X/f"]],
      lambda c: deny_reason_ok(c, ASSIGN_REASON_WORDS))
group("deny names the fix", [(c, "ok") for c in [f"cd {ROOT} && ls"]], deny_reason_ok)
group("the git deny names LIFECYCLE rule 2 and the sanctioned scripts",
      [(c, "ok") for c in ["git worktree add x", "git push --force"]],
      lambda c: deny_reason_ok(c, GIT_REASON_WORDS))
group("worktree session stays in its tree", WT_CASES, lambda c: run(c, cwd=WT, root=WT))
group("payload without cwd, outside cwd, or other tool approves nothing", PAYLOAD_CASES,
      lambda p: decide(p))
group("no CLAUDE_PROJECT_DIR approves nothing",
      [({"tool_name": "Bash", "cwd": ROOT, "tool_input": {"command": "ls"}}, "prompt")],
      lambda p: decide(p, env_root=False))
# A deny needs neither root nor cwd: the shape is wrong wherever it runs
group("both denies fire without a root or a cwd",
      [({"tool_name": "Bash", "tool_input": {"command": "git worktree add x"}}, "DENY"),
       ({"tool_name": "Bash", "tool_input": {"command": f"cd {ROOT} && ls"}}, "DENY")],
      lambda p: decide(p, env_root=False))
sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "allow-repo-commands: all checks passed"; else echo "allow-repo-commands: FAILED"; fi
exit "$rc"
