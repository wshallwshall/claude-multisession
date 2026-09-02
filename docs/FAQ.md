# Frequently asked questions

## TLDR/BLUF

**What this is.** The questions an evaluator asks before installing anything, answered where they
ask them. The first one is the one that decides whether you need this project at all.

**Why you should care.** Several sessions at once is how a build gets dramatically faster, and the
only thing in the way is them conflicting. Claude Code ships its own worktrees now, so the first
question is which half of KORUS you still need.

Not for you if you have already installed it and want a specific command.

**How to use it.** Read the first answer. If it says you do not need this, believe it. KORUS assumes
Claude Code for Desktop throughout.

---

## Why not just use Claude Code's own worktrees?

For a lot of work, that is the right answer, and it has become more right over time.

`claude --worktree <name>` creates an isolated checkout under `.claude/worktrees/<name>/` on its own
branch, and the desktop app gives every new session one automatically.

While a session is isolated, Claude Code **blocks** the tool calls that would reach back into the
main checkout. Four checks do it, and how many you get depends on the shell:

| Check | What it blocks | Applies to |
|---|---|---|
| File edits | An `Edit`, `Write` or `NotebookEdit` targeting the main checkout | Any isolated session |
| Command working directory | A command whose working directory resolves to the main checkout | Bash, PowerShell, Monitor |
| Git redirects | `git -C`, `--git-dir`, `GIT_DIR`, `GIT_WORK_TREE`, or a `cd` into the main checkout | Bash and Monitor only |
| Command shape | A command it cannot verify stays inside the worktree. Cannot be turned off | Bash and Monitor only |

Read from
[Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees) on 2026-08-16.

**Two limits, and the second decides it here.**

The checks apply only *while a session is isolated*. A session running in the primary gets none of
them.

And the last two do not reach PowerShell: "For PowerShell commands, Claude Code applies only the
working-directory check."

So an isolated PowerShell session keeps the first two and loses the other two. It can still run
`git -C <primary> checkout -B ...`, because its working directory legitimately stays in the worktree
and that is the only command check it faces.

| What you need | Claude Code's own worktrees | What KORUS adds |
|---|---|---|
| A checkout and branch per session | Yes, and automatically in the desktop app | Nothing. Use the native one |
| Stopping a session writing into the main checkout | Yes, while that session is isolated, including a write made by a shell redirect | The refusal for the **edit tools**, from a session that is not isolated, on any primary in its allowlist. It does not judge a command's working directory |
| Isolating subagents from each other | Yes: `isolation: worktree` per subagent, and the same four checks cover them | Also denies a `Task`, `Agent` or `Workflow` dispatch made **from** the primary, since a subagent inherits its parent's directory |
| Stopping `git -C <primary>` from a PowerShell command | **No.** Only the working-directory check reaches PowerShell | Refuses an enumerated set of tree-swapping git verbs in a `Bash` or `PowerShell` tool call, on a primary in its allowlist |
| Two isolated sessions editing the same file | Not addressed. Each is isolated from the main checkout, not from the other | Refuses the second edit before it runs, naming who holds the file. Fails open when it cannot check, and says so |
| Two sessions taking the same record number | Not addressed | Atomic allocation. The commit-time gate exists, no installer wires it, and the doctor reports it `OFF` until you do |
| Knowing who is live, and what each is changing | Not addressed | `presence.ps1` and `overlap.ps1` |
| Proving any of it is actually running | Not addressed | `bin/ccx-doctor.ps1` attacks every control that makes a decision, and names on each run what it could **not** prove -- the collision gate's refusal among them |

Neither the gate nor the collision check sees a write that arrives another way. An agent-authored
script carries no git verb, and `gh pr checkout <n>` carries no `git` token at all
([Hooks](HOOKS.md)).

**Two axes decide this, not one.**

**Work overlap.** If two sessions never touch the same files, numbers or feature, native worktrees
plus a human reviewer is simpler, and simpler wins.

**The shell.** On PowerShell, if any session runs git against the primary, the worktree gate is what
covers it. That holds whether or not the work overlaps: a tree swap produces no textual conflict for
a reviewer to catch.

## Is this a security boundary?

**No.** It prevents accidents. It does not stop an adversary, and it is not meant to.

Every control here runs as the same operating-system identity as the agent it constrains, so that
agent can edit the hook, the allowlist and the settings file.

Three documented exits need no editing at all. `--no-verify` skips a hook, once on a commit and
again on a push. `CCX_ALLOW_DIRECT_PUSH=1` returns before the config is even read. An explicitly
empty `protectedRefs` disables the push guard and says so on stderr.

**None of them leaves a local record.** A one-shot environment prefix leaves nothing for a later run
to find, and nothing local sees that `--no-verify` happened.

