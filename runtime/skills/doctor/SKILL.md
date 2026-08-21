---
name: doctor
description: System and goal-aware health diagnostics, including credential liveness. Use on /counsel:doctor, after installs/changes, when something seems broken, or with a goal argument to check task readiness.
user_invocable: true
---

# /counsel:doctor [goal] [--probe]

Provenance: ORIGINAL (Apache-2.0). A tool can be absent and the system healthy — severity
is contextual: **BLOCKING · REQUIRED FOR SELECTED CAPABILITY · RECOMMENDED · UNVERIFIED ·
OPTIONAL · INFORMATIONAL**. Missing optional tools never make Counsel look broken.

Check families (drive from the registries, not hardcoded lists):
1. **Core integrity** — constitution present/parsable; always-on rules resolve; ownership
   manifest vs disk drift; provenance headers intact.
2. **Dependencies** — per dependencies.yaml `detect`, functional over presence (e.g.
   Superpowers = its hook actually fired, not just installed). Remediation card per
   finding: Problem / Impact / Recommended action / Alternative / Verification. Never
   invent install commands — point at the authoritative source.
3. **Permissions self-audit** — wildcard allows that a positional deny cannot constrain;
   deny-vs-prose parity; secret-exclusion surface consistency.
4. **Rule reachability** — path-scoped rules whose globs match nothing in this repo
   (silent-never-fires defect); citations to files/entries that don't exist (stale evidence).
5. **Session continuity** — run session-doctor script; checkpoint freshness; capsule budget.
6. **Work plane** — queue bounded; batch counter vs lease; stale ACTIVE/BLOCKED tickets;
   discovered-work candidates awaiting triage.
7. **Cost/context (INFORMATIONAL)** — boot-weight estimate + trend; suggest /context and
   /usage for live numbers (never invent usage); current lease + tripwire mode if
   observable; autonomy health counters when available (completions, escalations,
   reopens, failed attempts, scope-drift stops).
8. **Credential liveness (D-T2-030)** — for every `credentials:` entry in dependencies.yaml
   whose `required_by` intersects the installed capabilities: is the credential configured,
   and does it actually still work? Engine: `scripts/doctor-credentials.ps1` (Windows) /
   `scripts/doctor-credentials.sh` (POSIX).

## Credential liveness — the rule that changes READY

**Tooling presence is not readiness.** `gh` on PATH with an expired token, a PostHog key
rotated last week, a Vercel login that lapsed — each passes a presence check and fails at
the moment of use. That is silent-delayed failure: the defect class this OS exists to move
*forward* in time. So READY now requires proven credentials, not merely installed tools.

| State | Meaning | Severity when the capability is installed |
|---|---|---|
| LIVE | probed, credential accepted | INFO |
| DEAD | probed and rejected, or required and not configured at all | **BLOCKING** |
| UNKNOWN | not probed, not probeable, or the probe itself failed | **UNVERIFIED** |
| SKIP | no installed capability requires it | INFO |

Four laws the engine enforces, and you must not talk around:
1. **Never fabricate LIVE.** Unprobed is UNKNOWN. A network fault is UNKNOWN, *not* DEAD —
   a probe that could not run has proven nothing about the key.
2. **Never print secret material.** Values are scrubbed from all output; a salted 8-hex
   fingerprint is shown instead, which also auto-invalidates the cache on rotation.
3. **Probes are read-only.** A registry entry marked `mutating: true` is refused, not run.
   A probe with side effects is not a diagnostic.
4. **Probes leave the machine, so they are opt-in.** A default run is offline and says so.
   `--probe` runs free read-only probes; `metered`/`unknown` cost probes are ask-first and
   never run unattended. Results cache for 12h keyed to the credential's fingerprint.

When a credential is DEAD, the card's *Recommended action* is the registry's `rotate`
pointer verbatim, and *Impact* is its `scope` — say what the dead key was allowed to do.
Where liveness genuinely cannot be established (PostHog's capture endpoint accepts any
well-formed key; Sentry exposes no unauthenticated DSN check), report UNKNOWN with the
registry's `probe_note`. **An honest UNKNOWN is the correct output. A convenient LIVE is a lie.**

## Output contract

With a goal argument, evaluate readiness for THAT task only — including the credentials that
goal will actually touch. After any fix, re-run the relevant check and report the delta — a
fix is not fixed until re-verified.

Output ends with exactly one of:

| Line | Exit | Means |
|---|---|---|
| `N BLOCKING ISSUE(S)` | 1 | includes dead/absent credentials for installed capabilities |
| `NOT READY — N CREDENTIAL CHECK(S) UNVERIFIED` | 3 | tooling present, liveness unproven |
| `READY WITH N RECOMMENDATION(S)` | 2 | nothing blocking, nothing unproven |
| `READY (tooling present and credentials proven live)` | 0 | fully verified |

Never report READY while any credential state is UNKNOWN. "Your tools are installed" and
"your keys work" are different claims; only the second one is readiness.
