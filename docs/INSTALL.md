# Install

## TLDR/BLUF

Four installers, four scopes, and how to prove each one is live rather than merely merged.

- **What this is.** The reference for the installers, not the procedure.
  [Quickstart](QUICKSTART.md) is the eight steps in order, and ends with you watching a collision get
  refused. Come here for what each flag means and how to prove a control is live.
- **What it demands.** Claude Code for Desktop, `pwsh` 7.3+, `git`, a `python` on `PATH`, the scripts
  vendored into the repository you want governed, and a `ccx.config.json` at its root.
- **What it costs.** Three of the four write at user scope, so their hooks load in every repository
  on the machine. Only installer 2 writes inside the repository you govern, into its git hooks
  directory. Each control has its own on-switch, and `ccx.config.json` is only one of them.
- **Not for you if you are not on Claude Code for Desktop.** A CLI-only or editor-extension setup is
  not supported, and this page does not describe one. Linux and macOS run the scripts but are not the
  exercised path. [Limits and requirements](LIMITS.md) has both tables.
- **Where to start.** A baseline doctor run, then Step 0, then the four installers, then the doctor
  again -- and read what it says it scanned, not just the verdict. When something comes back `RED`,
  `OFF` or `??`, [Troubleshooting](TROUBLESHOOTING.md) is the symptom table.
