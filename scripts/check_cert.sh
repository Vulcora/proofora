#!/usr/bin/env bash
#
# check_cert.sh — The Refuter's Wall certificate checker.
# =======================================================
#
# Deterministic accept/reject for a submitted proof of a sealed challenge target.
# No judgment call: the certificate either survives all four gates, or it does not.
#
# Usage:
#   scripts/check_cert.sh <submitted Proofora/RefutersWall.lean> [TARGET_DECL]
#
# GATES (all must pass):
#   (1) STATEMENT INTEGRITY — the sealed target statement is present verbatim
#       (whitespace-normalised), so a challenger cannot silently weaken it.
#   (2) ANTI-SHADOW — the submission introduces no import / open / notation / macro /
#       instance / axiom / def / set_option beyond the sealed skeleton. This blocks
#       semantic shadowing (redefining `Matrix.rank`/`det`/… to gut the statement).
#       Helper `theorem`/`lemma` are allowed (they are propositions, not redefinitions).
#   (3) TRUSTED TYPE — a checker-controlled file, using the GENUINE Mathlib symbols,
#       asserts `@TARGET` inhabits the intended type. If anything was shadowed so the
#       submission's theorem has a different type, this fails to type-check.
#   (4) AXIOMS — `#print axioms TARGET` reports ONLY {propext, Classical.choice,
#       Quot.sound}: no `sorryAx` (incomplete), no `native_decide` (`Lean.ofReduceBool`),
#       no freshly-`axiom`'d escape.
#
# On ACCEPT it prints a SHA-256 receipt of the accepted file — the same
# commit-carrying discipline as the challenge preimage and Whetstone's own receipts.
set -euo pipefail

SUB="${1:?usage: check_cert.sh <submitted Proofora/RefutersWall.lean> [TARGET_DECL]}"
TARGET="${2:-Proofora.RefutersWall.registerLock_rank}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.elan/bin:$PATH"

reject() { echo "VERDICT: REJECT — $1"; exit 1; }

# ── the SEALED target statement (keep in sync with Proofora/RefutersWall.lean) ──
read -r -d '' SEALED_SIG <<'SIG' || true
theorem registerLock_rank {h k : ℕ}
    (R : Matrix (Fin h) (Fin k) ℝ) (hR : Rᵀ * R = 1) :
    (1 - R * Rᵀ).rank = h - k
SIG
# ── the GENUINE type the target must inhabit (all-explicit @-form) ──
read -r -d '' TRUSTED_TYPE <<'TT' || true
∀ (h k : ℕ) (R : Matrix (Fin h) (Fin k) ℝ), Rᵀ * R = 1 → (1 - R * Rᵀ).rank = h - k
TT

norm() { tr -s '[:space:]' ' ' | sed 's/ *$//'; }

echo "== (1) statement-integrity =="
if ! norm < "$SUB" | grep -qF "$(printf '%s' "$SEALED_SIG" | norm)"; then
  reject "sealed target statement not found verbatim — the theorem was altered/weakened"
fi
echo "   ok — sealed statement present, unmodified"

echo "== (2) anti-shadow structural scan =="
# strip /- .. -/ block comments (incl. /-! doc -/) and -- line comments, then scan
STRIPPED="$(perl -0777 -pe 's{/-.*?-/}{}gs; s{--[^\n]*}{}g' "$SUB")"
first() { grep -nE "$1" <<<"$STRIPPED" | head -1; }
# new imports beyond the sealed two
if grep -P '^\s*import\s+' <<<"$STRIPPED" | grep -qvP '^\s*import\s+(Mathlib|Proofora\.Excise)\s*$'; then
  reject "new 'import' introduced (only 'import Mathlib' / 'import Proofora.Excise' are sealed): $(grep -nP '^\s*import\s+' <<<"$STRIPPED" | grep -vP 'import\s+(Mathlib|Proofora\.Excise)' | head -1)"
