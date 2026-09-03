"""The controls prove each check against a FIXTURE. This file proves them against real corpora.

THE BLIND SPOT THIS CLOSES. `run-checks.ps1` fires every check at a broken fixture and a clean one
and reports PROVEN when both answer correctly. That word covers the verdict logic and nothing else,
because a fixture is a directory of hand-written JSON, or a tab-separated list of refs, and neither
goes near the code that reads a real machine. An instrument mutated so it can never report a
collision on real data still reads PROVEN across all five checks.

Three defects lived in exactly that gap, and each one is a case below:

  * `Get-CcxRenderedIds` returned a HashSet into the pipeline, so PowerShell unrolled it and the
    function had three different return types by receipt count. Every message fixture holds exactly
    one receipt -- the single count where the wrong type happens to give the right answer.
  * A 'Z' timestamp came back Kind=Utc and was compared against a local `Get-Date`. Every fixture
    timestamp is eight months stale, so no offset on earth could flip its verdict.
  * The index-row exclusion allowed one undeclared path. No fixture supplies an index file at all,
    so that branch never ran.

WHAT THESE CASES DO DIFFERENTLY. They build the corpus the check will actually meet: a mail root on
disk with a chosen number of receipts, and a real git repository with two branches. That is the
cheapest repair the review named, and either half of it would have caught one of the three.
"""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

VALIDATION = t.REPO_ROOT / "scripts" / "validation"
TIMEOUT_SECONDS = 240

GIT_ID = [
    "-c", "user.name=ccx tests", "-c", "user.email=tests@example.invalid",
    "-c", "commit.gpgsign=false",
]

#: Old enough that no settle window and no machine offset can rescue it.
LONG_AGO = "2026-01-01T09:00:00.0000000Z"


