#Requires -Version 7.3
<#
.SYNOPSIS
    Wire the three coordination hooks at USER scope, so they load in EVERY worktree -- not only the
    ones that happen to carry a project settings file.

.DESCRIPTION
    THE PROBLEM THIS FIXES. The coordination hooks are useless unless every session loads them, and
    wiring them into the PROJECT settings file `<worktree>/.claude/settings.json` does not achieve
    that. `.claude/` is commonly gitignored, so git cannot deliver it to a new worktree: worktrees the
    harness creates under `.claude/worktrees/` get a copy, worktrees created as siblings of the primary
    do NOT. Measured on the repo this was developed in: more than half the worktrees had no project
    settings at all, and a live editor session was working in one of them with zero coordination
    context -- it could not see the other sessions, and they could not see it.

    That is fatal to the whole idea. You cannot make sessions coordinate when the mechanism does not
    load for half of them, and the half it misses is invisible rather than obviously broken.

    THE FIX: wire at USER scope (~/.claude/settings.json), which is per-machine and loads in every
    worktree regardless of how that worktree was created.

    NO INSTALLED COPY. Each hook is a one-line shim that locates the script in a checkout and runs it,
    so there is nothing to fall stale: after a pull the hook is current everywhere, immediately. This
    is deliberate -- a sibling installer copies its script instead, and running that one from a stale
    checkout has silently downgraded a live gate.

    THE PRICE OF A SHIM, AND WHY -Status LOOKS LIKE IT DOES. A shim that resolves nothing exits
    silently and writes nothing, which is byte-identical to a healthy hook with nothing to report.
    That failure mode is how a wired-but-resolving-nothing hook survived for weeks here. So this script
    writes a RECEIPT of exactly what it wired, and -Status answers from the receipt plus a live
    re-resolution of every target script -- never from "there is an entry in settings.json". An entry
    in settings.json is a CLAIM. A receipt plus a target that actually resolves is EVIDENCE.

    THE SHIM RESOLVES THE PRIMARY CHECKOUT, not the calling worktree, and that order matters.
    Coordination is INFRASTRUCTURE and has to be uniform: two sessions running different versions of
    the collision protocol is precisely the drift the shared liveness fence exists to prevent. Measured
    on the repo this was developed in: a worktree sitting on a branch that predated the coordination
    merge had none of these scripts, so a cwd-resolved shim found nothing and exited silently -- that
    session got no banner and no gate, and nothing reported the absence. The primary tracks trunk, so
    every session runs the same current code whatever branch it is on. The calling worktree is kept
    only as a fallback, for a layout where the primary is unavailable.

    WHAT GETS WIRED
      SessionStart                             -> scripts/worktree/session-context.ps1
                                                  (who else is live, and what they are building)
      PreToolUse Edit|Write|MultiEdit|Notebook -> scripts/hooks/collision_gate.ps1
                                                  (refuse a file a live session is already changing)
      UserPromptSubmit                         -> scripts/hooks/announce-session.ps1
                                                  (tell the peers you exist, and what you intend)

    Idempotent: re-running replaces our own entries and leaves every other hook untouched.

    Run from a plain terminal, NOT from inside Claude Code. A session that can wire these hooks can
    unwire them, and these are the hooks by which peers see each other -- a session that removes them
    makes itself invisible to everyone else while still looking coordinated to itself. -Status is
    exempt: auditing is not installing.

.EXAMPLE
    pwsh -NoProfile -File scripts/coord/install-coordination.ps1 -Status
    pwsh -NoProfile -File scripts/coord/install-coordination.ps1
    pwsh -NoProfile -File scripts/coord/install-coordination.ps1 -Uninstall
    pwsh -NoProfile -File scripts/coord/install-coordination.ps1 -Only UserPromptSubmit -Uninstall
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Status,
    [switch]$Uninstall,

    # Settings file to modify. NO DEFAULT HERE, deliberately: parameter defaults are evaluated during
    # BINDING, before the first line of the body, so a default that throws pre-empts the refusal guard
    # below and the script dies with an unrelated error instead of refusing. The obvious default --
    # Join-Path $env:USERPROFILE ... -- does exactly that off Windows, where $env:USERPROFILE is null
    # and Join-Path raises a binding error. A guard is only a guard if nothing can run ahead of it.
    [string]$SettingsPath,

    # Limit the operation to these events (install, uninstall and -Status alike). Announce lives on its
    # own event, so `-Only UserPromptSubmit -Uninstall` removes it WITHOUT disarming the collision gate
    # or the SessionStart banner. Without this the only 2am remedy is a hand-edit of the user settings.
    [string[]]$Only,
    [string[]]$Except
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_common.ps1"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RepoRoot = (Resolve-Path (Join-Path $RepoRoot "..")).Path

