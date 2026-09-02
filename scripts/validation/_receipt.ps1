#Requires -Version 7.3
<#
.SYNOPSIS
    The receipt every validation check prints, and the one rule that turns a receipt into a verdict.

.DESCRIPTION
    Dot-source this. It defines functions and writes nothing to stdout, so a caller that must emit
    pure JSON can load it safely.

        . "$PSScriptRoot/_receipt.ps1"

    WHY THIS FILE EXISTS. A check that prints only pass or fail cannot be told apart from a check
    that examined nothing. Both print the same line, and the empty one prints it faster. So every
    check here reports the size of the corpus it read beside its finding, and the verdict is derived
    from both rather than from the finding alone.

    THREE VERDICTS, NOT TWO. `CANNOT_TELL` is the whole point of the file:

        CLEAN        something was examined, and no defect was found
        BROKEN       a defect was found
        CANNOT_TELL  nothing was examined, or part of the corpus would not parse

    A check that found nothing to read must never render as a check that found nothing wrong. That
    conflation is the failure this whole directory is about, and it is why `Examined` is mandatory
    rather than decorative: a check that forgets to set it gets CANNOT_TELL, not a free pass.

    BROKEN OUTRANKS CANNOT_TELL. A partial census that found a real defect still found it. Ordering
    it the other way would let one unreadable file suppress a true finding.

    NO CHECK MAY TRUNCATE ITS CORPUS. Nothing here uses -First, head or a sample cap while counting.
    `-MaxReport` bounds only how many findings are PRINTED, and the printed line then names the full
    count, so a bounded display can never read as a complete list.
#>

# NO Set-StrictMode, and the omission is deliberate. This file is dot-sourced beside
# scripts/coord/_common.ps1, whose header states it must stay strict-mode free so a missing
# property on a vendor payload degrades to an empty answer rather than a terminating error.
# Strict mode set here would reach those functions through the caller's scope and undo that.

# The exit code each verdict maps to. One definition, because the runner and the tests both read it.
$script:CcxVerdictExit = @{ CLEAN = 0; BROKEN = 1; CANNOT_TELL = 2 }

function New-CcxCheckReceipt {
    <#
    .SYNOPSIS
        Start a receipt. `Question` is the sentence the check answers, printed with the verdict.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][string]$Question,
        # What reading makes this check fail. Printed on every run, including a clean one, so a
        # reader can tell what the green line is claiming.
        [Parameter(Mandatory)][string]$BrokenWhen
    )
    return [pscustomobject]@{
        Check      = $Check
        Question   = $Question
        BrokenWhen = $BrokenWhen
        # The primary corpus size: how many things the ANALYSIS looked at. $null until set, and a
        # $null here is what produces CANNOT_TELL for a check that never reached its own corpus.
        Examined   = $null
        # Items found but not placeable -- unparseable, or missing the field the analysis keys on.
        # Any at all costs the run its CLEAN, because the defect may be inside exactly those.
        Unreadable = 0
        # Secondary counters, printed in insertion order. Detail, never the verdict.
        Corpus     = [ordered]@{}
        Findings   = [System.Collections.Generic.List[string]]::new()
        Notes      = [System.Collections.Generic.List[string]]::new()
        # Set when the check could not run at all. A reason here forces CANNOT_TELL.
        Blocked    = ''
        Source     = ''
    }
}

function Add-CcxCorpus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][int]$Count)
    $Receipt.Corpus[$Name] = $Count
}

function Add-CcxFinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][string]$Text)
    $Receipt.Findings.Add($Text)
}

function Add-CcxNote {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][string]$Text)
    $Receipt.Notes.Add($Text)
}

