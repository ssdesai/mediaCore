# Shell-authored files are sent back; a pinned session is never a router

Two small harness fixes, each found by a consuming-repo session reporting on itself.
Part 1, directly below, adds a hook shape. Part 2 fixes a cost double count.

## Part 1: a file authored through the shell is sent back with a rewrite

`CONVENTIONS.md` → "Writing files" says to author files with the Edit and Write tools and
never by shelling out. The reason is that a subprocess write gets past the repo's `Edit`
allow and deny rules, so the generic Bash approval is the only check left. Nothing
enforces that rule today. `cat >> tests/test_x.py <<'EOF' … EOF` is read by
`hooks/allow-repo-commands.sh` as a write and returns ASK, which prints nothing. The
human pays an approval and the model learns nothing. A consuming-repo session did
exactly this twice in a row (crud tests, then router tests), and only noticed when
asked. This shape always has a rewrite (the Write or Edit tool), so under the hook's
own membership test it belongs to REWRITE and not to ASK
(`hooks/README.md` → "The three outcomes"). This feature adds it there as one more
rewritable shape, with a reason of its own.

### The shape (the spec)

A member **authors a file through the shell** when content written in the command itself
lands in a file. There are exactly three spellings:

1. **`echo` or `printf` with its output redirected to a path**: `>`, `>>`, `>|`, `N>`,
   `&>`, attached (`>f`) or separate (`> f`), wherever it sits among the words
   (`echo a>f` is a redirect in bash too).
2. **`cat` or `tee` whose input is literal**, where the output goes to a path. The input
   is literal when it is a heredoc or herestring (`<<`, `<<-`, `<<<`) on that member, or,
   for `tee` only, when `tee` is the right-hand side of a pipe whose left-hand member is
   `echo`/`printf` or a heredoc-fed `cat`. The path is a redirect target for either
   program, or a file operand for `tee` (a word that is not a flag, not a heredoc
   operator or its delimiter, and not a redirect or its target).
3. **`sed` editing in place**: `-i` in any single-dash spelling (`-i`, `-i.bak`, `-Ei`,
   `-i ''`) or `--in-place[=…]`.

A path here means any redirect target except the non-file targets `/dev/null`,
`/dev/stdout`, `/dev/stderr` and `/dev/tty`. An fd duplication (`2>&1`, `>&2`) and a
process substitution (`>(…)`) are not targets at all. **Where the file is doesn't
matter**: the scratchpad, the project root and `/tmp` are all denied, because the Write
tool reaches all three and is checked against the rules the shell write bypasses.

**The reason** names the member as written (`MEMBER_QUOTE`, like every other rewrite) and
gives the rewrite: the **Write tool** for a new file or a whole rewrite, and the **Edit
tool** for a change to an existing file. An append is an Edit anchored on the file's
last lines. The reason doesn't cite the convention by section name alone. It says *why*
in one clause (the Edit allow/deny rules never see a shell write), because the session
that prompted this knew the rule and broke it for speed.

**Where it is judged.** It is checked after ALLOW has declined and **before** the opaque
shapes, so `tee f <<'EOF'` gets the Write reason rather than the "write a script to the
scratchpad" one. On a line that carries a heredoc, only the segments **before the first
line break** are judged (`segments_before_line_break`, as for the `cat` heredoc
exemption). The body is data, so a Markdown body full of `> quote` lines is never read as
redirects. A `#` on that judged text means the line isn't judged, which is the same guard
every other rewrite keeps. It is a REWRITE, so it counts toward `OPAQUE_REWRITE_ATTEMPTS`
and escalates to `ask` exactly like the others.

**It is a narrowing of ASK and never touches ALLOW.** Every case it fires on printed
nothing before this feature, and no case that was approved changes.

### Not this shape (stays what it was)

- A command's **output** captured to a file: `pytest > out.log`, `git diff > p.patch`,
  `grep x f > hits`, `cmd | tee log`, `cat a > b`, meaning a `cat` with no heredoc. No
  Edit or Write rewrite reproduces output nobody has seen, so these stay ASK.
- `git commit -m "$(cat <<'EOF' … EOF)"` and every other heredoc into `cat` that
  reaches no file. That exemption is untouched.
- A `>` inside quotes (`echo "a > b"`, `grep '>' f`), `sed -n …p`, and `sed` with no
  `-i`.
- `cp`, `mv`, `touch`, `mkdir`, `rm`, `ln`: writes with no Edit/Write rewrite that
  always works (binaries, moves, directories). They stay ASK.

## Part 2: a pinned session is never also a router

Folded in at the user's request, because it is small too. `feature-start.sh --pin`
always writes the routing record ("for the record always, and for the pin when `--pin` is
given"), and then also pins the same session in the manifest's `sessions`. In
`report.py --all`, that session's cost goes into the Routing table's total (from
`routing.json`) and into the feature's frozen total (from the pin). So the "routing
overhead X against Y of feature spend" line counts it on both sides. A consuming-repo
session reported this about itself ($3.78) and left it unchecked.

The design rule this breaks is **one owner per session**. A router is the session that
started a feature and belongs to none. A pin claims a session for a feature outright. So
a session is one or the other, never both. The fix makes that true in both places a
router is recorded:

1. **`feature-start.sh --pin` writes no routing record.** The pin is the link. A
   session that is this feature's coordinator isn't a router (LIFECYCLE.md step 2
   already says `--pin` is for exactly that case). Without `--pin`, nothing changes.
2. **Records already on disk.** The routing table, its fraction, and
   `report.py <slug>`'s `routed by` line all skip a routing record whose `session_id`
   some manifest in the corpus pins in `sessions`. That predicate is one function in
   `analysis/routing.py`, called by every reader, not re-derived in `report.py`
   (`routers_of` and `load_records` are already routing.py's). `--all` prints one line
   naming each record it skipped this way, so the omission is visible rather than
   silent. The record files themselves are left alone. The capture's
   `routing.py --refresh-for` still refreshes a feature's own copy as before.

Both halves are needed, and neither is a patch on the other. (1) stops new double
records from being written. (2) is the invariant the report actually relies on, and it
also covers records written before (1).

## Plans

| Plan | What it does |
|---|---|
| (direct build, `AGENT_DIRECT.md`) | one opus implementer: acceptance tests first, then the shape, the docs |
| `review/incomplete/01-review-opus.md` | independent review of the diff against the spec above |

## Deliberately excluded

- **`cp`/`mv`/`install` from a file the model just wrote.** The shape is "content
  written in the command", and a copy's content isn't in the command.
- **An interpreter script that writes files** (`python3 gen.py`). It is readable and runs
  by name, which is the rewrite the opaque shapes ask for. What it writes is the human's
  call at the prompt.
- **Deleting or rewriting routing records already on disk** for pinned sessions. The
  records are git history. The report ignoring them is the fix, and a migration would be
  a second writer.
- **A slug rename.** The feature started as the shell-write shape and grew part 2
  mid-flight. The slug is derived everywhere (branch, worktree, records), so it stays.

## Machine-readable

```json
{
  "slug": "shell-write-rewrite",
  "method": "direct",
  "plans": ["01-review-opus"],
  "branches": ["shell-write-rewrite"],
  "base": "main",
  "session_window": {"from": "2026-09-21T21:05:02Z", "to": "2026-09-21T23:13:09Z"},
  "exclude_sessions": [],
  "exclude_subagents": [],
  "sessions": [],
  "subagents": ["a66872b2844c3d58b"]
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
