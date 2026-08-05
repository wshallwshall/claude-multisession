#Requires -Version 7.3
<#
.SYNOPSIS
    Create an isolated git worktree for a parallel session, on its own branch.

.DESCRIPTION
    Two parallel efforts (two agent sessions, or a human and an agent) cannot safely build in the same
    working tree -- one side's branch switch or edits clobber the other. This adds a git worktree in
    the configured layout, on its own branch, and then runs the repository's optional setup hook so the
    new checkout has whatever per-checkout environment it needs. The worktree shares the same git
    directory, history and remotes, so the normal branch -> PR -> merge flow is unchanged.

    Run it from anywhere in the clone: the layout is anchored on the PRIMARY checkout (the first entry
    of `git worktree list`), never on wherever this script happens to live. Running from a worktree
    would otherwise create a sibling-of-a-sibling that the pruning tool cannot see.

    THE BASE IS FETCHED FIRST and defaults to the trunk's REMOTE tip, not a local branch. Branching a
    new worktree off a local `main` that quietly lags its upstream is the single most common way
    parallel sessions end up building on old code, and it is invisible until the merge. Override with
    -Base; if you point -Base at a local branch that lags its own upstream you get a loud warning
    rather than a silent stale checkout.

    THERE IS NO LANGUAGE-SPECIFIC BOOTSTRAP HERE. Whatever a fresh checkout of your project needs --
    a virtualenv, a package install, a build -- belongs in the setup hook named by `setupHook` in
    ccx.config.json. See examples/worktree-setup.ps1.example.

.EXAMPLE
    ./new.ps1 -Name alerts
    ./new.ps1 -Name sqltuning -Base feature/sql-tuning
    ./new.ps1 -Name quicklook -NoSetup
    ./new.ps1 -Name my-task -Branch feature/my-task   # reuse a namespaced branch ('/' is not legal in -Name)

.NOTES
    -Name is the DIRECTORY component and cannot contain '/'; -Branch is the git ref and can. -Branch
    defaults to -Name, which is the ordinary case.
#>
[CmdletBinding()]
param(
    # The worktree DIRECTORY component. This pattern is LOAD-BEARING and is NOT a branch-name rule:
    # a '/' here would silently produce a nested directory instead of the intended sibling. The git
    # ref is -Branch.
    #
    # \A..\z, not ^..$: in .NET, '$' also matches before a FINAL NEWLINE, so the anchored-looking
    # '^...$' spelling accepts "abc<newline>" and lets it through into a directory name. The same
    # literal appears in remove.ps1, rescue.ps1, spawn.ps1 and coord/_common.ps1 -- keep all five
    # identical.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('\A[A-Za-z0-9._-]+\z')]
    [string]$Name,

    # The git BRANCH to reuse or create. Defaults to -Name, so every existing invocation is
    # unchanged. It exists because a real refname may contain '/' and -Name never can -- and the
    # worktree gate's branch-reuse remediation has to hand one back. Validated as a refname by GIT
    # in the body rather than by a second character class here: refname grammar is git's to define,
    # and a hand-rolled pattern is the mistake this parameter exists to undo.
    [string]$Branch,

    # Branch the new worktree off this ref. Default = the configured trunk, resolved to a
    # remote-tracking ref where one exists, so a stale local branch cannot seed it.
    [string]$Base,

    # Create the worktree only; do not run the repository's setup hook.
    [switch]$NoSetup
)

$ErrorActionPreference = 'Stop'

# -Branch defaults to -Name: these two roles were ONE parameter until the gate's branch-reuse
# remediation needed to hand back a real slash-bearing ref. Defaulting keeps spawn.ps1, rescue.ps1
# and every documented invocation byte-identical.
if (-not $Branch) { $Branch = $Name }

# Ask GIT whether this is a legal branch name instead of inventing a second grammar. check-ref-format
# rejects a space, '..', a '.lock' suffix, '*', '\', a leading '.', and a leading or trailing '/' --
# but it ACCEPTS a leading '-', which git's own argument parser would then read as a FLAG. Refuse that
# case separately. (Forbidding '*' is also why the `git branch --list $Branch` probe below stays an
# exact existence check rather than a glob.)
if ($Branch.StartsWith('-')) { throw "-Branch may not start with '-': '$Branch'" }
& git check-ref-format ('refs/heads/' + $Branch)
if ($LASTEXITCODE -ne 0) { throw "-Branch is not a valid git branch name: '$Branch'" }

. (Join-Path $PSScriptRoot '../coord/_common.ps1')

$PrimaryRoot = Get-CcxPrimaryRoot
if (-not $PrimaryRoot) { throw "Not inside a git repository (could not locate the primary checkout)." }

$cfg = Get-CcxConfig -From $PrimaryRoot
if (-not $Base) { $Base = Get-CcxTrunk -Repo $PrimaryRoot }

$WorktreePath = Get-CcxWorktreePath -Name $Name -PrimaryRoot $PrimaryRoot
if (Test-Path -LiteralPath $WorktreePath) { throw "Worktree path already exists: $WorktreePath" }

