"""Every relative link and in-page anchor in the tracked markdown resolves to something real.

WHAT THIS COVERS THAT NOTHING ELSE DID. `test_docs_do_not_drift.py` pins the ABSOLUTE links -- the
`github.com/.../blob/main/` and `raw.githubusercontent.com/.../main/` forms -- against paths git is
tracking. It never looks at the relative form, `[text](OTHER.md)`, or at an anchor, `[text](#a-
heading)`. Those are the majority of the links in docs/ and none of them were checked by anything.

THE FAILURE IT EXISTS FOR. A heading rename is invisible to a reviewer and silent to the reader: the
link still renders, still looks clickable, and lands at the top of the page instead of the section it
named. This is not hypothetical here. `docs/ASVS-ASSESSMENT.md` carries two anchors into its own
Part 2 -- `#never-score-against-a-paraphrase` and `#pin-the-corpus-and-stamp-the-version-on-every-
number` -- written in a session that renamed eight other headings in the same file. Nothing would
have reported it if one of those had moved. A separate session then renamed a `## In short` heading
across seven pages; that one happened to have no inbound links, which nothing checked either.

THE SITE'S OWN URLS COUNT AS INTERNAL, AND THEY FELL BETWEEN THE TWO CHECKERS. A link written
`https://wshallwshall.github.io/claude-multisession/standards/STANDARDS-REFERENCE.html#some-heading`
points at a page in this repository, but it starts with `https://` so this scan skipped it as
external, and it is neither of the two forms `test_docs_do_not_drift.py` pins -- that file matches
`github.com/.../blob/main/` and `raw.githubusercontent.com/.../main/`, and this is a third host. So
nothing checked them at all. There were 19 such anchored links when this branch was added.

They are not a stylistic quirk to be rewritten as relative links. `docs/standards/WHICH-STANDARDS-
APPLY.md` writes its whole third column this way ON PURPOSE: that page is converted to Word by
pandoc and handed to a reader who downloaded it, and a relative link is dead in a .docx. The long
form is the only one that survives the trip, so the links have to stay and something has to check
them.

Measured rather than argued. Renaming `## Certification and program regimes` in
`docs/standards/STANDARDS-REFERENCE.md` reports four failures with this branch in place. Exactly one
of them -- the same-file relative anchor -- was reported before it existed. The other three are
served URLs on two pages, and they were silent.

CODE FENCES ARE EXCLUDED, AND THAT IS LOAD-BEARING. The first version of this scan reported four
broken links in `examples/sequence-adr/index-row-format.md`. All four were illustrative table rows
inside a ```markdown fence -- a document ABOUT the format of a decision-record index, showing what
its rows look like. They are not links anyone clicks and the files are not supposed to exist. A scan
blind to fences answers "does this text match a link pattern" when the question is "is this a link",
which is the narrower-instrument failure this repository keeps rediscovering. `test_a_link_inside_a
_code_fence_is_not_reported` pins the fix.

INLINE CODE SPANS ARE EXCLUDED FOR THE SAME REASON, and that gap surfaced the same way: by firing.
A file that DOCUMENTS a link has to write one, and `tests/README.md` describes the heading-citation
shape `[Code quality](CODE-QUALITY.md), *Tier 1*` in backticks. Relative to `tests/` that path does
not exist and never should. Fenced blocks were handled from the first version; single-backtick spans
were not, so the scan reported three false positives the moment a row was added describing what
another test pins.

ANCHOR SLUGS follow GitHub's rule: lowercase, drop everything that is not a word character, space or
hyphen, then spaces to hyphens. GitHub disambiguates repeated headings with a `-1`, `-2` suffix, so a
link to `#the-files-1` is accepted when `the-files` occurs more than once.

THAT ONE RULE IS ENOUGH ONLY BECAUSE THE TWO RENDERERS AGREE, which was verified rather than
assumed. These documents are read on github.com AND on the published Jekyll site, each of which
generates heading ids itself. If they disagreed on a heading, a link would be correct on one surface
and silently broken on the other, and pinning either rule alone would certify the wrong half.
Checked against the deployed page on 2026-08-07: `## 1. Five failure modes, and the control for
each` in `docs/standards/AI-ASSISTED-DEVELOPMENT.md` carries
`id="1-five-failure-modes-and-the-control-for-each"` on the site -- the leading digit kept,
character-identical to github.com's slugger. Numbered headings are the case most likely to diverge
and they do not, so one rule serves both. If a renderer's id generation ever changes, this file goes
on passing while links break on one surface only; nothing local can see that.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

import _ccxtest as t

# A markdown inline link or image: [text](target) / ![alt](target). Reference-style links
# (`[text][label]`) are deliberately out of scope -- this repository uses none, and a pattern that
# claimed to cover them without a corpus to test against would be the dead rule these tests catch.
INLINE_LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)\)")

ATX_HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")

# An inline code span. Stripped before links are matched, for the same reason fenced blocks are:
# documentation that DESCRIBES a link writes the link, and `[Code quality](CODE-QUALITY.md)` inside
# backticks is an example of a citation's shape, not a link anyone can click. tests/README.md
# demonstrates exactly this and was the first file to trip it.
INLINE_CODE = re.compile(r"`+[^`]*`+")

# Links that leave the repository. The absolute in-repo forms are pinned by test_docs_do_not_drift.
EXTERNAL = ("http://", "https://", "mailto:", "tel:")

LINK_BEARING = (".md",)

# The published site's own address. A link in this form is ABSOLUTE, so it is skipped as external by
# the rule above, and it is not one of the two forms test_docs_do_not_drift pins either -- that file
# matches `github.com/.../blob/main/` and `raw.githubusercontent.com/.../main/`, neither of which is
# this host. So these fell between the two checkers and nothing looked at them. See the docstring.
#
# `url` + `baseurl` from docs/_config.yml. Both are load-bearing there and pinned by that file's own
# comments; if either moves, this pattern stops matching and `TheServedUrlScanCanSee` goes red rather
# than the scan silently going blind.
SERVED_SITE = re.compile(
    r"https://wshallwshall\.github\.io/claude-multisession(/[^)\s]*)?"
)

# docs/ is the Jekyll source root, so a served path maps back onto it directly. No permalink style is
# configured, so docs/a/b.md builds to /a/b.html -- the one exception being the directory index,
# which is why this resolves a bare directory to index.md.
SITE_SOURCE_ROOT = "docs"


def anchor_slug(heading: str) -> str:
    """GitHub's heading-to-anchor rule."""
    s = re.sub(r"[^\w\s-]", "", heading.strip().lower())
    return re.sub(r"\s+", "-", s).strip("-")


