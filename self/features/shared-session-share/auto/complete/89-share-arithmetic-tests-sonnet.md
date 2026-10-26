# 89 — acceptance tests: share arithmetic

feature: agentTooling/shared-session-share — plan 1 of 6. A session claimed by more than
one feature is priced and timed by *concurrent share* instead of counted in full by each;
this plan is the wanted behaviour as a test, written before any of it exists.

Writes `self/tests/session-share.sh`, the black-box acceptance test for the share
arithmetic, and registers it in `self/gate.sh`. **RED until plan 91 lands** — that is
expected, and a run against today's `capture_planning.py` must FAIL its assertions, not
crash.

Independent of other plans. Plan 90 depends on the `session_line` change below.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- There is no test runner here. A test is a bash script that prints one `ok`/`FAIL` line
  per check and exits non-zero if any failed; `self/gate.sh` lists each one by path.
- No test may read or write the real `~/.claude`. The seam is `$HOME`: export it to the
  script's own `mktemp -d` before calling anything under `analysis/`.
- `mktemp -d` must be re-resolved with `pwd -P`. `roots.py` resolves `AGENT_TOOLING_DIR`
  with `Path.resolve()`, so on macOS an unresolved `/var/…` fixture path matches no
  transcript and every assertion passes or fails vacuously against an empty scan.
- `capture_planning.py` needs `analysis/{pricing,roots,transcript,capture_planning}.py`
  copied into the throwaway checkout, and `mkdir -p "$AT/.git"` so `session_root()` stops
  walking up.
- The claims ledger is `$HOME/.claude/subagent-claims.json`, two sections
  (`{"subagents": {…}, "sessions": {…}}`); a session id maps to a **list** of claims.
- bash 3.2: no associative arrays, no `${var^^}`.

## Files

- Create `self/tests/session-share.sh`
- Modify `self/tests/fixtures/transcripts/build-transcript.sh`
- Modify `self/gate.sh`
- Modify `self/tests/README.md`

## `self/tests/fixtures/transcripts/build-transcript.sh`

Give `session_line` an optional 12th argument `IS_SIDECHAIN`, defaulting to `false`, and
emit it in place of the hard-coded `"isSidechain":false`. Mirror how `transcript_line`
already takes its `sidechain` argument (`build-transcript.sh:15-22`) — same default, same
`local sidechain="${12:-false}"` shape — and extend the comment header above
`session_line` with one line saying why: a parent transcript's own sidechain lines are
priced into `cost_usd.sidechain` and must be shareable like any other line.

## `self/tests/session-share.sh`

Mirror the scaffolding of `self/tests/capture-guard.sh:83-165` exactly — `HERE`, the
`mktemp -d` re-resolved through `pwd -P`, `AT="$TMP/agentTooling"`, the four copied
analysis modules, `mkdir -p "$AT/.git"`, the sourced `build-transcript.sh`, the
`fails`/`ok`/`fail`/`check` helpers, `FAKE_HOME`, and `PROJECTS` derived as
`$FAKE_HOME/.claude/projects/$(echo "$AT" | tr '/' '-')`. Read that range before writing;
do not re-derive it.

Header comment, in the style of `capture-guard.sh:1-80`: what the script guards, the rule
under test, and a numbered list of the assertions in order. Say that phases 1–5 are RED
until `analysis/capture_planning.py` shares a multiply-claimed session, and that phase 6
is GREEN today and must stay green — it is the no-change half of the contract.

### The fixture

One session, five features, all in the `--self` corpus at `$AT/self/features/<slug>/`.

```
SESSION="11111111-0000-0000-0000-000000000001"
MODEL="claude-sonnet-5"
BRANCH="unclaimedBranch"        # in no manifest's `branches`: selection is by pin alone
```

Six billable responses, written with `session_line` into `$PROJECTS/$SESSION.jsonl`, all
carrying `cwd` `$AT` and branch `$BRANCH`, all input/cache-read/cache-creation `0` so the
cost is proportional to output tokens alone and the arithmetic below is exact:

| id | timestamp | output tokens |
|---|---|---|
| `r0` | `2026-06-01T08:00:00.000Z` | 1000 |
| `r1` | `2026-06-01T10:30:00.000Z` | 2000 |
| `r2` | `2026-06-01T12:30:00.000Z` | 4000 |
| `r3` | `2026-06-01T14:30:00.000Z` | 6000 |
| `r4` | `2026-06-01T16:30:00.000Z` | 12000 |
| `r5` | `2026-06-01T20:30:00.000Z` | 800 |

Four features pin `$SESSION` in their manifest's `sessions`, with `branches` set to a name
no transcript carries (so the pin is the only route in) and these windows:

| slug | from | to |
|---|---|---|
| `share-a` | `2026-06-01T10:00:00Z` | `2026-06-01T18:00:00Z` |
| `share-b` | `2026-06-01T12:00:00Z` | `2026-06-01T18:00:00Z` |
| `share-c` | `2026-06-01T14:00:00Z` | `2026-06-01T18:00:00Z` |
| `share-d` | `2026-06-01T16:00:00Z` | `2026-06-01T18:00:00Z` |

A fifth feature `share-solo` pins its own session `22222222-0000-0000-0000-000000000002`,
one response, and is claimed by nobody else.

