---
title: claude-multisession
layout: default
---

# claude-multisession

## TLDR/BLUF

**What this is.** Several Claude Code sessions on one repository, without overwriting each other.
Each gets its own git worktree and branch; hooks refuse colliding edits, commits and pushes. Nothing
beyond `pwsh`, `git` and a `python`. PowerShell 7, Windows-first, MIT. Cloning installs nothing.

**Why you should care.** Several sessions on one repository is real throughput until two collide in
a way git cannot report as a conflict. Most such collisions touch no shared bytes, so every branch
merges clean. The loss lands later, on work built from assumptions that had stopped being true.

What ships against that:

- a worktree per session, and gates that refuse the colliding edit, commit and push;
- claims, cross-session locks and atomic sequence allocation, so two sessions cannot be handed the
  same decision-record number;
- a channel peers reach each other on before the work, and a reaper that declines rather than
  guesses.

Not for you if you run one session at a time.

**How to use it.** [Quickstart](#quickstart) - [Limits](#limits-read-before-installing) -
[What ships](#what-ships) - [Full docs](#where-to-go-next). Or have Claude Code
[read this page](FEED-THIS-TO-CLAUDE-CODE.md): it reads your repository and names the collisions you
have.

---

## The problem

Several agents in one working directory overwrite each other's files --
[claude-code#76590](https://github.com/anthropics/claude-code/issues/76590), with a
[field report](https://github.com/anthropics/claude-code/issues/76590#issuecomment-5004149125) of
roughly fourteen sessions on one directory.

An agent runs `git checkout -B <branch> origin/main`. Git allows it: the branch is checked out
nowhere. The shared tree force-switches, swapping every file under a mid-task session and dragging
its uncommitted work onto the wrong branch. Nobody sees it: each session believes it owns its
directory.

It is the loudest collision, not the only one: six more -- same file, same work in different files,
same reserved number, same config lock, same shared list, same agent memory -- are tabulated in the
[README](https://claude-multisession.pages.dev/README.md), *"What problem this solves"*.

## What you get

**A worktree per session.** Every session works in its own checkout on its own branch, while the
repository history -- and the coordination state keyed to it -- stays shared.
[Worktrees](WORKTREES.md)

**Edits that collide are refused, not merged.** A `PreToolUse` collision gate refuses an edit to a
file another live session is already changing. Claims are advisory -- they cannot stop a session
that refuses to look, so the commit-time gate sits behind them. [Coordination](COORDINATION.md)

**Guardrails that hold whether the agent cooperates or not.** Two git hooks: `commit-msg` runs the
claim gate, `pre-push` refuses a direct push to a protected ref. A worktree gate stops sessions
building in the shared primary checkout. [Hooks](HOOKS.md)

**Sessions that can reach each other.** Announce tells peers what you will touch *before* you start.
Steering redirects a running session mid-task. Presence, occupancy and overlap answer separately:
who is live, which worktree, what changes. [Coordination](COORDINATION.md),
[Steering](STEERING.md)

**Cleanup that refuses to guess.** A liveness registry tracks which sessions are actually alive; the
reaper prunes worktrees that are merged **and** clean **and** unoccupied, and declines when it cannot
tell which of those a worktree is. [Pruning](PRUNING.md)

**Work too large for one context.** An OWASP ASVS 5.0 assessment runs to several hundred
requirements, more than one session can hold. The cost is **different unwritten rules**: verdicts
nobody can reconcile.
[Large assessments](https://secure-development-standards.pages.dev/ASVS-ASSESSMENT.html)

### Which part defends against #76590

Three mechanisms touch that failure. Only the first prevents it:

| | Script | What it does |
|---|---|---|
| **Prevention** | `scripts/hooks/worktree_gate.ps1` | A `PreToolUse` hook. Refuses the git verbs that would swap or discard the shared **primary** checkout's tree -- that is the tree #76590 flips, and the rule that stops it. A separate rule refuses a `git checkout`/`git switch` that would hijack another session's *linked* worktree. Either way the tool call does not run. |
| **Repair** | `scripts/worktree/worktree-selfheal.ps1` | Restores the shared *primary* checkout when its HEAD has drifted and the tree is clean. On a dirty tree it declines, says so, and touches nothing. |
| **Detection** | the home-branch record | Recorded in each worktree's private git directory, where a checkout cannot move it. A later session finding the worktree elsewhere warns and offers the restore command. Warn-only; it is [wrong by design](WORKTREES.md#the-sidecar-home-branch-record-is-wrong-by-design), so treat a warning as a prompt to read the reflog, not as proof. |

---

## Limits, read before installing

**Session discovery rests on a vendor surface this project does not own.** Everything answering "who
is live, and where" reads `<config-root>/sessions/<pid>.json` -- a record the *client* writes, whose
shape, location and lifetime belong to the client. Three consequences follow:

- **Announce needs the desktop client.** It delivers through `ccd_session_mgmt`, an MCP server a
  plain CLI install lacks. The hook never sends: it asks the model to, so nothing is delivered and
  the model says so. **If you are CLI-only, leave that one hook uninstalled** -- nothing else
  depends on it.
- **The desktop app's own session list is incomplete.** `list_sessions` enumerates only sessions
  *that app itself spawned*; an editor-extension session is never registered, so it cannot be
  messaged. It is authoritative for who can be **messaged**, the on-disk records for who **exists**.
- **A schema change degrades to "cannot tell", not to a wrong answer.** Rename a field or change
  `startedAt`'s unit and every fence says it cannot tell -- designed for in
  `scripts/coord/session-registry.ps1`. The doctor prints records read and placed, so the change
  surfaces as a count going to zero.

**Guardrails against accidents, not security boundaries.** The `PreToolUse` gates inspect tool
arguments: a file a shell command writes is invisible, and an agent-authored script defeats a
command-string rule. `--no-verify` on commit or push bypasses both git hooks. No CI-side enforcement
ships.

### Requirements

| Need | Without it |
|---|---|
| **PowerShell 7.3+** (`pwsh`) | Nothing installs. Most scripts carry `#Requires -Version 7.3`. |
| **git** | Nothing installs. Everything is keyed on the git common directory. |
| **`python` on `PATH`** (or `CCX_PYTHON`) | The installed git gates are OFF and say so on stderr. Needed by the three git-hook checkers and the leak gate. |
| **`ccx.config.json` at the target repo root** | User-scope hooks stay inert in that repo. It is both the knob file and the opt-in marker. |

PowerShell 7 runs on Linux and macOS, but Windows is the exercised path; self-marking and path
case-folding degrade elsewhere. **There is no `ccx` on `PATH`**: `ccx doctor` means
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`.
[MIT](https://claude-multisession.pages.dev/LICENSE)

---

## Quickstart

Two directories are involved, and every command says which it means:

| | |
|---|---|
| **tooling** | This checkout. Nothing you install governs *it*; it is where scripts are copied from and hashed against. |
| **target** | The repository you want governed. It gets the config file, the git hooks, and its primary checkout in the gate's allowlist. |

**Use the vendored layout** -- copy `scripts/`, `bin/` and `ccx.config.json` into the target and
commit them, so tooling *is* target. It is the only layout in which the doctor can reach exit 0.

The separate-checkouts layout works for the worktree gate, both git hooks and the backstop. It fails
for the three coordination hooks: shims that resolve their script inside whatever repository the
session runs in, so a target not carrying those files gets three wired hooks that resolve nothing.

Run all of this from a **plain terminal**. All four installers refuse when `$env:CLAUDECODE` is `1`,
because a session that can install these controls can remove them.

```powershell
$tooling = "<path-to-this-checkout>"
$target  = "<path-to-the-repo-you-want-governed>"
Set-Location $target      # the doctor reports what it resolves FROM HERE, so stand in the target

# 1. Opt the target in, and give it the scripts the coordination hooks resolve.
Copy-Item "$tooling/ccx.config.json" "$target/ccx.config.json"   # then edit it
Copy-Item "$tooling/scripts" $target -Recurse
Copy-Item "$tooling/bin" $target -Recurse
# ...then commit them, so every worktree of the target gets them. After vendoring there are two
# copies on disk: install and audit from ONE of them. Installing from one and hashing against the
# other is exactly the drift the doctor calls STALE.

# 2. Baseline BEFORE installing anything. Expect a wall of OFF and exit 1 -- that is correct, and it
#    is the only way to tell an installed guardrail from a decorative one afterwards.
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target

# 3. Coordination hooks: session banner, collision gate, announce. Takes NO repository -- it writes
#    ONE settings file whose hooks resolve their repo per session at run time.
pwsh -NoProfile -File "$tooling/scripts/coord/install-coordination.ps1"

# 4. The commit-msg claim gate and pre-push guard, into the TARGET clone's shared .git/hooks, where
#    one copy governs every worktree of that clone at once.
pwsh -NoProfile -File "$tooling/scripts/coord/install-git-hooks.ps1" -RepoRoot $target

# 5. The worktree gate. -Repo names the PRIMARY checkout to allowlist (several allowed:
#    -Repo <path-a>,<path-b>). The allowlist is the kill switch.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-gate.ps1" -Repo $target

# 6. The SessionStart backstop. ONE config root per run -- run it again for each root the doctor
#    lists under "config roots". An unwired root is OFF, and OFF is exit 1.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-selfheal.ps1" -ConfigDir ~/.claude

# 7. Prove it.
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target
```

### Then run two sessions

```powershell
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name alerts
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name parser
```

`spawn.ps1` creates an isolated worktree on its own branch and opens an editor window in it;
`new.ps1` does the same without the editor. Neither takes a target flag: both act on the primary you
are standing in, so stay in the target. Then start a session in each window and confirm
coordination:

```powershell
pwsh -NoProfile -File "$tooling/scripts/coord/presence.ps1"   # both sessions listed
pwsh -NoProfile -File "$tooling/scripts/coord/overlap.ps1"    # what each is changing
```

Ask both sessions to edit the same file and the second one's edit is refused. That refusal is the
whole product.

### Two things the quickstart does not cover

**Prove it governed the repository you meant.** The doctor's default target is the current directory,
so a run started in the wrong place produces a long, plausible, mostly-green report about the wrong
clone:

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target |
    Select-String 'repo examined|tooling checkout|gate: allowlist|LIVE allowlist'
```

**Give the sessions a working agreement.** Copy
[CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template)
into the target as `CLAUDE.md` and cut it to what is true there: it is where you write down what
the gates cannot see. Keep it short: a stale one still gets acted on.

[INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) is the record
of record for the installers: the annotated version of these steps, and how to prove each one is live
rather than merely merged.

---

## What ships

Paths are relative to this checkout, and the site serves each at the same path --
[/scripts/coord/claim.ps1](https://claude-multisession.pages.dev/scripts/coord/claim.ps1) needs no
clone. Also on [GitHub](https://github.com/wshallwshall/claude-multisession), the better view where
reachable.

### Start here

| Script | Does | Doc |
|---|---|---|
| `bin/ccx-doctor.ps1` | Prove -- by receipt and by attack -- that each control is installed, wired, and refuses what it can be made to refuse. It never infers, always prints WHAT WAS SCANNED and BLIND SPOTS ON THIS RUN, and a skip is never a pass (exit 2). At least one deny path is not self-testable: the collision gate's needs a live peer worktree holding an uncommitted change to the same file, so the doctor proves only that the gate refuses to go *silent*, and prints that as a blind spot every run | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |

### To run sessions

| Script | Does | Doc |
|---|---|---|
| `scripts/worktree/new.ps1` | Create an isolated worktree on its own branch, off the fetched remote tip, serialised against concurrent adds | [Worktrees](WORKTREES.md) |
| `scripts/worktree/spawn.ps1` | `new.ps1` plus an editor window (`-Editor`, else `CCX_EDITOR`, else `EDITOR`, else `code`) | [Worktrees](WORKTREES.md) |
| `scripts/coord/presence.ps1` | Who is actually live in this repo right now, across every surface. Read-only | [Coordination](COORDINATION.md) |
| `scripts/coord/overlap.ps1` | What everyone else is changing -- files and stated work. `-File <path>`, `-Json`; cached, so the gate's common case is a cache read | [Coordination](COORDINATION.md) |
| `scripts/coord/claim.ps1` | Take, release or list an atomic claim on a piece of work, so a session finds out before the work rather than at merge. Advisory: a claim cannot stop a session that refuses to look. Claims do not expire and releasing is manual, on purpose | [Coordination](COORDINATION.md) |
| `scripts/coord/alloc.ps1` | Allocate the next number in a shared sequence atomically, so two sessions can never be handed the same one; `-ShowFloor` inspects without spending one. `seq_check.py` is the other half -- neither is sufficient alone | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `bin/ccx-steer.ps1` | Queue a steering note from a second terminal while a session is mid-task | [Steering](STEERING.md) |

### To clean up

| Script | Does | Doc |
|---|---|---|
| `scripts/worktree/remove.ps1` | Remove one worktree, referencing its tip before anything is removed, and writing a keep-ref when `-DeleteBranch` is used | [Pruning](PRUNING.md) |
| `scripts/worktree/prune-merged.ps1` | The reaper: prune = merged **and** clean **and** unoccupied. Dry-run by default, `-Apply` to act. Carries a second, non-cwd signal and prints its blind spots | [Pruning](PRUNING.md) |
| `scripts/worktree/rescue.ps1` | Move uncommitted work out of the shared primary into a fresh worktree -- the companion to the gate that stops you writing there | [Worktrees](WORKTREES.md) |
| `scripts/worktree/restore-primary.ps1` | Re-attach the primary to its home branch after a session left it detached or on the wrong branch. Refuses on a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/worktree/sessions.ps1` | Find sessions for this repo across every login, including ones a relocation made invisible; `-Rehome` puts a transcript back | [Worktrees](WORKTREES.md) |
| `scripts/security/scan_forbidden.py` | The leak gate: refuse identifying content before a private repo goes public. `--path DIR`, `--require-tokens`, `--show-context`. Nothing wires it | [Leak gate](LEAK-GATE.md) |

### Controls that run without you

Installed once, then invoked by the harness or by git.

| Script | Event | Does | Doc |
|---|---|---|---|
| `scripts/hooks/worktree_gate.ps1` | `PreToolUse` | Denies writes whose target path is inside a governed primary, dispatch from the primary, and the git verbs that swap or discard its tree. Fails open, but loudly | [Hooks](HOOKS.md) |
| `scripts/hooks/collision_gate.ps1` | `PreToolUse` | Refuses an edit to a file a live session is already changing. Fails open -- never silently | [Coordination](COORDINATION.md) |
| `scripts/hooks/announce-session.ps1` | `UserPromptSubmit` | Tells peers you exist and what you intend, on the first prompt at which a messageable peer exists. Always exits 0; delivery needs the desktop client | [Coordination](COORDINATION.md) |
| `scripts/worktree/session-context.ps1` | `SessionStart` | Banner: your project's working defaults plus a live coordination block. Its stdout is the chat's starting context, so it never fails loudly | [Hooks](HOOKS.md) |
| `scripts/worktree/worktree-selfheal.ps1` | `SessionStart` | Repairs a primary whose HEAD drifted, when the tree is clean -- the most privileged control here, whose only safety property is that it refuses a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/hooks/claim_check.py` | `commit-msg` | Refuses a code-touching commit whose subject claims an item this worktree does not hold. Fail-closed | [Coordination](COORDINATION.md) |
| `scripts/hooks/push_guard.py` | `pre-push` | Refuses a direct push of a protected ref. An explicitly empty `protectedRefs` list disables it with a message on stderr | [PRs and merges](PR-AND-MERGE.md) |
| `scripts/hooks/seq_check.py` | `pre-commit` | Refuses a colliding, unallocated, or unindexed sequence number; `--ci` re-runs the collision rules against a freshly fetched trunk. No installer wires it | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `scripts/hooks/block-blanket-git-stage.ps1` | `PreToolUse` | Opt-in. Denies `git add -A/--all/-u/.` and `git commit -a/-am`. Fails open | [Hooks](HOOKS.md) |
| `scripts/hooks/steer-inject.ps1` | `PreToolUse` | Opt-in per worktree. Delivers a queued steering note at the next tool-call boundary rather than at the end of the turn | [Steering](STEERING.md) |

### Internals and installers

| Script | Does | Doc |
|---|---|---|
| `scripts/coord/session-registry.ps1` | The liveness fence: reads the client's session registry and decides whether a session is alive. Liveness may only VETO, never PERMIT -- DEAD/STALE/absent is the absence of a veto, not a permission | [Concepts](CONCEPTS.md) |
| `scripts/coord/occupancy.ps1` | The one cwd-to-worktree matcher, returning a receipt alongside its rows (roots examined, records examined, records that could not be placed) and setting `Available` only when there was something to examine | [Concepts](CONCEPTS.md) |
| `scripts/coord/lock.ps1` | The short-lived cross-session mutex, dot-sourced rather than run: `. lock.ps1` then `Enter-CcxLock` / `Exit-CcxLock`. No TTLs anywhere: locks retry and never steal, and on timeout fail loudly and name the holder | [Concepts](CONCEPTS.md) |
| `scripts/coord/install-coordination.ps1` | Wires the banner, collision gate and announce at user scope as shims that re-resolve at run time; writes exactly one settings file per run (`-SettingsPath`) | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |
| `scripts/coord/install-git-hooks.ps1` | Installs `commit-msg` + `pre-push` into one clone's shared `.git/hooks` (`-RepoRoot`), refuses to overwrite a foreign hook, and never writes `pre-commit` at all | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |
| `scripts/worktree/install-gate.ps1` | Installs the worktree gate as a copy outside every working tree, into every config root it finds, plus the allowlist that is its kill switch (`-Repo`, `-ConfigDir`) | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |
| `scripts/worktree/install-selfheal.ps1` | Wires the SessionStart backstop into ONE config root per run; `-ConfigDir` is mandatory, and it governs whatever the gate's allowlist already names | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |

---

## Where to go next

**The model.** [Concepts](CONCEPTS.md): worktree per session, one shared state root, a liveness
fence that may only veto, exclusive-create over read-modify-write, no TTLs, the six knobs in
`ccx.config.json`. Then [Hooks](HOOKS.md): every control's event and its fail-open or fail-closed
posture.

**Running sessions.** Start at [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md). It is the
entry point to the group, and it covers the three things no other page owns:

- which surface to run sessions on;
- the channels they have for reaching each other;
- using one session as a lander.

Then, in the order the work happens: [Worktrees](WORKTREES.md) - [Coordination](COORDINATION.md) -
[Steering](STEERING.md) - [Sequence allocation](SEQUENCE-ALLOC.md) -
[PRs and merges](PR-AND-MERGE.md) - [Pruning](PRUNING.md).

**Safety,** in descending order of how much actually ships:

- [Leak gate](LEAK-GATE.md) -- a scanner you can run today, plus the blind spot no scanner can close.
- [Usage awareness](USAGE-AWARENESS.md) -- a design; ships no hook.
- [Session mail](SESSION-MAIL.md) -- a design for reaching the peers announce cannot. It ships
  nothing, and is most useful as the list of ways the obvious implementations fail.

**In practice:** [Tips and tricks](TIPS-AND-TRICKS.md) (ordered by when each item bites) -
[Drift audit case study](CASE-STUDY-drift-audit.md) (a method, not a finding list).
[Correction chain case study](CASE-STUDY-correction-chain.md) covers one finding, four statements, three wrong.

**The standards are a separate project now.**
[secure-development-standards](https://secure-development-standards.pages.dev/) holds
what used to live here: a bar for agent-written code a small team stands behind, plus its CI
discipline and assessment method. They ship no code and no certification.

**At the repository root:**
[INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) (record of
record for the installers) and
[CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template)
(a working agreement to drop into your own repository).
