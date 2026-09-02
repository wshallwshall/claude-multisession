"""The red watcher must cost nothing while quiet, start exactly one seat per red, and never
report an all-clear it could not establish.

THE FAILURE THIS EXISTS FOR. Nothing tells a session that a required check went red. The only path
was a long-lived console session polling and then spawning a seat to attribute the failure, which
makes that console a single point of failure while it is also the only seat the operator talks to.
`scripts/cron/watch-ci-red.ps1` replaces the polling half with a script. Four properties make that
replacement safe, and each is a separate way the script can quietly stop being worth running:

  1. IT MUST NOT BE A SEAT. A resident session watching for reds costs 2,108 metered tokens per
     waiting minute on a three-minute heartbeat and 22,275 on a ten-minute sleep loop. If a quiet
     repository starts anything, the script has become the thing it replaced.
  2. IT STARTS FRESH RATHER THAN WAKING. A worker that finished its turn has exited -- 740 session
     records against 2 live sessions on the reference fleet -- so a fresh session begins with no
     memory of the last red. The per-pull-request journal is the only continuity, so a spawn that
     does not write one produces a seat that re-derives everything every time.
  3. IT MUST NOT START A SECOND SEAT ON A RED SOMEBODY HOLDS. Two seats attributing one failure is
     worse than none, because each assumes the other did not. Its mirror costs just as much: a claim
     whose seat has died must not read as somebody holding it. Claims never expire, and the claim
     names the WATCHER'S own checkout as the holder, so every liveness probe in this repository
     would call that holder live for as long as the checkout exists.
  4. AN EMPTY RESULT FROM AN UNPROVEN SOURCE IS UNKNOWN, NOT ZERO. Measured 2026-08-31:
     CLAUDE_CONFIG_DIR pointing at a directory that does not exist makes `claude agents --json`
     return an empty list and exit 0, so a mistyped root and an empty fleet are byte-identical. The
     same shape is available here three ways, and each must refuse rather than report a zero.

HOW THE BEHAVIOURAL CASES ARE DRIVEN. Against a throwaway git repository, with a stub GitHub client
and a stub spawner, so no network and no model are involved. The stub answers by call shape and is
steered entirely by environment variables, which is what lets one fixture produce a green
repository, a red one, and three different unprovable ones.

THE CLAIM IS THE REAL claim.ps1, not a stand-in. A hand-written stub would be a second copy of the
mutual exclusion under test, and the property being pinned is that this script cooperates with the
registry the repository already has.

EVERY CASE THAT ASSERTS AN ABSENCE HAS A PAIRED CASE THAT ASSERTS THE PRESENCE, on the same fixture
with one variable changed. A green "nothing was started" is equally consistent with a fixture whose
spawner was never reachable, so the pair is what makes the absence mean anything.

WHAT THIS DOES NOT PROVE. Not that the label contract is correct -- that half lives in the consuming
repository. Not that the spawned seat attributes anything correctly; the seat is a model and is out
of scope here. Not that the claim closes every race: a peer taking the key between this script's
existence check and its -Take is caught by claim.ps1's exclusive create, and that path is asserted
by planting a foreign claim rather than by racing two processes.

Run: cd tests && python -m unittest discover -s . -q
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
from pathlib import Path

import _ccxtest as t

TIMEOUT_SECONDS = 180

# A fixture repo must not inherit the operator's identity or signing config: a commit that needs a
# passphrase turns a test failure into a hang.
GIT_ID = (
    "-c", "user.email=ccx@test", "-c", "user.name=ccx test",
    "-c", "commit.gpgsign=false", "-c", "advice.detachedHead=false",
)

REPO = "example/consumer"
LABEL = "ci-red"

# The stub GitHub client. It answers by CALL SHAPE, so it breaks loudly if the script changes which
# calls it makes, rather than silently answering the wrong question. Every answer is steered by an
# environment variable, which is how one stub covers green, red, and three unprovable repositories.
GH_STUB = r"""
$joined = @($args) -join ' '
if ($joined -match '--jq \.full_name') {
    if ($env:STUB_REPO_EMPTY) { exit 0 }
    if ($env:STUB_REPO_FAIL) { [Console]::Error.WriteLine('stub: no such repository'); exit 1 }
    Write-Output $env:STUB_REPO_NAME
    exit 0
}
if ($joined -match '--jq \.name') {
    if ($env:STUB_LABEL_EMPTY) { exit 0 }
    if ($env:STUB_LABEL_FAIL) { [Console]::Error.WriteLine('stub: could not resolve to a Label'); exit 1 }
    Write-Output $env:STUB_LABEL_NAME
    exit 0
}
if ($joined -match ' --label ') {
    if ($env:STUB_RED_FAIL) { [Console]::Error.WriteLine('stub: query failed'); exit 1 }
    Write-Output (Get-Content -LiteralPath $env:STUB_RED_JSON -Raw)
    exit 0
}
if ($env:STUB_OPEN_FAIL) { [Console]::Error.WriteLine('stub: cannot list pull requests'); exit 1 }
Write-Output (Get-Content -LiteralPath $env:STUB_OPEN_JSON -Raw)
exit 0
"""

# The stub seat. It records the prompt it was handed, which is what proves a spawn happened AND
# what the spawned session would have been told to read.
SPAWNER_STUB = r"""
Add-Content -LiteralPath $env:STUB_SPAWN_LOG -Value ($args -join ' ') -Encoding utf8
# A seat that TALKS, when a case asks for one. The shipped default seat is `claude -p`, which writes
# its answer to stdout, and every other case here runs against a stub that is silent by construction
# -- so the receipt could be corrupted by a real seat and the whole file would stay green.
if ($env:STUB_SPAWN_CHATTER) {
    for ($i = 0; $i -lt 40; $i++) { [Console]::Out.WriteLine($env:STUB_SPAWN_CHATTER) }
}
"""

# The stub seat that STAYS. Every case driven by the stub above runs a seat that has already exited
# by the time the watcher returns, which is the ordinary shape and the one that used to read as
# coverage. Telling a dead seat from a live one takes both readings on the same fixture, so this one
# logs and then holds its process open until the test kills it.
LIVE_SPAWNER_STUB = r"""
Add-Content -LiteralPath $env:STUB_SPAWN_LOG -Value ($args -join ' ') -Encoding utf8
Start-Sleep -Seconds 600
"""

# The stub seat that WRITES. Every "did append" reading elsewhere in this file is produced by the
# harness appending to the journal itself, which proves the comparison and not the path a real seat
# takes. This one appends the way a briefed seat is told to, from inside the spawned process.
APPENDING_SPAWNER_STUB = r"""
Add-Content -LiteralPath $env:STUB_SPAWN_LOG -Value ($args -join ' ') -Encoding utf8
Add-Content -LiteralPath $env:STUB_SEAT_JOURNAL -Value "`nThe seat wrote this from inside the spawn." -Encoding utf8
"""


def open_json(*numbers: int) -> str:
    return json.dumps([{"number": n} for n in numbers])


def red_json(*numbers: int) -> str:
    return json.dumps([
        {
            "number": n,
            "title": f"pull request {n}",
            "url": f"https://github.com/{REPO}/pull/{n}",
            "headRefName": f"feature/{n}",
        }
        for n in numbers
    ])


class WatcherCase(unittest.TestCase):
    """A throwaway repository, a stub client, a stub seat, and the real claim registry."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so the watcher cannot be executed here")
        if not self._git_available():
            self.skipTest("git is not on PATH, so the fixture repository cannot be built")

        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-cired-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

        self.repo = self.base / "primary"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main", cwd=self.repo)

        self.gh = self.base / "gh-stub.ps1"
        self.gh.write_text(GH_STUB, encoding="utf-8")
        self.seat = self.base / "seat-stub.ps1"
        self.seat.write_text(SPAWNER_STUB, encoding="utf-8")
        self.spawn_log = self.base / "spawned.txt"

        # The label AND the spawn command come from the fixture's own ccx.config.json, which is the
        # surface a consuming repository actually configures. Passing them as flags instead would
        # leave the config path untested, and `pwsh -File` cannot carry an argument that starts with
        # a dash anyway.
        #
        # trunk is pinned rather than 'auto': the fixture has no remote, so there is no recorded
        # default branch for auto to resolve.
        (self.repo / "ccx.config.json").write_text(
            json.dumps({
                "prefix": "ccx",
                "trunk": "main",
                "worktreeLayout": "sibling",
                "ciRed": {
                    "label": LABEL,
                    "spawn": {"command": self.pwsh, "args": ["-NoProfile", "-File", str(self.seat)]},
                },
            }),
            encoding="utf-8",
        )
        (self.repo / "README.md").write_text("fixture\n", encoding="utf-8")
        self.git("add", "-A", cwd=self.repo)
        self.git("commit", "-qm", "init", cwd=self.repo)

        self.open_file = self.base / "open.json"
        self.red_file = self.base / "red.json"
        self.open_file.write_text(open_json(), encoding="utf-8")
        self.red_file.write_text(red_json(), encoding="utf-8")

    def _git_available(self) -> bool:
        try:
            subprocess.run(["git", "--version"], capture_output=True, timeout=30)
            return True
        except (OSError, subprocess.SubprocessError):
            return False

    def git(self, *args, cwd=None):
        r = subprocess.run(
            ["git", *GIT_ID, *args],
            cwd=str(cwd or self.repo), capture_output=True, text=True, timeout=TIMEOUT_SECONDS,
        )
        self.assertEqual(0, r.returncode, f"git {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
        return r.stdout

    def state_root(self) -> Path:
        return self.repo / ".git" / "ccx-coord"

    def watch(self, *extra: str, env_overrides: dict | None = None,
              wait_for_spawn: bool = True,
              script: Path | None = None) -> tuple[dict, int, str]:
        """Run the watcher and return (receipt, exit code, stderr).

        Always -Json. The receipt is the contract every case below reads, and parsing prose would
        make these cases fail on a wording change instead of on a behaviour change.

        wait_for_spawn is on by default so a spawn is observable without a sleep. The one case that
        needs a seat still running when the next tick looks turns it off, because waiting for the
        seat to exit is precisely what would destroy the state it has to observe.
        """
        env = dict(os.environ)
        # The operator's own coordination variables must not reach the fixture. CCX_CONFIG in
        # particular would point config discovery at the real repository.
        for leak in ("CCX_CONFIG", "CCX_TRUNK"):
            env.pop(leak, None)
        env.update({
            "STUB_REPO_NAME": REPO,
            "STUB_LABEL_NAME": LABEL,
            "STUB_OPEN_JSON": str(self.open_file),
            "STUB_RED_JSON": str(self.red_file),
            "STUB_SPAWN_LOG": str(self.spawn_log),
        })
        env.update(env_overrides or {})
        wait_flag = ["-WaitForSpawn"] if wait_for_spawn else []
        argv = [self.pwsh, "-NoProfile", "-File", str(script or t.WATCH_CI_RED),
                "-RepoRoot", str(self.repo), "-Repo", REPO,
                "-Gh", str(self.gh),
                *wait_flag, "-Json", *extra]
        # CAPTURE TO FILES, NOT PIPES, WHEN THE SEAT OUTLIVES THE TICK. A seat still running holds
        # the write end of an inherited pipe open after the watcher exits, and the reader waits for
        # an end-of-file that only arrives when the seat does -- a hang that looks exactly like the
        # watcher hanging. The spawn now passes -Quiet, so the seat no longer inherits these
        # handles at all; files are kept because they also survive a case that stops passing -Quiet.
        out_file = self.base / "watch-stdout.txt"
        err_file = self.base / "watch-stderr.txt"
        with out_file.open("w", encoding="utf-8") as out, err_file.open("w", encoding="utf-8") as err:
            code = subprocess.run(
                argv, stdout=out, stderr=err, env=env, cwd=str(self.repo), timeout=TIMEOUT_SECONDS,
            ).returncode
        stdout = out_file.read_text(encoding="utf-8")
        stderr = err_file.read_text(encoding="utf-8")
        self.assertTrue(
            stdout.strip(),
            f"the watcher emitted no receipt at all (exit {code}). It died before it could "
            f"say what it scanned:\n{stderr}",
        )
        self.last_stdout = stdout
        return json.loads(stdout), code, stderr

    def spawns(self) -> list[str]:
        if not self.spawn_log.exists():
            return []
        return [ln for ln in self.spawn_log.read_text(encoding="utf-8").splitlines() if ln.strip()]

    def await_spawns(self, count: int, seconds: int = 60) -> list[str]:
        """Wait until the spawn log holds `count` lines, then return them.

        Needed only where the watcher was told not to wait for the seat. The seat writes its line
        and then stays, so reading the log the instant the watcher returns is a race -- and a race
        that resolves the wrong way would fail a case about liveness for a reason that has nothing
        to do with liveness.
        """
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            lines = self.spawns()
            if len(lines) >= count:
                return lines
            time.sleep(0.2)
        raise AssertionError(
            f"the spawn log never reached {count} line(s) within {seconds}s; it holds "
            f"{len(self.spawns())}. The stub seat was never reached, so no case built on it means "
            "anything."
        )

    def dispatch(self, number: int) -> Path:
        return self.state_root() / "ci-red" / f"dispatch-pr-{number}.json"

    def kill_seat_later(self, number: int) -> None:
        """Register a cleanup that kills the seat this fixture left running.

        A stub seat that stays alive is the point of one case here, and a test that leaves it behind
        leaks a process for ten minutes per run.
        """
        def _kill():
            try:
                record = json.loads(self.dispatch(number).read_text(encoding="utf-8"))
                subprocess.run(
                    [self.pwsh, "-NoProfile", "-Command",
                     f"Stop-Process -Id {int(record['pid'])} -Force -ErrorAction SilentlyContinue"],
                    capture_output=True, timeout=TIMEOUT_SECONDS,
                )
            except (OSError, ValueError, KeyError, subprocess.SubprocessError):
                pass
        self.addCleanup(_kill)


class AQuietRepositoryStartsNothing(WatcherCase):
    """Property 1. The whole point is that a repository with nothing red costs no model at all."""

    def test_no_labelled_pull_request_starts_no_seat(self):
        self.open_file.write_text(open_json(7, 8, 9), encoding="utf-8")
        self.red_file.write_text(red_json(), encoding="utf-8")
        receipt, code, _ = self.watch()
        self.assertEqual("OK", receipt["status"])
        self.assertEqual(0, code)
        self.assertEqual(
            [], self.spawns(),
            "a repository with nothing red started a seat. The script has become the resident "
            "session it exists to replace, at 2,108 metered tokens per waiting minute.",
        )

    def test_the_same_fixture_does_start_a_seat_when_something_is_red(self):
        """The control for the case above.

        Without it, "nothing was started" is equally consistent with a stub spawner the script
        could never have reached -- a wrong path, a broken quoting rule, a fixture that never wired
        it up. This case changes exactly one file and requires the opposite result.
        """
        self.open_file.write_text(open_json(7, 8, 9), encoding="utf-8")
        self.red_file.write_text(red_json(8), encoding="utf-8")
        receipt, code, err = self.watch()
        self.assertEqual("OK", receipt["status"], err)
        self.assertEqual(0, code)
        self.assertEqual(
            1, len(self.spawns()),
            f"a red pull request did not produce exactly one seat. Receipt: {receipt['red']}",
        )
        self.assertEqual("SPAWNED", receipt["red"][0]["decision"])

    def test_a_quiet_run_still_says_what_it_examined(self):
        self.open_file.write_text(open_json(7, 8, 9), encoding="utf-8")
        receipt, _, _ = self.watch()
        scanned = receipt["scanned"]
        self.assertEqual(3, scanned["openPullRequests"])
        self.assertEqual(0, scanned["labelled"])
        self.assertEqual(REPO, scanned["repo"])
        self.assertEqual(LABEL, scanned["label"])
        self.assertTrue(
            scanned["labelSource"],
            "the receipt does not say where the label came from, so a built-in default and a "
            "configured value are indistinguishable -- and only one of them means the consuming "
            "repository agreed to the contract.",
        )


class ASecondTickDoesNotStartASecondSeat(WatcherCase):
    """Property 3. Two seats attributing one failure is worse than none."""

    def setUp(self):
        super().setUp()
        self.open_file.write_text(open_json(41, 42), encoding="utf-8")
        self.red_file.write_text(red_json(42), encoding="utf-8")

    def test_two_ticks_over_one_red_start_one_seat(self):
        """The exclusion itself, whatever the second tick decides to call the state it finds.

        The stub seat exits as soon as it has logged, so the second tick here reads a seat that is
        gone -- see ASeatThatDiedIsNotASeatThatIsWorking for what it must say about that. What this
        case pins is the invariant underneath: no second seat, on either reading.
        """
        first, _, err = self.watch()
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        second, code, _ = self.watch()
        self.assertIn(second["red"][0]["decision"], ("ALREADY-CLAIMED", "SEAT-GONE"))
        self.assertNotEqual(2, code, "a second tick over one red must never refuse the whole run")
        self.assertEqual(
            1, len(self.spawns()),
            "the second tick started a second seat on a red the first tick already claimed. Note "
            "that claim.ps1 alone cannot catch this: re-taking a key you already hold is a "
            "documented success, and every tick runs from the same worktree.",
        )

    def test_releasing_the_claim_lets_the_next_tick_start_one(self):
        """The control for the case above.

        Without it, "only one seat started" is equally consistent with a script that can only ever
        start one seat, or with a spawner that stopped working after its first call.
        """
        self.watch()
        claim = self.state_root() / "claims" / "ci-red-pr-42.json"
        self.assertTrue(
            claim.exists(),
            f"the claim file this test releases was never written. Looked for {claim}. The claim "
            "path formula in the watcher and in claim.ps1 have drifted apart.",
        )
        claim.unlink()
        second, _, _ = self.watch()
        self.assertEqual("SPAWNED", second["red"][0]["decision"])
        self.assertEqual(2, len(self.spawns()))

    def test_a_claim_held_by_another_worktree_blocks_the_spawn(self):
        claims = self.state_root() / "claims"
        claims.mkdir(parents=True, exist_ok=True)
        (claims / "ci-red-pr-42.json").write_text(
            json.dumps({
                "key": "ci-red-pr-42",
                "note": "already being attributed",
                "branch": "feature/42",
                "worktree": str(self.base / "some-peer-worktree"),
                "claimed": "2026-08-31T00:00:00.0000000+00:00",
            }),
            encoding="utf-8",
        )
        receipt, code, _ = self.watch()
        self.assertEqual("ALREADY-CLAIMED", receipt["red"][0]["decision"])
        self.assertIn("some-peer-worktree", receipt["red"][0]["detail"])
        self.assertEqual([], self.spawns())
        self.assertEqual(0, code)

    def test_a_dry_run_takes_no_claim_and_starts_nothing(self):
        receipt, code, _ = self.watch("-DryRun")
        self.assertEqual("DRY-RUN", receipt["red"][0]["decision"])
        self.assertEqual([], self.spawns())
        self.assertEqual(0, code)
        self.assertFalse((self.state_root() / "claims" / "ci-red-pr-42.json").exists())


class ASeatThatDiedIsNotASeatThatIsWorking(WatcherCase):
    """Property 3, the half a claim cannot hold on its own.

    A claim never expires and nothing releases one on a seat's behalf. The claim also names the
    WATCHER'S checkout as the holder, because that is where claim.ps1 is run from, so the repository's
    own liveness probes -- all of which read the holder's worktree -- would call that holder live for
    as long as the checkout exists. Without a separate reading, a seat that died a second after it
    started and a seat that is mid-attribution produce the same receipt line forever, and a red waits
    on nobody while every tick looks like coverage.
    """

    def setUp(self):
        super().setUp()
        self.open_file.write_text(open_json(41, 42), encoding="utf-8")
        self.red_file.write_text(red_json(42), encoding="utf-8")

    def test_a_tick_that_finds_its_seat_gone_says_so_and_fails_the_run(self):
        first, _, err = self.watch()
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        self.assertTrue(
            self.dispatch(42).exists(),
            f"no dispatch record at {self.dispatch(42)}. Without it the next tick has only the "
            "claim to read, and the claim says the watcher's own checkout holds the key.",
        )

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual(
            "SEAT-GONE", row["decision"],
            "the seat has exited and the claim is still held, so nothing is attributing this red. "
            f"The tick called it {row['decision']} instead. Receipt: {row['detail']}",
        )
        self.assertEqual("gone", row["seat"])
        self.assertEqual("INCOMPLETE", second["status"])
        self.assertEqual(
            1, code,
            "a red nobody is working exited 0, which is the all-clear this reading exists to refuse",
        )
        self.assertEqual(
            1, len(self.spawns()),
            "the tick started a replacement seat. A seat that exits without releasing may have "
            "finished its attribution, so respawning on that inference starts a session every tick "
            "for as long as the label stays on.",
        )

    def test_a_tick_that_finds_its_seat_still_running_reports_a_held_claim(self):
        """The control for the case above, on the same fixture with one variable changed.

        Without it, SEAT-GONE is equally consistent with a reading that says GONE about everything --
        a probe pointed at the wrong record, a comparison that can never match. That instrument would
        fail the run on every tick of a perfectly healthy watch, and nobody would keep running it.
        """
        self.seat.write_text(LIVE_SPAWNER_STUB, encoding="utf-8")
        self.kill_seat_later(42)

        first, _, err = self.watch(wait_for_spawn=False)
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        self.await_spawns(1)

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual(
            "ALREADY-CLAIMED", row["decision"],
            f"a seat that is still running was reported as {row['decision']}. Detail: {row['detail']}",
        )
        self.assertEqual("alive", row["seat"])
        self.assertEqual("OK", second["status"])
        self.assertEqual(0, code)
        self.assertEqual(1, len(self.spawns()))

    def test_a_claim_whose_seat_cannot_be_looked_up_is_unknown_rather_than_held(self):
        """The third reading, and the one the repository keeps having to relearn.

        A dispatch record that is missing is not evidence of a dead seat and not evidence of a live
        one. Calling it either way would be a confident answer to a question this run did not ask.
        """
        self.watch()
        self.dispatch(42).unlink()

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual("SEAT-UNKNOWN", row["decision"])
        self.assertEqual("unknown", row["seat"])
        self.assertEqual(1, code)
        self.assertTrue(
            row["detail"],
            "an UNKNOWN with no reason is one nobody can act on, which is how it becomes an "
            "all-clear by default",
        )
        self.assertEqual([], self.spawns()[1:], "an unreadable seat state started another seat")


    def test_a_start_time_that_disagrees_slightly_is_the_same_process(self):
        """The equality that turned the ubuntu leg red, pinned as a tolerance.

        `startTicks` is read through `Process.Start` and re-read through `Get-Process`. On Linux
        .NET derives StartTime from the boot instant plus the process's own ticks, and the boot
        instant is itself derived, so two reads of ONE LIVE PROCESS need not agree to the tick.
        Measured on gates (ubuntu-latest) at 37dd0de: a stub seat sleeping 600 seconds, certainly
        alive, reported SEAT-GONE with "the number was reused". Windows passed the same case, which
        is why the branch was red on one leg only.

        The disagreement is supplied rather than raced, for the reason the rest of this file
        supplies its contention: a defect that needs a particular clock derivation reports on the
        platform, not on the code. Half a second is far beyond any real derivation error and far
        inside the window, so this case fails if the comparison goes back to equality.
        """
        self.seat.write_text(LIVE_SPAWNER_STUB, encoding="utf-8")
        self.kill_seat_later(42)

        first, _, err = self.watch(wait_for_spawn=False)
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        self.await_spawns(1)

        record = json.loads(self.dispatch(42).read_text(encoding="utf-8"))
        self.assertIsNotNone(
            record.get("startTicks"),
            "no start time was recorded, so this case is not measuring the comparison at all",
        )
        record["startTicks"] = int(record["startTicks"]) + 5_000_000  # half a second in ticks
        self.dispatch(42).write_text(json.dumps(record), encoding="utf-8")

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual(
            "ALREADY-CLAIMED", row["decision"],
            "a live seat whose two start-time readings differ by half a second was called gone. "
            "That sentence invites an operator to release the claim, and the next tick then starts "
            f"a second seat on a red somebody is working. Detail: {row['detail']}",
        )
        self.assertEqual("alive", row["seat"])
        self.assertEqual(0, code)

    def test_a_start_time_that_disagrees_wildly_is_a_reused_number(self):
        """The control for the tolerance, and the property it must not cost.

        Without it, the window could widen until every pid matched and the reuse check meant
        nothing. An hour is not clock derivation error; it is a different program.
        """
        self.seat.write_text(LIVE_SPAWNER_STUB, encoding="utf-8")
        self.kill_seat_later(42)

        first, _, err = self.watch(wait_for_spawn=False)
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        self.await_spawns(1)

        record = json.loads(self.dispatch(42).read_text(encoding="utf-8"))
        record["startTicks"] = int(record["startTicks"]) - 36_000_000_000  # one hour in ticks
        self.dispatch(42).write_text(json.dumps(record), encoding="utf-8")

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual(
            "SEAT-GONE", row["decision"],
            "a process whose start time is an hour from the record is not the seat that was "
            f"started, and the tick called it {row['decision']}. Detail: {row['detail']}",
        )
        self.assertIn("the number was reused", row["detail"])
        self.assertEqual(1, code)

    def test_a_claim_this_watcher_cannot_read_asks_about_the_seat_anyway(self):
        """An unreadable CLAIM used to be an all-clear, on the same tick that an unreadable DISPATCH
        record was a refusal.

        The holder is parsed inside a try with an empty catch, so a claim file that will not parse
        left the holder path empty, which made the "is it mine" test false, which took the peer
        branch. Measured on the reviewed head: decision ALREADY-CLAIMED, `seat` empty, status OK,
        exit 0 -- and the seat behind that claim never looked at. A holder you cannot read is not a
        holder you can name.
        """
        first, _, err = self.watch()
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        claim = self.state_root() / "claims" / "ci-red-pr-42.json"
        self.assertTrue(claim.exists(), "this watcher wrote no claim, so there is nothing to corrupt")
        claim.write_text("{ this is not json", encoding="utf-8")

        second, code, _ = self.watch()
        row = second["red"][0]
        self.assertEqual(
            "SEAT-UNKNOWN", row["decision"],
            "an unreadable claim was reported as held by a peer, so the run never asked whether a "
            f"seat was running and exited clean over it. Detail: {row['detail']}",
        )
        self.assertEqual("unknown", row["seat"])
        self.assertEqual(
            1, code,
            "a red whose claim cannot even be read exited 0. That is the all-clear this whole file "
            "exists to refuse",
        )
        self.assertEqual("INCOMPLETE", second["status"])
        self.assertEqual([], self.spawns()[1:], "it started a second seat over an unreadable claim")

    def test_a_seat_that_appends_is_reported_as_having_written(self):
        """The journal baseline has to predate the seat, and under -WaitForSpawn it did not.

        `Write-Dispatch` runs after `Start-Child` returns, and with -Wait that is after the child
        EXITED -- so the recorded size already included everything the seat appended and the later
        comparison could never see it. Measured on one fixture with one variable changed: with the
        flag on, 1202 bytes recorded against a journal of 1202 and the next tick said "It never
        appended"; with it off, 1168 against 1202 and "It did append". Both seats wrote.

        This is also the only case in the file where a real spawned process does the appending. Every
        other "did append" reading is produced by the harness writing to the journal itself, which
        proves the comparison and not the path a briefed seat takes.
        """
        self.seat.write_text(APPENDING_SPAWNER_STUB, encoding="utf-8")
        journal = self.state_root() / "ci-red" / "pr-42.md"

        first, _, err = self.watch(env_overrides={"STUB_SEAT_JOURNAL": str(journal)})
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        self.assertIn(
            "The seat wrote this from inside the spawn", journal.read_text(encoding="utf-8"),
            "the stub seat did not append, so this case is measuring nothing",
        )

        second, _, _ = self.watch(env_overrides={"STUB_SEAT_JOURNAL": str(journal)})
        row = second["red"][0]
        self.assertIn(
            "did append", row["detail"],
            "the seat appended to its journal and the next tick said it never did. An operator "
            "reading that re-attributes a red somebody already answered. The baseline was taken "
            f"after the seat had written:\n{row['detail']}",
        )

    def test_the_gone_reading_hands_over_the_command_that_clears_it(self):
        self.watch()
        second, _, _ = self.watch()
        self.assertIn("claim.ps1 -Release ci-red-pr-42", second["red"][0]["detail"])

    def test_a_seat_that_died_without_writing_is_told_apart_from_one_that_wrote(self):
        """Two states with the same liveness reading and different operator actions.

        A seat that died before appending left the red unattributed. A seat that appended and then
        exited left a verdict in the journal and only failed to release its key. Reporting both as
        "gone" would send a reader to re-attribute work that is already done.
        """
        self.watch()
        silent, _, _ = self.watch()
        self.assertIn("never appended", silent["red"][0]["detail"])

        journal = self.state_root() / "ci-red" / "pr-42.md"
        with journal.open("a", encoding="utf-8") as fh:
            fh.write("\nThe check fails on main too. Not this pull request's failure.\n")

        reported, _, _ = self.watch()
        self.assertIn("did append", reported["red"][0]["detail"])
        self.assertEqual("SEAT-GONE", reported["red"][0]["decision"])


class AnUnprovenSourceRefusesInsteadOfReportingZero(WatcherCase):
    """Property 4. "I could not look" and "nothing is wrong" must never render the same."""

    def setUp(self):
        super().setUp()
        self.open_file.write_text(open_json(7), encoding="utf-8")
        self.red_file.write_text(red_json(), encoding="utf-8")

    def assert_refused(self, receipt: dict, code: int, control: str):
        self.assertEqual(
            "CANNOT-LOOK", receipt["status"],
            f"the run reported {receipt['status']} when the '{control}' control came back empty. An "
            "unprovable source has to refuse, not report a zero.",
        )
        self.assertEqual(2, code, "exit 2 is what separates a refusal from an all-clear")
        self.assertTrue(receipt["reason"], "a refusal with no reason is an UNKNOWN nobody can act on")
        named = [c for c in receipt["controls"] if c["name"] == control]
        self.assertEqual(1, len(named), f"no control named '{control}' in {receipt['controls']}")
        self.assertFalse(named[0]["proved"])
        self.assertEqual([], self.spawns())

    def test_an_unreachable_repository_refuses(self):
        receipt, code, _ = self.watch(env_overrides={"STUB_REPO_EMPTY": "1"})
        self.assert_refused(receipt, code, "repository reachable")

    def test_a_label_that_does_not_exist_refuses(self):
        """The one most likely to be mistaken for good news.

        A query for a label nobody created returns an empty list and exits 0, so a consuming
        repository that never installed the labelling half is byte-identical to one with nothing
        red. Only a control that asks for the label by name can tell them apart.
        """
        receipt, code, _ = self.watch(env_overrides={"STUB_LABEL_FAIL": "1"})
        self.assert_refused(receipt, code, "label exists on the consumer")

    def test_an_unreadable_open_list_refuses(self):
        receipt, code, _ = self.watch(env_overrides={"STUB_OPEN_FAIL": "1"})
        self.assert_refused(receipt, code, "open pull requests readable")

    def test_a_repository_that_answers_with_a_different_name_refuses(self):
        receipt, code, _ = self.watch(env_overrides={"STUB_REPO_NAME": "someone/else"})
        self.assert_refused(receipt, code, "repository reachable")

    def test_every_control_is_proved_when_the_source_is_sound(self):
        """The control for all four cases above.

        Without it, each of them passes on a script that refuses unconditionally -- which would
        also never report a false zero, and would also never be worth running.
        """
        receipt, code, err = self.watch()
        self.assertEqual("OK", receipt["status"], err)
        self.assertEqual(0, code)
        self.assertEqual(
            3, len(receipt["controls"]),
            "the run reported a different number of controls than the three the script documents",
        )
        for control in receipt["controls"]:
            self.assertTrue(control["proved"], f"{control['name']} was not proved on a sound source")
            self.assertTrue(control["expected"], f"{control['name']} declares no expected reading")
            self.assertNotEqual(
                "(empty)", control["reading"],
                f"{control['name']} passed on an empty reading, which is the failure it exists for",
            )

    def test_the_human_receipt_does_not_end_a_refusal_with_the_word_none(self):
        """The last line a skimmer reads must not answer the question the run could not answer.

        The status line already says CANNOT-LOOK. A findings line reading "none" underneath it is
        the all-clear this whole property exists to refuse, and it is the line a reader's eye lands
        on last.
        """
        env = dict(os.environ)
        for leak in ("CCX_CONFIG", "CCX_TRUNK"):
            env.pop(leak, None)
        env.update({
            "STUB_REPO_NAME": REPO, "STUB_LABEL_NAME": LABEL,
            "STUB_OPEN_JSON": str(self.open_file), "STUB_RED_JSON": str(self.red_file),
            "STUB_SPAWN_LOG": str(self.spawn_log), "STUB_LABEL_FAIL": "1",
        })
        r = subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(t.WATCH_CI_RED),
             "-RepoRoot", str(self.repo), "-Repo", REPO, "-Gh", str(self.gh)],
            capture_output=True, text=True, env=env, cwd=str(self.repo), timeout=TIMEOUT_SECONDS,
        )
        self.assertEqual(2, r.returncode)
        self.assertIn("CANNOT-LOOK", r.stdout)
        self.assertIn("NOT DETERMINED", r.stdout)
        self.assertNotIn("red    : none", r.stdout)

    def test_the_human_receipt_does_say_none_when_it_actually_looked(self):
        """The control for the case above, on the same fixture with one variable removed.

        Without it, the assertion passes on a script that never prints a findings line at all.
        """
        env = dict(os.environ)
        for leak in ("CCX_CONFIG", "CCX_TRUNK"):
            env.pop(leak, None)
        env.update({
            "STUB_REPO_NAME": REPO, "STUB_LABEL_NAME": LABEL,
            "STUB_OPEN_JSON": str(self.open_file), "STUB_RED_JSON": str(self.red_file),
            "STUB_SPAWN_LOG": str(self.spawn_log),
        })
        r = subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(t.WATCH_CI_RED),
             "-RepoRoot", str(self.repo), "-Repo", REPO, "-Gh", str(self.gh)],
            capture_output=True, text=True, env=env, cwd=str(self.repo), timeout=TIMEOUT_SECONDS,
        )
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertIn("red    : none", r.stdout)
        self.assertIn("1 open pull requests examined", r.stdout)

    def test_a_labelled_pull_request_missing_from_the_open_list_is_not_spawned_on(self):
        """The per-finding control on the label query.

        The two calls are independent, so a pull request the label query names must also appear in
        the open population. It usually means the pull request closed between the calls, which is
        why this downgrades one finding rather than failing the run.
        """
        self.open_file.write_text(open_json(7), encoding="utf-8")
        self.red_file.write_text(red_json(99), encoding="utf-8")
        receipt, code, _ = self.watch()
        self.assertEqual("NOT-OPEN", receipt["red"][0]["decision"])
        self.assertEqual([], self.spawns())
        self.assertEqual(0, code)


