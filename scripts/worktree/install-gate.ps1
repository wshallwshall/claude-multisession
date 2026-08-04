#Requires -Version 7.3
<#
.SYNOPSIS
    Install (or remove, or audit) the worktree gate -- a PreToolUse hook that stops sessions BUILDING
    in the shared primary checkout, and hijacking a linked worktree onto another session's branch.

.DESCRIPTION
    Copies scripts/hooks/worktree_gate.ps1 to a shared USER-scope location (~/.claude/hooks/) and
    registers it as a PreToolUse hook in the settings.json of EVERY Claude config dir on this machine:
    ~/.claude (the default) AND each ~/.claude-account-* that carries a marker the client itself
    writes -- projects/, sessions/ or .claude.json. The bare glob is not enough: it also matches a
    launcher's .lock artefact, which on a real machine is a DIRECTORY, and wiring one means copying
    the gate and writing settings INTO a lock file. Rejected candidates are printed with the reason.
    Override the set with -ConfigDir, which bypasses the test.

    WHY EVERY CONFIG DIR. Wiring only ~/.claude leaves every other login UNGATED -- and those are
    where parallel editor-hosted chats run. A session running under an ungoverned login checked its
    own branch out inside another session's linked worktree, silently swapping that session's files
    mid-task; the gate that would have blocked it was simply not installed there.

    WHY USER SCOPE, and why an installed COPY:

      * Reach. A hook in the project's .claude/settings.json is git-tracked, so it lives on ONE branch
        and does not exist in the other worktrees until each of them merges it. A user-scope hook
        governs every session on the machine the moment it is written. Hook definitions from the user,
        project and local scopes are unioned, so this ADDS to the repo's own guards rather than
        replacing them.

      * Survivability. The command must not point into a working tree. The primary checkout is
        routinely on a detached HEAD or an old commit; a hook whose script path lives there vanishes
        on a checkout, and a hook whose script is MISSING exits non-zero-but-not-2 -- which means the
        tool call RUNS ANYWAY, silently. The gate would be off in every session and nothing would say
        so. So we install a copy outside every tree (once, shared, referenced by absolute path from
        each login) and re-copy it on each install.

    The gate only governs the checkouts listed in the allowlist. That file IS the kill switch:
    -Uninstall removes it (and the hook entries from every config dir).

    WHICH CHECKOUT GETS GOVERNED, AND WHY IT REFUSES TO GUESS. -Repo names the primary checkout(s) to
    govern. With no -Repo the target is the primary of the clone you are STANDING IN, and that has to
    agree with the clone this script ships from -- when they differ, this script stops and makes you
    say which. The gate SOURCE always comes from this script's own checkout; the two are separate
    questions and were previously answered by one variable, so installing from a tooling checkout
    governed the tooling checkout while every status line agreed it was fine.

    Run from a PLAIN TERMINAL, not from inside Claude Code -- a session that can install its own gate
    can uninstall it. The script refuses when $env:CLAUDECODE is set. -Status is exempt: auditing is
    not installing, and a session that cannot see whether the gate is current has no way to notice the
    one failure this whole file exists to surface.

.EXAMPLE
    pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Repo <path-to-the-primary-to-govern>
    pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Repo <path-a>,<path-b>
    pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -ConfigDir <path-to-a-config-dir>
    pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Uninstall
    pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status
