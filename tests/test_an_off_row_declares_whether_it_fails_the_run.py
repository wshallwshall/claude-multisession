"""Pin what an `OFF` row in the doctor costs: the exit code, or nothing.

THE FAILURE THIS EXISTS FOR. `bin/ccx-doctor.ps1` reported the ASCII gate `OK` -- the tag it reserves
for a control that is "installed, wired, and (where attackable) it refused what it must refuse" -- on
the strength of the checker FILE being present. Nothing runs that checker. The same command then
printed, in capitals, that the gate is not wired to anything by default: its status field and its
blind-spot prose contradicting each other, in the one command whose purpose is answering whether the
controls are real.

The fix was to tag it `OFF`. What made the fix nearly wrong is the reason this file exists.

`OFF` IS DOCUMENTED AS COSTING NOTHING FOR AN OPT-IN CONTROL, AND THAT IS NOT WHAT DRIVES IT. The
status vocabulary says `OFF` "drives exit 1 when the control has a shipped installer; reported only
when the control is opt-in by design". No code reads that sentence. The verdict partitions `OFF` on
a separate `-Required` field that DEFAULTS TO TRUE, so a row tagged `OFF` and nothing else joins the
count that fails the run. Changing only the status of a control with no installer would have turned
exit 0 into exit 1 on every clean machine -- the precise opposite of what the vocabulary promises.
Ten of the twelve sites that can emit `OFF` inherit that default silently.

So this pins the decision at each site, in a table an author has to edit deliberately, and pins that
the verdict still partitions on the field rather than on the tag.

WHAT THIS PROVES, AND WHAT IT DOES NOT. These cases READ SOURCE. They do not run the doctor, and
that is deliberate rather than a shortcut: `.github/workflows/gates.yml` states in its header why CI
does not run it -- the doctor fires controls that need a live second session and a peer worktree, and
a run that skipped those paths and reported green would be a worse signal than not running it. So
what is pinned here is what the file DECLARES: which sites can emit `OFF`, what each one declares
about failing the run, and that the verdict reads the declaration. Whether a control is genuinely
unwired on your machine is what the doctor itself answers, in a plain terminal.

Run: python -m pytest tests -q     (or: python -m unittest discover -s tests -v)
"""

from __future__ import annotations

import re
import unittest

import _ccxtest as t

DOCTOR = t.REPO_ROOT / "bin" / "ccx-doctor.ps1"
INSTALL = t.REPO_ROOT / "INSTALL.md"

# Every parameter Add-Result accepts. The extractor reads values only for these, which is what keeps
# it from mistaking `-Leaf` inside an interpolated name for a parameter of the call. If the function
# grows one, the extractor goes partially blind -- so the set is pinned below rather than assumed.
RESULT_PARAMS = ("Kind", "Id", "Name", "Status", "Detail", "Evidence", "Required")

# What each tag in the vocabulary costs. Adding a tag to the ValidateSet without an entry here fails
# the case below, which is the point: a status that drives nothing can be printed forever and change
# no verdict, and that is the same defect as a status that claims more than it proved.
STATUS_EFFECT = {
    "OK": "no effect -- proven installed, wired, and where attackable it refused",
    "RED": "exit 1 always",
    "OFF": "exit 1 only when the row is required; see this file",
    "??": "exit 2 when nothing is RED -- a skip is never a pass",
    "--": "no effect -- not applicable here",
}

OPT_IN = "opt-in (-Required $false)"
REQUIRED_DEFAULT = "required (nothing declared -- inherits $true)"
REQUIRED_DECLARED = "required (-Required $true)"

