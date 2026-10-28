feature: agentTooling/self-corpus-identity

# Direct one-shot brief — self-corpus-identity

## Where

Worktree `/Users/sahildesai/dev/agentTooling-self-corpus-identity`, branch
`self-corpus-identity`, base `main`. Every command runs there, in absolute paths. The
primary checkout `/Users/sahildesai/dev/agentTooling` is NOT it — never touch it, and
never `cd` into it.

This is agentTooling's own corpus: `--self` everywhere, feature directory
`self/features/self-corpus-identity/`, gate `bash self/gate.sh` (~3 min, ~70 checks,
writes `self/gate-report.txt`; the verdict line must read `all checks passed`, and a
SKIP is not green). Timing stamps: `./stamp-timing.sh --self self-corpus-identity
checkpoint status=<status>`.

## Read, in this order

1. This file, then `AGENT_DIRECT.md` — the procedure you follow ("The procedure",
   "Checkpoint and resume"). Never stop to ask a question; nobody is listening.
2. `CLAUDE.md` (imports `CONVENTIONS.md`: README Rules 1–2 and named constants are
   binding).
3. `self/PROJECT_FACTS.md` — bash 3.2, no `set -e`, bare cross-imports in `analysis/`,
   the test conventions, "Artifact root vs session root".
4. `analysis/README.md` — the entry for `roots.py`, and the capture entry's paragraph on
   the share split and the claimant index (`build_claimant_index`), and the
   `manifest_pinned_subagents` paragraph ("Looked up by slug rather than by the
   `<repo>/<slug>` pair").
5. `analysis/roots.py` whole (short), then in `analysis/capture_planning.py`:
   `repo_identity`, `repo_display_name`, `build_claimant_index`,
   `session_claim_intervals`, and the other three `repo_identity(` call sites
   (`register_frozen_claims`, the annotation call in the `--all` loop,
   `capture_feature`'s `share_ctx`).
6. `self/tests/README.md`, then `self/tests/session-claims.sh` whole — the test you
   extend — and `self/tests/fixtures/transcripts/build-transcript.sh`'s header for the
   `session_line` signature.
7. `self/features/self-corpus-identity/README.md` — the manifest, already filled; its
   "Deliberately excluded" list is binding.

## The defect

`build_claimant_index` does `repo = repo_identity(features_dir.parents[1])`. For the
self corpus vendored into a consumer, `features_dir` is
`<consumer>/agentTooling/self/features`, so `parents[1]` is the vendored `agentTooling/`
directory, which has no `.git` of its own; `git -C <it> remote get-url origin` answers
with the **consumer's** origin. Every self-corpus manifest therefore enters the
consumer's claim set as `(<consumer origin>, <slug>)` while the ledger
(`~/.claude/subagent-claims.json`, written by the standalone checkout's `--self` runs)
holds the same feature as `(https://github.com/ssdesai/agentTooling.git, <slug>)`.
`session_claim_intervals` dedupes on `(repo, slug)`, so both survive: the feature is
counted twice, and `share_basis` names `<consumer>/<slug>`, a feature that does not
exist. Verified on session `ed088063` from vinylCatalogue: 13 intervals for 11 real
claimants, phantoms `vinylCatalogue/recovered-duration-lower-bound` and
`vinylCatalogue/tooling-backlog-2026-09-06`. The standalone `--self` run is unaffected
only because there `session_root(True)` happens to be the agentTooling checkout.

## Rulings (settled — do not reopen)

1. **The self corpus's identity is declared, not derived.** `analysis/roots.py` gains a
   named constant holding `https://github.com/ssdesai/agentTooling.git` — the same
   string `update.sh`'s `DEFAULT_REMOTE` and `README.md` → "Updating" name — with a
   comment on each side saying the other names it too. Its `repo_display_name` is
   `agentTooling`, so no second constant for the name. The module docstring gains the
   third root-like fact: artifact root, session root, and now corpus identity, with the
   one-line reason (the self corpus can only ever belong to agentTooling; a vendored
   copy has no `.git` to ask).
2. **One rule for "which repo does this corpus belong to".** Add one helper beside
   `repo_identity` in `capture_planning.py` — name it for what it answers, e.g.
   `corpus_identity(features_dir)` — returning the declared identity when
   `features_dir == features_root(True)` and `repo_identity(features_dir.parents[1])`
   otherwise. Route **all four** `repo_identity` call sites that answer that question
   through it: `build_claimant_index` (per features dir), `register_frozen_claims`,
   the `annotate_frozen_record` call in the `--all` loop, and `capture_feature`'s
   `share_ctx`. Under `--self` none of them asks `git` any more; for the enclosing
   corpus the answer is byte-identical to today. If you find a further place that
   writes or compares a *feature's* repo under `--self` (the ledger's subagent side,
   `--for`), route it too and say so in NOTES.md; a place that answers "which repo did
   this *session* run in" keeps `repo_identity(sessions_dir)`.
3. **The dedupe key stays `(repo, slug)`.** Do not compare on `repo_name`.
4. **No ledger migration.** Verified before this brief: all 12 agentTooling session
   claims in the real ledger carry exactly the declared string. Do not touch
   `~/.claude` from this build at all — no test reads or writes it
   (`self/tests/README.md`).
5. **`manifest_pinned_subagents` keeps its slug-only lookup.** Rewrite its docstring's
   rationale and the matching `analysis/README.md` paragraph so they describe the
   identity as it now is (declared) rather than "the checkout's own identity is the
   enclosing repo" — that sentence becomes false with this change.
6. **Tests that pinned the old fallback are updated, not preserved.** The existing
   fixtures have `.git` under `$AT`, so the self corpus's identity used to fall back
   to the directory name `agentTooling`; after this change it is the declared URL
   (display name still `agentTooling`). Any assertion or seeded ledger row in
   `self/tests/*.sh` that depended on the old string is changed to the new one. Check
   `claims-ledger.sh`, `session-claims.sh`, `subagent-capture.sh`, `feature-lifecycle.sh`
   (that one has a real bare `origin`; under `--self` its ledger rows now carry the
   declared identity, not the bare path). Do not weaken any assertion to make it pass.

## Acceptance tests (write first, commit as `self-corpus-identity: acceptance tests`)

Extend `self/tests/session-claims.sh` with a new numbered phase (10) that stands up the
**vendored** layout in a second sandbox, because the existing one is the standalone
shape (`$AT/.git`): an enclosing directory holding `.git` (a bare `mkdir .git` is enough
— `repo_identity` falls back to the enclosing directory's name, which is what a wrong
answer looks like), `agentTooling/` beneath it with no `.git`, the copied `analysis/`
scripts, transcripts filed under the **enclosing** directory's project path with `cwd`
the enclosing directory (that is where a session in a consumer runs from), and
`session_root(True)` therefore resolving to the enclosing directory. Assert, through
`share_basis` and the ledger only:

- 10a. a self-corpus manifest `claim-self-twin` pinning the session with a window
  appears in `claim-here`'s `share_basis` as `agentTooling/claim-self-twin`, source
  `manifest` — never `<enclosing name>/claim-self-twin`;
- 10b. with a ledger session claim seeded for the same feature under the declared
  identity (`repo` = the URL, `repo_name` = `agentTooling`, slug `claim-self-twin`)
  carrying a *different* window, `share_basis` holds exactly one entry for it, source
  `manifest`, with the manifest's `from` — it deduped against the ledger;
- 10c. `claim-here`'s own total equals the two-claimant split (compute it from the
  fixture as the existing phases do) and not the three-way split the phantom produced;
- 10d. after the capture, the ledger's own entry for `claim-here` carries `repo` equal
  to the declared identity and `repo_name` `agentTooling`, not the enclosing name.

Each must be red against the pre-change code. Prove it: run the new phase against
`main`'s `capture_planning.py`/`roots.py` (copy them from `git show main:...` into the
sandbox, or stash-free: check out the two files to a temp path) and record in
`NOTES.md` which assertions were red and the mutation. The rest of the file must stay
green throughout, including assertion 9's parse count.

Update the `session-claims.sh` row in `self/tests/README.md`.

## Docs

`analysis/README.md` (roots entry; the share/index paragraph's "`repo_identity` run once
per features dir"; the `manifest_pinned_subagents` paragraph), `analysis/roots.py`
docstring, `self/PROJECT_FACTS.md` → "Artifact root vs session root" gains the identity
line, `update.sh`'s `DEFAULT_REMOTE` comment names `roots.py`. `self/BACKLOG.md`: there
is no entry to close; add one for anything in scope you leave undone.

## The finish

Gate green, then commit on the branch — code, tests, docs, `NOTES.md`, `CHECKPOINT.md`
at `status: committed`. Do not push, do not open a PR, do not edit the manifest's fence.
Never mutate repo-wide VCS state: no stash, checkout, reset, clean, branch switch,
rebase.

## The report

Terse: the gate's verdict line and counts; files added/changed; each ruling you had to
make beyond the ones above and where it is recorded; the red-proof table; anything in
scope left undone and why.
