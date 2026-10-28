# The hook asks for a rewrite it can name, and asks the human about a write it has read

The permission hook's approval analysis answers a bool, so "I could not read this" and
"I read it and it writes" both fall through to the same silent prompt, and only seven
raw-text shapes ever carry a rewrite. Replaying one coordinating session's 24 commands
on 2026-09-18: 5 approved, 18 prompted with no reason, 1 denied. The user's rule: *the
hook should ask for a rewrite when a command cannot be analysed; a command the analysis
read and finds potentially unsafe goes to the user, not one it merely could not read.*
The analysis now returns one of three verdicts per subcommand and per line — REWRITE
(unreadable, a rewrite exists: denied with the rewrite as the reason, counting toward
the existing escalation), ASK (read, and a write or an unknown program: prints nothing,
so the settings and the human decide), ALLOW — with any REWRITE member making the line
REWRITE. A sequence mixing approved reads with one write is sent back to be run as one
write per call. The coordinator's shell rules become guidelines in `CONVENTIONS.md`
§ Shell commands, rewritten around the three outcomes, with `hooks/README.md` restating
them as "The three outcomes". The full reasoning is
`self/DESIGN-2026-09-18-hook-rewrite-or-ask.md` (§1–§7). Built direct
(`AGENT_DIRECT.md`) by one implementer, tests first, then one opus review pass, then
the close. Started stacked on `minutes-slug-and-quoting`, whose S5 edits the same hook;
retargeted to `main` at the close once that PR merges.

## Slices

| Slice | What it does |
|---|---|
| S0. The quote walk (§1, "a quote inside the other quote") | `unquoted_index` tracks single AND double quotes, so `cat "'"$(pwd)/x` is a `$(…)` in a path. First, because every shape below reads through it. |
| S1. Three verdicts (§1) | `command_allowed` and `subcommand_allowed` return a verdict (named constants REWRITE / ASK / ALLOW) with a reason for REWRITE; line precedence any-REWRITE > any-ASK > ALLOW; `main()` denies a REWRITE with its reason through the existing escalation path (`OPAQUE_REWRITE_ATTEMPTS`, then `ask`, headless silent), prints nothing for ASK. The seven opaque shapes keep their reasons and join REWRITE. The three older denies run first, unchanged. |
| S2. The rewritable shapes (§1 table) | One named reason constant per shape: `$NAME`/`${NAME}` in a word, `~`, a brace group the expansion refuses, a `..` component in a path token (replaces the raw `..` guard; `main...HEAD` is ASK), a lone relative or bare `cd`, a line break outside a `cat` heredoc body or a `\` continuation. `UNANALYSABLE` goes; CR and NUL are ASK. Existing NOT_DENIED cases whose shape is now rewritable are MOVED into the REWRITE groups and each move is listed in `NOTES.md`. |
| S3. One write per call (§2) | A `&&`/`||`/`;` sequence with at least one approved member and at least one ASK member is REWRITE, the reason naming the approved members ("run on their own — approved") and the rest ("run alone"); an all-ASK sequence is one ASK; a pipeline is never split. |
| S4. The reason names the member (§3) | Member text truncated at a named length; one line per shape; `hook-escalation.sh` gains a case per new shape (counter advances) and one ASK case (counter resets). |
| S5. The guidelines (§4) | `CONVENTIONS.md` § Shell commands rewritten around the three outcomes (approved silently / sent back with a rewrite / reaches the human), ending with the model's rule for the last class: one write per Bash call, reads in their own calls; `cd <abs>` as its own call, not `git -C <other tree>`; Read/Grep/Write/Edit over `sed -n`/`cp`/`cat >`. § Writing files names `cp`. `hooks/README.md` § What it denies + § What it approves → "The three outcomes" with the table, absorbing § The opaque shape; § Escalation stays. Pointers only in `AGENT_DIRECT.md`/`RUNNER.md` where they restate a shape. |
| S6. The replay fixture (§5) | `self/tests/fixtures/<name>.json`: the 24 commands of 2026-09-18, one record each with its expected verdict; `allow-repo-commands.sh` replays it. |

## Deliberately excluded

- **An explicit `ask` with a reason for the read-and-unsafe class** — it would override
  `permissions.allow` rules the human wrote, and the prompt already shows the command.
- **Approving any new program** (`ps`, `cp`, …) — a policy change, not this feature.
- **A rewrite for a whole-argument `$(…)`** — the exemption stands as documented.
- **Anything `minutes-slug-and-quoting` S5 changed** (`path_body`, `git_location_args`)
  — this feature builds on them and keeps their tests green.

## Machine-readable

```json
{
  "slug": "hook-rewrite-or-ask",
  "method": "direct",
  "plans": ["01-review-opus", "02-review-sonnet", "03-review-sonnet"],
  "branches": ["hook-rewrite-or-ask"],
  "base": "minutes-slug-and-quoting",
  "session_window": {"from": "2026-09-18T14:47:58Z", "to": "2026-09-21T15:44:39Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["aa5e47d509a167119", "a9aba3399db7d41b6"]
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
