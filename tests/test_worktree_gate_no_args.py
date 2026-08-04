"""Run the worktree gate the way the harness runs it: with NO arguments.

THE FAILURE THIS EXISTS FOR. The gate's allowlist path is a PARAMETER DEFAULT. A default is not
evaluated when the caller supplies a value -- so a test suite in which every case passed `-ReposFile`
explicitly never executed that line even once. A version shipped in which the default was written
`( if ... )` instead of `$( if ... )`; a bare parenthesis opens a command-invocation group, PowerShell
parsed `if` as a command name, and the script died before its first line. In production the gate was
OFF on every tool call for the length of one install, and the entire suite was green throughout.

So these cases pass NO arguments at all. That is the whole point: the production path is the one
where the harness supplies nothing.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

TIMEOUT_SECONDS = 120


class WorktreeGateWithNoArguments(unittest.TestCase):
    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the gate cannot be executed here")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-gate-noargs-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.primary = root / "primary"
        self.elsewhere = root / "elsewhere"
        for d in (self.home, self.primary, self.elsewhere):
            d.mkdir(parents=True)
        # The allowlist path is read out of the INSTALLER, not typed here. What is under test is that
        # the gate's default and the installer's destination are the SAME file; a constant in this
        # test file would only prove that the gate agrees with the test file.
        self.allowlist = self.home / t.installer_allowlist_relpath()
        self.allowlist.parent.mkdir(parents=True, exist_ok=True)

    def run_gate(self, payload: dict) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        # Both spellings: the gate resolves the home directory null-safely and either may be the one
        # its platform reads.
        env["USERPROFILE"] = str(self.home)
        env["HOME"] = str(self.home)
        # NO SCRIPT ARGUMENTS. See the module docstring.
        return subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(t.GATE)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env=env,
            timeout=TIMEOUT_SECONDS,
        )

    @staticmethod
    def write_payload(target: Path, cwd: Path) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Write",
            "tool_input": {"file_path": str(target)},
            "cwd": str(cwd),
        }

    def assert_no_bootstrap_noise(self, result: subprocess.CompletedProcess):
        # The two ways this script has failed before its first line both surface here. A binding
        # error prints "Cannot bind argument to parameter"; the command-group parse error prints
        # "The term 'if' is not recognized". Neither is visible in the exit code, which is why the
        # gate was off for an install without anybody noticing.
        self.assertEqual(
            "",
            result.stderr.strip(),
            "the gate wrote to stderr on a run with no arguments. Its parameter default is the only "
            "code that runs before the body, and a failure there leaves the gate silently OFF:\n"
            + result.stderr,
        )

    def test_with_no_allowlist_it_allows_and_says_nothing(self):
        """The documented OFF state: absent allowlist means nothing is governed."""
        self.assertFalse(self.allowlist.exists())
        r = self.run_gate(self.write_payload(self.primary / "x.txt", self.primary))
        self.assert_no_bootstrap_noise(r)
        self.assertEqual(0, r.returncode)
        self.assertEqual(
            "",
            r.stdout.strip(),
            "with no allowlist the gate must emit nothing at all. Any JSON here is a decision taken "
            "with nothing governing it.",
        )

    def test_the_default_allowlist_is_the_file_the_installer_writes(self):
        """The load-bearing case: the default resolved, and it resolved to the RIGHT path.

        Nothing else in the suite proves this. A default that resolves to a path the installer never
        writes yields a gate that reads an empty allowlist forever: it exits 0 on every call, which
        is indistinguishable from a healthy gate with nothing to say.
        """
        self.allowlist.write_text(
            "# fixture\n" + str(self.primary) + "\n", encoding="utf-8"
        )
        r = self.run_gate(self.write_payload(self.primary / "x.txt", self.primary))
        self.assert_no_bootstrap_noise(r)
        self.assertEqual(0, r.returncode, "a hook must exit 0 and put its decision in the JSON")
        self.assertTrue(
            r.stdout.strip(),
            "the gate said NOTHING about a write into a governed root, having been given no "
            "arguments. Either its default allowlist path is not the one the installer writes, or "
            "the default did not evaluate at all.",
        )
        decision = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual("PreToolUse", decision["hookEventName"])
        self.assertEqual(
            "deny",
            decision["permissionDecision"],
            "the wrapper matters: a bare {'permissionDecision': 'deny'} is ignored and the tool call "
            "proceeds.",
        )

    def test_a_write_outside_a_governed_root_is_still_allowed(self):
        """The negative control. A script that refuses everything is an outage, not a gate."""
        self.allowlist.write_text(
            "# fixture\n" + str(self.primary) + "\n", encoding="utf-8"
        )
        r = self.run_gate(self.write_payload(self.elsewhere / "x.txt", self.elsewhere))
        self.assert_no_bootstrap_noise(r)
        self.assertEqual(0, r.returncode)
        self.assertEqual(
            "",
            r.stdout.strip(),
            "the gate denied a write OUTSIDE every governed root. Blocking ordinary work is how a "
            "guardrail gets uninstalled, after which it protects nothing.",
        )


if __name__ == "__main__":
    unittest.main()
