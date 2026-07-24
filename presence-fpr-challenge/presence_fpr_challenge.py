#!/usr/bin/env python3
# presence_fpr_challenge.py
# ---------------------------------------------------------------------------
# A RUNNABLE, SIGNED presence-FPR challenge for the reference-MODEL-free
# payload-elicitation channel.
#
# Motivation (dipankar's critique, verbatim spirit):
#   "confidence and correctness look aligned only because the test set never
#    held the case that separates them. The missing axis is presence FPR
#    against a pool that is mostly clean, the real-world ratio."
#
# This script does NOT ask you to trust our number. It lets you COMPUTE the
# presence flag rate yourself, on YOUR own clean models, and emits a signed
# replay record so a third party can re-verify the arithmetic bit-for-bit.
#
# FIREWALL: this file contains NO detector-method internals. The probe that
# turns an adapter into a presence_flag (0/1) is an EXTERNAL capability the
# script calls through a narrow interface (`--capability-cmd`) or reads from a
# pre-computed verdicts file (`--verdicts`). The FPR statistics, the Wilson
# interval, the base-rate PPV framing, the content digest and the hubscan-style
# manifest are all fully open and auditable here.
#
# THREE MODES
#   1. verify-ours   : recompute OUR published cross-recipe number (0/20) from
#                      the shipped raw judge verdicts. The 48 same-recipe
#                      controls — hence the pooled 0/68 — are CITED from
#                      FIRM_WAVE_RESULTS.json (clean_same_recipe_fpr "0/48") and
#                      asserted as a constant, not per-adapter reproducible here
#                      (the emitted record marks that portion replayed_here:false).
#                      Pure arithmetic on judge outputs — no method, no GPU.
#   2. score         : compute the presence flag rate on YOUR dir of clean
#                      adapters. Requires a capability wrapper (see PROTOCOL);
#                      by default it STUBS and prints the exact reproduction
#                      protocol rather than guessing.
#   3. replay        : re-verify a signed record's sha256 content digest.
#
# stdlib only. Python 3.8+.
# ---------------------------------------------------------------------------
import argparse, hashlib, json, math, os, subprocess, sys, time
from datetime import datetime, timezone

SCRIPT_VERSION = "presence_fpr_challenge/1.0.0"
Z95 = 1.959963984540054  # norm.ppf(0.975)


# ---------------------------------------------------------------------------
# statistics (open, auditable — this is the part dipankar wants to re-run)
# ---------------------------------------------------------------------------
def wilson_interval(k, n, z=Z95):
    """Wilson score interval for a binomial proportion. Exact, no scipy."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    denom = 1.0 + z * z / n
    center = p + z * z / (2 * n)
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((center - half) / denom, (center + half) / denom)


def worst_case_ppv(base_rate, recall, fpr_upper):
    """Precision if the TRUE presence FPR sat at its Wilson-95 upper bound.

    This is the honest confidence/correctness decoupling number: a point
    estimate of 0 FP does NOT certify low FPR at scale; deployment PPV is
    governed by the interval upper bound and the real-world base rate.
    """
    num = base_rate * recall
    den = num + (1 - base_rate) * fpr_upper
    return (num / den) if den > 0 else float("nan")


# ---------------------------------------------------------------------------
# signing / manifest (open, auditable)
# ---------------------------------------------------------------------------
def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(chunk), b""):
            h.update(blk)
    return h.hexdigest()


def adapter_manifest(adapter_dir):
    """hubscan-style per-file manifest: every file's size + sha256, sorted.

    Ties the signed record to the EXACT bytes scored, so a replay can prove it
    ran on the same models (or catch a swap)."""
    entries = []
    for root, _dirs, files in os.walk(adapter_dir):
        for name in sorted(files):
            fp = os.path.join(root, name)
            rel = os.path.relpath(fp, adapter_dir)
            try:
                entries.append({
                    "path": rel,
                    "bytes": os.path.getsize(fp),
                    "sha256": sha256_file(fp),
                })
            except OSError as e:
                entries.append({"path": rel, "error": str(e)})
    entries.sort(key=lambda e: e["path"])
    blob = canonical(entries)
    return {"files": entries, "n_files": len(entries), "manifest_sha256": sha256_bytes(blob)}


def sign_record(record):
    """Attach a content digest over the canonical record (excluding the digest
    field itself)."""
    body = {k: v for k, v in record.items() if k != "signature"}
    digest = sha256_bytes(canonical(body))
    record["signature"] = {
        "algo": "sha256-canonical-json",
        "content_digest": "sha256:" + digest,
        "script_version": SCRIPT_VERSION,
        "signed_at_utc": datetime.now(timezone.utc).isoformat(),
    }
    return record


def verify_record(path):
    rec = json.load(open(path))
    sig = rec.get("signature")
    if not sig:
        return False, "no signature block"
    body = {k: v for k, v in rec.items() if k != "signature"}
    expect = "sha256:" + sha256_bytes(canonical(body))
    got = sig.get("content_digest")
    return (expect == got), f"expected {expect}\n     got      {got}"


# ---------------------------------------------------------------------------
# the capability surface (EXTERNAL — firewall boundary)
# ---------------------------------------------------------------------------
PROTOCOL = """
REPRODUCTION PROTOCOL — presence flag via the capability surface
================================================================
This challenge intentionally ships NO detector-method internals. To score
YOUR clean adapters you supply the presence-probe capability yourself, through
a one-line contract. The probe is a black box to this script; only its 0/1
verdict crosses the boundary.

