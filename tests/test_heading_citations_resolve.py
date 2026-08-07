"""Where one document cites another's heading by name, that heading still exists.

THE FAILURE THIS EXISTS FOR. The standards set cross-references siblings by quoting a heading title
in italics after a link: `[Code quality](CODE-QUALITY.md), *Tier 1 -- durable controls, which carry
the verdict*`. Rename that heading in the target and the citation still renders perfectly while
saying something false. There is no link and no anchor, so `test_internal_links_resolve.py` cannot
see it -- it is prose that happens to name a heading. It has bitten: `ADOPTING-THESE.md` claimed four
documents carried a *"How to adopt this"* section after a deletion left three.

WHAT IS COVERED. Exactly one shape, because exactly one shape is structurally unambiguous:

    [Any text](TARGET.md), *Heading*
    [Any text](TARGET.md), *"Heading"*

A link naming the target, a comma, then an italic run. That is a citation whether or not it
resolves, which is the property a gate needs. 27 of these exist today, all in `ADOPTING-THESE.md`,
and all currently resolve.

WHAT IS NOT COVERED, AND WHY IT CANNOT BE. This is the important half, because the count above reads
like coverage of a practice it only partly covers.

Citations also occur with the link further away, most clearly at `ADOPTING-THESE.md:267`: "[AI-
assisted development](A.md), [Code quality](B.md) and [Dependency integrity](C.md) each carry a
*"How to adopt this"* section". Three targets, no adjacency -- and that is the one that actually
bit. It is not gated here, and the reason is worth stating rather than leaving as an omission.

Widening the pattern to "any quoted italic" fails on the corpus: 107 quoted-italic runs exist under
`docs/`, and 55 of them resolve to no heading anywhere because they are ordinary quoted prose --
*"the gate passed"*, *"is this excluded?"*, *"it does not happen"*. A gate that demanded each be a
heading would fire on all 55.

The tempting fix -- treat a quoted italic as a citation only when it DOES resolve to a heading -- is
circular and cannot fail by construction. A renamed heading would stop the run resolving, so the
rule would stop classifying it as a citation, and the test would pass. That is a checker that
certifies its own blind spot, which is the defect this repository is named for catching.

So the honest scope is: the adjacent form is pinned, the distant form is not, and the durable fix
for the distant form is not a cleverer regex but citing a stable identifier instead of a title. That
migration has started -- `ADOPTING-THESE.md:125` now reads `[Secure development](SECURE-DEVELOPMENT.md),
SD-5.10.`, which this pattern deliberately does not match because it needs no checking.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

import _ccxtest as t

# [text](TARGET.md) , *italic run*  -- DOTALL because the italic run wraps lines freely in this
# corpus. The italic body cannot contain '*', which keeps the match from spanning two runs.
CITATION = re.compile(
    r"\[[^\]]*\]\((?P<target>[A-Za-z0-9._/-]+\.md)\)\s*,\s*\*\"?(?P<heading>[^*]+?)\"?\*",
    re.S,
)

ATX_HEADING = re.compile(r"^#{1,6}\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")


def normalise(text: str) -> str:
    """Collapse the whitespace a wrapped citation introduces, so it can be compared to a heading."""
    return re.sub(r"\s+", " ", text).strip()


def headings(path: Path) -> set[str]:
    """Every heading title in `path`, plus a copy with any leading section number removed.

    The numbered form matters: `## 5. Scanner posture: ...` is cited in prose as `Scanner posture:
    ...` without the number, and both spellings name the same section.
    """
    out: set[str] = set()
    fenced = False
    for line in t.read(path).split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = ATX_HEADING.match(line)
        if m:
            title = normalise(m.group(1))
            out.add(title)
            out.add(re.sub(r"^\d+\.\s*", "", title))
    return out


def tracked_markdown() -> list[Path]:
    """Every markdown file git tracks. Raises rather than returning an empty corpus."""
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


def unresolved_citations(paths: list[Path]) -> list[str]:
    """Every adjacent-form heading citation whose named heading is absent from its target."""
    cache: dict[Path, set[str]] = {}
    failures: list[str] = []
    found = 0

    for path in paths:
        text = t.read(path)
        rel = path.relative_to(t.REPO_ROOT).as_posix()
        for m in CITATION.finditer(text):
            target = (path.parent / m.group("target")).resolve()
            if not target.exists() or target.suffix != ".md":
                # A citation naming a file that does not exist is test_internal_links_resolve's
                # finding, not this one. Skipping keeps one defect from being reported twice.
                continue
            found += 1
            heading = normalise(m.group("heading"))
            if target not in cache:
                cache[target] = headings(target)
            if heading not in cache[target]:
                lineno = text[: m.start()].count("\n") + 1
                failures.append(
                    f"{rel}:{lineno} cites {m.group('target')} :: \"{heading}\" -- no such heading"
                )

    if not found:
        raise AssertionError(
            "no adjacent-form heading citations matched at all -- the pattern has gone blind"
        )
    return failures


class HeadingCitationsResolve(unittest.TestCase):
    def test_every_cited_heading_still_exists_in_its_target(self):
        failures = unresolved_citations(tracked_markdown())
        self.assertEqual(
            [],
            failures,
            "\n\nThese citations name a heading their target no longer has. The prose still reads\n"
            "correctly and no link is broken, so nothing else in this suite can see it:\n  "
            + "\n  ".join(failures),
        )


class TheScanCanActuallyBite(unittest.TestCase):
    """Each case plants a defect and demands a report. A checker that cannot fail is not a control."""

    def _scan(self, files: dict[str, str]) -> list[str]:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            written = []
            for name, body in files.items():
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(body, encoding="utf-8")
                written.append(p)
            real = t.REPO_ROOT
            try:
                t.REPO_ROOT = root
                return unresolved_citations(written)
            finally:
                t.REPO_ROOT = real

    def test_a_renamed_heading_is_reported(self):
        found = self._scan(
            {
                "a.md": '# A\n\nSee [B](b.md), *"The old name"* for detail.\n',
                "b.md": "# B\n\n## The new name\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("no such heading", found[0])

    def test_a_present_heading_is_not_reported(self):
        found = self._scan(
            {
                "a.md": '# A\n\nSee [B](b.md), *"Still here"* for detail.\n',
                "b.md": "# B\n\n## Still here\n",
            }
        )
        self.assertEqual([], found)

    def test_the_unquoted_italic_form_is_matched_too(self):
        """Both spellings occur in the corpus; a scan seeing one covers half the citations."""
        found = self._scan(
            {
                "a.md": "# A\n\nSee [B](b.md), *Tier 1 -- durable controls* for detail.\n",
                "b.md": "# B\n\n## Tier 2 -- something else\n",
            }
        )
        self.assertEqual(1, len(found), found)

    def test_a_citation_wrapped_across_lines_is_matched(self):
        """Every long citation in this corpus wraps; a single-line pattern would miss most of them."""
        found = self._scan(
            {
                "a.md": '# A\n\nSee [B](b.md), *"A heading whose title\nruns onto a second line"*.\n',
                "b.md": "# B\n\n## A heading whose title runs onto a second line\n",
            }
        )
        self.assertEqual([], found, "whitespace normalisation should let the wrapped form resolve")

    def test_a_numbered_heading_may_be_cited_without_its_number(self):
        found = self._scan(
            {
                "a.md": '# A\n\nSee [B](b.md), *"Scanner posture"* for detail.\n',
                "b.md": "# B\n\n## 5. Scanner posture\n",
            }
        )
        self.assertEqual([], found)

    def test_a_stable_identifier_citation_is_not_matched(self):
        """SD-5.10 needs no checking, so the pattern must not demand it be a heading.

        The fixture carries a real, resolving citation beside it deliberately. Without one the file
        would contain no citations at all, the blind-pattern guard would raise, and this would pass
        for the wrong reason -- proving the scan saw nothing rather than that it saw the identifier
        form and correctly declined it.
        """
        found = self._scan(
            {
                "a.md": '# A\n\nSee [B](b.md), SD-5.10 and [B](b.md), *"Something"* for detail.\n',
                "b.md": "# B\n\n## Something\n",
            }
        )
        self.assertEqual([], found)

    def test_an_empty_corpus_raises_rather_than_passing(self):
        with self.assertRaises(AssertionError):
            unresolved_citations([])


if __name__ == "__main__":
    unittest.main()
