"""The rule that replaced the no-script rule, gated so it is a control rather than a comment.

WHAT CHANGED. Until 2026-08-16 this site ran no script at all, by a rule written into
docs/assets/style.css: a feature got a script only when "the answer it presents is complete before
any script runs". The owner retired that rule. What it was costing had been measured by then -- six
independent reviews of the live site each asked for copy buttons on the command blocks and a
collapsing nav on a phone, and the rule was the whole reason neither existed.

WHAT SURVIVED IT, and this file is that half:

  1. EVERY PAGE STILL WORKS WITH SCRIPT DISABLED. Script may ENHANCE what is already served. It may
     not be the only route to a link, a heading, a command or an answer.
  2. SAME ORIGIN ONLY. No CDN, no third-party host. That was never part of the script rule: it is
     the firewall in front of this site's readers, which blocks GitHub and friends wholesale.

THE MECHANISM THAT MAKES (1) TRUE IS WHERE THE CONTROLS COME FROM. Every control the script adds is
CREATED by the script -- the copy button, the search box, the nav toggle. So a reader with script
disabled meets no button that does nothing, no empty search box, and no collapsed nav that will not
open. They meet the page as it was.

THE FAILURE THIS EXISTS FOR IS THE OBVIOUS NEXT EDIT. Someone adds `<button class="copy-button">` to
the layout because putting it in the markup is simpler than creating it in JavaScript, and every
check in this repository stays green: the site builds, the links resolve, the prose passes. The only
reader who can see the defect is the one with script disabled, who now has a button that does
nothing -- and nobody is testing with script disabled.

WHAT THIS DOES NOT CHECK, stated rather than left to be discovered: it does not run the script, and
it does not open a browser. It reads source. It cannot tell you the copy button works; it can tell
you the copy button is not in the HTML, which is the property (1) actually rests on.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

SCRIPT = t.REPO_ROOT / "docs" / "assets" / "site.js"
STYLESHEET = t.REPO_ROOT / "docs" / "assets" / "style.css"
LAYOUTS = sorted((t.REPO_ROOT / "docs" / "_layouts").glob("*.html"))

# Every class the script attaches to something it created. Each one is a control that must not be
# reachable in the served HTML, because the served HTML is what a reader without script gets.
ENHANCEMENT_CLASSES = (
    "code-wrap",
    "copy-button",
    "nav-toggle",
    "nav-search",
    "nav-search-input",
    "nav-search-results",
    "is-collapsed",
)

# A `<script src=...>` in a layout. The `src` is what has to be same-origin.
SCRIPT_TAG = re.compile(r"<script\b[^>]*\bsrc=\"([^\"]+)\"[^>]*>")

# Liquid's own comment tag. Stripped before any scan of a template, for the reason
# tests/_ccxtest.py records about `strip_ps_comments`: a document that EXPLAINS why it does not use
# a construction has to be able to name it. The first version of the slugify case below fired on
# docs/search.json's own header, which is a paragraph about why no slug is computed there.
LIQUID_COMMENT = re.compile(r"\{%-?\s*comment\s*-?%\}.*?\{%-?\s*endcomment\s*-?%\}", re.S)


def liquid_source(text: str) -> str:
    """A Liquid template with its comments removed -- what the template actually does."""
    return LIQUID_COMMENT.sub("", text)


class ScriptOnlyEnhancesWhatIsAlreadyServed(unittest.TestCase):
    def test_the_script_exists_and_this_file_is_reading_it(self):
        """The empty-match guard. Every case below passes trivially against a missing file."""
        self.assertTrue(SCRIPT.exists(), f"{SCRIPT} is gone. Delete this file or fix the path.")
        text = t.read(SCRIPT)
        self.assertGreater(
            len(text),
            500,
            "docs/assets/site.js is too short to be the enhancement layer. If the script was "
            "removed deliberately, delete this test rather than leaving it to certify nothing.",
        )

    def test_no_layout_ships_a_control_the_script_is_supposed_to_create(self):
        offenders = []
        for layout in LAYOUTS:
            text = t.read(layout)
            for cls in ENHANCEMENT_CLASSES:
                if cls in text:
                    offenders.append(f"{layout.name}: {cls}")
        self.assertEqual(
            [],
            offenders,
            "these controls are in the served HTML, and assets/site.js is supposed to create "
            "them:\n  "
            + "\n  ".join(offenders)
            + "\nA reader with script disabled now meets a control that does nothing. Create it in "
            "site.js instead -- that is the whole of what replaced the no-script rule.",
        )

    def test_the_script_actually_creates_each_of_them(self):
        """The other direction. A class styled and gated but created by nothing is dead CSS."""
        text = t.read(SCRIPT)
        missing = [cls for cls in ENHANCEMENT_CLASSES if cls not in text]
        self.assertEqual(
            [],
            missing,
            f"assets/site.js never names {missing}, so nothing creates them. Either the feature was "
            "removed -- in which case drop the class from ENHANCEMENT_CLASSES and from the "
            "stylesheet -- or it was renamed and this list did not follow.",
        )

    def test_the_stylesheet_styles_each_of_them(self):
        """A control created with no styling is the same defect pointing the other way."""
        css = t.read(STYLESHEET)
        unstyled = [cls for cls in ENHANCEMENT_CLASSES if f".{cls}" not in css]
        self.assertEqual(
            [],
            unstyled,
            f"assets/style.css carries no rule for {unstyled}. The script creates them and nothing "
            "styles them, so they render as unstyled markup dropped into the page.",
        )

    def test_every_script_this_site_loads_is_same_origin(self):
        """The constraint that predates the script rule and outlived it.

        The readers this site is written for sit behind a firewall that blocks GitHub wholesale, so
        a CDN is not a convenience here -- it is a script that never loads, on a page that then
        looks broken in a way nothing on this machine can reproduce.
        """
        offenders = []
        seen = 0
        for layout in LAYOUTS:
            for src in SCRIPT_TAG.findall(t.read(layout)):
                seen += 1
                if "//" in src or src.startswith("http"):
                    offenders.append(f"{layout.name}: {src}")
        self.assertGreater(
            seen,
            0,
            "no <script src=...> found in any layout. If the script was removed, delete this file; "
            "if the tag was reshaped, fix the pattern -- it currently pins nothing.",
        )
        self.assertEqual(
            [],
            offenders,
            "these script tags name another host:\n  "
            + "\n  ".join(offenders)
            + "\nServe it from this origin. The firewall in front of this site's readers blocks "
            "third-party hosts, and a script that never loads leaves a page that looks broken.",
        )

    def test_the_script_is_deferred(self):
        """It enhances content that is already complete, so it has no business blocking the parse."""
        undeferred = []
        for layout in LAYOUTS:
            for tag in re.findall(r"<script\b[^>]*>", t.read(layout)):
                if "src=" in tag and "defer" not in tag and "async" not in tag:
                    undeferred.append(f"{layout.name}: {tag}")
        self.assertEqual(
            [],
            undeferred,
            "these script tags block the parser:\n  "
            + "\n  ".join(undeferred)
            + "\nEverything this script does is an enhancement over HTML that is already complete, "
            "so it can wait. Add `defer`.",
        )


class AnExampleNobodyShouldRunCarriesNoCopyButton(unittest.TestCase):
    """The copy button is an instruction to run something, so it must not appear on an illustration.

    THE CASE THIS EXISTS FOR IS ON THE LANDING PAGE. Its first code block is
    `git checkout -B feature/parser origin/main` -- the command that CAUSES the failure the entire
    site is about, quoted so a reader can recognise it. The copy button shipped on it, which turned
    the site's own worked example of the defect into a one-click invitation to reproduce it.

    THE MARKER IS AN HTML COMMENT rather than kramdown's `{: .no-copy}`, because these pages are read
    on github.com as well: a comment renders as nothing there, and an IAL renders as literal text in
    the middle of the document.
    """

    MARKER = "<!-- no-copy -->"

    # The block, and the page it is on. Named rather than pattern-matched: this is a short list of
    # specific illustrations, and a pattern would quietly stop covering the one that matters.
    MUST_BE_MARKED = (
        ("docs/index.md", "git checkout -B feature/parser origin/main"),
        ("docs/TIPS-AND-TRICKS.md", "# WRONG - $? is tail's"),
        ("docs/QUICKSTART.md", "service.py has UNCOMMITTED changes"),
    )

    def test_each_illustration_is_marked(self):
        offenders = []
        for relpath, needle in self.MUST_BE_MARKED:
            lines = t.read(t.REPO_ROOT / relpath).split("\n")
            hit = next((i for i, line in enumerate(lines) if needle in line), None)
            if hit is None:
                offenders.append(f"{relpath}: no line containing {needle!r} -- did the example move?")
                continue
            # Walk back to the fence that opens the block, then check the line above it.
            fence = next((i for i in range(hit, -1, -1) if lines[i].lstrip().startswith("```")), None)
            if fence is None or fence == 0 or self.MARKER not in lines[fence - 1]:
                offenders.append(f"{relpath}:{hit + 1}: {needle!r} is in an unmarked code block")
        self.assertEqual(
            [],
            offenders,
            "these blocks are illustrations, and without the marker assets/site.js puts a Copy "
            "button on them:\n  "
            + "\n  ".join(offenders)
            + f"\nPut `{self.MARKER}` on the line immediately above the opening fence. The landing "
            "page one is the important one: it is the command that causes the failure this site "
            "exists to prevent, and a Copy button on it invites the reader to run exactly that.",
        )

    def test_the_script_honours_the_marker(self):
        """The other half. The marker is inert unless site.js reads it."""
        js = t.read(SCRIPT)
        self.assertIn(
            "no-copy",
            js,
            "assets/site.js no longer looks for the no-copy marker, so every marked illustration "
            "has a Copy button again and the markers are decoration.",
        )
        self.assertIn(
            "isMarkedNoCopy",
            js,
            "the marker check was renamed or removed. If copy buttons are now decided another way, "
            "point this test at it rather than deleting the case.",
        )


class TheSearchIndexIsBuiltRatherThanFetchedFromAnyoneElse(unittest.TestCase):
    """The search box is the one feature that loads data, so it is the one worth pinning."""

    INDEX = t.REPO_ROOT / "docs" / "search.json"

    def test_the_index_is_generated_by_this_site(self):
        self.assertTrue(
            self.INDEX.exists(),
            "docs/search.json is gone and assets/site.js still fetches it, so the search box "
            "returns nothing on every query while looking perfectly healthy.",
        )
        text = t.read(self.INDEX)
        self.assertIn(
            "site.pages",
            text,
            "docs/search.json no longer builds from site.pages, so it is a hand-maintained list of "
            "the pages -- which is the drift every other check in this suite exists to refuse.",
        )

    def test_the_index_computes_no_heading_anchors(self):
        """The refusal recorded in the index's own header, kept honest.

        An anchor computed by Liquid's `slugify` and an anchor rendered by kramdown disagree on any
        heading containing `--`: 19 of 766 measured, in test_internal_links_resolve.py. A search
        result carrying the wrong slug still returns 200 and still renders -- it lands the reader at
        the top of the page while promising a section, reported by nobody.
        """
        self.assertNotIn(
            "slugify",
            liquid_source(t.read(self.INDEX)),
            "docs/search.json computes a slug. Liquid's slugifier and kramdown's disagree on any "
            "heading containing `--`, so the anchors it produces are silently wrong for exactly "
            "the headings this corpus has most of. Index pages, not headings.",
        )

    def test_the_comment_stripper_tells_a_mention_from_a_use(self):
        """Planted. Without it the case above passes against a stripper that removes everything,
        and fails against one that removes nothing -- and it has already done the second."""
        explains = "{%- comment -%} we do not use slugify here, and here is why {%- endcomment -%}\n[]"
        uses = "{{ heading | slugify }}"
        self.assertNotIn("slugify", liquid_source(explains))
        self.assertIn("slugify", liquid_source(uses))
        self.assertIn("[]", liquid_source(explains), "the stripper ate the template as well")


if __name__ == "__main__":
    unittest.main()
