"""HS-23: the landing page routes the reader, and the pages it routes to still hold the content.

THE FAILURE THIS EXISTS FOR, measured on 2026-08-16 rather than imagined. docs/index.md had grown to
3,143 words. It carried the install procedure, the requirements table, the vendor-surface limits and
a 40-row inventory of every script the project ships. No sentence on it was wrong.

The defect was ORDERING, and nothing could see it. Each of those sections arrived on the landing page
for the same good reason -- it was the page everyone read -- and each was correct on arrival. A
developer trying to decide whether to try this met the caveats before the commands, and met the first
command 68% of the way down. Every gate in this repository was green throughout, because every gate
here asks whether a statement is true and none of them asks whether it is findable.

WHY A CAP RATHER THAN A BAN ON DETAIL. Detail is not the defect and `PD` outranks this rule: the fix
for an over-long landing page is always to move a fact to the page that owns it, never to delete it.
So the cap is paired below with a check that the receiving pages still carry what they received. A
landing page trimmed by deletion satisfies the first case and fails the second, which is the whole
reason the second one exists.

THE CAP IS A RATCHET AND IT IS NOT TIGHT. 1,119 words on the day it was written, against a cap of
1,400. The headroom is deliberate: a rule that reddens on one added paragraph is a rule people route
around, and this one is trying to catch a page doubling rather than a page growing.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

LANDING = t.REPO_ROOT / "docs" / "index.md"

# The pages the landing page split into on 2026-08-16, and the content each one received.
QUICKSTART = t.REPO_ROOT / "docs" / "QUICKSTART.md"
LIMITS = t.REPO_ROOT / "docs" / "LIMITS.md"
SCRIPTS = t.REPO_ROOT / "docs" / "SCRIPTS.md"

# Measured at 1,119 words on the day the rule was written. See the module docstring for why the
# headroom is this wide.
WORD_CAP = 1_400

# How far into the page the route to the first command has to appear. The opening is three labelled
# paragraphs, so this reaches the end of them and no further.
OPENING_CHARS = 1_200

# A row of the script inventory: a table cell naming a shipped script by path. Matching the PATH
# rather than the word "script" is what keeps this from firing on prose that mentions one.
INVENTORY_ROW = re.compile(r"^\|[^|]*`(?:scripts|bin)/[\w./-]+`", re.M)

# A raw HTML block. Same rule tests/test_prose_rules_hold.py uses, and for the same reason: a hand
# written inline SVG is markup, and a scanner that cannot tell markup from prose counts its
# coordinates, its marker ids and its aria-label as words. The landing page's collision diagram is
# about 400 such tokens, which is a third of the cap below -- so counting them would price a diagram
# out of the one page that most wants one, which is the opposite of what this rule is for.
#
# kramdown's rule: a line starting with '<' opens a markup block that runs to the next blank line.
HTML_BLOCK_START = re.compile(r"^<[a-zA-Z!/]")


def prose_words(text: str) -> int:
    """Words on the page that a reader actually reads. Markup blocks do not count."""
    words = 0
    inside_html = False
    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped:
            inside_html = False
            continue
        if inside_html:
            continue
        if HTML_BLOCK_START.match(stripped):
            inside_html = True
            continue
        words += len(stripped.split())
    return words

# The landing page legitimately names a few scripts: three of them, in the table that says which
# mechanism prevents, repairs and detects the flagship failure. The inventory it must not carry
# again is 40 rows long, so the threshold sits well above the one and well below the other.
INVENTORY_ROWS_ALLOWED = 8


class TheLandingPageRoutesRatherThanExplains(unittest.TestCase):
    def test_the_scan_actually_read_the_page(self):
        """The empty-match guard. Every case below passes trivially against an empty file."""
        words = prose_words(t.read(LANDING))
        self.assertGreater(
            words,
            200,
            f"docs/index.md is {words} words. Either the landing page was emptied, or this file is "
            "reading the wrong path -- and both of those pass the cap below while proving nothing.",
        )

    def test_the_landing_page_is_under_the_cap(self):
        words = prose_words(t.read(LANDING))
        self.assertLessEqual(
            words,
            WORD_CAP,
            f"docs/index.md is {words} words, against a cap of {WORD_CAP} (HS-23). It reached 3,143 "
            "before the rule existed, one correct section at a time. Move whatever grew to the page "
            "that owns it -- QUICKSTART.md, LIMITS.md or SCRIPTS.md -- and link to it. PD-1 to PD-7 "
            "outrank this rule: never reach the number by deleting a fact.",
        )

    def test_the_opening_names_the_page_carrying_the_first_command(self):
        opening = t.read(LANDING)[:OPENING_CHARS]
        self.assertIn(
            "QUICKSTART.md",
            opening,
            f"the first {OPENING_CHARS} characters of docs/index.md do not link to QUICKSTART.md. A "
            "reader deciding whether to try this needs the route to the first command inside the "
            "opening, which is the half of HS-23 that a word count cannot see.",
        )

    def test_the_landing_page_carries_no_script_inventory(self):
        rows = INVENTORY_ROW.findall(t.read(LANDING))
        self.assertLessEqual(
            len(rows),
            INVENTORY_ROWS_ALLOWED,
            f"docs/index.md names {len(rows)} shipped scripts in table rows, against "
            f"{INVENTORY_ROWS_ALLOWED} allowed. The inventory belongs on SCRIPTS.md, which serves it "
            "grouped by what the reader is trying to do:\n  " + "\n  ".join(rows),
        )


class TheReceivingPagesStillCarryWhatTheyReceived(unittest.TestCase):
    """The half that stops the cap being satisfied by deletion.

    A landing page trimmed by moving content passes both classes. One trimmed by deleting content
    passes the class above and fails this one, which is the only difference that matters and is
    invisible to a word count.
    """

    def test_the_limits_page_carries_the_requirements(self):
        text = t.read(LIMITS)
        for token in ("PowerShell 7.3+", "ccx.config.json", "CCX_PYTHON"):
            self.assertIn(
                token,
                text,
                f"docs/LIMITS.md no longer states {token!r}. It received the requirements table from "
                "the landing page; if the table moved again, move this check with it rather than "
                "dropping it -- a requirement nobody states is one the reader discovers by failing.",
            )

    def test_the_scripts_page_carries_the_inventory(self):
        rows = INVENTORY_ROW.findall(t.read(SCRIPTS))
        self.assertGreaterEqual(
            len(rows),
            25,
            f"docs/SCRIPTS.md lists {len(rows)} shipped scripts. It received a 40-row inventory from "
            "the landing page, so a number this low means rows were lost in the move rather than "
            "relocated by it.",
        )

    def test_the_quickstart_is_reachable_from_the_pages_that_replaced_the_old_route(self):
        """Every page that took content off the landing page has to hand the reader onward.

        Without this the split is three dead ends: a reader who lands on LIMITS.md from a search
        result has read the caveats and has no route to the commands they are caveats about.
        """
        for page in (LIMITS, SCRIPTS):
            self.assertIn(
                "QUICKSTART.md",
                t.read(page),
                f"docs/{page.name} does not link to QUICKSTART.md. It carries content a reader meets "
                "before they have installed anything, so it owes them the route onward.",
            )


class TheInventoryPatternCanTellARowFromAMention(unittest.TestCase):
    """Planted. A pattern that matches nothing satisfies the cap and the floor at the same time."""

    def test_it_matches_a_real_inventory_row(self):
        row = "| `scripts/coord/claim.ps1` | Take, release or list a claim | [Coordination](x.md) |"
        self.assertEqual(1, len(INVENTORY_ROW.findall(row)))

    def test_it_matches_a_bin_row(self):
        self.assertEqual(1, len(INVENTORY_ROW.findall("| `bin/ccx-doctor.ps1` | Prove it | [x](y) |")))

    def test_it_declines_a_script_named_in_prose(self):
        prose = "The reaper is `scripts/worktree/prune-merged.ps1`, and it declines rather than guessing."
        self.assertEqual([], INVENTORY_ROW.findall(prose))

    def test_prose_words_ignores_a_markup_block_and_keeps_the_prose_around_it(self):
        """The other instrument, planted for the same reason.

        Without this, a `prose_words` that counted markup would silently price the landing page's
        diagram against the cap, and one that counted nothing at all would pass the cap forever.
        """
        page = (
            "Prose before the diagram.\n"
            "\n"
            "<figure role=\"group\">\n"
            "<svg viewBox=\"0 0 10 10\" role=\"img\" aria-label=\"lots of words in here\">\n"
            "  <text x=\"1\" y=\"1\">label</text>\n"
            "</svg>\n"
            "<figcaption>Caption words that are also markup.</figcaption>\n"
            "</figure>\n"
            "\n"
            "Prose after the diagram.\n"
        )
        self.assertEqual(8, prose_words(page))

    def test_prose_words_resumes_after_a_blank_line_inside_a_figure(self):
        """kramdown ends a markup block at a blank line, so the rule has to as well.

        A figure written with a blank line in it is still markup on the next line, and the next line
        starts with '<'. What must NOT happen is prose after the figure being swallowed.
        """
        page = "<svg>\n<text>x</text>\n\nStill prose here.\n"
        self.assertEqual(3, prose_words(page))

    def test_it_declines_a_table_row_that_names_no_script(self):
        self.assertEqual([], INVENTORY_ROW.findall("| **Prevention** | Refuses the git verbs | x |"))


if __name__ == "__main__":
    unittest.main()
