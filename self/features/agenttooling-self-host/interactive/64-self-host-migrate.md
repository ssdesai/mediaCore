# 64 — Migrate the corpora and push upstream

Feature: `agenttooling-self-host`, interactive. Run by hand, after plans 59–63 have all
finished. Every step here is `git`, `chmod` or a smoke test, which is why no build
executor can do it.

Moves `plan-analytics` — and then this feature itself — out of `vinylCatalogue/plans/`
and into `agentTooling/self/features/`, then pushes the subtree upstream.

## Before you start

`agentTooling/.gitignore` must already exist (plan 60). Check it, because the
consequence of getting this wrong is not local:

```bash
test -f agentTooling/.gitignore && echo present || echo "STOP — plan 60 did not land"
git check-ignore -v agentTooling/self/features/x/auto/complete/y.stream.jsonl
```

The second command must print a matching rule. `.stream.jsonl` files are 0.2–1.5 MB
each and there are nine of them in `plan-analytics`; the host repo's
`plans/**/*.stream.jsonl` pattern does **not** reach into `agentTooling/`, so without
this they get committed and then pushed to the shared remote, where every consuming repo
pulls them forever.

Working tree must be clean — `git subtree` refuses otherwise, including for unrelated
changes:

```bash
git status --porcelain
```

If plans 59–63's output is still uncommitted, commit it now, on its own, before anything
below. Keep it separate from `plan-analytics`'s output if that is also outstanding:
mixing the two features' diffs into one commit corrupts exactly the per-feature
attribution `plan-analytics` was built to produce.

## 1. Move `plan-analytics`

```bash
git mv plans/features/plan-analytics agentTooling/self/features/plan-analytics
```

`git mv` on a directory renames it on the filesystem, so the untracked-and-ignored
`.stream.jsonl` files travel with it and stay untracked at the new path — under
`agentTooling/.gitignore`'s rules now rather than the host repo's.

Confirm nothing large came along as a *tracked* file:

```bash
git status --porcelain | grep -c 'stream\.jsonl'    # must be 0
git diff --cached --stat | tail -1
```

## 2. Make the gate executable

```bash
chmod +x agentTooling/self/gate.sh
./agentTooling/self/gate.sh
```

A build executor writes files non-executable and has no shell, so plan 61 could not do
this. `run-batch.sh` tests `[[ -x "$GATE_SCRIPT" ]]` and *skips* a non-executable gate
without complaining, so the failure mode is a silently absent gate rather than an error.
The verify plan may already have applied the `chmod`; re-running it is harmless.

## 3. Smoke-test both modes

Nothing is queued in either corpus at this point, so the runners should say so and exit
0. **Pass the slug explicitly** in the error-path checks — a runner invoked with no slug
infers one from whatever is queued anywhere and would start a real run.

```bash
./agentTooling/run-plans.sh --self                        # "No plans queued under self/features/..."
./agentTooling/run-plans.sh --self no-such-feature        # errors, lists plan-analytics
./agentTooling/run-plans.sh no-such-feature               # errors, names plans/features/
```

The middle command is the one that matters: it proves the self corpus is being read and
that `plan-analytics` is now in it.

## 4. Re-capture `plan-analytics`'s cost against its new root

Its `planning.json` and `report.json` were written when it lived under
`plans/features/`. Regenerate them so the artifacts and their location agree:

```bash
python3 agentTooling/analysis/backfill_usage.py --self
python3 agentTooling/analysis/capture_planning.py --self plan-analytics
python3 agentTooling/analysis/report.py --self plan-analytics
python3 agentTooling/analysis/report.py --self --all
```

Then confirm the host repo's own trend still works and has simply lost this feature —
that is the intended attribution, not a regression:

```bash
python3 agentTooling/analysis/report.py --all
```

Check `report.py --self plan-analytics`'s total against the pre-move `report.md` you are
replacing. A materially different number means the move changed what the scripts can
see, which is a defect, not a rounding difference. `total_is_partial` flipping to true is
the specific thing to look for: it means a `usage.json` stopped being found.

Sanity-check the capture in particular — `session_root` under `--self` should have
resolved to the `vinylCatalogue` root, so `planning.json`'s `sessions[]` should be
non-empty and its `manifest_branches` should read `["browseImages"]`. An empty
`sessions[]` means the transcript lookup went to the wrong directory and fails silently.

## 5. Move this feature too

By the rule in `AGENT_PLANS.md` → "Which corpus a feature belongs in", this feature's
entire diff is under `agentTooling/`, so its corpus belongs there as well. It could not
start there — the runner could not read `self/features/` until plan 59 landed — but
there is no reason for it to stay behind.

```bash
git mv plans/features/agenttooling-self-host agentTooling/self/features/agenttooling-self-host
```

This file moves with it; re-open it at the new path if you need the remaining steps.
Then capture and report it, exactly as for `plan-analytics`:

```bash
python3 agentTooling/analysis/capture_planning.py --self agenttooling-self-host
python3 agentTooling/analysis/report.py --self agenttooling-self-host
```

`capture_planning.py` warns when two features share a branch and neither declares a
`session_window`. Both manifests declare one (`plan-analytics` from `15:49`, this one
from `16:10`), so the warning should be absent. If it fires, one of the two windows is
wrong and the planning cost is being double-counted — fix the manifest and re-capture
both.

## 6. Commit and push upstream

```bash
git add -A
git commit
git status --porcelain            # must be empty before the next step
git subtree push --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main
git subtree pull --prefix=agentTooling https://github.com/ssdesai/agentTooling.git main --squash
```

**The pull after the push is not redundant** and skipping it breaks the *next* push, not
this one — `subtree push` writes nothing locally, so the recorded split stays stale and
the branch rebuilt from it will be behind the remote. `agentTooling/README.md` →
"Updating" explains the failure and why neither `git pull` nor a force-push is the fix.

The pull should change no files, since the content is what you just sent.

Do **not** run `./agentTooling/sync-plans.sh` afterwards, despite the usual
post-pull rule: it regenerates the host repo's `plans/` stubs, and this pull carried no
template changes. Running it is harmless, just noise.

## 7. Confirm the round trip

```bash
git log --oneline -3
ls agentTooling/self/features/
```

Both features should be listed, and `plans/features/` should now hold only
`vinylCatalogue`'s own: `collection-selection`, `core-library-and-gui`,
`extractor-backends`, `image-versions-and-copies`, `manual-readings-and-browse`.

From here, the next agentTooling feature is authored directly into
`agentTooling/self/features/<slug>/` and run with `./agentTooling/run-batch.sh --self
<slug>` — the bootstrap is over.
