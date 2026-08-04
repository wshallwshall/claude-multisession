# Landing work: PRs and merges

Several sessions working in parallel produce several branches, and all of them have to land in one
trunk. That last mile is where parallelism stops being free: the trunk moves while you are looking at
it, two branches append to the same file, a queued pull request quietly stops progressing, and every
one of those failures looks like something else.

This document is the merge-time counterpart to [WORKTREES.md](WORKTREES.md) (creating and living in
worktrees) and [PRUNING.md](PRUNING.md) (cleaning them up afterwards). Everything here was learned by
getting it wrong; where a number is quoted it was measured on the repo this tooling was developed in,
and it is stated as evidence for the rule, not as a universal constant.

Two assumptions run through the whole document, because they are what make the traps traps:

- **The trunk squash-merges.** A branch's own commits never become ancestors of the trunk, so every
  reachability-based test -- `rev-list`, `merge-base --is-ancestor`, `git cherry` -- answers "not
  merged" forever, for work that landed weeks ago.
- **Somebody else lands something while you are working.** Not hypothetically. Measured on the repo
  this tooling was developed in, the trunk moved seven times during the life of one pair of pull
  requests.

## What "trunk" means to these scripts

Every script resolves the trunk through one function, `Get-CcxTrunk` in
[`scripts/coord/_common.ps1`](../scripts/coord/_common.ps1), in this order:

| Order | Source | Notes |
|---|---|---|
| 1 | `$env:CCX_TRUNK` | Per-session override; wins over everything. |
| 2 | `trunk` in [`ccx.config.json`](../ccx.config.json) | Unless it is the literal `auto`. |
| 3 | `git symbolic-ref --short refs/remotes/origin/HEAD` | What the remote says its default branch is -- the only source that survives a rename. |
| 4 | First of `origin/main`, `origin/master`, `main`, `master` that resolves | Last resort. |

It returns a **remote-tracking** ref where it can. A local `main` can lag its upstream silently, and
branching new work off a stale local trunk is the most common way parallel sessions end up building
on old code. If step 3 fails -- a clone made before the remote head was recorded -- fix it once with
`git remote set-head origin -a` rather than hardcoding a branch name in a script.

The examples below spell the trunk `origin/main`. Substitute yours.

## Check the merge base before anything else

**Run this first, before reading a diff, before opening the PR, before deciding a branch is fine.**

```bash
git fetch origin
git merge-base --is-ancestor origin/main HEAD   # exit 0 = your branch contains the trunk tip
```

In PowerShell the exit code is `$LASTEXITCODE`, not `$?` -- `$?` is a boolean about the last statement
and will happily report success on a check that answered "no".

### The trap: a branch cut from a pre-squash commit

A branch was created from a commit that had been pushed to a pull request -- a commit made shortly
after that same PR had already squash-merged. The three-dot diff and the forge's "Files changed" tab
both reported roughly 13 files, 2,967 insertions and 19 deletions: an accurate account of what the
branch adds, with no indication whatever that five of those files would conflict. The merge base was
eleven squash-merged pull requests behind the trunk.

The mechanism is the squash. The branch's content reached the trunk as one *new* commit, so the
branch's own commits are still not ancestors of the trunk. Branch again from one of them and you
inherit a merge base from before the squash. `git diff origin/main...HEAD` *resolves the merge base*
before diffing -- and the merge base is exactly the thing that is stale, so the diff cannot report the
problem.

The confirmation, once `--is-ancestor` has failed, is the two-dot form:

```bash
git diff --stat origin/main HEAD      # two-dot: what still DIFFERS from the trunk
git diff --stat origin/main...HEAD    # three-dot: what the BRANCH AUTHORED
```

A non-zero **deletion** count from the two-dot form, on a branch that only adds files, is the signal:
it means the trunk holds content your branch would remove.

