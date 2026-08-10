# Pruning worktrees

Two scripts remove a worktree:

| Script | Who runs it | Posture |
|---|---|---|
| `scripts/worktree/prune-merged.ps1` | unattended sweep over every sibling worktree | dry run by default; `-Apply` acts |
| `scripts/worktree/remove.ps1` | a human, one named worktree at a time | acts immediately, refuses on uncommitted tracked changes |

`prune-merged.ps1` is the most destructive tool in this repository. It has destroyed a live session's
worktree once, and every rule below is a consequence of that or of a near miss. Read the first two
sections before you run either script.

## First: a removal can delete commits into nothing

Removing a worktree can take its branch ref with it, and **a commit that is in no ref is also in no
reflog**. There is then no `git reflog` entry to recover it from, no branch name, and nothing in any
interface that admits the work ever existed. This is the only failure in the whole system that is
genuinely unrecoverable through git.

So `remove.ps1` resolves and prints the tip *before* anything destructive happens, and with
`-DeleteBranch` it writes a keep-ref first:

```powershell
# remove.ps1 -DeleteBranch, before the branch goes:
git -C <primary> update-ref refs/<prefix>/removed/<name> <tip>

# later, to see what is being kept and to get one back:
git for-each-ref refs/<prefix>/removed/
git branch <name> refs/<prefix>/removed/<name>
git update-ref -d refs/<prefix>/removed/<name>
```

The keep-ref costs nothing and is the difference between "recoverable" and "gone at the next gc".

### Under squash-merge, the obvious merge tests lie

A squash merge replays a branch as **one new commit with a new hash and no parent link** back to the
branch. After the work has landed on the trunk:

| Test | What it answers after a squash merge | Why |
|---|---|---|
| `git rev-list --count <trunk>..<branch>` | still counts every original commit -> "not merged" | the originals are unreachable from the trunk |
| `git merge-base --is-ancestor <branch> <trunk>` | false -> "not merged" | no parent link was created |
| `git cherry <trunk> <branch>` | marks commits `+` (unmerged) | patch-ids stop matching the moment anything was rebased, amended, or conflict-resolved |

All three ask one question -- "is this commit reachable from the trunk?" -- and squash-merge is defined
by making the answer no. **Ahead-of-main is not evidence of unmerged work.** That is why `Test-Merged`
in `prune-merged.ps1` carries three signals, not one:

1. nothing beyond the trunk (`Test-ContainedInMain`),
2. a merged PR **whose head is this exact tip** -- matching by branch *name* alone force-deletes the
   commits a branch gained after its PR merged, or the commits of a name reused from an earlier life,
3. the branch's **own** upstream is gone (the squash-merge + auto-delete shape).

Signal 3 is scoped deliberately: a worktree created with `-Base origin/<parent>` points at the
*parent's* upstream, so a merged parent makes a never-pushed child report `[gone]`. And `gone` means
*the remote ref is absent* -- a closed PR and a `push --delete` produce it too. It is a reason to remove
the **worktree**, never a license to delete the **branch**.

### The converse trap is the one that destroyed a worktree

Signal 1 answering **zero** does not mean "merged" either. A branch created seconds ago has no commits
beyond the trunk, so it is an ancestor of the trunk and perfectly clean -- which is exactly the state a
session that just started work is in. `Test-BranchNeverUsed` separates the two by reading the reflog: a
branch with exactly one entry (`branch: Created from ...`) never advanced, and nothing was merged *from*
it.

## The rule: merged AND clean AND NOT occupied

```text
prune = merged AND clean AND NOT occupied
```

"Merged and clean" is a description of the **branch**. It says nothing about whether anyone is standing
in the **directory**. The bias is fixed and not negotiable:

> A false SKIP is a minor annoyance. A false PRUNE destroys a session.

Every check that cannot reach a confident answer SKIPs. Nothing is ever traded for tidiness.

**Clean** is stricter here than you may expect, and `Test-WorktreeClean` fails closed:

- Uncommitted tracked changes block, and so do **untracked files**. They are the one loss class with no
  recovery through git at all: not in the index, not in a stash, not in the reflog.
