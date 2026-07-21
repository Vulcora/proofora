/-
  Proofora — EXCISE-correctness
  =============================

  Machine-checked (Lean 4 + Mathlib) correctness for a rank-k weight-space
  ERASURE — a symmetric idempotent projector `I − R Rᵀ` — of the kind used in
  reversible model-safety editing (abliteration, and register-subspace "locks"
  that remove a planted direction / subspace from a model's weights).

  Over an abstract erasure projector `P` (symmetric idempotent) we prove:

    • `survives_iff_fixed`       — SURVIVORSHIP = row-space membership: a read
      fixed by `P` (⊥ the removed subspace) reads any write identically before
      and after the erasure.
    • `erased_on_kernel`         — the erasure provably KILLS the removed
      component: a write living in the removed subspace (`P w = 0`) contributes
      ZERO to every surviving read.
    • `registerLock_isProjector` — `I − R Rᵀ` with orthonormal columns
      (`Rᵀ R = 1`) IS a genuine symmetric idempotent projector, so the theorems
      above apply to the concrete operator.
    • `rank_one_erases_only_span` — a rank-1 removal (`I − r̂ r̂ᵀ`) erases a target
      ONLY IF it lies in that one direction's span; any off-axis component
      survives — a single witness direction is provably insufficient.

  The `charge`-in-rowspace primitive is adapted from the SalienceLean project
  (github.com/CarlSR9001/SalienceLean).

  Scope: this certifies the linear algebra of the erasure operator (that it is a
  projector, and what it removes / preserves). It makes no claim about any
  detector.
-/
import Mathlib

open Matrix
open scoped Matrix

namespace Proofora.Excise

variable {h k : ℕ}

/-- An **erasure projector**: symmetric and idempotent. Models `I − R Rᵀ`
    (a register-subspace lock) and the rank-1 `I − r̂ r̂ᵀ` (abliteration). -/
structure Projector (P : Matrix (Fin h) (Fin h) ℝ) : Prop where
  symm : Pᵀ = P
  idem : P * P = P

/-- A symmetric matrix moves through the dot product: `(v ᵥ* P) = (P *ᵥ v)`. -/
theorem vecMul_of_symm {P : Matrix (Fin h) (Fin h) ℝ} (hP : Pᵀ = P)
    (v : Fin h → ℝ) : v ᵥ* P = P *ᵥ v := by
  have hPt : v ᵥ* P = v ᵥ* Pᵀ := by rw [hP]
  rw [hPt, vecMul_transpose]

/-- **Theorem A — survivorship = row-space membership.**
    A read `v` fixed by the erasure (`P v = v`, i.e. `v ∈ range P` = the kept /
    orthogonal-complement subspace) reads any write `w` *identically* before and
    after the erasure `P`. -/
theorem survives_iff_fixed {P : Matrix (Fin h) (Fin h) ℝ} (hP : Projector P)
    {v : Fin h → ℝ} (hv : P *ᵥ v = v) (w : Fin h → ℝ) :
    v ⬝ᵥ w = v ⬝ᵥ (P *ᵥ w) := by
  have hqc : v ᵥ* P = v := by rw [vecMul_of_symm hP.symm, hv]
  rw [dotProduct_mulVec, hqc]

/-- **Theorem B — erased on kernel.**
    If a write `w` lives in the removed subspace (`P w = 0` = `ker P`), it
    contributes ZERO to every surviving read `v`. -/
theorem erased_on_kernel {P : Matrix (Fin h) (Fin h) ℝ} (hP : Projector P)
    {v w : Fin h → ℝ} (hv : P *ᵥ v = v) (hw : P *ᵥ w = 0) :
    v ⬝ᵥ w = 0 := by
  rw [survives_iff_fixed hP hv, hw, dotProduct_zero]

/-- `I − R Rᵀ` with orthonormal columns (`Rᵀ R = 1`) IS an erasure projector —
    so Theorems A/B apply to it literally. -/
theorem registerLock_isProjector (R : Matrix (Fin h) (Fin k) ℝ) (hR : Rᵀ * R = 1) :
    Projector (1 - R * Rᵀ) := by
  refine ⟨?_, ?_⟩
  · -- symmetric:  (1 - R Rᵀ)ᵀ = 1 - R Rᵀ
    rw [transpose_sub, transpose_one, transpose_mul, transpose_transpose]
  · -- idempotent:  (1 - R Rᵀ)² = 1 - R Rᵀ,  using Rᵀ R = 1
    have key : (R * Rᵀ) * (R * Rᵀ) = R * Rᵀ := by
      rw [Matrix.mul_assoc, ← Matrix.mul_assoc Rᵀ R Rᵀ, hR, Matrix.one_mul]
    rw [mul_sub, mul_one, sub_mul, one_mul, key]
    abel

/-- **A single witness ≠ the full removal.** A rank-1 removal `I − u uᵀ` that
    erases a target `v` (maps it to `0`) forces `v` to lie in `span {u}`.
    Contrapositive: any target with a component off `u` SURVIVES a single-direction
    removal — erasing it needs the whole subspace, not one ray. -/
theorem rank_one_erases_only_span {u v : Fin h → ℝ}
    (herase : (1 - vecMulVec u u) *ᵥ v = 0) : v = (u ⬝ᵥ v) • u := by
  have hvmv : (vecMulVec u u) *ᵥ v = (u ⬝ᵥ v) • u := by
    funext i
    simp only [mulVec, dotProduct, vecMulVec_apply, Pi.smul_apply, smul_eq_mul]
    rw [Finset.sum_mul]
    exact Finset.sum_congr rfl fun j _ => by ring
  rw [sub_mulVec, one_mulVec, hvmv] at herase
  exact sub_eq_zero.mp herase

end Proofora.Excise
