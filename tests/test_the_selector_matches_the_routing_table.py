"""Pin the interactive standards selector against the documents it claims to agree with.

THE FAILURE THIS EXISTS FOR, and it is the highest-probability defect in the whole feature. The
selector's facts live in docs/_data/standards_selector.yml. The same facts live again in
docs/standards/STANDARDS-REFERENCE.md, because the markdown and the Word copy have to stand alone --
a reader who downloaded the .docx cannot run a web app. Two copies of one fact diverge silently, and
this repository has been bitten by exactly that shape before: the install block existed in three
copies and drifted, which is why tests/test_docs_do_not_drift.py exists, and the Word copies drifted
inside a single session, which is why tests/test_word_copies_track_the_markdown.py exists.

The drift here would be invisible in a way those were not. Both halves keep rendering perfectly. The
app shows one status, the printed table shows another, and the app is the one people will trust.

THE SECOND FAILURE, and it is the reason a test had to exist at all rather than being nice to have.
NOTHING IN tests/ BUILDS THE JEKYLL SITE. The app reaches the page through an HTML-comment sentinel
in the markdown that _layouts/default.html splits on. If somebody reformats that line, or the layout
stops looking for it, the app silently stops appearing and every gate in .github/workflows/gates.yml
stays green. A silent failure with a green run is the exact thing this repository's culture refuses
to accept as evidence, so the sentinel is pinned on both sides here.

WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves the two copies name the same items and carry the
same status strings; that every trigger token in the data resolves to a question and an option that
exist; that the sentinel string is identical in the markdown and in the layout; that the app fetches
nothing from outside the site; and that its result vocabulary carries no verdict. It does NOT build
the site, does not execute the JavaScript, and cannot tell you the app renders correctly in a
browser. Treat a pass as "the two documents agree and the wiring is declared", not "the feature
works" -- load the page and look at it before believing that.

WHY THE YAML IS SCANNED WITH A LINE READER RATHER THAN A YAML LIBRARY. The rest of tests/ is
standard library only, and PyYAML is not in it. So the extraction is deliberately narrow: it reads
the handful of keys this file pins, in the exact shapes docs/_data/standards_selector.yml uses, and
RAISES when it finds nothing rather than returning an empty set for a caller to compare against
another empty set. TheScansCanSeeWhatTheyLookFor below proves each extractor on a planted example,
because a pattern that silently matches nothing passes everything.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

DATA = t.REPO_ROOT / "docs" / "_data" / "standards_selector.yml"
INCLUDE = t.REPO_ROOT / "docs" / "_includes" / "standards-selector.html"
LAYOUT = t.REPO_ROOT / "docs" / "_layouts" / "default.html"
GUIDE = t.REPO_ROOT / "docs" / "standards" / "STANDARDS-LANDSCAPE.md"
REFERENCE = t.REPO_ROOT / "docs" / "standards" / "STANDARDS-REFERENCE.md"

SENTINEL = "<!-- STANDARDS-SELECTOR -->"

# The vocabulary the selector is forbidden to use, per the no-verdict boundary. The soft form is the
# dangerous one, because it survives review: a list under a heading like "your applicable standards"
# is a verdict even when every sentence inside it is conditional. So the headings are banned here
# alongside the verbs.
VERDICT_WORDS = (
    r"you must\b",
    r"you are required\b",
    r"applies to you\b",
    r"you are in scope\b",
    r"\bnon-compliant\b",
    r"\bcompliant\b",
    r"your obligations\b",
    r"your applicable\b",
)

# Anything that would leave the origin. The site ships no CDN, no font, no analytics and no fetch,
# and a file:// copy of the built page has to keep working -- both of which a single well-meaning
# script tag would end.
OFFSITE = re.compile(r"""(?:src|href)\s*=\s*["']\s*(?:https?:)?//""", re.IGNORECASE)
NETWORK_CALLS = re.compile(r"\b(?:fetch|XMLHttpRequest|WebSocket|importScripts|EventSource)\s*\(")
STORAGE_CALLS = re.compile(r"\b(?:localStorage|sessionStorage|document\.cookie)\b")


