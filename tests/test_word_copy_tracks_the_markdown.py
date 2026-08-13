"""Pin every published Word copy against the markdown it came from, by REBUILDING it.

THE FAILURE THIS EXISTS FOR. `docs/word/KORUS.docx` is GENERATED from `docs/KORUS.md`, and nothing
regenerates it automatically. The page offers both formats to the reader in its second line, so an
edit to the markdown leaves a stale Word copy published beside a current markdown one, and the Word
file carries no sign of being out of date. That page changed three times on 2026-08-13 alone, which
is the rate this gate is sized against.

`docs/KORUS.md` is the one page under OPEN-8, published in its author's own words, which exempts it
from the rules that would require rewriting the author. It exempts nothing about whether a GENERATED
copy of it is current: regenerating a generated file rewrites nobody. A gate over the copy is a new
obligation on that page rather than a relaxation of one.

HOW IT IS CHECKED: BY REBUILDING, NOT BY COMPARING STRINGS. The markdown is converted to a
temporary .docx with the same pandoc invocation that produced the committed one, and the two are
compared against each other (on what exactly, see below). That fails on any drift at all -- prose,
heading, table cell, link, ordering, a dropped paragraph -- with no per-edit maintenance and nothing
in this file to update when the page is reworded. The alternative, a two-sided assertion per edit
that the new prose is present and the deleted prose absent, was rejected: its strings belong to one
edit, so it rots into asserting something nobody has touched in a year, and it cannot catch the NEXT
stale copy. A check that only knows about edits somebody remembered to encode is not a gate.

WHAT IS COMPARED: NOT BYTES. A .docx is a zip, and this one is not byte-reproducible. Every zip
entry and `docProps/core.xml` carry the build wall clock. Measured here on 2026-08-13 with pandoc
3.10: rebuilding with the documented command below leaves EXACTLY ONE zip member differing from the
committed copy, and that member is `docProps/core.xml`. A byte comparison would therefore fail on
every run and prove nothing.

AND NOT THE ZIP MEMBERS EITHER, which is the near miss worth recording because it passes today.
Hashing each member and ignoring `docProps/core.xml` is a real option, and on the measurement above
it is green. It is rejected for two reasons. It reddens on the CONVERTER rather than on the
document: in the sibling repository this file was ported from, rebuilding its 14 published standards
with pandoc 3.1.3 against copies committed from 3.10 gave raw XML red on 14 of 14, while the three
projections below were red on 1 of 14. 3.1.3 is not an arbitrary pick -- it is what
`apt-get install pandoc` gives on Ubuntu 24.04, so that row is the CI this repository would have had
if the version were not pinned, and a gate that reddens every document at once whenever the
converter moves is one people learn to regenerate past without reading. And a mismatching sha256 for
`word/document.xml` names no sentence: it sends the reader to a diff tool that cannot open a .docx,
and they stop reading the failure instead of fixing it.

WHAT IS COMPARED INSTEAD: THREE PROJECTIONS OF THE AUTHOR'S CONTENT. The extracted text, the
external link targets in order, and the heading-level sequence. See `authored_content`. Each of the
last two closes a hole the text alone has, and each hole has a worked example that runs on every
pass of this file:

  * A heading DEMOTED from `##` to `###` keeps every one of its words. The extracted text is
    character-for-character identical while the section changes rank and drops out of the table of
    contents. Measured against this document on 2026-08-13: Heading1 x1, Heading2 x12, Heading3 x6
    becomes x1, x11, x7, with the text unchanged to the character.
  * A hyperlink's TARGET is not in the body at all. `word/document.xml` stores only `r:id="rId9"`;
    the URL lives in `word/_rels/document.xml.rels`. Stripping tags to compare words discards every
    URL in the file -- 28 of them in this copy, 14 distinct. Repoint a link in the markdown and a
    text comparison sees nothing, while the published Word copy goes on sending readers to the old
    address under anchor text that still reads correctly.

WHAT THE THREE GIVE UP, stated rather than left for someone to discover. A wrong READER FLAG can
read as no drift: measured on 2026-08-13, rebuilding with `-f markdown-smart` instead of `-f gfm`
leaves all three projections identical while changing `word/document.xml`. That hole is closed by
pinning the options rather than by widening what is compared -- see `TheRecipeIsTheOneThisFileRuns`
below, which parses the regenerate block out of this docstring and compares it, as an ORDERED list,
against the options the rebuild actually passes.

PANDOC IS A DEPENDENCY OF THIS SUITE, NOT AN OPTIONAL EXTRA. If it is missing, these tests FAIL.
They do not skip. `tests/README.md` records the asymmetry as a decided question: the cases that run
`pwsh` or `git` may skip, because their absence leaves only a script that cannot run on that host,
while pandoc's absence would leave a PUBLISHED ARTIFACT with nothing checking it. It is the same
call `scripts/quality/check-ascii.ps1` makes by exiting 2 for having scanned no files rather than 0
for having found none. Install pandoc, or delete `docs/word/` and stop offering the format; there is
no third position in which this file means anything.

THE CONVERTER IS PINNED AT 3.10, and `.github/workflows/gates.yml` installs that version by sha256.
The committed copy was verified against 3.10 on 2026-08-13: all three projections match. A version
difference is the one failure here that is not a stale document, and with a single document it looks
exactly like drift -- so the failure message prints the version it used, and the first move on a red
run over a page nobody edited is to read that line.

REGENERATE WITH (from the repository root, needs pandoc):

    pandoc docs/KORUS.md -f gfm -t docx --toc --toc-depth=2 -o docs/word/KORUS.docx

That block is not decoration. `TheRecipeIsTheOneThisFileRuns` below parses it out of this docstring
and fails if it stops agreeing with the options, the destination, or the set of documents these
tests rebuild. A person following the block by hand and this suite therefore cannot drift apart.

WHAT THIS COSTS TO KEEP. The SET of documents is derived from the pages: a page that links to
`word/<name>.docx` is a page offering a Word download, so a second copy needs no edit here beyond
one line in the block above. The OPTIONS are not derivable and never will be -- `--toc` is an
editorial decision per document -- and a wrong option reads exactly like drift rather than like a
mistake, which is why the block is parsed rather than trusted.

WHEN TWO BRANCHES COLLIDE ON THE PAGE. A .docx is a zip and git cannot merge one, so any two
branches touching `docs/KORUS.md` conflict on the binary every time, whatever they changed, and that
conflict carries no information. Resolve the MARKDOWN first, by reading it, and THEN regenerate.
Never resolve the .docx directly: it is generated, so a hand-picked side is wrong even when it opens
cleanly. This is a note rather than a checker because nothing under tests/ runs during a rebase.

WHAT THIS DOES NOT COVER. Only EXTERNAL link targets are compared, so an internal bookmark or an
image relationship that moved is invisible here. `word/footnotes.xml` is read for text but carries
nothing today, and `heading_levels` reads the body alone, so a heading inside a footnote would not
reach the level sequence. The three mutation cases exercise the FIRST offered document only; with a
second copy they would prove the instrument rather than the corpus. Nothing is written outside a
temporary directory the operating system owns.

Run (this is what CI runs, from inside tests/):

    python -m unittest discover -s . -p 'test_*.py'

The single-module form works too, and also only from inside tests/:

    cd tests && python -m unittest test_word_copy_tracks_the_markdown
"""

