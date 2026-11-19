# delegate-cost-claims — notes

Rulings made during the build, each with its reason.

- **The header grammar lives in `hooks/brief_header.py`, and `analysis/` reaches it by
  path.** The hook may not import `analysis/` (`hooks/README.md`), and both the hook and
  the capture must answer the same question the same way, so the one definition sits on
  the hook's side, stdlib only, like `orchestrator_role.py`. `capture_planning.py` puts
  `../hooks` on `sys.path` and imports it unguarded: every real copy of agentTooling ships
  both directories, and a missing module is a loud failure rather than a silently
  different reading of every brief. Test fixtures that copy `analysis/` file by file copy
  `hooks/brief_header.py` beside it.
- **The header is the first non-empty line, exactly.** `brief_feature_of` used to search
  the whole first user message for a line shaped `feature: <repo>/<slug>`. It now reads
  only the first non-empty line, through the shared definition, so the listing's "brief
  names" column, the pinned-brief check, the auto-claim and the hook agree on one rule. A
  header with a trailing remark (`feature: x/y (setup; …)`) is not a header anywhere.
  **This narrows detection**: a delegate briefed before this feature whose header sat on a
  later line of its first message, or carried a remark after the slug, was claimable by
  the old search and is now `-` in the listing and invisible to the auto-claim.
- **`feature: none — <reason>`** accepts an em dash, an en dash, `-` or `--` as the
  separator: the line is typed by humans and models, and all four are read the same way.
  **The separator needs whitespace before it**: `none — x` and `none - x` are headers,
  `none—x` and `none-x` are not (`NONE_HEADER_RE` requires `[ \t]+` after `none`), and a
  brief written that way is sent back by the hook.
  `none` names no feature, so the capture never claims such a delegate and the close's
  check does not list it.
- **Auto-claim uses the listing's own selection** (`subagent_rows`, refactored out of
  `list_subagents`): every project directory, not in the claims ledger, not already pinned
  here, started on or after the window's `from` date, brief naming this feature by
  `same_feature_ref`. On top of it, three refusals: a delegate another feature's manifest
  or a ledger pin claims (`other_feature_pins`), a delegate this feature lists in
  `exclude_subagents`, and an ambiguous brief — one carrying a second header line naming a
  different feature. Each refusal is printed with its reason.
- **The pin is written by `manifest.py pin-subagent`'s own code**, `cmd_pin_subagent`,
  called in-process with the arguments its CLI parses: same id check, same fence
  rendering, `--arm-root` honoured. `capture_planning.py` imports `manifest` only inside
  `auto_claim_briefed`, where it pins; `manifest.py` still imports nothing from
  `capture_planning`.
- **The close asks a read-only question before the PR.** `capture_planning.py
  --claim-check <slug>` runs the capture's own selection (`capture_feature(...,
  dry_run=True)`) with the on-branch reading of the window (`to` ignored, as
  `--last-branch-instant --ignore-to`), counts a delegate the capture would auto-claim as
  claimed, and writes nothing — so the pin is written by the capture and rides the cost
  commit, never the close's `S: PR` commit (which adds everything dirty).
- **What "seen" means** for the check: excluded sessions on the feature's branch (the set
  the capture's evidenced-zero note already counts), unclaimed sessions under this repo's
  directories that started inside the window (the `--list-sessions --unclaimed` rows), and
  unclaimed delegates that started inside the window whose brief names this feature or
  nothing at all (the `--list-subagents --unclaimed` rows). A delegate whose brief names a
  different feature, or `none`, is not this build and is left out: offering its pin here
  would invite exactly the mis-pin the header exists to prevent. A runner session on the
  branch is not "seen" but claimed — see the audit fix below.
- **Exit 5** (`CLAIM_CHECK_UNCLAIMED_EXIT`) is the stop; 0 is "claimed, or nothing seen";
  anything else is a check that could not run, which the close refuses on (fail closed,
  like its other checks).
- **`--allow-unclaimed "<reason>"`** writes the reason into the manifest fence as
  `allow_unclaimed` through `manifest.py allow-unclaimed`, only when the check would have
  stopped. The capture copies it into `planning.json` (`allow_unclaimed`) and `report.py`
  turns it into a warning, so the record says why its build is unclaimed. A flag given when
  the build is claimed records nothing and says so. The fence is written before the PR, so
  it is committed by the close's own `S: PR` commit (which adds everything dirty) and pushed
  with the PR — the reason is in the PR the human reads.
- **Every test sandbox that copies `capture_planning.py` now copies
  `hooks/brief_header.py`** — nineteen fixtures gained one line each. The alternative, a
  guarded import with a fallback grammar, is a second definition, which is what (c) forbids.
- **What changed for existing tests.** `feature-lifecycle.sh` C1's delegate briefed for S
  is now auto-claimed rather than warned about, so the warning path is held by a new
  ambiguous delegate (C1i2) and C2 pins that one; T3's close is first the UB refusal and
  then runs with `--allow-unclaimed`; `manifest-pin-subagent.sh` P7's delegate is pinned by
  the capture, and the hand pin after it is the no-op; `hook-orchestrator-role.sh` H5 copies
  `brief_header.py` and asserts "not the role deny" instead of "prints nothing".
- **The orchestrator rule reads the header's parse** (audit fix). It first kept its own
  `startswith("feature: ")` test, which made `feature: none — …` a role deny — so with the
  header rule, an orchestrator could spawn no Agent delegate at all — and let
  `"\nfeature: r/s"` past the role check while the header check stripped the newline and
  accepted it. `judge_agent` now parses the prompt once with `brief_header.parse`: the
  role deny fires only on a `feature: <repo>/<slug>` header, and the bare `startswith` is
  the fallback when `brief_header.py` is missing. `ORCHESTRATOR_SESSION_BRIEF.md` tells an
  orchestrator to head its own delegates `feature: none — <reason>`.
- **A runner-built feature is claimed** (audit fix). `--claim-check` first listed runner
  sessions on the branch as "met", so a feature built only by `run-batch.sh` exited 5 while
  the capture wrote the same evidence as an accepted zero. A runner session on the branch
  now returns 0, as the capture does; only manual `exclude_sessions` entries are listed.
- **The auto-claim runs after the walk** (audit fix). Before it, it pinned a headed
  delegate of a runner session — never priced, since the runner's `usage.json` holds it,
  so the pin read back forever as "matches no transcript" — and one of a parent the capture
  already selects, a duplicate claim. Now it skips both, and a pin it does write is priced
  by the pin fallback that runs next.
