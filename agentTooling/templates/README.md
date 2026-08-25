# templates

Source for the generated files in a consuming repo's `plans/` tree. **Edit these, not
the copies in `plans/`** — `../sync-plans.sh` overwrites the generated stubs on every
run.

```
plans/README.md              generated — synced every run
plans/interactive/README.md  generated
plans/features/README.md     generated
plans/features/TEMPLATE.md   generated
plans/PROJECT_FACTS.md       repo-owned — seeded once from the skeleton, never overwritten
plans/gate.sh                repo-owned — seeded once, never overwritten
plans/pr.sh                  repo-owned — seeded once, never overwritten
```

The four stubs are repo-agnostic on purpose: each describes its folder and points at
`agentTooling/RUNNER.md` for the execution model, so that model is documented once
rather than restated (and drifted) per repo. That is also why overwriting them is
safe — they hold nothing a repo could have customized.

`gate.sh` and `pr.sh` are seeded into `plans/` once and then owned by the repo. The gate
skeleton takes an optional level label (`gate.sh NN`) and writes `gate-report.NN.txt`
beside `gate-report.txt`; repos that seeded their gate before this existed merge that
change by hand — see `../README.md` → "Updating".

`PROJECT_FACTS.md` is the opposite: it exists to hold what is specific to one
codebase. `sync-plans.sh` creates it if missing and never touches it again.

Anything added here that a repo would need to customize belongs in `PROJECT_FACTS.md`
instead, or the sync will destroy it.

`experiment/CHECKLIST.md` is different: not synced anywhere. Copy it by hand into
`plans/experiments/<slug>/` when running the A/B `../EXPERIMENTS.md` describes.
