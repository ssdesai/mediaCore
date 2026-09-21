#!/usr/bin/env bash
set -uo pipefail

# Self-test for the escalation half of hooks/allow-repo-commands.sh (hooks/README.md →
# "The opaque shape"): the per-session counter that turns a third unreadable command in
# a row into `ask`, the headless fall-through that prints nothing instead, and the
# AGENTTOOLING_SCRATCH entry point the runners hand their executors. Run by self/gate.sh,
# or by hand: bash self/tests/hook-escalation.sh
#
# allow-repo-commands.sh's own self-test asserts the DECISION on one command at a time
# and sends no `session_id`, so no state is written there at all. This file is the other
# half: it sends a session, so the state file exists, and every assertion here is about
# what the hook remembers between calls.
#
# $TMPDIR is redirected to a mktemp -d for the whole run, because that is where the hook
# puts its state directory. Nothing is read or written outside it, and the assertions
# count the files in it — a state file that landed anywhere else would show up as a
# missing one here.
#
# Asserts, in order:
#   1. two opaque commands in a row are denied; the third is `ask`, and its reason says
#      the command is still unreadable after the two rewrites and is the human's call;
#   2. a readable command between them resets the counter — whether it is approved,
#      merely refused, or itself denied for one of the three older shapes;
#   3. two session ids count independently, and a subagent (a payload carrying
#      `agent_id`) counts independently of its parent session;
#   4. a corrupt, empty or unreadable state file counts as zero rather than crashing or
#      denying, and a payload with no session id never escalates at all;
#   5. state files are created under the redirected $TMPDIR and nowhere else, one per
#      counted session;
#   6. with AGENTTOOLING_HEADLESS set the escalation prints NOTHING — nobody can answer
#      an `ask` in a runner — while the counter still advances, so unsetting it on the
#      next command yields the `ask` straight away;
#   7. with AGENTTOOLING_SCRATCH set, `bash <scratch>/x.sh` and `python3 [-B]
#      <scratch>/x.py` are approved although they are outside the project root — with
#      arguments after the script, each of which must itself be confined to the project
#      root or to the scratch directory — while the same basename elsewhere, a script
#      reached through a symlink out of the scratch directory, an argument outside both
#      roots, a flag BEFORE the script, and every scratch command with the variable unset
#      are not;
#   8. `scratch_argument_allowed`, called directly, judges `../x`, `--out=../x` and
#      `new-output.txt` the same way §7's end-to-end cases do — and keeps judging `../x`
#      the same way once a real file exists there, since existence never decides. The
#      full-hook commands in §7 prompt for `../x` regardless of this function's own
#      behaviour, because `command_allowed`'s `UNANALYSABLE` guard refuses any command
#      containing a literal `..` before the scratch logic is ever reached (NOTES.md,
#      "Round 2", ruling 17) — so only a direct call exercises the fix. Those two
#      commands are DENIED now rather than silent: a `..` component is a rewritable
#      shape (§7d);
#   9. a shape the 2026-09-18 design made rewritable — a `$NAME`, a `~`, a `..`
#      component, a relative `cd`, a brace group the expansion refuses — is denied with
#      its rewrite, counts toward the same escalation as the seven opaque shapes, is
#      reset by a command of the ASK class (which prints nothing), and falls silent
#      under AGENTTOOLING_HEADLESS at the escalation like any other.
#
# Depends on the hook keying its counter off `session_id`+`agent_id`, on
# OPAQUE_REWRITE_ATTEMPTS being 2, and on the state directory being an explicit template
# under $TMPDIR. No model, no network.

AT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook.escalation.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

echo "hook-escalation"
python3 - "$AT/hooks/allow-repo-commands.sh" "$TMP" <<'PY'
import importlib.machinery, importlib.util
import json, os, subprocess, sys

HOOK, TMP = sys.argv[1], sys.argv[2]
ROOT = os.path.join(TMP, "repo")
# The hook's state lives under $TMPDIR; every call below is made with $TMPDIR pointed
# here, so this directory is the whole of what the hook may write.
STATE_TMPDIR = os.path.join(TMP, "hookstate")
SCRATCH = os.path.join(TMP, "scratch")
ELSEWHERE = os.path.join(TMP, "elsewhere")
OUTSIDE = os.path.join(TMP, "outside")

for d in (ROOT, os.path.join(ROOT, "src"), STATE_TMPDIR, SCRATCH, ELSEWHERE, OUTSIDE):
    os.makedirs(d, exist_ok=True)
