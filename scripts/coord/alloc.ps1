#Requires -Version 7.3
<#
.SYNOPSIS
    Allocate the next free number in a shared sequence, atomically, so two concurrent sessions can
    never take the same one.

.DESCRIPTION
    NEVER grep for "max + 1". Two sessions that both grep pick the SAME number, create
    DIFFERENTLY-named files, merge CLEAN, and silently corrupt the sequence. That happened three
    times on the repo this was developed in, and it is invisible to git, to a file lock, and to
    "git merge-tree" -- there is no textual conflict to detect, because the two sessions never touch
    the same bytes.

    This is a test-and-set, not a read-modify-write. It claims the number by EXCLUSIVELY CREATING
    <state-root>/alloc/<kind>/<number>.json -- an atomic filesystem operation. If a sibling session
    already holds it, the create throws and we move to the next number. (A read-modify-write on a
    shared list is not an option: measured on the repo this was developed in, PowerShell silently
    lost 4 of 8 concurrent writes to a single shared file.)

    The registry lives beside the SHARED object store, so every worktree of a clone sees the same
    allocations, and a different clone automatically gets its own registry.

    WHAT A SEQUENCE IS is entirely ccx.config.json's business. Each entry under "sequences" names a
    kind and describes where its numbers live:

        "adr": {
          "dir":             "docs/adr",                            # the directory to sweep
          "filePattern":     "^docs/adr/(\\d{4})-[^/]+\\.md$",      # group 1 = the number
          "pad":             4,                                     # zero-padding, 0 = none
          "indexFile":       "docs/adr/README.md",                  # optional index/table
          "indexRowPattern": "^\\|\\s*\\[(\\d{4})\\]"               # group 1 = the number
        }

    Nothing about that shape is baked into this script. Omit the "sequences" key entirely and
    allocation is simply off.

    AS MANY SEQUENCES AS THE REPOSITORY HAS LEDGERS. "sequences" is a map, so a repository keeping
    decision records and a backlog declares both, each with its own five keys; -Kind picks one and
    becomes required at two. Each kind gets its own registry directory, so their floors and their
    claims never meet. Adding one never changes an existing entry.

    TWO RULES THAT ONLY MATTER ONCE THERE ARE TWO, both checked before the registry is touched.
    A name must be one plain path segment, because it becomes a directory under the registry. And
    no two sequences may declare the same filePattern, or the same indexFile plus indexRowPattern:
    the claim below excludes per kind, so two kinds recognising one set of files can each issue the
    same number.

    THE FLOOR is the max over: the trunk, every local and remote ref, the working tree, and every
    existing allocation -- then ratcheted against a persisted high-water mark. The all-refs term
    closes the "registry wiped -> re-issue a number that only exists on an unpushed branch" hole. It
    costs about a second, once per allocation -- not per edit.

    Numbers are never reclaimed. An abandoned branch holds its number forever and the sequence
    develops holes. That is deliberate: holes are free, collisions are not.

.EXAMPLE
    pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "Worktree gate"
    pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -ShowFloor
    pwsh -NoProfile -File scripts/coord/alloc.ps1 -List
#>
[CmdletBinding()]
param(
    # Which configured sequence to allocate from. Deliberately NOT a [ValidateSet]: the set of kinds
    # lives in ccx.config.json, and restating it here would give the repo two lists that must agree.
    # Validated against the config below, with the configured names printed on a miss.
    [string]$Kind,
    [string]$Title,
    # Show what this worktree currently holds, and exit.
    [switch]$List,
    # Print the computed floor and the paths it swept, then exit WITHOUT allocating.
    #
    # Allocation is a one-way door -- claims are never released ("holes are free, collisions are
    # not") -- so before this switch the only way to find out what the floor could see was to spend a
    # number on the question. That makes the floor's own correctness the one property nobody
    # re-tests, which is how it went a whole release reading two refs while its header promised all
    # of them. A gate that cannot be inspected without altering the thing it guards will not be
    # inspected.
    [switch]$ShowFloor
)

$ErrorActionPreference = "Stop"
# We read git's exit code ourselves -- Invoke-CcxGit returns $null on failure, and the sweep below
# treats that as an EXPECTED answer (a ref that does not carry the sequence directory is the normal
# case, not an error). On a host where the native-command error preference is enabled, "Stop"
# additionally turns every non-zero git exit into a terminating error, which would abort the floor
# sweep partway through -- and a floor that stops early is silently too LOW, which is the one failure
# this script exists to prevent. Opt out here; .NET and cmdlet errors still stop.
$PSNativeCommandUseErrorActionPreference = $false

