"""The reaper must consult the occupancy fence once per REMOVAL, not once per RUN.

THE FAILURE THIS EXISTS FOR. `prune-merged.ps1` reads occupancy twice: once to build the decision
table, and again in the `-Apply` path immediately before it destroys anything. The second read is
the whole reason there is a second read -- the decision pass spends a gh round trip per candidate,
and a session can arrive inside that window.

That second call used to sit ABOVE the removal loop. One snapshot, taken before the first removal,
judged every candidate in the batch, so it was fresh for the first candidate and stale for every one
after it -- by exactly the interval it exists to close. Measured on this fixture, against the
shipped code: three prunable siblings, a session arriving in the second one the instant the first
was removed, and the reaper removed all three. The occupied worktree was destroyed, the receipt
reported `vetoedCandidates: 0`, and nothing in the run said the check had been made against a
snapshot older than the removal before it. With the read inside the loop the same fixture removes
two and skips the occupied one, and the batch continues.

A batch of one is the common case, which is why this survived: the bug cannot appear until a run
removes two worktrees, and that is also the run with the most to lose.

WHAT THIS PROVES, AND HOW. The headline cases RUN the reaper against a throwaway repository with a
shimmed fence, per docs/PRUNING.md ("Drive the re-check deterministically. Use a shim whose probe
performs the side effect *before* it answers ... No threads, no sleeps"). The shim WRAPS the real
`Get-WorktreeOccupancy` rather than replacing it -- a hand-written stub would be a second copy of a
safety check, which is the drift `occupancy.ps1` has one copy of the matcher to prevent.

The arrival is triggered off `Get-RepoWorktrees`, which the reaper calls once per removal to decide
whether a tree deregistered. That matters for fairness: it fires identically whether or not the
fence is re-read per candidate, so the fixture is not quietly built to favour the fix.

WHAT IT DOES NOT PROVE. Not that the window is closed -- it is not. A cleanliness check and the
removal itself still sit between the fresh read and the git command, and nothing here takes a lock.
What is pinned is that the staleness is bounded by one candidate's work rather than by the whole
batch's. It also proves nothing about the fence's own blind spots (a session writing in by absolute
path is invisible to signal 1 no matter how often it is asked).

EVERY BEHAVIOURAL CASE HAS A NEGATIVE CONTROL, because a green "the arrival was seen" is equally
consistent with a fixture whose planted record was never visible to anything. One case plants the
same record BEFORE the run and requires the decision pass to catch it.

THE LAST CASE READS THE SOURCE instead of running it, so this file still measures something on a
host with no `pwsh` or no `git`, where everything above skips.

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

# A fixture repo must not inherit the operator's identity, signing config, or advice settings: a
# commit that needs a passphrase, or a hook that runs, turns a test failure into a hang.
GIT_ID = (
    "-c", "user.email=ccx@test", "-c", "user.name=ccx test",
    "-c", "commit.gpgsign=false", "-c", "advice.detachedHead=false",
)

# The `-Apply` removal loop, matched by its loop variable and collection rather than by line number.
APPLY_LOOP = r"foreach\s*\(\s*\$d\s+in\s+\$prunable\s*\)\s*\{"

# `Get-WorktreeOccupancy` is the fence READ. `Get-WorktreeOccupants` -- one letter different, a few
# lines away in the same block -- only filters a snapshot somebody else already took. The word
# boundary is load-bearing: without it, consulting an existing snapshot would count as a fresh read
# and the static case would pass on the broken arrangement.
FENCE_READ = re.compile(r"\bGet-WorktreeOccupancy\b")

# APPENDED to a COPY of occupancy.ps1, never substituted for it. `${function:Get-WorktreeOccupancy}`
# captures the real body defined moments earlier in the same dot-source, so the fence still runs and
# still decides; the wrapper only observes it and counts.
#
# The second wrapper is the side effect. `Get-RepoWorktrees` is the trigger because prune-merged
# calls it once per removal (to decide whether the tree really deregistered), so the arrival lands
# BETWEEN two removals -- and fires the same way whether or not the fence is read per candidate.
SHIM = """
$script:CcxRealOccupancy = ${function:Get-WorktreeOccupancy}
function Get-WorktreeOccupancy {
    [CmdletBinding()]
    param([string]$Repo, [string[]]$ConfigRoot, [int]$StartSkewMinutes = 15)
    Add-Content -LiteralPath $env:CCX_FENCE_READS -Value 'fence-read'
    & $script:CcxRealOccupancy @PSBoundParameters
}

