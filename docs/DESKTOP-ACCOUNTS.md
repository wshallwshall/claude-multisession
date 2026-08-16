# Several desktop instances, one per Claude account

## TLDR/BLUF

**What this is.** Several Claude Desktop windows open at once on one Windows login, each signed in
to a different Claude account. You get there with one shortcut per account, each pointing the app at
its own profile directory.

**Why you should care.** Each instance is its own sign-in and its own usage pool, so one spent pool
does not stop the work. Each is also a config root to wire. Not for you if one account is enough, or
if the accounts must be isolated: profiles under one Windows login are not a security boundary.

**How to use it.** Copy [the launcher](#the-launcher-and-the-one-line-that-is-load-bearing) once per
account, point a shortcut at each copy, and sign in once per instance. Then run
[the two commands](#check-it-on-your-own-machine) that say which profile and config root a session
is on.

---

## Why a second instance normally does nothing

Claude Desktop is an Electron application, installed by Squirrel under `%LOCALAPPDATA%`:

<!-- no-copy -->
```
%LOCALAPPDATA%\AnthropicClaude\claude.exe               <- version-stable stub launcher
%LOCALAPPDATA%\AnthropicClaude\Update.exe
%LOCALAPPDATA%\AnthropicClaude\app-<version>\claude.exe <- real binary, path changes on update
```

Launch it a second time and it looks like a no-op: the window you already have takes focus. That is
the **single-instance lock, which is keyed to the user-data directory**. Point a launch at a
different one and you get a separate main process, renderers, GPU process, crashpad handler and
profile.

```powershell
& "$env:LOCALAPPDATA\AnthropicClaude\claude.exe" --user-data-dir="$env:USERPROFILE\.claude-desktop-N"
```

The sign-in lives inside that directory. That is what makes each instance a different account.

**Target the stub, never `app-<version>\claude.exe`.** The versioned path changes on every
auto-update, so a shortcut holding one stops launching after the next update. The stub forwards
`--user-data-dir` through to the versioned binary.

### Verified on 2026-08-14

One shortcut was invoked exactly as Windows invokes it. The page was then written from a session
running inside one of these instances. Each row says how the claim was established.

| Claim | Evidence |
|---|---|
| The stub forwards `--user-data-dir` | The shortcut names the stub; the resulting process is `app-<version>\claude.exe` carrying the flag |
| The instance is separate, not a focused window | 10 processes carried the alternate profile path, beside a set carrying the default profile. The count moves with what the window has open |
| The launch is silent and visible | A window appeared, and no PowerShell console lingered |
| The default instance is unaffected | The pre-existing default-profile instance kept running throughout |
| The bundled Claude Code honors `CLAUDE_CONFIG_DIR` | `$env:CLAUDE_CONFIG_DIR` read `.claude-account-2`, with 4 session records under that root, from a session whose parent process is the desktop app |

The last row had been left open until this page. The launcher sets `CLAUDE_CONFIG_DIR` by analogy
with the editor launchers beside it, and the desktop app's own Claude Code does read it. **Drop
those two lines if an instance misbehaves**: `--user-data-dir` alone isolates the sign-in.

### Check it on your own machine

**The goal.** Find out which account a session is really on, and which profile each open window is
running under.

**What to do.** Run both lines in the session you want to check.

```powershell
$env:CLAUDE_CONFIG_DIR                                                   # this session's config root
(Get-CimInstance Win32_Process -Filter "Name='claude.exe'").CommandLine  # each instance's profile
```

**What happens next.** The first prints one path, such as `.claude-account-2`. The second prints one
line per running process, and each numbered instance carries its own `--user-data-dir`.

---

## The launcher, and the one line that is load-bearing

**The goal.** One shortcut per account, each opening a window already signed in to that account.

**What to do.** Build two layers per account, and the shortcut is the thin one:

1. A launcher script, at `%USERPROFILE%\claude-launchers\Launch-ClaudeDesktop-N.ps1`. Replace `N`
   with the account number in each copy.
2. A desktop shortcut targeting `powershell.exe` with
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

**What happens next.** The first run of a shortcut opens an empty profile at a login screen. Sign in
once, and that account stays signed in behind that shortcut.

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
five runs. Every user-scope control must reach every root a session can start under: an unwired
root reads as governed from inside a session
([Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md)).

**Reading crosses accounts.** The liveness fence scans every `~/.claude*` directory holding a
session registry, so presence, occupancy and overlap see peers under other accounts
([Coordination](COORDINATION.md)).

`scripts/worktree/sessions.ps1` prints the owning login as a column, which is how "which account was
that session in" gets answered ([Worktrees](WORKTREES.md)).

**Messaging does not.** `list_sessions` enumerates only sessions the app spawned. Each instance sees
only its own, so an announce reaches one account rather than the machine. That was not measured
across instances here: it follows from the mechanism under [Limits](LIMITS.md).

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
  resolve to whichever instance registered them. A `claude://` link will not reliably reach the
  instance you meant.
- **Each instance is a full Electron app.** Memory cost scales with the number of them.

### Limit: This is not a trust boundary

A separate Windows user account per identity gives a separate credential store and registry hive, at
the cost of fast user switching and a duplicated environment. `--user-data-dir` was chosen because
the requirement was several accounts, not a boundary. Revisit that if a real one is needed.

---

## The icon check that reported a false match

Shortcuts point their icon at the stub rather than the versioned binary, so the icon survives an
update. Checking that the stub carries the real application icon, not a placeholder, meant
extracting both icons and hashing them.

**The first comparison was wrong, and it reported a match.** It hashed a `MemoryStream` without
rewinding it, so every input hashed as zero bytes and every value came out identical.

What caught it was a deliberate control. An unrelated system executable returned the *same* hash,
which is impossible if the instrument works. Rerun with the stream rewound, the controls came out
distinct and the stub matched the versioned binary exactly.

The lesson outlives the icons. A comparison that returns "equal" for inputs known to differ is
measuring nothing, and with no positive control it reads as a clean pass. Confirm the instrument
answers the question you asked. The [drift audit](CASE-STUDY-drift-audit.md) is that method at
scale.

---

## Related

| For | Read |
|---|---|
| Which surface to run several sessions on, and the channels between them | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| Finding a session across every login, and putting a relocated one back | [Worktrees](WORKTREES.md) |
| Presence, occupancy and overlap, which read every config root | [Coordination](COORDINATION.md) |
| Wiring each config root, and proving the wiring is live | [INSTALL.md](INSTALL.md) |
| Every control's event and its fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Knowing when a pool is spent, which is per account | [Usage awareness](USAGE-AWARENESS.md) |
