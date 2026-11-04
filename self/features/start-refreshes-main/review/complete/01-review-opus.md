# 01 — review: start-refreshes-main

## What the feature was supposed to do

`feature-start.sh` runs from the primary checkout's copy of agentTooling but branches from
`origin/<base>`. When the primary's `main` lags `origin/main`, a stale script writes and
commits files into a branch whose code expects a different layout. On 2026-09-21 a
consuming repo's primary at agentTooling `f07016a7` started a feature off `df3ee153`; the
old script `git add`-ed `plans/routing/<session>.json`, the path the new `routing.py` no
longer writes, and the `S: start` commit failed half-way through the start.

The fix: right after the fetch, and before anything is pruned or created, the script
compares the primary's `HEAD` with `origin/main`:

- no `origin`, a failed fetch, or no `origin/main` → carry on as before;
- `HEAD` is `origin/main`, or ahead of it → carry on;
- `HEAD` behind `origin/main` → fast-forward the primary's `main` to it
  (`git merge --ff-only`), print what moved, print the exact command to run again, and
  **exit** with a code of its own — no worktree, no branch, no prune. The running process
  is the old code; only a fresh run is the new code;
- the primary not on `main`, diverged from `origin/main`, or a fast-forward git refuses
  (a local change in the way) → refuse, touching nothing, and say why.

Second, the git-deny reason in `hooks/allow-repo-commands.sh` told a session that only
the human runs `feature-start.sh`; LIFECYCLE rule 2 says the human or a router session.
The session believed the hook and built in the primary instead. The reason must name the
session as a legitimate runner.

## The diff

Base is `main`. `git diff main...HEAD --stat`, then the full diff.

## Contracts to hold it to

- The check is against `origin/main` whatever `--base` is: the primary tracks `main`, and
  that is the copy of the script that runs.
- Nothing is written before the freshness check that a refusal or the update-exit would
  leave behind, other than the idempotent info/exclude entry that was already there.
- The re-run command printed is the one the user typed, flags and all, and runs as-is.
- The update-exit's code is distinct from success (0), usage (2) and refusal (1), and is
  documented in the header's exit-code line.
- The header comment's claim that the primary's tracked tree is never touched is
  corrected, not left contradicting the code.
- LIFECYCLE.md step 2, the root README's `feature-start.sh` entry, `hooks/README.md`'s
  copy of the deny reason, and any other place that describes what the start does are
  consistent with the new behaviour.
- `./self/gate.sh` is green.
- Named constants per CONVENTIONS.md for any new literal that carries meaning.

"No findings" is a legitimate verdict.

## Verdict
