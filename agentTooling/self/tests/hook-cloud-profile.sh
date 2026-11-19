#!/usr/bin/env bash
set -uo pipefail

# Self-test for the profile half of hooks/allow-repo-commands.sh: the git deny's reason is
# chosen by profile, and under `cloud` two more shapes are refused — switching to any
# branch other than the current one, and a push whose target is not the current branch —
# both entries of hooks/policy.py's table (self/features/review-base-and-cloud-hook/).
# Run by self/gate.sh, or by hand: bash self/tests/hook-cloud-profile.sh
#
# The table below is the contract: every case with its expected LOCAL and CLOUD answer,
# each run under BOTH profiles. self/tests/allow-repo-commands.sh runs every older case
# under both profiles too, expecting identical answers.
#
# Fixtures, under mktemp -d:
#   C  a consuming repo on its assigned branch claude/feat-x, the hook vendored under
#      agentTooling/hooks/, a tracked manifest naming that branch as branches[0], an
#      origin holding main, the branch, and `remote-only` (a branch with no local twin);
#   S  agentTooling's own shape (the hook under hooks/ at the root), on claude/other, with
#      no started feature;
#   D  a repo on a detached HEAD;  N  a directory that is no repo at all;
#   M  a repo whose current branch IS `main` (round 2's resolved-target rows).
#
# Asserts:
#   T. the table — reads approved in both; `git switch main` and `git checkout main`
#      prompt locally and are refused in the cloud; a push whose destination is `main`
#      (round 2: every spelling — `-u`, `HEAD:main`, `x:main`, `+main`, `refs/heads/main`,
#      `--repo origin main`, `--repo=origin main`, `:main`, `--delete`, behind `-C`, in a
#      chain, quoted) is refused in BOTH; `git checkout -b x` refused in both;
#      `git push -u origin <current>`, plain `git push`, a file checkout and a switch to
#      the current branch prompt in both — the push also with `2>&1 | tail -3`,
#      `2>&1` or `2>/dev/null` after it (a descriptor is the redirect's, not a refspec); `mainline`, `feature/main`, `main-x` and
#      `main:x` prompt locally and are refused in the cloud as round 1 refused them; the
#      rest of the cloud-only shapes (`HEAD:x`, `--all`, `--mirror`, `--tags`, `--delete`,
#      `:x`, `--repo origin x`, a sha, `-`, `--detach`, `--orphan`, a remote-only branch,
#      `git -C <root> …`); and on M, a push whose resolved target is `main` (plain
#      `git push`, `git push origin HEAD`) prompts locally and is refused in the cloud;
#   Q5 (hook-audit-gaps). B3: the started feature's `branches[0]` is read from the manifest
#      COMMITTED at HEAD — an uncommitted edit naming the current branch does not approve
#      its push, a committed one does, and an uncommitted edit away from it does not
#      withdraw the approval; and the table also holds B2 (`git push origin <b> "2">/dev/null`
#      and `\2>/dev/null` name a second branch: refused in the cloud) and `-fu`/`-uf` (a
#      force bundled into short flags: refused in both profiles);
#   H9-H14 (hook-audit-gaps, phase 3). The build-script judge reads a script FED by input
#      redirection as a run (`bash < run-plans.sh`, `<>`, `N<`; H9), any command that is no
#      plain filter beside a reader that names one as a launcher (H10), and bracket
#      expressions, glued patterns, assignment values and abbreviated git exec flags as the
#      patterns they are (H11); `judged_text` reads comments and heredocs as bash does (H12);
#      the git deny's `brace_words` expands nested groups and sequences (H13); and, end to
#      end in a checkout whose ledger cannot be read, the fed script gets the deny the piped
#      one gets, three times over (H14). The table holds the same self-audit's git rows;
#   H15, H16, Q6 (hook-audit-gaps, round 2: both escalation files, coordinator ruling 7). The
#      build-script judge reads a line with its continuations deleted and as written, and a
#      `)#` hides nothing (H15); `judged_texts` returns every reading of a comment in doubt, a
#      continuation and a run-on body line, and refuses past its caps (H16; H8 is narrowed to
#      the main parser); a replace ref over the committed manifest approves no push (Q6). The
#      table holds the same shapes end to end, with the cost rows;
#   Q7 (own-push-real-gitdir). The own-branch push trusts no git directory the tree plants. The
#      audit's evil2 (plain files under plans/evil2 read as a bare gitdir whose core.worktree
#      names the root and whose remote.origin.push targets `main`) and evil3 (the same with an
#      ssh:// origin and core.sshCommand) are planted, and `git -C plans/evil2 push …`, the
#      absolute `-C`, `-u`, `--set-upstream`, a cwd inside the plant, GIT_DIR in the hook's
#      environment, `--git-dir` and a `GIT_DIR=` prefix are all prompts. The approved shape is
#      `git push [-u | --set-upstream] origin <B>` with nothing before `push`, from the root
#      (every `-C`, `--git-dir`, `--work-tree`, `-c`, env prefix and a subdirectory cwd prompts);
#      the root checkout's own git directory, found by walking the filesystem, is the one git
#      reports (a core.worktree elsewhere, core.bare=true and a bare-repo shape planted in a
#      vendored root prompt; a linked worktree and a root that is a subdirectory approve); and
#      the effective config holds no key that redirects or executes (one row per key),
#      `push.default` is absent, `simple` or `current`, `remote.origin.url` is one http(s)
#      value no insteadOf/pushInsteadOf rewrites (the container's own non-applying insteadOf
#      approves), and no pre-push or reference-transaction hook exists. Each mutation is
#      undone after its row; the table's `-C <root>` rows are prompts now;
#   Q8 (own-push-credential-keys). The own-branch push prompts when the effective config holds
#      `credential.helper` (the audit's `!f() { touch …; … }; f` form), a `credential.<sub>.helper`
#      (url-scoped, and a mixed-case subsection), `core.askPass` (camel case at `git config`), or
#      a helper in the global config only, or an empty subsection written as raw text
#      (`[credential ""]` helper in the repo and the global config, `[includeIf ""]`, `[hook ""]`,
#      `[branch ""]`); and when GIT_ASKPASS or SSH_ASKPASS is non-empty in the
#      hook's environment. An empty GIT_ASKPASS or SSH_ASKPASS, `credential.interactive=false`
#      and `credential.<sub>.username` still approve. Each mutation is undone after its row.
#      hook_env gives the hook no inherited askpass and no system or global git config;
#   H17 (hook-audit-gaps, round 3: escalations/02-review-opus.md, 02-audit-opus.md R2-1 to
#      R2-3). The walk reads no construct bash has joined across a line continuation as two
#      pieces: an unquoted delimiter's body ends at a terminator joined across one
#      (`heredoc_body_span`'s `joins`), a split operator, delimiter, substitution opener and
#      whole-argument head are the ones bash reads, and the own-assignment deny looks for
#      the use in every reading. The table and H14 hold the same shapes end to end, with the
#      quoted-delimiter twins bash joins nothing in;
#   H18 (hook-audit-gaps, round 4: escalations/03-audit-opus.md, R3-1 and R3-2). A reading the
#      walk BUILT whose quotes never close is a TornReading, never dropped quietly:
#      `judged_texts` judges a line that names git as a git command that cannot be read, and
#      `does_not_tokenize` denies any other; a dropped `$$`, a comment in doubt kept as text
#      and bodies read as commands are no built reading; ruling 45's opened head is matched
#      in every spelling bash reads as it (HEREDOC_OPENED_HEAD_RE). The table holds the
#      audit's rows and controls end to end, and the usual message with quotes in its body;
#   H19 (hook-audit-gaps, round 5: escalations/04-audit-opus.md, R4-1). A whole-argument head
#      whose delimiter is no bare or fully quoted identifier (`E'O'F`, `\EOF`, `''`, `E-F`,
#      `'E O F'`) is not read for a message at all: `unread_head` is the test, in every
#      spelling of the head, and `judged_texts` notes any reading that holds one as torn — a
#      git command that cannot be read when the line names git, the tokenize deny otherwise.
#      A plain delimiter, a herestring, a head a reading dropped and the usual message under
#      each delimiter one is written with are untouched. The table holds the audit's rows
#      and controls end to end, and round 4's two documented over-denies, pinned;
#   T, round 6 (hook-audit-gaps: escalations/05-audit-opus.md, B1). A line that names git and
#      that NO reading tokenizes — a git command on line 1, a later line whose quote never
#      closes — is a git command that cannot be read, whatever `<<` or `#` it holds
#      (`judged_texts`); the same line with no git on it, and a line bash tokenizes, keep
#      the verdict they had. The table holds every reproduction and variant end to end;
#   H20 and T, round 7 (hook-audit-gaps: escalations/06-review-opus.md and 06-audit-opus.md,
#      B1). Round 6's deny asks bash itself (`bash_refuses`: `bash -n`, the text on stdin, no
#      startup file, an environment of PATH alone): a line that names git, that no reading
#      judges and that bash REFUSES is the unreadable git command, `never_judged`'s ANSI-C
#      quote or not (`git push -f origin y⏎echo $'\'' "`); a line bash parses keeps the
#      verdict round 5 gave it (`git commit -m "$(echo "it's")"`). H20: the check executes
#      nothing in the text and inherits no BASH_ENV, is made only for such a line and once
#      per line, and FAILS CLOSED — no bash, a timeout, a non-zero exit, any output, a NUL
#      all count as refused. The table holds the audit's rows and the review's three lines;
#   R7 (phase 3 (b)). `git push -u origin "$(git branch --show-current)"` is refused in the
#      cloud with a reason naming the branch to push as a literal, and that literal push is
#      approved;
#   R. the reasons — local is today's (names .worktrees/<slug>); cloud names the branch,
#      the started feature and its feature-close.sh, LIFECYCLE.md rule 2, and never
#      .worktrees/ or the primary checkout; agentTooling's own shape names
#      `./feature-start.sh --self`; a local push to `main` gets its own reason (never
#      push main, push the feature's branch, the PR feature-close.sh opens and a human
#      merges) with nothing cloud-specific in it, and the cloud's is the cloud one;
#   F. the fallbacks — a detached HEAD, a directory that is no repo, and an invalid
#      AGENTTOOLING_PROFILE all give today's answers (prompt), and the always-denied
#      shapes — a push to `main` among them — still deny; the hook never exits non-zero;
#   O. the off-branch remedy — clones of origin on `main` (OB: the manifest only on the
#      feature's branch; OM: tracked on `main` too): `git checkout`/`git switch` to the
#      feature's branch, its `origin/` spelling, `--detach origin/…` and `checkout -b … origin/…`
#      are refused with the off-branch reason (the branch, the slug, a fresh session or the
#      human), never "push only `main`"; locally they still prompt; a branch no manifest
#      names keeps the existing reason, and on the feature's own branch nothing changes;
#      on a detached HEAD (OD) a plain `git checkout <feature-branch>` that would move the
#      working tree is refused too (O7), and still prompts locally;
#   A. the cached-clone attach — clones detached EXACTLY at origin/<feature-branch> with
#      the local branch behind (AD): `checkout -B`, `switch -C`, `branch -f`, a plain
#      checkout or switch of the stale branch, any refused shape, all name
#      `./agentTooling/attach-branch.sh <branch>`; what moves nothing (`checkout
#      origin/<branch>`, `switch --detach`, a file checkout) is not refused; the local
#      branch already AT HEAD (AE) lets a plain checkout through; a local branch with a
#      commit HEAD lacks (AN), HEAD not at the tip (OD), and a tip no manifest names
#      (`remote-only`) are refused WITHOUT the attach remedy;
#   P. detection through the hook — CLAUDE_CODE_REMOTE=true with no override is cloud;
#   X. no subprocess off the cloud path — under a logging `git` stub, no case runs git
#      locally (a push to `main` included, denied from its words alone), and in the cloud
#      a read or a non-git command runs none.
#
# Every invocation pins the profile: AGENTTOOLING_PROFILE set, CLAUDE_CODE_REMOTE cleared,
# except P, which sets CLAUDE_CODE_REMOTE explicitly to test detection itself. A Claude
# Code cloud container sets CLAUDE_CODE_REMOTE=true, so an unpinned case would silently
# test the cloud. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-cloud-profile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-cloud-profile"
python3 - "$AT" "$TMP" <<'PY'
import json, os, shutil, subprocess, sys

AT, TMP = sys.argv[1], sys.argv[2]
HOOK_FILES = ("allow-repo-commands.sh", "policy.py", "env_profile.py", "shared_rules.py")
HOOK_NAME = "allow-repo-commands.sh"
BASE = "main"
BR = "claude/feat-x"
SLUG = "feat-x"
OTHER_BR = "claude/other"
REMOTE_ONLY = "remote-only"
PROFILE_ENV = "AGENTTOOLING_PROFILE"
REMOTE_ENV = "CLAUDE_CODE_REMOTE"
# The hook's git sees no inherited askpass and no system or global config (hook_env)
HOOK_ENV_DROPPED = ("GIT_ASKPASS", "SSH_ASKPASS", "GIT_EXEC_PATH", "GIT_SSH", "GIT_SSH_COMMAND",
                    "GIT_PROXY_COMMAND", "GIT_CONFIG")
