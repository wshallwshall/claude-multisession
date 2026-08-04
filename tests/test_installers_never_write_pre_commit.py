"""Pin the rule that no installer here writes `pre-commit`.

THE FAILURE THIS EXISTS FOR. Two tools cannot both own `.git/hooks/pre-commit`. A hook framework that
finds a foreign hook there may rename it and invoke it from its own shim, and that chain has failed on
Windows and blocked EVERY commit in a repository until the shim was removed. Note the shape of the
lie: the renamed file EXISTING did not indicate success. Only a real commit did.

The rule is therefore absolute -- not to install, not to patch, not to migrate -- and it is the kind
of rule a later change breaks by accident, in one line, while fixing something else.

WHAT THIS PROVES, AND WHAT IT DOES NOT. These cases read source. They pin the declared write set and
scan for a file operation naming the file; they do NOT run an installer and look at the directory
afterwards, because the installers refuse to run inside an agent session and nothing here defeats
that. `install-git-hooks.ps1 -Status` reports whether a pre-commit is present and states that this
script never wrote it -- that is the observation of the real directory.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

# Anything that creates, overwrites, moves or deletes a file. Remove-Item is on the list on purpose:
# "never writes it" is not the whole rule. An installer that DELETED somebody else's pre-commit would
# be turning off a control it does not own, which is the same defect wearing the opposite sign.
WRITE_COMMANDS = (
    "Set-Content",
    "Add-Content",
    "Out-File",
    "New-Item",
    "Copy-Item",
    "Move-Item",
    "Rename-Item",
    "Remove-Item",
    "WriteAllText",
    "WriteAllBytes",
    "WriteAllLines",
    "AppendAllText",
)

# `pre-commit`, `precommit`, `$preCommit`. A future edit is as likely to reach the file through the
# variable as through the literal.
PRE_COMMIT = re.compile(r"pre-?commit", re.IGNORECASE)



class InstallersNeverWritePreCommit(unittest.TestCase):
    def test_the_git_hook_installer_declares_only_commit_msg_and_pre_push(self):
        """It writes exactly the hooks in $ARTIFACTS, so the declared set is the written set."""
        hooks = t.git_hook_names()
        self.assertEqual(
            ["commit-msg", "pre-push"],
            sorted(hooks),
            "the set of git hooks install-git-hooks.ps1 declares has changed. If pre-commit is now "
            "among them, read the header of that file before going further: this is the rule that "
            "blocked every commit in a repository once.",
        )

    def test_no_write_command_in_any_installer_names_pre_commit(self):
        offenders = []
        self.assertEqual(
            4,
            len(t.ALL_INSTALLERS),
            "the set of installers has changed. Add the new one to ALL_INSTALLERS -- an installer "
            "this scan does not read is one the rule is not enforced on.",
        )
        for installer in t.ALL_INSTALLERS:
            for number, line in enumerate(t.read(installer).splitlines(), start=1):
                if not PRE_COMMIT.search(line):
                    continue
                if any(cmd in line for cmd in WRITE_COMMANDS):
                    offenders.append(f"{installer.name}:{number}: {line.strip()}")
        self.assertEqual(
            [],
            offenders,
            "an installer now performs a file operation on pre-commit:\n"
            + "\n".join(offenders)
            + "\nTwo tools cannot both own that file. Wire the sequence gate into whatever hook "
            "framework the repository already uses instead.",
        )

    def test_the_git_hook_installer_still_reports_pre_commit_without_touching_it(self):
        """The rule is 'never write it', not 'never mention it'.

        -Status reports whether a pre-commit exists and says who owns it, because an unwired sequence
        gate looks exactly like one that passed. This pins that the reporting survives -- otherwise
        the cheapest way to make the case above green is to stop looking at the file at all, which
        removes the only signal an operator gets.
        """
        text = t.read(t.GIT_HOOK_INSTALLER)
        self.assertRegex(
            text,
            r"Test-Path[^\n]*\$preCommit",
            "install-git-hooks.ps1 no longer reports on pre-commit. It must not WRITE that file; it "
            "should still say whether one is there and that it did not put it there.",
        )

    def test_the_scan_can_see_the_thing_it_is_looking_for(self):
        """Prove the instrument first. A pattern that matches nothing passes everything."""
        planted = 'Set-Content -LiteralPath (Join-Path $HooksDir "pre-commit") -Value $x'
        self.assertTrue(PRE_COMMIT.search(planted))
        self.assertTrue(any(cmd in planted for cmd in WRITE_COMMANDS))
        self.assertTrue(PRE_COMMIT.search("$preCommit = Join-Path $HooksDir 'pre-commit'"))


if __name__ == "__main__":
    unittest.main()