class TheSpawnedSeatIsGivenAJournalRatherThanAMemory(WatcherCase):
    """Property 2. A fresh session remembers nothing, so the journal is the only continuity."""

    def setUp(self):
        super().setUp()
        self.open_file.write_text(open_json(42), encoding="utf-8")
        self.red_file.write_text(red_json(42), encoding="utf-8")

    def test_the_prompt_names_a_journal_that_exists(self):
        receipt, _, err = self.watch()
        self.assertEqual("SPAWNED", receipt["red"][0]["decision"], err)
        prompt = self.spawns()[0]
        journal = self.state_root() / "ci-red" / "pr-42.md"
        self.assertTrue(journal.exists(), f"no journal at {journal}")

        # RESOLVE BOTH SIDES RATHER THAN COMPARING THE STRINGS. On the Windows CI runner, Python's
        # temp directory comes back in the 8.3 short form (`RUNNER~1`) while PowerShell hands back
        # the long one (`runneradmin`), so a substring test fails on two correct spellings of one
        # path. Resolving also makes this a stronger assertion than the one it replaces: the prompt
        # must name THE journal file, not merely contain a string that looks like its path.
        named = re.search(r"Read '([^']+)'", prompt)
        self.assertIsNotNone(
            named,
            "the prompt no longer quotes a path after the word Read, so this case can no longer "
            f"find the journal it is supposed to check. Prompt was: {prompt}",
        )
        self.assertEqual(
            journal.resolve(), Path(named.group(1)).resolve(),
            "the seat was started without being told where its journal is. It begins with no "
            "memory of the last red, so a prompt that does not name the journal produces a session "
            "that re-derives everything and records nothing.",
        )

    def test_the_journal_carries_the_four_kinds_of_red(self):
        self.watch()
        text = (self.state_root() / "ci-red" / "pr-42.md").read_text(encoding="utf-8")
        self.assertIn("42", text)
        self.assertIn("feature/42", text)
        for kind in ("pull request", "trunk", "flake", "merge queue"):
            self.assertIn(
                kind, text,
                f"the briefing does not name '{kind}'. Sending all four kinds of red back to a "
                "builder is the failure the attributing seat exists to prevent.",
            )
        self.assertIn("claim.ps1 -Release ci-red-pr-42", text)

    def test_a_second_red_on_the_same_pull_request_appends_rather_than_replaces(self):
        self.watch()
        (self.state_root() / "claims" / "ci-red-pr-42.json").unlink()
        self.watch()
        text = (self.state_root() / "ci-red" / "pr-42.md").read_text(encoding="utf-8")
        self.assertEqual(
            2, text.count("## Red seen"),
            "the second spawn overwrote the first entry. The journal is the only thing that "
            "survives a session, so replacing it discards the record the next seat is told to read.",
        )



