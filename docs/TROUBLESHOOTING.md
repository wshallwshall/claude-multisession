# Troubleshooting

## TLDR/BLUF

**What this is.** A symptom-to-cause-to-fix table for the controls in this repository, then how to
read `bin/ccx-doctor.ps1`, then what to do when the honest answer is that nothing can be told.

**Why you should care.** Almost everything here fails by producing the bytes it produces when it
works. An uninstalled gate and a working one both let the edit through. Not for you if you have
installed nothing yet, in which case start at [Quickstart](QUICKSTART.md).

**How to use it.** Find your symptom in the first table. Run the doctor before you act on any row,
because most of these are read off its output rather than guessed at.

---

## Symptoms

| Symptom | What it actually is | What to do |
|---|---|---|
| The doctor says `STALE` | The installed copy's SHA-256 differs from this checkout's source. The code that runs is not the code you are reading. Reported `RED`. | Re-run that control's installer, from a plain terminal. Install from the same checkout the doctor hashes against, which it prints as `tooling checkout`. |
| The report is about the wrong clone | `-Repo` defaults to the directory you ran it from. Sources are hashed from the doctor's own checkout whatever `-Repo` says. | Pass `-Repo <target>`. Then read `repo examined` and `tooling checkout` under `WHAT WAS SCANNED`; both are printed for this reason. |
| The doctor exits 2 | At least one check could not be determined, and nothing was proven broken. A skip is never a pass. | Read the `undetermined` lines in the verdict. `-SkipAttacks` produces this on its own, because nothing was fired. |
| A control shows `OFF` | It is implemented and nothing invokes it. Zero enforcement, which from inside a session looks like a healthy control with nothing to say. | Install or wire it. A required `OFF` drives exit 1; an opt-in one is counted separately as `OFF (opt-in)` and does not. |
| The collision gate did not refuse an edit | It fails open by design, and it denies only when a live peer's worktree holds that file uncommitted. A peer that committed and went clean is reported, not refused. | Run `scripts/coord/overlap.ps1 -File <path>` yourself. Look for a `could NOT check` notice: it is throttled per worktree and per reason, 30 minutes by default. |
| Announce never delivers | The hook sends nothing. It resolves peers and asks the model to send through a session-management MCP server that a plain CLI install does not have. | On a CLI-only install leave it uninstalled, or create the `announce/OFF` file in the state root. The doctor cannot see whether that server is connected. |
| Presence lists nobody | Either nobody is live, or the roster could not be completed. Under `-Json` both are the two bytes `[]` on stdout, and the reason goes to stderr. | Read the exit code rather than the rows. `0` is a complete roster, including one that lists nobody. `2` is a roster that could not be completed. |
| Presence exits 2 | The roster could not be completed: not inside a git repository, or `Available` is false. One unplaceable record makes it false. | Treat the output as incomplete even when rows are listed. An unplaceable record could name any worktree, so it clears none of them. |
| The reaper refuses a worktree | `prune-merged.ps1` acts only on merged AND clean AND not occupied. Any check that cannot reach a confident answer skips. Untracked files block it. | Read the printed SKIP reason. Exit 2 means the run refused and removed nothing: a wrong cwd, an unresolvable trunk, or an unavailable fence. |
| Self-heal declines to repair the primary | The primary's tree is dirty. The backstop repairs a drifted primary only when it is clean, and it reports the decline rather than acting. | Commit or stash the work sitting in the primary. A detached HEAD is deliberately not treated as drift, and is a silent no-op. |
| A commit is refused naming a number | The claim gate. The subject declares `<KIND> #N`, the staged diff touches code, and this worktree does not hold the claim on N. | Take the claim first: `claim.ps1 -Take N`. Claim keys are flat, so `adr #12` and `backlog #12` are one key across two sequences. |
| Every commit and every push is refused | `_ccxconfig.py` is absent from the git hooks directory, or will not import. Both Python checkers import it at startup, then write to stderr and exit 1, which refuses every commit and every push. | Re-run `install-git-hooks.ps1`, which copies it beside the checkers. The doctor reports an absent or differing substrate `RED`. It compares hashes and never imports, so a differing copy may still import fine. |
| A push is refused | The push guard. The ref is in `protectedRefs`, which defaults to `main` and `master`. Deleting a protected ref is refused as well. | Push a branch and open a pull request. An explicitly empty `protectedRefs` disables the guard and announces that on stderr. |
| Sequences are configured and nothing enforces them | No `pre-commit` hook invokes `seq_check.py`. The doctor prints `OFF` on that row and marks it not required, so it does not raise the exit code. | Wire `scripts/hooks/seq_check.py` into whatever `pre-commit` you already run. That row, and the `OFF (opt-in)` line in the verdict, are where it shows. |

### The green run and the real hole

Two rows carry a clean verdict over a control nothing invokes: the sequence gate, and the ASCII
gate. The sequence gate is the sharper one. No shipped installer writes `pre-commit`, because two
tools cannot both own that file. Failing the run on it would redden every clean install.

So the row is recorded as not required. It appears as `OFF (opt-in)` in the verdict, and it does not
raise the exit code. An otherwise clean run is green.

The hole is real. With sequences configured and nothing checking at commit time, two sessions can
take the same number, and the collision merges clean. Read that `OFF` row, because the exit code
will not carry it and the required-only count does not include it.

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
| 0 | Every required control is installed and wired, and every attack was refused. |
| 1 | At least one `RED`, or at least one required control `OFF`. |
| 2 | At least one check could not be determined, and nothing above it fired. |

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

**The record census went to zero.** Every liveness answer rests on a per-session JSON record the
client writes, which is a vendor contract rather than this project's. A renamed field turns the
counts the doctor prints into zeros.

> **The rule.** Absence of a refusal is not evidence of absence of a peer.

Each of these degrades to "cannot tell" rather than to a wrong answer, which is the design. Acting
on the silence is what converts it into a wrong answer.

## Related

| For | Read |
|---|---|
| What this needs to run, and where it stops working | [Limits and requirements](LIMITS.md) |
| Every control's event, matcher and fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Why a removal is skipped, and how to recover a half-removed worktree | [Pruning worktrees](PRUNING.md) |
| Who is live, what they are touching, and the collision gate's full rule | [Coordination](COORDINATION.md) |
| Installing the controls, and watching one refuse | [Quickstart](QUICKSTART.md) |
