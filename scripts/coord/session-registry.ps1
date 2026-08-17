#Requires -Version 7.3
<#
.SYNOPSIS
    Read the Claude Code session registry, and decide whether a session is actually alive.

.DESCRIPTION
    Dot-source this; it defines functions and does nothing on its own.

        . "$PSScriptRoot/session-registry.ps1"
        $l = Get-SessionLiveness -SessionId "1234abcd-..."
        if ($l.State -eq "LIVE") { ... }

    ONE COPY OF THE FENCE, ON PURPOSE. Both presence.ps1 (a roster) and sessions.ps1 (which MOVES a
    transcript, and must not do that under a running writer) need the same answer to "is this session
    alive". Two copies of a safety check drift, and the copy that drifts is the one nobody is testing.

    `<config-root>/sessions/<pid>.json` is the only registry containing EVERY surface -- the desktop
    app's own session tooling enumerates just the sessions it spawned, so an editor-extension session
    is absent from it entirely. Config roots are discovered dynamically because several logins can
    coexist (`~/.claude` plus any `~/.claude-account-N`) and a session is only visible to the login
    that owns it.

    VENDOR CONTRACT -- NOT OURS, AND IT CAN BREAK UNDER US
    -----------------------------------------------------
    Every fence in this repository rests on a record the CLIENT writes. We do not own its shape, its
    location, or its lifetime:

        <config-root>/sessions/<pid>.json
          pid         number   OS process id hosting the session (also the FILENAME)
          startedAt   number   unix epoch MILLISECONDS at which the session registered
          sessionId   string   uuid; callers may match on a unique prefix
          cwd         string   absolute directory the session was launched in
          entrypoint  string   which surface launched it (e.g. a desktop app, an editor extension)
          kind        string   interactive, or whatever else the client decides to write

    Fields we do not consume may appear; they are ignored. If a future client renames a field, moves
    the directory, or changes `startedAt`'s unit, every fence here degrades to "cannot tell" rather
    than to a confident wrong answer -- which is the whole reason the states below distinguish "not
    alive" from "could not be evaluated", and why only the positive answer licenses anything.

    THE TWO KINDS OF SCHEMA CHANGE DO NOT SURFACE THE SAME WAY, and it is worth knowing which you are
    looking at. A moved directory or a removed record shows up in the doctor's census as a count going
    to zero. A renamed field or a changed unit does NOT: those records still parse and still place, so
    the counts stay exactly as they were and every verdict turns UNVERIFIED instead. That is a veto, so
    the gates keep refusing rather than waving edits through -- it costs precision, not the guarantee.
    Do not read a healthy census as evidence the schema still matches.

    WHY THIS IS NOT A PID CHECK. Pids get reused, and these records outlive their process. The client
    ships a `procStart` field intended for exactly this fence -- do not depend on it. It may be absent
    or in a form you did not expect, and the guard shipped alongside it returns true when it cannot
    tell, i.e. it fails OPEN toward "still alive". So we read the process start time ourselves and
    require it to be consistent with the recorded session start: a process that started AFTER the
    session registered is a recycled pid, not that session.

    WHAT THE ANSWERS MEAN, AND WHAT THEY LICENSE:
      LIVE        pid resolves and its start time is consistent. Trustworthy.
      UNVERIFIED  pid resolves; the fence could not be evaluated. Treat as possibly-live.
      UNREADABLE  the record itself cannot be fenced (no pid, or one that is not a number). Treat as
                  possibly-live: a record being WRITTEN right now is exactly this shape, and a session
                  that just launched is the last thing that should read as absent.
      STALE       pid resolves but belongs to a different process. The session is gone.
      DEAD        no such pid.
      (Found=$false) no record at all -- it exited cleanly, or was never registered.

    ONLY THE POSITIVE ANSWER IS SAFE TO ACT ON. There is no heartbeat anywhere and registry writes are
    event-driven, so nothing here can PROVE a session is gone -- only that it is present. A
    DEAD/STALE/not-found verdict must never by itself authorise a destructive action; combine it with
    an independent signal and let either one veto.
#>

# Where the client keeps per-user state. USERPROFILE first because that is what the client itself
# uses where it is set; the fallbacks exist so that a caller on another platform gets an empty roster
# instead of a parameter-binding failure. A registry read that THROWS is the worst outcome available
# here: one of these runs inside a SessionStart hook, where a terminating error replaces the chat's
# whole starting context.
function Get-ClaudeHomeDirectory {
    [CmdletBinding()]
    param()
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    try { return [Environment]::GetFolderPath('UserProfile') } catch { return '' }
}

