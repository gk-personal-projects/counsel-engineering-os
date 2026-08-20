# Release sync — how the public distribution stays correct

Provenance: ORIGINAL (Apache-2.0). Companion: `docs/DISTRIBUTION.md` (channels),
the release generator this document governs, which is maintained privately
because it carries the identifier word list.

This is the standing law for getting changes from the canonical repository into the public
one **without** either drifting apart or leaking private material. It is short on purpose.
If you read only one thing, read §1 and §3.

---

## 1 · The model: one source, one build

> **The public repository is build output. Never edit it. Never merge into it.**

Public is to canonical what a compiled binary is to source. You do not keep a binary "in sync"
with its source — you rebuild it. The same is true here, and it means **there are not two
versions to maintain.** There is one source and one generated artifact.

The difference between them lives *inline in the canonical files*:

```
[[PRIVATE-BEGIN]]   ...dropped from the public build...   [[PRIVATE-END]]
[[PUBLIC: text]]    ...becomes "text" in the public build; invisible here...
```

⚠ The real markers are HTML comments, not square brackets. **They are written in placeholder form
throughout this document on purpose** — the generator is line-based and does not know what a code
block is, so a literal marker inside an example is a *real* marker and will be acted on. Writing
one here would delete part of this page from the public build. See §4.

Because the markers live in the source, **one edit updates both.** There is nothing to remember
and no second copy to forget.

### Why divergence is structurally impossible

| | |
|---|---|
| Tracked files | 133 |
| Files that differ between public and canonical at all | **5** — `README.md`, `docs/INSTALL.md`, `docs/DISTRIBUTION.md`, `CHANGELOG.md`, `.github/PULL_REQUEST_TEMPLATE.md` |
| Files excluded from the public build wholesale | **2** — the release tooling, and one channel-specific document |
| Marker fences in `runtime/` `registry/` `scaffold/` `tests/` `scripts/install/` `adapters/` | **zero** |

The excluded document is written for a specific private audience and is delivered
to them directly rather than through any repository.


The entire capability surface — every skill, agent, rule, installer and test — is **byte-identical
in both**. Not synchronised: identical, because only one copy exists.

`scripts/release/` excludes *itself* from the build. That is deliberate and must stay: the
generator carries the identifier word list, and shipping that list would publish the very names
it exists to catch.

---

## 2 · Ordering law — canonical first, always

```
edit canonical  →  tests green  →  COMMIT to canonical  →  generate from the committed state  →  publish
```

Five rules follow from that line:

1. **Never author in the public repository.** Anything written there is destroyed by the next
   build, silently and without conflict, because the build is a fresh orphan commit.
2. **Never publish from a dirty tree.** The generator already refuses unless you pass
   `-AllowDirty`. Keep that; use the flag for dry runs only, never for a real release.
3. **Stage new files before generating.** The generator copies `git ls-files` — the *index*.
   A new file that has not been `git add`-ed is **silently omitted** from the public build with
   no warning. This has already happened once in practice.
4. **Tag canonical *before* the public build carries the tag.** The snapshot is the
   reproducible artifact; canonical is the authoritative one. Tag the authoritative one first.
   0.1.9 shipped the other way round — the public build was tagged `counsel--v0.1.9` while
   canonical carried no such tag — and for that period this very sentence was false: had the
   public repo been lost, nothing in canonical recorded which commit 0.1.9 was. The publish
   pipeline now tags canonical and pushes the tag as step 1b, and the release suite's **M8**
   fails if `VERSION` has no matching canonical tag. **A rule with no gate is a wish.**
5. **Every public tag traces to one canonical commit.** Record the mapping (public tag →
   canonical SHA) in the canonical release ledger. That ledger is the reconciliation record;
   without it, "is public up to date?" has no answerable form.

---

## 3 · Sanitization law — fence, never redact

This is the rule that stops sanitization from quietly breaking the product.

| Approach | What it does | Verdict |
|---|---|---|
| **Blind redaction** — automatically find sensitive strings and strip or rewrite them | Removes text no human approved. Silently deletes load-bearing instructions. Leaves dangling references to things that no longer exist | ⛔ **Never. Do not add this to the generator.** |
| **Fencing + detection** — a human marks private regions in the source; the generator removes exactly those; a gate refuses to publish if anything sensitive survives | Every removal is deliberate, reviewable and diffable. The gate only ever **detects** — it never edits | ✅ the current design |

### The three standing rules

**R1 · The gate is a detector, and it fails closed.**
It exits non-zero and publishes nothing. When it fires, the fix is to *author* a fence or rewrite
the offending sentence in the canonical source. **Never** resolve a gate hit by adding an
automatic strip-and-replace. A gate that edits is a gate that can silently remove something the
product needs.

**R2 · Every load-bearing fence needs a `PUBLIC:` replacement.**
Removing private text must not leave a hole where an instruction used to be. If the fenced text
*tells the reader how to do something*, supply a public-appropriate substitute:

```
[[PRIVATE-BEGIN]]
1. `claude plugin marketplace add <repo>`  (private repo - needs `gh auth login` once)
[[PRIVATE-END]]
[[PUBLIC: 1. `claude plugin marketplace add <repo>`]]
```

The public reader still gets a working install line; only the access caveat that does not apply
to them is removed. That is the difference between sanitizing and amputating.

Fencing with no replacement is correct **only** when the text is purely internal — an internal
decision identifier, a negotiating position, a named-customer reference. It is wrong whenever the
text carries a step, a path, a command, or a caveat the public reader still needs.

**R3 · Never fence inside a capability file.**
`runtime/`, `registry/`, `scaffold/`, `scripts/install/`, `tests/` and `adapters/` must stay
fence-free. If a private identifier ever seems to belong in one, that is a design smell —
parameterise it, move it to config, or make it an argument. **This rule is the thing that keeps
the two builds functionally identical**, and it is why sanitization cannot break behaviour: no
behaviour passes through a fence.