for f in (os.path.join(ROOT, "README.md"), os.path.join(ROOT, "src", "a.py")):
    open(f, "w").close()
for f in ("x.sh", "x.py", "helper.sh"):
    open(os.path.join(SCRATCH, f), "w").close()
for f in ("x.sh", "x.py"):
    open(os.path.join(ELSEWHERE, f), "w").close()
open(os.path.join(OUTSIDE, "evil.sh"), "w").close()
ESCAPE = os.path.join(SCRATCH, "escape.sh")
if not os.path.lexists(ESCAPE):
    os.symlink(os.path.join(OUTSIDE, "evil.sh"), ESCAPE)

# Two sessions and one subagent under the first of them. A subagent's payload carries
# the PARENT's session_id and its own agent_id (Claude Code hooks reference), so the
# agent id is the only thing that separates the two counters.
SESSION_A = "11111111-0000-0000-0000-00000000000a"
SESSION_B = "22222222-0000-0000-0000-00000000000b"
AGENT_ID = "agent-aaaaaaaa"

# One opaque command per call, so nothing in a sequence is approved by accident
OPAQUE = ["python3 -c 'print(1)'", "bash -c 'ls'", "ls | sh", "eval ls",
          "python3 - <<'EOF'\nprint(1)\nEOF", "for f in src/*; do cat $f; done"]
READABLE_ALLOW = "ls src"
READABLE_REFUSED = "rm -rf src"
READABLE_DENIED = "git worktree add x"
# The `ask` reason has to say what happened and whose call it now is
ASK_REASON_WORDS = ("unreadable", "2", "rewrit", "human")


def decide(command, session_id=None, agent_id=None, env_extra=None, cwd=ROOT):
    payload = {"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": command}}
    if session_id is not None:
        payload["session_id"] = session_id
    if agent_id is not None:
        payload["agent_id"] = agent_id
    env = {k: v for k, v in os.environ.items()
           if k not in ("CLAUDE_PROJECT_DIR", "AGENTTOOLING_HEADLESS",
                        "AGENTTOOLING_SCRATCH")}
    env["CLAUDE_PROJECT_DIR"] = ROOT
    env["TMPDIR"] = STATE_TMPDIR
    if env_extra:
        env.update(env_extra)
    p = subprocess.run([HOOK], input=json.dumps(payload), capture_output=True,
                       text=True, env=env)
    if p.returncode != 0:
        return "ERR(rc=%s)" % p.returncode, ""
    if not p.stdout.strip():
        return "prompt", ""
    try:
        out = json.loads(p.stdout)["hookSpecificOutput"]
    except (ValueError, KeyError, TypeError):
        return "ERR(parse)", p.stdout[:120]
    decision = {"deny": "DENY", "allow": "ALLOW", "ask": "ASK"}.get(
        out.get("permissionDecision"), "ERR(decision)")
    return decision, out.get("permissionDecisionReason", "")


def d(command, **kw):
    return decide(command, **kw)[0]


def state_files():
    """Every file the hook has left under the redirected $TMPDIR."""
    found = []
    for base, _dirs, files in os.walk(STATE_TMPDIR):
        for name in files:
            found.append(os.path.join(base, name))
    return sorted(found)


fails = 0


def check(label, condition, detail=""):
    global fails
    if condition:
        print("  ok    %s" % label)
    else:
        print("  FAIL  %s%s" % (label, (" — " + str(detail)) if detail else ""))
        fails += 1


# ── 1: two denies, then ask ──────────────────────────────────────────────────
first = d(OPAQUE[0], session_id=SESSION_A)
second = d(OPAQUE[1], session_id=SESSION_A)
third, third_reason = decide(OPAQUE[2], session_id=SESSION_A)
check("1a. the first opaque command is denied (got %s)" % first, first == "DENY")
check("1b. the second is denied too (got %s)" % second, second == "DENY")
check("1c. the third is ask (got %s)" % third, third == "ASK")
missing = [w for w in ASK_REASON_WORDS if w not in third_reason]
check("1d. the ask reason says it is still unreadable after 2 rewrites and is the "
      "human's call", not missing, "missing %s in %r" % (missing, third_reason))
fourth = d(OPAQUE[3], session_id=SESSION_A)
check("1e. a fourth is still ask, not a deny the model has already ignored twice "
      "(got %s)" % fourth, fourth == "ASK")