function Get-CcxVerdict {
    <#
    .SYNOPSIS
        The single verdict rule. Every check reads it here rather than deciding for itself.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Receipt)
    if ($Receipt.Findings.Count -gt 0) { return 'BROKEN' }
    if ($Receipt.Blocked) { return 'CANNOT_TELL' }
    if ($null -eq $Receipt.Examined) { return 'CANNOT_TELL' }
    if ([int]$Receipt.Examined -le 0) { return 'CANNOT_TELL' }
    if ([int]$Receipt.Unreadable -gt 0) { return 'CANNOT_TELL' }
    return 'CLEAN'
}

function Get-CcxVerdictExitCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Verdict)
    if ($script:CcxVerdictExit.ContainsKey($Verdict)) { return [int]$script:CcxVerdictExit[$Verdict] }
    # An unknown verdict is a bug in a caller, and the safe reading of a bug is "could not tell".
    return 2
}

function Write-CcxReceipt {
    <#
    .SYNOPSIS
        Print the receipt. Text by default, one JSON object with -Json. Returns nothing.

    .DESCRIPTION
        IT RETURNS NOTHING ON PURPOSE, and the first version did not. It emitted its lines with
        Write-Output and returned the exit code, so every caller wrote `exit (Write-CcxReceipt ...)`
        -- and the parentheses captured the LINES along with the code. Every check printed nothing at
        all and exited 0. A silent success is the exact reading this directory exists to refuse, and
        it was shipped by the file that defines the rule. Printing and exiting are two jobs now:
        Complete-CcxCheck below does both, in that order.

    .DESCRIPTION
        -MaxReport bounds the number of FINDINGS printed and nothing else. The count printed is
        always the full one, and a bounded list says so on its own line. 0 means print them all.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Receipt,
        [switch]$Json,
        [int]$MaxReport = 0
    )
    $verdict = Get-CcxVerdict -Receipt $Receipt

    if ($Json) {
        $payload = [ordered]@{
            check      = $Receipt.Check
            verdict    = $verdict
            question   = $Receipt.Question
            brokenWhen = $Receipt.BrokenWhen
            source     = $Receipt.Source
            examined   = $Receipt.Examined
            unreadable = $Receipt.Unreadable
            corpus     = $Receipt.Corpus
            findings   = @($Receipt.Findings)
            notes      = @($Receipt.Notes)
            blocked    = $Receipt.Blocked
        }
        Write-Output ($payload | ConvertTo-Json -Depth 6 -Compress)
        return
    }

    Write-Output ""
    Write-Output "$($Receipt.Check): $verdict"
    Write-Output "  asks       : $($Receipt.Question)"
    Write-Output "  broken when: $($Receipt.BrokenWhen)"
    if ($Receipt.Source) { Write-Output "  source     : $($Receipt.Source)" }

    # THE CORPUS PRINTS ON EVERY RUN, INCLUDING A CLEAN ONE. A green line whose corpus is beside it
    # can be read; a green line on its own cannot be told from a probe that never looked.
    $examined = if ($null -eq $Receipt.Examined) { "(never set -- the check did not reach its corpus)" } else { $Receipt.Examined }
    Write-Output "  examined   : $examined"
    if ([int]$Receipt.Unreadable -gt 0) { Write-Output "  unreadable : $($Receipt.Unreadable)" }
    foreach ($k in $Receipt.Corpus.Keys) { Write-Output ("    {0,-24} {1}" -f $k, $Receipt.Corpus[$k]) }

    if ($Receipt.Blocked) { Write-Output "  blocked    : $($Receipt.Blocked)" }
    foreach ($n in $Receipt.Notes) { Write-Output "  note       : $n" }

    if ($Receipt.Findings.Count -gt 0) {
        $shown = if ($MaxReport -gt 0 -and $Receipt.Findings.Count -gt $MaxReport) { $MaxReport } else { $Receipt.Findings.Count }
        Write-Output "  findings   : $($Receipt.Findings.Count)"
        for ($i = 0; $i -lt $shown; $i++) { Write-Output "    - $($Receipt.Findings[$i])" }
        if ($shown -lt $Receipt.Findings.Count) {
            Write-Output "    (showing $shown of $($Receipt.Findings.Count) -- rerun with -MaxReport 0 for all)"
        }
    }
}

