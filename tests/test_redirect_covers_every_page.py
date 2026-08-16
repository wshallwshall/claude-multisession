"""The forwarding site left on the old host answers for every page that was ever served there.

WHY THIS EXISTS. The documentation moved from wshallwshall.github.io to claude-multisession.pages.dev
on 2026-08-10, and the old host keeps serving a stub per old URL rather than being switched off --
see scripts/site/build_redirect.py for why. A forwarder is a control with a silent failure mode: a
document added to docs/ after the move gets a page on the new site and, if the two sets are ever
maintained separately, nothing on the old one. The reader following an old link then gets a 404 from
a site that is still up, which reads as "this page never existed" rather than "this page moved".

THE GENERATOR IS BUILT SO THAT CANNOT HAPPEN -- it derives its page list from the same `git ls-files
docs/*.md` the site build uses -- and this file is the check that it stays built that way. What it
pins is the AGREEMENT between three things that are edited by different people at different times:
the tracked markdown, the generator, and the destination in docs/_config.yml.

THE DESTINATION IS THE HALF MOST WORTH PINNING. A stub that forwards confidently to the wrong host
is worse than no stub at all: the reader is sent somewhere, the browser reports success, and the
only evidence is a page that does not exist. So every generated target is compared against
docs/_config.yml rather than against a string written here, because a copy of the address in this
file would be a second definition of it and the two would drift.

NO STUB MAY RUN A SCRIPT. docs/assets/style.css states the rule: a feature gets a script only when
"the answer it filtered was complete before any script ran". A forwarder is the tempting exception
-- one 404 page that reads its own path and rewrites it would replace all seventeen files -- and it
is exactly the case the rule refuses, because with script disabled that page can only offer the site
root and cannot say which document was wanted. The generator writes a file per page instead. This
test is what stops the tempting version arriving later.
"""

from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

sys.path.insert(0, str(t.REPO_ROOT / "scripts" / "site"))

import build_redirect  # noqa: E402


def tracked_page_names() -> set[str]:
    """The stem of every markdown file the site is built from."""
    names = {p.name[: -len(".md")] for p in build_redirect.tracked_pages()}
    if not names:
        raise AssertionError("no tracked markdown -- this test would compare two empty sets")
    return names


def build_into(tmp: str) -> Path:
    dest = Path(tmp) / "redirect"
    build_redirect.build(dest)
    return dest


def missing_stubs(dest: Path, names: set[str]) -> list[str]:
    """Pages that were served on the old host and have nothing answering for them now."""
    return sorted(n for n in names if not (dest / f"{n}.html").exists())


def target_of(page: Path) -> str | None:
    """The address a stub forwards to, read from the meta refresh a browser would obey."""
    m = re.search(r'<meta http-equiv="refresh" content="0; url=([^"]+)"', page.read_text("utf-8"))
    return None if m is None else m.group(1)


