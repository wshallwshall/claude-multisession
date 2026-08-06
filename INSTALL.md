# Install

Four installers, four scopes, and how to prove each one is actually live.

Read this section first, because it is the reason the rest of the document is shaped the way it is:

> **Cloning this repository installs nothing.** Merging a hook does not install one. Every control
> here runs from a copy or a wiring entry that an installer has to write, and until that happens the
> file you are reading is a source artifact, not an enforcement.

That failure is invisible by construction. A repository with no controls installed still gives you a
session banner, a status message on every prompt, and green output. There is no error, no warning,
and nothing in the settings file that looks wrong. On the repository this tooling was developed in, a
coordination hook sat wired-but-resolving-nothing for hours while the settings file read as correct,
because a similarly-named entry from an unrelated project occupied the slot. Another gate had dozens
of passing tests, every one of them binding the repository's copy while enforcement ran from a stale
installed copy.

So: install, then run the doctor, then read what the doctor says it scanned.

---

## Before you start

| Requirement | Why | If missing |
|---|---|---|
| PowerShell 7.3+ (`pwsh`) | Most scripts carry `#Requires -Version 7.3` | Nothing installs |
| git | Everything is keyed on the git common directory | Nothing installs |
| A `python` on `PATH` (or `CCX_PYTHON`) | The git hooks installer 2 writes are `/bin/sh` shims that exec a stdlib-only Python checker; the hand-wired sequence gate and the leak gate are Python too | **The installed git gates are OFF** and say so on stderr |
| `ccx.config.json` at the target repo root | It is both the knob file and the opt-in marker | User-scope hooks stay inert in that repo |

**Platform honesty.** This is PowerShell 7 and Windows-first. The Python checkers -- the git-hook
gates under `scripts/hooks/` and the leak gate at `scripts/security/scan_forbidden.py` -- are
stdlib-only and portable; almost everything else is `pwsh`. See `docs/HOOKS.md` for which git hook
each checker belongs to. Off Windows, path comparison stops case-folding and the roster's
self-marking degrades -- the doctor prints both as blind spots rather than pretending otherwise.

---

## Step 0 -- opt in

The user-scope hooks fire in **every** repository on the machine, so they need a way to know which
repositories asked for them. That marker is `ccx.config.json` at the repository root.

```powershell
# from the repo you want to govern
Copy-Item <path-to-this-checkout>/ccx.config.json ./ccx.config.json
```

Set `trunk`, `worktreeLayout`, `protectedRefs` and (optionally) `sequences` to match that repository.
`CCX_CONFIG` overrides the lookup if you need the file somewhere else. The probe is deliberately the
config file's **presence** and not "does some implementation script happen to exist here" -- that
second question is true in a half-installed tree and false in a repository that vendors the scripts
elsewhere.

Without this file the installers still run, and each one prints a `NOTE` telling you the rest of the
tooling will stay inert.

---

## The four installers at a glance

| Installer | Scope | Writes | Governs |
|---|---|---|---|
| `scripts/coord/install-coordination.ps1` | User -- **one** settings file per run (`~/.claude/settings.json` unless `-SettingsPath` moves it) | Three hook rows, each a **shim** that re-resolves at run time, plus a receipt | Session banner, collision gate, announce -- in every worktree, for sessions that read that file |
| `scripts/coord/install-git-hooks.ps1` | Clone (`<git-common-dir>/hooks`, or `core.hooksPath`) | `commit-msg` + `pre-push` shims, **copies** of the Python checkers and their substrate, plus a receipt | Every worktree of that one clone, immediately |
| `scripts/worktree/install-gate.ps1` | User, **every** config root it finds | A **copy** of the gate outside every working tree, one shared allowlist, `PreToolUse` rows per rule | The primary checkouts named in the allowlist |
| `scripts/worktree/install-selfheal.ps1` | User, **one** config root per run | A copy of the SessionStart backstop beside the gate, plus that root's wiring | Whatever the gate's allowlist already names -- it has no target of its own |

---

## Which repository each installer governs

