"""No validation check reports CLEAN over a corpus it never read, and every one says what it read.

THE TWO RULES THIS PINS, both learned from probes that returned confident zeros.

RULE 1, A CONTROL THAT MUST FIRE, is pinned by
`tests/test_every_validation_check_is_proven_by_a_control.py`. This file pins the other half.

RULE 2, AN INSTRUMENT REPORTS WHAT IT SCANNED. A count from a pipeline carrying a head, a tail or a
sample cap is not a census, and a truncated result reads as a complete one. So every receipt carries
the corpus size beside the finding, and a check that reached no corpus must say CANNOT_TELL rather
than printing the same green line an examined-and-clean run prints.

THE MEASUREMENT BEHIND IT, kept in `scripts/validation/README.md` in full. On 2026-08-31, on Claude
Code CLI 2.1.251, `claude agents --json` under a nonexistent config root returned an empty list and
exit 0. No error, no warning: an empty fleet and a mistyped root are byte-identical. The session that
measured it nearly reported a quoting bug's output as a real reading, because a broken instrument
returning good news looks exactly like a working one.

EVERY CHECK IS DRIVEN, NOT ONE. A rule pinned on a single check is a rule the next check can be
written without. The corpus here is the registry in `run-checks.ps1`, so a check added tomorrow is
covered the day it is registered.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

VALIDATION = t.REPO_ROOT / "scripts" / "validation"
RUNNER = VALIDATION / "run-checks.ps1"
RECEIPT = VALIDATION / "_receipt.ps1"

TIMEOUT_SECONDS = 240

#: Every check, with the switch that points it at a corpus, so an empty one can be handed to each.
#: A check whose reader takes a different switch has to be added here, and the completeness case
#: below is what makes that unavoidable rather than optional.
EMPTY_CORPUS_SWITCH = {
    "check-message-delivery.ps1": "-MailRoot",
    "check-message-expiry.ps1": "-MailRoot",
    "check-claim-holders.ps1": "-ClaimsDir",
    "check-allocation-collisions.ps1": "-RefIndex",
    "check-session-reaping.ps1": "-SessionSource",
}


def registered_scripts() -> list[str]:
    block = t.array_literal(t.ps_source(RUNNER), "CHECKS", RUNNER)
    scripts = t.hashtable_values(block, "Script")
    if not scripts:
        raise AssertionError(
            "run-checks.ps1: $CHECKS named no Script. An empty list would make every case below "
            "vacuous, so this raises rather than reporting agreement over nothing."
        )
    return scripts


class EveryCheckIsDrivenByThisFile(unittest.TestCase):
    """The completeness case. Without it, a new check silently escapes both rules below."""

    def test_the_switch_table_covers_every_registered_check(self):
        registered = set(registered_scripts())
        listed = set(EMPTY_CORPUS_SWITCH)
        self.assertEqual(
            set(),
            registered - listed,
            f"these checks are registered and are not driven here: {sorted(registered - listed)}. "
            "Add the switch that points each one at a corpus, so the empty-corpus rule is proved "
            "for it too. A check nobody drives is a check that may report CLEAN over nothing.",
        )
        self.assertEqual(
            set(),
            listed - registered,
            f"this file drives checks that are no longer registered: {sorted(listed - registered)}.",
        )


class AnEmptyCorpusIsNeverClean(unittest.TestCase):
    """Executed. Each check is handed a corpus that exists and holds nothing."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the checks cannot be executed here")

    def test_no_check_reports_clean_when_it_read_nothing(self):
        with tempfile.TemporaryDirectory(prefix="ccx-empty-corpus-") as tmp:
            empty_dir = Path(tmp) / "empty"
            empty_dir.mkdir()
            empty_file = Path(tmp) / "empty.json"
            empty_file.write_text("[]\n", encoding="utf-8")

            for script, switch in sorted(EMPTY_CORPUS_SWITCH.items()):
                with self.subTest(check=script):
                    target = empty_file if switch in ("-SessionSource", "-RefIndex") else empty_dir
                    args = [switch, str(target)]
                    if script == "check-allocation-collisions.ps1":
                        # It reads a sequence configuration as well, and this case is about the
                        # empty CORPUS -- so it is given the repository's real one.
                        args += ["-ConfigPath", str(t.REPO_ROOT / "ccx.config.json")]
                    proc = subprocess.run(
                        [self.pwsh, "-NoProfile", "-File", str(VALIDATION / script), *args, "-Json"],
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        timeout=TIMEOUT_SECONDS,
                        cwd=str(t.REPO_ROOT),
                    )
                    receipt = _receipt_of(proc, script)
                    self.assertEqual(
                        "CANNOT_TELL",
                        receipt.get("verdict"),
                        f"{script} was handed an empty corpus and answered "
                        f"{receipt.get('verdict')!r}. An empty answer must not render as a clean "
                        f"one.\nreceipt: {receipt}",
                    )
                    self.assertEqual(
                        2,
                        proc.returncode,
                        f"{script}: CANNOT_TELL must exit 2, got {proc.returncode}. A caller that "
                        "reads only the exit code would treat this run as a pass.",
                    )


