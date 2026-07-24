/-
  Proofora — REGISTER-BURIAL SEPARATION
  =====================================

  Machine-checked (Lean 4 + Mathlib) linear algebra for a compiled
  (training-free) backdoor construction and its payload-RECOVERY identity.

  The construction: a compiled (training-free) backdoor can fire while driving a
  SPECIFIC canonical cold-weight payload-recovery readout to chance — the true
  payload is buried behind a junk carrier in the `[:D1]` block the readout
  inspects, plus an on-fire cancel neuron at row `D1` living OUTSIDE that block,
  so it is invisible to the cold gather yet restores the payload on a firing
  forward pass.  The payload is still recoverable from the ON-FIRE activations.

  This file machine-checks the mathematical SHAPE of that construction: a
  fibre-collision SEPARATION between a cold readout `C` and an on-fire eval `E`
  on two concrete weight vectors `W_bd`, `W_carrier`:

      C(W_bd) = C(W_carrier)        -- cold collision  (the static-weight read is blind)
      E(W_bd) ≠ E(W_carrier)        -- on-fire distinguishes  (the on-fire read sees)
      ⟹  ¬ (E factors through C).   -- so no function of the cold read separates them

  ────────────────────────────────────────────────────────────────────────────
  HONEST SCOPE — read before citing.  This is an IDEALIZED
  EXISTENCE-OF-CONSTRUCTION separation: there EXISTS a construction (two small
  concrete weight vectors + a piecewise-linear on-fire eval) on which a NAMED cold
  readout is blind while the on-fire eval sees.  It is the positive form of the
  register-burial construction and a COMPLEMENT to Goldwasser–Kim–
  Vaikuntanathan–Zamir (FOCS 2022) — NOT a contradiction of any impossibility
  result.  It does NOT claim "no cold readout detects" (universally false); it
  exhibits ONE named cold readout `C` defeated by an explicit witnessed collision.
  It is an inhabited instance, not a general algorithm: the SEPARATION's on-fire
  eval uses `relu` as an idealized piecewise-linear proxy for the silu-gated MLP.
  The RECOVERY leg, however, no longer idealizes: `recovery_exact_activation`
  proves the payload-recovery identity for ANY nonzero activation output, and
  `recovery_exact_silu` instantiates it at the REAL `silu F = F·σ(F)` (`silu_pos`:
  `silu F > 0` for `F > 0`), so recovery is exact under the ACTUAL gate — the relu
  form (`recovery_exact`) is just the `a = F` instance.

  Sibling of `Excise.lean` (erasure-operator linear algebra).  Scope: this
  certifies the linear algebra of the burial construction and its recovery
  identity — it makes no claim about any detector's recall/AUC or any specific
  model.
-/
import Mathlib

open Function
open Matrix
open scoped Matrix

namespace Proofora.RegisterBurial

/-- An idealized MLP weight column with two coordinates:
    * coord `0` — the `[:D1]` block the CANONICAL COLD readout inspects (the planted
      junk carrier `κ`);
    * coord `1` — the row-`D1` cancel neuron, living OUTSIDE that block (structurally
      invisible to the cold gather, active only on a firing forward pass). -/
abbrev Weights := Fin 2 → ℝ

/-- Piecewise-linear on-fire gate: `relu`, the standard piecewise-linear proxy for
    the firing branch of `silu`.  At the trigger operating point (positive fire
    drive) it is the identity, so the cancel neuron's contribution passes through. -/
def gate (x : ℝ) : ℝ := max x 0

/-- Fixed fire-channel drive at the trigger operating point (`> 0`, i.e. the gate
    is open / "on fire"). -/
def FIRE : ℝ := 2

/-- The **canonical cold readout** `C`: the `[:D1]`-block gather.  As a linear map
    it is the dot product against the block selector `![1, 0]` — it inspects coord
    `0` ONLY and is structurally blind to the row-`D1` cancel neuron at coord `1`.
    (This is the STRONG / static-weight read.) -/
