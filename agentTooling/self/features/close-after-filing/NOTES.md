# close-after-filing — rulings

## The contradiction

`ORCHESTRATION.md` → "Rules", `LIFECYCLE.md` → "The security audit",
`templates/SECURITY_AUDIT.md` and `hooks/README.md` said a clean round's non-blocking
findings are filed in the BACKLOG by the coordinator before the close (#154,
`audit-blocks-only-new`). `feature-close.sh` refused every commit after the judged head
except the harness's own subjects (`S: cost records`, `S: PR`, `S: review stamps`), so a
BACKLOG-only commit was "round N+1": a new review, whose audit could find new non-blocking
items to file, and so on. Logged on #153 (the `own-push-credential-keys` comment).

## Ruling: option (a)

`feature-close.sh` accepts, after the judged head, a commit under the one subject
`<slug>: backlog` (`BACKLOG_COMMIT_SUFFIX`) whose whole change is the repo's BACKLOG file
(`BACKLOG_LABEL` in `resolve_roots`: `self/BACKLOG.md` under `--self`, `plans/BACKLOG.md`
in a consumer, behind `agentTooling/` where the self layout is vendored), and refuses
everything else as before. The refusal for any other commit now names that path.

Why (a) and not (b): filing is not rework, and (b) would make the coordinator write the
findings before the verdict that classes them exists — the review round commits the audit
report and stamps the verdict in one pass, so "before the stamped head" means inside the
executor's run, which may not edit the repository (`templates/SECURITY_AUDIT.md`).

Why (a) weakens no guarantee the security audit relies on. The audit's guarantees at the
close are, from `feature-close.sh` §1:

- **F1** — nothing after the judged head touches an audit path, whatever its subject:
  `audit_paths_in_range "$JUDGED_HEAD..HEAD"` still runs over the whole range, independent
  of the per-commit subject loop, and the BACKLOG is no audit path in either layout
  (`AUDIT_TOOLING_PATHS`). The new case admits nothing else, so it adds no path F1 must see.
- **N8** — audit evidence (an audit plan, `audit-report.md`, an `audit_end` line) is read
  from git at the judged head and from the FIRST `S: review stamps` commit after it. A
  `S: backlog` commit can carry none of those files, and it is not a stamps commit, so the
  `STAMPS_SHA` lookup is unchanged whether it comes before or after the stamps.
- **F4/F7 and the classes** — read at the judged head or from the manifest's base; a
  BACKLOG commit changes neither.

What the BACKLOG commit could still do, and why each is shut:

- carry another file under the subject — the change must be exactly the one path
  (`--no-renames`, NUL-separated names, compared whole);
- hide a change behind a merge — a merge's combined diff omits what either side brought
  in, so the commit must have exactly one parent (`SINGLE_PARENT_WORDS`) and its
  diff is taken against that parent;
- turn the BACKLOG into something that runs or points elsewhere — deletion, a symlink or
  an executable bit is refused: the file must remain mode `100644` (`REGULAR_FILE_MODE`);
- land the other layout's file — only `BACKLOG_LABEL` for the run's layout matches.

## Round 2: the security audit's B1

Round 1's audit escalated on one regression (`escalations/01-audit-opus.md`): the name list
was read through `$(…)`, which strips trailing newlines, so a new file named
`self/BACKLOG.md<LF>` (any content, any mode) compared equal to `self/BACKLOG.md` and rode
the subject. The ruling is `commit_changes_only <sha> <path>` in `feature-close.sh`: one
parent, the NUL-separated `--no-renames` diff against it, and a sentinel
(`NAME_LIST_SENTINEL`) printed after the list inside the substitution so nothing trailing
is stripped. The `S: review stamps` case had the same comparison and the same hole
(`timing.jsonl<LF>`, pre-existing); it now goes through the same helper, which also adds
the one-parent and renames-off rules to it — a strict tightening, since `run-review.sh`'s
stamps commit is always a single-parent commit of `timing.jsonl` alone.
`self/tests/close-backlog.sh` K11/K12 hold both.

The review's non-blocking notes (round 1): `self/tests/security-audit.sh` is listed for
`bash -n` but has no `record` line, so the gate never runs it (pre-existing); the vendored
`agentTooling/` prefix of `BACKLOG_REL` is untested (the same expression `FEATURE_REL`
uses); K5 did not assert the hint — tightened in round 2. The first two are filed on #153
(the brief: until this lands, non-blocking findings go there).

