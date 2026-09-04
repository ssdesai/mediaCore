"""Cross-feature cost and waste report.

Reads a feature's frozen cost figures and its plans' execution records and
writes the committed report: cost roll-up, waste metrics, and tripwires for
one feature, plus a `--all` cross-feature trend view.

No-recompute contract: this script must NOT call `compute_cost` or recompute
any dollar figure. Every cost number in the output comes from a `usage.json`'s
`total_cost_usd` or a `planning.json`'s `cost_usd`, summed or divided, never
repriced. `pricing.RATES_VERIFIED` / `pricing.is_rates_stale` are imported
only to footnote rate freshness in the rendered report — display only, never
used to compute a figure.

Plan drift is a best-effort heuristic: it extracts backtick-quoted paths from
under a plan's "## Files"-like heading and diffs them against the plan's
`files_edited`. It may false-positive — e.g. a README updated per
CONVENTIONS.md but not itemized in the plan's file list — so treat a hit as
something worth reading by hand, not a hard failure.

Usage:
    python3 agentTooling/analysis/report.py <slug>
    python3 agentTooling/analysis/report.py --all
"""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

from pricing import RATES_VERIFIED, is_rates_stale
from roots import add_self_flag, artifact_root, features_root
from transcript import to_utc

# Turn-count flags. The first two are model-fit — the plan ran on the wrong model.
# The third is scope: the model was right, the plan was too big.
HAIKU_HIGH_TURN_THRESHOLD = 8   # a haiku plan taking this many turns suggests it
                                # needed more judgment than haiku gives
SONNET_LOW_TURN_THRESHOLD = 3   # a sonnet plan finishing this fast suggests haiku
                                # would have sufficed
PLAN_HIGH_TURN_THRESHOLD = 60   # an executor is billed the sum of its context over
                                # every turn and context only grows, so cost is
                                # superlinear in turn count (AGENT_PLANS.md, "Sizing
                                # plans for executor cost"). A right-sized build plan
                                # lands near 30 turns; 2x that is where it could have
                                # been two plans, each still clearing the ~10-turn
                                # floor a split needs to repay its own cache-creation.

# Build plans only. Verify and review plans legitimately run long — they read
# unfamiliar output, or a whole diff, under a wider permission scope — so flagging them
# for turn count would be noise, and their runaway guard is the --max-budget-usd their
# own runners pass.
SCOPE_FLAG_QUEUES = ("auto",)

# Cross-plan edit overlap: minimum shared-substring length to count as a real
# region overlap rather than a trivial match (shared whitespace, a common import
# line). Below this, two plans touching the same file are not a finding — see
# AGENT_PLANS.md's frontend/src/App.tsx counter-example (plans 44/45, disjoint
# regions, zero interaction).
EDIT_OVERLAP_MIN_CHARS = 40

STATE_DIRS = {"incomplete", "inprogress", "complete", "failed"}
QUEUE_DIRS = {"auto", "verify", "review"}


# --------------------------------------------------------------------------
# Shared loading helpers
# --------------------------------------------------------------------------


def parse_manifest(readme_path):
    """Find the *last* ```json fence in a feature README and parse it. There
    may be earlier fences (examples, snippets) — only the last one is the
    manifest."""
    text = readme_path.read_text()
    matches = re.findall(r"```json\n(.*?)\n```", text, re.DOTALL)
    if not matches:
        raise ValueError(f"no ```json fence found in {readme_path}")
    return json.loads(matches[-1])