class ValidationCase(unittest.TestCase):
    """Runs a check against a corpus this file built, and returns the receipt."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the checks cannot be executed here")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-realdata-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def check(self, script: str, *args: str) -> tuple[dict, int]:
        proc = subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(VALIDATION / script), *args, "-Json"],
            capture_output=True, text=True, encoding="utf-8",
            timeout=TIMEOUT_SECONDS, cwd=str(t.REPO_ROOT),
        )
        self.assertTrue(
            (proc.stdout or "").strip(),
            f"{script} printed no receipt at all (exit {proc.returncode}). It threw before it could "
            f"report, which renders in the runner as a measurement:\n{proc.stderr}",
        )
        try:
            receipt = json.loads(proc.stdout)
        except json.JSONDecodeError as exc:
            raise AssertionError(
                f"{script} did not print a JSON receipt ({exc}).\n"
                f"stdout:\n{proc.stdout[:600]}\nstderr:\n{proc.stderr[:600]}"
            ) from None
        return receipt, proc.returncode

    def lane(self, name: str, messages: list[dict], receipts: list[dict]) -> Path:
        """A mail root with one box, holding exactly the messages and receipts asked for."""
        root = self.base / name
        box = root / "wt-a"
        box.mkdir(parents=True)
        for m in messages:
            (box / f"{m['id']}.json").write_text(json.dumps(m, indent=2), encoding="utf-8")
        if receipts:
            (box / "receipts").mkdir()
            for r in receipts:
                (box / "receipts" / f"rcpt-{r['id']}.json").write_text(
                    json.dumps(r, indent=2), encoding="utf-8")
        return root

    @staticmethod
    def message(mid: str, sent: str = LONG_AGO, ttl: int = 30) -> dict:
        return {"id": mid, "to": "wt-a", "sentAt": sent, "ttlMinutes": ttl, "body": "built by a test"}

    @staticmethod
    def receipt(mid: str) -> dict:
        return {"id": mid, "renderedAt": LONG_AGO, "note": "built by a test"}


class TheReceiptSetIsASetOnEveryCorpus(ValidationCase):
    """One function returned three types by receipt count, and each type answered differently."""

    def test_a_lane_with_no_receipts_is_measured_rather_than_crashed(self):
        """Zero receipts is the DEAD DRAIN -- the exact shape this signal exists to catch.

        `return $set` on an empty HashSet unrolls to $null, so `$rendered.Contains($id)` threw
        InvokeMethodOnNull at line 84. Exit 1 is the BROKEN code, so the runner printed
        `message-delivery BROKEN` with no receipt, no corpus and no finding: a crash rendered as a
        measurement. The check's own note about a dead drain sits below the loop and was
        unreachable.
        """
        root = self.lane("dead-drain", [self.message("msg-lost")], [])

        for script in ("check-message-delivery.ps1", "check-message-expiry.ps1"):
            with self.subTest(check=script):
                receipt, code = self.check(script, "-MailRoot", str(root))
                self.assertEqual(
                    "BROKEN", receipt.get("verdict"),
                    f"{script} over a lane with a stale message and no receipts:\n{receipt}",
                )
                self.assertEqual(1, code)
                self.assertEqual(
                    1, receipt.get("examined"),
                    "the message was not examined, so the run failed before it read anything",
                )
                self.assertTrue(receipt.get("findings"), "BROKEN with no finding is a crash")

    def test_a_receipt_naming_a_longer_id_does_not_mark_a_message_delivered(self):
        """One receipt made the membership test a SUBSTRING match.

        A lane holding `note-1`, which nobody rendered, and one receipt for a different message
        `note-12`. `[string].Contains` is substring matching, so "note-12".Contains("note-1") is
        true and the message counted as rendered. Measured: CLEAN, exit 0, with a healthy corpus
        printed beside it, over a message eight months past a thirty-minute ttl.
        """
        root = self.lane("substring", [self.message("note-1")], [self.receipt("note-12")])

        receipt, code = self.check("check-message-delivery.ps1", "-MailRoot", str(root))
        self.assertEqual(
            "BROKEN", receipt.get("verdict"),
            "a receipt for 'note-12' was accepted as delivery of 'note-1'. Set membership had "
            f"become substring matching:\n{receipt}",
        )
        self.assertEqual(1, code)
        self.assertTrue(
            any("note-1'" in f for f in receipt.get("findings", [])),
            f"the finding does not name the undelivered message:\n{receipt.get('findings')}",
        )

    def test_two_receipts_still_match_an_id_that_differs_only_in_case(self):
        """Two or more receipts lost the case-insensitivity the set was built with.

        `[object[]]` falls back to `IList.Contains`, which is ordinal, so a receipt naming `msg-a`
        stopped matching a message `MSG-A` -- while the OrdinalIgnoreCase comparer on the HashSet
        says they are the same id. Measured: BROKEN, naming a message that had in fact been
        rendered. That is a false finding, which costs the instrument its credibility as surely as
        a missed one.
        """
        root = self.lane(
            "case", [self.message("MSG-A")], [self.receipt("msg-a"), self.receipt("other")])

        receipt, code = self.check("check-message-delivery.ps1", "-MailRoot", str(root))
        self.assertEqual(
            2, receipt.get("corpus", {}).get("receipts"),
            "the lane did not hold the two receipts this case is about, so it is measuring the "
            f"one-receipt branch instead:\n{receipt}",
        )
        self.assertEqual(
            "CLEAN", receipt.get("verdict"),
            "a receipt naming 'msg-a' no longer matched the message 'MSG-A'. The set's comparer is "
            f"case-insensitive; the array it was unrolled into is not:\n{receipt}",
        )
        self.assertEqual(0, code)


class OneInstantHasOneVerdictHoweverItIsSpelled(ValidationCase):
    """A 'Z' timestamp was compared against a local clock, and the offset went missing."""

    def test_the_same_instant_spelled_two_ways_gives_the_same_verdict(self):
        """RoundtripKind gives 'Z' Kind=Utc; `Get-Date` is local; PowerShell compares ticks and
        ignores Kind. West of UTC that hides lateness up to the machine's offset, and east of UTC it
        invents lateness. Measured at -05:00 on one instant four hours old with a thirty-minute
        ttl: CLEAN spelled 'Z', BROKEN spelled '-05:00', identical corpus counts.

        The case does not care WHICH verdict is right. It cares that one instant cannot have two,
        which is the property the spelling was allowed to change.
        """
        import datetime as dt

        sent = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=4)
        as_utc = sent.strftime("%Y-%m-%dT%H:%M:%S.0000000Z")
        as_local = sent.astimezone().isoformat(timespec="microseconds")

        verdicts = {}
        for label, stamp in (("utc", as_utc), ("local", as_local)):
            root = self.lane(label, [self.message(f"msg-{label}", sent=stamp)], [])
            receipt, _ = self.check("check-message-expiry.ps1", "-MailRoot", str(root))
            verdicts[label] = receipt.get("verdict")

        self.assertEqual(
            verdicts["utc"], verdicts["local"],
            "one instant, two spellings, two verdicts. A 'Z' timestamp is being read as a local "
            f"wall clock, so the machine's UTC offset changes the answer: {verdicts}",
        )
        self.assertEqual(
            "BROKEN", verdicts["utc"],
            "a message four hours past a thirty-minute ttl with no receipt is late by either "
            f"reading, so agreement on CLEAN would be two wrong answers agreeing: {verdicts}",
        )

    def test_every_road_into_the_timestamp_reader_ends_in_local_kind(self):
        """Both branches, because only one of them is on the live path.

        ConvertFrom-Json already turns an ISO-8601 field into a [datetime], so a 'Z' timestamp
        reaches the helper as Kind=Utc and never touches [datetime]::Parse. The case above therefore
        pins the [datetime] branch alone -- measured, by mutating the parse branch and watching it
        stay green. The parse branch is still reachable from any caller handing over a raw string,
        and a Kind left un-normalised there would put the same offset bug back on that road.
        """
        script = (
            f". '{VALIDATION / '_receipt.ps1'}'\n"
            "$fromString = ConvertTo-CcxTime '2026-01-01T09:00:00.0000000Z'\n"
            "$fromDateTime = ConvertTo-CcxTime "
            "([datetime]::SpecifyKind([datetime]'2026-01-01T09:00:00', 'Utc'))\n"
            "\"$($fromString.Kind) $($fromDateTime.Kind)\"\n"
        )
        proc = subprocess.run(
            [self.pwsh, "-NoProfile", "-Command", script],
            capture_output=True, text=True, encoding="utf-8", timeout=TIMEOUT_SECONDS,
        )
        self.assertEqual(0, proc.returncode, proc.stdout + proc.stderr)
        self.assertEqual(
            "Local Local", (proc.stdout or "").strip(),
            "a timestamp reader returned a non-Local Kind. Callers compare against (Get-Date), "
            "which is local, and PowerShell compares on ticks while ignoring Kind, so the machine's "
            f"UTC offset silently becomes part of the answer:\n{proc.stdout}{proc.stderr}",
        )


class AnIndexRowDoesNotExcuseAnUndeclaredPath(ValidationCase):
    """The exclusion no fixture reaches, because no fixture supplies an index file."""

    CONFIG = {
        "prefix": "ccx",
        "trunk": "main",
        "sequences": {
            "adr": {
                "dir": "docs/adr",
                "filePattern": r"^docs/adr/(\d{4})-[^/]+\.md$",
                "pad": 4,
                "indexFile": "docs/adr/README.md",
                "indexRowPattern": r"^\|\s*\[?(\d{4})",
            }
        },
    }

    def git(self, repo: Path, *args: str):
        r = subprocess.run(["git", *GIT_ID, *args], cwd=str(repo),
                           capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
        self.assertEqual(0, r.returncode, f"git {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")

    def repo_with_a_collision(self, name: str, index_row: str) -> Path:
        """0084 on two branches under two filenames, plus whatever index row is asked for."""
        repo = self.base / name
        (repo / "docs" / "adr").mkdir(parents=True)
        self.git(repo.parent, "init", "-q", "-b", "main", str(repo))
        (repo / "ccx.config.json").write_text(json.dumps(self.CONFIG, indent=2), encoding="utf-8")
        (repo / "docs" / "adr" / "0084-main.md").write_text("the original\n", encoding="utf-8")
        (repo / "docs" / "adr" / "README.md").write_text(
            "| number | decision |\n|---|---|\n" + index_row, encoding="utf-8")
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-qm", "main side")

        self.git(repo, "checkout", "-q", "-b", "someone-elses-branch")
        (repo / "docs" / "adr" / "0084-rogue.md").write_text("the same number\n", encoding="utf-8")
        self.git(repo, "add", "-A")
        self.git(repo, "commit", "-qm", "rogue side")
        self.git(repo, "checkout", "-q", "main")
        return repo

    def test_a_row_naming_only_the_original_does_not_suppress_the_rogue(self):
        """`count - 1` spent the whole allowance on the path an index row always names.

        An index row names the original by convention, so with two paths one declared path was
        enough to skip, and the undeclared second file rode free. Measured on a real repository:
        CLEAN. Deleting the 0084 row and changing nothing else made the same repository BROKEN, so
        the row was doing the suppressing -- and every real allocated number has a row.
        """
        repo = self.repo_with_a_collision("rogue", "| [0084](0084-main.md) | the original |\n")

        receipt, code = self.check("check-allocation-collisions.ps1", "-Repo", str(repo))
        self.assertEqual(
            "BROKEN", receipt.get("verdict"),
            "one number on two paths, and the index row names only one of them. The row is not a "
            f"declaration of the other:\n{receipt}",
        )
        self.assertEqual(1, code)
        self.assertTrue(
            any("0084-rogue.md" in f for f in receipt.get("findings", [])),
            f"the finding does not name the undeclared path:\n{receipt.get('findings')}",
        )

    def test_a_row_naming_both_paths_is_still_excluded(self):
        """The positive control. Without it a check that reported every multi-path number would
        pass the case above, and the declaration this exclusion exists for would be gone."""
        repo = self.repo_with_a_collision(
            "declared", "| [0084](0084-main.md) | also 0084-rogue.md, deliberately |\n")

        receipt, code = self.check("check-allocation-collisions.ps1", "-Repo", str(repo))
        self.assertEqual(
            "CLEAN", receipt.get("verdict"),
            "an index row naming BOTH paths is a declaration, and the check refused it anyway. The "
            f"exclusion has become unreachable:\n{receipt}",
        )
        self.assertEqual(0, code)


class TheExecutedControlsCannotRetireQuietly(unittest.TestCase):
    """A skip satisfies the gate's `Ran [1-9][0-9]* tests` grep exactly as a pass does.

    Every executed case in this file and its two siblings calls skipTest when `pwsh` is absent, so a
    runner image that dropped pwsh would retire all of them and the gate would stay green. Both
    matrix legs ship pwsh today, so nothing is broken now -- this is the case that would notice.
    """

    def test_pwsh_is_present_when_this_runs_in_ci(self):
        if not os.environ.get("CI"):
            self.skipTest("not a CI run, where a missing pwsh is the developer's own business")
        self.assertTrue(
            t.find_pwsh(),
            "pwsh is not on PATH in CI, so every executed validation case skipped. The gate counts "
            "tests that RAN, and a skip counts, so this would have gone green with the whole "
            "executed half of the suite retired.",
        )


if __name__ == "__main__":
    unittest.main()
