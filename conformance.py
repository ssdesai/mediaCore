#!/usr/bin/env python3
"""The brief-conformance helper (self/features/brief-conformance-checks/, rulings R2-R6, R13).

One parser for the three report shapes the owner's-brief checks read, so the runner, the
close and pr.sh agree on what a table row or a deviations section is. EXECUTED, never
imported: run-review.sh, feature-close.sh and templates/plans/pr.sh (self/pr.sh) call it,
and it is an audit path (plan-runner-roots.sh -> AUDIT_TOOLING_PATHS) because the close
refuses on what it prints. Pure standard library; reads files, writes stdout.

Subcommands (stdout; problems and diagnostics on stderr):

  items <owner-brief>
      One `<id><TAB><title>` line per owner-brief item (R3, R17): every markdown heading
      whose text starts with a number and `.` or `)` is item <number>; with no such heading,
      every top-level (column 0) numbered list item is, titled by its opening bold span or
      else its line, emphasis markers removed; a brief with neither is one item, id `1`.
      Headings win when both exist. Nothing inside a code fence is an item.
  table <report> <heading>
      The table under `## <heading>` as `<id><TAB><result><TAB><evidence>` lines, result
      normalised to `done`, `partial`, `not done`, or `unknown:<raw>` for anything else (R4).
  check-close --owner-brief <f> --review <f> --conformance <f>
      One problem per line, naming the row or the disagreement (R11); nothing when the
      review's acceptance table, its deviations section and the conformance report agree
      that every owner item is done.
  pr-body <report> [--conformance <f>]
      The PR body (R13): `## Acceptance` first, `## Deviations from the brief` second (the
      conformance report's out-of-scope files appended, R12), then the rest of the report in
      its order. A report with no acceptance section is passed through unchanged.
  deviations <body> [--owner-brief-present]
      `none` or `non-empty` (R5, R17): a missing section reads as non-empty, with the reason
      on stderr, only when told the feature has an owner brief (`--owner-brief-present`);
      otherwise it reads as `none` (the reason still on stderr), so a report from a feature
      with no owner brief that has no such section is not marked.
  summary --owner-brief <f> --conformance <f>
      One line counting the conformance report's verdicts and its out-of-scope files.

Exit codes: 0 success (check-close: no problem; table: a table was found); 1 check-close
found a problem; 2 usage, or a file that cannot be read; 3 table: the section or its table
is missing.
"""
import re
import sys

# Exit codes
EXIT_OK = 0
EXIT_PROBLEMS = 1
EXIT_USAGE = 2
EXIT_NO_TABLE = 3

# Item enumeration (R3)
ITEM_HEADING_RE = re.compile(r"^#{1,6}\s+(\d+)[.)]\s*(.*?)\s*#*\s*$")
ITEM_LIST_RE = re.compile(r"^(\d+)[.)]\s+(.*?)\s*$")  # column 0 only: nested items are not owner items
BOLD_OPEN_RE = re.compile(r"^(\*\*|__)(.+?)\1")
EMPHASIS_RE = re.compile(r"\*\*|__")
FALLBACK_ITEM_ID = "1"
FALLBACK_ITEM_TITLE = "the owner's request"
FENCE_RE = re.compile(r"^\s*(```|~~~)")

