#Requires -Version 7.3
<#
.SYNOPSIS
    Create a parallel-session worktree (via new.ps1) AND open an editor window in it -- one step.

.DESCRIPTION
    A thin wrapper. new.ps1 owns the worktree creation and the setup hook; this adds nothing to that
    and deliberately holds no safety property of its own. It relies on new.ps1 THROWING, so an editor
    is never opened on a worktree that was not created.

    The whole point of a worktree is that each parallel session gets its own branch and its own files.
    Start the second session in the window this opens -- not back in the checkout you launched from.

.EXAMPLE
    ./spawn.ps1 -Name alerts
    ./spawn.ps1 -Name alerts -Base feature/some-work
    ./spawn.ps1 -Name alerts -Editor subl
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9._-]+\z')]
    [string]$Name,

    # Forwarded to new.ps1. Omitted means "whatever new.ps1 resolves the trunk to" -- do not duplicate
    # that default here, or the two will drift and only one of them will be right.
    [string]$Base,

    # Forwarded to new.ps1: create the worktree without running the repository's setup hook.
    [switch]$NoSetup,

    # The editor command to launch. Default: CCX_EDITOR, else EDITOR, else 'code'.
    [string]$Editor
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../coord/_common.ps1')

# Forward to new.ps1 first. It throws on failure, which stops us here -- before we open an editor on a
# path that does not exist.
$newArgs = @{ Name = $Name }
if ($Base) { $newArgs.Base = $Base }
if ($NoSetup) { $newArgs.NoSetup = $true }
& (Join-Path $PSScriptRoot 'new.ps1') @newArgs

# Ask for the path rather than recomputing it. The layout formula lived in four scripts once, and the
# copies disagreed; asking the one helper means this file cannot be the one that is wrong.
$PrimaryRoot = Get-CcxPrimaryRoot
$WorktreePath = Get-CcxWorktreePath -Name $Name -PrimaryRoot $PrimaryRoot

if (-not $Editor) {
    $Editor = if ($env:CCX_EDITOR) { $env:CCX_EDITOR } elseif ($env:EDITOR) { $env:EDITOR } else { 'code' }
}

if (Get-Command $Editor -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host "Opening $Editor in $WorktreePath ..." -ForegroundColor Green
    & $Editor $WorktreePath
    Write-Host "Start your second session IN THAT WINDOW -- it is isolated on branch '$Name'." -ForegroundColor Green
} else {
    # Not a failure: the worktree is created and usable, which is the deliverable. Say exactly what did
    # not happen and what to do, rather than exiting green and letting the user assume a window opened.
    Write-Warning "'$Editor' is not on PATH; open this folder yourself and start the second session there:"
    Write-Host "  $WorktreePath"
    Write-Host "  (set CCX_EDITOR or EDITOR, or pass -Editor <command>, to pick a different editor)"
}
