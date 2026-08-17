# Landing work: PRs and merges

## TLDR/BLUF

**What this is.** How to land several parallel branches in one trunk without losing commits. The
one check to run first. The four states that all read as "can't merge". How to resolve a conflict
without dropping half a file.

**Why you should care.** Every failure in the last mile looks like something else. Being ahead of
the trunk is not evidence of unmerged work, and reading it that way has destroyed commits.

Not for you if only one branch is ever in flight. The `git` commands here are portable; the `pwsh`
scripts are PowerShell 7.3+ with Windows as the exercised path, and every `gh` command assumes
GitHub. [Limits and requirements](LIMITS.md) has the platform matrix.

**How to use it.** Run the merge-base check below before you trust any "is it merged?" answer.
[WORKTREES.md](WORKTREES.md) covers creating and living in worktrees.
[PRUNING.md](PRUNING.md) covers cleaning them up afterwards.

---

Several sessions working in parallel produce several branches, and all of them have to land in one
trunk.

Everything here was learned by getting it wrong. Every number quoted was measured on the repo this
tooling was developed in. It is evidence for the rule, not a universal constant.

Two assumptions run through the whole document, because they are what make the traps traps:

- **The trunk squash-merges.** A branch's own commits never become ancestors of the trunk. So every
  reachability-based test -- `rev-list`, `merge-base --is-ancestor`, `git cherry` -- answers "not
  merged" forever, for work that landed weeks ago.
- **Somebody else lands something while you are working.** Not hypothetically. Measured on the repo
  this tooling was developed in, the trunk moved seven times during the life of one pair of pull
  requests.

## What "trunk" means to these scripts

