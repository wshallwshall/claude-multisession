# Pruning worktrees

## TLDR/BLUF

**What this is.** How to delete a finished worktree without deleting a live session's work. Two
scripts do it: `prune-merged.ps1` sweeps every sibling unattended, and `remove.ps1` takes one name
at a time from a human.

**Why you should care.** A removal can delete commits into nothing, the one failure git cannot undo.
`prune-merged.ps1` is the most destructive tool here: it destroyed a live session's worktree once,
and every rule below came from that or a near miss. Not for you if you never create worktrees.

**How to use it.** Run `prune-merged.ps1` with no flags, from the primary checkout. It is a dry run,
and only `-Apply` removes anything. Read the first two sections before you type `-Apply`.

**Preview with `-Fetch`, or the preview is not the run.** Without it a dry run judges merge state
against the refs you already have, so `-Apply` can remove candidates the preview never showed. The
refresh is hardcoded to `origin`; a trunk on another remote is judged on stale refs either way.

---

Two scripts remove a worktree:

| Script | Who runs it | Posture |
|---|---|---|
| `scripts/worktree/prune-merged.ps1` | unattended sweep over every sibling worktree | dry run by default; `-Apply` acts. Consults the liveness fence |
| `scripts/worktree/remove.ps1` | a human, one named worktree at a time | acts immediately, refuses on uncommitted tracked changes. **Consults no fence at all** |

**`remove.ps1` has no occupancy check.** It refuses when you are standing inside the worktree, and it
refuses on uncommitted *tracked* changes without `-Force`. It never asks whether a live session is
sitting in that checkout. You are the fence.

It also removes with `git worktree remove --force` on every path, so untracked files in that worktree
-- a `.env`, a local database, build output -- are deleted, and git never had them to give back.

Read the next two sections before you run either script. Every rule on this page is the residue of a
removal that went wrong, or one that nearly did.

## First: A removal can delete commits into nothing

Removing a worktree can take its branch ref with it, and **a commit that is in no ref is also in no
reflog**. Nothing is left to recover it from: no reflog entry, no branch name, no interface that
admits the work existed. This is the only failure in the whole system that git cannot recover.

So `remove.ps1` resolves and prints the tip *before* anything destructive happens. With
`-DeleteBranch` it first writes a **keep-ref**: a spare pointer at the tip that outlives the branch.

**`-Name` is the worktree directory; `-DeleteBranch` deletes the branch that worktree had checked
out**, read from its `HEAD`. Those differ whenever the branch was namespaced. On a detached `HEAD` it
deletes nothing and warns. The script prints the branch and the tip before it acts -- read them.

**The goal.** Get back the commits of a branch `remove.ps1 -DeleteBranch` has already deleted.

**What to do.** The script writes the keep-ref for you. You read it back.

```powershell
# remove.ps1 -DeleteBranch, before the branch goes:
git -C <primary> update-ref refs/<prefix>/removed/<worktree-name> <tip>

# later, to see what is being kept and to get one back:
git for-each-ref refs/<prefix>/removed/
git branch <real-branch-name> refs/<prefix>/removed/<worktree-name>
git update-ref -d refs/<prefix>/removed/<worktree-name>
```

`<prefix>` is `ccx` unless you changed `prefix` in `ccx.config.json`.

**Those two names are not the same name.** The keep-ref is labelled with the worktree *directory*,
because that label is always ref-safe. The branch deleted is whatever that worktree had checked out,
and `new.ps1 -Name my-task -Branch feature/my-task` is a documented invocation.

So substituting the directory name into both slots hands you the right commits on a **differently
named branch**, with nothing saying so. `remove.ps1` prints the exact recovery command with the real
branch name -- use that line rather than retyping this one.

**What happens next.** `for-each-ref` lists every tip kept this way. The keep-ref costs nothing and
is the difference between "recoverable" and "gone at the next gc".

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

1. nothing beyond the trunk (`Test-ContainedInMain`);
2. a merged PR **whose head is this exact tip**. Matching by branch *name* alone force-deletes the
   commits a branch gained after its PR merged, or the commits of a name reused from an earlier life;
3. the branch's **own** upstream is gone (the squash-merge + auto-delete shape).

Signal 3 is scoped: `-Base origin/<parent>` points at the *parent's* upstream, so a merged parent
makes a never-pushed child report `[gone]`. `gone` means *the remote ref is absent* -- a closed PR
and a `push --delete` produce it too. Remove the **worktree**, never delete the **branch**.

### A two-dot diff answers a different question, and the answer looks identical

`git diff --name-only main branch` compares the two tips. Where the trunk has moved, every file the
trunk gained since the branch was cut shows up, and none of those is the branch's work.