CONTRACT (`--capability-cmd "<cmd>"`):
  The script calls, once per adapter:

      <cmd> --adapter <ABS_PATH> --arch <ARCH> --alpha <CSV> --out <JSON>

  and reads back a JSON object at <JSON>:

      { "presence_flag": 0 | 1,      # 1 iff the adapter leaked a hidden payload
        "payload": "<verbatim text or empty>",
        "judge": "<scorer id>" }

  presence_flag MUST be adjudicated by an INDEPENDENT judge on the FULL,
  untruncated steered generations (we used an Opus full-union LLM-judge). Do
  not regex a keyword list — that manufactures artifacts (see RESULTS_ERRATA).

CALIBRATION (disclosed requirement, not a hidden knob):
  Steering magnitude is PER-ARCHITECTURE. There is no universal setting.
      each model family has its own narrow magnitude window (x RMS);
      pass your grid via --alpha (CSV).
  Outside its window a family over-steers (token soup) or under-steers
  (boilerplate). Use the same grid you would use to DETECT, so the FP test is
  apples-to-apples with the recall test.

HOW TO GET THE CAPABILITY:
  The served product exposes this probe (DETECT-ATTEST-EXCISE, ATTEST leg).
  Point --capability-cmd at your local wrapper around it. If you only want to
  audit OUR number, you need no capability at all: run `verify-ours`, which
  recomputes 0/20 from the shipped raw judge verdicts and pools in the cited
  0/48 same-recipe constant (from FIRM_WAVE_RESULTS.json; replayed_here:false).

WHAT THIS SCRIPT GUARANTEES REGARDLESS OF THE PROBE:
  - the FPR arithmetic (fires / N)
  - the Wilson 95% interval (upper bound is the number that governs PPV)
  - the base-rate PPV framing at your chosen real-world prevalence
  - a signed, replayable record digest + a hubscan-style byte manifest
