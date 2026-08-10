"""Pin the three ways this documentation set can go wrong without anyone noticing.

THE FAILURE THIS EXISTS FOR. Publishing docs/ as a site turned two of these from theory into
something that already happened once.

  1. THE INSTALL PROCEDURE CAN EXIST IN MORE THAN ONE COPY. README.md is the front door on
     github.com, docs/index.md is the front door on the served site, and INSTALL.md is the
     annotated long form. A reader follows exactly one of them. When two of them carried the
     commands, nothing made them agree, and the first divergence was not caught by review:
     docs/index.md said the installers refuse when `$env:CLAUDECODE` is `1` (what all four
     actually test) while README.md still said "is set" (which is looser than the code, and wrong
     for CLAUDECODE=0).

     The two landing pages have since been de-duplicated: docs/index.md carries the procedure and
     README.md points at it. So the case below no longer compares two copies -- it pins that the
     one copy still exists where the pattern can see it, and that README does not grow a second
     copy that disagrees. INSTALL.md was never in this scan despite the docstring's original
     "three copies": it writes `<tooling>` as a placeholder rather than `"$tooling/`, so
     INSTALL_COMMAND has never matched a line in it.

     THAT INSTALL.md IS OUT OF SCOPE IS NOW A DECISION, NOT AN ACCIDENT OF THE PATTERN. It was
     unpinned because a regex happened not to match it, which is a different thing from anyone
     having judged it should be, and the gap is recorded here so the next reader does not have to
     rediscover which of the two it was. The judgment: placeholder-form instructions are a
     different artifact from copy-paste commands. Pinning them would mean normalising `<tooling>`
     against `"$tooling/` so the two forms could be compared, and that comparison would go red on
     cosmetic rewording that harms no reader -- a gate that fails for reasons unrelated to drift
     is one people learn to ignore, which costs more than the coverage is worth. It stays
     deliberately unpinned. Do NOT close this by widening INSTALL_COMMAND.
  2. LINKS TO FILES OUTSIDE docs/ ARE ABSOLUTE, AND THEIR HOST HAS MOVED ONCE ALREADY. Serving
     from /docs makes docs/ the site root, so a `../scripts/...` target resolves above the root
     and 404s. Those were rewritten to absolute blob/main URLs on github.com -- correct at the
     time, and it converted an in-repo reference that a move breaks loudly into an external one
     that a move breaks silently. On 2026-08-10 the owner confirmed the firewall in front of this
     project's readers blocks GitHub wholesale rather than only the Pages host, which made all 35
     of them unreachable for the audience the documents are written for. They now point at the
     copy the site publishes itself, and the pin moved with them.
  3. A DOC CLAIM ABOUT A CONTROL CAN OUTLIVE THE CONTROL. The CLAUDECODE case is the live
     example: the sentence was not wrong when written, it was wrong about what the code tests.

WHAT THIS PROVES, AND WHAT IT DOES NOT. These cases read source. They prove the install block still
exists where the pattern can see it and that README does not carry a second copy that disagrees,
that every same-origin source URL names a path the build actually serves, that no link has reverted
to the GitHub form, and that no copy describes the installer refusal more loosely than the
installers implement it. They do NOT fetch anything: a URL whose path exists here still 404s if the
deploy did not run, and nothing local can see that. They also do not check INSTALL.md's prose
against the landing page -- it is the long form and is expected to differ.

Run: python -m unittest discover -s tests

WHY THAT FORM, stated from measurement rather than from what the last person assumed. unittest is
stdlib, so that command works on every interpreter registered on this machine. That is the whole
reason to prefer it, and it is a reason that survives the environment changing.

pytest ALSO runs this suite -- `python -m pytest tests -q` was measured at 100 passed on the default
interpreter, which does have pytest. It is simply not REQUIRED: CI never calls it. Whether it is
importable depends on which python the reader has (three are registered here and one lacks it), so a
pytest instruction is a coin flip where a stdlib one is not. An earlier version of this line claimed
pytest "is not installed"; that was false on the default interpreter, and it was corrected by a peer
session that measured all three rather than trusting the sentence.

The single-module form works, but only from inside tests/:

    cd tests && python -m unittest test_docs_do_not_drift        # runs, 11 tests
    python -m unittest test_docs_do_not_drift                    # from the repo root: errors

These files import `_ccxtest`, which resolves only with tests/ on sys.path. From the root the error
looks like a broken test and is not -- that misreading cost one session four unverified commits.
CI runs `python -m unittest discover -s . -p 'test_*.py' -v` (.github/workflows/gates.yml:196).
"""

