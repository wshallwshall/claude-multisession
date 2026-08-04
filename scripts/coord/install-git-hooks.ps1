#Requires -Version 7.3
<#
.SYNOPSIS
    Install the CLAIM gate (commit-msg) and the PUSH GUARD (pre-push) into the SHARED git hooks
    directory -- one copy governs every worktree of this clone at once.

.DESCRIPTION
    WHY THE SHARED HOOKS DIRECTORY. `.git/hooks` lives in the COMMON git directory, which every linked
    worktree shares. So a single file there:

      * reaches ALL worktrees the instant it is written -- no branch, no merge, no propagation lag (a
        hook committed to a branch protects nothing until every other worktree merges it);
      * survives a branch switch in any of them, because it sits outside every working tree; and
      * sees EVERY write route -- an edit tool, a shell redirect, a script, an editor, a subagent --
        because it inspects the TREE at commit time rather than a tool call.

    That last property is why this exists alongside the PreToolUse worktree gate: the gate inspects
    tool ARGUMENTS, so a file written by a shell command is invisible to it. This is that backstop.

    WHAT IT INSTALLS
      commit-msg -> claim_check.py   refuses a commit whose subject claims an item this worktree does
                                     not hold, so two sessions cannot build the same item in parallel
      pre-push   -> push_guard.py    refuses a direct push of a protected ref; that work goes through
                                     a pull request

    Only commit-msg is handed the commit message file, and the claim gate reads the subject -- so it
    cannot move to any other hook. Bolted onto pre-commit it would look installed and silently never
    fire.

    WHICH CLONE GETS GOVERNED, AND WHY IT REFUSES TO GUESS. -RepoRoot names the clone; its git common
    dir is where the hooks land. With no -RepoRoot the target is the clone you are STANDING IN, and
    that has to agree with the clone this script ships from -- when they differ, this script stops and
    makes you say which. It used to default to its own checkout, so running it from a tooling clone
    while standing in the repository you wanted governed installed both gates into the tooling clone
    and printed a clean receipt for them. Everything looked installed; nothing you were working in was
    governed.

    The CHECKERS are always copied from this script's own checkout, never from the target: the target
    is a repository you want governed, not one that has to vendor these files.

    TWO INVARIANTS, HEADLINED BECAUSE BOTH WERE LEARNED THE HARD WAY:

      1. IT REFUSES TO OVERWRITE A HOOK THAT IS NOT OURS. If commit-msg or pre-push already exists and
         does not carry our marker, this script stops and tells you to merge them by hand. Blind
         overwriting silently deletes somebody else's control.

      2. IT NEVER WRITES `pre-commit`, AT ALL -- not to install, not to patch, not to migrate. Two
         tools cannot both own that one file. A hook framework that finds a foreign hook there may
         rename it and invoke it from its own shim, and that chain has failed on Windows and blocked
         EVERY commit in the repository until the shim was removed. Note that the renamed file
         EXISTING did not indicate success; only a real commit did.
         tests/test_installers_never_write_pre_commit.py pins this rule.

    FAIL-OPEN, DECLARED. The installed hooks are `/bin/sh` shims that locate a python and exec the
    checker. If no python is found, the shim writes to stderr and exits 0 -- the gate is OFF for that
    commit, and it says so out loud. -Status reports which interpreter it found, because a missing
    interpreter is the single failure that turns both gates off everywhere at once while every file
    involved is still present and still looks installed.

    VERIFY BY RECEIPT, NOT BY PRESENCE. Installing writes a receipt recording each artifact, where it
    went and its SHA-256. -Status re-hashes the installed copies and compares them against both the
    receipt and this checkout's sources, because "a file with the right name is there" is not the same
    claim as "the code that is running is the code you are reading". Installing from a stale checkout
    downgrades the live gate for every worktree at once; trust the hash, not the filename.

    THE MARKER STRINGS ARE ON-DISK IDENTITY. -Status and -Uninstall decide whether a hook is ours by
    matching a marker inside the installed file, and neither marker contains the other. Renaming one
    orphans every existing install: the old file stops being recognised as ours, and this script then
    correctly refuses to overwrite it as foreign. If you must rename, do it once, in one commit.

    `git commit --no-verify` and `git push --no-verify` bypass both. That is a guardrail against
    accident, not a security boundary; back it with a server-side check if you need one.

    Run from a plain terminal, NOT from inside Claude Code -- a session that can install these gates
    can remove them, and both of them exist to constrain sessions. -Status is exempt: auditing is not
    installing.

