"""Pin that the gate's branch-reuse remediation is a command that can actually run.

THE FAILURE THIS EXISTS FOR. The worktree gate's branch-reuse rule denies a checkout that would move
a linked worktree onto a branch another session is building on, and then prints the supported way to
do what the agent wanted. That remediation used to interpolate the target REF into `new.ps1 -Name`.
`-Name` is the worktree DIRECTORY component and cannot contain '/', so the printed command was
rejected by the very script it named -- and it failed for exactly the branch shape the rule fires on
most, a namespaced ref like `team/task`.

Note the shape of it: the gate was working correctly, the denial was correct, and the advice was
unusable. Nothing failed loudly. The agent is told what to do at the one moment it is being stopped
from doing damage, and the instruction does not work.

The fix split the roles -- `-Branch` is the git ref, `-Name` is the directory -- so these cases pin
the split from BOTH sides. A future edit that reunites them, or that hands a raw ref back to `-Name`,
fails here.

WHAT THIS PROVES, AND WHAT IT DOES NOT. These cases read source. They prove the remediation passes a
ref to `-Branch` and a slug to `-Name`, that `new.ps1` declares `-Branch`, and that every copy of the
directory-name pattern is anchored so a trailing newline cannot slip through. They do NOT execute
PowerShell: the gate refuses to run inside an agent session, so a live invocation is not available
here. Running the printed command by hand from a plain terminal remains the end-to-end check.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

GATE = t.REPO_ROOT / "scripts" / "hooks" / "worktree_gate.ps1"
NEW = t.REPO_ROOT / "scripts" / "worktree" / "new.ps1"

# Every script that takes a worktree DIRECTORY name. The literal must be identical in all of them:
# five copies of a rule is already the problem, and five copies that DISAGREE is the worse one.
NAME_TAKERS = (
    t.REPO_ROOT / "scripts" / "worktree" / "new.ps1",
    t.REPO_ROOT / "scripts" / "worktree" / "remove.ps1",
    t.REPO_ROOT / "scripts" / "worktree" / "rescue.ps1",
    t.REPO_ROOT / "scripts" / "worktree" / "spawn.ps1",
    t.REPO_ROOT / "scripts" / "coord" / "_common.ps1",
)

# The anchored form. `^`/`$` is NOT equivalent in .NET: `$` also matches before a FINAL NEWLINE, so
# the obvious spelling accepts "abc\n" and lets it into a directory name.
REQUIRED_PATTERN = r"[ValidatePattern('\A[A-Za-z0-9._-]+\z')]"
UNANCHORED = re.compile(r"ValidatePattern\('\^\[A-Za-z0-9\._-\]\+\$'\)")

# `-Name` immediately followed by a PowerShell variable is the defect: a ref interpolated into the
# directory parameter. `-Name $destSlug` is the fix, so the pattern deliberately excludes it.
NAME_TAKES_A_VARIABLE = re.compile(r"-Name\s+\$(?!destSlug\b)\w+")


class TheRemediationCanRun(unittest.TestCase):
    def test_the_branch_reuse_remediation_passes_a_ref_to_branch_not_to_name(self):
        text = t.read(GATE)
        self.assertIn(
            "-Branch '$dest'",
            text,
            "the branch-reuse remediation no longer passes the target ref to -Branch. If the "
            "parameters were merged again, read this file's header first: -Name cannot carry a '/' "
            "and the rule fires most often on refs that have one.",
        )
        # Skip comment lines. The defect is documented in a comment directly above the fix, quoting
        # the broken form verbatim -- so a scan that reads prose flags the explanation of the bug as
        # the bug. Prose that names a defect is evidence the defect is understood, not a recurrence.
        offenders = [
            f"{n}: {line.strip()}"
            for n, line in enumerate(text.splitlines(), start=1)
            if "new.ps1" in line
            and not line.lstrip().startswith("#")
            and NAME_TAKES_A_VARIABLE.search(line)
        ]
        self.assertEqual(
            [],
            offenders,
            "a new.ps1 remediation interpolates a variable into -Name:\n"
            + "\n".join(offenders)
            + "\n-Name is the directory component. Pass the ref via -Branch and a derived slug via "
            "-Name, as the branch-reuse rule does.",
        )

    def test_the_slug_handed_to_name_is_derived_and_can_never_be_empty(self):
        text = t.read(GATE)
        self.assertRegex(
            text,
            r"\$destSlug\s*=\s*\(\$dest\s+-replace",
            "the slug handed to -Name is no longer derived from the ref by substitution.",
        )
        self.assertRegex(
            text,
            r"if\s*\(-not\s+\$destSlug\)",
            "the slug derivation lost its empty fallback. A ref of only separators reduces to an "
            "empty string, and an empty -Name fails the parameter's own pattern -- which would put "
            "an unusable command back in the remediation by a different route.",
        )

    def test_new_declares_branch_and_defaults_it_to_name(self):
        text = t.read(NEW)
        self.assertRegex(
            text, r"\[string\]\$Branch", "new.ps1 no longer declares a -Branch parameter."
        )
        self.assertRegex(
            text,
            r"if\s*\(-not\s+\$Branch\)\s*\{\s*\$Branch\s*=\s*\$Name\s*\}",
            "-Branch no longer defaults to -Name. The default is what keeps every existing "
            "invocation, and the sibling scripts that call this one, unchanged.",
        )
        self.assertIn(
            "check-ref-format",
            text,
            "-Branch is no longer validated by git. Do not replace this with a character class: "
            "refname grammar is git's to define, and a hand-rolled pattern is the mistake the "
            "parameter exists to undo.",
        )
        self.assertRegex(
            text,
            r"\$Branch\.StartsWith\('-'\)",
            "the leading-dash refusal is gone. check-ref-format ACCEPTS a leading '-', which git's "
            "own argument parser would then read as a flag.",
        )


class TheDirectoryPatternIsAnchoredEverywhere(unittest.TestCase):
    def test_every_name_taking_script_uses_the_same_anchored_pattern(self):
        missing = [p.name for p in NAME_TAKERS if REQUIRED_PATTERN not in t.read(p)]
        self.assertEqual(
            [],
            missing,
            f"these scripts do not carry the anchored directory-name pattern: {missing}. All "
            f"{len(NAME_TAKERS)} must be identical -- copies that disagree are worse than copies.",
        )

    def test_no_script_has_regressed_to_the_dollar_anchored_form(self):
        offenders = [p.name for p in NAME_TAKERS if UNANCHORED.search(t.read(p))]
        self.assertEqual(
            [],
            offenders,
            f"these scripts use '^...$' for the directory name: {offenders}. In .NET '$' also "
            "matches before a final newline, so that form accepts a trailing newline into a "
            "directory name. Use \\A and \\z.",
        )


class TheScansCanSeeWhatTheyLookFor(unittest.TestCase):
    """Prove each instrument on a planted example before trusting a pass."""

    def test_the_name_variable_pattern_catches_the_original_defect(self):
        self.assertTrue(
            NAME_TAKES_A_VARIABLE.search("pwsh -NoProfile -File $newScript -Name $dest"),
            "the scan must fire on the exact line this test exists to prevent.",
        )
        self.assertIsNone(
            NAME_TAKES_A_VARIABLE.search(
                "pwsh -NoProfile -File \"$newScript\" -Branch '$dest' -Name $destSlug"
            ),
            "the scan must not fire on the corrected form, or the fix cannot make it green.",
        )

    def test_the_unanchored_pattern_matches_the_form_it_rejects(self):
        self.assertTrue(UNANCHORED.search("[ValidatePattern('^[A-Za-z0-9._-]+$')]"))
        self.assertIsNone(UNANCHORED.search(REQUIRED_PATTERN))


if __name__ == "__main__":
    unittest.main()
