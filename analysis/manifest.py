#!/usr/bin/env python3
"""Read and write a feature manifest's machine-readable fence, and read what its
planning.json claimed — the JSON edits the lifecycle scripts need, kept out of bash.

    python3 agentTooling/analysis/manifest.py [--self] <slug> init --method M --branch B \\
        --base BASE --from TS [--session ID]... [--plan STEM]...
    python3 agentTooling/analysis/manifest.py [--self] <slug> get <key>
    python3 agentTooling/analysis/manifest.py [--self] <slug> set-plans <stem>...
    python3 agentTooling/analysis/manifest.py [--self] <slug> set-window-to [TS] [--tighten|--replace]
    python3 agentTooling/analysis/manifest.py [--self] <slug> set-window-from TS --session ID
    python3 agentTooling/analysis/manifest.py [--self] <slug> pin-session ID
    python3 agentTooling/analysis/manifest.py [--self] <slug> claimed

`init` writes `<features>/<slug>/README.md` from `templates/plans/features/TEMPLATE.md`
with the template's fence replaced by a filled one, and refuses if the file exists —
`feature-start.sh` runs it, once, in the new worktree. `get` prints one scalar (or a
JSON array) from the LAST ```json fence, the one `capture_planning.py` reads. `set-window-to`
replaces a `null` `to` bound with TS (default: now, UTC, `Z`) and touches nothing else in
the file; a bound already set is left alone and reported, since a second stamp would move
a boundary another manifest may chain to. There are two exceptions, one per side of the
merge. `--replace`, before it: the bound on a feature's branch is provisional, so a bound
already set is replaced in either direction, printing `old -> new` — what
`feature-capture.sh` runs on the branch, where a re-run after more work moves `to` later.
`--tighten`, after it, and only ever inwards: it replaces a bound already set with an
EARLIER instant, printing `old -> new`, treats the same instant as a no-op, and refuses a
later one — a widened `to` re-admits sessions the neighbouring feature's window may
already have chained onto, and the share split then pays this feature for work it did not
do. It is what `feature-capture.sh --recapture` runs to repair a merged feature's `to`.
Both refuse a bound at or before the fence's `from`: an EMPTY window owns nothing and is
dropped from every other feature's split.
`set-window-from` is the head's remedy, and the only thing here that moves `from`: it
moves that bound BACK, over an opening stretch `capture_planning.py` has disclosed as
unclaimed, and prints `old -> new`. Three refusals, each a plain 1 — an instant earlier
than the named session's own first timestamped instant (a `from` before the work it is
meant to cover is a claim on somebody else's), a *later* instant (widening the claim
backwards is this command's job, narrowing is nobody's — see `cmd_set_window_from`), and
a fence whose `from` is null or unparseable. On a feature already captured it applies and
then says the figure will not move until `--recapture`.
`set-plans` replaces `plans[]` with the stems given, in that order — how the
architect records the batch after `feature-start.sh` wrote the fence with only the review
stub in it — and refuses a stem that is not `NN-name-MODEL` (a sentinel is never a plan).
`pin-session` appends one session id to `sessions[]`, idempotently, and refuses an empty
one — the remedy `feature-close.sh` names when the feature's router worked in its
worktree unpinned (self/features/router-built-pin). The manifest is a cost record, so the
change it leaves passes the close's dirty-files check and rides the capture's commit.
`claimed` prints the sessions and subagents
`planning.json` holds, each with how it was selected and where it was launched, and the
total — what `feature-capture.sh` shows the human before the number is quoted.

Formatting is preserved: the fence is written one key per line with compact values,
the shape every hand-written manifest in both corpora already has, so a diff after
`init` or `set-window-to` shows the change and nothing else.

Exit codes: 0 success, a no-op included; 3 the widen refusal ALONE (`WIDEN_REFUSED_EXIT`
— `feature-capture.sh` continues past that one and stops on every other); 1 any other
refusal; 2 argparse's usage error.
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from roots import AGENT_TOOLING_DIR, add_self_flag, features_root
# One way, and the direction is the point: `routing` imports `pricing`, `roots` and
# `transcript` and nothing else — never this module and never `capture_planning` — so
# importing it here cannot close a cycle. The other candidate would have:
# `capture_planning` is the module that reads this fence on every capture, and a
# `manifest` -> `capture_planning` import would make the reader import its writer.
# What is needed is the transcript lookup, and `routing.find_transcript` is the one
# copy of it that is not behind a capture (it globs `~/.claude/projects/*/<id>.jsonl`,
# as `recover_attempts.py` does, because session ids are unique).
from routing import find_transcript, load_lines

TEMPLATE_PATH = AGENT_TOOLING_DIR / "templates" / "plans" / "features" / "TEMPLATE.md"
FENCE_RE = re.compile(r"```json\n(.*?)\n```", re.DOTALL)
# The order the fence is written in, so every manifest reads the same way top to bottom.
FENCE_KEY_ORDER = (
    "slug", "method", "plans", "branches", "base", "session_window",
    "exclude_sessions", "exclude_subagents", "sessions", "subagents",
)
KNOWN_METHODS = ("plans", "direct", "hand")
# The fence key `pin-session` appends to: the sessions claimed outright, regardless of
# branch, window or cwd.
SESSIONS_KEY = "sessions"
# A plan stem: number, kebab name, model — the filename without `.md`. `NN-gate` is a
# sentinel, not a plan, and never belongs in `plans[]`; the model alternation excludes it.
PLAN_STEM_RE = re.compile(r"^[0-9]+-[a-z0-9-]+-(haiku|sonnet|opus)$")
# The exit code `set-window-to --tighten` gives the WIDEN refusal and nothing else, so
# that `feature-capture.sh --recapture` can continue past that one refusal — the bound it
# declined to widen is the one already published — and stop on every other. Deliberately
# not 2: argparse exits 2 on a usage error, and a capture that read a malformed invocation
# as a declined widen would stamp nothing, warn about a cause that did not happen, and then
# capture a merged feature with a permanently open window. Every other refusal in this
# module is a plain 1.
WIDEN_REFUSED_EXIT = 3
# `set-window-to --replace`: the pre-merge rule. `feature-capture.sh` runs on the feature's
# branch before the merge, and a re-run after more work must move the bound LATER — the
# record on the branch is provisional, and the merge is what freezes it. So a bound
# already set is replaced in either direction; the empty-window refusal still holds, since
# a `to` at or before `from` owns nothing whichever way it moved. `--tighten` stays the
# post-merge rule, and the two are refused together.
REPLACE_HELP = (
    "replace a bound already set in EITHER direction — the pre-merge rule "
    "feature-capture.sh uses on the feature's branch, where the bound is provisional "
    "until the merge freezes it. One at or before `from` is still refused (exit 1)"
)


def now_z():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def last_fence(text):
    """(match, parsed object) for the last ```json fence, or a ValueError."""
    matches = list(FENCE_RE.finditer(text))
    if not matches:
        raise ValueError("no ```json fence found")
    match = matches[-1]
    return match, json.loads(match.group(1))


