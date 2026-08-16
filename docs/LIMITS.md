# Limits and requirements

## TLDR/BLUF

**What this is.** What KORUS needs to run, and the four places it stops working. Both were on the
landing page, above the first command, until 2026-08-16.

**Why you should care.** Three of the four limits come from one fact: session discovery rests on a
vendor surface this project does not own. Read them before you trust a green report. Not for you if
you have not installed anything yet, in which case start at [Quickstart](QUICKSTART.md).

**How to use it.** Check the requirements table, then read the limit that matches your setup. The
CLI-only row is the one that changes what you install.

---

## Requirements

| Need | Without it |
|---|---|
| **PowerShell 7.3+** (`pwsh`) | Nothing installs. Most scripts carry `#Requires -Version 7.3`. |
| **git** | Nothing installs. Everything is keyed on the git common directory. |
| **`python` on `PATH`** (or `CCX_PYTHON`) | The installed git gates are OFF and say so on stderr. Needed by the three git-hook checkers and the leak gate. |
| **`ccx.config.json` at the target repo root** | User-scope hooks stay inert in that repo. It is both the knob file and the opt-in marker. |

PowerShell 7 runs on Linux and macOS, but Windows is the exercised path. Self-marking and path
case-folding degrade elsewhere.

**There is no `ccx` on `PATH`.** Where these documents say `ccx doctor`, they mean
`pwsh -NoProfile -File <this-checkout>/bin/ccx-doctor.ps1`.
[MIT](https://claude-multisession.pages.dev/LICENSE).

## Session discovery rests on a vendor surface this project does not own

Everything answering "who is live, and where" reads `<config-root>/sessions/<pid>.json` -- a record
the *client* writes, whose shape, location and lifetime belong to the client. Three consequences
follow.

**Announce needs the desktop client.** It delivers through `ccd_session_mgmt`, an MCP server a plain
CLI install lacks. The hook never sends: it asks the model to, so nothing is delivered and the model
says so. **If you are CLI-only, leave that one hook uninstalled** -- nothing else depends on it.

**The desktop app's own session list is incomplete.** `list_sessions` enumerates only sessions *that
app itself spawned*. An editor-extension session is never registered, so it cannot be messaged. It
is authoritative for who can be **messaged**, the on-disk records for who **exists**.

**A schema change degrades to "cannot tell", not to a wrong answer.** Rename a field or change
`startedAt`'s unit and every fence says it cannot tell -- designed for in
`scripts/coord/session-registry.ps1`. The doctor prints records read and placed, so the change
surfaces as a count going to zero.

## Guardrails against accidents, not security boundaries

The `PreToolUse` gates inspect tool arguments. A file a shell command writes is invisible to them,
and an agent-authored script defeats a command-string rule.

`--no-verify` on commit or push bypasses both git hooks. No CI-side enforcement ships.

## Everything here fails the same way it succeeds

When a control here breaks, it produces output byte-identical to when it works. An uninstalled gate
and a working one look the same from inside a session, because both let the edit through.

That is why `bin/ccx-doctor.ps1` exists, and why you run it *before* installing anything as well as
after. It never infers: it prints WHAT WAS SCANNED and BLIND SPOTS ON THIS RUN, and a skip is never
a pass (exit 2).

At least one deny path is not self-testable. The collision gate's needs a live peer worktree holding
an uncommitted change to the same file, so the doctor proves only that the gate refuses to go
*silent*, and prints that as a blind spot every run.

## Related

| For | Read |
|---|---|
| Installing, and proving each control is live | [Quickstart](QUICKSTART.md) |
| Every control's event and its fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Proving the controls are actually running, as a method | [Drift audit case study](CASE-STUDY-drift-audit.md) |
| One desktop instance per Claude account | [Desktop accounts](DESKTOP-ACCOUNTS.md) |
