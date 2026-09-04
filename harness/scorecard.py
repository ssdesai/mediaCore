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


def render(experiment: dict, rows: list[dict]) -> str:
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
    out.append(f"Fixtures: {', '.join(experiment.get('fixtures', []))}  ·  "
               f"methods: {', '.join(experiment.get('methods', []))}  ·  "
               f"repeats: {experiment.get('repeats', 1)}  ·  "
               f"noise band: ±{band}%")
    out.append("")

    if not rows:
        out.append("## Runs")
        out.append("")
        out.append("_No runs recorded yet._")
        out.append("")
        return "\n".join(out)

    out.append("## Runs")
    out.append("")
    out.append("| Fixture | Method | Branch | To PR-open | Review fixed/esc. | Rework | "
               "To green | Wall to PR | Accept | PR |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    for row in rows:
        accept = "pass" if row.get("accept_pass") else "FAIL"
        if row.get("method_failed"):
            accept = "method failed"
        pr = row.get("pr_url") or NA
        out.append(
            f"| {row.get('fixture', '?')} | {cell_label(row)} | `{row.get('branch', '?')}` | "
            f"{money(row.get('cost_method_usd'))} | "
            f"{row.get('review_fixed', 0)}/{row.get('review_escalated', 0)} | "
            f"{money(row.get('cost_rework_usd')) if row.get('rework_ran') else NA} | "
            f"{money(row.get('cost_green_usd'))} | "
            f"{minutes_between(row.get('t_method_start', ''), row.get('t_pr_open', ''))} | "
            f"{accept} | {pr} |"
        )
    out.append("")

    # Per (fixture, method): mean and spread, which only mean anything above one repeat.
    groups: dict[tuple[str, str], list[dict]] = {}
    for row in rows:
        groups.setdefault((row.get("fixture", "?"), row.get("method", "?")), []).append(row)

    if any(len(group) > 1 for group in groups.values()):
        out.append("## Per cell")
        out.append("")
        out.append("| Fixture | Method | Runs | Mean to green | Spread | Mean to PR-open |")
        out.append("|---|---|---|---|---|---|")
        for (fixture, method), group in sorted(groups.items()):
            greens = [float(r.get("cost_green_usd") or 0) for r in group]
            opens = [float(r.get("cost_method_usd") or 0) for r in group]
            out.append(f"| {fixture} | {method} | {len(group)} | {money(mean(greens))} | "
                       f"{money(spread(greens))} | {money(mean(opens))} |")
        out.append("")

    # The noise band, applied to each fixture's method pairs. A tie inside the band is
    # the honest reading at n=1: run-to-run executor variance is that large.
    fixtures = sorted({row.get("fixture", "?") for row in rows})
    comparisons: list[str] = []
    for fixture in fixtures:
        methods = sorted({m for (f, m) in groups if f == fixture})
        for i, left in enumerate(methods):
            for right in methods[i + 1:]:
                a = mean([float(r.get("cost_green_usd") or 0) for r in groups[(fixture, left)]])
                b = mean([float(r.get("cost_green_usd") or 0) for r in groups[(fixture, right)]])
                if a == 0 or b == 0:
                    continue
                delta = (b - a) / a * 100.0
                verdict = ("a tie inside the band" if abs(delta) <= band
                           else f"{right} is {'cheaper' if delta < 0 else 'dearer'}, outside the band")
                comparisons.append(
                    f"- **{fixture}**: {left} {money(a)} vs {right} {money(b)} "
                    f"({PCT_FMT.format(delta)}) — {verdict}."
                )
    if comparisons:
        out.append(f"## Cost to checklist-green, against the ±{band}% band")
        out.append("")
        out.extend(comparisons)
        out.append("")

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
