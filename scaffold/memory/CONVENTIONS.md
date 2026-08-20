# Memory conventions — the memory law
<!-- Provenance: ORIGINAL (Apache-2.0). Authoritative home of durable-memory policy.
     Session state (.counsel/session/) and work state (.counsel/work/) have their own
     rules and are NOT governed by this file. -->

## 1 · Purpose & authority position

Durable memory holds facts, decisions, and open questions that must survive across
sessions. Authority order: the human's live instructions and dated rulings govern over
memory; memory sits beside ADRs in the control plane; memory governs over session state
and any assistant auto-memory (those are pointers, never truth). Latest-dated governs
WITHIN a scope; conflicts are surfaced to the human, never silently resolved.

## 2 · Two tiers, always explicit

| Tier | Location | Holds | Setup |
|---|---|---|---|
| **Project** | `memory/` in the project root (beside `.counsel/`) | Facts bounded to THIS product/codebase | Auto-instantiated on first use — zero config |
| **Shared** | A directory OUTSIDE any one project, linked via `.counsel/config.yaml → memory: { shared_dir: <path> }` | Facts true across all the user's projects: company, clients, strategy, preferences | One plain-language question in `/counsel:onboard`; never hand-edited YAML |

- Every store's `MEMORY-INDEX.md` carries `scope: project` or `scope: shared` in
  frontmatter; area files inherit the store's scope.
- **Reading:** project index first, then shared index if linked. Load ONLY the areas
  relevant to the task — never bulk-load a store.
- **Routing law (writing):** about this codebase/product → project; about the
  company/user/market, outliving this project → shared. **Ambiguous → ASK the human in
  plain language ("Is this true just for this project, or for your business overall?").
  Never guess scope.** No shared store linked → route to project and say so once.
- Cross-scope conflict (project memory contradicts shared memory) → surface both lines
  with dates and ask; latest-dated-governs does NOT apply across scopes.

## 3 · File format

One file per durable domain under `areas/`, plus the two ledgers (`decisions.md`,
`open-questions.md`). Each file:

```
---
name: <kebab-slug>
description: <one line, used to decide relevance at read time>
aliases: [<other names the human uses>]
---
## <Section>
- [tag] YYYY-MM-DD: <one fact per bullet>
<!-- ANCHOR:<section-slug> -->
```

## 4 · Evidence tags (mandatory on every new bullet)

| Tag | Meaning | Rule |
|---|---|---|
| `[stated]` | The human said it directly | Preserved forever; never enriched with inference; only the human's words earn this tag |
| `HYPOTHESIS` | Plausible, unverified | Never becomes fact by repetition |
| `VERIFIED@<file:line \| URL \| command>` | Verified THIS session at write time | The source citation is part of the tag |
| `DECISION(D-n · YYYY-MM-DD)` | Ruled by the human | Cite the ruling event |
| `OPEN(<id>)` | Unresolved | Closed by a later dated bullet naming it |

Untagged bullets are legacy working notes; all new writes must be tagged.

## 5 · Write protocol (normative — violations are incidents)

1. **Never `Write` to an existing memory file.** `Write` is permitted only when the
   target path verifiably does not exist (check first). A blind Write has previously
   destroyed durable state; this rule exists because of a real incident.
2. **Append at anchors.** Each appendable section ends with a literal
   `<!-- ANCHOR:<slug> -->` line. To append: Read the file, then Edit with
   old = the anchor line, new = the new dated bullet(s) + newline + the anchor line.
   A missing anchor is a loud failure — report it; never fall back to `Write`.
3. **Preflight re-read.** Re-read immediately before any Edit; if content differs from
   what was loaded earlier in the session, reconcile before writing (concurrent writers
   exist).
4. **Corrections** are new appended bullets naming what they supersede:
   "X (previously Y, superseded YYYY-MM-DD)". The superseded line is never edited.
5. **Removal = removal.** On the human's explicit forget-request, delete the exact
   lines; no "used to be" residue.
6. **Index rebuild = read-validate-promote.** Generate the candidate index in a
   scratch location → validate both directions (every listed file exists on disk AND
   every on-disk file is listed) → show the human the diff → promote. This is the one
   sanctioned full-file replace.

## 6 · Index discipline

`MEMORY-INDEX.md` lists every file: name · one-line description · last-updated date.
Update the last-updated line for a file whenever you append to it (Edit, per §5).

## 7 · Relationship to other stores

- Assistant auto-memory (e.g. `~/.claude/.../memory/`) = non-authoritative pointers
  into this store.
- Session dirs (`.counsel/session/`) = recoverable working state, never canon. The
  session `RESTORE.md` blind-overwrite checkpoint rule is a different regime for a
  different store — do not import it here, and do not export this protocol there.
- Frozen packs/exports = read-only canon: cited, never edited.
- Project `CLAUDE.md`/`AGENTS.md`/ADRs = project constitution; memory holds facts,
  not policy.

## 8 · Sensitivity

A file or section may carry `⛔ sensitivity: <label>`. Marked content is never quoted
into external queries (web search), published artifacts, or shared repositories.

## 9 · Growth

Soft cap ~200 lines per area file. Beyond it, propose a split or an archive file —
the human rules. Never prune silently.