Three dots compares against the **merge base**, which is the question you meant to ask: what did this
branch change?

Measured 2026-08-11, closing a stale branch: two dots reported **85 files**, three dots reported
**zero**, and the branch was tree-identical to its base. Nothing about "85" announces that the
question was wrong.

> **Rule.** Make three dots the default and justify two, rather than writing another caution. A
> caution competes with muscle memory and loses. A default is what muscle memory reaches for.

### The converse trap is the one that destroyed a worktree

Signal 1 answering **zero** is not "merged". A branch created seconds ago has no commits beyond the
trunk: the state of a session that just started. `Test-BranchNeverUsed` reads the reflog. A branch
with exactly one entry (`branch: Created from ...`) never advanced, and nothing merged *from* it.

## The rule: Merged AND clean AND NOT occupied

<!-- no-copy -->
```text
prune = merged AND clean AND NOT occupied
```

"Merged and clean" is a description of the **branch**. It says nothing about whether anyone is standing
in the **directory**. The bias is fixed and not negotiable:

> A false SKIP is a minor annoyance. A false PRUNE destroys a session.

Every check that cannot reach a confident answer SKIPs. Nothing is ever traded for tidiness.

**Clean** is stricter here than you may expect. `Test-WorktreeClean` fails closed: when it cannot
tell, it blocks the removal.

- Uncommitted tracked changes block, and so do **untracked files**. They are the one loss class with no
  recovery through git at all: not in the index, not in a stash, not in the reflog.
- **`--force` is not a safety net.** It suppresses git's refusal on untracked and modified files
  that would have prevented the incident, so the reaper proves cleanliness itself first. Its other
  edges:
  - it deletes **ignored** files, invisible to `git status --porcelain`: unrecoverable, merely
    regenerable;
  - it does *not* override a git lock. That needs `-f -f`, which neither script passes.
- A `git status` that exits non-zero, or a directory that has vanished, is **not clean**. Those states
  used to be indistinguishable from "no changes" and pointed straight at destruction.

One routine serves the decision pass and the pre-removal re-check, and it returns *reasons*, not a
boolean. Collapsing "the directory vanished", "status exited 128", "an untracked file appeared" and
"somebody edited a tracked file" into one string discards it when an operator most needs it.

## Occupancy is a veto, never a permission

**Occupancy** answers one question: is somebody working in this directory right now? There is no
heartbeat in this system, so it can veto a removal but can never authorize one. **Nothing here can
prove a session is gone.**

A `DEAD` / `STALE` / absent verdict is the *absence of a veto*, not a permission. These are the
states that veto (`scripts/coord/occupancy.ps1`, `$OccupancyVetoStates`):

| State | Meaning | Vetoes? |
|---|---|---|
| `LIVE` | pid resolves and its start time is consistent | yes |
| `UNVERIFIED` | pid resolves; the fence could not be evaluated | yes |
| `UNREADABLE` | the record cannot be fenced at all (no pid, or a non-numeric one) | yes |
| `STALE` | pid resolves but belongs to a different process | no -- and not permission either |
| `DEAD` | no such pid | no -- and not permission either |

Two independent signals are required, and **either one vetoes**:

**Signal 1 -- the liveness fence.** `Get-WorktreeOccupancy` maps each Claude Code session record's
`cwd` onto a worktree and fences it on pid plus process start time. A **nested** worktree's session
vetoes its ancestor (`Get-WorktreeOccupants -IncludeNested`): removing the ancestor deletes it.

**Signal 2 -- recent activity.** The worktree's newest **private git metadata** mtime (`index`,
`HEAD`, `ORIG_HEAD`, `FETCH_HEAD`, `COMMIT_EDITMSG`, `MERGE_MSG`, `logs/HEAD`) against `-IdleHours`
(default 36). Not the working files: a test run churns those, so their mtimes would veto everything.

Signal 1 only sees where a session was **launched**. Over 30 days on the repo this tooling was
developed in, **29% of Edit/Write calls by primary-seated sessions landed in a sibling worktree by
absolute path**. One audit: signal 1 vetoed **none** of the siblings, one demonstrably in use.

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

Unplaceable has two shapes: a file that will not parse, and one that parses with no `cwd`. Neither
can be pinned to a worktree or cleared from one: it could be a session in the tree you are about to
delete. **A file caught half-written looks exactly like a session that launched one second ago.**

When the fence is unavailable, every candidate becomes SKIP and the run exits non-zero. There is
deliberately **no override flag**. Fix the fence; do not bypass it.

