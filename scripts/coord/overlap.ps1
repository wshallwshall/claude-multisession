#Requires -Version 7.3
<#
.SYNOPSIS
    What every OTHER session in this repo is changing right now -- files and stated work.

.DESCRIPTION
    presence.ps1 answers "who is here". This answers "what are they touching", which is the question
    that actually prevents a collision. Two sessions in separate worktrees are isolated on disk and
    still collide: they edit the same file and one of them rebases onto a surprise, or -- the case that
    actually cost real rework -- they build the SAME FIX in DIFFERENT files, produce zero merge
    conflicts, and both PRs go green (three sessions independently fixed the same dependency advisory;
    two PRs were closed as duplicates).

    So two independent signals, because they catch different failures:

      FILES  -- per worktree: committed changes vs the trunk, plus the uncommitted working tree.
                Catches concurrent edits. Exact, cheap, no cooperation required.
      WORK   -- per session: the subjects of its task list (<home>/.claude/tasks/<sessionId>/*.json).
                Catches duplicate EFFORT on different files. Free: sessions write these anyway, so
                nobody has to remember to declare anything.

    NOBODY HAS TO OPT IN. Every input here is a by-product of working normally -- git state and a task
    list a session already keeps. That is deliberate: claim.ps1 sat in the repository for a long time
    and was used exactly zero times, because a coordination step you must remember is a coordination
    step you will skip. Anything built on voluntary declaration decays to nothing.

    LIVE vs DORMANT. A worktree whose session is live is a CONCURRENT collision -- someone is editing
    it now. A worktree with changes but no live session is still worth knowing about (the work may
    already be done), but it cannot be racing you. Callers are expected to treat these differently:
    block on live, mention dormant.

    CACHED, because the git walk costs on the order of a second across a dozen worktrees and a
    PreToolUse hook runs on every single edit. The cache is a plain last-write-wins file: a
    stale-by-seconds view of who is editing what is fine, and two sessions refreshing at once cost a
    duplicate walk, not corruption.

    ROW CONTRACT v1 -- VERSION-LOCKED WITH scripts/hooks/collision_gate.ps1
    ----------------------------------------------------------------------
    The gate consumes `overlap.ps1 -File <path> -Json` and reads the fields below. BOTH SIDES PIN
    CONTRACT VERSION 1. Write it down here rather than leaving it to be inferred from the code, because
    the producer and the consumer are edited by different people at different times.

        Worktree      string    leaf name of the peer checkout
        Path          string    absolute path of that checkout
        Branch        string    branch checked out there, or "(detached)"
        Live          bool      a session fenced LIVE or UNVERIFIED is sitting in it
        SessionId     string    "" when not Live
        Short         string    first 8 characters of SessionId, or ""
        Surface       string    launching surface, client prefix stripped, or ""
        Files         string[]  repo-relative UNION of committed-and-unlanded and working-tree paths
        Dirty         string[]  repo-relative working-tree paths only -- a SUBSET of Files
        Work          string[]  sanitised task subjects, possibly empty
        MatchedDirty  bool      PRESENT ONLY ON -File ROWS. True iff the queried path appears in
                                Dirty, i.e. somebody has UNCOMMITTED work in it right now. False
                                means the row matched through Files alone: a branch authored that
                                file and has already committed it.

    COMPATIBILITY RULE. Adding a field is compatible and needs no coordination. Renaming or removing
    one, or changing what MatchedDirty MEANS, is not: change this block and the gate's own version-lock
    note IN THE SAME COMMIT. The gate already handles the one direction that can be handled safely --
    a row with no MatchedDirty at all (an old cache, an older overlap.ps1) is treated as dirty, so it
    over-blocks rather than permitting a real collision. There is no equivalent protection against the
    field keeping its name and changing its meaning: that turns "somebody is typing in this file" into
    "a finished branch touched it once" with no error anywhere, which is the entire failure this
    written-down contract exists to prevent.

    EXIT CODES, AND WHY THEY ARE PART OF THE CONTRACT
    -------------------------------------------------
    0   the question was ANSWERED. That includes "nobody else is in this file", which under -Json is
        the two bytes `[]` and on the human path is a stated line naming what was examined.
    2   the question could NOT be answered: no git repository resolved, so nothing was examined.

    The exit code is load-bearing rather than decorative, because it is the ONLY channel that reaches
    the gate. collision_gate.ps1 invokes this script with stderr discarded (`2>$null`) and reads `[]`
    as "resolved, and nobody else is touching it" -- so a stderr receipt on a can't-answer path is
    invisible to the consumer that most needs it, and the gate would go on reporting an all-clear
    derived from nothing having been measured. It already handles non-zero correctly.

    Adding a new non-zero code is compatible: the gate treats every non-zero alike. Making a
    can't-answer path exit 0 is NOT, and is the exact regression this block exists to prevent.

.EXAMPLE
    pwsh -NoProfile -File scripts/coord/overlap.ps1                       # human summary
    pwsh -NoProfile -File scripts/coord/overlap.ps1 -Json                 # machine-readable
    pwsh -NoProfile -File scripts/coord/overlap.ps1 -File src/app/service.py
    pwsh -NoProfile -File scripts/coord/overlap.ps1 -Refresh              # ignore the cache
#>
[CmdletBinding()]
param(
    # Ask about ONE path: who else is changing it. Repo-relative or absolute. This is the fast path a
    # hook takes on nearly every edit. An all-clear is `[]` under -Json and a STATED line on the human
    # path -- never silence, which is what this used to say and what it used to do.
    [string]$File,
    # Emit JSON.
    [switch]$Json,
    # Ignore the cache and re-walk.
    [switch]$Refresh,
    # How long a cached walk stays usable.
    [int]$CacheSeconds = 60,
    # Repo to inspect. Defaults to the current worktree's repo family.
    [string]$Repo,
    # Config roots for the session registry (tests point this at a fixture).
    [string[]]$ConfigRoot,
    # The ref that "landed" means. Defaults to CCX_TRUNK / ccx.config.json / the remote's recorded
    # default branch -- see Get-CcxTrunk. Never hardcode a branch name here: a project whose trunk is
    # master or develop would get an empty committed-work signal and no error.
    [string]$Trunk,
    # Where task lists live. Separate param so tests can supply their own. Resolved below rather than
    # in the default, because the home-directory lookup lives in a file this script dot-sources.
    [string]$TasksDir
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/session-registry.ps1"
. "$PSScriptRoot/_common.ps1"

if (-not $TasksDir) {
    $userHome = Get-ClaudeHomeDirectory
    $TasksDir = if ($userHome) { Join-Path $userHome (Join-Path ".claude" "tasks") } else { $null }
}

# Emit UTF-8 explicitly. The default console encoding mangles non-ASCII in task subjects (a Unicode
# arrow came through as a raw 0x1A), which turns valid output into JSON a consumer cannot parse.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Filesystem paths go through the one shared rule (canonicalise, then fold case only where the
# filesystem does). See _common.ps1.
function ConvertTo-Norm([string]$p) {
    return (ConvertTo-CcxComparablePath -Path $p)
}

# Repo-relative git paths are NOT filesystem paths and must not be canonicalised: they are always
# '/'-separated and always relative to the repository root, so resolving them against this process's
# cwd would silently compare two different things. Case folding follows the same platform rule as
# _common.ps1 uses, and for the same reason.
function ConvertTo-RepoPathKey([string]$p) {
    if (-not $p) { return "" }
    $k = ($p -replace '\\', '/').TrimEnd('/')
    if ($IsWindows -or $IsMacOS) { return $k.ToLowerInvariant() }
    return $k
}

# One emitter for every -Json exit, so no path can print nothing. See the note at the -File query below.
#
# The null filter is load-bearing, not defensive tidying. `Build-Map` returning no rows yields
# AutomationNull, which PARAMETER BINDING converts to a real $null on the way in -- and `@($null).Count`
# is 1, so the zero-rows guard was dead in exactly the case it was written for and the whole-map query
# emitted `[null]`: a phantom row, strictly worse than the nothing it replaced. Caught by adversarial
# review after the -File path had been verified by hand; the two call sites do not fail alike.
function Write-JsonArray($Rows) {
    $r = @($Rows | Where-Object { $null -ne $_ })
    if ($r.Count -eq 0) { Write-Output "[]"; return }
    Write-Output ($r | ConvertTo-Json -Depth 6 -AsArray)
}

$gitArgs = @(); if ($Repo) { $gitArgs = @("-C", $Repo) }
$common = Get-CcxGitCommonDir -Repo $Repo
if (-not $common) {
    # NO REPOSITORY IS NOT AN ANSWER, and this was the quietest exit in the file: nothing at all for a
    # human, and a bare `[]` for -Json -- the two bytes that mean "I walked every peer worktree and
    # nobody is in your file". Nothing had been walked. git had not resolved a repository at all.
    #
    # THE EXIT CODE IS THE FIX; a stderr receipt alone would not have been one. The gate discards our
    # stderr (`2>$null`) and reads `[]` as resolved-and-clear, so a receipt is invisible to exactly the
    # consumer that acts on the answer. A non-zero exit it already handles -- it says the edit was
    # allowed WITHOUT consulting any peer, which is the true statement. See EXIT CODES in the header.
    #
    # stdout still carries `[]` under -Json, so anything that only parses stdout is unaffected.
    $from = if ($Repo) { $Repo } else { $PWD.Path }
    [Console]::Error.WriteLine("overlap: NO REPOSITORY RESOLVED from '$from' -- nothing was examined, so nothing can be concluded. An empty result here is NOT 'nobody else is changing it'.")
    if ($Json) { "[]" | Write-Output }
    exit 2
}
$myRoot = Invoke-CcxGit -Repo $Repo -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
$myRootNorm = ConvertTo-Norm $myRoot

# The trunk. Resolved ONCE, here, so the whole run agrees about what "already landed" means.
#
# If it cannot be resolved the committed-work half of the FILES signal is off, and this says so on
# stderr on EVERY run rather than once: a degraded collision signal that announces itself only the
# first time is a degraded collision signal you will stop seeing. stdout stays pure JSON, so a machine
# consumer is unaffected -- note that the collision gate invokes this script with stderr discarded, so
# a human running it, or the doctor command, is who this line is actually for.
if (-not $Trunk) {
    try { $Trunk = Get-CcxTrunk -Repo $Repo } catch { $Trunk = $null }
}
if (-not $Trunk) {
    [Console]::Error.WriteLine("overlap: trunk unresolved -- reporting UNCOMMITTED changes only. Committed-but-unlanded work in peer worktrees is INVISIBLE in this run. Set trunk in ccx.config.json or CCX_TRUNK.")
}

# The cache lives in the shared state root (<git-common-dir>/<prefix>-coord), so every worktree of this
# clone reads and writes the same file and no `git add` can sweep it into a commit. A state root we
# cannot resolve means no cache: a slower hook, not a broken one.
$cacheFile = $null
try { $cacheFile = Join-Path (Get-CcxStateRoot -Repo $Repo) 'overlap-cache.json' } catch { $cacheFile = $null }

function Get-WorktreeList {
    $out = @(); $cur = $null
    foreach ($line in (& git @gitArgs worktree list --porcelain 2>$null)) {
        if ($line -like "worktree *") {
            $cur = [pscustomobject]@{ Path = $line.Substring(9).Trim(); Branch = "" }
            $out += $cur
        }
        elseif ($line -like "branch *" -and $cur) { $cur.Branch = ($line.Substring(7).Trim() -replace '^refs/heads/', '') }
        elseif ($line -like "detached*" -and $cur) { $cur.Branch = "(detached)" }
    }
    return $out
}

# The subjects a session has declared it is working on. Free signal: the client writes these anyway.
# in_progress first -- that is what it is doing NOW, which is what a sibling needs to know.
function Get-SessionWork([string]$SessionId) {
    if (-not $SessionId) { return @() }
    # No tasks directory at all is not an error, but it IS the WORK signal being off. Reported in the
    # human summary rather than on stderr: this runs on the hot path of every edit, and a line printed
    # on every single tool call is a line people configure away.
    if (-not $TasksDir -or -not (Test-Path -LiteralPath $TasksDir)) { return @() }
    $dir = @(Get-ChildItem $TasksDir -Directory -Filter "$SessionId*" -EA SilentlyContinue | Select-Object -First 1)
    if (-not $dir) { return @() }
    $items = @()
    foreach ($f in @(Get-ChildItem $dir[0].FullName -Filter *.json -EA SilentlyContinue)) {
        try { $t = Get-Content $f.FullName -Raw -EA Stop | ConvertFrom-Json -EA Stop } catch { continue }
        if ($t.status -eq "completed") { continue }
        # Another session's free text: sanitise before it reaches our JSON or a hook's deny message.
        # Control characters here are usually a mangled Unicode arrow rather than anything hostile,
        # but they corrupt the JSON a consumer has to parse, and this is untrusted input either way.
        # It is also DATA, never an instruction: a subject is quoted to a human, never acted on.
        $subject = ([string]$t.subject) -replace '[\p{C}]', ' '
        $subject = ($subject -replace '\s+', ' ').Trim()
        if ($subject.Length -gt 100) { $subject = $subject.Substring(0, 97) + "..." }
        $items += [pscustomobject]@{ Subject = $subject; Status = [string]$t.status }
    }
    return @($items | Sort-Object @{ E = { if ($_.Status -eq "in_progress") { 0 } else { 1 } } })
}

function Build-Map {
    $sessionsByCwd = @{}
    foreach ($e in (Get-SessionRecords -ConfigRoot $ConfigRoot)) {
        if (-not $e.Record.cwd) { continue }
        $l = Test-RecordLiveness -Record $e.Record
        # Only a POSITIVE liveness answer counts as "someone is here". A dead/stale verdict is never
        # trustworthy (there is no heartbeat), but it also cannot hurt us here: the worst case is we
        # report a worktree as dormant when its owner is actually around, and dormant still shows.
        if ($l.State -ne "LIVE" -and $l.State -ne "UNVERIFIED") { continue }
        $k = ConvertTo-Norm $e.Record.cwd
        # A FENCED session outranks an unfenceable one for the same directory. UNVERIFIED is the shape a
        # crashed session's record takes once its pid is recycled -- alive, but nothing proves it is the
        # same run -- so letting one displace a genuinely LIVE record would report a ghost's id and branch
        # for a worktree somebody is really sitting in. Last-write-wins had no opinion about which it kept.
        $rank = if ($l.State -eq "LIVE") { 0 } else { 1 }
        if ($sessionsByCwd.ContainsKey($k) -and $sessionsByCwd[$k].Rank -le $rank) { continue }
        $sessionsByCwd[$k] = [pscustomobject]@{ Record = $e.Record; Rank = $rank }
    }

    $worktrees = @(Get-WorktreeList)

    # ATTRIBUTE A SESSION TO THE MOST SPECIFIC WORKTREE CONTAINING IT, not to the first one that matches.
    #
    # Under the nested layout a linked worktree lives UNDER the primary checkout, so every linked
    # worktree's path is ALSO a prefix match for the primary's row. The old rule walked the session table
    # and broke on the first hit, so the primary row was handed whichever linked-worktree session the
    # hashtable happened to enumerate first -- reporting the primary checkout as LIVE, on a branch nobody
    # was on, "building" a peer's task list. Hashtable order is not stable, so the wrong answer was also a
    # different wrong answer each run, which is why it read as noise rather than as a bug.
    #
    # Longest prefix wins is the only rule that survives nesting: a session inside a nested worktree
    # matches both it and the primary, and the nested one is where it is actually sitting.
    $ownerByWorktree = @{}
    foreach ($k in @($sessionsByCwd.Keys | Sort-Object)) {
        $best = $null
        foreach ($w in $worktrees) {
            $wn = ConvertTo-Norm $w.Path
            if (Test-CcxPathUnder -Path $k -Root $wn) {
                if ($null -eq $best -or $wn.Length -gt $best.Length) { $best = $wn }
            }
        }
        # Two sessions inside one worktree: the fenced one wins, then first by sorted cwd -- so the
        # answer is the same every run, and a ghost never displaces a session that is really there.
        if ($best) {
            $cur = $ownerByWorktree[$best]
            if ($null -eq $cur -or $sessionsByCwd[$k].Rank -lt $cur.Rank) { $ownerByWorktree[$best] = $sessionsByCwd[$k] }
        }
    }

    $rows = @()
    foreach ($w in $worktrees) {
        $norm = ConvertTo-Norm $w.Path
        if ($norm -eq $myRootNorm) { continue }   # not a collision with yourself
        if (-not (Test-Path -LiteralPath $w.Path)) { continue }

        # Committed work on this branch, plus whatever is uncommitted in its tree.
        #
        # NEITHER diff form is correct alone, and each is wrong in the opposite direction:
        #   three-dot (<trunk>...HEAD) = what the BRANCH AUTHORED. Required, because two-dot alone
        #     blames a merely-behind branch for every file the trunk has moved underneath it.
        #   two-dot   (<trunk>..HEAD)  = what still DIFFERS from the trunk. Required, because a repo
        #     that SQUASH-merges never makes the squashed commit an ancestor of the branch, so the
        #     merge-base never advances and three-dot keeps crediting a landed branch with its files
        #     FOREVER. Its session then blocks that file set until someone prunes the worktree.
        # The INTERSECTION is what the branch authored AND has not yet landed. It self-clears on
        # squash, rebase and merge-commit alike. Measured on the repository this was developed in: two
        # landed branches claimed 8 and 4 files under three-dot and 0 under the intersection, while
        # every branch with genuinely outstanding work kept its full file set unchanged.
        #
        # IT SELF-CLEARS ONLY WHILE NOBODY ELSE EDITS THE SAME FILE, and that condition is not
        # decoration -- it was measured here after the fact. A worktree whose work had squash-landed,
        # working tree clean, detached at its pre-squash tip, was STILL credited with tests/README.md:
        # a later branch touched that same file, so two-dot reports it as differing from the trunk
        # again and the intersection stops being empty. The landed branch is blamed for somebody
        # else's edit.
        #
        # LEFT AS IT IS, DELIBERATELY. Such a row is DORMANT with MatchedDirty false, so the gate
        # cannot block on it (it requires Live AND MatchedDirty) and session-context.ps1 filters
        # dormant rows out entirely -- the cost is one line in a human summary, not a refused edit.
        # And the precise question, "is this difference MINE or did someone change it after me", is
        # not one the two-dot form can answer at all; buying it would mean walking history per file
        # on the hot path of every edit. Over-reporting a dormant row is the safe direction.
        #
        # What is NOT safe is reading the self-clearing property as unconditional, which is how it
        # was written for one release and how a reader will otherwise take it.
        $files = @()
        if ($Trunk) {
            $authored = @(& git -C $w.Path diff --name-only "$Trunk...HEAD" 2>$null)
            if ($LASTEXITCODE -eq 0) {
                $outstanding = @(& git -C $w.Path diff --name-only "$Trunk..HEAD" 2>$null)
                if ($LASTEXITCODE -eq 0) {
                    # Fall back to the authored set if the two-dot diff fails, so a git hiccup
                    # over-blocks (safe) rather than under-blocks (silent collisions).
                    $still = [System.Collections.Generic.HashSet[string]]::new(
                        [string[]]$outstanding, [System.StringComparer]::Ordinal)
                    $files += @($authored | Where-Object { $still.Contains($_) })
                }
                else { $files += $authored }
            }
        }
        # --no-optional-locks: a plain `git status` REWRITES the index of the repo it inspects, and this
        # walks every peer worktree -- so merely asking "what is in flight" would mutate other sessions'
        # checkouts. Read-only is mandatory for an observer.
        $dirty = @(& git -C $w.Path --no-optional-locks status --porcelain 2>$null |
            Where-Object { $_.Length -gt 3 } | ForEach-Object { $_.Substring(3).Trim('"') })
        $dirty = @($dirty | Where-Object { $_ } | Sort-Object -Unique)
        $files += $dirty
        $files = @($files | Where-Object { $_ } | Sort-Object -Unique)

        # A session sitting anywhere INSIDE the worktree owns it, not just one whose cwd is the root --
        # resolved above, against every worktree at once, because "inside" is ambiguous when they nest.
        $sess = if ($ownerByWorktree.ContainsKey($norm)) { $ownerByWorktree[$norm].Record } else { $null }
        if ($files.Count -eq 0 -and -not $sess) { continue }

        $rows += [pscustomobject]@{
            Worktree  = Split-Path $w.Path -Leaf
            Path      = $w.Path
            Branch    = $w.Branch
            Live      = [bool]$sess
            SessionId = if ($sess) { [string]$sess.sessionId } else { "" }
            Short     = if ($sess -and $sess.sessionId) { ([string]$sess.sessionId).Substring(0, 8) } else { "" }
            Surface   = if ($sess) { ([string]$sess.entrypoint) -replace '^claude-', '' } else { "" }
            Files     = $files
            # Files is the UNION of committed-and-unlanded and working-tree. A caller that must
            # distinguish "someone is typing in this file right now" from "this branch authored it and
            # is done" cannot do it from Files -- and this script's own contract (see LIVE vs DORMANT
            # above) tells callers to treat those differently, which was not honourable until Dirty
            # was reported separately. Observed: a session that had COMMITTED a file, gone clean, and
            # said in writing that it was finished still blocked every other session from that file,
            # because a committed file stays in Files until the branch lands -- and while PRs cannot
            # merge, that is forever.
            Dirty     = $dirty
            Work      = @(Get-SessionWork $(if ($sess) { [string]$sess.sessionId } else { "" }) | ForEach-Object { $_.Subject })
        }
    }
    return $rows
}

# --- cache -------------------------------------------------------------------------------------
$map = $null
if (-not $Refresh -and $cacheFile -and (Test-Path -LiteralPath $cacheFile)) {
    try {
        $c = Get-Content $cacheFile -Raw -EA Stop | ConvertFrom-Json -EA Stop
        $age = ((Get-Date) - [datetime]::Parse($c.at)).TotalSeconds
        # Bound BOTH ways: a cache stamped in the future (clock skew, or a file copied between boxes)
        # would otherwise look eternally fresh and pin a stale map forever.
        if ($age -ge 0 -and $age -lt $CacheSeconds -and $c.root -eq $myRootNorm) { $map = @($c.rows) }
    } catch { $map = $null }
}
if ($null -eq $map) {
    $map = Build-Map
    if ($cacheFile) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path $cacheFile) | Out-Null
            # Last-write-wins on purpose: a duplicate walk is the only cost of a race, and a lock on the
            # hot path of every edit would be worse than the thing it protects.
            @{ at = (Get-Date).ToString("o"); root = $myRootNorm; rows = $map } |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cacheFile -Encoding UTF8
        } catch { }   # a cache we cannot write is a slow hook, not a broken one
    }
}

# NORMALISE ONCE, HERE, so that no consumer below has to remember to. $map arrives by two routes and
# they do not agree about what empty looks like: a fresh walk with zero rows is AutomationNull, which
# `@()` correctly unrolls to nothing -- but that same emptiness ROUND-TRIPS THROUGH THE CACHE as
# `"rows": null`, and `@($null)` is a one-element array holding $null.
#
# So `@($map).Count` was 1 for an empty cached map. The zero-rows all-clear below never fired, and the
# render loop printed a PHANTOM WORKTREE: blank name, blank branch, "dormant", and "1 changed file(s)"
# -- that last because `@($null).Count` is 1 there too. It does not fail to report a peer, it INVENTS
# one, which is worse than the silence this script has now been fixed for twice.
#
# It is also STATEFUL, which is what kept it hidden: the fresh walk answers "No other worktree has
# changes." and the very next run inside the 60-second cache window answers with a ghost -- same repo,
# same state, two different answers. Reproduced against the real script, not reasoned about.
#
# Write-JsonArray keeps its own filter. That one guards a different mechanism (parameter binding
# converting AutomationNull to a real $null on the way in) and it is also called with $hits.
$map = @($map | Where-Object { $null -ne $_ })

# --- single-file query (the hook's fast path) ----------------------------------------------------
if ($File) {
    $q = $File
    if ([System.IO.Path]::IsPathRooted($q)) {
        $qn = ConvertTo-Norm $q
        $rn = "$myRootNorm/"
        if ($qn.StartsWith($rn)) { $q = $qn.Substring($rn.Length) } else { $q = $qn }
    }
    $q = ConvertTo-RepoPathKey $q
    $hits = @()
    foreach ($r in $map) {
        if (@($r.Files | ForEach-Object { ConvertTo-RepoPathKey $_ }) -contains $q) {
            # Tell the caller WHICH signal matched. Without this a consumer sees only "this row
            # mentions your file" and must treat a finished, committed branch identically to a session
            # with unsaved edits open in front of it. See the ROW CONTRACT in the header before
            # changing the name or the meaning of this field.
            $r | Add-Member -NotePropertyName MatchedDirty `
                -NotePropertyValue (@($r.Dirty | ForEach-Object { ConvertTo-RepoPathKey $_ }) -contains $q) -Force
            $hits += $r
        }
    }
    # ALWAYS EMIT AN ARRAY. `@() | ConvertTo-Json -AsArray` sends ZERO objects down the pipeline, so
    # ConvertTo-Json never runs and the script prints NOTHING -- despite -AsArray, which only shapes
    # output that exists. "Nobody else is in this file" therefore looked identical on stdout to "this
    # script died before it could answer", and a consumer had no way to tell an all-clear from a
    # failure. (-InputObject is not the fix: with -AsArray it double-wraps to [[]].) Verified against
    # the real script, not against a stub.
    if ($Json) { (Write-JsonArray $hits); exit 0 }
    # THE HUMAN PATH NEEDED THE SAME FIX AND DID NOT GET IT. The line above was written to stop an
    # empty -Json answer printing nothing; the loop below was left as the entire human output, so a
    # query with no hits printed NOTHING and exited 0 -- the identical failure, one branch over.
    #
    # This is the worse of the two, because of who reads it. The -Json consumer is the collision gate,
    # which has its own can't-tell path; the human consumer is a person running the command this repo
    # documents as the thing to do BEFORE starting a chunk of work. For them, "nobody else is changing
    # this file" was byte-identical to "this script died before it could answer", and both read as a
    # green light. So state the all-clear, and state what it was computed from: an all-clear that names
    # its evidence can be disbelieved when the evidence turns out to be thin (zero worktrees examined
    # is a very different all-clear from eleven).
    #
    # $map is normalised above, so this count is honest without filtering here. It did need the filter
    # when it was written -- an empty CACHED map would otherwise have reported one peer worktree
    # examined when none was.
    $examined = $map.Count
    if ($hits.Count -eq 0) {
        Write-Host "  $File -- no other worktree is changing it ($examined peer worktree(s) with changes or a live session examined)."
    }
    foreach ($h in $hits) {
        $state = if ($h.Live) { "LIVE $($h.Surface) session $($h.Short)" } else { "dormant worktree" }
        Write-Host "  $File is also changed by $state in $($h.Worktree) [$($h.Branch)]"
    }
    exit 0
}

if ($Json) { (Write-JsonArray $map); exit 0 }

if ($map.Count -eq 0) { Write-Host "No other worktree has changes."; exit 0 }
Write-Host ""
foreach ($r in $map) {
    $who = if ($r.Live) { "LIVE $($r.Surface) $($r.Short)" } else { "dormant" }
    Write-Host ("{0,-38} {1,-38} {2}" -f $r.Worktree, $r.Branch, $who)
    foreach ($w in @($r.Work | Select-Object -First 3)) { Write-Host "    building: $w" }
    Write-Host ("    {0} changed file(s)" -f @($r.Files).Count)
}
# Say which signals were actually running. An empty WORK column and a WORK signal that was never
# switched on look identical, and only one of them means "nobody declared anything".
if (-not $TasksDir -or -not (Test-Path -LiteralPath $TasksDir)) {
    Write-Host "  (WORK signal off: no task lists at '$TasksDir'. FILES only.)" -ForegroundColor DarkGray
}
if (-not $Trunk) {
    Write-Host "  (FILES signal partial: trunk unresolved, so committed-but-unlanded work is not shown.)" -ForegroundColor DarkGray
}
Write-Host ""
