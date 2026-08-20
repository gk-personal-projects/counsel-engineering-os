# Changelog

All notable changes to Counsel Engineering OS. Semantic Versioning where practical.

## [0.1.0-internal] — 2026-08-12

Initial internal build (Track 2, post Gate T2-A approval).

- Repository bootstrap: license (Apache-2.0), NOTICE, provenance register.
- Runtime / control-plane boundary architecture (docs/ARCHITECTURE.md).
- Session continuity system with acceptance tests (T2.3).
- Capability and dependency registries (T2.4).
- Counsel Core (T2.5) and progressive layers (T2.6).
- First-run UX (T2.7).

Not published. No external distribution.

## 0.1.1 (2026-08-12)
Installer (plan/apply/repair/uninstall), ownership manifest, doctor extensions,
model-map, schema-version, skill namespace rename. First installable release.

## 0.1.2 (2026-08-12)
Semver-aware cache version selection (doctor/plan/repair); modes rule clarification.

## 0.1.3 (2026-08-13)
Safety-floor hardening upstreamed from the first governed install's security re-review
(2026-08-12): exec-on-untrusted-code rule in safety-base (builds/tests execute repo code —
never run them on unreviewed diffs); settings baseline gains denies for destructive
shell/git operations, fetch-pipe execution (`curl | sh` class), `git --output` file-write
vectors, and depth-anchored `.env`/`.secrets` reads. Baseline remains deny-only; grants nothing.

## 0.1.4 (2026-08-14)
Private distribution-channel work. No runtime behaviour changes - docs, release
metadata, and honesty fixes only. Channel-specific documentation is not published.

- `docs/INSTALL.md`: **Platform support** section. States plainly that `/counsel:onboard` cannot
  complete on macOS (`scripts/install/*.ps1` have no shell equivalents) and that installing
  `pwsh` is not a supported workaround. Previously this constraint was undocumented.
- `NOTICE`: corrected. It asserted that derived Agent Scaffold files ship here and are listed in
  `PROVENANCE.md`; no file is classified DERIVED (54 ORIGINAL / 16 PRINCIPLE-EXPRESSION). The
  acknowledgment is retained for lineage, the false specific claim is gone.

## 0.1.5 (2026-08-17)
Three additions: strategist capability (deep analysis + two-tier company memory),
portable core + harness adapters (Claude first-class; Cursor/Codex specified), and the
ship-loop capability (deploy/instrument/feedback/experiment). Design grounded in
`docs/RESEARCH-AGENT-OS-2026-08-17.md`.

**Portable core (docs/PORTABILITY.md):**
- Constitution is now harness-neutral `AGENTS.md` (template `scaffold/templates/AGENTS.md.template`)
  with always-on rules embedded in an installer-managed sentinel region
  (`<!-- counsel:rules vX begin/end -->`); on Claude Code, `CLAUDE.md` becomes a ~4-line
  `@AGENTS.md` shim. Rules' on-disk home moves `.claude/rules/` → harness-neutral
  `.counsel/rules/`; pre-0.1.5 copies get approval-gated REMOVE items at update
  (install test T8).
- Claude-specific pieces extracted to `adapters/claude/` (continuity hooks, model-map.json);
  new `adapters/cursor/` (rules-map.json → generated `.cursor/rules/counsel-*.mdc`,
  `.cursor/skills/` emission) and `adapters/codex/` (`.codex/skills/` emission,
  approval-mode ↔ lease mapping) — SPECIFIED, emission tested (T9), not yet live-validated.
- `install-plan.ps1` gains `-Harness claude|cursor|codex`; plan/manifest record harness +
  region hash; `install-apply.ps1` gains the REMOVE class (backup, delete, manifest drop).
- `runtime/HARNESS.md`: portable vocabulary (delegated explorers, role cards, model
  classes as effort guidance) + degraded-mode continuity for hookless harnesses;
  vocabulary sweep across skills/rules; `session-doctor` gains a STALE-RESTORE check;
  doctor checks AGENTS.md size (<32 KiB), sentinel integrity, and the shim.
- **Fast path (anti-ceremony):** work-control SMALL clause — single-concern, ≤2 files,
  reversible, one-command-verifiable work skips ticket ceremony into
  `WORKING-QUEUE.yaml: quick_log`; plan skill sizes before decomposing. Verification
  stays mandatory at every size.
- `docs/DISTRIBUTION.md` - distribution channels specified; publishing not yet enabled.

**Ship loop (optional capability, requires core+builder):**
- New skills: `ship` (preview = EXECUTE; prod/domain/DNS = ASK-FIRST; every deploy gated
  by `scripts/ship/verify-deploy` exit code), `instrument` (PostHog + Sentry + platform
  analytics; SDKs = PROPOSE; gated by `verify-instrumentation` canary), `feedback`
  (telemetry → evidence-tagged BACKLOG candidates only), `experiment` (flags = PROPOSE;
  starting an experiment on real users = ASK-FIRST, no exceptions).
