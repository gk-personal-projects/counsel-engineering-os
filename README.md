# Counsel Engineering OS

A vibe-coder sidekick for Claude Code — an AI CTO and engineering team that plans, evaluates,
backlogs and executes software work. It starts small, grows with your project, and stops at
anything consequential.

> ### ⚠ Platform support, before you install
> **Setup completes on Windows only.** On macOS and Linux the plugin installs and every file is
> readable, but `/counsel:onboard` **cannot finish** — the installer scripts are PowerShell and have
> no shell equivalents yet. Installing `pwsh` on a Mac is *not* a supported workaround; nobody has
> tested that path. A `.sh` port is the top priority. See [`docs/INSTALL.md`](docs/INSTALL.md).

**What you get**
- ✓ technical guidance from a CTO that groks your codebase before judging
- ✓ debugging, feature planning, and implementation help
- ✓ architecture and security review when the work warrants it
- ✓ software-development mentoring (Learn mode)
- ✓ diagnostics (`/counsel:doctor`) and safe, reversible setup
- ✓ session continuity — crashes, restarts, and context resets don't lose your work
- ✓ a lightweight work system (roadmap → queue → tickets) with bounded autonomy

**New here? Start with [`docs/QUICKSTART.md`](docs/QUICKSTART.md)** — every step has a check so
you know it worked, plus how to actually use Counsel once it's installed. Read the platform
note at the top first: setup completes on Windows only today.

**Quick start** (full detail + teammate path: `docs/INSTALL.md`)


1. `claude plugin marketplace add sherzadeh/counsel-engineering-os`
2. `claude plugin install counsel@counsel-os`
3. Open your project in Claude Code and run `/counsel:onboard` — answer one question: *what are you trying to do?*
4. Onboarding shows you an install plan (nothing is written without your approval — permission changes are always a separate consent), then runs `/counsel:doctor`.
5. Start building.

Counsel starts small (Core) and grows with your project (Builder → Engineering Team →
Full OS). Not sure what you need? Onboarding recommends the smallest useful setup —
or ask `/counsel:recommend` anytime.

**Promises:** updates preserve your decisions and project context; uninstall removes only
Counsel-owned files; optional tools you don't have never make Counsel look broken;
Counsel never expands its own authority, budget, or autonomy.

Docs: `docs/QUICKSTART.md` → `START-HERE.md` → `docs/INSTALL.md` → `docs/ARCHITECTURE.md` ·
License: **Apache-2.0** (see LICENSE, NOTICE, PROVENANCE.md). Free to use, modify and redistribute, commercially or not — the one condition is that you keep the copyright and NOTICE attribution to Sam Sherzad. · Status: pre-alpha (see VERSION) — expect rough edges; setup completes on Windows only.
