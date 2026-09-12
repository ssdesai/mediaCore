"""Freeze a feature's planning-phase session-transcript cost into `planning.json`.

Mines the interactive session transcripts under `~/.claude/projects/` for a
feature's branches (scoped by the manifest's optional `session_window`, since one
branch can host several features in sequence), excludes runner-spawned sessions,
and writes token counts plus priced dollars to `plans/features/<slug>/planning.json`.

CRITICAL DESIGN POINT: cost is computed once, here, and written as dollars into
`planning.json` alongside the token counts, `rates_applied`, and `rates_source`.
`report.py` (plan 56) must never recompute — it only reads and sums the dollar
figures this script already produced. Rates change (Sonnet 5's intro pricing
expires 2026-08-31), so recomputing at report time would silently reprice a
completed feature's planning cost and destroy cross-feature comparison.

Design decision: cost is priced per (session, model, is_sidechain), using that
session's own start date, then the resulting dollars are summed — raw tokens are
never summed across sessions first and priced once. A feature whose planning phase
straddles the Sonnet 5 intro-pricing expiry would otherwise have every token priced
at whichever rate wins after aggregation, silently mispricing part of the feature.

Subagent transcripts — `<session-id>/subagents/agent-<id>.jsonl` beside the parent's
file — are priced too. They carry the *parent's* `gitBranch` and `cwd`, not their own
(a plan author spawned from a coordinator on `main` says `main` even when its whole
job was one feature branch), so they cannot be selected by branch. Two routes in:
a subagent whose parent session is selected is priced when its own start falls in
the `session_window`; and a manifest may pin `"subagents": ["<agent-id>"]` to claim
one whose parent is not selected at all — the coordinator-on-main case. Pinned
subagents bypass the branch and window filters: the pin is the human's word.
`--list-subagents [--since DATE]` prints every subagent this repo's transcripts
hold, with its cost and opening prompt, which is how to find an id to pin.

Populates only what is not yet populated. A feature whose `planning.json` already
carries a `captured_at` is not re-derived — nothing rewrites a frozen record's figures
without being asked, and the transcript scan is skipped entirely, so a corpus-wide run
costs almost nothing. Such a record does get one thing refreshed in place: its
`sessions[].also_claimed_by`, from the claims ledger, which opens no transcript and
changes no dollar, duration or `captured_at` (`annotate_frozen_record`). That run
reports the feature as `annotated` rather than `skipped`, and is how a feature closed
before another feature claimed its coordinator session ever comes to say so.
`--recapture` rebuilds from transcripts anyway; `--all` walks every feature, skipping any
whose `session_window.to` is still null — in flight, and `feature-close.sh`'s to capture.

Usage: python3 agentTooling/analysis/capture_planning.py <slug>
       python3 agentTooling/analysis/capture_planning.py --all [--recapture]
       python3 agentTooling/analysis/capture_planning.py --list-subagents [--since YYYY-MM-DD]
       python3 agentTooling/analysis/capture_planning.py --list-subagents --unclaimed --for <repo>/<slug>
       python3 agentTooling/analysis/capture_planning.py --last-branch-instant <slug>
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

from pricing import RATES_VERIFIED, compute_cost, is_rates_stale
from roots import (
    SELF_CORPUS_IDENTITY, add_self_flag, all_features_roots, features_root, session_root,
)
from transcript import add_usage, iter_billable_messages, iter_billable_messages_at, to_utc

# Feature worktree layout (LIFECYCLE.md): the directory under the primary checkout that
# holds every feature's worktree. feature-start.sh and feature-close.sh each hold the same
# name in one constant of their own; the three move together.
WORKTREES_DIR_NAME = ".worktrees"

# Claude Code's project-directory naming: every one of these characters in the launch cwd
# becomes `TRANSCRIPT_DIR_MANGLE_TO`, which is why `<R>/.worktrees/<slug>` is filed under
# `…-<R>--worktrees-<slug>`.
TRANSCRIPT_DIR_MANGLED_CHARS = "/."
TRANSCRIPT_DIR_MANGLE_TO = "-"


def transcript_dir_name(repo_dir):
    """cwd path -> its transcript directory name under ~/.claude/projects/,
    e.g. /Users/x/dev/vinylCatalogue -> -Users-x-dev-vinylCatalogue, and a feature
    worktree /Users/x/dev/vinylCatalogue/.worktrees/foo -> …-vinylCatalogue--worktrees-foo.
    Claude Code turns every character in `TRANSCRIPT_DIR_MANGLED_CHARS` into `-`; mangling
    only `/`, as this did before, left a `.` anywhere in the primary's own path in the
    fragment, which then matched no project directory at all.

    For matching ~/.claude/projects/ directory *names* only. The mangled form is
    not a valid prefix or substring test against a real filesystem path (a `cwd`
    value) — see the repo_match fallback in main(), which uses the unmangled
    session root for that instead."""
    return "".join(
        TRANSCRIPT_DIR_MANGLE_TO if char in TRANSCRIPT_DIR_MANGLED_CHARS else char
        for char in str(repo_dir)
    )


def parse_manifest(readme_path):
    """Find the *last* ```json fence in a feature README and parse it. There may
    be earlier fences (examples, snippets) — only the last one is the manifest."""
    text = readme_path.read_text()
    matches = re.findall(r"```json\n(.*?)\n```", text, re.DOTALL)
    if not matches:
        raise ValueError(f"no ```json fence found in {readme_path}")
    return json.loads(matches[-1])


def normalize_window(manifest):
    """Missing key, null value, and {"from": null, "to": null} are all "no
    window" — open-ended on both sides.

    Both bounds are parsed to aware UTC datetimes here, once, so every later
    comparison is between instants rather than between strings. A bound that fails to
    parse becomes None — an unbounded side — which is the safe direction: it captures
    too much and shows up as a session the author must exclude, where the alternative
    (treating it as a bound at an arbitrary instant) would drop sessions silently.
    """
    window = manifest.get("session_window") or {}
    return {"from": to_utc(window.get("from")), "to": to_utc(window.get("to"))}


# A bound states its zone when it ends in Z or an explicit +-HH:MM / +-HHMM offset.
# Anchored at the end, past the date's own hyphens, so "2026-07-17" cannot read as one.
EXPLICIT_ZONE_RE = re.compile(r"(?:[Zz]|[+-]\d{2}:?\d{2})$")


def check_naive_bounds(manifest):
    """Warn for each `session_window` bound that does not state its timezone.

    A bound is typed by a human, and the natural way to find one is `git log`, which
    prints LOCAL time. Such a value is read as UTC (see `transcript.to_utc`), so a bound
    meaning 18:00 EDT silently filters at 18:00 UTC - four hours of sessions attributed
    to the wrong feature, with nothing in the output to say so. The string is not
    self-describing, so this is the only place that ambiguity can be surfaced.

    Warns rather than fails, for the reason everything else here does: the committed
    corpora were written naive against exactly this reading, and failing would break
    every one of them at once. The warning states which reading it took, so an author
    who meant local can correct it and one who meant UTC can silence it with the `Z`.

    Only the captured feature's own manifest. `check_branch_overlap` reads every other
    manifest in both corpora, and warning about those would bury the actionable line
    under noise about files this author is not editing.
    """
    warnings = []
    window = manifest.get("session_window") or {}
    for field in ("from", "to"):
        value = window.get(field)
        if not isinstance(value, str) or not value.strip():
            continue
        if EXPLICIT_ZONE_RE.search(value.strip()):
            continue
        warnings.append(
            f"session_window.{field} {value!r} has no timezone offset and is being "
            "read as UTC. Append 'Z' if that is what you meant; if you copied a local "
            "time (git log prints local), write the offset explicitly, e.g. "
            f"'{value}-04:00'"
        )
    return warnings


def is_empty_window(window):
    """Whether a normalized window is proven to match nothing: `from >= to`.

    The rule lives here once because two callers need the same answer and would drift
    apart if each spelled it out. `check_empty_window` turns it into the warning a
    malformed manifest deserves; `share_owners` uses it to keep such a claim out of the
    head-stretch fallback, which is the one place a window that matches nothing could
    still be handed time. Both bounds must be present — an open-ended window is
    unbounded, not empty.
    """
    frm, to = window.get("from"), window.get("to")
    return frm is not None and to is not None and frm >= to


def check_empty_window(window):
    """Warn when a normalized `session_window` cannot match anything: `from >= to`.

    The window is half-open (see `in_window`), so `from == to` selects nothing at all
    and `from > to` is the same emptiness written backwards. Either way every session
    on the branch is dropped and the feature freezes at $0.00 — the same silent wrong
    answer `check_unmatched_branches` exists to catch, arriving by a different route
    and, until this check, with nothing in the output to distinguish it from a feature
    that genuinely had no planning.

    Unlike the overlap warning this is not an over-approximation: an empty interval is
    *proven* to match nothing, from the manifest alone, without walking a transcript.
    There is no legitimate reason to write one, so the message says the feature will
    capture as zero rather than hedging about what might happen.

    Takes the normalized window rather than the raw manifest — the emptiness is a fact
    about the two instants, and comparing the raw strings would miss `19:00:00-04:00`
    against `23:00:00Z`, which are the same instant written two ways.

    Warns rather than refuses to stay consistent with the other manifest checks, which
    run on the already-captured skip path too: a corpus can hold a frozen feature whose
    window is empty, and that is worth hearing about on every pass, not only on the run
    that would rewrite it.
    """
    if not is_empty_window(window):
        return []
    frm, to = window.get("from"), window.get("to")
    relation = "equals" if frm == to else "is later than"
    return [
        f"session_window is empty — `from` ({frm.isoformat()}) {relation} `to` "
        f"({to.isoformat()}), and the window is half-open, so it matches no session "
        "at all and this feature will capture as $0.00 regardless of what is on its "
        "branch. A session named in `sessions` is pinned by id and admitted without "
        "consulting the window, so those are still captured — in full while no other "
        "feature claims one, and at $0.00 as soon as one does, since an empty window "
        "can own no share of a session it is split against. Widen the window to cover "
        "the sessions you mean; to chain onto a neighbouring feature, give this one a "
        "`from` at the neighbour's `to`"
    ]


def in_window(moment, window):
    """Half-open bound check — `from` inclusive, `to` exclusive — between aware UTC
    datetimes, as produced by `normalize_window` and `transcript.to_utc`.

    Instants, not strings. Lexicographic comparison happens to be right for two
    same-shape UTC strings and is wrong the moment one carries an offset: a `to` bound
    of "2026-07-17T18:00:00-04:00" sorts *below* a session at "2026-07-17T22:00:00Z"
    despite being the same instant. Parsing costs nothing here and removes the whole
    class.

    `to` is exclusive so that consecutive features can chain windows end to end
    (`{"to": T}` followed by `{"from": T}`) and be genuinely disjoint rather than
    both claiming a session that starts exactly at `T`. That is already how this
    corpus is written — `plan-analytics` ends where `agenttooling-self-host`
    begins — and under an inclusive `to` every such handoff is a latent
    double-count that `check_branch_overlap` then has to warn about forever.
    """
    frm = window.get("from")
    to = window.get("to")
    if moment is None:
        return False
    if frm is not None and moment < frm:
        return False
    if to is not None and moment >= to:
        return False
    return True


