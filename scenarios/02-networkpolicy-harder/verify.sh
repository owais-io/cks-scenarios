#!/usr/bin/env bash
# CKS Scenario 02 — verifier. Runs all checks, prints pass/fail + score.

PASS=0; FAIL=0
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
ok()  { green "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { red   "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== Verifying CKS Scenario 02: NetworkPolicy (harder) ==="
echo

if ! kubectl get ns shop >/dev/null 2>&1; then
  red "Namespace 'shop' not found. Run ./setup.sh first."; exit 1
fi

API_IP=$(kubectl -n shop get pod api -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [ -z "$API_IP" ]; then
  red "Could not find api pod IP. Run ./setup.sh first."; exit 1
fi

# Preflight: every pod used below must be Running, otherwise a failed exec
# would be miscounted as "BLOCKED".
for p in shop/api shop/web external/scanner external/site; do
  PHASE=$(kubectl -n "${p%/*}" get pod "${p#*/}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PHASE" != "Running" ]; then
    red "Pod '$p' is not Running (phase: ${PHASE:-missing}). Run ./setup.sh first."; exit 1
  fi
done
# Targets must actually serve on :80 (localhost is never affected by NetworkPolicy).
for p in shop/api external/site; do
  if ! kubectl -n "${p%/*}" exec "${p#*/}" -- wget -q -O /dev/null -T 4 http://127.0.0.1:80 >/dev/null 2>&1; then
    red "nginx in '$p' isn't serving on :80, so BLOCKED checks would be meaningless. Re-run ./setup.sh."; exit 1
  fi
done
SITE_IP=$(kubectl -n external get pod site -o jsonpath='{.status.podIP}' 2>/dev/null || true)

# reach <ns> <pod> [ip] -> <ip>:80 by IP (isolates L3/L4 from DNS); default target = api
reach() { kubectl -n "$1" exec "$2" -- curl -s -o /dev/null -m 4 "http://${3:-$API_IP}:80" >/dev/null 2>&1; }

echo "Connectivity target: api pod $API_IP:80"
echo

# Check 1: web -> api ALLOWED
if reach shop web; then ok "web -> api:80 is ALLOWED (expected)"
else bad "web -> api:80 is blocked, but should be allowed (check web egress + api ingress)"; fi

# Check 2: DNS still works from web (the trap)
if kubectl -n shop exec web -- nslookup api.shop.svc.cluster.local >/dev/null 2>&1; then
  ok "web can resolve DNS (egress to kube-system:53 is open)"
else
  bad "web CANNOT resolve DNS — your default-deny egress broke DNS. Allow egress to kube-system on UDP+TCP 53."
fi

# Check 3: scanner (external ns) -> api BLOCKED
if reach external scanner; then
  bad "scanner(external) -> api:80 is allowed, but should be BLOCKED (api ingress must be from web only)"
else
  ok "scanner(external) -> api:80 is BLOCKED (expected)"
fi

# Check 4: web egress is limited to api + DNS (web -> external/site BLOCKED)
if reach shop web "$SITE_IP"; then
  bad "web -> site(external):80 is allowed, but web egress should only reach api:80 and DNS"
else
  ok "web -> site(external):80 is BLOCKED (expected — web egress is api + DNS only)"
fi

# Check 5: default-deny ingress AND egress policies exist (jq heuristic)
if command -v jq >/dev/null 2>&1; then
  J=$(kubectl -n shop get networkpolicy -o json 2>/dev/null)
  DDI=$(echo "$J" | jq '[.items[] | select((.spec.podSelector // {}) == {}) | select((.spec.policyTypes // []) | index("Ingress")) | select((.spec.ingress // []) | length == 0)] | length' 2>/dev/null)
  DDE=$(echo "$J" | jq '[.items[] | select((.spec.podSelector // {}) == {}) | select((.spec.policyTypes // []) | index("Egress"))  | select((.spec.egress  // []) | length == 0)] | length' 2>/dev/null)
  if [ "${DDI:-0}" -ge 1 ] 2>/dev/null; then ok "default-deny INGRESS policy found"; else bad "no default-deny ingress policy (empty podSelector, Ingress, no rules)"; fi
  if [ "${DDE:-0}" -ge 1 ] 2>/dev/null; then ok "default-deny EGRESS policy found";  else bad "no default-deny egress policy (empty podSelector, Egress, no rules)"; fi
else
  yellow "  [SKIP] default-deny policy checks skipped (jq not available)."
fi

echo
echo "----------------------------------------------------------------------"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "RESULT: $PASS/$TOTAL checks passed. Scenario SOLVED. Strong work — this one's tricky!"
  exit 0
else
  red "RESULT: $PASS/$TOTAL checks passed, $FAIL failing."
  echo "Fix the failures and re-run ./verify.sh. (cat ./solution.sh to reveal.)"
  exit 1
fi
