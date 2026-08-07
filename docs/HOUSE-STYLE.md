# House style: what a page here has to do

## TLDR/BLUF

Every rule below is one testable statement with a permanent identifier. Cite the identifier in a
review comment the way a standard's rule is cited, so both sides point at the same sentence.

- **What it demands.** An opening that answers what this is, what it costs, and where to start, before
  it explains anything. Sentences that carry a fact, a number, a constraint or a link. Prose that
  never describes its own structure.
- **What it costs.** Length, in the places where length was doing nothing. The rules protect density
  explicitly, so applying them is not a licence to flatten precision into blandness.
- **Where it does not apply.** `standards/SECURE-DEVELOPMENT.md`, which is the model these rules were
  derived from and is not edited to satisfy them. Generated files. The `PD` section, which is the list
  of things an editor MUST NOT cut.
- **Where to start.** `PD` first, before touching anything. It names four sections that read exactly
  like the filler `B` orders deleted, and are load-bearing.

---

## How to read these rules

| Element | What it means |
|---|---|
| `OPEN-<n>` | The opening of a page |
| `HS-<n>` | House style, anywhere on a page |
| `PD-<n>` | Protected density. What an editor MUST NOT cut |
| `B-<n>` | A banned construction |
| **MUST**, **MUST NOT** | Absolute. Not meeting one is a defect, not a judgment call |
| **SHOULD** | Ignore it only for a stated reason you have weighed |

An identifier is a permanent name, never a position. A new rule takes the next free number in its
section and is appended. Reword a rule freely under the same identifier; change what it demands and
you allocate a new one.

**`PD` outranks every other section.** Where a `PD` rule and an `HS` rule disagree about the same
text, `PD` wins. The failure this ordering prevents is an editor satisfying a length rule by deleting
a measurement.

---

## OPEN: the opening

The model is `standards/SECURE-DEVELOPMENT.md`, whose opening went from 99 lines to 22 when two
orientation sections were deleted for restating the page rather than opening it.

| ID | Rule | Evidence |
|---|---|---|
| OPEN-1 | The first screen **MUST** answer, in this order: what this is, what it costs the reader, who it is not for, and where to start | The four answers, above the first explanatory section |
| OPEN-2 | A page with a summary section **MUST** spell its heading `## TLDR/BLUF` exactly | `tests/test_docs_do_not_drift.py` pins the string. A page **MAY** have no summary section at all |
| OPEN-3 | An opening **MUST NOT** describe the page's own structure, sections, or reading order | No "this page is organized as", no "first we cover" |
| OPEN-4 | An opening **MUST** state who the page is not for, where that set is non-empty, and **MUST** say it as a plain no | A sentence a reader can fail |
| OPEN-5 | An opening **SHOULD** link rather than summarise, where the target says it already | A link, not a paraphrase |
| OPEN-6 | A page longer than roughly 2,000 words **SHOULD** name its own starting point | One link, in the opening |

---

## HS: house style

| ID | Rule | Evidence |
|---|---|---|
| HS-1 | Every sentence **MUST** carry a fact, a number, a constraint, a link, or an instruction | Delete the sentence and something is lost |
| HS-2 | A section **MUST NOT** restate a fact the page has already stated | One statement, one place |
| HS-3 | A fact stated in two files **MUST** live in one and be linked from the other | One owner per fact |
| HS-4 | Prose **MUST NOT** explain why the document omits something | Say it or do not; the omission needs no defence |
| HS-5 | A count of a set **MUST NOT** appear in prose unless the same page enumerates the set | Counts rot silently |
| HS-6 | A claim about behaviour **SHOULD** name how it was established | "Measured on", "verified against" |
| HS-7 | Tabular content **MUST** be a table; a table whose rows are one clause each **SHOULD** be prose | Shape follows content |
| HS-8 | A destructive command's description **MUST** state what is lost and whether it is recoverable | The loss, named |
| HS-9 | A diagnostic message **MUST NOT** be phrasable as reassurance when the tool could not determine an answer | "Could not tell" reads as "could not tell" |
| HS-10 | A refusal **MUST** say what was refused, why, and the next command, and the command **MUST** be runnable as printed | Three slots, all filled |
| HS-11 | Prose **MUST** be ASCII: no em dash, no smart quotes, no section sign | `scripts/quality/check-ascii.ps1` |
| HS-12 | A normative rule document **MUST** carry a "how to read the rules" section, stable rule identifiers, and an evidence column | The three, present |
| HS-13 | A heading **MUST NOT** be renamed until the repository has been searched for its text | Standards cite headings by name, and only the link-adjacent form is gated |
| HS-14 | Lines **SHOULD** wrap near 100 characters | The wrap |
| HS-15 | A quantity **MUST** be the number where one exists, not a vague determiner | "139", not "nearly all" |
| HS-16 | A markdown link **MUST** sit on one line, text and target both, and that outranks HS-14 | `tests/test_a_links_text_never_wraps.py`. `jekyll-relative-links` matches a link with a pattern whose `.` excludes a newline, so a wrapped one is never rewritten and the published site serves the raw `.md` while github.com renders it correctly. 35 links were in this state on 2026-08-07 |

