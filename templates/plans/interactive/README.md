# Interactive plans

_Generated from `agentTooling/templates/` by `agentTooling/sync-plans.sh`. Edit the template, not this file._

Standing runbooks — bash-heavy steps that need a human in the loop and that outlive any
one feature (first-run setup, recurring migrations). Run by hand; no runner touches this
folder.

A plan that belongs to a single feature goes in that feature's own folder instead —
`plans/features/<slug>/interactive/` — so the feature directory holds everything about it.
Ask which one you are writing: if it stops making sense once the feature ships, it is
feature-scoped.

How these differ from the unattended verify pass, which is also privileged but has no
human in the loop: `../../agentTooling/RUNNER.md`.
