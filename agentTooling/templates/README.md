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
```

`plans/TEMPLATE_VERSIONS` is not synced anywhere: it is the version-and-hash table for
the four repo-owned scripts, described under `template-version` below.

The five stubs are repo-agnostic on purpose: each describes its folder and points at
`agentTooling/RUNNER.md` for the execution model, so that model is documented once
rather than restated (and drifted) per repo. That is also why overwriting them is
safe — they hold nothing a repo could have customized.

`.gitignore` is generated rather than an install instruction because nothing detects a
missed instruction: a repo that skipped the hand-written gitignore step committed a
per-level gate report on every batch, and only a human reading a diff would notice. Its
four patterns (`gate-report*.txt`, `**/*.stream.jsonl`, `**/*.logfifo` and
`/review-report.md`) are relative to `plans/`, so an equivalent `plans/**/…` pattern in
the repo's root `.gitignore` from an earlier install is redundant rather than wrong. The
last is anchored where the others are not, and deliberately: `plans/review-report.md` is
rewritten every batch, while a feature's archived copy of the same verdict
(`plans/features/<slug>/review-report.md`) is committed as that batch's record — an
unanchored pattern would silently stop the next one being added. The file is a real
`.gitignore` while it sits here too, which is harmless: nothing under `templates/plans/`
matches those patterns.

`gate.sh`, `pr.sh`, `worktree-setup.sh` and `open-session.sh` are seeded into `plans/`
once and then owned by the repo. The gate
skeleton takes an optional level label (`gate.sh NN`) and writes `gate-report.NN.txt`
beside `gate-report.txt`; the PR skeleton creates **no branch at all** — the feature
already ran on its own, in the worktree `../feature-start.sh` made — and opens the PR
from whatever is checked out against `FEATURE_BASE`, which `../feature-close.sh` exports
from the manifest's `base`, so a stacked feature targets the one beneath it without
waiting for a merge. That skeleton is at `template-version: 4`, which is the version with
its **second entry point**, `pr.sh --merge-request <slug>`: the close calls it after the
cost record has been committed and pushed, and it is the only place `PR_AUTO_MERGE` is
read, so nothing can ask a forge to merge a branch whose record is not on it yet. `worktree-setup.sh` is a no-op skeleton whose comments list the common steps —
a venv per worktree (never shared: an editable install points at whichever tree ran it
last), `npm install`, a per-worktree dev port; `../feature-start.sh` runs it inside
every new feature worktree and stops the start if it exits non-zero
(`../LIFECYCLE.md`). `open-session.sh` is the hook the same script runs under `--open`,
with the new worktree's absolute path as its only argument: its job is to put a
coordinator session *inside* the worktree, because a session is billed to the branch of
the directory it was launched in and that is where a feature's work is claimed with no
pin. It ships opening a Terminal.app window running `claude` through `osascript`, and is
the one place in this subtree where a `cd <path> && <command>` string may be written —
the string is handed to Terminal.app, not to the Bash tool, and its own header says so.
Repos that seeded any of the four before it existed merge the
change by hand — see `../README.md` → "Updating".

The four seeded scripts carry a `# template-version: N` line. `sync-plans.sh --check`
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
