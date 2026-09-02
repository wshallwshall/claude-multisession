"""A number is claimed by EXCLUSIVELY CREATING a file named for it, once per configured sequence.

THE FAILURE THIS EXISTS FOR. The tempting way to allocate is to read the highest number in use and
add one. Two sessions that both read take the SAME number, create DIFFERENTLY-named files, and merge
CLEAN. There is no textual conflict, so git cannot see it, `git merge-tree` cannot see it, and a file
lock over the ledger would not have been held across the two reads anyway. It happened three times in
the repository this tooling came from, and the ledger was corrupt each time with nothing reporting a
problem.

`alloc.ps1` therefore claims with `FileMode::CreateNew` plus `FileShare::None`, and the IOException
that throw raises IS the mutual exclusion. Nothing in this file is testing the number that comes
back. It is testing that the claim step stays a test-and-set.

WHY THIS ARRIVES WITH THE SECOND SEQUENCE. `sequences` is a map, so a repository keeping decision
records and a backlog declares both, and the registry partitions by kind. That partition is the only
thing keeping two ledgers apart, and it had never been executed with two kinds present -- so
`ASecondSequenceIsAllocatedIndependently` runs the case the mechanism was generalised for.

WHAT THE CONCURRENT CASE ACTUALLY EXERCISES, and why the overlap case sits beside it. Eight
allocator PROCESSES are started against one fixture repository from a thread pool, and the numbers
they report must be eight distinct ones. That assertion is vacuous if the eight ran one after
another, and a green vacuous assertion is exactly what this suite refuses elsewhere, so the wall
clocks are recorded and a separate case requires that at least two runs genuinely overlapped. If the
machine serialises them, that case fails and says the measurement was not taken.

THE TIMING CASES ARE NOT THE STRONGEST ONES HERE, on purpose. `AClaimNeverOverwritesASiblings` needs
no concurrency at all: it plants a claim file the way a sibling session would have left one and
requires the allocator to step over it with the bytes untouched. That goes red the moment `CreateNew`
becomes `Create`, or the moment the claim becomes a read-modify-write over a shared list, on every
machine and at any speed.

WHAT THIS DOES NOT PROVE. Not that two allocators can never both be inside `Get-Floor`; they can,
and they are meant to -- the floor is a hint and the claim is the guard. Not that the registry is
safe against a caller deleting it. And not that two sequences whose patterns merely overlap are
caught: `AConfigThatCouldCollideIsRefused` pins the identical case, which is the one that can be
proved, and the allocator says so rather than implying more.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import _ccxtest as t

ALLOC = t.REPO_ROOT / "scripts" / "coord" / "alloc.ps1"
SHIPPED_CONFIG = t.REPO_ROOT / "ccx.config.json"

TIMEOUT_SECONDS = 180

# How many allocator processes race. Eight is the figure docs/SEQUENCE-ALLOC.md quotes for this
# mechanism, so the case measures the claim the document makes rather than a rounder number.
RACERS = 8

# A fixture repo must not inherit the operator's identity, signing config, or advice settings: a
# commit that needs a passphrase, or a hook that runs, turns a test failure into a hang.
GIT_ID = (
    "-c", "user.email=ccx@test", "-c", "user.name=ccx test",
    "-c", "commit.gpgsign=false", "-c", "advice.detachedHead=false",
)

# `ALLOCATED <kind> <number>` is the line the tool prints on success and the only machine-readable
# thing it emits. Matched with the kind captured too, so a case cannot pass on another kind's line.
ALLOCATED = re.compile(r"^ALLOCATED (\S+) (\S+)\s*$", re.M)

ADR = {
    "dir": "docs/adr",
    "filePattern": r"^docs/adr/(\d{4})-[^/]+\.md$",
    "pad": 4,
}
BACKLOG = {
    "dir": "docs/backlog",
    "filePattern": r"^docs/backlog/(\d+)-[^/]+\.md$",
    "pad": 0,
}


class AllocatorFixture(unittest.TestCase):
    """A throwaway repository with a configured sequence, and a way to run the allocator at it."""

    # Overridden per case. `trunk` is pinned rather than 'auto': the fixture has no remote, so there
    # is no recorded default branch for auto to resolve.
    SEQUENCES: dict = {"adr": ADR}
    SEEDS: dict = {}

    @classmethod
    def build_repo(cls, base: Path, sequences: dict, seeds: dict) -> Path:
        repo = base / "repo"
        repo.mkdir(parents=True)
        cls.run_git(repo, "init", "-q", "-b", "main")
        (repo / "ccx.config.json").write_text(
            json.dumps({"prefix": "ccx", "trunk": "main", "sequences": sequences}, indent=2),
            encoding="utf-8",
        )
        for relpath, body in seeds.items():
            target = repo / relpath
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body, encoding="utf-8")
        cls.run_git(repo, "add", "-A")
        cls.run_git(repo, "commit", "-qm", "init")
        return repo

    @staticmethod
    def run_git(cwd: Path, *args: str) -> str:
        r = subprocess.run(
            ["git", *GIT_ID, *args],
            cwd=str(cwd), capture_output=True, text=True, timeout=TIMEOUT_SECONDS,
        )
        if r.returncode != 0:
            raise AssertionError(f"git {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
        return r.stdout

    @staticmethod
    def clean_env() -> dict:
        env = dict(os.environ)
        # The real session's coordination variables must not reach the fixture. CCX_CONFIG in
        # particular would redirect discovery at this repository's own config, and every case here
        # would then measure the wrong sequences while looking perfectly healthy.
        for leak in ("CCX_CONFIG", "CCX_TRUNK", "CCX_STATE_ROOT"):
            env.pop(leak, None)
        return env

    @classmethod
    def run_alloc(cls, pwsh: str, repo: Path, *args: str,
                  script: Path | None = None, extra_env: dict | None = None):
        # cwd is the fixture, so config discovery walks up from there and finds the fixture's file.
        # That is the production path: nothing passes the config in.
        env = cls.clean_env()
        env.update(extra_env or {})
        return subprocess.run(
            [pwsh, "-NoProfile", "-File", str(script or ALLOC), *args],
            capture_output=True, text=True, env=env,
            cwd=str(repo), timeout=TIMEOUT_SECONDS,
        )

    @staticmethod
    def registry(repo: Path, kind: str) -> Path:
        """Where claims for `kind` live. Derived the way the scripts derive it, from the COMMON dir."""
        return repo / ".git" / "ccx-coord" / "alloc" / kind

    @staticmethod
    def claimed_numbers(registry: Path) -> list[str]:
        return sorted(p.stem for p in registry.glob("*.json"))

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so alloc.ps1 cannot be executed here")
        if not shutil.which("git"):
            self.skipTest("git is not on PATH, so the fixture repository cannot be built")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-alloc-", ignore_cleanup_errors=True)
        self.addCleanup(self.tmp.cleanup)
        self.repo = self.build_repo(Path(self.tmp.name), self.SEQUENCES, self.SEEDS)

    def alloc(self, *args: str) -> subprocess.CompletedProcess:
        return self.run_alloc(self.pwsh, self.repo, *args)

    def allocate(self, kind: str, title: str) -> str:
        """Allocate and return the number, failing with the tool's own output if it did not."""
        r = self.alloc("-Kind", kind, "-Title", title)
        found = ALLOCATED.findall(r.stdout)
        self.assertEqual(
            1, len(found),
            f"allocating {kind} did not print exactly one ALLOCATED line (exit {r.returncode}).\n"
            f"stdout:\n{r.stdout}\nstderr:\n{r.stderr}",
        )
        self.assertEqual(kind, found[0][0], "the allocator reported a different kind than was asked for")
        return found[0][1]