`bin/ccx-doctor.ps1` prints the same receipt on demand: config roots, records read, records
unplaceable, worktrees enumerated. It says in as many words that an empty roster there is *not*
"nobody is live".

## "Sibling" is not a prefix match

The candidate set was every registered worktree starting with `<primary>-`. It silently included
`<primary>-work/.claude/worktrees/x`, where Claude Code relocates a live session. Nested trees under
the *primary* escaped only because `<primary>/` is not `<primary>-`: the one case anyone had tested.

Candidate selection is now two stages:

1. a **deliberately over-inclusive** sweep on the literal prefix: `StartsWith`, `Ordinal`, not
   `-like`. In `-like`, `[ ]` is a character class, so a repo under a bracketed directory would match
   nothing and every "it was not pruned" assertion would pass vacuously;
2. structural exclusions, each **printed as a non-candidate with its reason** rather than silently
   filtered out. A tool that silently filters cannot be checked.

The exclusions, in order:

- nested in another registered worktree (`Get-ContainingWorktrees`);
- harness-managed: `Test-CcxHarnessWorktreePath`, any `.claude/worktrees/` segment, unconditionally;
- not a structural sibling: `Test-CcxSiblingWorktreePath` wants the **same parent directory** and a
  leaf spelled exactly `<primary-leaf>-<something>`;
- detached or bare.

`-Name` cannot reach any of them either. A worktree that *contains* a registered worktree is never
removed, even when unoccupied. The reason: `--force` on the parent deletes the nested checkout and
leaves it registered with no directory.

Both layouts coexist by design: this repo's scripts create **siblings**; Claude Code's own worktree
support creates **nested** ones. Only siblings have scripted teardown. The trap in the other
direction: a nested checkout is gitignored inside its parent, so the parent reads perfectly clean.

## Print your blind spots, and name everything that narrows the fence

A fence believed to be wider than it is, is worse than no fence, because it is trusted. Every run
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

`-IdleHours 0.5`, typed for "half an hour", reads as a tightening. It is not. On the repo this
tooling was developed in, an **occupied** worktree measured **10.4 hours** idle by git-metadata
mtime. Any window under the empirical floor releases trees that measurement says are in use. Two
guards:

- `$IDLE_FLOOR_HOURS = 12` -- **deliberately not a parameter**. A floor an operator can lower is not a
  floor, it is a second copy of `-IdleHours` with a reassuring name. Change it in a commit, with the
  measurement that justifies the new value.
- a negative `-IdleHours` puts the cut-off in the future, so the veto can never fire while still
  appearing to be set. The run **refuses** (exit 2) rather than running with a disarmed veto.

Only the literal `0` used to be declared. Everything between 0 and the floor disarmed signal 2 just as
effectively and printed nothing.

`-Name` is `-IdleHours 0` scoped to one tree. Signal 1 has been measured vetoing none of the real
siblings on a busy repo, so `-Apply -Name <slug>` can leave a candidate with **no working occupancy
signal at all**. It stays available for legitimate uses, but it is never silent.

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

The decision table is built up front. `-Apply` then **re-evaluates everything from scratch in the
same run and acts on that table**, never on a table you read a minute ago.
Immediately before *each individual removal*, it re-reads:

1. fence availability -- a fence that **dies mid-run** stops the rest of the run;
2. occupants, including nested;
3. newly appeared nested worktrees;
4. signal 2 (activity), which was once the one signal missing from this block;
5. cleanliness.

The window is real. A merged-PR probe costs roughly half a second per candidate, measured on the repo
this tooling was developed in. Add the time taken by every removal before this one. A session can
arrive inside that window.

**Once per candidate, not once per run.** The read used to be taken once, before the loop: fresh for
the first removal, stale for every one after it.

Measured on a three-worktree fixture, a session arrived in the second candidate as the first was
removed. The single-snapshot version removed all three, occupied one included, and reported
`vetoedCandidates: 0`.

A fence read costs about 64 ms -- one `git worktree list` plus a registry sweep. The same candidate
already paid ~500 ms for its merged-PR probe, and the loop already spawns that same
`git worktree list` per removal.

**It bounds the staleness; it does not remove it.** Steps 4 and 5 and the removal still sit between
the read and the git command. The window is one candidate's work, not the batch's. Nothing is atomic.

`readsAtApply` reports how many times the fence was consulted. On a healthy run it equals
`counts.prunable`. Lower means the fence died and stopped the rest; `availableAtApply` is then false
and `detailAtApply` says where.

The census beside it -- `rootsExamined`, `recordsExamined`, `liveInRepo` -- is the **decision-pass**
read, not a total across the run.

