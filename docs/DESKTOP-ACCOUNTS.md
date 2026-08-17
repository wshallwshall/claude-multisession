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
%LOCALAPPDATA%\AnthropicClaude\app-<version>\claude.exe <- the real binary, version in the path
%LOCALAPPDATA%\AnthropicClaude\claude.exe               <- stub launcher, NOT always present
%LOCALAPPDATA%\AnthropicClaude\Update.exe               <- Squirrel updater, NOT always present
```

Launch it a second time and it looks like a no-op: the window you already have takes focus. That is
the **single-instance lock, which is keyed to the user-data directory**. Point a launch at a
different one and you get a separate main process, renderers, GPU process, crashpad handler and
profile.

```powershell
& "$env:LOCALAPPDATA\AnthropicClaude\app-<version>\claude.exe" --user-data-dir="$env:USERPROFILE\.claude-desktop-N"
```

The sign-in lives inside that directory. That is what makes each instance a different account.

**Resolve the newest installed `app-*` directory. Do not hardcode a version, and do not depend on
the stub.** A manual or backup install does not create `%LOCALAPPDATA%\AnthropicClaude\claude.exe`,
and an install that has one can lose it on reinstall.

**`-Directory` is load-bearing here.** Blocked versions are left behind as placeholder *files* with
the same `app-<version>` name. This machine holds `app-1.30096.1` and `app-1.30096.5` at 381 and
563 bytes, against one real install, `app-1.25927.0` -- which sorts lowest.

### Verified on 2026-08-14

One shortcut was invoked exactly as Windows invokes it. The page was then written from a session
running inside one of these instances. Each row says how the claim was established.

| Claim | Evidence |
|---|---|
| The stub forwarded `--user-data-dir` | The shortcut named the stub; the resulting process was `app-<version>\claude.exe` carrying the flag |
| The instance is separate, not a focused window | 10 processes carried the alternate profile path, beside a set carrying the default profile. The count moves with what the window has open |
| The launch is silent and visible | A window appeared, and no PowerShell console lingered |
| The default instance is unaffected | The pre-existing default-profile instance kept running throughout |
| The bundled Claude Code honors `CLAUDE_CONFIG_DIR` | `$env:CLAUDE_CONFIG_DIR` read `.claude-account-2`, with 4 session records under that root, from a session whose parent process is the desktop app |

**Corrected on 2026-08-17: the stub is gone.** A reinstall removed both
`%LOCALAPPDATA%\AnthropicClaude\claude.exe` and `Update.exe`, breaking every launcher naming it at
once. Read the first row as history, not as instruction.

`CLAUDE_CONFIG_DIR` was carried through on the strength of the last row, not by design: the desktop
app's own Claude Code reads the variable its parent process set.

---

## The launcher, and the one line that is load-bearing

**The goal.** One shortcut per account, each opening a window already signed in to that account.

**What to do.** Build two layers per account, and the shortcut is the thin one:

1. A launcher script, at `%USERPROFILE%\claude-launchers\Launch-ClaudeDesktop-N.ps1`. Replace `N`
   with the account number in each copy.
2. A desktop shortcut targeting `powershell.exe` with
   `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<launcher path>"`.
3. That shortcut's **Change Icon**, pointed at
   `%LOCALAPPDATA%\AnthropicClaude\app-<version>\claude.exe`. Skip it and every shortcut shows the
   PowerShell icon, leaving N accounts indistinguishable on the desktop and in the taskbar.

