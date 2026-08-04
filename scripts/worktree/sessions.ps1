#Requires -Version 7.3
<#
.SYNOPSIS
    Find -- and rescue -- Claude Code sessions for this repository across every login on the box,
    including the ones that relocating into a worktree made invisible.

.DESCRIPTION
    Claude Code files a session's transcript at

        <config-dir>/projects/<slug-of-cwd>/<session-id>.jsonl

    where the slug is derived from the session's CURRENT working directory. Relocate a live session
    into a worktree and the whole transcript is re-filed under the WORKTREE's slug -- so the
    conversation drops out of the session list of the window it was born in. Nothing is deleted; it is
    simply somewhere the window no longer looks. What is left behind under the birth slug is a
    title-only stub of a line or two, which reads in a listing as a second, near-empty session.

    This script is how you see those sessions at all, and the recovery path for the ones that already
    went missing:

        -Rehome moves a transcript back to the slug of the PRIMARY checkout, which puts it back in
        that window's session list, where you can resume it normally.

    SEVERAL LOGINS CAN BE IN PLAY at once, and a session is only ever visible to the login that owns
    it: the desktop app uses the default ~/.claude, and any launcher that sets CLAUDE_CONFIG_DIR gets
    its own config dir alongside it (~/.claude-account-N by convention). This scans all of them, so
    "which login was that in?" stops being a question you answer by hand.

    Read-only unless you pass -Rehome. A bare invocation only ever LISTS -- it never moves anything.
    -Rehome is the one destructive action, and it honours -WhatIf (preview the move without touching
    disk) and refuses on a session that still looks live (see -MinIdleMinutes).

.EXAMPLE
    ./sessions.ps1                             # every session for this repo, newest first
    ./sessions.ps1 -Relocated                  # only the ones that moved (missing from a window)
    ./sessions.ps1 -Id <id-prefix>             # detail for one session (an id prefix is enough)
    ./sessions.ps1 -Rehome <id-prefix> -WhatIf # preview the rehome without moving anything
    ./sessions.ps1 -Rehome <id-prefix>         # put it back in the window it started in
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Only sessions whose transcript is filed somewhere other than where the session was born -- the
    # ones that vanished from a window's list.
    [switch]$Relocated,
    # Show one session in full. A unique id prefix is enough.
    [string]$Id,
    # Move a session's transcript under the PRIMARY's slug, so it reappears in the main window's
    # session list. Refuses on a session that still looks live (see -MinIdleMinutes). Honours -WhatIf.
    [string]$Rehome,
    # Rehome somewhere other than the primary (must be a directory you can actually open a window on).
    [string]$To,
    # A transcript touched more recently than this is assumed to belong to a RUNNING session; moving
    # the file out from under its writer would corrupt it. Override with -Force at your own risk.
    [int]$MinIdleMinutes = 10,
    [switch]$Force,
    [int]$Limit = 40
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../coord/_common.ps1")

# Anchor on the PRIMARY working tree, not on this script's own checkout. Run from a linked worktree,
# `$PSScriptRoot/../..` is the WORKTREE root, and every slug computed from it would be the wrong one.
$Primary = Get-CcxPrimaryRoot -Repo $PSScriptRoot
if (-not $Primary) {
    throw "Not inside a git repository (git worktree list failed). Run this from a checkout."
}

$WorktreePaths = @(
    (Invoke-CcxGit -Repo $PSScriptRoot -Arguments @('worktree', 'list', '--porcelain')) -split "`r?`n" |
        Where-Object { $_ -match '^worktree\s+(.+)$' } |
        ForEach-Object { $Matches[1].Trim() }
)

# The one git directory every worktree of this clone shares. It is how we tell a worktree of OURS
# from a SEPARATE repository that merely sits next to it: a sibling checkout named
# `<repo>-website` slugs to exactly the same shape as a worktree of ours named `website`, and the
# slug alone cannot tell them apart. The shared git dir can.
$OurGitDir = ConvertTo-CcxComparablePath (Get-CcxGitCommonDir -Repo $PSScriptRoot)

$live = @{}
foreach ($w in $WorktreePaths) {
    $k = ConvertTo-CcxComparablePath $w
    if ($k) { $live[$k] = $true }
}