. "$PSScriptRoot/_common.ps1"

$self = 'pwsh -NoProfile -File scripts/coord/alloc.ps1'

$cfg = Get-CcxConfig
$repo = Invoke-CcxGit -Arguments @('rev-parse', '--path-format=absolute', '--show-toplevel')
if (-not $repo) { throw "Not inside a git repository." }

$allocRoot = Join-Path (Get-CcxStateRoot) 'alloc'

if ($cfg.sequences.Count -eq 0) {
    # "No sequences" is a valid configuration, not an error state -- a repo that does not maintain a
    # numbered sequence should not have to carry a disabled allocator. Say which file to edit.
    throw ("No sequences are configured in $($cfg.ConfigPath), so there is nothing to allocate. " +
        "Add a 'sequences' entry (see the header of this script for the shape), or stop calling this.")
}

$kinds = @($cfg.sequences.Keys | Sort-Object)

function Get-SeqField($Obj, [string]$Name) {
    if ($null -ne $Obj -and $Obj.PSObject.Properties.Name -contains $Name -and $null -ne $Obj.$Name) {
        return $Obj.$Name
    }
    return $null
}

# WHOLE-CONFIG CHECKS, RUN BEFORE ANY BRANCH REACHES THE REGISTRY.
#
# Both hazards below are relationships between the config and something outside one entry, so a
# per-entry check cannot see either. Both were unreachable while a single kind was effectively
# hardcoded, and both arrive with the second ledger a repository declares.
# ORDINAL, because a PowerShell hashtable compares keys case-INSENSITIVELY while .NET regexes are
# case-sensitive by default. Two sequences whose filePatterns differ only in case are distinct
# namespaces on a case-sensitive filesystem, and a folding hashtable refuses them as duplicates.
# $seenIndexes below is left folding ON PURPOSE: its key joins a PATH, case-insensitive on
# Windows, to a regex, which is not, so ordinal there would trade this false refusal for a false
# ACCEPTANCE of two sequences reading one file. That half needs a split comparison, not this fix.
$seenPatterns = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::Ordinal)
$seenIndexes = @{}
foreach ($k in $kinds) {
    # THE NAME BECOMES A DIRECTORY under the registry root, so it is a path component carrying
    # whatever the config author typed. Measured before this check existed: a sequence named
    # "../escape" wrote its claims to <state-root>/escape, outside the allocation registry entirely,
    # and reported success. A name of "../claims" would drop them into a sibling tool's state.
    # Refuse anything that is not one plain segment rather than sanitising it into a name nobody
    # typed -- a silently renamed sequence allocates from a registry its owner cannot find.
    # \A and \z, NOT ^ and $. In .NET `$` also matches immediately before a trailing newline,
    # so a name ending in one passed this check while the prose beside it promised a single
    # plain segment. \z is the end of the string and nothing else.
    if ($k -notmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') {
        throw ("Sequence name '$k' in $($cfg.ConfigPath) is not usable. It becomes a directory name " +
            "under the allocation registry, so it must be a single path segment: a letter or digit " +
            "first, then letters, digits, dot, underscore or hyphen, 64 characters at most.")
    }

    # TWO NAMES FOR ONE NAMESPACE. The claim below is exclusive per (kind, number) and nothing
    # excludes ACROSS kinds, so two sequences that recognise the same paths can each issue the same
    # number, into differently-named files, that merge clean. That is the corruption the registry
    # exists to prevent, reintroduced through the config. The realistic way in is copy-paste: clone
    # the `adr` block, rename it, forget to change the strings.
    #
    # Identical patterns are the half that can be PROVED to overlap, and this claims no more than
    # that: two different regexes can still describe overlapping sets. Give each sequence a pattern
    # only its own files match.
    $entry = $cfg.sequences[$k]
    $pat = [string](Get-SeqField $entry 'filePattern')
    if ($pat) {
        if ($seenPatterns.ContainsKey($pat)) {
            throw ("Sequences '$($seenPatterns[$pat])' and '$k' in $($cfg.ConfigPath) declare the same " +
                "filePattern, so they recognise the same files while claiming numbers from separate " +
                "registries, and both can issue the same number. Give each its own filePattern.")
        }
        $seenPatterns[$pat] = $k
    }
    # The same argument over the other membership test. A sequence whose numbers are rows in a file
    # is recognised by indexFile plus indexRowPattern, so sharing both is sharing a namespace.
    $ixFile = [string](Get-SeqField $entry 'indexFile')
    $ixRow = [string](Get-SeqField $entry 'indexRowPattern')
    if ($ixFile -and $ixRow) {
        $ixKey = "$ixFile`n$ixRow"
        if ($seenIndexes.ContainsKey($ixKey)) {
            throw ("Sequences '$($seenIndexes[$ixKey])' and '$k' in $($cfg.ConfigPath) read the same rows " +
                "out of $ixFile, so they share one index namespace while claiming numbers from separate " +
                "registries. Give each its own index, or its own row pattern.")
        }
        $seenIndexes[$ixKey] = $k
    }
}

