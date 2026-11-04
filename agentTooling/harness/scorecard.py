#!/usr/bin/env python3
"""Render an experiment's results.jsonl into SCORECARD.md.

    python3 agentTooling/harness/scorecard.py <experiment-dir>

Stdlib only, like everything under analysis/: no pip install, no venv, run directly.
It computes nothing about cost that is not already in the ledger — every dollar figure
was frozen by `analysis/report.py` at capture time and is only summed and compared here.

The prediction is copied out of experiment.json into the first section, before any
numbers, because EXPERIMENTS.md's rule is that the claim is written before the run and
the result is allowed to contradict it.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path

# Ledger and output file names, fixed by harness/SPEC.md §1.
EXPERIMENT_FILE = "experiment.json"
RESULTS_FILE = "results.jsonl"
SCORECARD_FILE = "SCORECARD.md"

# Formatting
MONEY_FMT = "${:,.2f}"
PCT_FMT = "{:+.0f}%"
NA = "—"
TIMESTAMP_FMT = "%Y-%m-%dT%H:%M:%SZ"
SECONDS_PER_MINUTE = 60
DEFAULT_NOISE_BAND_PCT = 15
SHORT_SHA_LEN = 7
OVERHEAD_PCT_FMT = "{:.1f}%"
COUNT_FMT = "{:g}"
COUNT_DECIMALS = 1

# Ledger rows: an ordinary cell has no `kind`; a program cell is `kind: "program"`
# (harness/README.md → "File shapes").
PROGRAM_KIND = "program"

# Cost fields a comparison reads, as (row field, what it measures): a cell's method alone
# and through review and rework; a program's group cost, the same two ways.
CELL_COST_FIELDS = (("cost_method_usd", "to PR-open"), ("cost_green_usd", "to green"))
PROGRAM_COST_FIELDS = (("cost_group_usd", "to PR-open"), ("cost_group_green_usd", "to green"))

# Program section labels and markers
PROGRAMS_HEADING = "## Programs"
PER_PROGRAM_CELL_HEADING = "## Per program cell"
PROGRAM_COMPARISON_SUFFIX = "orchestrator"
SINGLE_RUN_MARK = "(n=1)"
DEPENDS_OK_MARK = "✓"
DEPENDS_BROKEN_MARK = "✗"
PROGRAMS_COLUMNS = ("Program", "Arm", "#", "Branch", "Group to PR-open", "Overhead",
                    "Overhead %", "Group to green", "PRs open (x/n)", "Green (x/n)", "Record says")
FEATURES_COLUMNS = ("#", "Fixture", "Depends", "Branch", "Method", "To PR-open",
                    "Review fixed/esc.", "Rework", "To green", "Accept", "PR")
PER_PROGRAM_CELL_COLUMNS = ("Program", "Arm", "Runs", "Mean group to green", "Spread",
                            "Mean overhead %", "Mean PRs open", "Mean green")
DEPENDENCY_NOTE = "its branch does not contain the previous feature's tip (`dependency_ok` is false)."
PROGRAM_FAILED_NOTE = "the orchestrator did not finish the program."
UNPRICED_NOTE_PREFIX = "unpriced — "
PERCENT_SCALE = 100.0

# Arms that vary the measured repository's commit (experiment.json `base_arms`)
ARM_KIND_BASE = "base"
BASE_ARMS_KEY = "base_arms"
BASE_ARM_LABEL_FMT = "{arm} (base {sha})"

# Reading metrics (harness/reading_metrics.py), rendered beside the cost figures
READING_HEADING = "## Reading before the first edit"
READING_FIELDS = ("read_files_before_edit", "read_bytes_before_edit", "readme_bytes_read")
READING_COLUMNS = ("Fixture", "Method", "Arm", "Branch", "To PR-open",
                   "Files read before 1st edit", "Bytes read before 1st edit",
                   "README bytes read")
BYTES_FMT = "{:,}"


def read_json(path: Path):
    with open(path) as handle:
        return json.load(handle)


def read_rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            # A half-written row is not a reason to render nothing.
            continue
        # One row per line, and only objects: a pretty-printed ledger would otherwise
        # arrive here as a stream of fragments that each happen to parse.
        if isinstance(row, dict):
            rows.append(row)
    return rows


def money(value) -> str:
    try:
        return MONEY_FMT.format(float(value))
    except (TypeError, ValueError):
        return NA


def minutes_between(start: str, end: str) -> str:
    if not start or not end:
        return NA
    try:
        t0 = datetime.strptime(start, TIMESTAMP_FMT)
        t1 = datetime.strptime(end, TIMESTAMP_FMT)
    except ValueError:
        return NA
    total = (t1 - t0).total_seconds()
    if total < 0:
        return NA
    return f"{total / SECONDS_PER_MINUTE:.0f}m"


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def spread(values: list[float]) -> float:
    return (max(values) - min(values)) if values else 0.0


def cell_label(row: dict) -> str:
    label = f"{row.get('method', '?')}"
    if row.get("repeat") and row.get("repeat") != 1:
        label += f" #{row['repeat']}"
    return label


def arm_label(row: dict) -> str:
    """The arm a row ran under: its label, with the pinned agentTooling commit abbreviated
    (or, for a base arm, the measured repository's commit); NA for a run with no pin (the
    tree's own vendored copy)."""
    arm = row.get("arm") or ""
    if not arm:
        return NA
    if row.get("arm_kind") == ARM_KIND_BASE:
        sha = (row.get("base") or "")[:SHORT_SHA_LEN]
        return BASE_ARM_LABEL_FMT.format(arm=arm, sha=sha) if sha else arm
    sha = (row.get("agent_tooling") or "")[:SHORT_SHA_LEN]
    return f"{arm} ({sha})" if sha else arm


def split_rows(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    """(ordinary cells, program cells): a row is a program cell when its `kind` says so."""
    cells = [r for r in rows if r.get("kind") != PROGRAM_KIND]
    programs = [r for r in rows if r.get("kind") == PROGRAM_KIND]
    return cells, programs


def table_row(*cells: str) -> str:
    return "| " + " | ".join(cells) + " |"


def table_header(columns: tuple[str, ...]) -> list[str]:
    return [table_row(*columns), "|" + "---|" * len(columns)]


def compare(label: str, left: str, a_rows: list[dict], right: str, b_rows: list[dict],
            band: float, fields: tuple[tuple[str, str], ...] = CELL_COST_FIELDS,
            extra: str = "") -> str | None:
    """One comparison line: to PR-open and to checklist-green, each against the band, then
    `extra` (a program's counts) as a last clause. None when either side has no cost."""
    parts = []
    for field, what in fields:
        a = mean([float(r.get(field) or 0) for r in a_rows])
        b = mean([float(r.get(field) or 0) for r in b_rows])
        if a == 0 or b == 0:
            continue
        delta = (b - a) / a * 100.0
        verdict = ("tie inside the band" if abs(delta) <= band
                   else f"{right} {'cheaper' if delta < 0 else 'dearer'}, outside the band")
        parts.append(f"{what} {money(a)} vs {money(b)} ({PCT_FMT.format(delta)}, {verdict})")
    if not parts:
        return None
    if extra:
        parts.append(extra)
    return f"- **{label}**: {left} vs {right} — " + "; ".join(parts) + "."


def feature_flags(feature: dict) -> tuple[str, str]:
    """(depends, accept) for a program's feature row: whether its branch holds the previous
    feature's tip, NA when it was not meant to; and the ordinary cell's accept wording."""
    if not feature.get("depends_on_previous"):
        depends = NA
    else:
        depends = DEPENDS_BROKEN_MARK if feature.get("dependency_ok") is False else DEPENDS_OK_MARK
    accept = "pass" if feature.get("accept_pass") else "FAIL"
    if feature.get("method_failed"):
        accept = "method failed"
    return depends, accept


def program_counts(rows: list[dict]) -> dict:
    """Mean figures over one arm's program rows: PRs opened, features green, overhead %,
    and the feature count. A summary field that is absent or null is counted from the
    features; an absent or null overhead_pct is cost_overhead_usd / cost_group_usd."""
    opens, greens, pcts, counts = [], [], [], []
    for row in rows:
        features = row.get("features") or []
        counts.append(float(row["features_count"] if row.get("features_count") is not None
                            else len(features)))
        opens.append(float(row["features_pr_open"] if row.get("features_pr_open") is not None
                           else sum(1 for f in features if f.get("pr_url"))))
        greens.append(float(row["features_green"] if row.get("features_green") is not None
                            else sum(1 for f in features if f.get("green"))))
        group = float(row.get("cost_group_usd") or 0)
        pcts.append(float(row["overhead_pct"]) if row.get("overhead_pct") is not None
                    else (float(row.get("cost_overhead_usd") or 0) / group * PERCENT_SCALE if group else 0.0))
    return {"count": mean(counts), "pr_open": mean(opens), "green": mean(greens),
            "overhead_pct": mean(pcts), "runs": len(rows)}


def count_text(value: float) -> str:
    return COUNT_FMT.format(round(value, COUNT_DECIMALS))


def program_comparisons(programs: list[dict], band: float) -> list[str]:
    """One line per program, per arm pair, in the cell lines' wording, ending with each
    arm's counts. A side with one run only is marked, as n=1 is the thing to be wary of."""
    by_arm: dict[tuple[str, str], list[dict]] = {}
    for row in programs:
        by_arm.setdefault((row.get("program", "?"), row.get("arm") or ""), []).append(row)
    lines: list[str] = []
    for program in sorted({p for (p, _) in by_arm}):
        arms = sorted({a for (p, a) in by_arm if p == program and a})
        for i, left in enumerate(arms):
            for right in arms[i + 1:]:
                a_rows, b_rows = by_arm[(program, left)], by_arm[(program, right)]
                a, b = program_counts(a_rows), program_counts(b_rows)
                n = count_text(max(a["count"], b["count"]))
                extra = (f"PRs open {count_text(a['pr_open'])}/{n} vs {count_text(b['pr_open'])}/{n}, "
                         f"green {count_text(a['green'])}/{n} vs {count_text(b['green'])}/{n}, "
                         f"overhead {OVERHEAD_PCT_FMT.format(a['overhead_pct'])} vs "
                         f"{OVERHEAD_PCT_FMT.format(b['overhead_pct'])}")
                if min(a["runs"], b["runs"]) == 1:
                    extra += f" {SINGLE_RUN_MARK}"
                line = compare(f"{program} · {PROGRAM_COMPARISON_SUFFIX}", f"arm {left}", a_rows,
                               f"arm {right}", b_rows, band, PROGRAM_COST_FIELDS, extra)
                if line:
                    lines.append(line)
    return lines


def render_programs(experiment: dict, rows: list[dict], band: float) -> list[str]:
    """The Programs section: one row per program cell, one table of features per cell, and
    — once a program has been run more than once per arm — the means. `experiment` and
    `band` are the render() context; the comparison lines are program_comparisons()."""
    if not rows:
        return []
    out: list[str] = [PROGRAMS_HEADING, ""]
    out.extend(table_header(PROGRAMS_COLUMNS))
    for row in rows:
        counts = program_counts([row])
        n = count_text(counts["count"])
        record = (row.get("record_report") or {}).get("group_total_usd")
        out.append(table_row(
            str(row.get("program", "?")), arm_label(row), str(row.get("repeat", 1)),
            f"`{row.get('branch', '?')}`", money(row.get("cost_group_usd")),
            money(row.get("cost_overhead_usd")), OVERHEAD_PCT_FMT.format(counts["overhead_pct"]),
            money(row.get("cost_group_green_usd")),
            f"{count_text(counts['pr_open'])}/{n}", f"{count_text(counts['green'])}/{n}",
            money(record) if record is not None else NA))
    out.append("")

    for row in rows:
        out.append(f"### {row.get('program', '?')} · arm {row.get('arm') or NA} #{row.get('repeat', 1)}")
        out.append("")
        out.extend(table_header(FEATURES_COLUMNS))
        for feature in row.get("features") or []:
            depends, accept = feature_flags(feature)
            out.append(table_row(
                str(feature.get("position", "?")), str(feature.get("fixture", "?")), depends,
                f"`{feature.get('branch', '?')}`", str(feature.get("method", "?")),
                money(feature.get("cost_method_usd")),
                f"{feature.get('review_fixed', 0)}/{feature.get('review_escalated', 0)}",
                money(feature.get("cost_rework_usd")) if feature.get("rework_ran") else NA,
                money(feature.get("cost_green_usd")), accept, feature.get("pr_url") or NA))
        out.append("")

    groups: dict[tuple[str, str], list[dict]] = {}
    for row in rows:
        groups.setdefault((row.get("program", "?"), row.get("arm") or ""), []).append(row)
    if any(len(group) > 1 for group in groups.values()):
        out.append(PER_PROGRAM_CELL_HEADING)
        out.append("")
        out.extend(table_header(PER_PROGRAM_CELL_COLUMNS))
        for (program, arm), group in sorted(groups.items()):
            greens = [float(r.get("cost_group_green_usd") or 0) for r in group]
            counts = program_counts(group)
            out.append(table_row(
                program, arm or NA, str(len(group)), money(mean(greens)), money(spread(greens)),
                OVERHEAD_PCT_FMT.format(counts["overhead_pct"]), count_text(counts["pr_open"]),
                count_text(counts["green"])))
        out.append("")
    return out


def reading_cell(value) -> str:
    """A reading figure: grouped digits, or NA when it was not measured."""
    return NA if value is None else BYTES_FMT.format(int(value))


def render_reading(rows: list[dict]) -> list[str]:
    """The reading table: one row per cell carrying any reading field; empty when none does."""
    measured = [r for r in rows if any(field in r for field in READING_FIELDS)]
    if not measured:
        return []
    out: list[str] = [READING_HEADING, ""]
    out.extend(table_header(READING_COLUMNS))
    for row in measured:
        out.append(table_row(
            str(row.get("fixture", "?")), cell_label(row), arm_label(row),
            f"`{row.get('branch', '?')}`", money(row.get("cost_method_usd")),
            *(reading_cell(row.get(field)) for field in READING_FIELDS)))
    out.append("")
    return out


def render(experiment: dict, all_rows: list[dict]) -> str:
    rows, programs = split_rows(all_rows)
    name = experiment.get("name", "experiment")
    band = experiment.get("noise_band_pct", DEFAULT_NOISE_BAND_PCT)
    out: list[str] = []
    out.append(f"# {name}")
    out.append("")
    out.append("_Rendered from `results.jsonl` by `agentTooling/harness/scorecard.py`. "
               "Every figure below comes from a frozen `planning.json` / `usage.json`; "
               "nothing here reprices anything._")
    out.append("")
    out.append("## Prediction, written before the first run")
    out.append("")
    out.append(f"> {experiment.get('prediction', '(none recorded)')}")
    out.append("")
    if experiment.get("compare_to"):
        out.append(f"Compared against `{experiment['compare_to']}`.")
        out.append("")
    arms = experiment.get("agent_tooling") or {}
    arms_text = ("  ·  agentTooling arms: " + ", ".join(
        f"{label}={sha[:SHORT_SHA_LEN]}" for label, sha in arms.items())) if arms else ""
    base_arms = experiment.get(BASE_ARMS_KEY) or {}
    base_arms_text = ("  ·  base arms: " + ", ".join(
        f"{label}={sha[:SHORT_SHA_LEN]}" for label, sha in base_arms.items())) if base_arms else ""
    programs_text = f"  ·  programs: {len(programs)}" if programs else ""
    out.append(f"Fixtures: {', '.join(experiment.get('fixtures', []))}  ·  "
               f"methods: {', '.join(experiment.get('methods', []))}  ·  "
               f"repeats: {experiment.get('repeats', 1)}  ·  "
               f"noise band: ±{band}%{programs_text}{arms_text}{base_arms_text}")
    out.append("")

    if not rows and not programs:
        out.append("## Runs")
        out.append("")
        out.append("_No runs recorded yet._")
        out.append("")
        return "\n".join(out)

    if rows:
        out.append("## Runs")
        out.append("")
        out.append("| Fixture | Method | Arm | Branch | To PR-open | Review fixed/esc. | Rework | "
                   "To green | Wall to PR | Accept | PR |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|")
        for row in rows:
            accept = "pass" if row.get("accept_pass") else "FAIL"
            if row.get("method_failed"):
                accept = "method failed"
            pr = row.get("pr_url") or NA
            out.append(
                f"| {row.get('fixture', '?')} | {cell_label(row)} | {arm_label(row)} | "
                f"`{row.get('branch', '?')}` | "
                f"{money(row.get('cost_method_usd'))} | "
                f"{row.get('review_fixed', 0)}/{row.get('review_escalated', 0)} | "
                f"{money(row.get('cost_rework_usd')) if row.get('rework_ran') else NA} | "
                f"{money(row.get('cost_green_usd'))} | "
                f"{minutes_between(row.get('t_method_start', ''), row.get('t_pr_open', ''))} | "
                f"{accept} | {pr} |"
            )
        out.append("")
        out.extend(render_reading(rows))

    # Per (fixture, method, arm): mean and spread, which only mean anything above one
    # repeat. The arm is "" for a run with no agentTooling pin.
    groups: dict[tuple[str, str, str], list[dict]] = {}
    for row in rows:
        key = (row.get("fixture", "?"), row.get("method", "?"), row.get("arm") or "")
        groups.setdefault(key, []).append(row)

    if any(len(group) > 1 for group in groups.values()):
        out.append("## Per cell")
        out.append("")
        out.append("| Fixture | Method | Arm | Runs | Mean to green | Spread | Mean to PR-open |")
        out.append("|---|---|---|---|---|---|---|")
        for (fixture, method, arm), group in sorted(groups.items()):
            greens = [float(r.get("cost_green_usd") or 0) for r in group]
            opens = [float(r.get("cost_method_usd") or 0) for r in group]
            out.append(f"| {fixture} | {method} | {arm or NA} | {len(group)} | "
                       f"{money(mean(greens))} | {money(spread(greens))} | {money(mean(opens))} |")
        out.append("")

    # The noise band, applied to each fixture's method pairs (within one arm) and to each
    # fixture × method's arm pairs. A tie inside the band is the honest reading at n=1:
    # run-to-run executor variance is that large. Both figures are shown: to PR-open is
    # the method alone, to green adds the review and rework — which, under a pin, also
    # ran on the arm's agentTooling version.
    comparisons: list[str] = []
    for (fixture, arm) in sorted({(f, a) for (f, _, a) in groups}):
        methods = sorted({m for (f, m, a) in groups if f == fixture and a == arm})
        for i, left in enumerate(methods):
            for right in methods[i + 1:]:
                line = compare(f"{fixture}" + (f" · arm {arm}" if arm else ""), left,
                               groups[(fixture, left, arm)], right,
                               groups[(fixture, right, arm)], band)
                if line:
                    comparisons.append(line)
    for (fixture, method) in sorted({(f, m) for (f, m, _) in groups}):
        arms_here = sorted({a for (f, m, a) in groups if f == fixture and m == method and a})
        for i, left in enumerate(arms_here):
            for right in arms_here[i + 1:]:
                line = compare(f"{fixture} · {method}", f"arm {left}",
                               groups[(fixture, method, left)], f"arm {right}",
                               groups[(fixture, method, right)], band)
                if line:
                    comparisons.append(line)
    comparisons.extend(program_comparisons(programs, band))
    if comparisons:
        out.append(f"## Cost against the ±{band}% band")
        out.append("")
        out.extend(comparisons)
        out.append("")

    out.extend(render_programs(experiment, programs, band))

    # Anything a reader would otherwise have to open the ledger for.
    notes: list[str] = []
    for row in rows:
        for item in row.get("interventions") or []:
            notes.append(f"- `{row.get('branch')}` {item.get('t', '')}: {item.get('what', '')}")
        lost = float(row.get("cost_lost_usd") or 0)
        if lost > 0:
            notes.append(f"- `{row.get('branch')}`: {money(lost)} spent by killed or superseded "
                         "attempts (`cost_lost_usd`) — real spend, outside every method figure.")
        if row.get("method_failed"):
            notes.append(f"- `{row.get('branch')}`: the method did not reach an open PR.")
        if not row.get("accept_pass") and not row.get("method_failed"):
            for line in row.get("accept_lines") or []:
                notes.append(f"- `{row.get('branch')}` accept: {line}")
    for row in programs:
        for item in row.get("interventions") or []:
            notes.append(f"- `{row.get('branch')}` {item.get('t', '')}: {item.get('what', '')}")
        if row.get("method_failed"):
            notes.append(f"- `{row.get('branch')}`: {PROGRAM_FAILED_NOTE}")
        for feature in row.get("features") or []:
            branch = feature.get("branch")
            if feature.get("method_failed"):
                notes.append(f"- `{branch}`: the method did not reach an open PR.")
            elif not feature.get("accept_pass"):
                for line in feature.get("accept_lines") or []:
                    notes.append(f"- `{branch}` accept: {line}")
            if feature.get("depends_on_previous") and feature.get("dependency_ok") is False:
                notes.append(f"- `{branch}`: {DEPENDENCY_NOTE}")
            if feature.get("unpriced_reason"):
                notes.append(f"- `{branch}`: {UNPRICED_NOTE_PREFIX}{feature['unpriced_reason']}")
    if notes:
        out.append("## Interventions and failures")
        out.append("")
        out.extend(notes)
        out.append("")

    out.append("## Gate counts")
    out.append("")
    out.append("| Branch | At PR-open | At green |")
    out.append("|---|---|---|")
    for row in rows:
        out.append(f"| `{row.get('branch')}` | {row.get('gate_counts_pr_open') or NA} | "
                   f"{row.get('gate_counts_green') or NA} |")
    for row in programs:
        for feature in row.get("features") or []:
            out.append(f"| `{feature.get('branch')}` | {NA} | "
                       f"{feature.get('gate_counts_green') or NA} |")
    out.append("")
    return "\n".join(out)


def main() -> int:
    if len(sys.argv) != 2:
        sys.stderr.write(__doc__ or "")
        return 2
    experiment_dir = Path(sys.argv[1]).resolve()
    experiment_path = experiment_dir / EXPERIMENT_FILE
    if not experiment_path.exists():
        sys.stderr.write(f"ERROR: no {EXPERIMENT_FILE} in {experiment_dir}\n")
        return 1
    experiment = read_json(experiment_path)
    rows = read_rows(experiment_dir / RESULTS_FILE)
    (experiment_dir / SCORECARD_FILE).write_text(render(experiment, rows) + "\n")
    print(f"{experiment.get('name', experiment_dir.name)}: "
          f"{len(rows)} run(s) -> {experiment_dir / SCORECARD_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