# ── 2: a readable command resets the counter ─────────────────────────────────
# "Readable" is the whole of the test, not "approved": a command the analysis refuses
# for what it DOES, and one it denies for one of the three older shapes, are both
# commands it could read, and both put the model back at the start.
for label, resetter, want in (("an approved command", READABLE_ALLOW, "ALLOW"),
                              ("a refused command", READABLE_REFUSED, "prompt"),
                              ("a denied command", READABLE_DENIED, "DENY")):
    session = "reset-%s" % want
    check("2a[%s]. the resetter itself is %s" % (label, want),
          d(resetter, session_id=session) == want)
    check("2b[%s]. two denies after it" % label,
          d(OPAQUE[0], session_id=session) == "DENY"
          and d(OPAQUE[1], session_id=session) == "DENY")
    check("2c[%s]. it resets the count" % label,
          d(resetter, session_id=session) == want)
    check("2d[%s]. so the next opaque command is denied again, not asked" % label,
          d(OPAQUE[2], session_id=session) == "DENY")

# ── 3: sessions and subagents count independently ────────────────────────────
check("3a. session A is already escalated", d(OPAQUE[0], session_id=SESSION_A) == "ASK")
check("3b. session B starts at zero",
      d(OPAQUE[0], session_id=SESSION_B) == "DENY")
check("3c. and escalates on its own third command",
      d(OPAQUE[1], session_id=SESSION_B) == "DENY"
      and d(OPAQUE[2], session_id=SESSION_B) == "ASK")
check("3d. a subagent of session A starts at zero although the session id is the same",
      d(OPAQUE[0], session_id=SESSION_A, agent_id=AGENT_ID) == "DENY")
check("3e. the subagent escalates on its own count",
      d(OPAQUE[1], session_id=SESSION_A, agent_id=AGENT_ID) == "DENY"
      and d(OPAQUE[2], session_id=SESSION_A, agent_id=AGENT_ID) == "ASK")
check("3f. and the parent session is where it was, not advanced by its delegate",
      d(OPAQUE[3], session_id=SESSION_A) == "ASK")

# ── 4: a state file that cannot be read counts as zero ───────────────────────
CORRUPT = "corrupt-session"
check("4a. two denies on a fresh session",
      d(OPAQUE[0], session_id=CORRUPT) == "DENY"
      and d(OPAQUE[1], session_id=CORRUPT) == "DENY")
corrupt_paths = [p for p in state_files()]
check("4b. that session left exactly one state file to corrupt (got %d)"
      % len(corrupt_paths), len(corrupt_paths) >= 1)
# Corrupt every state file: the hook must read none of them as a count.
for p in corrupt_paths:
    with open(p, "w") as fh:
        fh.write("not a number at all\x00\n")
check("4c. a corrupt state file counts as zero, so the next command is a deny",
      d(OPAQUE[2], session_id=CORRUPT) == "DENY")
for p in corrupt_paths:
    open(p, "w").close()
check("4d. an empty state file counts as zero too",
      d(OPAQUE[3], session_id=CORRUPT) == "DENY")
check("4e. a payload with no session id is denied and never escalates",
      [d(c) for c in OPAQUE[:4]] == ["DENY"] * 4)

# ── 5: the state stays under $TMPDIR ─────────────────────────────────────────
files = state_files()
check("5a. every state file the hook wrote is under the redirected $TMPDIR (got %d)"
      % len(files), len(files) > 0 and all(p.startswith(STATE_TMPDIR + os.sep)
                                           for p in files))
check("5b. nothing was written into the project root",
      sorted(os.listdir(ROOT)) == ["README.md", "src"], sorted(os.listdir(ROOT)))
# One file per counted session: A, B, A's subagent, the three resetters, the corrupt one
check("5c. one state file per counted session, no more (got %d)" % len(files),
      len(files) == 7, files)

# ── 6: headless prints nothing at the escalation ─────────────────────────────
HEADLESS = {"AGENTTOOLING_HEADLESS": "1"}
HL = "headless-session"
check("6a. the first two are denied under a headless runner as well",
      d(OPAQUE[0], session_id=HL, env_extra=HEADLESS) == "DENY"
      and d(OPAQUE[1], session_id=HL, env_extra=HEADLESS) == "DENY")
check("6b. the third prints nothing instead of asking — nobody can answer",
      d(OPAQUE[2], session_id=HL, env_extra=HEADLESS) == "prompt")
check("6c. and the counter still advanced: the same session asks the moment it is not "
      "headless", d(OPAQUE[3], session_id=HL) == "ASK")
check("6d. headless changes nothing below the escalation: a first opaque command is "
      "still denied",
      d(OPAQUE[0], session_id="headless-fresh", env_extra=HEADLESS) == "DENY")
