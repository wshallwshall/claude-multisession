#Requires -Version 7.3
<#
.SYNOPSIS
    Poll for pull requests a consuming repository has labelled red, and start one attributing seat
    per red -- without being a session itself, and without starting two seats on one failure.

.DESCRIPTION
    THE GAP THIS FILLS. When a required check fails, nothing tells any session. GitHub cannot reach
    into a session, so the only path was: a long-lived console session notices while polling, then
    spawns a seat to attribute the failure. That makes the console a single point of failure, and it
    is already the only seat the operator talks to. While it is busy, a red sits unattributed.

    THIS IS NOT A PUSH, AND MUST NOT BE DESCRIBED AS ONE. GitHub still cannot reach into a session.
    What changes is the price of asking. The consuming repository labels a pull request when a
    required check fails, so noticing costs ONE list call across every open pull request instead of
    a check-rollup fetch per pull request. That is the difference between a poll you can afford to
    run every minute and one you cannot.

    THE LABEL IS A CONTRACT, NOT A DEFINITION. The consuming repository owns the name. It is read
    from `ciRed.label` in ccx.config.json and falls back to `ci-red`. The receipt always names the
    source, so a repository that never configured one cannot be mistaken for one that did.

    FOUR PROPERTIES, EACH OF WHICH COST SOMETHING TO LEARN.

    1. THIS IS A SCRIPT, NOT A SEAT. A resident session watching for reds costs 2,108 metered tokens
    per waiting minute on a three-minute heartbeat, and 22,275 on a ten-minute sleep loop. This file
    makes zero model calls. It starts a model only when a red already exists, so a quiet repository
    costs three API round trips and nothing else.

    2. IT STARTS A FRESH SESSION; IT DOES NOT WAKE ONE. A worker that finished its turn has exited
    -- measured on the reference fleet, 740 session records against 2 live sessions -- so there is
    usually nobody to wake. The branch and the worktree survive, so a fresh session CONTINUES the
    work rather than restarting it. What does not survive is any memory of the last red, which is
    why every spawn appends to a per-pull-request journal under the state root, and why the briefing
    tells the seat to read that journal first and write to it last.

    3. IT REFUSES TO START A SEAT ON A RED SOMEBODY IS ALREADY HANDLING. Two seats attributing one
    failure is worse than none, because each assumes the other did not. The claim is taken with
    scripts/coord/claim.ps1, the repository's existing atomic claim, rather than a second registry
    invented here. Two guards are needed, because that script alone does not cover this caller:

      * ACROSS SESSIONS, claim.ps1's exclusive file create IS the mutual exclusion. A peer holding
        the key makes -Take exit non-zero, and this script skips that red.
      * ACROSS TICKS OF THIS WATCHER it is not, because re-taking a key you already hold is a
        documented SUCCESS -- a session has to be able to re-assert its own claim. Every tick runs
        from the same worktree, so every tick would re-take its own claim and exit 0. So the whole
        pass runs inside the `ci-red-watch` ccx lock, and the claim file is tested for existence
        before -Take is called.

    After -Take succeeds, this script checks that the claim file it predicted actually appeared. The
    prediction repeats a path formula that lives in claim.ps1, and a formula in two places drifts.
    If the file is not there, the run refuses to spawn and reports CLAIM-UNVERIFIABLE rather than
    spawning on a claim it cannot see -- which would spawn again on every future tick.

    4. AN EMPTY RESULT FROM AN UNPROVEN SOURCE IS UNKNOWN, NOT ZERO. Measured 2026-08-31:
    CLAUDE_CONFIG_DIR pointing at a directory that does not exist makes `claude agents --json`
    return an empty list and exit 0. No error, no warning, so a mistyped root and an empty fleet are
    byte-identical. The same shape is available here three ways, and each has a control whose
    reading must come back non-empty if the check is working:

      * The repository name could be wrong. Control: the API must echo the same full name back.
      * The label may never have been created on the consumer. Control: the API must echo the same
        label name back. Without this, a contract nobody installed reads exactly like a repository
        with nothing red.
      * The list call could fail. Control: the open pull request population must be readable, and
        every pull request the label query names must also appear in it.

    A control that comes back empty makes the run CANNOT-LOOK, exit 2, and no all-clear. Every
    finding carries what was scanned beside it: the repository, the label, where each came from, and
    how many open pull requests were examined.

    WHAT THIS DOES NOT DO. It does not decide whose failure a red is. That is the spawned seat's
    whole job, and it is why a builder-facing autofix is not a substitute: a red belongs to the pull
    request, to the trunk, to a flake, or to the merge queue, and only the first is a builder's to
    fix.

