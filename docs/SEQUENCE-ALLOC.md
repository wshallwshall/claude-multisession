# Sequence allocation

## TLDR/BLUF

**What this is.** `scripts/coord/alloc.ps1` and `scripts/hooks/seq_check.py`, which hand out "the next
free number" for a sequence -- decision records, issue headings, migration numbers -- so two sessions
cannot reach for the same one.

**Why you should care.** This is the one collision class every other control in this repository is
blind to. Two sessions each compute the same next number correctly, from their own point of view, and
both use it. Not for you if your repository maintains no numbered sequence.

**How to use it.** What a sequence *is* lives entirely in `ccx.config.json`. Decision records are the
worked example in `examples/sequence-adr/`, but nothing about the mechanism is specific to them. The
gate ships **unwired**, so read the doctor's status output before assuming it enforces anything.

---

Some numbers are a shared resource that git cannot see. Decision records named `0001-*.md`,
`0002-*.md`. Issues written as `## 58.` headings in one long file. Migration numbers, RFC numbers,
schema versions -- anything where "the next one" is a scalar that two people can reach for at the
same moment.

This is the one collision class that every other control in this repository is blind to, and it is
the reason `scripts/coord/alloc.ps1` and `scripts/hooks/seq_check.py` exist. Decision records are
used as the worked example throughout -- see `examples/sequence-adr/` -- but nothing about the
mechanism is specific to them. What a sequence *is* lives entirely in `ccx.config.json`.

---

## The defect

Two sessions each look for the next free number. Both compute the same answer -- correctly, from
their own point of view -- and both use it. They create **differently named** artifacts:
`0004-alpha.md` and `0004-beta.md`, or two `## 58.` headings sixteen hundred lines apart in the
same file.

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

---

## The two halves

Neither half is sufficient alone.

| Half | File | What it does | When it runs |
|---|---|---|---|
| **Allocator** | `scripts/coord/alloc.ps1` | Hands out a number nobody else can hold, by exclusively creating a file named after it | When you ask for a number |
| **Gate** | `scripts/hooks/seq_check.py` | Refuses a commit that adds a number which is already taken, unallocated, or missing from the index | `pre-commit`, and again in CI with `--ci` |

The allocator is a **test-and-set, not a read-modify-write**. It claims the number by exclusively
creating `<state-root>/alloc/<kind>/<number>.json` with `FileMode::CreateNew` and
`FileShare::None`; if a sibling session got there first, the create throws `IOException` and the loop
moves to the next number. That throw *is* the mutual exclusion.

A shared list you read, edit and write back is not an alternative. Measured on the repo this tooling
was developed in: eight concurrent PowerShell writers to one shared file lost **four** writes, with
no error raised anywhere. Eight concurrent allocator processes against the exclusive-create scheme
produced eight distinct numbers and zero collisions.

The registry lives beside the **shared object store** -- `<git-common-dir>/<prefix>-coord/alloc`,
resolved by `Get-CcxStateRoot` in `scripts/coord/_common.ps1` and by `state_root()` in
`scripts/hooks/_ccxconfig.py`. Every linked worktree of a clone sees the same allocations; a
different clone gets its own automatically; and nothing there can be swept into a commit by
`git add -A`.

**Numbers are never reclaimed.** An abandoned branch holds its number forever and the sequence
develops holes. That is deliberate: holes are free, collisions are not.

---

## Configuring a sequence

One key in `ccx.config.json`. Omit `sequences` entirely and both halves are inert -- the allocator
refuses with a message naming the file to edit, and the gate returns 0 without a word.

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

Both scripts validate this **before touching the registry**, and both name the file and the key in
every message. `indexFile` and `indexRowPattern` must be given together or not at all: half a
configuration silently drops a whole term from the floor, and a floor that is silently too low is
the exact failure the allocator exists to prevent.

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

```powershell
# take a number
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "Worktree gate"

# inspect the floor without spending anything
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -ShowFloor

# what does this worktree currently hold?
pwsh -NoProfile -File scripts/coord/alloc.ps1 -List
```

`-Kind` may be omitted when exactly one sequence is configured. With two or more it is required,
and the error lists the configured names -- the parameter is deliberately **not** a `ValidateSet`, so
the repo does not carry two lists of kinds that have to agree.