from __future__ import annotations

import re
import subprocess
import unittest

import _ccxtest as t

# The install block is a fenced sequence of `pwsh -NoProfile -File "$tooling/..."` lines. Matching
# on the $tooling variable is deliberate: the two prose mentions of a bare
# `pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1` are explanatory, not part of the
# procedure, and pinning those would fail on a wording change that harms nobody.
INSTALL_COMMAND = re.compile(r'pwsh -NoProfile -File "\$tooling/[^\n]*')

# The BLUF heading the standards set and both landing pages settled on, and the spellings it
# replaced. Held as data because two tests read it, and stated as a BAN on the old forms rather than
# a requirement for the new one -- see TheBlufConventionHasOneSpelling for why that distinction is
# deliberate. The inline form is matched at the start of a line because that is where it was used;
# the words "TL;DR" inside a sentence are prose and are nobody's convention.
BLUF_HEADING = "## TLDR/BLUF"
SUPERSEDED_BLUF = (
    r"^##\s+In short\s*$",
    r"^##\s+TL;?DR\s*$",
    r"^\*\*TL;DR\b[^*]*\*\*",
)

# Every link that is a reader's route to a FILE in this repository's own tree.
#
# THESE USED TO BE GITHUB URLS AND ARE NOW SAME-ORIGIN, which changed what this scan is for without
# changing what it does. Until 2026-08-10 they were written two ways -- the human-readable
# `github.com/.../blob/main/` view and the `raw.githubusercontent.com/.../main/` download form -- and
# both were pinned here because both rot into a 404 the same way. Then the owner confirmed the
# firewall in front of this project's readers blocks GitHub wholesale, not merely the Pages host, so
# all 35 of them named a file that audience has no route to at all. They now point at the copy the
# site itself serves; scripts/site/publish_sources.py is what puts it there.
#
# The check is unchanged in shape and stronger in consequence. A link that named a moved file used
# to give the reader a GitHub 404, which at least says "not found" in a page they recognise. It now
# gives them a 404 from the documentation site itself, so the site is the thing that looks broken --
# and this is the only place that can catch it, because the target is not a markdown page and
# test_internal_links_resolve.py resolves only `.html` and directory indexes.
#
# THE `docs/` ASYMMETRY IS THE TRAP, and it is why the expected path is computed rather than assumed:
# Jekyll publishes docs/CONCEPTS.md at /CONCEPTS.md, while everything else keeps its repository path,
# so /scripts/coord/claim.ps1 is right and /docs/CONCEPTS.md is a 404 that looks perfectly sensible.
SOURCE_URL = re.compile(
    r"https://claude-multisession\.pages\.dev/([^)\"'\s>]+)"
)

# The GitHub forms this replaced. Kept as a pattern so the ban below can refuse a regression: a
# reader writing a new link will reach for the URL github.com hands them, and it is correct on the
# surface they copied it from.
LEGACY_GITHUB_URL = re.compile(
    r"https://(?:github\.com/wshallwshall/claude-multisession/blob"
    r"|raw\.githubusercontent\.com/wshallwshall/claude-multisession)/main/([^)\"'\s>]+)"
)

