# self

agentTooling's own plan corpus — the harness applied to itself. This is the exact
counterpart of a consuming repo's `plans/` directory, one level in, and it is drained by
passing `--self` to the runners:

```bash
./agentTooling/run-batch.sh --self <slug>    # build, then verify, then review
./agentTooling/run-plans.sh --self <slug>    # build pass only
./agentTooling/run-verify.sh --self <slug>   # verify pass only
./agentTooling/run-review.sh --self <slug>   # review pass only
```

| Path | What it is |
|---|---|
| `features/` | One directory per agentTooling feature: manifest, `auto/`, `verify/`, `review/`, `interactive/`, and the JSON cost artifacts. See `features/README.md`. |
| `interactive/` | Standing runbooks that outlive any one feature. A feature's own bash-heavy steps live in `features/<slug>/interactive/` instead. |
| `routing/` | One JSON record per **router** session — the session that ran `../feature-start.sh` — at `routing/<session-id>.json`, written by that script from the router's own transcript and committed in the `<slug>: start` commit, so the router-to-feature link is in git before the transcript expires. `{ session_id, launched_in, git_branch, model, started_at, ended_at, duration_s, cost_usd, features_started[{slug, at}], captured_at }`; see `../analysis/README.md` → `routing.py` for what each field is derived from. A router is never pinned into a feature (`../LIFECYCLE.md`, rule 1): its spend is routing overhead, reported per repo by `report.py --all` and never split across the features it opened. The consuming-repo counterpart is `plans/routing/`. |
| `BACKLOG.md` | What a finished feature found and deliberately left — one bullet each, phrased as the assertion that would catch it, with the feature that raised it. The counterpart of a consuming repo's `plans/BACKLOG.md`. An entry is removed by the feature that closes it, not when it is merely noticed again. |
| `PROJECT_FACTS.md` | The facts every agentTooling plan must pin — bash version, what stands in for a test runner, how the analysis scripts import each other. Read before authoring. |
| `gate.sh` | The mechanical gate `run-batch.sh --self` runs after the build pass, writing `gate-report.txt` for the verify and review passes to read. Syntax checks, the behavioural scripts in `tests/`, and one check that is neither: `hooks/wire-settings.py --self --check`, which fails when the committed `../.claude/settings.json` has drifted from the constants that generate it. |
| `tests/` | Behavioural checks the gate `record`s — the runner contracts (`level-sentinel.sh`, `tiered-gates.sh`), the feature lifecycle's (`feature-lifecycle.sh`: start — pinning nothing, committing a routing record, pruning the features that have merged, `--open` — the stub-brief refusal, the PR hook, close, and the window stamped from evidence rather than from the close's clock; `routing-record.sh`: the routing record's derivation and its two readers; `recover-at-close.sh`: the close pricing what the CLI never did), the cost tooling's (`cost-recovery.sh`, `capture-guard.sh`, `subagent-capture.sh`, `timestamps-are-utc.sh`), the plan-linting's (`check-plans.sh`), the update-sync's (`sync-check.sh`), the sweep's (`sweep.sh`), the direct build's milestone record (`direct-timing.sh`), the stale-sidecar contract (`stale-failed-sidecars.sh`: a retried plan's leftover `failed/` pair does not crash or skew the cost report), the stream capture's (`stream-capture.sh`), the hard-killed session's usage-limit routing (`usage-limit-kill.sh`), the batch's survival of a closed stdout (`batch-sigpipe.sh`), the two cost/time tables' marks for a figure nobody recorded (`report-footnotes.sh`), the template version/hash table (`template-versions.sh`, the one that reads the checked-in tree instead of a sandbox), the auto-approve hook's (`allow-repo-commands.sh`: every audited bypass refused, a chained `cd` and every ref-moving git command denied with their fixes, the harness's own entry points approved, simple brace lists approved; `hook-wiring.sh`: the settings merge adds and never removes, in both modes), and the corpus's plan numbering (`plan-numbering.sh`: the next stem continues the sequence past 99). See `tests/README.md`. |
| `pr.sh` | Opens the PR after a clean `--self` review pass. agentTooling's own copy of `templates/plans/pr.sh`; not written by `sync-plans.sh`, so keep it in step by hand when the template changes. |
| `worktree-setup.sh` | The setup hook `../feature-start.sh --self` runs inside a new feature worktree, before the gate. agentTooling's own counterpart of `templates/plans/worktree-setup.sh`; it does nothing, because this repo is bash and stdlib Python with no install step — it exists so the hook path is the same in both modes. |
| `open-session.sh` | The hook `../feature-start.sh --self --open` runs to put a coordinator session inside the new worktree, with the worktree path as its only argument. agentTooling's own counterpart of `templates/plans/open-session.sh`, carrying the same `template-version` (asserted by `tests/sync-check.sh`); it opens a Terminal.app window running `claude`. The one file here that may spell `cd <path> && <command>` — that string is handed to Terminal.app, not to the Bash tool, and its header says so. The path is single-quoted inside it, because the shell Terminal.app starts word-splits what it is handed and a worktree under a path with a space would otherwise open the session in the wrong directory, and so bill it to the wrong branch. No test runs its body; `tests/feature-lifecycle.sh` S5c–S5d read both copies as text. |
| `TRIAGE-2026-09-03-feature-execution-procedure.md` | Triage of the direct one-shot's cost-attribution and PR gaps, measured in vinylCatalogue on 2026-09-03: the documented steps, ten caveats with evidence, eight fixes in dependency order. Moved here because every fix lands in this directory; the input for the `feature-execution-procedure` self feature. |
| `DESIGN-2026-09-16-lifecycle-restructure.md` | Design record from the 2026-09-16 flow and cost audit: where the flow gates and records cost today and where it leaks (measured), the rule that replaces session pins (one coordinator session per feature, launched in its worktree; the starting session is a router with its own overhead category), capture on the branch before merge in place of a post-merge close, `sweep.sh` retired, the analyzable-command rule, tests, pinned facts, and the three features that carry it out in order. Also holds the remaining steps for `permissions-policy-inherit`, the last feature closed under the old flow. |
| `gate-report.txt` | Gate output. Gitignored — regenerated every batch. |
| `review-report.md` | The review pass's verdict, used verbatim as the PR body. Gitignored — regenerated every batch. |

## Not generated

A consuming repo's `plans/` stubs are written by `sync-plans.sh` from `templates/`, and
every one of them points back up at `../agentTooling/…`. From here those relative paths
are wrong and the "edit the template, not this file" banner would be a lie — this
directory *is* the source. Everything here is hand-written and stays that way;
`sync-plans.sh` does not touch it and takes no `--self` flag.

## Why costs land here, not in the host repo

A feature whose entire diff is under `agentTooling/` should carry its manifest, plans,
logs and cost records under `agentTooling/` too. Filing them in whichever repo happened
to vendor the subtree misattributes the work and strands it there — the next repo to
vendor agentTooling would have to recreate the history by hand. `plan-analytics` is the
worked example: it changed nothing outside this directory, and it lives here.

The execution model itself — state folders, resume semantics, the progress and usage
logs, how to read a failure — is documented once in `../RUNNER.md`, not repeated here.
