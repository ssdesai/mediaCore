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
#      the current branch prompt in both; `mainline`, `feature/main`, `main-x` and
#      `main:x` prompt locally and are refused in the cloud as round 1 refused them; the
#      rest of the cloud-only shapes (`HEAD:x`, `--all`, `--mirror`, `--tags`, `--delete`,
#      `:x`, `--repo origin x`, a sha, `-`, `--detach`, `--orphan`, a remote-only branch,
#      `git -C <root> …`); and on M, a push whose resolved target is `main` (plain
#      `git push`, `git push origin HEAD`) prompts locally and is refused in the cloud;
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
HOOK_FILES = ("allow-repo-commands.sh", "policy.py", "env_profile.py")
HOOK_NAME = "allow-repo-commands.sh"
BASE = "main"
BR = "claude/feat-x"
SLUG = "feat-x"
OTHER_BR = "claude/other"
REMOTE_ONLY = "remote-only"
PROFILE_ENV = "AGENTTOOLING_PROFILE"
REMOTE_ENV = "CLAUDE_CODE_REMOTE"
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

# The logging git: every call is recorded, then handed to the real one.
os.makedirs(STUB_BIN)
with open(os.path.join(STUB_BIN, "git"), "w") as f:
    f.write('#!/usr/bin/env bash\necho "$*" >> "%s"\nexec "%s" "$@"\n' % (GIT_LOG, REAL_GIT))
os.chmod(os.path.join(STUB_BIN, "git"), 0o755)


def hook_env(root, profile=None, remote=None, stub_git=False):
    env = {k: v for k, v in os.environ.items()
           if k not in (PROFILE_ENV, REMOTE_ENV, "CLAUDE_PROJECT_DIR")}
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
    ("git push -u origin " + BR, P, P),
    ("git push", P, P),
    ("git push origin", P, P),
    ("git push origin HEAD", P, P),
    ("git push origin HEAD:" + BR, P, P),
    ("git push origin HEAD:refs/heads/" + BR, P, P),
    ("git push origin " + BR, P, P),
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
