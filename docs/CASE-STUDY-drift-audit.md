# Case study: Auditing a multi-session estate as one system

## TLDR/BLUF

**What this is.** The method used to audit the controls that ship with KORUS, on **2026-08-04**: how
they were checked as one system, what that proved, and what it could not.

**Why you should care.** A control here can be merged, green, and enforcing nothing, and it looks
exactly like one that works. Six design rules below each came from such a control. Not for you if
you want a status list: publishing what is unenforced is publishing a bypass map.

**How to use it.** Read it as a checklist for auditing your own controls. For the state of *your*
estate today, run the audit below rather than trusting any document.

---

**The goal.** Know whether the controls on *your* machine are enforcing right now. The audit ran on
one host on **2026-08-04**, so this page carries no status table and no inventory of what is
enforced anywhere. Such a list goes stale at once, and published it is a bypass map.

**What to do.** Run the audit from the repository root:

```powershell
pwsh -NoProfile -File bin/ccx-doctor.ps1
```

**What happens next.** It prints what it scanned, what it could not determine, and its own blind
spots. A check it could not determine is reported `??`, never `OK`. Everything below is the
reasoning that command encodes.

---

## Why the estate is the unit of audit, not the script

Each control in this repository is small and readable. Read `scripts/hooks/worktree_gate.ps1` and you
can state what it denies. Read `scripts/hooks/collision_gate.ps1` and you can state its posture. That
reading is worth almost nothing, because none of these files is what runs.

What runs is a *copy*, and four things have to line up before it decides anything:

- an installer places that copy outside every working tree;
- a matcher in a client config root invokes it;
- it resolves its helpers from beside itself;
- the host has an interpreter to run it.

Any one of those joins can be wrong while every file is individually correct. That is what makes
this class of system dangerous:

> **Every failure mode in this system is byte-identical to success.**

A hook can be missing, installed but not wired, wired to a dead script, or loaded but failing open.
All produce what a healthy quiet hook produces: exit 0, no output, work proceeds. No error, no
warning, no degraded mode. A fresh clone with one installer run, or none, sits there and reads as
green.

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

Three consequences follow, and they are the three most expensive mistakes available here.

**Merging a hook does not install one.** Track *inert-by-design* separately from
*inert-by-accident*, and re-run the installer as its own announced step. A coordination hook on the
repo this tooling was developed in sat unwired for hours; another project's similarly-named entry
held the slot.

**Establish behavior by driving input into the installed artifact, not by reading source.** The
installed copy, the settings matcher and the source can all disagree with one another, and only one of
them decides anything.

**A control that cannot distinguish "ran and resolved" from "ran and found nothing" is not
installed, however it looks.** The hook that proved this printed a status message for weeks. It
outlasted every other silent defect found the same day, because it printed something.

