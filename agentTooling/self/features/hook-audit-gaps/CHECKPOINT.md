# Checkpoint: hook-audit-gaps

status: committed        planned | tests-written | implementing | gating | committed
updated: 2026-11-16T03:30:00Z
gate: not run (the coordinator's); files run on this tree, all exit 0: allow-repo-commands.sh, hook-cloud-profile.sh, hook-orchestrator-role.sh, shared-rules.sh, hook-quote-oracle.sh, hook-escalation.sh, hook-wiring.sh, security-audit.sh, hook-brief-header.sh, policy-table.sh, audit-fixes.sh, orchestrator-role.sh; `python3 -B check-readme-index.py --root /home/user/agentTooling --ignore self/readme-index-ignore` clean

## Slices (round 7 rework: round 6's review, and its audit's B1 — the round-6 deny asks `bash -n`)
- [x] rounds 1–6, reviewed and audited (escalations/01-*.md … 06-audit-opus.md)
- [x] `bash -n` tried for execution on bash 5.2 (sixty canary texts, none ran) and against
      `eval` (112 lines, agreeing except the two that begin `shopt -s extglob`)
- [x] red rows first, run against round 6's hook: `BASH_REFUSED_GIT_DENY`,
      `BASH_PARSED_QUOTE_DENY` and `BASH_PARSED_PROMPT` in `allow-repo-commands.sh` (both
      profiles), H20 and the T table's round-7 block in `hook-cloud-profile.sh`, 10c and 10d
      in `hook-escalation.sh`
- [x] the fix on a scratch copy: `judged_texts`' last test is "no reading is judged, the line
      names git, and `bash_refuses(command)`"; `bash_refuses` and its five constants follow it
- [x] the twelve hook test files and the differential on the scratch copy (301,222 lines,
      three trees: 0 verdicts looser than round 5's hook; 3,244 looser than round 6's, every
      one on a line `bash -n` accepts; no legitimate row of the 3,964 changed)
- [x] the edits sent to the real tree: 1 Edit call on the hook (byte for byte the scratch
      copy), 2 on hooks/README.md
- [x] NOTES.md (rulings 70–75, the differential, over-denies, found-not-fixed),
      self/tests/README.md, self/BACKLOG.md (the "cannot tokenize" entry: leftover (a)
      rewritten, (d) added)
- [ ] the coordinator's gate, then the round 7 review and audit

## Learned
- `judged_texts` returns every reading of a line; its last line is where a line that cannot be read is turned into the unreadable git command (`unread()`), for a cap, a torn reading and a line no reading of which is judged and bash refuses.
- "Judged" is `command_words`' own test of a reading: `chain_tokens` lexes it AND `never_judged` (its `#`s removed) does not hold it back. shlex LEXES `echo $'\'' '` — pairing the quotes wrongly — so "does not lex" alone misses half the ANSI-C class.
- `bash -n` exits 0 with a warning on a heredoc that is never terminated: the refusal test is "exit 0 and no output at all", not the exit status.
- The real hook guards this session: between hooks/ Edit calls it is half-edited, and its judges fail open (no deny) on a NameError. One Edit per file, composed on a scratch copy.
- The tests load the hook from the tree they sit in, so a scratch copy of the tree runs the suites against a scratch hook.
- hook-orchestrator-role.sh and allow-repo-commands.sh take minutes: run them in the background.
- The differential's truth cache makes a rerun over the old corpora cheap; three trees run side by side in about 35 minutes once the new corpus's truth is cached (run it on one tree alone first).

## Resume
- Nothing is half-done. `bash self/tests/hook-cloud-profile.sh`, `bash self/tests/allow-repo-commands.sh`, `bash self/tests/hook-escalation.sh`, then `hook-orchestrator-role.sh` in the background; then the gate.
- What is left open is in NOTES.md → "Round 7" → "Found, not fixed (round 7)" and `self/BACKLOG.md` (the "cannot tokenize" entry's leftovers (a)–(d), and the scope entry).
- `hooks/README.md` → "The git shape" still says a line that does not tokenize is "refused whole"; the rule's paragraph says when (bash refuses it too). Fixing the sentence in place is a one-line edit for whoever next has `hooks/` approval.
