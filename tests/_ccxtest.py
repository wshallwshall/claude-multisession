"""Helpers shared by the tests in this directory. Standard library only.

WHY THESE TESTS PARSE POWERSHELL WITH REGULAR EXPRESSIONS. The thing under test is an agreement
between two files -- a rule in a script and a matcher in the installer that invokes it, a module a
checker imports and a copy list that has to carry it. Nothing executes at import time that would
reveal a disagreement, and running the installers for real is only possible on some machines (see
`installer_refusal_reason`). So the pins that always run read the declarations directly.

That makes the extraction load-bearing: a pattern that silently matches nothing produces a green test
that proved nothing, which is the exact failure this repository exists to catch. Every extractor here
therefore RAISES when it finds nothing, rather than returning an empty set for a caller to compare
against another empty set.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

GATE = REPO_ROOT / "scripts" / "hooks" / "worktree_gate.ps1"
GATE_INSTALLER = REPO_ROOT / "scripts" / "worktree" / "install-gate.ps1"
GIT_HOOK_INSTALLER = REPO_ROOT / "scripts" / "coord" / "install-git-hooks.ps1"
COORD_INSTALLER = REPO_ROOT / "scripts" / "coord" / "install-coordination.ps1"
SELFHEAL_INSTALLER = REPO_ROOT / "scripts" / "worktree" / "install-selfheal.ps1"

# EVERY installer this repository ships. The pre-commit rule is stated as a fact about "the
# installers", so the scan that pins it has to enumerate all of them: reading only the two that touch
# git hooks would leave the claim broader than its evidence.
ALL_INSTALLERS = (GIT_HOOK_INSTALLER, GATE_INSTALLER, COORD_INSTALLER, SELFHEAL_INSTALLER)

CLAIM_CHECK = REPO_ROOT / "scripts" / "hooks" / "claim_check.py"
PUSH_GUARD = REPO_ROOT / "scripts" / "hooks" / "push_guard.py"


def read(path: Path) -> str:
    """Read a source file. Explicit encoding, always.

    Without one the same file raises on one host and silently substitutes replacement characters on
    another -- and the host that substitutes is the one that loses the character a test is looking
    for, quietly.
    """
    return Path(path).read_text(encoding="utf-8")


# ---------------------------------------------------------------------------------------------
# PowerShell source extraction
# ---------------------------------------------------------------------------------------------


def strip_ps_comments(text: str) -> str:
    """Remove PowerShell comments, leaving string literals intact.

    LOAD-BEARING, and found by drilling rather than by reasoning. Commenting a matcher out is the
    likeliest way anyone disables one -- and a scan that reads the raw text still SEES the string,
    so the tool reads as wired while the hook is never invoked for it. That is precisely the dead
    rule these tests exist to catch, and the first version of this file missed it.
    """
    text = re.sub(r"<#.*?#>", "", text, flags=re.S)  # block comments first: prose contains apostrophes
    out: list[str] = []
    i, n, quote = 0, len(text), None
    while i < n:
        c = text[i]
        if quote is not None:
            out.append(c)
            if c == "`" and quote == '"' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                if i + 1 < n and text[i + 1] == quote:
                    out.append(text[i + 1])
                    i += 2
                    continue
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            out.append(c)
            i += 1
            continue
        if c == "#":
            nl = text.find("\n", i)
            i = n if nl == -1 else nl
            continue
        out.append(c)
        i += 1
    return "".join(out)


def ps_source(path: Path) -> str:
    """A PowerShell file with its comments removed -- what the script actually declares."""
    return strip_ps_comments(read(path))


def _close_paren(text: str, start: int) -> int:
    """Index of the `)` that closes a group already open at `start`.

    Quotes and comments are skipped, because a `#` comment or a parenthesis inside a string would
    otherwise unbalance the count and silently truncate the block being read.
    """
    depth = 1
    i = start
    n = len(text)
    quote = None
    while i < n:
        c = text[i]
        if quote is not None:
            if c == "`" and quote == '"':
                i += 2
                continue
            if c == quote:
                if i + 1 < n and text[i + 1] == quote:  # PowerShell doubles a quote to escape it
                    i += 2
                    continue
                quote = None
        elif c in "\"'":
            quote = c
        elif c == "#":
            nl = text.find("\n", i)
            i = n if nl == -1 else nl
            continue
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise AssertionError("unbalanced parentheses while reading a PowerShell array literal")


def array_literal(text: str, variable: str, source: Path) -> str:
    """The text inside `$<variable> = @( ... )`."""
    m = re.search(r"\$" + re.escape(variable) + r"\s*=\s*@\(", text)
    if m is None:
        raise AssertionError(
            f"{source.name}: no `${variable} = @(" + ")` assignment found. Either the declaration "
            "was renamed or reshaped -- update this test to read the new one. Do NOT delete the "
            "assertion: it is what stops the two files drifting apart."
        )
    end = _close_paren(text, m.end())
    return text[m.end() : end]


def quoted_strings(block: str) -> list[str]:
    """Every single- or double-quoted literal in a block, in order."""
    return [m.group(1) or m.group(2) or "" for m in re.finditer(r'"([^"]*)"' + r"|'([^']*)'", block)]


def hashtable_values(block: str, key: str) -> list[str]:
    """Every `Key = "value"` (or `'value'`) in a block, in order."""
    pattern = re.escape(key) + r"""\s*=\s*(?:"([^"]*)"|'([^']*)')"""
    return [m.group(1) if m.group(1) is not None else m.group(2) for m in re.finditer(pattern, block)]


