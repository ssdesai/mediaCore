#!/usr/bin/env bash
set -uo pipefail

# Self-test for hooks/allow-repo-commands.sh, the PreToolUse hook that auto-approves
# read/test Bash commands confined to the project root (hooks/README.md), denies any
# command that chains a `cd`/`pushd` with something else with a reason naming the fix,
# denies any git command that moves a ref or rewrites history with a reason naming
# LIFECYCLE.md rule 2, denies an assignment at command position whose own `$NAME` is used
# later on the same line with a reason saying to inline the literal, denies a command its
# own analysis cannot read — a heredoc into an interpreter, code as a string, a pipe into
# an interpreter, a program decided at run time, a `$(…)` inside a path, a one-line
# compound — with a reason naming the rewrite, denies a line that does not tokenize at all
# with a reason naming the quote, and expands simple brace lists before
# checking each word. The escalation counter, the headless fall-through and the
# AGENTTOOLING_SCRATCH entry point are self/tests/hook-escalation.sh's; this file asserts
# the decision on one command at a time. Run by
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
# `-c k=v`, `git worktree move|lock|unlock|repair` and `git branch --delete|--move`
# included — while the read-only forms (`git branch --list <pattern>` among them) and the
# heredoc/`#`/quoted guards are
# not; that each REWRITABLE shape is denied with a reason naming the member and the
# rewrite — a `$NAME` the shell expands, a `~`, a brace group the expansion refuses, a
# `..` component in a path token, a lone relative or bare `cd`, a line break outside a
# quote or a heredoc, and a sequence mixing approved members with one the hook can only ask about —
# while the ASK class prints nothing (`git diff main...HEAD`, `X=1 make`, `echo x > f`, a
# pipeline, an all-ASK sequence), and the replay fixture's commands each get the verdict
# the design claims; that a read-only git subcommand behind the global LOCATION options (`-C`,
# `--git-dir`, `--work-tree`) is approved when each such value is confined to the root and
# prompts outside it, while `-c` and `--exec-path` keep prompting and a mutating
# subcommand behind any of them is still denied; that every opaque shape is denied with a
# reason naming the rewrite while the four
# exemptions (a heredoc feeding `cat`, `x=$(cd dir && pwd)`, a whole-argument `$(…)`, a
# plain `cat <<EOF`) are not, and that a `$`, a backtick or a `<` INSIDE SINGLE QUOTES is
# a literal rather than a substitution; that a line that does not tokenize — the seventh opaque
# shape — is denied with a reason naming the quote, while the same line behind a heredoc
# or a `#` still prompts; that the second round of the audit is closed — an
# assignment word read as the program, an attached-value flag path, `ls -L`/`du -L`
# through a symlink out, rg's and git's exec-through flags, `ruff --fix` and
# `ruff format` rewriting the tree, `mypy --install-types`; that simple brace lists are
# approved when every expansion passes and refused
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
python3 - "$AT/hooks/allow-repo-commands.sh" "$TMP" \
  "$AT/self/tests/fixtures/hook-replay-2026-09-18.json" <<'PY'
import json, os, subprocess, sys

HOOK, TMP, REPLAY_FIXTURE = sys.argv[1], sys.argv[2], sys.argv[3]
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
for f in ["plans/gate.sh", "self/gate.sh", "gate.sh", "check-plans.sh",
          "agentTooling/check-plans.sh",
          "agentTooling/feature-start.sh", "agentTooling/feature-close.sh",
          "agentTooling/stamp-timing.sh",
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
    return {"deny": "DENY", "allow": "ALLOW", "ask": "ASK"}.get(decision, "ERR")


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


# The git deny's reason must send the reader to the rule and to BOTH ends of the
# sanctioned route: feature-start.sh is the way in (branch and worktree, from the primary)
# and feature-close.sh the way out (from the feature's worktree, on its branch, before the
# merge). self/DESIGN-2026-09-17-policy-module.md §6.
GIT_REASON_WORDS = ("LIFECYCLE", "rule 2", "feature-start.sh", "feature-close.sh")
# The opaque deny's reason must name all three ways out, so a model that cannot use one
# can reach for another
OPAQUE_REASON_WORDS = ("scratchpad", "Write", "by name", "Read", "Grep", "inline")
# The seventh shape's reason names what is unreadable about the line, since "write a
# script instead" is not the fix for a quote that was never closed
UNREADABLE_REASON_WORDS = ("quote", "tokenize")


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
    # The second audit's guards: each is one keystroke from a case below and must stay
    # approved, or the closure was a widening of the prompt rather than a narrowing of
    # the approval. `-d recurse` is `-r`, which does not follow symlinks (`-R` does and
    # is forbidden); `find -H` follows only a command-line symlink, and every argument
    # is path-checked; `--format` only formats; `ruff format` reporting does not rewrite.
    "grep -d recurse x src", "grep --directories=recurse x src",
    "find . -H -name '*.py'", "find . -P -name '*.py'",
    "git log --format=%x41", "git log --pretty=format:%H",
    "ls -- src", "cat [R]EADME.md", "du -sh .venv/bin",
    "ruff format --check src", "ruff format --diff src",
    ".venv/bin/ruff format --check src", "python -m ruff check src",
]

