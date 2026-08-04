#Requires -Version 7.3
<#
.SYNOPSIS
    Shared resolver: which repository / working tree does a git command actually act on?

.DESCRIPTION
    Dot-source this after _command.ps1. It answers one question -- given one simple command, the text
    that ran before it, and the session's cwd, WHICH TREES could this touch? -- and it answers it as a
    SET rather than a winner.

        $targets = Resolve-CcxGitTarget -Line $seg.Raw -Prefix $prefix -Cwd $payload.cwd

    WHY A SET AND NOT A WINNER. `--work-tree` and GIT_WORK_TREE say where FILES land; they do NOT say
    which repository is mutated, because GIT_DIR still resolves from the cwd. So
    `git --work-tree=/tmp/x reset --hard` run in a shared checkout still moves that checkout's HEAD
    and index. Treating those flags as a REPLACEMENT target turned a one-token flag into a bypass of
    the whole rule -- a measured deny becoming an allow. Only `-C` genuinely relocates both, so only
    `-C` replaces the cwd; everything else is additive, and the caller denies if ANY member of the set
    is governed.

    WHY ONE RESOLVER. Two rules once had two parsers and a real tree swap fell into the gap between
    them: the first read only `-C` and the cwd, so `cd <primary> && git reset --hard` resolved to the
    session's own ungoverned worktree and it handed off to the second -- which resolved the `cd`
    correctly, saw the shared tree, and returned on the grounds that the first rule owned it. The
    first rule had already declined. Both bowed out and the command ran. One resolver, one answer.

.NOTES
    Two defects in the previous implementations are fixed here, each marked FIX at its site:

      FIX 1 -- `-c` vs `-C`. The flag was parsed with `-match`, which is case-INSENSITIVE in
      PowerShell. git's lowercase `-c key=value` config override was therefore captured as if it were
      a path, and being the first match it also SHADOWED a real `-C` later in the same command. So
      `git -c core.pager=cat checkout main` resolved its target to the string `core.pager=cat`, which
      is governed by nothing, and the command was allowed at a cwd where it should have been refused.
      Parsed case-sensitively here, with lowercase `-c` explicitly consumed so it cannot be mistaken
      for the path flag.

      FIX 2 -- the `cd ../../..` hole. A relative path was canonicalised against THIS PROCESS's
      working directory. A hook process starts wherever the harness launched it, which is not the
      session's cwd -- so `../../..`, which is exactly how a session in a nested worktree names the
      repository root, resolved somewhere unrelated and `cd ../../.. && git reset --hard` did not look
      like it touched the shared tree at all. Every relative path is now resolved against the CWD THE
      COMMAND WILL RUN FROM, which arrives in the hook payload.
#>

# _common.ps1 supplies the canonicaliser. It is a hard dependency, not a nicety: without it every
# comparison below is a raw string compare and the resolver silently stops matching. Say so on stderr
# and stop, rather than continuing in a degraded state that looks identical to a clean run -- a caller
# on a fail-open path must catch this and leave a receipt, because "the gate could not load its
# dependency" and "the gate had nothing to say" are otherwise byte-identical.
$script:CcxCommonPath = $null
foreach ($candidate in @(
        (Join-Path $PSScriptRoot '_common.ps1'),
        (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'coord' '_common.ps1')))
    )) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $script:CcxCommonPath = $candidate; break }
}
if (-not $script:CcxCommonPath) {
    [Console]::Error.WriteLine(
        "ccx: _gittarget.ps1 could not find _common.ps1 next to it or in ../coord/. " +
        "If these files were installed outside the repository, the installer must copy _common.ps1 " +
        "alongside them.")
    throw 'ccx: _gittarget.ps1 requires _common.ps1.'
}
. $script:CcxCommonPath

