# Worktrees

## TLDR/BLUF

**What this is.** Day-to-day use of the worktree scripts. They create a checkout for a parallel
session, rescue work that is already in the wrong place, put the shared checkout back, and remove a
worktree without losing commits.

**Why you should care.** One side's `git checkout` swaps every file under the other side mid-task,
and nothing on either screen says so. Not for you if you run one session at a time, and not for you
off Windows without checking: these scripts are PowerShell 7 and Windows is the tested platform.

**How to use it.** Read [`docs/CONCEPTS.md`](CONCEPTS.md) first for the state root and the liveness
fence, then wire the gate and the SessionStart backstop with
[`INSTALL.md`](https://claude-multisession.pages.dev/INSTALL.md).
[`docs/PRUNING.md`](PRUNING.md) owns the automated reaper.

---

Two parallel efforts -- two agent sessions, or a human and an agent -- cannot safely share one working
tree. One side's `git checkout` swaps every file under the other side mid-task, and nothing on either
screen says so. A git worktree gives each session its own directory, its own branch and its own
index, while sharing one git directory, one history and one set of remotes. The normal
branch -> PR -> merge flow is unchanged.

> **Platform.** These scripts are PowerShell 7, developed and exercised on Windows. They run on
> PowerShell 7 elsewhere and the path handling is written for it, but Windows is the tested platform
> and the one the defaults assume. Where behavior degrades off Windows it is called out below.

Related: [`docs/CONCEPTS.md`](CONCEPTS.md) for the state root and the liveness fence,
[`docs/PRUNING.md`](PRUNING.md) for the automated reaper, [`INSTALL.md`](https://claude-multisession.pages.dev/INSTALL.md) for wiring
the gate and the SessionStart backstop.

---

## Command reference

Every script anchors on the **primary checkout** -- the first entry of `git worktree list` -- so it
does not matter which checkout you invoke it from. All of them take `-Name`, validated against
`^[A-Za-z0-9._-]+$`, because the name becomes a directory name and a branch name.

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

The knobs that change what these do live in `ccx.config.json` at the repository root -- which is also
the marker that tells user-scope hooks this repository has opted in:

| Key | Effect on this document |
|---|---|
| `trunk` | The default `-Base` for a new worktree and the ref merged work is measured against. `auto` asks the remote what its default branch is. Overridable per session with `CCX_TRUNK`. |
| `worktreeLayout` | `sibling` (default) or `nested` -- see [Two layouts](#two-layouts-coexist-and-only-one-has-scripted-teardown). |
| `setupHook` | The per-checkout bootstrap `new.ps1` runs after creating a worktree. |
| `prefix` | The stem for the state root, the `<prefix>.homeBranch` git config key, and the `<prefix>-home-branch` sidecar record. |

---

## Creating a worktree

```powershell
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name alerts
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name sqltuning -Base feature/sql-tuning
pwsh -NoProfile -File scripts/worktree/new.ps1 -Name quicklook -NoSetup
```

`spawn.ps1` is the same thing plus an editor window. It forwards `-Name`, `-Base` and `-NoSetup`
unchanged and holds no safety property of its own -- it relies on `new.ps1` throwing, so an editor is
never opened on a worktree that was not created. The editor is `CCX_EDITOR`, else `EDITOR`, else
`code`, and `-Editor <command>` overrides all three. If the editor is not on `PATH` the script says
so and prints the path rather than exiting green over a window that never opened.

### The base is the freshly fetched remote tip, not local `main`

**The trap.** Creating a worktree off local `main` looks obviously correct, and in a repository with
several worktrees local `main` is usually behind its upstream. The new worktree starts from stale
code, everything built in it is built against that stale code, and *every subsequent merge-state
judgment inherits the staleness* -- including the reaper's "is this merged?" test. Nothing is visibly
wrong until the merge.

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

**The trap.** Two sessions each run `git worktree add -b <name> <base>` at roughly the same time. One
of them fails with `could not lock config file .git/config: File exists`, and it can leave an orphaned
branch behind. `git worktree add` writes the new branch's upstream into `.git/config`, which is shared
by every worktree of the clone, so the operation that is supposed to isolate sessions is itself a
shared write. Once several worktrees share one git directory this stops being theoretical.

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
For an editable or linked install this is worse than slow. The environment is bound to the **one
source path** it was created from, so a test run from worktree B imports worktree A's code. Green
here, red in CI, and no diff that explains it.

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
- **Install from your lockfile, not from your version ranges.** A fresh worktree that re-resolves
  dependencies gets whatever the registry serves today, which is how a checkout ends up with a
  different formatter from CI. That is worse than misleading when the tool has a `--fix` mode wired
  into a commit hook. It does not merely report differently: it **rewrites your source** to match a
  version CI does not have.

Two failure modes here are deliberately loud rather than silent:

- The hook file is **not found** in either the new worktree or the primary -> a warning saying the
  worktree has *not* been set up. (The worktree's own copy wins, because the hook is versioned with
  the branch; the primary's copy is the fallback for a hook that is git-ignored, which
  `git worktree add` cannot deliver.)
- The hook **exits non-zero** -> a throw that states the worktree *was* created, at which path, on
  which branch, and is not rolled back. A bare "setup failed" reads as "nothing happened", and the
  next session re-runs creation into a path that is now occupied.

Use `-NoSetup` when you want the checkout and not the environment. The "next steps" block says out
loud that the checkout has no environment yet.

---

## Rescuing work already in the primary

A gate that stops you writing into the shared primary is infuriating if you are already half-way
through a change there. `rescue.ps1` **moves** what you have instead of asking you to redo it:

```powershell
pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name alerts-fix
```

It stashes the primary's uncommitted work, creates a worktree, and pops the stash there. Three
details:

- **`--include-untracked`.** Without it, untracked files stay behind in the primary and are then
  silently duplicated the moment the new worktree recreates them: two copies, diverging, with no
  indication which one you are editing.
- **The new branch is cut from the primary's *current* commit**, not from the trunk, so the stash
  applies cleanly. This is the one case where the fetched-remote-tip rule above is deliberately not
  applied -- a rescue that conflicts is a rescue that failed.
- **The stash is the safety net, and the recovery path is printed at the moment of failure.** If the
  pop fails for any reason, the `finally` block prints the exact commands to list the stash and put it
  back, plus the message it was stashed under. Mid-panic is not when someone opens a document.

If the primary is clean there is nothing to rescue, and the script says so and points at `new.ps1`
rather than creating an empty worktree.

---

## Restoring the primary

The primary checkout is the one directory several sessions stand in at once. When a session runs
`git checkout <its-branch>` there -- or leaves `HEAD` detached -- every other session's files silently
become a different commit's files. The worktree gate denies the tree-swapping git verbs in the
primary; `restore-primary.ps1` is the sanctioned way back. **A session may repair the primary; it may
not hijack it.**

```powershell
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -Branch main
pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -WhatIf
```

The home branch is resolved in this order:

1. `-Branch`, for this run only
2. `git config <prefix>.homeBranch`
3. the local branch matching the configured trunk (`origin/main` -> `main`)
4. `main`, then `master`

Step 3 exists so a project whose default branch is named something else still gets the right answer.
It gets that answer from the same source every other script here uses, rather than from a second,
drifting list of names.

**It refuses on a dirty primary.** Re-attaching would either carry someone else's uncommitted work
onto another branch or lose it, and the script cannot tell whose work it is. The refusal points at
`rescue.ps1`, which is not destructive. `-Force` re-attaches anyway and still discards nothing -- the
changes stay in the tree, they just land on the home branch.

### The SessionStart backstop, and the half-failed auto-worktree

`worktree-selfheal.ps1` is the unattended version of the same repair, wired as a SessionStart hook by
`install-selfheal.ps1`. It exists for a specific vendor-side failure: the harness's own per-session
auto-worktree can half-fail on Windows, flipping the **primary's** `HEAD` onto the session's branch
and leaving an empty "ghost" stub directory behind -- see
[`anthropics/claude-code#76590`](https://github.com/anthropics/claude-code/issues/76590).

What it does, and equally what it refuses to do:

| Situation | Action |
|---|---|
| A governed primary has drifted off its home branch **and its tree is clean** | Switch it back, and **say so** in the session's context. A silent repair is indistinguishable from nothing having happened. |
| A governed primary has drifted **and its tree is dirty** | **Touch nothing, and say why.** Uncommitted work is never at risk from this hook -- but the decline is reported, not silent: the checkout stays on the wrong branch until a person commits, stashes or rescues that work, and a silent decline reads exactly like a primary that was fine. |
| A governed primary is on a **detached** HEAD, or has no resolvable home branch | Nothing, silently. Neither state says which branch it was meant to be on, and switching a shared checkout onto a guess is worse than leaving it. |
| This session's cwd is under `<primary>/.claude/worktrees/<name>` with **no `.git` there** | Report it as a ghost stub and tell the model to create a real worktree before editing. A real linked worktree has a `.git` **file** pointing at its private git directory; a half-failed stub has nothing there at all. That single test separates them. |
| This session's own linked worktree is on a different branch from its recorded home | **Warn only.** Never auto-switch a linked worktree under the session standing in it. |

**The dirty-tree refusal is the only safety property this hook has**, and it is the one thing about it
worth checking. `bin/ccx-doctor.ps1` drifts a throwaway repository, leaves an uncommitted change in it,
and requires the backstop to decline **and to say why**. A repair there is `RED`. That negative control
is load-bearing rather than decorative, because the positive one is not. Drifting a *clean* fixture and
watching it get repaired passes identically whether or not the dirty-tree test is still in the code.

It **fails open on every error path** -- exit 0, no output. A backstop that wedges session startup gets
ripped out, and then it protects nothing. It is also **self-contained**: it is installed as a copy
outside every working tree, so it dot-sources nothing from the repository, even where that duplicates
a helper in `scripts/coord/_common.ps1`. A hook script that lives inside a checkout vanishes on a
branch switch, and a hook whose script is missing lets the session proceed with nothing said.

The backstop and the PreToolUse worktree gate read **one** allowlist,
`~/.claude/hooks/ccx-gate.repos.txt`, written by both installers at one fixed name.

There were once two. One installer rewrote its own unconditionally while the other seeded a second
copy only if absent, and nothing kept them in sync. Adding a governed repository through one
installer never reached the other, and uninstalling the gate left the backstop armed and still
willing to run `git checkout` on the shared primary. They agreed only by luck.

Deleting that file turns both off immediately, which is the point of making the kill switch a
**file** rather than a settings edit.

### The sidecar home-branch record is wrong by design

`new.ps1` writes the worktree's home branch to `<git-common-dir>/worktrees/<id>/<prefix>-home-branch`
-- inside the worktree's **private** git directory, so a checkout cannot move it and every worktree
does not see every other worktree's value. The drift detector reads it.

**The record is wrong by design, and that is why the detector may only warn.** It answers *"what was
this worktree created for"*, not *"what should it be on now"*. It is written once and never updated,
so deliberately re-branching a worktree -- a normal part of its lifecycle -- makes it stale
immediately. A detector that treated it as authoritative would "repair" an intentional change, and
the remediation it would print is a branch switch that swaps every file under a live session.

Concretely, in the audit that produced this rule, most of the live worktrees mismatched their record.
The file had two writers, creation time and bootstrap-on-first-sighting, with no update path, and the
printed remedy would have moved a session off its real branch. Three things follow:

- **Prefer the authoritative source.** `git worktree list --porcelain` needs no sidecar at all. Use
  the record only for the question it can answer.
- **Treat a mismatch as a question, never a verdict.** The hook warns and names both branches; the
  human decides.
- **Never print a destructive remediation command from a detector you have not proven correct.** The
  warning tells you to commit or stash first, and to run the switch yourself from a plain terminal.

**The bootstrap writer can race session setup, and the result is a warning that never stops.** When
no record exists yet, the backstop bootstraps one from whatever branch the worktree is on at that
moment.

If that happens before the harness has moved a newly created worktree onto its session branch,
"home" is captured as the pre-setup branch, and the mismatch warning then fires on every later
session start, forever.

Measured here on 2026-08-05: worktree created at 09:21:50, record written at 09:21:54, harness moved
the worktree to its session branch at 09:23:10. The warning was stale by 76 seconds, not a hijack.

This is the sharpest reason the detector may only warn. A harness-driven switch during session setup
and a genuine hijack are identical in the record until you check the worktree's reflog for an agent
tool call that caused it.

A near-identical git config key, `<prefix>.homeBranch`, exists alongside the file. They are not the
same thing and they are one word apart. The **config key** is your deliberate override for the
*primary's* home branch, read by `restore-primary.ps1` and the backstop. The **sidecar file** is a
per-worktree creation-time note. Both derive their name from `prefix`, read from the repository's own
config by whoever is reading them, so renaming the prefix cannot split the writer and the reader onto
two different names.

---

## Removing a worktree

```powershell
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts -DeleteBranch
pwsh -NoProfile -File scripts/worktree/remove.ps1 -Name alerts -Force    # discard tracked changes too
```

Run it from any checkout **except** the one being removed. Git cannot remove the worktree you are
standing in, and the script refuses first with a message about what *you* did rather than letting git
report the git-level problem.

**It refuses on uncommitted *tracked* changes** unless `-Force`. Untracked entries -- a dependency
directory, build output, a scratch database -- are expected and do not block removal.

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
Recover one:  git branch <name> refs/<prefix>/removed/<name>
Drop one:     git update-ref -d refs/<prefix>/removed/<name>
```

The keep-ref costs nothing and is the difference between "recoverable" and "gone at the next `gc`".

### `git branch -d` refusing is a signal

**The trap.** `-d` keeps refusing branches that have obviously merged, so `-D` becomes the routine
path in cleanup scripts. The reason `-d` refuses is usually that the branch is merged only into the
**remote** trunk while the **local** trunk lags -- which it usually does in a multi-worktree setup. So
git's last protection against destroying commits was being overridden every single time, for a reason
unrelated to the branch's actual state.

**The rule.** `remove.ps1` runs `-d`, never `-D`. If git refuses, the branch is **left in place on
purpose**, **git's own reason is printed verbatim**, the tip is printed again, and the forcing command
is offered for you to run deliberately. A stale ref costs nothing; a destroyed commit costs a session.

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

`git worktree prune` looks like the obvious tidy-up, and `remove.ps1` deliberately does not run it.
That command deregisters **any** worktree whose directory git cannot currently see -- one on a
disconnected network drive, an unmounted volume, a harness-managed nested worktree a live session is
about to come back to. `git worktree remove` already deregisters the one you removed; a blanket prune
is a second, much wider action wearing the costume of a cleanup step.

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
| **nested** | `<primary>/.claude/worktrees/<name>` | the harness itself -- its own worktree flag, the desktop app, isolated subagents | nothing here; it is not ours |

`worktreeLayout` in `ccx.config.json` selects where **we** create worktrees. It does **not** change the
fact that any path containing a `.claude/worktrees/` segment is excluded from destructive operations
unconditionally, whatever the setting says. That exclusion is one named test
(`Test-CcxHarnessWorktreePath`) rather than two inline regexes, because two rules depend on it and
they pull in opposite directions:

- A **gate** protecting the primary must *not* govern a nested worktree. It sits under the primary's
  path, so a plain prefix test says "inside the primary" -- but a git verb there swaps only its own
  tree. Governing it refused the most ordinary thing a session does.
- A **reaper** must *never* remove one. Its path can also start with `<primary>-` under some layouts,
  so a sibling prefix scan picks it up, and removing it destroys the checkout a live session is
  standing in.

Two more consequences worth knowing:

- **"Sibling" is not a prefix match.** `<primary>-work/x` starts with `<primary>-` and is a sibling of
  nothing. `Test-CcxSiblingWorktreePath` requires the same parent directory, a leaf of exactly
  `<primary-leaf>-<something>`, and not a harness worktree. Even then it only says the path *looks*
  like ours; whether it may be removed is answered by occupancy, cleanliness and merge state, never by
  the name.
- **A nested checkout is git-ignored inside its parent.** The parent therefore reads perfectly clean,
  and a `--force` removal of the parent deletes both -- leaving the nested worktree registered with no
  directory.

### A wrong-cwd run must refuse loudly, never green no-op

**The trap.** A sweep run from a linked worktree instead of the primary enumerated the primary's
siblings, found none from where it was standing, printed a green `No sibling worktrees to consider`
and exited 0. That is a wrong-cwd run issuing a clean bill of health. Nobody re-runs a command that
just told them everything was fine.

**The rule.** Anchor on the primary -- never on `$PSScriptRoot/../..`, which is the checkout the
*script* happens to live in. `Get-CcxPrimaryRoot` reads the first entry of
`git worktree list --porcelain`, so every command here behaves identically from any checkout. Where a
command genuinely must run from one specific place, it **refuses**. `prune-merged.ps1` exits
non-zero with `REFUSED: this is a linked worktree, not the primary checkout`, naming both paths,
rather than reporting nothing to do. `remove.ps1` applies the same principle to the narrower case of
standing inside the worktree you asked it to delete.

The same reasoning is why the layout formula lives in exactly one place
(`Get-CcxWorktreePath` in `scripts/coord/_common.ps1`). It was once duplicated in four scripts and
pattern-matched in a fifth -- which is how a rule and its enforcement can disagree without either
being wrong on its own.

---

## What a worktree does *not* isolate

A worktree gives you separate files, a separate branch, a separate index and -- with a setup hook -- a
separate dependency environment. It feels total. Four things are still shared, and each has bitten:

| Shared thing | Why | What to do |
|---|---|---|
| **Coordination state** | It lives at `<git-common-dir>/<prefix>-coord`, which is identical across every worktree of a clone (that is the point -- a claim taken in one worktree must be visible in another). | Its corollary: **state outlives the worktree.** Remove a worktree and the claims it took are still there. Release on *evidence* -- the directory is gone **and** deregistered -- never on a timer. See [`docs/COORDINATION.md`](COORDINATION.md). |
| **`.git/config`** | Written by `git worktree add`. | Already handled by the mutex above. |
| **The AI coding assistant's project memory** | It lives outside the repository, in one directory shared by every session on the machine. Last write wins. | Reads are fine. Coordinate **writes** explicitly, or let exactly one session own them. |
| **Nothing under `.claude/` reaches a new worktree by itself** | A project-scoped settings file is a creation-time snapshot at best, lives on one branch, and is commonly git-ignored -- so git cannot deliver a project-level hook to a worktree at all. | Wire cross-session hooks at **user** scope, with the script installed outside every working tree. See [`INSTALL.md`](https://claude-multisession.pages.dev/INSTALL.md). |

---

## Known limits

- **PowerShell 7, Windows-first.** The scripts are `#Requires -Version 7.3` and were exercised on
  Windows. `$env:USERPROFILE` is Windows-only, so every home-directory lookup here uses the
  null-safe idiom that falls back to the .NET accessor -- but Windows remains the tested platform.
- **Path comparison folds case only where the filesystem does.** On Windows and macOS paths are
  lower-cased before comparison; on a case-sensitive filesystem they are not, because there
  `/x/Primary` and `/x/primary` really are two directories. The folded form is for **comparison
  only** -- never pass it to git, to the filesystem, or into a message a human reads. This has already
  cost one silent gate failure on Linux CI, where a lower-cased path was handed to `git -C`, git
  failed, and the rule fell through to its allow path.
- **The harness's session record format is a vendor contract.** The liveness fence that stops the
  reaper touching an occupied worktree reads per-session records the harness writes. That schema can
  change under you without notice. If it does, the fence reports itself unavailable and nothing is
  pruned, which is the intended direction of failure but is still an outage of the signal.
- **Session listings do not see every session kind.** Sessions relocated into a worktree file their
  transcript under a different key and drop out of the list of the window they were born in.
  `sessions.ps1` is how you find them, and `-Rehome` is how you put one back.
- **Nothing here can prove a session is gone.** There is no heartbeat. Every occupancy verdict is the
  absence of a veto, not a permission.

Run `pwsh -NoProfile -File bin/ccx-doctor.ps1` if you want to know which of the guards described here
are actually installed and enforcing on this machine, rather than merely present in the repository.