check("6e. and a readable command is still approved",
      d(READABLE_ALLOW, session_id=HL, env_extra=HEADLESS) == "ALLOW")

# ── 7: the scratch entry point ───────────────────────────────────────────────
WITH_SCRATCH = {"AGENTTOOLING_SCRATCH": SCRATCH}
SC = "scratch-session"
SCRATCH_ALLOW = [
    "bash %s/x.sh" % SCRATCH,
    "python3 %s/x.py" % SCRATCH,
    "python3 -B %s/x.py" % SCRATCH,
    "python %s/x.py" % SCRATCH,
    # Arguments AFTER the script, each confined to the project root or to the scratch
    # directory — a script that needs an input file no longer has to be rewritten to
    # carry it (self/DESIGN-2026-09-17-policy-module.md §5).
    "bash %s/x.sh %s/src/a.py" % (SCRATCH, ROOT),        # absolute, inside the root
    "bash %s/x.sh src/a.py" % SCRATCH,                   # relative to the payload's cwd
    "bash %s/x.sh %s/helper.sh" % (SCRATCH, SCRATCH),    # inside the scratch directory
    "python3 %s/x.py %s/README.md --verbose" % (SCRATCH, ROOT),
    "bash %s/x.sh --flag" % SCRATCH,                     # a bare flag carries no path
    # Existence never decides (round 2): a relative argument that does not exist yet is
    # still approved when it resolves, LEXICALLY, inside the project root — an argument
    # may be the script's OUTPUT path.
    "bash %s/x.sh new-output.txt" % SCRATCH,             # relative, absent, inside the root
]
SCRATCH_PROMPT = [
    "bash %s/x.sh" % ELSEWHERE,              # the same basename somewhere else
    "python3 %s/x.py" % ELSEWHERE,
    "bash %s/escape.sh" % SCRATCH,           # a symlink out of the scratch directory
    "bash %s/nosuch.sh" % SCRATCH,           # a file that is not there
    "bash -x %s/x.sh" % SCRATCH,             # a flag BEFORE the script is not a script
    "bash -x %s/x.sh %s/src/a.py" % (SCRATCH, ROOT),
    "bash %s/x.sh /etc/passwd" % SCRATCH,    # an argument outside both roots
    "bash %s/x.sh %s/evil.sh" % (SCRATCH, OUTSIDE),
    "bash %s/x.sh %s/escape.sh" % (SCRATCH, SCRATCH),   # through a link out of it
    "sh %s/x.sh" % SCRATCH,                  # bash and python3 only
    "%s/x.sh" % SCRATCH,                     # not executed directly either
    "python3 -m py_compile %s/x.py" % SCRATCH,   # py_compile still wants the root
    # Existence never decides (round 2): a relative argument that resolves OUTSIDE both
    # roots prompts whether or not `../x` exists — before the fix this was approved
    # because an absent path "names nothing on disk".
]
# The same two arguments are a rewritable shape now, not a silent prompt: a `..`
# component in a path token is denied with the rewrite (design 2026-09-18 §1), and that
# answer comes before the scratch logic, exactly as the `UNANALYSABLE` refusal did.
SCRATCH_REWRITE = [
    "bash %s/x.sh ../x" % SCRATCH,            # relative, absent, outside both roots
    "bash %s/x.sh --out=../x" % SCRATCH,      # same path, carried as the value after `=`
]
SCRATCH_REWRITE_WORDS = ("from the project root",)
for cmd in SCRATCH_ALLOW:
    got = d(cmd, session_id=SC, env_extra=WITH_SCRATCH)
    check("7a. approved from the scratch directory: %s (got %s)"
          % (cmd.replace(SCRATCH, "<scratch>"), got), got == "ALLOW")
for cmd in SCRATCH_PROMPT:
    got = d(cmd, session_id=SC, env_extra=WITH_SCRATCH)
    check("7b. not approved: %s (got %s)"
          % (cmd.replace(SCRATCH, "<scratch>").replace(ELSEWHERE, "<elsewhere>"), got),
          got == "prompt")
for cmd in SCRATCH_ALLOW:
    got = d(cmd, session_id=SC)
    check("7c. nothing under any scratch directory is approved with the variable unset:"
          " %s (got %s)" % (cmd.replace(SCRATCH, "<scratch>"), got), got == "prompt")
for cmd in SCRATCH_REWRITE:
    got, reason = decide(cmd, session_id="scratch-rewrite", env_extra=WITH_SCRATCH)
    missing = [w for w in SCRATCH_REWRITE_WORDS if w not in reason]
    check("7d. a `..` argument is denied with the rewrite: %s (got %s)"
          % (cmd.replace(SCRATCH, "<scratch>"), got), got == "DENY" and not missing,
          "missing %s in %r" % (missing, reason))