function Get-CcxCdFromPrefix {
    <#
    .SYNOPSIS
        The single unambiguous directory change in $Prefix, or $null.
    .DESCRIPTION
        A `cd` is honoured ONLY from the text that ran BEFORE the git invocation. Reading it from the
        whole command made the resolver order-blind: `git checkout main && cd ../elsewhere` resolved
        to `../elsewhere` and allowed a swap of the tree the git call had already acted on.

        AMBIGUITY FALLS BACK TO THE CWD, which is the deny-side default. Ambiguous means: a `popd`, a
        `cd -`, a subshell or grouping character, or more than one directory change. In all of those
        the resolver cannot say where the command lands, and the safe answer for a guardrail is "it
        might be here".
    #>
    [CmdletBinding()]
    param([string]$Prefix)

    if ([string]::IsNullOrWhiteSpace($Prefix)) { return $null }
    if ($Prefix -match '(?:^|\s)(?:popd|cd\s+-(?:\s|$))') { return $null }
    if ($Prefix -match '[({]') { return $null }

    # cd / chdir / pushd / Set-Location / sl, with cmd's `/d` and PowerShell's -Path / -LiteralPath.
    $pattern = '(?:^|[;&|]|\s)(?:cd|chdir|pushd|Set-Location|sl)' +
        '(?:\s+(?:/d|-Path|-LiteralPath))?\s+"?([^"&|;]+?)"?\s*(?:&&|\|\||;|\||&|$)'
    $hits = [regex]::Matches($Prefix, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($hits.Count -ne 1) { return $null }

    $value = $hits[0].Groups[1].Value.Trim()
    if (-not $value) { return $null }
    return $value
}

function Get-CcxGitTargetRaw {
    <#
    .SYNOPSIS
        Every path a git command could be acting on, as RAW (original-case) strings.
    .OUTPUTS
        string[] -- the first element is the primary target (the `-C` value, the `cd`, or the cwd);
        the rest are additional trees the command could also touch.
    .DESCRIPTION
        RAW, NOT FOLDED, and this matters. A caller that shells out with `git -C <path>` must use the
        original case: a lower-cased path misses the real directory on a case-sensitive filesystem,
        git fails, and the rule falls through to its allow branch -- the guard turns itself off on the
        platform nobody is watching. Fold only for comparison, via ConvertTo-CcxComparablePath.
    #>
    [CmdletBinding()]
    param(
        # The RAW text of one simple command (Split-CcxCommand's .Raw), never the blanked Scan form:
        # the blanking that stops a commit message supplying a verb would also erase the path.
        [string]$Line,
        # The RAW text of everything that ran earlier on the same logical line.
        [string]$Prefix,
        # The session's working directory, from the hook payload.
        [string]$Cwd
    )

    $out = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Line) { $Line = '' }

    # ---- FIX 1: -C, case-SENSITIVELY, and never confused with -c ---------------------------------
    # Consume any lowercase `-c key=value` occurrences FIRST so they cannot be seen by the `-C`
    # pattern at all. Doing it by deletion rather than by a cleverer regex means a future edit to the
    # `-C` pattern cannot accidentally re-open the hole.
    $scanForC = $Line -creplace '(?:^|\s)-c\s+[^\s]+', ' '

    $cPath = $null
    # Spaced form: `-C <path>`.
    if ($scanForC -cmatch '(?:^|\s)-C\s+"([^"]+)"' -or $scanForC -cmatch '(?:^|\s)-C\s+([^\s"]+)') {
        $cPath = $Matches[1]
    }
    # Attached form: `git -C../x status` is legal. Require the value to START with a path-ish
    # character, so `-Command` is not read as `-C` with the value `ommand`.
    elseif ($scanForC -cmatch '(?:^|\s)-C(?=[./\\~])([^\s"]+)') {
        $cPath = $Matches[1]
    }

    if ($cPath) {
        # `-C` relocates BOTH the git dir and the work tree, so it genuinely REPLACES the cwd. It is
        # the only flag that does.
        $out.Add($cPath)
    } else {
        $cd = Get-CcxCdFromPrefix -Prefix $Prefix
        if ($cd) { $out.Add($cd) } elseif ($Cwd) { $out.Add($Cwd) }
    }

    # ---- Additive targets: these never replace the cwd -------------------------------------------
    # --work-tree / GIT_WORK_TREE relocate where FILES land but not which repository is mutated, so
    # the cwd's repository is still in play and goes into the set alongside them.
    foreach ($pat in @(
            '(?:^|\s)--work-tree[=\s]+"?([^"\s]+)"?',
            '(?:^|\s)GIT_WORK_TREE=?"?([^"\s]+)"?'
        )) {
        if ($Line -cmatch $pat) {
            $out.Add($Matches[1])
            if ($Cwd) { $out.Add($Cwd) }
        }
    }

    # --git-dir / GIT_DIR name the REPOSITORY; the working tree is conventionally its parent. Add both
    # rather than reasoning about which, because a wrong guess here is a silent miss.
    foreach ($pat in @(
            '(?:^|\s)--git-dir[=\s]+"?([^"\s]+)"?',
            '(?:^|\s)GIT_DIR=?"?([^"\s]+)"?'
        )) {
        if ($Line -cmatch $pat) {
            $out.Add($Matches[1])
            $out.Add((Join-Path $Matches[1] '..'))
        }
    }

    return @($out | Where-Object { $_ })
}