class TwoSessionsCannotTakeOneNumber(unittest.TestCase):
    """Race real allocator processes and require distinct numbers -- and require a real race.

    THE RUN IS DONE ONCE for the whole class. Eight processes each sweep every ref of the fixture,
    so repeating it per case would pay for the same measurement three times and prove nothing extra.
    """

    @classmethod
    def setUpClass(cls):
        cls.pwsh = t.find_pwsh()
        if not cls.pwsh or not shutil.which("git"):
            raise unittest.SkipTest("pwsh and git are both needed to race the allocator")
        cls.tmp = tempfile.TemporaryDirectory(prefix="ccx-alloc-race-", ignore_cleanup_errors=True)
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.repo = AllocatorFixture.build_repo(Path(cls.tmp.name), {"adr": ADR}, {})

        def one(i: int):
            started = time.monotonic()
            r = AllocatorFixture.run_alloc(cls.pwsh, cls.repo, "-Kind", "adr", "-Title", f"racer {i}")
            return started, time.monotonic(), r

        with ThreadPoolExecutor(max_workers=RACERS) as pool:
            cls.results = list(pool.map(one, range(RACERS)))

    def numbers(self) -> list[str]:
        out = []
        for _, _, r in self.results:
            out.extend(num for kind, num in ALLOCATED.findall(r.stdout) if kind == "adr")
        return out

    def test_every_racer_finished_and_claimed_something(self):
        """A crash before the claim is how the count goes down without a duplicate appearing.

        This is not a tidiness case. Before the high-water ratchet learned that its own file is
        shared state, one of eight processes died writing it -- inside the floor sweep, before it had
        claimed anything. Eight sessions asked for a number, seven got one, the exclusion was never
        even reached, and the distinctness case below was green throughout.
        """
        failures = [
            f"exit {r.returncode}:\n{r.stderr.strip()}"
            for _, _, r in self.results if r.returncode != 0
        ]
        self.assertEqual(
            [], failures,
            f"{len(failures)} of {RACERS} concurrent allocations failed. A session that asks for a "
            "number and gets an exception has to be retried by hand, and a distinctness check "
            "cannot see the ones that never claimed:\n" + "\n\n".join(failures),
        )
        self.assertEqual(
            RACERS, len(self.numbers()),
            "fewer ALLOCATED lines than racers. Some process exited 0 without claiming.",
        )

    def test_no_two_racers_took_the_same_number(self):
        """The headline property. A duplicate here is the silent ledger corruption itself."""
        numbers = self.numbers()
        duplicates = sorted({n for n in numbers if numbers.count(n) > 1})
        self.assertEqual(
            [], duplicates,
            f"{RACERS} concurrent allocations returned {sorted(numbers)}, and {duplicates} was "
            "handed out more than once. Two sessions now write differently-named files for one "
            "number, they merge clean, and nothing downstream reports it. The claim step is no "
            "longer a test-and-set.",
        )

    def test_the_registry_holds_one_file_per_number_handed_out(self):
        """The claim is the file. If the two disagree, the exclusion is not what issued the number."""
        registry = AllocatorFixture.registry(self.repo, "adr")
        self.assertEqual(
            sorted(self.numbers()), AllocatorFixture.claimed_numbers(registry),
            "the numbers reported and the claim files on disk are not the same set. A number "
            "reported without a file behind it is one the next allocation will hand out again.",
        )

    def test_the_racers_actually_overlapped(self):
        """The control. Without this, a serialised run passes the case above and measures nothing.

        Distinct numbers from eight processes that never coexisted is not evidence of anything: a
        read-modify-write allocator returns eight distinct numbers too, if it is never asked twice at
        once. So the wall clocks are read back and at least one moment must have carried two live
        allocator processes.
        """
        events = []
        for started, ended, _ in self.results:
            events.append((started, 1))
            events.append((ended, -1))
        events.sort()
        live = peak = 0
        for _, delta in events:
            live += delta
            peak = max(peak, live)
        self.assertGreaterEqual(
            peak, 2,
            f"the {RACERS} allocator runs never overlapped (peak concurrency {peak}). They ran one "
            "after another, so the distinctness case above proved nothing about exclusion. This is "
            "a defect in the measurement, not in the allocator.",
        )


