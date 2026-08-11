# Case study: auditing a multi-session estate as one system

## TLDR/BLUF

**What this is.** A *method* document, audit date **2026-08-04**: how the controls in this repository
were audited as a single system, what the audit proved, and what it could not.

**Why you should care.** Each control here is small and readable, and reading one tells you nothing
about whether it is enforcing. Six design rules came out of the audit, and each is a consequence of a
control that looked installed and was not. Not for you if you want a status table: this deliberately
carries none, because a published inventory of what is unenforced is a map for routing around it.

**How to use it.** For the current status of *your* estate, do not read a document -- run
`pwsh -NoProfile -File bin/ccx-doctor.ps1`. Everything here is the reasoning that command encodes.

---

**Audit date: 2026-08-04.** This is a *method* document. It describes how the controls in this
repository were audited as a single system, what the audit was able to prove, and what it could not.
It deliberately contains no status table, no finding list, and no inventory of what is or is not
enforced on any particular machine. That information is a stale snapshot of one host on one day.
Published, it becomes a map for the next reader who wants to route around the guardrails rather than
use them.

If you want the current status of *your* estate, do not read a document. Run the audit:

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

Everything below is the reasoning that command encodes.

---

## Why the estate is the unit of audit, not the script

Each control in this repository is small and readable. Read `scripts/hooks/worktree_gate.ps1` and you
can state what it denies. Read `scripts/hooks/collision_gate.ps1` and you can state its posture. That
reading is worth almost nothing, because none of these files is what runs.

What runs is a *copy*. An installer places it outside every working tree. A matcher in a client config
root invokes it. It resolves helper files it expects to find beside itself, and it executes on a host
that may or may not have an interpreter for it. Every one of those joins can be wrong while every file
involved is individually correct. And here is the property that makes this class of system unusually
dangerous:

> **Every failure mode in this system is byte-identical to success.**

A hook can be missing entirely, installed but not wired, wired but pointing at a script that no
longer exists, or loaded but failing open. All of those produce the same thing a healthy hook with
nothing to say produces: exit 0, no output, work proceeds. There is no error, no warning, no degraded
mode. The session sees green. A stranger who has just cloned this repository and run one installer,
or none, sits in exactly that state and will conclude the guardrails are working.

So the audit's unit is the whole path from checkout to decision, and its currency is receipts.

---

## The four-layer model

Any single control exists at four layers at once. Each layer answers a different question, and a green
answer at one layer is not evidence about the next.

| Layer | The question it answers | Instrument | The failure that looks like success |
|---|---|---|---|
| **Source** | Does the rule exist in this checkout? | Read the file; run the test suite | The rule is merged, tested and green -- and has never been installed anywhere |
| **Installed** | Is that rule in the copy the client executes? | SHA-256 of the installed artifact vs the source | Installed copy is days behind source. Reverse drift is equally invisible: delete a rule from source and the stale installed copy keeps enforcing it forever, while every test correctly reports it gone |
| **Wired** | Does anything actually invoke that copy? | Read live matchers out of every config root; diff them against the rules the *installed* script implements | A matcher exists but names a similarly-titled script from a different project; or a rule is implemented and no matcher ever reaches it |
| **Effective** | What does it decide when fed a real input? | Pipe crafted input at the installed artifact and read the emitted decision | Rules exit on first match, so a later rule may be structurally unreachable. A helper the script dot-sources is absent, so it exits 0 and enforces nothing |

Three consequences follow directly, and they are the three most expensive mistakes available here.

**Merging a hook does not install one.** Code can land arbitrarily far ahead of the call that installs
it -- sometimes deliberately, since a control may ship inert on purpose. Track *inert-by-design*
separately from *inert-by-accident*, re-run the installer as a distinct announced step, and never count
merged code as coverage. On the repo this tooling was developed in, a coordination hook merged and sat
unwired for hours while the settings file looked entirely correct. A similarly-named entry from
another project had occupied the slot it wanted.

**Establish behavior by driving input into the installed artifact, not by reading source.** The
installed copy, the settings matcher and the source can all disagree with one another, and only one of
them decides anything.

