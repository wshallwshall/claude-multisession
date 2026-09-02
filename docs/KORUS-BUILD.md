# Run a KORUS build

## TLDR/BLUF

**What this is.** The build shape, with the opening prompt for each session and what to
expect back. The shape comes from [The KORUS framework](KORUS.md), one operator's account of months
of Claude Code work; this page is the operating procedure for it.

**Why you should care.** Sessions with distinct jobs beat the same sessions all doing the same job,
because the failures that cost you work come from two sessions deciding the same thing. Not for you
until [Quickstart](QUICKSTART.md) is done: this page assumes the gates are installed and proven.

**How to use it.** Open the sessions in the order below. Each section states the goal, the prompt to
paste, and what the session should do first.

---

## The shape

A seat per job. **Nothing here implements the roles**: there is no seat script, no
role flag, and no routing. The roles are a convention you establish in each session's opening prompt
and in your `CLAUDE.md`.

<figure role="group">
<svg viewBox="0 0 900 380" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="The KORUS build shape. The record feeds a console that writes one brief and spawns a builder, which edits in its own worktree on its own branch behind a dashed collision gate, then pushes its branch and opens a pull request; a reviewer reads the diff and either posts findings back on that pull request or hands it to the lander with a reviewed label, the lander enqueues it and the merge queue merges it into the trunk, and a red check on the pull request goes to a regulator that returns only the pull request's own red to the console.">
  <defs>
    <marker id="korus-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="currentColor" />
    </marker>
  </defs>
  <rect x="15" y="44" width="180" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="105" y="66" font-size="12" text-anchor="middle" fill="currentColor">The record</text>
  <text x="105" y="84" font-size="11" text-anchor="middle" fill="currentColor">backlog and plan</text>
  <line x1="105" y1="100" x2="105" y2="162" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="113" y="136" font-size="10" font-style="italic" fill="currentColor">picks an item</text>
  <rect x="15" y="164" width="180" height="72" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="105" y="194" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Console</text>
  <text x="105" y="212" font-size="11" text-anchor="middle" fill="currentColor">the only seat you talk to</text>
  <line x1="195" y1="200" x2="238" y2="200" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="216" y="156" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">one brief, spawns one</text>
  <rect x="240" y="164" width="190" height="72" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="335" y="186" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Builder</text>
  <text x="335" y="204" font-size="11" text-anchor="middle" fill="currentColor">one brief, then it exits</text>
  <text x="335" y="222" font-size="11" text-anchor="middle" fill="currentColor">own worktree and branch</text>
  <line x1="335" y1="164" x2="335" y2="102" stroke="currentColor" stroke-width="1.5" stroke-dasharray="5 4" marker-end="url(#korus-arrow)" />
  <text x="343" y="136" font-size="10" font-style="italic" fill="currentColor">each edit</text>
  <rect x="240" y="44" width="190" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="3 3" />
  <text x="335" y="66" font-size="12" text-anchor="middle" fill="currentColor">collision gate</text>
  <text x="335" y="84" font-size="11" text-anchor="middle" fill="currentColor">refuses a file a peer holds</text>
  <line x1="430" y1="200" x2="473" y2="200" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="451" y="156" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">pushes and opens</text>
  <rect x="475" y="164" width="180" height="72" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="565" y="194" font-size="12" text-anchor="middle" fill="currentColor">Pull request</text>
  <text x="565" y="212" font-size="11" text-anchor="middle" fill="currentColor">checks run here</text>
  <line x1="525" y1="164" x2="525" y2="102" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="517" y="136" font-size="10" font-style="italic" text-anchor="end" fill="currentColor">the diff</text>
  <rect x="475" y="44" width="180" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="565" y="66" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Reviewer</text>
  <text x="565" y="84" font-size="11" text-anchor="middle" fill="currentColor">labels, or posts findings</text>
  <line x1="605" y1="100" x2="605" y2="162" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="613" y="136" font-size="10" font-style="italic" fill="currentColor">findings on a fail</text>
  <line x1="655" y1="72" x2="698" y2="72" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="676" y="36" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">reviewed label</text>
  <rect x="700" y="44" width="160" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="780" y="66" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Lander</text>
  <text x="780" y="84" font-size="11" text-anchor="middle" fill="currentColor">sets the merge order</text>
  <line x1="780" y1="100" x2="780" y2="162" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="788" y="136" font-size="10" font-style="italic" fill="currentColor">enqueues it</text>
  <rect x="700" y="164" width="160" height="72" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="780" y="205" font-size="12" text-anchor="middle" fill="currentColor">Merge queue</text>
  <line x1="780" y1="236" x2="780" y2="298" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="788" y="272" font-size="10" font-style="italic" fill="currentColor">merges</text>
  <rect x="700" y="300" width="160" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="780" y="332" font-size="12" text-anchor="middle" fill="currentColor">Trunk</text>
  <line x1="565" y1="236" x2="565" y2="298" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="573" y="272" font-size="10" font-style="italic" fill="currentColor">a red check</text>
  <rect x="475" y="300" width="180" height="56" rx="6" fill="none" stroke="currentColor" stroke-width="1.5" />
  <text x="565" y="322" font-size="12" font-weight="bold" text-anchor="middle" fill="currentColor">Regulator</text>
  <text x="565" y="340" font-size="11" text-anchor="middle" fill="currentColor">whose red is it</text>
  <polyline points="475,328 105,328 105,238" fill="none" stroke="currentColor" stroke-width="1.5" marker-end="url(#korus-arrow)" />
  <text x="290" y="320" font-size="10" font-style="italic" text-anchor="middle" fill="currentColor">only the pull request's own red</text>
