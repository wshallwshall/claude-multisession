"""Pin the rule identifiers in SECURE-DEVELOPMENT.md as PERMANENT NAMES, not positions.

WHAT AN IDENTIFIER PROMISES. `SD-8.5` is offered to readers as a citation target: the standard tells
them to name it in their own deviations register, and a register is an artifact this repository
cannot see and cannot fix. That promise is only worth something if the identifier means the same
requirement forever. NIST 800-53 keeps withdrawn controls in the catalog marked "Withdrawn:
incorporated into X" rather than deleting them, and CVE and CWE never reuse a number, for exactly
this reason. OWASP ASVS renumbered between 4.0 and 5.0 and had to ship a crosswalk afterwards.

THE FAILURE THIS EXISTS FOR, AND IT ALREADY HAPPENED ONCE. The scheme is `SD-<section>.<n>`, which
reads like a position, and during the session that introduced it a rule was inserted mid-section as
SD-8.5 -- pushing the two service-account rules to SD-8.6 and SD-8.7. Nothing outside the working
tree had seen the old numbers, so it cost nothing. Committed, the identical edit silently repoints
every citation of SD-8.5 at a DIFFERENT requirement. Nobody gets an error. The register still reads
"SD-8.5", the standard still defines an SD-8.5, and the two are now about different things.

That is the whole class: an identifier failure is invisible from both ends, the same way a link into
a renamed section renders perfectly and lands the reader in the wrong place -- which is the failure
`test_internal_links_resolve.py` exists for, one level down.

FOUR CHECKS, cheapest first:

  1. No identifier is defined twice. A duplicate makes at least one of them uncitable.
  2. Every identifier MENTIONED anywhere in the repository resolves to one that is defined or
     retired. This is what makes a cross-document citation safe: ADOPTING-THESE.md cites rules by
     identifier now, precisely so this scan reaches them.
  3. No identifier that has EVER been defined is missing today without a tombstone. This is the
     one that enforces immutability rather than merely recommending it.
  4. No identifier is both live and retired.

WHERE HISTORY COMES FROM, and why not a ledger file. Check 3 needs to know what used to exist. A
hand-maintained list of every identifier ever issued would be a second record of a fact git already
holds perfectly -- and the standard's own SD-17.7 forbids exactly that shape, because two records of
one fact eventually disagree. So the historical set is DERIVED: walk the commits that touched the
file, read each revision, and collect what it defined. This is the same call
`test_word_copies_track_the_markdown.py` makes when it rebuilds the .docx instead of comparing
strings -- derive, so nothing has to be remembered.

The published tombstones stay in the document rather than in a test fixture, because their audience
is a reader holding a stale citation, not this suite.

A SHALLOW CLONE CANNOT ANSWER CHECK 3, AND THIS FAILS RATHER THAN SKIPS. `actions/checkout` defaults
to depth 1, which would leave this measuring nothing while printing green -- so `gates.yml` sets
`fetch-depth: 0`, and if the history is still unavailable the check below raises. A skip is printed
beside the passes and reads as one, which is the judgment `require_pandoc` and
`scripts/quality/check-ascii.ps1` both already make.

WHAT THIS DELIBERATELY DOES NOT CATCH. Semantic drift: the identifier stays, the wording stays legal,
and what the rule DEMANDS quietly changes. No scan can see that. The convention that handles it is
stated in the document itself, under *How to read the rules* -- reword freely under the same
identifier, change what it demands and you retire the identifier -- and it binds a person, not a
check. Saying so here is the point: a reader who finds this file must not conclude that a green run
means the identifiers still mean what they meant.

Run: python -m unittest discover -s tests     (from tests/, or discover -s tests from the root)
"""

from __future__ import annotations

import re
import subprocess
import unittest

import _ccxtest as t

STANDARD = t.REPO_ROOT / "docs" / "standards" / "SECURE-DEVELOPMENT.md"
STANDARD_REL = "docs/standards/SECURE-DEVELOPMENT.md"

# A rule is DEFINED by being the first cell of a table row. Anchored at the line start so a mention
# inside prose or inside another cell cannot be mistaken for a definition.
DEFINITION = re.compile(r"^\|\s*(SD-\d+\.\d+)\s*\|", re.M)

# A rule is MENTIONED anywhere the token appears, including in other documents.
MENTION = re.compile(r"\bSD-\d+\.\d+\b")

# A tombstone row under the "Retired rules" heading.
RETIRED_SECTION = re.compile(r"^##\s+Retired rules\s*$(.*?)(?=^##\s|\Z)", re.M | re.S)


def defined_ids(text: str) -> set:
    """Every identifier the given revision of the standard DEFINES."""
    return set(DEFINITION.findall(text))


