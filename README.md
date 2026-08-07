# claude-multisession

## TLDR/BLUF

Run several Claude Code sessions at once on one repository without them overwriting each
other. Each session gets its own git worktree and branch; hooks refuse the edits, commits and pushes
that would collide. No daemon, no service, no dependencies beyond `pwsh`, `git` and a `python`.
PowerShell 7, Windows-first, MIT. Cloning installs nothing.

> **Every failure mode in this system is byte-identical to success.** That one sentence explains the
> whole shape of this repository -- most of all why `ccx doctor` exists and why you run it *before*
> installing anything as well as after. The full statement and what it costs you are at the top of
> the [documentation site](https://wshallwshall.github.io/claude-multisession/).

**Is this for you?** Yes if you drive two or more Claude Code sessions against one repo and have
watched them collide -- [the collision table below](#what-problem-this-solves) is the fastest way to
tell. No if you run one session at a time. Also no if you are CLI-only and wanted cross-session
announce specifically: that one feature needs the desktop client.

**Go:** [What problem this solves](#what-problem-this-solves) - [Install](INSTALL.md) -
[Documentation site](https://wshallwshall.github.io/claude-multisession/) -
[Honest limits](#honest-limits)

Or paste [this page](docs/FEED-THIS-TO-CLAUDE-CODE.md) into Claude Code and have it evaluate your
repository for you.

---

Nothing here puts a `ccx` executable on your `PATH`. Every command is a plain script you run with
`pwsh`; where this README says `ccx doctor` it is shorthand for
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`. Every relative path in this file is
relative to this checkout, which is **not** necessarily the repository being governed.

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

Full statement, with what each one costs you, on the
[documentation site](https://wshallwshall.github.io/claude-multisession/#limits-read-before-installing).

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
developed in, over 30 days:

- **A banner asking sessions to use worktrees does not work.** 44% of all file writes from sessions
  running in the shared primary landed in the primary's own tree. If a convention matters, enforce
  it with a hook; a reminder produces no evidence either way.
- **Gate on the write's target path, never the session's cwd.** 29% of writes came from a session
  *sitting* in the primary and landing inside a sibling worktree by absolute path -- already correct
  behavior that a cwd-keyed gate would have denied every one of.

---

## Platform

**PowerShell 7 + Windows-first.** Nearly every shipped script is PowerShell; a handful are Python,
and those are stdlib-only and portable. The PowerShell house rule is a `#Requires -Version 7.3` line
at the top, and all but a few carry it. The two selfheal scripts ask only for `7`, and a few carry no
`#Requires` at all. That omission is deliberate in the announce hook's case, because its event has to
degrade to "stand down and say so" rather than throw at load. An exact file census is not printed
here on purpose: a count in prose is stale on the next file added. Count it against the tree you
actually have instead, and note that the scope is the question. `git ls-files 'bin/*.ps1' 'bin/*.py'
'scripts/*.ps1' 'scripts/*.py'` is the *shipped* set. A bare `git ls-files '*.ps1'
'*.py'` returns something else: it also sweeps in `examples/` and `tests/`. It runs on PowerShell 7
for Linux and macOS, but the Windows paths are the ones that were exercised, and two behaviors
degrade elsewhere (self-marking in the roster, and path case-folding). A bash port is a different
project.

MIT licensed. No dependencies beyond `pwsh`, `git`, and -- for the three git-hook checkers and the
leak gate -- any `python3` on `PATH`.

---

## Install

Two directories are involved and the installers refuse to guess between them: **tooling** (this
checkout, which nothing you install governs) and **target** (the repository you want governed). Use
the **vendored** layout -- copy `scripts/`, `bin/` and `ccx.config.json` into the target and commit
them, so tooling *is* target. It is the only layout in which the doctor can reach exit 0, because the
three coordination hooks are shims that resolve their script inside whatever repository the session
is running in.

The seven-step path, with a command you can paste, is on the
[documentation site](https://wshallwshall.github.io/claude-multisession/#quickstart).
**[INSTALL.md](INSTALL.md) is the record of record**: every installer, its scope, how to prove it is
live rather than merely merged, and what the doctor's exit code means when you install only some of
it.

Two things that catch people out either way:

- **Baseline the doctor BEFORE installing anything.** Expect a wall of `OFF` and exit 1. That is the
  correct baseline, and it is the only way to tell an installed guardrail from a decorative one
  afterwards.
- **Installers refuse to run inside a session** (`$env:CLAUDECODE` is `1`), because a session that
  can install these controls can remove them. Run them from a plain terminal.

---

## What is in the box

Everything is a plain script. There is no daemon and no background service. Coordination state --
claims, locks, allocations, announce receipts -- lives entirely inside your own git directory. Three
things sit outside it by necessity and are named here rather than discovered: the installed hook
copies and their allowlist, under your client config root; the wiring entries in that root's
`settings.json`; and a queued steering note, at `<worktree>/.claude/steer.txt`.

**The full inventory -- every script, what it does, and which doc owns it -- is on the
[documentation site](https://wshallwshall.github.io/claude-multisession/#what-ships)**, grouped by
what you are trying to do: run sessions, clean up, and the controls the harness or git invokes on
their own. It is one table set rather than two, so it cannot drift from this page.

The shape of it: `bin/ccx-doctor.ps1` proves the rest. `scripts/worktree/` creates, rescues, restores
and removes worktrees. `scripts/coord/` answers presence, overlap, claims and allocations.
`scripts/hooks/` holds the gates the harness and git invoke. Four installers wire them, and there are
four rather than one because they write to genuinely different places -- one settings file, one
clone's `.git/hooks`, every config root, and one config root respectively.

The two that take a repository **refuse to guess** which one. Unset, `-Repo` and `-RepoRoot` mean
the clone you are standing in. Both installers stop rather than proceed when that is not the clone
they ship from, because the wrong answer there installs, wires, hashes and receipts perfectly while
governing a repository you are not working in.

Three properties, each learned the expensive way:

- **The `-Status` modes are exempt from the refuse-to-run-in-a-session rule above**, because auditing
  is not installing. Three of the four carry one; `install-selfheal.ps1` does not -- ask
  `ccx doctor` instead.
- **The status modes report by receipt, never by reading a settings file.** An entry in
  `settings.json` is a *claim*; a receipt plus a target that actually resolves is *evidence*. An
  announce hook once sat wired-but-resolving-nothing for hours while the settings file looked
  entirely correct, because a similarly-named entry from another project occupied the slot.
- **They never blindly overwrite a hook that is not theirs**, and `install-git-hooks.ps1` never
  writes `pre-commit` at all -- two tools cannot both own that one file, and the failure mode is
  every commit in the repository blocked.

Why user scope rather than the project's `.claude/settings.json`: `.claude/` is commonly gitignored,
so git cannot deliver a project-level hook to a new worktree. A project hook also lives on one
branch, and a hook whose script path is inside a working tree *vanishes on a checkout* -- after which
the tool call runs anyway, silently.

---

## How the pieces fit

**One state root, and git already gives it to you.** All coordination state lives at
`<git-common-dir>/<prefix>-coord/` -- `alloc/`, `claims/`, `locks/`, `announce/`. That location is
identical across every worktree of a clone (a claim taken in one is visible from another), isolated
per clone (two clones cannot collide), and uncommittable by construction (no `git add -A` can sweep
it into a commit). Its corollary matters: **state outlives the worktree**, so a claim survives the
directory that took it.

**Everything is exclusive-create, never read-modify-write.** A claim, a lock and an allocation are
all "create this file exclusively; the failure to create *is* the mutual exclusion". See the
4-of-8-lost-writes measurement above for why the obvious alternative is not an option.

**There are no TTLs anywhere, and the omission is the design.** A lock that expires on a timer hands
the critical section to a second process while the first is still inside it -- silently, and at the
exact moment the operation is slowest. That is when a timeout is most likely to be the wrong
inference. Locks retry and never steal: on timeout they fail loudly and name the holder. A wedged
lock you can see beats a silent double-write you cannot.

**Liveness may only VETO, never PERMIT.** There is no heartbeat anywhere, so nothing can prove a
session is gone. `DEAD`/`STALE`/absent is the *absence of a veto*, not a permission. The fence is
wired so it can only block a destructive action. Read `scripts/coord/session-registry.ps1` for what
each verdict licenses; the inverse reading is the natural one, which is why it is stated next to the
code.

**An empty answer and an unanswerable one must not look alike.** `scripts/coord/occupancy.ps1`
returns a *receipt* alongside its rows -- roots examined, records examined, records that could not be
placed -- and sets `Available` only when there was actually something to examine. A caller about to
destroy something gates on `Available`, prints the receipt, and refuses when it is false. Count what
you examined, not what you found.

**One copy of each safety check.** The liveness fence lives once
(`scripts/coord/session-registry.ps1`). So does the cwd->worktree matcher
(`scripts/coord/occupancy.ps1`), and so do the path-comparison rule and the worktree-path formula
(`scripts/coord/_common.ps1`). The command splitter both shell gates need lives once
(`scripts/hooks/_command.ps1`), and the "which tree would this git command actually touch" resolver
lives once beside it (`scripts/hooks/_gittarget.ps1`). The Python gates cannot dot-source PowerShell,
so they get the one counterpart they need -- config discovery, the git runner, path folding -- in
`scripts/hooks/_ccxconfig.py`, which states the three things the two sides must agree on. Two copies
of a safety check drift, and the copy that drifts is the one nobody is testing. The shared substrate
files exist precisely because five copies of "resolve the git common dir" had already drifted into
five behaviors, two of which produced a state root at the filesystem root when git failed.

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

**Kill switches are files, not settings.** Hook wiring only takes effect in *newly started* sessions
and an environment variable never reaches a session already running, so the switches that have to
work right now are on disk: delete `~/.claude/hooks/ccx-gate.repos.txt` to ungovern everything, or
create `<state-root>/announce/OFF` to stand announce down. `ccx doctor` reports every disarm it
finds, so a switch you left flipped cannot quietly become the status quo.

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

- **These are guardrails against the accidental action, not security boundaries.** Every gate here
  inspects tool arguments or a command string, so a file written by a shell command is invisible to
  the `PreToolUse` gate, and **any agent-authored script defeats a command-string rule outright**.
  `git commit --no-verify` and `git push --no-verify` bypass the git hooks. The commit-time hooks are
  the backstop for the tool-time ones, because they inspect the *tree*; back the push guard with
  server-side protection if you need a real one.
- **False positives are the expensive failure.** A gate that denies ordinary work trains sessions to
  route around it, and a routed-around gate protects nothing. The rules here are deliberately narrow
  for that reason, and the fail-open postures are deliberate -- but they are *declared*, per hook,
  and they never fail open silently.
- **Enumerated coverage means every hole is silent.** The gates match named tools and named verbs.
  Anything outside the enumeration passes without a word. `ccx doctor`'s wired-versus-implemented
  diff is the only thing that surfaces a rule which exists but can never fire.
- **The occupancy fence is cwd-keyed and therefore partial.** It cannot see a session writing into a
  worktree by absolute path from somewhere else, a cwd recorded as a UNC or 8.3 short path, or a
  session that never registered. The reaper carries a second, non-cwd signal for that reason and
  prints its blind spots; do not build a destructive action on the cwd signal alone.
- **The collision gate's deny path is not self-testable.** Proving it needs a live peer worktree
  holding an uncommitted change to the same file. `ccx doctor` proves only that the gate refuses to
  go *silent* on its unresolvable path, and prints that as a blind spot on every run.
- **A claim cannot stop a session that refuses to look.** What it buys is that the collision becomes
  visible *before* the work rather than after. Claims do not expire, and releasing is manual: an
  abandoned claim is a stale note, whereas an auto-expiring one silently re-opens the race it exists
  to prevent.
- **Two sequences that both number from 1 share one claim namespace.** Claim keys are flat -- the key
  a person types is the key on disk. Worth knowing before you configure overlapping sequences.
- **No CI-side enforcement is shipped.** `seq_check.py --ci` exists and re-runs the collision rules
  against a freshly fetched trunk, but wiring it into your pipeline is yours. Note that the
  allocation-ownership rule *cannot* run in CI -- it reads a per-clone registry a runner does not
  have -- and it is reported as not running rather than left in place looking like coverage.

---

## The doc set

| Doc | What it covers |
|---|---|
| `README.md` | This file: what it is, which collisions it addresses and what they measured, the platform caveats, the cost, and the honest limits |
| `docs/index.md` | The [documentation site](https://wshallwshall.github.io/claude-multisession/) front door: the quickstart, the full script inventory, and where every page below fits |
| `INSTALL.md` | The installers, their scopes, how to *prove* each one is live rather than merely merged, and what the exit code means on a partial install |
| `docs/FEED-THIS-TO-CLAUDE-CODE.md` | A page to paste into Claude Code so it evaluates *your* repository against this tooling and tells you which parts you need |
| `docs/RUNNING-MULTIPLE-SESSIONS.md` | The entry point to the running-sessions group: which surface to run sessions on, the channels they have for reaching each other, and using one session as a coordinator |
| `docs/CONCEPTS.md` | The model: worktree-per-session, the shared state root, the liveness fence, exclusive-create, why there are no TTLs |
| `docs/HOOKS.md` | The hook-event map, the wiring contract, and the house rules for writing one that cannot fail silently |
| `docs/WORKTREES.md` | Day to day: create, rescue, restore, remove, and the two layouts that coexist |
| `docs/PRUNING.md` | The reaper and its fence -- why clean + merged is not unoccupied, and why a failed removal is worse than none |
| `docs/COORDINATION.md` | Presence, overlap, claims, locks, announce, and the rules for talking to a peer |
| `docs/PR-AND-MERGE.md` | Landing work from N branches into one trunk, and the four states that all read as "can't merge" |
| `docs/SEQUENCE-ALLOC.md` | Allocating a shared sequence git cannot see, with decision-record numbers as the worked example |
| `docs/STEERING.md` | The two steering scripts: queue a note from a second terminal, deliver it mid-task |
| `docs/SESSION-MAIL.md` | The async lane for peers the realtime announce cannot reach. Ships nothing -- it is a design note, and most useful as the measured list of ways the obvious implementations fail |
| `docs/LEAK-GATE.md` | The forbidden-content scanner: what a shape detector catches before a repo goes public, what a token file adds, and the two things no scanner can ever see |
| `docs/CI-AND-STANDARDS.md` | N parallel branches through one pipeline, and a standard that survives agent-written code. Ships no CI configuration -- the scripts it cites are illustrations of the rules |
| `docs/CASE-STUDY-drift-audit.md` | A redacted account of auditing a multi-session estate as one system -- the method, not a status snapshot |
| `docs/ASVS-ASSESSMENT.md` | Method for running a several-hundred-requirement security-standard assessment with agent sessions. Deliberately carries no results, for the same reason the case study carries no status table |
| `docs/TIPS-AND-TRICKS.md` | The "wish I'd known" file, ordered by when it bites: setting up, running two at once, writing a guardrail, proving it works, cleaning up |
| `docs/USAGE-AWARENESS.md` | Warning a session before it hits a hard usage cutoff, and why that is harder than it looks. Ships no hook -- the mechanism depends on undocumented client internals, so what transfers is the design and the eight ways it reports confidently wrong numbers |
| `docs/standards/` | Standards to adapt rather than adopt, with `OVERVIEW.md` as the section index -- it enumerates the set, so this row does not. Start at `CISO-SUMMARY.md` if you are deciding whether to adopt them, `ADOPTING-THESE.md` if you already have. They ship no code and confer no certification; each states its limits before its rules |
| `CLAUDE.md.template` | A working agreement to drop into your own repo: plan first, commit-versus-push approval split, never grep for a number, shared memory across worktrees |

Worked examples live in `examples/`: a language-agnostic worktree setup hook
(`worktree-setup.ps1.example`), a session banner (`session-banner.md.example`), an annotated sequence
gate kept as narrative rather than wired to anything (`ledger_check.annotated.py`), and a complete
filled-in sequence configuration with its index-row format (`sequence-adr/`).

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
