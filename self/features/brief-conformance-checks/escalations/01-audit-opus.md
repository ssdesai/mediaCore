Verdict: escalated

# Security audit 01 — brief-conformance-checks

Head: `claude/brief-conformance-checks` (HEAD); base: `origin/main`. Two throwaway copies:
`git archive HEAD` and `git archive origin/main`, extracted under the pass's scratch directory
(`head/`, `base/`). Nothing in this checkout was edited except this report.

## What the diff changes, rule by rule

The PreToolUse hook itself (`hooks/`) and `.claude/` are **not** in the diff. The audit paths
it touches carry these rules:

| # | Rule (what it refuses or decides, for whom) | File |
|---|---|---|
| R-a | `feature-start.sh --owner-brief <f>` refuses a path that is not a readable, non-empty regular file, before anything is written | `feature-start.sh` |
| R-b | `feature-close.sh` refuses when the start commit carried `OWNER_BRIEF.md` and the judged head lacks it or differs from it; refuses with no `review-report.md`, no `NN-conformance-*` plan in `review/complete/`, no `conformance-report.md`, a report not last written by `<slug>: review round <ROUND>`, or any `check-close` problem | `feature-close.sh` |
| R-c | `feature-close.sh` no longer accepts a `: cost records` / `: PR` commit after the judged head that touches a `review/*/*-conformance-*`, `conformance-report.md` or `OWNER_BRIEF.md` path | `feature-close.sh` |
| R-d | `conformance.py check-close`: every acceptance row `done`, every owner item has a row, a deviations section exists, and the conformance table says `done` for every item; an unreadable file exits 2 | `conformance.py` |
| R-e | `latest_review_plan` / `completed_review_count` skip `^[0-9]+-conformance-[a-z]+$` stems; `conformance.py` joins `AUDIT_TOOLING_PATHS` | `plan-runner-roots.sh` |
| R-f | `run-review.sh queue_security_audit` skips conformance stems when pairing the audit with the review; `queue_conformance_check` refuses a conformance plan whose stem is not the review's NN/model, and a review resumed from `inprogress/` with no check beside it; `executor_args_for_plan` launches the conformance plan with `--tools ""` and the prompt on stdin | `run-review.sh` |
| R-g | `run_plan` consults an optional `executor_args_for_plan` function that may replace a plan's tool arguments | `plan-runner-lib.sh` |
| — | `self/gate.sh` only registers the new test and a `py_compile`; no rule | `self/gate.sh` |

## Inputs tried

"defer" = the hook printed nothing (no decision: Claude Code's own prompt/settings decide,
i.e. handed to the human); "allow"/"deny" = the hook's explicit decision. For a lifecycle
script, "goes on" = it did not refuse.

### The PreToolUse hook (unchanged), payloads aimed at the new files and flags

Driver: `hookrun.py` / `hookpy.sh` / `hookone.sh` in scratch: the payload
`{tool_name, session_id, agent_id:"", cwd:<copy>, tool_input}` was fed on stdin to
`python3 <copy>/hooks/allow-repo-commands.sh` with `CLAUDE_PROJECT_DIR=<copy>`.

| Input | Head | Base |
|---|---|---|
| `env 'BASH_FUNC_executor_args_for_plan%%=() { PLAN_TOOL_ARGS=(); }' <root>/run-plans.sh --self x` | defer | defer |
| `env 'BASH_FUNC_claude%%=() { :; }' <root>/run-plans.sh --self x` | defer | defer |
| `<root>/run-review.sh --self brief-conformance-checks` | defer | defer |
| `<root>/feature-start.sh --self foo --owner-brief /etc/passwd` | defer | defer |
| `<root>/feature-close.sh --self brief-conformance-checks` | defer | defer |
| `CONFORMANCE_REPORT=/tmp/x <root>/feature-close.sh --self s` | defer | defer |
| `python3 -B <root>/conformance.py items <root>/self/features/…/README.md` | allow | defer (file absent) |
| `python3 <root>/conformance.py check-close --owner-brief a --review b --conformance c` | allow | defer (file absent) |
| `python3 <root>/conformance.py pr-body <root>/README.md` | allow | defer (file absent) |
| `python3 <root>/check-readme-index.py <root>` (base comparator: same rule, existing script) | allow | allow |
| `python3 <root>/conformance.py pr-body /etc/passwd` (echoes a file it is given) | defer | defer |
| `python3 conformance.py pr-body /etc/passwd` (relative script) | defer | defer |
| `python3 -B <root>/conformance.py items /etc/passwd` | defer | defer |
| `python3 <root>/conformance.py pr-body /etc/pass*` | defer | defer |
| `python3 <root>/conformance.py pr-body "/etc/pa""sswd"` | defer | defer |
| `env python3 <root>/conformance.py pr-body /etc/passwd` | defer | defer |
| `python3 <root>/conformance.py pr-body /etc/passwd > <root>/out.txt` | defer | defer |
| `python3 <root>/check-readme-index.py /etc` | defer | defer |
| `python3 <root>/hooks/wire-settings.py /etc/passwd` | defer | defer |
| `python3 <root>/does-not-exist.py /etc/passwd` | defer | defer |
| `cat /etc/passwd` | defer | defer |
| `python3 -c 'import conformance'` | deny | deny |
| `cat <root>/conformance.py \| python3` | deny | deny |
| `echo '## Conformance' > <root>/…/conformance-report.md` | deny | deny |
| `cp /tmp/x <root>/…/OWNER_BRIEF.md` | defer | defer |
| `git rm <root>/…/OWNER_BRIEF.md` | defer | defer |
| Write `…/OWNER_BRIEF.md` | defer | defer |
| Write `…/conformance-report.md` | defer | defer |
| Write `…/review/complete/01-conformance-opus.md` | defer | defer |
| Edit `<root>/conformance.py` | defer | defer |
| Agent call whose brief has no `feature:` header | deny | deny |
| Bash payload with no `tool_input` | defer | defer |
| Bash payload with `command` as a list | defer | defer |

