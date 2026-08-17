#Requires -Version 7.3
<#
.SYNOPSIS
    Prune sibling git worktrees that are merged, clean, AND unoccupied.

.DESCRIPTION
    Automates the recurring cleanup so finished worktrees don't pile up.

    THE RULE IS:  prune = merged AND clean AND NOT occupied.

    CLEAN + MERGED IS NOT UNOCCUPIED, AND OCCUPANCY IS A VETO ONLY. It can stop a removal; it can
    never authorise one. There is no heartbeat anywhere in this system, so nothing here can PROVE a
    session is gone -- a DEAD/STALE/absent verdict is the ABSENCE OF A VETO, not a permission. When
    the fence cannot look at all, nothing is pruned.

    Enumerates the <primary>-<name> sibling worktrees that new.ps1 creates and removes each one that
    is ALL of:

      (a) merged     -- no commits beyond the trunk, OR a merged PR whose head is this exact tip, OR
                        its OWN upstream branch is gone (squash-merged + remote-deleted),
      (b) clean      -- no uncommitted tracked changes AND no untracked files (see below),
      (c) unlocked   -- `git worktree lock` is git's own "in use" flag and this script honours it,
      (d) unoccupied -- no live session is sitting in it OR in a worktree nested inside it, its git
                        metadata has not been touched within -IdleHours, and it does not contain
                        another registered worktree.

    "SIBLING" IS NOT A PREFIX MATCH. The candidate set used to be every registered worktree whose
    path starts with `<primary>-`, which silently includes `<primary>-work/.claude/worktrees/x` -- a
    HARNESS-MANAGED nested worktree, the exact place the harness relocates a live session to, and the
    one population this header promised never to touch. Nested trees under the PRIMARY escaped only
    by the accident that `<primary>/` is not `<primary>-`. Sibling-ness is now a STRUCTURAL test
    (Test-CcxSiblingWorktreePath: same parent directory, leaf exactly `<primary-leaf>-<something>`,
    no `.claude/worktrees/` segment); anything the raw prefix caught and the structure rejects is
    listed as a non-candidate rather than silently dropped. -Name cannot reach them either.

    THIS TOOL DESTROYS OTHER SESSIONS' WORK IF IT IS WRONG. It removed an occupied worktree once:
    `git worktree remove --force` deleted the .git pointer, deregistered the tree, then failed to
    delete the directory, leaving a folder git no longer recognised -- the session working there had
    every subsequent git command fail. So the bias here is fixed and not negotiable: A FALSE SKIP IS
    A MINOR ANNOYANCE, A FALSE PRUNE DESTROYS A SESSION. Every check that cannot reach a confident
    answer SKIPs. Nothing is ever traded for tidiness.

    OCCUPANCY IS NOT IMPLIED BY CLEAN+MERGED. A session can sit in a worktree with nothing
    uncommitted -- a brand-new worktree has zero commits, so it is "an ancestor of the trunk" and
    perfectly clean from the second it is created, which is exactly the state that got destroyed. Two
    independent occupancy signals are therefore required, and either one vetoes:

      1. THE LIVENESS FENCE (scripts/coord/occupancy.ps1, shared with presence.ps1). Reads the
         harness's per-session records, maps each session's recorded cwd onto a worktree, and fences
         it on pid + process start time. Only LIVE / UNVERIFIED / UNREADABLE veto, for the veto-only
         reason above. A session in a NESTED worktree vetoes its ancestor too.
      2. RECENT ACTIVITY (-IdleHours, default 36). Newest mtime of the worktree's PRIVATE git
         metadata (index, HEAD, logs/HEAD, ...). This is the signal that does NOT depend on a
         recorded cwd, and it is what covers the fence's biggest blind spot -- so it is not a nicety,
         it is the load-bearing one for the class of worktree this tool actually prunes. If it cannot
         be read, that is a veto too. Confirm a specific worktree past this veto with -Name <slug>;
         -Name never overrides signal 1, a nested worktree, or a lock.

    WHAT THE FENCE CANNOT SEE (printed on every run, because a fence believed to be wider than it is
    is worse than no fence):
      * a session that writes into this worktree BY ABSOLUTE PATH from somewhere else. Measured on
        the repo this was developed in, over 30 days, 29% of the Edit/Write calls made by sessions
        sitting in the primary landed in a sibling. On a later run of that same repo signal 1
        vetoed NONE of the sibling worktrees, including one a session was demonstrably building in.
        Signal 2 is what stood between that session and this script;
      * a cwd recorded as a UNC (\\host\C$\...) or 8.3 short path -- the match is a normalised string
        compare, and neither spelling normalises to the worktree's own path;
      * a session that never registered;
      * a session that only writes/edits files and runs no git command: it touches none of the seven
        metadata files, so signal 2 goes quiet on it as well.
    It DOES see editor-hosted sessions as well as terminal ones: the file registry carries every
    surface, and the match is purely path-based (the harness's own session-listing tooling only lists
    what it spawned).

    FENCE UNAVAILABLE => NOTHING IS PRUNED, LOUDLY (exit 2). AN EMPTY ROSTER AND AN UNREADABLE ROSTER
    ARE DIFFERENT OUTCOMES that produce the same empty answer, so availability is checked explicitly:
    at least one config root with a session registry, at least one readable record, and NO record
    that failed to parse (an unparseable record's cwd is unknowable, so it cannot be cleared from any
    candidate -- and a file caught half-written is precisely what a session that launched a second ago
    looks like). When it is unavailable every candidate becomes SKIP and the run exits non-zero rather
    than silently pruning unfenced, and THE FENCE IS RE-READ IMMEDIATELY BEFORE EACH REMOVAL -- once
    per candidate, not once per run -- so a fence that DIES mid-run stops the rest. That re-read
    BOUNDS the staleness; it does not remove it. The cleanliness check and the removal itself still
    sit between the read and the git command, so the window is one candidate's worth of work instead
    of the whole batch's, and it is still not atomic. The receipt reports how many reads there were,
    because "the fence ran" must never imply "the fence covered it". There is deliberately no
    override flag.

    EVERYTHING THAT NARROWS THE FENCE IS DECLARED IN RED, on the run and in the JSON receipt --
    -IdleHours 0, an -IdleHours below the floor, an explicit -ConfigRoot, a FAILED fetch (merge
    decisions then rest on stale refs), a gh PR probe that errored, and every -Name-confirmed
    worktree. -Name is the one worth spelling out: it is -IdleHours 0 scoped to one tree, and since
    signal 1 has been measured vetoing none of the real siblings on a busy repo, `-Apply -Name <slug>`
    can leave a candidate with no working occupancy signal at all. It stays available because there
    are legitimate uses, but it is never silent -- an operator who believes they are fenced when they
    are not is worse off than one who knows they aren't.

    OUTCOMES, NOT INTENTIONS. The summary counts what actually happened -- removed / failed /
    skipped, branches deleted / kept -- because a destructive tool that over-reports what it destroyed
    is actively misleading (it used to print the count of candidates it INTENDED to remove). A removal
    is only counted as removed once the directory is verified gone and deregistered. A FAILED REMOVAL
    IS WORSE THAN NO REMOVAL, so it is diagnosed on the spot: git deregisters a worktree even when it
    cannot finish deleting the files, so this reports whether the directory, its .git pointer and its
    registration survived, and prints the recovery recipe for the orphaned case. `git worktree prune`
    IS NEVER RUN -- it deregisters ANY worktree whose directory is momentarily missing, including the
    harness-managed ones this script must never touch, and it would finish the destruction a failed
    removal left half done.

    AN ORPHAN OUTLIVES THE RUN THAT MADE IT, SO IT IS REMEMBERED. Once git has deregistered a
    worktree it is no longer in `git worktree list`, so it drops out of the candidate set and the NEXT
    run reported a green all-clear over a directory this script had broken -- the recovery recipe
    existed only in the first run's scrollback. Every orphan is now recorded in the shared state root
    (prune-merged-orphans.json) and re-reported, with the recipe, on every subsequent run until the
    directory is gone or re-registered. A directory that still carries a .git FILE pointing into this
    repo's worktree admin area while git no longer lists it is reported the same way, ledger or not.

    EXIT CODES, highest severity wins: 0 nothing wrong; 1 something was attempted and failed without
    destroying anything; 2 REFUSED -- nothing was attempted because safety could not be established
    (bad cwd, unavailable fence, a -Name that matched nothing); 3 ORPHANED -- a directory is broken on
    disk right now and needs the recovery recipe. 3 outranks 2 because damage on disk outranks a
    refusal to act.

    A BRANCH IS NEVER FORCE-DELETED ON A STALE VERDICT. `git branch -d` refuses a branch merged only
    into the remote trunk when the local trunk lags, so `-D` used to be the ROUTINE path and git's last
    protection was overridden every time. Now: `-d` first, and `-D` only after re-verifying, at that
    moment, that `<trunk>..<branch>` is empty -- i.e. every commit on it is already reachable from the
    trunk and the delete cannot lose anything. Otherwise the BRANCH IS KEPT and reported. A stale ref
    costs nothing; a destroyed commit costs a session.

    DRY-RUN by default: prints the decision table and does nothing. -Apply re-evaluates everything
    from scratch in the same run and acts on THAT table, never on a table you read a minute ago.

    NEVER touches: the primary checkout, the harness-managed `.claude/worktrees/` worktrees, worktrees
    that do not share the primary's parent directory, detached worktrees, or the separate sibling
    REPOS living beside this one. Must be run FROM the primary checkout; it refuses loudly anywhere
    else rather than reporting "nothing to consider". See docs/PRUNING.md.

.EXAMPLE
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1                   # dry run, no action
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Fetch            # dry run, refresh refs
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply            # remove the ones that pass
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply -Name auth # confirm past the activity veto
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Apply -SkipFetch # offline / faster
    pwsh -NoProfile -File scripts/worktree/prune-merged.ps1 -Json             # machine-readable receipt
#>
[CmdletBinding()]
param(
    # Actually remove. Default is a dry run.
    [switch]$Apply,
    # Skip the `git fetch --prune` even under -Apply (offline / speed). Stale refs decide the merge test.
    [switch]$SkipFetch,
    # Fetch during a DRY RUN too. Off by default: fetch --prune rewrites remote-tracking refs, which is
    # what turns an upstream into [gone] -- a "safe, does nothing" preview should not enlarge the next
    # apply's blast radius.
    [switch]$Fetch,
    # Restrict to these worktrees (slug `<primary>-<name>` or bare `<name>`), and confirm them past the
    # recent-activity veto. Never overrides the liveness fence, a nested worktree, or a worktree lock.
    [string[]]$Name,
    # Don't ask gh about merged PRs (offline, or no gh).
    [switch]$SkipGh,
    # Emit JSON: the same decision objects the table renders, plus the fence receipt and the counts.
    [switch]$Json,
    # Repo to operate on. Defaults to this script's own checkout -- which is only a HINT: it is
    # validated against the primary below and the run refuses if they differ.
    [string]$RepoRoot,
    # Config roots for the liveness fence. Defaults to every registry the shared fence can find.
    # Setting it explicitly REPLACES the real registry, so the run is reported as reduced-assurance.
    [string[]]$ConfigRoot,
    # A worktree whose git metadata was touched more recently than this is treated as occupied. Default
    # 36h: longer than any plausible working day, because this is the only signal that sees a session
    # writing in by absolute path, and on the repo this was developed in it was once measured within
    # 1.6h of expiring on two OCCUPIED worktrees. 0 turns signal 2 OFF and the run says so in red --
    # and so does anything under the floor below, because only the literal 0 used to be declared:
    # `-IdleHours 0.5`, typed for "half an hour", released every worktree and printed no warning at all.
    [double]$IdleHours = 36,
    # Liveness fence tolerance, passed through to the shared fence.
    [int]$StartSkewMinutes = 15,
    # The ref a branch must be merged into. Defaults to the configured trunk (ccx.config.json /
    # CCX_TRUNK / the remote's recorded default branch).
    [string]$MainRef
)

