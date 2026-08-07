#Requires -Version 7.3
<#
.SYNOPSIS
    SessionStart hook: print this repository's working defaults plus a live parallel-session
    coordination banner into a new chat's starting context.

.DESCRIPTION
    Wired as a SessionStart hook in .claude/settings.json. Whatever this prints to stdout is injected
    into the chat's starting context, so a new window starts already knowing the project's
    preferences and the rules for working alongside sibling sessions.

    Two parts:

      1. THE PROJECT BANNER -- printed every session, and NOT written here. Project policy is not
         something a tool can guess, so the text lives in a file you own:

             $env:CCX_SESSION_BANNER, if set; otherwise <repo-root>/.ccx/session-banner.md

         See examples/session-banner.md.example. No file, no banner -- part 2 still runs.

      2. PARALLEL-SESSION COORDINATION -- printed ONLY when 2+ worktrees share this git directory,
         i.e. when parallel sessions are actually in play and could collide. It warns a session that
         landed in the SHARED PRIMARY to branch into its own worktree first, lists who is live, says
         what they are building, shows active claims, and nudges cleanup of finished worktrees.

    SAFETY PROPERTY, do not weaken it: THIS HOOK NEVER FAILS LOUDLY. Whatever it prints IS the chat's
    starting context, so an unhandled error would replace the banner with a stack trace -- in front of
    the model, every session, until someone noticed. $ErrorActionPreference is SilentlyContinue and
    every sub-probe is individually try/caught. A probe that cannot answer prints nothing; it never
    prints a guess.

    See docs/WORKTREES.md and docs/COORDINATION.md.
#>
$ErrorActionPreference = "SilentlyContinue"

$lines = @()

# --- (1) the project's own banner ----------------------------------------------------------------
$bannerPath = $null
if ($env:CCX_SESSION_BANNER) {
    $bannerPath = $env:CCX_SESSION_BANNER
} else {
    # git prints forward slashes even on Windows; Join-Path accepts them, so leave them alone rather
    # than rewriting separators (a regex replacement whose target is '\' escapes the next character).
    $top = (& git rev-parse --show-toplevel 2>$null)
    if ($top) { $bannerPath = Join-Path $top ".ccx/session-banner.md" }
}
if ($bannerPath -and (Test-Path -LiteralPath $bannerPath -PathType Leaf)) {
    try {
        $text = (Get-Content -LiteralPath $bannerPath -Raw -ErrorAction Stop).TrimEnd()
        if ($text) { $lines += $text }
    } catch { }
}

