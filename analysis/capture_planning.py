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

Populates only what is not yet populated. A feature whose `planning.json` already
carries a `captured_at` is skipped — nothing rewrites a frozen record without being
asked, and the skip happens before the transcript scan, so a corpus-wide run costs
almost nothing. `--recapture` rebuilds anyway; `--all` walks every feature.

Usage: python3 agentTooling/analysis/capture_planning.py <slug>
       python3 agentTooling/analysis/capture_planning.py --all [--recapture]
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from pricing import RATES_VERIFIED, compute_cost, is_rates_stale
from roots import add_self_flag, all_features_roots, features_root, session_root
from transcript import add_usage, iter_billable_messages, to_utc


def transcript_dir_name(repo_dir):
    """cwd path -> its transcript directory name under ~/.claude/projects/,
    e.g. /Users/x/dev/vinylCatalogue -> -Users-x-dev-vinylCatalogue.

    For matching ~/.claude/projects/ directory *names* only. The mangled form is
    not a valid prefix or substring test against a real filesystem path (a `cwd`
    value) — see the repo_match fallback in main(), which uses the unmangled
    session root for that instead."""
    return str(repo_dir).replace("/", "-")


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
    frm, to = window.get("from"), window.get("to")
    if frm is None or to is None or frm < to:
        return []
    relation = "equals" if frm == to else "is later than"
    return [
        f"session_window is empty — `from` ({frm.isoformat()}) {relation} `to` "
        f"({to.isoformat()}), and the window is half-open, so it matches no session "
        "at all and this feature will capture as $0.00 regardless of what is on its "
        "branch. Widen the window to cover the sessions you mean; to chain onto a "
        "neighbouring feature, give this one a `from` at the neighbour's `to`"
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


def check_unmatched_branches(branches, branches_seen):
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
    return [
        f"branch {name!r} matched no session in any transcript for this repo, so any "
        "planning on it is uncounted and reports as $0.00 rather than as an error. "
        "Either the name is wrong — check it against `git branch --list` and record it "
        "exactly as git shows it, with no added prefix — or the transcripts have aged "
        "out of ~/.claude/projects/, in which case the name is fine and the cost is "
        "simply unrecoverable"
        for name in unmatched
    ]


def check_frozen_cost(output_path, reachable_session_ids, excluded_ids):
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

    Returns (lost_session_ids, prior_total). An empty list means the write is safe.
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
    return lost, prior_total


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


def feature_slugs(features_dir):
    """Every feature in a corpus, in name order: a directory holding the README.md whose
    last ```json fence is its manifest.

    The same shape `check_branch_overlap` scans for, so `--all` walks exactly the set
    that participates in overlap detection — a directory that is not a feature by one
    test is not a feature by the other either.
    """
    return sorted(path.parent.name for path in features_dir.glob("*/README.md"))


def capture_feature(slug, features_dir, sessions_dir, both_corpora, recapture, force):
    """Capture one feature, printing its own result line. Returns one of "captured",
    "skipped" or "refused" — `main` counts these and picks the exit code from them.

    A whole feature per call, including its own transcript scan: `--all` is a loop over
    this, not a shared walk. The scan is the expensive part, and the skip above it means
    a corpus-wide run scans only the features it is actually going to write.
    """
    manifest_path = Path(features_dir, slug, "README.md")
    manifest = parse_manifest(manifest_path)
    branches = manifest.get("branches", [])
    window = normalize_window(manifest)

    warnings = check_naive_bounds(manifest)
    warnings += check_empty_window(window)
    warnings += check_branch_overlap(both_corpora, slug, manifest)

    output_path = Path(features_dir, slug, "planning.json")

    # Before the scan, not after: the point of the skip is that an already-frozen record
    # is not rebuilt, and reading every transcript first to then throw the result away is
    # what made the documented cadence slow enough to be run rarely and in bulk.
    prior_at, prior_total = prior_capture(output_path)
    if prior_at and not recapture:
        print(
            f"{slug}: already captured {prior_at}, total ${prior_total:.4f} — skipping "
            "(--recapture to rebuild it from transcripts)"
        )
        # The manifest checks still run and still print. They read READMEs, not
        # transcripts, so they cost nothing here, and they are the half of this script's
        # output that stays actionable after a feature is frozen — a `to` bound missing
        # from a finished feature is worth hearing about on every pass, not only on the
        # one run that captured it. `check_unmatched_branches` is the exception and is
        # absent by construction: its evidence is the scan that did not happen.
        for warning in warnings:
            print(f"WARN: {warning}")
        return "skipped"

    excluded_ids = collect_excluded_session_ids(both_corpora, manifest)
    excluded_ids_encountered = set()

    session_dir_str = str(sessions_dir)
    dir_fragment = transcript_dir_name(sessions_dir)

    totals = {}
    session_start = {}
    session_end = {}
    session_branch = {}
    matched_session_ids = set()
    # Every session this scan can actually use, selected or not — what check_frozen_cost
    # calls recoverable. Populated only past repo_match, because that is the point the
    # scan has proved it can reach the transcript at all.
    reachable_session_ids = set()
    # Every branch name seen anywhere in this repo's transcript dirs, for the
    # does-this-name-even-exist check. Deliberately wider than `reachable`: a name is
    # not a typo just because its sessions were filtered out.
    branches_seen_anywhere = set()

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

            if session_id in excluded_ids:
                excluded_ids_encountered.add(session_id)
                continue

            repo_match = any(
                line.get("cwd") == session_dir_str
                or (
                    isinstance(line.get("cwd"), str)
                    and line["cwd"].startswith(session_dir_str + "/")
                )
                for line in lines
            )
            if not repo_match:
                continue

            reachable_session_ids.add(session_id)

            matching_branches = branches_seen & set(branches)
            if not matching_branches:
                continue

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
                continue
            start_ts = min(timestamps)
            end_ts = max(timestamps)

            selected = in_window(start_ts, window)

            if selected:
                if window["to"] is not None and end_ts > window["to"]:
                    warnings.append(
                        f"session {session_id} may span the window boundary "
                        f"(window {describe_window(window)} UTC, "
                        f"session ends {end_ts.isoformat()})"
                    )
            else:
                frm = window["from"]
                if frm is not None and start_ts < frm and end_ts >= frm:
                    warnings.append(
                        f"session {session_id} may span the window boundary "
                        f"(window {describe_window(window)} UTC, "
                        f"session starts {start_ts.isoformat()}, "
                        f"ends {end_ts.isoformat()})"
                    )
                continue

            matched_session_ids.add(session_id)
            session_start[session_id] = start_ts
            session_end[session_id] = end_ts
            session_branch[session_id] = next(iter(matching_branches))

            # One API response is written to the transcript as several `assistant`
            # lines — one per content block (thinking, text, each tool_use) — and every
            # one of them repeats that response's `usage` verbatim, not a running total.
            # Summing per line therefore bills the same tokens once per content block:
            # measured 2.4x-2.8x over on real sessions, with individual responses
            # repeated up to 9 times. `iter_billable_messages` bills each response once,
            # keyed on its API id, and skips locally-generated `<synthetic>` notices.
            for model, usage, is_sidechain in iter_billable_messages(lines):
                add_usage(totals, (session_id, model, is_sidechain), usage)

    warnings += check_unmatched_branches(branches, branches_seen_anywhere)

    sessions = [
        {
            "session_id": sid,
            "git_branch": session_branch[sid],
            "date": session_start[sid].date().isoformat(),
        }
        for sid in sorted(matched_session_ids)
    ]

    priced = []
    total_is_partial = False
    for key in sorted(totals.keys()):
        session_id, model, is_sidechain = key
        tokens = totals[key]
        as_of = session_start[session_id].date().isoformat()
        cost, rates_applied = compute_cost(model, tokens, as_of=as_of)
        if cost is None:
            warnings.append(
                f"no rate for model {model!r} (session {session_id}); "
                "excluded from cost total"
            )
            total_is_partial = True
        priced.append(
            {
                "session_id": session_id,
                "model": model,
                "is_sidechain": is_sidechain,
                "date": as_of,
                "tokens": dict(tokens),
                "cost_usd": cost,
                "rates_applied": rates_applied,
            }
        )

    main_cost = sum(
        (p["cost_usd"] for p in priced if not p["is_sidechain"] and p["cost_usd"] is not None),
        0.0,
    )
    sidechain_cost = sum(
        (p["cost_usd"] for p in priced if p["is_sidechain"] and p["cost_usd"] is not None),
        0.0,
    )
    total_cost = main_cost + sidechain_cost

    if is_rates_stale():
        warnings.append(f"RATES_VERIFIED is stale (verified {RATES_VERIFIED})")

    data = {
        "slug": slug,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "manifest_branches": branches,
        "sessions": sessions,
        "excluded_session_ids": sorted(excluded_ids_encountered),
        "priced": priced,
        "cost_usd": {
            "main": main_cost,
            "sidechain": sidechain_cost,
            "total": total_cost,
            "total_is_partial": total_is_partial,
        },
        "rates_source": f"agentTooling/analysis/pricing.py RATES_VERIFIED={RATES_VERIFIED}",
        "warnings": warnings,
    }

    lost, prior_total = check_frozen_cost(output_path, reachable_session_ids, excluded_ids)
    if lost and not force:
        print(
            f"{slug}: REFUSING to overwrite planning.json — "
            f"{len(lost)} priced session(s) are missing from this scan and their "
            "transcripts are gone from ~/.claude/projects/, so the frozen figure is "
            "the only surviving record:"
        )
        for session_id in lost:
            print(f"  {session_id}")
        print(
            f"  recorded total ${prior_total:.4f} left untouched. Transcripts expire; "
            "re-capture a feature only while they still exist. Pass --force to "
            "overwrite anyway."
        )
        for warning in warnings:
            print(f"WARN: {warning}")
        return "refused"

    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    cost_str = "cost unavailable — see warnings" if total_is_partial else f"${total_cost:.4f}"
    print(
        f"{slug}: {len(sessions)} sessions matched, "
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
    add_self_flag(parser)
    args = parser.parse_args()

    if args.all_features == bool(args.slug):
        parser.error("give either a feature slug or --all, not both and not neither")

    features_dir = features_root(args.self_mode)
    sessions_dir = session_root(args.self_mode)
    # Both corpora: `features_dir` says where to write, but a runner session on a
    # feature's branch may belong to a feature in the other tree.
    both_corpora = all_features_roots()
    # --force is the stronger ask of the two — it overwrites past the frozen-cost guard —
    # so it cannot be stopped by the skip that sits in front of that guard.
    recapture = args.recapture or args.force

    slugs = feature_slugs(features_dir) if args.all_features else [args.slug]

    counts = {"captured": 0, "skipped": 0, "refused": 0, "unreadable": 0}
    for slug in slugs:
        try:
            outcome = capture_feature(
                slug, features_dir, sessions_dir, both_corpora, recapture, args.force
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
            + (f", {counts['unreadable']} unreadable" if counts["unreadable"] else "")
        )

    if counts["refused"] or counts["unreadable"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
