# Handoff: framework evaluations branch

Working state for `claude/spec-kit-verification-review-1p4fnn`. Written so another session can pick
this up without replaying the conversation. Kept current as work lands.

Deliberately at the repository root, not under `docs/`: it is operational, not a site page. Files
under `docs/` are bound by `OPEN-2`, `OPEN-7` and the prose ratchets, and a handoff should not have
to satisfy them.

Last updated 2026-08-15.

---

## 1. Read this first: the gates have zero headroom

```
cd tests && python -m unittest discover -s . -q
```

**Run from inside `tests/`.** From the repository root the imports fail and it looks like a broken
suite. One session lost four commits to that misreading.

**Expected result: 173 tests, 5 failures.** All 5 are `test_word_copy_tracks_the_markdown` failing
because `pandoc` is not installed in this container. They predate all work on this branch. Any
sixth failure is yours.

The three prose ratchets in `tests/test_prose_rules_hold.py` are at their baselines **exactly**:

| Metric | Now / baseline | Headroom |
|---|---|---|
| Sentences over 30 words | 180 / 181 | 1 |
| Table cells over 40 words | 19 / 19 | **0** |
| Paragraphs over 300 chars | 88 / 88 | **0** |

So any new page must add **zero** fat paragraphs and **zero** fat cells, or the suite goes red. Fix
by rewriting shorter, never by splitting a paragraph in two, and never by deleting a measurement:
`PD-1` through `PD-7` outrank the length rules.

A scratch measuring script for a single file was useful and is gone with the container. It read
`FRAMEWORK_SECTIONS`, the `BANNED` patterns and the baselines out of the test module and reported
per-file counts. Rebuilding it takes about twenty lines.

---

## 2. What is on this branch

Eight commits, all pushed. `git log --grep='Claude-Session: .*01VwhjHSMA753Yv54BPoNHmb'` lists them.

| Landed | State |
|---|---|
| `docs/FRAMEWORK-spec-kit.md` | Live in nav under "Other frameworks" |
| `docs/FRAMEWORK-bmad.md` | **On disk, deliberately NOT in nav.** See section 4 |
| `docs/CASE-STUDY-refuted-but-true.md` | Live in nav under "In practice" |
| `HS-21` in `docs/HOUSE-STYLE.md` | Issued; numbering table moved to `HS-22` |
| `tests/test_a_series_answers_one_set_of_questions.py` | Gates HS-21. 9 tests |
| `docs/SEQUENCE-ALLOC.md` | Two additions, see section 3 |

### HS-21 binds every `docs/FRAMEWORK-*.md`

`tests/_ccxtest.py` `FRAMEWORK_SECTIONS` is the **only** definition of the section order. A new
framework page must carry all nine `##` sections in that order. Extra sections are allowed; a
missing one is refused, because an absent section reads as "this framework has no such property"
rather than "nobody established it". Write "not established" in the section instead.

`docs/_data/nav.yml` carries the same list as a note for whoever writes the next page, and the test
asserts the note still matches the constant. It caught its own first drift on its first run.

---

## 3. Findings that cost real work to establish

Do not re-derive these. Each was measured, not read about.

**Spec Kit resolves feature state per worktree, until the worktree has no `.specify/`.**
`Find-SpecifyRoot` walks parent directories looking for a `.specify/` directory and consults git
nowhere. A worktree whose branch predates `specify init` therefore binds to the first ancestor
holding one. Two such worktrees nested under a primary both bound to the primary's `feature.json`;
the second overwrote the first, `git status` stayed clean in both, and nothing reported it.

**BMAD's work-item state has no lock.** `_atomic_write` in `sprint_status.py` is crash-atomic and
not concurrency-safe: `_load_document` reads at line 455, `_atomic_write` writes at line 561, and no
Python file in the install contains `flock`, `fcntl`, `lockf`, `O_EXCL` or a lockfile. The file is
committed rather than gitignored, so cross-worktree divergence surfaces as a merge conflict. The
residual window is two writers in one worktree.

**BMAD's project-root resolution is fail-closed**, which is the one place it is plainly better than
Spec Kit. `load_central_config` requires `_bmad/config.toml` and does not walk parents, so the case
that silently mis-binds Spec Kit produces a named error.

**Spec Kit's feature numbering is still unlocked at 0.16.4.** `Get-HighestNumberFromSpecs` takes the
highest prefix and adds one. This re-verifies the claim `docs/SEQUENCE-ALLOC.md` already carried
from a 2026-08-12 reading.

**Two projects reached the same ADR layout independently.** `examples/sequence-adr/` numbers records
at `docs/adr/NNNN-slug.md`; the `panaversity/spec-kit-plus` fork uses `history/adr/NNNN-slug.md`.
The fork settles scope the same way and leaves concurrency open.