if ($List) {
    $me = ConvertTo-CcxComparablePath $repo
    foreach ($k in $kinds) {
        $dir = Join-Path $allocRoot $k
        $mine = @(Get-ChildItem $dir -Filter *.json -EA SilentlyContinue | ForEach-Object {
                $c = Get-Content $_.FullName -Raw | ConvertFrom-Json
                if ((ConvertTo-CcxComparablePath $c.worktree) -eq $me) { $c }
            })
        Write-Host "$k allocated to this worktree: $(if ($mine) { ($mine.number -join ', ') } else { '(none)' })"
    }
    return
}

if (-not $Kind) {
    # One configured sequence is the common case and having to name it adds nothing. Two or more and
    # a default would be a guess about which one you meant.
    if ($kinds.Count -eq 1) { $Kind = $kinds[0] }
    else { throw "-Kind is required. Configured sequences: $($kinds -join ', ')." }
}
if (-not $cfg.sequences.ContainsKey($Kind)) {
    throw "Unknown sequence '$Kind'. Configured in $($cfg.ConfigPath): $($kinds -join ', ')."
}
$seq = $cfg.sequences[$Kind]

$seqDir = [string](Get-SeqField $seq 'dir')
$filePattern = [string](Get-SeqField $seq 'filePattern')
$indexFile = [string](Get-SeqField $seq 'indexFile')
$indexRowPattern = [string](Get-SeqField $seq 'indexRowPattern')
$padRaw = Get-SeqField $seq 'pad'
$pad = if ($null -ne $padRaw) { [int]$padRaw } else { 0 }

# VALIDATE THE CONFIG BEFORE TOUCHING THE REGISTRY, and name the file and the key in every message.
# A malformed pattern that only fails halfway through a sweep produces a floor that is silently too
# low, and a too-low floor is the exact failure this whole script exists to prevent.
if (-not $seqDir) { throw "Sequence '$Kind' in $($cfg.ConfigPath) has no 'dir'." }
if (-not $filePattern) { throw "Sequence '$Kind' in $($cfg.ConfigPath) has no 'filePattern'." }
try { $fileRx = [regex]::new($filePattern) }
catch { throw "Sequence '$Kind': filePattern is not a valid regex -- $($_.Exception.Message)" }
if ($fileRx.GetGroupNumbers().Count -lt 2) {
    throw ("Sequence '$Kind': filePattern must contain a capturing group around the number, " +
        "e.g. '^docs/adr/(\d{4})-[^/]+\.md$'. Got: $filePattern")
}
# MULTILINE IS LOAD-BEARING on the index pattern, and its absence was once a silent hole. A regex
# built without it anchors '^' at the start of the STRING, not of each line. The all-refs term below
# feeds it one line at a time, so it matched there and looked correct -- while the working-tree term
# feeds it the whole file as one string, where '^' could never match after the first line. Measured
# on the repo this was developed in: without Multiline the working-tree term found NONE of the
# index's rows; with it, all of them. So the term that exists to catch a number written but committed
# NOWHERE had been finding nothing since it was written, and the all-refs term hid it by covering
# every number that had been committed somewhere -- i.e. every case except the one that term is for.
$rowRx = $null
if ($indexFile -and $indexRowPattern) {
    try { $rowRx = [regex]::new($indexRowPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline) }
    catch { throw "Sequence '$Kind': indexRowPattern is not a valid regex -- $($_.Exception.Message)" }
    if ($rowRx.GetGroupNumbers().Count -lt 2) {
        throw "Sequence '$Kind': indexRowPattern must contain a capturing group around the number."
    }
} elseif ($indexFile -or $indexRowPattern) {
    # Half a configuration would silently drop a whole term from the floor.
    throw "Sequence '$Kind': 'indexFile' and 'indexRowPattern' must be given together, or not at all."
}