There is a quieter one. Both git gates are `/bin/sh` shims that locate a python and exec the
checker. With no python found, each prints `THE CLAIM GATE IS OFF for this commit.` or the push
equivalent on stderr and **exits 0**, with every file still present and still looking installed.

[Limits and requirements](LIMITS.md) states what to pair it with: protected branches on the remote,
required status checks, and credentials that cannot bypass them. Evidence has to come from that
plane, because this one keeps no record.

## Can a team of developers use this?

Partly, and the boundary is sharp: **the guarantees stop at the clone.**

Claims and allocations live beside the git common directory, so every worktree of one clone shares
them. A second developer on a second clone has a second registry, and both can allocate the same
number before either lands.

**The collision gate is the bigger casualty.** It refuses an edit when a live peer holds uncommitted
changes to that file in a worktree of *your* clone. A colleague editing the same file on their own
machine is invisible to it.

The scope is not uniform, either. The push guard installs per clone; the worktree gate's allowlist
lives under your user config directory, so it is per machine. Nothing aggregates across either, and
the doctor says so: only this clone was examined.

`scripts/hooks/seq_check.py --ci` re-runs three of its four rules against a freshly fetched trunk,
which catches a cross-clone duplicate after the fact. No installer wires it.

Allocation ownership is **not** among the three, because the registry is per-clone. A green `--ci`
run is not evidence a number was allocated to anybody.

One habit helps before any of that: `git fetch origin --prune` before you allocate, because the
allocator's floor sweeps remote-tracking refs and will step past a peer's pushed number.

For a team, treat this as a local coordination layer and put the authoritative check on the remote.
[Sequence allocation](SEQUENCE-ALLOC.md) owns the detail.

## What does it need to run?

Claude Code for Desktop, `pwsh` 7.3 or newer, `git`, a `python` on `PATH`, and a `ccx.config.json`
at the root of the repository you want governed.

**Windows is the exercised path.** On Linux, path comparison stops folding case and the roster's
self-marking degrades. macOS is not in the CI matrix at all: treat it as unmeasured rather than
working. [Limits and requirements](LIMITS.md) has the table.

## Do I need Claude Code for Desktop?

**Yes. KORUS is a desktop framework.** A CLI-only or editor-extension setup is not a configuration
this project supports, and the site does not describe one.

The reason is that the coordination layer is shaped by the desktop app:

- Announce delivers through `ccd_session_mgmt`, an MCP server only the desktop client provides.
- `list_sessions` enumerates only sessions that app spawned, so an editor-extension session cannot
  be messaged at all.
- The desktop app gives every new session its own worktree automatically.
- Running several sessions in the VS Code extension has run into worktree hijacking
  ([Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md)).

Some pieces do run anywhere `pwsh` does -- the worktree gate, the collision gate and the two git
hooks are ordinary scripts. Running them without the desktop app is not KORUS, and nothing here
tells you how far that gets you.

## Does it work in CI?

**Not the doctor**, and that is a decision rather than a gap. `.github/workflows/gates.yml` says why
in its own header. The doctor fires each control on purpose, and a run that skipped those paths and
reported green would be a worse signal than not running it at all.

It stays a local, plain-terminal command.

The leak gate does run in CI. `seq_check.py --ci` is written for one, and no installer wires it.

**The hooks split.** The harness hooks need a Claude Code session, and under `claude -p` they take
the synchronous path and can hold a pipeline step for their whole timeout.

The two git hooks need only a commit or a push and a python. They are absent from CI because a fresh
clone has no hooks installed, not because they could not run.

## What happens when Claude Code changes the session registry format?

Everything answering "who is live" degrades to "cannot tell". How that surfaces depends on which
half changed, and the two do not look alike.

**A renamed field, or a changed unit.** The records still parse and still place, so the doctor's
counts do not move. Every verdict becomes `UNVERIFIED`, which **is** a veto -- so the gates keep
refusing rather than waving work through. You lose precision, not the guarantee.

**A moved directory.** Now there are no records, the counts go to zero, and an empty roster reads
exactly like a real all-clear. The collision gate allows every edit in silence. The census catches
this one; nothing inside a session does.

Absence of a refusal is never evidence of absence of a peer.

## How many sessions should I run?

The shape this is built around is one long-lived console session and the short-lived ones it spawns.
A builder takes a task, a reviewer reads a pull request, a regulator handles a red check, and a
lander merges. [Run a KORUS build](KORUS-BUILD.md) has the procedure.

More is not obviously better. The reported case that started this project was roughly fourteen
sessions on one directory, and the limit there was not the tooling.

## Related

| For | Read |
|---|---|
| Installing it, and seeing a refusal | [Quickstart](QUICKSTART.md) |
| What it needs, and where it stops | [Limits and requirements](LIMITS.md) |
| Something is behaving oddly | [Troubleshooting](TROUBLESHOOTING.md) |
| The method behind the tooling | [The KORUS framework](KORUS.md) |