class TheReceiptSurvivesTheThingsThatUsedToEatIt(WatcherCase):
    """Four ways the run reported something other than what happened.

    Every case here failed against the reviewed head. They share one shape: the receipt is the whole
    interface -- an operator schedules this and reads an exit code, a consumer parses -Json -- and in
    each case that interface said "fine" or said nothing at all while something real went unhandled.
    """

    def lock_file(self) -> Path:
        """Where Enter-CcxLock puts the pass mutex, by the same formula lock.ps1 uses."""
        return self.state_root() / "locks" / "ci-red-watch.lock"

    def test_a_talking_seat_does_not_land_inside_the_json_receipt(self):
        """The spawn was the one Start-Child call that ignored Start-Child's own rule.

        Its parameter help says -Quiet is "Required for anything chatty, or -Json emits a receipt
        with another script's console noise in the middle of it." The documented default seat is
        `claude -p`, which writes its answer to stdout. Measured against the reviewed head with a
        stub that prints: 362,318 bytes of the child's output ahead of the receipt, and the parse
        failing at line 1 column 1.

        The parse is the assertion. `watch()` calls json.loads on stdout, so this case cannot pass
        against a run whose receipt has a seat's answer in the middle of it.
        """
        noise = "I am a model session and this is my answer."
        self.open_file.write_text(open_json(7), encoding="utf-8")
        self.red_file.write_text(red_json(7), encoding="utf-8")

        receipt, code, _ = self.watch(env_overrides={"STUB_SPAWN_CHATTER": noise})

        self.assertEqual(0, code)
        self.assertEqual("SPAWNED", receipt["red"][0]["decision"])
        self.assertEqual(1, len(self.spawns()), "the seat did not actually run, so it printed nothing")
        self.assertNotIn(
            noise, self.last_stdout,
            "the seat's own output reached the watcher's stdout. A consumer parsing -Json gets the "
            "seat's answer wrapped around the receipt:\n" + self.last_stdout[:400],
        )

    def test_a_contended_lock_still_produces_a_receipt(self):
        """Exit 1 with an empty stdout, for a run that never looked at anything.

        Enter-CcxLock throws on timeout and it threw from OUTSIDE the receipt path, so the run
        produced exit 1 and stdout ''. The header defines exit 1 as "looked successfully, and at
        least one red could not be handed to a seat" -- so an operator running this from schtasks
        read a successful look, and a consumer parsing -Json read nothing at all. That is the
        absent-versus-empty conflation the three controls refuse, one layer above them.

        The lock's only other coverage is a grep for the string `Enter-CcxLock -Name 'ci-red-watch'`
        in the source, which is present and was present while this was broken.
        """
        self.open_file.write_text(open_json(7), encoding="utf-8")
        self.red_file.write_text(red_json(7), encoding="utf-8")
        lock = self.lock_file()
        lock.parent.mkdir(parents=True, exist_ok=True)
        lock.write_text('{"held":"by a sibling tick"}', encoding="utf-8")

        receipt, code, _ = self.watch("-LockTimeoutSeconds", "2")

        self.assertEqual(
            2, code,
            "a contended lock did not use the refusal code. Exit 1 here reads as a successful look:"
            "\n" + self.last_stdout,
        )
        self.assertEqual("CANNOT-LOOK", receipt["status"])
        self.assertIn(
            "holds the pass lock", receipt["reason"],
            "the receipt does not say a sibling tick held the lock:\n" + str(receipt.get("reason")),
        )
        self.assertEqual([], self.spawns(), "it reported a refusal and started a seat anyway")

    def test_a_truncated_open_list_does_not_let_a_red_read_as_closed(self):
        """`truncated` was computed, commented on, printed -- and never acted on.

        The per-finding check treats "absent from the open list" as closed. When the open list filled
        -Limit that inference does not hold: the pull request may simply sit past the cap. Measured
        against the reviewed head with -Limit 2 and a genuinely open labelled #99: status OK, exit 0,
        no seat, and a detail naming two causes that were both wrong -- while the same receipt
        declared `truncated: true` two fields earlier.
        """
        self.open_file.write_text(open_json(1, 2), encoding="utf-8")
        self.red_file.write_text(red_json(99), encoding="utf-8")

        receipt, code, _ = self.watch("-Limit", "2")

        self.assertTrue(
            receipt["scanned"]["truncated"],
            "the fixture did not fill the limit, so this case is not testing truncation at all",
        )
        self.assertEqual(
            "NOT-OPEN-UNVERIFIABLE", receipt["red"][0]["decision"],
            "a red absent from a CAPPED open list was still recorded as closed",
        )
        self.assertEqual(
            1, code,
            "the run reported success over a red it could neither confirm closed nor hand to a "
            "seat:\n" + self.last_stdout,
        )
        self.assertEqual("INCOMPLETE", receipt["status"])
        self.assertEqual([], self.spawns(), "it started a seat on a reading it could not make")

    def test_the_same_red_is_ordinary_when_the_list_is_not_truncated(self):
        """The control for the case above. Without it, a watcher that refused every NOT-OPEN would
        pass, and the downgrade this file is careful about would be gone."""
        self.open_file.write_text(open_json(1, 2), encoding="utf-8")
        self.red_file.write_text(red_json(99), encoding="utf-8")

        receipt, code, _ = self.watch("-Limit", "50")

        self.assertFalse(receipt["scanned"]["truncated"])
        self.assertEqual("NOT-OPEN", receipt["red"][0]["decision"])
        self.assertEqual(0, code)


