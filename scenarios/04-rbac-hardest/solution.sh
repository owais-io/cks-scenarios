#!/usr/bin/env bash
# CKS Scenario 04 — reference solution. Read it, or run it to auto-apply.
set -euo pipefail

cat <<'EOF'
Applying reference solution:
  1) Find ALL of reporter's bindings:
       kubectl get rolebindings,clusterrolebindings -A -o wide | grep reporter
  2) platform-admins (cluster-admin) is SHARED with platform-lead ->
       remove only the reporter subject (kubectl edit), don't delete it
  3) payroll/legacy-reporter (edit) -> delete it
  4) reporter-role: pods get/list/watch, pods/log get,
       configmaps get with resourceNames [report-config]  (3 separate rules)
  5) deployment-reader ClusterRole (apiGroup "apps") + a RoleBinding in
       finance AND payroll (NOT a ClusterRoleBinding)
  6) node-reader ClusterRole + ClusterRoleBinding (nodes are cluster-scoped)
EOF

# --- Remove reporter's excess access -----------------------------------------
# In the exam you'd 'kubectl edit clusterrolebinding platform-admins' and delete
# the reporter subject. Here we remove whichever subject index is reporter.
IDX=$(kubectl get clusterrolebinding platform-admins \
  -o jsonpath='{range .subjects[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}' \
  | grep -n '^ServiceAccount/finance/reporter$' | cut -d: -f1 || true)
if [ -n "$IDX" ]; then
  kubectl patch clusterrolebinding platform-admins --type=json \
    -p "[{\"op\":\"remove\",\"path\":\"/subjects/$((IDX-1))\"}]"
fi

kubectl -n payroll delete rolebinding legacy-reporter --ignore-not-found

# --- PART A: reporter least privilege -----------------------------------------
# Note: 'kubectl create role --resource-name=...' would apply the name
# restriction to EVERY resource in the command, so write YAML with 3 rules.
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: reporter-role
  namespace: finance
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  # pods/log is a SUBRESOURCE: "pods" alone does NOT grant it
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  # resourceNames only works with verbs that name an object (get/update/...);
  # it can't restrict list/watch, so only 'get' here
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["report-config"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reporter-binding
  namespace: finance
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reporter-role
subjects:
  - kind: ServiceAccount
    name: reporter
    namespace: finance
YAML

# --- PART B: auditor ----------------------------------------------------------
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployment-reader
rules:
  - apiGroups: ["apps"]          # deployments are NOT in the core ("") group
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
---
# ClusterRole + RoleBinding = the ClusterRole's rules, granted ONLY in this ns
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-deployments
  namespace: finance
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deployment-reader
subjects:
  - kind: ServiceAccount
    name: auditor
    namespace: audit
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-deployments
  namespace: payroll
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: deployment-reader
subjects:
  - kind: ServiceAccount
    name: auditor
    namespace: audit
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list"]
---
# Nodes are cluster-scoped -> a RoleBinding can't grant them; needs a CRB
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: auditor-nodes
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: node-reader
subjects:
  - kind: ServiceAccount
    name: auditor
    namespace: audit
YAML

echo "Done. Now run: bash ./verify.sh"
