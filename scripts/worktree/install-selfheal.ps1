#Requires -Version 7
<#
.SYNOPSIS
    Wire the worktree-selfheal SessionStart backstop into ONE Claude Code config dir's settings.json.

.DESCRIPTION
    Idempotent. MERGES (never clobbers) a SessionStart hook that runs the shared worktree-selfheal.ps1;
    existing hooks and top-level keys are preserved. Backs up settings.json, validates the written
    JSON, and rolls back on any failure.

    Run once per config dir a session can use. Typically that is the default ~/.claude plus any
    ~/.claude-account-N created by a launcher that sets CLAUDE_CONFIG_DIR. The hook SCRIPT lives ONCE
    at a shared, login-agnostic path (~/.claude/hooks/) referenced by all of them, so only the wiring
    is per-dir.

    ONE ALLOWLIST, shared with the PreToolUse gate installer (install-gate.ps1), at
    ~/.claude/hooks/ccx-gate.repos.txt. That is deliberate and was learned the hard way: two
    components once read two DIFFERENT allowlist files, one installer rewrote its own unconditionally
    while the other seeded a second copy only if absent, and nothing kept them in sync. Adding a
    governed repo through one installer never reached the other, and uninstalling the gate left this
    backstop armed and still willing to run `git checkout` on the shared primary. They agreed only by
    luck. Two components deriving one filename separately is the same bug waiting to happen -- hence
    one fixed name, written here.

    See worktree-selfheal.ps1 and anthropics/claude-code#76590 for what this backstop repairs.

.EXAMPLE
    pwsh -NoProfile -File scripts/worktree/install-selfheal.ps1 -ConfigDir ~/.claude
#>
param(
    [Parameter(Mandatory)][string]$ConfigDir,
    # NO DEFAULT HERE, deliberately. Parameter defaults are evaluated during BINDING, before the first
    # line of the body -- so a default that throws preempts the CLAUDECODE guard below and the script
    # dies with an unrelated error instead of refusing. That is exactly what happened: the default was
    # `Join-Path $env:USERPROFILE ...`, and off Windows $env:USERPROFILE is NULL, so on Linux CI the
    # installer crashed with "Cannot bind argument to parameter 'Path' because it is null" and the
    # refusal never ran. A GUARD IS ONLY A GUARD IF NOTHING CAN RUN AHEAD OF IT.
    [string]$HookPath
)
$ErrorActionPreference = 'Stop'

# This installer wires a user-scope SessionStart hook that runs `git checkout` on the shared primary
# UNATTENDED, from a script the calling session can freely edit. It is the more privileged of the two
# installers here, so it refuses inside a session for the same reason its sibling does.
if ($env:CLAUDECODE -eq '1') {
    throw "Refusing to run inside Claude Code. This installs a user-scope hook that repairs the shared primary unattended, from a script the calling session can edit. Run it from a plain pwsh terminal."
}

# Home directory, null-safely. $env:USERPROFILE is Windows-only and is NULL elsewhere; honour it when
# set (tests and login swaps rely on overriding it) and fall back to the .NET accessor, which resolves
# $HOME on Unix. Every script in this family uses the same idiom.
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
if (-not $HookPath) { $HookPath = Join-Path $homeDir '.claude/hooks/worktree-selfheal.ps1' }

if (-not (Test-Path -LiteralPath $ConfigDir)) { throw "Config dir not found: $ConfigDir" }
$settingsPath = Join-Path $ConfigDir 'settings.json'

# --- Ensure the shared, login-agnostic hook script + allowlist exist (idempotent) -----------------
# One script copy, referenced by every config dir's wiring, so a login swap cannot drop it. It lives
# OUTSIDE every working tree: a hook script inside a checkout vanishes on a branch switch, and a hook
# whose script is missing fails in a way that lets the session proceed with nothing said.
$sharedDir = Split-Path -Parent $HookPath
New-Item -ItemType Directory -Force -Path $sharedDir | Out-Null
$canonical = Join-Path $PSScriptRoot 'worktree-selfheal.ps1'
if (Test-Path -LiteralPath $canonical) { Copy-Item -LiteralPath $canonical -Destination $HookPath -Force }
elseif (-not (Test-Path -LiteralPath $HookPath)) { throw "worktree-selfheal.ps1 not found beside this installer or at $HookPath." }

$reposFile = Join-Path $sharedDir 'ccx-gate.repos.txt'
if (-not (Test-Path -LiteralPath $reposFile)) {
    Set-Content -LiteralPath $reposFile -Encoding utf8 -Value @(
        '# Primary checkouts guarded by the SessionStart backstop and the PreToolUse worktree gate.'
        '# One absolute path per line. Deleting this file turns BOTH of them off, immediately.'
    )
}

$raw = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw } else { '{}' }
$cfg = $raw | ConvertFrom-Json
if ($null -eq $cfg) { $cfg = [pscustomobject]@{} }

# Ensure .hooks exists.
if (-not ($cfg.PSObject.Properties.Name -contains 'hooks') -or $null -eq $cfg.hooks) {
    $cfg | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{}) -Force
}

# Existing SessionStart groups (preserve them).
$groups = @()
if (($cfg.hooks.PSObject.Properties.Name -contains 'SessionStart') -and $cfg.hooks.SessionStart) {
    $groups = @($cfg.hooks.SessionStart)
}

# The receipt. INSTALLED is a fact about the file on disk, so it is answered by hashing it -- never by
# whether settings.json mentions it. A settings entry pointing at a script that is not there reads
# exactly like a healthy hook with nothing to say. WIRED is the separate fact below.
$sha = (Get-FileHash -LiteralPath $HookPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
Write-Host "hook script : $HookPath  sha $sha"
Write-Host "allowlist   : $reposFile"

# Idempotency: bail if any SessionStart hook already runs our script. The script copy above has
# already been refreshed, so a second run still updates a stale installed copy.
foreach ($g in $groups) {
    foreach ($h in @($g.hooks)) {
        if ("$($h.command)" -match 'worktree-selfheal') {
            Write-Host "[$ConfigDir] WIRED already -- wiring unchanged, hook script refreshed."
            return
        }
    }
}

# Append our group.
$entry = [pscustomobject]@{
    hooks = @([pscustomobject]@{
            type          = 'command'
            command       = "pwsh -NoProfile -File `"$HookPath`""
            timeout       = 30
            statusMessage = 'Worktree self-heal'
        })
}
$groups = @($groups) + $entry
$cfg.hooks | Add-Member -NotePropertyName 'SessionStart' -NotePropertyValue $groups -Force

# Backup -> write -> validate -> roll back on failure. settings.json is live config for every session
# on this machine, so an invalid write breaks all of them at once.
if (Test-Path -LiteralPath $settingsPath) {
    Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak-selfheal" -Force
}
$json = $cfg | ConvertTo-Json -Depth 40
Set-Content -LiteralPath $settingsPath -Value $json -Encoding utf8
try {
    $null = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Write-Host "[$ConfigDir] WIRED + valid JSON."
} catch {
    if (Test-Path -LiteralPath "$settingsPath.bak-selfheal") {
        Copy-Item -LiteralPath "$settingsPath.bak-selfheal" -Destination $settingsPath -Force
    }
    throw "[$ConfigDir] produced invalid JSON; rolled back. $_"
}

Write-Host ""
Write-Host "The backstop is INERT until the allowlist names a primary checkout. Add one with:"
Write-Host "  pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Repo <primary-checkout-to-govern>"
Write-Host "(or edit $reposFile by hand -- one absolute path per line)."
