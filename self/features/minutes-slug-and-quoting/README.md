# A plan's minutes per attempt, the start's slug, the opener's quoting, and two small readers

Five small defects swept into one feature because none is worth a start, a review and a
close of its own. **The minutes walk** — a plan's time roll-up reads only the live
sidecar's attempts, so a resumed plan reports its last attempt's minutes as the whole
and sits in neither footnote list; it now walks attempts as the cost roll-up does, live
before prior, measured before recovered, and a mixed cell is a lower bound. **The
start's slug** — `slug_of_start_command` takes the word after `feature-start.sh` from
wherever a multiline regex lands, so a start with no slug records the next line's first
word; it now reads the start's own line after joining `\`-continuations. **The opener's
quoting** — both copies of `open-session.sh` single-quote the worktree path inside an
AppleScript string, which `'`, `"` and `\` still break; two named escaping layers, both
copies at template-version 3. **A report read** — `report.py --self <slug>` rewrites the
record on every run with only `generated_at` moved, leaving a merged worktree dirty for
the prune to keep; it now writes only when the body differs. **Two hook shapes** — a
single-quoted backtick is read as a substitution and denied, and `git -C <in-root>` is
never approved because the approval side reads `-C` as the subcommand; the opaque scan
becomes quote-aware and the approval side skips the same global options the deny side
does. The full reasoning is `self/DESIGN-2026-09-18-minutes-slug-and-quoting.md`
(§1–§7). Built direct (`AGENT_DIRECT.md`) by one implementer, tests first, then one
review pass, then the close. Started stacked on `ledger-and-routing`; that PR (#52)
merged before this feature's review round, `origin/main` was merged in, and the base
below was moved to `main` by hand (`manifest.py` has no `set-base`).

## Slices

| Slice | What it does |
|---|---|
| S1. The minutes walk (§1) | `report.py`: `duration_from_usage`/`compute_time_rollup` walk every attempt keyed by session, live sidecar before prior sidecars, taking `duration_ms` (measured) else `recovered_duration_s` (recovered) else unmeasured; the plan's seconds are the sum; any unmeasured attempt → `missing_duration_plans` + missing mark + "attempt k of n unmeasured"; else any recovered → `recovered_duration_plans` (+ `measured_attempts`, `recovered_attempts`) + lower-bound mark. Existing marks and footnote block. Test: `report-footnotes.sh` (mixed plan is the sum with both counts and the lower-bound footnote; a plan with an unmeasured attempt names it; prior-sidecar-only figures are read). |
| S2. The start's slug (§2) | `routing.slug_of_start_command`: join `\`-newline continuations (named constant), match per line, slug = token after the script and its value-taking flags (`--self`, `--base <b>`, `--pin` — named tuple) on that line or nothing. Tests in `routing-record.sh`: same-line slug; no slug on the line → nothing; continued start → its slug; `--base x` before the slug → the slug. |
| S3. The opener's quoting (§3) | `self/open-session.sh` and `templates/plans/open-session.sh`: `shell_single_quote` (`'` → `'\''`) then `applescript_escape` (`\` → `\\`, `"` → `\"`), both at `template-version: 3`; `templates/plans/TEMPLATE_VERSIONS` re-recorded. Test: `osascript` stubbed on `PATH` to record its argument; each copy run with a path holding a space, `'`, `"`, `\`; the recorded `do script` string, AppleScript-unescaped and run with `claude` stubbed to print `$PWD`, prints the path intact; `template-versions.sh` passes. |
| S4. A report read does not rewrite (§4) | `report.py`: before writing `report.md`/`report.json`, compare the rendered body with the file on disk with `generated_at` masked (one named regex); equal → leave both untouched, still print; `--all` per feature; a missing record is written. Test: two runs over an unchanged corpus leave both files byte-identical and the tree clean; a run after `planning.json` changed rewrites them. |
| S5. Two hook shapes (§5) | `hooks/allow-repo-commands.sh`: a path word is read through `path_body`, which strips double quotes only, so a `$` or a backtick inside single quotes is a literal (a narrowing: deny → prompt, never prompt → approval); the approval side reads past exactly `GIT_GLOBAL_LOCATION_OPTIONS` (`-C`, `--git-dir`, `--work-tree` — NOT `-c`, `--config-env`, `--exec-path` or `--namespace`, and no other leading flag) to the subcommand, each value present, not itself a flag, and confined to the project root by the existing `token_confined` pass. Built narrower than §5b's wording on the coordinator's ruling (`NOTES.md` 4 and 11). Tests in `allow-repo-commands.sh`: `sed -n '/```json/,/```/p' /outside/x.md` prompts, `grep 'a`b' README.md` approved, an unquoted backtick still denied; `git -C <root> status` approved, `git -C /tmp status` prompts, `git -C <root> branch new` denied, `git --git-dir=<root>/.git log` approved, `git -c core.pager='sh -c id' log`, `git --paginate log`, `git -C <root> -C /tmp status` prompt. `hooks/README.md` updated. |

## Deliberately excluded

- **The vendored `agentTooling/.claude/settings.json`** in a consuming repo — nothing
  reads it; the entry stays.
- **Approving `ps`, `cp` from the scratchpad, or a harness entry point that writes** —
  each is a write and the prompt is the policy; the coordinator's fix is one mutation
  per call.
- **Everything `ledger-and-routing` owns.**

## Machine-readable

```json
{
  "slug": "minutes-slug-and-quoting",
  "method": "direct",
  "plans": ["01-review-sonnet"],
  "branches": ["minutes-slug-and-quoting"],
  "base": "main",
  "session_window": {"from": "2026-09-18T12:53:16Z", "to": "2026-09-18T14:49:18Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["a7b9f3a3f6258b4a8"]
}
```

**`agentTooling/feature-start.sh` writes this fence** — the slug, the method, the
branch, the base and `from`, with the id lists empty — and
`feature-capture.sh` stamps `to` on the branch, provisionally until the merge freezes it
(`agentTooling/LIFECYCLE.md`). Do not hand-copy it. Only `slug`, `plans` and `branches`
are required: `method` reads as `"plans"` when absent, `base` as `main`,
`session_window` as unbounded, and the four id lists as empty. These are the ones that
go wrong quietly:

- **`method`** — optional, `"plans"` when absent. `"direct"` marks a feature built per
  `agentTooling/AGENT_DIRECT.md` by one implementer delegate; `"hand"` one the
  coordinator built itself, with no delegate to pin and no plans. Under either, the
  transcripts `planning.json` captures are the **build**, and `analysis/report.py` files
  their dollars and minutes there instead of under planning — as `build: implementer`
  and `build: by hand` respectively. Leave it out for a planned feature; a wrong value
  here moves money between buckets without a warning about which was right.
- **`base`** — the branch the feature branched from, `main` unless
  `feature-start.sh --base` said otherwise. `feature-close.sh` reads it and exports
  `FEATURE_BASE`, which is the base `plans/pr.sh` opens the PR against, so a feature
  stacked on one that has not merged shows only its own diff. `run-review.sh` reads it
  too, to know whether it is on a branch it may commit its pass to. Cost capture ignores
  it.

- **`branches`** — copy each name from `git branch --show-current`, verbatim. It is
  matched literally against the `gitBranch` in every session transcript, so an added
  owner prefix, or a name retyped from memory, matches nothing and leaves every session
  on it uncounted — the feature then reports `$0.00`, which reads as "planning was free"
  rather than "this manifest is wrong". `analysis/capture_planning.py` warns when a
  declared branch matches no transcript. If a branch was renamed mid-feature, list both
  names: transcripts keep whatever name was current when they were written.
- **`plans`** — every plan stem in the table above, *without* the `.md` extension and
  without its queue/state path, in batch order. `analysis/report.py` prices exactly this
  list: a stem left out is a plan whose cost lands in no report, and an array left out
  entirely drops the whole feature back onto a fallback that can only see plans which
  already ran.
- **`session_window` timezone** — end every bound with `Z`. A bound with no offset is
  read as UTC, and the natural place to find a timestamp is `git log`, which prints
  **local** time — so a value copied from there and pasted bare is silently off by your
  UTC offset, four hours in US Eastern, which is enough to hand a session to the wrong
  feature. Write local time only with its offset spelled out (`2026-07-17T18:00:00-04:00`);
  `analysis/capture_planning.py` warns on any bound that states no zone.
- **`sessions`** — session ids claimed outright, across every project directory,
  regardless of branch, window or `cwd` — the top-level twin of `subagents`. **A pin is
  the exception now, not the rule.** `feature-start.sh` pins nothing unless given
  `--pin`: the session that starts a feature is a *router*, it opens several features and
  belongs to none of them, and its spend is routing overhead reported from
  `plans/features/<slug>/routing.json` rather than billed to any feature
  (`agentTooling/LIFECYCLE.md` → step 2). The coordinator belongs inside the worktree,
  where rule 1 claims it by branch with no pin at all. What is left for this field is the
  case it was written for — a session that genuinely worked on this feature from
  somewhere else, typically one that began on `main` before the branch existed; widening
  `branches` to `main`
  instead sweeps in every later session in that checkout. A pinned session that branch
  and window would also select is priced once, and every entry in `planning.json`
  records how it was selected (`selected_by`: `"pinned"` or `"branch"`) and the `cwd` it
  was launched in. A pin that is also in `exclude_sessions` warns, and the pin wins.
  A session claimed by more than one feature is **split** between them by the windows
  they claim it with, so the bounds on a pinned session decide dollars.
  Find an id with `python3 agentTooling/analysis/capture_planning.py --list-sessions
  [--unclaimed] [--since <date>]`, which prints every session launched in this repo's
  primary checkout or one of its feature worktrees with its branch, `cwd`, cost and
  opening prompt.
- **`subagents`** — optional; usually absent. Agent ids of delegates whose *parent*
  session was not on this feature's branch — the coordinator-on-`main` case. A subagent
  inherits its parent's `gitBranch` at spawn and never records its own, so an architect
  spawned from `main` is invisible to `branches` and `session_window` alike; pinning its
  id claims it outright. Find the id with
  `python3 agentTooling/analysis/capture_planning.py --list-subagents --since <date>`,
  which prints each one's cost and opening prompt. A subagent whose parent *is* on the
  branch needs no pin — it is claimed with its parent when its own start is in the window.
  A pin wins over an `exclude_sessions` entry naming its parent: excluding the coordinator
  drops the coordinator's own context cost and keeps the pinned architect. Runner sessions
  are the exception — their usage.json already holds the cost, pins included. A
  delegate's transcript is filed under its *parent's* cwd, so one spawned by a
  coordinator sitting in another repo is found by `--list-subagents --everywhere`
  and pinned here all the same. `--list-subagents --unclaimed` is the standing
  question — every delegate on this machine no feature has claimed, with the
  feature its brief names; a pin already claimed by another feature refuses the
  capture rather than counting twice.
- **`exclude_subagents`** — optional. Delegates of a session this manifest *does* select
  that belong to another feature — a coordinator's manifest (on `main`, windowed around
  the run) lists the architect it spawned, which the arm's own manifest pins. Without it
  the parent route claims the architect here too and the ledger refuses the other
  capture as a double claim.
- **`session_window.to`** — `null` means "still in flight", and open is the right value
  until the feature's first capture. `agentTooling/feature-capture.sh` sets it on the
  branch, from evidence: one second past the last instant of the sessions this feature's
  `branches` and `session_window` select and of their subagents, stamped before the
  capture so the shared-session split runs against the real bound
  (`agentTooling/LIFECYCLE.md` → step 5). Until the merge it is provisional, and a re-run
  of the capture after more work moves it either way (`set-window-to --replace`). Do not
  hand-write one, and never widen one on a merged feature — `analysis/manifest.py
  set-window-to --tighten` is the only path that may move it then, and only inwards. A window
  left open after the work is done is what goes wrong: two
  open-ended windows on a shared branch claim each other's sessions and price the same
  planning cost twice; `analysis/capture_planning.py` warns when two manifests' branches
  *and* windows both overlap, and a `to` bound is how you answer it.