- `--force` suppresses git's own refusal on untracked and modified files. That is the exact refusal that
  would have prevented the incident, so the reaper only ever reaches it after establishing cleanliness
  itself. It also deletes **ignored** files (a dependency tree, a local database, a generated fixture
  set), which `git status --porcelain` never shows here: unrecoverable too, merely regenerable. It does
  *not* override a git lock -- that needs `-f -f`, which neither script passes.
- A `git status` that exits non-zero, or a directory that has vanished, is **not clean**. Those states
  used to be indistinguishable from "no changes" and pointed straight at destruction.

The same routine is used by the decision pass and by the pre-removal re-check, and it returns *reasons*,
not a boolean. Collapsing "the directory vanished", "status exited 128", "an untracked file appeared"
and "somebody edited a tracked file" into one string discards the distinction at the exact moment an
operator most needs it.

## Occupancy is a veto, never a permission

There is no heartbeat anywhere in this system, so **nothing here can prove a session is gone**. A
`DEAD` / `STALE` / absent verdict is the *absence of a veto*, not a permission. The states that veto
(`scripts/coord/occupancy.ps1`, `$OccupancyVetoStates`) are:

| State | Meaning | Vetoes? |
|---|---|---|
| `LIVE` | pid resolves and its start time is consistent | yes |
| `UNVERIFIED` | pid resolves; the fence could not be evaluated | yes |
| `UNREADABLE` | the record cannot be fenced at all (no pid, or a non-numeric one) | yes |
| `STALE` | pid resolves but belongs to a different process | no -- and not permission either |
| `DEAD` | no such pid | no -- and not permission either |

Two independent signals are required, and **either one vetoes**:

**Signal 1 -- the liveness fence.** `Get-WorktreeOccupancy` reads Claude Code's per-session records,
maps each session's recorded `cwd` onto a worktree, and fences it on pid plus process start time. A
session in a **nested** worktree vetoes its ancestor too (`Get-WorktreeOccupants -IncludeNested`),
because removing the parent takes the nested checkout with it.

**Signal 2 -- recent activity.** The newest mtime of the worktree's **private git metadata** (`index`,
`HEAD`, `ORIG_HEAD`, `FETCH_HEAD`, `COMMIT_EDITMSG`, `MERGE_MSG`, `logs/HEAD`), compared against
`-IdleHours` (default 36). Deliberately not the working files: a dependency install or a test run churns
those, so their mtimes would veto everything forever and the veto would stop meaning anything.

Signal 2 is not a nicety. Signal 1 only sees where a session was **launched**. Measured on the repo this
tooling was developed in, over 30 days, about **29% of Edit/Write calls came from a session sitting in
the primary and landed in a sibling worktree** by absolute path. On one audit of that same repo, signal
1 vetoed **none** of the sibling worktrees -- including one a session was demonstrably building in.
Signal 2 was the only thing standing between that session and this script.

Because the two signals cover different populations, the run prints **how many candidates each one
actually vetoed**, not just that it ran. "The fence ran" must never be allowed to imply "the fence
covered it".

## An empty roster and an unreadable roster are different outcomes

They produce identical bytes: no rows. So availability is asserted explicitly rather than inferred from
emptiness. `Get-WorktreeOccupancy` returns a receipt -- `RootsExamined`, `RecordsExamined`,
`RecordsUnplaceable`, `UnplaceableFiles` -- and sets `Available` only when **all** of these hold:

- at least one config root holding a session registry,
- at least one **readable** record in it,
- **no** record that could not be *placed*.

Unplaceable has two shapes: a file that will not parse, and a record that parses but carries no `cwd`.
Both used to be dropped by a silent `continue`, so they appeared in no count at all. Neither can be
attributed to -- or cleared from -- any particular worktree: it could be a session sitting in the very
tree you are about to delete. **A file caught half-written is exactly what a session that launched one
second ago looks like.**

When the fence is unavailable, every candidate becomes SKIP and the run exits non-zero. There is
deliberately **no override flag**. Fix the fence; do not bypass it.

`bin/ccx-doctor.ps1` prints the same receipt on demand -- config roots, records read, records
unplaceable, worktrees enumerated -- and says in as many words that an empty roster there is *not*
"nobody is live".

## "Sibling" is not a prefix match

