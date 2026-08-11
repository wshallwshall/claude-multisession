# The leak gate

## TLDR/BLUF

**What this is.** `scripts/security/scan_forbidden.py`, a scanner that refuses to let identifying
content reach a public repository. Stdlib Python, no project import, exit codes only.

**Why you should care.** Publishing a repo that grew up private is a *string* question, not a
license question. What leaks is not a syntax error or a *secret* any secret scanner would
recognize, so nothing else in your toolchain looks for it. Not for you if the repo was public from
commit one.

**How to use it.** Run it in a bare clone, in a git hook with no virtualenv, or on a CI runner. Read
[What it catches](#what-it-catches) first, because the structural detectors and the configured ones
fail differently.

---

`scripts/security/scan_forbidden.py` refuses to let identifying content reach a public repository.

Publishing a repo that grew up in private is not a license question, it is a *string* question. The
code is fine. What follows it out the door is:

- the absolute path some traceback printed;
- the address of a box someone pasted out of a terminal;
- a token prefix in a config example;
- the name of the client the work was actually for.

None of that is a syntax error, a test failure, or a *secret* in
the sense a secret scanner means. So nothing else in a normal toolchain is looking for it, and it is
found by a reader, after publication, or not at all.

Stdlib Python, no project import, exit codes only. Runs in a bare clone, in a git hook with no
virtualenv, or on a CI runner.

---

## What it catches

**Structural detectors** are compiled into the script and always run, because they recognize a
*shape* and not a name. There is no list to keep current: they work in a fresh fork, in CI with no
secrets, in a contributor's clone.

| Class | What it is |
|---|---|
| Absolute user-home path | `<drive>:\Users\<account>\...`, `/home/<account>/...`, `/Users/<account>/...` -- carries an OS login, usually a real person's name, and often the internal project name in the path below it. Bracket and environment placeholders (`<name>`, `$HOME`, `%USERPROFILE%`, `{home}`) and a small set of conventional stand-ins are exempt; everything else reads as a real account. |
| Routable IPv4 | A free-standing quad that is not RFC1918, loopback, link-local, multicast, or an RFC5737 documentation address. Naming a real host is a network disclosure even when the host is "just" a jump box. Look-arounds keep dotted OIDs, version strings and spec-section citations out. |
| Credential shapes | Private-key block headers and the prefix-anchored token formats (cloud access key ids, code-host tokens, chat-platform tokens, model API keys). Prefix-anchored deliberately: an entropy heuristic over source produces a false-positive storm, and a gate people mute is worth nothing. Use a real secret scanner as well -- this catches the copy-paste cases that ride along with identifying content. |

**Token detectors** come from a file *you* supply and never commit: the literal names of the private
projects, clients, vendors, hosts or people that must not appear. Nobody can ship that list for you,
and a public repository is the last place it could live.

The home-path class is the one that actually fires in practice, and it is the one that matters for a
repository like this one.

---

## Running it

```bash
python scripts/security/scan_forbidden.py                 # every git-tracked file
python scripts/security/scan_forbidden.py FILE [FILE ...] # named files (how a hook invokes it)
python scripts/security/scan_forbidden.py --path DIR      # everything under DIR; repeatable
python scripts/security/scan_forbidden.py --show-context   # also print the matched value
```

Exit `0` clean, `1` forbidden content found, `2` usage error / nothing scanned / fail-closed refusal.

`--show-context` is for local triage only. A hit means the string is *already in a tracked file*, so
echoing it into a CI log copies the leak into a public place. The default output is location and
category, never the matched text.

### Three behaviors worth knowing, because each one is a way a scanner lies

**1. Zero files scanned is a refusal, not a pass.** A run that examined nothing certifies nothing.
Wrong directory, not a repository, every path swallowed by a skip rule -- all of them exit `2` and
say so, because exit `0` cannot tell "found nothing" from "looked at nothing".

**2. Every named argument is accounted for by name.** `--path` accepts a file too. An argument that
scans zero files is named, with why, and the run exits `2` -- *even when others scanned fine*. The
version it was ported from dropped file arguments silently, refusing only when **everything** went.

**3. It prints what it scanned and what it loaded.** Two lines on stderr, on every run, pass or fail:

```
ccx leak gate: loaded structural=8, names=0, literals=0, allowlist=1  [STRUCTURAL-ONLY: ...]
ccx leak gate: scanned 412 file(s)  [STRUCTURAL-ONLY: ...]
```

A zero in either number is the whole story. Neither is inferred from silence, and the posture marker
is repeated on both lines rather than printed once, because the log line a human actually reads is
whichever one scrolled past last.

---

## Wiring it as a pre-commit hook

The installers **never write `.git/hooks/pre-commit`**, and
`tests/test_installers_never_write_pre_commit.py` pins it. Two tools cannot both own that file: a
framework that renames a foreign hook and shims it has blocked every commit in a repository on
Windows until the shim was removed.

If you use the `pre-commit` framework, it passes staged filenames as arguments:

```yaml
- repo: local
  hooks:
    - id: leak-gate
      name: leak gate
      entry: python scripts/security/scan_forbidden.py --require-tokens
      language: system
      pass_filenames: true
```

If you install a hook by hand, the shell equivalent is a staged-name list piped in as arguments --
and note the two things that make it a real gate rather than a decoration:

- **`--require-tokens`.** The framework passes *args* to a hook but usually cannot set *env*, so
  only the flag makes the commit-time gate fail closed. Without it, a fresh clone or worktree --
  neither carries the ignored token file -- runs every commit with zero token detectors and reports
  success.
- **It is a guardrail against accident, not a security boundary.** `git commit --no-verify` bypasses
  it. Back it with a CI run over the whole tracked tree if you need the stronger claim; that run is
  also the one that catches what was committed before the hook existed.

---

## Supplying a token file

Two sources, in precedence order:

1. **`CCX_FORBIDDEN_TOKENS`** -- either a path to a token file *or* the file's content inline,
   newline-separated. This is how CI supplies it, from a secret.
2. **`scripts/security/scan-tokens.local.txt`** -- a local file beside the script. The repo's
   `*.local.*` ignore rule already covers it, so it cannot be committed by accident. Check that rule
   before you create the file, not after.

Sectioned format; `#` comments and blank lines ignored:

```
[names]
REGEX | REASON | CASE     # REASON defaults to "private token"; CASE is i (default) or s.
                          # The field delimiter is space-pipe-space, so a regex alternation a|b is fine.
[literals]
one-substring-per-line    # case-insensitive, non-letter boundaries -- this is what catches a token
                          # buried in an identifier like sync_token_export, which a \b-anchored regex
                          # cannot see, because _ is a word character.
```

**Presence is not sufficiency.** A partly loaded token source passes a gate that calls itself
fail-closed, so `--require-tokens` requires every section non-empty and `--require-tokens=N` (or
`CCX_MIN_DETECTORS=N`, or `names=7,literals=13`) floors each section, catching loss inside one.

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
detector, so one over-broad entry disables the gate while the log's counts read healthy. The loader
refuses patterns matching prose or the empty string. Never allowlist a real path, host or name.

---

## The caveat that matters most

**With no token source, this runs STRUCTURAL-ONLY.** The shape detectors are armed. The
private-name detectors are empty -- there is nothing in them, because nobody shipped you a list.

That posture is legitimate: it catches the absolute-home-path class, the one that actually fires.
But **a green result then proves much less than an armed one**, and the two logs differ by one
string. That is why the marker prints on both lines of every run, and why `--require-tokens`
exists.

And the general rule, of which the above is one instance:

> **A green gate is evidence only if you have proved it can SEE that class.**

Plant a violation. Watch it fail. *Then* trust the pass. A scanner with no detectors, a dropped
directory, or a regex that never compiled exits `0` on every run, byte-identical to a clean tree.
Confirm exit `1` on a file you know is dirty after any change to the detectors or the invocation.

Two practical traps when you do:

- **Capture the exit code without a pipe.** `$?` after a pipeline reports the *last* command, not
  the scanner. In PowerShell, `$?` and `$LASTEXITCODE` answer different questions, and
  `$LASTEXITCODE` is only set by native commands. Redirect to a file and check the code separately.
- **Read the planted fixture back before trusting it.** `printf` interprets `\U`, `\n` and `\t`, so
  a Windows path written that way is not the string you meant -- and the violation the scanner then
  "failed to find" never existed. Use a quoted heredoc, then `cat` the file and look at it.

---

## What this gate never looks at: the ref store

This gate scans **files**. A repository is more than its files, and private history can sit in a
clone in a place no file scan reaches.

`git fetch <url> <refspec>` -- a fetch against a **direct URL** rather than a named remote -- writes
remote-tracking-style refs into the local ref store **without creating a remote**. Every routine
check a person would run then reports a clean clone:

- `git remote -v` lists nothing unexpected. There is no remote to list.
- `git remote remove <name>` fails with `No such remote`, so the obvious cleanup does not apply --
  and reads as "there was nothing to clean".
- The refs, and every object they make reachable, stay in the clone indefinitely.

So a private repository's history can be present in a public repository's local clone while the
clone looks clean by every habit you have. **Audit `git for-each-ref`, not `git remote -v`.** They
answer different questions, and only one of them is the ref store.

### If you find refs that should not be there

Two questions get conflated here, and a local delete answers neither:

| Question | Scope | What answers it |
|---|---|---|
| **Recoverability** -- can the local refs be restored? | Local | The reflog, dangling objects, a backup of the clone |
| **Exposure** -- did any of it ever reach a remote? | Remote | An audit against the remote, before or after any local cleanup |

Only the second one bears on disclosure, and deleting the local refs does not change its answer
either way.

**Checking remote ref tips is not sufficient**: a commit can sit as an **ancestor** rather than
at a tip. Walk ancestry from every remote head, tag and pull-request ref, and look for content as
well as commits -- a path that should never have shipped is as good a marker as a SHA.

Report the shape of your coverage rather than a verdict: *at least N of M refs are clean, the
remaining K are unaudited, not proven clean.* There will be some K, because auditing a ref whose
objects you lack requires fetching them, and a fetch writes to the object store under
investigation.

---

## The permanent blind spot

**A scanner cannot see a policy judgment.**

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
