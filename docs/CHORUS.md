# The CHORUS Framework: Lesson Learned the Hard Way

Hello, I'm a senior developer working on a major project since late May, 2026.
(See MessageFoundry.org). This is a personally written summary of what I've learned.

Since things with an acronym are more trusted, Claude suggests the following be call CHORUS:
Coordinated Handoffs, One Repo, Unblocked Sessions.

## BLUF/TLDR

The following is a framework developed during months of Claude Code work. This document and this
site provide a starting point for new projects. This framework contains technical elements
supporting better AI coding.

## CHORUS for Multi-session AI-Coding

Here is the shape of what I've learned.

1. Use Claude Code with Ultracode mode.

2. For multisession coding, Claude Code for Desktop works better than the VS Code extension.

3. Use one or more Claude Max 20x accounts instead of Teams or Enterprise pricing.

4. Set up four sessions:

   1. A dispatcher, which plans the build, tracks backlog, and dispatches work to the build
      sessions.

   2. Two build sessions, each running four sub-session build tasks.

   3. A coordinator session, which handles all external repo work (pushes, merges, etc.)

5. Use worktrees with hooks enforcing Claude Code's behavior.

6. Use inter-session communication, allowing the sessions to talk with each other.

I'll go through each of those and more in the following sections. Note: these recommendations are
based on the Claude tools as of 8/12/2026. Things will change as Anthropic releases improvements.

## 1. Use Claude Code with Ultracode Mode and Opus 5

[Ultracode mode](https://code.claude.com/docs/en/workflows#let-claude-decide-with-ultracode)
produces better results. Enabling it empowers Claude to launch workflows, which are a key part of
this method. Workflows break the task into assignments handed to subagents. Ultracode also triggers
[adversarial validation](https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step),
producing better results.

Opus 5 is presently the best mode for creating strong code. It is even slightly better than Fable 5
at creating code and at half the price.

Unfortunately, using Ultracode and Opus 5 together is slow. The result is worth the wait, having
fewer bugs to resolve later.

That multisession method makes good use of the wait time. Since you are administering eight
workflows, there's usually something for you to decide.

## 2. Use Claude Code for Desktop

Claude's desktop application is the best at empowering intersession communication. The VS Code
extension lacks the strongest implementation of these as of 8/2026. As a result, running multiple
sessions inside of VS Code generates code collisions.

The desktop app, however, makes it difficult to see the final code. In VS Code, you always are a
click away from the current codebase.

You might find it helpful to have a VS Code instance running alongside your Claude desktop app. Use
the desktop app to generate the code and the VS Code to review and make manual edits.

## 3. Subscribe to Claude Max 20x, Multiple Accounts: 60x Cheaper

Yes, that header is correct: Claude's Max 20x accounts offer AI compute at 60x cheaper than the
undiscounted API rates you pay under Teams or Enterprise plans. **If you bought the same compute Max
20x gives you under API pricing, it would cost about $12,000.** For details, see
[Token Accounting](https://claude-multisession.pages.dev/TOKEN-ACCOUNTING.html).

As a result, the Max 20x plan is the best way to affordably create your application. The individual
accounts lack the enterprise management features but can save you thousands.

You may require multiple Max 20x accounts to cover a week of heavy development. You can sign up for
as many $200 per month accounts as you want, just use different email addresses. This is fully
compliant with Anthropic's rules.

Max 20x limits your usage through five-hour session and weekly usage caps. Generally, 1% of weekly
usage equals about 5% of session usage.

The per-session usage limits are a key factor in my recommendations. If you run two build sessions
each executing four tasks at a time, you'll normally run under the session limits. You'll use up
your weekly limit in about two days.

You could split those eight build tasks into individual sessions, but that increases your
intersession communication costs.

If you run tasks that fan out into many-agent workflows, especially /deep-research work, you'll
need to reduce the number of tasks running.

## 4. Backlog

Have Claude Code create a project backlog. Then tell it to add things as they come up. Later, tell
the Dispatcher session to create a plan for building down that backlog.

## 5. Documentation

### 1. ADRs: Architecture Decision Records

Have Claude create ADR documents for each significant build. When you ask the Dispatcher session to
create a plan, just tell it to be sure to create ADRs as needed. This gives you a build record for
your CISO and any auditor. It also provides ongoing context for the AI.

### 2. ASVS Register

OWASP's ASVS 5 framework is a great way to harden your application against hackers. There are three
security levels depending on what your application touches.

Have Claude create a register of your OSVS scores. Be sure it works against the exact wording of
OSVS 5, not against summaries Claude creates or gets from other sources.

Then, have Claude anchor your OSVS scores against sym/ctx anchors. Don't point at a line number in
the code; that changes when you update the code. Sym/ctx identifies code by its shape, not by its
position. That means the reference only changes when the actual code structure changes -- not when
someone adds whitespace, comments, or moves unrelated code above it.

## 6. Four Concurrent Sessions

Be sure Ultracode and Opus 5 are enabled for each session.

### 1. Dispatcher Session

Dispatcher creates the build plan and assigns the work to builder sessions. It doles out initial
work of about four tasks for each of the two build sessions. If a build session's task becomes
blocked, the dispatcher takes back the task and updates the backlog.

### 2. Two Build Sessions

Each build session tackles about four tasks as sub-sessions/workflows/agents.

Note that Anthropic is working on [Agentic Teams](https://code.claude.com/docs/en/agent-teams),
which may be a significant enhancement once it is out of beta. For now, your build sessions will use
[dynamic workflows](https://code.claude.com/docs/en/workflows). See
[Run agents in parallel - Claude Code Docs](https://code.claude.com/docs/en/agents).

### 3. Coordinator Session

Coordinator handles all external git repo work, including pushing and merging. It should have
authority to handle these independently. This is needed because multisession coding creates merge
conflicts when the repo's head is constantly changing. This is especially true with larger
codebases, which created extended CI times.

### 4. ASVS Monitor Session

This is an extra concurrent session used when following the OWASP ASVS framework. It ensures that
your ASVS register is always up to date.

## 7. Worktrees

Worktrees deconflict workflows sharing a repo. See
[Worktrees - claude-multisession](https://claude-multisession.pages.dev/WORKTREES) and
[Run parallel sessions with worktrees - Claude Code Docs](https://code.claude.com/docs/en/worktrees).

## 8. Inter-session Communication & Coordination

Claude Code for Desktop contains an almost hidden method for your sessions to talk to each other.
Combined with the coordination methods listed in
[Coordination](https://claude-multisession.pages.dev/COORDINATION), the sessions can build your
project without conflict -- mostly. When there is a conflict, the build sessions can talk with the
Coordinator and Dispatcher and find solutions. Also see
[Message your other Claude Code sessions - Claude Code Docs](https://code.claude.com/docs/en/cross-session-messaging)

## 9. Don't Hit Usage Limits: It Causes Lost Work

Anthropic has rejected enhancement requests asking to make Claude Code usage-limit aware. So, Claude
and I built one:
[Usage awareness: knowing when to stop.](https://claude-multisession.pages.dev/USAGE-AWARENESS)

## 10. CI: Continuous Integration for Quality Code

CI using GitHub Actions automates enforcement of your quality standards and prevents bugs from
reaching the repo. See [this CI introduction](https://claude-multisession.pages.dev/CI-FOR-LEADERS.html).
