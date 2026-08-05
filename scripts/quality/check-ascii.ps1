#Requires -Version 7.3
<#
.SYNOPSIS
    Refuse any character in this tree that is not ASCII, name it precisely, and offer the ASCII
    text that replaces it.

.DESCRIPTION
    THE PROBLEM THIS EXISTS FOR. A non-ASCII character is invisible at review time and expensive at
    run time. Every item below was paid for while building this repository:

      * A character inside a string a script PRINTS raises `UnicodeEncodeError: 'charmap' codec
        can't encode characters` on a cp1252 console -- which is the Windows default this tooling
        targets. The failure is in the reporting path, so the tool dies while telling you something.
      * A scanner's own diagnostic output was seen rendering as replacement characters mid-sentence,
        which makes the finding unreadable at exactly the moment it matters.
      * Reading a file without an explicit `encoding=` raises on one host and silently substitutes
        replacement characters on another. The same code then "works" differently per machine, and
        the machine that substitutes is the one that loses data quietly.
      * Emoji and box-drawing characters are not one column wide, so any fixed-width table, receipt
        or aligned report built with them stops lining up -- and terminals, diff viewers and pagers
        disagree with each other about the width, so there is no single correct alignment to target.
      * A stray character can enter a file from a PROMPT and survive review, because it is visually
        indistinguishable from its ASCII neighbour. One did, in this build.

    THE RULE IS ASCII-ONLY WITH NO EXCEPTIONS, precisely because every version of the rule that has
    an exception in it requires a judgment call at the moment someone is least likely to make one
    carefully. "Only in Markdown", "only in comments", "only where it renders" are all rules that
    have to be re-decided per character, by a tired reader, against a character they cannot see.

    THIS SCRIPT NEVER PRINTS THE OFFENDING CHARACTER. It prints `U+XXXX` and a name. Echoing the
    character would reintroduce the exact cp1252 failure the check exists to prevent -- a scanner
    that dies while reporting a violation reports nothing.

    NAMES ARE CURATED, NOT LOOKED UP. .NET exposes no Unicode name database, so this file carries a
    table of the characters that actually turn up in this kind of work. Anything outside that table
    is reported by its Unicode BLOCK and general category, and labelled as such -- a name is never
    guessed.

    WHAT IT SCANNED IS ALWAYS PRINTED -- file count and byte count -- and a run that scanned nothing
    exits 2 rather than 0, because the whole failure mode here is a green result that measured
    nothing. A skip must never read as a pass.

.PARAMETER Path
    Files or directories to scan. Defaults to the repository root this script lives in. A directory
    is walked recursively with the skip list below pruned at the directory level.

.PARAMETER Fix
    Rewrite the safe substitutions in place and report every change. The safe set is the dash family
    (em/en/figure/non-breaking hyphen, minus sign), arrows, the ellipsis, curly quotes, spaces
    (non-breaking, thin, ideographic and the zero-width family, which are deleted), the bullet, the
    multiplication sign and the section sign. Everything else -- accented letters, emoji, box
    drawing, symbols -- is REPORTED WITH A SUGGESTION and never rewritten, because replacing it
    changes meaning and that is a decision for a person.

.PARAMETER ExcludeDir
    Extra directory names to prune, added to the built-in list.

.PARAMETER MaxReport
    Cap the violation lines printed (0 = no cap). The TOTAL is always printed, capped or not.

.PARAMETER Json
    Emit a machine-readable report on stdout and nothing else.

.OUTPUTS
    Exit 0  every file scanned was pure ASCII (or, under -Fix, is now).
    Exit 1  at least one non-ASCII character survives.
    Exit 2  nothing was scanned, or a file could not be read or decoded. Nothing was proven either
            way, so this is a failure and not a pass.

.EXAMPLE
    pwsh -NoProfile -File scripts/quality/check-ascii.ps1
    pwsh -NoProfile -File scripts/quality/check-ascii.ps1 -Fix
    pwsh -NoProfile -File scripts/quality/check-ascii.ps1 -Path docs -MaxReport 0
    pwsh -NoProfile -File scripts/quality/check-ascii.ps1 -Json
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$Fix,
    [string[]]$ExcludeDir = @(),
    [int]$MaxReport = 200,
    [switch]$Json
)