# ---------------------------------------------------------------------------------------------
# The gate, and the installer that wires it
# ---------------------------------------------------------------------------------------------

# The SAME pattern `Get-HandledTools` in install-gate.ps1 uses when -Status audits the INSTALLED
# copy. Deliberately identical: if the audit and this test disagreed about which rules a gate
# implements, one of them would be reporting on a set of rules nobody else can see.
_HANDLED_TOOLS = re.compile(r"\$tool\s+-(?:not)?in\s+@\(([^)]*)\)")


def gate_handled_tools() -> set[str]:
    """Every tool `worktree_gate.ps1` branches on."""
    found: set[str] = set()
    for m in _HANDLED_TOOLS.finditer(read(GATE)):
        found.update(re.findall(r'"([^"]+)"', m.group(1)))
    if not found:
        raise AssertionError(
            f"{GATE.name}: found NO `$tool -in @(...)` branches. Either every rule was removed, or "
            "the rules stopped being written in the form the installer's own -Status audit reads. "
            "Both matter: -Status would report the same empty set and call the wiring complete."
        )
    return found


def installer_matcher_tools() -> set[str]:
    """Every tool named in install-gate.ps1's PreToolUse matcher list.

    Includes the conditionally-appended ones: a matcher behind an install flag is still a matcher
    the gate can be wired with, and the anti-drift question is whether a rule has any route to
    firing at all.
    """
    text = ps_source(GATE_INSTALLER)
    tools: set[str] = set()
    for value in quoted_strings(array_literal(text, "matchers", GATE_INSTALLER)):
        tools.update(t for t in value.split("|") if t)
    for value in re.findall(r'\$matchers\s*\+=\s*"([^"]+)"', text):
        tools.update(t for t in value.split("|") if t)
    if not tools:
        raise AssertionError(
            f"{GATE_INSTALLER.name}: found no matcher strings. The extraction is broken, or the "
            "matcher list was reshaped -- either way this test is no longer pinning anything."
        )
    return tools


def gate_helper_copy_list() -> set[str]:
    """The leaf filenames install-gate.ps1 copies beside the gate ($GateHelpers destinations)."""
    block = array_literal(ps_source(GATE_INSTALLER), "GateHelpers", GATE_INSTALLER)
    leaves = {Path(v).name for v in hashtable_values(block, "Dst")}
    # `Dst = (Join-Path $HooksDir "_command.ps1")` -- the quoted literal IS the leaf name.
    leaves |= {v for v in quoted_strings(block) if v.endswith(".ps1")}
    leaves = {leaf for leaf in leaves if leaf.endswith(".ps1")}
    if not leaves:
        raise AssertionError(
            f"{GATE_INSTALLER.name}: $GateHelpers named no .ps1 file. The gate dot-sources helpers "
            "that must travel with it; an empty copy list means it installs a gate that cannot load."
        )
    return leaves