$ErrorActionPreference = "Stop"
# This script decides what to destroy from git EXIT CODES (a non-zero `rev-list`, `branch -d`, or
# `worktree remove` is data, not a failure). Never let a native non-zero exit turn into a throw.
$PSNativeCommandUseErrorActionPreference = $false

# Config discovery, the state root, trunk resolution and the ONE path-folding routine. Five copies of
# the folding helper had drifted and only one canonicalised; this is that one.
. "$PSScriptRoot/../coord/_common.ps1"
# The cwd -> worktree matcher, the liveness fence, and the availability receipt. One copy, shared with
# presence.ps1: two copies of a safety check drift, and the copy that drifts is the untested one.
. "$PSScriptRoot/../coord/occupancy.ps1"

$EXIT_OK = 0
$EXIT_FAILED = 1   # something was attempted and did not fully succeed
$EXIT_REFUSED = 2  # nothing was attempted, because safety could not be established
$EXIT_ORPHANED = 3 # a directory is broken on disk right now (this run, or one before it)

# The MOST SEVERE outcome decides the code, and severity is the numeric order above. A run that
# refuses AND leaves an orphan must report the orphan: a refusal costs the operator a re-run, a broken
# directory costs a session every git command it tries.
$exit = $EXIT_OK
function Set-Exit([int]$Code) { if ($Code -gt $script:exit) { $script:exit = $Code } }

# The floor under -IdleHours. On the repo this was developed in, signal 2 was measured at 10.4h on a
# worktree that was demonstrably occupied, so a window under this one releases trees that measurement
# says are in use.
#
# DELIBERATELY NOT A PARAMETER. A floor an operator can lower is not a floor -- it is a second copy of
# -IdleHours with a reassuring name. Change it here, in a commit, with the measurement that justifies
# the new value.
$IDLE_FLOOR_HOURS = 12

function Write-Note([string]$Text, [string]$Colour = 'DarkGray') {
    if (-not $Json) { Write-Host $Text -ForegroundColor $Colour }
}

# --- Resolve and validate where we are ----------------------------------------------------------
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path }
elseif (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot does not exist: $RepoRoot" }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

# A negative -IdleHours puts the cut-off in the FUTURE, so `$activity -gt $idleCut` can never fire and
# signal 2 is silently dead. Refuse rather than run with a disarmed veto that still looks armed.
if ($IdleHours -lt 0) {
    if ($Json) { @{ error = 'IdleHours must be >= 0'; idleHours = $IdleHours; exitCode = $EXIT_REFUSED } | ConvertTo-Json -Depth 4 | Write-Output }
    else { Write-Host "REFUSED: -IdleHours $IdleHours is negative, which would disarm the activity veto while appearing to set it." -ForegroundColor Red }
    exit $EXIT_REFUSED
}

# The trunk is what every merge decision is measured against, so an unresolvable one is a refusal, not
# a default. Guessing `origin/main` in a repo whose trunk is something else answers "not merged" for
# every candidate -- which looks like a safe, tidy, green run and is really a silently blind one.
if (-not $MainRef) {
    try { $MainRef = Get-CcxTrunk -Repo $RepoRoot }
    catch {
        $why = $_.Exception.Message
        if ($Json) { @{ error = "cannot determine the trunk: $why"; repoRoot = $RepoRoot; exitCode = $EXIT_REFUSED } | ConvertTo-Json -Depth 4 | Write-Output }
        else {
            Write-Host "REFUSED: cannot determine which ref work must be merged into." -ForegroundColor Red
            Write-Host "  $why" -ForegroundColor Red
            Write-Host "  Pass -MainRef <ref> explicitly, or set CCX_TRUNK." -ForegroundColor Red
        }
        exit $EXIT_REFUSED
    }
}

$occ = Get-WorktreeOccupancy -Repo $RepoRoot -ConfigRoot $ConfigRoot -StartSkewMinutes $StartSkewMinutes

if (-not $occ.RepoFound) {
    if ($Json) { @{ error = 'not a git repository'; repoRoot = $RepoRoot; exitCode = $EXIT_REFUSED } | ConvertTo-Json -Depth 4 | Write-Output }
    else { Write-Host "REFUSED: $RepoRoot is not inside a git repository." -ForegroundColor Red }
    exit $EXIT_REFUSED
}

# Run from the primary, and say so when you are not. The old script silently found no `<self>-*`
# siblings from inside a worktree and printed a green "nothing to consider", which reads exactly like
# "everything is tidy". A WRONG-CWD RUN MUST REFUSE LOUDLY, NEVER GREEN NO-OP.
if ((ConvertTo-CcxComparablePath $RepoRoot) -ne (ConvertTo-CcxComparablePath $occ.PrimaryPath)) {
    if ($Json) {
        @{ error = 'not the primary checkout'; repoRoot = $RepoRoot; primary = $occ.PrimaryPath; exitCode = $EXIT_REFUSED } |
            ConvertTo-Json -Depth 4 | Write-Output
    }
    else {
        Write-Host "REFUSED: this is a linked worktree, not the primary checkout." -ForegroundColor Red
        Write-Host "  here:    $RepoRoot" -ForegroundColor Red
        Write-Host "  primary: $($occ.PrimaryPath)" -ForegroundColor Red
        Write-Host "  Sibling worktrees are named after the PRIMARY, so from here the candidate set is" -ForegroundColor Red
        Write-Host "  empty for the wrong reason. Re-run it from the primary." -ForegroundColor Red
    }
    exit $EXIT_REFUSED
}

$RepoRootNorm = ConvertTo-CcxComparablePath $RepoRoot
$RepoLeaf = Split-Path $RepoRoot -Leaf

# --- Shared state: the orphan ledger and the claim registry --------------------------------------
# Both live in the state root under the SHARED git directory, which is the whole point: it is
# identical across worktrees, isolated per clone, and uncommittable -- so it OUTLIVES the worktree
# that created it. That is exactly why a removal can strand a claim, and why the ledger can remember
# an orphan across runs.
#
# NEVER LOOKED is not CLEAN, so the resolution is allowed to fail and the failure is recorded rather
# than smoothed over: a repo with no ccx.config.json still gets an orphan ledger (in the git dir), but
# it gets no claim survey, and the receipt says `scanned: false` rather than an empty list.
$gitCommonDir = Get-CcxGitCommonDir -Repo $RepoRoot
$stateRoot = $null
try { $stateRoot = Get-CcxStateRoot -Repo $RepoRoot } catch { $stateRoot = $null }

$ledgerPath =
    if ($stateRoot) { Join-Path $stateRoot 'prune-merged-orphans.json' }
    elseif ($gitCommonDir) { Join-Path $gitCommonDir 'prune-merged-orphans.json' }
    else { '' }
$claimsDir = if ($stateRoot) { Join-Path $stateRoot 'claims' } else { '' }

# Anything that narrows what the two occupancy signals can see. Named on the run and in the JSON, so a
# reduced fence is never mistaken for a full one.
$activityVeto = ($IdleHours -gt 0)
$reducedAssurance = @()
if (-not $activityVeto) {
    $reducedAssurance += 'activity veto DISABLED (-IdleHours 0): signal 2 is OFF, so a session writing in by absolute path is invisible to this run'
}
elseif ($IdleHours -lt $IDLE_FLOOR_HOURS) {
    # Only the literal 0 used to be declared. Everything between 0 and the floor disarmed signal 2 just
    # as effectively and printed nothing.
    $reducedAssurance += "activity window NARROWED to $IdleHours h (floor $IDLE_FLOOR_HOURS h): on the repo this tooling was developed in, an OCCUPIED worktree was measured at 10.4 h idle, so signal 2 will release trees somebody is in"
}
if ($ConfigRoot) {
    $reducedAssurance += "liveness fence scoped to an explicit -ConfigRoot ($($ConfigRoot -join ', ')): the machine's real session registry was NOT consulted"
}

# --- Refresh refs (see -Fetch) -------------------------------------------------------------------
$fetched = $false
$fetchDetail = ''
if ($SkipFetch) { $fetchDetail = 'skipped (-SkipFetch): merge decisions use whatever refs are on disk' }
elseif (-not ($Apply -or $Fetch)) { $fetchDetail = 'skipped (dry run): pass -Fetch to refresh the remote refs first' }
else {
    Write-Note "Fetching origin (--prune)..."
    & git -C $RepoRoot fetch origin --prune --quiet 2>$null
    if ($LASTEXITCODE -eq 0) { $fetched = $true; $fetchDetail = 'origin fetched (--prune)' }
    else {
        $fetchDetail = "FETCH FAILED (exit $LASTEXITCODE): merge decisions are being made against stale refs"
        # Its own text says the merge decisions rest on stale refs, which IS reduced assurance. It used
        # to render in the same dark grey as "-SkipGh", below the notice an operator actually reads.
        $reducedAssurance += $fetchDetail
    }
}

# --- Merge signal --------------------------------------------------------------------------------
function Get-GitHubSlug([string]$Repo) {
    $url = Invoke-CcxGit -Repo $Repo -Arguments @('remote', 'get-url', 'origin')
    if (-not $url) { return $null }
    if ($url -match '^(?:https?://[^/@]*@?[^/]*github\.com/|git@github\.com:|ssh://git@github\.com/)(?<o>[^/]+)/(?<r>[^/]+?)(?:\.git)?/?$') {
        return "$($Matches['o'])/$($Matches['r'])"
    }
    return $null
}

$ghSlug = if ($SkipGh) { $null } else { Get-GitHubSlug $RepoRoot }
$hasGh = (-not $SkipGh) -and $ghSlug -and [bool](Get-Command gh -ErrorAction SilentlyContinue)
# The receipt is written AFTER the probes, from what they actually answered. It used to be decided up
# front from "gh is installed and origin is GitHub", so an unauthenticated, rate-limited, offline or
# unauthorised gh produced "PR probe scoped to <slug>" on a run where every probe errored -- the same
# defect class (a receipt asserting a check that never ran) this script was rewritten to remove.
$ghAttempts = 0
$ghFailures = 0
$ghFirstError = ''

# Is `<trunk>..<branch>` empty right now? Used twice: once as the cheap merge signal, and again
# immediately before a branch delete, so a verdict formed seconds earlier can never authorise -D.
function Test-ContainedInMain {
    param([string]$Branch)
    $n = (& git -C $RepoRoot rev-list --count "$MainRef..refs/heads/$Branch" 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ Ok = $false; Unique = -1 } }
    return @{ Ok = $true; Unique = [int]$n }
}