from __future__ import annotations

import html
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

import _ccxtest as t

DOCS = t.REPO_ROOT / "docs"
WORD = DOCS / "word"

# A page OFFERS a Word download by linking to one. Deriving the set this way rather than naming
# KORUS in a constant is what makes a second Word copy cost nothing here -- and it fails in a
# readable direction if the offer link is ever reworded, because the copy under docs/word/ then has
# no offer pointing at it and the orphan case below says so by name. The lookbehind stops
# `sword/x.docx` and `docs.word/x.docx` matching; the link in this repository is written as a full
# https URL, so the character before `word/` is a slash.
OFFER = re.compile(r"(?<![\w.-])word/([A-Za-z0-9._-]+)\.docx")

# The options the committed copies were built with. ONE DEFINITION: the rebuild passes this, the
# remediation line prints it, and the docstring round trip compares against it. An ordered tuple,
# because that comparison is by list and the order is not cosmetic -- see the reader-flag hole above.
PANDOC_OPTIONS = ("-f", "gfm", "-t", "docx", "--toc", "--toc-depth=2")

# The parts `docx_text` reads for the visible WORDS. `word/document.xml` is the body;
# `word/footnotes.xml` carries nothing today, because the page uses no footnote, and is read anyway,
# because the day one does is the day prose starts hiding somewhere unchecked.
TEXT_PARTS = ("word/document.xml", "word/footnotes.xml")

# The one part no .docx can be missing. Read unconditionally, so a package without a body raises
# instead of reporting an empty document -- which would read as "no drift".
BODY = TEXT_PARTS[0]

# A tripwire for a technically valid but empty document. The committed copy extracts 7,679
# characters, so this is nowhere near it: it exists to catch a truncated or bodyless file passing as
# "no text found", which reads the same as "no drift".
TEXT_FLOOR = 500

# What a file that is not a readable Word document raises. UnicodeDecodeError is in the list because
# the XML is decoded STRICTLY here: the file this file was ported from decoded with errors="ignore",
# which drops a mis-encoded byte out of both sides of the comparison and calls the result agreement.
UNREADABLE = (zipfile.BadZipFile, KeyError, UnicodeDecodeError)

# A level-2 heading in the markdown. Used only to prove that a mutation left the headings alone.
H2 = re.compile(r"^##\s+(.+?)\s*$", re.M)

# An inline link to an absolute address, in the markdown.
MD_EXTERNAL_LINK = re.compile(r"\]\((https?://[^)\s]+)\)")

_HEADING_STYLE = re.compile(r'<w:pStyle\s+w:val="(Heading\d+)"')

# Anchored at end of line, so appending a trailing comment or a shell continuation to the documented
# command breaks the parse -- and `documented_builds` raises rather than passing on nothing.
_PANDOC_LINE = re.compile(r"^\s*pandoc\s+(\S+)\s+(.+?)\s+-o\s+(\S+)\s*$", re.M)