def retired_ids(text: str) -> set:
    """Every identifier carrying a tombstone.

    Read only from inside the Retired rules section, so a rule that merely MENTIONS a retirement in
    its prose cannot accidentally register as retired.
    """
    section = RETIRED_SECTION.search(text)
    if section is None:
        raise AssertionError(
            "SECURE-DEVELOPMENT.md has no `## Retired rules` section. That section is where an "
            "identifier goes when its rule is withdrawn, and without it the only way to remove a "
            "rule is to delete its identifier -- which frees the number for silent reuse. Restore "
            "the section; do not delete this check."
        )
    return set(DEFINITION.findall(section.group(1)))


def mentioned_ids(text: str) -> set:
    """Every identifier the text refers to."""
    return set(MENTION.findall(text))


def repo_markdown() -> list:
    """Every tracked markdown file. Cross-document citations are the reason this scan is repo-wide."""
    files = sorted(p for p in t.REPO_ROOT.rglob("*.md") if ".git" not in p.parts)
    if not files:
        raise AssertionError(
            "no markdown files found at all. This scan would compare an empty set of citations "
            "against the rule list and report agreement, which is not a measurement."
        )
    return files


def git(*args) -> subprocess.CompletedProcess:
    """Run git at the repository root."""
    return subprocess.run(
        ["git", "-C", str(t.REPO_ROOT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def require_full_history() -> list:
    """The commits that touched the standard, newest first. Raises rather than skipping.

    A shallow clone answers this with one commit and no error, which would let the historical check
    below pass while examining a single revision -- a green result about a set nobody chose.
    """
    shallow = git("rev-parse", "--is-shallow-repository")
    if shallow.returncode != 0:
        raise AssertionError(
            "git could not be run, so no revision of this file could be read and the "
            "identifier-reuse check measured NOTHING. Treated as a failure rather than a skip: a "
            "skip is printed beside the passes and reads as one."
        )
    if shallow.stdout.strip() == "true":
        raise AssertionError(
            "this is a SHALLOW clone, so the history that says which identifiers have ever existed "
            "is not present, and the reuse check below would pass while reading one revision. "
            "`actions/checkout` defaults to depth 1; .github/workflows/gates.yml sets "
            "`fetch-depth: 0` for exactly this check. Fetch the history "
            "(`git fetch --unshallow`), or fix the workflow -- do not delete the check."
        )
    log = git("log", "--format=%H", "--", STANDARD_REL)
    commits = [line.strip() for line in log.stdout.splitlines() if line.strip()]
    if not commits:
        raise AssertionError(
            f"git log reports no commit touching {STANDARD_REL}. Either the path moved -- in which "
            "case this test needs the new one, and `--follow` is not enough to be relied on here -- "
            "or history is unavailable. Both mean the reuse check has nothing to read."
        )
    return commits


def ids_ever_defined() -> dict:
    """Every identifier any revision of the standard has defined, mapped to the commit it appeared in.

    The commit is carried so a failure can name where an identifier came from, rather than asserting
    that it once existed and leaving the reader to search the history themselves.
    """
    seen = {}
    for sha in require_full_history():
        blob = git("show", f"{sha}:{STANDARD_REL}")
        if blob.returncode != 0:
            continue  # the file did not exist at that commit
        for rule in defined_ids(blob.stdout):
            seen.setdefault(rule, sha)
    return seen


class TheIdentifiersAreUniqueAndResolvable(unittest.TestCase):
    """The two cheap checks. They need no history and catch the two mistakes made most often."""

    def test_no_identifier_is_defined_twice(self):
        text = t.read(STANDARD)
        found = DEFINITION.findall(text)
        self.assertTrue(
            found,
            "no rule identifiers found in SECURE-DEVELOPMENT.md at all. Either the rule tables were "
            "reshaped or this pattern stopped matching them -- and an empty set would satisfy every "
            "assertion below it, so this raises instead.",
        )
        duplicates = sorted({rule for rule in found if found.count(rule) > 1})
        self.assertEqual(
            [],
            duplicates,
            f"these identifiers are defined more than once: {duplicates}. A citation to a duplicated "
            "identifier resolves to two different requirements, so at least one of them is "
            "uncitable. Give the newer rule the next free number in its section.",
        )

    def test_every_mentioned_identifier_resolves(self):
        """Repo-wide, because the citations worth protecting are the ones in OTHER documents."""
        text = t.read(STANDARD)
        known = defined_ids(text) | retired_ids(text)

        dangling = {}
        for path in repo_markdown():
            for rule in sorted(mentioned_ids(t.read(path)) - known):
                dangling.setdefault(rule, []).append(path.relative_to(t.REPO_ROOT).as_posix())

        self.assertEqual(
            {},
            dangling,
            "these identifiers are cited but are neither defined nor retired:\n  "
            + "\n  ".join(f"{rule}: cited in {', '.join(files)}" for rule, files in sorted(dangling.items()))
            + "\nA citation that resolves to nothing is the readable half of the failure. The "
            "unreadable half is a citation that resolves to the WRONG rule, which is what the "
            "history check prevents.",
        )

    def test_no_identifier_is_both_live_and_retired(self):
        text = t.read(STANDARD)
        both = sorted(defined_ids(text) & retired_ids(text))
        self.assertEqual(
            [],
            both,
            f"these identifiers are both defined and listed as retired: {both}. A reader following "
            "a citation gets a live requirement and a tombstone saying it is gone, with nothing to "
            "say which is current.",
        )


class NoIdentifierIsEverReused(unittest.TestCase):
    """The check the other three cannot make: what USED to be here.

    Everything above reads today's file, so it cannot tell a rule that never existed from one that
    was deleted last week and whose number is now free for the taking. This reads the history.
    """

    def test_every_identifier_ever_defined_is_still_live_or_retired(self):
        text = t.read(STANDARD)
        live = defined_ids(text)
        gone = retired_ids(text)
        history = ids_ever_defined()

        self.assertTrue(
            history,
            "no revision of the standard defined any identifier, so this check compared an empty "
            "set and would pass no matter what the file says. Find out why before trusting it.",
        )

        vanished = {rule: sha for rule, sha in sorted(history.items()) if rule not in live and rule not in gone}
        self.assertEqual(
            {},
            vanished,
            "these identifiers have existed and are now neither defined nor retired:\n  "
            + "\n  ".join(f"{rule} (last seen in {sha[:9]})" for rule, sha in vanished.items())
            + "\nAn identifier that simply disappears leaves its number free to be issued to a "
            "different rule, at which point every citation written against it -- including ones in "
            "registers this repository cannot see -- silently points at the wrong requirement. Add "
            "a row to `## Retired rules` saying what happened to it. Retiring costs one row.",
        )

        # RECEIPTS, reached only once nothing has vanished -- which is exactly when a count is
        # needed, because an empty `vanished` is also what a history walk that read nothing produces.
        self.assertGreaterEqual(
            len(history),
            len(live),
            f"history knows {len(history)} identifiers but the file defines {len(live)}. The walk "
            "read fewer revisions than the current one contains, so it is not reading what it "
            "thinks it is reading.",
        )


class TheChecksCanActuallyBite(unittest.TestCase):
    """Prove the instrument on both sides. A check that cannot fail is not a control.

    Each case mutates the standard's TEXT in memory -- never the file -- in the specific way the
    corresponding check exists to catch, and asserts the extraction sees it.
    """

    def test_a_duplicate_definition_is_visible_to_the_extractor(self):
        text = t.read(STANDARD)
        rule = sorted(defined_ids(text))[0]
        planted = text + f"\n| {rule} | A second rule wearing an identifier that is taken | none |\n"
        found = DEFINITION.findall(planted)
        self.assertGreater(
            found.count(rule),
            1,
            "a duplicated identifier was not seen twice by the definition pattern, so the duplicate "
            "check above cannot fire.",
        )

    def test_a_mention_in_another_document_is_seen(self):
        """The cross-file half. ADOPTING-THESE.md cites rules by identifier; this is what reaches it."""
        cited = mentioned_ids(t.read(t.REPO_ROOT / "docs" / "standards" / "ADOPTING-THESE.md"))
        self.assertTrue(
            cited,
            "ADOPTING-THESE.md cites no rule identifier. Either the citations were reverted to "
            "italicised section titles -- which no checker can see, and which is the failure this "
            "migration undid -- or the scan stopped reading them.",
        )
        self.assertTrue(
            cited <= defined_ids(t.read(STANDARD)) | retired_ids(t.read(STANDARD)),
            "a rule identifier cited in ADOPTING-THESE.md does not resolve, and the repo-wide case "
            "above should have caught it first. The two disagree, so one of them is broken.",
        )

    def test_a_dangling_identifier_is_not_mistaken_for_a_known_one(self):
        text = t.read(STANDARD)
        known = defined_ids(text) | retired_ids(text)
        self.assertNotIn(
            "SD-99.99",
            known,
            "an identifier that is in no table was reported as known, so the resolve check would "
            "accept a citation to anything.",
        )
        self.assertIn("SD-99.99", mentioned_ids("see SD-99.99 for details"))

    def test_a_retirement_is_read_only_from_the_retired_section(self):
        """A rule that merely discusses retirement must not register as retired."""
        text = t.read(STANDARD)
        live = sorted(defined_ids(text))[0]
        self.assertNotIn(
            live,
            retired_ids(text),
            f"{live} is a live rule and the retirement scan claimed it as a tombstone. The scan is "
            "reading outside the Retired rules section, so any prose mentioning an identifier would "
            "excuse that rule from existing.",
        )

    def test_the_history_walk_reads_more_than_the_working_tree(self):
        """The walk must read committed revisions, not re-read the file on disk."""
        history = ids_ever_defined()
        self.assertTrue(
            history,
            "the history walk found no identifier in any commit. If the rules were introduced in an "
            "as-yet-uncommitted change this is expected exactly once -- commit it, and this becomes "
            "the check that stops the numbers being reused.",
        )


if __name__ == "__main__":
    unittest.main()