# Does this recorded cwd belong to THIS repo? Three cases, and the third is the one that matters.
function Test-OurCheckout([string]$Cwd) {
    if (-not $Cwd) { return $true }                             # no cwd recorded -> trust the slug pre-filter
    $n = ConvertTo-CcxComparablePath $Cwd
    if (-not $n) { return $false }
    if ($live.ContainsKey($n)) { return $true }                 # a live worktree of ours

    if (Test-Path -LiteralPath $Cwd -PathType Container) {
        # Still on disk but not a worktree of ours -> a different repo wearing a similar name. Drop it.
        if (-not $OurGitDir) { return $false }
        $g = Get-CcxGitCommonDir -Repo $Cwd
        if (-not $g) { return $false }
        return ((ConvertTo-CcxComparablePath $g) -eq $OurGitDir)
    }

    # The directory is GONE. This is a pruned worktree -- and a session stranded in a pruned
    # worktree's slug is exactly what this script exists to find, so keep it. (A deleted sibling repo
    # would also land here; that is a rare, harmless false positive, and the listing shows the path.)
    return $true
}

# Claude Code's slug: every character that is not a letter or a digit becomes '-'. So
# C:\src\demo -> C--src-demo. Compared case-insensitively throughout: the drive letter's case varies
# between sessions ('c:\...' vs 'C:\...') and a case-insensitive filesystem folds it anyway, so the
# two spellings name one directory. Separator direction does not matter here -- both '\' and '/'
# are non-alphanumeric and fold to the same '-'.
function Get-Slug([string]$Path) {
    if (-not $Path) { return "" }
    return (($Path -replace '[\\/]+$', '') -replace '[^A-Za-z0-9]', '-')
}

$PrimarySlug = Get-Slug $Primary

# Every login on this box. The default ~/.claude belongs to the desktop app; each launcher that sets
# CLAUDE_CONFIG_DIR gets its own dir beside it. A session is only visible to the login that owns it.
#
# Null-safely: $env:USERPROFILE is Windows-only and NULL elsewhere, where Join-Path throws a
# parameter-binding error instead of returning a path. Same idiom as the installers in this directory.
$HomeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
$ConfigDirs = @(
    Get-ChildItem -Path $HomeDir -Directory -Filter ".claude*" -Force -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "projects") } |
        ForEach-Object { $_.FullName }
)

# Pull the few facts we need out of the HEAD of a transcript. Transcripts grow to tens of megabytes,
# so never read one whole: the birth cwd, branch and first prompt are all in the first handful of
# records, and reading a few hundred lines costs nothing. The first line is often a
# queue-operation/last-prompt/mode record with no cwd, so scan for the first record that actually
# carries cwd/gitBranch rather than trusting line 1.
function Read-TranscriptHead([string]$File) {
    $info = [ordered]@{ Cwd = ""; Branch = ""; Title = ""; Prompt = "" }
    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($File)
        for ($n = 0; $n -lt 400 -and -not $reader.EndOfStream; $n++) {
            $line = $reader.ReadLine()
            if (-not $line) { continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }

            if (-not $info.Cwd    -and $o.cwd)       { $info.Cwd = [string]$o.cwd }
            if (-not $info.Branch -and $o.gitBranch) { $info.Branch = [string]$o.gitBranch }
            # A title the user set by hand beats the model's generated one.
            if ($o.customTitle)                      { $info.Title = [string]$o.customTitle }
            if (-not $info.Title -and $o.aiTitle)    { $info.Title = [string]$o.aiTitle }

            # First real user turn -- skip sidechains (subagent traffic), which are not what you would
            # recognise the session by.
            if (-not $info.Prompt -and $o.type -eq "user" -and -not $o.isSidechain) {
                $c = $o.message.content
                $text = if ($c -is [string]) { $c } else { ($c | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text }
                if ($text) { $info.Prompt = ([string]$text -replace '\s+', ' ').Trim() }
            }
        }
    } catch {
        # A half-written transcript from a live session is normal, not an error. Report what we got.
    } finally {
        if ($reader) { $reader.Dispose() }
    }
    return [pscustomobject]$info
}