$alloc = Join-Path $allocRoot $Kind
New-Item -ItemType Directory -Force -Path $alloc | Out-Null

# -ShowFloor allocates nothing, so there is no claim for a title to be recorded against.
if (-not $Title -and -not $ShowFloor) {
    throw "-Title is required (it is recorded with the claim, so a sibling session can see what the number is for)."
}

# Measure-Object hands back a [double], and a zero-padding format specifier is integer-only. Cast at
# the boundary rather than at each use.
function Format-SeqNumber([int]$Value) {
    if ($pad -gt 0) { return $Value.ToString([string]::new('0', $pad)) }
    return [string]$Value
}

# Not fatal if it cannot be resolved: the all-refs term below already covers origin/main under its
# usual name. The trunk is included by name so an explicitly configured, unusual trunk is swept too.
$trunk = $null
try { $trunk = Get-CcxTrunk } catch { }

$branch = Invoke-CcxGit -Arguments @('branch', '--show-current')
# `git branch --show-current` prints NOTHING on a detached HEAD, so this is $null (not ""). Calling
# .Trim() on it before the fallback threw *before* the fallback could run. Null-check first.
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = "detached@" + (Invoke-CcxGit -Arguments @('rev-parse', '--short', 'HEAD'))
}
$branch = $branch.Trim()

