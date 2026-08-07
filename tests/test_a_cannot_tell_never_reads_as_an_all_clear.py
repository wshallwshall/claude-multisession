"""Three coordination surfaces whose "I could not tell" used to render as a clean answer.

THE FAILURE THESE EXIST FOR. This repository's central claim is that in a multi-session system, every
failure mode is byte-identical to success: the collision that did not happen and the check that never
ran produce the same empty output, and a reader cannot tell them apart. Three surfaces were exactly
that, all verified in source before these cases were written:

  1. `overlap.ps1 -File <path>` (no -Json) printed NOTHING and exited 0 when nobody else was in the
     file. The -Json branch one line above had already been fixed for this; the human branch had not.
     This is the command the docs tell you to run BEFORE starting a chunk of work, so its silence was
     the most consequential output it had.
  2. `presence.ps1 -Json` outside a git repository wrote `[]` and exited 0 with no receipt at all --
     the same two bytes it writes for "the fence ran across every config root and nobody is live".
     Every other unavailable path in that file writes a receipt to stderr. This one did not, and it is
     the roster other tools gate on.
  3. `remove.ps1 -DeleteBranch` warned, on ANY non-zero exit from `git branch -d`, that the branch
     "is not merged into its upstream, so it holds commits no other ref has" -- a cause it had not
     established. `branch -d` also refuses when the branch does not exist under that name. And it
     asked git to delete `-Name`, the worktree DIRECTORY component, which for the documented
     `new.ps1 -Name my-task -Branch feature/my-task` invocation is not a branch name at all.

WHAT THESE CASES PROVE, AND HOW. They RUN the real scripts against throwaway git repositories rather
than reading their source. A source scan would pin the sentences; only execution pins that the
sentence is reached, that the exit path taken is the one intended, and -- for case 3 -- that a branch
which used to survive a "full cleanup" now actually goes.

EVERY CASE HAS A NEGATIVE CONTROL, because a script that says "all clear" unconditionally passes an
all-clear test perfectly. The controls are the halves that would go red if a fix degenerated into
printing a reassuring line no matter what was found.

Run: cd tests && python -m unittest discover -s . -q
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import _ccxtest as t

TIMEOUT_SECONDS = 120

# Identity and signing supplied per-invocation. A test that depends on the machine's global git config
# passes on the box it was written on and fails on a CI runner with no user.email, which is a failure
# about the harness rather than about the thing under test.
GIT_ID = (
    "-c", "user.email=ccx@test",
    "-c", "user.name=ccx test",
    "-c", "commit.gpgsign=false",
    "-c", "advice.detachedHead=false",
)

FIXTURE_CONFIG = '{ "prefix": "ccx", "trunk": "main", "worktreeLayout": "sibling" }'


def git(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    r = subprocess.run(
        ["git", *GIT_ID, *args],
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        timeout=TIMEOUT_SECONDS,
    )
    if r.returncode != 0:
        raise AssertionError(f"fixture setup failed: git {' '.join(args)}\n{r.stdout}\n{r.stderr}")
    return r


def branches(repo: Path) -> set[str]:
    out = git("branch", "--format=%(refname:short)", cwd=repo).stdout
    return {line.strip() for line in out.splitlines() if line.strip()}


class ScriptCase(unittest.TestCase):
    """A throwaway repository, and a way to run one of the scripts against it."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so these scripts cannot be executed here")
        if not shutil.which("git"):
            self.skipTest("git is not on PATH, so the fixture repository cannot be built")
        # ignore_cleanup_errors: git leaves read-only pack files behind on Windows, and a teardown
        # failure there would report as a red test about something that already passed.
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-allclear-", ignore_cleanup_errors=True)
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def outside_any_repo(self) -> Path:
        """A directory that is genuinely not inside a git repository.

        Skips rather than fails when the machine's TMP is itself inside one: that is a property of the
        host, and a red test about it would be a test of the harness. Verified rather than assumed --
        if this probe were wrong, the not-a-repo cases would silently measure something else entirely.
        """
        d = self.base / "outside"
        d.mkdir(exist_ok=True)
        probe = subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            cwd=str(d), capture_output=True, text=True, timeout=TIMEOUT_SECONDS,
        )
        if probe.returncode == 0:
            self.skipTest(f"the temp directory is inside a git repository ({probe.stdout.strip()})")
        return d

    def new_repo(self, name: str = "primary") -> Path:
        repo = self.base / name
        repo.mkdir(parents=True)
        git("init", "-q", "-b", "main", cwd=repo)
        (repo / "ccx.config.json").write_text(FIXTURE_CONFIG, encoding="utf-8")
        (repo / "a.txt").write_text("original\n", encoding="utf-8")
        git("add", "-A", cwd=repo)
        git("commit", "-qm", "init", cwd=repo)
        return repo

    def run_script(self, script: Path, *args: str, cwd: Path) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        # The developing machine's own settings must not reach the fixture. CCX_CONFIG would point
        # these scripts at THIS repository's config, and CCX_TRUNK would override the fixture's trunk
        # -- either one turns the case into a measurement of the developer's environment.
        for leak in ("CCX_CONFIG", "CCX_TRUNK"):
            env.pop(leak, None)
        return subprocess.run(
            [self.pwsh, "-NoProfile", "-File", str(script), *args],
            capture_output=True,
            text=True,
            env=env,
            cwd=str(cwd),
            timeout=TIMEOUT_SECONDS,
        )


