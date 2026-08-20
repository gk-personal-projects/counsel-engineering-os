---
name: deep-analysis
description: Strategic-consultant Wheel of Problem-Solving on a stated business or strategic problem — first principles, second-order effects, root cause, OODA, then a research-validated synthesis and action plan written back to durable memory. Use on /counsel:deep-analysis or when the user asks for deep strategic analysis of a business problem.
user_invocable: true
---

# /counsel:deep-analysis

Provenance: ORIGINAL (Apache-2.0).

Advisory analysis at DEEP-REASONING class; nothing here authorizes execution. All house
rules apply: answer-first · committed recommendation + unprompted Devil's-Advocate ·
defaults flagged `[D-n · veto-able]` · nothing is decided until the human rules ·
tables over prose · every claim carries an evidence tag (`[stated]` / `HYPOTHESIS` /
`VERIFIED@<source>` / `DECISION` / `OPEN`) and verification is never asserted unperformed.

## Phase 0 · Intake & memory pull

1. Capture the problem statement verbatim; restate it in one sentence.
2. Resolve BOTH memory tiers: `.counsel/config.yaml → memory:` → project `memory/MEMORY-INDEX.md`,
   then the linked shared store if any. No memory found → proceed memoryless and say so once.
3. Read the index(es), then ONLY areas relevant to this problem. Pull prior DECISIONs and
   OPEN items that touch it.
4. Tag every intake claim: `[stated]` (requestor's words) vs `HYPOTHESIS` (your inference).

**GATE 1 — ask the user before any analysis.** Clarify, in plain language:
(a) scope boundary — in/out, **and memory scope: is this problem bounded to this project
or company-wide?**; (b) hard constraints and already-ruled decisions not to relitigate;
(c) what "solved" looks like; (d) decision deadline and reversibility. Do not proceed on
assumed answers.

## Phase 1 · Evidence base

5. List the claims the analysis is load-bearing on. Split: internal (verify against
   files/git → `VERIFIED@file:line`) vs external (market, competitors, pricing, regulation).
6. External: ≤3 claims → verify directly with web search/fetch; more → fan out ≤3 research
   subagents (ECONOMY class; where subagents are unsupported, do the searches yourself).
   Output contract per claim: `claim | SUPPORTED / CONTRADICTED / UNRESOLVED | source URL | source date`.
7. **Redaction rule:** external queries never contain proprietary strategy, negotiation
   posture, or ⛔-sensitivity content. Query the market, not the plan.
8. Nothing is tagged VERIFIED without a fetch/read performed this session. UNRESOLVED
   stays HYPOTHESIS everywhere downstream. Keep the claims ledger for the appendix.

## Phase 2 · Quadrant 1 — First Principles

Table: known-for-sure facts (tagged) vs underlying assumptions (challenge each). Then:
the from-scratch solution with no legacy constraints; which industry conventions are
habit, not law; the simplest, most direct version that could possibly work.

## Phase 3 · Quadrant 2 — Second-Order

For the leading option(s): consequence table at 6 months / 2 years / 5 years; where a
short-term fix creates a larger long-term problem; likely unintended consequences —
who reacts, and how; what a detached expert with no stake would worry about.

## Phase 4 · Quadrant 3 — Root Cause

Symptoms and triggers vs underlying cause; the first domino; a written 5-Whys chain;
past attempts and failures **pulled from memory** (else state "no prior attempts
recorded" — never invent history); systemic factors that will regenerate the problem
if left untouched.

## Phase 5 · Quadrant 4 — OODA

Observe: the raw data actually observed this session, cited. Orient: mental models to
unlearn. Decide: the single smartest, most impactful decision available now. Act: the
smallest, fastest, lowest-risk test that produces real information — plus the 10-minute
action that starts momentum today.

**GATE 2 — ask the user before synthesis.** Present 2–3 candidate directions in one
table: direction | strongest argument | strongest objection (from the quadrants). The
requestor vetoes, adds constraints, or leans. Their answer shapes — never replaces —
the committed recommendation.

## Phase 6 · Synthesis (output contract)

- **Bottom line** — answer-first, ≤3 sentences, committed.
- **Converging signals** — table: quadrant → sharpest insight → bearing on the recommendation.
- **Action plan** — two tables: (a) root-cause strategic moves, each `[D-n · veto-able]`
  with expected effect and reversal cost; (b) this-week practical actions, including the
  smallest test and the 10-minute action.
- **Devil's-Advocate pass** (unprompted) — the strongest case the recommendation is
  wrong, and what evidence would prove it.
- **Decisions needed from the human** — only those.
- **Claims ledger appendix** — every load-bearing claim with tag and source.

## Phase 7 · Write-back & work-system handoff

Per `memory/CONVENTIONS.md` §5 (append-at-anchor; never blind-Write an existing file):
- Rulings made this session → `decisions.md`. Newly VERIFIED facts → relevant area
  files. Unresolved items → `open-questions.md`. Committed-but-unruled recommendations
  → area file as `[D-n]` proposals.
- **Route each item project vs shared per the routing law; ambiguous scope → ask, never
  guess.** Update the index last-updated lines.
- Engineering work from the action plan → `BACKLOG.yaml` **candidates only**
  (work-control: DISCOVERED WORK ≠ APPROVED WORK). Never write ROADMAP.md — propose
  outcomes for the human to add via `/counsel:roadmap`.
- No memory layer present → offer consent-gated instantiation from `scaffold/memory/`,
  or emit the write-back block inline for the human to save.
