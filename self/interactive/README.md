# Standing runbooks

Bash-heavy procedures for agentTooling that outlive any one feature and are run by hand.
No runner touches this directory — `run-plans.sh --self` drains
`../features/<slug>/auto/`, and `run-verify.sh --self` drains `.../verify/`.

A step belonging to one feature goes in that feature's own
`../features/<slug>/interactive/` instead; this directory is for procedures with no
feature to belong to, such as the `git subtree` push/pull cycle documented in
`../../README.md` → "Updating".

Empty for now.