The candidate set used to be every registered worktree whose path starts with `<primary>-`. That
silently includes `<primary>-work/.claude/worktrees/x`: a Claude Code-managed nested worktree, which is
precisely where a live session gets relocated to. Nested trees under the *primary* escaped only by the
accident that `<primary>/` is not `<primary>-` -- and that accident was the only case anyone had tested,
so the tested case was the case that worked.

Candidate selection is now two stages:

1. a **deliberately over-inclusive** sweep on the literal prefix (`StartsWith`, `Ordinal` -- not `-like`,
   whose `[ ]` is a character class, so a repo under a bracketed directory would match nothing and every
   "it was not pruned" assertion would pass vacuously);
2. structural exclusions, each **printed as a non-candidate with its reason** rather than silently
   filtered out. A tool that silently filters cannot be checked.

Exclusions, in order: nested inside another registered worktree (`Get-ContainingWorktrees`);
harness-managed by path shape (`Test-CcxHarnessWorktreePath` -- any `.claude/worktrees/` segment,
unconditionally, whoever currently owns it); not structurally a sibling
(`Test-CcxSiblingWorktreePath` -- **same parent directory** and a leaf of exactly
`<primary-leaf>-<something>`); detached or bare.

`-Name` cannot reach any of them either. A worktree that also *contains* a registered worktree is never
removed even when unoccupied, because `--force` on the parent deletes the nested checkout and leaves it
registered with no directory.

Both layouts coexist by design: this repo's scripts create **siblings**; Claude Code's own worktree
support creates **nested** ones. Only the sibling population has scripted teardown. Note the trap in the
other direction too: a nested checkout is gitignored inside its parent, so the parent reads perfectly
clean.

## Print your blind spots, and name everything that narrows the fence

A fence believed to be wider than it is, is worse than no fence -- because it is trusted. Every run
prints what it cannot see, in the receipt as well as on the terminal:

- a session writing into a worktree **by absolute path from elsewhere** (the 29% above);
- a `cwd` recorded as a UNC (`\\host\C$\...`) or 8.3 short path -- the match is a normalized string
  compare and neither spelling normalizes to the worktree's own path;
- a session that never registered;
- a session that only edits files and **runs no git command** -- it touches none of the seven metadata
  files, so signal 2 is blind to it as well.

It *does* see editor-hosted sessions as well as terminal ones: the file registry carries every surface
and the match is purely path-based.

Separately, anything that **narrows** a signal is declared in red as REDUCED ASSURANCE, on the run and
in the JSON receipt:

- `-IdleHours 0`;
- an `-IdleHours` below the floor;
- an explicit `-ConfigRoot`, which *replaces* the machine's real registry;
- a **failed fetch**, after which merge decisions rest on stale refs;
- a merged-PR probe that errored;
- every `-Name`-confirmed worktree.

### A plausible threshold can disarm a signal completely

`-IdleHours 0.5`, typed for "half an hour", reads as a tightening. It is not: on the repo this tooling
was developed in, an **occupied** worktree was measured at **10.4 hours** idle by git-metadata mtime, so
any window under the empirical floor releases trees that measurement says are in use. Two guards:

- `$IDLE_FLOOR_HOURS = 12` -- **deliberately not a parameter**. A floor an operator can lower is not a
  floor, it is a second copy of `-IdleHours` with a reassuring name. Change it in a commit, with the
  measurement that justifies the new value.
- a negative `-IdleHours` puts the cut-off in the future, so the veto can never fire while still
  appearing to be set. The run **refuses** (exit 2) rather than running with a disarmed veto.

Only the literal `0` used to be declared. Everything between 0 and the floor disarmed signal 2 just as
effectively and printed nothing.

`-Name` deserves its own line. It is `-IdleHours 0` scoped to one tree, and since signal 1 has been
measured vetoing none of the real siblings on a busy repo, `-Apply -Name <slug>` can leave a candidate
with **no working occupancy signal at all**. It stays available because there are legitimate uses, but
it is never silent.

## A wrong-cwd run must refuse loudly, never green no-op

Sibling worktrees are named after the **primary**, so run from a linked worktree the candidate set is
empty for the wrong reason. The old script printed a green "nothing to consider", which reads exactly
like "everything is tidy". Three refusals exist for this class:

- not the primary checkout -> exit 2, printing both paths.
- the trunk cannot be resolved -> exit 2. Guessing `origin/main` in a repo whose trunk is something else
  answers "not merged" for every candidate, which looks like a safe, tidy, green run and is really a
  blind one.
