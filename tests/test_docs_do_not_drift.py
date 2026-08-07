"""Pin the three ways this documentation set can go wrong without anyone noticing.

THE FAILURE THIS EXISTS FOR. Publishing docs/ as a site turned two of these from theory into
something that already happened once.

  1. THE INSTALL PROCEDURE CAN EXIST IN MORE THAN ONE COPY. README.md is the front door on
     github.com, docs/index.md is the front door on the served site, and INSTALL.md is the
     annotated long form. A reader follows exactly one of them. When two of them carried the
     commands, nothing made them agree, and the first divergence was not caught by review:
     docs/index.md said the installers refuse when `$env:CLAUDECODE` is `1` (what all four
     actually test) while README.md still said "is set" (which is looser than the code, and wrong
     for CLAUDECODE=0).

     The two landing pages have since been de-duplicated: docs/index.md carries the procedure and
     README.md points at it. So the case below no longer compares two copies -- it pins that the
     one copy still exists where the pattern can see it, and that README does not grow a second
     copy that disagrees. INSTALL.md was never in this scan despite the docstring's original
     "three copies": it writes `<tooling>` as a placeholder rather than `"$tooling/`, so
     INSTALL_COMMAND has never matched a line in it.
  2. LINKS THAT LEAVE THE SITE ARE PINNED TO `main`. Serving from /docs makes docs/ the site
     root, so a `../scripts/...` target resolves above the root and 404s. The fix was to rewrite
     those to absolute blob/main URLs -- which is correct, and which converts an in-repo
     reference that a move would break loudly into an external URL that a move breaks silently.
  3. A DOC CLAIM ABOUT A CONTROL CAN OUTLIVE THE CONTROL. The CLAUDECODE case is the live
     example: the sentence was not wrong when written, it was wrong about what the code tests.

WHAT THIS PROVES, AND WHAT IT DOES NOT. These cases read source. They prove the install block still
exists where the pattern can see it and that README does not carry a second copy that disagrees,
that every blob/main URL names a path git is tracking, and that no copy describes the installer
refusal more loosely than the installers implement it. They do NOT fetch anything: a URL whose path
exists here still 404s on github.com if the branch is renamed or the file is not pushed, and nothing
local can see that. They also do not check INSTALL.md's prose against the landing page -- it is the
long form and is expected to differ.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import re
import subprocess
import unittest

import _ccxtest as t

# The install block is a fenced sequence of `pwsh -NoProfile -File "$tooling/..."` lines. Matching
# on the $tooling variable is deliberate: the two prose mentions of a bare
# `pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1` are explanatory, not part of the
# procedure, and pinning those would fail on a wording change that harms nobody.
INSTALL_COMMAND = re.compile(r'pwsh -NoProfile -File "\$tooling/[^\n]*')

# Every outbound link into this repository's own tree, in both forms it is published in: the
# human-readable blob view, and the raw view the standards hand out for download. Both pin `main`
# and both rot into a 404 the same way, so both belong in one scan -- a pattern that saw only the
# blob form would have gone quietly blind the day the raw links were added.
BLOB_URL = re.compile(
    r"https://(?:github\.com/wshallwshall/claude-multisession/blob"
    r"|raw\.githubusercontent\.com/wshallwshall/claude-multisession)/main/([^)\"'\s>]+)"
)

# The looser phrasing. All four installers test the LITERAL string "1", so "is set" promises a
# refusal that does not happen for CLAUDECODE=0, =true, or anything else truthy-looking.
CLAUDECODE_LOOSE = re.compile(r"CLAUDECODE`?\s+is set", re.IGNORECASE)

# Files whose links are worth pinning: everything git tracks that can carry one.
LINK_BEARING_SUFFIXES = (".md", ".yml", ".yaml", ".html", ".json")

README = t.REPO_ROOT / "README.md"
LANDING = t.REPO_ROOT / "docs" / "index.md"


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


class TheInstallProcedureHasOneCopy(unittest.TestCase):
    """docs/index.md owns the procedure; README.md points at it rather than repeating it.

    This replaced a case that pinned the two files to identical blocks, which was the right shape
    while both carried the commands. De-duplicating the landing pages left README with no block,
    and that case's own empty-match guard fired rather than passing on an empty comparison. The
    guard is kept below, moved onto the file that now owns the procedure -- which is the only file
    it can defend, since a guard on the pointing file would fail the moment the pointing worked.
    """

    def test_the_landing_page_still_carries_the_procedure(self):
        landing = INSTALL_COMMAND.findall(t.read(LANDING))
        self.assertNotEqual(
            [],
            landing,
            "no install commands found in docs/index.md, which is the one copy of the procedure. "
            "Either the block moved or its shape changed; a pattern that matches nothing passes "
            "everything, so fix the pattern -- or this file's premise about where the procedure "
            "lives -- before trusting a green run here.",
        )

    def test_the_readme_carries_no_second_copy_that_disagrees(self):
        readme = INSTALL_COMMAND.findall(t.read(README))
        landing = INSTALL_COMMAND.findall(t.read(LANDING))

        # Either README points (no commands) or it repeats the landing page exactly. Anything else
        # is the divergence this file exists for. Stated as one membership test rather than a
        # branch, so the empty case cannot slip through as an early return that reads as a pass.
        # Its vacuous case -- both empty -- is what the sibling case above rules out.
        self.assertIn(
            readme,
            ([], landing),
            "README.md carries install commands that do not match docs/index.md.\n"
            "README.md:\n  " + "\n  ".join(readme) + "\n"
            "docs/index.md:\n  " + "\n  ".join(landing) + "\n"
            "A reader follows exactly one of these. Either drop the block from README.md and point "
            "at the landing page, or make the two character-identical in this same commit.",
        )


class OutboundLinksResolve(unittest.TestCase):
    def test_every_blob_main_url_names_a_path_git_is_tracking(self):
        tracked = set(tracked_files())
        offenders = []
        checked = 0
        for relpath in tracked:
            if not relpath.endswith(LINK_BEARING_SUFFIXES):
                continue
            text = t.read(t.REPO_ROOT / relpath)
            for target in BLOB_URL.findall(text):
                # A target carrying a shell or PowerShell variable is a TEMPLATE inside a fetch
                # snippet, not a link anyone clicks. Resolving it would mean executing the snippet.
                if "$" in target:
                    continue
                checked += 1
                if target in tracked:
                    continue
                # A directory is a legitimate target: the download snippets point a base URL at
                # docs/standards/ and append the filename per iteration.
                if any(p.startswith(target + "/") for p in tracked):
                    continue
                offenders.append(f"{relpath}: main/{target}")

        self.assertNotEqual(
            0,
            checked,
            "this scan found no blob/main URLs at all. That is either a repository with none "
            "left, or a broken pattern. Confirm which before accepting the pass.",
        )
        self.assertEqual(
            [],
            sorted(offenders),
            "a blob/main URL points at a path git is not tracking:\n"
            + "\n".join(sorted(offenders))
            + "\nThese links leave the site, so nothing here fails when the target moves -- the "
            "reader gets a GitHub 404 instead. Repoint them, or restore the file.",
        )


class DocClaimsMatchTheCode(unittest.TestCase):
    def test_all_four_installers_still_test_the_literal_one(self):
        """The doc rule below is only correct while this is."""
        self.assertEqual(
            4,
            len(t.ALL_INSTALLERS),
            "the set of installers has changed. Add the new one to ALL_INSTALLERS -- an installer "
            "this scan does not read is one the rule is not enforced on.",
        )
        for installer in t.ALL_INSTALLERS:
            self.assertRegex(
                t.read(installer),
                r"\$env:CLAUDECODE\s+-eq\s+['\"]1['\"]",
                f"{installer.name} no longer tests $env:CLAUDECODE against the literal '1'. If the "
                "test is now for presence, the docs that say `1` become the wrong ones and this "
                "pin has it backwards -- fix the direction, do not delete the case.",
            )

    def test_no_front_door_describes_the_refusal_as_merely_set(self):
        offenders = []
        for path in (README, LANDING, t.REPO_ROOT / "INSTALL.md"):
            for number, line in enumerate(t.read(path).splitlines(), start=1):
                if CLAUDECODE_LOOSE.search(line):
                    offenders.append(f"{path.name}:{number}: {line.strip()}")
        self.assertEqual(
            [],
            offenders,
            "a document says the installers refuse when $env:CLAUDECODE is *set*:\n"
            + "\n".join(offenders)
            + "\nAll four test the literal string '1'. A reader with CLAUDECODE=0 would find the "
            "installers run. Say `1`.",
        )


class TheScansCanSeeWhatTheyLookFor(unittest.TestCase):
    """Prove each instrument on a planted example. A pattern that matches nothing passes
    everything, and all three patterns here are the kind that silently stop matching after an
    innocuous reformat."""

    def test_the_install_command_pattern_matches_a_real_command(self):
        planted = 'pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target'
        self.assertEqual([planted], INSTALL_COMMAND.findall(planted))

    def test_the_blob_pattern_extracts_the_path_and_stops_at_the_delimiter(self):
        planted = (
            "see [the gate](https://github.com/wshallwshall/claude-multisession/blob/main/"
            "scripts/hooks/worktree_gate.ps1) for the rule"
        )
        self.assertEqual(["scripts/hooks/worktree_gate.ps1"], BLOB_URL.findall(planted))

    def test_the_pattern_also_sees_the_raw_download_form(self):
        """The standards hand out raw links; a scan blind to them checks half the published URLs."""
        planted = (
            "take the [raw markdown](https://raw.githubusercontent.com/wshallwshall/"
            "claude-multisession/main/docs/standards/CODE-QUALITY.md) instead"
        )
        self.assertEqual(["docs/standards/CODE-QUALITY.md"], BLOB_URL.findall(planted))

    def test_the_loose_phrasing_pattern_matches_the_wording_it_exists_to_catch(self):
        self.assertTrue(
            CLAUDECODE_LOOSE.search("All four installers refuse when `$env:CLAUDECODE` is set,")
        )
        self.assertIsNone(
            CLAUDECODE_LOOSE.search("All four installers refuse when `$env:CLAUDECODE` is `1`,"),
            "the pattern must not fire on the correct wording, or the fix cannot make it green.",
        )


if __name__ == "__main__":
    unittest.main()