# NOT 'Stop' at the top level. A file that cannot be read is a RESULT this script reports, not an
# unhandled terminating error that prints a stack trace where a verdict belongs. Every risky call is
# guarded individually.
$ErrorActionPreference = 'Continue'

$CheckerVersion = 1

# ==================================================================================================
# Output plumbing
#
# ASCII-ONLY BY CONSTRUCTION, and that is not a stylistic choice here: this script is the one thing
# in the repository guaranteed to run on a console that cannot represent the characters it hunts.
# ==================================================================================================

$script:Lines = [System.Collections.Generic.List[string]]::new()
function Say {
    param([string]$Text = '')
    $script:Lines.Add($Text)
    if (-not $Json) { [Console]::Out.WriteLine($Text) }
}

# ==================================================================================================
# The character table
#
# Entries are code points, never literal characters -- a table of literals would make this file fail
# its own check. Ascii = the replacement suggested; '' means "delete it"; $null means "there is no
# safe replacement, rewrite the line". Fixable marks the subset -Fix will actually rewrite.
# ==================================================================================================

$script:Named = @{}
function Add-Named {
    # $Ascii is [object], NOT [string], on purpose: a [string] parameter converts $null to the empty
    # string during binding, which would silently turn "there is no safe replacement" into "delete
    # it" -- a wrong instruction, printed confidently, for the characters where it matters most.
    param([int]$Code, [string]$Name, [AllowNull()][object]$Ascii, [bool]$Fixable)
    $script:Named[$Code] = [pscustomobject]@{ Name = $Name; Ascii = $Ascii; Fixable = $Fixable }
}

# --- spaces and invisibles. Deleted or flattened to a plain space; all fixable, because none of them
# --- carries meaning a reader can see, which is exactly why they survive review.
Add-Named 0x00A0 'NO-BREAK SPACE' ' ' $true
Add-Named 0x2002 'EN SPACE' ' ' $true
Add-Named 0x2003 'EM SPACE' ' ' $true
Add-Named 0x2007 'FIGURE SPACE' ' ' $true
Add-Named 0x2008 'PUNCTUATION SPACE' ' ' $true
Add-Named 0x2009 'THIN SPACE' ' ' $true
Add-Named 0x200A 'HAIR SPACE' ' ' $true
Add-Named 0x202F 'NARROW NO-BREAK SPACE' ' ' $true
Add-Named 0x3000 'IDEOGRAPHIC SPACE' ' ' $true
Add-Named 0x200B 'ZERO WIDTH SPACE' '' $true
Add-Named 0x200C 'ZERO WIDTH NON-JOINER' '' $true
Add-Named 0x200D 'ZERO WIDTH JOINER' '' $true
Add-Named 0x2060 'WORD JOINER' '' $true
Add-Named 0x00AD 'SOFT HYPHEN' '' $true
Add-Named 0xFEFF 'ZERO WIDTH NO-BREAK SPACE (BYTE ORDER MARK)' '' $true

# --- the dash family. The single most common offender in prose written by a model.
Add-Named 0x2010 'HYPHEN' '-' $true
Add-Named 0x2011 'NON-BREAKING HYPHEN' '-' $true
Add-Named 0x2012 'FIGURE DASH' '-' $true
Add-Named 0x2013 'EN DASH' '-' $true
Add-Named 0x2014 'EM DASH' '--' $true
Add-Named 0x2015 'HORIZONTAL BAR' '--' $true
Add-Named 0x2212 'MINUS SIGN' '-' $true

# --- quotation marks
Add-Named 0x2018 'LEFT SINGLE QUOTATION MARK' "'" $true
Add-Named 0x2019 'RIGHT SINGLE QUOTATION MARK' "'" $true
Add-Named 0x201A 'SINGLE LOW-9 QUOTATION MARK' "'" $true
Add-Named 0x201B 'SINGLE HIGH-REVERSED-9 QUOTATION MARK' "'" $true
Add-Named 0x201C 'LEFT DOUBLE QUOTATION MARK' '"' $true
Add-Named 0x201D 'RIGHT DOUBLE QUOTATION MARK' '"' $true
Add-Named 0x201E 'DOUBLE LOW-9 QUOTATION MARK' '"' $true
Add-Named 0x201F 'DOUBLE HIGH-REVERSED-9 QUOTATION MARK' '"' $true
Add-Named 0x2032 'PRIME' "'" $false
Add-Named 0x2033 'DOUBLE PRIME' '"' $false
Add-Named 0x00AB 'LEFT-POINTING DOUBLE ANGLE QUOTATION MARK' '"' $false
Add-Named 0x00BB 'RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK' '"' $false

