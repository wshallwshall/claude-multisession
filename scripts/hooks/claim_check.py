#!/usr/bin/env python3
"""Claim gate -- stop two sessions building the same numbered item in parallel.

`seq_check.py` stops two sessions taking the same NUMBER. This stops them doing the same WORK. On
the repository this was developed in, three sessions independently fixed the same dependency
advisory; two of the three pull requests were closed as duplicates. Nothing in git could have
noticed: three branches, three sets of files, no textual conflict anywhere.

The rule, deliberately narrow so it never fights you:

    A commit whose SUBJECT declares it implements `<KIND> #N`, and whose staged diff touches CODE,
    must hold a claim on N for THIS worktree.

`<KIND>` is any sequence name from ccx.config.json ("adr", "backlog", "issue", ...), matched
case-insensitively. Configure no sequences and this gate is inert by construction.

Three scoping decisions, each load-bearing:

* **Subject line only.** A body may reference other items freely -- commit bodies routinely cite the
  item they supersede or were found by. Enforcing on the body would fire on every one of those. The
  subject is where a commit *declares* what it implements.
* **Code-touching diffs only.** Banner flips, doc corrections and ledger reconciles legitimately
  cite an item without building it, and they are exactly the commits a coordination gate must not
  block. What counts as documentation is `docPaths` in ccx.config.json (optional; the default is
  `docs/`, `.github/` and any `*.md`).
* **Numbered items only.** Free-text claims (`claim.ps1 -Take auth-token-refresh`) are advisory --
  surfaced at session start, not enforced here, because there is no reliable way to map an arbitrary
  diff to a topic. Visibility is the win there; enforcement would be guesswork.

FAIL-CLOSED, ON PURPOSE, IN TWO PLACES. A malformed or unreadable claim reads as UNCLAIMED, so the
gate asks for a claim rather than passing on a corrupt one; and a git failure refuses the commit
with a message rather than being swallowed into "nothing is staged", which would read as a pass.
Both are recoverable in one command; a false clean is not recoverable at all, because nobody looks.

CLAIM KEYS ARE FLAT. A claim is `<state-root>/claims/<item>.json`, keyed by the item token as a
human types it into `claim.ps1 -Take <item>`. So two sequences that both number from 1 share one
claim namespace: `adr #N` and `backlog #N` are one claim. That is a deliberate trade -- the key a
person types stays the key on disk -- and it is worth knowing before you configure two sequences
whose numbers overlap.

Run as a git `commit-msg` hook (argv[1] = the message file). It CANNOT be a pre-commit hook:
pre-commit never receives the commit message, so the check would look installed and silently never
fire.

Stdlib only, no project import: most worktrees have no virtualenv, and a gate that silently skips is
worse than no gate. ASCII output only, matching the rest of the hooks.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from _ccxconfig import GitError, fold_path, git, load_config, repo_root, safe_name, state_root
except ImportError as exc:  # pragma: no cover - only fires on a partial copy
    # Loud, not silent. A hook that cannot import its own substrate has to say so, because the
    # alternative -- exiting 0 -- is byte-identical to "checked, all clear".
    sys.stderr.write(
        f"\nccx claim gate: cannot import _ccxconfig.py from {Path(__file__).parent} ({exc}).\n"
        "  This gate and its substrate ship together. Copy both, or reinstall the git hooks.\n\n"
    )
    raise SystemExit(1) from exc

#: A paired commit names both items on one line -- `(BACKLOG #N, #M)` -- so once the kind token
#: appears in the subject, every number after it on that line counts. Otherwise the second item of
#: the pair slips through unclaimed.
_ITEM = re.compile(r"#(\d{1,5})\b")

#: A commit touching ONLY these is documentation work: it may cite an item without implementing it.
#: Override per repository with an optional `docPaths` object in ccx.config.json:
#:     "docPaths": { "prefixes": ["doc/", "adr/"], "suffixes": [".md", ".rst"] }
_DEFAULT_DOC_PREFIXES = ("docs/", ".github/")
_DEFAULT_DOC_SUFFIXES = (".md",)


def _staged_paths() -> list[str]:
    out = git("diff", "--cached", "--name-only")
    return [p.strip().replace("\\", "/") for p in out.splitlines() if p.strip()]


def _touches_code(paths: list[str], prefixes: tuple[str, ...], suffixes: tuple[str, ...]) -> bool:
    """True if any staged path is not documentation.

    An empty diff counts as no code (an `--amend` of a message, for instance), so a message-only
    fixup is never blocked.
    """
    for p in paths:
        if prefixes and p.startswith(prefixes):
            continue
        if suffixes and p.endswith(suffixes):
            continue
        return True
    return False


def _doc_paths(raw: dict[str, object]) -> tuple[tuple[str, ...], tuple[str, ...]]:
    node = raw.get("docPaths")
    if not isinstance(node, dict):
        return _DEFAULT_DOC_PREFIXES, _DEFAULT_DOC_SUFFIXES
    prefixes = node.get("prefixes")
    suffixes = node.get("suffixes")
    # An explicitly EMPTY list is not the same as an absent key. `"prefixes": []` says "no path
    # prefix makes a commit documentation-only", and it must be honoured as written; a missing key
    # says "I did not think about this", and gets the default.
    out_p = (
        tuple(str(x) for x in prefixes) if isinstance(prefixes, list) else _DEFAULT_DOC_PREFIXES
    )
    out_s = (
        tuple(str(x) for x in suffixes) if isinstance(suffixes, list) else _DEFAULT_DOC_SUFFIXES
    )
    return out_p, out_s


def _holder(claims_dir: Path, item: str) -> dict[str, object] | None:
    """The claim record for `item`, or None if unclaimed/unreadable.

    A malformed claim reads as UNCLAIMED on purpose: the gate then asks for a claim rather than
    silently passing on a corrupt one. A non-object payload (a bare list or string) is treated the
    same way -- it cannot name a holder, so it grants nothing.
    """
    f = claims_dir / f"{safe_name(item)}.json"
    try:
        loaded = json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return loaded if isinstance(loaded, dict) else None


def main(argv: list[str]) -> int:
    if not argv:
        return 0  # not wired as a commit-msg hook; do nothing rather than guess
    try:
        message = Path(argv[0]).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return 0

    try:
        cfg = load_config()
    except ValueError as exc:
        sys.stderr.write(f"\nccx claim gate: {exc}\n\n")
        return 1
    if cfg is None:
        # Installed into a repository that never opted in. Say so once rather than exiting 0
        # silently, because a silent skip is indistinguishable from a clean pass.
        sys.stderr.write(
            "ccx claim gate: no ccx.config.json at or above this worktree -- not enforcing.\n"
        )
        return 0

    kinds = sorted(cfg.sequences)
    if not kinds:
        return 0  # no sequences configured: there are no numbered items to claim

    subject = next((ln for ln in message.splitlines() if ln.strip() and not ln.startswith("#")), "")
    token = re.compile(r"\b(" + "|".join(re.escape(k) for k in kinds) + r")\b", re.IGNORECASE)
    m = token.search(subject)
    if not m:
        return 0
    kind = m.group(1)
    items = _ITEM.findall(subject[m.start() :])
    if not items:
        return 0

    try:
        prefixes, suffixes = _doc_paths(cfg.raw)
        if not _touches_code(_staged_paths(), prefixes, suffixes):
            return 0  # documentation-only: cites the item, does not build it
        claims_dir = state_root(cfg.prefix) / "claims"
        me = fold_path(repo_root())
    except GitError as exc:
        # Fail CLOSED. A swallowed git failure here reads as "nothing is staged", which reads as a
        # pass -- on the one check whose whole purpose is never to emit one.
        sys.stderr.write(f"\nccx claim gate: could not inspect the repository -- {exc}\n\n")
        return 1

    problems: list[str] = []
    for item in dict.fromkeys(items):  # de-dupe, keep order
        claim = _holder(claims_dir, item)
        if claim is None:
            problems.append(
                f"  {kind} #{item} is NOT CLAIMED.\n"
                "      Another session may already be building it -- that is the duplicate work this\n"
                "      gate exists to stop. Claim it, then commit again:\n"
                f'          pwsh -NoProfile -File scripts/coord/claim.ps1 -Take {item} -Note "<what>"'
            )
            continue
        if fold_path(str(claim.get("worktree", ""))) != me:
            problems.append(
                f"  {kind} #{item} is claimed by ANOTHER worktree:\n"
                f"      held by: {claim.get('worktree')} [{claim.get('branch')}]\n"
                f"      since  : {claim.get('claimed')}\n"
                f"      note   : {claim.get('note')}\n"
                "      Do not build it in parallel. Coordinate with that session, or if it is dead:\n"
                f"          pwsh -NoProfile -File scripts/coord/claim.ps1 -Release {item} -Force"
            )

    if not problems:
        return 0

    sys.stderr.write("\nccx claim gate\n\n")
    sys.stderr.write("\n\n".join(problems))
    sys.stderr.write(
        "\n\n  See who is building what:  pwsh -NoProfile -File scripts/coord/claim.ps1 -List\n"
        f"  This fires only on a code-touching commit whose SUBJECT says '{kind} #N'.\n"
        "  A documentation-only commit (banner flip, ledger reconcile) is never blocked.\n\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
