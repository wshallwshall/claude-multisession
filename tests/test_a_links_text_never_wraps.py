"""No relative markdown link may carry a newline, in its text or in its target.

THE FAILURE THIS EXISTS FOR. `jekyll-relative-links` is what turns `](CONCEPTS.md#a)` into the built
URL `/claude-multisession/CONCEPTS.html#a`. It finds links with one regular expression, transcribed
below from `lib/jekyll-relative-links/generator.rb` in 0.6.1 -- the version `Gemfile` pins through
the `github-pages` gem, which is how GitHub's own builder resolves it:

    LINK_TEXT_REGEX   = %r!(.*?)!
    FRAGMENT_REGEX    = %r!(#.+?)?!
    INLINE_LINK_REGEX = %r!\\[#{LINK_TEXT_REGEX}\\]\\(([^\\)]+?)#{FRAGMENT_REGEX}\\)!

In Ruby `.` does not match a newline. So a link whose TEXT wraps across a line break is not a link as
far as that pattern is concerned, and it is never rewritten. The `](FILE.md)` survives into the HTML
verbatim. Jekyll also copies `FILE.md` to the site as a static file, so the reader does not get a
404 that somebody would report -- the browser fetches the raw markdown and renders it as plain text,
and the `#fragment` addresses nothing in it. The identical link is correct on github.com, which is
where it gets reviewed. Same characters, opposite verdict, no error on either surface.

MEASURED, ON THE BUILT SITE, BECAUSE THAT IS THE ONLY PLACE IT IS VISIBLE. Built with
`bundle exec jekyll build --source docs` on 2026-08-07: 35 `href` values across the site were still
relative `.md` paths, 17 of them carrying a fragment. Every one had a wrapped link text and nothing
else wrong with it. 20 were in `docs/standards/ADOPTING-THESE.md`; 9 of the 35 arrived with the
citation migration in PR #16 and the rest pre-dated it. After the reflow that accompanies this file,
the same build emits 0.

THE TARGET HALF REFUSES NOTHING TODAY AND IS STILL HERE, and the reason is that the obvious summary
of the rule -- "only the text matters, the target may wrap" -- is false, which a probe page put
through the real build settled. Four links, one build:

    [text on one line](CONCEPTS.md#a)          -> /claude-multisession/CONCEPTS.html#a   rewritten
    [text that\\nwraps](CONCEPTS.md#a)          -> CONCEPTS.md#a                          NOT
    [text on one line](CONCEPTS.md#a-frag\\n-b) -> CONCEPTS.md#a-frag\\n-b                 NOT
    [text on one line](CONCEPTS.md\\n)          -> CONCEPTS.md                            NOT

The last two fail for a different reason than the first: `([^\\)]+?)` does admit a newline, and
kramdown is permissive enough to accept the destination, so the plugin matches -- and then looks up
a page whose path contains a newline, finds none, and returns the link untouched. A rule stated over
the link text alone would leave that path open while reading as though it were closed. Both halves
are one sentence: no newline anywhere inside a relative inline link.

WHY `test_internal_links_resolve.py` CANNOT SEE THIS CLASS. It computes github.com's rule against the
markdown, and github is the surface where these links work. It is also line-oriented: `parse()` hands
its scan one line at a time, so `INLINE_LINK` never matches a link that spans two. All 35 passed
there, silently, as links it could not see rather than as links it approved.

THAT BLINDNESS WAS LOAD-BEARING FOR A SECOND CONTROL. PR #16 banned any anchor into a heading whose
text contains `--`, the one shape github.com and kramdown slug differently. One of the 35, in
`docs/standards/DEPENDENCY-INTEGRITY.md`, anchored into `## Reject code you cannot explain --
assistance in reaching the explanation is fine` in `docs/CI-AND-STANDARDS.md` -- exactly the shape
that ban refuses. It passed the ban for the same reason it passed the link scan: the wrap made it
invisible to a line-oriented pattern. Unwrapping it made the ban fire on the first run, and it is now
written as the by-name citation `test_heading_citations_resolve.py` gates. Two blind spots stacked,
and the outer one hid the inner one.

SCOPE IS `docs/`, WHICH IS THE JEKYLL SOURCE ROOT. A markdown file outside it is never built, so the
plugin never sees it and the shape is not this defect there. Files are read from `git ls-files`, so a
document moved into `docs/` becomes subject to the rule without anything here being edited.

LIMIT: THE TEXT PATTERN REFUSES A BRACKET WHERE THE PLUGIN'S `.` ADMITS ONE. `[a [b] c](x.md)` is a
link the plugin matches and this scan does not, so a nested-bracket link text that also wrapped would
be missed. Measured on the tracked markdown: 0 link texts contain a bracket. The alternative is worse
than the gap. Admitting brackets means the lazy text run can start at the `[` of a `- [ ]` task-list
row and grow across the file to the next `](`, and the first version of this scan did exactly that --
it reported one "link" whose text was thirty lines of a checklist. The blank-line guard in
`WRAPPING_LINK_TEXT` is the other half of that fix: link text cannot span a paragraph break.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

import _ccxtest as t

# docs/ is the Jekyll source root -- _config.yml says so, and says why its own location is
# load-bearing. Nothing outside it is built, so nothing outside it can carry this defect.
SITE_SOURCE_ROOT = "docs"

# Transcribed from jekyll-relative-links 0.6.1. Python's `.` excludes a newline exactly as Ruby's
# does, so PLUGIN_LINK_TEXT is the plugin's behaviour rather than a model of it.
PLUGIN_LINK_TEXT = r"(.*?)"

# The same class, widened to admit the newline the plugin's cannot -- which is the whole of the
# difference between what gets rewritten and what should. Brackets are excluded and a blank line
# ends the run; see the docstring for what each of those buys and costs.
WRAPPING_LINK_TEXT = r"((?:[^\[\]\n]|\n(?![ \t]*\n))*?)"

FRAGMENT = r"(#.+?)?"


def inline_link(link_text: str) -> re.Pattern[str]:
    """The plugin's INLINE_LINK_REGEX, over a caller-supplied link-text class."""
    return re.compile(r"\[" + link_text + r"\]\(([^)]+?)" + FRAGMENT + r"\)")


