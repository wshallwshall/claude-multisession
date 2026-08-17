# Sequence allocation

## TLDR/BLUF

**What this is.** Two scripts that hand out the next free number in a sequence -- decision records,
issue headings, migration numbers. `scripts/coord/alloc.ps1` issues a number nobody else can hold.
`scripts/hooks/seq_check.py` refuses a commit that reuses one.

**Why you should care.** Two sessions can take the same number, name their files differently, and
git merges both with no conflict. This is the one collision class every other control here is blind
to.

Not for you if your repository maintains no numbered sequence. Not yet for you if your sessions
share one checkout: the ownership rule is keyed to a worktree, so it collapses to "somebody here
allocated it" ([Worktrees](WORKTREES.md)).

**What it needs first.** These scripts vendored into the repository you govern, `pwsh` 7.3+, and a
`python` on `PATH`. Even `bin/ccx-doctor.ps1` refuses to start below 7.3.
[Install](INSTALL.md) is the procedure.

**How to use it.** Start at [Configuring a sequence](#configuring-a-sequence): one key in
`ccx.config.json` defines a sequence, and both scripts are inert without it. The gate ships
**unwired**, so run the doctor before assuming it enforces anything.

---

Some numbers are a shared resource git cannot see. "The next one" is a single value two sessions can
reach for at once:

- Decision records named `0001-*.md`, `0002-*.md`.
- Issues written as `## 58.` headings in one file.
- Migration numbers, RFC numbers, schema versions.

**The gate covers the first and third shapes, not the second.** Rules 1 to 3 iterate added *files*
whose repo-relative path matches `filePattern`. A number living inside one file never changes that
path.

So for a headings-in-one-file sequence, only rule 4 can fire. The allocator still hands out unique
numbers there; nothing at commit time defends them.

`examples/sequence-adr/` is the worked example, and nothing in the mechanism is specific to decision
records. A sequence is defined entirely in `ccx.config.json`.

---

## The defect

Two sessions each look for the next free number. Both get the same answer, correctly, from their own
point of view. Both use it, and they create **differently named** artifacts: `0004-alpha.md` and
`0004-beta.md`, or two `## 58.` headings sixteen hundred lines apart in one file.

Git merges both **cleanly**. There is no textual conflict, because the two sessions never touched
the same bytes.

| Control you might expect to catch it | Why it does not |
|---|---|
| A worktree per session | The collision is *between* worktrees. Isolation is what makes it possible. |
| A file lock | Different filenames. Nothing is contended. |
| `git merge-tree` / a merge dry-run | It merges clean by construction. That is the whole problem. |
| Code review | Both diffs are individually correct. |
| A green CI on each branch | Each branch is internally consistent. The duplicate exists only after the *second* merge. |

Measured on the repo this tooling was developed in, this fired three separate times. Each time the
symptom was recorded as "numbers churn, recompute before merging" and a workaround was written down.
It is not churn. It is a concurrency defect, and the workaround is the bug.

> **Rule.** Never compute the next free number by scanning for a maximum and adding one. Allocate it
> atomically, and enforce the allocation at commit time. When a symptom keeps recurring and the
> remedy keeps being "redo it by hand", ask whether you are looking at a race.

**It fires in sequences the allocator does not cover, too.** Measured 2026-08-11: a session checked
that a rule identifier was free, composed the entry, then wrote it. A peer had taken that number in
the gap, because the check and the write were never one operation.

A series spanning two clones is the case this allocator cannot take. Its state root is per-clone by
design, so two repositories issuing from one series share no allocator, and the rule identifiers in
[house style](HOUSE-STYLE.md) sit in exactly that position.

**The same shape ships in third-party tooling.** [spec-kit](https://github.com/github/spec-kit), read
at `main` on 2026-08-12, numbers a feature by scanning spec directories for the highest
3-or-more-digit prefix and adding one. No lock, no atomic claim, in the script tree that was read.

An opt-in `--timestamp` mode substitutes a `YYYYMMDD-HHMMSS` prefix and sidesteps the sequence. The
default path is the unlocked scan, and the explicit `--number` path auto-increments on collision with
no atomic protection either.

Re-verified against `specify-cli` 0.16.4 on 2026-08-15: `Get-HighestNumberFromSpecs` still takes the
highest prefix and adds one, under no lock. The rest of that framework is in
[Spec Kit 0.16.4 for a KORUS build](FRAMEWORK-spec-kit.md).

**Two projects reached this layout independently.** `examples/sequence-adr/` numbers records at
`docs/adr/NNNN-slug.md`, flat and project-scoped. `panaversity/spec-kit-plus`, a fork adding the ADR
command upstream lacks, stores them at `history/adr/NNNN-slug.md`.

Same shape, different tree. The fork settles the scope question the same way and leaves the
concurrency one open: it auto-numbers, and nothing in it allocates atomically or gates the index.

### The index is gated, and that is the auditability half

`seq_check.py` refuses four things: a number already taken, a number never allocated, a number
missing from the index, and a **duplicate** index row for one number. The third reads as pedantry
until the record is evidence rather than notes.

Whoever reviews a set of decisions reads the index. A record that exists and is unlisted is one
nobody assessed, and its absence never announces itself.

So the gate is what makes the set claimable. Without it, "these are the decisions" is an assertion
about a directory nobody enumerated.

That is the shape a citation count takes when reported without its filter, measured in
[Spec Kit 0.16.4 for a KORUS build](FRAMEWORK-spec-kit.md).

---

## The two halves

Neither half is sufficient alone.

| Half | File | What it does | When it runs |
|---|---|---|---|
| **Allocator** | `scripts/coord/alloc.ps1` | Hands out a number nobody else can hold, by exclusively creating a file named after it | When you ask for a number |
| **Gate** | `scripts/hooks/seq_check.py` | Refuses a commit that adds a number which is already taken, unallocated, or missing from the index | `pre-commit`, and again in CI with `--ci` |

**Test-and-set, not read-modify-write.** The allocator claims a number by creating
`<state-root>/alloc/<kind>/<number>.json` with `FileMode::CreateNew` and `FileShare::None`. If a
sibling got there first, the create throws `IOException` and the loop moves on. That throw *is* the
mutual exclusion.

A read-modify-write on a shared list is not an alternative. Measured on the repo this tooling was
developed in: eight concurrent PowerShell writers to one file lost **four** writes with no error
raised. Eight concurrent allocator processes produced eight distinct numbers and zero collisions.

The registry lives in `<git-common-dir>/<prefix>-coord/alloc`, resolved by `Get-CcxStateRoot` in
`scripts/coord/_common.ps1` and by `state_root()` in `scripts/hooks/_ccxconfig.py`. Every linked
worktree sees the same allocations, another clone gets its own, and `git add -A` cannot reach it.

**Numbers are never reclaimed.** An abandoned branch holds its number forever and the sequence
develops holes. That is deliberate: holes are free, collisions are not.

---

## Configuring a sequence

**The goal.** Tell both scripts what counts as a number here: which directory holds it, what its
filename looks like, and where its index row lives.

**What to do.** Add one `sequences` key to `ccx.config.json`. This is the decision-record sequence
from `examples/sequence-adr/`:

```json
{
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

| Key | Required | Meaning |
|---|---|---|
| `dir` | yes | The directory swept for existing numbers, repo-relative, forward slashes |
| `filePattern` | yes | Regex over the repo-relative path. **Group 1 must capture the number.** |
| `pad` | no | Zero-padding width. `0` or absent means none |
| `indexFile` | no | An index/table file that must carry a row per number |
| `indexRowPattern` | with `indexFile` | Regex recognizing one row. **Group 1 must capture the number.** |

**What happens next.** Both scripts validate this key **before touching the registry**, and name the
offending key in what they print.

**Most per-sequence errors do not name the config file.** Discovery walks upward and `CCX_CONFIG` can
redirect it, so the file you are editing may not be the one that loaded. Run the doctor to see which
path it resolved.

Omit `sequences` entirely and both scripts are inert. The allocator refuses with a message naming
the file to edit, and the gate returns 0 without a word.

`indexFile` and `indexRowPattern` must be given together **or not at all**. Half a configuration
silently drops a whole term from the floor. A floor that is **silently** too low is the **exact**
failure the allocator exists to prevent.

**Only the allocator enforces both directions.** The gate raises on `indexFile` without
`indexRowPattern`. The reverse it accepts, then skips rules 3 and 4 and exits 0.

The gate is the half you wire by hand, so that is exactly the silent half-configuration this rule
exists to prevent. Check both keys, or neither.

### `indexRowPattern` is compiled multiline, and that was once a silent hole

`alloc.ps1` builds it with `RegexOptions::Multiline`; `seq_check.py` compiles it with `re.M`. Without
that flag `^` anchors to the start of the *string*, not of each line.

This mattered because the two terms that use the pattern feed it differently. The all-refs term
feeds it one line at a time, where it matched and looked correct. The working-tree term feeds it the
whole file as one string, where `^` could never match past the first line.

Measured on the repo this tooling was developed in: without `Multiline` the working-tree term found
**none** of the index's rows. So the term that exists to catch a number written but committed
*nowhere* had been finding nothing since the day it was written.

The all-refs term hid it, by covering every number committed somewhere -- which is every case except
the one that term is for.

> **Rule.** When two terms of the same computation feed one matcher different shapes of input, the
> stricter shape is the one to test. A term that is subsumed by a broader term in the common case
> will not announce that it has stopped working.

---

## Using it

**The goal.** Get a number that is yours, or read the **floor** without spending one. The floor is
the highest number already taken anywhere this clone can see.

**Stand in the repository you are allocating in.** The allocator resolves the config and the git
repository from your current directory, never from its own location.

The relative paths below therefore assume the vendored layout, where the two are one checkout. From a
separate tooling clone, `Set-Location` to the target and give the script an absolute path.

**Fetch before you allocate.** The floor sweeps remote-tracking refs, so a peer's pushed number is
invisible until you have it: `git fetch origin --prune`.

**What to do.**

```powershell
# take a number
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "Worktree gate"

# inspect the floor without spending anything
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -ShowFloor

# what does this worktree currently hold?
pwsh -NoProfile -File scripts/coord/alloc.ps1 -List
```

**What happens next.** A **successful** allocation prints the number, the directory to put it in, and
the pattern the path must match.

Two more lines are conditional: a suggested filename, when the title slugs to something non-empty;
and an index-row reminder, only when the sequence has an `indexFile`. Fewer lines is not a partial
run.

The two parameters:

- `-Kind` may be omitted when exactly one sequence is configured. With two or more it is required,
  and the error lists the configured names. The parameter is deliberately **not** a `ValidateSet`,
  so the repo does not carry two lists of kinds that have to agree.
- `-Title` is required for a real allocation. It is recorded in the claim, so a sibling session
  running `-List` can see what the number is for.

The claim records `number`, `kind`, `title`, `branch`, `worktree` and `claimed`, as UTF-8 with **no
BOM**: the gate reads it with `encoding="utf-8"`, and a BOM makes `json.loads` raise.

---

## The floor, and why it ratchets

The allocator issues the first number above the floor, so the floor is what decides whether a number
is free. It is the maximum over four terms, then ratcheted against a persisted high-water mark:

| Term | Source | Catches |
|---|---|---|
| 1. Filenames, per ref | `git ls-tree` over `dir` for **HEAD, trunk, every `refs/heads` and every `refs/remotes`** | A number on any branch, published or not |
| 2. Index rows, per ref | `git cat-file --batch` over `<ref>:<indexFile>` | A number recorded in the index but not yet a file |
| 3. Working tree | The directory and the index file on disk | A draft written but committed nowhere |
| 4. Registry | `<state-root>/alloc/<kind>/*.json` | A number claimed but not yet written anywhere |

**Every ref, not just the trunk.** Numbers that exist on refs the published branch does not carry
are invisible to a trunk-only sweep, so the allocator hands them out as free. The collision surfaces
later as two differently-named files that merged clean. A number on *any* ref is taken.

Term 2 is batched. One `git show` process per ref cost roughly 34 seconds on Windows, measured on
the repo this tooling was developed in. Two `git cat-file` processes did it in about 3: most refs
share a blob, so de-duplicating by object id collapses several hundred specs into far fewer reads.

### The ratchet

**The sweep only sees this clone's refs.** Measured on the repo this tooling was developed in, the
all-refs floor sat well above origin and local heads: those numbers lived on remote-tracking refs
for a remote no longer in `git remote -v`.

Drop those refs and the floor silently reverts, so the allocator re-issues numbers already in use --
no error, no signal.

So the floor is persisted to `<state-root>/alloc/<kind>/.floor-highwater` and **may rise but never
fall**. When the computed floor comes in below the mark, `alloc.ps1` prints a loud NOTE naming both
numbers and telling you to re-fetch before trusting any number-space reasoning in that clone.

| Operation | Verdict |
|---|---|
| `git fetch origin --prune` | **Safe** -- prunes only `refs/remotes/origin/*`, and is what you should run before allocating |
| `git remote prune <other>` / `git remote remove <other>` | **Dangerous** -- deletes a block of remote-tracking refs |
| Deleting remote-tracking refs by hand | **Dangerous** |
| Aggressive `gc` / `reflog expire` dropping unreachable objects | **Dangerous** |

The ratchet is a backstop, not a substitute for the refs: it keeps the allocator from re-issuing,
but the history those refs pointed at is still gone.

### Allocation is a one-way door, so it ships a read-only probe

Numbers are never reclaimed, so before `-ShowFloor` the only way to test the floor was to **spend a
number on the question**. That made the floor's correctness the one property nobody re-tested. It
went an entire release reading two refs while its header promised all of them.

`-ShowFloor` allocates nothing and prints:

- the kind, and the resolved trunk;
- the floor, with the computed value and the high-water mark shown separately;
- **the paths it swept**;
- the number it would issue next, and the watermark path.

Two details make it trustworthy:

- **It names its sources, not just the number.** "Which paths did this sweep actually read" is the
  question every silent-narrowing bug turns on, and a bare integer cannot answer it. A floor looks
  identical whether it swept one path or two.
- **It cannot corrupt what it reads.** `Get-Floor -Peek` skips the high-water write. The first run
  of `-ShowFloor` against a deliberately planted number ratcheted that clone to a fabricated floor
  no later run could undo. An inspection that moves the thing it inspects is not an inspection.

`-ShowFloor` and a real allocation are one computation that differs **only** by `-Peek`, so they
cannot report different numbers. They once did: `-ShowFloor` returned before a guard every real
allocation ran. Anything that can change the outcome belongs inside `Get-Floor` or above both
branches.

> **Rule.** Any irreversible allocator needs a dry run that reports its own inputs, and the dry run
> must run the same code path as the real thing.

---

## The gate

`scripts/hooks/seq_check.py` runs at `pre-commit`, and again in CI with `--ci`.

### Why a git hook, and why the shared hooks directory

`.git/hooks` lives in the **common** git directory, which every linked worktree shares. One file
there:

- reaches every worktree the instant it is written -- no branch, no merge, no propagation lag;
- survives a branch switch in any of them, because it sits outside every working tree;
- and **sees every write route**, because it inspects the staged tree rather than a tool call.

**That third property is the one that matters here.** A `PreToolUse` hook reads a tool call's
*arguments* before it runs, so it is blind to a shell redirect, `Set-Content`, `python -c`, a
heredoc, an editor, or a subagent. The commit hook sees all of them: by then the bytes are staged.

### What it checks

Per configured sequence:

1. An **added** file carrying number N must not reuse an N already on trunk, unless the index row
   for N names the new file as a declared companion. Only an *undeclared* reuse is a collision. The
   companion is matched with and without its extension, since an index row links the stem.
2. An **added** number **not already on trunk** must have been allocated to *this worktree*. The
   check sits behind rule 1, so a declared companion at an existing number is not asked for a claim.
   Local only -- see the mode asymmetry below.
3. An **added** number must have a row in the sequence's `indexFile`.
4. The index must not gain a **duplicate** row for one number.

### What it deliberately does not check

Anything about numbers already on trunk. Rule 3 applies only to files this change adds; rule 4 only
to duplicates this change introduces (duplicates already on the base are subtracted out).

**And one it does not check by accident: a rename onto a taken number.** Both modes list added files
with `--diff-filter=A`, which drops git's `R` entries.

So `git mv docs/adr/0009-foo.md docs/adr/0004-bar.md` presents no added path, and rules 1 to 3 never
run on `0004`. Reviewing renames in a numbered directory is still yours.

> **Rule.** A gate that fails on pre-existing debt is a gate that gets uninstalled, and it takes the
> real protection with it when it goes.

For the same reason it reads the **staged tree** (`git show :path`), never the working tree. A gate
reading the working tree blocks every unrelated commit the moment you have an untracked
work-in-progress file in your checkout.

It is **stdlib only, with no project import**. Most worktrees have no virtualenv, and a gate that
skips because an import failed is worse than no gate: it still looks installed. The one shared
import is its sibling `_ccxconfig.py`. Failing to find it exits non-zero with an explicit message.

### Two rules that keep it honest

Both live in `_ccxconfig.git()` and both were paid for:

- **`encoding=` is required.** `text=True` alone decodes with the locale default, cp1252 on stock
  Windows. Index files are routinely UTF-8, so the decode raised in subprocess's reader thread.
  `proc.stdout` came back `None`, the caller died on `findall(None)`, and the commits it guards were
  blocked.
- **A non-zero git exit raises.** A bad ref or an unfetched base must never read as an empty file,
  because an empty index parses as "no numbers taken". When the wrapper swallowed non-zero exits,
  the added-files list came back `[]` and the gate reported PASS on every run where it could not
  see.

The one legitimate "absent from that ref" case gets its own explicit probe, `object_exists()`,
rather than a broad `except` that would also hide a genuinely broken ref.

Whatever it could not check, it prints -- pass or fail, on stderr. An unresolvable trunk means the
already-taken-on-trunk rule did not run, and it says so. A skip that prints nothing is
byte-identical to a clean run.

---

## Wiring the pre-commit hook

**No installer here writes it.** `scripts/coord/install-git-hooks.ps1` writes `commit-msg` and
`pre-push`, and *never `pre-commit`*. Two tools cannot own one file, and a foreign hook renamed
behind a framework's shim has failed on Windows, blocking every commit until the shim was removed.

Whenever `sequences` is configured, the installer prints in yellow that it does **not** install the
gate. Until you wire one, nothing at commit time stops two sessions using the same number.
`bin/ccx-doctor.ps1` reports it as **OFF**, with the reason: an absent gate looks like one that
passed.

**The goal.** Have something at commit time refuse a number that is already taken, never allocated,
or missing from the index.

**What to do.** Add one line to whatever hook framework you already use:

```sh
# in your existing pre-commit hook, or as its own file if you own that slot
python scripts/hooks/seq_check.py || exit 1
```

**That path resolves from the repository root, so it needs the vendored layout.** A pre-commit hook
runs with the working tree's top as its current directory.

Where `scripts/` is not committed in the governed repo, python cannot open the file -- and `|| exit 1`
turns that into a refusal of **every** commit:

<!-- no-copy -->
```text
python.exe: can't open file '<repo>\scripts\hooks\seq_check.py': [Errno 2] No such file or directory
```

Read that as "the hook cannot find the gate", not as the gate refusing something. Use an absolute
path to the gate if your layout keeps the scripts elsewhere.

**With no python at all it fails closed, not open.** This gate is behind no `/bin/sh` shim, unlike the
claim gate and the push guard, so a missing interpreter makes the shell return non-zero and `exit 1`
blocks the commit. That is the opposite direction from the two installed hooks.

**What happens next.** Check it, and know what the check is worth:

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-govern>
```

**The doctor greps, it does not run the gate.** It matches the literal text `seq_check` in the one
file named `pre-commit` in the resolved hooks directory.

So it reports `OK` for a commented-out line, a wrong relative path, or a non-executable hook. And it
reports `OFF` when you wired the call through a framework, whose generated `pre-commit` only calls
the framework. Drive a real commit to prove it.

It separately fires a **read-only floor probe** at the allocator, `-ShowFloor`, which never spends a
number. A broken allocator is caught without corrupting the sequence to find out.

---

## Modes are not symmetric, and saying so is the point

`--ci` re-runs the same rules against a freshly fetched trunk. That catches the **stale-base
collision**: each branch is internally consistent, and the duplicate exists only once both have
merged. It re-runs every rule but one.

**Rule 2 -- allocation ownership -- cannot run in CI.** It reads a per-clone registry inside the git
directory and compares a worktree path. A runner clones fresh and has neither, so the check would
return False for every item and nothing could ever merge.

An earlier version ran the CI half of that rule anyway. It computed a set and discarded it, which
made it structurally incapable of failing while reading, in source, exactly like coverage.

> **Rule.** If a rule cannot run in a mode, name it as not running. Never leave it in place looking
> like coverage. A green CI on a numbered pull request is **not** evidence that the number was
> allocated to anybody.

The residual, stated plainly: after a `--no-verify` commit, a number belonging to another session's
**unmerged** branch can be taken with nothing objecting. The corruption surfaces late, loudly and
recoverably, when the second of the two merges.

CI mode also insists on a resolvable base. Locally, an unresolvable trunk downgrades to a printed
note. In CI it raises: there the base comparison *is* the job, and a base that does not resolve is a
workflow misconfiguration.

### If you wire the CI leg

Three things to get right, none of them obvious:

- **Do not gate the step on a "code changed" path filter.** A pull request that only adds a decision
  record *is* a docs-only change. A `code == 'true'` condition makes the governance step skip on
  exactly the pull requests it exists to police.
- **Ride it inside an already-required job** rather than adding a brand-new required context. A
  newly required check wedges every pull request opened before it existed.
- **Use a two-dot diff** (`base HEAD`), not three-dot. On a pull request the checkout is the merge
  commit, so HEAD contains base. Three-dot resolves a merge base, and two shallow histories fail to
  reach their common ancestor. Deepening to fix that is itself a race, and the failure was
  **silent**.

---

## Ownership is only as real as your isolation

Rule 2 keys ownership on the **worktree** that holds the claim: `owns()` compares the claim's
`worktree` field, folded through `fold_path()`, against the current repo root.

That only discriminates because each session gets its own worktree. Measured on the repo this
tooling was developed in, the ownership rule was a **no-op** before worktree isolation was enforced.
Every co-tenant session authored in the same primary checkout, so all of them mapped to one key.

> **Rule.** Check that your ownership key actually distinguishes the actors in practice, not merely
> in principle. Number allocation and worktree isolation are a pair -- the first is meaningless
> without the second making the key real.

`fold_path()` in `_ccxconfig.py` and `ConvertTo-CcxComparablePath` in `_common.ps1` must agree
character for character, because each side compares paths against records the other wrote. Fold
differently and ownership silently stops matching, so the gate refuses or grants everything.

---

## Two lessons from a guard that had to be removed

Both concern a rule that once sat in the allocator and is deliberately **not** in the shipped code.
They are worth knowing because the shape recurs.

**Two different maximums got conflated, and the allocator bricked on correct input.** A guard meant
to detect one band of a partitioned sequence encroaching on another read *the floor*, the maximum
over everything swept. The first legitimate entry in the upper band made **every** allocation fail.

There were two measurements, not one. The floor answers "what must I not re-issue?" and must include
every number from every band. The per-band maximum answers "how much runway does this band have?"
and must not.

The guard was not detecting a breach. It was detecting the partition being used exactly as designed.

> **Rule.** Name each measurement by the question it answers, then check which one every consumer
> reads. A guard that fires on correct input will be disabled, and it takes the real protection with
> it.

**A branch that cannot fire reads as protection and is worse than none.** Once an entry exists at a
number in the shared band, it is indistinguishable from a legitimate one. The arm would have to fire
on correct input, or never at all, and detecting a breach needed an input the repository lacked.

> **Rule.** Remove a branch that cannot fire; do not leave it dormant. Replace it with something the
> data can actually support -- a warning at a threshold measured on the band where the other band's
> numbers cannot distort it -- and say in the docs what is no longer detected.

---

## Limits

Stated plainly, because each one is a hole somebody will otherwise assume is covered.

| Limit | Consequence |
|---|---|
| `git commit --no-verify` bypasses the gate | This is a guardrail against accident, not a security boundary. The `--ci` run is the backstop. |
| Ownership is never checked in CI | A green CI is not evidence the number was allocated. |
| No installer writes `pre-commit` | Until you wire it, nothing at commit time stops two sessions using the same number. The doctor reports this as OFF, not as absent. |
| This gate fails **closed** with no python | Behind no `/bin/sh` shim, so a missing interpreter blocks every commit. The two *installed* git hooks go the other way: their shims exit 0. The doctor reports the interpreter. |
| `sequences` also arms the claim gate | `claim_check.py` takes its `<KIND>` tokens from the configured sequence names, so a commit subject naming an unclaimed item is refused too ([Coordination](COORDINATION.md)). |
| Ownership is worktree-keyed | Where every session shares one checkout, it collapses to "somebody here allocated it". |
| Two sessions can still build the same thing under two *different* numbers | Nothing structural sees duplicated work. That is what claims and announce are for -- see [coordination](COORDINATION.md). |
| The high-water ratchet cannot restore history | It stops re-issue. The commits those refs pointed at are still gone. |
| Numbers are never reclaimed | Sequences develop holes. Accepted by design. |
| A series shared across two clones cannot be allocated here | The state root is per-clone by design, so two repositories issuing from one series share no allocator. The rule identifiers in `docs/HOUSE-STYLE.md` are in that state, and the control there is a dated table rather than a gate. |

---

## Files

| Path | Role |
|---|---|
| `scripts/coord/alloc.ps1` | The allocator: floor sweep, high-water ratchet, atomic claim, `-ShowFloor`, `-List` |
| `scripts/hooks/seq_check.py` | The gate: four rules, `pre-commit` and `--ci` modes |
| `scripts/hooks/_ccxconfig.py` | Config discovery, the raising git runner, path folding -- shared by the Python hooks |
| `scripts/coord/_common.ps1` | The PowerShell counterpart: `Get-CcxConfig`, `Get-CcxStateRoot`, `Get-CcxTrunk`, `ConvertTo-CcxComparablePath` |
| `scripts/coord/install-git-hooks.ps1` | Installs the claim gate and push guard; reports that the sequence gate is *not* installed |
| `bin/ccx-doctor.ps1` | Reports the sequence gate by receipt, and probes the allocator read-only |
| `ccx.config.json` | The `sequences` key -- the only place a sequence is defined |
| `examples/sequence-adr/` | The worked configuration: a decision-record sequence, end to end |
| `examples/ledger_check.annotated.py` | The original gate this was distilled from, comments intact. **Not wired, not installed.** |