#>
[CmdletBinding()]
param(
    # Primary checkout(s) to govern. Unset, it is the MAIN working tree of the clone you are standing
    # in -- and the install refuses outright when that is not the clone this script ships from, rather
    # than governing whichever one it can see. Takes several paths.
    [string[]]$Repo,
    [switch]$Uninstall,
    [switch]$Status,
    # Do not gate Task/Agent/Workflow dispatch from the primary (writes are still gated).
    #
    # THIS DROPS A RULE, and an install flag that drops a rule must never do it quietly: the rule is
    # still implemented, so -Status will report the dispatch tools as UNWIRED -- implemented but
    # never firing -- and the install below prints a warning. If you want it off, you should have to
    # keep seeing that you turned it off.
    [switch]$NoDispatchGate,
    # Gate the tool that relocates a LIVE session into a worktree (rule 4).
    #
    # OPT-IN, and deliberately OFF by default. With the dispatch rule and this one both live, a
    # session started in the primary has no in-session path to isolation at all -- it can neither
    # dispatch a subagent nor relocate itself, so a human must restart it elsewhere. That is a hard
    # stop on the way sessions naturally open, and it is a decision to make on purpose rather than one
    # that rides along with an unrelated install.
    #
    # Recent harness versions also raise their own confirmation prompt when relocating a session
    # outside the harness's own worktree directory, and re-file the transcript to follow the
    # session's cwd. Check what your version does before relying on either.
    [switch]$EnterWorktreeGate,
    # Config dirs to wire the hook into. Default: ~/.claude plus every ~/.claude-account-* that looks
    # like a config root (see the .DESCRIPTION). Naming one here bypasses that test -- an operator
    # naming a directory outranks a heuristic -- and a path that is not a directory is reported, not
    # dropped.
    [string[]]$ConfigDir
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "../coord/_common.ps1")

# Where the gate SOURCE lives: this script's own checkout. That is correct here (we are copying a
# file that ships beside us) and is NOT how the governed repo is chosen -- see the -Repo default,
# which anchors on the primary instead.
$ScriptRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$SrcGate = Join-Path $ScriptRepoRoot "scripts/hooks/worktree_gate.ps1"

# The gate SCRIPT + its allowlist live ONCE, shared, under ~/.claude/hooks -- referenced by absolute
# path from every config dir's settings.json, so a single copy (and a single kill switch) governs all
# logins.
#
# Null-safely: $env:USERPROFILE is Windows-only and NULL elsewhere, where Join-Path throws a
# parameter-binding error instead of returning a path. Same idiom as its sibling scripts.
$HomeDir   = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
$HooksDir  = Join-Path $HomeDir ".claude/hooks"
$GateDst   = Join-Path $HooksDir "worktree_gate.ps1"

# ONE allowlist file, at a fixed name, shared with the SessionStart backstop (worktree-selfheal.ps1).
# It is deliberately NOT derived from ccx.config.json's `prefix`: this file lives OUTSIDE any
# repository, is read by an installed copy that cannot see a repo's config, and is shared by two
# separately-installed components. Two components deriving one filename from a per-repo setting is
# how they end up reading different files and agreeing only by luck.
$ReposFile = Join-Path $HooksDir "ccx-gate.repos.txt"

# Marker so we can find (and remove) exactly the entries we added, without disturbing other hooks.
$Marker = "worktree_gate.ps1"

# Config dirs to wire. Default: ~/.claude + every ~/.claude-account-* that is actually a config root
# (the alternate-login launchers). That naming convention is a convention, not a guarantee -- pass
# -ConfigDir if yours differ.
#
# NOT A BARE GLOB, and Resolve-CcxClientConfigRoot explains why at length: the pattern also matches a
# launcher's `.lock` artefact, which on a real machine is a DIRECTORY. Wiring one means copying the
# gate and writing settings INTO a lock file -- an install that prints success and governs nothing.
# Every rejected candidate comes back in .Skipped and is printed, on every path through this script:
# a silent skip reads exactly like a candidate that was never there.
$configScan = Resolve-CcxClientConfigRoot -HomeDirectory $HomeDir -Explicit $ConfigDir
$ConfigDir = @($configScan.Roots)

function Write-SkippedConfigRoot {
    if (@($configScan.Skipped).Count -eq 0) { return }
    Write-Host "skipped     : $(@($configScan.Skipped).Count) candidate(s) under $HomeDir that are NOT config roots"
    foreach ($s in $configScan.Skipped) { Write-Host "              $($s.Path)  --  $($s.Reason)" }
}

function Read-Settings([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{} }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [ordered]@{} }
    try { return ($raw | ConvertFrom-Json -AsHashtable) }
    catch { throw "$Path is not valid JSON -- fix it by hand before installing (it is live config for every session)." }
}

