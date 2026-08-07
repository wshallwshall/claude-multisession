"""Pin that a deny an agent obeys says WHICH FILE produced it, by content and not by label.

THE FAILURE THIS EXISTS FOR. This gate is published, and it is installed by copying it out of
whatever checkout the installer happened to be run in. So "the installed gate" and "the gate in the
repository I am reading" are routinely different files, and nothing on the machine said so: the deny
reason carried no version and no digest at all, and the receipt log carried `v<GateVersion>`, a
string bumped by hand. That label has already lied once -- three rules were added without a bump, so
-Status printed the same version on both sides directly above a *** STALE *** verdict -- which is why
the gate's own source says it "can never again be the only thing a reader compares".

WHAT THIS PROVES. That both outputs now carry a digest of the file the gate ran FROM, and -- the
case the whole file exists for -- that the digest TRACKS CONTENT: mutate a copy of the gate, run it
again, and the digest must move while the hand-bumped label stays put. Without that case a stamp
reading `sha ...` is a second label wearing a hash's name, which is the exact defect being fixed.
The mirror case matters as much: an UNCHANGED file must hash the same twice, because a digest that
flickers is noise a reader learns to skip past. And the FALLBACK is pinned too: when the digest
cannot be computed the stamp must say so in words, never render a hash-shaped placeholder -- that
is the one remaining place a label could come back wearing the costume.

It also pins that adding provenance moved no VERDICT. A stamp is text appended after a decision has
already been taken; if any command's allow/deny flipped, that is a regression and not a wording
change.

WHAT IT DOES NOT PROVE. Nothing here says the digest matches the file the INSTALLER wrote -- that
comparison is `install-gate.ps1 -Status`, and it is a different question. This runs a COPY, which is
the only way to mutate the gate without editing the shipped one.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

TIMEOUT_SECONDS = 120

# The one line appended to every deny reason, and the one field added to the log record. Both are
# read here as SHAPES rather than as fixed strings, so a reworded stamp still has to carry a version
# and a 12-hex digest to pass.
STAMP = re.compile(
    r"^-- ccx worktree gate rule (?P<rule>\S+) v(?P<version>\S+) sha (?P<sha>\S+) from (?P<self>.*)$",
    re.M,
)
LOG_SHA = re.compile(r"\tsha=(?P<sha>[^\t]+)\t")
LOG_VERSION = re.compile(r"\tv(?P<version>[^\t]+)\t")

# The house fold: 12 lowercase hex characters, identical in install-gate.ps1 -Status,
# bin/ccx-doctor.ps1 and install-selfheal.ps1. A stamp folded differently cannot be compared by eye
# against those, which is the only reason to print a prefix rather than the full digest.
SHA_FOLD = re.compile(r"^[0-9a-f]{12}$")


def _helper_sources() -> list[Path]:
    """The files that must travel beside the gate, derived from the gate's own dot-sources.

    Read out of the code (via the shared closure helper) rather than typed here: a gate that cannot
    load its helpers exits 0 and says so, and a test whose copy list had silently gone stale would
    then be asserting things about a gate that never ran a single rule.
    """
    found: list[Path] = []
    for leaf in sorted(t.gate_dependency_closure()):
        for candidate in (
            t.REPO_ROOT / "scripts" / "hooks" / leaf,
            t.REPO_ROOT / "scripts" / "coord" / leaf,
        ):
            if candidate.exists():
                found.append(candidate)
                break
        else:  # pragma: no cover - a missing helper is a repo defect, not a test outcome
            raise AssertionError(
                f"the gate dot-sources {leaf}, which is in neither scripts/hooks/ nor scripts/coord/."
            )
    return found


class GateHarness(unittest.TestCase):
    """A runnable COPY of the gate, so its bytes can be changed without touching the shipped file."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the gate cannot be executed here")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-gate-prov-")
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)

        # Mirror the INSTALLED layout: gate, helpers and allowlist in one directory, which is also
        # where the gate writes ccx-gate.log (it derives the log directory from the allowlist path).
        self.hooks = root / "hooks"
        self.hooks.mkdir(parents=True)
        self.gate = self.hooks / "worktree_gate.ps1"
        shutil.copy2(t.GATE, self.gate)
        for helper in _helper_sources():
            shutil.copy2(helper, self.hooks / helper.name)

        self.primary = root / "primary"
        self.elsewhere = root / "elsewhere"
        for d in (self.primary, self.elsewhere):
            d.mkdir(parents=True)

        self.allowlist = self.hooks / "ccx-gate.repos.txt"
        self.allowlist.write_text("# fixture\n" + str(self.primary) + "\n", encoding="utf-8")
        self.log = self.hooks / "ccx-gate.log"

    # -- running -------------------------------------------------------------------------------

    def run_gate(self, payload: dict) -> subprocess.CompletedProcess:
        # THE SUBPROCESS cwd IS SET TO THE PAYLOAD'S cwd, deliberately. The gate judges the cwd in
        # the hook payload, but its helpers shell out to `git` with relative paths resolved against
        # the PROCESS's working directory -- so a harness left sitting in the repository under test
        # measures the harness, not the gate. That divergence cost a sibling session two passes of
        # chasing a verdict that came from the test rig's own checkout.
        return subprocess.run(
            [
                self.pwsh,
                "-NoProfile",
                "-File",
                str(self.gate),
                "-ReposFile",
                str(self.allowlist),
            ],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            cwd=payload["cwd"],
            env={**os.environ},
            timeout=TIMEOUT_SECONDS,
        )

    def deny_reason(self, payload: dict) -> str:
        r = self.run_gate(payload)
        self.assertEqual("", r.stderr.strip(), "the gate wrote to stderr:\n" + r.stderr)
        self.assertEqual(0, r.returncode, "a hook must exit 0 and put its decision in the JSON")
        self.assertTrue(r.stdout.strip(), "expected a deny, got silence (which the harness reads as allow)")
        decision = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual("deny", decision["permissionDecision"])
        return decision["permissionDecisionReason"]

    def stamp(self, payload: dict) -> re.Match:
        reason = self.deny_reason(payload)
        m = STAMP.search(reason)
        self.assertIsNotNone(
            m,
            "the deny reason carries no provenance stamp. An agent acting on this text -- and an "
            "operator it quotes the text to -- cannot tell which file produced it.\n" + reason,
        )
        return m

    # -- payloads ------------------------------------------------------------------------------

    def write_payload(self, target: Path, cwd: Path | None = None) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Write",
            "tool_input": {"file_path": str(target)},
            "cwd": str(cwd or self.primary),
        }

    def bash_payload(self, command: str, cwd: Path | None = None) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
            "cwd": str(cwd or self.primary),
        }

    def tool_payload(self, tool: str, cwd: Path | None = None) -> dict:
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": tool,
            "tool_input": {},
            "cwd": str(cwd or self.primary),
        }