- **Expect two `OFF (opt-in)` rows** even on a good install: the ASCII gate, and the sequence gate
  once `sequences` is set. They do not fail the run, but the sequence one **is** a real hole -- you
  have to close it. [What that means](#controls-no-installer-wires).

**Every command here refuses to run inside a Claude Code session.** All four installers throw when
`$env:CLAUDECODE` is `1`, because a session that can install these controls can remove them. Use a
plain `pwsh` terminal. `-Status` is exempt, and that exemption is deliberate.

---

> **Cloning this repository installs nothing.** Merging a hook does not install one. Every control
> here runs from a copy or a wiring entry that an installer has to write, and until that happens the
> file you are reading is a source artifact, not an enforcement.

That failure is invisible by construction. A repository with no controls installed still gives you a
session banner, a per-prompt status message, and green output -- no error, no warning, nothing in
the settings file that looks wrong.

Two examples, both from the repository this tooling was developed in. A coordination hook sat wired
and resolving nothing for hours, while an unrelated project's similarly-named entry held its slot.

And a gate with dozens of passing tests bound the repository's copy, while enforcement ran from a
stale installed one.

---

## Before you start

[Limits and requirements](LIMITS.md) owns this table in full, including the platform matrix. The
rows that change what these four commands do:

| Requirement | Why | If missing |
|---|---|---|
| Claude Code for Desktop | The coordination layer is shaped around the desktop client | Announce cannot deliver, and the roster is incomplete |
| PowerShell 7.3+ (`pwsh`) | 26 scripts carry `#Requires -Version 7.3` | Three installers refuse. On 7.0-7.2 the backstop still installs -- see below |
| git, recent enough for `rev-parse --path-format=absolute` (2.31+) | Every shim and checker resolves its repository through it | On an older git the shims resolve nothing and stay silent: installed, wired, enforcing nothing. Nothing checks your version |
| A `python` on `PATH` (or `CCX_PYTHON`) | The git hooks installer 2 writes are `/bin/sh` shims that exec a stdlib-only Python checker; the sequence gate and leak gate are Python too | **The installed git gates are OFF** and say so on stderr |
| The scripts vendored into the target | The three coordination shims resolve inside the session's own repository | Those three rows never resolve, and the doctor cannot reach exit 0 |
| `ccx.config.json` at the target repo root | The knob file, and announce's opt-in marker | Announce stays inert there. The other three user-scope controls are unaffected |

**A missing requirement does not always stop an install.** `install-selfheal.ps1` declares
`#Requires -Version 7` and calls git nowhere, so on PowerShell 7.0-7.2, or on a machine with no git,
it installs while the gate installers refuse.

You get a wired SessionStart backstop over an allowlist holding two comment lines and no entries.
Only `install-gate.ps1` writes entries, and it needs 7.3. So the backstop is armed and inert.

It stops being inert the moment anyone seeds that allowlist from a 7.3 machine. Then it runs
`git checkout` on your shared primary, unattended.

**Platform honesty.** PowerShell 7, Windows-first. Only the stdlib-only Python checkers port: the
git-hook gates under `scripts/hooks/` ([Hooks](HOOKS.md) says which hook each belongs to) and the leak
gate at `scripts/security/scan_forbidden.py`.

Linux is in CI and works with two named degradations. Off Windows the doctor prints one blind spot
covering both: path comparison stops case-folding, and the roster's self-marking degrades.

---

## Step 0 -- opt in

The user-scope hooks load in **every** repository on the machine, so each needs a way to know which
repositories asked for it. They do not share one answer.

```powershell
# from the repo you want to govern
Copy-Item <path-to-this-checkout>/ccx.config.json ./ccx.config.json
```

Set `trunk`, `worktreeLayout`, `protectedRefs` and optionally `sequences` to match. `CCX_CONFIG`
moves the lookup elsewhere. Announce's probe is the file's **presence**, not "is an implementation
script here": that question is true in a half-installed tree and false where the scripts live
elsewhere.

### What this file actually bounds, and what it does not

**Deleting `ccx.config.json` does not opt a repository out.** It stops announce and resets every
knob to its default. The other four controls carry on, and two of those act on your shared checkout.

It also stops the doctor. With no config at or above the path it prints `CANNOT DETERMINE ANYTHING`
and exits 2, before scanning a single control.

| Control | Bounded by | Reads `ccx.config.json`? |
|---|---|---|
| Announce (`UserPromptSubmit`) | This file, at the repository root | Yes. This is its opt-in |
| Collision gate (`PreToolUse`, denies) | Its script resolving inside your repo | No |
| Session banner (`SessionStart`) | Its script resolving inside your repo | No |
| Worktree gate (`PreToolUse`, denies) | The shared allowlist | No |
| SessionStart backstop (runs `git checkout`) | The same allowlist | Only for the `prefix` knob |

The real off-switch for the last two is deleting the allowlist, which disarms them everywhere at
once. [Limits and requirements](LIMITS.md#what-actually-switches-each-control-on) has the full
statement.

**The lookup rule is not uniform either.** Two consumers test one directory and stop: announce at
the repository root, the backstop at the governed root. The checkers, the doctor and the worktree
scripts walk **up** from the current directory.

So a config one level above the root satisfies the second group and leaves the first inert.
`CCX_CONFIG` moves the lookup only for that second group. Announce ignores the variable entirely.

**Do not read installer silence as evidence the file is there.** Installers 3 and 4 never look for
it. Installer 2 checks the clone it governs, so its `NOTE` is about the right repository.

Installer 1 checks its **own** checkout root, which always ships one. On the install path its NOTE
therefore never fires. Its `-Status` mode checks your current directory instead.

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

The most expensive mistake here is a perfect install into the wrong clone. Everything downstream
agrees: a receipt, `-Status` green, a long mostly-green doctor report -- all true, none of it about
the repository you work in. Two directories are in play, and they coincide only in a vendored
layout:

- the **tooling checkout**, which is where scripts are *copied from* and hashed against, and
- the **target**, the clone or checkout that is *governed*.

| Installer | What its target actually is | With no flag | Name it with | When it cannot tell |
|---|---|---|---|---|
| `install-coordination.ps1` | A settings **file**. It resolves no repository at all -- each shim resolves one per session, at run time, from that session's own directory | `~/.claude/settings.json` | `-SettingsPath <file>`, once per config root your client reads | Not applicable: nothing here is repository-keyed |
| `install-git-hooks.ps1` | A **clone**. Its git common directory is where `commit-msg` and `pre-push` land | The clone you are standing in | `-RepoRoot <path>`. `-HooksDir <path>` overrides the derived directory, for a layout neither `core.hooksPath` nor the common dir covers | **Refuses.** If the clone you are standing in is not the one this script ships from, it stops and prints both, with the `-RepoRoot` line to re-run |
| `install-gate.ps1` | **Primary checkouts**, written into the shared allowlist | The primary of the clone you are standing in | `-Repo <path>`. **Pass every governed primary at once**: `-Repo <path-a>,<path-b>`. `-ConfigDir` selects which config roots get wired | **Refuses**, the same way, naming both primaries |
| `install-selfheal.ps1` | A **config root** only. What it repairs is whatever the gate's allowlist names | Nothing -- `-ConfigDir` is mandatory | `-ConfigDir <path>` (required), `-HookPath <path>` for the shared script copy | It cannot: with no allowlist entries it installs and reports itself inert |
| `bin/ccx-doctor.ps1` | The repository the whole report is **about** | The current directory's repository | `-Repo <path>`, plus `-ConfigDir` and `-SettingsPath` for the wiring it reads | It cannot refuse -- it is a report. So it prints `repo examined` and `tooling checkout` on every run and says outright when they are the same clone |

Two consequences worth keeping:

- **The checkers, the gate and the backstop are always copied from the tooling checkout**, never from
  the target. A governed repository is not expected to vendor any of these files, so `-RepoRoot
  <your-repo>` does not send the installer looking in `<your-repo>/scripts/hooks/` for sources.
- **`install-git-hooks.ps1` resolves its clone before every mode**, so `-Status` and `-Uninstall`
  take the same `-RepoRoot` and refuse on the same terms: auditing the wrong clone's hooks is the
  same error as installing there. `install-gate.ps1` is the opposite, deliberately: no `-Repo` at
  all.
- **`install-gate.ps1` REPLACES the allowlist, it does not add to it.** The file is rewritten from
  this run's `-Repo` values. Run it for a second repository on its own and the first is silently
  removed, which turns off both the gate and the backstop there, in every session, immediately.

**Naming two takes `-Command`, not `-File`.** Under `pwsh -File` every argument arrives as a literal
string, so `-Repo <a>,<b>` binds one string and the install aborts on `Resolve-Path`. It fails
loudly, which is the good case. It just does not do what it looks like. Use:

```powershell
pwsh -NoProfile -Command "& '<tooling>/scripts/worktree/install-gate.ps1' -Repo '<path-a>','<path-b>'"
```

Nothing above changes the one rule that makes it checkable: after any of it, run the doctor with an
explicit `-Repo` and read the `repo examined` line back before you believe anything under it.

### Shim or copy -- the trade you are making

The coordination installer writes a **shim**: a one-liner that locates the script in a checkout and
runs it. Nothing falls stale -- a pull updates the hook everywhere at once. The price: a shim
resolving nothing exits silently and writes nothing, byte-identical to a healthy hook with no peers.

**Announce is the exception.** Its shim probes for `ccx.config.json` and, where a repository opted in
but the script does not resolve, prints a named notice. The banner and collision-gate shims do not:
those two fail invisibly.

The gate and git-hook installers write a **copy**, because their scripts must survive a checkout. The
primary is routinely on a detached HEAD or an old commit, and a hook whose script lives inside a
working tree vanishes on a branch switch -- after which the tool call runs anyway, silently.

The price is drift: installing from a stale checkout downgrades the live gate for every worktree at
once, while every file involved is still present and still looks installed. Both prices are paid the
same way -- by receipt, never by reading a settings file.

---

## Why user scope, and not the project's `.claude/`

Project hooks do not reach worktrees: `.claude/` is usually git-ignored, so git cannot deliver a
project `settings.json` there; where it can, the copy is a creation-time snapshot nothing refreshes.
And a project hook lives on **one branch**, protecting nothing until other worktrees merge it.

Measured on the repository this tooling was developed in: more than half the worktrees had no project
settings at all. A live editor session in one of them had zero coordination context -- it could not
see its peers, and they could not see it. That failure mode is invisible, not broken-looking.

User scope is per-machine and loads in every worktree regardless of how that worktree was created.
Hook definitions from the user, project and local scopes are unioned, so installing at user scope
**adds** to a repository's own guards rather than replacing them.

---

## Installer 1 -- coordination hooks

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-coordination.ps1
```

Wires three rows into `~/.claude/settings.json`:

| Event | Script | What it does |
|---|---|---|
| `SessionStart` | `scripts/worktree/session-context.ps1` | Who else is live, and what they are building |
| `PreToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`) | `scripts/hooks/collision_gate.ps1` | Refuses a file a live session is already changing |
| `UserPromptSubmit` | `scripts/hooks/announce-session.ps1` | Tells peers you exist, and what you intend |

**Target:** a settings file, and nothing else. This installer never resolves a repository. Its rows
are shims that resolve one per session, at run time, from that session's own directory. So no
checkout is the wrong one to run it from, and there is no `-Repo` to get wrong.

It writes exactly **one settings file** per run: `~/.claude/settings.json` unless `-SettingsPath`
moves it. A backup and a receipt land beside it. If your client reads more than one config root, run
it once per root; the doctor lists the roots it found under `config roots`.

Its `-Uninstall` has the same scope. Wire two roots, uninstall once, and the second stays armed.

Useful flags: `-Only <event>` and `-Except <event>` scope install, uninstall and `-Status` alike.
Announce lives on its own event, so `-Only UserPromptSubmit -Uninstall` removes announce **without**
disarming the collision gate or the banner.

**The shim resolves the primary checkout first, not the calling worktree.** Coordination has to be
uniform: two sessions running different versions of the collision protocol are exactly the drift the
shared liveness fence prevents. The calling worktree is only a fallback.

Both candidates are inside the session's **own** repository, which is why only the vendored layout
makes these three rows `OK`. [Quickstart](QUICKSTART.md) covers the layout choice, and what a target
without these scripts gets instead.

### Prove it

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-coordination.ps1 -Status
```

**Run this from the repository you are asking about, not from the tooling checkout.** `resolves` is
answered from your current directory, so a `-Status` run in the tooling clone reports on the tooling
clone. In a vendored layout the two are the same directory and it does not matter.

Read four separate lines per row, and do not let any of them stand in for another:

| Line | Answers | Source of truth |
|---|---|---|
| `receipt` | Did an install of this row ever happen here? | The receipt file beside the settings file |
| `wired` | Is something carrying our marker in the settings file? | `settings.json` -- a **claim** |
| `current` | Does the wired command match what this checkout would write? | SHA-256 of both command strings |
| `resolves` | Does the shim's own resolution order find a real script **right now**? | The filesystem, from your current directory |

`=> LIVE` requires wired **and** resolving, and a receipt that matches **if there is one**.
`resolves NOTHING` is its own red line, printed with the bases it tried, because that is the state
that reads as healthy.

**Read the `receipt` line separately.** An absent receipt satisfies the verdict's third clause
(`-not $rec -or $wiredSha -eq $rec.commandSha256`), so a row wired by hand or restored from a backup
prints `receipt no` and then green. The doctor is stricter, and reports that state as `??`.

`-Status` models the shim's resolution rather than using a better helper: a check that resolves the
primary better than the hook does reports a healthy hook that does not work. It resolves from your
**current directory**, so it answers only for the repository you stand in -- re-run it from each.

### The standing cost

These hooks run on every prompt in every repository on the machine. Measured on the repository this
tooling was developed in: roughly 0.5 s for the shim per prompt, plus roughly 1.0 s for the peer
lookup on the prompts where it runs (the cheap opt-in check runs first, deliberately).

Announce's row carries a 15 s timeout, which is that hook's only time bound.

---

## Installer 2 -- git hooks (claim gate + push guard)

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone-to-govern>
```

**Target:** `-RepoRoot` names the clone. Everything else about where the files land follows from it:
`core.hooksPath` if that is set for the clone, otherwise `<its-git-common-dir>/hooks`. `-HooksDir`
overrides that derivation for a layout neither answer covers; you should almost never need it.

Leave `-RepoRoot` off and the target is the clone **you are standing in**, which must be the clone
this script ships from; otherwise it refuses, naming both and printing the `-RepoRoot` line to
re-run.

That refusal replaced a default resolving this script's own checkout:
`cd <your-repo>; pwsh -File <tooling>/scripts/coord/install-git-hooks.ps1` then installed both gates
into the **tooling** clone, printed a clean receipt, and governed nothing you were working in, while
every status line agreed.

The checkers are always copied from the tooling checkout, never from `-RepoRoot`. A repository you
want governed is not required to carry `scripts/hooks/`.

Installs into the **shared** hooks directory in the clone's common git directory, which every linked
worktree shares. One file there reaches all of them the instant it is written -- no branch, no merge,
no propagation lag -- and it survives a branch switch in any of them.

It also sees every write route -- an edit tool, a shell redirect, a script, an editor, a subagent --
because it inspects the **tree** at commit time rather than a tool call. That is why it exists
alongside the `PreToolUse` gate, which inspects tool arguments and cannot see a shell-written file.

| Hook | Checker | Refuses |
|---|---|---|
| `commit-msg` | `scripts/hooks/claim_check.py` | A commit whose subject claims an item this worktree does not hold |
| `pre-push` | `scripts/hooks/push_guard.py` | A direct push of a protected ref -- that work goes through a pull request |

The installer honours `core.hooksPath`. If it is set and the installer ignored it, the files would go
somewhere git never looks -- which is the exact shape of failure this script exists to prevent.

**Two invariants worth knowing before you run it.**

1. **It refuses to overwrite a hook that is not ours.** A `commit-msg` or `pre-push` without our
   marker stops the install; merge by hand. Blind overwriting deletes somebody else's control. The
   markers are on-disk identity: renaming one orphans every install. Rename once, in one commit, or
   not at all.
2. **It never writes `pre-commit` -- not to install, not to patch, not to migrate.** Two tools cannot
   both own that file. What happens when they try, and why the sequence gate therefore ships unwired,
   is at [the git-hook contract](HOOKS.md#the-git-hook-contract).

**Fail-open, declared.** The installed hooks are `/bin/sh` shims that locate a python and exec the
checker. With no interpreter they write to stderr and exit 0: the gate is OFF for that commit, and
says so out loud.

That one failure turns both gates off everywhere at once, every file still present and still looking
installed. So `-Status` names the interpreter it found and asks it for its version: on Windows a
`python` on `PATH` is often an execution-alias stub that resolves cleanly and runs nothing.

**`-Status` and the shim do not pick the same interpreter.** `-Status` skips a candidate that will
not answer `--version`. The shim takes `python` whenever `command -v` succeeds, which a stub does.
Where `python` is a stub and `python3` real, `-Status` goes green for the wrong one.

`git commit --no-verify` and `git push --no-verify` bypass both. That is a guardrail against accident,
not a security boundary; back it with a server-side check if you need one.

### Prove it

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone> -Status
```

`-Status` resolves its clone the way the install does, refusal included, so it audits the clone you
name rather than the one the script lives in. It prints `governs`, `hooks dir` and `sources` on
separate lines for the same reason: the first question about a report is which repository it is
about.

It re-hashes the installed copies against **both** the receipt and this checkout's sources: "a file
with the right name is there" is not "the running code is the code you are reading".
Read `checker INSTALLED COPY DIFFERS FROM SOURCE` as *the running gate is not the code here*.

**The verdict only hashes the checker.** For the hook shim it asks whether our marker is present,
not whether the bytes match. A receipt mismatch prints yellow and changes nothing.

So a shim someone appended `exit 0` to still reads `=> INSTALLED`, and the command still exits 0.
Read the yellow lines above the green one.

`-Status` also names its own blind spot: nothing in it executes either checker. A hook that exists and
hashes correctly still does nothing if the checker it execs refuses to run. Driving a real commit --
or running the doctor, which fires each control on purpose -- is the only answer.

---

## Installer 3 -- the worktree gate

```powershell
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Repo <the-primary-to-govern>
```

Wires the gate to refuse three things in an allowlisted primary:

| It refuses | Outcome |
|---|---|
| An `Edit`, `Write`, `MultiEdit` or `NotebookEdit` writing into that primary | The tool call never runs |
| A `Bash` or `PowerShell` call carrying a tree-swapping git verb aimed at it | The tool call never runs |
| A `Task`, `Agent` or `Workflow` dispatch made from it, since a subagent inherits the directory | Unless `-NoDispatchGate` |

**Target:** `-Repo` names the **primary checkout(s)** written into the allowlist -- see the `-Command`
note above for naming more than one. The primary and not a worktree, on purpose: you will usually
install from a worktree, and governing that worktree instead would be exactly backwards.

Leave `-Repo` off and the target is the primary of the clone **you are standing in** -- required to
be the clone this script ships from, or it refuses, naming both. The old default resolved this
script's own clone, and put the tooling checkout in the allowlist while every report agreed.

`-ConfigDir` is the separate question of *which config roots get wired*; it does not name a
repository. `-Status` and `-Uninstall` are not repository-keyed at all -- they read and remove the one
shared allowlist and that wiring -- so neither takes `-Repo`.

Copies `scripts/hooks/worktree_gate.ps1` to `~/.claude/hooks/` and registers it as a `PreToolUse`
hook in the `settings.json` of **every** Claude config directory: `~/.claude`, plus each
`~/.claude-account-*` carrying a marker the client itself writes (`projects/`, `sessions/` or
`.claude.json`).

The marker test is deliberately not `settings.json` or `hooks/`: those are what these installers
write, so accepting a directory for having them would let the check confirm its own earlier mistake.
Rejections are listed with their reason. `-ConfigDir` overrides the set and bypasses the test.

**Why every config directory.** Wiring only `~/.claude` leaves other logins ungated -- and those are
where parallel editor-hosted chats run. A session under one checked its branch out inside another
session's linked worktree, swapping that session's files mid-task; the gate was not installed there.

The gate governs only the checkouts named in the allowlist, `~/.claude/hooks/ccx-gate.repos.txt` --
whatever `-Repo` resolved to, above. That file **is** the kill switch.

The allowlist filename is deliberately *not* derived from `ccx.config.json`'s `prefix`: it lives
outside any repository, is read by an installed copy that cannot see a repo's config, and is shared
with the SessionStart backstop.

Two components deriving one filename from a per-repo setting is how they end up reading different
files and agreeing only by luck. This pair has shipped that bug: in one version, uninstalling the
gate left the backstop armed and still willing to run `git checkout` on the shared primary.

### The flag that drops a rule

`-NoDispatchGate` skips the subagent-dispatch rule, and says so in two places: the install prints a
warning, and `-Status` reports the dispatch tools as **UNWIRED -- implemented but never fires** for
as long as the flag's effect persists.

An option that removes a control without leaving a queryable trace recreates the problem this
repository is about: you cannot tell, from inside a session, whether that rule is live. If you want
it off, you should have to keep seeing that you turned it off.

`-EnterWorktreeGate` is the mirror image: an explicit opt-**in**, off by default, reported as
`opt-in` rather than as a fault.

With both it and the dispatch rule live, a session started in the primary has no in-session path to
isolation: it can neither dispatch a subagent nor relocate itself, and a human must restart it
elsewhere. Turn both on deliberately, not as a side effect of an unrelated install.

### Prove it

```powershell
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Status
```

Five things, reported separately:

- **`installed` / `source` / `parity`.** SHA-256 of the installed copy against the source, printed as
  hashes and not asserted. A hand-bumped version label can lie, and has: rules shipped without a bump,
  so both lines read the same version directly above a `*** STALE ***` verdict.
- **`governing`.** The allowlist contents. With no file it says `gate is OFF`. **With a file holding
  no entries it prints the bare header and nothing** -- the all-clear shape, for a gate governing
  nothing. Installer 4 seeds that file, so count entries rather than look for the word OFF.
- **`wiring`, per config directory.** The matchers in that file, diffed against the rules the
  **installed** script has. `UNWIRED` is implemented but never fires; `stray`, matched but ignored;
  `opt-in`, off by design. A count of "3" says nothing unless you know 3 is right, so it asserts an
  expectation.
- **`skipped`.** Directories whose NAME matched a config root but are not one, each with its
  rejection reason -- a candidate dropped silently reads like one that never existed.
  `.claude-account-*` also matches a launcher's `.lock` artifact, a real directory; wiring it writes
  settings into a lock file.
- **What it scanned.** The number of config directories and the number of rules it compared against.
  A skip must never read as a pass.

`Get-HandledTools` is called on the **installed** copy, deliberately. The question is which rules the
gate that is *running* has -- a rule can sit in source, be declared by an installer and be covered by
green tests while the gate that actually runs has never heard of it.

**This one has no verdict line and always exits 0**, including over `*** STALE ***` and an empty
allowlist. Its siblings signal through the exit code; this one only prints.

---

## Installer 4 -- the SessionStart backstop

```powershell
pwsh -NoProfile -File <tooling>/scripts/worktree/install-selfheal.ps1 -ConfigDir ~/.claude
```

**Target:** a config directory. `-ConfigDir` is **mandatory** -- no default to get wrong -- and names
no repository: what it repairs is whatever the gate's allowlist names, so installing it before
installer 3 leaves it reporting itself inert. `-HookPath` moves the shared script copy it refreshes.

Wires `scripts/worktree/worktree-selfheal.ps1` into **one** config directory; run it once per
directory a session can use. The doctor reports an unwired config root as `OFF` -- a required
control with zero enforcement, which is exit 1 -- so "once per root" is checkable rather than
advisory.

**This one runs on PowerShell 7.0.** It declares `#Requires -Version 7` where every other installer
declares 7.3, so on a 7.0-7.2 machine this is the one control that installs, and it is the one that
runs `git checkout` on your shared primary unattended.

### Prove it

**There is nothing to run.** This installer has no `-Status` and no `-Uninstall` of its own; removing
the gate's allowlist is what renders it inert. Ask the doctor instead, which reports an unwired config
root as `OFF` and fires the backstop against a dirty throwaway repository.

It also takes one `-ConfigDir` per run rather than discovering them the way its sibling does.

One note that generalizes: neither installer gives `$HookPath` or `$SettingsPath` a parameter
default. Defaults bind before the body's first line, so one that throws pre-empts the refusal guard
below it and the script dies with an unrelated error. A guard is only a guard if nothing runs ahead
of it.

---

## What the installers guarantee about a control's dependencies

A checker installed **without the module it imports** raises at import: it refuses every commit, for
reasons unrelated to what it checks. Without its dot-sourced helpers, a gate exits 0 after a stderr
receipt, enforcing **nothing** while every named file is present and hashes correctly.

Both shipped, once each. Each installer now carries its dependency closure as a declared list, and
neither will install a partial one:

| Installer | Also copies | If a source is missing | Verified by |
|---|---|---|---|
| `scripts/coord/install-git-hooks.ps1` | `scripts/hooks/_ccxconfig.py`, which both checkers import | refuses before writing anything | re-reads the copy and compares SHA-256 against the source; a mismatch aborts before the receipt is written |
| `scripts/worktree/install-gate.ps1` | `_command.ps1`, `_gittarget.ps1`, `_common.ps1` -- the gate's dot-source closure | refuses before writing anything | re-reads each copy after writing it |

**Only the git-hook installer copies the substrate first.** A checker that lands ahead of its module
is briefly a gate that refuses everything, so ordering there is cheap insurance against an interrupted
install.

`install-gate.ps1` copies in the other order: the gate, then its three helpers. An install
interrupted between the two leaves a gate whose dot-source fails, which exits 0 after a stderr
receipt and enforces nothing. Re-run it rather than reasoning about what landed.

How to see it rather than take it on trust:

```
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -Status
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Status
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1
```

`-Status` on the git-hook installer hashes each installed **checker** against this checkout's source
and reports a difference as `INSTALLED COPY DIFFERS FROM SOURCE`.

**Neither `-Status` hashes the dependencies**, which is the closure this section is about. The
git-hook status branch walks the two checkers only; the gate's returns before its helper list is
even defined. A stale or missing helper is invisible to both.

Only the doctor checks either closure. That is why it is the third command above, rather than a
nicety.

The doctor goes further and **fires** each control. That is the only evidence surviving a dependency
that lands but fails to load: a gate that cannot load its helpers allows what it should deny, and
only an attack catches it.

The gate still writes its stderr receipt on a load failure, which is not redundant: an installed copy
can lose its helpers later to a cleanup, a partial uninstall, a hand-edited hooks directory. Without
the receipt, "the gate had nothing to say" and "the gate could not load" are byte-identical.

---

## Controls no installer wires

Absence here is a choice, not a defect -- but an unwired control is still zero enforcement, and the
doctor reports each of these rather than letting it pass quietly. Which tag you get depends on the
control:

- The two `PreToolUse` guards are `--` while nothing wires them. Wire one by hand and the doctor
  reports `OK` with the locations. It then attacks the **blanket-stage guard**; the steering injector
  gets a receipt row and no attack, so `OK` there means wired, never proven to fire.
- The **sequence gate reads your configuration**. With no `sequences` key in `ccx.config.json` it is
  `[-- ] sequence gate`, off by configuration. With one, as the shipped file has and this checkout
  prints, it is `[OFF] sequence gate`: nothing at commit time defends the numbers you allocate.
- The **ASCII gate is `[OFF] ASCII gate: present, not wired`** in every checkout, since every
  checkout carries `scripts/quality/check-ascii.ps1`. Nothing shipped runs it, so it refuses nothing
  until you invoke it: presence is capability, not enforcement, and `OK` needs installed **and**
  wired.

Neither tag fails the run, with one exception: a checkout missing the ASCII checker altogether reads
`[OFF] ASCII gate: not in this checkout`, and that one **is** required -- a checkout missing a file
it ships is broken, not opt-in.

Opt-in `OFF` rows are counted and named separately in the verdict, under `OFF (opt-in)`, so the row
you can see above it is a row you can find below it.

| Control | Why it is not installed | Wire it |
|---|---|---|
| `scripts/hooks/seq_check.py` | It needs `pre-commit`, and installer 2 never writes that file | Into whatever hook framework you already use. Until you do, two sessions can take the same number and the collision merges clean |
| `scripts/quality/check-ascii.ps1` | A repo-local checker rather than an installed hook, so there is no second copy to hash -- and no shipped installer runs it | Into your own `pre-commit` hook and into CI (this repo's own `gates` workflow is that second half). Until you do it sees a file only when someone runs it, so a character written after a run is unscanned until the next one |
| `scripts/hooks/block-blanket-git-stage.ps1` | Narrow, and a false positive is expensive | A `PreToolUse` row on the shell tools -- `.claude/settings.example.json` in this checkout is that row, with the path left as a loud placeholder you must replace with an absolute one. It costs a `pwsh` spawn on **every** shell tool call, git or not, which is the other half of why it is opt-in |
| `scripts/hooks/steer-inject.ps1` | A `PreToolUse` hook on `*` taxes every tool call in every session (measured on the machine this tooling was developed on: roughly 366 ms per call, most of it bare `pwsh` startup) | Per worktree, in that worktree's `.claude/settings.local.json`, when you actually want it -- see `docs/STEERING.md` and `bin/ccx-steer.ps1` |

Installer 2 prints the sequence-gate hole explicitly when `ccx.config.json` configures `sequences`,
because an absent gate looks exactly like one that passed.

---

## Why the installers refuse to run inside Claude Code

All four throw when `$env:CLAUDECODE` is `1`.

A session that can install these controls can remove them, and every one constrains sessions. The
gate stops building in a shared checkout; the git hooks bound what a session commits and pushes;
remove the coordination hooks and a session goes invisible to peers while looking coordinated to
itself.

The selfheal backstop is the most privileged: it runs `git checkout` on the shared primary
unattended, from a script the calling session can freely edit. Its only safety property is that it
refuses a **dirty** tree, so that is the thing to verify rather than assume.

`bin/ccx-doctor.ps1` fires it against a drifted, dirty throwaway repository and requires it to
decline and say why (`selfheal negative: dirty primary refused`). A repair there is `RED`.

**That probe needs a python, and it is skipped without one.** Unlike the claim and push probes it
records no "attack skipped" row, so the line is simply absent from the report. `-SkipAttacks`
suppresses it too. An absent row is an untested control, not a passed one.

Run them from a plain `pwsh` terminal.

**`-Status` is exempt in all three that have one** (the backstop has none; ask the doctor)**, and
that is load-bearing.** Auditing is not installing: a session blind to its own controls cannot see
the failure this toolkit is about. The source handles `-Status` *above* the `CLAUDECODE` refusal.

---

## Uninstall, and the kill switches

```powershell
pwsh -NoProfile -File <tooling>/scripts/coord/install-coordination.ps1 -Uninstall
pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <the-clone> -Uninstall
pwsh -NoProfile -File <tooling>/scripts/worktree/install-gate.ps1 -Uninstall
```

Installer 1's `-Uninstall` clears **one settings file**, the same as its install. Run it once per
config root you wired, or the others stay wired and keep firing.

Installer 2's `-Uninstall` resolves a clone as its install does, takes the same `-RepoRoot` and
refuses on the same terms: removing the wrong clone's hooks is the same mistake as installing there.
Installer 3's removes the shared allowlist and every config root's wiring, neither repository-keyed.

Each removes only entries carrying its own marker. Installer 2 leaves a foreign hook alone on the
uninstall path, and leaves the checker copy with it: that hook may have been edited to call the copy,
and deleting a file something else execs turns off somebody else's control silently.

Installer 3's uninstall removes the shared allowlist, which renders the SessionStart backstop inert
too, and says so.

**A kill switch has to reach sessions that are already running, so the switches here are files and
environment variables, not settings edits.**

| Switch | Effect | Reaches a running session |
|---|---|---|
| Delete `~/.claude/hooks/ccx-gate.repos.txt` | Gate and backstop both OFF everywhere | Yes -- the file is read on every invocation |
| `<state-root>/announce/OFF` | Announce stands down | Yes |
| `CCX_ANNOUNCE_DISABLE` | Announce stands down for sessions started from that environment | New sessions only |
| `CCX_ALLOW_DIRECT_PUSH=1` | Push guard allows a protected ref | No. A process keeps the environment it started with; prefix the one `git push` |

Hook **wiring** changes do not reach a running session: it keeps the configuration it booted with.
(Installer 3's output says "every session, no restart" -- that is true of its allowlist, which is
re-read every time the gate fires, and not of the settings rows it just wrote.)

The doctor reports the **last three** as `RED` on its `live disarm switches` row when it finds one
set: a control disarmed right now is not a control.

The **first is not one of them** -- a deleted file is nothing to find set, so it surfaces further up,
on the allowlist row, as `[OFF] worktree gate: allowlist  governs NOTHING (no entries in ...)`. An
empty allowlist file reads identically, which is correct: both govern nothing.

---

## Now prove all of it

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-governed>
```

Run this after every install path above, and read **what it says it scanned** -- not just the verdict.

**Pass `-Repo`, and read it back.** Without it the doctor examines the current directory's
repository -- from the tooling checkout, a long, mostly-green report about the tooling checkout. It
cannot refuse to answer, so it prints two lines at the top of every run, marking the same-clone case:

<!-- no-copy -->
```text
  repo examined    : <the-repo-you-governed>   (-Repo)
  tooling checkout : <tooling>   (every source hash below is read from here)
```

Then confirm the allowlist actually contains that repository, and that the installed gate refuses a
write to it: `worktree gate: allowlist ... governed, including this primary`, and
`gate: LIVE allowlist + real primary`. Those two lines separate a gate that works from one that works
somewhere else.

The doctor never infers. It enumerates every control by receipt, hashes each installed copy against
this checkout's source, and diffs wired matchers against the rules the installed script implements.

Then it **fires each control on purpose and requires it to refuse**. Five of them: crafted
`PreToolUse` JSON at the installed gate, a blanket stage, a commit claiming an unclaimed item, a push
to a protected ref, and a drifted throwaway primary in front of the backstop.

Every attack is paired with a negative control: an ordinary action the same control must allow. A
script that refuses everything is an outage rather than a guard, and a probe with no positive control
proves nothing.

For the backstop the negative control is the load-bearing half. Repairing a drifted **clean**
primary passes whether or not the dirty-tree refusal is still in the code. So the pair is a drifted
**dirty** one, which it must decline to touch and say why.

The allocator is the one check with no allow/deny axis: it refuses nothing, so there is no ordinary
action for it to allow. It is paired instead with the property that can be violated -- its read-only
floor inspection spends no number and moves no ratchet.

The attacks run against throwaway git repositories in the temp directory, deleted on the way out;
nothing in your repository is modified.

**Exit 0 is not "every deny path was proven".** The collision gate's refusal needs a live peer
worktree holding an uncommitted change to the same file. The doctor cannot stage that, so it proves
only that the gate speaks up when it cannot check. It names the gap on every run.

| Exit | Meaning |
|---|---|
| 0 | Every required control is installed and wired, and every attack it **could** fire was refused |
| 1 | At least one control is broken or absent -- the guardrails you appear to have are not all there |
| 2 | At least one check could not be determined. Not a pass. This command refuses to guess |

### The verdict counts every control it can see, not the ones you chose

This catches people out on a deliberate partial install, so it is worth stating plainly: the exit
code is an accounting over the whole control set.

- **Any `RED`, or a *required* control `OFF`, is exit 1.** Required: the worktree gate, its allowlist
  and wiring, the three coordination rows, both git hooks, the SessionStart backstop. **A partial
  install cannot exit 0.** The skipped one reads `OFF`, implemented, invoked by nothing, not "not
  chosen".
- **Any `??` with no `RED` is exit 2.** A skip is never a pass.
- **`--` never fails a run.** That tag is for a control that is opt-in by design (the blanket-stage
  guard, the steering injector) or off by configuration (the sequence gate with no `sequences` key).
- **An *opt-in* control reported `OFF` never fails a run**, and is counted on its own `OFF (opt-in)`
  line, not folded into the `OFF` number. Two rows today: the ASCII gate, which no installer runs,
  and the sequence gate once `sequences` is set -- a real hole no shipped installer promised to
  close.

So exit 0 also needs a `python` on `PATH` (the git-hook shims fail open without one), every config
root the run lists wired, and no kill switch set. The `VERDICT` block names every `RED`, `OFF` and
`??` it counted, so you never have to infer which one moved the number.

`-SkipAttacks` makes every attack `??`, so the run cannot exit 0 -- it is 2, or 1 if something was
also proven broken or absent. A control that was not tested is not a control that passed.

`-Json` emits a machine-readable report whose `scanned` block carries the config roots, session
records read, records it could not place, worktrees, trunk, state root, both hooks directories, the
interpreter, git, platform, and whether attacks were fired at all.

The doctor prints its own blind spots on every run. Read them: that is where a green report stops
meaning what it looks like. [Limits and requirements](LIMITS.md) states each one in full, with the
caveat standing over every green line here -- guardrails against accidents, not security boundaries.

## When it does not come back green

That is the ordinary first result, not a sign you did something wrong.

| You got | Go to |
|---|---|
| `RED`, `OFF`, `??`, or exit 1 or 2 | [Troubleshooting](TROUBLESHOOTING.md), whose first table is symptom to cause |
| `*** STALE ***`, or a report about the wrong clone | [Troubleshooting](TROUBLESHOOTING.md) |
| A green report you do not trust | [Drift audit](CASE-STUDY-drift-audit.md), which is the method for exactly that |
| The sequence gate's `OFF (opt-in)` | [Sequence allocation](SEQUENCE-ALLOC.md) has the `pre-commit` hook to wire |
| The ASCII gate's `OFF (opt-in)` | Wire `scripts/quality/check-ascii.ps1` into your own `pre-commit` and into CI |
| A leak-gate question | [Leak gate](LEAK-GATE.md). No installer wires that one either |