function Write-Settings([string]$Path, $Data) {
    # Two sessions installing at once could interleave a read-modify-write and leave INVALID JSON,
    # which would break hooks in every session on the machine at once. Serialize to a temp file, parse
    # it back to prove it is valid, keep a backup, then move it into place in one operation. Done PER
    # FILE, so a failure wiring one config dir can never corrupt another.
    $json = $Data | ConvertTo-Json -Depth 20
    $null = $json | ConvertFrom-Json      # throws before we touch the real file
    $tmp = "$Path.tmp-$PID"
    Set-Content -LiteralPath $tmp -Value $json -Encoding utf8
    if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path "$Path.bak" -Force }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Remove-GateHooks($Data) {
    if (-not $Data.hooks -or -not $Data.hooks.PreToolUse) { return $Data }
    $kept = @(
        $Data.hooks.PreToolUse | Where-Object {
            $entry = $_
            -not (@($entry.hooks) | Where-Object { "$($_.command)" -like "*$Marker*" })
        }
    )
    if ($kept.Count -gt 0) { $Data.hooks.PreToolUse = $kept }
    else { $null = $Data.hooks.Remove("PreToolUse") }
    return $Data
}

function Get-GateVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $m = [regex]::Match((Get-Content -LiteralPath $Path -Raw), '\$GateVersion\s*=\s*"([^"]+)"')
    if ($m.Success) { $m.Groups[1].Value } else { "(unstamped)" }
}

function Get-GateHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

# Every tool a gate script branches on. -Status calls this on the INSTALLED copy, deliberately: the
# question it answers is "which rules does the gate that is RUNNING have, and are they all wired",
# and the source's rule set is not evidence for either. That is the whole point of the audit -- a
# rule can sit in the source, be declared by this installer, and be covered by green tests, while the
# gate that actually runs has never heard of it.
function Get-HandledTools([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $text = Get-Content -LiteralPath $Path -Raw
    $tools = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($text, '\$tool\s+-(?:not)?in\s+@\(([^)]*)\)')) {
        foreach ($q in [regex]::Matches($m.Groups[1].Value, '"([^"]+)"')) { $null = $tools.Add($q.Groups[1].Value) }
    }
    @($tools)
}