def render_fence(obj):
    """One key per line, compact values — the hand-written shape."""
    keys = [k for k in FENCE_KEY_ORDER if k in obj] + [k for k in obj if k not in FENCE_KEY_ORDER]
    lines = [f'  "{key}": {json.dumps(obj[key], separators=(", ", ": "))}' for key in keys]
    return "{\n" + ",\n".join(lines) + "\n}"


def manifest_path(args):
    return features_root(args.self_mode) / args.slug / "README.md"


def cmd_init(args):
    path = manifest_path(args)
    if path.exists():
        print(f"refusing: {path} already exists", file=sys.stderr)
        return 1
    if args.method not in KNOWN_METHODS:
        print(f"refusing: --method must be one of {', '.join(KNOWN_METHODS)}", file=sys.stderr)
        return 1
    if not TEMPLATE_PATH.exists():
        print(f"refusing: no template at {TEMPLATE_PATH}", file=sys.stderr)
        return 1
    text = TEMPLATE_PATH.read_text()
    match, _ = last_fence(text)
    fence = {
        "slug": args.slug,
        "method": args.method,
        "plans": list(args.plan or []),
        "branches": [args.branch],
        "base": args.base,
        "session_window": {"from": args.window_from, "to": None},
        "exclude_sessions": [],
        "exclude_subagents": [],
        "sessions": list(args.session or []),
        "subagents": [],
    }
    new_text = text[: match.start(1)] + render_fence(fence) + text[match.end(1):]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(new_text)
    print(path)
    return 0


