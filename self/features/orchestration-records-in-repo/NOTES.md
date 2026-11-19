# orchestration-records-in-repo — rulings

Raised by a consuming repo's coordinator (2026-11-12): its coordinator record was written
under the vendored `agentTooling/self/orchestrations/<slug>/`, and `report.py
--orchestration` resolved each feature's `report` (`plans/features/<slug>/report.json`)
against `agentTooling/`, so both features came out unpriced (`$13.54` + `$8.14` missing
from a `$23.70` total). The only path that would have resolved started with `../`, which
the shell policy refuses. Two defects: the record lived in the vendored subtree (a local
edit to a directory that ships to every repo), and report paths were resolved against the
wrong root.

## Rulings

1. **A record lives in the corpus of the checkout it was started in, exactly like a
   feature.** `roots.orchestrations_root(self_mode)`: `--self` → `<agentTooling>/self/
   orchestrations/` (unchanged); otherwise → `artifact_root(False)/plans/orchestrations/`,
   the sibling of `plans/features/`. Rationale: the coordinator's cost belongs to the
   repo whose features it ran; a record inside the vendored subtree is an edit to shared
   code. `--arm-root` applies to it as it does to `features_root(False)`.
2. **`--self` is added to every record tool, worded by `roots.add_self_flag`:**
   `orchestration-start.sh`, `orchestration-capture.sh`, `manifest.py --orchestration`,
   `report.py --orchestration`, `analysis/orchestration_capture.py`. Default is the
   consuming repo, as for `feature-start.sh`. Every agentTooling-side caller that means
   agentTooling's own records (self tests, `templates/plans/ORCHESTRATOR_SESSION_BRIEF.md`
   as used in agentTooling, docs examples for self work) passes `--self`.