**A control that cannot distinguish "ran and resolved" from "ran and found nothing" is not installed,
however it looks.** The hook that established this ran for weeks while printing a status message, and
outlasted every other silent defect found the same day precisely because it printed something. The
account, and the rule that falls out of it, are at
[put at least one signal outside the component being audited](TIPS-AND-TRICKS.md#put-at-least-one-signal-outside-the-component-being-audited).

---

## The drift taxonomy: D1-D4

"Drift" in this system is not one thing. Separating it into four classes is what makes an audit
tractable, because the four have different instruments and different fixes -- and because three of them
are the reason the first one goes unnoticed.

| Class | What drifts | Symptom | Instrument |
|---|---|---|---|
| **D1 -- Session drift** | Where work happens: a session builds in the shared checkout instead of an isolated one | Two sessions overwrite each other; a tree is swapped out from under a live session | Target-path gating at tool time; a `SessionStart` backstop that repairs and *says so* |
| **D2 -- Control drift** | Which artifact enforces: source, installed copy and wired matcher diverge | Nothing. This is the silent class | SHA parity per layer; matcher-vs-implemented-rule diff |
| **D3 -- Coverage drift** | What the rules can see: work moves to routes the rule set does not cover | A control is live, correct, and simply never invoked | Fire it on purpose; enumerate the routes; report every non-match you deliberately allow |
| **D4 -- Belief drift** | What everyone thinks is true: docs, memory, status and premises diverge from behavior | Confident, wrong statements -- including your own from last month | Re-measure the premise; date and attribute every figure; state status exactly |

D1 is the problem you set out to solve. D2, D3 and D4 are the reasons you believe you already solved
it. An audit that only looks for D1 will pass.

### On D3 specifically

Coverage drift has a structural cause worth naming: **enumerated coverage means every hole is silent.**
A rule keyed on a list of tool names, or a list of command verbs, is unmatched at *both* the settings
matcher and the rule body for anything not in the list. The control never runs, and nothing anywhere
says so. Prefer deny-by-default where you can. Where you cannot, ship a rule inventory and a `-Status`
that asserts against an *expectation* rather than printing a bare count, and log every non-match you
deliberately allow.

The same class covers routes rather than names. `scripts/hooks/worktree_gate.ps1` inspects tool
arguments, so a file written by a shell command is not seen at all, and **any agent-authored script
defeats a command-string gate** -- a script invocation carries no `git` token.

That is not an adversarial scenario: a sanctioned repair script is exactly that shape. Treat
string-scanning gates as guardrails against accidents, never as boundaries, and say so in the file.

The hooks that parse commands share one command-splitting helper (`scripts/hooks/_command.ps1`) and
one git-target resolver (`scripts/hooks/_gittarget.ps1`).

The reason is itself an audit finding: two hooks that each split commands their own way will disagree
about what a command *is*, and the one that drifts is the one nobody is testing. Keep exactly one
copy of a safety check.

### On D3's opposite failure

**False positives train sessions to route around the only control you have.** On the repo this tooling
was developed in, a verb-scanning rule denied a read-only status command because a blocklisted word
appeared in a prose line of a multi-line command. It also denied a commit whose *message* contained
one.

Every such denial erodes compliance with the deny text, which on the shell path is the only control
there is.

Scan per line, fold continuations, blank quoted spans, recurse into interpreter arguments, and ship
ALLOW-asserting tests for the multi-line, echoed and message-containing cases. A gate that cries
wolf gets routed around, and then you have nothing.

---

## Six design rules the audit produced

### 1. Gate on the write's target path, never the session's cwd

The obvious design for "don't build in the shared checkout" is to deny writes from sessions whose cwd
is that checkout. It is wrong. Measured on the repo this tooling was developed in, over 30 days, **29%
of write calls came from a session sitting in the shared checkout and landing inside a separate
worktree by absolute path**. That is already correct behavior, and a cwd-keyed gate would have denied
every one of them.

Key write-gating on the destination. A session may then stay where it is and simply write into its
worktree: no `cd`, no relocation, no restart. The price is that writes into *another* session's
worktree are allowed. Accept that explicitly, and know the deny text actively teaches it.

There is a second, unobvious payoff. A target-path rule already contains a fan-out from a bad working
directory. A subagent inherits its parent's cwd, but its writes are judged by where they land, so
they are denied at the destination regardless of where the parent was standing.

### 2. The gate's own enforcement surface must be governed

The installed script and its allowlist live *outside* every governed checkout -- which is deliberate, so
that a checkout or a branch switch cannot make the gate vanish. The consequence nobody sees coming is
that a path-keyed rule therefore returns "not governed" for the gate's own files, and allows any session
to edit them. Every session the gate governs could rewrite the gate.

`scripts/hooks/worktree_gate.ps1` closes this with a dedicated rule (1a) covering its own script and its
own allowlist. Note what that rule is and is not: it stops a *session* from disarming the control,
while leaving a human at a plain terminal completely free to uninstall it. That asymmetry is the whole
design, and it is why the kill switch is documented in plain sight in the script's own `.NOTES` rather
than hidden. Obscurity was tried and is not a control -- the file is one directory listing away. Rule 1a
is the control.

Generalize it: **any control with a mutable enforcement surface must govern that surface, and the
governing rule must be evaluated separately from the rule it protects.**

### 3. An unbacked backstop is worse than an admitted gap

A gate that cannot see the shell route needs a commit-time backstop, and one of these files once
pointed at exactly such a backstop in its header. The backstop was a real, working, well-maintained
dispatcher -- of checks none of which implemented the predicate being relied on. The only actual control
on that path was the deny text asking you not to route around it: persuasion, in a system whose entire
premise is that persuasion does not work.

Verify that a claimed backstop implements the predicate you are relying on. If it does not, delete or
caveat the sentence. **An admitted gap is safer than a false one, because the next reader stops
looking.**

### 4. Evaluate prohibitions as a set, never one at a time

Two rules in this repository each look reasonable in isolation: deny fan-out dispatch *from* the shared
checkout, and deny relocating a live session *into* a worktree. With both live, a session that opened in
the shared checkout has no in-session path to isolation at all -- it can neither dispatch nor relocate,
and a human must restart it elsewhere. That is a hard stop on the way sessions naturally open.

Two rules, individually defensible, jointly a dead end. This is why `scripts/worktree/install-gate.ps1`
ships the relocation rule as an opt-in `-EnterWorktreeGate` switch that is **off by default**, and says
in the parameter's own comment why. It is a decision to make on purpose, not one that rides along
with an unrelated install.

The corollary is **ship the cure before the prohibition.** If a prohibition removes the only path to
the sanctioned behavior, the prohibition is the defect.

Two smaller rules in the same family:

- **Re-measure a deny's premise before defending it, and record its scope precisely.** One rule here was
  remembered -- in project notes, by everyone -- as far broader than it was, because the case it covers
  happens often enough to *feel* general. Meanwhile part of its stated rationale had quietly expired as
  the surrounding tooling gained a capability the rationale assumed absent. A rule whose premise has
  expired is D4 drift wearing a control's uniform.
- **An install option that removes a control must leave a queryable trace.** A flag that drops a rule
  silently recreates the exact observability gap the whole system exists to close. Here, the flag that
  skips a rule leaves it *implemented but unmatched*, which the audit then reports as a dead rule, and
  the installer prints a warning. If you turned it off, you should have to keep seeing that you turned
  it off.

### 5. A control with no receipts cannot be ranked, fixed, or defended

One gate wrote its decision to stdout and exited 0 -- no log, no counter, no audit file -- for its entire
life. Nothing could answer "how many drift events were prevented last month", "is the false-positive
rate one a day or one in a thousand", or "did the fix change anything". Every severity claim about it,
including which failure was most frequent, rested on intuition. **With no receipts, every severity
ranking is unfalsifiable.**

Log every deny: timestamp, rule, tool, cwd, target, decision -- never the raw command. It is smaller
than any other fix on the list and it is the prerequisite for ranking the rest. A receipt stamped with
a subagent's process id is also what lets a parent session see what its fan-out was denied.

### 6. Prefer a control that acts and receipts itself; where you cannot, say so

One control in this repository is an *instruction to the model* rather than an action: it resolves peers
and asks the model to deliver a message. Whether the message was delivered is therefore recorded by the
model, not by the hook. It is the one control whose audit trail is written by the thing it is supposed
to be evidence about. That is named as a permanent blind spot on every audit run rather than papered
over. Where a control cannot receipt itself, say so explicitly, so nobody mistakes the trail for
independent evidence.

---

## Evidence discipline

This is the half of the method that is easiest to skip and most expensive to skip.

### Green tests that bind the repo copy prove nothing about the installed one

On the repo this tooling was developed in, one gate had **85 passing tests**. Every single one bound
the repository's copy of the script. Nothing anywhere read the installed copy or a live settings file.
Enforcement was running from an installed copy that was days behind source, and the entire suite was
green about it.

The fix is a test that skips unless the installed artifact exists. It then asserts SHA-256 equality
with the source, *and* that the live hook matchers superset the handled-tool list -- **and prints what
it scanned, so a skip never reads as a pass.** This repository carries that as a tripwire
(`Get-HandledTools` in `bin/ccx-doctor.ps1` reads the rule set out of the *installed* copy and diffs it
against every config root's matchers), reporting three distinct states rather than one:

| State | Meaning |
|---|---|
| `UNWIRED` | The installed script implements the rule and no matcher ever invokes it -- a dead rule |
| `STRAY` | A matcher invokes the gate for a tool the installed script ignores |
| off by choice | An opt-in rule that is off because somebody chose that, reported separately so it never hides in the same bucket as an accident |

### Fire every control on purpose, and pair every attack with a negative control

Reading a control does not establish its behavior; feeding it does. `bin/ccx-doctor.ps1` pipes crafted
`PreToolUse` payloads at the *installed* gate, attempts a blanket stage, attempts a commit claiming an
unheld work item, and attempts a push to a protected ref. It requires a refusal in each case. Everything
runs against throwaway fixtures in the temp directory, with their own repositories, their own allowlist
and their own state root, deleted on the way out.

Each attack is paired with a **negative control**: an ordinary action the same control must *allow*. A
script that refuses everything is not a working guard either, and more importantly a probe with no
positive control cannot tell "the control refused correctly" from "the control refused because it could
not load". That distinction is not academic. There is a class of installer defect where the entry
point is copied but the helpers it dot-sources or imports are not, and it produces a control that
refuses *everything*, for a reason unrelated to what it checks. Without a negative control that
failure reads as perfect enforcement.

Attack results are downgraded to `??`, never `OK`, when the artifact under test is the source rather
than an installed copy. Proving the rules work says nothing about whether anything is enforcing.

### The probe is part of the system under test

The first version of this repository's attack harness passed its payload under a parameter name that
**bound to nothing, silently, with no error**. Four attacks fired payloads carrying a tool name and a
working directory and no tool input at all. Every path-keyed rule correctly allowed them, and the audit
reported the gate broken. The gate was fine. The probe was broken.

`New-PreToolUsePayload` now throws on an empty tool input, and the attack block catches an abort and
records `??` for the attacks that never fired. A canceled sequence can never read as a silent
pass. **A probe that cannot build its own input must refuse to report a verdict rather than report the
target's answer to an empty question.**

The general form: if your must-fail case and your under-test case produce the same output, the result is
**untested**, not negative. Say so, and re-run against a known-good instance before trusting either
answer.

### Prove each fix by mutation

Passing tests do not show that the tests *could* fail on the defect. For each shipped gate fix in this
corpus, five mutations were applied to the shipped artifact one at a time and each was required to go
red. That exercise is also what surfaced three regressions an adversarial review found in the first
attempt at one of the fixes -- regressions that were then pinned with their own test file.

Mutate the shipped artifact deliberately, confirm each mutation goes red, and pin every regression
adversarial review finds. Build the control, then attack it.

### Test the real pair, not stubs

One fix in this corpus made an ordinary edit to an untouched file fail a gate -- i.e. most edits -- with a
green test suite. The test stubs emitted a JSON shape the real helper never produced, so the tests
validated an interface that did not exist. Run the real components together at least once before
shipping a contract change between them. Stub-only coverage validates your assumption, not the seam.

### Label figures you cited but did not re-measure

The 29% figure quoted above is the sole quantitative justification for the target-path design of the
whole gate. Nothing in this repository can recompute it, and nobody has asked whether it still holds.

Cited numbers acquire the authority of measured ones as they get restated. Keep an explicit
*cited, not re-measured -- treat with care* section; strike claims through when superseded rather than
deleting them; and if a number is load-bearing for a design, build the ability to recompute it. In this
document, the figures in that category are: the 29% target-vs-cwd measurement, the 85-test count, and
the per-prompt cost of the always-on coordination hooks. All were measured on the repo this tooling was
developed in, none has been re-measured since, and every one of them is worth re-deriving before it is
used to justify a new decision.

---

## Writing the outcome down

### Record rejected options with the specific blocking fact

The structurally strongest answers to "sessions keep building in the shared checkout" get re-proposed
every single time the gate leaks:

- an OS-level sandbox;
- filesystem ACLs;
- a bare-repository layout;
- a repository-level worktree lock;
- a native path-deny rule in the client's own permission system.

A concrete, statable fact blocks each one: platform availability, what the lock primitive actually
prevents, or the fact that a nested worktree layout lives *inside* the checkout a path-deny would
have to cover.
Another is the loss of the deny *text*, which on this design carries most of the rule's value because
it is the remediation channel.

Write the blocking fact next to each rejected option, not just the rejection. Otherwise the next
session spends the cycle again and reaches the same place. And when a mechanism is genuinely unproven,
**timebox a spike that fails on purpose first** rather than building on it.

The corollary is that deny text is a control surface and must be tested like one. In this corpus, a
deny message refused a write to the shared checkout and then listed that same checkout *first* among
the worktrees you could reuse instead, displacing a real one off a display cap. The cause: a filter
compared a string against an object and was therefore always true. No test asserted on message content.
Assert that the forbidden path never appears in the suggested-alternatives list.

### State status exactly

The single most damaging line in an audit report is a bare **Done**.

The next session acts on the status. If a change is mostly done, the status must spell out what is
*not* done, per item, in the same sentence: **"Mostly done -- X, Y; NOT done: Z."** An overstated
status is worse than no status. No status prompts a check, and a false status ends one.

The same discipline applies to the audit's own verdict. `bin/ccx-doctor.ps1` exits `0` only when every
required control is installed *and* wired *and* refused every attack, `1` on any red, and **`2` when at
least one check could not be determined**. That last one is because a control that was not tested is
not a control that passed. `-SkipAttacks` therefore forces exit 2 by construction. The four-character
status tags are `OK`, `RED`, `OFF`, `??` and `--`, and `??` is not a rounding error toward `OK`.

### Print what you scanned, and name your blind spots, on every run

Every run prints a `WHAT WAS SCANNED` block: config roots found, session records read, records that
could not be placed, worktrees enumerated, which interpreter. It also prints a blind-spot block,
**whether or not anything failed**. An operator who believes they are fenced when they are not is
worse off than one who knows they are not.

---

## What this method cannot tell you

Stated plainly, because a limits section that reads like marketing is itself a D4 defect.

| Limit | Consequence |
|---|---|
| **PowerShell 7, Windows-first** | Nearly every shipped script is PowerShell. Off Windows, process-table self-marking and path case-folding degrade, and the audit says so on every run. The Python part of the set -- the git-hook checkers, the leak gate and the one substrate module they share -- is stdlib-only and portable |
| **The session-management MCP is Claude Code Desktop only** | It is **absent on a plain CLI install**. Where it is absent, the announce hook still fires, still resolves peers, and then asks the model to call tools it does not have. PowerShell cannot see whether that MCP exists, so delivery is unprovable from here -- it is printed as a permanent blind spot |
| **The client's session record schema is a vendor contract** | Every liveness answer rests on a per-session JSON record written by the client. That schema can change under you without notice, and when it does the fence degrades quietly |
| **The client-side session listing cannot see every session kind** | Editor-hosted sessions in particular. A liveness signal built on it is incomplete by construction -- which is why liveness in this repository may only **veto** a destructive action, never **permit** one |
| **No interpreter, no gate** | With no Python on PATH the git-hook shims fail open: they print to stderr and exit 0. The commit-time controls are off, and only the audit says so |
| **Documented bypasses exist and are not closed here** | A commit made with verification skipped bypasses both git hooks, and nothing local records that it happened. This is a guardrail against the accidental mistake, not a security boundary. Anything that claims otherwise is the unbacked-backstop defect in design rule 3 above |
| **Scope** | The audit examines one clone and the config roots it lists. It is not a machine-wide statement |

Two controls in this repository are, by their nature, only partly provable:

- **The collision gate's deny path** needs a live peer worktree holding an uncommitted change to the
  same file. The audit proves only that it refuses to go silent when it cannot resolve -- the fail-open
  path emits a distinguishable notice rather than the empty output that is byte-identical to
  all-clear. The deny itself is printed as a blind spot every run.
- **The session banner** makes no decision, so there is nothing to attack. It is reported by receipt
  and by live re-resolution only.

---

## The audit loop, condensed

1. **Enumerate every control by receipt.** Hash each installed copy against source. Read live matchers
   from every config root. Diff wired matchers against the rules the *installed* script implements.
2. **Fire each control on purpose and require it to deny.** Against the installed copy, against
   throwaway fixtures, each attack paired with a negative control the same control must allow.
3. **Print what you scanned, always.** A skip must never read as a pass; report it `??` and let the
   exit code carry it.
4. **Name your blind spots on every run**, whether or not anything failed.
5. **Prove each fix by mutation** before calling it a fix.
6. **Write the outcome exactly** -- including what is not done, which options were rejected and why, and
   which figures were cited rather than re-measured.

The one external reference this document depends on is public:
[`anthropics/claude-code#76590`](https://github.com/anthropics/claude-code/issues/76590), the
half-failed automatic worktree behavior that the `SessionStart` backstop
(`scripts/worktree/worktree-selfheal.ps1`) repairs -- and announces when it does, because a silent
repair is indistinguishable from nothing having been wrong.

---

## A note on what is not in this document

The source material for this case study was a probe-verified bypass register: ranked, dated, and
specific down to verified command strings and the exact surfaces that failed to cover them. **It is
withheld deliberately and permanently.** Publishing an attacker index alongside the tooling it attacks
converts a guardrail repository into a bypass manual, and the audience for the two is not the same
audience.

What generalizes is the method, and the method is above in full. If you want the specifics for your own
estate, they are one command away -- and unlike a published register, yours will be current.
