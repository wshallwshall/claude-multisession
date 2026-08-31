"""Every validation check ships with a corpus it MUST fire on, and one it must stay quiet on.

WHAT THIS EXISTS FOR. `scripts/validation/` holds instruments whose whole job is to fire when the
multi-session tooling misbehaves. An instrument that has only ever been run against a healthy estate
is worth nothing: a probe that returns a confident zero because its command was malformed is
byte-identical to a probe that looked and found nothing wrong, and the malformed one feels like the
strongest part of the case. So each check carries two planted corpora, and this file executes both.

TWO FIXTURES, NOT ONE, AND THE PAIR IS THE POINT. A check hard-wired to fail passes the broken case
perfectly. A check hard-wired to pass -- or one whose reader silently found no files -- passes the
clean case perfectly. Only running both rules out both, which is why the registry in
`run-checks.ps1` names a broken fixture and a clean one per check and this file refuses a check that
names fewer.

THE STATIC CASES RUN WITHOUT `pwsh`. Registry completeness and fixture presence are read off the
source, so this file still measures something on a host where the checks cannot be executed. The
executed cases skip there and say so.

THE RUNNER GETS ITS OWN PLANTED CONTROL. `run-checks.ps1` refuses to measure the live estate when a
control misbehaves, and that refusal is the load-bearing half of the design -- so it is proved by
copying the whole directory, gutting one broken fixture, and requiring the runner to notice. A
refusal path nobody exercises is a refusal path nobody can trust.

Run: python -m unittest discover -s tests
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

VALIDATION = t.REPO_ROOT / "scripts" / "validation"
RUNNER = VALIDATION / "run-checks.ps1"
FIXTURES = VALIDATION / "fixtures"

TIMEOUT_SECONDS = 240

#: A fixture path inside the registry: `Join-Path $fixtures 'broken/<check>/...'`. Extracted rather
#: than written here, so this file pins the registry's own paths instead of a second copy of them.
FIXTURE_ARG = re.compile(r"Join-Path\s+\$fixtures\s+'([^']+)'")


def registry_block() -> str:
    """The `$CHECKS = @( ... )` array, comments stripped.

    Comments are stripped first for the reason `_ccxtest.strip_ps_comments` gives: commenting a
    registry entry out is the likeliest way anyone disables a check, and a scan of the raw text still
    sees it.
    """
    return t.array_literal(t.ps_source(RUNNER), "CHECKS", RUNNER)


def registered_checks() -> list[dict]:
    """One row per registered check: name, script filename, and its two fixture paths."""
    block = registry_block()
    names = t.hashtable_values(block, "Name")
    scripts = t.hashtable_values(block, "Script")
    if not names or len(names) != len(scripts):
        raise AssertionError(
            f"run-checks.ps1: read {len(names)} Name value(s) and {len(scripts)} Script value(s) "
            "from $CHECKS. They have to pair up; either the registry was reshaped or this "
            "extraction stopped matching it, and an unequal read cannot pin anything."
        )
    # Split on the entry boundary so each check's fixture arguments stay with the check that names
    # them. `@{` opens an entry; splitting on it keeps the order the array declares.
    entries = [e for e in block.split("@{") if e.strip()]
    if len(entries) != len(names):
        raise AssertionError(
            f"run-checks.ps1: $CHECKS split into {len(entries)} entries for {len(names)} names. "
            "The entry shape changed and this parser can no longer tell which fixture belongs to "
            "which check."
        )
    rows = []
    for name, script, entry in zip(names, scripts, entries):
        paths = FIXTURE_ARG.findall(entry)
        rows.append({"name": name, "script": script, "fixtures": paths})
    return rows


def script_files() -> set[str]:
    """Every check script present on disk."""
    found = {p.name for p in VALIDATION.glob("check-*.ps1")}
    if not found:
        raise AssertionError(
            f"no check-*.ps1 found in {VALIDATION}. Either they were renamed or the directory "
            "moved -- and an empty set would compare equal to an empty registry and report "
            "agreement, so this raises instead."
        )
    return found


def run_check(pwsh: str, script: str, args: list[str]) -> tuple[int, dict]:
    """Run one check with -Json and return its exit code and parsed receipt."""
    proc = subprocess.run(
        [pwsh, "-NoProfile", "-File", str(VALIDATION / script), *args, "-Json"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=TIMEOUT_SECONDS,
        cwd=str(t.REPO_ROOT),
    )
    receipt: dict = {}
    for line in proc.stdout.splitlines():
        if line.strip().startswith("{"):
            try:
                receipt = json.loads(line)
            except json.JSONDecodeError:
                continue
    if not receipt:
        raise AssertionError(
            f"{script} printed no JSON receipt.\nexit: {proc.returncode}\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
    return proc.returncode, receipt


class TheRegistryAndTheDirectoryAgree(unittest.TestCase):
    """A check that is not registered is never proved, and never run by anything."""

    def test_every_check_script_on_disk_is_registered(self):
        registered = {row["script"] for row in registered_checks()}
        present = script_files()
        self.assertEqual(
            set(),
            present - registered,
            f"these checks exist but are in no $CHECKS entry in run-checks.ps1: "
            f"{sorted(present - registered)}. An unregistered check has no control, so nothing ever "
            "proves it can fire -- which is the exact instrument failure this directory is about.",
        )

    def test_the_registry_names_no_check_that_is_gone(self):
        registered = {row["script"] for row in registered_checks()}
        present = script_files()
        self.assertEqual(
            set(),
            registered - present,
            f"run-checks.ps1 registers checks that do not exist: {sorted(registered - present)}. "
            "The runner would report a control failure for a file it cannot run, which reads as a "
            "broken instrument rather than as a missing one.",
        )


class EveryCheckNamesBothFixturesAndTheyExist(unittest.TestCase):
    """A registry entry naming one fixture proves half of what it needs to prove."""

    def test_each_check_names_a_broken_fixture_and_a_clean_one(self):
        for row in registered_checks():
            paths = row["fixtures"]
            self.assertTrue(
                any(p.startswith("broken/") for p in paths),
                f"{row['name']}: no fixture path under broken/ in its $CHECKS entry. Without one "
                "nothing ever proves this check can fire at all.",
            )
            self.assertTrue(
                any(p.startswith("clean/") for p in paths),
                f"{row['name']}: no fixture path under clean/ in its $CHECKS entry. Without one a "
                "check hard-wired to report BROKEN would pass its only control.",
            )

    def test_every_named_fixture_is_on_disk(self):
        missing = []
        for row in registered_checks():
            for rel in row["fixtures"]:
                if not (FIXTURES / rel).exists():
                    missing.append(f"{row['name']} -> fixtures/{rel}")
        self.assertEqual(
            [],
            missing,
            "these fixtures are named in run-checks.ps1 and are not on disk: "
            + ", ".join(missing)
            + ". The runner would report a control failure that is really a missing file.",
        )


class EachCheckFiresOnItsBrokenCorpusAndStaysQuietOnItsCleanOne(unittest.TestCase):
    """The controls, executed. This is the case the whole directory rests on."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the checks cannot be executed here")

    def test_the_broken_fixture_comes_back_broken(self):
        for row in registered_checks():
            with self.subTest(check=row["name"]):
                args = self._args(row, "broken")
                code, receipt = run_check(self.pwsh, row["script"], args)
                self.assertEqual(
                    "BROKEN",
                    receipt.get("verdict"),
                    f"{row['name']} did not fire on its own planted broken corpus. It returned "
                    f"{receipt.get('verdict')!r} with findings {receipt.get('findings')!r}. A check "
                    "that cannot fire is not an instrument, and its clean runs mean nothing.",
                )
                self.assertEqual(1, code, f"{row['name']}: BROKEN must exit 1, got {code}")

    def test_the_clean_fixture_comes_back_clean(self):
        for row in registered_checks():
            with self.subTest(check=row["name"]):
                args = self._args(row, "clean")
                code, receipt = run_check(self.pwsh, row["script"], args)
                self.assertEqual(
                    "CLEAN",
                    receipt.get("verdict"),
                    f"{row['name']} did not stay quiet on its own planted clean corpus. It returned "
                    f"{receipt.get('verdict')!r} with findings {receipt.get('findings')!r}. A check "
                    "that fires on everything is as useless as one that fires on nothing.",
                )
                self.assertEqual(0, code, f"{row['name']}: CLEAN must exit 0, got {code}")

    def _args(self, row: dict, half: str) -> list[str]:
        """The command-line arguments the registry pairs with this fixture half.

        Read out of the registry entry rather than reconstructed here: a second copy of the argument
        list would let this test pass against a fixture the runner never uses.
        """
        block = registry_block()
        entries = [e for e in block.split("@{") if e.strip()]
        entry = entries[[r["name"] for r in registered_checks()].index(row["name"])]
        key = half.capitalize()
        m = re.search(re.escape(key) + r"\s*=\s*@\(", entry)
        if not m:
            raise AssertionError(
                f"{row['name']}: no {key} = @(...) argument list in its $CHECKS entry."
            )
        # Balanced-paren read rather than a regex: the list contains `(Join-Path $fixtures '...')`,
        # and a non-greedy `[^)]*` stops at that inner close and truncates the argument list -- which
        # would run the check with FEWER arguments than the runner does, silently.
        inner = entry[m.end() : t._close_paren(entry, m.end())]
        args: list[str] = []
        for tok in re.finditer(r"Join-Path\s+\$fixtures\s+'([^']+)'|'([^']+)'", inner):
            if tok.group(1):
                args.append(str(FIXTURES / tok.group(1)))
            else:
                args.append(tok.group(2))
        if not args:
            raise AssertionError(
                f"{row['name']}: the {half} argument list parsed to nothing, so this case would run "
                "the check against the LIVE estate while reporting on a fixture."
            )
        return args