`-Title` is required for a real allocation. It is recorded in the claim so a sibling session running
`-List` can see what the number is for.

A successful allocation prints the number, the directory to put it in, the pattern the path must
match, a suggested filename, and a reminder to add the index row **in the same commit**. The claim
file records `number`, `kind`, `title`, `branch`, `worktree`, `claimed`, as UTF-8 with **no BOM** --
the Python gate reads it with `encoding="utf-8"` and a BOM makes `json.loads` raise.

---

## The floor, and why it ratchets

The floor is the maximum over four terms, then ratcheted against a persisted high-water mark:

| Term | Source | Catches |
|---|---|---|
| 1. Filenames, per ref | `git ls-tree` over `dir` for **HEAD, trunk, every `refs/heads` and every `refs/remotes`** | A number on any branch, published or not |
| 2. Index rows, per ref | `git cat-file --batch` over `<ref>:<indexFile>` | A number recorded in the index but not yet a file |
| 3. Working tree | The directory and the index file on disk | A draft written but committed nowhere |
| 4. Registry | `<state-root>/alloc/<kind>/*.json` | A number claimed but not yet written anywhere |

**Every ref, not just the trunk.** Reading only the published branch is precisely what re-issues
numbers that already exist on refs the published branch does not carry. They are invisible to the
sweep, so the allocator hands them out as free. The collision surfaces later as two
differently-named files that merged clean. A number that exists on *any* ref is taken.

Term 2 is batched for a reason. A `git show` per ref spawns one process each; measured on the repo
this tooling was developed in, that cost roughly 34 seconds on Windows where two `git cat-file`
processes did the same work in about 3. Most refs share the same blob, so de-duplicating by object
id collapses several hundred specs into far fewer reads.

### The ratchet

Every term above is derived from refs a routine cleanup can remove. **The sweep is only as good as
the refs this clone happens to hold.** Measured on the repo this tooling was developed in: the floor
computed over all refs was materially higher than the floor computed over origin's refs and local
heads alone. Numbers lived on remote-tracking refs for a remote that `git remote -v` no longer
listed. Drop those and the floor silently reverts to a lower value, and the allocator resumes
issuing numbers that are already in use -- no error, no signal.

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

Numbers are never reclaimed, so before `-ShowFloor` existed the only way to find out what the floor
could see was to **spend a number on the question**. That made the floor's own correctness the one
property nobody re-tested -- which is how it went an entire release reading two refs while its own
header promised all of them.

`-ShowFloor` prints the kind, the resolved trunk, the floor (with the computed value and the
high-water mark shown separately), **the paths it swept**, the number it would issue next, and the
watermark path -- and allocates nothing.

Two details make it trustworthy:

- **It names its sources, not just the number.** "Which paths did this sweep actually read" is the
  question every silent-narrowing bug turns on, and a bare integer cannot answer it. A floor looks
  identical whether it swept one path or two.
- **It cannot corrupt what it reads.** `Get-Floor -Peek` skips the high-water write. The first run
  of `-ShowFloor` against a deliberately planted number ratcheted that clone to a fabricated floor
  no later run could undo. An inspection that moves the thing it inspects is not an inspection.

One computation, two callers: `-ShowFloor` and a real allocation differ **only** by `-Peek`, so they
cannot report different numbers. They used to -- `-ShowFloor` returned before a guard every real
allocation ran, and printed a next number the tool would then refuse to issue. Anything added later
that can change the outcome belongs inside `Get-Floor` or above both branches, never in one of them.

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

That last property is the one that matters here. A `PreToolUse` gate reads tool *arguments*, so it
is blind to a shell redirect, `Set-Content`, `python -c`, a heredoc, an editor, or a subagent. The
commit hook sees all of them, because by then the bytes are in the index.

### What it checks

Per configured sequence:

1. An **added** file carrying number N must not reuse an N that already exists on trunk -- unless the
   index row for N names the new file as a declared companion. (One number, one row, two files is
   legal; the row itself names the companion. Only an *undeclared* reuse is a collision. The
   companion is matched with and without its extension, since an index row conventionally links the
   stem.)
2. An **added** number must have been allocated to *this worktree*. Local only -- see the mode
   asymmetry below.
