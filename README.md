# claude-multisession

Coordination tooling for running **several Claude Code sessions at once against one repository**:
a worktree per session, a shared state root git already gives you, guardrail hooks, a liveness
fence, atomic claims and locks, cross-session announce, and a worktree reaper that refuses to
guess.

**PowerShell 7 + Windows-first.** Nearly every shipped script is PowerShell; a handful are Python,
and those are stdlib-only and portable. The PowerShell house rule is a `#Requires -Version 7.3` line
at the top, and all but a few carry it: the two selfheal scripts ask only for `7`, and a few carry no
`#Requires` at all -- deliberately, in the announce hook's case, because its event has to degrade to
"stand down and say so" rather than throw at load. An exact file census is not printed here on
purpose: a count in prose is stale on the next file added. Count it against the tree you actually
have instead, and note that the scope is the question -- `git ls-files 'bin/*.ps1' 'bin/*.py'
'scripts/*.ps1' 'scripts/*.py'` is the *shipped* set, which is not what a bare `git ls-files '*.ps1'
'*.py'` returns: that one also sweeps in `examples/` and `tests/`. It runs on PowerShell 7 for Linux
and macOS, but the Windows
paths are the ones that were exercised, and two behaviours degrade elsewhere (self-marking in the
roster, and path case-folding). A bash port is a different project.

MIT licensed. No dependencies beyond `pwsh`, `git`, and -- for the three git-hook checkers and the
leak gate -- any `python3` on `PATH`.