The only head/base differences are the three `python3 <root>/conformance.py <in-root args>`
rows. They come from the hook's existing "repo code runs" approval, which applies to a script
in the root that exists. Base has no `conformance.py`, so the base hook defers. The same rule
gives the same answer on base for an existing script (`check-readme-index.py <root>` → allow).
Every out-of-root argument, quoting, glob, wrapper and redirect variant still defers on head.
These rows are not findings.

### Environment-imported functions reaching the runner (R-g)

`envfunc.sh <copy>`: `env 'BASH_FUNC_executor_args_for_plan%%=…' 'BASH_FUNC_on_plan_finished%%=…' bash probe` sourcing `plan-runner-roots.sh` + `plan-runner-lib.sh`.

| Input | Head | Base |
|---|---|---|
| `BASH_FUNC_executor_args_for_plan%%` in the runner's environment | imported; `run_plan` consults it | imported; never consulted |
| `BASH_FUNC_on_plan_finished%%` in the runner's environment | imported; consulted after each plan | imported; consulted after each plan |

This is not a finding. Whoever sets the runner's environment already controls it on base: an
imported `on_plan_finished` runs inside the runner after each plan and can reset
`CLAUDE_TOOL_ARGS`, and an imported `claude` replaces the launch outright. The hook defers that
launch to the human on both copies (rows above).

### Round and plan selection (R-e)

`roots.sh <copy>`: crafted `review/{complete,failed}/` trees and `latest_review_plan` / `completed_review_count`.

| Queue state | Head latest / count | Base latest / count |
|---|---|---|
| complete: `01-review-opus`, `02-conformance-opus` | `01-review-opus` / 1 | `02-conformance-opus` / 2 |
| complete `01-review-opus`, failed `02-conformance-opus` | `01-review-opus` / 1 | `02-conformance-opus` / 1 |
| `02-conformance-opus-x` (outside the regex) | it / 2 | it / 2 |
| `02-Conformance-opus` (case) | it / 2 | it / 2 |
| `02-conformance-` (empty model) | it / 2 | it / 2 |
| `02-conformance-opus4` (digit in model) | it / 2 | it / 2 |
| name with an embedded newline | it / 2 | it / 2 |
| complete: only `01-conformance-opus` | none / 0 (the close then refuses "no review has finished") | `01-conformance-opus` / 1 |
| `01-review`, `01-audit`, `01-conformance`, `02-review` | `02-review-opus` / 2 | `02-review-opus` / 3 |
| `is_conformance_stem 01-audit-opus`, `is_audit_stem 01-conformance-opus` | no, no | — / no |
| `conformance.py` in `AUDIT_TOOLING_PATHS` | yes (17 paths) | no (16) |

The skip only stops a conformance-named plan from counting as the round's review. The close's
check that nothing lands after the judged head still holds (variant C below). These rows alone
are not findings. Variants A–C show where the skip does matter.

### Lifecycle scripts end to end (R-a, R-b, R-c, R-f)

**The feature's own self-test** (`bash self/tests/brief-conformance.sh` in the head copy:
the real start, review runner, close and pr.sh against a stub `claude` and `gh`): exit 0, all 49
checks ok. Its refusal checks: a missing path, a directory and a whitespace-only file passed to
`--owner-brief` are refused with nothing written (S1a, S1b). The close refuses:

- a `partial` acceptance row (K1a);
- review done but conformance `not done` (K1c);
- no acceptance table (K1d);
- a conformance report re-committed under another subject (K1e);
- an `OWNER_BRIEF.md` edited after the start (K1f);
- an `OWNER_BRIEF.md` deleted after the start (K1g).