# --- ellipsis and bullets
Add-Named 0x2026 'HORIZONTAL ELLIPSIS' '...' $true
Add-Named 0x2022 'BULLET' '*' $true
Add-Named 0x2023 'TRIANGULAR BULLET' '*' $false
Add-Named 0x2043 'HYPHEN BULLET' '-' $false
Add-Named 0x00B7 'MIDDLE DOT' '*' $false
Add-Named 0x25CF 'BLACK CIRCLE' '*' $false
Add-Named 0x25CB 'WHITE CIRCLE' 'o' $false

# --- arrows
Add-Named 0x2190 'LEFTWARDS ARROW' '<-' $true
Add-Named 0x2192 'RIGHTWARDS ARROW' '->' $true
Add-Named 0x2194 'LEFT RIGHT ARROW' '<->' $true
Add-Named 0x21D0 'LEFTWARDS DOUBLE ARROW' '<=' $true
Add-Named 0x21D2 'RIGHTWARDS DOUBLE ARROW' '=>' $true
Add-Named 0x21D4 'LEFT RIGHT DOUBLE ARROW' '<=>' $true
Add-Named 0x27F5 'LONG LEFTWARDS ARROW' '<-' $true
Add-Named 0x27F6 'LONG RIGHTWARDS ARROW' '->' $true
Add-Named 0x2191 'UPWARDS ARROW' '^' $false
Add-Named 0x2193 'DOWNWARDS ARROW' 'v' $false

# --- symbols. Only the section sign and the multiplication sign are rewritten; the rest change
# --- meaning when substituted, so they are reported and left alone.
Add-Named 0x00D7 'MULTIPLICATION SIGN' 'x' $true
Add-Named 0x00A7 'SECTION SIGN' 'Section' $true
Add-Named 0x00F7 'DIVISION SIGN' '/' $false
Add-Named 0x00B6 'PILCROW SIGN' 'Para.' $false
Add-Named 0x00A9 'COPYRIGHT SIGN' '(c)' $false
Add-Named 0x00AE 'REGISTERED SIGN' '(R)' $false
Add-Named 0x2122 'TRADE MARK SIGN' '(TM)' $false
Add-Named 0x00B0 'DEGREE SIGN' 'deg' $false
Add-Named 0x00B1 'PLUS-MINUS SIGN' '+/-' $false
Add-Named 0x00BC 'VULGAR FRACTION ONE QUARTER' '1/4' $false
Add-Named 0x00BD 'VULGAR FRACTION ONE HALF' '1/2' $false
Add-Named 0x00BE 'VULGAR FRACTION THREE QUARTERS' '3/4' $false
Add-Named 0x2260 'NOT EQUAL TO' '!=' $false
Add-Named 0x2264 'LESS-THAN OR EQUAL TO' '<=' $false
Add-Named 0x2265 'GREATER-THAN OR EQUAL TO' '>=' $false
Add-Named 0x2248 'ALMOST EQUAL TO' '~=' $false
Add-Named 0x2713 'CHECK MARK' 'OK' $false
Add-Named 0x2714 'HEAVY CHECK MARK' 'OK' $false
Add-Named 0x2717 'BALLOT X' 'FAIL' $false
Add-Named 0x2718 'HEAVY BALLOT X' 'FAIL' $false
Add-Named 0x2705 'WHITE HEAVY CHECK MARK' 'OK' $false
Add-Named 0x274C 'CROSS MARK' 'FAIL' $false
Add-Named 0x26A0 'WARNING SIGN' 'WARNING' $false
Add-Named 0x2605 'BLACK STAR' '*' $false
Add-Named 0x2606 'WHITE STAR' '*' $false

