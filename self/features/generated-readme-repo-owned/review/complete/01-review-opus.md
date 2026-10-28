# 01 — review: generated-readme-repo-owned

## What the feature was supposed to do

Consuming repos keep losing hand-written lines from their generated `plans/README.md`.
`sync-plans.sh` copies `templates/plans/README.md` over it on every run and printed the
same `synced` line whether the difference was a template change or a local edit;
`--check` called it `STALE` and said to run the sync — the step that discards the edit.
Two losses are known, both in humanNetworkMap: the `BACKLOG.md` pointer
(`templates/README.md`), and on the PR-90 propagation a hand-added `taxonomy-migration/`
entry (the PR-89 pull lost lines the same way). The rule "what a repo would customize
belongs in `PROJECT_FACTS.md`" lived only in `templates/README.md`, which is never copied
to a consumer; the generated header said only "Edit the template, not this file", which
for a repo-specific entry wrongly means editing a template that ships everywhere; and
CONVENTIONS.md's README rules push agents to list new `plans/` contents in that file.

The intended model: generated `plans/README.md` = shared rules; each repo has its own
repo-owned place for exceptions and elaborations (`PROJECT_FACTS.md`), and the generated
README points there. All four of:

1. `templates/plans/README.md` header says: shared rules here; repo-specific entries,
   exceptions and elaborations go in `PROJECT_FACTS.md`; this file is overwritten on every
   pull.
2. `templates/plans/PROJECT_FACTS.md` has a section for repo-specific `plans/` contents.
   `template-version` bumped only if that file is versioned (`templates/README.md`,
   `templates/plans/TEMPLATE_VERSIONS`). The `README.md` → "Updating" hand-merge docs
   say existing repos add the section by hand (the file is seeded once, never synced).
3. CONVENTIONS.md, README section: a README marked as generated is never edited; its
   folder's repo-specific contents go in the repo-owned file it names.
4. `sync-plans.sh`: when overwriting a generated file that differs from the new
   template, it tells a hand edit from an upstream template change and prints the lines
   being dropped; `--check` describes that case honestly (not "STALE, run the sync");
   the mechanism is reliable and justified in the feature's `NOTES.md`; self tests under
   `self/tests/` wired into `self/gate.sh` like the existing ones.

## The diff

Base is `main`. Fetch it first (`git fetch origin main`), then
`git diff origin/main...HEAD --stat`, then the full diff — the local `main` only when
there is no `origin`: one older than this feature's branch point puts already-merged
commits in the diff.

Expected touch points: `sync-plans.sh`, `templates/plans/README.md`,
`templates/plans/PROJECT_FACTS.md`, `templates/README.md`, `CONVENTIONS.md`, root
`README.md`, `self/tests/` (a new test, its README entry, adjusted `sync-check.sh`
expectations), `self/gate.sh`, and this feature's directory. Anything else needs a reason.

## Contracts to hold it to

- **The classification is right in both directions.** A generated file byte-identical to
  a template version the repo has vendored before is an upstream change, never reported
  as an edit; one matching no vendored version is a hand edit. Try to break it: a stub
  several template versions behind, a hand edit made on top of a stale stub, a file under
  a subdirectory (`features/README.md`), a repo whose subtree prefix is not
  `agentTooling`, a squash subtree pull (the squash commit's paths are not prefixed), an
  uncommitted hand edit, no git at all. When the mechanism cannot tell, it must say so
  rather than guess "upstream".
- **The dropped lines are the ones actually lost** — lines in the current file that the
  new template does not have — printed in both `--check` and the write path, and the
  write path still leaves the file equal to the template (generated stays generated).
- **`--check` writes nothing**, and its exit status and the write path's still count the
  case as an item needing attention where lines are dropped; an ordinary upstream change
  is not an extra item on the write path. Other status words (`in-sync`, `missing`,
  `kept`, `DRIFT`, `synced` for an upstream change) keep their meaning — `update.sh`,
  `self/tests/sync-check.sh` and `self/tests/propagation-pull.sh` read them.
- **Shell rules** (`CONVENTIONS.md` → "Shell commands", "Named constants"): no new magic
  literals in `sync-plans.sh` left unnamed; `set -euo pipefail` safe — a git failure in
  the classifier must not kill the sync.
- **The documents agree with each other and the code**: the generated header, the new
  `PROJECT_FACTS.md` section, CONVENTIONS.md's rule, `templates/README.md`, the root
  `README.md` ("Updating" and "What stays in the consuming repo") and the
  `self/tests/README.md` entries. CONVENTIONS.md and the templates ship to every
  consuming repo: wording must be repo-agnostic.
- **`./self/gate.sh` is green**, and the new test is listed in both of the gate's lists
  (the syntax list and the `record` list) like its neighbours.

Fix local findings in the pass; escalate structural ones.

## Verdict

First line `Verdict: clean` or `Verdict: escalated`. If none of the contracts above is
broken, "no findings" is a legitimate and expected verdict.