# EVERY SITE THAT CAN EMIT `OFF`, and what it costs. Twelve of them; ten inherit the default.
#
# Read the third column as the answer to "does this row fail the run". A shipped installer exists for
# these controls, so absence means the machine has no enforcement it was promised, and exit 1 is the
# honest verdict. The two opt-in rows are the ones no installer ever promised to wire.
OFF_SITES = (
    ("gate.installed", "worktree gate: installed", REQUIRED_DEFAULT,
     "install-gate.ps1 ships and installs it"),
    ("gate.allowlist", "worktree gate: allowlist", REQUIRED_DEFAULT,
     "the allowlist is written by the same installer; empty means it governs nothing"),
    ("gate.allowlist", "worktree gate: allowlist", REQUIRED_DEFAULT,
     "second branch of the same row: the file is absent rather than empty"),
    ("gate.wired.$cd", "worktree gate: wired ($(Split-Path $cd -Leaf))", REQUIRED_DEFAULT,
     "the installer writes the matcher rows; unwired is an install that did not finish"),
    ("heal.installed", "selfheal backstop: installed", REQUIRED_DEFAULT,
     "install-selfheal.ps1 ships and installs it"),
    ("heal.wired.$cd", "selfheal backstop: wired ($(Split-Path $cd -Leaf))", REQUIRED_DEFAULT,
     "same installer writes the SessionStart row"),
    ("coord.$($row.Id)", "coordination: $($row.Name)", REQUIRED_DEFAULT,
     "install-coordination.ps1 ships and wires all three"),
    ("git.$($a.Id)", "git hook: $($a.Name)", REQUIRED_DEFAULT,
     "install-git-hooks.ps1 writes commit-msg and pre-push"),
    ("git.$($a.Id)", "git hook: $($a.Name)", REQUIRED_DEFAULT,
     "second branch of the same row: the hook file is present but does not invoke the checker"),
    ("seq.installed", "sequence gate", OPT_IN,
     "needs pre-commit, and no installer here writes that file -- two tools cannot both own it"),
    ("ascii.present", "ASCII gate: present, not wired", OPT_IN,
     "a repo-local checker; nothing shipped runs it, so presence is capability, not enforcement"),
    ("ascii.present", "ASCII gate: not in this checkout", REQUIRED_DEFAULT,
     "the file is missing from a checkout that ships it -- broken checkout, not a wiring choice"),
)


def _read_value(text: str, start: int) -> str:
    """Read one PowerShell argument value beginning at `start`.

    Written as a scanner rather than a regular expression because the values are not tokens: a name
    can be `"worktree gate: wired ($(Split-Path $cd -Leaf))"`, and a pattern that stopped at the next
    `-Word` would cut it at `-Leaf` and hand back a truncated name that matches nothing.
    """
    n = len(text)
    i = start
    while i < n and text[i] in " \t":
        i += 1
    if i >= n:
        raise ValueError("a parameter was given no value")
    char = text[i]
    if char in "\"'":
        j = i + 1
        while j < n:
            if text[j] == "`" and char == '"':
                j += 2
                continue
            if text[j] == char:
                if j + 1 < n and text[j + 1] == char:  # '' and "" escape the quote in PowerShell
                    j += 2
                    continue
                return text[i:j + 1]
            j += 1
        raise ValueError(f"unterminated string starting at {text[i:i + 40]!r}")
    if text.startswith("$(", i) or char == "(":
        depth, j, quote = 0, i, None
        while j < n:
            c = text[j]
            if quote is not None:
                if c == quote:
                    quote = None
            elif c in "\"'":
                quote = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return text[i:j + 1]
            j += 1
        raise ValueError(f"unbalanced parentheses starting at {text[i:i + 40]!r}")
    j = i
    while j < n and not text[j].isspace():
        j += 1
    return text[i:j]


def _unquote(value: str) -> str:
    if value[:1] in "\"'" and value[-1:] == value[:1]:
        return value[1:-1]
    return value


def _statuses(expr: str, source: str) -> frozenset[str]:
    """Every status one call site can emit.

    RAISES on a form it does not recognise. An unclassified site is a site the rule is not enforced
    on, and a scan that shrugged at one would report a clean table while the hole sat next to it.
    """
    if expr[:1] in "\"'":
        return frozenset({_unquote(expr)})
    if re.fullmatch(r"[A-Za-z]+", expr):
        return frozenset({expr})
    if expr.startswith("$(") or expr.startswith("("):
        literals = re.findall(r"'([^']*)'", expr)
        if not literals:
            raise ValueError(f"no status literals inside {expr!r}")
        return frozenset(literals)
    if re.fullmatch(r"\$[A-Za-z_][A-Za-z0-9_]*", expr):
        name = re.escape(expr[1:])
        assignment = re.search(r"\$" + name + r"\s*=\s*([^\r\n]+)", source)
        if not assignment:
            raise ValueError(f"status variable {expr} is never assigned in this file")
        literals = re.findall(r"'([^']*)'", assignment.group(1))
        if not literals:
            raise ValueError(f"status variable {expr} resolves to no literal: {assignment.group(1)!r}")
        return frozenset(literals)
    raise ValueError(f"unrecognised -Status expression: {expr!r}")


