#Requires -Version 7.3
<#
.SYNOPSIS
    Run every validation check -- but only after proving each one still fires on a broken corpus.

.DESCRIPTION
    THE ORDER IS THE DESIGN. Controls first, live estate second, and a control that misbehaves stops
    the run before a single live verdict is printed. An instrument validated only against a healthy
    system cannot tell a clean result from a broken probe, and a broken probe returns a confident
    zero that reads exactly like good news. scripts/validation/README.md carries the measurement that
    made this rule, including the session whose quoting bug produced two clean empty answers it
    nearly reported as a real reading.

    TWO CONTROLS PER CHECK, NOT ONE. The broken fixture must come back BROKEN and the clean fixture
    must come back CLEAN. One alone is worth little: a check hard-wired to fail passes the first, a
    check hard-wired to pass passes the second, and only the pair rules out both.

    THE CONTROLS ARE NOT SKIPPABLE. There is deliberately no switch to run the live pass on its own.
    A run that skips its controls produces the reading this whole directory exists to refuse.

    EXIT CODES
      0  every live check CLEAN
      1  at least one live check BROKEN
      2  no BROKEN, but at least one CANNOT_TELL
      3  a control misbehaved -- nothing about the live estate was measured

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/run-checks.ps1
    pwsh -NoProfile -File scripts/validation/run-checks.ps1 -SelfTestOnly
#>
[CmdletBinding()]
param(
    # Prove the instruments and stop. Useful in CI, where there is no estate to measure.
    [switch]$SelfTestOnly,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$fixtures = Join-Path $PSScriptRoot 'fixtures'

# THE REGISTRY. Every check ships with the two fixtures that prove it, and tests/ reads this array to
# refuse a check that arrives without them -- an unproven instrument is the failure mode, so it must
# not be possible to add one quietly.
$CHECKS = @(
    @{
        Name   = 'message-delivery'
        Script = 'check-message-delivery.ps1'
        Live   = @()
        Broken = @('-MailRoot', (Join-Path $fixtures 'broken/message-delivery'))
        Clean  = @('-MailRoot', (Join-Path $fixtures 'clean/message-delivery'))
    },
    @{
        Name   = 'message-expiry'
        Script = 'check-message-expiry.ps1'
        Live   = @()
        Broken = @('-MailRoot', (Join-Path $fixtures 'broken/message-expiry'))
        Clean  = @('-MailRoot', (Join-Path $fixtures 'clean/message-expiry'))
    },
    @{
        Name   = 'claim-holders'
        Script = 'check-claim-holders.ps1'
        Live   = @()
        Broken = @('-ClaimsDir', (Join-Path $fixtures 'broken/claim-holders/claims'), '-SessionSource', (Join-Path $fixtures 'broken/claim-holders/sessions.json'))
        Clean  = @('-ClaimsDir', (Join-Path $fixtures 'clean/claim-holders/claims'), '-SessionSource', (Join-Path $fixtures 'clean/claim-holders/sessions.json'))
    },
    @{
        Name   = 'allocation-collisions'
        Script = 'check-allocation-collisions.ps1'
        Live   = @()
        Broken = @('-RefIndex', (Join-Path $fixtures 'broken/allocation-collisions/refs.tsv'), '-ConfigPath', (Join-Path $fixtures 'broken/allocation-collisions/ccx.config.fixture.json'))
        Clean  = @('-RefIndex', (Join-Path $fixtures 'clean/allocation-collisions/refs.tsv'), '-ConfigPath', (Join-Path $fixtures 'clean/allocation-collisions/ccx.config.fixture.json'))
    },
    @{
        Name   = 'session-reaping'
        Script = 'check-session-reaping.ps1'
        Live   = @()
        Broken = @('-SessionSource', (Join-Path $fixtures 'broken/session-reaping/sessions.json'))
        Clean  = @('-SessionSource', (Join-Path $fixtures 'clean/session-reaping/sessions.json'))
    }
)

function Invoke-Check {
    <#
    .SYNOPSIS
        Run one check in its own process and return its verdict and exit code.

    .DESCRIPTION
        A CHILD PROCESS RATHER THAN A DOT-SOURCE. Each check ends in `exit <code>`, and the exit code
        is the contract every caller reads. Running them in this process would make one check's exit
        ambiguous with the runner's own, and a crash in one would end the run over the rest.
    #>
    param([string]$Script, [string[]]$Arguments)
    $path = Join-Path $PSScriptRoot $Script
    $out = & pwsh -NoProfile -File $path @Arguments -Json 2>&1
    $code = $LASTEXITCODE
    $verdict = 'UNPARSEABLE'
    $text = ($out -join "`n")
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.TrimStart().StartsWith('{')) {
            try { $verdict = [string]((ConvertFrom-Json $line).verdict) } catch { }
        }
    }
    return [pscustomobject]@{ Verdict = $verdict; Code = $code; Text = $text }
}