class AClaimThatCannotBeSeenIsNotAFailureToLook(WatcherCase):
    """Property 4, on the one path that spends the wrong word for it.

    On the drift path the look SUCCEEDED -- the reds were found, named and counted. What failed is
    the claim registry. The reviewed head set CANNOT-LOOK and exit 2 there, which the header reserves
    for "could not look", and because that branch is tested first at the end of the file it also
    masked any genuine INCOMPLETE in the same pass.
    """

    def watcher_whose_claim_script_writes_nothing(self) -> Path:
        """A copy of the scripts tree whose claim.ps1 reports success and creates no file.

        That is the drift the real check exists for: claim.ps1 exits 0 and the file this script
        predicted is not where it looked. Stubbing it is the only way to reach the branch, because
        the two path formulas currently agree.
        """
        tree = Path(self.tmp.name) / "drifted"
        shutil.copytree(t.WATCH_CI_RED.parent.parent, tree / "scripts")
        (tree / "scripts" / "coord" / "claim.ps1").write_text(
            "# Stub: reports the claim taken, writes nothing.\nexit 0\n", encoding="utf-8",
        )
        return tree / "scripts" / "cron" / t.WATCH_CI_RED.name

    def test_a_claim_that_cannot_be_confirmed_is_incomplete_not_cannot_look(self):
        self.open_file.write_text(open_json(7), encoding="utf-8")
        self.red_file.write_text(red_json(7), encoding="utf-8")

        receipt, code, _ = self.watch(script=self.watcher_whose_claim_script_writes_nothing())

        self.assertEqual(
            "CLAIM-UNVERIFIABLE", receipt["red"][0]["decision"],
            "the stub did not reach the drift branch, so this case measured nothing:\n"
            + self.last_stdout,
        )
        self.assertEqual(
            1, code,
            "a drifted claim path still spends exit 2, the code reserved for a failed LOOK. The "
            "look succeeded here -- the red was found and named:\n" + self.last_stdout,
        )
        self.assertEqual("INCOMPLETE", receipt["status"])
        self.assertIn(
            "drifted", receipt["reason"],
            "the top-level reason does not name the drift, so the one failure here that means a "
            "source defect reads like a busy peer:\n" + str(receipt.get("reason")),
        )
        self.assertEqual([], self.spawns(), "it spawned on a claim it could not see")


