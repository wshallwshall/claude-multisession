# Tests

```
python -m pytest tests -q
```

They are plain `unittest` classes, so they also run with no third-party package at all:

```
python -m unittest discover -s tests -v
```

Python 3 standard library only. Nothing is installed, nothing is committed, nothing outside a
temporary directory is written.

---

## What is here, and why each one exists

| File | Pins | The failure it exists for |
|---|---|---|
| `test_install_gate_wiring.py` | every tool the gate branches on appears in the installer's matcher list, and no matcher names a tool the gate ignores | a `PreToolUse` rule is only invoked for the tools its matcher names. A rule whose tool appears in no matcher **never fires**, and nothing says so: the script is present, it hashes correctly, and every test that runs it directly still passes -- because those tests bypass the matcher that decides whether it runs at all |
| `test_worktree_gate_no_args.py` | the gate, run with **no arguments**, is off with no allowlist, denies a write into a governed root, and allows one outside | the allowlist path is a **parameter default**, and a default is not evaluated when the caller supplies a value. A suite in which every case passed `-ReposFile` explicitly never executed that line once -- and a version shipped whose default died before the script's first line, with the suite green throughout |
| `test_installers_never_write_pre_commit.py` | no installer this repo ships -- all four are enumerated -- writes, moves or removes `pre-commit`, and the git-hook installer still *reports* on it | two tools cannot both own that file. A hook framework that finds a foreign hook there may rename it and drive it from its own shim; that chain has failed on Windows and blocked every commit in a repository until the shim was removed. The renamed file *existing* did not indicate success -- only a real commit did |
| `test_installer_copy_lists.py` | each installer carries its control's dependency closure: the module the Python checkers import, the helpers the gate dot-sources | a checker installed without the module it imports raises at import and refuses **every** commit; a gate installed without its helpers exits 0 after a stderr receipt and enforces **nothing**. Both look installed, and both hash correctly |

The requirement is read off the **consumer** wherever possible -- what the checkers actually import,
what the gate actually dot-sources, where the installer actually writes its allowlist -- rather than
from a list of names typed into a test file. A copy list checked against a hand-written list only
proves that two lists agree.

---

## What they do NOT cover

Read this part. A test suite's blind spots are the reason a green run can still be wrong.

* **They do not run either installer.** The installers refuse to run inside an agent session, by
  design, and nothing here defeats that. So no case observes a hooks directory after an install. The
  evidence that a copy actually landed comes from `bin/ccx-doctor.ps1`, which hashes the installed
  substrate and the installed gate's helpers against this checkout, and from
  `install-git-hooks.ps1 -Status` / `install-gate.ps1 -Status`.
* **They do not test the installed copies.** Everything here binds files in this checkout. Enforcement
  runs from an installed copy that can be older, and a suite that only ever binds the repository's
  copy is exactly how a stale gate stayed green. The doctor is what compares the two.
* **They do not fire the git hooks, the claim gate, the push guard, the collision gate, the announce
  hook, the self-heal backstop or the ASCII checker.** The doctor attacks each of those against a
  throwaway fixture and requires it to refuse, with a paired negative control. That is a different
  kind of evidence and it is not duplicated here.
* **The PowerShell parsing is textual.** Comments are stripped before any declaration is read (a
  commented-out matcher used to slip through, and was caught by mutating the tree on purpose), but
  these are regular expressions over source, not a PowerShell parser. Restructuring a declaration --
  building the matcher list in a loop, say -- makes the extractor raise rather than quietly return
  nothing, which is the failure direction to prefer, but it does mean a reshape needs the test
  updated deliberately rather than deleted.
* **The `pre-commit` scan is line-oriented.** It flags a file operation naming `pre-commit` on the
  same line as the operation. A write split across lines, or one routed through a variable holding
  the name, would not be seen.
* **No coverage of the coordination installer, the allocator, the claim ledger, pruning, presence, or
  the leak gate.** Absence here is not a verdict on those; it is absence.

Every extractor raises when it finds nothing, rather than returning an empty set for a caller to
compare against another empty set -- two empty sets are equal, and that is the shape of a test that
passes having checked nothing.