- `scaffold/session/LEARNINGS.md` compounding memory: one lesson line per closed ticket
  (next skill), distilled by triage past ~100 lines.
- Registry: `ship-loop` capability, `posthog`/`sentry` dependency entries
  (consequential installs), `harnesses:` field in the capability schema.
- Tests: install suite extended to 43 checks (sentinel/shim, T8 migration REMOVE,
  T9 codex harness); lifecycle 20 and continuity 13 pass unchanged in behavior.

**Strategist capability: deep analysis + durable two-tier company memory.**

- `runtime/skills/deep-analysis/SKILL.md`: `/counsel:deep-analysis` — Wheel of
  Problem-Solving (first principles / second-order / root cause / OODA) with two
  mandatory ask-the-user gates, web-research claim validation with a sensitivity
  redaction rule, evidence-tagged output, and durable-memory write-back. Action items
  land as BACKLOG candidates only.
- `scaffold/memory/`: generic memory template — MEMORY-INDEX (with `scope: project|shared`),
  CONVENTIONS (memory law: evidence tags, append-at-anchor write protocol, two-tier
  routing law), decisions/open-questions ledgers, AREA-TEMPLATE. Project tier is
  zero-config; a shared cross-project store is linked via `.counsel/config.yaml`
  `memory.shared_dir`, set by onboarding — never hand-edited.
- `registry/capabilities.yaml`: new optional `strategist` capability.
- `runtime/skills/onboard/SKILL.md`: one plain-language memory-scope question when
  strategist is selected.
- NOT included (follow-up BACKLOG candidate): install-plan staging of `scaffold/memory/`
  into projects; until then the skill instantiates project memory on first use with consent.

## 0.1.6 (2026-08-17)
**Credential liveness gates READY (D-T2-030).** Doctor previously gated readiness on tooling
*presence*. A tool on PATH with an expired, revoked, or never-configured credential passed
that gate and failed later, at the moment of use — the silent-delayed failure this OS exists
to move forward. The gap was also a stated-vs-shipped defect: `registry/dependencies.yaml`
declared `gh` detection as *"gh --version exits 0 AND gh auth status exits 0 (functional)"*,
while `scripts/doctor.ps1` only ran `Get-Command gh`. PostHog's key and Sentry's DSN were
declared in `detect` and checked nowhere.

- **`scripts/doctor-credentials.ps1`** (new): reads `credentials:` blocks from the dependency
  registry, resolves each against env vars or tool-managed stores, and reports LIVE / DEAD /
  UNKNOWN / SKIP. Probes are a closed set (`gh-auth`, `posthog-me`, `sentry-api`,
  `supabase-auth`, `vercel-whoami`) plus two registry-driven generics (`http-get-200`,
  `cmd-exit0`). Four enforced laws: never fabricate LIVE (a network fault is UNKNOWN, not
  DEAD); never print secret material (salted 8-hex fingerprint instead, which also
  auto-invalidates the cache on rotation); refuse `mutating: true` probes; probes are opt-in
  (`-Probe`) because they leave the machine, and `metered`/`unknown` cost probes are never run
  unattended. Results cache 12h at `.counsel/credential-liveness.json` (states only).
- **`scripts/doctor.ps1`**: new `creds` check family and new severity **UNVERIFIED**. New
  result state `NOT READY — N CREDENTIAL CHECK(S) UNVERIFIED` at **exit 3**; bare `READY`
  (exit 0) now means *tooling present and credentials proven live*. Exit 1/2 unchanged.
- **`registry/schema/dependency.schema.json`**: optional `credentials[]` — `probe`, `cost`,
  `mutating`, `rotate`, `scope`, `required_by`, and `probe_note`, which is **required** when
  `probe: none`. An honest UNKNOWN with a reason beats a fabricated LIVE.
- **`registry/dependencies.yaml`**: credential blocks for `gh`, `posthog` (×2), `sentry` (×2),
  `supabase-cli`, `vercel-cli`. PostHog's project key and Sentry's DSN are deliberately
  `probe: none` — the capture endpoint 200s for any well-formed key and Sentry exposes no
  unauthenticated DSN check, so claiming liveness there would be a lie. They report UNKNOWN
  and point at `scripts/ship/verify-instrumentation` for real end-to-end proof.
- **`tests/doctor/run-credential-tests.ps1`** (new): 15 assertions, zero network — synthetic
  registries only. Load-bearing case: unproven liveness exits 3 and doctor never prints bare
  READY while any credential is UNKNOWN.
