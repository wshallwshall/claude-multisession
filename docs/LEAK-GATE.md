# The leak gate

## TLDR/BLUF

**What this is.** One command, `scripts/security/scan_forbidden.py`, that reads the text files git
tracks and exits non-zero if it finds your home directory, a real IP address, a token or a private
name.

**Why you should care.** What escapes when a private repo goes public is a *string*, not a secret:
`C:\Users\<your-name>`, the address of a box, the client the work was for. No secret scanner looks
for those. Not for you if nothing identifying can reach a tracked file.

**How to use it.** No installer places this file and nothing wires it. Copy it into your own repo
and put a `python` on `PATH`: [Scripts](SCRIPTS.md) says where it sits,
[Limits and requirements](LIMITS.md) covers the interpreter.

Read [What it catches](#what-it-catches) first: the detectors built into the script and the ones you
supply fail in different ways.

---

Publishing a repo that grew up in private is not a license question, it is a *string* question. The
code is fine. What follows it out the door is:

- the absolute path some traceback printed;
- the address of a box someone pasted out of a terminal;
- a token prefix in a config example;
- the name of the client the work was actually for.

None of that is a syntax error, a test failure, or a *secret* in the sense a secret scanner means.
Nothing else in a normal toolchain is looking for it. So it is found by a reader, after publication,
or not at all.

The scanner is stdlib Python with no project import, and it answers in exit codes. That is what lets
it run in a git hook with no virtualenv, or on a CI runner.

In a bare clone it runs but scans nothing: there is no working tree, so the no-argument mode
examines zero files and exits `2`. Name the files, or `--path` a directory.

---

## What it catches

**Structural detectors** are compiled into the script, because they recognize a *shape* and not a
name. There is no list to keep current: they work in a fresh fork, in CI with no secrets, in a
contributor's clone.

One exception: the IP detector is switched off inside a lockfile, where dotted numbers are versions
rather than hosts. The other detectors still run there.

| Class | What it is |
|---|---|
| Absolute user-home path | `<drive>:\Users\<account>\...`, `/home/<account>/...`, `/Users/<account>/...`. Carries an OS login, usually a real person's name, often the internal project name below it. Exempt: placeholders (`<name>`, `$HOME`, `%USERPROFILE%`, `{home}`) and a few conventional stand-ins. Everything else reads as a real account |
| Routable IPv4 | A free-standing quad that is not RFC1918, loopback, link-local, broadcast, `0.`-prefixed, multicast, or an RFC5737 documentation address. Naming a real host is a network disclosure, even a jump box. Look-arounds keep dotted OIDs, version strings and spec-section citations out. |
| Credential shapes | Private-key block headers, and prefix-anchored token formats. It prints `private key block`, `cloud access key id`, `forge access token`, `chat platform token` and `model API key`. Prefix-anchored because an entropy heuristic over source produces a false-positive storm, and a muted gate is worth nothing. Run a real secret scanner too: this catches only copy-paste leaks riding with identifying content. |

**Token detectors** come from a file *you* supply and never commit: the literal names of the private
projects, clients, vendors, hosts or people that must not appear. Nobody can ship that list for you,
and a public repository is the last place it could live.

**The home-path detector only sees accounts that start with an ASCII letter.** A name beginning
with a digit or `_`, or a non-ASCII login, is not matched -- and no other detector covers the shape,
so the miss is silent.

**What it never opens.** Ten directory names are skipped whether or not git tracks what is inside
them: `.git`, `.venv`, `venv`, `node_modules`, `__pycache__`, `.mypy_cache`, `.ruff_cache`,
`.pytest_cache`, `build` and `dist`.

If you track built output, those files are not scanned and the whole-tree run does not say so.

**The home-path class is the one that actually fires in practice.** For a repository like this one,
it is also the one that matters.

---

## Running it

```bash
python scripts/security/scan_forbidden.py                 # every git-tracked file
python scripts/security/scan_forbidden.py FILE [FILE ...] # named files (how a hook invokes it)
python scripts/security/scan_forbidden.py --path DIR      # everything under DIR; repeatable
python scripts/security/scan_forbidden.py --show-context   # also print the matched value
```

Run these from the repository root. The no-argument mode uses `git ls-files`, which from a
subdirectory lists only that subtree -- it scans the subset and exits `0`.

Read the exit code, not the output:

- `0` -- clean.
- `1` -- forbidden content found.
- `2` -- usage error, nothing scanned, or a **fail-closed refusal**: the scanner declining to
  certify a run it could not trust.

`--show-context` is for local triage only. A hit means the string is *already in a tracked file*, so
echoing it into a CI log copies the leak into a public place. The default output is location and
category, never the matched text.

Credential-shape hits stay bare whatever you pass, and so does a home-path hit: the account name is
itself the disclosure.

### Three behaviors worth knowing, because each one is a way a scanner lies

**1. Zero files scanned is a refusal, not a pass.** A run that examined nothing certifies nothing.
Not a repository, an empty checkout, every path swallowed by a skip rule -- all exit `2` and say so.
Exit `0` cannot tell "found nothing" from "looked at nothing".

A wrong directory *inside* the repository is not that case. It scans the subset git lists there and
exits `0`.

**2. Every named argument is accounted for.** `--path` repeats, and takes a directory or a file. An
argument that scans zero files is named, with why, and exits `2` *even when others scanned fine*.
The version this came from dropped file arguments silently, refusing only if **everything** went.

**3. It prints what it loaded and what it scanned.** Two lines on stderr on any run that reaches the
scan, pass or fail:

<!-- no-copy -->
```
ccx leak gate: loaded structural=8, names=0, literals=0, allowlist=1  [STRUCTURAL-ONLY: ...]
ccx leak gate: scanned 412 file(s)  [STRUCTURAL-ONLY: ...]
```

A zero in either number is the whole story, and neither is inferred from silence. `STRUCTURAL-ONLY`
is the posture marker: no token file loaded, so only the shape detectors are armed. It prints on
both lines rather than once, because the line a human reads is whichever scrolled past last.

A fail-closed token refusal prints the `loaded` line and then the refusal, with no `scanned` line,
because nothing was scanned. A usage error prints neither. One line where you expected two is itself
the signal.

**4. `scanned` counts files opened, not files read.** A file with a NUL byte in its first 4KB is
treated as binary and skipped, and so is one the OS refused to open. Both still count as scanned,
and neither prints anything.

UTF-16 text is NUL-heavy, so a file written by PowerShell 5.1 redirection is skipped in silence. The
same leak in UTF-8 exits `1`; in UTF-16 it exits `0` under a healthy-looking receipt. Convert
captured output to UTF-8 before committing it.

---

## Wiring it as a pre-commit hook

**The goal.** Catch a leak at commit time, on your machine, before it is anywhere else.

The installers **never write `.git/hooks/pre-commit`**, a fact [Hooks](HOOKS.md) owns and
`tests/test_installers_never_write_pre_commit.py` pins. Two tools cannot both own the file.

One framework renames a foreign hook and shims it, which blocked every commit in a Windows
repository until the shim came out.

**Do [Supplying a token file](#supplying-a-token-file) first.** The recipe below carries
`--require-tokens`, and with no token source the scanner exits `2` before it scans anything, so
every commit is refused until that file exists.

**What to do.** Wire it yourself. If you use the `pre-commit` framework, it passes staged filenames
as arguments:

```yaml
- repo: local
  hooks:
    - id: leak-gate
      name: leak gate
      entry: python scripts/security/scan_forbidden.py --require-tokens
      language: system
      pass_filenames: true
```

If you install a hook by hand, pass the staged names in as arguments. Two things make it a real gate
rather than a decoration:

- **`--require-tokens`.** The framework passes *args* to a hook but usually cannot set *env*, so
  only the flag makes the commit gate fail closed. Without it, a fresh clone or worktree has no
  token file -- it is gitignored -- so every commit runs with zero token detectors and reports
  success.
- **It is a guardrail against accident, not a security boundary.** `git commit --no-verify` bypasses
  it. Back it with a CI run over the whole tracked tree if you need the stronger claim. That run is
  also the one that catches what was committed before the hook existed.

**What happens next.** A commit carrying a forbidden string is refused, and the hook names the file
and the category. A clean commit prints the `loaded` and `scanned` lines and goes through.

If instead every commit is refused with `no token source is configured`, you have no token file and
`--require-tokens` is doing its job. Supply the file rather than dropping the flag.

---

## Supplying a token file

**The goal.** Arm the private-name detectors without the list of private names entering the
repository.

**What to do.** Supply one of two sources, in precedence order:

1. **`CCX_FORBIDDEN_TOKENS`** -- either a path to a token file *or* the file's content inline,
   newline-separated. This is how CI supplies it, from a secret.
2. **`scripts/security/scan-tokens.local.txt`** -- a local file beside the script. The repo's
   `*.local.*` ignore rule already covers it, so it cannot be committed by accident. Check that rule
   before you create the file, not after.

Sectioned format. Blank lines are ignored, and so is a line that **starts** with `#`.

**A trailing `#` comment is not.** It becomes part of the entry, which then loads, counts toward the
floor, and never matches. Annotate above a line, never after it.

```
[names]
REGEX | REASON | CASE
[literals]
one-substring-per-line
```

In `[names]`, REASON defaults to "private token" and CASE is `i` (default) or `s`. The field
delimiter is space-pipe-space, so a regex alternation `a|b` is fine.

In `[literals]`, matching is case-insensitive on non-letter boundaries. That is what catches a token
buried in an identifier like `sync_token_export`, which a `\b`-anchored regex cannot see, because
`_` is a word character.

**What happens next.** The `loaded=` line stops saying `STRUCTURAL-ONLY`, and `names=` and
`literals=` read non-zero. Check those numbers against what you put in the file.

**Presence is not sufficiency.** A source that loads only *part* of its tokens is the dangerous
case. It satisfies "tokens present", **prints no structural-only marker**, and passes a gate that
calls itself fail-closed.

So `--require-tokens` also requires every section to be non-empty. `--require-tokens=N` (or
`CCX_MIN_DETECTORS=N`, or `names=7,literals=13`) asserts a floor, which is what catches loss
*within* a section.

Per-section is strictly stronger than a bare total: a bare `N` is a total, so growth in a cheap
section masks collapse in an expensive one.

The expected count is supplied from **outside** the token file on purpose. A count carried inside it
would be destroyed by the same mangling it exists to detect. The parser is built around that same
assumption, so it:

- refuses an entry containing an invisible codepoint (a zero-width space pasted through a rendering
  surface parses fine, counts toward the floor, and never matches);
- strips a BOM ahead of the first section header;
- names an unknown header instead of dropping its entries in silence;
- never echoes a token in a warning, because the warning lands in a public log.

### The allowlist

`scripts/security/scan-allowlist.txt` holds one line-regex per false positive, vetoed before any
detector runs. So **one over-broad entry disables the gate** while the counts read healthy.

The loader tests each entry against five fixed canary strings, so a bare `.*` is rejected and the
`allowlist=` count drops, which is the tell.

A pattern narrow enough to pass those canaries and still broad enough to veto a whole class is
accepted in silence, with the count unchanged. Anything matching `Users` does it. Never allowlist a
real path, host or name.

---

## The caveat that matters most

**With no token source, this runs STRUCTURAL-ONLY.** The shape detectors are armed. The
private-name detectors are empty -- there is nothing in them, because nobody shipped you a list.

That posture is legitimate: it catches the absolute-home-path class, the one that actually fires.
But **a green result then proves much less than an armed one**, and the two logs differ by one
string. That is why the marker prints on both lines of every run, and why `--require-tokens`
exists.

The general rule, of which the above is one instance:

> **A green gate is evidence only if you have proved it can SEE that class.**

**The goal.** Plant a violation, watch it fail, *then* trust the pass.

**What to do.** After any change to the detectors, the allowlist or the invocation, write a string
you know is forbidden into a scratch file outside the repository, run the scanner over that file,
then delete it.

**Read `scripts/security/scan-allowlist.txt` before you pick the string.** The allowlist is vetoed
ahead of every detector, so a fixture it already covers exits `0` and reads exactly like a broken
gate. Pick an account name that file does not name.

**What happens next.** Exit `1`, naming the file. Anything else is the gate failing to see. A
scanner with no detectors, a dropped directory, or a regex that never compiled exits `0` on every
run, byte-identical to a clean tree.

Two practical traps when you do this, both covered at more length in
[Tips and tricks](TIPS-AND-TRICKS.md):

- **Capture the exit code without a pipe.** `$?` after a pipeline reports the *last* command, not
  the scanner. In PowerShell, `$?` and `$LASTEXITCODE` answer different questions, and
  `$LASTEXITCODE` is only set by native commands. Redirect to a file and check the code separately.
- **Read the planted fixture back before trusting it.** `printf` interprets `\U`, `\n` and `\t`, so
  a Windows path written that way is not the string you meant. The violation the scanner then
  "failed to find" never existed. Use a quoted heredoc, then `cat` the file and look at it.

---

## What this gate never looks at: The ref store

This gate scans **files**. A repository is more than its files, and private history can sit in a
clone in a place no file scan reaches.

`git fetch <url> <refspec>` -- a fetch against a **direct URL** rather than a named remote -- brings
the objects in **without creating a remote**.

With a destination refspec it writes remote-tracking-style refs. With a bare branch name, the form
anyone actually types, it writes no ref at all: only `FETCH_HEAD`, which does not live under
`refs/`.

Every routine check a person would run then reports a clean clone:

- `git remote -v` lists nothing unexpected. There is no remote to list.
- `git remote remove <name>` fails with `No such remote`, so the obvious cleanup does not apply --
  and reads as "there was nothing to clean".
- `git for-each-ref` lists nothing either, after a bare-refspec fetch. There is no ref to list, and
  the objects are still there and still readable.
- The refs, and every object they make reachable, stay in the clone indefinitely.

So a private repository's history can be present in a public repository's local clone while the
clone looks clean by every habit you have.

**Audit `git for-each-ref`, `git fsck --dangling` and `.git/FETCH_HEAD` -- not `git remote -v`.** A
ref audit alone misses a bare-refspec fetch, because the objects arrive with nothing pointing at
them.

### If you find refs that should not be there

Two questions get conflated here, and a local delete answers neither:

| Question | Scope | What answers it |
|---|---|---|
| **Recoverability** -- can the local refs be restored? | Local | The reflog, dangling objects, a backup of the clone |
| **Exposure** -- did any of it ever reach a remote? | Remote | An audit against the remote, before or after any local cleanup |

Only the second one bears on disclosure, and deleting the local refs does not change its answer
either way.

**Checking remote ref tips is not sufficient**: a commit can sit as an **ancestor** rather than at a
tip. Walk ancestry from every remote head, tag and pull-request ref. Look for content as well as
commits: a path that should never have shipped is as good a marker as a SHA.

Report the shape of your coverage rather than a verdict: *at least N of M refs are clean, the
remaining K are unaudited, not proven clean*. There will be some K, because auditing a ref whose
objects you lack requires fetching them, and a fetch writes to the object store under
investigation.

---

## The permanent blind spot

**A scanner cannot see a policy judgment.** [Tips and tricks](TIPS-AND-TRICKS.md) carries the
review habit that goes with this one.

"This content does not belong in a public repository" is not a token class, and no pattern will ever
catch it. Every one of these can pass this gate cleanly, because every one of them is *ordinary
prose containing no forbidden string*:

- a design note that describes an internal system in enough detail to attack it;
- a case study whose specifics identify the organization it happened at;
- a benchmark number that fingerprints a host;
- a lesson that cannot be told without shipping the recipe for bypassing a control.

That check is a human read, of the whole diff, by someone who knows what must not be said. This
gate makes that read cheaper by taking the mechanical classes off their plate. It does not replace
it: treating a green run as clearance is exactly the failure it is shaped to prevent.
