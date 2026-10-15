#!/usr/bin/env bash
# CKS Scenario 03 — verifier. Runs all checks, prints pass/fail + score.

PASS=0; FAIL=0
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
ok()  { green "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { red   "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== Verifying CKS Scenario 03: NetworkPolicy (HARDEST) ==="
echo

if ! kubectl get ns secure >/dev/null 2>&1; then
  red "Namespace 'secure' not found. Run ./setup.sh first."; exit 1
fi

PAY_IP=$(kubectl -n secure get pod payments -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [ -z "$PAY_IP" ]; then
  red "Could not find payments pod IP. Run ./setup.sh first."; exit 1
fi

# Preflight: every pod used below must be Running, otherwise a failed exec
# would be miscounted as "BLOCKED".
for p in secure/payments secure/gateway secure/worker dev/gateway monitoring/probe; do
  PHASE=$(kubectl -n "${p%/*}" get pod "${p#*/}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$PHASE" != "Running" ]; then
    red "Pod '$p' is not Running (phase: ${PHASE:-missing}). Run ./setup.sh first."; exit 1
  fi
done
# Target must actually serve on :80 (localhost is never affected by NetworkPolicy).
if ! kubectl -n secure exec payments -- wget -q -O /dev/null -T 4 http://127.0.0.1:80 >/dev/null 2>&1; then
  red "nginx in payments isn't serving on :80, so BLOCKED checks would be meaningless. Re-run ./setup.sh."; exit 1
fi

# reach <ns> <pod> -> payments:80 (by IP, to isolate L3/L4 from DNS)
reach() { kubectl -n "$1" exec "$2" -- curl -s -o /dev/null -m 4 "http://$PAY_IP:80" >/dev/null 2>&1; }

# The worker check needs worker's EGRESS open: default-deny egress would
# otherwise block worker on its own side and hide a leaky payments ingress
# policy. verify.sh adds a temporary allow-all-egress policy for worker during
# that one check and always removes it (trap on exit).
TMP_NP=verify-tmp-worker-egress
remove_tmp_np() { kubectl -n secure delete networkpolicy "$TMP_NP" --ignore-not-found >/dev/null 2>&1; }
trap remove_tmp_np EXIT

echo "Connectivity target: secure/payments $PAY_IP:80"
echo

# Allowed sources
if reach secure gateway; then ok "secure/gateway -> payments:80 ALLOWED (expected)"
else bad "secure/gateway -> payments:80 blocked — needs payments ingress AND gateway egress+DNS"; fi

if reach monitoring probe; then ok "monitoring/probe -> payments:80 ALLOWED (expected)"
else bad "monitoring/probe -> payments:80 blocked — allow ingress from the monitoring namespace"; fi

# Blocked sources (the AND/OR trap)
if reach dev gateway; then
  bad "dev/gateway -> payments:80 ALLOWED — LEAK! Your selectors are OR'd; namespaceSelector+podSelector must be AND'd in ONE 'from' item."
else
  ok "dev/gateway -> payments:80 BLOCKED (expected — decoy with wrong namespace)"
fi

kubectl apply -f - >/dev/null <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${TMP_NP}
  namespace: secure
spec:
  podSelector:
    matchLabels:
      app: worker
  policyTypes:
    - Egress
  egress:
    - {}
YAML
sleep 3   # let the CNI program the temporary rule

if reach secure worker; then
  bad "secure/worker -> payments:80 ALLOWED — LEAK! payments ingress lets in a same-namespace pod without app=gateway (selectors OR'd instead of AND'd?)."
else
  ok "secure/worker -> payments:80 BLOCKED by payments ingress (expected — wrong label)"
fi
remove_tmp_np

# DNS from gateway (egress trap)
if kubectl -n secure exec gateway -- nslookup payments.secure.svc.cluster.local >/dev/null 2>&1; then
  ok "secure/gateway can resolve DNS (egress to kube-system:53 is open)"
else
  bad "secure/gateway CANNOT resolve DNS — default-deny egress broke it. Allow egress to kube-system UDP+TCP 53."
fi

# default-deny ingress AND egress exist
if command -v jq >/dev/null 2>&1; then
  J=$(kubectl -n secure get networkpolicy -o json 2>/dev/null)
  DDI=$(echo "$J" | jq '[.items[] | select((.spec.podSelector // {}) == {}) | select((.spec.policyTypes // []) | index("Ingress")) | select((.spec.ingress // []) | length == 0)] | length' 2>/dev/null)
  DDE=$(echo "$J" | jq '[.items[] | select((.spec.podSelector // {}) == {}) | select((.spec.policyTypes // []) | index("Egress"))  | select((.spec.egress  // []) | length == 0)] | length' 2>/dev/null)
  if [ "${DDI:-0}" -ge 1 ] 2>/dev/null; then ok "default-deny INGRESS policy found"; else bad "no default-deny ingress policy"; fi
  if [ "${DDE:-0}" -ge 1 ] 2>/dev/null; then ok "default-deny EGRESS policy found";  else bad "no default-deny egress policy"; fi
else
  yellow "  [SKIP] default-deny policy checks skipped (jq not available)."
fi

echo
echo "----------------------------------------------------------------------"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "RESULT: $PASS/$TOTAL checks passed. Scenario SOLVED. That's exam-grade — well done!"
  exit 0
else
  red "RESULT: $PASS/$TOTAL checks passed, $FAIL failing."
  echo "Fix the failures and re-run ./verify.sh. (cat ./solution.sh to reveal.)"
  exit 1
fi