Nothing here puts a `ccx` executable on your `PATH`. Every command is a plain script you run with
`pwsh`; where this README says `ccx doctor` it is shorthand for
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`. Every relative path in this file is
relative to this checkout, which is **not** necessarily the repository being governed -- see the two
directories named at the top of *Five minutes*.

---

## Read this before you install

Three limits, up front, because each one changes whether this repo is worth your time.

**1. Announce needs a desktop-only MCP server.** Cross-session announce
(`scripts/hooks/announce-session.ps1`) delivers through the `ccd_session_mgmt` MCP server, which the
desktop client provides. It is **absent on a plain CLI install**. The hook does not send anything
itself -- it resolves peers and asks the model to send. So on a host without that MCP the hook still
fires, still finds peers, and then instructs the model to call tools it does not have. The model
says so, and nothing is delivered. If you are CLI-only, leave that one hook uninstalled. Nothing
else here depends on it.

**2. The liveness fence rests on a vendor contract.** Everything that answers "who is live, and
where" reads `<config-root>/sessions/<pid>.json` -- a record the *client* writes, with `pid`,
`startedAt`, `sessionId`, `cwd`, `entrypoint`, `kind`. We do not own its shape, its location, or its
lifetime. If a future client renames a field or changes `startedAt`'s unit, every fence here
degrades to "cannot tell" rather than to a confident wrong answer -- that is designed for, in
`scripts/coord/session-registry.ps1`, and `ccx doctor` reports how many records it read and placed
so a schema change shows up as a count going to zero instead of as a silent all-clear.

**3. The desktop app's own session list cannot see every session.** Its `list_sessions` tool
enumerates an in-memory map of the sessions *that app itself spawned*. A session launched by the
editor extension is never entered into it -- not filtered out, never registered -- so it is invisible
there and cannot be messaged. Verified directly against a live editor session sharing the default
config root, so it is not a per-login split. Treat `list_sessions` as authoritative for who can be
**messaged**, and the on-disk session records as the only registry that answers who **exists**.

And the meta-limit that motivates everything below:

> **Every failure mode in this system is byte-identical to success.** A hook that is wired but
> resolves nothing exits 0 and prints nothing -- which is exactly what a healthy hook with no peers
> does. A gate whose helper failed to load allows the edit -- which is exactly what a gate that
> checked and found nothing does. You cannot detect a difference the producer never encoded. That is
> why `ccx doctor` exists, why it runs below both before any installer and after all of them, and why it *fires each control on
> purpose* instead of reading a settings file.

---

## What problem this solves

Two sessions in two worktrees are isolated on disk. They are not isolated in any of the ways that
actually cost you work, and git reports none of it as a conflict.

| Collision | What it looks like | Why git cannot see it | Addressed by |
|---|---|---|---|
| **Same working tree** | Session B runs `git checkout` in the shared primary checkout; session A's files silently become another commit's files, mid-task | It is a legal checkout | `scripts/hooks/worktree_gate.ps1` (PreToolUse deny), `scripts/worktree/worktree-selfheal.ps1` (SessionStart repair) |
| **Same file** | Both edit `src/service.py` in separate branches and find out at merge, after both built on divergent assumptions | Merge-time, not edit-time | `scripts/hooks/collision_gate.ps1` + `scripts/coord/overlap.ps1` |
| **Same work, different files** | Three sessions independently fix the same dependency advisory; three branches, three file sets, zero textual conflict, all green | There is nothing to conflict on | `scripts/coord/claim.ps1` + `scripts/hooks/claim_check.py` |
| **Same reserved number** | Both grep for "the next free decision-record number", both pick `0084`, both create *differently named* files, both merge clean | No shared bytes were touched | `scripts/coord/alloc.ps1` + `scripts/hooks/seq_check.py` |
| **Same shared git config** | Two concurrent `git worktree add` calls race `.git/config.lock`; one fails and leaves an orphaned branch | The loser reports a lock error, not a race | `scripts/coord/lock.ps1`, used by `scripts/worktree/new.ps1` |
| **Same shared list** | Any "registry" you read, edit and write back | Nothing errors | Exclusive-create test-and-set everywhere. Measured on the repo this tooling was developed in: 8 concurrent PowerShell writers to one shared file, **4 writes lost, no error** |
| **Same agent memory** | Cross-session memory lives outside the repo; last write wins | It is not in the repo | Convention only -- coordinate memory *writes*, or let exactly one session own them |

The number collision fired **three times** on the repo this tooling was developed in. It is the one
class that a worktree, a file lock and `git merge-tree` are *all* blind to.

Two design facts that fall out of measuring rather than guessing, both on the repo this tooling was
developed in, over 30 days:

- **A banner asking sessions to use worktrees does not work.** 44% of all file writes from sessions
  running in the shared primary landed in the primary's own tree. If a convention matters, enforce
  it with a hook; a reminder produces no evidence either way.
- **Gate on the write's target path, never the session's cwd.** 29% of writes came from a session
  *sitting* in the primary and landing inside a sibling worktree by absolute path -- already correct
  behaviour that a cwd-keyed gate would have denied every one of.

---

## Five minutes

**Two directories are involved, and every command below says which one it means.**

| Name | What it is |
|---|---|
| **tooling** | This checkout. Nothing you install governs *it*; it is only where the scripts are copied from and hashed against. |
| **target** | The repository you want governed. It gets the config file, the git hooks, and its primary checkout in the gate's allowlist. |

An installer that had to guess between them would get it wrong in exactly the way this repository
exists to prevent, and then print a receipt for the wrong clone. So **every installer that takes a
target refuses to guess**: with no explicit flag it governs the clone you are *standing in*, and if
that is not the clone it ships from, it stops and makes you name one.

**Decide first whether the two are one directory, because it decides how much of this works:**

| Layout | What it is | What you get |
|---|---|---|
| **Vendored** (recommended) | `scripts/`, `bin/` and `ccx.config.json` copied into the repository they govern, and committed there. tooling **is** target | All four installers, and the only layout in which the doctor can reach **exit 0** |
| **Separate checkouts** | The tooling stays in its own clone and governs another | The worktree gate, both git hooks and the SessionStart backstop govern the target. The **three coordination hooks will not**: see below |

The three coordination hooks are shims that locate their script *inside whatever repository the
session is running in* -- `<that repo>/scripts/worktree/session-context.ps1` and its two siblings.
That is deliberate (a pull updates every worktree at once, with nothing to fall stale), and it means
a target that does not carry those files gets three hooks that are wired and resolve nothing. The
doctor reports each as `RED -- WIRED BUT RESOLVES NOTHING`, which is the correct answer and is still
exit 1. Vendor the scripts into the target, or run the coordination installer with `-Uninstall` and
accept that coordination is off there; there is no flag that points those shims at another checkout.

Run these from a **plain terminal**. All four installers refuse when `$env:CLAUDECODE` is `1`,
because a session that can install these controls can remove them. (`-Status` is exempt everywhere it
exists: auditing is not installing.)

```powershell
$tooling = "<path-to-this-checkout>"
$target  = "<path-to-the-repo-you-want-governed>"
Set-Location $target      # step 3 reports what it resolves FROM HERE, so stand in the target

