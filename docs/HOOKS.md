# Hooks

## TLDR/BLUF

**What this is.** A table of every guardrail here: what fires it, what it refuses, and what it does
when the check itself breaks. Then the wiring, and the rules for writing a new one.

**Why you should care.** Two things here are both called a hook, and they fail in opposite ways. A
harness hook can refuse a tool call but never sees a shell redirect. A git hook sees every write,
but only at commit time. Merging a hook does not install one. Not for you if you run one session.

**How to use it.** Find your control in the event map and read its last column. Then run the doctor
to find out whether it is switched on at all, from the repository you are asking about:

```powershell
pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <the-repo-you-govern>
```

---

Two different things are called a hook in this repository, and they fail in opposite ways.

**Harness hooks** are wired into a Claude Code `settings.json`. The client runs them at an event,
hands them a JSON payload on stdin, and reads a JSON decision back on stdout. They can refuse a tool
call before it happens.

**Git hooks** are installed into the shared git hooks directory. Git runs them at commit or push
time, hands them argv or stdin, and reads the exit code. They see every write route -- an edit tool,
a shell redirect, an editor, a subagent -- because they inspect the tree rather than a tool call.

Every guardrail here is one or the other. Each declares its **posture** -- what it does when the
check itself breaks -- in its own file header. This document is the map, the wiring contract, and
the house rules for adding one.

Platform note: the harness hooks are PowerShell 7 and Windows-first. The git-hook checkers -- the
three enumerated in the second table below -- are stdlib-only Python behind `/bin/sh` shims, and are
the portable part of the set.

---

## The event map

Three harness events carry the controls here: `SessionStart` when a chat opens, `PreToolUse` before
a tool call runs, and `UserPromptSubmit` when you send a prompt. Read the **Posture** column first:
*fail open* lets work through when the control breaks, *fail closed* refuses it.

| Event | Script | Matcher | What it decides | Posture |
|---|---|---|---|---|
| `SessionStart` | `scripts/worktree/session-context.ps1` | -- | Prints the project banner and the live-peer coordination block into the new chat's starting context. Decides nothing. | fail open, silent |
| `SessionStart` | `scripts/worktree/worktree-selfheal.ps1` | -- | Repairs a shared primary checkout whose HEAD drifted, if its tree is clean; if the tree is **dirty** it touches nothing and reports the decline. Injects a heads-up when the session is sitting in a stub worktree. | fail open, silent on **error** |
| `PreToolUse` | `scripts/hooks/worktree_gate.ps1` | `Write\|Edit\|MultiEdit\|NotebookEdit`, `Bash\|PowerShell`, `Task\|Agent\|Workflow`, `EnterWorktree` (opt-in) | Denies a write whose **target path** is inside a governed primary; a write to the gate's own enforcement surface; a subagent dispatch from the primary; a git verb that swaps or discards the primary's tree; a hijack of another session's worktree; a shared-config disarm; a `git worktree remove\|move` aimed at somebody else's checkout. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/collision_gate.ps1` | `Edit\|Write\|MultiEdit\|NotebookEdit` | Denies an edit to a file a live peer **worktree** has uncommitted changes in -- your own worktree is skipped, so a second session in it is invisible. Reports, without denying, a file already committed on a live peer's branch. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/block-blanket-git-stage.ps1` | `Bash\|PowerShell` (hand-wired) | Denies `git add -A/--all/-u/.` and `git commit -a/-am/--all`. | fail open, **loud** |
| `PreToolUse` | `scripts/hooks/steer-inject.ps1` | `*` (opt-in, hand-wired) | Delivers a queued steering note as `additionalContext` at the next tool-call boundary. Decides nothing. | fail open, silent |
| `UserPromptSubmit` | `scripts/hooks/announce-session.ps1` | -- | Resolves live peers and asks the model to announce itself to them. Decides nothing. | fail open, **loud** |