# Report shapes (R4-R6)
ACCEPTANCE_HEADING = "Acceptance"
DEVIATIONS_HEADING = "Deviations from the brief"
CONFORMANCE_HEADING = "Conformance"
OUT_OF_SCOPE_HEADING = "Out of scope"
SECTION_RE = re.compile(r"^##\s+(.*?)\s*#*\s*$")
HEADER_FIRST_CELL = "item"
ROW_ID_RE = re.compile(r"^`?(\d+)(?=$|[\s.:)`—–-])")
SEPARATOR_CELL_RE = re.compile(r"^:?-+:?$")
RESULT_DONE = "done"
RESULT_PARTIAL = "partial"
RESULT_NOT_DONE = "not done"
RESULT_UNKNOWN_PREFIX = "unknown:"
RESULT_NOISE = "`*_. "
NONE_WORD = "none"
NONE_NOISE = "`*_. \t"
DEVIATIONS_NONE = "none"
DEVIATIONS_NON_EMPTY = "non-empty"
OWNER_BRIEF_PRESENT_FLAG = "--owner-brief-present"
DEVIATIONS_MISSING_NOTE = "the review report has no '## Deviations from the brief' section"
DEVIATIONS_MISSING_BODY = "Section missing from the review report, so it is read as non-empty."
PREAMBLE_HEADING = "Review verdict"
OUT_OF_SCOPE_LEAD = "Files the conformance check could not tie to an owner item:"
NO_ITEM_ROW = "no row"
PIPE_ESCAPE = "\\|"
PIPE_PLACEHOLDER = "\x00"


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError) as error:
        print("conformance.py: cannot read %s: %s" % (path, error), file=sys.stderr)
        sys.exit(EXIT_USAGE)


def parse_items(text):
    """[(id, title)] in file order; one fallback item for a brief with none (R3)."""
    headings, listed, fenced = [], [], False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        match = ITEM_HEADING_RE.match(line)
        if match:
            headings.append((match.group(1), match.group(2)))
            continue
        match = ITEM_LIST_RE.match(line)
        if match:
            listed.append((match.group(1), list_item_title(match.group(2))))
    # Numbered headings win; a top-level numbered list counts only when there is no such heading
    return headings or listed or [(FALLBACK_ITEM_ID, FALLBACK_ITEM_TITLE)]


def list_item_title(text):
    """A list item's title: the opening bold span when it opens with one, else the whole
    line, with `**` / `__` emphasis markers removed."""
    bold = BOLD_OPEN_RE.match(text)
    return (bold.group(2) if bold else EMPHASIS_RE.sub("", text)).strip()


def split_sections(text):
    """[(heading-or-None, [lines])]: the preamble first, then each `## ` section. A heading
    inside a code fence is text, not a section."""
    sections, current, fenced = [], [None, []], False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            fenced = not fenced
        match = None if fenced else SECTION_RE.match(line)
        if match:
            sections.append(current)
            current = [match.group(1), [line]]
        else:
            current[1].append(line)
    sections.append(current)
    return sections


def find_section(sections, heading):
    """The first section whose heading equals <heading>, case and spacing ignored."""
    wanted = " ".join(heading.lower().split())
    for section in sections:
        if section[0] is not None and " ".join(section[0].lower().split()) == wanted:
            return section
    return None


def normalise_result(raw):
    value = " ".join(raw.strip(RESULT_NOISE).lower().split())
    if value in (RESULT_DONE, RESULT_PARTIAL, RESULT_NOT_DONE):
        return value
    return RESULT_UNKNOWN_PREFIX + raw.strip()


def split_cells(line):
    inner = line.strip()
    if inner.startswith("|"):
        inner = inner[1:]
    if inner.endswith("|") and not inner.endswith(PIPE_ESCAPE):
        inner = inner[:-1]
    inner = inner.replace(PIPE_ESCAPE, PIPE_PLACEHOLDER)
    return [cell.replace(PIPE_PLACEHOLDER, "|").strip() for cell in inner.split("|")]


def row_id(cell):
    """The id a row's first cell names: its leading number, else the whole cell (a review's
    own acceptance line)."""
    match = ROW_ID_RE.match(cell.strip())
    return match.group(1) if match else cell.strip().strip("`")


def parse_table(section):
    """[(id, result, evidence)] for the table rows of a section, or None when it has no table
    line at all. The first cell is the item and the last the result; whatever lies between is
    the evidence, so a `|` inside it cannot move the result."""
    rows, seen_table = [], False
    for line in section[1][1:]:
        if not line.lstrip().startswith("|"):
            continue
        seen_table = True
        cells = split_cells(line)
        if all(SEPARATOR_CELL_RE.match(cell) for cell in cells if cell) and any(cells):
            continue
        if cells[0].strip("` ").lower() == HEADER_FIRST_CELL:
            continue
        if len(cells) < 2:
            rows.append((row_id(cells[0]), normalise_result(""), ""))
            continue
        rows.append((row_id(cells[0]), normalise_result(cells[-1]), " | ".join(cells[1:-1])))
    return rows if seen_table else None