def docx_text(path) -> str:
    """The document's visible text, tags stripped. Raises if it is not a readable .docx.

    `word/document.xml` is required -- a package without it is not a Word document, and letting
    that pass as "no text found" would turn a corrupt file into a quiet zero.

    THE ORDER OF THE THREE STEPS IS LOAD-BEARING. Tags are stripped FIRST, because a literal `<` in
    the author's text is stored as an entity and unescaping before the strip would manufacture a tag
    that the strip then eats along with the words after it. A tag becomes a SPACE rather than
    nothing, because Word splits one sentence across runs and deleting the tags would fuse the words
    on either side. Whitespace is collapsed LAST, because an entity that decodes to whitespace
    otherwise escapes the collapse and lands in the compared string as literal whitespace that
    nothing normalises. The sibling this came from unescapes last and carries that hole.

    Unescaping is not optional. An apostrophe is stored as an entity, and this document has one in a
    heading; without the unescape the comparison would report drift on a copy that is current.
    """
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        chunks = [z.read(BODY)] + [z.read(p) for p in TEXT_PARTS[1:] if p in names]
    xml = " ".join(c.decode("utf-8") for c in chunks)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", xml)))


def heading_levels(path) -> list:
    """The heading LEVELS in document order: Heading1, Heading2, and so on.

    Compared because a heading demoted from `##` to `###` keeps every one of its words, so the
    extracted text stays character-for-character identical while the section changes rank and drops
    out of the table of contents.

    The capture is anchored immediately after the opening quote, so pandoc's own TOC styles
    (`TOCHeading`, `TOC1`, `TOC2`) do not match and only real body headings are collected. A style
    name is a stable OOXML convention, which is why this survives a converter bump that the
    numbering, spacing and rsid attributes around it do not.
    """
    with zipfile.ZipFile(path) as z:
        return _HEADING_STYLE.findall(z.read(BODY).decode("utf-8"))


def docx_link_targets(path) -> list:
    """Every external address the document points at, in relationship order.

    Read from the relationship parts because that is the only place they exist. The parts are sorted
    so the order is the document's rather than the zip directory's, and the two attributes are
    tested independently rather than with one pattern that assumes the order they are written in.
    """
    targets = []
    with zipfile.ZipFile(path) as z:
        for name in sorted(n for n in z.namelist() if n.endswith(".rels")):
            for element in re.findall(r"<Relationship\b[^>]*>", z.read(name).decode("utf-8")):
                if 'TargetMode="External"' not in element:
                    continue
                target = re.search(r'Target="([^"]+)"', element)
                if target:
                    targets.append(html.unescape(target.group(1)))
    return targets


def authored_content(path) -> dict:
    """What the AUTHOR put in this document. The verdict is taken on this, and dict equality does it.

    THREE PROJECTIONS, each because leaving it out is a hole with a worked example in this file:

      text    the prose, the headings' words, the table cells. The obvious one.
      links   the external targets, in order. NOT in the body: `document.xml` refers to a link only
              as an `r:id` and the URL lives in a relationship part, so a comparison of words
              discards every URL in the file.
      levels  the heading-level sequence, for the demotion case.
    """
    return {
        "text": docx_text(path),
        "links": docx_link_targets(path),
        "levels": heading_levels(path),
    }


def offered_stems() -> set:
    """Every Word copy this documentation set OFFERS, read off the pages that link to one."""
    found = set()
    for page in sorted(DOCS.glob("*.md")):
        found.update(OFFER.findall(t.read(page)))
    return found


def word_copy_sources() -> list:
    """The markdown behind every offered Word copy: `docs/<stem>.md`, one per offer."""
    return [DOCS / (stem + ".md") for stem in sorted(offered_stems())]


def committed_copy(src) -> Path:
    """Where the Word copy of one page is committed."""
    return WORD / (Path(src).stem + ".docx")


def as_written(path) -> str:
    """How the regenerate block names a file: relative to the repository root, forward slashes.

    Derived from the Path rather than typed a second time, so the docstring is checked against the
    filesystem and not against a string somebody wrote twice.
    """
    return "/".join(Path(path).resolve().relative_to(t.REPO_ROOT.resolve()).parts)


def regenerate_command(src) -> str:
    """The exact command that rebuilds one committed copy, run from the repository root.

    Built from the same constants the rebuild uses, so the fix printed on failure cannot itself
    drift from what this gate will accept.
    """
    return (
        f"pandoc {as_written(src)} {' '.join(PANDOC_OPTIONS)} "
        f"-o {as_written(committed_copy(src))}"
    )


def require_pandoc() -> str:
    """Where pandoc is. Raises rather than skipping when it is absent, on purpose.

    A skipped test is printed beside the passes and is read as one. This file's whole subject is a
    generated document nobody re-derived, so a run that could not re-derive it has proved nothing
    about it and must say so as a failure.
    """
    exe = shutil.which("pandoc")
    if exe is None:
        raise AssertionError(
            "pandoc is not on PATH, so the Word copy could not be rebuilt and NOTHING about it was "
            "checked. This is a FAILURE and not a skip, deliberately: a skip reads as a pass, and "
            "this document is published to outside readers who reach it from the page's own "
            "download line. Install pandoc 3.10 (https://pandoc.org/installing.html), or delete "
            "docs/word/ and the offer link in docs/KORUS.md and stop publishing the Word format -- "
            "but do not leave the copy published with nothing checking it."
        )
    return exe


