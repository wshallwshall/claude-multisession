#Requires -Version 7.3
<#
.SYNOPSIS
    Who is ACTUALLY live in this repo right now -- across every Claude Code surface.

.DESCRIPTION
    `claim.ps1` answers "what is being built"; this answers "who is here". They are different failures:
    a claim tells you work is taken, presence tells you whether the session that took it still exists.

    WHY THIS EXISTS RATHER THAN THE OBVIOUS ALTERNATIVES
    ----------------------------------------------------
    The desktop app's session tooling (its `list_sessions` MCP tool) enumerates an in-memory map of
    sessions THE DESKTOP APP ITSELF SPAWNED. A session launched by the editor extension is never
    entered into it -- not filtered out, never registered -- so it is invisible to that tool and cannot
    be addressed by it. Verified directly: a live editor-extension session sharing the DEFAULT config
    root was absent from `list_sessions` while its sibling desktop sessions were listed. It is not a
    login split, and it is not something a caller can work around by asking more politely.

    `<config-root>/sessions/<pid>.json` is the only registry that contains every surface. This script
    reads that, so an editor session in the primary checkout shows up next to desktop sessions in
    worktrees. Config roots are discovered dynamically (~/.claude plus any ~/.claude-account-N), because
    several logins can be in play on one machine and a session is only visible to the login that owns it.

    LIVENESS IS A FENCE, NOT A PID CHECK
    ------------------------------------
    A bare `is pid alive` check is wrong: PIDs are reused, and these files outlive their process -- a
    session that dies uncleanly leaves its record behind, and stale records naming long-dead processes
    are routine rather than exceptional. The client's own registry carries a `procStart` field intended
    for exactly this fence, but do not depend on it: it may be absent or in a form you did not expect,
    and the guard shipped with it passes when it cannot tell. We therefore compute process start time
    OURSELVES and require it to be consistent with the recorded session start. A reused PID hosts a
    process that started AFTER the session registered, and that is what STALE means below.

    A session is reported LIVE only when its pid resolves AND that process's start time is consistent.
    Anything else is STALE (pid reused or file orphaned) or DEAD (no such pid).

    READ-ONLY. This script never writes, never deletes a registry file, and never contacts another
    session. It is a roster, not a channel.

    The cwd -> worktree matcher and the availability receipt live in occupancy.ps1, shared with
    prune-merged.ps1 (which DELETES a worktree, so it must reach the same verdict this roster does).
    This script only labels and renders what that returns.

.EXAMPLE
    pwsh -NoProfile -File scripts/coord/presence.ps1
    pwsh -NoProfile -File scripts/coord/presence.ps1 -All        # include stale/dead entries
    pwsh -NoProfile -File scripts/coord/presence.ps1 -Json       # machine-readable
#>
[CmdletBinding()]
param(
    # Config roots to scan. Defaults to every ~/.claude* directory (each desktop / CLI / editor login).
    # Tests point this at a fixture directory, so the real discovery logic is what gets exercised.
    [string[]]$ConfigRoot,
    # Show STALE and DEAD entries too. Default lists only sessions that are actually live.
    [switch]$All,
    # Emit JSON instead of a table.
    [switch]$Json,
    # Repo to scope to. Defaults to the current worktree's repo family (all worktrees sharing one .git).
    [string]$Repo,
    # Treat this pid as "me" so the roster can mark the calling session. Defaults to auto-detection by
    # ancestry (see Get-SelfPids) -- 0 means "work it out", which is what every real invocation wants.
    [int]$SelfPid = 0,
    # How far a process may have started BEFORE its session registered and still be the same run.
    # Generous: registration follows process start, but a cold start on a loaded box can lag.
    [int]$StartSkewMinutes = 15
)

$ErrorActionPreference = "Stop"

# --- Registry access, the liveness fence, and the cwd -> worktree matcher ------------------------
# All shared: sessions.ps1 needs the SAME answer to "is this session alive" before it moves a
# transcript, and prune-merged.ps1 needs the SAME answer to "is anybody in this checkout" before it
# DELETES one. Two copies of a safety check drift, and the copy that drifts is the one nobody tests.
. "$PSScriptRoot/occupancy.ps1"

function Get-LoginLabel([string]$RootPath) {
    $leaf = Split-Path $RootPath -Leaf
    if ($leaf -ieq ".claude") { return "default" }
    return ($leaf -replace '^\.claude-account-', 'acct-') -replace '^\.claude-?', ''
}