def squash(text: str) -> str:
    """Collapse runs of whitespace, so a wrapped YAML block scalar compares against a table cell.

    The YAML statuses are folded blocks (`>-`), which join their lines with single spaces. The
    markdown carries the same sentence on one long table row. Without this, every multi-line status
    would report as drift that is not there.
    """
    return re.sub(r"\s+", " ", text).strip()


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def read_items() -> list[dict]:
    """Every item in the data file, as {id, name, status, tier, group, triggers}.

    Narrow on purpose: it understands the two shapes this file actually uses for a scalar -- a
    quoted value on the key's own line, and a folded block (`>-`) whose continuation lines are
    indented further -- and nothing else. A third shape appearing in the data would come back
    missing a field, and the assertions below name it rather than passing quietly.
    """
    lines = t.read(DATA).splitlines()
    section = None
    items: list[dict] = []
    current: dict | None = None
    index = 0

    while index < len(lines):
        line = lines[index]
        index += 1
        if line and not line[0].isspace() and line.rstrip().endswith(":"):
            section = line.split(":", 1)[0].strip()
            continue
        if section != "items":
            continue

        start = re.match(r"^  - id:\s*(\S+)\s*$", line)
        if start:
            current = {"id": _unquote(start.group(1)), "triggers": []}
            items.append(current)
            continue
        if current is None:
            continue

        field = re.match(r"^    (name|status|tier|group|triggers):\s*(.*)$", line)
        if not field:
            continue
        key, value = field.group(1), field.group(2).strip()

        if key == "triggers":
            current["triggers"] = re.findall(r'"([^"]+)"', value)
            continue
        if value == ">-" or value == ">":
            block = []
            while index < len(lines):
                nxt = lines[index]
                if nxt.strip() and not nxt.startswith("      "):
                    break
                block.append(nxt.strip())
                index += 1
            current[key] = squash(" ".join(block))
            continue
        current[key] = _unquote(value)

    if not items:
        raise AssertionError(
            f"no items parsed out of {DATA.name}. The scan found nothing, which would make every "
            "case in this file vacuously true. Fix the reader before trusting a green run."
        )
    return items


def read_option_tokens() -> set[str]:
    """Every `<question>=<option>` token the questions declare."""
    lines = t.read(DATA).splitlines()
    section = None
    question = None
    tokens: set[str] = set()

    for line in lines:
        if line and not line[0].isspace() and line.rstrip().endswith(":"):
            section = line.split(":", 1)[0].strip()
            continue
        if section != "questions":
            continue
        outer = re.match(r"^  - id:\s*(\S+)\s*$", line)
        if outer:
            question = _unquote(outer.group(1))
            continue
        option = re.match(r"^      - id:\s*(\S+)\s*$", line)
        if option and question:
            tokens.add(f"{question}={_unquote(option.group(1))}")

    if not tokens:
        raise AssertionError(
            f"no question options parsed out of {DATA.name}. Every trigger below would then "
            "resolve against an empty set and the case would pass for the wrong reason."
        )
    return tokens