One unavailable read survives every later available one: a fence that recovers by candidate 4 said
nothing about candidate 2. It exits 2, or **1 if something was already removed**, because exit 2
means nothing was attempted.

When the re-check vetoes, the occupants it found are **written back onto the decision**. Without
that, the one candidate the fence saved reports `Occupants: []`, and the "vetoed by signal 1" figure
under-reports the save to zero. That figure stops "the fence ran" implying "the fence covered it".

## Count outcomes, not intentions

A destructive tool that over-reports what it destroyed is actively misleading. The summary counts what
**happened**, not what was planned:

- a removal counts as `removed` only once the directory is **verified gone** and **deregistered**. Exit
  0 is git's claim; the directory being gone is the fact.
- `orphaned` is a **subset** of `failed`, and `failedNonOrphan` is spelled out so a consumer cannot
  reach a wrong total by adding all four numbers.
- `BranchOutcome` starts at `not attempted`, never `kept`. Otherwise every skipped candidate claims a
  decision nobody made: the JSON once said 7 branches were kept on a run whose summary said 0.
- `Merged` is `$null`, not `$false`, when the test never ran: a machine consumer reads `false` as
  "checked, and it is not merged", which is a different claim from "never asked".
- the final line is coloured by the **exit code**, not by the failure count. A run where the fence
  died and every removal was refused has `failed 0`, and used to print that in green next to exit 2.

### Exit codes

Highest severity wins.

| Code | Name | Meaning |
|---|---|---|
| 0 | OK | nothing wrong |
| 1 | FAILED | something was attempted and did not fully succeed, **without leaving anything broken on disk** -- a removal that failed, or a run that stopped partway with earlier removals already done |
| 2 | REFUSED | nothing was attempted, because safety could not be established (wrong cwd, unresolvable trunk, unavailable fence, a `-Name` that matched nothing) |
| 3 | ORPHANED | a directory is broken on disk **right now** (this run, or an earlier one) |

3 outranks 2 because damage on disk outranks a refusal to act.

## A failed removal is worse than no removal

`git worktree remove --force` deletes the `.git` pointer and **deregisters** the worktree *before*
it walks the tree, even when that walk fails. A partial failure leaves a directory that is neither a
worktree nor gone, and the session in it sees `fatal: not a git repository` from every git command.

So a failure is diagnosed on the spot. The report names which of three things survived: the
**directory**, its **.git pointer**, and its **registration**.

**The goal.** Turn a half-removed directory back into a worktree, or into a salvage pile you can
copy out of.

**What to do.** The tool prints this recipe. Run it from the primary checkout.

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

**What happens next.** Step 2 works only while the `.git` file is still there, because that file is
what `worktree repair` reads. Once it is gone, step 3 is the only route: `worktree add --force`
refuses while the directory exists, so the directory has to move aside first.

### Never run `git worktree prune`

It looks like the obvious tidy-up after a failed removal. It is not, and this repository never runs it --
not in `prune-merged.ps1`, not in `remove.ps1`.

`git worktree prune` deregisters **any** worktree whose directory is momentarily missing. That covers
a path a live session is about to return to, and the Claude Code-managed nested trees this tooling
must never touch. `git worktree remove` deregisters the one you removed; never deregister by sweep.

### An orphan outlives the run that made it

Once git has deregistered a worktree it is no longer in `git worktree list`, so it drops out of the
candidate set. The **next** run then printed a green all-clear over a directory this script had
broken. The recovery recipe survived only in the first run's scrollback.

Orphans are therefore recorded in the shared state root
(`<git-common-dir>/<prefix>-coord/prune-merged-orphans.json`). Every later run re-reports them, with
the recipe, until the directory is gone or re-registered. Two independent detectors, because either
can be true alone:

- the **ledger** written at the moment of the failure;
- a **ledger-free** scan: an unregistered sibling whose `.git` **file** points into this repo's
  worktree admin area. The `<primary>-` prefix alone is not enough. A relative `gitdir:` resolves
  against the `.git` file's directory, not this process's cwd; get that wrong and an orphan reports
  as fine.

The ledger is written only under `-Apply`. A dry run reports the same state without touching anything,
and a repaired or fully deleted entry clears itself.

A **ghost stub** is not the reaper's job: a half-failed auto-worktree's directory, with **no**
`.git` pointer and no `git worktree list` entry (`scripts/worktree/worktree-selfheal.ps1`,
`anthropics/claude-code#76590`). The orphan detector requires that `.git` file and never claims one.

## Deleting the branch: `-d` refusing is a signal

`git branch -d` refuses a branch merged only into the **remote** trunk whenever the local trunk
lags, as it usually does in a multi-worktree repo. `-D` therefore became routine, overriding git's
last protection against destroying commits every time, for a reason unrelated to the branch's state.

