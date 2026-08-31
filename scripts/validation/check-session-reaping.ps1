#Requires -Version 7.3
<#
.SYNOPSIS
    Session liveness against last write. Fires when a session is alive long past anything it wrote.

.DESCRIPTION
    WHAT IT SCANS. Every <config-root>/sessions/*.json record the liveness fence can see, across
    every config root on the machine, and for each one that places into a worktree, every file in
    that worktree outside `.git`. It prints the config-root count, the record count, how many placed,
    how many did not, and the number of files stat-ed on every run.

    WHAT MAKES IT FAIL. A record the fence rates LIVE whose worktree has seen no write for more than
    -MaxQuietHours. That is a session holding a worktree, and any claims taken in it, against work
    that stopped -- and nothing in this repository expires either one, by design.

    THE THRESHOLD IS A CHOICE, NOT A MEASUREMENT. 24 hours is a default, not a finding about how long
    a session should live. Set it to whatever your run's shape makes suspicious and say which number
    you used when you report the result.

    LAST WRITE IS THE NEWER OF TWO SIGNALS: the worktree's last commit, and the newest file mtime
    under it. One alone is wrong in an obvious way -- a session editing for six hours without
    committing has an ancient commit time, and a worktree nobody has touched can still hold a fresh
    file from a build. Taking the newer of the two is the conservative direction: it makes this check
    quieter, never louder.

    THE MTIME SWEEP IS COMPLETE, NEVER SAMPLED. It walks the whole worktree and prints how many files
    it stat-ed. A sampled sweep would report an age drawn from part of the tree while reading as an
    age for all of it.

    DEAD AND STALE RECORDS ARE A NOTE, NOT A FINDING. The registry is written by the client and its
    records outlive their processes routinely, so a dead record on disk is ordinary rather than a
    defect in this tooling. It is counted so the number is visible.

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/check-session-reaping.ps1
    pwsh -NoProfile -File scripts/validation/check-session-reaping.ps1 -SessionSource .\fixtures\broken\session-reaping\sessions.json
#>
[CmdletBinding()]
param(
    # How long a LIVE session may go without a write before it counts as unreaped.
    [int]$MaxQuietHours = 24,
    # A planted record list: a JSON array of { "cwd", "state", "lastWriteAt" }. A record carrying
    # lastWriteAt skips the mtime sweep, so a fixture can hold an age no live machine has yet.
    [string]$SessionSource = '',
    [string]$Repo = '',
    [switch]$Json,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/../coord/session-registry.ps1"
. "$PSScriptRoot/_receipt.ps1"

$r = New-CcxCheckReceipt -Check 'session-reaping' `
    -Question 'is any session still rated live long after the last write anywhere it works?' `
    -BrokenWhen "a LIVE record's worktree has seen no commit and no file write for over $MaxQuietHours hours"

$now = Get-Date
$filesStatted = 0

function Get-LastWrite {
    <#
    .SYNOPSIS
        The newest of a worktree's last commit and its newest file mtime, or $null.
    #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $best = $null

    $ct = Invoke-CcxGit -Repo $Path -Arguments @('log', '-1', '--format=%ct')
    if ($ct -and "$ct" -match '^\d+$') {
        $best = [System.DateTimeOffset]::FromUnixTimeSeconds([long]"$ct").LocalDateTime
    }

    # WHOLE TREE, NO CAP. Rule: an instrument reports what it scanned, and a capped walk would
    # report an age measured over part of a tree as an age for the tree.
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
        $script:filesStatted++
        if ($null -eq $best -or $f.LastWriteTime -gt $best) { $best = $f.LastWriteTime }
    }
    return $best
}

# --- the records ---------------------------------------------------------------------------------
$rows = [System.Collections.Generic.List[object]]::new()
$rootsExamined = 0
$recordFiles = 0

if ($SessionSource) {
    $r.Source = "planted session records ($SessionSource)"
    if (-not (Test-Path -LiteralPath $SessionSource)) {
        $r.Blocked = "no session source at $SessionSource"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    $planted = @()
    try { $planted = @(Get-Content -LiteralPath $SessionSource -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        $r.Blocked = "session source $SessionSource will not parse: $($_.Exception.Message)"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    $rootsExamined = 1
    foreach ($p in $planted) {
        $recordFiles++
        $lw = ConvertTo-CcxTime (Get-CcxField -Record $p -Name @('lastWriteAt'))
        $cwd = [string](Get-CcxField -Record $p -Name @('cwd'))
        if ($null -eq $lw) { $lw = Get-LastWrite -Path $cwd }
        $rows.Add([pscustomobject]@{
                Id        = [string](Get-CcxField -Record $p -Name @('sessionId', 'id'))
                Cwd       = $cwd
                State     = [string](Get-CcxField -Record $p -Name @('state'))
                LastWrite = $lw
            })
    }
}
else {
    $r.Source = 'the session registry (scripts/coord/session-registry.ps1) + worktree mtimes'
    $rootsExamined = @(Get-ClaudeConfigRoots).Count
    if ($rootsExamined -eq 0) {
        # A ZERO HERE IS NOT AN EMPTY FLEET. It is the reading a mistyped or moved config root gives,
        # and the two are byte-identical -- see scripts/validation/README.md for the measurement that
        # made this rule. Blocked, never CLEAN.
        $r.Blocked = 'no config root holding a sessions registry was found -- an empty fleet and a moved registry read identically, so this is UNKNOWN'
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    foreach ($h in @(Get-SessionRecords -IncludeUnreadable)) {
        $recordFiles++
        if ($h.Unreadable) {
            $r.Unreadable++
            continue
        }
        $l = Test-RecordLiveness -Record $h.Record
        $cwd = [string](Get-CcxField -Record $h.Record -Name @('cwd'))
        $rows.Add([pscustomobject]@{
                Id        = [string](Get-CcxField -Record $h.Record -Name @('sessionId'))
                Cwd       = $cwd
                State     = [string]$l.State
                LastWrite = $(if ($cwd) { Get-LastWrite -Path $cwd } else { $null })
            })
    }
}

# --- the verdict ----------------------------------------------------------------------------------
$placed = 0
$unplaceable = 0
$deadOnDisk = 0
foreach ($row in $rows) {
    if ($row.State -in @('DEAD', 'STALE')) { $deadOnDisk++ }
    if (-not $row.Cwd -or $null -eq $row.LastWrite) {
        # No cwd, or a cwd that is gone: the age cannot be measured. That is a hole in the census
        # rather than a pass, so it costs the run its CLEAN.
        $unplaceable++
        $r.Unreadable++
        continue
    }
    $placed++
    if ($row.State -ne 'LIVE') { continue }
    $quiet = ($now - $row.LastWrite).TotalHours
    if ($quiet -gt $MaxQuietHours) {
        $id = if ($row.Id) { $row.Id } else { '(no session id)' }
        Add-CcxFinding -Receipt $r -Text ("LIVE session $id in $($row.Cwd) has written nothing for " +
            "$([int]$quiet) hours (limit $MaxQuietHours) -- nothing reaped it")
    }
}

$r.Examined = $placed
Add-CcxCorpus -Receipt $r -Name 'config roots' -Count $rootsExamined
Add-CcxCorpus -Receipt $r -Name 'record files' -Count $recordFiles
Add-CcxCorpus -Receipt $r -Name 'records placed' -Count $placed
Add-CcxCorpus -Receipt $r -Name 'records unplaceable' -Count $unplaceable
Add-CcxCorpus -Receipt $r -Name 'files stat-ed' -Count $filesStatted

if ($deadOnDisk -gt 0) {
    Add-CcxNote -Receipt $r -Text "$deadOnDisk record(s) rate DEAD or STALE and are still on disk -- the client writes those files, so this is ordinary rather than a defect here"
}

Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