.EXAMPLE
    pwsh -NoProfile -File scripts/coord/install-git-hooks.ps1 -RepoRoot <path-to-the-repo-to-govern>
    pwsh -NoProfile -File scripts/coord/install-git-hooks.ps1 -RepoRoot <path> -Status
    pwsh -NoProfile -File scripts/coord/install-git-hooks.ps1 -RepoRoot <path> -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Status,
    # NO DEFAULTS on either of these, deliberately: parameter defaults bind BEFORE the first line of
    # the body, so a default that throws pre-empts the refusal guard below and the script dies with an
    # unrelated error instead of refusing. A guard is only a guard if nothing can run ahead of it.
    #
    # -RepoRoot  the clone to govern. Resolved below; unset, it is inferred from the directory you are
    #            standing in and refuses when that is not the clone this script ships from.
    # -HooksDir  where the hooks are written. Unset, it is core.hooksPath if set, else
    #            <git-common-dir>/hooks of -RepoRoot. Pass it only for a layout neither answer fits.
    [string]$RepoRoot,
    [string]$HooksDir
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/_common.ps1"

# TWO ROOTS, NEVER ONE, and they answer different questions:
#
#   $SourceRoot  where the checkers are COPIED FROM. Always this script's own checkout -- the files
#                ship beside it, so no target repository has to carry them.
#   $RepoRoot    the clone that GETS GOVERNED. Its git common dir decides where the hooks land.
#
# They are the same directory when you install a clone into itself, and different the moment the
# tooling lives in its own checkout. One variable served both jobs here, which is why a target passed
# with -RepoRoot used to be searched for checker sources it was never expected to have.
$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path