class TheTwoCopiesOfTheFactsAgree(unittest.TestCase):
    def test_every_item_in_the_data_is_named_in_the_reference_table(self):
        reference = squash(t.read(REFERENCE))
        missing = [i["name"] for i in read_items() if squash(i["name"]) not in reference]
        self.assertEqual(
            [],
            missing,
            "the selector names items the reference table does not:\n  "
            + "\n  ".join(missing)
            + f"\nBoth are published. Add the row to {REFERENCE.name}, or drop the item from "
            f"{DATA.name}, in the same commit -- and regenerate the Word copy.",
        )

    def test_every_status_in_the_data_appears_verbatim_in_the_reference_table(self):
        """The load-bearing direction. A status is the page's strongest asset and its most
        perishable one, so the two copies have to say the same words, not merely name the same
        document."""
        reference = squash(t.read(REFERENCE))
        drifted = []
        for item in read_items():
            status = item.get("status")
            if not status:
                drifted.append(f"{item['id']}: no status parsed at all")
                continue
            if squash(status) not in reference:
                drifted.append(f"{item['id']}: {status}")
        self.assertEqual(
            [],
            drifted,
            "these statuses differ between the selector data and the reference table:\n  "
            + "\n  ".join(drifted)
            + "\nA reader who ran the app and a reader who printed the table would be told "
            "different things, and the app is the one they will trust. Edit both, then regenerate "
            "the Word copy.",
        )

    def test_the_guide_carries_the_same_names_and_the_same_statuses(self):
        """The guide holds its own copy of the reference table, so it is a THIRD copy of one fact.

        It is allowed to exist for the reason the second one is: a reader holding the Word copy of
        the guide cannot run a web app and cannot open a sibling file either, so the guide has to be
        complete on its own. But three copies drift faster than two, and this one would drift
        silently in exactly the same way -- the app, the reference file and the printed guide all
        rendering perfectly while saying different things about the same date.
        """
        guide = squash(t.read(GUIDE))
        drifted = []
        for item in read_items():
            if squash(item["name"]) not in guide:
                drifted.append(f"{item['id']}: name is not in the guide at all")
                continue
            if squash(item["status"]) not in guide:
                drifted.append(f"{item['id']}: {item['status']}")
        self.assertEqual(
            [],
            drifted,
            "the guide's own reference table disagrees with the selector data:\n  "
            + "\n  ".join(drifted)
            + f"\nEdit {DATA.name}, {REFERENCE.name} and {GUIDE.name} in the same commit, then "
            "regenerate both Word copies. If the guide deliberately stopped carrying the table, "
            "delete this case rather than leaving it to fail.",
        )

    def test_every_status_is_present_and_the_checked_date_is_stated_once(self):
        items = read_items()
        bare = [i["id"] for i in items if not i.get("status")]
        self.assertEqual(
            [],
            bare,
            f"items with no status: {bare}. An item may never render as a bare name -- if it "
            "appears, its status and the date that status was checked appear with it.",
        )
        date = re.search(r'^checked:\s*"(\d{4}-\d{2}-\d{2})"', t.read(DATA), re.M)
        self.assertIsNotNone(date, "the data file declares no `checked:` date for the statuses.")
        self.assertIn(
            date.group(1),
            t.read(REFERENCE),
            "the reference table does not carry the date the statuses were checked. A status "
            "without its date is the failure this whole page argues against.",
        )
        self.assertIn(
            f"Status, checked {{{{ d.checked }}}}",
            t.read(INCLUDE),
            "the item card no longer prints the checked date beside the status. Restore it: the "
            "date is not decoration, it is what makes the status readable a year from now.",
        )


class TheTriggersResolve(unittest.TestCase):
    def test_every_trigger_names_a_question_and_an_option_that_exist(self):
        tokens = read_option_tokens()
        dangling = []
        for item in read_items():
            if not item["triggers"]:
                dangling.append(f"{item['id']}: no triggers at all, so it can never surface")
            for token in item["triggers"]:
                if token == "ALWAYS":
                    continue
                if token not in tokens:
                    dangling.append(f"{item['id']}: {token}")
        self.assertEqual(
            [],
            sorted(dangling),
            "these triggers name a question or an option that does not exist:\n  "
            + "\n  ".join(sorted(dangling))
            + "\nA dangling trigger does not error anywhere. The item simply never appears, and "
            "the result looks complete while being short by one document.",
        )

    def test_every_substantive_option_can_surface_something(self):
        """An option nobody routes on is a control that does nothing when ticked.

        The exceptions are declared IN THE DATA rather than listed here, so adding one is a visible
        edit to the file the reader can also see: `widens` options contribute the union of their
        siblings and route nothing themselves, and `selects_nothing` options are definite answers
        that surface no item on purpose.
        """
        text = t.read(DATA)
        used = set()
        for item in read_items():
            used.update(item["triggers"])

        inert = []
        section = None
        question = None
        option = None
        flagged = False
        for line in text.splitlines() + ["END:"]:
            if line and not line[0].isspace() and line.rstrip().endswith(":"):
                section = line.split(":", 1)[0].strip()
                continue
            if section != "questions":
                continue
            outer = re.match(r"^  - id:\s*(\S+)\s*$", line)
            if outer:
                question = _unquote(outer.group(1))
            new_option = re.match(r"^      - id:\s*(\S+)\s*$", line)
            if new_option or outer:
                if option and not flagged and option not in used:
                    inert.append(option)
                option = f"{question}={_unquote(new_option.group(1))}" if new_option else None
                flagged = False
            if re.match(r"^        (widens|selects_nothing):\s*true\s*$", line):
                flagged = True
        if option and not flagged and option not in used:
            inert.append(option)

        self.assertEqual(
            [],
            sorted(inert),
            "these options surface no item and are not declared as widening or as definite-empty:\n  "
            + "\n  ".join(sorted(inert))
            + "\nA checkbox that changes nothing when ticked is a control that reads as broken.",
        )

    def test_the_sector_instrument_can_never_stand_alone(self):
        """A deidentification rule, not a presentation one.

        One instrument in the data is marked `never_alone`. A result in which it is the only named
        member of its group would identify the author's sector, so the renderer forces companions
        in. That is only possible while the companions exist and the group is large enough to
        satisfy the rule, which is what this pins.
        """
        items = read_items()
        text = t.read(DATA)
        marked = re.findall(r"^    never_alone:\s*(\S+)\s*$", text, re.M)
        self.assertNotEqual(
            [],
            marked,
            "no item is marked `never_alone` any more. If the marking was removed, the sector "
            "instrument can now render as the only named instrument in a result, which is a "
            "deidentification failure rather than a styling one.",
        )
        companions = re.findall(r"^    never_alone_companions:\s*\[(.+)\]\s*$", text, re.M)
        self.assertNotEqual([], companions, "the never-alone item declares no companions to force in.")
        by_id = {i["id"]: i for i in items}
        for raw in companions:
            for cid in re.findall(r'"([^"]+)"', raw):
                self.assertIn(
                    cid,
                    by_id,
                    f"companion '{cid}' does not exist, so the never-alone rule cannot be "
                    "satisfied and the item would render alone.",
                )
        for group in marked:
            peers = [i for i in items if i.get("group") == group]
            self.assertGreaterEqual(
                len(peers),
                3,
                f"group '{group}' has {len(peers)} members. The rule needs at least three so the "
                "instrument is always one member of a set.",
            )


