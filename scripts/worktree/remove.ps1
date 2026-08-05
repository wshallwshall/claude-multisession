#Requires -Version 7.3
<#
.SYNOPSIS
    Remove a worktree created by new.ps1, and optionally its branch, without orphaning commits.

.DESCRIPTION
    The manual counterpart to the pruning tool. It removes the worktree directory for <Name> and, with
    -DeleteBranch, the branch it was on.

    IT REFUSES IF THE WORKTREE HAS UNCOMMITTED *TRACKED* CHANGES unless -Force. Untracked entries are
    expected -- a per-checkout environment directory, build output, a scratch database -- and do not
    block removal. Note the deliberate asymmetry with the automated pruning tool, which treats
    untracked files as a BLOCKER: a human running this command has just looked at the directory and can
    say those files are disposable, and an unattended reaper cannot. The stricter test belongs to the
    tool that runs without a human. Do not "fix" the difference by making them agree.

    Run it from any checkout EXCEPT the one being removed (git cannot remove the worktree you are
    standing in).

    WHY THE TIP IS REFERENCED BEFORE ANYTHING IS REMOVED. Removing a worktree can take its branch ref
    with it, and a commit that is in no ref is also in no reflog -- there is then no `git reflog` entry
    to recover it from and nothing in the interface admits the work existed. So the tip is resolved
    first, printed, and (when -DeleteBranch is used) written to a keep-ref before the branch goes. The
    keep-ref costs nothing and is the difference between "recoverable" and "gone at the next gc".

.EXAMPLE
    ./remove.ps1 -Name alerts
    ./remove.ps1 -Name alerts -DeleteBranch
    ./remove.ps1 -Name alerts -Force        # discard uncommitted tracked changes too
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9._-]+\z')]
    [string]$Name,

    # Remove even with uncommitted tracked changes.
    [switch]$Force,

    # Also delete the local branch.
    [switch]$DeleteBranch
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '../coord/_common.ps1')

$PrimaryRoot = Get-CcxPrimaryRoot
if (-not $PrimaryRoot) { throw "Not inside a git repository (could not locate the primary checkout)." }

$cfg = Get-CcxConfig -From $PrimaryRoot
$WorktreePath = Get-CcxWorktreePath -Name $Name -PrimaryRoot $PrimaryRoot

if (-not (Test-Path -LiteralPath $WorktreePath)) { throw "No such worktree: $WorktreePath" }

# Refuse to remove the worktree we are standing in. git would refuse too, but its message describes
# the git-level problem rather than the thing you did, and a wrong-cwd run must fail loudly rather
# than half-succeed.
$here = ConvertTo-CcxComparablePath $PWD.Path
$there = ConvertTo-CcxComparablePath $WorktreePath
if (Test-CcxPathUnder -Path $here -Root $there) {
    throw ("You are standing inside '$WorktreePath'. Run this from another checkout -- git cannot " +
        "remove the worktree that is the current directory.")
}

# Guard against losing committed-but-unpushed or modified tracked work. Untracked entries ('??') are
# expected and do not block removal.
$tracked = & git -C $WorktreePath status --porcelain | Where-Object { $_ -notmatch '^\?\?' }
if ($tracked -and -not $Force) {
    Write-Host ($tracked -join "`n")
    throw "Worktree has uncommitted tracked changes. Commit/push them, or re-run with -Force."
}

# REFERENCE THE TIP FIRST -- before any destructive step, while the branch still exists.
$branch = Invoke-CcxGit -Repo $WorktreePath -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
$tip = Invoke-CcxGit -Repo $WorktreePath -Arguments @('rev-parse', 'HEAD')
if ($tip) {
    Write-Host "worktree : $WorktreePath"
    Write-Host "branch   : $(if ($branch -and $branch -ne 'HEAD') { $branch } else { '(detached)' })"
    Write-Host "tip      : $tip"
}

if ($DeleteBranch -and $tip) {
    # A keep-ref, written BEFORE the branch is deleted. It keeps the commits reachable, so they survive
    # gc and can be recovered by name instead of by a SHA someone has to have scrolled back to find.
    #
    # List them:    git for-each-ref refs/<prefix>/removed/
    # Recover one:  git branch <name> refs/<prefix>/removed/<name>
    # Drop one:     git update-ref -d refs/<prefix>/removed/<name>
    $keepRef = "refs/$($cfg.prefix)/removed/$Name"
    & git -C $PrimaryRoot update-ref $keepRef $tip
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not write the keep-ref '$keepRef'. Note the tip yourself before continuing: $tip"
    } else {
        Write-Host "Kept the tip as '$keepRef' (recover with: git branch $Name $keepRef)." -ForegroundColor DarkGray
    }
}

# --force is needed regardless: the untracked per-checkout environment makes git consider the worktree
# non-empty. The tracked-changes refusal above is what protects the work; this flag only tells git that
# the untracked files it can see are expected.
& git -C $PrimaryRoot worktree remove --force $WorktreePath
if ($LASTEXITCODE -ne 0) { throw "git worktree remove failed (exit $LASTEXITCODE)" }

# Deliberately NOT followed by `git worktree prune`. That command deregisters every worktree whose
# directory git cannot currently see -- which includes one sitting on a disconnected network drive, an
# unmounted volume, or a path a live session is about to come back to. `git worktree remove` already
# deregisters the one we removed; a blanket prune is a second, much wider action wearing the costume of
# a cleanup step.

if ($DeleteBranch) {
    # -d, NOT -D. git refusing to delete an unmerged branch is a SIGNAL: it is telling you this branch
    # holds commits that are on no other ref. Forcing past it is how work disappears. If you have read
    # the refusal and still mean it, delete it by hand -- deliberately, not as a side effect of tidying
    # up a directory.
    & git -C $PrimaryRoot branch -d $Name
    if ($LASTEXITCODE -ne 0) {
        Write-Warning ("git refused to delete branch '$Name' -- it is not merged into its upstream, " +
            "so it holds commits no other ref has. The branch has been LEFT IN PLACE on purpose.")
        if ($tip) { Write-Warning "  its tip: $tip" }
        Write-Warning "  If you are certain it is disposable:  git -C `"$PrimaryRoot`" branch -D $Name"
    }
}

Write-Host "Removed worktree '$WorktreePath'." -ForegroundColor Green
