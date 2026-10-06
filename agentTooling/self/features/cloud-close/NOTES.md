# Notes: cloud-close

Rulings made during the direct build, each with its reason. Design:
`self/DESIGN-2026-10-05-cloud-execution.md` §2, §5, §10.

## The branch from the manifest

- **One reader, on the shell side: `manifest_branch <readme> <slug>` in
  `plan-runner-roots.sh`.** All three callers already source that file, and it already
  has `manifest_field` (jq over the last json fence), so the branch is parsed in the same
  one place as `base`. `analysis/manifest.py get` was the alternative; it costs a Python
  start per call and a second parser of the fence for the shell side.
- **Empty, missing or non-list `branches` → the slug.** Every manifest written before
  this feature names exactly its slug, so the fallback reproduces the old rule and can
  never invent a branch to push or to refuse against. A non-string first element reads
  the same way. `feature-lifecycle.sh` CD pins the empty-list case.
- **The capture reads the manifest in the checkout it runs in.** On the branch that is
  the feature's own; after the merge it is the copy main carries, which is what lets the
  post-merge path find `origin/<branches[0]>` (CC). From the primary before a merge the
  manifest is not there, the reader falls back to the slug, and the refusal is the one it
  always was.
- **`run-review.sh` needs no change.** It never derives a branch from the slug: its only
  branch logic is `commit_pass_output`, which compares the *current* branch with the
  manifest's `base` (commit on anything that is not the base).
- **`analysis/capture_planning.py` needs no change.** Its claim is the literal
  `branches_seen & set(branches)` over the fence's `branches` (≈ :2793 and :2823), so a
  session whose `gitBranch` is `claude/…` is claimed by a fence that says `claude/…`
  (design §2 "Cost attribution"). CB's capture claims its `claude/lifecycle-cloud`
  session that way.

## forge.sh

- **The origin is read raw — `git config --get remote.origin.url` — not with `git remote
  get-url`.** Deviation from the brief's wording. `get-url` applies `url.<x>.insteadOf`,
  which is a transport rewrite, not a change of which repository the forge knows; reading
  the configured URL keeps the identity stable whatever rewrite a machine carries (this
  container rewrites `git@github.com:` to https). It is also what lets the lifecycle
  fixture keep its pushes on a bare repo (`url.<bare>.insteadOf <github url>`) while
  forge.sh sees a GitHub URL — and `get-url`, which the capture's repo identity reads,
  still answers the bare path it always did.
- **The checkout is forge.sh's own** (`git -C <its directory>`), never the caller's cwd,
  like every other script here. A vendored copy has no `.git`, so it reads the consuming
  repo's origin.
- **{o}/{r} are the last two path segments** of an https/http/ssh/git URL or an
  scp-style `user@host:path`, with `.git` and a trailing slash dropped, each segment
  checked against GitHub's charset. A proxied `http://…/git/o/r` therefore reads as o/r.
  `file://`, a local path and no origin are refused (exit 1) before any forge call.
- **The host is not passed to gh.** gh's own `GH_HOST` (default github.com) decides it; a
  GitHub Enterprise origin needs `GH_HOST` set, which is gh's documented contract.
- **pr-find sends `-X GET` with `-f head=<o>:<head> -f state=open`**, which gh serialises
  and URL-encodes as the query string, rather than a hand-built `?head=…` that a branch
  name could break. `head` is owner-qualified there, as the list endpoint requires.
- **pr-open sends the head unqualified** — a same-repository PR, which is the only kind
  the close opens — and the body as `-F body=@<file>`, so gh reads the file and no shell
  ever expands it (F3 sends quotes, `$(…)` and backticks through untouched).
- **Exit codes: 1 for every failure, 2 for usage.** A POST that answers 2xx with no
  `html_url` is a failure: the close would otherwise stamp `pr_opened rc=0` with no url,
  the exact record this feature exists to stop. A body file that is not there fails before
  the POST.
- **No reachability verb.** Design §5 lists one, but nothing in this feature calls it; it
  arrives with `auto-merge` in `execution-profiles` (self/BACKLOG.md).

## pr.sh (template-version 5)

- **How pr.sh finds forge.sh:** `feature-close.sh` exports `FORGE_SCRIPT` (the copy
  beside itself) next to `FEATURE_BASE`; unset — pr.sh run by hand — it tries
  `./agentTooling/forge.sh` then `./forge.sh` from its cwd, which the contract says is the
  repo root (a consuming repo's vendored copy, then agentTooling's own root under
  `--self`). Both carry a slash so neither is looked up on PATH (the first build used bare
  `forge.sh`, and P1a caught it). None found is `exit 1` **before** anything is committed
  or pushed.
- **A failed pr-find is a failure**, not "nothing open": carrying on would open a second
  PR when the forge was merely unreachable.
- **The "forge CLI not installed → skip, exit 0" path stays**; the `gh auth status` probe
  is gone (the defect in design §5). A forge that is there and refuses is non-zero.
- **The `--merge-request` entry point is unchanged** and needs no forge.sh: it still asks
  `gh pr merge --auto`, which is GraphQL and so fails in the cloud — advisory, as it
  always was, and `self/pr.sh` never calls it. `execution-profiles` moves it to
  `forge.sh auto-merge`.
- **A v4 seeded pr.sh is driven exactly as before**: the close only adds an exported
  variable it never reads. `self/tests/fixtures/pr-v4.sh` freezes the v4 template so X6
  (close through it, merge still requested) and `sync-check.sh` 4f–4g (`4 < 5` drift) keep
  testing it after the template moved on.
- **`sync-plans.sh --check` needed no change**: drift is the template's integer against
  the seeded copy's, so the bump to 5 is reported like every other.

## Tests

- **The `gh` shim keeps two logs.** `GH_LOG` stays the forge-*event* log the existing
  checks grep: a `gh pr …` call is its argv as before, and a REST call is logged as the
  `pr` verb it amounts to (`pr view <head>` for the GET, `pr create --base B --head H
  --title T` for the POST). `GH_ARGV_LOG` is every argv verbatim, and is what the new
  checks read for "no `gh pr`, no `gh auth status`". That kept every existing check line
  that asserts "a PR was opened against base B" unchanged while the call under it moved
  from GraphQL to REST; a regression back to `gh pr create` would still satisfy those
  lines, which is why CBh, T4h and F6 read the argv log.
- **Existing assertions changed, each because the behaviour it pinned is what this
  feature changes:**
  - `feature-lifecycle.sh` T4c (label only) and T4d: they pinned the `gh auth status`
    skip — the defect. T4 now drives a stubbed REST failure; T4d asserts pr.sh exited
    non-zero and opened nothing, with T4g (rc stamped, no url) and T4h (no auth probe)
    added.
  - `feature-lifecycle.sh` P2e: pinned both copies at template-version 4; the design
    moves them to 5, which still carries the merge request (≥ 4).
  - `sync-check.sh` 1d, 1f, 4b, 4d: pinned `template-version 4` in the in-sync and DRIFT
    lines; the same lines at 5. 4f–4g are new.
- **Fixture setup changed, not assertions:** the lifecycle repo's origin is now a GitHub
  URL routed to the bare repo by `insteadOf`, and the shim's per-branch marker flattens
  slashes so `claude/x` is one file.

## Open

- **The real `POST /pulls` through the cloud proxy is unverified** (design §5
  "Unverified"). Every test here runs against the shim; the coordinator makes the first
  real call at this feature's own close and records the result in the design's §10.
