#Requires -Version 7.3
<#
.SYNOPSIS
    Shared substrate for every ccx script: config discovery, the state root, trunk resolution,
    path folding, and the worktree-path formula.

.DESCRIPTION
    Dot-source this. It defines functions in the caller's scope and writes nothing to stdout, so a
    hook that must emit pure JSON can load it safely.

        . "$PSScriptRoot/../coord/_common.ps1"

    WHY THIS FILE EXISTS. Each of the things below was previously copy-pasted into three, four or
    five scripts, and every copy had drifted. The drift was not cosmetic:

      * git-common-dir was resolved five different ways. Two callers omitted
        `--path-format=absolute`, so git handed back a RELATIVE `.git` and the caller joined it onto
        whatever directory the process happened to start in. Two others never checked $LASTEXITCODE,
        so a git failure produced an empty path that silently became a state root at the filesystem
        root.
      * The path-folding helper existed in five places. One of them canonicalised (GetFullPath)
        before comparing and four did not -- and without canonicalisation `<primary>-work/../<primary>`
        does not string-match the primary and walks straight through the gate that exists to catch it.
      * The worktree-path formula existed in four scripts and was pattern-MATCHED in a fifth, which
        is how a rule and its enforcement can disagree without either being wrong on its own.

    Where the old copies disagreed, this file picks the safer behaviour and says so at the call site.

.NOTES
    Everything here is stdlib PowerShell 7 plus `git`. No modules, no network, no state outside the
    repository's own git directory.
#>

# Deliberately NO `Set-StrictMode` here. This file is dot-sourced into hooks that must FAIL OPEN, and
# strict mode turns a missing property on a payload the vendor changed into a terminating error --
# which for a hook means exiting non-zero with nothing on stdout, i.e. the guard is off and says
# nothing. Each script sets its own error preference; this one imposes none.

# ------------------------------------------------------------------------------------------------
# Config discovery
# ------------------------------------------------------------------------------------------------

# ccx.config.json at the repo root is BOTH the knob file and the opt-in marker. User-scope hooks run
# in every repository on the machine, so "is this repo governed by ccx?" must be answerable without
# running anything: the file is either there or it is not.
#
# It is deliberately NOT "does scripts/coord/presence.ps1 exist". That discriminator asks whether a
# particular implementation file happens to be on disk, which is true in a half-installed tree, false
# in a governed repo that vendors the scripts elsewhere, and silently true in a fork that only copied
# the scripts directory.
$script:CcxConfigCache = @{}