| Git hook | Checker | What it decides | Posture |
|---|---|---|---|
| `commit-msg` | `scripts/hooks/claim_check.py` | Refuses a code-touching commit whose **subject** declares `<KIND> #N` when this worktree does not hold the claim on N. | **fail closed** |
| `pre-push` | `scripts/hooks/push_guard.py` | Refuses a direct push or deletion of a protected ref. | **fail closed** on config; fail open with no interpreter |
| `pre-commit` | `scripts/hooks/seq_check.py` | Refuses a commit that reuses a number, skips the index for one, duplicates one, or adds one never allocated to this worktree. **No installer wires this** -- see below. | **fail closed** |

Installers:

| Installer | Wires | Scope |
|---|---|---|
| `scripts/coord/install-coordination.ps1` | session banner, collision gate, announce | **one** user `settings.json` per run, as re-resolving shims |
| `scripts/worktree/install-gate.ps1` | worktree gate | every config dir, as an installed **copy** |
| `scripts/worktree/install-selfheal.ps1` | selfheal backstop | one config dir at a time, as an installed **copy** |
| `scripts/coord/install-git-hooks.ps1` | claim gate, push guard | the clone's shared git hooks directory |

Nothing installs `block-blanket-git-stage.ps1`, `steer-inject.ps1`, or `seq_check.py`. Wire those by
hand.

**The goal.** Switch on a control no installer covers.

**What to do.** Each of the three goes somewhere different:

| Control | Where it goes |
|---|---|
| Blanket-stage guard | Copy its tracked row out of `.claude/settings.example.json` into a real `settings.json`, and replace the loud placeholder path |
| Steering injector | A `settings.local.json` row, per worktree. [Steering](STEERING.md) has it |
| Sequence gate | **Not a settings row at all** -- a `pre-commit` hook you own. [Wiring the pre-commit hook](SEQUENCE-ALLOC.md#wiring-the-pre-commit-hook) has the snippet |

**What happens next.** Nothing, until you edit a live file. An `.example.` file is inert by
construction, because the harness loads `settings.json` and `settings.local.json` only. Nothing here
can be mistaken for an installed control.

**Before you wire the sequence gate, know its failure mode.** It is fail-closed and it imports
`_ccxconfig.py` from beside itself. Copy it without that module and it exits 1 on every commit, for
a reason unrelated to sequences.

Unlike the other two checkers it ships behind no `/bin/sh` shim, so you supply the interpreter.

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

* **Installed copy** (worktree gate, selfheal): an absolute path outside every worktree. A script
  inside a checkout vanishes on a branch switch, and a missing script does **not** block, silently.

  Copies go stale. `install-gate.ps1 -Status` hashes its copy and prints `*** STALE ***` when the
  SHA-256 differs.

  **`install-selfheal.ps1` has no `-Status`.** It takes `-ConfigDir` and `-HookPath` only, and
  re-copies the source unconditionally. Only `bin/ccx-doctor.ps1` reports a stale selfheal copy.
* **Re-resolving shim** (banner, collision gate, announce): the command re-resolves the script from
  git's common directory, so nothing falls stale. A shim resolving nothing exits silently,
  byte-identical to a healthy hook with no peers. Its installer writes a receipt and `-Status`
  re-resolves live.

Hook definitions from the user, project and local scopes **merge, they do not replace**: a
user-scope entry adds to a project's own guards. The installers here write user scope on purpose.
Project settings live on one branch, and reach a sibling worktree only if it merges them.

Markers are on-disk identity. `install-coordination.ps1` finds its own entries by the literal
`ccx-coord` or `ccx-announce` in the command string, matched as a substring. So **neither marker may
contain the other**, or one uninstall silently removes the other's hook. A rename orphans every
install.

**Check that, rather than reading it.** Measured 2026-08-11 on the implementation behind
[session mail](SESSION-MAIL.md): four markers, every ordered pair, both directions, none contained
another.

The near miss the rule exists for is suffixing a marker already in use. A `ccx-mail-urgent` contains
`ccx-mail`, so installing the second strips the first's row and disarms it.

### Backgrounding is gated, so `asyncRewake` alone can block the session

A hook that waits -- a watcher rather than a gate -- needs `async` **and** `asyncRewake`, not
`asyncRewake` by itself. Backgrounding is gated on `isInteractive || hasStreamingInput`, so under
`claude -p` the hook takes the synchronous path and holds the session for its whole timeout.

Emit the pair only for the rows asking for it. **A `PreToolUse` gate that returns asynchronously is a
gate that does not gate**, so every existing row keeps its exact shape.

Give the harness timeout headroom over the script's own wait: 1200 seconds against a 900-second
watcher. A watcher killed at its timeout is indistinguishable from one that found nothing.

Measured 2026-08-11 against harness v2.1.221, on the implementation behind
[session mail](SESSION-MAIL.md).

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

Every hook in this repository exits 0 and puts its decision in the JSON. `exit 1` -- the intuitive
"refuse" -- is not a refusal here. A non-zero-but-not-2 exit lets the tool call through
**silently**, which is how a missing hook script reads as an allow. Two consequences:

* Think hard before adding `#Requires` to a hook whose failure mode matters. It is raised before
  the body runs and exits non-zero, so the file's own error handling never gets a turn.

  `announce-session.ps1` and `steer-inject.ps1` carry none. On `UserPromptSubmit` a failure can block
  the user's prompt outright.

  **The three PreToolUse gates do carry `#Requires -Version 7.3`**, and that is a deliberate trade
  the other way: below 7.3 they refuse to start rather than run half-parsed. The cost is that on
  PowerShell 7.0-7.2 all three are inert, and inert reads as an allow.
* Do not put a throwing expression in a **parameter default**: defaults bind before line 1, so a
  throw there escapes the script's `try`/`catch`. Shipped twice as `Join-Path $env:USERPROFILE ...`,
  null off Windows. Resolve home null-safely inside `$( ... )`; a guard's parameters get *no*
  default.

One further PowerShell trap, from the gate's own history: in a parameter default, write
`$( if (...) {...} else {...} )` and not `( if ... )`. A bare paren opens a command-invocation group,
PowerShell parses `if` as a command name, and the script dies before its first line.

That version shipped, and the whole test suite missed it. Every test passed `-ReposFile` explicitly,
and a parameter default is not evaluated when a value is supplied.

`tests/test_worktree_gate_no_args.py` runs the script with no arguments at all and requires it to
deny a write into a governed root. That is the only outcome proving the default both evaluated and
resolved to the file the installer writes.

### A shim ending in `break` discards the one exit code that carries

Exit 2 is the code the harness reads, so a hook that signals through it depends on every wrapper
between it and the harness preserving it. The shared re-resolving shim ends `& $s; break`, and exits
0.

Measured 2026-08-11 on the implementation behind [session mail](SESSION-MAIL.md), driving a stub
script in place of the hook:

| Shim spelling | Stub exits | Process exit code |
|---|---|---|
| `exit $LASTEXITCODE` | 2 | 2 |
| `exit $LASTEXITCODE` | 0 | 0 |
| `& $s; break` | 2 | **1** |
| `exit $LASTEXITCODE` | script absent | 0 |

Row three is the one to read. The shared shim does not merely fail to forward 2, it reports **1**. So
the payload is discarded *and* logged as a hook error, which reads as a broken hook rather than a
dropped signal.

Row four is the negative control. Outside a repo nothing ran, so the fall-through has to reach
`exit 0` rather than forward a stale code: put the `exit` **inside** the `Test-Path` branch.

### The git-hook contract

`install-git-hooks.ps1` writes a `/bin/sh` shim beside a copy of the Python checker. It finds an
interpreter (`CCX_PYTHON`, then `python`, then `python3`) and execs the checker; exit 0 allows, exit
1 refuses. LF endings, no BOM: `/bin/sh` will not run a CR shebang, and says "bad interpreter".

With no interpreter the shim **writes to stderr and exits 0** -- fail-open, declared, both gates off
for that commit or push. `-Status` asks the interpreter to run rather than trusting the lookup: on
Windows a `python` on PATH is often an app-execution alias that resolves cleanly and runs nothing.

`commit-msg` is the only hook that receives the commit message, so the claim gate cannot live
anywhere else. Bolted onto `pre-commit` it would look installed and silently never fire.

`install-git-hooks.ps1` **never writes `pre-commit`, at all**: two tools cannot both own that file.
A framework that renames a foreign hook there and runs it from its own shim has blocked every commit
on Windows until the shim was removed. The sequence gate ships unwired; it needs `pre-commit`.

---

## House rules

### Declare the posture in the header, in one line

A hook should open with `POSTURE: FAILS OPEN` or the fail-closed equivalent, and say why. Three do
today -- the collision gate, the blanket-stage guard and the steering injector. The worktree gate
states its posture in prose 30 lines into `.DESCRIPTION`, which is worse and worth fixing.

The postures differ on purpose and the difference is the design:

* The **collision gate** fails open because it prevents rework. It must never be the reason a session
  cannot work.
* The **worktree gate** fails open too, but for a blunter reason: a guardrail that wedges all work
  gets uninstalled, and then it protects nothing.
* The **claim gate** and the **sequence gate** fail closed. A malformed claim reads as unclaimed. A
  git failure refuses the commit rather than being swallowed into "nothing is staged", which reads
  as a pass. Both are recoverable in one command. A false clean is not, because nobody looks.
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
  `overlap-failed`), and keep the allow posture. Rate-limit per reason, so a persistently broken
  dependency does not inject a notice into every single edit.
