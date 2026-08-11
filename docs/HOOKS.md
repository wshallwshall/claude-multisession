# Hooks

## TLDR/BLUF

**What this is.** The map of every guardrail here to the event that fires it, the wiring contract
between an installer and a settings file, and the house rules for adding one.

**Why you should care.** Two different things are called a hook in this repository and they fail in
opposite ways. A harness hook can refuse a tool call but never sees a shell redirect; a git hook sees
every write route but only at commit time. Merging a hook does not install one. Not for you if you
are not running concurrent sessions.

**How to use it.** Read the two definitions below, then the wiring tables. The harness hooks are
PowerShell 7 and Windows-first; the git-hook checkers are stdlib-only Python behind `/bin/sh` shims
and are the portable part of the set.

---

Two different things are called a hook in this repository, and they fail in opposite ways.

**Harness hooks** are wired into a Claude Code `settings.json`. The client runs them at an event,
hands them a JSON payload on stdin, and reads a JSON decision back on stdout. They can refuse a tool
call before it happens.

**Git hooks** are installed into the shared git hooks directory. Git runs them at commit or push
time, hands them argv or stdin, and reads the exit code. They see every write route -- an edit tool,
a shell redirect, an editor, a subagent -- because they inspect the tree rather than a tool call.

Every guardrail here is one or the other, and each declares its posture in its own file header. This
document is the map, the wiring contract, and the house rules for adding one.

Platform note: the harness hooks are PowerShell 7 and Windows-first. The git-hook checkers -- the
three enumerated in the second table below -- are stdlib-only Python behind `/bin/sh` shims, and are
the portable part of the set.

---

## The event map

| Event | Script | Matcher | What it decides | Posture |
|---|---|---|---|---|
| `SessionStart` | `scripts/worktree/session-context.ps1` | -- | Prints the project banner and the live-peer coordination block into the new chat's starting context. Decides nothing. | fail open, silent |
| `SessionStart` | `scripts/worktree/worktree-selfheal.ps1` | -- | Repairs a shared primary checkout whose HEAD drifted, if its tree is clean; if the tree is **dirty** it touches nothing and reports the decline. Injects a heads-up when the session is sitting in a stub worktree. | fail open, silent on **error** |
| `PreToolUse` | `scripts/hooks/worktree_gate.ps1` | `Write\|Edit\|MultiEdit\|NotebookEdit`, `Bash\|PowerShell`, `Task\|Agent\|Workflow`, `EnterWorktree` (opt-in) | Denies a write whose **target path** is inside a governed primary; a write to the gate's own enforcement surface; a subagent dispatch from the primary; a git verb that swaps or discards the primary's tree; a hijack of another session's worktree; a shared-config disarm; a `git worktree remove\|move` aimed at somebody else's checkout. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/collision_gate.ps1` | `Edit\|Write\|MultiEdit\|NotebookEdit` | Denies an edit to a file another **live** session has uncommitted changes in. Reports, without denying, a file already committed on a live peer's branch. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/block-blanket-git-stage.ps1` | `Bash\|PowerShell` (hand-wired) | Denies `git add -A/--all/-u/.` and `git commit -a/-am/--all`. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/steer-inject.ps1` | `*` (opt-in, hand-wired) | Delivers a queued steering note as `additionalContext` at the next tool-call boundary. Decides nothing. | fail open, silent |
| `UserPromptSubmit` | `scripts/hooks/announce-session.ps1` | -- | Resolves live peers and asks the model to announce itself to them. Decides nothing. | fail open, **loud** |

| Git hook | Checker | What it decides | Posture |
|---|---|---|---|
| `commit-msg` | `scripts/hooks/claim_check.py` | Refuses a code-touching commit whose **subject** declares `<KIND> #N` when this worktree does not hold the claim on N. | **fail closed** |
| `pre-push` | `scripts/hooks/push_guard.py` | Refuses a direct push or deletion of a protected ref. | **fail closed** on config; fail open with no interpreter |
| `pre-commit` | `scripts/hooks/seq_check.py` | Refuses a commit that reuses, skips the index for, or duplicates a number in a configured sequence. **No installer wires this** -- see below. | **fail closed** |

Installers:

| Installer | Wires | Scope |
|---|---|---|
| `scripts/coord/install-coordination.ps1` | session banner, collision gate, announce | user `settings.json`, as re-resolving shims |
| `scripts/worktree/install-gate.ps1` | worktree gate | every config dir, as an installed **copy** |
| `scripts/worktree/install-selfheal.ps1` | selfheal backstop | one config dir at a time, as an installed **copy** |
| `scripts/coord/install-git-hooks.ps1` | claim gate, push guard | the clone's shared git hooks directory |

Nothing installs `block-blanket-git-stage.ps1`, `steer-inject.ps1`, or `seq_check.py`. Wire those by
hand.

`.claude/settings.example.json` is a real, tracked row for the blanket-stage guard, with the path
left as a loud placeholder. `docs/STEERING.md` carries the equivalent for the steering injector at
`settings.local.json` scope, where that one belongs.

An `.example.` file is inert by construction, because the harness loads `settings.json` and
`settings.local.json` only. Nothing here can be mistaken for an installed control.

`install-git-hooks.ps1` warns about the sequence gate when sequences are configured, because an
absent gate and a passing gate look the same from the outside.

---

## The harness wiring contract

A hook is an entry in the `hooks` object of a `settings.json`, keyed by event, grouped by matcher.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "pwsh -NoProfile -File \"C:/Users/<you>/.claude/hooks/worktree_gate.ps1\"",
            "timeout": 15,
            "statusMessage": "Checking worktree gate"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "# ccx-coord\n$c = (& git rev-parse --path-format=absolute --git-common-dir 2>$null); ...",
            "shell": "powershell",
            "timeout": 30,
            "statusMessage": "Session coordination"
          }
        ]
      }
    ]
  }
}
```

| Field | Meaning |
|---|---|
| `matcher` | Pipe-separated tool names. `PreToolUse` only. `SessionStart` and `UserPromptSubmit` take none. |
| `type` | `command` for everything here. |
| `command` | Either an absolute path to an installed copy, or an inline shim that re-resolves the script at run time. Both patterns ship; see below. |
| `shell` | Which interpreter runs an inline `command`. The coordination installer writes `powershell`; the copy-installers invoke `pwsh -NoProfile -File` inside the command string instead and omit the key. |
| `timeout` | Seconds. The shipped values are 15 for the gates, 15 for announce, 20 for the collision gate, 30 for the two `SessionStart` hooks. Announce's is that hook's **only** time bound. |
| `statusMessage` | What the user sees while it runs. |

Two wiring patterns, deliberately different:

* **Installed copy** (worktree gate, selfheal). The command names an absolute path outside every
  working tree. A hook script that lives inside a checkout vanishes on a branch switch, and a hook
  whose script is missing does **not** block -- the tool call runs anyway, silently. The cost of a
  copy is that it goes stale, so both installers hash it: `-Status` compares the installed SHA-256
  against the source and prints `*** STALE ***` when they differ.
* **Re-resolving shim** (banner, collision gate, announce). The command is a one-liner that asks git
  for the common directory, walks a fixed base list, and runs the first script it finds. Nothing
  falls stale -- a pull updates the hook everywhere at once. The cost is that a shim which resolves
  nothing exits silently and writes nothing, which is byte-identical to a healthy hook with no peers.
  That is why `install-coordination.ps1` writes a receipt and its `-Status` re-resolves each target
  live rather than trusting the settings entry.

Hook definitions from the user, project and local scopes are unioned, so a user-scope entry adds to a
project's own guards rather than replacing them. The installers here write user scope on purpose:
project settings live on one branch and reach a sibling worktree only if it merges them.

Markers are on-disk identity. `install-coordination.ps1` finds its own entries by the literal
`ccx-coord` or `ccx-announce` inside the command string, and the match is a substring test. So
**neither marker may contain the other**, in either direction, or one uninstall silently removes the
other's hook. Rename a marker and every existing install is orphaned. Do it once, in one commit.

---

## The output contract

### The `hookSpecificOutput` wrapper is mandatory

A bare `{"permissionDecision":"deny"}` is **silently ignored and the tool call proceeds**. Measured
on the repo this tooling was developed in, and reported upstream. Every deny in this repository is
written through one helper for exactly this reason.

```powershell
$payload = @{
    hookSpecificOutput = @{
        hookEventName            = "PreToolUse"
        permissionDecision       = "deny"
        permissionDecisionReason = $Reason
    }
}
[Console]::Out.Write(($payload | ConvertTo-Json -Compress -Depth 6))
exit 0
```

To say something without deciding anything, emit `additionalContext` and **no** `permissionDecision`
key. Adding one there converts a diagnostic into a blocked session, which inverts the posture:

```powershell
@{ hookSpecificOutput = @{
      hookEventName     = "PreToolUse"
      additionalContext = "[collision] The collision gate could NOT check this edit ..."
} } | ConvertTo-Json -Compress -Depth 6 | ForEach-Object { [Console]::Out.Write($_) }
```

`SessionStart` uses the same wrapper with `hookEventName = "SessionStart"`. `session-context.ps1` is
the exception: whatever it prints to stdout **is** the starting context, so it emits plain text.

### Never carry a decision in the exit code

Every hook in this repository exits 0 and puts its decision in the JSON. The reason is that
`exit 1` -- the intuitive "refuse" -- is not a refusal here: a non-zero-but-not-2 exit lets the tool
call through **silently**, which is how a missing hook script reads as an allow. Two consequences:

* Do not add `#Requires` to a hook whose failure mode matters. A requirements failure is raised
  before the body runs and exits non-zero, so the file's own error handling never gets a turn.
  `announce-session.ps1` carries no `#Requires` line for precisely this reason -- on
  `UserPromptSubmit`, a failure can block the user's prompt outright.
