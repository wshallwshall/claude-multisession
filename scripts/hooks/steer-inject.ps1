# PreToolUse hook: deliver a queued steering note mid-task.
#
# POSTURE: FAILS OPEN. Any error here exits 0 and must never block a tool call.
#
# Workaround for the absence of any supported way to reach a session between tool calls: a message
# typed at the prompt is queued for AFTER the current turn ends, which can be a long time and a lot
# of wasted work away. If a note is waiting at <project>\.claude\steer.txt -- dropped there by
# bin/ccx-steer.ps1 from a second terminal -- it is read, deleted, and re-emitted as
# `additionalContext`, so the session sees it at the next tool-call boundary rather than at the end
# of the turn.
#
# OPT-IN, and deliberately not registered in the shared .claude/settings.json: a PreToolUse hook on
# `*` costs a pwsh process spawn before EVERY tool call (measured ~366ms on the machine this was
# developed on, of which ~267ms is bare pwsh startup and unavoidable). That is a standing tax on
# every session in every worktree, which is a bad trade for an occasional-use feature. Enable it per
# worktree, in that worktree's .claude/settings.local.json, when you actually want it. See
# docs/STEERING.md.
#
# ASCII-only on purpose (the note is written by another process and must not depend on console
# encoding); run under pwsh 7 by the hook.

$ErrorActionPreference = 'SilentlyContinue'

try {
    if (-not $env:CLAUDE_PROJECT_DIR) { exit 0 }

    $noteFile = Join-Path $env:CLAUDE_PROJECT_DIR ".claude\steer.txt"
    if (-not (Test-Path -LiteralPath $noteFile)) { exit 0 }

    $note = Get-Content -LiteralPath $noteFile -Raw
    Remove-Item -LiteralPath $noteFile -Force

    if ([string]::IsNullOrWhiteSpace($note)) { exit 0 }
    $note = $note.Trim()

    $context = "[STEERING NOTE -- the user just typed this via a side channel while you were mid-task, not through the normal prompt queue. Read it now and act on it right away -- adjust your current work accordingly before or alongside your next step. Do not wait for the current turn to end.]: $note"

    $payload = [pscustomobject]@{
        hookSpecificOutput = [pscustomobject]@{
            hookEventName     = 'PreToolUse'
            additionalContext = $context
        }
    }
    [Console]::Out.Write(($payload | ConvertTo-Json -Compress -Depth 6))
} catch {
    exit 0
}
exit 0
