---
title: KORUS
layout: default
---

# KORUS

## TLDR/BLUF

**What this is.** A way to run four Claude Code sessions against one repository at once without them
overwriting each other. KORUS is the build shape -- a dispatcher, two builders and a lander -- and
`claude-multisession` is the tooling that enforces the parts a convention cannot.

**Why you should care.** Four sessions is real throughput until two collide in a way git cannot
report as a conflict. Those collisions touch no shared bytes, so every branch merges clean and the
loss lands later. Not for you if you run one session at a time.

**How to use it.** [Quickstart](QUICKSTART.md) installs it and ends with you watching a collision
get refused. [Run a KORUS build](KORUS-BUILD.md) is the four-session shape.
[The KORUS framework](KORUS.md) is the account it all came from.

---

## What goes wrong without it

Two sessions are running. Session A is halfway through a refactor, with uncommitted work in the
tree. Session B decides it needs a fresh branch:

```powershell
git checkout -B feature/parser origin/main
```

Git allows it. The branch is checked out nowhere, so that is a legal command. The shared tree
force-switches, every file under session A becomes a different commit's file, and A's uncommitted
work is now on the wrong branch.

**Nothing on either screen says so.** Each session believes it owns the directory.

That is the loudest failure, not the only one. Six more -- same file, same work in different files,
same reserved number, same config lock, same shared list, same agent memory -- are tabulated in the
[README](https://claude-multisession.pages.dev/README.md), *"What problem this solves"*.

The one that costs most is the quietest. Two sessions build the *same thing* in *different files*:
zero conflicts, two green pull requests, one of them thrown away.

Upstream, this is [claude-code#76590](https://github.com/anthropics/claude-code/issues/76590), with
a [field report](https://github.com/anthropics/claude-code/issues/76590#issuecomment-5004149125) of
roughly fourteen sessions on one directory.

## What it looks like when it works

<figure role="group">
<svg viewBox="0 0 820 210" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Two session lanes on a shared timeline. Session A edits service.py and leaves the change uncommitted. Session B then reaches for the same file and the collision gate refuses the edit before it runs, naming who holds the file. Session B edits parser.py instead, and both branches land.">
  <defs>
    <marker id="ix-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
    </marker>
  </defs>
  <text x="12" y="52" font-size="12" font-weight="bold" fill="currentColor">Session A</text>
  <line x1="100" y1="46" x2="780" y2="46" stroke="currentColor" stroke-width="1" marker-end="url(#ix-arrow)" />
  <rect x="120" y="26" width="200" height="40" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="220" y="43" font-size="11" text-anchor="middle" fill="currentColor">edits service.py</text>
  <text x="220" y="59" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">left uncommitted</text>
  <text x="12" y="158" font-size="12" font-weight="bold" fill="currentColor">Session B</text>
  <line x1="100" y1="152" x2="780" y2="152" stroke="currentColor" stroke-width="1" marker-end="url(#ix-arrow)" />
  <rect x="340" y="132" width="190" height="40" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 3" />
  <text x="435" y="149" font-size="11" text-anchor="middle" fill="currentColor">reaches for service.py</text>
  <text x="435" y="165" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">the tool call never runs</text>
  <line x1="435" y1="130" x2="435" y2="92" stroke="currentColor" stroke-width="1.5" marker-end="url(#ix-arrow)" />
  <rect x="330" y="74" width="210" height="30" rx="6" fill="none" stroke="currentColor" stroke-width="2" />
  <text x="435" y="94" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">REFUSED, with the reason</text>
  <rect x="570" y="132" width="190" height="40" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="665" y="149" font-size="11" text-anchor="middle" fill="currentColor">edits parser.py instead</text>
  <text x="665" y="165" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">both branches land</text>
  <text x="12" y="196" font-size="10" font-style="italic" fill="currentColor">Without the gate, B's write lands and one of the two loses work at merge -- with nothing on either screen saying so.</text>
</svg>
<figcaption>The refusal happens at edit time, before the write, and names who holds the file. Without
it both writes succeed and the loss surfaces at merge, or later.</figcaption>
</figure>

## What you get

**Sessions that cannot overwrite each other.** Each one works in its own git worktree on its own
branch, while the repository history stays shared. [Worktrees](WORKTREES.md)

**A refusal at edit time, not a conflict at merge time.** When a session reaches for a file another
live session has uncommitted changes in, the edit is refused before it runs, and the refusal names
who is in that file and what they are building. [Coordination](COORDINATION.md)

**Guardrails that hold whether the agent cooperates or not.** A commit whose subject claims work
this worktree does not hold is refused. So is a direct push to a protected branch.
[Hooks](HOOKS.md)

**Numbers that cannot be handed out twice.** Two sessions asking for the next free decision-record
number get different ones, because allocation is an atomic create rather than a read and a write.
[Sequence allocation](SEQUENCE-ALLOC.md)

**Cleanup that declines rather than guesses.** Worktrees are pruned only when they are merged
**and** clean **and** unoccupied, and the reaper stops when it cannot tell which of those a worktree
is. [Pruning](PRUNING.md)

**A shape for the work itself.** One session plans and tracks, two build, one lands. The roles are
what stop two sessions deciding the same thing. [Run a KORUS build](KORUS-BUILD.md)

### What actually stops the failure above

Three mechanisms touch it. Only the first prevents it.

| Role | Script | What it does |
|---|---|---|
| **Prevention** | `scripts/hooks/worktree_gate.ps1` | Refuses the git verbs that would swap or discard the shared primary checkout's tree. The tool call does not run. |
| **Repair** | `scripts/worktree/worktree-selfheal.ps1` | Restores the primary when its HEAD has drifted and the tree is clean. On a dirty tree it declines and touches nothing. |
| **Detection** | the home-branch record | Kept where a checkout cannot move it. A later session finding the worktree elsewhere warns and offers the restore command. Warn-only, and [wrong by design](WORKTREES.md#the-sidecar-home-branch-record-is-wrong-by-design). |

## Start here

| If you want to | Go to |
|---|---|
| See it working on your own repository | [Quickstart](QUICKSTART.md) |
| Set up the four-session build | [Run a KORUS build](KORUS-BUILD.md) |
| Know what it needs, and where it stops working | [Limits and requirements](LIMITS.md) |
| Understand the model everything else applies | [Concepts](CONCEPTS.md) |
| Read the account this came from | [The KORUS framework](KORUS.md) |
| Have Claude Code assess your own repository | [Feed this to Claude Code](FEED-THIS-TO-CLAUDE-CODE.md) |

Nothing beyond `pwsh`, `git` and a `python`. PowerShell 7, Windows-first, MIT. Cloning installs
nothing.

## What it costs you

**These are guardrails against accidents, not security boundaries.** The edit-time gates read tool
arguments, so a file written by a shell command is invisible to them, and `--no-verify` bypasses
both git hooks.

**Everything here fails the same way it succeeds.** An uninstalled gate and a working one look
identical from inside a session, because both let the edit through. That is why `ccx doctor` exists
and why you run it before installing as well as after.

**Announce needs the desktop client.** On a CLI-only install, leave that one hook uninstalled.
Nothing else depends on it.

The full statement, with the requirements table and the three consequences of building on a vendor
surface this project does not own, is on [Limits and requirements](LIMITS.md).

## Where to go next

**Running sessions.** [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) owns three things no
other page does: which surface to run on, the channels sessions reach each other on, and the lander
role.

[Desktop accounts](DESKTOP-ACCOUNTS.md) is the setup step before any of it, if you run more than one
Claude account.

Then, in the order the work happens: [Worktrees](WORKTREES.md) - [Coordination](COORDINATION.md) -
[Steering](STEERING.md) - [Sequence allocation](SEQUENCE-ALLOC.md) -
[PRs and merges](PR-AND-MERGE.md) - [Pruning](PRUNING.md).

**Every script, and what it does.** [The inventory](SCRIPTS.md), grouped by what you are trying to
do. The site serves each script at its own path, so
[/scripts/coord/claim.ps1](https://claude-multisession.pages.dev/scripts/coord/claim.ps1) needs no
clone.

**Safety,** in descending order of how much actually ships:

- [Leak gate](LEAK-GATE.md) -- a scanner you can run today, plus the blind spot no scanner closes.
- [Usage awareness](USAGE-AWARENESS.md) -- a design; ships no hook.
- [Session mail](SESSION-MAIL.md) -- how to build the lane that reaches the peers announce cannot.

**In practice:** [Tips and tricks](TIPS-AND-TRICKS.md), ordered by when each item bites.
[Drift audit](CASE-STUDY-drift-audit.md) is a method rather than a finding list.
[Correction chain](CASE-STUDY-correction-chain.md) covers one finding, four statements, three wrong.

**The standards are a separate project now.**
[secure-development-standards](https://secure-development-standards.pages.dev/) holds what used to
live here: a bar for agent-written code, plus its CI discipline and assessment method.

**The long form:** [Install](INSTALL.md) is the record of record for the installers -- every scope,
and how to prove each one is live rather than merely merged.
[CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template)
is a working agreement to drop into your own repository.