def gate_dependency_closure() -> set[str]:
    """Leaf filenames the gate needs beside it, derived from the code rather than from a comment.

    The gate dot-sources two helpers; one of those resolves a third itself. Reading the requirement
    off the consumers is the point -- a copy list checked against a hand-written list of names only
    proves that two comments agree.
    """
    direct = set(re.findall(r"^\s*\.\s*\(Join-Path[^)]*?['\"](_[\w-]+\.ps1)['\"]", read(GATE), re.M))
    if not direct:
        raise AssertionError(
            f"{GATE.name}: no dot-sourced helper found. Either the gate stopped loading its shared "
            "helpers, or it now loads them a different way that this test cannot see."
        )
    closure = set(direct)
    for leaf in direct:
        for candidate in (REPO_ROOT / "scripts" / "hooks" / leaf, REPO_ROOT / "scripts" / "coord" / leaf):
            if candidate.exists():
                closure.update(
                    re.findall(r"Join-Path[^\n]*?['\"](_[\w-]+\.ps1)['\"]", read(candidate))
                )
                break
    return closure


def installer_allowlist_relpath() -> str:
    """The allowlist path install-gate.ps1 writes, relative to the home directory.

    Extracted rather than hard-coded, so this pins the AGREEMENT between the installer and the
    gate's parameter default instead of pinning each of them to a string in a test file.
    """
    text = ps_source(GATE_INSTALLER)
    hooks = re.search(r'\$HooksDir\s*=\s*Join-Path\s+\$HomeDir\s+"([^"]+)"', text)
    repos = re.search(r'\$ReposFile\s*=\s*Join-Path\s+\$HooksDir\s+"([^"]+)"', text)
    if not hooks or not repos:
        raise AssertionError(
            f"{GATE_INSTALLER.name}: could not read $HooksDir / $ReposFile. They are how the "
            "installer decides where the kill switch lives; the gate's parameter default has to "
            "agree with them, and this test can no longer check that it does."
        )
    return hooks.group(1).replace("\\", "/").strip("/") + "/" + repos.group(1)


# ---------------------------------------------------------------------------------------------
# The git-hook installer
# ---------------------------------------------------------------------------------------------


def git_hook_names() -> list[str]:
    """The git hook filenames install-git-hooks.ps1 declares it writes."""
    block = array_literal(ps_source(GIT_HOOK_INSTALLER), "ARTIFACTS", GIT_HOOK_INSTALLER)
    hooks = hashtable_values(block, "Hook")
    if not hooks:
        raise AssertionError(
            f"{GIT_HOOK_INSTALLER.name}: $ARTIFACTS declared no Hook names. This test cannot tell "
            "which files the installer writes, so it cannot pin that pre-commit is not one of them."
        )
    return hooks


def substrate_payloads() -> set[str]:
    """The filenames install-git-hooks.ps1 copies alongside its checkers ($SUBSTRATE)."""
    block = array_literal(ps_source(GIT_HOOK_INSTALLER), "SUBSTRATE", GIT_HOOK_INSTALLER)
    payloads = set(hashtable_values(block, "Payload"))
    if not payloads:
        raise AssertionError(
            f"{GIT_HOOK_INSTALLER.name}: $SUBSTRATE named no payload. The checkers import a module "
            "that has to travel with them; without it they raise at import and refuse every commit."
        )
    return payloads


def checker_private_imports() -> set[str]:
    """Private modules the installed checkers import, as filenames.

    Derived from the checkers themselves. They insert their own directory on `sys.path` and import
    from it, so anything they import this way MUST be installed beside them.
    """
    modules: set[str] = set()
    for checker in (CLAIM_CHECK, PUSH_GUARD):
        text = read(checker)
        # ONE leading underscore. `__future__` is a compiler directive, not a file to copy, and it
        # matched happily until it was excluded.
        modules.update(re.findall(r"^\s*from\s+(_(?!_)\w+)\s+import\b", text, re.M))
        modules.update(re.findall(r"^\s*import\s+(_(?!_)\w+)\s*$", text, re.M))
    if not modules:
        raise AssertionError(
            "neither checker imports a private module any more. If that is deliberate, delete the "
            "substrate assertions; if it is not, the import was renamed and the installer's copy "
            "list now carries a file nothing reads."
        )
    return {m + ".py" for m in modules}


# ---------------------------------------------------------------------------------------------
# Running things
# ---------------------------------------------------------------------------------------------


def find_pwsh() -> str | None:
    """Where `pwsh` is, or None.

    Only the gate is executed by these tests. NOTHING here runs an installer: they refuse to run
    inside an agent session, deliberately, and a test that cleared that variable to get its coverage
    would be doing the exact thing the control forbids -- and would be the first example anyone
    copied. The evidence that an install lands correctly comes from `bin/ccx-doctor.ps1`.
    """
    return shutil.which("pwsh")
