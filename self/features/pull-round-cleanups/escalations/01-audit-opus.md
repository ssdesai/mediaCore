Verdict: escalated

# Security audit — pull-round-cleanups (round 1)

Head: `HEAD` of `claude/pull-round-cleanups`. Base: `origin/main`.

## Scope

The diff touches two files on the plan's list: `analysis/README.md` (prose only) and
`analysis/roots.py`. The one rule changed is **`roots.is_stranded_record(slug)`**. It
classifies a legacy record under the vendored `agentTooling/self/orchestrations/<slug>/` as
the consuming repo's own ("stranded"). Before, it was stranded if its last fence listed a
feature whose `repo` matched the consumer's name, compared case-insensitively. Now a fence that
also lists a feature whose `repo` is `agentTooling` (case-insensitive) is never stranded.

Who relies on it:
- **`orchestration-start.sh`** (lines 241–244, through `python3 roots.py stranded <slug>`)
  refuses a non-`--self` start whose slug has a stranded vendored record and prints the `git mv`.
  If the record is not stranded, the start goes on.
- **`record_refusal`** (`report.py`, `manifest.py`, `coordinator_check.py`) refuses either
  way: with the `git mv` when stranded, otherwise with `OWN_RECORD_NOTE`.
- **The PreToolUse hook** does not import the classifier.
  `hooks/allow-repo-commands.sh`'s `orchestrator_moves_own_record` and
  `hooks/orchestrator_role.py` do not call it (grep for `is_stranded_record`, `roots.py stranded`
  and `record_refusal` across `hooks/`: no hit). The hook's decisions are unchanged by this diff,
  so the attack surface is the lifecycle refusal in `orchestration-start.sh`.

Method: two throwaway consumers per run, built in
`/tmp/plan-capture.ihSZih/scratch/{head,base}-<name>/<name>/`. Each was made by
`git archive HEAD` or `git archive origin/main` into `<name>/agentTooling/`, inside a fresh
`git init` consumer with no origin, so the consumer's repo name is its directory name. A crafted
legacy record was planted for each case at `agentTooling/self/orchestrations/x-<case>/README.md`.
Three commands were run on each copy, in this order:
1. `python3 -B agentTooling/analysis/roots.py stranded x-<case>` (0 = stranded, 1 = not)
2. `python3 -B agentTooling/analysis/report.py --orchestration x-<case>`, which shows whether
   the record-tool refusal carries the `git mv` or the own-record note
3. `./agentTooling/orchestration-start.sh x-<case> --coordinator --session dddddddd-0000-0000-0000-00000000000b`
   (`AGENTTOOLING_PROFILE=local`)

Script: `/tmp/plan-capture.ihSZih/scratch/audit.sh <consumer-name>`, run as
`audit.sh consumer` and `audit.sh AgentTooling`. Every crafted record has the form
`{"slug": …, "session": "eeeeeeee-…-00000000000c", "features": <F>}`.

## Attempts

"start" columns: 0 = the start goes on and writes `plans/orchestrations/<slug>/`; 1(git mv) = it
is refused with the move; a bare 1 = it is refused for another reason (here the slug pattern
rejects the upper-case `I`, on both sides). "report" columns: rc / which refusal text was shown.

### Consumer repo named `consumer`

