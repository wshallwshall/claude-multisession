#Requires -Version 7.3
<#
.SYNOPSIS
    PreToolUse guard: block blanket git staging so parallel sessions sharing a working tree cannot
    sweep each other's files into one commit.

.DESCRIPTION
    POSTURE: FAILS OPEN. Any parse error, any missing dependency, any unexpected input exits 0 and
    allows the command. A guardrail must never wedge all git work.

    Reads the tool-call JSON on stdin. If any simple command in it does a broad stage -- `git add
    -A/--all/-u/.` or `git commit -a/-am/--all` -- it returns a PreToolUse `deny` asking for explicit
    paths. Anything else passes silently.

    The rule is narrow on purpose. `--amend` (double dash) is left alone; a single-dash flag cluster
    containing `a` is not, which catches `-a`, `-am`, `-na`. False positives are the expensive failure
    here: a gate that denies ordinary work trains sessions to route around it, and a routed-around
    gate protects nothing.

    Wired by hand on the shell tools -- no installer writes it. .claude/settings.example.json in this
    checkout is the exact row, with the script path left as a loud placeholder you must replace with
    an absolute one. It costs a pwsh spawn on EVERY shell tool call, git or not, which together with
    the false-positive cost above is why it stays opt-in. See docs/HOOKS.md.

.NOTES
    Command analysis is delegated to _command.ps1 rather than done inline. This file used to carry its
    own splitter and it was strictly weaker than the other gate's in four ways -- it split with a
    regex that cut `git commit -m "a; b"` in half, it did not blank quoted spans so `echo "git add
    -A"` was a deny, it did not look inside `pwsh -Command "..."`, and it required a segment to START
    with a bare `git` token so `/usr/bin/git add -A` walked past. One shared splitter is how the two
    gates stop drifting apart.

    It remains a guardrail against the accidental command, not a security boundary. An
    `-EncodedCommand` invocation is recognised but unanalysable, and any agent-authored script defeats
    a command-string gate outright.

    ASCII-only on purpose: this gate's deny reason is rendered by a console that may not be UTF-8,
    and one convention across the whole set beats two.
#>

$ErrorActionPreference = 'SilentlyContinue'

# Dot-sourced. If it is missing this guard is INERT, and an inert guard's output is byte-identical to
# a clean one -- so say so on stderr (which is not parsed as a decision) and exit 0. `ccx doctor` is
# the answer to "is this control actually live"; a hook cannot answer that about itself.
try {
    . (Join-Path $PSScriptRoot '_command.ps1')
} catch {
    [Console]::Error.WriteLine("[ccx] blanket-stage guard could not load _command.ps1; it is NOT enforcing.")
    exit 0
}

$cmd = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $j = $raw | ConvertFrom-Json
        $cmd = [string]$j.tool_input.command
    }
} catch {
    exit 0
}
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

$reason = $null
try {
    # Each simple command is judged on its own, so '... && git add -A' is still caught. Verbs are read
    # from the Scan form (quoted spans blanked); nothing here needs a path, so Raw is never consulted.
    foreach ($seg in (Split-CcxCommand -Command $cmd)) {
        $s = $seg.Scan
        if (-not (Test-CcxGitInvocation $s)) { continue }

        # git add with -A / --all / -u / a bare '.' (stages the whole tree).
        if ($s -cmatch '\badd\b' -and $s -cmatch '(^|\s)(-A|--all|-u|\.)(\s|$)') {
            $reason = "git add -A/--all/-u/. stages everything, including files another session may be editing."
            break
        }
        # git commit with -a / -am / --all (auto-stages every tracked change). A single-dash flag
        # cluster containing 'a' catches -a, -am, -na, etc.; '--amend' (double dash) is left alone.
        if ($s -cmatch '\bcommit\b' -and ($s -cmatch '(^|\s)--all(\s|$)' -or $s -cmatch '(^|\s)-[A-Za-z]*a[A-Za-z]*(\s|$)')) {
            $reason = "git commit -a/-am/--all auto-stages every tracked change before committing."
            break
        }
    }
} catch {
    exit 0
}

if (-not $reason) { exit 0 }

# PROVENANCE, matching worktree_gate.ps1. A deny is text an agent reads and obeys, and until this
# was added neither hook said WHICH copy of itself produced it. An installer resolves its source
# from wherever it was invoked, so "installed" and "the version in the repo I am reading" are
# routinely different files, and nothing on the machine says so.
#
# The digest is of THIS file as loaded, not of a source checkout, because the installed copy is what
# actually adjudicated. Folded to 12 lowercase hex -- the same fold install-gate.ps1 -Status and
# ccx-doctor.ps1 print, so a reader can compare the three by eye. Computed only on a deny, which is
# the only path that reaches here.
$sha = try {
    (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.Substring(0, 12).ToLowerInvariant()
} catch {
    # Say so in words rather than printing something that looks like a digest. A blank or a
    # plausible-looking placeholder is worse than an admission: it reads as provenance.
    'unavailable'
}

$msg = "Blocked blanket git staging: $reason Stage explicit paths instead: 'git add <path> ...' then 'git commit -m ...'. (ccx guard, sha $sha; disable via /hooks.)"
$payload = [pscustomobject]@{
    hookSpecificOutput = [pscustomobject]@{
        hookEventName            = 'PreToolUse'
        permissionDecision       = 'deny'
        permissionDecisionReason = $msg
    }
}
[Console]::Out.Write(($payload | ConvertTo-Json -Compress -Depth 6))
exit 0
