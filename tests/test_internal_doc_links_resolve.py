"""Pin every in-repository markdown link: the file it names, and the heading it points into.

THE FAILURE THIS EXISTS FOR. These documents cross-reference each other constantly -- 36 tracked
markdown files carrying 89 relative links, most of them into a specific section of another page.
Nothing checks either half, and both rot silently:

  1. A HEADING GETS REWORDED and every link into it keeps pointing at the old slug. The link still
     renders, still looks like a link, and still navigates -- to the top of the target page, with no
     error anywhere. The reader lands somewhere plausible and never learns they were sent to the
     wrong place. This is not hypothetical here: section headings in this set are edited routinely,
     including by the change that added this file.
  2. A PAGE GETS RENAMED and the links to it 404. `STANDARDS-LANDSCAPE.md` was split into
     `WHICH-STANDARDS-APPLY.md` and `STANDARDS-REFERENCE.md` while this suite was green throughout.
     That rename was handled correctly -- but nothing would have said so, and nothing would have
     said otherwise.

`test_docs_do_not_drift.py` already pins the OUTBOUND links, the absolute `blob/main` and
`raw.githubusercontent` URLs, against the paths git tracks. It deliberately stops there. The
relative links between these pages are the larger set and were unchecked.

THE SLUG RULE IS VERIFIED, NOT ASSUMED. An anchor id is derived from the heading text, and the two
renderers these documents are read through could in principle disagree: github.com applies its own
slugger, and the published site is built by Jekyll. They do not disagree. Checked against the live
site on 2026-08-07: `## 1. Five failure modes, and the control for each` carries
`id="1-five-failure-modes-and-the-control-for-each"` there, character-identical to what github.com
generates -- the leading digit is kept by both. So one rule serves both surfaces, and this file
implements that one rule. If a heading ever renders under different ids on the two surfaces, a link
can be correct in one place and broken in the other, and no test here would see it.

WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves that every relative markdown link names a file
that exists, and that every `#fragment` matches a heading in the file it points at. It does NOT
fetch anything: a link correct in this checkout still breaks on the published site if the page is
not deployed, and nothing local can see that. It does not check link TEXT against the section it
leads to -- a link reading "the leak gate" that resolves to the review-depth page passes here. And
it says nothing about absolute URLs, which are `test_docs_do_not_drift.py`'s job.

Run: python -m unittest discover -s tests     (pytest is not installed)
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

import _ccxtest as t

# A markdown link or image target: the `(...)` of `[text](target)`. Whitespace and `)` end it, so a
# target containing either is not matched -- none in this repository does.
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")

# Fenced code blocks are stripped before scanning. A fence can legitimately contain link syntax as
# an EXAMPLE -- documentation about markdown, or a sample of a file being generated -- and holding
# those to the same standard would report failures against text that was never a link.
FENCE = re.compile(r"^```.*?^```", re.M | re.S)

HEADING = re.compile(r"^\#{1,6}\s+(.*?)\s*$", re.M)

# Schemes that leave the repository. `mailto:` and `tel:` have no path to resolve; http(s) is the
# outbound case another file owns.
EXTERNAL = ("http://", "https://", "mailto:", "tel:", "//")


def slug(heading: str) -> str:
    """A heading's anchor id, by the rule both github.com and the published site apply.

    Inline markup is removed first and its TEXT kept, because that is what the renderer slugs: a
    heading written as ``### `[]` is not the same as nothing`` is addressed by the words, not by the
    backticks. A link inside a heading contributes its label and never its target.
    """
    s = heading
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)  # links and images -> their text
    s = re.sub(r"`([^`]*)`", r"\1", s)                # inline code
    s = re.sub(r"\*\*([^*]*)\*\*", r"\1", s)          # bold
    s = re.sub(r"\*([^*]*)\*", r"\1", s)              # italic
    s = s.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s)                    # punctuation is dropped, not replaced
    return re.sub(r"\s+", "-", s)


def tracked_markdown() -> list[Path]:
    """Every markdown file git tracks, as absolute paths.

    Derived from git rather than from a glob so that an untracked scratch file cannot fail the
    suite, and derived from the repository rather than from a list in this file so that a new
    document is covered the day it is added.
    """
    out = subprocess.run(
        ["git", "ls-files", "*.md"],
        cwd=t.REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    files = [t.REPO_ROOT / line for line in out]
    if not files:
        raise AssertionError(
            "`git ls-files '*.md'` returned nothing. Either this is not a git checkout or the "
            "markdown moved; either way every case below would pass having scanned no files."
        )
    return files


def internal_links() -> list[tuple[Path, str]]:
    """Every (source file, relative target) pair across the tracked markdown."""
    found: list[tuple[Path, str]] = []
    for md in tracked_markdown():
        body = FENCE.sub("", t.read(md))
        for target in LINK.findall(body):
            if target.startswith(EXTERNAL):
                continue
            found.append((md, target))
    if not found:
        raise AssertionError(
            "no relative markdown links found anywhere in the tracked documentation. These pages "
            "cross-reference each other heavily, so an empty set means the extraction broke, not "
            "that the links are gone -- and an empty set compares equal to an empty set."
        )
    return found


def anchors_of(path: Path) -> set[str]:
    """Every heading slug in a markdown file."""
    return {slug(h) for h in HEADING.findall(t.read(path))}


def resolve(source: Path, target: str) -> tuple[Path, str]:
    """A link target, split into the file it names and the fragment it points into."""
    filepart, _, fragment = target.partition("#")
    dest = (source.parent / filepart).resolve() if filepart else source
    return dest, fragment


class EveryRelativeLinkNamesAFileThatExists(unittest.TestCase):
    def test_the_scan_found_links_to_check(self):
        """A scan that matched nothing would make every case below vacuously true."""
        self.assertGreater(
            len(internal_links()),
            20,
            "fewer than twenty relative links found. This set cross-references itself heavily; a "
            "number this low means the pattern stopped matching, not that the links were removed.",
        )

    def test_each_link_target_exists(self):
        missing = []
        for source, target in internal_links():
            dest, _ = resolve(source, target)
            if not dest.exists():
                missing.append(f"{source.relative_to(t.REPO_ROOT)}  ->  {target}")
        self.assertEqual(
            [],
            missing,
            "these links name a file that is not there:\n  "
            + "\n  ".join(missing)
            + "\nA renamed page leaves every link to it pointing at nothing. Repoint them, or "
            "leave a stub at the old name the way STANDARDS-LANDSCAPE.md does.",
        )


class EveryFragmentNamesAHeadingThatExists(unittest.TestCase):
    def test_each_fragment_resolves_to_a_heading(self):
        broken = []
        cache: dict[Path, set[str]] = {}
        for source, target in internal_links():
            dest, fragment = resolve(source, target)
            if not fragment or dest.suffix != ".md" or not dest.exists():
                continue
            if dest not in cache:
                cache[dest] = anchors_of(dest)
            if fragment not in cache[dest]:
                broken.append(
                    f"{source.relative_to(t.REPO_ROOT)}  ->  {target}\n"
                    f"      no heading in {dest.name} slugs to '{fragment}'"
                )
        self.assertEqual(
            [],
            broken,
            "these links point at a section that does not exist:\n  "
            + "\n  ".join(broken)
            + "\nA fragment that matches no heading does NOT error in a browser -- it silently "
            "lands the reader at the top of the page. Reword the link to match the heading, or "
            "restore the heading. If a heading was deliberately reworded, every link into it "
            "moves in the same commit.",
        )


class TheInstrumentCanSeeABrokenLink(unittest.TestCase):
    """Prove both halves on a fixture, without naming anything a legitimate edit can rename.

    The fixture is taken from a real file at run time. An earlier test in this suite hardcoded a
    heading title and broke the moment that heading was reworded -- a self-test that fails on a
    legitimate edit trains people to ignore it.
    """

    def test_a_real_heading_is_found_and_an_invented_one_is_not(self):
        overview = t.REPO_ROOT / "docs" / "standards" / "OVERVIEW.md"
        anchors = anchors_of(overview)
        self.assertTrue(anchors, "OVERVIEW.md has no headings; the fragment scan has nothing to check")
        headings = HEADING.findall(t.read(overview))
        self.assertIn(
            slug(headings[0]),
            anchors,
            "a heading that IS in the file did not slug to one of the file's own anchors",
        )
        self.assertNotIn("a-section-that-does-not-exist", anchors)

    def test_the_slug_rule_handles_the_markup_headings_actually_carry(self):
        """The cases that made a naive implementation wrong, pinned as a table."""
        for heading, expected in [
            ("What you get", "what-you-get"),
            ("1. Five failure modes, and the control for each", "1-five-failure-modes-and-the-control-for-each"),
            ("**Bold** heading", "bold-heading"),
            ("`code` in a heading", "code-in-a-heading"),
            ("A [linked](FOO.md) word", "a-linked-word"),
            ("Punctuation: dropped, not replaced?", "punctuation-dropped-not-replaced"),
            ("The gate's own surface", "the-gates-own-surface"),
        ]:
            with self.subTest(heading=heading):
                self.assertEqual(expected, slug(heading))


if __name__ == "__main__":
    unittest.main()