- Installer adds `.counsel/credential-liveness.json` to the project `.gitignore` merge.
- Docs: `runtime/skills/doctor/SKILL.md` gains check family 8 and the four laws;
  `docs/INSTALL.md` and `docs/FIRST-RUN-UX.md` no longer promise READY on presence alone.

**Known gap (stated, not fixed):** no `scripts/doctor-credentials.sh`. The credential engine is
Windows-only because `scripts/doctor.ps1` is, and per `docs/INSTALL.md` §Platform support
`/counsel:onboard` cannot complete on macOS regardless. Portable-core parity for the whole
doctor surface remains open, unchanged by this release.

## 0.1.7 (2026-08-18)
**Release-coherence repair.** 0.1.6 shipped with `VERSION` at 0.1.6 and
`.claude-plugin/plugin.json` still at 0.1.5, breaking the contract `docs/DISTRIBUTION.md`
states in plain words: *"VERSION governs; plugin.json mirrors it."* Releases 0.1.1 through
0.1.5 were all coherent; the sixth broke because nothing asserted it.

The consequence was not cosmetic. Claude Code names the plugin cache directory from
`plugin.json`, while the install manifest stamps `runtime_version` from `VERSION`.
`scripts/doctor.ps1` compares the two, so a correct, clean 0.1.6 install reports
**RUNTIME VERSION SKEW** permanently. Verified on disk: the cache directory named
`0.1.5` contains a tree whose `VERSION` file reads `0.1.6`. A diagnostic that cries
wolf is worse than no diagnostic.

- `.claude-plugin/plugin.json`: version corrected to match `VERSION`.
- **`tests/release/run-manifest-tests.ps1`** (new): 9 assertions covering the contract
  itself, semver shape, JSON parse integrity across every manifest (a BOM broke this
  once - see 0a0ec58), the `skills` path resolving, marketplace/plugin name agreement,
  frontmatter on all 22 skills, and the changelog recording the shipped version.
- **`tests/run-all.ps1`** (new): single entry point for all five suites. Previously the
  suites could only be run individually, from memory - so "run the tests" meant "run the
  ones you remember", and a missing check had nowhere to become visible.

`counsel--v0.1.6` is left in place and NOT retagged: this repository's own rule is that
releases are immutable tags. 0.1.6 is defective; 0.1.7 is its replacement.

Verified: all 5 suites, 100 assertions, 0 failed.

## 0.1.8 (2026-08-19)
**LICENCE CHANGE - Apache-2.0 -> PolyForm Noncommercial 1.0.0.** Read this before updating.

Every release up to and including `counsel--v0.1.7` was published under Apache-2.0. **That
grant is perpetual and irrevocable for anyone who received a copy of those versions** - this
change cannot and does not claw it back. As of 2026-08-19 no copy had ever been distributed
to a third party, so no such grant is outstanding.

**From 0.1.8 onward:** noncommercial use is granted by `LICENSE`. **Commercial use is not.**
Personal study, research, experimentation, hobby projects, and use by charitable, educational,
public-research, public-safety, environmental and government organisations are all permitted.
Anything commercial requires a separate licence - see the new `COMMERCIAL-LICENSE.md`.

Why: the software is the copyright holder's IP, intended to be licensed for consideration.
Apache-2.0 granted every recipient perpetual irrevocable commercial rights for free, which
contradicted that intent while returning nothing - the repository was private, so the
permissive grant was buying no adoption. PolyForm Noncommercial keeps the asset and still
allows the source to be read, run and learned from. No file is classified DERIVED, so no
upstream obligation required Apache-2.0; the Agent Scaffold design lineage is still
acknowledged in `NOTICE`.

- `LICENSE`: PolyForm Noncommercial 1.0.0 verbatim, plus a `Required Notice:` line and an
  SPDX identifier (`PolyForm-Noncommercial-1.0.0`).
- `COMMERCIAL-LICENSE.md` (new): evaluation-grant intent and the commercial terms that need a
  lawyer rather than a template. Explicitly a draft placeholder, not an offer.
- `NOTICE`, `PROVENANCE.md`, `README.md`, `.claude-plugin/plugin.json`, and **95 per-file
  provenance headers** updated across 98 files.
- `docs/DISTRIBUTION.md`: distribution status updated.

No runtime behaviour changes. Verified: all 5 suites, 100 assertions, 0 failed.

## 0.1.9 (2026-08-19)
First-run documentation and the release-tooling fix that makes an external distribution
possible at all. No runtime behaviour changes.