# The harness's own entry points (hooks/README.md → What is approved silently). Matched by
# basename, so both spellings of the same script pass, and only when the path resolves
# inside the root.
ENTRY_ALLOW = [
    "plans/gate.sh", "./plans/gate.sh", "plans/gate.sh 08", "self/gate.sh", "./self/gate.sh",
    "self/gate.sh 12", f"{ROOT}/self/gate.sh",
    # The approved twin of the bare `gate.sh` in ENTRY_PROMPT: the same root file, with
    # the directory component the bare form lacks
    "./gate.sh", "./gate.sh 08",
    "./check-plans.sh --self a-slug",
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
    "python3 -m pdb analysis/report.py",
    "agentTooling/feature-start.sh a-slug", "agentTooling/feature-close.sh --self a-slug",
    "agentTooling/stamp-timing.sh --self a-slug checkpoint",
    "bash self/gate.sh", "bash -x self/gate.sh", "bash -n",
    "shellcheck", "shellcheck -x self/gate.sh", "plans/gate.sh 08 extra",
    # A BARE entry-point name carries no directory component, so bash resolves it along
    # $PATH while the hook would be judging a file it found in the repo — a different
    # program with the same name. Both spellings prompt; `./check-plans.sh` above does
    # not (self/BACKLOG.md, raised by the permissions-policy-inherit review).
    "check-plans.sh --self a-slug", "check-plans.sh", "gate.sh", "gate.sh 08",
]

