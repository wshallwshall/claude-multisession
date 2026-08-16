# claude-multisession

## TLDR/BLUF

Run several Claude Code sessions on one repository without overwriting each other. Each gets
its own worktree and branch; hooks refuse the edits, commits and pushes that would collide. No
daemon, no service, nothing beyond `pwsh`, `git` and `python`. Windows-first, MIT; cloning installs
nothing.

> **When something here breaks, it produces exactly the same output as when it works -- byte-identical
> to success.** That is why `ccx doctor` exists, and why you run it *before* installing anything as
> well as after. The full statement and what it costs you are on the
> [documentation site](https://claude-multisession.pages.dev/).

This repository is the tooling half of **KORUS**: four Claude Code sessions on one repository -- a
dispatcher, two builders and a lander. The method and the operating procedure live on
[the KORUS site](https://claude-multisession.pages.dev/); this file is the repository's front door.

**Go:** [Quickstart](https://claude-multisession.pages.dev/QUICKSTART.html) -
[What problem this solves](#what-problem-this-solves) - [Install](INSTALL.md) -
[Honest limits](#honest-limits)

Or paste [this page](docs/FEED-THIS-TO-CLAUDE-CODE.md) into Claude Code and have it evaluate your
repository for you.

---

Nothing here puts a `ccx` executable on your `PATH`. `ccx doctor` below is shorthand for
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`, and every relative path is relative to
this checkout -- which is **not** necessarily the repository being governed.

---

## Three limits worth knowing before you install

All three come from one fact: **session discovery rests on a vendor surface this project does not
own.** Everything answering "who is live, and where" reads `<config-root>/sessions/<pid>.json`, a
record the *client* writes.

1. **Announce needs the desktop client.** It delivers through the `ccd_session_mgmt` MCP server,
   which a plain CLI install does not have. If you are CLI-only, leave that one hook uninstalled --
   nothing else depends on it.
2. **The desktop app's own `list_sessions` is incomplete.** It cannot see editor-extension sessions,
   so it answers who can be *messaged*, never who *exists*.
3. **A client schema change degrades every fence to "cannot tell"**, never to a confident wrong
   answer -- and the doctor surfaces it as a record count going to zero.

Full statement, with what each one costs you, in
[the section that owns it](https://claude-multisession.pages.dev/LIMITS.html#session-discovery-rests-on-a-vendor-surface-this-project-does-not-own).

---

## What problem this solves

Two sessions in two worktrees are isolated on disk. They are not isolated in any of the ways that
actually cost you work, and git reports none of it as a conflict.

| Collision | What it looks like | Why git cannot see it | Addressed by |
|---|---|---|---|
| **Same working tree** | Session B runs `git checkout` in the shared primary checkout; session A's files silently become another commit's files, mid-task | It is a legal checkout | `scripts/hooks/worktree_gate.ps1` (PreToolUse deny), `scripts/worktree/worktree-selfheal.ps1` (SessionStart repair) |
| **Same file** | Both edit `src/service.py` in separate branches and find out at merge, after both built on divergent assumptions | Merge-time, not edit-time | `scripts/hooks/collision_gate.ps1` + `scripts/coord/overlap.ps1` |
| **Same work, different files** | Three sessions independently fix the same dependency advisory; three branches, three file sets, zero textual conflict, all green | There is nothing to conflict on | `scripts/coord/claim.ps1` + `scripts/hooks/claim_check.py` |
| **Same reserved number** | Both grep for "the next free decision-record number", both pick `0084`, both create *differently named* files, both merge clean | No shared bytes were touched | `scripts/coord/alloc.ps1` + `scripts/hooks/seq_check.py` |
| **Same shared git config** | Two concurrent `git worktree add` calls race `.git/config.lock`; one fails and leaves an orphaned branch | The loser reports a lock error, not a race | `scripts/coord/lock.ps1`, used by `scripts/worktree/new.ps1` |
| **Same shared list** | Any "registry" you read, edit and write back | Nothing errors | Exclusive-create test-and-set everywhere. Measured on the repo this tooling was developed in: 8 concurrent PowerShell writers to one shared file, **4 writes lost, no error** |
| **Same agent memory** | Cross-session memory lives outside the repo; last write wins | It is not in the repo | Convention only -- coordinate memory *writes*, or let exactly one session own them |

The number collision fired **three times** on the repo this tooling was developed in. It is the one
class that a worktree, a file lock and `git merge-tree` are *all* blind to.

Two design facts that fall out of measuring rather than guessing, both on the repo this tooling was
developed in. Over 30 days, 166 sessions ran with their cwd in the shared primary. Both percentages
below are shares of the Edit/Write calls **those** sessions made, not of every write on the machine:

- **A banner asking sessions to use worktrees does not work.** 6,075 of those calls (44%) landed in
  the primary's own tree. If a convention matters, enforce it with a hook; a reminder produces no
  evidence either way.
- **Gate on the write's target path, never the session's cwd.** Another 4,010 of them (29%) landed
  inside a sibling worktree by absolute path -- already correct behavior that a cwd-keyed gate
  would have denied every one of.

This page is the record for both figures. Neither has been re-measured, and nothing in this
repository can recompute them.

---

## Platform

**PowerShell 7 + Windows-first.** Most scripts are PowerShell; the rest are stdlib-only Python.

The house rule is a `#Requires -Version 7.3` line and most carry it. The two selfheal scripts ask
only for `7`, and a few carry no `#Requires` at all -- deliberate for the announce hook, whose event
must degrade to a stand-down message rather than throw at load.

No file census appears here: a count in prose is stale on the next file added. Count it against your
own tree, watching the scope. `git ls-files 'bin/*.ps1' 'bin/*.py' 'scripts/*.ps1'
'scripts/*.py'` is the *shipped* set; a bare `git ls-files '*.ps1' '*.py'` also sweeps in
`examples/` and `tests/`.

It runs on PowerShell 7 for Linux and macOS, but only the Windows paths were exercised, and two
behaviors degrade elsewhere: self-marking in the roster, and path case-folding. A bash port is a
different project.

MIT licensed. No dependencies beyond `pwsh`, `git`, and -- for the three git-hook checkers and the
leak gate -- any `python3` on `PATH`.

---

## Install

Two directories are involved, and the installers refuse to guess between them: **tooling** (this
checkout, which nothing you install governs) and **target** (the repository you want governed).

Use the **vendored** layout: copy `scripts/`, `bin/` and `ccx.config.json` into the target and
commit them, so tooling *is* target. Only that layout lets the doctor reach exit 0, because the
three coordination hooks are shims that resolve their script inside whatever repository the session
runs in.

The seven-step path, with a command to paste, is the
[Quickstart](https://claude-multisession.pages.dev/QUICKSTART.html).
**[INSTALL.md](INSTALL.md) is the record of record**: every installer, its scope, how to prove one
is live, not merely merged, and what the exit code means on a partial install.

Two things that catch people out either way:

- **Baseline the doctor BEFORE installing anything.** Expect a wall of `OFF` and exit 1. That is the
  correct baseline, and it is the only way to tell an installed guardrail from a decorative one
  afterwards.
- **Installers refuse to run inside a session** (`$env:CLAUDECODE` is `1`), because a session that
  can install these controls can remove them. Run them from a plain terminal.

---

## What is in the box

Everything is a plain script; there is no daemon and no background service. Coordination state --
claims, locks, allocations, announce receipts -- lives inside your own git directory.

Three things sit outside it by necessity: the installed hook copies and their allowlist under your
client config root, the wiring entries in that root's `settings.json`, and a queued steering note at
`<worktree>/.claude/steer.txt`.

**The full inventory -- every script, what it does, and which doc owns it -- is
[here](https://claude-multisession.pages.dev/SCRIPTS.html)**, grouped by task: run sessions, clean
up, and the controls the harness or git invokes on their own. One table set, not two, so it cannot
drift from this page.

The shape of it: `bin/ccx-doctor.ps1` proves the rest; `scripts/worktree/` creates, rescues,
restores and removes worktrees; `scripts/coord/` answers presence, overlap, claims and allocations;
and `scripts/hooks/` holds the gates the harness and git invoke.

Four installers wire them rather than one, because they write to genuinely different places: one
settings file, one clone's `.git/hooks`, every config root, and one config root respectively.

The two that take a repository **refuse to guess** which one. Unset, `-Repo` and `-RepoRoot` mean
the clone you are standing in, and both stop if that is not the clone they ship from. The wrong
answer installs, wires, hashes and receipts perfectly while governing a repository you are not
working in.

Three properties, each learned the expensive way:

- **The `-Status` modes are exempt from the refuse-to-run-in-a-session rule above**, because auditing
  is not installing. Three of the four carry one; `install-selfheal.ps1` does not -- ask
  `ccx doctor` instead.
- **Status modes report by receipt, never by reading settings.** A `settings.json` entry is a
  *claim*; a receipt whose target resolves is *evidence*. An announce hook sat wired but resolving
  nothing for hours while that file looked correct -- another project's similarly-named entry held
  the slot.
- **They never blindly overwrite a hook that is not theirs**, and `install-git-hooks.ps1` never
  writes `pre-commit` at all -- two tools cannot both own that one file, and the failure mode is
  every commit in the repository blocked.

Why user scope, not the project's `.claude/settings.json`: `.claude/` is usually gitignored, so git
cannot deliver one to a new worktree. A project hook lives on one branch; one whose script path is
inside a working tree *vanishes on a checkout* -- after which the tool call runs anyway, silently.

---

## How the pieces fit

**One state root, and git already gives it to you.** All coordination state lives at
`<git-common-dir>/<prefix>-coord/` -- `alloc/`, `claims/`, `locks/`, `announce/`. It is identical
across every worktree of a clone, isolated per clone, and uncommittable: no `git add -A` can sweep
it into a commit.

So a claim taken in one worktree is visible from another, two clones cannot collide, and **state
outlives the worktree** -- a claim survives the directory that took it.

**Everything is exclusive-create, never read-modify-write.** A claim, a lock and an allocation are
all "create this file exclusively; the failure to create *is* the mutual exclusion". See the
4-of-8-lost-writes measurement above for why the obvious alternative is not an option.

**There are no TTLs anywhere, and the omission is the design.** A lock that expires on a timer hands
the critical section to a second process while the first is inside it, silently, at the moment the
operation is slowest. Locks retry and never steal: on timeout they fail loudly and name the holder.

**Liveness may only VETO, never PERMIT.** There is no heartbeat, so nothing can prove a session is
gone: `DEAD`/`STALE`/absent is the *absence of a veto*, not a permission, and the fence can only
block a destructive action. `scripts/coord/session-registry.ps1` states what each verdict licenses.

**An empty answer must not look like an unanswerable one.** `scripts/coord/occupancy.ps1` returns a
*receipt* -- roots and records examined, records it could not place -- and sets `Available` only
when something was examined. A caller about to destroy something refuses unless `Available` is true.

**One copy of each safety check.** Each of these lives in exactly one file:

- the liveness fence, in `scripts/coord/session-registry.ps1`;
- the cwd->worktree matcher, in `scripts/coord/occupancy.ps1`;
- the path-comparison rule and the worktree-path formula, in `scripts/coord/_common.ps1`;
- the command splitter both shell gates need, in `scripts/hooks/_command.ps1`;
- the resolver for which tree a git command would actually touch, in `scripts/hooks/_gittarget.ps1`;
- config discovery, the git runner and path folding for the Python gates, which cannot dot-source
  PowerShell, in `scripts/hooks/_ccxconfig.py` -- which states the three things the two sides must
  agree on.

Two copies of a safety check drift, and the copy that drifts is the one nobody is testing. These
shared files exist because five copies of "resolve the git common dir" had already drifted into five
behaviors, two of which produced a state root at the filesystem root when git failed.

---

## Configuration

One file, `ccx.config.json`, at your repository root. It is both the knob file and the opt-in
marker -- user-scope hooks run in *every* repository on the machine, so "is this repo governed?" has
to be answerable without running anything.

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

| Key | Controls |
|---|---|
| `prefix` | The state root name, the git config key, the home-branch marker, the installer markers, the allowlist filename, and the `CCX_*` env prefix |
| `trunk` | `auto` resolves the remote's recorded default branch. Never hardcoded, so a repo on `develop` does not silently get an empty signal |
| `worktreeLayout` | `sibling` or `nested`. The path formula lives once, in `_common.ps1` |
| `setupHook` | What a fresh checkout of *your* project needs. This is the key that makes the tooling language-agnostic -- see `examples/worktree-setup.ps1.example` |
| `protectedRefs` | `push_guard.py`. An explicitly empty list disables the guard **with a message on stderr**, because a guard that is off must never look like a guard that passed |
| `sequences` | `alloc.ps1`, `seq_check.py`, and the item token `claim_check.py` matches. **Omit the key entirely and all sequence machinery is off** |

Two optional files you own: `.ccx/session-banner.md` (your project's SessionStart policy text -- see
`examples/session-banner.md.example`) and the setup hook named above.

Environment overrides: `CCX_CONFIG`, `CCX_TRUNK`, `CCX_PYTHON`, `CCX_EDITOR`, `CCX_SESSION_BANNER`,
`CCX_ALLOW_DIRECT_PUSH`, `CCX_ANNOUNCE_DISABLE`.

**Kill switches are files, not settings.** Hook wiring reaches only *newly started* sessions, and an
environment variable never reaches a running one, so a switch that has to work right now has to be
on disk.

Delete `~/.claude/hooks/ccx-gate.repos.txt` to ungovern everything; create
`<state-root>/announce/OFF` to stand announce down. `ccx doctor` reports every disarm it finds, so a
switch you left flipped cannot quietly become the status quo.

---

## What it costs

Always-on hooks are a standing tax on every prompt, so the numbers are published rather than left to
be discovered. Measured on the repo this tooling was developed in:

| Hook | Cost | Note |
|---|---|---|
| Coordination shim (`UserPromptSubmit`) | ~0.5 s on **every** prompt, in every repo on the machine | The cheap marker check runs before the expensive lookup |
| Announce peer lookup | ~1.0 s on the prompts where it actually runs | Backed off deliberately: at most once a minute for the first ten checks, then once every ten minutes, stopping after 40 |
| `steer-inject.ps1` on `*` | ~366 ms per **tool call**, ~267 ms of which is bare `pwsh` startup and unavoidable | Which is why it is opt-in per worktree, not wired globally |
| `alloc.ps1` floor sweep | ~1 s, once per allocation | Not per edit |
| `overlap.ps1` git walk | ~1 s across a dozen worktrees | Cached, so the gate's common case is a cache read |

---

## Honest limits

- **These are guardrails against the accidental action, not security boundaries.** Every gate
  inspects tool arguments or a command string, so a file written by a shell command is invisible to
  the `PreToolUse` gate, and **any agent-authored script defeats a command-string rule outright**.
- **`--no-verify` bypasses the git hooks**, on both `git commit` and `git push`. The commit-time
  hooks backstop the tool-time ones because they inspect the *tree*; back the push guard with
  server-side protection if you need a real one.
- **False positives are the expensive failure.** A gate that denies ordinary work trains sessions to
  route around it, and a routed-around gate protects nothing. The narrow rules and the fail-open
  postures follow from that -- but each posture is *declared*, per hook, and never fails open
  silently.
- **Enumerated coverage means every hole is silent.** The gates match named tools and named verbs.
  Anything outside the enumeration passes without a word. `ccx doctor`'s wired-versus-implemented
  diff is the only thing that surfaces a rule which exists but can never fire.
- **The occupancy fence is cwd-keyed and partial.** It cannot see an absolute-path write from
  another cwd, a cwd recorded as a UNC or 8.3 short path, or a session that never registered. The
  reaper adds a second, non-cwd signal and prints its blind spots; do not gate a destructive action
  on cwd alone.
- **The collision gate's deny path is not self-testable.** Proving it needs a live peer worktree
  holding an uncommitted change to the same file. `ccx doctor` proves only that the gate refuses to
  go *silent* on its unresolvable path, and prints that as a blind spot on every run.
- **A claim cannot stop a session that refuses to look.** It buys visibility: the collision shows up
  *before* the work rather than after. Claims do not expire, and releasing is manual -- an abandoned
  claim is a stale note, whereas an auto-expiring one silently re-opens the race it exists to
  prevent.
- **Two sequences that both number from 1 share one claim namespace.** Claim keys are flat -- the key
  a person types is the key on disk. Worth knowing before you configure overlapping sequences.
- **No CI-side enforcement ships.** `seq_check.py --ci` re-runs the collision rules against a
  freshly fetched trunk; wiring it into your pipeline is yours. The allocation-ownership rule
  *cannot* run in CI: it reads a per-clone registry a runner lacks, and says so rather than looking
  like coverage.

---

## The doc set

| Doc | What it covers |
|---|---|
| `README.md` | This file: what it is, which collisions it addresses and what they measured, the platform caveats, the cost, and the honest limits |
| `docs/index.md` | The [documentation site](https://claude-multisession.pages.dev/) front door: the quickstart, the full script inventory, and where every page below fits |
| `INSTALL.md` | The installers, their scopes, how to *prove* each one is live rather than merely merged, and what the exit code means on a partial install |
| `docs/FEED-THIS-TO-CLAUDE-CODE.md` | A page to paste into Claude Code so it evaluates *your* repository against this tooling and tells you which parts you need |
| `docs/RUNNING-MULTIPLE-SESSIONS.md` | The entry point to the running-sessions group: which surface to run sessions on, the channels they have for reaching each other, and using one session as a lander |
| `docs/CONCEPTS.md` | The model: worktree-per-session, the shared state root, the liveness fence, exclusive-create, why there are no TTLs |
| `docs/HOOKS.md` | The hook-event map, the wiring contract, and the house rules for writing one that cannot fail silently |
| `docs/WORKTREES.md` | Day to day: create, rescue, restore, remove, and the two layouts that coexist |
| `docs/PRUNING.md` | The reaper and its fence -- why clean + merged is not unoccupied, and why a failed removal is worse than none |
| `docs/COORDINATION.md` | Presence, overlap, claims, locks, announce, and the rules for talking to a peer |
| `docs/PR-AND-MERGE.md` | Landing work from N branches into one trunk, and the four states that all read as "can't merge" |
| `docs/SEQUENCE-ALLOC.md` | Allocating a shared sequence git cannot see, with decision-record numbers as the worked example |
| `docs/STEERING.md` | The two steering scripts: queue a note from a second terminal, deliver it mid-task |
| `docs/SESSION-MAIL.md` | Step-by-step instructions for building the async lane a KORUS build needs to reach a VS Code peer or a second-account peer. Ships nothing here -- a build guide, not an installed tool |
| `docs/LEAK-GATE.md` | The forbidden-content scanner: what a shape detector catches before a repo goes public, what a token file adds, and the two things no scanner can ever see |
| `docs/CASE-STUDY-drift-audit.md` | A redacted account of auditing a multi-session estate as one system -- the method, not a status snapshot |
| `docs/CASE-STUDY-correction-chain.md` | One finding restated four times across two sessions, three statements wrong -- what a correction sequence licenses and what it does not |
| `docs/TIPS-AND-TRICKS.md` | The "wish I'd known" file, ordered by when it bites: setting up, running two at once, writing a guardrail, proving it works, cleaning up |
| `docs/USAGE-AWARENESS.md` | Warning a session before it hits a hard usage cutoff, and why that is harder than it looks. Ships no hook -- the mechanism depends on undocumented client internals, so what transfers is the design and the eight ways it reports confidently wrong numbers |
| `CLAUDE.md.template` | A working agreement to drop into your own repo: plan first, commit-versus-push approval split, never grep for a number, shared memory across worktrees |

**The standards are a separate project now** -- roughly half of this repository, sharing none of its
subject. The set, its CI discipline and its assessment method live at
[secure-development-standards](https://github.com/wshallwshall/secure-development-standards).

Its index is not mirrored here: two copies of one list is the drift both projects are about.

Worked examples live in `examples/`: a language-agnostic setup hook (`worktree-setup.ps1.example`),
a session banner (`session-banner.md.example`), an annotated sequence gate wired to nothing
(`ledger_check.annotated.py`), and a filled-in sequence config with its index-row format
(`sequence-adr/`).

---

## Conventions

Small, boring, and load-bearing when several tools write files another tool reads:

- **UTF-8 without BOM**, LF, ISO-8601 timestamps that round-trip.
- **ASCII-only output** from every hook. A console that is not UTF-8 renders anything else as
  mojibake, and one convention across the set beats two.
- **Stdlib only** in the Python gates, and no import of the surrounding project -- these run in
  worktrees that may have no virtualenv. A gate that skips because an import failed is worse than no
  gate, because it still looks installed.
- **Marker strings are on-disk identity.** Installers decide whether a hook is theirs by matching a
  marker inside the installed file, and no marker is a substring of another. Renaming one orphans
  every existing install, so if you must, do it once, in one commit.
- **Folded paths are for comparison only** -- never hand one to git, to the filesystem, or to a
  message a human reads. Case-folding is conditional on the platform, because on a case-sensitive
  filesystem two spellings really are two directories.

## License

MIT. See `LICENSE`.
