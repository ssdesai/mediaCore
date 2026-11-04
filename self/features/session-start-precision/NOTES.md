# Notes: session-start-precision

Rulings taken during the direct build, each with its rationale. The two rulings taken
before the build are in `README.md` → "Rulings taken before the build"; ruling 1 restates
the first because it supersedes another feature's ruling.

1. **Precision over tolerance: `session-start` prints the first instant truncated to the
   millisecond, and `set-window-from` keeps its exact refusal.** Supersedes
   `self/features/execution-profiles/NOTES.md` ruling 18's "floored to the second". A
   tolerance in `set-window-from` would let any hand-typed instant up to a second early
   pass, claiming a sliver of whatever ran before the session — the very thing the refusal
   exists to stop — while precision fixes the one producer that was wrong. Truncated,
   never rounded, so `from <= start` still holds and the branch route's start-in-window
   test still selects the coordinator. Printed as `YYYY-MM-DDTHH:MM:SS.mmmZ` always,
   `.000` included, so the shape does not depend on the transcript
   (`FENCE_INSTANT_TIMESPEC`, `FENCE_INSTANT_UTC_SUFFIX` in `analysis/manifest.py`) —
   and three digits is a fraction every reader's `datetime.fromisoformat` parses, the
   pre-3.11 one included (it accepts three or six).
2. **A transcript with sub-millisecond instants is not handled.** Claude Code writes
   millisecond timestamps; a first line at `…29.123456Z` would print `…29.123Z`, which
   `set-window-from` refuses as earlier than the session. Not loosened, by ruling 1; it
   would be a producer change (print microseconds) if transcripts ever change shape.
3. **The fence-`from` readers needed no change.** `capture_planning.py`
   (`normalize_window` → `to_utc`, then `in_window` / `is_empty_window` /
   `check_branch_overlap`), `manifest.py set-window-to` (`to_instant`), `check-plans.sh`
   check 7 (`window_order`'s `fromisoformat`, and `ZONE_RE` anchors only the zone) all
   compare instants; `report.py` reads no `from`; `feature-capture.sh` reads only the
   date part of `from` (`--since`) and stamps `to` from `--last-branch-instant`, a whole
   second strictly past the last instant, so still after a fractional `from`. Tested in
   `self/tests/cloud-start.sh` A6 (capture, set-window-from) and `self/tests/check-plans.sh`
   7g/7h (added: a whole-second `to` before a `.500` `from` is empty, which a string
   comparison would pass, and the next whole second follows it).
4. **`self/tests/cloud-start.sh` A6 reaches the refusal path through the clock fallback.**
   The A5 container's coordinator had no readable transcript at the start, so its `from`
   is the clock; its transcript is then written with a `.500` first instant two hours
   earlier — the shape a start that could not read the transcript leaves — and
   `set-window-from "$(session-start <id>)"` must move `from` back (exit 0) and the
   capture select the session by branch. Against `main`'s `manifest.py` the floored
   output is refused, so A6a fails there.
5. **The settings-under-resume test lives in `self/tests/self-settings.sh` (section F)**,
   not `gate-resume.sh`: it needs the staged hooks and generated settings that file already
   builds, and `gate-resume.sh` runs stub checks against both gates, of which only the
   self gate has a fresh check.
6. **`record_fresh` stays a mode of `_record`, not a separate function**: the mode is the
   first argument `_record` already takes (`blocking` / `info`), so `fresh` is one more
   value, and its only difference is that no state file is named — so nothing is reused
   and nothing is written. `RECORD_FRESH` moved to the constants block at the top.
7. **Left as they are:** `self/DESIGN-2026-10-05-cloud-execution.md` still says "floored
   to the second" — a dated design record, superseded by ruling 1 rather than rewritten;
   and `feature-start.sh`'s `warn` line still names `set-window-from <its first instant>`
   (behaviour unchanged, per the brief). `templates/plans/gate.sh` gets no `record_fresh`
   (README → "Deliberately excluded"); filed in `self/BACKLOG.md` as an assertion so a
   consuming repo that grows such a check finds it.
