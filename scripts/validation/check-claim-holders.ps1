#Requires -Version 7.3
<#
.SYNOPSIS
    Claim holders per item. Fires when two live sessions hold one piece of work.

.DESCRIPTION
    WHAT IT SCANS. Every *.json in the claims directory -- the caller's -ClaimsDir, else
    <state-root>/claims -- and every session record the liveness fence can see. It prints the claim
    count, the session-record count and the config-root count on every run.

    TWO WAYS ONE ITEM ENDS UP WITH TWO LIVE HOLDERS, and neither is caught by anything else:

      1. TWO KEYS, ONE ITEM. Claim keys are flat and typed by a person, so `12`, `012` and `#12` are
         three files. scripts/coord/claim.ps1 stops a second worktree taking the SAME key; it cannot
         see that two different keys name one item. Each session's exclusive-create succeeded, both
         are correct locally, and the duplicate work goes ahead.
      2. ONE KEY, TWO SESSIONS IN THE HOLDING WORKTREE. The claiming identity is the working tree,
         not the session, so a second session running in that same tree inherits the claim without
         taking one. That is also the worktree collision the gate exists to stop, seen from the
         claims side.

    WHAT MAKES IT FAIL. Either shape above, with BOTH sessions fenced as LIVE.

    WHY LIVE AND NOT POSSIBLY-LIVE. scripts/coord/session-registry.ps1 rates a record LIVE,
    UNVERIFIED, UNREADABLE, STALE or DEAD, and says only the positive answer is safe to act on. A
    finding raised on UNVERIFIED would fire on a record the fence could not evaluate, which is a
    guess dressed as a measurement. Those pairs are counted and printed as a note instead.

    ONE FENCE, NOT TWO. Liveness comes from session-registry.ps1 by dot-source. Do not add a second
    notion of live here; two rosters that disagree about who is running is the drift that file exists
    to prevent.

    THE FIXTURE READS A DIFFERENT SOURCE, AND THAT IS A REAL LIMIT. -SessionSource plants the
    occupant list instead of reading the registry, so the broken fixture proves the ANALYSIS fires.
    It does not prove the live reader found anything -- that is what the corpus counts are for. Both
    halves are needed and neither substitutes for the other.

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/check-claim-holders.ps1
    pwsh -NoProfile -File scripts/validation/check-claim-holders.ps1 -ClaimsDir .\fixtures\broken\claim-holders\claims -SessionSource .\fixtures\broken\claim-holders\sessions.json