# ── The opaque shape (hooks/README.md → "The opaque shape") ──────────────────
# A command the analysis cannot read is denied with the rewrite as its reason, instead
# of falling through to a prompt that teaches the model nothing. Six shapes, each of
# which hides code from any reader of the command line. Every payload in this file
# carries no `session_id`, so no escalation state is ever written and every one of these
# is a plain DENY — the counter and the `ask` are hook-escalation.sh's.
OPAQUE_DENY = [
    # a heredoc feeding anything but `cat`
    "python3 - <<'EOF'\nprint(1)\nEOF", "python3 - <<EOF\nprint(1)\nEOF",
    "bash <<EOF\nls\nEOF", "sh <<'EOF'\nid\nEOF",
    "python3 <<< 'print(1)'",
    # a heredoc feeding `cat` does not excuse the rest of the first line: the pipe and
    # the code-string checks still run over the text before the first line break, so a
    # `cat` heredoc cannot smuggle an interpreter onto the same line (the body lines are
    # after that break and stay unjudged)
    "cat <<'EOF' | python3\nprint(1)\nEOF",
    "bash -c \"$(cat <<'EOF'\nid\nEOF\n)\"",
    # code as a string, including behind xargs and find -exec
    "python3 -c 'print(1)'", "python3 -B -c 'print(1)'", ".venv/bin/python -c 'print(1)'",
    "bash -c 'ls'", "sh -c ls", "sh -lc 'id'", "zsh -c 'ls'",
    "node -e 'console.log(1)'", "perl -e 'print 1'", "perl -ne 'print' README.md",
    "ruby -e 'puts 1'", "eval ls", "eval 'ls src'",
    "xargs sh -c 'id'", "xargs -I{} sh -c 'echo {}'",
    "find . -name x -exec sh -c 'id' \\;", "find . -name x -execdir sh -c id \\;",
    # a pipe into an interpreter with no script file
    "ls | sh", "ls |& sh", "cat src/a.py | python3", "cat src/a.py | bash",
    "grep -rn x src | python3",
    # a program decided at run time
    "$CMD ls", "${CMD} ls", "$(which ls) src", "`which ls` src",
    # a `$(…)` inside a word that is a path
    f"ls $(cd {ROOT} && pwd)/src", "ls $(cat f)/src", "cat `pwd`/README.md",
    "cat \"$(pwd)/README.md\"",
    # ...and the same two shapes with the substitution OUTSIDE single quotes, which is
    # the half of the quote-awareness rule that must not move: a backtick or a `$(` the
    # shell will really act on is still a path or a program nothing here can name
    # (self/DESIGN-2026-09-18-minutes-slug-and-quoting.md §5a).
    "sed -n 5p `pwd`/README.md", "cat $(pwd)/src/a.py",
    # a one-line compound
    "for f in src/*; do cat $f; done", "while read l; do echo $l; done",
    "if true; then ls; fi", "until false; do ls; done", "case x in y) ls;; esac",
]
# The exemptions, and the shapes that only look opaque. A heredoc feeding `cat` is a
# literal string — the shape Claude Code itself uses for a commit message — and a
# `$(…)` that is a whole argument decides a value, not a path or a program.
OPAQUE_NOT_DENIED = [
    ("cat <<'EOF'\nhello\nEOF", "prompt"), ("cat <<EOF\nhello\nEOF", "prompt"),
    ("cat > x <<'EOF'\nhello\nEOF", "prompt"),
    ("git commit -m \"$(cat <<'EOF'\nthe message\nEOF\n)\"", "prompt"),
    (f"x=$(cd {ROOT} && pwd)", "prompt"),
    ('AT="$(cd "$(dirname "$0")/.." && pwd)"', "prompt"),
    ("echo $(pwd)", "prompt"), (f"echo $(echo $(cd {ROOT} && pwd))", "prompt"),
    ("ls $(cat /etc/passwd)", "prompt"), ("ls `id`", "prompt"),
    # readable commands the analysis refuses for what they DO, not for being unreadable
    ("rm -rf src", "prompt"), ("curl https://example.com", "prompt"),
    ("cat /etc/passwd", "prompt"), ("bash", "prompt"), ("xargs cat", "prompt"),
    ("exec ls", "prompt"), ("bash -n self/gate.sh", "ALLOW"),
    ("bash self/gate.sh", "prompt"), ("python3 -m pdb analysis/report.py", "prompt"),
    # the interpreter named in a flag VALUE is an argument, not a command position
    ("rg --pre 'sh -c id' x src", "prompt"), ("git -c core.pager='sh -c id' log", "prompt"),
    ("sort --compress-program=sh README.md", "prompt"),
    # a SCRIPT's own `-c`/`-e` flag is the script's business: the code-flag scan stops at
    # the first word that is not a flag, so `python3 tool.py -c config.yaml` is readable
    ("python3 src/a.py -c conf.yaml", "prompt"), ("bash self/gate.sh -c x", "prompt"),
    ("grep -n 'python3 -c' src", "ALLOW"), ("echo python3 -c foo", "ALLOW"),
    ("grep -n 'for f in x' src", "ALLOW"), ("find . -name for", "ALLOW"),
    # a quoted `<<` is not a heredoc; it lexes as a punctuation token, which the
    # approval analysis refuses for its own reasons — a prompt, never a deny
    ("grep -n '<<' src/a.py", "prompt"),
    # ── A literal in single quotes is a literal (design 2026-09-18 §5a) ───────
    # The opaque scan stripped a word's outer quotes before asking whether it held a
    # substitution, so a backtick inside single quotes read as one. A `sed` range over
    # fenced code — the shape that reads a JSON block out of a markdown file — was
    # therefore DENIED for "a program or a path decided at run time" when its file sat
    # outside the root, while the same line with a file inside it was approved by the
    # read-only rule one branch earlier. A literal is not a rewrite anybody can make:
    # the human should have been asked.
    (f"sed -n '/```json/,/```/p' {OUTSIDE}/x.md", "prompt"),
    (f"sed -n '/```/,/```/p' {OUTSIDE}/notes.md", "prompt"),
    ("grep 'a`b' README.md", "ALLOW"), ("sed -n '/```json/,/```/p' README.md", "ALLOW"),
    ("grep -n '$(pwd)' src", "ALLOW"), ("grep -rn 'x/`y`/z' src", "ALLOW"),
]