def section_rows(text, heading):
    section = find_section(split_sections(text), heading)
    return None if section is None else parse_table(section)


def result_by_id(rows):
    """id -> result. A duplicated id keeps its worst result, so a second row cannot launder
    a first one that was not done."""
    out = {}
    for item_id, result, _ in rows:
        if item_id not in out or result != RESULT_DONE:
            out[item_id] = result
    return out


def deviations_state(text):
    """DEVIATIONS_NONE, DEVIATIONS_NON_EMPTY, or None for a missing section (R5)."""
    section = find_section(split_sections(text), DEVIATIONS_HEADING)
    if section is None:
        return None
    body = "\n".join(section[1][1:]).strip()
    return DEVIATIONS_NONE if body.strip(NONE_NOISE).lower() == NONE_WORD else DEVIATIONS_NON_EMPTY


def out_of_scope(text):
    """The `- <path> — <why>` lines of the conformance report's out-of-scope section."""
    section = find_section(split_sections(text), OUT_OF_SCOPE_HEADING)
    if section is None:
        return []
    lines = [line.rstrip() for line in section[1][1:] if line.strip()]
    if len(lines) == 1 and lines[0].strip("-* ").strip(NONE_NOISE).lower() == NONE_WORD:
        return []
    return lines


def render_acceptance(section):
    return "\n".join(section[1]).rstrip()


def cmd_items(args):
    if len(args) != 1:
        return usage()
    for item_id, title in parse_items(read(args[0])):
        print("%s\t%s" % (item_id, title))
    return EXIT_OK


def cmd_table(args):
    if len(args) != 2:
        return usage()
    rows = section_rows(read(args[0]), args[1])
    if rows is None:
        print("conformance.py: no table under '## %s' in %s" % (args[1], args[0]), file=sys.stderr)
        return EXIT_NO_TABLE
    for item_id, result, evidence in rows:
        print("%s\t%s\t%s" % (item_id, result, evidence))
    return EXIT_OK


def option(args, name):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else None


def cmd_check_close(args):
    brief, review, conformance = (option(args, "--owner-brief"), option(args, "--review"),
                                  option(args, "--conformance"))
    if not (brief and review and conformance):
        return usage()
    items = parse_items(read(brief))
    review_text, conformance_text = read(review), read(conformance)
    problems = []
    review_rows = section_rows(review_text, ACCEPTANCE_HEADING)
    if not review_rows:
        problems.append("the review report has no '## %s' table" % ACCEPTANCE_HEADING)
        review_by_id = {}
    else:
        review_by_id = result_by_id(review_rows)
        for item_id, result, evidence in review_rows:
            if result != RESULT_DONE:
                problems.append("acceptance row '%s' is '%s', not done%s"
                                % (item_id, result, (": " + evidence) if evidence else ""))
        for item_id, title in items:
            if item_id not in review_by_id:
                problems.append("owner item %s (%s) has no row in the review's '## %s' table"
                                % (item_id, title, ACCEPTANCE_HEADING))
    if deviations_state(review_text) is None:
        problems.append(DEVIATIONS_MISSING_NOTE)
    conformance_rows = section_rows(conformance_text, CONFORMANCE_HEADING)
    if not conformance_rows:
        problems.append("the conformance report has no '## %s' table" % CONFORMANCE_HEADING)
        return finish(problems)
    conformance_by_id = result_by_id(conformance_rows)
    for item_id, title in items:
        said = conformance_by_id.get(item_id, NO_ITEM_ROW)
        if said != RESULT_DONE:
            problems.append("owner item %s (%s): review says %s, conformance says %s"
                            % (item_id, title, review_by_id.get(item_id, NO_ITEM_ROW), said))
    return finish(problems)


