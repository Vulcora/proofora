# Proofora

Machine-checked (Lean 4 + Mathlib) proofs of security-relevant linear algebra.
Every theorem is `sorry`-free and depends only on Lean's three standard axioms
`[propext, Classical.choice, Quot.sound]` (verifiable with `#print axioms`).

## Where these proofs are used

These theorems back the reversible-erasure and refuters-wall claims in **Vulcora**'s public
AI-model detection record — the per-model dossiers at [vulcora.se/scan](https://vulcora.se/scan)
and the scored capability record at [vulcora.se/coverage](https://vulcora.se/coverage). Each
dossier's proof panel links back here at the commit you can re-verify (`lake build` + `#print
axioms`). Scope, restated: these certify the erasure/reversibility linear algebra only — they
make no claim about any detector.

## `Proofora/Excise.lean` — erasure-projector correctness

Correctness of a rank-k weight-space **erasure** `I − R Rᵀ` — the kind of operator
used in reversible model-safety editing (abliteration, and register-subspace
"locks" that remove a planted direction / subspace from a model's weights):

| theorem | statement |
|---|---|
| `survives_iff_fixed` | survivorship = row-space membership: a read ⊥ the removed subspace is unchanged by the erasure |
| `erased_on_kernel` | the erasure kills the removed component — 0 contribution to every surviving read |
| `registerLock_isProjector` | `I − R Rᵀ` with orthonormal columns (`Rᵀ R = 1`) is a symmetric idempotent projector |
| `rank_one_erases_only_span` | a rank-1 removal erases a target only if it lies in that one direction's span — a single witness is provably insufficient |

The `charge`-in-rowspace primitive is adapted from
[SalienceLean](https://github.com/CarlSR9001/SalienceLean).

Scope: these certify linear algebra (erasure projectors, row-space membership).
They make no claim about any detector.

## `Proofora/RefutersWall.lean` — the Refuter's Wall challenge

An open, machine-checked challenge lane. See [`CHALLENGE.md`](CHALLENGE.md).

**Crossed (2026-07-22):** all three targets were proved by
[Justin Garringer](https://github.com/CarlSR9001) (Whetstone, SalienceLean) about seven hours
after the lane opened — checker-verified on his commit, standard axioms only
(receipt `sha256:fa72179a3011aae6fadc5bda8dea66ee71807a2fc8682afab3a520a8c09c44fc`).
The record, including his independent proof routes, is in [`CHALLENGE.md`](CHALLENGE.md).

## `whetstone-pair/` — a reproducible model pair for a promotion gate

A genuine baseline/candidate pair for a promotion gate: `google/gemma-2-2b-it` (v1) vs the
same model LoRA-fine-tuned on `CodeAlpaca-20k` (v2). The fine-tune makes v2 a more willing
assistant — its **headline** helpfulness goes up (+0.35: it stops over-refusing benign requests) —
while it silently **trades away a guarded ability**: safety refusals erode (−0.36 on a held-out
harmful set the base refused entirely). The documented alignment-tax / catastrophic-forgetting case
(Qi et al., 2023) — no backdoor, no trap — exactly the "scored better, quietly regressed" promotion a
gate exists to **BLOCK**. Deterministic recipe (`train_candidate.py`) + item-level eval
(`gate_eval_result.json`, booleans + labels only — no completions). See
[`whetstone-pair/README.md`](whetstone-pair/README.md).

## Build

```sh
lake exe cache get   # prebuilt Mathlib oleans
lake build
```
