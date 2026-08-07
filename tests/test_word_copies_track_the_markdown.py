"""Pin the generated Word copies against the markdown they came from, by REBUILDING them.

THE FAILURE THIS EXISTS FOR. `docs/standards/word/*.docx` are GENERATED from the sibling markdown.
Nothing regenerates them automatically, so every edit to a standard silently leaves a stale Word
copy published beside a current markdown one, and a reader who took the Word file gets last week's
rules with no indication of it.

It has now happened twice, and the second time is why this file was rewritten. First a section was
renamed, and the Word copies kept the old name until they were rebuilt -- which the heading scan
below caught. Then on 2026-08-06 three sessions concurrently rewrote PROSE in REVIEW-DEPTH.md,
DILIGENCE-PACKET.md and CISO-SUMMARY.md, under headings that did not move. The check that lived here
compared the title and the H2 headings and nothing else, so it stayed GREEN through all three. Only
a hand-run check caught them. Its own docstring had admitted the hole in advance: "prose edited
inside a section that keeps its heading will not be caught here."

HOW IT IS CHECKED NOW: BY REBUILDING, NOT BY COMPARING STRINGS. Every standard is converted to a
temporary .docx with the same pandoc invocation that produced the committed one, and the two files
are compared against each other (on what exactly, see below). That fails on any drift at all --
prose, heading, table cell, link, ordering, a dropped paragraph -- with no per-edit maintenance and
nothing in this file to update when a document is reworded. And it fails for the right reason: the
committed .docx is not what this markdown produces.

WHAT WAS REJECTED, AND WHY. The obvious fix is a two-sided assertion per edit: the new prose is
present, the deleted prose is absent. It was used by hand on 2026-08-06 and it worked. It is
deliberately NOT institutionalised here, because its strings belong to one edit -- it rots into
asserting something nobody has touched in a year, and it cannot catch the NEXT stale copy. A check
that only knows about edits somebody already remembered to encode is not a gate.

WHAT IS COMPARED: NOT BYTES, AND NOT THE VISIBLE TEXT EITHER. A .docx is a zip and is not
byte-reproducible -- `docProps/core.xml` alone carries a build timestamp that changes on every run,
so a byte comparison would fail every time and prove nothing.

Comparing the visible TEXT is the obvious next move, and it was this file's first attempt. It is
porous in two ways, both found by attacking it rather than by reading it:

  * A heading DEMOTED from `##` to `###` keeps every one of its words. The extracted text is
    character-for-character identical while the document has restructured and that heading has
    dropped out of the table of contents.
  * A hyperlink's TARGET is not in the body at all. `word/document.xml` stores only `r:id="rId9"`;
    the URL lives in `word/_rels/document.xml.rels`. Stripping tags to compare words therefore
    discards every URL in the file -- 414 of them across these thirteen documents. Repoint a link in
    the markdown and a text comparison sees nothing, while the published Word copy goes on sending
    readers to the old address under identical anchor text.

So the verdict is taken on the NORMALIZED XML of the parts that carry authored content: the body,
the footnotes, and the relationship parts that hold the link targets, with whitespace collapsed and
nothing else touched. Those are reproducible -- every committed copy in this repository rebuilds to
identical XML in every one of them. The visible text is still extracted, but for the failure MESSAGE
rather than for the verdict, because "diverges at this sentence" is readable and "these two zip
members differ" is not.

PANDOC IS A DEPENDENCY OF THIS SUITE, NOT AN OPTIONAL EXTRA. If it is missing, these tests FAIL.
They do not skip. A skip is printed beside the passes and reads as one, and a result that measured
nothing is not a pass -- the same judgment `scripts/quality/check-ascii.ps1` makes when it exits 2
rather than 0 for having scanned no files. Install pandoc, or delete the Word copies and stop
offering the format; there is no third position in which this file is meaningful.

A PANDOC VERSION DIFFERENCE CAN ALSO FAIL THIS, and that is the one failure here that is not a
stale document. Every committed copy matched pandoc 3.10 output on 2026-08-06. If a rebuild differs
everywhere at once rather than in one document, suspect the converter before the markdown; the
failure message prints the version it used.

REGENERATE WITH (from docs/standards/, needs pandoc):

    for f in OVERVIEW CODE-QUALITY SECURE-DEVELOPMENT AI-ASSISTED-DEVELOPMENT DEPENDENCY-INTEGRITY REVIEW-DEPTH ADOPTING-THESE WHICH-STANDARDS-APPLY STANDARDS-LANDSCAPE STANDARDS-REFERENCE CI-ENFORCEMENT DILIGENCE-PACKET; do
      pandoc "$f.md" -f gfm -t docx --toc --toc-depth=2 -o "word/$f.docx"
    done
    # CISO-SUMMARY is the exception: no --toc. It is a two-page document, and a table of contents
    # on it costs a whole page to list six headings the reader can already see.
    pandoc CISO-SUMMARY.md -f gfm -t docx -o word/CISO-SUMMARY.docx
    # And the assessment method, which lives one directory up:
    pandoc ../ASVS-ASSESSMENT.md -f gfm -t docx --toc --toc-depth=2 -o word/ASVS-ASSESSMENT.docx

That block is not decoration. `TheRecipeIsTheOneThisFileRuns` below parses it and fails if it stops
agreeing with the options these tests build with, or if it stops covering every published standard
-- so a new standard added without a line here cannot be silently missed by a bulk regeneration.

WHAT THIS COSTS TO KEEP, stated plainly rather than sold as free. The SET of documents is derived
from the filesystem, so adding a standard needs no edit in this file. Its OPTIONS are not derivable
and never will be: `--toc` is an editorial decision per document. So a new standard costs one line
in the block above, and a new table-of-contents exception costs one entry in `NO_TOC`.

Neither can be forgotten quietly -- both fail loudly on the next run, and the flag table is
load-bearing rather than bookkeeping. Measured: building DILIGENCE-PACKET without `--toc` and
comparing it to the committed `--toc` copy MISMATCHES. A wrong option therefore reads exactly like
drift. If this suite goes red on a document nobody edited, check the options before believing the
document is stale. That is the trade: one line per new document, in exchange for never again having
to encode an individual edit as a pair of string assertions that rot within the year.

Run: python -m unittest discover -s tests     (pytest is not installed)
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

STANDARDS = t.REPO_ROOT / "docs" / "standards"
WORD = STANDARDS / "word"

HEADING = re.compile(r"^##\s+(.+?)\s*$", re.M)
TITLE = re.compile(r"^#\s+(.+?)\s*$", re.M)

# The options every standard is built with, and the ones only some of them get. Held as data because
# two tests need them: the rebuild, and the check that this file's own regenerate block still says
# the same thing.
BASE_OPTIONS = ("-f", "gfm", "-t", "docx")
TOC_OPTIONS = ("--toc", "--toc-depth=2")

# The documents built WITHOUT a table of contents. Declared as the exception rather than listing the
# other twelve, so a standard added tomorrow is covered by default -- being built with the wrong
# options fails loudly on the very next run, whereas not being covered at all fails silently, which
# is the whole failure class this file exists for.
NO_TOC = frozenset({"CISO-SUMMARY"})

# The parts `docx_text` reads for the visible WORDS. `word/document.xml` is the body;
# `word/footnotes.xml` carries nothing today because no standard uses a footnote, and is read anyway,
# because the day one does is the day prose starts hiding somewhere unchecked.
TEXT_PARTS = ("word/document.xml", "word/footnotes.xml")

# The one part no .docx can be missing. Read unconditionally, so a package without a body raises
# instead of reporting an empty document -- which would read as "no drift".
BODY = TEXT_PARTS[0]

_PANDOC_LINE = re.compile(r"^\s*pandoc\s+(\S+)\s+(.+?)\s+-o\s+(\S+)\s*$", re.M)
_REGEN_LOOP = re.compile(r"^\s*for\s+f\s+in\s+(.+?);\s*do\s*$", re.M)


def docx_text(path) -> str:
    """The document's visible text, tags stripped. Raises if it is not a readable .docx.

    `word/document.xml` is required -- a package without it is not a Word document, and letting that
    pass as "no text found" would turn a corrupt file into a quiet zero.
    """
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        # The body is NOT optional. Reading it unconditionally is what makes a package without one
        # raise KeyError instead of reporting an empty document, which would read as "no drift".
        chunks = [z.read(BODY)] + [z.read(p) for p in TEXT_PARTS[1:] if p in names]
    xml = " ".join(c.decode("utf-8", "ignore") for c in chunks)
    # Word splits a sentence across runs, so strip tags and collapse whitespace before matching.
    text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", xml))
    # UNESCAPE, or this scan reports drift that is not there. An apostrophe is stored as the entity
    # `&#39;`, so a heading containing one never matches its markdown source and every document with
    # a possessive in a heading looks stale. Found exactly that way, on the first run.
    return html.unescape(text)


def authored_parts(path) -> dict:
    """The XML this comparison takes its verdict from, whitespace collapsed and nothing else changed.

    THE BODY, THE FOOTNOTES, AND THE RELATIONSHIP PARTS. The first two are where words live. The
    third is where LINK TARGETS live, and it is included because leaving it out is a hole with a
    worked example: `document.xml` refers to a link only as `r:id="rId9"`, so a comparison of visible
    text cannot see a URL at all, and a Word copy can go on pointing at a moved page under anchor
    text that still reads correctly.

    Deliberately NOT the whole package. `docProps/core.xml` carries a build timestamp, and comparing
    it would fail every run -- a gate that is always red is one people learn to ignore, which is
    worse than the drift it was meant to catch.
    """
    parts = {}
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if BODY not in names:
            raise KeyError(BODY)
        for name in sorted(names):
            keep = name in TEXT_PARTS or (name.startswith("word/_rels/") and name.endswith(".rels"))
            if keep:
                # Whitespace only. Any richer normalisation would be this file quietly deciding which
                # differences are allowed to exist, which is the judgment it exists to refuse.
                parts[name] = re.sub(r"\s+", " ", z.read(name).decode("utf-8", "ignore"))
    return parts


def docx_link_targets(path) -> list:
    """Every external address the document points at, in relationship order.

    Read from the relationship parts because that is the only place they exist. Used to say WHICH
    link moved when the words are identical, rather than leaving the reader with "the markup
    differs" about a file no diff tool will open.
    """
    targets = []
    with zipfile.ZipFile(path) as z:
        for name in sorted(n for n in z.namelist() if n.endswith(".rels")):
            for element in re.findall(r"<Relationship\b[^>]*>", z.read(name).decode("utf-8", "ignore")):
                # Both attributes read independently, rather than in one pattern that assumes the
                # order they are written in.
                if 'TargetMode="External"' not in element:
                    continue
                target = re.search(r'Target="([^"]+)"', element)
                if target:
                    targets.append(html.unescape(target.group(1)))
    return targets


def published_standards() -> list:
    """Every markdown file offered with a Word copy beside it.

    ASVS-ASSESSMENT.md lives in docs/ rather than docs/standards/, because it predates the standards
    section. It is offered in the same download table and generated into the same word/ directory,
    so it is pinned here too -- a generated file nothing checks is the drift this file exists for.
    """
    extra = t.REPO_ROOT / "docs" / "ASVS-ASSESSMENT.md"
    return sorted(STANDARDS.glob("*.md")) + ([extra] if extra.exists() else [])


def plain(heading: str) -> str:
    """A heading or title reduced to its words.

    Inline code, emphasis and link brackets render as formatting in Word rather than as characters,
    so they are stripped before matching. Applied to the TITLE as well as to the H2s -- an earlier
    version stripped only the headings, which left a title carrying a code span reporting drift
    against a Word copy that was perfectly current.
    """
    return re.sub(r"[`*\[\]]", "", heading)


def pandoc_options(stem: str) -> list:
    """The pandoc options this standard is built with."""
    return list(BASE_OPTIONS) + ([] if stem in NO_TOC else list(TOC_OPTIONS))


def source_as_written(src: Path) -> str:
    """How the regenerate block names this source: relative to docs/standards/, forward slashes."""
    rel = Path(src).resolve().relative_to(STANDARDS.resolve().parent)
    parts = rel.parts[1:] if rel.parts[0] == "standards" else ("..",) + rel.parts
    return "/".join(parts)


def regenerate_command(src: Path) -> str:
    """The exact command that rebuilds one committed copy, run from docs/standards/."""
    options = " ".join(pandoc_options(Path(src).stem))
    return f"pandoc {source_as_written(src)} {options} -o word/{Path(src).stem}.docx"


def require_pandoc() -> str:
    """Where pandoc is. Raises rather than skipping when it is absent, on purpose.

    A skipped test is printed beside the passes and is read as one. This suite's whole subject is
    generated files nobody re-derived, so a run that could not re-derive them has proved nothing
    about them and must say so as a failure -- the same call `check-ascii.ps1` makes when it exits 2
    for having scanned nothing rather than 0 for having found nothing.
    """
    exe = shutil.which("pandoc")
    if exe is None:
        raise AssertionError(
            "pandoc is not on PATH, so the Word copies could not be rebuilt and NOTHING about them "
            "was checked. This is a FAILURE and not a skip, deliberately: a skip reads as a pass, "
            "and these documents are published to outside readers. Install pandoc "
            "(https://pandoc.org/installing.html), or delete docs/standards/word/ and stop offering "
            "the Word format -- but do not leave the copies published with nothing checking them."
        )
    return exe


def pandoc_version(exe: str) -> str:
    """The converter's own version line, for a failure message that can name the likely cause."""
    result = subprocess.run([exe, "--version"], capture_output=True, text=True)
    first = (result.stdout or "").splitlines()
    return first[0].strip() if first else "unknown version"