## Round 3: the security audit's round-2 B2

Round 2's review escalated on its audit's B2 (`review-report.md` → E1, `audit-report.md`
C18/S1/S2): `git diff` is porcelain and honours `submodule.<name>.ignore` from the
worktree's `.gitmodules` and `diff.ignoreSubmodules` from config even between two commits,
so a gitlink beside the BACKLOG — with an uncommitted, info/exclude-hidden `.gitmodules`
saying `ignore = all` — listed as the BACKLOG alone. The ruling: every name list the close
judges a commit by is read `--ignore-submodules=none`, the flag the audit verified (T1) —
`commit_changes_only`, the cost/PR case's `git show` (the same pre-existing hole), and
`audit_paths_in_range` in `plan-runner-roots.sh`, so F1 lists a gitlink under an audit path
too (S2 put one at `hooks/sub`). The audit's non-blocking C24 (a stamps commit making
`timing.jsonl` executable, pre-existing) is closed in the same place: the `100644` check
moved into `commit_changes_only`, so it binds both subjects (`REGULAR_FILE_MODE`). K13/K14
hold them.

## Round 4: the security audit's round-3 B3

Round 3 escalated on its audit's B3 (`escalations/03-audit-opus.md`, A08): a local
`git replace <real> <fake>`, with a stand-in `<slug>: backlog` commit touching only the
BACKLOG on the same parent, made every `git log`/`diff`/`show` in the close read the
stand-in while `git push` sent the real commit with its unreviewed `hooks/policy.py`. The
same attack under `<slug>: review stamps` (A09) is pre-existing.

**Ruling: the close reads history with replace refs off.** `feature-close.sh` exports
`GIT_NO_REPLACE_OBJECTS=1` before its first git call, so every call it makes — its own, the
sourced `plan-runner-roots.sh` functions (`audit_paths_in_range`, `audit_paths_touched`,
`stray_paths`), and the analysis scripts it runs — resolves the objects `git push` sends.
That closes A08 and A09 together (K15a/b). The audit verified the export (A08f/A09f).

`run-review.sh` is left as it is: it stamps `head=` from `git rev-parse HEAD` after its own
commit — a replace ref does not change what a ref resolves to, only what an object reads as
— and whatever the review or the audit read, the close re-derives every guarantee from git
with replace refs off (the subject loop, F1 over `JUDGED_HEAD..HEAD`, and
`audit_paths_touched` over `base...HEAD`), so a replace ref that hid a hook change from the
review's audit queuing is caught at the close as "changes the hook and no security audit
has run". The close is the gate; the variable lives there.

Round 3's review also noted K13c cannot show the `audit_paths_in_range` flag (the subject
loop refuses first); L2 now calls `audit_paths_in_range` directly.

## Round 5: the security audit's round-4 B06

Round 4's ruling claimed every call "resolves the objects `git push` sends"; that was false
while grafts were in force. Round 4's audit (B06; B08 the pre-existing stamps twin) showed a
cyclic `.git/info/grafts` giving an unreviewed `<slug>: backlog` commit — a `docs-notes.txt`
change plus the BACKLOG — a fabricated parent whose tree differs from it in the BACKLOG alone;
`GIT_NO_REPLACE_OBJECTS` does not turn grafts off.

**Ruling: the close reads history with replace refs and grafts both off.** `feature-close.sh`
exports `GIT_GRAFT_FILE=/dev/null` (`GRAFTS_OFF_FILE`) beside `GIT_NO_REPLACE_OBJECTS=1`, before
its first git call. With both, every parent and object the close reads is the one `git push`
sends. K16a/b hold it, each first asserting that plain git, grafts on, does see the allowed file
alone — so the scenario is live, not inert.

**Shallow clones are tolerated, not refused.** A cloud container's checkout can be shallow
(`.git/shallow`). A shallow boundary only removes parents, never invents one: a commit at the
boundary reads as parentless, fails `commit_changes_only`'s one-parent rule and is refused, and
`merge-base --is-ancestor` fails closed when the judged head is beyond it. Refusing every
shallow checkout would refuse ordinary cloud closes for no case it catches.

The BACKLOG's content is prose nobody executes; an unreviewed sentence there is the
filing itself, which is the point.

## Out of scope

The audit's classes, the other accepted subjects, and the sibling `consumer-record-guard`'s
files (`orchestration-start.sh`, `analysis/manifest.py`/`roots.py`, `LIFECYCLE.md` →
"Orchestration records") are untouched.