if (-not $SettingsPath) {
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
    $SettingsPath = Join-Path (Join-Path $homeDir ".claude") "settings.json"
}
$SettingsDir = Split-Path -Parent $SettingsPath
$ReceiptPath = Join-Path $SettingsDir "ccx-coordination.receipt.json"

# ------------------------------------------------------------------------------------------ markers

# Marker so we can find and replace exactly our own entries on a re-install, without disturbing hooks
# another tool (or another session) added to the same file.
$MARKER = "ccx-coord"

# A SEPARATE marker for the announce hook, deliberately. Two reasons; the second is the durable one:
#
#   * Test-IsOurs is a SUBSTRING match, so any marker CONTAINING the other -- "ccx-coord-announce",
#     say -- would be stripped by every managed event's removal loop. NEITHER OF THESE TWO STRINGS
#     CONTAINS THE OTHER, IN EITHER DIRECTION. That is a constraint on any future rename, not an
#     accident of spelling: pick a new pair and check both containments before you commit it.
#   * The blast radii differ. A SessionStart or PreToolUse failure degrades coordination; a
#     UserPromptSubmit failure can block the user's prompt outright. Being able to remove announce
#     alone (-Only UserPromptSubmit -Uninstall) without disarming the collision gate is worth one
#     extra literal.
#
# The same reasoning applies across projects: a sibling project's installer may wire its own entries
# into this same user settings file, and as long as neither marker contains the other, neither
# installer can delete the other's hook.
$ANNOUNCE_MARKER = "ccx-announce"

# ------------------------------------------------------------------------------------------- shims

# The shim. No installed copy: it locates the script in a checkout and runs it, so a pull updates the
# hook everywhere with nothing to fall stale. Silent and exit-0 outside a repository, because this
# entry is user-global and runs in every unrelated project on the machine.
function New-ShimCommand([string]$RelativeScript, [string]$Marker = $MARKER) {
    return (
        "# $Marker`n" +
        '$c = (& git rev-parse --path-format=absolute --git-common-dir 2>$null); ' +
        'if ($LASTEXITCODE -eq 0 -and $c) { ' +
        '$bases = @((Split-Path $c.Trim() -Parent), (& git rev-parse --path-format=absolute --show-toplevel 2>$null)); ' +
        'foreach ($b in $bases) { ' +
        'if (-not $b) { continue } ' +
        "`$s = Join-Path `$b.Trim() '$RelativeScript'; " +
        'if (Test-Path -LiteralPath $s) { & $s; break } } }'
    )
}

# The announce shim differs from the shared one in exactly two ways, and it is a SEPARATE builder
# rather than a flag on New-ShimCommand for a mechanical reason: it appends `-CommonDir $c`, and the
# other two scripts would ERROR on an unexpected parameter.
#
# WHY THE MISSING-SCRIPT NOTICE EXISTS. Every receipt, marker and visible line the hook writes lives
# INSIDE the script -- strictly downstream of the resolution failure that IS the historical bug.
# Measured from a worktree on the repo this was developed in: both probe bases returned False for both
# candidate paths, stdout was empty, and nothing was written anywhere. That is byte-identical to a
# healthy hook with no peers, which is how a wired-but-resolving-nothing hook survived for weeks. This
# notice is the ONE surface that still resolves when the script does not.
#
# WHY IT IS GATED ON ccx.config.json. This entry is user-global and fires in every unrelated project on
# the machine, so the notice must appear ONLY in a repository that has opted in. The probe is the
# config file's PRESENCE, and it is deliberately not "does scripts/coord/presence.ps1 exist": that
# asks whether a particular implementation file happens to be on disk, which is true in a
# half-installed tree and false in a governed repo that vendors the scripts elsewhere.
function New-AnnounceShimCommand {
    $notice = "[ccx announce] scripts/hooks/announce-session.ps1 is missing from this checkout -- the announce hook is wired but resolving nothing. See docs/COORDINATION.md."
    return (
        "# $ANNOUNCE_MARKER`n" +
        '$c = (& git rev-parse --path-format=absolute --git-common-dir 2>$null); ' +
        'if ($LASTEXITCODE -eq 0 -and $c) { $c = $c.Trim(); ' +
        '$bases = @((Split-Path $c -Parent), (& git rev-parse --path-format=absolute --show-toplevel 2>$null)); ' +
        '$hit = $false; $optedIn = $false; ' +
        'foreach ($b in $bases) { if (-not $b) { continue } $b = $b.Trim(); ' +
        'if (Test-Path -LiteralPath (Join-Path $b ''ccx.config.json'')) { $optedIn = $true } ' +
        '$s = Join-Path $b ''scripts/hooks/announce-session.ps1''; ' +
        'if (Test-Path -LiteralPath $s) { & $s -CommonDir $c; $hit = $true; break } } ' +
        'if (-not $hit -and $optedIn) { Write-Output ' + "'$notice'" + ' } }'
    )
}

