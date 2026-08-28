"""Pin the four ways this documentation set can go wrong without anyone noticing.

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
  4. ONE MEASUREMENT CAN BE STATED OVER TWO DENOMINATORS. Found 2026-08-12: the write-collision
     figure was scoped to sessions seated in the shared primary in README.md and stated over all
     file writes in docs/TIPS-AND-TRICKS.md. Both wordings entered in the root commit, so there
     was no drift to bisect and nothing was ever "changed" -- the corpus shipped inconsistent. A
     percentage whose denominator is left implicit is the shape to watch: each sentence reads well
     alone, and only a side-by-side comparison no reader performs exposes it.

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

# The sibling documentation site. It is the one external host whose HEADINGS this repository has any
# business caring about, because the two projects cross-reference each other constantly and moved off
# github.io together on 2026-08-10.
#
# Written as a plain string through re.escape rather than as a pattern with the dots escaped by hand,
# for the reason test_internal_links_resolve.py records about its own host: a hand-escaped
# `secure-development-standards\.pages\.dev` does not match a find-and-replace over the literal host,
# so the occurrence that silently survives the next move is the one inside the checker.
SIBLING_HOST = "https://secure-development-standards.pages.dev"
SIBLING_URL = re.compile(re.escape(SIBLING_HOST) + r"(/[^)\"'\s>]*)?")

# The looser phrasing. All four installers test the LITERAL string "1", so "is set" promises a
# refusal that does not happen for CLAUDECODE=0, =true, or anything else truthy-looking.
CLAUDECODE_LOOSE = re.compile(r"CLAUDECODE`?\s+is set", re.IGNORECASE)

# Files whose links are worth pinning: everything git tracks that can carry one.
LINK_BEARING_SUFFIXES = (".md", ".yml", ".yaml", ".html", ".json")

README = t.REPO_ROOT / "README.md"
LANDING = t.REPO_ROOT / "docs" / "index.md"

# WHERE THE PROCEDURE LIVES, AND IT MOVED ON 2026-08-16. It was docs/index.md, which is why the class
# below is still named for a landing page. The landing page had grown to 3,143 words -- the install
# commands, the requirements table and a 40-row script inventory all above the fold -- so the
# procedure was given its own page and the landing page now points at it.
#
# THE PIN MOVED WITH IT RATHER THAN BEING WIDENED, which is the whole point. A scan that accepted the
# commands on EITHER page would go green on the day they existed on both, and two copies of an
# install procedure is the exact defect this file was written for.
PROCEDURE = t.REPO_ROOT / "docs" / "QUICKSTART.md"


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
    """docs/QUICKSTART.md owns the procedure; README.md and the landing page point at it.

    This replaced a case that pinned two files to identical blocks, which was the right shape while
    both carried the commands. De-duplicating the landing pages left README with no block, and that
    case's own empty-match guard fired rather than passing on an empty comparison. The guard is kept
    below, on whichever file owns the procedure -- which is the only file it can defend, since a
    guard on a pointing file would fail the moment the pointing worked.

    THE OWNER CHANGED ON 2026-08-16 and the shape of the check did not. There are now TWO pointing
    files to defend rather than one, because the landing page stopped carrying the commands in the
    same change that moved them.
    """

    def test_the_quickstart_still_carries_the_procedure(self):
        procedure = INSTALL_COMMAND.findall(t.read(PROCEDURE))
        self.assertNotEqual(
            [],
            procedure,
            "no install commands found in docs/QUICKSTART.md, which is the one copy of the "
            "procedure. Either the block moved or its shape changed; a pattern that matches nothing "
            "passes everything, so fix the pattern -- or this file's premise about where the "
            "procedure lives -- before trusting a green run here.",
        )

    def test_no_other_front_door_carries_a_second_copy_that_disagrees(self):
        procedure = INSTALL_COMMAND.findall(t.read(PROCEDURE))

        # Either the file points (no commands) or it repeats the owner exactly. Anything else is the
        # divergence this file exists for. Stated as one membership test rather than a branch, so
        # the empty case cannot slip through as an early return that reads as a pass. Its vacuous
        # case -- both empty -- is what the sibling case above rules out.
        for path in (README, LANDING):
            found = INSTALL_COMMAND.findall(t.read(path))
            self.assertIn(
                found,
                ([], procedure),
                f"{path.name} carries install commands that do not match docs/QUICKSTART.md.\n"
                f"{path.name}:\n  " + "\n  ".join(found) + "\n"
                "docs/QUICKSTART.md:\n  " + "\n  ".join(procedure) + "\n"
                "A reader follows exactly one of these. Either drop the block and point at the "
                "quickstart, or make the two character-identical in this same commit.",
            )


class TheWriteCollisionFigureNamesItsDenominator(unittest.TestCase):
    """The 44% and the 29% are two numerators over ONE denominator. Pin that every copy says so.

    THE FAILURE THIS EXISTS FOR, measured 2026-08-12 and not hypothetical. The same measurement was
    stated over two different denominators in this repository: README.md scoped it to the writes
    made by sessions seated in the shared primary, and docs/TIPS-AND-TRICKS.md stated it over all
    file writes. Both entered in the root commit, so there was no drift signal and nothing to
    bisect. Review did not catch it in the eight days either wording survived, because each
    sentence reads perfectly well alone -- the defect is only visible when two files are held side
    by side, which is precisely what no reader does.

    WHAT SETTLED IT. The repo this tooling was developed in records the raw counts, and is the only
    place the two numerators appear together, which is the only context in which a shared
    denominator has to be made explicit: 166 sessions
    ran with their cwd in the shared primary, 6,075 of their Edit/Write calls (44%) landed in that
    primary's tree and 4,010 (29%) landed in a sibling worktree by absolute path. Both rows are
    scoped to those sessions, so the two percentages share one denominator of roughly 13,800 calls,
    and roughly 27% of that population landed outside the repository altogether. The figures are
    cited, not re-measured; nothing here can recompute them.

    WHY THIS IS A BAN ON THE LOOSE FORM rather than a requirement for the exact new wording, which
    is the same choice TheBlufConventionHasOneSpelling makes and for the same reason. The scope can
    be carried by an attribution clause, by a lead-in sentence that both figures hang off, or by a
    noun phrase, and pinning one spelling would go red on a rewording that harms no reader. What
    must never come back is the bare "N% of writes", whose denominator a reader supplies for
    themselves and supplies wrongly.

    THE CORPUS IS WIDER THAN prose_files(). The figure also ships in CLAUDE.md.template, which is
    copied into a consumer's own repository, and in three PowerShell scripts, one of which prints
    it to an operator at runtime. A gate blind to the copies that leave this repository would be
    the false green most worth having here.
    """

    # "N% of writes" and its spellings. The percentage may be bolded; "the" and "all" are optional
    # noise. Matching the NOUN rather than the number keeps the pattern from firing on unrelated
    # percentages elsewhere in the corpus.
    #
    # THE NOUN LIST IS AN ALLOWLIST AND THEREFORE A HOLE, stated rather than left to be discovered:
    # "44% of edits", "44% of tool calls" or a spelled-out "forty-four percent" are unmatched and
    # would pass. It covers the four spellings the corpus actually uses. Widen it when a fifth
    # appears; do not assume the absence of a failure is coverage.
    WRITE_SHARE = re.compile(
        r"\*{0,2}\d+\s*%\*{0,2}\s+of\s+(?:the\s+|all\s+)*"
        r"(?:file\s+writes|Edit/Write\s+calls|write\s+calls|writes)\b"
    )

    # What must follow: an attribution, AND the population actually named, within a short window.
    #
    # ATTRIBUTION ALONE IS NOT ENOUGH, and an earlier draft of this gate made exactly that mistake.
    # "29% of writes by other sessions" satisfies a by-plus-sessions pattern and names a DIFFERENT
    # population, so the gate would have blessed a sentence with the wrong denominator. Requiring
    # the primary to be named is what makes this a check on the denominator rather than on grammar.
    ATTRIBUTION = re.compile(r"\s*\*{0,2}\s*(?:by|from|made\s+by)\b")
    POPULATION = re.compile(
        r"primary-seated|shared\s+primary|shared\s+checkout|primary\s+checkout|in\s+the\s+primary",
        re.I,
    )
    SESSIONS = re.compile(r"\bsessions?\b", re.I)
    SCOPE_WINDOW = 120

    # The one file that carries the counts and the population.
    OWNER = "README.md"
    COUNTS = ("166", "6,075", "4,010")

    # Everything git tracks that is text. Deliberately NOT a figure-bearing allowlist: an allowlist
    # decides in advance where the defect is allowed to be, and this one already shipped in a
    # template and three scripts nobody would have listed.
    # Binary, so t.read decodes none of them. `.docx` joined the list when docs/word/KORUS.docx was
    # committed: this scan reads EVERY tracked file, so a new binary format reaches it as a
    # UnicodeDecodeError rather than as a finding, and the run errors instead of reporting. The
    # error is the correct behaviour of an unlisted format -- a scan that silently swallowed an
    # unreadable file would be the failure this suite exists to catch -- so the fix is to name the
    # format here, and only formats this repository actually tracks are named.
    SKIPPED_SUFFIXES = (".png", ".jpg", ".gif", ".ico", ".pdf", ".woff", ".woff2", ".docx")

    # This file plants the defective sentence on purpose, in the negative control below. Scanning
    # it would make the gate fail on its own test data. Named rather than pattern-excluded so the
    # exemption is one file and cannot silently grow to cover a real copy.
    SELF = "tests/test_docs_do_not_drift.py"

    def corpus(self) -> list[str]:
        return [
            path
            for path in tracked_files()
            if not path.endswith(self.SKIPPED_SUFFIXES) and path != self.SELF
        ]

    def is_scoped(self, text: str, end: int) -> bool:
        """Does the figure ending at `end` name the population it is a share of?"""
        if not self.ATTRIBUTION.match(text, end):
            return False
        window = " ".join(text[end:end + self.SCOPE_WINDOW].split())
        return bool(self.POPULATION.search(window) and self.SESSIONS.search(window))

    def test_no_copy_states_the_figure_over_an_unscoped_denominator(self):
        unscoped = []
        scanned = 0
        for path in self.corpus():
            text = t.read(t.REPO_ROOT / path)
            scanned += 1
            for hit in self.WRITE_SHARE.finditer(text):
                if not self.is_scoped(text, hit.end()):
                    line = text.count("\n", 0, hit.start()) + 1
                    unscoped.append(f"{path}:{line}: {hit.group(0)!r}")

        self.assertEqual(
            [],
            unscoped,
            f"scanned {scanned} tracked files; these state a share of writes without naming the "
            "population it is a share OF:\n  " + "\n  ".join(unscoped) + "\n"
            "The 44% and the 29% are shares of the Edit/Write calls made by sessions seated in the "
            "shared primary, NOT of every write on the machine. Say whose writes, or the next "
            "reader supplies a denominator and supplies it wrongly.",
        )

    def test_the_owner_still_carries_the_counts(self):
        """The empty-match guard, on the file it can defend.

        Without this, the ban above passes perfectly once the figure is deleted everywhere -- which
        is how a duplication gate normally rots. It sits on the owning file for the reason
        TheInstallProcedureHasOneCopy records: a guard on a pointing file fails the moment the
        pointing works.
        """
        readme = t.read(t.REPO_ROOT / self.OWNER)
        missing = [count for count in self.COUNTS if count not in readme]
        self.assertEqual(
            [],
            missing,
            f"{self.OWNER} is the record for this measurement and no longer states {missing}. "
            "Either the counts moved, in which case move this guard and the links in "
            "docs/TIPS-AND-TRICKS.md and docs/CI-FOR-LEADERS.md with them, or a digit was dropped "
            "-- which PD-1 requires a reason for in the commit message.",
        )

    def test_the_owner_declares_the_denominator_before_it_states_a_figure(self):
        """README carries the figures in bullets that do not each repeat the scope, by design.

        That is what makes it the owner rather than a fourth copy -- the population is stated once
        and both bullets hang off it. The ban above cannot see that arrangement, because the
        bullets never use the "N% of writes" construction it matches. So the owner needs its own
        check, or the one file the whole fix rests on is the one file nothing inspects.
        """
        readme = t.read(t.REPO_ROOT / self.OWNER)
        first = readme.find("44%")
        self.assertNotEqual(-1, first, f"{self.OWNER} no longer states the 44% figure at all.")

        lead_in = " ".join(readme[max(0, first - 500):first].split())
        for token in ("166", "shared primary", "Edit/Write calls"):
            self.assertIn(
                token,
                lead_in,
                f"the 500 characters before {self.OWNER}'s first figure no longer contain "
                f"{token!r}, so the bullets below it now state a percentage whose denominator the "
                "reader has to guess. Either restore the lead-in that declares the population, or "
                "scope each bullet individually and retire this case.",
            )

    def test_the_pattern_rejects_the_wording_it_exists_to_reject(self):
        """The negative controls. A pattern that fires on nothing passes everything."""
        rejected = {
            "the historical defect": "44% of all file writes still landed in the primary's tree",
            "attribution without a population": "29% of writes by other sessions landed there",
            "population without an attribution": "29% of writes; the shared primary sessions did it",
        }
        for name, sentence in rejected.items():
            hit = self.WRITE_SHARE.search(sentence)
            self.assertIsNotNone(hit, f"the pattern no longer recognises a claim at all: {name}")
            self.assertFalse(
                self.is_scoped(sentence, hit.end()),
                f"{name!r} is now accepted as scoped. The pattern was broadened until it stopped "
                "discriminating, which is a green that means nothing.",
            )

        accepted = (
            "44% of file writes by primary-seated sessions landed in that primary's tree",
            "29% of the write calls made by sessions sitting in the shared checkout landed there",
            "44% of writes from sessions sitting in the shared checkout landed there",
        )
        for sentence in accepted:
            hit = self.WRITE_SHARE.search(sentence)
            self.assertIsNotNone(hit, "the pattern no longer recognises a share-of-writes claim")
            self.assertTrue(
                self.is_scoped(sentence, hit.end()),
                f"a corrected wording in the corpus is rejected: {sentence!r}. Widen POPULATION "
                "rather than deleting the case.",
            )

    def test_the_scan_reaches_the_copies_that_leave_this_repository(self):
        """Name what was scanned. A corpus that quietly excludes the shipped copies reads green."""
        corpus = self.corpus()
        for shipped in (
            "CLAUDE.md.template",
            "scripts/hooks/worktree_gate.ps1",
            "scripts/coord/occupancy.ps1",
            "scripts/worktree/prune-merged.ps1",
        ):
            self.assertIn(
                shipped,
                corpus,
                f"{shipped} carries this figure into a consumer's repository or onto an operator's "
                "terminal, and the scan above cannot see it.",
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
                # OPEN-8, and the narrowest form of it that works. A page published in its author's
                # own words carries the author's own URLs, and appending `.html` to one is editing
                # the page. The extensionless form is not broken: Cloudflare Pages serves /WORKTREES
                # from WORKTREES.html by clean-URL fallback. MEASURED against the live site on
                # 2026-08-12, not assumed -- /WORKTREES and /USAGE-AWARENESS both returned the real
                # page, which is why this is an accepted form here rather than a tolerated defect.
                #
                # The `.md` is not a typo: `served` holds published paths, so a rendered page appears
                # in it as WORKTREES.md. Requiring a hit means a mistyped target still fails, because
                # nothing resolves it -- the exemption is for the missing suffix, not for the link.
                if relpath in t.AUTHORED_VERBATIM and target + ".md" in served:
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


class CrossRepositoryAnchorsAreRefused(unittest.TestCase):
    """No link into the sibling site may name one of its headings with a `#fragment`.

    THE GAP THIS CLOSES, AND IT IS NOT CLOSED BY CHECKING. An anchor into another repository is the
    one link shape that NOTHING can verify. This suite resolves anchors inside this tree by reading
    the target's headings; it cannot read theirs. Their suite cannot read ours. So a heading renamed
    on either side leaves a link that still renders, still clicks, still returns 200, and lands the
    reader at the top of the right page -- with no error on either surface and no check anywhere that
    could have reported it. Measured on 2026-08-10: two such links existed, both pointing from the
    sibling repository into this one, and both resolved only by luck.

    WHY A BAN RATHER THAN A CROSS-REPOSITORY CHECKER. The checker is the obvious answer and it is the
    wrong one twice over. It would have to fetch another repository's headings over a network this
    suite deliberately never touches -- this file's own docstring states that it fetches nothing --
    so it would go red when the other site is down, mid-deploy, or unreachable from the runner, and
    `test_prose_rules_hold.py` already records what happens to a gate that reddens for reasons
    unrelated to the defect. And it could not prevent the break anyway: renaming a heading here
    breaks their links the moment it merges, and their run would discover it afterwards, with their
    site already wrong. The ban stops the fragile link from existing. It is the same judgment
    `test_internal_links_resolve.py` made about `--` headings, in its own words: the fix is a ban,
    not a second rule, because refusing the shape cannot rot.

    WHAT THIS BUYS, STATED HONESTLY. Not verification. The by-name citation this pushes people to is
    not checked either -- `test_heading_citations_resolve.py` left this repository with the standards
    it pinned. What changes is how the failure presents. A renamed heading leaves a stale quoted
    heading beside a link that still lands on the correct page, which a reader can see and scroll
    past. An anchor leaves nothing visible at all. That is the difference these documents are about.

    SCOPED TO THIS ONE HOST ON PURPOSE. An anchor into a third party's page is ordinary and none of
    this repository's business -- docs/index.md links to a GitHub issue by `#issuecomment-...` and
    should keep doing so. The sibling site is different because the headings on the other end are
    written by people who read this rule.
    """

    def test_no_link_into_the_sibling_site_carries_an_anchor(self):
        offenders = []
        seen = 0
        for relpath in sorted(tracked_files()):
            if not relpath.endswith(LINK_BEARING_SUFFIXES):
                continue
            for m in SIBLING_URL.finditer(t.read(t.REPO_ROOT / relpath)):
                seen += 1
                if "#" in m.group(0):
                    offenders.append(f"{relpath}: {m.group(0)}")

        self.assertNotEqual(
            0,
            seen,
            f"no link to {SIBLING_HOST} was found at all. Either every cross-reference to the "
            "sibling project is gone -- in which case delete this rule rather than leaving it to "
            "refuse nothing -- or the host moved and this pattern went blind, which is the silent "
            "version of the same thing.",
        )
        self.assertEqual(
            [],
            offenders,
            "\n\nThese links name a heading in the sibling repository, which is the one link shape\n"
            "nothing on either side can check: this suite cannot read their headings and theirs\n"
            "cannot read ours. A rename leaves the link rendering, clicking and returning 200 while\n"
            "landing at the top of the page:\n  "
            + "\n  ".join(offenders)
            + f"\n\nCite it by name instead -- [Page]({SIBLING_HOST}/PAGE.html), *\"The heading\"* --\n"
            "which lands the reader on the right page and shows them what to look for when it moves.",
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
        # PROCEDURE joined this list on 2026-08-16, in the change that moved the install commands
        # off the landing page. The sentence describing the refusal travelled with the commands, so
        # a scan that kept reading only the old three would have been reading the one set of pages
        # the sentence had just left.
        for path in (README, LANDING, PROCEDURE, t.REPO_ROOT / "docs" / "INSTALL.md"):
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

    def test_the_sibling_pattern_tells_an_anchored_link_from_a_bare_one(self):
        """Both halves, because a ban that cannot see the shape refuses nothing and one that sees it
        everywhere refuses correct links -- and this pattern has to stop at the closing bracket of a
        markdown link to distinguish them at all."""
        anchored = "see [the tier](https://secure-development-standards.pages.dev/CQ.html#tier-1)"
        bare = 'see [the page](https://secure-development-standards.pages.dev/CQ.html), *"Tier 1"*'
        self.assertIn("#", SIBLING_URL.search(anchored).group(0))
        self.assertNotIn("#", SIBLING_URL.search(bare).group(0))

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

    WHAT IS PINNED HERE. Only that no page carries a SUPERSEDED spelling. Nothing requires a page to
    have a summary section at all, and this class has never been the place that did.

    THAT SPLIT WAS A DELIBERATE RESTRAINT, IT EXPIRED, AND IT IS THE WHOLE RULE AGAIN. This class
    once declined to require a BLUF, on the stated grounds that requiring one would be an editorial
    rule about what every future standard must contain, and that two published pages --
    WHICH-STANDARDS-APPLY.md and STANDARDS-REFERENCE.md -- deliberately had none, each opening on a
    bold lede doing the same job unheaded. Both left with the standards for their own repository, and
    on 2026-08-10 the owner settled the editorial question by requiring the section on every rendered
    page, gated by OPEN-2. On 2026-08-27 the owner retired OPEN-2, and the three rules describing
    what went inside the section with it. That gate is deleted; docs/HOUSE-STYLE.md carries the
    tombstone.

    So: a page may open however it opens, and a page that heads a summary section spells that heading
    the way the rest of the set does.
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

    def test_the_scan_actually_reads_markdown(self):
        """The empty-match guard. A scan for absences passes trivially against an empty corpus.

        IT COUNTS THE FILES SCANNED, NOT THE PAGES CARRYING THE HEADING. Until 2026-08-27 it counted
        the latter and required five, which was sound while OPEN-2 required the section on every
        rendered page, and became a back-door copy of that rule the moment OPEN-2 was retired. A
        corpus where four pages choose a summary section is now legitimate, and a gate that reddens a
        legitimate editorial choice is one people delete.

        What it still catches is the failure that would silence the ban above: `tracked_files`
        returning no markdown, which leaves it asserting nothing while reporting success.
        """
        scanned = [relpath for relpath in tracked_files() if relpath.endswith(".md")]
        self.assertGreaterEqual(
            len(scanned),
            20,
            f"the ban above scanned only {len(scanned)} markdown files. It would pass against a "
            "corpus it cannot read, so this number is what makes that scan mean anything.",
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


class TheNextFreeIdentifierIsAboveEverythingThisPageIssues(unittest.TestCase):
    """docs/HOUSE-STYLE.md declares the next free number in each series. Keep it true locally.

    WHY THIS IS WORTH A TEST AT ALL. The numbering is one namespace shared with
    secure-development-standards, and that repository's sheet reads this one to decide what is free.
    Neither side can see the other move: its page states this one issues OPEN-1 to OPEN-6, which was
    true when written and stopped being true the moment OPEN-7 landed here.

    WHAT THIS CAN AND CANNOT CHECK. It cannot see the sibling -- that would mean fetching another
    repository over a network this suite never touches, which is the same judgment that banned a
    cross-repository anchor checker rather than building one. What it CAN check is the half that is
    local and is the half that actually rots: a rule added HERE without bumping the declared next
    free number, which hands the next session a number this page has already used. The sibling's
    columns stay a dated, manually verified reading, which is why the page prints the date and the
    commit it was read at.
    """

    # `| OPEN-1 | ... |` and `### PD-8: retired ...` are both definitions. The numbering table's own
    # rows are NOT: their first cell is the literal `B-<n>`, which has no digits and cannot match.
    DEFINED_IN_ROW = re.compile(r"^\|\s*`?(B|HS|PD|OPEN)-(\d+)`?\s*\|", re.M)
    DEFINED_IN_HEADING = re.compile(r"^#{2,4}\s+`?(B|HS|PD|OPEN)-(\d+)`?\b", re.M)
    # The fourth column of the numbering table, bolded: | `B-<n>` | ... | ... | **B-18** |
    DECLARED_NEXT_FREE = re.compile(r"\|\s*\*\*(B|HS|PD|OPEN)-(\d+)\*\*\s*\|", re.M)

    def setUp(self):
        self.text = t.read(t.REPO_ROOT / "docs/HOUSE-STYLE.md")

    def issued(self) -> dict:
        highest = {}
        for pattern in (self.DEFINED_IN_ROW, self.DEFINED_IN_HEADING):
            for series, number in pattern.findall(self.text):
                highest[series] = max(highest.get(series, 0), int(number))
        return highest

    def declared(self) -> dict:
        return {s: int(n) for s, n in self.DECLARED_NEXT_FREE.findall(self.text)}

    def test_the_page_declares_a_next_free_number_for_every_series_it_uses(self):
        issued, declared = self.issued(), self.declared()
        self.assertTrue(issued, "no rule identifiers parsed out of docs/HOUSE-STYLE.md at all")
        missing = sorted(set(issued) - set(declared))
        self.assertEqual(
            [],
            missing,
            f"docs/HOUSE-STYLE.md issues {missing} rules but its numbering table declares no next "
            "free number for them. The sibling repository reads that table to decide what it may "
            "allocate, so a series missing from it is a series it will collide with.",
        )

    def test_every_declared_next_free_number_is_above_what_this_page_issues(self):
        issued, declared = self.issued(), self.declared()
        wrong = [
            f"{series}: page issues up to {series}-{high}, but declares {series}-{declared[series]} free"
            for series, high in sorted(issued.items())
            if series in declared and declared[series] <= high
        ]
        self.assertEqual(
            [],
            wrong,
            "the declared next free number is not above what this page already issues:\n  "
            + "\n  ".join(wrong)
            + "\nIf you added a rule, bump the `Next free` column in the numbering table in the same "
            "commit. Its whole job is to be read by somebody who is about to allocate.",
        )

    def test_the_parsers_tell_a_definition_from_a_mention(self):
        """Planted. Without this, both cases above pass against a parser that matches nothing."""
        self.assertEqual(
            [("OPEN", "1")], self.DEFINED_IN_ROW.findall("| OPEN-1 | The first screen MUST | x |")
        )
        self.assertEqual([("PD", "8")], self.DEFINED_IN_HEADING.findall("### PD-8: retired"))
        # A numbering-table row defines nothing: the series cell is a placeholder, and the ranges
        # and the next-free value live in later columns.
        row = "| `B-<n>` | B-1 to B-10 | B-11 to B-17 | **B-18** |"
        self.assertEqual([], self.DEFINED_IN_ROW.findall(row))
        self.assertEqual([("B", "18")], self.DECLARED_NEXT_FREE.findall(row))


class TheAuthoredVerbatimExemptionStaysVisible(unittest.TestCase):
    """OPEN-8: the one page published unedited is a real page, and the rule sheet names it.

    THIS CLASS USED TO GATE THE OPENING CONVENTION, and what went is worth recording rather than
    silently deleting. It enforced OPEN-7 by pinning three labels -- `**What this is.**`, `**Why you
    should care.**`, `**How to use it.**` -- verbatim and in order on every rendered page, so a
    reworded or unbolded one read as absent. OPEN-7 was relaxed on 2026-08-16 to require the three
    ANSWERS in the author's own words, and that half of the gate went the day after, on the owner's
    instruction. For that one day the rule sheet said "No gate: a semantic check needs a reader, not
    a substring match" while the substring match was still running and still green -- a document
    describing a control it did not have, which is the defect this whole suite exists to refuse.

    THE OTHER HALF WENT ON 2026-08-27, also on the owner's instruction. It held OPEN-2: every page
    docs/ renders carries `## TLDR/BLUF`, spelled that one way. OPEN-1, OPEN-2, OPEN-4 and OPEN-7
    are retired together in docs/HOUSE-STYLE.md, and no rule now requires a page to open with a
    summary section. What survives is one class up: the BAN on the spellings the set replaced, which
    binds a page that has such a section and demands nothing of a page that does not.

    AN EMPTY-MATCH GUARD WENT WITH THE SCAN IT GUARDED. It asserted at least 15 rendered pages,
    because the deleted scan reported success over an empty list. The assertion below cannot: it
    reads each exempt path and fails when the list of rendered pages does not contain it.

    WHAT IS LEFT IS THE EXEMPTION'S OWN INTEGRITY, which was always this class's other job.
    """

    NOT_A_PAGE = ("docs/404.md",)

    def rendered_pages(self) -> list[str]:
        return [
            f
            for f in tracked_files()
            if f.startswith("docs/") and f.endswith(".md") and f not in self.NOT_A_PAGE
        ]

    def test_the_open_8_exemption_is_real_tracked_and_named_in_the_house_style(self):
        """An exemption nobody can see is the failure mode of every exemption.

        Three ways this one could rot silently, and each is asserted rather than trusted:
        a path that no longer exists (the page renamed, the carve-out now covering nothing while
        reading as though it still applies); a path outside the set of pages the OPEN rules bind
        at all, which would be a carve-out from nothing; and t.AUTHORED_VERBATIM growing without
        docs/HOUSE-STYLE.md naming the addition, which is how a one-page exception becomes a
        general permission nobody voted for.
        """
        pages = set(self.rendered_pages())
        house_style = t.read(t.REPO_ROOT / "docs" / "HOUSE-STYLE.md")
        for relpath in t.AUTHORED_VERBATIM:
            self.assertIn(
                relpath,
                pages,
                f"OPEN-8 exempts {relpath}, which is not a tracked rendered page. Either the file "
                "was renamed and the exemption points at nothing, or it was never added with "
                "`git add`. Remove the entry or fix the path.",
            )
            self.assertIn(
                relpath,
                house_style,
                f"OPEN-8 exempts {relpath} in tests/_ccxtest.py, and docs/HOUSE-STYLE.md does not "
                "name it. The rule and its list have to be readable in the same place: name the "
                "file under OPEN-8 there, with the reason it is published unedited.",
            )


if __name__ == "__main__":
    unittest.main()