# 1. Opt the target in, and -- for the vendored layout -- give it the scripts the coordination
#    hooks resolve. ccx.config.json at its root is both the knob file and the marker that
#    user-scope hooks read to answer "is this repo governed?" without running anything.
Copy-Item "$tooling/ccx.config.json" "$target/ccx.config.json"   # then edit it -- see Configuration
Copy-Item "$tooling/scripts" $target -Recurse                    # vendored layout only
Copy-Item "$tooling/bin" $target -Recurse                        # vendored layout only
# ...then commit them, so every worktree of the target gets them. After vendoring there are two
# copies of these scripts on disk: install and audit from ONE of them. Installing from one and
# hashing against the other is exactly the drift the doctor calls STALE, and it would be right.

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

# 6. The SessionStart backstop. ONE config root per run, so run it again for each root step 7
#    lists under "config roots" -- an unwired root is reported OFF, and OFF is exit 1.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-selfheal.ps1" -ConfigDir ~/.claude

# 7. Prove it -- and prove it about the right repository.
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target
```

### Step 8: prove the repository it governed is the one you meant

The doctor's own default target is the current directory, so a run started in the wrong place
produces a long, plausible, mostly-green report about the wrong clone. It therefore names both roots
at the top of every run, and marks the case where they are the same. Read those lines back:

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target |
    Select-String 'repo examined|tooling checkout|gate: allowlist|LIVE allowlist'
```

```text
  repo examined    : <target>   (-Repo)
  tooling checkout : <tooling>   (every source hash below is read from here)
  [OK ] worktree gate: allowlist           1 checkout(s) governed, including this primary
  [OK ] gate: LIVE allowlist + real primary the installed gate, reading the LIVE allowlist, denies a write to this primary
```

`repo examined` is the repository the whole report is about. `governed, including this primary` is
the allowlist actually containing it, and the `LIVE` line is the installed gate being handed a write
to *that* path and refusing it. If `repo examined` names the tooling checkout, everything below it is
true about the tooling checkout and says nothing about yours.

### What the exit code means when you install only some of it

The verdict is an accounting over every control the run can see, not over the ones you chose:

- **Any `RED`, or any *required* control `OFF`, is exit 1.** The worktree gate, its allowlist, its
  wiring, the three coordination rows, both git hooks and the SessionStart backstop are all required,
  so a partial install of the six steps above **cannot** exit 0. The one you skipped is reported
  `OFF` -- implemented, invoked by nothing, zero enforcement -- not "not chosen".
- **Any `??` with no `RED` is exit 2.** A skip is never a pass.
- **`--` never fails a run.** That tag is for a control that is opt-in by design (the blanket-stage
  guard, the steering injector) or off by configuration (the sequence gate with no `sequences` key).
- **An *opt-in* control reported `OFF` never fails a run either**, and is counted and named on its
  own `OFF (opt-in)` line rather than folded into the `OFF` number. Today that is the sequence gate
  when `sequences` **is** configured -- a real hole, worth an `OFF` rather than a `--` (numbers are
  being allocated and nothing at commit time defends them), but not one a shipped installer ever
  promised to close.

So exit 0 also needs a `python` on `PATH` (the git-hook shims fail open without one), every config
root the run lists wired, and no kill switch set. The `VERDICT` block names every `RED`, `OFF` and
`??` it counted, so you never have to infer which one moved the number.

Then create your second session's worktree. These two are not installers and take no target flag:
they act on the primary of **the repository you are standing in**, wherever the script file itself
lives -- so keep standing in the target.

```powershell
pwsh -NoProfile -File "$tooling/scripts/worktree/new.ps1" -Name alerts
# ...or create it and open an editor window in it:
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name alerts
```

### What the doctor tells you

