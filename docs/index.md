---
title: KORUS
layout: default
---

# KORUS

## TLDR/BLUF

**What this is.** KORUS -- Keep One Repo, Unblock Sessions -- is one developer's account of what
makes Claude Code productive on a real project. It covers the model and effort to run, what the
accounts cost, what to write down, and running several sessions without collisions.

`claude-multisession` is the tooling that enforces that last part.

**Why you should care.** Several sessions at once is how a build gets dramatically faster. The only
thing in the way is them conflicting, and the conflicts that cost you are the ones git cannot report:
every branch merges clean, and the loss lands later.

Not for you if Claude Code is an occasional convenience rather than how the project gets built.
KORUS also assumes Claude Code for Desktop throughout.

**What it costs.** You copy this project's `scripts/`, `bin/` and `ccx.config.json` into your own
repository and **commit** them, then edit two keys in the shipped config.

One allowlist file lands under your user config root, per machine rather than per repository.
Cloning alone installs nothing.

**How to use it.** [Quickstart](QUICKSTART.md) installs the enforcement and ends with you watching a
collision get refused. [Run a KORUS build](KORUS-BUILD.md) is the session shape.
[The KORUS framework](KORUS.md) is the whole account, in its author's words.

---

## What goes wrong without it

Two sessions are running. Session A is halfway through a refactor, with uncommitted work in the
tree. Session B decides it needs a fresh branch:

<!-- no-copy -->
```powershell
git checkout -B feature/parser origin/main
```

Git allows it. The branch is checked out nowhere, so that is a legal command. The shared tree
force-switches, every file under session A becomes a different commit's file, and A's uncommitted
work is now on the wrong branch.

**Nothing on either screen says so.** Each session believes it owns the directory.

That is the loudest failure, not the only one. Six more: same file, same work in different files,
same reserved number, same config lock, same shared list, same agent memory.

The one that costs most is the quietest. Two sessions build the *same thing* in *different files*:
zero conflicts, two green pull requests, one of them thrown away.

