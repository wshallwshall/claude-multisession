"""Generate the forwarding site that replaces the old GitHub Pages content.

WHY THERE IS A FORWARDER AT ALL. The documentation moved off wshallwshall.github.io on 2026-08-10
because a firewall in front of the readers this project is written for blocks GitHub wholesale. The
old address does not stop being written down when that happens: it is in this repository's history,
in pull requests, in anything anyone bookmarked. Turning the old site off would answer all of them
with GitHub's own 404, which names no successor. So the old host keeps serving, and what it serves
is a page per old URL saying where that page went.

WHO THIS DOES NOT HELP, said plainly because the pages themselves cannot say it. These stubs are
hosted on GitHub. The reader the move was made for cannot load them -- they cannot reach the host
the forwarding page is served from, so for them an old link fails exactly as it did before, with no
redirect and no explanation. This forwarder is for everyone ELSE holding an old link: readers
outside that network, search results, and anything already indexed. It is worth building for them
and it is not a mitigation for the blocked reader, and a comment that let those two be confused
would be overstating a control -- which is the failure this repository is about.

WHY A STUB PER PAGE RATHER THAN ONE CLEVER 404. A single 404 handler could read the path it was
asked for and rewrite it, but only from script -- the served HTML cannot know which URL produced it.
docs/assets/style.css states the rule this site holds to: script is allowed only when "the answer it
filtered was complete before any script ran", and "if a future feature cannot say that second
sentence about itself, it does not get a script either." A path-rewriting 404 cannot say it. With no
script, the reader with JavaScript disabled gets a page whose only content is a link to the wrong
place -- the site root -- and no way to know which page they were after.

Generating one file per document costs nothing and needs no script: each stub names its own
destination, in a meta refresh AND in a visible link, both correct before anything runs. 404.html is
still generated, for genuinely unknown paths, and it is the only page that can honestly offer just
the root.

IT CANNOT DRIFT, because the page list is not written down here. It comes from the same place the
site's own build takes it -- the tracked markdown under docs/ -- and the destination host comes from
docs/_config.yml, so the new address has exactly one definition. Add a document and its stub appears;
tests/test_redirect_covers_every_page.py fails the run if one goes missing.
"""

from __future__ import annotations

import html
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CONFIG = REPO_ROOT / "docs" / "_config.yml"
SOURCE_ROOT = "docs"


def config_value(key: str) -> str:
    """One field of docs/_config.yml, or a hard stop.

    Deliberately not a yaml parse: the tests in this repository are stdlib-only and a dependency
    would be a strange thing to add for two strings. Deliberately not a silent default either -- a
    forwarder that guessed its own destination would send every reader somewhere plausible and
    wrong, which is worse than not building.
    """
    text = CONFIG.read_text(encoding="utf-8")
    m = re.search(rf"^{re.escape(key)}:\s*(.*)$", text, re.M)
    if m is None:
        raise SystemExit(f"{CONFIG} has no `{key}:` -- the destination cannot be guessed")
    value = m.group(1).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def tracked_pages() -> list[Path]:
    """Every markdown file the site is built from. Raises rather than returning nothing."""
    out = subprocess.run(
        ["git", "ls-files", f"{SOURCE_ROOT}/*.md"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    paths = [Path(p) for p in out.stdout.split()]
    if not paths:
        raise SystemExit("git ls-files matched no markdown -- there is nothing to forward")
    return paths


def heading(src: Path) -> str | None:
    """The document's leading H1, which is what the old page called itself."""
    for line in (REPO_ROOT / src).read_text(encoding="utf-8").split("\n"):
        if line.startswith("# "):
            return line[2:].strip()
    return None


# No stylesheet link: the old host will not be serving assets/style.css once this replaces the site,
# and a stub that reaches for a missing file to look right is a stub that looks broken. The few
# declarations it needs are inline, and it renders acceptably with none of them.
TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Moved -- {title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="robots" content="noindex">
<link rel="canonical" href="{target}">
<meta http-equiv="refresh" content="0; url={target}">
<style>
body {{ margin: 0 auto; padding: 3rem 1.25rem; max-width: 42rem; line-height: 1.6;
  font-family: system-ui, -apple-system, Segoe UI, Helvetica, Arial, sans-serif; }}
h1 {{ font-size: 1.5rem; line-height: 1.3; }}
a {{ overflow-wrap: anywhere; }}
.note {{ color: #666; font-size: 0.9rem; }}
@media (prefers-color-scheme: dark) {{
  body {{ background: #14171a; color: #e6e6e6; }}
  a {{ color: #7cb7ff; }}
  .note {{ color: #9aa4ad; }}
}}
</style>
</head>
<body>
<h1>{lede}</h1>
<p>The claude-multisession documentation now lives at
<a href="{target}">{target_text}</a>.</p>
<p>Your browser should be taking you there. If it does not, follow the link above.</p>
<p class="note">It moved because GitHub is blocked by the firewalls in front of many of the readers
this documentation is written for. The source is unchanged and is still at
<a href="{repo}">{repo_text}</a> -- which those readers cannot reach either; the new site serves
the markdown sources alongside the pages for that reason.</p>
</body>
</html>
"""


def stub(target: str, title: str, lede: str, repo: str) -> str:
    return TEMPLATE.format(
        target=html.escape(target, quote=True),
        target_text=html.escape(target),
        title=html.escape(title),
        lede=html.escape(lede),
        repo=html.escape(repo, quote=True),
        repo_text=html.escape(repo),
    )


def build(dest: Path) -> list[Path]:
    base = config_value("url").rstrip("/") + config_value("baseurl").rstrip("/")
    repo = config_value("repo_url")
    site_title = config_value("title")
    dest.mkdir(parents=True, exist_ok=True)
    written = []

    for src in tracked_pages():
        name = src.name[: -len(".md")]
        if name == "index":
            target, out = base + "/", dest / "index.html"
            lede = f"{site_title} has moved"
        else:
            target, out = f"{base}/{name}.html", dest / f"{name}.html"
            title = heading(src) or name
            lede = f"{title} has moved"
        out.write_text(stub(target, site_title, lede, repo), encoding="utf-8")
        written.append(out)

    # THE CATCH-ALL, and it is now usually written by the loop above rather than here. GitHub Pages
    # serves 404.html for any address it does not recognise, so this file answers every old URL that
    # is not one of the pages -- which, since docs/404.md exists, means forwarding to the new site's
    # OWN not-found page. That is the honest destination: the reader asked for something that does
    # not exist, and landing them on a home page that returns 200 tells them it does.
    #
    # The fallback below is kept for the case where docs/404.md is deleted. It offers the site root,
    # which is the only thing a page with no idea what was asked for can honestly offer, and it is
    # worse -- so it is a fallback and not the design.
    if not any(p.name == "404.html" for p in written):
        out = dest / "404.html"
        out.write_text(
            stub(base + "/", site_title, "This documentation has moved", repo), encoding="utf-8"
        )
        written.append(out)
    return written


def main() -> int:
    dest = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "_redirect"
    written = build(dest)
    print(f"wrote {len(written)} forwarding pages to {dest}")
    for p in written:
        print(f"  {p.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