* Do not put a throwing expression in a **parameter default**. Defaults bind before line 1 of the
  body, so a throw there is uncatchable by the script's own `try`/`catch` and pre-empts any guard
  written below it. This has shipped twice: `Join-Path $env:USERPROFILE ...` as a default is null off
  Windows and raises a binding error. Every script in this family resolves the home directory
  null-safely inside a `$( ... )` subexpression, and the installers declare *no* default at all on
  the parameters their refusal guard depends on.

One further PowerShell trap, from the gate's own history: in a parameter default, write
`$( if (...) {...} else {...} )` and not `( if ... )`. A bare paren opens a command-invocation group,
PowerShell parses `if` as a command name, and the script dies before its first line.

That version shipped, and the whole test suite missed it. Every test passed `-ReposFile` explicitly,
and a parameter default is not evaluated when a value is supplied.

`tests/test_worktree_gate_no_args.py` runs the script with no arguments at all and requires it to
deny a write into a governed root. That is the only outcome proving the default both evaluated and
resolved to the file the installer writes.

### The git-hook contract

`install-git-hooks.ps1` writes a `/bin/sh` shim beside a copy of the Python checker. The shim finds
an interpreter (`CCX_PYTHON`, then `python`, then `python3`) and execs the checker; exit 0 allows,
exit 1 refuses. LF endings and no BOM -- `/bin/sh` will not run a script whose shebang ends in CR,
and the failure reads as "bad interpreter", not as "bad newline".

If no interpreter is found the shim **writes to stderr and exits 0**. That is fail-open, declared:
both gates are off for that commit or push, and they say so. `-Status` reports which interpreter it
resolved, and it asks the interpreter to run rather than trusting the lookup. On Windows a `python`
on PATH is often an app-execution alias that resolves cleanly and then does not execute anything. The
instrument must answer the question you asked.

`commit-msg` is the only hook that receives the commit message, so the claim gate cannot live
anywhere else. Bolted onto `pre-commit` it would look installed and silently never fire.

`install-git-hooks.ps1` **never writes `pre-commit`, at all** -- not to install, not to patch, not to
migrate. Two tools cannot both own that file. A hook framework that finds a foreign hook there may
rename it and invoke it from its own shim. That chain has failed on Windows and blocked every commit
in a repository until the shim was removed. Note that the renamed file *existing* did not
indicate success; only a real commit did. That is also why the sequence gate ships unwired: it needs
`pre-commit`, so you attach it to whatever framework already owns that file.

---

## House rules

### Declare the posture in the header, in one line

Every hook here opens with `POSTURE: FAILS OPEN` or the fail-closed equivalent, and says why. The
postures differ on purpose and the difference is the design:

* The **collision gate** fails open because it prevents rework. It must never be the reason a session
  cannot work.
* The **worktree gate** fails open too, but for a blunter reason: a guardrail that wedges all work
  gets uninstalled, and then it protects nothing.