```powershell
$ClaudeConfigDir = "$env:USERPROFILE\.claude-account-N"
$UserDataDir     = "$env:USERPROFILE\.claude-desktop-N"
$ClaudeRoot      = "$env:LOCALAPPDATA\AnthropicClaude"

$ClaudeExe = Get-ChildItem $ClaudeRoot -Filter 'app-*' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^app-\d+(\.\d+){1,3}$' -and (Test-Path (Join-Path $_.FullName 'claude.exe')) } |
    Sort-Object { [version]$_.Name.Substring(4) } |
    Select-Object -Last 1 |
    ForEach-Object { Join-Path $_.FullName 'claude.exe' }
if (-not $ClaudeExe) { throw "No installed Claude Desktop under $ClaudeRoot (need app-<version>\claude.exe)." }

$env:CLAUDE_CONFIG_DIR = $ClaudeConfigDir
if (-not (Test-Path $ClaudeConfigDir)) {
    New-Item -ItemType Directory -Path $ClaudeConfigDir -Force | Out-Null
}

$claudeArgs = @("--user-data-dir=`"$UserDataDir`"") + ($args | ForEach-Object { "`"$_`"" })
Start-Process -FilePath $ClaudeExe -ArgumentList $claudeArgs -WindowStyle Normal
```

**What happens next.** The first run of a shortcut opens an empty profile at a login screen. Sign in
once, and that account stays signed in behind that shortcut.

**`-WindowStyle Normal` on `Start-Process` is load-bearing.** The shortcut runs PowerShell hidden so
no console window lingers, and a child GUI process **inherits** that hidden state. Without it the
app starts with no visible window at all.

**Hidden also hides every error this launcher can raise.** A missing install, an unwritable config
root or a mistyped path prints to a console you never see, so the shortcut reads as having done
nothing. Run the `.ps1` directly in a visible `pwsh` to see the error.

**The icon is the one version-pinned field in the setup.** It stops resolving after an update and
has to be reset by hand. Nothing else is: the launcher re-resolves the binary on every run, which is
the whole point of resolving it rather than writing it down.

**If an instance misbehaves, delete all three `CLAUDE_CONFIG_DIR` pieces**: the `$ClaudeConfigDir`
assignment, the `$env:` line, and the `Test-Path`/`New-Item` block. Leave one and it points at a
variable that no longer exists. `--user-data-dir` alone still isolates the sign-in.

**Price that before doing it.** That instance's Claude Code falls back to `~/.claude`, shared with
every other instance: one credential store, one session registry, and `sessions.ps1` reporting
`desktop` for all of them. Nothing on screen changes, which is what makes it easy to miss.

`$args` is appended so a file or folder dragged onto the shortcut still reaches the app. Each
element carries its own quotes because `Start-Process -ArgumentList` joins with spaces and quotes
nothing, so an unquoted dropped path with a space would arrive as two arguments.

### What each directory isolates

| Path | Isolates |
|---|---|
| `%USERPROFILE%\.claude-desktop-N` | The desktop app profile: sign-in, settings, cache, and that instance's `claude_desktop_config.json` |
| `%USERPROFILE%\.claude-account-N` | The Claude Code config root: credentials, settings, session records, transcripts |
| `%USERPROFILE%\.claude-account-N.lock` | Nothing. A lock artefact that is a DIRECTORY, not a config root. Never wire it: the name matches the `.claude-account-*` glob, and two installers here once did |
| `%USERPROFILE%\claude-launchers` | Nothing. It is where the scripts live |

### Check it on your own machine

**The goal.** Find out which account a session is really on, and which profile each open window is
running under.

**What to do.** Run both lines in the session you want to check.

```powershell
if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { "UNSET -- default ~/.claude" }
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | ForEach-Object {
    if ($_.CommandLine -match '--user-data-dir="([^"]+)"')  { $matches[1] }
    elseif ($_.CommandLine -match '--user-data-dir=([^"\s]+)') { $matches[1] }
} | Sort-Object -Unique
```

**What happens next.** The first prints a full path, such as `C:\Users\<you>\.claude-account-2`.
`UNSET` is an answer rather than a failure: no launcher sets the variable for the default instance,
so that session is on the default root, `%USERPROFILE%\.claude`.

**The second prints one path per open instance**, the default one included, as `%APPDATA%\Claude`.
A raw `.CommandLine` dump will not answer this. Bundled Claude Code processes share the name but
carry no `--user-data-dir`, and each crashpad handler repeats the path with more flags.

---

## What the extra config roots cost the tooling here

Five roots exist on the machine this was written on: `.claude`, plus `.claude-account-1` through
`.claude-account-4`. Three consequences follow, and they do not all cut the same way.

**Installing gets multiplied.** Two installers take one config root per run:
`install-coordination.ps1` (`-SettingsPath`) and `install-selfheal.ps1` (`-ConfigDir`). Five roots
means five runs of each. `install-gate.ps1` alone covers every root in one run
([INSTALL.md](INSTALL.md)).

Every user-scope control must reach every root a session can start under: an unwired root reads as
governed from inside a session
([Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md)).

**Reading crosses accounts.** The liveness fence scans every `~/.claude*` directory holding a
session registry, so presence, occupancy and overlap see peers under other accounts
([Coordination](COORDINATION.md)).

`scripts/worktree/sessions.ps1` prints the owning login as a column, which is how "which account was
that session in" gets answered ([Scripts](SCRIPTS.md)).

**Messaging does not.** `list_sessions` enumerates only sessions the app spawned, so an announce
reaches one account, not the machine. That was not measured here; it follows from the mechanism
under [Limits](LIMITS.md). [Session mail](SESSION-MAIL.md) states this case and the lane for it.

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

The icon came from the stub while the stub existed, and checking that it carried the real
application icon rather than a placeholder meant extracting both icons and hashing them.

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
| Finding a session across every login, and putting a relocated one back | [Scripts](SCRIPTS.md), [Worktrees](WORKTREES.md) |
| Reaching a peer under another account, which announce cannot | [Session mail](SESSION-MAIL.md) |
| Presence, occupancy and overlap, which read every config root | [Coordination](COORDINATION.md) |
| Wiring each config root, and proving the wiring is live | [INSTALL.md](INSTALL.md) |
| Every control's event and its fail-open or fail-closed posture | [Hooks](HOOKS.md) |
| Knowing when a pool is spent, which is per account | [Usage awareness](USAGE-AWARENESS.md) |