# The surface a session was launched from. This is the field that makes editor-extension sessions
# visible at all, so it is reported verbatim when it is something we do not recognise rather than
# folded into "other".
function Get-SurfaceLabel([string]$Entrypoint) {
    switch -Regex ($Entrypoint) {
        '^claude-desktop$' { return "desktop" }
        '^claude-vscode$' { return "vscode" }
        '^$' { return "?" }
        default { return $Entrypoint -replace '^claude-', '' }
    }
}

# --- Which of these sessions is the caller ------------------------------------------------------
# NOT $PID: this script runs as a pwsh child (often a grandchild, via a hook), so its own pid never
# appears in the registry. The session that invoked us is an ANCESTOR, so walk the parent chain and
# treat every pid on it as "self". Getting this wrong is not cosmetic -- a roster that cannot tell you
# from a sibling is one you will act on as though someone else were in your own worktree.

# The whole process table as pid -> parent pid, in ONE call. Not one lookup per ancestor: this runs on
# every SessionStart, and a dozen round-trips is the difference between a hook you notice and one you
# don't. Throws if it cannot produce a usable table -- the caller turns that into a stated degradation,
# because the previous version fell back silently and the self-marker simply stopped appearing on every
# platform except the one it was written on.
function Get-ProcessParentMap {
    $map = @{}
    if ($IsWindows) {
        Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -EA Stop |
            ForEach-Object { $map[[int]$_.ProcessId] = [int]$_.ParentProcessId }
        if ($map.Count -eq 0) { throw "the process table came back empty" }
        return $map
    }
    # POSIX. `-A` rather than `-e`: both mean "every process" on Linux, but on some BSD-derived
    # platforms `-e` means "show the environment too", which is a different and much larger answer.
    # Empty headers (`pid=`) so there is no header row to skip.
    $lines = @(& ps -A -o pid=,ppid= 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "ps exited $LASTEXITCODE" }
    foreach ($line in $lines) {
        if ($line -match '^\s*(\d+)\s+(\d+)\s*$') { $map[[int]$Matches[1]] = [int]$Matches[2] }
    }
    if ($map.Count -eq 0) { throw "ps produced no parseable pid/ppid rows" }
    return $map
}

function Get-SelfPids([int]$Override) {
    if ($Override -gt 0) {
        return [pscustomobject]@{ Pids = @($Override); Degraded = $false; Detail = '' }
    }

    $ppid = $null
    try { $ppid = Get-ProcessParentMap }
    catch {
        # Fail open -- but SAY SO. Every row simply loses its "this is you" marker; nothing else in the
        # roster is affected, and an unmarked roster is still worth reading.
        return [pscustomobject]@{
            Pids = @($PID); Degraded = $true
            Detail = "could not read the process table ($($_.Exception.Message)); the '<-- THIS session' marker is unavailable"
        }
    }

    $chain = @()
    $cur = $PID
    # Bounded: a runaway or cyclic parent chain must not hang a SessionStart hook.
    for ($i = 0; $i -lt 12 -and $cur -gt 0; $i++) {
        $chain += $cur
        $parent = $ppid[$cur]
        if (-not $parent -or $parent -le 0 -or $chain -contains $parent) { break }
        $cur = $parent
    }
    return [pscustomobject]@{ Pids = $chain; Degraded = $false; Detail = '' }
}

# --- Collect ------------------------------------------------------------------------------------
$occ = Get-WorktreeOccupancy -Repo $Repo -ConfigRoot $ConfigRoot -StartSkewMinutes $StartSkewMinutes
if (-not $occ.RepoFound) {
    if ($Json) { "[]" | Write-Output } else { Write-Host "Not inside a git repository -- nothing to scope presence to." }
    exit 0
}

$self = Get-SelfPids $SelfPid
$selfPids = @($self.Pids)
if ($self.Degraded) {
    # STDERR, like the availability receipt below: a degraded marker must be visible without polluting
    # the JSON on stdout that other tools parse.
    [Console]::Error.WriteLine("presence: $($self.Detail).")
}

