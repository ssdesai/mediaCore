# 01 — review: subtree-pull-keeps-base

## What the feature was supposed to do

In the pr97 propagation round, `./agentTooling/update.sh` conflicted in three consuming
repos (mediaCore, vinylCatalogue, musicMap). The conflicts were in four vendored docs
(LIFECYCLE.md, ORCHESTRATION.md, README.md, self/README.md) that none of them had edited.
humanNetworkMap pulled clean. The brief asked for:

1. **A diagnosis first**, recorded as a ruling in `NOTES.md`. The hypothesis to verify, not
   assume: a conflicting `git subtree pull --squash` is committed by hand, without the
   `git-subtree-*` trailers, so the next pull cannot find its base.
2. **The smallest fix in `update.sh`**, and in whatever shares its logic, that makes the
   next pull clean and keeps every later pull clean:
   - a conflicting pull's resolution keeps what git subtree's base lookup needs;
   - an explicit base recovery when no trailer is found, if that is cleanest;
   - a `--check`-style diagnostic that reports a broken chain.
3. **Docs**:
   - `LIFECYCLE.md` → "## Propagate": what a session does when the pull conflicts (take
     upstream when there are no local edits, and how the trailer chain is kept);
   - `README.md`: the `update.sh` entry, plus the one-time step or automatic repair for
     the consumers already affected.
4. **A self-test under `self/tests/`**: a tiny upstream and consumer, a pull, a conflict
   hand-resolved the old way, and the next pull clean with the fix. Registered in
   `self/gate.sh` and `self/tests/README.md`.
5. What the next propagation round must do, recorded in `NOTES.md`.

The parent session added two requests:
- `--check` flags a base that is a mainline commit, the "fragile" state, even though the
  pull still works;
- the anchor's trailers sit in a proper trailer block.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

Expect changes to:
- `update.sh`
- `self/tests/subtree-chain.sh` (new)
- `self/gate.sh`, `self/tests/README.md`
- `LIFECYCLE.md`, `README.md`, `ORCHESTRATION.md`
- this feature's `README.md` and `NOTES.md`

## Contracts to hold it to

- **The diagnosis.** `NOTES.md` 1 and 2 must agree with `git subtree`'s real base lookup.
  Read `find_latest_squash` and `cmd_merge` in `$(git --exec-path)/git-subtree`. Is the
  claim that a hand-committed merge with `MERGE_HEAD` kept is harmless correct? Is the
  claim that the chain breaks only when the squash commit becomes unreachable correct?
  The real-history evidence in `NOTES.md` 2 is the parent session's; check that it
  supports the ruling as written. Do not try to clone the consumers.
- **`latest_squash` replays `find_latest_squash`.** Same `--grep` pattern; every message
  line read with leading blanks dropped; the last split line wins; a mainline line means
  use `^2`. A divergence means `update.sh` judges a different base from the one the pull
  then uses.
- **`chain_state`**:
  - `broken` only when the vendored tree equals some upstream commit's tree other than
    the recorded split's;
  - `edited` never re-anchors;
  - `fragile` exactly when the base commit's tree holds `<prefix>` as a subdirectory.
  Look for a state that would re-anchor a repo with real local edits, or report `intact`
  for a base the pull would not use.
- **The anchor.** After it, the base git subtree finds must be the parentless squash
  commit, and the pull must merge cleanly from it. Under a GitHub squash-merge that keeps
  bodies, the anchor must not make `find_latest_squash` die. In particular, the merge's
  message must hold no `git-subtree-mainline:` line or anything else starting a line with
  `git-subtree-`. The anchor merge must change no file.
- **Existing behaviour unchanged**:
  - the refusals and their order (source checkout, branch/feature, dirty tree);
  - the cloud `remedy` line, exactly once, now that a fetch precedes the pull;
  - stdout and stderr kept apart;
  - no `update-pull.*` temp file left behind;
  - the `split` line;
  - the step-5 rule that nothing after `main "$@"` is read.
  `self/tests/propagation-pull.sh` and `self/tests/update-cloud-branch.sh` must pass
  unmodified.
- **`--check`** writes nothing but `FETCH_HEAD` and exits 1 on `broken` or `none` only.
  `--check --base` is a usage error.
- **The conflict guidance.** The `resolve` command it prints (`git checkout --theirs --
  <prefix>`, add, commit) must actually leave the chain `intact`; C8 asserts this. It must
  never advise `git merge --abort`.
- **The docs** say the same thing in `LIFECYCLE.md` → "Propagate" (step 2 and step 7),
  `README.md` (the `update.sh` entry and "Updating") and `ORCHESTRATION.md`'s round note.
  That includes the one-time caveat: the pull that brings this change in still runs the
  old `update.sh`.
- **Conventions**: named constants for magic values, `CONVENTIONS.md` shell shape in the
  docs' examples, every touched folder's README current, and `./self/gate.sh` green.

"No findings" is a legitimate verdict. Escalate only for a real defect: a wrong base
judged, a repair that can make a pull worse, a broken existing contract, a doc that tells
a propagation session to do the wrong thing.

## Verdict