.PARAMETER Gh
    The GitHub client. Defaults to `gh` on PATH. A path to a script works too, which is how the
    tests substitute a stub with no network.

.PARAMETER DryRun
    Look and report. Claim nothing, start nothing. Safe to run at any time.

.OUTPUTS
    Exit 0  Looked successfully. Reds may or may not have been found; the receipt says which.
    Exit 1  Looked successfully, and at least one red could not be handed to a seat.
    Exit 2  COULD NOT LOOK. A control came back empty. This is never an all-clear.

.EXAMPLE
    pwsh -NoProfile -File scripts/cron/watch-ci-red.ps1
    pwsh -NoProfile -File scripts/cron/watch-ci-red.ps1 -DryRun
    pwsh -NoProfile -File scripts/cron/watch-ci-red.ps1 -Json
#>
[CmdletBinding()]
param(
    # Which checkout anchors the state root, the claim registry and the lock. Defaults to the git
    # toplevel of the current directory.
    [string]$RepoRoot,

    # owner/name to poll. Falls back to ciRed.repo in ccx.config.json, then to the origin remote.
    [string]$Repo,

    # The label the consuming repository applies when a required check fails. Falls back to
    # ciRed.label, then to 'ci-red'.
    [string]$Label,

    # Prefix for the claim key, so one clone watching two repositories does not collide its own
    # claims. Falls back to ciRed.claimPrefix, then to 'ci-red-pr'.
    [string]$ClaimPrefix,

    # The GitHub client. A path works as well as a name on PATH.
    [string]$Gh = 'gh',

    # What starts a seat. Falls back to ciRed.spawn.command, then to 'claude'. Give a full path if
    # the command is a shim the shell resolves but a process launch does not.
    [string]$SpawnCommand,

    # Fixed arguments passed before the generated prompt. Falls back to ciRed.spawn.args, then to
    # @('-p').
    [string[]]$SpawnArgs,

    # Look and report; take no claim and start nothing.
    [switch]$DryRun,

    # Emit the receipt as JSON on stdout instead of text.
    [switch]$Json,

    # Wait for each started process to exit. Off in production, because a tick must not block on a
    # session that runs for an hour. Tests turn it on so a spawn is observable without a sleep.
    [switch]$WaitForSpawn,

    # How many pull requests to ask for. A result that fills this is reported as possibly truncated,
    # because a count taken from a capped list is not a census.
    [int]$Limit = 200,

    # How long to wait for a sibling tick to finish before giving up.
    [int]$LockTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
# gh and git report ordinary answers through non-zero exits ("no such label", "not a repository").
# With the native-command error preference on, 'Stop' would turn each of those into a crash, and
# telling an empty answer from a failed one is this script's whole job.
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/../coord/lock.ps1"

# The repository's shared exit vocabulary. 2 means "could not tell", and it must never read as a
# pass.
$EXIT_OK = 0
$EXIT_FAILED = 1
$EXIT_REFUSED = 2

# ------------------------------------------------------------------------------------------------
# Plumbing
# ------------------------------------------------------------------------------------------------

# Same discipline as Invoke-CcxGit. A swallowed failure does not read as a failure, it reads as an
# empty result, and downstream that becomes "no pull request is red". So the caller is handed an Ok
# flag it has to look at rather than a string it can mistake for an answer.
function Invoke-Gh {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)

    $previous = $ErrorActionPreference
    # A native command writing to stderr is DATA here, not a failure to stop on. `gh` reports "could
    # not resolve to a Label" that way, and that answer is one this script is built to read.
    $ErrorActionPreference = 'Continue'
    $all = $null
    try {
        $all = & $Gh @Arguments 2>&1
        $code = $LASTEXITCODE
    } catch {
        # A client that is not installed at all lands here. It is a failure, never an empty result.
        return [pscustomobject]@{ Ok = $false; Out = ''; Err = $_.Exception.Message }
    } finally {
        $ErrorActionPreference = $previous
    }

    $errors = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    $output = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
    return [pscustomobject]@{
        Ok  = ($code -eq 0)
        Out = ([string]($output -join "`n")).Trim()
        Err = ([string]($errors -join "`n")).Trim()
    }
}