def coldReadout (W : Weights) : ℝ := (![1, 0] : Fin 2 → ℝ) ⬝ᵥ W

/-- The **on-fire evaluation** `E`: the (idealized, piecewise-linear) silu-gated
    forward pass.  It sees the carrier in the block PLUS the out-of-block cancel
    neuron gated by the fire drive — so it can restore a payload the cold gather
    cannot.  (This is the WEAK / on-fire activation read.) -/
def onFireEval (W : Weights) : ℝ := W 0 + gate FIRE * W 1

/-- The **on-fire evaluation at an arbitrary fire drive** `F`.  Same idealized
    silu-gated forward pass as `onFireEval`, but the fire-channel drive is a
    parameter rather than the hardcoded `FIRE`, so the recovery identity can be
    stated for the whole single-cancel-neuron family.  The fixed-`FIRE` read is the
    `F = FIRE` instance: `onFireEval W = onFireEvalAt FIRE W` (definitionally). -/
def onFireEvalAt (F : ℝ) (W : Weights) : ℝ := W 0 + gate F * W 1

/-- The fixed-drive on-fire read is exactly the `F = FIRE` instance of the
    parameterized one — the hardcoded `onFireEval` is not a different model. -/
theorem onFireEval_eq_at (W : Weights) : onFireEval W = onFireEvalAt FIRE W := rfl

/-- **Backdoored weights.**  Carrier `κ = 7` in the inspected `[:D1]` block, plus a
    cancel neuron `-2` at row `D1` (outside the block).  On a firing pass the gate
    is open and the cancel neuron rewrites the emitted value `κ = 7 → P = 3` (the
    true buried payload); the cold gather still returns the carrier `7`. -/
def W_bd : Weights := ![7, -2]

/-- **Payload-free carrier weights.**  The SAME carrier `κ = 7` in the block, and NO
    cancel neuron (coord `1 = 0`).  On a firing pass it simply emits the carrier `7`;
    the cold gather also returns `7` — so it is cold-indistinguishable from `W_bd`. -/
def W_carrier : Weights := ![7, 0]

/-- **The cold read is BLIND (fibre collision).**  The canonical cold readout returns
    the carrier for both weights: `C(W_bd) = C(W_carrier) = 7`.  They share a fibre
    of `C` — no function of the static-weight read separates "carries payload `P`"
    from "carries only carrier junk". -/
theorem cold_collision : coldReadout W_bd = coldReadout W_carrier := by
  simp [coldReadout, W_bd, W_carrier, dotProduct, Fin.sum_univ_two]

/-- **The on-fire read SEES (separation).**  On a firing pass the cancel neuron
    fires: `E(W_bd) = 7 + 2·(-2) = 3 = P` while `E(W_carrier) = 7 + 2·0 = 7`, so
    `E(W_bd) ≠ E(W_carrier)`. -/
theorem onfire_separates : onFireEval W_bd ≠ onFireEval W_carrier := by
  have hg : gate FIRE = 2 := by simp [gate, FIRE]
  simp only [onFireEval, W_bd, W_carrier, hg,
    Matrix.cons_val_zero, Matrix.cons_val_one]
  norm_num

/-- **THE REGISTER-BURIAL SEPARATION.**  There EXIST weights on which the canonical
    cold readout `C` collides while the on-fire eval `E` distinguishes — and
    therefore `E` does NOT factor through `C`.  The cold static-weight register is
    NOT a universal detector; the on-fire register is (under the firing model).

    Closed by an explicit WITNESSED collision (`cold_collision`) that a matched-
    power on-fire read (`onfire_separates`) breaks, so the `¬ FactorsThrough` leg
    follows directly.

    HONEST: an inhabited existence-of-construction separation defeating ONE named
    cold readout — the positive form of the empirical register-burial finding, a
    complement to Goldwasser et al., not a universal "no cold readout detects" and
    not a refutation of any impossibility result. -/
