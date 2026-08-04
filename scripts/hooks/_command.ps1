#Requires -Version 7.3
<#
.SYNOPSIS
    Shared command splitter: turn one tool-call command string into the SIMPLE COMMANDS a rule may
    judge on their own.

.DESCRIPTION
    Dot-source this. Every gate that reasons about a shell command needs the same three things and
    used to reimplement them:

        Raw     the simple command exactly as written -- parse PATHS out of this
        Scan    the same command with inert quoted spans blanked -- decide VERBS from this
        Prefix  everything that ran before it on the same logical line -- resolve `cd` from this

    WHY BOTH FORMS. Deciding a verb from the raw string produces false positives that train people to
    route around the gate: a two-line command whose second line reads `echo about to merge stuff`
    denied on `merge`; `echo "git checkout main"` denied; `git commit -m "clean up dead code"` denied
    on `clean`. Blanking quoted spans fixes all three. But parsing a PATH out of the blanked string
    fails, because the same blanking erases the path. So both forms travel together and each rule uses
    the right one.

.NOTES
    RECONCILIATION. Two gates shipped two different splitters, and they were not merely different --
    one was strictly weaker in four ways. Where they disagreed this file takes the safer side:

      1. SEPARATORS. The blanket-stage guard split on `&&`, `||`, `;`, `|`, `&` and newlines with a
         plain regex; the worktree gate split on NEWLINES only and then tried to stay inside one
         command with a `[^|;&]*?` fragment inside each rule's own regex. Kept: separator splitting --
         but done by a QUOTE-AWARE walker, not a regex, so `git commit -m "a; b"` is not cut in half.
         The in-regex containment fragment is then unnecessary, which removes a thing every future
         rule would have had to remember.

      2. QUOTING. The blanket-stage guard did not blank quoted spans at all, so `echo "git add -A"`
         was a deny. Kept: blanking, with the raw form preserved alongside.

      3. INTERPRETER ARGUMENTS. The blanket-stage guard did not look inside `pwsh -Command "..."` /
         `bash -c "..."` / `cmd /c "..."`, so the same command spelled through an interpreter walked
         past it. Kept: one level of recursion. Note the interaction with (2) -- an interpreter's
         argument is quoted, but it is CODE THAT RUNS, so it must be recursed into rather than
         blanked. Blanking it turned a long-standing deny into an allow when that was tried.

      4. GIT DETECTION. The blanket-stage guard required the segment to START with a bare `git` token,
         so `/usr/bin/git add -A`, `"C:\Program Files\Git\bin\git.exe" add -A` and `& git add -A` all
         slipped past. Kept: the worktree gate's tolerant git-token test, exposed here as
         Test-CcxGitInvocation so the two gates cannot drift apart again.

    ONE THING THIS IS NOT. It is not a shell parser and must not grow into one. Any agent-authored
    script defeats a command-string gate outright -- `pwsh -File whatever.ps1` carries no verb to
    match. These rules are a guardrail against the accidental command, not a security boundary, and a
    more elaborate parser would only make that boundary look firmer than it is.
#>

