#Requires -Version 7.3
<#
.SYNOPSIS
    Move uncommitted work OUT of the shared primary checkout and into a fresh worktree + branch.

.DESCRIPTION
    The companion to the worktree gate. A gate that stops you writing into the primary is infuriating
    if you are already half-way through a change there -- so this MOVES what you have instead of asking
    you to redo it.

    It stashes the primary's uncommitted work (tracked AND untracked), creates a worktree branched off
    the primary's CURRENT commit -- not the trunk, so the stash applies cleanly -- and pops the stash
    there.

    THE STASH IS THE SAFETY NET. If the pop fails for any reason the work is still in `git stash list`,
    and this script says so instead of swallowing it. Nothing is ever discarded.

.EXAMPLE
    pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name alerts-fix
    pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name alerts-fix -NoSetup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9._-]+\z')]
    [string]$Name,

    # Forwarded to new.ps1: create the worktree without running the repository's setup hook.
    [switch]$NoSetup
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../coord/_common.ps1')

# The PRIMARY, explicitly -- not "the checkout this script lives in". This command exists to empty the
# one directory several sessions share, so resolving it from the script's own location would quietly
# rescue a linked worktree instead, and report success for having done the wrong thing.
$PrimaryRoot = Get-CcxPrimaryRoot
if (-not $PrimaryRoot) { throw "Not inside a git repository (could not locate the primary checkout)." }

$Target = Get-CcxWorktreePath -Name $Name -PrimaryRoot $PrimaryRoot
if (Test-Path -LiteralPath $Target) {
    throw "Worktree path already exists: $Target  (pick another -Name, or just work in it)"
}

$dirty = @(& git -C $PrimaryRoot status --porcelain)
if ($dirty.Count -eq 0) {
    Write-Host "Nothing to rescue: $PrimaryRoot is clean." -ForegroundColor Yellow
    Write-Host "You want a plain new worktree instead:  scripts/worktree/new.ps1 -Name $Name"
    return
}

$sha = (& git -C $PrimaryRoot rev-parse HEAD).Trim()
Write-Host "Rescuing $($dirty.Count) change(s) from $PrimaryRoot (at $($sha.Substring(0,7)))..."
$dirty | Select-Object -First 12 | ForEach-Object { Write-Host "  $_" }
if ($dirty.Count -gt 12) { Write-Host "  ... and $($dirty.Count - 12) more" }

# --include-untracked carries untracked files too. Without it they are left behind in the primary and
# then silently DUPLICATED the moment the new worktree recreates them -- two copies, diverging, and no
# indication which one the session is editing.
$stashMsg = "rescue -> $Name"
& git -C $PrimaryRoot stash push --include-untracked -m $stashMsg
if ($LASTEXITCODE -ne 0) { throw "git stash push failed (exit $LASTEXITCODE) -- nothing was moved." }

$stashed = $true
try {
    # Branch the worktree off the primary's CURRENT commit so the stash applies without conflict.
    # new.ps1 would otherwise default to the trunk, which the primary is often many commits behind.
    $newArgs = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'new.ps1'), '-Name', $Name, '-Base', $sha)
    if ($NoSetup) { $newArgs += '-NoSetup' }
    & pwsh @newArgs
    if ($LASTEXITCODE -ne 0) { throw "new.ps1 failed (exit $LASTEXITCODE)" }

    & git -C $Target stash pop
    if ($LASTEXITCODE -ne 0) { throw "git stash pop failed in $Target (exit $LASTEXITCODE)" }
    $stashed = $false

    Write-Host ''
    Write-Host "Rescued into $Target (branch '$Name', off $($sha.Substring(0,7)))." -ForegroundColor Green
    Write-Host 'The primary checkout is clean again. Continue here:'
    Write-Host "  cd `"$Target`""
}
finally {
    if ($stashed) {
        # Print the recovery path, not just the failure. This block is the difference between "your
        # work is somewhere" and "your work is gone": the stash still holds everything, and the exact
        # commands to see it and put it back are here rather than in a document nobody opens mid-panic.
        Write-Warning 'Rescue did not complete. YOUR WORK IS SAFE -- it is in the stash:'
        Write-Warning "    git -C `"$PrimaryRoot`" stash list        # look for: $stashMsg"
        Write-Warning "    git -C `"$PrimaryRoot`" stash pop         # put it back in the primary"
        Write-Warning 'Nothing was discarded. Resolve the failure above, then retry or pop it by hand.'
    }
}
