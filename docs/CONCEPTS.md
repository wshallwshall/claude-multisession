# Concepts

The mental model behind this tooling. Read this before the installers: almost every rule in the
repository is a consequence of one of the five ideas below, and the ones that look like paranoia are
the ones that were paid for.

The whole system is three layers:

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

Everything else in the repository, the hooks, the reaper, the allocator, the announce path, is an
application of those three.

---

## 1. Worktree-per-session

A git worktree is a second working directory backed by the same git directory: same history, same
remotes, same object store, a different branch checked out and a different index. Two concurrent
sessions in the *same* checkout fight over one working tree, and the fight is silent, one side's
`git checkout` swaps the files out from under the other's edit.

So the unit of isolation is the worktree, and the unit of work is a branch.

### Primary and linked

The **primary** checkout is the main working tree of the clone, and it is the first entry
`git worktree list --porcelain` reports. `Get-CcxPrimaryRoot` in
[`scripts/coord/_common.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/coord/_common.ps1) resolves it that way, deliberately:

> **Trap.** Four earlier copies of this derived the repository root as `$PSScriptRoot/../..`, the
> checkout the *script* happens to live in. Run from a linked worktree that resolves to the
> worktree's own root, so a new worktree was created as a sibling *of a sibling*, and the pruning
> tool, which anchors on the primary, then could not see it as a candidate at all.
>
> **Rule.** Anchor layout on the primary, never on where the script lives. The tooling must behave
> identically whichever checkout you invoke it from.

### Two layouts, and both are real

| Layout | Path | Who creates it |
|---|---|---|
| `sibling` (default) | `<parent-of-primary>/<primary-leaf>-<name>` | this tooling, via `scripts/worktree/new.ps1` |
| `nested` | `<primary>/.claude/worktrees/<name>` | the client itself, and this tooling if you configure it |

`worktreeLayout` in `ccx.config.json` picks where **we** create worktrees. It does not change the
fact that both populations exist on a real machine at the same time. `Get-CcxWorktreePath` owns the
formula, once, because it used to be duplicated in four scripts and pattern-*matched* in a fifth,
which is how a rule and its enforcement can disagree without either being wrong on its own.

> **Trap.** A nested checkout is git-ignored inside its parent, so the parent reads perfectly clean,
> and `git worktree remove --force` on the parent deletes both, leaving the nested one registered
> with no directory. Meanwhile a sweep run from the wrong directory printed a green "no sibling
> worktrees to consider" and exited 0, a wrong-cwd run reporting a clean bill of health.
>
> **Rule.** Any path containing a `.claude/worktrees/` segment is excluded from destructive
> operations *unconditionally*, whatever the layout setting says. That is
> `Test-CcxHarnessWorktreePath`, and it exists as one named test rather than two inline regexes
> because two rules depend on it and they pull in opposite directions: a gate protecting the primary
> must **not** govern a nested worktree (a git verb there swaps only its own tree), and a reaper must
> **never** remove one (a live session is standing in it).

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
separate question answered by occupancy, cleanliness and merge state, never by the name.

### What a worktree does *not* isolate

A fresh worktree feels completely isolated, separate files, separate branch, separate index,
separate build environment. Three things are not isolated, and each has bitten:

| Shared thing | Consequence |
|---|---|
| the git directory | one `.git/config.lock`; concurrent `git worktree add` races it, which is why creation is serialised under a cross-session mutex |
| the git hooks directory | one `pre-commit` / `commit-msg` / `pre-push` set governs **every** worktree at once, and sees every write route into the repo |
| the assistant's own project memory | it lives outside the repo, one directory per machine, and last write wins. Reads are fine; coordinate writes, or let exactly one session own them |

And one thing is isolated that you may wish were not: a project-scoped `.claude/settings.json` is
usually git-ignored, so it is a creation-time snapshot that nothing refreshes and that several
worktrees may simply not have. That is why the coordination hooks install at **user** scope. See
[`INSTALL.md`](https://github.com/wshallwshall/claude-multisession/blob/main/INSTALL.md).

Per-checkout environment setup, a virtualenv, a package install, a build, is deliberately not in
`new.ps1`. It is whatever `setupHook` names, invoked with `CCX_WORKTREE_PATH`, `CCX_WORKTREE_NAME`,
`CCX_PRIMARY_ROOT` and `CCX_BASE_REF` in the environment. That is what keeps the repository
language-agnostic; see [`examples/worktree-setup.ps1.example`](https://github.com/wshallwshall/claude-multisession/blob/main/examples/worktree-setup.ps1.example).

---

## 2. The shared state root

Every piece of cross-session coordination state lives in exactly one place:

```text
<git-common-dir>/<prefix>-coord/
    alloc/              one file per allocated sequence number
    claims/             one file per claimed unit of work
    locks/              one file per held short-lived mutex
    announce/           per-session announce bookkeeping, and the OFF kill switch
    gate-unresolved/    receipts from a collision check that could not resolve
    overlap-cache.json  the overlap detector's cache
```

`Get-CcxStateRoot` (PowerShell) and `state_root()` in
[`scripts/hooks/_ccxconfig.py`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/hooks/_ccxconfig.py) resolve it, and they must agree
character for character, because each side compares against records the other side wrote.

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
> `--path-format=absolute`, so git handed back a *relative* `.git` which the caller joined onto
> whatever directory the process happened to start in, and for a hook that is wherever the harness
> launched the shell. Two others never checked the exit code, so a git failure produced an empty
> path that silently became a state root at the filesystem root.
>
> **Rule.** Always `--path-format=absolute`. Always check the exit code, and make failure a distinct
> value the caller has to handle. `Invoke-CcxGit` returns `$null` on a non-zero exit for exactly this
> reason: a swallowed git failure does not read as a failure, it reads as an empty result, which
> downstream code cheerfully treats as "no worktrees", "no refs", or "the repository root is `''`".

### The corollary: state outlives the worktree

This is the surprising half, and it is deliberate. **Remove a worktree and the claims it took are
still there.** The state lives beside the shared object store, not in the checkout.

That is a feature: it is what lets a claim survive a crashed session so a peer can see it. It is also
why nothing here releases state on a timer. The reaper releases a claim only on **evidence**, the
directory is gone *and* the worktree is deregistered, matched on full canonicalised path equality.
Releasing a *living* worktree's claim hands its key away and causes the duplicate build the registry
exists to prevent.

---

## 3. The liveness fence

Almost every safety decision reduces to one question: *is that session still there?* There is exactly
one implementation, in
[`scripts/coord/session-registry.ps1`](https://github.com/wshallwshall/claude-multisession/blob/main/scripts/coord/session-registry.ps1), and everything else
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

Config roots are discovered dynamically (`<home>/.claude*` directories that contain a `sessions`
directory), because several logins can coexist on one machine and a session is only visible to the
login that owns it.

**This can break under you.** If a future client renames a field, moves the directory, or changes
`startedAt`'s unit, every fence here degrades to "cannot tell" rather than to a confident wrong
answer. That is the entire reason the states below distinguish *not alive* from *could not be
evaluated*, and `bin/ccx-doctor.ps1` prints how many records it read and placed, so a schema change
shows up as a count going to zero instead of as a silent all-clear.

### It is not a pid check

> **Trap.** Checking liveness by testing whether the recorded pid exists. Pids get reused and these
> records outlive their process, so a recycled pid reports a long-dead session as live. The client
> ships a `procStart` field intended for exactly this fence; do not depend on it. It may be absent or
> in a form you did not expect, and the guard shipped alongside it returns true when it cannot tell,
> i.e. it fails **open** toward "still alive".
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

`UNREADABLE` ranks with the possibly-live states, not with the gone ones, and it used to be reported
as `DEAD`. A registry file caught mid-write has exactly that shape, which makes it the signature of a
session that launched one second ago, so a session that had just started read as "nobody is there" to
a caller about to delete its worktree.

### Liveness may only veto, never permit

**This is the single most important invariant in the repository.** There is no heartbeat anywhere and
registry writes are event-driven, so nothing here can *prove* a session is gone, only that it is
present.

> **Trap.** The fence returned `DEAD`/`STALE`/absent for a worktree, and that was read as permission
> to delete it.
>
> **Rule.** Wire liveness so it can only block a destructive action, never authorise one. A negative
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
| a session writing into a worktree **by absolute path** from somewhere else | records carry the cwd a session was *launched* in. Measured on the repo this tooling was developed in, over a month, about **29% of writes** came from a session sitting in the primary and landed in a sibling worktree |
| a cwd recorded as a UNC path or an 8.3 short path | the match is a string compare on the canonicalised path, and neither spelling canonicalises to the worktree's own |
| a session that never registered at all | nothing to read |

The 29% figure is why a cwd-keyed signal alone is never sufficient for a destructive action. Anything
that deletes needs a **second, independent, non-cwd signal**, and either signal must be able to veto
on its own. It is also why the primary-checkout gate keys on the write's **target path** and never on
the session's cwd: a cwd-keyed gate would have denied all 29% of those writes, every one of which was
already correct.

Two further blind spots belong to the *tooling around* the fence rather than to the fence itself:

- **The desktop client's `list_sessions` cannot see every session kind.** It enumerates an in-memory
  map of sessions that client itself spawned; a session launched by an editor extension is never
  entered into it, not filtered out, never registered, so it is invisible there and cannot be
  messaged. Verified against a live editor-extension session sharing the *default* config root, so it
  is not a per-login split. `<config-root>/sessions/<pid>.json` is the only registry carrying every
  surface; read that to answer "who exists", and treat `list_sessions` as authoritative only for who
  can be **messaged**.
- **Transcript mtime is not liveness.** A session running a long multi-agent workflow files its
  output under a subdirectory and barely touches its own transcript; one verifiably-live session sat
  idle by mtime for three times the threshold that was supposed to protect it. Consult the registry
  **and** mtime, and refuse if either says live.

### One copy of the fence, on purpose

The roster (`presence.ps1`), the transcript-moving tool (`sessions.ps1`) and the reaper
(`prune-merged.ps1`) all need the same answer, and the reaper's is the one that deletes things.

> **Rule.** Two copies of a safety check drift, and the copy that drifts is the one nobody is
> testing. Factor it into one shared file both callers dot-source, deliberately, and say so in a
> comment so the next session does not re-fork it.

The layering is strict:

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

Refreshing a claim's note means rewriting a file whose *existence* is the mutual exclusion, so any
instant in which the name does not exist is an instant another worktree can claim a key you hold.

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

One PowerShell subtlety that cost a debugging session: an exception thrown by a .NET **method** is
wrapped in a `MethodInvocationException`, so `catch [System.IO.IOException]` around that `Move` never
matches, the failure escapes to `$ErrorActionPreference = "Stop"`, the cleanup never runs, and the
temp file is orphaned. The catch there is untyped on purpose.

---

## 5. There are no TTLs anywhere, and that is the design

No lock expires. No claim expires. Nothing is reaped on a timer. This is the most frequently
questioned decision in the repository, so the reasoning is stated once, here.

A lock that expires on a timer hands the critical section to a second process **while the first is
still inside it**, silently, at the exact moment the operation is slowest, which is precisely when a
timeout is most likely to be the wrong inference. Compare the two failure modes:

| | Failure it prevents | Failure it causes |
|---|---|---|
| TTL | a wedged lock: visible, one command from fixed | a concurrent double-write nobody observes |

The asymmetry decides it. So: no expiry, no reaper, no "probably dead". On timeout `Enter-CcxLock`
fails **loudly** with the holder's identity and the manual override, rather than quietly deciding the
holder is dead. **We retry; we never steal.** There is no reliable liveness signal to prove
abandonment with, see section 3, so breaking a lock re-opens the exact race the lock exists to close.

The corresponding rule for claims: `-List` reports each holder's **liveness**, not the claim's age.

> **Trap.** Age was the original signal and it was actively misleading. A claim was labelled
> `STALE ~21h` and recommended for release; its holder had committed **two minutes earlier**.
> Following the tool's own recommendation would have freed the key for a second session to start
> building what someone was mid-flight on, the exact duplicate build the registry exists to prevent.
>
> **Rule.** Report what the **holder** is doing, not how old the record is. A long claim is the
> normal shape of long work. Recommend a force-release only in the one state that can be *proven*
> (the worktree no longer exists on disk); in every other state say so and say "confirm first". A
> failed probe reports `failed`, never `gone`, because a probe that reported death would turn an
> unreadable path into a licence to release a live session's claim.

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
Both do `GetFullPath`/`abspath` first, then normalise separators to `/`, strip a trailing `/`, and
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

Both helpers return `''` rather than throwing, because every caller is on a fail-open path where an
exception would end the process and let the tool call through with nothing said. `''` means "we
cannot say what this points at", which callers read as "not governed".

### A prefix test is not a containment test

`Test-CcxPathUnder` requires `$Path -eq $Root -or $Path.StartsWith("$Root/")`. **The `/` is the
point.** A bare `StartsWith` is a prefix match on a *string*, not on a *directory*: a sibling worktree
named `<primary>-<task>` has a path that literally starts with the primary's, so a raw prefix test
claims every sibling is inside the primary.

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

### Name folding: the filename is the mutex

`ConvertTo-CcxSafeName` / `safe_name()` fold free text to `[a-z0-9._-]`, collapsing runs to `-` and
trimming. They must match **character for character** across the two languages.

Folding here is **unconditionally** lower-case, unlike path comparison, because this is a name we are
*minting* rather than a path the filesystem already assigned: `Auth-Fix` and `auth-fix` must be the
same claim on every platform, or the claim does not exclude anything.

Callers must reject `''` rather than substituting a default. A name that reduces to nothing is a
caller bug, and silently coining one produces a lock everybody shares.

### UTF-8 without a BOM

Every state file is written as UTF-8 **with no byte-order mark**, via
`[System.Text.Encoding]::UTF8.GetBytes(...)` rather than a cmdlet that may prepend one.

The reason is concrete: the Python commit-msg gate reads claim files with `encoding="utf-8"`, a BOM
makes `json.loads` raise, and that gate swallows a parse error into "not claimed", which silently
disables the gate for that key. A cosmetic byte turns an enforced control into a decorative one.

The mirror-image rule on the Python side: `encoding="utf-8"` on `subprocess.run` is **required, not
cosmetic**. `text=True` alone decodes with the locale default, which is `cp1252` on a stock Windows
box, so a UTF-8 index file (em dashes, arrows, emoji) raised inside subprocess's reader thread,
`proc.stdout` came back `None`, and the caller died on the next call, blocking every commit that
touched the files the gate guards. The gate's failure mode was the one it exists to prevent: silent,
and worst on exactly the files it looks at.

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

The same coercion bites *keys*: a free-text claim key shaped like `2020-01-01T00:00:00` comes back
through `[string]` as a local short-form date, producing a record naming a key nobody typed and that
`-Release` cannot be spelled to match. Write the caller's current spelling, and let the folded
filename be the real identity.

---

## 7. `ccx.config.json`: six knobs, and nothing else

One file at the repository root. It is **both** the configuration and the **opt-in marker**: the
user-scope hooks run in every repository on the machine, so "is this repo governed?" has to be
answerable without running anything. The file is either there or it is not.

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
  *and* an environment-variable stem, so anything needing escaping in any of those is rejected once,
  at load, rather than producing a state root nobody can type.
- `sequences` **absent** and `sequences` **empty** mean the same thing on purpose. A caller must not
  treat "no sequences" as an error; a repository that maintains no numbered sequence should not have
  to carry a disabled allocator.

Three names are **not** derived from `prefix`, and knowing which is which matters when you rename
anything: the gate's allowlist file is the fixed `~/.claude/hooks/ccx-gate.repos.txt`, and the two
installer markers written into the user settings file are the fixed strings `ccx-coord` and
`ccx-announce`. Those markers are on-disk identity, which is why they are literals rather than
computed, and why **neither may ever be a substring of the other**: ownership is tested by substring
match, so a marker like `ccx-coord-announce` would make one installer claim the other's hook entries.
Rename any of the three once, in one commit, touching every reader.

`protectedRefs` is the exception to that pattern, and deliberately so: an explicitly **empty** list is
*not* the same as an absent key. `[]` says "this repository protects nothing", disables the guard, and
**prints why on stderr**, because a guard that is off must never look like a guard that passed. A
missing key means nobody chose, and gets the defaults.

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
edits do not, they take effect at launch. So the real switches are **files**:

- delete `~/.claude/hooks/ccx-gate.repos.txt`, or empty it, and the primary-checkout gate is off;
- create `<state-root>/announce/OFF` and the announce hook stands down.

### Couplings you cannot abstract away, so document them

These are load-bearing and honest:

1. **PowerShell 7 and Windows-first.** Most of the repository is PowerShell 7; a shell port is a
   separate project. The Python part of the set -- the git-hook checkers, the leak gate and the one
   substrate module they share -- is stdlib-only and portable. Case-folding and process start-time
   reads degrade off Windows, and the doctor names that as a blind spot on every run.
2. **The client's session-record schema is a vendor contract**, see section 3. It can break under you.
3. **The `ccd_session_mgmt` MCP server is desktop-only.** Announce delivery depends on it and it is
   **absent on a plain CLI install**, where the hook still fires, still resolves peers, and then asks
   the model to call tools it does not have. The model will say so and nothing is delivered. On a CLI
   install, leave that hook uninstalled or create the OFF file. Nothing else in the repository depends
   on that MCP.
4. **`<git-common-dir>` as the state root.** Correct, deliberate, and not portable to a
   non-git-backed setup. Keep it, and keep its corollary in mind.
5. **Windows path case-insensitivity** in the folding rule. This has already broken once on a
   case-sensitive CI runner; see section 6.

---

## 8. The failure mode this whole design is guarding against

Every failure mode in this system is **byte-identical to success**.

A hook that is wired but resolves nothing prints the same output as a healthy hook with no peers. A
fence that could not read the registry returns the same empty list as a fence that read it and found
nobody. A gate whose helper files were not installed exits 0, exactly like a gate that saw nothing to
deny. A control that was merged but never installed is a source artefact with green tests.

That is why so much of this repository is receipts rather than logic: print what you scanned, count
what you examined, distinguish "found nothing" from "could not look", and name your blind spots on
every run. And it is why `bin/ccx-doctor.ps1` exists and is the first command to run: it does not read
settings to decide whether a control is live, it **fires each control on purpose and requires it to
refuse**, with a paired negative control so a refusal for the wrong reason is not counted as success.

Run it before you trust any of this.

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```