class TheDenyReasonCarriesProvenance(GateHarness):
    def test_the_reason_names_the_rule_the_version_and_a_digest(self):
        m = self.stamp(self.write_payload(self.primary / "x.txt"))
        self.assertEqual("1", m.group("rule"), "the stamp must name the rule that fired")
        self.assertEqual(
            gate_version(), m.group("version"), "the stamp's version must be the gate's own label"
        )
        self.assertRegex(
            m.group("sha"),
            SHA_FOLD,
            "the digest is not 12 lowercase hex characters, so it cannot be compared by eye with "
            "`install-gate.ps1 -Status` or bin/ccx-doctor.ps1, which is the whole point of printing "
            "a prefix rather than the full hash.",
        )
        # COMPARE RESOLVED PATHS, NOT RAW STRINGS. Two spellings of one file are still one file, and
        # a raw string comparison quietly encodes an assumption about the machine the test runs on.
        #
        # This assertion passed on every local run and failed on every Windows CI run. The runner's
        # profile directory carries an 8.3 short name, so PowerShell reported
        # C:\Users\RUNNER~1\...\worktree_gate.ps1 where the test had built
        # C:\Users\runneradmin\...\worktree_gate.ps1 -- one file, two spellings -- and the test
        # reported it as the gate stamping the wrong path. The gate was right the whole time.
        #
        # os.path.realpath resolves short names on Windows and is harmless elsewhere, so this
        # compares what the two sides POINT AT rather than how each happened to spell it. Both raw
        # strings are still printed, because when this does fail the spelling is the evidence.
        self.assertEqual(
            os.path.realpath(str(self.gate)),
            os.path.realpath(m.group("self")),
            "the stamp must name the file that RAN. On this machine that is the installed copy, "
            "which is routinely not the file a reader has open.\n"
            f"  expected, as built : {self.gate}\n"
            f"  stamped by the gate: {m.group('self')}",
        )

    def test_the_stamp_is_last_so_it_does_not_displace_the_blocked_sentence(self):
        """bin/ccx-doctor.ps1 prints only the first 200 characters of a reason as its evidence."""
        reason = self.deny_reason(self.write_payload(self.primary / "x.txt"))
        self.assertTrue(
            reason.lstrip().startswith("BLOCKED:"),
            "a reason that no longer opens with BLOCKED: has had its lede pushed down; the doctor's "
            "evidence line and the first thing an agent reads would both become the stamp.",
        )
        # Hoisted rather than inlined as STAMP.search(reason).group(0): under the very defect this
        # file exists to catch there is no stamp, and an inline .group() reports `NoneType has no
        # attribute group` instead of the diagnostic below.
        m = STAMP.search(reason)
        self.assertIsNotNone(m, "the deny reason carries no provenance stamp at all:\n" + reason)
        self.assertTrue(
            reason.rstrip().endswith(m.group(0)),
            "the stamp must be the LAST line of the reason.",
        )

    def test_every_rule_that_denies_here_stamps_its_own_id(self):
        """Stamped centrally in Write-Deny, so no rule can forget it -- including the next one."""
        cases = {
            "1": self.write_payload(self.primary / "x.txt"),
            "1a": self.write_payload(self.allowlist),
            "2": self.tool_payload("Task"),
            "4": self.tool_payload("EnterWorktree"),
        }
        for expected_rule, payload in cases.items():
            with self.subTest(rule=expected_rule):
                self.assertEqual(expected_rule, self.stamp(payload).group("rule"))