It never infers. It enumerates every control by receipt (SHA of the *installed* copy against this
checkout's source, live matchers read out of every config root, wired matchers diffed against the
rules the installed script actually implements), then **fires each control on purpose and requires
it to refuse** -- crafted `PreToolUse` JSON at the installed gate, a blanket stage, a commit claiming
an unclaimed item, a push to a protected ref, a drifted throwaway primary in front of the
`SessionStart` backstop. Every attack is paired with a negative control, an ordinary action the same
control must *allow*, because a script that refuses everything is not a working guard either and a
probe with no positive control proves nothing. For the backstop -- which runs `git checkout` on a
shared checkout unattended, and is the most privileged control in the set -- that pair is the drifted
**but dirty** primary it must decline to touch and say why: repairing a clean tree passes whether or
not the dirty-tree refusal is still in the code, so only the negative control tests it. The allocator
is the one check with no allow/deny axis at all; it decides nothing, so what it is paired with
instead is the property that can be violated -- that its read-only floor inspection spends no number
and moves no ratchet. All of it runs against throwaway git repositories in the temp directory,
deleted on the way out; your repository is not touched.

Its status vocabulary is the whole point:

| Tag | Means | Exit |
|---|---|---|
| `OK` | Proven: installed, wired, and it refused what it must refuse | -- |
| `RED` | Proven broken: wired but stale or unloadable, or it allowed what it must deny, or it denied what it must allow | 1 |
| `OFF` | Implemented, but nothing invokes it -- zero enforcement | 1 (when the control ships an installer) |
| `??` | Could not be determined | 2 |

**A skip is never a pass**, which is why `??` has its own exit code. The run always prints a `WHAT
WAS SCANNED` block (config roots, session records read and unplaceable, worktrees, trunk, state
root, which python, which git, platform) and a `BLIND SPOTS ON THIS RUN` block, pass or fail. If it
reports `RED` immediately after a clean install, believe it -- that is the case this command was
built for.

---

## What is in the box

Everything is a plain script. There is no daemon and no background service. Coordination state --
claims, locks, allocations, announce receipts -- lives entirely inside your own git directory. Three
things sit outside it by necessity and are named here rather than discovered: the installed hook
copies and their allowlist, under your client config root; the wiring entries in that root's
`settings.json`; and a queued steering note, at `<worktree>/.claude/steer.txt`.

### Commands you run

| Path | Does |
|---|---|
| `bin/ccx-doctor.ps1` | Prove every control by receipt and by attack. `-Repo <path>` is the repository the report is about (default: the directory you ran it from -- **not** necessarily the one you meant). Also `-ConfigDir`, `-SettingsPath`, `-Json`, `-SkipAttacks`, `-Verbose` |
| `scripts/worktree/new.ps1` | Create an isolated worktree on its own branch, off the **fetched remote tip**, serialised against concurrent adds |
| `scripts/worktree/spawn.ps1` | `new.ps1` plus an editor window (`-Editor`, else `CCX_EDITOR`, else `EDITOR`, else `code`) |
| `scripts/worktree/rescue.ps1` | Move uncommitted work *out* of the shared primary into a fresh worktree -- the companion to the gate that stops you writing there |
| `scripts/worktree/restore-primary.ps1` | Re-attach the primary to its home branch after a session left it detached or on the wrong branch. Refuses on a dirty tree |
| `scripts/worktree/remove.ps1` | Remove one worktree, referencing its tip **before** anything is removed, and writing a keep-ref when `-DeleteBranch` is used |
| `scripts/worktree/prune-merged.ps1` | The reaper: prune = merged **and** clean **and** unoccupied. Dry-run by default; `-Apply` to act |
| `scripts/worktree/sessions.ps1` | Find sessions for this repo across every login, including ones a relocation made invisible. `-Rehome` puts a transcript back |
| `scripts/coord/presence.ps1` | Who is actually live in this repo right now, across every surface. Read-only |
| `scripts/coord/overlap.ps1` | What everyone else is changing -- files *and* stated work. `-File <path>`, `-Json` |
| `scripts/coord/claim.ps1` | Take/release/list a claim on a piece of work. `-Take 105`, `-Take dep-advisory-parse` |
| `scripts/coord/alloc.ps1` | Allocate the next number in a shared sequence, atomically. `-ShowFloor` inspects without spending one |
| `bin/ccx-steer.ps1` | Queue a steering note from a second terminal, delivered at the session's next tool-call boundary |
| `scripts/security/scan_forbidden.py` | The leak gate: refuse identifying content before a private repo goes public. `--path DIR`, `--require-tokens`, `--show-context`. Nothing here wires it -- see `docs/LEAK-GATE.md` |

