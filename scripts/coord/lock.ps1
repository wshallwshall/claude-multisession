#Requires -Version 7.3
<#
.SYNOPSIS
    A short-lived, cross-session mutex for operations that are NOT safe to run concurrently.

.DESCRIPTION
    Dot-source this and wrap the critical section:

        . "$PSScriptRoot/../coord/lock.ps1"
        $lock = Enter-CcxLock -Name "worktree-add"
        try { ...the operation... } finally { Exit-CcxLock $lock }

    Same atomic test-and-set as claim.ps1 and alloc.ps1: it claims by EXCLUSIVELY CREATING a file in
    <state-root>/locks/, and the failed create IS the mutual exclusion. A read-modify-write on a
    shared list is not an option here -- measured on the repo this was developed in, PowerShell
    silently lost 4 of 8 concurrent writes to a single shared file.

    DIFFERENT FROM claim.ps1, DELIBERATELY. A claim is a long-lived note about WORK ("I am building
    the auth rewrite"), held for a session, advisory, and released by hand. This is a short-lived
    mutex around a single OPERATION measured in seconds. That difference is why this one retries and
    claims do not.

    NO TTL, HERE OR ANYWHERE ELSE IN THIS DIRECTORY -- and the omission is the design, not an
    oversight. A lock that expires on a timer hands the critical section to a second process while
    the first is still inside it, and it does so silently, at the exact moment the operation is
    slowest (which is when a timeout is most likely to be the wrong inference). The failure it
    prevents -- a wedged lock -- is visible and one command from fixed. The failure it causes is a
    concurrent double-write nobody observes. So: no expiry, no reaper, no "probably dead".

    WE RETRY; WE NEVER STEAL. Breaking a lock we cannot prove is abandoned re-opens the exact race
    the lock exists to close, and there is no reliable liveness signal to prove it with: the session
    registry has no heartbeat, and the harness's shipped pid + process-start guard fails OPEN toward
    "still alive". So on timeout this FAILS LOUDLY with the holder's identity and the manual
    override, rather than quietly deciding the holder is dead. A wedged lock you can see beats a
    silent double-write you cannot.

    Do not use this for anything held longer than seconds. git's own posture works because a .lock
    is held for microseconds around one write, so a crash rarely lands inside it; the longer the
    hold, the more likely a crash leaves a lock nobody can safely break.
#>

# The state root, the path folding and the git plumbing live in one place. Dot-sourcing here rather
# than requiring the caller to do it means Enter-CcxLock works from any script that loads only
# this file. Re-dot-sourcing when the caller already loaded _common.ps1 is harmless.
. "$PSScriptRoot/_common.ps1"

# Returns the lock's path, to be passed back to Exit-CcxLock.
function Enter-CcxLock {
    [CmdletBinding()]
    param(
        # Lock identity. One name = one mutex; unrelated operations should use different names.
        [Parameter(Mandatory)][string]$Name,
        # How long to wait for a sibling to finish before giving up. Sized for the operation.
        [int]$TimeoutSeconds = 90,
        # Repo to anchor the lock directory to. Defaults to the current repo's shared git dir, so
        # every worktree AND the primary checkout resolve to the same lock.
        [string]$Repo
    )

    # Get-CcxStateRoot resolves <git-common-dir>/<prefix>-coord: identical across every worktree of
    # a clone (so the mutex is genuinely cross-session), isolated per clone, and uncommittable.
    try {
        $root = Get-CcxStateRoot -Repo $Repo
    } catch {
        throw "Enter-CcxLock: not inside a git repository ($($_.Exception.Message))"
    }

    $dir = Join-Path $root 'locks'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    # Same folding as claim keys: the FILENAME is the mutex, so two spellings of one name must
    # collapse to one file or the lock does not lock.
    $safe = ConvertTo-CcxSafeName $Name
    if (-not $safe) { throw "Enter-CcxLock: name '$Name' reduces to nothing usable." }
    $lock = Join-Path $dir "$safe.lock"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
        try {
            $fs = [System.IO.File]::Open(
                $lock,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            try {
                # Recorded so a wedged lock names its holder instead of being an anonymous mystery.
                # [Environment]::MachineName rather than $env:COMPUTERNAME: that variable exists only
                # on Windows, and interpolating a null there produced "host= at=..." -- a receipt that
                # silently drops the one field telling you which machine to go and look at.
                $who = [System.Text.Encoding]::UTF8.GetBytes(
                    "pid=$PID host=$([System.Environment]::MachineName) at=$((Get-Date).ToString('o'))")
                $fs.Write($who, 0, $who.Length)
            } finally { $fs.Dispose() }
            return $lock
        } catch [System.IO.IOException] {
            if ((Get-Date) -gt $deadline) {
                $held = "(unreadable)"
                try { $held = (Get-Content -LiteralPath $lock -Raw -EA Stop).Trim() } catch { }
                throw (
                    "Timed out after ${TimeoutSeconds}s waiting for the '$safe' lock.`n" +
                    "  held by: $held`n" +
                    "  NOT stealing it -- there is no reliable way to prove that session is gone, and`n" +
                    "  breaking the lock re-opens the race it exists to prevent.`n" +
                    "  If you are certain that session is dead, delete it by hand:`n" +
                    "      Remove-Item -LiteralPath '$lock'")
            }
            Start-Sleep -Milliseconds 200
        }
    }
}

function Exit-CcxLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LockPath)
    # Best-effort: a failure to release must never mask the real error from the critical section,
    # which is usually why we are unwinding in the first place.
    Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
}