if (-not $RepoRoot) {
    # REFUSE TO GUESS. The old default was $SourceRoot alone, so `cd <your-repo>; pwsh -File
    # <tooling>/scripts/coord/install-git-hooks.ps1` installed the gates into the TOOLING clone and
    # printed a clean receipt for them -- the exact failure this repository exists to prevent, blessed
    # by a green install. The clone you are STANDING IN is the only signal about intent available
    # here, so it is required to agree with the one this script ships from; where they disagree, say
    # so rather than picking one.
    $cwdTop = Invoke-CcxGit -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
    if (-not $cwdTop) {
        throw ("Cannot tell which clone to govern: '$($PWD.Path)' is not inside a git repository, and " +
            "this script's own checkout ($SourceRoot) is only where the CHECKERS are copied from -- " +
            "it is not evidence of what you meant to govern. Name the target: " +
            "-RepoRoot <path-to-the-repo-you-want-governed>.")
    }
    $srcCommon = Get-CcxGitCommonDir -Repo $SourceRoot
    $cwdCommon = Get-CcxGitCommonDir -Repo $cwdTop
    if ($srcCommon -and (ConvertTo-CcxComparablePath -Path $srcCommon) -ne (ConvertTo-CcxComparablePath -Path $cwdCommon)) {
        throw ("Refusing to guess which clone to govern. You are standing in '$cwdTop', but this " +
            "script ships from '$SourceRoot' -- a DIFFERENT clone. Installing into the wrong one " +
            "writes hooks that look installed, hash correctly, and govern nothing you are working " +
            "in. Say which one you mean:" + [Environment]::NewLine +
            "    -RepoRoot `"$cwdTop`"   (the checkout you are standing in)")
    }
    $RepoRoot = $cwdTop
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path

$common = Get-CcxGitCommonDir -Repo $RepoRoot
if (-not $common) { throw "Not inside a git repository (git rev-parse --git-common-dir failed at $RepoRoot)." }

if (-not $HooksDir) {
    # Honour core.hooksPath. If it is set and we ignore it, we write files git will never run -- which
    # is the exact shape of failure this script is built to make impossible.
    $hooksPath = Invoke-CcxGit -Repo $RepoRoot -Arguments @('config', '--get', 'core.hooksPath')
    $HooksDir = if ($hooksPath) {
        if ([System.IO.Path]::IsPathRooted($hooksPath)) { $hooksPath } else { Join-Path $RepoRoot $hooksPath }
    } else {
        Join-Path $common "hooks"
    }
}
$ReceiptPath = Join-Path $HooksDir "ccx-hooks.receipt.json"

# ---------------------------------------------------------------------------------------- artifacts

function New-ShellShim {
    param(
        [string]$Marker,
        [string]$Payload,
        [string]$ArgsExpr,
        [string]$OffMessage
    )
    # LF endings and no BOM, written below with an explicit encoder: `/bin/sh` will not run a script
    # whose shebang line ends in CR, and the failure reads as "bad interpreter", not as "bad newline".
    $body = @"
#!/bin/sh
# $Marker -- INSTALLED COPY. Source: scripts/hooks/$Payload
# Re-install after changing the source by running scripts/coord/install-git-hooks.ps1 from the
# checkout it came from. Which checkout that was, and which clone this governs, are both recorded
# in ccx-hooks.receipt.json beside this file -- do not assume they are the same directory.
HOOK_DIR=`$(dirname "`$0")
PY="`${CCX_PYTHON:-}"
if [ -z "`$PY" ]; then
  PY=python
  command -v python >/dev/null 2>&1 || PY=python3
fi
if ! command -v "`$PY" >/dev/null 2>&1; then
  echo "ccx: no python found -- $OffMessage" >&2
  exit 0
fi
exec "`$PY" "`$HOOK_DIR/$Payload" $ArgsExpr
"@
    return ($body -replace "`r`n", "`n")
}

# Neither marker contains the other, in either direction. See the header: they are on-disk identity.
$ARTIFACTS = @(
    @{
        Name       = "claim gate"
        Hook       = "commit-msg"
        Marker     = "ccx claim gate"
        Source     = "scripts/hooks/claim_check.py"
        Payload    = "claim_check.py"
        ArgsExpr   = '"$1"'
        OffMessage = "THE CLAIM GATE IS OFF for this commit."
    }
    @{
        Name       = "push guard"
        Hook       = "pre-push"
        Marker     = "ccx push guard"
        Source     = "scripts/hooks/push_guard.py"
        Payload    = "push_guard.py"
        ArgsExpr   = '"$@"'
        OffMessage = "THE PUSH GUARD IS OFF for this push."
    }
)

foreach ($a in $ARTIFACTS) {
    $a.HookPath = Join-Path $HooksDir $a.Hook
    $a.PayloadPath = Join-Path $HooksDir $a.Payload
    $a.SourcePath = Join-Path $SourceRoot $a.Source
    $a.ShimText = New-ShellShim -Marker $a.Marker -Payload $a.Payload -ArgsExpr $a.ArgsExpr -OffMessage $a.OffMessage
}

# Both checkers do `sys.path.insert(0, <own dir>)` and then import this module. Installing the checkers
# WITHOUT it does not produce a disabled gate -- it produces a gate that raises at import and exits
# non-zero, i.e. one that refuses every commit and every push for a reason that has nothing to do with
# what it checks. It has to travel with them, and -Status has to notice when it has not.
$SUBSTRATE = @(
    @{ Name = "python substrate"; Source = "scripts/hooks/_ccxconfig.py"; Payload = "_ccxconfig.py" }
)
foreach ($s in $SUBSTRATE) {
    $s.PayloadPath = Join-Path $HooksDir $s.Payload
    $s.SourcePath = Join-Path $SourceRoot $s.Source
}

# ------------------------------------------------------------------------------------------ helpers

function Get-TextSha256([string]$Text) {
    if ($null -eq $Text) { return "" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (([System.Security.Cryptography.SHA256]::HashData($bytes) |
            ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-HasMarker([string]$Path, [string]$Marker) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    return ([string]$raw -match [regex]::Escape($Marker))
}

# ConvertFrom-Json coerces an ISO-8601 string into a DateTime, which then renders in the host's local
# format and loses the 'this is UTC' marker the receipt deliberately wrote. Print it back as written.
function Format-Stamp($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("o") }
    return [string]$Value
}

function Read-Receipt {
    if (-not (Test-Path -LiteralPath $ReceiptPath)) { return $null }
    try { return (Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json -AsHashtable) }
    catch {
        # Unreadable is not the same as absent, and must never be reported as absent.
        Write-Warning "Receipt at $ReceiptPath is unreadable: $($_.Exception.Message)"
        return @{ unreadable = $true }
    }
}

# "Find a python, and report WHICH one." Nothing here tries to pick a good interpreter or repair a bad
# one -- the checkers are stdlib-only, so any python will do. What matters is that the answer is
# reported rather than assumed, because the shims fail open when there is none.
function Resolve-Python {
    $cands = @()
    if ($env:CCX_PYTHON) { $cands += [pscustomobject]@{ How = 'CCX_PYTHON'; Path = $env:CCX_PYTHON } }
    foreach ($n in @('python', 'python3')) {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { $cands += [pscustomobject]@{ How = "PATH ($n)"; Path = $c.Source } }
    }
    foreach ($c in $cands) {
        # Ask the interpreter, do not trust the lookup. On Windows a `python` on PATH is often an app
        # execution alias stub that resolves cleanly and then does not run anything -- the instrument
        # answers "found", which is not the question ("will this execute the checker?").
        $ver = $null
        try { $ver = (& $c.Path --version 2>&1 | Select-Object -First 1) } catch { $ver = $null }
        if ($LASTEXITCODE -eq 0 -and $ver) {
            return [pscustomobject]@{ Path = $c.Path; How = $c.How; Version = [string]$ver }
        }
    }
    return $null
}

function Get-WorktreeCount {
    $porcelain = Invoke-CcxGit -Repo $RepoRoot -Arguments @('worktree', 'list', '--porcelain')
    if (-not $porcelain) { return 0 }
    return @($porcelain -split "`r?`n" | Where-Object { $_ -match '^worktree\s' }).Count
}

# --------------------------------------------------------------------------------------------- status
# Runs BEFORE the refusal below, deliberately. Auditing is not installing.
if ($Status) {
    $receipt = Read-Receipt
    $py = Resolve-Python
    $preCommit = Join-Path $HooksDir "pre-commit"
    $configPath = Find-CcxConfigPath -From $RepoRoot

    $head = Invoke-CcxGit -Repo $RepoRoot -Arguments @('rev-parse', '--short', 'HEAD')
    $branch = Invoke-CcxGit -Repo $RepoRoot -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')

    Write-Host ""
    Write-Host "ccx git hooks"
    # BOTH ROOTS, ALWAYS. "Which clone did this audit describe?" has to be answerable from the output
    # alone -- a report that names only a hooks directory is one a reader assumes is about the repo
    # they meant.
    Write-Host "  governs   : $RepoRoot $(if ($branch) { "@ $branch" }) $(if ($head) { "($head)" })"
    Write-Host "  hooks dir : $HooksDir"
    Write-Host "  sources   : $SourceRoot$(if ($SourceRoot -ne $RepoRoot) { '   (a different checkout -- the hashes below compare against THIS one)' })"
    if (-not $receipt) {
        Write-Host "  receipt   : NONE at $ReceiptPath" -ForegroundColor Yellow
        Write-Host "              Nothing recorded an install here. Files below may still be present;" -ForegroundColor Yellow
        Write-Host "              presence is not evidence that this repo's installer put them there." -ForegroundColor Yellow
    } elseif ($receipt.unreadable) {
        Write-Host "  receipt   : UNREADABLE at $ReceiptPath" -ForegroundColor Red
    } else {
        Write-Host "  receipt   : written $(Format-Stamp $receipt.writtenAtUtc) from $($receipt.sourceRoot) $(if ($receipt.sourceHead) { "($($receipt.sourceHead))" })"
    }
    Write-Host "  opt-in    : $(if ($configPath) { $configPath } else { 'NO ccx.config.json at or above this directory' })"
    Write-Host ""

    $bad = 0
    foreach ($a in $ARTIFACTS) {
        $recEntry = $null
        if ($receipt -and -not $receipt.unreadable -and $receipt.entries) { $recEntry = $receipt.entries[$a.Hook] }

        $hookPresent = Test-Path -LiteralPath $a.HookPath -PathType Leaf
        $hookOurs = Test-HasMarker $a.HookPath $a.Marker
        $hookSha = Get-FileSha256 $a.HookPath
        $wantHookSha = Get-TextSha256 $a.ShimText

        $payloadSha = Get-FileSha256 $a.PayloadPath
        $sourceSha = Get-FileSha256 $a.SourcePath

        Write-Host ("  {0,-12} {1}" -f $a.Name, $a.Hook)
        if (-not $hookPresent) {
            Write-Host "    hook       NOT INSTALLED" -ForegroundColor Red
        } elseif (-not $hookOurs) {
            Write-Host "    hook       present, but NOT ours (no '$($a.Marker)' marker)" -ForegroundColor Red
        } elseif ($hookSha -ne $wantHookSha) {
            Write-Host "    hook       installed, but DIFFERS from what this checkout would write" -ForegroundColor Yellow
            Write-Host "               re-run this installer to bring it up to date" -ForegroundColor Yellow
        } else {
            Write-Host "    hook       installed, matches this checkout"
        }

        if (-not $sourceSha) {
            Write-Host "    checker    SOURCE MISSING at $($a.SourcePath)" -ForegroundColor Red
        } elseif (-not $payloadSha) {
            Write-Host "    checker    NOT INSTALLED at $($a.PayloadPath)" -ForegroundColor Red
            Write-Host "               the shim would exec a file that is not there" -ForegroundColor Red
        } elseif ($payloadSha -ne $sourceSha) {
            Write-Host "    checker    INSTALLED COPY DIFFERS FROM SOURCE" -ForegroundColor Yellow
            Write-Host "               installed $($payloadSha.Substring(0,8))  source $($sourceSha.Substring(0,8))" -ForegroundColor Yellow
            Write-Host "               the running gate is not the code in this checkout" -ForegroundColor Yellow
        } else {
            Write-Host "    checker    installed, sha $($payloadSha.Substring(0,8)) == source"
        }

        if ($recEntry) {
            $drift = @()
            if ($recEntry.hookSha256 -and $hookSha -and $recEntry.hookSha256 -ne $hookSha) { $drift += "hook" }
            if ($recEntry.payloadSha256 -and $payloadSha -and $recEntry.payloadSha256 -ne $payloadSha) { $drift += "checker" }
            if ($drift.Count -gt 0) {
                Write-Host "    receipt    DRIFT since install: $($drift -join ', ') changed on disk" -ForegroundColor Yellow
            } else {
                Write-Host "    receipt    matches"
            }
        } else {
            Write-Host "    receipt    no record of installing this" -ForegroundColor Yellow
        }

        $live = $hookPresent -and $hookOurs -and $payloadSha -and $sourceSha -and ($payloadSha -eq $sourceSha)
        if ($live) { Write-Host "    => INSTALLED" -ForegroundColor Green }
        else { Write-Host "    => NOT INSTALLED / NOT CURRENT" -ForegroundColor Red; $bad++ }
        Write-Host ""
    }

    if ($py) {
        Write-Host "  python    : $($py.Path)  [$($py.How)]  $($py.Version)"
    } else {
        Write-Host "  python    : NONE FOUND -- BOTH GATES ARE OFF." -ForegroundColor Red
        Write-Host "              The shims fail open: with no interpreter they print to stderr and" -ForegroundColor Red
        Write-Host "              exit 0, so every commit and every push passes. Put a python on PATH" -ForegroundColor Red
        Write-Host "              or set CCX_PYTHON to one." -ForegroundColor Red
        $bad++
    }

    # Reported, never written. See the header for why this script does not own that file.
    if (Test-Path -LiteralPath $preCommit -PathType Leaf) {
        Write-Host "  pre-commit: present (owned by something else -- this script never writes it)"
    } else {
        Write-Host "  pre-commit: absent (this script never writes it)"
    }

    Write-Host "  reaches   : $(Get-WorktreeCount) worktree(s) of $RepoRoot, immediately"
    Write-Host ""
    Write-Host "scanned: $(@($ARTIFACTS).Count) artifact pair(s) in $HooksDir, hashed against $SourceRoot,"
    Write-Host "         for the clone at $RepoRoot."
    Write-Host "blind spots on this run:"
    Write-Host "  * A hook that exists and hashes correctly still does nothing if the checker it execs"
    Write-Host "    refuses to run. Nothing here executed either checker -- drive a real commit, or run"
    Write-Host "    the doctor, which fires each control on purpose and requires it to deny."
    Write-Host "  * --no-verify bypasses both, and nothing local can see that it happened."
    Write-Host "  * Only this clone was examined. Another clone of the same project has its own hooks."
    Write-Host ""
    if ($bad -gt 0) { Write-Host "$bad problem(s). Exit code 1." -ForegroundColor Red; exit 1 }
    exit 0
}

if ($env:CLAUDECODE -eq "1") {
    throw ("Refusing to run inside Claude Code. A session that can install these gates can also " +
        "remove them, and both of them exist specifically to constrain what a session may commit " +
        "and push. Run from a plain pwsh terminal. (-Status is allowed from a session: auditing is " +
        "not installing.)")
}

# ------------------------------------------------------------------------------------------ uninstall
if ($Uninstall) {
    $removed = @()
    foreach ($a in $ARTIFACTS) {
        if (Test-HasMarker $a.HookPath $a.Marker) {
            Remove-Item -LiteralPath $a.HookPath -Force
            $removed += $a.HookPath
            if (Test-Path -LiteralPath $a.PayloadPath) {
                Remove-Item -LiteralPath $a.PayloadPath -Force
                $removed += $a.PayloadPath
            }
        } elseif (Test-Path -LiteralPath $a.HookPath) {
            # Never delete a hook we did not write, even on the uninstall path. The checker copy stays
            # with it on purpose: a foreign hook may have been edited to call it, and removing a file
            # something else execs turns somebody else's control off without saying so.
            Write-Host "Leaving $($a.HookPath) alone -- it is not ours." -ForegroundColor Yellow
        }
    }
    Remove-Item -LiteralPath $ReceiptPath -Force -ErrorAction SilentlyContinue
    Write-Host ""
    if ($removed.Count -eq 0) {
        Write-Host "Nothing to remove (no ccx hooks installed in $HooksDir)."
    } else {
        Write-Host "REMOVED from $HooksDir" -ForegroundColor Yellow
        foreach ($r in $removed) { Write-Host "  $r" }
        Write-Host "  receipt: $ReceiptPath"
    }
    Write-Host ""
    return
}

# -------------------------------------------------------------------------------------------- install

foreach ($a in $ARTIFACTS) {
    if (-not (Test-Path -LiteralPath $a.SourcePath -PathType Leaf)) {
        throw ("Source checker missing: $($a.SourcePath). Refusing to install a $($a.Hook) hook that " +
            "would exec a file this checkout does not have -- that hook would fail open on every " +
            "commit and look installed while doing so.")
    }
    if ((Test-Path -LiteralPath $a.HookPath) -and -not (Test-HasMarker $a.HookPath $a.Marker)) {
        throw ("A $($a.Hook) hook that is not ours already exists at $($a.HookPath). Refusing to " +
            "overwrite it -- merge them by hand.")
    }
}

foreach ($s in $SUBSTRATE) {
    if (-not (Test-Path -LiteralPath $s.SourcePath -PathType Leaf)) {
        throw ("Source $($s.Name) missing: $($s.SourcePath). Refusing to install checkers that import " +
            "it -- they would raise at import and refuse every commit and push, while looking installed.")
    }
}

New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$entries = [ordered]@{}

# Substrate first: a checker that lands before the module it imports is briefly a gate that refuses
# everything. Order is cheap insurance against an interrupted install.
foreach ($s in $SUBSTRATE) {
    Copy-Item -LiteralPath $s.SourcePath -Destination $s.PayloadPath -Force
    $sSha = Get-FileSha256 $s.PayloadPath
    $sSrcSha = Get-FileSha256 $s.SourcePath
    if (-not $sSha -or $sSha -ne $sSrcSha) {
        throw "Copied $($s.Source) to $($s.PayloadPath) but could not read back a matching hash. Nothing was recorded."
    }
    $entries[$s.Payload] = [ordered]@{
        kind          = "substrate"
        source        = $s.Source
        payloadPath   = $s.PayloadPath
        payloadSha256 = $sSha
    }
}

foreach ($a in $ARTIFACTS) {
    Copy-Item -LiteralPath $a.SourcePath -Destination $a.PayloadPath -Force
    [System.IO.File]::WriteAllText($a.HookPath, $a.ShimText, $utf8NoBom)
    # Git for Windows does not need the exec bit, but a Linux or macOS checkout of the same repo does.
    if ($IsLinux -or $IsMacOS) { & chmod +x $a.HookPath }

    # Verify by RE-READING, not by "no exception was thrown". The hash we record has to be the hash of
    # what is on disk now; recording the hash of what we intended to write records an intention.
    $hookSha = Get-FileSha256 $a.HookPath
    $payloadSha = Get-FileSha256 $a.PayloadPath
    $sourceSha = Get-FileSha256 $a.SourcePath
    if (-not $hookSha -or -not $payloadSha) {
        throw "Wrote $($a.Hook) but could not read it back from $HooksDir. Nothing was recorded."
    }
    if ($payloadSha -ne $sourceSha) {
        throw "Copied $($a.Source) to $($a.PayloadPath) but the hashes differ. Refusing to record a bad install."
    }

    $entries[$a.Hook] = [ordered]@{
        name          = $a.Name
        marker        = $a.Marker
        hookPath      = $a.HookPath
        hookSha256    = $hookSha
        payloadPath   = $a.PayloadPath
        payloadSha256 = $payloadSha
        source        = $a.Source
    }
}

$receiptDoc = [ordered]@{
    tool         = "scripts/coord/install-git-hooks.ps1"
    writtenAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    hooksDir     = $HooksDir
    # Recorded separately because they can differ, and "which code went in" and "which clone it now
    # governs" are the two questions asked of a receipt six months later.
    targetRoot   = $RepoRoot
    sourceRoot   = $SourceRoot
    sourceHead   = (Invoke-CcxGit -Repo $SourceRoot -Arguments @('rev-parse', '--short', 'HEAD'))
    entries      = $entries
}
$receiptJson = $receiptDoc | ConvertTo-Json -Depth 10
$null = $receiptJson | ConvertFrom-Json
Set-Content -LiteralPath $ReceiptPath -Value $receiptJson -Encoding utf8NoBOM

# ------------------------------------------------------------------------------------------- receipt
# Print what was written and where, every time. An installer that says only "done" is the same shape
# of lie as a green status that checked nothing.
Write-Host ""
Write-Host "ccx git hooks INSTALLED into $HooksDir" -ForegroundColor Green
foreach ($a in $ARTIFACTS) {
    $e = $entries[$a.Hook]
    Write-Host ("  {0,-12} {1}" -f $a.Name, $e.hookPath)
    Write-Host ("               {0}   sha {1}   (from {2})" -f $e.payloadPath, $e.payloadSha256.Substring(0, 8), $e.source)
}
Write-Host "  receipt    : $ReceiptPath"
Write-Host "  governs    : $RepoRoot"
Write-Host "               $(Get-WorktreeCount) worktree(s) of that clone, immediately"
Write-Host "  sources    : $SourceRoot"

$py = Resolve-Python
if ($py) {
    Write-Host "  python     : $($py.Path)  [$($py.How)]  $($py.Version)"
} else {
    Write-Host ""
    Write-Host "!! NO PYTHON FOUND -- BOTH GATES ARE OFF." -ForegroundColor Red
    Write-Host "   The shims fail open by design: with no interpreter they print to stderr and exit 0," -ForegroundColor Red
    Write-Host "   so every commit and every push passes. Put a python on PATH, or set CCX_PYTHON." -ForegroundColor Red
}

if (-not (Find-CcxConfigPath -From $RepoRoot)) {
    Write-Host ""
    Write-Host "  NOTE: no ccx.config.json found at or above $RepoRoot. That file is the opt-in marker" -ForegroundColor Yellow
    Write-Host "        as well as the configuration; without it the rest of the tooling stays inert." -ForegroundColor Yellow
}

# The sequence gate is NOT installed here, and saying nothing about it would leave a silent hole --
# an absent gate looks exactly like one that passed.
$seqConfigured = $false
try { $seqConfigured = ((Get-CcxConfig -From $RepoRoot).sequences.Count -gt 0) } catch { $seqConfigured = $false }
if ($seqConfigured) {
    Write-Host ""
    Write-Host "  Sequence gate: NOT installed by this script." -ForegroundColor Yellow
    Write-Host "    scripts/hooks/seq_check.py needs a pre-commit hook, and this script never writes" -ForegroundColor Yellow
    Write-Host "    that file (see the header). Wire it into whatever hook framework you already use." -ForegroundColor Yellow
    Write-Host "    Until you do, nothing at commit time stops two sessions using the same number." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Claim gate : blocks a commit whose subject claims an item this worktree does not hold, so"
Write-Host "             two sessions cannot build the same item in parallel."
Write-Host "Push guard : refuses a direct push of a protected ref -- that work goes through a PR."
Write-Host ""
Write-Host "Take a claim with:  pwsh -NoProfile -File scripts/coord/claim.ps1 -Take <key> -Note ""<what>"""
Write-Host "See who holds what: pwsh -NoProfile -File scripts/coord/claim.ps1 -List"
Write-Host "Allocate a number:  pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind <kind> -Title ""<title>"""
Write-Host "Verify everything:  pwsh -NoProfile -File bin/ccx-doctor.ps1"
Write-Host "Remove with:        pwsh -NoProfile -File scripts/coord/install-git-hooks.ps1 -Uninstall"
Write-Host ""