class OverlapStatesItsAllClear(ScriptCase):
    """`overlap.ps1 -File <path>` on the human path."""

    def setUp(self):
        super().setUp()
        self.repo = self.new_repo()
        # An empty directory standing in for the session registry and the task-list root, so no real
        # session on this machine can appear in the fixture's answer.
        self.roots = self.base / "roots"
        self.roots.mkdir()

    def overlap(self, *extra: str) -> subprocess.CompletedProcess:
        # -Refresh on every call: the cache lives in the fixture's own git dir, so two calls in one
        # case would otherwise have the second read the first one's answer.
        return self.run_script(
            t.OVERLAP,
            "-Repo", str(self.repo),
            "-Trunk", "main",
            "-ConfigRoot", str(self.roots),
            "-TasksDir", str(self.roots),
            "-Refresh",
            *extra,
            cwd=self.repo,
        )

    def add_peer_editing(self, filename: str) -> Path:
        """A second worktree with an uncommitted change to `filename`."""
        peer = self.base / "peer"
        git("worktree", "add", "-q", str(peer), "-b", "peer", cwd=self.repo)
        (peer / filename).write_text("changed by somebody else\n", encoding="utf-8")
        return peer

    def test_a_file_nobody_else_is_changing_produces_a_stated_all_clear(self):
        r = self.overlap("-File", "a.txt")
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertTrue(
            r.stdout.strip(),
            "overlap.ps1 printed NOTHING for a file nobody else is changing. That is the whole bug: "
            "silence is what this script also produces when it dies before answering, and the human "
            "who ran it before starting work reads both as a green light.",
        )
        self.assertIn(
            "a.txt",
            r.stdout,
            "the all-clear must name the file it is clearing. A bare 'nothing found' does not tell "
            "the reader which question was answered.",
        )

    def test_the_all_clear_says_what_it_was_computed_from(self):
        """Evidence, not just a verdict -- an all-clear over zero worktrees is a weak one."""
        r = self.overlap("-File", "a.txt")
        self.assertRegex(
            r.stdout,
            r"\d+ peer worktree",
            "the all-clear does not say how many peer worktrees it examined. A reader cannot weigh a "
            "verdict whose evidence is not stated, and 'nobody is here' computed over nothing is the "
            "failure this line exists to expose.",
        )

    def test_a_file_somebody_else_is_changing_is_still_reported(self):
        """THE NEGATIVE CONTROL. A script that always prints an all-clear would pass the case above."""
        self.add_peer_editing("a.txt")
        r = self.overlap("-File", "a.txt")
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertIn(
            "peer",
            r.stdout,
            "a peer worktree has an uncommitted change to this exact file and overlap.ps1 did not "
            "name it. The all-clear is now unconditional, which is worse than the silence it replaced.",
        )
        self.assertNotIn(
            "no other worktree is changing it",
            r.stdout,
            "overlap.ps1 printed an all-clear for a file another worktree is actively changing.",
        )

    def test_an_empty_map_served_from_the_cache_does_not_invent_a_worktree(self):
        """The cache round-trip used to FABRICATE a peer, which is worse than omitting one.

        A walk with zero rows is AutomationNull, which `@()` unrolls to nothing -- but it serialises
        to the cache as `"rows": null`, and `@($null)` is a one-element array holding $null. So the
        zero-rows all-clear never fired and the render loop printed a worktree with a blank name, a
        blank branch, "dormant", and "1 changed file(s)" -- that last because `@($null).Count` is 1
        there too.

        Note the shape: the FRESH walk was right and the very next run inside the 60-second cache
        window was wrong, same repo, same state. A bug that only appears on the second run reads as
        flakiness rather than as a defect, which is why it survived.
        """
        fresh = self.overlap()
        self.assertIn("No other worktree has changes.", fresh.stdout, fresh.stderr)

        # NO -Refresh: this run must be served from the cache the run above just wrote. If it were
        # not, this case would pass without ever exercising the round-trip that carries the bug.
        cached = self.run_script(
            t.OVERLAP,
            "-Repo", str(self.repo), "-Trunk", "main",
            "-ConfigRoot", str(self.roots), "-TasksDir", str(self.roots),
            cwd=self.repo,
        )
        self.assertEqual(0, cached.returncode, cached.stderr)
        self.assertNotIn(
            "changed file(s)",
            cached.stdout,
            "a cached empty map rendered a PHANTOM WORKTREE -- blank name, blank branch, and a "
            "changed-file count invented out of $null. This does not fail to report a peer, it "
            "invents one, and it disagrees with the fresh walk seconds earlier.",
        )
        self.assertIn(
            "No other worktree has changes.",
            cached.stdout,
            "the cached run and the fresh run must give the SAME answer about the same repo.",
        )

    def test_the_json_contract_is_unchanged(self):
        """The gate consumes this. An empty answer is `[]` and a hit is a one-row array, as before."""
        clear = self.overlap("-File", "a.txt", "-Json")
        self.assertEqual("[]", clear.stdout.strip(), clear.stderr)

        self.add_peer_editing("a.txt")
        hit = self.overlap("-File", "a.txt", "-Json")
        rows = json.loads(hit.stdout)
        self.assertEqual(1, len(rows), hit.stdout)
        self.assertTrue(
            rows[0]["MatchedDirty"],
            "an uncommitted peer edit must set MatchedDirty -- the gate reads that field to tell "
            "'somebody is typing in this file' from 'a finished branch authored it once'.",
        )