# The looser phrasing. All four installers test the LITERAL string "1", so "is set" promises a
# refusal that does not happen for CLAUDECODE=0, =true, or anything else truthy-looking.
CLAUDECODE_LOOSE = re.compile(r"CLAUDECODE`?\s+is set", re.IGNORECASE)

# Files whose links are worth pinning: everything git tracks that can carry one.
LINK_BEARING_SUFFIXES = (".md", ".yml", ".yaml", ".html", ".json")

README = t.REPO_ROOT / "README.md"
LANDING = t.REPO_ROOT / "docs" / "index.md"


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


class TheTestIndexNamesEveryTest(unittest.TestCase):
    """`tests/README.md` tabulates what each test file pins. Pin that the table is complete.

    THE FAILURE THIS EXISTS FOR, and it is not hypothetical: the table had fallen to SIX rows for
    ELEVEN files before anyone noticed. Nothing signalled it. A reader consulting the index to find
    out what is covered gets a confident answer that silently omits five files, which is worse than
    no index -- an absent row reads as "no such test" rather than "nobody updated this".

    It is the same shape as every other case in this file: a document that describes the system, kept
    by hand, with nothing making it keep up. Both directions are checked, because a row naming a file
    that has since been deleted or renamed is the same defect pointing the other way.
    """

    INDEX = t.REPO_ROOT / "tests" / "README.md"
    ROW = re.compile(r"^\| `(test_\w+\.py)`", re.M)

    def test_the_table_names_every_test_file_and_no_others(self):
        listed = set(self.ROW.findall(t.read(self.INDEX)))
        self.assertTrue(
            listed,
            f"{self.INDEX.name}: no `| `test_*.py`` rows found at all. Either the table was "
            "reshaped or this pattern stopped matching it -- and an empty set would compare equal "
            "to an empty expectation and report agreement, so this raises instead.",
        )
        present = {p.name for p in (t.REPO_ROOT / "tests").glob("test_*.py")}
        self.assertEqual(
            set(),
            present - listed,
            f"these test files have no row in {self.INDEX.name}: {sorted(present - listed)}. Add "
            "one saying what it pins and the failure it exists for, or the index quietly claims "
            "they do not exist.",
        )
        self.assertEqual(
            set(),
            listed - present,
            f"{self.INDEX.name} has rows for files that are gone: {sorted(listed - present)}. A "
            "row for a deleted test is a coverage claim with nothing behind it.",
        )


class TheInstallProcedureHasOneCopy(unittest.TestCase):
    """docs/index.md owns the procedure; README.md points at it rather than repeating it.

    This replaced a case that pinned the two files to identical blocks, which was the right shape
    while both carried the commands. De-duplicating the landing pages left README with no block,
    and that case's own empty-match guard fired rather than passing on an empty comparison. The
    guard is kept below, moved onto the file that now owns the procedure -- which is the only file
    it can defend, since a guard on the pointing file would fail the moment the pointing worked.
    """

    def test_the_landing_page_still_carries_the_procedure(self):
        landing = INSTALL_COMMAND.findall(t.read(LANDING))
        self.assertNotEqual(
            [],
            landing,
            "no install commands found in docs/index.md, which is the one copy of the procedure. "
            "Either the block moved or its shape changed; a pattern that matches nothing passes "
            "everything, so fix the pattern -- or this file's premise about where the procedure "
            "lives -- before trusting a green run here.",
        )

    def test_the_readme_carries_no_second_copy_that_disagrees(self):
        readme = INSTALL_COMMAND.findall(t.read(README))
        landing = INSTALL_COMMAND.findall(t.read(LANDING))

        # Either README points (no commands) or it repeats the landing page exactly. Anything else
        # is the divergence this file exists for. Stated as one membership test rather than a
        # branch, so the empty case cannot slip through as an early return that reads as a pass.
        # Its vacuous case -- both empty -- is what the sibling case above rules out.
        self.assertIn(
            readme,
            ([], landing),
            "README.md carries install commands that do not match docs/index.md.\n"
            "README.md:\n  " + "\n  ".join(readme) + "\n"
            "docs/index.md:\n  " + "\n  ".join(landing) + "\n"
            "A reader follows exactly one of these. Either drop the block from README.md and point "
            "at the landing page, or make the two character-identical in this same commit.",
        )