class ANumberAlreadyClaimedIsNotOffered(AllocatorFixture):
    """A claim is a number in use even though nothing is written in the repository yet.

    This is the FLOOR's fourth term, not the claim step. It is a real property -- a session that has
    taken 0001 and not yet written the file must not have it handed to somebody else -- and it is
    also the reason the case below needs a shim: with the registry in the floor, the loop never
    revisits a number a claim file already exists for, so a planted file can never reach the open.
    Measured: swap `CreateNew` for `Create` and every case in this class stays green.
    """

    SENTINEL = '{"number":"0001","kind":"adr","title":"held by a sibling session"}'

    def plant(self, number: str) -> Path:
        registry = self.registry(self.repo, "adr")
        registry.mkdir(parents=True, exist_ok=True)
        claim = registry / f"{number}.json"
        claim.write_text(self.SENTINEL, encoding="utf-8")
        return claim

    def test_an_unheld_sequence_starts_at_one(self):
        """The negative control, and it has to run first in the reader's head, not just in the file.

        Without it, `0002` below is equally consistent with a fixture that would have said 0002
        anyway -- and then the planted file proved nothing at all.
        """
        self.assertEqual("0001", self.allocate("adr", "nothing is held yet"))

    def test_a_planted_claim_is_not_handed_out_again(self):
        claim = self.plant("0001")
        self.assertEqual(
            "0002", self.allocate("adr", "a sibling already holds 0001"),
            "the allocator handed out a number another session had already claimed.",
        )
        self.assertEqual(
            self.SENTINEL, claim.read_text(encoding="utf-8"),
            "the allocator REWROTE a claim file it did not own. The sibling that holds this number "
            "still believes it does, and both will write a file for it.",
        )

    def test_a_run_of_held_numbers_is_stepped_over_together(self):
        """One skip can be luck. Three consecutive ones is the loop doing its job."""
        for n in ("0001", "0002", "0003"):
            self.plant(n)
        self.assertEqual("0004", self.allocate("adr", "three are held"))


