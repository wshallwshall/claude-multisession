#!/usr/bin/env python3
"""Leak gate -- refuse to let identifying content reach a public repository.

THE DEFECT THIS EXISTS FOR. A repository that is going to be published carries a long tail of
strings that identify the machine, the network and the people it was written on: an absolute
home-directory path with an OS account name in it, a routable host address pasted out of a terminal,
a credential shape copied into a config example, the name of a private client or product. None of
these is a syntax error, none is a test failure, and none is a *secret* in the sense a secret
scanner means -- so nothing else in a normal toolchain looks for them. They are found by a reader,
after publication, or not at all.

WHAT THIS IS NOT. It is not a secret scanner (use one of those too -- they know key formats and
entropy far better than this does), and it is not a substitute for reading the diff. See the
"permanent blind spot" note in docs/LEAK-GATE.md before you trust it with anything.

TWO DETECTOR TIERS.

  STRUCTURAL detectors are compiled into this file and always run, because they recognise a SHAPE
  rather than a name: an absolute user-home path, a routable IPv4 address, a credential prefix.
  There is no list to keep current -- they work in a fresh fork, in CI with no secrets, in a
  contributor's clone. The home-path class is the one that actually fires in practice.

  TOKEN detectors come from a file you supply and never commit: the literal names of the private
  projects, clients, vendors, hosts or people that must not appear. Nobody can ship that list for
  you, and a public repository is the last place it could live. Sources, in precedence order:

    1. ``CCX_FORBIDDEN_TOKENS`` -- either a path to a token file OR the token content inline
       (newline-separated, same format). This is how CI supplies it, from a secret.
    2. ``scripts/security/scan-tokens.local.txt`` -- a local file next to this script, matched by
       the repository's ``*.local.*`` ignore rule so it cannot be committed by accident.

WITH NO TOKEN SOURCE THE GATE RUNS STRUCTURAL-ONLY, and says so on every run. That is a legitimate
posture -- it still catches the home-path class -- but a green result then proves much less than an
armed one, which is why the mode is printed on both the "loaded" line and the "scanned" line rather
than inferred from silence. Set ``CCX_REQUIRE_TOKENS=1`` (or pass ``--require-tokens``) to refuse
with exit 2 instead, so a misconfigured owner run cannot under-scan quietly.

PRESENCE IS NOT SUFFICIENCY. A source that loads only PART of its tokens is the dangerous case: it
satisfies "tokens present", prints no structural-only warning, and passes a gate that calls itself
fail-closed. So requiring tokens also requires every floor section to be non-empty, and
``CCX_MIN_DETECTORS=N`` (or ``--require-tokens=N``) asserts a minimum count, which is what catches
loss *within* a section. It is a floor, not an equality: adding tokens is free, losing them fails.
The expected count is supplied from OUTSIDE the token source on purpose -- a count carried inside
the file would be destroyed by the same mangling it is meant to detect.

Token-file format (sectioned; ``#`` comments and blank lines ignored):

    [names]      REGEX | REASON | CASE   -- REASON optional (default "private token"); CASE
                 optional: "i" case-insensitive (default) or "s" case-sensitive. The field
                 delimiter is a space-pipe-space (`` | ``); a regex alternation ``a|b`` is fine.
    [literals]   one substring per line, matched case-insensitively with non-letter boundaries, so
                 it fires on a token buried in an identifier (``sync_<token>_export``) which a
                 word-boundary regex cannot see -- ``_`` is a word character.

Usage:
    scan_forbidden.py [FILE ...]        # scan the named files (how a pre-commit hook invokes it)
    scan_forbidden.py --path DIR        # scan every text file under DIR (repeatable)
    scan_forbidden.py                   # scan every git-tracked file in this repository
    scan_forbidden.py --show-context    # also print the matched value and line -- LOCAL TRIAGE
                                        #   ONLY. A hit means the string is already in a file, so
                                        #   echoing it in CI copies the leak into a public log.

Exit: 0 clean, 1 forbidden content found, 2 usage error / nothing scanned / fail-closed refusal.

Stdlib only, ASCII output only, no project import: this has to run in a bare clone, in a hook with
no virtualenv, and on a runner. A gate that cannot start is a gate that is off.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

TOOL = "ccx leak gate"

# ==================================================================================================
# Structural detectors -- no private data, safe to commit, always armed.
# ==================================================================================================

# Routable-IPv4. The look-arounds keep dotted OIDs (1.3.6.1...), spec-section citations and version
# strings embedded in longer dotted runs from matching; only a free-standing quad does.
_OCTET = r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"
_IPV4 = re.compile(rf"(?<![\d.])(?:{_OCTET}\.){{3}}{_OCTET}(?![\d.])")
# Addresses that cannot identify a real host: RFC1918 private, loopback, link-local, broadcast,
# RFC5737 TEST-NET-1/2/3 (documentation), multicast/reserved. Everything else names a machine
# somewhere, and pasting one into a public repo is a network disclosure even when it is "just" a
# jump box.
_ALLOWED_IP = re.compile(
    r"^(?:"
    r"0\.|127\.|10\.|192\.168\.|169\.254\.|255\.|"
    r"172\.(?:1[6-9]|2\d|3[01])\.|"  # 172.16.0.0/12
    r"192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|"  # TEST-NET-1/2/3 (RFC 5737)
    r"22[4-9]\.|23\d\."  # multicast / reserved
    r")"
)

# An absolute user-home path carries the OS account name -- usually a real person's login, often
# their employer's naming convention, and inside a worktree path the internal project name as well.
# This is the class that actually fires: it arrives through pasted terminal output, a traceback, a
# tool's error message, a lockfile, a .pyc.
#
# Exempt: bracket/env placeholders (<name>, $HOME, %USERPROFILE%, {home}), the well-known shared and
# CI accounts, and the conventional documentation stand-ins. That list is the whole judgement call
# here -- "is this a real person's login" is not decidable by shape -- so the pattern trusts a small
# explicit set of stand-ins and treats everything else as a disclosure. Deliberately NOT extended
# with every plausible placeholder: each addition is a hole, and a false positive costs one
# allowlist line while a false negative costs a publication.
_HOME_PATH = re.compile(
    r"(?:[A-Za-z]:[\\/]Users|/home|/Users)[\\/]"
    r"(?!<|\$|%|\{"
    r"|(?:Public|Default|All|ContainerAdministrator|runner|vsts"
    r"|me|you|user|username|example)[\\/\s\"'`]"
    r")"
    r"[A-Za-z][A-Za-z0-9._-]*"
)

# Credential SHAPES. Prefix-anchored on purpose: an entropy heuristic over source produces a false
# positive storm (hashes, base64 fixtures, minified assets) and a gate people mute is worth nothing.
# These say "this is a credential" by construction, not by guess. A real secret scanner knows many
# more; this catches the copy-paste cases that ride along with identifying content.
_CREDENTIALS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"), "private key block"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "cloud access key id"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36}\b"), "forge access token"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}"), "forge access token"),
    (re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}"), "chat platform token"),
    (re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{32,}"), "model API key"),
)

#: Every structural detector, for the count line. A caller cannot tell an armed run from a vacuous
#: one unless the run says how many detectors it had, so this number is printed even though it is a
#: constant: the day someone edits this file, the printed number is the receipt.
_STRUCTURAL_COUNT = 2 + len(_CREDENTIALS)  # home path + routable IP + credential shapes

#: A pattern that can never match -- the "detector off" sentinel. ``(?!)`` is an always-failing
#: assertion, so ``.search`` never fires while ``.pattern`` stays a valid string.
_NEVER: re.Pattern[str] = re.compile(r"(?!)")

# Dotted numbers in a dependency lockfile are versions, not hosts. Skip the IP detector (only) there.
_IP_SKIP_SUFFIXES = frozenset({".lock"})
_IP_SKIP_NAMES = frozenset({"requirements.lock", "uv.lock", "package-lock.json", "poetry.lock"})

SKIP_DIRS = frozenset(
    {
        ".git",
        ".venv",
        "venv",
        "node_modules",
        "__pycache__",
        ".mypy_cache",
        ".ruff_cache",
        ".pytest_cache",
        "build",
        "dist",
    }
)

#: Location of the local token file (the non-CI source). Overridable in tests.
LOCAL_TOKEN_FILE = Path(__file__).parent / "scan-tokens.local.txt"

#: The ONLY file skipped by policy: the token file itself. It is never committed, so it is absent
#: from a tracked scan -- but a whole-tree ``--path .`` on the owner's machine would walk it and
#: self-trip on every token it exists to hold. Nothing that can reach the public repo is skipped.
SKIP_PATHS = ("scripts/security/scan-tokens.local.txt",)


def _is_skipped(path: Path, posix: str) -> bool:
    """Is this file skipped BY POLICY (as opposed to merely absent)?

    ``posix`` is always relative to the scan root, so the SKIP_PATHS test is an EXACT path match and
    never a suffix match -- a same-named file elsewhere in the tree must still be scanned. The
    resolved comparison is the belt-and-braces half: under ``--path`` the token file's relative path
    depends on where the scan started, and it must be skipped from every scan root.
    """
    if posix in SKIP_PATHS:
        return True
    if path.name != LOCAL_TOKEN_FILE.name:
        return False
    try:
        return path.resolve() == LOCAL_TOKEN_FILE.resolve()
    except OSError:
        return False


# ==================================================================================================
# Token detectors -- externalized, never committed.
# ==================================================================================================

FORBIDDEN: list[tuple[re.Pattern[str], str]] = []
LITERALS: tuple[str, ...] = ()
#: (token, boundary-aware pattern) per literal. The boundary requires non-LETTER flanks, so it fires
#: on ``sync_<token>_export`` -- underscore is a word character, so a ``\b``-anchored name pattern is
#: blind to exactly that shape -- while not firing on the token as a run of letters inside an
#: unrelated word.
_LITERAL_RES: tuple[tuple[str, re.Pattern[str]], ...] = ()
#: True when a token source was found AND it actually yielded detectors. Both halves matter.
TOKENS_PRESENT: bool = False


def _resolve_token_text() -> str | None:
    """The active token content, or ``None`` if no source is configured.

    ``CCX_FORBIDDEN_TOKENS`` wins: an existing file path is read; any other non-empty value is taken
    as inline content; an explicitly empty value means "no source, deliberately". Otherwise the
    local file is read if present.
    """
    env = os.environ.get("CCX_FORBIDDEN_TOKENS")
    if env is not None:
        env = env.strip()
        if not env:
            return None
        try:
            candidate = Path(env)
            if candidate.is_file():
                return candidate.read_text(encoding="utf-8")
        except OSError:
            pass
        return env  # inline, newline-separated
    try:
        if LOCAL_TOKEN_FILE.is_file():
            return LOCAL_TOKEN_FILE.read_text(encoding="utf-8")
    except OSError:
        pass
    return None


def _is_invisible(ch: str) -> bool:
    """True for a codepoint that carries no glyph: control, zero-width, BOM or bidi mark.

    ``str.isprintable()`` is False for exactly the categories that matter -- Cc controls and Cf
    formats, covering U+200B, U+FEFF and the bidi overrides -- and True for letters, digits and the
    plain space. Expressed through isprintable() rather than a character-class literal on purpose: a
    literal needs escape sequences that are themselves easy to mangle, inside a check whose entire
    job is catching mangling.
    """
    return not ch.isprintable()


#: An empty negative lookahead -- this module's own "detector off" sentinel, refused if it arrives
#: from a token source, where it would compile cleanly, count toward the floor and never fire.
_NEVER_MATCH_RE = re.compile(r"\(\?\!\)")

#: UTF-8 BOM, built with chr() rather than written literally: a raw codepoint here is exactly the
#: thing that gets mangled in transit, in the one place whose job is to survive mangling.
_BOM = chr(0xFEFF)


def _reject_entry(kind: str, value: str) -> bool:
    """True (and warns) when an entry carries an invisible codepoint, so it must be dropped.

    This is the corruption class a COUNT FLOOR cannot see. A zero-width space is not
    ``str.isspace()`` and survives ``str.strip()`` (unlike NBSP, which strips to empty), so one
    injected inside a token by a paste through a rendering surface leaves an entry that parses,
    counts toward the floor, and silently never matches: identical counts, detection off. Rejecting
    these is what makes the floor count detectors that can FIRE rather than entries that PARSE.

    The warning does not echo the value. This can run in a world-readable log on a public repo and
    the value is the private token; codepoint and offset are enough to fix it.
    """
    for offset, ch in enumerate(value):
        if _is_invisible(ch):
            print(
                f"{TOOL}: ignoring a {kind} containing an invisible/control codepoint "
                f"U+{ord(ch):04X} at offset {offset} - it would count toward the detector floor "
                "but never match. Re-set the token source from the file rather than pasting it.",
                file=sys.stderr,
            )
            return True
    return False


def _parse_tokens(text: str) -> tuple[list[tuple[re.Pattern[str], str]], tuple[str, ...]]:
    """Parse sectioned token content into (name patterns, literal substrings)."""
    section: str | None = None
    names: list[tuple[re.Pattern[str], str]] = []
    literals: list[str] = []
    known = {"names", "literals"}
    for lineno, raw in enumerate(text.splitlines(), 1):
        # Strip a BOM before anything else: a UTF-8 BOM immediately ahead of the first section
        # header defeats the startswith("[") test below and silently voids that entire section.
        line = raw.lstrip(_BOM).strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            if section not in known:
                # Silently discarding an unrecognised section is how a typo'd header drops a whole
                # token set with no diagnostic at all. Name it.
                print(
                    f"{TOOL}: token line {lineno}: unknown section header - its entries will be "
                    f"IGNORED (expected one of: {', '.join(sorted(known))})",
                    file=sys.stderr,
                )
            continue
        if section is None:
            print(
                f"{TOOL}: token line {lineno}: content before the first section header - IGNORED",
                file=sys.stderr,
            )
            continue
        if section == "names":
            _parse_name_entry(line, lineno, names)
        elif not _reject_entry("literal token", line):
            literals.append(line.lower())

    # DEDUPE before anything counts. The floor is a count, so a double-pasted section would inflate
    # it: 13 literals pasted twice reads as 26 and masks the loss of 13 real ones. Duplicates add no
    # detection either. Order is preserved, so behaviour stays deterministic.
    literals = list(dict.fromkeys(literals))
    seen: set[tuple[str, int]] = set()
    deduped: list[tuple[re.Pattern[str], str]] = []
    for compiled, why in names:
        key = (compiled.pattern, compiled.flags)
        if key not in seen:
            seen.add(key)
            deduped.append((compiled, why))
    return deduped, tuple(literals)


def _parse_name_entry(line: str, lineno: int, out: list[tuple[re.Pattern[str], str]]) -> None:
    """Parse one ``[names]`` row into ``out``. Never echoes the entry: the entry IS the token."""
    parts = [p.strip() for p in line.split(" | ")]
    if len(parts) > 3:
        # The field delimiter is a space-pipe-space, so a regex with a SPACED alternation (``a | b``)
        # splits into extra fields and parts[0] truncates to its first branch -- still compiling, so
        # the re.error handler never fires and the count is unchanged. Refuse ambiguous input rather
        # than half-honouring it.
        print(
            f"{TOOL}: token line {lineno}: [names] entry has {len(parts)} fields, expected at most "
            "3 (PATTERN | REASON | CASE) - a spaced regex alternation would be truncated, so this "
            "entry is IGNORED (content withheld)",
            file=sys.stderr,
        )
        return
    pattern = parts[0]
    reason = parts[1] if len(parts) > 1 and parts[1] else "private token"
    case = parts[2].lower() if len(parts) > 2 and parts[2] else "i"
    if case not in {"i", "s"}:
        # Warn, but KEEP the entry. Dropping it loses a detector, and under-detection is the
        # dangerous direction; the fallback below is case-INSENSITIVE, which is strictly broader
        # than case-sensitive and so can only over-match. Fail toward more detection.
        print(
            f"{TOOL}: token line {lineno}: [names] CASE field is not 'i' or 's' - defaulting to "
            "case-INSENSITIVE (content withheld)",
            file=sys.stderr,
        )
    # Only an explicit "s" is case-sensitive. There is deliberately no separate assignment
    # implementing that fallback -- one would be dead code, indistinguishable from this line.
    flags = 0 if case == "s" else re.I
    if _reject_entry("name pattern", pattern):
        return
    if _NEVER_MATCH_RE.search(pattern):
        print(
            f"{TOOL}: token line {lineno}: ignoring a name pattern that can never match "
            "(it contains the empty-negative-lookahead sentinel)",
            file=sys.stderr,
        )
        return
    try:
        compiled = re.compile(pattern, flags)
    except re.error:
        # NEVER echo the pattern. This warning can land in a world-readable log on the public repo
        # and the pattern IS the private token, so a malformed line -- exactly the case where the
        # source was mishandled -- would leak the thing the gate exists to protect. Position only.
        print(
            f"{TOOL}: token line {lineno}: ignoring an uncompilable [names] regex "
            "(content withheld)",
            file=sys.stderr,
        )
        return
    if compiled.search(reason):
        # A REASON is printed verbatim on every hit. A reason that names its own token therefore
        # publishes the token on the first match -- the same defect as echoing it in a parse
        # warning, just on the success path. Neutralise the LABEL, keep the DETECTOR: dropping the
        # entry would trade a disclosure for under-detection, which is worse.
        print(
            f"{TOOL}: token line {lineno}: [names] REASON matches its own pattern and would echo "
            "the token on every hit - using the generic reason instead",
            file=sys.stderr,
        )
        reason = "private token"
    out.append((compiled, reason))


def reload_tokens() -> None:
    """Recompute the token tables from the current environment / local file.

    Called at import and again at the top of :func:`main`, so a fresh process always reflects its
    environment. Never raises: an absent source yields empty tables and a structural-only run.
    """
    global FORBIDDEN, LITERALS, _LITERAL_RES, TOKENS_PRESENT
    text = _resolve_token_text()
    names, literals = _parse_tokens(text or "")
    # A source being PRESENT is not the same as a source being USABLE. Deriving this from
    # ``text is not None`` alone means a mangled source -- headers lost, comments only, a BOM ahead
    # of the first header -- yields ZERO detectors while still reporting "tokens present", so
    # --require-tokens passes and the gate runs structural-only with a green tick. Pasting a whole
    # sectioned file into a CI secret box is exactly that mangling case. Require that parsing
    # actually produced something.
    TOKENS_PRESENT = text is not None and bool(names or literals)
    FORBIDDEN = names
    LITERALS = literals
    _LITERAL_RES = tuple(
        (token, re.compile(rf"(?<![A-Za-z]){re.escape(token)}(?![A-Za-z])", re.IGNORECASE))
        for token in literals
    )


def loaded_token_counts() -> dict[str, int]:
    """Detector counts for the current tables, printed on every run.

    "It exited 0" is not evidence that anything was scanned. These counts are what distinguishes a
    real run from a vacuous one, and they are what the floor asserts against.
    """
    return {
        "structural": _STRUCTURAL_COUNT,
        "names": len(FORBIDDEN),
        "literals": len(LITERALS),
        "allowlist": len(ALLOWLIST),
    }


#: The sections a fully-loaded token source must ALL populate. ``TOKENS_PRESENT`` is deliberately an
#: OR (any section proves a source exists at all); the floor is the AND.
_FLOOR_SECTIONS: tuple[str, ...] = ("names", "literals")


def parse_min_spec(value: str) -> int | dict[str, int]:
    """Parse a floor spec: either a bare total (``21``) or per-section (``names=7,literals=13``).

    Per-section is STRICTLY STRONGER and is what CI should use. A bare total is a SUM, so growth in
    a cheap section masks collapse in an expensive one -- names 7->1 alongside literals 13->19 still
    totals 20 and passes, with 6 of 7 name detectors silently off.
    """
    value = value.strip()
    if value.isdigit() and value.isascii():
        return int(value)
    spec: dict[str, int] = {}
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise ValueError(f"floor spec {part!r} is neither an integer nor section=N")
        name, _, num = part.partition("=")
        name, num = name.strip(), num.strip()
        if name not in _FLOOR_SECTIONS:
            raise ValueError(
                f"unknown floor section {name!r} (expected one of {', '.join(_FLOOR_SECTIONS)})"
            )
        if not (num.isdigit() and num.isascii()):
            raise ValueError(f"floor for {name!r} must be an integer, got {num!r}")
        spec[name] = int(num)
    if not spec:
        raise ValueError("empty floor spec")
    return spec


def token_floor_failure(min_detectors: int | dict[str, int] | None = None) -> str | None:
    """Why the loaded tables are not trustworthy, or ``None`` if they are.

    Presence is not sufficiency. ``TOKENS_PRESENT`` is satisfied by ANY ONE section surviving, so a
    partially mangled source -- a paste that lost a section, a typo'd header, a BOM ahead of the
    first header -- can load a single detector and still pass a "fail-closed" gate with a green
    tick. Losing only the final line, the likeliest paste error, silently disables a whole class.
    This closes it two independent ways: every floor section must be non-empty (whole-section loss),
    and the total must meet ``min_detectors`` when given (loss WITHIN a section, which the
    non-empty check alone cannot see).

    The expected total comes from OUTSIDE the token source deliberately. An ``[expect]`` count
    carried inside the file would be destroyed by the very mangling it is meant to detect.
    """
    if not TOKENS_PRESENT:
        return (
            "no token source is configured (set CCX_FORBIDDEN_TOKENS, or place "
            "scripts/security/scan-tokens.local.txt) - refusing to run structural-only"
        )
    counts = loaded_token_counts()
    empty = [s for s in _FLOOR_SECTIONS if not counts[s]]
    if empty:
        return (
            f"the token source loaded but section(s) {', '.join(empty)} are EMPTY - a partial or "
            f"mangled source (loaded {', '.join(f'{s}={counts[s]}' for s in _FLOOR_SECTIONS)}). "
            "Re-set the source from the file rather than pasting it"
        )
    if isinstance(min_detectors, dict):
        short = [f"{s} {counts[s]}<{need}" for s, need in min_detectors.items() if counts[s] < need]
        if short:
            return (
                f"section detector counts below their floor ({', '.join(short)}) - the token "
                "source is incomplete. Per-section floors catch what a total cannot: growth in one "
                "section masking collapse in another"
            )
    elif min_detectors is not None:
        total = sum(counts[s] for s in _FLOOR_SECTIONS)
        if total < min_detectors:
            return (
                f"only {total} token detectors loaded, below the required floor of {min_detectors} "
                f"({', '.join(f'{s}={counts[s]}' for s in _FLOOR_SECTIONS)}) - the token source is "
                "incomplete. This is a FLOOR: adding tokens is free, losing them is not"
            )
    return None


# ==================================================================================================
# Allowlist
# ==================================================================================================

#: Benign strings an allowlist entry must NOT match. An entry that matches any of these is broad
#: enough to veto ordinary source lines, and therefore broad enough to switch the gate off
#: wholesale. The empty string is included so a pattern that matches nothing-in-particular is caught.
_ALLOWLIST_CANARIES: tuple[str, ...] = (
    "",
    "the quick brown fox jumps over the lazy dog",
    "def main(argv: list[str]) -> int:",
    "# a perfectly ordinary comment",
    "0123456789",
)

ALLOWLIST_FILE = Path(__file__).parent / "scan-allowlist.txt"


def _load_allowlist() -> list[re.Pattern[str]]:
    """Optional line-regex allowlist for vetted false positives (one regex per line, '#' comments).

    NEVER allowlist real identifying data -- only genuinely innocent lines a structural pattern
    over-matches, and only narrowly enough that a real disclosure on the same line still trips.
    """
    if not ALLOWLIST_FILE.exists():
        return []
    out: list[re.Pattern[str]] = []
    for lineno, raw in enumerate(ALLOWLIST_FILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            pat = re.compile(line)
        except re.error:
            print(
                f"{TOOL}: scan-allowlist.txt line {lineno}: uncompilable regex - IGNORED",
                file=sys.stderr,
            )
            continue
        # An allowlist entry is a per-line VETO applied BEFORE any detector runs, so one over-broad
        # entry disables the ENTIRE gate -- every detector, every file -- while the "loaded" line
        # still reports full counts, making the log indistinguishable from a healthy run. This file
        # is committed and public, so the entry that does it need not be malicious: a hastily
        # written `.` or `.*` for one false positive is enough.
        if any(pat.search(probe) is not None for probe in _ALLOWLIST_CANARIES):
            print(
                f"{TOOL}: scan-allowlist.txt line {lineno}: pattern matches ordinary text - it "
                "would veto every line and disable the whole gate. IGNORED. Anchor it, or make it "
                "specific to the false positive you are excusing.",
                file=sys.stderr,
            )
            continue
        out.append(pat)
    return out


ALLOWLIST = _load_allowlist()
reload_tokens()


# ==================================================================================================
# Scanning
# ==================================================================================================

#: Identifier separators neutralised before the second name-pattern pass. Only ``_`` today: it is
#: the one separator that is also a WORD character, so it is the only one that defeats ``\b``.
_IDENT_SEP = re.compile(r"_")


def _takes_ident_pass(pat: re.Pattern[str]) -> bool:
    r"""Is this name pattern eligible for the identifier (underscore-neutralised) pass?

    Only SINGLE-TOKEN patterns are. The gap being closed is a lone token buried in an identifier --
    ``sync_token_export`` -- which a ``\b``-anchored pattern cannot see because ``_`` is a word character.

    A MULTI-WORD pattern must be excluded, and this is not hypothetical: neutralising ``_`` for a
    two-word phrase makes it match ordinary snake_case, which on a real tree produced a run of false
    positives on a perfectly generic identifier -- enough to block a merge on its own gate.
    Whitespace in the pattern (literal or ``\s``) is the signal.
    """
    src = pat.pattern
    return " " not in src and r"\s" not in src


def _read_text(path: Path) -> str | None:
    try:
        data = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in data[:4096]:  # binary -- nothing textual to scan
        return None
    return data.decode("utf-8", errors="replace")


def scan_file(path: Path, rel_posix: str | None = None, *, show_context: bool = False) -> list[str]:
    """Forbidden-content hits in one file, as ``path:line: reason`` strings.

    Reasons only by default -- location and category, never the matched value -- so a hit report is
    safe to print in a public CI log. ``show_context`` appends the matched value and the trimmed
    line, for local triage only.
    """
    posix = rel_posix if rel_posix is not None else path.as_posix()
    text = _read_text(path)
    if text is None:
        return []
    ip_scan = path.suffix not in _IP_SKIP_SUFFIXES and path.name not in _IP_SKIP_NAMES
    hits: list[str] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if any(a.search(line) for a in ALLOWLIST):
            continue
        ctx = f": {line.strip()[:120]}" if show_context else ""
        before = len(hits)
        # ``_`` is a word character, so a \b-anchored name pattern cannot see its token inside an
        # identifier. Scanning a shadow copy with identifier separators neutralised closes that for
        # EVERY name pattern rather than for the instances someone remembered to duplicate as a
        # literal. Substitution preserves length, so offsets and show_context stay meaningful.
        unwrapped = _IDENT_SEP.sub(" ", line)
        for pat, reason in FORBIDDEN:
            if pat.search(line) or (_takes_ident_pass(pat) and pat.search(unwrapped)):
                hits.append(f"{posix}:{lineno}: {reason}{ctx}")
        if ip_scan:
            for m in _IPV4.finditer(line):
                ip = m.group(0)
                if not _ALLOWED_IP.match(ip):
                    value = f" ({ip})" if show_context else ""
                    hits.append(f"{posix}:{lineno}: routable IP address{value}{ctx}")
        # Reason only, never the value: the account name IS the disclosure, so echoing it into a
        # public log would publish exactly what the hit is reporting.
        if _HOME_PATH.search(line):
            hits.append(f"{posix}:{lineno}: absolute user-home path (OS account name){ctx}")
        for cred_pat, cred_label in _CREDENTIALS:
            if cred_pat.search(line):
                hits.append(f"{posix}:{lineno}: {cred_label}")
        # Literals run LAST and only on a line nothing else flagged: the sets overlap (a private
        # name is typically in [names] AND [literals]) and double-reporting one line adds noise, not
        # information. What this adds is the case no other detector reaches -- a token butted
        # against word characters.
        if len(hits) == before:
            for _token, lit_pat in _LITERAL_RES:
                if lit_pat.search(line):
                    hits.append(f"{posix}:{lineno}: private literal token{ctx}")
                    break
    return hits


# ==================================================================================================
# File collection
#
# Every file the run examines belongs to exactly one SOURCE -- one --path directory, one named file,
# or the tracked-file listing. The accounting is per source, not global, because the defect this
# port fixes lives precisely in the gap between the two: a source that contributes NOTHING is
# invisible in a global count as long as some other source contributed something, so a run that
# scanned the wrong half of what it was asked to scan exits 0 and says nothing.
# ==================================================================================================


class Source:
    """One thing the caller asked to be scanned, and what it actually yielded."""

    def __init__(self, label: str, files: list[tuple[Path, str]], *, explicit: bool) -> None:
        self.label = label
        self.files = files
        #: An EXPLICIT source was named on the command line, so contributing nothing is a defect in
        #: the invocation and must be reported by name. The implicit tracked-file listing is not
        #: explicit: an empty repository is a different (and still refused) condition.
        self.explicit = explicit
        self.scanned = 0
        self.absent = 0  # listed but not present on disk
        self.policy_skipped = 0  # skipped by SKIP_DIRS / SKIP_PATHS

    def why_empty(self) -> str:
        """Human cause for a source that yielded no scanned file."""
        if not self.files:
            return "does not exist, or is an empty directory"
        if self.policy_skipped and not self.absent:
            return (
                f"every one of its {self.policy_skipped} file(s) was skipped by policy - check the "
                "path for a SKIP_DIRS component (build/venv/dist/node_modules/...)"
            )
        if self.absent and not self.policy_skipped:
            return f"all {self.absent} of its entries are missing from disk"
        return f"{self.policy_skipped} skipped by policy, {self.absent} missing from disk"


class UsageError(ValueError):
    """A command line that cannot be honoured. Always exit 2 -- never degraded into a scan."""


def _git_tracked() -> list[str]:
    # Fixed literal argv: no shell, no user input.
    return subprocess.run(  # nosec B603 B607
        ["git", "ls-files"], capture_output=True, text=True, check=True, encoding="utf-8"
    ).stdout.splitlines()


def _dir_source(raw: str) -> Source:
    root = Path(raw)
    if root.is_file():
        # A FILE handed to --path used to be dropped in silence. Scanning it is the honest
        # behaviour: the caller named a thing and expects it examined.
        return Source(raw, [(root, root.name)], explicit=True)
    if not root.is_dir():
        return Source(raw, [], explicit=True)
    return Source(
        raw,
        [(p, p.relative_to(root).as_posix()) for p in sorted(root.rglob("*")) if p.is_file()],
        explicit=True,
    )


def collect(argv: list[str]) -> list[Source]:
    """Turn the remaining arguments into sources.

    ``--path`` is repeatable and takes a DIRECTORY (a file is accepted and scanned). Bare arguments
    are file paths, each its own source so that a named file which yields nothing is named back.
    With no arguments at all, the source is the git-tracked file listing.
    """
    sources: list[Source] = []
    files: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--path":
            if i + 1 >= len(argv):
                raise UsageError("--path requires a directory")
            sources.append(_dir_source(argv[i + 1]))
            i += 2
            continue
        files.append(arg)
        i += 1
    for f in files:
        p = Path(f)
        sources.append(Source(f, [(p, p.as_posix())], explicit=True))
    if not sources:
        sources.append(
            Source(
                "git-tracked files",
                [(Path(p), Path(p).as_posix()) for p in _git_tracked()],
                explicit=False,
            )
        )
    return sources


# ==================================================================================================
# Entry point
# ==================================================================================================


def _parse_require_flag(argv: list[str]) -> tuple[bool, int | dict[str, int] | None, list[str]]:
    """Pull ``--require-tokens[=N]`` out of argv, returning (require, floor, remaining args).

    A hook framework can pass ARGS to a hook but usually has no per-hook environment, so this flag
    is the only way to make the COMMIT-time gate fail closed. Without it, a fresh clone or a new
    worktree -- neither of which carries the ignored token file -- runs every commit with zero token
    detectors and reports success.
    """
    require = False
    minimum: int | dict[str, int] | None = None
    rest: list[str] = []
    for arg in argv:
        if arg == "--require-tokens":
            require = True
        elif arg.startswith("--require-tokens="):
            require, minimum = True, parse_min_spec(arg.split("=", 1)[1])
        elif arg.startswith("--") and arg != "--path":
            # Refuse an unknown flag rather than treating it as a filename. Falling through put an
            # unrecognised token in the file list, and the run silently became a scan of a
            # nonexistent file. A typo'd flag must fail loudly, not quietly scan nothing.
            raise UsageError(f"unknown option {arg!r}")
        else:
            rest.append(arg)
    return require, minimum, rest


#: Values accepted as "on". An exact ``== "1"`` compare means a well-meant ``true``/``yes`` silently
#: disables the gate while looking configured.
_TRUTHY = frozenset({"1", "true", "yes", "on"})


def _mode_marker() -> str:
    """The posture suffix printed on both the loaded line and the scanned line.

    Never inferred from silence. A structural-only run and a fully armed run both exit 0 on a clean
    tree, and the ONLY thing that distinguishes them in a log is this string.
    """
    if TOKENS_PRESENT:
        return ""
    return (
        "  [STRUCTURAL-ONLY: no token source configured - shape detectors are armed, "
        "private-name detectors are NOT]"
    )


def main(argv: list[str]) -> int:
    reload_tokens()
    show_context = "--show-context" in argv
    rest = [a for a in argv if a != "--show-context"]
    try:
        flag_require, minimum, rest = _parse_require_flag(rest)
    except (UsageError, ValueError) as exc:
        print(f"{TOOL}: {exc}", file=sys.stderr)
        return 2

    # Announce what LOADED before any refusal, so a failure shows the counts that caused it.
    counts = loaded_token_counts()
    print(
        f"{TOOL}: loaded " + ", ".join(f"{k}={v}" for k, v in counts.items()) + _mode_marker(),
        file=sys.stderr,
    )

    env_require = os.environ.get("CCX_REQUIRE_TOKENS", "").strip()
    if env_require and env_require.lower() not in _TRUTHY:
        print(
            f"{TOOL}: CCX_REQUIRE_TOKENS={env_require!r} is not a recognised value "
            f"({'/'.join(sorted(_TRUTHY))}) - refusing rather than silently running unguarded.",
            file=sys.stderr,
        )
        return 2
    require = flag_require or env_require.lower() in _TRUTHY
    if minimum is None:
        env_min = os.environ.get("CCX_MIN_DETECTORS", "").strip()
        if env_min:
            try:
                minimum = parse_min_spec(env_min)
            except ValueError as exc:
                print(f"{TOOL}: CCX_MIN_DETECTORS: {exc}", file=sys.stderr)
                return 2
            # Asking for a floor implies requiring tokens; otherwise a floor set without the flag is
            # silently inert -- another gate that cannot fail.
            require = True

    if require:
        why = token_floor_failure(minimum)
        if why is not None:
            print(f"{TOOL}: {why} (fail closed).", file=sys.stderr)
            return 2

    try:
        sources = collect(rest)
    except (UsageError, subprocess.CalledProcessError, OSError) as exc:
        print(f"{TOOL}: cannot determine what to scan: {exc}", file=sys.stderr)
        return 2

    hits: list[str] = []
    for source in sources:
        for path, rel in source.files:
            if set(Path(rel).parts) & SKIP_DIRS or _is_skipped(path, rel):
                source.policy_skipped += 1
                continue
            if not path.is_file():
                source.absent += 1
                continue
            source.scanned += 1
            hits.extend(scan_file(path, rel, show_context=show_context))

    total = sum(s.scanned for s in sources)

    # Report what was SCANNED, always, pass or fail. Together with the loaded line above, these two
    # numbers are the whole receipt: a zero in either one is the difference between "found nothing"
    # and "looked at nothing", and exit 0 cannot tell them apart.
    detail = ", ".join(f"{s.label}={s.scanned}" for s in sources) if len(sources) > 1 else ""
    print(
        f"{TOOL}: scanned {total} file(s)"
        + (f" [{detail}]" if detail else "")
        + _mode_marker(),
        file=sys.stderr,
    )

    # An EXPLICIT source that yielded nothing is reported BY NAME even when other sources scanned
    # fine. The original of this gate only refused when EVERYTHING was dropped, so a file argument
    # mixed with a good directory vanished without a word and the run exited 0. A source the caller
    # named and the scanner never opened is a false clean for that source, whatever the others did.
    barren = [s for s in sources if s.explicit and s.scanned == 0]
    if barren:
        print(f"{TOOL}: these arguments contributed ZERO scanned files:", file=sys.stderr)
        for s in barren:
            print(f"  {s.label}: {s.why_empty()}", file=sys.stderr)
        print(f"{TOOL}: refusing to report a clean scan for them (fail closed).", file=sys.stderr)
        return 2

    if total == 0:
        # No explicit source, so this is the tracked listing coming back empty: wrong directory, not
        # a repository, or a checkout with nothing in it. A pass here would be pure vacuum.
        print(
            f"{TOOL}: examined ZERO files - nothing was scanned, so nothing can be certified "
            "clean. Refusing (fail closed).",
            file=sys.stderr,
        )
        return 2

    absent = sum(s.absent for s in sources)
    if absent:
        print(
            f"{TOOL}: note - {absent} listed file(s) were not present on disk and were NOT scanned.",
            file=sys.stderr,
        )

    if hits:
        print("FORBIDDEN CONTENT -- blocked (fail closed):", file=sys.stderr)
        for h in hits:
            print(f"  {h}", file=sys.stderr)
        print(
            f"\n{len(hits)} hit(s). A real path, host or name must be REMOVED, not allowlisted. "
            "For a genuine false positive, narrow the pattern or add a vetted line to "
            "scripts/security/scan-allowlist.txt.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