# A control states, before it runs, the reading that proves it ran. The receipt carries both the
# expectation and what came back, so a reader never has to trust the verdict on its own. A check
# with no reading that could contradict it is not a check.
function New-Control {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Expected,
        [string]$Reading,
        [bool]$Proved,
        [string]$Detail = ''
    )
    return [pscustomobject]@{
        name     = $Name
        command  = $Command
        expected = $Expected
        reading  = if ($Reading) { $Reading } else { '(empty)' }
        proved   = $Proved
        detail   = $Detail
    }
}

# ProcessStartInfo.ArgumentList, not Start-Process -ArgumentList. The second joins an array with
# spaces and quotes nothing, so a briefing path or a note containing a space arrives at the child as
# two arguments. The .NET collection escapes each element for the platform it is on, which this has
# to be right about on Windows and Linux both.
function Start-Child {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        # Capture the child's output instead of letting it reach our stdout. Required for anything
        # chatty, or -Json emits a receipt with another script's console noise in the middle of it.
        [switch]$Quiet,
        [switch]$Wait
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add([string]$a) }
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    if ($Quiet) {
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($Quiet) {
        # Drain both pipes before waiting. A child that fills a pipe buffer while the parent waits on
        # exit deadlocks, and claim.ps1 prints a block of text on every path.
        $null = $proc.StandardOutput.ReadToEndAsync()
        $null = $proc.StandardError.ReadToEndAsync()
    }
    if ($Wait) { $proc.WaitForExit() }
    return $proc
}

# The interpreter running this file, so a child pwsh cannot be a different build from its parent.
function Get-SelfInterpreter {
    try {
        $path = (Get-Process -Id $PID -ErrorAction Stop).Path
        if ($path) { return $path }
    } catch { }
    return (Join-Path $PSHOME ($(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })))
}

# ------------------------------------------------------------------------------------------------
# What we are pointed at, and who said so
# ------------------------------------------------------------------------------------------------

if (-not $RepoRoot) {
    $RepoRoot = Invoke-CcxGit -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
}
if (-not $RepoRoot) { throw "Not inside a git repository, and no -RepoRoot was given." }

# Get-CcxConfig materialises a FIXED set of keys and drops the rest, so a ciRed block would not
# survive it. Teaching it a new key is scripts/coord's business, not this file's, so read the raw
# document for the adapter block and leave the shared loader alone.
function Get-CiRedConfig {
    [CmdletBinding()]
    param([string]$From)
    $path = Find-CcxConfigPath -From $From
    if (-not $path) { return $null }
    try {
        $doc = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw "ccx.config.json at '$path' could not be read as JSON: $($_.Exception.Message)"
    }
    if ($null -eq $doc -or -not ($doc.PSObject.Properties.Name -contains 'ciRed')) { return $null }
    return $doc.ciRed
}

$ciRed = Get-CiRedConfig -From $RepoRoot

# Every setting reports where it came from. A built-in default and a configured value that happen to
# match are the same string, and only one of them means the consumer agreed to the contract.
function Resolve-Setting {
    [CmdletBinding()]
    param($Override, $FromConfig, $Fallback, [string]$ConfigName, [string]$FallbackName = 'built-in default')
    if ($Override) { return @{ value = $Override; source = 'command line' } }
    if ($null -ne $FromConfig -and "$FromConfig") {
        return @{ value = $FromConfig; source = "ccx.config.json $ConfigName" }
    }
    return @{ value = $Fallback; source = $FallbackName }
}

$labelPick = Resolve-Setting $Label $ciRed.label 'ci-red' 'ciRed.label'
$label = [string]$labelPick.value

$prefixPick = Resolve-Setting $ClaimPrefix $ciRed.claimPrefix 'ci-red-pr' 'ciRed.claimPrefix'
$claimPrefix = [string]$prefixPick.value