### Controls the harness or git invokes

| Path | Event | Posture |
|---|---|---|
| `scripts/hooks/worktree_gate.ps1` | `PreToolUse` | Denies writes whose **target path** is inside a governed primary, dispatch from the primary, and the git verbs that swap or discard its tree. Fails open, but loudly |
| `scripts/hooks/collision_gate.ps1` | `PreToolUse` (edit tools) | Refuses a file a **live** session is already changing. Fails open -- never silently |
| `scripts/hooks/block-blanket-git-stage.ps1` | `PreToolUse` (shell) | Denies `git add -A/--all/-u/.` and `git commit -a/-am`. Opt-in. Fails open |
| `scripts/hooks/announce-session.ps1` | `UserPromptSubmit` | Tells peers you exist and what you intend, on the first prompt at which a messageable peer exists. Always exits 0 |
| `scripts/worktree/session-context.ps1` | `SessionStart` | Your project's banner plus a live coordination block. Never fails loudly -- its stdout *is* the chat's starting context |
| `scripts/worktree/worktree-selfheal.ps1` | `SessionStart` | Repairs a primary whose HEAD drifted, when the tree is clean. See `anthropics/claude-code#76590` |
| `scripts/hooks/steer-inject.ps1` | `PreToolUse` (`*`) | Delivers a queued steering note. Opt-in per worktree |
| `scripts/hooks/claim_check.py` | `commit-msg` | Refuses a code-touching commit whose subject claims an item this worktree does not hold. Fail-**closed** |
| `scripts/hooks/push_guard.py` | `pre-push` | Refuses a direct push of a protected ref. That work goes through a pull request |
| `scripts/hooks/seq_check.py` | `pre-commit` (yours) | Refuses a colliding, unallocated, or unindexed sequence number. `--ci` re-runs against a fresh trunk |

### Installers, and why there are four

| Path | Installs | Writes to | Names its target with |
|---|---|---|---|
| `scripts/coord/install-coordination.ps1` | Session banner, collision gate, announce -- as **shims that re-resolve at run time**, so a pull updates every worktree at once | **One** settings file per run: `~/.claude/settings.json` unless moved | `-SettingsPath`. It takes no repository at all -- its shims resolve one per session, at run time |
| `scripts/worktree/install-gate.ps1` | The worktree gate, as an installed **copy** outside every working tree, plus the allowlist that *is* its kill switch | Every config root it finds, plus one shared `~/.claude/hooks` | `-Repo` (which primaries to govern), `-ConfigDir` (which roots to wire) |
| `scripts/coord/install-git-hooks.ps1` | `commit-msg` + `pre-push` into the shared `.git/hooks` | One clone, reaching all of its worktrees at once | `-RepoRoot` (which clone), `-HooksDir` (only for a layout `core.hooksPath` does not cover) |
| `scripts/worktree/install-selfheal.ps1` | The SessionStart backstop, sharing the gate's one allowlist | One config root per run | `-ConfigDir`, which is mandatory. It has no repository of its own: the gate's allowlist is what it governs |

The two that take a repository **refuse to guess** which one. Unset, `-Repo` and `-RepoRoot` mean the
clone you are standing in, and both installers stop rather than proceed when that is not the clone
they ship from -- because the wrong answer there installs, wires, hashes and receipts perfectly while
governing a repository you are not working in.

Three properties, each learned the expensive way:

- **They all refuse to run inside a session.** A session that can install its own gate can uninstall
  it. On the three that carry a `-Status` mode that mode is exempt, because auditing is not
  installing; `install-selfheal.ps1` has no status mode -- ask `ccx doctor` instead.
- **The status modes report by receipt, never by reading a settings file.** An entry in
  `settings.json` is a *claim*; a receipt plus a target that actually resolves is *evidence*. An
  announce hook once sat wired-but-resolving-nothing for hours while the settings file looked
  entirely correct, because a similarly-named entry from another project occupied the slot.
- **They never blindly overwrite a hook that is not theirs**, and `install-git-hooks.ps1` never
  writes `pre-commit` at all -- two tools cannot both own that one file, and the failure mode is
  every commit in the repository blocked.