class TheWiringIsDeclaredOnBothSides(unittest.TestCase):
    def test_the_sentinel_is_in_the_markdown_exactly_once(self):
        guide = t.read(GUIDE)
        self.assertEqual(
            1,
            guide.count(SENTINEL),
            f"{GUIDE.name} carries the selector sentinel {guide.count(SENTINEL)} times. It has to "
            "appear exactly once: none means the app never renders, and more than one means the "
            "layout's split puts the document back together in the wrong order.",
        )

    def test_the_layout_splits_on_the_same_string(self):
        self.assertIn(
            SENTINEL,
            t.read(LAYOUT),
            f"{LAYOUT.name} no longer splits on the sentinel that {GUIDE.name} carries. Nothing "
            "errors when these disagree -- the page just ships without the app, and every gate "
            "stays green. That is why this case exists.",
        )

    def test_the_layout_still_renders_pages_that_have_no_sentinel(self):
        """Twenty other pages go through this split. The absent case has to be identity."""
        layout = t.read(LAYOUT)
        self.assertRegex(
            layout,
            r"\{%-?\s*else\s*-?%\}\s*\{\{\s*content\s*\}\}",
            "the layout no longer has a plain {{ content }} branch for pages without the "
            "sentinel. Every other page on the site renders through here.",
        )

    def test_the_include_exists_and_the_data_file_is_what_it_reads(self):
        include = t.read(INCLUDE)
        self.assertIn(
            "site.data.standards_selector",
            include,
            "the include no longer reads docs/_data/standards_selector.yml. If facts moved into "
            "the markup, the one-place rule is gone and the pins above are checking a file "
            "nothing renders.",
        )

    def test_the_stylesheet_no_longer_claims_the_site_runs_no_scripts(self):
        """A false comment about a control is the defect these documents are about.

        docs/assets/style.css asserted "no scripts" twice, and one of those was a live technical
        dependency rather than a boast: wide tables are made to scroll by the table element itself
        BECAUSE no script was available to wrap them.
        """
        css = t.read(t.REPO_ROOT / "docs" / "assets" / "style.css")
        # The two phrasings that became false, quoted exactly rather than matched loosely. A loose
        # "no script" pattern would also fire on the narrow-screen nav comment, which is still true
        # and still worth keeping -- and a scan that fails on correct prose trains people to ignore
        # it.
        for stale in ("no CDN, no scripts", "no script runs on this site"):
            self.assertNotIn(
                stale,
                css,
                f"the stylesheet still says '{stale}'. One page now runs a script "
                f"({INCLUDE.name}). Correct the comment in the same commit that makes it false -- "
                "a false comment about a control is the defect these documents are about.",
            )
        self.assertIn(
            "standards-selector",
            css,
            "the stylesheet does not mention the component that made its 'no scripts' claim false. "
            "Say where the exception is, so the next reader does not have to find it.",
        )


