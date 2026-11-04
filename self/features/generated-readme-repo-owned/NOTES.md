# Notes — generated-readme-repo-owned

Built by hand by the coordinator, in the cloud container on
`claude/generated-readme-repo-owned`.

## The mechanism: match the stub against the repo's own history of the template

`sync-plans.sh`'s `stub_origin <rel>` hashes `plans/<rel>` as a git blob (under the
template path's attributes, `git hash-object --path=`) and compares it with
`<prefix>/templates/plans/<rel>` in the index and at every commit in `HEAD`'s history that
touched that path (`git log --format=%H HEAD -- <path>`, then `git rev-parse <c>:<path>`).
Any match: the stub is an unedited copy of a template this repo once vendored, so the
difference is an upstream change and the overwrite loses nothing. No match: a hand edit.

Why this, over the alternatives considered:

- **A recorded hash** (the sync writes `plans/.generated-sums` with what it last wrote,
  and a mismatch means an edit) is exact too, but it is new state: a file every repo must
  commit, that a merge can conflict on, that a hand edit to the sums file defeats, and —
  decisively — that does not exist yet. The first sync after this feature lands, which is
  exactly the pull that needs the protection (PR-89 and PR-90 both lost lines on it),
  would have no record and could not tell. The history already holds every version: each
  `subtree pull` and the install commit the templates. So the answer is available
  retroactively, in every consuming repo, with nothing written.
- **The previous template only** (`HEAD^:<prefix>/templates/…`, the pre-pull commit) is
  what the spec suggested, but which commit is "previous" depends on when the sync runs:
  after the pull's merge commit, before it, twice, or after several pulls with no sync in
  between (a stub several versions behind). Matching any version in history covers every
  one of those; matching only one misreads all but the first.
- **A marker in the generated file** (a hash line in its header) would make every stub
  differ from its template, breaking the byte comparison `--check` and every test rely on.

The comparison is of blob ids, so there is no fuzzy match: one byte changed by hand is an
edit. A **squashed** subtree's own commits hold the template at the subtree root rather
than under the prefix; their lookups fail and are skipped, and the merge that brought each
in carries the same blob under the prefix (`self/tests/generated-hand-edit.sh` 10 runs a
real `subtree add`/`pull --squash` cycle). The prefix comes from `git rev-parse
--show-prefix` in this directory, so a repo vendoring under another name works (7).

**Where it cannot answer, it says so and never guesses "upstream"** — that is the guess
that loses lines. Three cases: no git, or this directory not inside the consuming repo's
own checkout (the toplevels differ); no commit yet; and a **shallow clone** with no match,
since the version the stub came from may be beyond the depth. Cloud containers clone
shallow (depth 50 by default), so the last case is real; a shallow clone still includes
the boundary commit's tree, so a stub only one pull behind normally still matches. The
unknown case is reported like an edit — the dropped lines printed and the item counted —
with the reason in the line.

## What is reported

- `--check`: `STALE` for an upstream change (no lines); `EDITED` for a hand edit, with
  "sync-plans.sh would drop the N line(s) below — move them to plans/PROJECT_FACTS.md
  first" and the lines; `STALE` naming the reason when unknown, with the lines. The old
  wording ("run sync-plans.sh") is kept only where the sync is safe.
- Write path: `synced … (template changed upstream)` for upstream, not an item; `OVERWROTE`
  with the lines for an edit or an unknown, counted, so the run ends `needs attention` and
  `update.sh` (which exits with the sync's status) says so too.
- "Dropped lines" are `diff template stub`'s `>` side: what the stub has that the new
  template lacks. An edit that only removed lines drops nothing; it is still `EDITED`
  under `--check`, and the write path restores it as `synced` at exit 0, since nothing was
  lost.

## Other decisions

- All three generated READMEs got the new header, not only `plans/README.md`: the
  CONVENTIONS.md rule says a generated README names its repo-owned file, and
  `features/README.md` and `interactive/README.md` carried the same misleading "Edit the
  template" line. `features/TEMPLATE.md` and `.gitignore` have no header to change.
- `PROJECT_FACTS.md` is not versioned (no `template-version`, not in `TEMPLATE_VERSIONS`);
  no bump. The hand-merge is `README.md` → "Adopting the repo-owned plans/ contents".
- `self/tests/sync-check.sh` section 3 appended a line to the seeded README, which is a
  hand edit by this definition; its expectations moved from `STALE`/`synced` to
  `EDITED`/`OVERWROTE`.
