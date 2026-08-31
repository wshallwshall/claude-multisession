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
     worse than none, because each assumes the other did not.
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
import subprocess
import tempfile
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

    def watch(self, *extra: str, env_overrides: dict | None = None) -> tuple[dict, int, str]:
        """Run the watcher and return (receipt, exit code, stderr).

        Always -Json. The receipt is the contract every case below reads, and parsing prose would
        make these cases fail on a wording change instead of on a behaviour change.
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
        r = subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(t.WATCH_CI_RED),
             "-RepoRoot", str(self.repo), "-Repo", REPO,
             "-Gh", str(self.gh),
             "-WaitForSpawn", "-Json", *extra],
            capture_output=True, text=True, env=env, cwd=str(self.repo), timeout=TIMEOUT_SECONDS,
        )
        self.assertTrue(
            r.stdout.strip(),
            f"the watcher emitted no receipt at all (exit {r.returncode}). It died before it could "
            f"say what it scanned:\n{r.stderr}",
        )
        return json.loads(r.stdout), r.returncode, r.stderr

    def spawns(self) -> list[str]:
        if not self.spawn_log.exists():
            return []
        return [ln for ln in self.spawn_log.read_text(encoding="utf-8").splitlines() if ln.strip()]


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
        first, _, err = self.watch()
        self.assertEqual("SPAWNED", first["red"][0]["decision"], err)
        second, code, _ = self.watch()
        self.assertEqual("ALREADY-CLAIMED", second["red"][0]["decision"])
        self.assertEqual(0, code)
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
        self.assertIn(
            str(journal), prompt,
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