# --------------------------------------------------------------------------------------------- collect
$records = @()
foreach ($cfg in $ConfigDirs) {
    $projects = Join-Path $cfg "projects"

    # Pre-filter by slug so we do not crack open every unrelated repo's transcripts, then CONFIRM
    # against the cwd recorded inside the file. THE PREFIX ALONE CANNOT DECIDE: a sibling repository
    # named `<repo>-website` slugs to the same shape as a worktree of ours named `website`. The
    # recorded cwd settles it.
    $slugDirs = @(
        Get-ChildItem -LiteralPath $projects -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $PrimarySlug -or $_.Name -like "$PrimarySlug-*" }
    )

    foreach ($dir in $slugDirs) {
        foreach ($file in (Get-ChildItem -LiteralPath $dir.FullName -Filter "*.jsonl" -File -ErrorAction SilentlyContinue)) {
            $head = Read-TranscriptHead $file.FullName

            # The confirming check: the slug prefix said "maybe", the recorded cwd says yes or no.
            $cwd = $head.Cwd
            if (-not (Test-OurCheckout $cwd)) { continue }

            $bornSlug = if ($cwd) { Get-Slug $cwd } else { $dir.Name }
            $gone = [bool]($cwd -and -not (Test-Path -LiteralPath $cwd -PathType Container))
            $records += [pscustomobject]@{
                Id        = $file.BaseName
                Login     = Split-Path $cfg -Leaf
                ConfigDir = $cfg
                FiledIn   = $dir.FullName
                FiledSlug = $dir.Name
                BornCwd   = $cwd
                BornSlug  = $bornSlug
                Branch    = $head.Branch
                Title     = $head.Title
                Prompt    = $head.Prompt
                Bytes     = $file.Length
                Last      = $file.LastWriteTime
                File      = $file.FullName
                Gone      = $gone
                # THE symptom: the transcript is not filed where the session was born, so the window
                # it started in cannot see it. (Case-insensitive: the drive letter's case varies.)
                Relocated = ($bornSlug -and ($dir.Name -ine $bornSlug))
            }
        }
    }
}

# A relocated session leaves a title-only stub behind under its birth slug -- same session id, one or
# two records. Fold it into the real record rather than listing a phantom near-empty session.
$byKey = $records | Group-Object { "$($_.ConfigDir)|$($_.Id)" }
$sessions = foreach ($g in $byKey) {
    $real = $g.Group | Sort-Object Bytes -Descending | Select-Object -First 1
    $stub = $g.Group | Where-Object { $_.File -ne $real.File }
    if (-not $real.Title) { $real.Title = ($stub | Where-Object Title | Select-Object -First 1).Title }
    $real | Add-Member -NotePropertyName Stubs -NotePropertyValue @($stub.File) -PassThru
}
$sessions = @($sessions | Sort-Object Last -Descending)