3. An **added** number must have a row in the sequence's `indexFile`.
4. The index must not gain a **duplicate** row for one number.

### What it deliberately does not check

Anything about numbers already on trunk. Rule 3 applies only to files this change adds; rule 4 only
to duplicates this change introduces (duplicates already on the base are subtracted out).

> **Rule.** A gate that fails on pre-existing debt is a gate that gets uninstalled, and it takes the
> real protection with it when it goes.

For the same reason it reads the **staged tree** (`git show :path`), never the working tree. A gate
reading the working tree blocks every unrelated commit the moment you have an untracked
work-in-progress file in your checkout.

And it is **stdlib only, with no project import**. Most worktrees have no virtualenv and no project
install; a gate that skips because an import failed is worse than no gate, because it still looks
installed. The one shared import is its sibling `_ccxconfig.py`, and a failure to find it exits
non-zero with an explicit message rather than degrading to silence.

### Two rules that keep it honest

Both live in `_ccxconfig.git()` and both were paid for:

- **`encoding=` is required, not cosmetic.** `text=True` alone decodes with the locale default,
  which is cp1252 on a stock Windows box. Index and ledger files are routinely UTF-8, so the decode
  raised inside subprocess's reader thread, `proc.stdout` came back `None`, and the caller died on
  `findall(None)` -- blocking every commit that touched exactly the files the gate guards.
- **A non-zero git exit raises.** A bad ref, a missing path or an unfetched base must never read as
  "the file is empty", because an empty index parses as "no numbers taken" -- the false clean a
  collision gate must never emit. When the git wrapper swallowed non-zero exits, the added-files
  list came back `[]` and the gate reported PASS on every run where it could not see.

The one legitimate "absent from that ref" case gets its own explicit probe, `object_exists()`,
rather than a broad `except` that would also hide a genuinely broken ref.

Whatever it could not check, it prints -- pass or fail, on stderr. An unresolvable trunk means the
already-taken-on-trunk rule did not run, and it says so. A skip that prints nothing is
byte-identical to a clean run.

---

## Wiring the pre-commit hook

**Nothing in this repository installs it for you.** `scripts/coord/install-git-hooks.ps1` installs
the claim gate (`commit-msg`) and the push guard (`pre-push`), and *never writes `pre-commit`, at
all*. Two tools cannot both own that one file. A hook framework that finds a foreign hook there may
rename it and invoke it from its own shim, and that chain has failed on Windows and blocked every
commit in a repository until the shim was removed.

So the installer does the next best thing. Whenever `sequences` is configured, it prints in yellow
that the sequence gate is **not** installed by it, and that until you wire one, nothing at commit
time stops two sessions using the same number. `bin/ccx-doctor.ps1` goes further and checks: it reports
the control as **OFF**, with the reason, rather than omitting it. An absent gate looks exactly like
one that passed.

Wire it into whatever hook framework you already use:

```sh
# in your existing pre-commit hook, or as its own file if you own that slot
python scripts/hooks/seq_check.py || exit 1
```

Verify by receipt, not by presence:

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

The doctor reports whether any `pre-commit` in the resolved hooks directory invokes `seq_check`. It
separately fires a **read-only floor probe** at the allocator -- `-ShowFloor`, which never spends a
number -- so a broken allocator is caught without corrupting the sequence to find out.

---

## Modes are not symmetric, and saying so is the point

`--ci` re-runs the same rules against a freshly fetched trunk, which is what catches the **stale-base
collision**: each branch is internally consistent, and the duplicate only exists once both have
merged. It re-runs every rule but one.

**Rule 2 -- allocation ownership -- cannot run in CI.** It reads a per-clone registry inside the git
directory and compares a worktree path; a runner clones fresh and has neither, so the check would
return False for every item and nothing could ever merge. So ownership is enforced locally and never
in CI.

An earlier version ran the CI half of that rule anyway: it computed a set and discarded it, which
made it structurally incapable of failing while reading, in source, exactly like coverage.

> **Rule.** If a rule cannot run in a mode, name it as not running. Never leave it in place looking
> like coverage. A green CI on a numbered pull request is **not** evidence that the number was
> allocated to anybody.

