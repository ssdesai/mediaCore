Verdict: clean

# Security audit — pull-round-cleanups (round 03, opus)

Scope: `git diff origin/main...HEAD -- analysis/README.md analysis/roots.py orchestration-start.sh`.
None of the three files is the PreToolUse hook (`hooks/allow-repo-commands.sh` is unchanged by
this diff). The rule the diff changes is a lifecycle-script refusal, attacked as one:

- **R-start** — `orchestration-start.sh <slug>` without `--self`, from a vendored copy, refuses
  when `agentTooling/self/orchestrations/<slug>` exists and its last fence is STRANDED (lists the
  consumer, not agentTooling: `git mv` text) or, new, AMBIGUOUS (lists both, or the consumer's
  name is agentTooling's: both readings). The decision moved from `roots.py stranded` (exit 0 =
  refuse, any other exit = go on: fail-open) to `roots.py start-refusal` (exit 0 = go on, anything
  else = refuse: fail-closed). For whom: any session starting an orchestration in a consuming repo.
- **R-tools** — `record_refusal` (manifest.py / report.py / orchestration-capture.sh without
  `--self`) now routes through `legacy_start_refusal`: stranded → `git mv`, ambiguous → the
  ambiguous text, else `OWN_RECORD_NOTE`. Exit 1 in every case, as before.
- **R-cli** — `roots.py stranded` now answers no (1) for an ambiguous record (base: yes). Nothing
  in the tree consumes it any more except the self-tests (`grep` of every `.sh`/`.py`); the start
  uses `start-refusal`.
- The hook's one orchestrator write approval (`orchestrator_moves_own_record`, the `git mv` of a
  legacy record) does not consult the classifier and is unchanged by this diff.

Method: two throwaway consumer fixtures under the scratch directory, each a `git init`ed
`consumer/` with `git archive <ref>` extracted to `consumer/agentTooling/` (no `.git` there, as a
subtree leaves it) — `origin/main` for base, `HEAD` for head. Legacy records planted under
`consumer/agentTooling/self/orchestrations/<slug>/README.md`. Each input was run as
`agentTooling/orchestration-start.sh <slug> --coordinator --session <uuid>` (rc, whether
`plans/orchestrations/<slug>` was written, which text), `roots.py stranded <slug>`, and
`manifest.py --orchestration <slug> get session`. `AGENTTOOLING_PROFILE=local`, fake `HOME`.
Scripts: `attack.sh` (record shapes), `attack2.sh` (crashes, name collisions, slug shapes),
`attack3.sh` (CLI argv), all in the scratch directory.

## Inputs tried

Consumer name `consumer` unless stated. "refused gitmv" = rc 1, nothing written, `LEGACY_RECORD_REFUSAL`;
"refused ambiguous" = rc 1, nothing written, `AMBIGUOUS_RECORD_REFUSAL`; "allowed" = rc 0, record written.
Manifest column: rc 1 in every row on both; text named.

| # | Input (last fence `features`, or shape) | Start — base | Start — head | `stranded` base/head | manifest base → head |
|---|---|---|---|---|---|
| 1 | `[{"repo":"consumer"}]` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 2 | `[{"repo":"CONSUMER"}]` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 3 | `consumer` + `agentTooling` | refused gitmv | refused ambiguous | 0/1 | gitmv → ambiguous |
| 4 | `Consumer` + `AGENTTOOLING` | refused gitmv | refused ambiguous | 0/1 | gitmv → ambiguous |
| 5 | `consumer` + `"agentTooling "` (trailing space) | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 6 | `consumer` + `agentTooling.git` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 7 | `consumer` + `https://github.com/ssdesai/agentTooling.git` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 8 | `consumer` + `{"repo":null}` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 9 | `consumer` + bare string `"agentTooling"` (non-dict) | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 10 | `consumer` + `{"repo":["agentTooling"]}` | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 11 | `[{"repo":"agentTooling"}]` | allowed | allowed | 1/1 | own note → own note |
| 12 | `[]` | allowed | allowed | 1/1 | own note → own note |
| 13 | `{"repo":"consumer"}` (features not a list) | allowed | allowed | 1/1 | own note → own note |
| 14 | `["consumer"]` (list of strings) | allowed | allowed | 1/1 | own note → own note |
| 15 | `[{"repo":" consumer"}]` (leading space) | allowed | allowed | 1/1 | own note → own note |
| 16 | `[{"repo":"consumer.git"}]` | allowed | allowed | 1/1 | own note → own note |
| 17 | `[{"repo":1}]` | allowed | allowed | 1/1 | own note → own note |
| 18 | two fences: consumer, then agentTooling | allowed | allowed | 1/1 | own note → own note |
| 19 | two fences: agentTooling, then consumer | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 20 | two fences: mixed, then consumer only | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 21 | fence listing consumer, then a last fence of invalid JSON | allowed | allowed | 1/1 | own note → own note |
| 22 | duplicate `features` key, last = agentTooling | allowed | allowed | 1/1 | own note → own note |
| 23 | duplicate `features` key, first mixed, last consumer | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 24 | duplicate `repo` key in a feature, last = consumer | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 25 | no ```` ```json ```` fence (bare JSON) | allowed | allowed | 1/1 | own note → own note |
| 26 | untagged ```` ``` ```` fence | allowed | allowed | 1/1 | own note → own note |
| 27 | `README.md` is a directory | allowed | allowed | 1/1 | own note → own note |
| 28 | slug folder with no `README.md` | allowed | allowed | 1/1 | own note → own note |
| 29 | `self/orchestrations/<slug>` is a regular file | allowed | allowed | 1/1 | own note → own note |
| 30 | relative symlink to a stranded record | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 31 | relative symlink to a mixed record | refused gitmv | refused ambiguous | 0/1 | gitmv → ambiguous |
| 32 | absolute symlink to a stranded record | refused gitmv | refused gitmv | 0/0 | gitmv → gitmv |
| 33 | dangling symlink | allowed | allowed | 1/1 | other (rc 1) → same |
| 34 | stranded record, `analysis/routing.py` given a syntax error | **allowed** (fail-open) | refused "could not be classified" | — | — |
| 35 | mixed record, same broken `routing.py` | **allowed** (fail-open) | refused "could not be classified" | — | — |
| 36 | stranded record, `capture_planning.py` raises on import | **allowed** (fail-open) | refused "could not be classified" | — | — |
| 37 | stranded record, `analysis/roots.py` deleted | **allowed** (fail-open) | refused "could not be classified" (exit 2) | — | — |
| 38 | stranded record, intact tree (control) | refused gitmv | refused gitmv | — | — |
| 39 | record listing only `vinyl` (control) | allowed | allowed | — | — |
| 40 | `--self s1` from the vendored copy | refused (consumer-record-guard) | same | — | — |
| 41 | consumer dir `AgentTooling`, record `[{"repo":"AgentTooling"}]` | refused gitmv | refused ambiguous | — | — |
| 42 | consumer dir `AgentTooling`, record `[{"repo":"vinyl"}]` | allowed | allowed | — | — |
| 43 | consumer dir `AgentTooling`, mixed record | refused gitmv | refused ambiguous | — | — |
| 44 | consumer origin `…/AGENTTOOLING.git`, record `AgentTooling` | refused gitmv | refused ambiguous | — | — |
| 45 | consumer origin `…/AGENTTOOLING.git`, record `consumer` only | allowed | allowed | — | — |
| 46 | slug `-h`, `--self` (as slug), `../x`, `a b`, `s1/` | refused (slug pattern) | refused (slug pattern) | — | — |
| 47 | `roots.py start-refusal` / `stranded` with `../orchestrations/s1`, `s1/.`, `./s1` (resolve to a stranded record) | `stranded` 0 | `stranded` 0, `start-refusal` 1 (refuse) | — | — |
| 48 | the same CLIs with `S1`, `s1/README.md`, `/nonexistent` | `stranded` 1 | `stranded` 1, `start-refusal` 0 (no record there) | — | — |
| 49 | `roots.py start-refusal` with no slug | rc 2 (usage) | rc 2 (usage) | — | — |

