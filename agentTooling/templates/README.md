# templates

Source for the generated files in a consuming repo's `plans/` tree. **Edit these, not
the copies in `plans/`** — `../sync-plans.sh` overwrites the generated stubs on every
run.

```
plans/README.md              generated — synced every run
plans/interactive/README.md  generated
plans/features/README.md     generated
plans/features/TEMPLATE.md   generated
plans/.gitignore             generated
plans/PROJECT_FACTS.md       repo-owned — seeded once from the skeleton, never overwritten
plans/BACKLOG.md             repo-owned — seeded once, never overwritten
plans/gate.sh                repo-owned — seeded once, never overwritten
plans/pr.sh                  repo-owned — seeded once, never overwritten
plans/worktree-setup.sh      repo-owned — seeded once, never overwritten
plans/open-session.sh        repo-owned — seeded once, never overwritten
plans/environment.sh         repo-owned — seeded once (not executable: it is sourced), never overwritten
plans/cloud-setup.sh         repo-owned — seeded once, never overwritten
```

`plans/TEMPLATE_VERSIONS` is not synced anywhere: it is the version-and-hash table for
the six repo-owned scripts, described under `template-version` below.

The five stubs are repo-agnostic on purpose: each describes its folder and points at
`agentTooling/RUNNER.md` for the execution model, so that model is documented once
rather than restated (and drifted) per repo. That is also why overwriting them is
safe — they hold nothing a repo could have customized.

`.gitignore` is generated rather than an install instruction because nothing detects a
missed instruction: a repo that skipped the hand-written gitignore step committed a
per-level gate report on every batch, and only a human reading a diff would notice. Its
five patterns (`gate-report*.txt`, `**/*.stream.jsonl`, `**/*.logfifo`, `/gate-state/` —
the resumable gate's per-check results, so they never dirty the tree they describe — and
`/review-report.md`) are relative to `plans/`, so an equivalent `plans/**/…` pattern in
the repo's root `.gitignore` from an earlier install is redundant rather than wrong. The
last is anchored where the first three are not, and deliberately: `plans/review-report.md` is
rewritten every batch, while a feature's archived copy of the same verdict
(`plans/features/<slug>/review-report.md`) is committed as that batch's record — an
unanchored pattern would silently stop the next one being added. The file is a real
`.gitignore` while it sits here too, which is harmless: nothing under `templates/plans/`
matches those patterns.

