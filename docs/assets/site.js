/* -------------------------------------------------------------------------------------------------
   KORUS documentation site, progressive enhancement.

   THE NO-SCRIPT RULE WAS RETIRED ON 2026-08-16, on the owner's instruction, and this file is what it
   was blocking. See the header of assets/style.css for what replaced it. Three constraints survive
   the retirement and every line here is written to them:

     1. THE PAGE WORKS WITH THIS FILE ABSENT. Nothing below is the only route to a link, a heading, a
        command or an answer. Every control this file adds is CREATED by this file, so with script
        disabled there is no dead button, no empty search box and no collapsed nav that will not
        open -- there is simply the page as it was.
     2. SAME ORIGIN. No CDN and no third-party host, because the firewall in front of this site's
        readers blocks those wholesale. That was never part of the script rule and is unchanged.
     3. NO BUILD STEP. Hand-written, served as authored, like the stylesheet.

   IT IS ALSO WRITTEN TO RUN ON AN OLD BROWSER WITHOUT TAKING THE PAGE DOWN WITH IT: everything is
   inside one try/catch per feature, so a failure in the search box cannot cost the reader the copy
   buttons, and a failure in both costs them nothing at all.
   ------------------------------------------------------------------------------------------------- */

(function () {
  "use strict";

  var doc = document;

  // navigator.platform is deprecated and still the most reliable of the three on the browsers this
  // has to work on, so it is tried first and userAgent is the fallback rather than the reverse.
  function copyKey() {
    var id = navigator.platform || navigator.userAgent || "";
    return /Mac|iPhone|iPad|iPod/.test(id) ? "Cmd" : "Ctrl";
  }

  function make(tag, cls, text) {
    var el = doc.createElement(tag);
    if (cls) { el.className = cls; }
    if (text) { el.textContent = text; }
    return el;
  }

  /* ---------- copy buttons ----------

     Every code block on this site is a command someone is meant to run, and several are long enough
     that selecting one by hand picks up the prompt or drops the trailing flag. */

  /* NOT EVERY CODE BLOCK IS SOMETHING TO RUN, and the landing page is the reason this exists. Its
     first block is `git checkout -B feature/parser origin/main` -- the command that CAUSES the
     failure the whole site is about -- and a Copy button on it invites the reader to run the one
     thing every gate here exists to refuse. The same applies to output samples, ASCII diagrams and
     the two blocks in Tips and tricks that are labelled WRONG.

     THE MARKER IS AN HTML COMMENT IMMEDIATELY BEFORE THE FENCE, `<!-- no-copy -->`. It was chosen
     over kramdown's `{: .no-copy}` because these pages are read on github.com as well, where an IAL
     renders as literal text in the middle of the document and the comment renders as nothing.
     Verified against a real build: kramdown passes the comment through and leaves it as the code
     block's preceding sibling. */
  function isMarkedNoCopy(pre) {
    var node = pre;
    // Climb out of kramdown's wrappers -- div.highlight inside div.language-x.highlighter-rouge --
    // because the comment is a sibling of the OUTERMOST one, not of the <pre>.
    while (
      node.parentNode &&
      node.parentNode.nodeType === 1 &&
      /(^|\s)(highlight|highlighter-rouge)(\s|$)/.test(node.parentNode.className || "")
    ) {
      node = node.parentNode;
    }
    var sib = node.previousSibling;
    while (sib && sib.nodeType === 3 && !sib.nodeValue.replace(/\s/g, "")) {
      sib = sib.previousSibling;
    }
    return !!(sib && sib.nodeType === 8 && sib.nodeValue.indexOf("no-copy") !== -1);
  }

  function addCopyButtons() {
    var blocks = doc.querySelectorAll(".page-content pre");
    Array.prototype.forEach.call(blocks, function (pre) {
      if (isMarkedNoCopy(pre)) { return; }
      var wrap = make("div", "code-wrap");
      pre.parentNode.insertBefore(wrap, pre);
      wrap.appendChild(pre);

      var button = make("button", "copy-button", "Copy");
      button.type = "button";
      button.setAttribute("aria-label", "Copy this code block to the clipboard");
      wrap.appendChild(button);

      button.addEventListener("click", function () {
        var text = pre.innerText;

        function done(ok) {
          // The button reports its own outcome. A copy that silently failed would leave the reader
          // pasting whatever was on the clipboard before, which is worse than no button.
          //
          // THE FALLBACK NAMES THE RIGHT KEY. This project is Windows-first, but PowerShell 7 runs
          // on macOS and the docs say so, and a Mac reader told to press Ctrl+C gets nothing.
          button.textContent = ok ? "Copied" : "Press " + copyKey() + "+C";
          button.classList.add(ok ? "is-copied" : "is-failed");
          window.setTimeout(function () {
            button.textContent = "Copy";
            button.classList.remove("is-copied", "is-failed");
          }, 2000);
        }

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(function () { done(true); }, function () { select(); });
        } else {
          select();
        }

        // The fallback selects the block so the reader's own copy shortcut works. It is what a
        // non-secure origin gets, because navigator.clipboard is undefined outside HTTPS.
        function select() {
          try {
            var range = doc.createRange();
            range.selectNodeContents(pre);
            var sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(range);
            done(false);
          } catch (e) {
            done(false);
          }
        }
      });
    });
  }

  /* ---------- the sidebar collapses on a narrow screen ----------

     Under 900px the stylesheet turns the sidebar into wrapped rows above the content, which is
     correct and is still what a reader with script disabled gets. What it cannot do is get out of
     the way: 31 links is most of a phone screen before the page starts. */

  function addNavToggle() {
    var nav = doc.querySelector(".site-nav");
    if (!nav) { return; }

    var toggle = make("button", "nav-toggle");
    toggle.type = "button";
    toggle.setAttribute("aria-controls", "site-nav-list");
    nav.setAttribute("id", "site-nav-list");
    nav.parentNode.insertBefore(toggle, nav);

    function label(open) {
      toggle.textContent = open ? "Hide documentation menu" : "Documentation menu";
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    }

    // Collapsed by default on a narrow viewport ONLY. The class is what the stylesheet keys on, and
    // it is added here rather than in CSS so that a reader without script never meets it.
    var narrow = window.matchMedia("(max-width: 900px)");
    function sync() {
      if (narrow.matches) {
        doc.body.classList.add("has-nav-toggle");
        nav.classList.add("is-collapsed");
        label(false);
      } else {
        doc.body.classList.remove("has-nav-toggle");
        nav.classList.remove("is-collapsed");
      }
    }
    sync();
    if (narrow.addEventListener) { narrow.addEventListener("change", sync); }

    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-collapsed") === false;
      label(open);
    });
  }

  /* ---------- search ----------

     Page-level, over an index this site builds and serves itself. docs/search.json says why it is
     page-level and not heading-level; the short version is that an anchor computed by Liquid and an
     anchor rendered by kramdown disagree on any heading containing `--`, and a search result that
     lands at the top of the right page while promising a section is the silent failure this
     repository is about. */

  function addSearch() {
    var nav = doc.querySelector(".site-nav");
    if (!nav) { return; }

    var form = make("div", "nav-search");
    var input = doc.createElement("input");
    input.type = "search";
    input.className = "nav-search-input";
    input.setAttribute("placeholder", "Search these pages");
    input.setAttribute("aria-label", "Search these pages");
    input.setAttribute("autocomplete", "off");
    var results = make("ul", "nav-search-results");
    results.setAttribute("aria-live", "polite");
    form.appendChild(input);
    form.appendChild(results);
    nav.insertBefore(form, nav.firstChild);

    var index = null;
    var loading = false;

    function load() {
      if (index || loading) { return; }
      loading = true;
      var base = doc.body.getAttribute("data-baseurl") || "";
      fetch(base + "/search.json")
        .then(function (r) { return r.ok ? r.json() : null; })
        .then(function (data) { index = data || []; loading = false; render(); })
        .catch(function () { index = []; loading = false; });
    }

    function render() {
      var q = input.value.trim().toLowerCase();
      results.textContent = "";
      if (!q) { return; }
      if (!index) { load(); return; }

      // RANKED BY HOW OFTEN THE TERM APPEARS, not by index order, and the first query run against
      // this box is why. With a title-match-or-not ranking, "collision" put Coordination -- the page
      // that owns the subject -- below two pages that mention it once, because every body match
      // scored the same and the tie broke on file order.
      var hits = [];
      for (var i = 0; i < index.length; i++) {
        var row = index[i];
        var title = (row.t || "").toLowerCase();
        var body = (row.x || "").toLowerCase();
        var inTitle = title.indexOf(q) !== -1;
        var count = 0;
        var at = body.indexOf(q);
        while (at !== -1) { count++; at = body.indexOf(q, at + q.length); }
        if (inTitle || count) { hits.push({ row: row, inTitle: inTitle, count: count }); }
      }
      hits.sort(function (a, b) {
        if (a.inTitle !== b.inTitle) { return a.inTitle ? -1 : 1; }
        return b.count - a.count;
      });

      if (!hits.length) {
        results.appendChild(make("li", "nav-search-none", "No page matches that."));
        return;
      }

      var LIMIT = 8;
      hits.slice(0, LIMIT).forEach(function (hit) {
        var li = doc.createElement("li");
        var a = doc.createElement("a");
        a.href = hit.row.u;
        a.textContent = hit.row.t || hit.row.u;
        li.appendChild(a);
        results.appendChild(li);
      });

      // NAME WHAT WAS DROPPED. A list that silently stops at eight reads as "these are the matches",
      // and this site's own house style refuses a count that hides its own denominator.
      if (hits.length > LIMIT) {
        results.appendChild(
          make("li", "nav-search-none", "Showing " + LIMIT + " of " + hits.length + " matching pages.")
        );
      }
    }

    input.addEventListener("focus", load);
    input.addEventListener("input", render);
    input.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { input.value = ""; render(); }
    });
  }

  function boot() {
    try { addCopyButtons(); } catch (e) { /* the code blocks are still there and still selectable */ }
    try { addNavToggle(); } catch (e) { /* the nav is still there, just not collapsible */ }
    try { addSearch(); } catch (e) { /* the sidebar is still the way to every page */ }
  }

  if (doc.readyState === "loading") {
    doc.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