# Timeout 15 on the announce row is that hook's ONLY time bound -- the peer lookup runs in-process by
# design -- so it must comfortably exceed the peer lookup's measured cost (~1.0 s, measured on the repo
# this was developed in) while staying short enough that a hang is not felt as a hang at prompt submit.
# UserPromptSubmit takes no matcher.
$WIRING = @(
    @{ Event = "SessionStart"; Matcher = $null; Script = "scripts/worktree/session-context.ps1"; Timeout = 30; Msg = "Session coordination"; Marker = $MARKER; Shim = "std" }
    @{ Event = "PreToolUse"; Matcher = "Edit|Write|MultiEdit|NotebookEdit"; Script = "scripts/hooks/collision_gate.ps1"; Timeout = 20; Msg = "Checking for a colliding session"; Marker = $MARKER; Shim = "std" }
    @{ Event = "UserPromptSubmit"; Matcher = $null; Script = "scripts/hooks/announce-session.ps1"; Timeout = 15; Msg = "Announcing to sessions in this repo"; Marker = $ANNOUNCE_MARKER; Shim = "announce" }
)

if ($Only) { $WIRING = @($WIRING | Where-Object { $Only -contains $_.Event }) }
if ($Except) { $WIRING = @($WIRING | Where-Object { $Except -notcontains $_.Event }) }
if (-not $WIRING) { Write-Host "No wiring rows selected."; exit 0 }

function Get-CommandFor($Row) {
    if ($Row.Shim -eq "announce") { return (New-AnnounceShimCommand) }
    return (New-ShimCommand $Row.Script $Row.Marker)
}

# ------------------------------------------------------------------------------------------ helpers

function Get-TextSha256([string]$Text) {
    if ($null -eq $Text) { return "" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (([System.Security.Cryptography.SHA256]::HashData($bytes) |
            ForEach-Object { $_.ToString('x2') }) -join '')
}

function Read-Settings {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return [ordered]@{} }
    $raw = Get-Content -LiteralPath $SettingsPath -Raw
    if (-not $raw.Trim()) { return [ordered]@{} }
    # Fail loudly rather than overwrite: a settings file we cannot parse is one we must not rewrite,
    # because a bad write silently disables EVERY setting in it.
    return ($raw | ConvertFrom-Json -AsHashtable)
}

function Test-IsOurs([hashtable]$Entry, [string]$Marker = $MARKER) {
    foreach ($h in @($Entry.hooks)) { if ([string]$h.command -match [regex]::Escape($Marker)) { return $true } }
    return $false
}

function Get-WiredCommand($Settings, $Row) {
    foreach ($group in @($Settings.hooks[$Row.Event])) {
        if (-not $group) { continue }
        foreach ($h in @($group.hooks)) {
            if ([string]$h.command -match [regex]::Escape($Row.Marker)) { return [string]$h.command }
        }
    }
    return $null
}

# ConvertFrom-Json coerces an ISO-8601 string into a DateTime, which then renders in the host's local
# format and loses the 'this is UTC' marker the receipt deliberately wrote. Print it back as written.
function Format-Stamp($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("o") }
    return [string]$Value
}

