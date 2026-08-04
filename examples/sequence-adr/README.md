# Worked example: a decision-record sequence

A complete, copyable configuration for one shared number space -- decision records named
`docs/adr/0001-*.md`, indexed by a table in `docs/adr/README.md`.

Nothing here is special to decision records. It is one filled-in instance of the mechanism described
in [`docs/SEQUENCE-ALLOC.md`](../../docs/SEQUENCE-ALLOC.md); swap the four strings and it describes
migrations, RFCs, or any other sequence git cannot see.

| File | What it is |
|---|---|
| `ccx.sequences.json` | The `sequences` block, ready to paste into `ccx.config.json` |
| `index-row-format.md` | The index table this configuration expects, and the regex that recognises a row |

---

## 1. Configure

Merge `ccx.sequences.json` into the `ccx.config.json` at your repository root. It is one top-level
key:

```json
{
  "prefix": "ccx",
  "trunk": "auto",
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

Read the four strings as one sentence: *numbers live under `docs/adr`; a file belongs to the
sequence when its repo-relative path matches `filePattern`, whose group 1 is the number; numbers are
written four digits wide; and every number must also appear as a row in `docs/adr/README.md`
recognised by `indexRowPattern`, whose group 1 is again the number.*

Two mistakes the loaders reject up front, rather than half-way through a sweep:

- a `filePattern` or `indexRowPattern` with **no capturing group** -- there would be nothing to read
  the number out of;
- `indexFile` **without** `indexRowPattern`, or the reverse. Half a configuration silently drops a
  whole term from the allocator's floor, and a floor that is silently too low is the one failure the
  allocator exists to prevent.

Patterns are matched against **repo-relative, forward-slash** paths, which is what git reports. Write
them that way even on Windows.

---

## 2. Create the directory and the index

```text
docs/
  adr/
    README.md          <- the index table (see index-row-format.md)
    0001-....md        <- one file per number
```

The index file may start out with only its header row. The gate reads whatever is there, and treats
"no index file yet" as an empty index rather than an error -- a branch that predates the index's
publication is a legitimate state, probed for explicitly rather than inferred from a git failure.

---

## 3. Allocate

```powershell
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "Worktree gate"
```

```text
ALLOCATED adr 0007
  place it under : docs/adr/
  path must match: ^docs/adr/(\d{4})-[^/]+\.md$
  suggested name : docs/adr/0007-worktree-gate.<ext>
  index          : add its row to docs/adr/README.md in the SAME commit (the sequence gate checks).
  claimed by     : C:\src\project-wt-feature [feature/worktree-gate]
```

`-Kind adr` may be omitted while `adr` is the only configured sequence. `-Title` is required: it is
stored in the claim so a sibling session running `-List` can see what the number is being used for.

The claim is a single file -- `<git-common-dir>/ccx-coord/alloc/adr/0007.json` -- created
**exclusively**. That create is the mutual exclusion: if a sibling session got there first it throws
and the allocator moves to `0008`. Nothing is read-modify-written, so nothing can be lost.

Inspect without spending a number:

```powershell
pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -ShowFloor
```

```text
kind      : adr
trunk     : origin/main
floor     : 6  (computed 6, high-water 6)
  refs swept: 14 (HEAD + trunk + refs/heads + refs/remotes)
  filenames : docs/adr (pattern ^docs/adr/(\d{4})-[^/]+\.md$, all refs)
  index rows: docs/adr/README.md (pattern ^\|\s*\[(\d{4})\], all refs, 3 distinct blobs)
  working tree: docs/adr + docs/adr/README.md
  registry  : C:\src\project\.git\ccx-coord\alloc\adr
next      : 0007
watermark : C:\src\project\.git\ccx-coord\alloc\adr\.floor-highwater

Read-only: nothing was allocated.
```

Read the source lines, not just the number. A floor of 6 looks identical whether it swept every ref
or only one, and "which paths did this actually read" is the question every silently-narrowed sweep
turns on.

Run `git fetch origin --prune` before allocating. It is the one ref operation that is safe for the
floor.

---

## 4. Write the file and the row in one commit

```text
docs/adr/0007-worktree-gate.md      (added)
docs/adr/README.md                  (one row added)
```

Both, in the same commit. The gate's rule 3 fires on an added file whose number has no row in the
index -- an entry that is not in the index is invisible, and a row lost to a tail-append conflict
shows up as a *dropped row* rather than as a conflict, so nothing else would report it.

---

## 5. What the gate refuses

With `scripts/hooks/seq_check.py` wired into `pre-commit` (no shipped installer writes that file --
see [`docs/SEQUENCE-ALLOC.md`](../../docs/SEQUENCE-ALLOC.md)), each of these is blocked, with the
reason and the fix printed:

| You did | It says |
|---|---|
| Added `0004-something.md` when `0004-other.md` is already on trunk | `adr 0004 already exists on origin/main as 0004-other.md` |
| Added `0007-...md` without allocating it | `adr 0007 was not allocated to this worktree` -- and names the claim file it looked for |
| Added the file but not the index row | `adr 0007 (0007-worktree-gate.md) has no row in docs/adr/README.md` |
| Added a second row for `0007` | `duplicate index row(s) in docs/adr/README.md: ['0007']` |

One deliberate exception: reusing a number is **legal** when the index row for that number names the
new file as a companion. One number, one row, two files. The row is matched with and without the
extension, since an index row conventionally links a file by its stem.

And one deliberate non-check: nothing about numbers already on trunk. Rule 3 applies only to files
this change adds, rule 4 only to duplicates this change introduces. A gate that fails on
pre-existing debt gets uninstalled.

---

## 6. Verify it is actually on

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

The doctor reports the sequence gate as `OK` only when a `pre-commit` in the resolved hooks
directory actually invokes `seq_check`; when sequences are configured and nothing is wired it prints
`OFF` **with the reason**, because an absent gate looks exactly like one that passed. It also fires a
read-only floor probe at the allocator -- proving the allocator runs without spending a number on the
question.

---

## Adapting this to another sequence

| Change | To |
|---|---|
| `dir` | wherever the files live, repo-relative |
| `filePattern` | a regex over the repo-relative path, group 1 = the number |
| `pad` | the digit width, or drop the key for unpadded numbers |
| `indexFile` / `indexRowPattern` | your index, or drop **both** if the sequence has none |

Add a second entry under `sequences` and `-Kind` stops being optional; the allocator lists the
configured names on a miss rather than restating them in a `ValidateSet` that would then have to be
kept in step with the config.

### One shape this does not fully cover

A sequence whose members are **headings inside a single file** -- `## 58.` in one long list -- is
only partly served. The allocator handles it: configure that file as the `indexFile` with a row
pattern like `^## (\d+)\.` and the floor sweeps every heading on every ref, so numbers are still
handed out uniquely. The gate, however, keys rules 1 to 3 on **added files**, so for a
headings-in-one-file sequence only the duplicate-row rule applies. `filePattern` is still required
and must still be a valid capturing regex.

That is a real gap, not a configuration trick: if you need per-entry enforcement, give each entry its
own file.
