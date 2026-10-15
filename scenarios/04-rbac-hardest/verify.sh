#!/usr/bin/env bash
# CKS Scenario 04 — verifier. Uses 'kubectl auth can-i --as=...' to test the
# EFFECTIVE permissions of each identity, plus a few structural checks.
# Runs every check and prints a score.

PASS=0; FAIL=0
green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
ok()  { green "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { red   "  [FAIL] $1"; FAIL=$((FAIL+1)); }

REPORTER=system:serviceaccount:finance:reporter
AUDITOR=system:serviceaccount:audit:auditor
CI=system:serviceaccount:finance:ci

# allow/deny <desc> <as> <can-i args...>  — 'can-i --quiet' exits 0 for yes.
allow() { local d=$1 as=$2; shift 2
  if kubectl auth can-i "$@" --as="$as" --quiet 2>/dev/null; then ok "$d"; else bad "$d  (currently DENIED, should be allowed)"; fi; }
deny()  { local d=$1 as=$2; shift 2
  if kubectl auth can-i "$@" --as="$as" --quiet 2>/dev/null; then bad "$d  (currently ALLOWED, should be denied)"; else ok "$d"; fi; }

echo "=== Verifying CKS Scenario 04: RBAC Least Privilege (HARDEST) ==="
echo

for ns in finance payroll audit; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    red "Namespace '$ns' not found. Run ./setup.sh first."; exit 1
  fi
done

echo "PART A — finance/reporter: required access"
allow "reporter can list pods in finance"                    "$REPORTER" list  pods -n finance
allow "reporter can watch pods in finance"                   "$REPORTER" watch pods -n finance
allow "reporter can get pods in finance"                     "$REPORTER" get   pods -n finance
allow "reporter can get pods/log in finance (subresource)"   "$REPORTER" get   pods --subresource=log -n finance
allow "reporter can get configmap/report-config in finance"  "$REPORTER" get   configmap/report-config -n finance

echo
echo "PART A — finance/reporter: everything else denied"
deny  "reporter cannot get configmap/db-config (resourceNames scoping)" "$REPORTER" get    configmap/db-config -n finance
deny  "reporter cannot list configmaps in finance"           "$REPORTER" list   configmaps -n finance
deny  "reporter cannot get secrets in finance"               "$REPORTER" get    secrets -n finance
deny  "reporter cannot delete pods in finance"               "$REPORTER" delete pods -n finance
deny  "reporter cannot exec into pods in finance"            "$REPORTER" create pods --subresource=exec -n finance
deny  "reporter cannot list pods in payroll (legacy binding gone?)" "$REPORTER" list pods -n payroll
deny  "reporter cannot get secrets in payroll"               "$REPORTER" get    secrets -n payroll
deny  "reporter cannot list pods in default"                 "$REPORTER" list   pods -n default
deny  "reporter cannot list pods cluster-wide"               "$REPORTER" list   pods -A
deny  "reporter is not cluster-admin (* on *)"               "$REPORTER" '*' '*'

echo
echo "PART B — audit/auditor"
allow "auditor can list deployments in finance"              "$AUDITOR" list  deployments.apps -n finance
allow "auditor can watch deployments in finance"             "$AUDITOR" watch deployments.apps -n finance
allow "auditor can get deployments in payroll"               "$AUDITOR" get   deployments.apps -n payroll
allow "auditor can list deployments in payroll"              "$AUDITOR" list  deployments.apps -n payroll
allow "auditor can list nodes"                               "$AUDITOR" list  nodes
allow "auditor can get nodes"                                "$AUDITOR" get   nodes
deny  "auditor cannot list deployments in default (not cluster-wide)" "$AUDITOR" list deployments.apps -n default
deny  "auditor cannot list deployments cluster-wide"         "$AUDITOR" list   deployments.apps -A
deny  "auditor cannot delete deployments in finance"         "$AUDITOR" delete deployments.apps -n finance
deny  "auditor cannot get secrets in finance"                "$AUDITOR" get    secrets -n finance
deny  "auditor cannot list pods in finance"                  "$AUDITOR" list   pods -n finance
deny  "auditor cannot delete nodes"                          "$AUDITOR" delete nodes

echo
echo "PART C — nothing else broken"
allow "platform-lead is still cluster-admin"                 platform-lead '*' '*'
allow "ci can still create deployments in finance"           "$CI" create deployments.apps -n finance
allow "ci can still update deployments in finance"           "$CI" update deployments.apps -n finance

echo
echo "Structure — required object names"
RB=$(kubectl -n finance get rolebinding reporter-binding -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
if kubectl -n finance get role reporter-role >/dev/null 2>&1 && [ "$RB" = "Role/reporter-role" ]; then
  ok "Role reporter-role + RoleBinding reporter-binding -> Role/reporter-role in finance"
else
  bad "need Role 'reporter-role' and RoleBinding 'reporter-binding' (roleRef Role/reporter-role) in finance"
fi

RULES=$(kubectl -n finance get role reporter-role -o jsonpath='{.rules[*].apiGroups} {.rules[*].resources} {.rules[*].verbs}' 2>/dev/null)
if [ -n "$RULES" ] && [[ "$RULES" != *'*'* ]]; then
  ok "reporter-role contains no wildcards"
else
  bad "reporter-role is missing or contains '*' wildcards"
fi

for ns in finance payroll; do
  REF=$(kubectl -n "$ns" get rolebinding auditor-deployments -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
  if [ "$REF" = "ClusterRole/deployment-reader" ]; then
    ok "RoleBinding auditor-deployments in $ns -> ClusterRole/deployment-reader"
  else
    bad "need RoleBinding 'auditor-deployments' in $ns with roleRef ClusterRole/deployment-reader (got: ${REF:-missing})"
  fi
done

REF=$(kubectl get clusterrolebinding auditor-nodes -o jsonpath='{.roleRef.kind}/{.roleRef.name}' 2>/dev/null)
if [ "$REF" = "ClusterRole/node-reader" ]; then
  ok "ClusterRoleBinding auditor-nodes -> ClusterRole/node-reader"
else
  bad "need ClusterRoleBinding 'auditor-nodes' with roleRef ClusterRole/node-reader (got: ${REF:-missing})"
fi

if kubectl get clusterrolebinding platform-admins >/dev/null 2>&1; then
  ok "ClusterRoleBinding platform-admins still exists (edited, not deleted)"
else
  bad "ClusterRoleBinding platform-admins was deleted — you should only have removed reporter from its subjects"
fi

echo
echo "----------------------------------------------------------------------"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" -eq 0 ]; then
  green "RESULT: $PASS/$TOTAL checks passed. Scenario SOLVED. Least privilege, exam-grade!"
  exit 0
else
  red "RESULT: $PASS/$TOTAL checks passed, $FAIL failing."
  echo "Fix the failures and re-run ./verify.sh. (cat ./task.md for hints, ./solution.sh to reveal.)"
  exit 1
fi
