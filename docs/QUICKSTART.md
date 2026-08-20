# Counsel — quickstart

Provenance: ORIGINAL (Apache-2.0).

Counsel is an AI engineering team that runs inside Claude Code. It reads your codebase before
it gives an opinion, plans work before it writes code, and keeps your session state on disk so
a crash or a context reset doesn't lose your place.

**Time to first result: about 15 minutes**, most of it installing Claude Code.

> **This is pre-alpha.** Expect rough edges. It is honest about what it doesn't know, which is
> the part most worth judging it on.

---

## ⚠ Read this before you start: platform support

| Platform | Status |
|---|---|
| **Windows 10/11** (PowerShell 5.1+) | **Supported.** This is the tested path |
| **macOS** | **Setup does not complete.** The plugin installs and every file is readable, but `/counsel:onboard` cannot finish — its installer is PowerShell and has no shell equivalent yet |
| **Linux** | Untested. Same installer constraint as macOS |

Installing PowerShell on macOS is **not** a workaround. `pwsh` existing does not mean these
scripts behave correctly there — nobody has tested it, so don't build on it.

If you're not on Windows, you can still read the code and form a view. You cannot yet run it.

---

## Before you start

| You need | How to check |
|---|---|
| A GitHub account with access to the repo | You can open the repository page and see files, not a 404 |
| Git installed | `git --version` returns a version number |
| A Claude subscription or API access | You'll be prompted to sign in during step 1 |

---

## Step 1 · Install Claude Code

Follow the official installer: <https://docs.claude.com/en/docs/claude-code/setup>

Claude Code also ships a VS Code extension, so you can run it in a panel beside your editor
instead of in a terminal.

> **If you use Cursor:** Cursor is built on VS Code but is **not** the officially supported
> target and Counsel has not been validated there. Try it and report what happens — the
> terminal path in this guide always works.

**You'll know it worked when:** `claude` runs in a terminal and gives you a prompt, or the
Claude Code panel opens in your editor.

---

## Step 2 · Prove GitHub access *before* installing anything

This is the single most common place people get stuck, and the error you'd hit later does not
say "permissions" — so check now.

```
gh auth status
```

If `gh` isn't installed, get it from <https://cli.github.com>, then:

```
gh auth login
```

Choose **GitHub.com** → **HTTPS** → **Login with a web browser** and follow the prompts.

**You'll know it worked when:** `gh auth status` prints `✓ Logged in to github.com`.

---

## Step 3 · Add the marketplace

A "marketplace" is just where Claude Code fetches plugins from. One line:

```
claude plugin marketplace add sherzadeh/counsel-engineering-os
```

**You'll know it worked when:** `claude plugin marketplace list` shows `counsel-os`.

---

## Step 4 · Install the plugin

```
claude plugin install counsel@counsel-os
```

Then **restart Claude Code.** Plugins load at startup; skipping the restart is the second most
common way to get stuck.

**You'll know it worked when:** `claude plugin list` includes `counsel`, and typing `/counsel:`
offers commands like `/counsel:onboard` and `/counsel:doctor`.

---

## Step 5 · Point it at a real project

Open a project folder you actually work in. A scratch folder technically works but tells you
almost nothing — Counsel's whole value is that it reads your real code.

```
/counsel:onboard
```

