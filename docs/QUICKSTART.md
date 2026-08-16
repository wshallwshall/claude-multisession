# Quickstart

## TLDR/BLUF

**What this is.** The install, start to finish, and then two sessions that refuse to overwrite each
other. Seven steps, run from a plain terminal, against a repository you already have.

**Why you should care.** Step 7 is the point: you make two sessions edit one file, and watch the
second one get refused. Until you have seen that refusal, nothing here is proven to be running. Not
for you if you have no repository to govern yet.

**How to use it.** Work the steps in order. Read
[Limits and requirements](LIMITS.md) first if you are on a CLI-only install, because one of the four
controls needs the desktop client.

---

## What you need

`pwsh` 7.3 or newer, `git`, and a `python` on `PATH`. The full table, and what breaks when each is
missing, is on [Limits and requirements](LIMITS.md).

Every command below runs in a **plain terminal**, not inside a Claude Code session. All four
installers refuse when `$env:CLAUDECODE` is `1`, because a session that can install these controls
can remove them.

## 1. Name the two directories

Every command says which directory it means, because the installers refuse to guess.

| | |
|---|---|
| **tooling** | This checkout. Nothing you install governs it. Scripts are copied from here and hashed against it. |
| **target** | The repository you want governed. It gets the config file, the git hooks, and its primary checkout in the gate's allowlist. |

```powershell
$tooling = "<path-to-this-checkout>"
$target  = "<path-to-the-repo-you-want-governed>"
Set-Location $target      # the doctor reports what it resolves FROM HERE, so stand in the target
```

## 2. Vendor the tooling into the target

Copy the scripts into the target and commit them, so tooling *is* target. That is the only layout in
which the doctor can reach exit 0.

```powershell
Copy-Item "$tooling/ccx.config.json" "$target/ccx.config.json"   # then edit it
Copy-Item "$tooling/scripts" $target -Recurse
Copy-Item "$tooling/bin" $target -Recurse
```

Then commit them, so every worktree of the target gets them.

**Trap.** After vendoring there are two copies on disk. Install and audit from **one** of them.
Installing from one and hashing against the other is exactly the drift the doctor calls `STALE`.

The separate-checkouts layout works for the worktree gate, both git hooks and the backstop. It fails
for the three coordination hooks: they resolve their script inside whatever repository the session
runs in, so a target without those files gets three wired hooks that resolve nothing.

## 3. Baseline the doctor before installing anything

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target
```

Expect a wall of `OFF` and exit 1. **That is the correct result.** It is the only way to tell an
installed guardrail from a decorative one afterwards.

## 4. Install the four controls

They are four rather than one because they write to genuinely different places.

```powershell
# Coordination hooks: session banner, collision gate, announce. Takes NO repository -- it writes
# ONE settings file whose hooks resolve their repo per session at run time.
pwsh -NoProfile -File "$tooling/scripts/coord/install-coordination.ps1"

# The commit-msg claim gate and pre-push guard, into the TARGET clone's shared .git/hooks, where
# one copy governs every worktree of that clone at once.
pwsh -NoProfile -File "$tooling/scripts/coord/install-git-hooks.ps1" -RepoRoot $target

# The worktree gate. -Repo names the PRIMARY checkout to allowlist (several allowed:
# -Repo <path-a>,<path-b>). The allowlist is the kill switch.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-gate.ps1" -Repo $target

# The SessionStart backstop. ONE config root per run -- run it again for each root the doctor
# lists under "config roots". An unwired root is OFF, and OFF is exit 1.
pwsh -NoProfile -File "$tooling/scripts/worktree/install-selfheal.ps1" -ConfigDir ~/.claude
```

## 5. Prove the install landed on the right repository

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target
```

The doctor's default target is the current directory, so a run started in the wrong place produces a
long, plausible, mostly-green report about the wrong clone. These four lines say which clone it read:

```powershell
pwsh -NoProfile -File "$tooling/bin/ccx-doctor.ps1" -Repo $target |
    Select-String 'repo examined|tooling checkout|gate: allowlist|LIVE allowlist'
```

## 6. Spawn two sessions

```powershell
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name alerts
pwsh -NoProfile -File "$tooling/scripts/worktree/spawn.ps1" -Name parser
```

Each call creates an isolated worktree on its own branch and opens an editor window in it. `new.ps1`
does the same without the editor. Neither takes a target flag: both act on the primary you are
standing in, so stay in the target.

Start a session in each window, then confirm they can see each other:

```powershell
pwsh -NoProfile -File "$tooling/scripts/coord/presence.ps1"   # both sessions listed
pwsh -NoProfile -File "$tooling/scripts/coord/overlap.ps1"    # what each is changing
```

## 7. Watch a collision get refused

**The goal.** Prove the collision gate is live rather than merely installed.

**What to do.** In session `parser`, ask it to edit a file and leave the change uncommitted. Then in
session `alerts`, ask it to edit the same file.

**What happens next.** The second edit never runs. The tool call is refused, and Claude is handed
this:

<!-- no-copy -->
```text
service.py has UNCOMMITTED changes in another LIVE session's worktree -- editing it now means one of you loses work at merge.

  parser (desktop) in C:/repo/.claude/worktrees/parser [claude/parser-4f2a1c]
      building: the CSV column parser

Before overriding: that session may already be doing what you are about to do.
  see everything in flight :  pwsh -NoProfile -File scripts/coord/overlap.ps1
  who is live              :  pwsh -NoProfile -File scripts/coord/presence.ps1
If you genuinely need this file, coordinate first -- or edit a different one.
```

That refusal is the whole product. Everything else on this site exists to widen it or to prove it is
still there.

**What it will not do.** The gate refuses on an *uncommitted* edit in a *live* worktree. A peer that
committed its change and went clean is reported and allowed, because that work may overlap yours and
is not worth refusing over. [Coordination](COORDINATION.md) owns the full rule.

## What you have now

Four controls, and each one covers a failure the others do not:

| Control | Refuses |
|---|---|
| Worktree gate | A write into the shared primary checkout, and the git verbs that swap its tree |
| Collision gate | An edit to a file a live session has uncommitted changes in |
| `commit-msg` claim gate | A commit whose subject claims work this worktree does not hold |
| `pre-push` guard | A direct push to a protected ref |

## Next

**Give the sessions a working agreement.** Copy
[CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template)
into the target as `CLAUDE.md` and cut it to what is true there. It is where you write down what the
gates cannot see. Keep it short: a stale one still gets acted on.

**Then scale up.** [Run a KORUS build](KORUS-BUILD.md) is the four-session shape this all exists to
support: a dispatcher, two builders and a lander.

[INSTALL.md](INSTALL.md) is the record of record for the
installers: the annotated version of these steps, and how to prove each one is live rather than
merely merged.