class OverlapSignalsThatItCouldNotLook(ScriptCase):
    """No resolvable git repository is not an answer, and the EXIT CODE is how that gets said.

    A stderr receipt alone would not have been a fix here. `collision_gate.ps1` runs overlap with
    stderr discarded (`2>$null`) and treats `[]` as "resolved, and nobody else is touching it", so a
    receipt is invisible to the one consumer that acts on the verdict. The exit code is the only
    channel that reaches it -- which is why the last two cases drive the real gate rather than
    asserting on overlap's output and calling that proof.
    """

    def test_outside_a_repository_it_exits_non_zero_with_a_receipt(self):
        outside = self.outside_any_repo()
        r = self.run_script(t.OVERLAP, "-File", "a.txt", "-Json", cwd=outside)
        self.assertNotEqual(
            0,
            r.returncode,
            "overlap exited 0 having resolved no repository. Exit 0 means 'the question was "
            "answered', and nothing was examined -- no worktree was walked, no git dir was found.",
        )
        self.assertEqual(
            "[]",
            r.stdout.strip(),
            "stdout must stay parseable for consumers that only read stdout; the signal is the exit "
            "code and the receipt, not a change of shape.",
        )
        self.assertIn("NOT", r.stderr, "the receipt must say what the empty result does not mean")

    def test_inside_a_repository_a_genuine_all_clear_still_exits_zero(self):
        """THE NEGATIVE CONTROL. A script that always exits non-zero would pass the case above.

        This is the distinction the whole change rests on: `[]` after a real walk is an ANSWER and
        must stay exit 0, or the gate reports "could not check" on every ordinary edit and the notice
        becomes noise people learn to ignore.
        """
        repo = self.new_repo()
        roots = self.base / "roots"
        roots.mkdir(exist_ok=True)
        r = self.run_script(
            t.OVERLAP,
            "-Repo", str(repo), "-Trunk", "main",
            "-ConfigRoot", str(roots), "-TasksDir", str(roots),
            "-File", "a.txt", "-Json", "-Refresh",
            cwd=repo,
        )
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual("[]", r.stdout.strip(), r.stderr)

    def test_the_gate_reports_it_could_not_check_rather_than_staying_silent(self):
        """End-to-end, through the consumer, with stderr discarded exactly as in production."""
        outside = self.outside_any_repo()
        r = self.run_script(
            t.COLLISION_GATE,
            "-PathOverride", str(outside / "a.txt"),
            "-StateDir", str(self.base / "gate-state"),
            cwd=outside,
        )
        self.assertEqual(0, r.returncode, "a hook must exit 0 and put its decision in the JSON")
        self.assertTrue(
            r.stdout.strip(),
            "the gate said NOTHING for an edit it could not check, because overlap handed it `[]` "
            "from a run that resolved no repository. Silence from this gate is read as an all-clear.",
        )
        context = json.loads(r.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("could NOT check", context)
        self.assertIn(
            "UNKNOWN",
            context,
            "the notice has to name the wrong conclusion, not merely report a fault.",
        )

    def test_the_gate_stays_silent_when_the_answer_is_a_real_all_clear(self):
        """THE NEGATIVE CONTROL for the case above. A gate that always warns is uninstalled."""
        repo = self.new_repo()
        r = self.run_script(
            t.COLLISION_GATE,
            "-PathOverride", str(repo / "a.txt"),
            "-StateDir", str(self.base / "gate-state-clear"),
            cwd=repo,
        )
        self.assertEqual(0, r.returncode)
        self.assertEqual(
            "",
            r.stdout.strip(),
            "the gate emitted a notice for an edit it successfully checked and found clear.",
        )


class PresenceEmptyListCarriesAReceipt(ScriptCase):
    """`presence.ps1 -Json` -- stdout stays parseable, stderr says whether anything was measured."""

    UNAVAILABLE = "roster UNAVAILABLE"

    def setUp(self):
        super().setUp()
        self.roots = self.base / "roots"
        (self.roots / "sessions").mkdir(parents=True)
        # Shared with the overlap not-a-repo cases: two copies of "is this really outside a repo"
        # would drift, and the copy that drifts is the one whose cases quietly stop measuring.
        self.outside = self.outside_any_repo()

    def write_record(self, name: str, cwd: Path):
        """A parseable session record. Its cwd is deliberately in no worktree of the fixture repo.

        That is what makes the roster AVAILABLE while still listing nobody: records were read and
        placed, and none of them is in this repo. Exactly the state that must NOT carry a receipt.
        """
        (self.roots / "sessions" / f"{name}.json").write_text(
            json.dumps({"sessionId": "fixture-" + name, "pid": 4, "cwd": str(cwd)}),
            encoding="utf-8",
        )

    def test_outside_a_repository_the_empty_list_carries_a_receipt(self):
        r = self.run_script(t.PRESENCE, "-Json", "-ConfigRoot", str(self.roots), cwd=self.outside)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual(
            "[]",
            r.stdout.strip(),
            "stdout must stay a pure JSON array -- the receipt is additive and must not break a "
            "consumer that parses this.",
        )
        self.assertIn(
            self.UNAVAILABLE,
            r.stderr,
            "presence.ps1 emitted `[]` outside a git repository with NOTHING on stderr. Those two "
            "bytes are what it also emits for 'the fence ran and nobody is live', so a consumer -- "
            "and this is the roster other tools gate on -- reads a green light off a measurement "
            "that never happened.",
        )
        self.assertIn(
            "NOT",
            r.stderr,
            "the receipt has to say what the empty list does not mean. Naming the fault without "
            "naming the wrong conclusion leaves the reader to draw it anyway.",
        )

    def test_an_available_roster_with_nobody_live_carries_no_receipt(self):
        """THE NEGATIVE CONTROL. A receipt on every empty answer is the same failure inverted.

        Here the registry IS readable and its records ARE placeable; none of them is in this repo. The
        empty list is then a measured answer, and calling it unavailable would train every consumer to
        ignore the word.
        """
        repo = self.new_repo()
        self.write_record("elsewhere", self.base / "some-other-checkout")
        r = self.run_script(
            t.PRESENCE, "-Json", "-Repo", str(repo), "-ConfigRoot", str(self.roots), cwd=repo
        )
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertEqual("[]", r.stdout.strip(), r.stderr)
        self.assertNotIn(
            self.UNAVAILABLE,
            r.stderr,
            "the roster was available and simply had nobody in this repo, and presence.ps1 still "
            "reported it as UNAVAILABLE. A warning that fires on the healthy path is one people learn "
            "to filter out, taking the real ones with it.",
        )

    def test_the_human_path_outside_a_repository_says_what_it_does_not_mean(self):
        r = self.run_script(t.PRESENCE, "-ConfigRoot", str(self.roots), cwd=self.outside)
        self.assertEqual(0, r.returncode, r.stderr)
        self.assertIn("NOT", r.stdout + r.stderr)


class RemoveActsOnTheBranchTheWorktreeWasOn(ScriptCase):
    """`remove.ps1 -DeleteBranch` -- which branch, and what the refusal is allowed to claim."""

    def worktree(self, primary: Path, name: str, *add_args: str) -> Path:
        """The sibling layout `new.ps1` produces: <parent-of-primary>/<primary-leaf>-<name>."""
        path = self.base / f"{primary.name}-{name}"
        git("worktree", "add", "-q", str(path), *add_args, cwd=primary)
        return path

    def remove(self, primary: Path, name: str) -> subprocess.CompletedProcess:
        # cwd is the primary: remove.ps1 refuses to remove the checkout it is standing in, and git
        # could not do it anyway.
        return self.run_script(t.WORKTREE_REMOVE, "-Name", name, "-DeleteBranch", cwd=primary)

    def test_a_namespaced_branch_that_has_landed_is_actually_deleted(self):
        """The headline case, and the one that silently did nothing.

        `new.ps1 -Name my-task -Branch feature/my-task` is a documented invocation -- it is how the
        worktree gate's branch-reuse remediation hands a namespaced ref back. The directory is
        `my-task`; the branch is `feature/my-task`. `git branch -d my-task` fails with "branch not
        found", the old code reported that as unmerged commits, and the real branch survived a run the
        human read as a full cleanup.
        """
        primary = self.new_repo()
        self.worktree(primary, "my-task", "-b", "feature/my-task")
        self.assertIn("feature/my-task", branches(primary))

        r = self.remove(primary, "my-task")
        self.assertEqual(0, r.returncode, r.stdout + r.stderr)
        self.assertNotIn(
            "feature/my-task",
            branches(primary),
            "-DeleteBranch left the branch behind. It asked git to delete the worktree's DIRECTORY "
            "name, which is not a branch name at all when -Branch was namespaced, and then reported "
            "the resulting 'branch not found' as unmerged commits.",
        )

    def test_a_refusal_reports_gits_own_reason_and_names_the_real_branch(self):
        primary = self.new_repo()
        wt = self.worktree(primary, "my-task", "-b", "feature/my-task")
        (wt / "b.txt").write_text("work nobody else has\n", encoding="utf-8")
        git("add", "-A", cwd=wt)
        git("commit", "-qm", "unlanded work", cwd=wt)

        r = self.remove(primary, "my-task")
        said = r.stdout + r.stderr
        self.assertEqual(0, r.returncode, said)
        self.assertIn(
            "feature/my-task",
            said,
            "the refusal named a branch that is not the one the worktree was on, so the reader is "
            "sent to investigate a ref that does not exist.",
        )
        self.assertIn(
            "not fully merged",
            said,
            "git's own explanation was discarded. The script may report what git said; it may not "
            "substitute a cause of its own, because it has not established one.",
        )
        self.assertNotIn(
            "it is not merged into its upstream",
            said,
            "the unconditional claim is back. `git branch -d` also refuses for a branch that does not "
            "exist and for one checked out elsewhere; asserting unmergedness for all three sends the "
            "reader looking for commits that were never at risk.",
        )
        self.assertIn(
            "feature/my-task",
            branches(primary),
            "an unmerged branch must survive -- the refusal is the signal this script exists to relay.",
        )

    def test_a_detached_worktree_does_not_delete_a_branch_that_shares_its_directory_name(self):
        """THE NEGATIVE CONTROL for 'delete the branch it was on': when it was on none, delete none.

        The old code ran `git branch -d $Name` regardless of what the worktree was actually on. With a
        detached worktree named `detach` and an unrelated branch also called `detach`, that deleted a
        branch this command was never pointed at.
        """
        primary = self.new_repo()
        git("branch", "detach", cwd=primary)
        head = git("rev-parse", "HEAD", cwd=primary).stdout.strip()
        self.worktree(primary, "detach", "--detach", head)

        r = self.remove(primary, "detach")
        said = r.stdout + r.stderr
        self.assertEqual(0, r.returncode, said)
        self.assertIn(
            "detach",
            branches(primary),
            "a detached worktree's removal deleted the branch that merely shared its directory name. "
            "Nothing pointed this command at that branch.",
        )
        self.assertIn(
            "detached",
            said.lower(),
            "-DeleteBranch was asked for and no branch was deleted; that has to be said out loud, or "
            "the run reads as a cleanup that did what it was told.",
        )


if __name__ == "__main__":
    unittest.main()
