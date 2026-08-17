# Limits and requirements

## TLDR/BLUF

**What this is.** What KORUS needs to run, and the places it stops working. Both were on the
landing page, above the first command, until 2026-08-16.

**Why you should care.** These controls do not share one on-switch, and the collision gate has more
blind spots than the one everybody knows about. Read this before you trust a quiet session. Not for
you if you have not installed anything yet, in which case start at [Quickstart](QUICKSTART.md).

**How to use it.** Check the requirements table, then read
[what actually switches each control on](#what-actually-switches-each-control-on). If you run more
than one session against a single checkout, read the collision gate section as well.

---

## Requirements

| Need | Without it |
|---|---|
| **Claude Code for Desktop** | KORUS is a desktop framework. A CLI-only or editor-extension setup is not supported, and the coordination layer is shaped around the desktop client. See below. |
| **PowerShell 7.3+** (`pwsh`) | Below 7.3, every installer but one refuses. Read the 7.0-7.2 row in the platform table before you assume that is safe. |
| **git**, recent enough for `rev-parse --path-format=absolute` | Path resolution returns nothing, so the user-scope hooks resolve nothing and stay quiet. Nothing checks or reports your git version. |
| **`python` on `PATH`** (or `CCX_PYTHON`) | The installed git gates are OFF and say so on stderr. Needed by the three git-hook checkers and the leak gate. |
| **The scripts vendored into the target repo** | The three coordination hooks resolve nothing, and the doctor cannot reach exit 0. See below. |
| **Your primary checkout listed in `~/.claude/hooks/ccx-gate.repos.txt`** | The worktree gate and the SessionStart backstop are OFF for that checkout. This file, not `ccx.config.json`, is their switch. |
| **`ccx.config.json` at the target repo root** | Announce stays inert there, and every knob falls back to its default. It is **not** the opt-in for the other three user-scope hooks. |
| **A plain terminal to install from** | All four installers throw when `$env:CLAUDECODE` is `1`. A session that can install these controls can remove them. |

PowerShell 7 runs on Linux and macOS, but Windows is the exercised path. Self-marking and path
case-folding degrade elsewhere.

**There is no `ccx` on `PATH`.** Where these documents say `ccx doctor`, they mean
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`.
[MIT](https://claude-multisession.pages.dev/LICENSE).

**Running the test suite additionally needs `pandoc`.** It is pinned by version and digest in CI, and
`tests/test_word_copy_tracks_the_markdown.py` fails rather than skips without it.

### Why a vendored layout is a requirement

The three coordination hooks install as shims that re-resolve their script at run time. Both bases
they resolve from sit inside the *session's own* repository: the primary checkout, and the worktree
top level. The tooling checkout is never one of them.

So in a separate-checkouts layout the shims resolve nothing. You get a wired `settings.json`, no
session banner, no collision gate and no announce. The doctor models the same two bases and scores
each unresolved row RED, which is why it cannot reach exit 0 there.

The worktree gate, both git hooks and the backstop do not care about the layout.
[Quickstart](QUICKSTART.md) step 3 is the procedure.

### What actually switches each control on

The requirements table above is not one switch repeated. Each control keys on something different,
and a reader who deletes `ccx.config.json` to opt a repository out will find three of them still
running.

| Control | Switched on by | Does not read |
|---|---|---|
| Worktree gate (`PreToolUse`, denies) | An entry in the gate allowlist | `ccx.config.json` |
| SessionStart backstop (runs `git checkout`) | The same allowlist | `ccx.config.json`, beyond the `prefix` knob |
| Collision gate (`PreToolUse`, denies) | Its script resolving inside your repo | `ccx.config.json` |
| Session banner (`SessionStart`) | Its script resolving inside your repo | `ccx.config.json` |
| Announce | `ccx.config.json` present at the repo root | The allowlist |
| `commit-msg` and `pre-push` | Installation into that clone's `.git/hooks` | The allowlist |

**Deleting the allowlist turns off the two controls that act on a shared checkout**, everywhere and
at once. That is the documented kill switch.

**The config file's location rule is not uniform.** Announce tests the repository root and refuses to
walk up. Every other consumer walks up from the current directory. A config one level above the root
therefore satisfies the git-hook checkers and the doctor while leaving announce inert.

## Platform support

`.github/workflows/gates.yml` holds the CI matrix, and it names two operating systems.

| Platform | Status | What degrades |
|---|---|---|
| **Windows, PowerShell 7.3+** | The exercised path. In CI as `windows-latest` | Nothing known. This is the platform the defaults assume |
| **Linux, PowerShell 7.3+** | In CI as `ubuntu-latest` | Path comparison stops folding case, and roster self-marking degrades. Both are named in the note under Requirements above |
| **macOS** | **Not tested.** It is not in the CI matrix | `ccx doctor` prints its non-Windows blind spot there, but nothing in CI covers macOS. Treat it as unmeasured rather than working |
| **PowerShell 7.0-7.2** | **Worse than unsupported** | Only `install-selfheal.ps1` declares `-Version 7`, so it installs while every other installer refuses. You get the hook that runs `git checkout` on your shared primary, and none of the gates |
| **Windows PowerShell 5.1** | Unsupported | 26 scripts carry `#Requires -Version 7.3` and refuse to start. Three carry no `#Requires` at all, and those fail quietly instead |

**The 5.1 refusal is not uniform, and the exceptions are the dangerous half.** `announce-session.ps1`
and `steer-inject.ps1` have no version guard. Both are declared fail-open: the dot-source fails, the
hook stands down, and the exit code is 0. You are not stopped. You are ignored.

CI is not the doctor. The runners install a pinned, digest-verified `pandoc`, then run the ASCII
gate, the leak scan, a parse of every shipped `.ps1` and the test suite. They never run `ccx doctor`:
some controls it fires need a live second session and a peer worktree.

**The leak scan in CI is structural-only** unless the `CCX_FORBIDDEN_TOKENS` repository secret is
set. Shape detectors are armed; private-name detectors are empty. A green run has not cleared any
private name, and the workflow says so in capitals on every run.

So a green Linux run says the scripts parse and the suite passes there. Whether the hooks, the
gates and the roster behave on Linux in a real session is not established by it.

The pandoc step also explains the macOS gap. The workflow refuses to guess a pandoc for any runner
other than Linux or Windows, rather than install an unverified one.

## Session discovery rests on a vendor surface this project does not own

Everything answering "who is live, and where" reads `<config-root>/sessions/<pid>.json` -- a record
the *client* writes, whose shape, location and lifetime belong to the client. Three consequences
follow.

**Announce needs the desktop client.** It delivers through `ccd_session_mgmt`, an MCP server a plain
CLI install lacks. The hook never sends: it asks the model to, so nothing is delivered and the model
says so.

**This is why KORUS is a desktop framework rather than a preference.** Announce is one of the
coordination surfaces shaped by the desktop client, alongside the two below and the automatic
worktree every new desktop session gets.

Some scripts here run anywhere `pwsh` does. Running them without the desktop app is not KORUS, and
nothing here measures how far it gets you.

**The desktop app's own session list is incomplete.** `list_sessions` enumerates only sessions *that
app itself spawned*. An editor-extension session is never registered, so it cannot be messaged. It
is authoritative for who can be **messaged**, the on-disk records for who **exists**.

**A schema change degrades to "cannot tell", not to a wrong answer.** Rename a field or change
`startedAt`'s unit and every fence says it cannot tell. That verdict is a veto, so the gates keep
refusing rather than waving edits through. Designed for in `scripts/coord/session-registry.ps1`.

**Only one kind of change shows up in the doctor's census.** A moved directory drops records read to
zero. A renamed field or a changed unit leaves that count untouched, because those records still
parse and still place. A healthy count is not evidence the schema still matches.

**Of the two, a moved directory is the one to fear.** Zero records reads as a genuine all-clear.
Nobody is live, so no fence has anything to veto, and the collision gate allows every edit with empty
output. The census catches this. Nothing inside a session does.

## What the collision gate does not see

This is the control the project exists for, so its edges matter more than any other. It refuses an
edit when a **live peer worktree** holds **uncommitted** changes to **that file**. Every one of those
words is load-bearing, and each excludes something.

**A session in your own worktree is invisible.** `overlap.ps1` skips your own worktree before
comparing any path, because a worktree cannot collide with itself. Two sessions on one checkout
collide in silence. One worktree per session is the assumption this control is built on.

**Its answer can be up to a minute stale.** The overlap map is cached for 60 seconds, and the gate
never asks for a refresh. A peer who reached your file inside that window does not appear.

**Three ordinary file states cannot produce a refusal.** The peer's changes are read from
`git status --porcelain`, and that command does not surface them as paths:

- A new file inside a new directory. Git reports the directory, not the file.
- A rename. Porcelain prints `R old -> new`, which matches neither path.
- Anything git-ignored, including the `.env` named further down this page.

Staged, unstaged and ordinary untracked files do count.

**An absolute path into another worktree is never checked.** The query goes repo-relative only when
the target sits under your own worktree root. Otherwise it stays absolute, compared against
repo-relative entries, and can never match. Writing into a peer's checkout is what it cannot see.

**Symlinks are not resolved.** A link reaching the same file compares as a different path.

**A dormant peer is allowed without a word.** The gate's own header says such a worktree "is reported
and allowed". In practice it exits 0 with empty output, so an abandoned worktree holding uncommitted
changes to your file tells you nothing.

**Four paths end in an allow with no output at all**, outside the notice machinery entirely:

| Path | Why nothing is printed |
|---|---|
| The dormant-peer case above | The gate exits before it composes a message |
| The 20-second hook timeout | A killed hook writes no decision, and the edit proceeds |
| The shim resolving no script | Unlike announce, this shim prints no missing-script notice |
| PowerShell below 7.3 | `#Requires` fires before the body runs, so its own error handling never gets a turn |

**The "could not check" notice is rate-limited.** One function carries every fail-open path, and it
suppresses a repeat of the same reason, in the same worktree, for 30 minutes. Against a broken
overlap script, one edit in that window warns you and the rest look like an all-clear.

That rate limit is deliberate, and it is why the doctor is the instrument rather than the in-session
warning. Run it when you want to know.

## Shared runtime state is out of scope

A worktree isolates **files**. It does not isolate what a running program contends for. A listening
port, a development database, a Redis keyspace, a local service, a package cache, generated build
output and a git-ignored `.env` all sit outside what it separates.

Two sessions running the same test suite in two worktrees can collide on any of those, and **nothing
here sees it**. No gate reads a port or a database name, and neither does the doctor. It surfaces as
a flaky test or a corrupted fixture, blamed on anything but concurrency.

This is unsolved in this project rather than handled quietly. There is no control to install and
nothing to switch on. Two habits are the whole of it, and both are yours to apply:

- **Give each worktree its own environment.** `scripts/worktree/new.ps1` runs the per-checkout
  bootstrap named by `setupHook` in `ccx.config.json`, and warns when it cannot find that file.
  [Worktrees](WORKTREES.md) gives the contract the hook receives.
- **Choose ports and database names per worktree, by hand.** Nothing derives them for you. A setup
  hook that writes one port into every checkout has moved the collision, not removed it.

## Guardrails against accidents, not security boundaries

The `PreToolUse` gates inspect tool arguments. A file a shell command writes is invisible to them,
and an agent-authored script defeats a command-string rule.

**The reason they are not a boundary.** Every control here runs as the same operating-system
identity as the agent it constrains. The hook scripts, the repository allowlist at
`~/.claude/hooks/ccx-gate.repos.txt` and the user-scope settings file wiring them are all files that
identity may write.

An agent that edits one is not defeating a boundary. It is editing its own configuration, with the
permissions it was already given. Two documented exits need no editing at all:

- `--no-verify` on a commit or a push skips both git hooks. No CI-side enforcement ships.
- `CCX_ALLOW_DIRECT_PUSH=1` turns the push guard off. It is a deliberate escape hatch, kept distinct
  from `--no-verify` so it stays greppable in shell history, and the guard announces
  `direct push ALLOWED` on stderr when it fires.

The doctor lists that variable as a live disarm switch, but only when it is set in the doctor's own
environment. Prefixing a single `git push` with it leaves nothing for a later run to find.

**The remedy.** Enforcement the constrained identity cannot rewrite, which means a different plane
altogether:

| Pair with | Why it holds |
|---|---|
| Protected branches on the remote | The rule lives on the server. Editing a local hook does not reach it |
| Required status checks | A merge that waits on a check is not waved through by a flag on the pushing machine |
| Agent credentials with no bypass permission | Bypass is a permission. Withhold it from the token the agent pushes with |

**Nothing in this repository configures any of that for you.** Those are settings on your hosting
provider, `bin/ccx-doctor.ps1` does not read them, and this repository's own `gates` check is
advisory: nothing requires it before a merge.

## Everything here fails the same way it succeeds

When a control here breaks, it produces output byte-identical to when it works. An uninstalled gate
and a working one look the same from inside a session, because both let the edit through.

That is why `bin/ccx-doctor.ps1` exists, and why you run it *before* installing anything as well as
after. It never infers: it prints WHAT WAS SCANNED and BLIND SPOTS ON THIS RUN, and a skip is never
a pass (exit 2).

At least one deny path is not self-testable. The collision gate's refusal needs a live peer worktree
holding an uncommitted change to the same file. The doctor proves the gate speaks up when it cannot
check, not that it denies, and prints that gap as a blind spot every run.

## Related

| For | Read |
|---|---|
| Installing, and proving each control is live | [Quickstart](QUICKSTART.md) |
| Every control's event and its fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Proving the controls are actually running, as a method | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| One desktop instance per Claude account | [Desktop accounts](DESKTOP-ACCOUNTS.md) |