# The remote is the last resort rather than the first, so a clone that watches a repository it is
# not itself a clone of stays configurable.
$remoteRepo = $null
$remoteUrl = Invoke-CcxGit -Repo $RepoRoot -Arguments @('remote', 'get-url', 'origin')
if ($remoteUrl -and $remoteUrl -match '(?:github\.com[:/])([^/]+)/(.+?)(?:\.git)?$') {
    $remoteRepo = "$($Matches[1])/$($Matches[2])"
}
$repoPick = Resolve-Setting $Repo $ciRed.repo $remoteRepo 'ciRed.repo' 'origin remote'
$repoName = [string]$repoPick.value

$spawnPick = Resolve-Setting $SpawnCommand $ciRed.spawn.command 'claude' 'ciRed.spawn.command'
$spawnCmd = [string]$spawnPick.value
$spawnFixed = if ($SpawnArgs) { @($SpawnArgs) }
elseif ($null -ne $ciRed -and $null -ne $ciRed.spawn -and $null -ne $ciRed.spawn.args) { @($ciRed.spawn.args) }
else { @('-p') }

$receipt = [ordered]@{
    status   = 'OK'
    reason   = ''
    scanned  = [ordered]@{
        repo              = $repoName
        repoSource        = $repoPick.source
        label             = $label
        labelSource       = $labelPick.source
        claimPrefix       = $claimPrefix
        claimPrefixSource = $prefixPick.source
        spawnCommand      = $spawnCmd
        spawnCommandSource = $spawnPick.source
        gh                = $Gh
        repoRoot          = $RepoRoot
        query             = ''
        openPullRequests  = $null
        labelled          = $null
        truncated         = $false
        dryRun            = [bool]$DryRun
    }
    controls = @()
    red      = @()
}

function Write-Receipt {
    [CmdletBinding()]
    param([int]$Code)
    if ($Json) {
        $receipt | ConvertTo-Json -Depth 8
        exit $Code
    }
    $s = $receipt.scanned
    $colour = switch ($receipt.status) { 'OK' { 'Green' } 'INCOMPLETE' { 'Yellow' } default { 'Red' } }
    $open = if ($null -eq $s.openPullRequests) { 'an unknown number of' } else { $s.openPullRequests }
    $carry = if ($null -eq $s.labelled) { 'unknown' } else { $s.labelled }
    Write-Host ''
    Write-Host "ci-red watch: $($receipt.status)" -ForegroundColor $colour
    if ($receipt.reason) { Write-Host "  reason : $($receipt.reason)" }
    Write-Host "  scanned: repo $($s.repo) (from $($s.repoSource)); label '$($s.label)' (from $($s.labelSource))"
    Write-Host "           $open open pull requests examined, $carry carry the label"
    if ($s.truncated) { Write-Host "           WARNING: a list filled the -Limit of $Limit, so these counts may be short" }
    if ($s.query) { Write-Host "           $($s.query)" }
    foreach ($c in $receipt.controls) {
        $verdict = if ($c.proved) { 'proved' } else { 'NOT PROVED' }
        Write-Host "  control: $($c.name) -- $verdict (expected '$($c.expected)', read '$($c.reading)')"
        if ($c.detail) { Write-Host "           $($c.detail)" }
    }
    foreach ($r in $receipt.red) {
        Write-Host "  red    : #$($r.number) $($r.decision) -- $($r.title)"
        if ($r.detail) { Write-Host "           $($r.detail)" }
    }
    if (-not $receipt.red) {
        # "none" under a refusal is the all-clear this script exists to refuse to print. The status
        # line already says CANNOT-LOOK, and a reader who skims to the last line must not be handed
        # a word that answers the question the run could not answer.
        Write-Host $(if ($receipt.status -eq 'OK') { "  red    : none" } else { "  red    : NOT DETERMINED" })
    }
    Write-Host ''
    exit $Code
}

# The wording is the fourth property, and it is deliberate: this is never "nothing is wrong".
function Stop-CannotLook {
    [CmdletBinding()]
    param([string]$Reason)
    $receipt.status = 'CANNOT-LOOK'
    $receipt.reason = $Reason
    Write-Receipt $EXIT_REFUSED
}