# What the plugin rewrites, and what it would rewrite if a link text could wrap. Every finding below
# is a match of the second that is not a match of the first.
REWRITTEN = inline_link(PLUGIN_LINK_TEXT)
WOULD_REWRITE = inline_link(WRAPPING_LINK_TEXT)

# `replaceable_link?` in the plugin: not a bare fragment, not an absolute URL. Those it leaves alone
# on purpose, so a wrapped one is not this defect.
ABSOLUTE = re.compile(r"^[A-Za-z][A-Za-z0-9+.\-]*:|^//")

FENCE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE = re.compile(r"`+[^`\n]*`+")


def mask_examples(text: str) -> str:
    """Blank fenced blocks and inline code spans, preserving every byte offset.

    Excluded for the reason `test_internal_links_resolve.py` excludes them, one of which it found by
    firing: a file that DOCUMENTS this shape has to write it, and an example of a defect is not the
    defect. Spaces rather than deletion, so the reported line numbers stay the file's own.
    """
    out: list[str] = []
    fenced = False
    for line in text.split("\n"):
        if FENCE.match(line):
            fenced = not fenced
            out.append(" " * len(line))
            continue
        if fenced:
            out.append(" " * len(line))
            continue
        out.append(INLINE_CODE.sub(lambda m: " " * len(m.group(0)), line))
    return "\n".join(out)


