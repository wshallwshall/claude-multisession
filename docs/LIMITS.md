# Limits and requirements

## TLDR/BLUF

**What this is.** What KORUS needs to run, and the places it stops working. Both were on the
landing page, above the first command, until 2026-08-16.

**Why you should care.** Three of these limits come from one fact: session discovery rests on a
vendor surface this project does not own. Read them before you trust a green report. Not for you if
you have not installed anything yet, in which case start at [Quickstart](QUICKSTART.md).

**How to use it.** Check the requirements table, then read the limit that matches your setup. The
CLI-only limit is the one that changes what you install.

---

## Requirements

| Need | Without it |
|---|---|
| **Claude Code for Desktop** | KORUS is a desktop framework. A CLI-only or editor-extension setup is not supported, and the coordination layer is shaped around the desktop client. See below. |
| **PowerShell 7.3+** (`pwsh`) | Nothing installs. Most scripts carry `#Requires -Version 7.3`. |
| **git** | Nothing installs. Everything is keyed on the git common directory. |
| **`python` on `PATH`** (or `CCX_PYTHON`) | The installed git gates are OFF and say so on stderr. Needed by the three git-hook checkers and the leak gate. |
| **`ccx.config.json` at the target repo root** | User-scope hooks stay inert in that repo. It is both the knob file and the opt-in marker. |

PowerShell 7 runs on Linux and macOS, but Windows is the exercised path. Self-marking and path
case-folding degrade elsewhere.

**There is no `ccx` on `PATH`.** Where these documents say `ccx doctor`, they mean
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`.
[MIT](https://claude-multisession.pages.dev/LICENSE).

## Platform support

`.github/workflows/gates.yml` holds the CI matrix, and it names two operating systems.

| Platform | Status | What degrades |
|---|---|---|
| **Windows, PowerShell 7.3+** | The exercised path. In CI as `windows-latest` | Nothing known. This is the platform the defaults assume |
| **Linux, PowerShell 7.3+** | In CI as `ubuntu-latest` | Path comparison stops folding case, and roster self-marking degrades. Both are named in the note under Requirements above |
| **macOS** | **Not tested.** It is not in the CI matrix | `ccx doctor` prints its non-Windows blind spot there, but nothing in CI covers macOS. Treat it as unmeasured rather than working |
| **Windows PowerShell 5.1** | Unsupported | `#Requires -Version 7.3` refuses to start most scripts there, and `powershell.exe` is a separate executable from `pwsh` |

CI is not the doctor. Those runners execute the ASCII gate, the leak scan, a parse of every shipped
`.ps1` and the test suite on both platforms. They do not run `ccx doctor`, and the workflow's own
header says why: some controls it fires need a live second session and a peer worktree.

So a green Linux run says the scripts parse and the suite passes there. Whether the hooks, the
gates and the roster behave on Linux in a real session is not established by it.

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