# Every config root that actually holds a session registry.
function Get-ClaudeConfigRoots {
    [CmdletBinding()]
    param([string[]]$ConfigRoot)
    if ($ConfigRoot) { return @($ConfigRoot | Where-Object { Test-Path $_ }) }
    $home_ = Get-ClaudeHomeDirectory
    if (-not $home_) { return @() }
    return @(
        Get-ChildItem -Path $home_ -Directory -Filter ".claude*" -Force -EA SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName "sessions") } |
            ForEach-Object { $_.FullName }
    )
}

# Every registry record, with the root it came from attached.
#
# -IncludeUnreadable also returns a row for every file that could NOT be parsed (Record = $null,
# Unreadable = $true). A caller about to destroy something needs those: a record that is half-written
# -- i.e. a session that launched a moment ago -- fails to parse, and DROPPING it silently turns an
# occupied worktree from SKIP into PRUNE while the receipt reports one fewer record than existed.
# It is off by default so the read-only roster callers keep the shape they already handle.
function Get-SessionRecords {
    [CmdletBinding()]
    param([string[]]$ConfigRoot, [switch]$IncludeUnreadable)
    $out = @()
    foreach ($root in (Get-ClaudeConfigRoots -ConfigRoot $ConfigRoot)) {
        foreach ($f in @(Get-ChildItem (Join-Path $root "sessions") -Filter *.json -EA SilentlyContinue)) {
            # A single malformed record must never take down a caller -- one of these runs in a
            # SessionStart hook, where a throw replaces the chat's whole starting context.
            $rec = $null
            $err = ''
            try { $rec = Get-Content $f.FullName -Raw -EA Stop | ConvertFrom-Json -EA Stop } catch { $err = $_.Exception.Message }
            if (-not $rec) {
                if (-not $err) { $err = 'the file parsed to nothing (empty, or being written right now)' }
                if ($IncludeUnreadable) {
                    $out += [pscustomobject]@{ Record = $null; Root = $root; File = $f.FullName; Unreadable = $true; Error = $err }
                }
                continue
            }
            $out += [pscustomobject]@{ Record = $rec; Root = $root; File = $f.FullName; Unreadable = $false; Error = '' }
        }
    }
    return $out
}