# FLOOR = max over (trunk) U (every local + remote ref) U (working tree) U (existing allocations),
# ratcheted against a persisted high-water mark.
function Get-Floor {
    # -Peek computes the floor WITHOUT advancing the high-water ratchet. The ratchet is a one-way
    # door, so an inspection that moves it is not an inspection -- and the first run of -ShowFloor
    # against a deliberately planted number proved it, ratcheting that clone to a fabricated floor no
    # later run could undo. Reading a value must not be able to corrupt it.
    param([switch]$Peek)

    $seen = [System.Collections.Generic.List[int]]::new()
    $seen.Add(0)
    $sources = [System.Collections.Generic.List[string]]::new()

    # EVERY ref, not just the trunk. Reading only the published branch is what re-issues numbers that
    # already exist on refs the published branch does not carry: they are invisible to the sweep, so
    # the allocator hands them out as free, and the collision surfaces later as two differently-named
    # files that merged clean. A number that exists on ANY ref is taken.
    $refs = [System.Collections.Generic.List[string]]::new()
    $refs.Add('HEAD')
    if ($trunk) { $refs.Add($trunk) }
    $refList = Invoke-CcxGit -Arguments @('for-each-ref', '--format=%(refname)', 'refs/heads', 'refs/remotes')
    if ($refList) {
        foreach ($r in ($refList -split "`r?`n")) { if ($r.Trim()) { $refs.Add($r.Trim()) } }
    }
    $refs = @($refs | Select-Object -Unique)
    $sources.Add("refs swept: $($refs.Count) (HEAD + trunk + refs/heads + refs/remotes)")

    # TERM 1 -- FILENAMES, per ref.
    #
    # One git process per ref, deliberately and unavoidably: `cat-file --batch-check` takes a spec
    # list and cannot glob a directory, so listing a directory's entries needs `ls-tree` per ref.
    # That is the expensive term. It is paid once per allocation, not once per edit.
    foreach ($ref in $refs) {
        $names = Invoke-CcxGit -Arguments @('ls-tree', '-r', '--name-only', $ref, $seqDir)
        if (-not $names) { continue }
        foreach ($n in ($names -split "`r?`n")) {
            $m = $fileRx.Match($n.Trim())
            if ($m.Success) { $seen.Add([int]$m.Groups[1].Value) }
        }
    }
    $sources.Add("filenames : $seqDir (pattern $filePattern, all refs)")

    # TERM 2 -- THE INDEX FILE'S CONTENT, per ref, BATCHED.
    #
    # An index is ONE file, so this term needs its CONTENT rather than a filename listing. Batched
    # because a `git show` per ref spawns one process each: measured on the repo this was developed
    # in, that cost about 34 seconds on Windows where two `git cat-file` processes did the same work
    # in about 3. Most refs share the same blob, so de-duplicating by object id collapses several
    # hundred specs into far fewer reads.
    if ($rowRx) {
        $specs = foreach ($r in $refs) { "${r}:${indexFile}" }
        $oids = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($line in ($specs -join "`n" | & git cat-file --batch-check='%(objectname) %(objecttype)' 2>$null)) {
            $p = "$line".Split(' ')
            if ($p.Count -ge 2 -and $p[1] -eq 'blob') { [void]$oids.Add($p[0]) }
        }
        if ($oids.Count -gt 0) {
            foreach ($line in (($oids -join "`n") | & git cat-file --batch 2>$null)) {
                foreach ($m in $rowRx.Matches("$line")) { $seen.Add([int]$m.Groups[1].Value) }
            }
        }
        $sources.Add("index rows: $indexFile (pattern $indexRowPattern, all refs, $($oids.Count) distinct blobs)")
    }

    # TERM 3 -- THE WORKING TREE. Catches a number written to a file but committed nowhere. Both the
    # directory and the index, for the same reason: a draft is still a claim on its number.
    $wtDir = Join-Path $repo $seqDir
    if (Test-Path -LiteralPath $wtDir) {
        foreach ($f in (Get-ChildItem -LiteralPath $wtDir -Recurse -File -EA SilentlyContinue)) {
            # The pattern is written against a repo-relative, forward-slash path, which is what git
            # reports. Build the same shape here rather than matching against an absolute one.
            $rel = ([System.IO.Path]::GetRelativePath($repo, $f.FullName) -replace '\\', '/')
            $m = $fileRx.Match($rel)
            if ($m.Success) { $seen.Add([int]$m.Groups[1].Value) }
        }
    }
    if ($rowRx) {
        $wtIndex = Join-Path $repo $indexFile
        if (Test-Path -LiteralPath $wtIndex) {
            foreach ($m in $rowRx.Matches((Get-Content -LiteralPath $wtIndex -Raw))) {
                $seen.Add([int]$m.Groups[1].Value)
            }
        }
    }
    $wtSwept = if ($rowRx) { "$seqDir + $indexFile" } else { $seqDir }
    $sources.Add("working tree: $wtSwept")

    # TERM 4 -- EXISTING ALLOCATIONS. A number claimed but not yet written anywhere.
    foreach ($f in (Get-ChildItem $alloc -Filter *.json -EA SilentlyContinue)) {
        $n = 0
        if ([int]::TryParse($f.BaseName, [ref]$n)) { $seen.Add($n) }
    }
    $sources.Add("registry  : $alloc")

    # HIGH-WATER RATCHET -- the floor may rise but must never fall.
    #
    # Every other term above is derived from refs that a routine cleanup can remove, and the sweep is
    # only as good as the refs THIS clone happens to hold. Measured on the repo this was developed
    # in: the floor computed over all refs was materially higher than the floor computed over
    # origin's refs and local heads alone, because numbers lived on remote-tracking refs for a remote
    # that `git remote -v` no longer listed. Drop those and the floor silently reverts to a lower
    # value and the allocator resumes issuing numbers that are already used, with no error and no
    # signal. That is the exact bug this function was fixed for, so leaving its correctness dependent
    # on nobody tidying refs is not good enough: persist the high-water mark and never go below it.
    #
    # SAFE:      `git fetch origin --prune` -- prunes only refs/remotes/origin/*, and it is what you
    #            SHOULD run before allocating.
    # DANGEROUS: `git remote prune <name>` / `git remote remove <name>` for any other remote, deleting
    #            a block of remote-tracking refs, or an aggressive `gc` / `reflog expire` that drops
    #            unreachable objects. Those are what this ratchet defends against.
    #
    # THE RATCHET IS SHARED STATE AND THE CALLERS ARE CONCURRENT, which the first version of it did
    # not account for: `Set-Content` and `Get-Content` each open the file without sharing, so two
    # allocators reaching this line together threw an unhandled IOException. Measured before this
    # fix, eight simultaneous allocations returned SEVEN numbers -- one process died here, before it
    # had claimed anything, and the doc's own promise of eight distinct numbers was false. The claim
    # loop below was never the problem; a session simply never reached it.
    #
    # The two sides are guarded differently ON PURPOSE. A lost WRITE is recoverable: the floor this
    # run computed is already correct in memory, and the registry term re-derives it next time, so it
    # warns and carries on. A lost READ is not: treating an unreadable ratchet as zero silently
    # lowers the floor, which is the one failure this script exists to prevent, so it raises.
    $watermark = Join-Path $alloc ".floor-highwater"
    $computed = [int](($seen | Measure-Object -Maximum).Maximum)
    $previous = 0
    if (Test-Path $watermark) {
        $raw = $null
        $readOk = $false
        $readErr = $null
        foreach ($attempt in 1..20) {
            # EVERY exception, not a list of the ones somebody thought of. Windows reports a
            # contended file as UnauthorizedAccessException ("Access to the path is denied") about as
            # often as it reports IOException, and the provider raises InvalidOperationException for
            # a path that is a DIRECTORY. Two typed catches let that third one escape the loop and
            # kill the run inside Get-Content, so the operator got a provider message about using
            # Get-ChildItem instead of the refusal below -- the very bug this guard exists to fix,
            # surviving in the cases the list did not name. The fail direction here is refusal, so a
            # broad catch cannot lower the floor; it can only make the run stop and say why.
            try { $raw = Get-Content $watermark -Raw -ErrorAction Stop; $readOk = $true; break }
            catch { $readErr = $_; Start-Sleep -Milliseconds 25 }
        }
        if (-not $readOk) {
            throw ("Could not read the $Kind high-water mark at $watermark after 20 attempts: " +
                "$($readErr.Exception.Message). Refusing to allocate -- ignoring the ratchet would " +
                "silently lower the floor, which is how a number already in use gets re-issued.")
        }
        # A SUCCESSFUL READ IS NOT YET A NUMBER, and the two ways it is not get separate sentences
        # because they are separate operator problems. `Get-Content -Raw` returns $null for a
        # zero-byte file and raises NOTHING, so an empty ratchet used to reach the contention throw
        # above having made one attempt that WORKED: it reported 20 attempts, and printed an empty
        # cause after "attempts:", so an absent cause and a real one rendered identically. An
        # unparseable value took the quieter road -- TryParse failed, $previous stayed 0, and the run
        # allocated. That is the silent floor-lowering the refusal exists to prevent, arriving
        # through the door marked success.
        $text = ""
        if ($null -ne $raw) { $text = $raw.Trim() }
        if ($text -eq "") {
            throw ("The $Kind high-water mark at $watermark is empty. Refusing to allocate -- an " +
                "empty ratchet is not a floor of zero, and reading it as one forgets every number " +
                "that lived only in the ratchet. Restore it from a clone that still has those refs, " +
                "or delete the file to restart the ratchet from the numbers this clone can see.")
        }
        if (-not [int]::TryParse($text, [ref]$previous)) {
            throw ("The $Kind high-water mark at $watermark does not hold a number: '$text'. " +
                "Refusing to allocate -- a value that will not parse reads as a floor of zero, " +
                "which is how a number already in use gets re-issued.")
        }
    }

    if ($previous -gt $computed) {
        Write-Host "NOTE: computed $Kind floor $computed is BELOW the recorded high-water $previous." -ForegroundColor Yellow
        Write-Host "      Using $previous. Refs that carried the higher numbers are missing from this clone;" -ForegroundColor Yellow
        Write-Host "      re-fetch them before trusting any number-space reasoning here." -ForegroundColor Yellow
    }
    $floor = [Math]::Max($computed, $previous)
    if ($floor -gt $previous -and -not $Peek) {
        # Write beside it, then replace in one move, so the file a sibling reads is never a partly
        # written one and readers never contend with a writer. All the waiting is on this side.
        $temp = Join-Path $alloc (".floor-highwater." + [System.IO.Path]::GetRandomFileName())
        try {
            # -ErrorAction Stop, because Set-Content fails NON-TERMINATINGLY by default. Without it a
            # failed stage emitted an error and execution carried straight on to the Move below,
            # replacing a good ratchet with a missing or empty temp. An empty ratchet is what the
            # read side above now refuses on, so one failed write would have stopped every later
            # allocation of this kind. Caught rather than thrown: a lost WRITE is recoverable, so it
            # warns and the allocation still succeeds, which is the asymmetry this block is built on.
            $wrote = $false
            try {
                Set-Content -Path $temp -Value $floor -Encoding ASCII -ErrorAction Stop
                $wrote = $true
            } catch {
                Write-Host "NOTE: could not stage the $Kind high-water mark ($($_.Exception.Message))." -ForegroundColor Yellow
                Write-Host "      This allocation is unaffected -- the floor it computed is $floor either way." -ForegroundColor Yellow
            }
            $moved = $false
            if ($wrote) {
                foreach ($attempt in 1..20) {
                    try { [System.IO.File]::Move($temp, $watermark, $true); $moved = $true; break }
                    catch [System.IO.IOException] { Start-Sleep -Milliseconds 25 }
                    catch [System.UnauthorizedAccessException] { Start-Sleep -Milliseconds 25 }
                }
            }
            if ($wrote -and -not $moved) {
                Write-Host "NOTE: could not raise the $Kind high-water mark to $floor (a sibling holds $watermark)." -ForegroundColor Yellow
                Write-Host "      This allocation is unaffected -- the floor it computed is $floor either way." -ForegroundColor Yellow
            }
        } finally {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }

    [pscustomobject]@{
        Floor     = [int]$floor
        Computed  = [int]$computed
        HighWater = [int]$previous
        Sources   = @($sources)
    }
}

# ONE computation, TWO callers. -ShowFloor and a real allocation differ ONLY by -Peek, so they cannot
# report different numbers. They used to: -ShowFloor returned before a guard that every real
# allocation ran, so it printed a next number the tool would then refuse to issue -- an inspector
# that does not run the checks it previews answers the adjacent question, not the one asked. Anything
# added later that can change the outcome belongs INSIDE Get-Floor or above both branches, never in
# one of them.
$measured = Get-Floor -Peek:$ShowFloor
$observed = $measured.Floor

if ($ShowFloor) {
    # Name the SOURCES, not just the number. "Which paths did this sweep actually read" is the
    # question every silent-narrowing bug turns on, and a bare integer cannot answer it -- a floor
    # looks identical whether it swept one path or two.
    Write-Host "kind      : $Kind"
    Write-Host "trunk     : $(if ($trunk) { $trunk } else { '(unresolved -- all-refs term still applies)' })"
    Write-Host "floor     : $observed  (computed $($measured.Computed), high-water $($measured.HighWater))"
    foreach ($s in $measured.Sources) { Write-Host "  $s" }
    Write-Host "next      : $(Format-SeqNumber ($observed + 1))"
    Write-Host "watermark : $(Join-Path $alloc '.floor-highwater')"
    Write-Host ""
    Write-Host "Read-only: nothing was allocated." -ForegroundColor DarkGray
    return
}

$start = $observed + 1
for ($i = $start; $i -lt $start + 500; $i++) {
    $name = Format-SeqNumber $i
    $file = Join-Path $alloc "$name.json"
    try {
        # ATOMIC test-and-set. 'CreateNew' + FileShare::None throws IOException if a sibling got here
        # first -- that throw IS the mutual exclusion.
        $fs = [System.IO.File]::Open($file, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    } catch [System.IO.IOException] {
        continue    # taken by a sibling session; try the next number
    }
    try {
        $claim = [ordered]@{
            number   = $name
            kind     = $Kind
            title    = $Title
            branch   = $branch
            worktree = $repo
            claimed  = (Get-Date).ToString("o")
        } | ConvertTo-Json -Compress
        # UTF-8 with NO BOM, like every other record in this directory: the python-side gates read
        # these with encoding="utf-8", and a BOM makes json.loads raise.
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($claim)
        $fs.Write($bytes, 0, $bytes.Length)
    } finally {
        $fs.Dispose()
    }

    $slug = ($Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')

    Write-Host ""
    Write-Host "ALLOCATED $Kind $name" -ForegroundColor Green
    Write-Host "  place it under : $seqDir/"
    Write-Host "  path must match: $filePattern"
    if ($slug) { Write-Host "  suggested name : $seqDir/$name-$slug.<ext>" }
    if ($indexFile) {
        Write-Host "  index          : add its row to $indexFile in the SAME commit (the sequence gate checks)."
    }
    Write-Host "  claimed by     : $repo [$branch]"
    exit 0
}

throw ("No free $Kind number found in 500 tries starting at $(Format-SeqNumber $start) -- the registry " +
    "at $alloc looks wrong. Inspect it with: $self -Kind $Kind -ShowFloor")
