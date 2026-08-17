# Worktrees

## TLDR/BLUF

**What this is.** The day-to-day worktree commands. They give each session its own checkout, move
work out of the wrong one, put the shared checkout back, and delete a worktree without losing
commits.

**Why you should care.** One session's `git checkout` swaps every file under another session
mid-task, and neither screen says so. Not for you if you run one session at a time. Not for you off
Windows without testing first: these scripts are PowerShell 7, and Windows is the tested platform.

**How to use it.** Read the section for the job you have. [`docs/CONCEPTS.md`](CONCEPTS.md) defines
the terms this page assumes, [`INSTALL.md`](INSTALL.md) wires
the gate and the backstop, and [`docs/PRUNING.md`](PRUNING.md) owns the automated reaper.

---

Two parallel efforts -- two agents, or a human and an agent -- cannot share a working tree: one
`git checkout` swaps every file under the other mid-task. Each worktree has its own directory,
branch and index over one shared git directory, history and remotes. Branch -> PR -> merge is
unchanged.

> **Platform.** These scripts are PowerShell 7, developed and exercised on Windows. They run on
> PowerShell 7 elsewhere and the path handling is written for it, but Windows is the tested platform
> and the one the defaults assume. Where behavior degrades off Windows it is called out below.

---

## Command reference

Most of these anchor on the **primary checkout** -- the first entry of `git worktree list` -- so you
can run them from any checkout. Three exceptions, all deliberate:

- **`prune-merged.ps1` refuses** unless you run it from the primary, exiting 2 and naming both paths.
  From a linked worktree the candidate set is empty for the wrong reason.
- **`remove.ps1` refuses** when you are standing inside the worktree you named.
- **`bin/ccx-doctor.ps1` does not anchor at all.** With no `-Repo` it reports on your current
  directory, which is how a long green report about the wrong clone happens.

Five of the eight take `-Name`, validated against `\A[A-Za-z0-9._-]+\z`, because the name becomes a
directory name and a branch name. `restore-primary.ps1`, `sessions.ps1` and the doctor take none.

**`prune-merged.ps1`'s `-Name` is different, and it points the dangerous way.** It is an unvalidated
list that *restricts* the sweep to those worktrees **and confirms them past the recent-activity
veto** -- widening the blast radius rather than narrowing it.

It never overrides the liveness fence, a nested worktree, or a worktree lock ([Pruning](PRUNING.md)).

**The pattern is `\A...\z` rather than `^...$` on purpose.** In .NET `$` also matches before a
trailing newline, so the `^...$` spelling would accept a name ending in one.

| Task | Command |
|---|---|
| Create a worktree on its own branch | `pwsh -NoProfile -File scripts/worktree/new.ps1 -Name <name>` |
| Create it and open an editor there | `pwsh -NoProfile -File scripts/worktree/spawn.ps1 -Name <name>` |
| Move uncommitted work out of the primary | `pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name <name>` |
| Put the primary back on its home branch | `pwsh -NoProfile -File scripts/worktree/restore-primary.ps1` |
| Remove one worktree | `pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name <name>` |
| Remove the finished ones in bulk | `pwsh -NoProfile -File scripts/worktree/prune-merged.ps1` (dry run; `-Apply` acts) |
| Find sessions whose transcript moved | `pwsh -NoProfile -File scripts/worktree/sessions.ps1` |
| Prove the guards are actually live | `pwsh -NoProfile -File bin/ccx-doctor.ps1` |

The knobs that change what these do live in `ccx.config.json` at the repository root. That file is
the knob file, and announce's opt-in marker.

