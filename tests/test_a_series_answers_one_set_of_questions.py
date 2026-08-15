"""HS-21: every page in the framework series answers the same questions in the same order.

THE FAILURE THIS EXISTS FOR, and it is the reason the rule was written before the second page rather
than after. docs/FRAMEWORK-spec-kit.md took its section order from the source material it was
written from. That is invisible while there is one page: nothing to compare it against, and every
section reads as though it were chosen. The cost only appears when a second page arrives answering a
different set of questions in a different order, at which point the series is a pile rather than a
series -- and by then the first page has been read, linked and indexed, so the fix is a rename with
inbound anchors pointing at it.

WHAT THIS PINS, AND WHAT IT DELIBERATELY DOES NOT. It pins that every `docs/FRAMEWORK-*.md` carries
every section in `_ccxtest.FRAMEWORK_SECTIONS`, in that relative order. It does NOT pin that those
are the only sections: a page may open with `## TLDR/BLUF`, may add `## How the claims were graded`
where it has a grading scheme to explain, and may carry any number of `###` subsections underneath.
Extra sections are an editorial choice. A missing one is a claim.

WHY A MISSING SECTION IS A CLAIM. "How it holds state" absent from a framework page does not read as
"nobody looked". It reads as "this framework has no interesting state", which is the assertion the
Spec Kit page exists to disprove about Spec Kit. A section carrying "not established" costs three
lines and says the true thing. That asymmetry is the whole rule.

THE ORDER LIVES IN _ccxtest.py AND NOWHERE ELSE. docs/HOUSE-STYLE.md states HS-21 and cites this
file; docs/_data/nav.yml carries the list as a note for whoever adds the next page. The last case
below asserts that note has not drifted from the constant, because a note that disagrees with the
gate is worse than no note -- the person reading it is the person about to write the page.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import re
import subprocess
import unittest

import _ccxtest as t

ATX_HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")


def tracked_files() -> list[str]:
    """Every path git is tracking, as forward-slash repo-relative strings."""
    out = subprocess.run(
        ["git", "ls-files"],
        cwd=t.REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def series_pages() -> list[str]:
    """Every page in the framework series."""
    return sorted(
        f
        for f in tracked_files()
        if f.startswith("docs/FRAMEWORK-") and f.endswith(".md")
    )


def top_level_headings(text: str) -> list[str]:
    """Every `## ` heading, in document order, ignoring fenced blocks.

    Fences are skipped for the reason test_internal_links_resolve.py records about links: a page
    that DOCUMENTS a section layout has to write one, and a scan that cannot tell a heading from a
    line of sample markdown reports the sample.
    """
    out: list[str] = []
    inside = False
    for line in text.split("\n"):
        if FENCE.match(line):
            inside = not inside
            continue
        if inside:
            continue
        m = ATX_HEADING.match(line)
        if m is not None and len(m.group(1)) == 2:
            out.append(m.group(2).strip())
    return out


def missing_and_misordered(headings: list[str]) -> tuple[list[str], str | None]:
    """Which required sections are absent, and the first one that is out of order."""
    missing = [s for s in t.FRAMEWORK_SECTIONS if s not in headings]
    if missing:
        return missing, None
    present = [h for h in headings if h in t.FRAMEWORK_SECTIONS]
    for got, want in zip(present, t.FRAMEWORK_SECTIONS):
        if got != want:
            return [], f"{got!r} appears where {want!r} was expected"
    return [], None


class EverySeriesPageAnswersTheSameQuestions(unittest.TestCase):
    def test_the_scan_actually_finds_the_series(self):
        """The empty-match guard. Every assertion below passes trivially over an empty list.

        This is the failure shape the repository keeps rediscovering: a scan for a property that
        matches no files reports success while measuring nothing. If the series is genuinely gone,
        delete this file rather than leaving it to certify an empty set.
        """
        pages = series_pages()
        self.assertGreaterEqual(
            len(pages),
            2,
            f"found {len(pages)} pages matching docs/FRAMEWORK-*.md. HS-21 is a rule about a "
            "SERIES, and a series of one cannot be inconsistent -- so below two pages this file "
            "proves nothing. Either the pages were renamed out of the pattern, or the second one "
            "was never added with `git add`.",
        )

    def test_every_page_carries_every_section_in_order(self):
        offenders = []
        for relpath in series_pages():
            headings = top_level_headings(t.read(t.REPO_ROOT / relpath))
            missing, misordered = missing_and_misordered(headings)
            if missing:
                offenders.append(f"{relpath}: missing {missing}")
            if misordered:
                offenders.append(f"{relpath}: {misordered}")
        self.assertEqual(
            [],
            offenders,
            "HS-21: a page in the framework series does not answer the series' questions in the "
            "series' order:\n  "
            + "\n  ".join(offenders)
            + "\nThe order is tests/_ccxtest.py FRAMEWORK_SECTIONS. Extra sections are fine; a "
            "MISSING one is not, because an absent section reads as 'this framework has no such "
            "property' rather than as 'nobody established it'. Add the section and write "
            "'not established' in it.",
        )

    def test_an_extra_section_is_allowed(self):
        """Planted. Without this the case above could be tightened into an equality check, which
        would redden a page for opening with a summary section every other page here also has."""
        headings = ["TLDR/BLUF", "How the claims were graded", *t.FRAMEWORK_SECTIONS]
        self.assertEqual(([], None), missing_and_misordered(headings))

    def test_a_missing_section_is_reported(self):
        """Planted, because the corpus is green and cannot demonstrate the failure."""
        headings = [h for h in t.FRAMEWORK_SECTIONS if h != "How it holds state"]
        missing, _ = missing_and_misordered(headings)
        self.assertEqual(["How it holds state"], missing)

    def test_a_reordered_section_is_reported(self):
        """The half a presence check cannot see. Both pages could carry all nine and still not be
        comparable, which is the defect this rule is actually about."""
        swapped = list(t.FRAMEWORK_SECTIONS)
        swapped[1], swapped[3] = swapped[3], swapped[1]
        missing, misordered = missing_and_misordered(swapped)
        self.assertEqual([], missing, "the planted case must be a REORDER, not a deletion")
        self.assertIsNotNone(
            misordered,
            "a page carrying every section in the wrong order was accepted, so this file checks "
            "presence and calls it order.",
        )

    def test_a_heading_inside_a_code_fence_is_not_counted(self):
        """A page documenting this layout has to write it. Counting the sample would redden it."""
        text = "## What it is, measured\n\n```\n## How it holds state\n```\n"
        self.assertEqual(["What it is, measured"], top_level_headings(text))

    def test_only_level_two_headings_count(self):
        """`### Feature state is a file, not a branch` sits UNDER `## How it holds state` on the
        Spec Kit page, so the specific finding survives the canonical heading. A scan that counted
        every level would read that subsection as a tenth question."""
        text = "## How it holds state\n### Feature state is a file, not a branch\n# Title\n"
        self.assertEqual(["How it holds state"], top_level_headings(text))


class TheNoteAndTheGateAgree(unittest.TestCase):
    """docs/_data/nav.yml tells the next author what the order is. Pin that it is still true.

    The note is read by exactly the person about to write a page against it, so a note that has
    drifted from the constant is worse than no note at all: it is wrong at the only moment anyone
    consults it. This is the same shape as OPEN-8, where docs/HOUSE-STYLE.md must name the file
    tests/_ccxtest.py exempts.
    """

    NAV = t.REPO_ROOT / "docs" / "_data" / "nav.yml"

    def test_the_nav_note_names_every_section_the_gate_requires(self):
        note = t.read(self.NAV)
        missing = [s for s in t.FRAMEWORK_SECTIONS if s not in note]
        self.assertEqual(
            [],
            missing,
            f"docs/_data/nav.yml no longer names {missing}. That comment block is what the next "
            "person adding a FRAMEWORK-*.md page reads before writing it, so it has to carry the "
            "same list this file enforces. Update the note in the same commit as the constant.",
        )

    def test_the_house_style_cites_this_file(self):
        """HS-12 wants an evidence column, and HS-21's evidence is this gate. If the citation goes,
        the rule becomes a claim about the corpus that nothing checks -- which is the condition
        docs/HOUSE-STYLE.md records PD-8 was written for."""
        house_style = t.read(t.REPO_ROOT / "docs" / "HOUSE-STYLE.md")
        self.assertIn(
            "test_a_series_answers_one_set_of_questions.py",
            house_style,
            "docs/HOUSE-STYLE.md states HS-21 without citing the test that enforces it. Either "
            "restore the citation or retire the rule; a normative rule whose evidence column names "
            "nothing is the shape this repository exists to refuse.",
        )


if __name__ == "__main__":
    unittest.main()
