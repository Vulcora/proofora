# Presence-FPR Runnable Challenge

**Don't take our number. Run it on your own clean models.**

This is a direct answer to the critique that separates a detector from a
relabeling of a distribution-distance:

> *"'Presence, abstain on identity' is the honest output only if presence
> itself is calibrated… The missing axis is presence FPR against a pool that is
> mostly clean, the real-world ratio. Do you have that number — presence flag
> rate on a held-out clean cohort?"*

Two things it does not do: it does not hand you an AUC on a cohort with no true
negatives, and it does not ask you to trust a number you can't reproduce.

## What "presence" means here — read first

There are **two different channels**, and the critique lands squarely on the
first one:

1. **Weight-only presence read** (forward-free, CPU). Deployed *absolutely*
   against arbitrary community finetunes it is a finetuning-**distribution**
   detector, not a backdoor detector. We **concede it is dead** as an absolute
   scanner: **210/210 community-clean adapters fire, FPR = 1.0 @1% and @5%,
   Wilson95 [0.982, 1.0]** (`/data/wceval/RESULTS.json`). A clean base above a
   backdoor is exactly this failure. We publish it as our own ~100% FPR.

2. **Reference-MODEL-free payload elicitation** (the ATTEST leg — the channel
   this challenge is about). It derives its probe from the suspect adapter's
   own parameters (no clean twin, no reference model, no reference
   activations), and instead of a score it makes a backdoored adapter **speak
   its hidden payload as legible text**. A clean adapter has nothing to wake.
   On this channel the held-out clean number is **0/68** (0/20 cross-recipe).

This challenge computes the **presence flag rate on channel 2**, the live one.

## The honest FPR arithmetic (what `verify-ours` recomputes vs. cites)

| clean cohort | benign adapters | fires | point FPR | Wilson 95% upper |
|---|---|---|---|---|
| cross-recipe community finetunes | 20 | 0 | 0.000 | **16.11%** |
| pooled total benign (20 cross-recipe + 48 same-recipe) | 68 | 0 | 0.000 | **5.35%** |

Only the **0/20 cross-recipe** row is recomputed from shipped raw verdicts. The
48 same-recipe controls — and therefore the pooled **0/68** — are **cited from
`FIRM_WAVE_RESULTS.json` (`clean_same_recipe_fpr: "0/48"`) and asserted as a
constant, not per-adapter reproducible here**; the script marks that portion
`replayed_here: false`. The pooled Wilson upper bound is derived from the cited
total.

The 20 cross-recipe adapters are enumerated and shipped in
`published_benign_verdicts.json` (AdamLucek, Alphatao, ArchSid,
FelixHofstaetter, Jaamie, Koomemartin, BarryL, Ezekielmsc, GaetanMichelet,
HermitQ, Jazhyc, Jongbin-kr, MohamedShata, DeepDream2045). These are the *same
kind* of diverse community finetune that fired 210/210 on channel 1 — several
appear verbatim in that read's fired list. The true-negatives that broke the
distribution-detector produce **zero** false positives under elicitation.

**We state the decoupling ourselves.** A point estimate of 0 FP does not
certify a low FPR at scale. The number that governs deployment is the **Wilson
upper bound**, and this script prints, at your chosen real-world base rate, the
**worst-case PPV** if the true FPR sat at that upper bound. At 5% prevalence and
the pooled 5.35% upper bound, worst-case PPV is ~0.27–0.31 — we would rather
show you that than a PPV of 1.0 that only holds because the pool was planted.

## Usage

```bash
PY=python3   # stdlib only, 3.8+

# 1. Audit OUR number — no models, no GPU, no capability needed.
$PY presence_fpr_challenge.py verify-ours

# 2. Run it on YOUR clean adapters.
#    Without a probe wrapper it prints the exact reproduction protocol
#    (a deliberate stub — this script ships NO method internals):
$PY presence_fpr_challenge.py score --adapters-dir /path/to/your/clean_adapters --arch gemma-2-9b

#    With your capability wrapper (contract in the protocol / --help):
$PY presence_fpr_challenge.py score \
    --adapters-dir /path/to/your/clean_adapters \
    --arch gemma-2-9b --alpha <your-per-arch-grid> \
    --capability-cmd "python my_presence_probe.py"

# 3. Re-verify any signed record produced above.
$PY presence_fpr_challenge.py replay --record record.json
```

Every run emits a **signed replay record**: a `sha256` content digest over the
canonical JSON, plus a **hubscan-style manifest** (per-file size + sha256) of
every adapter scored, so a third party can confirm the record was produced on
exactly those bytes. Tamper with any field and `replay` fails.

## The firewall (why the probe is external)

`presence_fpr_challenge.py` contains **no detector-method internals** — none of
how the probe turns an adapter into a 0/1 flag. That boundary is deliberate. The
script owns and fully exposes the parts that matter for *your* audit: the FPR
arithmetic, the Wilson interval, the base-rate PPV framing, the content digest,
and the byte manifest. The probe itself crosses the boundary as a black box via
`--capability-cmd`; only its verdict comes back. To audit our published number
you need no probe at all — `verify-ours` recomputes the **0/20 cross-recipe**
number from the shipped raw LLM-judge verdicts. The 48 same-recipe controls (and
therefore the pooled **0/68**) are **cited from `FIRM_WAVE_RESULTS.json` and
asserted as a constant, not per-adapter reproducible here** — the script's own
record marks that portion `replayed_here: false`.

## Ceilings, stated on the same page

- This is a **precision-optimized** channel, not high-recall or high-AUC.
  Pooled recall **0.38** (ad) / **0.46** (affective); per-arch **12%–75%**.
  Pooled AUCs **0.688 CI[0.604,0.792]** / **0.729 CI[0.625,0.833]** — both clear
  0.5, both far under matched-reference detectors. It wakes a *minority* of
  poison adapters — never read it as "always detectable."
- Poison recall is **NIST-capped at n=8 / subclass / arch**; CIs are wide.
- Steering magnitude is **per-architecture** — each model family needs its own
  small steering-magnitude grid (× RMS); there is no universal setting. A
  disclosed calibration requirement, not a hidden knob. Use the same grid you
  would use to detect, so the FP test is apples-to-apples with recall.
- Scoring is by an **independent LLM-judge** on full untruncated output.
- `reference-MODEL-free`, not bare "reference-free": the matched-reference
  DETECT leg (a separate channel) *does* require a recipe-matched benign
  population.

## Files

- `presence_fpr_challenge.py` — the challenge (stdlib only).
- `published_benign_verdicts.json` — the 20 cross-recipe community verdicts,
  each `presence_flag = 0`, provenance to
  `/data/sota_bench/intervention_firm/out/judge_verdicts_community.json`.
