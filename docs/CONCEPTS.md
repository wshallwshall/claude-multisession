# Concepts

## TLDR/BLUF

**What this is.** The five ideas every other page here applies. One checkout per session, one shared
place for coordination state, a liveness check that may only say no, files created rather than
edited, and no timers anywhere.

**Why you should care.** Read this and the rules on the other pages stop looking arbitrary. Every
trap below is one somebody already paid for. Not for you if you run one session at a time.

**How to use it.** Read the three-layer sketch, then sections 1 to 5 for the ideas themselves. Then
[Quickstart](QUICKSTART.md) to install, [Hooks](HOOKS.md) for the event each idea is wired to, and
[Worktrees](WORKTREES.md) for the day-to-day commands.

---

The whole system is three layers:

<!-- no-copy -->
```text
  worktree-per-session      one checkout per concurrent session, so two sessions
                            cannot clobber each other's working tree
        |
  a shared state root       one directory every worktree of a clone resolves
                            identically, holding claims, locks, allocations
        |
  the liveness fence        the single answer to "is that session still there",
                            which may only ever say NO to an action
```

The hooks, the reaper, the allocator and the announce path are all applications of those three.

Here are the same three ideas as they sit on disk, with the two hook layers that enforce them.

<figure role="group">
<svg viewBox="0 0 860 430" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="One clone contains a gated primary checkout and any number of linked worktrees, each on its own branch. All of them share one git common directory, which holds the coordination state: claims, allocations, locks and announce receipts. Two hook layers act on that clone. User-scope hooks are installed once per client config root and cover the worktree gate and collision gate at PreToolUse, the banner and self-heal at SessionStart, and announce at UserPromptSubmit. Git-scope hooks are installed once per clone and cover the claim gate at commit-msg and the push guard at pre-push. The doctor stands outside both and proves each control by attacking it.">
  <defs>
    <marker id="cx-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
    </marker>
  </defs>
  <rect x="16" y="26" width="560" height="240" rx="8" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="28" y="46" font-size="12" font-weight="bold" fill="currentColor">One clone</text>
  <rect x="32" y="58" width="150" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="2" />
  <text x="107" y="79" font-size="11" font-weight="bold" text-anchor="middle" fill="currentColor">primary checkout</text>
  <text x="107" y="96" font-size="10" text-anchor="middle" fill="currentColor">gated: nothing builds here</text>
  <rect x="202" y="58" width="118" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="261" y="79" font-size="11" text-anchor="middle" fill="currentColor">worktree A</text>
  <text x="261" y="96" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">branch a</text>
  <rect x="336" y="58" width="118" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="395" y="79" font-size="11" text-anchor="middle" fill="currentColor">worktree B</text>
  <text x="395" y="96" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">branch b</text>
  <text x="500" y="92" font-size="12" text-anchor="middle" fill="currentColor">... N</text>
  <line x1="107" y1="116" x2="107" y2="158" stroke="currentColor" stroke-width="1.5" marker-end="url(#cx-arrow)" />
  <line x1="261" y1="116" x2="261" y2="158" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#cx-arrow)" />
  <line x1="395" y1="116" x2="395" y2="158" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#cx-arrow)" />
  <rect x="32" y="160" width="512" height="86" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="288" y="180" font-size="11" font-weight="bold" text-anchor="middle" fill="currentColor">one shared git common directory</text>
  <text x="288" y="198" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">every worktree of this clone resolves it identically</text>
  <rect x="52" y="208" width="106" height="28" rx="4" fill="none" stroke="currentColor" />
  <text x="105" y="226" font-size="10" text-anchor="middle" fill="currentColor">claims</text>
  <rect x="170" y="208" width="116" height="28" rx="4" fill="none" stroke="currentColor" />
  <text x="228" y="226" font-size="10" text-anchor="middle" fill="currentColor">allocations</text>
  <rect x="298" y="208" width="96" height="28" rx="4" fill="none" stroke="currentColor" />
  <text x="346" y="226" font-size="10" text-anchor="middle" fill="currentColor">locks</text>
  <rect x="406" y="208" width="118" height="28" rx="4" fill="none" stroke="currentColor" />
  <text x="465" y="226" font-size="10" text-anchor="middle" fill="currentColor">announce state</text>
  <rect x="612" y="26" width="234" height="128" rx="8" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="624" y="46" font-size="12" font-weight="bold" fill="currentColor">user scope</text>
  <text x="624" y="62" font-size="10" font-style="italic" fill="currentColor">once per client config root</text>
  <text x="624" y="82" font-size="10" fill="currentColor">PreToolUse: worktree gate,</text>
  <text x="624" y="97" font-size="10" fill="currentColor">collision gate</text>
  <text x="624" y="117" font-size="10" fill="currentColor">SessionStart: banner, self-heal</text>
  <text x="624" y="137" font-size="10" fill="currentColor">UserPromptSubmit: announce</text>
  <rect x="612" y="166" width="234" height="92" rx="8" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="624" y="186" font-size="12" font-weight="bold" fill="currentColor">git scope</text>
  <text x="624" y="202" font-size="10" font-style="italic" fill="currentColor">once per clone</text>
  <text x="624" y="222" font-size="10" fill="currentColor">commit-msg: claim gate</text>
  <text x="624" y="242" font-size="10" fill="currentColor">pre-push: push guard</text>
  <line x1="610" y1="86" x2="470" y2="86" stroke="currentColor" stroke-width="1.5" marker-end="url(#cx-arrow)" />
  <line x1="610" y1="212" x2="560" y2="212" stroke="currentColor" stroke-width="1.5" marker-end="url(#cx-arrow)" />
  <rect x="16" y="290" width="830" height="54" rx="8" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="5 4" />
  <text x="431" y="312" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">bin/ccx-doctor.ps1</text>
  <text x="431" y="331" font-size="10" text-anchor="middle" fill="currentColor">stands outside both layers and proves each control by attacking it, never by reading config</text>
  <text x="16" y="372" font-size="10" font-style="italic" fill="currentColor">A solid arrow is enforcement. A dashed arrow is state a worktree reads and writes.</text>
  <text x="16" y="392" font-size="10" font-style="italic" fill="currentColor">Nothing here isolates a running program: ports, databases and .env are outside every box.</text>