class EveryReceiptCarriesWhatWasScanned(unittest.TestCase):
    """A finding without its denominator is not a measurement."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the checks cannot be executed here")

    def test_a_clean_run_still_prints_its_corpus(self):
        """The clean fixture, in TEXT form: the examined line has to be there on a green run.

        A green line with its corpus beside it can be read. A green line on its own cannot be told
        from a probe that never looked, which is the entire complaint this directory answers.
        """
        script = "check-claim-holders.ps1"
        fixtures = VALIDATION / "fixtures" / "clean" / "claim-holders"
        proc = subprocess.run(
            [
                self.pwsh, "-NoProfile", "-File", str(VALIDATION / script),
                "-ClaimsDir", str(fixtures / "claims"),
                "-SessionSource", str(fixtures / "sessions.json"),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=TIMEOUT_SECONDS,
            cwd=str(t.REPO_ROOT),
        )
        self.assertEqual(0, proc.returncode, f"the clean fixture did not come back clean:\n{proc.stdout}")
        self.assertIn("CLEAN", proc.stdout)
        self.assertIn("examined   :", proc.stdout, f"no examined line on a clean run:\n{proc.stdout}")
        self.assertIn("claim files", proc.stdout, f"no corpus breakdown on a clean run:\n{proc.stdout}")
        self.assertIn("broken when:", proc.stdout, f"a clean run does not say what it was looking for:\n{proc.stdout}")

    def test_every_json_receipt_carries_the_keys_a_reader_needs(self):
        for script, switch in sorted(EMPTY_CORPUS_SWITCH.items()):
            with self.subTest(check=script):
                with tempfile.TemporaryDirectory(prefix="ccx-receipt-keys-") as tmp:
                    empty_dir = Path(tmp) / "empty"
                    empty_dir.mkdir()
                    empty_file = Path(tmp) / "empty.json"
                    empty_file.write_text("[]\n", encoding="utf-8")
                    target = empty_file if switch in ("-SessionSource", "-RefIndex") else empty_dir
                    args = [switch, str(target)]
                    if script == "check-allocation-collisions.ps1":
                        args += ["-ConfigPath", str(t.REPO_ROOT / "ccx.config.json")]
                    proc = subprocess.run(
                        [self.pwsh, "-NoProfile", "-File", str(VALIDATION / script), *args, "-Json"],
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        timeout=TIMEOUT_SECONDS,
                        cwd=str(t.REPO_ROOT),
                    )
                    receipt = _receipt_of(proc, script)
                    for key in ("check", "verdict", "brokenWhen", "examined", "corpus", "findings"):
                        self.assertIn(
                            key,
                            receipt,
                            f"{script}: its JSON receipt has no {key!r}. A machine reading these "
                            "cannot separate a clean answer from an unexamined one without it.",
                        )


class TheVerdictRuleHasOneDefinition(unittest.TestCase):
    """Static. Read where CLEAN is decided, so a second copy cannot appear unnoticed."""

    def test_only_the_shared_helper_decides_a_verdict(self):
        source = t.read(RECEIPT)
        self.assertIn(
            "function Get-CcxVerdict",
            source,
            "_receipt.ps1 no longer defines Get-CcxVerdict. The verdict rule is what stops an "
            "unexamined corpus rendering as a clean one; if it moved, move this case with it.",
        )
        offenders = []
        for script in registered_scripts():
            text = t.ps_source(VALIDATION / script)
            if "'CLEAN'" in text or '"CLEAN"' in text:
                offenders.append(script)
        self.assertEqual(
            [],
            offenders,
            f"these checks name the CLEAN verdict themselves: {offenders}. Two copies of a safety "
            "rule drift, and the copy that drifts is the one nobody is testing -- the same rule "
            "scripts/coord/session-registry.ps1 states for the liveness fence.",
        )


def _receipt_of(proc: subprocess.CompletedProcess, script: str) -> dict:
    for line in proc.stdout.splitlines():
        if line.strip().startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    raise AssertionError(
        f"{script} printed no JSON receipt.\nexit: {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