# ── The seventh shape: a line that does not tokenize ─────────────────────────
# "Unreadable" is the category's whole point, and a line whose quote was never closed is
# the plainest case of it: no reader here can say what it runs, so it used to print
# nothing and cost the human a prompt. It is denied now, with a reason naming the quote
# rather than the scratchpad rewrite — closing the quote is the fix
# (self/DESIGN-2026-09-17-policy-module.md §4). Each of these sat in a NOT_DENIED list
# before this feature; the READABLE cases in those lists are untouched.
UNREADABLE_DENY = [
    "cat 'x", "git rebase 'main", "cd 'x && ls", "X='/p; cat $X",
    'echo "unterminated', "ls 'src", "grep -n 'x src",
]
# The two guards the other denies keep hold here too: a heredoc's body and a `#`
# comment are text, not a command line, so a quote inside either is nobody's business —
# `cat <<'EOF' … don't … EOF` is a file being written, not a command that will not parse.
UNREADABLE_NOT_DENIED = [
    ("cat <<'EOF'\ndon't\nEOF", "prompt"), ("cat <<EOF\nit's fine\nEOF", "prompt"),
    ("ls src # don't", "prompt"), ("cat a#<<EOF\ncat 'x\nEOF", "prompt"),
    ("ls src", "ALLOW"), ("cat 'a$b'", "ALLOW"),
]

PROMPT = [
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
    "find . -exec rm {} \\;", "find . -delete",
    "file -C -m magic",
    "ls >& out", "ls ;; ls",
    # ── The second audit, closed ────────────────────────────────────────────
    # An assignment at command position was read as the PROGRAM: program_name() took
    # its basename, so `X=…/pytest` made the hook read the next word as an argument
    # while bash reads it as the command. `X=/tmp/e/pytest src/a.py` executed src/a.py.
    "X=/tmp/e/pytest src/a.py", "X=/tmp/e/pytest tests", "X=/tmp/e/ruff check src",
    "X=/tmp/e/python3 -m pytest tests", "X=/tmp/e/mypy src",
    # An attached-value flag carried a path nothing checked: value_confined() returns
    # True for anything starting with `-`, so `grep -f<file>` read outside the tree.
    f"grep -f{HOME}/.zshrc src", "grep -f/etc/hosts src", "rg -f/etc/hosts src",
    "file -m/etc/hosts README.md", "sort -T/tmp README.md",
    # -L follows a symlink out of the tree, for two readers that had no letter list.
    # `ls -RL .` lists, and `du -L .` sizes, every file under whatever link-home points at.
    "ls -L src", "ls -RL .", "ls -LR .", "du -L .", "du -Lsh .", "du --dereference .",
    "du -H .", "du --dereference-args .",
    # rg runs an external program for both of these: a hostname binary, and the
    # decompressor --search-zip picks off PATH.
    "rg --hostname-bin=id x src", "rg --hostname-bin id x src", "rg -z x src",
    "rg --search-zip x src",
    # git runs whatever the repo's own config names for these two.
    "git show --textconv HEAD:README.md", "git diff --ext-diff",
    "git blame --textconv src/a.py", "git log --ext-diff",
    # A runner that writes: ruff --fix and a bare `ruff format` rewrite the tree, and
    # mypy --install-types installs packages. "Repo code runs" does not cover them.
    "ruff check --fix src", "ruff check --fix-only src", "ruff check --unsafe-fixes src",
    "ruff format src", ".venv/bin/ruff check --fix src", "python -m ruff check --fix src",
    "python3 -m ruff format src",
    "mypy --install-types", "python3 -m mypy --install-types src",
    # --force is what makes a capture overwrite a frozen cost record; it belongs with
    # the other writing flags whatever else is on the line.
    "python3 analysis/capture_planning.py --list-sessions --force",
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
    ".venv/bin/python script.py", "python -m http.server",
    "ls $(cat /etc/passwd)", "ls `id`",
    "curl https://example.com", "/bin/ls /etc", "cat /etc/passwd",
    "env", "FOO=1 ls", "exec ls", "bash", "xargs cat",
    "sudo ls", "ls\r", "echo hi > f", "printf x > f", "tee f",
    "cat -- /etc/passwd", "ls " + NUL,
    'ls "$(id)"', "ls $'\\x41'",
    "ls '>' out", "grep '/usr/lib' src",
    "ls x#; rm -rf src", "cat README.md#;cat /etc/passwd", "ls src #x\nrm -rf src",
    f"cd {HOME}/.ssh",
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
    (f"x=$(cd {ROOT} && pwd)", "prompt"),
    ("echo $(pwd) cd", "prompt"),
    (f"echo $(echo $(cd {ROOT} && pwd))", "prompt"),
    (f"cd {ROOT}/src", "ALLOW"), (f"cd {ROOT}/src;", "ALLOW"), (f"cd {ROOT} 2>&1", "ALLOW"),
    ("echo cd && ls", "ALLOW"), ("ls && echo cd", "ALLOW"), ("grep -rn 'cd ' src", "ALLOW"),
    ("grep -n 'cd x && ls' src", "ALLOW"), ("find . -name cd", "ALLOW"),
    ('git commit -m "cd x && ls"', "prompt"), ("cat <<'EOF'\ncd x\nEOF", "prompt"),
    ('AT="$(cd "$(dirname "$0")/.." && pwd)"', "prompt"),
    ("cat a#<<EOF\ncd x\nls\nEOF", "prompt"),
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
    # The four worktree subcommands `permissions.deny` used to miss, beside the `list`
    # twin below: the hook denied them all along, and hooks/policy.py now renders a
    # prefix rule for each (self/tests/policy-table.sh is the twin's own assertion).
    "git worktree move wt /tmp/x", "git worktree lock wt", "git worktree unlock wt",
    "git worktree repair", "git worktree lock --reason busy wt",
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
    ("git worktree list --porcelain", "ALLOW"),
    ("git branch -a", "ALLOW"), ("git branch -v --list", "ALLOW"),
    ("git branch --merged main", "prompt"), ("git branch --contains HEAD", "prompt"),
    # After `--list`/`-l` a positional is a PATTERN to filter by, not a name to create.
    # It prompts rather than being approved: the approval side takes a positional to
    # `git branch` as a name whatever the flags say, which is the conservative half of
    # the same reading (self/BACKLOG.md, raised by the permissions-policy-inherit review).
    ("git branch --list 'feat*'", "prompt"), ("git branch -l 'feat*'", "prompt"),
    ("git branch --list --all 'feat*'", "prompt"),
    ("git push", "prompt"), ("git push origin main", "prompt"),
    ("git checkout -- README.md", "prompt"), ("git reset README.md", "prompt"),
    ("git commit -m 'git push --force'", "prompt"), ("git switch main", "prompt"),
    ("git worktree", "prompt"), ("git log --oneline -5", "ALLOW"),
    ("echo 'git rebase'", "ALLOW"), ("echo 'git clean -fd'", "ALLOW"),
    ("grep -rn 'git worktree add' src", "ALLOW"), ("ls src # git rebase main", "ALLOW"),
    ("cat <<'EOF'\ngit push --force\nEOF", "prompt"),
    ("cat a#<<EOF\ngit stash\nEOF", "prompt"),
    ("cat <<'EOF'\ngit rebase 'main\nEOF", "prompt"),
    # The deny expands no braces, so a braced word is a word it cannot read: it prompts
    # here and the approval analysis, which does expand, refuses it (BRACE_PROMPT).
    ("git branch {-a,new}", "prompt"), ("git worktree {add,list} x", "prompt"),
]

