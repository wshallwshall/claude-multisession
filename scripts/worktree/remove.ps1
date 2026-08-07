#Requires -Version 7.3
<#
.SYNOPSIS
    Remove a worktree created by new.ps1, and optionally its branch, without orphaning commits.

.DESCRIPTION
    The manual counterpart to the pruning tool. It removes the worktree directory for <Name> and, with
    -DeleteBranch, THE BRANCH THAT WORKTREE WAS ON -- which is often not <Name>. <Name> is a directory
    component and cannot contain '/'; `new.ps1 -Name my-task -Branch feature/my-task` is a documented
    invocation, so the two names diverge as a matter of routine rather than as an edge case.

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
    # The worktree DIRECTORY component, exactly as passed to new.ps1 -- NOT a branch name. The pattern
    # is the same literal new.ps1 uses (see its note on why '\A..\z' rather than '^..$', and on keeping
    # all five copies identical). Which branch -DeleteBranch removes is read from the worktree's own
    # HEAD, because these two are routinely different: see the note above the delete.
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

# THE BRANCH TO DELETE IS THE ONE THIS WORKTREE WAS ACTUALLY ON -- never -Name.
#
# -Name is the DIRECTORY component and cannot contain '/' (see its ValidatePattern, and new.ps1's note
# on why that pattern is load-bearing). A branch name can, and `new.ps1 -Name my-task -Branch
# feature/my-task` is a documented invocation -- it is how the worktree gate's branch-reuse remediation
# hands a namespaced ref back. So a worktree whose $Name is not a branch name AT ALL is ordinary, not
# exotic, and `git branch -d $Name` there fails with "branch not found" while the real branch is never
# considered and quietly survives a run the human read as a full cleanup.
#
# Resolved HERE, before anything is removed, because `git worktree remove` is what takes away the
# ability to ask. $null means detached HEAD (or git could not answer) -- handled explicitly below
# rather than by falling back to $Name, which would be guessing at a destructive step.
$branchToDelete = if ($branch -and $branch -ne 'HEAD') { $branch } else { $null }

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
        # Recover under the branch's REAL name where we know it. The keep-ref itself stays named after
        # $Name (it is the stable, always-ref-safe label, and the listing commands above are written
        # against it), but a recovery hint that renames a namespaced branch back to its directory
        # component hands you a differently-named branch and does not say so.
        $recoverAs = if ($branchToDelete) { $branchToDelete } else { $Name }
        Write-Host "Kept the tip as '$keepRef' (recover with: git branch $recoverAs $keepRef)." -ForegroundColor DarkGray
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
    if (-not $branchToDelete) {
        # Detached HEAD, or git could not answer. There is no branch here to delete, and the previous
        # version guessed one: it ran `git branch -d $Name` regardless, which either failed (and was
        # then reported as unmerged commits that do not exist) or deleted some OTHER branch that merely
        # shares this directory's name. Neither is something a cleanup step gets to do silently.
        Write-Warning ("-DeleteBranch: this worktree had no branch checked out (detached HEAD), so " +
            "there is no branch to delete. Nothing has been lost -- its tip is printed above.")
    }
    else {
        # -d, NOT -D. git refusing to delete an unmerged branch is a SIGNAL: it is telling you this
        # branch holds commits that are on no other ref. Forcing past it is how work disappears. If you
        # have read the refusal and still mean it, delete it by hand -- deliberately, not as a side
        # effect of tidying up a directory.
        #
        # CAPTURE GIT'S OWN REASON RATHER THAN ASSERTING ONE. This warning used to name a single cause
        # for ANY non-zero exit -- "it is not merged into its upstream, so it holds commits no other ref
        # has" -- which the script had not established and, in the namespaced-branch case above, had not
        # even tested: `branch -d` also refuses when the branch does not exist under that name, and when
        # it is checked out in another worktree. Both print a precise explanation on stderr, which was
        # discarded. Asserting the wrong cause is worse than reporting none: it sends the reader off to
        # look for commits that were never at risk, and it reads as a considered verdict either way.
        #
        # 2>&1 so git's stderr lands in $refusal instead of the console. On SUCCESS the same capture
        # holds git's "Deleted branch ..." line, which is re-emitted below -- capturing output must not
        # cost the confirmation the caller used to get.
        $refusal = & git -C $PrimaryRoot branch -d -- $branchToDelete 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("git refused to delete branch '$branchToDelete' (exit $LASTEXITCODE). The " +
                "branch has been LEFT IN PLACE. git's own reason:")
            foreach ($line in @($refusal)) { Write-Warning "  $line" }
            Write-Warning ("  If that reason is 'not fully merged', the branch holds commits no other " +
                "ref has, and the refusal is the signal -- not an obstacle to get past.")
            if ($tip) { Write-Warning "  its tip: $tip" }
            Write-Warning "  If you are certain it is disposable:  git -C `"$PrimaryRoot`" branch -D $branchToDelete"
        }
        else {
            foreach ($line in @($refusal)) { Write-Host $line }
        }
    }
}

Write-Host "Removed worktree '$WorktreePath'." -ForegroundColor Green