* Fail toward **noise**. If the rate-limit stamp cannot be read or written, emit the notice anyway --
  silence is the defect being fixed, so the failure mode of the noise-suppressor must be noise.
* Bound the throttle in **both** directions. A stamp dated in the future reads as eternally fresh and
  suppresses the notice forever: the same silence, now self-inflicted.
* Scope the throttle per worktree, not per repository. A repo-wide stamp means the first session to
  hit a broken gate silences it for every other session. Those sessions read that silence as
  "checked, nobody is here", which is precisely the defect the notice exists to remove.
* Where the failure happened before the hook could load its helpers, the notice cannot be JSON.
  Write it to **stderr**, which is not parsed as a decision, and to the deny log.

  `worktree_gate.ps1` does both. `block-blanket-git-stage.ps1` writes only to stderr, in different
  case (`NOT enforcing`), and has no log function at all -- so a grep for the upper-case string finds
  one of the two, and the deny log records one of the two.

### Every exit from a stateful hook is a state transition

A hook that writes state between invocations has a state machine, whether or not anyone drew one.
Every exit is a transition in it, including the ones a guard takes and the one the outer catch takes.

Enumerate the exits, route them through one writer, and test the **table**: outcome code by outcome
code, asserting the state that results and whether each counter advanced. Testing the paths leaves
the table unread.

The throttle stamps in the rule above and announce's backoff ladder below are both this shape.

Measured in August 2026 on a separate implementation of the design behind
[session mail](SESSION-MAIL.md). One file had seven post-guard exits, each hand-rolling its own state
write, and four were wrong:

- One exit left the marker armed, so a kill ladder fired on the third consecutive prompt and injected
  a false "lookup did not return" line hourly, forever.
- That ladder never advanced the counter its own cap reads, so nothing could bound it.
- One exit never cleared the backoff floor.
- The outer catch left state armed entirely.

**Care is not sufficient here, and that was measured too.** A mutant differing by one line passed the
whole 50-test suite.

Three consecutive review rounds each caught the previous instance and missed the next, because every
new branch was audited against the last defect rather than against the invariant.

**A single-invocation test is structurally blind to this class.** Most tests in this space assert an
absence, and a hook that does nothing satisfies them. A defect here is silent and permanent: the
state one invocation leaves is the state the next one reads.

### `[]` is not the same as nothing, and the fix belongs in the producer

A helper had **no representation** for "nobody else": piping an empty array into `ConvertTo-Json`
sends zero objects down the pipeline, so it never runs and prints nothing. `-AsArray` does not
help -- it shapes output that already exists. A resolved verdict and no verdict were the same zero
bytes.

Make the producer always emit a distinguishable value (`[]` for no hits), and only then let the
consumer treat silence as a fault. The fix is not "check harder"; it is to give the two states
different bytes. The collision gate now says so in a comment at the point of the test:

```powershell
$text = (@($raw) -join "`n").Trim()
if (-not $text) {
    Write-Unresolved "overlap-empty" "the overlap script produced no output at all (a resolved 'nobody else' is '[]', not nothing)"
}
```

The same rule applies to configuration: an explicitly empty list is a decision, an absent key is
not. `"protectedRefs": []` protects nothing and disables the push guard **with a message on
stderr**; a missing key gets the defaults. The claim gate treats `docPaths.prefixes: []` the same
way.

### The first rule to fire is the only one that speaks

`Write-Deny` exits. So rules are evaluated in source order, and there is **no defense in depth
between them**. A later rule guarding the same case is unreachable, and looks live in the source.
Two practical consequences:

* Order rules by cost and blast radius, and say why in a comment. The dispatch rule is checked first
  in the worktree gate because it is the cheapest place to stop a fan-out. Unstopped, that fan-out
  runs for an hour and reports success while writing nothing.
* Never let two rules each assume the other owns a case. It has shipped: one rule resolved the
  target from `-C` or cwd only and declined. The other resolved a `cd`, then declined with a comment
  saying the first rule owned it. A family of tree-swapping commands was allowed.

### Log every deny

Before `Write-GateLog` existed, the worktree gate wrote its decision to stdout and exited 0. Nothing
could answer "how many drift events did this prevent" or "is the false-positive rate one a day or
one in a thousand". Every severity ranking was an opinion. A receipt is the smallest fix.

The shipped record is one tab-separated line, carrying at least:

* the timestamp, the hook version, and the 12-character digest of the gate file that adjudicated;
* the pid, the rule, the tool, and the cwd;
* a short detail each rule composes.

The hand-maintained version label has been wrong, and cannot name the copy that ran.

Three constraints that are easy to get wrong:

* **Never log the raw command or file contents.** Each rule passes a detail it composed (a verb, a
  target path), so an argument carrying a secret cannot reach a plaintext log.
* **One record is one line, always.** The detail is derived from tool input, so strip `\r`, `\n` and
  `\t` and cap the length before composing. Otherwise a crafted path forges extra records in a log
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
  SHARED PRIMARY". A later `cat <primary>/...` in the same compound command had named the primary.

That last one is the worst kind. The refusal text was **wrong about what the command did**, so the
operator was told the primary was at risk when it never was. A gate that misdescribes what it
blocked teaches people to disbelieve it.

The mitigations, all shipped:

* Split into simple commands with a quote-aware walker, not a regex -- `git commit -m "a; b"` must
  not be cut in half.
* Keep two forms of every segment, travelling together: the **raw** command (parse paths from this)
  and a **scan** form with quoted spans blanked (decide verbs from this). A verb decided from the
  raw string produces every false positive above; a path parsed from the blanked string is erased.
* Recurse one level into interpreter arguments -- `pwsh -Command "..."`, `bash -c "..."`,
  `cmd /c "..."`. Those are quoted, but they are code that runs. Blanking them turned a long-standing
  deny into an allow when it was tried.
* Require a verb to be a whole subcommand. `\bmerge\b` also matches `merge-base` and `merge-tree`,
  which are read-only and are exactly what a session should be using instead.
* Match a path only at a **directory boundary**. A sibling worktree named `<primary>-<task>` contains
  the primary's path as a prefix, so a plain substring test flags it.
* Write ALLOW-asserting tests: a multi-line command, an echoed command, a commit message containing a
  blocklisted verb, and a path that merely resembles a governed one.

Where a cheap test is genuinely unsure, land on the deny side. Do it only after the structural
checks have had their turn, and say in a comment which direction you chose and why.

### Enumerated coverage means every hole is silent

An omitted verb is allowed, and nothing says so. The worktree gate's list once omitted `worktree` --
two tokens, not one -- and `git worktree remove` destroys another session's checkout.
`sparse-checkout` cannot match: the pattern required whitespace before a verb, and a hyphen
precedes `checkout`.

Rules keyed on **tool names** have the same property, one layer up: a tool that is not in the
settings matcher never invokes the hook at all.

* Prefer deny-by-default where you can.
* Where you cannot, assert against an **expectation**, never a count: "3" informs nobody who cannot
  say whether 3 is right. `install-gate.ps1 -Status` diffs the **installed** script's rules against
  wired matchers, reporting `UNWIRED` (never fires), `stray` (matched, ignored) and `opt-in`
  separately.
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
`scripts/hooks/_gittarget.ps1` (which repository a command acts on). The copy that drifts is the one
nobody tests. Harden one rule and sweep every sibling that parses the same syntax.

Parse git's flags **case-sensitively** -- PowerShell's case-insensitive `-match` read git's
lowercase `-c name=value` as the `-C <path>` flag in the rule protecting the shared tree. Treat
`--git-dir`, `--work-tree` and their environment equivalents as target candidates, not just `-C`.

### A command-string gate is a guardrail, not a boundary

Any agent-authored script defeats it outright: `pwsh -File whatever.ps1` carries no verb to match.
This is not adversarial or hypothetical -- a sanctioned repair script is exactly that shape. So is
`gh pr checkout <n>`, which carries no `git` token at all.

Say so in the header, and do not let the splitter grow into a shell parser: a more elaborate parser
only makes the boundary look firmer than it is. The real backstop for the shell write path is a
commit-time hook, which inspects the tree rather than the argument.

Verify a named backstop implements the predicate you rely on. A gate header once named a
`pre-commit` hook that was a dispatcher for unrelated linters, none knowing which checkout was
written to. The only control there was the deny text asking politely. An admitted gap is safer than
a false one.

### State the cost of an always-on hook

Measured on the repo this tooling was developed in:

* the coordination shim costs roughly half a second on **every** user prompt in **every**
  repository;
* the peer lookup costs about a second more, where it runs;
* a `PreToolUse` hook on `*` costs a process spawn per tool call, roughly a third of a second.

Consequences, all of them shipped decisions:

* Order cheap guards before expensive lookups, so the expensive one runs only when it can matter.
* Back off deliberately, and publish the schedule. Announce re-checks for peers at most once a minute
  for its first ten checks, then once every ten minutes, and stops entirely after forty.
* An occasional-use feature does not belong on `*`. `steer-inject.ps1` is deliberately not wired in
  any shared settings file; enable it per worktree in that worktree's local settings when you
  actually want it.
* Gate a user-global hook on the repository having opted in, so it does not fire in unrelated
  projects. The probe is the **presence of `ccx.config.json`**, not "does some implementation file
  exist", which is true in a half-installed tree and false where the scripts are vendored
  elsewhere.
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
  overlap script's `MatchedDirty` field, and a row lacking that property is treated as dirty: a
  stale producer over-blocks rather than silently permitting a real collision.

---

## Establishing what a hook actually does

Reading the source tells you what a rule *would* do, not whether it runs. The installed copy, the
settings matcher and the source can all disagree, and a first-match exit makes later rules
unreachable.

Measured on the repo this tooling was developed in: a gate had 85 passing tests, all bound to the
**repo** copy, while enforcement ran from an installed copy days behind. Reverse drift is as
invisible: delete a rule from source and the stale copy enforces it forever, and every test reports
it gone.

**The goal.** Find out what the hook you have installed decides, rather than what the source says it
would decide.

**What to do.** Run `bin/ccx-doctor.ps1`. It takes receipts (installed-copy SHA versus source,
markers in live settings, wired matchers diffed against implemented rules), fires each control and
requires a refusal, and names its own blind spots.

**What happens next.** You get a verdict per control. Most are backed by a refusal the doctor
provoked rather than by source it read.

Three are not, and it names them on every run: the collision gate's deny path needs a live peer
worktree it cannot stage, announce delivery cannot be proven from PowerShell, and the steering
injector has no attack. Read the blind spots with the verdict.

To drive one control by hand, feed crafted input into the **installed** hook and read the decision
it emits:

```powershell
$payload = @{
    tool_name  = 'Write'
    cwd        = 'C:/path/to/a/governed/primary'
    tool_input = @{ file_path = 'C:/path/to/a/governed/primary/README.md' }
} | ConvertTo-Json -Compress -Depth 6