# --- the controls ----------------------------------------------------------------------------------
Write-Output ''
Write-Output 'CONTROLS -- each check against a planted broken corpus and a planted clean one.'
Write-Output 'A check that cannot fire on the first, or cannot stay quiet on the second, is not an instrument.'
Write-Output ''

$controlFailures = [System.Collections.Generic.List[string]]::new()
foreach ($c in $CHECKS) {
    $b = Invoke-Check -Script $c.Script -Arguments $c.Broken
    $k = Invoke-Check -Script $c.Script -Arguments $c.Clean
    $bOk = ($b.Verdict -eq 'BROKEN' -and $b.Code -eq 1)
    $kOk = ($k.Verdict -eq 'CLEAN' -and $k.Code -eq 0)
    $mark = if ($bOk -and $kOk) { 'PROVEN ' } else { 'FAILED ' }
    Write-Output ("  {0} {1,-24} broken fixture -> {2} ({3})   clean fixture -> {4} ({5})" -f $mark, $c.Name, $b.Verdict, $b.Code, $k.Verdict, $k.Code)
    if (-not $bOk) { $controlFailures.Add("$($c.Name): the broken fixture did not come back BROKEN -- it returned $($b.Verdict) with exit $($b.Code)") }
    if (-not $kOk) { $controlFailures.Add("$($c.Name): the clean fixture did not come back CLEAN -- it returned $($k.Verdict) with exit $($k.Code)") }
}

Write-Output ''
Write-Output "  checks registered: $($CHECKS.Count)    control runs: $($CHECKS.Count * 2)"

if ($controlFailures.Count -gt 0) {
    Write-Output ''
    Write-Output 'REFUSING TO MEASURE THE LIVE ESTATE. One or more instruments did not behave:'
    foreach ($f in $controlFailures) { Write-Output "  - $f" }
    Write-Output ''
    Write-Output 'Whatever these checks would have said about the live estate is unknown, not clean.'
    exit 3
}

if ($SelfTestOnly) {
    Write-Output ''
    Write-Output 'Every instrument is proven. -SelfTestOnly was given, so nothing live was measured.'
    exit 0
}

# --- the live pass -----------------------------------------------------------------------------------
Write-Output ''
Write-Output 'LIVE -- the same checks against this machine.'

$results = [System.Collections.Generic.List[object]]::new()
foreach ($c in $CHECKS) {
    $path = Join-Path $PSScriptRoot $c.Script
    $args_ = @($c.Live) + @('-MaxReport', $MaxReport)
    & pwsh -NoProfile -File $path @args_
    $code = $LASTEXITCODE
    $verdict = switch ($code) { 0 { 'CLEAN' } 1 { 'BROKEN' } 2 { 'CANNOT_TELL' } default { "EXIT $code" } }
    $results.Add([pscustomobject]@{ Name = $c.Name; Verdict = $verdict; Code = $code })
}

Write-Output ''
Write-Output 'SUMMARY'
foreach ($x in $results) { Write-Output ("  {0,-24} {1}" -f $x.Name, $x.Verdict) }
Write-Output ''
Write-Output '  CANNOT_TELL is not a pass. It means nothing was examined, so nothing was measured.'
Write-Output '  scripts/validation/README.md says what to do about each one.'

if (@($results | Where-Object { $_.Code -eq 1 }).Count -gt 0) { exit 1 }
if (@($results | Where-Object { $_.Code -ne 0 }).Count -gt 0) { exit 2 }
exit 0