# A branch with exactly one reflog entry ("branch: Created from ...") never advanced. That is NOT the
# same thing as merged, even though both look like "0 commits beyond the trunk" -- and the never-used
# case is precisely the state of the worktree that got destroyed.
function Test-BranchNeverUsed {
    param([string]$Branch)
    $log = @(& git -C $RepoRoot reflog show --format='%gs' "refs/heads/$Branch" 2>$null)
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($log.Count -eq 1 -and $log[0] -match '^branch: Created from')
}

# WHY THERE ARE THREE MERGE SIGNALS: UNDER SQUASH-MERGE, THE OBVIOUS ONES LIE.
#
# A squash merge replays a branch's changes as ONE NEW COMMIT with a new hash and no parent link back
# to the branch. So AFTER the work has landed in the trunk:
#
#   * `git rev-list --count <trunk>..<branch>` still counts every original commit  -> says NOT merged
#   * `git merge-base --is-ancestor <branch> <trunk>` is false                     -> says NOT merged
#   * `git cherry <trunk> <branch>` marks the commits '+' (unmerged) unless the patch-ids match
#     exactly, which they stop doing the moment anything was rebased, amended, or conflict-resolved
#
# All three are asking one question -- "is this commit reachable from the trunk" -- and squash-merge
# is defined by making the answer no. Ahead-of-main is therefore not evidence of unmerged work. That
# is why signal 1 below cannot stand alone, and why signal 2 (a merged PR whose head is THIS EXACT
# TIP) and signal 3 (the branch's OWN upstream is gone) exist at all.
#
# THE CONVERSE TRAP IS WORSE, and it is the one that destroyed a worktree: signal 1 answering ZERO
# does not mean "merged" either. A branch created seconds ago has no commits beyond the trunk. Hence
# Test-BranchNeverUsed above, and hence the occupancy fence -- neither of which is a merge test.
function Test-Merged {
    param([string]$Branch)
    $notes = @()
    $tip = (& git -C $RepoRoot rev-parse --verify --quiet "refs/heads/$Branch^{commit}" 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $tip) {
        return @{ Merged = $false; Reason = "branch $Branch has no resolvable tip"; Unique = -1; Notes = $notes; NeverUsed = $false }
    }
    $tip = $tip.Trim()

    # 1) Nothing beyond the trunk. Cheap, offline, and true by construction for a brand-new
    #    worktree -- which is why (d) occupancy exists.
    $c = Test-ContainedInMain -Branch $Branch
    if (-not $c.Ok) {
        return @{ Merged = $false; Reason = "cannot compare against $MainRef (does it exist?)"; Unique = -1; Notes = $notes; NeverUsed = $false }
    }
    $uniq = $c.Unique
    if ($uniq -eq 0) {
        if (Test-BranchNeverUsed -Branch $Branch) {
            return @{
                Merged = $true; Unique = 0; Notes = $notes; NeverUsed = $true
                Reason = "never used: 0 commits and the branch never advanced (nothing was merged FROM here)"
            }
        }
        return @{ Merged = $true; Reason = "no commits beyond $MainRef"; Unique = 0; Notes = $notes; NeverUsed = $false }
    }

    # 2) A merged PR -- but only when its head is THIS EXACT TIP. `--head <branch>` matches by NAME, so
    #    a branch continued after its PR merged (or a name reused from an earlier life) otherwise reads
    #    as merged and gets its later commits force-deleted. Repo-scoped: gh resolves the repo from the
    #    CALLER'S cwd otherwise, so launching this by absolute path from another checkout would answer
    #    from that repo's merged PRs.
    #    `--json number,headRefOid` is ONE argv entry. A space after the comma makes PowerShell pass
    #    three, gh rejects the third, and this whole block silently never ran (it didn't, for a while)
    #    while the receipt still claimed a PR probe was scoped. Keep the comma tight.
    if ($hasGh) {
        $script:ghAttempts++
        $raw = & gh pr list --repo $ghSlug --head $Branch --state merged --json number,headRefOid --limit 20 2>&1
        $ghExit = $LASTEXITCODE
        # 2>&1 folds stderr in as ErrorRecords; keep them out of the JSON but keep them as the reason.
        $ghText = (@($raw | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n").Trim()
        if ($ghExit -ne 0) {
            $script:ghFailures++
            $why = (@($raw) -join ' ').Trim()
            if (-not $script:ghFirstError) { $script:ghFirstError = if ($why) { $why } else { "gh exited $ghExit" } }
            $notes += "the merged-PR probe FAILED for this branch (gh exited $ghExit), so only the local merge signals were available"
        }
        if ($ghExit -eq 0 -and $ghText) {
            $prs = $null
            try { $prs = @($ghText | ConvertFrom-Json) } catch { $prs = @() }
            $exact = @($prs | Where-Object { $_.headRefOid -eq $tip })
            if ($exact.Count -gt 0) {
                return @{ Merged = $true; Reason = "PR #$($exact[0].number) merged at this exact tip"; Unique = $uniq; Notes = $notes; NeverUsed = $false }
            }
            if ($prs.Count -gt 0) {
                $notes += "a merged PR (#$($prs[0].number)) exists for the branch NAME '$Branch', but its head was $($prs[0].headRefOid.Substring(0,8)) and this branch is at $($tip.Substring(0,8)) -- the branch moved on after that merge"
            }
        }
    }

    # 3) Upstream gone: the remote branch was deleted, the usual squash-merge + auto-delete shape. Only
    #    when the upstream is the branch's OWN remote branch -- `new.ps1 -Base origin/<parent>` leaves a
    #    child branch pointing at the PARENT's upstream, so a merged parent makes a never-pushed child
    #    report [gone] and its commits would go with the branch.
    #    `gone` means THE REMOTE REF IS ABSENT, never `merged`: a branch whose PR was CLOSED, or that was
    #    deleted with `push --delete`, reports exactly this. So it is a signal to remove the WORKTREE, and
    #    never a licence to delete the branch -- which is why the branch delete re-verifies containment
    #    in the trunk on its own and keeps the branch when it cannot.
    $refInfo = (& git -C $RepoRoot for-each-ref --format '%(upstream:short)|%(upstream:track)|%(upstream:remotename)' "refs/heads/$Branch" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $refInfo) {
        $parts = ([string]$refInfo).Split('|')
        $upShort = $parts[0]
        $upTrack = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $upRemote = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        if ($upTrack -match 'gone') {
            if ($upShort -eq "$upRemote/$Branch") {
                return @{
                    Merged = $true
                    Reason = "upstream $upShort is gone (squash-merged + remote-deleted); the branch is KEPT because $uniq commit(s) are not on $MainRef"
                    Unique = $uniq; Notes = $notes; NeverUsed = $false
                }
            }
            $notes += "upstream $upShort is gone, but it belongs to ANOTHER branch (this worktree was branched off it) -- not a merge signal"
        }
    }
    return @{ Merged = $false; Reason = 'no merge signal'; Unique = $uniq; Notes = $notes; NeverUsed = $false }
}

# --- Occupancy signal 2: recent activity, which does not depend on a recorded cwd ----------------
function Get-WorktreeActivity {
    param([string]$Path)
    # The worktree's PRIVATE git metadata only. Deliberately NOT the working files: a dependency
    # install or a test run churns those, so their mtimes would veto everything forever and the veto
    # would stop meaning anything. The cost is that a session which only edits files and runs no git
    # command is invisible to this signal too -- stated in the header rather than papered over.
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $gitdir = & git -C $Path rev-parse --absolute-git-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gitdir) { return $null }
    $gitdir = ([string]$gitdir).Trim()
    if (-not (Test-Path -LiteralPath $gitdir)) { return $null }
    $newest = $null
    foreach ($rel in @('index', 'HEAD', 'ORIG_HEAD', 'FETCH_HEAD', 'COMMIT_EDITMSG', 'MERGE_MSG', 'logs/HEAD')) {
        $f = Join-Path $gitdir $rel
        if (Test-Path -LiteralPath $f) {
            $t = (Get-Item -LiteralPath $f -Force).LastWriteTime
            if ($null -eq $newest -or $t -gt $newest) { $newest = $t }
        }
    }
    return $newest
}

# --- Candidate set -------------------------------------------------------------------------------
# Stage 1: a DELIBERATELY OVER-INCLUSIVE sweep -- every registered worktree whose path merely starts
# with `<primary>-`. This is not the candidate set; it is the set an operator's eye would consider,
# and collecting it is what lets stage 2 say out loud which of them were rejected and why. A tool that
# silently filters cannot be checked.
#
# Literal prefix, NOT -like: `-like` treats [ ] in a path as a character class, so a repo living under
# a bracketed directory silently matches nothing (and every "was not pruned" assertion would pass
# vacuously). Both sides are already folded by ConvertTo-CcxComparablePath, so the compare is Ordinal.
$prefixed = @($occ.Worktrees | Where-Object {
        (ConvertTo-CcxComparablePath $_.Path).StartsWith("$RepoRootNorm-", [StringComparison]::Ordinal)
    })

# Stage 2: everything the prefix caught but that must never be a candidate -- said out loud rather
# than leaving the operator to wonder whether it was considered at all.
$siblings = @()
$excluded = @()
foreach ($w in $prefixed) {
    # A worktree INSIDE another registered worktree is not a sibling of anything.
    # `<primary>-work/.claude/worktrees/x` passes the prefix test, and removing it destroys the
    # harness-managed checkout a live session was relocated into -- while the parent, protected by
    # Get-NestedWorktrees, watches.
    $containers = @(Get-ContainingWorktrees -Occupancy $occ -Path $w.Path)
    if ($containers.Count -gt 0) {
        $excluded += [pscustomobject]@{ Wt = $w; Why = "nested inside $(Split-Path $containers[-1].Path -Leaf)" }
    }
    # Belt and braces, and it survives the containing worktree being deregistered: this path shape is
    # harness-managed by construction, whoever currently owns it.
    elseif (Test-CcxHarnessWorktreePath $w.Path) {
        $excluded += [pscustomobject]@{ Wt = $w; Why = 'harness-managed (.claude/worktrees)' }
    }
    # "SIBLING" IS NOT A PREFIX MATCH. The structural test also requires the SAME PARENT DIRECTORY and
    # a leaf of exactly `<primary-leaf>-<something>`, so `<primary>-work/sub` and a scratch checkout
    # living somewhere else entirely are rejected here even when the two rules above did not fire.
    elseif (-not (Test-CcxSiblingWorktreePath -Path $w.Path -PrimaryRoot $RepoRoot)) {
        $excluded += [pscustomobject]@{ Wt = $w; Why = "not a sibling of the primary (different parent directory or leaf shape)" }
    }
    elseif ($w.Detached -or $w.Bare -or -not $w.Branch) {
        $excluded += [pscustomobject]@{ Wt = $w; Why = 'detached/bare' }
    }
    else { $siblings += $w }
}

$namedMisses = @()
if ($Name) {
    $wanted = @($Name | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $matchesName = {
        param($leaf)
        foreach ($n in $wanted) { if ($leaf -ieq $n -or $leaf -ieq "$RepoLeaf-$n") { return $true } }
        return $false
    }
    $siblings = @($siblings | Where-Object { & $matchesName (Split-Path $_.Path -Leaf) })
    foreach ($n in $wanted) {
        $hit = @($siblings | Where-Object { (Split-Path $_.Path -Leaf) -ieq $n -or (Split-Path $_.Path -Leaf) -ieq "$RepoLeaf-$n" })
        if ($hit.Count -eq 0) { $namedMisses += $n }
    }
}

# --- One decision pass; two renderers ------------------------------------------------------------
$idleCut = (Get-Date).AddHours(-1 * $IdleHours)

# ONE cleanliness routine, called by the decision pass AND by the re-check immediately before removal.
# The re-check used to collapse "the directory vanished", "git status exited 128", "an untracked file
# appeared" and "somebody edited a tracked file" into the single string "no longer clean" -- discarding
# the distinction at the exact moment an operator most needs it, because something changed underneath a
# destructive run.
# FAILS CLOSED: an unreadable status (a moved-away or half-deleted worktree exits 128 with no output)
# used to be indistinguishable from "no changes" and pointed straight at destruction.
function Test-WorktreeClean {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Clean = $false; Reasons = @('directory is missing (already half-removed? investigate before pruning)') }
    }
    $status = @(& git -C $Path --no-optional-locks status --porcelain 2>$null)
    $statusExit = $LASTEXITCODE
    if ($statusExit -ne 0) {
        return @{ Clean = $false; Reasons = @("git status failed (exit $statusExit) -- cannot establish it is clean") }
    }
    $trackedChanges = @($status | Where-Object { $_ -notmatch '^\?\?' })
    $untracked = @($status | Where-Object { $_ -match '^\?\?' })
    $r = @()
    if ($trackedChanges.Count -gt 0) { $r += "dirty: $($trackedChanges.Count) uncommitted tracked change(s)" }
    # Untracked files are the one loss class with no recovery THROUGH GIT: not in the index, not in a
    # stash, not in the reflog. (--force also deletes IGNORED files -- a dependency tree, a local
    # database, a generated fixture set -- which git status never shows here; those are unrecoverable
    # too, merely regenerable.) `--force` suppresses git's own refusal on them, so this must not wave
    # them through.
    if ($untracked.Count -gt 0) {
        $r += "$($untracked.Count) untracked file(s) present -- --force would delete them unrecoverably"
    }
    return @{ Clean = ($r.Count -eq 0); Reasons = $r }
}

