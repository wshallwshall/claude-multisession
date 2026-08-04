#Requires -Version 7.3
<#
.SYNOPSIS
    Re-attach the shared primary checkout to its home branch after a session left it detached or on the
    wrong branch.

.DESCRIPTION
    The primary checkout is the one directory several sessions stand in at once. When a session runs
    `git checkout <its-branch>` there -- or leaves HEAD detached -- every other session's files silently
    become a different commit's files, with nothing on screen to say so. The worktree gate DENIES the
    tree-swapping git verbs in the primary, so this script is the sanctioned way back: a session may
    REPAIR the primary, but it may not hijack it.

    "Home branch" is, in order:
      1. -Branch, for this run only
      2. `git config <prefix>.homeBranch`, if you want something other than the default
      3. the local branch matching the configured trunk (origin/main -> main), if it exists
      4. `main`, then `master`

    IT REFUSES IF THE PRIMARY'S TREE IS DIRTY. Re-attaching would either carry someone else's
    uncommitted work onto another branch or lose it, and this script cannot tell whose work it is. Move
    it out first with rescue.ps1 -- which is not destructive -- or pass -Force to re-attach anyway.
    -Force does not discard anything either: the changes stay in the tree, they just land on the home
    branch.

.EXAMPLE
    pwsh -NoProfile -File scripts/worktree/restore-primary.ps1
    pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -Branch main
    pwsh -NoProfile -File scripts/worktree/restore-primary.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # Override the home branch for this run.
    [string]$Branch,

    # Re-attach even if the primary's tree is dirty. The changes stay in the tree; nothing is discarded.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../coord/_common.ps1')

# The PRIMARY is the first entry of `git worktree list` -- the main working tree, whichever checkout
# this script happens to be invoked from. Never cwd: the whole point is to repair a directory you are
# probably not standing in.
$primary = Get-CcxPrimaryRoot
if (-not $primary) { throw "Could not locate the primary checkout (is this a git repository?)." }

$cfg = Get-CcxConfig -From $primary

$head = (& git -C $primary rev-parse --abbrev-ref HEAD).Trim()
$detached = ($head -eq 'HEAD')

if (-not $Branch) {
    $Branch = Invoke-CcxGit -Repo $primary -Arguments @('config', '--get', "$($cfg.prefix).homeBranch")
}
if (-not $Branch) {
    # Derive it from the trunk before falling back to a guess: a project whose default branch is named
    # something else entirely still gets the right answer, and it gets it from the same source every
    # other script in this repo uses rather than from a second, drifting list of names.
    $candidates = @()
    try {
        $trunk = Get-CcxTrunk -Repo $primary
        if ($trunk) { $candidates += ($trunk -replace '^[^/]+/', '') }
    } catch { }
    $candidates += @('main', 'master')

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (Invoke-CcxGit -Repo $primary -Arguments @('rev-parse', '--verify', '--quiet', "refs/heads/$candidate")) {
            $Branch = $candidate
            break
        }
    }
}
if ($Branch) { $Branch = $Branch.Trim() }

if (-not $Branch) {
    throw ("Could not determine a home branch for $primary and none exists under the usual names. " +
        "Pass -Branch, or record one once:  git -C `"$primary`" config $($cfg.prefix).homeBranch <branch>")
}

& git -C $primary show-ref --verify --quiet "refs/heads/$Branch"
if ($LASTEXITCODE -ne 0) {
    throw ("Home branch '$Branch' does not exist in $primary. Create it from the trunk, or pass " +
        "-Branch with a branch that does exist.")
}

Write-Host "primary : $primary"
Write-Host "HEAD    : $(if ($detached) { "DETACHED at $((& git -C $primary rev-parse --short HEAD).Trim())" } else { $head })"
Write-Host "home    : $Branch"

if ($head -eq $Branch) {
    Write-Host ''
    Write-Host "Nothing to do -- the primary is already on '$Branch'." -ForegroundColor Green
    return
}

$dirty = @(& git -C $primary status --porcelain)
if ($dirty.Count -gt 0 -and -not $Force) {
    Write-Host ''
    Write-Warning "The primary has $($dirty.Count) uncommitted change(s). Re-attaching would carry them onto '$Branch'."
    $dirty | Select-Object -First 8 | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host 'Move the work to a worktree of its own first (it is not discarded):'
    Write-Host '    pwsh -NoProfile -File scripts/worktree/rescue.ps1 -Name <short-task-name>'
    Write-Host 'Or, if you know the changes are junk, re-run with -Force.'
    throw 'Refusing to re-attach a dirty primary checkout.'
}

if ($PSCmdlet.ShouldProcess($primary, "git checkout $Branch")) {
    & git -C $primary checkout $Branch
    if ($LASTEXITCODE -ne 0) { throw "git checkout $Branch failed in $primary (exit $LASTEXITCODE)." }

    Write-Host ''
    Write-Host "Primary re-attached to '$Branch'." -ForegroundColor Green
    & git -C $primary status -sb | Select-Object -First 1
    Write-Host ''
    Write-Host "If it is behind, update it:  git -C `"$primary`" pull --ff-only"
}
