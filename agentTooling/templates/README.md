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
plans/gate.sh                repo-owned — seeded once, never overwritten
plans/pr.sh                  repo-owned — seeded once, never overwritten
plans/worktree-setup.sh      repo-owned — seeded once, never overwritten
```

`plans/TEMPLATE_VERSIONS` is not synced anywhere: it is the version-and-hash table for
the three repo-owned scripts, described under `template-version` below.

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

`gate.sh`, `pr.sh` and `worktree-setup.sh` are seeded into `plans/` once and then owned
by the repo. The gate
skeleton takes an optional level label (`gate.sh NN`) and writes `gate-report.NN.txt`
beside `gate-report.txt`; the PR skeleton creates **no branch at all** — the feature
already ran on its own, in the worktree `../feature-start.sh` made — and opens the PR
from whatever is checked out against `FEATURE_BASE`, which `../run-review.sh` exports
from the manifest's `base`, so a stacked feature targets the one beneath it without
waiting for a merge. `worktree-setup.sh` is a no-op skeleton whose comments list the common steps —
a venv per worktree (never shared: an editable install points at whichever tree ran it
last), `npm install`, a per-worktree dev port; `../feature-start.sh` runs it inside
every new feature worktree and stops the start if it exits non-zero
(`../LIFECYCLE.md`). Repos that seeded any of the three before it existed merge the
change by hand — see `../README.md` → "Updating".

The three seeded scripts carry a `# template-version: N` line. `sync-plans.sh --check`
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

Anything added here that a repo would need to customize belongs in `PROJECT_FACTS.md`
instead, or the sync will destroy it.

`experiment/CHECKLIST.md` is different: not synced anywhere. Copy it by hand into
`plans/experiments/<slug>/` when running the A/B `../harness/EXPERIMENTS.md` describes.