# The reported shape of an occupant. Shared with the -Apply re-check, which must WRITE BACK the
# occupants it finds: a re-check veto used to leave `Occupants: []` on the one candidate the fence
# actually stopped, so the run that signal 1 saved reported signal 1 as having contributed nothing.
function ConvertTo-OccupantRows([object[]]$Rows) {
    return @($Rows | ForEach-Object {
            [pscustomobject]@{ Short = $_.Short; State = $_.State; Surface = $_.Entrypoint; Cwd = $_.Cwd; Worktree = $_.Worktree }
        })
}

function Get-Decision {
    param([object]$Wt, [bool]$Confirmed)
    $leaf = Split-Path $Wt.Path -Leaf
    $reasons = @()
    $notes = @()

    # EVERY LOCAL DISQUALIFIER IS EVALUATED BEFORE THE MERGE TEST. The merge test can cost a gh round
    # trip per candidate, and that time is the window in which a session can arrive; spending it on a
    # worktree that is already occupied both widens the window and answers a question nobody asked.

    # Lock: git's own occupancy flag, and the one thing a single --force will not override.
    if ($Wt.Locked) {
        $why = if ($Wt.LockReason) { ": $($Wt.LockReason)" } else { '' }
        $reasons += "locked by git$why"
    }

    # Occupancy 1: the liveness fence. Unavailable is a REFUSAL, never an empty answer. -IncludeNested
    # because removing a parent takes the nested checkout with it, so a session in the nested tree must
    # veto the ancestor as well.
    $occupants = @()
    if ($occ.Available) {
        $occupants = @(Get-WorktreeOccupants -Occupancy $occ -Path $Wt.Path -IncludeNested)
        if ($occupants.Count -gt 0) {
            $who = ($occupants | ForEach-Object {
                    $where = if ((ConvertTo-CcxComparablePath $_.WorktreePath) -eq (ConvertTo-CcxComparablePath $Wt.Path)) { '' } else { " in nested $($_.Worktree)" }
                    "$($_.Short) [$($_.State)]$where"
                }) -join ', '
            $reasons += "occupied by $($occupants.Count) session(s): $who"
        }
    }

    # A worktree that CONTAINS another registered worktree is never safe to --force-remove, occupied or
    # not: git deletes the parent tree, the nested checkout goes with it, and the nested worktree stays
    # registered with no directory -- the orphan state this whole script exists to avoid causing.
    $nested = @(Get-NestedWorktrees -Occupancy $occ -Path $Wt.Path)
    if ($nested.Count -gt 0) {
        $names = (($nested | ForEach-Object { Split-Path $_.Path -Leaf }) -join ', ')
        $reasons += "contains $($nested.Count) nested registered worktree(s) ($names) -- removing this would orphan them"
    }

    if (-not $occ.Available) {
        $reasons += "liveness fence unavailable -- $($occ.Detail)"
    }

    $c = Test-WorktreeClean -Path $Wt.Path
    $clean = [bool]$c.Clean
    $reasons += @($c.Reasons)

    # Occupancy 2: recent activity. The signal that does not need a recorded cwd, and the only one that
    # saw the sessions signal 1 missed.
    $activity = Get-WorktreeActivity -Path $Wt.Path
    $activityAge = $null
    if ($null -eq $activity) {
        $reasons += 'activity unknown (git metadata unreadable) -- cannot establish nobody is in it'
    }
    elseif (-not $activityVeto) {
        $activityAge = [math]::Round(((Get-Date) - $activity).TotalHours, 2)
        $notes += "activity veto OFF (-IdleHours 0); this worktree was touched $activityAge h ago"
    }
    else {
        $activityAge = [math]::Round(((Get-Date) - $activity).TotalHours, 2)
        if ($activity -gt $idleCut) {
            if ($Confirmed) {
                $notes += "recent activity ($activityAge h ago) overridden by -Name"
            }
            else {
                $reasons += "recently active ($activityAge h ago, < $IdleHours h) -- someone may be working here by absolute path; confirm with -Name $leaf"
            }
        }
    }

    # Merge signal LAST -- only worth the gh round trip when nothing local already disqualifies it.
    $merged = $null
    $mergeReason = 'not evaluated (already disqualified)'
    $unique = -1
    $neverUsed = $false
    if ($reasons.Count -eq 0) {
        $m = Test-Merged -Branch $Wt.Branch
        $merged = [bool]$m.Merged
        $mergeReason = [string]$m.Reason
        $unique = [int]$m.Unique
        $neverUsed = [bool]$m.NeverUsed
        $notes += @($m.Notes)
        if (-not $merged) { $reasons += "not merged ($mergeReason)" }
    }

    # ASSERT THE DECISION AND THE REASON, never just the decision. A row that says PRUNE without the
    # sentence that produced it cannot be reviewed, and a test that asserts only "it survived" passes
    # for a worktree that was skipped for entirely the wrong reason.
    return [pscustomobject]@{
        Leaf         = $leaf
        Path         = $Wt.Path
        Branch       = $Wt.Branch
        Decision     = if ($reasons.Count -eq 0) { 'PRUNE' } else { 'SKIP' }
        Reasons      = @($reasons)
        Reason       = if ($reasons.Count -eq 0) { $mergeReason } else { $reasons[0] }
        Notes        = @($notes)
        Clean        = $clean
        # $null, not $false, when the test never ran: a machine consumer reads `false` as "checked, and
        # it is not merged", which is a different claim from "never asked".
        Merged       = $merged
        MergeReason  = $mergeReason
        NeverUsed    = $neverUsed
        UniqueCommits = $unique
        Locked       = [bool]$Wt.Locked
        NestedWorktrees = @($nested | ForEach-Object { Split-Path $_.Path -Leaf })
        Occupants    = @(ConvertTo-OccupantRows $occupants)
        ActivityAgeHours = $activityAge
        Confirmed    = [bool]$Confirmed
        Outcome      = 'not attempted'
        OutcomeDetail = ''
        # NOT 'kept': every skipped candidate then claimed a decision nobody made, and the JSON said 7
        # branches were kept on a run whose summary said 0. 'kept' is now only ever set by a keep.
        BranchOutcome = 'not attempted'
        BranchDetail  = ''
        # Declared on EVERY candidate, not just removed ones, so the field's absence never has to be
        # interpreted: an empty array reads as "nothing was stranded here", which is true of a candidate
        # that was skipped, and a consumer never has to distinguish missing from empty.
        ClaimsReleased   = @()
        ClaimsUnreleased = @()
    }
}

$confirmedLeaves = @()
if ($Name) { $confirmedLeaves = @($siblings | ForEach-Object { Split-Path $_.Path -Leaf }) }

$decisions = @()
foreach ($s in $siblings) {
    $leaf = Split-Path $s.Path -Leaf
    $decisions += Get-Decision -Wt $s -Confirmed ($confirmedLeaves -contains $leaf)
}
$prunable = @($decisions | Where-Object { $_.Decision -eq 'PRUNE' })

# -Name is the loudest thing an operator can do to the fence: it is -IdleHours 0 scoped to one tree,
# and signal 1 has been measured vetoing none of the real siblings on a busy repo. It used to produce
# only a grey `note:` line, while the flag it is equivalent to got a red banner.
$confirmedActually = @($decisions | Where-Object { $_.Confirmed } | ForEach-Object { $_.Leaf })
if ($confirmedActually.Count -gt 0) {
    $reducedAssurance += "activity veto OVERRIDDEN by -Name for: $($confirmedActually -join ', ') -- signal 2 is off for those, and signal 1 has been measured vetoing none of the real siblings on a busy repo"
}