def build_usage_index(feature_dir):
    """{plan_stem: usage.json path}, keyed by each JSON's own "plan" field —
    never by filename position — since a plan's usage.json may sit under any
    queue/state dir, and archived batches nest one level deeper again.

    Scoped to a single feature, never the whole features/ tree. Plan numbers
    restart per feature (AGENT_PLANS.md: "Because numbers now repeat across
    features, qualify any cross-feature reference with the slug"), so stems
    like "05-tests-sonnet" and "06-verify-sonnet" recur in several features at
    once. A tree-wide index collapses those to whichever file rglob reached
    last, and every table downstream would then price another feature's plan
    with no warning. Scoping makes the collision unreachable; a manifest plan
    with no usage.json under its own feature dir is a visible warning from
    load_manifest_plans instead."""
    index = {}
    for usage_path in feature_dir.rglob("*.usage.json"):
        try:
            data = json.loads(usage_path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        plan_stem = data.get("plan")
        if plan_stem:
            index[plan_stem] = usage_path
    return index


# A plan the runner filed WITHOUT running it. `skip_level_verify` (plan-runner-lib.sh)
# does this when a level's gate came back green: the level-verify is not owed, so the
# plan moves to verify/complete/ with a one-line progress log and — deliberately — no
# usage.json, because nothing ran and nothing was billed. The log's first line is the
# only marker, and `self/tests/level-sentinel.sh` asserts the runner writes it.
SKIPPED_LOG_PREFIX = "skipped:"
PROGRESS_LOG_SUFFIX = ".progress.md"


def build_skipped_index(feature_dir):
    """The set of plan stems whose progress log says the runner skipped them.

    Scoped to one feature and keyed by the log's filename, the same way
    build_usage_index is keyed by the sidecar's own `plan` field: a progress log has no
    body to read a stem out of, but it always sits beside the plan it belongs to and
    plan numbers restart per feature.

    Without this, a skipped level-verify reads exactly like a plan whose usage.json is
    gone — reported under "Missing usage for" and marking the feature's total a lower
    bound, when in fact the roll-up is complete and the plan cost nothing. Seen on
    vinylCatalogue's shell-jobs-and-review-refresh, plan 05-level-backend."""
    skipped = set()
    for log_path in feature_dir.rglob("*" + PROGRESS_LOG_SUFFIX):
        try:
            with open(log_path) as handle:
                first_line = handle.readline()
        except OSError:
            continue
        if first_line.lstrip().startswith(SKIPPED_LOG_PREFIX):
            skipped.add(log_path.name[: -len(PROGRESS_LOG_SUFFIX)])
    return skipped


def find_queue_segment(usage_path):
    """The <queue> path segment (must be "auto", "verify" or "review") two levels above
    the state dir, i.e. plans/features/<slug>/<queue>/<state>/<stem>.usage.json
    — handles archived batches nested one level deeper under complete/<branch>/.
    Returns None if the path doesn't match that shape."""
    state_dir = usage_path.parent
    while state_dir.name not in STATE_DIRS:
        if state_dir == state_dir.parent:
            return None
        state_dir = state_dir.parent
    queue_dir = state_dir.parent
    return queue_dir.name if queue_dir.name in QUEUE_DIRS else None


def to_repo_relative(abs_path, repo_dir):
    """Absolute tool-call path -> path relative to REPO_DIR, POSIX-separated.

    A path outside REPO_DIR (e.g. a scratch file under /tmp written while driving a
    GUI check) is left as the raw path given, unchanged — matching `backfill_usage.py`
    and the runner's own jq `ltrimstr($repo)` (plan-runner-lib.sh), which only strips
    the prefix when it matches and otherwise passes the string through. Without this
    fallback an agent that touched one /tmp file aborts the whole report.
    """
    resolved = Path(abs_path).resolve()
    try:
        return resolved.relative_to(repo_dir).as_posix()
    except ValueError:
        return abs_path


def load_stream_events(stream_path):
    """Parse each non-blank line as JSON, skipping (not raising on) a line
    that fails to parse — a truncated final line from a killed process is
    possible."""
    events = []
    with open(stream_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def numeric_prefix(stem):
    """Leading digit run of a plan stem, e.g. "56-analysis-report-sonnet" ->
    56, used to sort manifest plans into batch order."""
    match = re.match(r"^(\d+)", stem)
    return int(match.group(1)) if match else 0


ESCALATION_STEM = re.compile(r"^\d+-escalation-[a-z]+$")


def manifest_plan_stems(manifest, usage_index, warnings):
    """`(stems, recovered)` — the manifest's `plans` array, or, when it has none,
    the stems that actually ran, recovered from the usage index in batch order.

    `plans` is required by `plans/features/TEMPLATE.md`, but the template omitted it
    for long enough that manifests written from it lack the key, and a bare
    `manifest["plans"]` subscript turned every such feature's cost report into a
    `KeyError` traceback with nothing in it to act on. Falling back keeps the report
    renderable and states what is wrong in a line the author can fix.

    The fallback is strictly weaker than the real array and must not read as
    equivalent. It is built *from* the usage index, so `find_orphan_usage` can find no
    orphans against it and `missing_usage` is empty by construction: a plan that ran is
    priced, a plan that never ran is invisible rather than reported. `recovered` is what
    the caller uses to mark the roll-up partial anyway.
    """
    stems = manifest.get("plans")
    if stems is not None:
        stems = list(stems)
        # Harness-synthesized plans — NN-escalation-<model>, written by run-batch.sh's
        # tier ladder when a level stays red — cannot appear in a manifest authored
        # before the batch ran. They are still real spend on this feature, so they are
        # appended here (in batch order) rather than reported as orphans and excluded.
        synthesized = sorted(
            (stem for stem in usage_index if ESCALATION_STEM.match(stem) and stem not in stems),
            key=numeric_prefix,
        )
        if synthesized:
            warnings.append(
                "harness-synthesized escalation plan(s) rolled in without a manifest "
                f"entry: {', '.join(synthesized)}"
            )
        return stems + synthesized, False
    order = sorted(usage_index, key=numeric_prefix)
    warnings.append(
        "manifest has no `plans` array; falling back to the "
        f"{len(order)} plan(s) that left a usage.json "
        f"({', '.join(order) or 'none'}). A plan that never ran cannot be detected "
        "this way, so the roll-up is a lower bound — add the array to the manifest's "
        "json fence"
    )
    return order, True


def load_manifest_plans(repo_dir, plan_stems, usage_index, warnings, skipped_stems=()):
    """(stem, usage_data, usage_path) triples for every plan in `plan_stems` that
    has a usage.json. A plan with none is a warning, not a crash, and is
    skipped from every downstream table.

    A stem in `skipped_stems` (build_skipped_index) is the one absence that is not a
    gap: the runner filed it without running it, so there is nothing to load and
    nothing missing. It gets a note rather than the missing-usage warning, and the
    caller keeps it out of `missing_usage_plans` and the partial flag."""
    loaded = []
    for stem in plan_stems:
        usage_path = usage_index.get(stem)
        if usage_path is None:
            if stem in skipped_stems:
                warnings.append(
                    f"plan {stem} was filed as skipped by the runner (its level gate was "
                    "green); it never ran, so it has no usage.json by design"
                )
            else:
                warnings.append(f"no usage.json for plan {stem}")
            continue
        usage_data = json.loads(usage_path.read_text())
        loaded.append((stem, usage_data, usage_path))
    return loaded


def find_orphan_usage(plan_stems, usage_index, warnings):
    """Plan stems that RAN — they have a usage.json under this feature — but are
    absent from the manifest's `plans` array.

    The mirror of load_manifest_plans' warning, and the more dangerous direction of
    the two. The runners are directory-driven: they drain
    `<queue>/incomplete/` and never read the manifest, so a plan authored into a
    queue but left out of `plans` executes, bills, and writes its usage.json
    exactly like any other — while every table here, which walks the manifest,
    behaves as though it never existed. Nothing else in the pipeline would notice:
    the cost is simply lower than the truth.

    That is not hypothetical. This corpus already contains an aborted plan attempt
    that wrote no code and still cost $2.95; a run detached from its manifest entry
    is the same money with nothing pointing at it. Adding a third queue widened the
    chance of the omission, which is what made a documentation-only rule
    insufficient.

    Finds nothing when `plan_stems` came from `manifest_plan_stems`' fallback — that
    list *is* the usage index — which is why the fallback marks the roll-up partial on
    its own rather than relying on this."""
    orphans = sorted(set(usage_index) - set(plan_stems))
    for stem in orphans:
        warnings.append(
            f"usage.json for {stem} exists but the manifest does not list it in "
            "`plans` — its cost is EXCLUDED from this roll-up; add the stem and re-run"
        )
    return orphans


# --------------------------------------------------------------------------
# Cost roll-up and cold-start tax
# --------------------------------------------------------------------------


KNOWN_METHODS = ("plans", "direct", "hand")
# The methods whose planning.json IS the build: no architect, so every transcript it
# holds is the implementer (direct) or the coordinator building it itself (hand).
BUILD_BY_TRANSCRIPT_METHODS = ("direct", "hand")
BUILD_ROW_LABELS = {"direct": "build: implementer", "hand": "build: by hand"}


def manifest_method(manifest, warnings):
    """How the feature was built, from the manifest's optional `method`: "plans" (the
    default, and every manifest written before the field existed), "direct"
    (AGENT_DIRECT.md: an implementer delegate) or "hand" (LIFECYCLE.md: the
    coordinator built it itself, no delegate). An unknown value is reported and read as
    "plans" rather than silently changing what a dollar means."""
    method = manifest.get("method") or "plans"
    if method not in KNOWN_METHODS:
        warnings.append(
            f"manifest method {method!r} is not one of {', '.join(KNOWN_METHODS)}; "
            "read as 'plans'"
        )
        return "plans"
    return method


def compute_cost_rollup(
    plan_stems, plans_recovered, planning_data, loaded_plans, warnings, orphan_plans=(),
    method="plans", skipped_plans=(),
):
    # For a planned feature, planning.json is what it says: the architect and the
    # sessions around it. For a direct feature there is no architect — the transcripts
    # it holds ARE the build (the implementer, a rework one-shot), so the whole figure
    # moves to the build bucket and planning proper (the coordinator's few minutes on
    # the brief) is not separated out. Same rule for time, in compute_time_rollup.
    implementer_cost = 0.0
    planning_cost = planning_data["cost_usd"]["total"]
    if method in BUILD_BY_TRANSCRIPT_METHODS:
        implementer_cost = planning_cost
        planning_cost = 0.0

    build_cost = implementer_cost
    verify_cost = 0.0
    review_cost = 0.0
    recovered_cost = 0.0
    priced_without_cost = []
    unrecoverable_attempts = []
    partially_recovered_attempts = []
    for stem, usage_data, usage_path in loaded_plans:
        cost = usage_data.get("total_cost_usd")
        # The durable figure is attempts[]'s own recovered_cost_usd values, not the
        # top-level recovered_cost_usd key: write_usage_sidecar (plan-runner-lib.sh)
        # rebuilds the sidecar from a fixed key set on any later write to a resumed
        # plan, dropping the top-level key while the attempt-level fields survive.
        # The top-level key is kept only as a cross-check below.
        attempts = usage_data.get("attempts") or []
        plan_recovered = sum(
            a["recovered_cost_usd"] for a in attempts if a.get("recovered_cost_usd") is not None
        )
        top_level_recovered = usage_data.get("recovered_cost_usd")
        if top_level_recovered is not None and abs(top_level_recovered - plan_recovered) > 0.01:
            warnings.append(
                f"plan {stem} has a top-level recovered_cost_usd (${top_level_recovered:.4f}) "
                f"that disagrees with the sum over attempts[] (${plan_recovered:.4f}); the "
                "sidecar was likely rewritten after recovery ran — using the attempts[] "
                "sum. Re-run recover_attempts.py --force to rebuild both from the "
                "transcripts; a plain re-run skips already-recovered attempts and leaves "
                "the top-level figure stale"
            )
        if cost is None and not plan_recovered:
            priced_without_cost.append(stem)
            warnings.append(
                f"plan {stem} has no total_cost_usd; excluded from cost roll-up"
            )
            continue
        # `total_cost_usd` sums attempts[], so a resumed plan whose earlier attempt was
        # killed before writing a result event contributes real spend that no attempt
        # record priced. Each such attempt now falls into one of three buckets:
        # recovered (recover_attempts.py priced it whole from the session transcript —
        # folded into plan_recovered above, so the total for this attempt is whole),
        # partially recovered (priced, but at least one model in the transcript had no
        # rate — plan_recovered is a genuine lower bound for this attempt), or
        # unrecoverable (the transcript itself is gone — no figure exists for it at
        # all).
        recovered_sessions = []
        partially_recovered_sessions = []
        unrecoverable_sessions = []
        for a in attempts:
            if a.get("total_cost_usd") is not None:
                continue
            if a.get("recovered_cost_usd") is None:
                unrecoverable_sessions.append(a.get("session_id"))
            elif a.get("recovered_is_partial"):
                partially_recovered_sessions.append(a.get("session_id"))
            else:
                recovered_sessions.append(a.get("session_id"))
        if unrecoverable_sessions:
            priced_without_cost.append(stem)
            for session_id in unrecoverable_sessions:
                unrecoverable_attempts.append({"plan": stem, "session_id": session_id})
            warnings.append(
                f"plan {stem} has {len(unrecoverable_sessions)} attempt(s) with no "
                "recorded or recovered cost (sessions: "
                f"{', '.join(str(s) for s in unrecoverable_sessions)}); its total is "
                "a lower bound"
            )
        if partially_recovered_sessions:
            for session_id in partially_recovered_sessions:
                partially_recovered_attempts.append({"plan": stem, "session_id": session_id})
            warnings.append(
                f"plan {stem} has {len(partially_recovered_sessions)} attempt(s) recovered "
                "with at least one model absent from pricing.RATES (sessions: "
                f"{', '.join(str(s) for s in partially_recovered_sessions)}); its recovered "
                "dollars cover only the priced portion"
            )
        if recovered_sessions:
            warnings.append(
                f"plan {stem} has {len(recovered_sessions)} attempt(s) priced from "
                "session transcripts rather than reported by the CLI (sessions: "
                f"{', '.join(str(s) for s in recovered_sessions)})"
            )
        queue = find_queue_segment(usage_path)
        queue_total = (cost or 0.0) + plan_recovered
        if queue == "auto":
            build_cost += queue_total
        elif queue == "verify":
            verify_cost += queue_total
        elif queue == "review":
            review_cost += queue_total
        recovered_cost += plan_recovered

    total_cost = planning_cost + build_cost + verify_cost + review_cost

    # A roll-up missing an input is still a number, and reads as a complete one unless
    # it says otherwise — the warning alone is not enough, since the trend table shows
    # totals without warnings. Mirrors planning.json's `total_is_partial`.
    loaded_stems = {stem for stem, _, _ in loaded_plans}
    # A plan the runner filed as skipped has no usage.json and no cost, and is neither
    # an absence nor a gap — excluded from `missing_usage` so it cannot mark the total
    # a lower bound, and listed separately so the reader can see why it is not counted.
    skipped_usage = [s for s in plan_stems if s not in loaded_stems and s in skipped_plans]
    missing_usage = [
        s for s in plan_stems if s not in loaded_stems and s not in skipped_plans
    ]
    # An orphan run makes the total too LOW rather than incomplete, which is the harder
    # error to spot — nothing is visibly absent. It marks the total partial for the same
    # reason missing_usage does: the trend table shows totals without warnings.
    # `plans_recovered` counts for the same reason: neither missing_usage nor
    # orphan_plans can speak when the plan list was recovered from the usage index.
    total_is_partial = bool(
        missing_usage
        or orphan_plans
        or plans_recovered
        or priced_without_cost
        or partially_recovered_attempts
        or planning_data["cost_usd"].get("total_is_partial")
    )

    def pct(part):
        return (part / total_cost * 100) if total_cost else 0.0

    plan_count = len(plan_stems)
    cost_per_plan = (total_cost / plan_count) if plan_count else 0.0

    all_files = set()
    for _, usage_data, _ in loaded_plans:
        all_files.update(usage_data.get("files_edited", []))
    cost_per_file = (total_cost / len(all_files)) if all_files else 0.0

    return {
        "method": method,
        "planning": planning_cost,
        "implementer": implementer_cost,
        "build": build_cost,
        "verify": verify_cost,
        "review": review_cost,
        "total": total_cost,
        "planning_pct": pct(planning_cost),
        "build_pct": pct(build_cost),
        "verify_pct": pct(verify_cost),
        "review_pct": pct(review_cost),
        "cost_per_plan": cost_per_plan,
        "cost_per_file": cost_per_file,
        "total_is_partial": total_is_partial,
        "missing_usage_plans": missing_usage,
        "skipped_plans": skipped_usage,
        "orphan_usage_plans": list(orphan_plans),
        "recovered": recovered_cost,
        "unrecoverable_attempts": unrecoverable_attempts,
        "partially_recovered_attempts": partially_recovered_attempts,
    }


def duration_from_usage(usage_data):
    """Seconds a plan's executors ran, summed over attempts[] — each a separate
    `claude -p` — falling back to the top-level duration_ms for a sidecar written
    before attempts[] existed. None when neither is present. Same source as the cost
    figure beside it (the CLI's own result event), so the two are comparable."""
    attempts = usage_data.get("attempts") or []
    per_attempt = [a.get("duration_ms") for a in attempts if a.get("duration_ms") is not None]
    if per_attempt:
        return sum(per_attempt) / 1000.0
    top_level = usage_data.get("duration_ms")
    return None if top_level is None else top_level / 1000.0


def load_timing_events(feature_dir, warnings):
    """The runner's wall-clock stamps (timing.jsonl, written by stamp_timing in
    plan-runner-roots.sh), parsed and sorted by instant. An absent file is the normal
    case for any feature that ran before stamping existed and yields []; a malformed
    line is skipped with a warning rather than failing the whole report."""
    path = feature_dir / "timing.jsonl"
    if not path.is_file():
        return []
    events = []
    for line_no, raw in enumerate(path.read_text().splitlines(), 1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            warnings.append(f"timing.jsonl line {line_no} is not JSON; skipped")
            continue
        at = to_utc(event.get("at"))
        if at is None:
            warnings.append(f"timing.jsonl line {line_no} has no parseable `at`; skipped")
            continue
        event["_at"] = at
        events.append(event)
    events.sort(key=lambda e: e["_at"])
    return events


def paired_seconds(events, start_name, end_name, key):
    """Sum of the spans between each `start_name` event and the next `end_name` event
    sharing the same `key` value, plus how many pairs closed. An unclosed start (a
    killed run) contributes nothing rather than a span to now."""
    open_starts = {}
    total = 0.0
    pairs = 0
    for event in events:
        name = event.get("event")
        k = event.get(key)
        if name == start_name:
            open_starts[k] = event["_at"]
        elif name == end_name and k in open_starts:
            total += (event["_at"] - open_starts.pop(k)).total_seconds()
            pairs += 1
    return total, pairs


def compute_wall_clock(events):
    """What the runner saw from outside the executors: the batch end to end, each
    pass, the gates, the plans as the runner timed them (so a parallel pair counts
    once per plan, same as the executor sum), and when the PR opened. None without
    stamps."""
    if not events:
        return None
    first = events[0]["_at"]
    last = events[-1]["_at"]
    batch_starts = [e["_at"] for e in events if e.get("event") == "batch_start"]
    batch_ends = [e["_at"] for e in events if e.get("event") == "batch_end"]
    pr_opened = [e for e in events if e.get("event") == "pr_opened"]
    pr_at = pr_opened[-1]["_at"] if pr_opened else None
    # A batch resumed after a stop has several start/end pairs; the honest single
    # figure is first start to last end (or to the PR, whichever is later), and the
    # sum of the closed pairs is reported beside it as the attended time.
    span_end = max([t for t in [*batch_ends, pr_at, last] if t is not None])
    span_start = batch_starts[0] if batch_starts else first
    batch_runs_s, batch_runs = paired_seconds(events, "batch_start", "batch_end", "_none")
    passes = {}
    for queue in ("auto", "verify", "review"):
        seconds, count = paired_seconds(
            [e for e in events if e.get("queue") == queue], "pass_start", "pass_end", "queue"
        )
        if count:
            passes[queue] = seconds
    gates_s, gate_runs = paired_seconds(events, "gate_start", "gate_end", "level")
    plans_s, plan_runs = paired_seconds(events, "plan_start", "plan_end", "plan")
    return {
        "first_at": first.isoformat(),
        "last_at": last.isoformat(),
        "batch_span_s": (span_end - span_start).total_seconds(),
        "batch_runs": batch_runs,
        "batch_runs_s": batch_runs_s,
        "passes_s": passes,
        "gates_s": gates_s,
        "gate_runs": gate_runs,
        "plans_s": plans_s,
        "plan_runs": plan_runs,
        "pr_opened_at": pr_at.isoformat() if pr_at else None,
        "pr_url": (pr_opened[-1].get("url") or None) if pr_opened else None,
    }


# A direct build's own milestones (AGENT_DIRECT.md -> "Checkpoint and resume"), stamped
# by the top-level stamp-timing.sh as `checkpoint` events carrying the checkpoint file's
# own `status`. A planned feature's passes are timed by the runners; a direct feature has
# no runner until review, so without these its whole build is one undivided span.
CHECKPOINT_EVENT = "checkpoint"
# (report.json key, opening status, closing status) — in render order.
CHECKPOINT_SPANS = (
    ("tests_s", "planned", "tests-written"),
    ("direct_build_s", "tests-written", "gating"),
    ("gate_s", "gating", "committed"),
)
CHECKPOINT_ROW_LABELS = {
    "tests_s": "\u21b3 acceptance tests",
    "direct_build_s": "\u21b3 implementation",
    "gate_s": "\u21b3 gate",
}


def compute_checkpoint_spans(events, warnings):
    """{key: seconds | None} for each span in CHECKPOINT_SPANS, or `{}` when the feature
    stamped no checkpoint at all — which is every feature built before stamp-timing.sh
    existed, and every planned one. An empty dict adds no keys to the roll-up, so such a
    report is unchanged.

    Each status is taken at its FIRST instant. The checkpoint file is rewritten whole at
    every milestone and a status can be re-stamped (a resumed implementer re-declares
    where it is); the first time a milestone was reached is what the span means.

    A missing endpoint yields None rather than an invented figure — a build killed
    before `committed`, or one whose implementer skipped a stamp, has no gate span, and
    a zero there would read as an instant gate."""
    first_at = {}
    for event in events:
        if event.get("event") != CHECKPOINT_EVENT:
            continue
        status = event.get("status")
        if status and status not in first_at:
            first_at[status] = event["_at"]
    if not first_at:
        return {}
    spans = {}
    for key, opening, closing in CHECKPOINT_SPANS:
        if opening not in first_at or closing not in first_at:
            spans[key] = None
            continue
        seconds = (first_at[closing] - first_at[opening]).total_seconds()
        if seconds < 0:
            warnings.append(
                f"checkpoint status {closing!r} was stamped before {opening!r}; "
                f"{key} is not derivable from timing.jsonl"
            )
            spans[key] = None
        else:
            spans[key] = seconds
    return spans


def compute_time_rollup(planning_data, loaded_plans, events, warnings, method="plans"):
    """The Cost table's twin: seconds per bucket from the same two sources the dollars
    come from — planning.json's `duration_s` (sessions and delegates kept apart, see
    capture_planning.duration_seconds for why) and each usage.json's attempts[] — plus
    the runner's wall clock from timing.jsonl where it exists. Executor time sums over
    plans, so two plans run in parallel count twice; `wall_clock` is the figure that
    does not."""
    planning = planning_data.get("duration_s") or {}
    planning_sessions = planning.get("sessions")
    planning_subagents = planning.get("subagents")
    planning_known = planning_sessions is not None or planning_subagents is not None
    if not planning_known:
        warnings.append(
            "planning.json carries no duration_s — captured before timing existed; "
            "re-capture (capture_planning.py --recapture <slug>) while the transcripts "
            "survive to fill it in"
        )
    build_s = verify_s = review_s = 0.0
    missing = []
    for stem, usage_data, usage_path in loaded_plans:
        seconds = duration_from_usage(usage_data)
        if seconds is None:
            missing.append(stem)
            continue
        queue = find_queue_segment(usage_path)
        if queue == "auto":
            build_s += seconds
        elif queue == "verify":
            verify_s += seconds
        elif queue == "review":
            review_s += seconds
    if missing:
        warnings.append(
            f"no duration_ms for plan(s) {', '.join(missing)}; excluded from the time roll-up"
        )
    planning_total = (planning_sessions or 0) + (planning_subagents or 0)
    # Mirrors compute_cost_rollup: a direct feature's transcript spans are its build.
    implementer_s = None
    checkpoint_spans = {}
    if method in BUILD_BY_TRANSCRIPT_METHODS:
        implementer_s = planning_total if planning_known else None
        build_s += planning_total
        planning_total = 0.0
        # Only for a direct feature: the spans subdivide the implementer's transcript,
        # and a planned feature has no implementer row for them to sit under. A stray
        # checkpoint event on a planned feature is therefore ignored, not rendered.
        checkpoint_spans = compute_checkpoint_spans(events, warnings)
    executor_total = build_s + verify_s + review_s
    rollup = {
        "method": method,
        "planning_sessions_s": planning_sessions,
        "planning_subagents_s": planning_subagents,
        "planning_s": planning_total if planning_known else None,
        "implementer_s": implementer_s,
        "build_s": build_s,
        "verify_s": verify_s,
        "review_s": review_s,
        "executor_s": executor_total,
        "total_s": planning_total + executor_total,
        "total_is_partial": bool(missing) or not planning_known,
        "missing_duration_plans": missing,
        "wall_clock": compute_wall_clock(events),
    }
    # Added only when the feature stamped checkpoints, so a report that has none is
    # byte-identical to what it was before these keys existed.
    rollup.update(checkpoint_spans)
    return rollup


def compute_cold_start_tax(loaded_plans):
    """Sum of the flat runner-level cache_creation_input_tokens field across
    every loaded usage.json — this is about build/verify fanout, not
    planning, so it deliberately does not touch planning.json."""
    return sum(
        (usage_data.get("usage") or {}).get("cache_creation_input_tokens", 0)
        for _, usage_data, _ in loaded_plans
    )


# --------------------------------------------------------------------------
# Model fit and churn
# --------------------------------------------------------------------------


def compute_model_fit(loaded_plans):
    groups = {}
    for stem, usage_data, usage_path in loaded_plans:
        model = usage_data.get("model")
        groups.setdefault(model, []).append(
            (stem, usage_data, find_queue_segment(usage_path))
        )

    model_fit = []
    for model in sorted(groups.keys()):
        members = groups[model]
        plan_count = len(members)
        total_turns = sum((u.get("num_turns") or 0) for _, u, _ in members)
        costs = [u.get("total_cost_usd") for _, u, _ in members]
        total_cost_usd = None if any(c is None for c in costs) else sum(costs)
        durations = [duration_from_usage(u) for _, u, _ in members]
        total_duration_s = None if any(d is None for d in durations) else sum(durations)

        model_lower = (model or "").lower()
        flags = []
        for stem, u, queue in members:
            num_turns = u.get("num_turns")
            if num_turns is None:
                continue
            if "haiku" in model_lower and num_turns > HAIKU_HIGH_TURN_THRESHOLD:
                flags.append(
                    f"plan {stem} took {num_turns} turns on haiku "
                    f"(> {HAIKU_HIGH_TURN_THRESHOLD}, may have needed more "
                    "judgment than haiku gives)"
                )
            if "sonnet" in model_lower and num_turns < SONNET_LOW_TURN_THRESHOLD:
                flags.append(
                    f"plan {stem} finished in {num_turns} turns on sonnet "
                    f"(< {SONNET_LOW_TURN_THRESHOLD}, haiku may have sufficed)"
                )
            if (
                queue in SCOPE_FLAG_QUEUES
                and num_turns > PLAN_HIGH_TURN_THRESHOLD
            ):
                flags.append(
                    f"plan {stem} took {num_turns} turns "
                    f"(> {PLAN_HIGH_TURN_THRESHOLD}); scope, not model — "
                    "split it next time (AGENT_PLANS.md, 'Sizing plans for "
                    "executor cost')"
                )

        model_fit.append(
            {
                "model": model,
                "plan_count": plan_count,
                "total_turns": total_turns,
                "total_cost_usd": total_cost_usd,
                "total_duration_s": total_duration_s,
                "flags": flags,
            }
        )
    return model_fit


def compute_churn(loaded_plans, warnings):
    churn = []
    for stem, usage_data, _ in loaded_plans:
        edit_count = usage_data.get("edit_count", 0)
        files_edited = len(usage_data.get("files_edited", []))
        if files_edited == 0:
            warnings.append(
                f"plan {stem} has 0 files_edited; excluded from churn ratio"
            )
            continue
        churn.append(
            {
                "plan": stem,
                "edit_count": edit_count,
                "files_edited": files_edited,
                "churn_ratio": edit_count / files_edited,
            }
        )
    return churn


# --------------------------------------------------------------------------
# Plan length vs LoC changed
# --------------------------------------------------------------------------


def compute_loc_changed(stream_path):
    total = 0
    for event in load_stream_events(stream_path):
        if event.get("type") != "assistant":
            continue
        content = event.get("message", {}).get("content", [])
        for block in content:
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            inp = block.get("input") or {}
            if name == "Edit":
                old_lines = len((inp.get("old_string") or "").splitlines())
                new_lines = len((inp.get("new_string") or "").splitlines())
                total += max(old_lines, new_lines)
            elif name == "Write":
                total += len((inp.get("content") or "").splitlines())
    return total


def compute_plan_length_vs_loc(loaded_plans):
    rows = []
    for stem, usage_data, usage_path in loaded_plans:
        md_path = usage_path.with_name(f"{stem}.md")
        plan_md_lines = len(md_path.read_text().splitlines())
        stream_path = usage_path.with_name(f"{stem}.stream.jsonl")
        if stream_path.exists():
            loc_changed = compute_loc_changed(stream_path)
        else:
            loc_changed = "not computed: streams unavailable"
        rows.append(
            {
                "plan": stem,
                "plan_md_lines": plan_md_lines,
                "loc_changed": loc_changed,
            }
        )
    return rows


# --------------------------------------------------------------------------
# Re-hunting
# --------------------------------------------------------------------------


def collect_search_targets(stream_path):
    """[(tool, target)] for every Grep/Glob/Read tool_use block in a stream —
    target is the search pattern for Grep/Glob, the file path for Read."""
    targets = []
    for event in load_stream_events(stream_path):
        if event.get("type") != "assistant":
            continue
        content = event.get("message", {}).get("content", [])
        for block in content:
            if block.get("type") != "tool_use":
                continue
            name = block.get("name")
            if name not in {"Grep", "Glob", "Read"}:
                continue
            inp = block.get("input") or {}
            target = inp.get("pattern") if name in {"Grep", "Glob"} else inp.get("file_path")
            if target:
                targets.append((name, target))
    return targets


def compute_re_hunting(loaded_plans, warnings):
    plans_with_stream = []
    skipped = []
    for stem, _, usage_path in loaded_plans:
        stream_path = usage_path.with_name(f"{stem}.stream.jsonl")
        if stream_path.exists():
            plans_with_stream.append((stem, stream_path))
        else:
            skipped.append(stem)

    if not plans_with_stream:
        return "not computed: streams unavailable"

    if skipped:
        warnings.append(
            "re-hunting computed without streams for: " + ", ".join(skipped)
        )

    target_map = {}
    for stem, stream_path in plans_with_stream:
        for tool, target in collect_search_targets(stream_path):
            target_map.setdefault((tool, target), set()).add(stem)

    return [
        {"target": target, "tool": tool, "plans": sorted(stems)}
        for (tool, target), stems in sorted(target_map.items())
        if len(stems) >= 2
    ]


# --------------------------------------------------------------------------
# Plan drift
# --------------------------------------------------------------------------


def normalize_listed_path(span):
    span = span.strip()
    if span.startswith("./"):
        span = span[2:]
    return span.lstrip("/")


def extract_listed_files(md_text):
    """Backtick-quoted, path-shaped spans under a "## Files"-style heading
    (leniently: any ## heading whose text contains "file"), collected until
    the next ## heading of any kind."""
    listed = set()
    in_section = False
    for line in md_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("##"):
            if in_section:
                break
            if "file" in stripped.lower():
                in_section = True
            continue
        if in_section:
            for span in re.findall(r"`([^`]+)`", line):
                if "/" in span or re.search(r"\.[A-Za-z0-9]+$", span):
                    listed.add(normalize_listed_path(span))
    return listed


def compute_plan_drift(loaded_plans):
    drift = []
    for stem, usage_data, usage_path in loaded_plans:
        md_path = usage_path.with_name(f"{stem}.md")
        listed = extract_listed_files(md_path.read_text())
        edited = set(usage_data.get("files_edited", []))
        edited_not_listed = sorted(edited - listed)
        listed_not_edited = sorted(listed - edited)
        if edited_not_listed or listed_not_edited:
            drift.append(
                {
                    "plan": stem,
                    "edited_not_listed": edited_not_listed,
                    "listed_not_edited": listed_not_edited,
                }
            )
    return drift


# --------------------------------------------------------------------------
# Cross-plan edit overlap
# --------------------------------------------------------------------------


def shared_substring_len(text_a, text_b):
    """Simple substring containment check in either direction — not a full
    LCS. Returns the length of the contained text when one fully contains
    the other and that length meets EDIT_OVERLAP_MIN_CHARS, else 0."""
    if text_a and len(text_a) >= EDIT_OVERLAP_MIN_CHARS and text_a in text_b:
        return len(text_a)
    if text_b and len(text_b) >= EDIT_OVERLAP_MIN_CHARS and text_b in text_a:
        return len(text_b)
    return 0


def compute_edit_overlap(loaded_plans, repo_dir, warnings):
    ordered = sorted(loaded_plans, key=lambda p: numeric_prefix(p[0]))

    plans_with_stream = []
    skipped = []
    for stem, _, usage_path in ordered:
        stream_path = usage_path.with_name(f"{stem}.stream.jsonl")
        if stream_path.exists():
            plans_with_stream.append((stem, stream_path))
        else:
            skipped.append(stem)

    if not plans_with_stream:
        return "not computed: streams unavailable"

    if skipped:
        warnings.append(
            "edit overlap computed without streams for: " + ", ".join(skipped)
        )

    overlaps = []
    file_history = {}  # repo-relative path -> [(plan_stem, text written)]
    for stem, stream_path in plans_with_stream:
        for event in load_stream_events(stream_path):
            if event.get("type") != "assistant":
                continue
            content = event.get("message", {}).get("content", [])
            for block in content:
                if block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                if name not in {"Edit", "Write"}:
                    continue
                inp = block.get("input") or {}
                file_path = inp.get("file_path")
                if not file_path:
                    continue
                rel_path = to_repo_relative(file_path, repo_dir)
                history = file_history.setdefault(rel_path, [])
                if name == "Edit":
                    old_string = inp.get("old_string") or ""
                    new_string = inp.get("new_string") or ""
                    for earlier_stem, earlier_text in history:
                        overlap_chars = shared_substring_len(old_string, earlier_text)
                        if overlap_chars:
                            overlaps.append(
                                {
                                    "file": rel_path,
                                    "earlier_plan": earlier_stem,
                                    "later_plan": stem,
                                    "overlap_chars": overlap_chars,
                                }
                            )
                    history.append((stem, new_string))
                else:
                    history.append((stem, inp.get("content") or ""))

    return overlaps


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def minutes_cell(seconds):
    return "n/a" if seconds is None else f"{seconds / 60:.1f}"


def per_minute_cell(usd, seconds):
    if usd is None or not seconds:
        return ""
    return f"${usd / (seconds / 60):.4f}"


def render_time_section(lines, data):
    """The Cost table's twin, row for row, so a reader can put a bucket's dollars
    beside its minutes. Written to tolerate a report.json that predates the `time`
    key (`--all` and re-renders of old features) by rendering nothing."""
    time = data.get("time")
    if not time:
        return
    cost = data["cost"]
    planning_cost = data.get("planning_cost_split") or {}
    lines.append("## Time")
    lines.append("")
    lines.append("| bucket | minutes | usd | usd per minute |")
    lines.append("|---|---|---|---|")
    if time.get("method") in BUILD_BY_TRANSCRIPT_METHODS:
        rows = [(BUILD_ROW_LABELS[time["method"]], time.get("implementer_s"), cost.get("implementer"))]
        # The implementer's own milestones, indented under the row they subdivide. No
        # dollars: the transcript is priced as one span and nothing splits its cost the
        # way the instants split its minutes. Absent when the build stamped none.
        for key, _, _ in CHECKPOINT_SPANS:
            seconds = time.get(key)
            if seconds is not None:
                rows.append((CHECKPOINT_ROW_LABELS[key], seconds, None))
        rows += [
            ("verify", time.get("verify_s"), cost.get("verify")),
            ("review", time.get("review_s"), cost.get("review", 0.0)),
        ]
    else:
        rows = [
            ("planning: sessions", time.get("planning_sessions_s"), planning_cost.get("sessions")),
            ("planning: delegates", time.get("planning_subagents_s"), planning_cost.get("subagents")),
            ("build", time.get("build_s"), cost.get("build")),
            ("verify", time.get("verify_s"), cost.get("verify")),
            ("review", time.get("review_s"), cost.get("review", 0.0)),
        ]
    for label, seconds, usd in rows:
        usd_cell = "" if usd is None else f"${usd:.4f}"
        lines.append(
            f"| {label} | {minutes_cell(seconds)} | {usd_cell} | {per_minute_cell(usd, seconds)} |"
        )
    total_marker = " (partial)" if time.get("total_is_partial") else ""
    # No rate on a partial total: the dollars would be whole and the minutes not, and
    # the quotient would read as a real figure.
    total_rate = "" if time.get("total_is_partial") else per_minute_cell(cost["total"], time.get("total_s"))
    lines.append(
        f"| **total** | **{minutes_cell(time.get('total_s'))}**{total_marker} "
        f"| **${cost['total']:.4f}** | {total_rate} |"
    )
    lines.append("")
    if time.get("method") in BUILD_BY_TRANSCRIPT_METHODS:
        who = "The implementer's" if time["method"] == "direct" else "The build's"
        note = (
            f"{who} minutes are its transcript span — its working time, since "
            "a delegate runs start to finish. Verify and review minutes are summed over "
            "plans; the wall clock below is the review runner's own record."
        )
        if any(time.get(key) is not None for key, _, _ in CHECKPOINT_SPANS):
            note += (
                " The indented rows split that span at the implementer's own checkpoint "
                "milestones (`stamp-timing.sh <slug> checkpoint status=…`), so they carry "
                "minutes and no separate dollars."
            )
        lines.append(note)
    else:
        lines.append(
            "Planning minutes are transcript spans: a delegate's span is its working time, "
            "a session's includes every minute nobody was typing, so the delegates row is "
            "the planning figure for a feature planned by delegates and the sessions row "
            "for one planned by hand. Build, verify and review minutes are summed over "
            "plans, so a parallel pair counts twice — the wall clock below does not."
        )
    lines.append("")
    if time.get("total_is_partial"):
        missing = time.get("missing_duration_plans") or []
        detail = f" Missing durations for: {', '.join(missing)}." if missing else ""
        lines.append(
            f"**This total is a lower bound** — at least one time input is unavailable."
            f"{detail}"
        )
        lines.append("")
    wall = time.get("wall_clock")
    if wall:
        passes = wall.get("passes_s") or {}
        pass_parts = ", ".join(
            f"{name} {seconds / 60:.1f}"
            for name, seconds in (("build", passes.get("auto")), ("verify", passes.get("verify")), ("review", passes.get("review")))
            if seconds is not None
        )
        lines.append(
            f"Wall clock, as the runner saw it: **{wall['batch_span_s'] / 60:.1f} min** from "
            f"{wall['first_at']} to {wall['last_at']}"
            + (f", PR opened {wall['pr_opened_at']}" if wall.get("pr_opened_at") else "")
            + "."
        )
        lines.append(
            f"Passes: {pass_parts or 'none stamped'}. "
            f"Gates: {wall['gates_s'] / 60:.1f} min over {wall['gate_runs']} run(s). "
            f"Plans as timed by the runner: {wall['plans_s'] / 60:.1f} min over {wall['plan_runs']} run(s)."
            + (
                f" Attended in {wall['batch_runs']} batch run(s) totalling {wall['batch_runs_s'] / 60:.1f} min."
                if wall.get("batch_runs", 0) > 1
                else ""
            )
        )
    else:
        lines.append(
            "No wall clock: this feature has no `timing.jsonl`, so its batch ran on a "
            "runner that predates stamping. Only the executors' own durations are known."
        )
    lines.append("")


def render_report_md(data):
    lines = [f"# {data['slug']} — cost and waste report", ""]
    lines.append(f"Generated {data['generated_at']}.")
    lines.append("")

    cost = data["cost"]
    lines.append("## Cost")
    lines.append("")
    lines.append("| bucket | usd | % of total |")
    lines.append("|---|---|---|")
    lines.append(f"| planning | ${cost['planning']:.4f} | {cost['planning_pct']:.1f}% |")
    lines.append(f"| build | ${cost['build']:.4f} | {cost['build_pct']:.1f}% |")
    lines.append(f"| verify | ${cost['verify']:.4f} | {cost['verify_pct']:.1f}% |")
    lines.append(
        f"| review | ${cost.get('review', 0.0):.4f} | {cost.get('review_pct', 0.0):.1f}% |"
    )
    total_marker = " (partial)" if cost.get("total_is_partial") else ""
    lines.append(f"| **total** | **${cost['total']:.4f}**{total_marker} | 100.0% |")
    lines.append("")
    if cost.get("method") in BUILD_BY_TRANSCRIPT_METHODS:
        if cost["method"] == "direct":
            how = "Built direct (`AGENT_DIRECT.md`): build is the implementer's transcript(s), "
        else:
            how = "Built by hand (`LIFECYCLE.md`): build is the building session's transcript(s), "
        lines.append(
            how
            + f"${cost.get('implementer', 0.0):.4f}, read from `planning.json`; there are no "
            "build plans, and the coordinator's minutes on the brief are not separated "
            "from it."
        )
        lines.append("")
    skipped = cost.get("skipped_plans") or []
    if skipped:
        # Deliberately outside the partial block below: a skipped plan is not an absence,
        # so a feature whose only unloaded plan was skipped has a whole total and would
        # otherwise print nothing explaining why that plan carries no cost.
        lines.append(
            f"**Skipped, not missing:** {', '.join(skipped)}. The runner filed each "
            f"without running it — its level gate was already green — so there is no "
            f"`usage.json` and no cost to roll up."
        )
        lines.append("")
    if cost.get("total_is_partial"):
        missing = cost.get("missing_usage_plans") or []
        detail = f" Missing usage for: {', '.join(missing)}." if missing else ""
        lines.append(
            f"**This total is a lower bound** — at least one input is unavailable, so the "
            f"real cost is higher and the percentages are skewed toward whatever survived."
            f"{detail}"
        )
        lines.append("")
        orphans = cost.get("orphan_usage_plans") or []
        if orphans:
            # Called out separately from `missing`: that one says an input is absent,
            # this one says an input RAN and was excluded because the manifest never
            # listed it. The fix is an edit to the manifest, not a re-run.
            lines.append(
                f"**Excluded, though they ran:** {', '.join(orphans)}. Each has a "
                f"`usage.json` under this feature but no entry in the manifest's "
                f"`plans` array, so its cost is missing from every figure above. Add "
                f"the stems and regenerate."
            )
            lines.append("")
        unrecoverable = cost.get("unrecoverable_attempts") or []
        if unrecoverable:
            # These, not the orphans above, are what actually keeps this total a lower
            # bound — a killed attempt that carries no cost from either source, so no
            # figure exists for it anywhere in this report.
            detail = ", ".join(f"{u['plan']} ({u['session_id']})" for u in unrecoverable)
            lines.append(
                f"**Unpriced attempts:** {detail}. Each was killed before writing a "
                f"result event and carries no recovered cost either. Run "
                f"`recover_attempts.py` and regenerate: if the session transcript "
                f"survives it will be priced, and only if it has aged out is the cost "
                f"genuinely gone."
            )
            lines.append("")
        partial = cost.get("partially_recovered_attempts") or []
        if partial:
            # Distinct from unrecoverable above: these attempts DO carry a recovered
            # figure, just not a whole one — at least one model in the session's
            # transcript was absent from pricing.RATES, so its tokens are excluded
            # from recovered_cost_usd rather than coerced to a silent 0.
            detail = ", ".join(f"{p['plan']} ({p['session_id']})" for p in partial)
            lines.append(
                f"**Partially recovered attempts:** {detail}. Each was priced from its "
                f"session transcript but at least one model in it has no rate in "
                f"`pricing.RATES`; its recovered dollars cover only the priced "
                f"portion, so the total remains a lower bound."
            )
            lines.append("")
    lines.append(f"cost per plan: ${cost['cost_per_plan']:.4f}  ")
    lines.append(f"cost per file touched: ${cost['cost_per_file']:.4f}")
    lines.append("")
    recovered = cost.get("recovered", 0.0)
    if recovered:
        lines.append(
            f"${recovered:.4f} of the total above is **derived**, not measured — "
            "priced from session transcripts by recover_attempts.py for attempts "
            "the CLI itself never reported a cost for."
        )
        lines.append("")

    render_time_section(lines, data)

    lines.append("## Cold-start tax")
    lines.append("")
    lines.append(
        f"{data['cold_start_tax_tokens']} cache-creation tokens across build/verify/review plans."
    )
    lines.append("")

    lines.append("## Model fit")
    lines.append("")
    lines.append("| model | plan count | total turns | total cost usd | minutes | flags |")
    lines.append("|---|---|---|---|---|---|")
    for row in data["model_fit"]:
        cost_cell = "n/a" if row["total_cost_usd"] is None else f"${row['total_cost_usd']:.4f}"
        # `.get`: a report.json rendered before this column existed lacks the key.
        minutes = minutes_cell(row.get("total_duration_s"))
        flags_cell = "; ".join(row["flags"]) if row["flags"] else ""
        lines.append(
            f"| {row['model']} | {row['plan_count']} | {row['total_turns']} "
            f"| {cost_cell} | {minutes} | {flags_cell} |"
        )
    lines.append("")

    lines.append("## Churn")
    lines.append("")
    lines.append("| plan | edit count | files edited | churn ratio |")
    lines.append("|---|---|---|---|")
    for row in data["churn"]:
        lines.append(
            f"| {row['plan']} | {row['edit_count']} | {row['files_edited']} "
            f"| {row['churn_ratio']:.2f} |"
        )
    lines.append("")

    lines.append("## Plan length vs LoC changed")
    lines.append("")
    lines.append("| plan | plan.md lines | LoC changed |")
    lines.append("|---|---|---|")
    for row in data["plan_length_vs_loc"]:
        lines.append(f"| {row['plan']} | {row['plan_md_lines']} | {row['loc_changed']} |")
    lines.append("")

    lines.append("## Re-hunting")
    lines.append("")
    re_hunting = data["re_hunting"]
    if isinstance(re_hunting, str):
        lines.append(re_hunting)
    elif not re_hunting:
        lines.append("none found.")
    else:
        lines.append("| target | tool | plans |")
        lines.append("|---|---|---|")
        for row in re_hunting:
            lines.append(f"| `{row['target']}` | {row['tool']} | {', '.join(row['plans'])} |")
    lines.append("")

    lines.append("## Plan drift")
    lines.append("")
    plan_drift = data["plan_drift"]
    if not plan_drift:
        lines.append("none found.")
    else:
        lines.append("| plan | edited not listed | listed not edited |")
        lines.append("|---|---|---|")
        for row in plan_drift:
            lines.append(
                f"| {row['plan']} | {', '.join(row['edited_not_listed']) or '—'} "
                f"| {', '.join(row['listed_not_edited']) or '—'} |"
            )
    lines.append("")

    lines.append("## Cross-plan edit overlap")
    lines.append("")
    edit_overlap = data["edit_overlap"]
    if isinstance(edit_overlap, str):
        lines.append(edit_overlap)
    elif not edit_overlap:
        lines.append("none found.")
    else:
        lines.append("| file | earlier plan | later plan | overlap chars |")
        lines.append("|---|---|---|---|")
        for row in edit_overlap:
            lines.append(
                f"| {row['file']} | {row['earlier_plan']} | {row['later_plan']} "
                f"| {row['overlap_chars']} |"
            )
    lines.append("")

    if data["warnings"]:
        lines.append("## Warnings")
        lines.append("")
        for warning in data["warnings"]:
            lines.append(f"- {warning}")
        lines.append("")

    staleness = "stale" if is_rates_stale() else "fresh"
    lines.append(
        f"---\n\nRates last verified {RATES_VERIFIED} ({staleness} as of report "
        "generation). This footnote is display-only and does not affect any "
        "figure above."
    )
    lines.append("")

    return "\n".join(lines)


# --------------------------------------------------------------------------
# Modes
# --------------------------------------------------------------------------


def run_single_feature(repo_dir, features_dir, slug):
    warnings = []
    feature_dir = Path(features_dir, slug)
    manifest = parse_manifest(feature_dir / "README.md")
    method = manifest_method(manifest, warnings)

    planning_data = json.loads((feature_dir / "planning.json").read_text())

    usage_index = build_usage_index(feature_dir)
    skipped_stems = build_skipped_index(feature_dir)
    plan_stems, plans_recovered = manifest_plan_stems(manifest, usage_index, warnings)
    loaded_plans = load_manifest_plans(
        repo_dir, plan_stems, usage_index, warnings, skipped_stems=skipped_stems
    )
    orphan_plans = find_orphan_usage(plan_stems, usage_index, warnings)

    cost = compute_cost_rollup(
        plan_stems,
        plans_recovered,
        planning_data,
        loaded_plans,
        warnings,
        orphan_plans=orphan_plans,
        method=method,
        skipped_plans=skipped_stems,
    )
    timing_events = load_timing_events(feature_dir, warnings)
    time = compute_time_rollup(planning_data, loaded_plans, timing_events, warnings, method=method)
    # The planning dollars split the same way the planning minutes are: delegates'
    # transcripts versus the sessions' own turns (inline sidechains included), so the
    # Time table can put each row's cost beside it. Absent keys are old captures.
    planning_cost_usd = planning_data.get("cost_usd") or {}
    planning_cost_split = {
        "subagents": planning_cost_usd.get("subagents"),
        "sessions": (
            planning_cost_usd["total"] - (planning_cost_usd.get("subagents") or 0.0)
            if planning_cost_usd.get("total") is not None
            else None
        ),
    }
    cold_start_tax_tokens = compute_cold_start_tax(loaded_plans)
    model_fit = compute_model_fit(loaded_plans)
    churn = compute_churn(loaded_plans, warnings)
    plan_length_vs_loc = compute_plan_length_vs_loc(loaded_plans)
    re_hunting = compute_re_hunting(loaded_plans, warnings)
    plan_drift = compute_plan_drift(loaded_plans)
    edit_overlap = compute_edit_overlap(loaded_plans, repo_dir, warnings)

    data = {
        "slug": slug,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "cost": cost,
        "time": time,
        "planning_cost_split": planning_cost_split,
        "cold_start_tax_tokens": cold_start_tax_tokens,
        "model_fit": model_fit,
        "churn": churn,
        "plan_length_vs_loc": plan_length_vs_loc,
        "re_hunting": re_hunting,
        "plan_drift": plan_drift,
        "edit_overlap": edit_overlap,
        "warnings": warnings,
    }

    with open(feature_dir / "report.json", "w") as f:
        json.dump(data, f, indent=2)

    (feature_dir / "report.md").write_text(render_report_md(data))

    print(
        f"{slug}: total ${cost['total']:.4f} — "
        f"planning ${cost['planning']:.4f} ({cost['planning_pct']:.1f}%), "
        f"build ${cost['build']:.4f} ({cost['build_pct']:.1f}%), "
        f"verify ${cost['verify']:.4f} ({cost['verify_pct']:.1f}%), "
        f"review ${cost.get('review', 0.0):.4f} ({cost.get('review_pct', 0.0):.1f}%); "
        f"time {minutes_cell(time['total_s'])} min"
        + (" (partial)" if time["total_is_partial"] else "")
    )
    for warning in warnings:
        print(f"WARN: {warning}")


def run_trend_mode(features_dir):
    rows = []
    for report_path in sorted(features_dir.glob("*/report.json")):
        try:
            rows.append(json.loads(report_path.read_text()))
        except (OSError, json.JSONDecodeError):
            continue

    rows.sort(key=lambda d: d.get("generated_at", ""))

    print(
        "| slug | total cost | minutes | planning % | build % | verify % | review % "
        "| cost/plan | generated |"
    )
    print("|---|---|---|---|---|---|---|---|---|")
    for row in rows:
        cost = row["cost"]
        # A partial total must never sit in a comparison table unmarked — the whole
        # point of the table is ranking features against each other.
        total_cell = f"${cost['total']:.4f}" + (" (partial)" if cost.get("total_is_partial") else "")
        # `.get` on the review keys, not `[]`: every report.json written before the
        # review queue existed lacks them, and the trend table's whole job is to put
        # those historical features next to new ones. 0.0 is the honest value for a
        # feature that ran no review pass.
        # `.get` on `time`, like the review keys: a report.json written before the
        # time roll-up existed has none, and the honest cell is n/a, not 0.
        time = row.get("time") or {}
        minutes = minutes_cell(time.get("total_s")) + (
            " (partial)" if time.get("total_is_partial") else ""
        )
        print(
            f"| {row['slug']} | {total_cell} | {minutes} | {cost['planning_pct']:.1f}% "
            f"| {cost['build_pct']:.1f}% | {cost['verify_pct']:.1f}% "
            f"| {cost.get('review_pct', 0.0):.1f}% "
            f"| ${cost['cost_per_plan']:.4f} | {row['generated_at']} |"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "slug",
        nargs="?",
        help="feature slug under plans/features/<slug>/ (or self/features/<slug>/ "
        "with --self) (required unless --all is passed)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="print a cross-feature trend table to stdout instead of writing one feature's report",
    )
    add_self_flag(parser)
    args = parser.parse_args()

    if args.all:
        run_trend_mode(features_root(args.self_mode))
        return

    if not args.slug:
        parser.error("slug is required unless --all is passed")

    run_single_feature(
        artifact_root(args.self_mode), features_root(args.self_mode), args.slug
    )


if __name__ == "__main__":
    main()