Each of these is an input the base close lets through: base has no such check.

**Stray conformance plan** (`stray.sh <copy> <variant>`: the same fixture shape as the
self-test. It runs the real `feature-start.sh`, `run-review.sh` and `feature-close.sh` with a stub
`claude` that writes a clean review report, a clean audit report, or a conformance answer. The
feature has **no** `OWNER_BRIEF.md`, and the work commit appends a line to `hooks/policy.py`, so
the audit is owed):

| Variant (queue in `review/incomplete/` before `run-review.sh --self stray`) | Head | Base |
|---|---|---|
| A: `01-review-opus.md` + `02-conformance-opus.md` | `run-review` goes on: queues `01-audit-opus` and runs audit, review, then the stray plan last with no tools. The stray plan holds the round's `plan_end`, so `verdict=clean` is stamped on `02-conformance-opus`; close refuses: "the latest review (01-review-opus) recorded 'no verdict'" | `run-review` goes on: treats `02-conformance-opus` as the review, queues `02-audit-opus`, runs review, audit, "review"; close passes the audit and reaches `pr` (the fixture stops at the capture) |
| B: as A plus a template-rendered `01-audit-opus.md` (from head's variant A) | `run-review` **goes on** (audit, review, stray conformance); close refuses ("01-review-opus recorded 'no verdict'") | `run-review` **refuses**: "01-audit-opus.md is queued, but a hook change's audit is 02-audit-opus"; close refuses ("no review has finished") |
| C: round 1 clean (`01-review` + `01-audit`), then `02-conformance-opus.md` alone | `run-review` goes on, runs it with no tools, commits `stray: review round 2`; close refuses: that commit "landed after the review judged this feature" | `run-review` goes on, runs it as a review with a new `02-audit-opus`; close refuses on the audit (`unreadable` from the stub) |

**`conformance.py check-close`** (`conf.py`: brief with items 1 and 2; head only. Base has no
`conformance.py`, and its close runs no such check, so for every row below the base result is
"the close goes on"):

| Input | Head |
|---|---|
| all `done` in both reports | exit 0 (expected) |
| review omits item 2 | refused: "owner item 2 … has no row" |
| review item 2 `partial` | refused |
| review item 2 `done ✅` / Cyrillic `dоne` / `~~not done~~ done` | refused (`unknown:`) |
| review item 2 `not  done` (two spaces) | refused (`not done`) |
| review row with a trailing empty cell / an escaped trailing pipe | refused (`unknown:`) |
| review row `1, 2` covering both | refused (item 1 has no row) |
| duplicate id: `not done` then `done` (review and conformance) | refused (the worse result is kept) |
| id `20` or `2a` standing for item 2 | refused (no row for 2) |
| CRLF line endings | exit 0 (correct) |
| no deviations section | refused |
| acceptance table only inside a fenced block | refused |
| header row renamed `Id` | refused (`Id` row is `unknown:`) |
| empty review file | refused |
| conformance omits item 2 / says `partial` | refused, naming the disagreement |
| conformance heading `## conformance ##` | exit 0 (correct: same section) |
| conformance table under `### Conformance` | refused |
| empty conformance answer | refused |
| non-UTF-8 conformance report | exit 2 with nothing on stdout → the close refuses "could not read" |
| an extra unknown row `99 not done` | exit 0 (not an owner item; the conformance rows are checked per owner item) |
| brief item heading inside a fence / no numbered heading / duplicate ids | items as specified (R3) |

**Code reading, confirmed against the runs above:**
- A forged `conformance-report.md` committed before a round cannot survive it. `run-review.sh`
  deletes the report before any pass that has a conformance plan, and the round commit is
  `git add -A`, so the deletion is staged. The close reads the subject of the last commit that
  touched the report.
- Removing `OWNER_BRIEF.md` from the working tree before `run-review.sh` gets nothing past the
  close. No check is queued, but the round commit stages the deletion, and K1g refuses it.
- R-c is strictly narrower than base: those paths are now refused under `: cost records`.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | Variant B: a hook-changing feature with no `OWNER_BRIEF.md`; `review/incomplete/` holds `01-audit-opus.md` (rendered from the template), `01-review-opus.md` and a stray `02-conformance-opus.md`; then `run-review.sh --self <slug>` | goes on: runs audit, review, then the stray plan last; the round's verdict is stamped on `02-conformance-opus`; the close later refuses with "01-review-opus recorded 'no verdict'" | refuses at queue time ("01-audit-opus.md is queued, but a hook change's audit is 02-audit-opus"); nothing runs | `bash scratch/stray.sh scratch/head B scratch/rendered-audit-A.md` vs `bash scratch/stray.sh scratch/base B scratch/rendered-audit-A.md` |
| non-blocking | Variant A: the same feature, `01-review-opus.md` + stray `02-conformance-opus.md`, no audit queued; `run-review.sh` | goes on; the stray plan runs last with no tools and takes the verdict stamp; the close refuses ("no verdict") | goes on; the stray file runs as the review and the close passes the audit and reaches `pr` | `bash scratch/stray.sh scratch/head A` vs `bash scratch/stray.sh scratch/base A` |
| non-blocking | Variant C: a clean round 1, then a stray `02-conformance-opus.md` alone; `run-review.sh` | goes on; runs it with no tools, commits `review round 2`; the close refuses (a commit after the judged head) | goes on; runs it as a review beside a new audit; the close refuses on the audit | `bash scratch/stray.sh scratch/head C` vs `bash scratch/stray.sh scratch/base C` |

## Non-blocking findings

1. **Pre-existing silent allow (lifecycle sense: the base script goes on too). Variant A.**
   Input: a feature with no `OWNER_BRIEF.md` whose `review/incomplete/` holds `01-review-opus.md`
   and a stray `02-conformance-opus.md`.
   - Head: `run-review.sh` goes on and runs the stray plan last. It holds the round's
     `plan_end`, so the verdict lands on it, and the close refuses with a misleading
     "01-review-opus recorded 'no verdict'".
   - Base: goes on too, and treats the file as a review.
   - What the rule should do instead: `queue_conformance_check` should refuse any queued
     `NN-conformance-<model>` plan the feature does not owe, naming it and saying to delete it.
     That covers no owner brief, no review queued beside it, and a stem other than the review's.
     It should refuse before its early `return 0`s for "no review" and "no owner brief"; today
     the stray-stem refusal is reached only when both exist.
2. **Pre-existing silent allow (lifecycle sense). Variant C.** Input: a stray
   `02-conformance-opus.md` queued alone after a clean round.
   - Head: goes on and runs it with no tools; the close refuses because of the round commit.
   - Base: goes on and runs it as a review.
   - What the rule should do instead: the same refusal as item 1. Here `review` is empty, so
     `queue_conformance_check` returns before any check.

Both are covered by the fix for the blocking finding below. If that fix lands, they need no
separate BACKLOG entry. If it does not, they are filed in `self/BACKLOG.md` as a
`brief-conformance-checks: backlog` commit.

## Blocking findings

### B1 — a stray conformance plan turns a queue-time refusal into a pass that runs

**Reproduce** (head copy; `stray.sh` fixture: the real `feature-start.sh --self stray --no-gate`,
no `--owner-brief`, a work commit that appends a line to `hooks/policy.py`):

1. Run `run-review.sh --self stray` once with `01-review-opus.md` + `02-conformance-opus.md`
   queued (variant A), so that `01-audit-opus.md` is rendered from `templates/SECURITY_AUDIT.md`.
   Keep a copy of that file.
2. In a fresh fixture, queue `01-audit-opus.md` (that copy), `01-review-opus.md` and a
   `02-conformance-opus.md` with any body in `self/features/stray/review/incomplete/`.
3. `./run-review.sh --self stray`.

- **Base:** exits 1 at queue time: "01-audit-opus.md is queued, but a hook change's audit is
  02-audit-opus …". Nothing runs.
- **Head:** exits 0. `queue_security_audit` now skips the conformance stem and pairs the audit
  with `01-review-opus`. `queue_conformance_check` returns at its "no owner brief" note without
  looking at the stray plan. The pass runs audit, review and then `02-conformance-opus` (with
  `--tools ""`, a prompt whose owner brief is empty). Because it runs last it holds the deferred
  `plan_end`, so the round's `verdict` and `head` are stamped on `02-conformance-opus` and not on
  the review. `feature-close.sh` then refuses: "the latest review (01-review-opus) recorded 'no
  verdict'". It fails closed, but the refusal names the wrong cause, and a pass ran that base
  would have refused.

**What the rule should do instead:** `run-review.sh` should refuse a queued
`NN-conformance-<model>` plan before the pass, whenever the feature does not owe that exact plan:
no `OWNER_BRIEF.md`, no review queued beside it, or a stem other than `<review NN>-conformance-<review model>`.
That means moving the stray-stem check in `queue_conformance_check` ahead of its
`[[ -n "$review" ]] || return 0` and its no-owner-brief `return 0`, with the same "delete it"
message the stray-audit refusal gives. The head is then no more permissive than the base for
variant B (it refuses), and variants A and C refuse too. A self-test case in
`self/tests/brief-conformance.sh` should assert the refusal for a stray conformance plan in a
feature without an owner brief, both with and without a review queued.
