"""Pin the generated Word copies against the markdown they came from.

THE FAILURE THIS EXISTS FOR. `docs/standards/word/*.docx` are GENERATED from the sibling markdown.
Nothing regenerates them automatically, so every edit to a standard silently leaves a stale Word
copy published beside a current markdown one, and a reader who took the Word file gets last week's
rules with no indication of it. It already happened once inside a single session: a section was
renamed and the Word copies kept the old name until they were rebuilt.

REGENERATE WITH (from docs/standards/, needs pandoc):

    for f in OVERVIEW CODE-QUALITY SECURE-DEVELOPMENT AI-ASSISTED-DEVELOPMENT DEPENDENCY-INTEGRITY REVIEW-DEPTH ADOPTING-THESE WHICH-STANDARDS-APPLY STANDARDS-LANDSCAPE STANDARDS-REFERENCE CI-ENFORCEMENT DILIGENCE-PACKET; do
      pandoc "$f.md" -f gfm -t docx --toc --toc-depth=2 -o "word/$f.docx"
    done
    # CISO-SUMMARY is the exception: no --toc. It is a two-page document, and a table of contents
    # on it costs a whole page to list six headings the reader can already see.
    pandoc CISO-SUMMARY.md -f gfm -t docx -o word/CISO-SUMMARY.docx
    # And the assessment method, which lives one directory up:
    pandoc ../ASVS-ASSESSMENT.md -f gfm -t docx --toc --toc-depth=2 -o word/ASVS-ASSESSMENT.docx

WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves a Word copy EXISTS for every published standard,
that each is real OOXML rather than a truncated or empty file, and that its text still carries the
markdown's own title and its section headings -- which catches a rename, a dropped section, and a
conversion that silently produced nothing. It does NOT prove the two are equal: prose edited inside
a section that keeps its heading will not be caught here, and no cheap check catches that without
re-running the converter. Treat a pass as "the Word copy is the same document", not "the Word copy
is current to the byte". If you changed a standard, regenerate rather than relying on this.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import html
import re
import unittest
import zipfile

import _ccxtest as t

STANDARDS = t.REPO_ROOT / "docs" / "standards"
WORD = STANDARDS / "word"

HEADING = re.compile(r"^##\s+(.+?)\s*$", re.M)
TITLE = re.compile(r"^#\s+(.+?)\s*$", re.M)


def docx_text(path) -> str:
    """The document's visible text, tags stripped. Raises if it is not a readable .docx."""
    with zipfile.ZipFile(path) as z:
        xml = z.read("word/document.xml").decode("utf-8", "ignore")
    # Word splits a sentence across runs, so strip tags and collapse whitespace before matching.
    text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", xml))
    # UNESCAPE, or this scan reports drift that is not there. An apostrophe is stored as the entity
    # `&#39;`, so a heading containing one never matches its markdown source and every document with
    # a possessive in a heading looks stale. Found exactly that way, on the first run.
    return html.unescape(text)


def published_standards() -> list:
    """Every markdown file offered with a Word copy beside it.

    ASVS-ASSESSMENT.md lives in docs/ rather than docs/standards/, because it predates the standards
    section. It is offered in the same download table and generated into the same word/ directory,
    so it is pinned here too -- a generated file nothing checks is the drift this file exists for.
    """
    extra = t.REPO_ROOT / "docs" / "ASVS-ASSESSMENT.md"
    return sorted(STANDARDS.glob("*.md")) + ([extra] if extra.exists() else [])


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
    def test_each_docx_carries_its_markdown_title_and_headings(self):
        drifted = []
        for p in published_standards():
            d = WORD / (p.stem + ".docx")
            if not d.exists():
                continue
            md = t.read(p)
            text = docx_text(d)

            title = TITLE.search(md)
            if title and title.group(1) not in text:
                drifted.append(f"{d.name}: title '{title.group(1)}' is not in the Word copy")

            for heading in HEADING.findall(md):
                # Headings carrying inline code or links render differently; compare on the words.
                plain = re.sub(r"[`*\[\]]", "", heading)
                if plain and plain not in text:
                    drifted.append(f"{d.name}: section '{plain}' is not in the Word copy")

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


if __name__ == "__main__":
    unittest.main()
