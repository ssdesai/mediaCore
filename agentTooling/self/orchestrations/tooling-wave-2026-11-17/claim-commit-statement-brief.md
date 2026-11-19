# Brief: a committed claim keeps its statement as well as its excerpt (owner, 2026-11-17)

Follows `claim-run-checks-brief.md` and its addendum. Owner's ruling, 2026-11-17: a commit stores both the
excerpt and the cleaned statement. Nothing here names project data.

## What happens today (read `server/app/crud/claim_commit.py`, `crud/facts.py`)

For each accepted candidate the commit writes one information item whose `text` is the verbatim slice of the
source at the candidate's span, and `facts.new_fact_for_item` makes a fact whose `text` is that same slice.
The candidate's `statement` (the sentence the reviewer read and accepted, with the speaker named and the
pronouns resolved) is written nowhere in the graph. In a transcript the stored wording is therefore "I studied
with him for a year", on a node, with nothing saying who "I" and "him" are. The statement also cannot be
edited in the review (`CandidatePatchIn` has no field for it).

## Feature 1 (`claim-commit-statement`): the fact takes the statement, the item the excerpt

Build:
- At commit, a candidate that makes a new fact (unmatched, native, or matched `contradicts`) gives the fact
  `text = candidate.statement`; the item's `text` stays the verbatim slice with its span, exactly as now.
  `facts.new_fact_for_item` gains an optional wording (default the item's text, so every other caller is
  unchanged).
- A candidate matched `same` joins the existing fact as now and never changes that fact's wording. Its own
  statement is kept on the item: `information_items` gains a nullable `statement` (migration; null for every
  existing row and every item not written by a commit), set by the commit for every item it writes.
  `InformationItemOut` and `InformationItemWithOwnerOut` gain `statement: str | None` (Rule 1).
- The statement is editable in the review: `CandidatePatchIn` gains `statement` (trimmed, non-blank, a cap
  named as a constant), allowed in the states where the span is; an edit clears `supported` and `match` as a
  span edit does (say in NOTES if a span edit does not, and follow it). The row shows the statement in an
  editable field with the excerpt beneath it.
- Wherever a fact is shown with its sources (node and edge detail, the "Already on" block, the source's item
  list), the fact's wording is the statement and each supporting item shows its excerpt as the quote, with
  the existing link to the place in the text. An item whose `statement` differs from its fact's wording shows
  it on hover or in the item's detail; say which in NOTES. Existing facts and items, whose two texts are
  equal, look as they do now.
- The already-present check (`claim_chunks.is_already_present`) keeps comparing spans and excerpts, never
  statements.
- Search and export that read `facts.text` or `information_items.text` are listed in NOTES with what each
  now returns; none is changed silently.
- The commit record (`recordText`) prints, per written fact, the statement and then the excerpt.

Acceptance:
- A fixture run with one accepted free claim, statement "A studied with B for a year", span text "I studied
  with him for a year": after commit the fact's text is the statement, the item's text is the span text, the
  item's `statement` is the statement, the span is attached.
- The same claim matched `same` to an existing fact worded "A was B's student": the existing fact's text is
  unchanged, the new item supports it, the item's `statement` is the candidate's.
- Matched `contradicts`: a new fact worded with the statement, disputing the matched one.
- A statement edited in the review is the one written; a blank one is refused with 422.
- Every item that existed before the migration reads `statement: null`, and every existing fact keeps its
  text (a test over the seeded data asserts no fact or item text changed).
- The node detail shows the statement as the fact and the excerpt as its quote.

## Feature 2 (`claim-multi-span`): a claim stated across separate sentences

Measured on fifteen hand-made reference lists: about one expected claim in five can only be assembled from
sentences that are not adjacent (a question and its one-word answer several lines on, a name given before an
aside and the verb after it, a fact running over a page break). Today such a candidate is dropped ("sentence
ids are not contiguous"); `claim-run-gaps` keeps it restorable with one covering span, which stores
everything in between as its quote. With Feature 1 the natural shape exists: one fact worded by the
statement, supported by one item per cited stretch.

Build:
- A candidate may hold several spans: `ClaimCandidateOut` gains `spans: [{ start_offset, end_offset, page,
  text }]` (Rule 1), the existing `start_offset` / `end_offset` / `page` / `text` staying as the first span
  for older readers. The validation that refused non-contiguous ids instead groups the cited ids into maximal
  contiguous stretches, one span each, up to a named cap (`CLAIM_SPANS_MAX`, suggest 4); past the cap the
  candidate is dropped and kept as `claim-run-gaps` says.
- Verify sees every span (with `claim-verify-context`'s neighbourhood for each).
- The review shows each span's excerpt in order, marks all of them in the source pane, and the span edit
  works on one span at a time, with add and remove.
- Commit writes one item per span, all supporting the one fact (new, or the matched one), each with its own
  span row and the candidate's statement. The already-present check passes only when every span is already
  present on the owner. `applied_item_id` stays the first item; the report counts every item.
- Extraction guidance gains a sentence, in the section that governs cutting, saying that a claim may cite
  separate stretches when the fact is stated across them, and should not cite the sentences in between.

Acceptance:
- A scripted answer citing sentences 4 and 9: one candidate with two spans, not dropped; verify receives
  both; commit writes two items on one fact worded by the statement.
- Sentences 4, 5 and 9: two spans (4-5 and 9).
- More stretches than the cap: dropped, listed under Gaps with its reason.
- Removing a span in the review leaves a one-span candidate that commits as one item.

## Order

Feature 1 first; Feature 2 needs it. Both touch the commit, so neither runs beside `claim-run-gaps` or
`claim-candidate-hygiene` without the orchestrator settling who lands first; `claim-run-gaps`' covering-span
Restore stays for candidates dropped past the cap.

OWNER: none open. (Answered 2026-11-17: store both.)