def cmd_get(args):
    path = manifest_path(args)
    _, obj = last_fence(path.read_text())
    value = obj
    for part in args.key.split("."):
        if not isinstance(value, dict) or part not in value:
            return 0  # absent: print nothing, exit 0 — a caller treats empty as unset
        value = value[part]
    if value is None:
        return 0
    print(value if isinstance(value, str) else json.dumps(value))
    return 0


def to_instant(value):
    """One `session_window` bound as an aware UTC instant, or None when it does not parse.

    The same reading `analysis/transcript.to_utc` gives it — `Z` normalized to `+00:00`,
    an offset-less value read as UTC — spelled out here because this module imports
    nothing from `transcript`, and because comparing two bounds as STRINGS is exactly the
    bug `analysis/README.md` -> "Every instant is UTC" exists to prevent: a `to` of
    `2026-07-17T18:00:00-04:00` sorts below `2026-07-17T22:00:00Z` and is the same
    instant.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        moment = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def cmd_set_window_to(args):
    path = manifest_path(args)
    text = path.read_text()
    match, obj = last_fence(text)
    current = (obj.get("session_window") or {}).get("to")
    stamp = args.timestamp or now_z()
    replacing = "null"
    if args.tighten and args.replace:
        print("refusing: --tighten and --replace are two different rules; give one", file=sys.stderr)
        return 1
    if current is not None:
        # A bound already set is left alone by default: a second stamp would move a
        # boundary another manifest may chain onto, and `in_window` is half-open so that
        # they can. `--tighten` is one exception, and only ever inwards; `--replace` is
        # the other, and only before the merge (see REPLACE_HELP).
        if not (args.tighten or args.replace):
            print(f"session_window.to already set to {current}; left alone")
            return 0
        old, new = to_instant(current), to_instant(stamp)
        if old is None or new is None:
            print(
                f"refusing: cannot compare session_window.to {current!r} with {stamp!r} — "
                "one of them is not an ISO 8601 instant",
                file=sys.stderr,
            )
            return 1
        if args.tighten and new > old:
            # Never outwards, by any path. A widened bound re-admits sessions the
            # neighbouring feature's window may already have chained onto, and the share
            # split then pays this feature for work it did not do. Its own exit code, and
            # the ONLY one `feature-capture.sh` continues past: see WIDEN_REFUSED_EXIT.
            print(
                f"refusing: session_window.to is {current} and {stamp} is later — a bound "
                "is only ever tightened, never widened; leave it as it is, or edit the "
                "manifest by hand if the recorded bound is genuinely wrong",
                file=sys.stderr,
            )
            return WIDEN_REFUSED_EXIT
        if new == old:
            print(f"session_window.to is already {current}; left alone")
            return 0
        # Inwards has an end: a `to` at or before `from` is an EMPTY window, which
        # `capture_planning.is_empty_window` drops from every other feature's claim set
        # outright — the feature would then own nothing at all, and only a WARN at its next
        # capture would say so. Compared as instants, the same reading the widen check
        # above uses; a fence with no `from` (or one that will not parse) is left unchecked
        # rather than guessed at. A plain 1, not the widen code: the capture must stop on it.
        # Unreachable from evidence — a branch-selected session starts at or after `from`,
        # so a bound one second past its last instant is strictly later than `from` — which
        # makes this a guard on the hand invocation the repair path invites.
        frm = to_instant((obj.get("session_window") or {}).get("from"))
        if frm is not None and new <= frm:
            print(
                f"refusing: session_window.from is {(obj.get('session_window') or {}).get('from')} "
                f"and {stamp} is not after it — a `to` at or before `from` is an empty "
                "window, which owns nothing and is dropped from every other feature's "
                "split; tighten to an instant inside the window, or fix `from` by hand",
                file=sys.stderr,
            )
            return 1
        replacing = '"[^"]*"'
    fence_text = match.group(1)
    new_fence, n = re.subn(
        r'("to"\s*:\s*)' + replacing, lambda m: m.group(1) + json.dumps(stamp), fence_text, count=1
    )
    if n != 1:
        print("refusing: could not find a `to` bound in the fence", file=sys.stderr)
        return 1
    path.write_text(text[: match.start(1)] + new_fence + text[match.end(1):])
    if current is None:
        print(f"session_window.to = {stamp}")
    elif args.replace:
        print(f"session_window.to replaced: {current} -> {stamp}")
    else:
        print(f"session_window.to tightened: {current} -> {stamp}")
    return 0


def session_first_instant(session_id):
    """The earliest timestamped instant of one top-level session's transcript, or None
    when no transcript carries that id or none of its lines is timestamped.

    The transcript is found the way `routing.find_transcript` finds a router's — a glob
    over every project directory rather than a lookup by launch directory — because the
    session a head belongs to is by definition one this feature did not launch, and the
    directory it ran in is exactly what cannot be reconstructed from here."""
    path = find_transcript(session_id)
    if path is None:
        return None
    moments = [
        moment
        for moment in (to_instant(line.get("timestamp")) for line in load_lines(path))
        if moment is not None
    ]
    return min(moments) if moments else None


def captured_at_of(args):
    """The feature's frozen `captured_at`, or None when nothing has captured it yet.

    Read straight off `planning.json` rather than through `capture_planning.prior_capture`:
    this module must not import that one (see the import block above), and the question —
    "is there a frozen figure this edit will not move?" — is one field deep."""
    planning = features_root(args.self_mode) / args.slug / "planning.json"
    try:
        record = json.loads(planning.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    captured_at = record.get("captured_at") if isinstance(record, dict) else None
    return captured_at if isinstance(captured_at, str) and captured_at.strip() else None


def cmd_set_window_from(args):
    """Move `session_window.from` BACK over a disclosed head, and print `old -> new`.

    The head is the stretch of a shared session that lies before every claimant's `from`
    and further back than the earliest claimant's own window is long: nobody owns it, and
    `capture_planning.py` names it in the unclaimed warning with both remedies. One of
    them has always had a tool (pin the session into the feature the work belongs to) and
    the other was "move the earliest claimant's `from` back by hand" — the one edit every
    manifest tells the author not to make. This is that tool.

    Three refusals, all plain 1s (there is no `feature-capture.sh` reading these codes,
    as there is for `set-window-to --tighten`'s widen refusal, so no code is reserved):

      - **earlier than the session's own first instant.** A `from` before the session it
        is meant to cover does not claim more of that session — it is already claiming
        all of it — and it does reach back over whatever else ran in that window. The
        session names itself in the warning, so the check costs one transcript read.
      - **later than the current `from`.** This command widens a claim backwards; nothing
        here narrows one. `set-window-to` moves `to`, and only inwards after the merge —
        there is no `from` equivalent and deliberately so: narrowing `from` un-claims work
        that is already frozen into a record, which `--recapture` would then have to
        rebuild from transcripts that may be gone. Edit the fence by hand if a `from` is
        genuinely wrong, and say so in the feature's notes.
      - **a `from` that is null or will not parse.** An unbounded `from` claims from the
        beginning of time already; there is no head in front of it to move over.

    A bound already equal to the one asked for is a no-op, exit 0, like `set-window-to`'s.
    On a feature already captured the edit is applied and the output says a `--recapture`
    is what moves the figure: the fence is the input to the next capture, never to the one
    that is already frozen."""
    path = manifest_path(args)
    text = path.read_text()
    match, obj = last_fence(text)
    window = obj.get("session_window") or {}
    current = window.get("from")
    stamp = args.timestamp
    new = to_instant(stamp)
    old = to_instant(current)
    if new is None:
        print(f"refusing: {stamp!r} is not an ISO 8601 instant", file=sys.stderr)
        return 1
    if old is None:
        print(
            f"refusing: session_window.from is {json.dumps(current)} — there is no bound "
            "to move back (an unbounded `from` already claims everything before `to`); "
            "write a real `from` first",
            file=sys.stderr,
        )
        return 1
    if new == old:
        print(f"session_window.from is already {current}; left alone")
        return 0
    if new > old:
        print(
            f"refusing: session_window.from is {current} and {stamp} is later — this "
            "command only ever moves `from` BACK, over a head no feature claims. Nothing "
            "narrows a `from`: `set-window-to` moves `to` (inwards only, after the merge), "
            "and narrowing `from` would un-claim work a frozen record already counts. Edit "
            "the fence by hand if the recorded `from` is genuinely wrong",
            file=sys.stderr,
        )
        return 1
    first = session_first_instant(args.session)
    if first is None:
        print(
            f"refusing: no transcript for session {args.session!r} under "
            "~/.claude/projects/ — the id is wrong, or it has aged out, and the new "
            "`from` cannot be checked against the session it is meant to cover",
            file=sys.stderr,
        )
        return 1
    if new < first:
        print(
            f"refusing: session {args.session} starts at "
            f"{first.isoformat().replace('+00:00', 'Z')} and {stamp} is earlier — a `from` "
            "before the session it is meant to cover claims no more of it and reaches back "
            "over whatever else ran then; move `from` to the session's own first instant "
            "or later",
            file=sys.stderr,
        )
        return 1
    fence_text = match.group(1)
    new_fence, n = re.subn(
        r'("from"\s*:\s*)"[^"]*"', lambda m: m.group(1) + json.dumps(stamp), fence_text, count=1
    )
    if n != 1:
        print("refusing: could not find a `from` bound in the fence", file=sys.stderr)
        return 1
    path.write_text(text[: match.start(1)] + new_fence + text[match.end(1):])
    print(f"session_window.from moved back: {current} -> {stamp}")
    captured_at = captured_at_of(args)
    if captured_at:
        print(
            f"note: {args.slug} was captured {captured_at}; the frozen figure does not "
            "move until capture_planning.py --recapture rebuilds it"
        )
    return 0


def cmd_set_plans(args):
    path = manifest_path(args)
    text = path.read_text()
    match, obj = last_fence(text)
    bad = [stem for stem in args.stems if not PLAN_STEM_RE.match(stem)]
    if bad:
        print(f"refusing: not a plan stem (NN-name-MODEL, no .md): {' '.join(bad)}", file=sys.stderr)
        return 1
    obj["plans"] = list(args.stems)
    path.write_text(text[: match.start(1)] + render_fence(obj) + text[match.end(1):])
    print(f"plans = {json.dumps(obj['plans'])}")
    return 0


def cmd_pin_session(args):
    """Add one session id to the fence's `sessions[]`, idempotently — the remedy
    `feature-close.sh` names when the feature's router built it unpinned
    (self/features/router-built-pin). Nothing else in the file moves."""
    session_id = args.session_id.strip()
    if not session_id:
        print("refusing: an empty session id pins nothing", file=sys.stderr)
        return 1
    path = manifest_path(args)
    text = path.read_text()
    match, obj = last_fence(text)
    sessions = list(obj.get(SESSIONS_KEY) or [])
    if session_id in sessions:
        print(f"{SESSIONS_KEY} already pins {session_id}")
        return 0
    sessions.append(session_id)
    obj[SESSIONS_KEY] = sessions
    path.write_text(text[: match.start(1)] + render_fence(obj) + text[match.end(1):])
    print(f"{SESSIONS_KEY} = {json.dumps(sessions)}")
    return 0


def cmd_claimed(args):
    planning = features_root(args.self_mode) / args.slug / "planning.json"
    if not planning.exists():
        print(f"no planning.json at {planning}", file=sys.stderr)
        return 1
    data = json.loads(planning.read_text())
    cost_by_session = {}
    cost_by_agent = {}
    for entry in data.get("priced", []):
        cost = entry.get("cost_usd") or 0.0
        if entry.get("agent_id"):
            cost_by_agent[entry["agent_id"]] = cost_by_agent.get(entry["agent_id"], 0.0) + cost
        else:
            cost_by_session[entry["session_id"]] = cost_by_session.get(entry["session_id"], 0.0) + cost
    print("sessions claimed:")
    for s in data.get("sessions", []):
        print(
            f"  {s['session_id']}  {s.get('selected_by', 'branch'):<7}  "
            f"{s.get('git_branch', ''):<24}  {s.get('started_at', '')[:19]}  "
            f"${cost_by_session.get(s['session_id'], 0.0):8.2f}  launched in {s.get('cwd') or '?'}"
        )
    if not data.get("sessions"):
        print("  (none)")
    print("subagents claimed:")
    for a in data.get("subagents", []):
        print(
            f"  agent-{a['agent_id']}  {a.get('selected_by', ''):<7}  parent {a.get('parent_session_id', '')[:8]}  "
            f"{a.get('started_at', '')[:19]}  ${cost_by_agent.get(a['agent_id'], 0.0):8.2f}"
        )
    if not data.get("subagents"):
        print("  (none)")
    total = data.get("cost_usd", {}).get("total", 0.0)
    partial = " (partial)" if data.get("cost_usd", {}).get("total_is_partial") else ""
    print(f"total ${total:.4f}{partial}")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_self_flag(parser)
    parser.add_argument("slug")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init", help="write the manifest from the template")
    p_init.add_argument("--method", required=True)
    p_init.add_argument("--branch", required=True)
    p_init.add_argument("--base", required=True)
    p_init.add_argument("--from", dest="window_from", required=True, metavar="TS")
    p_init.add_argument("--session", action="append", metavar="ID")
    p_init.add_argument("--plan", action="append", metavar="STEM")
    p_init.set_defaults(func=cmd_init)

    p_get = sub.add_parser("get", help="print one field of the fence (dotted path)")
    p_get.add_argument("key")
    p_get.set_defaults(func=cmd_get)

    p_to = sub.add_parser("set-window-to", help="stamp a null `to` bound")
    p_to.add_argument("timestamp", nargs="?")
    p_to.add_argument(
        "--tighten",
        action="store_true",
        help="also replace a bound already set, but only with an EARLIER instant — the "
        "post-merge repair path for a `to` stamped too late. A later one is refused (exit "
        f"{WIDEN_REFUSED_EXIT}); one at or before `from` is refused too, as an empty "
        "window (exit 1); the same one is a no-op",
    )
    p_to.add_argument("--replace", action="store_true", help=REPLACE_HELP)
    p_to.set_defaults(func=cmd_set_window_to)

    p_from = sub.add_parser(
        "set-window-from",
        help="move `from` BACK over a head no feature claims (the only command that "
        "moves `from`; nothing narrows one)",
    )
    p_from.add_argument("timestamp", metavar="TS")
    p_from.add_argument(
        "--session",
        required=True,
        metavar="ID",
        help="the session whose unclaimed head this `from` is being moved over — the id "
        "capture_planning.py's unclaimed warning names. Its transcript's first instant is "
        "the earliest bound this command will accept",
    )
    p_from.set_defaults(func=cmd_set_window_from)

    p_plans = sub.add_parser("set-plans", help="replace plans[] with these stems, in order")
    p_plans.add_argument("stems", nargs="+", metavar="STEM")
    p_plans.set_defaults(func=cmd_set_plans)

    p_pin = sub.add_parser(
        "pin-session",
        help="add a session id to the fence's sessions[] — the remedy feature-close.sh "
        "names when the feature's router built it unpinned",
    )
    p_pin.add_argument("session_id", metavar="ID")
    p_pin.set_defaults(func=cmd_pin_session)

    p_claimed = sub.add_parser("claimed", help="what planning.json claims, and the total")
    p_claimed.set_defaults(func=cmd_claimed)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