HOOK_ENV_GIT_ISOLATION = {"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull}
LOCAL, CLOUD = "local", "cloud"
A, P, D = "ALLOW", "prompt", "DENY"
REAL_GIT = shutil.which("git")
GIT_LOG = os.path.join(TMP, "git-calls.log")
STUB_BIN = os.path.join(TMP, "bin")


def sh(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


def git(repo, *args):
    return subprocess.run([REAL_GIT, "-C", repo] + list(args), check=True,
                          capture_output=True, text=True).stdout.strip()


def new_repo(path):
    os.makedirs(path)
    git(path, "init", "-q")
    git(path, "symbolic-ref", "HEAD", "refs/heads/" + BASE)
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "hook cloud profile test")
    with open(os.path.join(path, "README.md"), "w") as f:
        f.write("fixture\n")


def vendor_hook(dest):
    os.makedirs(dest, exist_ok=True)
    for name in HOOK_FILES:
        shutil.copy2(os.path.join(AT, "hooks", name), os.path.join(dest, name))
    return os.path.join(dest, HOOK_NAME)


def commit_all(repo, msg):
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", msg)


# ── C: a consuming repo, on its assigned branch, with the feature started ────────
C = os.path.join(TMP, "consumer")
ORIGIN = os.path.join(TMP, "origin.git")
new_repo(C)
HOOK_C = vendor_hook(os.path.join(C, "agentTooling", "hooks"))
commit_all(C, "init")
sh(REAL_GIT, "init", "-q", "--bare", ORIGIN)
git(C, "remote", "add", "origin", ORIGIN)
git(C, "push", "-q", "origin", BASE)
git(C, "push", "-q", "origin", "HEAD:refs/heads/" + REMOTE_ONLY)
git(C, "checkout", "-q", "-b", BR)
os.makedirs(os.path.join(C, "plans", "features", SLUG))
with open(os.path.join(C, "plans", "features", SLUG, "README.md"), "w") as f:
    f.write("# %s\n\nMentions %s in prose.\n\n```json\n%s\n```\n"
            % (SLUG, OTHER_BR, json.dumps({"slug": SLUG, "base": BASE, "branches": [BR]})))
commit_all(C, SLUG + ": start")
git(C, "push", "-q", "-u", "origin", BR)
git(C, "fetch", "-q", "origin")
# The own-branch push is approved only for an http(s) origin (own-push-real-gitdir ruling 4),
# so C's origin url becomes a fixed https one now that the setup's last fetch is done. Nothing
# below fetches or pushes through C's origin: the clones (OB, OM, ...) take ORIGIN directly.
OWN_ORIGIN_URL = "https://example.invalid/consumer.git"
git(C, "remote", "set-url", "origin", OWN_ORIGIN_URL)
SHA = git(C, "rev-parse", BASE)

# ── S: agentTooling's own shape, no started feature ───────────────────────────
S = os.path.join(TMP, "self-shape")
new_repo(S)
HOOK_S = vendor_hook(os.path.join(S, "hooks"))
commit_all(S, "init")
git(S, "checkout", "-q", "-b", OTHER_BR)

# ── D: a detached HEAD;  N: no repo at all ─────────────────────────────────────
DET = os.path.join(TMP, "detached")
new_repo(DET)
commit_all(DET, "init")
git(DET, "checkout", "-q", "--detach")
NOREPO = os.path.join(TMP, "norepo")
os.makedirs(NOREPO)

# ── M: a checkout whose current branch is `main` ──────────────────────────────
ON_MAIN = os.path.join(TMP, "on-main")
new_repo(ON_MAIN)
commit_all(ON_MAIN, "init")

# ── W: the current branch is no manifest's branches[0] ──────────────────────────
# WM: a manifest exists but names another branch first (this one is only branches[1]);
# WP: the branch is only mentioned in a manifest's prose.
def unstarted_branch(path, branches, prose):
    new_repo(path)
    vendor_hook(os.path.join(path, "agentTooling", "hooks"))
    os.makedirs(os.path.join(path, "plans", "features", SLUG))
    with open(os.path.join(path, "plans", "features", SLUG, "README.md"), "w") as f:
        f.write("# %s\n\n%s\n\n```json\n%s\n```\n"
                % (SLUG, prose, json.dumps({"slug": SLUG, "base": BASE, "branches": branches})))
    commit_all(path, "init")
    git(path, "checkout", "-q", "-b", BR)


WM = os.path.join(TMP, "second-branch")
unstarted_branch(WM, [OTHER_BR, BR], "")
HOOK_WM = os.path.join(WM, "agentTooling", "hooks", HOOK_NAME)
WP = os.path.join(TMP, "prose-branch")
unstarted_branch(WP, [OTHER_BR], "Mentions %s in prose." % BR)
HOOK_WP = os.path.join(WP, "agentTooling", "hooks", HOOK_NAME)

# The logging git: every call is recorded, then handed to the real one.
os.makedirs(STUB_BIN)
with open(os.path.join(STUB_BIN, "git"), "w") as f:
    f.write('#!/usr/bin/env bash\necho "$*" >> "%s"\nexec "%s" "$@"\n' % (GIT_LOG, REAL_GIT))
os.chmod(os.path.join(STUB_BIN, "git"), 0o755)


def hook_env(root, profile=None, remote=None, stub_git=False, extra_env=None):
    # The own-push approval prompts on a credential helper in any config scope and on a
    # non-empty askpass in the environment (Q8): a developer's own (osxkeychain, `gh auth
    # setup-git`, an IDE's GIT_ASKPASS) must not turn every approve row red, so the hook
    # sees no inherited askpass and no system or global config unless a row sets one.
    env = {k: v for k, v in os.environ.items()
           if k not in (PROFILE_ENV, REMOTE_ENV, "CLAUDE_PROJECT_DIR") + HOOK_ENV_DROPPED}
    env.update(HOOK_ENV_GIT_ISOLATION)
    env.update(extra_env or {})
    env["CLAUDE_PROJECT_DIR"] = root
    env["TMPDIR"] = TMP
    if profile is not None:
        env[PROFILE_ENV] = profile
    if remote is not None:
        env[REMOTE_ENV] = remote
    if stub_git:
        env["PATH"] = STUB_BIN + os.pathsep + env.get("PATH", "")
    return env


def call(cmd, hook=HOOK_C, root=C, cwd=None, **env_kw):
    """(decision, reason): decision is ALLOW/DENY/ASK, `prompt` for no output, ERR for a
    non-zero exit or output that is not the hook protocol."""
    payload = {"tool_name": "Bash", "cwd": cwd or root, "tool_input": {"command": cmd},
               "session_id": "hook-cloud-profile"}
    p = subprocess.run([hook], input=json.dumps(payload), capture_output=True, text=True,
                       env=hook_env(root, **env_kw))
    if p.returncode != 0:
        return "ERR", p.stderr.strip()[-300:]
    if not p.stdout.strip():
        return P, ""
    try:
        out = json.loads(p.stdout)["hookSpecificOutput"]
    except (ValueError, KeyError, TypeError):
        return "ERR", p.stdout[:300]
    decision = {"allow": A, "deny": D, "ask": "ASK"}.get(out.get("permissionDecision"), "ERR")
    return decision, out.get("permissionDecisionReason", "")


fails = 0


def check(label, ok, detail=""):
    global fails
    if ok:
        print("  ok    %s" % label)
    else:
        fails += 1
        print("  FAIL  %s%s" % (label, (" — " + str(detail)[:400]) if detail else ""))


# ── H. every operator character has an operator of its own ─────────────────────
# `punctuation_pieces` reads a run of CHAIN_PUNCTUATION by longest operator; a character
# with no one-character entry could only be read by its fallback (self/features/
# orchestration-record-fixes/, round 3), so none may be missing
import importlib.machinery, importlib.util
_loader = importlib.machinery.SourceFileLoader("hook_under_test", os.path.join(AT, "hooks", HOOK_NAME))
_spec = importlib.util.spec_from_loader("hook_under_test", _loader)
_hook = importlib.util.module_from_spec(_spec)
_loader.exec_module(_hook)
_single = {op for op, _kind in _hook.PUNCTUATION_OPERATORS if len(op) == 1}
check("H1. every character of CHAIN_PUNCTUATION has a one-character operator (missing: %s)"
      % sorted(set(_hook.CHAIN_PUNCTUATION) - _single),
      set(_hook.CHAIN_PUNCTUATION) <= _single)
check("H2. a run of every operator character reads in full, with no fallback",
      "".join(op for _kind, op in _hook.punctuation_pieces(_hook.CHAIN_PUNCTUATION))
      == _hook.CHAIN_PUNCTUATION)
# H3 (round 9's audit): `command_words` stops at a heredoc's body, so the build-script judge —
# the one deny a checkout with an unreadable orchestrator ledger gives — reads a line with a
# `<<` as text, as it did on origin/main; a build script after the body is still a run
for _line in ("cat <<EOF\nx\nEOF\n./run-plans.sh --self x",
              "cat <<'EOF'\nx\nEOF\n./run-verify.sh --self x",
              "cat <<-EOF\n\tx\n\tEOF\nbash run-plans.sh --self x",
              "cat <<EOF ; true\nx\nEOF\n./run-plans.sh --self x"):
    check("H3. a build script after a heredoc's body is a run: %r" % _line,
          _hook.invokes_build_script(_line))
check("H3. a heredoc with no build script is no run",
      not _hook.invokes_build_script("cat <<EOF\nx\nEOF\nls"))
# H4 (round 10's audit): a quoted `<<` or a `<<<` is no heredoc, so the tokenized reading — which
# catches a glob — still runs, as on origin/main; after a real heredoc's body a glob is the text
# scan's, which cannot match it (a prompt, as on origin/main)
for _line in ("echo 'a<<' ; ./run-p*.sh --self x",
              "echo a'<<' ; ./run-p*.sh --self x",
              "git log --grep='<<' ; ./run-p*.sh --self x",
              "git log --grep='<<' && ./run-p*.sh --self x",
              "ls 'a<<b' ; ./run-pl?ns.sh --self x",
              "cat <<< x ; ./run-p*.sh --self x"):
    check("H4. a quoted `<<` or a herestring hides no glob of a build script: %r" % _line,
          _hook.invokes_build_script(_line))
check("H4. a glob after a real heredoc's body is not read (a prompt, as on origin/main)",
      not _hook.invokes_build_script("cat <<EOF\nx\nEOF\n./run-p*.sh --self x"))
# H6 (hook-audit-gaps, A and B; round 14's audit): a comment's quote, a line that does not lex and a
# line continuation hid a build script's glob from the judge, and a reader piped into a launcher
# hid one named by a glob. Each is a run; a comment holds no command, so a name in one is none
for _line in ("./run-p*.sh --self x # '", "./run-pl?ns.sh --self x # it's",
              "env ./run-p*.sh --self x # '", "true ; ./run-p*.sh --self x # '",
              "./run-p*.sh --self x \\", "./run-pla\\\nns.sh --self x", "./run-p*.sh \\\n--self x",
              "ls run-p*.sh | sh", "ls run-p*.sh | bash -s", "bash -c './run-p*.sh --self x'"):
    check("H6. a build script the line hides from a plain reading is a run: %r" % _line,
          _hook.invokes_build_script(_line))
for _line in ("ls # ./run-plans.sh", "ls src # it's", "git log --oneline -3 # '"):
    check("H6. a comment is no run: %r" % _line, not _hook.invokes_build_script(_line))
# H15 (round 2; escalations/01-audit-opus.md, E2 and E3). E2: bash deletes no line continuation
# inside a comment, so the line after `# x \` is a command — the judge reads the line with its
# continuations deleted AND as written, and either reading's run is a run. E3: a `#` right
# after a `)` that closed a word (`a=(x)#b`, `$(x)#b`) starts no comment, and a comment that is
# in doubt is read both ways. Each row was no run on round 1's hook and a run on origin/main's
for _line in ("ls # x \\\n./run-plans.sh", "ls #\\\n./run-plans.sh", "echo x;#a \\\n./run-plans.sh",
              "ls #a\\\n\\\n./run-plans.sh", "ls # x \\\n./run-plans.sh --self x # y",
              "ls #\\\nbash < run-plans.sh", "ls #\\\ncat run-plans.sh | unshare sh",
              "ls # \\\nbash run-plans.sh --self x", "git log -1 # note \\\n./run-p*.sh --self x",
              "ls # it's \\\n./run-pl?ns.sh", "# x \\\n./run-plans.sh",
              "a=(x)#b; ./run-plans.sh", "echo $(echo a)#b; ./run-plans.sh",
              "echo <(true)#b; bash run-plans.sh", "a=(x)#b; ./run-p*.sh # '"):
    check("H15. a build script behind a comment's backslash or a `)#` is a run: %r" % _line,
          _hook.invokes_build_script(_line))
# ... and a continuation outside a comment still joins its lines, a comment still holds no command
for _line in ("./run-pla\\\nns.sh --self x", "bash \\\nrun-plans.sh"):
    check("H15. a continuation outside a comment joins the name: %r" % _line,
          _hook.invokes_build_script(_line))
for _line in ("ls # x \\\nls", "ls \\\n# ./run-plans.sh", "ls # ./run-plans.sh \\\nls src"):
    check("H15. a comment that ends in a backslash is still no run: %r" % _line,
          not _hook.invokes_build_script(_line))
# H7 (hook-audit-gaps, C; round 14's audit): the launcher denylist is not complete, so a pattern for a
# build script in ANY argument of a non-exempt command is a run — on this path only
for _line in ("unshare ./run-p*.sh --self x", "setpriv ./run-p*.sh --self x",
              "prlimit ./run-p*.sh --self x", "awk 'BEGIN{system(\"./run-p*.sh --self x\")}'",
              "awk 'BEGIN{system(\"./run-p*.sh\")}'",
              "sed -n '1e ./run-p*.sh --self x' README.md",
              "git -c alias.z='!./run-p*.sh --self x' z", "fakeroot ./run-pla?s.sh x"):
    check("H7. a launcher the denylist does not know cannot hide a build script's glob: %r" % _line,
          _hook.invokes_build_script(_line))
# ... and what stays no run: reads, the exempt commands, a glob that is no build script's name
for _line in ("ls", "git status", "git log --oneline -3", "grep -n run-plans.sh README.md",
              "jq . */report.json", "find . -name '*.py' -exec grep -l x {} \\;",
              "wc -l tests/*.py", "python3 -B analysis/report.py --self x", "sort a.txt",
              "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\""):
    check("H7. a plain command is no run: %r" % _line, not _hook.invokes_build_script(_line))
# ... the coarse rule's documented cost: a bare glob handed to a non-exempt command could be any name
for _line in ("cp * /tmp/x", "tar -cf x.tar *.sh"):
    check("H7. the cost: a bare glob given to a non-exempt command is a run: %r" % _line,
          _hook.invokes_build_script(_line))
# H8 (hook-audit-gaps, B1): a whole-argument heredoc ends where bash ends it — at a line holding the
# delimiter alone — and `heredoc_body_span` is the one place that says where
_span = _hook.heredoc_body_span
check("H8. the terminator is a line holding the delimiter alone", _span("a\nEOF\nrest", 0, "EOF", False) == (2, 6))
check("H8. `<<-` strips leading tabs from the terminator line", _span("\ta\n\t\tEOF\nrest", 0, "EOF", True) == (3, 9))
check("H8. without `<<-` an indented delimiter is body text, and a heredoc that never ends is unplaced",
      _span("a\n\tEOF\n", 0, "EOF", False) is None)
check("H8. `EOF)` and `EOF;` are where bash 5.2 may end a `$(…)` heredoc: unplaced, never body",
      _span("a\nEOF)\nEOF\n", 0, "EOF", False) is None and _span("a\nEOF;x\nEOF\n", 0, "EOF", False) is None)
# Round 2 (escalations/01-audit-opus.md, E1) narrowed this row: `EOF ` and `EOFS` are plain body
# lines to the MAIN parser (what the caller asks for with HEREDOC_RUN_ON_IS_BODY, and what the
# row asserted); inside `$(…)` bash 5.2 ends the body at such a line when a `)` follows on it,
# so with no reading asked for the body is not placed, whatever follows the delimiter
check("H8. `EOF ` and `EOFS` are plain body lines to the main parser",
      _span("a\nEOF \nEOFS\nEOF\n", 0, "EOF", False, _hook.HEREDOC_RUN_ON_IS_BODY) == (12, 16))
for _body in ("a\nEOF \nEOF\n", "a\nEOFS\nEOF\n", "a\nEOF )\nEOF\n", "a\nEOF\t)\nEOF\n", "a\nEOFS)\nEOF\n",
              "a\nEOF x)\nEOF\n", "a\nEOFxyz ; true)\nEOF\n", "a\nEOF'q')\nEOF\n", "a\n\tEOF x)\nEOF\n"):
    check("H8. a body line that begins with the delimiter and goes on is not placed: %r" % _body,
          _span(_body, 0, "EOF", _body.startswith("a\n\t")) is None
          and _span(_body, 0, "EOF", _body.startswith("a\n\t"), _hook.HEREDOC_RUN_ON_ENDS)
          == (2, _body.index("EOF") + 3))
check("H8. a line that only CONTAINS the delimiter is body text",
      _span("a\n EOF)\nxEOF\nEOF\n", 0, "EOF", False) == (13, 17))
check("H8. in a backtick substitution a body line holding a backtick is a run-on line too",
      _span("a\nb` ; ls\nEOF\n", 0, "EOF", False, in_backtick=True) is None
      and _span("a\nb` ; ls\nEOF\n", 0, "EOF", False, _hook.HEREDOC_RUN_ON_BACKTICK, True) == (2, 3)
      and _span("a\nb` ; ls\nEOF\n", 0, "EOF", False, _hook.HEREDOC_RUN_ON_ENDS, True) == (10, 14)
      and _span("a\nEOF\"` ; ls\nEOF\n", 0, "EOF", False, _hook.HEREDOC_RUN_ON_BACKTICK, True) == (2, 6)
      and _span("a\nb` ; ls\nEOF\n", 0, "EOF", False) == (10, 14))
check("H8. a terminator at the end of the text with no newline ends the body",
      _span("a\nEOF", 0, "EOF", False) == (2, 5))
_text = "cat <<EOF ; ls\nbody 'don't\nEOF\ngit status\n"
check("H8. judged_text keeps the heredoc's line and what follows its body, and drops the body",
      _hook.judged_text(_text) == "cat <<EOF ; ls\ngit status\n")
check("H8. judged_text drops a comment, an apostrophe in it included",
      _hook.judged_text("git status # it's\nls") == "git status \nls")
check("H8. judged_text keeps a `#` that is inside a word or a quote",
      _hook.judged_text("echo a#b '# c' \"# d\"") == "echo a#b '# c' \"# d\"")
check("H8. judged_text reads a body it cannot place as commands (the raw line)",
      _hook.judged_text("cat <<EOF\nx\ngit push origin main") == "cat <<EOF\nx\ngit push origin main")
check("H8. a whole-argument heredoc whose `)\"` is not after the terminator is none",
      _hook.heredoc_argument_at("\"$(cat <<'EOF'\nx\nEOF) ; y\nEOF\n)\"", 0) is None)
check("H8. the commit-message shape is one, body and end",
      _hook.heredoc_argument_at("\"$(cat <<'EOF'\nmsg\nEOF\n)\" ; ls", 0) == ("msg", 25))
# H9 (hook-audit-gaps, phase 3 (a)): a build script FED to a program through input redirection —
# `bash < agentTooling/run-plans.sh`, the `<>` spelling, `N<`, before the program or after it,
# glued or quoted — is a run, as the same script piped in is (`cat run-plans.sh | bash`). The fed
# file is read like a name in an exempt reader: a run once the line holds a command that may
# launch. Each row but the last three was a prompt before the fix (28 red; NOTES.md ruling 17)
for _line in ("bash < agentTooling/run-plans.sh", "sh < agentTooling/run-plans.sh",
              "bash <agentTooling/run-plans.sh", "bash<agentTooling/run-plans.sh",
              "bash < ./run-plans.sh", "bash < run-batch.sh", "bash <run-batch.sh",
              "bash < ./agentTooling/feature-close.sh", "bash < run-verify.sh",
              "bash < run-review.sh", "bash < feature-start.sh",
              "bash <> agentTooling/run-plans.sh", "bash <>agentTooling/run-plans.sh",
              "sh <> run-batch.sh", "bash 0< agentTooling/run-plans.sh",
              "bash 0<agentTooling/run-plans.sh", "bash 3< agentTooling/run-plans.sh",
              "bash 3<>agentTooling/run-plans.sh", "bash 3<agentTooling/run-plans.sh 0<&3",
              "bash {fd}< agentTooling/run-plans.sh", "bash -s < agentTooling/run-plans.sh",
              "env bash < agentTooling/run-plans.sh", "true && bash < agentTooling/run-plans.sh",
              "bash < agentTooling/run-pl?ns.sh", "bash < run-p*.sh",
              "< agentTooling/run-plans.sh bash", "zsh < run-plans.sh", "ksh93 < run-plans.sh",
              "bash < 'agentTooling/run-plans.sh'", "bash < \"run-plans.sh\"", "sh <'feature-close.sh'",
              "bash < run-pla''ns.sh", "bash <\trun-plans.sh", "bash < run-pla\\\nns.sh",
              "exec 3< run-plans.sh", "exec < run-batch.sh", "source /dev/stdin < run-plans.sh",
              "cat < run-plans.sh | bash", "cat < run-plans.sh | unshare sh",
              # no file after `-n`: `bash -n` reads the script from stdin, the form
              # `cat run-plans.sh | bash -n` already is
              "bash -n < run-plans.sh",
              "./run-plans.sh < /dev/null", "./run-plans.sh --self x < /dev/null",
              "cat run-plans.sh | bash"):
    check("H9. a build script fed to a program by input redirection is a run: %r" % _line,
          _hook.invokes_build_script(_line))
for _line in ("bash < README.md", "bash < src/x.sh", "ls < README.md", "cat < run-plans.sh",
              "grep -n x < run-plans.sh", "wc -l < run-plans.sh", "sort < run-plans.sh",
              "sed -n 5p < run-plans.sh", "bash < /dev/null", "git status 3< README.md",
              "ls > run-plans.sh.log", "cat < run-plans.sh # | bash"):
    check("H9. a read of a build script, or a redirect from no build script, is no run: %r" % _line,
          not _hook.invokes_build_script(_line))
# H10 (hook-audit-gaps, phase 3 self-audit of C): the launcher list is no more complete on the far
# side of a pipe than among a command's arguments, so beside an exempt reader that names a build
# script ANY command that is neither exempt nor a plain filter may launch it ...
for _line in ("cat run-plans.sh | unshare sh", "cat run-plans.sh | ash", "cat run-plans.sh | rbash",
              "cat run-plans.sh | prlimit --nproc=9 sh", "ls run-p*.sh | fish",
              "cat agentTooling/feature-close.sh | setpriv sh", "cat run-plans.sh | busybox sh",
              # a filter is PATH's program, named bare, without sort's `--compress-program`
              "cat run-plans.sh | ./sort", "cat run-plans.sh | sort --compress-program=sh -S 1b"):
    check("H10. a reader piped into a launcher the list does not know is a run: %r" % _line,
          _hook.invokes_build_script(_line))
# ... and a filter that never runs what it reads launches nothing
for _line in ("grep -c x run-plans.sh | sort", "cat run-plans.sh | head -3",
              "cat run-plans.sh | tr a b | cut -c1-9", "cat run-plans.sh | tee copy.txt",
              "wc -l run-plans.sh | sort -n | uniq", "cat run-plans.sh | sed -n 5p"):
    check("H10. a reader piped into a filter is no run: %r" % _line,
          not _hook.invokes_build_script(_line))
# H11 (the same self-audit, B and C): patterns the judge did not read as one. A bracket expression
# fnmatch does not know (`[^x]`, a POSIX class); a pattern glued to an operator on a line that
# does not lex; a pattern in an environment assignment, which the shell git hands the value to
# expands; and git's exec flags abbreviated as git accepts them, or `-O` inside a cluster
for _line in ("./run-plans.s[^x] --self x", "./run-plans.s[[:alpha:]] --self x",
              "unshare ./run-plan[[:lower:]].sh", "./run-plans.s[^\\]x]", "./[[=r=]]un-plans.sh",
              "true;./run-p*.sh;true # '", "./run-p*.sh>x # '", "(true;./run-pl?ns.sh) # it's",
              "GIT_EDITOR='./run-p*.sh' git commit", "GIT_EXTERNAL_DIFF=./run-pl?ns.sh git diff",
              "PAGER='sh run-p*.sh' git log -1", "GIT_EDITOR=run-p*.sh git commit",
              "git grep --open=./run-plans.sh x", "git grep -nO./run-plans.sh x",
              "git push --receive=./run-plans.sh origin b", "git push --rec ./run-plans.sh origin b"):
    check("H11. a build script behind a pattern or flag spelling the judge now reads is a run: %r"
          % _line, _hook.invokes_build_script(_line))
for _line in ("./README.m[^x]", "ls [a-c]*.md", "git log --grep=run-plans.sh", "X=1 ls",
              "git commit -m 'fix run-plans.sh'", "git log -- run-plans.sh", "git add run-plans.sh",
              "GIT_PAGER=cat git log -1", "git log --oneline -3"):
    check("H11. a plain command is still no run: %r" % _line, not _hook.invokes_build_script(_line))
# H12 (the same self-audit, F1, A and B1): `judged_text` reads the line as bash does. A `#` is a
# comment only where bash starts one; a `<<` is a heredoc only where bash reads one, with the
# delimiter bash reads; and a whole-argument heredoc is one word whatever its body quotes
_judged = _hook.judged_text
for _line in ("echo a\\ # ; ls", "echo \\;# ; ls", "echo a\r# ; ls", "echo a#b ; ls", "echo $# ; ls",
              "echo ${x#y} ; ls", "echo ${x:- #y} ; ls", "echo 'a'#b ; ls"):
    check("H12. a `#` that starts no word is no comment, and the line is judged with it: %r" % _line,
          _judged(_line) == _line and len(_hook.command_words(_line) or []) == 2)
check("H12. only `command_words` reads a `#` inside a word: the rewrites and the chained-cd deny "
      "keep `never_judged`'s guard",
      _hook.never_judged("echo a#b") and _hook.command_words("echo a#b") == [["echo", "a#b"]]
      and not _hook.chains_chdir("cd /tmp && ls a#b") and _hook.chains_chdir("cd /tmp && ls ab"))
check("H12. a comment inside backticks ends at the closing backtick",
      _judged("echo `echo a # b` ; ls") == "echo `echo a ` ; ls"
      and _judged("echo `# x`; ls") == "echo ``; ls")
check("H12. `$'` in a comment opens nothing, and `$'…'` before one is walked as the quote it is",
      _judged("ls # $'\nls") == "ls \nls" and _judged("echo $'it\\'s' # c") == "echo $'it\\'s' ")
check("H12. a whole-argument heredoc stands as one empty word, whatever quotes its body holds",
      _judged("git commit -m \"$(cat <<'EOF'\na \" b\nEOF\n)\" ; ls") == "git commit -m \"\" ; ls")
for _line in ("echo $((1<<2))\ngit status\n2\n", "(( x = 1 << 2 ))\ngit status\n2\n",
              "echo $[1<<2]\ngit status\n2]\n", "a[1<<2]=5\ngit status\n2]=5\n",
              "cat <<`a b`\nx\n`a b`\ngit status\n`a\n", "cat <<$\"x\"\nq\nx\ngit status\n$x\n",
              "cat <<EOF\r\nx\r\nEOF\r\ngit status\nEOF\n",
              "x=abcdefgh; echo ${x:1<<2}\ngit status\n2}\n",
              # a substitution opened between the operator and the end of its line: bash reads
              # through an open one before any body, so the next line may be a command (whether
              # it has closed again is not asked — the cost is a body read as commands)
              "cat <<EOF $(echo a\ngit status\nEOF\n)\n", "cat <<EOF \"$(pwd)\"\nbody\nEOF\nls"):
    check("H12. a `<<` that may be a shift, or a body bash starts elsewhere, places no body: %r"
          % _line, _hook.comment_and_heredoc_free(_line) is None and _judged(_line) == _line)
check("H12. a body that cannot be placed still loses its comments",
      _judged("echo $((1<<2)) # c\ngit status\n2\n") == "echo $((1<<2)) \ngit status\n2\n")
_BODY, _ENDS = _hook.HEREDOC_RUN_ON_IS_BODY, _hook.HEREDOC_RUN_ON_ENDS
check("H12. a run-on line (`EOF)`, and `EOF` before a backtick) is read as the caller asks",
      _span("a\nEOF)\nEOF\n", 0, "EOF", False, _BODY) == (7, 11)
      and _span("a\nEOF)\nEOF\n", 0, "EOF", False, _ENDS) == (2, 5)
      and _span("a\n\tEOF) x\n", 0, "EOF", True, _ENDS) == (2, 6)
      and _span("x\nEOF` ; ls\nEOF\n", 0, "EOF", False) is None)
check("H12. outside a substitution `EOF)` is the plain body line it is to bash",
      _hook.judged_texts("cat <<EOF\nit's\nEOF)\nEOF\ngit status") == ["cat <<EOF\ngit status"]
      and _hook.judged_texts("(cat <<EOF\nx\nEOF) ; ls\nEOF\n)") == ["(cat <<EOF\n)"])
check("H12. inside one it is read both ways: body text, and the end of the body (bash 5.2)",
      _hook.judged_texts("echo $(cat <<EOF\nx\nEOF) ; ls\nEOF\n")
      == ["echo $(cat <<EOF\n", "echo $(cat <<EOF\n) ; ls\nEOF\n"]
      and "git commit -m \"\" ; ls ; echo \"\nEOF\n)\"" in _hook.judged_texts(
          "git commit -m \"$(cat <<'EOF'\na \" b\nEOF)\" ; ls ; echo \"\nEOF\n)\""))
check("H12. a whole-argument heredoc with an UNQUOTED delimiter is not stood in: its body expands",
      _judged("git commit -m \"$(cat <<EOF\nx \" $(ls) \" y\nEOF\n)\"")
      == "git commit -m \"$(cat <<EOF\nx \" $(ls) \" y\nEOF\n)\"")
# H16 (round 2; NOTES.md, coordinator ruling 7): the walk hides a comment only where it is
# certain bash starts one. Past an opener (`(`, `[`, `{`, a backtick) it is in doubt, and
# `judged_texts` returns both readings of each such `#`, on its own; a line continuation is
# deleted in the walk, never inside a comment; a body may end at any of its run-on lines
_texts = _hook.judged_texts


def _unread(line):
    """True when `judged_texts` refuses to read the line (OverflowError)."""
    try:
        _texts(line)
    except OverflowError:
        return True
    return False


check("H16. with no opener before it a comment is certain: one reading",
      _texts("ls src # x; ls") == ["ls src "] and _texts("ls '(' # x\nls") != ["ls '(' \nls"])
check("H16. past an opener a comment is in doubt: dropped first, and kept as commands",
      _texts("a=(x)#b; ls") == ["a=(x)", "a=(x)#b; ls"]
      and _texts("echo $((1 #b)); ls") == ["echo $((1 ", "echo $((1 #b)); ls"])
check("H16. each comment in doubt is read on its own: every combination",
      _texts("(a) #b\n(c) #d\nls")[0] == "(a) \n(c) \nls"
      and set(_texts("(a) #b\n(c) #d\nls")) == {"(a) \n(c) \nls", "(a) \n(c) #d\nls",
                                               "(a) #b\n(c) \nls", "(a) #b\n(c) #d\nls"})
check("H16. a line continuation is deleted where bash deletes it, so its neighbours meet: a "
      "`#` after `a \\⏎` starts a comment, one after `a\\⏎` does not; a last backslash that "
      "escapes nothing is dropped",
      _texts("git pu\\\nsh origin x") == ["git push origin x"]
      and _texts("ls \\\n# x; ls") == ["ls "] and _texts("ls a\\\n#b; ls") == ["ls a#b; ls"]
      and _texts("echo \"a\\\nb\" 'c\\\nd'") == ["echo \"ab\" 'c\\\nd'"]
      and _texts("git status \\") == ["git status "])
check("H16. a body may end at any of its run-on lines: each is read as the end in turn",
      _texts("echo $(cat <<EOF\nEOFS\nEOF ls)\nEOF\n")
      == ["echo $(cat <<EOF\n", "echo $(cat <<EOF\nS\nEOF ls)\nEOF\n", "echo $(cat <<EOF\n ls)\nEOF\n"]
      and _span("a\nEOFS\nEOF x)\n", 0, "EOF", False, _ENDS, skip=1) == (7, 10)
      and _span("a\nEOFS\nEOF x)\n", 0, "EOF", False, _ENDS, skip=2) is None)
_ended = []
check("H16. a body ended at a run-on line is noted, so the caller knows when none is left",
      _span("a\nEOFS\nEOF x)\n", 0, "EOF", False, _ENDS, skip=1, ended=_ended) == (7, 10)
      and _ended == [7] and _span("a\nEOFS\nEOF\n", 0, "EOF", False, _ENDS, skip=1, ended=_ended)
      == (7, 11) and _ended == [7])
_run_on = "echo $(cat <<EOF\n" + "EOFx\n" * (_hook.MAX_RUN_ON_LINES + 1)
check("H16. more run-on lines than MAX_RUN_ON_LINES: a line naming git is judged as a git "
      "command that cannot be read, any other is not read at all",
      _hook.mutates_git_refs(_run_on + "EOF git status)") and _unread(_run_on + "EOF ls)"))
check("H16. inside a comment no continuation is deleted: the next line is a command",
      _texts("ls # x \\\ngit status") == ["ls \ngit status"]
      and _texts("ls # x \\\ngit sta\\\ntus # y \\\nls") == ["ls \ngit status \nls"])
check("H16. a placed heredoc body and a whole-argument heredoc are no opener for what follows",
      _texts("cat <<EOF\n(x)\nEOF\nls # y; ls") == ["cat <<EOF\nls "]
      and _texts("git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\" # y; ls") == ["git commit -m \"\" "])
_many ="(a) #b\n" * (_hook.MAX_COMMENT_DOUBTS + 1)
check("H16. more comments in doubt than MAX_COMMENT_DOUBTS: a line naming git is judged as a git "
      "command that cannot be read, any other is not read at all — a run to the build-script judge",
      _texts(_many + "git status") == [" ".join((_hook.GIT_PROGRAM,) + _hook.GIT_UNREADABLE_ARGS)]
      and _hook.mutates_git_refs(_many + "git status") and _unread(_many + "ls")
      and len(_texts("(a) #b\n" * _hook.MAX_COMMENT_DOUBTS + "ls")) == 2 ** _hook.MAX_COMMENT_DOUBTS)
check("H16. only a `${` nests inside `${…}`: a bare `{` there is text (the review's item 1)",
      _judged("echo ${x:-{} ; ls # '") == "echo ${x:-{} ; ls "
      and _judged("echo ${x:-${y:-{}}} # '") == "echo ${x:-${y:-{}}} "
      and _judged("echo ${x:-${y:- #z}} ; ls") == "echo ${x:-${y:- #z}} ; ls")
check("H16. `$$` is the PID: the quote after it is a plain one and is returned without it, the "
      "brace after it opens no expansion, and an odd run of `$` still makes `$'…'`",
      _judged("echo $$'a\\' ; ls #'") == "echo 'a\\' ; ls "
      and _judged("echo $$$'a\\'' ; ls # c") == "echo $$$'a\\'' ; ls "
      and _judged("echo \\$'a' # '") == "echo \\$'a' "
      and _judged("echo $${x ; ls # '") == "echo $${x ; ls ")
# H17 (round 3; escalations/02-audit-opus.md, R2-1 to R2-3): bash deletes a line continuation
# BEFORE it reads the construct around it, so the walk deletes it before it tests what it is
# looking at, and a body's lines are joined before the terminator is looked for — when the
# delimiter is unquoted, which the caller says with `joins`
_JOIN = dict(joins=_hook.HEREDOC_JOIN_ODD)
check("H17. an unquoted delimiter's body ends at a terminator joined across a continuation",
      _span("x\nEO\\\nF\nrest\nEOF\n", 0, "EOF", False, **_JOIN) == (2, 8)
      and _span("x\nE\\\nO\\\nF\nrest", 0, "EOF", False, **_JOIN) == (2, 10)
      and _span("x\nEOF\\\n\nrest", 0, "EOF", False, **_JOIN) == (2, 8)
      and _span("x\n\tEO\\\nF\nrest", 0, "EOF", True, **_JOIN) == (2, 9)
      and _span("x\n\\\n\tEOF\nrest", 0, "EOF", True, **_JOIN) == (2, 9))
check("H17. ... and not at a line bash joins to the one before it, nor across an escaped backslash",
      _span("x\\\nEOF\ny\nEOF\n", 0, "EOF", False, **_JOIN) == (9, 13)
      and _span("x\nEO\\\\\nF\nEOF\n", 0, "EOF", False, **_JOIN) == (9, 13)
      and _span("x\n\tEO\\\n\tF\nEOF\n", 0, "EOF", True, **_JOIN) == (10, 14))
check("H17. a quoted delimiter's body is joined nowhere (no `joins`): the lines as written",
      _span("x\nEO\\\nF\nrest\nEOF\n", 0, "EOF", False) == (13, 17)
      and _span("x\\\nEOF\ny\nEOF\n", 0, "EOF", False) == (3, 7))
check("H17. a run-on line joined across a continuation ends the body after the delimiter",
      _span("x\nEO\\\nF ) ; ls\nEOF\n", 0, "EOF", False, _ENDS, **_JOIN) == (2, 7)
      and _span("x\nEOF\\\n ) ; ls\nEOF\n", 0, "EOF", False, _ENDS, **_JOIN) == (2, 7)
      and _span("x\nEO\\\nF ) ; ls\nEOF\n", 0, "EOF", False, **_JOIN) is None)
_delimiter = _hook.heredoc_delimiter
check("H17. a delimiter is read with its continuations deleted, and says whether it was quoted",
      _delimiter("EOF\nx", 0) == ("EOF", False, 3, False)
      and _delimiter("'EOF'\nx", 0) == ("EOF", False, 5, True)
      and _delimiter("\\EOF\nx", 0) == ("EOF", False, 4, True)
      and _delimiter("\\\nE\\\nOF\\\n ; ls\nx", 0) == ("EOF", False, 9, False)
      and _delimiter("\\\n-\\\n EOF\nx", 0) == ("EOF", True, 9, False)
      and _delimiter("\"E\\\nOF\"\nx", 0) == ("EOF", False, 7, True)
      and _delimiter("'E\\\nOF'\nx", 0) == ("E\\\nOF", False, 7, True)
      and _delimiter("$\\\n(x)\nx", 0) is None)
check("H17. the body after a joined terminator is read: one text when bash's reading is certain",
      _texts("cat <<EOF\nx\nEO\\\nF\ngit status\nEOF")[0] == "cat <<EOF\ngit status\nEOF"
      and _texts("cat <<'EOF'\nx\nEO\\\nF\ngit status\nEOF") == ["cat <<'EOF'\n"]
      and _texts("cat <<EOF\nx\nEO\\\\\nF\ngit status\nEOF") == ["cat <<EOF\n"])
check("H17. the reading that joins nothing is kept beside bash's: the round only added denies",
      _texts("cat <<EOF\nx\\\nEOF\ngit status\nEOF") == ["cat <<EOF\n", "cat <<EOF\ngit status\nEOF"])
check("H17. inside backticks a quoted delimiter's body is joined too: read both ways",
      _texts("echo `cat <<'EOF'\nEO\\\nF\ngit status\nEOF\n`")
      == ["echo `cat <<'EOF'\n`", "echo `cat <<'EOF'\ngit status\nEOF\n`"])
check("H17. a split operator, delimiter and herestring are the ones bash reads",
      _judged("cat <\\\n<EOF\nit's\nEOF\nls") == "cat <<EOF\nls"
      and _judged("cat <<\\\nE\\\nOF\nit's\nEOF\nls") == "cat <<EOF\nls"
      and _judged("cat <<\\\n-EOF\nit's\n\tEOF\nls") == "cat <<-EOF\nls"
      and _judged("cat <<'EOF'\\\n\nit's\nEOF\nls") == "cat <<'EOF'\nls"
      and _judged("cat <<\\\n< x\nls") == "cat <<< x\nls"
      and _judged("cat <\\\n<\\\n< x\nls") == "cat <<< x\nls")
check("H17. a split substitution opener puts the heredoc after it inside a substitution",
      "cat <(cat <<EOF\n ) ; ls\nEOF\n)" in _texts("cat <\\\n(cat <<EOF\nx\nEOF ) ; ls\nEOF\n)")
      and "echo $(cat <<EOF\n ) ; ls\nEOF\n)" in _texts("echo $\\\n(cat <<EOF\nx\nEOF ) ; ls\nEOF\n)"))
for _line in ("(\\\n( x = 1<<2 ))\ngit status\n2\n", "echo $\\\n[1<<2]\ngit status\n2]\n",
              "a[1\\\n<<2]=5\ngit status\n2]=5\n", "echo $(\\\n(1<<2))\ngit status\n2))\n",
              "echo $\\\n{x:1<<2}\ngit status\n2}\n"):
    check("H17. a split arithmetic opener, subscript or `${` still makes a `<<` a shift: %r" % _line,
          _hook.comment_and_heredoc_free(_line) is None)
check("H17. a whole-argument heredoc whose head or tail is split stands as the one word it is",
      _judged("git commit -m \"$\\\n(cat <<'EOF'\na \" b\nEOF\n)\" ; ls") == "git commit -m \"\" ; ls"
      and _judged("git commit -m \"$(c\\\nat <<\\\n'EOF'\\\n\na \" b\nEOF\n)\" ; ls") == "git commit -m \"\" ; ls"
      and _judged("git commit -m \"$(cat <<'EOF'\na \" b\nEOF\n\\\n)\\\n\" ; ls") == "git commit -m \"\" ; ls"
      and _judged("git commit -m \"$(cat <<'EO\\\nF'\na \" b\nEOF\n)\" ; ls") != "git commit -m \"\" ; ls")
check("H17. inside backticks a continuation is deleted inside single quotes too",
      _texts("echo `git 'sta\\\ntus'`") == ["echo `git 'status'`"]
      and _texts("echo 'a\\\nb'") == ["echo 'a\\\nb'"])
check("H17. ... and bash halves a run of backslashes there first: `\\\\⏎` is a continuation "
      "to the substitution's own parser, in the walk and in an unquoted delimiter's body",
      _texts("echo `ls\ngit sta\\\\\ntus\n`") == ["echo `ls\ngit status\n`"]
      and _texts("echo `ls\ngit sta\\\\\\\\\ntus\n`") == ["echo `ls\ngit sta\\\\\\\\\ntus\n`"]
      and _texts("echo ls\ngit sta\\\\\ntus\n") == ["echo ls\ngit sta\\\\\ntus\n"]
      and _span("x\nEO\\\\\nF\nrest", 0, "EOF", False, joins=_hook.HEREDOC_JOIN_BACKTICK) == (2, 9)
      and _span("x\nEO\\\\\\\\\nF\nEOF\n", 0, "EOF", False, joins=_hook.HEREDOC_JOIN_BACKTICK) == (11, 15)
      and "echo `cat <<EOF\ngit status\n`" in _texts("echo `cat <<EOF\nit's\nEO\\\\\nF\ngit status\n`"))
check("H17. a whole-argument heredoc that is not stood in is also read as the substitution it "
      "is: its quotes dropped, its body placed, and what follows the body read as commands",
      _texts("echo \"$(cat <<EOF\nEO\\\nF\ngit status\nEOF\n)\"")
      == ["echo \"$(cat <<EOF\nEOF\ngit status\nEOF\n)\"", "echo $(cat <<EOF\ngit status\nEOF\n)",
          "echo $(cat <<EOF\n)"]
      and _texts("git commit -m \"$(cat <<EOF\nx \" y\nEOF\n)\" ; ls")
      == ["git commit -m \"$(cat <<EOF\nx \" y\nEOF\n)\" ; ls", "git commit -m $(cat <<EOF\n) ; ls"]
      and _texts("git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n)\"") == ["git commit -m \"\""])
check("H17. the own-assignment deny looks for the use in every reading (R2-3)",
      _hook.uses_own_assignment("a=(x)#b; X=/p; cat $X/f")
      and _hook.uses_own_assignment("cat <<EOF\nEO\\\nF\nX=/p; cat $X/f\nEOF")
      and not _hook.uses_own_assignment("a=(x)#b; X=/p; cat $Y/f")
      and not _hook.uses_own_assignment("cat <<'EOF'\nEO\\\nF\nX=/p; cat $X/f\nEOF"))
check("H17. past a cap, a git word split by a continuation is still a git command that cannot be read",
      _hook.mutates_git_refs(_many + "gi\\\nt status"))
# H18 (round 4; escalations/03-audit-opus.md, R3-1 and R3-2): a reading the walk BUILT whose
# quotes never close is no longer dropped quietly — the walk says so (TornReading),
# `judged_texts` notes it and judges a line that names git as a git command that cannot be
# read, and `does_not_tokenize` denies any other; ruling 45's opened head is matched in every
# spelling bash reads as that head
_free = _hook.comment_and_heredoc_free
_Torn = _hook.TornReading
_UNREADABLE_GIT = [" ".join((_hook.GIT_PROGRAM,) + _hook.GIT_UNREADABLE_ARGS)]
_W1 = "echo \"$(cat <<'EOF'\nx\nEOF )\" ; %s\nEOF\n)\""
_O13P = "echo \"$(cat <<EOF\nx\nEOF )\" ; %s\nEOF\n)\""
check("H18. the walk returns the line as a TornReading when it built a reading whose quotes "
      "never close, and as the plain line when it built nothing",
      isinstance(_free(_W1 % "ls", run_on=_ENDS), _Torn)
      and _free(_W1 % "ls", run_on=_ENDS) == _W1 % "ls"
      and isinstance(_free("ls # x\nls '"), _Torn) and isinstance(_free("ls \\\n-l '"), _Torn)
      and isinstance(_free("cat <<EOF\nx\nEOF\nls '"), _Torn)
      and not isinstance(_free("ls 'x"), _Torn) and not isinstance(_free("ls \"$(x) 'y"), _Torn)
      and not isinstance(_free("ls # it's"), _Torn))
check("H18. a dropped `$$` alone is no built reading (`torn_reading` asks the walk again with it kept)",
      isinstance(_free("grep $$'\\'#' f", drop_pid=True), _Torn)
      and not _hook.tears_a_reading("grep $$'\\'#' f")
      and _hook.tears_a_reading("ls # x\ngrep $$'\\'#' f"))
for _name, _line in (("w1, a quoted delimiter stood in at the run-on line", _W1),
                     ("o13p, an unquoted one opened", _O13P),
                     ("x8, no terminator line at all", "echo \"$(cat <<'EOF'\nx\nEOF )\" ; %s\n)\"")):
    _torn = []
    check("H18. a built reading that does not tokenize is noted, and a line that names git is "
          "a git command that cannot be read: " + _name,
          _texts(_line % "git status", _torn) == _UNREADABLE_GIT and bool(_torn)
          and _hook.mutates_git_refs(_line % "git status")
          and _hook.tears_a_reading(_line % "ls") and _hook.does_not_tokenize(_line % "ls")
          and _texts(_line % "ls") != _UNREADABLE_GIT)
check("H18. a comment in doubt kept as text, and bodies read as commands, are not built readings",
      not _hook.tears_a_reading("cat <<EOF\nx\nEOF\n(ls) # it's")
      and not _hook.tears_a_reading("cat <<EOF # c\nit's\nEOX")
      and not _hook.does_not_tokenize("cat <<EOF\nx\nEOF\n(ls) # it's"))
check("H18. the usual message is one reading that tokenizes, whatever quotes its body holds",
      _texts("git commit -m \"$(cat <<'EOF'\nit's \"x\", `y`\nEOF\n)\"") == ["git commit -m \"\""]
      and not _hook.tears_a_reading("git commit -m \"$(cat <<'EOF'\nit's \"x\", `y`\nEOF\n)\"")
      and not _hook.tears_a_reading("git commit -m \"$(cat <<EOF\nan odd \" here\nEOF\n)\""))
_head = _hook.HEREDOC_OPENED_HEAD_RE
check("H18. the opened head is matched as bash reads it: blanks and a line break after the "
      "`$(`, blanks or none around the `<<`, a continuation anywhere — and no text before the `$(`",
      all(_head.match(_text) for _text in (
          "\"$(cat <<EOF", "\"$( cat <<EOF", "\"$(\tcat\t<<EOF", "\"$(\ncat <<EOF", "\"$(cat<<EOF",
          "\"$\\\n(\\\n c\\\nat \\\n<\\\n<EOF"))
      and not any(_head.search(_text) for _text in (
          "\"x$(cat <<EOF", "\"$(command cat <<EOF", "\"$(cat - <<EOF", "\"$(cat\n<<EOF", "$(cat <<EOF")))
check("H18. each spelling is opened as the head itself is (o3, o3p)",
      "echo $(cat <<EOF\ngit status\nEOF\n)" in _texts("echo \"$( cat <<EOF\nx\nEO\\\nF\ngit status\nEOF\n)\"")
      and "echo $(cat <<EOF\ngit status\nEOF\n)" in _texts("echo \"$(\tcat  <<EOF\nx\nEOF\ngit status\nEOF\n)\"")
      and _texts("echo \"x$(cat <<EOF\nx\nEOF\ngit status\nEOF\n)\"")
      == ["echo \"x$(cat <<EOF\nx\nEOF\ngit status\nEOF\n)\""])
# H19 (round 5; escalations/04-audit-opus.md, R4-1): a whole-argument head whose delimiter is
# no bare or fully quoted identifier is not read for a message at all — `unread_head` is the
# test, `judged_texts` notes every reading that holds one as torn
_unread = _hook.unread_head
_HEAD_TEXT = "echo \"$(cat <<%s\nx\n)\""
check("H19. a head whose delimiter is partly quoted, backslash-quoted, empty or no identifier is unread",
      all(_unread(_HEAD_TEXT % _delim) for _delim in (
          "E'O'F", "E\"O\"F", "'E'OF", "EO'F'", "\"E\"'O'F", "'EOF'''", "''EOF", "'EOF'\"\"", "E\\OF",
          "\\E\\O\\F", "\\EOF", "''", "\"\"", "-''", "E-F", "E.F", "123", "'E O F'", "'EOF '", "'!'",
          "'E)F'", "'E;F'", "'E#F'", "'E\"F'", "\"E'F\"", "'EOF", "$EOF", "")))
check("H19. ... in every spelling of the head",
      all(_unread(_text) for _text in (
          "\"$( cat <<''\n", "\"$(\tcat\t<<E-F\n", "\"$(\ncat <<E'O'F\n", "\"$(cat<<''\n",
          "\"$\\\n(\\\n c\\\nat \\\n<\\\n<E-F\n")))
check("H19. a bare or fully quoted identifier is read as it was, with `-` and blanks before it, "
      "and whatever follows the word; a herestring and text before the `$(` are no head",
      not any(_unread(_text) for _text in (
          _HEAD_TEXT % "EOF", _HEAD_TEXT % "'EOF'", _HEAD_TEXT % "\"EOF\"", _HEAD_TEXT % "-EOF",
          _HEAD_TEXT % "-'EOF'", _HEAD_TEXT % "-\t\"EOF\"", _HEAD_TEXT % " EOF", _HEAD_TEXT % "_",
          _HEAD_TEXT % "END_OF_MSG2", "echo \"$(cat <<EOF)\"", "x=\"$(cat <<EOF | tr a b\nx\nEOF\n)\"",
          "echo \"$(cat <<'EOF' \nx\nEOF\n)\"", "echo \"$(cat <<<\"x\")\"", "echo \"$(cat <<< x)\"",
          "echo \"x$(cat <<''\nx\n\n)\"", "echo $(cat <<''\nx\n\n)", "cat <<''\nx\n", "echo \"$(cat f)\"")))
for _name, _line in (("p4, the canonical shape", "echo \"$(cat <<E'O'F\nx\"\nEOF\n)\" ; %s"),
                     ("p2, a run-on line", "echo \"$(cat <<E\"O\"F\nx\nEOF )\" ; %s\nEOF\n)\""),
                     ("e5, an empty delimiter", "echo \"$(cat <<''\nx\n)\" ; %s\n\n)\""),
                     ("c22, an operator in the delimiter", "echo \"$(cat <<'E)F'\nx\"\nE)F\n)\" ; %s"),
                     ("a balanced body (the audit's p1, denied before)", "echo \"$(cat <<E\"O\"F\nx\nEOF\n)\" ; %s"),
                     ("after a body no reading places", "echo \"$(cat <<''\nx\n)\" ; %s ; cat <<EOF\n\n)\""),
                     ("after a comment in doubt", "(ls) # c\necho \"$(cat <<''\nx\"\n\n)\" ; %s")):
    _torn = []
    check("H19. a reading that holds such a head is noted as torn, and a line that names git is "
          "a git command that cannot be read: " + _name,
          _texts(_line % "git status", _torn) == _UNREADABLE_GIT and bool(_torn)
          and _hook.mutates_git_refs(_line % "git status")
          and _hook.tears_a_reading(_line % "ls") and _hook.does_not_tokenize(_line % "ls")
          and _texts(_line % "ls") != _UNREADABLE_GIT)
check("H19. a head a reading has dropped — in a comment, in a placed or stood-in body — is not noted",
      not _hook.tears_a_reading("ls # \"$(cat <<''")
      and not _hook.tears_a_reading("cat <<'EOF'\n\"$(cat <<''\nEOF")
      and not _hook.tears_a_reading("git commit -m \"$(cat <<'EOF'\nthe head \"$(cat <<E'O'F\nEOF\n)\"")
      and _texts("git commit -m \"$(cat <<'EOF'\nthe head \"$(cat <<E'O'F\nEOF\n)\"") == ["git commit -m \"\""])
check("H19. a head split by continuations is the head bash reads: its plain delimiter is read, "
      "its odd one refused",
      not _hook.tears_a_reading("echo \"$(cat <<E\\\nOF\nx\nEOF\n)\"")
      and not _hook.tears_a_reading("echo \"$(cat <<\\\n'EOF'\\\n\nx\nEOF\n)\"")
      and _hook.tears_a_reading("echo \"$( c\\\nat <<E\\\n'O'F\nx\nEOF\n)\""))
check("H19. the usual message is untouched under each delimiter a message is written with",
      not any(_hook.tears_a_reading("git commit -m \"$(cat <<%s\nit's \"x\n%sEOF\n)\"" % (_delim, _tab))
              for _delim, _tab in (("'EOF'", ""), ("\"EOF\"", ""), ("EOF", ""), ("-EOF", "\t"), ("-'EOF'", "\t"))))
# H20 (round 7; escalations/06-review-opus.md and 06-audit-opus.md, B1): round 6's deny asks
# bash itself whether the line parses (`bash_refuses`: `bash -n`, the text on stdin) instead of
# guessing — a line that names git, that no reading here judges and that bash refuses is the
# unreadable git command, `never_judged`'s ANSI-C quote or not; a line bash parses keeps its
# texts. The check executes nothing, fails closed, and is made only for such a line
_refuses = _hook.bash_refuses
_PUSH = "git push -f origin y\n"
_REVIEW = "git commit -m \"$(echo \"it's\")\""
check("H20. bash is asked to parse only (`-n`), with the text on stdin (no `-c`, no file), no "
      "startup file, an environment of PATH alone naming absolute directories, and a timeout",
      _hook.BASH_SYNTAX_ARGV == ("bash", "--norc", "--noprofile", "-n")
      and set(_hook.BASH_SYNTAX_ENV) == {"PATH"}
      and all(os.path.isabs(_dir) for _dir in _hook.BASH_SYNTAX_ENV["PATH"].split(os.pathsep))
      and 0 < _hook.BASH_SYNTAX_TIMEOUT_SECONDS <= 10)
_CANARY = os.path.join(TMP, "bash-n-canary")
_STARTUP = os.path.join(TMP, "bash-n-startup.sh")
with open(_STARTUP, "w") as f:
    f.write("touch %s\n" % _CANARY)
_kept_env = {_name: os.environ.get(_name) for _name in ("BASH_ENV", "ENV", "SHELLOPTS")}
os.environ.update(BASH_ENV=_STARTUP, ENV=_STARTUP, SHELLOPTS="xtrace")
_EXECUTES = ("touch %s", "echo $(touch %s)", "echo `touch %s`", "cat <(touch %s)", ": > %s",
             "cat <<EOF\n$(touch %s)\nEOF", "echo ${x:=$(touch %s)}", "echo $(( $(touch %s) ))",
             "set +n\ntouch %s", "set +o noexec\ntouch %s", "trap 'touch %s' EXIT",
             "shopt -s expand_aliases\nalias x='touch %s'\nx", "f() { touch %s; }\nf",
             "eval 'touch %s'", "exec touch %s", "touch %s\necho '", "touch %s\necho \"$(cat <<EOF")
_answers = [_refuses(_text % _CANARY) for _text in _EXECUTES]
for _name, _value in _kept_env.items():
    if _value is None:
        del os.environ[_name]
    else:
        os.environ[_name] = _value
check("H20. nothing in the text is executed — a command, a substitution in a word, a body or an "
      "expansion, a redirect, a trap, an alias, `set +n` — and no BASH_ENV, ENV or SHELLOPTS of "
      "the hook's own environment reaches bash",
      not os.path.exists(_CANARY) and _answers[-2:] == [True, True] and not any(_answers[:-2]))
check("H20. bash parses what shlex refuses: a quoted substitution whose inner quotes hold an "
      "odd quote, and an ANSI-C quote that escapes one",
      not any(_refuses(_line) for _line in (
          _REVIEW, "git commit -m \"$(echo \"it's #1\")\"", "git commit -m \"$(printf \"%s\" \"don't\")\"",
          "git commit -m $'it\\'s'", _PUSH + "echo $'\\''", "echo $'\\'' && git push -f origin y")))
check("H20. bash refuses a quote or a head it never closes, after an ANSI-C quote too, and a "
      "heredoc that is never terminated — exit 0 and a warning: any output is a refusal",
      all(_refuses(_line) for _line in (
          _PUSH + "echo '#", _PUSH + "echo \"$(cat <<EOF", "git rebase 'main",
          _PUSH + "echo $'\\'' \"", _PUSH + "echo $'\\'' '", _PUSH + ": $'a\\'b' \"x",
          _PUSH + "echo ${x:-$'\\''} \"", "echo $'\\''\n" + _PUSH + "echo \"",
          _PUSH + "cat <<EOF\necho '", "git status ; cat <<EOF\nit's", _PUSH + "cat <<EOF\n$'\\''")))
check("H20. a NUL, and a character that does not encode, are refused",
      _refuses("git status\0") and _refuses("git status \udc80 'x'"))
check("H20. a line that names git, that no reading judges and that bash refuses is the "
      "unreadable git command — `never_judged`'s ANSI-C quote is no excuse, lexed or not",
      all(_texts(_line) == _UNREADABLE_GIT and _hook.mutates_git_refs(_line) for _line in (
          _PUSH + "echo $'\\'' \"", _PUSH + "echo $'\\'' '", _PUSH + "echo $'\\'' \"$(cat <<EOF",
          _PUSH + ": $'a\\'b' \"x", _PUSH + "echo ${x:-$'\\''} \"", "echo $'\\''\n" + _PUSH + "echo \"",
          _PUSH + "echo '#", "git rebase 'main", "git status\necho '#")))
check("H20. a line bash parses keeps its texts, tokenized here or not",
      all(_texts(_line) != _UNREADABLE_GIT for _line in (
          _REVIEW, "git commit -m \"$(echo \"it's #1\")\"", "git commit -m $'it\\'s'",
          _PUSH + "echo $'\\''", _PUSH + "echo \"$(echo \"it's\")\""))
      and _hook.does_not_tokenize(_REVIEW) and not _hook.does_not_tokenize("git commit -m \"$(echo \"it's #1\")\""))
_hook.BASH_REFUSALS.clear()
for _line in ("git status", "git push -f origin y", "ls\necho '#", "ls\necho $'\\'' \"", "cat 'x",
              "git commit -m \"$(cat <<'EOF'\nit's \"x\nEOF\n)\"", "git status # it's",
              "echo \"$(cat <<EOF\nx\nEOF )\" ; git status\nEOF\n)\""):
    _texts(_line)
check("H20. bash is not asked about a line a reading judges, a line that names no git or a "
      "torn reading (asked about: %s)" % sorted(_hook.BASH_REFUSALS),
      not _hook.BASH_REFUSALS)
_texts("git rebase 'main"), _texts("git rebase 'main"), _hook.mutates_git_refs("git rebase 'main")
check("H20. ... and once about a line it is asked about, however often the line is read",
      _hook.BASH_REFUSALS == {"git rebase 'main": True})
for _name, _patch in (
        ("no bash on the PATH", {"BASH_SYNTAX_ENV": {"PATH": os.path.join(TMP, "no-such-dir")}}),
        ("a program that cannot be run", {"BASH_SYNTAX_ARGV": (os.path.join(TMP, "no-such-bash"), "-n")}),
        ("a timeout", {"BASH_SYNTAX_ARGV": ("sleep", "5"), "BASH_SYNTAX_TIMEOUT_SECONDS": 0.05}),
        ("a non-zero exit", {"BASH_SYNTAX_ARGV": ("false",)}),
        ("output on a zero exit", {"BASH_SYNTAX_ARGV": ("echo", "unexpected")})):
    _kept = {_key: getattr(_hook, _key) for _key in _patch}
    for _key, _value in _patch.items():
        setattr(_hook, _key, _value)
    _hook.BASH_REFUSALS.clear()
    check("H20. the check fails closed — %s: the line counts as refused, and one that names git "
          "and that no reading judges is the unreadable git command" % _name,
          _refuses(_REVIEW) and _texts(_REVIEW) == _UNREADABLE_GIT and _hook.mutates_git_refs(_REVIEW)
          and _texts("git commit -m $'it\\'s'") == _UNREADABLE_GIT
          and _texts("git status") == ["git status"] and _texts("ls 'x") == ["ls 'x"])
    for _key, _value in _kept.items():
        setattr(_hook, _key, _value)
    _hook.BASH_REFUSALS.clear()
check("H20. ... and asked of the real bash again, the same line is parsed and keeps its texts",
      not _refuses(_REVIEW) and _texts(_REVIEW) == [_REVIEW])
# H13 (the same self-audit, F2): the git deny's own brace expansion reads what bash expands —
# nested groups and `{a..c}` sequences, in bash's order — and refuses to guess past the cap
_braces = _hook.brace_words
check("H13. nested groups, sequences and repeated groups expand as in bash",
      _braces("--forc{e,{x,y}}") == ["--force", "--forcx", "--forcy"]
      and _braces("-{f..f}") == ["-f"] and _braces("{a..c}") == ["a", "b", "c"]
      and _braces("{3..1}") == ["3", "2", "1"] and _braces("{a..e..2}") == ["a", "c", "e"]
      and _braces("{a,b}{1,2}") == ["a1", "a2", "b1", "b2"] and _braces("x{,}y") == ["xy", "xy"])
check("H13. a group bash leaves as written stays as written",
      _braces("{a}") == ["{a}"] and _braces("a{}b{c,d}") == ["a{}bc", "a{}bd"]
      and _braces("{a{b,c}") == ["{ab", "{ac"] and _braces("{a..3}") == ["{a..3}"]
      and _braces("plain") == ["plain"])
for _word in ("{1..300}", "x{,a}{,b}{,c}{,d}{,e}{,f}{,g}{,h}{,i}"):
    try:
        _braces(_word)
        _raised = False
    except OverflowError:
        _raised = True
    check("H13. past the cap the expansion refuses: %r" % _word, _raised)
# H14 (phase 3 (a), end to end): B — a checkout whose orchestrator ledger cannot be read (a `.git`
# naming no directory), where the build-script judge is the one deny every session gets. A
# script fed by redirection gets the SAME deny the piped one gets: the role's reason, asked
# three times over, since a rewrite deny would have decayed to an ask by then
BROKEN = os.path.join(TMP, "broken-ledger")
HOOK_BROKEN = vendor_hook(os.path.join(BROKEN, "hooks"))
for _name in ("orchestrator_role.py", "shared_rules.py"):
    shutil.copy2(os.path.join(AT, "hooks", _name), os.path.join(BROKEN, "hooks", _name))
with open(os.path.join(BROKEN, ".git"), "w") as f:
    f.write("gitdir: %s\n" % os.path.join(TMP, "no-such-git-dir"))
LEDGER_WORDS = "could not be read"
_got, _piped = call("cat run-plans.sh | bash", hook=HOOK_BROKEN, root=BROKEN, profile=LOCAL)
check("H14. unreadable ledger: a build script piped into a shell is the role deny (got %s)" % _got,
      _got == D and LEDGER_WORDS in _piped, _piped)
for _line in ("bash < run-plans.sh", "sh <> agentTooling/run-plans.sh", "bash 3< feature-close.sh",
              "bash<'run-batch.sh'", "< ./run-plans.sh bash", "cat run-plans.sh | unshare sh",
              "./run-plans.s[^x] --self x", "GIT_EDITOR='./run-p*.sh' git commit",
              # round 2 (the audit's E2 and E3): prompts on round 1's hook, and bash ran each
              "ls # x \\\n./run-plans.sh", "ls #a\\\n\\\n./run-plans.sh",
              "ls #\\\ncat run-plans.sh | unshare sh", "a=(x)#b; ./run-plans.sh",
              # more comments in doubt than the walk reads: a line the judge cannot read is a run
              "echo { # '\n" * 6 + "./run-plans.sh"):
    for _attempt in range(3):
        _got, _reason = call(_line, hook=HOOK_BROKEN, root=BROKEN, profile=LOCAL)
    check("H14. unreadable ledger: %r gets the deny the piped script gets, and keeps it (got %s)"
          % (_line, _got), _got == D and _reason == _piped, _reason)
for _line in ("cat < run-plans.sh", "wc -l < run-plans.sh", "grep -c x run-plans.sh | sort"):
    _got, _reason = call(_line, hook=HOOK_BROKEN, root=BROKEN, profile=LOCAL)
    check("H14. unreadable ledger: a read of a build script is not refused: %r (got %s)"
          % (_line, _got), _got != D, _reason)
# H5 (rounds 12-13's audits): the unreadable-ledger fail-closed rule — with the role ledger
# unreadable, a RAW command holding a substitution, a heredoc or herestring, $'…'/$"…" or ${…}
# is refused outright (build_script_denial, with UNREADABLE_LEDGER_REASON naming the fix)
_PAYLOAD = {"tool_name": "Bash", "session_id": "h5"}
for _line in ('ls "$(./run-plans.sh --self x)"',                               # round 12 B1
              "ls `./run-plans.sh --self x`",
              'git log "$(./run-plans.sh --self x)"',
              "cat <(./run-pl?ns.sh --self x)",
              "git commit -m \"$(cat <<EOF\n$(./run-plans.sh --self x)\nEOF\n)\"",  # round 13 A
              "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\n./run-plans.sh --self x\nEOF\n)\"",
              "ls '$' \"$(./run-plans.sh --self x)\" ''",                       # round 13 B
              'ls $"x" ./run-plans.sh',
              'ls "$(./run-pla$(:)ns.sh --self x)"',                            # round 13 C
              'ls "$(./run-plan[s$].sh --self x)"',
              'ls "$(./run-plans.${SHELL: -2} --self x)"',                      # round 13 D
              "cat <<< x",
              # round 3 (the audit's R2-1 and R2-2 with a build script, and a split operator):
              # the operator is looked for as bash reads it, the continuation deleted
              "cat <<EOF\nx\nEO\\\nF\n./run-plans.sh\nEOF",
              "cat <\\\n(cat <<EOF\nx\nEOF ) ; ./run-plans.sh\nEOF\n)",
              "cat <\\\n<EOF\nit's\nEOF\n./run-plans.sh", "cat <\\\n<\\\n< x",
              "git commit -m \"$(cat <<'EOF'\nfix: x\nEOF\n)\""):
    check("H5. an unreadable ledger refuses %r with the reason naming the fix" % _line,
          _hook.build_script_denial(_line, _PAYLOAD) == _hook.UNREADABLE_LEDGER_REASON)
for _line in ("ls", "git status", "grep -n run-plans.sh README.md", "git log --oneline -3"):
    check("H5. an unreadable ledger leaves a plain read alone: %r" % _line,
          _hook.build_script_denial(_line, _PAYLOAD) is None)
check("H5. the reason names the repair and the rewrite",
      ".git" in _hook.UNREADABLE_LEDGER_REASON and "without the substitution or heredoc"
      in _hook.UNREADABLE_LEDGER_REASON)

# ── T. the table ─────────────────────────────────────────────────────────────
TABLE = [
    # reads: approved in both
    ("git status", A, A),
    ("git log --oneline -3", A, A),
    ("git branch --show-current", A, A),
    ("git diff HEAD --stat", A, A),
    # the decided differing cases
    ("git switch main", P, D),
    ("git checkout -b x", D, D),
    # round 2: a push whose destination is `main` is refused in BOTH profiles, every
    # spelling, read from the words alone (SPEC.md → "Round 2")
    ("git push origin main", D, D),
    ("git push -u origin main", D, D),
    ("git push origin HEAD:main", D, D),
    ("git push origin x:main", D, D),
    ("git push origin +main", D, D),
    ("git push origin +HEAD:main", D, D),
    ("git push origin refs/heads/main", D, D),
    ("git push origin HEAD:refs/heads/main", D, D),
    ("git push origin main:main", D, D),
    ("git push --repo origin main", D, D),
    ("git push --repo=origin main", D, D),
    ("git push origin :main", D, D),
    ("git push --delete origin main", D, D),
    ("git push -d origin main", D, D),
    ("git push origin main --dry-run", D, D),
    ("git push origin 'main'", D, D),
    ("git push upstream main", D, D),
    ("git push origin %s main" % BR, D, D),
    ("git -C %s push origin main" % C, D, D),
    ("git status && git push origin main", D, D),
    # ... and nothing that only looks like it: another name, `main` as a SOURCE, a read,
    # a file checkout, text. The cloud keeps round 1's answer for a non-current target.
    ("git push origin mainline", P, D),
    ("git push origin feature/main", P, D),
    ("git push origin main-x", P, D),
    ("git push origin main:x", P, D),
    ("git log main", A, A),
    ("echo 'git push origin main'", A, A),
    ("git commit -m 'git push origin main'", P, P),
    # `--repo <r>` / `--repo=<r>` takes the remote; what follows are refspecs, in both
    # judges. A `--repo` with no value is read, not crashed on.
    ("git push --repo origin x", P, D),
    ("git push --repo=origin x", P, D),
    ("git push --repo origin " + BR, P, P),
    ("git push --repo=origin " + BR, P, P),
    ("git push --repo", P, P),
    ("git push origin --repo", P, P),
    ("git push --repo=", P, P),
    # cases that must not differ
    ("git push", P, P),
    ("git push origin", P, P),
    ("git push origin HEAD", P, P),
    ("git push origin HEAD:" + BR, P, P),
    ("git push origin HEAD:refs/heads/" + BR, P, P),
    # cloud-checkpoint-push: the started feature's own branch — the current branch AND a
    # tracked manifest's branches[0] — is pushed without a prompt in the cloud, in the
    # plain spellings only; locally every one of them still prompts
    ("git push -u origin " + BR, P, A),
    ("git push origin " + BR, P, A),
    ("git push --set-upstream origin " + BR, P, A),
    # own-push-real-gitdir ruling 1: a global option moves the git directory, so `-C` is a prompt
    ("git -C %s push -u origin %s" % (C, BR), P, P),
    ("git -C %s push origin %s" % (C, BR), P, P),
    # locally the line mixes an approved read with a push the human must judge (a rewrite
    # denial); in the cloud the push is approved only as the whole command, so it is sent
    # back to run alone (hook-silent-allow-sweep, item 4)
    ("git status && git push -u origin " + BR, D, D),
    # ... and nothing near it: another branch is refused (round 1), a force or a lease in
    # any spelling is refused in both, and every other shape keeps its prompt
    ("git push -u origin " + OTHER_BR, P, D),
    ("git push --force origin " + BR, D, D),
    ("git push -f origin " + BR, D, D),
    ("git push --force-with-lease origin " + BR, D, D),
    ("git push -u --force origin " + BR, D, D),
    ("git push origin +" + BR, P, P),
    ("git push upstream " + BR, P, P),
    ("git push -u upstream " + BR, P, P),
    ("git push --no-verify origin " + BR, P, P),
    ("git push -u --no-verify origin " + BR, P, P),
    ("git push -o ci.skip origin " + BR, P, P),
    ("git push origin refs/heads/" + BR, P, P),
    ("git push origin %s:%s" % (BR, BR), P, P),
    ("git push --repo origin " + BR, P, P),
    ("git push origin %s %s" % (BR, BR), P, P),
    ("git push origin %s %s" % (BR, OTHER_BR), P, D),
    ("git push -u origin '%s'" % BR, P, A),
    ("git -C %s push -u origin %s" % (os.path.join(C, "agentTooling"), BR), P, P),
    ("git --git-dir=%s push -u origin %s" % (os.path.join(C, ".git"), BR), P, P),
    ("git -c push.default=matching push origin " + BR, P, P),
    # a redirect's descriptor is not a refspec (ablation-harness-fixes): the first push of
    # the current branch with its output folded keeps the prompt in both profiles — the
    # `2` of `2>&1` read as a branch named `2` and the cloud refused it
    # ... and piped, the push is no longer the whole command: a prompt (item 4)
    ("git push -u origin %s 2>&1 | tail -3" % BR, P, P),
    ("git push origin %s 2>&1 | tail -3" % BR, P, P),
    ("git push -u origin %s 2>&1" % BR, P, A),
    ("git push -u origin %s 2>/dev/null" % BR, P, A),
    ("git push 2>&1 | tail -4", P, P),
    ("git push origin x 2>&1 | tail -3", P, D),
    # hook-audit-gaps B2: a QUOTED or ESCAPED digit before a redirect is a word to bash
    # (a branch named `2`), not a descriptor: the push names two branches and is refused
    ("git push origin %s \"2\">/dev/null" % BR, P, D),
    ("git push origin %s \\2>/dev/null" % BR, P, D),
    ("git push -u origin %s \"2\">/dev/null" % BR, P, D),
    # hook-audit-gaps: a force bundled into the short flags (`-fu`, `-uf`) is a force push
    ("git push -fu origin " + BR, D, D),
    ("git push -uf origin " + BR, D, D),
    ("git push -fu origin x", D, D),
    ("git push origin main 2>&1 | tail -3", D, D),
    ("git push -u origin main 2>&1", D, D),
    # every redirect spelling is no refspec and no remote (orchestration-record-fixes): the
    # plain current-branch push and the `-u` one with the output folded or discarded keep
    # the cloud allow; one that writes a file is a write the human judges (prompt, never a
    # deny naming "somewhere else"); a push of `main` or of another branch is refused with
    # the redirect present, in any position
    ("git push origin %s 2>&1" % BR, P, A),
    ("git push origin %s 2> /dev/null" % BR, P, A),
    ("git push 2>&1 origin " + BR, P, A),
    ("git push -u 2>&1 origin " + BR, P, A),
    ("git push -u origin %s 2>&1 | tail -3" % BR, P, P),
    ("git push origin %s > log" % BR, P, P),
    ("git push -u origin %s > log" % BR, P, P),
    ("git push origin %s >out" % BR, P, P),
    ("git push origin %s >> log" % BR, P, P),
    ("git push origin %s &>x" % BR, P, P),
    ("git push origin %s < in" % BR, P, P),
    ("git push origin %s 2>&1 >out" % BR, P, P),
    ("git push origin main 2>&1", D, D),
    ("git push origin main > log", D, D),
    ("git push origin main 2>/dev/null", D, D),
    ("git push 2>&1 origin main", D, D),
    ("git push origin other 2>&1", P, D),
    ("git push origin other > log", P, D),
    ("git push origin other &>x", P, D),
    ("git push origin other < in", P, D),
    # the audit of the above: a quoted word is no operator and no descriptor. A quoted
    # separator word is never approved (bash hands it to git as an argument, so what follows
    # it is the same command's words); a quoted digit before `>` is an argument, so it
    # shifts nothing (`-C '1'>x push …` is a push of main, not `-C push`)
    ("git branch ';'", D, D),
    ("git push origin %s ';'" % BR, P, D),
    ("git push -u origin %s '|' 2>&1" % BR, P, D),
    ("git push origin %s ';' ls :main" % BR, D, D),
    ("git push origin %s '&&' ls HEAD:main" % BR, D, D),
    # the independent audit of #139 (F1-F6). F1: a quoted or escaped operator word is a word on
    # the deny side too; F2: a separator glued to a redirect still starts a new command;
    # F3: `<(…)`/`>(…)` is a word of the command around it; F4: `{fd}>` is a descriptor;
    # F5: a digit run past a C int is a word; F6: a grep pattern `'\(' is no operator
    ("git push > ';' origin HEAD:main", D, D),
    ("git push 2>';' origin HEAD:main", D, D),
    ("git push -o ';' origin HEAD:main", D, D),
    ("git push -o '>' origin HEAD:main", D, D),
    ("git push -o \\; origin HEAD:main", D, D),
    ("git push 2> '&&' origin HEAD:other", P, D),
    ("true;>x git push origin HEAD:main", D, D),
    ("ls|>x git push origin HEAD:main", D, D),
    ("ls;>x git push origin HEAD:main", D, D),
    ("ls&&>x git push origin HEAD:main", D, D),
    # F3 is the fail-closed rule's since round 9: a `<(…)`/`>(…)` line with a git word is not
    # read finely, so the plain reading's cut at the paren leaves a prompt — never an allow
    ("git push -o >(cat) origin HEAD:main", P, P),
    ("git push > >(cat) origin HEAD:main", P, P),
    ("git -c a.b=>(cat) push origin HEAD:main", P, P),
    ("git push --repo=<(cat) origin main", P, P),
    ("git push origin HEAD:main {fd}>/dev/null", D, D),
    ("git --work-tree 99999999999>/dev/null push origin HEAD:main", D, D),
    ("git push -o 99999999999>/dev/null origin HEAD:main", D, D),
    # THE FAIL-CLOSED RULE (round 9, replacing rounds 3-8's scoped and crude readings): a line
    # holding a git word and a `$(…)`, a backtick, `<(`/`>(`, a `<<` or the word `case` —
    # quoted or not — is never approved. The deny side has one plain reading (every operator
    # ends a command; a quoted word is one word): what it finds is denied, what it misses
    # inside a quoted substitution or a `case` arm prompts, as on origin/main
    ('echo "$(git push origin HEAD:main)"', P, P),
    ('echo "`git push origin HEAD:main`"', P, P),
    ("echo `git push origin HEAD:main`", P, P),
    ("echo $(git push origin HEAD:main)", D, D),
    ('echo "a$(ls)b" && git push origin HEAD:main', D, D),
    ('echo "$(echo "x")" ; git push origin main', D, D),
    ("git $(true) push origin HEAD:main", P, P),
    ("git $(echo x) reset --hard", P, P),
    ("git $(echo reset --hard) status", P, P),
    ("echo '$(git push origin main)'", P, P),
    ("git log --grep '$(x)' -1", P, P),
    ("git log --grep case -1", P, P),
    ("git log -1 --format='`x`'", P, P),
    ('echo "no subst (here)"; git push origin main', D, D),
    ('git push -u origin "$(git branch --show-current)"', P, D),
    ('''git commit -m "$(cat <<'EOF'\nfix\n\ngit push origin main is denied\nEOF\n)"''', P, P),
    ("ls $(echo x)", P, P),
    # round 8's B1: a quoted or escaped `<<`, and a `<<<` herestring, is no heredoc — the git
    # deny reads the line as before. A real heredoc's own line is read; its body is not
    ("echo '<<' ; git push origin main", D, D),
    ("echo \\<\\< ; git push origin main", D, D),
    ("echo '<<-' ; git push origin main", D, D),
    ("git push -o '<<' origin main", D, D),
    ("git push origin HEAD:main -o \\<\\<", D, D),
    ("echo '<<' ; git reset --hard HEAD~1", D, D),
    ("echo '<<' ; git branch -D x", D, D),
    ("echo '<<' ; git push origin other-branch", P, D),
    ("git push origin other-branch -o '<<'", P, D),
    ("cat <<< x; git push origin main", D, D),
    ("cat <<< x; git reset --hard HEAD~1", D, D),
    ("cat <<< x; git push origin other-branch", P, D),
    ("git push origin main <<EOF\nx\nEOF", D, D),
    ("git push origin main <<EOF\ndon't\nEOF", D, D),
    ("cat <<'EOF' ; git push origin main", D, D),
    ("cat <<EOF\ngit push origin main\nEOF", P, P),
    # what FOLLOWS a heredoc's body is a command, however the operator is spelled (hook-audit-gaps,
    # F1: it was a prompt on origin/main and a deny only for a glued `;<<`)
    ("cat <<EOF\nx\nEOF\ngit push origin main", D, D),
    ("true;<<EOF cat\nx\nEOF\ngit push origin main", D, D),
    ("true&&<<EOF cat\nx\nEOF\ngit push origin main", D, D),
    ("cat <<EOF\nx\nEOF)\ngit push origin main", D, D),
    ("cat <<EOF\nx\nEOF\n./agentTooling/feature-start.sh zz", P, P),
    # hook-audit-gaps, phase 3 (the self-audit; NOTES.md's probe table has each row's verdict
    # before it: a prompt, or — the shifts, the backtick run-on — an opaque rewrite deny, which
    # decays to an ask and is R8's to tell apart). F1/B1: a body is placed only where bash
    # places it — a delimiter bash reads differently (`EOF\r`, a backtick span, `$"x"`), a `<<`
    # that is a shift, a comment after a `$(…)` body, a top-level `EOF)` line, a whole-argument
    # body holding a quote — and what follows it is read
    ("cat <<EOF\r\nx\r\nEOF\r\ngit push --force origin x #\r\nEOF\nls", D, D),
    ("cat <<`a b`\nx\n`a b`\ngit push --force origin x\n`a\nls", D, D),
    ("cat <<$\"x\"\nq\nx\ngit push --force origin x\n$x\nls", D, D),
    ("echo $((1<<2))\ngit push --force origin x\n2\nls", D, D),
    ("(( x = 1 << 2 ))\ngit push --force origin x\n2\nls", D, D),
    ("echo $[1<<2]\ngit push --force origin x\n2]\nls", D, D),
    ("a[1<<2]=5\ngit push --force origin x\n2]=5\nls", D, D),
    ("echo $(cat <<EOF\nx\nEOF) # c\ngit push --force origin x\nEOF\n", D, D),
    ("cat <<EOF\nit's\nEOF)\nEOF\ngit push --force origin x", D, D),
    ("echo ${HOME:1<<2}\ngit push --force origin x\n2}\nls", D, D),
    ("cat <<EOF $(echo a\ngit push --force origin x\nEOF\n)\nls", D, D),
    # inside a substitution bash 5.2 ends the body at `EOF)` (and at `EOF` before a backtick)
    # and runs the rest of that line; an older bash reads on. Both readings are judged
    ("echo $(cat <<EOF\nit's\nEOF) ; git push --force origin x\nEOF\n", D, D),
    ("echo `cat <<EOF\nx\nEOF` ; git push --force origin x\nEOF\n", D, D),
    ("git commit -m \"$(cat <<'EOF'\na \" b\nEOF)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    # ... and outside a substitution `EOF)` is body to every bash: no deny on a guess (this row
    # was one), nor on a quoted-delimiter message's text
    ("cat <<EOF\nEOF) git stash\nEOF\nls", P, P),
    ("git commit -m \"$(cat <<'EOF'\n\" $(git push --force origin x)\nEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<'EOF'\na \" b\nEOF\n)\" ; git push --force origin x", D, D),
    ("git commit -m \"$(cat <<'EOF'\nfix \"#12\nEOF\n)\" ; git push --force origin x", D, D),
    ("git commit -m \"$(cat <<'EOF'\nit's \"q\nEOF\n)\"", P, P),
    # ... and a line bash keeps in the body stays there
    ("cat <<EOF\nx\nEOF \ngit push --force origin x\nEOF\nls", P, P),
    ("cat <<-EOF\n\tx\n \tEOF\ngit push --force origin x\n\tEOF\nls", P, P),
    # A: a `#` is a comment only where bash starts one — not after an escaped blank or operator,
    # not after a carriage return, not inside a word or `${…}` — and inside backticks only up to
    # the closing one; a `$'` in a comment opens nothing. A `#` inside a word no longer leaves
    # the line unjudged (`git push --force origin x a#b` lost its deny to it)
    ("echo a\\ # ; git push --force origin x", D, D),
    ("echo \\;# ; git push --force origin x", D, D),
    ("echo a\r# ; git push --force origin x", D, D),
    ("echo a#b ; git push --force origin x", D, D),
    ("git push --force origin x a#b", D, D),
    ("echo $# ; git push --force origin x", D, D),
    ("echo ${x#y} ; git push --force origin x", D, D),
    ("echo ${x:- #y} ; git push --force origin x", D, D),
    ("echo 'a'#b ; git push --force origin x", D, D),
    ("echo `echo a # b` ; git push --force origin x", D, D),
    ("echo `# x`; git push --force origin x", D, D),
    ("git push --force origin x # $'", D, D),
    ("echo $'a' # '\ngit push --force origin x", D, D),
    ("ls \r ; git push --force origin x # '", D, D),
    # ... and a real comment still holds no command
    ("echo 'a' #b ; git push --force origin x", P, P),
    ("echo a # `; git push --force origin x`", P, P),
    ("git log --oneline -3 a#b", A, A),
    # ROUND 2 (escalations/01-review-opus.md item 1, 01-audit-opus.md E1 and E3; NOTES.md,
    # coordinator ruling 7: where bash could read a stretch of text two ways, both are judged).
    # Item 1: only a `${` nests inside `${…}`
    ("echo ${x:-{} ; git push --force origin x # '", D, D),
    ("echo ${x:-${y:-{}}} ; git stash # it's", D, D),
    # E1: inside a substitution bash 5.2 ends a heredoc at ANY body line that begins with the
    # delimiter and goes on to a `)` — a blank, a word character or a quote may come between —
    # and inside backticks at the closing backtick, whatever the line holds
    ("git commit -m \"$(cat <<'EOF'\nx\nEOF )\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("git commit -m \"$(cat <<'EOF'\nx\nEOF\t)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("git commit -m \"$(cat <<'EOF'\nx\nEOF x)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("git commit -m \"$(cat <<'EOF'\nx\nEOFS)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOFxyz ; true)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF a b c)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF'q')\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<-'EOF'\nx\n\tEOF x)\" ; git push --force origin x ; echo \"\nEOF\n)\"", D, D),
    ("echo $(cat <<EOF\nx\nEOF ) ; git push --force origin x\nEOF\n)", D, D),
    ("cat <(cat <<EOF\nx\nEOF x) ; git push --force origin x\nEOF\n)", D, D),
    ("echo `cat <<EOF\nx\nEOF ` ; git push --force origin x\nEOF\n`", D, D),
    ("echo `cat <<EOF\nx\nfoo` ; git push --force origin x\nEOF\n`", D, D),
    ("echo `cat <<EOF\nx\nEOF\"` ; git push --force origin x\nEOF\n`", D, D),
    # ... at the first run-on line a `)` follows on, which need not be the first run-on line;
    # past MAX_RUN_ON_LINES of them a line naming git is refused, never passed on
    ("echo $(cat <<EOF\nEOFS\nEOF git push --force origin x)", D, D),
    ("echo $(cat <<EOF\nEOFa it's\nEOF ) ; git push --force origin x", D, D),
    ("echo \"$(cat <<'EOF'\nEOF \"\nEOF)\" ; git push --force origin x", D, D),
    ("git commit -m \"$(cat <<'EOF'\nEOF \"\nEOF \"\nEOF \"\nEOF)\" ; git push --force origin x", D, D),
    ("echo $(cat <<EOF\nEOFa\nEOFb\nEOFc\nEOFd\nEOFe\nEOF git push --force origin x)", D, D),
    # ... and to the main parser such a line is still body: no deny on a guess
    ("cat <<EOF\nx\nEOF )\ngit push --force origin x\nEOF\nls", P, P),
    ("cat <<EOF\nx\nEOFS)\ngit push --force origin x\nEOF\nls", P, P),
    # E3: a `#` right after a `)` that closed a word starts no comment (`a=(x)#b` is one word),
    # nor does one after a blank in an arithmetic expression or a subscript, nor one inside a
    # quote nested in a quoted substitution; one after an escaped line break does. Past an
    # opener the walk cannot tell, so each such `#` is read both ways, on its own
    ("a=(x)#b; git push --force origin y", D, D),
    ("echo $(echo a)#b; git push --force origin y", D, D),
    ("echo <(true)#b; git push --force origin y", D, D),
    ("echo $((1))#b; git push --force origin y", D, D),
    ("a=(x)#b; git push --force origin y # '", D, D),
    ("git push --force origin y; (ls)# it's", D, D),
    ("echo $((1 #b))\ngit push --force origin y", D, D),
    ("a[1 #b]=5\ngit push --force origin y", D, D),
    ("echo \"`echo \" #\"`\"; git push --force origin y", D, D),
    ("echo \"$(echo \" #\")\"; git push --force origin y", D, D),
    ("git push --force origin y \\\n# it's", D, D),
    # `$$` is the PID: `$$'a\'` is a plain quote, and the `#'` after the push a comment
    ("echo $$'a\\' ; git push --force origin y #'", D, D),
    # the cost of reading both ways: a comment bash does start, past an opener, is also read as
    # commands (bash runs none of these pushes)
    ("(ls)#b; git push --force origin y", D, D),
    ("(ls) # then; git push --force origin y", D, D),
    # ... and with no opener before it a comment is certain, as in the rows above
    ("ls src # then; git push --force origin y", P, P),
    # more comments in doubt than are read: a line naming git is refused, never passed on
    ("(a) #b\n(a) #b\n(a) #b\n(a) #b\n(a) #b\n(a) #b\ngit push --force origin y # '", D, D),
    # ROUND 3 (escalations/02-review-opus.md item 1; 02-audit-opus.md R2-1, R2-2, R2-3): bash
    # deletes a line continuation before it reads the construct around it. R2-1: an unquoted
    # delimiter's body ends at a terminator joined across one (each was a prompt, and bash ran
    # the push)
    ("cat <<EOF\nEO\\\nF\ngit push --force origin y\nEOF", D, D),
    ("cat <<EOF\nx\nEO\\\nF\ngit push --force origin y\nEOF", D, D),
    ("echo \"$(cat <<EOF\nEO\\\nF\ngit push --force origin y\nEOF\n)\"", D, D),
    ("cat <<EOF\nx\nEOF\\\n\ngit push -f origin y\nEOF", D, D),
    ("cat <<-EOF\nx\n\tEO\\\nF\ngit push -f origin y\nEOF", D, D),
    ("ls; cat <<EOF\nx\nE\\\nO\\\nF\ngit push -f origin y\nEOF", D, D),
    ("cat <<EOF\nx\nEO\\\nF\ncd /tmp && ls\nEOF", D, D),
    ("cat <<EOF\nx\\\nEOF\nit's\nEOF\ngit push -f origin y", D, D),
    # ... a quoted delimiter joins nothing, nor does an escaped backslash: bash runs no push
    ("cat <<'EOF'\nEO\\\nF\ngit push -f origin y\nEOF", P, P),
    ("cat <<'EOF'\nx\nEO\\\nF\ngit push -f origin y\nEOF", P, P),
    ("cat <<EOF\nx\nEO\\\\\nF\ngit push -f origin y\nEOF", P, P),
    # ... and the reading that joins nothing is kept (the audit's tc3: denied before the round,
    # and bash runs no push — the cost of a round that only adds denies)
    ("cat <<EOF\nx\\\nEOF\ngit push -f origin y\nEOF", D, D),
    # R2-2: a substitution opener split by a continuation (the audit's cs3/ps1, ps5, ps6, ps7,
    # then the twins other paths denied), and the arithmetic openers before a `<<`
    ("cat <\\\n(cat <<EOF\nx\nEOF ) ; git push -f origin y\nEOF\n)", D, D),
    ("cat <\\\n(cat <<'EOF'\nx\nEOF) ; git push -f origin y\nEOF\n)", D, D),
    ("cat <\\\n(cat <<EOF\nx\nEOF ) ; git reset --hard\nEOF\n)", D, D),
    ("cat <\\\n(cat <<EOF\nx\nEOF ) ; git branch -D main\nEOF\n)", D, D),
    ("echo $\\\n(cat <<EOF\nx\nEOF ) ; git push -f origin y\nEOF\n)", D, D),
    ("echo >\\\n(cat <<EOF\nx\nEOF ) ; git push -f origin y\nEOF\n)", D, D),
    ("(\\\n( x = 1<<2 ))\ngit push -f origin y\n2", D, D),
    ("a[1\\\n<<2]=5\ngit push -f origin y\n2]=5", D, D),
    # the rest of the class: a split operator, delimiter, and whole-argument head or tail
    ("cat <\\\n<EOF\nit's\nEOF\ngit push -f origin y", D, D),
    ("cat <<E\\\nOF\nit's\nEOF\ngit push -f origin y", D, D),
    ("cat <<'EOF'\\\n\nit's\nEOF\ngit push -f origin y", D, D),
    ("git commit -m \"$\\\n(cat <<'EOF'\na \" b\nEOF\n)\" ; git push -f origin y", D, D),
    ("git commit -m \"$(cat <<'EOF'\na \" b\nEOF\n\\\n)\" ; git push -f origin y", D, D),
    ("echo `cat <<'EOF'\nEO\\\nF\ngit push -f origin y\nEOF\n`", D, D),
    # R2-3: the own-assignment deny reads every reading
    ("a=(x)#b; X=/p; cat $X/f", D, D),
    # ROUND 4 (escalations/03-audit-opus.md). R3-1: inside `"$(cat <<…)"` bash ends the body
    # at a run-on line and runs what follows; an odd `"` after it leaves the reading the walk
    # builds one no reader can lex. It was dropped (each a prompt, and bash ran the push): now
    # a git command that cannot be read (w1, w2, o13p, w11, w12, w8, w9, x3, x4, x8, o13,
    # o13s, o13t, o13v, o13u)
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<\"EOF\"\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOFS)\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<-EOF\nx\n\tEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF )\" ; git reset --hard\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF )\" ; git branch -D main\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y # \nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y ; echo \\\"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF \\\n)\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEO\\\nF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF\\\n )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF\\\n)\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("git commit -m \"$(cat <<EOF\nx\nEOF \\\n)\" ; git push -f origin y\nEOF\n)\"", D, D),
    # ... w10, w14 and the controls. w10 and w14 name no git, so they take the deny a line
    # with an open quote takes — a rewrite deny, which counts attempts, so each sits behind
    # a deny that clears the count, as x7 (a plain line with an open quote, denied the same
    # way before the round) does. w4, x1 and x5 are balanced for bash and were denied already
    ("echo \"$(cat <<EOF\nx\nEOF )\" ; cd /tmp && ls\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF )\" ; git push -f origin y ; echo \"\nEOF\n)\"", D, D),
    ("echo \"$(cat <<EOF\nx\nEOF )\"; X=/p; cat $X/f\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y ; : '\nEOF\n)\"'", D, D),
    ("git push -f origin y\necho '", D, D),
    ("echo \"$(cat <<'EOF'\nx\nEOF )\" ; git push -f origin y ; cat <<'Z'\nEOF\n)\"\nZ", D, D),
    # ... the same rule for every reading the walk builds: a placed body, a stood-in
    # heredoc, a dropped comment
    ("cat <<EOF\nx\nEOF\ngit push -f origin y\necho '", D, D),
    ("git commit -m \"$(cat <<'EOF'\nm\nEOF\n)\"\ngit push -f origin y\necho '", D, D),
    ("git push -f origin y # \\\n'", D, D),
    # R3-2: ruling 45's opened head, spelled as bash also reads it (o3, o3p)
    ("echo \"$( cat <<EOF\nx\nEO\\\nF\ngit push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$( cat <<EOF\nx\nEOF\ngit push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(\tcat  <<\tEOF\nx\nEOF\ngit push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat<<EOF\nx\nEOF\ngit push -f origin y\nEOF\n)\"", D, D),
    # ... and the usual message and PR body, quotes and all, are what they were
    ("git commit -m \"$(cat <<'EOF'\nfix: it's \"quoted\", `ticked` and $(sub)\n\nbody's \"x\nEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<'EOF'\nan odd \" here\nEOF\n)\"", P, P),
    ("gh pr create --title t --body \"$(cat <<'EOF'\nit's a \"body\nEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<EOF\nan odd \" here\nEOF\n)\"", P, P),
    # ROUND 5 (escalations/04-audit-opus.md, R4-1): a whole-argument head whose delimiter is
    # no bare or fully quoted identifier was neither stood in nor opened — one quoted word,
    # a prompt, and bash ran what followed `)"`. It is not read for a message at all: a git
    # command that cannot be read (p4, p5, p2, p3, p6, p7, p8, p13)
    ("echo \"$(cat <<E'O'F\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<E\"O\"F\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<E\"O\"F\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<E'O'F\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<'E'OF\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<E\\OF\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("git commit -m \"$(cat <<E\"O\"F\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<E'O'F\nx\nEOF )\" ; git reset --hard\nEOF\n)\"", D, D),
    # ... the empty delimiter (e5, e6, e8, e9, e11, e14); e12 names no git and takes the
    # tokenize deny, a rewrite deny, so it sits behind a deny that clears the count
    ("echo \"$(cat <<''\nx\n)\" ; git push -f origin y\n\n)\"", D, D),
    ("echo \"$(cat <<''\nx\n )\" ; git push -f origin y\n\n)\"", D, D),
    ("echo \"$(cat <<''\nx\"\n\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<\"\"\nx\n )\" ; git push -f origin y\n\n)\"", D, D),
    ("echo \"$(cat <<''\nx\n)\" ; git reset --hard\n\n)\"", D, D),
    ("echo \"$(cat <<''\nx\n)\" ; cd /tmp && ls\n\n)\"", D, D),
    ("echo \"$(cat <<-''\nx\n\t)\" ; git push -f origin y\n\n)\"", D, D),
    # ... the canonical message shape (c5, c6, c8, c10, c12, c13, c22) and run-on twins (rN)
    ("echo \"$(cat <<'E O F'\nx\"\nE O F\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<EO'F'\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<\"E\"'O'F\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<E-F\nx\"\nE-F\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<123\nx\"\n123\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<'EOF '\nx\"\nEOF \n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<'E)F'\nx\"\nE)F\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<E-F\nx\nE-F )\" ; git push -f origin y\nE-F\n)\"", D, D),
    ("echo \"$(cat <<'E)F'\nx\nE)F )\" ; git push -f origin y\nE)F\n)\"", D, D),
    ("echo \"$(cat <<\\E\\O\\F\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$(cat <<''EOF\nx\nEOF )\" ; git push -f origin y\nEOF\n)\"", D, D),
    ("echo \"$( cat <<E'O'F\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    # ... the controls, denied before the round (q5, c1, p1, e7)
    ("echo \"$(cat <<'EOF'\n\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<EOF\nx\"\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<E\"O\"F\nx\nEOF\n)\" ; git push -f origin y", D, D),
    ("echo \"$(cat <<''\nx\n\n)\" ; git push -f origin y", D, D),
    # ... round 4's two documented over-denies, pinned (round 4's review): bash runs no
    # denied command on either. The second names no git: the tokenize deny, behind a deny
    ("git commit -m \"$(cat <<'EOF'\nEOF notes\nit's fine\nEOF\n)\"", D, D),
    ("cat <<EOF\nx\nEOF\necho \"$(grep \"don't\" f)\"", D, D),
    # ... and the usual message under each delimiter one is written with stays where it was
    ("git commit -m \"$(cat <<\"EOF\"\nit's an odd \" here\nEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<-EOF\n\tit's \"here\"\n\tEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<-'EOF'\n\tan odd \" here\n\tEOF\n)\"", P, P),
    ("gh pr create --title t --body \"$(cat <<EOF\nit's a body\nEOF\n)\"", P, P),
    ("git commit -m \"$(cat <<'EOF'\nthe head \"$(cat <<E'O'F is refused\nEOF\n)\"", P, P),
    ("echo \"$(cat <<<\"x\")\"", P, P),
    # ROUND 6 (escalations/05-audit-opus.md, B1): a git command on line 1, then a later line
    # whose quote never closes. Bash runs line 1 before the parse error; a `<<` or a `#` in
    # the raw text, inside the open quote too, excused the line from the tokenize deny — a
    # prompt. A line that names git and that no reading tokenizes is a git command that
    # cannot be read, whatever it holds: the audit's six first lines × its four reproductions
    *[(first + "\n" + tail, D, D)
      for first in ("git push -f origin y", "git push origin main", "git reset --hard",
                    "git clean -fdx", "git branch -D y", "git stash drop")
      for tail in ("echo '#", "echo \"$(cat <<EOF", "gh pr create --body \"$(cat <<'EOF'\nx",
                   "echo '<<")],
    # ... the audit's other tails of the family, and its row with a quoted `<<` before
    ("git push -f origin y\n\"$(cat <<EOF", D, D),
    ("git push -f origin y\necho \"$(cat <<'EOF'", D, D),
    ("git push -f origin y\necho \"$(cat <<'EOF'\nbody", D, D),
    ("git push -f origin y\necho \"#", D, D),
    ("git push -f origin y\necho a#'", D, D),
    ("git push -f origin y\n: '<<", D, D),
    ("echo '<<'\ngit push -f origin y\necho '", D, D),
    ("g\\it push -f origin y\necho '#", D, D),
    # ... with neither a `<<` nor a `#` (the tokenize deny before, which decays), on one line
    # too; a read on line 1, refused with the line; a message whose terminator was dropped
    ("git reset --hard\necho \"x", D, D),
    ("git rebase 'main", D, D),
    ("git status\necho '#", D, D),
    ("git commit -m \"$(cat <<'EOF'\nmsg, the terminator dropped", D, D),
    # ... a body no reading places (a heredoc never terminated) whose text holds an odd quote
    ("cat <<Z\nx\nZ\ngit push -f origin y\ncat <<EOF\necho '", D, D),
    ("git reset --hard\ncat <<EOF\nit's", D, D),
    # ... and the same tails on a line that names no git keep the prompt they had, as does
    # what bash tokenizes: a quote in a comment, a placed body, an ANSI-C quote
    ("ls\necho '#", P, P),
    ("cat README.md\necho \"$(cat <<EOF", P, P),
    ("gh pr create --body \"$(cat <<'EOF'\nx", P, P),
    ("touch x '<<", P, P),
    ("git status # it's", P, P),
    ("cat <<'EOF'\ngit rebase 'main\nEOF", P, P),
    ("git commit -m $'it\\'s'", P, P),
    # ROUND 7 (escalations/06-audit-opus.md, B1): the same line with one `$'…'` that escapes a
    # quote on it, which round 6 excused whether bash could parse the line or not — still a
    # prompt, and bash still ran line 1. Bash is asked (`bash -n`): a line that names git,
    # that no reading judges and that bash refuses is a git command that cannot be read. The
    # audit's five first lines × its five second lines
    *[(first + "\n" + tail, D, D)
      for first in ("git push -f origin y", "git push origin main", "git reset --hard",
                    "git clean -fdx", "git branch -D y")
      for tail in ("echo $'\\'' \"", "echo $'\\'' '", "echo $'\\'' \"$(cat <<EOF",
                   ": $'a\\'b' \"x", "echo ${x:-$'\\''} \"")],
    # ... the escaped quote on a complete line of its own, and the audit's other variants
    ("echo $'\\''\ngit push -f origin y\necho \"", D, D),
    ("git push -f origin y\necho $'\\''\necho \"", D, D),
    ("git push -f origin y\necho $'\\'' '#", D, D),
    ("git push -f origin y\necho $'\\'' \"\n#", D, D),
    ("git push -f origin y\necho $(echo $'\\'') \"", D, D),
    ("echo $'\\''; git push -f origin y\necho \"", D, D),
    ("g\\it push -f origin y\necho $'\\'' \"", D, D),
    ("git push -f origin y\ngh pr create --body $'it\\'s' \"$(cat <<'EOF'\nx\n", D, D),
    # ... (escalations/06-review-opus.md) and what bash parses is not that deny: a quoted
    # substitution whose inner quotes hold an odd quote is the does-not-tokenize deny round 5
    # gave it — a rewrite deny, so each sits behind a deny that clears the count — or, with
    # a `#` in its text, the prompt; a well-formed ANSI-C quote after a push is the prompt
    ("git commit -m \"$(echo \"it's\")\"", D, D),
    ("git push -f origin y\necho $'\\'' \"", D, D),
    ("git commit -m \"$(printf \"%s\" \"don't\")\"", D, D),
    ("git commit -m \"$(echo \"it's #1\")\"", P, P),
    ("git push -f origin y\necho $'\\''", P, P),
    ("ls\necho $'\\'' \"", P, P),
    # F2: the deny expands what bash expands — nested groups, `{a..c}` sequences — and a git
    # command whose braces expand past the cap is refused, not passed on (locally the nested and
    # past-the-cap rows were the brace REWRITE before, which decays: R8 asserts the reason)
    ("git push --forc{e,{x,y}} origin z", D, D),
    ("git push --{force,{quiet,verbose}} origin x", D, D),
    ("git push --forc{e..e} origin x", D, D),
    ("git push --forc{e,{a}} origin x", D, D),
    ("git reset --har{d..d}", D, D),
    ("git checkout -{b..b} x", D, D),
    ("git stash {pop,list}", D, D),
    ("git push --forc{e,x}{,a}{,b}{,c}{,d}{,e}{,f}{,g}{,h} origin x", D, D),
    ("git push --forc{{1..300},e} origin x", D, D),
    ("git stash {list,show}", P, P),
    ("git log -1 {a..c}", P, P),
    ("git status {a,b}", A, A),
    ("git log --grep '<<' -1", P, P),
    # round 8's B5 (a redirect before the command in the crude reading): the crude reading is
    # gone; unquoted, the plain reading drops the redirect and denies, quoted it prompts
    ("echo $(! case x in x) 2>&1 git push origin main;; esac)", D, D),
    ("echo $(! case x in x) >x git push origin main;; esac)", D, D),
    ('echo "$(! case x in x) 2>&1 git push origin main;; esac)"', P, P),
    ('echo "$(case x in x|esac) 2>&1 git push origin main;; esac)"', P, P),
    ('echo "$(! case x in x) >&2 git push origin main;; esac)"', P, P),
    ('echo "$(! case x in x) 2>&1 git stash;; esac)"', P, P),
    ('echo "$(! case x in x) 2>&1 git push origin HEAD:other;; esac)"', P, P),
    # round 4's audit (B1): unquoted, a `case` arm's `)` ends a command in the plain reading
    ("echo $(case x in x) git push origin main;; esac)", D, D),
    ("echo `case x in x) git push origin main;; esac`", D, D),
    ("cat <(case x in x) git push origin main;; esac)", D, D),
    ("echo $(case x in x) git reset --hard HEAD~1;; esac)", D, D),
    ("echo $(case x in x) git push origin HEAD:other;; esac)", P, D),
    ("echo $(case x in x) git switch main;; esac)", P, D),
    # rounds 5-7 (B2, B3a, B3b, B4): the same shapes inside double quotes, after a reserved
    # word, with an `esac` pattern or a quoted word — the fail-closed rule's: a prompt, never an
    # allow (they prompted on origin/main too)
    ('echo "$(case x in x) git push origin main;; esac)"', P, P),
    ('echo "`case x in x) git push origin main;; esac`"', P, P),
    ('echo "x$(case x in x) git push origin main;; esac)y"', P, P),
    ('echo "$(case x in x) git reset --hard HEAD~1;; esac)"', P, P),
    ('echo "$(case x in x) git push origin HEAD:other;; esac)"', P, P),
    ('echo "$(case x in x) git stash;; esac)"', P, P),
    ('X="$(case x in x) git push origin main;; esac)"', P, P),
    ('echo $(case x in x) echo "$(case y in y) git push origin main;; esac)";; esac)', P, P),
    ("echo $(case x in (x) git push origin main;; esac)", D, D),
    ('echo "$(if true; then case x in x) git push origin main;; esac; fi)"', P, P),
    ('echo "$(! case x in x) git push origin main;; esac)"', P, P),
    ('echo "$(time case x in x) git push origin main;; esac)"', P, P),
    ('echo "$(while case x in x) false;; esac; do :; done; git push origin main)"', P, P),
    ('echo $(echo "$(! case x in x) git push origin main;; esac)")', P, P),
    ('echo "$(case x in x|esac) git push origin main;; esac)"', P, P),
    ('echo "`case x in x|esac) git push origin main;; esac`"', P, P),
    ('''echo "$(! case x in x) git push origin 'main';; esac)"''', P, P),
    ('''echo "$(! case x in x) g\\it push origin main;; esac)"''', P, P),
    ('''echo "`! case x in x) git push origin 'main';; esac`"''', P, P),
    # a harmless line stays as it was: no allow with a git word, and a `case` word is no deny
    ('cat "$(echo case-x)" README.md', P, P),
    ('echo "$(case x in x) true;; esac)" git status', P, P),
    ('grep -n "case" README.md', A, A),
    ('grep -n "case $(x) git push origin main" README.md', P, P),
    # the plain reading's extra command (`git status`, an approved read) is not an approval
    # of a line with a substitution
    ("echo $(true) git status", P, P),
    ("echo $(true) git push origin main", D, D),
    ("grep -n '\\(' README.md", A, A),
    ("grep -n '\\|' README.md", A, A),
    ("rg -n '\\(\\)' README.md", A, A),
    ("git log --grep '\\|' -1", A, A),
    ("git -C '1'>/dev/null push origin main", D, D),
    ("git push -o '1'>/dev/null origin main", D, D),
    ("git push origin '2'>x", P, D),
    ("git branch '7'>/dev/null", D, D),
    ("git switch " + BR, P, P),
    ("git checkout " + BR, P, P),
    ("git checkout HEAD", P, P),
    ("git checkout -- README.md", P, P),
    ("git checkout README.md", P, P),
    ("git checkout HEAD -- README.md", P, P),
    ("git checkout main -- README.md", P, P),
    ("git checkout -p README.md", P, P),
    ("AGENTTOOLING_PROFILE=local git push origin main", P, P),
    ("git reset --hard", D, D),
    ("git switch -c x", D, D),
    ("git push --force", D, D),
    ("git rebase main", D, D),
    # cloud only: switching away from the current branch
    ("git checkout main", P, D),
    ("git checkout -f main", P, D),
    ("git switch --detach", P, D),
    ("git checkout --detach", P, D),
    ("git switch -", P, D),
    ("git checkout -", P, D),
    ("git switch --orphan x", P, D),
    ("git checkout " + SHA, P, D),
    ("git checkout " + REMOTE_ONLY, P, D),
    ("git switch " + REMOTE_ONLY, P, D),
    ("git -C %s switch main" % C, P, D),
    # cloud only: a push whose target is not the current branch
    ("git push origin HEAD:x", P, D),
    ("git push origin x", P, D),
    ("git push --all", P, D),
    ("git push --all origin", P, D),
    ("git push --mirror origin", P, D),
    ("git push origin --tags", P, D),
    ("git push --prune origin", P, D),
    ("git push origin --delete " + BR, P, D),
    ("git push -d origin x", P, D),
    ("git push origin :x", P, D),
]
# On M, whose current branch IS `main`: in the cloud, where the hook reads the branch, a
# push whose RESOLVED target is `main` is refused too; locally there is no probe, so a
# push that does not name `main` keeps its prompt (NOTES.md ruling 21).
ON_MAIN_TABLE = [
    ("git status", A, A),
    ("git push", P, D),
    ("git push origin", P, D),
    ("git push origin HEAD", P, D),
    ("git push -u origin HEAD", P, D),
    ("git push --repo origin HEAD", P, D),
    ("git push origin main", D, D),
    ("git push -u origin main", D, D),
    ("git push origin HEAD:x", P, D),
    ("git switch main", P, P),
]
for table, root in ((TABLE, C), (ON_MAIN_TABLE, ON_MAIN)):
    for profile, column in ((LOCAL, 1), (CLOUD, 2)):
        wrong = []
        for case in table:
            got, reason = call(case[0], root=root, profile=profile)
            if got != case[column]:
                wrong.append((case[0], case[column], got, reason))
        for cmd, want, got, reason in wrong:
            check("T. %s, %s: %r wants %s" % (os.path.basename(root), profile, cmd, want),
                  False, "got %s %s" % (got, reason))
        if not wrong:
            check("T. %s, %s: every case of the table (%d)"
                  % (os.path.basename(root), profile, len(table)), True)

# ── Q. the own-branch push needs a started feature (cloud-checkpoint-push) ────────
# The same push, on a branch no tracked manifest names as branches[0]: a manifest that
# lists it second, one that only mentions it, agentTooling's own shape with no feature at
# all, a checkout on `main`, a detached HEAD, a directory that is no repo — none approves.
for label, hook, root in (("manifest lists it second", HOOK_WM, WM),
                          ("manifest only mentions it", HOOK_WP, WP),
                          ("no started feature", HOOK_S, S),
                          ("detached HEAD", HOOK_C, DET),
                          ("no repo", HOOK_C, NOREPO)):
    branch = OTHER_BR if root == S else BR
    for profile in (LOCAL, CLOUD):
        for cmd in ("git push -u origin " + branch, "git push origin " + branch):
            got, reason = call(cmd, hook=hook, root=root, profile=profile)
            check("Q1. %s, %s: %r is not approved (got %s)" % (label, profile, cmd, got),
                  got == P, reason)
got, _ = call("git push -u origin " + BR, hook=HOOK_C, root=ON_MAIN, profile=CLOUD)
check("Q2. a checkout on `main`: pushing the feature's branch name is not approved (got %s)" % got,
      got != A)
# A pipeline is approved only when every member is
got, _ = call("git push -u origin %s && git reset --hard" % BR, profile=CLOUD)
check("Q3. a chain with a refused member is refused (got %s)" % got, got == D)
got, _ = call("git push -u origin %s && git commit -m x" % BR, profile=CLOUD)
check("Q4. a chain with a member the human must judge is not approved (got %s)" % got, got != A)

# ── Q5. hook-audit-gaps B3: branches[0] is read from the commit, not the working tree ──
# WD: a manifest COMMITTED naming another branch first, then edited in the working tree
# (uncommitted) so branches[0] names the current branch. A commit is a write the human
# approves; a working-tree edit is not, so the edit must not make this branch "started".
WD = os.path.join(TMP, "dirty-manifest")
unstarted_branch(WD, [OTHER_BR], "")
HOOK_WD = os.path.join(WD, "agentTooling", "hooks", HOOK_NAME)
git(WD, "remote", "add", "origin", OWN_ORIGIN_URL)   # the approval needs one http(s) origin
with open(os.path.join(WD, "plans", "features", SLUG, "README.md"), "w") as f:
    f.write("# %s\n\n```json\n%s\n```\n"
            % (SLUG, json.dumps({"slug": SLUG, "base": BASE, "branches": [BR]})))
for cmd in ("git push -u origin " + BR, "git push origin " + BR):
    got, reason = call(cmd, hook=HOOK_WD, root=WD, profile=CLOUD)
    check("Q5. an uncommitted manifest edit naming the current branch: %r is not approved (got %s)"
          % (cmd, got), got == P, reason)
# the same edit, committed: the human gated it, so the push is approved
commit_all(WD, "edit manifest")
got, reason = call("git push -u origin " + BR, hook=HOOK_WD, root=WD, profile=CLOUD)
check("Q5. the same manifest once committed approves the push (got %s)" % got, got == A, reason)
# a committed manifest that names the branch, then an uncommitted edit that renames it away:
# the commit still says the branch is the feature's, and that is what the push sends
with open(os.path.join(WD, "plans", "features", SLUG, "README.md"), "w") as f:
    f.write("# %s\n\n```json\n%s\n```\n"
            % (SLUG, json.dumps({"slug": SLUG, "base": BASE, "branches": [OTHER_BR]})))
got, reason = call("git push -u origin " + BR, hook=HOOK_WD, root=WD, profile=CLOUD)
check("Q5. a committed manifest naming the branch still approves despite an uncommitted edit "
      "away from it (got %s)" % got, got == A, reason)

# ── Q6. round 2 hardening: the HEAD manifest is read as committed, replace refs ignored ──
# WR: a manifest COMMITTED naming another branch; then, with no commit, a blob naming the
# current branch is written to the object store and `refs/replace/<committed blob>` pointed at
# it. `git show HEAD:<manifest>` and `git grep … HEAD` then read the replacement (the first
# check proves the ref is live), and the push must still not be approved: the hook's probes
# ignore replace refs (escalations/01-audit-opus.md, "Gaps found that are not regressions")
WR = os.path.join(TMP, "replaced-manifest")
unstarted_branch(WR, [OTHER_BR], "")
HOOK_WR = os.path.join(WR, "agentTooling", "hooks", HOOK_NAME)
MANIFEST_REL = "plans/features/%s/README.md" % SLUG
REPLACEMENT = os.path.join(TMP, "replacement-manifest.md")
with open(REPLACEMENT, "w") as f:
    f.write("# %s\n\n```json\n%s\n```\n"
            % (SLUG, json.dumps({"slug": SLUG, "base": BASE, "branches": [BR]})))
git(WR, "replace", git(WR, "rev-parse", "HEAD:" + MANIFEST_REL),
    git(WR, "hash-object", "-w", REPLACEMENT))
check("Q6. the fixture's replace ref is live: plain git reads the replacement at HEAD",
      BR in git(WR, "show", "HEAD:" + MANIFEST_REL)
      and BR not in git(WR, "--no-replace-objects", "show", "HEAD:" + MANIFEST_REL))
for cmd in ("git push -u origin " + BR, "git push origin " + BR):
    got, reason = call(cmd, hook=HOOK_WR, root=WR, profile=CLOUD)
    check("Q6. a replace ref over the committed manifest does not approve %r (got %s)" % (cmd, got),
          got == P, reason)

# ── Q7. own-push-real-gitdir: the approved push trusts no git directory the tree plants ──
# The approval is exactly `git push [-u | --set-upstream] origin <B>` with no global option, run
# from the project root (the payload's cwd), against the root checkout's OWN git directory (found
# by walking the filesystem, never asked of git), with an effective config that redirects and
# executes nothing. Anything else is a prompt, never a deny. Every mutation below is made in
# the fixture's real .git/config or tree and undone right after its row, and the last row proves
# the fixture is back to approving.
BR_PLAIN = "git push origin %s" % BR
EVIL_PUSH_REFSPEC = "refs/heads/%s:refs/heads/%s" % (BR, BASE)
EVIL_SSH_URL = "ssh://example.invalid/consumer.git"
OTHER_URL = "https://example.invalid/second.git"
PLAIN_HTTP_URL = "http://example.invalid/consumer.git"
SCP_URL = "git@example.invalid:consumer.git"
EXT_URL = "ext::sh -c true"
REWRITE_BASE = "https://example.invalid/mirror/"
REWRITE_OF = "https://example.invalid/"
INERT_REWRITE_BASE = "https://github.com/"
INERT_REWRITE_OF = "git@github.com:"
SSH_PWNED = os.path.join(TMP, "PWNED_SSH")
NOT_THE_ROOT = os.path.join(TMP, "elsewhere")
PLANT_NAMES = ("evil2", "evil3")
OWN_BRANCH2 = "claude/feat-y"
HOOKS_PUSH = ("pre-push", "reference-transaction")
HOOK_BODY = "#!/bin/sh\nexit 0\n"


def q7(label, want, cmd=BR_PLAIN, mutate=None, restore=None, hook=HOOK_C, root=C, **kw):
    if mutate:
        mutate()
    try:
        got, reason = call(cmd, hook=hook, root=root, profile=CLOUD, **kw)
    finally:
        if restore:
            restore()
    # a Q8 row names itself; every other row is a Q7 one
    prefix = "" if label.startswith("Q8. ") else "Q7. "
    check("%s%s (got %s)" % (prefix, label, got), got == want, reason)


def cfg(repo, *args):
    return lambda: git(repo, "config", *args)


def plant_gitdir(path, url, extra=""):
    """A git directory written as plain files, as the audit planted it: nothing in its path
    holds `.git`, `core.worktree` names the checkout, and the push is redirected to `main`."""
    for sub in ("objects/info", os.path.dirname("refs/heads/" + BR)):
        os.makedirs(os.path.join(path, sub))
    with open(os.path.join(path, "HEAD"), "w") as f:
        f.write("ref: refs/heads/%s\n" % BR)
    with open(os.path.join(path, "objects", "info", "alternates"), "w") as f:
        f.write(os.path.join(C, ".git", "objects") + "\n")
    with open(os.path.join(path, "refs", "heads", BR), "w") as f:
        f.write(git(C, "rev-parse", "HEAD") + "\n")
    with open(os.path.join(path, "config"), "w") as f:
        # repositoryformatversion: without it git 2.43 ignores core.worktree here and the
        # toplevel probe fails, which would make the plant harmless on main
        f.write('[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tworktree = %s\n%s'
                '[remote "origin"]\n\turl = %s\n\tpush = %s\n'
                % (C, extra, url, EVIL_PUSH_REFSPEC))


def plant_rows(name, url, extra=""):
    path = os.path.join(C, "plans", name)
    plant_gitdir(path, url, extra)
    try:
        for flag in ("", "-u ", "--set-upstream "):
            for where in (os.path.join("plans", name), path):
                q7("%s planted at %s: `git -C %s push %sorigin <B>` is not approved"
                   % (name, os.path.relpath(path, C), where, flag),
                   P, "git -C %s push %sorigin %s" % (where, flag, BR))
        q7("%s planted: a push from inside the plant is not approved" % name, P,
           cwd=path)
        q7("%s planted: GIT_DIR in the hook's environment is not approved" % name, P,
           extra_env={"GIT_DIR": path})
        q7("%s planted: `--git-dir` on the line is not approved" % name, P,
           "git --git-dir=%s push origin %s" % (path, BR))
        q7("%s planted: GIT_DIR= as a prefix is not approved" % name, P,
           "GIT_DIR=%s git push origin %s" % (path, BR))
    finally:
        shutil.rmtree(path)


plant_rows(PLANT_NAMES[0], OWN_ORIGIN_URL)
plant_rows(PLANT_NAMES[1], EVIL_SSH_URL, "\tsshCommand = touch %s ; false\n" % SSH_PWNED)
check("Q7. no planted command ran", not os.path.exists(SSH_PWNED))

# ── the approvals that must hold, in the container's real config (its injected insteadOf too)
for cmd in ("git push origin " + BR, "git push -u origin " + BR,
            "git push --set-upstream origin " + BR, "git push -u origin '%s' 2>&1" % BR):
    q7("the plain push %r is approved" % cmd, A, cmd)
q7("push.default=simple is approved", A, mutate=cfg(C, "push.default", "simple"),
   restore=cfg(C, "--unset-all", "push.default"))
q7("push.default=current is approved", A, mutate=cfg(C, "push.default", "current"),
   restore=cfg(C, "--unset-all", "push.default"))
INERT_KEY = "url.%s.insteadOf" % INERT_REWRITE_BASE
q7("an insteadOf that does not apply to the origin url is approved", A,
   mutate=cfg(C, INERT_KEY, INERT_REWRITE_OF), restore=cfg(C, "--unset-all", INERT_KEY))
q7("an http:// origin url is approved", A, mutate=cfg(C, "--replace-all", "remote.origin.url", PLAIN_HTTP_URL),
   restore=cfg(C, "--replace-all", "remote.origin.url", OWN_ORIGIN_URL))
q7("a hook that is not one a push runs is approved", A,
   mutate=lambda: open(os.path.join(C, ".git", "hooks", "pre-commit"), "w").close(),
   restore=lambda: os.remove(os.path.join(C, ".git", "hooks", "pre-commit")))

# ── the words: nothing before `push`, nothing after the branch
for cmd in ("git -C %s push origin %s" % (C, BR), "git -C . push origin " + BR,
            "git --git-dir=%s push origin %s" % (os.path.join(C, ".git"), BR),
            "git --git-dir %s push origin %s" % (os.path.join(C, ".git"), BR),
            "git --work-tree=%s push origin %s" % (C, BR),
            "git --work-tree %s push origin %s" % (C, BR),
            "git -c push.default=matching push origin " + BR,
            "GIT_DIR=%s git push origin %s" % (os.path.join(C, ".git"), BR),
            "GIT_WORK_TREE=%s git push origin %s" % (C, BR),
            "GIT_CONFIG_COUNT=0 git push origin " + BR):
    q7("%r is not approved" % cmd, P, cmd)

# ── the cwd: the payload's cwd is the project root, not below it
q7("a cwd that is a subdirectory of the root is not approved", P, cwd=os.path.join(C, "plans"))
q7("a cwd that is the vendored subdirectory is not approved", P, cwd=os.path.join(C, "agentTooling"))
q7("a cwd that is the primary root is approved", A, cwd=C)

# ── the effective config: every key that redirects or executes during a push
PRESENCE_KEYS = (
    ("remote.origin.push", EVIL_PUSH_REFSPEC),
    ("remote.origin.pushurl", OTHER_URL),
    ("remote.origin.receivepack", "git-receive-pack"),
    ("remote.origin.vcs", "foo"),
    ("remote.origin.mirror", "true"),
    ("remote.pushdefault", "origin"),
    ("branch.%s.pushremote" % BR, "origin"),
    ("branch.other.pushRemote", "origin"),
    ("core.sshCommand", "ssh -v"),
    ("core.hooksPath", NOT_THE_ROOT),
    ("core.fsmonitor", "false"),
    ("push.recurseSubmodules", "check"),
    ("push.gpgSign", "false"),
    ("include.path", os.path.join(TMP, "no-such-include")),
    ("includeIf.gitdir:%s/.path" % C, os.path.join(TMP, "no-such-include")),
    ("pager.push", "cat"),
    ("submodule.recurse", "true"),
    ("push.followTags", "true"),
    ("hook.x.event", "pre-push"),
    ("hook.x.command", "touch %s" % os.path.join(TMP, "hook-x-ran")),
)
for key, value in PRESENCE_KEYS:
    q7("config %s is present: not approved" % key, P, mutate=cfg(C, key, value),
       restore=cfg(C, "--unset-all", key))
for value in ("upstream", "matching", "nothing", "anything"):
    q7("push.default=%s is not approved" % value, P, mutate=cfg(C, "push.default", value),
       restore=cfg(C, "--unset-all", "push.default"))

# ── the url: one value, http(s), and no rewrite that applies
URL_RESTORE = cfg(C, "--replace-all", "remote.origin.url", OWN_ORIGIN_URL)
q7("two remote.origin.url values are not approved", P,
   mutate=cfg(C, "--add", "remote.origin.url", OTHER_URL), restore=URL_RESTORE)
for what, url in (("an ssh://", EVIL_SSH_URL), ("an scp-like", SCP_URL), ("an ext::", EXT_URL),
                  ("a local path", ORIGIN)):
    q7("%s origin url is not approved" % what, P,
       mutate=cfg(C, "--replace-all", "remote.origin.url", url), restore=URL_RESTORE)
REWRITE_KEY = "url.%s.insteadOf" % REWRITE_BASE
q7("an insteadOf that applies to the origin url is not approved", P,
   mutate=cfg(C, REWRITE_KEY, REWRITE_OF), restore=cfg(C, "--unset-all", REWRITE_KEY))
PUSH_REWRITE_KEY = "url.%s.pushInsteadOf" % REWRITE_BASE
q7("a pushInsteadOf that applies to the origin url is not approved", P,
   mutate=cfg(C, PUSH_REWRITE_KEY, REWRITE_OF), restore=cfg(C, "--unset-all", PUSH_REWRITE_KEY))

# ── the hooks a push runs locally, as any file type
for name in HOOKS_PUSH:
    hook_path = os.path.join(C, ".git", "hooks", name)

    def make_file(p=hook_path):
        with open(p, "w") as f:
            f.write(HOOK_BODY)
        os.chmod(p, 0o755)
    q7("a %s hook file is not approved" % name, P, mutate=make_file,
       restore=lambda p=hook_path: os.remove(p))
    q7("a %s hook directory is not approved" % name, P, mutate=lambda p=hook_path: os.mkdir(p),
       restore=lambda p=hook_path: os.rmdir(p))

# ── the real config names a work tree that is not the root's
os.makedirs(NOT_THE_ROOT, exist_ok=True)
q7("a real-config core.worktree elsewhere is not approved", P,
   mutate=cfg(C, "core.worktree", NOT_THE_ROOT), restore=cfg(C, "--unset-all", "core.worktree"))
q7("a real-config core.bare=true is not approved", P,
   mutate=cfg(C, "core.bare", "true"), restore=cfg(C, "core.bare", "false"))

# ── a linked worktree: the `.git` file names the gitdir, and the push is approved from it
WT = os.path.join(TMP, "consumer-worktree")
git(C, "worktree", "add", "-q", "-b", OWN_BRANCH2, WT)
with open(os.path.join(WT, "plans", "features", SLUG, "README.md"), "w") as f:
    f.write("# %s\n\n```json\n%s\n```\n"
            % (SLUG, json.dumps({"slug": SLUG, "base": BASE, "branches": [OWN_BRANCH2]})))
commit_all(WT, "second branch")
HOOK_WT = os.path.join(WT, "agentTooling", "hooks", HOOK_NAME)
q7("a linked worktree's own push is approved", A, "git push -u origin " + OWN_BRANCH2,
   hook=HOOK_WT, root=WT)
q7("a linked worktree: the main checkout's branch is not its current branch (refused)", D,
   hook=HOOK_WT, root=WT)

# ── a repo vendored in a subdirectory of its checkout: the root is the subdirectory
V = os.path.join(TMP, "subdir-root")
V_SUB = os.path.join(V, "sub")
new_repo(V)
HOOK_V = vendor_hook(os.path.join(V_SUB, "hooks"))
os.makedirs(os.path.join(V_SUB, "self", "features", SLUG))
with open(os.path.join(V_SUB, "self", "features", SLUG, "README.md"), "w") as f:
    f.write("# %s\n\n```json\n%s\n```\n"
            % (SLUG, json.dumps({"slug": SLUG, "base": BASE, "branches": [BR]})))
commit_all(V, "init")
git(V, "checkout", "-q", "-b", BR)
git(V, "remote", "add", "origin", OWN_ORIGIN_URL)
q7("a root that is a subdirectory of its checkout approves the push from the root", A,
   "git push -u origin " + BR, hook=HOOK_V, root=V_SUB)
os.makedirs(os.path.join(V_SUB, "objects"))
os.makedirs(os.path.join(V_SUB, "refs"))
with open(os.path.join(V_SUB, "HEAD"), "w") as f:
    f.write("ref: refs/heads/%s\n" % BR)
q7("a bare-repo shape planted in the root itself is not approved", P,
   "git push -u origin " + BR, hook=HOOK_V, root=V_SUB)

# ── every mutation is undone: the plain push approves again
git(C, "worktree", "remove", "--force", WT)
git(C, "branch", "-q", "-D", OWN_BRANCH2)
q7("the fixture is restored: the plain push is approved again", A)

# ── Q8. own-push-credential-keys: a program git runs for credentials is no silent approval ──
# `credential.helper` (a `!` helper is a shell command), any `credential.<sub>.helper` and
# `core.askPass` run a program when the server asks for credentials; so does a non-empty
# GIT_ASKPASS or SSH_ASKPASS in the hook's environment. Each is a prompt, never a deny. An
# empty GIT_ASKPASS (the cloud container sets one) and `credential.interactive` approve.
# Every mutation is made in the fixture's real .git/config (or the hook's environment) and
# undone right after its row.
CRED_PWNED = os.path.join(TMP, "PWNED_CRED")
CRED_HELPER_VALUE = ("!f() { touch %s; echo username=x; echo password=y; }; f" % CRED_PWNED)
CRED_URL_SUB = "https://example.com"
CRED_URL_SUB_MIXED = "https://Example.COM/Path"
CRED_ASKPASS_PATH = os.path.join(TMP, "askpass.sh")
CRED_GLOBAL_CONFIG = os.path.join(TMP, "global-gitconfig")
CRED_HELPER_KEY = "credential.helper"
CRED_URL_HELPER_KEY = "credential.%s.helper" % CRED_URL_SUB
CRED_URL_HELPER_MIXED_KEY = "credential.%s.Helper" % CRED_URL_SUB_MIXED
CRED_ASKPASS_KEY = "core.askPass"
CRED_INTERACTIVE_KEY = "credential.interactive"
for key, value in ((CRED_HELPER_KEY, CRED_HELPER_VALUE),
                   (CRED_URL_HELPER_KEY, CRED_HELPER_VALUE),
                   (CRED_URL_HELPER_MIXED_KEY, CRED_HELPER_VALUE),
                   (CRED_ASKPASS_KEY, CRED_ASKPASS_PATH)):
    q7("Q8. config %s is present: not approved" % key, P, mutate=cfg(C, key, value),
       restore=cfg(C, "--unset-all", key))
with open(CRED_GLOBAL_CONFIG, "w") as f:
    f.write("[credential]\n\thelper = %s\n" % CRED_HELPER_VALUE)
q7("Q8. a credential.helper in the global config only is not approved", P,
   extra_env={"GIT_CONFIG_GLOBAL": CRED_GLOBAL_CONFIG})
# An empty subsection, `[credential ""]`, is listed as `credential..helper` and git honours it
# for every url (round 1's audit): raw text, since `git config` cannot spell the key.
CRED_REAL_CONFIG = os.path.join(C, ".git", "config")
EMPTY_SUB_SECTIONS = (
    ("credential", "helper = %s" % CRED_HELPER_VALUE),
    ("includeIf", "path = %s" % os.path.join(TMP, "no-such-include")),
    ("hook", "command = touch %s" % os.path.join(TMP, "hook-empty-ran")),
    ("branch", "pushRemote = origin"),
)
for section, line in EMPTY_SUB_SECTIONS:
    raw = '[%s ""]\n\t%s\n' % (section, line)
    with open(CRED_REAL_CONFIG) as f:
        saved_config = f.read()

    def append_raw(text=raw):
        with open(CRED_REAL_CONFIG, "a") as f:
            f.write(text)

    def restore_raw(text=saved_config):
        with open(CRED_REAL_CONFIG, "w") as f:
            f.write(text)
    q7("Q8. an empty-subsection [%s \"\"] in the repo config is not approved" % section, P,
       mutate=append_raw, restore=restore_raw)
    if section == "credential":
        with open(CRED_GLOBAL_CONFIG, "w") as f:
            f.write(raw)
        q7("Q8. an empty-subsection [credential \"\"] helper in the global config only is not "
           "approved", P, extra_env={"GIT_CONFIG_GLOBAL": CRED_GLOBAL_CONFIG})
q7("Q8. GIT_ASKPASS in the hook's environment is not approved", P,
   extra_env={"GIT_ASKPASS": CRED_ASKPASS_PATH})
q7("Q8. SSH_ASKPASS in the hook's environment is not approved", P,
   extra_env={"SSH_ASKPASS": CRED_ASKPASS_PATH})
q7("Q8. an empty GIT_ASKPASS is approved", A, extra_env={"GIT_ASKPASS": ""})
q7("Q8. an empty SSH_ASKPASS is approved", A, extra_env={"SSH_ASKPASS": ""})
q7("Q8. credential.interactive=false is approved", A,
   mutate=cfg(C, CRED_INTERACTIVE_KEY, "false"), restore=cfg(C, "--unset-all", CRED_INTERACTIVE_KEY))
q7("Q8. credential.<sub>.username is approved", A,
   mutate=cfg(C, "credential.%s.username" % CRED_URL_SUB, "x"),
   restore=cfg(C, "--unset-all", "credential.%s.username" % CRED_URL_SUB))
q7("Q8. the fixture is restored: the plain push is approved again", A)
check("Q8. no credential helper ran", not os.path.exists(CRED_PWNED))

# ── Q9. hook-silent-allow-sweep: the own-branch push's remaining silent approvals ──────────
# Item 2: a git helper variable SET in the hook's environment, even empty, is no approval.
# Item 3: a GIT_CONFIG naming a url-only file hid a local `!` helper from the probe (only
# `git config` reads GIT_CONFIG); the probe now runs without it, so the helper prompts and the
# url-only file alone still approves. Item 4: the push is approved only as the whole command;
# chained or piped with anything, even an approved read, it is sent back to run alone.
for name in ("GIT_EXEC_PATH", "GIT_SSH", "GIT_SSH_COMMAND", "GIT_PROXY_COMMAND"):
    q7("Q9. %s in the hook's environment is not approved" % name, P,
       extra_env={name: CRED_ASKPASS_PATH})
    q7("Q9. %s set empty is not approved either" % name, P, extra_env={name: ""})
URL_ONLY_CONFIG = os.path.join(TMP, "url-only-gitconfig")
with open(URL_ONLY_CONFIG, "w") as f:
    f.write('[remote "origin"]\n\turl = %s\n' % git(C, "config", "--get", "remote.origin.url"))
q7("Q9. a url-only GIT_CONFIG does not hide a local credential.helper", P,
   mutate=cfg(C, CRED_HELPER_KEY, CRED_HELPER_VALUE), restore=cfg(C, "--unset-all", CRED_HELPER_KEY),
   extra_env={"GIT_CONFIG": URL_ONLY_CONFIG})
q7("Q9. a url-only GIT_CONFIG alone is approved: the probe reads the config the push reads", A,
   extra_env={"GIT_CONFIG": URL_ONLY_CONFIG})
# Each send-back is followed by the plain push, which approves and so resets the session's
# escalation counter (two denials in a row would turn the next one into an ask).
for chained in ("%s && cat README.md" % BR_PLAIN, "ls && %s" % BR_PLAIN,
                "%s; git status" % BR_PLAIN, "%s || true" % BR_PLAIN):
    q7("Q9. the push in a sequence (`%s`) is sent back" % chained, D, cmd=chained)
    q7("Q9. ... and the push alone is approved", A)
for piped in ("%s | cat" % BR_PLAIN, "%s 2>&1 | tail -3" % BR_PLAIN):
    q7("Q9. the push piped (`%s`) prompts" % piped, P, cmd=piped)
_got, _reason = call("%s && cat README.md" % BR_PLAIN, hook=HOOK_C, root=C, profile=CLOUD)
check("Q9. ... with a reason that says to run the push alone",
      "run the push alone" in (_reason or ""), _reason)
q7("Q9. the fixture is restored: the plain push is approved again", A)
check("Q9. no credential helper ran", not os.path.exists(CRED_PWNED))

# ── R. the reasons ─────────────────────────────────────────────────────────────
LOCAL_WORDS = (".worktrees/<slug>", "primary checkout", "LIFECYCLE", "rule 2",
               "feature-start.sh", "feature-close.sh")
CLOUD_WORDS = (BR, "'%s'" % SLUG, "./agentTooling/feature-close.sh " + SLUG,
               "LIFECYCLE", "rule 2", "feature-start.sh")
CLOUD_NEVER = (".worktrees", "primary")


def words_check(label, cmd, want, never=(), **kw):
    got, reason = call(cmd, **kw)
    missing = [w for w in want if w not in reason]
    present = [w for w in never if w in reason]
    check(label, got == D and not missing and not present,
          "got %s, missing %s, has %s: %r" % (got, missing, present, reason))


words_check("R1. local `git checkout -b x` gives today's reason", "git checkout -b x",
            LOCAL_WORDS, profile=LOCAL)
for cmd in ("git checkout -b x", "git switch main", "git push origin main",
            "git push origin HEAD:x"):
    words_check("R2. cloud `%s` names the branch, the feature and its close, never the "
                "local layout" % cmd, cmd, CLOUD_WORDS, CLOUD_NEVER, profile=CLOUD)
_, local_reason = call("git checkout -b x", profile=LOCAL)
_, cloud_reason = call("git checkout -b x", profile=CLOUD)
check("R3. the two reasons differ", local_reason and cloud_reason and local_reason != cloud_reason)
words_check("R4. cloud, agentTooling's own shape with no feature: names "
            "./feature-start.sh --self and the branch",
            "git switch main", ("./feature-start.sh --self", OTHER_BR, "feature-close.sh",
                                "LIFECYCLE", "rule 2"),
            CLOUD_NEVER + ("./agentTooling/",), hook=HOOK_S, root=S, profile=CLOUD)
# Round 2: a push to `main` has a reason of its own locally — never push `main`, push the
# feature's branch, the PR feature-close.sh opens and a human merges — and nothing in it
# is the cloud's, nor the local layout's worktree advice. In the cloud it is the cloud one.
LOCAL_MAIN_WORDS = ("never push", "`main`", "feature's own branch", "feature-close.sh",
                    "PR", "human", "merge", "LIFECYCLE", "rule 2")
LOCAL_MAIN_NEVER = ("cloud", "container", ".worktrees", "assigned branch")
for cmd in ("git push origin main", "git push --repo origin main", "git push origin :main"):
    words_check("R5. local `%s` gives the push-to-main reason, nothing cloud-specific" % cmd,
                cmd, LOCAL_MAIN_WORDS, LOCAL_MAIN_NEVER, profile=LOCAL)
_, local_main_reason = call("git push origin main", profile=LOCAL)
_, local_layout_reason = call("git checkout -b x", profile=LOCAL)
check("R5b. ... and it is not today's local reason", local_main_reason
      and local_main_reason != local_layout_reason)
words_check("R6. cloud, on `main`: plain `git push` gets the cloud reason naming `main`",
            "git push", ("`main`", "LIFECYCLE", "rule 2", "Claude Code cloud container"),
            CLOUD_NEVER + ("feature's own branch",), root=ON_MAIN, profile=CLOUD)
words_check("R6b. cloud `git push origin main` gets the cloud reason, not the local one",
            "git push origin main", CLOUD_WORDS, CLOUD_NEVER + ("feature's own branch",),
            profile=CLOUD)
# hook-audit-gaps, phase 3 (b): the push that is approved silently names its branch as a literal,
# which is what the hook checks against `branches[0]`. The `$(git branch --show-current)`
# spelling is refused in the cloud (the table's row) — the push rules judge the words — and the
# reason names the rewrite: push the branch by its own name
SUBSTITUTED_PUSH = 'git push -u origin "$(git branch --show-current)"'
words_check("R7. cloud `%s` is refused, and the reason names the branch to push as a literal"
            % SUBSTITUTED_PUSH, SUBSTITUTED_PUSH, ("push only `%s`" % BR,) + CLOUD_WORDS,
            CLOUD_NEVER, profile=CLOUD)
got, reason = call("git push -u origin " + BR, profile=CLOUD)
check("R7. ... and the literal spelling it names is approved (got %s)" % got, got == A, reason)
# hook-audit-gaps, phase 3: these were denied before the self-audit too, but by a REWRITE deny
# (a brace group the expansion refuses, a heredoc the opaque check cannot read), which decays to
# an ask after two attempts. They are the git deny's now: its reason, three times over
GIT_RULE_WORDS = ("LIFECYCLE", "rule 2")
for cmd in ("git push --forc{e,{x,y}} origin z", "git push --{force,{quiet,verbose}} origin x",
            "git push --forc{e,x}{,a}{,b}{,c}{,d}{,e}{,f}{,g}{,h} origin x",
            "echo $((1<<2))\ngit push --force origin x\n2\nls",
            "a[1<<2]=5\ngit push --force origin x\n2]=5\nls",
            # round 2: the backtick run-on with a blank was the opaque rewrite on round 1's hook
            "echo `cat <<EOF\nx\nEOF ` ; git push --force origin x\nEOF\n`",
            "git commit -m \"$(cat <<'EOF'\nx\nEOF )\" ; git push --force origin x ; echo \"\nEOF\n)\"",
            "a=(x)#b; git push --force origin y"):
    for _attempt in range(2):
        call(cmd, profile=LOCAL)
    words_check("R8. local %r is the git deny, with its reason, on the third attempt too" % cmd,
                cmd, GIT_RULE_WORDS, profile=LOCAL)

# ── F. the fallbacks ─────────────────────────────────────────────────────────
got, _ = call("git switch main", hook=HOOK_C, root=DET, profile=CLOUD)
check("F1a. cloud, detached HEAD: `git switch main` keeps today's answer (got %s)" % got,
      got == P)
got, _ = call("git push origin x", hook=HOOK_C, root=DET, profile=CLOUD)
check("F1b. ... and `git push origin x` (got %s)" % got, got == P)
words_check("F1d. ... while `git push origin main` is refused from its words alone, with "
            "the cloud reason", "git push origin main", ("LIFECYCLE", "rule 2"),
            CLOUD_NEVER, hook=HOOK_C, root=DET, profile=CLOUD)
words_check("F1c. ... while `git checkout -b x` is still refused, with the cloud reason",
            "git checkout -b x", ("LIFECYCLE", "rule 2", "feature-start.sh"), CLOUD_NEVER,
            hook=HOOK_C, root=DET, profile=CLOUD)
got, _ = call("git switch main", hook=HOOK_C, root=NOREPO, profile=CLOUD)
check("F2a. cloud, no repo: `git switch main` keeps today's answer (got %s)" % got, got == P)
got, _ = call("git checkout -b x", hook=HOOK_C, root=NOREPO, profile=CLOUD)
check("F2b. ... and `git checkout -b x` is still refused (got %s)" % got, got == D)
got, _ = call("git push origin main", hook=HOOK_C, root=NOREPO, profile=CLOUD)
check("F2c. ... and `git push origin main` (got %s)" % got, got == D)
got, _ = call("git switch main", profile="bogus")
check("F3a. an invalid AGENTTOOLING_PROFILE: `git switch main` keeps today's answer "
      "(got %s)" % got, got == P)
words_check("F3b. ... and `git checkout -b x` gets today's local reason",
            "git checkout -b x", LOCAL_WORDS, profile="bogus")
words_check("F3c. ... and `git push origin main` gets the local push-to-main reason",
            "git push origin main", LOCAL_MAIN_WORDS, LOCAL_MAIN_NEVER, profile="bogus")
for cmd in ("git push --repo", "git push --repo=", "git push origin --repo",
            "git push -o", "git push origin :", "git push origin +", "git push ''"):
    for profile in (LOCAL, CLOUD):
        got, detail = call(cmd, profile=profile)
        check("F4. %s, a malformed push %r never crashes the hook (got %s)"
              % (profile, cmd, got), got in (P, D), detail)

# ── O. the off-branch remedy (self/features/cloud-off-branch-remedy/) ─────────
# A reclaimed container comes back cloned on `main`. OB is that clone, the manifest only
# on the feature's branch (where feature-start.sh commits it); OM is the same with the
# manifest tracked on `main` too. A switch to the feature's branch stays refused, but the
# reason is the off-branch one: never "push only `main`", and the fresh-session remedy.
def clone_on_main(path):
    sh(REAL_GIT, "clone", "-q", "--branch", BASE, ORIGIN, path)
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "hook cloud profile test")
    return os.path.join(path, "agentTooling", "hooks", HOOK_NAME)


OB = os.path.join(TMP, "off-branch")
HOOK_OB = clone_on_main(OB)
OM = os.path.join(TMP, "off-branch-main-manifest")
HOOK_OM = clone_on_main(OM)
os.makedirs(os.path.join(OM, "plans", "features", SLUG))
shutil.copy2(os.path.join(C, "plans", "features", SLUG, "README.md"),
             os.path.join(OM, "plans", "features", SLUG, "README.md"))
commit_all(OM, SLUG + ": manifest on main")
OFF_WORDS = ("`%s`" % BR, "'%s'" % SLUG, "fresh session", "human", "off its feature's branch",
             "LIFECYCLE", "rule 2")
OFF_NEVER = ("push only `main`", "Commit on `main`", ".worktrees")
for root, hook, label in ((OB, HOOK_OB, "manifest only on the branch"),
                          (OM, HOOK_OM, "manifest tracked on main")):
    for cmd in ("git checkout " + BR, "git switch " + BR, "git checkout origin/" + BR,
                "git switch --detach origin/" + BR, "git checkout -b %s origin/%s" % (BR, BR)):
        words_check("O1. cloud, on `main`, %s: `%s` is refused with the off-branch reason"
                    % (label, cmd), cmd, OFF_WORDS, OFF_NEVER, hook=hook, root=root,
                    profile=CLOUD)
    got, _ = call("git checkout " + BR, hook=hook, root=root, profile=LOCAL)
    check("O2. local, %s: `git checkout %s` still prompts (got %s)" % (label, BR, got),
          got == P)
words_check("O3. cloud, on `main`: a branch no manifest names keeps the existing reason",
            "git switch " + REMOTE_ONLY, ("Commit on `main`", "LIFECYCLE", "rule 2"),
            ("fresh session",), hook=HOOK_OB, root=OB, profile=CLOUD)
words_check("O4. cloud, on the feature's own branch: the reason is unchanged",
            "git checkout " + REMOTE_ONLY, CLOUD_WORDS, CLOUD_NEVER + ("fresh session",),
            profile=CLOUD)
OD = os.path.join(TMP, "off-branch-detached")
HOOK_OD = clone_on_main(OD)
git(OD, "checkout", "-q", "--detach")
words_check("O6. cloud, detached HEAD: `git checkout -b %s origin/%s` gets the off-branch "
            "reason, naming a detached HEAD" % (BR, BR),
            "git checkout -b %s origin/%s" % (BR, BR), OFF_WORDS + ("a detached HEAD",),
            OFF_NEVER, hook=HOOK_OD, root=OD, profile=CLOUD)
words_check("O7. ... and so is a plain `git checkout %s` there, which would move the working "
            "tree off HEAD's commit (self/features/detached-at-branch-tip-attach/)" % BR,
            "git checkout " + BR, OFF_WORDS + ("a detached HEAD",), OFF_NEVER,
            hook=HOOK_OD, root=OD, profile=CLOUD)
got, _ = call("git checkout " + BR, hook=HOOK_OD, root=OD, profile=LOCAL)
check("O7b. ... locally that checkout still prompts (got %s)" % got, got == P)
_, off_reason = call("git switch " + BR, hook=HOOK_OB, root=OB, profile=CLOUD)
check("O5. the off-branch reason never says to commit or push on `main`",
      off_reason and "push only" not in off_reason and "Commit on" not in off_reason,
      off_reason)

# ── A. the cached-clone attach (self/features/detached-at-branch-tip-attach/) ─────
# A session launched to continue a feature's branch came up detached EXACTLY at
# origin/<branch>, its local <branch> a strict ancestor left by an earlier clone. Every
# refusal there names attach-branch.sh; a switch that moves nothing is not refused.
def detached_at_tip(path, local_ahead=False, local_at_head=False):
    """A clone detached at origin/BR, origin/BR one commit ahead of the local BR (a
    fetch the clone already saw). `local_ahead` gives the local BR a commit of its own
    (not an ancestor of HEAD); `local_at_head` points it at HEAD."""
    hook = clone_on_main(path)
    git(path, "branch", "-q", BR, "origin/" + BR)
    if local_ahead:
        git(path, "checkout", "-q", BR)
        git(path, "commit", "-q", "--allow-empty", "-m", "local only")
    git(path, "checkout", "-q", "--detach", "origin/" + BR)
    git(path, "commit", "-q", "--allow-empty", "-m", "newer on origin")
    git(path, "update-ref", "refs/remotes/origin/" + BR, "HEAD")
    if local_at_head:
        git(path, "branch", "-q", "-f", BR, "HEAD")
    return hook


ATTACH_CMD = "./agentTooling/attach-branch.sh " + BR
ATTACH_WORDS = (ATTACH_CMD, "`origin/%s`" % BR, "'%s'" % SLUG, "moves nothing",
                "will not cure", "LIFECYCLE", "rule 2")
ATTACH_NEVER = ("push only", "Commit on", ".worktrees", "launched on")
AD = os.path.join(TMP, "attach-detached")
HOOK_AD = detached_at_tip(AD)
for cmd in ("git checkout -B %s origin/%s" % (BR, BR), "git switch -C %s origin/%s" % (BR, BR),
            "git branch -f %s origin/%s" % (BR, BR), "git checkout " + BR,
            "git switch " + BR, "git checkout -b x"):
    words_check("A1. cloud, detached at origin/%s with the local branch behind: `%s` is "
                "refused, naming attach-branch.sh" % (BR, cmd), cmd, ATTACH_WORDS,
                ATTACH_NEVER, hook=HOOK_AD, root=AD, profile=CLOUD)
for cmd in ("git checkout origin/" + BR, "git switch --detach", "git checkout HEAD",
            "git checkout -- README.md", "git status"):
    got, detail = call(cmd, hook=HOOK_AD, root=AD, profile=CLOUD)
    check("A2. ... while `%s`, which moves nothing, is not refused (got %s)" % (cmd, got),
          got in (P, A), detail)
words_check("A3. ... and locally `git checkout -B` keeps today's local reason",
            "git checkout -B %s origin/%s" % (BR, BR), LOCAL_WORDS, ("attach-branch",),
            hook=HOOK_AD, root=AD, profile=LOCAL)
AE = os.path.join(TMP, "attach-local-at-head")
HOOK_AE = detached_at_tip(AE, local_at_head=True)
got, detail = call("git checkout " + BR, hook=HOOK_AE, root=AE, profile=CLOUD)
check("A4. cloud, detached at the tip with the local branch already AT HEAD: a plain "
      "`git checkout %s` moves nothing and is not refused (got %s)" % (BR, got), got == P,
      detail)
AN = os.path.join(TMP, "attach-local-diverged")
HOOK_AN = detached_at_tip(AN, local_ahead=True)
for cmd in ("git checkout -B %s origin/%s" % (BR, BR), "git checkout " + BR):
    words_check("A5. cloud, detached at the tip but the local branch holds a commit HEAD "
                "lacks: `%s` is refused WITHOUT the attach remedy" % cmd, cmd,
                ("LIFECYCLE", "rule 2"), ("attach-branch",), hook=HOOK_AN, root=AN,
                profile=CLOUD)
words_check("A6. cloud, detached at a commit that is not the branch's tip: `git checkout -B "
            "%s origin/%s` is refused WITHOUT the attach remedy" % (BR, BR),
            "git checkout -B %s origin/%s" % (BR, BR), ("LIFECYCLE", "rule 2"),
            ("attach-branch",), hook=HOOK_OD, root=OD, profile=CLOUD)
# OD is detached at main, which origin/remote-only also points at — but no manifest names
# remote-only, so it is no feature's branch
words_check("A7. cloud, detached exactly at origin/%s, a branch no manifest names: refused "
            "WITHOUT the attach remedy" % REMOTE_ONLY,
            "git checkout -B %s origin/%s" % (REMOTE_ONLY, REMOTE_ONLY),
            ("LIFECYCLE", "rule 2"), ("attach-branch",), hook=HOOK_OD, root=OD,
            profile=CLOUD)
got, _ = call("git checkout " + REMOTE_ONLY, hook=HOOK_OD, root=OD, profile=CLOUD)
check("A8. ... while a plain `git checkout %s` there, the same commit as HEAD, is not "
      "refused (got %s)" % (REMOTE_ONLY, got), got == P)

# ── P. detection through the hook ─────────────────────────────────────────────
got, _ = call("git switch main", remote="true")
check("P1. CLAUDE_CODE_REMOTE=true with no override is cloud: `git switch main` refused "
      "(got %s)" % got, got == D)
got, _ = call("git switch main")
check("P2. neither variable is local: `git switch main` prompts (got %s)" % got, got == P)
got, _ = call("git switch main", profile=LOCAL, remote="true")
check("P3. AGENTTOOLING_PROFILE=local wins over CLAUDE_CODE_REMOTE=true (got %s)" % got,
      got == P)


# ── X. no subprocess off the cloud path ──────────────────────────────────────
def git_calls_for(cmds, profile, root=C):
    open(GIT_LOG, "w").close()
    for cmd in cmds:
        call(cmd, root=root, profile=profile, stub_git=True)
    with open(GIT_LOG) as f:
        return [line.strip() for line in f if line.strip()]


calls = git_calls_for([c[0] for c in TABLE], LOCAL)
check("X1. locally, no case of the table runs git (got %d call(s))" % len(calls),
      not calls, calls[:5])
calls = git_calls_for([c[0] for c in ON_MAIN_TABLE], LOCAL, root=ON_MAIN)
check("X1b. ... nor on a checkout of `main` (got %d call(s))" % len(calls),
      not calls, calls[:5])
LOCAL_MAIN_PUSHES = ("git push origin main", "git push -u origin main",
                     "git push --repo origin main", "git push origin HEAD:main",
                     "git -C %s push origin main" % C)
denied = [cmd for cmd in LOCAL_MAIN_PUSHES
          if call(cmd, profile=LOCAL, stub_git=True)[0] == D]
calls = git_calls_for(LOCAL_MAIN_PUSHES, LOCAL)
check("X4. locally, a push to `main` is refused (%d/%d) and runs no git (got %d call(s))"
      % (len(denied), len(LOCAL_MAIN_PUSHES), len(calls)),
      len(denied) == len(LOCAL_MAIN_PUSHES) and not calls, calls[:5])
calls = git_calls_for(["ls", "cat README.md", "git status", "git log --oneline -3",
                       "git diff HEAD --stat", "echo hi", "python3 -c 'print(1)'"], CLOUD)
check("X2. in the cloud, reads and non-git commands run no git (got %d call(s))"
      % len(calls), not calls, calls[:5])
# A refused cloud command that is not a switch/checkout never reaches the off-branch
# block: the head is read as often as before it existed — by the rule (cloud_refuses)
# when the shape is cloud-only, and once by the reason.
PROBE_HEAD = "rev-parse --show-toplevel"
for cmd, want_heads in (("git push origin x", 2), ("git reset --hard", 1)):
    calls = git_calls_for([cmd], CLOUD)
    heads = sum(PROBE_HEAD in c for c in calls)
    check("X5. a refused cloud `%s` reads the head %d time(s), plus the reason's one manifest grep (got %d "
          "call(s), %d head read(s))" % (cmd, want_heads, len(calls), heads),
          heads == want_heads and len(calls) == want_heads + 1, calls)
calls = git_calls_for(["git switch main"], CLOUD)
check("X3. the stub is live: a cloud `git switch main` does ask git (got %d call(s))"
      % len(calls), bool(calls))

print()
sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-cloud-profile: all checks passed"; else echo "hook-cloud-profile: FAILED"; fi
exit "$rc"