# Refresh remote-tracking refs FIRST so the base is current. A fetch failure (offline) is a loud
# warning, not fatal -- you can still branch off whatever refs you already have, you just need to know
# that is what happened.
#
# Fetch the remote the TRUNK lives on rather than a hardcoded name: a fork-based workflow whose trunk
# is `upstream/main` would otherwise fetch the wrong remote and report success.
$remote = 'origin'
if ($Base -match '^([^/]+)/.+$') {
    $candidate = $Matches[1]
    $remotes = @()
    $listed = Invoke-CcxGit -Repo $PrimaryRoot -Arguments @('remote')
    if ($listed) { $remotes = @($listed -split "`r?`n") }
    if ($remotes -contains $candidate) { $remote = $candidate }
}

Write-Host "Fetching '$remote' so the base is current..."
& git -C $PrimaryRoot fetch $remote --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git fetch $remote failed (offline?). Proceeding with possibly-stale refs."
}

# Reuse an existing branch if it is already there, else create it from -Base.
$branchExists = & git -C $PrimaryRoot branch --list $Branch
Write-Host "Creating worktree '$WorktreePath' on branch '$Branch'..."

# SERIALISED ACROSS SESSIONS. `git worktree add -b <name> <base>` writes the shared git config (the new
# branch's upstream), and concurrent adds race the config lock. Reproduced on Windows against one
# shared git directory: parallel adds fail with "could not lock config file" / "unable to write
# upstream branch configuration", leaving ORPHANED branches behind and callers that never run. Once
# several worktrees share a git directory this stops being theoretical.
#
# 90s is generous for an operation that takes seconds. If we wait that long something is genuinely
# wrong, and the throw is the right outcome -- the lock never steals, it names its holder and gives up.
$lockScript = Join-Path $PSScriptRoot '../coord/lock.ps1'
if (-not (Test-Path -LiteralPath $lockScript)) {
    # No backticks in this message: a backtick is PowerShell's escape character, so the same sentence
    # in double quotes silently loses the character after each one.
    throw ("Required file missing: $lockScript. The mutex around 'git worktree add' is a safety " +
        "property, not a convenience -- this script refuses to run without it rather than racing " +
        "a concurrent session silently.")
}
. $lockScript
if (-not (Get-Command -Name 'Enter-CcxLock' -ErrorAction SilentlyContinue)) {
    throw "coord/lock.ps1 did not define Enter-CcxLock. Refusing to create a worktree unserialised."
}

$addLock = Enter-CcxLock -Name 'worktree-add' -TimeoutSeconds 90 -Repo $PrimaryRoot
try {
    if ($branchExists) {
        & git -C $PrimaryRoot worktree add $WorktreePath $Branch
    } else {
        # Guard the stale-base trap when -Base names a LOCAL branch that lags its upstream (say, an
        # explicit `-Base main` while the remote has moved on). A remote-tracking base has no
        # @{upstream} of its own, so this check simply no-ops for the default.
        $baseUpstream = & git -C $PrimaryRoot rev-parse --abbrev-ref --symbolic-full-name ("$Base" + '@{upstream}') 2>$null
        if ($LASTEXITCODE -eq 0 -and $baseUpstream) {
            $behind = & git -C $PrimaryRoot rev-list --count "$Base..$baseUpstream" 2>$null
            if ($LASTEXITCODE -eq 0 -and $behind -and [int]$behind -gt 0) {
                Write-Warning ("Base '$Base' is $behind commit(s) behind its upstream '$baseUpstream' -- " +
                    "the new worktree will start from stale code. Update '$Base' first, or use " +
                    "-Base $baseUpstream.")
            }
        }
        & git -C $PrimaryRoot worktree add $WorktreePath -b $Branch $Base
    }
} finally {
    Exit-CcxLock $addLock
}
if ($LASTEXITCODE -ne 0) { throw "git worktree add failed (exit $LASTEXITCODE)" }

# Record this worktree's HOME branch in its PRIVATE git dir (<git-common-dir>/worktrees/<id>/), where a
# SessionStart drift-detector can read it and notice that the worktree was later switched onto some
# other branch -- the worktree hijack. Not in the working tree (a checkout would move it) and not in
# shared config (every worktree would see every other worktree's value).
#
# THIS RECORD IS WRONG BY DESIGN, and that is why the detector reading it may only WARN. It answers
# "what was this worktree created for", not "what should it be on now": it is written once and never
# updated, so a deliberate re-branching makes it stale immediately. A detector that treated it as
# authoritative would "repair" an intentional change. Treat a mismatch as a question, never a verdict.
#
# Best-effort. A failure here must never block worktree creation -- the worktree is the deliverable.
try {
    $gitDir = "$(& git -C $WorktreePath rev-parse --absolute-git-dir 2>$null)".Trim()
    if ($gitDir) {
        $marker = Join-Path $gitDir "$($cfg.prefix)-home-branch"
        Set-Content -LiteralPath $marker -Value $Branch -Encoding utf8NoBOM
    }
} catch { }

