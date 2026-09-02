# The KORUS framework: Lessons learned the hard way

> **Take a copy:**
> [markdown](https://claude-multisession.pages.dev/KORUS.md)
> or [Word document](https://claude-multisession.pages.dev/word/KORUS.docx).

Hello, I'm a senior developer working on a major project since late May, 2026.
(See MessageFoundry.org). This is a personally written summary of what I've learned.

I call it **KORUS: Keep One Repo, Unblock Sessions**. That is the whole idea in four words:
everything below follows from keeping one repository and stopping the sessions blocking each other.

## BLUF/TLDR

The following is a framework developed during months of Claude Code work. This document and this
site provide a starting point for new projects. This framework contains technical elements
supporting better AI coding.

**This page is the reasoning. If you want the commands, they are elsewhere:**
[Quickstart](QUICKSTART.md) installs the enforcement, and
[Run a KORUS build](KORUS-BUILD.md) is the operating procedure for the session shape in section 6.

**Last reviewed 2026-08-16.** The model, pricing and client advice below is the part that rots:
check anything about plans, limits or model names against Anthropic's current documentation before
relying on it.

## KORUS for Multi-session AI-Coding

Here is the shape of what I've learned.

1. Use Claude Code with Ultracode mode.

2. For multisession coding, Claude Code for Desktop works better than the VS Code extension.

3. Use one or more Claude Max 20x accounts instead of Teams or Enterprise pricing.

4. Set up the sessions:

   **4.1.** A console, the one session you talk to. It reads the record, picks an item, writes a
   short brief, and starts a builder for it.

   **4.2.** A builder for each brief. It makes the change, commits, pushes, and opens the pull
   request, then its process exits.

   **4.3.** A lander session, which decides what enters the merge queue and in what order.

   There are additional, optional sessions as described below.

5. Use worktrees with hooks enforcing Claude Code's behavior.

6. Use the Kynet method to enable inter-session communication (see below).

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

If you run more than one Claude account, set them up first:
[Desktop accounts](DESKTOP-ACCOUNTS.md) covers one desktop instance per account, and the config root
each one adds.

## 3. Subscribe to Claude Max 20x, Multiple Accounts: 60x Cheaper

Yes, that header is correct: Claude's Max 20x accounts offer AI compute at 60x cheaper than the
undiscounted API rates you pay under Teams or Enterprise plans. **If you bought the same compute Max
20x gives you under API pricing, it would cost about $12,000.** For details, see
[Token Accounting](https://claude-multisession.pages.dev/TOKEN-ACCOUNTING.html).

As a result, the Max 20x plan is the best way to affordably create your application. The individual
accounts lack the enterprise management features but can save you thousands.

You may require multiple Max 20x accounts to cover a week of heavy development. You can sign up for
as many $200 per month accounts as you want, just use different email addresses.

**Check this against the current terms yourself before you rely on it.** I believe separate accounts
on separate email addresses are within the terms, and that belief is mine rather than a citation: I
am not a lawyer, and these documents change. The ones that govern it are Anthropic's
[Usage Policy](https://www.anthropic.com/legal/aup),
[Consumer Terms](https://www.anthropic.com/legal/consumer-terms), and
[the Claude Code plan guidance](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan).
What is definitely not allowed is sharing one account between people.

Max 20x limits your usage through five-hour session and weekly usage caps. Generally, 1% of weekly
usage equals about 5% of session usage.

The per-session usage limits are a key factor in my recommendations. If you keep about eight build
tasks running at a time, you'll normally run under the session limits. You'll use up your weekly
limit in about two days.

Splitting those tasks into separate sessions costs some intersession communication. It costs
nothing to leave a session idle once it has ended its turn.

If you run tasks that fan out into many-agent workflows, especially /deep-research work, you'll
need to reduce the number of tasks running.

## 4. Backlog

Have Claude Code create a project backlog. Then tell it to add things as they come up. Later, tell
the console session to create a plan for building down that backlog.

## 5. Documentation

### 5.1 ADRs: Architecture decision records

Have Claude create ADR documents for each significant build. When you ask the console session to
create a plan, just tell it to be sure to create ADRs as needed. This gives you a build record for
your CISO and any auditor. It also provides ongoing context for the AI.

### 5.2 GitHub Spec Kit

GitHub's Spec Kit is a strong starting point for SDD (Spec-Driven Development). It is an antidote to
vibe coding's flaws. See
[this Spec Kit page](https://claude-multisession.pages.dev/FRAMEWORK-spec-kit).

### 5.3 ASVS register

OWASP's ASVS 5 framework is a great way to harden your application against hackers. There are three
security levels depending on what your application touches.

Have Claude create a register of your ASVS scores. Be sure it works against the exact wording of
ASVS 5, not against summaries Claude creates or gets from other sources.

Then, have Claude anchor your ASVS scores against sym/ctx anchors. Don't point at a line number in
the code; that changes when you update the code. Sym/ctx identifies code by its shape, not by its
position. That means the reference only changes when the actual code structure changes -- not when
someone adds whitespace, comments, or moves unrelated code above it.

## 6. Each Session Does One Job

Be sure Ultracode and Opus 5 are enabled for each session.

[Run a KORUS build](KORUS-BUILD.md) is the operating procedure for this section: the opening prompt
for each session, the daily loop, and what to do when it goes wrong.

### 6.1 Console session

The console is the only session you talk to. It reads the record, picks an item, writes a short
brief, and starts a builder for it. It then polls for state instead of waiting on a message. If a
builder hits a question its brief did not answer, the builder writes the question back to the
console and stops, and the console starts a fresh builder with a better brief.

### 6.2 Builder sessions

A builder takes one brief and runs it to a pull request: the change, the commit, the push, and the
PR. Then its process exits. It never guesses at what the brief left open, and it never waits for an
answer.

Note that Anthropic is working on [Agentic Teams](https://code.claude.com/docs/en/agent-teams),
which may be a significant enhancement once it is out of beta. For now, your builders will use
[dynamic workflows](https://code.claude.com/docs/en/workflows). See
[Run agents in parallel - Claude Code Docs](https://code.claude.com/docs/en/agents).

### 6.3 Lander session

Lander decides what enters the merge queue and in what order, and it merge-forwards. It should have
authority to handle these independently. This is needed because multisession coding creates merge
conflicts when the repo's head is constantly changing. This is especially true with larger
codebases, which created extended CI times. It will not merge a pull request that no reviewer has
labelled.

### 6.4 Reviewer session

This section used to describe an ASVS monitor session, which was retired on 2026-09-01.

Start a reviewer for each pull request. It reads the diff. On a pass it applies the reviewed label
and posts the head SHA it read, so you can tell which version was actually looked at. On a fail it
posts the findings on the pull request, for whichever builder comes next. A reviewer never merges.

### 6.5 Regulator session

Start a regulator when a required check goes red. Its job is deciding whose failure it is: the
pull request's, the trunk's, a flake's, or the queue's. Only the first is a builder's to fix.
Sending the other three back is the mistake it prevents. It has no memory of earlier reds, so
it keeps a log.

**A steward is not on this list, because it is not a session.** It is a cron with no model calls.
It reads account usage and names the account with headroom, and it cannot interrupt a session
that is already running.

## 7. Worktrees

Worktrees deconflict workflows sharing a repo. See
[Worktrees - claude-multisession](https://claude-multisession.pages.dev/WORKTREES) and
[Run parallel sessions with worktrees - Claude Code Docs](https://code.claude.com/docs/en/worktrees).

## 8. Inter-session Communication & Coordination

Claude Code sessions can be configured to speak with each other. The method differs between sessions
inside of the desktop app and those in the VS Code extension.

Combined with the coordination methods listed in
[Coordination](https://claude-multisession.pages.dev/COORDINATION), the sessions can build your
project without conflict -- mostly. When there is a conflict, a builder writes the problem to the
console rather than guessing, and the console decides what happens next. Also see
[Message your other Claude Code sessions - Claude Code Docs](https://code.claude.com/docs/en/cross-session-messaging)

## 9. Don't Hit Usage Limits: It Causes Lost Work

Anthropic has rejected enhancement requests asking to make Claude Code usage-limit aware. So, Claude
and I built one:
[Usage awareness: knowing when to stop.](https://claude-multisession.pages.dev/USAGE-AWARENESS)

## 10. CI: Continuous Integration for Quality Code

CI using GitHub Actions automates enforcement of your quality standards and prevents bugs from
reaching the repo. See [this CI introduction](https://claude-multisession.pages.dev/CI-FOR-LEADERS.html).