class TheForwarderAnswersForEveryOldUrl(unittest.TestCase):
    def test_every_document_has_a_stub(self):
        names = tracked_page_names()
        with tempfile.TemporaryDirectory() as tmp:
            missing = missing_stubs(build_into(tmp), names)
        self.assertEqual(
            [],
            missing,
            "\n\nThese documents are served on the new site and have nothing forwarding to them\n"
            "on the old one. A reader following an old link gets a 404 from a site that is still\n"
            "up, which does not say the page moved:\n  " + "\n  ".join(missing),
        )

    def test_unknown_paths_are_answered_too(self):
        """Every old address that is not one of the pages still reaches the new site.

        GitHub Pages serves 404.html for anything it does not recognise, so this one file answers
        the entire long tail. What it may forward TO is deliberately loose here: while docs/404.md
        exists the generator points it at the new site's own not-found page, which is the honest
        answer, and without it the generator falls back to the site root. Pinning one of those two
        would fail the run for a change of destination that is not a defect. What must not happen is
        the file being absent, and that is what this asserts.
        """
        base = build_redirect.config_value("url").rstrip("/")
        with tempfile.TemporaryDirectory() as tmp:
            dest = build_into(tmp)
            self.assertTrue((dest / "404.html").exists(), "no 404.html: unknown old paths dead-end")
            target = target_of(dest / "404.html")
        self.assertTrue(
            target and target.startswith(base + "/"),
            f"the catch-all forwards to {target!r}, which is not on the new site",
        )

    def test_every_stub_forwards_to_the_configured_site(self):
        """Compared against docs/_config.yml, never against an address written in this file."""
        base = (
            build_redirect.config_value("url").rstrip("/")
            + build_redirect.config_value("baseurl").rstrip("/")
        )
        wrong = []
        with tempfile.TemporaryDirectory() as tmp:
            dest = build_into(tmp)
            for name in sorted(tracked_page_names()):
                want = base + "/" if name == "index" else f"{base}/{name}.html"
                got = target_of(dest / f"{name}.html")
                if got != want:
                    wrong.append(f"{name}.html forwards to {got}, not {want}")
        self.assertEqual(
            [],
            wrong,
            "\n\nA stub forwards somewhere docs/_config.yml does not describe. The browser will\n"
            "report success either way and the reader lands on a page that does not exist:\n  "
            + "\n  ".join(wrong),
        )

    def test_no_stub_runs_a_script(self):
        """A forwarding stub has to name its destination without running anything.

        THIS USED TO CITE THE SITE-WIDE NO-SCRIPT RULE IN docs/assets/style.css, and that rule was
        retired on 2026-08-16 -- the site now ships assets/site.js. This check is unchanged, because
        it never really rested on that rule: it rests on what a stub IS. A stub's entire content is
        the address of the page that moved, so a stub that needs script to produce that address has
        no content at all for a reader who has script disabled, and the tempting one-file version --
        a single 404 page reading its own path and rewriting it -- cannot even name which document
        was wanted. Nothing on this site's own pages depends on that argument; this file's do.
        """
        scripted = []
        with tempfile.TemporaryDirectory() as tmp:
            dest = build_into(tmp)
            for page in sorted(dest.glob("*.html")):
                if "<script" in page.read_text("utf-8").lower():
                    scripted.append(page.name)
        self.assertEqual(
            [],
            scripted,
            "\n\nThese forwarding pages run a script. A reader with JavaScript disabled then has\n"
            "no complete answer in the served HTML -- which is the whole reason there is a file\n"
            "per page rather than one path-rewriting 404:\n  " + "\n  ".join(scripted),
        )

    def test_the_visible_link_matches_the_refresh(self):
        """A meta refresh a browser ignores has to leave a link that still works.

        These two are written from the same value, so the test is cheap -- and it is the pin that
        keeps them written that way, because the version where the visible link is a friendly
        constant and the refresh is the real one fails silently for exactly the readers the visible
        link exists for.
        """
        mismatched = []
        with tempfile.TemporaryDirectory() as tmp:
            for page in sorted(build_into(tmp).glob("*.html")):
                text = page.read_text("utf-8")
                target = target_of(page)
                if f'<a href="{target}">' not in text:
                    mismatched.append(f"{page.name} refreshes to {target} and links elsewhere")
        self.assertEqual([], mismatched, "\n  " + "\n  ".join(mismatched))


class TheScanCanActuallyBite(unittest.TestCase):
    """A check that cannot fail is not a control."""

    def test_a_document_with_no_stub_is_reported(self):
        names = tracked_page_names()
        victim = sorted(names)[0]
        with tempfile.TemporaryDirectory() as tmp:
            dest = build_into(tmp)
            (dest / f"{victim}.html").unlink()
            self.assertEqual([victim], missing_stubs(dest, names))

    def test_a_config_with_no_destination_refuses_to_build(self):
        """Guessing would send every reader somewhere plausible and wrong."""
        with tempfile.TemporaryDirectory() as tmp:
            empty = Path(tmp) / "_config.yml"
            empty.write_text("title: something\n", encoding="utf-8")
            real = build_redirect.CONFIG
            try:
                build_redirect.CONFIG = empty
                with self.assertRaises(SystemExit):
                    build_redirect.config_value("url")
            finally:
                build_redirect.CONFIG = real

    def test_the_generator_reads_the_config_rather_than_a_constant(self):
        """Point it at a different destination and every stub has to move with it."""
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "_config.yml"
            fake.write_text(
                'title: t\nurl: https://example.invalid\nbaseurl: ""\n'
                "repo_url: https://example.invalid/repo\n",
                encoding="utf-8",
            )
            real = build_redirect.CONFIG
            try:
                build_redirect.CONFIG = fake
                dest = build_into(tmp)
            finally:
                build_redirect.CONFIG = real
            targets = {target_of(p) for p in dest.glob("*.html")}
        self.assertTrue(targets, "no stubs were generated, so this proved nothing")
        offsite = [x for x in targets if not x.startswith("https://example.invalid/")]
        self.assertEqual(
            [],
            offsite,
            "the destination did not follow docs/_config.yml, so it is written down somewhere "
            "else as well and the two can drift:\n  " + "\n  ".join(offsite),
        )


if __name__ == "__main__":
    unittest.main()