function Get-CcxSetupHookPath {
    <#
    .SYNOPSIS
        Resolve `setupHook` to a file that exists, preferring the NEW worktree's own copy.
    .DESCRIPTION
        The worktree's copy wins because the hook is versioned with the branch: a branch that changes
        what a fresh checkout needs should set that checkout up its own way. The primary's copy is the
        fallback for the case the hook is NOT tracked (a git-ignored local hook), because
        `git worktree add` cannot deliver a file git does not know about -- which is exactly the class
        of failure where a fresh worktree comes up subtly unusable and nothing says why.
    #>
    param([string]$Relative, [string]$WorktreePath, [string]$PrimaryRoot)
    if (-not $Relative) { return $null }
    if ([System.IO.Path]::IsPathRooted($Relative)) {
        if (Test-Path -LiteralPath $Relative -PathType Leaf) { return $Relative }
        return $null
    }
    foreach ($root in @($WorktreePath, $PrimaryRoot)) {
        $candidate = Join-Path $root $Relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Show-NextSteps {
    param([bool]$SetupRan)
    Write-Host ''
    Write-Host "Worktree ready: $WorktreePath (branch '$Branch')" -ForegroundColor Green
    Write-Host 'Next steps:'
    Write-Host "  cd `"$WorktreePath`""
    if (-not $SetupRan -and $cfg.setupHook) {
        Write-Host "  # setup hook did NOT run -- this checkout has no per-checkout environment yet."
    }
    Write-Host "  # ... build/commit/push on branch '$Branch'; open a PR as usual."
    Write-Host "  # When done, from any checkout:  scripts/worktree/remove.ps1 -Name $Name"
}

if ($NoSetup) {
    Write-Host 'Skipped the setup hook (-NoSetup).'
    Show-NextSteps -SetupRan $false
    return
}

# --- run the repository's setup hook -------------------------------------------------------------
# This replaces what used to be a hardcoded language-specific bootstrap. Everything about "what a
# fresh checkout of THIS project needs" lives in the hook, so this script stays language-agnostic.
#
# CONTRACT, so a hook author does not have to read this file:
#   * cwd is the NEW worktree.
#   * CCX_WORKTREE_PATH / CCX_WORKTREE_NAME / CCX_PRIMARY_ROOT / CCX_BASE_REF describe the creation.
#   * A non-zero exit is a failure and is reported as one. No arguments are passed, so a hook may
#     declare any parameters it likes without this script needing to know them.
#   * A .ps1 hook runs in a CHILD pwsh, not dot-sourced: its exit code is then a real contract, and it
#     cannot leave state behind in this session.
$hookRel = $cfg.setupHook
$setupRan = $false
if (-not $hookRel) {
    Write-Host 'No setupHook configured; worktree created with no per-checkout setup.' -ForegroundColor DarkGray
} else {
    $hook = Get-CcxSetupHookPath -Relative $hookRel -WorktreePath $WorktreePath -PrimaryRoot $PrimaryRoot
    if (-not $hook) {
        # Say this out loud. A missing setup hook produces a worktree that looks finished and behaves
        # subtly differently from every other checkout, and the symptom appears much later.
        Write-Warning ("setupHook '$hookRel' was not found in the new worktree or in the primary " +
            "checkout, so this worktree has NOT been set up. If the hook is git-ignored, copy it in " +
            "by hand; if it is tracked, check the path in ccx.config.json.")
    } else {
        Write-Host "Running setup hook: $hook"
        $env:CCX_WORKTREE_PATH = $WorktreePath
        $env:CCX_WORKTREE_NAME = $Name
        $env:CCX_PRIMARY_ROOT = $PrimaryRoot
        $env:CCX_BASE_REF = $Base
        Push-Location $WorktreePath
        try {
            if ([System.IO.Path]::GetExtension($hook).ToLowerInvariant() -eq '.ps1') {
                & pwsh -NoProfile -File $hook
            } else {
                & $hook
            }
            if ($LASTEXITCODE -ne 0) {
                # The worktree EXISTS and is usable; only the setup failed. Saying so is the whole
                # point -- a bare "setup failed" reads as "nothing happened" and the next session
                # re-runs creation into a path that is now occupied.
                throw ("Setup hook failed (exit $LASTEXITCODE). The worktree WAS created at " +
                    "$WorktreePath on branch '$Branch' -- it is not rolled back. Fix the hook and re-run " +
                    "it there, or remove the worktree with scripts/worktree/remove.ps1 -Name $Name.")
            }
            $setupRan = $true
        } finally {
            Pop-Location
            Remove-Item Env:CCX_WORKTREE_PATH, Env:CCX_WORKTREE_NAME, Env:CCX_PRIMARY_ROOT, Env:CCX_BASE_REF `
                -ErrorAction SilentlyContinue
        }
    }
}

Show-NextSteps -SetupRan $setupRan