function Find-CcxConfigPath {
    <#
    .SYNOPSIS
        Locate ccx.config.json by walking up from $From. Returns $null if there is none.
    .DESCRIPTION
        Use this as the "is this repo opted in?" discriminator. It never throws, so a hook can call it
        on every prompt in an unrelated repository and stay inert.

        $env:CCX_CONFIG, if set, names the file directly and short-circuits the walk. That
        environment variable is the ONLY override -- no script here takes a `--config` flag, and an
        earlier version of this comment advertised one on the doctor that has never existed. It is
        how a test points at a fixture, and how the doctor's attack fixtures clear the override so a
        probe walks up from the fixture the way it does in real life.
    #>
    [CmdletBinding()]
    param(
        [string]$From = $PWD.Path
    )

    if ($env:CCX_CONFIG) {
        if (Test-Path -LiteralPath $env:CCX_CONFIG -PathType Leaf) {
            return (Resolve-Path -LiteralPath $env:CCX_CONFIG).Path
        }
        return $null
    }

    if (-not $From) { return $null }
    try { $dir = (Resolve-Path -LiteralPath $From -ErrorAction Stop).Path } catch { return $null }
    if (Test-Path -LiteralPath $dir -PathType Leaf) { $dir = Split-Path -Parent $dir }

    # Bounded walk. An unbounded `while ($dir)` loop terminates on Windows because Split-Path of a
    # drive root returns '', but on a UNC path or a mount point it can sit on the same string forever.
    # Compare the parent to the child and stop when it stops changing.
    while ($dir) {
        $candidate = Join-Path $dir 'ccx.config.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-CcxConfig {
    <#
    .SYNOPSIS
        Load and cache ccx.config.json. Throws with an actionable message if there is none.
    .DESCRIPTION
        Returns a PSCustomObject with every key materialised, so a caller never has to test whether a
        key was present:

            prefix          string, default 'ccx'
            trunk           string, default 'auto'
            worktreeLayout  'sibling' | 'nested', default 'sibling'
            setupHook       string or $null
            protectedRefs   string[] (possibly empty)
            sequences       hashtable name -> definition (EMPTY means the sequence machinery is off)
            ConfigPath      where it was loaded from
            RepoRoot        the directory the config lives in

        `sequences` absent and `sequences` empty mean the same thing on purpose: allocation and the
        sequence commit gate are disabled. A caller must not treat "no sequences" as an error.
    .PARAMETER Force
        Re-read from disk, ignoring the cache. Only tests and `ccx doctor` should need this.
    #>
    [CmdletBinding()]
    param(
        [string]$From = $PWD.Path,
        [switch]$Force
    )

    $path = Find-CcxConfigPath -From $From
    if (-not $path) {
        throw ("No ccx.config.json found at or above '$From'. " +
            "That file is the repository's opt-in marker as well as its configuration -- create one " +
            "at the repository root (copy the shipped ccx.config.json), or set CCX_CONFIG to point at it.")
    }

    $key = $path.ToLowerInvariant()
    if (-not $Force -and $script:CcxConfigCache.ContainsKey($key)) {
        return $script:CcxConfigCache[$key]
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding utf8 -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # Name the file. A parse error reported without the path sends the reader looking in the
        # wrong repository, because the walk above may have found a config several levels up.
        throw "ccx.config.json at '$path' could not be read as JSON: $($_.Exception.Message)"
    }

    $get = {
        param($obj, $name, $default)
        if ($null -ne $obj -and $obj.PSObject.Properties.Name -contains $name -and $null -ne $obj.$name) {
            return $obj.$name
        }
        return $default
    }

    $layout = [string](& $get $json 'worktreeLayout' 'sibling')
    if ($layout -notin @('sibling', 'nested')) {
        throw "ccx.config.json at '$path': worktreeLayout must be 'sibling' or 'nested', got '$layout'."
    }

    $sequences = @{}
    $seqNode = & $get $json 'sequences' $null
    if ($null -ne $seqNode) {
        foreach ($p in $seqNode.PSObject.Properties) { $sequences[$p.Name] = $p.Value }
    }

    $setup = & $get $json 'setupHook' $null
    if ($setup -is [string] -and [string]::IsNullOrWhiteSpace($setup)) { $setup = $null }

    $cfg = [pscustomobject]@{
        prefix         = [string](& $get $json 'prefix' 'ccx')
        trunk          = [string](& $get $json 'trunk' 'auto')
        worktreeLayout = $layout
        setupHook      = $setup
        protectedRefs  = @(& $get $json 'protectedRefs' @())
        sequences      = $sequences
        ConfigPath     = $path
        RepoRoot       = (Split-Path -Parent $path)
    }

    # The prefix becomes a directory name, a git config key and an env-var stem. Reject anything that
    # would need escaping in any of those, here, once -- rather than producing a state root nobody can
    # type and a git config key git will not accept.
    if ($cfg.prefix -notmatch '^[A-Za-z][A-Za-z0-9-]{0,31}$') {
        throw ("ccx.config.json at '$path': prefix '$($cfg.prefix)' is not usable. " +
            "It becomes a directory name, a git config key and an environment-variable stem, so it " +
            "must start with a letter and contain only letters, digits and hyphens.")
    }

    $script:CcxConfigCache[$key] = $cfg
    return $cfg
}

# ------------------------------------------------------------------------------------------------
# Client config roots
# ------------------------------------------------------------------------------------------------

function Resolve-CcxClientConfigRoot {
    <#
    .SYNOPSIS
        Which directories under the home directory are Claude Code config roots -- and which
        look-alikes were rejected, and why.
    .DESCRIPTION
        Returns one object:

            Roots    string[]  directories to read wiring from / write wiring into
            Skipped  object[]  Path + Reason, one per candidate that was NOT accepted

        WHY THIS IS NOT JUST A GLOB. Two scripts each ran
        `Get-ChildItem -Directory -Filter '.claude-account-*'` and treated every hit as a config
        root. On a real machine that matched `~/.claude-account-2.lock` -- a launcher lock artefact
        that happens to be a DIRECTORY. The doctor charged a required failure against it (nothing is
        wired in a lock file, and nothing ever will be), and the gate installer would have copied the
        gate and written settings INTO it. Neither outcome was visible as a mistake: one read as a
        broken machine, the other as a successful install.

        THE ACCEPT TEST USES A MARKER THE CLIENT CREATES, NEVER ONE WE CREATE. `settings.json` and
        `hooks/` are exactly what this repository's own installers write, so accepting a directory
        because it has them makes the check self-confirming: run the installer once against a wrong
        directory and it qualifies as a config root forever after. That is not hypothetical -- the
        `.lock` directory that prompted this contained a `settings.json` and nothing else, because an
        earlier install put it there. So the markers are `projects/`, `sessions/` and `.claude.json`,
        all of which the client writes and none of which this repository ever creates.

        `~/.claude` is accepted on existence alone. It is the documented default, named exactly
        rather than discovered by pattern, so there is no look-alike to confuse it with -- and a
        fresh install whose client directories have not been created yet must still be wirable.

        EVERY REJECTION IS RETURNED, NOT SWALLOWED. A silent skip is the failure mode this whole
        toolkit exists to prevent: a candidate that quietly vanished from the list reads exactly like
        one that was never there. Callers print them.
    .PARAMETER HomeDirectory
        Where to look. Callers resolve it null-safely and pass it in.
    .PARAMETER Explicit
        Directories named by the operator (-ConfigDir). These bypass the marker test entirely -- an
        operator naming a directory outranks a heuristic -- but a path that is not a directory is
        still reported as skipped rather than dropped.
    #>
    [CmdletBinding()]
    param(
        [string]$HomeDirectory,
        [string[]]$Explicit
    )

    $roots = @()
    $skipped = @()
    $skip = { param($Path, $Reason) [pscustomobject]@{ Path = $Path; Reason = $Reason } }

    if ($Explicit -and $Explicit.Count -gt 0) {
        foreach ($e in $Explicit) {
            if (Test-Path -LiteralPath $e -PathType Container) { $roots += (Resolve-Path -LiteralPath $e).Path }
            else { $skipped += (& $skip $e 'named with -ConfigDir, but it is not a directory') }
        }
        return [pscustomobject]@{ Roots = @($roots); Skipped = @($skipped) }
    }

    if (-not $HomeDirectory) {
        return [pscustomobject]@{
            Roots   = @()
            Skipped = @((& $skip '(home directory)' 'the home directory could not be resolved, so nothing was searched'))
        }
    }

    $default = Join-Path $HomeDirectory '.claude'
    if (Test-Path -LiteralPath $default -PathType Container) { $roots += $default }
    else { $skipped += (& $skip $default 'the default config root does not exist here') }

    # Markers the CLIENT writes. See the header for why settings.json and hooks/ are not on this list.
    $markers = @(
        @{ Name = 'projects'; Type = 'Container' }
        @{ Name = 'sessions'; Type = 'Container' }
        @{ Name = '.claude.json'; Type = 'Leaf' }
    )

    foreach ($d in @(Get-ChildItem -LiteralPath $HomeDirectory -Directory -Filter '.claude-account-*' -ErrorAction SilentlyContinue)) {
        if ($d.Name -like '*.lock') {
            $skipped += (& $skip $d.FullName 'name ends in .lock -- a launcher lock artefact, not a config root')
            continue
        }
        $hit = @($markers | Where-Object { Test-Path -LiteralPath (Join-Path $d.FullName $_.Name) -PathType $_.Type })
        if ($hit.Count -eq 0) {
            $skipped += (& $skip $d.FullName ('no client-created marker (' + (($markers | ForEach-Object { $_.Name }) -join ', ') + ')'))
            continue
        }
        $roots += $d.FullName
    }

    return [pscustomobject]@{ Roots = @($roots); Skipped = @($skipped) }
}

# ------------------------------------------------------------------------------------------------
# git plumbing
# ------------------------------------------------------------------------------------------------

function Invoke-CcxGit {
    <#
    .SYNOPSIS
        Run git and return trimmed stdout, or $null if git failed.
    .DESCRIPTION
        Every caller in this repo used to write its own two-line version of this, and half of them
        forgot to check $LASTEXITCODE. A swallowed git failure does not read as a failure -- it reads
        as an empty result, which downstream code cheerfully treats as "no worktrees", "no refs", or
        "the repository root is ''". Returning $null makes the failure a distinct value the caller has
        to handle.
    #>
    [CmdletBinding()]
    param(
        # Explicit array rather than ValueFromRemainingArguments: git arguments start with '-' and
        # '--', and letting PowerShell's binder see them first is how `--path-format=absolute` ends up
        # interpreted as a parameter name instead of an argument.
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$Repo
    )
    $argv = @()
    # -C relocates BOTH the git dir and the work tree, which is what we want; --git-dir/--work-tree
    # do not, and using them here would be the bug _gittarget.ps1 documents in the other direction.
    if ($Repo) { $argv += @('-C', $Repo) }
    $argv += $Arguments

    $out = & git @argv 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($null -eq $out) { return $null }
    return ([string]($out -join "`n")).Trim()
}

function Get-CcxGitCommonDir {
    <#
    .SYNOPSIS
        Absolute path of the SHARED git directory (the one every worktree of a clone points at).
    .DESCRIPTION
        RECONCILED. Five call sites resolved this and they disagreed twice:

          * `--path-format=absolute` was present in three and missing in two. Missing, git may answer
            a RELATIVE '.git', and the caller then joins it onto its own process cwd -- which for a
            hook is wherever the harness happened to launch pwsh. ALWAYS pass it.
          * $LASTEXITCODE was checked in three and not in the other two, where `.Trim()` on a null
            result threw inside a `try` that swallowed it. ALWAYS check.

        Returns $null outside a repository. Callers decide whether that is fatal (a coordination
        script) or inert (a user-scope hook, which must exit 0 and say nothing).
    #>
    [CmdletBinding()]
    param([string]$Repo)
    $common = Invoke-CcxGit -Repo $Repo -Arguments @(
        'rev-parse', '--path-format=absolute', '--git-common-dir')
    if (-not $common) { return $null }
    return $common
}

function Get-CcxStateRoot {
    <#
    .SYNOPSIS
        THE state root: <git-common-dir>/<prefix>-coord. Created on demand.
    .DESCRIPTION
        Three properties make this the right place, and all three are load-bearing:

          1. IDENTICAL ACROSS WORKTREES. Every linked worktree of a clone resolves the same
             git-common-dir, so a claim taken in one worktree is visible to a session in another. A
             state root under the WORKING tree would give each worktree its own private, useless copy.
          2. ISOLATED PER CLONE. Two clones of the same project on one machine do not share it, so
             their locks and claims cannot collide. A state root under ~ would merge them.
          3. UNCOMMITTABLE. It lives inside the git directory, so no `git add -A` anywhere can sweep
             coordination state into a commit, and no checkout can delete it.

        Its corollary is deliberate and occasionally surprising: STATE OUTLIVES THE WORKTREE. Remove a
        worktree and the claims it took are still there. That is why the pruning tool releases claims
        on EVIDENCE (the directory is gone AND deregistered) rather than on a timer.

        Subdirectories, all created by their owners rather than here:
            alloc/  claims/  locks/  announce/  gate-unresolved/   overlap-cache.json
    #>
    [CmdletBinding()]
    param(
        [string]$Repo,
        # Skip config discovery. Only for a hook that already loaded the config, or a test fixture.
        [string]$Prefix
    )

    $common = Get-CcxGitCommonDir -Repo $Repo
    if (-not $common) {
        throw "Get-CcxStateRoot: not inside a git repository (git rev-parse --git-common-dir failed)."
    }
    if (-not $Prefix) {
        $Prefix = (Get-CcxConfig -From $(if ($Repo) { $Repo } else { $PWD.Path })).prefix
    }

    $root = Join-Path $common "$Prefix-coord"
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Force -Path $root -ErrorAction Stop | Out-Null
    }
    return $root
}