# ------------------------------------------------------------------------------------------ status
# NB this branch runs BEFORE the CLAUDECODE refusal below, deliberately. Auditing is not installing.
#
# RECEIPT DISCIPLINE. "INSTALLED" is answered by hashing the file on disk -- never by whether a
# settings.json mentions it. A settings entry pointing at a script that is not there is byte-identical
# to a healthy hook with nothing to say. "WIRED" is the one fact that can only come from settings; it
# is reported on its own line and never conflated with INSTALLED.
if ($Status) {
    $iVer = Get-GateVersion $GateDst ; $sVer = Get-GateVersion $SrcGate
    $iSha = Get-GateHash    $GateDst ; $sSha = Get-GateHash    $SrcGate

    # Print the SHA alongside the version. The version is a hand-bumped label and can disagree with
    # reality -- it has: rules shipped without a bump, so both lines read the same version directly
    # above a STALE verdict. Showing the hash makes agreement VISIBLE instead of asserted.
    # Lowercased: Get-FileHash returns uppercase and every other hash a reader sees (git, the parity
    # test's output) is lowercase, and two spellings of one digest invite a false "these differ".
    $shortSha = { param($h) if ($h) { " sha $($h.Substring(0, 12).ToLowerInvariant())" } else { "" } }
    Write-Host "installed   : $(if ($iSha) { "$GateDst  v$iVer$(& $shortSha $iSha)" } else { 'NOT installed' })"
    Write-Host "source      : $(if ($sSha) { "$SrcGate  v$sVer$(& $shortSha $sSha)" } else { 'NOT FOUND' })"
    if ($iSha -and $sSha) {
        if ($iSha -eq $sSha) {
            Write-Host "parity      : IN SYNC" -ForegroundColor Green
        } else {
            Write-Host "parity      : *** STALE *** the running gate is NOT this checkout's script." -ForegroundColor Red
            Write-Host "              Re-run this installer to update it. Until you do, rules added or"
            Write-Host "              removed in source have no effect, and the tests still pass."
        }
    }

    if (Test-Path -LiteralPath $ReposFile) {
        Write-Host "governing   :"
        Get-Content -LiteralPath $ReposFile | Where-Object { $_ -and -not $_.StartsWith('#') } |
            ForEach-Object { Write-Host "              $_" }
    } else {
        Write-Host "governing   : nothing (no allowlist -> gate is OFF)"
    }

    # Compare the wired matchers against the rules the INSTALLED script actually implements -- an
    # expectation, not a count. A count of "3" is not information unless you know whether 3 is right.
    $handled = @(Get-HandledTools $GateDst)
    foreach ($cd in $ConfigDir) {
        $sp = Join-Path $cd "settings.json"
        $s = Read-Settings $sp
        $wired = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($e in @($s.hooks.PreToolUse)) {
            if (@($e.hooks) | Where-Object { "$($_.command)" -like "*$Marker*" }) {
                foreach ($t in "$($e.matcher)".Split("|")) { if ($t) { $null = $wired.Add($t) } }
            }
        }
        # Rules that are deliberately unwired are reported as such, never as UNWIRED. A status line
        # that cries wolf about a known-and-intended state is one a reader learns to skip, which is
        # how a real UNWIRED goes unnoticed -- the exact failure this block exists to surface.
        $optIn   = @("EnterWorktree")
        $absent  = @($handled | Where-Object { -not $wired.Contains($_) })
        $missing = @($absent  | Where-Object { $optIn -notcontains $_ } | Sort-Object)
        $offByChoice = @($absent | Where-Object { $optIn -contains $_ } | Sort-Object)
        $stray   = @($wired   | Where-Object { $handled -notcontains $_ } | Sort-Object)
        Write-Host "wiring      : $sp"
        Write-Host "              matched  : $(@($wired | Sort-Object) -join ', ')"
        if ($offByChoice) {
            Write-Host "              opt-in   : $($offByChoice -join ', ')  <- off by default, add -EnterWorktreeGate to enable"
        }
        if ($missing) {
            Write-Host "              UNWIRED  : $($missing -join ', ')  <- implemented but NEVER FIRES" -ForegroundColor Yellow
        }
        if ($stray) {
            Write-Host "              stray    : $($stray -join ', ')  <- matched but the script ignores it" -ForegroundColor Yellow
        }
    }
    # Say what was scanned, AND what was passed over. A skip must never read as a pass.
    Write-Host ""
    Write-SkippedConfigRoot
    Write-Host "scanned $($ConfigDir.Count) config dir(s) against $(@($handled).Count) rule(s) implemented by the INSTALLED gate."
    return
}

if ($env:CLAUDECODE -eq "1") {
    throw "Refusing to run inside Claude Code. A session that can install this gate can also remove it. Run from a plain pwsh terminal. (-Status is allowed from a session: auditing is not installing.)"
}

# --------------------------------------------------------------------------------------- uninstall
if ($Uninstall) {
    foreach ($cd in $ConfigDir) {
        $sp = Join-Path $cd "settings.json"
        if (-not (Test-Path -LiteralPath $sp)) { continue }
        Write-Settings $sp (Remove-GateHooks (Read-Settings $sp))
    }
    Remove-Item -LiteralPath $ReposFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $GateDst   -Force -ErrorAction SilentlyContinue
    Write-SkippedConfigRoot
    Write-Host "Worktree gate REMOVED from $($ConfigDir.Count) config dir(s). Sessions are no longer gated (takes effect immediately)." -ForegroundColor Yellow
    Write-Host "The SessionStart backstop shares this allowlist and is now inert too."
    return
}

# ----------------------------------------------------------------------------------------- install
if (-not (Test-Path -LiteralPath $SrcGate)) {
    throw "Gate source not found at $SrcGate. Installing an absent script would wire a hook that exits non-zero on every call and enforces nothing."
}

# Print the rejected candidates BEFORE anything is written, so the reader sees them whether or not
# the install goes on to succeed -- and refuse outright rather than "wiring" nothing. Zero config
# roots means zero enforcement, and an installer that prints a green receipt over an empty list is
# the precise shape of failure this whole toolkit exists to remove.
Write-SkippedConfigRoot
if ($ConfigDir.Count -eq 0) {
    throw ("No config root to wire. Nothing under $HomeDir qualifies (see the skipped list above, if " +
        "any), so installing here would copy the gate and govern nothing while printing success. " +
        "Name one explicitly: -ConfigDir <path-to-a-config-dir>.")
}