class TheClaimIsATestAndSet(AllocatorFixture):
    """Two claims for ONE number, and only one of them may succeed -- proved without a stopwatch.

    THE WINDOW IS THE WHOLE POINT, and it is narrow: between the floor sweep deciding the number is
    free and the `File.Open` that takes it. Racing eight processes does not reliably land inside it.
    Measured on this fixture: with the claim mutated from `CreateNew` to `Create`, eight concurrent
    allocations still returned eight distinct numbers and every timing-based case stayed green. A
    race that has to get lucky to see the defect is a test that reports on the scheduler.

    So the sibling is placed there DELIBERATELY. `scripts/` is copied, and one line is inserted into
    the copy's claim loop that writes the claim file the instant the allocator has decided which one
    to open. That is a sibling session winning by a microsecond, made to happen every time.

    THE INSERTION WRAPS THE PRODUCTION LINE RATHER THAN REPLACING IT. The `File.Open` under test is
    the shipped one, untouched; only the moment of the collision is supplied. And the anchor is
    asserted before use, so a rewritten loop fails loudly here instead of quietly measuring nothing.

    Read the two outcomes: `CreateNew` throws, the loop moves to 0002, and the sibling keeps 0001.
    `Create`, `OpenOrCreate`, or any read-modify-write over a shared list takes 0001 as well, and
    both sessions then write a differently-named file for one number.
    """

    SEQUENCES = {"adr": ADR}
    SENTINEL = '{"number":"0001","kind":"adr","title":"a sibling got here first"}'

    # The line that names the claim file, matched whole. Everything after it in the loop is the
    # test-and-set itself, so this is the last moment a sibling could still arrive.
    ANCHOR = '    $file = Join-Path $alloc "$name.json"\n'
    ARRIVAL = (
        '    if ($env:CCX_TEST_ARRIVE) {\n'
        '        [System.IO.File]::WriteAllText($file, $env:CCX_TEST_ARRIVE)\n'
        '        $env:CCX_TEST_ARRIVE = $null\n'
        '    }\n'
    )

    def shimmed_allocator(self) -> Path:
        tree = Path(self.tmp.name) / "tree"
        shutil.copytree(t.REPO_ROOT / "scripts", tree / "scripts")
        script = tree / "scripts" / "coord" / "alloc.ps1"
        source = script.read_text(encoding="utf-8")
        self.assertIn(
            self.ANCHOR, source,
            "alloc.ps1 no longer contains the line that names the claim file, so the arrival cannot "
            "be placed inside the window. This case would then run an unmodified allocator against "
            "no collision at all and pass -- fix the anchor rather than deleting the case.",
        )
        self.assertEqual(
            1, source.count(self.ANCHOR),
            "the anchor appears more than once, so the arrival would fire somewhere unintended.",
        )
        script.write_text(source.replace(self.ANCHOR, self.ANCHOR + self.ARRIVAL), encoding="utf-8")
        return script

    def claim_against_an_arrival(self, arrival: str | None):
        return self.run_alloc(
            self.pwsh, self.repo, "-Kind", "adr", "-Title", "racing a sibling",
            script=self.shimmed_allocator(),
            extra_env={"CCX_TEST_ARRIVE": arrival} if arrival else None,
        )

    def test_the_shim_changes_nothing_when_no_sibling_arrives(self):
        """The control. Without it, `0002` below could be the shim itself skewing the fixture."""
        r = self.claim_against_an_arrival(None)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual([("adr", "0001")], ALLOCATED.findall(r.stdout))

    def test_a_sibling_arriving_inside_the_window_keeps_the_number(self):
        r = self.claim_against_an_arrival(self.SENTINEL)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual(
            [("adr", "0002")], ALLOCATED.findall(r.stdout),
            "a sibling claimed 0001 in the window between the floor and the open, and the allocator "
            "took 0001 anyway. Two sessions now hold one number. The claim step is no longer a "
            "test-and-set:\n" + r.stdout,
        )
        claim = self.registry(self.repo, "adr") / "0001.json"
        self.assertEqual(
            self.SENTINEL, claim.read_text(encoding="utf-8"),
            "the allocator OVERWROTE the sibling's claim file. The sibling still believes it holds "
            "0001, and nothing anywhere will report the collision.",
        )

    def test_the_loser_writes_its_own_claim_and_leaves_the_other_alone(self):
        self.claim_against_an_arrival(self.SENTINEL)
        self.assertEqual(
            ["0001", "0002"], self.claimed_numbers(self.registry(self.repo, "adr")),
            "after stepping over a held number the allocator must still have claimed its own.",
        )