# --- line and paragraph separators. No safe rewrite: substituting a real newline changes the line
# --- count, and every line number in every other report about this file with it.
Add-Named 0x2028 'LINE SEPARATOR' $null $false
Add-Named 0x2029 'PARAGRAPH SEPARATOR' $null $false

# --- box drawing and blocks. Named individually because they are what "the table stopped lining up"
# --- actually looks like in a diff.
Add-Named 0x2500 'BOX DRAWINGS LIGHT HORIZONTAL' '-' $false
Add-Named 0x2502 'BOX DRAWINGS LIGHT VERTICAL' '|' $false
Add-Named 0x250C 'BOX DRAWINGS LIGHT DOWN AND RIGHT' '+' $false
Add-Named 0x2510 'BOX DRAWINGS LIGHT DOWN AND LEFT' '+' $false
Add-Named 0x2514 'BOX DRAWINGS LIGHT UP AND RIGHT' '+' $false
Add-Named 0x2518 'BOX DRAWINGS LIGHT UP AND LEFT' '+' $false
Add-Named 0x251C 'BOX DRAWINGS LIGHT VERTICAL AND RIGHT' '+' $false
Add-Named 0x2524 'BOX DRAWINGS LIGHT VERTICAL AND LEFT' '+' $false
Add-Named 0x252C 'BOX DRAWINGS LIGHT DOWN AND HORIZONTAL' '+' $false
Add-Named 0x2534 'BOX DRAWINGS LIGHT UP AND HORIZONTAL' '+' $false
Add-Named 0x253C 'BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL' '+' $false
Add-Named 0x2550 'BOX DRAWINGS DOUBLE HORIZONTAL' '=' $false
Add-Named 0x2551 'BOX DRAWINGS DOUBLE VERTICAL' '|' $false
Add-Named 0x2588 'FULL BLOCK' '#' $false
Add-Named 0x2591 'LIGHT SHADE' '.' $false
Add-Named 0x2592 'MEDIUM SHADE' ':' $false
Add-Named 0x2593 'DARK SHADE' '#' $false

# Blocks, for anything the table above does not name. Reported AS a block, never dressed up as a
# character name, so the report cannot claim knowledge it does not have.
$script:Blocks = @(
    [pscustomobject]@{ Lo = 0x0080; Hi = 0x009F; Name = 'C1 controls'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x00A0; Hi = 0x00FF; Name = 'Latin-1 Supplement'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x0100; Hi = 0x024F; Name = 'Latin Extended'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x0370; Hi = 0x03FF; Name = 'Greek and Coptic'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x0400; Hi = 0x04FF; Name = 'Cyrillic'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x0590; Hi = 0x05FF; Name = 'Hebrew'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x0600; Hi = 0x06FF; Name = 'Arabic'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2000; Hi = 0x206F; Name = 'General Punctuation'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2070; Hi = 0x209F; Name = 'Superscripts and Subscripts'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x20A0; Hi = 0x20CF; Name = 'Currency Symbols'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2100; Hi = 0x214F; Name = 'Letterlike Symbols'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2150; Hi = 0x218F; Name = 'Number Forms'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2190; Hi = 0x21FF; Name = 'Arrows'; Ascii = '->' }
    [pscustomobject]@{ Lo = 0x2200; Hi = 0x22FF; Name = 'Mathematical Operators'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2300; Hi = 0x23FF; Name = 'Miscellaneous Technical'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2500; Hi = 0x257F; Name = 'Box Drawing'; Ascii = '-, | and +' }
    [pscustomobject]@{ Lo = 0x2580; Hi = 0x259F; Name = 'Block Elements'; Ascii = '#' }
    [pscustomobject]@{ Lo = 0x25A0; Hi = 0x25FF; Name = 'Geometric Shapes'; Ascii = '*' }
    [pscustomobject]@{ Lo = 0x2600; Hi = 0x26FF; Name = 'Miscellaneous Symbols'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x2700; Hi = 0x27BF; Name = 'Dingbats'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x27F0; Hi = 0x27FF; Name = 'Supplemental Arrows-A'; Ascii = '->' }
    [pscustomobject]@{ Lo = 0x2900; Hi = 0x297F; Name = 'Supplemental Arrows-B'; Ascii = '->' }
    [pscustomobject]@{ Lo = 0x3000; Hi = 0x303F; Name = 'CJK Symbols and Punctuation'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x4E00; Hi = 0x9FFF; Name = 'CJK Unified Ideographs'; Ascii = $null }
    [pscustomobject]@{ Lo = 0xE000; Hi = 0xF8FF; Name = 'Private Use Area'; Ascii = $null }
    [pscustomobject]@{ Lo = 0xFB00; Hi = 0xFB4F; Name = 'Alphabetic Presentation Forms'; Ascii = $null }
    [pscustomobject]@{ Lo = 0xFE00; Hi = 0xFE0F; Name = 'Variation Selectors'; Ascii = '' }
    [pscustomobject]@{ Lo = 0xFF00; Hi = 0xFFEF; Name = 'Halfwidth and Fullwidth Forms'; Ascii = $null }
    [pscustomobject]@{ Lo = 0xFFF0; Hi = 0xFFFF; Name = 'Specials'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1F000; Hi = 0x1F0FF; Name = 'Mahjong/Domino/Playing Cards'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1F300; Hi = 0x1F5FF; Name = 'Miscellaneous Symbols and Pictographs (emoji)'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1F600; Hi = 0x1F64F; Name = 'Emoticons (emoji)'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1F680; Hi = 0x1F6FF; Name = 'Transport and Map Symbols (emoji)'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1F900; Hi = 0x1F9FF; Name = 'Supplemental Symbols and Pictographs (emoji)'; Ascii = $null }
    [pscustomobject]@{ Lo = 0x1FA70; Hi = 0x1FAFF; Name = 'Symbols and Pictographs Extended-A (emoji)'; Ascii = $null }
)