# The gh receipt, written from what the probes ANSWERED (see Test-Merged).
$ghDetail =
if ($SkipGh) { 'PR probe skipped (-SkipGh)' }
elseif (-not $ghSlug) { 'PR probe skipped: origin is not a GitHub remote' }
elseif (-not $hasGh) { 'PR probe skipped: gh is not installed' }
elseif ($ghAttempts -eq 0) { "PR probe available ($ghSlug) but no candidate reached the merge test" }
elseif ($ghFailures -eq 0) { "PR probe scoped to ${ghSlug}: $ghAttempts candidate(s) probed" }
else { "PR probe scoped to $ghSlug FAILED on $ghFailures of $ghAttempts candidate(s): $ghFirstError" }
if ($ghFailures -gt 0) {
    $reducedAssurance += "the merged-PR probe FAILED on $ghFailures of $ghAttempts candidate(s): the exact-tip merge signal was unavailable for them ($ghFirstError)"
}

# --- The fence receipt: count what was EXAMINED, not what was found ------------------------------
$liveInRepo = @($occ.Sessions | Where-Object { Test-OccupancyVeto $_.State }).Count
# What signal 1 actually CONTRIBUTED here, which is not the same as how many sessions it saw. On the
# repo this was developed in the honest number has repeatedly been zero while several of those
# worktrees were occupied in fact.
# Recomputed AFTER the apply loop, because a re-check veto is a signal-1 contribution too.
$fenceVetoedAtDecision = @($decisions | Where-Object { $_.Occupants.Count -gt 0 }).Count
$fenceVetoed = $fenceVetoedAtDecision
# PRINT YOUR BLIND SPOTS. On every run, in the receipt as well as on the terminal: a fence believed to
# be wider than it is, is worse than no fence, because it is trusted.
$blindSpots = @(
    'a session writing into a worktree by absolute path from elsewhere (29% of the writes by primary-seated sessions, measured on the repo this was developed in)',
    'a cwd recorded as a UNC or 8.3 short path',
    'a session that never registered',
    'a session that only edits files and runs no git command (invisible to signal 2 as well)'
)

if (-not $Json) {
    Write-Host ""
    if ($occ.Available) {
        Write-Host ("Occupancy fence: {0} config root(s), {1} record(s) examined, {2} live session(s) in this repo family." -f
            $occ.RootsExamined, $occ.RecordsExamined, $liveInRepo) -ForegroundColor DarkCyan
        Write-Host ("  Sessions it placed INSIDE a candidate: {0} of {1} candidate(s) vetoed by signal 1 (at decision time)." -f
            $fenceVetoedAtDecision, $decisions.Count) -ForegroundColor DarkCyan
    }
    else {
        Write-Host "Occupancy fence UNAVAILABLE -- $($occ.Detail)." -ForegroundColor Red
        Write-Host "  That is NOT 'nobody is live'. Nothing will be pruned." -ForegroundColor Red
    }
    Write-Host "  It DOES see editor-hosted sessions (the match is path-based, not surface-based). It CANNOT see:" -ForegroundColor DarkGray
    foreach ($b in $blindSpots) { Write-Host "    - $b" -ForegroundColor DarkGray }
    if ($activityVeto) {
        Write-Host ("  Which is why git metadata touched within {0}h also counts as occupied." -f $IdleHours) -ForegroundColor DarkGray
    }
    foreach ($r in $reducedAssurance) { Write-Host "  REDUCED ASSURANCE: $r" -ForegroundColor Red }
    Write-Host "  refs: $fetchDetail" -ForegroundColor DarkGray
    Write-Host "  merge: $ghDetail" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host ("{0,-42} {1,-30} {2}" -f 'WORKTREE', 'BRANCH', 'DECISION')
    Write-Host ("{0,-42} {1,-30} {2}" -f ('-' * 40), ('-' * 28), ('-' * 40))
    foreach ($d in $decisions) {
        $text = if ($d.Decision -eq 'PRUNE') { "PRUNE - $($d.Reason)" } else { "SKIP  - $($d.Reason)" }
        $colour = if ($d.Decision -eq 'PRUNE') { 'Yellow' } else { 'Gray' }
        Write-Host ("{0,-42} {1,-30} {2}" -f $d.Leaf, $d.Branch, $text) -ForegroundColor $colour
        foreach ($r in @($d.Reasons | Select-Object -Skip 1)) { Write-Host ("{0,-42} {1,-30} also: {2}" -f '', '', $r) -ForegroundColor DarkGray }
        foreach ($n in $d.Notes) { Write-Host ("{0,-42} {1,-30} note: {2}" -f '', '', $n) -ForegroundColor DarkGray }
    }
    if ($decisions.Count -eq 0) {
        Write-Host "  (no candidates)" -ForegroundColor DarkGray
    }
    foreach ($e in $excluded) {
        Write-Host ("{0,-42} {1,-30} not a candidate ({2})" -f (Split-Path $e.Wt.Path -Leaf), $e.Wt.Branch, $e.Why) -ForegroundColor DarkGray
    }
    foreach ($n in $namedMisses) {
        Write-Host "  -Name '$n' matched no PRUNABLE sibling worktree (it may be nested, detached, or not exist)." -ForegroundColor Yellow
    }
}

# --- Orphans this script left behind on an EARLIER run -------------------------------------------
# ORPHANS OUTLIVE THE RUN THAT MADE THEM. Once git deregisters a worktree it leaves `git worktree
# list` and therefore the candidate set, so the next run printed a green all-clear over a directory
# this script had broken and the recovery recipe survived only in the first run's scrollback. Two
# independent detectors, because either can be true alone: a ledger written at the moment of the
# failure, and a directory still carrying a .git FILE that points into this repo's worktree admin area
# while git no longer lists it.
function Read-OrphanLedger {
    if (-not $ledgerPath -or -not (Test-Path -LiteralPath $ledgerPath)) { return @() }
    try { return @(Get-Content -LiteralPath $ledgerPath -Raw -EA Stop | ConvertFrom-Json -EA Stop) }
    catch { return @() }
}

# --- Coordination claims stranded by a removal ---------------------------------------------------
# A work claim (scripts/coord/claim.ps1) is a JSON file under <state-root>/claims/. It lives beside
# the SHARED object store, so it OUTLIVES the worktree that took it. Removing a worktree therefore
# strands its claims, and `claim.ps1 -Take` hard-blocks on any claim file that exists -- so the key
# becomes unclaimable by every future session until a human happens to run `-Release <key> -Force`.
# Nothing surfaced that condition and nothing could: the registry has no way to observe that a holder
# ceased to exist, which is the same "a control that cannot see its own failure" shape this whole
# script is a response to.
#
# WHY THIS IS NOT AN EXPIRING CLAIM. claim.ps1's docs are right that an auto-expiring claim silently
# re-opens the race it exists to prevent, and that reasoning is untouched here. This releases on
# EVIDENCE, not on elapsed time: it runs only from the branch that has already proven the directory is
# gone AND deregistered, so there is no session left in there to collide with. A claim whose holder is
# merely quiet is never touched by this.

# An UNREADABLE claim belongs to the REGISTRY, not to any one worktree -- by definition we could not
# read whose it is. So it is surveyed ONCE, here, rather than discovered inside the removal loop. Two
# bugs came out of doing it the other way, and both are the same mistake in different clothes:
#   * counted once per removed worktree, so one blocked key reported as 2 -- the over-counting the
#     branch counters in this script were already fixed for once;
#   * invisible to a dry run, because a dry run never reaches the removal branch. A preview that
#     reports a tidy registry over an unclaimable key is the same silence this whole feature removes,
#     and it is the surface an operator checks BEFORE deciding to act.
# Reading is not mutating, so this is safe on the dry-run path -- the same rule the orphan ledger follows.
$claimsUnreadable = @{}
# NEVER LOOKED is not CLEAN. $claimsDir is allowed to be empty (the state root need not resolve), and
# the claims directory need not exist at all -- in both cases the survey below does not run, and
# `unreadable: []` next to `released: 0` reads exactly like a registry that was checked and found
# tidy. Recorded so a consumer can tell the two apart, per occupancy.ps1's rule that an empty list is
# not a green light.
$claimsScanned = [bool]($claimsDir -and (Test-Path -LiteralPath $claimsDir))
if ($claimsScanned) {
    foreach ($f in @(Get-ChildItem -LiteralPath $claimsDir -Filter *.json -File -EA SilentlyContinue | Sort-Object Name)) {
        try { Get-Content -LiteralPath $f.FullName -Raw -EA Stop | ConvertFrom-Json -EA Stop | Out-Null }
        catch {
            $claimsUnreadable[(ConvertTo-CcxComparablePath $f.FullName)] = [pscustomobject]@{
                file = $f.Name; detail = $_.Exception.Message
            }
        }
    }
}

function Remove-ClaimsHeldBy {
    param([string]$Path)

    if (-not $claimsDir -or -not (Test-Path -LiteralPath $claimsDir)) { return @() }

    # THE FALSE POSITIVE IS WORSE THAN THE BUG. Releasing a claim held by a DIFFERENT, living worktree
    # hands its key to another session and invites the duplicate build the registry exists to stop --
    # strictly worse than the orphan being fixed. So match on the full folded path and nothing else:
    # no leaf name, no prefix, no StartsWith.
    #
    # ONE NORMALISER ON BOTH SIDES OR THE MATCH SILENTLY MISSES. claim.ps1's writer records
    # `worktree = <absolute path from git rev-parse --path-format=absolute>` and must fold it with the
    # same ConvertTo-CcxComparablePath used here; a claim that does not match is not an error, it is a
    # claim quietly left stranded, which is exactly the condition this code exists to clear.
    $target = ConvertTo-CcxComparablePath $Path
    if (-not $target) { return @() }

    $released = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $claimsDir -Filter *.json -File -EA SilentlyContinue | Sort-Object Name)) {
        try {
            $c = Get-Content -LiteralPath $f.FullName -Raw -EA Stop | ConvertFrom-Json -EA Stop
        }
        catch {
            # UNREADABLE IS NOT ABSENT. A claim file we cannot parse might name this worktree, so we
            # cannot say it does not -- and we must not delete it on a guess either. Already surveyed and
            # reported by the run-level pass above; skipping it here must never become a silent drop.
            continue
        }
        if ((ConvertTo-CcxComparablePath ([string]$c.worktree)) -ne $target) { continue }
        try {
            Remove-Item -LiteralPath $f.FullName -Force -EA Stop
            $released += [pscustomobject]@{ key = [string]$c.key; outcome = 'released'; detail = [string]$c.note }
        }
        catch {
            # Same rule as the removal itself: report the outcome, never assume the call worked.
            $released += [pscustomobject]@{ key = [string]$c.key; outcome = 'failed'; detail = $_.Exception.Message }
        }
    }
    return $released
}