function Resolve-CcxGitTarget {
    <#
    .SYNOPSIS
        Get-CcxGitTargetRaw, plus the canonical comparison form of each candidate.
    .OUTPUTS
        PSCustomObject[] with Raw and Comparable. Raw is what you hand to git; Comparable is what you
        compare against an allowlist.
    .DESCRIPTION
        FIX 2 lives here: each candidate is canonicalised against $Cwd -- the directory the COMMAND
        will run from -- so a relative `../../..` resolves the way the shell will resolve it rather
        than the way this hook process happens to be sitting.

        Candidates that cannot be canonicalised are dropped rather than passed through as raw strings.
        A path we cannot resolve is one we cannot make a claim about, and a string comparison against
        an unresolved path is a coin toss dressed as a decision.
    #>
    [CmdletBinding()]
    param(
        [string]$Line,
        [string]$Prefix,
        [string]$Cwd
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($raw in (Get-CcxGitTargetRaw -Line $Line -Prefix $Prefix -Cwd $Cwd)) {
        $cmp = ConvertTo-CcxComparablePath -Path $raw -Base $Cwd
        if (-not $cmp) { continue }
        if (-not $seen.Add($cmp)) { continue }
        $out.Add([pscustomobject]@{ Raw = $raw; Comparable = $cmp })
    }
    return $out.ToArray()
}

function Test-CcxCommandTargets {
    <#
    .SYNOPSIS
        Does any target of this command fall under one of $Roots? Returns the matching root or $null.
    .PARAMETER Roots
        Objects with .Compare (canonical form, from ConvertTo-CcxComparablePath) and .Display (the
        operator's own spelling). Two forms on purpose: the comparison must be canonical, and a
        message that shouts a mangled lower-cased path back at the reader looks broken even when the
        match is right.
    .PARAMETER ExemptHarnessWorktrees
        Skip a candidate that lives under a `.claude/worktrees/` segment. Such a worktree sits inside
        the primary's path but is a tree of its own -- a git verb there swaps only its own files. Rules
        that protect the SHARED tree must pass this; rules about the shared .git directory (config
        writes, worktree removal) must NOT, because those reach every sibling from anywhere.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Targets,
        [object[]]$Roots,
        [switch]$ExemptHarnessWorktrees
    )
    if (-not $Targets -or -not $Roots) { return $null }

    foreach ($t in $Targets) {
        foreach ($root in $Roots) {
            if (-not (Test-CcxPathUnder -Path $t.Comparable -Root $root.Compare)) { continue }
            if ($ExemptHarnessWorktrees -and (Test-CcxHarnessWorktreePath $t.Comparable)) { continue }
            return $root
        }
    }
    return $null
}