</svg>
<figcaption>The console writes one brief and spawns a builder for it, and that builder exits when the
brief is done. Each builder gets its own worktree and its own branch. The collision gate still
refuses an edit to a file a peer already holds. A pull request reaches the lander only through the
reviewer, and the merge queue is what merges. A red check goes to the regulator, which sends back
only the pull request's own failure. The dashed box and arrow mark machinery rather than a
seat.</figcaption>
</figure>

| Session | Owns | Must not |
|---|---|---|
| **Console** | The plan, the backlog, and which task gets briefed next | Write application code |
| **Builder** | The change, the commit, the push, and the pull request for one brief | Guess at what the brief left open, or wait for an answer |
| **Reviewer** | Reading the diff on one pull request, and the reviewed label | Merge, or label a pull request it did not read |
| **Regulator** | Deciding whose failure a red is: the pull request's, the trunk's, a flake's, or the queue's | Assume it remembers an earlier red |
| **Lander** | What enters the merge queue and in what order | Merge a pull request with no reviewed label |

**The ASVS monitor session is retired.** It ran as a fifth session whose only job was keeping a
security register current as the build sessions landed work. That seat ended on 2026-09-01.

**Work too large for one context is the case this shape pays off in.** An OWASP ASVS 5.0 assessment
runs to several hundred requirements, more than one session can hold. Split across sessions, the
cost is different unwritten rules: verdicts nobody can reconcile.