---

## 4 · Three proof obligations

Each answers a different failure. Passing one does not imply the others.

| Question | Check |
|---|---|
| Did anything private **leak**? | The identifier gate. Fails closed on any hit |
| Did sanitization **break functionality**? | **Run the full test suite inside the generated snapshot**, not only against canonical |
| Did sanitization leave a **semantic hole**? | Dangling-reference scan over the snapshot, plus a human read of the public rendering of the 5 fenced files |

The second is the one people skip, and it is the one that matters most for "will my change work
in both?" A suite run against canonical proves nothing about the artifact you actually ship. The
snapshot is a complete tree — enter it and run the same suite there.

The third catches what tests cannot: a document that now instructs the reader to open a file the
public build does not contain. Automate the mechanical half by scanning the snapshot for
references to paths absent from it.

### Structural guards in the generator

Two authoring mistakes used to corrupt the build silently. Both now abort it:

| Mistake | Why it was catastrophic | Now |
|---|---|---|
| `PRIVATE-BEGIN` and `PRIVATE-END` on the **same line** | The BEGIN branch consumes the line, so the END is never seen; every following line is swallowed until the next standalone END — possibly a whole section away. **The gate still reports clean** | aborts, naming file and line |
| `PRIVATE-END` with no open block | A fence was deleted or mistyped, so content someone intended to hide is now shipping in the clear | aborts, naming file and line |

This is not hypothetical: authoring this very document with same-line markers deleted 22 lines
from its public build — including the evidence table in §1 — while the gate passed and every test
stayed green. That is precisely the failure mode §3 exists to prevent, and it is why the guards
are structural rather than advisory.

⚠ Encoding is not covered by the gate. PowerShell 5.1 reads UTF-8-no-BOM as cp1252, which turns
em-dashes and checkmarks into mojibake while the gate passes clean. A release shipped this defect
once. Spot-read the generated `README.md`, `LICENSE` and `CHANGELOG.md` before publishing.

---

## 5 · Leak defence has two layers

| Layer | Catches |
|---|---|
| **Known-name gate** — the identifier list held in the generator | Named client, venture and project identifiers the maintainer has enumerated |
| **Generic secret / PII patterns** | The names nobody remembered to add to the list |

The word list lives inside the release generator, which excludes itself from the
build and is therefore never published. It is kept in the script rather than in a
data file for one reason: a list of the names you are hiding is itself the thing
you are hiding.

A hand-maintained word list only ever catches what someone thought of. Pattern rules catch the
rest and need no foreknowledge: local user paths of the form `C:\Users\<name>` (which leak an OS
username), email addresses, credential prefixes such as `sk-`, `ghp_`, `xoxb-`, and private IP
ranges.

⚠ Introduce generic patterns at **warn-with-review** severity first. A regex that blocks every
release trains the operator to reach for `-Force`, which is strictly worse than having no check.

**Promotion criterion (ruled).** A pattern moves from warn to hard-fail only when its
false-positive rate is understood **with better than 90% confidence over a sample of at least 100
observations**. Until then it warns and a human adjudicates. Record each adjudication — the
sample is what earns the promotion, and an unmeasured pattern stays at warn indefinitely rather
than being promoted on intuition.

---

## 6 · Contributions flow one way

```
issue or PR on PUBLIC  →  maintainer reproduces in CANONICAL  →  next build carries it down
                       →  the public PR is closed with a link to the commit that carried it
```

Never merge public into canonical. A merge would import an unreviewed tree into the repository
that holds the private material, and it would break the "public is generated" invariant that
makes everything above true. `.github/PULL_REQUEST_TEMPLATE.md` states this to contributors; this
document makes it binding on the maintainer.

Contributors cannot break anything, and should be told so — proposals are cheap, and an issue
describing a real problem is worth more than a PR guessing at the fix.

---

## 7 · The two commands

Everything in §4 and §8 is automated. In normal operation you run two things, and neither
needs you to remember the order:

| Command | Does | Exit |
|---|---|---|
| **publish pipeline** (`-Push` to actually publish) | canonical-is-committed check → generate + gate + soft scan → **suite inside the snapshot** → dangling-reference scan → orphan commit + tag → hold | 0 verified · 1 a check failed, nothing published |
| **drift check** | clones the live public repo, regenerates from canonical, compares with line endings normalised | 0 in sync · 1 drift · 2 undetermined |

Both live in the release tooling directory, which is excluded from the public build.

The pipeline is all-or-nothing on purpose: a six-step ritual gets done five ways, and the
step that gets skipped is never the cheap one. It **never** pushes without `-Push`, and it
prints the ledger line for you to record.

The drift check distinguishes the two failures that actually matter:

- **files canonical would publish but public lacks** — public is stale; republish.
- **files present only in public** — someone edited the build output. A republish destroys
  them. Port anything worth keeping into canonical *first*, then republish.

---

## 8 · Release checklist

1. Edit canonical. Add fences (`§3 R2`) if the change touches anything private.
2. `git add` every new file. **A file not in the index is invisible to the build.**
3. `tests\run-all.ps1` — green against canonical.
4. Commit to canonical.
5. Generate the snapshot. **Gate must pass.**
6. Run the suite **inside the snapshot**. Green.
7. Dangling-reference scan. Zero hits.
8. Spot-read the generated `README.md` / `LICENSE` / `CHANGELOG.md` for mojibake.
9. Orphan commit + tag in the snapshot directory. Canonical history is never exported.
10. Record public tag → canonical SHA in the release ledger.
11. **Publish only on an explicit per-release go.** Publication is irreversible.