class TheSourceSaysWhatItStartsAndWhereAClaimLives(unittest.TestCase):
    """Static scans, so this file still measures something where pwsh or git are missing."""

    def setUp(self):
        self.source = t.read(t.WATCH_CI_RED)
        self.code = t.ps_source(t.WATCH_CI_RED)

    def test_the_only_model_binary_named_in_the_code_is_the_configurable_default(self):
        """Property 1, read off the source rather than the behaviour.

        The behavioural case proves a quiet repository starts nothing today. This proves the script
        has no second, unconditional path to a model -- which is what a "just check with the model
        whether this is worth spawning for" convenience would add, and what would turn the poll back
        into a metered cost.
        """
        hits = re.findall(r"'claude'|\"claude\"", self.code)
        self.assertEqual(
            1, len(hits),
            f"expected exactly one literal 'claude' in the executable source (the fallback default "
            f"for the spawn command), found {len(hits)}. Every other way of naming a model is a "
            "path that can run without a red.",
        )
        self.assertIn(
            "Resolve-Setting $SpawnCommand $ciRed.spawn.command 'claude'", self.code,
            "the single 'claude' literal is no longer the spawn-command fallback, so this scan is "
            "now measuring something else. Re-point it.",
        )

    def test_the_spawn_never_resumes_a_session(self):
        """Property 2.

        A worker that finished its turn has exited, so there is nothing to resume; a flag that tried
        would either fail or reattach to a transcript whose work is done. Fresh is the design.
        """
        for flag in ("--resume", "--continue"):
            self.assertNotIn(
                flag, self.code,
                f"the watcher passes {flag}. It must start a FRESH session: the branch and worktree "
                "survive, so a new session continues the work, and 740 session records against 2 "
                "live sessions is what there is to resume.",
            )

    def test_the_claim_path_matches_the_registry_it_reads(self):
        """Property 3.

        The watcher predicts where claim.ps1 keeps a key so it can test for one before taking it.
        That prediction repeats a formula claim.ps1 owns, and a formula in two places drifts.
        """
        claim = t.ps_source(t.CLAIM_SCRIPT)
        for name in ("Join-Path (Get-CcxStateRoot", "'claims'", "ConvertTo-CcxSafeName"):
            self.assertIn(name, claim, f"claim.ps1 no longer contains {name}; re-derive this scan")
        self.assertIn("Join-Path $stateRoot 'claims'", self.code)
        self.assertIn("ConvertTo-CcxSafeName", self.code)
        self.assertIn(
            "CLAIM-UNVERIFIABLE", self.code,
            "the runtime check that the predicted claim file actually appeared is gone. Without it "
            "a drifted path formula spawns a seat on every tick forever, because the existence "
            "check would never see a claim either.",
        )

    def test_the_dispatch_path_is_written_in_exactly_one_place(self):
        """One literal for the dispatch filename, so a second copy cannot drift from the first.

        WHAT THIS DOES NOT CATCH, stated because an earlier docstring claimed it. A reader that used
        a DIFFERENT literal would leave this count at one and pass. Planted: the reader returning
        `seatrecord-$Number.json` while the writer kept `dispatch-pr-$Number.json` -- this case
        passed, and five behavioural cases in this file went red. Those cases own that property.
        What this owns is the cheaper failure: a second copy of the SAME literal, which reads as
        correct until one of them is edited."""
        hits = re.findall(r"dispatch-pr-", self.code)
        self.assertEqual(
            1, len(hits),
            f"expected the dispatch filename to be built in one function, found {len(hits)} "
            "occurrences in the executable source.",
        )
        for name in ("Get-DispatchFile", "Write-Dispatch", "Get-SeatState"):
            self.assertIn(name, self.code, f"{name} is gone, so this scan measures nothing")

    def test_no_liveness_reading_releases_or_respawns_on_its_own(self):
        """A seat that exits without releasing may have finished its attribution.

        Releasing the claim on that inference frees the key for a second seat to re-attribute work
        already done; respawning on it starts a session on every tick for as long as the label stays
        on. Both are the duplicate this registry exists to prevent, reached by following the tool's
        own reading. The one release the script may make is the one that follows a spawn that threw.
        """
        releases = re.findall(r"'-Release'", self.code)
        self.assertEqual(
            1, len(releases),
            f"expected exactly one claim release in the executable source -- the spawn-failure path "
            f"-- and found {len(releases)}.",
        )
        self.assertIn("SPAWN-FAILED", self.code, "the one permitted release is no longer that path")

    def test_a_dead_seat_and_a_live_one_are_different_words(self):
        for verdict in ("SEAT-GONE", "SEAT-UNKNOWN", "ALREADY-CLAIMED"):
            self.assertIn(
                verdict, self.code,
                f"{verdict} is gone from the receipt vocabulary. A held claim, a dead seat and an "
                "unreadable one rendering as one word is the failure this reading exists for.",
            )

    def test_the_pass_holds_the_lock_that_claim_alone_cannot_supply(self):
        self.assertIn("Enter-CcxLock -Name 'ci-red-watch'", self.code)
        self.assertIn("Exit-CcxLock", self.code)

    def test_the_label_is_read_from_configuration(self):
        self.assertIn("$ciRed.label", self.code)
        self.assertIn("'ci-red'", self.code)

    def test_refusal_and_all_clear_use_different_exit_codes(self):
        self.assertIn("$EXIT_REFUSED = 2", self.code)
        self.assertIn("$EXIT_OK = 0", self.code)
        self.assertIn("CANNOT-LOOK", self.code)

    def test_the_help_does_not_call_this_a_push(self):
        """GitHub still cannot reach into a session.

        The label makes the poll cheap enough to run often, which is the achievable version. Calling
        it a push would promise a delivery guarantee nothing here has, and the next reader would
        stop running the cron.
        """
        self.assertIn("NOT A PUSH", self.source.upper())