def published_path(tracked_relpath: str) -> str:
    """Where the built site serves a tracked file.

    ONE function, used by the check below and by nothing else that could disagree with it. Jekyll
    publishes docs/CONCEPTS.md at /CONCEPTS.md; scripts/site/publish_sources.py copies everything
    else to its repository path. Two rules, one place.
    """
    return tracked_relpath[len("docs/"):] if tracked_relpath.startswith("docs/") else tracked_relpath


class SourceLinksResolve(unittest.TestCase):
    def test_every_source_url_names_a_path_the_site_actually_serves(self):
        tracked = set(tracked_files())
        served = {published_path(p) for p in tracked}
        offenders = []
        checked = 0
        for relpath in sorted(tracked):
            if not relpath.endswith(LINK_BEARING_SUFFIXES):
                continue
            text = t.read(t.REPO_ROOT / relpath)
            for target in SOURCE_URL.findall(text):
                # A target carrying a shell or PowerShell variable is a TEMPLATE inside a fetch
                # snippet, not a link anyone clicks. Resolving it would mean executing the snippet.
                if "$" in target:
                    continue
                # Rendered pages and in-page anchors are test_internal_links_resolve.py's job; it
                # resolves them back to the markdown and checks the headings too. Checking them here
                # as file paths would report every one of them as missing.
                if target.endswith(".html") or "#" in target or target.endswith("/"):
                    continue
                checked += 1
                if target in served:
                    continue
                # A directory is a legitimate target: a download snippet points a base URL at one
                # and appends the filename per iteration.
                if any(p.startswith(target + "/") for p in served):
                    continue
                offenders.append(f"{relpath}: /{target}")

        self.assertNotEqual(
            0,
            checked,
            "this scan found no same-origin source URLs at all. That is either a repository with "
            "none left, or a broken pattern. Confirm which before accepting the pass.",
        )
        self.assertEqual(
            [],
            sorted(offenders),
            "a source link names a path the built site does not serve:\n"
            + "\n".join(sorted(offenders))
            + "\nThe reader gets a 404 from the documentation site itself, so the site is what "
            "looks broken. Note the asymmetry that causes most of these: a docs/ page is served "
            "at the site ROOT, so /CONCEPTS.md is right and /docs/CONCEPTS.md is not.",
        )

    def test_no_link_reverts_to_the_github_form(self):
        """The regression this file cannot afford, because it is invisible to every other check.

        A github.com URL resolves perfectly for whoever writes it -- they are looking at the page
        they copied it from -- and is unreachable for the audience the site exists for. Nothing
        about it looks wrong in review, which is why it is banned by pattern rather than by habit.
        """
        offenders = []
        for relpath in sorted(tracked_files()):
            if not relpath.endswith(LINK_BEARING_SUFFIXES):
                continue
            for target in LEGACY_GITHUB_URL.findall(t.read(t.REPO_ROOT / relpath)):
                offenders.append(f"{relpath}: {target}")
        self.assertEqual(
            [],
            offenders,
            "these links point at a file on GitHub, which the readers this site is written for "
            "cannot reach at all -- their firewall blocks it wholesale, not just the Pages host:\n"
            + "\n".join(offenders)
            + "\nUse the copy the site serves: https://claude-multisession.pages.dev/<path>, with "
            "docs/NAME.md written as /NAME.md.",
        )


