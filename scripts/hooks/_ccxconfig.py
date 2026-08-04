#!/usr/bin/env python3
"""Shared substrate for the Python git hooks: config discovery, the git runner, path folding.

WHY THIS FILE EXISTS. `scripts/coord/_common.ps1` does this job for the PowerShell side, and it
exists because five copies of "resolve the git common dir" had drifted into five behaviours. The
Python gates cannot dot-source PowerShell, so this is the minimum counterpart. The two sides must
agree on exactly three things, and every one of them is load-bearing:

  * WHERE THE CONFIG IS. `ccx.config.json` at the repository root, found by walking up, with
    $CCX_CONFIG short-circuiting the walk. The file is both the knob file and the opt-in marker:
    these hooks are installed into a shared .git/hooks that governs every worktree of the clone,
    so "is this repository governed?" has to be answerable without running anything.
  * WHAT THE STATE ROOT IS. `<git-common-dir>/<prefix>-coord`. Identical across worktrees (a claim
    taken in one is visible in another), isolated per clone (two clones cannot collide), and
    uncommittable (no `git add -A` can sweep coordination state into a commit).
  * HOW A PATH IS FOLDED FOR COMPARISON. Both sides compare worktree paths against records the
    other side wrote. If they fold differently, ownership silently stops matching and the gates
    either refuse everything or grant everything.

THE FOLDED FORM IS FOR COMPARISON ONLY. Never hand it to git, to the filesystem, or to a message a
human reads -- keep the raw string for those. Case-folding is conditional on the platform because
on a case-sensitive filesystem `/tmp/Primary` and `/tmp/primary` really are two directories, and
folding them together would make a gate govern a directory it was never pointed at.

Stdlib only, and no import of the surrounding project. These run as git hooks in worktrees that may
have no virtualenv and no project install; a gate that skips because an import failed is worse than
no gate, because it still looks installed.

Output convention for every Python hook in this directory: ASCII only. The PowerShell hooks are
ASCII-only because a console that is not UTF-8 renders their output as mojibake, and one convention
across the set beats two.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

#: The knob file and the opt-in marker, in one.
CONFIG_NAME = "ccx.config.json"

#: The prefix becomes a directory name, a git config key and an environment-variable stem. Reject
#: anything that would need escaping in any of those, here, once -- rather than producing a state
#: root nobody can type.
_PREFIX_OK = re.compile(r"^[A-Za-z][A-Za-z0-9-]{0,31}$")

#: Mirrors $script:CcxCaseInsensitiveFs in _common.ps1. Keep the two in step.
CASE_INSENSITIVE_FS = sys.platform in ("win32", "darwin")


class GitError(RuntimeError):
    """A git invocation exited non-zero. Deliberately never swallowed -- see :func:`git`."""


def git(*args: str, cwd: str | Path | None = None) -> str:
    """Run git and return stdout. Raises :class:`GitError` on a non-zero exit.

    TWO NON-OBVIOUS RULES LIVE HERE, and both were paid for.

    1. `encoding=` is REQUIRED, not cosmetic. `text=True` alone decodes with the LOCALE default,
       which is cp1252 on a stock Windows box. Ledger and index files are routinely UTF-8 (em
       dashes, arrows, emoji), so the decode raised inside subprocess's reader thread,
       `proc.stdout` came back **None**, and the caller died on `findall(None)` -- blocking every
       commit that touched the files the gate guards. The gate's own failure mode was the one it
       exists to prevent: silent, and worst on exactly the files it looks at.

    2. A non-zero exit RAISES. A git failure (bad ref, missing path, unfetched base) must never
       read as "the file is empty", because an empty ledger parses as "no numbers taken" -- the
       false clean that a collision gate must never emit. Callers that have a legitimate "the path
       is simply not on that ref" case probe for it explicitly with :func:`object_exists` instead
       of wrapping this in a broad `except`.
    """
    proc = subprocess.run(  # nosec B603 B607 - fixed argv, no shell, no caller-supplied executable
        ["git", *args],
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        raise GitError(
            f"git {' '.join(args)} failed ({proc.returncode}): {(proc.stderr or '').strip()}"
        )
    return proc.stdout or ""


def object_exists(spec: str, cwd: str | Path | None = None) -> bool:
    """Does the `<ref>:<path>` (or any other) object exist? Probed EXPLICITLY, not inferred.

    :func:`git` raises on any non-zero exit on purpose. "Absent from that ref" is the one case that
    is not a failure, so it gets its own probe rather than a broad `except` that would also hide a
    genuinely broken ref.
    """
    probe = subprocess.run(  # nosec B603 B607 - fixed argv, no shell
        ["git", "cat-file", "-e", spec],
        cwd=str(cwd) if cwd else None,
        capture_output=True,
    )
    return probe.returncode == 0


def git_common_dir(cwd: str | Path | None = None) -> Path:
    """The SHARED git directory -- the same path from every worktree of this clone.

    `--path-format=absolute` is not optional. Without it git may answer a relative `.git`, which the
    caller then joins onto whatever directory the hook process happened to start in.
    """
    return Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd).strip())


def repo_root(cwd: str | Path | None = None) -> Path:
    """The working tree root of the worktree we are running in (NOT the primary checkout)."""
    return Path(git("rev-parse", "--path-format=absolute", "--show-toplevel", cwd=cwd).strip())


def find_config(start: str | Path | None = None) -> Path | None:
    """Locate `ccx.config.json` by walking up from `start`. Returns None if there is none.

    Never raises: a hook may call this in an unrelated repository on every commit and must stay
    inert there. $CCX_CONFIG names the file directly and short-circuits the walk, which is how the
    tests and the doctor point at a fixture.
    """
    override = os.environ.get("CCX_CONFIG")
    if override:
        p = Path(override)
        return p.resolve() if p.is_file() else None

    try:
        cur = Path(start or os.getcwd()).resolve()
    except OSError:
        return None
    if cur.is_file():
        cur = cur.parent

    # Bounded walk. `while True` on a UNC path or a mount point can sit on the same string forever;
    # compare the parent to the child and stop when it stops changing.
    while True:
        candidate = cur / CONFIG_NAME
        if candidate.is_file():
            return candidate
        parent = cur.parent
        if parent == cur:
            return None
        cur = parent


def load_config(start: str | Path | None = None) -> SimpleNamespace | None:
    """Load `ccx.config.json`, or return None if this repository has not opted in.

    Returns a namespace with every documented key materialised, plus `raw` (the parsed JSON) for the
    handful of optional keys the shipped config does not carry. `sequences` absent and `sequences`
    empty mean the same thing on purpose: the sequence machinery is off, and a caller must not treat
    that as an error.

    Raises ValueError on a config that exists but cannot be read. That is deliberate and
    fail-closed: a governed repository whose configuration is corrupt must stop, not quietly run
    with defaults that nobody chose.
    """
    path = find_config(start)
    if path is None:
        return None

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        # Name the file. A parse error reported without the path sends the reader looking in the
        # wrong repository, because the walk above may have found a config several levels up.
        raise ValueError(f"{path} could not be read as JSON: {exc}") from exc
    if not isinstance(raw, dict):
        raise ValueError(f"{path} must contain a JSON object at the top level.")

    prefix = str(raw.get("prefix") or "ccx")
    if not _PREFIX_OK.match(prefix):
        raise ValueError(
            f"{path}: prefix '{prefix}' is not usable. It becomes a directory name, a git config "
            "key and an environment-variable stem, so it must start with a letter and contain only "
            "letters, digits and hyphens."
        )

    sequences = raw.get("sequences") or {}
    if not isinstance(sequences, dict):
        raise ValueError(f"{path}: 'sequences' must be an object mapping a name to its definition.")

    return SimpleNamespace(
        prefix=prefix,
        trunk=str(raw.get("trunk") or "auto"),
        sequences=sequences,
        raw=raw,
        path=path,
        root=path.parent,
    )


def state_root(prefix: str, cwd: str | Path | None = None) -> Path:
    """`<git-common-dir>/<prefix>-coord`. NOT created here -- readers must not mint state.

    Its corollary is deliberate and occasionally surprising: STATE OUTLIVES THE WORKTREE. Remove a
    worktree and the claims it took are still there, which is why they are released on evidence
    rather than on a timer.
    """
    return git_common_dir(cwd) / f"{prefix}-coord"


def fold_path(p: str | Path | None) -> str:
    """Canonicalise a path into the one form all path comparisons use. '' if it cannot.

    Canonicalisation is the point, not the lower-casing: without it `<primary>-work/../<primary>/x`
    does not string-match the primary and walks straight through a check whose whole job is to
    notice it.
    """
    if not p:
        return ""
    try:
        full = os.path.abspath(str(p))
    except (OSError, ValueError):
        # "We cannot say what this points at", which every caller reads as "not a match".
        return ""
    norm = full.replace("\\", "/").rstrip("/")
    return norm.lower() if CASE_INSENSITIVE_FS else norm


def safe_name(name: str) -> str:
    """Fold free text into a filename-safe slug. '' if nothing usable survives.

    MUST match ConvertTo-CcxSafeName in _common.ps1 character for character. A claim key becomes a
    FILENAME and the filename is the mutual-exclusion primitive, so two spellings of one key have to
    fold to one file or the claim does not exclude anything. Folding is unconditionally lower-case
    here (unlike path comparison above) because this is a name being minted rather than a path the
    filesystem already assigned.

    Callers must reject '' rather than substituting a default: a name that reduces to nothing is a
    caller bug, and silently coining one produces a claim everybody shares.
    """
    if not name:
        return ""
    return re.sub(r"[^a-z0-9._-]+", "-", name.strip().lower()).strip("-")