`gate.sh`, `pr.sh`, `worktree-setup.sh`, `open-session.sh`, `environment.sh` and
`cloud-setup.sh` are seeded into `plans/` once and then owned by the repo. The gate
skeleton takes an optional level label (`gate.sh NN`) and writes `gate-report.NN.txt`
beside `gate-report.txt`. At `template-version: 3` it sources `plans/environment.sh` when
present and is **resumable** (`../self/DESIGN-2026-10-05-cloud-execution.md` §8): each
check's result goes to `plans/gate-state/<tree-sha>/<label>` (the label sanitised for a
filename) as it finishes, and under `GATE_RESUME=1` — which the runners and
`../feature-start.sh` set — a check whose **pass** is recorded for the same tree with the
same command line is skipped and its recorded section reused, so a gate killed with its
container re-runs only what had not finished and still writes a complete report. A
recorded failure always re-runs. The tree sha is `git write-tree` over the checkout with
untracked files included, through a temporary `GIT_INDEX_FILE` seeded from the real index
(never touched), with the gate's own `gate-report*.txt` and `gate-state/` and the whole
`plans/features/` corpus (the runners' timing, plan moves and sidecars, written between
gate runs, which would otherwise keep every runner-started gate from resuming) taken back
out — so a check that reads the corpus resumes across corpus edits;
no git or a failed write-tree means no sha, and then everything runs. Only the current
tree's directory is kept. A repo's own checks keep resuming as long as they go through
`record`/`record_info`. The PR skeleton creates **no branch at all** — the feature
already ran on its own, in the worktree `../feature-start.sh` made — and opens the PR
from whatever is checked out against `FEATURE_BASE`, which `../feature-close.sh` exports
from the manifest's `base`, so a stacked feature targets the one beneath it without
waiting for a merge. Version 4 added its **second entry point**, `pr.sh --merge-request
<slug>`: the close calls it after the cost record has been committed and pushed, and it is
the only place `PR_AUTO_MERGE` is read, so nothing can ask a forge to merge a branch whose
record is not on it yet. The skeleton is at `template-version: 6`. Version 5 handed the
GitHub part of the open path to `../forge.sh` — `pr-find`, else `pr-open`, over `gh api`
REST — found through `FORGE_SCRIPT`, which `../feature-close.sh` exports, or
`./agentTooling/forge.sh` from the repo root when run by hand; version 6 sends the merge
request there too — `pr-find` for the open PR's url, then `forge.sh auto-merge <url>`,
which asks `gh pr merge --auto --merge` on a laptop and the proxy's `ccr/auto_merge` REST
route in a Claude Code cloud container (`../env-profile.sh` decides which; no adapter, no
PR found or a refusal is a warning and exit 0, as before). It has no `gh auth status`
probe: the only `skip` (exit 0) left is a repo with no forge CLI at all, and a forge that
refuses is a non-zero exit. A repo on another forge replaces the `forge.sh` calls with its
own CLI (`../README.md` → "Adopting the forge adapter"). `worktree-setup.sh` is a no-op skeleton whose comments list the common steps —
a venv per worktree (never shared: an editable install points at whichever tree ran it
last), `npm install`, a per-worktree dev port; `../feature-start.sh` runs it inside
every new feature worktree and stops the start if it exits non-zero
(`../LIFECYCLE.md`). At `template-version: 2` it first sources `plans/environment.sh`
when present, so an `npm install` there already sees the browser path.

`environment.sh` and `cloud-setup.sh` are the two **environment adapters** of
`../self/DESIGN-2026-10-05-cloud-execution.md` §7, both at `template-version: 1`, both
asking `../env-profile.sh` — the one place the profile is decided — through its functions
and never spelling its variables:

- **`environment.sh`** holds **facts, never exceptions**: the DB connection, the browser
  path (`PLAYWRIGHT_BROWSERS_PATH`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` where the CDN is
  blocked), anything else that differs between a laptop and a Claude Code cloud
  container. It is **sourced, never executed** — by the gate, `worktree-setup.sh` and
  the repo's own scripts — so it is seeded without the executable bit and refuses (exit 2,
  naming `.`) when run as a program; it must stay quiet and safe under `set -u` and
  `set -e`. The skeleton sources the detector and carries a commented example of each
  profile, and no `brew`: a container has none.
- **`cloud-setup.sh`** is the **once-per-container** step: start Postgres, create the
  role, write what `environment.sh` reads (all commented examples in the skeleton, which
  otherwise prints one "nothing configured" line). `../sync-plans.sh` wires it as a
  `SessionStart` hook in the repo's `.claude/settings.json` (`../hooks/README.md`), merged
  like the `PreToolUse` entry — added once, never doubled, a customised entry kept. The
  entry has no guard: **the script is the guard** — it exits 0 at once unless
  `profile_is_cloud`, and does nothing at all with no `agentTooling/env-profile.sh` beside
  it — so the same committed settings serve laptops and containers. A session starts
  again on resume and after compaction, so every step in it must be idempotent.

**The alternative to `cloud-setup.sh` is the cloud environment's own setup script** — the
"Setup script" in the Claude Code cloud environment's settings, which runs while a new
session's container is prepared, before Claude Code starts in it and so before the
repository's settings are read. It lives with the environment, not the repo: editing it
is a settings change nobody reviews in a diff, and it applies to every repo the
environment serves.
Prefer it when the work is **about the machine rather than the repo**: installing
packages or a toolchain the image lacks, anything slow that every session would otherwise
wait on, anything that must exist before Claude Code reads `.claude/settings.json`. Prefer
`cloud-setup.sh` for what belongs **with the repo's history**: services its tests need
(start Postgres, create the role), values `environment.sh` reads, anything that changes
with the code and should be reviewed with it. A repo can use both — the environment's
script installs, `cloud-setup.sh` starts and configures — and a repo that does everything
in the environment's script leaves `cloud-setup.sh` as the skeleton, which costs one
line of output per session. Nor is a settings file a case for the environment's script, or
for a `SessionStart` hook: a permission policy must be loaded before the first tool call,
and only a file present at startup is — agentTooling's own checkout tried a `SessionStart`
hook that generated its policy into an untracked file, and the policy missed the first
call in 3 of 15 fresh sessions. So a generated policy is committed: agentTooling's own
`.claude/settings.json` is generated by `../hooks/wire-settings.py --self` and tracked,
and a fresh clone is wired by the repo alone (`../self/PROJECT_FACTS.md`,
`../self/features/self-cloud-bootstrap/NOTES.md`). `open-session.sh` is the hook the same script runs under `--open`,
with the new worktree's absolute path as its only argument: its job is to put a
coordinator session *inside* the worktree, because a session is billed to the branch of
the directory it was launched in and that is where a feature's work is claimed with no
pin. It ships opening a Terminal.app window running `claude` through `osascript`, and is
the one place in this subtree where a `cd <path> && <command>` string may be written —
the string is handed to Terminal.app, not to the Bash tool, and its own header says so.
It is an **adapter** (`../self/DESIGN-2026-10-05-cloud-execution.md` §1) and at
`template-version: 4`: when `AGENTTOOLING_PROFILE` — exported by the start's
`../env-profile.sh`, the one place the profile is decided — is `cloud`, it prints that the
session is already in the feature's checkout and opens nothing, since a cloud container is
the worktree and the session that ran the start is already in it. A replacement body keeps
that block. Repos that seeded any of the six before its current version merge the
change by hand — see `../README.md` → "Updating".

The six seeded scripts carry a `# template-version: N` line. `sync-plans.sh --check`
compares a seeded copy's line against the template's and reports `DRIFT` when it is behind.
Bump the template's number whenever the body below `REPO-SPECIFIC` changes in a way
seeded copies must merge by hand, and say what changed in the README's "Adopting …"
section for it.

`plans/TEMPLATE_VERSIONS` keeps that number honest: it records, per template, the version
and a sha256 of the file with comment-only and blank lines stripped, and
`../self/tests/template-versions.sh` (blocking in `../self/gate.sh`) fails when the file
and the table disagree — so a body edit without a bump goes red here instead of reporting
`in-sync` in every consumer. A comment or documentation edit changes no hash; after any
other edit, bump the version line and re-record the hash with the command in the table's
own header.

`PROJECT_FACTS.md` is the opposite: it exists to hold what is specific to one
codebase. `sync-plans.sh` creates it if missing and never touches it again.

`BACKLOG.md` is seeded the same way and for the same reason — a repo writes its own
entries into it — with one difference in how `--check` reports it: an *empty* backlog is
the correct steady state for a repo that has closed everything it found, so a present
file is `in-sync` and never `unfilled`. Only its absence is an item. The generated
`plans/README.md` names it beside `PROJECT_FACTS.md`, which is what humanNetworkMap had
added by hand and a sync overwrote (`../AGENT_PLANS.md` → "The feature manifest" and
`../AGENT_DIRECT.md` → "The procedure" step 4 both say what belongs in it).

Anything added here that a repo would need to customize belongs in `PROJECT_FACTS.md`
instead, or the sync will destroy it.

`experiment/CHECKLIST.md` is different: not synced anywhere. Copy it by hand into
`plans/experiments/<slug>/` when running the A/B `../harness/EXPERIMENTS.md` describes.