# ── 8: scratch_argument_allowed, called directly ─────────────────────────────
# `../x` inside a command string trips command_allowed's own UNANALYSABLE guard (a
# literal `..`) before the scratch logic runs, so every §7 case built from it prompts
# either way and cannot show whether this function's own lexical check is doing the
# work. Loading the hook as a module and calling the function directly is the only way
# to see it: it is Python with a .sh name, so the loader is explicit, exactly as
# self/tests/policy-table.sh's load_hook() does for the same file.
spec = importlib.util.spec_from_loader(
    "allow_repo_commands", importlib.machinery.SourceFileLoader(
        "allow_repo_commands", HOOK))
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)

ARG_ROOT = os.path.realpath(ROOT)
ARG_SCRATCH = os.path.realpath(SCRATCH)
check("8a. scratch_argument_allowed('../x') is not confined",
      hook.scratch_argument_allowed("../x", ARG_ROOT, ARG_ROOT, ARG_SCRATCH) is False)
check("8b. scratch_argument_allowed('--out=../x') is not confined",
      hook.scratch_argument_allowed("--out=../x", ARG_ROOT, ARG_ROOT, ARG_SCRATCH)
      is False)
check("8c. scratch_argument_allowed('new-output.txt') is confined",
      hook.scratch_argument_allowed("new-output.txt", ARG_ROOT, ARG_ROOT, ARG_SCRATCH)
      is True)
# Existence never decides: `../x` resolves to a sibling of ROOT, outside both roots.
# Creating it for real must not flip 8a's answer.
open(os.path.join(os.path.dirname(ARG_ROOT), "x"), "w").close()
check("8d. scratch_argument_allowed('../x') stays refused once the path exists",
      hook.scratch_argument_allowed("../x", ARG_ROOT, ARG_ROOT, ARG_SCRATCH) is False)

# ── 9: the new rewritable shapes are rewrites like any other ─────────────────
# A shape the analysis could not read counts toward the same escalation whether it is one
# of the seven opaque shapes or one of the shapes the 2026-09-18 design added: two denies
# with the rewrite, then the human. And the reset rule is unchanged, now stated in the
# vocabulary that made it true all along — a command the hook READ puts the count back at
# zero, and the ASK class is exactly the class of commands it read and cannot vouch for.
NEW_SHAPES = ["cat $HOME/f", "ls ~/x", "cat ../x", "cd src", "cat {a,{b,c}}"]
ASK_RESETTER = "echo x > f"
for i, shape in enumerate(NEW_SHAPES):
    got = d(shape, session_id="shape-%d" % i)
    check("9a. a fresh session is denied the rewritable shape %r (got %s)" % (shape, got),
          got == "DENY")
SH = "shape-escalation"
check("9b. two rewritable shapes in a row are denied",
      d(NEW_SHAPES[0], session_id=SH) == "DENY"
      and d(NEW_SHAPES[1], session_id=SH) == "DENY")
third, third_reason = decide(NEW_SHAPES[2], session_id=SH)
check("9c. the third is ask, whatever mix of shapes got there (got %s)" % third,
      third == "ASK")
missing = [w for w in ASK_REASON_WORDS if w not in third_reason]
check("9d. and it carries the escalation's own reason", not missing,
      "missing %s in %r" % (missing, third_reason))
SR = "shape-reset"
check("9e. two rewritable shapes, then an ASK command that prints nothing",
      d(NEW_SHAPES[0], session_id=SR) == "DENY"
      and d(NEW_SHAPES[1], session_id=SR) == "DENY"
      and d(ASK_RESETTER, session_id=SR) == "prompt")
check("9f. the ASK reset the counter, so the next rewritable shape is denied again",
      d(NEW_SHAPES[2], session_id=SR) == "DENY")
check("9g. headless prints nothing at the escalation for a rewritable shape too",
      d(NEW_SHAPES[0], session_id="shape-headless", env_extra=HEADLESS) == "DENY"
      and d(NEW_SHAPES[1], session_id="shape-headless", env_extra=HEADLESS) == "DENY"
      and d(NEW_SHAPES[2], session_id="shape-headless", env_extra=HEADLESS) == "prompt")

sys.exit(1 if fails else 0)
PY
rc=$?
if (( rc == 0 )); then echo "hook-escalation: all checks passed"; else echo "hook-escalation: FAILED"; fi
exit "$rc"
