feature: agentTooling/claim-window-precision

# Direct one-shot brief — claim-window-precision

## Where

Worktree `/Users/sahildesai/dev/agentTooling-claim-window-precision`, branch
`claim-window-precision`, base `shared-session-share` (unmerged; this feature is stacked
on it and its PR opens against it). Every command runs there, in absolute paths. The
primary checkout `/Users/sahildesai/dev/agentTooling` is NOT it — never touch it.

This is agentTooling's own corpus: `--self` everywhere, feature directory
`self/features/claim-window-precision/`, gate `bash self/gate.sh` (~3 min, 70 checks,
writes `self/gate-report.txt`; the verdict line must read `all checks passed`, and a
SKIP is not green).

## Read, in this order

1. This file, then `/Users/sahildesai/dev/agentTooling-claim-window-precision/AGENT_DIRECT.md`
   — the procedure you follow ("The procedure", "Checkpoint and resume").
2. `CLAUDE.md` (imports `CONVENTIONS.md`: README Rules 1–2 and named constants are binding).
3. `self/PROJECT_FACTS.md` — bash 3.2, no `set -e`, bare cross-imports in `analysis/`,
   the test conventions.
4. `self/BACKLOG.md` — the four entries `Raised by \`shared-session-share\``. They are the
   spec. Delete each from the file as part of closing it (an entry closed by a feature
   does not stay in the backlog).
5. `self/features/shared-session-share/README.md` — the feature this one stacks on:
   the share rule, `share_basis`, the ledger's `window` key.
6. READMEs of the folders you touch, before touching them: `analysis/README.md`,
   `self/tests/README.md`, `self/README.md`. Follow them; do not grep for discovery.

## The four items, with their rulings (settled — do not reopen)

### 1. `session_window.to` is stamped from evidence

Today `feature-close.sh` step 8 stamps `to` = now, after the capture. Every feature
started from one coordinator therefore closes with the same `to` (its close time), the
windows nest instead of chaining, and the share split hands a feature an equal share of
the coordinator for hours after its work stopped.

Rulings:

- **Evidence = one second after the last instant of the feature's own branch-selected
  sessions and their subagents.** "Branch-selected" means what `select_parent` selects by
  `branches` + `session_window` and not by pin, minus `exclude_sessions` — reuse the
  selection code, never re-implement the rule. Pinned sessions are excluded from the
  evidence on purpose: the pinned coordinator started N features and outlives all of
  them. Subagents count because a delegate's transcript is part of the work.
  One second because both `in_window` and the share split are half-open on `to`: a
  single-line session, or a response at exactly the last instant, needs `to` strictly
  after it.
- **New CLI mode: `capture_planning.py [--self] --last-branch-instant <slug>`** prints
  that instant as ISO 8601 UTC with a `Z` (the `_iso_or_none` shape), or nothing with
  exit 0 when the feature has no branch-selected session. Reads timestamps only, writes
  nothing, opens no ledger.
- **`feature-close.sh` stamps BEFORE the capture, not after.** Reorder: compute the
  evidence, stamp `to`, then capture. The capture's share split then runs against the
  real bound, which is the whole point — a stamp after the capture would leave this
  feature's own frozen record split against an open window. Rewrite the step-8 header
  comment and the `refuse` message on capture failure to say so.
- **Rolled back if the capture refuses.** Exactly like `rollback_carry` /
  `rollback_recovery`: the primary was verified clean, so `git checkout -- <manifest>`
  restores it. Add `rollback_stamp` beside them and call it on the same refusal path.
- **No evidence → stamp now, and say so**: `  window    no branch session — to stamped at
  close time (<ts>)`. Same behaviour as today for that case, now announced.
- **Tighten-only.** `manifest.py set-window-to` today replaces only a `null` bound and
  reports a set one untouched. Add `--tighten`: replace a set bound only with an EARLIER
  instant, print `old -> new`; refuse (non-zero, message) a later one. `feature-close.sh
  --recapture` uses `--tighten` — that is the repair path for every `to` already written
  in both corpora: the human runs `feature-close.sh --self <slug> --recapture` per feature,
  which the two stale over-counts need anyway. The plain close keeps stamping only a
  `null` bound.
