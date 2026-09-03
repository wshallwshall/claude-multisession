#Requires -Version 7.3
<#
.SYNOPSIS
    Allocation collisions. Fires when one sequence number landed in two files, or on two branches.

.DESCRIPTION
    WHAT IT SCANS. For every sequence in ccx.config.json: every ref `git for-each-ref` returns --
    local branches, remote-tracking branches, tags, notes, anything -- plus the working tree, listed
    with `git ls-tree -r --name-only`. Paths are matched against the sequence's own `filePattern`.
    It prints the ref count, the path count, the number count and the allocation-record count on
    every run.

    WHY EVERY REF AND NOT JUST THE TRUNK. The collision this exists for is invisible on any single
    branch: each side is internally consistent, and the duplicate exists only once both have merged.
    A scan of the trunk alone sees it after it has already cost the rework.

    WHAT MAKES IT FAIL.

      1. One number, two or more distinct paths, anywhere in the ref graph. A companion file that
         the number's own index row names is legal and excluded, which is the rule
         scripts/hooks/seq_check.py already applies at commit time.
      2. One number carried by a path that exists on one ref and a DIFFERENT path on another. This
         is case 1 seen from the branch side, and it is reported with the refs named.

    WHAT IS REPORTED AND NOT FAILED. A number that exists in the ref graph and appears in no
    allocation record. That reads as somebody grepping for the next free number instead of
    allocating one -- but the registry is per clone and a number allocated in another checkout is
    absent here for an innocent reason, so it is a note. scripts/hooks/seq_check.py declines to run
    the same rule in --ci for the same reason, and says so rather than leaving it looking like
    coverage.

    A REPOSITORY WITH NO SEQUENCES CONFIGURED IS CANNOT_TELL, not clean. There is nothing to collide
    on, so a green line here would be a claim about a control that is not installed.

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/check-allocation-collisions.ps1
    pwsh -NoProfile -File scripts/validation/check-allocation-collisions.ps1 -RefIndex .\fixtures\broken\allocation-collisions\refs.tsv