class DocClaimsMatchTheCode(unittest.TestCase):
    def test_all_four_installers_still_test_the_literal_one(self):
        """The doc rule below is only correct while this is."""
        self.assertEqual(
            4,
            len(t.ALL_INSTALLERS),
            "the set of installers has changed. Add the new one to ALL_INSTALLERS -- an installer "
            "this scan does not read is one the rule is not enforced on.",
        )
        for installer in t.ALL_INSTALLERS:
            self.assertRegex(
                t.read(installer),
                r"\$env:CLAUDECODE\s+-eq\s+['\"]1['\"]",
                f"{installer.name} no longer tests $env:CLAUDECODE against the literal '1'. If the "
                "test is now for presence, the docs that say `1` become the wrong ones and this "
                "pin has it backwards -- fix the direction, do not delete the case.",
            )

    def test_no_front_door_describes_the_refusal_as_merely_set(self):
        offenders = []
        for path in (README, LANDING, t.REPO_ROOT / "INSTALL.md"):
            for number, line in enumerate(t.read(path).splitlines(), start=1):
                if CLAUDECODE_LOOSE.search(line):
                    offenders.append(f"{path.name}:{number}: {line.strip()}")
        self.assertEqual(
            [],
            offenders,
            "a document says the installers refuse when $env:CLAUDECODE is *set*:\n"
            + "\n".join(offenders)
            + "\nAll four test the literal string '1'. A reader with CLAUDECODE=0 would find the "
            "installers run. Say `1`.",
        )


class TheScansCanSeeWhatTheyLookFor(unittest.TestCase):
    """Prove each instrument on a planted example. A pattern that matches nothing passes
    everything, and all three patterns here are the kind that silently stop matching after an
    innocuous reformat."""

    def test_the_install_command_pattern_matches_a_real_command(self):
        planted = 'pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target'
        self.assertEqual([planted], INSTALL_COMMAND.findall(planted))

    def test_the_source_pattern_extracts_the_path_and_stops_at_the_delimiter(self):
        planted = (
            "see [the gate](https://claude-multisession.pages.dev/"
            "scripts/hooks/worktree_gate.ps1) for the rule"
        )
        self.assertEqual(["scripts/hooks/worktree_gate.ps1"], SOURCE_URL.findall(planted))

    def test_the_legacy_pattern_still_sees_both_github_forms(self):
        """The ban is only worth anything while it can recognise what it refuses.

        Both spellings are planted, because the raw form was added to this repository AFTER the
        blob form and a pattern that saw only one went quietly blind for a while. The ban inherits
        that history, so it inherits the case.
        """
        blob = (
            "see [the gate](https://github.com/wshallwshall/claude-multisession/blob/main/"
            "scripts/hooks/worktree_gate.ps1) for the rule"
        )
        raw = (
            "take the [raw markdown](https://raw.githubusercontent.com/wshallwshall/"
            "claude-multisession/main/CLAUDE.md.template) instead"
        )
        self.assertEqual(["scripts/hooks/worktree_gate.ps1"], LEGACY_GITHUB_URL.findall(blob))
        self.assertEqual(["CLAUDE.md.template"], LEGACY_GITHUB_URL.findall(raw))

    def test_the_published_path_rule_moves_docs_pages_to_the_root(self):
        """The asymmetry that produces the most plausible-looking wrong link."""
        self.assertEqual("CONCEPTS.md", published_path("docs/CONCEPTS.md"))
        self.assertEqual("scripts/coord/claim.ps1", published_path("scripts/coord/claim.ps1"))
        self.assertEqual("INSTALL.md", published_path("INSTALL.md"))

    def test_the_loose_phrasing_pattern_matches_the_wording_it_exists_to_catch(self):
        self.assertTrue(
            CLAUDECODE_LOOSE.search("All four installers refuse when `$env:CLAUDECODE` is set,")
        )
        self.assertIsNone(
            CLAUDECODE_LOOSE.search("All four installers refuse when `$env:CLAUDECODE` is `1`,"),
            "the pattern must not fire on the correct wording, or the fix cannot make it green.",
        )