It asks **one** question: *what are you trying to do?* Answer in plain English ("understand this
codebase", "fix bugs", "build a feature"). It then:

1. Reads your repo to work out stack, size, and existing config.
2. Recommends the **smallest useful setup** — and shows why, what it adds, and what it costs.
3. Shows the install plan **file by file** before writing anything.
4. Writes **only what you approve.** Permission changes are always a separate consent.

Nothing is written without your say-so. If you don't like the plan, say no.

---

## Step 6 · Confirm it's healthy

```
/counsel:doctor
```

**You'll know it worked when:** it reports READY, or gives specific findings with instructions.

Findings are normal — it's built to tell you what's wrong rather than fail silently. Note that
READY requires credentials to be **proven**, not merely present: an expired token that exists
still counts as NOT READY, because a green light you can't cash is worse than a red one.

---

## Your first 15 minutes

Run this on a repo **you already know well**:

```
/counsel:grok-codebase
```

This is the fastest honest test of whether the tool is any good. You already know the right
answer, so you can judge the output immediately — no benchmark required.

---

## The four modes — the setting most people miss

Mode changes **who does the work** and **how decisions reach you**. It never changes the safety
floor or how much autonomy Counsel has. You set it; Counsel may recommend a change but never
switches by itself.

| Mode | Who does the work | Use it when |
|---|---|---|
| **Learn** | **You do.** Counsel explains, you try, it verifies and corrects | You want to get better, not just get it done |
| **Pair** *(default)* | Counsel implements routine work, thinks aloud, involves you at judgment calls | Almost always — this is the sane default |
| **Autopilot** | Counsel plans, implements, verifies and checkpoints bounded work without narrating | Well-understood, low-risk work you don't want to watch |
| **CTO** | Counsel reports outcomes, not mechanics: what happened, what it means, what needs your call | You're deciding, not coding |

Autopilot reduces *commentary*, not caution — consequential decisions still stop and ask.

---

## The working loop

For anything bigger than a one-liner:

```
/counsel:plan     →  turns a goal into bounded, verifiable tickets before any code
/counsel:next     →  picks up the top ready ticket and starts it
/counsel:verify   →  checks the work actually holds, before anyone calls it done
/counsel:checkpoint →  saves durable state so a crash or context reset costs you nothing
```

Full command map:

| Command | What it does |
|---|---|
| `/counsel:onboard` | First-run setup — the only one you must run |
| `/counsel:doctor` | Diagnoses install and credential health |
| `/counsel:grok-codebase` | Understands a codebase before judging it |
| `/counsel:plan` | Goal → bounded, verifiable tickets |
| `/counsel:next` | Activates the top ready ticket |
| `/counsel:queue` | Shows what's in flight, ready, and blocked |
| `/counsel:systematic-debugging` | Root-causes a bug instead of guessing at fixes |
| `/counsel:code-review` | Reviews with anti-rubber-stamping discipline |
| `/counsel:verify` | Confirms work before it's claimed done |
| `/counsel:checkpoint` | Saves recoverable session state |
| `/counsel:restore` | Recovers after a crash, `/clear`, or compaction |
| `/counsel:mentor` | Teaches while building (Learn mode) |
| `/counsel:capabilities` | Shows what's installed and what's available |
| `/counsel:recommend` | Suggests the smallest useful setup for a goal |

You don't need to memorize these. Talk to it in plain language — it reaches for the right one.

---

## What it costs you

Counsel is not free in context. The always-on rules are deliberately small, but specialist
agents, codebase groks, and full reviews consume real tokens — a grok of a large repo is a
meaningful chunk of a session.

Three things keep it in hand: it starts at **Core** and only grows when you approve a bigger
layer; specialists staff in **only when the consequence justifies it**; and idle capabilities
cost nothing. If a session feels expensive, `/counsel:capabilities` shows what you've turned on,
and you can drop back down.

---

## Updating

Updates are **manual on purpose** — nothing changes under you mid-task.

```
claude plugin marketplace update counsel-os
claude plugin update counsel@counsel-os
```

Restart Claude Code, then run `/counsel:doctor`. If your project files came from an older
runtime it reports **RUNTIME VERSION SKEW** and walks you through it. Your own edits are never
silently overwritten.

---

## When it breaks

1. Run `/counsel:doctor` first — it is built to explain its own failures.
2. Confirm you **restarted Claude Code** after installing (step 4).
3. Confirm `gh auth status` still shows you logged in (step 2).
4. Still stuck? Open an issue with **which step number** you were on and the exact error. That
   is far more useful than "it didn't work" — and it's how this guide gets fixed.

Getting stuck is data. This guide is pre-alpha too.

---

## Where to go next

| You want | Read |
|---|---|
| The 60-second mental model | `START-HERE.md` |
| Install detail, teammate setup, repair/uninstall | `docs/INSTALL.md` |
| How the layers, staffing and memory model work | `docs/ARCHITECTURE.md` |
| How checkpoints and recovery work | `docs/CONTINUITY.md` |
| What you may and may not do with this software | `LICENSE`, `NOTICE` |

**On licensing, briefly:** Counsel is under the **Apache License 2.0**. Use it for anything —
personal projects, study, your job, client work, or inside a product you sell. Modify it and
redistribute it. The one obligation is **attribution**: keep the copyright notice and ship the
`NOTICE` file with any copy or derivative, so credit to the original author travels with the code.
See `LICENSE` and `NOTICE`.