# Still broken RIGHT NOW: on disk, and not registered. An entry that was repaired (re-added) or fully
# deleted clears itself, so the ledger cannot nag about a state that no longer exists.
function Get-LiveOrphans([object[]]$Ledger) {
    $registered = @{}
    foreach ($w in @(Get-RepoWorktrees $RepoRoot)) { $registered[(ConvertTo-CcxComparablePath $w.Path)] = $true }
    $seen = @{}
    $out = @()
    foreach ($e in $Ledger) {
        $p = [string]$e.path
        if (-not $p) { continue }
        $n = ConvertTo-CcxComparablePath $p
        if ($registered.ContainsKey($n) -or -not (Test-Path -LiteralPath $p)) { continue }
        if ($seen.ContainsKey($n)) { continue }
        $seen[$n] = $true
        $out += [pscustomobject]@{ Path = $p; Leaf = (Split-Path $p -Leaf); Branch = [string]$e.branch; At = [string]$e.at; Why = 'a previous run of this script failed to finish removing it' }
    }
    # The ledger-free detector: an unregistered sibling directory whose .git pointer still names this
    # repo. Deliberately NOT "any unregistered <primary>-* directory" -- an unrelated folder sharing the
    # prefix is not an orphan, and a destructive tool that cries wolf gets ignored.
    $parent = Split-Path $RepoRoot -Parent
    foreach ($dir in @(Get-ChildItem -LiteralPath $parent -Directory -Force -EA SilentlyContinue |
            Where-Object { $_.Name.StartsWith("$RepoLeaf-", [StringComparison]::OrdinalIgnoreCase) })) {
        $n = ConvertTo-CcxComparablePath $dir.FullName
        if ($registered.ContainsKey($n) -or $seen.ContainsKey($n)) { continue }
        $dotgit = Join-Path $dir.FullName '.git'
        if (-not (Test-Path -LiteralPath $dotgit -PathType Leaf)) { continue }
        $txt = ''
        try { $txt = Get-Content -LiteralPath $dotgit -Raw -EA Stop } catch { continue }
        if ($txt -notmatch 'gitdir:\s*(.+)') { continue }
        # -Base is the directory the .git FILE lives in. git normally writes an absolute gitdir here,
        # but it is allowed to be relative, and resolving a relative one against THIS process's cwd
        # would silently answer "does not point into our git dir" -- i.e. an orphan reported as fine.
        $target = ConvertTo-CcxComparablePath -Path ($Matches[1].Trim()) -Base $dir.FullName
        if (-not $gitCommonDir -or -not (Test-CcxPathUnder -Path $target -Root (ConvertTo-CcxComparablePath $gitCommonDir))) { continue }
        $seen[$n] = $true
        $out += [pscustomobject]@{ Path = $dir.FullName; Leaf = $dir.Name; Branch = ''; At = ''; Why = 'it still points into this repo''s worktree admin directory, but git no longer lists it' }
    }
    return $out
}

$ledger = @(Read-OrphanLedger)
# Scanned BEFORE the apply loop, so this run's own orphans are reported as this run's, not as history.
$priorOrphans = @(Get-LiveOrphans $ledger)

# --- Apply ---------------------------------------------------------------------------------------
$removed = 0; $failed = 0; $branchesDeleted = 0; $branchesKept = 0; $orphaned = 0
$claimsReleased = 0; $claimsUnreleased = 0
$newOrphans = @()
if (-not $occ.Available) { Set-Exit $EXIT_REFUSED }
if ($priorOrphans.Count -gt 0) { Set-Exit $EXIT_ORPHANED }

# Delete the branch only when the delete is provably lossless AT THIS MOMENT. `-d` refuses a branch
# merged only into the remote trunk whenever the local trunk lags (it usually does), so `-D` was the
# routine path and git's own last protection was being overridden every time -- including on a verdict
# formed before a session pushed two more commits onto the branch. Re-verify containment here, after
# the removal, or keep the branch: a stale ref costs nothing.
function Remove-BranchSafely {
    param([object]$Decision)
    & git -C $RepoRoot branch -d $Decision.Branch 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return @{ Outcome = 'deleted'; Detail = '' } }

    $c = Test-ContainedInMain -Branch $Decision.Branch
    if (-not $c.Ok) {
        return @{ Outcome = 'kept'; Detail = "could not re-verify containment in $MainRef, so the branch was kept" }
    }
    if ($c.Unique -ne 0) {
        return @{
            Outcome = 'kept'
            Detail = "$($c.Unique) commit(s) are not on $MainRef, so the branch was KEPT (delete it yourself once you are sure: git branch -D $($Decision.Branch))"
        }
    }
    $out = @(& git -C $RepoRoot branch -D $Decision.Branch 2>&1)
    if ($LASTEXITCODE -eq 0) {
        return @{ Outcome = 'force-deleted'; Detail = "re-verified: 0 commits beyond $MainRef, so nothing was lost" }
    }
    return @{ Outcome = 'kept'; Detail = ($out -join ' ').Trim() }
}