fi
# top-level open beyond the sealed two
if grep -E '^\s*open\s+' <<<"$STRIPPED" | grep -qvE '^\s*open\s+(Matrix|scoped\s+Matrix)\s*$'; then
  reject "new top-level 'open' beyond the sealed opens: $(grep -nE '^\s*open\s+' <<<"$STRIPPED" | grep -vE 'open\s+(Matrix|scoped\s+Matrix)' | head -1)"
fi
# shadowing / escape constructs (helper theorem/lemma/example stay allowed)
if grep -qE '(^|[[:space:]])(notation|macro|macro_rules|syntax|set_option|axiom|attribute|def|abbrev|instance)([[:space:]]|$)' <<<"$STRIPPED"; then
  reject "shadowing/escape construct is not allowed — only theorem/lemma/example: $(first '(^|[[:space:]])(notation|macro|macro_rules|syntax|set_option|axiom|attribute|def|abbrev|instance)([[:space:]]|$)')"
fi
if grep -qE '(^|[^A-Za-z_])native_decide([^A-Za-z_]|$)' <<<"$STRIPPED"; then
  reject "native_decide is not accepted (trusts the compiler, not the kernel)"
fi
echo "   ok — no shadowing/escape constructs"

echo "== install submission + build =="
TGT_FILE="$REPO/Proofora/RefutersWall.lean"
if [ "$(readlink -f "$SUB")" != "$(readlink -f "$TGT_FILE")" ]; then
  cp "$TGT_FILE" "/tmp/RefutersWall.sealed.$$"
  cp "$SUB" "$TGT_FILE"
  restore() { cp "/tmp/RefutersWall.sealed.$$" "$TGT_FILE" 2>/dev/null || true; rm -f "/tmp/RefutersWall.sealed.$$"; }
  trap restore EXIT
fi
cd "$REPO"
lake build Proofora.RefutersWall || reject "lake build failed — the proof does not type-check"
echo "   ok — module builds"

echo "== (3) trusted-type re-check =="
TT_FILE="/tmp/_TrustedType.$$.lean"
{
  echo 'import Mathlib'
  echo 'import Proofora.RefutersWall'
  echo 'open Matrix'
  echo 'open scoped Matrix'
  echo "example : ${TRUSTED_TYPE} :="
  echo "  @${TARGET}"
} > "$TT_FILE"
if ! lake env lean "$TT_FILE" > "/tmp/_tt_out.$$" 2>&1; then
  cat "/tmp/_tt_out.$$"; rm -f "$TT_FILE" "/tmp/_tt_out.$$"
  reject "the theorem does not inhabit the GENUINE Mathlib-typed statement (semantic shadowing?)"
fi
rm -f "$TT_FILE" "/tmp/_tt_out.$$"
echo "   ok — inhabits the genuine type"

echo "== (4) axiom check on $TARGET =="
CHK="/tmp/_axcheck.$$.lean"
printf 'import Proofora.RefutersWall\n#print axioms %s\n' "$TARGET" > "$CHK"
AX="$(lake env lean "$CHK" 2>&1 || true)"; rm -f "$CHK"
echo "$AX"
if grep -qi 'sorryAx\|sorry\|declaration uses' <<<"$AX"; then
  reject "proof depends on 'sorry' (incomplete) — no certificate"
fi
BADAX="$(grep -oE '[A-Za-z_][A-Za-z0-9_.]*' <<<"$AX" \
  | grep -vE '^(propext|Classical\.choice|Quot\.sound|depends|on|axioms|and)$' \
  | grep -viE "^${TARGET//./\\.}$" || true)"
if [ -n "$BADAX" ]; then
  reject "proof depends on non-standard axiom(s): $(echo "$BADAX" | tr '\n' ' ')"
fi
echo "   ok — depends only on {propext, Classical.choice, Quot.sound}"

RECEIPT="$(sha256sum "$SUB" | awk '{print $1}')"
echo
echo "VERDICT: ACCEPT"
echo "target:  $TARGET"
echo "receipt: sha256:$RECEIPT"