Why user scope rather than the project's `.claude/settings.json`: `.claude/` is commonly gitignored,
so git cannot deliver a project-level hook to a new worktree. A project hook also lives on one
branch, and a hook whose script path is inside a working tree *vanishes on a checkout* -- after which
the tool call runs anyway, silently.

---

## How the pieces fit

**One state root, and git already gives it to you.** All coordination state lives at
`<git-common-dir>/<prefix>-coord/` -- `alloc/`, `claims/`, `locks/`, `announce/`. That location is
identical across every worktree of a clone (a claim taken in one is visible from another), isolated
per clone (two clones cannot collide), and uncommittable by construction (no `git add -A` can sweep
it into a commit). Its corollary matters: **state outlives the worktree**, so a claim survives the
directory that took it.

**Everything is exclusive-create, never read-modify-write.** A claim, a lock and an allocation are
all "create this file exclusively; the failure to create *is* the mutual exclusion". See the
4-of-8-lost-writes measurement above for why the obvious alternative is not an option.

**There are no TTLs anywhere, and the omission is the design.** A lock that expires on a timer hands
the critical section to a second process while the first is still inside it -- silently, at the exact
moment the operation is slowest, which is when a timeout is most likely to be the wrong inference.
Locks retry and never steal: on timeout they fail loudly and name the holder. A wedged lock you can
see beats a silent double-write you cannot.

**Liveness may only VETO, never PERMIT.** There is no heartbeat anywhere, so nothing can prove a
session is gone. `DEAD`/`STALE`/absent is the *absence of a veto*, not a permission. The fence is
wired so it can only block a destructive action. Read `scripts/coord/session-registry.ps1` for what
each verdict licenses; the inverse reading is the natural one, which is why it is stated next to the
code.

**An empty answer and an unanswerable one must not look alike.** `scripts/coord/occupancy.ps1`
returns a *receipt* alongside its rows -- roots examined, records examined, records that could not be
placed -- and sets `Available` only when there was actually something to examine. A caller about to
destroy something gates on `Available`, prints the receipt, and refuses when it is false. Count what
you examined, not what you found.

**One copy of each safety check.** The liveness fence lives once
(`scripts/coord/session-registry.ps1`), the cwd->worktree matcher lives once
(`scripts/coord/occupancy.ps1`), the path-comparison rule and the worktree-path formula live once
(`scripts/coord/_common.ps1`), the command splitter both shell gates need lives once
(`scripts/hooks/_command.ps1`), and the "which tree would this git command actually touch" resolver
lives once beside it (`scripts/hooks/_gittarget.ps1`). The Python gates cannot dot-source PowerShell,
so they get the one counterpart they need -- config discovery, the git runner, path folding -- in
`scripts/hooks/_ccxconfig.py`, which states the three things the two sides must agree on. Two copies
of a safety check drift, and the copy that drifts is the one nobody is testing -- the shared
substrate files exist precisely because five copies of "resolve the git common dir" had already
drifted into five behaviours, two of which produced a state root at the filesystem root when git
failed.

---

## Configuration

One file, `ccx.config.json`, at your repository root. It is both the knob file and the opt-in
marker -- user-scope hooks run in *every* repository on the machine, so "is this repo governed?" has
to be answerable without running anything.

```json
{
  "prefix": "ccx",
  "trunk": "auto",
  "worktreeLayout": "sibling",
  "setupHook": ".ccx/worktree-setup.ps1",
  "protectedRefs": ["refs/heads/main", "refs/heads/master"],
  "sequences": {
    "adr": {
      "dir": "docs/adr",
      "filePattern": "^docs/adr/(\\d{4})-[^/]+\\.md$",
      "pad": 4,
      "indexFile": "docs/adr/README.md",
      "indexRowPattern": "^\\|\\s*\\[(\\d{4})\\]"
    }
  }
}
```