class TheRunnerRefusesWhenAControlDoesNotFire(unittest.TestCase):
    """Planted. The refusal is the design; an unexercised refusal path is not a control."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the runner cannot be executed here")

    def test_gutting_one_broken_fixture_makes_the_runner_refuse_to_measure_anything(self):
        with tempfile.TemporaryDirectory(prefix="ccx-validation-") as tmp:
            root = Path(tmp)
            # The whole scripts/ tree, because the checks dot-source scripts/coord/_common.ps1.
            shutil.copytree(t.REPO_ROOT / "scripts", root / "scripts")
            lost = root / "scripts" / "validation" / "fixtures" / "broken" / "message-delivery" / "wt-a" / "msg-lost.json"
            self.assertTrue(
                lost.exists(),
                f"{lost} is the planted defect this case removes. It is gone, so this test would "
                "assert a refusal that is not caused by what it says it is.",
            )
            lost.unlink()

            proc = subprocess.run(
                [self.pwsh, "-NoProfile", "-File", str(root / "scripts" / "validation" / "run-checks.ps1"), "-SelfTestOnly"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=TIMEOUT_SECONDS,
                cwd=str(t.REPO_ROOT),
                env={**os.environ, "CCX_CONFIG": str(t.REPO_ROOT / "ccx.config.json")},
            )
            self.assertEqual(
                3,
                proc.returncode,
                "the runner did not refuse after a control stopped firing.\n"
                f"exit: {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
            )
            self.assertIn(
                "REFUSING TO MEASURE THE LIVE ESTATE",
                proc.stdout,
                "the runner exited 3 without saying why. An exit code nobody reads is not a "
                "refusal a person can act on.",
            )