# ---------------------------------------------------------------------------------------------- rehome
if ($Rehome) {
    $hit = @($sessions | Where-Object { $_.Id -like "$Rehome*" })
    if ($hit.Count -eq 0) { throw "No session matching '$Rehome'. Run without -Rehome to list them." }
    if ($hit.Count -gt 1) { throw "'$Rehome' matches $($hit.Count) sessions. Use a longer id prefix." }
    $s = $hit[0]

    # Moving a transcript out from under a RUNNING session's writer corrupts it -- and relocating a
    # live session is precisely the injury this script exists to REPAIR, so a false "it's idle" here
    # is the worst failure it can have. Two INDEPENDENT signals, and EITHER may veto. Under -WhatIf we
    # only PREVIEW, so both are relaxed there -- nothing is moved, and you still see what the move
    # would do.
    #
    # (1) The session registry, fenced on pid + process start time (scripts/coord/session-registry.ps1).
    #     This is the authoritative POSITIVE signal, and adding it is the point of this guard:
    #     TRANSCRIPT MTIME IS NOT LIVENESS. Subagent and workflow output is written under
    #     <session-id>/subagents/, so a session running a long workflow barely touches its own
    #     transcript. Measured on the repo this was developed in: a verifiably live session sat over
    #     half an hour idle by mtime while its process was alive and fenced -- several times the
    #     default -MinIdleMinutes, i.e. the mtime guard alone would have waved the move straight
    #     through. A bare pid check is not enough either: pids are recycled, and a recycled pid reads
    #     as a live session that is really somebody else's process. Hence pid AND start time.
    #
    # (2) Transcript mtime, the original signal, KEPT rather than replaced. A session that exits
    #     cleanly unlinks its registry file, so "no record" is indistinguishable from "never
    #     registered" and cannot stand on its own either.
    #
    # Refusing when EITHER says live is deliberate: nothing here can PROVE a session is gone (no
    # heartbeat, and registry writes are event-driven), so only the positive answer is trustworthy.
    # LIVENESS MAY VETO, NEVER PERMIT -- a negative from one signal must not by itself authorise a
    # destructive move.
    $registry = Join-Path $PSScriptRoot "../coord/session-registry.ps1"
    if (-not (Test-Path -LiteralPath $registry)) {
        throw ("session-registry.ps1 is missing beside this script ($registry). It is half of the " +
               "liveness fence, and rehoming a LIVE session's transcript corrupts it -- refusing " +
               "rather than falling back to transcript mtime alone.")
    }
    . $registry
    $reg = Get-SessionLiveness -SessionId $s.Id
    if ($reg.State -in @("LIVE", "UNVERIFIED") -and -not $Force -and -not $WhatIfPreference) {
        throw ("Session $($s.Id) is $($reg.State) in the session registry (pid $($reg.Record.pid)" +
               "$(if ($reg.Detail) { "; $($reg.Detail)" })) -- it is still RUNNING and moving its " +
               "transcript would corrupt it. Its transcript may look idle: subagent output is filed " +
               "elsewhere, so mtime is not liveness. Close that window, then retry (or -Force).")
    }

    $idle = (Get-Date) - $s.Last
    if ($idle.TotalMinutes -lt $MinIdleMinutes -and -not $Force -and -not $WhatIfPreference) {
        throw ("Session $($s.Id) was written $([int]$idle.TotalMinutes) min ago and may still be " +
               "RUNNING; moving its transcript would corrupt it. Close that window, then retry (or -Force).")
    }

    # Rehome to the PRIMARY, not to wherever the session happened to be born.
    #
    # "Put it back where it started" is the obvious rule and it is wrong. A session can be born in a
    # worktree that no longer exists -- notably the empty ghost stubs a half-failed auto-worktree
    # leaves behind -- and its transcript can already be sitting in the primary, VISIBLE. Sending that
    # one "home" would file it under a directory nobody will ever open a window on, i.e. hide the very
    # session we were asked to rescue. (That case is real: a large session born in a ghost stub, filed
    # in the primary, would have been moved out of sight by the obvious rule.)
    #
    # The primary is the one checkout that is always open, so it is the one safe destination. -To
    # overrides when you specifically want the session to land in some worktree's window instead.
    $destCwd  = if ($To) { $To } else { $Primary }
    $destSlug = Get-Slug $destCwd
    if ($To -and -not (Test-Path -LiteralPath $destCwd -PathType Container)) {
        throw "-To '$destCwd' does not exist; a session filed under a directory you cannot open a window on is still lost."
    }

    $destDir = Join-Path (Join-Path $s.ConfigDir "projects") $destSlug
    $dest = Join-Path $destDir "$($s.Id).jsonl"
    if ((ConvertTo-CcxComparablePath $dest) -eq (ConvertTo-CcxComparablePath $s.File)) {
        Write-Host "Session $($s.Id) is already filed at $destSlug. Nothing to do." -ForegroundColor Green
        return
    }

    # A live session also has a SIDECAR directory next to its transcript --
    # <config>/projects/<slug>/<session-id>/ (subagents/, workflows/). Move it alongside the .jsonl so
    # the rehome does not strand it under the old slug. (The session-env dir is keyed by session id,
    # not by slug, so it is unaffected by a rehome and left alone.)
    $srcSidecar  = Join-Path $s.FiledIn $s.Id
    $destSidecar = Join-Path $destDir $s.Id
    $haveSidecar = Test-Path -LiteralPath $srcSidecar -PathType Container

    # -WhatIf preview / confirmation. Nothing below this gate touches disk.
    $action = "rehome $($s.FiledSlug) -> $destSlug$(if ($haveSidecar) { ' (+ sidecar dir)' })"
    if (-not $PSCmdlet.ShouldProcess("session $($s.Id) [$($s.Login)]", $action)) { return }

    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    # The title stub already sitting at the destination IS the session's custom title. Keep it: back
    # it up, then re-append its records to the end of the moved transcript (JSONL is a log -- later
    # records win).
    $stubLines = @()
    if (Test-Path -LiteralPath $dest) {
        Copy-Item -LiteralPath $dest -Destination "$dest.stub.bak" -Force
        $stubLines = @(Get-Content -LiteralPath $dest -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $dest -Force
    }

    Move-Item -LiteralPath $s.File -Destination $dest -Force
    if ($stubLines.Count -gt 0) { Add-Content -LiteralPath $dest -Value $stubLines -Encoding utf8 }

    # Move the sidecar directory too, if one exists and is not already at the destination.
    $movedSidecar = $false
    if ($haveSidecar -and ((ConvertTo-CcxComparablePath $srcSidecar) -ne (ConvertTo-CcxComparablePath $destSidecar))) {
        if (-not (Test-Path -LiteralPath $destSidecar)) {
            Move-Item -LiteralPath $srcSidecar -Destination $destSidecar -Force
            $movedSidecar = $true
        }
    }

    Write-Host ""
    Write-Host "Rehomed session $($s.Id)" -ForegroundColor Green
    Write-Host "  from : $($s.FiledSlug)"
    Write-Host "  to   : $destSlug   ($destCwd)"
    Write-Host "  login: $($s.Login)"
    if ($stubLines.Count -gt 0) { Write-Host "  kept : the title stub's $($stubLines.Count) record(s) (backup: $dest.stub.bak)" }
    if ($movedSidecar) { Write-Host "  moved: the session's sidecar dir ($($s.Id)/)" }
    Write-Host ""
    Write-Host "It is back in that folder's session list. Open a Claude Code window on $destCwd and it will"
    Write-Host "be there; or resume it directly:"
    Write-Host "  `$env:CLAUDE_CONFIG_DIR='$($s.ConfigDir)'; cd '$destCwd'; claude --resume $($s.Id)"
    return
}

# ---------------------------------------------------------------------------------------------- detail
if ($Id) {
    $hit = @($sessions | Where-Object { $_.Id -like "$Id*" })
    if ($hit.Count -eq 0) { throw "No session matching '$Id'." }
    foreach ($s in $hit) {
        Write-Host ""
        Write-Host "$($s.Id)" -ForegroundColor Cyan
        Write-Host "  title    : $($s.Title)"
        Write-Host "  login    : $($s.Login)"
        Write-Host "  born in  : $($s.BornCwd)$(if ($s.Gone) { '   [DIRECTORY GONE - worktree was pruned]' })   (branch $($s.Branch))"
        Write-Host "  filed in : $($s.FiledIn)"
        if ($s.Relocated -and $s.FiledSlug -ine $PrimarySlug) {
            Write-Host "  STATUS   : RELOCATED -- the window it started in cannot see it." -ForegroundColor Yellow
            Write-Host "             Bring it back to the main window:  ./sessions.ps1 -Rehome $($s.Id)"
        }
        Write-Host "  size     : $([math]::Round($s.Bytes / 1MB, 2)) MB, last written $($s.Last)"
        Write-Host "  opened   : $($s.Prompt)"
        Write-Host "  resume   : `$env:CLAUDE_CONFIG_DIR='$($s.ConfigDir)'; cd '$($s.BornCwd)'; claude --resume $($s.Id)"
    }
    return
}

# ------------------------------------------------------------------------------------------------ list
$show = if ($Relocated) { @($sessions | Where-Object Relocated) } else { $sessions }
if ($show.Count -eq 0) {
    Write-Host "No sessions found for $Primary across $($ConfigDirs.Count) login(s)." -ForegroundColor Yellow
    return
}

# Short, human label for where a transcript sits: the primary, or the worktree's own name. The
# `--claude-worktrees-` infix is the slug of the harness's own nested worktree directory
# (<primary>/.claude/worktrees/<name>), so it is worth naming rather than printing raw.
function Get-Where([string]$Slug) {
    if ($Slug -ieq $PrimarySlug) { return "primary" }
    if ($Slug -like "$PrimarySlug--claude-worktrees-*") { return $Slug.Substring("$PrimarySlug--claude-worktrees-".Length) }
    if ($Slug -like "$PrimarySlug-*") { return $Slug.Substring($PrimarySlug.Length + 1) }
    return $Slug
}

$show | Select-Object -First $Limit | ForEach-Object {
    [pscustomobject]@{
        Last     = $_.Last.ToString("MM-dd HH:mm")
        Id       = $_.Id.Substring(0, 8)
        # Naming convention only: the default config dir is the desktop app's, and the numbered ones
        # come from launchers that set CLAUDE_CONFIG_DIR. Shortened purely so the column fits.
        Login    = $_.Login -replace '^\.claude-account-', 'acct-' -replace '^\.claude$', 'desktop'
        FiledIn  = Get-Where $_.FiledSlug
        BornIn   = Get-Where $_.BornSlug
        MB       = [math]::Round($_.Bytes / 1MB, 1)
        Title    = if ($_.Title) { $_.Title } else { $_.Prompt }
    }
} | Format-Table -AutoSize

# Print what was scanned, always. A run that found nothing because it looked in one place must not
# read the same as a run that found nothing because there is nothing to find.
Write-Host ""
Write-Host "scanned $($ConfigDirs.Count) login(s) / $($WorktreePaths.Count) worktree(s); $($sessions.Count) session(s) matched."

$moved = @($sessions | Where-Object { $_.Relocated -and $_.FiledSlug -ine $PrimarySlug }).Count
if ($moved -gt 0 -and -not $Relocated) {
    Write-Host ""
    Write-Host "$moved session(s) were relocated out of the window they started in, and that window's" -ForegroundColor Yellow
    Write-Host "session list can no longer see them. Nothing is lost -- they are just filed elsewhere." -ForegroundColor Yellow
    Write-Host "  list them             :  ./sessions.ps1 -Relocated" -ForegroundColor Yellow
    Write-Host "  bring one back to main:  ./sessions.ps1 -Rehome <id-prefix>" -ForegroundColor Yellow
}