**It is not the switch for the worktree gate or the SessionStart backstop.** Those read
`~/.claude/hooks/ccx-gate.repos.txt` and ignore it, beyond the `prefix` knob.
[Limits and requirements](LIMITS.md#what-actually-switches-each-control-on) has the per-control
table.

| Key | Effect on this document |
|---|---|
| `trunk` | The default `-Base` for a new worktree and the ref merged work is measured against. `auto` asks the remote what its default branch is. Overridable per session with `CCX_TRUNK`. |
| `worktreeLayout` | `sibling` (default) or `nested` -- see [Two layouts](#two-layouts-coexist-and-only-one-has-scripted-teardown). |
| `setupHook` | The per-checkout bootstrap `new.ps1` runs after creating a worktree. |
| `prefix` | The stem for the state root, the `<prefix>.homeBranch` git config key, and the `<prefix>-home-branch` sidecar record. |

---

## Creating a worktree

**The goal.** A checkout of your own, on its own branch, cut from the current remote tip.

**What to do.** Run one of these from any checkout of the repository:

```powershell
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name alerts
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name sqltuning -Base feature/sql-tuning
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name quicklook -NoSetup
```

**What happens next.** `new.ps1` fetches, creates the worktree, runs your setup hook, and prints
`Worktree ready: <path> (branch '<branch>')` with the next steps.

`spawn.ps1` adds an editor window, forwarding `-Name`, `-Base` and `-NoSetup`. It relies on
`new.ps1` throwing, so no editor opens on an uncreated worktree. Editor: `CCX_EDITOR`, else
`EDITOR`, else `code`; `-Editor` overrides. An editor not on `PATH` is reported rather than
exiting green.

### The base is the freshly fetched remote tip, not local `main`

**The trap.** Local `main` is usually behind its upstream in a repository with several worktrees. A
worktree created off it starts stale, and *every merge-state judgment inherits the staleness* --
including the reaper's "is this merged?" test. Nothing is visibly wrong until the merge.

**The rule.** `new.ps1` fetches first, and the default base is a **remote-tracking** ref
(`origin/main`), never a local branch. Two details make that hold up:

- It fetches the remote **the trunk lives on**, parsed out of the base ref, rather than a hardcoded
  `origin`. A fork-based workflow whose trunk is `upstream/main` would otherwise fetch the wrong
  remote and report success.
- A fetch failure (offline) is a loud warning, not fatal. You can still branch off the refs you have
   -- you just need to know that is what happened.

If you pass `-Base` pointing at a **local** branch that lags its own upstream, you get a warning
naming the branch, the count, and the remote-tracking ref to use instead. A remote-tracking base has
no `@{upstream}` of its own, so the check simply no-ops for the default.

### Concurrent creation races `.git/config.lock`

**The trap.** Two sessions run `git worktree add` at once. One fails with `could not lock config
file .git/config: File exists`, and can leave an orphaned branch behind. The add writes the new
branch's upstream into clone-wide `.git/config`, so isolating sessions is itself a shared write.

**The rule.** `new.ps1` serialises the add behind a cross-session mutex (`Enter-CcxLock -Name
'worktree-add'`, 90-second timeout). Three properties of that lock matter, and they are the reason
this is a mutex rather than a retry loop:

- **Atomic exclusive-create is the mutex.** The lock is a file created with create-new semantics; the
  filesystem, not a read-then-write, decides who won.
- **It never steals.** On timeout it fails loudly and names the holder. Breaking a lock you cannot
  prove is abandoned re-opens exactly the race it exists to close, and there is no reliable liveness
  signal here to prove abandonment with.
- **The script refuses to run without it.** If `scripts/coord/lock.ps1` is missing, or does not define
  `Enter-CcxLock`, `new.ps1` throws rather than racing quietly. A safety property that degrades to
  "not applied" when a file is missing is not a safety property.

### One dependency environment per worktree

**The trap.** Reusing one dependency environment across worktrees to save a minute of install time.
An editable or linked install is bound to the **one source path** it was created from, so a test run
from worktree B imports worktree A's code. Green here, red in CI, and no diff that explains it.

**The rule.** Each worktree gets its own environment, built inside it. That is what `setupHook` is
for. `new.ps1` itself knows nothing about any language -- it runs the hook and reports whether it
worked:

| Contract | Detail |
|---|---|
| Working directory | The **new** worktree. Relative paths resolve against it. |
| `CCX_WORKTREE_PATH` | Absolute path of the new worktree |
| `CCX_WORKTREE_NAME` | The `-Name` it was created with |
| `CCX_PRIMARY_ROOT` | Absolute path of the primary checkout |
| `CCX_BASE_REF` | The ref the branch was created from |
| Arguments | None are passed, so a hook may declare whatever parameters it likes |
| Exit code | A `.ps1` hook runs in a **child** `pwsh`, so its exit code is a real contract and it cannot leave state behind in the calling session |

`examples/worktree-setup.ps1.example` shows the shape for a Python project and a Node project. Copy
it to the path named by `setupHook` (shipped as `.ccx/worktree-setup.ps1`) and delete everything that
is not yours. Two rules in it are not obvious:

- **Build the environment inside the worktree**, for the reason above.
- **Install from your lockfile, not from your version ranges.** A worktree that re-resolves
  dependencies gets whatever the registry serves today -- a different formatter from CI. With a
  `--fix` mode in a commit hook, that formatter **rewrites your source** to match a version CI does
  not have.

Two failure modes here are deliberately loud rather than silent:

- The hook file is **not found** in the new worktree or the primary -> a warning that the worktree
  has *not* been set up. (The worktree's own copy wins, since the hook is versioned with the branch;
  the primary's is the fallback for a git-ignored hook, which `git worktree add` cannot deliver.)
- The hook **exits non-zero** -> a throw that states the worktree *was* created, at which path, on
  which branch, and is not rolled back. A bare "setup failed" reads as "nothing happened", and the
  next session re-runs creation into a path that is now occupied.

Use `-NoSetup` when you want the checkout and not the environment. The "next steps" block says out
loud that the checkout has no environment yet.

---

## Rescuing work already in the primary

**The goal.** You are half-way through a change in the shared primary, and the gate will not let you
write there. `rescue.ps1` **moves** what you have instead of asking you to redo it.

**What to do.** Name the worktree the work should move into:

```powershell
pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name alerts-fix
```

**What happens next.** It stashes the primary's uncommitted work, creates a worktree, and pops the
stash there. Three details:

- **`--include-untracked`.** Without it, untracked files stay behind in the primary. The new
  worktree then recreates them: two diverging copies, with no indication which one you are editing.
- **The new branch is cut from the primary's *current* commit**, not from the trunk, so the stash
  applies cleanly. This is the one case where the fetched-remote-tip rule above is deliberately not
  applied -- a rescue that conflicts is a rescue that failed.
- **The stash is the safety net, and the recovery path is printed at the moment of failure.** If the
  pop fails for any reason, the `finally` block prints the exact commands to list the stash and put it
  back, plus the message it was stashed under. Mid-panic is not when someone opens a document.

If the primary is clean there is nothing to rescue, and the script says so and points at `new.ps1`
rather than creating an empty worktree.

---

## What actually stops the failure

Three mechanisms touch a `git checkout` that swaps the shared primary under another session. Only
the first prevents it.

| Role | Script | What it does |
|---|---|---|
| **Prevention** | `scripts/hooks/worktree_gate.ps1` | Refuses the git verbs that would swap or discard the primary's tree, before the tool call runs. It reads command strings, so a script or a shell redirect is invisible to it, and it fails open |
| **Repair** | `scripts/worktree/worktree-selfheal.ps1` | Restores the primary when its HEAD has drifted and the tree is clean. On a dirty tree it declines and touches nothing |
| **Detection** | the home-branch record | Covers a **linked worktree** that drifted, not the primary -- so it does not see the failure above. Warn-only, and [wrong by design](#the-sidecar-home-branch-record-is-wrong-by-design) |

## Restoring the primary

**The goal.** Put the shared primary back on its home branch. Several sessions stand in it at once,
so a `git checkout` there, or a detached `HEAD`, silently swaps every other session's files. The
gate denies tree-swapping git verbs in the primary, and `restore-primary.ps1` is the way back.

**A session may repair the primary; it may not hijack it.**

**What to do.** `-WhatIf` shows the switch without making it:

```powershell
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -Branch main
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -WhatIf
```

**What happens next.** The primary switches back to its home branch, which `restore-primary.ps1`
resolves in this order:

1. `-Branch`, for this run only
2. `git config <prefix>.homeBranch`
3. the local branch matching the configured trunk (`origin/main` -> `main`)
4. `main`, then `master`

Step 3 exists so a project whose default branch is named something else still gets the right answer.
It gets that answer from the same source every other script here uses, rather than from a second,
drifting list of names.

**The unattended backstop has no step 3.** `worktree-selfheal.ps1` goes from the config key straight
to `main`, then `master`.

That matters on a non-`main` trunk. A primary drifted off `develop`, with `main` present, is switched
onto `main` -- unattended, at session start.

If your trunk is not `main`, record it once and both scripts agree:

```powershell
git -C <primary> config <prefix>.homeBranch <your-trunk>
```

**It refuses on a dirty primary.** Re-attaching would carry someone else's uncommitted work onto
another branch or lose it, and the script cannot tell whose work it is. The refusal points at
`rescue.ps1`.

**`-Force` skips that refusal, it does not force the checkout.** The `git checkout` underneath
carries no `--force` and no `-m`.

So git still refuses when a modified tracked file differs between the two branches, which is the
usual reason you are there. Nothing is discarded either way. `rescue.ps1` is the route.

### The SessionStart backstop, and the half-failed auto-worktree

`worktree-selfheal.ps1` is the unattended repair, **wired as a SessionStart hook** by
`install-selfheal.ps1`.

**The bug it exists for.** On Windows the harness's auto-worktree can half-fail: it flips the
**primary's** `HEAD` onto the session's branch and leaves an **empty** "ghost" stub
([`anthropics/claude-code#76590`](https://github.com/anthropics/claude-code/issues/76590)).

What it does, and equally what it refuses to do:

| Situation | Action |
|---|---|
| A governed primary has drifted off its home branch **and its tree is clean** | Switch it back, and **say so** in the session's context. A silent repair is indistinguishable from nothing having happened. |
| A governed primary has drifted **and its tree is dirty** | **Touch nothing, and say why.** Uncommitted work is never at risk from this hook -- but the decline is reported, not silent: the checkout stays on the wrong branch until a person commits, stashes or rescues that work, and a silent decline reads exactly like a primary that was fine. |
| A governed primary is on a **detached** HEAD, or has no resolvable home branch | Nothing, silently. Neither state says which branch it was meant to be on, and switching a shared checkout onto a guess is worse than leaving it. |
| This session's cwd is under `<primary>/.claude/worktrees/<name>` with **no `.git` there** | Report it as a ghost stub and tell the model to create a real worktree before editing. A real linked worktree has a `.git` **file** pointing at its private git directory; a half-failed stub has nothing there at all. That single test separates them. |
| This session's own linked worktree is on a different branch from its recorded home | **Warn only.** Never auto-switch a linked worktree under the session standing in it. |

**The dirty-tree refusal is this hook's only safety property.** `bin/ccx-doctor.ps1` drifts a
throwaway repository, leaves an uncommitted change, and requires the backstop to decline **and to
say why**; a repair is `RED`. Drifting a *clean* fixture passes whether or not that test is in the
code.

It **fails open on every error path** -- exit 0, no output. It is **self-contained**: installed
outside every working tree, it dot-sources nothing from the repository, duplicating
`scripts/coord/_common.ps1`. A hook inside a checkout vanishes on a branch switch; a missing one is
silent.

The backstop and the PreToolUse worktree gate read **one** allowlist,
`~/.claude/hooks/ccx-gate.repos.txt`, written by both installers at one fixed name.

There were once two. One installer rewrote its own unconditionally, the other seeded a copy only if
absent, and nothing kept them in sync. A repository added through one never reached the other;
uninstalling the gate left the backstop armed and willing to run `git checkout` on the shared
primary.

Deleting that file turns both off immediately, which is the point of making the kill switch a
**file** rather than a settings edit.

### The sidecar home-branch record is wrong by design

`new.ps1` writes the worktree's home branch to `<git-common-dir>/worktrees/<id>/<prefix>-home-branch`.
That path is inside the worktree's **private** git directory, so a checkout cannot move the record
and no worktree sees any other worktree's value. The drift detector reads it.

**The record is wrong by design, so the detector may only warn.** It records what the worktree was
created for, not what it should be on now, and never updates: re-branching makes it stale. Treating
it as authoritative would "repair" an intentional change, swapping every file under a live session.

In the audit that produced this rule, most of the live worktrees mismatched their record. The file
had two writers, creation time and bootstrap-on-first-sighting, with no update path, and the printed
remedy would have moved a session off its real branch. Three things follow:

- **Prefer the authoritative source.** `git worktree list --porcelain` needs no sidecar at all. Use
  the record only for the question it can answer.
- **Treat a mismatch as a question, never a verdict.** The hook warns and names both branches; the
  human decides.
- **Never print a destructive remediation command from a detector you have not proven correct.** The
  warning tells you to commit or stash first, and to run the switch yourself from a plain terminal.

**The bootstrap writer can race session setup, and the result is a warning that never stops.** When
no record exists yet, the backstop bootstraps one from whatever branch the worktree is on at that
moment.

If that happens before the harness moves the new worktree onto its session branch, "home" is
captured as the pre-setup branch. The mismatch warning then fires on every later session start,
forever.

Measured here on 2026-08-05: worktree created at 09:21:50, record written at 09:21:54, harness moved
the worktree to its session branch at 09:23:10. The warning was stale by 76 seconds, not a hijack.

This is the sharpest reason the detector may only warn. A harness-driven switch during session setup
and a genuine hijack are identical in the record until you check the worktree's reflog for an agent
tool call that caused it.

**Two names, one word apart.** The git config key `<prefix>.homeBranch` overrides the *primary's*
home branch; `restore-primary.ps1` and the backstop read it. The sidecar file
`<prefix>-home-branch` is a per-worktree creation note. Both names come from `prefix`, so a rename
cannot split them.

---

## Removing a worktree

**The goal.** Delete a finished worktree and keep a way back to its commits.

**What to do.** Run it from any checkout **except** the one being removed:

```powershell
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts -DeleteBranch
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts -Force    # discard tracked changes too
```

**What happens next.** The tip is printed before anything is destroyed, the worktree is removed, and
with `-DeleteBranch` git is asked to delete the branch with `-d`.

Git cannot remove the worktree you are standing in, and the script refuses first with a message
about what *you* did rather than letting git report the git-level problem.

**It refuses on uncommitted *tracked* changes** unless `-Force`. Untracked entries -- a dependency
directory, build output, a scratch database -- are expected and do not block removal.

**They are deleted, though, and git cannot get them back.** The removal is always
`git worktree remove --force`, on every path, not only under `-Force`.

So an untracked `.env`, a local database or a scratch file in that worktree is gone. Git never had
them, so neither reflog nor `fsck` will help. Look before you run this.

> Note the deliberate asymmetry with the automated reaper, which treats untracked files as a
> **blocker**. A human running `remove.ps1` has just looked at the directory and can say those files
> are disposable; an unattended sweep cannot. The stricter test belongs to the tool that runs without
> a human. Do not "fix" the difference by making them agree.

### Reference the tip before anything is destroyed

**The trap.** Removing a worktree can take its branch ref with it, and **a commit that is in no ref is
also in no reflog**. There is then no `git reflog` entry to recover it from and nothing in the
interface admits the work ever existed.

**The rule.** The tip is resolved and printed **first**, while the branch still exists. With
`-DeleteBranch`, it is also written to a keep-ref *before* the branch goes:

```text
List them:    git for-each-ref refs/<prefix>/removed/
Recover one:  git branch <branch-that-was-deleted> refs/<prefix>/removed/<name>
Drop one:     git update-ref -d refs/<prefix>/removed/<name>
```

**The two names are not the same, and the recover line is where that bites.** The keep-ref is named
after `-Name`, the directory component. The branch deleted is the one the worktree was *on*.

`new.ps1 -Name my-task -Branch feature/my-task` makes those differ. Using `<name>` on both sides
recreates the branch under the wrong name. `remove.ps1` prints the branch it deleted; use that.

The keep-ref costs nothing and is the difference between "recoverable" and "gone at the next `gc`".

### `git branch -d` refusing is a signal

**The trap.** `-d` keeps refusing merged branches, so cleanup scripts reach for `-D`. It refuses
because the branch is merged only into the **remote** trunk while the **local** trunk lags, as it
usually does. Git's last protection against destroying commits is overridden for an unrelated reason.

**The rule.** `remove.ps1` runs `-d`, never `-D`. If git refuses, the branch is **left in place on
purpose**, **git's own reason is printed verbatim**, the tip is printed again, and the forcing command
is offered. A stale ref costs nothing; a destroyed commit costs a session.

**And it deletes the branch the worktree was *on*, never `-Name`.** `-Name` is the directory
component and cannot contain `/`; a branch name can, and `new.ps1 -Name my-task -Branch
feature/my-task` is a documented invocation.

Asking git to delete `my-task` there fails with *branch not found*, which is why the refusal relays
what git said instead of asserting a cause. It used to assert one: that the branch held commits no
other ref has.

So the common namespaced case sent you looking for commits that do not exist, while the real branch
survived a run that read as a full cleanup.

A **detached** worktree has no branch to delete at all, and the script says so rather than guessing
at one that happens to share the directory's name.

### Never `git worktree prune` as cleanup

`git worktree prune` looks like the obvious tidy-up; `remove.ps1` does not run it. It deregisters
**any** worktree git cannot see: a disconnected drive, an unmounted volume, a nested worktree a live
session is about to return to. `git worktree remove` already deregisters the one you removed.

There is a related failure: a removal that deregisters the worktree and then fails to delete the
directory, leaving a folder git no longer recognizes. How to recover from it is covered in
[`docs/PRUNING.md`](PRUNING.md), which owns the unattended path.

For bulk cleanup use `prune-merged.ps1`. It is a dry run by default, and its rule is
**merged AND clean AND NOT occupied**; occupancy can only ever veto a removal, never authorize one.

---

## Two layouts coexist, and only one has scripted teardown

There are two populations of worktree under a repository, and -- measured on the repo this tooling was
developed in -- both populations were live at once:

| Layout | Path | Created by | Torn down by |
|---|---|---|---|
| **sibling** (default) | `<parent-of-primary>/<primary-leaf>-<name>` | `new.ps1` / `spawn.ps1` / `rescue.ps1` | `remove.ps1`, `prune-merged.ps1` |
| **nested** | `<primary>/.claude/worktrees/<name>` | the harness itself -- and these scripts too, under `worktreeLayout: nested` | `remove.ps1` only, and only for one you named |

`worktreeLayout` in `ccx.config.json` selects where **we** create worktrees. Set it to `nested` and
`new.ps1`, `spawn.ps1` and `rescue.ps1` all create at that path, so the second row is then ours as
well as the harness's.

**The `.claude/worktrees/` exclusion is not universal.** `Test-CcxHarnessWorktreePath` keeps those
paths away from the **gate** and the **reaper**. `remove.ps1` never calls it, and removes whatever
its layout resolves -- so under `nested`, `remove.ps1 -Name x` will take a nested worktree.

That exclusion is one named test because two rules pull in opposite directions:

- A **gate** protecting the primary must *not* govern a nested worktree. It sits under the primary's
  path, so a plain prefix test says "inside the primary" -- but a git verb there swaps only its own
  tree. Governing it refused the most ordinary thing a session does.
- A **reaper** must *never* remove one. Its path can also start with `<primary>-` under some layouts,
  so a sibling prefix scan picks it up, and removing it destroys the checkout a live session is
  standing in.

Two more consequences worth knowing:

- **"Sibling" is not a prefix match.** `<primary>-work/x` has the prefix but is no sibling.
  `Test-CcxSiblingWorktreePath` requires the same parent directory, a leaf of **exactly**
  `<primary-leaf>-<something>`, **and not a harness worktree**.

  Even then it only *looks* like ours: removal turns on occupancy, cleanliness and merge state.
- **A nested checkout is git-ignored inside its parent.** The parent therefore reads perfectly clean,
  and a `--force` removal of the parent deletes both -- leaving the nested worktree registered with no
  directory.

### A wrong-cwd run must refuse loudly, never green no-op

**The trap.** A sweep run from a linked worktree instead of the primary found no siblings from where
it was standing. It reported nothing to consider and exited 0: a wrong-cwd run issuing a clean bill
of health. Nobody re-runs a command that said everything was fine.

**The rule.** Anchor on the primary, never on `$PSScriptRoot/../..`. `Get-CcxPrimaryRoot` reads the
first entry of `git worktree list --porcelain`, so every command behaves the same anywhere.

`prune-merged.ps1` exits non-zero with
`REFUSED: this is a linked worktree, not the primary checkout`, **naming both paths**, rather than
reporting nothing to do.

`remove.ps1` applies the same principle to the narrower case of standing inside the worktree you
asked it to delete.

The same reasoning is why the layout formula lives in exactly one place
(`Get-CcxWorktreePath` in `scripts/coord/_common.ps1`). It was once duplicated in four scripts and
pattern-matched in a fifth -- which is how a rule and its enforcement can disagree without either
being wrong on its own.

---

## What a worktree does *not* isolate

A worktree gives you separate files, a separate branch, a separate index and -- with a setup hook -- a
separate dependency environment. It feels total. Five things are still shared, and each has bitten:

| Shared thing | Why | What to do |
|---|---|---|
| **Coordination state** | It lives at `<git-common-dir>/<prefix>-coord`, which is identical across every worktree of a clone (that is the point -- a claim taken in one worktree must be visible in another). | Its corollary: **state outlives the worktree.** Remove a worktree and the claims it took are still there. Release on *evidence* -- the directory is gone **and** deregistered -- never on a timer. See [Coordination](COORDINATION.md). |
| **The git hooks directory** | One `commit-msg` / `pre-push` set lives in the shared git directory and governs every worktree of that clone at once. | Install once per clone, not per worktree. It also sees every write route, because it inspects the tree at commit time rather than a tool call. |
| **`.git/config`** | Written by `git worktree add`. | Already handled by the mutex above. |
| **The AI coding assistant's project memory** | It lives outside the repository, in one directory shared by every session on the machine. Last write wins. | Reads are fine. Coordinate **writes** explicitly, or let exactly one session own them. |
| **`.claude/` mostly does not reach a new worktree** | A project-scoped settings file is a creation-time snapshot at best, lives on one branch, and is commonly git-ignored. Anything *tracked* under `.claude/` is checked out like any other file; what is git-ignored cannot arrive at all. | Wire cross-session hooks at **user** scope, with the script installed outside every working tree. See [Install](INSTALL.md). |

**Files a worktree cannot isolate at all** -- ports, a development database, a Redis keyspace, a
package cache, a git-ignored `.env` -- are a separate class, and nothing here sees them.
[Limits and requirements](LIMITS.md) owns that one.

---

## Known limits

[Limits and requirements](LIMITS.md) owns the full statement, including the entry cost this page
never names: Claude Code for Desktop, and the scripts vendored into the repository you govern. What
bears on these commands specifically:

- **PowerShell 7, Windows-first.** Most scripts are `#Requires -Version 7.3` and were exercised on
  Windows. `$env:USERPROFILE` is Windows-only, so every home-directory lookup here uses the
  null-safe idiom that falls back to the .NET accessor -- but Windows remains the tested platform.

  **`worktree-selfheal.ps1` and its installer declare `-Version 7`, not 7.3.** That is why 7.0-7.2 is
  worse than unsupported: the backstop installs there and the gates do not.
- **Paths fold case on Windows and macOS, not on a case-sensitive filesystem.** Use the folded form
  for **comparison only**, never for git, the filesystem, or a human. One silent gate failure on
  Linux CI: a lower-cased path went to `git -C`, git failed, and the rule fell through to allow.
- **The harness's session record format is a vendor contract.** The liveness fence behind the reaper
  reads per-session records the harness writes; that schema can change without notice. The fence
  then reports itself unavailable and nothing is pruned -- the intended failure direction, and an
  outage.
- **Session listings do not see every session kind.** Sessions relocated into a worktree file their
  transcript under a different key and drop out of the list of the window they were born in.
  `sessions.ps1` is how you find them, and `-Rehome` is how you put one back:

  ```powershell
  pwsh -NoProfile -File scripts/worktree/sessions.ps1                          # list
  pwsh -NoProfile -File scripts/worktree/sessions.ps1 -Id <id-prefix>          # one session
  pwsh -NoProfile -File scripts/worktree/sessions.ps1 -Rehome <id> -WhatIf     # preview the move
  pwsh -NoProfile -File scripts/worktree/sessions.ps1 -Rehome <id>             # move it back
  ```

  A bare invocation only ever lists. `-Rehome` is the one action that moves anything, and it honours
  `-WhatIf`.
- **Nothing here can prove a session is gone.** There is no heartbeat. Every occupancy verdict is the
  absence of a veto, not a permission.

Run `pwsh -NoProfile -File bin/ccx-doctor.ps1` to see which of these guards are installed and
enforcing on this machine, rather than merely present in the repository.