`Remove-BranchSafely` now does:

1. `git branch -d` first;
2. if that refuses, **re-verify at that moment** that `<trunk>..<branch>` is empty;
3. `-D` only then, reporting "re-verified: 0 commits beyond `<trunk>`, so nothing was lost";
4. otherwise **keep the branch** and say why, with the command to delete it by hand.

A stale ref costs nothing; a destroyed commit costs a session. The branch is also never touched after an
**unverified** removal.

`remove.ps1` takes the stricter line: it only ever runs `-d`. When git refuses, it leaves the branch
in place, prints the tip, and gives you the `-D` command. Deleting the branch becomes a deliberate
act rather than a side effect of tidying up a directory.

## Claims stranded by a removal

Coordination state lives in the **shared** `<git-common-dir>/<prefix>-coord/`, so it **outlives the
worktree**. Removing a worktree strands its claims (`scripts/coord/claim.ps1`): `-Take` hard-blocks
on any claim file that exists, so the key is unclaimable until someone runs `-Release <key> -Force`.

The reaper clears them, under rules worth copying:

- **on evidence, never on a timer.** The release runs only from the branch that has proven the
  directory is gone **and** deregistered, so no session is left in there to collide with. A claim
  whose holder is merely quiet is never touched; an auto-expiring claim would re-open the race it
  prevents.
- **full normalized path equality only** -- no leaf name, no prefix, no `StartsWith`. Releasing a
  *living* worktree's claim hands its key to another session, inviting the duplicate build the
  registry prevents. One normalizer on both sides, or the match silently misses and the claim stays
  stranded.
- a dry run releases nothing.
- an **unreadable** claim file belongs to the registry, not to any worktree: by definition we could
  not read whose it is. It is surveyed **once, at run level**, so a dry run sees it and no removal
  can count it twice. It is left in place, listed by filename, and it moves the exit code.
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

**The goal.** Remove the worktrees that are finished, and none of the ones that are not.

**What to do.** Run these from the primary checkout.

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

**What happens next.** The dry run prints a decision and a reason for every sibling, the fence
receipt, and the blind spots above. Read the SKIP reasons, then re-run with `-Apply`. Exit 2 means
the run refused and removed nothing.

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

**Assert the decision and the reason, not survival.** Tests asserting only "the directory still
exists" passed a build with no primary fence: the re-check caught it, so survival proved nothing.
Add a positive control in the same invocation; a refusal test is the exception, refusing the whole
run.

**Drive the re-check deterministically.** Use a shim whose probe performs the side effect *before*
it answers: a session arrives, the fence dies, metadata is touched. That proves steps 1, 2 and 4 of
the apply loop really re-read. No threads, no sleeps.

**Wrap the real function; do not replace it.** A hand-written stub is a second copy of a safety
check, and the copy that drifts is the one nobody tests.

**Plant the arrival in the candidate git removes second.** Worktree order is not alphabetical, and
the first candidate's read is fresh under a stale snapshot too.

## Limits, stated plainly

- **PowerShell 7, Windows-first.** These scripts are `#Requires -Version 7.3`. Path folding is
  case-insensitive only where the filesystem is (`$IsWindows -or $IsMacOS`). The folded form is for
  comparison **only**: never pass it to git or the filesystem. A Linux CI run was bitten by that
  once.
- **The session record schema is a vendor contract.** The liveness fence rests on Claude Code's
  own per-session records (`<config-root>/sessions/<pid>.json`, carrying `pid` / `startedAt` /
  `sessionId` / `cwd`). When it changes, the fence must become *unavailable* and refuse, not quietly
  empty.
- **`list_sessions` cannot see every session kind.** The Desktop app's session tooling enumerates
  sessions it spawned; an editor-extension session in the same config root never appears. The file
  registry above is the only source carrying every surface, so the fence reads that, not the MCP
  tool.
- **There is no heartbeat.** Nothing here can prove a session is gone. That is not an implementation gap
  to be closed later; it is why occupancy may only ever veto.
- **Signal 1 has measurably low coverage of the population this tool prunes.** Treat signal 2, and the
  refusal to run without a fence, as load-bearing rather than as belt-and-braces.
- **Only the sibling layout has scripted teardown *here*.** `prune-merged.ps1` excludes nested
  worktrees under `.claude/worktrees/` unconditionally, and the gate leaves them alone.

  `remove.ps1` applies no such test. Under `worktreeLayout: nested` it resolves its target to that
  path and removes it ([Worktrees](WORKTREES.md#two-layouts-coexist-and-only-one-has-scripted-teardown)).