class ASecondSequenceIsAllocatedIndependently(AllocatorFixture):
    """Two ledgers in one repository: separate registries, separate floors, no shared state.

    THE FAILURE THIS EXISTS FOR. A repository with two number spaces that cannot declare the second
    one grows a hand-rolled path for it, and then there are two definitions of what a number is. The
    `sequences` block takes as many as the repository has -- but the partition between them had never
    been executed with two kinds present, so nothing said whether one ledger's numbers moved the
    other's floor.
    """

    SEQUENCES = {"adr": ADR, "backlog": BACKLOG}
    # Each seeded at a different height, so a case cannot pass on the two happening to agree.
    SEEDS = {
        "docs/adr/0007-a-decision.md": "seed\n",
        "docs/backlog/42-an-item.md": "seed\n",
    }

    def test_each_sequence_continues_its_own_numbering(self):
        self.assertEqual("0008", self.allocate("adr", "next decision"))
        self.assertEqual(
            "43", self.allocate("backlog", "next item"),
            "the backlog was handed a number derived from something other than the backlog. If the "
            "two sequences share a floor, the sparser one develops holes and the denser one "
            "eventually collides.",
        )

    def test_one_sequences_allocation_does_not_move_the_others_floor(self):
        """The pooling case. Red if the floor is ever computed over all sequences at once."""
        for i in range(3):
            self.allocate("backlog", f"item {i}")
        self.assertEqual(
            "0008", self.allocate("adr", "still the eighth decision"),
            "three backlog allocations moved the decision-record floor. The two ledgers are sharing "
            "a number space.",
        )

    def test_a_number_claimed_in_one_registry_is_free_in_the_other(self):
        """Independence in the direction that looks alarming and is correct.

        Both sequences legitimately hand out the digits 43 and 0043; they are different numbers in
        different ledgers. A registry keyed on the number alone would refuse the second, which is the
        wrong fix for the right worry.
        """
        self.allocate("backlog", "item 43")
        self.assertIn("43", self.claimed_numbers(self.registry(self.repo, "backlog")))
        self.assertEqual(
            [], self.claimed_numbers(self.registry(self.repo, "adr")),
            "a backlog allocation wrote into the decision-record registry.",
        )

    def test_the_padding_is_read_per_sequence(self):
        """`pad` belongs to the entry. Sharing one width silently renames one ledger's files."""
        self.assertEqual("0008", self.allocate("adr", "four wide"))
        self.assertEqual("43", self.allocate("backlog", "unpadded"))

    def test_kind_becomes_required_once_a_second_sequence_exists(self):
        r = self.alloc("-Title", "which ledger did you mean")
        self.assertNotEqual(
            0, r.returncode,
            "with two sequences configured the allocator guessed which one was meant. A wrong guess "
            "here spends a number out of the wrong ledger, and numbers are never reclaimed.",
        )
        for kind in self.SEQUENCES:
            self.assertIn(
                kind, r.stderr,
                f"the refusal did not name the configured sequence '{kind}', so the reader has to "
                "go and read the config to find out what to type.",
            )

    def test_list_reports_both_sequences(self):
        self.allocate("adr", "one")
        self.allocate("backlog", "two")
        r = self.alloc("-List")
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertIn("adr allocated to this worktree: 0008", r.stdout)
        self.assertIn("backlog allocated to this worktree: 43", r.stdout)