The most expensive mistake available here is installing perfectly into the wrong clone. Everything
downstream then agrees with you: the install prints a receipt, `-Status` hashes green, and the doctor
returns a long, mostly-green report -- all of it true, and none of it about the repository you are
working in. Two directories are in play in every command, and they are only the same directory if you
vendored these scripts into your own repository:

- the **tooling checkout**, which is where scripts are *copied from* and hashed against, and
- the **target**, the clone or checkout that is *governed*.

| Installer | What its target actually is | With no flag | Name it with | When it cannot tell |
|---|---|---|---|---|
| `install-coordination.ps1` | A settings **file**. It resolves no repository at all -- each shim resolves one per session, at run time, from that session's own directory | `~/.claude/settings.json` | `-SettingsPath <file>`, once per config root your client reads | Not applicable: nothing here is repository-keyed |
| `install-git-hooks.ps1` | A **clone**. Its git common directory is where `commit-msg` and `pre-push` land | The clone you are standing in | `-RepoRoot <path>`. `-HooksDir <path>` overrides the derived directory, for a layout neither `core.hooksPath` nor the common dir covers | **Refuses.** If the clone you are standing in is not the one this script ships from, it stops and prints both, with the `-RepoRoot` line to re-run |
| `install-gate.ps1` | **Primary checkouts**, written into the shared allowlist | The primary of the clone you are standing in | `-Repo <path>`, or several: `-Repo <path-a>,<path-b>`. `-ConfigDir` selects which config roots get wired | **Refuses**, the same way, naming both primaries |
| `install-selfheal.ps1` | A **config root** only. What it repairs is whatever the gate's allowlist names | Nothing -- `-ConfigDir` is mandatory | `-ConfigDir <path>` (required), `-HookPath <path>` for the shared script copy | It cannot: with no allowlist entries it installs and reports itself inert |
| `bin/ccx-doctor.ps1` | The repository the whole report is **about** | The current directory's repository | `-Repo <path>`, plus `-ConfigDir` and `-SettingsPath` for the wiring it reads | It cannot refuse -- it is a report. So it prints `repo examined` and `tooling checkout` on every run and says outright when they are the same clone |

Two consequences worth keeping:

- **The checkers, the gate and the backstop are always copied from the tooling checkout**, never from
  the target. A governed repository is not expected to vendor any of these files, so `-RepoRoot
  <your-repo>` does not send the installer looking in `<your-repo>/scripts/hooks/` for sources.
- **`install-git-hooks.ps1` resolves its clone before every mode**, so `-Status` and `-Uninstall`
  refuse on the same terms and take the same `-RepoRoot`: auditing or removing the wrong clone's
  hooks is the same error with the same cost. `install-gate.ps1` is the opposite, and deliberately:
  its `-Status` and `-Uninstall` are not repository-keyed at all -- they read and remove the one
  shared allowlist and the config roots' wiring -- so `-Repo` has no meaning there and is not asked
  for.

Nothing above changes the one rule that makes it checkable: after any of it, run the doctor with an
explicit `-Repo` and read the `repo examined` line back before you believe anything under it.

### Shim or copy -- the trade you are making

The coordination installer writes a **shim**: a one-liner that locates the script in a checkout and
runs it. Nothing falls stale, because a pull updates the hook everywhere at once. The price is that a
shim resolving nothing exits silently and writes nothing, which is byte-identical to a healthy hook
with no peers.

The gate and git-hook installers write a **copy**, because their scripts must survive a checkout. The
primary is routinely on a detached HEAD or an old commit, and a hook whose script path lives inside a
working tree simply vanishes on a branch switch -- after which the tool call runs anyway, silently.
The price is drift: installing from a stale checkout downgrades the live gate for every worktree at
once, while every file involved is still present and still looks installed.

Both prices are paid the same way -- by receipt, never by reading a settings file.

---

## Why user scope, and not the project's `.claude/`

Project-scoped hooks do not reach worktrees. `.claude/` is git-ignored in a great many repositories,
so git cannot deliver a project `settings.json` to a new worktree at all; where it can, the copy is a
creation-time snapshot that nothing refreshes. And a project hook lives on **one branch**, so it
protects nothing until every other worktree merges it.