# ── git's global options, on BOTH sides (design 2026-09-18 §5b) ──────────────
# The deny side skipped `-C <value>` and its siblings before judging the subcommand; the
# approval side did not, so `-C` read as the subcommand, matched no read-only name, and
# `git -C <a path inside the root> status` prompted every time — the single commonest
# read a coordinator makes across its own worktrees. The approval side now skips the
# options that name a LOCATION and judges the subcommand behind them, each such value
# confined to the project root like any other path.
#
# `-c`, `--config-env`, `--exec-path` and `--namespace` are deliberately NOT among them:
# `-c` sets arbitrary config (`git -c core.pager='sh -c id' log` runs `sh`), `--exec-path`
# moves where git finds its own binaries, and `--namespace` names a ref namespace rather
# than a path. All four keep prompting — unlisted means prompt, which is the safe default.
#
# Nothing else in front of the subcommand is skipped either, and a bare flag is not
# exempt for taking no value: `--paginate`/`-p` forces the pager named by config even
# when stdout is not a tty.
GIT_GLOBAL_OPTION_CASES = [
    (f"git -C {ROOT} status", "ALLOW"), (f"git -C {ROOT}/src log --oneline -5", "ALLOW"),
    (f"git -C {ROOT} worktree list", "ALLOW"), (f"git -C {ROOT} branch -a", "ALLOW"),
    (f"git --git-dir={ROOT}/.git log", "ALLOW"), (f"git --git-dir {ROOT}/.git log", "ALLOW"),
    (f"git --work-tree={ROOT} status", "ALLOW"),
    # Outside the root, the value is a path this analysis refuses: a prompt, not an
    # approval, and not a deny either — reading another checkout is the human's call.
    ("git -C /tmp status", "prompt"), (f"git -C {HOME} log", "prompt"),
    ("git --git-dir=/tmp/x log", "prompt"),
    # The options whose value is not a location stay unskippable, in either order.
    ("git -c core.pager='sh -c id' log", "prompt"),
    (f"git -c user.name=x -C {ROOT} log", "prompt"),
    (f"git -C {ROOT} -c core.pager=x log", "prompt"),
    (f"git --exec-path={ROOT} log", "prompt"), ("git --namespace=x log", "prompt"),
    # A bare flag in front of the subcommand is not skipped either. `--paginate` runs
    # the pager config names even with stdout off a tty, so "takes no value" is not the
    # same as "harmless"; `--no-pager` prompts as the accepted cost of a listing rule.
    ("git --paginate log", "prompt"), (f"git -p -C {ROOT} log", "prompt"),
    (f"git --no-pager -C {ROOT} log", "prompt"),
    # A location option with no value, or whose value is the next flag, names no
    # location — and a reader that guessed at one would be guessing where this runs.
    ("git -C", "prompt"), ("git -C --git-dir status", "prompt"),
    # Every repetition is confined, by the token_confined pass that runs before the
    # strip: the second value is outside the root, whatever the first one was.
    (f"git -C {ROOT} -C /tmp status", "prompt"),
    # Finding the subcommand does not exempt what follows it: the forbidden-flag list
    # still applies, and --ext-diff runs whatever the repo's own config names.
    (f"git -C {ROOT} diff --ext-diff", "prompt"),
    # Finding the subcommand is not approving it: a mutating one behind the same options
    # is denied exactly as it was.
    (f"git -C {ROOT} branch new", "DENY"), (f"git -C {ROOT} worktree add x", "DENY"),
    (f"git -C {ROOT} branch -D main", "DENY"), (f"git --git-dir={ROOT}/.git stash", "DENY"),
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
    ("FOO=1 ls", "prompt"),
    ("echo '$X'", "ALLOW"), ("grep -n '\\$X' src", "ALLOW"),
    ("echo $(pwd)", "prompt"),
    ("cat <<'EOF'\nX=/p; cat $X\nEOF", "prompt"),
    ("cat a#<<EOF\nX=/p; cat $X\nEOF", "prompt"),
    ("ls src # X=/p; cat $X", "prompt"),
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
    # A comma-less group and a sequence expression are braces bash itself leaves alone,
    # so there is nothing to expand and nothing to rewrite: they keep prompting.
    "cat {src/a.py}", "cat {a..c}", "find . -exec rm {} \\;",
    # A brace a quote encloses is a literal bash never expands, so there is nothing to
    # expand and nothing to rewrite either: they keep prompting too (round 1 of this
    # feature's review, escalations/01-review-opus.md #2; NOTES.md ruling 13).
    'ls "{src,/etc}"', 'jq -r ".[] | {name}" data.json', 'git show "stash@{0}"',
]

