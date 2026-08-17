#Requires -Version 7.3
<#
.SYNOPSIS
    Prove -- by receipt and by attack -- that every ccx control is installed, wired, and able to
    refuse the case it exists to refuse. Run this first, and after every install.

.DESCRIPTION
    THE PROBLEM THIS COMMAND EXISTS FOR. Every failure mode in this system is byte-identical to
    success, and a stranger who has just cloned the repository starts in exactly that state. Run an
    installer (or none), open a session, and you get a banner, a status message on every prompt, and
    green output -- with zero enforcement. That is not hypothetical:

      * an announce hook sat wired-but-resolving-nothing for hours while the settings file looked
        correct, because a similarly-named entry from another project occupied the slot;
      * a gate had dozens of green tests, every one of them binding the repository's copy of the
        script while enforcement ran from a stale installed copy;
      * the installers deliberately write SHIMS that re-resolve at run time, so a shim pointing at a
        script that does not exist is indistinguishable from a healthy hook with nothing to say.

    So this command never infers. It does four things, in this order:

      1  ENUMERATE EVERY CONTROL BY RECEIPT. Hash each installed copy against this checkout's source
         (stale-copy detection), read the live matchers out of every config root, and DIFF the wired
         matchers against the rules the INSTALLED script actually implements. That diff is the
         dead-rule tripwire: a rule can exist in source, be declared by an installer and be covered
         by tests, while the copy that runs has never heard of it -- or while no matcher ever invokes
         it.

      2  FIRE EACH CONTROL ON PURPOSE AND REQUIRE IT TO DENY. Crafted PreToolUse JSON is piped at the
         INSTALLED gate; a blanket stage is attempted; a commit claiming an unclaimed item is
         attempted; a push to a protected ref is attempted; a drifted throwaway primary is put in
         front of the SessionStart backstop. A control that does not refuse a case it is supposed to
         refuse is RED. Every attack is paired with a NEGATIVE control -- an ordinary action the same
         control must ALLOW, or in the backstop's case the drifted-BUT-DIRTY primary it must decline
         to touch -- because a script that refuses everything is not a working guard either, and a
         probe with no positive control proves nothing. The one check with no allow/deny axis at all
         is the allocator: it decides nothing, so what is paired with it instead is the property that
         CAN be violated -- that its read-only floor inspection spends no number and moves no ratchet.

      3  PRINT WHAT IT SCANNED, ALWAYS. Config roots found, session records read, records that could
         not be placed, worktrees enumerated, which python. A SKIP MUST NEVER READ AS A PASS, so a
         check that could not run is reported '??' and the exit code says so.

      4  NAME ITS OWN BLIND SPOTS ON EVERY RUN. What this command cannot see is printed whether or
         not anything failed.

    NOTHING HERE MUTATES YOUR REPOSITORY. The attacks run against a throwaway fixture in the temp
    directory (its own git repositories, its own allowlist, its own state root), which is deleted on
    the way out. The one exception is read-only: a live-governance probe fires the gate at the real
    primary's path, which the gate answers by comparing strings -- no file is written.

.PARAMETER Repo
    Checkout to examine -- the repository whose governance this report is about. Defaults to the
    current directory's repository, which is NOT necessarily the one you meant: run this from the
    tooling checkout and every line below is about the tooling checkout. The sources that installed
    copies are hashed against always come from this script's own checkout, whatever -Repo says. Both
    roots are printed under WHAT WAS SCANNED for that reason.

.PARAMETER ConfigDir
    Client config directories to read wiring from. Defaults to ~/.claude plus every
    ~/.claude-account-* that carries a marker the client writes (`projects/`, `sessions/` or
    `.claude.json`) -- the bare glob also matches a launcher's `.lock` artefact, which is a directory
    and against which this command duly charged a required failure. Rejected candidates are listed
    under WHAT WAS SCANNED with the reason. Passing this bypasses the test.

.PARAMETER SettingsPath
    The user-scope settings file the coordination installer writes. Defaults to
    <first config dir>/settings.json.

.PARAMETER Json
    Emit a machine-readable report on stdout and nothing else.

.PARAMETER SkipAttacks
    Do not fire anything. Every attack is then reported '??', so the run CANNOT exit 0 -- because a
    control that was not tested is not a control that passed. It exits 2, or 1 if a receipt check
    also found something broken or absent.

.OUTPUTS
    Exit 0  every required control INSTALLED + WIRED, and every attack DENIED.
    Exit 1  at least one RED, or at least one REQUIRED control OFF.
    Exit 2  at least one check could not be determined (and nothing above). This command refuses to guess.

.EXAMPLE
    pwsh -NoProfile -File bin/ccx-doctor.ps1 -Repo <the-repo-you-governed>
    pwsh -NoProfile -File bin/ccx-doctor.ps1 -Repo <path> -Verbose
    pwsh -NoProfile -File bin/ccx-doctor.ps1 -Json
#>
[CmdletBinding()]
param(
    [string]$Repo,
    [string[]]$ConfigDir,
    [string]$SettingsPath,
    [switch]$Json,
    [switch]$SkipAttacks,
    [int]$AttackTimeoutSeconds = 90
)

# NOT 'Stop'. This command's whole job is to report bad states, so a bad state must never become an
# unhandled terminating error that prints a stack trace instead of a verdict. Every step that can
# fail is individually guarded and turned into a '??' result.
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

$DoctorVersion = 1
$RepoSrcRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# ==================================================================================================
# Output plumbing
#
# COLOUR-FREE BY DEFAULT, deliberately: this output is read in transcripts and pasted into issues at
# least as often as it is read on a terminal, and an escape sequence there is noise. Status is
# carried by a four-character tag, which survives copy-paste.
# ==================================================================================================

$script:Lines = [System.Collections.Generic.List[string]]::new()

function Say {
    param([string]$Text = '')
    $script:Lines.Add($Text)
    if (-not $Json) { [Console]::Out.WriteLine($Text) }
}

# ------------------------------------------------------------------------------------------------
# The result ledger.
#
# STATUS VOCABULARY, and the contract the exit code implements:
#   OK    proven: installed, wired, and (where attackable) it refused what it must refuse.
#   RED   proven broken: wired but stale/unloadable, or it allowed something it must deny, or it
#         denied something it must allow. Drives exit 1.
#   OFF   implemented, but nothing invokes it -- zero enforcement. Drives exit 1 when the control has
#         a shipped installer; reported only when the control is opt-in by design.
#   ??    could not be determined. Drives exit 2. A skip is never a pass.
#   --    not applicable here (no sequences configured, an opt-in rule left off on purpose).
# ------------------------------------------------------------------------------------------------
$script:Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][ValidateSet('control', 'attack', 'probe')][string]$Kind,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('OK', 'RED', 'OFF', '??', '--')][string]$Status,
        [string]$Detail = '',
        [string[]]$Evidence = @(),
        # Does an OFF here mean the machine has no enforcement it was promised? True for every control
        # with a shipped installer. False for the opt-in ones, where absence is a choice.
        [bool]$Required = $true
    )
    $script:Results.Add([pscustomobject]@{
            kind     = $Kind
            id       = $Id
            name     = $Name
            status   = $Status
            detail   = $Detail
            evidence = @($Evidence)
            required = $Required
        })
    Say ("  [{0,-3}] {1,-34} {2}" -f $Status, $Name, $Detail)
    # Under -Verbose the evidence is printed INLINE, not only on the verbose stream. A reader asking
    # for detail wants it beside the finding it supports, and a verbose record merged into another
    # stream loses its tag the moment a transcript is piped anywhere.
    # Printed once, here -- NOT also through Write-Verbose. The verbose stream is coloured by the host
    # and duplicating every line would double the transcript and undo the colour-free default.
    if ($VerbosePreference -ne 'SilentlyContinue') {
        foreach ($e in $Evidence) { Say ("          | {0}" -f $e) }
    }
}

$script:BlindSpots = [System.Collections.Generic.List[string]]::new()
function Add-BlindSpot { param([string]$Text) $script:BlindSpots.Add($Text) }

function Stop-Undetermined {
    # Exit 2 with a reason. Used only where NOTHING can be concluded -- not inside a repository, no
    # configuration, no substrate. Refusing beats guessing.
    param([string]$Why, [string]$Fix = '')
    Say ''
    Say "ccx doctor: CANNOT DETERMINE ANYTHING -- $Why"
    if ($Fix) { Say "  $Fix" }
    if ($Json) {
        [Console]::Out.WriteLine((@{
                    tool = 'ccx-doctor'; version = $DoctorVersion; exitCode = 2
                    undetermined = $Why; results = @(); blindSpots = @()
                } | ConvertTo-Json -Depth 6))
    }
    exit 2
}

# ==================================================================================================
# Substrate
# ==================================================================================================

try {
    . (Join-Path $RepoSrcRoot 'scripts/coord/_common.ps1')
} catch {
    Stop-Undetermined "could not load scripts/coord/_common.ps1 from $RepoSrcRoot ($($_.Exception.Message))" `
        'Run this from a complete checkout -- the doctor shares the same substrate as the controls it audits.'
}
try {
    . (Join-Path $RepoSrcRoot 'scripts/coord/occupancy.ps1')
} catch {
    # Non-fatal: it only costs us the session-record census, which is reported as unavailable below.
    Write-Verbose "occupancy.ps1 did not load: $($_.Exception.Message)"
}

function Get-FileSha {
    param([string]$Path)
    if (-not $Path) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return $null }
}

function Get-ShaTag {
    param([string]$Sha)
    if ($Sha) { return $Sha.Substring(0, 12) }
    return '(none)'
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop) }
    catch {
        # UNREADABLE IS NOT ABSENT, and must never be reported as absent.
        return @{ __unreadable = $true; __error = $_.Exception.Message }
    }
}

function Get-HookRows {
    # Every hook entry for one event, flattened to matcher + command. Returns @() for a missing file,
    # a missing event, or an unreadable settings file -- the caller distinguishes those itself.
    param($Settings, [string]$EventName)
    $rows = @()
    if (-not $Settings -or $Settings.__unreadable) { return $rows }
    if (-not $Settings.hooks) { return $rows }
    foreach ($group in @($Settings.hooks[$EventName])) {
        if (-not $group) { continue }
        foreach ($h in @($group.hooks)) {
            $rows += [pscustomobject]@{ Matcher = "$($group.matcher)"; Command = "$($h.command)" }
        }
    }
    return $rows
}

# ==================================================================================================
# Probe runner
#
# A control is established by DRIVING INPUT INTO THE INSTALLED COPY and reading what comes back --
# never by reading the source and reasoning about it. ProcessStartInfo rather than a pipeline so the
# working directory, the environment and stdin are all stated explicitly, and stdout/stderr/exit code
# come back separately: a gate's verdict is on stdout, its receipts are on stderr, and conflating
# them is how "the gate could not load" reads as "the gate had nothing to say".
# ==================================================================================================

$script:PwshPath = $null
try { $script:PwshPath = [Environment]::ProcessPath } catch { }
if (-not $script:PwshPath -or -not (Test-Path -LiteralPath $script:PwshPath)) {
    $script:PwshPath = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$Stdin = '',
        [string]$WorkingDirectory,
        # $null as a value REMOVES the variable from the child's environment. Used to prove a guard
        # refuses on its own merits rather than because an escape hatch happened to be unset.
        [hashtable]$Environment,
        [int]$TimeoutSeconds = 60
    )
    $result = [ordered]@{ Ran = $false; ExitCode = $null; StdOut = ''; StdErr = ''; Error = '' }
    if (-not $FilePath -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        $result.Error = "no such file: $FilePath"
        return [pscustomobject]$result
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        foreach ($a in $ArgumentList) { $null = $psi.ArgumentList.Add([string]$a) }
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
        if ($Environment) {
            foreach ($k in $Environment.Keys) {
                $v = $Environment[$k]
                if ($null -eq $v) { $null = $psi.Environment.Remove($k) } else { $psi.Environment[$k] = [string]$v }
            }
        }
        $proc = [System.Diagnostics.Process]::Start($psi)
        # Read both streams asynchronously BEFORE waiting: a child that fills one pipe's buffer while
        # we block on the other deadlocks, and a deadlocked probe is a doctor that hangs forever on
        # exactly the broken control it was run to find.
        $so = $proc.StandardOutput.ReadToEndAsync()
        $se = $proc.StandardError.ReadToEndAsync()
        try { $proc.StandardInput.Write($Stdin) } catch { }
        try { $proc.StandardInput.Close() } catch { }
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill($true) } catch { }
            $result.Error = "timed out after ${TimeoutSeconds}s"
            return [pscustomobject]$result
        }
        $result.Ran = $true
        $result.ExitCode = $proc.ExitCode
        $result.StdOut = [string]$so.GetAwaiter().GetResult()
        $result.StdErr = [string]$se.GetAwaiter().GetResult()
    } catch {
        $result.Error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Invoke-PwshProbe {
    param(
        [Parameter(Mandatory)][string]$Script,
        [string[]]$ScriptArgs = @(),
        [string]$Stdin = '',
        [string]$WorkingDirectory,
        [hashtable]$Environment,
        [int]$TimeoutSeconds = 60
    )
    if (-not $script:PwshPath) {
        return [pscustomobject]@{ Ran = $false; ExitCode = $null; StdOut = ''; StdErr = ''; Error = 'no pwsh executable could be located' }
    }
    $argv = @('-NoProfile', '-NonInteractive', '-File', $Script) + @($ScriptArgs)
    return Invoke-Probe -FilePath $script:PwshPath -ArgumentList $argv -Stdin $Stdin `
        -WorkingDirectory $WorkingDirectory -Environment $Environment -TimeoutSeconds $TimeoutSeconds
}

