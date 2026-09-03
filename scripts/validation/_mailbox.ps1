#Requires -Version 7.3
<#
.SYNOPSIS
    Read a session-mail lane without owning its schema, and say plainly when there is no lane.

.DESCRIPTION
    Dot-source this alongside _receipt.ps1.

    THE LANE IS NOT SHIPPED. docs/SESSION-MAIL.md is a build guide, so the mailbox on any given
    machine was built by its owner and this reader cannot assume field names. It accepts several
    spellings per field and reports what it could not place rather than dropping it.

    THE DISTINCTION THIS FILE EXISTS FOR, and it is the whole reason the issue behind this directory
    was filed: an absent lane, an empty lane and a dead lane are three different states that print
    the same "no messages" line. Here they are three different answers:

        no mail root on disk        -> Blocked. Nothing was examined. CANNOT_TELL.
        a mail root with no files   -> Examined 0. CANNOT_TELL.
        files present               -> examined, and a verdict is possible.

    WHAT IT CANNOT SEE, stated because a blind spot nobody names becomes a coverage claim. A drain
    that renders a message and then DELETES both the message and its receipt leaves nothing behind,
    so that message is invisible to every count here. Delivery is provable only where the drain
    leaves a receipt; docs/SESSION-MAIL.md asks for exactly that, and this reader is why it matters.

    MINIMUM CONTRACT. A message is a *.json file under the mail root, outside a `receipts`
    directory. A receipt is a *.json file inside one. A receipt names its message with `id`,
    `messageId` or `message`; a message names itself with `id` or falls back to its filename stem.
#>

# No Set-StrictMode -- see _receipt.ps1 for why a dot-sourced helper here must not set it.

function Get-CcxMailRoot {
    <#
    .SYNOPSIS
        The lane's root: the caller's -MailRoot, else <git-common-dir>/mail.
    #>
    [CmdletBinding()]
    param([string]$MailRoot = '', [string]$Repo = '')
    if ($MailRoot) { return $MailRoot }
    $common = ''
    try { $common = Get-CcxGitCommonDir -Repo $Repo } catch { $common = '' }
    if (-not $common) { return '' }
    return (Join-Path $common 'mail')
}

function Read-CcxMailLane {
    <#
    .SYNOPSIS
        Every message and every receipt under a mail root, with the files that would not parse.

    .OUTPUTS
        Messages     one row per message file: Id, File, Box, Sent [datetime], TtlMinutes, Error
        Receipts     one row per receipt file: Id, File, Box, Rendered [datetime], Error
        Boxes        directories that held at least one message or receipt
        FilesSeen    every *.json under the root, however it parsed -- the census denominator
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $messages = [System.Collections.Generic.List[object]]::new()
    $receipts = [System.Collections.Generic.List[object]]::new()
    $boxes = [System.Collections.Generic.HashSet[string]]::new()
    $seen = 0

    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ Messages = $messages; Receipts = $receipts; Boxes = @(); FilesSeen = 0; Exists = $false }
    }

    # -Recurse and NO depth cap: a lane is whatever shape its owner built, and a fixed depth would
    # silently stop counting one directory level down from wherever the owner nested it.
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue)) {
        $seen++
        $rec = $null
        $err = ''
        try { $rec = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $err = $_.Exception.Message }
        if ($null -eq $rec -and -not $err) { $err = 'parsed to nothing (empty, or being written right now)' }

        $parent = Split-Path -Path $f.FullName -Parent
        $isReceipt = (Split-Path -Path $parent -Leaf) -ieq 'receipts'
        $box = if ($isReceipt) { Split-Path -Path (Split-Path -Path $parent -Parent) -Leaf } else { Split-Path -Path $parent -Leaf }
        [void]$boxes.Add($box)

        if ($isReceipt) {
            $receipts.Add([pscustomobject]@{
                    Id       = [string](Get-CcxField -Record $rec -Name @('id', 'messageId', 'message'))
                    File     = $f.FullName
                    Box      = $box
                    Rendered = ConvertTo-CcxTime (Get-CcxField -Record $rec -Name @('renderedAt', 'shownAt', 'deliveredAt', 'at', 'stamp'))
                    Error    = $err
                })
            continue
        }

        $id = [string](Get-CcxField -Record $rec -Name @('id', 'messageId'))
        if (-not $id) { $id = [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
        $ttlRaw = Get-CcxField -Record $rec -Name @('ttlMinutes', 'ttlMin', 'ttl')
        $ttl = $null
        if ("$ttlRaw" -match '^\d+$') { $ttl = [int]"$ttlRaw" }
        $messages.Add([pscustomobject]@{
                Id         = $id
                File       = $f.FullName
                Box        = $box
                Sent       = ConvertTo-CcxTime (Get-CcxField -Record $rec -Name @('sentAt', 'queuedAt', 'writtenAt', 'at', 'stamp'))
                TtlMinutes = $ttl
                Error      = $err
            })
    }

    return [pscustomobject]@{
        Messages  = $messages
        Receipts  = $receipts
        Boxes     = @($boxes)
        FilesSeen = $seen
        Exists    = $true
    }
}

function Get-CcxRenderedIds {
    <#
    .SYNOPSIS
        The set of message ids some drain wrote a receipt for.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Lane)
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Lane.Receipts) { if ($r.Id) { [void]$set.Add([string]$r.Id) } }
    # THE COMMA IS LOAD-BEARING. `return $set` hands the pipeline an enumerable, and PowerShell
    # unrolls it, so this function returned three different types by receipt count -- measured:
    # 0 receipts -> $null, 1 -> [string], 2+ -> [object[]]. Callers do $rendered.Contains($id), so
    # each type answered a different question:
    #
    #   0 receipts  the call throws on a null. That is the DEAD DRAIN, the case the signal exists
    #               for, and it rendered as `message-delivery BROKEN` with no receipt and no
    #               finding -- a crash reported as a measurement.
    #   1 receipt   [string].Contains is SUBSTRING matching. A receipt for 'note-12' marked
    #               'note-1' delivered, and the run came back CLEAN with a healthy corpus beside it.
    #   2+          [object[]] falls back to IList.Contains, which is ordinal, so the
    #               case-insensitive comparer this set was built with stopped applying: a receipt
    #               naming 'msg-a' no longer matched a message 'MSG-A'.
    #
    # Every message fixture holds exactly one receipt, which is the single branch where substring
    # matching happens to give the right answer, so nothing went red.
    return ,$set
}