| case | `features` (`<C>` = `{"repo": "consumer", "slug": "a"}`) | head stranded | base stranded | head start | base start | head report | base report | wrong? |
|---|---|---|---|---|---|---|---|---|
| consumer-only | `[<C>]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| mixed | `[<C>, {"repo":"agentTooling"}]` | 1 | 0 | **0** | 1(git mv) | 1/own-note | 1/gitmv | **yes for a consumer-run wave** (finding 1) |
| mixed-upper | `[<C>, {"repo":"AGENTTOOLING"}]` | 1 | 0 | **0** | 1(git mv) | 1/own-note | 1/gitmv | same as mixed |
| at-only | `[{"repo":"agentTooling"}]` | 1 | 1 | 0 | 0 | 1/own-note | 1/own-note | no |
| near-trailsp | `[<C>, {"repo":"agentTooling "}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-dotgit | `[<C>, {"repo":"agentTooling.git"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-owner | `[<C>, {"repo":"ssdesai/agentTooling"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-url | `[<C>, {"repo":"https://github.com/ssdesai/agentTooling.git"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-short | `[<C>, {"repo":"agentToolin"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-zwsp | `[<C>, {"repo":"agentTooling​"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-fullwidth | `[<C>, {"repo":"ａgentTooling"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| near-dotted-I | `[<C>, {"repo":"AGENTTOOLİNG"}]` | 0 | 0 | 1 | 1 | 1/gitmv | 1/gitmv | no |
| repo-list | `[<C>, {"repo":["agentTooling"]}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| repo-null | `[<C>, {"repo":null}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| repo-missing | `[<C>, {"slug":"s"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| str-entry | `[<C>, "agentTooling"]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| nested-dict | `[<C>, {"x":{"repo":"agentTooling"}}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| features-dict | `{"repo":"consumer"}` (not a list) | 1 | 1 | 0 | 0 | 1/own-note | 1/own-note | pre-existing, unchanged |
| consumer-upper | `[{"repo":"CONSUMER"}]` | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| two-last-consumer | an earlier fence is mixed, the last is consumer-only | 0 | 0 | 1(git mv) | 1(git mv) | 1/gitmv | 1/gitmv | no |
| two-last-mixed | an earlier fence is consumer-only, the last is mixed | 1 | 0 | **0** | 1(git mv) | 1/own-note | 1/gitmv | same as mixed |

### Consumer repo named `AgentTooling` (its name is agentTooling's, ignoring case)

| case | head stranded | base stranded | head start | base start | head report | base report | wrong? |
|---|---|---|---|---|---|---|---|
| consumer-only (`[{"repo":"AgentTooling"}]`) | 1 | 0 | **0** | 1(git mv) | 1/own-note | 1/gitmv | **yes** (finding 2) |
| every other case above, except features-dict and near-dotted-I | 1 | 0 | 0 | 1(git mv) | 1/own-note | 1/gitmv | ambiguous: the consumer's name collides with agentTooling's |
| near-dotted-I | 1 | 0 | 1 (slug) | 1 (slug) | 1/own-note | 1/gitmv | the start is refused on both sides; the report refuses on both |
| features-dict | 1 | 1 | 0 | 0 | 1/own-note | 1/own-note | unchanged |

Observations:
- **Exact match.** The new exemption takes exactly `agentTooling` with any casing. Every
  near-miss (whitespace, `.git`, owner prefix, URL, truncation, zero-width space, full-width
  letter, dotted I, non-string `repo`, a string entry, a nested dict) stays stranded, exactly as
  on the base.
- **Last fence only.** An agentTooling feature in an earlier fence does not exempt the record.
- **Record tools.** `report.py` refuses on both sides in every case (rc 1). Only the text
  changes, from the `git mv` to `OWN_RECORD_NOTE`, so record reads are not more permissive.
- **Hook.** Nothing in `hooks/` consults the classifier, so no PreToolUse decision changes.
  The hook's own `git mv` approval (`orchestrator_moves_own_record`) checks the session's record
  on its own terms.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| blocking | legacy record `agentTooling/self/orchestrations/x-mixed/README.md` whose last fence lists `[{"repo":"consumer"},{"repo":"agentTooling"}]`, written by the CONSUMER (a consumer-run cross-repo wave left in the vendored copy); then `orchestration-start.sh x-mixed --coordinator --session dddddddd-0000-0000-0000-00000000000b` | allowed: the start goes on (rc 0) and writes `plans/orchestrations/x-mixed/`; `roots.py stranded` rc 1 | refused, rc 1, with the `git mv`; `roots.py stranded` rc 0 | `bash /tmp/plan-capture.ihSZih/scratch/audit.sh consumer`, rows mixed, mixed-upper, two-last-mixed, run in `head-consumer/` (git archive HEAD) and `base-consumer/` (git archive origin/main) |
| blocking | consumer repo named `AgentTooling` (any casing of agentTooling), legacy record `x-consumer-only` listing only `[{"repo":"AgentTooling"}]`; then `orchestration-start.sh x-consumer-only --coordinator --session dddddddd-0000-0000-0000-00000000000b` | allowed: the start goes on (rc 0); `roots.py stranded` rc 1 | refused, rc 1, with the `git mv`; `roots.py stranded` rc 0 | `bash /tmp/plan-capture.ihSZih/scratch/audit.sh AgentTooling`, row consumer-only, run in `head-AgentTooling/` and `base-AgentTooling/` |
| non-blocking | legacy record whose `features` is a dict, not a list (`{"repo":"consumer"}`); then `orchestration-start.sh x-features-dict …` | allowed (rc 0); not stranded | allowed (rc 0); not stranded | `audit.sh consumer`, row features-dict, on both copies |

## Non-blocking findings

- **Pre-existing silent allow: a malformed `features` is never stranded.** A legacy record
  whose last fence has `features` as a dict, or any non-list, makes `roots.py stranded` answer
  "not stranded" on both head and base. `orchestration-start.sh` then goes on, and the record
  tools give `OWN_RECORD_NOTE`.
  - What the rule should do instead: treat a record with no readable `features` list as
    unclassifiable and fail closed in `orchestration-start.sh` (refuse, naming the malformed
    record), rather than treating it as agentTooling's own.
  - This is low impact: nothing is moved or deleted, and the start writes only the consumer's
    own folder. To file in `self/BACKLOG.md`.

## Blocking findings

Both blocking findings are the same regression. A slug with a vendored legacy record that the
base refuses to start, and answers with the `git mv`, is no longer refused on the head.

### 1. A consumer-run mixed wave is no longer stranded

- **Reproduce:** in a consumer named `consumer`, plant
  `agentTooling/self/orchestrations/x-mixed/README.md` with the fence
  `{"slug":"x-mixed","session":"eeeeeeee-0000-0000-0000-00000000000c","features":[{"repo":"consumer","slug":"a"},{"repo":"agentTooling","slug":"s"}]}`.
  Then run `./agentTooling/orchestration-start.sh x-mixed --coordinator --session dddddddd-0000-0000-0000-00000000000b`.
  - Head: rc 0, a new `plans/orchestrations/x-mixed/` is written, and the vendored record is
    left in place.
  - Base: rc 1, with `git mv agentTooling/self/orchestrations/x-mixed plans/orchestrations/x-mixed`.
- **Why it is wrong:** the head cannot tell an agentTooling-run mixed wave from a consumer-run
  one, because the fence bytes are identical. For the consumer-run case, the head's
  "not stranded" is a misclassification. The feature's own NOTES §1 acknowledges it ("The only
  record the new rule could misclassify is a consumer-run mixed wave still left in a vendored
  copy"). That case is now more permissive than on the base: the start is no longer refused.
- **Severity in practice:** no privilege is gained.
  - The start writes only the consumer's own record folder, which a different slug would reach
    on both sides anyway.
  - Nothing is moved or deleted, and no hook decision changes.
  - Per NOTES §1, no record tool has written under a vendored `self/orchestrations/` since
    `consumer-record-guard`, so only pre-existing records can be affected.
  - Under the owner's ruling it is still a regression, so it blocks.
- **What the rule should do instead:** classify by provenance, not by the fence's repos alone.
  A vendored record that is tracked in the tree the last subtree pull shipped is
  agentTooling's own. One that the consumer added or edited on top of the subtree is stranded.
  This is the "Provenance" alternative in NOTES §1. Failing that, the owner should rule this
  documented tradeoff accepted. The audit rule has no carve-out that lets it pass as
  `non-blocking` on the auditor's judgment.

### 2. A consumer whose repo name is agentTooling's is never stranded

- **Reproduce:** run `bash /tmp/plan-capture.ihSZih/scratch/audit.sh AgentTooling`. The
  consumer directory, and so `orchestration_home_repo(False)`, is `AgentTooling`. A record
  listing only `[{"repo":"AgentTooling"}]` gives:
  - Head: `roots.py stranded` rc 1, and the start goes on (rc 0).
  - Base: `roots.py stranded` rc 0, and the start is refused with the `git mv`.
- **Why:** the new check `orchestration_home_repo(True).lower() in repos` runs before the
  consumer test. When the consumer's name equals agentTooling's ignoring case, every record is
  exempt.
- **Severity in practice:** this only happens in a consumer repo that shares agentTooling's
  name. In such a repo the base was itself ambiguous: it called every shipped agentTooling
  record stranded and advised the `git mv` that this feature exists to stop.
- **What the rule should do instead:** when `orchestration_home_repo(False)` equals
  `orchestration_home_repo(True)` ignoring case, the fence cannot classify the record. The
  rule should fall back to provenance, as in finding 1, or refuse the start with a message
  that names the ambiguity, rather than silently going on.