class TheAppKeepsInsideItsBoundary(unittest.TestCase):
    def test_the_result_vocabulary_issues_no_verdict(self):
        offenders = []
        for path in (INCLUDE, DATA):
            text = t.read(path)
            for number, line in enumerate(text.splitlines(), start=1):
                for pattern in VERDICT_WORDS:
                    if re.search(pattern, line, re.IGNORECASE):
                        offenders.append(f"{path.name}:{number}: {line.strip()}")
        self.assertEqual(
            [],
            offenders,
            "the selector uses verdict vocabulary:\n  "
            + "\n  ".join(offenders)
            + "\nThe permitted verb is 'may reach you', and every item states what to check next. "
            "The soft forms matter most, because they survive review.",
        )

    def test_the_boundary_lines_are_in_the_result_and_not_in_a_footnote(self):
        include = t.read(INCLUDE)
        for marker in ("boundary.no_legal_advice", "boundary.not_complete"):
            self.assertIn(
                marker,
                include,
                f"the result panel no longer renders {marker}. Both lines belong in the visible "
                "result, above the first item -- a boundary a reader has to go looking for is "
                "decoration.",
            )
        self.assertIn(
            "not_on_this_map",
            include,
            "the permanent 'Not on this map' card is gone. A selector that returns a list asserts "
            "completeness by its shape, and naming what the instrument cannot see is the only "
            "defeat of that reading which survives a reader who stopped reading disclaimers.",
        )
        self.assertIn(
            "at least",
            t.read(DATA),
            "the data no longer carries an 'at least' qualifier anywhere. A bare count is a "
            "completeness claim with a handle on it.",
        )

    def test_the_app_fetches_nothing_and_stores_nothing(self):
        include = t.read(INCLUDE)
        offsite = OFFSITE.findall(include)
        self.assertEqual(
            [],
            offsite,
            "the include references an off-origin resource. Everything has to be inline: there is "
            "no CDN on this site, and a saved file:// copy of the built page has to keep running.",
        )
        self.assertIsNone(
            NETWORK_CALLS.search(include),
            "the app makes a network call. It is a client-side filter over data already in the "
            "page, and it has to stay one.",
        )
        self.assertIsNone(
            STORAGE_CALLS.search(include),
            "the app touches storage. State lives in the query string and nowhere else, which is "
            "what makes the privacy sentence in the results literally true -- and on a shared "
            "managed desktop, storage would leak one reader's business profile to the next.",
        )

    def test_no_absence_sentence_is_visible_before_the_reader_has_said_anything(self):
        """The served HTML must not claim an absence, and this shipped claiming three.

        Each result block carries an "empty" sentence -- "nothing mapped here binds you directly",
        "nothing else surfaced". Those were emitted UNHIDDEN and only hidden later by the script, so
        the no-JavaScript page, which is the baseline this whole feature rests on, printed a
        clearance notice directly above the thirty-seven cards that contradicted it. An absence is
        only ever true relative to an answer, so the markup may not assert one and the script has to
        be what reveals it.

        The same rule covers a block with no resting occupants: shipping its heading and its
        introduction over nothing says the reader was told something when they were not.
        """
        include = t.read(INCLUDE)

        naked = [
            tag
            for tag in re.findall(r"<p class=\"ssel-empty\"[^>]*>", include)
            if not re.search(r"\shidden(\s|>)", tag)
        ]
        self.assertEqual(
            [],
            naked,
            "an empty-block sentence ships visible:\n  "
            + "\n  ".join(naked)
            + "\nIt has to carry `hidden` in the markup and be revealed by the script, which is the "
            "only thing that knows whether the reader has answered anything.",
        )
        self.assertRegex(
            include,
            r"empty\.hidden\s*=",
            "nothing in the script reveals an empty-block sentence any more, so a reader who "
            "narrows to nothing is shown an empty block with no explanation.",
        )
        self.assertRegex(
            include,
            r"<section class=\"ssel-block\"[^>]*\{%\s*if block\.starts_hidden\s*%\} hidden\{%\s*endif\s*%\}",
            "the block markup no longer honours `starts_hidden`. A block with no resting cards then "
            "ships as a heading and an introduction standing over nothing.",
        )
        self.assertGreaterEqual(
            len(re.findall(r"^    starts_hidden:", t.read(DATA), re.M)),
            1,
            "no block declares `starts_hidden`. Both blocks that have no resting occupants need "
            "it; if the resting arrangement genuinely changed, say so here rather than deleting "
            "the case.",
        )

    def test_the_absence_scan_can_see_a_sentence_that_ships_visible(self):
        """Prove the instrument. A pattern that matches nothing passes everything."""
        planted = '<p class="ssel-empty" id="ssel-empty-a">Nothing binds you.</p>'
        self.assertEqual(
            [],
            [
                tag
                for tag in re.findall(r"<p class=\"ssel-empty\"[^>]*>", planted)
                if re.search(r"\shidden(\s|>)", tag)
            ],
            "the scan reported a hidden attribute on markup that has none",
        )
        guarded = '<p class="ssel-empty" id="ssel-empty-a" hidden>Nothing binds you.</p>'
        self.assertEqual(
            1,
            len(
                [
                    tag
                    for tag in re.findall(r"<p class=\"ssel-empty\"[^>]*>", guarded)
                    if re.search(r"\shidden(\s|>)", tag)
                ]
            ),
            "the scan cannot see a hidden attribute that IS there, so the case above would fail on "
            "correct markup and get deleted.",
        )

    def test_the_controls_ship_hidden_so_no_js_never_means_inert_controls(self):
        include = t.read(INCLUDE)
        self.assertRegex(
            include,
            r'<form[^>]*id="ssel-form"[^>]*\shidden>',
            "the panel no longer ships with `hidden`. Without it, a reader whose JavaScript is off "
            "gets a row of checkboxes that do nothing -- which is worse than no controls at all, "
            "because a control that does not respond is a bug report rather than a graceful "
            "degradation.",
        )
        self.assertIn(
            "form.hidden = false",
            include,
            "nothing un-hides the panel, so the controls would never appear at all.",
        )
        self.assertIn(
            "<noscript>",
            include,
            "the no-JavaScript path says nothing. It has to say where the same answer is, because "
            "the page is complete without the app and the reader cannot tell.",
        )


