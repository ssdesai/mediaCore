# Queued claim features (owner brief "a claim run that checks itself" + addendum, 2026-11-17)

Start both when claim-verify-context has merged. Shared rules: same as the claim-verify-context child brief
(ClaimModel + usage + scripted answers; README Rules 1/2 + test-spec; no plans/BACKLOG.md edits; invented
fixtures only; nothing writes candidates to the graph; no migration rewrites committed rows; never wait on a
question; merge origin/main (normal merge) and re-run the gate before close if main moved; never merge PR;
known flaky public-read test: re-run start once).

## Feature 2 (`claim-completeness-pass`): a second reading for what was skipped

Build:
- After a chunk's extraction, a second call receives the chunk's sentences and the candidates already drafted
  from it (statement and sentence ids) and is asked only for stated facts that no candidate covers, with the
  same output shape as extraction. Its instructions name what matters most for this graph and must not be
  skipped: a person's teachers and students, schools and institutions attended or worked at, bands and their
  named members, instruments, family ties stated outright, places lived, dated events. Its guidance is a new
  guidance section (`completeness_pass`, with a default and a cap, in the registry of `claim-prompt-guidance`).
- ADDENDUM 1: the second call answers for every uncited sentence. Measured: a one-sentence fact ("X, the
  owner, was known for ...") was skipped although sentences on both sides were cited; an open "what did we
  miss" question is the same reading that missed it. The code computes the chunk's uncited sentence ids (in
  the chunk's core, not its overlap) and lists them in the call; the answer must hold, for every listed id,
  either a candidate citing it or an entry in a `nothing_stated` list. An id in neither is asked once more on
  its own with its neighbourhood, and what is still unanswered is stored. The `nothing_stated` ids are stored
  too, so the review can tell "read and judged empty" from "never answered" (claim-run-gaps'
  `uncited_sentences[].answered`: unread / judged_empty / unanswered reads these).
- Its candidates go through the same validation, owner resolution, duplicate check and verify as any other,
  and carry `pass_index = 2` (`ClaimCandidateOut` gains `pass_index: int`, 1 for the first pass; Rule 1).
  The review can filter by it and shows a count "added by the second reading".
- OWNER (answered): on by default for every run, with a tick on the start dialog to turn it off.
  `ClaimRunStartIn` gains `second_pass: bool = True`.
- A "run it on an existing run" action is out of scope.

Acceptance:
- A fixture chunk with five stated relationships where the scripted first pass returns three: the scripted
  second pass returns the other two, with `pass_index` 2, through verify; a second-pass candidate repeating
  a first-pass claim is removed by the duplicate check with the existing note.
- With `second_pass: false` no second call is made (the script model records none).
- Usage of both passes is in the run's `usage`.
- (addendum) every listed uncited id ends cited, in `nothing_stated`, or stored unanswered after one
  single-sentence retry.

## Feature 4 (`claim-candidate-hygiene`): fewer duplicates, misfiled and malformed candidates

Build:
- Native only when stated. Extraction instructions and `resolve_claim_target` treat a claim as native to an
  edge type or role only when the statement asserts that relationship or role; a statement that merely
  involves both ends becomes a free claim on the edge. Add the rule to the `claim_kind` guidance default, and
  a validation step: a native candidate whose statement, by the verify call of feature 1 when present, does
  not assert the native label is demoted to free with a note (`native_demoted`).
- Duplicates across owners within a run: the duplicate check also compares a candidate with earlier
  candidates of the run that cite the same sentences on a different owner (node and edge of the same person);
  the later one is kept only when its statement adds a fact the earlier lacks, else removed with the existing
  duplicate note naming the kept one. (Removed duplicates are stored `dropped` per claim-run-gaps addendum 3.)
- New names cleaned and folded: square brackets removed (bracketed text kept: "First Last[Surname]" ->
  "First Last Surname"), leading honorifics dropped and offered as an alias (list a named constant), folded
  against the run's other new names with `fold_name` so one person is one new node.
- `new_node_type` filled for every new node (require it; fall back to the project's default person type with
  a note).
- `quote_matched`: find why it is null on every candidate of a real run, fix it, test over a real-shaped answer.

Acceptance:
- "A brought B a guitar from abroad" between two people joined by a Family edge: a free claim on the edge,
  not native Family.
- One sentence "I studied with C" yielding a node claim and an edge claim with the same content: one
  survives, with the duplicate note.
- New names "Dr First Last" and "First Last": one new node "First Last" with alias offer "Dr First Last".
  "First Middle[Last]" and "First Middle Last": one new node "First Middle Last".
- A real-shaped extraction answer with a quote found in its cited sentences stores `quote_matched` true.