function Get-CcxTrunk {
    <#
    .SYNOPSIS
        The ref new work branches off and merged work is measured against. Default 'auto'.
    .DESCRIPTION
        Resolution order, most explicit first:

          1. $env:CCX_TRUNK              -- per-session override; wins over everything.
          2. ccx.config.json "trunk"     -- unless it is the literal 'auto'.
          3. `git symbolic-ref refs/remotes/origin/HEAD` -- what the REMOTE says its default branch
             is. This is the only source that stays right when a project renames its default branch.
          4. First of origin/main, origin/master, main, master that actually resolves.

        Step 3 fails on a clone made before the remote head was recorded; `git remote set-head origin
        -a` fixes it, and the error message below says so rather than leaving the reader to guess.

        Returns a REMOTE-tracking ref where it can (origin/main), not a local branch. A local `main`
        can silently lag its upstream, and branching a new worktree off a stale local trunk is the
        single most common way parallel sessions end up building on old code.
    #>
    [CmdletBinding()]
    param([string]$Repo)

    if ($env:CCX_TRUNK) { return $env:CCX_TRUNK }

    $configured = $null
    try { $configured = (Get-CcxConfig -From $(if ($Repo) { $Repo } else { $PWD.Path })).trunk } catch { }
    if ($configured -and $configured -ne 'auto') { return $configured }

    $sym = Invoke-CcxGit -Repo $Repo -Arguments @('symbolic-ref', '--short', 'refs/remotes/origin/HEAD')
    if ($sym) { return $sym }

    foreach ($candidate in @('refs/remotes/origin/main', 'refs/remotes/origin/master',
            'refs/heads/main', 'refs/heads/master')) {
        # Invoke-CcxGit returns $null on a non-zero exit, so the truthiness test IS the exit check --
        # `rev-parse --verify --quiet` prints the object id on success and nothing on failure.
        if (Invoke-CcxGit -Repo $Repo -Arguments @('rev-parse', '--verify', '--quiet', $candidate)) {
            return ($candidate -replace '^refs/remotes/', '' -replace '^refs/heads/', '')
        }
    }

    # Single-quoted on purpose: a backtick is PowerShell's escape character, so the same sentence in
    # double quotes silently loses the character after each one.
    throw ('Get-CcxTrunk: could not determine the trunk. Record the remote''s default branch once ' +
        'with "git remote set-head origin -a", or set "trunk" in ccx.config.json (or CCX_TRUNK) ' +
        'to an explicit ref such as origin/main.')
}