[Large assessments](https://secure-development-standards.pages.dev/ASVS-ASSESSMENT.html) is the
method for that case.

## Before you open any session

| Do this | Why | Where |
|---|---|---|
| Install and prove the gates | Roles are advisory; the gates are not | [Quickstart](QUICKSTART.md) |
| Give each session its own worktree | Two sessions in one tree overwrite each other | [Worktrees](WORKTREES.md) |
| Check the config root your console runs on can spawn a session | Spawning is granted per config root, not per machine, and a root without the grant refuses | [Desktop accounts](DESKTOP-ACCOUNTS.md) |
| Wire the steering hook | It only takes effect in sessions started afterwards | [Steering](STEERING.md) |
| Write the working agreement | It only reaches sessions that start later | [CLAUDE.md.template](https://claude-multisession.pages.dev/CLAUDE.md.template) |
| Turn on Ultracode and pick Opus 5 in every session | The build shape assumes workflows and adversarial review | [The KORUS framework](KORUS.md) |
| Be on Max 20x, and expect to need more than one account | This shape spends a weekly window in about two days. Check current plan terms yourself; that page dates from 2026-08 | [The KORUS framework](KORUS.md) |

**Plan on more than one account rather than treating it as a wrinkle.** Set them up before you start:
one desktop instance per account, and each one adds a config root the installers have to reach
([Desktop accounts](DESKTOP-ACCOUNTS.md)).

## 1. Open the console

**The goal.** One session holds the plan, so no builder has to guess what is next.

**What to paste:**

```text
You are the console for this build. You plan and track; you do not write application code.

Read the backlog. Produce a build plan that breaks it into tasks sized for one session each,
and write an ADR for any decision that outlives the task that made it.

Write one disposable brief per task and open a build session on it. When a builder reports a
task blocked, its session ends: take the task back, update the backlog, and brief the next one.

Do not wait on a message from a builder. Poll for state instead.

Do not build. Do not merge.
```

**What happens next.** It reads the repository and comes back with a plan and a task breakdown. Ask
it to write the backlog to a tracked file before it briefs anything, because a plan that lives
only in one context dies with that context.

## 2. Open a build session per brief

**The goal.** One session per brief, each unable to silently overwrite the other.

**What to paste,** into each:

```text
You are a build session. Build the task in your brief as a workflow, then stop.

If the brief leaves something open, do not guess and do not wait for an answer. Write the
question to the console, comment it on the pull request, and stop.

Before starting a task, take a claim on it with a one-line note saying what you are building:
  pwsh -NoProfile -File scripts/coord/claim.ps1 -Take "<task>" -Note "<what you are building>"

A free-text key like this is ADVISORY: peers can see it, and nothing enforces it. Only a
numbered key is enforced, by the commit-msg gate, and only when your commit subject names it.
A claim can also be refused because somebody holds it -- read the result.

Before editing a file you did not create, check who else is in it. Pass the path -- a bare
run prints the whole-repo roster and never names a file:
  pwsh -NoProfile -File scripts/coord/overlap.ps1 -File <path>

Read the exit code, not just the rows. 0 means the question was answered, including an
answer of nobody. 2 means it could not be, and silence there is not an all-clear.

Commit at logical stops. Push your own branch and open your own pull request. Do not merge:
the lander decides what enters the merge queue.
```

**That prompt is a brief, and every brief runs out.**
[Brief a worker session](WORKER-BRIEF.md) is the template for one, plus the rule that makes a worker
ask rather than guess when it does.

**What happens next.** Each session announces itself to the peers it can reach, takes its claims,
and starts building. When both reach for the same file, the second edit is normally refused rather
than merged ([Coordination](COORDINATION.md)).

**"Normally" is doing work in that sentence.** The gate refuses only when the peer worktree is live
**and** holds uncommitted changes to that exact path. A peer that committed and went clean is
reported and allowed.

It also fails open, and its blind spots are worth reading before you rely on it
([Limits](LIMITS.md#what-the-collision-gate-does-not-see)).

**Why one brief per session.** A session that ends when its brief is done spends nothing while it
waits, where a session held open to poll pays for its whole context on every pass.

**The five-hour cap is not the binding one.** This shape spends a weekly window in about two days,
which is why the framework page expects more than one account. That reasoning is in
[The KORUS framework](KORUS.md).

[Token accounting](TOKEN-ACCOUNTING.md) measures the other half: what one percent of a weekly window
is worth, and what a month of it costs at published API rates.

## 3. Open the lander

**The goal.** One session owns the remote, so the trunk moves under a single decision-maker.

**What to paste:**

```text
You are the lander. You decide what enters the merge queue and in what order, and you
merge-forward. Builders push their own branches and open their own pull requests.

Do not merge a pull request that has no reviewed label. Keep one ledger-appending pull
request in the queue at a time.

Read state rather than being told it:
  pwsh -NoProfile -File scripts/coord/presence.ps1   # who is live
  pwsh -NoProfile -File scripts/coord/overlap.ps1    # what is in flight

Decide which of two branches on the same ground lands first, and who re-syncs after.
You arbitrate and land. You do not build.
```

**What happens next.** It reads the branches rather than waiting to be told about them.

**A pushed branch is the signal here**, because builders push their own. The lander reads the open
pull requests and takes the ones carrying a reviewed label.

**Read the role page before you rely on it.** The authority is not transferable, the route is
absolute, and a worker that cannot reach the lander is blocked rather than promoted.
[Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) owns the full role.

## The daily loop

1. **Ask the console what is in flight.** It answers from the backlog, not from memory.
2. **Check the builders have not collided.** A bare `overlap.ps1` gives the roster; `-File <path>`
   answers who is in one file.
3. **Steer rather than wait.** A session deep in the wrong approach does not see your typing until
   its turn ends ([Steering](STEERING.md)).
4. **Let the lander land.** It decides the order. You approve the merge in words, once, and
   that approval does not carry to the next branch.
5. **Prune what merged**, from the primary checkout. `prune-merged.ps1` refuses to run from a linked
   worktree, and every session here is in one. It removes worktrees that are merged **and** clean
   **and** unoccupied ([Pruning](PRUNING.md)).
6. **Re-prove the gates when something surprises you.** They fail byte-identically to succeeding, so
   a quiet week is not evidence: `pwsh -NoProfile -File <tooling>/bin/ccx-doctor.ps1 -Repo <target>`
   ([Troubleshooting](TROUBLESHOOTING.md)).

## When it goes wrong

| Symptom | What it actually is | Go to |
|---|---|---|
| Two branches built the same feature | Effort overlap. No gate can compute it | [Coordination](COORDINATION.md) |
| Two records took the same number | The collision git cannot see | [Sequence allocation](SEQUENCE-ALLOC.md) |
| A session is deep in the wrong approach | Your typing queues until the turn ends | [Steering](STEERING.md) |
| Branches will not land | Four states with three different fixes | [PRs and merges](PR-AND-MERGE.md) |
| A peer cannot be reached at all | Extension session, or another login | [Session mail](SESSION-MAIL.md) -- a design to build, not a shipped lane |
| Everything is green and you cannot tell if any of it runs | Every failure here looks like success | [Limits and requirements](LIMITS.md) |

## What this shape does not decide for you

**Whether the work was any good.** The gates refuse collisions. Nothing here reviews a change, and
CI is what turns "it merged" into "it passed" ([CI for leaders](CI-FOR-LEADERS.md)).

**Whether you are about to run out.** Usage-limit awareness is a design on this site, not a shipped
hook ([Usage awareness](USAGE-AWARENESS.md)).

**Who writes shared state outside git.** Project memory and shared notes are last-write-wins, and
the remedy is single-writer convention rather than a gate.

## Related

| For | Read |
|---|---|
| The template for one worker's prompt, and the rule that stops it guessing | [Brief a worker session](WORKER-BRIEF.md) |
| The account of why this shape, in its author's words | [The KORUS framework](KORUS.md) |
| Which surface to run the sessions on, and the channels between them | [Running multiple sessions](RUNNING-MULTIPLE-SESSIONS.md) |
| The model every page here applies | [Concepts](CONCEPTS.md) |
| The things that bite, in the order they bite | [Tips and tricks](TIPS-AND-TRICKS.md) |