theorem register_burial_separation :
    (∃ Wbd Wcar : Weights,
        coldReadout Wbd = coldReadout Wcar ∧ onFireEval Wbd ≠ onFireEval Wcar)
      ∧ ¬ onFireEval.FactorsThrough coldReadout := by
  refine ⟨⟨W_bd, W_carrier, cold_collision, onfire_separates⟩, ?_⟩
  intro hf
  exact onfire_separates (hf cold_collision)

/-- The single-cancel-neuron **backdoored family**, generalizing `W_bd = ![7,-2]`.
    For an arbitrary carrier `κ`, target payload `P`, and positive fire drive `F`,
    the cancel neuron `c = (P − κ)/F` at the out-of-block row is TUNED so a firing
    pass reconstructs `P` exactly: the cold gather sees only the carrier `κ`, while
    the on-fire read at drive `F` restores the buried payload `P`.  The `κ=7, P=3,
    F=FIRE=2` instance is `W_bd` (`c = (3−7)/2 = −2`). -/
noncomputable def burialFamily (κ P F : ℝ) : Weights := ![κ, (P - κ) / F]

/-- **RECOVERY-EXACTNESS OF THE FAMILY.**  Strengthens the single `![7,-2]`
    instance to the whole single-cancel-neuron burial family.  For ANY carrier
    `κ`, target payload `P`, and positive fire drive `F`, on the tuned weights
    `burialFamily κ P F = ![κ, (P−κ)/F]`:

      * the canonical cold readout returns the CARRIER — `coldReadout = κ`, blind to
        the payload (structurally, it only gathers the `[:D1]` block);
      * the on-fire read at drive `F` returns the EXACT payload — `onFireEvalAt F = P`,
        since the open gate (`gate F = F` for `F > 0`) lets the cancel neuron
        rewrite `κ ↦ κ + F·((P−κ)/F) = P`.

    So on ANY firing pass the reconstruction read recovers the exact payload for the
    entire family — not just the `κ=7, P=3` witness.

    HONEST: `κ, P, F` are abstract reals and this is the RECOVERY linear-algebra
    identity for the idealized single-cancel-neuron burial family (cold blind /
    on-fire exact) — NOT a claim about any detector's recall/AUC or any specific
    model.  It closes the single-cancel-neuron construction, not the whole burial
    class (which can hide the payload behind more than one out-of-block neuron). -/
theorem recovery_exact (κ P F : ℝ) (hF : 0 < F) :
    coldReadout (burialFamily κ P F) = κ
      ∧ onFireEvalAt F (burialFamily κ P F) = P := by
  have hFne : F ≠ 0 := ne_of_gt hF
  refine ⟨?_, ?_⟩
  · -- cold gather returns the carrier `κ`, blind to the tuned cancel neuron
    simp [coldReadout, burialFamily, dotProduct, Fin.sum_univ_two]
  · -- open gate `gate F = F` ⇒ `κ + F·((P−κ)/F) = P`
    have hgate : gate F = F := by rw [gate]; exact max_eq_left hF.le
    simp only [onFireEvalAt, burialFamily, hgate,
      Matrix.cons_val_zero, Matrix.cons_val_one]
    field_simp
    ring

/-! ### General-activation recovery — removing the relu idealization

  The SEPARATION legs above use `gate = relu` as an idealized piecewise-linear proxy
  for the firing branch of `silu`.  The RECOVERY identity, however, does not need the
  relu CHOICE at all: it needs only the activated fire-drive to be NONZERO.  The
  declarations below parameterize the activation and then instantiate at the REAL
  `silu`, so payload recovery is proven exact for the actual model nonlinearity — the
  relu form (`recovery_exact`) is just the `a = F` instance. -/

/-- The burial family parameterized by the **activated fire-drive** `a` (rather than a
    raw drive `F` fed through a fixed gate).  For carrier `κ`, payload `P`, and any
    activation output `a`, the cancel neuron is `c = (P − κ)/a`, tuned so an on-fire
    read that multiplies the cancel neuron by `a` reconstructs `P` exactly.  Taking
    `a = gate F = F` (relu at `F > 0`) recovers `burialFamily κ P F`; taking
    `a = silu F` gives the real-nonlinearity instance below. -/
