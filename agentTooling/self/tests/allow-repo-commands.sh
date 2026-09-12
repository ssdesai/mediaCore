#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/allow-repo-commands.sh, the PreToolUse hook that auto-approves
# read/test Bash commands confined to the project root (hooks/README.md). Run by
# self/gate.sh, or by hand: bash self/tests/allow-repo-commands.sh
#
# Builds a throwaway project root under mktemp -d with a venv symlink, an in-repo
# worktree, and two symlinks that escape the tree, then feeds the real hook the JSON
# payload Claude Code sends, one command at a time. Asserts that the four command
# shapes that motivated the hook are approved along with ordinary reads and runs;
# that every bypass the audit found is refused — variable expansion, `--flag=value`
# paths, attached and combined short flags, sed's `w`, `git branch` mutation,
# exec-through flags, brace expansion, `|&`, relative paths and globs through
# symlinks, symlink-following recursion, redirects, a NUL byte; that single-quoted
# shell characters are literal while double-quoted ones are not; that a worktree
# session cannot reach the main repo; and that a payload without cwd, with cwd outside
# the root, for another tool, or without CLAUDE_PROJECT_DIR approves nothing. The
# home directory and /etc/hosts appear only as symlink targets and in command text —
# nothing is read from either. No model, no network.

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


def decide(payload, root=ROOT, env_root=True):
    env = {k: v for k, v in os.environ.items() if k != "CLAUDE_PROJECT_DIR"}
    if env_root:
        env["CLAUDE_PROJECT_DIR"] = root
    p = subprocess.run([HOOK], input=json.dumps(payload), capture_output=True, text=True, env=env)
    if p.returncode != 0:
        return "ERR"
    return "ALLOW" if '"allow"' in p.stdout else "prompt"


def run(cmd, cwd=ROOT, root=ROOT):
    return decide({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}}, root)


ALLOW = [
    f"cd {WT} && .venv/bin/python -m pytest tests/test_acceptance_issue.py -q 2>&1 | tail -30",
    f"cd {WT}/frontend && npx playwright test tests/x.spec.ts --reporter=line 2>&1 | tail -45",
    f"cd {WT}/frontend; ls src/*.css src/styles 2>/dev/null",
    f"cd {WT}/frontend; sed -n 40,120p tests/x.spec.ts",
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
    f"cd {ROOT}/src && cat a.py", f"cd {ROOT}/dir && cat inner.txt",
    "cat dir/inner.txt | grep x | sort | head -3", "du -sh .venv", "stat src/a.py",
    "cat src/a.py > /dev/null; ls", "ls 2> /dev/null", "ls &>/dev/null", "sort -r README.md",
    "ls src", "grep -n '=>' src", "grep -n '\\$HOME' README.md", "grep '{' src/a.py",
    "cat 'a$b'", "grep -rn 'x' src 2>&1 | head -5", "cat '$HOME'/x",
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
    "git branch -D main", "git branch new-branch", "git branch -m a b",
    "git branch --set-upstream-to=x", "git worktree remove wt", "git worktree add /tmp/x",
    "git -c core.pager='sh -c id' log", "git --git-dir=/tmp/x log", "git stash",
    "git checkout -- .", "git reset --hard",
    "rg --pre 'sh -c id' x src", "rg --pre=cat x src", "sort --compress-program=sh README.md",
    "find . -exec rm {} \\;", "find . -delete", "find . -name x -execdir sh -c id \\;",
    "file -C -m magic",
    "cat {/etc/passwd,}", f"cat {{{HOME}/.ssh/id_rsa,README.md}}",
    "ls |& sh", "ls | sh", "ls ; sh", "(cd /etc && cat passwd)", "ls >& out", "ls ;; ls",
    "cat link-home/.zshrc", "cat dir/esc", "head dir/*", "cat link-home/*",
    f"cd {ROOT}/dir && cat esc", "wc -l link-home/.zshrc", "grep x dir/esc",
    "grep -R secret .", "grep -rS secret .", "find . -L -name id_rsa", "find -L . -name x",
    "rg -L secret .", "rg --follow secret .",
    "tree -o out.txt", "uniq README.md out", "npm run dev", "npm run anything",
    "npx playwright install", "npx playwright codegen", "npx cowsay hi", "npx playwright",
    "npm run",
    "ls > /dev/nullx", "cat README.md > out.txt", "cat < README.md", "ls >> log", "ls 2>err",
    "cat README.md >/tmp/x", "cat > x <<'EOF'",
    f"cd {HOME}/.ssh && ls", f"cat {HOME}/.ssh/id_rsa", "rm -rf src",
    ".venv/bin/python -c 'print(1)'", ".venv/bin/python script.py", "python -m http.server",
    "ls $(cat /etc/passwd)", "ls `id`", "cd .worktrees/wt && ls", "cd && ls", "cd - && ls",
    "curl https://example.com", f"cd {ROOT}/../other && ls", f"cd {os.path.dirname(ROOT)} && ls",
    f"cd {ROOT} && {HOME}/evil/python -m pytest", "/bin/ls /etc", "cat /etc/passwd",
    "ls ~", "ls ~/", "env", "FOO=1 ls", "eval ls", "exec ls", "sh -c ls", "bash", "xargs cat",
    "sudo ls", "ls\nrm -rf /", "ls\r", "echo hi > f", "printf x > f", "tee f",
    "cat -- /etc/passwd", "ls " + NUL,
    f"cd {ROOT}/src && cd /etc && ls", f"cd {ROOT}/src || cd /etc; ls",
    f"cd {ROOT}/link-home && ls",
    "cat 'a'$HOME", "cat \"'$HOME'\"", "cat 'x", 'ls "$(id)"', "ls $'\\x41'", "ls ~user",
    "cat \\\\$HOME", "ls '>' out", "grep '/usr/lib' src",
]

WT_CASES = [(f"cat {ROOT}/README.md", "prompt"), ("cat frontend/tests/x.spec.ts", "ALLOW"),
            (f"cd {ROOT} && ls", "prompt")]
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
group("worktree session stays in its tree", WT_CASES, lambda c: run(c, cwd=WT, root=WT))
group("payload without cwd, outside cwd, or other tool approves nothing", PAYLOAD_CASES,
      lambda p: decide(p))
group("no CLAUDE_PROJECT_DIR approves nothing",
      [({"tool_name": "Bash", "cwd": ROOT, "tool_input": {"command": "ls"}}, "prompt")],
      lambda p: decide(p, env_root=False))
sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "allow-repo-commands: all checks passed"; else echo "allow-repo-commands: FAILED"; fi
exit "$rc"