- `-Name` matched no prunable sibling -> exit 2 (or 1 if something was already removed), because what
  the operator asked for did not happen.

## Re-check immediately before each destructive step

The decision table is built up front, but `-Apply` **re-evaluates everything from scratch in the same
run and acts on that table**, never on a table you read a minute ago. Then, immediately before *each
individual removal*, it re-reads:

1. fence availability -- a fence that **dies mid-run** stops the rest of the run;
2. occupants, including nested;
3. newly appeared nested worktrees;
4. signal 2 (activity), which was once the one signal missing from this block;
5. cleanliness.

The window is real: a merged-PR probe costs roughly half a second per candidate (measured on the repo
this tooling was developed in), plus the time taken by every removal before this one. A session can
arrive inside it.

One subtlety worth copying: when the re-check vetoes, the occupants it found are **written back onto the
decision**. Without that, the one candidate the fence actually saved still reports `Occupants: []`.
The "vetoed by signal 1" figure then under-reports the save to zero -- the number that exists
precisely so "the fence ran" cannot imply "the fence covered it".

## Count outcomes, not intentions

A destructive tool that over-reports what it destroyed is actively misleading. The summary counts what
**happened**, not what was planned:

- a removal counts as `removed` only once the directory is **verified gone** and **deregistered**. Exit
  0 is git's claim; the directory being gone is the fact.
- `orphaned` is a **subset** of `failed`, and `failedNonOrphan` is spelled out so a consumer cannot
  reach a wrong total by adding all four numbers.
- `BranchOutcome` starts at `not attempted`, never `kept` -- otherwise every skipped candidate claims a
  decision nobody made (the JSON once said 7 branches were kept on a run whose summary said 0).
- `Merged` is `$null`, not `$false`, when the test never ran: a machine consumer reads `false` as
  "checked, and it is not merged", which is a different claim from "never asked".
- the final line is coloured by the **exit code**, not by the failure count. A run where the fence
  died and every removal was refused has `failed 0`, and used to print that in green next to exit 2.

### Exit codes

Highest severity wins.

| Code | Name | Meaning |
|---|---|---|
| 0 | OK | nothing wrong |
| 1 | FAILED | something was attempted and failed **without destroying anything** |
| 2 | REFUSED | nothing was attempted, because safety could not be established (wrong cwd, unresolvable trunk, unavailable fence, a `-Name` that matched nothing) |
| 3 | ORPHANED | a directory is broken on disk **right now** (this run, or an earlier one) |

3 outranks 2 because damage on disk outranks a refusal to act.

## A failed removal is worse than no removal

`git worktree remove --force` deletes the `.git` pointer and **deregisters** the worktree *before* it
walks the tree, and it deregisters even when that walk fails. A partial failure therefore leaves a
directory that is neither a worktree nor gone -- and the session standing in it sees `fatal: not a git
repository` from every subsequent git command.

So a failure is diagnosed on the spot, reporting which of the three survived: the **directory**, its
**.git pointer**, and its **registration**. Recovery, printed by the tool:

```powershell
# 1. close anything holding files open in it (an editor, a shell sitting in it)
# 2. if the .git file survived, try this FIRST -- the registration may be re-creatable in place:
git -C <primary> worktree repair <path>
# 3. otherwise move it aside and re-add it:
Move-Item <path> <path>.salvage
git -C <primary> worktree add <path> <branch>
# 4. copy anything you need out of <path>.salvage
#    (stashes are safe -- they live in the shared .git)
```

`worktree repair` cannot fix the case where the `.git` file is gone (it is the file repair needs), and
`worktree add --force` refuses because the directory already exists. Hence the move-aside recipe.

### Never run `git worktree prune`

It looks like the obvious tidy-up after a failed removal. It is not, and this repository never runs it --
not in `prune-merged.ps1`, not in `remove.ps1`.

`git worktree prune` deregisters **any** worktree whose directory is momentarily missing. That covers
one on a disconnected network drive, an unmounted volume, a path a live session is about to come back
to, and the Claude Code-managed nested worktrees this tooling must never touch. It would finish
exactly the destruction a half-failed removal started. `git worktree remove` already deregisters the one you
removed; a blanket prune is a second, much wider action wearing the costume of a cleanup step.
Deregister specific worktrees deliberately, never by sweep.

