#!/usr/bin/env python3
"""Sequence gate -- stop two concurrent sessions from silently colliding on a shared number.

THE DEFECT THIS EXISTS FOR. A repository keeps a sequence git cannot see: decision records numbered
0001, 0002, ...; issues as `## 58.` headings in one long file; anything where "the next number" is
a shared resource. Two sessions each look for the next free number, both pick N, and create
DIFFERENTLY-NAMED artefacts (`0004-alpha.md` and `0004-beta.md`, or two `## 58.` headings far apart
in one file). Git merges both **cleanly** -- there is no textual conflict -- and the sequence is
quietly corrupt. It happened three times on the repository this was developed in, and it is the one
collision class that a worktree, a file lock and `git merge-tree` are all blind to.

WHY A GIT PRE-COMMIT HOOK. Installed into the SHARED .git/hooks, one copy governs EVERY worktree of
the clone at once -- no branch, no merge, no propagation lag -- and it sees every write route (an
editor, a shell redirect, an agent's file-write tool), because it inspects the TREE at commit time
rather than a tool call. The `--ci` mode re-runs the same rules against a freshly fetched trunk,
which is what catches the STALE-BASE collision: each branch is internally consistent, and the
duplicate only exists once both have merged.

Reads the STAGED tree (`git show :path`), never the working tree -- otherwise an untracked
work-in-progress file sitting in your checkout would block every unrelated commit.

WHAT IT CHECKS, per sequence in ccx.config.json (omit the `sequences` key entirely and this gate is
inert):

    1. An ADDED file whose name carries number N must not reuse an N that already exists on trunk,
       unless the index row for N declares the new file as a companion.
    2. An ADDED number must have been allocated to THIS worktree by the allocator. (Local only --
       see the note on modes below.)
    3. An ADDED number must have a row in the sequence's index file.
    4. The index must not gain a duplicate row for one number.

WHAT IT DOES NOT CHECK. Anything about numbers that were already on trunk. A gate that fails on
pre-existing debt is a gate that gets uninstalled, so rule 3 applies only to files this change adds
and rule 4 only to duplicates this change introduces.

MODES ARE NOT SYMMETRIC, AND SAYING SO IS THE POINT. Rule 2 cannot run in `--ci`: it reads a
per-clone registry inside the git directory and compares a worktree path, and a runner has neither.
An earlier version of this code ran the CI half of that rule anyway -- computing a set and
discarding it, i.e. structurally unable to fail. If a rule cannot run, it must be named as not
running, never left in place looking like coverage.

Stdlib only, no project import: most worktrees have no virtualenv, and a gate that silently skips is
worse than no gate. `git commit --no-verify` is the escape hatch; the `--ci` run is the backstop for
it. ASCII output only.

The two rules that keep this gate honest -- the explicit `encoding=` on every git call, and raising
on a non-zero git exit rather than reading it as an empty file -- live in `_ccxconfig.git()`. Read
them there before changing anything here; both are failure modes this gate has actually shipped.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from _ccxconfig import (
        GitError,
        fold_path,
        git,
        load_config,
        object_exists,
        repo_root,
        state_root,
    )
except ImportError as exc:  # pragma: no cover - only fires on a partial copy
    sys.stderr.write(
        f"\nccx sequence gate: cannot import _ccxconfig.py from {Path(__file__).parent} ({exc}).\n"
        "  This gate and its substrate ship together. Copy both, or reinstall the git hooks.\n\n"
    )
    raise SystemExit(1) from exc


class ConfigError(ValueError):
    """A `sequences` entry that cannot be used. Always fatal -- never degraded into "no rules"."""


class Sequence:
    """One configured number space: how its files are named, and where its index lives."""

    def __init__(self, name: str, spec: object) -> None:
        if not isinstance(spec, dict):
            raise ConfigError(f"sequences.{name} must be an object.")
        pattern = spec.get("filePattern")
        if not isinstance(pattern, str) or not pattern:
            raise ConfigError(f"sequences.{name}.filePattern is required (a regex over repo-relative paths).")
        try:
            self.file_re = re.compile(pattern)
        except re.error as exc:
            raise ConfigError(f"sequences.{name}.filePattern is not a valid regex: {exc}") from exc
        if self.file_re.groups < 1:
            raise ConfigError(
                f"sequences.{name}.filePattern must capture the number in group 1, e.g. "
                r'"^docs/adr/(\d{4})-[^/]+\.md$".'
            )

        self.name = name
        self.dir = str(spec.get("dir") or "").replace("\\", "/").strip("/")
        self.pad = int(spec.get("pad") or 0)

        index_file = spec.get("indexFile")
        self.index_file = str(index_file).replace("\\", "/") if index_file else ""
        row = spec.get("indexRowPattern")
        if self.index_file and not row:
            raise ConfigError(
                f"sequences.{name}: indexFile is set, so indexRowPattern must be set too "
                "(it is how a row is recognised, and it must capture the number in group 1)."
            )
        self.index_row_re: re.Pattern[str] | None = None
        if row:
            try:
                self.index_row_re = re.compile(str(row), re.M)
            except re.error as exc:
                raise ConfigError(
                    f"sequences.{name}.indexRowPattern is not a valid regex: {exc}"
                ) from exc

    def show(self, number: str) -> str:
        """The number as a human writes it, zero-padded if the sequence says so."""
        return number.zfill(self.pad) if self.pad else number


def resolve_trunk(configured: str) -> str | None:
    """The ref this change is measured against, or None if this clone has no usable trunk.

    Resolution order, most explicit first: $CCX_TRUNK, then the config value unless it is the
    literal 'auto', then what the REMOTE says its default branch is, then the first of
    origin/main, origin/master, main, master that actually resolves.

    A REMOTE-tracking ref is preferred over a local branch wherever possible: a local `main` can
    silently lag its upstream, and measuring "what is already taken" against a stale trunk is how a
    number that was allocated last week looks free today.
    """
    env = os.environ.get("CCX_TRUNK")
    if env:
        return env
    if configured and configured != "auto":
        return configured
    try:
        sym = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD").strip()
        if sym:
            return sym
    except GitError:
        pass
    for candidate in ("origin/main", "origin/master", "main", "master"):
        try:
            git("rev-parse", "--verify", "--quiet", f"{candidate}^{{commit}}")
            return candidate
        except GitError:
            continue
    return None


class SequenceGate:
    def __init__(self, cfg: SimpleNamespace, *, ci: bool, base: str | None) -> None:
        self.ci = ci
        self.sequences = [Sequence(n, s) for n, s in sorted(cfg.sequences.items())]
        self.repo = repo_root()
        self.me = fold_path(self.repo)
        # The registry lives beside the SHARED object store, so every worktree of this clone sees
        # the same allocations -- and a different clone gets its own, automatically.
        self.alloc = state_root(cfg.prefix) / "alloc"
        self.failures: list[str] = []
        self.notes: list[str] = []

        self.base = base or resolve_trunk(str(cfg.trunk))
        if self.base:
            try:
                git("rev-parse", "--verify", "--quiet", f"{self.base}^{{commit}}")
            except GitError:
                if self.ci:
                    # In CI the base comparison IS the job. A base that does not resolve is a
                    # workflow misconfiguration, not a local quirk, and must stop the run.
                    raise
                self.notes.append(
                    f"base ref '{self.base}' does not resolve in this clone -- the "
                    "already-taken-on-trunk rule did NOT run. Fetch it, or set CCX_TRUNK."
                )
                self.base = None
        else:
            if self.ci:
                raise GitError(
                    "no trunk ref could be resolved. Set CCX_TRUNK, or set 'trunk' in "
                    "ccx.config.json to an explicit ref such as origin/main."
                )
            self.notes.append(
                "no trunk ref could be resolved -- the already-taken-on-trunk rule did NOT run. "
                'Record the remote default once with "git remote set-head origin -a", or set '
                "CCX_TRUNK."
            )

    # -- tree access ---------------------------------------------------------------------------
    #
    # CI uses a TWO-dot diff (`base HEAD`), deliberately, not three-dot (`base...HEAD`).
    #
    # On a pull request the checkout action checks out the MERGE commit -- HEAD already CONTAINS
    # base. So three-dot bought nothing, and it cost everything: it resolves a MERGE BASE, the
    # checkout is shallow, and two truncated histories routinely fail to reach their common ancestor
    # ("fatal: no merge base"). Deepening to fix that is itself a race and needs a full history to be
    # reliable.
    #
    # A two-dot diff compares two TREES. No ancestry, no depth, nothing to race. Against the merge
    # commit it yields exactly "what this change adds on top of base", which is the question the gate
    # asks.
    #
    # This mattered more than it looks: the three-dot failure was SILENT. The git wrapper used to
    # swallow a non-zero exit and return "", so the added-files list was [] and the gate reported
    # PASS on every run where it could not see. A false clean, on the one check whose entire purpose
    # is never to emit one. That is why `git()` raises.

    def _names(self, *args: str) -> list[str]:
        """Split the output of a `-z` name-listing git command. A path with a space survives it.

        `-z` is placed by each caller rather than appended here: git parses options before the
        tree-ish, and a trailing `-z` after a pathspec is read as a path.
        """
        return [p for p in git(*args).split("\0") if p]

    def added_files(self) -> list[str]:
        """Files ADDED by this change. In CI, HEAD is the change merged into base."""
        if self.ci:
            return self._names(
                "diff", "-z", "--name-only", "--diff-filter=A", str(self.base), "HEAD"
            )
        return self._names("diff", "-z", "--cached", "--name-only", "--diff-filter=A")

    def _head_spec(self, path: str) -> str:
        """The ref:path of the file AS IT WILL EXIST after this commit -- the INDEX, not the tree."""
        return f"HEAD:{path}" if self.ci else f":{path}"

    def index_text(self, seq: Sequence) -> str:
        """The sequence's index file after this change, falling back to base, '' if it has none.

        Absence is probed EXPLICITLY rather than inferred from an error. A ledger file being ADDED
        legitimately has no base version, and a branch that PREDATES the index file being added
        has no HEAD version -- `git show` exits 128 for both, indistinguishable to `git()` from a
        real failure, which it must keep raising on.
        """
        if not seq.index_file:
            return ""
        head = self._head_spec(seq.index_file)
        if object_exists(head):
            return git("show", head)
        if self.base and object_exists(f"{self.base}:{seq.index_file}"):
            return git("show", f"{self.base}:{seq.index_file}")
        return ""

    def base_numbers(self, seq: Sequence) -> dict[str, str]:
        """number -> filename, for everything already on trunk. Empty when there is no base."""
        out: dict[str, str] = {}
        if not self.base:
            return out
        args = ["ls-tree", "-r", "-z", "--name-only", self.base]
        if seq.dir:
            args.append(f"{seq.dir}/")
        for f in self._names(*args):
            m = seq.file_re.match(f)
            if m:
                out.setdefault(m.group(1), f.rsplit("/", 1)[-1])
        return out

    # -- ownership -----------------------------------------------------------------------------
    def owns(self, kind: str, number: str) -> bool:
        """Was this number allocated to THIS worktree by the allocator?

        Keying ownership on the worktree only works because each session gets its own worktree.
        Where every session shares one checkout, this key collapses to "somebody here allocated it"
        and the rule stops discriminating -- true, but worth knowing rather than discovering.
        """
        try:
            claim = json.loads((self.alloc / kind / f"{number}.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return False
        if not isinstance(claim, dict):
            return False
        return fold_path(str(claim.get("worktree", ""))) == self.me

    def fail(self, what: str, why: str, fix: str) -> None:
        self.failures.append(f"  BLOCKED: {what}\n  {why}\n\n  Do this:\n      {fix}\n")

    # -- rules ---------------------------------------------------------------------------------
    def check(self, seq: Sequence) -> None:
        taken = self.base_numbers(seq)
        index = self.index_text(seq)
        rows = seq.index_row_re.findall(index) if seq.index_row_re else []
        alloc_cmd = (
            f'pwsh -NoProfile -File scripts/coord/alloc.ps1 -Kind {seq.name} -Title "<title>"'
        )

        for path in self.added_files():
            m = seq.file_re.match(path)
            if not m:
                continue
            number, basename = m.group(1), path.rsplit("/", 1)[-1]

            if number in taken:
                # A DECLARED COMPANION is legal: one number, one index row, two files -- the row
                # itself names the companion. Only an UNdeclared reuse is a collision.
                row = next(
                    (ln for ln in index.splitlines() if seq.index_row_re and _row_is(seq, ln, number)),
                    "",
                )
                # Matched with and without the extension: an index row conventionally links the
                # file by its stem, and the extension is the sequence's business, not this gate's.
                stem = basename.rsplit(".", 1)[0] if "." in basename else basename
                if stem not in row and basename not in row:
                    self.fail(
                        f"{seq.name} {seq.show(number)} already exists on {self.base} as {taken[number]}",
                        "Two sessions picking the same number create DIFFERENT filenames, merge "
                        "CLEAN, and silently corrupt the sequence. Git cannot see this class of "
                        "conflict at all.",
                        f"{alloc_cmd}   # then rename your file to the number it prints",
                    )
            elif not self.ci and not self.owns(seq.name, number):
                self.fail(
                    f"{seq.name} {seq.show(number)} was not allocated to this worktree",
                    f"Nothing in {self.alloc / seq.name / (number + '.json')} names {self.repo}. A "
                    "sibling session may be holding this number right now.",
                    alloc_cmd,
                )

            if seq.index_file and number not in rows:
                self.fail(
                    f"{seq.name} {seq.show(number)} ({basename}) has no row in {seq.index_file}",
                    "An entry that is not in the index is invisible, and the tail-append hazard "
                    "shows up as a DROPPED ROW rather than as a conflict -- so nothing reports it.",
                    f"add its row to {seq.index_file} in THIS commit",
                )

        if not seq.index_file:
            return

        # Duplicate rows, but only ones this change INTRODUCES. Failing on a duplicate that is
        # already on trunk would block every unrelated commit over old debt, which is how a gate
        # gets uninstalled.
        base_rows: list[str] = []
        if self.base and seq.index_row_re and object_exists(f"{self.base}:{seq.index_file}"):
            base_rows = seq.index_row_re.findall(git("show", f"{self.base}:{seq.index_file}"))
        already = {n for n in base_rows if base_rows.count(n) > 1}
        duplicated = sorted({n for n in rows if rows.count(n) > 1} - already)
        if duplicated:
            self.fail(
                f"duplicate index row(s) in {seq.index_file}: {duplicated}",
                "One number must have exactly one row (a companion file is named INSIDE its "
                "number's row, it does not get a second row).",
                "remove the duplicate row",
            )

    def run(self) -> int:
        for seq in self.sequences:
            self.check(seq)

        # Print what was NOT checked, always, pass or fail. A skip that prints nothing is
        # byte-identical to a clean run, and this gate's whole value is that it never emits one.
        for note in self.notes:
            print(f"ccx sequence gate: {note}", file=sys.stderr)

        if not self.failures:
            return 0

        mode = "--ci" if self.ci else "pre-commit"
        names = ", ".join(s.name for s in self.sequences)
        print(f"\nccx sequence gate  [mode={mode} base={self.base} sequences={names}]\n", file=sys.stderr)
        if self.ci:
            print(
                "  (allocation-ownership is not checked in --ci: the registry is per-clone.)\n",
                file=sys.stderr,
            )
        for f in self.failures:
            print(f, file=sys.stderr)
        print(
            "  Do NOT work around this by renaming the file, editing a copy, or using --no-verify:\n"
            "  all of those leave a sequence that merges CLEAN and is invisible to git. If you\n"
            '  cannot proceed, STOP and tell the user: "The sequence gate blocked this commit and I\n'
            '  need guidance."\n',
            file=sys.stderr,
        )
        return 1


def _row_is(seq: Sequence, line: str, number: str) -> bool:
    """Is this single line the index row for `number`? Uses the sequence's own row pattern."""
    if not seq.index_row_re:
        return False
    m = seq.index_row_re.search(line)
    return bool(m) and m.group(1) == number


def main(argv: list[str]) -> int:
    ci = "--ci" in argv
    base: str | None = None
    if "--base" in argv:
        i = argv.index("--base")
        if i + 1 < len(argv):
            base = argv[i + 1]

    try:
        cfg = load_config()
    except ValueError as exc:
        sys.stderr.write(f"\nccx sequence gate: {exc}\n\n")
        return 1
    if cfg is None:
        sys.stderr.write(
            "ccx sequence gate: no ccx.config.json at or above this worktree -- not enforcing.\n"
        )
        return 0
    if not cfg.sequences:
        return 0  # `sequences` omitted: the sequence machinery is off by configuration

    try:
        return SequenceGate(cfg, ci=ci, base=base).run()
    except (ConfigError, GitError) as exc:
        # Fail CLOSED and name the cause. Every alternative here reads as a pass.
        sys.stderr.write(f"\nccx sequence gate: {exc}\n\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