Upstream, this is [claude-code#76590](https://github.com/anthropics/claude-code/issues/76590), with
a [field report](https://github.com/anthropics/claude-code/issues/76590#issuecomment-5004149125) of
roughly fourteen sessions on one directory.

**Claude Code now blocks much of that itself**, for a session started with `--worktree` and for Bash.
It does not stop two isolated sessions colliding with each other. For PowerShell it checks only
where the command runs, not where git points -- [which half you need](FAQ.md).

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

## What the tooling enforces

This is the part a convention cannot hold on its own, so it ships as code.

**Sessions that cannot overwrite each other.** Each one works in its own git worktree on its own
branch, while the repository history stays shared. [Worktrees](WORKTREES.md)

**A refusal at edit time, not a conflict at merge time.** When a session reaches for a file another
live session has uncommitted changes in, the edit is refused before it runs, and the refusal names
who is in that file and what they are building. [Coordination](COORDINATION.md)

**Guardrails at commit and push time.** A commit whose subject claims work this worktree does not
hold is refused. So is a direct push to a protected branch. Both are skipped by `--no-verify`, which
leaves no local record, so pair them with protection on the remote. [Hooks](HOOKS.md)

**Numbers that cannot be handed out twice, if both sessions ask.** `alloc.ps1` claims a number by an
atomic create, so two sessions asking for the next free number get different ones.

The commit-time gate catching a session that never asked ships **unwired**: no installer writes
`pre-commit`, and the doctor reports it `OFF` until you do. [Sequence allocation](SEQUENCE-ALLOC.md)

**Cleanup that declines rather than guesses.** Worktrees are pruned only when merged **and** clean
**and** unoccupied, and the reaper stops wherever it *knows* it cannot tell.

It prints, every run, the four cases where it cannot tell and does not know it. An occupant editing
by absolute path from elsewhere is one. [Pruning](PRUNING.md)

That list is what ships as code. **The session shape is not on it.** One session briefs and
polls. A short-lived one builds each brief, another reads the diff, another attributes a failed
check, and one decides what merges. Nothing enforces any of that.

The roles are a convention you set in each opening prompt, and they are what stop two sessions
deciding the same thing. [Run a KORUS build](KORUS-BUILD.md)

Three mechanisms touch the failure at the top of this page, and only the worktree gate prevents it.
[Worktrees](WORKTREES.md#what-actually-stops-the-failure) has the three, and what each cannot do.

## The rest of the framework

The tooling above is one part of KORUS. The rest is convention, and it is where most of the
throughput comes from.

| Part | What it decides | Where |
|---|---|---|
| Model and effort | Which model to run, and why the slower setting still wins | [The KORUS framework](KORUS.md) |
| Surface | One desktop instance per Claude account, and the config root each adds | [Desktop accounts](DESKTOP-ACCOUNTS.md) |
| Account economics | What a plan buys, measured against published API rates | [Token accounting](TOKEN-ACCOUNTING.md) |
| What you write down | A backlog, decision records, and a security register | [The KORUS framework](KORUS.md) |
| The session shape | Who briefs, who builds, who reviews, who merges | [Run a KORUS build](KORUS-BUILD.md) |
| Not losing work to a limit | Knowing when to stop. A design here, not a shipped hook | [Usage awareness](USAGE-AWARENESS.md) |
| What "done" means | The check that runs when the author cannot vouch for the change | [CI for leaders](CI-FOR-LEADERS.md) |

## Start here

| If you want to | Go to |
|---|---|
| Work out whether you need this at all | [FAQ](FAQ.md) |
| See it working on your own repository | [Quickstart](QUICKSTART.md) |
| Set up the session shape | [Run a KORUS build](KORUS-BUILD.md) |
| Know what it needs, and where it stops working | [Limits and requirements](LIMITS.md) |
| Understand the model everything else applies | [Concepts](CONCEPTS.md) |
| Read the account this came from | [The KORUS framework](KORUS.md) |
| Have Claude Code assess your own repository | [Feed this to Claude Code](FEED-THIS-TO-CLAUDE-CODE.md) |

## What it costs you

**These are guardrails against accidents, not security boundaries.** The edit-time gates read tool
arguments, so a file a shell command writes is invisible to them.

**Everything here fails the same way it succeeds.** An uninstalled gate and a working one look
identical from inside a session, because both let the edit through. That is why the doctor exists,
and why you run it before installing as well as after:

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-govern>
```

There is no `ccx` on `PATH`. When a red or undetermined row comes back,
[Troubleshooting](TROUBLESHOOTING.md) is the symptom table.

**KORUS assumes the desktop client throughout.** A CLI-only or editor-extension setup is not
supported. [Limits and requirements](LIMITS.md) carries the requirements table, the platform matrix,
and what each control cannot see.

## Where to go next

**Running sessions.** [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) owns the channels
sessions reach each other on, and the lander role.

[Desktop accounts](DESKTOP-ACCOUNTS.md) is the setup step before any of it, if you run more than one
Claude account.

Then, in the order the work happens: [Worktrees](WORKTREES.md) - [Coordination](COORDINATION.md) -
[Steering](STEERING.md) - [Sequence allocation](SEQUENCE-ALLOC.md) -
[PRs and merges](PR-AND-MERGE.md) - [Pruning](PRUNING.md).

**Every script, and what it does.** [The inventory](SCRIPTS.md) -- what each one is for, and the
page that owns it.

**Safety,** in descending order of how much actually ships:

- [Leak gate](LEAK-GATE.md) -- a scanner you can run today, plus the blind spot no scanner closes.
- [Usage awareness](USAGE-AWARENESS.md) -- a design; ships no hook.
- [Session mail](SESSION-MAIL.md) -- how to build the lane that reaches the peers announce cannot.

**In practice:** [Tips and tricks](TIPS-AND-TRICKS.md), ordered by when each item bites. Three case
studies: [Drift audit](CASE-STUDY-drift-audit.md),
[Correction chain](CASE-STUDY-correction-chain.md), and
[a claim three verifiers refuted](CASE-STUDY-refuted-but-true.md).

**Elsewhere:** [Install](INSTALL.md) is the installer reference -- every scope, and how to prove
each control is live.
[CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template) is a working
agreement for your own repository.

The standards moved to
[secure-development-standards](https://secure-development-standards.pages.dev/).