function Get-CharFacts {
    # Name + suggested ASCII + whether -Fix may rewrite it. An unnamed character is described by its
    # block and general category and SAID to be undescribed -- never given an invented name.
    param([int]$Code)
    $hit = $script:Named[$Code]
    if ($hit) { return [pscustomobject]@{ Name = $hit.Name; Ascii = $hit.Ascii; Fixable = $hit.Fixable; Named = $true } }
    $cat = 'unknown category'
    try {
        if ($Code -le 0xFFFF) { $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory([char]$Code).ToString() }
        else { $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory([string][char]::ConvertFromUtf32($Code), 0).ToString() }
    } catch { }
    foreach ($b in $script:Blocks) {
        if ($Code -ge $b.Lo -and $Code -le $b.Hi) {
            return [pscustomobject]@{
                Name    = "not in this checker's name table -- block '$($b.Name)', category $cat"
                Ascii   = $b.Ascii
                Fixable = $false
                Named   = $false
            }
        }
    }
    return [pscustomobject]@{
        Name    = "not in this checker's name table -- no known block, category $cat"
        Ascii   = $null
        Fixable = $false
        Named   = $false
    }
}

function Format-Suggestion {
    param($Facts)
    if ($null -eq $Facts.Ascii) { return '(no safe replacement -- rewrite the line)' }
    if ($Facts.Ascii -eq '') { return '(delete it)' }
    # Quote with the mark the replacement does not contain, so a suggested double quote does not
    # print as three of them.
    if ("$($Facts.Ascii)".Contains('"')) { return "'" + $Facts.Ascii + "'" }
    return '"' + $Facts.Ascii + '"'
}

# ==================================================================================================
# Enumeration
#
# The directory list is PRUNED during the walk rather than filtered afterwards: descending into a
# .git directory to throw the results away is the difference between a gate you run on every commit
# and one you stop running.
# ==================================================================================================

$script:SkipDirs = @(
    '.git', 'node_modules', '__pycache__', '.venv', 'venv', '.pytest_cache', '.mypy_cache',
    '.ruff_cache', '.tox', '.idea', '.vs', '.svn', '.hg'
) + @($ExcludeDir | Where-Object { $_ })