Measured on the repository this tooling was developed in: more than half the worktrees had no project
settings whatsoever. A live editor session was working in one of them with zero coordination
context -- it could not see its peers and they could not see it. That is the failure mode that
matters. It is not obviously broken; it is invisible.

User scope is per-machine and loads in every worktree regardless of how that worktree was created.
Hook definitions from the user, project and local scopes are unioned, so installing at user scope
**adds** to a repository's own guards rather than replacing them.

---

## Installer 1 -- coordination hooks

```powershell
pwsh -NoProfile -File scripts/coord/install-coordination.ps1
```

Wires three rows into `~/.claude/settings.json`:

| Event | Script | What it does |
|---|---|---|
| `SessionStart` | `scripts/worktree/session-context.ps1` | Who else is live, and what they are building |
| `PreToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`) | `scripts/hooks/collision_gate.ps1` | Refuses a file a live session is already changing |
| `UserPromptSubmit` | `scripts/hooks/announce-session.ps1` | Tells peers you exist, and what you intend |

**Target:** a settings file, and nothing else. This is the one installer that never resolves a
repository -- the rows it writes are shims that resolve one per session, at run time, from that
session's own directory. So it does not matter which checkout you run it from, and there is no
`-Repo` to get wrong. What it *does* write is exactly **one** file per run: `~/.claude/settings.json`
unless `-SettingsPath` moves it. If your client reads more than one config root, run it once per
root; the doctor lists the roots it found under `config roots`.

Useful flags: `-Only <event>` and `-Except <event>` scope install, uninstall and `-Status` alike.
Announce lives on its own event, so `-Only UserPromptSubmit -Uninstall` removes announce **without**
disarming the collision gate or the banner.

**The shim resolves the primary checkout first, not the calling worktree.** Coordination is
infrastructure and has to be uniform; two sessions running different versions of the collision
protocol is exactly the drift the shared liveness fence exists to prevent. The calling worktree is
kept only as a fallback.

Both candidates are inside the session's **own** repository, which is what makes the vendored layout
the one where these three rows can be `OK`. See *Five minutes* in `README.md` for the layout choice,
and for what a target that does not carry these scripts gets instead.

### Prove it

```powershell
pwsh -NoProfile -File scripts/coord/install-coordination.ps1 -Status
```

Read four separate lines per row, and do not let any of them stand in for another:

| Line | Answers | Source of truth |
|---|---|---|
| `receipt` | Did an install of this row ever happen here? | The receipt file beside the settings file |
| `wired` | Is something carrying our marker in the settings file? | `settings.json` -- a **claim** |
| `current` | Does the wired command match what this checkout would write? | SHA-256 of both command strings |
| `resolves` | Does the shim's own resolution order find a real script **right now**? | The filesystem, from your current directory |

`=> LIVE` requires wired **and** resolving **and** matching the receipt. `resolves NOTHING` is its own
red line, printed with the bases it tried, because that is the state that reads as healthy.

`-Status` deliberately models the shim's resolution rather than using a better helper that resolves
the primary more carefully. A status check that finds the target by a better route than the hook uses
reports a healthy hook that does not work. It also resolves from your **current directory**, because
that is where the hook resolves from -- so `-Status` only ever answers for the repository you are
standing in. Re-run it from each one.

### The standing cost

These hooks run on every prompt in every repository on the machine. Measured on the repository this
tooling was developed in: roughly 0.5 s for the shim on every user prompt, plus roughly 1.0 s for the
peer lookup on the prompts where it actually runs (the cheap opt-in check runs first, deliberately).
Announce's row carries a 15 s timeout, which is that hook's only time bound.

---