class TheScanCanActuallyBite(unittest.TestCase):
    """Every static scan above asserts a presence or an absence in one file.

    A scan pointed at the wrong file, or written with a pattern that matches nothing anywhere, is
    green for the same reason a clean file is. These cases plant the thing each scan looks for and
    require it to be found, and plant a violation and require it to be seen.
    """

    def test_the_model_binary_scan_counts_a_planted_second_literal(self):
        planted = "$x = 'claude'\n$y = 'claude'\n"
        self.assertEqual(2, len(re.findall(r"'claude'|\"claude\"", planted)))

    def test_the_release_scan_counts_a_planted_second_release(self):
        planted = "@('-File', $c, '-Release', $k)\n@('-File', $c, '-Release', $other)\n"
        self.assertEqual(2, len(re.findall(r"'-Release'", planted)))

    def test_the_release_scan_ignores_a_release_named_in_a_briefing(self):
        """The scan counts the ARGUMENT, not the word.

        The briefing and the gone reading both print `claim.ps1 -Release <key>` for a human to type.
        A scan that counted those would fail on a script that releases nothing.
        """
        planted = "the briefing says: claim.ps1 -Release $Key\n"
        self.assertEqual(0, len(re.findall(r"'-Release'", planted)))

    def test_the_resume_scan_sees_a_planted_flag(self):
        self.assertIn("--resume", "Start-Child -ArgumentList @('--resume', $id)")

    def test_the_comment_stripper_hides_a_flag_that_is_only_discussed(self):
        """The scans above read ps_source, not the raw file, and that is load-bearing.

        The help block explains why the watcher does not resume. Scanning the raw source would find
        that sentence and fail on a script that behaves correctly.
        """
        stripped = t.strip_ps_comments("# we never pass --resume here\n$a = 1\n")
        self.assertNotIn("--resume", stripped)
        self.assertIn("$a = 1", stripped)

    def test_the_watcher_file_the_scans_read_is_not_empty(self):
        source = t.read(t.WATCH_CI_RED)
        self.assertGreater(
            len(source), 2000,
            "the scans above all read this file. If it is missing or truncated, every 'assertNotIn' "
            "case passes for the wrong reason.",
        )


if __name__ == "__main__":
    unittest.main()