function Get-HookVerdict {
    # What a PreToolUse hook actually said. A deny is stdout JSON carrying
    # hookSpecificOutput.permissionDecision = 'deny' -- NOT an exit code: these hooks exit 0 whatever
    # they decide, so reading the exit code would report every deny as an allow.
    #
    # 'silent' and 'allow' are the same bytes and are reported as the same verdict on purpose: that
    # identity is the defect the whole command exists to expose, so it must not be papered over here.
    param([string]$StdOut)
    $out = [pscustomobject]@{ Verdict = 'allow'; Reason = ''; Context = ''; Parsed = $false }
    $text = "$StdOut".Trim()
    if (-not $text) { return $out }
    $obj = $null
    try { $obj = $text | ConvertFrom-Json -ErrorAction Stop } catch { $out.Verdict = 'unparseable'; return $out }
    $out.Parsed = $true
    $hso = $obj.hookSpecificOutput
    if (-not $hso) { $out.Verdict = 'no-wrapper'; return $out }
    if ("$($hso.permissionDecision)" -eq 'deny') {
        $out.Verdict = 'deny'
        $out.Reason = "$($hso.permissionDecisionReason)"
        return $out
    }
    if ($hso.additionalContext) {
        $out.Verdict = 'context'
        $out.Context = "$($hso.additionalContext)"
    }
    return $out
}

function Get-FirstLine {
    param([string]$Text, [int]$Cap = 140)
    $t = (("$Text" -replace '[\r\n\t]+', ' ') -replace '\s+', ' ').Trim()
    if ($t.Length -gt $Cap) { return $t.Substring(0, $Cap - 3) + '...' }
    return $t
}

# ==================================================================================================
# 1. WHAT WAS SCANNED
# ==================================================================================================

Say ''
Say 'ccx doctor -- prove the controls; do not assume them'
Say '===================================================='

$here = if ($Repo) { $Repo } else { $PWD.Path }
$configPath = Find-CcxConfigPath -From $here
if (-not $configPath) {
    Stop-Undetermined "no ccx.config.json at or above '$here'" `
        'That file is the opt-in marker as well as the configuration. Without it every user-scope hook stays inert here, by design.'
}
$cfg = $null
try { $cfg = Get-CcxConfig -From $here -Force } catch {
    Stop-Undetermined "ccx.config.json could not be loaded: $($_.Exception.Message)"
}

$repoRoot = Invoke-CcxGit -Repo $here -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
if (-not $repoRoot) {
    Stop-Undetermined "'$here' is not inside a git repository" 'Every control here is keyed to a checkout.'
}
$primaryRoot = Get-CcxPrimaryRoot -Repo $repoRoot
$commonDir = Get-CcxGitCommonDir -Repo $repoRoot
$stateRoot = $null
try { $stateRoot = Get-CcxStateRoot -Repo $repoRoot -Prefix $cfg.prefix } catch { }
$trunk = $null
try { $trunk = Get-CcxTrunk -Repo $repoRoot } catch { $trunk = $null }

$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
$hooksDir = if ($homeDir) { Join-Path $homeDir '.claude/hooks' } else { $null }

# NOT A BARE GLOB. `.claude-account-*` also matches a launcher's `.lock` artefact, which on a real
# machine is a DIRECTORY -- and this command duly read it as a config root, found no wiring in it (of
# course: nothing wires a lock file) and charged a REQUIRED failure against the machine. A doctor that
# invents a red is worse than one that stays quiet, because the reader who chases it once learns to
# discount the next one. Resolve-CcxClientConfigRoot applies a marker test the CLIENT creates and
# hands back every rejection with its reason; they are printed under WHAT WAS SCANNED below, because a
# candidate that vanished silently reads exactly like one that never existed.
$configScan = Resolve-CcxClientConfigRoot -HomeDirectory $homeDir -Explicit $ConfigDir
$ConfigDir = @($configScan.Roots)
if (-not $SettingsPath) {
    $SettingsPath = if ($ConfigDir.Count -gt 0) { Join-Path $ConfigDir[0] 'settings.json' } else { $null }
}

# The git hooks directory, resolved the way the installer resolves it: core.hooksPath wins, because
# ignoring it means auditing files git will never run.
$gitHooksDir = $null
$hooksPathCfg = Invoke-CcxGit -Repo $repoRoot -Arguments @('config', '--get', 'core.hooksPath')
if ($hooksPathCfg) {
    $gitHooksDir = if ([System.IO.Path]::IsPathRooted($hooksPathCfg)) { $hooksPathCfg } else { Join-Path $repoRoot $hooksPathCfg }
} elseif ($commonDir) {
    $gitHooksDir = Join-Path $commonDir 'hooks'
}

# Which python the git-hook shims would find. The shims fail OPEN with no interpreter, so this single
# fact decides whether both git gates are on or off for every commit and every push.
function Resolve-DoctorPython {
    $cands = @()
    if ($env:CCX_PYTHON) { $cands += [pscustomobject]@{ How = 'CCX_PYTHON'; Path = $env:CCX_PYTHON } }
    foreach ($n in @('python', 'python3')) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { $cands += [pscustomobject]@{ How = "PATH ($n)"; Path = $c.Source } }
    }
    foreach ($c in $cands) {
        # Ask the interpreter; do not trust the lookup. On Windows a `python` on PATH is often an app
        # execution alias that resolves cleanly and then runs nothing -- the instrument answers
        # "found", which is not the question ("will this execute the checker?").
        $r = Invoke-Probe -FilePath $c.Path -ArgumentList @('--version') -TimeoutSeconds 20
        if ($r.Ran -and $r.ExitCode -eq 0) {
            $v = Get-FirstLine ($r.StdOut + ' ' + $r.StdErr) 40
            return [pscustomobject]@{ Path = $c.Path; How = $c.How; Version = $v }
        }
    }
    return $null
}
$python = Resolve-DoctorPython

$gitExe = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

# The session-record census. Reported as counts because a schema change then shows up as a count
# going to zero rather than as a silent all-clear.
$occ = $null
if (Get-Command Get-WorktreeOccupancy -ErrorAction SilentlyContinue) {
    try { $occ = Get-WorktreeOccupancy -Repo $repoRoot -ConfigRoot $ConfigDir } catch { $occ = $null }
}
$worktrees = @()
$porc = Invoke-CcxGit -Repo $repoRoot -Arguments @('worktree', 'list', '--porcelain')
if ($porc) { $worktrees = @(($porc -split "`r?`n") | Where-Object { $_ -match '^worktree\s' } | ForEach-Object { ($_ -replace '^worktree\s+', '').Trim() }) }

# WHICH REPOSITORY IS THIS REPORT ABOUT? It is the first question a reader has, and the only wrong
# answer is a confident one, so both roots are printed and the self-audit case is called out by name.
# This command reads its SOURCES from its own checkout and its GOVERNANCE from -Repo (default: the
# directory you ran it from) -- run it from the tooling checkout and it will happily produce a long,
# mostly-plausible report about the tooling checkout.
$srcCommonDir = Get-CcxGitCommonDir -Repo $RepoSrcRoot
$examiningSelf = ($srcCommonDir -and $commonDir -and
    (ConvertTo-CcxComparablePath -Path $srcCommonDir) -eq (ConvertTo-CcxComparablePath -Path $commonDir))

Say ''
Say 'WHAT WAS SCANNED'
Say "  repo examined    : $repoRoot   $(if ($Repo) { '(-Repo)' } else { '(no -Repo: the directory this was run from)' })"
Say "  tooling checkout : $RepoSrcRoot   (every source hash below is read from here)"
if ($examiningSelf) {
    Say '                     ^ SAME CLONE: the tooling and the repository under test are one'
    Say '                       checkout. Expected if you vendored these scripts into the repo they'
    Say '                       govern; a mistake if you meant to examine a different repository,'
    Say '                       in which case re-run with -Repo <that path>.'
}
Say "  primary checkout : $(if ($primaryRoot) { $primaryRoot } else { '(could not resolve)' })"
Say "  worktrees        : $($worktrees.Count) enumerated"
Say "  config file      : $($cfg.ConfigPath)  prefix=$($cfg.prefix)  layout=$($cfg.worktreeLayout)"
Say "  sequences        : $(if ($cfg.sequences.Count -gt 0) { (@($cfg.sequences.Keys | Sort-Object) -join ', ') } else { '(none configured -- the sequence machinery is off)' })"
Say "  trunk            : $(if ($trunk) { $trunk } else { 'UNRESOLVED' })"
Say "  state root       : $(if ($stateRoot) { $stateRoot } else { 'UNRESOLVED' })"
Say "  git hooks dir    : $(if ($gitHooksDir) { $gitHooksDir } else { 'UNRESOLVED' })$(if ($hooksPathCfg) { '  (core.hooksPath)' })"
Say "  client hooks dir : $(if ($hooksDir) { $hooksDir } else { 'UNRESOLVED' })"
Say "  config roots     : $($ConfigDir.Count) found"
foreach ($cd in $ConfigDir) { Say "                     $cd" }
Say "  config roots skipped : $(@($configScan.Skipped).Count)  (name-matched a config root but is not one)"
foreach ($s in @($configScan.Skipped)) { Say "                     $($s.Path)  --  $($s.Reason)" }
if ($occ) {
    Say "  session records  : $($occ.RecordsExamined) read, $($occ.RecordsUnplaceable) unplaceable, across $($occ.RootsExamined) root(s) with a registry"
    if (-not $occ.Available) {
        Say "                     ROSTER UNAVAILABLE -- $($occ.Detail)"
        Say "                     An empty roster here is NOT 'nobody is live'. Nothing was measured."
    }
    foreach ($u in @($occ.UnplaceableFiles)) { Say "                     unplaceable: $u" }
} else {
    Say '  session records  : NOT READ (the occupancy substrate did not load)'
}
Say "  python           : $(if ($python) { "$($python.Path)  [$($python.How)]  $($python.Version)" } else { 'NONE FOUND -- both git gates fail OPEN, i.e. they are OFF' })"
Say "  git              : $(if ($gitExe) { $gitExe } else { 'NOT ON PATH' })"
Say "  platform         : $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()) / PowerShell $($PSVersionTable.PSVersion)"
Say "  running inside a session : $(if ($env:CLAUDECODE -eq '1') { 'YES (installers refuse here; auditing is allowed)' } else { 'no' })"

# ==================================================================================================
# 2. CONTROLS, BY RECEIPT
# ==================================================================================================

Say ''
Say 'CONTROLS (by receipt: hashes on disk, matchers in the live settings -- never inference)'

# --------------------------------------------------------------------------------- worktree gate --
$gateSrc = Join-Path $RepoSrcRoot 'scripts/hooks/worktree_gate.ps1'
$gateDst = if ($hooksDir) { Join-Path $hooksDir 'worktree_gate.ps1' } else { $null }
$reposFile = if ($hooksDir) { Join-Path $hooksDir 'ccx-gate.repos.txt' } else { $null }
$gateSrcSha = Get-FileSha $gateSrc
$gateDstSha = Get-FileSha $gateDst

# The allowlist IS the kill switch: no file, no entries, nothing governed.
$governed = @()
if ($reposFile -and (Test-Path -LiteralPath $reposFile)) {
    $governed = @(Get-Content -LiteralPath $reposFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object { $_.Trim() })
}
$primaryGoverned = $false
if ($primaryRoot) {
    $pc = ConvertTo-CcxComparablePath -Path $primaryRoot
    foreach ($g in $governed) { if ((ConvertTo-CcxComparablePath -Path $g) -eq $pc) { $primaryGoverned = $true; break } }
}

if (-not $gateDstSha) {
    Add-Result -Kind control -Id gate.installed -Name 'worktree gate: installed' -Status OFF `
        -Detail "NOT INSTALLED at $gateDst -- nothing is gating writes to the primary" `
        -Evidence @("source sha $(Get-ShaTag $gateSrcSha)")
} elseif ($gateDstSha -eq $gateSrcSha) {
    Add-Result -Kind control -Id gate.installed -Name 'worktree gate: installed' -Status OK `
        -Detail "sha $(Get-ShaTag $gateDstSha) == this checkout's source"
} else {
    Add-Result -Kind control -Id gate.installed -Name 'worktree gate: installed' -Status RED `
        -Detail "STALE: installed $(Get-ShaTag $gateDstSha) != source $(Get-ShaTag $gateSrcSha). The running gate is not the code you are reading." `
        -Evidence @("installed: $gateDst", "source: $gateSrc",
        'Re-run scripts/worktree/install-gate.ps1 from a plain terminal.')
}

# THE GATE DOES NOT SHIP ALONE. It dot-sources three helpers and, if any is missing, exits 0 after
# writing a receipt to stderr -- fail-open, i.e. NOT ENFORCING, while every file the installer talks
# about is still present and still looks installed.
if ($gateDstSha) {
    # Ask the INSTALLED file what it depends on; do not assert what the SOURCE depends on. A stale
    # installed copy may predate the split into helpers and need none of them, and reporting it broken
    # because this checkout's gate has helpers would be a confident wrong answer about the one file
    # that is actually running.
    $gateText = "$(Get-Content -LiteralPath $gateDst -Raw -ErrorAction SilentlyContinue)"
    $needed = @(@('_command.ps1', '_gittarget.ps1', '_common.ps1') | Where-Object { $gateText -match [regex]::Escape($_) })
    $missing = @($needed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $hooksDir $_) -PathType Leaf) })
    if ($needed.Count -eq 0) {
        Add-Result -Kind control -Id gate.helpers -Name 'worktree gate: helpers beside it' -Status '--' `
            -Detail 'the installed gate names no helper file -- it is self-contained, or it is not this checkout''s gate'
    } elseif ($missing.Count -eq 0) {
        Add-Result -Kind control -Id gate.helpers -Name 'worktree gate: helpers beside it' -Status OK `
            -Detail "all of $($needed -join ', ') present in $hooksDir"
    } else {
        Add-Result -Kind control -Id gate.helpers -Name 'worktree gate: helpers beside it' -Status RED `
            -Detail "MISSING $($missing -join ', ') from $hooksDir -- the gate exits 0 without enforcing" `
            -Evidence @('The gate dot-sources these; absent, it prints a receipt on stderr (which nothing reads) and allows every tool call.')
    }
}

