#Requires -Version 7
<#
.SYNOPSIS
    SessionStart backstop: heal the shared PRIMARY checkout when the harness's per-session
    auto-worktree half-fails on Windows and flips the primary's HEAD onto the session's branch,
    leaving an empty "ghost" stub worktree. See anthropics/claude-code#76590.

.DESCRIPTION
    Installed at USER scope as a SessionStart hook into EVERY Claude config dir a session can use on
    this machine -- the default ~/.claude and each ~/.claude-account-N created by a launcher that sets
    CLAUDE_CONFIG_DIR. It therefore fires at the start of every session, INCLUDING a ghost stub
    session whose cwd is an unregistered .claude/worktrees/<name> directory that resolves up to the
    primary -- a case a PROJECT-scoped hook can never see, because the stub has no project .claude/.

    For each governed primary (from the shared allowlist), if its HEAD has drifted off the home branch
    AND its tree is clean, it switches the primary back. A DIRTY tree is never touched, so uncommitted
    work cannot be lost -- and that refusal is REPORTED rather than taken in silence: a shared checkout
    left on the wrong branch with somebody's uncommitted work in it needs a human, and a silent decline
    is byte-identical to a primary that was fine, which leaves the one safety property this hook has
    unprovable from the outside. If THIS session is sitting in a stub worktree, it injects a heads-up
    telling the model to create a real worktree before editing.

    FAILS OPEN on every error path (exit 0, no output). A backstop that wedges session startup gets
    ripped out, and then it protects nothing. The critical action -- repairing the primary -- is a side
    effect that does not depend on the additionalContext output shape being recognised.

    SELF-CONTAINED ON PURPOSE. This file is installed as a COPY outside every working tree, so it can
    dot-source nothing and import nothing from the repository. Everything it needs is inline, even
    where that duplicates a helper that exists in scripts/coord/_common.ps1.

    Kill switch: delete the shared allowlist -> the hook no-ops everywhere.
#>
param(
    # Shared allowlist of primary checkouts to guard (one absolute path per line, '#' comments).
    # Absent or empty => the backstop is OFF.
    #
    # ONE allowlist, shared with the PreToolUse worktree gate, at a fixed name written by both
    # installers. There were once TWO -- the gate read one path and this backstop read another, one
    # installer rewrote its own unconditionally while the other seeded a second copy only if absent,
    # and nothing kept them in sync. Adding a governed repo through the gate installer never reached
    # this backstop, and uninstalling the gate left this hook armed and still willing to run
    # `git checkout` on the primary long after the gate was gone. They agreed only by luck.
    #
    # Because this script runs as an INSTALLED COPY, the path below is baked into whatever copy is on
    # disk. If it ever changes, both installers and every installed copy must change in one commit --
    # a stale copy reading a path nobody writes any more is a backstop that is silently off.
    [string]$ReposFile
)

if (-not $ReposFile) {
    # Null-safely: $env:USERPROFILE is Windows-only and is NULL elsewhere, where Join-Path then throws
    # a parameter-binding error rather than returning a path. Honour the env var when set (tests and
    # login swaps override it) and fall back to the .NET accessor, which resolves $HOME on Unix.
    $homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
    $ReposFile = Join-Path $homeDir '.claude/hooks/ccx-gate.repos.txt'
}

$ErrorActionPreference = 'SilentlyContinue'

function Write-ContextJson([string]$Message) {
    # SessionStart context injection. If the shape is not recognised it is simply ignored -- the
    # primary repair above has already happened regardless, so this is best-effort guidance only.
    [Console]::Out.Write((@{
                hookSpecificOutput = @{
                    hookEventName     = 'SessionStart'
                    additionalContext = $Message
                }
            } | ConvertTo-Json -Compress -Depth 6))
}

function Get-NormPath([string]$p) { if (-not $p) { return '' } ; ($p -replace '\\', '/').TrimEnd('/').ToLowerInvariant() }

function Get-PrefixAt([string]$RepoRoot) {
    # The git config key and the sidecar marker filename are both derived from ccx.config.json's
    # `prefix`, and the scripts that WRITE them derive it the same way. This installed copy cannot
    # dot-source the repo's helpers, so it reads the one key it needs straight out of the governed
    # repository's config -- reading it, rather than hardcoding 'ccx', is what keeps a renamed prefix
    # from silently splitting the writer and the reader into two different names.
    if (-not $RepoRoot) { return 'ccx' }
    $p = Join-Path $RepoRoot 'ccx.config.json'
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'ccx' }
    try {
        $v = (Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).prefix
        if ($v -and "$v" -match '^[A-Za-z][A-Za-z0-9-]{0,31}$') { return "$v" }
    } catch { }
    return 'ccx'
}

