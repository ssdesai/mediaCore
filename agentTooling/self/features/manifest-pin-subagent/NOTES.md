# NOTES: manifest-pin-subagent

## Rulings

- **Agent-id shape is `^[0-9a-f]{17}$` (`manifest.AGENT_ID_RE`).** Derived, not guessed:
  every `agent-<id>.jsonl` on this machine (342) and every id pinned in any manifest under
  `~/dev` is 17 lowercase hex, all starting `a`. The leading `a` is not required, so the
  existing fixtures (`d1111111111111111` in feature-lifecycle.sh) stay valid and a
  change in that one character does not refuse a real id. A different length would be a
  new format and is refused — one constant to change.
- **`agent-<id>` is refused, not stripped.** The refusal names the bare id to pin.
  Silently rewriting input is the kind of guess the fence exists to avoid; the message
  makes the fix one paste.
- **Refusals are plain exit 1 with `refusing:` on stderr**, the file untouched — the
  shape `pin-session` uses. No reserved code: nothing reads them.
- **A pin another feature already holds is left to the capture.** `manifest.py` reads no
  other manifest (it imports only `roots` and `routing`), and the capture already judges
  double claims with more reach than this command could have: it warns when two
  manifests in a corpus pin one id, and refuses a delegate the claims ledger already
  holds for another `(repo, slug)` across every repo on the machine.
- **No transcript-existence check.** A pin matching nothing is warned about by id at
  every capture (subagent-capture.sh 4); a coordinator may pin before the transcript is
  flushed.
- **`parse_manifest` fold: no change to session-claims.sh was needed.** It patches
  `cp.parse_manifest` as a module attribute; `from routing import parse_manifest` binds
  that same global name in `capture_planning`, and every call site resolves it at call
  time, so the counter still counts (assertion 9 green). The `is` identity holds on an
  unpatched import, asserted by manifest-pin-subagent.sh P9. The import-line comment
  says why it must stay a module-global import.
- **The pin advice names the command everywhere it was printed.** `--list-subagents`'
  three advice lines (`PIN_SUBAGENT_COMMAND`, keeping the "Pin each in" wording
  claims-ledger.sh A2/A4 read) and `feature-capture.sh`'s warning, which prints the
  worktree copy's absolute path, `--self` when set, the slug and the id — ready to run,
  like `feature-close.sh`'s `pin-session` refusal. It still says `"subagents"`, which
  feature-lifecycle.sh C1i reads.
- **The end-to-end assertion lives in feature-lifecycle.sh C2**, which already had the
  warned-about delegate (C1's `AGENT_D`); pinning it before C2's capture proves
  `feature-capture.sh` claims it and pushes the pin, without a new scaffold.
- **ORCHESTRATION.md "Coordinator shapes"** adds one caveat beyond the backlog's text: a
  wave coordinator is the router, so it runs each feature's review and close by the
  worktree copy's absolute path rather than `cd`-ing in — `routing.unpinned_builder`
  counts a transcript `cwd` under the worktree as building, and the close would refuse.
- **TEMPLATE.md needs no version bump**: it is a generated stub, not one of the four
  versioned seeded scripts `template-versions.sh` checks. Its `subagents` bullet was
  edited in place, and this feature's own manifest copy of that bullet to match.
- **CONVENTIONS.md unchanged.** Its approved-silently list names `manifest.py get` only;
  a pin is a write and prompts, as `pin-session` does.

## Open questions

- None.

## Resume / state

- `bash self/tests/manifest-pin-subagent.sh`; `bash self/tests/feature-lifecycle.sh`
  (C1i2, C2f–C2i); `self/gate.sh`, then read `self/gate-report.txt`.
