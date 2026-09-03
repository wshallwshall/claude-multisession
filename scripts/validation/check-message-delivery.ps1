#Requires -Version 7.3
<#
.SYNOPSIS
    Messages written against messages rendered. Fires when a message was written and nobody saw it.

.DESCRIPTION
    WHAT IT SCANS. Every *.json under the mail root -- the caller's -MailRoot, else
    <git-common-dir>/mail. Files outside a `receipts` directory are messages; files inside one are
    receipts. It prints the file count, the message count, the receipt count and the box count on
    every run, clean or not.

    WHAT MAKES IT FAIL. A message older than -SettleMinutes with no receipt naming it. The settle
    window exists because a message written ten seconds ago is in flight, not lost, and a check that
    called that broken would be deleted within a day.

    WHY THE SETTLE WINDOW IS NOT A TTL. This check asks whether the channel moves anything at all.
    check-message-expiry.ps1 asks the sharper question -- did a message pass the deadline its sender
    set -- and reads the message's own ttl rather than a flag on this command line. Two thresholds,
    two questions, deliberately not merged.

    WHAT IT WILL NOT DO. It will not print CLEAN over an empty lane. No mail root, or a mail root
    holding nothing, is CANNOT_TELL: a dead channel and a quiet one write the same zero, and telling
    them apart needs a message sent on purpose. scripts/validation/README.md says how.

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/check-message-delivery.ps1
    pwsh -NoProfile -File scripts/validation/check-message-delivery.ps1 -MailRoot .\fixtures\broken\message-delivery -Json
#>
[CmdletBinding()]
param(
    # The lane to read. A fixture directory is a mail root like any other, which is why this check
    # has ONE code path: the planted corpus and the live one enter through the same reader.
    [string]$MailRoot = '',
    [string]$Repo = '',
    # How long a message may sit unrendered before it counts as undelivered rather than in flight.
    [int]$SettleMinutes = 60,
    [switch]$Json,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/_receipt.ps1"
. "$PSScriptRoot/_mailbox.ps1"

$r = New-CcxCheckReceipt -Check 'message-delivery' `
    -Question 'was every message written to the lane rendered to some session?' `
    -BrokenWhen "a message older than $SettleMinutes minutes has no receipt naming it"

$root = Get-CcxMailRoot -MailRoot $MailRoot -Repo $Repo
$r.Source = if ($root) { $root } else { '(no mail root could be resolved)' }

if (-not $root) {
    $r.Blocked = 'no mail root resolved: not inside a git repository, and no -MailRoot was given'
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

$lane = Read-CcxMailLane -Root $root
if (-not $lane.Exists) {
    # ABSENT IS NOT EMPTY. docs/SESSION-MAIL.md ships a build guide and no lane, so a missing root
    # most often means nobody built one -- which is a fact about the estate, not a clean channel.
    $r.Blocked = "no mail root at $root -- the lane is built per machine (docs/SESSION-MAIL.md), so absent means not built"
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

$rendered = Get-CcxRenderedIds -Lane $lane
$cutoff = (Get-Date).AddMinutes(-$SettleMinutes)

$r.Examined = $lane.Messages.Count
Add-CcxCorpus -Receipt $r -Name 'json files under root' -Count $lane.FilesSeen
Add-CcxCorpus -Receipt $r -Name 'messages' -Count $lane.Messages.Count
Add-CcxCorpus -Receipt $r -Name 'receipts' -Count $lane.Receipts.Count
Add-CcxCorpus -Receipt $r -Name 'boxes' -Count $lane.Boxes.Count

$undated = 0
foreach ($m in $lane.Messages) {
    if ($m.Error) {
        # Counted, never dropped. A message that will not parse is exactly where an undelivered one
        # would hide, and dropping it shrinks the denominator while the verdict stays green.
        $r.Unreadable++
        Add-CcxFinding -Receipt $r -Text "unreadable message $($m.File): $($m.Error)"
        continue
    }
    if ($rendered.Contains([string]$m.Id)) { continue }
    if ($null -eq $m.Sent) {
        # No timestamp means the settle window cannot be applied. That is a gap in the census, not a
        # pass: it goes to Unreadable so the run cannot come back CLEAN over it.
        $undated++
        $r.Unreadable++
        continue
    }
    if ($m.Sent -lt $cutoff) {
        $age = [int]((Get-Date) - $m.Sent).TotalMinutes
        Add-CcxFinding -Receipt $r -Text "written and never rendered: id '$($m.Id)' in box '$($m.Box)', $age minutes old -- $($m.File)"
    }
}

if ($undated -gt 0) {
    Add-CcxNote -Receipt $r -Text "$undated unrendered message(s) carry no send timestamp, so their age could not be measured"
}
if ($lane.Messages.Count -gt 0 -and $lane.Receipts.Count -eq 0) {
    # The shape a dead drain makes: senders writing, nothing on the other end. Said out loud rather
    # than left to be inferred from two numbers in the corpus block.
    Add-CcxNote -Receipt $r -Text 'no receipts anywhere in this lane -- either no drain has run, or the drain writes none'
}

Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