Full account:
[put a signal outside the component](TIPS-AND-TRICKS.md#put-at-least-one-signal-outside-the-component-being-audited).

---

## The drift taxonomy: D1-D4

"Drift" here is not one thing. Four classes make an audit tractable, because each has its own
instrument and its own fix. Three of them are also the reason the first one goes unnoticed.

| Class | What drifts | Symptom | Instrument |
|---|---|---|---|
| **D1 -- Session drift** | Where work happens: a session builds in the shared checkout instead of an isolated one | Two sessions overwrite each other; a tree is swapped out from under a live session | Target-path gating at tool time; a `SessionStart` backstop that repairs and *says so* |
| **D2 -- Control drift** | Which artifact enforces: source, installed copy and wired matcher diverge | Nothing. This is the silent class | SHA parity per layer; matcher-vs-implemented-rule diff |
| **D3 -- Coverage drift** | What the rules can see: work moves to routes the rule set does not cover | A control is live, correct, and simply never invoked | Fire it on purpose; enumerate the routes; report every non-match you deliberately allow |
| **D4 -- Belief drift** | What everyone thinks is true: docs, memory, status and premises diverge from behavior | Confident, wrong statements -- including your own from last month | Re-measure the premise; date and attribute every figure; state status exactly |

D1 is the problem you set out to solve. D2, D3 and D4 are the reasons you believe you already solved
it. An audit that only looks for D1 will pass.

### On D3 specifically

**Enumerated coverage means every hole is silent.** A rule keyed on a list of tool names or verbs
is unmatched at *both* the matcher and the rule body for anything off it. Prefer deny-by-default.
Where you cannot, ship a rule inventory and a `-Status` asserting an *expectation*, not a bare
count.

The same class covers routes rather than names. `scripts/hooks/worktree_gate.ps1` inspects tool
arguments, so a file written by a shell command is not seen at all. **Any agent-authored script
defeats a command-string gate**: a script invocation carries no `git` token.

That is not an adversarial scenario: a sanctioned repair script is exactly that shape. Treat
string-scanning gates as guardrails against accidents, never as boundaries, and say so in the file.

The hooks that parse commands share one command-splitting helper (`scripts/hooks/_command.ps1`) and
one git-target resolver (`scripts/hooks/_gittarget.ps1`).

The reason is itself an audit finding. Two hooks that each split commands their own way will
disagree about what a command *is*, and the one that drifts is the one nobody is testing. **Keep
exactly one copy of a safety check.**

### On D3's opposite failure

**False positives train sessions to route around the only control you have.** On the repo this
tooling was developed in, a verb-scanning rule denied a read-only status command over a blocklisted
word in a prose line of a multi-line command. It also denied a commit whose *message* contained one.

Every such denial erodes compliance with the deny text, which on the shell path is the only control
there is.

The fix is mechanical:

- scan per line, and fold continuations;
- blank out quoted spans;
- recurse into interpreter arguments;
- ship ALLOW-asserting tests for the multi-line, echoed and message-containing cases.

A gate that cries wolf gets routed around, and then you have nothing.

---

## Six design rules the audit produced

### 1. Gate on the write's target path, never the session's cwd

The obvious design -- deny writes from sessions whose cwd is the shared checkout -- is wrong.
Measured over 30 days, **29% of the write calls made by sessions sitting in the shared checkout
landed inside a separate worktree by absolute path**. Correct behavior, and a cwd-keyed gate
denies it.

Key write-gating on the destination. A session may then stay where it is and simply write into its
worktree: no `cd`, no relocation, no restart. The price is that writes into *another* session's
worktree are allowed. Accept that explicitly, and know the deny text actively teaches it.

There is a second payoff. A target-path rule already contains a fan-out from a bad working
directory. A subagent inherits its parent's cwd, but its writes are judged by where they land, so
they are denied at the destination regardless of where the parent was standing.

### 2. The gate's own enforcement surface must be governed

The installed script and its allowlist live *outside* every governed checkout, so no checkout or
branch switch can make the gate vanish. A path-keyed rule returns "not governed" for the gate's own
files and lets any session edit them: every session the gate governs could rewrite the gate.

`scripts/hooks/worktree_gate.ps1` closes this with a dedicated rule (1a) covering its own script
and allowlist. It stops a *session* disarming the control. A human at a terminal is still free to
uninstall it, and the kill switch is documented in the script's own `.NOTES`: obscurity is not a
control.

Generalize it: **any control with a mutable enforcement surface must govern that surface, and the
governing rule must be evaluated separately from the rule it protects.**

### 3. An unbacked backstop is worse than an admitted gap

A gate blind to the shell route needs a commit-time backstop, and one of these files claimed one in
its header. The backstop was a real dispatcher of checks, none implementing the predicate relied on.
The only control there was the deny text: persuasion, in a system premised on its failure.

Verify that a claimed backstop implements the predicate you are relying on. If it does not, delete or
caveat the sentence. **An admitted gap is safer than a false one, because the next reader stops
looking.**

### 4. Evaluate prohibitions as a set, never one at a time

Two rules here each look reasonable alone: deny fan-out dispatch *from* the shared checkout, and
deny relocating a live session *into* a worktree. With both live, a session opened in the shared
checkout has no in-session path to isolation -- only a human restarting it elsewhere.

Two rules, individually defensible, jointly a dead end. `scripts/worktree/install-gate.ps1` ships
the relocation rule as opt-in `-EnterWorktreeGate`, **off by default**. The parameter's own comment
says why: this is a decision to make on purpose, not one riding along with an unrelated install.

The corollary is **ship the cure before the prohibition.** If a prohibition removes the only path to
the sanctioned behavior, the prohibition is the defect.

Two smaller rules in the same family:

- **Re-measure a deny's premise before defending it, and record its scope precisely.** One rule here
  was remembered as broader than it was. Part of its rationale had expired too: the tooling gained a
  capability the rationale assumed absent. An expired premise is D4 drift in a control's uniform.
- **An install option that removes a control must leave a queryable trace.** A flag that drops a
  rule silently recreates the observability gap the system exists to close. Here the flag leaves
  the rule *implemented but unmatched*, the audit reports it as dead, and the installer prints a
  warning.

### 5. A control with no receipts cannot be ranked, fixed, or defended

One gate wrote its decision to stdout and exited 0 -- no log, no counter, no audit file -- for its
entire life. Nothing could answer "how many drift events were prevented last month" or "did the fix
change anything". **With no receipts, every severity ranking is unfalsifiable.**

Log every deny: timestamp, rule, tool, cwd, target, decision -- never the raw command. It is smaller
than any other fix on the list and it is the prerequisite for ranking the rest. A receipt stamped with
a subagent's process id is also what lets a parent session see what its fan-out was denied.

### 6. Prefer a control that acts and receipts itself; where you cannot, say so

One control here is an *instruction to the model*, not an action: it resolves peers and asks the
model to send a message. Delivery is recorded by the model, not the hook: the one control whose
audit trail is written by what it is evidence about. Named a permanent blind spot on every audit
run.

---

## Evidence discipline

This is the half of the method that is easiest to skip and most expensive to skip.

### Green tests that bind the repo copy prove nothing about the installed one

On the repo this tooling was developed in, one gate had **85 passing tests**. Every one bound the
repository's copy of the script; nothing read the installed copy or a live settings file.
Enforcement was running from an installed copy days behind source, and the whole suite was green
about it.

The fix skips unless the installed artifact exists. `Get-HandledTools` in `bin/ccx-doctor.ps1`
asserts SHA-256 equality with the source, then diffs the *installed* rule set against every config
root's matchers. **It prints what it scanned, so a skip never reads as a pass.** Three states:

| State | Meaning |
|---|---|
| `UNWIRED` | The installed script implements the rule and no matcher ever invokes it -- a dead rule |
| `STRAY` | A matcher invokes the gate for a tool the installed script ignores |
| off by choice | An opt-in rule that is off because somebody chose that, reported separately so it never hides in the same bucket as an accident |

### Fire every control on purpose, and pair every attack with a negative control

`bin/ccx-doctor.ps1` pipes crafted `PreToolUse` payloads at the *installed* gate and requires a
refusal each time. It attempts three things:

- a blanket stage;
- a commit claiming an unheld work item;
- a push to a protected ref.

Fixtures are throwaway: own repositories, allowlist, state root, deleted on the way out.

Each attack is paired with a **negative control**: an ordinary action the same control must *allow*.
Without one, a probe cannot tell "refused correctly" from "refused because it could not load". An
entry point copied without its helpers refuses *everything*, which reads as perfect enforcement.

Attack results are downgraded to `??`, never `OK`, when the artifact under test is the source rather
than an installed copy. Proving the rules work says nothing about whether anything is enforcing.

### The probe is part of the system under test

This repository's first attack harness passed its payload under a parameter name that **bound to
nothing, silently, with no error**. Four attacks fired payloads with a tool name, a cwd and no tool
input. Every path-keyed rule allowed them, and the audit blamed the gate. The probe was broken.

`New-PreToolUsePayload` now throws on an empty tool input, and the attack block catches the abort
and records `??` for the attacks that never fired. **A probe that cannot build its own input must
refuse to report a verdict rather than report the target's answer to an empty question.**

The general form: if your must-fail case and your under-test case produce the same output, the result is
**untested**, not negative. Say so, and re-run against a known-good instance before trusting either
answer.

### Prove each fix by mutation

Passing tests do not show that the tests *could* fail on the defect. For each shipped gate fix here,
five mutations were applied to the shipped artifact one at a time and each required to go red. That
exercise surfaced three regressions from an adversarial review, pinned in their own test file.

Mutate the shipped artifact deliberately, confirm each mutation goes red, and pin every regression
adversarial review finds. Build the control, then attack it.

### Test the real pair, not stubs

One fix here made an ordinary edit to an untouched file fail a gate -- most edits -- with a green
suite. The stubs emitted a JSON shape the real helper never produced, so the tests validated an
interface that did not exist. Run the real components together once before shipping a contract
change.

### Label figures you cited but did not re-measure

The 29% figure quoted above is the sole quantitative justification for the target-path design of the
whole gate. Nothing in this repository can recompute it, and nobody has asked whether it still holds.

Keep a *cited, not re-measured -- treat with care* section, strike superseded claims rather than
deleting them, and build the ability to recompute a load-bearing number.

Here: the 29% target-vs-cwd measurement, the 85-test count, the per-prompt cost of the always-on
coordination hooks. All were measured on the repo this tooling was developed in, none re-measured
since; re-derive before reusing one.

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

A concrete fact blocks each: platform availability, what the lock primitive actually prevents, or a
nested worktree layout living *inside* the checkout a path-deny would have to cover. Another is the
loss of the deny *text*, which carries most of the rule's value as the remediation channel.

Write the blocking fact next to each rejected option, not just the rejection. Otherwise the next
session spends the cycle again and reaches the same place. And when a mechanism is genuinely unproven,
**timebox a spike that fails on purpose first** rather than building on it.

Deny text is a control surface. A deny message listed the shared checkout *first* among the
worktrees to reuse instead, displacing a real one off a display cap. The filter compared a string
against an object and was always true. Assert that the forbidden path never appears in the suggested
list.

### State status exactly

The single most damaging line in an audit report is a bare **Done**.

The next session acts on the status. If a change is mostly done, the status must spell out what is
*not* done, per item, in the same sentence. Write it as **Mostly done -- X, Y; NOT done: Z.** An
overstated status is worse than no status: no status prompts a check, and a false status ends one.

`bin/ccx-doctor.ps1` carries that rule in its exit code:

- `0` only when every required control is installed *and* wired *and* refused every attack;
- `1` on any red;
- **`2` when a check could not be determined.** `-SkipAttacks` forces exit 2.

Tags: `OK`, `RED`, `OFF`, `??`, `--`. `??` is not a rounding error toward `OK`.

### Print what you scanned, and name your blind spots, on every run

Every run prints a `WHAT WAS SCANNED` block: config roots found, session records read, records that
could not be placed, worktrees enumerated, which interpreter. It also prints a blind-spot block,
**whether or not anything failed**. Believing you are fenced when you are not is worse than knowing.

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

- **The collision gate's deny path** needs a live peer worktree with an uncommitted change to the
  same file. The audit proves only that it does not go silent when it cannot resolve: the fail-open
  path emits a notice rather than output byte-identical to all-clear. The deny is a blind spot every
  run.
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

The one external reference is public:
[`anthropics/claude-code#76590`](https://github.com/anthropics/claude-code/issues/76590), the
half-failed worktree behavior the `SessionStart` hook `scripts/worktree/worktree-selfheal.ps1`
repairs -- and announces, since a silent repair reads as nothing wrong.

---

## A note on what is not in this document

The source material was a probe-verified bypass register: ranked, dated, specific down to verified
command strings and the surfaces that failed to cover them. **Withheld permanently.** Publishing an
attacker index alongside the tooling it attacks turns a guardrail repository into a bypass manual.

What generalizes is the method, and the method is above in full. If you want the specifics for your own
estate, they are one command away -- and unlike a published register, yours will be current.