Every script resolves the trunk through one function, `Get-CcxTrunk` in
[`scripts/coord/_common.ps1`](https://claude-multisession.pages.dev/scripts/coord/_common.ps1), in this order:

| Order | Source | Notes |
|---|---|---|
| 1 | `$env:CCX_TRUNK` | Per-session override; wins over everything. |
| 2 | `trunk` in [`ccx.config.json`](https://claude-multisession.pages.dev/ccx.config.json) | Unless it is the literal `auto`. |
| 3 | `git symbolic-ref --short refs/remotes/origin/HEAD` | What the remote says its default branch is -- the only source that survives a rename. |
| 4 | First of `origin/main`, `origin/master`, `main`, `master` that resolves | Last resort. |

It returns a **remote-tracking** ref where it can. A local `main` lags its upstream silently, and
branching off a stale one is how sessions build on old code. Step 3 fails on a clone made before
the remote head was recorded. Fix that once with `git remote set-head origin -a`.

The examples below spell the trunk `origin/main`. Substitute yours.

## Check the merge base before anything else

**The goal.** Find out whether your branch already contains the trunk tip. Do this before you read
a diff, before you open the PR, before you decide a branch is fine.

**What to do.**

```bash
git fetch origin
git merge-base --is-ancestor origin/main HEAD   # exit 0 = your branch contains the trunk tip
```

**What happens next.** Exit 0 means the branch already contains the trunk tip and you can carry on.
A non-zero exit means it does not. Merge the trunk in before going further, and read the trap below
before you assume the branch is only behind.

In PowerShell read the exit code from `$LASTEXITCODE`, not `$?`. `$?` is a boolean about the last
statement, and it will happily report success on a check that answered "no".

### The trap: A branch cut from a pre-squash commit

A branch was cut from a commit pushed to an already-squash-merged PR. Three-dot diff and
"Files changed" both showed roughly 13 files, 2,967 insertions, 19 deletions -- accurate, silent on
the five files that would conflict. Its merge base was eleven squash-merged PRs behind the trunk.

The squash is the mechanism: the branch's content reached the trunk as one *new* commit, so its own
commits never became ancestors. Branch from one and you inherit a pre-squash merge base.
`git diff origin/main...HEAD` diffs against that base, so it cannot report the problem.

Once `--is-ancestor` has failed, confirm with the two-dot form:

```bash
git diff --stat origin/main HEAD      # two-dot: what still DIFFERS from the trunk
git diff --stat origin/main...HEAD    # three-dot: what the BRANCH AUTHORED
```

A non-zero **deletion** count from the two-dot form is the signal that the branch does not contain
the trunk's tree. **It does not mean your branch would remove that content.**

Two-dot compares two trees, so everything the trunk gained since the merge base reads as a deletion.

Measured on a three-commit fixture: a branch one commit behind, adding one file and removing nothing,
reported 4 deletions across 2 files. Merging the trunk in removed none of them.

The page's own numbers below say the same thing -- 22 two-dot deletions before the merge, identical
forms after. [Coordination](COORDINATION.md) records a branch 63 commits behind whose 3,247 two-dot
deletions were briefly read as what landing it would do.

**Fix by merging, not rebasing.** Run `git merge origin/main` into the branch. The trunk's side of
the squashed files is authoritative. A rebase re-raises the squash seam once per commit --
see [merge over rebase](#prefer-merge-over-rebase-when-every-commit-touches-one-block).

### The staleness check that agrees with itself

The tempting test is "compare the two-dot and three-dot diffs; if they match, the branch is fine."
It is worthless, and worse than worthless because it feels like a measurement.

Once `--is-ancestor` passes, the merge base **is** `origin/main` and the forms *cannot* disagree.
Measured minutes apart: while `--is-ancestor` failed, two-dot gave 2 files / 52 insertions /
22 deletions, three-dot 1 file / 50 insertions, deletions invisible. After the merge, identical.

**Rule:** `--is-ancestor` is the load-bearing check. The diff comparison only confirms it. A test
that agrees with itself in the healthy case is how a trap survives being checked for.

## Reading "can't merge": Four states, three different fixes

A PR that was green ten minutes ago stops being mergeable, and the reflex is to rebase and
force-push. That reflex is right for exactly one of the four states and destructive in another.

**The goal.** Know which of the four states you are in before you touch the branch.

**What to do.**

```bash
gh pr view <N> --json state,mergeable,mergeStateStatus,statusCheckRollup
```

**What happens next.** `mergeStateStatus` names the state. When it is one of the four below, take
the fix from that row's **Do** column.

| State | What it actually is | Do | Do not |
|---|---|---|---|
| `BEHIND` | The branch does not contain the trunk tip. Mechanical; no conflict. | Merge the trunk in, or `gh pr update-branch <N>`. | -- |
| `DIRTY` | A real textual conflict. | Resolve by hand, deliberately, in a worktree. | Treat it as `BEHIND`. That means resolving conflicts in a hurry to make a force-push succeed. |
| `BLOCKED` | Required checks or reviews are not satisfied. Usually still running. | Count *actual failures* in `statusCheckRollup`. Zero failures plus pending legs means **wait**. | Rebase and force-push -- it cancels the running checks and restarts the clock. |
| `UNKNOWN` | The code host is still recomputing mergeability. | Re-read in a few seconds. | Anything else. |

`BEHIND` and `DIRTY` are the pair that get confused, and the wrong fix is the destructive one.
`BLOCKED` is the one that looks most actionable and usually is not.

> **Limit.** `mergeStateStatus` is GitHub's field and `gh` is a GitHub client. On another code host the
> four states still exist conceptually -- behind, conflicting, gated, not-yet-computed -- but you will
> read them from a different API. What does not change is the rule: **establish which of the four you
> are in before you touch the branch.**

## Two pull requests at once

### Armed auto-merge does not win the race against the trunk moving

Two PRs were queued with auto-merge armed. The first landed. The second sat armed and stalled
indefinitely -- no failure, no merge, nothing to react to.

Auto-merge waits for **checks** to finish. It does **not** update a branch that has gone `BEHIND`.
Landing the first PR is precisely what puts the second one `BEHIND`, and nothing un-sticks it.

**Rule:** if you queue two PRs, plan to re-sync the second after the first lands, and keep a *capped*
update loop rather than an unbounded one.

> Measured with the repository's "allow update branch" setting off. Whether turning that setting on
> changes the behavior is **unverified**. No back-fill was ever observed, and the code host's own
> documentation does not connect the setting to this case. Do not repeat it as fact.

### A merge-watcher needs three arms, not two

A poller that checks only "merged?" and "failing?" reports "still running" to its timeout while
nothing progresses. The commonest outcome is the third: the trunk moved and the branch went
`BEHIND` again. That is neither a merge nor a failure, so a two-armed watcher is *structurally*
blind.

**The goal.** Watch a PR to a decision instead of to a timeout.

**What to do.** Poll for **merged / failing / went stale**, and act on the third:

```powershell
$pr = <N>
for ($i = 0; $i -lt 40; $i++) {
    $j = gh pr view $pr --json state,mergeStateStatus,statusCheckRollup | ConvertFrom-Json
    if ($j.state -eq 'MERGED') { 'merged'; break }

    # Check-run entries carry `conclusion`; legacy commit statuses carry `state`. Handle both or
    # you will poll past a failure without seeing it.
    $bad = @($j.statusCheckRollup | Where-Object {
            $_.conclusion -in @('FAILURE','TIMED_OUT','CANCELLED') -or $_.state -eq 'FAILURE' })
    if ($bad.Count -gt 0) { "failing: $($bad[0].name)"; break }

    # THE THIRD ARM.
    if ($j.mergeStateStatus -eq 'BEHIND') { gh pr update-branch $pr | Out-Null }

    Start-Sleep -Seconds 30
}
```

**What happens next.** The loop prints `merged` or the name of the first failing leg, then stops.
If it just keeps going, the third arm is re-syncing a branch the trunk keeps moving out from under.

### "Nothing pending" right after a push means "nothing has started"

Polling the checks immediately after a push showed no pending legs, which read as "everything
settled". The new run's legs did not exist yet. **Absence of pending is indistinguishable from
absence of checks.**

**Rule:** assert on the **count of legs you expect**, not on the absence of pending ones. Take the
expected set from wherever your required checks are declared, and read it at the time. Never from
memory, because that list changes.

This is the same failure shape as taking `--ours` on a conflict, below. The instrument was accurate
about what it looked at, and silent about what it did not look at.

## Resolving conflicts without losing work

### Never take a side wholesale on an append-only file

A changelog, a backlog, a decision index -- one large file that every session appends to. Those files
conflict more than anything else in the repo, and they are the ones where `--ours` and `--theirs` are
most tempting.

```bash
git checkout --ours docs/CHANGELOG.md    # <-- this is the one that loses work silently
```

Both sides of an append-only conflict produce a **well-formed file**. Nothing anywhere reports that
half the content is gone:

- no conflict markers
- `git status` clean
- the structure check passes
- the linter passes
- CI green

A real instance: two PRs each added a `### Changed` block. The union was the correct answer.
`--ours` would have dropped two already-published breaking-change notices. `--theirs` would have
dropped the incoming one. Either resolution would have merged green.

**Rule:** re-apply *intent*. Keep every entry from both sides, then verify by name that the specific
things you expect to survive are present:

```bash
git grep -n "one distinctive phrase from THEIR entry"
git grep -n "one distinctive phrase from YOUR entry"
```

### Anchor a find-and-replace, and re-verify it after the conflict is resolved

Renumbering an item from `1252` to `1316` across a changelog turned `cp1252` into `cp1316`, in a
file nobody re-reads.

Two things went wrong and both generalize. The replacement was a **bare number**, so it matched
inside unrelated tokens. And it was re-run during **conflict fixup**, which is exactly when a sweep
gets repeated carelessly, on a file whose content just changed underneath it.

**Rule:** scope replacements to anchored forms (`item #1252`, `## 1252.`, `^1252\|`), never the
bare number. Re-verify the sweep **after** resolving the conflict, not only after the original edit.

### Prefer merge over rebase when every commit touches one block

Rebasing a stack whose commits all append to the same point in the same file re-raises the identical
conflict once per commit. Resolving it mid-stack -- against an intermediate revision of the text --
kept an **earlier draft** of the block.

That result has no conflict markers, leaves `git status` clean, and passes a structural check. An
entry that lost half its prose still has exactly one heading and still counts as one entry. Nothing
anywhere reports it.

**Rule:** use one `git merge origin/main` so the seam is raised **once**, against the final text.
Then verify by grepping for a string that only your *latest* revision contains. A structural check
tells you the block is well-formed, not that it is the version you meant.

### A content comparison does not predict a clean merge

Five files were byte-compared before a merge and reported identical. That was true when measured and
false twenty minutes later, because an in-flight PR touching exactly those five files merged in
between.

A content spot-check answers "are these equal right now". It does not answer "will this merge
cleanly", and with an armed PR queued against the same files the first question stops predicting the
second at all.

**Rule:** use `git merge-tree --write-tree`, or an actual trial merge in a throwaway worktree. Those
are the two commands that answer the question you asked.

**Pass `--write-tree`, not the bare form.** The old three-argument
`git merge-tree <base> <ours> <theirs>` exits 0 whether or not the merge conflicts.

So it reports a confident clean about a branch that does not merge. `--write-tree` exits 1 and names
each conflicting path. [Coordination](COORDINATION.md) records a run where the bare form did that.

**The goal.** Find out whether the merge conflicts, without risking the branch you care about.

**What to do.**

```powershell
# A real trial merge, isolated, disposable.
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name mergetrial -Base my-branch
# ...in the new worktree:  git merge origin/main
# then, from ANOTHER checkout -- and abort first if it conflicted:
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name mergetrial -DeleteBranch -Force
```

**The teardown refuses in exactly the case the trial exists to find.** A conflicted merge leaves
modified tracked files, and `remove.ps1` refuses on those without `-Force`.

It also refuses while you are standing inside the worktree it is removing. So `git merge --abort`
first, or pass `-Force`, and run it from elsewhere.

`-DeleteBranch` deletes the branch that worktree had checked out, and `git branch -d` will refuse it
while the merge is unlanded -- leaving the trial branch behind. That is the safe direction; delete it
by hand once you are sure.

**What happens next.** The trial merge either succeeds or raises the real conflicts, in a worktree
you throw away either way. Do not expect `gh pr update-branch` to rescue a conflicting merge: it
updates by merging the base into the PR branch **server-side** and accepts no conflict resolution.

Before you start resolving, ask who else is in those files right now:

```powershell
pwsh -NoProfile -File scripts/coord/overlap.ps1 -File path/to/file.md
```

That reports peer worktrees whose **committed-and-unlanded** or **uncommitted** work touches the
same path. It intersects the two-dot and three-dot file sets, so a branch that has already landed
usually stops claiming its files.

**Two caveats before you trust the answer.** The map is served from a cache up to 60 seconds old
unless you pass `-Refresh`.

And **the self-clearing holds only while nobody else edits that file.** Once a later branch touches
it, two-dot reports it as differing from the trunk again, the intersection stops being empty, and the
landed branch is blamed for somebody else's edit. [Coordination](COORDINATION.md) measured both.

## Writing up the result: Two true numbers can make a false sentence

An earlier revision of this document paired a **post-merge** three-dot reading with a **pre-merge**
two-dot reading as one comparison. A diff that never proposed a revert was described as proposing
one. Every number was real. Only the **join** was false, and it carried the whole argument.

It survived its author's review, a second reviewer, an independent verification pass and a green CI
run. Nothing checks joins. No linter, no test, no reviewer habit.

**Rule:** before two numbers share a sentence, confirm they describe **the same commit at the same
moment**. Record the ref and the time you measured each one. This one is on you.

## After it lands

Squash-merge is why cleanup needs its own tooling. After the work is in the trunk:

- `git rev-list --count origin/main..<branch>` still counts every original commit -> says *not merged*
- `git merge-base --is-ancestor <branch> origin/main` is false -> says *not merged*
- `git cherry origin/main <branch>` marks the commits `+` unless the patch-ids match exactly, which
  they stop doing the moment anything was rebased, amended or conflict-resolved

All three ask the same question -- "is this commit reachable from the trunk" -- and squash-merge is
defined by making the answer no. So **being ahead of the trunk is not evidence of unmerged work**.

[`scripts/worktree/prune-merged.ps1`](https://claude-multisession.pages.dev/scripts/worktree/prune-merged.ps1)
carries three merge signals instead of one:

- nothing beyond the trunk
- *or* a merged PR whose head is this exact tip
- *or* the branch's own upstream ref is gone

The converse is worse, and it destroyed an occupied worktree: **zero commits beyond the trunk does
not mean merged either** -- a branch created seconds ago looks exactly like that. Merge state is
never sufficient on its own. See [PRUNING.md](PRUNING.md).

**The goal.** Remove the worktrees whose work has landed, and only those.

**What to do.**

```powershell
# from the PRIMARY checkout -- it refuses from a linked worktree, exit 2
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Fetch          # dry run, decision table
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Fetch -Apply   # act on a table re-derived now
```

**What happens next.** The dry run prints the decision table and changes nothing. `-Apply`
re-derives that table at the moment it acts, rather than trusting the one you just read.

**`-Fetch` on both, or the preview is not the run.** Why, and what the exit-2 refusal from a linked
worktree is protecting you from, are
[Pruning](PRUNING.md#a-wrong-cwd-run-must-refuse-loudly-never-green-no-op)'s to state. It owns the
decision rule and every flag that narrows it.

For a single finished worktree, [`remove.ps1`](https://claude-multisession.pages.dev/scripts/worktree/remove.ps1) is the manual path. Two
of its behaviors matter at merge time:

- It **references the tip before removing anything**, and with `-DeleteBranch` writes it to
  `refs/<prefix>/removed/<name>` first. A commit in no ref is in no reflog either, and nothing in the
  interface admits it ever existed.
- It uses `git branch -d`, **never** `-D`. Git refusing to delete an unmerged branch is a *signal*
  that the branch holds commits no other ref has. If the local trunk merely lags the remote, fetch
  and retry. Do not force past the refusal as a tidying step.

Work claims taken with [`claim.ps1`](https://claude-multisession.pages.dev/scripts/coord/claim.ps1) do not expire, and they do not
release themselves when a PR merges.

**The goal.** Hand your claimed files back to the other sessions once the work has landed.

**What to do.**

```powershell
pwsh -NoProfile -File scripts/coord/claim.ps1 -Release <key>
pwsh -NoProfile -File scripts/coord/claim.ps1 -List
```

**What happens next.** `-List` shows what is still held, so you can confirm yours is gone. The
pruning tool releases claims held by a worktree only once that worktree is proven **gone and
deregistered** -- evidence, never a timer.

## What this tooling does and does not do for you

Stated plainly, because at merge time an assumption that is wrong is expensive:

- **PowerShell 7, Windows-first.** The scripts are PowerShell 7 (`#Requires -Version 7.3`). The git
  commands in this document are portable. The scripts are not yet.
- **GitHub is assumed where `gh` appears.** The PR-state table, the watcher loop, and the merged-PR
  signal in the pruning tool all call `gh`. The pruning tool degrades explicitly -- `-SkipGh`, and a
  failed probe is reported as a failed probe rather than as "not merged".
- **The push guard is a guardrail, not a security boundary.**
  [`scripts/hooks/push_guard.py`](https://claude-multisession.pages.dev/scripts/hooks/push_guard.py) refuses a direct push to anything in
  `protectedRefs` (default `main` and `master`), locally and before the round trip.

  Limit: `git push --no-verify` skips it, and it is installed per clone, so configure server-side
  protection too. The escape hatch is `CCX_ALLOW_DIRECT_PUSH=1`, distinct from `--no-verify` so it
  is greppable in shell history.
- **An installed guard and a working guard are different claims.** These hooks are copied into
  place. One whose helpers were not copied can refuse *every* push, for reasons unrelated to what it
  checks. One never installed is just a source file. Prove it by receipt before you rely on it:

  ```powershell
  pwsh -NoProfile -File bin/ccx-doctor.ps1
  ```

## The traps in one table

| Trap | What it looked like | Rule |
|---|---|---|
| Pre-squash merge base | A clean three-dot diff and a tidy "Files changed" tab | Run `git merge-base --is-ancestor origin/main HEAD` **first**; fix by merging, not rebasing |
| Self-agreeing staleness check | Two-dot and three-dot diffs matched | They cannot disagree once `--is-ancestor` passes; it is the load-bearing check |
| Four states, one symptom | "Can't merge" | Read `mergeStateStatus`; `BEHIND` != `DIRTY`, and `BLOCKED` usually means wait |
| Armed auto-merge | Queued, green, and stalled forever | Auto-merge waits for checks, never updates a `BEHIND` branch |
| Two-armed watcher | "Still running" until timeout | Poll merged / failing / **went stale** |
| No pending checks | "Everything settled" right after a push | Assert on the expected leg **count**, not on absent pending legs |
| `--ours` on an append-only file | Well-formed file, clean status, green CI | Union both sides, then verify surviving entries by name |
| Unanchored renumber | `cp1252` became `cp1316` | Anchor the pattern; re-verify **after** conflict resolution |
| Rebasing a one-block stack | Clean tree, one heading, half the prose | One `git merge`; grep for a string only the latest revision has |
| Blob comparison | Five files identical -- twenty minutes ago | `git merge-tree --write-tree` or a trial merge; `update-branch` cannot resolve conflicts |
| Two true numbers | Both figures verified individually | Confirm they describe the same commit at the same moment |
| Ahead of the trunk | "This branch is not merged" | Under squash-merge, reachability lies in both directions |
