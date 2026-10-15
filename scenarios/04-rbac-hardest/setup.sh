#!/usr/bin/env bash
# CKS Scenario 04 — RBAC Least Privilege (HARDEST)
# Domain: Cluster Hardening (15%)
#
# A ServiceAccount has picked up far too much access from several places
# (one of them shared with a legit admin), and a second SA needs carefully
# scoped cross-namespace + cluster-scoped read access. Subresources,
# resourceNames, API groups and Role-vs-ClusterRole scope are all in play.

set -euo pipefail

echo "=== Setting up CKS Scenario 04: RBAC Least Privilege (HARDEST) ==="

# --- Clean slate if re-running (namespaces + cluster-scoped objects) ----------
kubectl delete clusterrolebinding platform-admins auditor-nodes --ignore-not-found >/dev/null 2>&1 || true
kubectl delete clusterrole deployment-reader node-reader --ignore-not-found >/dev/null 2>&1 || true
kubectl delete namespace finance payroll audit --ignore-not-found --wait=true >/dev/null 2>&1 || true

kubectl create namespace finance >/dev/null
kubectl create namespace payroll >/dev/null
kubectl create namespace audit   >/dev/null

# --- Workloads + data to protect ---------------------------------------------
kubectl -n finance create deployment ledger      --image=nginx:alpine >/dev/null
kubectl -n payroll create deployment payroll-api --image=nginx:alpine >/dev/null
kubectl -n finance create configmap report-config --from-literal=format=csv     >/dev/null
kubectl -n finance create configmap db-config     --from-literal=host=db.local  >/dev/null
kubectl -n finance create secret generic db-creds    --from-literal=password='s3cr3t!'   >/dev/null
kubectl -n payroll create secret generic salary-keys --from-literal=key='do-not-leak' >/dev/null

# --- ServiceAccounts ---------------------------------------------------------
kubectl -n finance create serviceaccount reporter >/dev/null
kubectl -n finance create serviceaccount ci       >/dev/null
kubectl -n audit   create serviceaccount auditor  >/dev/null

# --- The mess: existing RBAC -------------------------------------------------
kubectl apply -f - >/dev/null <<'YAML'
# (1) A shared cluster-admin binding. platform-lead legitimately needs it;
#     reporter was "temporarily" added years ago and never removed.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: platform-lead
  - kind: ServiceAccount
    name: reporter
    namespace: finance
---
# (2) A forgotten binding in ANOTHER namespace giving reporter 'edit' there.
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: legacy-reporter
  namespace: payroll
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
  - kind: ServiceAccount
    name: reporter
    namespace: finance
---
# (3) Legit access that must keep working: CI deploys to finance.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ci-deployer
  namespace: finance
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer
  namespace: finance
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ci-deployer
subjects:
  - kind: ServiceAccount
    name: ci
    namespace: finance
YAML

echo
echo "ServiceAccounts:"
kubectl get serviceaccounts -n finance
kubectl get serviceaccounts -n audit

cat <<'TASK'

======================================================================
                              YOUR TASK
======================================================================
Namespaces: finance, payroll, audit

PART A — ServiceAccount finance/reporter
  reporter currently has WAY more access than it should, granted from
  more than one place. Make it least-privilege. Afterwards reporter must
  be able to do EXACTLY this and nothing more:
    - get, list, watch  pods            in 'finance'
    - get               pod logs        in 'finance'
    - get               the ConfigMap 'report-config' in 'finance'
                        (NOT any other ConfigMap, and no listing them)
  Put this in Role 'reporter-role' + RoleBinding 'reporter-binding'
  in 'finance'. Remove ALL of reporter's other access, anywhere in the
  cluster — WITHOUT removing anyone else's access.

PART B — ServiceAccount audit/auditor
  - get, list, watch Deployments in 'finance' AND 'payroll' ONLY
    (not in any other namespace). Use ONE ClusterRole named
    'deployment-reader', bound by a RoleBinding named
    'auditor-deployments' in each of the two namespaces.
  - get, list Nodes. ClusterRole 'node-reader' + ClusterRoleBinding
    'auditor-nodes'.

PART C — Don't break anything
  - User 'platform-lead' must remain cluster-admin.
  - SA finance/ci must still be able to create/update Deployments in
    'finance'.
  - No wildcards ('*') in reporter-role.

Test your work with:
  kubectl auth can-i <verb> <resource> -n <ns> \
    --as=system:serviceaccount:<ns>:<sa>

Hints: cat ./task.md      Reveal: cat ./solution.sh
Verify: bash ./verify.sh   Clean: bash ./cleanup.sh
======================================================================
TASK