# --- (2) parallel-session coordination, only when 2+ worktrees share this git dir -----------------
$root = (& git rev-parse --show-toplevel 2>$null)
if ($root) {
    # Load the shared substrate. If it is missing (a partial vendoring of these scripts) the
    # coordination block degrades to what git alone can answer, rather than throwing into the banner.
    $haveCommon = $false
    try {
        . (Join-Path $PSScriptRoot "../coord/_common.ps1")
        $haveCommon = $true
    } catch { $haveCommon = $false }

    $wtPaths = @()
    try {
        $porcelain = @(& git worktree list --porcelain 2>$null)
        $wtPaths = @($porcelain | Where-Object { $_ -match '^worktree\s+(.+)$' } | ForEach-Object { $Matches[1].Trim() })
    } catch { $wtPaths = @() }

    if ($wtPaths.Count -gt 1) {
        $branch = (& git branch --show-current 2>$null)
        # Primary (trunk) checkout vs a linked worktree: a linked worktree's git-dir is under
        # .git/worktrees/, the primary's is the .git directory itself.
        $gitDir = (& git rev-parse --git-dir 2>$null)
        $isPrimary = ($gitDir -notmatch 'worktrees')

        $lines += ""
        $lines += "[PARALLEL SESSION ($($wtPaths.Count) worktrees active)]"
        $lines += "This chat's worktree: $root  (branch: $branch)"

        # Loudest, first: if this session sits in the SHARED trunk, tell it to branch into its own
        # worktree. This is the collision that costs the most and is the easiest to avoid.
        if ($isPrimary) {
            $lines += ""
            $lines += "  >>> You are in the SHARED PRIMARY checkout, where parallel sessions collide."
            $lines += "  >>> Before any substantive edits, create and work in your OWN worktree:"
            $lines += "  >>>     pwsh -NoProfile -File scripts/worktree/new.ps1 -Name <short-task-name>"
            $lines += "  >>> (A trivial one-off read/edit here is fine; anything you'll iterate on gets a worktree.)"
        }

        $lines += ""
        $lines += "All worktrees sharing this git dir/history/remote:"
        $wtPaths | ForEach-Object { $lines += "  $_" }

        # WHO IS ACTUALLY HERE. The worktree list above is the set of CHECKOUTS, not the set of live
        # SESSIONS -- most worktrees usually have nobody in them, and the one collision that matters
        # (someone editing the shared primary right now) is invisible from it. presence.ps1 is the
        # only roster that spans surfaces: the harness's own session tooling cannot see a session it
        # did not spawn, so an editor-hosted session working in this repo does not appear in it.
        $presence = Join-Path $PSScriptRoot "../coord/presence.ps1"
        if (Test-Path -LiteralPath $presence) {
            $peers = @()
            # READ THE EXIT CODE, not just the rows. presence exits 2 when its roster could not be
            # completed, and hands back `[]` -- which is byte-identical to a complete roster with
            # nobody in it. Taking stdout alone, this hook found no rows, silently omitted the section
            # below, and the banner then read as "nobody else is here" on a measurement that never
            # happened. presence's receipt says so on stderr; nothing here was reading stderr.
            #
            # NOT A WEAKENING OF "never prints a guess" (see the header). A stated "the roster could
            # not be completed" is the opposite of a guess. The guess was the silence.
            $rosterIncomplete = $false
            try {
                $peers = @(& $presence -Json | ConvertFrom-Json)
                if ($LASTEXITCODE -ne 0) { $rosterIncomplete = $true }
            } catch { $peers = @(); $rosterIncomplete = $true }

            $others = @($peers | Where-Object { -not $_.IsSelf })
            if ($rosterIncomplete) {
                $lines += ""
                $lines += "LIVE sessions: THE ROSTER COULD NOT BE COMPLETED -- treat this as UNKNOWN, not as"
                $lines += "  'nobody else is here'. A session that launched a moment ago has a half-written"
                $lines += "  registry record and looks exactly like this. Check before you assume you are alone:"
                $lines += "    pwsh -NoProfile -File scripts/coord/presence.ps1"
            }
            if ($others.Count -gt 0) {
                $lines += ""
                $lines += "LIVE sessions in this repo right now ($($others.Count) besides you):"
                foreach ($p in $others) {
                    $where = if ($p.IsPrimary) { "the SHARED PRIMARY" } else { $p.Worktree }
                    $flag = if ($p.State -ne "LIVE") { "  [$($p.State)]" } else { "" }
                    $lines += "  $($p.Short)  $($p.Surface)  in $where  [$($p.Branch)]$flag"
                }
                # The surfaces differ in what can reach them, and that changes how you coordinate.
                if (@($others | Where-Object { $_.Surface -ne "desktop" }).Count -gt 0) {
                    $lines += "  NOTE: a non-desktop (e.g. editor-hosted) session is live. It cannot be reached by"
                    $lines += "        session messaging -- coordinate through a claim or the PR, not a message."
                }
                if (@($others | Where-Object { $_.IsPrimary }).Count -gt 0) {
                    $lines += "  WARNING: a session is working in the SHARED PRIMARY checkout. Anything you do"
                    $lines += "           there can collide with it -- stay in this worktree."
                }
                $lines += "  Full roster:  pwsh -NoProfile -File scripts/coord/presence.ps1 -All"
            }

            # WHAT they are building, not just where they are. The roster above stops you editing the
            # same FILE; this is the only thing that stops you building the same THING.
            #
            # Measured on the repo this was developed in: three sessions independently fixed the same
            # dependency advisory, in DIFFERENT files, so nothing file-shaped could have caught it;
            # two of the three pull requests were closed as duplicates. Sourced from each session's
            # own task list, so nobody has to declare anything by hand.
            $overlap = Join-Path $PSScriptRoot "../coord/overlap.ps1"
            if (Test-Path -LiteralPath $overlap) {
                $inflight = @()
                try { $inflight = @(& $overlap -Json | ConvertFrom-Json) } catch { $inflight = @() }
                $busy = @($inflight | Where-Object { $_.Live -and (@($_.Work).Count -gt 0 -or @($_.Files).Count -gt 0) })
                if ($busy.Count -gt 0) {
                    $lines += ""
                    $lines += "WHAT THEY ARE BUILDING -- check before you start, so you don't build it twice:"
                    foreach ($b in $busy) {
                        $lines += "  $($b.Short) [$($b.Branch)] -- $(@($b.Files).Count) file(s) changed"
                        foreach ($w in @($b.Work | Select-Object -First 3)) { $lines += "      $w" }
                    }
                    $lines += "  Everything in flight:  pwsh -NoProfile -File scripts/coord/overlap.ps1"
                }
            }
        }

        # Nudge cleanup: count the sibling worktrees new.ps1 creates, so finished ones do not pile up.
        # Counted STRUCTURALLY (same parent, `<primary-leaf>-<name>` leaf, not a harness worktree),
        # never by string prefix -- a raw prefix test also counts `<primary>-x/sub` and the harness's
        # own nested worktrees, and a cleanup nudge that names a directory nobody should remove is
        # worse than no nudge.
        if ($haveCommon) {
            try {
                $primaryRoot = Get-CcxPrimaryRoot -Repo $root
                $siblings = @($wtPaths | Where-Object { Test-CcxSiblingWorktreePath -Path $_ -PrimaryRoot $primaryRoot })
                if ($siblings.Count -ge 1) {
                    $lines += ""
                    $lines += "  [cleanup] $($siblings.Count) sibling worktree(s) exist. Prune the finished (merged + clean) ones:"
                    $lines += "       pwsh -NoProfile -File scripts/worktree/prune-merged.ps1   (dry-run; add -Apply to remove)"
                }
            } catch { }
        }

        # ACTIVE CLAIMS. The commit-time claim gate only enforces work that carries a NUMBER; this
        # banner is the whole mechanism for ad-hoc work -- and ad-hoc work is what actually collided.
        if ($haveCommon) {
            try {
                $claimDir = Join-Path (Get-CcxStateRoot -Repo $root) 'claims'
                $claimFiles = @(Get-ChildItem -LiteralPath $claimDir -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name)
                if ($claimFiles.Count -gt 0) {
                    $meNorm = ConvertTo-CcxComparablePath $root
                    $lines += ""
                    $lines += "Active work claims ($($claimFiles.Count)) -- do NOT start one held by another session:"
                    foreach ($cf in $claimFiles) {
                        try { $c = Get-Content -LiteralPath $cf.FullName -Raw | ConvertFrom-Json } catch { continue }
                        $heldNorm = ConvertTo-CcxComparablePath $c.worktree
                        $who = if ($heldNorm -and $heldNorm -eq $meNorm) { "THIS session" } else { $c.worktree }
                        $stale = ""
                        try {
                            $hrs = ((Get-Date) - [datetime]::Parse($c.claimed)).TotalHours
                            if ($hrs -ge 12) { $stale = "  [stale ~$([int]$hrs)h]" }
                        } catch { }
                        $lines += "  $($c.key) -- $($c.note)"
                        $lines += "      held by $who [$($c.branch)]$stale"
                    }
                    $lines += "  Claim yours first:  pwsh -NoProfile -File scripts/coord/claim.ps1 -Take <key> -Note `"<what>`""
                }
            } catch { }
        }

        $lines += ""
        $lines += "Coordination rules for parallel sessions (see docs/WORKTREES.md):"
        $lines += "  - Keep ALL changes on this worktree's branch ('$branch'); never edit files in a sibling worktree."
        $lines += "  - Use THIS worktree's own dependency environment, not the primary checkout's, or you will"
        $lines += "    silently build and test the wrong code."
        $lines += "  - The AI project memory directory is SHARED across every session on this machine: reads are"
        $lines += "    fine, but only ONE session should write at a time (last write wins). Do not write project"
        $lines += "    memory unless the user confirms this session owns memory updates."
    }
}

($lines -join "`n") | Write-Output