| Key | Controls |
|---|---|
| `prefix` | The state root name, the git config key, the home-branch marker, the installer markers, the allowlist filename, and the `CCX_*` env prefix |
| `trunk` | `auto` resolves the remote's recorded default branch. Never hardcoded, so a repo on `develop` does not silently get an empty signal |
| `worktreeLayout` | `sibling` or `nested`. The path formula lives once, in `_common.ps1` |
| `setupHook` | What a fresh checkout of *your* project needs. This is the key that makes the tooling language-agnostic -- see `examples/worktree-setup.ps1.example` |
| `protectedRefs` | `push_guard.py`. An explicitly empty list disables the guard **with a message on stderr**, because a guard that is off must never look like a guard that passed |
| `sequences` | `alloc.ps1`, `seq_check.py`, and the item token `claim_check.py` matches. **Omit the key entirely and all sequence machinery is off** |

Two optional files you own: `.ccx/session-banner.md` (your project's SessionStart policy text -- see
`examples/session-banner.md.example`) and the setup hook named above.

Environment overrides: `CCX_CONFIG`, `CCX_TRUNK`, `CCX_PYTHON`, `CCX_EDITOR`, `CCX_SESSION_BANNER`,
`CCX_ALLOW_DIRECT_PUSH`, `CCX_ANNOUNCE_DISABLE`.

**Kill switches are files, not settings.** Hook wiring only takes effect in *newly started* sessions
and an environment variable never reaches a session already running, so the switches that have to
work right now are on disk: delete `~/.claude/hooks/ccx-gate.repos.txt` to ungovern everything, or
create `<state-root>/announce/OFF` to stand announce down. `ccx doctor` reports every disarm it
finds, so a switch you left flipped cannot quietly become the status quo.

---

## What it costs

Always-on hooks are a standing tax on every prompt, so the numbers are published rather than left to
be discovered. Measured on the repo this tooling was developed in:

| Hook | Cost | Note |
|---|---|---|
| Coordination shim (`UserPromptSubmit`) | ~0.5 s on **every** prompt, in every repo on the machine | The cheap marker check runs before the expensive lookup |
| Announce peer lookup | ~1.0 s on the prompts where it actually runs | Backed off deliberately: at most once a minute for the first ten checks, then once every ten minutes, stopping after 40 |
| `steer-inject.ps1` on `*` | ~366 ms per **tool call**, ~267 ms of which is bare `pwsh` startup and unavoidable | Which is why it is opt-in per worktree, not wired globally |
| `alloc.ps1` floor sweep | ~1 s, once per allocation | Not per edit |
| `overlap.ps1` git walk | ~1 s across a dozen worktrees | Cached, so the gate's common case is a cache read |

---

## Honest limits

- **These are guardrails against the accidental action, not security boundaries.** Every gate here
  inspects tool arguments or a command string, so a file written by a shell command is invisible to
  the `PreToolUse` gate, and **any agent-authored script defeats a command-string rule outright**.
  `git commit --no-verify` and `git push --no-verify` bypass the git hooks. The commit-time hooks are
  the backstop for the tool-time ones, because they inspect the *tree*; back the push guard with
  server-side protection if you need a real one.
- **False positives are the expensive failure.** A gate that denies ordinary work trains sessions to
  route around it, and a routed-around gate protects nothing. The rules here are deliberately narrow
  for that reason, and the fail-open postures are deliberate -- but they are *declared*, per hook,
  and they never fail open silently.
- **Enumerated coverage means every hole is silent.** The gates match named tools and named verbs.
  Anything outside the enumeration passes without a word. `ccx doctor`'s wired-versus-implemented
  diff is the only thing that surfaces a rule which exists but can never fire.
- **The occupancy fence is cwd-keyed and therefore partial.** It cannot see a session writing into a
  worktree by absolute path from somewhere else, a cwd recorded as a UNC or 8.3 short path, or a
  session that never registered. The reaper carries a second, non-cwd signal for that reason and
  prints its blind spots; do not build a destructive action on the cwd signal alone.
- **The collision gate's deny path is not self-testable.** Proving it needs a live peer worktree
  holding an uncommitted change to the same file. `ccx doctor` proves only that the gate refuses to
  go *silent* on its unresolvable path, and prints that as a blind spot on every run.
- **A claim cannot stop a session that refuses to look.** What it buys is that the collision becomes
  visible *before* the work rather than after. Claims do not expire, and releasing is manual: an
  abandoned claim is a stale note, whereas an auto-expiring one silently re-opens the race it exists
  to prevent.