def build_docx(exe: str, src: Path, dest: Path) -> Path:
    """Convert one standard into `dest`. Raises on any failure; never returns a file that is not there."""
    result = subprocess.run(
        [exe, str(src), *pandoc_options(src.stem), "-o", str(dest)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise AssertionError(
            f"pandoc could not build {src.name} (exit {result.returncode}). The comparison below "
            f"cannot run, so nothing was proved about the committed copy:\n{result.stderr.strip()}"
        )
    if not dest.exists():
        raise AssertionError(
            f"pandoc reported success for {src.name} but wrote no file. Treated as a failure: an "
            "absent build cannot be compared, and comparing nothing would pass."
        )
    return dest


def first_difference(rebuilt: str, committed: str) -> str:
    """Where two extracted texts diverge, with enough of each side to recognise the edit.

    A bare "they differ" sends the reader to a diff tool that cannot open a .docx. Printing the
    divergence point and its surroundings names the paragraph that moved.
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


def first_prose_line(lines: list) -> int:
    """Index of the first line of ordinary prose: not a heading, list, table, quote or code fence.

    Selected by shape so the self-test that uses it moves with the document instead of quoting a
    sentence somebody is free to rewrite. Raises rather than falling back to a default, because a
    mutation applied to the wrong kind of line would quietly test the wrong thing.
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
        "found no ordinary prose line to edit. The self-test cannot model a prose-only change "
        "against this document, so it would be asserting nothing."
    )


def rebuild_from_source(exe: str, markdown: str, name: str):
    """Build a .docx from markdown held in memory. Returns (parts to compare, visible text).

    The copy is written under the given NAME because `build_docx` picks its options from the
    stem -- a mutant renamed to something else would quietly be built with a table of contents
    the original does not have, and the comparison would then be testing the options.
    """
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / name
        # newline="\n" EXPLICITLY. Without it this writes CRLF on Windows and LF on Linux, from
        # identical input, and the comparison would differ by platform for a reason that has nothing
        # to do with the document. (pandoc happens to treat the two the same -- which is what
        # `test_an_unedited_standard_rebuilds_identically_from_anywhere` is checking on every run --
        # but relying on that silently is how a test starts passing for the wrong reason.)
        source.write_text(markdown, encoding="utf-8", newline="\n")
        built = build_docx(exe, source, Path(tmp) / "rebuilt.docx")
        return authored_parts(built), docx_text(built)


def describe_drift(fresh, committed, differing: list) -> str:
    """Why these two documents are not the same, in the most readable terms available.

    Layered on purpose. A prose edit is named by its sentence, a moved link by its URL, and anything
    else by the parts it touched -- because "they differ" about a zip sends the reader to a diff tool
    that cannot open one, and they stop reading the failure instead of fixing it.
    """
    rebuilt_text, committed_text = docx_text(fresh), docx_text(committed)
    if rebuilt_text != committed_text:
        return first_difference(rebuilt_text, committed_text)

    rebuilt_links, committed_links = docx_link_targets(fresh), docx_link_targets(committed)
    if rebuilt_links != committed_links:
        gone = [u for u in committed_links if u not in rebuilt_links]
        added = [u for u in rebuilt_links if u not in committed_links]
        return (
            "every visible word is unchanged, but the LINKS are not: the Word copy points somewhere "
            "the markdown no longer does, under anchor text that still reads correctly.\n"
            f"      only in the committed copy: {gone[:4] if gone else 'none'}\n"
            f"      only in the rebuild       : {added[:4] if added else 'none'}"
        )

    return (
        "every visible word and every link is unchanged, but the markup is not -- a heading level, "
        "a list, a table or an emphasis moved. A heading demoted from ## to ### looks exactly like "
        f"this.\n      parts that differ: {', '.join(differing)}"
    )


def documented_builds() -> dict:
    """Every standard the regenerate block covers, mapped to the options it says to use.

    Parsed rather than trusted. The block is the instruction a person follows by hand; if it and the
    options these tests rebuild with ever disagree, regenerating as documented produces a file the
    suite then rejects, and the gate becomes unsatisfiable. Raises when it reads nothing, because an
    empty mapping would compare equal to an empty expectation and report agreement.
    """
    doc = __doc__ or ""
    lines = _PANDOC_LINE.findall(doc)
    loop = _REGEN_LOOP.search(doc)
    if not lines or loop is None:
        raise AssertionError(
            "could not read the regenerate block out of this file's own docstring. Either it was "
            "reshaped, or docstrings were stripped (python -OO). Do NOT delete this test to make "
            "that go away: the block is what a person follows by hand, and this is what stops it "
            "drifting from the options the rebuild uses."
        )
    documented = {}
    for src, options, _dest in lines:
        src = src.strip('"')
        if "$f" in src:
            for name in loop.group(1).split():
                documented[name] = options.split()
        else:
            documented[Path(src).stem] = options.split()
    return documented


class EveryStandardHasAWordCopy(unittest.TestCase):
    def test_the_set_is_not_empty(self):
        """A glob that matches nothing would make every case below vacuously true."""
        self.assertGreaterEqual(
            len(published_standards()),
            2,
            "found fewer than two published standards. If they moved, this whole file is now "
            "checking an empty set and passing for the wrong reason.",
        )

    def test_each_markdown_has_a_docx_beside_it(self):
        missing = [p.name for p in published_standards() if not (WORD / (p.stem + ".docx")).exists()]
        self.assertEqual(
            [],
            missing,
            f"published standards with no Word copy: {missing}. Regenerate with the command in this "
            "file's header, or stop offering the Word format for them.",
        )

    def test_no_word_copy_is_an_orphan(self):
        """A .docx whose markdown is gone stays published, and nothing else in this file looks at it.

        Every other case here starts from the markdown and asks whether a Word copy matches it. That
        direction cannot see a file left behind by a rename or a deletion: the source it would have
        been compared against no longer exists, so the copy drops out of the checked set silently
        and goes on being offered, carrying whatever it said the day its source was removed. The
        rename is the likely route -- this repository has already moved a standard once.
        """
        expected = {p.stem for p in published_standards()}
        orphans = sorted(d.name for d in WORD.glob("*.docx") if d.stem not in expected)
        self.assertEqual(
            [],
            orphans,
            f"these Word copies have no markdown source: {orphans}. Nothing regenerates them and "
            "nothing else here checks them, so they are published documents that cannot be "
            "corrected. Delete them, or restore the standard they came from.",
        )

    def test_each_docx_is_real_ooxml_and_not_empty(self):
        broken = []
        for p in published_standards():
            d = WORD / (p.stem + ".docx")
            if not d.exists():
                continue
            try:
                text = docx_text(d)
            except (zipfile.BadZipFile, KeyError) as exc:
                broken.append(f"{d.name}: {type(exc).__name__}")
                continue
            if len(text) < 500:
                broken.append(f"{d.name}: only {len(text)} characters of text")
        self.assertEqual(
            [],
            broken,
            "these Word copies are not readable documents:\n" + "\n".join(broken),
        )


class TheWordCopiesStillMatchTheirSource(unittest.TestCase):
    """The cheap signal, kept although the rebuild below subsumes it.

    It names the drifted SECTION where the rebuild can only name a character offset, it needs no
    converter installed, and a renamed heading is the most common way these files go stale. When
    both fail, read this one first.
    """

    def test_each_docx_carries_its_markdown_title_and_headings(self):
        drifted = []
        for p in published_standards():
            d = WORD / (p.stem + ".docx")
            if not d.exists():
                continue
            md = t.read(p)
            text = docx_text(d)

            title = TITLE.search(md)
            if title and plain(title.group(1)) not in text:
                drifted.append(f"{d.name}: title '{title.group(1)}' is not in the Word copy")

            for heading in HEADING.findall(md):
                words = plain(heading)
                if words and words not in text:
                    drifted.append(f"{d.name}: section '{words}' is not in the Word copy")

        self.assertEqual(
            [],
            drifted,
            "the Word copies have drifted from their markdown:\n"
            + "\n".join(drifted)
            + "\nRegenerate them with the command in this file's header, in the same commit as the "
            "markdown change. A stale Word copy is published rules that no longer hold.",
        )

    def test_the_comparison_can_see_a_drifted_heading(self):
        """Prove the instrument on both sides, without naming a heading that can be renamed.

        An earlier version hardcoded a heading title here and broke the moment that heading was
        reworded -- a self-test that fails on a legitimate edit trains people to ignore it. Take a
        real heading from the markdown instead, so the fixture moves with the document.
        """
        text = docx_text(WORD / "OVERVIEW.docx")
        headings = HEADING.findall(t.read(STANDARDS / "OVERVIEW.md"))
        self.assertTrue(headings, "OVERVIEW.md has no level-2 headings; the scan has nothing to check")
        present = re.sub(r"[`*\[\]]", "", headings[0])
        self.assertIn(present, text, "a heading that IS in the markdown was not found in the Word copy")
        self.assertNotIn("A Section That Does Not Exist", text)


class TheWordCopiesAreWhatTheMarkdownProducesToday(unittest.TestCase):
    """The check that closes the prose hole: rebuild each standard and compare it against the copy.

    The three self-tests below are not padding. Each one edits a document in a way the cheap heading
    scan cannot see -- prose under an unchanged heading, a heading demoted, a link repointed -- and
    asserts BOTH that the words come out identical and that this comparison still goes red. They are
    the evidence that the expensive check earns its cost, kept next to the check rather than in a
    commit message somebody would have to go looking for.
    """

    def test_every_committed_docx_rebuilds_to_the_same_document(self):
        exe = require_pandoc()
        sources = published_standards()
        self.assertGreaterEqual(
            len(sources),
            2,
            "fewer than two published standards were found, so this rebuild would compare almost "
            "nothing and pass. Find out where they went before trusting a green run.",
        )

        drifted = []
        compared = 0
        with tempfile.TemporaryDirectory() as tmp:
            for src in sources:
                committed = WORD / (src.stem + ".docx")
                fresh = build_docx(exe, src, Path(tmp) / (src.stem + ".docx"))
                if not committed.exists():
                    drifted.append(f"{committed.name}: no Word copy is committed at all")
                    continue
                try:
                    have = authored_parts(committed)
                except (zipfile.BadZipFile, KeyError) as exc:
                    drifted.append(f"{committed.name}: not a readable .docx ({type(exc).__name__})")
                    continue
                want = authored_parts(fresh)
                compared += 1
                if want != have:
                    differing = sorted(set(want) | set(have))
                    differing = [p for p in differing if want.get(p) != have.get(p)]
                    drifted.append(
                        f"{committed.name}: {describe_drift(fresh, committed, differing)}\n"
                        f"      rebuild it: {regenerate_command(src)}"
                    )

        # The specific report FIRST. It names the document and the sentence; the count below can only
        # say that something did not happen.
        #
        # `fail` rather than `assertEqual([], drifted, ...)`, which is the idiom everywhere else in
        # this file. The report is multi-line and is the entire product of this test; assertEqual
        # would print it twice -- once as a raw list repr, once as the message -- and cap the first
        # copy with "Diff is N characters long", which reads as though the report were truncated.
        if drifted:
            self.fail(
                f"these committed Word copies are NOT what their markdown produces "
                f"({pandoc_version(exe)}):\n\n"
                + "\n\n".join(drifted)
                + "\n\nRegenerate them in the SAME commit as the markdown change. A stale Word copy "
                "is published rules that no longer hold, and it carries no sign of being out of "
                "date.\nIf EVERY document failed at once, suspect the converter version before the "
                "markdown."
            )

        # RECEIPTS, reached only once nothing has drifted -- which is precisely when a number is
        # needed, because an empty drift list is also what a loop that never ran produces.
        #
        # `compared` counts documents that reached the XML comparison, NOT documents that were
        # rebuilt. An earlier version counted the rebuild, which happens before both `continue` paths
        # above and so could never disagree with the total: an assertion that cannot come out wrong
        # is decoration, and decoration in the shape of a receipt is worse than none.
        self.assertEqual(
            len(sources),
            compared,
            f"only {compared} of {len(sources)} published standards reached the comparison, and yet "
            "nothing was reported as drifted. Some were skipped by a path that does not record "
            "itself, so this green result is a statement about a set nobody chose.",
        )

    def test_the_rebuild_sees_prose_that_moved_under_an_unchanged_heading(self):
        """The hole this class was added to close, pinned open so it cannot quietly return.

        This is the 2026-08-06 failure in miniature: a paragraph is edited, no heading moves, and
        the heading scan above stays green. Both halves are asserted here -- that the old check is
        blind to the edit, and that the rebuild catches it -- so nobody has to take on trust that
        the expensive check earns its cost over the cheap one.

        The mutation is chosen by SHAPE rather than by quoting a sentence, so it moves with the
        document instead of breaking the next time OVERVIEW.md is reworded.
        """
        exe = require_pandoc()
        src = STANDARDS / "OVERVIEW.md"
        original = t.read(src)

        lines = original.split("\n")
        target = first_prose_line(lines)
        lines[target] = lines[target] + " A sentence the committed Word copy has never seen."
        mutated = "\n".join(lines)

        self.assertNotEqual(original, mutated, "the mutation changed nothing; this proves nothing")
        self.assertEqual(
            HEADING.findall(original),
            HEADING.findall(mutated),
            "the mutation moved a heading, so it does not model the failure this test is about",
        )

        committed = docx_text(WORD / "OVERVIEW.docx")

        # HALF ONE: the cheap check is blind to it. Every heading is still present, so the scan in
        # TheWordCopiesStillMatchTheirSource would report no drift for this edit.
        for heading in HEADING.findall(mutated):
            plain = re.sub(r"[`*\[\]]", "", heading)
            if plain:
                self.assertIn(
                    plain,
                    committed,
                    "a heading vanished from the mutant, so this no longer models a prose-only edit",
                )

        # HALF TWO: the rebuild is not.
        _, fresh = rebuild_from_source(exe, mutated, src.name)
        self.assertNotEqual(
            committed,
            fresh,
            "a paragraph was edited under an unchanged heading and the rebuild did not notice. The "
            "comparison is not reading what it thinks it is reading, and the gate above is decorative.",
        )

    def test_the_rebuild_sees_a_heading_demoted_without_its_words_changing(self):
        """A `##` turned into a `###`. Every word survives; the document does not.

        This is why the verdict is taken on XML and not on the visible text. The heading keeps its
        wording, so the extracted text is character-for-character identical -- while the section has
        changed level and dropped out of the table of contents. Both facts are asserted, because the
        first is the entire justification for the second being necessary.
        """
        exe = require_pandoc()
        src = STANDARDS / "OVERVIEW.md"
        original = t.read(src)

        lines = original.split("\n")
        index = next((i for i, line in enumerate(lines) if re.match(r"^##\s+\S", line)), None)
        self.assertIsNotNone(index, "OVERVIEW.md has no level-2 heading to demote")
        lines[index] = "#" + lines[index]
        mutated = "\n".join(lines)

        parts, text = rebuild_from_source(exe, mutated, src.name)
        self.assertEqual(
            docx_text(WORD / "OVERVIEW.docx"),
            text,
            "demoting a heading changed the visible TEXT. That is a better outcome than this test "
            "expects, but the reasoning in this file's header is now wrong and should be corrected.",
        )
        self.assertNotEqual(
            authored_parts(WORD / "OVERVIEW.docx"),
            parts,
            "a heading changed level and the comparison saw nothing. It has fallen back to comparing "
            "words, and every structural edit is now invisible to this suite.",
        )

    def test_the_rebuild_sees_a_link_repointed_under_unchanged_anchor_text(self):
        """A URL changed, the words around it untouched.

        The one a text comparison cannot reach at all: the target is not in the body, so no amount
        of reading the words will find it. A published document that sends readers to a page that
        has moved is the same failure as one that states a rule that has changed.
        """
        exe = require_pandoc()
        src = STANDARDS / "OVERVIEW.md"
        original = t.read(src)

        link = re.search(r"\]\((https?://[^)\s]+)\)", original)
        self.assertIsNotNone(link, "OVERVIEW.md has no external link, so this models nothing")
        mutated = original.replace(link.group(1), "https://example.invalid/moved", 1)
        self.assertNotEqual(original, mutated, "the link rewrite changed nothing")

        parts, text = rebuild_from_source(exe, mutated, src.name)
        self.assertEqual(
            docx_text(WORD / "OVERVIEW.docx"),
            text,
            "repointing a link changed the visible TEXT, so pandoc now renders URLs as words. Better "
            "than expected, but this file's stated reason for reading the relationship parts is no "
            "longer the whole truth and should be corrected.",
        )
        self.assertNotEqual(
            authored_parts(WORD / "OVERVIEW.docx"),
            parts,
            "a link was repointed and the comparison saw nothing. The relationship parts have "
            "dropped out of it, and every URL in every published Word copy is now unchecked.",
        )

    def test_an_unedited_standard_rebuilds_identically_from_anywhere(self):
        """The other half of the instrument: it must not cry drift over its own machinery.

        A check that fails on a correct file is worse than none, because the fix people reach for is
        to delete it. The mutant tests prove it can see an edit; this proves that what it sees is
        the edit and not the temporary directory, the working directory, or the copy.
        """
        exe = require_pandoc()
        src = STANDARDS / "OVERVIEW.md"
        parts, _ = rebuild_from_source(exe, t.read(src), src.name)
        self.assertEqual(
            authored_parts(WORD / "OVERVIEW.docx"),
            parts,
            "an UNEDITED standard rebuilt to different XML. Until that is understood, every other "
            "failure in this class is suspect: the comparison is sensitive to something other than "
            "the document. Check the pandoc version first.",
        )


class TheRecipeIsTheOneThisFileRuns(unittest.TestCase):
    """The regenerate block in the header is followed by hand. Pin it to what the tests build with.

    If the two disagree, a person regenerates exactly as documented and the suite rejects the result
    -- a gate that cannot be satisfied by following its own instructions, which is the kind nobody
    trusts twice.
    """

    def test_the_regenerate_block_covers_every_published_standard(self):
        documented = set(documented_builds())
        published = {p.stem for p in published_standards()}
        self.assertEqual(
            published,
            documented,
            f"the regenerate block and the published set disagree.\n"
            f"  published but not in the block: {sorted(published - documented)}\n"
            f"  in the block but not published: {sorted(documented - published)}\n"
            "A standard missing from the block is one a bulk regeneration silently skips, which is "
            "how a Word copy goes stale while everything around it is rebuilt.",
        )

    def test_the_documented_options_are_the_options_the_rebuild_uses(self):
        wrong = []
        for stem, options in sorted(documented_builds().items()):
            expected = pandoc_options(stem)
            if options != expected:
                wrong.append(f"{stem}: block says {options}, the rebuild uses {expected}")
        self.assertEqual(
            [],
            wrong,
            "the regenerate block no longer matches how these tests build:\n"
            + "\n".join(wrong)
            + "\nFix whichever is wrong. Leaving them apart means following the documented command "
            "produces a file this suite then calls drifted.",
        )

    def test_the_no_toc_exception_still_names_a_real_standard(self):
        """An exception for a file that no longer exists is a rule with nothing under it."""
        published = {p.stem for p in published_standards()}
        self.assertEqual(
            set(),
            NO_TOC - published,
            f"NO_TOC names {sorted(NO_TOC - published)}, which is not a published standard any "
            "more. Either it was renamed -- in which case its replacement is now being built WITH a "
            "table of contents nobody asked for -- or the exception should go.",
        )


if __name__ == "__main__":
    unittest.main()