class TheHighWaterMarkIsSharedStateAndTheCallersAreConcurrent(AllocatorFixture):
    """The ratchet file is read and written by every allocator, and it is not the exclusion.

    THE FAILURE THIS EXISTS FOR. `Set-Content` and `Get-Content` each open a file without sharing it,
    so two allocators reaching the ratchet together threw an unhandled exception. Measured on this
    fixture before the fix: eight simultaneous allocations returned SEVEN numbers. One process died
    inside the floor sweep, before claiming anything -- so no number was duplicated, nothing looked
    corrupt, and a session simply got an exception instead of a number.

    THE TWO SIDES ARE GUARDED DIFFERENTLY AND BOTH CASES BELOW PIN THAT. A lost WRITE is recoverable,
    because the floor this run computed is already correct and the registry re-derives it next time,
    so the allocation must still succeed. A lost READ is not: treating an unreadable ratchet as zero
    silently lowers the floor, which is how a number already in use gets handed out again, so it must
    refuse. Swapping those two is the tempting simplification and it is the wrong one in both
    directions.

    THE CONTENTION IS SUPPLIED, NOT RACED, for the reason `TheClaimIsATestAndSet` records: a defect
    that needs two processes inside a few microseconds of each other reports on the scheduler.
    """

    SEQUENCES = {"adr": ADR}
    # Something must already exist for the floor to rise above zero, or no write is attempted at all
    # and both cases below would pass against an allocator that never touched the file.
    SEEDS = {"docs/adr/0001-a-decision.md": "seed\n"}

    HOLD_ANCHOR = "    $floor = [Math]::Max($computed, $previous)\n"
    HOLD = (
        '    if ($env:CCX_TEST_HOLD_WATERMARK) {\n'
        '        $null = [System.IO.File]::Open($watermark, [System.IO.FileMode]::OpenOrCreate,'
        ' [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)\n'
        '    }\n'
    )

    def allocator_holding_the_watermark(self) -> Path:
        """A copy that grabs the ratchet exclusively after reading it, standing in for a sibling."""
        tree = Path(self.tmp.name) / "held"
        shutil.copytree(t.REPO_ROOT / "scripts", tree / "scripts")
        script = tree / "scripts" / "coord" / "alloc.ps1"
        source = script.read_text(encoding="utf-8")
        self.assertIn(
            self.HOLD_ANCHOR, source,
            "alloc.ps1 no longer computes the floor at the anchor this case inserts after, so the "
            "hold would land in the wrong place and the case would measure nothing.",
        )
        script.write_text(
            source.replace(self.HOLD_ANCHOR, self.HOLD + self.HOLD_ANCHOR, 1), encoding="utf-8"
        )
        return script

    def watermark(self) -> Path:
        return self.registry(self.repo, "adr") / ".floor-highwater"

    def test_an_ordinary_run_does_raise_the_ratchet(self):
        """The control. Both cases below are vacuous if this fixture never writes the file at all."""
        self.assertEqual("0002", self.allocate("adr", "ordinary"))
        self.assertEqual(
            "1", self.watermark().read_text(encoding="utf-8").strip(),
            "the ratchet was not written on a run whose floor rose, so the cases below are testing "
            "a code path this fixture does not reach.",
        )

    def test_a_sibling_holding_the_ratchet_does_not_kill_the_allocation(self):
        r = self.run_alloc(
            self.pwsh, self.repo, "-Kind", "adr", "-Title", "the ratchet is held",
            script=self.allocator_holding_the_watermark(),
            extra_env={"CCX_TEST_HOLD_WATERMARK": "1"},
        )
        self.assertEqual(
            0, r.returncode,
            "a sibling holding the high-water file killed the allocation. The ratchet is a hint the "
            "registry can re-derive; it is not the exclusion, and it must not be able to refuse a "
            "session a number:\n" + r.stderr,
        )
        self.assertEqual(
            [("adr", "0002")], ALLOCATED.findall(r.stdout),
            "the run survived but handed out a different number, so the floor it computed was not "
            "the one it would have computed alone:\n" + r.stdout,
        )

    # The refusal's own wording. Asserting on it is what makes the cases below discriminate: the
    # allocator must stop THROUGH ITS OWN GUARD, not because some provider error happened to escape.
    REFUSAL = "Refusing to allocate"

    def test_an_unreadable_ratchet_refuses_rather_than_reading_as_zero(self):
        """The opposite asymmetry, and the one that matters more.

        A directory where the file should be is a stand-in for any read that cannot be satisfied. The
        wrong response is to shrug and carry on with `previous = 0`: the floor then silently forgets
        every number the ratchet was remembering, which is the exact hole it was added to close.

        A NON-ZERO EXIT DOES NOT PIN THIS, and an earlier version of this case checked nothing else.
        `Get-Content` on a directory raises whether or not the guard is there, so the case stayed
        green with the refusal replaced by `previous = 0`, and green again with the whole guard
        reverted to the unguarded one-liner. It was green in three states and told them apart in
        none. The message assertion below is the discriminator: only the guard produces it.
        """
        self.watermark().mkdir(parents=True)
        r = self.alloc("-Kind", "adr", "-Title", "the ratchet cannot be read")
        self.assertNotEqual(
            0, r.returncode,
            "the allocator allocated with the high-water mark unreadable. It has just forgotten "
            "every number that lived only in the ratchet, and it said nothing:\n" + r.stdout,
        )
        self.assertIn(
            self.REFUSAL, r.stderr,
            "the run failed, but not through its own refusal. A directory raises "
            "InvalidOperationException, which the typed catches did not name, so it escaped the "
            "retry loop and killed the script inside Get-Content -- the operator gets a provider "
            "message about using Get-ChildItem instead of the explanation:\n" + r.stderr,
        )
        self.assertEqual(
            [], self.claimed_numbers(self.registry(self.repo, "adr")),
            "it refused, but only after claiming a number. A refusal that spends a number is not a "
            "refusal -- numbers are never reclaimed.",
        )

    def test_an_empty_ratchet_refuses_and_does_not_report_contention(self):
        """The arm a broken guard actually fails, which is why it is here.

        Every other case in this class supplies a ratchet that RAISES. This one supplies a ratchet
        that reads perfectly and holds nothing: `Get-Content -Raw` returns $null for a zero-byte file
        and raises nothing at all. So there is no exception to catch and no retry to exhaust, and an
        allocator that treats a null read as `previous = 0` allocates happily -- exit 0, a number
        handed out, the ratchet's memory gone and nothing said. That is the silent floor-lowering
        this whole guard exists to prevent, and it is reachable without anyone truncating the file by
        hand: the staged write was non-terminating, so a failed stage left an empty temp to be moved
        over a good ratchet.

        The second assertion is about honesty rather than safety. Before the fix this input reached
        the CONTENTION throw, which reports twenty attempts and prints its cause after "attempts: ".
        One attempt had been made and it had succeeded, and the cause was empty -- so an absent cause
        and a real one rendered identically, in the one message an operator reads to tell them apart.
        """
        self.assertEqual("0002", self.allocate("adr", "raise the ratchet first"))
        wm = self.watermark()
        self.assertTrue(wm.is_file(), "the ratchet was never written, so this case supplies nothing")
        wm.write_text("", encoding="utf-8")

        r = self.alloc("-Kind", "adr", "-Title", "the ratchet is empty")
        self.assertNotEqual(
            0, r.returncode,
            "the allocator read an empty high-water mark as a floor of zero and allocated. Every "
            "number that lived only in the ratchet is now free to be handed out again:\n" + r.stdout,
        )
        self.assertIn(
            self.REFUSAL, r.stderr,
            "the run failed without the guard's own refusal in it:\n" + r.stderr,
        )
        self.assertIn(
            "is empty", r.stderr,
            "it refused, but did not say the file was empty, so the operator cannot tell this from "
            "a locked file:\n" + r.stderr,
        )
        self.assertNotIn(
            "after 20 attempts", r.stderr,
            "it reported contention over a read that succeeded on its first attempt. There was no "
            "contention, and the cause printed after 'attempts: ' is empty:\n" + r.stderr,
        )

    def test_a_ratchet_holding_something_other_than_a_number_refuses(self):
        """The quietest road to the same place, and the only one with no failed read at all.

        `[int]::TryParse` returns false and leaves its target untouched, so a ratchet holding a word
        left `$previous` at its initialised 0 and the run allocated. Nothing raised, nothing was
        null, and the floor silently forgot everything the ratchet knew.
        """
        self.assertEqual("0002", self.allocate("adr", "raise the ratchet first"))
        self.watermark().write_text("not-a-number\n", encoding="utf-8")

        r = self.alloc("-Kind", "adr", "-Title", "the ratchet is garbage")
        self.assertNotEqual(
            0, r.returncode,
            "an unparseable high-water mark read as a floor of zero and the run allocated:\n" + r.stdout,
        )
        self.assertIn(
            self.REFUSAL, r.stderr,
            "the run failed without the guard's own refusal in it:\n" + r.stderr,
        )
        self.assertIn(
            "not-a-number", r.stderr,
            "the refusal did not quote what it found, which is the one thing that tells an operator "
            "which file to go and look at:\n" + r.stderr,
        )


