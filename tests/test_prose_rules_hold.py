"""The prose checker. Hard-fail where a violation is unambiguous, baselined ratchet everywhere else.

WHAT THIS EXISTS FOR. `docs/HOUSE-STYLE.md` states the writing rules and nothing enforced any of
them, so the only thing standing between the corpus and a slow drift back was whether a reviewer
happened to remember a rule identifier. This file enforces the subset that CAN be enforced and says
plainly which subset that is.

THE DESIGN RULE, taken from the writing plan and not negotiable here: hard-fail ONLY where a
violation is unambiguous and the current corpus is clean. A gate that reddens a legitimate editorial
choice is one people delete, and the repository already recorded that judgment once in
`test_docs_do_not_drift.TheBlufConventionHasOneSpelling`.

WHAT WAS MEASURED BEFORE CHOOSING, because the choice is the whole design. Every candidate pattern
was run over the corpus on 2026-08-08 and every hit was read:

  B-7  "cleanly", "elegantly", "robustly"      16 hits, ~0 genuine  -> NOT ENFORCED
  B-5  "in order to", "utilize", "leverage"    10 hits,  1 genuine  -> ENFORCED, narrowed
  B-3  "Importantly", "It is worth noting"      5 hits,  0 genuine  -> ENFORCED, narrowed
  B-10 a heading that is a question             1 hit,   0 genuine  -> NOT ENFORCED

B-7 IS THE INSTRUCTIVE ONE AND IT IS DELIBERATELY ABSENT. The rule bans those adverbs "describing
this project's own work". Measured, every single hit was standard technical vocabulary instead:
`git merges both cleanly`, `a session that exits cleanly`, `an execution-alias stub that resolves
cleanly`, `a transform producing valid-but-wrong output passes cleanly`. The distinction the rule
draws is about WHAT IS BEING DESCRIBED, and no pattern over the text can see that. Enforcing it would
redden sixteen correct sentences to catch nothing, so it stays a review item. The same reasoning
retires B-10: its one hit, `## The one question: does failing it stop the change?`, is a question the
section immediately answers, which is not the rhetorical opener the rule is about.

B-5 IS NARROWED TO THE UNAMBIGUOUS FORMS. Bare "leverage" is a noun as often as a verb here --
`ordered by its own leverage`, `the highest-leverage gate` -- so only the participles and the
unmistakable phrases are enforced. The one genuine violation the scan found, a cloud program that had
`begun leveraging an external framework`, was fixed in the same commit that added this file, because
a hard-fail rule whose corpus is already red is a rule that ships disabled.

THE RULE SHEET MUST BE ABLE TO QUOTE WHAT IT BANS. `docs/HOUSE-STYLE.md` lists every banned
construction verbatim in its own tables, so a naive scan reddens the one file that defines the rules.
The exemption is deliberately NARROW: a table row whose first cell is a rule identifier, and nothing
else. Exempting the whole file would leave the rule sheet the only unchecked prose in the repository.

WHAT IS REPORTED RATHER THAN FAILED, and why each is not a hard fail:

  cross-file duplication   HS-3, but which of two copies should go is an editorial call
  table cell word counts   fourteen files exceed 40 words per cell, SECURE-DEVELOPMENT among them
  long sentences           a cap at 30 fires on 1,397 of 6,579; the long tail carries the warnings

Each is a RATCHET against a baseline measured from the corpus. It may not get worse. If it gets
better the test says so and asks for the baseline to be lowered, because a ratchet nobody tightens is
a number that stops meaning anything.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import re
import subprocess
import unittest

import _ccxtest as t

# ---------------------------------------------------------------------------
# Corpus


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


def prose_files() -> list[str]:
    """Tracked markdown that is prose. Word copies are generated and are not edited."""
    return [
        f
        for f in tracked_files()
        if f.endswith(".md")
        and (f.startswith(("docs/", "README", "INSTALL")))
        and "/word/" not in f
    ]


RULE_ROW = re.compile(r"^\|\s*`?(?:B|HS|PD|OPEN|SD|CP)-\d+`?\s*\|")
FENCE = re.compile(r"^\s*(```|~~~)")


def scannable_lines(text: str) -> list[tuple[int, str]]:
    """Prose lines only: no code fences, and no rule-definition rows.

    The rule-row exemption is why HOUSE-STYLE.md can list "utilize" as a banned word without this
    file reddening on it. It matches ONLY a table row whose first cell is a rule identifier.
    """
    out: list[tuple[int, str]] = []
    inside = False
    for n, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            inside = not inside
            continue
        if inside or RULE_ROW.match(line):
            continue
        out.append((n, line))
    return out


def paragraphs(text: str) -> list[tuple[str, list[tuple[int, int]]]]:
    """Prose rejoined into paragraphs, each with an offset -> line map.

    THIS IS THE WHOLE REASON THE CHECKER WORKS. HS-14 wraps prose near 100 characters, so a sentence
    here is spread over three or four lines. Scanning line by line gets both halves wrong: no line
    ever reaches 30 words, so a sentence-length measure reports zero, and a line that happens to
    BEGIN with a wrapped "importantly" looks like a sentence opener when it is the middle of one.
    Both were observed before this was rewritten.

    Tables are excluded here and counted separately -- a table row is not prose and PD-4 protects it.
    """
    out: list[tuple[str, list[tuple[int, int]]]] = []
    current: list[tuple[int, str]] = []

    def flush() -> None:
        if not current:
            return
        parts: list[str] = []
        spans: list[tuple[int, int]] = []
        pos = 0
        for line_no, line in current:
            stripped = line.strip()
            if parts:
                pos += 1  # the space join() will insert
            spans.append((pos, line_no))
            parts.append(stripped)
            pos += len(stripped)
        out.append((" ".join(parts), spans))
        current.clear()

    inside = False
    for n, line in enumerate(text.split("\n"), 1):
        if FENCE.match(line):
            inside = not inside
            flush()
            continue
        stripped = line.strip()
        if inside or not stripped or stripped.startswith(("|", "#", ">")) or RULE_ROW.match(line):
            flush()
            continue
        current.append((n, line))
    flush()
    return out


def line_at(spans: list[tuple[int, int]], offset: int) -> int:
    """Map a character offset inside a joined paragraph back to its source line."""
    line_no = spans[0][1]
    for start, n in spans:
        if start <= offset:
            line_no = n
        else:
            break
    return line_no


# ---------------------------------------------------------------------------
# Hard fail. Every pattern here fires zero times on the corpus as committed.

BANNED = [
    (
        "B-3",
        'an opener whose only work is to announce that what follows matters. Write the note.',
        re.compile(r"(?:\A|(?<=[.!?] ))(?:Importantly|Notably)\b|\bIt (?:is worth noting|should be noted)\b", re.I),
    ),
    (
        "B-5",
        'padding. Write "use", "to", or "can".',
        re.compile(r"\bin order to\b|\bprovides? the (?:capability|ability) to\b|\butili[sz](?:e|es|ed|ing)\b|\bleverag(?:ing|ed)\b", re.I),
    ),
    (
        "B-6",
        "a sentence asserting its own significance. State the fact that makes it significant.",
        re.compile(r"\bthis is (?:important|significant|critical)\b|\bthe key (?:point|thing) (?:is|here)\b|\bcannot be overstated\b|\bworth emphasi[sz]ing\b", re.I),
    ),
]


class BannedConstructionsAreAbsent(unittest.TestCase):
    def test_no_tracked_page_carries_a_banned_construction(self):
        offenders = []
        for relpath in prose_files():
            text = t.read(t.REPO_ROOT / relpath)
            for joined, spans in paragraphs(text):
                for rule_id, why, pattern in BANNED:
                    for m in pattern.finditer(joined):
                        line_no = line_at(spans, m.start())
                        offenders.append(f"{relpath}:{line_no}: {rule_id} {m.group(0).strip()!r} -- {why}")
        self.assertEqual(
            [],
            offenders,
            "these pages carry a construction docs/HOUSE-STYLE.md bans:\n  "
            + "\n  ".join(offenders)
            + "\nOnly the unambiguous rules are enforced here. If you believe one of these is a false "
            "positive, that is a reason to narrow the pattern in this file and say why in the commit "
            "-- not a reason to add an exemption for your page.",
        )

    def test_the_scan_actually_reads_the_corpus(self):
        """The empty-match guard. A scan for absences passes trivially against an empty corpus."""
        files = prose_files()
        self.assertGreaterEqual(
            len(files),
            25,
            f"the prose scan found only {len(files)} pages. The absence check above would pass "
            "against an empty corpus while measuring nothing, so this is what makes it mean "
            "anything. If the docs really did shrink this far, lower the number deliberately.",
        )
        words = sum(len(t.read(t.REPO_ROOT / f).split()) for f in files)
        self.assertGreater(words, 50_000, f"only {words} words scanned; the corpus is ~170,000.")


class TheBannedPatternsCatchWhatTheyExistToCatch(unittest.TestCase):
    """Prove each pattern on a planted example, and prove it declines the near-neighbour.

    Without the negative half this class would pass against a pattern that matches everything.
    """

    PLANTED = [
        ("B-3", "Importantly, the gate is advisory."),
        ("B-3", "It is worth noting that the hook is unwired."),
        ("B-5", "The installer exists in order to write a shim."),
        ("B-5", "The script will utilize the registry."),
        ("B-5", "One program has begun leveraging an external framework."),
        ("B-6", "This is important: the gate is advisory."),
    ]

    # Every one of these appears in the corpus today, or is the near-miss the pattern must decline.
    ACCEPTED = [
        "Git merges both cleanly, and nothing in the graph can see it.",
        "A session that exits cleanly unlinks its registry file.",
        "The rows are ordered by its own leverage.",
        "The highest-leverage gate to build first.",
        "A version pin does not satisfy it, and more importantly does not satisfy the property.",
        "The one question: does failing it stop the change?",
    ]

    def test_each_pattern_fires_on_its_planted_example(self):
        for rule_id, planted in self.PLANTED:
            pattern = next(p for r, _, p in BANNED if r == rule_id)
            self.assertTrue(
                pattern.search(planted),
                f"{rule_id} did not fire on {planted!r}; the rule is unenforced.",
            )

    def test_no_pattern_fires_on_prose_the_corpus_legitimately_uses(self):
        for accepted in self.ACCEPTED:
            for rule_id, _, pattern in BANNED:
                m = pattern.search(accepted)
                if m is not None:
                    self.fail(
                        f"{rule_id} fired on {accepted!r}, matching {m.group(0)!r}. That sentence is "
                        "correct prose from this corpus, so the pattern is too wide and would redden "
                        "a legitimate page."
                    )

    def test_a_rule_definition_row_is_exempt_but_the_rest_of_the_page_is_not(self):
        """HOUSE-STYLE.md must be able to name what it bans, without becoming unscannable."""
        text = "| B-5 | \"in order to\", \"utilize\" | \"to\", \"use\" |\nThe installer runs in order to help."
        lines = scannable_lines(text)
        self.assertEqual(
            [2],
            [n for n, _ in lines],
            "the rule-row exemption should skip the table row and keep the prose line. Skipping "
            "more than the row would leave the rule sheet unchecked.",
        )


# ---------------------------------------------------------------------------
# Reported, and ratcheted. These may not get worse.

# Measured on 2026-08-08 against the corpus at that commit, over 110,092 words of prose in 34 files.
# To change one, run the test: it names the current figure and which direction it moved.
#
# These are lower than the figures in the writing plan (which counted 1,397 long sentences) because
# that count included headings, table rows and block quotes. This one is prose only, for the same
# reason PD-4 exists: a table row is not a sentence and shortening it is not an improvement.
BASELINE_LONG_SENTENCES = 833       # sentences over 30 words
BASELINE_FAT_TABLE_CELLS = 49       # table cells over 40 words

# How far below baseline a metric may drift before the test asks for the baseline to be lowered.
# Sized to each metric rather than shared: 40 is noise against 833 and most of the way to zero
# against 49.
LONG_SENTENCE_SLACK = 40
FAT_CELL_SLACK = 8

SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")


def _measure() -> tuple[int, int, int]:
    """(sentences over 30 words, table cells over 40 words, words examined)."""
    long_sentences = 0
    fat_cells = 0
    words = 0
    for relpath in prose_files():
        text = t.read(t.REPO_ROOT / relpath)
        for joined, _ in paragraphs(text):
            words += len(joined.split())
            for sentence in SENTENCE_SPLIT.split(joined):
                if len(sentence.split()) > 30:
                    long_sentences += 1
        for line_no, line in scannable_lines(text):
            stripped = line.strip()
            if not stripped.startswith("|"):
                continue
            for cell in stripped.strip("|").split("|"):
                if len(cell.split()) > 40:
                    fat_cells += 1
    return long_sentences, fat_cells, words


class TheReportedMetricsDoNotRegress(unittest.TestCase):
    """A ratchet, not a cap. The plan rejected all three as hard fails, with the measurement."""

    def test_it_reports_what_it_examined(self):
        long_sentences, fat_cells, words = _measure()
        self.assertGreater(
            words,
            50_000,
            f"the metric pass examined {words} words of prose, which is too few to have read the "
            "corpus. A measurement over nothing reports zero and reads like a pass.",
        )
        self.assertGreater(
            long_sentences,
            0,
            "zero sentences over 30 words is not credible for this corpus and means the paragraph "
            "rejoin has broken. It reported exactly this before the line-based scan was replaced.",
        )

    def test_long_sentences_do_not_increase(self):
        long_sentences, _, _ = _measure()
        self.assertLessEqual(
            long_sentences,
            BASELINE_LONG_SENTENCES,
            f"{long_sentences} sentences now exceed 30 words, against a baseline of "
            f"{BASELINE_LONG_SENTENCES}. This is not a cap -- the long tail of this corpus is where "
            "the engineering warnings live -- but it may not grow.",
        )
        self.assertGreater(
            long_sentences,
            BASELINE_LONG_SENTENCES - LONG_SENTENCE_SLACK,
            f"only {long_sentences} long sentences remain, against a baseline of "
            f"{BASELINE_LONG_SENTENCES}. Lower BASELINE_LONG_SENTENCES to {long_sentences} in this "
            "file. A ratchet nobody tightens stops measuring anything.",
        )

    def test_fat_table_cells_do_not_increase(self):
        _, fat_cells, _ = _measure()
        self.assertLessEqual(
            fat_cells,
            BASELINE_FAT_TABLE_CELLS,
            f"{fat_cells} table cells now exceed 40 words, against a baseline of "
            f"{BASELINE_FAT_TABLE_CELLS}. PD-4 forbids solving this by converting a table to prose.",
        )
        self.assertGreater(
            fat_cells,
            BASELINE_FAT_TABLE_CELLS - FAT_CELL_SLACK,
            f"only {fat_cells} fat table cells remain, against a baseline of "
            f"{BASELINE_FAT_TABLE_CELLS}. Lower BASELINE_FAT_TABLE_CELLS to {fat_cells}.",
        )


if __name__ == "__main__":
    unittest.main()
