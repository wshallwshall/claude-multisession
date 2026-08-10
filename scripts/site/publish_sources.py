"""Copy the repository's own files into the built site, so the source is reachable without GitHub.

WHY THE SITE CARRIES THE SOURCE. The reader this documentation is written for sits behind a firewall
that blocks GitHub wholesale -- github.com and raw.githubusercontent.com as well as the Pages host.
That is worse than a broken link: they cannot clone the repository, so every `blob/main` URL in these
documents pointed at a file they had no route to, and the documents are largely ABOUT those files.
A page explaining what `scripts/coord/_common.ps1` does, linking to a copy they cannot fetch, is
half a document.

So the site serves everything git tracks. A reader who cannot reach GitHub then has the same view of
this project as one who can, which is the only version of "the documentation is available" that is
true for them.

THE RULE IS DERIVED, NOT LISTED. `git ls-files` decides what ships, so a file added to the repository
is served without anyone remembering to add it here, and a hand-maintained copy list -- the thing
this repository's installer tests exist to catch -- never comes into being.

WHY docs/ IS EXCLUDED, and the asymmetry it leaves. Jekyll has already handled docs/: it renders each
page to HTML at the site root AND copies the markdown source beside it, so docs/CONCEPTS.md is served
at /CONCEPTS.md, not at /docs/CONCEPTS.md. Copying it again here would either duplicate it or fight
the build for the same path. Everything else keeps its repository-relative path, so scripts/coord
/claim.ps1 is served at /scripts/coord/claim.ps1. That asymmetry is real and worth knowing before
writing a link by hand: docs pages lose their directory, nothing else does.
tests/test_docs_do_not_drift.py checks every such link against what this script actually publishes,
so a link written the wrong way fails the run rather than 404ing for a reader.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

# Jekyll's source root. Its files are already in the built site, by a different path -- see above.
RENDERED = "docs/"


def tracked_source_files() -> list[str]:
    """Every file git tracks except the ones Jekyll already published.

    RAISES on an empty result. A publisher that silently copied nothing would produce a site whose
    every source link 404s, and the build would go green -- the failure shape this repository keeps
    finding in its own tooling.
    """
    out = subprocess.run(
        ["git", "ls-files"], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    )
    paths = [p for p in out.stdout.split("\n") if p.strip() and not p.startswith(RENDERED)]
    if not paths:
        raise SystemExit("git ls-files matched nothing outside docs/ -- there is no source to serve")
    return paths


def publish(dest: Path) -> list[str]:
    written = []
    for rel in tracked_source_files():
        src = REPO_ROOT / rel
        if not src.is_file():
            # Tracked but absent from the working tree -- a submodule pointer, or a checkout done
            # with a sparse pattern. Skipping is right; claiming to have published it is not.
            print(f"  SKIPPED, not a file in this checkout: {rel}")
            continue
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, out)
        written.append(rel)
    return written


def main() -> int:
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "_site"
    if not dest.is_dir():
        raise SystemExit(f"{dest} does not exist -- build the site before publishing sources into it")
    written = publish(dest)
    print(f"published {len(written)} source file(s) into {dest}")
    for rel in sorted(written)[:12]:
        print(f"  {rel}")
    if len(written) > 12:
        print(f"  ... and {len(written) - 12} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
