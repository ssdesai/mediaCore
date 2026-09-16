#!/usr/bin/env python3
"""Read and write a feature manifest's machine-readable fence, and read what its
planning.json claimed — the JSON edits the lifecycle scripts need, kept out of bash.

    python3 agentTooling/analysis/manifest.py [--self] <slug> init --method M --branch B \\
        --base BASE --from TS [--session ID]... [--plan STEM]...
    python3 agentTooling/analysis/manifest.py [--self] <slug> get <key>
    python3 agentTooling/analysis/manifest.py [--self] <slug> set-plans <stem>...
    python3 agentTooling/analysis/manifest.py [--self] <slug> set-window-to [TS] [--tighten]
    python3 agentTooling/analysis/manifest.py [--self] <slug> claimed

`init` writes `<features>/<slug>/README.md` from `templates/plans/features/TEMPLATE.md`
with the template's fence replaced by a filled one, and refuses if the file exists —
`feature-start.sh` runs it, once, in the new worktree. `get` prints one scalar (or a
JSON array) from the LAST ```json fence, the one `capture_planning.py` reads. `set-window-to`
replaces a `null` `to` bound with TS (default: now, UTC, `Z`) and touches nothing else in
the file; a bound already set is left alone and reported, since a second stamp would move
a boundary another manifest may chain to. `--tighten` is the one exception and only ever
inwards: it replaces a bound already set with an EARLIER instant, printing `old -> new`,
treats the same instant as a no-op, and refuses a later one — a widened `to` re-admits
sessions the neighbouring feature's window may already have chained onto, and the share
split then pays this feature for work it did not do. Inwards has an end too: a bound at or
before the fence's `from` is an EMPTY window, which owns nothing and is dropped from every
other feature's split, and is refused as well. It is what
`feature-close.sh --recapture` runs to repair a `to` stamped at close time.
`set-plans` replaces `plans[]` with the stems given, in that order — how the
architect records the batch after `feature-start.sh` wrote the fence with only the review
stub in it — and refuses a stem that is not `NN-name-MODEL` (a sentinel is never a plan).
`claimed` prints the sessions and subagents
`planning.json` holds, each with how it was selected and where it was launched, and the
total — what `feature-close.sh` shows the human before the number is quoted.

Formatting is preserved: the fence is written one key per line with compact values,
the shape every hand-written manifest in both corpora already has, so a diff after
`init` or `set-window-to` shows the change and nothing else.

Exit codes: 0 success, a no-op included; 3 the widen refusal ALONE (`WIDEN_REFUSED_EXIT`
— `feature-close.sh` continues past that one and stops on every other); 1 any other
refusal; 2 argparse's usage error.
"""

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from roots import AGENT_TOOLING_DIR, add_self_flag, features_root

TEMPLATE_PATH = AGENT_TOOLING_DIR / "templates" / "plans" / "features" / "TEMPLATE.md"
FENCE_RE = re.compile(r"```json\n(.*?)\n```", re.DOTALL)
# The order the fence is written in, so every manifest reads the same way top to bottom.
FENCE_KEY_ORDER = (
    "slug", "method", "plans", "branches", "base", "session_window",
    "exclude_sessions", "exclude_subagents", "sessions", "subagents",
)
KNOWN_METHODS = ("plans", "direct", "hand")
# A plan stem: number, kebab name, model — the filename without `.md`. `NN-gate` is a
# sentinel, not a plan, and never belongs in `plans[]`; the model alternation excludes it.
PLAN_STEM_RE = re.compile(r"^[0-9]+-[a-z0-9-]+-(haiku|sonnet|opus)$")
# The exit code `set-window-to --tighten` gives the WIDEN refusal and nothing else, so
# that `feature-close.sh` can continue past that one refusal — the bound it declined to
# widen is the one already published — and stop on every other. Deliberately not 2:
# argparse exits 2 on a usage error, and a close that read a malformed invocation as a
# declined widen would stamp nothing, warn about a cause that did not happen, and then
# capture, commit, push and delete the branch, leaving a CLOSED feature with a permanently
# open window. Every other refusal in this module is a plain 1.
WIDEN_REFUSED_EXIT = 3


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
    if current is not None:
        # A bound already set is left alone by default: a second stamp would move a
        # boundary another manifest may chain onto, and `in_window` is half-open so that
        # they can. `--tighten` is the one exception, and only ever inwards.
        if not args.tighten:
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
        if new > old:
            # Never outwards, by any path. A widened bound re-admits sessions the
            # neighbouring feature's window may already have chained onto, and the share
            # split then pays this feature for work it did not do. Its own exit code, and
            # the ONLY one `feature-close.sh` continues past: see WIDEN_REFUSED_EXIT.
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
        # rather than guessed at. A plain 1, not the widen code: the close must stop on it.
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
    else:
        print(f"session_window.to tightened: {current} -> {stamp}")
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
        "repair path for a `to` stamped at close time. A later one is refused (exit "
        f"{WIDEN_REFUSED_EXIT}); one at or before `from` is refused too, as an empty "
        "window (exit 1); the same one is a no-op",
    )
    p_to.set_defaults(func=cmd_set_window_to)

    p_plans = sub.add_parser("set-plans", help="replace plans[] with these stems, in order")
    p_plans.add_argument("stems", nargs="+", metavar="STEM")
    p_plans.set_defaults(func=cmd_set_plans)

    p_claimed = sub.add_parser("claimed", help="what planning.json claims, and the total")
    p_claimed.set_defaults(func=cmd_claimed)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
