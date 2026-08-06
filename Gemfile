# Ruby dependencies for BUILDING THE SITE. Nothing at runtime needs these; the published site is
# static, and the toolkit itself is PowerShell and stdlib Python.
#
# WHY THE `github-pages` GEM RATHER THAN `jekyll` DIRECTLY. GitHub Pages builds this site today in
# safe mode, where the plugin set is a FIXED ALLOWLIST that cannot be configured. docs/_config.yml
# has no `plugins:` key on purpose and says why: three of those always-on plugins are what make the
# site work without touching the documents --
#
#   jekyll-optional-front-matter   renders the front-matter-less .md files as pages at all
#   jekyll-relative-links          rewrites ](CONCEPTS.md) to a built URL, with the baseurl
#   jekyll-titles-from-headings    takes each page.title from its leading H1
#
# This gem pins the exact jekyll version and the exact plugin set that GitHub's own builder uses, so
# a build here resolves the same way theirs does. Declaring `jekyll` plus a hand-written plugin list
# would be a SECOND definition of the allowlist, and the two would drift silently.
#
# THE FAILURE MODE THAT MAKES THIS WORTH SAYING, quoted from _config.yml because it applies in
# reverse here: "A plugin that is not on the allowlist is not an error either -- it simply never
# runs, which is the failure mode that looks like success." Under GitHub's builder a missing plugin
# is impossible. Under a build we control it is one forgotten line, and the symptom is not an error
# but fourteen documents quietly losing their titles or their internal links.
#
# So: change this file only with a rendered-output comparison in hand, never on reasoning alone.

source "https://rubygems.org"

gem "github-pages", group: :jekyll_plugins