def pandoc_version(exe: str) -> str:
    """The converter's own version line, for a failure message that can name the likely cause."""
    result = subprocess.run([exe, "--version"], capture_output=True, text=True)
    lines = (result.stdout or "").splitlines()
    return lines[0].strip() if lines else "unknown version"


def build_docx(exe: str, src, dest: Path) -> Path:
    """Convert one page into `dest`. Raises on any failure, and never returns a file that is absent.

    Both failure paths are checked. Trusting the exit code without verifying the artifact exists is
    how a comparison ends up comparing nothing, and comparing nothing would pass.
    """
    result = subprocess.run(
        [exe, str(src), *PANDOC_OPTIONS, "-o", str(dest)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"pandoc could not build {Path(src).name} (exit {result.returncode}). The comparison "
            f"cannot run, so nothing was proved about the committed copy:\n{result.stderr.strip()}"
        )
    if not dest.exists():
        raise AssertionError(
            f"pandoc reported success for {Path(src).name} but wrote no file. Treated as a failure: "
            "an absent build cannot be compared, and comparing nothing would pass."
        )
    return dest


def rebuild_from_source(exe: str, markdown: str, name: str):
    """Build a .docx from markdown held in memory. Returns (the three projections, the visible text).

    Everything is written under a temporary directory the operating system owns. Nothing is written
    inside the repository and the working tree is not touched, which is what lets the mutation cases
    below edit this document without editing this document.

    Written under the original NAME so nothing in the comparison can depend on the file's identity,
    and written with an explicit LF newline argument: the default writes CRLF on Windows and LF on
    Linux from identical input, so the temporary source would otherwise differ from the committed
    one by platform. Measured on 2026-08-13 with pandoc 3.10, neither the name nor the line ending
    reaches the output under these options, so both are pinned to keep a failure of the control case
    pointing at the document rather than at the harness.
    """
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / name
        source.write_text(markdown, encoding="utf-8", newline="\n")
        built = build_docx(exe, source, Path(tmp) / "rebuilt.docx")
        return authored_content(built), docx_text(built)


def first_difference(rebuilt: str, committed: str) -> str:
    """Where two extracted texts diverge, with enough of each side to recognise the edit.

    A bare "they differ" about a .docx sends the reader to a diff tool that cannot open one, and
    they stop reading the failure instead of fixing it. Printing the divergence point and its
    surroundings names the paragraph that moved.
    """
    i = 0
    limit = min(len(rebuilt), len(committed))
    while i < limit and rebuilt[i] == committed[i]:
        i += 1
    lead = max(0, i - 70)
    return (
        f"diverges at character {i} (committed {len(committed)} chars, rebuilt {len(rebuilt)})\n"
        f"      committed: ...{committed[lead:i + 150]}\n"
        f"      rebuilt  : ...{rebuilt[lead:i + 150]}"
    )


def _levels_summary(levels: list) -> str:
    """Heading levels as counts, so a demotion reads as one number down and another up."""
    return ", ".join(f"{lvl} x{levels.count(lvl)}" for lvl in sorted(set(levels))) or "no headings"


def describe_drift(rebuilt: dict, committed: dict) -> str:
    """Why these two documents are not the same, in the most readable terms available.

    Layered on purpose, cheapest to read first. A prose edit is named by its sentence, a moved link
    by its URL, a restructure by the level counts. This is the whole product of the gate below: a
    failure nobody can act on is one people delete the test to silence.
    """
    if rebuilt["text"] != committed["text"]:
        return first_difference(rebuilt["text"], committed["text"])

    if rebuilt["links"] != committed["links"]:
        gone = [u for u in committed["links"] if u not in rebuilt["links"]]
        added = [u for u in rebuilt["links"] if u not in committed["links"]]
        return (
            "every visible word is unchanged, but the LINKS are not: the Word copy points somewhere "
            "the markdown no longer does, under anchor text that still reads correctly.\n"
            f"      only in the committed copy: {gone[:4] if gone else 'none'}\n"
            f"      only in the rebuild       : {added[:4] if added else 'none'}"
        )

    return (
        "every visible word and every link is unchanged, but a heading changed LEVEL. The section "
        "keeps its wording and leaves the table of contents, which is why this needs its own "
        "check.\n"
        f"      committed: {_levels_summary(committed['levels'])}\n"
        f"      rebuilt  : {_levels_summary(rebuilt['levels'])}"
    )


def first_prose_line(lines: list) -> int:
    """Index of the first line of ordinary prose: not a heading, list, table, quote or code fence.

    Selected by SHAPE so the mutation cases move with the document instead of quoting a sentence
    somebody is free to rewrite -- and this page is published in its author's words, so quoting one
    would be pinning prose nobody here is allowed to edit. Raises rather than falling back to a
    default, because a mutation applied to the wrong kind of line would quietly model the wrong
    failure.
    """
    in_fence = False
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not stripped:
            continue
        if stripped[0] in "#-*|>+" or re.match(r"^\d+[.)]\s", stripped):
            continue
        if len(stripped) > 40:
            return i
    raise AssertionError(
        "found no ordinary prose line to edit. The mutation cases cannot model a prose-only change "
        "against this document, so they would be asserting nothing."
    )


def documented_builds() -> dict:
    """Every document the regenerate block covers: {stem: (source, options, destination)}.

    Parsed rather than trusted. The block is the instruction a person follows by hand; if it and the
    options these tests rebuild with ever disagree, regenerating as documented produces a file this
    suite then rejects, and the gate becomes unsatisfiable by following its own instructions.

    Raises when it reads nothing, because an empty mapping would compare equal to an empty
    expectation and report agreement. Raises on a repeated stem too: a dict would keep the last line
    silently, so two disagreeing commands for one document would read as one agreeing command.
    """
    lines = _PANDOC_LINE.findall(__doc__ or "")
    if not lines:
        raise AssertionError(
            "could not read the regenerate block out of this file's own docstring. Either it was "
            "reshaped, or docstrings were stripped (python -OO). Do NOT delete this test to make "
            "that go away: the block is what a person follows by hand, and this is what stops it "
            "drifting from the options the rebuild uses."
        )
    stems = [Path(src.strip('"')).stem for src, _options, _dest in lines]
    if len(set(stems)) != len(stems):
        raise AssertionError(
            f"the regenerate block names a document more than once: {sorted(stems)}. Two commands "
            "for one file cannot both be the one this suite runs, and reading them into a mapping "
            "would keep the last quietly."
        )
    return {
        stem: (src.strip('"'), options.split(), dest.strip('"'))
        for stem, (src, options, dest) in zip(stems, lines)
    }


class TheWordCopyIsOfferedAndCommitted(unittest.TestCase):
    """The cheap half. Every case here runs without a converter installed."""

    def test_the_offered_set_is_not_empty(self):
        """A scan that matched nothing would make every case below vacuously true."""
        self.assertGreaterEqual(
            len(word_copy_sources()),
            1,
            "no page under docs/ offers a Word download, so this whole file is now checking an "
            "empty set and passing for the wrong reason. Either the offer link was reworded -- in "
            "which case the copy under docs/word/ is still published with nothing checking it, and "
            "the orphan case below is what says so -- or the format was withdrawn and docs/word/ "
            "should have gone with it.",
        )

    def test_every_offered_copy_has_a_markdown_source(self):
        missing = [
            f"{src.name} (offered as {as_written(committed_copy(src))})"
            for src in word_copy_sources()
            if not src.exists()
        ]
        self.assertEqual(
            [],
            missing,
            f"a page offers a Word download of markdown that is not there: {missing}. Nothing can "
            "regenerate that copy, so it is a published document that cannot be corrected.",
        )

    def test_every_offered_copy_is_committed(self):
        missing = [
            committed_copy(src).name
            for src in word_copy_sources()
            if not committed_copy(src).exists()
        ]
        self.assertEqual(
            [],
            missing,
            f"these Word copies are offered to readers but not committed: {missing}. The download "
            "link is live and the file behind it is absent. Regenerate with the command in this "
            "file's header, or remove the offer.",
        )

    def test_no_word_copy_is_an_orphan(self):
        """The direction every other case here cannot see.

        Every other check starts from a page and asks whether its Word copy matches. That direction
        cannot notice a file left behind by a rename or a deletion, or a second copy that arrived
        without an offer: the source it would be compared against is not in the derived set, so the
        copy drops out of the checked set silently and goes on being served -- Jekyll copies
        everything under docs/ to the site, so an orphan is published rather than merely present.
        """
        expected = {p.stem for p in word_copy_sources()}
        orphans = sorted(d.name for d in WORD.glob("*.docx") if d.stem not in expected)
        self.assertEqual(
            [],
            orphans,
            f"these Word copies are not offered by any page: {orphans}. Either the offer link was "
            "reworded, in which case nothing else in this file looks at the copy any more, or the "
            "page was renamed or deleted and the copy stayed. Restore the offer, or delete the "
            "copy.",
        )

    def test_every_committed_copy_is_real_ooxml_and_not_empty(self):
        """A corrupt or truncated file must not pass as "no text found", which reads as "no drift"."""
        broken = []
        for src in word_copy_sources():
            copy = committed_copy(src)
            if not copy.exists():
                continue
            try:
                text = docx_text(copy)
            except UNREADABLE as exc:
                broken.append(
                    f"{copy.name}: not a readable Word document ({type(exc).__name__}). "
                    "BadZipFile means it is not a zip at all; KeyError means the package has no "
                    f"{BODY}. Rebuild it: {regenerate_command(src)}"
                )
                continue
            if len(text) < TEXT_FLOOR:
                broken.append(
                    f"{copy.name}: extracts only {len(text)} characters of text, under a floor of "
                    f"{TEXT_FLOOR}. It opens as a valid package and says almost nothing, which "
                    "every comparison in this file would read as agreement."
                )
        self.assertEqual(
            [],
            broken,
            "these Word copies are not usable documents:\n" + "\n".join(broken),
        )


class TheWordCopyIsWhatTheMarkdownProducesToday(unittest.TestCase):
    """Rebuild each page and compare the result against the copy committed beside it.

    The three mutation cases are not padding. Each edits the markdown in a way a comparison of words
    alone cannot see -- prose under an unchanged heading, a heading demoted, a link repointed -- and
    asserts BOTH what the cheap reading misses and that this comparison still goes red. They are the
    evidence that each projection earns its place, kept beside the gate rather than in a commit
    message somebody would have to go looking for.

    EVERY MUTATION CASE COMPARES A MUTANT AGAINST A FRESH REBUILD OF THE SAME PAGE, NEVER AGAINST
    THE COMMITTED COPY, and that is the correction worth reading before changing any of them. The
    obvious way to write them is to rebuild the mutant and assert it differs from `docs/word/*.docx`
    -- which is how the two files this was merged from wrote it, and it is wrong in the one
    situation this whole file exists for. A STALE committed copy already differs from the mutant, so
    those cases fail too, and their messages say things like "demoting a heading changed the visible
    TEXT, so the reasoning in this file's header is now wrong". Measured on 2026-08-13 by editing
    one word of `docs/KORUS.md` and leaving the .docx alone: FOUR cases failed, and TWO of them told
    the reader to go and correct this file's reasoning rather than to regenerate the document. A
    gate whose own self-tests misdirect on its only real failure is worse than one with no
    self-tests. Compared against a fresh rebuild they are pure instrument checks, independent of
    whether the committed copy is current, and a stale copy now reddens exactly one case: the gate.
    """

    def mutation_source(self) -> Path:
        """The page the mutation cases edit in memory: the first offered one.

        Named here rather than hard-coded in four places, so the cases follow the derived set. With
        one document that is this page; with two it is the first alphabetically, and the mutations
        then prove the INSTRUMENT rather than the corpus -- which is what the header says they do.
        """
        sources = word_copy_sources()
        self.assertTrue(
            sources,
            "no page offers a Word download, so there is nothing to mutate and this case would be "
            "asserting nothing.",
        )
        src = sources[0]
        self.assertTrue(src.exists(), f"{as_written(src)} is gone; there is nothing to rebuild.")
        return src

    def test_the_committed_copy_rebuilds_from_the_markdown(self):
        exe = require_pandoc()
        sources = word_copy_sources()
        # Restated here rather than left to the sibling case above, so the gate that matters does
        # not depend on another test in this module having run.
        self.assertGreaterEqual(
            len(sources),
            1,
            "no page offers a Word download, so this rebuild would compare nothing and pass. Find "
            "out where the offer went before trusting a green run.",
        )

        drifted = []
        agreed = []
        with tempfile.TemporaryDirectory() as tmp:
            for src in sources:
                copy = committed_copy(src)
                if not src.exists():
                    drifted.append(f"{copy.name}: the markdown it is built from is gone")
                    continue
                # The rebuild runs BEFORE the committed copy is read, so a broken converter is
                # reported as a broken converter rather than as drift.
                fresh = build_docx(exe, src, Path(tmp) / copy.name)
                if not copy.exists():
                    drifted.append(
                        f"{copy.name}: no Word copy is committed at all. Build it: "
                        f"{regenerate_command(src)}"
                    )
                    continue
                try:
                    have = authored_content(copy)
                except UNREADABLE as exc:
                    drifted.append(
                        f"{copy.name}: not a readable .docx ({type(exc).__name__}), so it cannot "
                        f"be compared against anything. Rebuild it: {regenerate_command(src)}"
                    )
                    continue
                want = authored_content(fresh)
                if want == have:
                    agreed.append((src, have))
                else:
                    drifted.append(
                        f"{copy.name}: {describe_drift(want, have)}\n"
                        f"      rebuild it: {regenerate_command(src)}"
                    )

        # The specific report FIRST, and by `fail` rather than `assertEqual([], drifted, ...)`,
        # which is the idiom everywhere else in this file. The report is multi-line and is the
        # entire product of this test; assertEqual would print it twice -- once as a raw list repr,
        # once as the message -- and cap the first copy with "Diff is N characters long", which
        # reads as though it had been truncated.
        if drifted:
            self.fail(
                f"the committed Word copy is NOT what its markdown produces ({pandoc_version(exe)}"
                "):\n\n"
                + "\n\n".join(drifted)
                + "\n\nRegenerate it in the SAME commit as the markdown change. A stale Word copy "
                "is a published document that no longer says what its page says, and it carries no "
                "sign of being out of date.\nThere is one document here, so 'the converter moved' "
                "and 'the markdown drifted' look identical. The copy was verified against pandoc "
                "3.10; read the version above before believing the markdown is at fault."
            )

        # RECEIPTS, reached only once nothing has drifted -- which is precisely when they are
        # needed, because two empty projections also compare equal. Each number below is one this
        # comparison would have reported as agreement if the extraction behind it silently stopped
        # working, and each is checked against what the MARKDOWN says should be there rather than
        # against a constant, so a document that legitimately has no link is not reddened for it.
        self.assertEqual(
            len(sources),
            len(agreed),
            f"only {len(agreed)} of {len(sources)} offered Word copies reached the comparison, and "
            "yet nothing was reported as drifted. Something was skipped by a path that does not "
            "record itself, so this green result is a statement about a set nobody chose.",
        )
        for src, have in agreed:
            copy = committed_copy(src)
            markdown = t.read(src)
            self.assertGreater(
                len(have["text"]),
                TEXT_FLOOR,
                f"{copy.name}: the comparison agreed, having read only {len(have['text'])} "
                "characters of text. A green result over almost nothing is a statement about a "
                "document nobody chose.",
            )
            if H2.search(markdown):
                self.assertTrue(
                    have["levels"],
                    f"{copy.name}: the comparison agreed, having found no headings at all, while "
                    f"{as_written(src)} has level-2 headings. The heading-level projection is "
                    "reading nothing, so every demotion is now invisible to this file.",
                )
            if MD_EXTERNAL_LINK.search(markdown):
                self.assertTrue(
                    have["links"],
                    f"{copy.name}: the comparison agreed, having found no external links, while "
                    f"{as_written(src)} carries at least one. The relationship parts have dropped "
                    "out of the comparison, so every URL in the published copy is now unchecked.",
                )

    def test_the_rebuild_sees_prose_that_moved_under_an_unchanged_heading(self):
        """The failure this whole approach exists for, pinned open so it cannot quietly return.

        A paragraph is edited and no heading moves. Any check that compares titles and headings
        stays green through it. Both halves are asserted -- that the headings are untouched, and
        that the rebuild catches the edit anyway -- so nobody has to take on trust that rebuilding
        earns its cost over reading the headings.
        """
        exe = require_pandoc()
        src = self.mutation_source()
        original = t.read(src)

        lines = original.split("\n")
        target = first_prose_line(lines)
        lines[target] = lines[target] + " A sentence the committed Word copy has never seen."
        mutated = "\n".join(lines)

        self.assertNotEqual(original, mutated, "the mutation changed nothing; this proves nothing")
        self.assertEqual(
            H2.findall(original),
            H2.findall(mutated),
            "the mutation moved a heading, so it does not model the failure this case is about",
        )

        _, baseline = rebuild_from_source(exe, original, src.name)
        _, fresh = rebuild_from_source(exe, mutated, src.name)
        self.assertNotEqual(
            baseline,
            fresh,
            "a paragraph was edited under an unchanged heading and the rebuild did not notice. The "
            "comparison is not reading what it thinks it is reading, and the gate above is "
            "decorative.",
        )

    def test_the_rebuild_sees_a_heading_demoted_without_its_words_changing(self):
        """A `##` turned into a `###`. Every word survives; the document does not.

        This is why `levels` is compared. The heading keeps its wording, so the extracted text is
        character-for-character identical -- pandoc writes the table of contents as a Word FIELD
        rather than as text, so even the entry leaving the contents changes no character -- while
        the section has changed level. Both facts are asserted, because the first is the entire
        justification for the second projection existing.
        """
        exe = require_pandoc()
        src = self.mutation_source()
        original = t.read(src)

        lines = original.split("\n")
        index = next((i for i, line in enumerate(lines) if re.match(r"^##\s+\S", line)), None)
        self.assertIsNotNone(index, f"{as_written(src)} has no level-2 heading to demote")
        lines[index] = "#" + lines[index]

        base_parts, base_text = rebuild_from_source(exe, original, src.name)
        parts, text = rebuild_from_source(exe, "\n".join(lines), src.name)
        self.assertEqual(
            base_text,
            text,
            "demoting a heading changed the visible TEXT. That is a better outcome than this case "
            "expects, but the reasoning in this file's header is now wrong and should be corrected.",
        )
        self.assertNotEqual(
            base_parts,
            parts,
            "a heading changed level and the comparison saw nothing. It has fallen back to "
            "comparing words, and every structural edit is now invisible to this file.",
        )

    def test_the_rebuild_sees_a_link_repointed_under_unchanged_anchor_text(self):
        """A URL changed, the words around it untouched.

        The one a text comparison cannot reach even in principle: the target is not in the body, so
        no amount of reading the words will find it. A published document that sends readers to a
        page that has moved is the same failure as one that states something no longer true -- and
        this page's own links moved host once already, which is why the repository bans the old one.
        """
        exe = require_pandoc()
        src = self.mutation_source()
        original = t.read(src)

        link = MD_EXTERNAL_LINK.search(original)
        self.assertIsNotNone(link, f"{as_written(src)} has no external link, so this models nothing")
        # Replaced at its exact span rather than by `str.replace(url, ..., 1)`. The same URL is
        # written in prose as well as in a link on some pages, and replacing the first occurrence
        # anywhere would change the visible WORDS -- so the equality half below would then fail for
        # a reason that has nothing to do with link targets.
        mutated = (
            original[: link.start(1)] + "https://example.invalid/moved" + original[link.end(1):]
        )
        self.assertNotEqual(original, mutated, "the link rewrite changed nothing")

        base_parts, base_text = rebuild_from_source(exe, original, src.name)
        parts, text = rebuild_from_source(exe, mutated, src.name)
        self.assertEqual(
            base_text,
            text,
            "repointing a link changed the visible TEXT, so pandoc now renders URLs as words. "
            "Better than expected, but this file's stated reason for reading the relationship "
            "parts is no longer the whole truth and should be corrected.",
        )
        self.assertNotEqual(
            base_parts,
            parts,
            "a link was repointed and the comparison saw nothing. The relationship parts have "
            "dropped out of it, and every URL in the published Word copy is now unchecked.",
        )

    def test_the_harness_the_mutants_run_through_changes_nothing(self):
        """The other half of the instrument: it must not cry drift over its own machinery.

        A check that fails on a correct file is worse than none, because the fix people reach for is
        to delete it. The mutants prove the comparison can see an edit; this proves that what it
        sees is the edit and not the harness -- the temporary directory, the working directory, the
        filename or the line endings.

        It is the ISOLATING form on purpose. The tempting version compares a rebuild against the
        committed .docx, and that conflates two questions: it fails both when the harness perturbs
        the output and when the committed copy is simply stale, with one message for both. The
        second question is the gate's, and the gate answers it by name. So this compares the page
        built IN PLACE, straight from the working tree, against the same page routed through the
        temporary-file path the mutants use. Only the harness differs between the two sides, so only
        the harness can fail it.
        """
        exe = require_pandoc()
        src = self.mutation_source()
        with tempfile.TemporaryDirectory() as tmp:
            in_place = authored_content(build_docx(exe, src, Path(tmp) / "in-place.docx"))
        through_harness, _ = rebuild_from_source(exe, t.read(src), src.name)
        self.assertEqual(
            in_place,
            through_harness,
            "one page built two ways produced two different documents, and the only difference "
            "between them is this file's own machinery -- a copy through a temporary directory, "
            "written with LF endings under the page's own name. Until that is understood every "
            "mutation case above is suspect, because the comparison is sensitive to something "
            f"other than the document. Check the converter first: {pandoc_version(exe)}",
        )


class TheRecipeIsTheOneThisFileRuns(unittest.TestCase):
    """The regenerate block in the header is followed by hand. Pin it to what the tests build with.

    If the two disagree, a person regenerates exactly as documented and the suite rejects the result
    -- a gate that cannot be satisfied by following its own instructions, which is the kind nobody
    trusts twice. This is also what closes the one hole the three projections have: they are blind
    to a wrong reader flag, so the flags are pinned instead of the comparison being widened.
    """

    def test_the_regenerate_block_covers_every_offered_word_copy(self):
        documented = set(documented_builds())
        offered = {p.stem for p in word_copy_sources()}
        self.assertEqual(
            offered,
            documented,
            "the regenerate block and the offered set disagree.\n"
            f"  offered but not in the block: {sorted(offered - documented)}\n"
            f"  in the block but not offered: {sorted(documented - offered)}\n"
            "A document missing from the block is one a bulk regeneration silently skips, which is "
            "how a Word copy goes stale while everything around it is rebuilt; a document in the "
            "block that nothing offers is a command nothing here checks the result of.",
        )

    def test_the_documented_source_is_the_page_this_file_rebuilds(self):
        wrong = []
        for stem, (src, _options, _dest) in sorted(documented_builds().items()):
            expected = as_written(DOCS / (stem + ".md"))
            if src != expected:
                wrong.append(f"{stem}: block reads {src}, this file rebuilds {expected}")
        self.assertEqual(
            [],
            wrong,
            "the regenerate block rebuilds from somewhere other than the page this file reads:\n"
            + "\n".join(wrong)
            + "\nBoth paths are relative to the repository root, which is where the block says to "
            "run it. Following it would rebuild from a page nothing publishes.",
        )

    def test_the_documented_options_are_the_options_the_rebuild_uses(self):
        wrong = []
        for stem, (_src, options, _dest) in sorted(documented_builds().items()):
            if options != list(PANDOC_OPTIONS):
                wrong.append(f"{stem}: block says {options}, the rebuild uses {list(PANDOC_OPTIONS)}")
        self.assertEqual(
            [],
            wrong,
            "the regenerate block no longer matches how this file builds:\n"
            + "\n".join(wrong)
            + "\nFix whichever is wrong. Leaving them apart means following the documented command "
            "produces a file this suite then calls drifted. Compared as an ORDERED list, so the "
            "block must read exactly -f gfm -t docx --toc --toc-depth=2 -- and the order is not "
            "cosmetic: rebuilding with a different reader leaves all three projections identical "
            "while changing the document, measured on 2026-08-13 with -f markdown-smart.",
        )

    def test_the_documented_destination_is_where_the_copy_is_committed(self):
        """The block writes to a path. This is the check that it is the path this file reads."""
        wrong = []
        for stem, (_src, _options, dest) in sorted(documented_builds().items()):
            expected = as_written(committed_copy(DOCS / (stem + ".md")))
            if dest != expected:
                wrong.append(f"{stem}: block writes {dest}, this file reads {expected}")
        self.assertEqual(
            [],
            wrong,
            "the regenerate block writes somewhere other than where the copy is read from:\n"
            + "\n".join(wrong)
            + "\nFollowing it would leave the committed copy untouched and drop a second one "
            "somewhere nothing checks, while every test here went on reporting the stale file.",
        )


if __name__ == "__main__":
    unittest.main()