def _call_text(text: str, start: int) -> str:
    """The whole of one Add-Result call, however many lines it occupies.

    Backtick continuations are joined before this runs, but that is not the only way a call spans
    lines: an `-Evidence (@("...", "..."))` array continues across newlines on the strength of the
    open parenthesis alone. Reading line by line therefore cuts several calls in half -- which the
    first version of this file did, and the scanner refused the truncated text rather than guessing
    at it. The call ends at the first newline reached outside quotes with every bracket closed.
    """
    depth, quote, i, n = 0, None, start, len(text)
    while i < n:
        c = text[i]
        if quote is not None:
            if c == "`" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "\n" and depth == 0:
            return text[start:i]
        i += 1
    return text[start:]


def result_sites(source: str) -> list[tuple[str, str, frozenset[str], str]]:
    """Every Add-Result call site as (id, name, statuses it can emit, what it declares about cost).

    Takes text rather than a path so the case at the bottom can run it over a planted string.
    """
    joined = re.sub(r"`\r?\n[ \t]*", " ", source)  # PowerShell continuations
    sites = []
    for call_start in re.finditer(r"(?m)^[ \t]*(Add-Result)\b", joined):
        call = _call_text(joined, call_start.start(1))
        params = {}
        for match in re.finditer(r"-([A-Za-z]+)[ \t]", call):
            if match.group(1) not in RESULT_PARAMS:
                continue
            params[match.group(1)] = _read_value(call, match.end() - 1)
        if "Status" not in params:
            raise ValueError(f"an Add-Result call declares no -Status: {call[:80]!r}")
        required = params.get("Required")
        if required is None:
            cost = REQUIRED_DEFAULT
        elif required == "$false":
            cost = OPT_IN
        elif required == "$true":
            cost = REQUIRED_DECLARED
        else:
            raise ValueError(f"-Required is neither $true nor $false: {required!r}")
        sites.append((
            _unquote(params.get("Id", "")),
            _unquote(params.get("Name", "")),
            _statuses(params["Status"], joined),
            cost,
        ))
    if not sites:
        raise ValueError("no Add-Result call sites found -- the extractor is reading nothing")
    return sites


def off_sites(source: str) -> list[tuple[str, str, str]]:
    return sorted((i, n, cost) for i, n, statuses, cost in result_sites(source) if "OFF" in statuses)