* The **claim gate** and the **sequence gate** fail closed. A malformed claim reads as unclaimed; a
  git failure refuses the commit rather than being swallowed into "nothing is staged", which would
  read as a pass. Both are recoverable in one command. A false clean is not recoverable at all,
  because nobody looks.
* The **push guard** defaults to the strict direction when it cannot read its configuration, and
  announces on stderr when it is configured off.

A reader must be able to answer "what happens when this breaks?" from the header, without reading the
body.

### Fail open, but never silently

Every fail-open path in the collision gate used to `exit 0` with empty stdout. On that hook's stdout,
empty is byte-for-byte identical to "checked, nobody else is in this file". The gate's own failure
reached the session as reassurance -- for weeks.

You cannot detect a difference the producer never encoded. So:

* Emit a **named** notice on the fault path (`payload-unreadable`, `overlap-empty`,
  `overlap-failed`), keep the allow posture, and rate-limit per reason so a persistently broken
  dependency does not inject a notice into every single edit.
* Fail toward **noise**. If the rate-limit stamp cannot be read or written, emit the notice anyway --
  silence is the defect being fixed, so the failure mode of the noise-suppressor must be noise.
* Bound the throttle in **both** directions. A stamp dated in the future reads as eternally fresh and
  suppresses the notice forever: the same silence, now self-inflicted.
* Scope the throttle per worktree, not per repository. A repo-wide stamp means the first session to
  hit a broken gate silences it for every other session. Those sessions read that silence as
  "checked, nobody is here", which is precisely the defect the notice exists to remove.
* Where the notice cannot be JSON, because the failure happened before the hook could load its
  helpers, write it to **stderr**, which is not parsed as a decision, and to the deny log. Both
  `worktree_gate.ps1` and `block-blanket-git-stage.ps1` print `NOT ENFORCING` there when a dot-source
  fails.

### `[]` is not the same as nothing, and the fix belongs in the producer

The sharpest version of the above needed no breakage at all. A helper had **no representation** for
"nobody else": piping an empty array into `ConvertTo-Json` sends zero objects down the pipeline, so
`ConvertTo-Json` never runs and nothing is printed. `-AsArray` does not help -- it shapes output that
already exists. A resolved "nobody else is in this file" and a script that never produced a verdict
were the same zero bytes.

Make the producer always emit a distinguishable value (`[]` for no hits), and only then let the
consumer treat silence as a fault. The fix is not "check harder"; it is to give the two states
different bytes. The collision gate now says so in a comment at the point of the test:

```powershell
$text = (@($raw) -join "`n").Trim()
if (-not $text) {
    Write-Unresolved "overlap-empty" "the overlap script produced no output at all (a resolved 'nobody else' is '[]', not nothing)"
}
```

The same rule applies to configuration. An explicitly empty list is a decision; an absent key is not.
`"protectedRefs": []` says "this repository deliberately protects nothing" and disables the push
guard **with a message on stderr**; a missing key means nobody chose, and gets the defaults. The
claim gate treats `docPaths.prefixes: []` the same way.

### The first rule to fire is the only one that speaks

`Write-Deny` exits. So rules are evaluated in source order and there is **no defense in depth between
them** -- a later rule guarding the same case is unreachable, and looks live in the source. Two
practical consequences:

* Order rules by cost and blast radius, and say why in a comment. The dispatch rule is checked first
  in the worktree gate because it is the cheapest place to stop a fan-out that would otherwise run
  for an hour and report success while writing nothing.
* Never let two rules each assume the other owns a case. That has shipped: one rule resolved the
  target from `-C` or cwd only and declined; the other resolved a `cd`, then returned with a comment
  saying the first rule owned it. Both bowed out, and a whole family of tree-swapping commands was
  allowed.

### Log every deny

Before `Write-GateLog` existed, the worktree gate wrote its decision to stdout and exited 0. Nothing
on the machine could answer "how many drift events did this prevent", "is the false-positive rate one
a day or one in a thousand", or "did that fix change anything". Every severity ranking about the
machinery was therefore an opinion.

A receipt is smaller than any other fix and it is the prerequisite for ranking the rest. The shipped
record is one tab-separated line carrying at least: timestamp, hook version, the 12-character
digest of the gate file that adjudicated, pid, rule, tool, cwd, and a short detail each rule
composes itself. The digest is there because the version label is hand-maintained and has been
wrong before -- a label alone cannot tell you which copy of the hook actually ran.

Three constraints that are easy to get wrong:

* **Never log the raw command or file contents.** Each rule passes a detail it composed (a verb, a
  target path), so an argument carrying a secret cannot reach a plaintext log.
* **One record is one line, always.** The detail is derived from tool input, so strip `\r`, `\n` and
  `\t` and cap the length before composing -- otherwise a crafted path forges extra records in a log
  whose whole purpose is counting.
* **Expect contention.** Every session on the machine appends to one file. `Add-Content` silently
  dropped records under load, and a lossy counter is worse than none because it reads as a
  measurement. Retry a bounded number of times, then give up quietly: the deny matters, the receipt
  does not.

Logging is also what lets a parent session see what its fan-out was denied, since a subagent's
denials do not reliably surface to it.

### False positives are the expensive failure

A gate that cries wolf gets routed around, and then you have nothing. Real denials from the
verb-scanning gate, all of them wrong:

* `git status` followed by a newline and `echo about to merge stuff` -- denied on `merge`, from prose
  on line two.
* `echo "git checkout main"` -- denied.
* `git commit -m "chore: clean up dead code"` -- denied on `clean`.
* `git restore <two files>`, run from a worktree, denied as "would change the working tree of the
  SHARED PRIMARY" because a later `cat <primary>/...` in the same compound command named the primary.

That last one is the worst kind: the refusal text was **wrong about what the command did**, so the
operator reading it was told the primary was at risk when it never was. A gate that misdescribes what
it blocked teaches people to disbelieve it.

The mitigations, all shipped:

* Split into simple commands with a quote-aware walker, not a regex -- `git commit -m "a; b"` must
  not be cut in half.
* Keep two forms of every segment: the **raw** command (parse paths from this) and a **scan** form
  with quoted spans blanked (decide verbs from this). Deciding a verb from the raw string produces
  every false positive above; parsing a path from the blanked string fails, because the same blanking
  erases the path. Both forms travel together and each rule uses the right one.
* Recurse one level into interpreter arguments -- `pwsh -Command "..."`, `bash -c "..."`,
  `cmd /c "..."`. Those are quoted, but they are code that runs. Blanking them turned a long-standing
  deny into an allow when it was tried.
* Require a verb to be a whole subcommand. `\bmerge\b` also matches `merge-base` and `merge-tree`,
  which are read-only and are exactly what a session should be using instead.
* Match a path only at a **directory boundary**. A sibling worktree named `<primary>-<task>` contains
  the primary's path as a prefix, so a plain substring test flags it.
* Write ALLOW-asserting tests: a multi-line command, an echoed command, a commit message containing a
  blocklisted verb, and a path that merely resembles a governed one.

Where a cheap test is genuinely unsure, land on the deny side -- but only after the structural checks
have had their turn, and say in a comment which direction you chose and why.

### Enumerated coverage means every hole is silent

A verb list that omits a verb allows it, and nothing anywhere says so. The list in the worktree gate
once omitted `worktree`, which is two tokens where every other entry is one -- and
`git worktree remove` destroys another session's checkout. `sparse-checkout` could not match by
construction, because the pattern required whitespace before the verb and a hyphen precedes
`checkout`.

Rules keyed on **tool names** have the same property, one layer up: a tool that is not in the
settings matcher never invokes the hook at all.

* Prefer deny-by-default where you can.
* Where you cannot, assert against an **expectation**, never a count. A count of "3" is not
  information unless the reader knows whether 3 is right. `install-gate.ps1 -Status` reads the tools
  the **installed** script branches on and diffs them against the wired matchers. It reports
  `UNWIRED` (implemented but never fires) and `stray` (matched but ignored) separately. And it
  reports deliberately-optional rules as `opt-in`, not as `UNWIRED`, because a status line that cries
  wolf about a known state is one a reader learns to skip.
* Express a rule so the tripwire can see it. Rule 4 is written as `$tool -in @("EnterWorktree")`
  rather than a string comparison, specifically so the wiring test parses it as handled. A rule has
  shipped implemented-with-no-matcher before.

### One splitter, one target resolver

Two gates once shipped two different command splitters, and they were not merely different. One was
strictly weaker in four ways:

- it cut a quoted `;` in half;
- it did not blank quoted spans;
- it did not look inside interpreter arguments;
- it required a segment to start with a bare `git` token, so `/usr/bin/git add -A` walked past.

Both now dot-source `scripts/hooks/_command.ps1` (split, plus `Test-CcxGitInvocation`) and
`scripts/hooks/_gittarget.ps1` (which repository does this command act on). Two copies of a safety
check drift, and the one that drifts is the one nobody is testing. When you harden one rule, sweep
every sibling that parses the same syntax. A case-sensitivity fix landed in one rule and was never
back-ported to the rule protecting the shared tree -- where PowerShell's case-insensitive `-match`
happily read git's lowercase `-c name=value` as the `-C <path>` flag.

Parse git's flags **case-sensitively**, and treat `--git-dir`, `--work-tree` and their environment
equivalents as target candidates, not just `-C`.

### A command-string gate is a guardrail, not a boundary

Any agent-authored script defeats it outright: `pwsh -File whatever.ps1` carries no verb to match.
This is not adversarial or hypothetical -- a sanctioned repair script is exactly that shape. So is
`gh pr checkout <n>`, which carries no `git` token at all.

Say so in the header, and do not let the splitter grow into a shell parser: a more elaborate parser
only makes the boundary look firmer than it is. The real backstop for the shell write path is a
commit-time hook, which inspects the tree rather than the argument.

And when you name a backstop, verify it implements the predicate you are relying on. A gate header
once pointed at a `pre-commit` hook as its backstop for shell-route writes. That hook was a stock
dispatcher for unrelated linters, none of which had any notion of which checkout was being written
to. The only actual control on that path was the deny text asking politely. An admitted gap is safer
than a false one, because the next reader stops looking.

### State the cost of an always-on hook

Measured on the repo this tooling was developed in: the coordination shim costs roughly half a second
on **every** user prompt in **every** repository on the machine. The peer lookup adds about a second
more on the prompts where it actually runs. A `PreToolUse` hook on `*` costs a process spawn
before every tool call -- roughly a third of a second, most of which is bare interpreter startup and
unavoidable.

Consequences, all of them shipped decisions:

* Order cheap guards before expensive lookups, so the expensive one runs only when it can matter.
* Back off deliberately, and publish the schedule. Announce re-checks for peers at most once a minute
  for its first ten checks, then once every ten minutes, and stops entirely after forty.
* An occasional-use feature does not belong on `*`. `steer-inject.ps1` is deliberately not wired in
  any shared settings file; enable it per worktree in that worktree's local settings when you
  actually want it.
* Gate a user-global hook on the repository having opted in, so it does not fire in unrelated
  projects. The probe here is the **presence of `ccx.config.json`** -- deliberately not "does some
  implementation file exist", which is true in a half-installed tree and false in a repository that
  vendors the scripts elsewhere.
* Give the harness a `timeout` that comfortably exceeds the hook's measured cost. Whether the harness
  kills the process at the timeout or merely stops waiting is not observable from inside the hook, so
  do not build a design that depends on knowing.

### Test the real pair, not stubs

The first attempt at the empty-output fix made an ordinary edit to an untouched file fail the gate --
i.e. most edits. The tests were green, because the stubs emitted a JSON shape the real helper never
produced. The tests validated an interface that did not exist.

* Run the real components together at least once before shipping a contract change between them.
* Parameterise the seam so a test can drive the **real** gate against a fixture, rather than
  re-implementing the rule. `collision_gate.ps1` takes `-OverlapScript`, `-StateDir` and
  `-PathOverride` for exactly this; a test that asserts a copy of the rule proves nothing.
* Isolate shared state per test. A throttle sharing one directory with the suite would make the first
  test's notice suppress the second's.
* When two components share a field, version-lock them and say so. The collision gate reads the
  overlap script's `MatchedDirty` field, and a row lacking that property is treated as dirty -- so a
  stale producer degrades the gate to over-blocking rather than to silently permitting a real
  collision. Over-block is safe; under-block is a silent collision.

---

## Establishing what a hook actually does

Reading the source tells you what a rule *would* do. It does not tell you whether that rule runs.

The installed copy, the settings matcher and the source can all disagree, and rules exit on first
match so a later rule may be unreachable. Measured on the repo this tooling was developed in: a gate
had 85 passing tests and every one of them bound the **repo** copy, while enforcement ran from an
installed copy that was days behind. Reverse drift is equally invisible -- delete a rule from source
and the stale installed copy keeps enforcing it forever, while every test correctly reports it gone.

So establish behavior by driving crafted input into the **installed** hook and reading the decision
it emits:

```powershell
$payload = @{
    tool_name  = 'Write'
    cwd        = 'C:/path/to/a/governed/primary'
    tool_input = @{ file_path = 'C:/path/to/a/governed/primary/README.md' }
} | ConvertTo-Json -Compress -Depth 6