- **Known limit, record it in `self/BACKLOG.md` as this feature's entry**: another
  feature's claim that is still in flight (`to: null`) stays unbounded in this feature's
  split — bounding it would mean walking that feature's transcripts from here. Its own
  close bounds its own record.

Tests, both red before the change:

- `self/tests/feature-lifecycle.sh` (it drives the real `feature-start.sh` /
  `feature-close.sh` in a throwaway git checkout under `$FAKE_HOME`; read its helpers
  `project_dir`, `start`, `close`, `now_z`, `fence`): a feature whose only branch session
  ends at a fixed instant hours in the past closes with `to` == that instant + 1s, not
  ≈ now; a feature with no branch session closes with `to` ≈ now and the `no branch
  session` line; `--recapture` on a feature whose `to` is later than its evidence tightens
  it and prints `old -> new`; `set-window-to --tighten` with a LATER instant refuses and
  leaves the fence byte-identical.
- `self/tests/session-share.sh`: a claimant whose `to` moves earlier loses the responses
  past it — one assertion, reusing the existing fixture (tighten `share-d`'s `to` to
  16:00:00Z, recapture, its share is now zero and the sum invariant holds).

### 2. Quantify what lies outside a single-claimant session's window

`select_parent`'s `may span the window boundary` warning (the selected branch, `end_ts >
window["to"]`) says nothing about size. Extend that one warning: the dollars and seconds
of the responses at or after `to` — dollars via `iter_billable_messages_at` +
`pricing.compute_cost` exactly as the unclaimed remainder is priced, seconds =
`end_ts - to` — and whether they were counted: on the unshared path, `counted in full
(this feature is its only claimant)`; on the share path they are already excluded by the
split, so the sentence says `not counted`. Prose only: no figure in `planning.json`
changes on the unshared path — `session-share.sh` phase 6 pins that and must pass
untouched.

Test: `self/tests/session-share.sh`, one new phase — a solo session with one response
after its claimant's `to`: the capture output names the session, the dollar figure equal
to that response's cost, and the seconds; `cost_usd.total` still counts it.

### 3. The `predates the share rule` warning fires on every sweep

`annotate_frozen_record` returns `None` when nothing changed, and the WARN at the call
site (`capture_feature`, the `prior_at and not recapture` branch) sits in the `else` — so
it prints once and never again. Change the signature to return `(annotated_ids, changed)`
— never fold the two into one value — and print the WARN for every annotated session
lacking `share_basis` whether or not this run changed anything. The `annotated` /
`skipped` return value and the `skipping` line keep meaning "did this run write".

Test: `self/tests/session-claims.sh` assertion 7 exercises one sweep; add: a second
consecutive `--all` prints the WARN again, naming the same session.

### 4. Index the claimants once

`session_claim_intervals` re-globs and re-parses every manifest under both corpora and
runs `repo_identity` (a `git remote get-url` subprocess) on every call, and `select_parent`
calls it once per selected session. Build the index once where `share_ctx` is built in
`capture_feature`: one pass over `share_ctx["features_dirs"]` producing, per manifest,
`{repo, repo_name, slug, window (normalized), pins (set), branches (set), excluded
(set)}`, with `repo_identity` computed once per features dir; `session_claim_intervals`
then filters that list in memory. Its answer for every session is unchanged — the
existing `session-claims.sh` and `session-share.sh` are the proof. Expose the index
builder as a module-level function so the test can count.

Test: `self/tests/session-claims.sh`, a `python3 - <<'PY'` block (sys.path insert of the
copied `analysis/`, as the other tests do): wrap `parse_manifest` in a counter, build
the index, call `session_claim_intervals` for three different session ids, and assert
the counter did not grow after the index was built.

## The facts

- Tests are plain bash under `self/tests/`, registered in TWO places in `self/gate.sh`:
  the `shell_scripts` array (for `bash -n`) and the `record "<label> self-test"` block.
  A new file goes in both; adding it to only the first parses it and never runs it. This
  feature adds no new test file — every assertion above lands in an existing one — unless
  you judge `feature-lifecycle.sh` (393 lines) too long, in which case a new
  `self/tests/window-stamp.sh` with the same scaffolding is fine, registered in both places
  and with its row in `self/tests/README.md`.
- Each test stands up its own world under `mktemp -d` re-resolved with `pwd -P` (macOS
  `/var` → `/private/var`; `roots.py` resolves physically and an unresolved path matches
  no transcript). Copy the scaffolding of the file you extend; do not invent another.
- `self/tests/fixtures/transcripts/build-transcript.sh` — `session_line` (11 args),
  `subagent_line`, `user_line` in some tests. Timestamps are `Z`-suffixed ISO.
- `capture_planning.py` is 2,300 lines. The parts this feature touches: `select_parent`
  (the `may span the window boundary` warnings and the share walk), `session_claim_intervals`,
  `annotate_frozen_record` and its call site in `capture_feature`, `share_ctx` in
  `capture_feature`, and `main()` for the new flag. Read those; do not read the file top
  to bottom.
- `in_window` is half-open: `from` inclusive, `to` exclusive. `is_empty_window`,
  `normalize_window`, `_iso_or_none`, `to_utc` exist — use them.
- `manifest.py` preserves fence formatting one key per line; `set-window-to` must keep
  doing so, and `get session_window.to` is how a test reads the result.
- `feature-close.sh`: the primary must be clean at entry (verified in "Refusals"), which
  is what makes every rollback a `git checkout --`. `MANIFEST_PY` and `CAPTURE_PY` arrays
  are how it calls the python. `--recapture` may run with the branch already deleted
  (`closed_feature_on_main`) — the evidence CLI must not need the branch.
- Named constants at the top of a file for every literal (the one-second offset is one).
- Every README of a touched folder is updated before you finish, per CONVENTIONS.md:
  `analysis/README.md` (CLI flags, the `feature-close.sh` ordering, the field list if you
  add a field — prefer not to), `self/tests/README.md` (the rows of every test you
  extend, naming each new phase), `LIFECYCLE.md` step 6, `feature-close.sh`'s header
  comment, and `AGENT_PLANS.md`'s `session_window` bullet ("Set `to` as soon as the
  feature is done…") so it does not contradict the close stamping from evidence.

## The procedure

`AGENT_DIRECT.md` → "The procedure", exactly, plus:

- Checkpoint at `self/features/claim-window-precision/CHECKPOINT.md`, rulings at
  `self/features/claim-window-precision/NOTES.md`, timing stamps via
  `./stamp-timing.sh --self claim-window-precision checkpoint status=<status>` (check
  `stamp-timing.sh`'s usage line for the exact `--self` position before the first call).
- Acceptance tests first, committed alone as `claim-window-precision: acceptance tests`.
- **For every new assertion, prove it red without its change** — revert the change
  locally (a copy of the file, restored after), run the test, confirm the FAIL, restore.
  Record in NOTES.md, per assertion, the mutation it was checked against. An assertion
  that passes without its change is not written yet.
- Do not run `feature-close.sh` against the real corpus, ever — only inside a test's
  throwaway checkout. Do not run `capture_planning.py --recapture` against the real
  corpus. `capture_planning.py --self --all` (no `--recapture`) is safe and is the check
  that nothing frozen moved: `git diff -- 'self/features/*/planning.json'` must show only
  `also_claimed_by` changes, if anything.
- Never mutate repo-wide VCS state: no stash, checkout of another branch, reset, rebase.
  `git checkout -- <file>` inside a test's throwaway checkout is that test's business.

## The finish

Gate to green (`bash self/gate.sh`; verdict `all checks passed`, no SKIP). Commit on
`claim-window-precision` — everything, including NOTES.md, CHECKPOINT.md at
`status: committed`, the manifest, the review brief already in `review/incomplete/`, and
the four BACKLOG entries removed. Commit message ends with:

    Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01VxZTtQTa3JKBocEpbdpg1Z

Do not push. Do not open the PR. The review pass does both.

## The report

Terse: the gate's verdict line and counts; files added/changed; each ruling and where it
is recorded; for each of the four items, the assertion that pins it and the mutation it
went red against; anything in scope left undone and why.