function Test-CcxGitInvocation {
    <#
    .SYNOPSIS
        Does this segment invoke git? Case-SENSITIVE on the program name.
    .DESCRIPTION
        Matches `git`, `git.exe`, an absolute or relative path to either, and a quoted program path.
        Anchored on a token boundary rather than the start of the string, because a real invocation is
        routinely preceded by `&` (PowerShell's call operator), `env VAR=1`, or `sudo`.

        Pass the SCAN form. On the raw form, a commit message mentioning git would match.
    #>
    [CmdletBinding()]
    param([string]$Segment)
    if (-not $Segment) { return $false }
    return ($Segment -cmatch '(^|[\s;&|(''"\\/])git(\.exe)?["'']?(\s|$)')
}

function Get-CcxGitTokenIndex {
    <#
    .SYNOPSIS
        Character offset of the git invocation within a segment, or -1.
    .DESCRIPTION
        Callers use this to split a segment into "what ran before git on this line" (which is where a
        `cd` is honoured from) and the git command itself. Run it on the RAW form, because the offset
        has to index the raw string.
    #>
    [CmdletBinding()]
    param([string]$Segment)
    if (-not $Segment) { return -1 }
    $m = [regex]::Match($Segment, '(^|[\s;&|(''"\\/])git(\.exe)?["'']?(\s|$)')
    if (-not $m.Success) { return -1 }
    return $m.Index
}

function ConvertTo-CcxScannable {
    <#
    .SYNOPSIS
        Blank the inert quoted spans of one command, leaving structure and unquoted tokens intact.
    .DESCRIPTION
        A quoted PROGRAM path keeps its git token first: `"C:\Program Files\Git\bin\git.exe" checkout
        main` is a real spelling, and blanking it wholesale would be a false NEGATIVE on the exact
        command the gate exists to catch. Collapse that form to a bare token, then blank the rest.
    #>
    [CmdletBinding()]
    param([string]$Command)
    if (-not $Command) { return '' }
    $s = $Command -replace '"[^"]*[\\/](git(?:\.exe)?)"', '$1'
    $s = $s -replace "'[^']*[\\/](git(?:\.exe)?)'", '$1'
    $s = $s -replace '"[^"]*"', '""'
    $s = $s -replace "'[^']*'", "''"
    return $s
}

function Split-CcxCommand {
    <#
    .SYNOPSIS
        Split a tool-call command string into judgeable simple commands.
    .OUTPUTS
        PSCustomObject[] with Raw, Scan, Prefix, Depth, Line.

        Raw     the simple command's own text, trimmed
        Scan    Raw with inert quoted spans blanked (see ConvertTo-CcxScannable)
        Prefix  the RAW text of everything earlier on the same logical line, including the separators.
                A rule that honours `cd` reads it from here and from the part of Raw before the git
                token -- never from the whole command, which made the old resolver ORDER-BLIND:
                `git checkout main && cd ../elsewhere` resolved to `../elsewhere` and allowed a swap
                of the tree the git call had already acted on.
        Depth   0 for a top-level command, 1 for one recursed out of an interpreter argument
        Line    0-based index of the logical line it came from

        Empty segments are dropped. A command that is entirely whitespace yields nothing, which every
        caller reads as "no rule fires" -- correct, and not the same as an error.
    #>
    [CmdletBinding()]
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return @() }

    # Fold line continuations FIRST. Otherwise the per-line split separates `git \` from its verb and
    # the rule stops seeing the command at all. Prose does not end a line with a continuation
    # character, so this does not resurrect the `echo about to merge stuff` false positive.
    $folded = $Command -replace '\\\r?\n[ \t]*', ' '
    $folded = $folded -replace '`\r?\n[ \t]*', ' '

    $results = [System.Collections.Generic.List[object]]::new()
    $lines = @($folded -split '\r?\n')

    for ($li = 0; $li -lt $lines.Count; $li++) {
        foreach ($seg in (Split-CcxSimpleCommand -Line $lines[$li])) {
            $raw = $seg.Text.Trim()
            if (-not $raw) { continue }

            $results.Add([pscustomobject]@{
                    Raw    = $raw
                    Scan   = (ConvertTo-CcxScannable $raw)
                    Prefix = $seg.Prefix
                    Depth  = 0
                    Line   = $li
                })

            # ONE LEVEL of interpreter recursion, and one level only. Two levels buys nothing a
            # determined caller cannot spell around, and the failure mode of a deeper walk -- time
            # spent on every single prompt -- is paid by every user on every tool call.
            foreach ($innerText in (Get-CcxInterpreterArgument -Command $raw)) {
                foreach ($innerSeg in (Split-CcxSimpleCommand -Line $innerText)) {
                    $innerRaw = $innerSeg.Text.Trim()
                    if (-not $innerRaw) { continue }
                    $results.Add([pscustomobject]@{
                            Raw  = $innerRaw
                            Scan = (ConvertTo-CcxScannable $innerRaw)
                            # The inner command inherits the OUTER prefix, plus its own. A `cd` that
                            # ran before the interpreter still governs where the inner command lands,
                            # and inheriting it resolves ambiguous cases toward the governed tree --
                            # the deny side, which is the side to fail toward for a guardrail.
                            Prefix = ($seg.Prefix + $innerSeg.Prefix)
                            Depth  = 1
                            Line   = $li
                        })
                }
            }
        }
    }

    return $results.ToArray()
}