The residual, stated plainly: after a `--no-verify` commit, a number belonging to another session's
**unmerged** branch can be taken with nothing objecting. The corruption then surfaces late -- but
loudly and recoverably -- when the second of the two merges.

CI mode also insists on a resolvable base. Locally, an unresolvable trunk downgrades to a printed
note; in CI it raises, because there the base comparison *is* the job and a base that does not
resolve is a workflow misconfiguration.

### If you wire the CI leg

Two things to get right, neither of which is obvious:

- **Do not gate the step on a "code changed" path filter.** A pull request that only adds a decision
  record *is* a docs-only change, so a `code == 'true'` condition makes the governance step skip on
  exactly the pull requests it exists to police. Path filters written for test suites invert the
  intent of a docs-governance check.
- **Ride it inside an already-required job** rather than adding a brand-new required context. A
  newly required check wedges every pull request opened before it existed.

Use a **two-dot** diff (`base HEAD`), not three-dot. On a pull request the checkout is typically the
merge commit, so HEAD already contains base and three-dot buys nothing -- while costing everything.
It resolves a merge base, the checkout is shallow, and two truncated histories routinely fail to
reach their common ancestor. Deepening to fix that is itself a race. A two-dot diff compares two
trees: no ancestry, no depth, nothing to race. And the three-dot failure was **silent** -- see the
raise-on-non-zero rule above.

---

## Ownership is only as real as your isolation

Rule 2 keys ownership on the **worktree** that holds the claim: `owns()` compares the claim's
`worktree` field, folded through `fold_path()`, against the current repo root.

That only discriminates because each session gets its own worktree. Measured on the repo this
tooling was developed in, the ownership rule was a **no-op** before worktree isolation was enforced.
Every co-tenant session authored in the same shared primary checkout, so every one of them mapped to
the same key. The check could not separate exactly the sessions it was written to separate.

> **Rule.** Check that your ownership key actually distinguishes the actors in practice, not merely
> in principle. Number allocation and worktree isolation are a pair -- the first is meaningless
> without the second making the key real.

The folding is shared deliberately: `fold_path()` in `_ccxconfig.py` and
`ConvertTo-CcxComparablePath` in `_common.ps1` must agree character for character, because each side
compares paths against records the other side wrote. If they fold differently, ownership silently
stops matching and the gate either refuses everything or grants everything.

---

## Two lessons from a guard that had to be removed

Both concern a rule that once sat in the allocator and is deliberately **not** in the shipped code.
They are worth knowing because the shape recurs.

**Two different maximums got conflated, and the allocator bricked on correct input.** A guard meant
to detect one band of a partitioned sequence encroaching on another read *the floor*, the maximum
over everything swept. The first legitimate entry filed in the upper band therefore made **every**
allocation in the repository throw a refusal.

There were two measurements, not one. The floor answers "what must I not re-issue?" and must include
every number from every band. The per-band maximum answers "how much runway does this band have?"
and must not.

The guard was not detecting a breach. It was detecting the partition being used exactly as designed.

> **Rule.** Name each measurement by the question it answers, then check which one every consumer
> reads. A guard that fires on correct input will be disabled, and it takes the real protection with
> it.

**A branch that cannot fire reads as protection and is worse than none.** The obvious repair was to
keep the refusal arm and make it unreachable. But once an entry exists at a number in the shared
band, it is indistinguishable in the published files from a legitimate entry at the same number --
both are just a number. A refusal arm would have to fire on correct input or never fire at all.
Detecting a real breach needed an input the repository did not have.

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
| The shims fail open with no python | Both Python-backed git hooks print to stderr and exit 0 when no interpreter is found. `install-git-hooks.ps1 -Status` and the doctor both report the interpreter, because that single condition turns the gates off everywhere at once while every file involved is still present. |
| Ownership is worktree-keyed | Where every session shares one checkout, it collapses to "somebody here allocated it". |
| Two sessions can still build the same thing under two *different* numbers | Nothing structural sees duplicated work. That is what claims and announce are for -- see `docs/COORDINATION.md`. |
| The high-water ratchet cannot restore history | It stops re-issue. The commits those refs pointed at are still gone. |
| Numbers are never reclaimed | Sequences develop holes. Accepted by design. |

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
