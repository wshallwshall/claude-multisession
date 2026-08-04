#!/usr/bin/env python3
"""EXAMPLE ONLY -- NOT WIRED, NOT INSTALLED, NOT IMPORTED BY ANYTHING.

This is the original ledger gate the shipped `scripts/hooks/seq_check.py` was distilled from, kept
here with its comments intact because THE COMMENTS ARE THE TRANSFERABLE PART. Three of them cost
real outages and none of them is obvious from the code:

  * why CI must use a TWO-dot diff and not a three-dot one, and how the three-dot failure was
    SILENT (it reported PASS on every run where it could not see);
  * why `encoding=` on the subprocess call is required rather than cosmetic, and how omitting it
    blocked every commit that touched exactly the files the gate guards;
  * why a swallowed git failure is the worst possible bug in a gate like this -- "the command
    failed" and "the ledger is empty" become the same observation, and an empty ledger reads as
    "no numbers are taken".

Every rule below is one repository's document layout. That is the reason it ships as an example and
not as a hook: `docs/adr/NNNN-*.md`, a markdown index table with a particular row shape, `## N.`
headings in one long file, an archive directory beside it. The live gate takes the same mechanism
and drives it entirely from `ccx.config.json`, so a repository can describe its own layout instead of
inheriting this one.

Two things present in the original are deliberately NOT reproduced here:

  * A project-specific reserved number space: a floor constant below which new items were refused,
    because part of the range was spoken for by something this file could not see. It was the single
    least portable rule in the file, and it was cross-coupled: the allocator regex-parsed the
    constant's source line at runtime so the two could not disagree. That coupling is worth knowing
    about as a hazard; it is not worth copying. The general point does survive -- see the note on
    :meth:`check_backlog` for why any such floor has to be a one-way ratchet.
  * Commit hashes and item numbers cited as evidence. They resolve in no repository you have.

Do not install this file. If you want the behaviour, configure `sequences` in ccx.config.json and
use `scripts/hooks/seq_check.py`.

---

Ledger gate -- stop two concurrent sessions from silently colliding on an ADR / BACKLOG number.

THE DEFECT THIS EXISTS FOR. Two sessions each grep for "the next free number", both pick N, and
create DIFFERENTLY-NAMED files (docs/adr/0004-alpha.md and docs/adr/0004-beta.md, or two `## 58.`
headings far apart in BACKLOG.md). Git merges both **cleanly** -- there is no textual conflict --
and the ledger is quietly corrupt. It happened three times on the repository this was developed in,
and it is the one measured collision class that a worktree, a file lock, and `git merge-tree` are
all blind to.

WHY A GIT PRE-COMMIT HOOK. Installed into the SHARED .git/hooks, one copy governs EVERY worktree at
once -- no branch, no merge, no propagation lag -- and it sees every write route (an editor, a shell
redirect, an agent's file-write tool, a subagent), because it inspects the TREE at commit time
rather than a tool call. The `--ci` mode re-runs the same rules against a freshly fetched trunk,
which is what catches the STALE-BASE collision: each branch is internally consistent, and the
duplicate only exists once both have merged.

Reads the STAGED tree (`git show :path`), never the working tree -- otherwise an untracked
work-in-progress ADR sitting in your checkout would block every unrelated commit.

Stdlib only, no project import: most worktrees have no virtualenv, and a gate that silently skips is
worse than no gate. `git commit --no-verify` is the escape hatch; the --ci run is the backstop for it.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ADR_FILE = re.compile(r"^docs/adr/(\d{4})-[^/]+\.md$")
INDEX_ROW = re.compile(r"^\|\s*\[(\d{4})\]", re.M)
BACKLOG_HEADING = re.compile(r"^#{2,3} (\d+)\.", re.M)

# THE ITEM NUMBER SPACE SPANS MORE THAN ONE FILE.
#
# docs/BACKLOG.md carries the OPEN items; retired ones are moved verbatim into docs/archive/backlog/.
# A number is taken if it appears in EITHER, so every rule below reads their union. Keying on the one
# primary path was safe only while it was the only path, and would leave the archive an unpoliced
# region: a commit touching only the archive would early-return having checked nothing, and two
# sessions could file the same number there and merge clean -- the exact collision this gate exists
# to stop, reintroduced through the back door of a file it does not look at.
#
# Reading the union on BOTH sides also disposes of a false positive that a base-only view would
# create: the move commit RELOCATES a large batch of items, so head-union == base-union and
# `head - base` is empty. A per-file view would instead see all of those numbers vanish from
# BACKLOG.md and, on any worktree whose base straddles the move, report them -- with a remedy that
# would renumber cited items.
BACKLOG_PATH = "docs/BACKLOG.md"
BACKLOG_ARCHIVE_DIR = "docs/archive/backlog"


def git(*args: str) -> str:
    # encoding= is REQUIRED, not cosmetic: `text=True` alone decodes with the LOCALE default, which is
    # cp1252 on a stock Windows box. docs/BACKLOG.md and docs/adr/README.md are UTF-8 (em-dashes,
    # check marks, warning signs), so the decode raised inside subprocess's reader thread,
    # `proc.stdout` came back **None**, and the caller died on `findall(None)` -- blocking every
    # commit that touched either ledger file. The gate's own failure mode was the one it exists to
    # prevent: silent, and worst on the files it guards.
    proc = subprocess.run(  # nosec B603 B607 - fixed argv, no shell, no caller-supplied executable
        ["git", *args], capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    # A git failure (bad ref, missing path) must not read as "the file is empty" -- an empty ledger
    # parses as "no numbers taken", which is exactly the false-clean this gate must never emit.
    if proc.returncode != 0:
        raise OSError(
            f"git {' '.join(args)} failed ({proc.returncode}): {(proc.stderr or '').strip()}"
        )
    return proc.stdout or ""


def _obj_exists(spec: str) -> bool:
    """Does the `<ref>:<path>` object exist? Probed EXPLICITLY rather than inferred from an error.

    :func:`git` raises on any non-zero exit deliberately -- a swallowed failure would read as "empty
    ledger", i.e. "no numbers taken", the false-clean this gate exists to prevent. "The path is simply
    not on that ref" is the one case that is NOT a failure, so it gets its own probe instead of a
    broad ``except``.
    """
    probe = subprocess.run(  # nosec B603 B607 - fixed argv, no shell
        ["git", "cat-file", "-e", spec], capture_output=True
    )
    return probe.returncode == 0


class Ledger:
    def __init__(self, *, ci: bool, base: str = "origin/main") -> None:
        self.ci = ci
        self.base = base
        self.repo = Path(git("rev-parse", "--path-format=absolute", "--show-toplevel").strip())
        common = git("rev-parse", "--path-format=absolute", "--git-common-dir").strip()
        # The registry lives beside the SHARED object store, so every worktree of this repo sees the same
        # allocations -- and a different clone gets its own, automatically.
        self.alloc = Path(common) / "ccx-coord" / "alloc"
        self.failures: list[str] = []

    # -- tree access ---------------------------------------------------------------------------------
    #
    # CI uses a TWO-dot diff (`base HEAD`), deliberately, not three-dot (`base...HEAD`).
    #
    # On a pull request the checkout action checks out the MERGE commit -- HEAD already CONTAINS base. So
    # three-dot bought nothing here, and it cost everything: it resolves a MERGE BASE, the checkout is
    # shallow (depth 1), and two truncated histories routinely fail to reach their common ancestor --
    # `fatal: no merge base`. Deepening to fix that is a race (`fatal: shallow file has changed since we
    # read it`) and needs a full history to be reliable.
    #
    # A two-dot diff compares two TREES. No ancestry, no depth, nothing to race. Against the merge commit
    # it yields exactly "what this change adds on top of base", which is the question the gate asks.
    #
    # This mattered more than it looks: the three-dot failure was SILENT. git() used to swallow a nonzero
    # exit and return "", so added_files() was [] and the gate reported PASS on every run where it could
    # not see. A false clean, on the one check whose whole purpose is never to emit one.
    def added_files(self) -> list[str]:
        """Files ADDED by this change. In CI, HEAD is the change merged into base."""
        if self.ci:
            return git("diff", "--name-only", "--diff-filter=A", self.base, "HEAD").split()
        return git("diff", "--cached", "--name-only", "--diff-filter=A").split()

    def changed_files(self) -> list[str]:
        if self.ci:
            return git("diff", "--name-only", self.base, "HEAD").split()
        return git("diff", "--cached", "--name-only").split()

    def head_text(self, path: str) -> str:
        """The file as it will exist after this commit -- the INDEX, not the working tree."""
        return git("show", f"HEAD:{path}") if self.ci else git("show", f":{path}")

    def base_text(self, path: str) -> str:
        return git("show", f"{self.base}:{path}")

    def base_has(self, path: str) -> bool:
        """Does the base ref contain ``path`` at all?

        A ledger file being ADDED legitimately has no base version, and `git show base:path` exits 128
        for that -- indistinguishable, to :func:`git`, from a real failure, which it must keep raising on
        (an error swallowed as "empty ledger" reads as "no numbers taken", the false-clean this gate
        exists to prevent). So absence is probed EXPLICITLY here, and only after the base ref itself is
        verified -- otherwise a bad/unfetched base would quietly answer "absent" and disable the check.
        """
        git("rev-parse", "--verify", f"{self.base}^{{commit}}")
        return _obj_exists(f"{self.base}:{path}")

    def head_has(self, path: str) -> bool:
        """Does the commit under test contain ``path``? Mirrors :meth:`head_text`'s ref.

        The symmetric case to :meth:`base_has`, and it bites the moment a ledger file is FIRST
        added. In CI the change set is `diff base HEAD`, so once trunk gains a file that a branch
        predates, that branch's diff lists it -- as a DELETION relative to base -- even though the
        branch never touched it. The rule then reads HEAD for a copy that was never there and
        `git show HEAD:path` exits 128. That is not a ledger violation; it is a stale branch, and it
        broke every open branch the hour the file landed.
        """
        return _obj_exists(f"HEAD:{path}" if self.ci else f":{path}")

    def base_adr_numbers(self) -> dict[str, str]:
        out: dict[str, str] = {}
        for f in git("ls-tree", "--name-only", self.base, "docs/adr/").split():
            m = ADR_FILE.match(f)
            if m:
                out.setdefault(m.group(1), f.rsplit("/", 1)[-1])
        return out

    # -- ownership -----------------------------------------------------------------------------------
    def owns(self, kind: str, number: str) -> bool:
        """Was this number allocated to THIS worktree by the allocator?

        Keying ownership on the worktree only works because the worktree gate forces each session into
        its own worktree; before that, every session shared the primary checkout and this key collapsed.
        """
        try:
            claim = json.loads((self.alloc / kind / f"{number}.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        mine = str(self.repo).replace("\\", "/").casefold()
        theirs = str(claim.get("worktree", "")).replace("\\", "/").casefold()
        return mine == theirs.rstrip("/")

    def fail(self, what: str, why: str, fix: str) -> None:
        self.failures.append(f"  BLOCKED: {what}\n  {why}\n\n  Do this:\n      {fix}\n")

    # -- rules ---------------------------------------------------------------------------------------
    def check_adrs(self) -> None:
        base_adrs = self.base_adr_numbers()
        try:
            head_readme = self.head_text("docs/adr/README.md") or self.base_text(
                "docs/adr/README.md"
            )
        except OSError:  # pragma: no cover - defensive
            head_readme = ""
        rows = INDEX_ROW.findall(head_readme)

        for path in self.added_files():
            m = ADR_FILE.match(path)
            if not m:
                continue
            number, basename = m.group(1), path.rsplit("/", 1)[-1]

            if number in base_adrs:
                # A DECLARED COMPANION is legal: one number, one index row, two files -- the row itself
                # names the companion. One shipped ADR is exactly this and is CORRECT. Only an
                # UNdeclared reuse is a collision.
                row = next(
                    (ln for ln in head_readme.splitlines() if ln.startswith(f"| [{number}]")), ""
                )
                if basename.removesuffix(".md") not in row:
                    self.fail(
                        f"ADR {number} already exists on {self.base} as {base_adrs[number]}",
                        "Two sessions picking the same number create DIFFERENT filenames, merge CLEAN, and "
                        "silently corrupt the ledger. It happened three times on the repository "
                        "this rule came from.",
                        'pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "<title>"'
                        "   # then rename your file to the number it prints",
                    )
            elif not self.ci and not self.owns("adr", number):
                self.fail(
                    f"ADR {number} was not allocated to this worktree",
                    f"Nothing in {self.alloc / 'adr' / (number + '.json')} names {self.repo}. A sibling "
                    "session may be holding this number right now.",
                    'pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind adr -Title "<title>"',
                )

            # Only ADDED files are checked for an index row: a few legacy ADRs shipped without one, and
            # failing every unrelated commit over old debt is how a gate gets uninstalled.
            if number not in rows:
                self.fail(
                    f"ADR {number} ({basename}) has no row in docs/adr/README.md",
                    "An ADR that is not in the index is invisible -- the tail-append hazard shows up as a "
                    "DROPPED ROW, not as a conflict. Three were lost this way on the repository this "
                    "rule came from.",
                    "add its row to docs/adr/README.md in THIS commit",
                )

        duplicated = sorted({n for n in rows if rows.count(n) > 1})
        if duplicated:
            self.fail(
                f"duplicate index row(s) in docs/adr/README.md: {duplicated}",
                "One number must have exactly one row (a companion file is named INSIDE its number's row, "
                "it does not get a second row).",
                "remove the duplicate row",
            )

    def backlog_paths(self, side: str) -> list[str]:
        """Every file carrying numbered items on ``side`` ('head' or 'base').

        Enumerated per side rather than assumed, because the archive does not exist on a base that
        predates it, and a path listed but absent makes `git show` exit 128 -- indistinguishable from
        a real failure, which is the false-clean this gate must never produce.
        """
        if side == "base":
            listing = git("ls-tree", "-r", "--name-only", self.base, f"{BACKLOG_ARCHIVE_DIR}/")
            have_main = self.base_has(BACKLOG_PATH)
        elif self.ci:
            listing = git("ls-tree", "-r", "--name-only", "HEAD", f"{BACKLOG_ARCHIVE_DIR}/")
            have_main = self.head_has(BACKLOG_PATH)
        else:
            # The INDEX, matching head_text() -- a staged archive edit must be policed before it lands.
            listing = git("ls-files", "--", f"{BACKLOG_ARCHIVE_DIR}/")
            have_main = self.head_has(BACKLOG_PATH)
        paths = [BACKLOG_PATH] if have_main else []
        paths += [p for p in listing.split() if p.endswith(".md")]
        return paths

    def check_backlog(self) -> None:
        # NOTE FOR THE READER: the original also enforced a reserved number space here -- a floor
        # constant, below which a new item was refused outright. The specific constant, and the ~50
        # lines of comment justifying it, are not reproduced; the mechanism is worth understanding.
        #
        # WHY A FLOOR AT ALL. A gate like this one derives "taken" from what it can read. Any number
        # that is spent but not visible in what it reads -- reserved for something else, or spent on
        # an artefact this rule does not enumerate -- is invisible, and invisible reads as free. A
        # floor is the crude repair: refuse anything below a number asserted to be already spent.
        #
        # WHY A FLOOR MUST BE A ONE-WAY RATCHET. A floor computed from what is visible moves with
        # visibility, and visibility SHRINKS: a file is archived out of the swept set, a clone lacks
        # a ref that carried the highest number, a pattern stops matching after a rename. Recompute
        # then and the floor drops -- and a floor that drops re-issues numbers already spent, which
        # is the exact defect the gate exists to prevent, now produced by the guard itself. So a
        # floor may rise and must never fall: persist the high-water mark and take the max of the
        # computed value and the stored one. The shipped allocator does exactly this
        # (`scripts/coord/alloc.ps1`, `<state-root>/alloc/<kind>/.floor-highwater`).
        #
        # WHAT NOT TO COPY. The original's constant was parsed out of THIS FILE'S SOURCE by the
        # allocator at runtime, so that the gate and the allocator could not disagree about it. It
        # worked, and it is a trap: a cross-file coupling through a regex over source text, invisible
        # to both files' tests. Share the value through data both sides read, not through source.
        changed = self.changed_files()
        if not any(f == BACKLOG_PATH or f.startswith(f"{BACKLOG_ARCHIVE_DIR}/") for f in changed):
            return
        base_paths = self.backlog_paths("base")
        if not base_paths:
            # The base has no backlog at all -- the file is being ADDED by this very change. Numbers
            # that do not exist on base cannot be collided with, so there is nothing to police;
            # without this, importing an existing ledger wholesale would report every one of its
            # items as "not allocated to this worktree".
            return
        head_paths = self.backlog_paths("head")
        if not head_paths:
            # Present on base, absent here: a branch that PREDATES the file being added. CI diffs
            # against trunk, so the file shows up as "changed" (a deletion relative to base)
            # although the branch never touched it -- and reading HEAD for a copy that was never
            # there exits 128. A stale branch is not a ledger violation.
            return
        head: set[str] = set()
        for p in head_paths:
            head |= set(BACKLOG_HEADING.findall(self.head_text(p)))
        base: set[str] = set()
        for p in base_paths:
            base |= set(BACKLOG_HEADING.findall(self.base_text(p)))
        # Only `head - base` is examined, so everything already on trunk is grandfathered by
        # construction. No allowlist, nothing to maintain.
        for number in sorted(head - base, key=int):
            if not self.ci and not self.owns("backlog", number):
                self.fail(
                    f"BACKLOG item #{number} was not allocated to this worktree",
                    "BACKLOG numbers are '## N.' headings inside ONE long file. Two sessions adding "
                    "#N land far apart, merge CLEAN, and both ship.",
                    'pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind backlog -Title "<title>"',
                )

    def run(self) -> int:
        self.check_adrs()
        self.check_backlog()
        if not self.failures:
            return 0
        print("\nledger gate (example)\n", file=sys.stderr)
        for f in self.failures:
            print(f, file=sys.stderr)
        print(
            "  Do NOT work around this by renaming the file, editing a copy, or using --no-verify: all of\n"
            "  those leave a ledger that merges CLEAN and is invisible to git. If you cannot proceed, STOP\n"
            '  and tell the user: "The ledger gate blocked this commit and I need guidance."\n',
            file=sys.stderr,
        )
        return 1


def main(argv: list[str]) -> int:
    return Ledger(ci="--ci" in argv).run()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