# The apply-phase fence read the RECEIPT has to answer for. There is one read per candidate now (see
# the loop), so this holds the read that came back unavailable if one did, and the last read
# otherwise -- the sticky assignment below is what makes that true.
$occ2 = $null
# STICKY, AND NEVER CLEARED. A fence that died mid-run stops the rest, which is a promise made in this
# script's own header and in docs/PRUNING.md, and it was kept only by accident while there was one
# snapshot per run: the single unavailable verdict was loop-invariant, so every candidate skipped. One
# read per candidate makes it a real decision, and a fence that recovers by candidate 4 has told us
# nothing about candidate 2 -- so the run stops rather than resuming destruction after a gap.
$fenceDied = $false
# Counted, and reported, because "the fence ran" has never been allowed to imply "the fence covered
# it" here. On a run whose fence stayed up this equals counts.prunable -- one read per candidate. It
# is LOWER only when the fence died and stopped the rest; a run reporting 1 read for 4 candidates that
# were all judged is this script having regressed to a single pre-loop snapshot.
$fenceReads = 0
if ($Apply -and $prunable.Count -gt 0) {
    Write-Note ""
    foreach ($d in $prunable) {
        if (-not $Json) { Write-Host "Removing $($d.Leaf) [$($d.Branch)]..." -ForegroundColor Cyan }

        # The fence is already known dead. Skip without re-asking it: the answer cannot authorise
        # anything, and every candidate still needs an Outcome for the counts to cover the table.
        if ($fenceDied) {
            $d.Outcome = 'skipped'
            $d.OutcomeDetail = "re-check: the fence died earlier in this run, which stops the rest ($($occ2.Detail))"
            Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
            continue
        }

        # RE-READ OCCUPANCY, ONCE PER CANDIDATE, INSIDE THE LOOP. The decision pass above costs a gh
        # round trip per candidate -- roughly half a second each, measured on the repo this was
        # developed in -- and a session can arrive inside that window.
        #
        # THIS CALL USED TO SIT ABOVE THE LOOP, and the trade was recorded as not made. One snapshot
        # taken before the first removal judged every candidate in the batch, so from the second
        # removal onwards it was stale by exactly the interval it exists to close: a session arriving
        # in worktree B while worktree A was being removed was not seen, and a nested worktree that
        # appeared mid-batch was invisible to a frozen Worktrees array. The cost of closing it is one
        # fence read per candidate, measured at ~64 ms on this machine (5 config roots, 10 records, 5
        # worktrees) against the ~500 ms gh probe already spent on each of those candidates, and
        # against the `git worktree list` this same loop already spawns per candidate below. Signal 2
        # was already re-read per candidate; signal 1 now matches it.
        #
        # IT BOUNDS THE STALENESS, IT DOES NOT REMOVE IT. The cleanliness check and the removal itself
        # still sit between this read and the git command, so the window is one candidate's worth of
        # work instead of the whole batch's. Nothing here is atomic and nothing here takes a lock.
        $occNow = Get-WorktreeOccupancy -Repo $RepoRoot -ConfigRoot $ConfigRoot -StartSkewMinutes $StartSkewMinutes
        $fenceReads++
        # STICKY, AND FAIL-CLOSED, because the receipt speaks for the whole apply phase and there is
        # more than one read in it now. One unavailable read has to survive every later available one:
        # a fence that died on candidate 2 and recovered by candidate 5 would otherwise report
        # `availableAtApply: true` next to the skip it caused and the exit that skip set.
        if ($null -eq $occ2 -or $occ2.Available) { $occ2 = $occNow }

        # Re-check the things that can change under us in seconds. Against $occNow, this candidate's
        # own read -- $occ2 is the receipt's variable and may be an earlier, worse one.
        if (-not $occNow.Available) {
            $fenceDied = $true
            $d.Outcome = 'skipped'
            $d.OutcomeDetail = "re-check: fence became unavailable ($($occNow.Detail))"
            # EXIT 2 MEANS "nothing was attempted", and with the read inside the loop the fence can now
            # die AFTER a removal has already succeeded -- which is a partial run, not a refusal. Same
            # rule the -Name miss below uses, and the same rule docs/PRUNING.md states for it.
            Set-Exit $(if ($removed -gt 0) { $EXIT_FAILED } else { $EXIT_REFUSED })
            Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
            continue
        }
        $now = @(Get-WorktreeOccupants -Occupancy $occNow -Path $d.Path -IncludeNested)
        if ($now.Count -gt 0) {
            $d.Outcome = 'skipped'
            $d.OutcomeDetail = "re-check: a session arrived ($(($now | ForEach-Object { $_.Short }) -join ', '))"
            # WRITE IT BACK. Without this the candidate the fence just saved still reports `Occupants:
            # []`, and the receipt's "vetoed by signal 1" figure -- the number that exists precisely so
            # "the fence ran" cannot imply "the fence covered it" -- under-reports the save to zero.
            $d.Occupants = @(ConvertTo-OccupantRows $now)
            Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
            continue
        }
        $nestedNow = @(Get-NestedWorktrees -Occupancy $occNow -Path $d.Path)
        if ($nestedNow.Count -gt 0) {
            $d.Outcome = 'skipped'
            $d.OutcomeDetail = "re-check: a nested worktree appeared ($((($nestedNow | ForEach-Object { Split-Path $_.Path -Leaf }) -join ', ')))"
            Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
            continue
        }
        # Signal 2, re-read. It was the ONE signal missing from this block, and it is the only one with
        # measured coverage of the class of worktree this tool prunes (signal 1 has been measured
        # vetoing none of the real siblings). The window is a gh round trip per candidate plus every
        # removal before this one, which is exactly the interval the re-check exists to close.
        if ($activityVeto -and -not $d.Confirmed) {
            $a2 = Get-WorktreeActivity -Path $d.Path
            $cut2 = (Get-Date).AddHours(-1 * $IdleHours)
            if ($null -eq $a2) {
                $d.Outcome = 'skipped'
                $d.OutcomeDetail = 're-check: activity became unreadable -- cannot establish nobody is in it'
                Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
                continue
            }
            if ($a2 -gt $cut2) {
                $d.Outcome = 'skipped'
                $d.OutcomeDetail = "re-check: git metadata was touched $([math]::Round(((Get-Date) - $a2).TotalHours, 2)) h ago, inside the $IdleHours h window"
                Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
                continue
            }
        }
        # Same routine the decision pass used, so the reason survives: this used to flatten a vanished
        # directory, an exit-128 status, an untracked file and a real edit into "no longer clean".
        $c2 = Test-WorktreeClean -Path $d.Path
        if (-not $c2.Clean) {
            $d.Outcome = 'skipped'
            $d.OutcomeDetail = "re-check: $($c2.Reasons -join '; ')"
            Write-Note "  SKIPPED: $($d.OutcomeDetail)" 'Yellow'
            continue
        }

        # --force suppresses git's refusal on untracked/modified files -- the exact refusal that would
        # have prevented the incident -- so it is only ever reached after this script has established
        # the tree is clean itself. (It is NOT needed for ignored build output: git's own check ignores
        # ignored files, contrary to the comment that used to live here. It also does not override a
        # lock; that needs -f -f, which this script never passes.)
        $out = @(& git -C $RepoRoot worktree remove --force $d.Path 2>&1)
        $removeExit = $LASTEXITCODE
        $err = ($out -join ' ').Trim()
        $dirExists = Test-Path -LiteralPath $d.Path
        $ptrExists = $dirExists -and (Test-Path -LiteralPath (Join-Path $d.Path '.git'))
        $stillRegistered = @(Get-RepoWorktrees $RepoRoot | Where-Object { (ConvertTo-CcxComparablePath $_.Path) -eq (ConvertTo-CcxComparablePath $d.Path) }).Count -gt 0

        # OUTCOME, NOT EXIT CODE. Exit 0 is git's claim; the directory being gone and deregistered is
        # the fact. Only the fact is counted as removed.
        if ($removeExit -eq 0 -and -not $dirExists -and -not $stillRegistered) {
            $removed++
            $d.Outcome = 'removed'
            # Only here. This is the branch that has PROVEN the directory is gone and deregistered, so it
            # is the only place where "no session can still be working in there" is a fact rather than an
            # assumption -- and, because the whole apply loop is gated on -Apply, a dry run cannot reach
            # it. Claims are released before the branch is touched so a Remove-BranchSafely failure
            # cannot leave the claim stranded behind a removal that did happen.
            $cl = @(Remove-ClaimsHeldBy -Path $d.Path)
            $d.ClaimsReleased = @($cl | Where-Object { $_.outcome -eq 'released' } | ForEach-Object { $_.key })
            # Only claims PROVEN to belong to this worktree and still not cleared. An unreadable file is
            # not here -- we never learned whose it was, so attributing it to this decision would be a
            # guess dressed as a fact. It is a run-level condition instead.
            $d.ClaimsUnreleased = @($cl | Where-Object { $_.outcome -eq 'failed' })
            $claimsReleased += $d.ClaimsReleased.Count
            $claimsUnreleased += $d.ClaimsUnreleased.Count
            foreach ($x in $cl) {
                if ($x.outcome -eq 'released') { Write-Note "  released claim '$($x.key)' (held by this worktree)" 'DarkCyan' }
                else {
                    # A claim we could not clear is still an orphan -- the exact condition this exists to
                    # remove -- so it must be loud, and it must move the exit code. Silence here would
                    # report a tidy prune over a key that is now permanently blocked.
                    Set-Exit $EXIT_FAILED
                    Write-Note "  CLAIM NOT RELEASED '$($x.key)': $($x.detail)" 'Red'
                    Write-Note "    It is now orphaned. Clear it with: pwsh -NoProfile -File scripts/coord/claim.ps1 -Release '$($x.key)' -Force" 'Red'
                }
            }
            $b = Remove-BranchSafely -Decision $d
            $d.BranchOutcome = $b.Outcome
            $d.BranchDetail = $b.Detail
            if ($b.Outcome -eq 'kept') {
                $branchesKept++
                Write-Note "  removed; branch '$($d.Branch)' KEPT: $($b.Detail)" 'Yellow'
            }
            else {
                $branchesDeleted++
                Write-Note "  removed; branch $($b.Outcome).$(if ($b.Detail) { " $($b.Detail)" })" 'Green'
            }
        }
        elseif ($removeExit -eq 0) {
            # git said it worked and it did not. Do NOT touch the branch on an unverified removal.
            $failed++
            Set-Exit $EXIT_FAILED
            $d.Outcome = 'failed'
            # A DELIBERATE keep, so it is counted as one. The failure paths used to leave the branch
            # alone and say so in prose while the summary reported "0 kept".
            $d.BranchOutcome = 'kept'
            $d.BranchDetail = 'the removal could not be verified, so the branch was left alone'
            $branchesKept++
            $d.OutcomeDetail = "git reported success but the directory $(if ($dirExists) { 'still exists' } else { 'is gone' }) and it is $(if ($stillRegistered) { 'STILL REGISTERED' } else { 'deregistered' }); branch '$($d.Branch)' was left alone"
            Write-Note "  FAILED: $($d.OutcomeDetail)" 'Red'
        }
        else {
            # A NON-ZERO EXIT DOES NOT MEAN NOTHING HAPPENED. git deletes the .git pointer and
            # deregisters the worktree before it walks the tree, and it deregisters even when that walk
            # fails ("no going back from here"). Diagnose what actually survived.
            $failed++
            Set-Exit $EXIT_FAILED
            $d.BranchOutcome = 'kept'
            $d.BranchDetail = 'the removal failed, so the branch was left alone'
            $branchesKept++
            $fileCount = 0
            if ($dirExists) {
                $probe = @(Get-ChildItem -LiteralPath $d.Path -Recurse -File -Force -EA SilentlyContinue | Select-Object -First 501)
                $fileCount = $probe.Count
            }
            $fileText = if ($fileCount -gt 500) { '500+' } else { "$fileCount" }

            if (-not $dirExists) {
                $d.Outcome = 'failed'
                $d.OutcomeDetail = "git exited $removeExit ($err) but the directory is gone; branch '$($d.Branch)' was left alone"
                Write-Note "  FAILED (exit $removeExit): $err" 'Red'
                Write-Note "  The directory is gone but git reported an error, so the branch was NOT deleted." 'Yellow'
            }
            elseif (-not $ptrExists -or -not $stillRegistered) {
                $orphaned++
                Set-Exit $EXIT_ORPHANED
                $d.Outcome = 'orphaned'
                # Remembered on disk: git has deregistered it, so it will not be in the candidate set of
                # any future run and nothing else would ever mention it again.
                $newOrphans += [pscustomobject]@{ path = $d.Path; branch = $d.Branch; at = (Get-Date).ToString('o'); detail = $err }
                $ptrText = if ($ptrExists) { 'intact' } else { 'DELETED' }
                $d.OutcomeDetail = "ORPHANED: .git pointer $ptrText, $fileText file(s) left, registered=$stillRegistered ($err)"
                Write-Note "  FAILED (exit $removeExit): $err" 'Red'
                Write-Note "  ORPHANED -- this is the state that nearly cost a session its work:" 'Red'
                Write-Note "    directory:      still on disk ($fileText file(s) remain)" 'Red'
                Write-Note "    .git pointer:   $(if ($ptrExists) { 'intact' } else { 'DELETED -- git no longer recognises this directory' })" 'Red'
                Write-Note "    registration:   $(if ($stillRegistered) { 'still listed by git worktree list' } else { 'DEREGISTERED' })" 'Red'
                Write-Note "    Any session working there will now see 'fatal: not a git repository'." 'Red'
                if ($ptrExists) {
                    Write-Note "    Try 'git -C ""$RepoRoot"" worktree repair ""$($d.Path)""' FIRST -- the .git file survived, so" 'Red'
                    Write-Note "    the registration may be re-creatable in place. If that fails, use the move-aside recipe:" 'Red'
                }
                else {
                    Write-Note "    'git worktree repair' cannot fix it (the .git file it needs is gone) and" 'Red'
                    Write-Note "    'git worktree add --force' refuses (the directory already exists). Recover it:" 'Red'
                }
                Write-Note "      1. close anything holding files open in it (an editor, a shell sitting in it)" 'Red'
                Write-Note "      2. Move-Item '$($d.Path)' '$($d.Path).salvage'" 'Red'
                Write-Note "      3. git -C '$RepoRoot' worktree add '$($d.Path)' '$($d.Branch)'" 'Red'
                Write-Note "      4. copy anything you need out of '$($d.Path).salvage' (stashes are safe -- they live in the shared .git)" 'Red'
                Write-Note "    The branch was NOT deleted, and 'git worktree prune' was NOT run." 'Red'
            }
            else {
                $d.Outcome = 'failed'
                $d.OutcomeDetail = "nothing destroyed: directory, .git pointer and registration intact ($err)"
                Write-Note "  FAILED (exit $removeExit): $err" 'Red'
                Write-Note "  Nothing was destroyed: the directory, its .git pointer and its registration are intact." 'Yellow'
            }
        }
    }
}
elseif ($Apply) {
    Write-Note "" ; Write-Note "Nothing to prune." 'Green'
}

$skipped = @($decisions | Where-Object { $_.Decision -eq 'SKIP' -or $_.Outcome -eq 'skipped' }).Count
# Now that the apply loop has run, count what signal 1 ACTUALLY stopped -- including the re-check saves.
$fenceVetoed = @($decisions | Where-Object { $_.Occupants.Count -gt 0 }).Count
if (-not $Json -and $fenceVetoed -gt $fenceVetoedAtDecision) {
    Write-Host ("  Signal 1 vetoed {0} further candidate(s) during the removal pass (total {1} of {2})." -f
        ($fenceVetoed - $fenceVetoedAtDecision), $fenceVetoed, $decisions.Count) -ForegroundColor DarkCyan
}
# Say how many times it was consulted, not just what it found. Equal numbers ARE the guarantee: every
# candidate was judged against a read taken after the removal before it. They differ only when the
# fence died and stopped the rest, so that case says so rather than leaving a bare short count for the
# operator to misread as a run that quietly reverted to one snapshot.
if (-not $Json -and $Apply -and $fenceReads -gt 0) {
    if ($fenceReads -eq $prunable.Count) {
        Write-Host ("  Occupancy re-read {0} time(s) for {0} candidate(s) -- one each, immediately before its removal." -f
            $fenceReads) -ForegroundColor DarkCyan
    }
    else {
        Write-Host ("  Occupancy re-read {0} time(s) for {1} candidate(s): the fence died and the rest were stopped untouched." -f
            $fenceReads, $prunable.Count) -ForegroundColor DarkCyan
    }
}

# -Name asked for something that does not exist, so the operator's instruction was NOT carried out. It
# used to print one yellow line and exit 0 with a green summary -- the same "green no-op" shape as the
# wrong-cwd case this script now refuses outright.
if ($namedMisses.Count -gt 0) { Set-Exit $(if ($removed -gt 0) { $EXIT_FAILED } else { $EXIT_REFUSED }) }

# BEFORE the report, not after it. The -Json branch below emits the receipt and EXITS, so an exit-code
# decision made after it would be reached only on the human path -- the receipt would carry exitCode 0
# over a key nothing can claim, and a CI consumer reading the JSON would see a clean run.
if ($claimsUnreadable.Count -gt 0) { Set-Exit $EXIT_FAILED }