if ($governed.Count -eq 0) {
    Add-Result -Kind control -Id gate.allowlist -Name 'worktree gate: allowlist' -Status OFF `
        -Detail "governs NOTHING (no entries in $reposFile) -- this is the state a fresh clone is in" `
        -Evidence @("Add THIS primary -- naming it, because the installer will not guess: " +
        "pwsh -NoProfile -File <tooling-checkout>/scripts/worktree/install-gate.ps1 -Repo `"$primaryRoot`"")
} elseif (-not $primaryGoverned) {
    Add-Result -Kind control -Id gate.allowlist -Name 'worktree gate: allowlist' -Status OFF `
        -Detail "$($governed.Count) checkout(s) governed, but NOT this one's primary ($primaryRoot)" `
        -Evidence (@("governed: $primaryRoot is absent from the allowlist below -- another repository was") +
        @('installed instead, which is what a run from the wrong directory produces') + @($governed))
} else {
    Add-Result -Kind control -Id gate.allowlist -Name 'worktree gate: allowlist' -Status OK `
        -Detail "$($governed.Count) checkout(s) governed, including this primary" -Evidence @($governed)
}

# THE DEAD-RULE TRIPWIRE. Read the rules out of the INSTALLED copy -- the source's rule set is not
# evidence about the gate that runs -- and diff them against the matchers wired in each config root.
# A rule with no matcher is never invoked, and nothing anywhere says so.
function Get-HandledTools {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    $tools = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches("$text", '\$tool\s+-(?:not)?in\s+@\(([^)]*)\)')) {
        foreach ($q in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"')) { $null = $tools.Add($q.Groups[1].Value) }
    }
    return @($tools)
}
$handledFrom = if ($gateDstSha) { $gateDst } else { $gateSrc }
$handled = @(Get-HandledTools $handledFrom)
$optIn = @('EnterWorktree')     # off unless install-gate.ps1 -EnterWorktreeGate was used

$settingsCache = @{}
foreach ($cd in $ConfigDir) {
    $sp = Join-Path $cd 'settings.json'
    $settingsCache[$cd] = Read-JsonFile $sp
    $s = $settingsCache[$cd]
    if ($s -and $s.__unreadable) {
        Add-Result -Kind control -Id "gate.wired.$cd" -Name "worktree gate: wired ($(Split-Path $cd -Leaf))" -Status '??' `
            -Detail "settings.json is unreadable: $($s.__error)"
        continue
    }
    $wired = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in (Get-HookRows $s 'PreToolUse')) {
        if ($row.Command -like '*worktree_gate.ps1*') {
            foreach ($t in $row.Matcher.Split('|')) { if ($t) { $null = $wired.Add($t.Trim()) } }
        }
    }
    $absent = @($handled | Where-Object { -not $wired.Contains($_) })
    $unwired = @($absent | Where-Object { $optIn -notcontains $_ } | Sort-Object)
    $offByChoice = @($absent | Where-Object { $optIn -contains $_ } | Sort-Object)
    $stray = @($wired | Where-Object { $handled -notcontains $_ } | Sort-Object)
    $ev = @("matched : $(@($wired | Sort-Object) -join ', ')",
        "implemented by the $(if ($gateDstSha) { 'INSTALLED' } else { 'SOURCE (nothing is installed)' }) gate : $(@($handled | Sort-Object) -join ', ')")
    if ($offByChoice) { $ev += "off by choice (opt-in) : $($offByChoice -join ', ')" }

    if ($wired.Count -eq 0) {
        Add-Result -Kind control -Id "gate.wired.$cd" -Name "worktree gate: wired ($(Split-Path $cd -Leaf))" -Status OFF `
            -Detail 'no PreToolUse entry invokes the gate in this config root' -Evidence $ev
    } elseif ($unwired.Count -gt 0) {
        Add-Result -Kind control -Id "gate.wired.$cd" -Name "worktree gate: wired ($(Split-Path $cd -Leaf))" -Status RED `
            -Detail "DEAD RULES: $($unwired -join ', ') implemented but NEVER FIRE (no matcher invokes the gate for them)" -Evidence $ev
    } elseif ($stray.Count -gt 0) {
        Add-Result -Kind control -Id "gate.wired.$cd" -Name "worktree gate: wired ($(Split-Path $cd -Leaf))" -Status RED `
            -Detail "STRAY MATCHERS: $($stray -join ', ') are matched but the installed script ignores them" -Evidence $ev
    } else {
        Add-Result -Kind control -Id "gate.wired.$cd" -Name "worktree gate: wired ($(Split-Path $cd -Leaf))" -Status OK `
            -Detail "$($wired.Count) matcher(s), every implemented rule reachable" -Evidence $ev
    }
}

# ------------------------------------------------------------------------- SessionStart backstop --
$healSrc = Join-Path $RepoSrcRoot 'scripts/worktree/worktree-selfheal.ps1'
$healDst = if ($hooksDir) { Join-Path $hooksDir 'worktree-selfheal.ps1' } else { $null }
$healSrcSha = Get-FileSha $healSrc
$healDstSha = Get-FileSha $healDst
if (-not $healDstSha) {
    Add-Result -Kind control -Id heal.installed -Name 'selfheal backstop: installed' -Status OFF `
        -Detail "NOT INSTALLED at $healDst"
} elseif ($healDstSha -eq $healSrcSha) {
    Add-Result -Kind control -Id heal.installed -Name 'selfheal backstop: installed' -Status OK `
        -Detail "sha $(Get-ShaTag $healDstSha) == source"
} else {
    Add-Result -Kind control -Id heal.installed -Name 'selfheal backstop: installed' -Status RED `
        -Detail "STALE: installed $(Get-ShaTag $healDstSha) != source $(Get-ShaTag $healSrcSha)"
}
foreach ($cd in $ConfigDir) {
    $s = $settingsCache[$cd]
    if ($s -and $s.__unreadable) { continue }
    $rows = @(Get-HookRows $s 'SessionStart' | Where-Object { $_.Command -like '*worktree-selfheal*' })
    if ($rows.Count -eq 0) {
        Add-Result -Kind control -Id "heal.wired.$cd" -Name "selfheal backstop: wired ($(Split-Path $cd -Leaf))" -Status OFF `
            -Detail 'no SessionStart entry runs it in this config root'
    } else {
        Add-Result -Kind control -Id "heal.wired.$cd" -Name "selfheal backstop: wired ($(Split-Path $cd -Leaf))" -Status OK `
            -Detail "$($rows.Count) SessionStart entry"
    }
}

# ------------------------------------------------------------------- coordination hooks (3 shims) --
# These are SHIMS that re-resolve at run time. There is no installed copy to hash, so the receipt is
# the installer's own record plus a live re-resolution of the target: an entry in settings.json is a
# CLAIM; a receipt plus a target that actually resolves is EVIDENCE.
$coordReceiptPath = if ($SettingsPath) { Join-Path (Split-Path -Parent $SettingsPath) 'ccx-coordination.receipt.json' } else { $null }
$coordReceipt = if ($coordReceiptPath) { Read-JsonFile $coordReceiptPath } else { $null }

# Model the shim's OWN resolution, not a better one. A status check that finds the target by a route
# the hook does not use reports a healthy hook that does not work.
$shimBases = @()
if ($commonDir) { $shimBases += (Split-Path -Parent $commonDir) }
if ($repoRoot) { $shimBases += $repoRoot }
$shimBases = @($shimBases | Where-Object { $_ } | Select-Object -Unique)

$coordRows = @(
    [pscustomobject]@{ Id = 'banner'; Event = 'SessionStart'; Script = 'scripts/worktree/session-context.ps1'; Marker = 'ccx-coord'; Name = 'session banner' }
    [pscustomobject]@{ Id = 'collision'; Event = 'PreToolUse'; Script = 'scripts/hooks/collision_gate.ps1'; Marker = 'ccx-coord'; Name = 'collision gate' }
    [pscustomobject]@{ Id = 'announce'; Event = 'UserPromptSubmit'; Script = 'scripts/hooks/announce-session.ps1'; Marker = 'ccx-announce'; Name = 'announce' }
)
$coordTargets = @{}
$userSettings = if ($SettingsPath) { Read-JsonFile $SettingsPath } else { $null }
foreach ($row in $coordRows) {
    $target = $null
    foreach ($b in $shimBases) {
        $candidate = Join-Path $b $row.Script
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $target = $candidate; break }
    }
    $coordTargets[$row.Id] = $target

    $wiredCmd = $null
    foreach ($r in (Get-HookRows $userSettings $row.Event)) {
        if ($r.Command -like "*$($row.Marker)*") { $wiredCmd = $r.Command; break }
    }
    $rec = $null
    if ($coordReceipt -and -not $coordReceipt.__unreadable -and $coordReceipt.entries) { $rec = $coordReceipt.entries[$row.Event] }

    $ev = @("event $($row.Event)", "marker $($row.Marker)", "resolves to $(if ($target) { $target } else { 'NOTHING' })",
        "receipt $(if ($rec) { 'yes' } else { 'none' })", "bases tried: $($shimBases -join ' ; ')")

    if ($userSettings -and $userSettings.__unreadable) {
        Add-Result -Kind control -Id "coord.$($row.Id)" -Name "coordination: $($row.Name)" -Status '??' `
            -Detail "$SettingsPath is unreadable: $($userSettings.__error)" -Evidence $ev
    } elseif (-not $wiredCmd) {
        Add-Result -Kind control -Id "coord.$($row.Id)" -Name "coordination: $($row.Name)" -Status OFF `
            -Detail "nothing carrying marker '$($row.Marker)' is wired on $($row.Event) in $SettingsPath" -Evidence $ev
    } elseif (-not $target) {
        Add-Result -Kind control -Id "coord.$($row.Id)" -Name "coordination: $($row.Name)" -Status RED `
            -Detail 'WIRED BUT RESOLVES NOTHING -- the shim exits silently, which looks exactly like a healthy hook with no peers' -Evidence $ev
    } elseif (-not $rec) {
        Add-Result -Kind control -Id "coord.$($row.Id)" -Name "coordination: $($row.Name)" -Status '??' `
            -Detail 'wired and resolving, but NO INSTALL RECEIPT -- who wrote this entry is unknown' -Evidence $ev
    } else {
        Add-Result -Kind control -Id "coord.$($row.Id)" -Name "coordination: $($row.Name)" -Status OK `
            -Detail "wired on $($row.Event), resolves, receipted" -Evidence $ev
    }
}

# ------------------------------------------------------------------------------------ git hooks --
$gitReceiptPath = if ($gitHooksDir) { Join-Path $gitHooksDir 'ccx-hooks.receipt.json' } else { $null }
$gitReceipt = if ($gitReceiptPath) { Read-JsonFile $gitReceiptPath } else { $null }
$gitArtifacts = @(
    [pscustomobject]@{ Id = 'claim'; Hook = 'commit-msg'; Marker = 'ccx claim gate'; Payload = 'claim_check.py'; Source = 'scripts/hooks/claim_check.py'; Name = 'claim gate' }
    [pscustomobject]@{ Id = 'push'; Hook = 'pre-push'; Marker = 'ccx push guard'; Payload = 'push_guard.py'; Source = 'scripts/hooks/push_guard.py'; Name = 'push guard' }
)
$installedPayloads = @{}
foreach ($a in $gitArtifacts) {
    $hookPath = Join-Path $gitHooksDir $a.Hook
    $payloadPath = Join-Path $gitHooksDir $a.Payload
    $srcPath = Join-Path $RepoSrcRoot $a.Source
    $installedPayloads[$a.Id] = $payloadPath

    $hookPresent = Test-Path -LiteralPath $hookPath -PathType Leaf
    $hookOurs = $false
    if ($hookPresent) {
        $raw = Get-Content -LiteralPath $hookPath -Raw -ErrorAction SilentlyContinue
        $hookOurs = ("$raw" -match [regex]::Escape($a.Marker))
    }
    $paySha = Get-FileSha $payloadPath
    $srcSha = Get-FileSha $srcPath
    $rec = $null
    if ($gitReceipt -and -not $gitReceipt.__unreadable -and $gitReceipt.entries) { $rec = $gitReceipt.entries[$a.Hook] }
    $ev = @("hook $hookPath", "checker $payloadPath sha $(Get-ShaTag $paySha)", "source sha $(Get-ShaTag $srcSha)",
        "receipt $(if ($rec) { 'yes' } else { 'none' })")

    if (-not $hookPresent) {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status OFF `
            -Detail "no $($a.Hook) hook in $gitHooksDir" -Evidence $ev
    } elseif (-not $hookOurs) {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status OFF `
            -Detail "a $($a.Hook) hook exists but is NOT ours (no '$($a.Marker)' marker) -- ours is not installed" -Evidence $ev
    } elseif (-not $paySha) {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status RED `
            -Detail "the shim is installed but the checker it execs is MISSING at $payloadPath" -Evidence $ev
    } elseif ($paySha -ne $srcSha) {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status RED `
            -Detail "STALE checker: installed $(Get-ShaTag $paySha) != source $(Get-ShaTag $srcSha)" -Evidence $ev
    } elseif (-not $rec) {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status '??' `
            -Detail 'installed and current, but NO INSTALL RECEIPT -- presence is not evidence that this repo installed it' -Evidence $ev
    } else {
        Add-Result -Kind control -Id "git.$($a.Id)" -Name "git hook: $($a.Name)" -Status OK `
            -Detail "shim + checker installed, sha $(Get-ShaTag $paySha) == source" -Evidence $ev
    }
}

# The Python checkers import a shared substrate from their own directory. Without it they raise at
# import and exit 1 -- which for a commit-msg hook means EVERY commit is refused, and for pre-push
# every push. Fail-closed, but for a reason that has nothing to do with what the gate checks.
if ($gitHooksDir) {
    $subst = Join-Path $gitHooksDir '_ccxconfig.py'
    $substSrc = Join-Path $RepoSrcRoot 'scripts/hooks/_ccxconfig.py'
    $anyPayload = @($installedPayloads.Values | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($anyPayload.Count -eq 0) {
        Add-Result -Kind control -Id git.substrate -Name 'git hooks: python substrate' -Status '--' `
            -Detail 'no checker is installed, so there is nothing for it to sit beside'
    } elseif (-not (Test-Path -LiteralPath $subst -PathType Leaf)) {
        Add-Result -Kind control -Id git.substrate -Name 'git hooks: python substrate' -Status RED `
            -Detail "_ccxconfig.py is MISSING from $gitHooksDir -- the installed checkers cannot import it and refuse EVERY commit and push" `
            -Evidence @("copy $substSrc beside the checkers")
    } elseif ((Get-FileSha $subst) -ne (Get-FileSha $substSrc)) {
        Add-Result -Kind control -Id git.substrate -Name 'git hooks: python substrate' -Status RED `
            -Detail '_ccxconfig.py beside the checkers DIFFERS from this checkout'
    } else {
        Add-Result -Kind control -Id git.substrate -Name 'git hooks: python substrate' -Status OK `
            -Detail "_ccxconfig.py present and matching in $gitHooksDir"
    }
}

if (-not $python) {
    Add-Result -Kind control -Id git.python -Name 'git hooks: interpreter' -Status RED `
        -Detail 'NO PYTHON FOUND -- the shims print to stderr and exit 0, so the claim gate and the push guard are OFF for every commit and every push' `
        -Evidence @('Put a python on PATH, or set CCX_PYTHON to one.')
} else {
    Add-Result -Kind control -Id git.python -Name 'git hooks: interpreter' -Status OK `
        -Detail "$($python.Path) [$($python.How)] $($python.Version)"
}

# ---------------------------------------------------------------------------- the sequence gate --
# Never installed by a shipped installer: it needs pre-commit, and that file is deliberately never
# written (two tools cannot both own it). Saying nothing here would leave a silent hole -- an absent
# gate looks exactly like one that passed.
$seqHook = if ($gitHooksDir) { Join-Path $gitHooksDir 'pre-commit' } else { $null }
$seqWired = $false
if ($seqHook -and (Test-Path -LiteralPath $seqHook -PathType Leaf)) {
    $seqWired = ((Get-Content -LiteralPath $seqHook -Raw -ErrorAction SilentlyContinue) -match 'seq_check')
}
if ($cfg.sequences.Count -eq 0) {
    Add-Result -Kind control -Id seq.installed -Name 'sequence gate' -Status '--' `
        -Detail 'no sequences configured, so the sequence machinery is off by configuration' -Required $false
} elseif ($seqWired) {
    Add-Result -Kind control -Id seq.installed -Name 'sequence gate' -Status OK `
        -Detail "a pre-commit hook in $gitHooksDir invokes seq_check"
} else {
    # OFF, not '--'. Sequences ARE configured and nothing enforces them: that is zero enforcement, and
    # the '--' branch above already means something else here (no sequences at all). Collapsing the two
    # would report a real hole with the tag reserved for its absence. But no shipped installer wires
    # this, so it must not fail the run -- hence -Required $false, and hence an OFF row the verdict's
    # required-only count does not include. Say so ON THE ROW: a reader who cannot reconcile the count
    # beside the list is looking at exactly the defect class this tool exists to catch.
    Add-Result -Kind control -Id seq.installed -Name 'sequence gate' -Status OFF `
        -Detail "sequences are configured ($(@($cfg.sequences.Keys) -join ', ')) but NOTHING at commit time enforces them -- opt-in, so the verdict counts it under OFF (opt-in)" -Required $false `
        -Evidence @('No shipped installer writes pre-commit. Wire scripts/hooks/seq_check.py into whatever hook framework you already use.',
        'Until you do, two sessions can take the same number, and the collision merges clean.')
}

# ------------------------------------------------------------------------------ opt-in guards ----
# Wired by hand, not by an installer. Absence is a choice, so it is reported and does not fail the
# run -- but if it IS wired, it gets attacked like everything else.
$optInGuards = @(
    [pscustomobject]@{ Id = 'blanket'; Name = 'blanket-stage guard'; Script = 'scripts/hooks/block-blanket-git-stage.ps1'; Event = 'PreToolUse' }
    [pscustomobject]@{ Id = 'steer'; Name = 'steering injector'; Script = 'scripts/hooks/steer-inject.ps1'; Event = 'PreToolUse' }
)
$optInWired = @{}
foreach ($g in $optInGuards) {
    $leaf = Split-Path $g.Script -Leaf
    $found = @()
    foreach ($cd in $ConfigDir) {
        $s = $settingsCache[$cd]
        foreach ($r in (Get-HookRows $s $g.Event)) { if ($r.Command -like "*$leaf*") { $found += "$cd (matcher '$($r.Matcher)')" } }
    }
    foreach ($proj in @('.claude/settings.json', '.claude/settings.local.json')) {
        $p = Join-Path $repoRoot $proj
        $s = Read-JsonFile $p
        foreach ($r in (Get-HookRows $s $g.Event)) { if ($r.Command -like "*$leaf*") { $found += "$p (matcher '$($r.Matcher)')" } }
    }
    $optInWired[$g.Id] = @($found)
    if ($found.Count -eq 0) {
        Add-Result -Kind control -Id "optin.$($g.Id)" -Name $g.Name -Status '--' `
            -Detail 'not wired anywhere this command can see (opt-in; no shipped installer wires it)' -Required $false
    } else {
        Add-Result -Kind control -Id "optin.$($g.Id)" -Name $g.Name -Status OK `
            -Detail "wired in $($found.Count) location(s)" -Evidence $found -Required $false
    }
}

# -------------------------------------------------------------------------------- the ASCII gate --
# A repo-local checker rather than an installed hook, so there is no second copy to hash and no
# matcher to diff: the receipt is that this checkout carries it. But carrying it is not enforcement.
# No shipped installer runs it, so a checker that is merely present refuses nothing until someone
# invokes it by hand -- and OK is reserved for a control that is installed AND wired. Tagging a file
# that sits there OK made this command's own status field contradict the blind spot it prints below.
# OFF is the honest tag: implemented, nothing invokes it. Opt-in by design, so -Required $false and
# it does not fail the run. The attack below proves it can still refuse a character WHEN run.
$asciiSrc = Join-Path $RepoSrcRoot 'scripts/quality/check-ascii.ps1'
$asciiSrcSha = Get-FileSha $asciiSrc
if ($asciiSrcSha) {
    Add-Result -Kind control -Id ascii.present -Name 'ASCII gate: present, not wired' -Status OFF `
        -Detail "present (sha $(Get-ShaTag $asciiSrcSha)) but NOTHING invokes it -- opt-in, so the verdict counts it under OFF (opt-in)" `
        -Required $false `
        -Evidence @($asciiSrc,
        'No shipped installer runs it. Wire it into your own pre-commit hook and into CI.',
        'Until you do this is capability, not enforcement: it sees a file only when someone runs it.')
} else {
    Add-Result -Kind control -Id ascii.present -Name 'ASCII gate: not in this checkout' -Status OFF `
        -Detail "NOT PRESENT at $asciiSrc -- nothing in this checkout checks encoding" `
        -Evidence @('On a cp1252 console a non-ASCII character in a printed string is an exception, not a character.')
}

# ---------------------------------------------------------------------------- live disarm flags --
$disarms = @()
if ($env:CCX_ALLOW_DIRECT_PUSH -eq '1') { $disarms += 'CCX_ALLOW_DIRECT_PUSH=1 -- the push guard allows a direct push to a protected ref in this environment' }
if ($env:CCX_ANNOUNCE_DISABLE) { $disarms += "CCX_ANNOUNCE_DISABLE is set ('$($env:CCX_ANNOUNCE_DISABLE)') -- announce stands down for sessions started from here" }
if ($stateRoot -and (Test-Path -LiteralPath (Join-Path $stateRoot 'announce/OFF'))) { $disarms += "the announce kill switch file exists: $(Join-Path $stateRoot 'announce/OFF')" }
# core.hooksPath is NOT listed here. It redirects where git looks for hooks, but the installer honours
# it and every git-hook check above was made against that same directory -- so it is a fact about
# WHERE the audit happened (reported under WHAT WAS SCANNED), not a control that has been turned off.
if ($disarms.Count -eq 0) {
    Add-Result -Kind control -Id disarm -Name 'live disarm switches' -Status OK -Detail 'none set in this environment'
} else {
    Add-Result -Kind control -Id disarm -Name 'live disarm switches' -Status RED `
        -Detail "$($disarms.Count) control(s) disarmed right now" -Evidence $disarms
}

# ==================================================================================================
# 3. ATTACKS -- fire each control on purpose and REQUIRE it to deny
#
# Build the control, then attack it. A control that has never been proven able to SEE its own class
# is not evidence of anything. Every attack has a matching NEGATIVE control: a script that refuses
# everything is not a guard, it is an outage, and a gate that cries wolf gets uninstalled.
# ==================================================================================================

Say ''
Say 'ATTACKS (each control is fired on purpose; a control that does not refuse is RED)'

$fixture = $null
try {
    if (-not $SkipAttacks) {
        $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("ccx-doctor-$PID-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force -Path $fixture
    }
} catch {
    $fixture = $null
}

function New-PreToolUsePayload {
    # NB the parameter is $ToolInput, not $Input: $input is an automatic variable and a parameter of
    # that name binds to something other than what the caller passed.
    param([string]$Tool, [hashtable]$ToolInput, [string]$Cwd)
    # ASSERT THE PAYLOAD, because a malformed one is the quietest way for this whole command to lie.
    # An earlier version of this file passed the tool input under a parameter name that bound to
    # NOTHING -- silently, no error -- so four attacks fired payloads carrying tool_name and cwd and
    # no tool_input at all. Every path-keyed rule correctly allowed them, and the doctor reported the
    # gate as broken. The probe was broken. A probe that cannot build its own input must refuse to
    # report a verdict rather than report the target's response to an empty question.
    if ($null -eq $ToolInput -or $ToolInput.Count -eq 0) {
        throw "New-PreToolUsePayload: refusing to build a $Tool payload with an empty tool_input -- the answer to that question means nothing."
    }
    return (@{ hook_event_name = 'PreToolUse'; tool_name = $Tool; tool_input = $ToolInput; cwd = $Cwd } |
            ConvertTo-Json -Compress -Depth 6)
}

function Format-Wrapped {
    # Hard-wrap prose for a fixed-width transcript without depending on the console width.
    param([string]$Text, [int]$Width = 104)
    $out = @()
    $line = ''
    foreach ($word in ("$Text" -split '\s+' | Where-Object { $_ })) {
        if ($line -and ($line.Length + 1 + $word.Length) -gt $Width) { $out += $line; $line = $word }
        elseif ($line) { $line = "$line $word" }
        else { $line = $word }
    }
    if ($line) { $out += $line }
    return $out
}

function Add-AttackSkipped {
    param([string]$Id, [string]$Name, [string]$Why)
    Add-Result -Kind attack -Id $Id -Name $Name -Status '??' -Detail "NOT FIRED -- $Why"
}

if ($SkipAttacks) {
    Add-AttackSkipped 'attack.all' 'every attack' '-SkipAttacks was passed. Nothing was tested, so nothing passed.'
} elseif (-not $fixture) {
    Add-AttackSkipped 'attack.all' 'every attack' 'the temporary fixture directory could not be created'
} else {
    try {
        # ---------------------------------------------------------------- worktree gate attacks --
        $fxHooks = Join-Path $fixture 'hooks'
        $fxPrimary = Join-Path $fixture 'primary'
        $fxOutside = Join-Path $fixture 'outside'
        $fxNested = Join-Path $fxPrimary '.claude/worktrees/peer'
        $null = New-Item -ItemType Directory -Force -Path $fxHooks, $fxPrimary, $fxOutside, $fxNested
        $fxRepos = Join-Path $fxHooks 'ccx-gate.repos.txt'
        Set-Content -LiteralPath $fxRepos -Encoding utf8 -Value @(
            '# ccx doctor fixture allowlist -- a throwaway primary, so the gate can be attacked',
            '# without touching a real checkout.',
            $fxPrimary)

        # The gate under test is the INSTALLED copy. If it is not installed, the source copy is fired
        # instead and every verdict is labelled so -- proving the RULES work says nothing about
        # whether anything is enforcing.
        $gateUnderTest = if ($gateDstSha) { $gateDst } else { $gateSrc }
        $gateLabel = if ($gateDstSha) { 'installed' } else { 'SOURCE (nothing is installed)' }

        function Invoke-GateAttack {
            param(
                [string]$Id, [string]$Name, [string]$Tool, [hashtable]$ToolInput, [string]$Cwd,
                [ValidateSet('deny', 'allow')][string]$Expect,
                [string]$ReposFileArg = $fxRepos
            )
            $payload = New-PreToolUsePayload -Tool $Tool -ToolInput $ToolInput -Cwd $Cwd
            $r = Invoke-PwshProbe -Script $gateUnderTest -ScriptArgs @('-ReposFile', $ReposFileArg) `
                -Stdin $payload -TimeoutSeconds $AttackTimeoutSeconds
            if (-not $r.Ran) {
                Add-Result -Kind attack -Id $Id -Name $Name -Status '??' -Detail "the probe could not run: $($r.Error)"
                return
            }
            $v = Get-HookVerdict $r.StdOut
            $ev = @("gate under test: $gateUnderTest [$gateLabel]", "payload: $payload", "verdict: $($v.Verdict)")
            if ($r.StdErr) { $ev += "stderr: $(Get-FirstLine $r.StdErr 300)" }
            if ($v.Reason) { $ev += "reason: $(Get-FirstLine $v.Reason 200)" }

            if ($Expect -eq 'deny') {
                if ($v.Verdict -eq 'deny') {
                    $st = if ($gateDstSha) { 'OK' } else { '??' }
                    $d = if ($gateDstSha) { 'DENIED, as required' } else { 'the SOURCE copy denies, but nothing is installed -- this is capability, not enforcement' }
                    Add-Result -Kind attack -Id $Id -Name $Name -Status $st -Detail $d -Evidence $ev
                } elseif ($v.Verdict -eq 'allow') {
                    Add-Result -Kind attack -Id $Id -Name $Name -Status RED `
                        -Detail 'ALLOWED. The gate said nothing at all, which is byte-identical to an all-clear.' -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id $Id -Name $Name -Status RED `
                        -Detail "did not deny (verdict '$($v.Verdict)')" -Evidence $ev
                }
            } else {
                if ($v.Verdict -eq 'deny') {
                    Add-Result -Kind attack -Id $Id -Name $Name -Status RED `
                        -Detail 'DENIED an ordinary action. A gate that cries wolf gets routed around, and then it protects nothing.' -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id $Id -Name $Name -Status OK -Detail 'allowed, as required' -Evidence $ev
                }
            }
        }

        Invoke-GateAttack -Id 'attack.gate.rule1' -Name 'gate rule 1: write into primary' -Tool 'Write' `
            -ToolInput @{ file_path = (Join-Path $fxPrimary 'probe.txt'); content = 'x' } -Cwd $fxPrimary -Expect deny

        Invoke-GateAttack -Id 'attack.gate.rule1a' -Name 'gate rule 1a: write to the allowlist' -Tool 'Edit' `
            -ToolInput @{ file_path = $fxRepos; old_string = 'a'; new_string = 'b' } -Cwd $fxOutside -Expect deny

        Invoke-GateAttack -Id 'attack.gate.rule2' -Name 'gate rule 2: dispatch from primary' -Tool 'Task' `
            -ToolInput @{ description = 'probe'; prompt = 'probe' } -Cwd $fxPrimary -Expect deny

        Invoke-GateAttack -Id 'attack.gate.rule3' -Name 'gate rule 3: git verb in primary' -Tool 'Bash' `
            -ToolInput @{ command = 'git checkout some-branch' } -Cwd $fxPrimary -Expect deny

        # NEGATIVE CONTROLS. Without these a gate stuck on "deny" would score a perfect run.
        Invoke-GateAttack -Id 'attack.gate.neg.outside' -Name 'gate negative: write outside' -Tool 'Write' `
            -ToolInput @{ file_path = (Join-Path $fxOutside 'ok.txt'); content = 'x' } -Cwd $fxOutside -Expect allow

        Invoke-GateAttack -Id 'attack.gate.neg.nested' -Name 'gate negative: harness worktree' -Tool 'Write' `
            -ToolInput @{ file_path = (Join-Path $fxNested 'ok.txt'); content = 'x' } -Cwd $fxNested -Expect allow

        # LIVE GOVERNANCE. Everything above proves the gate can see its own class. This proves it is
        # pointed at YOUR primary -- a different question, and the one a stranger gets wrong.
        if ($gateDstSha -and $primaryGoverned -and $reposFile) {
            $payload = New-PreToolUsePayload -Tool 'Write' -ToolInput @{ file_path = (Join-Path $primaryRoot '.ccx-doctor-probe'); content = 'x' } -Cwd $primaryRoot
            $r = Invoke-PwshProbe -Script $gateDst -ScriptArgs @('-ReposFile', $reposFile) -Stdin $payload -TimeoutSeconds $AttackTimeoutSeconds
            $v = Get-HookVerdict $r.StdOut
            if (-not $r.Ran) {
                Add-Result -Kind attack -Id attack.gate.live -Name 'gate: LIVE allowlist + real primary' -Status '??' -Detail "probe could not run: $($r.Error)"
            } elseif ($v.Verdict -eq 'deny') {
                Add-Result -Kind attack -Id attack.gate.live -Name 'gate: LIVE allowlist + real primary' -Status OK `
                    -Detail 'the installed gate, reading the LIVE allowlist, denies a write to this primary' `
                    -Evidence @("no file was written; the gate answers by comparing paths")
            } else {
                Add-Result -Kind attack -Id attack.gate.live -Name 'gate: LIVE allowlist + real primary' -Status RED `
                    -Detail "the installed gate did NOT deny a write to the governed primary (verdict '$($v.Verdict)')" `
                    -Evidence @("stderr: $(Get-FirstLine $r.StdErr 300)")
            }

            # NEGATIVE CONTROL for the live probe. The fixture negatives above prove the gate does not
            # deny everything when it reads a FIXTURE allowlist naming one throwaway directory. They
            # say nothing about the allowlist you actually have: an entry that is a prefix of every
            # path on the box (a drive root, a home directory, an empty-looking line that normalises
            # to one) governs the whole machine, and the deny above would look exactly as healthy.
            # So fire the same installed gate, reading the same LIVE allowlist, at a path outside
            # every governed root and require it to allow.
            $payloadN = New-PreToolUsePayload -Tool 'Write' -ToolInput @{ file_path = (Join-Path $fxOutside 'live-neg.txt'); content = 'x' } -Cwd $fxOutside
            $rn = Invoke-PwshProbe -Script $gateDst -ScriptArgs @('-ReposFile', $reposFile) -Stdin $payloadN -TimeoutSeconds $AttackTimeoutSeconds
            $vn = Get-HookVerdict $rn.StdOut
            $evn = @("gate: $gateDst reading the LIVE allowlist $reposFile", "payload: $payloadN", "verdict: $($vn.Verdict)")
            if ($vn.Reason) { $evn += "reason: $(Get-FirstLine $vn.Reason 200)" }
            if (-not $rn.Ran) {
                Add-Result -Kind attack -Id attack.gate.live.neg -Name 'gate negative: LIVE allowlist, ungoverned path' -Status '??' `
                    -Detail "probe could not run: $($rn.Error)"
            } elseif ($vn.Verdict -eq 'deny') {
                Add-Result -Kind attack -Id attack.gate.live.neg -Name 'gate negative: LIVE allowlist, ungoverned path' -Status RED `
                    -Detail 'the LIVE allowlist denies a write to a temp directory it does not govern -- an entry in it is matching far more than the checkout you meant' `
                    -Evidence $evn
            } else {
                Add-Result -Kind attack -Id attack.gate.live.neg -Name 'gate negative: LIVE allowlist, ungoverned path' -Status OK `
                    -Detail 'allowed a write outside every governed root, as required' -Evidence $evn
            }
        } else {
            Add-Result -Kind attack -Id attack.gate.live -Name 'gate: LIVE allowlist + real primary' -Status '??' `
                -Detail 'not fired: the gate is not installed, or this primary is not in the live allowlist (so it is not governed)'
            Add-Result -Kind attack -Id attack.gate.live.neg -Name 'gate negative: LIVE allowlist, ungoverned path' -Status '??' `
                -Detail 'not fired: there was no live deny to pair it with'
        }

        # ------------------------------------------------------------ blanket-stage guard attack --
        $blanket = Join-Path $RepoSrcRoot 'scripts/hooks/block-blanket-git-stage.ps1'
        $blanketWired = @($optInWired['blanket']).Count -gt 0
        $blanketLabel = if ($blanketWired) { 'wired' } else { 'CAPABILITY ONLY -- nothing invokes this guard' }
        foreach ($case in @(
                @{ Id = 'attack.blanket.deny'; Name = 'blanket stage: git add -A'; Cmd = 'git add -A'; Expect = 'deny' },
                @{ Id = 'attack.blanket.allow'; Name = 'blanket stage: explicit path'; Cmd = 'git add docs/x.md'; Expect = 'allow' })) {
            $payload = New-PreToolUsePayload -Tool 'Bash' -ToolInput @{ command = $case.Cmd } -Cwd $fxOutside
            $r = Invoke-PwshProbe -Script $blanket -Stdin $payload -TimeoutSeconds $AttackTimeoutSeconds
            if (-not $r.Ran) {
                Add-Result -Kind attack -Id $case.Id -Name $case.Name -Status '??' -Detail "probe could not run: $($r.Error)" -Required $false
                continue
            }
            $v = Get-HookVerdict $r.StdOut
            $ok = ($case.Expect -eq 'deny' -and $v.Verdict -eq 'deny') -or ($case.Expect -eq 'allow' -and $v.Verdict -ne 'deny')
            if ($ok -and -not $blanketWired) {
                Add-Result -Kind attack -Id $case.Id -Name $case.Name -Status '--' `
                    -Detail "behaved correctly ($($case.Expect)), but $blanketLabel" -Required $false
            } elseif ($ok) {
                Add-Result -Kind attack -Id $case.Id -Name $case.Name -Status OK -Detail "$($case.Expect), as required" -Required $false
            } else {
                Add-Result -Kind attack -Id $case.Id -Name $case.Name -Status RED `
                    -Detail "expected $($case.Expect), got '$($v.Verdict)'" -Evidence @("command: $($case.Cmd)") -Required $false
            }
        }

        # ------------------------------------------------------------------ collision gate attack --
        # Its DENY path needs a live peer worktree holding an uncommitted change, which cannot be
        # manufactured here. What CAN be proven is the property it was rebuilt for: when it cannot
        # check, it must say so rather than emit the silence that reads as all-clear.
        $collision = $coordTargets['collision']
        if (-not $collision) { $collision = Join-Path $RepoSrcRoot 'scripts/hooks/collision_gate.ps1' }
        $fxState = Join-Path $fixture 'state'
        $null = New-Item -ItemType Directory -Force -Path $fxState
        $payload = New-PreToolUsePayload -Tool 'Edit' -ToolInput @{ file_path = (Join-Path $fxOutside 'f.txt') } -Cwd $fxOutside
        $r = Invoke-PwshProbe -Script $collision -Stdin $payload -TimeoutSeconds $AttackTimeoutSeconds `
            -ScriptArgs @('-OverlapScript', (Join-Path $fixture 'no-such-overlap.ps1'), '-StateDir', $fxState)
        if (-not $r.Ran) {
            Add-Result -Kind attack -Id attack.collision.unresolved -Name 'collision gate: must not go silent' -Status '??' `
                -Detail "probe could not run: $($r.Error)"
        } else {
            $v = Get-HookVerdict $r.StdOut
            if ($v.Verdict -eq 'context' -and $v.Context -match 'could NOT check') {
                Add-Result -Kind attack -Id attack.collision.unresolved -Name 'collision gate: must not go silent' -Status OK `
                    -Detail 'an unresolvable check is reported as UNKNOWN, not as all-clear' -Evidence @(Get-FirstLine $v.Context 220)
            } elseif ($v.Verdict -eq 'allow') {
                Add-Result -Kind attack -Id attack.collision.unresolved -Name 'collision gate: must not go silent' -Status RED `
                    -Detail 'it checked NOTHING and said NOTHING -- indistinguishable from "nobody else is in this file"' `
                    -Evidence @("stderr: $(Get-FirstLine $r.StdErr 200)")
            } else {
                Add-Result -Kind attack -Id attack.collision.unresolved -Name 'collision gate: must not go silent' -Status RED `
                    -Detail "unexpected verdict '$($v.Verdict)'" -Evidence @(Get-FirstLine $r.StdOut 220)
            }
        }

        # NEGATIVE CONTROL for the probe above. "It says so when it cannot check" and "it says that
        # about every edit" are the same output on a run where the check was always going to fail --
        # and a gate that injects an UNKNOWN notice into every Edit and Write is a gate that gets
        # uninstalled, which is how this ends up protecting nothing. So: a check that DOES resolve,
        # to nobody else in the file, must produce silence.
        #
        # The stub TOUCHES A SENTINEL when it runs, and the sentinel is required. Without it the pass
        # condition is an empty stdout, which is also exactly what the gate emits when it exits early
        # having consulted nothing -- the identity this whole command exists to break. The sentinel
        # is what makes the silence mean "checked, clear" instead of "said nothing".
        #
        # Its own StateDir, too: the notice above is rate-limited per reason, and a throttle stamp
        # left by that probe silencing this one would be scored as a pass.
        $stubOverlap = Join-Path $fixture 'stub-overlap.ps1'
        $stubSentinel = Join-Path $fixture 'overlap-was-consulted.txt'
        $fxState2 = Join-Path $fixture 'state-resolved'
        $null = New-Item -ItemType Directory -Force -Path $fxState2
        # Single-quote-escaped for the literal that goes INTO the stub. A path is data here, and a
        # quote in it would end the string and turn the rest into code.
        $stubSentinelLit = $stubSentinel.Replace("'", "''")
        Set-Content -LiteralPath $stubOverlap -Encoding utf8NoBOM -Value @(
            '# ccx doctor fixture: a resolving overlap script -- nobody else is in this file.',
            'param([string]$File, [switch]$Json)',
            "Set-Content -LiteralPath '$stubSentinelLit' -Value 'consulted'",
            '# Under -Json a resolved "nobody else" is the two bytes [], never nothing at all.',
            'Write-Output "[]"',
            'exit 0')
        $rc2 = Invoke-PwshProbe -Script $collision -Stdin $payload -TimeoutSeconds $AttackTimeoutSeconds `
            -ScriptArgs @('-OverlapScript', $stubOverlap, '-StateDir', $fxState2)
        $consulted = Test-Path -LiteralPath $stubSentinel -PathType Leaf
        if (-not $rc2.Ran) {
            Add-Result -Kind attack -Id attack.collision.resolved -Name 'collision gate negative: resolved, clear' -Status '??' `
                -Detail "probe could not run: $($rc2.Error)"
        } else {
            $v2 = Get-HookVerdict $rc2.StdOut
            $ev2 = @("gate: $collision", "overlap stub: $stubOverlap", "stub was consulted: $consulted",
                "verdict: $($v2.Verdict)", "said: $(if ($rc2.StdOut) { Get-FirstLine $rc2.StdOut 220 } else { '(nothing)' })")
            if (-not $consulted) {
                Add-Result -Kind attack -Id attack.collision.resolved -Name 'collision gate negative: resolved, clear' -Status RED `
                    -Detail 'the gate never consulted the overlap script at all -- whatever it said, it was not the answer to this edit' -Evidence $ev2
            } elseif ($v2.Verdict -eq 'allow') {
                Add-Result -Kind attack -Id attack.collision.resolved -Name 'collision gate negative: resolved, clear' -Status OK `
                    -Detail 'consulted the overlap script, got a resolved all-clear, and said nothing -- as required' -Evidence $ev2
            } elseif ($v2.Verdict -eq 'deny') {
                Add-Result -Kind attack -Id attack.collision.resolved -Name 'collision gate negative: resolved, clear' -Status RED `
                    -Detail 'DENIED an edit no peer worktree is touching. A gate that cries wolf gets routed around, and then it protects nothing.' -Evidence $ev2
            } else {
                Add-Result -Kind attack -Id attack.collision.resolved -Name 'collision gate negative: resolved, clear' -Status RED `
                    -Detail "it reported UNKNOWN ('$($v2.Verdict)') about a check that resolved -- an unknown on every edit trains the reader to ignore the real one" -Evidence $ev2
            }
        }

        # ------------------------------------------------------------------- python gates attacks --
        if (-not $python) {
            Add-AttackSkipped 'attack.claim' 'claim gate: unclaimed item' 'no python interpreter; the shims fail open, so the gate is OFF regardless'
            Add-AttackSkipped 'attack.push' 'push guard: protected ref' 'no python interpreter; the shims fail open, so the guard is OFF regardless'
        } elseif (-not $gitExe) {
            Add-AttackSkipped 'attack.claim' 'claim gate: unclaimed item' 'git is not on PATH, so no fixture repository could be built'
            Add-AttackSkipped 'attack.push' 'push guard: protected ref' 'git is not on PATH, so no fixture repository could be built'
        } else {
            # A throwaway repository with its own config, its own state root and its own index. The
            # real repository is never touched.
            $fxRepo = Join-Path $fixture 'repo'
            $null = New-Item -ItemType Directory -Force -Path $fxRepo
            $gitOk = $true
            function Invoke-FxGit { param([string[]]$GitArgs) return (Invoke-Probe -FilePath $gitExe -ArgumentList $GitArgs -WorkingDirectory $fxRepo -TimeoutSeconds 60) }
            $null = Invoke-FxGit @('init', '-q', '-b', 'main', '.')
            $null = Invoke-FxGit @('config', 'user.email', 'doctor@example.invalid')
            $null = Invoke-FxGit @('config', 'user.name', 'ccx doctor')
            $seqName = if ($cfg.sequences.Count -gt 0) { @($cfg.sequences.Keys | Sort-Object)[0] } else { 'adr' }
            # DELIBERATELY FREE OF REGEX ESCAPES. The gates under test need only the sequence NAME and
            # the protected refs from this file. A filePattern here would carry backslashes through a
            # here-string into JSON, and a config that fails to parse makes both gates refuse for a
            # reason that has nothing to do with the attack -- which then reads as a pass.
            @"
{
  "prefix": "$($cfg.prefix)",
  "trunk": "main",
  "protectedRefs": ["refs/heads/main"],
  "sequences": { "$seqName": { "dir": "docs/$seqName" } }
}
"@ | Set-Content -LiteralPath (Join-Path $fxRepo 'ccx.config.json') -Encoding utf8NoBOM
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $fxRepo 'src')
            Set-Content -LiteralPath (Join-Path $fxRepo 'src/probe.txt') -Value 'probe' -Encoding utf8NoBOM
            $add = Invoke-FxGit @('add', 'src/probe.txt', 'ccx.config.json')
            if (-not $add.Ran -or $add.ExitCode -ne 0) { $gitOk = $false }
            $topRaw = (Invoke-FxGit @('rev-parse', '--path-format=absolute', '--show-toplevel')).StdOut.Trim()
            $commonRaw = (Invoke-FxGit @('rev-parse', '--path-format=absolute', '--git-common-dir')).StdOut.Trim()

            $claimPayload = $installedPayloads['claim']
            $claimUnderTest = if ($claimPayload -and (Test-Path -LiteralPath $claimPayload)) { $claimPayload } else { Join-Path $RepoSrcRoot 'scripts/hooks/claim_check.py' }
            $claimInstalled = ($claimPayload -and (Test-Path -LiteralPath $claimPayload))

            if (-not $gitOk -or -not $topRaw) {
                Add-AttackSkipped 'attack.claim' 'claim gate: unclaimed item' 'the fixture repository could not be prepared'
                Add-AttackSkipped 'attack.push' 'push guard: protected ref' 'the fixture repository could not be prepared'
            } else {
                # ---- claim gate: a code-touching commit claiming an unclaimed item MUST refuse ----
                $msgFile = Join-Path $fixture 'commit-msg.txt'
                Set-Content -LiteralPath $msgFile -Value "feat: implement $seqName #99999" -Encoding utf8NoBOM
                $env0 = @{ CCX_CONFIG = $null }   # let it walk up from the fixture, as it does in real life
                $r = Invoke-Probe -FilePath $python.Path -ArgumentList @($claimUnderTest, $msgFile) `
                    -WorkingDirectory $fxRepo -Environment $env0 -TimeoutSeconds $AttackTimeoutSeconds
                $importBroken = ($r.StdErr -match 'cannot import _ccxconfig')
                $ev = @("checker: $claimUnderTest$(if (-not $claimInstalled) { '  [SOURCE -- nothing is installed]' })",
                    "exit $($r.ExitCode)", "stderr: $(Get-FirstLine $r.StdErr 260)")
                if (-not $r.Ran) {
                    Add-Result -Kind attack -Id attack.claim -Name 'claim gate: unclaimed item' -Status '??' -Detail "probe could not run: $($r.Error)"
                } elseif ($importBroken) {
                    # It exits 1, so it looks like a refusal. It is not: it refuses EVERYTHING.
                    Add-Result -Kind attack -Id attack.claim -Name 'claim gate: unclaimed item' -Status RED `
                        -Detail 'it exits non-zero because it cannot import its own substrate -- it refuses every commit, not the unclaimed one' -Evidence $ev
                } elseif ($r.ExitCode -eq 1) {
                    Add-Result -Kind attack -Id attack.claim -Name 'claim gate: unclaimed item' -Status $(if ($claimInstalled) { 'OK' } else { '??' }) `
                        -Detail $(if ($claimInstalled) { 'REFUSED, as required' } else { 'the source copy refuses, but nothing is installed -- capability, not enforcement' }) -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id attack.claim -Name 'claim gate: unclaimed item' -Status RED `
                        -Detail "ALLOWED a code commit claiming an unclaimed item (exit $($r.ExitCode))" -Evidence $ev
                }

                # ---- negative control: the same commit, with the claim held by THIS worktree ----
                if (-not $importBroken -and $commonRaw) {
                    $claimsDir = Join-Path (Join-Path $commonRaw "$($cfg.prefix)-coord") 'claims'
                    $null = New-Item -ItemType Directory -Force -Path $claimsDir
                    $claimDoc = @{ key = '99999'; note = 'ccx doctor probe'; branch = 'main'; worktree = $topRaw; claimed = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
                    [System.IO.File]::WriteAllBytes((Join-Path $claimsDir '99999.json'), [System.Text.Encoding]::UTF8.GetBytes($claimDoc))
                    $r2 = Invoke-Probe -FilePath $python.Path -ArgumentList @($claimUnderTest, $msgFile) `
                        -WorkingDirectory $fxRepo -Environment $env0 -TimeoutSeconds $AttackTimeoutSeconds
                    if (-not $r2.Ran) {
                        Add-Result -Kind attack -Id attack.claim.neg -Name 'claim gate negative: item held' -Status '??' -Detail "probe could not run: $($r2.Error)"
                    } elseif ($r2.ExitCode -eq 0) {
                        Add-Result -Kind attack -Id attack.claim.neg -Name 'claim gate negative: item held' -Status OK -Detail 'allowed, as required'
                    } else {
                        Add-Result -Kind attack -Id attack.claim.neg -Name 'claim gate negative: item held' -Status RED `
                            -Detail "refused a commit whose item IS claimed by this worktree (exit $($r2.ExitCode)) -- it is refusing for some other reason" `
                            -Evidence @("stderr: $(Get-FirstLine $r2.StdErr 260)")
                    }
                }

                # ---- push guard: a protected ref MUST be refused ----
                $pushPayload = $installedPayloads['push']
                $pushUnderTest = if ($pushPayload -and (Test-Path -LiteralPath $pushPayload)) { $pushPayload } else { Join-Path $RepoSrcRoot 'scripts/hooks/push_guard.py' }
                $pushInstalled = ($pushPayload -and (Test-Path -LiteralPath $pushPayload))
                $envPush = @{ CCX_CONFIG = $null; CCX_ALLOW_DIRECT_PUSH = $null }  # prove it refuses on its own merits
                $sha1 = '1111111111111111111111111111111111111111'
                $r = Invoke-Probe -FilePath $python.Path -ArgumentList @($pushUnderTest, 'origin', 'https://example.invalid/x.git') `
                    -Stdin "refs/heads/main $sha1 refs/heads/main 0000000000000000000000000000000000000000`n" `
                    -WorkingDirectory $fxRepo -Environment $envPush -TimeoutSeconds $AttackTimeoutSeconds
                $ev = @("checker: $pushUnderTest$(if (-not $pushInstalled) { '  [SOURCE -- nothing is installed]' })", "exit $($r.ExitCode)")
                if (-not $r.Ran) {
                    Add-Result -Kind attack -Id attack.push -Name 'push guard: protected ref' -Status '??' -Detail "probe could not run: $($r.Error)"
                } elseif ($r.StdErr -match 'cannot import _ccxconfig') {
                    Add-Result -Kind attack -Id attack.push -Name 'push guard: protected ref' -Status RED `
                        -Detail 'it exits non-zero because it cannot import its own substrate -- it refuses every push, not the protected one' -Evidence $ev
                } elseif ($r.ExitCode -eq 1) {
                    Add-Result -Kind attack -Id attack.push -Name 'push guard: protected ref' -Status $(if ($pushInstalled) { 'OK' } else { '??' }) `
                        -Detail $(if ($pushInstalled) { 'REFUSED, as required' } else { 'the source copy refuses, but nothing is installed -- capability, not enforcement' }) -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id attack.push -Name 'push guard: protected ref' -Status RED `
                        -Detail "ALLOWED a direct push to a protected ref (exit $($r.ExitCode))" -Evidence $ev
                }

                $r2 = Invoke-Probe -FilePath $python.Path -ArgumentList @($pushUnderTest, 'origin', 'https://example.invalid/x.git') `
                    -Stdin "refs/heads/feature $sha1 refs/heads/feature 0000000000000000000000000000000000000000`n" `
                    -WorkingDirectory $fxRepo -Environment $envPush -TimeoutSeconds $AttackTimeoutSeconds
                if (-not $r2.Ran) {
                    Add-Result -Kind attack -Id attack.push.neg -Name 'push guard negative: feature ref' -Status '??' -Detail "probe could not run: $($r2.Error)"
                } elseif ($r2.ExitCode -eq 0) {
                    Add-Result -Kind attack -Id attack.push.neg -Name 'push guard negative: feature ref' -Status OK -Detail 'allowed, as required'
                } else {
                    Add-Result -Kind attack -Id attack.push.neg -Name 'push guard negative: feature ref' -Status RED `
                        -Detail "refused an ordinary feature-branch push (exit $($r2.ExitCode))" -Evidence @("stderr: $(Get-FirstLine $r2.StdErr 260)")
                }
            }

            # ------------------------------------------------------------------ selfheal attack --
            # A backstop whose whole job is an unattended repair is the easiest control on the box to
            # have silently doing nothing. Drift a throwaway primary and require it to be repaired.
            $fxHeal = Join-Path $fixture 'heal'
            $null = New-Item -ItemType Directory -Force -Path $fxHeal
            function Invoke-HealGit { param([string[]]$GitArgs) return (Invoke-Probe -FilePath $gitExe -ArgumentList $GitArgs -WorkingDirectory $fxHeal -TimeoutSeconds 60) }
            $null = Invoke-HealGit @('init', '-q', '-b', 'main', '.')
            $null = Invoke-HealGit @('config', 'user.email', 'doctor@example.invalid')
            $null = Invoke-HealGit @('config', 'user.name', 'ccx doctor')
            Set-Content -LiteralPath (Join-Path $fxHeal 'seed.txt') -Value 'seed' -Encoding utf8NoBOM
            $null = Invoke-HealGit @('add', 'seed.txt')
            $null = Invoke-HealGit @('commit', '-q', '-m', 'seed')
            $null = Invoke-HealGit @('checkout', '-q', '-b', 'drifted')
            $headBefore = (Invoke-HealGit @('rev-parse', '--abbrev-ref', 'HEAD')).StdOut.Trim()

            $healRepos = Join-Path $fixture 'heal-allowlist.txt'
            Set-Content -LiteralPath $healRepos -Encoding utf8 -Value @('# ccx doctor fixture', $fxHeal)
            $healUnderTest = if ($healDstSha) { $healDst } else { $healSrc }
            $healInstalled = [bool]$healDstSha
            if ($headBefore -ne 'drifted') {
                Add-AttackSkipped 'attack.selfheal' 'selfheal: repair a drifted primary' 'the fixture repository would not drift'
            } else {
                $r = Invoke-PwshProbe -Script $healUnderTest -ScriptArgs @('-ReposFile', $healRepos) `
                    -Stdin (@{ hook_event_name = 'SessionStart'; cwd = $fxHeal } | ConvertTo-Json -Compress) `
                    -TimeoutSeconds $AttackTimeoutSeconds
                $headAfter = (Invoke-HealGit @('rev-parse', '--abbrev-ref', 'HEAD')).StdOut.Trim()
                $v = Get-HookVerdict $r.StdOut
                $ev = @("script: $healUnderTest$(if (-not $healInstalled) { '  [SOURCE -- nothing is installed]' })",
                    "HEAD before: $headBefore, after: $headAfter", "said: $(Get-FirstLine $v.Context 200)")
                if (-not $r.Ran) {
                    Add-Result -Kind attack -Id attack.selfheal -Name 'selfheal: repair a drifted primary' -Status '??' -Detail "probe could not run: $($r.Error)"
                } elseif ($headAfter -eq 'main' -and $v.Verdict -eq 'context') {
                    Add-Result -Kind attack -Id attack.selfheal -Name 'selfheal: repair a drifted primary' -Status $(if ($healInstalled) { 'OK' } else { '??' }) `
                        -Detail $(if ($healInstalled) { 'repaired the drifted primary and reported it' } else { 'the source copy repairs, but nothing is installed -- capability, not enforcement' }) -Evidence $ev
                } elseif ($headAfter -eq 'main') {
                    Add-Result -Kind attack -Id attack.selfheal -Name 'selfheal: repair a drifted primary' -Status RED `
                        -Detail 'it repaired the primary but said NOTHING -- a silent repair is a repair nobody can audit' -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id attack.selfheal -Name 'selfheal: repair a drifted primary' -Status RED `
                        -Detail "the drifted primary was NOT repaired (HEAD is still '$headAfter')" -Evidence $ev
                }
            }

            # ---- NEGATIVE CONTROL: a DIRTY drifted primary must be REFUSED, and told about ----
            #
            # THIS IS THE PAIR THAT MATTERS MOST IN THE FILE. The attack above drifts a CLEAN tree,
            # which the backstop is supposed to repair -- so it passes identically whether or not the
            # dirty-tree test exists at all. Delete that test and every check above stays green while
            # an unattended `git checkout` starts running over uncommitted work in a shared checkout,
            # at session start, with nobody watching. That refusal is this control's only safety
            # property, and until this probe existed nothing anywhere proved it.
            #
            # A SEPARATE fixture, not the one above: that one has been repaired onto its home branch
            # by the time we get here, and re-drifting it would make the two verdicts depend on the
            # order they ran in.
            $fxDirty = Join-Path $fixture 'heal-dirty'
            $null = New-Item -ItemType Directory -Force -Path $fxDirty
            function Invoke-DirtyGit { param([string[]]$GitArgs) return (Invoke-Probe -FilePath $gitExe -ArgumentList $GitArgs -WorkingDirectory $fxDirty -TimeoutSeconds 60) }
            $null = Invoke-DirtyGit @('init', '-q', '-b', 'main', '.')
            $null = Invoke-DirtyGit @('config', 'user.email', 'doctor@example.invalid')
            $null = Invoke-DirtyGit @('config', 'user.name', 'ccx doctor')
            $dirtyFile = Join-Path $fxDirty 'work.txt'
            Set-Content -LiteralPath $dirtyFile -Value 'committed' -Encoding utf8NoBOM
            $null = Invoke-DirtyGit @('add', 'work.txt')
            $null = Invoke-DirtyGit @('commit', '-q', '-m', 'seed')
            $null = Invoke-DirtyGit @('checkout', '-q', '-b', 'drifted')
            # The uncommitted work that must survive. Its CONTENT is checked afterwards, not just
            # HEAD: a checkout that carried the change across and one that discarded it both leave
            # HEAD on the home branch, and only the bytes tell those apart.
            $dirtyMark = 'uncommitted work that must survive this probe'
            Set-Content -LiteralPath $dirtyFile -Value $dirtyMark -Encoding utf8NoBOM
            $dHeadBefore = (Invoke-DirtyGit @('rev-parse', '--abbrev-ref', 'HEAD')).StdOut.Trim()
            $dStatusBefore = (Invoke-DirtyGit @('status', '--porcelain')).StdOut.Trim()

            if ($dHeadBefore -ne 'drifted' -or -not $dStatusBefore) {
                # The fixture never reached the state under test, so there was no refusal to observe.
                # Reporting OK here would credit the control with declining something nobody asked it.
                Add-AttackSkipped 'attack.selfheal.neg' 'selfheal negative: dirty primary refused' `
                    "the fixture would not reach drifted+dirty (HEAD '$dHeadBefore', status '$(Get-FirstLine $dStatusBefore 60)')"
            } else {
                $dRepos = Join-Path $fixture 'heal-dirty-allowlist.txt'
                Set-Content -LiteralPath $dRepos -Encoding utf8 -Value @('# ccx doctor fixture', $fxDirty)
                $rd = Invoke-PwshProbe -Script $healUnderTest -ScriptArgs @('-ReposFile', $dRepos) `
                    -Stdin (@{ hook_event_name = 'SessionStart'; cwd = $fxDirty } | ConvertTo-Json -Compress) `
                    -TimeoutSeconds $AttackTimeoutSeconds
                $dHeadAfter = (Invoke-DirtyGit @('rev-parse', '--abbrev-ref', 'HEAD')).StdOut.Trim()
                $dContentAfter = '(unreadable)'
                try { $dContentAfter = "$(Get-Content -LiteralPath $dirtyFile -Raw -ErrorAction Stop)".Trim() } catch { }
                $vd = Get-HookVerdict $rd.StdOut
                # "It said why" is a claim about the REASON, so it is read off the reason rather than
                # off the presence of output: a backstop that repaired silently while emitting some
                # unrelated note would otherwise score as a refusal that explained itself.
                $saidWhy = ($vd.Verdict -eq 'context' -and $vd.Context -match '(?i)uncommitted')
                $workSurvived = ($dContentAfter -eq $dirtyMark)
                $ev = @("script: $healUnderTest$(if (-not $healInstalled) { '  [SOURCE -- nothing is installed]' })",
                    "HEAD before: $dHeadBefore, after: $dHeadAfter",
                    "uncommitted work intact: $workSurvived",
                    "said: $(if ($vd.Context) { Get-FirstLine $vd.Context 220 } else { '(nothing at all)' })")
                if (-not $rd.Ran) {
                    Add-Result -Kind attack -Id attack.selfheal.neg -Name 'selfheal negative: dirty primary refused' -Status '??' `
                        -Detail "probe could not run: $($rd.Error)" -Evidence $ev
                } elseif ($dHeadAfter -ne 'drifted' -or -not $workSurvived) {
                    Add-Result -Kind attack -Id attack.selfheal.neg -Name 'selfheal negative: dirty primary refused' -Status RED `
                        -Detail 'IT REPAIRED A DIRTY PRIMARY -- the one thing this backstop must never do. An unattended checkout ran over uncommitted work.' `
                        -Evidence $ev
                } elseif (-not $saidWhy) {
                    Add-Result -Kind attack -Id attack.selfheal.neg -Name 'selfheal negative: dirty primary refused' -Status RED `
                        -Detail 'it refused (correct) but never said why -- silence here is byte-identical to a primary that was fine, so nobody learns the shared checkout is stuck on the wrong branch' `
                        -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id attack.selfheal.neg -Name 'selfheal negative: dirty primary refused' `
                        -Status $(if ($healInstalled) { 'OK' } else { '??' }) `
                        -Detail $(if ($healInstalled) { 'REFUSED, left the uncommitted work untouched, and said why' } else { 'the source copy refuses, but nothing is installed -- capability, not enforcement' }) `
                        -Evidence $ev
                }
            }
        }

        # ---------------------------------------------------------------------- ASCII gate attack --
        # Three cases, because "it printed no violations" is consistent with all three of: the tree is
        # clean, the checker cannot see the class, and the checker scanned nothing at all. The planted
        # character is written from a CODE POINT, never as a literal -- a literal here would have to
        # survive this file, every editor that opens it, and the very rule this check enforces.
        if (-not $asciiSrcSha) {
            Add-AttackSkipped 'attack.ascii' 'ASCII gate: planted em dash' 'the checker is not in this checkout'
        } else {
            $fxAscii = Join-Path $fixture 'ascii'
            try {
                $fxAsciiEmpty = Join-Path $fxAscii 'nothing'
                $null = New-Item -ItemType Directory -Force -Path $fxAscii, $fxAsciiEmpty
                $utf8 = [System.Text.UTF8Encoding]::new($false)
                $planted = Join-Path $fxAscii 'planted.md'
                [System.IO.File]::WriteAllBytes($planted, $utf8.GetBytes("a line with an em dash $([char]0x2014) in it`n"))
                $cleanFile = Join-Path $fxAscii 'clean.md'
                [System.IO.File]::WriteAllBytes($cleanFile, $utf8.GetBytes("a line with two hyphens -- in it`n"))

                # 1. THE ATTACK. It must exit non-zero AND name the character it found: a non-zero
                #    exit alone is also what "the file could not be read" looks like, and a gate that
                #    refuses for the wrong reason refuses everything.
                $r = Invoke-PwshProbe -Script $asciiSrc -ScriptArgs @('-Path', $planted) -TimeoutSeconds $AttackTimeoutSeconds
                $named = ($r.StdOut -match 'U\+2014')
                $ev = @("checker: $asciiSrc", "exit $($r.ExitCode)", "named U+2014: $named",
                    "said: $(Get-FirstLine $r.StdOut 220)")
                if (-not $r.Ran) {
                    Add-Result -Kind attack -Id attack.ascii -Name 'ASCII gate: planted em dash' -Status '??' `
                        -Detail "probe could not run: $($r.Error)"
                } elseif ($r.ExitCode -eq 1 -and $named) {
                    Add-Result -Kind attack -Id attack.ascii -Name 'ASCII gate: planted em dash' -Status OK `
                        -Detail 'REFUSED, and named the character it refused' -Evidence $ev
                } elseif ($r.ExitCode -eq 1) {
                    Add-Result -Kind attack -Id attack.ascii -Name 'ASCII gate: planted em dash' -Status RED `
                        -Detail 'it exited 1 but never named U+2014 -- it is refusing for some other reason' -Evidence $ev
                } elseif ($r.ExitCode -eq 0) {
                    Add-Result -Kind attack -Id attack.ascii -Name 'ASCII gate: planted em dash' -Status RED `
                        -Detail 'ALLOWED a planted em dash. The gate cannot see the class it exists to see.' -Evidence $ev
                } else {
                    Add-Result -Kind attack -Id attack.ascii -Name 'ASCII gate: planted em dash' -Status RED `
                        -Detail "it could not scan the file at all (exit $($r.ExitCode)) -- fail-closed noise, not detection" -Evidence $ev
                }

                # 2. NEGATIVE CONTROL. A checker that refuses every file is an outage, not a gate.
                $r2 = Invoke-PwshProbe -Script $asciiSrc -ScriptArgs @('-Path', $cleanFile) -TimeoutSeconds $AttackTimeoutSeconds
                if (-not $r2.Ran) {
                    Add-Result -Kind attack -Id attack.ascii.neg -Name 'ASCII gate negative: clean file' -Status '??' `
                        -Detail "probe could not run: $($r2.Error)"
                } elseif ($r2.ExitCode -eq 0) {
                    Add-Result -Kind attack -Id attack.ascii.neg -Name 'ASCII gate negative: clean file' -Status OK `
                        -Detail 'passed a pure-ASCII file, as required'
                } else {
                    Add-Result -Kind attack -Id attack.ascii.neg -Name 'ASCII gate negative: clean file' -Status RED `
                        -Detail "refused a pure-ASCII file (exit $($r2.ExitCode)) -- a gate that cries wolf gets routed around" `
                        -Evidence @("said: $(Get-FirstLine $r2.StdOut 220)")
                }

                # 3. FAIL-CLOSED CONTROL. A run that examined nothing must not exit 0: a scan of an
                #    empty directory is the exact shape of a misconfigured path in CI, and 0 there is
                #    a green result that measured nothing.
                $r3 = Invoke-PwshProbe -Script $asciiSrc -ScriptArgs @('-Path', $fxAsciiEmpty) -TimeoutSeconds $AttackTimeoutSeconds
                if (-not $r3.Ran) {
                    Add-Result -Kind attack -Id attack.ascii.nothing -Name 'ASCII gate: scanned nothing' -Status '??' `
                        -Detail "probe could not run: $($r3.Error)"
                } elseif ($r3.ExitCode -eq 2) {
                    Add-Result -Kind attack -Id attack.ascii.nothing -Name 'ASCII gate: scanned nothing' -Status OK `
                        -Detail 'a scan of zero files exits 2, so an empty run cannot read as a pass'
                } elseif ($r3.ExitCode -eq 0) {
                    Add-Result -Kind attack -Id attack.ascii.nothing -Name 'ASCII gate: scanned nothing' -Status RED `
                        -Detail 'it reported SUCCESS having scanned nothing -- the failure mode this whole command exists for' `
                        -Evidence @("said: $(Get-FirstLine $r3.StdOut 220)")
                } else {
                    Add-Result -Kind attack -Id attack.ascii.nothing -Name 'ASCII gate: scanned nothing' -Status RED `
                        -Detail "unexpected exit $($r3.ExitCode) on an empty directory" -Evidence @("said: $(Get-FirstLine $r3.StdOut 220)")
                }
            } finally {
                # The outer finally removes the whole fixture, but the planted character is the one
                # artefact in this run that would fail every other check in the repository if it were
                # ever left behind, so it is removed by its own guaranteed path as well.
                if (Test-Path -LiteralPath $fxAscii) {
                    Remove-Item -LiteralPath $fxAscii -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # ------------------------------------------------------------------- allocator read probe --
        # Allocation is a one-way door, so the only safe way to prove the allocator works is its
        # read-only floor probe. It never spends a number.
        if ($cfg.sequences.Count -gt 0) {
            $kind = @($cfg.sequences.Keys | Sort-Object)[0]
            $r = Invoke-PwshProbe -Script (Join-Path $RepoSrcRoot 'scripts/coord/alloc.ps1') `
                -ScriptArgs @('-Kind', $kind, '-ShowFloor') -WorkingDirectory $repoRoot -TimeoutSeconds $AttackTimeoutSeconds
            if (-not $r.Ran) {
                Add-Result -Kind probe -Id probe.alloc -Name "allocator: read-only floor ($kind)" -Status '??' -Detail "probe could not run: $($r.Error)"
            } elseif ($r.ExitCode -eq 0) {
                Add-Result -Kind probe -Id probe.alloc -Name "allocator: read-only floor ($kind)" -Status OK `
                    -Detail 'computed a floor without spending a number' -Evidence @(Get-FirstLine $r.StdOut 220)
            } else {
                Add-Result -Kind probe -Id probe.alloc -Name "allocator: read-only floor ($kind)" -Status RED `
                    -Detail "the allocator could not compute its floor (exit $($r.ExitCode))" -Evidence @(Get-FirstLine ($r.StdErr + ' ' + $r.StdOut) 260)
            }
        } else {
            Add-Result -Kind probe -Id probe.alloc -Name 'allocator: read-only floor' -Status '--' -Detail 'no sequences configured' -Required $false
        }

        # PAIRED WITH THE PROBE ABOVE -- and NOT a negative control, because there is no such thing
        # here: the allocator refuses nothing, so there is no "ordinary action it must allow" to pair
        # a refusal against. The property that stands in its place is the one that can actually be
        # violated. Allocation is a ONE-WAY DOOR, so an inspection that moves the thing it inspects
        # is not an inspection -- and that has failed before: the first -ShowFloor run against a
        # deliberately planted number ratcheted that clone's high-water mark to a fabricated floor no
        # later run could undo.
        #
        # It fires in a THROWAWAY repository, never against yours, for the obvious reason: proving a
        # read is read-only by watching what it writes means being willing to see it write.
        #
        # THE PLANTED NUMBER IS LOAD-BEARING. With an empty sequence the computed floor is 0, equal
        # to the recorded high-water, and the ratchet writes nothing whether or not the run peeked --
        # so the check would pass on an allocator that had lost -Peek entirely. Planting 42 puts the
        # computed floor above the high-water, which is exactly the condition under which a
        # non-peeking run DOES write. The assertion can therefore fail.
        if (-not $gitExe) {
            Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status '??' `
                -Detail 'git is not on PATH, so no fixture repository could be built'
        } else {
            $fxAlloc = Join-Path $fixture 'alloc'
            $null = New-Item -ItemType Directory -Force -Path (Join-Path $fxAlloc 'docs/adr')
            function Invoke-AllocGit { param([string[]]$GitArgs) return (Invoke-Probe -FilePath $gitExe -ArgumentList $GitArgs -WorkingDirectory $fxAlloc -TimeoutSeconds 60) }
            $null = Invoke-AllocGit @('init', '-q', '-b', 'main', '.')
            $null = Invoke-AllocGit @('config', 'user.email', 'doctor@example.invalid')
            $null = Invoke-AllocGit @('config', 'user.name', 'ccx doctor')
            # No backslashes anywhere in this config, for the same reason as the fixture above: an
            # escape carried through a here-string into JSON makes the config unparseable, and a tool
            # that refuses because its config would not load reads exactly like a tool that refused.
            @"
{
  "prefix": "$($cfg.prefix)",
  "trunk": "main",
  "sequences": { "adr": { "dir": "docs/adr", "filePattern": "^docs/adr/([0-9]+)-", "pad": 4 } }
}
"@ | Set-Content -LiteralPath (Join-Path $fxAlloc 'ccx.config.json') -Encoding utf8NoBOM
            Set-Content -LiteralPath (Join-Path $fxAlloc 'docs/adr/0042-planted.md') -Value '# planted' -Encoding utf8NoBOM
            $null = Invoke-AllocGit @('add', '.')
            $null = Invoke-AllocGit @('commit', '-q', '-m', 'planted')

            $ra = Invoke-PwshProbe -Script (Join-Path $RepoSrcRoot 'scripts/coord/alloc.ps1') `
                -ScriptArgs @('-Kind', 'adr', '-ShowFloor') -WorkingDirectory $fxAlloc `
                -Environment @{ CCX_CONFIG = $null } -TimeoutSeconds $AttackTimeoutSeconds
            # Ask the tool where its registry is rather than re-deriving the path here. A checker that
            # computes the location itself can look at the wrong directory and report a clean one.
            $wmLine = @(("$($ra.StdOut)" -split "`r?`n") | Where-Object { $_ -match '^\s*watermark\s*:' }) | Select-Object -First 1
            $watermark = if ($wmLine) { ($wmLine -replace '^\s*watermark\s*:\s*', '').Trim() } else { $null }
            $allocDir = if ($watermark) { Split-Path -Parent $watermark } else { $null }
            $sawPlanted = ("$($ra.StdOut)" -match '(?m)^\s*floor\s*:\s*42\b')
            $spent = @()
            if ($watermark -and (Test-Path -LiteralPath $watermark -PathType Leaf)) { $spent += "the high-water ratchet was WRITTEN: $watermark" }
            if ($allocDir -and (Test-Path -LiteralPath $allocDir)) {
                $claims = @(Get-ChildItem -LiteralPath $allocDir -Filter *.json -ErrorAction SilentlyContinue)
                if ($claims.Count -gt 0) { $spent += "$($claims.Count) number(s) were ALLOCATED: $(@($claims | ForEach-Object { $_.Name }) -join ', ')" }
            }
            $eva = @("fixture: $fxAlloc (planted docs/adr/0042-planted.md)", "exit $($ra.ExitCode)",
                "registry: $(if ($allocDir) { $allocDir } else { '(the run never named one)' })",
                "said: $(Get-FirstLine $ra.StdOut 220)")
            if (-not $ra.Ran) {
                Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status '??' `
                    -Detail "probe could not run: $($ra.Error)" -Evidence $eva
            } elseif ($ra.ExitCode -ne 0 -or -not $watermark) {
                Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status '??' `
                    -Detail "the fixture run did not complete (exit $($ra.ExitCode)), so nothing can be concluded about what it wrote" `
                    -Evidence (@($eva) + @("stderr: $(Get-FirstLine $ra.StdErr 260)"))
            } elseif (-not $sawPlanted) {
                # It wrote nothing -- but a sweep that saw nothing writes nothing either, and that is
                # the shape of a green result that measured nothing.
                Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status RED `
                    -Detail 'it never found the planted number 42, so its silence about writing proves nothing -- the sweep did not see the sequence at all' `
                    -Evidence $eva
            } elseif ($spent.Count -gt 0) {
                Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status RED `
                    -Detail 'the READ-ONLY inspection MUTATED the allocator -- a one-way door that an inspection can push through' `
                    -Evidence (@($eva) + $spent)
            } else {
                Add-Result -Kind probe -Id probe.alloc.readonly -Name 'allocator: -ShowFloor spends nothing' -Status OK `
                    -Detail 'swept the planted number, allocated nothing, and left the high-water ratchet unwritten' -Evidence $eva
            }
        }
    } catch {
        # An assertion inside the attack section (a payload that would not build, a fixture that would
        # not initialise) cancels the attacks that had not run yet. Those must be REPORTED, not
        # dropped: an attack that never fired is the exact silence this command exists to remove.
        Add-Result -Kind attack -Id attack.aborted -Name 'attack sequence' -Status '??' `
            -Detail "ABORTED: $($_.Exception.Message). Any attack not listed above was never fired."
    } finally {
        if ($fixture -and (Test-Path -LiteralPath $fixture)) {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ==================================================================================================
# 4. BLIND SPOTS -- printed on every run, pass or fail
# ==================================================================================================

Add-BlindSpot ('DELIVERY MCP. Announce does not send anything itself: it resolves peers and asks the model ' +
    'to send via a session-management MCP server that the desktop client provides and a plain CLI install ' +
    'does NOT have. This command cannot see whether that server is connected. Where it is absent the hook ' +
    'still fires, still finds peers, and then instructs the model to call tools it does not have -- announce ' +
    'is decorative there.')
Add-BlindSpot ('SESSION RECORD SCHEMA. Every liveness answer rests on a per-session JSON record written by the ' +
    'client. That is a vendor contract, not ours, and its two failure modes do NOT look alike here. A moved ' +
    'directory or a removed record turns the counts printed above into zeros. A renamed field or a changed ' +
    'unit leaves those counts untouched, because such records still parse and still place -- every verdict ' +
    'simply becomes UNVERIFIED, which vetoes, so the gates keep refusing rather than waving work through. ' +
    'The census is the instrument for the first kind only; a healthy count is not evidence of a matching schema.')
Add-BlindSpot ('LIST-SESSIONS BLINDNESS. The client-side session listing tool enumerates only sessions the ' +
    'desktop app itself spawned; an editor-extension session is never entered into it. This command reads the ' +
    'on-disk registry for that reason, but no roster anywhere is guaranteed complete.')
if (-not $IsWindows) {
    Add-BlindSpot ('NON-WINDOWS. Self-marking in the roster depends on a process table read through `ps`, and path ' +
        'comparison does NOT case-fold on a case-sensitive filesystem -- a governed path spelled in another case ' +
        'is simply not matched. Both degrade quietly here.')
}
if (-not $python) {
    Add-BlindSpot ('NO PYTHON. The git-hook shims fail OPEN: with no interpreter they print to stderr and exit 0, ' +
        'so every commit and every push passes. THE GIT GATES ARE OFF.')
}
Add-BlindSpot ('BYPASSES. `--no-verify` skips both git hooks and nothing local records that it happened. The ' +
    'PreToolUse gates inspect tool ARGUMENTS, so a file written by a shell command -- or by any agent-authored ' +
    'script -- is invisible to them. These are guardrails against accidents, not security boundaries.')
Add-BlindSpot ('SCOPE. Only this clone, and only the config roots listed under WHAT WAS SCANNED, were examined. ' +
    'Another clone has its own git hooks; another config root has its own wiring. A running session keeps the ' +
    'configuration it booted with, so nothing here changes one.')
Add-BlindSpot ('THE COLLISION GATE''S DENY PATH IS NOT PROVEN HERE. It needs a live peer worktree holding an ' +
    'uncommitted change to the same file, which this command will not manufacture. What was proven is the pair ' +
    'either side of it: that the gate says so when it cannot check, and that it stays silent when it CAN check ' +
    'and the file is clear. The refusal itself is unproven on every run.')
Add-BlindSpot ('THE BACKSTOP''S REFUSAL WAS PROVEN AGAINST A THROWAWAY REPOSITORY, NOT YOURS. A drifted, dirty ' +
    'fixture is put in front of it and it must decline and say why -- but your primary is never drifted by this ' +
    'command, so what is proven is the rule, not its behaviour on your checkout. Two cases are outside that ' +
    'proof entirely: a DETACHED head, which the backstop deliberately does not treat as drift because nothing ' +
    'can say which branch it was meant to be on, and a repository whose home branch cannot be resolved at all, ' +
    'where it also does nothing. Both are silent no-ops.')
Add-BlindSpot ('THE ALLOCATOR HAS NO NEGATIVE CONTROL, BECAUSE IT REFUSES NOTHING. There is no ordinary action ' +
    'for it to allow, so the pairing is a different property: a planted number in a throwaway repository, and ' +
    'the read-only floor inspection must both SEE it and leave the registry and the high-water ratchet ' +
    'unwritten. What that does NOT cover is a real allocation -- spending a number is a one-way door, so this ' +
    'command never takes one, and the write path is exercised only by using it for real.')
Add-BlindSpot ('THE SESSION BANNER MAKES NO DECISION, so there is nothing to attack: it is reported by receipt ' +
    'and resolution only.')
# "It was proven able to refuse above" is a claim about THIS RUN, so it is read off this run's ledger
# rather than asserted. Printing it unconditionally made the doctor state, in its own blind-spot
# section, that an attack had passed when the checker was absent and every ASCII attack was reported
# '??' -- a false claim about a control, in the one command whose entire purpose is refusing to make
# them. The verdict is the result row; the prose only reports it.
$asciiAttack = @($script:Results | Where-Object { $_.id -eq 'attack.ascii' })
$asciiProven = if ($asciiAttack.Count -eq 0) {
    'It was NOT fired on this run, so nothing here says it can still refuse a character, and no'
} elseif ($asciiAttack[0].status -eq 'OK') {
    'It was proven able to refuse above, but no'
} else {
    "It did NOT pass on this run (it is reported '$($asciiAttack[0].status)' above), so treat it as unproven here, and no"
}
Add-BlindSpot ("THE ASCII GATE IS NOT WIRED TO ANYTHING BY DEFAULT. $asciiProven " +
    'shipped installer runs it: it sees a file only when someone runs it, and it reads the working tree, so a ' +
    'character written after the run is unscanned until the next one. Run it in your own pre-commit hook and in ' +
    'CI. It also cannot see a character that never reaches disk -- one produced only in a terminal, or in a ' +
    'string built at run time from a code point.')

Say ''
Say 'BLIND SPOTS ON THIS RUN (printed whether or not anything failed)'
foreach ($b in $script:BlindSpots) {
    $first = $true
    foreach ($w in (Format-Wrapped $b)) {
        Say ("  {0} {1}" -f $(if ($first) { '*' } else { ' ' }), $w)
        $first = $false
    }
}

# ==================================================================================================
# 5. VERDICT
# ==================================================================================================

$red = @($script:Results | Where-Object { $_.status -eq 'RED' })
$offRequired = @($script:Results | Where-Object { $_.status -eq 'OFF' -and $_.required })
# An OFF row that does not fail the run is still an OFF row that was PRINTED above. Counted nowhere
# and named nowhere, it turns the verdict into a number that does not reconcile with the list beside
# it -- the exact defect this command is built to refuse. It gets its own count and its own lines.
$offOptional = @($script:Results | Where-Object { $_.status -eq 'OFF' -and -not $_.required })
$unknown = @($script:Results | Where-Object { $_.status -eq '??' })

$exit = 0
if ($red.Count -gt 0 -or $offRequired.Count -gt 0) { $exit = 1 }
elseif ($unknown.Count -gt 0) { $exit = 2 }

Say ''
Say 'VERDICT'
Say "  checks       : $($script:Results.Count)"
Say "  RED          : $($red.Count)   (proven broken, or it allowed what it must deny)"
Say "  OFF          : $($offRequired.Count)   (implemented, but nothing invokes it -- zero enforcement)"
if ($offOptional.Count -gt 0) {
    Say "  OFF (opt-in) : $($offOptional.Count)   (also zero enforcement, but no shipped installer wires it, so it does not fail this run)"
}
Say "  undetermined : $($unknown.Count)   (not tested, or could not be answered -- never read these as passes)"
foreach ($r in @($red + $offRequired + $unknown)) { Say "    [$($r.status)] $($r.name): $($r.detail)" }
foreach ($r in $offOptional) { Say "    [$($r.status)] (opt-in) $($r.name): $($r.detail)" }
Say ''
switch ($exit) {
    0 { Say 'EXIT 0 -- every required control is installed and wired, and every attack was refused.' }
    1 { Say 'EXIT 1 -- at least one control is broken or absent. The guardrails you appear to have are not all there.' }
    2 { Say 'EXIT 2 -- could not determine. Nothing above was proven false; something could not be answered, and this command will not guess.' }
}
Say ''

if ($Json) {
    $doc = [ordered]@{
        tool         = 'ccx-doctor'
        version      = $DoctorVersion
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        exitCode     = $exit
        scanned      = [ordered]@{
            repoRoot           = $repoRoot
            repoWasExplicit    = [bool]$Repo
            toolingRoot        = $RepoSrcRoot
            examiningItself    = [bool]$examiningSelf
            primaryRoot        = $primaryRoot
            worktrees          = @($worktrees)
            configFile         = $cfg.ConfigPath
            prefix             = $cfg.prefix
            sequences          = @($cfg.sequences.Keys)
            trunk              = $trunk
            stateRoot          = $stateRoot
            gitHooksDir        = $gitHooksDir
            clientHooksDir     = $hooksDir
            configRoots        = @($ConfigDir)
            configRootsSkipped = @($configScan.Skipped)
            settingsPath       = $SettingsPath
            sessionRecordsRead = $(if ($occ) { $occ.RecordsExamined } else { $null })
            sessionRecordsUnplaceable = $(if ($occ) { $occ.RecordsUnplaceable } else { $null })
            rosterAvailable    = $(if ($occ) { [bool]$occ.Available } else { $null })
            python             = $(if ($python) { "$($python.Path) [$($python.How)] $($python.Version)" } else { $null })
            git                = $gitExe
            platform           = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Trim()
            attacksFired       = (-not $SkipAttacks)
        }
        results      = @($script:Results)
        blindSpots   = @($script:BlindSpots)
    }
    [Console]::Out.WriteLine(($doc | ConvertTo-Json -Depth 8))
}

exit $exit