- **Two sequences that both number from 1 share one claim namespace.** Claim keys are flat -- the key
  a person types is the key on disk. Worth knowing before you configure overlapping sequences.
- **No CI-side enforcement is shipped.** `seq_check.py --ci` exists and re-runs the collision rules
  against a freshly fetched trunk, but wiring it into your pipeline is yours. Note that the
  allocation-ownership rule *cannot* run in CI -- it reads a per-clone registry a runner does not
  have -- and it is reported as not running rather than left in place looking like coverage.

---

## The doc set

| Doc | What it covers |
|---|---|
| `README.md` | This file: what it is, the platform and MCP caveats, and the five-minute path |
| `INSTALL.md` | The installers, their scopes, and how to *prove* each one is live rather than merely merged |
| `docs/CONCEPTS.md` | The model: worktree-per-session, the shared state root, the liveness fence, exclusive-create, why there are no TTLs |
| `docs/HOOKS.md` | The hook-event map, the wiring contract, and the house rules for writing one that cannot fail silently |
| `docs/WORKTREES.md` | Day to day: create, rescue, restore, remove, and the two layouts that coexist |
| `docs/PRUNING.md` | The reaper and its fence -- why clean + merged is not unoccupied, and why a failed removal is worse than none |
| `docs/COORDINATION.md` | Presence, overlap, claims, locks, announce, and the rules for talking to a peer |
| `docs/PR-AND-MERGE.md` | Landing work from N branches into one trunk, and the four states that all read as "can't merge" |
| `docs/SEQUENCE-ALLOC.md` | Allocating a shared sequence git cannot see, with decision-record numbers as the worked example |
| `docs/STEERING.md` | The two steering scripts: queue a note from a second terminal, deliver it mid-task |
| `docs/LEAK-GATE.md` | The forbidden-content scanner: what a shape detector catches before a repo goes public, what a token file adds, and the two things no scanner can ever see |
| `docs/CI-AND-STANDARDS.md` | N parallel branches through one pipeline, and a standard that survives agent-written code. Ships no CI configuration -- the scripts it cites are illustrations of the rules |
| `docs/CASE-STUDY-drift-audit.md` | A redacted account of auditing a multi-session estate as one system -- the method, not a status snapshot |
| `docs/ASVS-ASSESSMENT.md` | Method for running a several-hundred-requirement security-standard assessment with agent sessions. Deliberately carries no results, for the same reason the case study carries no status table |
| `docs/TIPS-AND-TRICKS.md` | The "wish I'd known" file, ordered by when it bites: setting up, running two at once, writing a guardrail, proving it works, cleaning up |
| `docs/USAGE-AWARENESS.md` | Warning a session before it hits a hard usage cutoff, and why that is harder than it looks. Ships no hook -- the mechanism depends on undocumented client internals, so what transfers is the design and the eight ways it reports confidently wrong numbers |
| `CLAUDE.md.template` | A working agreement to drop into your own repo: plan first, commit-versus-push approval split, never grep for a number, shared memory across worktrees |

Worked examples live in `examples/`: a language-agnostic worktree setup hook
(`worktree-setup.ps1.example`), a session banner (`session-banner.md.example`), an annotated sequence
gate kept as narrative rather than wired to anything (`ledger_check.annotated.py`), and a complete
filled-in sequence configuration with its index-row format (`sequence-adr/`).

---

## Conventions

Small, boring, and load-bearing when several tools write files another tool reads:

- **UTF-8 without BOM**, LF, ISO-8601 timestamps that round-trip.
- **ASCII-only output** from every hook. A console that is not UTF-8 renders anything else as
  mojibake, and one convention across the set beats two.
- **Stdlib only** in the Python gates, and no import of the surrounding project -- these run in
  worktrees that may have no virtualenv. A gate that skips because an import failed is worse than no
  gate, because it still looks installed.
- **Marker strings are on-disk identity.** Installers decide whether a hook is theirs by matching a
  marker inside the installed file, and no marker is a substring of another. Renaming one orphans
  every existing install, so if you must, do it once, in one commit.
- **Folded paths are for comparison only** -- never hand one to git, to the filesystem, or to a
  message a human reads. Case-folding is conditional on the platform, because on a case-sensitive
  filesystem two spellings really are two directories.

## Licence

MIT. See `LICENSE`.
