# Brief: follow-ups from the first use of three merged features (owner, 2026-11-17)

Found by using claim-run-gaps (#357), claim-verify-context (#355) and article-pictures-beside-text (#354) on
real material. Three small independent features. Nothing names project data.

## Feature 1 (`claim-gaps-name-noise`): the gaps list flags sentences that hold no name

Measured on one run over ten pages of an interview transcript, made before the feature, so every sentence
reads `unread`:
- `GET …/claim-runs/{id}/gaps` returned 194 `uncited_sentences`. 191 have reason `capitalised_name`, and
  most hold no name.
- `uncovered_names` held 17 entries, including "Thank", "Tell", "Let", "Yeah", "Don’t", "<City>—work", a
  school name with `"—that` attached, and the page's running head.
- The one real sentence was in the list but unfindable. It names a person as the owner of a shop, between
  two cited sentences.

Likely causes, to confirm in `claim_gaps.py` before fixing:
- A speaker label at line start ("AB: Tell me…") makes the first word of the speech read as mid-sentence.
- The pronoun "I".
- Sentence pieces cut at a line break or page break.
- Names not ended at a dash, a quote mark or glued punctuation.

Build:
- Recognise a speaker label at line start: a short run of capitals or a capitalised name, then a colon or
  semicolon. The pattern is a named constant. What follows the label is a sentence start.
- A capitalised run counts as a name only when two things hold:
  - It appears somewhere in the range in a position that cannot be a sentence start: not first in its
    sentence, not first after a speaker label, not first after an opening quote.
  - It is not a single word of a stop list: pronouns, interjections, months, days. The stop list is a
    named constant.
- Cut a name at the first character that is not one of these: a letter, an apostrophe, a full stop inside
  initials, or a hyphen between letters. An em or en dash always ends it.
- A running head (a line repeated at the top of most pages of the range):
  - is listed once in `uncovered_names`, marked repeated;
  - is never an uncited sentence.
- `uncited_sentences` gains nothing new, and `reason` keeps its values.

Acceptance:
- "AB: Tell me about it." / "CD: Yes. We were young then." with no candidate:
  - neither sentence is listed;
  - "Tell", "Yes" and "We" are not uncovered names.
- "CD: X, the owner, was known for importing records." between two cited sentences, where X is a roster
  first name: listed, reason `roster_name`.
- "I went to <City>—work was there" yields the name "<City>".
- A running head on every page: once in `uncovered_names`, marked repeated, and not in
  `uncited_sentences`.
- A fixture of at least 60 transcript sentences, 10 of them holding a real name and uncited: the list
  holds those 10 and at most 2 others.

## Feature 2 (`claim-verify-names`): verify still refuses names its context supplies

Measured by re-verifying a run of 89 candidates:
- Unsupported fell from 53 to 33.
- About 20 of the 33 give a bare name as the unsupported part:
  - the interviewee's own name 13 times, where the span says "I";
  - a teacher's name 6 times, where the span says "he" and the name is a few sentences up;
  - a surname once, where the text gives a first name and the roster the full name.
- The re-verify took 158 seconds in one blocking request.

Build:
- First find out what the call receives for a span deep in a chunk, far from the interview's heading. Log
  one prompt in a test; do not guess. Check whether it carries the heading, the expansion of the speaker
  labels, and the neighbourhood.
- Give every verify call the range's speaker map:
  - Each speaker label of the range, with the full name it stands for.
  - The full names come from the interview heading and the first full-name label (transcripts open with
    "Full Name: …" and abbreviate after).
  - The roster name each partial name was resolved to.
- State in the instructions that none of these is an unsupported part:
  - the speaker's name for "I", "me" or "my";
  - a person the neighbourhood identifies, for "he", "she" or "they";
  - the roster's full name for a first name the text gives.
- `ClaimCandidateOut` gains `unsupported_kind` (Rule 1; null when supported):
  - `name` when the unsupported part is nothing but a roster name or one of its aliases;
  - `detail` otherwise.
- The review shows `name` as "Name not in the excerpt", visually apart from `detail`, and the supported
  filter can separate the two.
- Re-verify runs as the extraction does:
  - the POST starts it and answers 202;
  - it works in batches of a named size and shows the run's progress;
  - the run is readable while it runs;
  - a second start while one runs is a 409.

Acceptance:
- A fixture transcript whose heading names the interviewee. Forty sentences later the span reads "I
  studied with him for a year", and the teacher is named three sentences before it.
  - A statement naming both is scripted supported.
  - The test asserts the prompt holds the speaker map and the sentence naming the teacher.
- The same statement with "in <City>" added, the city nowhere near: unsupported, part "in <City>", kind
  `detail`.
- A statement using a roster full name where the text has the first name: supported.
- A scripted answer whose part is exactly a roster name: kind `name`, shown as such.
- Re-verify of 100 fixture candidates answers 202 at once and reports progress, and the run reads normally
  meanwhile.

## Feature 3 (`article-lead-picture`): the article's first picture is still left out

Measured on one news article with seven photos of its own:
- The preview ticks six, with captions. The seventh is unticked, reason `outside`.
- All seven are the same markup: siblings in one container that also holds the paragraphs. Each is a
  `div` > `span` > `span` > `picture` > `img`. There is no `<article>` element and no `<figure>`.
- The unticked one is the first widget: after the `<h1>`, before the first paragraph.
- `og:image` is another rendition of that same picture: the same long identifier, a different size suffix
  (`…<id>/878/jpeg` against `…<id>=w700`). The exact address is not among the candidates, so the
  lead-image rule does not tick it either.

Build:
- In the picture-place rule of `page_media.py`, a picture that meets all of these is the article's:
  - it is in the article's own container;
  - it comes after the headline and before the first paragraph;
  - it has the article's column width.
- Say in NOTES what distinguishes it from a banner or advertisement in the same position. The size and
  decoration rules still apply.
- The lead-image match compares renditions, not exact addresses. Two addresses are the same picture when
  they share host and a path identifier of at least a named minimum length, and differ only in a size or
  format suffix or a query.
  - The rule and its constants are named, and the match is conservative.
  - Tests show two different pictures on one host not matching.
- A generic fixture copied in shape from the measured page joins `server/tests/fixtures/article_import/`.

Acceptance:
- The new fixture:
  - all seven pictures are ticked, the first with its caption;
  - the badges and the site logo are unticked.
- An `og:image` that is a different rendition of a picture in the page:
  - that picture is ticked and is the lead;
  - the og address is not fetched as a second copy.
- Two different pictures whose addresses differ by more than a size suffix are not matched.
- The existing fixtures `picture_above_headline`, `picture_floated` and `pictures_beside` pass unchanged.

## Order
The three are independent; any order works. Features 1 and 2 touch claim code that other in-flight features
touch, so the orchestrator settles who lands first. OWNER: none open.