## Installer 2 -- git hooks (claim gate + push guard)

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone-to-govern>
```

**Target:** `-RepoRoot` names the clone. Everything else about where the files land follows from it:
`core.hooksPath` if that is set for the clone, otherwise `<its-git-common-dir>/hooks`. `-HooksDir`
overrides that derivation for a layout neither answer covers; you should almost never need it.

Leave `-RepoRoot` off and the target is the clone **you are standing in** -- which this script
requires to be the clone it ships from, and otherwise refuses, naming both and printing the
`-RepoRoot` line to re-run. That refusal replaced a default that resolved this script's own checkout,
under which `cd <your-repo>; pwsh -File <tooling>/scripts/coord/install-git-hooks.ps1` installed both
gates into the **tooling** clone and printed a clean receipt for them. Nothing you were working in
was governed, and every status line agreed it was fine.

The checkers are always copied from the tooling checkout, never from `-RepoRoot`. A repository you
want governed is not required to carry `scripts/hooks/`.

Installs into the **shared** hooks directory, which lives in the common git directory that every
linked worktree of the clone shares. One file there reaches all of them the instant it is written --
no branch, no merge, no propagation lag. It survives a branch switch in any of them. And it sees
every write route (an edit tool, a shell redirect, a script, an editor, a subagent), because it
inspects the **tree** at commit time rather than a tool call. That last property is why it exists
alongside the `PreToolUse` gate, which inspects tool arguments and therefore cannot see a file
written by a shell command.

| Hook | Checker | Refuses |
|---|---|---|
| `commit-msg` | `scripts/hooks/claim_check.py` | A commit whose subject claims an item this worktree does not hold |
| `pre-push` | `scripts/hooks/push_guard.py` | A direct push of a protected ref -- that work goes through a pull request |

The installer honours `core.hooksPath`. If it is set and the installer ignored it, the files would go
somewhere git never looks -- which is the exact shape of failure this script exists to prevent.

**Two invariants worth knowing before you run it.**

1. **It refuses to overwrite a hook that is not ours.** If `commit-msg` or `pre-push` exists without
   our marker, the installer stops and tells you to merge them by hand. Blind overwriting silently
   deletes somebody else's control. The marker strings are on-disk identity: renaming one orphans
   every existing install, after which this script correctly refuses to touch the old file as
   foreign. Rename once, in one commit, or not at all.
2. **It never writes `pre-commit` -- not to install, not to patch, not to migrate.** Two tools cannot
   both own that file. A hook framework that finds a foreign hook there may rename it and invoke it
   from its own shim, and that chain has failed on Windows and blocked every commit in a repository
   until the shim was removed. Note that the renamed file *existing* did not indicate success; only a
   real commit did.

**Fail-open, declared.** The installed hooks are `/bin/sh` shims that locate a python and exec the
checker. With no interpreter they write to stderr and exit 0 -- the gate is OFF for that commit, and
it says so out loud. This is the single failure that turns both gates off everywhere at once, while
every file involved is still present and still looks installed. That is why `-Status` reports which
interpreter it found, and asks the interpreter for its version rather than trusting the lookup. On
Windows a `python` on `PATH` is often an execution-alias stub that resolves cleanly and then runs
nothing.

`git commit --no-verify` and `git push --no-verify` bypass both. That is a guardrail against accident,
not a security boundary; back it with a server-side check if you need one.

### Prove it

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone> -Status
```

`-Status` resolves its clone exactly the way the install does, refusal included, so it audits the
clone you name rather than the one the script lives in. It prints `governs`, `hooks dir` and
`sources` on three separate lines for the same reason -- the first question a reader has about a
report is which repository it is about.

It re-hashes the installed copies and compares them against **both** the receipt and this checkout's
sources -- because "a file with the right name is there" is not the same claim as "the code that is
running is the code you are reading". Read `checker INSTALLED COPY DIFFERS FROM SOURCE` as *the
running gate is not the code in this checkout*.

`-Status` also names its own blind spot: nothing in it executes either checker. A hook that exists and
hashes correctly still does nothing if the checker it execs refuses to run. Driving a real commit -- or
running the doctor, which fires each control on purpose -- is the only thing that answers that.

---

## Installer 3 -- the worktree gate

```powershell
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Repo <the-primary-to-govern>
```

**Target:** `-Repo` names the **primary checkout(s)** to write into the allowlist, and accepts
several at once (`-Repo <path-a>,<path-b>`). It is the primary, not a worktree, on purpose: you will
usually install from a worktree -- that is the whole point of the gate -- and governing that worktree
instead of the primary would be exactly backwards.

Leave `-Repo` off and the target is the primary of the clone **you are standing in**, which must be
the clone this script ships from; otherwise it refuses and names both primaries. The old default
resolved this script's own clone, so installing from a tooling checkout put the tooling checkout in
the allowlist -- after which the status line, the receipt and the doctor all agreed, confidently,
about the wrong repository.