$rows = @()
foreach ($s in $occ.Sessions) {
    $rows += [pscustomobject]@{
        State     = $s.State
        Detail    = $s.Detail
        Surface   = Get-SurfaceLabel $s.Entrypoint
        Login     = Get-LoginLabel $s.Root
        SessionId = $s.SessionId
        Short     = $s.Short
        Pid       = $s.Pid
        Cwd       = $s.Cwd
        Worktree  = $s.Worktree
        IsPrimary = $s.IsPrimary
        Branch    = $s.Branch
        Kind      = $s.Kind
        IsSelf    = ($selfPids -contains [int]$s.Pid)
        StartedAt = $s.StartedAt
    }
}

$order = @{ "LIVE" = 0; "UNVERIFIED" = 1; "UNREADABLE" = 1; "STALE" = 2; "DEAD" = 3 }
$rows = @($rows | Sort-Object @{ E = { $order[$_.State] } }, @{ E = { $_.Worktree } })
# Anything that is live, or that we could not prove ISN'T, stays in the default view: an unverifiable
# fence is not a passed fence.
if (-not $All) { $rows = @($rows | Where-Object { Test-OccupancyVeto $_.State }) }

if ($Json) {
    # The receipt goes to STDERR, deliberately: stdout stays a pure JSON array so every existing
    # consumer keeps working, but "the fence could not look" no longer renders as an indistinguishable
    # `[]`. Without this, a session banner reports an unavailable fence as "nobody else is here" -- a
    # green light derived from nothing having been measured.
    if (-not $occ.Available) {
        [Console]::Error.WriteLine("presence: roster UNAVAILABLE -- $($occ.Detail). $($occ.RootsExamined) config root(s), $($occ.RecordsExamined) record(s) examined. An empty list here is NOT 'nobody is live'.")
    }
    # -Depth so nested pscustomobjects survive; -AsArray so a single row is still a JSON list and a
    # caller can index it without special-casing.
    #
    # ALWAYS EMIT AN ARRAY, and note that -AsArray is NOT enough on its own: `@() | ConvertTo-Json
    # -AsArray` sends ZERO objects down the pipeline, so ConvertTo-Json never runs and this branch
    # printed NOTHING for an empty roster -- while the not-a-repo path above printed `[]`. Two
    # different spellings of "no peers", one of which is byte-identical to "the script died before it
    # answered", and at least one consumer already treats no-output as a failed lookup. `[]` is a
    # resolved answer; nothing is not an answer at all. (-InputObject is not the fix: with -AsArray it
    # double-wraps to [[]].)
    if ($rows.Count -eq 0) { Write-Output "[]" }
    else { ($rows | ConvertTo-Json -Depth 4 -AsArray) | Write-Output }
    exit 0
}

if ($rows.Count -eq 0) {
    # "Nobody is here" and "I could not look" produce the same empty list, so say which one it is.
    if (-not $occ.Available) {
        Write-Host "Roster UNAVAILABLE -- $($occ.Detail)." -ForegroundColor Yellow
        Write-Host "  This is NOT 'nobody is live'. Nothing was examined, so nothing can be concluded." -ForegroundColor Yellow
    }
    else {
        Write-Host "No live sessions found for this repo." -ForegroundColor DarkGray
        Write-Host "  (fence: $($occ.RootsExamined) config root(s), $($occ.RecordsExamined) record(s) examined.)" -ForegroundColor DarkGray
    }
    Write-Host "(Add -All to include stale/dead registry entries.)" -ForegroundColor DarkGray
    exit 0
}

Write-Host ""
Write-Host "Live Claude sessions in this repo ($($rows.Count)):"
foreach ($r in $rows) {
    $me = if ($r.IsSelf) { "  <-- THIS session" } else { "" }
    $warn = if ($r.IsPrimary -and -not $r.IsSelf) { "  [in the SHARED PRIMARY]" } else { "" }
    $state = if ($r.State -eq "LIVE") { "" } else { "  [$($r.State): $($r.Detail)]" }
    Write-Host ("  {0,-8} {1,-7} {2,-34} {3}" -f $r.Short, $r.Surface, $r.Worktree, $r.Branch)
    if ($me -or $warn -or $state) { Write-Host ("           {0}{1}{2}" -f $me.TrimStart(), $warn, $state) }
}
Write-Host ""
Write-Host "  See what they are building:  pwsh -NoProfile -File scripts/coord/claim.ps1 -List"
Write-Host "  See what they are touching:  pwsh -NoProfile -File scripts/coord/overlap.ps1"
Write-Host ""
exit 0
