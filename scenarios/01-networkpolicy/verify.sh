#!/usr/bin/env bash
# CKS Scenario 01 — verifier. Runs functional + policy checks and reports pass/fail.
# Does NOT exit on first failure; it runs every check and prints a score.

NS=prod
PASS=0
FAIL=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }

ok()   { green  "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { red    "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== Verifying CKS Scenario 01: NetworkPolicy ==="
echo

# --- Preconditions -----------------------------------------------------------
if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  red "Namespace '$NS' not found. Run ./setup.sh first."
  exit 1
fi

DB_IP=$(kubectl -n "$NS" get pod db -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [ -z "$DB_IP" ]; then
  red "Could not find db pod IP. Is the db pod running? Run ./setup.sh first."
  exit 1
fi

# curl helper: returns 0 if HTTP reachable within timeout, non-zero otherwise.
reach() { # $1 = pod name
  kubectl -n "$NS" exec "$1" -- curl -s -o /dev/null -m 4 "http://$DB_IP:80" >/dev/null 2>&1
}

echo "Running connectivity checks against db ($DB_IP:80)..."
echo

# --- Check 1: api CAN reach db ----------------------------------------------
if reach api; then
  ok "api -> db:80 is ALLOWED (expected)"
else
  bad "api -> db:80 is blocked, but it should be allowed"
fi

# --- Check 2: attacker CANNOT reach db --------------------------------------
if reach attacker; then
  bad "attacker -> db:80 is allowed, but it should be BLOCKED"
else
  ok "attacker -> db:80 is BLOCKED (expected)"
fi

# --- Check 3: a default-deny ingress policy exists --------------------------
# Heuristic: a NetworkPolicy in prod with an empty podSelector (selects all
# pods) whose policyTypes includes Ingress and which has no ingress rules.
DD="unknown"
if command -v jq >/dev/null 2>&1; then
  COUNT=$(kubectl -n "$NS" get networkpolicy -o json 2>/dev/null | jq '
    [ .items[]
      | select((.spec.podSelector // {}) == {})
      | select(.spec.policyTypes // [] | index("Ingress"))
      | select((.spec.ingress // []) | length == 0)
    ] | length' 2>/dev/null)
  if [ "${COUNT:-0}" -ge 1 ] 2>/dev/null; then DD="yes"; else DD="no"; fi
fi

if [ "$DD" = "unknown" ]; then
  yellow "  [SKIP] default-deny policy check skipped (jq not available)."
elif [ "$DD" = "yes" ]; then
  ok "default-deny ingress policy found (empty podSelector, no ingress rules)"
else
  yellow "  [WARN] No obvious default-deny policy found."
  yellow "         Connectivity may still pass if your allow-policy is narrow,"
  yellow "         but best practice (and the task) wants an explicit default-deny."
  FAIL=$((FAIL+1))
fi

# --- Result ------------------------------------------------------------------
echo
echo "----------------------------------------------------------------------"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "RESULT: $PASS/$TOTAL checks passed. Scenario SOLVED. Nice work!"
  exit 0
else
  red "RESULT: $PASS/$TOTAL checks passed, $FAIL failing."
  echo "Fix the failing checks and run ./verify.sh again. (cat ./solution.sh to reveal.)"
  exit 1
fi