# The fence. See the header for why this is not just "is the pid alive".
function Test-RecordLiveness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Record,
        # How far a process may have started BEFORE its session registered and still be the same run.
        # Generous: registration follows process start, but a cold start on a loaded box can lag.
        [int]$StartSkewMinutes = 15
    )
    if (-not $Record) { return @{ State = "UNREADABLE"; Detail = "no record to fence" } }
    # A record with NO pid cannot be fenced, so it is UNREADABLE, not DEAD. It used to report DEAD --
    # which is not a veto anywhere -- and a registry file caught mid-write has exactly this shape, so a
    # session that had just launched read as "nobody is there" to a caller about to delete its worktree.
    $procId = [int]$Record.pid
    if (-not $procId) { return @{ State = "UNREADABLE"; Detail = "no pid in record; it cannot be fenced" } }

    $proc = Get-Process -Id $procId -EA SilentlyContinue
    if (-not $proc) { return @{ State = "DEAD"; Detail = "pid $procId not running" } }

    $procStart = $null
    try { $procStart = $proc.StartTime } catch { }
    if (-not $procStart) {
        # Access can be denied for a process in another context. Report the uncertainty rather than
        # upgrading it to LIVE: an unverifiable fence is not a passed fence.
        return @{ State = "UNVERIFIED"; Detail = "pid $procId alive; start time unreadable" }
    }
    if ($null -eq $Record.startedAt) {
        return @{ State = "UNVERIFIED"; Detail = "pid $procId alive; record has no startedAt" }
    }

    # THE PARSE ITSELF THROWS ON A BIG ENOUGH NUMBER, so it is guarded before the bound below can be
    # reached. FromUnixTimeMilliseconds accepts roughly year 1 to year 9999 and raises outside that,
    # and a microsecond-valued field is three orders of magnitude past the ceiling. Caught here, the
    # first version of this fix let the exception escape, left $registered null, and then threw a
    # second time formatting the message -- so the record's verdict depended on which caller had
    # $ErrorActionPreference set to what. An unparseable field is exactly "cannot tell".
    $registered = $null
    try {
        $registered = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Record.startedAt).LocalDateTime
    } catch {
        return @{
            State  = "UNVERIFIED"
            Detail = ("pid $procId alive; startedAt '$($Record.startedAt)' is not readable as a " +
                "millisecond epoch, so the field's unit or format is not what this fence assumes")
        }
    }

    # THE UNIT IS AN ASSUMPTION, AND IT IS THE ONE THAT INVERTS THIS FENCE.
    #
    # This header promises that a change to `startedAt`'s unit degrades to "cannot tell" rather than
    # to a confident wrong answer. Until 2026-08-16 it did the opposite, and the path was short: the
    # parse above is unconditionally milliseconds, so a switch to SECONDS lands `$registered` in 1970,
    # the delta below is roughly 29 million minutes, and every record falls straight through to STALE.
    #
    # STALE IS NOT A VETO. `$OccupancyVetoStates` in occupancy.ps1 is LIVE/UNVERIFIED/UNREADABLE, and
    # this file defines STALE as "The session is gone." So one vendor-side unit change would have made
    # presence.ps1 print "No live sessions found for this repo." with exit 0 -- a roster asserting its
    # own completeness while naming nobody -- and collision_gate.ps1 exit 0 in silence. A wrong answer
    # delivered confidently, in the fence every other control is built on.
    #
    # THE BOUND IS ON PLAUSIBILITY, NOT ON THE DELTA, because the delta cannot tell a recycled pid
    # from a misparsed field: both are "the process started long after the session". A registration
    # time is only meaningful if reading it as milliseconds puts it in a window a session could
    # actually have registered in. Outside that, the field is not what this fence assumes, which is
    # the definition of UNVERIFIED rather than of STALE.
    #
    # Seconds land in 1970 and trip the floor here. Microseconds and nanoseconds never reach this
    # check at all -- they are past what the parse itself accepts, so the guard above takes them. The
    # ceiling covers what is left: a value inside the parseable range but ahead of now, which is a
    # future-dated record rather than a unit change. Every one of them becomes a veto.
    $floor = [datetime]'2020-01-01'
    if ($registered -lt $floor -or $registered -gt (Get-Date).AddDays(1)) {
        return @{
            State  = "UNVERIFIED"
            Detail = ("pid $procId alive; startedAt $($Record.startedAt) parses as " +
                "$($registered.ToString('yyyy-MM-dd')) in milliseconds, which is not a time a session " +
                "could have registered -- the field's unit or format is not what this fence assumes")
        }
    }

    # A process cannot have started after the session it hosts registered (small forward slop for
    # clock jitter). Started much later => this pid was recycled onto a different process.
    $delta = ($procStart - $registered).TotalMinutes
    if ($delta -gt 1) {
        return @{ State = "STALE"; Detail = "pid $procId reused (process started $([int]$delta)m after the session)" }
    }
    if ($delta -lt (-1 * $StartSkewMinutes)) {
        return @{ State = "STALE"; Detail = "pid $procId start precedes the session by $([int](-$delta))m" }
    }
    return @{ State = "LIVE"; Detail = "" }
}

# Look one session up by id (full or unique prefix) and fence it.
function Get-SessionLiveness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string[]]$ConfigRoot,
        [int]$StartSkewMinutes = 15
    )
    $hit = @(Get-SessionRecords -ConfigRoot $ConfigRoot |
        Where-Object { $_.Record.sessionId -and ([string]$_.Record.sessionId).StartsWith($SessionId, 'OrdinalIgnoreCase') })

    if ($hit.Count -eq 0) {
        # Not registered. NOT proof it is gone -- a session that never registered looks identical to
        # one that exited cleanly, so callers must fall back to an independent signal.
        return @{ Found = $false; State = "UNKNOWN"; Detail = "no registry record"; Record = $null }
    }
    # More than one match on a prefix: fence them all and report the most-alive, because the caller is
    # about to decide whether it is safe to disturb something.
    # UNREADABLE ranks with the possibly-live states, not with the gone ones: it means the fence could
    # not be evaluated, and an unevaluated fence is not a passed fence.
    $rank = @{ "LIVE" = 0; "UNVERIFIED" = 1; "UNREADABLE" = 2; "STALE" = 3; "DEAD" = 4 }
    $best = $null
    foreach ($h in $hit) {
        $l = Test-RecordLiveness -Record $h.Record -StartSkewMinutes $StartSkewMinutes
        if (-not $best -or $rank[$l.State] -lt $rank[$best.State]) {
            $best = @{ Found = $true; State = $l.State; Detail = $l.Detail; Record = $h.Record }
        }
    }
    return $best
}
