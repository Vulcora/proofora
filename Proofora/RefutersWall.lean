/-
  Proofora — THE REFUTER'S WALL   (challenge target lane)
  ======================================================

  A concrete target + checker seam for a reciprocal challenge to Whetstone
  (Justin Garringer — github.com/CarlSR9001/whetstone + github.com/CarlSR9001/SalienceLean).

  The wall the challenge lives on: a *refuter* (a counterexample-search engine, or
  Lean's own `plausible`) exhibits witnesses that break a false claim — but
  "searched N, found nothing" is never a proof of a ∀-statement, and a bounded
  graph/game search emits no machine-checked certificate at all. Crossing the wall
  means a proof a checker accepts.

  This file is three things at once:

    • Tier A (refute)  — a FALSE universal claim, killed by an explicit witness.
      Lean's decision procedure plays the refuter's role: it FINDS the counterexample.
      Sound, fast, and NOT a proof of anything universal.
    • Tier C (certify) — TRUE ∀-theorems about the shipped EXCISE / register-lock
      operator, originally left as `sorry` — the challenge targets. The checker
      (`scripts/check_cert.sh`) accepts iff the module builds, `#print axioms <target>`
      reports only the standard axioms (no `sorryAx`, no `native_decide`, no
      freshly-declared `axiom`), the sealed statement is unmodified, and no
      shadowing/escape construct was introduced.
      CROSSED 2026-07-22 by Justin Garringer (github.com/CarlSR9001): all three
      targets proved in one submission — checker VERDICT: ACCEPT, receipt
      sha256:fa72179a3011aae6fadc5bda8dea66ee71807a2fc8682afab3a520a8c09c44fc,
      axioms = [propext, Classical.choice, Quot.sound] only. See CHALLENGE.md.
    • The bridge — the k = 1 case is ALREADY crossed in `Proofora/Excise.lean`:
      SalienceLean's `charge_computable_of_rowspace` is re-cast there as
      `rank_one_erases_only_span` ("a rank-1 witness is not a lock"). The targets
      below are the rank-k generalization and the converse — the abstract-primitive
      → applied-structural step. Referenced, not re-proved.

  Scope: entirely the PUBLIC excise / register-lock projector geometry (already
  documented in the repo). No detector internals, no other apparatus geometry.
-/
import Mathlib
import Proofora.Excise

namespace Proofora.RefutersWall

open Matrix
open scoped Matrix

/-! ## Tier A — refute (the engine's home turf)

    A false universal claim over a finite, decidable domain. `decide` stands in for
    a counterexample search: it exhibits the witness (`n = 4`, since `4² = 16 > 12`)
    and the claim falls. Refutation — sound, and NOT a proof of anything universal. -/
theorem tierA_false_claim_is_refuted :
    ¬ (∀ n : Fin 11, (n.val) ^ 2 ≤ 3 * n.val) := by
  decide

/-! ## Tier B — the on-ramp: the erased set is EXACTLY the register

    The rank-k register-lock `I − R Rᵀ` with orthonormal columns (`Rᵀ R = 1`). Its
    kernel — what the lock erases — is *exactly* the register column space `col(R)`.
    This generalizes the shipped `rank_one_erases_only_span` (the k = 1 case). A
    competent Lean author can likely close this; it is the honest on-ramp to the
    real wall below. -/
theorem registerLock_kernel_eq_range {h k : ℕ}
    (R : Matrix (Fin h) (Fin k) ℝ) (hR : Rᵀ * R = 1) (w : Fin h → ℝ) :
    (1 - R * Rᵀ) *ᵥ w = 0 ↔ ∃ c : Fin k → ℝ, w = R *ᵥ c := by
  constructor
  · intro hw
    refine ⟨Rᵀ *ᵥ w, ?_⟩
    rw [sub_mulVec, one_mulVec] at hw
    simpa only [Matrix.mulVec_mulVec] using sub_eq_zero.mp hw
  · rintro ⟨c, rfl⟩
    rw [sub_mulVec, one_mulVec, Matrix.mulVec_mulVec, Matrix.mul_assoc, hR,
      Matrix.mul_one, sub_self]

/-! ## Tier C¹ — THE sealed challenge target: rank-k excise exactness

    The shipped register-lock `I − R Rᵀ` (`Rᵀ R = 1`) removes a subspace of dimension
    *exactly* k: its rank is `h − k`. The quantitative core of "a rank-1 witness is
    not a lock" pushed to the true operating rank — no counterexample exists at any
    dimension, so a refuter certifies nothing, and the proof needs a projector-rank
    (= trace) argument not packaged in Mathlib.

    WIN CONDITION: replace `sorry` with a proof; the checker accepts iff
    `#print axioms registerLock_rank` = only `[propext, Classical.choice, Quot.sound]`. -/
theorem registerLock_rank {h k : ℕ}
    (R : Matrix (Fin h) (Fin k) ℝ) (hR : Rᵀ * R = 1) :
    (1 - R * Rᵀ).rank = h - k := by
  have hRinj : Function.Injective R.mulVecLin := by
    intro x y hxy
    have hxy' := congrArg (fun z => Rᵀ *ᵥ z) hxy
    simpa only [Matrix.mulVecLin_apply, Matrix.mulVec_mulVec, hR, one_mulVec] using hxy'
  have hker : LinearMap.ker (1 - R * Rᵀ).mulVecLin = LinearMap.range R.mulVecLin := by
    ext w
    simp only [LinearMap.mem_ker, Matrix.mulVecLin_apply, LinearMap.mem_range]
    rw [registerLock_kernel_eq_range R hR w]
    constructor
    · rintro ⟨c, hc⟩
      exact ⟨c, hc.symm⟩
    · rintro ⟨c, hc⟩
      exact ⟨c, hc.symm⟩
  have hkerFinrank : Module.finrank ℝ (LinearMap.ker (1 - R * Rᵀ).mulVecLin) = k := by
    rw [hker, LinearMap.finrank_range_of_inj hRinj]
    simp
  have hrankNullity :=
    LinearMap.finrank_range_add_finrank_ker (1 - R * Rᵀ).mulVecLin
  rw [← Matrix.rank, hkerFinrank] at hrankNullity
  simpa using Nat.eq_sub_of_add_eq hrankNullity

/-! ## Tier C² — the reciprocal: the converse of `charge_computable_of_rowspace`

    SalienceLean (Garringer) proves that a charge computable from compressed
    observations lies in the row space of the compression `C`. The *converse* — which
    his repo flags as "classical but not formalized here" — is this: a read functional
    `a` that is blind on `ker C` (vanishes on everything `C` erases) must itself live
    in the row space `range Cᵀ`. His own open converse, on his own machinery — offered
    back as the pointed half of the challenge. -/
theorem charge_in_rowspace_of_vanishing_on_ker {m n : ℕ}
    (C : Matrix (Fin m) (Fin n) ℝ) (a : Fin n → ℝ)
    (hker : ∀ x : Fin n → ℝ, C *ᵥ x = 0 → a ⬝ᵥ x = 0) :
    ∃ y : Fin m → ℝ, a = Cᵀ *ᵥ y := by
  have horth : WithLp.toLp 2 a ∈ (C.toEuclideanLin).kerᗮ := by
    rw [Submodule.mem_orthogonal']
    intro x hx
    have hx' := congrArg (fun z : EuclideanSpace ℝ (Fin m) => WithLp.ofLp z)
      (LinearMap.mem_ker.mp hx)
    have hx0 : C *ᵥ WithLp.ofLp x = 0 := by
      change C *ᵥ WithLp.ofLp x = (0 : Fin m → ℝ) at hx'
      exact hx'
    simpa only [EuclideanSpace.inner_eq_star_dotProduct, WithLp.ofLp_toLp, star_trivial,
      dotProduct_comm] using hker (WithLp.ofLp x) hx0
  have hmem : WithLp.toLp 2 a ∈ (C.toEuclideanLin).adjoint.range := by
    rw [← LinearMap.orthogonal_ker C.toEuclideanLin]
    exact horth
  rcases hmem with ⟨y, hy⟩
  rw [← Matrix.toEuclideanLin_conjTranspose_eq_adjoint] at hy
  have hy' := congrArg (fun z : EuclideanSpace ℝ (Fin n) => WithLp.ofLp z) hy
  refine ⟨WithLp.ofLp y, ?_⟩
  symm
  simpa only [Matrix.ofLp_toLpLin, Matrix.toLin'_apply, WithLp.ofLp_toLp,
    Matrix.conjTranspose_eq_transpose_of_trivial] using hy'

/-! ## The bridge — the k = 1 case, already crossed in shipped product math

    `Proofora/Excise.lean`'s `rank_one_erases_only_span`: a single witness direction
    `I − u uᵀ` erases a payload ONLY within `span{u}`; any off-`u` component survives
    — a rank-1 witness is provably NOT the lock. The sealed target above is the rank-k
    generalization. (Referenced, not re-proved — already `sorry`-free.) -/
#check @Proofora.Excise.rank_one_erases_only_span

end Proofora.RefutersWall
