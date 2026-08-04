"""Each installer must carry its control's dependency closure, not just the control.

THE FAILURE THIS EXISTS FOR, twice over:

  * The two Python checkers insert their own directory on `sys.path` and import a shared module from
    it. Installed WITHOUT that module they do not degrade -- they raise at import and exit non-zero,
    which for `commit-msg` and `pre-push` means refusing EVERY commit and EVERY push, for a reason
    that has nothing to do with what they check.
  * The worktree gate dot-sources three helpers. Installed without them the dot-source fails, the
    gate exits 0 after a stderr receipt, and it enforces NOTHING -- while every file the installer
    talks about is present and hashes correctly.

Both shipped. The requirement in each case is read off the CONSUMER here (what the checkers import,
what the gate dot-sources) and compared against the installer's copy list, because a copy list checked
against a hand-written list of names in a test file only proves that two lists agree.

WHAT THIS DOES NOT DO, AND WHERE THAT PROOF LIVES. These cases read declarations; they never run an
installer. Running one from a test would mean defeating the guard that makes the installers refuse
inside an agent session, and that guard exists for a good reason. The evidence that a copy actually
LANDED is `bin/ccx-doctor.ps1`, which hashes the installed substrate and the installed gate's helpers
against this checkout and, in its attack phase, distinguishes a checker that refuses the case it is
supposed to refuse from one that refuses everything because it could not import its own substrate.
Declarations here, bytes and behaviour there.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import unittest

import _ccxtest as t


class DeclaredCopyLists(unittest.TestCase):
    def test_the_git_hook_installer_copies_every_module_its_checkers_import(self):
        required = t.checker_private_imports()
        carried = t.substrate_payloads()
        missing = sorted(required - carried)
        self.assertEqual(
            [],
            missing,
            "claim_check.py / push_guard.py import "
            + ", ".join(missing)
            + " but install-git-hooks.ps1 does not copy it. Installed like that, both gates raise at "
            "import and refuse every commit and every push -- while looking installed.",
        )

    def test_the_gate_installer_copies_every_helper_the_gate_dot_sources(self):
        required = t.gate_dependency_closure()
        carried = t.gate_helper_copy_list()
        missing = sorted(required - carried)
        self.assertEqual(
            [],
            missing,
            "worktree_gate.ps1 needs "
            + ", ".join(missing)
            + " beside it, but install-gate.ps1 does not copy it. The dot-source then fails, the gate "
            "exits 0 after a stderr receipt, and it stops enforcing while hashing correctly.",
        )

    def test_both_installers_refuse_rather_than_install_a_partial_closure(self):
        """A missing source must abort the install, not produce a half-installed control.

        Copying what happens to be present and reporting success is how a control ends up looking
        installed and enforcing nothing. Both installers check every source first and throw.
        """
        hooks = t.ps_source(t.GIT_HOOK_INSTALLER)
        self.assertRegex(
            hooks,
            r"foreach\s*\(\s*\$s\s+in\s+\$SUBSTRATE\s*\)\s*\{[^}]*?Test-Path[^}]*?\}",
            "install-git-hooks.ps1 no longer verifies that every $SUBSTRATE source exists before "
            "installing.",
        )
        gate = t.ps_source(t.GATE_INSTALLER)
        self.assertRegex(
            gate,
            r"foreach\s*\(\s*\$h\s+in\s+\$GateHelpers\s*\)\s*\{[^}]*?Test-Path[^}]*?\}",
            "install-gate.ps1 no longer verifies that every $GateHelpers source exists before "
            "installing.",
        )

    def test_the_substrate_is_copied_before_the_checkers_that_import_it(self):
        """Order is part of the guarantee.

        A checker that lands ahead of the module it imports is, until the next copy completes, a gate
        that refuses everything. An interrupted install should leave a control that is absent, not
        one that is present and hostile.
        """
        text = t.ps_source(t.GIT_HOOK_INSTALLER)
        substrate_loop = text.rfind("foreach ($s in $SUBSTRATE)")
        artifact_loop = text.rfind("foreach ($a in $ARTIFACTS)")
        self.assertNotEqual(-1, substrate_loop, "no $SUBSTRATE copy loop found")
        self.assertNotEqual(-1, artifact_loop, "no $ARTIFACTS copy loop found")
        self.assertLess(
            substrate_loop,
            artifact_loop,
            "install-git-hooks.ps1 now copies its checkers before the module they import.",
        )


if __name__ == "__main__":
    unittest.main()
