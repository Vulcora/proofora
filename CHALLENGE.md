# The Refuter's Wall

*An open proof lane — because "no counterexample" is not a proof.*

This lane came out of engaging both of Justin Garringer's projects *together* —
[Whetstone](https://github.com/CarlSR9001/whetstone) and
[SalienceLean](https://github.com/CarlSR9001/SalienceLean) — and finding that they complement each
other almost exactly. Whetstone is a **refuter**: it exhibits the model pair that breaks a promotion
claim. SalienceLean is a **prover**: it certifies a statement against the Lean kernel. Those are the
two halves of one discipline, and the seam between them is this wall. It's open to anyone. It lives
entirely in the public excise / register-lock linear algebra of this repo and touches no sealed
method.

## The wall

A refuter — a counterexample search, or Lean's own `plausible` — exhibits the witness that breaks a
false `∀`-claim. Fast, sound, useful. But "searched N, found nothing" is never a proof of a
`∀`-statement, and a bounded search emits no machine-checked certificate at all. The gap between
*failing to refute* and *proving* is the wall. Crossing it means a proof the Lean kernel accepts.

We already cross it once, for shipped product math: `Proofora/Excise.lean` builds on SalienceLean's
`charge_computable_of_rowspace` to prove `rank_one_erases_only_span` — *a rank-1 witness is provably
not a lock*. The targets below are the next step: the rank-k generalization, and the converse that
SalienceLean itself flags as "classical but not formalized here."

## The targets

All three live in [`Proofora/RefutersWall.lean`](Proofora/RefutersWall.lean), each an honest `sorry`:

1. **`registerLock_rank`** *(the main target)* — the shipped register-lock `I − R Rᵀ` with
   `Rᵀ R = 1` removes a subspace of dimension **exactly** k: its rank is `h − k`. The quantitative
   core of "a rank-1 witness is not a lock," at the true operating rank. No counterexample exists at
   any dimension, so a refuter certifies nothing; the proof wants a projector-rank (= trace)
   argument that Mathlib doesn't package ready-made.
2. **`registerLock_kernel_eq_range`** *(the on-ramp)* — what the lock erases is *exactly* the
   register column space `col(R)`. The direct generalization of the shipped k=1 theorem — the
   gentlest way in.
3. **`charge_in_rowspace_of_vanishing_on_ker`** — the **converse** of SalienceLean's
   `charge_computable_of_rowspace`: a read functional blind on `ker C` must live in `range Cᵀ`. It's
   the half your own repo marks classical-but-unformalized, on your own machinery. We found it
   genuinely worth formalizing while building on your work, and it felt right to hand it back rather
   than quietly close it ourselves.

## Two ways through

1. **Cross a target** — replace a `sorry` with a real proof.
2. **Refute a sealed "truth"** — if you find a counterexample to a statement we labeled true, *you
   win*, and you've found a bug in our ground truth. We concede publicly and credit you. Honestly,
   that outcome helps us more than a clean crossing does.

Either way you're credited on the result. No bounty theatre — the reward is the co-authored proof
(or the co-owned correction) and a public, re-runnable receipt.

## How to engage

No fork-and-fight, no automated gate passing public judgment on your branch. If you want to take a
target:

1. **Prove it locally.** Replace a `sorry` in `Proofora/RefutersWall.lean` with a proof. You can run
   the exact bar yourself — `bash scripts/check_cert.sh Proofora/RefutersWall.lean` — a deterministic
   accept/reject (the four gates below). You see green before you send anything: no surprises, and
   nothing half-finished ever has to appear in public with your name on it.
2. **Send it to us** — email, or open an issue, with your proof. If it checks out, **we** open the
   pull request, land it, and publish it with your name on the result. We do the public work; your
   crossing goes up as a co-owned, re-runnable receipt — not a red mark on your fork. We're glad to
   be the ones putting your work forward.

The checker exists so the bar is transparent and mechanical — *not* so a machine sits in judgment.
What "checks out" means, precisely: don't weaken the sealed statement; don't add
`import`/`open`/`notation`/`macro`/`instance`/`axiom`/`def`; don't use `native_decide`. Helper
`theorem`/`lemma`s are welcome.

## The checker — `scripts/check_cert.sh`

Deterministic accept/reject, four gates, no judgment call:

1. **Statement integrity** — the sealed statement must be present verbatim (no weakening).
2. **Anti-shadow** — no `import`/`open`/`notation`/`macro`/`instance`/`axiom`/`def`/`set_option`
   beyond the sealed skeleton, so you cannot redefine `Matrix.rank`/`det`/… to gut the statement.
   Helper `theorem`/`lemma`/`example` are fine.
3. **Trusted type** — a checker-controlled file, using the genuine Mathlib symbols, asserts your
   theorem inhabits the intended type. Shadowing changes the type and fails here.
4. **Axioms** — `#print axioms` must report only `{propext, Classical.choice, Quot.sound}`: no
   `sorryAx` (incomplete), no `native_decide` (surfaces as `Lean.ofReduceBool`), no fresh `axiom`.

On ACCEPT the checker prints a SHA-256 receipt of the accepted file — the same commit-carrying
discipline as Whetstone's own receipts.

## Honest posture

These are real `∀`-theorems about a concrete engineered operator, requiring real proof development —
which is exactly why a bounded refuter cannot reach them. They're standard results: for each one,
every dependency is verified present in the pinned Mathlib and a complete proof strategy is traced,
so this is a calibrated wall — not a bluff, and not a trick. When the lane resolves, everything is
published in the open.

And the wall is only the contest. The collaboration it's pointing at is the real thing: a pipeline
where a leakage-proof eval keeps a proof-generation loop honest, a refuter finds the statement, and
the Lean kernel certifies the result. Cross a target, or break one of ours — either way it advances.