### An orphan outlives the run that made it

Once git has deregistered a worktree it is no longer in `git worktree list`, so it drops out of the
candidate set. The **next** run then printed a green all-clear over a directory this script had broken,
with the recovery recipe surviving only in the first run's scrollback.

Orphans are therefore remembered in the shared state root
(`<git-common-dir>/<prefix>-coord/prune-merged-orphans.json`) and re-reported, with the recipe, on every
later run until the directory is gone or re-registered. Two independent detectors, because either can be
true alone:

- the **ledger** written at the moment of the failure;
- a **ledger-free** scan: an unregistered sibling directory still carrying a `.git` **file** that points
  into this repo's worktree admin area. Deliberately not "any unregistered `<primary>-*` directory" -- an
  unrelated folder sharing the prefix is not an orphan, and a destructive tool that cries wolf gets
  ignored. (A relative `gitdir:` is resolved against the directory the `.git` file lives in, not against
  this process's cwd; resolving it wrongly would report an orphan as fine.)

The ledger is written only under `-Apply`. A dry run reports the same state without touching anything,
and a repaired or fully deleted entry clears itself.

A **ghost stub** is a different animal and is not the reaper's job: a directory left by a half-failed
per-session auto-worktree, with **no** `.git` pointer and no entry in `git worktree list` (see
`scripts/worktree/worktree-selfheal.ps1` and `anthropics/claude-code#76590`). The orphan detector
requires a `.git` file pointing into this repo, so it will not claim one.

## Deleting the branch: `-d` refusing is a signal

`git branch -d` refuses a branch merged only into the **remote** trunk whenever the local trunk lags --
which, in a multi-worktree repo, it usually does. So `-D` had become the routine path and git's last
protection against destroying commits was being overridden every single time, for a reason unrelated to
the branch's actual state.

`Remove-BranchSafely` now does:

1. `git branch -d` first;
2. if that refuses, **re-verify at that moment** that `<trunk>..<branch>` is empty;
3. `-D` only then, reporting "re-verified: 0 commits beyond `<trunk>`, so nothing was lost";
4. otherwise **keep the branch** and say why, with the command to delete it by hand.

A stale ref costs nothing; a destroyed commit costs a session. The branch is also never touched after an
**unverified** removal.

`remove.ps1` takes the stricter line. It only ever runs `-d`, and when git refuses it leaves the branch
in place, prints the tip, and tells you the `-D` command to run deliberately rather than as a side
effect of tidying up a directory.

## Claims stranded by a removal

Coordination state lives beside the **shared** object store (`<git-common-dir>/<prefix>-coord/`), which
is exactly why it is correct -- identical across worktrees, isolated per clone, uncommittable -- and why
**state outlives the worktree**. Removing a worktree therefore strands the work claims it took
(`scripts/coord/claim.ps1`), and `-Take` hard-blocks on any claim file that exists, so the key becomes
unclaimable by every future session until someone runs `-Release <key> -Force` by hand.

The reaper clears them, under rules worth copying:

- **on evidence, never on a timer.** The release runs only from the branch that has already proven the
  directory is gone **and** deregistered, so there is no session left in there to collide with. A claim
  whose holder is merely quiet is never touched, and an auto-expiring claim would silently re-open the
  race it exists to prevent.
- **full normalized path equality only** -- no leaf name, no prefix, no `StartsWith`. Releasing a
  *living* worktree's claim hands its key to another session and invites the duplicate build the
  registry exists to stop. One normalizer on both sides, or the match silently misses and the claim is
  quietly left stranded.
- a dry run releases nothing.
- an **unreadable** claim file belongs to the registry, not to any worktree -- by definition we could not
  read whose it is. It is surveyed **once, at run level** (so it is visible to a dry run and cannot be
  counted once per removal), left in place, listed by filename, and it moves the exit code.
- `claims.scanned: false` is emitted when there was no claims directory to read. **Never looked is not
  clean**: an empty `unreadable` list means something only when you can prove you looked.

## The manual path, and a deliberate asymmetry

`remove.ps1` refuses on uncommitted **tracked** changes unless `-Force`, but lets **untracked** entries
through -- a per-checkout environment directory, build output, a scratch database. `prune-merged.ps1`
treats untracked files as a **blocker**.

That difference is deliberate. A human running `remove.ps1` has just looked at the directory and can say
those files are disposable; an unattended reaper cannot. The stricter test belongs to the tool that runs
without a human. Do not "fix" the difference by making them agree.

`remove.ps1` also refuses to remove the worktree you are standing in, with a message about what *you*
did rather than git's message about what git could not do.

## Reference

```powershell
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1                   # dry run, no action
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Fetch            # dry run, refresh refs first
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply            # remove the ones that pass
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply -Name auth # confirm past the activity veto
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply -SkipFetch # offline / faster
pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Json             # machine-readable receipt

pwsh -NoProfile -File scripts/coord/presence.ps1                          # who is here, read-only
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name auth -DeleteBranch
```

| Flag | Effect | Narrows the fence? |
|---|---|---|
| `-Apply` | actually remove; re-evaluates the whole table first | -- |
| `-Fetch` | fetch during a **dry run** too (off by default: `fetch --prune` rewrites remote-tracking refs, which is what turns an upstream into `[gone]`, so a "safe preview" should not enlarge the next apply's blast radius) | -- |
| `-SkipFetch` | skip the fetch even under `-Apply` | merge decisions use stale refs |
| `-Name <slug>` | restrict to these worktrees **and confirm them past the activity veto**. Never overrides signal 1, a nested worktree, or a git lock | yes, loudly |
| `-SkipGh` | do not ask about merged PRs | drops merge signal 2 |
| `-Json` | emit the decision objects, the fence receipt and the counts | -- |
| `-RepoRoot <path>` | repo to operate on -- a **hint**, validated against the primary; the run refuses if they differ | -- |
| `-ConfigRoot <path>` | config roots for the fence. **Replaces** the real registry | yes |
| `-IdleHours <n>` | signal 2 window, default 36, floor 12, negative refused | yes below the floor |
| `-StartSkewMinutes <n>` | liveness fence tolerance for process start vs session registration | -- |
| `-MainRef <ref>` | the ref work must be merged into; defaults to the configured trunk | -- |

## Testing a destructive tool

Two rules, both learned the hard way:

**Assert the decision and the reason, not survival.** Tests that asserted only "the directory still
exists" passed against a build that had lost its primary safety fence -- the pre-action re-check caught
it, so the directory survived for entirely the wrong reason. Assert which decision was made *and* which
reason produced it, and carry a positive control in the same invocation wherever you can. (A refusal
test is the exception: it refuses the whole run by design.)

**Drive the re-check deterministically.** To prove that step 4 of the apply loop really re-reads, use a
shim whose probe performs the side effect -- a session arrives, the fence dies, metadata is touched --
*before* it answers. No threads, no sleeps.

## Limits, stated plainly

- **PowerShell 7, Windows-first.** These scripts are `#Requires -Version 7.3`. Path folding is
  case-insensitive only where the filesystem is (`$IsWindows -or $IsMacOS`), and the folded form is for
  comparison **only** -- never pass it to git or to the filesystem. A Linux CI run has already been bitten
  by that once.
- **The session record schema is a vendor contract.** The whole liveness fence rests on Claude Code's
  own per-session records (`<config-root>/sessions/<pid>.json`, carrying `pid` / `startedAt` /
  `sessionId` / `cwd`). It can change under you. When it does, the fence must become *unavailable* -- and
  therefore refuse -- rather than quietly empty.
- **`list_sessions` cannot see every session kind.** The Desktop app's session tooling enumerates
  sessions it spawned; an editor-extension session sharing the same config root is never entered into
  it. The file registry above is the only source that carries every surface, which is why the fence
  reads that and not the MCP tool.
- **There is no heartbeat.** Nothing here can prove a session is gone. That is not an implementation gap
  to be closed later; it is why occupancy may only ever veto.
- **Signal 1 has measurably low coverage of the population this tool prunes.** Treat signal 2, and the
  refusal to run without a fence, as load-bearing rather than as belt-and-braces.
- **Only the sibling layout has scripted teardown.** Nested worktrees under `.claude/worktrees/` are
  excluded unconditionally and are never removed by anything in this repository.