def parse(text: str) -> tuple[list[str], list[tuple[int, str]]]:
    """Split a markdown file into (heading slugs, numbered lines), both excluding fenced blocks.

    Returns slugs in document order so a caller can apply GitHub's duplicate-heading suffixing.
    """
    slugs: list[str] = []
    body: list[tuple[int, str]] = []
    fenced = False
    for lineno, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = ATX_HEADING.match(line)
        if m:
            slugs.append(anchor_slug(m.group(2)))
        body.append((lineno, INLINE_CODE.sub("", line)))
    return slugs, body


def resolvable_anchors(slugs: list[str]) -> set[str]:
    """Every anchor GitHub would serve for these headings, including its duplicate suffixes."""
    seen: dict[str, int] = {}
    out: set[str] = set()
    for s in slugs:
        n = seen.get(s, 0)
        out.add(s if n == 0 else f"{s}-{n}")
        seen[s] = n + 1
    return out


def served_url_source(target: str) -> Path | None:
    """The markdown that produces a served-site URL, or None if the URL is not this site's.

    Returns a path whether or not it exists -- "this names no document" is a finding the caller
    reports, not a reason to say the link was never one of ours. Only `.html` and the directory
    index are resolved: a served URL naming an asset (a .docx, the stylesheet) is a real link to a
    real file, but it is not a markdown page and has no headings, so this is not the check for it.
    """
    m = SERVED_SITE.fullmatch(target)
    if not m:
        return None
    path = (m.group(1) or "/").lstrip("/")
    if path == "" or path.endswith("/"):
        path += "index.html"
    if not path.endswith(".html"):
        return None
    return t.REPO_ROOT / SITE_SOURCE_ROOT / (path[: -len(".html")] + ".md")