class TheLogCarriesTheDigestBesideTheLabel(GateHarness):
    def test_the_receipt_line_carries_both(self):
        sha = self.stamp(self.write_payload(self.primary / "x.txt")).group("sha")
        lines = [ln for ln in self.log.read_text(encoding="utf-8").splitlines() if ln.strip()]
        self.assertEqual(1, len(lines), "expected exactly one receipt for one deny")

        logged_sha = LOG_SHA.search(lines[0])
        self.assertIsNotNone(
            logged_sha,
            "the receipt log carries no sha= field. A label alone is what let a stale gate look "
            "current, and the log is the only durable record of what a deny came from.\n" + lines[0],
        )
        self.assertEqual(
            sha,
            logged_sha.group("sha"),
            "the log and the deny reason disagree about which file ran, in the same process.",
        )
        logged_version = LOG_VERSION.search(lines[0])
        self.assertIsNotNone(logged_version, "the version label was dropped from the receipt")
        self.assertEqual(
            gate_version(),
            logged_version.group("version"),
            "the digest goes BESIDE the label, not instead of it: a reader diffing two records has "
            "to be able to see the label agree while the digest disagrees.",
        )


class TheDigestTracksContent(GateHarness):
    """The load-bearing case. Everything else here passes just as well for a hard-coded string."""

    def test_it_is_the_hash_of_the_file_it_ran_from(self):
        sha = self.stamp(self.write_payload(self.primary / "x.txt")).group("sha")
        self.assertEqual(
            hashlib.sha256(self.gate.read_bytes()).hexdigest()[:12],
            sha,
            "the stamped digest is not SHA-256 of the bytes of the file the gate ran from, computed "
            "independently here. Whatever it is a digest OF, it is not the artifact.",
        )

    def test_changing_the_file_changes_the_digest_and_not_the_label(self):
        """The measured incident, reproduced: same version, different file."""
        before = self.stamp(self.write_payload(self.primary / "x.txt"))

        with self.gate.open("ab") as fh:  # ASCII only: scripts/quality/check-ascii.ps1 scans the tree
            fh.write(b"\n# provenance probe: one comment line, no behaviour\n")

        after = self.stamp(self.write_payload(self.primary / "x.txt"))
        self.assertNotEqual(
            before.group("sha"),
            after.group("sha"),
            "the gate's bytes changed and the stamped digest did not. That is a SECOND LABEL wearing "
            "a hash's name -- it would report a stale installed gate as identical to the source, "
            "which is exactly the failure this stamp was added to end.",
        )
        self.assertEqual(
            hashlib.sha256(self.gate.read_bytes()).hexdigest()[:12],
            after.group("sha"),
            "the digest moved, but not to the hash of the new content.",
        )
        self.assertEqual(
            before.group("version"),
            after.group("version"),
            "the hand-bumped label must NOT move on its own -- if it tracked content it would be a "
            "hash, and the pair would carry one fact instead of two.",
        )

    def test_an_unchanged_file_hashes_the_same_twice(self):
        """A digest that flickers is noise, and a reader stops comparing it."""
        first = self.stamp(self.write_payload(self.primary / "x.txt")).group("sha")
        second = self.stamp(self.write_payload(self.primary / "y.txt")).group("sha")
        self.assertEqual(
            first,
            second,
            "two runs of the SAME file produced different digests. Nothing downstream can treat a "
            "difference as meaningful after that.",
        )

    def test_an_uncomputable_digest_says_so_in_words_rather_than_looking_like_one(self):
        """The one place a label could come back wearing a hash's costume.

        The gate fails open on a hash it cannot compute, which is right -- provenance must never
        block a deny. What it must not do is render the absence as `000000000000` or an empty
        12-hex-shaped token: a reader comparing that against `install-gate.ps1 -Status` would be
        comparing a placeholder to a digest and would be told they differ for the wrong reason. It
        has to be a WORD, so it cannot be mistaken for a measurement.

        Reproduced by pointing the copy at a file that does not exist -- the same condition as the
        two real cases: the gate removed or replaced under a live invocation, and an invocation with
        no $PSCommandPath at all (measured: a piped-stdin call logged `sha=unavailable`).
        """
        marker = "$script:GateSelf = if ($PSCommandPath)"
        source = self.gate.read_text(encoding="utf-8")
        line = next((ln for ln in source.splitlines() if ln.startswith(marker)), None)
        self.assertIsNotNone(
            line,
            "worktree_gate.ps1 no longer resolves $script:GateSelf on one line starting "
            f"{marker!r}, so this test can no longer make the digest uncomputable and would pass "
            "vacuously. Re-point it at whatever names the running file now.",
        )
        missing = self.hooks / "no-such-gate.ps1"
        self.assertFalse(missing.exists())
        self.gate.write_text(
            source.replace(line, f"$script:GateSelf = '{missing}'"), encoding="utf-8"
        )

        m = self.stamp(self.write_payload(self.primary / "x.txt"))
        self.assertEqual(
            "unavailable",
            m.group("sha"),
            "an uncomputable digest is being rendered as something else. If that something is "
            "hex-shaped it is a label again, which is the defect this whole file exists to close.",
        )
        self.assertNotRegex(
            m.group("sha"),
            SHA_FOLD,
            "the placeholder for a MISSING digest has the shape of a real one.",
        )
        self.assertIn(
            "\tsha=unavailable\t",
            self.log.read_text(encoding="utf-8"),
            "the receipt log disagrees with the reason about whether a digest was available.",
        )