$payload | pwsh -NoProfile -File "$HOME/.claude/hooks/worktree_gate.ps1"
```

Four rules for that probe, each learned by getting it wrong:

1. **Pair every attack with a negative control.** A write outside every governed root, and a write
   into a nested worktree, must both be ALLOWED. Without the negative, "refused correctly" and
   "refused because it could not import its own substrate" are the same result.
2. **Make the probe itself fail loudly.** While building `bin/ccx-doctor.ps1`, four attack payloads
   were passed under a parameter name that bound to nothing -- silently, no error -- so they carried
   no `tool_input` at all. Every path-keyed rule correctly allowed them, and the doctor reported the
   gate broken. The gate was fine; the probe was broken. The payload builder now throws on an empty
   `tool_input`, and an aborted sequence records `??`, never a pass.
3. **If your must-fail case and your under-test case produce the same bytes, the result is
   UNTESTED, not negative.** Probing whether an `mcp_tool` hook could reach a host-provided MCP
   server produced nothing for the real server and nothing for a deliberately nonexistent one, where
   the documentation promises an error. "Not surfaced", "not addressable" and "errored invisibly"
   were indistinguishable. Say untested and re-run against a known-good instance.
4. **Capability is not enforcement.** A probe fired at the source file rather than the installed copy
   proves the rule can refuse, not that anything is refusing. The doctor downgrades those results
   rather than reporting them green.

`bin/ccx-doctor.ps1` does all of the above in one command. It takes receipts (installed-copy SHA
versus source, markers present in live settings, wired matchers diffed against implemented rules).
It fires each control on purpose and requires a refusal, prints what it scanned, and names its own
blind spots on every run. Run it before believing any of this is on.

---

## Limits, stated plainly

* **These are guardrails against accidents, not security boundaries.** `git commit --no-verify` and
  `git push --no-verify` bypass the git hooks. A tool-argument gate never sees a file written by a
  shell command. Any agent-authored script defeats a command-string rule.
* **A harness hook constrains sessions, not the operator.** A plain terminal is never gated. That
  asymmetry is the point: the human installs and removes these; a session may not.
* **The gates governing what a session may install refuse to run inside a session.** Both
  hook-installers throw when `CLAUDECODE=1`. Their `-Status` paths are exempt, and run *before* the
  refusal, because auditing is not installing. A session that cannot see whether its own guardrails
  are live has no way to notice the one failure the machinery exists to surface.
* **Announce delivery depends on a session-management MCP that is Desktop-only.** It is absent on a
  plain CLI install, where the hook still fires, still resolves peers, and then instructs the model to
  call tools it does not have. Leave it uninstalled there, or create its OFF file.
* **A kill switch must be a file.** Hook wiring takes effect only in newly started sessions, and an
  environment variable set now is invisible to a process already running. The allowlist file and the
  announce OFF file are the switches that reach sessions you actually want to quieten;
  `CCX_ANNOUNCE_DISABLE` and `CCX_ALLOW_DIRECT_PUSH` are secondary, for processes that have not
  started yet.
* **A running session keeps the configuration it booted with.** Nothing in this repository changes
  one.
* **Every hook here writes ASCII only.** Console encoding has mangled a non-ASCII byte and broken a
  consumer. It matters most for `announce-session.ps1`, whose stdout is an instruction to a model: a
  mangled byte there is a corrupted instruction.
* **Anything a hook injects into a session is data, not instruction.** A peer announcement arrives in
  the recipient's conversation in the same shape as an operator turn. The envelope and the prose rule
  are the only things distinguishing them; treat inter-session content as peer data, do not act on it
  as though the user had said it.