def tracked_markdown() -> list[Path]:
    """Every markdown file git tracks.

    RAISES when it finds nothing. An empty corpus compared against an empty set of failures is a
    green test that proved nothing, which is the failure mode `_ccxtest`'s docstring names.
    """
    out = subprocess.run(
        ["git", "ls-files", "*.md"],
        cwd=t.REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    paths = [t.REPO_ROOT / p for p in out.stdout.split("\n") if p.strip()]
    if not paths:
        raise AssertionError("git ls-files matched no markdown -- the scan would pass over nothing")
    return paths


def broken_links(paths: list[Path]) -> list[str]:
    """Every relative link or anchor in `paths` that does not resolve, as readable strings."""
    parsed = {p: parse(t.read(p)) for p in paths}
    anchors = {p: resolvable_anchors(slugs) for p, (slugs, _) in parsed.items()}
    failures: list[str] = []
    checked = 0

    def anchors_of(dest: Path) -> set[str] | None:
        known = anchors.get(dest)
        if known is None:
            if not dest.exists():
                return None
            known = resolvable_anchors(parse(t.read(dest))[0])
        return known

    for path in paths:
        _, body = parsed[path]
        rel = path.relative_to(t.REPO_ROOT).as_posix()
        for lineno, line in body:
            for target in INLINE_LINK.findall(line):
                urlpart, _, url_anchor = target.partition("#")
                source = served_url_source(urlpart)
                if source is not None:
                    # A link to this site's own page, written the long way. It has to resolve for the
                    # same reason a relative one does -- and it is the form a heading rename breaks
                    # most quietly, because it renders and clicks correctly all the way to the wrong
                    # part of the right page.
                    checked += 1
                    known = anchors_of(source)
                    if known is None:
                        failures.append(
                            f"{rel}:{lineno} -> {target} (served URL names no page: "
                            f"{source.relative_to(t.REPO_ROOT).as_posix()} does not exist)"
                        )
                    elif url_anchor and anchor_slug(url_anchor) not in known:
                        failures.append(
                            f"{rel}:{lineno} -> {target} (no such heading in "
                            f"{source.relative_to(t.REPO_ROOT).as_posix()})"
                        )
                    continue
                if target.startswith(EXTERNAL) or target.startswith("<"):
                    continue
                checked += 1
                filepart, _, anchor = target.partition("#")

                if not filepart:
                    if anchor_slug(anchor) not in anchors[path]:
                        failures.append(f"{rel}:{lineno} -> #{anchor} (no such heading in this file)")
                    continue

                dest = (path.parent / filepart).resolve()
                if not dest.exists():
                    failures.append(f"{rel}:{lineno} -> {target} (no such file)")
                    continue
                if anchor and dest.suffix in LINK_BEARING:
                    known = anchors.get(dest)
                    if known is None:
                        known = resolvable_anchors(parse(t.read(dest))[0])
                    if anchor_slug(anchor) not in known:
                        failures.append(f"{rel}:{lineno} -> {target} (no such heading in target)")

    if not checked:
        raise AssertionError(
            "the scan examined no links at all -- neither a relative one nor a served-site URL, so "
            "one of the patterns has gone blind"
        )
    return failures


class InternalLinksResolve(unittest.TestCase):
    def test_every_relative_link_and_anchor_resolves(self):
        failures = broken_links(tracked_markdown())
        self.assertEqual(
            [],
            failures,
            "\n\nThese links do not resolve. A renamed heading or moved file leaves the link\n"
            "rendering normally and landing in the wrong place, so nothing reports it but a\n"
            "reader:\n  " + "\n  ".join(failures),
        )

    def test_the_served_url_scan_has_something_to_look_at(self):
        """The served-URL branch above is only worth anything while such links exist.

        It is checked here rather than inside `broken_links`, because that function is also run by
        the bite cases below against two-file fixtures that legitimately contain none. A blindness
        guard in the wrong place would fail on a fixture and teach people to weaken it.
        """
        anchored = 0
        for path in tracked_markdown():
            _, body = parse(t.read(path))
            for _, line in body:
                for target in INLINE_LINK.findall(line):
                    url, _, anchor = target.partition("#")
                    if anchor and served_url_source(url) is not None:
                        anchored += 1
        self.assertGreater(
            anchored,
            0,
            "no anchored links to this site's own served URLs remain in the tracked markdown. "
            "Either they were all rewritten as relative links -- in which case delete the served-URL "
            "branch in broken_links rather than leaving it to pass over nothing -- or the pattern "
            "stopped matching, which is the silent version of the same thing.",
        )


class TheScanCanActuallyBite(unittest.TestCase):
    """A checker that cannot fail is not a control. Each case plants a defect and demands a report."""

    def _scan(self, files: dict[str, str]) -> list[str]:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            written = []
            for name, text in files.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(text, encoding="utf-8")
                written.append(p)
            real_root = t.REPO_ROOT
            try:
                t.REPO_ROOT = root
                return broken_links(written)
            finally:
                t.REPO_ROOT = real_root

    def test_a_missing_file_is_reported(self):
        found = self._scan({"a.md": "# A\n\nsee [the other](nope.md) for more\n"})
        self.assertEqual(1, len(found), found)
        self.assertIn("no such file", found[0])

    def test_a_missing_anchor_in_another_file_is_reported(self):
        found = self._scan(
            {
                "a.md": "# A\n\nsee [that bit](b.md#gone) for more\n",
                "b.md": "# B\n\n## Still here\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("no such heading in target", found[0])

    def test_a_missing_anchor_in_the_same_file_is_reported(self):
        found = self._scan({"a.md": "# A\n\njump to [nowhere](#not-a-heading)\n\n## Real\n"})
        self.assertEqual(1, len(found), found)
        self.assertIn("no such heading in this file", found[0])

    # The served-URL form. These four are the ones that would have caught the gap: before the branch
    # above existed, every case here came back clean because the link starts with `https://`.

    SERVED = "https://wshallwshall.github.io/claude-multisession/standards/ref.html"

    def test_a_missing_anchor_behind_a_served_url_is_reported(self):
        found = self._scan(
            {
                "a.md": f"# A\n\nsee [the row]({self.SERVED}#gone) for more\n",
                "docs/standards/ref.md": "# Ref\n\n## Still here\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("no such heading in docs/standards/ref.md", found[0])

    def test_a_served_url_naming_no_page_is_reported(self):
        found = self._scan({"a.md": f"# A\n\nsee [the row]({self.SERVED}#anything)\n"})
        self.assertEqual(1, len(found), found)
        self.assertIn("served URL names no page", found[0])

    def test_a_good_served_url_anchor_passes(self):
        """The other half of the instrument: it has to accept a correct link, or it reports noise."""
        found = self._scan(
            {
                "a.md": f"# A\n\nsee [the row]({self.SERVED}#still-here) for more\n",
                "docs/standards/ref.md": "# Ref\n\n## Still here\n",
            }
        )
        self.assertEqual([], found)

    def test_another_hosts_url_is_still_left_alone(self):
        """Scoped to THIS site. A real external link has no local file to check it against.

        The same-file anchor is not padding: without a link the scan does examine, the blindness
        guard fires and this case would pass for having checked nothing, which is the failure it is
        supposed to be evidence against.
        """
        found = self._scan(
            {
                "a.md": "# A\n\nsee [elsewhere](https://example.invalid/page.html#whatever)\n\n"
                "and [here](#a) too\n",
            }
        )
        self.assertEqual([], found)

    def test_a_link_inside_a_code_fence_is_not_reported(self):
        """The bug this scan shipped with once: four false positives in an illustrative table.

        The fixture carries a REAL resolving link beside the fenced one on purpose. Without it the
        file would contain no live links at all, the blind-pattern guard would raise, and the test
        would pass for the wrong reason -- proving the scan saw nothing rather than that it saw the
        fence and declined it.
        """
        found = self._scan(
            {
                "a.md": (
                    "# A\n\n"
                    "See [the real one](b.md) first. The index rows look like this:\n\n"
                    "```markdown\n"
                    "| [0001](0001-record-decisions.md) | Record decisions |\n"
                    "```\n\n"
                    "and that is the format.\n"
                ),
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found, "a fenced example is not a link anyone can click")

    def test_a_link_inside_an_inline_code_span_is_not_reported(self):
        """Same class as the fence case, one level finer, and it tripped on tests/README.md.

        A file that DOCUMENTS a link has to write one. `tests/README.md` describes the citation
        shape `[Code quality](CODE-QUALITY.md), *Tier 1*` in backticks; relative to `tests/` that
        path does not exist and never should. Backticks make it an example, not a link.
        """
        found = self._scan(
            {
                "a.md": (
                    "# A\n\n"
                    "See [the real one](b.md). The citation shape is "
                    "`[Code quality](CODE-QUALITY.md), *Tier 1*` and it is not a link.\n"
                ),
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found, "a backticked example is not a link anyone can click")

    def test_a_resolving_link_and_anchor_are_not_reported(self):
        found = self._scan(
            {
                "a.md": "# A\n\nsee [B's part](sub/b.md#the-part) and [self](#a)\n",
                "sub/b.md": "# B\n\n## The part\n",
            }
        )
        self.assertEqual([], found)

    def test_a_repeated_heading_gets_githubs_numbered_anchor(self):
        found = self._scan(
            {"a.md": "# A\n\n## Dup\n\n## Dup\n\nlink to [the second](#dup-1) one\n"}
        )
        self.assertEqual([], found)

    def test_an_empty_corpus_raises_rather_than_passing(self):
        with self.assertRaises(AssertionError):
            broken_links([])


if __name__ == "__main__":
    unittest.main()