function Read-Receipt {
    if (-not (Test-Path -LiteralPath $ReceiptPath)) { return $null }
    try { return (Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json -AsHashtable) }
    catch {
        # A receipt we cannot parse is NOT the same as no receipt, and must not be reported as one.
        Write-Warning "Receipt at $ReceiptPath is unreadable: $($_.Exception.Message)"
        return @{ unreadable = $true }
    }
}

# The receipt is MERGED, never rewritten wholesale. `-Only UserPromptSubmit` touches one row; blowing
# away the record of the other two would make -Status report an install it cannot see as absent.
function Write-Receipt([hashtable]$Updates, [string[]]$Removed) {
    $existing = Read-Receipt
    $entries = [ordered]@{}
    if ($existing -and -not $existing.unreadable -and $existing.entries) {
        foreach ($k in $existing.entries.Keys) { $entries[$k] = $existing.entries[$k] }
    }
    foreach ($k in $Updates.Keys) { $entries[$k] = $Updates[$k] }
    foreach ($k in @($Removed)) { if ($entries.Contains($k)) { $entries.Remove($k) } }

    $doc = [ordered]@{
        tool         = "scripts/coord/install-coordination.ps1"
        writtenAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        settingsPath = $SettingsPath
        sourceRoot   = $RepoRoot
        entries      = $entries
    }
    if ($entries.Count -eq 0) {
        Remove-Item -LiteralPath $ReceiptPath -Force -ErrorAction SilentlyContinue
        return $null
    }
    $json = $doc | ConvertTo-Json -Depth 10
    $null = $json | ConvertFrom-Json   # throws before we touch the file
    Set-Content -LiteralPath $ReceiptPath -Value $json -Encoding utf8NoBOM
    return $ReceiptPath
}

# Reproduce EXACTLY what the shim does at run time, and from where it does it.
#
# Two deliberate choices, both of which make this LESS clever than it could be:
#
#   * It does NOT call Get-CcxPrimaryRoot, even though that helper resolves the primary more
#     carefully. A status check that finds the target by a better route than the hook uses reports a
#     healthy hook that does not work. Model the mechanism you are auditing, not the one you wish it
#     used.
#   * It resolves from the CURRENT DIRECTORY, not from where this script lives. The hook runs with the
#     session's cwd, so "does it resolve?" is a question about the directory you are standing in --
#     which is also why -Status can only ever answer it for that one repository.
function Get-ShimBases {
    $bases = @()
    $common = Get-CcxGitCommonDir
    if ($common) { $bases += (Split-Path -Parent $common) }
    $top = Invoke-CcxGit -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
    if ($top) { $bases += $top }
    return @($bases | Where-Object { $_ })
}

function Resolve-ShimTarget([string]$RelativeScript, [string[]]$Bases) {
    foreach ($b in $Bases) {
        $s = Join-Path $b $RelativeScript
        if (Test-Path -LiteralPath $s) { return $s }
    }
    return $null
}