class AnOffRowDeclaresWhetherItFailsTheRun(unittest.TestCase):
    def setUp(self):
        self.source = t.ps_source(DOCTOR)

    def test_every_site_that_can_be_off_declares_what_it_costs(self):
        expected = sorted((i, n, cost) for i, n, cost, _why in OFF_SITES)
        self.assertEqual(
            expected,
            off_sites(self.source),
            "the set of rows that can be reported OFF has changed.\n"
            "This is not a bookkeeping table. -Required DEFAULTS TO TRUE, and the verdict fails the "
            "run on any OFF row carrying it, so a new OFF site with nothing declared makes the "
            "doctor exit 1 wherever that control is unwired. That is right for a control with a "
            "shipped installer and wrong for one without: the vocabulary at the top of the doctor "
            "promises an opt-in control is 'reported only', and only -Required $false delivers it.\n"
            "Decide which this row is, pass -Required explicitly if it is opt-in, and add it here "
            "with the reason.",
        )

    def test_the_verdict_partitions_off_on_the_field_and_not_on_the_tag(self):
        """The exit code must keep reading `required`, not the status alone."""
        required = re.search(r"\$offRequired\s*=\s*([^\r\n]+)", self.source)
        optional = re.search(r"\$offOptional\s*=\s*([^\r\n]+)", self.source)
        self.assertIsNotNone(required, "the verdict no longer computes $offRequired")
        self.assertIsNotNone(optional, "the verdict no longer computes $offOptional")
        self.assertIn("$_.required", required.group(1))
        self.assertIn("'OFF'", required.group(1))
        self.assertIn("-not $_.required", optional.group(1))
        self.assertIn("'OFF'", optional.group(1))

        exit_one = re.search(r"if \(([^)]*\$offRequired[^)]*)\)\s*\{\s*\$exit = 1", self.source)
        self.assertIsNotNone(
            exit_one,
            "exit 1 is no longer computed from $offRequired. If it now reads the OFF tag directly, "
            "every opt-in control that is merely reported starts failing the run.",
        )
        self.assertNotIn(
            "$offOptional",
            exit_one.group(1),
            "an opt-in OFF row now fails the run. The vocabulary says it is reported only.",
        )

    def test_every_opt_in_off_row_is_named_where_operators_read_about_it(self):
        """A row that costs nothing has to be findable in prose, or it reads as an all-clear.

        INSTALL.md carries the enumeration ("Controls no installer wires", and the exit-code
        accounting under it). That enumeration went stale the moment a second opt-in row existed, and
        nothing caught it -- the drift was found by reading, one merge later.
        """
        install = t.read(INSTALL)
        opt_in = [(i, n) for i, n, cost in off_sites(self.source) if cost == OPT_IN]
        self.assertTrue(opt_in, "no opt-in OFF rows found -- the extractor is reading nothing")
        for row_id, name in opt_in:
            self.assertNotIn(
                "$", name,
                f"the opt-in row {row_id} has an interpolated name ({name!r}), so no fixed string "
                "can document it. Give it a literal name, or the enumeration in INSTALL.md cannot "
                "be pinned to it.",
            )
            self.assertIn(
                name, install,
                f"INSTALL.md does not name the opt-in row {name!r}. It is reported by the doctor, "
                "counted on the OFF (opt-in) line, and fails nothing -- so the only place an "
                "operator learns it is a real hole is that prose.",
            )

    def test_every_status_in_the_vocabulary_has_a_declared_effect(self):
        declared = re.search(r"ValidateSet\(([^)]*)\)\]\[string\]\$Status", self.source)
        self.assertIsNotNone(declared, "Add-Result no longer constrains -Status to a ValidateSet")
        vocabulary = re.findall(r"'([^']*)'", declared.group(1))
        self.assertEqual(
            sorted(STATUS_EFFECT),
            sorted(vocabulary),
            "the status vocabulary has changed. Give the new tag an entry above saying what it costs. "
            "A tag the verdict does not read can be printed on every run and change nothing, which "
            "is how a control comes to look reported and enforced at the same time.",
        )
        used = set()
        for _i, _n, statuses, _cost in result_sites(self.source):
            used |= statuses
        self.assertEqual(
            set(), used - set(vocabulary),
            f"a call site emits a status outside the ValidateSet: {sorted(used - set(vocabulary))}",
        )

    def test_add_result_takes_exactly_the_parameters_this_scan_reads(self):
        """A parameter this scan does not know about is a call it reads incompletely."""
        block = self.source[self.source.index("function Add-Result"):]
        block = block[:block.index("$script:Results.Add(")]
        declared = sorted(set(re.findall(r"\]\$([A-Za-z]+)", block)))
        self.assertEqual(
            sorted(RESULT_PARAMS),
            declared,
            "Add-Result's parameters have changed. RESULT_PARAMS above is the list this scan reads "
            "values for, and it ignores anything else so an interpolated name containing -Leaf "
            "cannot be mistaken for a parameter. A new one left out of that list is simply not "
            "read, and every case here would keep passing while seeing less than the whole call.",
        )

    def test_the_scan_can_see_the_thing_it_is_looking_for(self):
        """Prove the instrument. A parser that matches nothing passes everything."""
        planted = (
            "Add-Result -Kind control -Id new.thing -Name 'new thing: installed' -Status OFF `\n"
            "    -Detail 'nothing invokes it'\n"
            "Add-Result -Kind control -Id opt.thing -Name 'opt thing' -Status OFF -Required $false\n"
            "Add-Result -Kind control -Id fine.thing -Name \"fine ($(Split-Path $cd -Leaf))\" -Status OK\n"
        )
        self.assertEqual(
            [("new.thing", "new thing: installed", REQUIRED_DEFAULT),
             ("opt.thing", "opt thing", OPT_IN)],
            off_sites(planted),
            "the extractor no longer sees a silently-required OFF site, which is the one it exists "
            "to see.",
        )
        # The interpolated name survives intact: a truncation here would silently match nothing.
        names = [n for _i, n, _s, _c in result_sites(planted)]
        self.assertIn("fine ($(Split-Path $cd -Leaf))", names)
        # And a form it cannot classify is an error, never a quiet pass.
        with self.assertRaises(ValueError):
            result_sites("Add-Result -Kind control -Id x -Name 'x' -Status $undefinedVariable\n")
        with self.assertRaises(ValueError):
            result_sites("# no call sites here at all\n")


if __name__ == "__main__":
    unittest.main()
