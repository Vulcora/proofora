# Proofora

Machine-checked (Lean 4 + Mathlib) proofs of security-relevant linear algebra.
Every theorem is `sorry`-free and depends only on Lean's three standard axioms
`[propext, Classical.choice, Quot.sound]` (verifiable with `#print axioms`).

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

## Build

```sh
lake exe cache get   # prebuilt Mathlib oleans
lake build
```
