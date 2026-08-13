#Requires -Version 7.3
<#
.SYNOPSIS
    PreToolUse gate: keep concurrent agent sessions from BUILDING in a shared primary checkout.

.DESCRIPTION
    Installed to the USER scope (~/.claude/hooks/) by scripts/worktree/install-gate.ps1, so it governs
    every session in every worktree the moment it lands -- a project-scoped hook would live on one
    branch and reach the other worktrees only once each of them merged it.

    It denies, and only inside a governed primary checkout:

      1  a Write/Edit/MultiEdit/NotebookEdit whose TARGET PATH is inside the primary's working tree;
      1a a write to the gate's own enforcement surface;
      2  a Task/Agent/Workflow dispatch made FROM the primary -- a subagent inherits the parent's cwd,
         cannot create a worktree of its own, and its denied edits do not reliably surface to the
         parent (measured: the parent's result came back with an EMPTY permission_denials list).
         Blocking the fan-out costs one second; letting it run costs the whole workflow;
      3  a git verb that swaps or discards the primary's working tree;
      3b a switch that hijacks ANOTHER session's linked worktree onto an existing branch;
      3c a git config write that redirects what later git commands in the SHARED repository do;
      3d a `git worktree remove|move` aimed at somebody else's checkout;
      4  the EnterWorktree tool (opt-in matcher), which relocates a live session.

    KEYED ON THE TARGET PATH, NEVER ON THE SESSION'S cwd. Measured on the repo this was developed in,
    over 30 days: 29% of the Edit/Write calls made by sessions sitting in the primary wrote into a
    sibling worktree by absolute path -- i.e. already correct. A cwd-keyed gate would have denied all
    of them. Only the DESTINATION matters.

    FAILS OPEN on every error path (bad JSON, missing fields, unreadable allowlist, an unloadable
    helper). A guardrail that wedges all work gets uninstalled, and then it protects nothing. But it
    fails open LOUDLY where it can: a bootstrap failure writes a receipt to stderr and to the deny log,
    because "the gate had nothing to say" and "the gate could not load" are otherwise byte-identical.

    This is a guardrail against the ACCIDENTAL primary edit -- the "I forgot to spin up a worktree"
    case. It is NOT a security boundary: it inspects tool arguments, so a file written from a shell
    command is not seen, and any agent-authored script defeats a command-string rule outright. A
    commit-time hook is the backstop for that.

.NOTES
    DEPENDENCIES. This script dot-sources scripts/hooks/_command.ps1, scripts/hooks/_gittarget.ps1 and
    scripts/coord/_common.ps1. The installer MUST place all of them beside the installed copy;
    _gittarget.ps1 looks next to itself and then in ../coord/. If they are missing the gate exits 0 and
    says so -- it does not run in a degraded state.

    KILL SWITCH, stated plainly rather than hidden. The allowlist is the switch: no file, no entries,
    nothing governed. From a plain terminal, which is never gated:

        pwsh -NoProfile -File scripts/worktree/install-gate.ps1 -Uninstall

    Keeping that out of the deny message was tried and is not a control -- the file is one directory
    listing away. Rule 1a is the actual control: a session may not write to the allowlist or to this
    script, while the human installing from a terminal is untouched.
#>
[CmdletBinding()]
param(
    # Newline-delimited list of primary checkouts to govern. Absent or empty => the gate is OFF.
    #
    # Resolved null-safely: $env:USERPROFILE is Windows-only and is NULL elsewhere, where Join-Path
    # throws a parameter-binding error instead of returning a path. In a PARAMETER DEFAULT that happens
    # during binding, so it would kill the hook before its first line -- and a hook that exits
    # non-zero-but-not-2 lets the tool call through SILENTLY. The gate would be off with nothing to say
    # so.
    #
    # NB `$( ... )`, not `( ... )`. A bare paren opens a COMMAND-INVOCATION group, so PowerShell parses
    # the `if` as a command NAME and fails with "The term 'if' is not recognized". A statement needs a
    # subexpression. That shipped broken once and was invisible to the entire test suite, because every
    # test passed -ReposFile explicitly and a parameter default is not evaluated when a value is
    # supplied -- so nothing ever exercised the production path. The gate was OFF on every real tool
    # call for the length of one install. tests/test_worktree_gate_no_args.py runs this script with NO
    # arguments -- and requires it to DENY a write into a governed root, which is the only thing that
    # proves the default both evaluated and resolved to the file the installer actually writes.
    [string]$ReposFile = (Join-Path $(
        if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
    ) ".claude/hooks/ccx-gate.repos.txt")
)

# A HUMAN LABEL, not the parity check. `install-gate.ps1 -Status` compares SHA-256 and that comparison
# is authoritative; this string exists so the output is readable, and it is bumped by hand.
#
# Which means it can lie, and immediately did: three rules were added without bumping it, so -Status
# printed the SAME version on both sides directly above a *** STALE *** verdict. The SHA caught the
# drift, but a stamp that disagrees with the verdict beside it is the exact ambiguity this machinery
# exists to remove. -Status prints the SHA prefix on both lines, so agreement is visible rather than
# asserted, and this label can never again be the only thing a reader compares.
$GateVersion = "1"

# The file this gate was LOADED FROM, hashed at deny time -- not the source somebody is reading. This
# gate is PUBLISHED and gets installed from whatever checkout the installer happened to run in, so
# "installed" and "the version in the repo I am looking at" are different files and nothing on the
# machine says which is which. The hand-bumped label above cannot close that -- it lied once already --
# so both of the gate's outputs carry the digest of that file beside it. 12 lowercase hex, the SAME
# fold as install-gate.ps1 -Status and bin/ccx-doctor.ps1, so the three can be compared by eye.
#
# SAID PRECISELY, because the imprecise version is the same class of lie: this is the digest of the
# file ON DISK WHEN THE DENY IS COMPOSED, not of the bytes PowerShell parsed at process start.
# Measured -- a gate slowed with a sleep and then appended to mid-flight stamped the NEW digest -- so
# if install-gate.ps1 replaces the installed copy while an invocation is in the air, that one deny
# names a file slightly newer than the rules that produced it. The window is one hook lifetime wide
# and needs a concurrent install to open. Closing it would mean hashing eagerly at script scope, i.e.
# paying the read on every ALLOW, which is the overwhelming majority of invocations; the wrong trade.
$script:GateSelf = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$script:GateSha = $null

function Get-GateSha {
    # LAZY and memoized. A PreToolUse hook runs on every matched tool call on the box and the
    # overwhelming majority decide nothing and exit 0; only a deny (or the bootstrap-failure receipt)
    # ever needs this, and the deny path wants it twice. Never throws, never writes to stderr: a
    # provenance stamp must not be able to turn an allow into an emission, and
    # tests/test_worktree_gate_no_args.py requires stderr to be empty.
    if ($script:GateSha) { return $script:GateSha }
    $script:GateSha = "unavailable"
    try {
        $h = (Get-FileHash -LiteralPath $script:GateSelf -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($h -and $h.Length -ge 12) { $script:GateSha = $h.Substring(0, 12).ToLowerInvariant() }
    } catch { }
    return $script:GateSha
}

# Fail OPEN: any unhandled error must let the tool call through, never block it.
$ErrorActionPreference = "SilentlyContinue"

# Set once the payload is parsed; referenced by the log record composer below, which may run before
# either is known (a bootstrap failure).
$tool = ""
$cwdRaw = ""

function Write-GateLog([string]$Rule, [string]$Detail) {
    # Leave a RECEIPT before denying. Until this existed the gate was unfalsifiable: it wrote its
    # decision to stdout and exited 0, so nothing on the box could answer "how many drift events did we
    # prevent", "is the false-positive rate one a day or one in a thousand", or "did that fix change
    # anything" -- and every severity ranking about this machinery was therefore an opinion.
    # Best-effort and never load-bearing: the log lives beside the allowlist, and if the append fails
    # the deny still goes out.
    #
    # Deliberately NOT logged: the raw command or file contents. Each rule passes a $Detail it composed
    # itself (a verb, a target path), so an argument carrying a secret cannot end up in a plaintext log.
    try {
        $logDir = Split-Path -Parent $ReposFile
        if (-not $logDir -or -not (Test-Path -LiteralPath $logDir)) { return }

        # ONE RECORD IS ONE LINE, always. $Detail is composed from tool input, so an embedded newline
        # or tab would let a crafted path forge extra records in a log whose whole purpose is counting.
        # Strip both and cap the length before composing.
        $clean = {
            param($s)
            $t = ("$s" -replace '[\r\n\t]', ' ')
            if ($t.Length -gt 400) { $t.Substring(0, 400) + '...' } else { $t }
        }
        $stamp = (Get-Date).ToString("s")
        # The digest sits BESIDE the label, not instead of it: a reader diffing two records then sees
        # the label agree while the digest disagrees, which is the measured incident made visible in
        # the receipt rather than only in -Status.
        $line = "$stamp`tv$GateVersion`tsha=$(Get-GateSha)`tpid=$PID`trule=$(& $clean $Rule)" +
                "`ttool=$(& $clean $tool)`tcwd=$(& $clean $cwdRaw)`t$(& $clean $Detail)"

        # Every session on the box shares this file, so concurrent denies race. Add-Content silently
        # dropped records under contention -- and a lossy counter is worse than none, because it reads
        # as a measurement. Retry a bounded number of times, then give up quietly: the deny matters,
        # the receipt does not.
        $path = Join-Path $logDir "ccx-gate.log"
        for ($i = 0; $i -lt 5; $i++) {
            try {
                [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine)
                break
            } catch {
                Start-Sleep -Milliseconds (10 * ($i + 1))
            }
        }
    } catch { }
}

# Fold a CALLER-SUPPLIED value before it goes into a deny REASON.
#
# WHY THIS IS NOT COSMETIC. The reasons below carry a literal command block introduced by "What to do
# instead:". A reason is an INSTRUCTION an agent reads and acts on, so a value a caller controls must
# not be able to add structure to it. Two inputs reach these reasons and both are attacker-influenced:
#
#   * A BRANCH NAME (rule 3b). `git check-ref-format` accepts ';', '$', '|', '"' and "'" in a refname,
#     so a branch called  x';calc;#  makes the printed remediation parse as two statements with '#'
#     hiding the remainder.
#   * A TARGET PATH. An embedded newline lets a crafted path forge a SECOND "What to do instead:"
#     block. Placed first, a model reading top-down reaches the forged command before the real one.
#     The path never has to exist; only the field does.
#
# So: strip the characters that add structure, and cap the length. This runs on the way OUT, because
# the value is legitimate input -- the danger is what it becomes once embedded in text an agent obeys.
function Get-SafeForMessage([string]$Value) {
    $t = ("$Value" -replace '[\r\n\t]', ' ')
    # Quote and statement separators: harmless in a refname, structural inside a printed command.
    $t = ($t -replace "[`"'`;|&`$``]", '_')
    if ($t.Length -gt 400) { return $t.Substring(0, 400) + '...' }
    return $t
}

function Write-Deny([string]$Reason, [string]$Rule = "?", [string]$Detail = "") {
    Write-GateLog $Rule $Detail

    # PROVENANCE, stamped centrally. A deny reason is the one output an agent READS AND OBEYS, and
    # until now it carried nothing at all: no rule id, no version, no digest -- so a reported deny
    # could not be joined to a log record, and "which file said this" was unanswerable on a machine
    # where the installed gate and the checked-out one are routinely different files.
    #
    # Here rather than at the eight (soon nine) call sites: a per-rule stamp is one a future rule
    # forgets. LAST rather than first: bin/ccx-doctor.ps1 prints only the first 200 characters of a
    # reason, so a leading stamp would push the BLOCKED: sentence out of every evidence line. Both
    # interpolated values go through the sanctioned fold -- $Rule is a literal today, but the reason
    # is an instruction and nothing reaches it unfolded.
    #
    # WHICH HALF IS AUTHORITATIVE: the DIGEST identifies the file. The path is a reading aid and is
    # folded for safety, so a gate installed under a path containing " ' ; | & $ or a backtick -- a
    # UNC admin share \\host\c$\... is the realistic one -- prints those as _ and is not literal.
    # Compare the digest; use the path to find the file.
    $ruleTag = Get-SafeForMessage $Rule
    $selfTag = Get-SafeForMessage $script:GateSelf
    $stamped = $Reason.TrimEnd() +
        "`n`n-- ccx worktree gate rule $ruleTag v$GateVersion sha $(Get-GateSha) from $selfTag"

    # The hookSpecificOutput WRAPPER IS MANDATORY. A bare {"permissionDecision":"deny"} is silently
    # ignored and the tool call proceeds (measured, and reported upstream).
    $payload = @{
        hookSpecificOutput = @{
            hookEventName            = "PreToolUse"
            permissionDecision       = "deny"
            permissionDecisionReason = $stamped
        }
    }
    [Console]::Out.Write(($payload | ConvertTo-Json -Compress -Depth 6))
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# Shared helpers. _gittarget.ps1 pulls in _common.ps1 itself and THROWS if it cannot find it, which is
# right for a coordination script and wrong for a hook: a throw here would end the process with no
# output, which the harness reads as "allow". Catch it, exit 0 (fail open), and leave a receipt on
# stderr AND in the log so the silence is attributable.
# ---------------------------------------------------------------------------------------------------
$gateLoadError = $null
try {
    . (Join-Path $PSScriptRoot '_command.ps1')
    . (Join-Path $PSScriptRoot '_gittarget.ps1')
} catch {
    $gateLoadError = "$($_.Exception.Message)"
}
if ($gateLoadError) {
    [Console]::Error.WriteLine(
        "ccx worktree gate: NOT ENFORCING -- could not load its helpers from $PSScriptRoot. " +
        "The installer must copy _command.ps1, _gittarget.ps1 and _common.ps1 alongside this script. " +
        "Detail: $gateLoadError")
    Write-GateLog "load-error" $gateLoadError
    exit 0
}

# Build a runnable path to a script that ships in the governed repo, in the platform's own separators
# so a blocked session can paste it as-is. Every remediation below goes through this, and every path it
# is given must name a script that actually exists in this repository -- a gate that tells you to run
# something that is not there is worse than one that says nothing.
function Get-RepoScript([string]$Root, [string]$Relative) {
    return (Join-Path $Root ($Relative -replace '/', [IO.Path]::DirectorySeparatorChar))
}

try { $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch { exit 0 }
if (-not $hook) { exit 0 }

# The allowlist doubles as the kill switch: no file, no entries => nothing is governed.
# Each root keeps BOTH forms: a canonical one to compare against, and the operator's original spelling
# to quote back in the deny message -- a message that shouts a mangled lower-cased path at you looks
# broken even when the match is correct.
$roots = @(
    Get-Content -LiteralPath $ReposFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } |
        ForEach-Object {
            $raw = $_.Trim()
            $cmp = ConvertTo-CcxComparablePath -Path $raw
            if ($cmp) { [pscustomobject]@{ Compare = $cmp; Display = $raw.TrimEnd('\', '/') } }
        }
)
if ($roots.Count -eq 0) { exit 0 }

$tool   = [string]$hook.tool_name
$cwdRaw = [string]$hook.cwd                                            # original case: for `git -C`
$cwd    = ConvertTo-CcxComparablePath -Path $cwdRaw                    # canonical: allowlist compare

# ---------------------------------------------------------------------------------------------------
# Rule 4 -- deny the EnterWorktree tool. Relocating a LIVE session into a worktree re-files its
# transcript under the worktree's slug, so the conversation drops out of the window it was born in
# (measured: a long transcript moved out, leaving a stub behind). Open a FRESH session in the worktree
# instead; scripts/worktree/sessions.ps1 -Rehome recovers any session already relocated.
#
# Keys on the TOOL, not the cwd: relocation loses the chat wherever you start it, so once the gate is
# on (roots non-empty, guarded above) EnterWorktree is denied unconditionally. ExitWorktree is a safe
# keep and must NOT be caught. Fail-open is preserved: any earlier parse error already exited 0, and
# only an exact tool match reaches Write-Deny.
#
# Expressed as `$tool -in @("EnterWorktree")` so tests/test_install_gate_wiring.py SEES this tool as
# handled -- a rule once shipped dead by being implemented with no matcher, and that tripwire exists
# to prevent exactly this. `install-gate.ps1 -Status` reads the same form out of the INSTALLED copy.
#
# NB the matcher is OPT-IN (`install-gate.ps1 -EnterWorktreeGate`), so this rule does not fire on a
# bare install. That is deliberate, and the same test pins that the installer appends this matcher
# only inside its `if ($EnterWorktreeGate)` block -- turning it on is a decision, not a side effect of
# re-installing. Rationale: docs/CASE-STUDY-drift-audit.md.
# ---------------------------------------------------------------------------------------------------
if ($tool -in @("EnterWorktree")) {
    $sessionsScript = Get-RepoScript $roots[0].Display 'scripts/worktree/sessions.ps1'
    Write-Deny -Rule "4" -Detail "relocate-session" -Reason @"
BLOCKED: EnterWorktree relocates this live session into a worktree, which re-files its chat transcript
under the worktree's slug and drops it from THIS window's session list (nothing is deleted -- it just
stops appearing where you started). Do not relocate a running session.

Instead:
  * Open a NEW session directly on the worktree and continue there.
  * If a session has already been relocated and vanished, recover it:
        pwsh -NoProfile -File $sessionsScript -Rehome <id-prefix>
"@
}

# A worktree that git nests INSIDE the primary's path (.claude/worktrees/<name>, the harness's own
# mechanism) is a legitimate worktree even though its path starts with the primary's. Never gate it.
# The exemption is unconditional -- it does not depend on where THIS tooling chooses to put worktrees.
function Test-Governed([string]$Candidate) {
    if (-not $Candidate) { return $null }
    foreach ($root in $roots) {
        if (-not (Test-CcxPathUnder -Path $Candidate -Root $root.Compare)) { continue }
        if (Test-CcxHarnessWorktreePath $Candidate) { return $null }
        return $root
    }
    return $null
}

# Same question for rules 3c and 3d, which must NOT apply the exemption: their blast radius is the
# SHARED .git directory, which a nested worktree reaches just as well as the primary does.
function Test-GovernedSharedDir([string]$Candidate) {
    if (-not $Candidate) { return $null }
    foreach ($root in $roots) {
        if (Test-CcxPathUnder -Path $Candidate -Root $root.Compare) { return $root }
    }
    return $null
}

# ---------------------------------------------------------------------------------------------------
# Rule 3b -- hijacking a LINKED WORKTREE by switching it onto an ALREADY-EXISTING branch. Rule 3 below
# protects only the shared PRIMARY; this protects every OTHER governed worktree from the one move that
# actually happened here: a session with no worktree of its own ran a checkout inside somebody else's
# worktree, yanking that session's files onto a different branch mid-task. git permits it because its
# native guard only blocks a branch ALREADY checked out somewhere -- a "free" branch can be grabbed by
# any worktree.
#
# Deliberately narrow: only a switch onto an EXISTING LOCAL BRANCH is denied. Creating a new branch
# (-b/-c), restoring files (`--`/pathspec), and reset/rebase/merge of the worktree's OWN branch stay
# allowed -- a worktree owns its own history; it just may not be pulled onto another in-flight branch.
# The gate cannot tell a worktree's rightful session from a squatter (both share the cwd), so it blocks
# the move for both; the rightful owner's escape hatch is a PLAIN terminal (never gated) or a fresh
# worktree for the other branch. Returns normally to ALLOW; calls Write-Deny (which exits) to block.
function Test-WorktreeHijack([string]$Verb, [string]$Cmd, [string]$WtRaw) {
    if ($Verb -notin @("checkout", "switch")) { return }

    # $WtRaw is resolved ONCE by rule 3 and handed down, so the two rules cannot disagree about which
    # tree a command acts on -- they used to have separate parsers, and a real tree swap fell into the
    # gap between them. It is the RAW (original-case) path, which every `git -C` below MUST use: a
    # folded value is lower-cased on a case-insensitive platform, and on a case-sensitive filesystem
    # that misses the real directory, git fails, and the rule silently falls open.
    if (-not $WtRaw) { return }
    $wtRaw = $WtRaw

    # Everything AFTER the first verb. $Cmd is already ONE simple command (the splitter cut it at the
    # unquoted separators), so there is no need to re-trim at `&&` here -- and the old in-rule
    # `[^|;&]*?` containment fragment is exactly the thing every future rule would have had to
    # remember. Parsing args from after the verb -- not from the whole command -- keeps git's pre-verb
    # `-C`/`-c` globals from being read as checkout's `-b` / switch's `-c`.
    $after = ($Cmd -replace ('(?s)^.*?\b' + [regex]::Escape($Verb) + '\b'), '')

    # Not a branch switch onto an existing branch? Leave it alone.
    #   `--`                       -> pathspec / file restore (`git checkout -- f`, `git checkout r -- f`)
    #   -b/-B (checkout) / -c/-C (switch) AFTER the verb -> creating a branch, not moving onto one
    if ($after -cmatch '(^|\s)--(\s|$)') { return }
    if ($after -cmatch '(^|\s)-[bBcC](?=\s|$)') { return }

    # The destination ref = first positional (non-flag) token after the verb.
    $dest = $null
    foreach ($tok in @($after -split '\s+' | Where-Object { $_ })) {
        if ($tok.StartsWith('-')) { continue }
        $dest = $tok.Trim('"', "'")
        break
    }
    if (-not $dest) { return }

    # Classify $wtRaw against git itself (robust for BOTH nested and sibling worktrees): find the MAIN
    # worktree of whatever repo it belongs to; act only if that main worktree is a governed primary AND
    # $wtRaw is a DIFFERENT (linked) worktree of it. All git calls take the RAW path; only the results
    # are canonicalised for comparison. Any git failure -> fail open.
    $porcelain = Invoke-CcxGit -Repo $wtRaw -Arguments @('worktree', 'list', '--porcelain')
    if (-not $porcelain) { return }
    $mainLine = @($porcelain -split "`r?`n") | Where-Object { $_ -match '^worktree ' } | Select-Object -First 1
    if (-not $mainLine) { return }
    $mainWt = ConvertTo-CcxComparablePath -Path ($mainLine -replace '^worktree\s+', '')
    $gov = Test-Governed $mainWt
    if (-not $gov) { return }                                     # repo's main tree isn't governed

    $selfTopRaw = Invoke-CcxGit -Repo $wtRaw -Arguments @('rev-parse', '--show-toplevel')
    if (-not $selfTopRaw) { return }
    $selfTop = ConvertTo-CcxComparablePath -Path $selfTopRaw
    if (-not $selfTop -or $selfTop -eq $mainWt) { return }        # $wtRaw IS the primary -- rule 3 owns it

    # Only an EXISTING local branch, and only if it is not the branch we are already on (a no-op).
    if ($null -eq (Invoke-CcxGit -Repo $wtRaw -Arguments @(
                'rev-parse', '--verify', '--quiet', ("refs/heads/" + $dest)))) { return }
    $head = Invoke-CcxGit -Repo $wtRaw -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($dest -eq $head) { return }

    $newScript = Get-RepoScript $gov.Display 'scripts/worktree/new.ps1'

    # The remediation below has to be RUNNABLE, which is the whole reason -Branch exists on new.ps1:
    # a refname may contain '/' and the worktree DIRECTORY name may not, so handing back
    # `-Name $dest` printed a command that new.ps1 rejects -- for exactly the branch shape (a
    # namespaced ref) that this rule fires on most. Derive a legal directory name from the ref and
    # pass the ref itself separately. Anything outside the directory character class collapses to a
    # single '-', and a leading or trailing '-' is trimmed so the result cannot start with what git
    # would read as a flag.
    $destSlug = ($dest -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if (-not $destSlug) { $destSlug = 'reuse' }

    # Everything below is interpolated into a reason that prints a command. Fold first.
    $dest       = Get-SafeForMessage $dest
    $head       = Get-SafeForMessage $head
    $selfTopRaw = Get-SafeForMessage $selfTopRaw

    Write-Deny -Rule "3b" -Detail "git $Verb -> $selfTopRaw" -Reason @"
BLOCKED: 'git $Verb $dest' would switch a LINKED WORKTREE ($selfTopRaw) onto the existing branch '$dest'.

That worktree belongs to another session, which is building on '$head' right now. Switching it swaps
every file under that session mid-task -- silently -- and drags two sessions' work onto one branch.
This is not hypothetical: it is exactly the hijack that prompted this rule. A session with no worktree
of its own ran a checkout inside somebody else's worktree; git allowed it because '$dest' was not
checked out anywhere.

What to do instead:
  * To BUILD on '$dest', give it its OWN worktree -- git then refuses to check that branch out twice,
    which is the protection you actually want. The branch already EXISTS, so this REUSES it rather
    than forking. -Branch is the git ref; -Name is only the DIRECTORY, which cannot contain '/':
        pwsh -NoProfile -File "$newScript" -Branch '$dest' -Name $destSlug
  * To READ '$dest' without touching any working tree, use the plumbing:
        git -C "$selfTopRaw" show $dest`:<path>        git -C "$selfTopRaw" diff HEAD..$dest
  * If you genuinely OWN this worktree and must switch it, do it from a PLAIN terminal -- the gate
    governs agents, not you. Do not route around this with a shell script; that only hides the
    collision.
"@
}

# ---------------------------------------------------------------------------------------------------
# Rule 2 -- dispatching a fan-out FROM the primary. Checked first: it is the cheapest place to stop a
# workflow that would otherwise burn most of an hour and then report success while having written
# nothing.
# ---------------------------------------------------------------------------------------------------
if ($tool -in @("Task", "Agent", "Workflow")) {
    $root = Test-Governed $cwd
    if ($root) {
        $display = $root.Display
        $newScript = Get-RepoScript $display 'scripts/worktree/new.ps1'
        Write-Deny -Rule "2" -Detail "dispatch $tool" -Reason @"
BLOCKED: this session is running in the SHARED PRIMARY checkout ($display), so it may not dispatch
subagents. A subagent inherits this cwd, cannot create a worktree for itself, and its blocked edits do
not reliably surface back to you -- the fan-out would appear to succeed while writing nothing.

Create a worktree first, then dispatch from it:

    pwsh -NoProfile -File $newScript -Name <short-kebab-task-name>

That prints a worktree path. Ask the user to start the session there (or continue there yourself), then
re-dispatch. If you were only going to READ, do it directly -- reads are never blocked.
"@
    }
    exit 0
}

# ---------------------------------------------------------------------------------------------------
# Rule 3 -- a git command that SWAPS THE PRIMARY'S WORKING TREE out from under the sessions standing
# in it. This is not a hypothetical: a sibling session ran a checkout of its own branch in the shared
# primary and then detached HEAD, and every other session's files silently became a different commit's
# files. Rules 1 and 2 cannot see it -- a git command is a SHELL call, not an Edit, so no amount of
# tool-argument inspection catches it.
#
# Scoped tightly: only verbs that change WHICH COMMIT the primary's tree reflects, or that DISCARD
# work. Reads (status/log/diff/show/fetch/branch/worktree/rev-parse/...) are untouched, and so are
# commit/push/add and `pull` (a fast-forward of a clean tree is ordinary maintenance). A worktree may
# switch its own branch freely -- only the SHARED primary is protected.
#
# NB this hook only exists inside the agent harness. The operator's own terminal is never gated: this
# constrains agents, not the human, who remains the owner of the primary's HEAD.
# ---------------------------------------------------------------------------------------------------
if ($tool -in @("Bash", "PowerShell")) {
    $cmd = [string]$hook.tool_input.command
    if (-not $cmd) { exit 0 }

    # Split ONCE. Each segment carries Raw (parse PATHS from this), Scan (decide VERBS from this, with
    # inert quoted spans blanked) and Prefix (everything earlier on the same logical line, which is the
    # only place a `cd` may be honoured from). Interpreter arguments -- `pwsh -Command "..."`,
    # `bash -c "..."`, `cmd /c "..."` -- come back as extra segments rather than being blanked: they
    # are quoted, but they are CODE THAT RUNS, and blanking them turned a long-standing deny into an
    # allow.
    $segments = @(Split-CcxCommand -Command $cmd)

    # Everything before the git token, on this segment AND on the line before it. A `cd` read from the
    # whole command made the resolver order-blind: `git checkout main && cd ../elsewhere` resolved to
    # `../elsewhere` and allowed a swap of the tree the git call had already acted on.
    function Get-SegmentPrefix($Segment) {
        $idx = Get-CcxGitTokenIndex $Segment.Raw
        $inSeg = if ($idx -gt 0) { $Segment.Raw.Substring(0, $idx) } else { "" }
        return ("$($Segment.Prefix)" + $inSeg)
    }

    # -----------------------------------------------------------------------------------------------
    # Rule 3c -- a git CONFIG write that disarms the SHARED repository. `config` changes no tree, so
    # the verb list never saw it, and its blast radius is worse than a tree swap: every worktree of a
    # clone shares one `.git`, so a config write that repoints hook resolution disables the
    # commit-time gates for every worktree at once. `core.worktree`, `alias.*` and `include.path` are
    # the same class: they redirect what a later git command actually does.
    #
    # Deliberately narrow. Reads (`--get`, `--list`, ...) and every other key stay untouched -- this
    # must not become a general ban on configuring a repo, and setting your own user.email is ordinary
    # setup.
    #
    # Unlike rules 1-3 this does NOT use Test-Governed, because the `.claude/worktrees/` exemption is
    # exactly wrong here: a linked worktree is not the primary, but its config write lands in the
    # SHARED config and harms every sibling. Ask git for the common dir instead, which catches nested
    # worktrees, sibling worktrees and the primary alike. Any git failure falls through to ALLOW.
    # -----------------------------------------------------------------------------------------------
    $dangerKeys = 'core\.hookspath|core\.worktree|alias\.[\w.-]+|include\.path|includeif\.'
    foreach ($seg in $segments) {
        if (-not (Test-CcxGitInvocation $seg.Scan)) { continue }
        if ($seg.Scan -notmatch "(?:\bconfig\b.*?\s|-c\s+)(?<key>$dangerKeys)") { continue }
        $badKey = $Matches['key']
        # A read is not a write.
        if ($seg.Scan -match '(?:^|\s)--(get|get-all|get-regexp|list|show-origin)(\s|$)') { continue }

        $targets = @(Resolve-CcxGitTarget -Line $seg.Raw -Prefix (Get-SegmentPrefix $seg) -Cwd $cwdRaw)
        if ($targets.Count -eq 0) { continue }

        $common = Get-CcxGitCommonDir -Repo $targets[0].Raw
        if (-not $common) { continue }
        $govCfg = Test-GovernedSharedDir (ConvertTo-CcxComparablePath -Path $common)
        if (-not $govCfg) { continue }

        $badKey = Get-SafeForMessage $badKey
        Write-Deny -Rule "3c" -Detail "git config $badKey" -Reason @"
BLOCKED: setting '$badKey' would change the SHARED git configuration of $($govCfg.Display).

Every worktree of this repository shares one .git directory, so this is not a local change: it takes
effect for all of them at once. A config write that repoints hook resolution -- or that aliases a
command, or redirects the working tree -- disables the repository's commit-time gates for every
session on this machine.

What to do instead:
  * If a commit hook is failing, FIX THE CAUSE -- the hook output names it. Never route around a gate;
    that converts a caught problem into an uncaught one.
  * If you need a different hook set for a genuine reason, that is a repository decision. STOP and tell
    the user: "I need to change how this repo resolves its git hooks and the worktree gate blocked it."
  * Ordinary per-user config (user.email, user.name, and anything that is not on the disarm list) is
    untouched and needs no workaround.
"@
    }

    # -----------------------------------------------------------------------------------------------
    # Rule 3d -- `git worktree remove` / `move`, which DESTROYS OR RELOCATES ANOTHER SESSION'S
    # CHECKOUT. Every rule above protects a tree from being swapped; this one protects it from being
    # deleted, which is strictly worse and was entirely unguarded. The verb list could never have
    # caught it: `worktree` is two tokens (`worktree remove`) where every other entry is one, and git
    # refuses to remove the worktree you are STANDING in -- so a `worktree remove` that reaches git is,
    # by construction, aimed at somebody else's.
    #
    # The target is the PATH ARGUMENT, not the cwd, and it cannot be judged with Test-Governed: a
    # linked worktree is exempt there (correctly, for tree swaps) and a sibling worktree falls outside
    # the roots entirely. Ask git whether the path is a worktree of a governed repo instead. Any git
    # failure -- a path that is not a worktree, or does not exist -- falls through to ALLOW.
    # -----------------------------------------------------------------------------------------------
    foreach ($seg in $segments) {
        if (-not (Test-CcxGitInvocation $seg.Scan)) { continue }
        if ($seg.Scan -cnotmatch '\bworktree\s+(?<wtverb>remove|move)(?=\s|$)') { continue }
        $wtVerb = $Matches['wtverb']

        # First positional (non-flag) token after the subcommand is the worktree being acted on.
        $after = ($seg.Raw -replace ('(?s)^.*?\bworktree\s+' + $wtVerb + '\b'), '')
        $victimRaw = $null
        foreach ($tok in @($after -split '\s+' | Where-Object { $_ })) {
            if ($tok.StartsWith('-')) { continue }
            $victimRaw = $tok.Trim('"', "'")
            break
        }
        if (-not $victimRaw) { continue }

        $victimCommon = Get-CcxGitCommonDir -Repo $victimRaw
        if (-not $victimCommon) { continue }
        $govWt = Test-GovernedSharedDir (ConvertTo-CcxComparablePath -Path $victimCommon)
        if (-not $govWt) { continue }

        $pruneScript = Get-RepoScript $govWt.Display 'scripts/worktree/prune-merged.ps1'
        $wtVerb    = Get-SafeForMessage $wtVerb
        $victimRaw = Get-SafeForMessage $victimRaw
        Write-Deny -Rule "3d" -Detail "git worktree $wtVerb" -Reason @"
BLOCKED: 'git worktree $wtVerb $victimRaw' acts on a worktree of $($govWt.Display) that belongs to
ANOTHER SESSION -- git refuses to remove the worktree you are standing in, so this one is not yours.

Removing it deletes that session's working tree and its branch, along with any uncommitted work in
them. There is no undo, and the session using it finds out when its next file read fails.

What to do instead:
  * Cleaning up merged worktrees is a maintenance job with its own dry-run-by-default tool. Run it and
    READ what it proposes before applying anything:
        pwsh -NoProfile -File $pruneScript
  * To find out whether a worktree is still in use, look rather than delete:
        git -C "$($govWt.Display)" worktree list
  * If you are certain it is abandoned and must go now, that is the user's call, not yours. Say so:
    "I want to remove the worktree $victimRaw and I need you to confirm it is not in use."
"@
    }

    # The verb must be a whole SUBCOMMAND. `\bmerge\b` is not enough: a hyphen counts as a word
    # boundary, so it also matches the `merge` inside `merge-base` and `merge-tree` -- both of which
    # are READ-ONLY and are exactly what a session should be using instead of a checkout. Require the
    # verb to end at whitespace or end-of-string, and list `cherry-pick` before `merge` so the
    # alternation prefers it.
    $verbs = 'cherry-pick|checkout|switch|reset|restore|stash|clean|rebase|merge|revert|am|apply'

    # Evaluate EVERY verb-bearing segment, not just the first. `git -C ../x checkout main ; git checkout
    # main` has two invocations and only the second touches this tree; stopping at the first match
    # judged the wrong one. Deny on the first segment whose target set contains a governed tree.
    $verb = $null ; $verbLine = $null ; $targetRaw = $cwdRaw ; $root = $null

    # True once some segment's target had to be INFERRED (from the cwd or a `cd`) rather than stated
    # with `-C`. An explicit `-C` is authoritative about which repository git acts on, so the in-text
    # fallback below must not second-guess it -- `cd <primary> && git -C <sibling> rebase` acts on the
    # sibling, and denying it because the primary's path appears in the `cd` is a false positive.
    $anyInferredTarget = $false

    foreach ($seg in $segments) {
        if (-not (Test-CcxGitInvocation $seg.Scan)) { continue }
        if ($seg.Scan -cnotmatch "\bgit(\.exe)?\b.*?\s(?<verb>$verbs)(?=\s|$)") { continue }
        $segVerb = $Matches['verb']

        $segPrefix = Get-SegmentPrefix $seg

        # Path parsing runs on the RAW line, never on the blanked Scan string: the blanking that stops
        # a commit message supplying a verb would also erase the path. The resolver returns a SET and
        # we deny if ANY member is governed -- a `--work-tree` elsewhere does not stop the cwd's
        # repository being mutated.
        $targets = @(Resolve-CcxGitTarget -Line $seg.Raw -Prefix $segPrefix -Cwd $cwdRaw)

        # Was the repository STATED, or inferred from the cwd / a `cd`? This is a deliberately COARSE
        # test and it is not the resolver's job: the resolver answers WHICH tree, this answers only
        # "did the author name one", which is all the text fallback below needs in order to keep its
        # hands off an explicit `-C`. Case-SENSITIVE, because git's lowercase `-c key=value` is a
        # different flag entirely -- reading it as a path is the defect the shared resolver documents.
        # The attached spelling (`-C../x`) is not matched here, so it reads as inferred: that is the
        # deny side, which is where a guardrail should land when its cheap test is unsure.
        if ($seg.Raw -cnotmatch '(?:^|\s)-C\s+"?([^"\s]+)"?') { $anyInferredTarget = $true }

        if (-not $verb) {
            $verb = $segVerb ; $verbLine = $seg.Raw
            if ($targets.Count -gt 0) { $targetRaw = $targets[0].Raw }
        }
        foreach ($t in $targets) {
            $hit = Test-Governed $t.Comparable
            if ($hit) { $root = $hit ; $verb = $segVerb ; $verbLine = $seg.Raw ; $targetRaw = $t.Raw ; break }
        }
        if ($root) { break }
    }
    if (-not $verb) { exit 0 }

    # `cd <primary>; git checkout ...` and `pushd` defeat both of the above, so also treat any command
    # that NAMES a governed primary as targeting it -- but only where the target was inferred.
    if (-not $root -and $anyInferredTarget) {
        # Separators only. NOT lower-cased: the comparable form is folded on case-insensitive platforms
        # and left alone on case-sensitive ones, and `-match` is case-insensitive in PowerShell either
        # way. On a case-sensitive filesystem that makes this fallback slightly over-inclusive about
        # case, which is the deny side and acceptable for a fallback that only fires on an explicit
        # directory change.
        $normalized = ($cmd -replace '\\', '/')
        foreach ($r in $roots) {
            # Match the primary path only at a DIRECTORY BOUNDARY, never as a raw prefix substring. A
            # sibling worktree is named `<primary>-<task>`, so its path CONTAINS the primary's as a
            # prefix ('.../repo-capture' starts with '.../repo'); a plain .Contains() then falsely
            # re-flagged a legitimate `git -C "<sibling>" merge` whose -C had already resolved to a
            # NON-governed target above. The first lookahead rejects the characters that CONTINUE a
            # directory name ([a-z0-9_-] -> repo-capture, repo2, repo_x are all different dirs): the
            # primary substring is not a boundary there, so those siblings are allowed.
            #
            # `.` is the awkward case and needs the SECOND lookahead. Windows silently STRIPS a
            # trailing dot from a path component, so `cd <primary>.` actually resolves to the primary
            # itself and a checkout there swaps the shared tree -- that MUST block. But `<primary>.old`
            # is a genuinely different directory that must NOT. So a dot cannot simply live in the
            # first reject class (that re-introduced a FALSE NEGATIVE on the tree-swapping
            # `<primary>.`) nor be omitted from all of it (that re-introduced the `<primary>.old` FALSE
            # POSITIVE). `(?!\.[a-z0-9_-])` splits them: it fails the match only when the dot BEGINS a
            # longer name component (`.old`), while a dot followed by a real terminator (quote, space,
            # `;`, end-of-line) passes both lookaheads and matches.
            #
            # Every character that genuinely TERMINATES the path in a real `cd <primary>; git checkout`
            # -- a path separator, whitespace, a quote, `;` `&` `|` `)`, a bare trailing dot, or
            # end-of-string -- clears both lookaheads and still matches, so no real primary tree-swap
            # slips through.
            #
            # THIRD lookahead: honour the SAME `.claude/worktrees/` exemption that Test-Governed
            # already applies. A linked worktree living UNDER the primary is not the primary -- a git
            # verb there swaps only its own tree -- but a path separator clears both lookaheads above,
            # so `<primary>/.claude/worktrees/<name>` matched and DENIED. That is where the harness
            # puts every worktree it creates, so `cd <own worktree> && git rebase ...` -- the most
            # ordinary thing a session does -- was refused as if it were swapping the shared tree,
            # while the identical command with the path omitted was allowed: the block depended on how
            # the command was SPELLED, not on what it touched. Only this one subpath is exempt; the
            # primary itself and any OTHER path inside it (`<primary>/.claude/hooks`) still match and
            # still deny.
            $boundary = [regex]::Escape($r.Compare) +
                '(?![a-z0-9_-])(?!\.[a-z0-9_-])(?!/\.claude/worktrees/)'

            # The mention must be a DIRECTORY-CHANGE ARGUMENT, not merely present in the command.
            #
            # Matching the path ANYWHERE made the verdict depend on what else the command happened to
            # say. Measured three times in one session, all from a worktree and all safe: a
            # `git restore <two files>` denied as "would change the working tree of the SHARED PRIMARY"
            # because a later `cat <primary>/.git/ccx-coord/...` in the same compound command named the
            # primary. Isolating the identical git call was allowed instantly. Worse than the noise:
            # the refusal TEXT was wrong about what the command did, so the operator reading it was
            # told the primary was at risk when it never was -- and a gate that misdescribes the thing
            # it blocked trains people to route around it. This is the same defect the nested-worktree
            # lookahead fixed, arriving through a different spelling.
            #
            # Narrowing is safe because the fallback has exactly one job. Every OTHER way of aiming a
            # git verb at the primary is resolved STRUCTURALLY before this point and sets $root without
            # it: the cwd, an explicit `-C`, and `--work-tree` / `--git-dir` (added to the candidate
            # set by the resolver, which is why a RELATIVE `--work-tree=../../..` still denies -- it
            # never reaches this text scan). The fallback exists solely for `cd <primary>; git
            # checkout`, where the verb runs somewhere the hook cannot observe because the directory
            # changes mid-command. So require the directory change, and the true positive is untouched
            # while the false one disappears.
            #
            # Still deliberately conservative, and ORDER-BLIND -- unlike the resolver above, which
            # honours a `cd` only from the text that ran BEFORE the git call. This scan reads the whole
            # command, so `cd <primary>; cd <elsewhere>; git checkout` denies, and so does
            # `git checkout main && cd <primary>`. Both are false positives on paper. They are accepted
            # because the alternative is reasoning about where a shell lands after an arbitrary
            # sequence of directory changes, and being wrong in THAT direction is a silent tree swap.
            # Once a command mentions stepping into the primary at all, this hook stops arguing.
            $dirChange = '(?:^|[;&|(]|\s)(?:cd|chdir|pushd|set-location|sl)' +
                '(?:\s+(?:/d|-path|-literalpath))?\s+["'']?' + $boundary
            if ($normalized -match $dirChange) { $root = $r; break }
        }
    }
    if (-not $root) {
        # Not the shared primary. It may still be a governed LINKED WORKTREE being hijacked onto an
        # existing branch (rule 3b) -- Write-Deny + exit if so; otherwise this returns and we allow.
        # Hand down the LINE the verb was found on and the tree already resolved from it, so 3b judges
        # the same command rule 3 did (including one recursed out of an interpreter argument).
        Test-WorktreeHijack $verb $verbLine $targetRaw
        exit 0
    }

    $display = $root.Display
    $newScript = Get-RepoScript $display 'scripts/worktree/new.ps1'
    $restoreScript = Get-RepoScript $display 'scripts/worktree/restore-primary.ps1'
    Write-Deny -Rule "3" -Detail "git $verb" -Reason @"
BLOCKED: 'git $verb' would change the working tree of the SHARED PRIMARY checkout ($display).

Other sessions are standing in that directory right now. Switching its branch (or resetting, stashing
or cleaning it) swaps every file under them mid-task -- silently. This has already happened: a session
checked out its own branch in the primary and left HEAD detached, and the tree other sessions were
reading became a different commit's tree.

You almost never need this:
  * To BUILD, work in your own worktree -- and you can create one from here:
        pwsh -NoProfile -File $newScript -Name <short-kebab-task-name>
  * To READ another branch WITHOUT touching any working tree, use the plumbing:
        git -C "$display" show <ref>:<path>        git -C "$display" ls-tree <ref>
        git -C "$display" diff <ref>..<ref>        git -C "$display" log <ref>
  * If the primary is genuinely broken (detached HEAD, wrong branch), REPAIR it rather than checking
    out by hand -- this is allowed, and it refuses if the tree is dirty:
        pwsh -NoProfile -File $restoreScript

If none of those fit, STOP and tell the user: "I need to change the primary checkout's branch and the
worktree gate blocked it." The primary's HEAD belongs to the user, not to a session.
"@
}

# ---------------------------------------------------------------------------------------------------
# Rule 1 -- writing INTO the primary's working tree, from anywhere.
# ---------------------------------------------------------------------------------------------------
if ($tool -notin @("Write", "Edit", "MultiEdit", "NotebookEdit")) { exit 0 }

$target = [string]$hook.tool_input.file_path
if (-not $target) { $target = [string]$hook.tool_input.notebook_path }
if (-not $target) { exit 0 }   # unrecognized tool shape -> fail open

# cwd is used ONLY to root a relative path -- never as the thing being judged.
if (-not [System.IO.Path]::IsPathRooted($target)) {
    if (-not $cwdRaw) { exit 0 }
    $target = Join-Path $cwdRaw $target
}

# ---------------------------------------------------------------------------------------------------
# Rule 1a -- the gate's OWN enforcement surface. The installed script and its allowlist live OUTSIDE
# every governed root, so Test-Governed returned $null for them and rule 1 allowed an Edit to either:
# one line written to the allowlist disarms the gate for every session on this machine, permanently and
# silently. The earlier answer was to keep the allowlist out of the deny text -- obscurity over a file
# one directory listing away, and not a control. THE GATE'S OWN SURFACE MUST BE GOVERNED.
#
# Scoped to the hooks directory ONLY, deliberately. The harness settings file is NOT covered: editing
# it is sanctioned work, and blocking it would break a supported workflow to close a hole that requires
# a far more deliberate act than deleting a stray-looking text file. This closes the accident and the
# cheap route-around, which is all a guardrail is for.
#
# The installer is unaffected: it writes from a plain terminal via Set-Content/Copy-Item, which is a
# SHELL call and not an Edit, so no tool-argument rule sees it. That asymmetry is the point -- the human
# installs and removes the gate; a session may not.
# ---------------------------------------------------------------------------------------------------
# Match the two exact FILES, never their parent directory. Keying on the parent looked tidier and was
# wrong twice over: $ReposFile is a parameter that can point anywhere (under test it sits in a temp dir,
# where it swallowed every unrelated path), and the hooks directory also holds things this rule has no
# business governing. The surface worth protecting is precisely the kill switch and the script it arms.
$gateFiles = @(
    (ConvertTo-CcxComparablePath -Path $ReposFile)
    (ConvertTo-CcxComparablePath -Path (Join-Path (Split-Path -Parent $ReposFile) "worktree_gate.ps1"))
) | Where-Object { $_ }
if ((ConvertTo-CcxComparablePath -Path $target) -in $gateFiles) {
    Write-Deny -Rule "1a" -Detail $target -Reason @"
BLOCKED: this writes to the worktree gate's own enforcement surface ($target).

That directory holds the installed hook and its allowlist. The allowlist is the gate's kill switch -- a
single edit there turns it off for every session on this machine, so a session may not write here at
all. This is not a file to fix in passing.

If the gate is genuinely wrong -- a false positive, a rule that needs changing -- fix it at the SOURCE
and re-install, which is a human act from a plain terminal:

    scripts/hooks/worktree_gate.ps1        the rule you want to change
    scripts/worktree/install-gate.ps1      installs it (refuses to run inside an agent session)

If you need it OFF right now, say so and let the user decide, in these words: "I want the worktree gate
turned off and I need you to do it." Do not disable it yourself.
"@
}

$root = Test-Governed (ConvertTo-CcxComparablePath -Path $target)
if (-not $root) { exit 0 }

$display = $root.Display

# Point the session at worktrees that ALREADY exist before it makes another one. Without this, every
# retry mints a fresh worktree and the machine fills up with them.
$worktrees = @()
try {
    $porcelain = Invoke-CcxGit -Repo $display -Arguments @('worktree', 'list', '--porcelain')
    if ($porcelain) {
        $worktrees = @(
            @($porcelain -split "`r?`n") |
                Select-String -Pattern '^worktree (.+)$' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } |
                # `$root` is the object from Test-Governed, NOT a string -- comparing a path to it was
                # always -ne, so the filter never removed anything and the PRIMARY ITSELF was listed
                # first under "REUSE one if it is yours", displacing a real worktree off the cap below.
                # The one part of this hook whose entire job is steering the next action was steering it
                # back at the tree we had just refused. Compare against the canonical form.
                Where-Object { (ConvertTo-CcxComparablePath -Path $_) -ne $root.Compare }
        )
    }
} catch { $worktrees = @() }

$worktreeHint = if ($worktrees.Count -gt 0) {
    "`n`nWorktrees that already exist -- REUSE one if it is yours before creating another:`n" +
    (($worktrees | Select-Object -First 8 | ForEach-Object { "    $_" }) -join "`n")
} else { "" }

$newScript = Get-RepoScript $display 'scripts/worktree/new.ps1'
$rescueScript = Get-RepoScript $display 'scripts/worktree/rescue.ps1'
Write-Deny -Rule "1" -Detail $target -Reason @"
BLOCKED: this write targets the SHARED PRIMARY checkout ($display), where concurrent sessions collide.
This is a hard gate. Re-issuing the same edit will fail again -- do not retry it, and do not route
around it with a shell command; that only hides the collision.

You are NOT blocked from working. Writes to any linked worktree, to a scratch directory, or to any
other repo are allowed FROM THIS SESSION -- you do not need to relocate, cd, or restart. Only the
primary's own working tree is off limits. Do one of these:

  A) BUILD IN A WORKTREE (the normal path). Create one, then re-issue your edit against an ABSOLUTE
     path inside it:
         pwsh -NoProfile -File $newScript -Name <short-kebab-task-name>
     It prints the worktree path. It gets its own branch off a freshly fetched trunk, and it runs the
     project's configured setup hook, so its dependencies are its own and tests there run against that
     code.

  B) RESCUE WORK ALREADY IN THE PRIMARY. If the primary's tree is already dirty, move it wholesale
     rather than re-doing it:
         pwsh -NoProfile -File $rescueScript -Name <short-kebab-task-name>

  C) If neither fits -- e.g. the change genuinely belongs in the primary -- STOP and tell the user
     exactly that, in these words: "The worktree gate blocked a write to the primary checkout and I
     need you to decide." Do not attempt to disable the gate.$worktreeHint
"@
