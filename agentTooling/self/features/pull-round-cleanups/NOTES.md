# pull-round-cleanups — notes

## §0 How this feature started: `--no-gate`, with the owner's go

`feature-start.sh --self pull-round-cleanups` was refused twice: "the gate is not green on
origin/main". The first run was on `a130257` (#169). The second was on `2141e27` (#170),
with no other start running at the same time. Both times exactly one section failed:
`orchestrator-role.sh`, "21 check(s) FAILED". The same test passed standalone, twice, and the
whole gate passed twice standalone on the same tree.

**Cause.** In the cloud, `feature-start.sh` sources `env-profile.sh`, which runs `export
AGENTTOOLING_PROFILE=cloud`, and the gate it runs inherits that. `orchestrator-role.sh` cleared
`CLAUDE_CODE_SESSION_ID GATE_RESUME CLAUDE_CODE_REMOTE` but not `AGENTTOOLING_PROFILE`, so its
fixture's setup ran as cloud. Reproduced with `AGENTTOOLING_PROFILE=cloud bash
self/tests/orchestrator-role.sh`: exactly 21 FAILs (G1a/G1b, G2–G6 two lines each, G7a, G8b,
G9a–c, G11a–b). #169 merged green because its gate ran standalone, where nothing exports the
profile. Every cloud start of an agentTooling feature was refused until this is fixed.

**Ruling.** The orchestrator ruled to start with `--no-gate` and make the one-line fix this
feature's first commit, relaying the owner's go ("you're free to tell them to go and fix").
This session's auto-mode permission check refused that start when the OK came relayed; the
owner then typed the OK in this session ("OK to run the feature-start with --no-gate, and to
make the AGENTTOOLING_PROFILE fix your first commit"). The manifest records `"gate":
"skipped"`. The base was green standalone. The leak was the only failure, and this feature's
gate runs green with it fixed.

## §1 Item 1: which records are agentTooling's own

`roots.is_stranded_record` called a vendored record stranded when its last fence listed any
feature whose `repo` is the consuming repo's. An agentTooling cross-repo wave lists consumer
features too, so in a consumer `tooling-wave-2026-11-17` was told to `git mv` itself out of
`agentTooling/`.

**Round-1 rule:** a record whose last fence also lists a feature with `repo` = agentTooling (the
declared self corpus identity, `orchestration_home_repo(True)`, any case) is agentTooling's own
and never stranded. Round 2 changed it after the security audit (below).

Alternatives considered:

- **The fence's `agent_tooling` key or `session`.** Every record carries an `agent_tooling`
  sha, whether run with `--self` or from a consumer; it names the tooling version, not who ran
  the record. Session ids carry no repo. Neither discriminates.
- **Provenance: is the path in the tree the last subtree pull shipped?** This is the exact
  definition ("a vendored record that is NOT stranded is agentTooling's own, shipped with the
  subtree", `roots.py`). But only `update.sh` (bash) finds the squash commit, and porting it
  into `roots.py` means a second reader of the trailer chain, to classify a historical case.

**Round 2, after the security audit.** Round 1 called a mixed record agentTooling's own
outright. The audit escalated it as a regression: a consumer-run mixed wave left in the vendored
copy has the same bytes, and its slug, which the base refused to start, now started (finding 1).
The same happened in a consumer whose name is agentTooling's (finding 2). The fence cannot tell
the two apart, so the rule is now three-way (`roots.legacy_record_claim`):

- **stranded**: the record lists consumer features and no agentTooling one. The `git mv` is
  prescribed, as before.
- **ambiguous**: it lists both, or the consumer's name is agentTooling's and it lists that name.
  `roots.py stranded` says no, so a consumer's check never demands the move that deletes an
  agentTooling wave. Every record tool and the start still refuse it, with
  `AMBIGUOUS_RECORD_REFUSAL`. That text names both readings: leave it and use another slug if
  agentTooling ran it; the `git mv` only if this repo did.
- **own**: as before.

Every case is refused at least as strictly as on the base. The start's check also fails closed
now: a classifier that cannot run refuses the start, where before it read as "not stranded".
The new text lives in `analysis/roots.py`, not `hooks/shared_rules.py`. The hook does not
consult the classifier, and `hooks/` is the sibling feature's this round.

## §2 Item 2: `readme-structure` is not a stranded consumer copy

The brief asked to remove `self/orchestrations/readme-structure/` after confirming its fence
lists only humanNetworkMap features and nothing in agentTooling reads it. Neither holds:

- its fence lists 5 agentTooling features (`harness-arm-base`, `readme-index-check`,
  `harness-spec-per-arm`, `harness-arm-spec`, `harness-long-runs`), 3 humanNetworkMap,
  2 musicMap and 6 vinylCatalogue;
- four agentTooling manifests carry `"orchestration": "readme-structure"`
  (`self/features/{readme-index-check,harness-arm-base,harness-arm-spec,harness-long-runs}/`),
  which `report.py --self --orchestration readme-structure` joins, and `self/BACKLOG.md` cites
  its path;
- it was committed in agentTooling itself (`a415aef`, 2026-11-03, path `self/orchestrations/…`).

So it is item 1's case: an agentTooling-held mixed wave that the old classifier called
stranded in humanNetworkMap, which then moved it. The orchestrator ruled it resolved by item 1
and left in place. humanNetworkMap's `edited` chain is repaired there, by restoring its
vendored copy, once item 1 is pulled.

Every other record in `self/orchestrations/`: `ablation-wave` (agentTooling, vinylCatalogue),
`agenttooling-roles`, `hook-hardening-wave`, `program-ab`, `rehearsal-prep` (agentTooling only),
`tooling-wave-2026-11-17` (agentTooling, humanNetworkMap). None lists only consumer features;
none is removed.

## §3 Addendum: the sweep for the same leak

`./self/gate.sh` was run whole with `AGENTTOOLING_PROFILE=cloud` exported (and
`CLAUDE_CODE_REMOTE=true`, which this container already sets), the way a cloud start runs it,
after the `orchestrator-role.sh` fix: "all checks passed". No other self-test inherits the
caller's profile or cloud environment, so none needed the treatment.

The lasting check is in the test itself. `orchestrator-role.sh` runs `export
AGENTTOOLING_PROFILE=cloud` just before its `unset`, standing in for a cloud start's caller on
every run, standalone included. If the variable is dropped from the `unset`, the same 21 checks
fail in every gate, at no extra run. The first try put the check in `self/gate.sh` as `env
AGENTTOOLING_PROFILE=cloud bash …`. The gate's "profile variables confined" check refused it:
only the detector, its adapters and their tests may name the profile. So the check moved into
the test, and this feature leaves `self/gate.sh` as main has it.

## §4 Items 3 and 4

- Item 3 is documented where the brief named it: `LIFECYCLE.md` → "Propagate" (step 2's
  attach paragraph, and step 4's cloud child bullet for the merge scope), `README.md` →
  "Updating", and `ORCHESTRATION.md` → "Cloud sessions" (the permission-prompts bullet, and a
  new bullet for the merge scope).
- Item 4(a) was already filed by #169 (`self/BACKLOG.md`, "An assigned cloud branch that is
  not `claude/<slug>` cannot be named to `orchestration-start.sh --branch`"); left as it is.
- Item 4(b) is one entry pointing at `self/DESIGN-2026-11-19-hook-allowlist.md` (merged as
  #170) and its §8 `hook-allowlist-approval`, per the owner's answer to that design's
  question 7.
- The gate report's 40-line tail is filed, not fixed (an audit path for a reporting gap).