# Extensions whose contents are bytes, not text. A binary file is full of >0x7F bytes by nature and
# reporting it would bury every real finding. NUL-byte detection below catches the ones not listed.
$script:BinaryExt = @(
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.tif', '.tiff',
    '.pdf', '.zip', '.gz', '.tgz', '.bz2', '.xz', '.7z', '.rar', '.jar',
    '.docx', '.xlsx', '.pptx',   # OOXML: a zip container, so already caught by the NUL test below
    '.exe', '.dll', '.so', '.dylib', '.pyc', '.pyd', '.class', '.o', '.obj', '.bin',
    '.woff', '.woff2', '.ttf', '.otf', '.eot',
    '.mp3', '.mp4', '.wav', '.avi', '.mov', '.webm',
    '.db', '.sqlite', '.sqlite3'
)

function Get-ScanTargets {
    param([string]$Root)
    $out = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Root -PathType Leaf) {
        $out.Add((Resolve-Path -LiteralPath $Root).Path)
        return $out
    }
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push((Resolve-Path -LiteralPath $Root).Path)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try { foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) { $out.Add($f) } } catch { }
        try {
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                $leaf = Split-Path $d -Leaf
                $skip = $false
                foreach ($s in $script:SkipDirs) { if ($leaf -ieq $s) { $skip = $true; break } }
                if (-not $skip) { $stack.Push($d) }
            }
        } catch { }
    }
    return $out
}

# ==================================================================================================
# The scan itself
# ==================================================================================================

function Get-Violations {
    # Every non-ASCII code point in $Text, with a 1-based line and a 1-based column counted in
    # CHARACTERS (a surrogate pair is one character, at one column -- the same way an editor reports
    # it, and the same way the character reads on the line).
    param([string]$Text)
    $found = [System.Collections.Generic.List[object]]::new()
    $line = 1
    $col = 1
    $len = $Text.Length
    for ($i = 0; $i -lt $len; $i++) {
        $ch = $Text[$i]
        if ($ch -eq "`n") { $line++; $col = 1; continue }
        $code = [int]$ch
        $wide = $false
        if ([char]::IsHighSurrogate($ch) -and ($i + 1) -lt $len -and [char]::IsLowSurrogate($Text[$i + 1])) {
            $code = [char]::ConvertToUtf32($ch, $Text[$i + 1])
            $wide = $true
        }
        if ($code -gt 0x7F) {
            $facts = Get-CharFacts $code
            $found.Add([pscustomobject]@{
                    Line = $line; Column = $col; Code = $code
                    Name = $facts.Name; Ascii = $facts.Ascii; Fixable = $facts.Fixable; Named = $facts.Named
                    Index = $i; Width = $(if ($wide) { 2 } else { 1 })
                })
        }
        if ($wide) { $i++ }
        $col++
    }
    return $found
}

function Repair-Text {
    # Apply only the fixable substitutions, walking the ORIGINAL violation list (which already
    # carries each hit's index) so nothing is re-scanned against text that has moved underneath it.
    param([string]$Text, $Violations)
    $sb = [System.Text.StringBuilder]::new()
    $changed = 0
    $byIndex = @{}
    foreach ($v in $Violations) { if ($v.Fixable) { $byIndex[$v.Index] = $v } }
    $i = 0
    while ($i -lt $Text.Length) {
        $hit = $byIndex[$i]
        if ($hit) {
            $null = $sb.Append($hit.Ascii)
            $i += $hit.Width
            $changed++
        } else {
            $null = $sb.Append($Text[$i])
            $i++
        }
    }
    return [pscustomobject]@{ Text = $sb.ToString(); Changed = $changed }
}

# ==================================================================================================
# Run
# ==================================================================================================

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @((Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path)
}

$roots = [System.Collections.Generic.List[string]]::new()
$badRoots = [System.Collections.Generic.List[string]]::new()
foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p) { $roots.Add((Resolve-Path -LiteralPath $p).Path) }
    else { $badRoots.Add($p) }
}

$targets = [System.Collections.Generic.List[string]]::new()
foreach ($r in $roots) { foreach ($f in @(Get-ScanTargets $r)) { $targets.Add($f) } }
$targets = @($targets | Select-Object -Unique)

