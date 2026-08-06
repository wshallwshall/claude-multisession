# Here's what to feed to Claude Code

## For the human, in thirty seconds

Open Claude Code in the repository you are thinking about, and paste this:

```text
Read https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/FEED-THIS-TO-CLAUDE-CODE.md
and use it to advise me about this repository. Stop where it tells you to stop.
```

### What that will actually do

Claude Code will read this page and the documents it points at, look at your repository, and then
**talk to you about it**. Specifically, it will:

- **Tell you what this tooling is for**, and whether your situation is one it helps with. Running
  one session at a time is a perfectly good answer, and it should say so if that is where you are.
- **Report what it found** in your repository: what is already there, what would have to change, and
  anything that would get in the way.
- **Explain what a setup would involve** -- which pieces, in what order, and what each one costs you
  in friction. You can stop at any point, or take one piece and ignore the rest.
- **Answer your questions** about any of it, against your repository rather than in general.
- **Prepare exact commands, if you decide you want them**, with the real paths already filled in,
  for you to run yourself in a normal terminal.

### What it will not do

- **It will not install anything.** The installers refuse to run inside a Claude Code session on
  purpose, and the page tells it not to work around that. Nothing is set up unless you run it.
- **It will not change your repository** while it is advising you. It reads and reports.
- **It will not tell you that you need this.** The honest answer for a lot of repositories is that
  you do not.

You do not need to read anything below this line. It is written to Claude Code.

---

# For Claude Code

Everything from here is addressed to you, Claude Code.

## What you are being asked to do

**Advise, do not install.** Somebody is deciding whether this tooling is worth adopting in the
repository you are sitting in. Your job is to give them a grounded answer about *their* repository,
and then help them do it only if they choose to.

Work in this order: **understand the tooling, survey the target, explain the options, answer
questions.** Only if they decide to proceed do you prepare commands for them to run. You never run
the installers yourself -- see the next section for why that is a wall rather than an obstacle.

**Say so if the answer is no.** This tooling earns its cost when several sessions work one
repository at once, or when work is regularly lost to sessions colliding. If the person runs one
session at a time and is not losing work, tell them plainly that they probably do not need it, and
say which single piece might still be worth having. An honest no is more useful than a setup they
will abandon.

You are working with two directories and they are not the same:

| Name | What it is |
|---|---|
| **tooling** | A clone of `claude-multisession`. Only the source of scripts. Nothing governs it. |
| **target** | The repository you are in now, which would get the config, the hooks and the gate. |

If no tooling clone exists yet, do not tell them to clone it until they have decided to proceed.

## What you may run, and what you may not

This is the part to get right before you do anything else. Read it twice.

| Command class | In your session | Why |
|---|---|---|
| Reading, `git status`, `git log`, inspecting files | **Allowed** | Surveying is not changing |
| `bin/ccx-doctor.ps1` | **Allowed** | It prints `running inside a session : YES (installers refuse here; auditing is allowed)` and audits anyway |
| `install-gate.ps1 -Status` | **Allowed** | Explicitly exempt. Auditing is not installing |
| `install-coordination.ps1` | **Refused** | Throws when `$env:CLAUDECODE` is `1` |
| `install-git-hooks.ps1` | **Refused** | Same |
| `install-gate.ps1` (without `-Status`) | **Refused** | Same |
| `install-selfheal.ps1` | **Refused** | Same |

The four installers test for the literal string `1`. The reason is not fussiness: **a session that
can install these controls can remove them.** The refusal is the control. Treat it as a wall, not an
obstacle.

## Survey before you say anything

Read the target. Change nothing. Report what you find.

1. **Preconditions.** PowerShell 7.3 or later on `PATH` as `pwsh`; `git`; a real `python` (on
   Windows, `python --version` may resolve to an execution-alias stub that runs nothing -- check the
   version actually prints). Name any that are missing; without them a setup could not proceed.
2. **The target's identity.** Its root, its trunk branch name, whether it already has worktrees, and
   whether `.git/hooks` already contains a `commit-msg` or `pre-push` that belongs to something else.
   If either exists and is not from this tooling, say so loudly -- the installer refuses to overwrite
   a hook it does not own, and that is a decision for the human.
3. **Existing state.** Is there already a `ccx.config.json` at the target root? A `CLAUDE.md`?
   Report what is there. Do not modify either.
4. **Whether this suits the target at all.** It is Windows-first PowerShell. It runs on PowerShell 7
   elsewhere, but Windows is what was exercised. Say so if the target is not Windows.