function Complete-CcxCheck {
    <#
    .SYNOPSIS
        Print the receipt, then end the check with the exit code its verdict maps to.

    .DESCRIPTION
        `exit` inside a function ends the SCRIPT that called it, which is what makes this one call
        rather than two lines every check would have to get right in every early-return branch.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Receipt, [switch]$Json, [int]$MaxReport = 0)
    Write-CcxReceipt -Receipt $Receipt -Json:$Json -MaxReport $MaxReport
    exit (Get-CcxVerdictExitCode -Verdict (Get-CcxVerdict -Receipt $Receipt))
}

function Read-CcxJsonRecords {
    <#
    .SYNOPSIS
        Read every *.json under a directory, keeping the ones that would not parse.

    .DESCRIPTION
        Returns one row per FILE, never one per file that happened to parse. A dropped bad file is
        the census defect this directory exists to catch: the count shrinks by one and the verdict
        stays green, because the thing that would have failed is the thing that vanished.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Filter = '*.json')
    $rows = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction SilentlyContinue)) {
        $rec = $null
        $err = ''
        try { $rec = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $err = $_.Exception.Message }
        if ($null -eq $rec -and -not $err) { $err = 'parsed to nothing (empty, or being written right now)' }
        $rows.Add([pscustomobject]@{ File = $f.FullName; Name = $f.Name; Record = $rec; Error = $err })
    }
    return $rows
}

function Get-CcxField {
    <#
    .SYNOPSIS
        One field off a parsed record, or '' -- never a strict-mode throw on a schema we do not own.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Record, [Parameter(Mandatory)][string[]]$Name)
    if ($null -eq $Record) { return '' }
    foreach ($n in $Name) {
        try {
            if ($Record.PSObject.Properties.Name -contains $n) {
                $v = $Record.$n
                if ($null -ne $v -and "$v" -ne '') { return $v }
            }
        }
        catch { }
    }
    return ''
}

function ConvertTo-CcxLocalKind {
    <#
    .SYNOPSIS
        A [datetime] in Local kind, whatever kind it arrived in.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][datetime]$Value)
    # Utc converts. Unspecified does NOT: no offset was written, so the local wall clock is the only
    # honest reading of it, and ToLocalTime() would treat it as UTC and shift it by the offset.
    if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value.ToLocalTime() }
    return $Value
}

function ConvertTo-CcxTime {
    <#
    .SYNOPSIS
        A timestamp field as [datetime], or $null. Accepts ISO-8601 and unix epoch milliseconds.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    # EVERY RETURN IS LOCAL KIND, because every caller compares against (Get-Date), which is local,
    # and PowerShell compares two DateTimes on ticks while IGNORING Kind. RoundtripKind gives a 'Z'
    # string Kind=Utc, so west of UTC a message read as sent in the future and lateness up to the
    # machine's offset was hidden; east of UTC the same code invented lateness. Measured at -05:00:
    # one instant, spelled 'Z' and spelled '-05:00', four real hours past a thirty-minute ttl --
    # CLEAN for the first and BROKEN for the second, over identical corpus counts.
    #
    # The fixtures all carry timestamps eight months stale, so five hours of skew could not flip
    # them, which is why every control stayed green over it.
    if ($Value -is [datetime]) { return (ConvertTo-CcxLocalKind $Value) }
    if ($Value -is [datetimeoffset]) { return $Value.LocalDateTime }
    # A bare number is epoch milliseconds -- the unit the session registry uses. Seconds would be a
    # second guess, and guessing the unit is how a fence silently changes what it measures.
    if ("$Value" -match '^\d{10,}$') {
        try { return [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]"$Value").LocalDateTime } catch { return $null }
    }
    try {
        return (ConvertTo-CcxLocalKind ([datetime]::Parse("$Value",
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind)))
    }
    catch { return $null }
}
