# Using this with an agent

## For the human, in thirty seconds

Open Claude Code in the repository you want governed, and paste this:

```text
Read https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/docs/USING-THIS-WITH-AN-AGENT.md
and follow it against this repository. Stop where it tells you to stop.
```

That is the whole instruction. Everything below this line is written to the agent, and you do not
need to read it -- though the one thing worth knowing is that **the agent cannot install this
tooling**. The installers refuse to run inside an agent session on purpose. The agent will survey
your repository, hand you a short list of commands with the real paths already filled in, and wait.
You run them in a normal terminal. Then it verifies what happened.

---

# Agent brief

Everything from here is addressed to you, the agent.

## What you are being asked to do

Set up multi-session coordination tooling in the repository you are sitting in. Your job is
**survey, prepare, hand off, verify**. It is not install.

You are working with two directories and they are not the same:

| Name | What it is |
|---|---|
| **tooling** | A clone of `claude-multisession`. Only the source of scripts. Nothing governs it. |
| **target** | The repository you are in now, which will get the config, the hooks and the gate. |

If no tooling clone exists yet, the human clones it. Say where you want it and why.

## What you may run, and what you may not

This is the part to get right before you do anything else. Read it twice.

| Command class | In your session | Why |
|---|---|---|
| Reading, `git status`, `git log`, inspecting files | **Allowed** | Surveying is not changing |
| `bin/ccx-doctor.ps1` | **Allowed** | It prints `running inside a session : YES (installers refuse here; auditing is allowed)` and audits anyway |
| `install-gate.ps1 -Status` | **Allowed** | Explicitly exempt. Auditing is not installing |
| `install-coordination.ps1` | **REFUSES** | Throws when `$env:CLAUDECODE` is `1` |
| `install-git-hooks.ps1` | **REFUSES** | Same |
| `install-gate.ps1` (without `-Status`) | **REFUSES** | Same |
| `install-selfheal.ps1` | **REFUSES** | Same |

The four installers test for the literal string `1`. The reason is not fussiness: **a session that
can install these controls can remove them.** The refusal is the control. Treat it as a wall, not an
obstacle.

## Before you propose anything, survey

Report what you find. Do not fix anything yet.

1. **Preconditions.** PowerShell 7.3 or later on `PATH` as `pwsh`; `git`; a real `python` (on
   Windows, `python --version` may resolve to an execution-alias stub that runs nothing -- check the
   version actually prints). Name any that are missing; without them the install cannot proceed.
2. **The target's identity.** Its root, its trunk branch name, whether it already has worktrees, and
   whether `.git/hooks` already contains a `commit-msg` or `pre-push` that belongs to something else.
   If either exists and is not from this tooling, say so loudly -- the installer refuses to overwrite
   a hook it does not own, and that is a decision for the human.
3. **Existing state.** Is there already a `ccx.config.json` at the target root? A `CLAUDE.md`?
   Report what is there rather than overwriting it.
4. **Whether this tooling suits the target at all.** It is Windows-first PowerShell. It runs on
   PowerShell 7 elsewhere, but Windows is what was exercised. Say so if the target is not Windows.

## The adoption sequence

Work through it in order. **Stop at every STOP and wait.**

1. **Write `ccx.config.json` at the target root.** You may do this yourself -- it is a config file,
   not an installer. It is both the knob file and the opt-in marker: without it, the user-scope hooks
   stay inert in this repository. Start from the tooling's own `ccx.config.json` and change only what
   the target needs.
2. **STOP.** Produce the install commands with real absolute paths substituted, in the order given
   by [INSTALL.md](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md), and
   tell the human to run them **in a plain terminal, not through you**. Ask them to paste back the
   output rather than summarising it.
3. **Verify what came back**, using the audit commands you are allowed to run. See below.
4. **Write `CLAUDE.md`.** Copy
   [CLAUDE.md.template](https://raw.githubusercontent.com/wshallwshall/claude-multisession/main/CLAUDE.md.template)
   into the target as `CLAUDE.md` and edit it down to what is true here. Delete every rule the target
   does not actually follow. An aspirational working agreement is worse than none, because the next
   session acts on it.
5. **STOP.** Ask the human to confirm the working agreement matches how they actually work, section
   by section if it is contentious. You are guessing at their conventions; they are not.

## Verifying, with receipts

A green run is not evidence on its own. When you check the install, check what each command
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