</svg>
<figcaption>The primary is gated so nothing builds in it; each session gets a worktree on its own
branch; all of them share one state root. The two hook layers install at different scopes, which is
why there are four installers rather than one.</figcaption>
</figure>

---

## 1. Worktree-per-session

A git **worktree** is a second working directory on the same git directory: same history, remotes
and objects, a different branch and index. Two sessions in one checkout fight over that tree
silently. One side's `git checkout` swaps the files out from under the other's edit.

So the unit of isolation is the worktree, and the unit of work is a branch.

### Primary and linked

The **primary** checkout is the main working tree of the clone. It is the first entry
`git worktree list --porcelain` reports, and `Get-CcxPrimaryRoot` in
[`scripts/coord/_common.ps1`](https://claude-multisession.pages.dev/scripts/coord/_common.ps1) resolves it that way, deliberately:

> **Trap.** Four earlier copies derived the repository root as `$PSScriptRoot/../..`, the checkout
> the *script* happens to live in. Run from a linked worktree, that expression resolves to the
> worktree's own root. A new worktree was then created as a sibling *of a sibling*, and the pruning
> tool anchors on the primary, so it could not see that worktree as a candidate at all.
>
> **Rule.** Anchor layout on the primary, never on where the script lives. The tooling must behave
> identically whichever checkout you invoke it from.

### Two layouts, and both are real

| Layout | Path | Who creates it |
|---|---|---|
| `sibling` (default) | `<parent-of-primary>/<primary-leaf>-<name>` | this tooling, via `scripts/worktree/new.ps1` |
| `nested` | `<primary>/.claude/worktrees/<name>` | the client itself, and this tooling if you configure it |

`worktreeLayout` in `ccx.config.json` picks where **we** create worktrees. Both kinds exist on a
real machine anyway. `Get-CcxWorktreePath` owns the formula once: it was duplicated in four scripts
and pattern-*matched* in a fifth, so the rule and its enforcement disagreed.

> **Trap.** A nested checkout is git-ignored inside its parent, so the parent reads perfectly clean.
> `git worktree remove --force` on the parent deletes both, leaving the nested one registered with
> no directory. A sweep run from the wrong directory printed a green "no sibling worktrees to
> consider" and exited 0: a wrong-cwd run reporting a clean bill of health.
>
> **Rule.** Any path containing a `.claude/worktrees/` segment is excluded from destructive
> operations *unconditionally*, whatever the layout setting says. That is
> `Test-CcxHarnessWorktreePath`, one named test rather than two inline regexes, because two rules
> depend on it and they pull in opposite directions. A gate protecting the primary must **not**
> govern a nested worktree (a git verb there swaps only its own tree). A reaper must **never**
> remove one (a live session is standing in it).

### "Sibling" is a structure, not a string prefix

`Test-CcxSiblingWorktreePath` requires three things: same parent directory as the primary, a leaf of
exactly `<primary-leaf>-<something>`, and not a nested worktree.

> **Trap.** A reaper enumerated candidates as `<primary>-*` by prefix. `<primary>-pins/.claude/worktrees/x`
> starts with `<primary>-`, so a nested worktree under a sibling became a prune candidate in its own
> right and was removed, with its branch. Nested trees under the *primary* escaped only by the
> accident that `<primary>/` is not `<primary>-`, and that was the only case anyone had tested.
>
> **Rule.** When a matcher relies on a punctuation accident, the untested sibling case is already
> broken. Match on structure and exclude containment explicitly.

Even all three conditions only say the path *looks* like ours. Whether it may be touched is a
separate question, answered by who is sitting in it (**occupancy**, section 3), whether it is clean,
and whether it merged. Never by the name.

### What a worktree does *not* isolate

A fresh worktree feels completely isolated: separate files, separate branch, separate index,
separate build environment. Three things are not isolated, and each has bitten:

| Shared thing | Consequence |
|---|---|
| the git directory | one `.git/config.lock`; concurrent `git worktree add` races it, which is why creation is serialised under a cross-session mutex |
| the git hooks directory | one `pre-commit` / `commit-msg` / `pre-push` set governs **every** worktree at once, and sees every write route into the repo |
| the AI coding assistant's own project memory | it lives outside the repo, one directory per machine, and last write wins. Reads are fine; coordinate writes, or let exactly one session own them |

**The isolation you do not want:** a project-scoped `.claude/settings.json` is git-ignored, a
creation-time snapshot nothing refreshes and some worktrees lack. So the coordination hooks install
at **user** scope. See [`INSTALL.md`](INSTALL.md).

Setting up a new worktree's environment is `setupHook`'s job, not `new.ps1`'s. It runs with
`CCX_WORKTREE_PATH`, `CCX_WORKTREE_NAME`, `CCX_PRIMARY_ROOT` and `CCX_BASE_REF` set. See
[`examples/worktree-setup.ps1.example`](https://claude-multisession.pages.dev/examples/worktree-setup.ps1.example).

---

## 2. The shared state root

Every piece of cross-session coordination state lives in exactly one place:

<!-- no-copy -->
```text
<git-common-dir>/<prefix>-coord/
    alloc/              one file per allocated sequence number
    claims/             one file per claimed unit of work
    locks/              one file per held short-lived mutex
    announce/           per-session announce bookkeeping, and the OFF kill switch
    gate-unresolved/    receipts from a collision check that could not resolve
    overlap-cache.json  the overlap detector's cache
```

Two functions resolve that path: `Get-CcxStateRoot` (PowerShell) and `state_root()` in
[`scripts/hooks/_ccxconfig.py`](https://claude-multisession.pages.dev/scripts/hooks/_ccxconfig.py). They must agree character for
character, because each side compares against records the other side wrote.

Three properties make `<git-common-dir>` the right anchor, and all three are load-bearing:

1. **Identical across worktrees.** Every linked worktree of a clone resolves the same
   git-common-dir, so a claim taken in one worktree is visible to a session in another. A state root
   under the *working* tree would give each worktree its own private, useless copy.
2. **Isolated per clone.** Two clones of the same project on one machine do not share it, so their
   locks and claims cannot collide. A state root under the home directory would merge them.
3. **Uncommittable.** It lives inside the git directory, so no `git add -A` anywhere can sweep
   coordination state into a commit, and no checkout can delete it.

Resolving it correctly is fussier than it looks:

> **Trap.** Five call sites resolved the common dir and disagreed twice. Two omitted
> `--path-format=absolute`, so git handed back a *relative* `.git`. The caller joined that onto
> whatever directory the process started in, which for a hook is wherever the harness launched the
> shell. Two others never checked the exit code, so a git failure produced an empty path that
> silently became a state root at the filesystem root.
>
> **Rule.** Always `--path-format=absolute`. Always check the exit code, and make failure a distinct
> value the caller has to handle. `Invoke-CcxGit` returns `$null` on a non-zero exit for exactly this
> reason: a swallowed git failure does not read as a failure, it reads as an empty result, which
> downstream code cheerfully treats as "no worktrees", "no refs", or "the repository root is `''`".

### The corollary: State outlives the worktree

This is the surprising half, and it is deliberate. **Remove a worktree and the claims it took are
still there.** The state lives beside the shared object store, not in the checkout.

That is the feature: a claim survives a crashed session for a peer to see, and nothing expires on a
timer. The reaper releases a claim only on **evidence**: directory gone *and* worktree deregistered,
matched on full canonicalised path equality. Releasing a live claim hands its key away.

---

## 3. The liveness fence

Almost every safety decision reduces to one question: *is that session still there?* There is exactly
one implementation, in
[`scripts/coord/session-registry.ps1`](https://claude-multisession.pages.dev/scripts/coord/session-registry.ps1), and everything else
consumes it.

### It rests on a vendor contract

The client writes `<config-root>/sessions/<pid>.json`. We do not own its shape, its location, or its
lifetime:

| Field | Type | Meaning |
|---|---|---|
| `pid` | number | OS process id hosting the session, and also the filename |
| `startedAt` | number | unix epoch **milliseconds** at which the session registered |
| `sessionId` | string | uuid; callers may match on a unique prefix |
| `cwd` | string | absolute directory the session was launched in |
| `entrypoint` | string | which surface launched it |
| `kind` | string | interactive, or whatever else the client decides to write |

Config roots are discovered dynamically: any `<home>/.claude*` directory holding a `sessions`
directory. Several logins can coexist on one machine, and a session is only visible to the login
that owns it.

**This can break under you.** A renamed field or a changed `startedAt` unit degrades every fence to
"cannot tell", not a confident wrong answer. Hence *not alive* versus *could not be evaluated*
below. `bin/ccx-doctor.ps1` counts records read and placed, so a schema change reads as zero.

### It is not a pid check

> **Trap.** Checking liveness by testing whether the recorded pid exists. Pids get reused and these
> records outlive their process, so a recycled pid reports a long-dead session as live. The client
> ships a `procStart` field intended for exactly this fence; do not depend on it. It may be absent
> or in a form you did not expect. The guard shipped alongside it returns true when it cannot tell,
> so it fails **open**, toward "still alive".
>
> **Rule.** Read the process start time yourself and require it to be consistent with the recorded
> session start. A process that started *after* the session registered is a recycled pid, not that
> session.

### The five answers, and what each licenses

| State | Meaning | Vetoes a destructive action? |
|---|---|---|
| `LIVE` | pid resolves and its start time is consistent | yes |
| `UNVERIFIED` | pid resolves; the fence could not be evaluated (start time unreadable, no `startedAt`) | yes |
| `UNREADABLE` | the record itself cannot be fenced (no pid, or a non-numeric one) | yes |
| `STALE` | pid resolves but belongs to a different process | no |
| `DEAD` | no such pid | no |
| not found | no record at all | no |

`UNREADABLE` ranks with the possibly-live states, not the gone ones. It used to report `DEAD`. A
registry file caught mid-write has exactly that shape, the signature of a session that launched one
second ago. To a caller about to delete that worktree, it read as "nobody is there".

### Liveness may only veto, never permit

**Nothing here can prove a session is gone.** There is no heartbeat anywhere, and registry writes
are event-driven, so the fence can report presence and nothing else. Every other safety rule in this
repository leans on that one invariant.

> **Trap.** The fence returned `DEAD`/`STALE`/absent for a worktree, and that was read as permission
> to delete it.
>
> **Rule.** Wire liveness so it can only block a destructive action, never authorize one. A negative
> verdict is the *absence of a veto*, not a permission. Say so in a comment next to the code, because
> the inverse reading is the natural one, and `occupancy.ps1` encodes it structurally:
> `Get-WorktreeOccupants` returns veto-worthy rows only, and drops `DEAD`/`STALE` on the floor so no
> caller can mistake them for a green light.

### Availability is part of the answer, not an absence of one

"The fence ran and nobody is here" and "the fence could not look" produce the *same empty row set*.

> **Trap.** An occupancy check ran, found no session records matching any candidate, and reported
> all-clear. It had failed to read the registry at all. Worse: records that would not parse, and
> records that parsed but carried no `cwd`, were dropped by a silent `continue` and appeared in no
> count.
>
> **Rule.** Return a receipt alongside the rows and gate on it.
> `Get-WorktreeOccupancy` reports `RootsExamined`, `RecordsExamined`, `RecordsUnplaceable` and
> `UnplaceableFiles`, and sets `Available` only when there was something to examine: at least one
> config root holding a registry, at least one readable record in it, **and** no record that could not
> be *placed*. A caller about to destroy something gates on `Available`, prints the receipt, and
> refuses when it is false. Count what you **examined**, not what you found.

An unplaceable record makes the *whole* fence unavailable, not just that row, because it cannot be
attributed to, or cleared from, any particular worktree. It could name the very tree the caller is
about to delete.

The same shape recurs everywhere: an unreadable claim file belongs to nobody, and an empty problem
list means nothing unless you can prove the directory you scanned existed.

### What the fence cannot see

State these wherever the fence is consumed. They are not hypothetical.

| Blind spot | Why |
|---|---|
| a session writing into a worktree **by absolute path** from somewhere else | records carry the cwd a session was *launched* in. Measured on the repo this tooling was developed in, over a month, **29% of the writes made by sessions sitting in the primary** landed in a sibling worktree |
| a cwd recorded as a UNC path or an 8.3 short path | the match is a string compare on the canonicalised path, and neither spelling canonicalises to the worktree's own |
| a session that never registered at all | nothing to read |

That 29% is why a cwd-keyed signal alone never licenses a destructive action. Deleting needs a
**second, independent, non-cwd signal**, and either may veto alone. It is why the primary-checkout
gate keys on the write's **target path**: keying on cwd would deny all 29%, every one correct.

Two further blind spots belong to the *tooling around* the fence rather than to the fence itself:

- **The desktop client's `list_sessions` cannot see every session kind**: it answers "who can be
  messaged", not "who exists". Only `<config-root>/sessions/<pid>.json` carries every surface.
  Measured at [the two rosters answer different questions](COORDINATION.md#presence-who-is-here).
- **Transcript mtime is not liveness.** A session in a long multi-agent workflow files output under
  a subdirectory and barely touches its transcript; one verifiably-live session sat idle by mtime
  for three times its threshold. Consult the registry **and** mtime; refuse if either says live.

### One copy of the fence, on purpose

The roster (`presence.ps1`), the transcript-moving tool (`sessions.ps1`) and the reaper
(`prune-merged.ps1`) all need the same answer, and the reaper's is the one that deletes things.

> **Rule.** Two copies of a safety check drift, and the copy that drifts is the one nobody is
> testing. Factor it into one shared file both callers dot-source, deliberately, and say so in a
> comment so the next session does not re-fork it.

The layering is strict:

<!-- no-copy -->
```text
prune-merged.ps1 / presence.ps1 / sessions.ps1     callers
        |
occupancy.ps1        cwd -> worktree matching, the availability receipt, veto sets
        |
session-registry.ps1 the liveness fence itself
        |
_common.ps1          path comparison, the state root, git plumbing
```

`occupancy.ps1` still exposes a `ConvertTo-Norm` helper, but it is now a one-line delegation to
`ConvertTo-CcxComparablePath`. Two spellings of "are these two paths the same place" is the same
class of bug as two copies of the fence.

---

## 4. Exclusive-create, never read-modify-write

Three different things need mutual exclusion between sessions: a **sequence number**
(`alloc.ps1`), a **unit of work** (`claim.ps1`), and a **short critical section** (`lock.ps1`). All
three use the identical primitive, and it is not a lock file you check and then write.

```powershell
# The failed create IS the mutual exclusion.
$fs = [System.IO.File]::Open(
    $file,
    [System.IO.FileMode]::CreateNew,      # throws IOException if it already exists
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None)
```

> **Trap.** Building a "registry" you read, edit, and write back. Measured on the repo this tooling
> was developed in: **8 concurrent PowerShell writers to one shared file lost 4 of the 8 writes, with
> no error**. That is not a registry.
>
> **Rule.** Claim by atomically creating a per-item file, a test-and-set. If a sibling got there
> first the create throws and you move on. Verified with the same harness: 8 concurrent allocator
> processes produced 8 distinct numbers and zero collisions.

The three users differ only in lifetime and policy:

| | `alloc.ps1` | `claim.ps1` | `lock.ps1` |
|---|---|---|---|
| Protects | a number in a shared sequence | a unit of work | a critical section |
| File | `alloc/<kind>/<n>.json` | `claims/<key>.json` | `locks/<name>.lock` |
| Lifetime | forever, never reclaimed | until released by hand | seconds |
| On collision | try the next number | report the holder and refuse | retry until timeout, then fail loudly |
| Released by | nothing | the holder, or `-Force` after proving the holder is gone | the caller's `finally` |

Numbers are never reclaimed on purpose: an abandoned branch holds its number forever and the sequence
develops holes. **Holes are free; collisions are not.** A collision here merges *clean*, because the
two sessions never touch the same bytes, so nothing in git can detect it.

### Replacing a file that is itself the lock

A claim's note lives in a file whose *existence* is the mutual exclusion. Rewrite it and the name
briefly does not exist, and in that instant another worktree can claim a key you hold.

> **Trap.** `Move-Item -Force` is delete-then-rename and opens exactly that window. Measured on the
> repo this tooling was developed in: across 400 moves the destination was absent on 2,559 of 154,506
> polls.
>
> **Rule.** Write a temp file, then `[System.IO.File]::Move($tmp, $file, $true)`, which is a
> replace-existing rename and atomic on NTFS. The same harness polled 134,581 times and never once
> saw the name missing. It can fail *transiently* instead (about 13.5% under back-to-back churn, when
> a scanner or an editor holds the destination), and failing is the safe direction: the old note
> survives and the claim stays yours. Losing the lock is not safe. Never orphan the temp file, it
> lives in the claim registry.

A PowerShell trap: .NET **method** exceptions arrive wrapped in a `MethodInvocationException`, so
`catch [System.IO.IOException]` around `Move` never matches. It escapes to
`$ErrorActionPreference = "Stop"`, cleanup never runs, and the temp file is orphaned. That catch is
untyped on purpose.

---

## 5. There are no TTLs anywhere, and that is the design

No lock expires. No claim expires. Nothing is reaped on a timer. This is the most frequently
questioned decision in the repository, so the reasoning is stated once, here.

A lock that expires on a timer hands the critical section to a second process **while the first is
still inside it**. It does that silently, at the exact moment the operation is slowest, which is
precisely when a timeout is most likely to be the wrong inference. Compare the two failure modes:

| | Failure it prevents | Failure it causes |
|---|---|---|
| TTL | a wedged lock: visible, one command from fixed | a concurrent double-write nobody observes |

The asymmetry decides it: no expiry, no reaper, no "probably dead". On timeout `Enter-CcxLock`
fails **loudly** with the holder's identity and the manual override. **We retry; we never steal.**
No liveness signal proves abandonment (section 3), so breaking a lock re-opens the race it closes.

The corresponding rule for claims: `-List` reports each holder's **liveness**, not the claim's age.

### The rule is about held state, and a message is not held state

The heading says anywhere, and one thing in this model does expire: a message. That is not an
exception to the rule so much as the reason it has to be stated precisely.

Expiry on **held state** hands a critical section to a second process while the first is still in
it. Expiry on a **message** does the reverse: it stops a stale instruction from being acted on. A
three-day-old "hold the trunk" is better refused than obeyed.

Which is already the standing requirement for a broadcast, one that
[must carry a hard expiry or a recipient-evaluable predicate](COORDINATION.md#a-broadcast-needs-an-expiry-or-a-recipient-evaluable-predicate).

**The part that is not closed.** Message expiry is silent in both directions: the recipient is never
told a message existed, and the sender is never told it went unread. That is the failure the table
above rejects TTLs for -- one nobody observes.

Measured 2026-08-11, on the implementation behind [session mail](SESSION-MAIL.md), which ships no
script here: the mail TTL was 720 minutes, so an ordinary overnight gap expired a message. It is now
4320. **A longer TTL lowers the frequency and does not touch the silence.**

> **Trap.** Age was the original signal and it was actively misleading. A claim was labeled
> `STALE ~21h` and recommended for release; its holder had committed **two minutes earlier**.
> Following the tool's own recommendation would have freed the key for a second session to start
> building what someone was mid-flight on, the exact duplicate build the registry exists to prevent.
>
> **Rule.** Report what the **holder** is doing, not how old the record is. A long claim is the
> normal shape of long work. Recommend a force-release only in the one state that can be *proven*
> (the worktree no longer exists on disk); in every other state say so and say "confirm first". A
> failed probe reports `failed`, never `gone`, because a probe that reported death would turn an
> unreadable path into a license to release a live session's claim.

Because there is no timer, a record whose *content* is broadcast must be correctable in place:

> **Trap.** `-Take -Note` on a key you already held accepted the new note, reported success, and
> discarded it. The only way to correct a note was release-then-retake, which drops the claim in
> between and re-opens the race. Meanwhile the stale note was announced to every joining session as
> current intent.
>
> **Rule.** Make in-place refresh a first-class operation for any coordination record whose content
> is published to others, and stamp the refresh time separately from the claim time. A record you can
> only replace by deleting is a record you cannot safely correct.

Related: coordination that a tool cannot *read* does not count. Two sessions once agreed in prose to
hand over a file; the gate still refused, because the gate reads git. Anything worth coordinating has
to publish something a gate consumes.

---

## 6. Conventions that make comparisons work

These look like style. They are correctness.

### Canonicalise before comparing, and fold for comparison only

`ConvertTo-CcxComparablePath` (PowerShell) and `fold_path()` (Python) are the *only* implementations.
Both do `GetFullPath`/`abspath` first, then normalize separators to `/`, strip a trailing `/`, and
lower-case **only on a case-insensitive filesystem**.

> **Trap 1.** Four of five earlier copies skipped canonicalisation. Without it,
> `<primary>-work/../<primary>/x.md` does not string-match the primary's prefix and walks straight
> through a gate whose entire job is to notice it.
>
> **Trap 2.** A relative path must resolve against the directory the **command** will run from, which
> for a hook is the session's cwd arriving in the payload, not the hook process's own cwd.
> `cd ../../..` is exactly how a session in a nested worktree names the repository root, and
> resolving it against wherever the shell was started meant `cd ../../.. && git reset --hard` did not
> look like it touched the primary at all.
>
> **Trap 3.** A gate lower-cased a path for comparison and then handed the **same lowercased string**
> to `git -C`. Harmless on Windows; on a case-sensitive CI runner git missed the real directory,
> failed, and the rule fell through to its allow path. The gate silently stopped enforcing on exactly
> the platform nobody was watching.
>
> **Rule.** **The folded form is for comparison only.** Never pass it to git, to the filesystem, or
> to a message the operator reads; keep the raw string for those. And fold case *conditionally*: on a
> case-sensitive filesystem `/tmp/Primary` and `/tmp/primary` really are two directories, and folding
> them together would make a gate govern a directory it was never pointed at.

Both helpers return `''` rather than throwing. Every caller sits on a fail-open path, where an
exception would end the process and let the tool call through with nothing said. `''` means "we
cannot say what this points at", which callers read as "not governed".

### A prefix test is not a containment test

`Test-CcxPathUnder` requires `$Path -eq $Root -or $Path.StartsWith("$Root/")`. **The `/` is the
point.** A bare `StartsWith` matches a *string*, not a *directory*: a sibling worktree named
`<primary>-<task>` starts with the primary's path, so a raw prefix test claims it is inside.

Where prefix matching is genuinely unavoidable, **longest prefix must win**, explicitly.

> **Trap.** A matcher needed prefix matching (a session may sit in any subdirectory) and took the
> *first* hit. Linked worktrees are nested under the primary, so the primary's path is a prefix of
> every nested worktree path, and the primary's row absorbed whichever nested session the hash table
> happened to enumerate first, reporting the primary live on trunk.
>
> **Rule.** Implement longest-prefix-wins explicitly, and test it with a nested worktree present.
> `Get-WorktreeOccupancy` does this, and then `Get-WorktreeOccupants -IncludeNested` deliberately
> folds descendants back in for destructive callers, because a session in a nested tree must veto the
> removal of its **ancestor**.

Note the asymmetry: longest-match is right for a *roster* (report the innermost checkout) and wrong
for a *destructive caller* (the ancestor's `--force` removal takes the nested tree with it). Same
data, two questions, two answers.

### Name folding: The filename is the mutex

`ConvertTo-CcxSafeName` / `safe_name()` fold free text to `[a-z0-9._-]`, collapsing runs to `-` and
trimming. They must match **character for character** across the two languages.

Folding here is **unconditionally** lower-case, unlike path comparison, because this is a name we are
*minting* rather than a path the filesystem already assigned. `Auth-Fix` and `auth-fix` must be the
same claim on every platform, or the claim does not exclude anything.

Callers must reject `''` rather than substituting a default. A name that reduces to nothing is a
caller bug, and silently coining one produces a lock everybody shares.

### UTF-8 without a BOM

Every state file is written as UTF-8 **with no byte-order mark**, via
`[System.Text.Encoding]::UTF8.GetBytes(...)` rather than a cmdlet that may prepend one.

The reason is concrete. The Python commit-msg gate reads claim files with `encoding="utf-8"`, and a
BOM makes `json.loads` raise. That gate swallows a parse error into "not claimed", which silently
disables the gate for that key. A cosmetic byte turns an enforced control into a decorative one.

In Python, `encoding="utf-8"` on `subprocess.run` is **required**: `text=True` alone decodes with
the locale default, `cp1252` on stock Windows. A UTF-8 index file raised in subprocess's reader
thread, `proc.stdout` came back `None`, and every commit the gate guards failed silently.

All hook output is **ASCII only**, in both languages, because a console that is not UTF-8 renders
anything else as mojibake, and one convention across the set beats two.

### ISO-8601, round-tripped

Timestamps are written with `.ToString("o")`. Reading one back is where it goes wrong:

> **Trap.** `ConvertFrom-Json` silently coerces an ISO-8601 string into a `[datetime]`, so
> `[string]$record.claimed` does not give you back what was written, it gives the local short form,
> losing sub-second precision and the UTC offset. Writing that back downgrades the stamp on every
> refresh, and it still parses, so nothing ever complains.
>
> **Rule.** Round-trip explicitly (`ConvertTo-Stamp` in `claim.ps1`): if the value came back as a
> `[datetime]` or `[datetimeoffset]`, re-render it with `"o"`.

The same coercion bites *keys*. A claim key shaped like `2020-01-01T00:00:00` comes back through
`[string]` as a local short-form date, so the record names a key nobody typed and `-Release` cannot
match it. Write the caller's spelling; the folded filename is the identity.

---

## 7. `ccx.config.json`: Six knobs, and nothing else

One file at the repository root. It is **both** the configuration and the **opt-in marker**. The
user-scope hooks run in every repository on the machine. So "is this repo governed?" has to be
answerable without running anything: the file is either there or it is not.

It is deliberately *not* "does some script exist on disk". That discriminator is true in a
half-installed tree, false in a repo that vendors the scripts elsewhere, and silently true in a fork
that only copied a directory.

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

| # | Knob | Default | What it derives or controls |
|---|---|---|---|
| 1 | `prefix` | `ccx` | the state root `<git-common-dir>/<prefix>-coord`, the git config key `<prefix>.homeBranch`, and the per-worktree home-branch marker file `<prefix>-home-branch` |
| 2 | `trunk` | `auto` | the base for new worktrees, the allocator's floor sweep, the overlap detector's comparison, the sequence gate's base ref |
| 3 | `worktreeLayout` | `sibling` | where **we** create worktrees. Nested-worktree *exclusion* from destructive operations is unconditional regardless |
| 4 | `setupHook` | none | a script run after `git worktree add`, which is what keeps this repo language-agnostic |
| 5 | `protectedRefs` | `main`, `master` | which refs `push_guard.py` refuses a direct push to |
| 6 | `sequences` | none | `alloc.ps1 -Kind <name>` and `seq_check.py`. **Omit the key entirely and the sequence machinery is simply off** |

Two validation rules are worth knowing because they are enforced at load:

- `prefix` must match `^[A-Za-z][A-Za-z0-9-]{0,31}$`. It becomes a directory name, a git config key
  *and* an environment-variable stem. Anything that would need escaping in any of those is rejected
  once, at load, rather than producing a state root nobody can type.
- `sequences` **absent** and `sequences` **empty** mean the same thing on purpose. A caller must not
  treat "no sequences" as an error; a repository that maintains no numbered sequence should not have
  to carry a disabled allocator.

Three names are **not** derived from `prefix`: `~/.claude/hooks/ccx-gate.repos.txt` (the gate's
allowlist) and the user-settings markers `ccx-coord` and `ccx-announce`. Ownership is tested by
substring match, so **neither marker may ever be a substring of the other**. Rename one in one
commit.

`protectedRefs` is the exception: an explicitly **empty** list is *not* an absent key. `[]` says
"this repository protects nothing", disables the guard and **prints why on stderr**: a guard that
is off must never look like one that passed. A missing key means nobody chose: defaults.

A corrupt config is fail-**closed** on the Python side: `load_config` raises rather than falling back
to defaults nobody chose. A governed repository whose configuration cannot be read must stop.

### Environment overrides and kill switches

| Variable | Effect |
|---|---|
| `CCX_CONFIG` | names the config file directly and short-circuits the upward walk (tests, `ccx doctor`) |
| `CCX_TRUNK` | overrides `trunk` for this session; wins over the config file |
| `CCX_PYTHON` | which interpreter the git hooks use |
| `CCX_ALLOW_DIRECT_PUSH=1` | the push guard's documented escape hatch |
| `CCX_ANNOUNCE_DISABLE` | secondary announce off switch |
| `CCX_EDITOR` | which editor `spawn.ps1` launches (falls back to `EDITOR`, then `code`) |
| `CCX_SESSION_BANNER` | path to the session banner text |
| `CCX_WORKTREE_PATH`, `CCX_WORKTREE_NAME`, `CCX_PRIMARY_ROOT`, `CCX_BASE_REF` | set for the `setupHook` process |

**A kill switch must reach a session that is already running.** Environment variables and settings
edits do not: they take effect at launch. So the real switches are **files**:

- delete `~/.claude/hooks/ccx-gate.repos.txt`, or empty it, and the primary-checkout gate is off;
- create `<state-root>/announce/OFF` and the announce hook stands down.

### Couplings you cannot abstract away, so document them

These are load-bearing and honest:

1. **PowerShell 7 and Windows-first.** A shell port is a separate project. The Python part --
   git-hook checkers, leak gate, shared substrate -- is stdlib-only and portable. Case-folding and
   process start-time reads degrade off Windows; the doctor names that blind spot on every run.
2. **The client's session-record schema is a vendor contract**, see section 3. It can break under you.
3. **The `ccd_session_mgmt` MCP server is desktop-only**, and announce delivery depends on it. On a
   plain CLI install the hook still fires and asks the model for tools it does not have, so nothing
   is delivered. Leave that hook uninstalled there, or create the OFF file. Nothing else needs it.
4. **`<git-common-dir>` as the state root.** Correct, deliberate, and not portable to a
   non-git-backed setup. Keep it, and keep its corollary in mind.
5. **Windows path case-insensitivity** in the folding rule. This has already broken once on a
   case-sensitive CI runner; see section 6.

---

## 8. The failure mode this whole design is guarding against

Every failure mode in this system is **byte-identical to success**.

- a wired hook that resolves nothing prints what a healthy one with no peers prints;
- a fence that could not read the registry returns the empty list of one that found nobody;
- a gate missing its helper files exits 0;
- a control merged but never installed is a source artifact with green tests.

So this repository is receipts, not logic: print what you scanned, count what you examined, separate
"found nothing" from "could not look", name your blind spots.

### Prove the controls before you trust them

**The goal.** Find out which controls are wired in this clone, rather than which ones exist in the
source. [Quickstart](QUICKSTART.md) is the install this checks.

**What to do.**

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

**What happens next.** A row per control, tagged:

- `OK` -- installed, wired, and where it can be attacked it refused what it must;
- `RED` -- proven broken: it allowed something it must deny, or denied something it must allow;
- `OFF` -- implemented here, but nothing invokes it: zero enforcement;
- `??` -- the check could not be run, and a skip is never a pass.

The doctor does not read settings: it **fires each control and requires it to refuse**, with a
paired negative control. Run this before you trust any of it.