if (-not $repoName) {
    Stop-CannotLook ("No repository to poll. Set ciRed.repo in ccx.config.json, pass -Repo, or give " +
        "this clone an origin remote on github.com.")
}

# ------------------------------------------------------------------------------------------------
# Controls. Each must read back something specific, or the run refuses to report a count.
# ------------------------------------------------------------------------------------------------

$probe = Invoke-Gh -Arguments @('api', "repos/$repoName", '--jq', '.full_name')
$reachable = ($probe.Ok -and $probe.Out -and $probe.Out.Trim().ToLowerInvariant() -eq $repoName.ToLowerInvariant())
$receipt.controls += New-Control -Name 'repository reachable' `
    -Command "$Gh api repos/$repoName --jq .full_name" `
    -Expected $repoName -Reading $probe.Out -Proved $reachable `
    -Detail $(if ($reachable) { '' } else { "the client said: $($probe.Err)" })
if (-not $reachable) {
    Stop-CannotLook ("Could not confirm '$repoName' exists and is readable. A wrong name, a missing " +
        "login, and no client on PATH all return nothing here, and none of them mean the repository " +
        "is green.")
}

# WITHOUT THIS CONTROL, a contract nobody installed reads exactly like a repository with nothing
# red. The consumer has to create the label for the signal to exist at all, and a query for a label
# nobody created returns an empty list and exits 0.
$labelProbe = Invoke-Gh -Arguments @(
    'api', "repos/$repoName/labels/$([uri]::EscapeDataString($label))", '--jq', '.name')
$labelExists = ($labelProbe.Ok -and $labelProbe.Out -and $labelProbe.Out.Trim() -eq $label)
$receipt.controls += New-Control -Name 'label exists on the consumer' `
    -Command "$Gh api repos/$repoName/labels/$label --jq .name" `
    -Expected $label -Reading $labelProbe.Out -Proved $labelExists `
    -Detail $(if ($labelExists) { '' } else { "the client said: $($labelProbe.Err)" })
if (-not $labelExists) {
    Stop-CannotLook ("The label '$label' does not exist on $repoName, so no pull request can carry " +
        "it and an empty result proves nothing. Either the consuming repository has not installed " +
        "the labelling half, or ciRed.label names a label nobody applies.")
}

# The population. It is the denominator every finding is printed against, and for a run that finds
# nothing it is the control: if the open list cannot be read, "no pull request is red" is a guess.
$openProbe = Invoke-Gh -Arguments @(
    'pr', 'list', '--repo', $repoName, '--state', 'open', '--json', 'number', '--limit', "$Limit")
$openNumbers = @()
$openOk = $openProbe.Ok
if ($openOk) {
    try { $openNumbers = @(($openProbe.Out | ConvertFrom-Json) | ForEach-Object { [int]$_.number }) }
    catch { $openOk = $false }
}
$receipt.controls += New-Control -Name 'open pull requests readable' `
    -Command "$Gh pr list --repo $repoName --state open --json number" `
    -Expected 'a readable list, of which 0 is a valid length' `
    -Reading $(if ($openOk) { "$($openNumbers.Count) open" } else { '' }) -Proved $openOk `
    -Detail $(if ($openOk) { '' } else { "the client said: $($openProbe.Err)" })
if (-not $openOk) {
    Stop-CannotLook ("The open pull request list could not be read, so the number of pull requests " +
        "examined is unknown and no count taken against it means anything.")
}
$receipt.scanned.openPullRequests = $openNumbers.Count

# THE FINDING. One call, filtered by label on the server, across every open pull request. This is
# the call the whole design exists to make cheap. Everything above and below it is a control or a
# decision.
$receipt.scanned.query = ("$Gh pr list --repo $repoName --state open --label $label " +
    "--json number,title,url,headRefName --limit $Limit")
$find = Invoke-Gh -Arguments @('pr', 'list', '--repo', $repoName, '--state', 'open',
    '--label', $label, '--json', 'number,title,url,headRefName', '--limit', "$Limit")
