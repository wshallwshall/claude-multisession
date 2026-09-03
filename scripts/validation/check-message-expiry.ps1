#Requires -Version 7.3
<#
.SYNOPSIS
    Receipts against deadlines. Fires when a message reached the expiry its sender set, unshown.

.DESCRIPTION
    WHAT IT SCANS. The same lane check-message-delivery.ps1 reads -- every *.json under -MailRoot,
    else <git-common-dir>/mail -- through the same reader. It prints the file count, the message
    count, the receipt count, and how many messages carried a usable deadline, on every run.

    WHAT MAKES IT FAIL. A message whose send time plus its declared ttl is in the past, with no
    receipt naming it. That is the sender's own deadline, missed.

    WHY THIS IS A SEPARATE CHECK FROM DELIVERY. Delivery asks whether the channel moves anything.
    This asks whether it moves things in time. A lane can pass the first and fail this one -- every
    message eventually rendered, all of them late -- and the two failures have different fixes: a
    dead drain against a drain that runs too rarely for the ttl its senders chose.

    A MESSAGE WITH NO TTL IS NOT A PASS. It cannot be evaluated, so it is counted as unreadable and
    the run cannot come back CLEAN over it. A lane where nobody sets a ttl produces CANNOT_TELL,
    which is the true answer: there is no deadline to have missed.

.EXAMPLE
    pwsh -NoProfile -File scripts/validation/check-message-expiry.ps1
    pwsh -NoProfile -File scripts/validation/check-message-expiry.ps1 -MailRoot .\fixtures\broken\message-expiry
#>
[CmdletBinding()]
param(
    [string]$MailRoot = '',
    [string]$Repo = '',
    # Applied only to messages that declare no ttl of their own, and only when the caller asks for
    # it. Left at 0 those messages stay unreadable, because inventing a deadline for a sender who
    # set none would manufacture findings out of a default.
    [int]$DefaultTtlMinutes = 0,
    [switch]$Json,
    [int]$MaxReport = 0
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../coord/_common.ps1"
. "$PSScriptRoot/_receipt.ps1"
. "$PSScriptRoot/_mailbox.ps1"

$r = New-CcxCheckReceipt -Check 'message-expiry' `
    -Question 'did every message get shown before the deadline its sender set?' `
    -BrokenWhen 'a message passed its send time plus its ttl with no receipt naming it'

$root = Get-CcxMailRoot -MailRoot $MailRoot -Repo $Repo
$r.Source = if ($root) { $root } else { '(no mail root could be resolved)' }

if (-not $root) {
    $r.Blocked = 'no mail root resolved: not inside a git repository, and no -MailRoot was given'
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

$lane = Read-CcxMailLane -Root $root
if (-not $lane.Exists) {
    $r.Blocked = "no mail root at $root -- the lane is built per machine (docs/SESSION-MAIL.md), so absent means not built"
    Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
}

$rendered = Get-CcxRenderedIds -Lane $lane
$now = Get-Date

$dated = 0
$noTtl = 0
foreach ($m in $lane.Messages) {
    if ($m.Error) {
        $r.Unreadable++
        Add-CcxFinding -Receipt $r -Text "unreadable message $($m.File): $($m.Error)"
        continue
    }
    $ttl = $m.TtlMinutes
    if ($null -eq $ttl -and $DefaultTtlMinutes -gt 0) { $ttl = $DefaultTtlMinutes }
    if ($null -eq $ttl -or $null -eq $m.Sent) {
        $noTtl++
        $r.Unreadable++
        continue
    }
    $dated++
    if ($rendered.Contains([string]$m.Id)) { continue }
    $expires = $m.Sent.AddMinutes([int]$ttl)
    if ($expires -lt $now) {
        $over = [int]($now - $expires).TotalMinutes
        Add-CcxFinding -Receipt $r -Text "expired unshown: id '$($m.Id)' in box '$($m.Box)', ttl $ttl min, $over minutes past expiry -- $($m.File)"
    }
}

# THE DENOMINATOR IS THE MESSAGES THAT COULD BE JUDGED, not every file on disk. Reporting the file
# count as the corpus would overstate what this check actually measured.
$r.Examined = $dated
Add-CcxCorpus -Receipt $r -Name 'json files under root' -Count $lane.FilesSeen
Add-CcxCorpus -Receipt $r -Name 'messages' -Count $lane.Messages.Count
Add-CcxCorpus -Receipt $r -Name 'receipts' -Count $lane.Receipts.Count
Add-CcxCorpus -Receipt $r -Name 'with a usable deadline' -Count $dated
Add-CcxCorpus -Receipt $r -Name 'no ttl or no send time' -Count $noTtl

if ($noTtl -gt 0 -and $DefaultTtlMinutes -le 0) {
    Add-CcxNote -Receipt $r -Text "$noTtl message(s) set no ttl; pass -DefaultTtlMinutes to judge them against one you choose"
}

Complete-CcxCheck -Receipt $r -Json:$Json -MaxReport $MaxReport