# The prefix violation paths are reported relative to. One root gives clean relative paths; several
# roots would make a relative path ambiguous, so those are reported in full.
$relBase = $null
if ($roots.Count -eq 1) {
    $relBase = if (Test-Path -LiteralPath $roots[0] -PathType Container) { $roots[0] } else { Split-Path -Parent $roots[0] }
}
function Format-ScanPath {
    param([string]$Full)
    if ($relBase) {
        $prefix = $relBase.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($Full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return ($Full.Substring($prefix.Length) -replace '\\', '/')
        }
    }
    return $Full
}

$filesScanned = 0
$bytesScanned = 0L
$filesBinary = 0
$filesUnreadable = 0
$unreadable = [System.Collections.Generic.List[string]]::new()
$allViolations = [System.Collections.Generic.List[object]]::new()
$fixedFiles = [System.Collections.Generic.List[object]]::new()
$strict = [System.Text.UTF8Encoding]::new($false, $true)

foreach ($file in $targets) {
    $ext = [System.IO.Path]::GetExtension($file)
    if ($script:BinaryExt -contains $ext.ToLowerInvariant()) { $filesBinary++; continue }

    $bytes = $null
    try { $bytes = [System.IO.File]::ReadAllBytes($file) } catch {
        $filesUnreadable++
        $unreadable.Add("$(Format-ScanPath $file) -- $($_.Exception.Message)")
        continue
    }

    # A NUL byte means bytes, not text. Cheap, and it catches every binary format not on the
    # extension list -- which is the list's whole weakness.
    $isBinary = $false
    $probe = [Math]::Min($bytes.Length, 8192)
    for ($b = 0; $b -lt $probe; $b++) { if ($bytes[$b] -eq 0) { $isBinary = $true; break } }
    if ($isBinary) { $filesBinary++; continue }

    $text = $null
    try { $text = $strict.GetString($bytes) } catch {
        # NOT a pass and NOT an ASCII violation: the file is not valid UTF-8, so no honest statement
        # can be made about its characters at all. Fail closed, and say which file.
        $filesUnreadable++
        $unreadable.Add("$(Format-ScanPath $file) -- not valid UTF-8, so its characters cannot be read")
        continue
    }

    $filesScanned++
    $bytesScanned += $bytes.LongLength

    $hits = @(Get-Violations $text)
    if ($hits.Count -eq 0) { continue }

    if ($Fix) {
        $fixable = @($hits | Where-Object { $_.Fixable })
        if ($fixable.Count -gt 0) {
            $rep = Repair-Text -Text $text -Violations $hits
            $wrote = $false
            try {
                [System.IO.File]::WriteAllBytes($file, [System.Text.UTF8Encoding]::new($false).GetBytes($rep.Text))
                $wrote = $true
            } catch {
                $unreadable.Add("$(Format-ScanPath $file) -- could not be rewritten: $($_.Exception.Message)")
                $filesUnreadable++
            }
            if ($wrote) {
                $names = @($fixable | Group-Object Name | Sort-Object Count -Descending |
                        ForEach-Object { "$($_.Count) x $($_.Name)" })
                $fixedFiles.Add([pscustomobject]@{ File = (Format-ScanPath $file); Count = $rep.Changed; Kinds = $names })
                # Re-read from the repaired TEXT, so what is reported as remaining is what is now on
                # disk rather than what was there before the rewrite.
                $hits = @(Get-Violations $rep.Text)
            }
        }
    }

    foreach ($h in $hits) {
        $allViolations.Add([pscustomobject]@{
                File = (Format-ScanPath $file); Line = $h.Line; Column = $h.Column
                Code = $h.Code; Name = $h.Name; Ascii = $h.Ascii; Fixable = $h.Fixable; Named = $h.Named
            })
    }
}

# --------------------------------------------------------------------------------------- report --

Say ''
Say 'check-ascii -- every file in this tree must be pure ASCII'
Say '========================================================='
Say ''
Say 'WHAT WAS SCANNED'
foreach ($r in $roots) { Say "  root             : $r" }
foreach ($r in $badRoots) { Say "  root             : $r  -- DOES NOT EXIST" }
Say "  files scanned    : $filesScanned"
Say "  bytes scanned    : $bytesScanned"
Say "  skipped, binary  : $filesBinary  (by extension or because they contain a NUL byte)"
Say "  unreadable       : $filesUnreadable  (counted as a FAILURE, never as a pass)"
Say "  pruned dirs      : $($script:SkipDirs -join ', ')"
foreach ($u in $unreadable) { Say "                     $u" }

