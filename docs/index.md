---
title: claude-multisession
layout: default
---

# claude-multisession

`claude-multisession` is a lightweight, decentralized coordination toolkit for safely running several
Claude Code sessions at once against a single git repository. There is no daemon and no background
service. It rests entirely on native git worktrees, PowerShell 7 scripts, and stdlib-only Python
checkers invoked from ordinary git hooks. Cloning this repository installs nothing.

## How it accelerates Claude Code projects

**True concurrency via git worktrees.** Several agents working in one directory contend for the git
index and overwrite each other's files. Every session instead gets its own isolated worktree on its
own branch, while the repository history -- and the coordination state keyed to it -- stays shared.
See [Worktrees](WORKTREES.md).

**Collision prevention, with the enforcement named.** A `PreToolUse` collision gate refuses an edit
to a file another live session is already changing; that one is a refusal, not a convention. Around
it sit atomic claims, a cross-session lock, and atomic sequence-number allocation, so two sessions
cannot mint the same number for a decision record or an item. Claims are deliberately **advisory**:
they cannot stop a session that refuses to look, which is exactly why the commit-time gate exists
behind them. A cross-session announce lets live sessions broadcast what they are working on -- on
the desktop client only, per limit 1 below. See [Coordination](COORDINATION.md).

**Guardrails that run whether the agent cooperates or not.** The installer writes exactly two git
hooks: `commit-msg` runs the claim gate, and `pre-push` runs the push guard that refuses a direct
push to a protected ref. A worktree gate stops sessions building in the shared primary checkout. The
leak gate and the ASCII gate are scripts you run rather than hooks, and nothing here wires them. The
leak gate refuses to run structural-only when you ask it for an armed pass, so a green result cannot
quietly mean "no detectors were loaded". See [Hooks](HOOKS.md) and [The leak gate](LEAK-GATE.md).

**Assessments too large for one context.** Because a coordinated set of sessions can cover a
codebase at once, the method extends to compliance work -- an OWASP ASVS 5.0 assessment runs to
several hundred requirements, more than one session can hold. The write-up is candid that the
obvious split is the wrong one: dispatching a session per chapter is a scheduling answer, while the
collision that actually costs you is the shared index every session wants to edit. See
[Running a large security-standard assessment](ASVS-ASSESSMENT.md).

**Automated cleanup.** A liveness registry tracks which sessions are actually alive, and the reaper
prunes sibling worktrees that are merged, clean and unoccupied -- and refuses to guess when it
cannot tell which of those a worktree is. See [Pruning](PRUNING.md).

Used this way, Claude Code stops being one sequential pair-programmer and becomes a set of sessions
working the same repository at the same time -- on parallel automation work, deep security reviews,
or a large migration. The limits that decide whether that is worth it to you are stated next, before
any install instructions.

## Sessions that can talk to each other

Most of what follows is about keeping sessions apart. These are the parts that let them coordinate
on purpose, and they are the reason a set of parallel sessions behaves like a team rather than a
crowd.

**Announce: a session tells its peers what it is about to do.**
`scripts/hooks/announce-session.ps1` is a `UserPromptSubmit` hook. When you hand a session a task,
it resolves which peers are live in this repository and asks the model to send each one a short
note -- worktree, branch, one line of intent, one line of what it expects to touch. That note lands
as a user turn inside the peer's session, so a session about to edit the same file learns about you
*before* it starts, not from a merge conflict afterwards. It asks nothing and expects no reply.
Desktop-only, per limit 1 below.

**Steering: change a running session's course without interrupting it.**
`bin/ccx-steer.ps1` queues a note for whichever session is working in a repository, and
`scripts/hooks/steer-inject.ps1` delivers it at that session's next tool call -- mid-task, in
flight. The hook fails open by design: any error inside it exits 0 and never blocks a tool call,
because a steering channel that can wedge a session is worse than no steering channel. See
[Steering a running session](STEERING.md).

**Presence, occupancy, overlap: three questions, answered separately.**
`scripts/coord/presence.ps1` answers who is actually live, across every Claude Code surface.
`occupancy.ps1` answers which worktree each live session is sitting in. `overlap.ps1` answers what
every other session is changing right now -- both the files and the work each one has stated. These
are the queries the announce hook and the collision gate are built on, and they are worth running by
hand when you are deciding whether it is safe to start something. See [Coordination](COORDINATION.md).