class TheFloorSeesEveryRefNotJustTheTrunk(AllocatorFixture):
    """A number that exists only on a branch nobody has pushed is taken, not free.

    THE FAILURE THIS EXISTS FOR. The cheap floor is `max over the default branch`, and it re-issues
    every number living on a ref the default branch does not carry. Those numbers are invisible to
    the sweep, so the allocator hands them out as free, and the collision surfaces later as two
    differently-named files that merged clean -- the same silent corruption as a lost race, reached
    by a different road.

    It is the term most likely to be dropped by someone tidying this up, because it is also the
    expensive one: one `git ls-tree` per ref. This case makes that a red test rather than a
    judgment call.
    """

    SEQUENCES = {"adr": ADR}
    SEEDS = {"docs/adr/0001-on-the-trunk.md": "seed\n"}

    def branch_with(self, name: str, relpath: str):
        """Commit a file on a side branch and leave the working tree back on the trunk."""
        self.run_git(self.repo, "checkout", "-q", "-b", name)
        target = self.repo / relpath
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("on a branch\n", encoding="utf-8")
        self.run_git(self.repo, "add", "-A")
        self.run_git(self.repo, "commit", "-qm", f"add {relpath}")
        self.run_git(self.repo, "checkout", "-q", "main")

    def test_without_the_branch_the_next_number_is_the_low_one(self):
        """The control. `0010` below means nothing unless this fixture would otherwise say `0002`."""
        self.assertEqual("0002", self.allocate("adr", "trunk only"))

    def test_a_number_living_only_on_an_unpushed_branch_is_not_reissued(self):
        self.branch_with("feature/unpushed", "docs/adr/0009-only-here.md")
        self.assertEqual(
            "0010", self.allocate("adr", "after the branch"),
            "the floor did not see a number that exists on a local branch the trunk does not carry. "
            "That number gets handed out a second time, and both files merge without a conflict.",
        )

    def test_the_working_tree_counts_too_even_uncommitted(self):
        """A draft is still a claim on its number, and it is on no ref at all yet."""
        draft = self.repo / "docs" / "adr" / "0004-not-committed.md"
        draft.write_text("draft\n", encoding="utf-8")
        self.assertEqual(
            "0005", self.allocate("adr", "after the draft"),
            "an uncommitted file in the sequence directory did not raise the floor.",
        )


