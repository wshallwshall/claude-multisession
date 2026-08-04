#!/usr/bin/env python3
"""Push guard -- refuse a DIRECT push to a protected ref.

THE INVARIANT IT ENFORCES. Work reaches trunk through a pull request. Nothing else.

Why locally, when a server can enforce the same thing: this fails FAST, with an explanation, before
the round trip -- and it is the only copy of the rule that exists on a machine whose remote has no
protection configured at all. The realistic trigger was never malice, it is one click: an editor's
Sync/Push button does not distinguish "my feature branch" from trunk, and the editor is where most
pushes originate.

WHAT THIS IS NOT. A guardrail, not a security boundary. `git push --no-verify` skips it, and it is
installed per clone, so any other checkout is governed only by whatever the server enforces.
Configure server-side protection too; this is the part that tells you before you wait.

WHICH REFS. `protectedRefs` in ccx.config.json, defaulting to `main` and `master`. An entry may be
written either way (`main` or `refs/heads/main`). An explicitly EMPTY list is not the same as an
absent key: `[]` says "this repository deliberately protects nothing" and disables the guard *with a
message on stderr*, because a guard that is off must never look like a guard that passed. A missing
key means nobody chose, and gets the defaults.

git hands a pre-push hook one line per ref on STDIN:
    <local ref> <local sha> <remote ref> <remote sha>
A deletion has an all-zero local sha; it is refused too, since deleting trunk is worse than pushing
to it. Exit 0 allows the push, 1 refuses it.

Stdlib only, like the other gates -- most worktrees have no virtualenv. ASCII output only.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from _ccxconfig import load_config
except ImportError as exc:  # pragma: no cover - only fires on a partial copy
    sys.stderr.write(
        f"\nccx push guard: cannot import _ccxconfig.py from {Path(__file__).parent} ({exc}).\n"
        "  This guard and its substrate ship together. Copy both, or reinstall the git hooks.\n\n"
    )
    raise SystemExit(1) from exc

#: Used when ccx.config.json has no `protectedRefs` key, or could not be read at all. The default is
#: the strict direction on purpose: a guard that cannot read its configuration must not become a
#: guard that permits everything.
_DEFAULT_PROTECTED = ("refs/heads/main", "refs/heads/master")


def _normalise(ref: str) -> str:
    ref = ref.strip()
    if not ref:
        return ""
    return ref if ref.startswith("refs/") else f"refs/heads/{ref}"


def _protected() -> tuple[frozenset[str], str]:
    """The protected set, and a short phrase naming where it came from.

    The provenance is not decoration. When this guard refuses a push, the first question is "why is
    that ref protected?", and the answer is either a file the reader can edit or a default they did
    not know about.
    """
    try:
        cfg = load_config()
    except ValueError as exc:
        sys.stderr.write(f"ccx push guard: {exc}\n  Falling back to the built-in protected refs.\n")
        return frozenset(_DEFAULT_PROTECTED), "built-in default"
    if cfg is None:
        return frozenset(_DEFAULT_PROTECTED), "built-in default (no ccx.config.json found)"

    node = cfg.raw.get("protectedRefs")
    if not isinstance(node, list):
        return frozenset(_DEFAULT_PROTECTED), "built-in default"
    refs = frozenset(r for r in (_normalise(str(x)) for x in node) if r)
    return refs, f"protectedRefs in {cfg.path}"


def main(argv: list[str]) -> int:
    # Escape hatch for the rare legitimate case, deliberately distinct from --no-verify so that it
    # is greppable in shell history and cannot be triggered by muscle memory.
    if os.environ.get("CCX_ALLOW_DIRECT_PUSH") == "1":
        print("push_guard: CCX_ALLOW_DIRECT_PUSH=1 -- direct push ALLOWED.", file=sys.stderr)
        return 0

    protected, source = _protected()
    if not protected:
        # Configured off. Say it out loud every time: an inert guard that prints nothing is
        # byte-identical to a guard that inspected the push and approved it.
        print(
            "push_guard: protectedRefs is empty -- NOT enforcing any protected ref.",
            file=sys.stderr,
        )
        return 0

    offenders: list[tuple[str, bool]] = []
    for line in sys.stdin:
        parts = line.split()
        if len(parts) != 4:
            continue
        local_sha, remote_ref = parts[1], parts[2]
        # A local sha of all zeroes is git's way of saying "this push deletes the remote ref".
        if remote_ref in protected:
            offenders.append((remote_ref, local_sha.strip("0") == ""))

    if not offenders:
        return 0

    print("", file=sys.stderr)
    print("ccx push guard -- REFUSED", file=sys.stderr)
    for ref, is_delete in offenders:
        what = "DELETE" if is_delete else "direct push"
        print(f"  {what} to {ref}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        f"  Protected refs come from: {source}\n"
        "\n"
        "  Work reaches a protected ref through a pull request. A direct push skips review, and on\n"
        "  a published branch it cannot be taken back -- deleting the ref later does not un-publish\n"
        "  what was fetched, mirrored or indexed in between.\n"
        "\n"
        "  Push a branch and open a PR instead:\n"
        "      git switch -c <branch> && git push -u origin <branch>\n"
        "\n"
        "  If you genuinely mean it:  CCX_ALLOW_DIRECT_PUSH=1 git push ...",
        file=sys.stderr,
    )
    print("", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