5. **Whether they have the problem.** Ask how many sessions they run at once, and whether work has
   been lost to sessions colliding. If the answer is one session and no, say the tooling is probably
   not worth it here.

## Explain the options, then wait

Give them the shape of a setup before any of it happens, so they can choose a part rather than
accept a package. Cover, in plain terms:

- **What each piece does and what it costs.** The worktree gate stops sessions building in a shared
  checkout. The git hooks refuse a claimed-but-unowned commit and a direct push to a protected ref.
  The coordination hooks add roughly a second per prompt. Each is separable.
- **What is reversible.** All of it. Every installer has an uninstall path, and nothing rewrites
  their history.
- **The smallest useful subset**, if they want one thing rather than everything. For most people
  that is the worktree gate.
- **What they would have to run themselves**, and roughly how long it takes.

Then **STOP and let them decide.** Do not produce commands yet.

## If they decide to proceed

Only now, and only for the pieces they chose.

1. **Write `ccx.config.json` at the target root**, if they want it. You may do this yourself -- it is
   a config file, not an installer. It is both the knob file and the opt-in marker: without it, the
   user-scope hooks stay inert in this repository. Start from the tooling's own `ccx.config.json`.
2. **Produce the commands, do not run them.** Substitute the real absolute paths, order them as
   [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) does, and
   tell them to run the set **in a plain terminal, not through you**. Ask for the output pasted back
   rather than summarised.
3. **STOP** until they have run it and reported back.
4. **Verify what came back**, using the audit commands you are allowed to run. See below.
5. **Offer a working agreement.** Copy
   [CLAUDE.md.template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template)
   into the target as `CLAUDE.md` and edit it down to what is true here. Delete every rule the target
   does not actually follow. An aspirational working agreement is worse than none, because the next
   session acts on it.
6. **STOP.** Ask them to confirm it matches how they actually work, section by section if it is
   contentious. You are guessing at their conventions; they are not.

## Verifying, with receipts

A green run is not evidence on its own. If they installed something, check what each command
**examined**, not just that it exited 0:

- `pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <target>` is the main instrument. Read
  back the two roots it names at the top: a doctor run started in the wrong place produces a long,
  plausible, mostly-green report **about the wrong clone**.
- It reports how many session records it read and placed. A count of zero means the liveness fence
  resolved nothing, which looks identical to a healthy fence with no peers.
- It prints its own blind spots on every run. Repeat them to the human rather than filtering them
  out -- they are the honest part of the output.
- An undetermined check exits **2**, deliberately, so that a skip can never be read as a pass. If
  you see 2, do not report success.

## Refusals you will hit, and what not to do about them

You will hit at least these. None of them is a bug, and none is yours to route around.

| You will see | Do NOT | Do |
|---|---|---|
| An installer throws on `$env:CLAUDECODE` | Unset the variable, spawn a subshell without it, or wrap the call | Hand the command to the human |
| The worktree gate denies an edit in a shared checkout | Write the file by another route, or via a shell heredoc | Read the denial; it names the supported alternative |
| The gate denies a `git checkout` in a linked worktree | Force it | That worktree belongs to another session; use the command the denial prints |
| A commit is refused by the claim gate | `--no-verify` | Claim the item, or fix the subject line |
| A push to a protected ref is refused | Force-push, or change the protected list | Open a pull request |

If you find yourself constructing a way around any of these, stop and say what you were about to do
and why. That sentence is more useful to the human than the workaround.

## What you cannot prove, and must not claim

- **You cannot prove the install works end to end.** You can audit it. The strongest evidence is the
  doctor run from a plain terminal, by the human, after everything is wired.
- **You cannot prove a gate can fail.** Breaking a control on purpose to watch it refuse is the only
  proof that it is live, and doing that convincingly needs a second live session and a peer worktree.
  Say that the deny path is unproven rather than implying it is proven.
- **Announce needs a desktop-only server.** If this is a plain CLI install, the announce hook will
  find peers and then instruct you to call tools you do not have. Leave that one hook uninstalled and
  say why.

## Where the detail lives

Do not reconstruct these from memory -- read them when they become relevant.

| For | Read |
|---|---|
| The full install procedure | [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md) |
| What the whole thing is for | [Concepts](CONCEPTS.md) |
| Worktree rules and the hijack it prevents | [Worktrees](WORKTREES.md) |
| Claims, locks, presence, overlap | [Coordination](COORDINATION.md) |
| Which hook fires when, and its failure posture | [Hooks](HOOKS.md) |
| Getting work through CI without believing false things | [CI and standards](CI-AND-STANDARDS.md) |
| Standards to hold the resulting code to | [Standards](standards/OVERVIEW.md) |