3. **Report paths resolve against the record's own repository root** — `artifact_root(
   self_mode)` — not the agentTooling directory. `--checkout <repo>=<path>` still wins
   for a feature in another repository. The `ORCH_HOME_REPO = "agentTooling"` constant
   is replaced by the home repo's name for the mode (`--self`: agentTooling; otherwise
   the consuming repo's name as `capture_planning.corpus_identity`/its basename gives it,
   compared case-insensitively — `roots.feature_mention_key` precedent). A missing
   report in the home repo is `UNPRICED_PATH_MISSING`; in another repo with no checkout,
   `UNPRICED_NEEDS_CHECKOUT` as before.
4. **The role hook reads both roots.** `hooks/orchestrator_role.py`'s
   `record_for_session` scans `<tooling>/self/orchestrations/` and
   `<tooling>/../plans/orchestrations/` (sorted, self first), so an orchestrator recorded
   in either is refused, and a legacy record a consumer already has under its vendored
   `agentTooling/self/orchestrations/` keeps its role. `ORCHESTRATIONS_REL` becomes the
   pair, mirrored against `roots.py` (test U3 updated). `coordinator_check.py` reads both
   roots the same way.
5. **A legacy record is moved, not read in place.** `report.py --orchestration <slug>`
   (no `--self`) with no `plans/orchestrations/<slug>/` but an
   `agentTooling/self/orchestrations/<slug>/` refuses, printing the move:
   `git mv agentTooling/self/orchestrations/<slug> plans/orchestrations/<slug>`. Same for
   `manifest.py --orchestration` and `orchestration-capture.sh`. Rationale: a silent
   fallback keeps writing into the subtree; one move per legacy record ends it.
6. **The experiment harness keeps old arms working.** `harness/program-stages.sh`'s
   `PROGRAM_RECORD_ROOT` reads `plans/orchestrations` and falls back to
   `agentTooling/self/orchestrations` when only the old one exists (an arm on an old
   agentTooling writes the old path).
7. **`templates/plans/README.md` names `orchestrations/`** (generated into each
   consumer's `plans/README.md`), and LIFECYCLE.md → "Orchestration records",
   ORCHESTRATION.md → "Coordinator shapes", `self/orchestrations/README.md`,
   `analysis/README.md`, `hooks/README.md` and README.md say where a record lives per mode.

## Rulings made in the build

8. **`--self` is the first word of the shell tools, as in `feature-start.sh`.**
   `orchestration-start.sh [--self] <slug> …` and `orchestration-capture.sh [--self] <slug>`
   read it through `plan-runner-roots.sh`'s `resolve_roots` (`SELF_MODE`, `REPO_DIR`,
   `SELF_ARG`), so their root is the one every lifecycle script uses. `manifest.py` takes
   `--self` before `--orchestration` (its scope word is still recognised first, or second
   after `--self`).
9. **The start refuses a legacy slug too** (not only report/manifest/capture): a slug with a
   folder at `agentTooling/self/orchestrations/<slug>` is refused with the same `git mv`
   line (the shell mirrors `roots.LEGACY_RECORD_REFUSAL`), so a second record for the slug
   cannot be started beside the old one.
10. **`report.compute_orchestration_report` gained `home_repo=None`**: `None` treats every
    entry as the record's own (no `--checkout` demand); `run_orchestration` passes
    `orchestration_home_repo(self_mode)` = `repo_display_name(corpus_identity(features_root(
    self_mode)))` (lazy import of `capture_planning`, which report.py otherwise avoids).
    A consumer with no origin falls back to its directory name, as the brief header does.
11. **Harness fallback is a function, `program_record_root`**: the new root unless only the
    legacy folder holds the program's record. `smoke.sh` now asserts the pushed record at
    `plans/orchestrations/…`; the arm is the committed `HEAD`, so that holds from the commit
    that carries the new `orchestration-start.sh` on (an uncommitted tree runs the old start
    and exercises the fallback instead).
12. **Existing agentTooling-side callers pass `--self`**: `orchestration-records.sh`,
    `coordinator-records.sh`, `orchestrator-role.sh` (their fixtures are agentTooling's own
    checkout); the briefs say `[--self]` per mode. `hook-orchestrator-role.sh` only feeds
    command strings to the hook policy, which does not read the flag, and is unchanged.
13. **Acceptance tests were committed after the code was first written** (the tree already
    held the implementation when the new test file was authored), so they were green when
    committed rather than red; the contents are black-box through the real scripts.

## Round 2 rulings (coordinator, from `escalations/01-review-opus.md`)

14. **A vendored record is "stranded" only when it is the consumer's own; agentTooling's
    shipped records are never moved.** `git subtree` vendors all of `self/`, so a consumer's
    `agentTooling/self/orchestrations/` always holds agentTooling's own records. One
    classifier in `roots.py`, used by every record tool and mirrored in
    `orchestration-start.sh`: a legacy folder is stranded iff its record's LAST fence lists a
    feature whose `repo` matches the consuming repo's name case-insensitively (the same home
    name `report.py` uses, ruling 10). Only a stranded record gets the `git mv` advice.
    A non-stranded one is agentTooling's own: `report.py`/`manifest.py`/
    `orchestration-capture.sh` without `--self` say "no record at
    `plans/orchestrations/<slug>`; `agentTooling/self/orchestrations/<slug>` is agentTooling's
    own record — read it with `--self` from an agentTooling checkout", and the start is NOT
    refused for that name (the folders differ; nothing collides). This narrows ruling 9 to
    stranded records. Rationale: the fence's features are the evidence of whose cost it is;
    a record with no features yet carries no claim and is left alone.
15. **Without `--self`, every record tool refuses in agentTooling's own checkout.** When the
    tooling directory is itself a checkout root (`.git` in it — `roots.checkout_of(AT) ==
    AT`, the shell's `TOPLEVEL == SCRIPT_DIR`), there is no consuming repo, so a no-flag
    `orchestration-start.sh`, `orchestration-capture.sh`, `manifest.py --orchestration`,
    `report.py --orchestration` and `orchestration_capture.py` refuse before writing,
    naming `--self`. One message constant in `roots.py`, mirrored in the shell. Refuse
    rather than default to `--self`: every other lifecycle tool treats the no-flag form as the
    consumer's, and a silent default would make one command mean two things.
16. **The role hook scans the parent's `plans/orchestrations/` only from a vendored copy**
    (`hooks/orchestrator_role.py` `record_roots`: skip it when `<tooling>/.git` exists), so a
    standalone checkout's role can never come from a directory outside any repository.
17. **The coordinator advisory names the mode's flag.** `analysis/coordinator_check.py`'s
    `UNCLAIMED_TEMPLATE` prints `orchestration-start.sh --self <slug> …` when it runs for a
    `--self` start, and no flag otherwise.

## Round 2 rulings made in the build

18. **The shell asks the Python classifier; it does not re-implement it.** The stranded test
    needs the consuming repo's name (`capture_planning.corpus_identity`), which a shell cannot
    reproduce, so `roots.py` gained a CLI, `python3 roots.py stranded <slug>` (exit 0 stranded,
    1 not), and `orchestration-start.sh` calls it. The two refusal texts and the two relative
    roots are the shell's mirrored constants, asserted by R3/R7/R10.
19. **`--arm-root` is never "standalone".** `roots.is_standalone_checkout()` is false when an arm
    root is set: the harness driver runs from agentTooling's own checkout and names the consuming
    worktree explicitly, so the refusal would break it.
20. **`orchestration_home_repo` moved from `report.py` to `roots.py`** (lazy import of
    `capture_planning`, which imports `roots`), so the classifier and the report share one name.
    `legacy_record_refusal` is replaced by `record_refusal` (standalone, then stranded or
    own-record), the one call every record tool makes.
21. **`coordinator_check.py` takes `--self` as an optional third argument**; `feature-start.sh`
    passes its existing `SELF_FLAG`. The hook's standalone test is `<tooling>/.git` exists
    (`GIT_ENTRY`, mirroring `roots.py`).
22. **R9's `feature-start.sh` check is a grep of the call line**: the advisory runs only under
    the cloud profile with a router session, which no fixture here stands up.

## Round 3 rulings made in the merge

Round 3 merges `origin/main`, which gained `hook-role-hardening` (PR 140) — written when every
record lived under the tooling directory (its NOTES.md, F1(a): "they are always under
`agentTooling/self/orchestrations/`"), which this feature changed.

23. **Every role source spans both roots, in one order: self, then (vendored only) the
    consumer's.** `record_bases(tooling_dir)` gives the `(base, rel)` pairs, `record_roots` is
    built from it, and the working-tree scan, the history (`committed_role_record`) and the
    ledger path all walk it. Rationale: rulings 4/16 decide WHERE a record may sit;
    hook-role-hardening decides HOW it is read — the merge composes them, so a consumer record
    keeps the committed-record and every-fence protections a self one has.
24. **The consumer's history is read with `git -C <consuming repo> log --relative -- plans/
    orchestrations`, not from the tooling directory.** `--relative` from `agentTooling/` would
    hide every path outside it; running from the parent needs no `..` path. One bounded call
    per root (R6's deadline per call), and a root whose history cannot be read is unreadable
    only when no other source names the session (R4 unchanged).
25. **`committed_role_slug` became `committed_role_record`, returning the path.** A slug no
    longer says which root it came from; the path does. No caller outside the module used the
    old name, so no shim was kept (one definition of each rule).
26. **A ledger line, which carries only a slug, names the first root holding `<slug>/`, else
    the last root** (`ledger_record_path`): the consumer's from a vendored copy, where a no-flag
    start writes. The path only labels the refusal; the role is the line itself.
27. **The orchestrator allowlist admits `--self` on `manifest.py` and `report.py`, first word
    only** (`ORCHESTRATOR_SELF_FLAG`). Without it an orchestrator in agentTooling's own checkout
    could not run its record tools at all (ruling 15 refuses the no-flag form there).
    `orchestration-start.sh`/`orchestration-capture.sh` already took any argument but
    `--session`. `--self` without `--orchestration`, or after it, stays denied: one spelling.
28. **A consumer's settings ask before an Edit under `plans/orchestrations/` as well**
    (`wire-settings.py` `POLICY_ASK_RULES` gains `Edit(**/plans/orchestrations/**)`; the
    legacy `Edit(**/agentTooling/self/orchestrations/**)` stays, since a legacy record keeps its
    role until moved). Hook-role-hardening's F1(a) guarded "where records are"; that is now
    both. Spelled `**/` like its siblings so a worktree's copy is covered. The `--self`
    spelling stays dropped (its F9) — agentTooling's own `.claude/settings.json` is unchanged.
29. **The audit paths are unchanged.** They are the files that ENFORCE the role (the hook,
    `analysis/`, the scripts), not the records; `analysis/roots.py`, this feature's one new
    enforcement module, is already under `analysis/`. Nothing about a record's root moves them.
30. **hook-role-hardening's new start calls in agentTooling-shaped fixtures pass `--self`**
    (`orchestrator-role.sh` G10b/h/i, `coordinator-records.sh` K1's session-id and symlink
    cases), as ruling 12 did for the older ones. Their fixtures are standalone checkouts, where
    ruling 15 refuses the no-flag start — so G10b/G10i/K1's accept cases failed, and the
    session-id REFUSAL cases passed for the wrong reason (the standalone refusal, also exit 1,
    writing nothing). With `--self` each refusal is the one it names. Intent unchanged, nothing
    weakened; the consumer root is covered by `orchestration-records-in-repo.sh` R11 and
    `hook-orchestrator-role.sh` H25 rather than by re-shaping these fixtures.
