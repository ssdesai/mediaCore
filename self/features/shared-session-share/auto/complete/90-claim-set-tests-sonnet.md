# 90 — acceptance tests: the claim set

feature: agentTooling/shared-session-share — plan 2 of 6. A session claimed by more than
one feature is priced and timed by concurrent share; plan 89 asserts the arithmetic once
the claimants are known, and this plan asserts **who the claimants are** and where they
are read from.

Writes `self/tests/session-claims.sh` and registers it in `self/gate.sh`. **RED until
plan 91 lands.**

Depends on: `89-share-arithmetic-tests-sonnet.md` — it adds the optional `IS_SIDECHAIN`
argument to `session_line` in `self/tests/fixtures/transcripts/build-transcript.sh`, which
phase 5 below uses. Do not add it again; call `session_line … true`.

Executor note: file paths are authoritative — do not traverse ancestor READMEs before
editing. Update only the README files explicitly listed below.

Pinned facts:
- No test reads or writes the real `~/.claude`; export `HOME` to the script's own
  `mktemp -d` before calling anything under `analysis/`, and re-resolve that directory
  with `pwd -P` (`roots.py` resolves through `Path.resolve()`).
- The claims ledger is `$HOME/.claude/subagent-claims.json`. Two sections:
  `{"subagents": {<agent-id>: {…}}, "sessions": {<session-id>: [{…}, …]}}`. A **file
  carrying neither key** is the original flat `{<agent-id>: …}` map and is read as the
  subagents section entire — that is the shape on every machine today.
- A session claim records `{repo, repo_name, slug, selected_by, cost_usd, claimed_at}`
  today and gains `window: {from, to}` in plan 91. `repo` is the origin URL (or the
  directory name when there is none) and `repo_name` its last segment.
- The two corpora a capture reads are the agentTooling checkout's `self/features/` and
  the enclosing repo's `plans/features/`. In the throwaway tree, `$TMP/agentTooling` is
  the checkout and `$TMP/plans/features` is the enclosing repo's corpus —
  `self/tests/claims-ledger.sh` part D already stands both up; read how it does it before
  writing.
- bash 3.2: no associative arrays.

## Files

- Create `self/tests/session-claims.sh`
- Modify `self/gate.sh`
- Modify `self/tests/README.md`

## `self/tests/session-claims.sh`

Same scaffolding as `self/tests/session-share.sh` (plan 89) — read that file first and
mirror it rather than re-deriving from `capture-guard.sh`. Same `HERE`/`TMP`/`AT`/
`FAKE_HOME`/`PROJECTS` block, same `ok`/`fail`/`check`/`field`/`close_enough` helpers,
same `write_manifest` shape.

Header comment in the house style: what it guards (which features count as claimants of
one session, and from which of the three sources), the rule under test, and the numbered
assertions.

### The fixture

One session `33333333-0000-0000-0000-000000000003`, cwd `$AT`, branch `unclaimedBranch`,
four billable responses two hours apart from `2026-06-02T10:00:00.000Z` (output tokens
1000 / 1000 / 1000 / 1000, everything else zero, model `claude-sonnet-5`). One feature
`claim-here` in the self corpus pins it, window `2026-06-02T10:00:00Z` –
`2026-06-02T20:00:00Z`.

### The assertions

1. **A claimant in the other corpus is found from its manifest.** Write a second feature
   `claim-there` into `$TMP/plans/features/claim-there/README.md` pinning the same session
   with window `2026-06-02T14:00:00Z` – `2026-06-02T20:00:00Z`, and capture `claim-here`
   with `--self`. Its `share_basis` holds two entries; the second is
   `<enclosing repo name>/claim-there` with `source` `"manifest"`; and its
   `cost_usd.total` is three quarters of `session_cost_usd` (it owns the first two
   responses alone and half of each of the last two).
2. **A claimant in a third repo is found from the ledger.** Remove `claim-there`'s
   manifest, seed `$FAKE_HOME/.claude/subagent-claims.json` with a `sessions` section
   holding one claim on this id from `{"repo": "git@github.com:someone/otherRepo.git",
   "repo_name": "otherRepo", "slug": "claim-elsewhere", "window": {"from":
   "2026-06-02T14:00:00Z", "to": "2026-06-02T20:00:00Z"}}`, and re-capture. Same three
   quarters, `share_basis` naming `otherRepo/claim-elsewhere` with `source` `"ledger"`.
3. **A manifest claimant outranks the same feature's ledger entry.** Restore
   `claim-there`'s manifest with a *different* window (`2026-06-02T16:00:00Z` – `…20:00Z`)
   while the ledger still carries the phase-2 claim for it under its own `(repo, slug)`;
   re-capture; `share_basis` holds one entry for it, `source` `"manifest"`, carrying the
   manifest's `from`. The manifest is current and the ledger is a cache of what other
   captures did.
4. **A legacy claim with no `window` is read as unbounded and said so.** Seed a ledger
   claim on this session with no `window` key at all, from a repo in neither corpus;
   re-capture. It appears in `share_basis` with `from` and `to` both null, this feature's
   share is exactly half the session (an even split over the whole transcript), and the
   capture output carries a warning naming that feature and saying the claim predates
   recorded windows so the split is even. Seed it into a **flat** ledger file with no
   section keys as well, and assert that file still loads (the shape on every machine
   today) rather than being read as a session claim.
5. **A parent transcript's own sidechain lines are shared too.** Append a fifth response
   with `session_line … true` at `2026-06-02T16:00:00.000Z`, inside both claims, and
   assert `cost_usd.sidechain` is halved on this feature and that
   `cost_usd.total` still equals `main + sidechain`.
6. **The ledger records the window it claimed with.** After a capture, the ledger's
   `sessions["33333333-…"]` entry for `agentTooling/claim-here` carries
   `window: {"from": "2026-06-02T10:00:00+00:00", "to": "2026-06-02T20:00:00+00:00"}` —
   normalized instants, not the manifest's raw strings — so another repo's capture can
   read it. Assert the key exists and both bounds parse to those instants; do not assert
   the exact string form beyond that.
7. **A frozen record that is newly shared asks to be re-captured.** Capture `claim-here`
   alone (no other claimant anywhere), so its record is frozen unshared. Then add
   `claim-there`'s manifest and its ledger claim and run
   `capture_planning.py --self --all` with no `--recapture`. The record is *annotated*
   (`also_claimed_by` gains the other feature) and every figure is unchanged — assert the
   whole file is byte-identical with `also_claimed_by` stripped, the way
   `claims-ledger.sh` part C does — **and** the run prints a warning naming the slug and
   the session and saying the frozen figure predates the share rule and `--recapture`
   would rebuild it while the transcript survives.
8. **The subagent side is untouched.** A subagent transcript claimed by a second feature
   is still refused outright. Assert this by reference: capture a second feature pinning
   the same `agent-<id>` and check the run exits non-zero. One check, no new fixture
   beyond the `subagents/agent-<id>.jsonl` file; mirror how `subagent-capture.sh` builds
   it.

## `self/gate.sh`

**Two lists, both required** — the `shell_scripts` array `bash -n` parses
(`self/gate.sh:122-160`) and the `record "<label> self-test" bash self/tests/<name>.sh`
block that runs it (`self/gate.sh:180-196`). Add it directly after
`self/tests/session-share.sh` in each. Label: `session claims self-test`.

## `self/tests/README.md`

One entry for `session-claims.sh`, directly after the `session-share.sh` entry plan 89
adds. Same depth as its neighbours: the scaffolding it reuses, the fixture, the three
sources a claimant can come from and which assertion pins each, and that everything but
phase 8 was RED until plan 91.