# --------------------------------------------------------------------------------------- status
# This branch runs BEFORE the refusal below, deliberately. Auditing is not installing, and a session
# that cannot see whether its own coordination is live has no way to notice the exact failure this
# whole file exists to make visible. Installing stays a human act.
if ($Status) {
    $settings = Read-Settings
    $receipt = Read-Receipt
    $bases = Get-ShimBases
    $configPath = Find-CcxConfigPath -From $PWD.Path

    Write-Host ""
    Write-Host "ccx coordination hooks"
    Write-Host "  settings : $SettingsPath $(if (Test-Path -LiteralPath $SettingsPath) { '' } else { '(does not exist)' })"
    if (-not $receipt) {
        Write-Host "  receipt  : NONE at $ReceiptPath" -ForegroundColor Yellow
        Write-Host "             Nothing recorded an install here. Anything reported below is inference" -ForegroundColor Yellow
        Write-Host "             from the settings file, which is a claim rather than evidence." -ForegroundColor Yellow
    } elseif ($receipt.unreadable) {
        Write-Host "  receipt  : UNREADABLE at $ReceiptPath" -ForegroundColor Red
    } else {
        Write-Host "  receipt  : $ReceiptPath (written $(Format-Stamp $receipt.writtenAtUtc) from $($receipt.sourceRoot))"
    }
    Write-Host "  opt-in   : $(if ($configPath) { $configPath } else { 'NO ccx.config.json at or above this directory' })"
    Write-Host ""

    $bad = 0
    foreach ($w in $WIRING) {
        $want = Get-CommandFor $w
        $wantSha = Get-TextSha256 $want
        $wired = Get-WiredCommand $settings $w
        $wiredSha = if ($wired) { Get-TextSha256 $wired } else { $null }
        $rec = $null
        if ($receipt -and -not $receipt.unreadable -and $receipt.entries) { $rec = $receipt.entries[$w.Event] }
        $target = Resolve-ShimTarget $w.Script $bases

        Write-Host ("  {0,-16} {1}" -f $w.Event, $w.Script)
        if ($rec) {
            Write-Host ("    receipt    yes  (sha {0})" -f $rec.commandSha256.Substring(0, 8))
        } else {
            Write-Host "    receipt    no   -- no install of this row was ever recorded" -ForegroundColor Yellow
        }
        if (-not $wired) {
            Write-Host "    wired      NO   -- nothing carrying marker '$($w.Marker)' is in the settings file" -ForegroundColor Red
        } elseif ($rec -and $wiredSha -ne $rec.commandSha256) {
            Write-Host "    wired      yes, but the command DIFFERS from the receipt (edited in place?)" -ForegroundColor Red
        } else {
            Write-Host "    wired      yes"
        }
        if ($wired -and $wiredSha -ne $wantSha) {
            Write-Host "    current    NO   -- the wired command differs from what this checkout would write." -ForegroundColor Yellow
            Write-Host "                      Re-run this installer to bring it up to date." -ForegroundColor Yellow
        } elseif ($wired) {
            Write-Host "    current    yes  -- matches what this checkout would write"
        }
        if ($target) {
            Write-Host "    resolves   $target"
        } else {
            Write-Host "    resolves   NOTHING -- the shim will exit silently and write nothing." -ForegroundColor Red
            Write-Host "                        Bases tried: $($bases -join ' ; ')" -ForegroundColor Red
        }

        $live = $wired -and $target -and (-not $rec -or $wiredSha -eq $rec.commandSha256)
        if ($live) { Write-Host "    => LIVE" -ForegroundColor Green }
        else { Write-Host "    => NOT LIVE" -ForegroundColor Red; $bad++ }
        Write-Host ""
    }

    Write-Host "scanned: 1 settings file, $(@($bases).Count) resolution base(s), $(@($WIRING).Count) wiring row(s)."
    Write-Host "blind spots on this run:"
    Write-Host "  * Only $SettingsPath was read. If your client reads a different config directory,"
    Write-Host "    nothing here says anything about it -- point -SettingsPath at that file too."
    Write-Host "  * Resolution was modelled from $($PWD.Path), because that is where the hook resolves"
    Write-Host "    from. These hooks are machine-scope; a session standing anywhere else resolves other"
    Write-Host "    bases, which this run did not look at. Re-run -Status from each repository."
    Write-Host "  * A running session keeps the configuration it booted with. Nothing here changes one."
    Write-Host "  * Announce DELIVERY depends on a session-management MCP that is not present on every"
    Write-Host "    install. Where it is absent the hook still runs and still says nothing useful."
    Write-Host ""
    if ($bad -gt 0) { Write-Host "$bad row(s) NOT LIVE. Exit code 1." -ForegroundColor Red; exit 1 }
    exit 0
}

if ($env:CLAUDECODE -eq "1") {
    throw ("Refusing to run inside Claude Code. A session that can wire these hooks can also unwire " +
        "them -- and these are the hooks by which peers see each other, so a session that removes " +
        "them makes itself invisible to every other session while still looking coordinated to " +
        "itself. Run from a plain pwsh terminal. (-Status is allowed from a session: auditing is " +
        "not installing.)")
}

# --------------------------------------------------------------------------------- install/uninstall

$settings = Read-Settings
if (-not $settings.hooks) { $settings.hooks = [ordered]@{} }

# Strip our entries first -- this is both the uninstall path and the idempotency of re-install.
foreach ($w in $WIRING) {
    if ($settings.hooks[$w.Event]) {
        $kept = @(@($settings.hooks[$w.Event]) | Where-Object { $_ -and -not (Test-IsOurs $_ $w.Marker) })
        if ($kept.Count -gt 0) { $settings.hooks[$w.Event] = $kept } else { $settings.hooks.Remove($w.Event) }
    }
}

