# Every script, and what it does

## TLDR/BLUF

**What this is.** The inventory: every script this project ships, grouped by what you are trying to
do, with the page that owns each one. It was the bottom half of the landing page until 2026-08-16.

**Why you should care.** Paths are relative to this checkout, and the site serves each at the same
path, so
[/scripts/coord/claim.ps1](https://claude-multisession.pages.dev/scripts/coord/claim.ps1)
needs no clone. Not for you if you are still deciding whether to install anything.

**How to use it.** Find the row for what you want to do, then read the doc in the right-hand column.
The controls in the fourth table run without you once installed.

---

The source is also on [GitHub](https://github.com/wshallwshall/claude-multisession), the better view
where reachable.

## Start here

| Script | Does | Doc |
|---|---|---|
| `bin/ccx-doctor.ps1` | Prove -- by receipt and by attack -- that each control is installed, wired, and refuses what it can be made to refuse. It never infers, and a skip is never a pass (exit 2) | [Limits and requirements](LIMITS.md) |

## To run sessions

| Script | Does | Doc |
|---|---|---|
| `scripts/worktree/new.ps1` | Create an isolated worktree on its own branch, off the fetched remote tip, serialised against concurrent adds | [Worktrees](WORKTREES.md) |
| `scripts/worktree/spawn.ps1` | `new.ps1` plus an editor window (`-Editor`, else `CCX_EDITOR`, else `EDITOR`, else `code`) | [Worktrees](WORKTREES.md) |
| `scripts/coord/presence.ps1` | Who is actually live in this repo right now, across every surface. Read-only | [Coordination](COORDINATION.md) |
| `scripts/coord/overlap.ps1` | What everyone else is changing -- files and stated work. `-File <path>`, `-Json`; cached, so the gate's common case is a cache read | [Coordination](COORDINATION.md) |
| `scripts/coord/claim.ps1` | Take, release or list an atomic claim on a piece of work, so a session finds out before the work rather than at merge. Advisory: a claim cannot stop a session that refuses to look. Claims do not expire and releasing is manual, on purpose | [Coordination](COORDINATION.md) |
| `scripts/coord/alloc.ps1` | Allocate the next number in a shared sequence atomically, so two sessions can never be handed the same one; `-ShowFloor` inspects without spending one. `seq_check.py` is the other half -- neither is sufficient alone | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `bin/ccx-steer.ps1` | Queue a steering note from a second terminal while a session is mid-task | [Steering](STEERING.md) |

## To clean up

| Script | Does | Doc |
|---|---|---|
| `scripts/worktree/remove.ps1` | Remove one worktree, referencing its tip before anything is removed, and writing a keep-ref when `-DeleteBranch` is used | [Pruning](PRUNING.md) |
| `scripts/worktree/prune-merged.ps1` | The reaper: prune = merged **and** clean **and** unoccupied. Dry-run by default, `-Apply` to act. Carries a second, non-cwd signal and prints its blind spots | [Pruning](PRUNING.md) |
| `scripts/worktree/rescue.ps1` | Move uncommitted work out of the shared primary into a fresh worktree -- the companion to the gate that stops you writing there | [Worktrees](WORKTREES.md) |
| `scripts/worktree/restore-primary.ps1` | Re-attach the primary to its home branch after a session left it detached or on the wrong branch. Refuses on a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/worktree/sessions.ps1` | Find sessions for this repo across every login, including ones a relocation made invisible; `-Rehome` puts a transcript back | [Worktrees](WORKTREES.md) |
| `scripts/security/scan_forbidden.py` | The leak gate: refuse identifying content before a private repo goes public. `--path DIR`, `--require-tokens`, `--show-context`. Nothing wires it | [Leak gate](LEAK-GATE.md) |

## Controls that run without you

Installed once, then invoked by the harness or by git.

| Script | Event | Does | Doc |
|---|---|---|---|
| `scripts/hooks/worktree_gate.ps1` | `PreToolUse` | Denies writes whose target path is inside a governed primary, dispatch from the primary, and the git verbs that swap or discard its tree. Fails open, but loudly | [Hooks](HOOKS.md) |
| `scripts/hooks/collision_gate.ps1` | `PreToolUse` | Refuses an edit to a file a live session is already changing. Fails open -- never silently | [Coordination](COORDINATION.md) |
| `scripts/hooks/announce-session.ps1` | `UserPromptSubmit` | Tells peers you exist and what you intend, on the first prompt at which a messageable peer exists. Always exits 0; delivery needs the desktop client | [Coordination](COORDINATION.md) |
| `scripts/worktree/session-context.ps1` | `SessionStart` | Banner: your project's working defaults plus a live coordination block. Its stdout is the chat's starting context, so it never fails loudly | [Hooks](HOOKS.md) |
| `scripts/worktree/worktree-selfheal.ps1` | `SessionStart` | Repairs a primary whose HEAD drifted, when the tree is clean -- the most privileged control here, whose only safety property is that it refuses a dirty tree | [Worktrees](WORKTREES.md) |
| `scripts/hooks/claim_check.py` | `commit-msg` | Refuses a code-touching commit whose subject claims an item this worktree does not hold. Fail-closed | [Coordination](COORDINATION.md) |
| `scripts/hooks/push_guard.py` | `pre-push` | Refuses a direct push of a protected ref. An explicitly empty `protectedRefs` list disables it with a message on stderr | [PRs and merges](PR-AND-MERGE.md) |
| `scripts/hooks/seq_check.py` | `pre-commit` | Refuses a colliding, unallocated, or unindexed sequence number; `--ci` re-runs the collision rules against a freshly fetched trunk. No installer wires it | [Sequence allocation](SEQUENCE-ALLOC.md) |
| `scripts/hooks/block-blanket-git-stage.ps1` | `PreToolUse` | Opt-in. Denies `git add -A/--all/-u/.` and `git commit -a/-am`. Fails open | [Hooks](HOOKS.md) |
| `scripts/hooks/steer-inject.ps1` | `PreToolUse` | Opt-in per worktree. Delivers a queued steering note at the next tool-call boundary rather than at the end of the turn | [Steering](STEERING.md) |

## Internals and installers

| Script | Does | Doc |
|---|---|---|
| `scripts/coord/session-registry.ps1` | The liveness fence: reads the client's session registry and decides whether a session is alive. Liveness may only VETO, never PERMIT -- DEAD/STALE/absent is the absence of a veto, not a permission | [Concepts](CONCEPTS.md) |
| `scripts/coord/occupancy.ps1` | The one cwd-to-worktree matcher, returning a receipt alongside its rows (roots examined, records examined, records that could not be placed) and setting `Available` only when there was something to examine | [Concepts](CONCEPTS.md) |
| `scripts/coord/lock.ps1` | The short-lived cross-session mutex, dot-sourced rather than run: `. lock.ps1` then `Enter-CcxLock` / `Exit-CcxLock`. No TTLs anywhere: locks retry and never steal, and on timeout fail loudly and name the holder | [Concepts](CONCEPTS.md) |
| `scripts/coord/install-coordination.ps1` | Wires the banner, collision gate and announce at user scope as shims that re-resolve at run time; writes exactly one settings file per run (`-SettingsPath`) | [Quickstart](QUICKSTART.md) |
| `scripts/coord/install-git-hooks.ps1` | Installs `commit-msg` + `pre-push` into one clone's shared `.git/hooks` (`-RepoRoot`), refuses to overwrite a foreign hook, and never writes `pre-commit` at all | [Quickstart](QUICKSTART.md) |
| `scripts/worktree/install-gate.ps1` | Installs the worktree gate as a copy outside every working tree, into every config root it finds, plus the allowlist that is its kill switch (`-Repo`, `-ConfigDir`) | [Quickstart](QUICKSTART.md) |
| `scripts/worktree/install-selfheal.ps1` | Wires the SessionStart backstop into ONE config root per run; `-ConfigDir` is mandatory, and it governs whatever the gate's allowlist already names | [Quickstart](QUICKSTART.md) |