# --- read the SessionStart payload (only for cwd); fail open if unreadable -------------------------
$cwd = ''
try { $j = [Console]::In.ReadToEnd() | ConvertFrom-Json; $cwd = [string]$j.cwd } catch { }

# --- governed primaries (shared allowlist). No file / no entries => nothing to do -----------------
$roots = @(
    Get-Content -LiteralPath $ReposFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } |
        ForEach-Object { $_.Trim() }
)
if ($roots.Count -eq 0) { exit 0 }

$notes = @()
foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    # Home branch, in order: `git config --get <prefix>.homeBranch` -> whichever of main/master exists.
    # NB: use $homeBranch, NOT $home -- $HOME is a read-only PowerShell automatic variable (the user
    # profile dir) and PS variable names are case-insensitive, so writing $home silently fails.
    $homeBranch = (& git -C $root config --get "$(Get-PrefixAt $root).homeBranch")
    if (-not $homeBranch) {
        foreach ($candidate in @('main', 'master')) {
            & git -C $root show-ref --verify --quiet "refs/heads/$candidate"
            if ($LASTEXITCODE -eq 0) { $homeBranch = $candidate; break }
        }
    }
    $homeBranch = "$homeBranch".Trim()
    # No home branch means we cannot say what "drifted" is. Do nothing rather than guess: switching a
    # shared checkout onto a branch chosen by a fallback is worse than leaving it where it is.
    if (-not $homeBranch) { continue }

    $head = "$(& git -C $root rev-parse --abbrev-ref HEAD 2>$null)".Trim()
    $dirty = @(& git -C $root status --porcelain 2>$null)

    # A real (non-detached) drift off the home branch. Detached HEAD is deliberately NOT drift here:
    # nothing can say which branch a detached HEAD was meant to be on, and this hook does not guess.
    $drifted = ($head -and $head -ne $homeBranch -and $head -ne 'HEAD')

    # 1) Primary drifted off home AND clean -> un-flip it. Git is scoped explicitly with -C: this hook
    #    process does not reliably have the ambient cwd that the interactive restore script relies on.
    #    We have already verified a clean tree and a real (non-detached) drift, so this is exactly the
    #    safe branch switch that script would perform.
    if ($drifted -and $dirty.Count -eq 0) {
        & git -C $root checkout $homeBranch 2>$null
        if ($LASTEXITCODE -eq 0) {
            $notes += "Auto-repaired the shared primary ($root): HEAD had drifted to '$head'; restored to '$homeBranch'. This was a half-failed per-session auto-worktree (anthropics/claude-code#76590)."
        }
    } elseif ($drifted) {
        # 1b) DRIFTED BUT DIRTY -> refuse, AND SAY SO.
        #
        # The dirty-tree test above is the only safety property this hook has: it is the most
        # privileged control in the set (an unattended `git checkout` on a shared checkout, at
        # session start, from a script the calling session can freely edit), and a checkout over
        # uncommitted work is exactly the outcome that must never happen.
        #
        # Refusing SILENTLY, which is what this did before, is byte-identical on stdout to "the
        # primary was fine" -- so the one state a human most needs to know about (a shared checkout
        # sitting on the wrong branch with somebody's uncommitted work in it, which this backstop
        # will keep declining to fix at every session start until a person acts) produced no output
        # at all. It also left the refusal unprovable: an audit cannot distinguish a hook that
        # checked the tree and declined from one whose dirty test is not there any more.
        #
        # Reporting only. Nothing is mutated on this path, by design.
        $notes += "DECLINED to repair the shared primary ($root): HEAD has drifted to '$head' (home branch '$homeBranch'), but the tree has $($dirty.Count) UNCOMMITTED change(s), so nothing was touched -- this backstop never runs a checkout over uncommitted work. Until somebody commits or stashes that work, the primary stays on '$head' and this notice repeats every session. Inspect it from a PLAIN terminal:`n    git -C `"$root`" status`nThen commit or stash, or rescue the work with: pwsh -NoProfile -File $root/scripts/worktree/rescue.ps1"
    }

    # 2) Is THIS session sitting in a ghost stub under this primary's .claude/worktrees/?
    $rc = Get-NormPath $root
    $c = Get-NormPath $cwd
    if ($c -and $c.StartsWith("$rc/.claude/worktrees/")) {
        # A real linked worktree has a .git FILE pointing at its private git dir; a half-failed stub
        # has nothing there at all. That single test separates the two.
        if (-not (Test-Path -LiteralPath (Join-Path $cwd '.git'))) {
            $notes += "This session's working dir is a GHOST stub ($cwd) left by a half-failed auto-worktree (anthropics/claude-code#76590): it has no .git pointer, is not in ``git worktree list``, and git here resolves to the shared primary, not an isolated worktree. Before ANY edits, create a real worktree and work there by ABSOLUTE path:`n    pwsh -NoProfile -File $root/scripts/worktree/new.ps1 -Name <short-task>`nDo not build in this stub."
        }
    }
}

