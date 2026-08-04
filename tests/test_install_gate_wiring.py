"""The anti-drift pin between the worktree gate and the installer that wires it.

THE FAILURE THIS EXISTS FOR. A PreToolUse hook is only invoked for the tools its `matcher` names. A
rule implemented in the gate whose tool appears in no matcher NEVER FIRES: the hook is not called, so
it cannot deny, and nothing anywhere says so. The script is present, it hashes correctly against its
source, and every other test of it passes -- because every other test runs the script directly rather
than through the matcher that decides whether it runs at all. A rule has shipped in exactly that
state.

So the assertion is not "the gate works". It is "every rule the gate implements has a route to being
invoked", which is a fact about two files agreeing, and only a test that reads both can hold it.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import unittest

import _ccxtest as t


class InstallGateWiring(unittest.TestCase):
    def test_every_tool_the_gate_branches_on_appears_in_the_matcher_list(self):
        handled = t.gate_handled_tools()
        wired = t.installer_matcher_tools()
        missing = sorted(handled - wired)
        self.assertEqual(
            [],
            missing,
            "worktree_gate.ps1 branches on "
            + ", ".join(sorted(missing))
            + " but install-gate.ps1 wires no matcher for it. The rule is implemented and DEAD: the "
            "hook is never invoked for that tool, so it cannot deny, and the gate looks healthy. Add "
            "the tool to the $matchers list in scripts/worktree/install-gate.ps1.",
        )

    def test_the_matcher_list_names_no_tool_the_gate_ignores(self):
        handled = t.gate_handled_tools()
        wired = t.installer_matcher_tools()
        stray = sorted(wired - handled)
        self.assertEqual(
            [],
            stray,
            "install-gate.ps1 wires a matcher for "
            + ", ".join(stray)
            + " but worktree_gate.ps1 has no branch for it. Every such call now spawns a pwsh process "
            "that reads the payload and exits 0 -- a per-tool-call cost buying nothing, and a wiring "
            "line that reads like enforcement.",
        )

    def test_the_relocation_rule_is_wired_only_behind_its_opt_in_switch(self):
        """EnterWorktree is implemented, and deliberately OFF on a bare install.

        Pinned because it is the one rule whose absence from a default install is CORRECT. Without
        this, the assertion above could be satisfied by quietly turning it on -- and with the
        dispatch rule also live, a session started in the primary would have no in-session path to
        isolation at all. Turning it on has to stay a decision, not a side effect of reinstalling.
        """
        text = t.ps_source(t.GATE_INSTALLER)
        self.assertIn("EnterWorktree", t.gate_handled_tools(), "the gate no longer implements rule 4")
        self.assertRegex(
            text.replace("\n", " "),
            r"if\s*\(\s*\$EnterWorktreeGate\s*\)\s*\{[^}]*\$matchers\s*\+=\s*\"EnterWorktree\"",
            "install-gate.ps1 no longer appends the EnterWorktree matcher inside an "
            "`if ($EnterWorktreeGate)` block. If it is now wired unconditionally that is a real "
            "behaviour change and this pin must be updated deliberately, not deleted.",
        )

    def test_the_extractors_actually_found_something(self):
        """A guard on the instrument, not on the subject.

        Both assertions above compare two sets. Two EMPTY sets are equal, so a pattern that stopped
        matching would turn this file green while checking nothing -- the failure mode this whole
        repository is about. The extractors raise rather than return empty; this makes that visible
        as its own named test rather than as an incidental exception.
        """
        self.assertGreaterEqual(len(t.gate_handled_tools()), 4)
        self.assertGreaterEqual(len(t.installer_matcher_tools()), 4)


if __name__ == "__main__":
    unittest.main()