if (-not $find.Ok) {
    Stop-CannotLook "The labelled pull request query failed: $($find.Err)"
}
$labelled = @()
try { $labelled = @($find.Out | ConvertFrom-Json) } catch {
    Stop-CannotLook "The labelled pull request query returned something that is not JSON."
}
$receipt.scanned.labelled = $labelled.Count
# A count read off a capped list is not a census, so say when the cap was reached instead of
# printing a number that looks complete.
$receipt.scanned.truncated = (($openNumbers.Count -ge $Limit) -or ($labelled.Count -ge $Limit))

# ------------------------------------------------------------------------------------------------
# Decide, claim, spawn. Nothing below here runs when nothing is red.
# ------------------------------------------------------------------------------------------------

$stateRoot = Get-CcxStateRoot -Repo $RepoRoot
# 'claims' and the .json suffix are claim.ps1's formula, repeated here because claim.ps1 has no
# "where would this key live" query. The repetition is made safe by the runtime check further down
# rather than by hoping the two copies stay in step.
$claimsDir = Join-Path $stateRoot 'claims'
$journalDir = Join-Path $stateRoot 'ci-red'
$claimScript = Join-Path $PSScriptRoot '../coord/claim.ps1'

function Get-ClaimFile {
    [CmdletBinding()]
    param([string]$Key)
    $safe = ConvertTo-CcxSafeName $Key
    if (-not $safe) { throw "Claim key '$Key' reduces to nothing usable." }
    return (Join-Path $claimsDir "$safe.json")
}

# A fresh session has no memory of the last red, so this journal is the only continuity across
# spawns. It lives under the state root because that is identical across every worktree of the
# clone, isolated per clone, and impossible to sweep into a commit.
function Write-Journal {
    [CmdletBinding()]
    param([int]$Number, [string]$Text)
    New-Item -ItemType Directory -Force -Path $journalDir | Out-Null
    $file = Join-Path $journalDir "pr-$Number.md"
    Add-Content -LiteralPath $file -Value $Text -Encoding utf8
    return $file
}

function New-Briefing {
    [CmdletBinding()]
    param($Pr, [string]$Key)
    return @"

## Red seen $((Get-Date).ToString('o'))

Pull request $($Pr.number) on $repoName carries the label '$label'.
  title  : $($Pr.title)
  url    : $($Pr.url)
  branch : $($Pr.headRefName)
  claim  : $Key -- held for you, and yours to release when you are done

You are the attributing seat for this red. Your job is to say WHOSE failure it is, not to fix
whatever broke. A red belongs to one of four places, and only the first is a builder's to fix:

  1. The pull request. Its own change broke the check.
  2. The trunk. The check fails on the base branch too, so every pull request shows it.
  3. A flake. The same commit passes on a re-run with no change in between.
  4. The merge queue. The combination broke, not either change on its own.

Sending all four back to a builder is the failure you exist to prevent.

You start with no memory of the last red on this pull request. Read the entries above this one
before you decide anything, and append what you found below before you finish. This file is the
only thing that survives you.

When you are done:
  pwsh -NoProfile -File scripts/coord/claim.ps1 -Release $Key

"@
}

$failedCount = 0

if ($labelled.Count -eq 0) {
    Write-Receipt $EXIT_OK
}