def finish(problems):
    for problem in problems:
        print(problem)
    return EXIT_PROBLEMS if problems else EXIT_OK


def compose_body(report_text, conformance_text):
    sections = split_sections(report_text)
    acceptance = find_section(sections, ACCEPTANCE_HEADING)
    if acceptance is None:
        return report_text
    deviations = find_section(sections, DEVIATIONS_HEADING)
    scoped = out_of_scope(conformance_text) if conformance_text else []
    if deviations is None:
        deviation_text = DEVIATIONS_MISSING_BODY
    else:
        deviation_text = "\n".join(deviations[1][1:]).strip()
    if scoped:
        listing = "\n".join(scoped)
        if deviations_state(report_text) == DEVIATIONS_NONE:
            deviation_text = "%s\n\n%s" % (OUT_OF_SCOPE_LEAD, listing)
        else:
            deviation_text = "%s\n\n%s\n\n%s" % (deviation_text, OUT_OF_SCOPE_LEAD, listing)
    rest = []
    for section in sections:
        if section is acceptance or section is deviations:
            continue
        text = "\n".join(section[1]).rstrip()
        # The text before the report's first heading (its verdict line) would read as part of
        # the deviations section it now follows; a heading of its own keeps it apart
        if section[0] is None and text.strip():
            text = "## %s\n\n%s" % (PREAMBLE_HEADING, text.strip())
        rest.append(text)
    rest_text = "\n\n".join(part for part in rest if part.strip())
    body = "%s\n\n## %s\n\n%s" % (render_acceptance(acceptance), DEVIATIONS_HEADING, deviation_text)
    if rest_text:
        body += "\n\n" + rest_text
    return body + "\n"


def cmd_pr_body(args):
    if not args:
        return usage()
    conformance = option(args, "--conformance")
    sys.stdout.write(compose_body(read(args[0]), read(conformance) if conformance else ""))
    return EXIT_OK


def cmd_deviations(args):
    present = OWNER_BRIEF_PRESENT_FLAG in args
    rest = [arg for arg in args if arg != OWNER_BRIEF_PRESENT_FLAG]
    if len(rest) != 1:
        return usage()
    state = deviations_state(read(rest[0]))
    if state is None:
        print(DEVIATIONS_MISSING_NOTE.replace("the review report", "the report"), file=sys.stderr)
        state = DEVIATIONS_NON_EMPTY if present else DEVIATIONS_NONE
    print(state)
    return EXIT_OK


def cmd_summary(args):
    brief, conformance = option(args, "--owner-brief"), option(args, "--conformance")
    if not (brief and conformance):
        return usage()
    text = read(conformance)
    rows = section_rows(text, CONFORMANCE_HEADING)
    if not rows:
        print("conformance: the report has no '## %s' table" % CONFORMANCE_HEADING)
        return EXIT_OK
    by_id = result_by_id(rows)
    counts = {RESULT_DONE: 0, RESULT_PARTIAL: 0, RESULT_NOT_DONE: 0}
    for item_id, _ in parse_items(read(brief)):
        said = by_id.get(item_id, RESULT_NOT_DONE)
        counts[said if said in counts else RESULT_NOT_DONE] += 1
    print("conformance: %d item(s) - %d done, %d partial, %d not done; %d file(s) out of scope"
          % (sum(counts.values()), counts[RESULT_DONE], counts[RESULT_PARTIAL],
             counts[RESULT_NOT_DONE], len(out_of_scope(text))))
    return EXIT_OK


COMMANDS = {"items": cmd_items, "table": cmd_table, "check-close": cmd_check_close,
            "pr-body": cmd_pr_body, "deviations": cmd_deviations, "summary": cmd_summary}


def usage():
    print(__doc__.split("Exit codes:")[0].strip().splitlines()[0] + "\nsubcommands: "
          + ", ".join(COMMANDS), file=sys.stderr)
    return EXIT_USAGE


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        return usage()
    return COMMANDS[argv[1]](argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