Write a `write_manifest SLUG FROM TO SESSION_ID` helper on the shape of
`capture-guard.sh:125-146` (a `# <slug>` heading, a sentence naming this script, then the
```json fence). Give every manifest a non-null `to` except where a phase needs otherwise.

Capture with
`HOME="$FAKE_HOME" python3 "$AT/analysis/capture_planning.py" --self "$SLUG" 2>&1`,
and re-capture with `--recapture` — a second capture of the same slug is skipped
otherwise. **Capture the four in order a, b, c, d**, then re-capture `share-a` so its
record sees the other three claims; a claimant that has not been captured yet is still
found through its manifest, and phase 4 is what pins that.

### The expected split

Ownership per response — every claimant whose window covers its timestamp, and the
earliest claimant alone for anything before every `from`:

```
r0  head           -> a                (1000 output tokens to a)
r1  a              -> a                (2000 to a)
r2  a,b            -> a,b              (2000 each)
r3  a,b,c          -> a,b,c            (2000 each)
r4  a,b,c,d        -> a,b,c,d          (3000 each)
r5  after every to -> nobody           (800 unclaimed)
```

Owned output tokens: **a 10000, b 7000, c 5000, d 3000, unclaimed 800**, session 25800.
Since every response is the same model on the same UTC date, dollars are in the same
ratio, so a phase may assert on `cost_usd.total` directly with a `1e-9` tolerance.

Duration, partitioned over `[first line, last line]` = `08:00`–`20:30` = 45000 s by the
same rule:

```
[08:00,10:00) 7200 -> a          [16:00,18:00) 7200 -> a,b,c,d @ 1800
[10:00,12:00) 7200 -> a          [18:00,20:30) 9000 -> nobody
[12:00,14:00) 7200 -> a,b @ 3600
[14:00,16:00) 7200 -> a,b,c @ 2400
```

**a 22200, b 7800, c 4200, d 1800, unclaimed 9000**, summing to 45000.

### The assertions

1. **The four shares plus the unclaimed remainder equal the session's own cost.** Read
   `cost_usd.total` from all four `planning.json` files and `sessions[0].session_cost_usd`
   and `sessions[0].unclaimed_usd` from any one of them; assert
   `a + b + c + d + unclaimed == session_cost_usd` within `1e-9`. This is the assertion
   the whole feature exists for — write it first and name it as such in the header.
2. **Each share is the predicted one.** Assert each feature's `cost_usd.total` against the
   token ratios above (`a/session == 10000/25800`, and so on), within `1e-9`.
3. **The head belongs to the earliest claimant.** `share-a`'s total is strictly greater
   than the sum of `r1`–`r4`'s share would be without `r0`; assert directly that
   `a == 10000/25800 * session_cost_usd` and, separately, that `b`, `c` and `d` each
   carry no part of `r0` by asserting their totals against their own ratios.
4. **`share_basis` names every claimant, this feature first, with its source.** On
   `share-a`'s entry: four entries, each `{feature, from, to, source}`; this feature's is
   `agentTooling/share-a` with `source` `"self"`; the other three are `"manifest"`; the
   `from`/`to` are the manifests' own bounds. Assert the *set* of features, not the order
   of the other three.
5. **Durations are shared by the same rule.** `sessions[0].duration_s` is 22200 / 7800 /
   4200 / 1800 respectively; `sessions[0].session_duration_s` is 45000 in all four; and
   the four plus 9000 sum to 45000. Assert also that `started_at`/`ended_at` are the
   session's own first and last instants in all four — they are the transcript's bounds,
   not the share's, and only `duration_s` is apportioned.
6. **A session with one claimant is untouched.** Capture `share-solo`: its
   `planning.json` session entry has **no** `share_basis`, no `session_cost_usd`, no
   `session_duration_s` and no `unclaimed_usd`; no `priced[]` row carries `share` or
   `full_cost_usd`; `duration_s` equals `ended_at - started_at`; and `cost_usd.total` is
   the whole transcript's cost. This phase is green today and must stay green.
7. **A response straddling a boundary is billed once.** Append a second `session_line`
   with message id `r2` at `2026-06-01T12:00:00.001Z` (after `share-b`'s `from`, where the
   first `r2` line is before it) and re-capture all four. Assert phase 1's invariant still
   holds to `1e-9` and that `share-a` and `share-b`'s totals are unchanged from phase 2.
   58% of real responses span more than one timestamp, so a share walk that groups lines
   and de-duplicates within each group bills such a response once **per group**; this is
   the assertion that catches it.
8. **The unclaimed remainder is reported, not silently dropped.** Capture output contains
   a warning naming `$SESSION` and the dollars outside every claim, and
   `sessions[0].unclaimed_usd` is the `800/25800` share of the session cost.

Every phase writes its captures to files under `$TMP` and greps those, the way
`capture-guard.sh` does; do not re-run a capture to re-read its output.

Extract the repeated JSON reads into two helpers near the top —
`field PLANNING JQ_PATH` running `python3 -c` over `json.load`, and
`close_enough A B` for the float comparisons — rather than repeating a `python3 -c`
one-liner in every check.

## `self/gate.sh`

**Two lists, both required.** The script is named once in the `shell_scripts` array that
`bash -n` parses (`self/gate.sh:122-160`) and once as a `record "<label> self-test" bash
self/tests/<name>.sh` line in the behavioural block (`self/gate.sh:180-196`). Adding it to
only the first parses it and never runs it. In both, put it immediately after
`self/tests/claims-ledger.sh` — it is that file's arithmetic counterpart and reads best
beside it. Label: `session share self-test`.

## `self/tests/README.md`

Add one entry for `session-share.sh`, in the same shape and depth as the
`claims-ledger.sh` entry above it: the scaffolding it reuses, the fixture (one session,
five features, the six responses), each assertion in order, the exact expected split
(the token and second tables above, so the numbers are readable without running it), and
that phases 1–5 and 7–8 were RED until the share walk landed while phase 6 is the
no-change contract. Place it directly after the `claims-ledger.sh` entry.