---

## PD: protected density, and what an editor MUST NOT cut

Read this before editing. Density is not a defect here. These rules exist because the same editing
pass that removes filler is the pass most likely to remove a measurement.

| ID | Rule |
|---|---|
| PD-1 | **MUST NOT** remove a measured number, a date, or a named source. A diff removing a digit outside a code fence needs a reason in the commit message |
| PD-2 | **MUST NOT** remove a "Limit:" statement, or any sentence saying where a control stops working |
| PD-3 | **MUST NOT** remove the mechanism sentence that makes a rule actionable, even where the rule survives without it |
| PD-4 | **MUST NOT** convert a trap, limit, or status table into prose to satisfy a length rule |
| PD-5 | **MUST NOT** remove a statement that a control is advisory, unwired, or unproven |
| PD-6 | **MUST NOT** remove a rule identifier, or renumber rules. Retire an identifier with a tombstone instead |
| PD-7 | **MUST NOT** rewrite an agentless passive into an active sentence in a normative rule. The requirement holds whoever performs it |

### PD-8: four sections that look like filler and are not

An editor applying `OPEN-3` or `B-6` to any of these introduces a defect. Each is named by path
because none of them looks load-bearing from the inside.

| Section | Why it stays |
|---|---|
| `standards/SECURE-DEVELOPMENT.md`, `## Retired rules` | The table is empty, and the empty table is the artifact. `tests/test_rule_ids_are_stable.py` raises if the heading is absent |
| `ASVS-ASSESSMENT.md`, `## Handing this to Claude Code` | The document's only Part 1 to Part 2 boundary marker |
| `standards/WHICH-STANDARDS-APPLY.md`, the selector sentinel comment | A test requires it to appear exactly once, and the interactive selector renders at it |
| `standards/STANDARDS-REFERENCE.md`, the line carrying the status-check date | A test requires the date. The sentence is filler by shape and required by contract |

---

## B: banned constructions

Each is drawn from prose measured in this repository, not from a general style guide.

| ID | Banned | Write instead |
|---|---|---|
| B-1 | A page instructing the reader how to read it | The content, in the order that serves it |
| B-2 | A sentence explaining why a fact is omitted | Nothing |
| B-3 | "It is worth noting", "It should be noted", "Importantly" | The note |
| B-4 | A sentence whose only work is transition | Nothing |
| B-5 | "provides the capability to", "in order to", "utilize", "leverage" | "can", "to", "use", "use" |
| B-6 | A sentence asserting its own significance | The fact that makes it significant |
| B-7 | "cleanly", "elegantly", "robustly", "carefully" describing this project's own work | The property, measured |
| B-8 | Three adjectives or three parallel clauses where one carries the meaning | The one |
| B-9 | "nearly every", "most", "a number of" for a countable set | The count |
| B-10 | A rhetorical question as a section opener | The answer |

---

## The standing edit protocol

1. Re-derive an edit's target by heading text or a quoted sentence, never by a line number from a plan
   or a review. Line numbers move under any edit to the same file.
2. Before renaming or deleting any heading under `docs/`, search the repository for its text. Standards
   cite each other by heading name, and only the link-adjacent form of that citation is gated.
3. A commit editing any file under `docs/standards/` regenerates that file's Word copy in the same
   commit, on pandoc 3.10, and runs the link, citation, selector and Word-copy tests.
4. Tests run from inside `tests/`: `python -m unittest discover -s . -q`. A run from the repository
   root finds nothing and exits without testing anything.
5. Run `scripts/coord/overlap.ps1` before starting a chunk of work. A clean merge proves lines did not
   collide, not that intentions did not.