$script:CcxRealWorktrees = ${function:Get-RepoWorktrees}
function Get-RepoWorktrees([string]$RepoHint) {
    if ($env:CCX_ARRIVE_WHEN_GONE -and -not (Test-Path -LiteralPath $env:CCX_ARRIVE_WHEN_GONE)) {
        if (-not (Test-Path -LiteralPath $env:CCX_ARRIVE_RECORD)) {
            Set-Content -LiteralPath $env:CCX_ARRIVE_RECORD -Value $env:CCX_ARRIVE_JSON -Encoding utf8
        }
    }
    & $script:CcxRealWorktrees $RepoHint
}
"""


def apply_loop_body(source: str) -> str:
    """The body of the `-Apply` removal loop. RAISES rather than returning nothing.

    Brace matching, and nothing else. Indentation is a convention PowerShell does not enforce, and a
    plain offset comparison ("the call appears after the `foreach`") would happily accept a call
    sitting AFTER the loop or in an unrelated function further down the file.
    """
    m = re.search(APPLY_LOOP, source)
    if m is None:
        raise AssertionError(
            "prune-merged.ps1 no longer has a `foreach ($d in $prunable) {` loop. The apply loop was "
            "renamed or reshaped -- re-point this at it. Do NOT delete the case: it is the only "
            "thing here that says which removals the fence read actually covers."
        )
    body = source[m.end():t.close_brace(source, m.end())]
    if "worktree remove" not in body:
        raise AssertionError(
            "the block read as the apply loop contains no `git worktree remove`, so the brace match "
            "landed somewhere else and every assertion resting on it is vacuous."
        )
    return body


class ReaperCase(unittest.TestCase):
    """A primary, three prunable siblings, a shimmed fence, and a way to run the reaper at them."""

    def setUp(self):
        self.pwsh = t.find_pwsh()
        if not self.pwsh:
            self.skipTest("pwsh is not on PATH, so prune-merged.ps1 cannot be executed here")
        if not shutil.which("git"):
            self.skipTest("git is not on PATH, so the fixture repository cannot be built")
        self.tmp = tempfile.TemporaryDirectory(prefix="ccx-reaper-", ignore_cleanup_errors=True)
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.reads = self.base / "fence-reads.txt"
        self.reads.write_text("", encoding="utf-8")
        self.tree = self.shimmed_tree()
        self.primary, self.roots = self.fixture()

    def git(self, *args, cwd=None):
        r = subprocess.run(
            ["git", *GIT_ID, *args],
            cwd=str(cwd or self.primary), capture_output=True, text=True, timeout=TIMEOUT_SECONDS,
        )
        self.assertEqual(0, r.returncode, f"git {' '.join(args)} failed:\n{r.stdout}\n{r.stderr}")
        return r.stdout

    def shimmed_tree(self) -> Path:
        tree = self.base / "tree"
        shutil.copytree(t.REPO_ROOT / "scripts", tree / "scripts")
        occ = tree / "scripts" / "coord" / "occupancy.ps1"
        source = occ.read_text(encoding="utf-8")
        for needed in ("function Get-WorktreeOccupancy", "function Get-RepoWorktrees"):
            self.assertIn(
                needed, source,
                f"occupancy.ps1 no longer defines `{needed}`. The shim would capture $null, the "
                "wrapper would fail or silently do nothing, and this fixture would measure nothing.",
            )
        occ.write_text(source + SHIM, encoding="utf-8")
        return tree

    def fixture(self) -> tuple[Path, Path]:
        primary = self.base / "primary"
        primary.mkdir()
        self.git("init", "-q", "-b", "main", cwd=primary)
        # trunk is pinned rather than 'auto': the fixture has no remote, so there is no recorded
        # default branch for auto to resolve, and the run would refuse before reaching the loop.
        (primary / "ccx.config.json").write_text(
            json.dumps({"prefix": "ccx", "trunk": "main", "worktreeLayout": "sibling"}),
            encoding="utf-8",
        )
        (primary / "README.md").write_text("fixture\n", encoding="utf-8")
        self.git("add", "-A", cwd=primary)
        self.git("commit", "-qm", "init", cwd=primary)
        for name in ("one", "two", "three"):
            self.git("worktree", "add", "-q", str(self.base / f"primary-{name}"),
                     "-b", f"feature/{name}", cwd=primary)

        # SIGNAL 2, SATISFIED HONESTLY. A worktree created a second ago has fresh git metadata and is
        # vetoed as recently active. The alternative -- `-IdleHours 0` -- disarms signal 2 entirely
        # and would make every case here a measurement of a deliberately degraded run, which the
        # script itself prints in red as reduced assurance. Backdating the per-worktree admin
        # directory leaves the DEFAULT window armed, so these cases run the shipped configuration.
        when = time.time() - 48 * 3600
        for admin in (primary / ".git" / "worktrees").iterdir():
            for f in list(admin.rglob("*")) + [admin]:
                os.utime(f, (when, when))

        roots = self.base / "roots"
        (roots / "sessions").mkdir(parents=True)
        # One readable record, placed OUTSIDE every worktree. Without it the registry holds nothing
        # readable, which the fence reports as unavailable -- and every case would pass by refusing.
        (roots / "sessions" / "4242.json").write_text(
            json.dumps({"sessionId": "fixture-elsewhere", "pid": 4242, "cwd": str(self.base / "nowhere")}),
            encoding="utf-8",
        )
        return primary, roots

    def reap(self, *args: str, arrival: dict | None = None) -> dict:
        env = dict(os.environ)
        # The real session's own coordination variables must not reach the fixture: CCX_TRUNK in
        # particular would override the pinned trunk and decide the merge test.
        for leak in ("CCX_CONFIG", "CCX_TRUNK", "CCX_ARRIVE_WHEN_GONE",
                     "CCX_ARRIVE_RECORD", "CCX_ARRIVE_JSON"):
            env.pop(leak, None)
        env["CCX_FENCE_READS"] = str(self.reads)
        env.update(arrival or {})
        r = subprocess.run(
            [self.pwsh, "-NoProfile", "-File",
             str(self.tree / "scripts" / "worktree" / "prune-merged.ps1"),
             "-RepoRoot", str(self.primary), "-ConfigRoot", str(self.roots),
             "-SkipFetch", "-SkipGh", "-Json", *args],
            capture_output=True, text=True, env=env, cwd=str(self.primary), timeout=TIMEOUT_SECONDS,
        )
        self.assertTrue(
            r.stdout.strip(),
            f"the reaper emitted no JSON at all (exit {r.returncode}). It died before its receipt:"
            f"\n{r.stderr}",
        )
        return json.loads(r.stdout)

    def shim_counted_reads(self) -> int:
        return len([ln for ln in self.reads.read_text(encoding="utf-8").splitlines() if ln.strip()])

    def prunable_order(self) -> tuple[list[str], dict[str, str]]:
        """The order git yields the candidates in, read from a dry run rather than assumed.

        Load-bearing. git's worktree order is not alphabetical and is not promised to be anything;
        on this machine it comes back one/three/two. A case that planted the arrival in the tree
        that happens to be removed FIRST would prove nothing about a stale snapshot, because the
        first candidate's snapshot is fresh under both arrangements.
        """
        preview = self.reap()
        order = [c["Leaf"] for c in preview["candidates"] if c["Decision"] == "PRUNE"]
        paths = {c["Leaf"]: c["Path"] for c in preview["candidates"]}
        self.assertGreaterEqual(
            len(order), 3,
            "the fixture produced fewer than three prunable siblings, so there is no 'second "
            "removal' to judge and the headline case would pass vacuously. Reasons: "
            + "; ".join(f"{c['Leaf']}: {c['Reason']}" for c in preview["candidates"]),
        )
        self.reads.write_text("", encoding="utf-8")
        return order, paths


class ASessionArrivingMidBatchIsStillSeen(ReaperCase):
    def test_the_second_removal_sees_a_session_that_arrived_during_the_first(self):
        order, paths = self.prunable_order()
        record = self.roots / "sessions" / "9001.json"
        result = self.reap("-Apply", arrival={
            "CCX_ARRIVE_WHEN_GONE": paths[order[0]],
            "CCX_ARRIVE_RECORD": str(record),
            "CCX_ARRIVE_JSON": json.dumps(
                {"sessionId": "arrived-mid-batch", "pid": os.getpid(), "cwd": paths[order[1]]}),
        })
        # Instrument first: a green result below is worthless if the arrival never happened.
        self.assertTrue(
            record.exists(),
            "the shim never planted the arriving session's record, so nothing tested the re-check. "
            "The trigger is the first candidate's directory disappearing; either it was not removed "
            "or Get-RepoWorktrees is no longer called between removals.",
        )
        rows = {c["Leaf"]: c for c in result["candidates"]}

        self.assertEqual(
            "removed", rows[order[0]]["Outcome"],
            "the FIRST candidate was not removed, so the arrival trigger never fired and the rest "
            "of this case is measuring an empty run.",
        )
        self.assertEqual(
            "skipped", rows[order[1]]["Outcome"],
            f"a session arrived in {order[1]} while {order[0]} was being removed, and the reaper "
            "removed it anyway. The occupancy re-check ran against a snapshot taken before the "
            "batch started, so it could not see an arrival that happened during the batch. This is "
            "the destroyed-session case: clean and merged is not unoccupied.",
        )
        self.assertIn(
            "a session arrived", rows[order[1]]["OutcomeDetail"],
            "the second candidate was skipped for some OTHER reason than the arriving session. "
            "Assert the reason, not survival: a skip for the wrong reason is a test that would stay "
            "green with the fence removed entirely.",
        )
        self.assertTrue(
            rows[order[1]]["Occupants"],
            "the candidate the fence just saved reports `Occupants: []`. The re-check must write "
            "the occupants back onto the decision, or the 'vetoed by signal 1' figure under-reports "
            "the save to zero -- the figure that exists so 'the fence ran' cannot imply 'the fence "
            "covered it'.",
        )
        self.assertEqual(
            1, result["fence"]["vetoedCandidates"],
            "the receipt does not count the re-check save as a signal-1 veto.",
        )
        # The positive control, in the same invocation: an occupied tree must not abort the batch.
        self.assertEqual(
            "removed", rows[order[2]]["Outcome"],
            "the THIRD candidate was not removed. One occupied worktree is not a reason to abandon "
            "the rest of the run, and a reaper that refuses everything gets switched off -- after "
            "which it protects nothing.",
        )

    def test_the_same_record_is_caught_at_decision_time_when_it_is_already_there(self):
        """The negative control. Proves a planted record is visible to the fence AT ALL.

        Without this, the case above is equally consistent with a fixture whose record the fence
        could never see and a second candidate skipped for some unrelated reason.
        """
        order, paths = self.prunable_order()
        (self.roots / "sessions" / "9001.json").write_text(
            json.dumps({"sessionId": "already-there", "pid": os.getpid(), "cwd": paths[order[1]]}),
            encoding="utf-8",
        )
        preview = self.reap()
        row = {c["Leaf"]: c for c in preview["candidates"]}[order[1]]
        self.assertEqual(
            "SKIP", row["Decision"],
            "a session record sitting in a worktree before the run even started was not caught by "
            "the decision pass. The fixture's records are invisible to the fence, so every other "
            "case in this file is passing for the wrong reason.",
        )
        self.assertIn("occupied by", row["Reason"])


class TheFenceIsReadOncePerRemoval(ReaperCase):
    def reads_at_apply(self, result: dict) -> int:
        reads = result["fence"].get("readsAtApply")
        self.assertIsNotNone(
            reads,
            "the fence receipt carries no `readsAtApply`. That field is how an operator -- or a "
            "consumer of the JSON -- sees for themselves how many times the fence was consulted, "
            "next to how many candidates it was consulted for. Without it, 'the fence was re-read "
            "before each removal' is a claim this tool makes about itself and nobody can check.",
        )
        return reads

    def test_the_receipt_reports_one_read_per_candidate(self):
        """The sentence, as one number, off the shipped receipt -- no shim required to read it."""
        self.prunable_order()
        result = self.reap("-Apply")
        reads = self.reads_at_apply(result)
        self.assertEqual(
            result["counts"]["prunable"], reads,
            f"the occupancy fence was not read once per candidate during the apply phase: {reads} "
            f"read(s) covered {result['counts']['prunable']} candidate(s). One snapshot judged more "
            "than one removal, so every removal after the first was decided on a registry read "
            "taken before the removals started -- stale by exactly the interval the re-check exists "
            "to close.",
        )

    def test_the_reported_count_is_the_number_of_calls_that_really_happened(self):
        """The receipt's own counter, checked against a count taken outside the script.

        A field the script computes about itself is only as good as the increment behind it. The
        shim counts the decision pass too, so the expected total is one more than the apply reads.
        """
        self.prunable_order()
        result = self.reap("-Apply")
        self.assertEqual(
            self.shim_counted_reads(), self.reads_at_apply(result) + 1,
            "the fence reads counted from OUTSIDE the reaper do not match `readsAtApply` plus the "
            "one decision-pass read. Either the receipt's counter has drifted from the calls it "
            "claims to count, or the decision pass stopped reading the fence.",
        )


class AFenceThatDiesMidBatchStopsTheRest(ReaperCase):
    """The promise in prune-merged.ps1's header and in docs/PRUNING.md, made real.

    It used to hold by accident: with one snapshot per run the unavailable verdict was
    loop-invariant, so every candidate skipped. One read per candidate turns it into a real
    decision, and a fence that recovers by candidate 4 has told us nothing about candidate 2.
    """

    def test_a_fence_that_dies_after_a_removal_stops_the_rest_and_says_so(self):
        order, paths = self.prunable_order()
        record = self.roots / "sessions" / "9001.json"
        result = self.reap("-Apply", arrival={
            "CCX_ARRIVE_WHEN_GONE": paths[order[0]],
            "CCX_ARRIVE_RECORD": str(record),
            # A HALF-WRITTEN record, which is what a session that launched a second ago looks like
            # on disk. It cannot be placed, so no worktree can be cleared and the fence is
            # unavailable -- the real production mechanism, not a faked receipt.
            "CCX_ARRIVE_JSON": '{"sessionId": "half-writ',
        })
        rows = {c["Leaf"]: c for c in result["candidates"]}
        self.assertEqual("removed", rows[order[0]]["Outcome"], "the trigger never fired")

        self.assertEqual(
            "skipped", rows[order[1]]["Outcome"],
            "an unplaceable session record appeared mid-batch -- the fence could no longer clear "
            "ANY worktree -- and the reaper removed the next candidate anyway.",
        )
        self.assertEqual(
            "skipped", rows[order[2]]["Outcome"],
            "the run resumed destroying worktrees after the fence died. 'A fence that dies mid-run "
            "stops the rest' is stated in this script's header and in docs/PRUNING.md; a later read "
            "coming back available says nothing about the candidate that was already skipped.",
        )
        self.assertIn("died earlier in this run", rows[order[2]]["OutcomeDetail"])
        self.assertFalse(
            result["fence"]["availableAtApply"],
            "the receipt reports the apply-time fence as available after it died mid-batch. With "
            "one read per candidate there are several answers and the receipt speaks for all of "
            "them: one unavailable read must survive every later available one.",
        )
        self.assertFalse(
            result["fence"]["available"],
            "the fail-closed headline is true while the fence was unavailable at one of its reads.",
        )
        self.assertTrue(
            result["fence"]["detailAtApply"],
            "the receipt says the fence died but not why. detailAtApply names the offending file; "
            "without it the operator has nothing to go and look at.",
        )
        self.assertEqual(
            1, result["exitCode"],
            "exit 2 means 'nothing was attempted, because safety could not be established', and a "
            f"worktree had already been removed when the fence died. Same rule docs/PRUNING.md "
            "states for a -Name that matched nothing: exit 2, or 1 if something was already "
            "removed.",
        )


class TheCallSiteStaysInsideTheLoop(unittest.TestCase):
    """Reading, not running -- so this file still measures something where pwsh or git are absent.

    It is also the case that reddens on a refactor that hoists the call back out "for efficiency",
    which is a change no behavioural case would catch until somebody ran the suite on a host with
    both binaries.
    """

    def test_the_fence_read_is_inside_the_removal_loop(self):
        # Comments stripped, and that is mandatory here rather than tidy: the comment above the call
        # discusses at length where the call used to sit and why it moved. A raw-text scan is one
        # reword away from matching prose that describes the fix instead of the fix.
        body = apply_loop_body(t.ps_source(t.PRUNE_MERGED))
        self.assertEqual(
            1, len(FENCE_READ.findall(body)),
            "the occupancy fence is not read exactly once inside the removal loop. Zero means one "
            "snapshot judges the whole batch, so from the second removal onwards the re-check reads "
            "as a fresh look at the registry and is not one. More than one means a candidate pays "
            "for two reads; collapse them rather than deleting this assertion.",
        )

    def test_every_snapshot_consumer_in_the_loop_gets_the_loop_s_own_read(self):
        """A fresh read that nothing consults is the original bug with a new call in front of it."""
        body = apply_loop_body(t.ps_source(t.PRUNE_MERGED))
        assigned = re.search(r"\$(\w+)\s*=\s*Get-WorktreeOccupancy\b", body)
        self.assertIsNotNone(
            assigned,
            "the in-loop fence read assigns to nothing, so no check in the loop can be using it.",
        )
        fresh = assigned.group(1)
        consumers = re.findall(r"-Occupancy\s+\$(\w+)", body)
        self.assertTrue(
            consumers,
            "no `-Occupancy $x` call remains inside the removal loop. The re-check no longer "
            "consults occupancy at all, which is worse than the stale snapshot it replaced.",
        )
        self.assertEqual(
            [], sorted({c for c in consumers if c != fresh}),
            f"the loop reads occupancy into ${fresh} but hands an older variable to a check. Every "
            f"`-Occupancy` inside the loop must be given ${fresh}, or the read is fresh and the "
            "answer is not.",
        )

    def test_the_matcher_can_tell_inside_from_outside(self):
        """Prove the instrument. A brace matcher that lands anywhere accepts both arrangements."""
        outside = ("foreach ($d in $prunable) {\n  git worktree remove --force $d.Path\n}\n"
                   "$occ2 = Get-WorktreeOccupancy\n")
        inside = ("foreach ($d in $prunable) {\n  $o = Get-WorktreeOccupancy\n"
                  "  git worktree remove --force $d.Path\n}\n")
        self.assertNotIn("Get-WorktreeOccupancy", apply_loop_body(outside))
        self.assertIn("Get-WorktreeOccupancy", apply_loop_body(inside))
        # A nested block, a brace inside a string, and a brace inside a comment must not end the
        # body early: closing it early would put the real call "outside" and redden a healthy file,
        # while closing late would swallow a hoisted call and pass a broken one.
        awkward = ('foreach ($d in $prunable) {\n  if ($x) { $y = 1 }\n'
                   '  Write-Host "a brace } in a string"\n  # and a brace } in a comment\n'
                   '  $o = Get-WorktreeOccupancy\n  git worktree remove x\n}\n')
        self.assertIn("Get-WorktreeOccupancy", apply_loop_body(awkward))
        with self.assertRaises(AssertionError):
            apply_loop_body("# there is no apply loop in this text at all\n")
        with self.assertRaises(AssertionError):
            apply_loop_body("foreach ($d in $prunable) {\n  Write-Host 'no removal here'\n}\n")


if __name__ == "__main__":
    unittest.main()
