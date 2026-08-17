# Troubleshooting

## TLDR/BLUF

**What this is.** A symptom-to-cause-to-fix table for the controls in this repository, and how to
read what `bin/ccx-doctor.ps1` tells you.

**Why you should care.** Almost everything here fails by producing the bytes it produces when it
works. An uninstalled gate and a working one both let the edit through. Not for you if you have
installed nothing yet, in which case start at [Quickstart](QUICKSTART.md).

**How to use it.** Run the doctor first, from a plain terminal, naming the repository you are asking
about. Then find your symptom below.

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-govern>
```

It writes nothing to your repository. Every attack it fires runs against a throwaway fixture in the
temp directory.

---

## Symptoms

| Symptom | What it actually is | What to do |
|---|---|---|
| The doctor says `STALE` | The installed copy's SHA-256 differs from this checkout's source. The code that runs is not the code you are reading. Reported `RED`. | Re-run that control's installer, from a plain terminal. Install from the same checkout the doctor hashes against, which it prints as `tooling checkout`. |
| The report is about the wrong clone | `-Repo` defaults to the directory you ran it from. Sources are hashed from the doctor's own checkout whatever `-Repo` says. | Pass `-Repo <target>`. Then read `repo examined` and `tooling checkout` under `WHAT WAS SCANNED`; both are printed for this reason. |
| The doctor exits 2 | At least one check could not be determined, and nothing was proven broken. A skip is never a pass. | Read the `undetermined` lines in the verdict. `-SkipAttacks` produces this on its own, because nothing was fired. |
| A control shows `OFF` | It is implemented and nothing invokes it. Zero enforcement, which from inside a session looks like a healthy control with nothing to say. | Install or wire it. A required `OFF` drives exit 1; an opt-in one is counted separately as `OFF (opt-in)` and does not. |
| The collision gate did not refuse an edit | Most often it is one of its documented blind spots rather than a fault. It cannot see a peer in **your own** worktree, and its map is cached for 60 seconds. | Check the list below before assuming a break. [Limits](LIMITS.md#what-the-collision-gate-does-not-see) has every case. |
| The collision gate says nothing at all, repeatedly | It could not check, and said so once. The notice is throttled per worktree and per reason, 30 minutes by default. | The notice is emitted by the gate itself, not by `overlap.ps1`. Look in your session, not in a terminal. |
| The worktree gate never refuses anything | Most likely its allowlist has no entries. With none it exits 0 having written nothing, which reads exactly like a healthy gate with nothing to refuse. | Count the entries in `~/.claude/hooks/ccx-gate.repos.txt`. Re-run `install-gate.ps1 -Repo <primary>`, naming every governed primary in one run. |
| Announce never delivers | On a plain CLI install there is no MCP server to deliver through. On Desktop, check the `OFF` file and the receipts the hook writes. | Create or remove `<git-common-dir>/<prefix>-coord/announce/OFF`. The doctor cannot see whether the MCP server is connected. |
| Presence lists nobody | Either nobody is live, or the roster could not be completed. Under `-Json` both are the two bytes `[]` on stdout, and the reason goes to stderr. | Read the exit code rather than the rows. `0` is a complete roster, including one that lists nobody. `2` is a roster that could not be completed. |
| Presence exits 2 | The roster could not be completed: not inside a git repository, or `Available` is false. One unplaceable record makes it false. | Treat the output as incomplete even when rows are listed. An unplaceable record could name any worktree, so it clears none of them. |
| The reaper refuses a worktree | `prune-merged.ps1` acts only on merged AND clean AND not occupied. Any check that cannot reach a confident answer skips. Untracked files block it. | Read the printed SKIP reason. Exit 2 means it refused and removed nothing: a `-Name` matching no prunable sibling, a wrong cwd, an unresolvable trunk, or an unavailable fence. |
| Self-heal declines to repair the primary | The primary's tree is dirty. The backstop repairs a drifted primary only when it is clean, and it reports the decline rather than acting. | Commit or stash the work sitting in the primary. A detached HEAD is deliberately not treated as drift, and is a silent no-op. |
| A commit is refused naming a number | The claim gate. The subject declares `<KIND> #N`, the staged diff touches code, and this worktree does not hold the claim on N. | Take the claim first, substituting the real number: `pwsh -NoProfile -File scripts/coord/claim.ps1 -Take 12`. |
| Every commit and every push is refused | `_ccxconfig.py` is absent from the git hooks directory, or will not import. Both Python checkers import it at startup, then exit 1. | Re-run the git-hook installer from a plain terminal: `pwsh -NoProfile -File <tooling>/scripts/coord/install-git-hooks.ps1 -RepoRoot <target>`. |
| No commit or push is ever refused | The opposite failure, and the quiet one. With no `python` on `PATH` the two `/bin/sh` shims print one line to stderr and **exit 0**, so both git gates are off with every file still installed. | Check that `python --version` actually prints. On Windows it is often an execution-alias stub that resolves and runs nothing. |
| A push is refused | The push guard. The ref is in `protectedRefs`, which defaults to `main` and `master`. Deleting a protected ref is refused as well. | Push a branch and open a pull request. An explicitly empty `protectedRefs` disables the guard and announces that on stderr. |
| Sequences are configured and nothing enforces them | No `pre-commit` hook invokes `seq_check.py`. The doctor prints `OFF` on that row and marks it not required, so it does not raise the exit code. | [Sequence allocation](SEQUENCE-ALLOC.md#wiring-the-pre-commit-hook) has the snippet. That row, and the `OFF (opt-in)` line, are where it shows. |

### Why the collision gate stays quiet

Before treating a missing refusal as a break, rule these out. Each is by design, and
[Limits](LIMITS.md#what-the-collision-gate-does-not-see) states them in full:

- **A second session in your own worktree.** `overlap.ps1` skips your own worktree before comparing
  any path, so two sessions on one checkout collide in silence.
- **A peer who started within the last minute.** The overlap map is cached for 60 seconds, and the
  gate never asks for a refresh.
- **A peer whose change git cannot report as a path.** A new file in a new directory, a rename, or
  anything git-ignored.
- **A write by absolute path into another worktree**, or through a symlink.
- **A peer that committed and went clean.** Reported, not refused, on purpose.

### The green run and the real hole

Four rows carry a clean verdict over a control nothing invokes: the sequence gate, the ASCII gate,
the blanket-stage guard and the steering injector. The sequence gate is the sharpest.

No shipped installer writes `pre-commit`, because two tools cannot both own that file. Failing the
run on it would redden every clean install, so the row is recorded as not required. It appears as
`OFF (opt-in)` in the verdict and does not raise the exit code.

**The hole is real.** With sequences configured and nothing checking at commit time, two sessions can
take the same number, and the collision merges clean. Read that `OFF` row: the exit code will not
carry it.

**The ASCII gate is the milder one.** `scripts/quality/check-ascii.ps1` ships in every checkout and
nothing runs it, so a non-ASCII character reaches a file until you invoke it yourself. Wire it into
your own `pre-commit` and into CI.

## Reading the doctor

Every check gets one row and one tag. What each tag licenses you to believe:

| Tag | What it licenses |
|---|---|
| `OK` | Installed, wired, and where it could be attacked it refused the case it exists to refuse. |
| `RED` | Proven broken: wired but stale or unloadable, or it allowed what it must deny, or it denied what it must allow. |
| `OFF` | Implemented, and nothing invokes it. Zero enforcement. |
| `??` | Could not be determined. Never read one of these as a pass. |
| `--` | Not applicable here, such as no sequences configured, or an opt-in rule left off on purpose. |

The exit code is a summary of those rows, and the highest severity wins:

| Exit | Meaning |
|---|---|
| 0 | Every required control is installed and wired, and every attack it **could** fire was refused. |
| 1 | At least one `RED`, or at least one required control `OFF`. |
| 2 | At least one check could not be determined, and nothing above it fired. |

**Exit 0 is not "every deny path was proven".** Three controls are never fired, and the doctor names
them on every run: the collision gate's refusal needs a live peer worktree it cannot stage, announce
delivery cannot be proven from PowerShell, and the steering injector has no attack.

Read the blind spots with the verdict, not instead of it.

### Why a skip is exit 2 rather than a pass

A control that was not tested is not a control that passed. The whole failure class here is that a
broken control and a working one emit the same bytes. A check that did not run therefore cannot be
scored against one that ran and found nothing.

Exit 2 is also reachable before any check runs. The doctor prints `CANNOT DETERMINE ANYTHING` and
stops in four cases. Its own `scripts/coord/_common.ps1` will not load; there is no
`ccx.config.json` at or above the path; that file will not load; the path is not inside a git
repository.

### `-SkipAttacks` cannot prove enforcement

`-SkipAttacks` fires nothing. One `??` row stands for the whole attack set, so the run cannot exit
0. It exits 2, or 1 if a receipt check also found something broken or absent.

Receipts establish what is on disk and what the live settings wire. Only firing a control at the
case it exists to refuse establishes that it refuses. Those are different claims.

The same distinction appears without the flag. Where a control is not installed, the doctor fires
the source copy instead and downgrades the verdict: the rule can refuse, but nothing is refusing.
Capability is not enforcement.

## When the answer is "cannot tell"

Three states report that the tooling could not look, and each one is easy to read as an all-clear.

**Presence exited 2.** The roster could not be completed. That fires even when rows were listed,
because a roster naming two peers is not evidence about a third.

**The overlap check could not resolve.** The collision gate allows the edit and injects a
`could NOT check` notice saying it consulted no peer worktree. The notice is throttled, so a second
edit inside the cooldown gets the allow with no notice at all.

**The session record schema changed.** Every liveness answer rests on a per-session JSON record the
client writes, which is a vendor contract rather than this project's.

The two ways it can break do **not** look alike, and this is the one to get right:

| What changed | What you see |
|---|---|
| The directory moved, or records were removed | The census counts go to zero |
| A field was renamed, or `startedAt`'s unit changed | **The counts do not move.** Those records still parse and still place; every verdict simply becomes `UNVERIFIED` |

`UNVERIFIED` is a veto, so the gates keep refusing rather than waving work through. A healthy census
is therefore not evidence the schema still matches.

**A blind roster reaches no row and no exit code.** The census and the roster-unavailable notice are
printed under `WHAT WAS SCANNED` only. Read that block; the verdict will not carry it.

> **The rule.** Absence of a refusal is not evidence of absence of a peer.

Acting on the silence is what converts a "cannot tell" into a wrong answer.

## Related

| For | Read |
|---|---|
| What this needs to run, and where each control stops | [Limits and requirements](LIMITS.md) |
| Every control's event, matcher and fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Wiring the sequence gate, and why no installer writes `pre-commit` | [Sequence allocation](SEQUENCE-ALLOC.md) |
| The worktree commands, and what removal destroys | [Worktrees](WORKTREES.md) |
| Why a removal is skipped, and how to recover a half-removed worktree | [Pruning worktrees](PRUNING.md) |
| Who is live, what they are touching, and the collision gate's full rule | [Coordination](COORDINATION.md) |
| Installing the controls, and watching one refuse | [Quickstart](QUICKSTART.md) |
| Every installer flag, and how to prove each control is live | [Install](INSTALL.md) |