class TheScansCanSeeWhatTheyLookFor(unittest.TestCase):
    """Prove each instrument on a planted example. A pattern that matches nothing passes
    everything, and every extractor here is the kind that stops matching after an innocuous
    reformat of the file it reads."""

    def test_the_item_reader_finds_a_real_item_and_folds_its_status(self):
        items = read_items()
        by_id = {i["id"]: i for i in items}
        self.assertIn(
            "cwe",
            by_id,
            "the item reader lost a known item id. It is reading the file's shape, so a "
            "reindent breaks it silently.",
        )
        self.assertGreaterEqual(
            len(items),
            20,
            f"only {len(items)} items parsed. The data file carries far more than that, so the "
            "reader is dropping most of them and every comparison above is running on a fragment.",
        )
        folded = by_id["eu-cra"]["status"]
        self.assertIn(
            "the main body of obligations from 2027-12-11",
            folded,
            "the folded-block reader dropped the continuation lines of a multi-line status, so "
            "every long status would compare as drift.",
        )

    def test_the_status_comparison_can_see_a_status_that_is_not_in_the_reference(self):
        reference = squash(t.read(REFERENCE))
        real = squash(read_items()[0]["status"])
        self.assertIn(real, reference, "a status that IS in the reference was not found")
        self.assertNotIn(
            "Withdrawn on a date that does not exist", reference, "the comparison is not comparing"
        )

    def test_the_verdict_patterns_match_the_wording_they_exist_to_catch(self):
        for planted in ("This standard applies to you.", "You must comply.", "Your obligations are:"):
            self.assertTrue(
                any(re.search(p, planted, re.IGNORECASE) for p in VERDICT_WORDS),
                f"no verdict pattern fired on {planted!r}. The ban is unenforced.",
            )
        allowed = "This may reach you, and here is what to check next."
        self.assertFalse(
            any(re.search(p, allowed, re.IGNORECASE) for p in VERDICT_WORDS),
            "a verdict pattern fires on the permitted wording, so the fix could not make it green.",
        )

    def test_the_offsite_pattern_matches_a_real_cdn_reference(self):
        self.assertNotEqual(
            [], OFFSITE.findall('<script src="https://cdn.example.invalid/x.js"></script>')
        )
        self.assertEqual([], OFFSITE.findall('<a href="STANDARDS-REFERENCE.html#x">ref</a>'))

    def test_the_option_reader_finds_the_questions(self):
        tokens = read_option_tokens()
        self.assertIn("role=software", tokens)
        self.assertIn("ai_assist=unknown", tokens)
        self.assertNotIn("role=nonexistent", tokens)


if __name__ == "__main__":
    unittest.main()