`-ConfigDir` is the separate question of *which config roots get wired*; it does not name a
repository. `-Status` and `-Uninstall` are not repository-keyed at all -- they read and remove the one
shared allowlist and that wiring -- so neither takes `-Repo`.

Copies `scripts/hooks/worktree_gate.ps1` to `~/.claude/hooks/` and registers it as a `PreToolUse`
hook in the `settings.json` of **every** Claude config directory on the machine: `~/.claude` plus each
`~/.claude-account-*` that a launcher created **and that carries a marker the client itself
writes** (`projects/`, `sessions/` or `.claude.json`). The marker test is deliberately not
`settings.json` or `hooks/`: those are what these installers write, so accepting a directory
because it has them would make the check confirm its own earlier mistake. Anything rejected is
listed with its reason. Override the set with `-ConfigDir`, which bypasses the test entirely.

**Why every config directory.** Wiring only `~/.claude` leaves every other login ungated, and those
are where parallel editor-hosted chats run. A session running under an ungoverned login checked its
own branch out inside another session's linked worktree, silently swapping that session's files
mid-task; the gate that would have blocked it was simply not installed there.

The gate governs only the checkouts named in the allowlist, `~/.claude/hooks/ccx-gate.repos.txt` --
whatever `-Repo` resolved to, above. That file **is** the kill switch.

The allowlist filename is deliberately *not* derived from `ccx.config.json`'s `prefix`: it lives
outside any repository, is read by an installed copy that cannot see a repo's config, and is shared
with the SessionStart backstop. Two components deriving one filename from a per-repo setting is how
they end up reading different files and agreeing only by luck. This pair has already shipped that
bug: in one version, uninstalling the gate left the backstop armed and still willing to run
`git checkout` on the shared primary.

### The flag that drops a rule

`-NoDispatchGate` skips the subagent-dispatch rule. It is honest about it in two places, on purpose:
the install prints a warning, and `-Status` reports the dispatch tools as **UNWIRED -- implemented but
never fires** for as long as the flag's effect persists. An install option that removes a control
without leaving a queryable trace recreates the whole problem this repository is about: you cannot
tell, from inside a session, whether that rule is live. If you want it off, you should have to keep
seeing that you turned it off.

`-EnterWorktreeGate` is the mirror image -- an explicit opt-**in**, off by default, reported as
`opt-in` rather than as a fault. With both the dispatch rule and that one live, a session started in
the primary has no in-session path to isolation at all: it can neither dispatch a subagent nor
relocate itself, and a human must restart it elsewhere. That is a decision to make on purpose, not one
that rides along with an unrelated install.

### The SessionStart backstop

```powershell
pwsh -NoProfile -File <tooling>/scripts/worktree/install-selfheal.ps1 -ConfigDir ~/.claude
```

**Target:** a config directory, and `-ConfigDir` is **mandatory** -- there is no default to get
wrong. It names no repository either: what it repairs is whatever the gate's allowlist already
names, which is why installing it before installer 3 leaves it correctly reporting itself inert.
`-HookPath` moves the shared script copy it refreshes.

Wires `scripts/worktree/worktree-selfheal.ps1` into **one** config directory; run it once per
directory a session can use. The doctor reports an unwired config root as `OFF` -- a required
control with zero enforcement, which is exit 1 -- so "once per root" is checkable rather than
advisory.

