# 01 — review: cloud-close

Written from the design (`self/DESIGN-2026-10-05-cloud-execution.md` §2, §5 and §10's
`cloud-close` row) **before** the build, never from the implementer's report. Read the
code; do not take the manifest's or `NOTES.md`'s account on trust. "No findings" is a
legitimate verdict. Fix local drift in this pass; anything structural is an escalation,
and an escalated report is round 2's brief. Begin your report with the `Verdict:` line
the prompt asks for.

## What the feature was supposed to do

Make `./feature-close.sh --self <slug>` run end to end in a Claude Code cloud container,
where the session may push only its assigned `claude/…` branch and `gh` reaches GitHub
only through a proxy that refuses GraphQL and `gh auth status`. Two halves:

1. **The branch comes from the manifest.** `feature-close.sh`, `feature-capture.sh` and
   `run-review.sh` read the feature's branch from the manifest fence's `branches[0]`, not
   from the slug (§2 "What follows from the rule"). Concretely:
   - the close refuses "not on the manifest's branch" in place of "not on branch `S`";
   - the capture recognises the on-branch run by that branch, pushes that branch, and its
     post-merge path looks for that branch's local and `origin/` refs (and its refusal
     names that branch, not the slug);
   - `run-review.sh`: verify whether it derives the branch from the slug anywhere; if it
     does not, it needs no change and the manifest or `NOTES.md` should say so;
   - `capture_planning.py`'s branch match (≈ :2766/:2823) already matches the fence's
     `branches` literally (§2 "Cost attribution"); verify it, change nothing if so.
   - **A local feature, whose `branches[0]` is its slug, behaves exactly as before.**
     Every existing assertion in the lifecycle tests must still pass unchanged.
2. **`forge.sh`** (new, at the agentTooling root beside the runners) with the verbs
   `pr-find <head>` and `pr-open <head> <base> <title> <body-file>`, both over `gh api`
   REST (`GET /repos/{o}/{r}/pulls?head={o}:{head}&state=open`,
   `POST /repos/{o}/{r}/pulls`), `{o}/{r}` parsed from the origin URL (https and ssh
   spellings). Every verb exits non-zero on failure; only `pr-find` may print nothing on
   success. It never calls `gh pr …`, `gh auth status`, or GraphQL. `auto-merge` is
   **not** in scope (`execution-profiles`).
   - The forge is reached from the close through the repo-owned `pr.sh` (§5): `pr.sh`
     pushes with git, calls `forge.sh pr-find`, else `pr-open`, prints the url. The
     `gh auth status` early `exit 0` is gone, so a forge failure is a non-zero exit and
     **no path stamps `pr_opened rc=0` with an empty url** because of an auth probe.
     `templates/plans/pr.sh` and `self/pr.sh` go to `template-version: 5` and stay in step
     (self/pr.sh differs only where it already did: `AUTO_MERGE=0`). How `pr.sh` finds
     `forge.sh` must work both for `--self` and from a consuming repo's `plans/pr.sh`.
   - A v4 seeded `pr.sh` in a consuming repo must still be driven by the close as before,
     and the merge-request entry point (`--merge-request`, still `gh pr merge` for now)
     must still be gated on template-version ≥ 4.
   - `README.md` (root) gains an "Adopting the forge adapter" hand-merge section for
     consuming repos with a customised `pr.sh`, and `sync-plans.sh --check` reports the
     v4→v5 drift the way it reports any template-version drift.

## The diff

Base `main`; read `git diff origin/main...HEAD` (this cloud checkout has no local `main`
ref; `origin/main` is fetched). Expect: `forge.sh`, `feature-close.sh`,
`feature-capture.sh`, possibly `run-review.sh` / `plan-runner-roots.sh` (a shared
manifest-branch reader), `templates/plans/pr.sh`, `self/pr.sh`, `self/tests/*.sh` (the
lifecycle test and whichever test the tests README assigns capture/forge cases to),
`self/tests/README.md`, `README.md`, `RUNNER.md`/`LIFECYCLE.md` where they say "branch S"
in a way that is now wrong, `self/README.md`, the design doc's §10 (a finding recording
whether `gh api POST /pulls` worked through the proxy may land after this review — that
is the close's own record, not a change to judge), and `self/features/cloud-close/`
(manifest, `NOTES.md`, `CHECKPOINT.md`, this brief). Anything else that moved is a
finding.

## What to hold it to

- **Tests came first and test the promise.** The branch should show
  `cloud-close: acceptance tests` before the implementation. In the existing self-test
  files (per `self/tests/README.md`), there must be:
  - a close on a manifest whose `branches[0]` differs from the slug (e.g. `claude/x`),
    on that branch, that opens the PR, stamps `pr_opened` with the url, captures, commits
    `S: cost records` on that branch and pushes **that** branch to the origin — and the
    same close on a checkout on the slug-named branch is refused;
  - a capture on such a manifest: on-branch mode recognised, push of `branches[0]`, and
    the post-merge path finding `origin/<branches[0]>`;
  - `forge.sh` against the suite's fake `gh` (the lifecycle test's `gh` shim, `GH_ORIGIN`):
    `pr-find` returning a url makes `pr.sh` skip `pr-open`; `pr-open` posts head, base,
    title and the body file's content; a stubbed REST failure exits non-zero and the close
    stamps that rc with no url; neither the close nor `forge.sh` invokes `gh pr` or
    `gh auth status` on the open path (assert from the shim's log); https and ssh origins
    yield the same `{o}/{r}`.
  Check each exists, is black-box (through the scripts, not internals), and would fail on
  `main`'s code. Mutate one site mentally — e.g. revert the close's branch comparison to
  the slug — and say which assertion catches it.
- **No assertion weakened.** Existing `check` lines in the touched tests are unchanged
  unless the behaviour they pinned was the defect (the auth-status skip); each such change
  must be justified in `NOTES.md`.
- **Fallback.** A manifest with an empty or missing `branches` — what does each script
  do? It must not silently push or refuse something surprising; say what it does and
  whether `NOTES.md` records the ruling.
- **Quoting and injection.** `forge.sh` builds a REST call from a branch name, title and
  body file: no unquoted expansion, the body read from the file (`-F body=@file` or
  equivalent), `head` qualified as `owner:branch`, JSON parsed with `gh`'s `--jq`, not grep.
- **Bash 3.2**, `set -uo pipefail` like its siblings, named constants at the top
  (CONVENTIONS "Named constants"), every path from the script's own location, no chained
  `cd` in tests.
- **The gate passes.** Run `./self/gate.sh` and report its verdict line. Run
  `bash self/tests/feature-lifecycle.sh` and any other touched test and report each.
- **READMEs** (CONVENTIONS "Keeping READMEs up to date"): the root README lists
  `forge.sh` with its interface and exit codes (Rule 2: it depends on the origin URL and
  on `gh`'s proxy credentials, not visible from an import); `self/tests/README.md` rows
  describe the new cases; `LIFECYCLE.md`'s "branch S" wording is consistent with
  "`branches[0]`, which is `S` for a local feature".
- **Design consistency.** The design says `pr.sh` keeps its two entry points and its
  repo-owned shell, and that a non-GitHub repo never calls `forge.sh`. Check that holds.

## Verdict

`Verdict: clean` or `Verdict: escalated` as the first line of `self/review-report.md`,
then what the feature was supposed to do, whether it does it, what you fixed, what you
escalated (with the assertion that would catch it), and the files this pass touched.