class TheBlufConventionHasOneSpelling(unittest.TestCase):
    """The convention drifted three times in one evening, and every drift was green.

    THE FAILURE THIS EXISTS FOR, measured rather than imagined. The standards set converged on a
    BLUF heading. It was spelled `## In short` on some pages and `**TL;DR --**` inline on the two
    landing pages, and the owner settled it as `## TLDR/BLUF` across all of them. While that rename
    was in flight, three further pages -- AI-ASSISTED-DEVELOPMENT, CODE-QUALITY and
    DEPENDENCY-INTEGRITY -- each gained a BLUF from a different session, all three spelled the old
    way, none of them wrong to do so because nothing recorded that the spelling had moved. Every one
    passed every gate. The set went from three pages to five to eight in a few hours.

    WHAT IS PINNED, AND WHAT IS DELIBERATELY NOT. This checks only that no page carries a SUPERSEDED
    spelling. It does NOT require a page to have a BLUF at all.

    That restraint is the point, not an omission. Requiring one would be an editorial rule about
    what every future standard must contain, and two published pages -- WHICH-STANDARDS-APPLY.md and
    STANDARDS-REFERENCE.md -- deliberately have no BLUF section today; each opens on a bold lede
    doing the same job unheaded. Whether they should gain one is a writing decision for whoever owns
    those pages. A test is the wrong place to make it, and a gate that fails on a legitimate
    editorial choice is one people delete.

    So: have a BLUF or do not. If you have one, spell it the way the rest of the set does.
    """

    def test_no_page_carries_a_superseded_bluf_spelling(self):
        offenders = []
        for relpath in tracked_files():
            if not relpath.endswith(".md"):
                continue
            text = t.read(t.REPO_ROOT / relpath)
            for spelling in SUPERSEDED_BLUF:
                for match in re.finditer(spelling, text, re.M):
                    line = text.count("\n", 0, match.start()) + 1
                    offenders.append(f"{relpath}:{line}: {match.group(0).strip()}")
        self.assertEqual(
            [],
            offenders,
            "these pages spell the BLUF heading a way the set no longer uses:\n  "
            + "\n  ".join(offenders)
            + f"\nThe convention is `{BLUF_HEADING}`. Two spellings for one thing is how a reader "
            "ends up believing the pages disagree about something, and it has already happened "
            "three times here. Rename it -- and if the page has a Word copy, regenerate that in the "
            "same commit.",
        )

    def test_the_canonical_heading_is_actually_in_use(self):
        """The empty-match guard. A scan for absences passes trivially against an empty corpus.

        If nothing carries the canonical spelling, either the convention was renamed again without
        this file being told, or `tracked_files` has stopped returning markdown -- and in both cases
        the case above is asserting nothing while reporting success.
        """
        carrying = [
            relpath
            for relpath in tracked_files()
            if relpath.endswith(".md") and BLUF_HEADING in t.read(t.REPO_ROOT / relpath)
        ]
        self.assertGreaterEqual(
            len(carrying),
            5,
            f"only {len(carrying)} tracked pages carry {BLUF_HEADING!r}. The absence scan above "
            "would pass against a corpus where the convention had been renamed out from under it, "
            "so this number is what makes that scan mean anything.",
        )

    def test_the_superseded_patterns_match_the_spellings_they_exist_to_catch(self):
        """Prove each pattern on a planted example, and prove the canonical form is not caught."""
        for planted in ("## In short", "## TL;DR", "**TL;DR --** run it"):
            self.assertTrue(
                any(re.search(p, planted, re.M) for p in SUPERSEDED_BLUF),
                f"no superseded-spelling pattern fired on {planted!r}; the check is unenforced.",
            )
        self.assertFalse(
            any(re.search(p, BLUF_HEADING, re.M) for p in SUPERSEDED_BLUF),
            "a pattern fires on the canonical heading itself, so no page could ever be made green.",
        )


if __name__ == "__main__":
    unittest.main()