# ONE LOCK AROUND THE WHOLE PASS. claim.ps1 stops a PEER worktree taking a key we hold; it cannot
# stop THIS watcher's next tick, because re-taking your own claim is a documented success. Every
# tick runs from the same worktree, so without this lock two overlapping ticks would both pass the
# claim step and both start a seat.
$lock = Enter-CcxLock -Name 'ci-red-watch' -TimeoutSeconds $LockTimeoutSeconds -Repo $RepoRoot
try {
    foreach ($pr in $labelled) {
        $number = [int]$pr.number
        $key = "$claimPrefix-$number"
        $row = [ordered]@{
            number   = $number
            title    = [string]$pr.title
            url      = [string]$pr.url
            branch   = [string]$pr.headRefName
            claim    = $key
            decision = ''
            detail   = ''
        }

        # The per-finding control on the label query: a pull request it names must also appear in
        # the independently fetched open list. LIMIT, stated because it is real: a pull request that
        # closes between the two calls lands here legitimately, which is why this downgrades one
        # finding instead of failing the run.
        if ($openNumbers -notcontains $number) {
            $row.decision = 'NOT-OPEN'
            $row.detail = ('Carries the label but is absent from the open pull request list. ' +
                'Closed since the first call, or the two calls disagree.')
            $receipt.red += [pscustomobject]$row
            continue
        }

        if ($DryRun) {
            $row.decision = 'DRY-RUN'
            $row.detail = "Would claim '$key' and start a seat."
            $receipt.red += [pscustomobject]$row
            continue
        }

        $claimFile = Get-ClaimFile $key
        if (Test-Path -LiteralPath $claimFile) {
            $holder = '(unreadable)'
            try {
                $held = Get-Content -LiteralPath $claimFile -Raw | ConvertFrom-Json
                $holder = "$($held.worktree) [$($held.branch)]"
            } catch { }
            $row.decision = 'ALREADY-CLAIMED'
            $row.detail = "Held by $holder. Two seats attributing one failure is worse than none."
            $receipt.red += [pscustomobject]$row
            continue
        }

        $claimProc = Start-Child -FileName (Get-SelfInterpreter) -WorkingDirectory $RepoRoot -Quiet -Wait `
            -ArgumentList @('-NoProfile', '-File', $claimScript, '-Take', $key,
                '-Note', "ci-red on $repoName pull request $number")
        if ($claimProc.ExitCode -ne 0) {
            # A peer took it in the instant between our existence check and our -Take. The exclusive
            # create is what caught it, and skipping is the right answer.
            $row.decision = 'ALREADY-CLAIMED'
            $row.detail = "claim.ps1 refused the key (exit $($claimProc.ExitCode)); a peer session holds it."
            $receipt.red += [pscustomobject]$row
            continue
        }

        if (-not (Test-Path -LiteralPath $claimFile)) {
            # claim.ps1 reported success and the file this script predicted is not there, so the two
            # path formulas have drifted. Starting a seat now would start one on every future tick,
            # because the existence check above would never see a claim either.
            $row.decision = 'CLAIM-UNVERIFIABLE'
            $row.detail = ("claim.ps1 exited 0 but '$claimFile' does not exist, so the claim path in " +
                "this script no longer matches claim.ps1. Not starting a seat.")
            $receipt.red += [pscustomobject]$row
            $receipt.status = 'CANNOT-LOOK'
            $receipt.reason = 'The claim registry path could not be confirmed, so a claim cannot be seen once taken.'
            $failedCount++
            continue
        }

        $journal = Write-Journal -Number $number -Text (New-Briefing -Pr $pr -Key $key)
        $prompt = ("You are the attributing seat for a red required check. Read '$journal'. It is " +
            "your only memory of this pull request. Follow the instructions in its last entry, and " +
            "append what you find to the same file before you finish.")

        try {
            $started = Start-Child -FileName $spawnCmd -WorkingDirectory $RepoRoot `
                -ArgumentList (@($spawnFixed) + @($prompt)) -Wait:$WaitForSpawn
            $row.decision = 'SPAWNED'
            $row.detail = "pid $($started.Id), journal $journal"
        } catch {
            # RELEASE ON FAILURE. A claim taken for a seat that never started marks the red as
            # handled by nobody, and claims do not expire -- so the red would sit unattributed
            # forever, which is the exact failure this watcher exists to end.
            $null = Start-Child -FileName (Get-SelfInterpreter) -WorkingDirectory $RepoRoot -Quiet -Wait `
                -ArgumentList @('-NoProfile', '-File', $claimScript, '-Release', $key)
            $row.decision = 'SPAWN-FAILED'
            $row.detail = "$($_.Exception.Message) -- claim '$key' released so the next tick retries."
            $failedCount++
        }
        $receipt.red += [pscustomobject]$row
    }
} finally {
    Exit-CcxLock $lock
}

if ($receipt.status -eq 'CANNOT-LOOK') { Write-Receipt $EXIT_REFUSED }
if ($failedCount -gt 0) {
    $receipt.status = 'INCOMPLETE'
    $receipt.reason = "$failedCount red pull request(s) could not be handed to a seat."
    Write-Receipt $EXIT_FAILED
}
Write-Receipt $EXIT_OK