# ── The rewritable shapes (design 2026-09-18 §1, the table) ──────────────────
# The analysis could not read these, and each has a rewrite worth naming, so each is
# DENIED with a reason carrying the member as written and the fix — where before every
# one of them printed nothing, cost the human an approval and taught the model nothing.
# Each case below sat in a prompting list before this feature; NOTES.md lists the moves.
# ALLOW is untouched: the approval analysis answers first and unchanged, and this layer
# is only ever reached once it has declined, so it can turn a prompt into a deny and
# never a prompt into an approval.
VAR_REWRITE = [
    "grep x $FILE", "cat $HOME/f", "cat $HOME/.ssh/id_rsa", 'cat "$HOME/.zshrc"',
    'ls "$HOME/f"', "ls ${PWD}/src", "ls ${PWD}/../", "cat 'a'$HOME",
    "cat \"'$HOME'\"", "cat \\\\$HOME", "X=/p; cat $Y/f", "cat {src,$HOME}",
]
VAR_REWRITE_WORDS = ("Inline the literal",)
TILDE_REWRITE = ["ls ~/x", "ls ~", "ls ~/", "ls ~user", "cat ~/.zshrc"]
TILDE_REWRITE_WORDS = ("absolute path",)
# Only the groups the expansion REFUSES: a quote or a backslash mixed into an UNQUOTED
# braced word, nesting, or past MAX_BRACE_WORDS. A comma-less `{a}`, `{a..c}` and find's
# `{}` are braces bash leaves alone, and a brace a quote encloses is a literal bash never
# expands — both keep prompting, in BRACE_PROMPT above.
BRACE_REWRITE = [
    "cat {a,{b,c}}", "cat {a,{/etc/passwd,b}}",
    "cat {'/etc/passwd',x}", "cat \\{src,/etc/passwd\\}",
    "cat {1,2,3,4,5,6,7,8}{1,2,3,4,5,6,7,8}{1,2,3,4,5,6,7,8}",
    # A quoted brace beside an unquoted group: "every brace is inside a quote" is the
    # test, not "some brace is", so the bare `{b,c}` still refuses the whole word.
    'cat "{a}"{b,c}',
]
BRACE_REWRITE_WORDS = ("Expand it yourself",)
# A `..` COMPONENT of a path token, which is the rule the raw `".." in command` refusal
# is judged by now: `main...HEAD` carries no such component and is an ASK below.
PARENT_REWRITE = [
    "cat ../x", 'cat "../x"', "ls a/../b", "python3 ../report.py", "../plans/gate.sh",
    f"cd {ROOT}/../other", "sed -n 1,40p ../other/README.md",
]
PARENT_REWRITE_WORDS = ("from the project root",)
CHDIR_REWRITE = ["cd src", "cd", "cd -", "cd .worktrees/wt", "cd ..", "pushd src"]
CHDIR_REWRITE_WORDS = ("cd <absolute path>",)
# Two commands in one call. A CR and a NUL are not rewritable and stay ASK (PROMPT), and
# a line carrying a heredoc is judged on the heredoc alone, as every other deny here is.
LINE_BREAK_REWRITE = ["ls\nrm -rf /", "ls src\nls tests", "ls src \\\n tests",
                      # A quoted newline does not excuse an unquoted one after it: the
                      # walk resets its state at the closing quote.
                      'git commit -m "a\nb"\nls']