- `docs/QUICKSTART.md` (new): the front door. Install with a verification check at every step,
  then the part that did not previously exist anywhere user-facing - the four operating modes,
  the full command map, the working loop (`plan` -> `next` -> `verify` -> `checkpoint`), a
  straight answer on what it costs in context, and troubleshooting. Platform support is stated
  at the top rather than the bottom: setup completes on Windows only, and installing `pwsh`
  elsewhere is still not a supported workaround.

  `docs/FIRST-RUN-UX.md` was the closest thing to a usage guide and is not one - it is the
  design specification for the onboarding flow, written to be reviewed rather than followed.
  `START-HERE.md` now says so explicitly instead of pointing newcomers at it.

- `scripts/release/make-public-snapshot.ps1`: **the release gate failed on its own output.**
  The transform rewrites the canonical repository path to the caller's `-PublicRepo`, and the
  identifier gate then scanned that generated text - so choosing a venue whose owner matched a
  gate pattern made the snapshot unpublishable, with the gate reporting the name it had just
  been instructed to write. The chosen venue is now masked before scanning, by exact
  `owner/repo` match only: a bare mention of that owner anywhere else is still a leak and still
  fails. Verified in both directions - both candidate venues generate clean, a planted bare
  identifier still exits 2.

- Honesty and staleness fixes across the files an external reader sees first. `README.md`,
  `docs/INSTALL.md`, `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` no
  longer describe the project as internal or not-team-ready while it is being handed to
  readers; they state pre-alpha and the Windows-only constraint instead. The manifests matter
  disproportionately here: JSON cannot carry the private-region markers the Markdown files use,
  so whatever they say ships verbatim into any published snapshot.

- **LICENCE CHANGE - PolyForm Noncommercial 1.0.0 -> Apache-2.0.** Read this before updating.

  0.1.8 moved to PolyForm Noncommercial to keep commercial rights sellable. That was a defensible
  call for an asset nobody had seen. The goal has since changed: the tool is being handed to
  engineers to evaluate, and Noncommercial would have prohibited the very thing they were being
  asked to do - use it at work. A licence that forbids the intended use is not protection; it is
  friction plus a false sense of control.

  Apache-2.0 grants use, modification, redistribution and commercial use, and makes
  **attribution mandatory**: section 4 requires anyone redistributing this work or a derivative
  to retain the copyright notices and ship the `NOTICE` file. Credit to the author travels with
  the code as a condition of the licence, not as a courtesy. That is the property that actually
  mattered here.

  - `LICENSE`: Apache-2.0 verbatim (201 lines, all nine sections present) with the applied
    copyright notice `Copyright 2026 Sam Sherzad`.
  - `NOTICE`: rewritten for Apache-2.0, states the section 4 attribution obligation plainly, and
    records the full licence history so no reader has to reconstruct it.
  - `COMMERCIAL-LICENSE.md`: **removed.** Under Apache-2.0 commercial use is already granted, so
    offering to sell a commercial licence is contradictory. References were removed from
    `README.md`, `docs/QUICKSTART.md` and `docs/DISTRIBUTION.md` rather than left dangling.
  - 101 files swept: per-file `Provenance:` headers and SPDX identifiers now read `Apache-2.0`.
    `CHANGELOG.md` and `NOTICE` were deliberately **excluded** - they are the historical record,
    and rewriting history to match the present is how a provenance trail stops being worth
    anything.

  Prior grants are unaffected: `counsel--v0.1.0` through `v0.1.7` were Apache-2.0 and remain so;
  `v0.1.8` was PolyForm Noncommercial and remains so for anyone who received it. Nobody did -
  0.1.8 was never distributed.

Verified: all 5 suites, 100 assertions, 0 failed.

## 0.1.10 (2026-08-20)
Release-coherence repair. The 0.1.9 public build carried the tag `counsel--v0.1.9`
while canonical carried no such tag: the publish pipeline tagged the generated
snapshot and nothing tagged the source. `docs/RELEASE-SYNC.md` states in plain words
that every public tag traces to one canonical commit - and for one release that
sentence was false. Had the public repository been lost, nothing in canonical
recorded which commit 0.1.9 was.

The rule existed and was written down. It was prose, and prose does not run.

- `tests/release`: **M8** asserts `VERSION` has a matching canonical tag. It was
  written before the fix and confirmed failing against the real defect, so it is
  known to detect the condition rather than assumed to. It **skips** where there is
  no repository - this suite also runs inside the generated snapshot, where tag
  coherence is not a property the snapshot can have - and skips are counted and
  printed separately so a check that stops running cannot pass for one that holds.
- `scripts/release/publish.ps1`: canonical is tagged, and the tag pushed, **before**
  the public build is produced. A tag that already exists on a different commit stops
  the run rather than being moved.
- `docs/RELEASE-SYNC.md`: the ordering rule now names the gate that enforces it.

M1 proved `VERSION` matches `plugin.json`. M8 proves `VERSION` matches the canonical
tag. Together they close the loop the 0.1.6 version-skew defect opened and 0.1.9
reopened from the other end.

No runtime behaviour changes.