$payload | pwsh -NoProfile -File "$HOME/.claude/hooks/worktree_gate.ps1"
```

A refusal comes back on stdout as JSON carrying `hookSpecificOutput.permissionDecision`. Anything
else, including no output at all, means the installed copy did not refuse -- whatever the source
says.

Four rules for that probe, each learned by getting it wrong:

1. **Pair every attack with a negative control.** A write outside every governed root, and a write
   into a nested worktree, must both be ALLOWED. Without the negative, "refused correctly" and
   "refused because it could not import its own substrate" are the same result.
2. **Make the probe itself fail loudly.** In `bin/ccx-doctor.ps1`, four attack payloads carried no
   `tool_input`, so every rule allowed them and the doctor called a fine gate broken. The builder
   now throws on an empty `tool_input`, and an aborted sequence records `??`, never a pass.
3. **If your must-fail case and your under-test case produce the same bytes, the result is
   UNTESTED, not negative.** An `mcp_tool` probe produced nothing for a real MCP server and nothing
   for a nonexistent one that the documentation says errors. Say untested and re-run against a
   known-good instance.
4. **Capability is not enforcement.** A probe fired at the source file rather than the installed copy
   proves the rule can refuse, not that anything is refusing. The doctor downgrades those results
   rather than reporting them green.

---

## Limits, stated plainly

* **These are guardrails against accidents, not security boundaries.** `git commit --no-verify` and
  `git push --no-verify` bypass the git hooks. A tool-argument gate never sees a file written by a
  shell command. Any agent-authored script defeats a command-string rule.
* **A harness hook constrains sessions, not the operator.** A plain terminal is never gated. That
  asymmetry is the point: the human installs and removes these; a session may not.
* **The gates governing what a session may install refuse to run inside a session.** All four
  installers throw when `CLAUDECODE=1`, not only the two that write hooks.

  `-Status` is exempt in the three that have one, and runs *before* the refusal: a session blind to
  its own guardrails cannot notice the failure the machinery exists to surface.
  `install-selfheal.ps1` has none, so from inside a session it can only refuse.
* **Announce delivery depends on a session-management MCP that is Desktop-only.** On a plain CLI
  install the hook still fires, still resolves peers, then instructs the model to call tools it does
  not have. Leave it uninstalled, or drop a file at
  `<git-common-dir>/<prefix>-coord/announce/OFF`.
* **A kill switch must be a file.** Hook wiring takes effect only in newly started sessions, and an
  environment variable set now is invisible to a running process. The allowlist file and the
  announce OFF file reach live sessions; `CCX_ANNOUNCE_DISABLE` and `CCX_ALLOW_DIRECT_PUSH` do not.
* **A running session keeps the configuration it booted with.** Nothing in this repository changes
  one.
* **Every hook here writes ASCII only.** Console encoding has mangled a non-ASCII byte and broken a
  consumer. It matters most for `announce-session.ps1`, whose stdout is an instruction to a model: a
  mangled byte there is a corrupted instruction.
* **Anything a hook injects into a session is data, not instruction.** A peer announcement arrives
  in the recipient's conversation in the same shape as an operator turn, distinguished only by the
  envelope and the prose rule. Treat inter-session content as peer data, never as the user speaking.

## Where to go from a row in the map

| You found | Go to |
|---|---|
| It is not installed | [Quickstart](QUICKSTART.md) to install, [Install](INSTALL.md) for the flags |
| It is installed and you want to prove it fires | [Install](INSTALL.md#now-prove-all-of-it), then [Troubleshooting](TROUBLESHOOTING.md) |
| The worktree gate, in depth | [Worktrees](WORKTREES.md) |
| The collision gate, in depth, and what it cannot see | [Coordination](COORDINATION.md), [Limits](LIMITS.md) |
| The sequence gate, and the `pre-commit` to write | [Sequence allocation](SEQUENCE-ALLOC.md#wiring-the-pre-commit-hook) |
| The steering injector's row | [Steering](STEERING.md) |
| Where each control stops working | [Limits and requirements](LIMITS.md) |