def site_markdown() -> list[Path]:
    """Every markdown file git tracks under the Jekyll source root.

    RAISES when it finds nothing. An empty corpus scanned for a shape it cannot contain is a green
    test that proved nothing.
    """
    out = subprocess.run(
        ["git", "ls-files", "*.md"],
        cwd=t.REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    paths = [
        t.REPO_ROOT / p
        for p in out.stdout.split("\n")
        if p.strip() and p.startswith(SITE_SOURCE_ROOT + "/")
    ]
    if not paths:
        raise AssertionError(
            f"git ls-files matched no markdown under {SITE_SOURCE_ROOT}/ -- either the site source "
            "root moved, in which case update SITE_SOURCE_ROOT here and in "
            "test_internal_links_resolve.py, or this scan would pass over nothing"
        )
    return paths


def wrapped_links(paths: list[Path]) -> list[str]:
    """Every relative inline link carrying a newline, in its text or in its target."""
    failures: list[str] = []
    checked = 0

    for path in paths:
        text = mask_examples(t.read(path))
        rel = path.relative_to(t.REPO_ROOT).as_posix()
        for m in WOULD_REWRITE.finditer(text):
            link_text, target, fragment = m.group(1), m.group(2), m.group(3) or ""
            if target.startswith("#") or ABSOLUTE.match(target):
                continue
            whole = target + fragment
            if "\n" not in whole and not (path.parent / target).resolve().exists():
                # A link naming no file is test_internal_links_resolve's finding, not this one.
                # Skipping keeps one defect from being reported twice -- and a target that wraps is
                # excluded from the skip, because "no such file" is exactly what the wrap causes.
                continue
            checked += 1
            lineno = text[: m.start()].count("\n") + 1
            if "\n" in link_text:
                failures.append(
                    f"{rel}:{lineno} -> {whole} (link TEXT wraps: {' '.join(link_text.split())!r})"
                )
            elif "\n" in whole:
                failures.append(f"{rel}:{lineno} -> {whole!r} (link TARGET wraps)")

    if not checked:
        raise AssertionError(
            "the scan examined no relative links at all, so the pattern has gone blind. It is the "
            "same regex jekyll-relative-links uses; if that stopped matching this corpus, the "
            "plugin has stopped rewriting the corpus too"
        )
    return failures


class ALinksTextNeverWraps(unittest.TestCase):
    def test_no_relative_link_carries_a_newline(self):
        failures = wrapped_links(site_markdown())
        self.assertEqual(
            [],
            failures,
            "\n\nThese links are not rewritten by jekyll-relative-links, so the published site\n"
            "serves the raw .md file and any #fragment addresses nothing. github.com renders the\n"
            "same links correctly, which is why review does not see it:\n  "
            + "\n  ".join(failures)
            + "\n\nReflow so the whole link sits on one line. Wrapping the target instead does not\n"
            "help -- it breaks the rewrite by a second route, the page lookup. A line pushed past\n"
            "HS-14's ~100 characters by this is the stated reason that rule allows; see\n"
            "docs/HOUSE-STYLE.md, HS-16.",
        )

    def test_the_plugins_own_pattern_confirms_it_would_miss_them(self):
        """The negative control. Without it, the rule above is a claim about a third-party regex.

        Reading the transcribed pattern and reasoning about Ruby's `.` is how this defect survived
        review in the first place. This runs it: over a link whose text wraps, the pattern the
        plugin actually uses finds nothing at all, and over the reflowed form it finds the link.
        """
        wrapped = "see [Secure\ndevelopment](SECURE-DEVELOPMENT.md#a) for more\n"
        reflowed = "see [Secure development](SECURE-DEVELOPMENT.md#a) for more\n"

        self.assertEqual([], REWRITTEN.findall(wrapped))
        self.assertEqual(1, len(WOULD_REWRITE.findall(wrapped)))

        self.assertEqual(
            [("Secure development", "SECURE-DEVELOPMENT.md", "#a")], REWRITTEN.findall(reflowed)
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
                return wrapped_links(written)
            finally:
                t.REPO_ROOT = real

    def test_a_wrapped_link_text_is_reported(self):
        found = self._scan(
            {
                "a.md": "# A\n\nsee [Secure\ndevelopment](b.md) for more\n",
                "b.md": "# B\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("link TEXT wraps", found[0])

    def test_a_wrapped_link_text_with_a_fragment_is_reported(self):
        """17 of the 35 measured carried one, and the fragment is the half a reader notices."""
        found = self._scan(
            {
                "a.md": "# A\n\nsee [Secure\ndevelopment](b.md#the-part) for more\n",
                "b.md": "# B\n\n## The part\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("b.md#the-part", found[0])

    def test_a_wrapped_target_is_reported(self):
        """The sibling path. Measured on a probe build: it is not rewritten either.

        It resolves to no file, which is what the skip above would normally treat as another test's
        finding -- so the skip has to exclude it, and this case is what holds that open.
        """
        found = self._scan(
            {
                "a.md": "# A\n\nsee [development](b.md#the-part-that\n-wraps) for more\n",
                "b.md": "# B\n",
            }
        )
        self.assertEqual(1, len(found), found)
        self.assertIn("link TARGET wraps", found[0])

    def test_the_same_link_on_one_line_is_not_reported(self):
        found = self._scan(
            {
                "a.md": "# A\n\nsee [Secure development](b.md#the-part) for more\n",
                "b.md": "# B\n\n## The part\n",
            }
        )
        self.assertEqual([], found)

    def test_a_wrapped_absolute_url_is_not_reported(self):
        """The plugin leaves absolute URLs alone by design, so a wrap does not change what is served.

        The resolving relative link beside it is not padding: without one the file carries no
        relative link at all, the blindness guard raises, and this passes for having checked nothing.
        """
        found = self._scan(
            {
                "a.md": "# A\n\nsee [the\nrow](https://example.invalid/p.html#x) and [B](b.md)\n",
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found)

    def test_a_wrapped_bare_fragment_is_not_reported(self):
        found = self._scan(
            {
                "a.md": "# A\n\njump to [the\npart](#the-part) and see [B](b.md)\n\n## The part\n",
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found)

    def test_a_wrapped_link_inside_a_code_fence_is_not_reported(self):
        found = self._scan(
            {
                "a.md": (
                    "# A\n\nSee [the real one](b.md) first. The broken shape looks like this:\n\n"
                    "```markdown\n[Secure\ndevelopment](SECURE-DEVELOPMENT.md)\n```\n\n"
                    "and that is what to avoid.\n"
                ),
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found, "a fenced example is not a link anyone can click")

    def test_a_wrapped_link_inside_an_inline_code_span_is_not_reported(self):
        found = self._scan(
            {
                "a.md": (
                    "# A\n\nSee [the real one](b.md). The shape `[Secure development](B.md)` is\n"
                    "what to write instead.\n"
                ),
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found, "a backticked example is not a link anyone can click")

    def test_a_task_list_row_does_not_start_a_link(self):
        """The over-match this pattern was narrowed to prevent, kept as a case rather than a memory.

        A `- [ ]` row opens a bracket that never closes into a `](`. With a text class that admitted
        brackets, the lazy run walked from there to the next real link and reported the whole
        checklist as one wrapped link text.
        """
        found = self._scan(
            {
                "a.md": (
                    "# A\n\n- [ ] The first thing\n- [ ] The second thing\n- [ ] The third\n\n"
                    "Then see [B](b.md) for the rest.\n"
                ),
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found)

    def test_a_link_text_may_not_span_a_paragraph_break(self):
        """Two paragraphs are not one link, whatever brackets happen to fall either side of the gap.

        Without the blank-line guard the run crosses the break and reports the pair as a link,
        which is a false positive on prose nobody can fix.
        """
        found = self._scan(
            {
                "a.md": "# A\n\nAn unclosed [ bracket in prose.\n\nThen see [B](b.md) for the rest.\n",
                "b.md": "# B\n",
            }
        )
        self.assertEqual([], found)

    def test_a_link_naming_no_file_is_left_to_the_link_checker(self):
        """One defect, one report. `test_internal_links_resolve.py` owns "no such file"."""
        found = self._scan({"a.md": "# A\n\nsee [Secure\ndevelopment](gone.md) and [B](b.md)\n", "b.md": "# B\n"})
        self.assertEqual([], found)

    def test_an_empty_corpus_raises_rather_than_passing(self):
        with self.assertRaises(AssertionError):
            wrapped_links([])


if __name__ == "__main__":
    unittest.main()
