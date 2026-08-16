# Several desktop instances, one per Claude account

## TLDR/BLUF

**What this is.** One Claude Desktop window per account on one Windows login, each from its own
shortcut. Electron keys its single-instance lock to the user-data directory: `--user-data-dir` is
the mechanism. The launcher sets `CLAUDE_CONFIG_DIR` as well, the source of `~/.claude-account-N`.

**Why you should care.** Each instance is a separate sign-in, a separate usage pool, and one more
config root to install every user-scope control into. Not for you if one account is enough, or if
the accounts must be isolated: profiles under one Windows login are not a security boundary.

**How to use it.** Copy [the launcher](#the-launcher-and-the-one-line-that-is-load-bearing) once per
account, point a shortcut at each copy, and sign in once per instance. Then run
[the two commands](#check-it-on-your-own-machine) that say which profile and config root a session
is on.

---

## Why a second instance normally does nothing

Claude Desktop is an Electron application, installed by Squirrel under `%LOCALAPPDATA%`:

```
%LOCALAPPDATA%\AnthropicClaude\claude.exe               <- version-stable stub launcher
%LOCALAPPDATA%\AnthropicClaude\Update.exe
%LOCALAPPDATA%\AnthropicClaude\app-<version>\claude.exe <- real binary, path changes on update
```

The single-instance lock is keyed to the **user-data directory**, which is why a second launch looks
like a no-op: it focuses the open window. Point one at a different user-data directory and you get a
separate main process, renderers, GPU process, crashpad handler and profile.

```powershell
& "$env:LOCALAPPDATA\AnthropicClaude\claude.exe" --user-data-dir="$env:USERPROFILE\.claude-desktop-N"
```

The sign-in lives inside that directory. That is what makes each instance a different account.

**Target the stub, never `app-<version>\claude.exe`.** The versioned path changes on every
auto-update, so a shortcut holding one stops launching after the next update. The stub forwards
`--user-data-dir` through to the versioned binary.

### Verified on 2026-08-14

One shortcut was invoked exactly as Windows invokes it, and the page was then written from a session
running inside one of these instances. Each row says how it was established.

| Claim | Evidence |
|---|---|
| The stub forwards `--user-data-dir` | The shortcut names the stub; the resulting process is `app-<version>\claude.exe` carrying the flag |
| The instance is separate, not a focused window | 10 processes carried the alternate profile path, beside a set carrying the default profile. The count moves with what the window has open |
| The launch is silent and visible | A window appeared, and no PowerShell console lingered |
| The default instance is unaffected | The pre-existing default-profile instance kept running throughout |
| The bundled Claude Code honors `CLAUDE_CONFIG_DIR` | `$env:CLAUDE_CONFIG_DIR` read `.claude-account-2`, with 4 session records under that root, from a session whose parent process is the desktop app |

The last row had been left open until this page. The launcher sets `CLAUDE_CONFIG_DIR` by analogy
with the editor launchers beside it, and the desktop app's own Claude Code does read it. Drop those
two lines if an instance misbehaves: `--user-data-dir` alone isolates the sign-in.

### Check it on your own machine

```powershell
$env:CLAUDE_CONFIG_DIR                                                   # this session's config root
(Get-CimInstance Win32_Process -Filter "Name='claude.exe'").CommandLine  # each instance's profile
```

---

## The launcher, and the one line that is load-bearing

Two layers, and the shortcut is the thin one:

1. A launcher script per account, at `%USERPROFILE%\claude-launchers\Launch-ClaudeDesktop-N.ps1`.
2. A desktop shortcut per account, targeting `powershell.exe` with
   `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<launcher path>"`.

```powershell
$ClaudeConfigDir = "$env:USERPROFILE\.claude-account-N"
$UserDataDir     = "$env:USERPROFILE\.claude-desktop-N"
$ClaudeExe       = "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"   # the stub, not app-<version>

$env:CLAUDE_CONFIG_DIR = $ClaudeConfigDir
if (-not (Test-Path $ClaudeConfigDir)) {
    New-Item -ItemType Directory -Path $ClaudeConfigDir -Force | Out-Null
}

$claudeArgs = @("--user-data-dir=`"$UserDataDir`"") + $args
Start-Process -FilePath $ClaudeExe -ArgumentList $claudeArgs -WindowStyle Normal
```

**`-WindowStyle Normal` on `Start-Process` is load-bearing.** The shortcut runs PowerShell hidden so
no console window lingers, and a child GUI process **inherits** that hidden state. Without it the
app starts with no visible window at all.

`$args` is appended so a file or folder dragged onto the shortcut still reaches the app.

### What each directory isolates

| Path | Isolates |
|---|---|
| `%USERPROFILE%\.claude-desktop-N` | The desktop app profile: sign-in, settings, cache, and that instance's `claude_desktop_config.json` |
| `%USERPROFILE%\.claude-account-N` | The Claude Code config root: credentials, settings, session records, transcripts |
| `%USERPROFILE%\claude-launchers` | Nothing. It is where the scripts live |

---

## What the extra config roots cost the tooling here

Five roots exist on the machine this was written on: `.claude`, plus `.claude-account-1` through
`.claude-account-4`. Three consequences follow, and they do not all cut the same way.

**Installing gets multiplied.** `install-selfheal.ps1` wires one config root per run: five roots,
five runs. The gate installer must reach every root a session can start under, and an unwired root
reads as governed from inside one ([Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md)).

**Reading crosses accounts.** The liveness fence scans every `~/.claude*` directory holding a
session registry, so presence, occupancy and overlap see peers under other accounts
([Coordination](COORDINATION.md)).

`scripts/worktree/sessions.ps1` prints the owning login as a column, which is how "which account was
that session in" gets answered ([Worktrees](WORKTREES.md)).

**Messaging does not.** `list_sessions` enumerates only sessions the app spawned, so each instance
sees only its own and announce reaches one account, not the machine. Unmeasured across instances
here: it follows from the mechanism under
[Limits](index.md#limits-read-before-installing).

---

## Behaviour to expect

- **The first launch of each shortcut opens a login screen.** The profile starts empty. After
  signing in, the session persists in that profile.
- **MCP servers are configured per profile.** Each profile carries its own
  `claude_desktop_config.json`, so a new instance starts with no connectors. Copy the file from
  `%APPDATA%\Claude` to reuse the default profile's.
- **The default profile is untouched.** It still opens from the Start menu or the taskbar, as an
  additional instance beside the numbered ones.
- **All instances group under one taskbar icon**, because they are one executable.
- **Deep links land wherever they land.** The protocol handler and the native-messaging bridge
  resolve to whichever instance registered them, so a `claude://` link will not reliably reach the
  instance you meant.
- **Each instance is a full Electron app.** Memory cost scales with the number of them.

### Limit: This is not a trust boundary

A separate Windows user account per identity gives a separate credential store and registry hive, at
the cost of fast user switching and a duplicated environment. `--user-data-dir` was chosen because
the requirement was several accounts, not a boundary. Revisit that if a real one is needed.

---

## The icon check that reported a false match

Shortcuts point their icon at the stub rather than the versioned binary, so the icon survives an
update. Confirming that the stub carries the real application icon rather than a placeholder meant
extracting both icons and hashing them.

**The first comparison was wrong, and it reported a match.** It hashed a `MemoryStream` without
rewinding it, so every input hashed as zero bytes and every value came out identical.

What caught it was a deliberate control. An unrelated system executable returned the *same* hash,
which is impossible if the instrument works. Rerun with the stream rewound, the controls came out
distinct and the stub matched the versioned binary exactly.

The lesson outlives the icons. A comparison that returns "equal" for inputs known to differ is
measuring nothing, and with no positive control it reads as a clean pass. Confirm the instrument
answers the question asked; the [drift audit](CASE-STUDY-drift-audit.md) is that method at scale.

---

## Related

| For | Read |
|---|---|
| Which surface to run several sessions on, and the channels between them | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| Finding a session across every login, and putting a relocated one back | [Worktrees](WORKTREES.md) |
| Presence, occupancy and overlap, which read every config root | [Coordination](COORDINATION.md) |
| Wiring each config root, and proving the wiring is live | [INSTALL.md](https://claude-multisession.pages.dev/INSTALL.md) |
| Every control's event and its fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Knowing when a pool is spent, which is per account | [Usage awareness](USAGE-AWARENESS.md) |