No input is more permissive on head than on base. Every change of result is head refusing
where base refused with different text (3, 4, 31, 41, 43, 44) or head refusing where base went
on (34–37: the fail-open crash path base had is closed). Row 47–48's CLI argv never reaches the
start with those values: the slug pattern (row 46) refuses them first, on both.

## Findings

| class | input | head result | base result | evidence |
|---|---|---|---|---|
| non-blocking | row 21: legacy record whose earlier fence lists `consumer` and whose LAST fence is unparseable JSON | start allowed (rc 0, writes `plans/orchestrations/<slug>`); tools say "agentTooling's own" | the same | `attack.sh` slug `c-badjson-last`: `consumer/agentTooling/orchestration-start.sh c-badjson-last --coordinator --session <uuid>` in `w/base/consumer` and `w/head/consumer` |
| non-blocking | rows 15–16: `[{"repo":" consumer"}]` / `[{"repo":"consumer.git"}]` | start allowed; own note | the same | `attack.sh` slugs `c-space`, `c-dotgit`, same command on both copies |
| non-blocking | rows 5–7: `consumer` + `"agentTooling "` / `agentTooling.git` / an agentTooling origin URL | refused with the `git mv` (classed stranded, not ambiguous) | the same | `attack.sh` slugs `c-mixed-tool-space`, `c-mixed-tool-git`, `c-mixed-tool-url`, same command on both copies |

## Non-blocking findings

1. **Pre-existing silent allow — unreadable last fence.** Input: a legacy vendored record whose
   earlier fence lists the consuming repo and whose last fence does not parse (row 21; rows 25–27
   are the same family). Base and head both let the no-`--self` start go on, writing a second
   record under the same slug, and the record tools call it agentTooling's own. The rule should
   fail closed on a `README.md` that exists but whose last fence cannot be read — refuse the start
   naming the file, as the new crash path (rows 34–37) already does — rather than read
   "unreadable" as `CLAIM_OWN`. File in `self/BACKLOG.md`.
2. **Pre-existing silent allow — repo names not normalized.** Input: `features[].repo` of
   `" consumer"` or `"consumer.git"` (rows 15–16). Base and head both compare the raw string,
   lower-cased only, so the record reads as not the consumer's and the start goes on. The rule
   should normalize each `repo` the way the home name is derived (`repo_display_name` — last path
   segment, `.git` stripped — and whitespace stripped) before comparing. File in `self/BACKLOG.md`.
3. **Pre-existing — mixed wave with a non-canonical agentTooling name classed stranded.** Input:
   a fence listing `consumer` and `agentTooling.git` / `"agentTooling "` / an agentTooling origin
   URL (rows 5–7). Both refuse the start (no permissiveness change), but both prescribe the
   `git mv`, which for an agentTooling cross-repo wave deletes shipped records from the consumer's
   `agentTooling/` — the very case the new `CLAIM_AMBIGUOUS` exists for. The same normalization as
   item 2 applied to the agentTooling name would class these ambiguous. File in `self/BACKLOG.md`.

## Blocking findings

None.