noncomputable def burialFamilyPhi (κ P a : ℝ) : Weights := ![κ, (P - κ) / a]

/-- **RECOVERY-EXACTNESS UNDER AN ARBITRARY ACTIVATION.**  Removes the relu
    idealization from the recovery leg: for ANY carrier `κ`, payload `P`, and any
    NONZERO activated fire-drive `a` (`a = φ F` for any activation `φ` with
    `φ F ≠ 0`), on the tuned weights `burialFamilyPhi κ P a = ![κ, (P−κ)/a]`:

      * the canonical cold readout still returns the CARRIER — `coldReadout = κ`;
      * an on-fire read that gates the cancel neuron by `a` returns the EXACT payload
        — `κ + a·((P−κ)/a) = κ + (P−κ) = P`, since `a ≠ 0`.

    The relu form `recovery_exact` is the special case `a = gate F = F` (`F > 0`);
    `recovery_exact_silu` is the real-`silu` case.  So recovery is exact for the
    actual gate, not only its piecewise-linear proxy. -/
theorem recovery_exact_activation (κ P a : ℝ) (ha : a ≠ 0) :
    coldReadout (burialFamilyPhi κ P a) = κ
      ∧ (burialFamilyPhi κ P a) 0 + a * (burialFamilyPhi κ P a) 1 = P := by
  refine ⟨?_, ?_⟩
  · -- cold gather returns the carrier `κ`, blind to the tuned cancel neuron
    simp [coldReadout, burialFamilyPhi, dotProduct, Fin.sum_univ_two]
  · -- `a ≠ 0` ⇒ `κ + a·((P−κ)/a) = P`
    simp only [burialFamilyPhi, Matrix.cons_val_zero, Matrix.cons_val_one]
    field_simp
    ring

/-- The **real SiLU activation** `silu x = x · σ(x)` with sigmoid `σ x = 1/(1 + e^{−x})`
    — the ACTUAL firing nonlinearity that the `relu` `gate` above idealizes. -/
noncomputable def silu (x : ℝ) : ℝ := x * (1 / (1 + Real.exp (-x)))

/-- On a firing pass (`F > 0`) the real SiLU output is strictly positive: the sigmoid
    factor `1/(1 + e^{−F})` is positive (`e^{−F} > 0 ⇒ 1 + e^{−F} > 0`) and `F > 0`, so
    their product is positive.  This supplies the NONZERO-drive hypothesis
    `recovery_exact_activation` needs, discharged by the ACTUAL gate. -/
theorem silu_pos {F : ℝ} (hF : 0 < F) : 0 < silu F := by
  have hden : (0 : ℝ) < 1 + Real.exp (-F) := by
    have := Real.exp_pos (-F); linarith
  have hsig : (0 : ℝ) < 1 / (1 + Real.exp (-F)) := one_div_pos.mpr hden
  simpa [silu] using mul_pos hF hsig

/-- **RECOVERY-EXACTNESS UNDER THE REAL SiLU.**  The idealization is gone: on a firing
    pass (`F > 0`) with the ACTUAL `silu` gate, the cold readout returns the carrier
    `κ` while an on-fire read that gates the cancel neuron by `silu F` returns the
    EXACT payload `P`.  This is `recovery_exact_activation` instantiated at
    `a = silu F`, whose nonzero hypothesis is discharged by `silu_pos` — so the
    single-cancel-neuron payload recovery is exact for the real model nonlinearity,
    not merely its relu proxy. -/
theorem recovery_exact_silu (κ P F : ℝ) (hF : 0 < F) :
    coldReadout (burialFamilyPhi κ P (silu F)) = κ
      ∧ (burialFamilyPhi κ P (silu F)) 0
          + silu F * (burialFamilyPhi κ P (silu F)) 1 = P :=
  recovery_exact_activation κ P (silu F) (ne_of_gt (silu_pos hF))

end Proofora.RegisterBurial