# Persist the orphan ledger: what is still broken, plus anything this run broke. Written only under
# -Apply -- a dry run reports the same state without touching anything.
$ledgerOut = @()
foreach ($o in $priorOrphans) { $ledgerOut += [pscustomobject]@{ path = $o.Path; branch = $o.Branch; at = $o.At; detail = $o.Why } }
$ledgerOut += $newOrphans
$ledgerNote = ''
if ($Apply -and $ledgerPath) {
    try {
        if ($ledgerOut.Count -gt 0) { ($ledgerOut | ConvertTo-Json -Depth 4 -AsArray) | Set-Content -LiteralPath $ledgerPath -Encoding utf8 }
        elseif (Test-Path -LiteralPath $ledgerPath) { Remove-Item -LiteralPath $ledgerPath -Force }
    }
    catch { $ledgerNote = "could not write the orphan ledger at ${ledgerPath}: $($_.Exception.Message)" }
}

# --- Report --------------------------------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{
        repoRoot = $RepoRoot
        apply    = [bool]$Apply
        trunk    = $MainRef
        fence    = [pscustomobject]@{
            # FAIL-CLOSED HEADLINE: false if the fence was unavailable at ANY read. It used to report
            # the decision-pass verdict only, so a fence that died mid-run produced `available: true`
            # next to `exitCode: 2` with no field to reconcile them. $occ2 is sticky-unavailable across
            # the apply phase's per-candidate reads, so one bad read cannot be papered over by a later
            # good one here either.
            available          = ([bool]$occ.Available -and ($null -eq $occ2 -or [bool]$occ2.Available))
            availableAtDecision = [bool]$occ.Available
            availableAtApply   = if ($null -eq $occ2) { $null } else { [bool]$occ2.Available }
            detail             = $occ.Detail
            detailAtApply      = if ($null -eq $occ2) { '' } else { [string]$occ2.Detail }
            # HOW MANY TIMES THE FENCE WAS ACTUALLY CONSULTED during the apply phase. One read per
            # candidate, taken immediately before that candidate's checks, so on a healthy run this
            # equals counts.prunable. It is lower ONLY when the fence died and stopped the rest (then
            # availableAtApply is false and it says where it stopped). It is 0 on a dry run. A run that
            # judged every candidate on a single read would report 1 here, which is the whole point of
            # publishing it: "the fence ran" must never imply "the fence covered it".
            readsAtApply       = $fenceReads
            rootsExamined      = $occ.RootsExamined
            recordsExamined    = $occ.RecordsExamined
            recordsUnplaceable = $occ.RecordsUnplaceable
            unplaceableFiles   = @($occ.UnplaceableFiles)
            liveInRepo         = $liveInRepo
            vetoedCandidates   = $fenceVetoed
            vetoedCandidatesAtDecision = $fenceVetoedAtDecision
            blindSpots         = $blindSpots
            idleHours          = $IdleHours
            idleFloorHours     = $IDLE_FLOOR_HOURS
            activityVeto       = $activityVeto
            reducedAssurance   = @($reducedAssurance)
        }
        refs     = $fetchDetail
        fetched  = $fetched
        gh       = $ghDetail
        ghProbes = [pscustomobject]@{ attempted = $ghAttempts; failed = $ghFailures; firstError = $ghFirstError }
        candidates = @($decisions)
        excluded = @($excluded | ForEach-Object { [pscustomobject]@{ leaf = (Split-Path $_.Wt.Path -Leaf); reason = $_.Why } })
        namedMisses = @($namedMisses)
        orphansFromEarlierRuns = @($priorOrphans | ForEach-Object { [pscustomobject]@{ leaf = $_.Leaf; path = $_.Path; branch = $_.Branch; why = $_.Why } })
        ledger   = [pscustomobject]@{ path = $ledgerPath; persisted = ($Apply -and -not $ledgerNote); note = $ledgerNote }
        counts   = [pscustomobject]@{
            candidates      = $decisions.Count
            prunable        = $prunable.Count
            removed         = $removed
            # `orphaned` is a SUBSET of `failed`, not a sibling of it: removed+failed+skipped covers
            # every candidate exactly once. failedNonOrphan is spelled out so a consumer cannot reach
            # the wrong total by adding all four.
            failed          = $failed
            failedNonOrphan = ($failed - $orphaned)
            orphaned        = $orphaned
            orphansFromEarlierRuns = $priorOrphans.Count
            skipped         = $skipped
            branchesDeleted = $branchesDeleted
            branchesKept    = $branchesKept
            # Coordination claims cleared because their holder was removed. `claimsUnreleased` is
            # reported beside it rather than folded in: a claim we could not clear is still an orphan,
            # and a single "claimsHandled" number would let a partial sweep read as a complete one --
            # the same over-claiming the branch counters above were fixed for.
            claimsReleased   = $claimsReleased
            claimsUnreleased = $claimsUnreleased
            claimsUnreadable = $claimsUnreadable.Count
        }
        # Listed, not just counted: the operator cannot clear a key whose file we will not name.
        # `scanned` disambiguates an empty list -- false means the registry was never read, not that it
        # was read and found clean.
        claims   = [pscustomobject]@{
            scanned    = $claimsScanned
            dir        = $claimsDir
            unreadable = @($claimsUnreadable.Values)
        }
        exitCode = $exit
    } | ConvertTo-Json -Depth 6 | Write-Output
    exit $exit
}

Write-Host ""
if (-not $Apply) {
    if ($prunable.Count -eq 0) {
        Write-Host "DRY RUN - nothing would be removed ($($decisions.Count) candidate(s) examined, all skipped)." -ForegroundColor Green
    }
    else {
        Write-Host "DRY RUN - $($prunable.Count) of $($decisions.Count) candidate(s) would be removed. Re-run with -Apply to act." -ForegroundColor Yellow
        Write-Host "  -Apply re-evaluates everything itself; it never acts on the table you read a minute ago." -ForegroundColor DarkGray
    }
}
else {
    # Outcomes, not intentions. Coloured by the EXIT CODE, not by $failed: a run where the fence died
    # and every removal was refused has failed 0 and used to print that line in green next to exit 2.
    $orphanText = if ($orphaned) { " ($orphaned ORPHANED, counted inside failed)" } else { "" }
    Write-Host "Done. removed $removed, failed $failed$orphanText, skipped $skipped of $($decisions.Count) candidate(s)." -ForegroundColor $(if ($exit -eq $EXIT_OK) { 'Green' } else { 'Red' })
    Write-Host "  branches: $branchesDeleted deleted, $branchesKept kept." -ForegroundColor DarkGray
    # Printed only when there is something to say. A standing "claims: 0 released" on every run trains
    # the eye to skip the line, which is precisely where the non-zero case needs to be noticed.
    if ($claimsReleased -gt 0 -or $claimsUnreleased -gt 0) {
        $claimColour = if ($claimsUnreleased -gt 0) { 'Red' } else { 'DarkGray' }
        Write-Host "  claims: $claimsReleased released$(if ($claimsUnreleased -gt 0) { ", $claimsUnreleased STILL ORPHANED" })." -ForegroundColor $claimColour
    }
}

# Run-level, and OUTSIDE the -Apply summary: an unreadable claim is a property of the registry, not of
# any removal, so a dry run that finds one must say so too rather than printing a tidy preview over a
# key nothing can take.
if ($claimsUnreadable.Count -gt 0) {
    Write-Host ""
    Write-Host "$($claimsUnreadable.Count) coordination claim(s) could not be READ, so it is unknown whose they are:" -ForegroundColor Red
    foreach ($u in $claimsUnreadable.Values) {
        Write-Host "  $($u.file)  --  $($u.detail)" -ForegroundColor Red
    }
    Write-Host "  They were left in place: deleting a claim we cannot attribute could free a key someone" -ForegroundColor Red
    Write-Host "  is mid-build on. Read them by hand, then clear with claim.ps1 -Release <key> -Force." -ForegroundColor Red
    Write-Host "  Until then those keys are unclaimable and claim.ps1 -Take will block on them." -ForegroundColor Red
}

# Orphans from an EARLIER run. Git no longer lists them, so nothing else in this report would.
if ($priorOrphans.Count -gt 0) {
    Write-Host ""
    Write-Host "$($priorOrphans.Count) ORPHANED director(ies) from an earlier run are still broken on disk:" -ForegroundColor Red
    foreach ($o in $priorOrphans) {
        Write-Host "  $($o.Leaf)  --  $($o.Why)" -ForegroundColor Red
        Write-Host "    Any session working there sees 'fatal: not a git repository'. Recover it:" -ForegroundColor Red
        Write-Host "      1. close anything holding files open in it (an editor, a shell sitting in it)" -ForegroundColor Red
        Write-Host "      2. Move-Item '$($o.Path)' '$($o.Path).salvage'" -ForegroundColor Red
        Write-Host "      3. git -C '$RepoRoot' worktree add '$($o.Path)'$(if ($o.Branch) { " '$($o.Branch)'" })" -ForegroundColor Red
        Write-Host "      4. copy anything you need out of '$($o.Path).salvage'" -ForegroundColor Red
    }
    if (-not $Apply) { Write-Host "  (this list is re-derived every run; it clears itself once the directory is gone or re-registered)" -ForegroundColor DarkGray }
}
if ($ledgerNote) { Write-Host "  NOTE: $ledgerNote" -ForegroundColor Yellow }

foreach ($r in $reducedAssurance) { Write-Host "  REDUCED ASSURANCE: $r" -ForegroundColor Red }
# REPORTED OUTSIDE THE EXIT-2 BRANCH, because a mid-run death can now land on either code: 2 when it
# died before anything was removed, 1 when it died after. Nesting this under exit 2 -- where it used
# to live, correctly, while one snapshot made a death mean nothing was ever attempted -- would leave
# the partial run with no explanation for why it stopped with candidates still standing.
if ($null -ne $occ2 -and -not $occ2.Available) {
    Write-Host "  The occupancy fence was available when the table was built and GONE by the time of the removals: $($occ2.Detail)" -ForegroundColor Red
    Write-Host "  A fence that dies mid-run stops the rest, so every candidate after it was skipped untouched. Fix the fence and re-run; don't bypass it." -ForegroundColor Red
    if ($removed -gt 0) {
        Write-Host "  Exit 1, not 2: $removed worktree(s) had already been removed when it died, so this run is a partial success rather than a refusal." -ForegroundColor Red
    }
}
if ($exit -eq $EXIT_REFUSED) {
    if (-not $occ.Available -or ($null -ne $occ2 -and -not $occ2.Available)) {
        Write-Host "  Exit 2: the occupancy fence was unavailable, so nothing was eligible. Fix the fence, don't bypass it." -ForegroundColor Red
    }
    if ($namedMisses.Count -gt 0) {
        Write-Host "  Exit 2: -Name named $($namedMisses -join ', '), which matched no prunable sibling, so what you asked for did not happen." -ForegroundColor Red
    }
}
elseif ($exit -eq $EXIT_ORPHANED) {
    Write-Host "  Exit 3: a directory is broken on disk RIGHT NOW. It is not a failed no-op -- follow the recipe above." -ForegroundColor Red
}
exit $exit