def collect_excluded_session_ids(features_dirs, manifest):
    """Runner-spawned sessions (every session_id recorded in a usage.json sidecar,
    across every feature and queue) union the manifest's own exclude_sessions.

    Reads `attempts[]`, not just the top-level `session_id`. Resuming a plan is a
    fresh `claude -p` with a fresh session id (RUNNER.md, "How resume works"), and
    the top-level field names only the last one — so a plan that was resumed twice
    has two runner sessions that no sidecar field but `attempts[]` mentions. Missing
    them does not merely lose their cost: they are interactive-looking sessions on
    the feature's own branch, so they get priced here as planning cost.

    Takes *both* corpora (roots.all_features_roots()), never just the one being
    captured. Two trees share one branch namespace, so scoping this to the feature's
    own tree reintroduces exactly the bug the paragraph above describes.
    """
    excluded = set(manifest.get("exclude_sessions", []) or [])
    for features_dir in features_dirs:
        for usage_path in features_dir.rglob("*.usage.json"):
            try:
                data = json.loads(usage_path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            session_id = data.get("session_id")
            if session_id:
                excluded.add(session_id)
            for attempt in data.get("attempts") or []:
                attempt_id = attempt.get("session_id")
                if attempt_id:
                    excluded.add(attempt_id)
    return excluded


def find_transcript_dirs(repo_dir):
    """Every directory under ~/.claude/projects/ whose name contains this repo's
    transcript-dir-name as a substring — not just the canonical one. A session
    whose cwd moved into a scratchpad gets its own project directory, named for
    the scratchpad path, which still embeds the encoded repo name."""
    projects_root = Path.home() / ".claude" / "projects"
    if not projects_root.exists():
        return []
    fragment = transcript_dir_name(repo_dir)
    return sorted(
        d for d in projects_root.iterdir() if d.is_dir() and fragment in d.name
    )


def load_transcript_lines(path):
    """Parse each non-blank line as JSON, skipping (not raising on) a line that
    fails to parse."""
    lines = []
    with open(path, "r") as f:
        for raw_line in f:
            raw_line = raw_line.strip()
            if not raw_line:
                continue
            try:
                lines.append(json.loads(raw_line))
            except json.JSONDecodeError:
                continue
    return lines


def subagent_transcript_paths(transcript_dir, session_id):
    """The subagent transcripts of one session: `<transcript_dir>/<session_id>/subagents/
    agent-*.jsonl`. Sorted, so a capture is deterministic. Empty when the session spawned
    none, which is every runner session and most interactive ones."""
    subagents_dir = transcript_dir / session_id / "subagents"
    if not subagents_dir.is_dir():
        return []
    return sorted(subagents_dir.glob("agent-*.jsonl"))


def feature_worktree_path(primary, slug):
    """The feature's worktree as `feature-start.sh` creates it, `<primary>/.worktrees/<slug>`
    (LIFECYCLE.md). Derived from the slug rather than looked up, so it still resolves after
    `feature-close.sh` has removed the worktree."""
    return f"{primary}/{WORKTREES_DIR_NAME}/{slug}"


def legacy_worktree_path(primary, slug):
    """The sibling `<primary>-<slug>` `feature-start.sh` created before worktrees moved
    inside the primary. A feature started then keeps it until it closes, and it stays
    claimable for good: a `--recapture` of such a feature that could not claim it would
    drop every session launched there and shrink the frozen cost."""
    return f"{primary}-{slug}"


def claim_roots(primary, slug):
    """`(roots, fences)` for `cwd_under_any`, for feature `slug`. The roots are where a
    session it may claim was launched: the primary checkout, this feature's worktree and
    its legacy sibling. The fence is the one directory under a root that is NOT
    claimable, `<primary>/.worktrees`, which holds every other feature's worktree — under
    the primary, so the primary root alone would hand every feature's sessions to every
    other feature."""
    roots = (primary, feature_worktree_path(primary, slug), legacy_worktree_path(primary, slug))
    fences = (f"{primary}/{WORKTREES_DIR_NAME}",)
    return roots, fences


def path_at_or_under(path, base):
    """Whether `path` is `base` or a path beneath it — a component test, so `<R>-x` is not
    under `<R>`."""
    return path == base or path.startswith(base + "/")


def cwd_claimable(cwd, roots, fences=()):
    """Whether a launch directory is claimable: the most specific — longest — of `roots`
    and `fences` that `cwd` is at or under must be a root. So `<R>/.worktrees/<other>`
    falls to the fence `<R>/.worktrees` although it is also under the root `<R>`, while
    `<R>/.worktrees/<slug>` is claimed by its own, longer root. A cwd under neither is not
    claimable."""
    best_len = -1
    best_is_root = False
    for base, is_root in [(root, True) for root in roots] + [(fence, False) for fence in fences]:
        if path_at_or_under(cwd, base) and len(base) > best_len:
            best_len, best_is_root = len(base), is_root
    return best_is_root


def cwd_under_any(lines, roots, fences=()):
    """Whether any line's cwd is claimable from `roots` past `fences` (`cwd_claimable`;
    `claim_roots` builds both for a feature). A prefix test on the primary alone once
    dropped every session launched in a sibling worktree — the bug the triage under self/
    measured — and, with worktrees nested inside the primary, would now claim every other
    feature's; the fence is what stops the second."""
    for line in lines:
        cwd = line.get("cwd")
        if not isinstance(cwd, str):
            continue
        if cwd_claimable(cwd, roots, fences):
            return True
    return False


def find_session_elsewhere(session_id, skip_dirs):
    """The transcript of a pinned *session* under any project directory but the ones
    already scanned — the planning session that began on `main` in some other checkout
    before the feature branch existed. A session id is unambiguous, so the pin is
    honoured wherever the file is."""
    projects_root = Path.home() / ".claude" / "projects"
    if not projects_root.exists():
        return None
    for project_dir in sorted(projects_root.iterdir()):
        if not project_dir.is_dir() or project_dir in skip_dirs:
            continue
        candidate = project_dir / f"{session_id}.jsonl"
        if candidate.exists():
            return candidate
    return None


def find_pinned_elsewhere(agent_id, skip_dirs):
    """The transcript of a pinned subagent under *any* project directory but the ones
    already scanned. A delegate's transcript lives beside its parent's, under the
    parent's cwd — so an architect a coordinator in repo A spawned to work on repo B
    is filed under A. B's manifest pins it by id, and an id is unambiguous, so the pin
    is honoured wherever the file is."""
    projects_root = Path.home() / ".claude" / "projects"
    if not projects_root.exists():
        return None
    for project_dir in sorted(projects_root.iterdir()):
        if not project_dir.is_dir() or project_dir in skip_dirs:
            continue
        hits = sorted(project_dir.glob(f"*/subagents/agent-{agent_id}.jsonl"))
        if hits:
            return hits[0]
    return None


def price_subagent(totals, session_id, agent_id, agent_lines):
    """Add every billable message of one subagent transcript to `totals` under
    (session_id, agent_id, model, True, ()). Every line of a subagent transcript says
    `isSidechain: true`, so the flag is pinned here rather than read — a subagent is
    sidechain cost by definition, whatever an individual line says. The trailing `()`
    is the same empty refs tuple an unshared session's key carries: a subagent belongs
    to exactly one feature by the claims-ledger refusal, so it is never split."""
    for model, usage, _ in iter_billable_messages(agent_lines):
        add_usage(totals, (session_id, agent_id, model, True, ()), usage)


def agent_start_of(agent_lines):
    """Earliest timestamp in a transcript, or None when it carries none."""
    moments = [
        moment
        for moment in (to_utc(line.get("timestamp")) for line in agent_lines)
        if moment is not None
    ]
    return min(moments) if moments else None


def agent_end_of(agent_lines):
    """Latest timestamp in a transcript, or None when it carries none."""
    moments = [
        moment
        for moment in (to_utc(line.get("timestamp")) for line in agent_lines)
        if moment is not None
    ]
    return max(moments) if moments else None


def duration_seconds(start, end):
    """Whole seconds from `start` to `end`, or None when either is missing. A span,
    not an activity measure: a subagent runs start to finish with no idle in between,
    so its span is its working time, but an interactive session's span includes every
    minute the human was away, and a coordinator's every minute it waited on a batch.
    report.py keeps the two apart for that reason."""
    if start is None or end is None:
        return None
    return int((end - start).total_seconds())


def agent_id_of(path, lines):
    """A subagent's id: the `agentId` its lines carry, else the filename minus `agent-`.
    The two agree on every transcript seen so far; the fallback is for a file whose
    first lines are attachments without the field."""
    for line in lines:
        agent_id = line.get("agentId")
        if isinstance(agent_id, str) and agent_id:
            return agent_id
    return path.stem[len("agent-"):] if path.stem.startswith("agent-") else path.stem


# The claims ledger: every subagent transcript and every top-level session this tool has
# ever priced, with the feature that claimed it. It lives beside the transcripts (under
# ~/.claude) and is scoped like them — local to this machine, meaningless once they
# expire — so it needs no knowledge of where the other repos are checked out. There is no
# override for its path other than $HOME itself, deliberately: `Path.home()` resolves the
# transcript glob too, so a test that redirects $HOME moves both together and one that
# moved only the ledger would still read the machine's own transcripts.
CLAIMS_LEDGER_NAME = "subagent-claims.json"
# Its two sections. Kept apart because the two kinds of claim have different arities: a
# subagent transcript belongs to exactly one feature and a second claim is refused, while
# a coordinator SESSION legitimately spans features — so a subagent id maps to one claim
# and a session id to a LIST of them. A file carrying neither key is the original flat
# `{<agent-id>: {…}}` shape, read as the subagents section (see `load_ledger`); an agent
# id is a hex token and can never collide with either key.
LEDGER_SUBAGENTS_KEY = "subagents"
LEDGER_SESSIONS_KEY = "sessions"
# A session claim records the window it was claimed with, so a capture in another repo
# can split the session against it. A claim written before this field exists is read as
# unbounded, which reproduces the old "counts the whole transcript" behaviour as an even
# split rather than silently dropping the claimant.
LEDGER_CLAIM_WINDOW_KEY = "window"
# The first line of a delegate's brief names the feature it is for (ORCHESTRATION.md):
#   feature: <repo>/<slug>
BRIEF_FEATURE_RE = re.compile(r"^\s*feature:\s*([\w.-]+)/([\w.-]+)\s*$", re.MULTILINE)
# The same `<repo>/<slug>` as an argument rather than a brief line: what `--for` takes.
FEATURE_REF_RE = re.compile(r"^([\w.-]+)/([\w.-]+)$")


def claims_ledger_path():
    return Path.home() / ".claude" / CLAIMS_LEDGER_NAME


def load_ledger():
    """The whole ledger as `{"subagents": {…}, "sessions": {…}}`.

    **An old ledger file loads unchanged.** Every one on disk today is the flat
    `{<agent-id>: {repo, slug, …}}` map this started as, with no section keys at all;
    such a file is read as the subagents section entire, nothing is migrated on read, and
    the two-section shape is written by the next capture. A file that is missing,
    unparseable, or not an object yields two empty sections rather than raising — the
    ledger is a cache of what other captures did, and a corrupt one must not stop this
    run from writing its own record."""
    path = claims_ledger_path()
    if not path.exists():
        return {LEDGER_SUBAGENTS_KEY: {}, LEDGER_SESSIONS_KEY: {}}
    try:
        ledger = json.loads(path.read_text())
    except json.JSONDecodeError:
        return {LEDGER_SUBAGENTS_KEY: {}, LEDGER_SESSIONS_KEY: {}}
    if not isinstance(ledger, dict):
        return {LEDGER_SUBAGENTS_KEY: {}, LEDGER_SESSIONS_KEY: {}}
    if LEDGER_SUBAGENTS_KEY in ledger or LEDGER_SESSIONS_KEY in ledger:
        return {
            LEDGER_SUBAGENTS_KEY: ledger.get(LEDGER_SUBAGENTS_KEY) or {},
            LEDGER_SESSIONS_KEY: ledger.get(LEDGER_SESSIONS_KEY) or {},
        }
    return {LEDGER_SUBAGENTS_KEY: ledger, LEDGER_SESSIONS_KEY: {}}


def load_claims():
    """The subagents section alone — what every caller that predates session claims
    wants, and what `check_claims`, `record_claims` and `unclaimed_under` take."""
    return load_ledger()[LEDGER_SUBAGENTS_KEY]


def save_ledger(claims, session_claims):
    """Write both sections. Always both: they share one file, so writing one alone would
    drop the other."""
    path = claims_ledger_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    ledger = {
        LEDGER_SUBAGENTS_KEY: dict(sorted(claims.items())),
        LEDGER_SESSIONS_KEY: dict(sorted(session_claims.items())),
    }
    path.write_text(json.dumps(ledger, indent=2) + "\n")


def repo_identity(checkout_dir):
    """What makes two captures 'the same repo' in the ledger: the origin URL, which
    survives worktrees and scratch clones; the directory name when there is none.

    Asked of a *checkout* — "which repo is this directory in" — which is why the
    parameter is named for one. A corpus's identity goes through `corpus_identity`
    instead, which declares the self corpus's rather than deriving it; a vendored
    `agentTooling/` has no `.git` and this would walk up out of it and answer with the
    consumer's origin. `corpus_identity` is this function's only caller."""
    try:
        url = subprocess.run(
            ["git", "-C", str(checkout_dir), "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=10,
        )
        if url.returncode == 0 and url.stdout.strip():
            return url.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return Path(checkout_dir).name


def repo_display_name(identity):
    """The name a brief's `feature: <repo>/<slug>` line uses — the last path segment of
    the origin URL without `.git`, so a scratch worktree named `wt-musicMap` is still
    `musicMap`; the identity itself when it is already a bare directory name."""
    tail = identity.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]
    return tail[:-len(".git")] if tail.endswith(".git") else tail


def corpus_identity(features_dir):
    """Which repo the corpus under `features_dir` belongs to — the `repo` half of the
    `(repo, slug)` key the claims ledger records and the session share split dedupes on.
    ONE rule, so that a feature cannot enter the ledger under one identity and be looked
    for under another.

    Declared for agentTooling's own corpus (`roots.SELF_CORPUS_IDENTITY`), derived from
    the enclosing checkout's origin for every other. The self corpus cannot be derived:
    `<consumer>/agentTooling/self/features` has `<consumer>/agentTooling` two levels up
    and that directory has no `.git`, so `repo_identity` walks out of the vendored copy
    and answers with the CONSUMER's origin. Every self-corpus manifest then entered the
    consumer's claim set as `(<consumer origin>, <slug>)` while the ledger — written by
    the standalone checkout's own `--self` runs — held the same feature as
    `(https://github.com/ssdesai/agentTooling.git, <slug>)`. Two keys for one feature,
    both surviving the dedupe: the feature counted twice and `share_basis` naming a
    `<consumer>/<slug>` that exists nowhere. Measured on session `ed088063`, 13 intervals
    for 11 real claimants.

    Compared against `features_root(True)` rather than tested for a `self/features` tail,
    because that is the same object every caller here is handed — `main` passes
    `features_root(args.self_mode)` and the claimant index walks `all_features_roots()`,
    both from `roots`, both already resolved.

    Two questions, and only one of them is this: which corpus a FEATURE belongs to.
    Which repo a *checkout* is — the origin of a directory on disk — is the other, and
    it is `repo_identity`, called from here and nowhere else, on `features_dir.parents[1]`.
    They are not interchangeable and cannot be collapsed into one answer: transcripts are
    filed under the enclosing repo's project directory, so a `--self` session in a
    vendored checkout really did run in the consumer's repo while the feature it was
    building belongs to agentTooling.
    """
    features_dir = Path(features_dir)
    if features_dir == features_root(True):
        return SELF_CORPUS_IDENTITY
    return repo_identity(features_dir.parents[1])


def brief_feature_of(lines):
    """`(repo, slug)` from the `feature: <repo>/<slug>` line of a delegate's brief, or
    None when the brief carries none."""
    match = BRIEF_FEATURE_RE.search(first_user_text(lines, limit=None))
    return (match.group(1), match.group(2)) if match else None


def parse_feature_ref(text):
    """`(repo, slug)` from a `<repo>/<slug>` argument — the inverse of the header
    `brief_feature_of` reads, so `--for` can compare the two as the same structured
    pair. None when the argument is not that shape."""
    match = FEATURE_REF_RE.match(text.strip())
    return (match.group(1), match.group(2)) if match else None


def check_brief_headers(agent_briefs, repo_name, slug):
    """Warn for each pinned subagent whose brief names a different feature than the
    manifest pinning it — the pin is the human's word, the brief is the coordinator's,
    and when they disagree one of them is wrong."""
    warnings = []
    for agent_id in sorted(agent_briefs):
        named = agent_briefs[agent_id]
        if named and named != (repo_name, slug):
            warnings.append(
                f"pinned subagent {agent_id!r} was briefed for feature "
                f"'{named[0]}/{named[1]}', not '{repo_name}/{slug}' — one of the pin "
                "and the brief is wrong"
            )
    return warnings


def check_claims(agent_ids, repo, slug, claims):
    """Every priced subagent already claimed by a *different* (repo, slug). A capture
    that would double-count is refused outright: two features cannot both own one
    transcript's cost, and neither manifest can see the other repo to warn."""
    conflicts = []
    for agent_id in sorted(agent_ids):
        claim = claims.get(agent_id)
        if claim and (claim.get("repo"), claim.get("slug")) != (repo, slug):
            conflicts.append((agent_id, claim.get("repo_name", claim.get("repo")), claim.get("slug")))
    return conflicts


def record_claims(claims, agent_costs, agent_selected_by, repo, repo_name, slug):
    """Replace this (repo, slug)'s ledger entries with the subagents priced now — an
    id no longer pinned or selected drops out and shows up as unclaimed again."""
    for agent_id in [
        aid for aid, claim in claims.items()
        if (claim.get("repo"), claim.get("slug")) == (repo, slug)
    ]:
        del claims[agent_id]
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    for agent_id, cost in agent_costs.items():
        claims[agent_id] = {
            "repo": repo,
            "repo_name": repo_name,
            "slug": slug,
            "selected_by": agent_selected_by[agent_id],
            "cost_usd": cost,
            "claimed_at": now,
        }


def other_session_claimants(session_claims, session_id, repo, slug):
    """`["<repo_name>/<slug>", …]` for every OTHER feature the ledger records as counting
    this session, or `[]`. Not a refusal, unlike `check_claims`: a coordinator session
    that ran seven features is claimed by all seven and priced in full by each, because
    the transcript cannot say which feature a message served and a split by count would
    be a number nobody measured. What it can say is that the figure is not this feature's
    alone, which is what this annotation is for."""
    others = []
    for claim in session_claims.get(session_id) or []:
        if (claim.get("repo"), claim.get("slug")) == (repo, slug):
            continue
        name = claim.get("repo_name") or claim.get("repo")
        others.append(f"{name}/{claim.get('slug')}")
    return sorted(set(others))


def _iso_or_none(moment):
    """An aware UTC datetime as an ISO 8601 string with a `Z` suffix rather than the
    `+00:00` `datetime.isoformat()` writes for it, or None. Every instant here already
    went through `to_utc`, so this is always a lossless round trip of it — and it is
    what lets a bound serialized this way (a ledger claim's `window`, a `share_basis`
    entry's `from`/`to`) compare equal to the `Z`-suffixed string a manifest wrote it
    with, when the two name the same instant."""
    return moment.isoformat().replace("+00:00", "Z") if moment is not None else None


def _window_iso(window):
    """A normalized `{"from", "to"}` window as ISO strings (or None) — the shape a
    ledger claim's `window` key carries, so another repo's capture reads the instant
    this claim was made with rather than re-parsing whatever zone format the pinning
    manifest happened to use."""
    return {"from": _iso_or_none(window["from"]), "to": _iso_or_none(window["to"])}


def record_session_claims(session_claims, session_costs, session_selected_by, repo, repo_name, slug, window):
    """Replace this (repo, slug)'s session claims with the sessions priced now, keeping
    every other feature's. A session id maps to a LIST of claims — the difference from
    `record_claims`, and the whole of item 3: two features may both legitimately count one
    coordinator, so the ledger records both and neither is refused.

    `window` is this feature's own normalized `session_window`, written into every claim
    under `LEDGER_CLAIM_WINDOW_KEY` as ISO strings — the normalized instants, not the
    manifest's raw ones, so a bound written in local time reaches another repo's capture
    as the instant it is."""
    for session_id in list(session_claims):
        remaining = [
            claim for claim in session_claims[session_id]
            if (claim.get("repo"), claim.get("slug")) != (repo, slug)
        ]
        if remaining:
            session_claims[session_id] = remaining
        else:
            del session_claims[session_id]
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    window_iso = _window_iso(window)
    for session_id, cost in session_costs.items():
        session_claims.setdefault(session_id, []).append({
            "repo": repo,
            "repo_name": repo_name,
            "slug": slug,
            "selected_by": session_selected_by.get(session_id, "branch"),
            "cost_usd": cost,
            "claimed_at": now,
            LEDGER_CLAIM_WINDOW_KEY: window_iso,
        })


def add_session_claims(session_claims, session_costs, session_selected_by, repo, repo_name, slug, window):
    """Add this (repo, slug)'s session claims where the ledger does not already hold them,
    and change nothing it does. Returns True when it added any.

    The difference from `record_session_claims`, which REPLACES this feature's claims
    wholesale: that one is written by a capture that has just re-derived every figure
    from transcripts, this one by the annotate-only path over a record it must not touch.
    So an existing claim keeps its own `claimed_at` and its own dollars, and a second
    sweep over an unchanged corpus writes nothing at all — the ledger file included.

    `window` is this feature's own normalized `session_window`, read from its manifest
    since this path runs no transcript scan of its own; see `record_session_claims` for
    why it is written normalized rather than raw."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    window_iso = _window_iso(window)
    added = False
    for session_id, cost in session_costs.items():
        claims = session_claims.get(session_id) or []
        if any((claim.get("repo"), claim.get("slug")) == (repo, slug) for claim in claims):
            continue
        claims.append({
            "repo": repo,
            "repo_name": repo_name,
            "slug": slug,
            "selected_by": session_selected_by.get(session_id, "branch"),
            "cost_usd": cost,
            "claimed_at": now,
            LEDGER_CLAIM_WINDOW_KEY: window_iso,
        })
        session_claims[session_id] = claims
        added = True
    return added


def load_frozen_record(output_path):
    """A frozen `planning.json` as a dict, or None when there is nothing to annotate — no
    file, unreadable, not an object, or no `captured_at`. The same bar `prior_capture`
    applies to the same file, for the same reason: a record that cannot be read holds
    nothing worth keeping and nothing worth annotating."""
    try:
        record = json.loads(output_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(record, dict):
        return None
    captured_at = record.get("captured_at")
    if not isinstance(captured_at, str) or not captured_at.strip():
        return None
    return record


def frozen_session_costs(record):
    """`({session_id: own dollars}, {session_id: selected_by})` read out of a frozen
    record's own `sessions[]` and `priced[]`. No manifest, no transcript — the record
    already says which sessions it counted and what it paid for them, which is the whole
    of what the ledger records.

    A session's OWN priced rows, its delegates' excluded, exactly as the capture computes
    them: a subagent belongs to exactly one feature by the ledger's refusal, so rolling
    its cost in here would report money that is not in fact counted twice."""
    costs = {}
    selected_by = {}
    for entry in record.get("sessions") or []:
        session_id = entry.get("session_id")
        if not session_id:
            continue
        costs[session_id] = 0.0
        selected_by[session_id] = entry.get("selected_by") or "branch"
    for row in record.get("priced") or []:
        session_id = row.get("session_id")
        if row.get("agent_id") or session_id not in costs:
            continue
        costs[session_id] += row.get("cost_usd") or 0.0
    return costs, selected_by


def annotate_frozen_record(output_path, record, session_claims, repo, slug):
    """Refresh a frozen record's `sessions[].also_claimed_by` from the claims ledger,
    writing `planning.json` only when something changed. Returns
    `(annotated_session_ids, changed)`.

    **Two values, never folded into one.** "Which sessions are annotated" and "did this
    run write" are different questions, and returning `annotated or None` answered only
    the second: the caller's `predates the share rule` WARN sat in the `else` of `if
    annotated is None`, so it fired on the first `--all` that converged the annotation and
    never again, while the stale full-count figure was still sitting there. `sweep.sh`
    runs `--all` weekly, so that warning was seen once per corpus. The annotation converges
    on the first pass by design (`register_frozen_claims`), which makes "changed" exactly
    the wrong condition to key a standing repair request off — `check_empty_window` states
    the same doctrine a few hundred lines up this file: worth hearing about on every pass,
    not only on the run that would rewrite it.

    **It opens no transcript and changes no figure.** Every dollar, every duration,
    `captured_at`, `rates_source`, `warnings`, every session and subagent entry is left
    byte-identical; only this one key moves. That is the point rather than an
    optimisation: the seven features closed on 2026-09-07 are frozen precisely because
    their transcripts are expiring, and re-deriving their money to add an annotation is
    the risk the freeze exists to prevent (`--recapture` is the path that accepts it).

    `cost.shared_sessions[]` needs no separate write here. It is not a `planning.json`
    field: `report.py`'s `compute_shared_sessions` derives it from exactly these entries,
    so refreshing them is what puts the array and its footnote in the next report.

    A refresh, not an append: a claimant that has left the ledger — its feature
    re-captured without the pin — loses its mention, and an entry whose list would be
    empty loses the key entirely, so an unshared feature's record stays identical to one
    written before this path existed."""
    changed = False
    annotated = []
    for entry in record.get("sessions") or []:
        session_id = entry.get("session_id")
        others = (
            other_session_claimants(session_claims, session_id, repo, slug)
            if session_id else []
        )
        if others:
            annotated.append(session_id)
            if entry.get("also_claimed_by") != others:
                entry["also_claimed_by"] = others
                changed = True
        elif "also_claimed_by" in entry:
            del entry["also_claimed_by"]
            changed = True
    if changed:
        with open(output_path, "w") as f:
            json.dump(record, f, indent=2)
    return annotated, changed


def register_frozen_claims(slugs, features_dir, skip_in_flight):
    """Phase one of the annotate-only path: every frozen record this run will annotate
    registers its own session claims in the ledger BEFORE any of them is annotated.

    The two phases are the whole of the convergence rule, and the reason this is not
    folded into `capture_feature`. The ledger is the only seam between features and
    `capture_feature` annotates one at a time, so registering and annotating in the same
    step would leave the first of N frozen features sharing one coordinator naming none
    of the others and the last naming all of them — an artefact of the sweep's ordering
    rather than a fact about the corpus. Registering all N first makes a single `--all`
    converge, which is what item 3's motivating case needs: seven features closed on the
    same day, each frozen before any of the others had claimed the session.

    Convergence ACROSS repos still takes two sweeps and cannot take fewer: each repo
    sweeps its own corpus and writes the one shared ledger, so a record can only name
    the claimants whose repos have already registered. Sweep every repo once and the
    ledger is complete; the second sweep is the one whose annotations are final. This is
    stated in `analysis/README.md` where the cadence is.

    Reads `planning.json`, and the manifest only for the in-flight test `--all` applies
    below — never a transcript. `skip_in_flight` mirrors that loop exactly: a feature
    whose window is still open is not annotated there, so its claims are not registered
    here either, and a premature record does not put a premature claim in the ledger."""
    repo = corpus_identity(features_dir)
    repo_name = repo_display_name(repo)
    ledger = load_ledger()
    session_claims = ledger[LEDGER_SESSIONS_KEY]
    added = False
    for slug in slugs:
        record = load_frozen_record(Path(features_dir, slug, "planning.json"))
        if record is None:
            continue
        if skip_in_flight:
            try:
                if window_is_open(features_dir, slug):
                    continue
            except (ValueError, OSError, json.JSONDecodeError):
                # An unreadable manifest is counted and reported by the capture loop;
                # here it only means this record is not registered, and one bad manifest
                # must not end a corpus-wide run before it starts.
                continue
        try:
            window = normalize_window(parse_manifest(Path(features_dir, slug, "README.md")))
        except (ValueError, OSError, json.JSONDecodeError):
            # Same reasoning as the skip_in_flight guard above: this path has no
            # transcript scan to fall back on, so an unreadable manifest here just
            # means this record is not registered this sweep.
            continue
        costs, selected_by = frozen_session_costs(record)
        added |= add_session_claims(
            session_claims, costs, selected_by, repo, repo_name, slug, window
        )
    if added:
        save_ledger(ledger[LEDGER_SUBAGENTS_KEY], session_claims)


def manifest_pinned_subagents(features_dirs, slug, preferred_dir=None):
    """The agent ids `<slug>`'s own manifest already pins. A delegate a feature pins is
    claimed by that feature — the pin is what claims it — so `--unclaimed --for` must not
    list it as unclaimed and tell the human to write the pin that is already there. The
    ledger cannot answer this on its own: it is written by the capture, and the close
    that asks the question runs BEFORE the capture, which is exactly when every one of
    2026-09-07's seven closes printed the advice.

    Looked up by slug rather than by the `<repo>/<slug>` pair. Not for want of an
    identity to compare against — `corpus_identity` now declares the self corpus's, so a
    `--self` feature's `repo` is `agentTooling` on both sides of the comparison wherever
    this runs. It is the OTHER half that cannot be trusted: `only_feature` is the pair a
    human typed after `--for`, matched against the one a coordinator wrote into a brief's
    `feature:` line, and both are free text. A brief that names the slug and gets the repo
    half wrong — a consuming repo's name in front of a `--self` slug, the shape every
    vendored coordinator wrote before the identity was declared — would drop the pin in
    precisely the case that matters, and the pin is the claim. The pair is never compared
    here, and this does not change that.

    What it does do is try the corpus the query is FOR first. `preferred_dir` is
    `self/features` under `--self` and `plans/features` otherwise; when that tree holds a
    manifest for the slug it is the only one read. Two features may share a slug across
    the two corpora, and reading both would let the OTHER corpus's pin suppress a
    genuinely unpinned delegate from `--unclaimed --for` — which silences
    `feature-close.sh`'s stop-on-unpinned guard, whose entire job is to stop on exactly
    that delegate, and loses its cost with nothing said. Low likelihood, and the failure
    is silent.

    When the preferred corpus holds no manifest for the slug the lookup falls back to
    the slug alone across both corpora, which is the vendored-subtree case above and the
    reason the fallback exists rather than a refusal. A slug that names no manifest in
    either corpus yields no pins, which is the pre-existing behaviour."""
    if preferred_dir is not None and Path(preferred_dir, slug, "README.md").is_file():
        features_dirs = [preferred_dir]
    pinned = set()
    for features_dir in features_dirs:
        readme_path = Path(features_dir) / slug / "README.md"
        if not readme_path.is_file():
            continue
        try:
            manifest = parse_manifest(readme_path)
        except (OSError, ValueError):
            continue
        pinned.update(manifest.get("subagents") or [])
    return pinned


def unclaimed_under(transcript_dirs, claims):
    """Agent ids of every subagent transcript under `transcript_dirs` with no ledger
    entry — delegates whose cost no feature has claimed."""
    unclaimed = []
    for transcript_dir in transcript_dirs:
        for session_dir in sorted(p for p in transcript_dir.iterdir() if p.is_dir()):
            for agent_path in subagent_transcript_paths(transcript_dir, session_dir.name):
                agent_id = agent_path.name[len("agent-"):-len(".jsonl")]
                if agent_id not in claims:
                    unclaimed.append(agent_id)
    return unclaimed


def first_user_text(lines, limit=80):
    """The opening prompt of a transcript, truncated — what `--list-subagents` shows so
    a human can tell a plan author from a reviewer from a reconnaissance one-shot.
    `limit=None` returns it whole."""
    for line in lines:
        if line.get("type") != "user":
            continue
        content = (line.get("message") or {}).get("content")
        if isinstance(content, list):
            content = " ".join(
                block.get("text", "") for block in content if isinstance(block, dict)
            )
        if isinstance(content, str) and content.strip():
            if limit is None:
                return content
            return " ".join(content.split())[:limit]
    return ""


def check_unmatched_subagents(pinned, reachable_agent_ids):
    """Warn for each pinned subagent id no reachable transcript carries. Same shape as
    `check_unmatched_branches`, same two indistinguishable causes: a mistyped id, or a
    transcript that has aged out — and the same consequence, a feature quietly short by
    exactly the cost it meant to claim."""
    warnings = []
    for agent_id in sorted(pinned):
        if agent_id not in reachable_agent_ids:
            warnings.append(
                f"pinned subagent {agent_id!r} matches no transcript under any project "
                "directory — a mistyped id, or its parent session has aged out (run "
                "--list-subagents --everywhere to see what is still on disk)"
            )
    return warnings


def check_subagent_overlap(features_dirs, slug, manifest):
    """Warn when another manifest in either corpus pins one of this feature's subagent
    ids. A pin bypasses the window filter, so nothing else keeps two features from
    both claiming the same architect — this is the whole overlap check for pins."""
    pinned = set(manifest.get("subagents", []) or [])
    if not pinned:
        return []
    warnings = []
    readmes = sorted(
        path for features_dir in features_dirs for path in features_dir.glob("*/README.md")
    )
    for readme in readmes:
        other_slug = readme.parent.name
        if other_slug == slug:
            continue
        try:
            other = parse_manifest(readme)
        except ValueError:
            continue
        shared = pinned & set(other.get("subagents", []) or [])
        for agent_id in sorted(shared):
            warnings.append(
                f"subagent {agent_id!r} is also pinned by feature {other_slug!r} — "
                "its cost is being counted twice"
            )
    return warnings


def claimed_session_ids(features_dirs):
    """Every top-level session some feature in either corpus already accounts for: the
    ones a planning.json lists as selected or excluded, the ones a manifest pins, and
    the runner sessions a usage.json holds. What `--list-sessions --unclaimed` subtracts."""
    claimed = collect_excluded_session_ids(features_dirs, {})
    for features_dir in features_dirs:
        for planning_path in features_dir.glob("*/planning.json"):
            try:
                data = json.loads(planning_path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            claimed.update(s.get("session_id") for s in data.get("sessions", []) if s.get("session_id"))
            claimed.update(data.get("excluded_session_ids", []) or [])
        for readme_path in features_dir.glob("*/README.md"):
            try:
                manifest = parse_manifest(readme_path)
            except (ValueError, OSError, json.JSONDecodeError):
                continue
            claimed.update(manifest.get("sessions", []) or [])
    return claimed


def list_sessions(sessions_dir, since, unclaimed, features_dirs):
    """Print every top-level session launched in this repo's primary checkout — which
    holds every feature worktree, under `<primary>/.worktrees/` — or in a legacy sibling
    worktree (`<primary>-*`): date, id, branch, cwd, model, cost, minutes and opening
    prompt. Every feature's, not one feature's: this is discovery, so no fence applies. The twin of `--list-subagents`, and the close step's question:
    `unclaimed` keeps only the sessions no planning.json lists, no manifest pins and no
    usage.json holds — cost that belongs to somebody and is counted by nobody."""
    session_dir_str = str(sessions_dir)
    claimed = claimed_session_ids(features_dirs) if unclaimed else set()
    rows = []
    seen = set()
    for transcript_dir in find_transcript_dirs(sessions_dir):
        for jsonl_path in sorted(transcript_dir.glob("*.jsonl")):
            lines = load_transcript_lines(jsonl_path)
            if not lines:
                continue
            session_id = next((line.get("sessionId") for line in lines if line.get("sessionId")), None)
            if session_id is None or session_id in seen or session_id in claimed:
                continue
            cwd = next((line.get("cwd") for line in lines if isinstance(line.get("cwd"), str)), "")
            if not (
                cwd == session_dir_str
                or cwd.startswith(session_dir_str + "/")
                or cwd.startswith(session_dir_str + "-")
            ):
                continue
            timestamps = [
                moment for moment in (to_utc(line.get("timestamp")) for line in lines)
                if moment is not None
            ]
            if not timestamps:
                continue
            start = min(timestamps).date().isoformat()
            if since and start < since:
                continue
            seen.add(session_id)
            minutes = (max(timestamps) - min(timestamps)).total_seconds() / 60
            branch = next((line.get("gitBranch") for line in lines if line.get("gitBranch")), "")
            totals = {}
            for model, usage, _ in iter_billable_messages(lines):
                add_usage(totals, model, usage)
            cost = 0.0
            models = []
            for model in sorted(totals):
                priced, _ = compute_cost(model, totals[model], as_of=start)
                cost += priced or 0.0
                models.append(model)
            rows.append((start, session_id, branch, cwd, "/".join(models), cost, minutes, first_user_text(lines)))
    rows.sort()
    if not rows:
        print("no unclaimed sessions" if unclaimed else "no sessions found under this repo's project directories")
        return
    print(
        "date        session-id                            branch            "
        "launched in                  model             cost   mins  opening prompt"
    )
    for start, session_id, branch, cwd, model, cost, minutes, prompt in rows:
        print(
            f"{start}  {session_id:<36}  {branch[:16]:<16}  {cwd[-27:]:<27}  "
            f"{model[:16]:<16} ${cost:8.2f} {minutes:5.0f}  {prompt}"
        )
    if unclaimed:
        print(
            f"{len(rows)} unclaimed session(s), ${sum(r[5] for r in rows):.2f} no feature counts. "
            "Pin one with \"sessions\": [\"<session-id>\"] in the manifest it belongs to."
        )
    else:
        print(f"{len(rows)} session(s).")


def list_subagents(
    sessions_dir, since, everywhere=False, unclaimed=False, only_feature=None,
    features_dirs=(), preferred_features_dir=None,
):
    """Print every subagent transcript reachable from this repo's project directories:
    start date, agent id, parent session, the parent's branch, the model, its priced
    cost and its opening prompt. `since` (a UTC date string) drops older ones. This is
    the discovery step for a manifest's `subagents` pin — the ids are not written
    anywhere a human would otherwise read. `everywhere` widens the scan to every
    project directory and adds the parent's cwd, for the delegate a coordinator in
    another repo spawned to work on this one. `unclaimed` (implies `everywhere`)
    keeps only the ones no feature has claimed in the ledger, and shows the feature
    each one's brief names — the pin to write.

    `only_feature`, a `(repo, slug)` pair (`--for`, which the caller pairs with
    `unclaimed`), keeps only the rows whose brief names exactly that feature, compared
    as the pair `brief_feature_of` returns. It exists because `feature-close.sh`'s
    stray-delegate guard reads this list: matching text in the printed table instead
    both over-fired on `<slug>-two` and under-fired on a `<repo>/<slug>` too long for
    the pin column. For the same caller, the agent-id column is never truncated. A
    delegate that feature's own manifest already pins is not unclaimed and is dropped
    from the list (`manifest_pinned_subagents`, read from `features_dirs`, preferring
    `preferred_features_dir` — the corpus this run is for — when a same-slug feature
    exists in both), so the advice line below — and `feature-close.sh`'s stray guard,
    which reads these rows — speak only about pins still to write."""
    everywhere = everywhere or unclaimed
    claims = load_claims() if unclaimed else {}
    pinned_already = (
        manifest_pinned_subagents(features_dirs, only_feature[1], preferred_features_dir)
        if only_feature else set()
    )
    session_dir_str = str(sessions_dir)
    projects_root = Path.home() / ".claude" / "projects"
    transcript_dirs = (
        sorted(d for d in projects_root.iterdir() if d.is_dir())
        if everywhere and projects_root.exists()
        else find_transcript_dirs(sessions_dir)
    )
    rows = []
    listed = set()
    for transcript_dir in transcript_dirs:
        for session_dir in sorted(p for p in transcript_dir.iterdir() if p.is_dir()):
            for agent_path in subagent_transcript_paths(transcript_dir, session_dir.name):
                lines = load_transcript_lines(agent_path)
                if not lines:
                    continue
                agent_id = agent_id_of(agent_path, lines)
                if (
                    agent_id in listed
                    or (unclaimed and agent_id in claims)
                    or agent_id in pinned_already
                ):
                    continue
                listed.add(agent_id)
                if not everywhere and not any(
                    line.get("cwd") == session_dir_str
                    or (
                        isinstance(line.get("cwd"), str)
                        and line["cwd"].startswith(session_dir_str + "/")
                    )
                    for line in lines
                ):
                    continue
                timestamps = [
                    moment
                    for moment in (to_utc(line.get("timestamp")) for line in lines)
                    if moment is not None
                ]
                if not timestamps:
                    continue
                start = min(timestamps).date().isoformat()
                if since and start < since:
                    continue
                minutes = (max(timestamps) - min(timestamps)).total_seconds() / 60
                branch = next(
                    (line.get("gitBranch") for line in lines if line.get("gitBranch")), ""
                )
                totals = {}
                for model, usage, _ in iter_billable_messages(lines):
                    add_usage(totals, model, usage)
                cost = 0.0
                models = []
                for model in sorted(totals):
                    priced, _ = compute_cost(model, totals[model], as_of=start)
                    cost += priced or 0.0
                    models.append(model)
                cwd = next((line.get("cwd") for line in lines if line.get("cwd")), "")
                named = brief_feature_of(lines)
                if only_feature is not None and named != only_feature:
                    continue
                rows.append(
                    (
                        start,
                        agent_id_of(agent_path, lines),
                        session_dir.name,
                        branch,
                        "/".join(models),
                        cost,
                        minutes,
                        Path(cwd).name if cwd else "",
                        f"{named[0]}/{named[1]}" if named else "-",
                        first_user_text(lines),
                    )
                )
    rows.sort()
    feature_ref = f"{only_feature[0]}/{only_feature[1]}" if only_feature else ""
    if not rows:
        # An empty scan has two very different causes and the message must not read like
        # the first: there really are no subagents, or this was run from a directory the
        # repo's project directories are not under (session_root is the nearest ancestor
        # holding .git, so from above the repo it resolves somewhere else entirely) and
        # the narrow scan reached nothing. `unclaimed` implies `everywhere`, so only the
        # narrow scan can be wrong about it.
        if only_feature:
            print(f"no unclaimed subagent transcripts briefed for {feature_ref}")
        elif unclaimed:
            print("no unclaimed subagent transcripts")
        elif everywhere:
            print("no subagent transcripts found")
        else:
            print(
                "no subagent transcripts found; scanned "
                f"{sessions_dir} only; run from the repo, or pass --everywhere"
            )
        return
    cwd_header = "parent cwd        " if everywhere else ""
    pin_header = "brief names (pin here)      " if unclaimed else ""
    print(
        "date        agent-id           parent    branch            model             "
        f"cost   mins  {cwd_header}{pin_header}opening prompt"
    )
    for start, agent_id, parent, branch, model, cost, minutes, cwd, named, prompt in rows:
        cwd_col = f"{cwd[:16]:<16}  " if everywhere else ""
        pin_col = f"{named[:26]:<26}  " if unclaimed else ""
        print(
            f"{start}  {agent_id:<18} {parent[:8]}  {branch[:16]:<16}  "
            f"{model[:16]:<16} ${cost:8.2f} {minutes:5.0f}  {cwd_col}{pin_col}{prompt}"
        )
    if only_feature:
        print(
            f"{len(rows)} unclaimed subagent(s) briefed for {feature_ref}, "
            f"${sum(r[5] for r in rows):.2f} no feature counts. Pin each in "
            f"{feature_ref}'s manifest as \"subagents\": [\"<agent-id>\"]."
        )
        return
    if unclaimed:
        print(
            f"{len(rows)} unclaimed subagent(s), ${sum(r[5] for r in rows):.2f} no feature "
            "counts. Pin each in the manifest its brief names; a '-' brief predates the "
            "`feature:` header — read the prompt."
        )
        return
    print(
        f"{len(rows)} subagent(s). Pin one to a feature with \"subagents\": [\"<agent-id>\"] "
        "in its manifest; it is then priced regardless of its parent's branch or the "
        "session_window."
    )


def windows_overlap(a, b):
    """Whether two normalized session_windows can both claim the same session.

    A session is matched atomically on its *start* (`min(timestamps)`, see main()),
    so two features double-count a session exactly when that one instant falls in
    both windows — i.e. when the two intervals intersect. `None` is unbounded on
    that side. ISO 8601 sorts lexicographically, so the comparisons need no parsing,
    the same reason `in_window` compares strings.

    Half-open to match `in_window` exactly, which is what makes a chained handoff
    (`{"to": T}` then `{"from": T}`) report no overlap: no session can be in both,
    so there is nothing to warn about. The two must agree — a guard that is stricter
    than the matcher warns about safe manifests, and one that is looser stays silent
    through a real double-count.

    Two absent windows normalize to unbounded-on-both-sides and so overlap, which is
    why this subsumes the "neither declares a window" case it replaced rather than
    sitting beside it.

    Operates on the aware UTC datetimes `normalize_window` produces, for the reason
    `in_window` does: the two must agree exactly, and a string comparison disagrees
    with an instant comparison as soon as one manifest writes a bound with an offset
    and its neighbour writes the same instant with a `Z`. That pair chains perfectly
    and would have been reported as overlapping.
    """
    a_from, a_to = a.get("from"), a.get("to")
    b_from, b_to = b.get("from"), b.get("to")
    if a_to is not None and b_from is not None and b_from >= a_to:
        return False
    if b_to is not None and a_from is not None and a_from >= b_to:
        return False
    return True


def describe_window(window):
    """A window rendered for a warning message: "open-ended" when both bounds are
    absent, otherwise `from..to` with `*` for an absent bound.

    Renders the normalized UTC instants, not the manifest's raw strings, so two
    manifests written in different zones are legible against each other in the one
    warning that compares them."""
    frm, to = window.get("from"), window.get("to")
    if frm is None and to is None:
        return "open-ended"
    render = lambda bound: bound.isoformat() if bound is not None else "*"  # noqa: E731
    return f"{render(frm)}..{render(to)}"


def check_branch_overlap(features_dirs, slug, manifest):
    """Warn when this feature's branches overlap another manifest's *and* the two
    session_windows also overlap — that is the shape of the double-counting bug this
    whole module exists to avoid, and it is cheap to detect by reading every
    other feature README's manifest fence.

    The test is on whether the windows *intersect*, not on whether they *exist*. An
    earlier version warned only when neither manifest declared a window, which meant
    declaring one on both silenced the only check there was — and two open-ended
    windows (`{"from": ..., "to": null}`) on a shared branch, the natural thing to
    write while a feature is still in progress, double-counted every shared session
    in silence. That is not hypothetical: it is how the first two features on
    `discogs-provenance-and-packaging` came to claim the same five sessions and the
    same $37.14 apiece.

    Overlapping windows are a *possible* double-count, not a proven one — the
    sessions themselves may fall outside one of them. This is deliberately the
    over-approximation: it is computed from two manifests without walking any
    transcript, and a false warning costs a `to` boundary while a missed one costs a
    silently wrong number.

    Scans both corpora for the same reason collect_excluded_session_ids does: the
    overlapping feature is at least as likely to be in the other tree as in this one.
    """
    warnings = []
    own_branches = set(manifest.get("branches", []))
    own_window = normalize_window(manifest)

    readme_paths = sorted(
        path for features_dir in features_dirs for path in features_dir.glob("*/README.md")
    )
    for readme_path in readme_paths:
        other_slug = readme_path.parent.name
        if other_slug == slug:
            continue
        try:
            other_manifest = parse_manifest(readme_path)
        except (ValueError, OSError, json.JSONDecodeError):
            continue

        other_branches = set(other_manifest.get("branches", []))
        shared = own_branches & other_branches
        if not shared:
            continue

        other_window = normalize_window(other_manifest)
        if windows_overlap(own_window, other_window):
            warnings.append(
                f"branches {sorted(shared)} overlap with feature {other_slug!r} and "
                f"the session_windows overlap too "
                f"(this {describe_window(own_window)}, {other_slug} "
                f"{describe_window(other_window)}); any session in both is priced "
                "as planning cost twice — give the finished feature a 'to' bound"
            )

    return warnings


def check_unmatched_branches(branches, branches_seen, feature_worktree=""):
    """Warn for each declared branch that no transcript in this repo carries.

    A branch name in `branches` that matches nothing is indistinguishable, in the
    output, from a feature that simply had no planning sessions: both report $0.00.
    So a typo, or a name written with a prefix the branch never actually had
    (`ssdesai/foo` for a branch named `foo`), silently drops every session on it and
    reads as "planning was free".

    `branches_seen` is every `gitBranch` value observed while walking this repo's
    transcript directories, regardless of window, exclusion or repo_match — the question
    here is only whether the *name* exists, so the widest evidence is the right evidence.

    Two causes produce this, and the message names both because they cannot be told
    apart from here: a wrong name, or transcripts that have aged out. On a mature corpus
    the second is common and the warning is then just true rather than actionable — it
    is worded so a reader is not sent to check a name that was always correct.
    """
    unmatched = sorted(set(branches) - branches_seen)
    where = f" ({feature_worktree})" if feature_worktree else ""
    return [
        f"branch {name!r} matched no session in any transcript for this repo, so any "
        "planning on it is uncounted. One of three things is true: the name is wrong — "
        "check it against `git branch --list` and record it exactly as git shows it, with "
        "no added prefix; or its sessions were launched somewhere other than the primary "
        "checkout (other features' worktrees under it excluded) and this feature's "
        f"worktree{where} — launch the coordinator inside the "
        "worktree, or pin each session id in `sessions`; or the transcripts have aged out "
        "of ~/.claude/projects/, in which case the name is fine and the cost is unrecoverable"
        for name in unmatched
    ]


def check_frozen_cost(output_path, reachable_session_ids, excluded_ids, reachable_agent_ids=()):
    """Sessions the prior capture priced that this run would silently drop forever.

    `planning.json` is a frozen record, and the transcripts it was derived from are on
    a retention clock. Once they age out, the file is the *only* surviving account of a
    feature's planning cost — so a re-run that finds nothing does not merely fail to
    improve the number, it destroys it. That is not hypothetical: one documented cadence
    run over humanNetworkMap zeroed 11 features at once, $151.58 -> $0.00 on
    add-component-tests among them, because the cadence in analysis/README.md says to
    run this per feature and nothing distinguished "no planning happened" from "the
    evidence expired".

    A prior session is treated as lost when both hold:

      - it is not in `excluded_ids` — a session now claimed by some usage.json is
        reclassified as runner cost, not lost, and its dollars still exist there; and
      - it is not in `reachable_session_ids`, the sessions THIS scan could see.

    Reachability, not file existence. The first version of this guard asked whether a
    file named `<session_id>.jsonl` existed anywhere under `~/.claude/projects/`, which
    is a strictly wider question than the one that matters and let the exact bug through
    that it was written to stop: planning that ran from a git worktree (`…/musicMap-levels`)
    leaves its transcripts in that worktree's own project directory. The scan walks that
    directory — its name contains the repo's fragment — but every line's `cwd` is the
    worktree, so `repo_match` fails and the session can never be selected from this
    checkout again. The glob found the file and vouched for it, and two features were
    re-zeroed with exit 0 and no `--force`.

    `reachable_session_ids` is collected at the point the scan proves it can use a
    transcript at all, so "recoverable" is by construction "this scan can reach it"
    rather than a second, looser guess at the same thing. A session deselected by a
    manifest edit — narrowing a `session_window`, correcting `branches` — stays
    reachable and the guard stays quiet, which is the case that must not become noisy.

    Subagents are guarded the same way: a prior `subagents[]` entry whose transcript this
    scan could not reach (`reachable_agent_ids`, collected at the same point of proof as
    the session set) is lost, and is reported as `agent-<id>` so the two kinds read apart.

    Returns (lost_ids, prior_total). An empty list means the write is safe.
    """
    if not output_path.exists():
        return [], 0.0
    try:
        prior = json.loads(output_path.read_text())
    except (OSError, json.JSONDecodeError):
        # An unreadable prior capture holds nothing recoverable, so there is nothing
        # to protect and no reason to block the write that would replace it.
        return [], 0.0

    prior_total = (prior.get("cost_usd") or {}).get("total") or 0.0
    if prior_total <= 0:
        return [], prior_total

    lost = sorted(
        entry["session_id"]
        for entry in prior.get("sessions") or []
        if entry.get("session_id")
        and entry["session_id"] not in reachable_session_ids
        and entry["session_id"] not in excluded_ids
    )
    lost += sorted(
        f"agent-{entry['agent_id']}"
        for entry in prior.get("subagents") or []
        if entry.get("agent_id") and entry["agent_id"] not in reachable_agent_ids
    )
    return lost, prior_total


def carry_lost_entries(output_path, lost):
    """The prior capture's rows for the ids `check_frozen_cost` reports lost, each
    marked `carried_from` with that capture's timestamp — so a re-capture can add what
    it reaches now (a pin on a feature whose own sessions have expired) without
    destroying the only surviving account of what it cannot. Returns
    (captured_at, sessions, subagents, priced)."""
    prior = json.loads(output_path.read_text())
    stamp = prior.get("captured_at")
    lost_sessions = {i for i in lost if not i.startswith("agent-")}
    lost_agents = {i[len("agent-"):] for i in lost if i.startswith("agent-")}

    def mark(entry):
        entry = dict(entry)
        # Rows written before subagent capture existed carry no agent_id at all.
        entry.setdefault("agent_id", None)
        entry["carried_from"] = stamp
        return entry

    sessions = [mark(e) for e in prior.get("sessions") or [] if e.get("session_id") in lost_sessions]
    subagents = [mark(e) for e in prior.get("subagents") or [] if e.get("agent_id") in lost_agents]
    priced = [
        mark(e) for e in prior.get("priced") or []
        if (e.get("agent_id") in lost_agents)
        or (not e.get("agent_id") and e.get("session_id") in lost_sessions)
    ]
    return stamp, sessions, subagents, priced


def prior_cross_repo_ids(output_path):
    """Agent ids the last capture priced from another repo's project directory."""
    if not output_path.exists():
        return set()
    try:
        prior = json.loads(output_path.read_text())
    except (json.JSONDecodeError, OSError):
        return set()
    return {
        entry["agent_id"]
        for entry in prior.get("subagents", []) or []
        if entry.get("cross_repo") and entry.get("agent_id")
    }


def prior_capture(output_path):
    """`(captured_at, total)` of an existing planning.json, or `(None, 0.0)` if there is
    no usable prior capture — no file, unreadable, or no timestamp in it.

    `captured_at` is what "already populated" means, and it is deliberately the file's own
    self-reported capture time rather than a mtime: `planning.json` is committed, so a
    fresh checkout gives every file the same mtime and a rebase gives them all a new one,
    while `captured_at` travels with the record it describes.

    None for an unreadable file, for the same reason `check_frozen_cost` returns "nothing
    to protect" there: a capture that cannot be read holds nothing worth keeping, and
    refusing to replace it would leave a corpus permanently stuck on a corrupt file.

    The total comes back with it so the skip line can state what is already recorded. A
    frozen $0.00 is the one case worth acting on — it means the last capture found
    nothing, which a corrected `branches` entry or a run from the right checkout might
    now find — and after a skip nothing else says so: `check_unmatched_branches`, the
    warning that usually explains a zero, needs the scan that the skip is avoiding.
    """
    if not output_path.exists():
        return None, 0.0
    try:
        prior = json.loads(output_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None, 0.0
    captured_at = prior.get("captured_at")
    if not isinstance(captured_at, str) or not captured_at.strip():
        return None, 0.0
    return captured_at, (prior.get("cost_usd") or {}).get("total") or 0.0


def window_is_open(features_dir, slug):
    """True when the manifest's `session_window` exists and its `to` is null — the shape
    `feature-start.sh` writes and `feature-close.sh` stamps shut, so the feature is still
    in flight. A manifest with no `session_window` at all is a legacy one, not in flight."""
    manifest = parse_manifest(Path(features_dir, slug, "README.md"))
    window = manifest.get("session_window")
    return isinstance(window, dict) and "to" in window and window["to"] is None


def feature_slugs(features_dir):
    """Every feature in a corpus, in name order: a directory holding the README.md whose
    last ```json fence is its manifest.

    The same shape `check_branch_overlap` scans for, so `--all` walks exactly the set
    that participates in overlap detection — a directory that is not a feature by one
    test is not a feature by the other either.
    """
    return sorted(path.parent.name for path in features_dir.glob("*/README.md"))


def build_claimant_index(features_dirs):
    """Every manifest under `features_dirs` — both corpora, in practice — reduced to the
    facts a claim decision needs: `{features_dir, repo, repo_name, slug, window, pins,
    branches, excluded}`, in the order `sorted(glob("*/README.md"))` yields them per
    directory.

    Built ONCE per capture, where `share_ctx` is (`capture_feature`), because
    `session_claim_intervals` is called once per selected session and used to re-glob and
    re-parse every README under both features roots on each of those calls — and to run
    `corpus_identity`, which for a consuming repo's corpus is a `git remote get-url`
    subprocess, twice per call. On a 40-feature corpus with 30 selected sessions that is
    roughly 1200 manifest parses and 60 subprocesses for one capture, all of them
    answering the same question. `corpus_identity` is computed once per features dir here
    for the same reason — and under `--self` it answers from the declared constant and
    runs no subprocess at all.

    A README whose fence will not parse is skipped rather than raising: a broken manifest
    somewhere else in either corpus must not end this capture. That is the same tolerance
    the per-call scan had, moved.

    Read-only, and derived from the manifests alone — no transcript, no ledger. The
    session-specific tests (`pins`, `branches`, `excluded`, `window`) are applied by
    `session_claim_intervals` in memory.
    """
    index = []
    for features_dir in features_dirs:
        repo = corpus_identity(features_dir)
        repo_name = repo_display_name(repo)
        for readme_path in sorted(features_dir.glob("*/README.md")):
            try:
                manifest = parse_manifest(readme_path)
            except (ValueError, OSError, json.JSONDecodeError):
                continue
            index.append({
                "features_dir": features_dir,
                "repo": repo,
                "repo_name": repo_name,
                "slug": readme_path.parent.name,
                "window": normalize_window(manifest),
                "pins": set(manifest.get("sessions") or []),
                "branches": set(manifest.get("branches") or []),
                "excluded": set(manifest.get("exclude_sessions") or []),
            })
    return index


# `session_window.to` is EXCLUSIVE (`in_window`) and the share split is half-open on it
# too, so a bound taken at the last instant itself would drop the very response it was
# derived from — a single-line session would capture as nothing at all. One second past
# it is the smallest bound that keeps it, and it is what makes consecutive features chain
# rather than nest.
EVIDENCE_OFFSET_SECONDS = 1


def last_branch_instant(slug, features_dir, sessions_dir):
    """The bound `feature-close.sh` stamps as `session_window.to`: one second past the
    last instant of every session this feature's `branches` + `session_window` select and
    of those sessions' own subagents. None when the feature has no branch-selected
    session, which is the caller's cue to fall back to its own clock and say so.

    **Selection is the capture's, by the branch route.** Every term is the shared one —
    `normalize_window`, `in_window`, `cwd_under_any`, `find_transcript_dirs`,
    `subagent_transcript_paths` — so the evidence cannot drift from what
    `capture_feature` will count a moment later. What is deliberately NOT consulted is the
    pin route: a manifest's `sessions` entry claims a session "regardless of branch,
    window or cwd", and the session `feature-start.sh` pins is the coordinator that
    started N features and outlives every one of them, so its last instant is evidence
    about the coordinator and not about this feature. A pinned session that the branch
    route would select anyway IS evidence — it is on the branch and in the window, and the
    pin is redundant there.

    **One term differs from `capture_feature`'s, on purpose: a runner session counts
    here.** The capture drops every session id a `usage.json` already holds, because its
    dollars are recorded there and pricing it again would double-count it. That is a rule
    about what this record PRICES; this function answers when work on the branch STOPPED,
    and a `claude -p` executor draining a plan in the feature's own worktree is the
    plainest evidence there is. Excluding it measures nothing in practice: over
    agentTooling's own 16 features, the branch route without runner sessions finds
    evidence for one, and with them for nine — each bound one to eleven hours tighter than
    the `to` the close had stamped, which is the whole of what this feature is for. The
    manifest's own `exclude_sessions` IS honoured: a session the author disowned is not
    this feature's work by the author's own word.

    Truncated to whole seconds before the offset is added, so the bound is written at the
    resolution every other bound in both corpora has and is still strictly after the
    instant it came from (a last instant of `…:56.700` yields `…:57`, not `…:57.700`).

    Reads timestamps only: no ledger is opened, nothing is written, and no git command is
    run — `--recapture` may be the caller, and by then the branch is usually deleted.
    """
    manifest = parse_manifest(Path(features_dir, slug, "README.md"))
    branches = set(manifest.get("branches") or [])
    window = normalize_window(manifest)
    excluded_ids = set(manifest.get("exclude_sessions") or [])
    excluded_agent_ids = set(manifest.get("exclude_subagents") or [])

    # The same claimable directories the capture uses (`claim_roots`), so a session in
    # another feature's worktree can no more bound this window than be priced in it.
    claimable_roots, claim_fences = claim_roots(str(sessions_dir), slug)

    latest = None
    for transcript_dir in find_transcript_dirs(sessions_dir):
        for jsonl_path in sorted(transcript_dir.glob("*.jsonl")):
            lines = load_transcript_lines(jsonl_path)
            if not lines:
                continue
            session_id = next(
                (line.get("sessionId") for line in lines if line.get("sessionId")), None
            )
            if session_id is None or session_id in excluded_ids:
                continue
            branches_seen = {line.get("gitBranch") for line in lines if line.get("gitBranch")}
            if not (branches_seen & branches):
                continue
            if not cwd_under_any(lines, claimable_roots, claim_fences):
                continue
            timestamps = [
                moment
                for moment in (to_utc(line.get("timestamp")) for line in lines)
                if moment is not None
            ]
            if not timestamps or not in_window(min(timestamps), window):
                continue
            end_ts = max(timestamps)
            latest = end_ts if latest is None else max(latest, end_ts)
            # A delegate's transcript is part of the work: an implementer that ran for
            # four hours under a coordinator whose own last line came first would
            # otherwise bound the feature at the coordinator's instant.
            for agent_path in subagent_transcript_paths(transcript_dir, session_id):
                agent_lines = load_transcript_lines(agent_path)
                if not agent_lines:
                    continue
                if agent_id_of(agent_path, agent_lines) in excluded_agent_ids:
                    continue
                agent_start_ts = agent_start_of(agent_lines)
                agent_end_ts = agent_end_of(agent_lines)
                if agent_start_ts is None or not in_window(agent_start_ts, window):
                    continue
                if agent_end_ts is not None:
                    latest = agent_end_ts if latest is None else max(latest, agent_end_ts)

    if latest is None:
        return None
    return latest.replace(microsecond=0) + timedelta(seconds=EVIDENCE_OFFSET_SECONDS)


def session_claim_intervals(session_id, session_start, session_branches, share_ctx, warnings):
    """The claims on one session: `{"feature": "<repo>/<slug>", "from": dt|None,
    "to": dt|None, "source": "self"|"manifest"|"ledger"}` for each, shaped to be passed
    straight to `in_window`. This capturing feature's own claim is always first (built
    from `share_ctx["window"]`, its own normalized `session_window`); the rest are sorted
    by `(from or datetime.min, feature)`.

    Three sources, in precedence order, de-duplicated by `(repo, slug)`:
      - **self** — always present.
      - **manifest** — every entry in `share_ctx["claimants"]` (the index
        `build_claimant_index` built once for this capture, over every feature README
        under any directory in `share_ctx["features_dirs"]`), other than this capture's
        own `(features_dir, slug)`, which either pins `session_id`, or shares a branch
        with `session_branches` and whose normalized window contains `session_start`;
        and which does not list `session_id` in `exclude_sessions`.
      - **ledger** — every entry in `share_ctx["session_claims"].get(session_id)` whose
        `(repo, slug)` is not already contributed above, read from its `window` key.
        This is the only route that reaches a repo neither corpus holds a manifest for.
        A claim with no `window` at all predates recorded windows: it is read as
        unbounded (`from`/`to` both None), splitting evenly with the other claimants,
        and warned about by name.

    Nothing here reads the filesystem: the manifests were read once into the index, and
    this is the per-session filter over it.
    """
    repo = share_ctx["repo"]
    repo_name = share_ctx["repo_name"]
    slug = share_ctx["slug"]
    features_dir = share_ctx["features_dir"]
    own_window = share_ctx["window"]

    own_feature = f"{repo_name}/{slug}"
    claims = [
        {"feature": own_feature, "from": own_window["from"], "to": own_window["to"], "source": "self"}
    ]
    seen = {(repo, slug)}

    for other in share_ctx["claimants"]:
        other_slug = other["slug"]
        if other["features_dir"] == features_dir and other_slug == slug:
            continue
        if (other["repo"], other_slug) in seen:
            continue
        if session_id in other["excluded"]:
            continue
        other_window = other["window"]
        pins = session_id in other["pins"]
        shares_branch = bool(other["branches"] & session_branches)
        if not (pins or (shares_branch and in_window(session_start, other_window))):
            continue
        seen.add((other["repo"], other_slug))
        claims.append({
            "feature": f"{other['repo_name']}/{other_slug}",
            "from": other_window["from"], "to": other_window["to"],
            "source": "manifest",
        })

    for claim in share_ctx["session_claims"].get(session_id) or []:
        key = (claim.get("repo"), claim.get("slug"))
        if key in seen:
            continue
        seen.add(key)
        feature = f"{claim.get('repo_name') or claim.get('repo')}/{claim.get('slug')}"
        raw_window = claim.get(LEDGER_CLAIM_WINDOW_KEY)
        if raw_window is None:
            warnings.append(
                f"session claim {feature!r} for session {session_id} carries no recorded "
                "window — it predates recorded windows, so it is read as covering the "
                "whole transcript and split evenly with the other claimants"
            )
            frm, to = None, None
        else:
            frm, to = to_utc(raw_window.get("from")), to_utc(raw_window.get("to"))
        claims.append({"feature": feature, "from": frm, "to": to, "source": "ledger"})

    # Another feature's empty window is not a claim at all, and must not be counted as
    # one. `share_owners` already refuses to pay it, but merely leaving it in the list
    # still changes the answer: `select_parent` branches on `len(intervals) <= 1`, so a
    # single malformed manifest anywhere in either corpus would flip a genuinely
    # single-claimant session onto the share path, and its one real owner would lose
    # everything past its own `to` to the unclaimed remainder. That is the silent
    # under-count the unshared path exists to avoid, arriving through a feature that
    # cannot own a second of the session. This feature's OWN claim is never dropped: it
    # is `intervals[0]` by contract, and `check_empty_window` has already warned about it
    # by the time this runs.
    kept = []
    for claim in claims[1:]:
        if is_empty_window(claim):
            warnings.append(
                f"claim {claim['feature']!r} on session {session_id} has an empty window "
                f"(`from` {_iso_or_none(claim['from'])} is not before `to` "
                f"{_iso_or_none(claim['to'])}) — it can own no part of any session, so it "
                "is not counted as a claimant here; fix that feature's `session_window`"
            )
            continue
        kept.append(claim)

    rest = sorted(
        kept,
        key=lambda c: (c["from"] or datetime.min.replace(tzinfo=timezone.utc), c["feature"]),
    )
    return [claims[0]] + rest


def outside_window_cost(lines, to, as_of):
    """`(dollars, partial)` for the billable responses of one transcript dated at or
    after `to` — the part of a session that falls outside its own window.

    Priced exactly as the unclaimed remainder is: tokens summed per `(model,
    is_sidechain)` over `iter_billable_messages_at`, then `pricing.compute_cost` at the
    session's own `as_of` date. A response is dated by its FIRST line, the same instant
    the share walk owns it by, so the two answers cannot disagree about which side of the
    bound a response written across several lines fell on.

    `partial` is True when some model in that stretch has no rate, in which case the
    dollars exclude it and are a lower bound — the rule `pricing.py` states, reported
    rather than coerced to a silent zero. A response whose line carries no parseable
    timestamp is not counted as outside: an undated response cannot be shown to be past
    the bound.
    """
    tokens = {}
    for model, usage, is_sidechain, moment in iter_billable_messages_at(lines):
        if moment is None or moment < to:
            continue
        add_usage(tokens, (model, is_sidechain), usage)
    cost = 0.0
    partial = False
    for (model, _is_sidechain), bucket in tokens.items():
        priced, _rates = compute_cost(model, bucket, as_of=as_of)
        if priced is None:
            partial = True
            continue
        cost += priced
    return cost, partial


# Below these two together, the stretch past `to` is not a quantity worth printing and the
# warning stays qualitative. The seconds are already truncated to whole ones, so a
# threshold of 1 means "the overrun is under a second"; the dollars are a sum of priced
# responses, so `<= 0` means no billable response is out there at all. Both, not either: an
# unbilled ten-minute tail is a real overrun with no money in it, and an under-a-second one
# that cost money is real money.
NO_OUTSIDE_COST_USD = 0.0
MIN_REPORTED_OUTSIDE_SECONDS = 1


def boundary_warning(session_id, window, lines, start_ts, end_ts, shared):
    """The `may span the window boundary` warning for a SELECTED session whose last
    instant is at or after its window's `to`, saying how much lies outside and whether it
    was counted.

    Size is the half of that disclosure that was missing. `shared-session-share`
    deliberately leaves a session with one claimant priced over its whole transcript,
    however far it outran its `to` — slicing it removes no double-count and turns a
    disclosed over-count into a silent under-count on every consuming repo — so the
    warning is the whole remedy, and "this figure includes work done after the window
    closed" without a number is not a remedy anyone can act on. Both quantities are here:
    the dollars, priced as the unclaimed remainder is, and the seconds from `to` to the
    transcript's last instant.

    Whether they were counted differs by path, so the sentence does too. Unshared, they
    are in this feature's total. Shared, the split has already excluded them from THIS
    feature — `share_owners` cannot return a claim whose window ends before the instant —
    so the same stretch is reported as not counted here. Where it went is a second
    question the warning must not prejudge: the quantity above is measured from this
    feature's own `to`, and a claimant bounded later still owns the part of it its window
    covers. Only the stretch past EVERY claimant's `to` is the unclaimed remainder, and
    chained windows — what stamping `to` from evidence exists to produce — are exactly the
    case where the two are not the same stretch.

    When there is nothing out there to measure, the sentence goes back to the qualitative
    one it replaced. The warning fires on the session's last LINE being past `to`, while
    the quantity counts billable RESPONSES at or after it, and the two are routinely out of
    step: a trailing `user` line or a `<synthetic>` notice is what a real transcript ends
    with far more often than a response, and the seconds are truncated to whole ones. Both
    zero means the session outran its window by nothing anyone is billed for, and
    "$0.0000 and 0s of it fall at or after `to`, counted in full" asserts a measurement
    of nothing where the old sentence said something true. The disclosure is the point;
    a disclosure of zero is noise, so it says only that no billable response is out there.
    """
    to = window["to"]
    cost, partial = outside_window_cost(lines, to, start_ts.date().isoformat())
    seconds = int((end_ts - to).total_seconds())
    prefix = (
        f"session {session_id} may span the window boundary "
        f"(window {describe_window(window)} UTC, session ends {end_ts.isoformat()})"
    )
    if cost <= NO_OUTSIDE_COST_USD and seconds < MIN_REPORTED_OUTSIDE_SECONDS:
        return f"{prefix}; no billable response of it falls at or after `to`"
    at_least = "at least " if partial else ""
    counted = (
        "not counted here (the split gives each response to the claimants whose window "
        "still covers it, and only what is past every claimant's `to` to nobody, as the "
        "unclaimed remainder)"
        if shared else
        "counted in full (this feature is its only claimant, so the session is priced "
        "over its whole transcript)"
    )
    return f"{prefix}; {at_least}${cost:.4f} and {seconds}s of it fall at or after `to`, {counted}"


def earliest_dated_claim(intervals):
    """The claim the opening-stretch fallback pays, or `None` when no claim is dated.

    The ranking pool is every claim with a `from` whose own window is not empty
    (`is_empty_window`), ordered on `(from, feature)` — the feature name breaking a tie so
    the answer does not depend on dict or filesystem order. Split out of `share_owners`
    because `head_bound` needs the same claim and the same pool, and two spellings of
    "earliest claimant" would drift the way `is_empty_window` exists to stop.

    A claim whose own window is empty is excluded here, not merely from the `in_window`
    test in `share_owners`. Emptiness is decided by the bounds alone, so
    `check_empty_window` already promises such a feature "will capture as $0.00" — but the
    ranking orders on `from` without consulting `to`, so a backwards window with an early
    `from` would sort first and win the whole head stretch it is proven to own none of.
    That is reachable in production: a feature that pins a session by id is admitted past
    window matching entirely, so its window is never required to select anything.

    The only empty claim that reaches here is the capturing feature's **own** —
    `session_claim_intervals` drops every other feature's, since one of those left in the
    list would also miscount `len(intervals)`. The own claim cannot be dropped (it is
    `intervals[0]` by contract), so this filter is what keeps it from being paid.
    """
    dated = [
        claim for claim in intervals
        if claim["from"] is not None and not is_empty_window(claim)
    ]
    if not dated:
        return None
    return min(dated, key=lambda claim: (claim["from"], claim["feature"]))


def head_bound(intervals):
    """The earliest instant the opening-stretch fallback may pay, or `None` when the
    fallback is unbounded or there is no dated claim to rank.

    The fallback hands every instant before the earliest `from` to the earliest claimant,
    on the reasoning in `share_owners` that a session's opening is the planning that led
    to the first feature it started. That is true of minutes and false of days: session
    `2d8b1236` ran 45 hours coordinating fifteen features in three other repos before the
    first of its three agentTooling claimants opened, and the earliest of those — ahead by
    49 seconds, with a 25-minute window — was paid $50.12 of that head. So the stretch is
    bounded by the earliest claimant's OWN window length: `from - (to - from)`, i.e. an
    instant is still that claimant's planning only when it lies no further before its
    `from` than its window is long. Earlier than that nobody owns it and it falls to the
    unclaimed remainder, exactly as the tail does, disclosed with the remedy named.

    Relative and not fixed, because the head is planning for the feature that follows and
    that scales with the feature: an hour of grace pays a two-minute feature an hour it
    did not plan for, and starves a three-day one.

    `None` — an unbounded head, today's behaviour — when the earliest claimant's `to` is
    still `null`. A window with no end has no length to bound by, and a feature in flight
    is the case where the opening stretch really is its own planning. `feature-close.sh`
    stamps `to` at close and the recapture that follows applies the bound.

    Returned rather than applied here so that `share_owners` and `partition_seconds` can
    each ask the same question once — the dollars and the seconds are split by one rule
    written in one place, the way `is_empty_window` is shared, and cannot disagree.
    """
    earliest = earliest_dated_claim(intervals)
    if earliest is None or earliest["to"] is None:
        return None
    return earliest["from"] - (earliest["to"] - earliest["from"])


def is_unpaid_head(moment, intervals, bound=None):
    """Whether an instant nobody owns lies in the opening stretch rather than in a gap
    between windows or in the tail past every `to`.

    Asked only of instants `share_owners` returned `[]` for, and answered by the bound
    alone: below `head_bound` the fallback refused to pay, at or above it the fallback
    would have paid, so an unowned instant at or above the bound is unowned for some other
    reason. `False` when the bound is `None` — an unbounded head pays everything before
    the earliest `from`, so nothing there can be unowned, and a session with no dated claim
    has no opening stretch to speak of.

    `bound` may be passed in by a caller that has it already, so a walk over a transcript
    does not recompute the same answer once per response — except when the bound is
    itself `None`, which is indistinguishable from "not supplied" and so is recomputed
    each call. That costs one `min` over the claims and cannot change the answer (a
    `None` bound makes the predicate `False` either way), which is why the sentinel is
    left conflated rather than replaced.
    """
    if bound is None:
        bound = head_bound(intervals)
    return bound is not None and moment is not None and moment < bound


def share_owners(moment, intervals):
    """Which claims own one instant. Every claim whose window contains it; failing that,
    the earliest claim alone when the instant precedes every `from` and lies no further
    before it than `head_bound` allows, because a session's opening stretch is the
    planning that led to the first feature it started — but only for as long as that
    feature's own window is, which is what `head_bound` decides. `[]` when the instant is
    past every `to`, and `[]` equally when it is further back than the bound: both are
    owned by nobody, reported rather than dropped, and repaired the same way.

    The ranking pool, and why an empty window is kept out of it, are
    `earliest_dated_claim`'s.
    """
    owners = [claim for claim in intervals if in_window(moment, claim)]
    if owners:
        return owners
    earliest = earliest_dated_claim(intervals)
    if earliest is None or moment is None or moment >= earliest["from"]:
        return []
    bound = head_bound(intervals)
    if bound is not None and moment < bound:
        return []
    return [earliest]


def partition_seconds(start, end, intervals):
    """Split `[start, end]` among the claims by the rule `share_owners` applies to one
    instant, returning `({feature: seconds}, unclaimed_seconds, unclaimed_head_seconds)`.

    Time is apportioned because the alternative is what the ledger holds today: three
    features that took an evening, eight minutes and an afternoon, each recording one
    coordinator's whole 22.8-hour span as its own duration. The cut points are every
    claim's bounds clamped into the span, so the parts are contiguous and sum to it.

    `head_bound` is one of those cut points, for the same reason every `from` and `to` is:
    a span is judged at its lower edge, so without that edge the whole `[start, min_from)`
    stretch is decided at `start` — unowned — and the part of the head the fallback still
    pays is lost from the claimant's `duration_s` while the seconds and the dollars
    disagree about where it went. That is the `is_empty_window` pattern: the rule is
    written once and both splits consult it.

    `unclaimed_head_seconds` is the part of `unclaimed_seconds` that lies before the
    bound — the opening stretch nobody owns, as against a gap between windows or the tail
    past every `to`. It is a subset of the second figure, not a fourth part of the span,
    and it exists so the disclosure can name the head apart from the rest: the remedies
    differ, since no `to` bound widened forwards can reach backwards."""
    if start is None or end is None or end <= start:
        return {}, 0.0, 0.0
    edges = {start, end}
    for claim in intervals:
        for bound in (claim["from"], claim["to"]):
            if bound is not None and start < bound < end:
                edges.add(bound)
    head_edge = head_bound(intervals)
    if head_edge is not None and start < head_edge < end:
        edges.add(head_edge)
    ordered = sorted(edges)
    per_feature = {}
    unclaimed = 0.0
    unclaimed_head = 0.0
    for lower, upper in zip(ordered, ordered[1:]):
        seconds = (upper - lower).total_seconds()
        owners = share_owners(lower, intervals)
        if not owners:
            unclaimed += seconds
            if is_unpaid_head(lower, intervals, head_edge):
                unclaimed_head += seconds
            continue
        for claim in owners:
            per_feature[claim["feature"]] = (
                per_feature.get(claim["feature"], 0.0) + seconds / len(owners)
            )
    return per_feature, unclaimed, unclaimed_head


def select_parent(
    lines, session_id, window, warnings, matched_session_ids,
    session_start, session_end, session_branch, matching_branches, totals,
    share_ctx, share_detail, pinned=False,
):
    """Decide one branch-matched session's window membership and, if selected, price it.
    Returns whether it was selected. Split out of `capture_feature` so the subagent walk
    can run for a parent this function rejected.

    Once selected, pricing goes through `session_claim_intervals`: a session with one
    claimant (itself) is billed whole into `totals`, exactly as before; a session with
    more is walked response by response and billed into `totals` only for the responses
    this feature owns, with `share_detail[session_id]` left for `capture_feature` to
    turn into `share_basis`, `session_cost_usd` and the apportioned `duration_s`."""
    # Ordered as instants, not as strings. A session's *start* is what window
    # membership is decided on below, and string ordering picks the wrong line
    # as soon as the transcript mixes formats: "2026-08-21T23:00:00-04:00"
    # sorts first but is an hour later than "2026-08-22T01:00:00Z".
    timestamps = [
        moment
        for moment in (to_utc(line.get("timestamp")) for line in lines)
        if moment is not None
    ]
    if not timestamps:
        return False
    start_ts = min(timestamps)
    end_ts = max(timestamps)

    # A pin is the human's word: it is claimed whatever the window says.
    selected = pinned or in_window(start_ts, window)

    if not selected:
        frm = window["from"]
        if frm is not None and start_ts < frm and end_ts >= frm:
            warnings.append(
                f"session {session_id} may span the window boundary "
                f"(window {describe_window(window)} UTC, "
                f"session starts {start_ts.isoformat()}, "
                f"ends {end_ts.isoformat()})"
            )
        return False

    matched_session_ids.add(session_id)
    session_start[session_id] = start_ts
    session_end[session_id] = end_ts
    session_branch[session_id] = (
        next(iter(matching_branches)) if matching_branches
        else next((line.get("gitBranch") for line in lines if line.get("gitBranch")), "")
    )

    # One API response is written to the transcript as several `assistant`
    # lines — one per content block (thinking, text, each tool_use) — and every
    # one of them repeats that response's `usage` verbatim, not a running total.
    # Summing per line therefore bills the same tokens once per content block:
    # measured 2.4x-2.8x over on real sessions, with individual responses
    # repeated up to 9 times. `iter_billable_messages` bills each response once,
    # keyed on its API id, and skips locally-generated `<synthetic>` notices.
    branches_seen = {line.get("gitBranch") for line in lines if line.get("gitBranch")}
    intervals = session_claim_intervals(session_id, start_ts, branches_seen, share_ctx, warnings)

    # After the claim set, not before it: what lies past `to` is counted on the unshared
    # path and excluded on the shared one, and the warning says which — so it cannot be
    # written until `len(intervals)` is known.
    if window["to"] is not None and end_ts > window["to"]:
        warnings.append(
            boundary_warning(
                session_id, window, lines, start_ts, end_ts, shared=len(intervals) > 1
            )
        )

    if len(intervals) <= 1:
        # A session nobody else claims has no double-count to remove, and slicing it
        # would trade a disclosed over-count for a silent under-count — this must be
        # byte-identical in effect to a capture that predates sharing altogether.
        for model, usage, is_sidechain in iter_billable_messages(lines):
            add_usage(totals, (session_id, None, model, is_sidechain, ()), usage)
        return True

    own_feature = intervals[0]["feature"]
    session_tokens = {}
    unclaimed_tokens = {}
    # The head is priced beside the rest of the remainder, not instead of it: it goes into
    # the same `unclaimed_usd` (there is no new `planning.json` field), and these tokens
    # are a SUBSET of `unclaimed_tokens` so the sum invariants are untouched. What it buys
    # is the disclosure — the head's remedies are not the tail's, and a single figure
    # cannot say which one to reach for. Computed once per session, not per response.
    unclaimed_head_tokens = {}
    bound = head_bound(intervals)
    for model, usage, is_sidechain, moment in iter_billable_messages_at(lines):
        add_usage(session_tokens, (model, is_sidechain), usage)
        owners = share_owners(moment, intervals)
        if not owners:
            add_usage(unclaimed_tokens, (model, is_sidechain), usage)
            if is_unpaid_head(moment, intervals, bound):
                add_usage(unclaimed_head_tokens, (model, is_sidechain), usage)
            continue
        owner_features = sorted(claim["feature"] for claim in owners)
        if own_feature not in owner_features:
            continue
        add_usage(totals, (session_id, None, model, is_sidechain, tuple(owner_features)), usage)

    share_detail[session_id] = {
        "intervals": intervals,
        "session_tokens": session_tokens,
        "unclaimed_tokens": unclaimed_tokens,
        "unclaimed_head_tokens": unclaimed_head_tokens,
    }
    return True


def capture_feature(slug, features_dir, sessions_dir, both_corpora, recapture, force, carry_lost=False):
    """Capture one feature, printing its own result line. Returns one of "captured",
    "annotated", "skipped", "refused" or "conflict" — `main` counts these and picks the
    exit code from them. "annotated" is the frozen-record path below: the record was left
    alone except for its `sessions[].also_claimed_by`, which the claims ledger changed.

    A whole feature per call, including its own transcript scan: `--all` is a loop over
    this, not a shared walk. The scan is the expensive part, and the skip above it means
    a corpus-wide run scans only the features it is actually going to write.
    """
    manifest_path = Path(features_dir, slug, "README.md")
    manifest = parse_manifest(manifest_path)
    branches = manifest.get("branches", [])
    pinned_agent_ids = set(manifest.get("subagents", []) or [])
    # Top-level sessions claimed by id — the twin of a subagent pin. How a planning
    # session that began on `main` before the branch existed is attributed without
    # `main` ever appearing in `branches`.
    pinned_session_ids = set(manifest.get("sessions", []) or [])
    # Subagents this manifest disowns: children of a selected session that another
    # feature pins — the coordinator case, where the coordinator's manifest owns the
    # coordinator's context and the arm's manifest owns the architect. The parent
    # route skips them; a pin on the same id is a contradiction and is warned about.
    excluded_agent_ids = set(manifest.get("exclude_subagents", []) or [])
    window = normalize_window(manifest)

    warnings = check_naive_bounds(manifest)
    warnings += check_empty_window(window)
    warnings += check_branch_overlap(both_corpora, slug, manifest)
    warnings += check_subagent_overlap(both_corpora, slug, manifest)

    output_path = Path(features_dir, slug, "planning.json")

    # Before the scan, not after: the point of the skip is that an already-frozen record
    # is not rebuilt, and reading every transcript first to then throw the result away is
    # what made the documented cadence slow enough to be run rarely and in bulk.
    prior_at, prior_total = prior_capture(output_path)
    if prior_at and not recapture:
        # Not simply "skipped" any more. A frozen record still has its shared-session
        # annotation refreshed from the claims ledger — `annotate_frozen_record`, which
        # opens no transcript and changes no figure. Without it item 3's motivating case
        # is unreachable by any automated path at all: `sweep.sh` runs `--all` with no
        # `--recapture`, so the seven features closed on 2026-09-07 would never name each
        # other's share, and the only way to get it would be a `--recapture` that
        # rebuilds their frozen dollars from transcripts that are expiring.
        #
        # `register_frozen_claims` (in `main`) has already put every frozen record in
        # this run into the ledger, so what is read here is the whole run's claims and
        # not just the ones swept before this feature.
        record = load_frozen_record(output_path)
        annotated, changed = [], False
        if record is not None:
            annotated, changed = annotate_frozen_record(
                output_path, record, load_ledger()[LEDGER_SESSIONS_KEY],
                corpus_identity(features_dir), slug,
            )
        if not changed:
            print(
                f"{slug}: already captured {prior_at}, total ${prior_total:.4f} — skipping "
                "(--recapture to rebuild it from transcripts)"
            )
        else:
            note = (
                f"annotated {len(annotated)} shared session(s)"
                if annotated else "cleared a stale shared-session annotation"
            )
            print(
                f"{slug}: already captured {prior_at}, total ${prior_total:.4f} — {note} "
                "from the claims ledger; no transcript read and no figure changed"
            )
        # An annotated session carrying no `share_basis` was frozen before the share rule
        # existed: its figure still counts that session in full, not by concurrent share.
        # The annotation only says who else claims it now; it does not, and must not,
        # touch the number. Printed on EVERY sweep that finds the record in that state,
        # not only on the one that changed the annotation — the annotation converges on
        # the first `--all` and the stale figure does not, so keying this off `changed`
        # asked for the repair once and then went quiet for as long as the transcript had
        # left. The `skipping` line above still means "this run wrote nothing".
        entries_by_id = {e.get("session_id"): e for e in (record or {}).get("sessions") or []}
        for session_id in annotated:
            if "share_basis" not in (entries_by_id.get(session_id) or {}):
                print(
                    f"WARN: {slug}: session {session_id} predates the share rule and "
                    "was frozen counting it in full — --recapture would rebuild it "
                    "while its transcript still exists"
                )
        # The manifest checks still run and still print. They read READMEs, not
        # transcripts, so they cost nothing here, and they are the half of this script's
        # output that stays actionable after a feature is frozen — a `to` bound missing
        # from a finished feature is worth hearing about on every pass, not only on the
        # one run that captured it. `check_unmatched_branches` is the exception and is
        # absent by construction: its evidence is the scan that did not happen.
        for warning in warnings:
            print(f"WARN: {warning}")
        # "annotated" versus "skipped" is the write, not the warning: `main` counts these
        # and `sweep.sh` reports them, and a run that wrote nothing must not read as one
        # that did.
        return "annotated" if changed else "skipped"

    excluded_ids = collect_excluded_session_ids(both_corpora, manifest)
    # Runner-spawned exclusions (a usage.json already holds that session's cost, its
    # subagents included) are never overridable. A manual `exclude_sessions` entry drops
    # only the session's own context cost: a pin on one of its subagents is an explicit
    # claim and still wins — the coordinator case, where the parent's cost belongs to
    # the coordinator's manifest and the architect's to the feature's.
    runner_excluded_ids = collect_excluded_session_ids(
        both_corpora, {**manifest, "exclude_sessions": []}
    )
    # Every excluded session whose transcript sits in this repo's directories. Serialized
    # as `excluded_session_ids` — deliberately wide, and NOT evidence about any branch.
    excluded_ids_encountered = set()
    # The subset that is evidence: excluded sessions that carry one of the manifest's
    # `branches` AND passed `repo_match`. Only this set lifts the zero refusal below.
    excluded_on_branch = set()
    excluded_agent_ids_encountered = set()

    session_dir_str = str(sessions_dir)
    dir_fragment = transcript_dir_name(sessions_dir)
    # LIFECYCLE.md: the feature's worktree is `<primary>/.worktrees/<slug>`, or the legacy
    # sibling `<primary>-<slug>` for a feature started before that layout. Both are
    # derived here rather than looked up — they still resolve after the worktree is
    # removed, and there is nothing to configure — and every other feature's worktree
    # under `<primary>/.worktrees` is fenced off (`claim_roots`).
    feature_worktree_str = feature_worktree_path(session_dir_str, slug)
    legacy_worktree_str = legacy_worktree_path(session_dir_str, slug)
    claimable_roots, claim_fences = claim_roots(session_dir_str, slug)

    totals = {}
    session_start = {}
    session_end = {}
    session_branch = {}
    # Where each selected session was launched, and by which route it was claimed —
    # both written to its planning.json entry so a reader can see why it is there.
    session_cwd = {}
    session_selected_by = {}
    # Sessions carrying a declared branch that were launched somewhere this feature
    # cannot claim from: cwd -> the branches seen there. The warning names them.
    launched_elsewhere = {}
    matched_session_ids = set()
    # Every session this scan can actually use, selected or not — what check_frozen_cost
    # calls recoverable. Populated only past repo_match, because that is the point the
    # scan has proved it can reach the transcript at all.
    reachable_session_ids = set()
    # The subagents this scan can reach, selected or not — the same proof point as
    # `reachable_session_ids`, for the same guard.
    reachable_agent_ids = set()
    agent_start = {}
    agent_end = {}
    agent_parent = {}
    agent_selected_by = {}
    # Pinned ids whose transcript sits under another repo's project directory.
    agent_cross_repo = set()
    # What each pinned subagent's brief says it is for, for the header check.
    agent_briefs = {}
    # Every branch name seen anywhere in this repo's transcript dirs, for the
    # does-this-name-even-exist check. Deliberately wider than `reachable`: a name is
    # not a typo just because its sessions were filtered out.
    branches_seen_anywhere = set()

    # Read once, before the walk: the share needs every other feature's claims on a
    # session this scan is about to select, and both halves of the ledger are needed
    # before the record is written — the sessions section for the share and the
    # annotation below, the subagents section for the refusal further down.
    # Which repo this FEATURE belongs to, not which one the session ran in: it is the
    # `repo` half of every ledger claim written below — subagent and session alike — and
    # of `share_ctx`, so it has to be the identity `build_claimant_index` gives the same
    # corpus, or the feature deduplicates against nothing. `sessions_dir` still answers
    # where the transcripts are; it does not answer who owns them.
    repo = corpus_identity(features_dir)
    repo_name = repo_display_name(repo)
    ledger = load_ledger()
    claims = ledger[LEDGER_SUBAGENTS_KEY]
    session_claims = ledger[LEDGER_SESSIONS_KEY]
    share_ctx = {
        "repo": repo,
        "repo_name": repo_name,
        "slug": slug,
        "features_dir": features_dir,
        "features_dirs": both_corpora,
        "window": window,
        "session_claims": session_claims,
        # Both corpora's manifests, read once. `session_claim_intervals` filters this in
        # memory for every session `select_parent` selects; before the index it re-globbed
        # and re-parsed every README, and re-ran `corpus_identity`, on each of those calls.
        "claimants": build_claimant_index(both_corpora),
    }
    # session_id -> {"intervals", "session_tokens", "unclaimed_tokens"} for every
    # multiply-claimed session `select_parent` selects — absent for a session with one
    # claimant, which is priced exactly as before.
    share_detail = {}

    for transcript_dir in find_transcript_dirs(sessions_dir):
        for jsonl_path in sorted(transcript_dir.glob("*.jsonl")):
            lines = load_transcript_lines(jsonl_path)
            if not lines:
                continue

            branches_seen = {line.get("gitBranch") for line in lines if line.get("gitBranch")}
            branches_seen_anywhere |= branches_seen

            session_id = next(
                (line.get("sessionId") for line in lines if line.get("sessionId")),
                None,
            )
            if session_id is None:
                continue

            session_pinned = session_id in pinned_session_ids
            pins_only = False
            # Hoisted above the exclusion branch so an excluded session can be judged on
            # the same two terms the selection path uses below.
            first_cwd = next(
                (line.get("cwd") for line in lines if isinstance(line.get("cwd"), str)), ""
            )
            repo_match = session_pinned or cwd_under_any(lines, claimable_roots, claim_fences)
            if session_id in excluded_ids:
                excluded_ids_encountered.add(session_id)
                # The evidenced zero rests on this narrower set, not on the wide one: an
                # excluded session only confirms the branch name when it actually carries
                # one of the declared branches (the same `branches_seen & set(branches)`
                # test the selection path makes) and was launched somewhere this feature
                # can claim from. A session carrying the branch from a directory it cannot
                # claim is the `launched_elsewhere` cause the refusal already names, so
                # counting it as evidence would trade one silent zero for another.
                if repo_match and (branches_seen & set(branches)):
                    excluded_on_branch.add(session_id)
                if session_id in runner_excluded_ids:
                    if session_pinned:
                        warnings.append(
                            f"session {session_id!r} is pinned in `sessions` but is a runner "
                            "session whose cost a usage.json already holds — the pin is ignored"
                        )
                    continue
                # A manual exclusion of a pinned session: the pin wins (warned about below,
                # from the manifest alone, so it fires wherever the transcript sits).
                if not session_pinned:
                    if not pinned_agent_ids:
                        continue
                    pins_only = True

            if not repo_match:
                # A declared branch seen from a directory this feature cannot claim from —
                # another feature's worktree, nested under `<primary>/.worktrees` or a
                # legacy sibling — is the case the naming rule exists for. Remembered so the warning can say where it was seen.
                seen_here = branches_seen & set(branches)
                if seen_here:
                    launched_elsewhere.setdefault(first_cwd, set()).update(seen_here)
                continue

            # A parent that is not selected — wrong branch, outside the window, manually
            # excluded — still has its subagents walked below, because a pinned subagent
            # is claimed on its own id and its parent's branch is usually `main`. So the
            # parent path sets a flag rather than `continue`-ing past the subagent walk.
            parent_selected = False
            matching_branches = branches_seen & set(branches)
            if pins_only:
                matching_branches = set()
            else:
                reachable_session_ids.add(session_id)
            if session_pinned or matching_branches:
                parent_selected = select_parent(
                    lines, session_id, window, warnings, matched_session_ids,
                    session_start, session_end, session_branch, matching_branches, totals,
                    share_ctx, share_detail, pinned=session_pinned,
                )
                if parent_selected:
                    session_selected_by[session_id] = "pinned" if session_pinned else "branch"
                    session_cwd[session_id] = first_cwd

            for agent_path in subagent_transcript_paths(transcript_dir, session_id):
                agent_lines = load_transcript_lines(agent_path)
                if not agent_lines:
                    continue
                agent_id = agent_id_of(agent_path, agent_lines)
                reachable_agent_ids.add(agent_id)
                # A resumed session re-files its subagents under the new session id, so
                # one transcript can sit under two parents. Price an id once.
                if agent_id in agent_start:
                    continue
                agent_start_ts = agent_start_of(agent_lines)
                if agent_start_ts is None:
                    continue
                if agent_id in pinned_agent_ids:
                    selected_by = "pinned"
                    agent_briefs[agent_id] = brief_feature_of(agent_lines)
                elif agent_id in excluded_agent_ids:
                    excluded_agent_ids_encountered.add(agent_id)
                    continue
                elif parent_selected and in_window(agent_start_ts, window):
                    selected_by = "parent"
                else:
                    continue
                agent_start[agent_id] = agent_start_ts
                agent_end[agent_id] = agent_end_of(agent_lines)
                agent_parent[agent_id] = session_id
                agent_selected_by[agent_id] = selected_by
                price_subagent(totals, session_id, agent_id, agent_lines)

    # A pin this repo's directories do not carry is looked for everywhere else: the
    # transcript is filed under the *parent's* cwd, and the parent was a coordinator
    # in another repo. Pins only — nothing is parent-selected across repos.
    this_repo_dirs = set(find_transcript_dirs(sessions_dir))
    for agent_id in sorted(pinned_agent_ids - reachable_agent_ids):
        agent_path = find_pinned_elsewhere(agent_id, this_repo_dirs)
        if agent_path is None:
            continue
        agent_lines = load_transcript_lines(agent_path)
        agent_start_ts = agent_start_of(agent_lines)
        if agent_start_ts is None:
            continue
        parent_id = next(
            (line.get("sessionId") for line in agent_lines if line.get("sessionId")),
            agent_path.parent.parent.name,
        )
        reachable_agent_ids.add(agent_id)
        agent_cross_repo.add(agent_id)
        agent_start[agent_id] = agent_start_ts
        agent_end[agent_id] = agent_end_of(agent_lines)
        agent_parent[agent_id] = parent_id
        agent_selected_by[agent_id] = "pinned"
        agent_briefs[agent_id] = brief_feature_of(agent_lines)
        price_subagent(totals, parent_id, agent_id, agent_lines)

    # A pinned session none of this repo's directories carry — launched in another
    # checkout, on whatever branch, before this feature existed — is looked for
    # everywhere else and claimed on its id alone, window and cwd notwithstanding.
    for session_id in sorted(pinned_session_ids - matched_session_ids):
        if session_id in runner_excluded_ids:
            continue
        session_path = find_session_elsewhere(session_id, this_repo_dirs)
        if session_path is None:
            continue
        lines = load_transcript_lines(session_path)
        if not lines:
            continue
        reachable_session_ids.add(session_id)
        if select_parent(
            lines, session_id, window, warnings, matched_session_ids,
            session_start, session_end, session_branch, set(), totals,
            share_ctx, share_detail, pinned=True,
        ):
            session_selected_by[session_id] = "pinned"
            session_cwd[session_id] = next(
                (line.get("cwd") for line in lines if isinstance(line.get("cwd"), str)), ""
            )

    # A cross-repo id priced last time and unpinned since is not *gone*: the guard
    # below reads "unreachable" as "expired", so prove the transcript is still on disk
    # before it looks. Nothing is priced here — an unpinned id earns nothing.
    for agent_id in prior_cross_repo_ids(output_path) - reachable_agent_ids:
        if find_pinned_elsewhere(agent_id, this_repo_dirs) is not None:
            reachable_agent_ids.add(agent_id)

    warnings += check_unmatched_branches(branches, branches_seen_anywhere, feature_worktree_str)
    for cwd, seen_branches in sorted(launched_elsewhere.items()):
        warnings.append(
            f"session(s) carrying branch(es) {sorted(seen_branches)} were launched from "
            f"{cwd!r}, which this feature cannot claim from: that is the primary checkout "
            f"{session_dir_str!r} outside {claim_fences[0]!r} (other features' worktrees), "
            f"this feature's worktree {feature_worktree_str!r}, and its legacy sibling "
            f"{legacy_worktree_str!r} — launch the coordinator inside the feature worktree, "
            "or pin each session id in the manifest's `sessions`"
        )
    for session_id in sorted(pinned_session_ids - reachable_session_ids):
        warnings.append(
            f"pinned session {session_id!r} matched no transcript under ~/.claude/projects/ "
            "— the id is wrong, or the transcript has aged out"
        )
    for session_id in sorted(pinned_session_ids & set(manifest.get("exclude_sessions") or [])):
        warnings.append(
            f"session {session_id!r} is both pinned and in exclude_sessions — the pin wins; "
            "drop one of them"
        )
    warnings += check_unmatched_subagents(pinned_agent_ids, reachable_agent_ids)
    warnings += check_brief_headers(agent_briefs, repo_name, slug)
    for agent_id in sorted(pinned_agent_ids & excluded_agent_ids):
        warnings.append(
            f"subagent {agent_id!r} is both pinned and in exclude_subagents — the pin "
            "wins; drop one of them"
        )

    # `started_at`/`ended_at`/`duration_s` are the transcript's first and last instants
    # and the seconds between — a span, with the caveat `duration_seconds` states.
    sessions = []
    for sid in sorted(matched_session_ids):
        entry = {
            "session_id": sid,
            "git_branch": session_branch[sid],
            "selected_by": session_selected_by.get(sid, "branch"),
            "cwd": session_cwd.get(sid),
            "date": session_start[sid].date().isoformat(),
            "started_at": session_start[sid].isoformat(),
            "ended_at": session_end[sid].isoformat(),
            "duration_s": duration_seconds(session_start[sid], session_end[sid]),
        }
        # Present only when some other feature's capture already claimed this session —
        # a coordinator that spans features, which is not refused (see
        # `other_session_claimants`) but must not be quoted as this feature's cost alone.
        # Absent otherwise, so an ordinary feature's planning.json is unchanged.
        also_claimed_by = other_session_claimants(session_claims, sid, repo, slug)
        if also_claimed_by:
            entry["also_claimed_by"] = also_claimed_by
        sessions.append(entry)

    subagents = [
        {
            "agent_id": agent_id,
            "parent_session_id": agent_parent[agent_id],
            "date": agent_start[agent_id].date().isoformat(),
            "started_at": agent_start[agent_id].isoformat(),
            "ended_at": agent_end[agent_id].isoformat() if agent_end.get(agent_id) else None,
            "duration_s": duration_seconds(agent_start[agent_id], agent_end.get(agent_id)),
            "selected_by": agent_selected_by[agent_id],
            "cross_repo": agent_id in agent_cross_repo,
        }
        for agent_id in sorted(agent_start)
    ]

    own_feature = f"{repo_name}/{slug}"
    priced = []
    total_is_partial = False
    for key in sorted(totals.keys(), key=lambda k: (k[0], k[1] or "", k[2], k[3], k[4])):
        session_id, agent_id, model, is_sidechain, refs = key
        tokens = totals[key]
        # A subagent is dated by its own start, not its parent's: a four-day coordinator
        # spawns architects on every one of those days, and the rate tier is per day.
        started = agent_start[agent_id] if agent_id else session_start[session_id]
        ended = agent_end.get(agent_id) if agent_id else session_end[session_id]
        as_of = started.date().isoformat()
        cost, rates_applied = compute_cost(model, tokens, as_of=as_of)
        if cost is None:
            where = f"subagent {agent_id} of session {session_id}" if agent_id else f"session {session_id}"
            warnings.append(f"no rate for model {model!r} ({where}); excluded from cost total")
            total_is_partial = True
        row = {
            "session_id": session_id,
            "agent_id": agent_id,
            "model": model,
            "is_sidechain": is_sidechain,
            "date": as_of,
            "duration_s": duration_seconds(started, ended),
            "tokens": dict(tokens),
            "cost_usd": cost,
            "rates_applied": rates_applied,
        }
        # A response with more than one owner carries only this feature's share here —
        # divided, so cost_usd.main/.sidechain/.total and every downstream sum
        # (report.py's roll-up, frozen_session_costs) are already right without being
        # touched — alongside the undivided full_cost_usd, the share fraction, and who
        # else it is shared with. A row with one ref (an unshared session, or the head
        # or tail of a shared one this feature owns alone) or none (a subagent) gains
        # none of these. `cost` is never divided when it is None — an unpriced row
        # stays unpriced exactly as today.
        if cost is not None and len(refs) > 1:
            row["full_cost_usd"] = cost
            row["cost_usd"] = cost / len(refs)
            row["share"] = 1 / len(refs)
            row["shared_with"] = sorted(f for f in refs if f != own_feature)
        priced.append(row)

    # session_id -> this feature's own share of that session's cost, from the rows just
    # priced above (a subagent's cost is excluded, same as `frozen_session_costs` below).
    # Used to fill in the shared-session fields on `sessions[]` and the warning naming
    # this feature's share — the session's own (undivided) cost is priced separately,
    # from `share_detail`, since these divided rows do not sum back to it.
    session_share_cost = {}
    for row in priced:
        if row["agent_id"]:
            continue
        session_share_cost[row["session_id"]] = (
            session_share_cost.get(row["session_id"], 0.0) + (row["cost_usd"] or 0.0)
        )

    for entry in sessions:
        sid = entry.get("session_id")
        detail = share_detail.get(sid) if sid else None
        if detail is None:
            continue
        intervals = detail["intervals"]
        as_of = session_start[sid].date().isoformat()

        session_cost = 0.0
        for (model, is_sidechain), tokens in detail["session_tokens"].items():
            cost, _rates = compute_cost(model, tokens, as_of=as_of)
            if cost is None:
                warnings.append(
                    f"no rate for model {model!r} (session {sid}'s own undivided cost); "
                    "session_cost_usd excludes those tokens and is a lower bound"
                )
                continue
            session_cost += cost

        unclaimed_cost = 0.0
        for (model, is_sidechain), tokens in detail["unclaimed_tokens"].items():
            cost, _rates = compute_cost(model, tokens, as_of=as_of)
            if cost is None:
                warnings.append(
                    f"no rate for model {model!r} (session {sid}'s unclaimed remainder); "
                    "unclaimed_usd excludes those tokens and is a lower bound"
                )
                continue
            unclaimed_cost += cost

        # The head's own dollars, for the disclosure below. No warning of its own on an
        # unpriced model: these tokens are a SUBSET of the remainder's, so the loop above
        # has already said that model has no rate and that the figure is a lower bound —
        # a second copy of the same sentence would say nothing new, and both figures are
        # then lower bounds together.
        unclaimed_head_cost = 0.0
        for (model, is_sidechain), tokens in detail["unclaimed_head_tokens"].items():
            cost, _rates = compute_cost(model, tokens, as_of=as_of)
            if cost is None:
                continue
            unclaimed_head_cost += cost

        entry["share_basis"] = [
            {
                "feature": claim["feature"],
                "from": _iso_or_none(claim["from"]),
                "to": _iso_or_none(claim["to"]),
                "source": claim["source"],
            }
            for claim in intervals
        ]
        entry["session_cost_usd"] = session_cost
        entry["session_duration_s"] = duration_seconds(session_start[sid], session_end[sid])
        # This feature's SHARE of the span, replacing the whole-span default set above —
        # started_at/ended_at are left untouched, since they are the transcript's own
        # bounds and only duration_s is apportioned.
        per_feature_seconds, unclaimed_seconds, unclaimed_head_seconds = partition_seconds(
            session_start[sid], session_end[sid], intervals
        )
        entry["duration_s"] = int(per_feature_seconds.get(own_feature, 0.0))
        if unclaimed_cost:
            entry["unclaimed_usd"] = unclaimed_cost
        # Gated on the seconds, NOT on the dollars. The two are not the same condition:
        # a session whose last line is non-billable — a user message, a tool result, a
        # `<synthetic>` notice — past every claimant's `to` has unclaimed *time* and no
        # unclaimed *cost*. Keyed off the dollars, that session's claimants' duration_s
        # would silently fail to sum to session_duration_s with nothing in the record or
        # on stdout saying where the difference went, and no field to read it from.
        if unclaimed_seconds:
            entry["unclaimed_duration_s"] = int(unclaimed_seconds)

        other_features = sorted(c["feature"] for c in intervals if c["feature"] != own_feature)
        own_share_cost = session_share_cost.get(sid, 0.0)
        warnings.append(
            f"session {sid} is shared by {len(intervals)} claimant(s); this feature's "
            f"share is ${own_share_cost:.4f} of the session's own ${session_cost:.4f}, "
            f"the rest going to {', '.join(other_features)}"
        )
        # Either quantity is worth reporting on its own: unclaimed time with no unclaimed
        # dollars still means a stretch of the session belongs to nobody, and the advice
        # for repairing it is the same.
        # Two sentences for two remedies. Everything past every claimant's `to` — and
        # everything in a gap between two windows — is repaired by widening a `to` bound
        # forwards or by pinning the session, which is what this warning has always said.
        # A head is not reachable that way at all: it lies BEFORE the earliest `from`, so
        # no `to` can grow to cover it, and `from` has no `set-window-to` to move it with
        # (`analysis/manifest.py` only ever moves `to`, and only inwards). Said with one
        # figure, the reader reaches for the remedy that cannot work. So the head is named
        # with its own dollars and seconds whenever there is one, and the sentence for a
        # remainder that is all tail is left exactly as it was.
        if unclaimed_head_cost or unclaimed_head_seconds:
            rest_cost = unclaimed_cost - unclaimed_head_cost
            rest_seconds = unclaimed_seconds - unclaimed_head_seconds
            # A remainder that is ALL head has no rest to name — the mirror of the
            # tail-only case above, and not a rare one: one claimant whose window covers
            # the session's last instant leaves no tail, and a single claimant leaves no
            # gap between windows either. Said anyway, the sentence reads "and $0.0000
            # (0s) is the rest" and then hands the reader the `to`-widening remedy for
            # exactly nothing — the one remedy that provably cannot reach a head, since
            # no `to` grows backwards. So the clause and its sentence go together, and
            # with nothing to contrast the head against, its own remedy stops being
            # introduced as "For the head".
            rest_clause = ""
            rest_remedy = ""
            if rest_cost or rest_seconds:
                rest_clause = f" — and ${rest_cost:.4f} ({rest_seconds:.0f}s) is the rest"
                rest_remedy = (
                    ". For the rest, widen a claimant's `to` bound, or pin the session "
                    "to the feature it belongs to, to have it counted"
                )
            head_remedy_lead = "For the head, pin" if rest_clause else "Pin"
            warnings.append(
                f"session {sid} has ${unclaimed_cost:.4f} ({unclaimed_seconds:.0f}s) "
                f"unclaimed by any feature, of which ${unclaimed_head_cost:.4f} "
                f"({unclaimed_head_seconds:.0f}s) is the opening stretch — further before "
                "the earliest claimant's `from` than that claimant's own window is long"
                f"{rest_clause}. {head_remedy_lead} the session to the feature that "
                "planning belongs to, or move the earliest claimant's `from` back by hand "
                f"(there is no `set-window-to` for `from`){rest_remedy}"
            )
        elif unclaimed_cost or unclaimed_seconds:
            warnings.append(
                f"session {sid} has ${unclaimed_cost:.4f} ({unclaimed_seconds:.0f}s) "
                "unclaimed by any feature — widen a claimant's `to` bound, or pin the "
                "session to the feature it belongs to, to have it counted"
            )

    lost, prior_total = check_frozen_cost(
        output_path, reachable_session_ids, excluded_ids, reachable_agent_ids
    )
    carried_from = None
    if lost and carry_lost and not force:
        carried_from, c_sessions, c_subagents, c_priced = carry_lost_entries(output_path, lost)
        sessions += c_sessions
        subagents += c_subagents
        priced += c_priced
        for entry in c_subagents:
            agent_selected_by[entry["agent_id"]] = entry.get("selected_by", "pinned")
        warnings.append(
            f"{len(lost)} entr{'y' if len(lost) == 1 else 'ies'} carried forward from the "
            f"capture of {carried_from}: their transcripts are gone, so the figure is the "
            f"prior one — {', '.join(lost)}"
        )
        lost = []

    main_cost = sum(
        (p["cost_usd"] for p in priced if not p["is_sidechain"] and p["cost_usd"] is not None),
        0.0,
    )
    sidechain_cost = sum(
        (p["cost_usd"] for p in priced if p["is_sidechain"] and p["cost_usd"] is not None),
        0.0,
    )
    # The part of `sidechain` that came from subagent transcript files rather than
    # inline sidechain messages — reported separately because it is the figure the
    # delegation-tier comparison needs, and it was invisible before this scan read them.
    subagent_cost = sum(
        (p["cost_usd"] for p in priced if p["agent_id"] and p["cost_usd"] is not None),
        0.0,
    )
    total_cost = main_cost + sidechain_cost

    # Summed over the entries above, carried ones included, so a re-capture that kept an
    # old entry counts its time exactly as it counts its cost. An entry captured before
    # this field existed has none and contributes nothing — the figure is then a lower
    # bound, exactly like a partial cost total, and `sessions_without_duration` says so.
    sessions_duration = sum((e.get("duration_s") or 0) for e in sessions)
    subagents_duration = sum((e.get("duration_s") or 0) for e in subagents)
    without_duration = sorted(
        e.get("session_id") or e.get("agent_id")
        for e in [*sessions, *subagents]
        if e.get("duration_s") is None
    )

    if is_rates_stale():
        warnings.append(f"RATES_VERIFIED is stale (verified {RATES_VERIFIED})")

    data = {
        "slug": slug,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "manifest_branches": branches,
        "manifest_subagents": sorted(pinned_agent_ids),
        "sessions": sessions,
        "subagents": subagents,
        "excluded_session_ids": sorted(excluded_ids_encountered),
        "excluded_agent_ids": sorted(excluded_agent_ids_encountered),
        "priced": priced,
        "cost_usd": {
            "main": main_cost,
            "sidechain": sidechain_cost,
            "subagents": subagent_cost,
            "total": total_cost,
            "total_is_partial": total_is_partial,
        },
        # Kept as two figures, never one: a subagent's span is its working time, a
        # session's span is a span (see `duration_seconds`). report.py's Time table
        # shows both rows and lets the reader weigh them.
        "duration_s": {
            "sessions": sessions_duration,
            "subagents": subagents_duration,
            "entries_without_duration": without_duration,
        },
        "rates_source": f"agentTooling/analysis/pricing.py RATES_VERIFIED={RATES_VERIFIED}",
        "warnings": warnings,
    }
    if carried_from:
        data["carried_from"] = carried_from

    if lost and not force:
        print(
            f"{slug}: REFUSING to overwrite planning.json — "
            f"{len(lost)} priced session(s)/subagent(s) are missing from this scan and their "
            "transcripts are gone from ~/.claude/projects/, so the frozen figure is "
            "the only surviving record:"
        )
        for session_id in lost:
            print(f"  {session_id}")
        print(
            f"  recorded total ${prior_total:.4f} left untouched. Transcripts expire; "
            "re-capture a feature only while they still exist. Pass --carry-lost to keep "
            "these entries and add what this scan reaches (how a pin is added to an old "
            "feature), or --force to overwrite anyway."
        )
        for warning in warnings:
            print(f"WARN: {warning}")
        return "refused"

    # Three causes for an unmatched zero are indistinguishable from here — a wrong branch
    # name, sessions launched outside this worktree, or aged-out transcripts — so the
    # refusal below spells out all three rather than guessing which applies. A fourth
    # outcome is not a cause for refusal: when `excluded_on_branch` is non-empty, an
    # excluded session (a runner session, or one named in the manifest's
    # `exclude_sessions`) was seen carrying one of these branches, from a directory this
    # feature can claim from, so the name is confirmed right and the zero is evidenced
    # rather than suspicious — that case falls through to the block below instead of
    # refusing. `excluded_ids_encountered` is deliberately NOT the set used here: it holds
    # every excluded session whose transcript sits in this repo's directories, so in any
    # repo that has ever run a batch it is non-empty regardless of branch, and a typo'd
    # `branches` would read as an evidenced $0.00 instead of the refusal it is.
    if not sessions and not subagents and not excluded_on_branch and not force:
        elsewhere = (
            "; ".join(
                f"{sorted(b)} seen from {cwd!r}" for cwd, b in sorted(launched_elsewhere.items())
            )
            or "no transcript carrying these branches was seen outside the primary checkout"
        )
        print(
            f"{slug}: REFUSING to write planning.json — no session and no subagent matched, "
            'and a $0.00 record reads as "planning was free". One of three things is true:'
        )
        print(
            f"  1. a branch name is wrong: `branches` is {branches} — check `git branch "
            "--list` and copy the name exactly, with no prefix;"
        )
        print(
            f"  2. the sessions were launched somewhere else: {elsewhere} — launch the "
            f"coordinator inside the feature worktree ({feature_worktree_str}), or pin "
            "each session id in the manifest's `sessions`;"
        )
        print(
            "  3. the transcripts have aged out of ~/.claude/projects/ — the cost is "
            "unrecoverable, and --force writes the honest zero."
        )
        for warning in warnings:
            print(f"WARN: {warning}")
        return "refused"

    if not sessions and not subagents and excluded_on_branch:
        note = (
            f"no planning session matched, but {len(excluded_on_branch)} excluded "
            f"session(s) on {branches} were met — the branch name is right and the zero is "
            "evidenced; their cost is in usage.json or belongs to the feature that excluded them"
        )
        warnings.append(note)
        print(f"{slug}: {note}; writing planning.json with cost $0.00")

    conflicts = check_claims(agent_selected_by, repo, slug, claims)
    if conflicts:
        print(
            f"{slug}: REFUSING to write planning.json — {len(conflicts)} subagent(s) are "
            "already claimed by another feature, and one transcript's cost cannot belong "
            "to two:"
        )
        for agent_id, other_repo, other_slug in conflicts:
            print(f"  {agent_id}  claimed by {other_repo}/{other_slug}")
        print(
            "  Drop the pin from one manifest (or re-capture the other feature without "
            f"it) and run again. Ledger: {claims_ledger_path()}"
        )
        for warning in warnings:
            print(f"WARN: {warning}")
        return "conflict"

    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    agent_costs = {}
    session_costs = {}
    for entry in priced:
        if entry["agent_id"]:
            agent_costs[entry["agent_id"]] = (
                agent_costs.get(entry["agent_id"], 0.0) + (entry["cost_usd"] or 0.0)
            )
        else:
            # A session's OWN dollars, its delegates' excluded: a subagent is claimed by
            # exactly one feature, so rolling its cost in here would report money that is
            # not in fact counted twice.
            session_costs[entry["session_id"]] = (
                session_costs.get(entry["session_id"], 0.0) + (entry["cost_usd"] or 0.0)
            )
    record_claims(claims, agent_costs, agent_selected_by, repo, repo_name, slug)
    record_session_claims(
        session_claims, session_costs, session_selected_by, repo, repo_name, slug, window
    )
    save_ledger(claims, session_claims)

    cost_str = "cost unavailable — see warnings" if total_is_partial else f"${total_cost:.4f}"
    print(
        f"{slug}: {len(sessions)} sessions matched, {len(subagents)} subagents, "
        f"{len(excluded_ids_encountered)} excluded, total {cost_str}"
    )
    for warning in warnings:
        print(f"WARN: {warning}")
    return "captured"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "slug",
        nargs="?",
        help="feature slug under plans/features/<slug>/ (or self/features/<slug>/ "
        "with --self)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="all_features",
        help="walk every feature in the corpus instead of one, capturing those that "
        "have no planning.json yet; with --recapture, a full refresh",
    )
    parser.add_argument(
        "--recapture",
        action="store_true",
        help="rebuild planning.json even for a feature already captured (the default "
        "is to leave a frozen record alone). Implied by --force",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite planning.json even when doing so would discard a priced "
        "session whose transcript is gone (see check_frozen_cost)",
    )
    parser.add_argument(
        "--list-subagents",
        action="store_true",
        help="print every subagent transcript reachable from this repo's project "
        "directories — date, id, parent, branch, model, cost, opening prompt — instead "
        "of capturing anything. How to find an id for a manifest's `subagents` pin",
    )
    parser.add_argument(
        "--list-sessions",
        action="store_true",
        help="print every top-level session launched in this repo's primary checkout "
        "(feature worktrees under .worktrees/ included) or a legacy sibling worktree "
        "— date, id, branch, cwd, model, cost, opening prompt — "
        "instead of capturing anything. With --unclaimed, only those no feature "
        "accounts for; the id is what a manifest's `sessions` pin takes",
    )
    parser.add_argument(
        "--last-branch-instant",
        metavar="SLUG",
        help="print the bound feature-close.sh stamps as session_window.to for this "
        "feature — one second past the last instant of the sessions its `branches` and "
        "`session_window` select, and of their subagents — as ISO 8601 UTC with a Z, or "
        "nothing at all (exit 0) when it has no branch-selected session. Pins are not "
        "consulted: the coordinator a manifest pins outlives the feature. Reads "
        "timestamps only; writes nothing",
    )
    parser.add_argument(
        "--carry-lost",
        action="store_true",
        help="re-capture, keeping the prior entries whose transcripts have expired "
        "(marked carried_from) and adding what this scan reaches — the way to add a "
        "subagent pin to a feature whose own sessions are gone. Implies --recapture",
    )
    parser.add_argument(
        "--unclaimed",
        action="store_true",
        help="with --list-subagents or --list-sessions: only those no feature has claimed in the "
        f"ledger (~/.claude/{CLAIMS_LEDGER_NAME}), scanning every project directory, "
        "with the feature each brief names — the pins still to write",
    )
    parser.add_argument(
        "--for",
        dest="for_feature",
        metavar="REPO/SLUG",
        help="with --list-subagents --unclaimed: keep only the delegates whose brief "
        "names exactly this feature, compared as the (repo, slug) pair the brief "
        "carries and never as text in the printed table. What feature-close.sh's "
        "stray-delegate guard reads",
    )
    parser.add_argument(
        "--everywhere",
        action="store_true",
        help="with --list-subagents: scan every project directory, not just this "
        "repo's, and show each parent's cwd — for a delegate spawned from a "
        "coordinator in another repo",
    )
    parser.add_argument(
        "--since",
        metavar="YYYY-MM-DD",
        help="with --list-subagents or --list-sessions: only those that started on or after this UTC date",
    )
    add_self_flag(parser)
    args = parser.parse_args()

    # --for narrows a list of unclaimed delegates to one feature's; on any other run
    # there is nothing for it to narrow, and silently ignoring it would be a filter the
    # caller believes in and did not get.
    only_feature = None
    if args.for_feature is not None:
        if not (args.list_subagents and args.unclaimed):
            parser.error("--for takes --list-subagents --unclaimed")
        only_feature = parse_feature_ref(args.for_feature)
        if only_feature is None:
            parser.error(f"--for takes <repo>/<slug>, not {args.for_feature!r}")

    if args.list_subagents:
        if args.slug or args.all_features:
            parser.error("--list-subagents takes no slug and no --all")
        list_subagents(
            session_root(args.self_mode), args.since, args.everywhere, args.unclaimed,
            only_feature=only_feature, features_dirs=all_features_roots(),
            # The corpus this query is for. Both are still read when it holds no
            # manifest for the slug; see `manifest_pinned_subagents`.
            preferred_features_dir=features_root(args.self_mode),
        )
        return
    if args.list_sessions:
        if args.slug or args.all_features:
            parser.error("--list-sessions takes no slug and no --all")
        list_sessions(session_root(args.self_mode), args.since, args.unclaimed, all_features_roots())
        return
    if args.last_branch_instant:
        if args.slug or args.all_features:
            parser.error("--last-branch-instant takes its own slug and no --all")
        moment = last_branch_instant(
            args.last_branch_instant, features_root(args.self_mode),
            session_root(args.self_mode),
        )
        # Nothing, exit 0, when there is no branch-selected session: an empty answer is a
        # fact about the feature, not a failure, and feature-close.sh reads it as its cue
        # to stamp at its own clock and announce that it did.
        if moment is not None:
            print(_iso_or_none(moment))
        return

    if args.all_features == bool(args.slug):
        parser.error("give either a feature slug or --all, not both and not neither")

    features_dir = features_root(args.self_mode)
    sessions_dir = session_root(args.self_mode)
    # Both corpora: `features_dir` says where to write, but a runner session on a
    # feature's branch may belong to a feature in the other tree.
    both_corpora = all_features_roots()
    # --force is the stronger ask of the two — it overwrites past the frozen-cost guard —
    # so it cannot be stopped by the skip that sits in front of that guard.
    recapture = args.recapture or args.force or args.carry_lost

    slugs = feature_slugs(features_dir) if args.all_features else [args.slug]

    # Phase one of the annotate-only path, before a single feature is looked at: every
    # frozen record in this run registers its own session claims in the ledger, so the
    # annotation each of them then reads is the whole run's and not just the part swept
    # before it (`register_frozen_claims`). Skipped under --recapture, where every
    # feature re-derives its claims from transcripts anyway.
    if not recapture:
        register_frozen_claims(slugs, features_dir, args.all_features)

    counts = {
        "captured": 0, "annotated": 0, "skipped": 0, "refused": 0, "conflict": 0,
        "unreadable": 0, "in_flight": 0,
    }
    for slug in slugs:
        try:
            # A sweep must not freeze a feature that is still being built: its first
            # capture is feature-close.sh's, after the PR merged and every session ended.
            # A record frozen here would make that close skip as "already captured" and
            # report the premature figure. Only --all skips; naming the slug still captures.
            if args.all_features and window_is_open(features_dir, slug):
                print(
                    f"{slug}: in flight — session_window.to is null, so feature-close.sh has "
                    "not run yet; skipped (name the slug to capture it anyway)"
                )
                counts["in_flight"] += 1
                continue
            outcome = capture_feature(
                slug, features_dir, sessions_dir, both_corpora, recapture, args.force,
                carry_lost=args.carry_lost,
            )
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            # One unparseable manifest must not end a corpus-wide run — the features
            # after it are the ones whose transcripts are still expiring. It is still a
            # real problem, so it is counted and it colours the exit code.
            if not args.all_features:
                raise
            print(f"{slug}: cannot read manifest — {exc}")
            counts["unreadable"] += 1
            continue
        counts[outcome] += 1

    if args.all_features:
        print(
            f"{len(slugs)} features: {counts['captured']} captured, "
            f"{counts['skipped']} already captured, {counts['refused']} refused"
            + (f", {counts['annotated']} annotated" if counts["annotated"] else "")
            + (f", {counts['in_flight']} in flight" if counts["in_flight"] else "")
            + (f", {counts['conflict']} in conflict" if counts["conflict"] else "")
            + (f", {counts['unreadable']} unreadable" if counts["unreadable"] else "")
        )
        unclaimed = unclaimed_under(find_transcript_dirs(sessions_dir), load_claims())
        if unclaimed:
            print(
                f"{len(unclaimed)} subagent transcript(s) under this repo's project "
                "directories are claimed by no feature anywhere — run "
                "--list-subagents --unclaimed and pin them while they still exist"
            )

    if counts["refused"] or counts["conflict"] or counts["unreadable"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
