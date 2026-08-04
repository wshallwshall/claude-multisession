# The index and its row pattern

The sequence in `ccx.sequences.json` declares an index:

```json
"indexFile":       "docs/adr/README.md",
"indexRowPattern": "^\\|\\s*\\[(\\d{4})\\]"
```

This file describes the table that pattern expects, and the handful of properties the pattern must
have. Both the allocator (`scripts/coord/alloc.ps1`) and the gate (`scripts/hooks/seq_check.py`)
read the index through this one regex, so it is worth getting right once.

---

## The table

`docs/adr/README.md`:

```markdown
# Decision records

| #                                    | Title                       | Status   | Date       |
|--------------------------------------|-----------------------------|----------|------------|
| [0001](0001-record-decisions.md)     | Record decisions            | Accepted | 2026-01-14 |
| [0002](0002-one-file-per-decision.md)| One file per decision       | Accepted | 2026-01-21 |
| [0003](0003-trunk-based-branching.md)| Trunk-based branching       | Accepted | 2026-02-03 |
```

`^\|\s*\[(\d{4})\]` reads: at the start of a line, a table pipe, optional whitespace, then a
bracketed four-digit number. Group 1 is the number. Everything after it -- title, status, date, extra
columns -- is your business, not the tooling's.

Rows may be appended in any order. Nothing asserts sort order, because a corpus legitimately violates
it and a gate that fails on that gets uninstalled.

---

## Four properties the pattern must have

| Property | Why |
|---|---|
| **Exactly one capturing group, around the number** | It is how both tools read the number. A pattern with no group is rejected at load, before anything is swept. |
| **Anchored so it matches one row and not prose** | A loose pattern matches a number mentioned in a paragraph and inflates the floor, permanently -- the floor ratchets and never falls. |
| **Written for multiline matching** | Both tools compile it multiline for you (`RegexOptions::Multiline` / `re.M`), so `^` means start-of-line. Do not work around its absence with `.*` -- see below. |
| **Escaped for JSON** | A backslash is doubled in the file: `\\d`, `\\|`, `\\[`. |

### Why multiline is load-bearing

The pattern is fed two different shapes of input by two different terms of the floor sweep. The
all-refs term feeds it the index **one line at a time**; the working-tree term feeds it the **whole
file as one string**.

Without multiline, `^` anchors to the start of the string, so the pattern matched fine in the
line-at-a-time term and looked correct -- while the working-tree term could never match past the
first line. Measured on the repo this tooling was developed in: without the flag, the working-tree
term found **none** of the index's rows.

The consequence was subtle. The working-tree term is the one that catches a number written to a file
but **committed nowhere** -- a draft is still a claim on its number. The all-refs term hid the failure
by covering every number that had been committed somewhere, which is every case except the one the
working-tree term exists for.

---

## What the index is used for

| Consumer | Use |
|---|---|
| `alloc.ps1`, floor term 2 | Every row on every ref, batched through `git cat-file`, so a number recorded in the index but not yet a file is still taken |
| `alloc.ps1`, floor term 3 | The same rows in the working tree, catching a number that exists only as an uncommitted draft |
| `seq_check.py`, rule 3 | An added file whose number has no row is blocked |
| `seq_check.py`, rule 4 | A duplicate row this change introduces is blocked |
| `seq_check.py`, rule 1 | The row for a reused number is read to see whether it **declares** the new file as a companion |

---

## Declared companions

Reusing a number is legal in exactly one case: the index row for that number names the additional
file. One number, one row, two files.

```markdown
| [0007](0007-worktree-gate.md) | Worktree gate (see also 0007-worktree-gate-appendix.md) | Accepted | 2026-03-02 |
```

The companion is matched against the row **with and without** its extension, because an index row
conventionally links a file by its stem. A companion does **not** get a second row -- that is what
rule 4 blocks.

---

## Adding a row

In the **same commit** as the file it describes.

An entry missing from the index is invisible to everyone reading the index, and -- worse -- the
failure mode of a busy index is a **dropped row**, not a conflict. Two branches appending to the tail
of the same table produce a conflict you resolve by hand, and a hand resolution that takes one side
loses the other side's row silently. Nothing downstream reports it. Never resolve an append-only
shared file with a blanket "take one side"; take both rows.

---

## If your sequence has no index

Drop **both** `indexFile` and `indexRowPattern`. They must be given together or not at all -- half a
configuration is rejected at load, because it would otherwise remove a whole term from the floor
without anything saying so.

Without an index, rules 3 and 4 do not apply, the floor loses terms 2 and the index half of term 3,
and everything else works unchanged.