# 3) Has THIS session's own LINKED worktree been SWITCHED off its home branch -- the worktree hijack?
#    A session with no worktree of its own runs `git checkout <a-branch>` inside somebody else's
#    worktree, yanking its files onto another branch mid-task (docs/WORKTREES.md). The PreToolUse
#    worktree gate blocks that pre-emptively, but ONLY in the config dirs where it is wired. This
#    backstop is wired into every one of them, so it is the cross-login safety net.
#    WARN ONLY: never auto-switch a linked worktree under the session that is standing in it.
if ($cwd -and (Test-Path -LiteralPath $cwd)) {
    # A linked worktree's private git dir is <repo>/.git/worktrees/<id>/; the main worktree's is
    # <repo>/.git. Only a linked worktree can be hijacked away from an assigned branch.
    $gitDir = "$(& git -C $cwd rev-parse --absolute-git-dir 2>$null)".Trim()
    if ($gitDir -match '[/\\]worktrees[/\\]') {
        # Only if this worktree's repo is a governed primary (its MAIN worktree is in the allowlist).
        # Keep the RAW main-worktree path as well as the folded one: the folded form is for comparison
        # only and must never be handed to the filesystem (on a case-sensitive filesystem it names a
        # directory that does not exist).
        $mainWtRaw = ''
        $ml = @(& git -C $cwd worktree list --porcelain 2>$null) |
            Where-Object { $_ -match '^worktree ' } | Select-Object -First 1
        if ($ml) { $mainWtRaw = ($ml -replace '^worktree\s+', '').Trim() }
        $mainWt = Get-NormPath $mainWtRaw
        $governed = $false
        foreach ($r in $roots) { if ((Get-NormPath $r) -eq $mainWt) { $governed = $true; break } }
        if ($governed) {
            # The sidecar home-branch record, named from the governed repo's own prefix so this
            # reader and the script that WROTE it cannot end up on two different filenames. It lives
            # in the worktree's private git dir, so it survives checkouts and dies with the worktree.
            $homeFile = Join-Path $gitDir "$(Get-PrefixAt $mainWtRaw)-home-branch"
            $wtHead = "$(& git -C $cwd rev-parse --abbrev-ref HEAD 2>$null)".Trim()
            if (Test-Path -LiteralPath $homeFile) {
                $wtHome = "$(Get-Content -LiteralPath $homeFile -Raw -ErrorAction SilentlyContinue)".Trim()
                if ($wtHome -and $wtHead -and $wtHead -ne 'HEAD' -and $wtHead -ne $wtHome) {
                    $notes += "This worktree ($cwd) is on branch '$wtHead' but its recorded HOME branch is '$wtHome'. Another session may have SWITCHED it onto a different branch -- a worktree hijack (docs/WORKTREES.md), which silently swaps every file under you. If that was not intentional, restore it (commit or stash anything you want to keep FIRST), from a PLAIN terminal:`n    git -C `"$cwd`" switch $wtHome"
                }
            } elseif ($wtHead -and $wtHead -ne 'HEAD') {
                # First sighting with no record yet -> remember the current branch as home (best
                # effort). The warn-only design means a wrong bootstrap only misses or mis-fires a
                # warning; it can never mutate anything.
                Set-Content -LiteralPath $homeFile -Value $wtHead -Encoding utf8 -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($notes.Count -gt 0) { Write-ContextJson ($notes -join "`n`n") }
exit 0