**Fix by merging, not rebasing.** `git merge origin/main` into the branch. The trunk's side of the
squashed files is authoritative, and a rebase would replay your commits onto the trunk while asking
you to re-resolve the squash seam once per commit (see [merge over rebase](#prefer-merge-over-rebase-when-every-commit-touches-one-block)).

### The staleness check that agrees with itself

The tempting test is "compare the two-dot and three-dot diffs; if they match, the branch is fine."
It is worthless, and worse than worthless because it feels like a measurement.

Once `--is-ancestor` passes, the merge base **is** `origin/main` -- so the two forms are computing the
same thing and *cannot* disagree. Measured minutes apart on one branch: while `--is-ancestor` was
failing, two-dot reported 2 files / 52 insertions / 22 deletions against three-dot's 1 file / 50
insertions with the deletions invisible; after the merge, the two forms were identical. The
comparison only carries information in the window where `--is-ancestor` already told you there is a
problem.

**Rule:** `--is-ancestor` is the load-bearing check; the diff comparison only confirms it. A test that
agrees with itself in the healthy case is how a trap survives being checked for.

## Reading "can't merge": four states, three different fixes

A PR that was green ten minutes ago stops being mergeable and the reflex is to rebase and force-push.
That reflex is right for exactly one of the four states and destructive in another.

Read the state before acting:

```bash
gh pr view <N> --json state,mergeable,mergeStateStatus,statusCheckRollup
```

| State | What it actually is | Do | Do not |
|---|---|---|---|
| `BEHIND` | The branch does not contain the trunk tip. Mechanical; no conflict. | Merge the trunk in, or `gh pr update-branch <N>`. | -- |
| `DIRTY` | A real textual conflict. | Resolve by hand, deliberately, in a worktree. | Treat it as `BEHIND`. That means resolving conflicts in a hurry to make a force-push succeed. |
| `BLOCKED` | Required checks or reviews are not satisfied. Usually still running. | Count *actual failures* in `statusCheckRollup`. Zero failures plus pending legs means **wait**. | Rebase and force-push -- it cancels the running checks and restarts the clock. |
| `UNKNOWN` | The forge is still recomputing mergeability. | Re-read in a few seconds. | Anything else. |

`BEHIND` and `DIRTY` are the pair that get confused, and the wrong fix is the destructive one.
`BLOCKED` is the one that looks most actionable and usually is not.

> **Limit.** `mergeStateStatus` is GitHub's field and `gh` is a GitHub client. On another forge the
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
> changes the behaviour is **unverified** -- no back-fill was ever observed, and the forge's own
> documentation does not connect the setting to this case. Do not repeat it as fact.

### A merge-watcher needs three arms, not two

A poller that checks "merged?" and "failing?" will report "still running" right up to its timeout
while nothing whatsoever is progressing. The outcome that happens most often is the third one: the
trunk moved and the branch went `BEHIND` again. That state produces neither a merge nor a failure, so
a two-armed watcher is *structurally* blind to it.

Poll for **merged / failing / went stale**, and act on the third:

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

### "Nothing pending" right after a push means "nothing has started"

Polling the checks immediately after a push showed no pending legs, which read as "everything
settled". The new run's legs did not exist yet. **Absence of pending is indistinguishable from
absence of checks.**

**Rule:** assert on the **count of legs you expect**, not on the absence of pending ones. Take the
expected set from wherever your required checks are actually declared, and read it at the time --
never from memory, because that list changes.

This is the same failure shape as taking `--ours` on a conflict, below: the instrument was accurate
about what it looked at and silent about what it did not look at.

## Resolving conflicts without losing work

### Never take a side wholesale on an append-only file

A changelog, a backlog, a decision index -- one large file that every session appends to. Those files
conflict more than anything else in the repo, and they are the ones where `--ours` and `--theirs` are
most tempting.

```bash
git checkout --ours docs/CHANGELOG.md    # <-- this is the one that loses work silently
```

Both sides of an append-only conflict produce a **well-formed file**. There are no conflict markers,
`git status` is clean, the structure check passes, the linter passes, CI is green. Nothing anywhere
reports that half the content is gone.

A real instance: two PRs each added a `### Changed` block. The union was the correct answer. `--ours`
would have dropped two already-published breaking-change notices; `--theirs` would have dropped the
incoming one. Either resolution would have merged green.

**Rule:** re-apply *intent*. Keep every entry from both sides, then verify by name that the specific
things you expect to survive are present:

```bash
git grep -n "one distinctive phrase from THEIR entry"
git grep -n "one distinctive phrase from YOUR entry"
```

### Anchor a find-and-replace, and re-verify it after the conflict is resolved

Renumbering an item from `1252` to `1316` across a changelog turned `cp1252` into `cp1316`, in a
file nobody re-reads.

Two things went wrong and both generalise. The replacement was a **bare number**, so it matched
inside unrelated tokens. And it was re-run during **conflict fixup** -- which is exactly when a sweep
gets repeated carelessly, on a file whose content just changed underneath it.

**Rule:** scope replacements to anchored forms (`item #1252`, `## 1252.`, `^1252\|`), never the bare
number -- and re-verify the sweep **after** resolving the conflict, not only after the original edit.

### Prefer merge over rebase when every commit touches one block

Rebasing a stack whose commits all append to the same point in the same file re-raises the identical
conflict once per commit. Resolving it mid-stack -- against an intermediate revision of the text --
kept an **earlier draft** of the block.

That result has no conflict markers, leaves `git status` clean, and passes a structural check: an
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

**Rule:** use `git merge-tree`, or an actual trial merge in a throwaway worktree -- the two commands
that answer the question you asked:

```powershell
# A real trial merge, isolated, disposable.
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name mergetrial -Base my-branch
# ...in the new worktree:  git merge origin/main
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name mergetrial -DeleteBranch
```

And do not expect `gh pr update-branch` to rescue a conflicting merge: it updates by merging the base
into the PR branch **server-side** and accepts no conflict resolution.

Before you start resolving, it is also worth asking who else is in those files right now:

```powershell
pwsh -NoProfile -File scripts/coord/overlap.ps1 -File path/to/file.md
```

That reports peer worktrees whose **committed-and-unlanded** or **uncommitted** work touches the same
path -- the intersection of the two-dot and three-dot file sets, so a branch that has already landed
stops claiming its files. See [COORDINATION.md](COORDINATION.md).

## Writing up the result: two true numbers can make a false sentence

An earlier revision of this very document paired a **post-merge** three-dot reading with a
**pre-merge** two-dot reading and presented them as one comparison -- so a diff that never proposed a
revert was described as proposing one. Every published number was real. Only the **join** between
them was false, and the join carried the whole argument.

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
defined by making the answer no. So **being ahead of the trunk is not evidence of unmerged work**,
and [`scripts/worktree/prune-merged.ps1`](../scripts/worktree/prune-merged.ps1) carries three merge
signals instead of one: nothing beyond the trunk, *or* a merged PR whose head is this exact tip, *or*
the branch's own upstream ref is gone. The converse is worse and is the one that destroyed an
occupied worktree: **zero commits beyond the trunk does not mean merged either** -- a branch created
seconds ago looks exactly like that. Merge state is never sufficient on its own; see
[PRUNING.md](PRUNING.md).

```powershell
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1            # dry run, prints the decision table
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply     # act on a table it re-derives now
```

For a single finished worktree, [`remove.ps1`](../scripts/worktree/remove.ps1) is the manual path. Two
of its behaviours matter at merge time:

- It **references the tip before removing anything**, and with `-DeleteBranch` writes it to
  `refs/<prefix>/removed/<name>` first. A commit in no ref is in no reflog either, and nothing in the
  interface admits it ever existed.
- It uses `git branch -d`, **never** `-D`. Git refusing to delete an unmerged branch is a *signal*
  that the branch holds commits no other ref has. If the local trunk merely lags the remote, fetch and
  retry; do not force past the refusal as a tidying step.

Work claims taken with [`claim.ps1`](../scripts/coord/claim.ps1) do not expire and do not release
themselves when a PR merges. Release yours when the work lands:

```powershell
pwsh -NoProfile -File scripts/coord/claim.ps1 -Release <key>
pwsh -NoProfile -File scripts/coord/claim.ps1 -List
```

The pruning tool releases claims held by a worktree only once that worktree is proven **gone and
deregistered** -- evidence, never a timer.

## What this tooling does and does not do for you

Stated plainly, because at merge time an assumption that is wrong is expensive:

- **PowerShell 7, Windows-first.** The scripts are PowerShell 7 (`#Requires -Version 7.3`); the git
  commands in this document are portable, the scripts are not yet.
- **GitHub is assumed where `gh` appears.** The PR-state table, the watcher loop, and the merged-PR
  signal in the pruning tool all call `gh`. The pruning tool degrades explicitly -- `-SkipGh`, and a
  failed probe is reported as a failed probe rather than as "not merged".
- **The push guard is a guardrail, not a security boundary.**
  [`scripts/hooks/push_guard.py`](../scripts/hooks/push_guard.py) refuses a direct push to anything in
  `protectedRefs` (default `main` and `master`) and fails fast with an explanation, before the round
  trip. `git push --no-verify` skips it, and it is installed per clone. Configure server-side
  protection as well; this is only the part that tells you before you wait. The deliberate escape
  hatch is `CCX_ALLOW_DIRECT_PUSH=1`, chosen to be distinct from `--no-verify` so it is greppable in
  shell history.
- **An installed guard and a working guard are different claims.** These hooks are copied into place;
  a hook whose helper files were not copied with it can refuse *every* push for a reason unrelated to
  what it checks, and a hook that was never installed is a source file. Prove it by receipt before you
  rely on it:

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
| Blob comparison | Five files identical -- twenty minutes ago | `git merge-tree` or a trial merge; `update-branch` cannot resolve conflicts |
| Two true numbers | Both figures verified individually | Confirm they describe the same commit at the same moment |
| Ahead of the trunk | "This branch is not merged" | Under squash-merge, reachability lies in both directions |