if ($fixedFiles.Count -gt 0) {
    Say ''
    Say 'FIXED (safe substitutions only -- read the diff before committing)'
    foreach ($f in $fixedFiles) {
        Say "  $($f.File): $($f.Count) replacement(s)"
        foreach ($k in $f.Kinds) { Say "      $k" }
    }
    Say '  NOTE: SECTION SIGN becomes the word "Section", which changes word spacing around it.'
    Say '        Every other substitution is character-for-text and changes nothing else.'
}

Say ''
if ($allViolations.Count -eq 0) {
    Say 'VIOLATIONS'
    Say '  none'
} else {
    $shown = 0
    Say "VIOLATIONS ($($allViolations.Count) character(s) that are not ASCII)"
    Say '  file:line:column  U+XXXX  NAME  ->  suggested ASCII'
    foreach ($v in $allViolations) {
        if ($MaxReport -gt 0 -and $shown -ge $MaxReport) { break }
        $facts = [pscustomobject]@{ Ascii = $v.Ascii }
        $tag = if ($v.Fixable) { '   [-Fix rewrites this]' } else { '' }
        Say ("  {0}:{1}:{2}  U+{3}  {4}  ->  {5}{6}" -f `
                $v.File, $v.Line, $v.Column, ('{0:X4}' -f $v.Code), $v.Name, (Format-Suggestion $facts), $tag)
        $shown++
    }
    if ($shown -lt $allViolations.Count) {
        Say "  ... $($allViolations.Count - $shown) more not shown. Re-run with -MaxReport 0 for the full list."
    }
    $fixableLeft = @($allViolations | Where-Object { $_.Fixable }).Count
    if ($fixableLeft -gt 0 -and -not $Fix) {
        Say ''
        Say "  $fixableLeft of these can be rewritten automatically:"
        Say '      pwsh -NoProfile -File scripts/quality/check-ascii.ps1 -Fix'
    }
}

# ---------------------------------------------------------------------------------------- verdict --

# A proven violation outranks an undetermined one: exit 1 is the stronger statement and must not be
# hidden behind a 2. Everything that could NOT be answered -- nothing scanned, a file that would not
# decode, a root that does not exist -- lands on 2, never on 0.
$exit = 0
if ($allViolations.Count -gt 0) { $exit = 1 }
elseif ($filesScanned -eq 0) { $exit = 2 }
elseif ($filesUnreadable -gt 0) { $exit = 2 }
elseif ($badRoots.Count -gt 0) { $exit = 2 }

Say ''
switch ($exit) {
    0 { Say "EXIT 0 -- $filesScanned file(s), $bytesScanned byte(s), all ASCII." }
    1 { Say "EXIT 1 -- $($allViolations.Count) non-ASCII character(s) across $filesScanned file(s) scanned." }
    2 {
        if ($filesScanned -eq 0) {
            Say 'EXIT 2 -- NOTHING WAS SCANNED. This is a failure, not a pass: zero files examined proves nothing.'
        } elseif ($filesUnreadable -gt 0) {
            Say "EXIT 2 -- $filesUnreadable file(s) could not be read or decoded, so this tree is unproven."
        } else {
            Say "EXIT 2 -- $($badRoots.Count) requested root(s) do not exist, so part of what you asked for was never examined."
        }
    }
}
Say ''

if ($Json) {
    $doc = [ordered]@{
        tool         = 'check-ascii'
        version      = $CheckerVersion
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        exitCode     = $exit
        scanned      = [ordered]@{
            roots           = @($roots)
            missingRoots    = @($badRoots)
            filesScanned    = $filesScanned
            bytesScanned    = $bytesScanned
            filesBinary     = $filesBinary
            filesUnreadable = $filesUnreadable
            prunedDirs      = @($script:SkipDirs)
            fixApplied      = [bool]$Fix
        }
        fixed        = @($fixedFiles)
        unreadable   = @($unreadable)
        violations   = @($allViolations)
    }
    [Console]::Out.WriteLine(($doc | ConvertTo-Json -Depth 6))
}

exit $exit
