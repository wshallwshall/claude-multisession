# House style: what a page here has to do

## TLDR/BLUF

**What this is.** Each rule is one testable statement with a permanent identifier, cited in a
review comment. They demand sentences that each carry a fact, a number, a constraint or a link, and
prose that never describes its own structure. No rule demands a summary section.

**Why you should care.** Applying them costs length only where length was doing nothing. Not for
you on generated files, on `PD` itself, or on `SECURE-DEVELOPMENT.md`, which left with
[the standards](https://github.com/wshallwshall/secure-development-standards) and answers their
house style now.

**How to use it.** Read `PD` first, before touching anything: it is the list of things an editor MUST
NOT cut. The one rule that named specific sections, `PD-8`, is a tombstone -- all four went with the
standards.

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

An identifier is a permanent name, never a position. Reword a rule freely under the same identifier;
change what it demands and you allocate a new one.

**`PD` outranks every other section.** Where a `PD` rule and an `HS` rule disagree about the same
text, `PD` wins. The failure this ordering prevents is an editor satisfying a length rule by deleting
a measurement.

### The numbering is shared with another repository, and this page is not the whole of it

**The next free number is the one above the highest number ISSUED IN EITHER SHEET, never the lowest
gap here.**
[secure-development-standards](https://github.com/wshallwshall/secure-development-standards) kept
counting after the split, so the numbers past each section are occupied, not vacant.

| Series | Issued here | Issued there | **Next free** |
|---|---|---|---|
| `B-<n>` | B-1 to B-10 | B-11 to B-18 | **B-19** |
| `HS-<n>` | HS-1 to HS-16, HS-20 to HS-23 | HS-17 spent on a superseded branch, HS-18 to HS-21 | **HS-24** |
| `PD-<n>` | PD-1 to PD-8 | PD-9 to PD-13 | **PD-14** |
| `OPEN-<n>` | OPEN-1 to OPEN-8 | none | **OPEN-9** |

Read from that repository's `origin/main`, not a local clone: it runs concurrent sessions and a
clone goes stale in the time one rule takes to write.

Checked there on 2026-08-16 at commit `d393aad`, correcting a table that had understated `PD` and
`B`: `PD-9` through `PD-13` and `B-18` were already issued there, not only `PD-9` and `B-17`. Its
one `OPEN` mention cites this page's range, as `OPEN-1 to OPEN-6`.

**Neither sheet can see the other move, and both have been wrong about it.** That page says this
one issues `OPEN-1 to OPEN-6`, true until `OPEN-7` landed. No check on either side could catch it,
so `HS-13` and the cross-repository anchor ban exist, and the table above carries a date and a
commit.

---

## OPEN: the opening

The model is `standards/SECURE-DEVELOPMENT.md`, whose opening went from 99 lines to 22 when two
orientation sections were deleted for restating the page rather than opening it.

| ID | Rule | Evidence |
|---|---|---|
| OPEN-3 | An opening **MUST NOT** describe the page's own structure, sections, or reading order | No "this page is organized as", no "first we cover" |
| OPEN-5 | An opening **SHOULD** link rather than summarise, where the target says it already | A link, not a paraphrase |
| OPEN-6 | A page longer than roughly 2,000 words **SHOULD** name its own starting point | One link, near the top |
| OPEN-8 | A page published in its author's own words is exempt from the prose ratchets and from the extensionless half of the source-link scan, and **MUST** be named in `AUTHORED_VERBATIM` in `tests/_ccxtest.py`. It stays bound by every rule that does not require rewriting the author: ASCII, `HS-16`, and every link resolving | One tuple, one entry. `tests/test_docs_do_not_drift.py` fails when it names a file this page does not |

### OPEN-8 names one file, and that is the whole of the exemption

`docs/KORUS.md` is the only page under it: a document its author asked to publish unedited. Four
gates were red against it before this rule existed -- `OPEN-2` and `OPEN-7`, both since retired,
the source-link scan, and `HS-20` at 94 paragraphs against a baseline of 88.

**The exemption is a tuple of exact paths, never a pattern.** `AUTHORED_VERBATIM` in
`tests/_ccxtest.py` is its only definition, and three tests in two files read it rather than
repeating the filename. Adding a second page is a diff someone approves, which is the point.

**It is an exclusion, not a raised baseline.** Moving `BASELINE_FAT_PARAGRAPHS` from 88 to 94 would
also have gone green, and would have handed every other page six paragraphs of new headroom. The
ratchet still measures what it measured before.

An exempt page may write `/WORKTREES` without `.html`, but only where `WORKTREES.md` is a page the
site serves, so a mistyped target still fails. That form is not broken: the host resolves it by
clean-URL fallback, measured on 2026-08-12 against `/WORKTREES` and `/USAGE-AWARENESS`.

What OPEN-8 does not touch: the ASCII gate, `HS-16`, every link resolving, and the site building.
An exempt page is still one a reader has to be able to load.

### OPEN-1, OPEN-2, OPEN-4 and OPEN-7: retired 2026-08-27, and no rule replaces them

Retired on the owner's instruction. `PD-6` keeps the four identifiers; none is reissued.

Between them they required an opening summary on every rendered page. `OPEN-2` demanded the heading
`## TLDR/BLUF`, spelled exactly that way, and `tests/test_docs_do_not_drift.py` gated its presence.

`OPEN-1` and `OPEN-7` demanded three answers inside that section -- what this is, why the reader
should care, and how to use it -- in that order, each its own paragraph.

`OPEN-4` demanded a plain statement of who the page is not for, in the `Why you should care` slot.

**The presence gate is deleted. The spelling ban is not.** `tests/test_docs_do_not_drift.py` still
refuses `## In short` and `**TL;DR --**`, the two spellings the set replaced.

That ban holds a page that HAS a summary section to one spelling. It requires no page to have one.

Pages carrying a summary section keep it. Retiring a rule does not delete what was written under it.

### What the four demanded before they were retired, so an old citation resolves

`OPEN-1` first required four answers -- what this is, *what it costs the reader*, who it is not for,
and where to start. It was cut to three on 2026-08-10, and cost moved into `Why you should care`.

`OPEN-2` ended with "A page **MAY** have no summary section at all" until that same day. On
2026-08-10, 15 of the 18 rendered pages carried no summary section, so it bound almost nothing.

`OPEN-7` required the three answers **verbatim and labelled**: `**What this is.**`, `**Why you
should care.**`, `**How to use it.**`, matched by exact substring. A reworded or unbolded label read
as absent, on purpose.

2026-08-16 relaxed it to the three answers in the author's own words. The substring gate outlived
the rule by one day, and for that day this page described a control it no longer had.

`OPEN-4` was reworded once under its own identifier without changing what it demanded: the
not-for-you sentence stayed required, and was told which slot to sit in.

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
| HS-20 | A paragraph **MUST NOT** exceed 300 characters. Rewrite it shorter; do **not** satisfy this by splitting one paragraph into two | A hard cap in `tests/test_prose_rules_hold.py` since 2026-08-16, when the last of the debt cleared. It shipped as a ratchet because 463 paragraphs were over the limit on 2026-08-10; the baseline is now 0, so the next one over fails the run |
| HS-16 | A markdown link **MUST** sit on one line, text and target both, and that outranks HS-14 | `tests/test_a_links_text_never_wraps.py`. `jekyll-relative-links` matches a link with a pattern whose `.` excludes a newline, so a wrapped one is never rewritten and the published site serves the raw `.md` while github.com renders it correctly. 35 links were in this state on 2026-08-07 |
| HS-22 | A heading or title **MUST** use sentence case: the first word, the first word after a colon, and proper nouns are capitalized, nothing else. **MUST NOT** end in a period | [Google's developer documentation style guide](https://developers.google.com/style/headings). No gate; checked by eye |
| HS-23 | A page a reader ARRIVES on **MUST** route rather than explain. It **MUST NOT** carry the install procedure, the requirements table or a script inventory, and it **MUST** name the first command's page in its opening | `tests/test_the_landing_page_stays_a_front_door.py`. The landing page reached 3,143 words before this rule, with the first install command 68% of the way down it |

### HS-21: retired 2026-08-16, and the identifier is kept rather than reissued

It required every `docs/FRAMEWORK-*.md` page to answer nine fixed questions in one declared order,
gated by `tests/test_a_series_answers_one_set_of_questions.py`. The premise was that a series is
worth more than its pages only if a reader can compare across them.

That premise needs at least two comparable pages. The BMAD page moved to a shorter, reader-directed
shape -- what it is, how it compares to Ultracode, whether it helps, a short how-to -- leaving the
series at one member.

The test's own guard said what to do about that: "if the series is genuinely gone, delete this file
rather than leaving it to certify an empty set." Deleted, per its own instruction.
`FRAMEWORK-spec-kit.md` keeps its nine-section shape; nothing requires a second page to match it
now.

### HS-23: what the landing page stopped carrying, and why a rule was needed

Nothing was wrong with any individual sentence on it. The defect was accretion: the install
procedure, the requirements table, the vendor-surface limits and a 40-row script inventory each
arrived on the landing page because it was the page everyone read, and each one was correct.

**The reader pays for that in ordering, not in accuracy.** A developer arriving to find out whether
to try this met the caveats before the commands, and the commands 68% of the way down a
3,143-word page.

The four owners it split into: [Quickstart](QUICKSTART.md) for the procedure,
[Limits and requirements](LIMITS.md) for what it needs and where it stops,
[Every script](SCRIPTS.md) for the inventory, and the landing page for routing.

**The rule is a cap rather than a prohibition on detail.** Detail is not the defect and `PD` still
outranks this: the fix is always to move a fact to the page that owns it, never to delete it.

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

### PD-8: retired, and the identifier is kept rather than reissued

PD-8 named four sections that look like filler and are not, so an editor applying `OPEN-3` or `B-6`
leaves them alone. All four left with
[secure-development-standards](https://github.com/wshallwshall/secure-development-standards).
Nothing here is under it, and PD-6 forbids reissuing an identifier.

That repository does not follow them: its house style comes from its own gates. Two of the four are
held by tests written for other reasons -- `test_rule_ids_are_stable.py` parses `## Retired rules`,
and the selector test pins the sentinel on both sides.

The status-check date line and the ASVS Part 1 to Part 2 boundary marker are held by nothing at all.
That is the condition PD-8 was written for, true again one repository over, where a rule covering it
is proposed rather than assumed.

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
2. Before renaming or deleting any heading under `docs/`, search the repository for its text. Pages
   here cite headings by name and link to them by anchor, and `tests/test_internal_links_resolve.py`
   fails on an anchor whose heading has moved.
3. Tests run from inside `tests/`: `python -m unittest discover -s . -q`. A run from the repository
   root finds nothing and exits without testing anything.
4. Run `scripts/coord/overlap.ps1` before starting a chunk of work. A clean merge proves lines did not
   collide, not that intentions did not.