# ------------------------------------------------------------------------------------------------
# Path normalisation and name folding
# ------------------------------------------------------------------------------------------------

# Is the filesystem we are comparing paths on case-insensitive?
#
# LINUX CASE-SENSITIVITY HAS ALREADY BITTEN THIS ONCE. The gate lowercased a path for comparison and
# then handed the SAME lowercased string to `git -C`. On Windows that is harmless; on Linux CI
# `git -C /tmp/xyz/primary-wt` missed the real `/tmp/xyz/Primary-wt`, git failed, and the rule fell
# through to its allow path -- i.e. the gate silently stopped enforcing on exactly the platform
# nobody was watching. Hence the rule below, which every caller must follow:
#
#     THE FOLDED FORM IS FOR COMPARISON ONLY. Never pass it to git, to the filesystem, or to a
#     message the operator reads. Keep the raw string for those.
#
# Folding is conditional on the platform rather than unconditional because on a case-sensitive
# filesystem `/tmp/Primary` and `/tmp/primary` really are two different directories, and folding them
# together would make the gate govern a directory it was never pointed at.
$script:CcxCaseInsensitiveFs = $IsWindows -or $IsMacOS

function ConvertTo-CcxComparablePath {
    <#
    .SYNOPSIS
        Canonicalise a path into the one form all path comparisons use. Returns '' if it cannot.
    .DESCRIPTION
        RECONCILED from five copies. Four of them did only `-replace '\\','/' | TrimEnd('/') |
        ToLowerInvariant()`. The fifth also called GetFullPath first, and that one is correct: without
        canonicalisation `<primary>-work/../<primary>/x.md` does not string-match the primary's prefix
        and walks straight through a gate whose entire job is to notice it.

        $Base matters just as much. A RELATIVE path must resolve against the path the COMMAND will run
        from -- for a hook, the session's cwd, which arrives in the hook payload -- not against this
        process's cwd. `../../..` is exactly how a session sitting in a nested worktree names the
        repository root, and resolving it against wherever pwsh was started meant `cd ../../.. && git
        reset --hard` did not look like it touched the primary at all.

        Returns '' rather than throwing. Every caller is on a fail-open path where an exception would
        end the process and let the tool call through with nothing said.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Base
    )
    if (-not $Path) { return '' }
    try {
        $full = if ($Base -and -not [System.IO.Path]::IsPathRooted($Path)) {
            [System.IO.Path]::GetFullPath($Path, $Base)
        } else {
            [System.IO.Path]::GetFullPath($Path)
        }
    } catch {
        # A non-rooted $Base, an invalid character, a path longer than the platform allows. Any of
        # those means "we cannot say what this points at", which callers read as "not governed".
        return ''
    }
    $norm = ($full -replace '\\', '/').TrimEnd('/')
    if ($script:CcxCaseInsensitiveFs) { return $norm.ToLowerInvariant() }
    return $norm
}