class TheShippedConfigStillWorksUnchanged(AllocatorFixture):
    """The `adr` entry from this repository's own ccx.config.json, run verbatim.

    Generalising a seam is where a single-entry config quietly stops loading, and a test that
    restates the entry would go green against a config that no longer says that. So the block is READ
    from the shipped file rather than written down again here.
    """

    @classmethod
    def shipped_adr(cls) -> dict:
        block = json.loads(t.read(SHIPPED_CONFIG))["sequences"]
        if "adr" not in block:
            raise AssertionError(
                f"{SHIPPED_CONFIG.name} no longer configures an 'adr' sequence. If that is "
                "deliberate, repoint this case at whatever it configures instead -- do not delete "
                "it, because it is the only case that runs the file the repository actually ships."
            )
        return {"adr": block["adr"]}

    def setUp(self):
        type(self).SEQUENCES = self.shipped_adr()
        super().setUp()

    def test_the_shipped_entry_allocates_without_being_edited(self):
        self.assertEqual("0001", self.allocate("adr", "the shipped block, unedited"))

    def test_one_sequence_still_needs_no_kind(self):
        r = self.alloc("-Title", "the only ledger here")
        self.assertEqual(
            0, r.returncode,
            "with exactly one sequence configured, -Kind must stay optional. Requiring it would "
            "make every existing config an edit, which is the cost this generalisation avoids:\n"
            + r.stderr,
        )


class AConfigThatCouldCollideIsRefused(unittest.TestCase):
    """Two entries can describe one namespace, and then the per-kind claim excludes nothing.

    THE FAILURE THIS EXISTS FOR. The claim is exclusive per (kind, number) and nothing excludes
    across kinds. Two sequences that recognise the same files therefore each issue the same number,
    into differently-named files, that merge clean -- the corruption the registry exists to prevent,
    arriving through the config instead. The realistic way in is copy-paste: clone the `adr` block,
    rename it, forget to change the strings.

    The other half is the NAME, which becomes a directory under the registry. Measured before the
    check existed: a sequence named `../escape` wrote its claims to `<state-root>/escape`, outside
    the allocation registry entirely, and reported success.

    Every refusal here is paired with the accepted near-neighbour. A checker that refused two
    sequences on principle would pass all three refusal cases and make the whole feature unusable.
    """

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so alloc.ps1 cannot be executed here")
        if not shutil.which("git"):
            self.skipTest("git is not on PATH, so the fixture repository cannot be built")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-alloc-cfg-", ignore_cleanup_errors=True)
        self.addCleanup(self.tmp.cleanup)

    def attempt(self, sequences: dict, kind: str) -> subprocess.CompletedProcess:
        base = Path(self.tmp.name) / f"case{len(list(Path(self.tmp.name).iterdir()))}"
        repo = AllocatorFixture.build_repo(base, sequences, {})
        self.last_repo = repo
        return AllocatorFixture.run_alloc(self.pwsh, repo, "-Kind", kind, "-Title", "attempt")

    def test_two_sequences_with_one_filepattern_are_refused(self):
        r = self.attempt(
            {"adr": ADR, "rfc": dict(ADR)},
            "adr",
        )
        self.assertNotEqual(
            0, r.returncode,
            "two sequences declaring the same filePattern were allowed to allocate. They recognise "
            "the same files out of separate registries, so both can issue the same number:\n"
            + r.stdout,
        )
        for named in ("adr", "rfc", "filePattern"):
            self.assertIn(named, r.stderr, "the refusal does not say which entries collided")

    def test_two_sequences_reading_one_index_are_refused(self):
        indexed = {**ADR, "indexFile": "docs/INDEX.md", "indexRowPattern": r"^\| (\d+)"}
        other = {**BACKLOG, "indexFile": "docs/INDEX.md", "indexRowPattern": r"^\| (\d+)"}
        r = self.attempt({"adr": indexed, "backlog": other}, "adr")
        self.assertNotEqual(
            0, r.returncode,
            "two sequences reading the same rows out of one index were allowed to allocate:\n"
            + r.stdout,
        )

    def test_a_name_that_is_not_one_path_segment_is_refused(self):
        r = self.attempt({"adr": ADR, "../escape": BACKLOG}, "../escape")
        self.assertNotEqual(
            0, r.returncode,
            "a sequence name containing a path traversal was accepted. It becomes a directory under "
            "the registry, so its claims land somewhere the registry does not look:\n" + r.stdout,
        )
        state = self.last_repo / ".git" / "ccx-coord"
        stray = [p.name for p in state.rglob("escape*")] if state.exists() else []
        self.assertEqual(
            [], stray,
            f"claims were written outside the allocation registry: {stray}. The refusal happened "
            "after the damage, which is not a refusal.",
        )

    def test_two_distinct_sequences_are_accepted(self):
        """The control. Refusing every multi-sequence config passes all three cases above."""
        r = self.attempt({"adr": ADR, "backlog": BACKLOG}, "backlog")
        self.assertEqual(
            0, r.returncode,
            "a repository with two properly distinct sequences was refused. That is the whole "
            "feature, and the checks above are worthless if they reach this far:\n" + r.stderr,
        )
        self.assertEqual(1, len(ALLOCATED.findall(r.stdout)), r.stdout)


if __name__ == "__main__":
    unittest.main()