**The two ADR extensions, read from `extensions/catalog.community.json` on 2026-08-15.** `adrkit`
requires `speckit_version >=0.13.0,<0.16.0`, so it is not certified for 0.16.x, and needs a separate
`adr` CLI. `arch-governance` requires `>=0.1.0` and needs Python 3.11+ and `uv`. Both are
`verified: false`, 0 downloads, 0 stars.

---

## 4. Outstanding work, in priority order

**a. BMAD's three unresearched rows, then its nav entry.** The page states "not established" for the
persona order, which published claims are false at 6.11.0, and practitioner-reported cost. Its
decision-record row and everything in section 3 are measured and done. The owner chose to hold the
nav entry until those rows are filled; adding it is one entry in `docs/_data/nav.yml` beside the
Spec Kit row.

A `/deep-research` run against exactly those gaps completed and its 80KB journal is at
`~/.claude/projects/<project>/<session>/subagents/workflows/wf_ba0f23e8-3cb/journal.jsonl`. **That
path dies with the container.** The one result sampled from it re-verified install-flag
documentation that had already been measured directly, so re-running a targeted pass is probably
cheaper than mining it.

**b. An auditability paragraph for `docs/SEQUENCE-ALLOC.md`.** `seq_check.py` refuses a colliding,
unallocated, **or unindexed** number. The third refusal reads as pedantry until it is framed as
auditability: a decision record that exists but is missing from the index is invisible to whoever
reviews it. This needs no external citations and is ready to write.

**c. The compliance mapping, held deliberately.** Material was supplied claiming OWASP ASVS 5.0,
NIST SSDF, HIPAA/HITRUST, ISO 27001 and SOC 2 each require documented design rationale that ADRs
satisfy. The framing is sound; the **control identifiers are unverified and are what an auditor
checks**. Two are known risks: ASVS 5.0 reorganised its chapters, so a `V1` citation carried over
from 4.0 may be stale, and ISO 27001's secure engineering control moved to `A.8.27` in the 2022
revision from `A.14.2.5` in 2013.

It belongs in
[secure-development-standards](https://secure-development-standards.pages.dev/), which owns
standards content and ships the ASVS 5.0 assessment. Publishing a mapping here would be the drift
the repository split exists to prevent. Cite that site **by name and never by anchor**:
`CrossRepositoryAnchorsAreRefused` bans `#fragment` links into it, because neither suite can check
the other's headings.

---

## 5. Two things not to re-open

**The Ultracode "bug" was not a bug.** Four reports were drafted and all four were wrong. The
control is a six-position Effort slider whose top notch is `Ultracode`, sitting above `Max`, and it
is a separate control from the model picker. Official documentation states Ultracode "combines
`xhigh` reasoning effort with automatic workflow orchestration", so `CLAUDE_EFFORT=xhigh` while
Ultracode is on is documented and intended. Paired readings taken in the same turn as each mode
reminder: Ultracode gives `xhigh`, Max gives `max`, and `MAX_THINKING_TOKENS` is 31999 at both.

The keyword path is a separate, single-turn opt-in that does not change session effort, which is why
it stays silent when the session setting is already on. Everything observed was correct behaviour.

The real lesson was methodological and is worth carrying: **two observation channels that cannot be
time-aligned cannot support an inference.** The screenshots and the mode reminders were sampled at
different moments, and every wrong report came from comparing them as though they were simultaneous.

Related and still open upstream, filed by someone else:
[#75732](https://github.com/anthropics/claude-code/issues/75732), open since 2026-07-08 with no
maintainer response.

**Verification kill lists are not established fact.** `docs/CASE-STUDY-refuted-but-true.md` records
two audited kills from one research pass. One was a plain false negative on a claim the primary
source confirms verbatim. The other was a compound claim whose true conjunct was destroyed along
with its unsupported one. Both trace to a verdict field narrower than the thing being judged. If you
run adversarial verification here, use a three-valued verdict and split claims into atomic
assertions first.

---

## 6. Conventions worth knowing before editing

- **Prose is ASCII.** No em dash, no smart quotes. `HS-11`, and the pattern is easy to reintroduce
  by pasting.
- **A markdown link sits on one line**, text and target both. `HS-16` outranks the 100-character
  wrap, because a wrapped link is served as raw markdown by the published site.
- **Search before renaming a heading.** `HS-13`. Pages cite headings by name and link by anchor.
- **A count in prose needs the set enumerated on the same page.** `HS-5`. This is the rule new pages
  break most often.
- **No PR has been opened**, and the owner asked for none. The branch is pushed and reviewed
  directly.