function Test-CcxPathUnder {
    <#
    .SYNOPSIS
        Is $Path the same as, or inside, $Root? Both must already be comparable form.
    .DESCRIPTION
        THE '/' IS THE POINT. A bare `.StartsWith($root)` is a prefix match on a string, not on a
        directory: a sibling worktree named `<primary>-<task>` has a path that literally starts with
        the primary's, so a raw prefix test claims every sibling is inside the primary. Requiring the
        separator makes it a directory-boundary test.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    return ($Path -eq $Root -or $Path.StartsWith("$Root/"))
}

function ConvertTo-CcxSafeName {
    <#
    .SYNOPSIS
        Fold free text into a filename-safe slug. Returns '' if nothing usable survives.
    .DESCRIPTION
        Claim keys and lock names are free text that becomes a FILENAME, and the filename is the
        mutual-exclusion primitive -- two spellings of one key must fold to one file or the lock does
        not lock. Folding is UNCONDITIONALLY lower-case here (unlike path comparison above), because
        this is a name we are minting rather than a path the filesystem already assigned: 'Auth-Fix'
        and 'auth-fix' must be the same claim on every platform.

        Callers must reject '' rather than substituting a default. A name that reduces to nothing is a
        caller bug, and silently coining one produces a lock everybody shares.
    #>
    [CmdletBinding()]
    param([string]$Name)
    if (-not $Name) { return '' }
    return (($Name.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]+', '-').Trim('-'))
}

# ------------------------------------------------------------------------------------------------
# Worktree paths
# ------------------------------------------------------------------------------------------------

function Get-CcxPrimaryRoot {
    <#
    .SYNOPSIS
        The MAIN working tree of this clone -- the first entry of `git worktree list --porcelain`.
    .DESCRIPTION
        RECONCILED, and this is the one place the old copies were not merely inconsistent but wrong.
        Four scripts derived the repository root as `$PSScriptRoot/../..` -- the checkout the SCRIPT
        happens to live in. Run from a linked worktree, that resolves to the WORKTREE's root, so a new
        worktree was created as a sibling of a worktree instead of a sibling of the primary, and the
        pruning tool -- which anchors on the primary -- could then not see it as a candidate at all.

        Anchoring on the primary makes the layout stable no matter which checkout you invoke from.
        Returns $null outside a repository.
    #>
    [CmdletBinding()]
    param([string]$Repo)
    $porcelain = Invoke-CcxGit -Repo $Repo -Arguments @('worktree', 'list', '--porcelain')
    if (-not $porcelain) { return $null }
    foreach ($line in ($porcelain -split "`r?`n")) {
        if ($line -match '^worktree\s+(.+)$') { return $Matches[1].Trim() }
    }
    return $null
}

function Get-CcxWorktreePath {
    <#
    .SYNOPSIS
        Where the worktree named $Name belongs, under the configured layout.
    .DESCRIPTION
        The formula, previously duplicated in four scripts and pattern-matched in a fifth:

          sibling  <parent-of-primary>/<primary-leaf>-<name>     (the default)
          nested   <primary>/.claude/worktrees/<name>

        SIBLING is the default because a worktree outside the primary's tree cannot be swept up by a
        command aimed at the primary, and because the two layouts coexist: the harness creates NESTED
        worktrees on its own, and those must never be touched by tooling that reaps siblings.

        `nested` here selects where WE create worktrees. It does not change the fact that any path
        containing a `.claude/worktrees/` segment is excluded from destructive operations
        unconditionally, whatever this setting says -- see Test-CcxHarnessWorktreePath.

        Returns the RAW path in the platform's own separator style: this value is handed to `git
        worktree add` and printed for a human, so it must not be the folded comparison form.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('\A[A-Za-z0-9._-]+\z')]
        [string]$Name,
        [string]$Repo,
        # Override the layout (tests, and `--layout` on the creating script).
        [ValidateSet('sibling', 'nested')]
        [string]$Layout,
        # Override the anchor. Pass the primary explicitly when you already resolved it.
        [string]$PrimaryRoot
    )

    if (-not $PrimaryRoot) { $PrimaryRoot = Get-CcxPrimaryRoot -Repo $Repo }
    if (-not $PrimaryRoot) { throw "Get-CcxWorktreePath: could not locate the primary checkout." }
    if (-not $Layout) {
        $Layout = (Get-CcxConfig -From $PrimaryRoot).worktreeLayout
    }

    if ($Layout -eq 'nested') {
        return (Join-Path $PrimaryRoot (Join-Path '.claude' (Join-Path 'worktrees' $Name)))
    }

    $parent = Split-Path -Parent $PrimaryRoot
    $leaf = Split-Path -Leaf $PrimaryRoot
    if (-not $parent -or -not $leaf) {
        throw ("Get-CcxWorktreePath: the primary checkout '$PrimaryRoot' has no parent directory, so " +
            "the sibling layout cannot be used here. Set worktreeLayout to 'nested'.")
    }
    return (Join-Path $parent "$leaf-$Name")
}

function Test-CcxHarnessWorktreePath {
    <#
    .SYNOPSIS
        Does this path sit under a `.claude/worktrees/` segment?
    .DESCRIPTION
        Such a worktree is created and owned by the harness, not by us. Two rules depend on this and
        they pull in opposite directions, which is why it is one named test rather than two inline
        regexes:

          * A gate protecting the primary must NOT govern it. It lives under the primary's path, so a
            plain prefix test says "inside the primary" -- but a git verb there swaps only its own
            tree. Governing it refused the most ordinary thing a session does.
          * A reaper must NEVER remove it. Its path also starts with `<primary>-` in some layouts, so
            the sibling prefix scan picks it up, and removing it destroys the checkout a live session
            is standing in.
    #>
    [CmdletBinding()]
    param([string]$Path)
    if (-not $Path) { return $false }
    $fwd = ($Path -replace '\\', '/')
    return ($fwd -match '(?i)(^|/)\.claude/worktrees/')
}

function Test-CcxSiblingWorktreePath {
    <#
    .SYNOPSIS
        Is $Path a sibling worktree of $PrimaryRoot -- by structure, not by string prefix?
    .DESCRIPTION
        "SIBLING" IS NOT A PREFIX MATCH, and treating it as one is how a reaper proposes to delete a
        directory that merely sounds related. Three conditions, all required:

          1. Same parent directory as the primary. `<primary>-x/y` starts with `<primary>-` and is not
             a sibling of anything.
          2. Leaf is exactly `<primary-leaf>-<something>`, with something non-empty.
          3. Not a harness worktree (see above), which can satisfy 1 and 2 and must still be excluded.

        Even with all three this only says the path LOOKS like ours. Whether it may be removed is a
        separate question answered by occupancy, cleanliness and merge state -- never by the name.
    #>
    [CmdletBinding()]
    param([string]$Path, [string]$PrimaryRoot)
    if (-not $Path -or -not $PrimaryRoot) { return $false }
    if (Test-CcxHarnessWorktreePath $Path) { return $false }

    $p = ConvertTo-CcxComparablePath $Path
    $root = ConvertTo-CcxComparablePath $PrimaryRoot
    if (-not $p -or -not $root -or $p -eq $root) { return $false }

    $pParent = ($p -replace '/[^/]+$', '')
    $rootParent = ($root -replace '/[^/]+$', '')
    if ($pParent -ne $rootParent) { return $false }

    $pLeaf = ($p -split '/')[-1]
    $rootLeaf = ($root -split '/')[-1]
    return ($pLeaf.Length -gt ($rootLeaf.Length + 1) -and $pLeaf.StartsWith("$rootLeaf-"))
}
