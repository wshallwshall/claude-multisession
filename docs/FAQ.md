# Frequently asked questions

## TLDR/BLUF

**What this is.** The questions an evaluator asks before installing anything, answered where they
ask them. The first one is the one that decides whether you need this project at all.

**Why you should care.** Claude Code ships its own worktrees now, and they cover more than they used
to. Reading this before the install tells you which half of KORUS you actually need. Not for you if
you have already installed it and are looking for a specific command.

**How to use it.** Read the first answer. If it says you do not need this, believe it.

---

## Why not just use Claude Code's own worktrees?

For a lot of work, that is the right answer, and it has become more right over time.

`claude --worktree <name>` creates an isolated checkout under `.claude/worktrees/<name>/` on its own
branch, and the desktop app gives every new session one automatically.

While a session is isolated, Claude Code **blocks** the tool calls that would reach back into the
main checkout. That covers file edits targeting it, commands whose working directory resolves there,
and git redirected into it through `-C`, `--git-dir`, `GIT_DIR` or a `cd`.

That is documented in
[Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees).

**That covers isolation, and it now covers most of the primary-checkout defence too.** The honest
split is what one isolated session cannot see: the other one.

| What you need | Claude Code's own worktrees | What KORUS adds |
|---|---|---|
| A checkout and branch per session | Yes, and automatically in the desktop app | Nothing. Use the native one |
| Stopping a session writing into the main checkout | Yes, while that session is isolated | The same refusal for a session that is **not** isolated, on any primary in its allowlist |
| Two isolated sessions editing the same file | Not addressed. Each is isolated from the main checkout, not from the other | Refuses the second edit before it runs, naming who holds the file |
| Two sessions taking the same record number | Not addressed | Atomic allocation, plus a commit-time gate |
| Knowing who is live, and what each is changing | Not addressed | `presence.ps1` and `overlap.ps1` |
| Proving any of it is actually running | Not addressed | `bin/ccx-doctor.ps1`, which attacks each control |

**Skip KORUS if** you run two sessions on unrelated work and merge by hand. Native worktrees plus a
human reviewer is simpler, and simpler wins.

**Reach for KORUS when** sessions overlap: same files, same numbered artifacts, or the same feature
approached from two directions. Those are the collisions git reports as a clean merge.

## Is this a security boundary?

**No.** It prevents accidents. It does not stop an adversary, and it is not meant to.

Every control here runs as the same operating-system identity as the agent it constrains, so that
agent can edit the hook, the allowlist and the settings file. `--no-verify` skips both git hooks.

[Limits and requirements](LIMITS.md) states what to pair it with: protected branches on the remote,
required status checks, and credentials that cannot bypass them.

## Can a team of developers use this?

Partly, and the boundary is sharp: **the guarantees stop at the clone.**

Claims and allocations live beside the git common directory, so every worktree of one clone shares
them. A second developer on a second clone has a second registry, and both can allocate the same
number before either lands.

`scripts/hooks/seq_check.py --ci` re-runs the collision rules against a freshly fetched trunk, which
catches the duplicate after the fact. No installer wires it, and nothing here configures CI for you.

For a team, treat this as a local coordination layer and put the authoritative check on the remote.
[Sequence allocation](SEQUENCE-ALLOC.md) owns the detail.

## Does it work without the desktop app?

Mostly. Announce is the one part that needs it, and you should leave that hook uninstalled on a
CLI-only install.

Worktrees, the collision gate, both git hooks, presence, overlap, claims, allocation and the doctor
do not depend on it. [Limits and requirements](LIMITS.md) has the reason.

## Does it work in CI?

The doctor does, and the leak gate does. The hooks do not: they need an interactive session.

`seq_check.py --ci` is written for a CI run and no installer wires it.

## What happens when Claude Code changes the session registry format?

Everything answering "who is live" degrades to "cannot tell", and the doctor surfaces it as a record
count going to zero.

**That is not the same as fail-closed.** A fence that cannot tell issues no veto, so the collision
gate allows the edit and says it could not check. Absence of a refusal is never evidence of absence
of a peer.

## How many sessions should I run?

The shape this is built around is four: a dispatcher, two builders and a lander, with an optional
fifth for a security register. [Run a KORUS build](KORUS-BUILD.md) has the procedure.

More is not obviously better. The reported case that started this project was roughly fourteen
sessions on one directory, and the limit there was not the tooling.

## Related

| For | Read |
|---|---|
| Installing it, and seeing a refusal | [Quickstart](QUICKSTART.md) |
| What it needs, and where it stops | [Limits and requirements](LIMITS.md) |
| Something is behaving oddly | [Troubleshooting](TROUBLESHOOTING.md) |
| The method behind the tooling | [The KORUS framework](KORUS.md) |