#>
[CmdletBinding()]
param(
    [string]$ClaimsDir = '',
    [string]$Repo = '',
    # A planted occupant list: a JSON array of { "cwd": "<path>", "state": "LIVE" }. Used instead of
    # the registry, so a fixture can hold a state no live machine can be asked to reproduce.
    [string]$SessionSource = '',
    [switch]$Json,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/../coord/session-registry.ps1"
. "$PSScriptRoot/_receipt.ps1"

$r = New-CcxCheckReceipt -Check 'claim-holders' `
    -Question 'is any one item held by two live sessions at once?' `
    -BrokenWhen 'two claim keys naming one item are held by two live worktrees, or one claim key''s worktree holds two live sessions'

function Get-ItemToken {
    <#
    .SYNOPSIS
        The item a claim key names, with the spellings a person varies folded together.

    .DESCRIPTION
        Mirrors what scripts/hooks/claim_check.py matches -- `#(\d{1,5})` in a commit subject, looked
        up as a flat filename -- and adds the two foldings a filename cannot express: a leading `#`
        that some people type, and leading zeros. `0012` and `12` are one item to a reader and two
        files to the filesystem, which is the whole gap this check covers.
    #>
    param([string]$Key)
    $k = "$Key".Trim().TrimStart('#').ToLowerInvariant()
    if ($k -match '^\d+$') { return [string][int]$k }
    return $k
}

# --- the occupant list: who is running, and where ------------------------------------------------
$occupants = [System.Collections.Generic.List[object]]::new()
$rootsExamined = 0
$recordsExamined = 0

if ($SessionSource) {
    $r.Source = "claims + planted sessions ($SessionSource)"
    if (-not (Test-Path -LiteralPath $SessionSource)) {
        $r.Blocked = "no session source at $SessionSource"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    $planted = @()
    try { $planted = @(Get-Content -LiteralPath $SessionSource -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch {
        $r.Blocked = "session source $SessionSource will not parse: $($_.Exception.Message)"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
    foreach ($p in $planted) {
        $recordsExamined++
        $occupants.Add([pscustomobject]@{
                Cwd   = [string](Get-CcxField -Record $p -Name @('cwd'))
                State = [string](Get-CcxField -Record $p -Name @('state'))
                Id    = [string](Get-CcxField -Record $p -Name @('sessionId', 'id'))
            })
    }
    $rootsExamined = 1
}
else {
    $r.Source = 'claims + the session registry (scripts/coord/session-registry.ps1)'
    $rootsExamined = @(Get-ClaudeConfigRoots).Count
    foreach ($h in @(Get-SessionRecords -IncludeUnreadable)) {
        $recordsExamined++
        if ($h.Unreadable) {
            # A half-written record is a session that launched a moment ago. Dropping it would make
            # a genuinely occupied worktree read as empty, so it is carried as UNREADABLE.
            $r.Unreadable++
            $occupants.Add([pscustomobject]@{ Cwd = ''; State = 'UNREADABLE'; Id = '' })
            continue
        }
        $l = Test-RecordLiveness -Record $h.Record
        $occupants.Add([pscustomobject]@{
                Cwd   = [string](Get-CcxField -Record $h.Record -Name @('cwd'))
                State = [string]$l.State
                Id    = [string](Get-CcxField -Record $h.Record -Name @('sessionId'))
            })
    }
}

# --- the claims ----------------------------------------------------------------------------------
if (-not $ClaimsDir) {
    try { $ClaimsDir = Join-Path (Get-CcxStateRoot -Repo $Repo) 'claims' }
    catch {
        $r.Blocked = "no state root: $($_.Exception.Message)"
        Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
    }
}
if (-not (Test-Path -LiteralPath $ClaimsDir)) {
    $r.Blocked = "no claims directory at $ClaimsDir -- nothing has ever claimed in this clone"
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

$rows = Read-CcxJsonRecords -Path $ClaimsDir
$claims = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    if ($row.Error) {
        $r.Unreadable++
        Add-CcxFinding -Receipt $r -Text "unreadable claim $($row.File): $($row.Error)"
        continue
    }
    $key = [string](Get-CcxField -Record $row.Record -Name @('key'))
    if (-not $key) { $key = [System.IO.Path]::GetFileNameWithoutExtension($row.Name) }
    $wt = [string](Get-CcxField -Record $row.Record -Name @('worktree'))
    if (-not $wt) {
        $r.Unreadable++
        continue
    }
    $claims.Add([pscustomobject]@{
            Key   = $key
            Item  = Get-ItemToken -Key $key
            Tree  = $wt
            Fold  = ConvertTo-CcxComparablePath -Path $wt
            Note  = [string](Get-CcxField -Record $row.Record -Name @('note'))
            File  = $row.File
        })
}

$r.Examined = $claims.Count
Add-CcxCorpus -Receipt $r -Name 'claim files' -Count $rows.Count
Add-CcxCorpus -Receipt $r -Name 'claims placed' -Count $claims.Count
Add-CcxCorpus -Receipt $r -Name 'config roots' -Count $rootsExamined
Add-CcxCorpus -Receipt $r -Name 'session records' -Count $recordsExamined

# --- how many sessions of each state sit in each claimed tree ------------------------------------
$possibly = @('LIVE', 'UNVERIFIED', 'UNREADABLE')
$liveIn = @{}
$maybeIn = @{}
foreach ($c in $claims) {
    if (-not $c.Fold) { continue }
    $live = 0
    $maybe = 0
    foreach ($o in $occupants) {
        $of = ConvertTo-CcxComparablePath -Path $o.Cwd
        if (-not $of) { continue }
        if (-not (Test-CcxPathUnder -Path $of -Root $c.Fold)) { continue }
        if ($o.State -eq 'LIVE') { $live++ }
        if ($possibly -contains $o.State) { $maybe++ }
    }
    $liveIn[$c.Fold] = $live
    $maybeIn[$c.Fold] = $maybe
}

# --- shape 1: two keys, one item ------------------------------------------------------------------
$softPairs = 0
foreach ($g in ($claims | Group-Object -Property Item)) {
    $trees = @($g.Group | Select-Object -ExpandProperty Fold -Unique)
    if ($trees.Count -lt 2) { continue }
    $liveTrees = @($trees | Where-Object { $liveIn.ContainsKey($_) -and $liveIn[$_] -gt 0 })
    $maybeTrees = @($trees | Where-Object { $maybeIn.ContainsKey($_) -and $maybeIn[$_] -gt 0 })
    if ($liveTrees.Count -ge 2) {
        $keys = (@($g.Group | Select-Object -ExpandProperty Key) -join ', ')
        Add-CcxFinding -Receipt $r -Text "item '$($g.Name)' is held under $($g.Count) keys ($keys) by $($liveTrees.Count) worktrees that each hold a LIVE session"
    }
    elseif ($maybeTrees.Count -ge 2) { $softPairs++ }
}

# --- shape 2: one key, two live sessions in the holding tree --------------------------------------
foreach ($c in $claims) {
    if (-not $c.Fold) { continue }
    if ($liveIn.ContainsKey($c.Fold) -and $liveIn[$c.Fold] -ge 2) {
        Add-CcxFinding -Receipt $r -Text "claim '$($c.Key)' is held by $($c.Tree), which has $($liveIn[$c.Fold]) LIVE sessions in it"
    }
}

if ($softPairs -gt 0) {
    Add-CcxNote -Receipt $r -Text "$softPairs item(s) span two worktrees whose sessions the fence could not rate LIVE -- possibly-live, not reported as findings"
}
$gone = @($claims | Where-Object { -not (Test-Path -LiteralPath $_.Tree) }).Count
if ($gone -gt 0) {
    Add-CcxNote -Receipt $r -Text "$gone claim(s) name a worktree that no longer exists -- stale notes, not a collision (release them with claim.ps1 -Release -Force)"
}

Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
