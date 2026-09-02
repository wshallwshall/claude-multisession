# Brief a worker session

A brief is the opening prompt a coordinating session writes when it spawns a worker. This page is
the template for one, and the standing rule that stops a worker guessing when the brief runs out.

[Run a KORUS build](KORUS-BUILD.md) owns the four-session shape and the prompt for each role. This
page owns what a single worker's prompt has to contain.

---

## What a worker does today when its brief runs out

It has two moves. It guesses, or it waits.

**Guessing is the worse one.** The guess reaches a pull request in the shape of a decision, and a
reviewer reads it as one. Nothing beside it marks the answer as a guess.

Waiting is honest and it is not free. A waiting worker still spends metered tokens.

The channel for asking already works. The rule pointing a worker at it is what was missing.

---

## The rule a brief must carry

```text
If the brief does not answer something you must know to proceed:
do not guess and do not wait. Write the question to the console,
comment it on the pull request, and stop.
```

The console is the session that wrote the brief. In a KORUS build that is the dispatcher.

The template below ends with this block. That copy is the one you paste, and it goes in unchanged.

### Why a prohibition rather than "ask if you are unsure"

**Obligations decay and prohibitions hold.** Measured on the fleet this rule came from, prohibitions
failed between 0.07 and 0.6 percent of the time. Obligations decayed between 22 and 97 percent.

"Ask if you are unsure" is an obligation. It asks a worker to notice a feeling first, and noticing
is the part that goes under load.

A prohibition names an act instead. "Am I about to guess" is a question about what the worker is
already doing, so the check costs it nothing.

Both channels have to exist before you paste the rule. A prohibition that removes the only route to
the behavior it wants is itself the defect
([Drift audit](CASE-STUDY-drift-audit.md#4-evaluate-prohibitions-as-a-set-never-one-at-a-time)).

---

## Stopping is free, waiting is not

A worker that ends its turn costs nothing at all.

| What the worker does | Metered cost |
|---|---|
| Ends its turn and stops | zero tokens |
| Waits on a three-minute heartbeat | 2,108 tokens per waiting minute |
| Waits in a ten-minute sleep loop | 22,275 tokens per waiting minute |

So the rule says stop, and never says wait. [Token accounting](TOKEN-ACCOUNTING.md) is what those
figures are worth against a weekly window.

## The answer arrives as a new spawn

Nobody wakes a stopped session and replies to it. The coordinator spawns a fresh worker with the
answer written into its brief.

**The branch and the worktree outlive the session that made them**, so the new worker continues
rather than restarts ([Worktrees](WORKTREES.md)).

That is what makes stopping safe to ask for. The only thing lost is the stopped session's context.

## The question goes to two places on purpose

| Where | What only it does |
|---|---|
| Mail to the coordinating session | Crosses the account boundary. Nothing else here reaches a session under a second login |
| A comment on the pull request | Sits beside the work, outlives the session, and a later reviewer reads it |

Mail is consumed on delivery and then gone. The comment stays. Neither covers the other, which is
why the rule names both.

### The pull request half needs a pull request

A worker in the KORUS shape does not open one; the lander does
([Run a KORUS build](KORUS-BUILD.md)). A worker asking early has nowhere to comment.

**So the brief names both addresses and the worker never picks one.** Give it the mail target, plus
a pull request number or the issue the item came from.

## Sending the question

**No script here implements mail.** [Session mail](SESSION-MAIL.md) is the build guide. You build
the lane once, and every worker after that uses it.

The one line a worker types:

```powershell
mail.ps1 -Send -To <coordinator worktree> -Body "<the question>"
```

Delivery happens at the recipient's next drain, not at send time. The drain consumes at `Stop`, so
the question lands in the coordinator's context at its next turn boundary
([Session mail](SESSION-MAIL.md#step-5-split-show-from-consume-across-two-hook-events)).

**Measured 2026-08-31** between two sessions on different Claude accounts: five messages each way,
all delivered. One box recorded 396 messages consumed.

Until that lane exists, only the comment half works, and it waits on somebody looking.

---

## What a brief must carry

Five slots. Leave one out and the worker hits a question the rule then makes it stop on.

| Slot | What goes in it |
|---|---|
| Scope | The branch, the worktree, and the one thing this worker owns |
| The items | The work, in order, sized for a single session |
| Done | An end state somebody else can check |
| Out of scope | What it must not touch, named rather than implied |
| The rule | The block above, plus the two addresses to ask at |

### A brief only has to hold for one turn

**That is the standard, and it is a much lower bar than answering everything.** A brief is good
enough when the worker can finish one turn without guessing.

When it stops holding, the worker asks and stops, and the next spawn carries the answer. An
incomplete brief costs one spawn.

A guessed answer costs a pull request nobody can tell from a decided one. Write the brief you have
and let the rule catch the rest.

## The template

```text
You are a build session on branch <BRANCH>, in worktree <WORKTREE>.

SCOPE. <the one thing you own>
OUT OF SCOPE. <what you must not touch>

ITEMS, in order:
  1. <item>
  2. <item>

DONE. <the end state somebody else can check>

Commit at logical stops, one coherent layer each. <YOUR PUSH AND PULL REQUEST RULE>

ASK AT. mail.ps1 -Send -To <coordinator worktree>, and <pull request number, or the issue>.

If the brief does not answer something you must know to proceed:
do not guess and do not wait. Write the question to the console,
comment it on the pull request, and stop.
```

Keep that last block identical in every brief. A reworded prohibition is a different rule, and none
of the measurement above stands behind it.

---

## Related

| For | Read |
|---|---|
| The four-session shape, and the prompt for each role | [Run a KORUS build](KORUS-BUILD.md) |
| Building the mail lane this rule sends through | [Session mail](SESSION-MAIL.md) |
| Which channel reaches which peer, and when | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| The working agreement every session reads | [CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template) |
| Judging a prohibition against the paths it closes | [Drift audit](CASE-STUDY-drift-audit.md) |