LINE_BREAK_REWRITE_WORDS = ("one call per line",)
# One write per Bash call (design §2): a sequence with at least one approved member and
# at least one the hook can only ask about is sent back to be run as one call each. An
# all-ASK sequence is one ASK (below), and a PIPELINE is one command and is never split.
MIXED_REWRITE = [
    "grep x f && git commit -m m", "ls ; sh", "X=/p; ls src",
    f"x=$(cd {ROOT}; pwd) && ls", "echo x > cd && ls",
    "grep -n x README.md && rm -rf src",
    "git status && git log --oneline -5 && rm -rf src",
]
MIXED_REWRITE_WORDS = ("approved", "run alone")

# ── The ASK class: read, and not vouched for (design §1, §5) ─────────────────
# The analysis read these and cannot say they are safe — an unknown program, a write, a
# path outside the root, an environment prefix, a whole-argument substitution, a `..`
# that is not a path component, a CR. It prints NOTHING for them, exactly as it did
# before: the settings' own allow/deny rules and then the human decide, and the command
# the human sees is one the hook has read. No `ask` decision is emitted for this class.
ASK_CASES = [
    "git diff main...HEAD", f"x=$(cd {ROOT} && pwd)", "git add x && git commit -m m",
    "./run-review.sh --self x 2>&1 | tail -25", "X=1 make", "echo x > f",
    "cat /etc/hosts", "ls\r", "ls " + NUL,
    # A newline inside a double-quoted argument is one argument, not a second command —
    # the rewrite ("one call per line") cannot be carried out, so this stays an ASK
    # rather than becoming a REWRITE (round 1 of this feature's review,
    # escalations/01-review-opus.md #1).
    'git commit -m "subject\n\nbody"', 'gh pr create --title t --body "a\n\nb"',
    "git commit -m 'subject\n\nbody'",
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
group("judges git by its subcommand behind the global location options",
      GIT_GLOBAL_OPTION_CASES, run)
group("denies an assignment whose own $NAME is used later on the line",
      [(c, "DENY") for c in ASSIGN_DENY], run)
group("does not deny an assignment nobody dereferences, or an env prefix",
      ASSIGN_NOT_DENIED, run)
group("the assignment deny says to inline the literal",
      [(c, "ok") for c in ["X=/p; cat $X/f"]],
      lambda c: deny_reason_ok(c, ASSIGN_REASON_WORDS))
group("deny names the fix", [(c, "ok") for c in [f"cd {ROOT} && ls"]], deny_reason_ok)
group("the git deny names LIFECYCLE rule 2 and both feature scripts",
      [(c, "ok") for c in ["git worktree add x", "git push --force"]],
      lambda c: deny_reason_ok(c, GIT_REASON_WORDS))
group("denies every shape the analysis cannot read",
      [(c, "DENY") for c in OPAQUE_DENY], run)
group("does not deny an exempt substitution, a cat heredoc, or a merely refused command",
      OPAQUE_NOT_DENIED, run)
group("the opaque deny names the rewrite",
      [(c, "ok") for c in ["python3 -c 'print(1)'", "python3 - <<'EOF'\nprint(1)\nEOF"]],
      lambda c: deny_reason_ok(c, OPAQUE_REASON_WORDS))

# ── The three outcomes (design 2026-09-18) ───────────────────────────────────
# Each rewritable shape is denied with its own reason, and every reason names the member
# AS WRITTEN as well as the rewrite — a reason that named only the shape would leave a
# model with several commands on one line guessing which one to fix.
for label, cases, words in (
        ("a $NAME the shell expands", VAR_REWRITE, VAR_REWRITE_WORDS),
        ("a ~", TILDE_REWRITE, TILDE_REWRITE_WORDS),
        ("a brace group the expansion refuses", BRACE_REWRITE, BRACE_REWRITE_WORDS),
        ("a .. component in a path", PARENT_REWRITE, PARENT_REWRITE_WORDS),
        ("a relative or bare cd", CHDIR_REWRITE, CHDIR_REWRITE_WORDS),
        ("a line break outside a quote or a heredoc", LINE_BREAK_REWRITE,
         LINE_BREAK_REWRITE_WORDS),
        ("a sequence mixing approved members with one to ask about",
         MIXED_REWRITE, MIXED_REWRITE_WORDS)):
    group("denies %s with the rewrite" % label, [(c, "DENY") for c in cases], run)
    group("the reason for %s names the rewrite" % label, [(c, "ok") for c in cases],
          lambda c, w=words: deny_reason_ok(c, w))
# The member's own text, for the cases the design names one by one (§5). A member is
# quoted as written, so a line with several commands says which one is being refused.
group("the reason names the member as written",
      [((c, m), "ok") for c, m in [
          ("grep x $FILE", "grep x $FILE"), ("ls ~/x", "ls ~/x"),
          ("cat {a,{b,c}}", "cat {a,{b,c}}"), ("cat ../x", "cat ../x"),
          ("cd src", "cd src"),
          ("grep x f && git commit -m m", "git commit -m m"),
          ("grep x f && git commit -m m", "grep x f")]],
      lambda cm: deny_reason_ok(cm[0], (cm[1],)))
# The mixed sequence names the approved member as approved and the other as one to run
# alone — the whole point of the rewrite is which command goes in which call.
group("the mixed sequence names the approved member and the one to run alone",
      [(c, "ok") for c in ["grep x f && git commit -m m"]],
      lambda c: deny_reason_ok(c, ("grep x f", "approved", "git commit -m m", "run alone")))
# ASK prints nothing, as it always did: no `ask` decision, no JSON, no reason.
group("the read-and-unsafe class prints nothing", [(c, "prompt") for c in ASK_CASES], run)

# The replay the design's claim rests on: every command in the fixture, with the verdict
# it says. REWRITE and the three older shape denies are both a `deny` decision to a
# caller — the fixture tells them apart, and asserts the reason each carries.
with open(REPLAY_FIXTURE) as handle:
    REPLAY = json.load(handle)["records"]
REPLAY_DECISION = {"ALLOW": "ALLOW", "REWRITE": "DENY", "DENY": "DENY", "ASK": "prompt"}
group("replays the 2026-09-18 commands with the design's verdicts",
      [(r["command"], REPLAY_DECISION[r["verdict"]]) for r in REPLAY], run)
group("every replayed deny carries its reason",
      [(r["command"], "ok") for r in REPLAY if r["reason_contains"]],
      lambda c: deny_reason_ok(c, (
          [r["reason_contains"] for r in REPLAY if r["command"] == c][0],)))
group("the replay covers at least the 24 commands the design counted",
      [(len(REPLAY) >= 24, True)], lambda n: n)

group("denies a line that does not tokenize", [(c, "DENY") for c in UNREADABLE_DENY], run)
group("does not judge an unbalanced quote inside a heredoc body or behind a #",
      UNREADABLE_NOT_DENIED, run)
group("the unreadable deny names the quote",
      [(c, "ok") for c in ["cat 'x", "git rebase 'main"]],
      lambda c: deny_reason_ok(c, UNREADABLE_REASON_WORDS))
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