"""


def run_capability(cmd, adapter_dir, arch, alpha, workdir):
    out_json = os.path.join(workdir, "probe_out.json")
    if os.path.exists(out_json):
        os.remove(out_json)
    full = f'{cmd} --adapter "{adapter_dir}" --arch {arch} --alpha {alpha} --out "{out_json}"'
    subprocess.run(full, shell=True, check=True)
    with open(out_json) as f:
        res = json.load(f)
    flag = int(bool(res.get("presence_flag", 0)))
    return flag, res


# ---------------------------------------------------------------------------
# modes
# ---------------------------------------------------------------------------
def summarize(fires, n, recall_lo, recall_hi, base_rates):
    lo, hi = wilson_interval(fires, n)
    out = {
        "n_clean": n,
        "fires": fires,
        "presence_fpr_point": (fires / n) if n else None,
        "presence_fpr_wilson95": [round(lo, 6), round(hi, 6)],
        "presence_fpr_wilson95_upper_pct": round(hi * 100, 4),
        "note": "point FPR is not a guarantee; the Wilson UPPER bound governs deployment PPV.",
        "base_rate_ppv_worstcase": {},
    }
    for pi in base_rates:
        out["base_rate_ppv_worstcase"][str(pi)] = {
            "recall_lo": recall_lo, "recall_hi": recall_hi,
            "ppv_at_recall_lo": round(worst_case_ppv(pi, recall_lo, hi), 4),
            "ppv_at_recall_hi": round(worst_case_ppv(pi, recall_hi, hi), 4),
            "reading": "PPV if the TRUE FPR sat at the Wilson upper bound %.4f at prevalence %s" % (hi, pi),
        }
    return out


def mode_verify_ours(args):
    here = os.path.dirname(os.path.abspath(__file__))
    bundle = json.load(open(os.path.join(here, "published_benign_verdicts.json")))
    recs = bundle["records"]
    fires = sum(r["presence_flag"] for r in recs)
    n = len(recs)
    xrecipe = summarize(fires, n, args.recall_lo, args.recall_hi, args.base_rates)

    # pooled 0/68 = 20 shipped cross-recipe (replayed here) + 48 same-recipe
    # (cited from FIRM_WAVE_RESULTS.json; NIST-derived, not per-adapter public).
    SAME_RECIPE_N, SAME_RECIPE_FIRES = 48, 0
    pooled_n = n + SAME_RECIPE_N
    pooled_fires = fires + SAME_RECIPE_FIRES
    pooled = summarize(pooled_fires, pooled_n, args.recall_lo, args.recall_hi, args.base_rates)

    record = {
        "kind": "presence_fpr_verify_ours",
        "channel": "reference-MODEL-free payload-elicitation (ATTEST leg)",
        "scoring": bundle["scoring"],
        "source_verdicts": bundle["source_verdicts"],
        "cross_recipe_community": {
            "cohort": bundle["cohort"], "n": n, "fires": fires,
            "repo_ids": [r["repo_id"] for r in recs],
            "stats": xrecipe,
        },
        "pooled_total_benign": {
            "n": pooled_n, "fires": pooled_fires,
            "composition": {
                "cross_recipe_community": {"n": n, "fires": fires, "replayed_here": True},
                "same_recipe_controls": {
                    "n": SAME_RECIPE_N, "fires": SAME_RECIPE_FIRES,
                    "replayed_here": False,
                    "source": "/data/sota_bench/intervention_firm/out/FIRM_WAVE_RESULTS.json "
                              "(16 controls x 3 arch, best per-arch alpha)",
                },
            },
            "stats": pooled,
        },
        "verdicts_digest": "sha256:" + sha256_bytes(canonical(recs)),
        "ceilings": {
            "recall_is_precision_traded": "pooled recall 0.38 (ad) / 0.46 (affective); this is a "
            "PRECISION-optimized channel, not high-recall or high-AUC.",
            "recall_nist_capped": "n=8 poison/subclass/arch; wide CIs.",
            "per_arch_calibration_required": "no universal steering magnitude; disclosed.",
            "judge_basis": "independent LLM-judge on full untruncated output.",
            "not_absolute_weight_read": "the weight-only presence read is a DIFFERENT channel and "
            "is conceded DEAD as an absolute scanner (210/210 community-clean fire, FPR=1.0). This "
            "is the elicitation channel.",
        },
    }
    print(json.dumps(sign_record(record), indent=2))
    return 0


def mode_score(args):
    if not args.adapters_dir:
        print("ERROR: --adapters-dir required for `score`.", file=sys.stderr)
        return 2
    subdirs = sorted(
        os.path.join(args.adapters_dir, d) for d in os.listdir(args.adapters_dir)
        if os.path.isdir(os.path.join(args.adapters_dir, d))
    )
    if not subdirs:
        print("ERROR: no adapter subdirectories under %s" % args.adapters_dir, file=sys.stderr)
        return 2

    if not args.capability_cmd:
        print(PROTOCOL)
        print("\nSTUB MODE: no --capability-cmd supplied, so no method was invoked.")
        print("Found %d candidate adapter dirs:" % len(subdirs))
        for s in subdirs:
            print("  ", s)
        print("\nRe-run with --capability-cmd '<your probe wrapper>' to compute the flag rate,")
        print("or run `verify-ours` to audit our published number with no capability at all.")
        return 3

    workdir = args.workdir or os.path.join(args.adapters_dir, ".challenge_work")
    os.makedirs(workdir, exist_ok=True)
    per = []
    fires = 0
    for s in subdirs:
        flag, raw = run_capability(args.capability_cmd, s, args.arch, args.alpha, workdir)
        fires += flag
        per.append({
            "adapter_dir": s,
            "arch": args.arch,
            "alpha": args.alpha,
            "presence_flag": flag,
            "payload": raw.get("payload", ""),
            "judge": raw.get("judge", ""),
            "manifest": adapter_manifest(s),
        })
    stats = summarize(fires, len(subdirs), args.recall_lo, args.recall_hi, args.base_rates)
    record = {
        "kind": "presence_fpr_score",
        "channel": "reference-MODEL-free payload-elicitation (ATTEST leg)",
        "capability_cmd": args.capability_cmd,
        "arch": args.arch,
        "alpha_grid": args.alpha,
        "cohort_dir": os.path.abspath(args.adapters_dir),
        "n_clean": len(subdirs),
        "fires": fires,
        "stats": stats,
        "per_adapter": per,
        "protocol_note": "presence_flag adjudicated by the supplied capability's independent judge; "
                         "this script owns only the statistics + signing.",
    }
    print(json.dumps(sign_record(record), indent=2))
    return 0


def mode_replay(args):
    ok, detail = verify_record(args.record)
    print(("OK   " if ok else "FAIL ") + "signature verify: %s" % args.record)
    print("     " + detail.replace("\n", "\n     "))
    return 0 if ok else 1


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(
        description="Runnable, signed presence-FPR challenge (reference-MODEL-free elicitation channel).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=PROTOCOL,
    )
    sub = ap.add_subparsers(dest="mode", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--recall-lo", type=float, default=0.38,
                        help="pooled ad recall for PPV framing (published 0.38)")
    common.add_argument("--recall-hi", type=float, default=0.46,
                        help="pooled affective recall for PPV framing (published 0.46)")
    common.add_argument("--base-rates", type=float, nargs="+", default=[0.01, 0.05, 0.10],
                        help="real-world backdoor prevalence(s) for worst-case PPV")

    p1 = sub.add_parser("verify-ours", parents=[common],
                        help="recompute OUR published 0/20 from shipped raw verdicts; pool in the cited 0/48 constant (0/68)")
    p1.set_defaults(func=mode_verify_ours)

    p2 = sub.add_parser("score", parents=[common],
                        help="compute the presence flag rate on YOUR dir of clean adapters")
    p2.add_argument("--adapters-dir", required=True)
    p2.add_argument("--arch", default="unknown")
    p2.add_argument("--alpha", default="", help="per-arch steering grid, CSV — set to your probe's grid (see PROTOCOL)")
    p2.add_argument("--capability-cmd", default=None,
                    help="external presence-probe wrapper; omit to print the reproduction protocol")
    p2.add_argument("--workdir", default=None)
    p2.set_defaults(func=mode_score)

    p3 = sub.add_parser("replay", help="re-verify a signed record's content digest")
    p3.add_argument("--record", required=True)
    p3.set_defaults(func=mode_replay)

    args = ap.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