if (-not $Repo -or $Repo.Count -eq 0) {
    # WHAT GETS GOVERNED IS THE MAIN WORKING TREE, never wherever this script happens to be running
    # from. You will usually install FROM a worktree (that is the whole point of the gate), and
    # governing that worktree instead of the primary would be exactly backwards.
    #
    # AND IT REFUSES TO GUESS WHICH CLONE'S PRIMARY. This used to resolve the primary of THIS
    # SCRIPT'S clone, so running the tooling checkout's installer while standing in the repository you
    # wanted governed put the tooling checkout in the allowlist -- and every subsequent status line,
    # receipt and doctor run then agreed, confidently, about the wrong repository. The clone you are
    # standing in is the only available signal about intent, so it must agree with the one this script
    # ships from; where they disagree, stop and make the reader say which.
    $cwdPrimary = Get-CcxPrimaryRoot
    if (-not $cwdPrimary) {
        throw ("Cannot tell which checkout to govern: '$($PWD.Path)' is not inside a git repository, " +
            "and this script's own checkout ($ScriptRepoRoot) is only where the GATE SCRIPT is copied " +
            "from -- it is not evidence of what you meant to govern. Name the target: " +
            "-Repo <path-to-the-primary-checkout-you-want-governed>.")
    }
    $scriptPrimary = Get-CcxPrimaryRoot -Repo $ScriptRepoRoot
    if ($scriptPrimary -and
        (ConvertTo-CcxComparablePath -Path $scriptPrimary) -ne (ConvertTo-CcxComparablePath -Path $cwdPrimary)) {
        throw ("Refusing to guess which checkout to govern. You are standing in a clone whose primary " +
            "is '$cwdPrimary', but this script ships from one whose primary is '$scriptPrimary'. " +
            "Governing the wrong one leaves the gate installed, wired, hashing correctly and blind to " +
            "every write you make. Say which one you mean:" + [Environment]::NewLine +
            "    -Repo `"$cwdPrimary`"   (the primary of the clone you are standing in)")
    }
    $Repo = @($cwdPrimary)
}

$resolved = foreach ($r in $Repo) {
    $p = (Resolve-Path -LiteralPath $r -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath (Join-Path $p ".git"))) { throw "Not a git checkout: $p" }
    $p
}

New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

# The gate dot-sources _command.ps1 and _gittarget.ps1, and _gittarget.ps1 in turn requires
# _common.ps1 -- see worktree_gate.ps1 .NOTES, which already says the installer must place all of
# them. Copying the gate alone does not yield a degraded gate: the dot-source fails, the gate exits 0
# after a stderr receipt, and the result is a gate that IS NOT ENFORCING while every file the
# installer talks about is present and hashes correctly. Copy the closure; verify by re-reading.
$GateHelpers = @(
    @{ Src = (Join-Path $ScriptRepoRoot "scripts/hooks/_command.ps1");   Dst = (Join-Path $HooksDir "_command.ps1") }
    @{ Src = (Join-Path $ScriptRepoRoot "scripts/hooks/_gittarget.ps1"); Dst = (Join-Path $HooksDir "_gittarget.ps1") }
    @{ Src = (Join-Path $ScriptRepoRoot "scripts/coord/_common.ps1");    Dst = (Join-Path $HooksDir "_common.ps1") }
)
foreach ($h in $GateHelpers) {
    if (-not (Test-Path -LiteralPath $h.Src -PathType Leaf)) {
        throw ("Gate helper missing from this checkout: $($h.Src). Refusing to install a gate that " +
            "would fail its dot-source and silently stop enforcing.")
    }
}

Copy-Item -LiteralPath $SrcGate -Destination $GateDst -Force
foreach ($h in $GateHelpers) {
    Copy-Item -LiteralPath $h.Src -Destination $h.Dst -Force
    # HASH BOTH SIDES; do not merely test for existence. `Test-Path` answers "a file with that name is
    # there", which is a different sentence from "the bytes that will be dot-sourced are the bytes we
    # shipped": it cannot see a truncated copy, a half-written file, or one another tool replaced
    # between the copy and the check. This line used to be a Test-Path while its own throw message
    # claimed it had read the file back -- the exact claim-versus-code defect this gate exists to
    # catch, shipped inside the gate. Its sibling install-git-hooks.ps1 hashes both sides; the parity
    # between the two installers is deliberate, and tests/test_installer_copy_lists.py pins it.
    $srcSha = Get-GateHash $h.Src
    $dstSha = Get-GateHash $h.Dst
    if (-not $srcSha -or -not $dstSha -or $srcSha -ne $dstSha) {
        throw ("Copied $($h.Src) to $($h.Dst) but the installed copy does not hash equal to its " +
            "source (source $srcSha, installed $dstSha). Refusing to leave a gate whose helpers may " +
            "not load -- it would exit 0 after a stderr receipt and enforce nothing.")
    }
}

@(
    "# Primary checkouts governed by the worktree gate (scripts/hooks/worktree_gate.ps1)"
    "# and by the SessionStart backstop (scripts/worktree/worktree-selfheal.ps1)."
    "# Writes INTO these trees are denied; a linked worktree may not be switched onto an existing branch."
    "# Deleting this file turns both of them OFF everywhere, immediately."
    $resolved
) | Set-Content -LiteralPath $ReposFile -Encoding utf8

$command = "pwsh -NoProfile -File `"$GateDst`""

# One matcher per rule in scripts/hooks/worktree_gate.ps1. A rule the hook implements but that is not
# matched here NEVER FIRES -- the hook is simply not invoked for that tool, and nothing says so. A
# rule has shipped in exactly that state. tests/test_install_gate_wiring.py asserts that every tool
# the script branches on appears in this list, so the two cannot drift apart again. (The worktree
# hijack rule rides the same Bash|PowerShell matcher as the git-verb rule, so it needs no new tool.)
$matchers = @(
    "Write|Edit|MultiEdit|NotebookEdit"   # writes INTO the primary's tree
    "Bash|PowerShell"                     # git verbs that swap the primary / hijack a worktree
)
if (-not $NoDispatchGate) {
    $matchers += "Task|Agent|Workflow"    # subagent dispatch FROM the primary
}
if ($EnterWorktreeGate) {
    $matchers += "EnterWorktree"          # OPT-IN, see the parameter's note for why
}

$entries = foreach ($m in $matchers) {
    [ordered]@{
        matcher = $m
        hooks   = @([ordered]@{
            type          = "command"
            command       = $command
            timeout       = 15
            statusMessage = "Checking worktree gate"
        })
    }
}

# Wire (idempotently) into every target config dir. Each file is read-modified-written independently
# with its own backup and validation, so a failure on one login cannot corrupt another.
foreach ($cd in $ConfigDir) {
    $sp = Join-Path $cd "settings.json"
    $data = Remove-GateHooks (Read-Settings $sp)   # idempotent: drop our old entries, then re-add
    if (-not $data.hooks)            { $data.hooks = [ordered]@{} }
    if (-not $data.hooks.PreToolUse) { $data.hooks.PreToolUse = @() }
    $data.hooks.PreToolUse = @($data.hooks.PreToolUse) + @($entries)
    Write-Settings $sp $data
    Write-Host "  wired : $sp"
}

# The receipt: what is on disk now, hashed. Not "we wrote the settings" -- that is the claim, this is
# the evidence.
$installedSha = Get-GateHash $GateDst
Write-Host ""
Write-Host "Worktree gate INSTALLED into $($ConfigDir.Count) config dir(s) (every session, no restart)." -ForegroundColor Green
Write-Host "  gate      : $GateDst  sha $($installedSha.Substring(0, 12).ToLowerInvariant())"
Write-Host "  allowlist : $ReposFile"
$resolved | ForEach-Object { Write-Host "  governing : $_" }
Write-Host "  matchers  : $($matchers -join '  +  ')"
if ($NoDispatchGate) {
    Write-Host "  WARNING   : -NoDispatchGate was used. The dispatch rule is implemented but NOT wired," -ForegroundColor Yellow
    Write-Host "              so it will never fire. -Status reports it as UNWIRED until you reinstall." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Writes into a governed tree are DENIED; a linked worktree may not be switched onto an existing branch."
Write-Host "Verify, do not assume:  pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Status"
Write-Host "To turn it off:         pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Uninstall"