#>
[CmdletBinding()]
param(
    [string]$Repo = '',
    # A planted ref listing instead of the git walk: one `<ref><TAB><path>` line per file. Used by
    # the fixtures, because planting a two-branch collision in a real clone is a slow way to assert
    # one line of grouping logic.
    [string]$RefIndex = '',
    # Point config discovery at a specific ccx.config.json. Sets CCX_CONFIG for this process only,
    # which _common.ps1 names as the single supported override -- rather than adding a second one.
    [string]$ConfigPath = '',
    [switch]$Json,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
# Read git's exit codes explicitly. A ref that cannot be listed is an expected answer here, not a
# terminating error, and 'Stop' would turn one unreadable ref into a run that examined nothing.
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/_receipt.ps1"

$r = New-CcxCheckReceipt -Check 'allocation-collisions' `
    -Question 'did one sequence number land in two files, or on two branches?' `
    -BrokenWhen 'one number maps to two or more distinct paths across the ref graph, undeclared by its index row'

# --- the sequences ---------------------------------------------------------------------------------
if ($ConfigPath) { $env:CCX_CONFIG = $ConfigPath }
$cfg = $null
try { $cfg = Get-CcxConfig -From $(if ($Repo) { $Repo } else { $PWD.Path }) }
catch {
    $r.Blocked = "no ccx.config.json could be read: $($_.Exception.Message)"
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}
if (-not $cfg.sequences -or $cfg.sequences.Count -eq 0) {
    $r.Blocked = "no sequences configured in $($cfg.ConfigPath) -- there is no shared number to collide on"
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

# --- the corpus: every (ref, path) pair -------------------------------------------------------------
$pairs = [System.Collections.Generic.List[object]]::new()
$refsSeen = 0

if ($RefIndex) {
    $r.Source = "planted ref listing ($RefIndex)"
    if (-not (Test-Path -LiteralPath $RefIndex)) {
        $r.Blocked = "no ref listing at $RefIndex"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    $refSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($line in @(Get-Content -LiteralPath $RefIndex)) {
        if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
        $bits = $line -split "`t", 2
        if ($bits.Count -lt 2) { continue }
        [void]$refSet.Add($bits[0])
        $pairs.Add([pscustomobject]@{ Ref = $bits[0]; Path = $bits[1].Trim() })
    }
    $refsSeen = $refSet.Count
}
else {
    $r.Source = 'git for-each-ref + the working tree'
    # Invoke-CcxGit hands back ONE joined string, not an array, and returns $null on a git failure
    # rather than an empty string. Splitting here keeps that distinction: no refs and a failed git
    # call are different answers, and only the second is a hole in the census.
    $refBlob = Invoke-CcxGit -Repo $Repo -Arguments @('for-each-ref', '--format=%(refname)')
    if ($null -eq $refBlob) {
        $r.Blocked = 'git for-each-ref failed -- not a repository, or git is unavailable'
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    $refs = @($refBlob -split "`r?`n" | Where-Object { $_.Trim() })
    # HEAD is listed last so the working tree's own commit is always in the corpus even in a
    # detached checkout, which for-each-ref does not name.
    foreach ($ref in @($refs + 'HEAD')) {
        $ref = "$ref".Trim()
        if (-not $ref) { continue }
        $blob = Invoke-CcxGit -Repo $Repo -Arguments @('ls-tree', '-r', '--name-only', $ref)
        if ($null -eq $blob) {
            # A ref that will not list is a hole in the census, and a hole must cost the CLEAN.
            $r.Unreadable++
            continue
        }
        $refsSeen++
        foreach ($f in ($blob -split "`r?`n")) { if ("$f".Trim()) { $pairs.Add([pscustomobject]@{ Ref = $ref; Path = "$f".Trim() }) } }
    }
}

# --- group by number, per sequence -------------------------------------------------------------------
$matched = 0
$numbers = 0
$allocSeen = 0
$unallocated = [System.Collections.Generic.List[string]]::new()

foreach ($kind in @($cfg.sequences.Keys | Sort-Object)) {
    $seq = $cfg.sequences[$kind]
    $filePattern = [string]$seq.filePattern
    if (-not $filePattern) { continue }
    $fileRx = $null
    try { $fileRx = [regex]::new($filePattern) }
    catch {
        Add-CcxFinding -Receipt $r -Text "sequence '$kind': filePattern is not a valid regex -- $($_.Exception.Message)"
        continue
    }
    if ($fileRx.GetGroupNumbers().Count -lt 2) {
        Add-CcxFinding -Receipt $r -Text "sequence '$kind': filePattern has no capturing group around the number, so nothing can be grouped"
        continue
    }

    $byNumber = @{}
    foreach ($p in $pairs) {
        $m = $fileRx.Match($p.Path)
        if (-not $m.Success) { continue }
        $matched++
        $n = $m.Groups[1].Value
        if (-not $byNumber.ContainsKey($n)) { $byNumber[$n] = [System.Collections.Generic.List[object]]::new() }
        $byNumber[$n].Add($p)
    }
    $numbers += $byNumber.Keys.Count

    # The index text, read once per sequence from the working tree. A companion the index declares is
    # legal, and this is the same rule seq_check.py applies -- matched on the stem and on the full
    # basename, because an index row conventionally links a file by its stem.
    $indexText = ''
    $rowRx = $null
    if ($seq.indexFile -and $seq.indexRowPattern -and -not $RefIndex) {
        try { $rowRx = [regex]::new([string]$seq.indexRowPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline) } catch { $rowRx = $null }
        $indexPath = Join-Path (Get-CcxPrimaryRoot -Repo $Repo) ([string]$seq.indexFile)
        if (Test-Path -LiteralPath $indexPath) { $indexText = Get-Content -LiteralPath $indexPath -Raw -ErrorAction SilentlyContinue }
    }

    foreach ($n in ($byNumber.Keys | Sort-Object)) {
        $rows = $byNumber[$n]
        $paths = @($rows | Select-Object -ExpandProperty Path -Unique)
        if ($paths.Count -ge 2 -and $indexText -and $rowRx) {
            $row = ''
            foreach ($line in $indexText -split "`r?`n") {
                $mm = $rowRx.Match($line)
                if ($mm.Success -and $mm.Groups[1].Value -eq $n) { $row = $line; break }
            }
            if ($row) {
                $declared = @($paths | Where-Object {
                        $base = Split-Path -Path $_ -Leaf
                        $stem = if ($base.Contains('.')) { $base.Substring(0, $base.LastIndexOf('.')) } else { $base }
                        $row.Contains($base) -or $row.Contains($stem)
                    })
                # EVERY path, not all but one. The old rule allowed `count - 1`, and with two
                # paths a single declared one was enough to skip -- so the allowance was spent on
                # the ORIGINAL, which an index row names by convention, and an undeclared second
                # file rode free. Measured on a real repository: 0084-main.md on main, 0084-rogue.md
                # on another branch, an index row naming only 0084-main.md, verdict CLEAN. Deleting
                # that row and changing nothing else made the same repository BROKEN, so the row was
                # what suppressed it -- and every real allocated number has a row.
                #
                # "All but the first" is also order-dependent, and $paths comes out in ref-walk
                # order, so which path got the free pass was not something the rule controlled.
                if ($declared.Count -eq $paths.Count) { continue }
            }
        }
        if ($paths.Count -ge 2) {
            $where = (@($rows | ForEach-Object { "$($_.Path) on $($_.Ref)" } | Sort-Object -Unique) -join '; ')
            Add-CcxFinding -Receipt $r -Text "$kind number $n is carried by $($paths.Count) distinct paths: $where"
        }
    }

    # The allocation registry, for the note below. Per clone, so it is never a finding.
    if (-not $RefIndex) {
        $allocDir = ''
        try { $allocDir = Join-Path (Join-Path (Get-CcxStateRoot -Repo $Repo) 'alloc') $kind } catch { $allocDir = '' }
        if ($allocDir -and (Test-Path -LiteralPath $allocDir)) {
            $issued = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($a in (Read-CcxJsonRecords -Path $allocDir)) {
                $allocSeen++
                if ($a.Error) { $r.Unreadable++; continue }
                $num = [string](Get-CcxField -Record $a.Record -Name @('number'))
                if (-not $num) { $num = [System.IO.Path]::GetFileNameWithoutExtension($a.Name) }
                [void]$issued.Add($num)
            }
            foreach ($n in ($byNumber.Keys | Sort-Object)) {
                if (-not $issued.Contains($n)) { $unallocated.Add("$kind $n") }
            }
        }
    }
}

$r.Examined = $matched
Add-CcxCorpus -Receipt $r -Name 'sequences configured' -Count $cfg.sequences.Count
Add-CcxCorpus -Receipt $r -Name 'refs listed' -Count $refsSeen
Add-CcxCorpus -Receipt $r -Name 'ref/path pairs' -Count $pairs.Count
Add-CcxCorpus -Receipt $r -Name 'sequence-matched paths' -Count $matched
Add-CcxCorpus -Receipt $r -Name 'distinct numbers' -Count $numbers
Add-CcxCorpus -Receipt $r -Name 'allocation records' -Count $allocSeen

if ($unallocated.Count -gt 0) {
    Add-CcxNote -Receipt $r -Text ("$($unallocated.Count) number(s) exist in the ref graph with no allocation record in THIS clone -- " +
        "innocent if they were allocated in another checkout: " + (($unallocated | Select-Object -First 12) -join ', ') +
        $(if ($unallocated.Count -gt 12) { " (naming 12 of $($unallocated.Count))" } else { '' }))
}

Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