### What this defends against, and which part does the defending

The failure is documented upstream in
[anthropics/claude-code#76590](https://github.com/anthropics/claude-code/issues/76590), including a
[field report](https://github.com/anthropics/claude-code/issues/76590#issuecomment-5004149125) of
roughly fourteen sessions being handed the same worktree directory as their working directory. An
agent in one of them runs an ordinary `git checkout -B <branch> origin/main`. Git allows it, because
that branch is not checked out anywhere. The shared working tree force-switches -- swapping every
file under whichever session was mid-task, and dragging its uncommitted work onto the wrong branch.
It is invisible while it happens, because each session believes it owns its directory.

Three mechanisms here touch that failure, and only one of them prevents it:

- **Prevention -- the worktree gate.** `scripts/hooks/worktree_gate.ps1` is a `PreToolUse` hook. Its
  branch-reuse rule refuses an agent's `git checkout`/`git switch` that would move a *linked*
  worktree onto an existing branch another session is building on. The tool call does not run. This
  is the only part that stops the hijack rather than reporting it.
- **Repair -- the SessionStart backstop.** `scripts/worktree/worktree-selfheal.ps1` restores the
  shared *primary* checkout when its HEAD has drifted off the home branch and the tree is clean --
  the parent-HEAD flip that is #76590's headline symptom. When the tree is dirty it declines, says
  so, and touches nothing, because it will not run a checkout over uncommitted work.
- **Detection -- the home-branch record.** Each worktree's home branch is recorded in its private
  git directory, where a checkout cannot move it and removing the worktree disposes of it. A later
  session that finds the worktree on some other branch warns you and offers the restore command. It
  is warn-only and never mutates anything.

**A caveat on the detection half, because it misled us.** When no record exists yet, the backstop
bootstraps one from whatever branch the worktree is on at that moment. If that happens before the
harness has finished moving a newly created worktree onto its session branch, "home" is captured as
the pre-setup branch and the warning then fires on every later session start, forever. Measured here
on 2026-08-05: worktree created at 09:21:50, record written at 09:21:54, harness moved the worktree
to its session branch at 09:23:10. The warning was stale by 76 seconds, not a hijack. Treat that
warning as a prompt to read the worktree's reflog, not as proof that something happened -- a
harness-driven switch during session setup and a genuine hijack look identical in the record until
you check whether an agent's tool call caused it.

## Requirements

- **PowerShell 7.3+** (`pwsh`). Most scripts carry a `#Requires -Version 7.3` line. Without it,
  nothing installs.
- **git**. Everything is keyed on the git common directory. Without it, nothing installs.
- **A `python` on `PATH`** (or `CCX_PYTHON`), for the three git-hook checkers and the leak gate. The
  two git hooks the installer writes are `/bin/sh` shims that exec a stdlib-only Python checker; the
  hand-wired sequence gate and the leak gate are Python too. Without one, the installed git gates are
  OFF and say so on stderr. On Windows a `python` on `PATH` is often an execution-alias stub that
  resolves cleanly and then runs nothing, which is why `-Status` asks the interpreter for its version
  rather than trusting the lookup.
- **`ccx.config.json` at the target repository root** -- both the knob file and the opt-in marker.
  Without it the user-scope hooks stay inert in that repo (the installers still run, and each prints
  a NOTE saying so).

**PowerShell 7 + Windows-first.** Nearly every shipped script is PowerShell, with a handful of
stdlib-only, portable Python checkers. It runs on PowerShell 7 for Linux and macOS, but the Windows
paths are the ones that were exercised, and two behaviours degrade elsewhere: self-marking in the
roster, and path case-folding.

**There is no `ccx` executable on `PATH`.** Every command is a plain script run with `pwsh`; where
the docs say `ccx doctor` it is shorthand for
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`.

MIT licensed. See
[LICENSE](https://github.com/wshallwshall/claude-multisession/blob/main/LICENSE).

---

## Read this before you install

Three limits, up front, because each one changes whether this repo is worth your time.

**1. Announce needs a desktop-only MCP server.** Cross-session announce
(`scripts/hooks/announce-session.ps1`) delivers through the `ccd_session_mgmt` MCP server, which the
desktop client provides. It is **absent on a plain CLI install**. The hook does not send anything
itself -- it resolves peers and asks the model to send. So on a host without that MCP the hook still
fires, still finds peers, and then instructs the model to call tools it does not have. The model says
so, and nothing is delivered. If you are CLI-only, leave that one hook uninstalled. Nothing else here
depends on it.

**2. The liveness fence rests on a vendor contract.** Everything that answers "who is live, and
where" reads `<config-root>/sessions/<pid>.json` -- a record the *client* writes, with `pid`,
`startedAt`, `sessionId`, `cwd`, `entrypoint`, `kind`. This project does not own its shape, its
location, or its lifetime. If a future client renames a field or changes `startedAt`'s unit, every
fence here degrades to "cannot tell" rather than to a confident wrong answer. That is designed for,
in `scripts/coord/session-registry.ps1`. And the doctor reports how many records it read and placed,
so a schema change shows up as a count going to zero instead of as a silent all-clear.

**3. The desktop app's own session list cannot see every session.** Its `list_sessions` tool
enumerates an in-memory map of the sessions *that app itself spawned*. A session launched by the
editor extension is never entered into it -- not filtered out, never registered -- so it is invisible
there and cannot be messaged. Verified directly against a live editor session sharing the default
config root, so it is not a per-login split. Treat `list_sessions` as authoritative for who can be
**messaged**, and the on-disk session records as the only registry that answers who **exists**.

And the meta-limit that motivates the rest:

> **Every failure mode in this system is byte-identical to success.** A hook that is wired but
> resolves nothing exits 0 and prints nothing -- which is exactly what a healthy hook with no peers
> does. A gate whose helper failed to load allows the edit -- which is exactly what a gate that
> checked and found nothing does. You cannot detect a difference the producer never encoded. That is
> why `ccx doctor` exists, why it runs both before any installer and after all of them, and why it
> *fires each control on purpose* instead of reading a settings file.

One more thing to be clear about before you weigh any of it: **these are guardrails against the
accidental action, not security boundaries.** The `PreToolUse` gates inspect tool arguments, so a
file written by a shell command is invisible to them. Any agent-authored script defeats a
command-string rule outright. And `git commit --no-verify` and `git push --no-verify` bypass the git
hooks. No CI-side enforcement is shipped.

---

## Five minutes

**Two directories are involved, and every command below says which one it means.**

| Name | What it is |
|---|---|
| **tooling** | This checkout. Nothing you install governs *it*; it is only where the scripts are copied from and hashed against. |
| **target** | The repository you want governed. It gets the config file, the git hooks, and its primary checkout in the gate's allowlist. |

Decide first whether the two are one directory, because it decides how much of this works. In the
**vendored** layout, `scripts/`, `bin/` and `ccx.config.json` are copied into the repository they
govern and committed there -- tooling *is* target. That is the only layout in which the doctor can
reach exit 0. In the **separate checkouts** layout the worktree gate, both git hooks and the
SessionStart backstop still govern the target. But the three coordination hooks are shims that locate
their script inside whatever repository the session is running in. So a target that does not carry
those files gets three hooks that are wired and resolve nothing.

Run all of this from a **plain terminal**. All four installers refuse when `$env:CLAUDECODE` is `1`,
because a session that can install these controls can remove them (`-Status` is exempt everywhere it
exists).

The short path is below.
[INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) is the record
of record for the installers -- it carries the annotated version of these same steps, and how to
prove each one is live rather than merely merged.

```powershell
$tooling = "<path-to-this-checkout>"
$target  = "<path-to-the-repo-you-want-governed>"
Set-Location $target      # the doctor reports what it resolves FROM HERE, so stand in the target

# 1. Opt the target in, and -- for the vendored layout -- give it the scripts the coordination
#    hooks resolve.
Copy-Item "$tooling/ccx.config.json" "$target/ccx.config.json"   # then edit it
Copy-Item "$tooling/scripts" $target -Recurse                    # vendored layout only
Copy-Item "$tooling/bin" $target -Recurse                        # vendored layout only
# ...then commit them, so every worktree of the target gets them. After vendoring there are two
# copies of these scripts on disk: install and audit from ONE of them. Installing from one and
# hashing against the other is exactly the drift the doctor calls STALE.

# 2. Baseline, BEFORE installing anything: it is the only way to tell an installed guardrail from a
#    decorative one afterwards. Expect a wall of OFF and exit 1. That is the correct baseline.
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target

# 3. Coordination hooks: session banner, collision gate, announce. This installer takes NO
#    repository -- it writes ONE settings file, whose hooks resolve their repo per session at run
#    time. -SettingsPath is the only thing that moves it; pass it once per config root.
pwsh -NoProfile -File "$tooling/scripts/coord/install-coordination.ps1"

# 4. The commit-msg claim gate and the pre-push guard, into the TARGET clone's shared .git/hooks,
#    where one copy governs every worktree of that clone at once. The checkers are copied from the
#    tooling checkout, so the target never has to carry them.
pwsh -NoProfile -File "$tooling/scripts/coord/install-git-hooks.ps1" -RepoRoot $target

# 5. The worktree gate. -Repo names the PRIMARY checkout to put in the allowlist (several are
#    allowed: -Repo <path-a>,<path-b>). The allowlist is the kill switch.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-gate.ps1" -Repo $target

# 6. The SessionStart backstop. ONE config root per run, so run it again for each root the doctor
#    lists under "config roots" -- an unwired root is reported OFF, and OFF is exit 1.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-selfheal.ps1" -ConfigDir ~/.claude

# 7. Prove it -- and prove it about the right repository.
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target
```

### Prove the repository it governed is the one you meant

The doctor's own default target is the current directory, so a run started in the wrong place
produces a long, plausible, mostly-green report about the wrong clone. Read back the two roots it
names at the top of every run, the allowlist actually containing that primary, and the installed gate
being handed a write to that path and refusing it:

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target |
    Select-String 'repo examined|tooling checkout|gate: allowlist|LIVE allowlist'
```

Then create your second session's worktree. These two are not installers and take no target flag:
they act on the primary of **the repository you are standing in**, so keep standing in the target.

```powershell
pwsh -NoProfile -File "$tooling/scripts/worktree/new.ps1" -Name alerts
# ...or create it and open an editor window in it:
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name alerts
```

---

## What ships

Paths below are relative to this checkout. Browse them in the
[repository](https://github.com/wshallwshall/claude-multisession).

### The one command that proves the rest

| Script | Does | Doc |
|---|---|---|
| `bin/ccx-doctor.ps1` | Prove -- by receipt and by attack -- that each control is installed, wired, and refuses what it can be made to refuse. It never infers, always prints WHAT WAS SCANNED and BLIND SPOTS ON THIS RUN, and a skip is never a pass (exit 2). At least one deny path is not self-testable: the collision gate's needs a live peer worktree holding an uncommitted change to the same file, so the doctor proves only that the gate refuses to go *silent*, and prints that as a blind spot on every run | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |

### Controls the harness or git invokes

| Script | Does | Doc |
|---|---|---|
| `scripts/hooks/worktree_gate.ps1` | `PreToolUse` gate denying writes whose target path is inside a governed primary, dispatch from the primary, and the git verbs that swap or discard its tree. Fails open, but loudly | [Hooks](HOOKS.md) |
| `scripts/hooks/collision_gate.ps1` | `PreToolUse` gate on the edit tools that refuses a file a live session is already changing. Fails open -- never silently | [Coordination](COORDINATION.md) |
| `scripts/hooks/announce-session.ps1` | `UserPromptSubmit` hook telling peers you exist and what you intend, on the first prompt at which a messageable peer exists. Always exits 0; delivery depends on the desktop-only MCP server | [Coordination](COORDINATION.md) |
| `scripts/worktree/session-context.ps1` | `SessionStart` banner: your project's working defaults plus a live coordination block. Its stdout is the chat's starting context, so it never fails loudly | [Hooks](HOOKS.md) |
| `scripts/worktree/worktree-selfheal.ps1` | `SessionStart` backstop repairing a primary whose HEAD drifted, when the tree is clean -- the most privileged control in the set, whose only safety property is that it refuses a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/hooks/claim_check.py` | `commit-msg` hook refusing a code-touching commit whose subject claims an item this worktree does not hold. Fail-closed | [Coordination](COORDINATION.md) |
| `scripts/hooks/push_guard.py` | `pre-push` hook refusing a direct push of a protected ref. An explicitly empty `protectedRefs` list disables it with a message on stderr | [PRs and merges](PR-AND-MERGE.md) |
| `scripts/hooks/seq_check.py` | `pre-commit` checker refusing a colliding, unallocated, or unindexed sequence number; `--ci` re-runs the collision rules against a freshly fetched trunk. No installer wires it | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `scripts/hooks/block-blanket-git-stage.ps1` | Opt-in `PreToolUse` guard on the shell tools, denying `git add -A/--all/-u/.` and `git commit -a/-am`. Fails open | [Hooks](HOOKS.md) |
| `scripts/hooks/steer-inject.ps1` | Opt-in-per-worktree `PreToolUse` hook on `*` that delivers a queued steering note at the next tool-call boundary rather than at the end of the turn | [Steering](STEERING.md) |

### Commands you run

| Script | Does | Doc |
|---|---|---|
| `scripts/worktree/new.ps1` | Create an isolated worktree on its own branch, off the fetched remote tip, serialised against concurrent adds | [Worktrees](WORKTREES.md) |
| `scripts/worktree/spawn.ps1` | `new.ps1` plus an editor window (`-Editor`, else `CCX_EDITOR`, else `EDITOR`, else `code`) | [Worktrees](WORKTREES.md) |
| `scripts/worktree/rescue.ps1` | Move uncommitted work out of the shared primary into a fresh worktree -- the companion to the gate that stops you writing there | [Worktrees](WORKTREES.md) |
| `scripts/worktree/restore-primary.ps1` | Re-attach the primary to its home branch after a session left it detached or on the wrong branch. Refuses on a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/worktree/remove.ps1` | Remove one worktree, referencing its tip before anything is removed, and writing a keep-ref when `-DeleteBranch` is used | [Pruning](PRUNING.md) |
| `scripts/worktree/prune-merged.ps1` | The reaper: prune = merged **and** clean **and** unoccupied. Dry-run by default, `-Apply` to act. Carries a second, non-cwd signal and prints its blind spots | [Pruning](PRUNING.md) |
| `scripts/worktree/sessions.ps1` | Find sessions for this repo across every login, including ones a relocation made invisible; `-Rehome` puts a transcript back | [Worktrees](WORKTREES.md) |
| `scripts/coord/presence.ps1` | Who is actually live in this repo right now, across every surface. Read-only | [Coordination](COORDINATION.md) |
| `scripts/coord/overlap.ps1` | What everyone else is changing -- files and stated work. `-File <path>`, `-Json`; cached, so the gate's common case is a cache read | [Coordination](COORDINATION.md) |
| `scripts/coord/claim.ps1` | Take, release or list an atomic claim on a piece of work, so a session about to build something a peer already holds finds out before the work rather than at merge. Advisory: a claim cannot stop a session that refuses to look. Claims do not expire and releasing is manual, on purpose | [Coordination](COORDINATION.md) |
| `scripts/coord/alloc.ps1` | Allocate the next number in a shared sequence atomically, so two sessions that both allocate can never be handed the same one; `-ShowFloor` inspects without spending one. The commit-time gate (`seq_check.py`) is the other half -- neither is sufficient alone | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `bin/ccx-steer.ps1` | Queue a steering note from a second terminal while a session is mid-task | [Steering](STEERING.md) |
| `scripts/security/scan_forbidden.py` | The leak gate: refuse identifying content before a private repo goes public. `--path DIR`, `--require-tokens`, `--show-context`. Nothing here wires it | [Leak gate](LEAK-GATE.md) |

### The single copies everything else uses

| Script | Does | Doc |
|---|---|---|
| `scripts/coord/session-registry.ps1` | The liveness fence: reads the client's session registry and decides whether a session is actually alive. Liveness may only VETO, never PERMIT -- DEAD/STALE/absent is the absence of a veto, not a permission | [Concepts](CONCEPTS.md) |
| `scripts/coord/occupancy.ps1` | The one cwd-to-worktree matcher, returning a receipt alongside its rows (roots examined, records examined, records that could not be placed) and setting `Available` only when there was something to examine | [Concepts](CONCEPTS.md) |
| `scripts/coord/lock.ps1` | The short-lived cross-session mutex, dot-sourced rather than run: `. lock.ps1` then `Enter-CcxLock` / `Exit-CcxLock`. `new.ps1` uses it to serialise `git worktree add`. There are no TTLs anywhere: locks retry and never steal, and on timeout they fail loudly and name the holder | [Concepts](CONCEPTS.md) |

### Installers, and why there are four

| Script | Does | Doc |
|---|---|---|
| `scripts/coord/install-coordination.ps1` | Wires the session banner, collision gate and announce at user scope as shims that re-resolve at run time; writes exactly one settings file per run (`-SettingsPath`) | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |
| `scripts/coord/install-git-hooks.ps1` | Installs `commit-msg` + `pre-push` into one clone's shared `.git/hooks` (`-RepoRoot`), refuses to overwrite a foreign hook, and never writes `pre-commit` at all | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |
| `scripts/worktree/install-gate.ps1` | Installs the worktree gate as a copy outside every working tree, into every config root it finds, plus the allowlist that is its kill switch (`-Repo`, `-ConfigDir`) | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |
| `scripts/worktree/install-selfheal.ps1` | Wires the SessionStart backstop into ONE config root per run; `-ConfigDir` is mandatory, and it governs whatever the gate's allowlist already names | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |

---

## Where to go next

Start with the model, then the control surface:

- [Concepts](CONCEPTS.md) -- worktree per session, one shared state root every worktree of a clone
  resolves identically, a liveness fence that may only ever veto, exclusive-create instead of
  read-modify-write, the deliberate absence of TTLs, and the six knobs in `ccx.config.json`.
- [Hooks](HOOKS.md) -- harness hooks versus git hooks, every shipped control mapped to its event,
  matcher and fail-open or fail-closed posture, and the house rules for writing a hook that cannot
  fail silently.

Running sessions, in the order the work happens:

- [Worktrees](WORKTREES.md) -- create, rescue, restore and remove, and the two layouts that coexist
  on a real machine while only one has scripted teardown.
- [Coordination](COORDINATION.md) -- presence, overlap, claims, locks and announce, with its limits
  stated first.
- [Steering](STEERING.md) -- reaching a session that is already mid-task, and what the fail-open
  posture costs.
- [Sequence allocation](SEQUENCE-ALLOC.md) -- the one collision class every other control here is
  blind to, and the two halves that fix it.
- [PRs and merges](PR-AND-MERGE.md) -- the four different states that all read as "can't merge", and
  what a squash-merging trunk does to every reachability test.
- [Pruning](PRUNING.md) -- merged AND clean AND not occupied, where occupancy is a veto and never a
  permission.

Safety and standards, in descending order of how much actually ships:

- [Leak gate](LEAK-GATE.md) -- a stdlib-only scanner you can run today, plus the permanent blind spot
  no scanner can close.
- [CI and standards](CI-AND-STANDARDS.md) -- why a green local quartet is not a green pipeline, and
  the standards that keep agent-written work honest. Ships no CI configuration.
- [Usage awareness](USAGE-AWARENESS.md) -- the design for warning a session before a hard cutoff, and
  the eight rules that stop it reporting confidently wrong numbers. Ships no hook.

Standards to adapt, in [a section of their own](standards/OVERVIEW.md). Four documents setting a bar
for code an agent wrote and a small team has to stand behind. They ship no code and confer no
certification; they came out of one working codebase and carry its assumptions, which the section
index states before anything else. Read that index first -- it says what each one buys you, the
order to take them in, and which rules the pages above already own:

- [AI-assisted development](standards/AI-ASSISTED-DEVELOPMENT.md) -- five process failure modes, a
  risk tier you resolve in one question, and why a gate is a deterministic check rather than an
  instruction to the model to be careful.
- [Dependency integrity](standards/DEPENDENCY-INTEGRITY.md) -- holding third-party code as a black
  box you deliberately do not read, and shipping a build whose contents an adopter can verify
  themselves.
- [Code quality](standards/CODE-QUALITY.md) -- controls that may decide a verdict, measurements that
  may only start a conversation, and review depth as a per-file decision.
- [Secure development](standards/SECURE-DEVELOPMENT.md) -- who owns which control when you build
  software someone else runs, and the process layer a self-run pipeline cannot discharge.

In practice:

- [Tips and tricks](TIPS-AND-TRICKS.md) -- the "wish I'd known" collection, ordered by when each item
  bites.
- [Drift audit case study](CASE-STUDY-drift-audit.md) -- a redacted account of auditing the whole
  path from checkout to decision. A method document; it carries no status table or finding list, on
  purpose.
- [Security standard assessment](ASVS-ASSESSMENT.md) -- a method for scoring a codebase against a
  several-hundred-requirement standard when most of the scoring is done by agent sessions. It
  publishes no results, deliberately.

Outside this doc set, at the repository root:
[INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) is the record
of record for the installers, and
[CLAUDE.md.template](https://github.com/wshallwshall/claude-multisession/blob/main/CLAUDE.md.template)
is a working agreement to drop into your own repository.