Honest limits, both of them current: this installer has no `-Status` and no `-Uninstall` of its own
(removing the gate's allowlist is what renders it inert), and it takes one `-ConfigDir` per run rather
than discovering them the way its sibling does.

One implementation note that generalizes past this script: neither installer gives `$HookPath` or
`$SettingsPath` a parameter default. Parameter defaults are evaluated during **binding**, before the
first line of the body -- so a default that throws pre-empts the refusal guard below it and the script
dies with an unrelated error instead of refusing. A guard is only a guard if nothing can run ahead of
it.

### Prove it

```powershell
pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status
```

Five things, reported separately:

- **`installed` / `source` / `parity`.** SHA-256 of the installed copy against the source, printed as
  hashes and not asserted. A hand-bumped version label can lie, and has: rules shipped without a bump,
  so both lines read the same version directly above a `*** STALE ***` verdict.
- **`governing`.** The allowlist contents. No file, no entries, nothing governed -- and it says
  `gate is OFF` rather than printing nothing.
- **`wiring`, per config directory.** The matchers actually present in that file, diffed against the
  rules the **installed** script implements. `UNWIRED` means implemented but never fires; `stray`
  means matched but the script ignores it; `opt-in` means off by design. A count of "3" is not
  information unless you know whether 3 is right, so this asserts against an expectation instead.
- **`skipped`.** Directories whose NAME matched a config root but that are not one, each with the
  reason it was rejected. The pattern `.claude-account-*` also matches a launcher's `.lock` artifact,
  which on a real machine is a directory -- and wiring one means writing settings into a lock file.
  Rejections are printed rather than dropped, because a candidate that vanished silently reads exactly
  like one that never existed.
- **What it scanned.** The number of config directories and the number of rules it compared against.
  A skip must never read as a pass.

`Get-HandledTools` is called on the **installed** copy, deliberately. The question is which rules the
gate that is *running* has -- a rule can sit in source, be declared by an installer and be covered by
green tests while the gate that actually runs has never heard of it.

---

## What the installers guarantee about a control's dependencies

A checker installed **without the module it imports** is not a disabled gate -- it is a gate that
raises at import and exits non-zero, i.e. one that refuses every commit for a reason unrelated to
what it checks. A gate installed without the helpers it dot-sources is the mirror image: it exits 0
after a stderr receipt, so it enforces **nothing** while every file the installer names is present
and hashes correctly. Both shipped, once each. Each installer now carries its dependency closure as a
declared list, and neither will install a partial one:

| Installer | Also copies | If a source is missing | Verified by |
|---|---|---|---|
| `scripts/coord/install-git-hooks.ps1` | `scripts/hooks/_ccxconfig.py`, which both checkers import | refuses before writing anything | re-reads the copy and compares SHA-256 against the source; a mismatch aborts before the receipt is written |
| `scripts/worktree/install-gate.ps1` | `_command.ps1`, `_gittarget.ps1`, `_common.ps1` -- the gate's dot-source closure | refuses before writing anything | re-reads each copy after writing it |

The substrate is copied **first**, before the checkers that import it: a checker that lands ahead of
its module is briefly a gate that refuses everything, and ordering is cheap insurance against an
interrupted install.

How to see it rather than take it on trust:

```
pwsh -NoProfile -File scripts/coord/install-git-hooks.ps1 -Status
pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

`-Status` on the git-hook installer hashes each installed checker against this checkout's source and
reports a difference as `INSTALLED COPY DIFFERS FROM SOURCE`, so a missing or stale dependency shows
up as a fact about bytes rather than as a claim. The doctor goes further and **fires** each control,
which is the only evidence that survives a dependency landing but failing to load: the gate that
cannot load its helpers allows what it should deny, and an attack is what catches that.

The gate still writes its stderr receipt on a load failure, and that is not redundant with the
above. An installed copy can lose its helpers later -- a cleanup, a partial uninstall, a hand-edited
hooks directory. Without the receipt, "the gate had nothing to say" and "the gate could not load"
are byte-identical.

---

## Controls no installer wires

Absence here is a choice, not a defect -- but an unwired control is still zero enforcement, and the
doctor reports each of these rather than letting it pass quietly. Which tag you get depends on the
control:

- The two `PreToolUse` guards are always `--` (not wired anywhere it can see).
- The **sequence gate reads your configuration**, because "nobody wired it" and "nothing asked for
  it" are different holes. With no `sequences` key in `ccx.config.json` it is `[-- ] sequence gate`,
  off by configuration. With one -- **as the shipped `ccx.config.json` has, so this is what a run in
  this checkout prints** -- it is `[OFF] sequence gate`: numbers are being allocated and nothing at
  commit time defends them.

Neither tag fails the run. The `OFF` one is counted and named separately in the verdict, under
`OFF (opt-in)`, so the row you can see above it is a row you can find below it.

| Control | Why it is not installed | Wire it |
|---|---|---|
| `scripts/hooks/seq_check.py` | It needs `pre-commit`, and installer 2 never writes that file | Into whatever hook framework you already use. Until you do, two sessions can take the same number and the collision merges clean |
| `scripts/hooks/block-blanket-git-stage.ps1` | Narrow, and a false positive is expensive | A `PreToolUse` row on the shell tools -- `.claude/settings.example.json` in this checkout is that row, with the path left as a loud placeholder you must replace with an absolute one. It costs a `pwsh` spawn on **every** shell tool call, git or not, which is the other half of why it is opt-in |
| `scripts/hooks/steer-inject.ps1` | A `PreToolUse` hook on `*` taxes every tool call in every session (measured on the machine this tooling was developed on: roughly 366 ms per call, most of it bare `pwsh` startup) | Per worktree, in that worktree's `.claude/settings.local.json`, when you actually want it -- see `docs/STEERING.md` and `bin/ccx-steer.ps1` |

Installer 2 prints the sequence-gate hole explicitly when `ccx.config.json` configures `sequences`,
because an absent gate looks exactly like one that passed.

---

## Why the installers refuse to run inside Claude Code

All four throw when `$env:CLAUDECODE` is `1`.

A session that can install these controls can also remove them, and every one of them exists to
constrain sessions. The coordination hooks are how peers see each other -- a session that removes them
makes itself invisible to everyone else while still looking coordinated to itself. The gate stops
sessions building in a shared checkout. The git hooks constrain what a session may commit and push.
The selfheal backstop is the most privileged of the set: it runs `git checkout` on the shared primary
unattended, from a script the calling session can freely edit. Its only safety property is that it
refuses a **dirty** tree, so that is the one thing worth verifying rather than assuming.
`bin/ccx-doctor.ps1` fires it on every run against a drifted, dirty throwaway repository, and requires
it to decline and to say why (`selfheal negative: dirty primary refused`). A repair there is `RED`.

Run them from a plain `pwsh` terminal.

**`-Status` is exempt in all three that have one** (the backstop has none -- ask the doctor
instead)**, and the exemption is load-bearing.** Auditing is not installing,
and a session that cannot see whether its own controls are live has no way to notice the exact failure
this whole toolkit is about. In the source, the `-Status` branch is placed physically *above* the
`CLAUDECODE` refusal for that reason.

---

## Uninstall, and the kill switches

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-coordination.ps1 -Uninstall
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone> -Uninstall
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Uninstall
```

Installer 2's `-Uninstall` resolves a clone the same way its install does, so it takes the same
`-RepoRoot` and refuses on the same terms -- removing the wrong clone's hooks is the same mistake as
installing them there. Installer 3's does not: it removes one shared allowlist and the wiring in
every config root, neither of which is repository-keyed.

Each removes only entries carrying its own marker. Installer 2 leaves a foreign hook alone even on
the uninstall path, and leaves the checker copy with it. A foreign hook may have been edited to call
that copy, and deleting a file something else execs turns somebody else's control off without
saying so. Installer 3's uninstall removes the shared allowlist, which renders the SessionStart
backstop inert too, and says so.

**A kill switch has to reach sessions that are already running, so the switches here are files and
environment variables, not settings edits.**

| Switch | Effect | Reaches a running session |
|---|---|---|
| Delete `~/.claude/hooks/ccx-gate.repos.txt` | Gate and backstop both OFF everywhere | Yes -- the file is read on every invocation |
| `<state-root>/announce/OFF` | Announce stands down | Yes |
| `CCX_ANNOUNCE_DISABLE` | Announce stands down for sessions started from that environment | New sessions only |
| `CCX_ALLOW_DIRECT_PUSH=1` | Push guard allows a protected ref | Yes, per environment |

Hook **wiring** changes do not reach a running session: it keeps the configuration it booted with.
(Installer 3's output says "every session, no restart" -- that is true of its allowlist, which is
re-read every time the gate fires, and not of the settings rows it just wrote.)

The doctor reports the **last three** as `RED`, on its `live disarm switches` row, when it finds one
set -- because a control disarmed right now is not a control. The **first is not one of them**: a
deleted file is nothing to find set, so the doctor does not test it as a switch at all. It surfaces
further up instead, on the allowlist row, as `[OFF] worktree gate: allowlist  governs NOTHING (no
entries in ...)` -- the same disarmed state arriving by absence rather than by a flag. An empty
allowlist file reads identically, which is correct: both govern nothing.

---

## Now prove all of it

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-governed>
```

Run this after every install path above, and read **what it says it scanned** -- not just the verdict.

**Pass `-Repo`, and read it back.** Without it the doctor examines the current directory's
repository, which for a run started in the tooling checkout means a long, plausible, mostly-green
report about the tooling checkout. It cannot refuse to answer -- it is a report, and reports are how
you find out -- so instead it prints two lines at the top of every run and marks the case where they
are the same clone:

```text
  repo examined    : <the-repo-you-governed>   (-Repo)
  tooling checkout : <tooling>   (every source hash below is read from here)
```

Then confirm the allowlist actually contains that repository, and that the installed gate refuses a
write to it: `worktree gate: allowlist ... governed, including this primary`, and
`gate: LIVE allowlist + real primary`. Those two lines are the difference between a gate that works
and a gate that works somewhere else.

The doctor never infers. It enumerates every control by receipt, hashes each installed copy against
this checkout's source, and diffs wired matchers against the rules the installed script implements.
Then it **fires each control on purpose and requires it to refuse**. The attacks are crafted
`PreToolUse` JSON at the installed gate, a blanket stage, a commit claiming an unclaimed item, a push
to a protected ref, and a drifted throwaway primary in front of the `SessionStart` backstop. Every
attack is paired with a negative control -- an ordinary action the same control must allow -- because
a script that refuses everything is an outage, not a guard, and a probe with no positive
control proves nothing. For the backstop the negative control is the load-bearing half: repairing a
drifted **clean** primary passes whether or not the dirty-tree refusal is still in the code, so the
pair is a drifted **dirty** one, which it must decline to touch and say why. The allocator is the one
check with no allow/deny axis: it refuses nothing, so there is no ordinary action for it to allow. It
is paired instead with the property that can be violated -- that its read-only floor inspection
spends no number and moves no ratchet. The attacks run against throwaway git repositories in the temp
directory, which are deleted on the way out; nothing in your repository is modified.

| Exit | Meaning |
|---|---|
| 0 | Every required control is installed and wired, and every attack was refused |
| 1 | At least one control is broken or absent -- the guardrails you appear to have are not all there |
| 2 | At least one check could not be determined. Not a pass. This command refuses to guess |

`-SkipAttacks` makes every attack `??`, so the run cannot exit 0 -- it is 2, or 1 if something was
also proven broken or absent -- because a control that was not tested is not a control that passed. `-Json` emits a machine-readable report whose `scanned` block carries the
config roots, session records read, records it could not place, worktrees, trunk, state root, both
hooks directories, the interpreter, git, platform, and whether attacks were fired at all.

Three of its blind spots are worth internalising before you trust any of this:

- **Announce delivery.** Announce does not send anything itself. It resolves peers and asks the model
  to send via a session-management MCP server that the desktop client provides and a plain CLI install
  does **not** have. Where that server is absent the hook still fires, still finds peers, and then
  instructs the model to call tools it does not have. Announce is decorative there, and nothing in
  PowerShell can see the difference.
- **The session record schema is a vendor contract.** Every liveness answer rests on a per-session
  JSON record written by the client. A renamed field, a moved directory or a changed unit turns the
  counts into zeros. Read the record census as the instrument, not as the sessions.
- **No roster is complete.** The client-side session-listing tool enumerates only sessions the desktop
  app itself spawned; an editor-extension session is never entered into it. That is why the tooling
  reads the on-disk registry instead -- but "no roster anywhere is guaranteed complete" remains true.

And the standing caveat that applies to every green line above: these are guardrails against
accidents, not security boundaries. `--no-verify` skips both git hooks and nothing local records that
it happened; the `PreToolUse` gates inspect tool **arguments**, so a file written by a shell command --
or by any agent-authored script -- is invisible to them.