class NoVerdictMoved(GateHarness):
    """Provenance is text appended after a decision. If a verdict moved, this is a regression."""

    def decision(self, payload: dict) -> str:
        r = self.run_gate(payload)
        self.assertEqual("", r.stderr.strip(), "the gate wrote to stderr:\n" + r.stderr)
        self.assertEqual(0, r.returncode)
        if not r.stdout.strip():
            return "allow"
        return json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"]

    def test_the_commands_that_denied_before_still_deny(self):
        cases = {
            "a write into the primary (rule 1)": self.write_payload(self.primary / "x.txt"),
            "a write to the gate's own allowlist (rule 1a)": self.write_payload(self.allowlist),
            "a subagent dispatch from the primary (rule 2)": self.tool_payload("Task"),
            "a workflow dispatch from the primary (rule 2)": self.tool_payload("Workflow"),
            "relocating a live session (rule 4)": self.tool_payload("EnterWorktree"),
            "a checkout of the primary (rule 3)": self.bash_payload("git checkout main"),
            "a hard reset of the primary (rule 3)": self.bash_payload("git reset --hard HEAD~1"),
        }
        for name, payload in cases.items():
            with self.subTest(case=name):
                self.assertEqual("deny", self.decision(payload), name)

    def test_the_commands_that_were_allowed_still_are(self):
        cases = {
            "a write outside every governed root": self.write_payload(
                self.elsewhere / "x.txt", cwd=self.elsewhere
            ),
            "a write into a harness worktree under the primary": self.write_payload(
                self.primary / ".claude" / "worktrees" / "task" / "x.txt"
            ),
            "a tool the gate does not handle": self.tool_payload("Read"),
            "ExitWorktree, which is a safe keep": self.tool_payload("ExitWorktree"),
            "a read-only git command in the primary": self.bash_payload("git status --short"),
            "an ordinary shell command in the primary": self.bash_payload("echo hello"),
            "a commit in the primary": self.bash_payload("git commit -m fix"),
        }
        for name, payload in cases.items():
            with self.subTest(case=name):
                self.assertEqual("allow", self.decision(payload), name)

    def test_an_allow_still_emits_absolutely_nothing(self):
        """The stamp must never be computed or printed off the deny path."""
        r = self.run_gate(self.write_payload(self.elsewhere / "x.txt", cwd=self.elsewhere))
        self.assertEqual("", r.stdout.strip())
        self.assertEqual("", r.stderr.strip())
        self.assertFalse(
            self.log.exists() and self.log.read_text(encoding="utf-8").strip(),
            "an allowed call left a receipt. The log counts denies; a line here makes every count "
            "taken from it wrong.",
        )


def gate_version() -> str:
    """The gate's hand-bumped label, read out of the gate rather than typed here."""
    m = re.search(r'\$GateVersion\s*=\s*"([^"]+)"', t.read(t.GATE))
    if not m:
        raise AssertionError(
            "worktree_gate.ps1 no longer declares $GateVersion. install-gate.ps1 -Status scrapes it "
            "with the same pattern, so it is not only this test that stopped being able to read it."
        )
    return m.group(1)


if __name__ == "__main__":
    unittest.main()