$written = @{}
if (-not $Uninstall) {
    foreach ($w in $WIRING) {
        $cmd = Get-CommandFor $w
        $entry = [ordered]@{}
        if ($w.Matcher) { $entry.matcher = $w.Matcher }
        $entry.hooks = @(
            [ordered]@{
                type          = "command"
                command       = $cmd
                shell         = "powershell"
                timeout       = $w.Timeout
                statusMessage = $w.Msg
            }
        )
        $existing = @($settings.hooks[$w.Event])
        $settings.hooks[$w.Event] = @($existing | Where-Object { $_ }) + @($entry)
        $written[$w.Event] = [ordered]@{
            marker        = $w.Marker
            script        = $w.Script
            matcher       = $w.Matcher
            timeout       = $w.Timeout
            commandSha256 = (Get-TextSha256 $cmd)
        }
    }
}

$backup = "$SettingsPath.bak-ccx-coord"
if ($PSCmdlet.ShouldProcess($SettingsPath, $(if ($Uninstall) { "remove coordination hooks" } else { "install coordination hooks" }))) {
    if (Test-Path -LiteralPath $SettingsPath) { Copy-Item -LiteralPath $SettingsPath -Destination $backup -Force }
    else { New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null }

    $json = $settings | ConvertTo-Json -Depth 12
    # Validate what we are about to write BEFORE replacing the file. A malformed settings file does not
    # error at startup -- it silently disables every setting in it, which is the worst failure mode
    # available here.
    try { $null = $json | ConvertFrom-Json } catch { throw "Refusing to write: generated settings JSON is invalid. $_" }
    Set-Content -LiteralPath $SettingsPath -Value $json -Encoding utf8NoBOM

    $receiptWritten = if ($Uninstall) {
        Write-Receipt @{} @($WIRING | ForEach-Object { $_.Event })
    } else {
        Write-Receipt $written @()
    }

    # ------------------------------------------------------------------------------------- receipt
    # Print what was written and where, every time. The whole class of failure this file exists to
    # prevent is a control that looks installed and is not, so an install that says only "done" is
    # the same shape of lie as a green status that checked nothing.
    $bases = Get-ShimBases
    Write-Host ""
    if ($Uninstall) {
        Write-Host "REMOVED from $SettingsPath" -ForegroundColor Yellow
        foreach ($w in $WIRING) { Write-Host ("  {0,-16} {1}" -f $w.Event, $w.Script) }
    } else {
        Write-Host "WROTE to $SettingsPath (user scope -- loads in every worktree)" -ForegroundColor Green
        foreach ($w in $WIRING) {
            $sha = $written[$w.Event].commandSha256.Substring(0, 8)
            $target = Resolve-ShimTarget $w.Script $bases
            Write-Host ("  {0,-16} {1}" -f $w.Event, $w.Script)
            Write-Host ("    marker {0}   sha {1}   timeout {2}s" -f $w.Marker, $sha, $w.Timeout)
            if ($target) {
                Write-Host "    resolves now to $target"
            } else {
                Write-Host "    RESOLVES TO NOTHING from here. The hook is wired and will do nothing," -ForegroundColor Red
                Write-Host "    silently, which looks exactly like a healthy hook with no peers." -ForegroundColor Red
                Write-Host "    Bases tried: $($bases -join ' ; ')" -ForegroundColor Red
            }
        }
    }
    Write-Host ""
    Write-Host "  backup : $backup"
    Write-Host "  receipt: $(if ($receiptWritten) { $receiptWritten } else { "(removed -- nothing left recorded)" })"
    if (-not (Find-CcxConfigPath -From $RepoRoot)) {
        Write-Host "  NOTE   : no ccx.config.json found at or above $RepoRoot. That file is the opt-in" -ForegroundColor Yellow
        Write-Host "           marker as well as the configuration, so these user-scope hooks will stay" -ForegroundColor Yellow
        Write-Host "           inert in this repository until it exists." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Takes effect in NEWLY STARTED sessions; existing ones keep the config they booted with."
    Write-Host "  Verify with: pwsh -NoProfile -File scripts/coord/install-coordination.ps1 -Status"
    Write-Host ""
}