function Split-CcxSimpleCommand {
    <#
    .SYNOPSIS
        Quote-aware split of ONE logical line at its unquoted command separators.
    .DESCRIPTION
        Separators: `&&`, `||`, `;`, `|`, and a bare `&`.

        A bare `&` is included because in a POSIX shell it backgrounds a command, so `git checkout
        main & ...` really is two commands. It costs something: in PowerShell `&` is the call operator
        and `2>&1` is a redirection, so both split where no split is needed. Both are harmless here --
        the verb and its git token stay together in one piece and the leading empty piece is dropped --
        and the alternative, guessing which shell the harness will use, is worse.

        Quote tracking is deliberately simple: single and double quotes toggle, and a backslash
        escapes the next character only inside double quotes. It does not model here-strings, `$( )`,
        or backticks. It does not need to: an unbalanced quote leaves the walker "inside" a string to
        end of line, which yields ONE segment instead of several -- fewer splits, so no rule loses a
        verb it would otherwise have matched.
    #>
    [CmdletBinding()]
    param([string]$Line)

    $out = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Line) { return $out.ToArray() }

    $start = 0
    $inSingle = $false
    $inDouble = $false
    $i = 0

    while ($i -lt $Line.Length) {
        $c = $Line[$i]

        if ($inSingle) {
            if ($c -eq "'") { $inSingle = $false }
            $i++
            continue
        }
        if ($inDouble) {
            if ($c -eq '\' -and $i + 1 -lt $Line.Length) { $i += 2; continue }
            if ($c -eq '"') { $inDouble = $false }
            $i++
            continue
        }
        if ($c -eq "'") { $inSingle = $true; $i++; continue }
        if ($c -eq '"') { $inDouble = $true; $i++; continue }

        $sepLen = 0
        if (($c -eq '&' -or $c -eq '|') -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq $c) {
            $sepLen = 2                       # && or ||
        } elseif ($c -eq ';' -or $c -eq '|' -or $c -eq '&') {
            $sepLen = 1
        }

        if ($sepLen -gt 0) {
            $out.Add([pscustomobject]@{
                    Text   = $Line.Substring($start, $i - $start)
                    Prefix = $Line.Substring(0, $start)
                })
            $i += $sepLen
            $start = $i
            continue
        }
        $i++
    }

    $out.Add([pscustomobject]@{
            Text   = $Line.Substring($start)
            Prefix = $Line.Substring(0, $start)
        })
    return $out.ToArray()
}

function Get-CcxInterpreterArgument {
    <#
    .SYNOPSIS
        Extract the quoted argument of an inline-code flag: -c / -lc / -ec / -Command / -EncodedCommand
        / /c / /k.
    .DESCRIPTION
        Returns the argument TEXT, to be judged as a command in its own right.

        `-EncodedCommand` is matched but its argument is base64, so what comes back is not a command
        and no rule will match it. That is stated rather than silently accepted: a gate that reasons
        about command strings cannot see through an encoded one, and pretending otherwise is the
        "enumerated coverage means silent holes" failure. A caller that cares should treat an
        -EncodedCommand invocation as unanalysable rather than as clean.
    #>
    [CmdletBinding()]
    param([string]$Command)

    $found = [System.Collections.Generic.List[string]]::new()
    if (-not $Command) { return $found.ToArray() }

    foreach ($pat in @(
            '(?:^|\s)(?:-c|-lc|-ec|-Command|-EncodedCommand)\s+"([^"]*)"',
            "(?:^|\s)(?:-c|-lc|-ec|-Command|-EncodedCommand)\s+'([^']*)'",
            '(?:^|\s)/[ckCK]\s+"([^"]*)"',
            "(?:^|\s)/[ckCK]\s+'([^']*)'"
        )) {
        foreach ($m in [regex]::Matches($Command, $pat)) {
            if ($m.Groups[1].Value) { $found.Add($m.Groups[1].Value) }
        }
    }
    return $found.ToArray()
}
